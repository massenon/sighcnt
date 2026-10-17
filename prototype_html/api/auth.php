<?php
/* =============================================================================
 * SIGH-CNT — Authentification
 * -----------------------------------------------------------------------------
 * CE QUE CE FICHIER REMPLACE. La page de connexion portait la liste des comptes
 * EN DUR et ne vérifiait AUCUN mot de passe : elle contrôlait que les deux
 * champs n'étaient pas vides, puis ouvrait la session avec le rôle choisi dans
 * une liste déroulante. Autant dire qu'il n'y avait pas d'authentification.
 *
 * Désormais : les comptes vivent dans la table `utilisateurs`, le mot de passe
 * y est HACHÉ (`password_hash`), et c'est le SERVEUR qui engendre le jeton de
 * session. Un client ne peut ni choisir son jeton, ni se déclarer d'un autre
 * rôle que celui que la base lui reconnaît.
 *
 * Actions :
 *   POST {action:'connexion', identifiant, motDePasse}  → jeton + profil
 *   POST {action:'deconnexion'}                          → ferme la session
 *   GET  ?action=moi          (en-tête X-Sigh-Jeton)     → la session en cours
 *   GET  ?action=comptes                                 → la liste des postes
 * ========================================================================== */

require_once __DIR__ . '/_commun.php';

/* --------------------------------------------------------------------------
 * LES COMPTES D'ORIGINE.
 * C'est une MIGRATION : elle ne s'exécute que si la table est vide. Les noms
 * viennent des quatorze comptes nommés par la Direction le 25/08/2026 et des
 * rôles créés depuis. « Compte à pourvoir » n'est pas un oubli : anesthésiste
 * et assistant comptable ne sont nommés par AUCUN document, et inventer un nom
 * d'agent serait la même faute qu'inventer un numéro d'urgence.
 * ------------------------------------------------------------------------ */
const SIGH_COMPTES_ORIGINE = [
    ['c.bassongui',          'BASSONGUI Chabi Séko',                          'admin',               'direction',     'ADM'],
    ['a.taki',               'TAKI Alimatou',                                 'da',                  'direction',     'ADM'],
    ['f.yeni',               'YENI M’PO Florent',                             'medecin',             'medecin',       'MGE'],
    ['z.badobani',           'BADO BANI A. B. Zoulehath',                     'infirmier',           'sage_femme',    'MAT'],
    ['y.garba',              'GARBA Yahouza',                                 'infirmier',           'infirmier',     'SUR'],
    ['s.tepa',               'TEPA Séraphine',                                'aide_soignant',       'aide_soignant', 'HOS'],
    ['a.kinnou',             'KINNOU Addoul Ganiou',                          'laborantin',          'tsl',           'LAB'],
    ['z.maman',              'MAMAN Zoukanéri',                               'stock',               'stock',         'ADM'],
    ['a.kassa',              'KASSA Augustin',                                'comptable',           'comptable',     'ADM'],
    ['a.dieyabidi',          'DIEYABIDI Aïssatou — Dispensaire (Pharmacie)',  'caissier',            'caissiere',     'CPH'],
    ['e.orouyo',             'OROU YO Edmond',                                'reception',           'accueil',       'ACC'],
    ['r.ahohou',             'AHOHOU Rodrigue',                               'echographiste',       'medecin',       'IMG'],
    ['y.garba.sur',          'GARBA Yahouza — Surveillant',                   'surveillant',         'infirmier',     'SUR'],
    ['h.gbedji',             'GBEDJI Hervé — Assistant de Direction',         'assistant_comptable', 'comptable',     'ADM'],
    ['c.bassongui.chi',      'BASSONGUI Chabi Séko — Chirurgien',             'chirurgien',          'medecin',       'CHI'],
    ['demo.anesthesiste',    'Compte à pourvoir (démonstration)',             'anesthesiste',        'medecin',       'CHI'],
    ['demo.assist-comptable','Compte à pourvoir (démonstration)',             'aide_comptable',      'comptable',     'ADM'],
];

/** Mot de passe d'origine, à changer à la première connexion réelle. */
const SIGH_MDP_ORIGINE = 'demonstration';

