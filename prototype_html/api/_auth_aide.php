<?php
/* =============================================================================
 * SIGH-CNT : aides de l'authentification (utilisées par `auth.php` seulement)
 * -----------------------------------------------------------------------------
 * Ce fichier porte ce qui croise le COMPTE DE CONNEXION (table `utilisateurs`,
 * haché du mot de passe) et la FICHE de la collection `utilisateurs` du magasin
 * (celle que l'écran m14-utilisateurs écrit : statut, actif, rôle, double
 * facteur, réinitialisation imposée), plus la matrice des rôles (collection
 * `rbac`), les échecs de connexion et le jeton de changement de mot de passe.
 *
 * Aucun secret n'est écrit ici : ni en clair, ni dans un journal.
 * ========================================================================== */

require_once __DIR__ . '/_commun.php';

/** Échecs tolérés avant verrou, et durée de la fenêtre (CDCT §12.2). */
const SIGH_ECHECS_MAX      = 5;
const SIGH_ECHECS_FENETRE  = 15; /* minutes */
const SIGH_CHANGEMENT_TTL  = 15; /* minutes de validité du jeton de changement */
const SIGH_MDP_MIN         = 8;

/** Rôles autorisés à créer un compte et à lever un verrou, vérifiés SUR LA SESSION. */
const SIGH_ROLES_GESTION_COMPTES = ['admin', 'da'];

/** Fonction (capacités métier) rattachée à un rôle à la création d'un compte. */
const SIGH_FONCTION_DU_ROLE = [
    'admin' => 'direction', 'da' => 'direction', 'direction' => 'direction',
    'dm' => 'medecin', 'medecin' => 'medecin', 'chirurgien' => 'medecin',
    'anesthesiste' => 'medecin', 'echographiste' => 'medecin',
    'infirmier' => 'infirmier', 'surveillant' => 'infirmier', 'aide_soignant' => 'aide_soignant',
    'laborantin' => 'tsl', 'stock' => 'stock',
    'comptable' => 'comptable', 'assistant_comptable' => 'comptable', 'aide_comptable' => 'comptable',
    'caissier' => 'caissiere', 'reception' => 'accueil',
];

