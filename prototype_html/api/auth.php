<?php
/* =============================================================================
 * SIGH-CNT : Authentification
 * -----------------------------------------------------------------------------
 * SOURCE D'AUTORITÉ DE LA CONNEXION (décision du 07/11/2026).
 *   - Le COMPTE DE CONNEXION vit en table `utilisateurs` : identifiant, haché du
 *     mot de passe (`password_hash`, bcrypt par défaut de PHP), état, obligation
 *     de changer. Jamais de mot de passe en clair, ni ici ni dans une fiche ni
 *     dans le journal.
 *   - La FICHE de la collection `utilisateurs` du magasin (écran m14-utilisateurs
 *     et « Sécurité des utilisateurs ») est CROISÉE à chaque connexion, par
 *     l'identifiant : compte archivé ou désactivé, compte bloqué, rôle de la
 *     fiche, réinitialisation imposée. Sans fiche correspondante, la table seule
 *     fait foi. Le RÔLE DE LA SESSION est celui de la TABLE (jamais celui que le
 *     client annonce, jamais celui de la fiche : la collection est écrite par les
 *     postes, lui faire confiance serait une élévation de privilège). La fiche ne
 *     fait que RESTREINDRE.
 *   - Le rôle archivé dans la matrice (`rbac`) ferme la connexion.
 *   - Double facteur : la réponse porte `mfa` (fiche), AUCUN second facteur n'est
 *     encore vérifié par le serveur de la maquette.
 *
 * Actions :
 *   POST {action:'connexion', identifiant, motDePasse}
 *        -> jeton + profil, ou refus nommé (`code`) :
 *           IDENTIFIANTS_REFUSES 401 (inconnu OU mot de passe faux, même réponse),
 *           COMPTE_INACTIF 403, ROLE_ARCHIVE 403, COMPTE_BLOQUE 423,
 *           COMPTE_VERROUILLE 423 (5 échecs en 15 minutes sur l'identifiant),
 *           CHANGEMENT_REQUIS 200 sans `jeton` : un `jetonChangement` à usage
 *           unique ne sert qu'à `changer_mot_de_passe`, aucune session n'existe
 *           tant que le mot de passe provisoire n'est pas remplacé.
 *   POST {action:'changer_mot_de_passe', ancienMotDePasse, nouveauMotDePasse}
 *        (session OU jetonChangement) -> lève l'obligation, ouvre la session
 *   POST {action:'creer_compte', identifiant, nom, role, motDePasse}
 *        (session admin ou da) -> compte haché, `doitChanger` vrai
 *   POST {action:'deverrouiller', identifiant}   (session admin ou da)
 *   POST {action:'deconnexion'}                          -> ferme la session
 *   GET  ?action=moi          (en-tête X-Sigh-Jeton)     -> la session en cours
 *   GET  ?action=comptes                                 -> la liste des postes
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

require_once __DIR__ . '/_auth_aide.php';

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
    sigh_auth_installer($pdo);
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

    /* LE VERROU PASSE AVANT TOUT : cinq échecs en quinze minutes sur le même
       identifiant, connu ou non (sans cela, le verrou révélerait les comptes
       qui existent). Une tentative faite pendant le verrou ne le prolonge pas :
       il se lève par le temps, ou par l'administrateur (`deverrouiller`). */
    if (sigh_nb_echecs($pdo, $identifiant) >= SIGH_ECHECS_MAX) {
        sigh_tentative($pdo, $identifiant, null, 'Compte verrouillé : ' . SIGH_ECHECS_MAX . ' échecs en ' . SIGH_ECHECS_FENETRE . ' minutes');
        sigh_repondre([
            'erreur' => 'compte verrouillé', 'code' => 'COMPTE_VERROUILLE',
            'detail' => 'Trop d’échecs de connexion sur cet identifiant. Réessayer dans ' . SIGH_ECHECS_FENETRE
                      . ' minutes, ou demander son déblocage à l’administrateur.',
        ], 423);
    }

    $q = $pdo->prepare('SELECT * FROM utilisateurs WHERE identifiant = ?');
    $q->execute([$identifiant]);
    $u = $q->fetch();

    /* UN REFUS NE DIT PAS CE QUI MANQUE. « Identifiant inconnu » et « mot de
       passe erroné » distingués, c'est un annuaire offert à qui essaie : même
       réponse, même code, et une vérification de haché même sans compte (le
       temps de réponse ne renseigne pas non plus). */
    $hachePourTemps = '$2y$10$/oTioC/w28VSn7m83cgJIulHmP9D1w9FHfZOIBoZyUYQxP3al9m5G';
    $valide = password_verify($motDePasse, $u ? $u['mdp'] : $hachePourTemps);
    if (!$u || !$valide) {
        sigh_compter_echec($pdo, $identifiant);
        sigh_tentative($pdo, $identifiant, $u ?: null, $u ? 'Mot de passe erroné' : 'Identifiant inconnu');
        sigh_repondre([
            'erreur' => 'identifiants refusés', 'code' => 'IDENTIFIANTS_REFUSES',
            'detail' => 'Identifiant ou mot de passe incorrect.',
        ], 401);
    }

    /* Le mot de passe est bon : les refus qui suivent peuvent être NOMMÉS sans
       rien révéler à qui n'a pas le secret. */
    sigh_effacer_echecs($pdo, $identifiant);
    $fiche = sigh_fiche_compte($pdo, $u['identifiant']);
    $role  = sigh_role_de_session($u, $fiche);

    if (($u['statut'] ?? 'actif') !== 'actif' || sigh_fiche_inactive($fiche)) {
        sigh_tentative($pdo, $identifiant, $u, 'Compte archivé ou désactivé : accès retiré par l’administrateur');
        sigh_repondre([
            'erreur' => 'compte fermé', 'code' => 'COMPTE_INACTIF',
            'detail' => 'Ce compte est archivé ou désactivé : il n’ouvre plus de session (RG-14). Contacter l’administrateur.',
        ], 403);
    }

    /* UN COMPTE BLOQUÉ PAR L'ADMINISTRATEUR N'OUVRE PAS DE SESSION (01/11/2026). */
    if ($fiche !== null && !empty($fiche['bloque'])) {
        sigh_tentative($pdo, $identifiant, $u, 'Compte bloqué par l’administrateur');
        sigh_repondre([
            'erreur' => 'compte bloqué', 'code' => 'COMPTE_BLOQUE',
            'detail' => 'Ce compte a été bloqué par l’administrateur système : il n’ouvre plus de session tant qu’il n’est pas débloqué.',
        ], 423);
    }

    /* UN RÔLE ARCHIVÉ NE SE CONNECTE PAS (vague 15), et l'administrateur le retrouve
       dans l'onglet des tentatives de « Rôles & permissions ». */
    if (sigh_role_archive($pdo, $role)) {
        sigh_tentative($pdo, $identifiant, ['nom' => $u['nom'], 'role' => $role], 'Rôle archivé : accès retiré par l’administrateur');
        sigh_repondre([
            'erreur' => 'rôle archivé', 'code' => 'ROLE_ARCHIVE',
            'detail' => 'Le profil rattaché à ce compte a été archivé par l’administrateur système : le compte ne peut plus ouvrir de session.',
            'utilisateur' => ['identifiant' => $u['identifiant'], 'nom' => $u['nom'], 'role' => $role],
        ], 403);
    }

    $profil = [
        'identifiant' => $u['identifiant'], 'nom' => $u['nom'], 'role' => $role,
        'fonction' => $u['fonction'], 'secteur' => $u['secteur'],
        'mfa' => $fiche !== null && !empty($fiche['mfa']), 'mfaVerifie' => false,
    ];

    /* LE MOT DE PASSE PROVISOIRE NE DONNE AUCUNE SESSION. Un jeton de
       changement, à usage unique et de quinze minutes, ne sert qu'à choisir
       le vrai mot de passe : tant qu'il n'est pas changé, aucun écran, aucune
       lecture ni écriture du magasin ne s'ouvre (le serveur n'a pas de session
       à reconnaître). */
    if (sigh_doit_changer($u, $fiche)) {
        $jc = bin2hex(random_bytes(24));
        $pdo->prepare('DELETE FROM changements_requis WHERE cree_le < ' . sigh_il_y_a_minutes(SIGH_CHANGEMENT_TTL))->execute();
        $pdo->prepare('INSERT INTO changements_requis (jeton, identifiant) VALUES (?, ?)')->execute([$jc, $u['identifiant']]);
        sigh_journaliser($pdo, sigh_session_fictive($u, $role), 'Connexion en attente de changement de mot de passe',
            'sessions', $u['identifiant'], null, ['role' => $role]);
        sigh_repondre([
            'code' => 'CHANGEMENT_REQUIS', 'doitChanger' => true, 'jetonChangement' => $jc,
            'detail' => 'Un nouveau mot de passe doit être choisi avant d’ouvrir la session.',
            'utilisateur' => $profil + ['doitChanger' => true],
        ]);
    }

    /* LE JETON EST ENGENDRÉ ICI, ET NULLE PART AILLEURS. */
    $jeton = sigh_ouvrir_session($pdo, $u, $role, (string) ($corps['poste'] ?? ''));
    sigh_journaliser($pdo, sigh_session_fictive($u, $role), 'Connexion', 'sessions', $u['identifiant'], null, ['role' => $role]);

    sigh_repondre([
        'jeton'       => $jeton,
        'utilisateur' => $profil + ['doitChanger' => false],
    ]);
}

