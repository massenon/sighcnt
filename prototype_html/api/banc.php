<?php
/* =============================================================================
 * SIGH-CNT — Maintenance des BANCS D'ESSAI
 * -----------------------------------------------------------------------------
 * Un banc d'essai doit partir d'un jeu PROPRE et REPRODUCTIBLE : si chaque
 * exécution héritait de la précédente, un scénario finirait par dépendre de
 * celui qui l'a précédé, et un échec ne dirait plus lequel des deux ment.
 *
 * CE FICHIER EST FERMÉ PAR DÉFAUT, comme `session.php` : il ne répond que sur
 * un serveur démarré avec `SIGH_BANC=1`, et les bancs le démarrent sur une
 * base JETABLE (`SIGH_BASE`). La base de travail n'est jamais à sa portée.
 *
 * POST { action: 'reinitialiser' } → vide collections, meta et sessions.
 * ========================================================================== */

require_once __DIR__ . '/_commun.php';

if (getenv('SIGH_BANC') !== '1') {
    sigh_repondre([
        'erreur' => 'point d’entrée fermé',
        'detail' => 'Maintenance réservée aux bancs d’essai (SIGH_BANC=1).',
    ], 403);
}

/* GARDE-FOU : on refuse de vider une base dont le nom ne dit pas qu'elle est
   jetable. Une variable d'environnement mal posée ne doit pas effacer le
   travail de la clinique. */
$nom = '';
if (preg_match('/dbname=([^;]+)/', SIGH_DSN, $m)) {
    $nom = $m[1];
}
if (!preg_match('/(test|essai|banc)/i', $nom)) {
    sigh_repondre([
        'erreur' => 'base non jetable',
        'detail' => 'Refus de réinitialiser « ' . $nom . ' » : le nom d’une base de banc '
                  . 'doit porter « test », « essai » ou « banc ». Une variable mal posée '
                  . 'ne doit pas effacer la base de travail.',
    ], 403);
}

/* LA BASE JETABLE SE CRÉE TOUTE SEULE. Exiger qu'elle préexiste ferait
   échouer le banc sur un poste neuf pour une raison sans rapport avec ce
   qu'il mesure. On ne crée QUE celle dont le nom dit qu'elle est jetable —
   le garde-fou ci-dessus a déjà tranché. */
try {
    $pdo = sigh_pdo();
} catch (Throwable $e) {
    try {
        $dsnAdmin = preg_replace('/dbname=[^;]*/', 'dbname=postgres', SIGH_DSN);
        $admin = new PDO($dsnAdmin, SIGH_USER, SIGH_PASS, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
        $admin->exec('CREATE DATABASE "' . str_replace('"', '', $nom) . '"');
        $pdo = sigh_pdo();
    } catch (Throwable $e2) {
        sigh_repondre(['erreur' => 'base indisponible',
            'detail' => $e->getMessage() . ' / création : ' . $e2->getMessage()], 503);
    }
}
try {
    sigh_installer($pdo);
    sigh_installer_comptes($pdo);
} catch (Throwable $e) {
    sigh_repondre(['erreur' => 'schéma', 'detail' => $e->getMessage()], 503);
}

$corps  = sigh_corps();
$action = (string) ($corps['action'] ?? $_GET['action'] ?? '');

if ($action === 'reinitialiser') {
    $pdo->exec('DELETE FROM collections');
    $pdo->exec('DELETE FROM meta');
    $pdo->exec('DELETE FROM sessions_poste');
    sigh_repondre(['base' => $nom, 'vide' => true]);
}

if ($action === 'etat') {
    $c = (int) $pdo->query('SELECT COUNT(*) FROM collections')->fetchColumn();
    $f = (int) $pdo->query('SELECT COALESCE(SUM(fiches), 0) FROM collections')->fetchColumn();
    $u = (int) $pdo->query('SELECT COUNT(*) FROM utilisateurs')->fetchColumn();
    sigh_repondre(['base' => $nom, 'collections' => $c, 'fiches' => $f, 'comptes' => $u]);
}

sigh_repondre(['erreur' => 'action inconnue',
    'detail' => 'Actions acceptées : reinitialiser, etat.'], 400);
