<?php
/* =============================================================================
 * SIGH-CNT — Contrôle de la copie relationnelle (réservé à l'administration)
 * -----------------------------------------------------------------------------
 * GET                       → parité magasin ↔ tables : combien de fiches de
 *                             chaque collection, quels écarts, quelles erreurs
 *                             de projection récentes.
 * GET ?collection=X&id=Y    → la ligne de la table relationnelle pour une fiche
 *                             (lecture seule ; seules les tables du schéma).
 * ========================================================================== */
require __DIR__ . '/_commun.php';
require_once __DIR__ . '/projection.php';

try {
    $pdo = sigh_pdo();
    sigh_installer($pdo);
} catch (Throwable $e) {
    sigh_repondre(['erreur' => 'base indisponible', 'detail' => $e->getMessage()], 503);
}
$session = sigh_exiger_session($pdo);
if (!in_array($session['role'] ?? '', ['admin', 'da', 'direction'], true)) {
    sigh_repondre(['erreur' => 'accès refusé', 'detail' => 'Le contrôle de la copie relationnelle est réservé à l’administration.'], 403);
}
if (!sigh_proj_installer($pdo)) {
    sigh_repondre(['erreur' => 'copie relationnelle indisponible', 'detail' => 'Base non PostgreSQL ou schéma absent.'], 501);
}
$m = sigh_proj_manifeste();

if (isset($_GET['collection'], $_GET['id'])) {
    $nom = (string) $_GET['collection'];
    if (!isset($m['tables'][$nom]) || !$m['tables'][$nom]['aId']) {
        sigh_repondre(['erreur' => 'collection inconnue du schéma'], 404);
    }
    $t = $m['tables'][$nom];
    $q = $pdo->prepare('SELECT * FROM "' . $t['schema'] . '"."' . $t['table'] . '" WHERE "id" = ?');
    $q->execute([(string) $_GET['id']]);
    $ligne = $q->fetch(PDO::FETCH_ASSOC);
    sigh_repondre(['table' => $t['schema'] . '.' . $t['table'], 'ligne' => $ligne ?: null]);
}

$v = sigh_proj_verifier($pdo);
$erreurs = $pdo->query('SELECT collection, message, le FROM projection_erreurs ORDER BY id DESC LIMIT 10')->fetchAll(PDO::FETCH_ASSOC);
$schemas = $pdo->query("SELECT table_schema AS schema, count(*) AS tables FROM information_schema.tables
    WHERE table_schema NOT IN ('pg_catalog','information_schema','public') GROUP BY 1 ORDER BY 1")->fetchAll(PDO::FETCH_ASSOC);
sigh_repondre(['parite' => $v, 'erreurs' => $erreurs, 'schemas' => $schemas]);