/* --- Changement de mot de passe -------------------------------------------- */
if ($action === 'changer_mot_de_passe') {
    $ancien  = (string) ($corps['ancienMotDePasse'] ?? '');
    $nouveau = (string) ($corps['nouveauMotDePasse'] ?? '');
    $s = sigh_session($pdo, $corps);
    $pendant = null;
    if ($s !== null) {
        $identifiant = (string) $s['identifiant'];
    } else {
        $jc = (string) ($corps['jetonChangement'] ?? '');
        $q = $pdo->prepare('SELECT identifiant FROM changements_requis WHERE jeton = ? AND cree_le > ' . sigh_il_y_a_minutes(SIGH_CHANGEMENT_TTL));
        $q->execute([$jc]);
        $identifiant = (string) $q->fetchColumn();
        if ($jc === '' || $identifiant === '') {
            sigh_repondre(['erreur' => 'session absente', 'code' => 'SESSION_ABSENTE',
                'detail' => 'Aucune session ni jeton de changement valide : se reconnecter.'], 401);
        }
        $pendant = $jc;
    }
    if (sigh_nb_echecs($pdo, $identifiant) >= SIGH_ECHECS_MAX) {
        sigh_repondre(['erreur' => 'compte verrouillé', 'code' => 'COMPTE_VERROUILLE',
            'detail' => 'Trop d’échecs sur ce compte. Réessayer dans ' . SIGH_ECHECS_FENETRE . ' minutes.'], 423);
    }
    $q = $pdo->prepare('SELECT * FROM utilisateurs WHERE identifiant = ?');
    $q->execute([$identifiant]);
    $u = $q->fetch();
    if (!$u || !password_verify($ancien, $u['mdp'])) {
        sigh_compter_echec($pdo, $identifiant);
        sigh_tentative($pdo, $identifiant, $u ?: null, 'Changement de mot de passe : ancien mot de passe erroné');
        sigh_repondre(['erreur' => 'ancien mot de passe erroné', 'code' => 'ANCIEN_MDP_ERRONE',
            'detail' => 'L’ancien mot de passe est incorrect.'], 401);
    }
    if (mb_strlen($nouveau) < SIGH_MDP_MIN) {
        sigh_repondre(['erreur' => 'mot de passe trop court', 'code' => 'MDP_TROP_COURT',
            'detail' => 'Le nouveau mot de passe doit compter au moins ' . SIGH_MDP_MIN . ' caractères.'], 400);
    }
    if ($nouveau === $ancien) {
        sigh_repondre(['erreur' => 'mot de passe identique', 'code' => 'MDP_IDENTIQUE',
            'detail' => 'Le nouveau mot de passe doit différer de l’ancien.'], 400);
    }
    $pdo->prepare('UPDATE utilisateurs SET mdp = ?, doit_changer = ' . (sigh_est_postgres() ? 'FALSE' : '0') . ', mdp_change_le = ? WHERE identifiant = ?')
        ->execute([password_hash($nouveau, PASSWORD_DEFAULT), gmdate('Y-m-d H:i:s'), $identifiant]);
    sigh_effacer_echecs($pdo, $identifiant);
    $fiche = sigh_fiche_compte($pdo, $identifiant);
    sigh_lever_marquage_fiche($pdo, $fiche);
    $role = sigh_role_de_session($u, $fiche);
    /* Le journal consigne le geste, jamais le secret (RG-12). */
    sigh_journaliser($pdo, $s ?? sigh_session_fictive($u, $role), 'Changement de mot de passe', 'utilisateurs', $identifiant, null, ['changeLe' => date('c')]);

    if ($pendant !== null) {
        $pdo->prepare('DELETE FROM changements_requis WHERE jeton = ?')->execute([$pendant]);
        if (sigh_role_archive($pdo, $role) || sigh_fiche_inactive($fiche)) {
            sigh_repondre(['erreur' => 'compte fermé', 'code' => 'COMPTE_INACTIF',
                'detail' => 'Mot de passe changé, mais le compte ne peut pas ouvrir de session.'], 403);
        }
        $u['doit_changer'] = false;
        $jeton = sigh_ouvrir_session($pdo, $u, $role, (string) ($corps['poste'] ?? ''));
        sigh_repondre(['ok' => true, 'jeton' => $jeton, 'utilisateur' => [
            'identifiant' => $u['identifiant'], 'nom' => $u['nom'], 'role' => $role,
            'fonction' => $u['fonction'], 'secteur' => $u['secteur'], 'doitChanger' => false,
        ]]);
    }
    sigh_repondre(['ok' => true, 'doitChanger' => false]);
}