function sigh_semer_comptes(PDO $pdo): void
{
    sigh_installer_comptes($pdo);
    $n = (int) $pdo->query('SELECT COUNT(*) FROM utilisateurs')->fetchColumn();
    if ($n > 0) {
        return;
    }
    $hash = password_hash(SIGH_MDP_ORIGINE, PASSWORD_DEFAULT);
    $q = $pdo->prepare('INSERT INTO utilisateurs (identifiant, nom, role, fonction, secteur, mdp, doit_changer)
                        VALUES (?, ?, ?, ?, ?, ?, ' . (sigh_est_postgres() ? 'TRUE' : '1') . ')');
    foreach (SIGH_COMPTES_ORIGINE as $c) {
        $q->execute([$c[0], $c[1], $c[2], $c[3], $c[4], $hash]);
    }
}

$pdo = null;
try {
    $pdo = sigh_pdo();
    sigh_installer($pdo);
    sigh_semer_comptes($pdo);
} catch (Throwable $e) {
    sigh_repondre([
        'erreur' => 'base indisponible',
        'detail' => 'Connexion perdue avec le serveur de base de données.',
        'cause'  => $e->getMessage(),
    ], 503);
}

$methode = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$corps   = $methode === 'POST' ? sigh_corps() : [];
$action  = (string) ($corps['action'] ?? $_GET['action'] ?? '');

/* --- La liste des postes, pour le sélecteur de l'écran de connexion -------
   Elle ne porte NI mot de passe NI jeton : c'est un annuaire, pas une clé. */
if ($action === 'comptes') {
    $q = $pdo->query('SELECT identifiant, nom, role, fonction, secteur, statut
                        FROM utilisateurs WHERE statut = \'actif\' ORDER BY nom');
    sigh_repondre(['comptes' => $q->fetchAll()]);
}

/* --- La session en cours -------------------------------------------------- */
if ($action === 'moi') {
    $s = sigh_session($pdo, $corps);
    if ($s === null) {
        sigh_repondre(['erreur' => 'session absente'], 401);
    }
    sigh_repondre(['session' => [
        'jeton'       => $s['jeton'],
        'identifiant' => $s['identifiant'],
        'nom'         => $s['nom'],
        'role'        => $s['role'],
        'fonction'    => $s['fonction'],
        'secteur'     => $s['secteur'],
        'poste'       => $s['poste'],
    ]]);
}

/* --- Fermeture ------------------------------------------------------------ */
if ($action === 'deconnexion') {
    $s = sigh_session($pdo, $corps);
    if ($s !== null) {
        $pdo->prepare('DELETE FROM sessions_poste WHERE jeton = ?')->execute([$s['jeton']]);
    }
    sigh_repondre(['ferme' => true]);
}

/* --- Connexion ------------------------------------------------------------ */
if ($action === 'connexion') {
    $identifiant = trim((string) ($corps['identifiant'] ?? ''));
    $motDePasse  = (string) ($corps['motDePasse'] ?? '');

    if ($identifiant === '' || $motDePasse === '') {
        sigh_repondre([
            'erreur' => 'identifiants incomplets',
            'detail' => 'Identifiant et mot de passe sont obligatoires.',
        ], 400);
    }

    $q = $pdo->prepare('SELECT * FROM utilisateurs WHERE identifiant = ?');
    $q->execute([$identifiant]);
    $u = $q->fetch();

    /* UN REFUS NE DIT PAS CE QUI MANQUE. « Identifiant inconnu » et « mot de
       passe erroné » distingués, c'est un annuaire offert à qui essaie : on
       répond la même chose aux deux. La tentative, elle, est journalisée. */
    if (!$u || !password_verify($motDePasse, $u['mdp'])) {
        sigh_ajouter_fiche($pdo, 'tentativesConnexion', [
            'id'          => sigh_uid('TNT'),
            'identifiant' => $identifiant,
            'nom'         => $u['nom'] ?? $identifiant,
            'role'        => $u['role'] ?? '—',
            'motif'       => $u ? 'Mot de passe erroné' : 'Identifiant inconnu',
            'horodatage'  => date('c'),
            'poste'       => 'Écran de connexion',
            'traitee'     => false,
            'statut'      => 'actif',
        ], 200);
        sigh_repondre([
            'erreur' => 'identifiants refusés',
            'detail' => 'Identifiant ou mot de passe incorrect.',
        ], 401);
    }

    if (($u['statut'] ?? 'actif') !== 'actif') {
        sigh_ajouter_fiche($pdo, 'tentativesConnexion', [
            'id'          => sigh_uid('TNT'),
            'identifiant' => $identifiant,
            'nom'         => $u['nom'],
            'role'        => $u['role'],
            'motif'       => 'Compte archivé — accès retiré par l’administrateur',
            'horodatage'  => date('c'),
            'poste'       => 'Écran de connexion',
            'traitee'     => false,
            'statut'      => 'actif',
        ], 200);
        sigh_repondre([
            'erreur' => 'compte fermé',
            'detail' => 'Ce compte a été archivé : il n’ouvre plus de session (RG-14).',
        ], 403);
    }

    /* LE JETON EST ENGENDRÉ ICI, ET NULLE PART AILLEURS. */
    $jeton = bin2hex(random_bytes(24));
    $pdo->prepare('INSERT INTO sessions_poste (jeton, identifiant, nom, role, fonction, secteur, poste)
                   VALUES (?, ?, ?, ?, ?, ?, ?)')
        ->execute([$jeton, $u['identifiant'], $u['nom'], $u['role'], $u['fonction'], $u['secteur'],
            (string) ($corps['poste'] ?? '')]);
    $pdo->prepare('UPDATE utilisateurs SET vu_le = CURRENT_TIMESTAMP WHERE identifiant = ?')
        ->execute([$u['identifiant']]);

    $session = [
        'jeton' => $jeton, 'identifiant' => $u['identifiant'], 'nom' => $u['nom'],
        'role' => $u['role'], 'fonction' => $u['fonction'], 'secteur' => $u['secteur'],
    ];
    sigh_journaliser($pdo, $session, 'Connexion', 'sessions', $u['identifiant'], null,
        ['role' => $u['role']]);

    sigh_repondre([
        'jeton'       => $jeton,
        'utilisateur' => [
            'identifiant' => $u['identifiant'],
            'nom'         => $u['nom'],
            'role'        => $u['role'],
            'fonction'    => $u['fonction'],
            'secteur'     => $u['secteur'],
            'doitChanger' => (bool) $u['doit_changer'],
        ],
    ]);
}

sigh_repondre(['erreur' => 'action inconnue',
    'detail' => 'Actions acceptées : connexion, deconnexion, moi, comptes.'], 400);