/** Schéma propre à l'authentification, créé à la demande et rejouable. */
function sigh_auth_installer(PDO $pdo): void
{
    if (sigh_est_postgres()) {
        $pdo->exec('CREATE TABLE IF NOT EXISTS echecs_connexion (
            id          BIGSERIAL PRIMARY KEY,
            identifiant VARCHAR(64) NOT NULL,
            quand       TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
        )');
        $pdo->exec('CREATE TABLE IF NOT EXISTS changements_requis (
            jeton       VARCHAR(64) PRIMARY KEY,
            identifiant VARCHAR(64) NOT NULL,
            cree_le     TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
        )');
        $pdo->exec('ALTER TABLE utilisateurs ADD COLUMN IF NOT EXISTS mdp_change_le TIMESTAMP');
        return;
    }
    $pdo->exec('CREATE TABLE IF NOT EXISTS echecs_connexion (
        id          BIGINT AUTO_INCREMENT PRIMARY KEY,
        identifiant VARCHAR(64) NOT NULL,
        quand       DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4');
    $pdo->exec('CREATE TABLE IF NOT EXISTS changements_requis (
        jeton       VARCHAR(64) NOT NULL PRIMARY KEY,
        identifiant VARCHAR(64) NOT NULL,
        cree_le     DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4');
    try {
        $pdo->exec('ALTER TABLE utilisateurs ADD COLUMN mdp_change_le DATETIME NULL');
    } catch (Throwable $e) { /* colonne déjà présente */ }
}

/** Fragment SQL « il y a N minutes », sans paramètre lié. */
function sigh_il_y_a_minutes(int $n): string
{
    return sigh_est_postgres()
        ? "(CURRENT_TIMESTAMP - INTERVAL '" . $n . " minutes')"
        : 'DATE_SUB(CURRENT_TIMESTAMP, INTERVAL ' . $n . ' MINUTE)';
}

/** Une collection du magasin, sous forme de tableau (vide si absente). */
function sigh_lire_collection(PDO $pdo, string $nom): array
{
    $q = $pdo->prepare('SELECT donnees FROM collections WHERE nom = ?');
    $q->execute([$nom]);
    $brut = $q->fetchColumn();
    $fiches = is_string($brut) ? json_decode($brut, true) : $brut;
    return is_array($fiches) ? $fiches : [];
}

/**
 * La fiche de la collection `utilisateurs` qui correspond à l'identifiant.
 * Plusieurs fiches peuvent le porter : une fiche non archivée est préférée,
 * la première dans l'ordre du magasin l'emporte. Null si aucune fiche ne
 * correspond : le COMPTE DE LA TABLE reste alors seule autorité.
 */
function sigh_fiche_compte(PDO $pdo, string $identifiant): ?array
{
    $cle = mb_strtolower($identifiant);
    $trouvee = null;
    foreach (sigh_lire_collection($pdo, 'utilisateurs') as $f) {
        if (!is_array($f) || mb_strtolower((string) ($f['identifiant'] ?? '')) !== $cle) {
            continue;
        }
        if (($f['statut'] ?? 'actif') !== 'archive') {
            return $f;
        }
        $trouvee = $trouvee ?? $f;
    }
    return $trouvee;
}

/** Une fiche ferme-t-elle le compte ? (archivée ou désactivée à l'écran). */
function sigh_fiche_inactive(?array $fiche): bool
{
    if ($fiche === null) {
        return false;
    }
    return ($fiche['statut'] ?? 'actif') === 'archive' || (array_key_exists('actif', $fiche) && $fiche['actif'] === false);
}

/**
 * Le rôle est-il archivé dans la matrice (collection `rbac`) ?
 * Même règle que `surcharges()` de nav.js : plusieurs fiches fusionnent champ
 * par champ, la dernière qui définit `statut` l'emporte.
 */
function sigh_role_archive(PDO $pdo, string $role): bool
{
    $statut = null;
    foreach (sigh_lire_collection($pdo, 'rbac') as $f) {
        if (is_array($f) && ($f['role'] ?? null) === $role && isset($f['statut'])) {
            $statut = $f['statut'];
        }
    }
    return $statut === 'archive';
}

/** Une tentative refusée, écrite dans `tentativesConnexion` (jamais le mot de passe). */
function sigh_tentative(PDO $pdo, string $identifiant, ?array $u, string $motif): void
{
    sigh_ajouter_fiche($pdo, 'tentativesConnexion', [
        'id'          => sigh_uid('TNT'),
        'identifiant' => $identifiant,
        'nom'         => $u['nom'] ?? $identifiant,
        'role'        => $u['role'] ?? 'inconnu',
        'motif'       => $motif,
        'horodatage'  => date('c'),
        'poste'       => 'Écran de connexion',
        'traitee'     => false,
        'statut'      => 'actif',
    ], 200);
}

function sigh_nb_echecs(PDO $pdo, string $identifiant): int
{
    $q = $pdo->prepare('SELECT COUNT(*) FROM echecs_connexion WHERE identifiant = ? AND quand > ' . sigh_il_y_a_minutes(SIGH_ECHECS_FENETRE));
    $q->execute([mb_strtolower($identifiant)]);
    return (int) $q->fetchColumn();
}

function sigh_compter_echec(PDO $pdo, string $identifiant): void
{
    $pdo->prepare('INSERT INTO echecs_connexion (identifiant) VALUES (?)')->execute([mb_strtolower($identifiant)]);
    /* La table ne grossit pas sans fin : au-delà de la fenêtre, une ligne ne sert plus. */
    $pdo->exec('DELETE FROM echecs_connexion WHERE quand < ' . sigh_il_y_a_minutes(SIGH_ECHECS_FENETRE * 4));
}

function sigh_effacer_echecs(PDO $pdo, string $identifiant): void
{
    $pdo->prepare('DELETE FROM echecs_connexion WHERE identifiant = ?')->execute([mb_strtolower($identifiant)]);
}

/** Le compte (table) est-il tenu de changer son mot de passe ? */
function sigh_doit_changer(array $u, ?array $fiche): bool
{
    /* Banc d'essai uniquement : les comptes de démonstration d'origine, jamais
       modifiés, ne sont pas contraints, sans quoi aucun scénario ne pourrait
       ouvrir de session. Un compte créé par `creer_compte` l'est toujours. */
    $banc = getenv('SIGH_BANC') === '1';
    $origine = false;
    foreach (SIGH_COMPTES_ORIGINE as $c) {
        if ($c[0] === $u['identifiant']) {
            $origine = true;
            break;
        }
    }
    $modifie = !empty($u['mdp_change_le']);
    if ((bool) $u['doit_changer'] && !($banc && $origine && !$modifie)) {
        return true;
    }
    /* Réinitialisation imposée à l'écran « Sécurité des utilisateurs » : elle ne
       vaut que si elle est POSTÉRIEURE au dernier changement fait ici, sinon
       une copie périmée du magasin d'un poste forcerait le changement sans fin. */
    if ($fiche !== null && ($fiche['doitChangerMotDePasse'] ?? false) === true && !empty($fiche['reinitialisationImposeeLe'])) {
        if (!$modifie) {
            return true;
        }
        $imposee = strtotime((string) $fiche['reinitialisationImposeeLe']);
        $change = strtotime((string) $u['mdp_change_le'] . ' UTC');
        return $imposee !== false && $change !== false && $imposee > $change;
    }
    return false;
}

/** Le rôle de la SESSION est celui de la TABLE, jamais celui de la fiche.
 *  La collection `utilisateurs` vit dans le magasin que tout poste connecté peut écrire : lui faire confiance pour le rôle ouvrirait une
 *  élévation de privilège (un agent éditerait sa propre fiche en « admin » et l'obtiendrait à la connexion suivante). La fiche ne sait donc
 *  que RESTREINDRE (archivée, inactive, bloquée, réinitialisation imposée) ; un changement de rôle voulu par l'administrateur doit passer par
 *  une action serveur réservée à admin (suite à faire : `changer_role`). */
function sigh_role_de_session(array $u, ?array $fiche): string
{
    return (string) $u['role'];
}

/** Session de la forme attendue par `sigh_journaliser`, pour un compte sans jeton. */
function sigh_session_fictive(array $u, string $role): array
{
    return ['jeton' => '', 'identifiant' => $u['identifiant'], 'nom' => $u['nom'], 'role' => $role,
        'fonction' => $u['fonction'], 'secteur' => $u['secteur']];
}

/** Ouvre la session serveur d'un compte et rend le jeton (engendré ici, jamais par le client). */
function sigh_ouvrir_session(PDO $pdo, array $u, string $role, string $poste): string
{
    $jeton = bin2hex(random_bytes(24));
    $pdo->prepare('INSERT INTO sessions_poste (jeton, identifiant, nom, role, fonction, secteur, poste)
                   VALUES (?, ?, ?, ?, ?, ?, ?)')
        ->execute([$jeton, $u['identifiant'], $u['nom'], $role, $u['fonction'], $u['secteur'], $poste]);
    $pdo->prepare('UPDATE utilisateurs SET vu_le = CURRENT_TIMESTAMP WHERE identifiant = ?')->execute([$u['identifiant']]);
    return $jeton;
}

/** Retire de la fiche du magasin le marquage « changement imposé » (id de fiche, pas d'identifiant). */
function sigh_lever_marquage_fiche(PDO $pdo, ?array $fiche): void
{
    if ($fiche === null || empty($fiche['id'])) {
        return;
    }
    sigh_modifier_fiche($pdo, 'utilisateurs', (string) $fiche['id'], [
        'doitChangerMotDePasse' => false,
        'motDePasseDefiniLe'    => date('c'),
    ]);
}