/* --- Création d'un compte (admin ou da, vérifiés SUR LA SESSION) ------------ */
if ($action === 'creer_compte') {
    $s = sigh_exiger_session($pdo, $corps);
    if (!in_array($s['role'], SIGH_ROLES_GESTION_COMPTES, true)) {
        sigh_repondre(['erreur' => 'droit insuffisant', 'code' => 'DROIT_INSUFFISANT',
            'detail' => 'Seuls l’administrateur et la Directrice Administrative ouvrent un compte.'], 403);
    }
    $id  = mb_strtolower(trim((string) ($corps['identifiant'] ?? '')));
    $nom = trim((string) ($corps['nom'] ?? ''));
    $rol = trim((string) ($corps['role'] ?? ''));
    $mdp = (string) ($corps['motDePasse'] ?? '');
    if (!preg_match('/^[a-z0-9][a-z0-9._-]{2,63}$/', $id)) {
        sigh_repondre(['erreur' => 'identifiant invalide', 'code' => 'IDENTIFIANT_INVALIDE',
            'detail' => 'Identifiant : 3 à 64 caractères (lettres minuscules, chiffres, point, tiret).'], 400);
    }
    if ($nom === '' || !preg_match('/^[a-z_]{2,48}$/', $rol)) {
        sigh_repondre(['erreur' => 'compte incomplet', 'code' => 'COMPTE_INCOMPLET',
            'detail' => 'Le nom et le rôle sont obligatoires.'], 400);
    }
    if (mb_strlen($mdp) < SIGH_MDP_MIN) {
        sigh_repondre(['erreur' => 'mot de passe trop court', 'code' => 'MDP_TROP_COURT',
            'detail' => 'Le mot de passe provisoire doit compter au moins ' . SIGH_MDP_MIN . ' caractères.'], 400);
    }
    if ($rol === 'admin' && $s['role'] !== 'admin') {
        sigh_repondre(['erreur' => 'droit insuffisant', 'code' => 'DROIT_INSUFFISANT',
            'detail' => 'Seul un administrateur crée un compte administrateur.'], 403);
    }
    if (sigh_role_archive($pdo, $rol)) {
        sigh_repondre(['erreur' => 'rôle archivé', 'code' => 'ROLE_ARCHIVE',
            'detail' => 'Ce rôle est archivé : aucun compte ne peut y être rattaché.'], 409);
    }
    $q = $pdo->prepare('SELECT 1 FROM utilisateurs WHERE LOWER(identifiant) = ?');
    $q->execute([$id]);
    if ($q->fetchColumn()) {
        sigh_repondre(['erreur' => 'identifiant pris', 'code' => 'IDENTIFIANT_EXISTANT',
            'detail' => 'Cet identifiant est déjà attribué : aucun compte ne peut être partagé.'], 409);
    }
    $secteur = preg_match('/^[A-Za-z]{2,8}$/', (string) ($corps['secteur'] ?? '')) ? strtoupper((string) $corps['secteur']) : 'ADM';
    $pdo->prepare('INSERT INTO utilisateurs (identifiant, nom, role, fonction, secteur, mdp, doit_changer)
                   VALUES (?, ?, ?, ?, ?, ?, ' . (sigh_est_postgres() ? 'TRUE' : '1') . ')')
        ->execute([$id, $nom, $rol, SIGH_FONCTION_DU_ROLE[$rol] ?? $rol, $secteur, password_hash($mdp, PASSWORD_DEFAULT)]);
    sigh_journaliser($pdo, $s, 'Création de compte', 'utilisateurs', $id, null, ['role' => $rol, 'doitChanger' => true]);
    sigh_repondre(['ok' => true, 'identifiant' => $id, 'role' => $rol, 'doitChanger' => true], 201);
}

/* --- Levée d'un verrou d'échecs (admin ou da) ------------------------------- */
if ($action === 'deverrouiller') {
    $s = sigh_exiger_session($pdo, $corps);
    if (!in_array($s['role'], SIGH_ROLES_GESTION_COMPTES, true)) {
        sigh_repondre(['erreur' => 'droit insuffisant', 'code' => 'DROIT_INSUFFISANT',
            'detail' => 'Seuls l’administrateur et la Directrice Administrative lèvent un verrou.'], 403);
    }
    $id = trim((string) ($corps['identifiant'] ?? ''));
    sigh_effacer_echecs($pdo, $id);
    sigh_journaliser($pdo, $s, 'Déverrouillage de compte', 'utilisateurs', $id, null, null);
    sigh_repondre(['ok' => true, 'identifiant' => $id]);
}

sigh_repondre(['erreur' => 'action inconnue',
    'detail' => 'Actions acceptées : connexion, changer_mot_de_passe, creer_compte, deverrouiller, deconnexion, moi, comptes.'], 400);
