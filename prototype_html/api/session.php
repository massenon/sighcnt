<?php
/* =============================================================================
 * SIGH-CNT — La session, tenue par le SERVEUR
 * -----------------------------------------------------------------------------
 * Le prototype ouvrait sa session dans le `localStorage` : une ligne de console
 * suffisait à se déclarer administrateur. Tant que les données vivaient dans le
 * même navigateur, cela n'engageait personne. Dès lors que PLUSIEURS POSTES
 * écrivent dans la même base, ce n'est plus vrai : ce qu'un poste écrit, les
 * autres le lisent.
 *
 * La session est donc ouverte ICI et porte un JETON que le serveur seul
 * délivre. Le navigateur le garde et le présente à chaque écriture ; sans lui,
 * `magasin.php` refuse (RG-12 : aucune action anonyme).
 *
 * CE QUE CELA GARANTIT — et pas davantage : on sait QUI écrit, et l'on refuse
 * un anonyme. La matrice des droits par module vit encore dans le manifeste
 * JavaScript : le serveur ne la connaît pas. Le prétendre serait faux.
 *
 * POST   { identifiant, nom, role, fonction, secteur, poste } → { jeton }
 * GET    ?jeton=…                                            → la session
 * DELETE ?jeton=…                                            → la ferme
 * ========================================================================== */

require __DIR__ . '/config.php';

header('Access-Control-Allow-Origin: ' . ($_SERVER['HTTP_ORIGIN'] ?? '*'));
header('Access-Control-Allow-Credentials: true');
header('Access-Control-Allow-Headers: Content-Type, X-Sigh-Jeton');
header('Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS');
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    sigh_repondre(['ok' => true]);
}

/* =============================================================================
 * CE POINT D'ENTRÉE EST FERMÉ PAR DÉFAUT (08/10/2026).
 * -----------------------------------------------------------------------------
 * Il délivre un jeton pour un rôle DÉCLARÉ, sans vérifier de mot de passe.
 * C'était sans conséquence tant que la donnée vivait dans le navigateur ;
 * depuis que l'authentification passe par `auth.php` et que le jeton commande
 * l'écriture en base, ce serait une porte dérobée : n'importe qui obtiendrait
 * un jeton d'administrateur en le demandant poliment.
 *
 * Il ne reste ouvert que pour les BANCS D'ESSAI, qui doivent endosser une
 * trentaine de rôles au fil d'un parcours sans retaper un mot de passe à
 * chaque fois. La porte s'ouvre par `SIGH_BANC=1` dans l'environnement du
 * serveur — jamais en exploitation, jamais par défaut.
 *
 * La connexion réelle passe par `api/auth.php`, qui vérifie le haché.
 * ========================================================================== */
if (getenv('SIGH_BANC') !== '1') {
    sigh_repondre([
        'erreur' => 'point d’entrée fermé',
        'detail' => 'La session s’ouvre par api/auth.php, qui vérifie le mot de passe. '
                  . 'Ce point d’entrée ne déclare un rôle sans contrôle que sur un serveur '
                  . 'de banc d’essai (SIGH_BANC=1).',
    ], 403);
}

try {
    $pdo = sigh_pdo();
    sigh_installer($pdo);
} catch (Throwable $e) {
    sigh_repondre(['erreur' => 'base indisponible', 'detail' => $e->getMessage()], 503);
}

$methode = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$jeton   = $_GET['jeton'] ?? ($_SERVER['HTTP_X_SIGH_JETON'] ?? '');

if ($methode === 'POST') {
    $v = sigh_corps();
    if (empty($v['role'])) {
        sigh_repondre(['erreur' => 'rôle absent',
            'detail' => 'Une session de poste porte au minimum un rôle.'], 400);
    }
    /* Le jeton est tiré par le SERVEUR : un jeton choisi par le client
       n'atteste de rien. 32 octets aléatoires, en hexadécimal. */
    $jeton = bin2hex(random_bytes(24));
    $pdo->prepare('INSERT INTO sessions_poste (jeton, identifiant, nom, role, fonction, secteur, poste)
                   VALUES (?, ?, ?, ?, ?, ?, ?)')
        ->execute([
            $jeton,
            $v['identifiant'] ?? null,
            $v['nom'] ?? ($v['nomComplet'] ?? null),
            $v['role'],
            $v['fonction'] ?? null,
            $v['secteur'] ?? null,
            $v['poste'] ?? gethostname(),
        ]);
    /* Les sessions d'il y a plus d'un jour sont retirées au passage : une
       table de sessions qui ne se vide jamais finit par peser plus que le
       magasin qu'elle protège. */
    $pdo->exec(sigh_est_postgres()
        ? "DELETE FROM sessions_poste WHERE vue < CURRENT_TIMESTAMP - INTERVAL '1 day'"
        : 'DELETE FROM sessions_poste WHERE vue < DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 1 DAY)');

    sigh_repondre(['ok' => true, 'jeton' => $jeton]);
}

if ($methode === 'GET') {
    if ($jeton === '') {
        /* Combien de postes travaillent en ce moment : c'est la question que
           pose une simulation multi-postes, et elle a sa réponse ici. */
        $n = (int) $pdo->query('SELECT count(*) AS n FROM sessions_poste')->fetch()['n'];
        sigh_repondre(['ok' => true, 'sessions' => $n]);
    }
    $q = $pdo->prepare('SELECT jeton, identifiant, nom, role, fonction, secteur, poste, ouverte, vue
                        FROM sessions_poste WHERE jeton = ?');
    $q->execute([$jeton]);
    $s = $q->fetch();
    if (!$s) {
        sigh_repondre(['erreur' => 'session inconnue'], 404);
    }
    sigh_repondre(['ok' => true, 'session' => $s]);
}

if ($methode === 'DELETE') {
    $pdo->prepare('DELETE FROM sessions_poste WHERE jeton = ?')->execute([$jeton]);
    sigh_repondre(['ok' => true]);
}

sigh_repondre(['erreur' => 'méthode non prise en charge'], 405);
