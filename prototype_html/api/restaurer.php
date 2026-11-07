<?php
/* =============================================================================
 * SIGH-CNT — Restaurer le magasin depuis une sauvegarde du planificateur
 * -----------------------------------------------------------------------------
 * `api/cron.php` écrit chaque nuit `api/sauvegardes/magasin-AAAA-MM-JJ.json.gz`
 * (méta + collections). Une sauvegarde qu'on ne sait pas relire n'est pas une
 * sauvegarde : ce script est le chemin inverse.
 *
 *   php api/restaurer.php api/sauvegardes/magasin-2026-10-21.json.gz            → simulation
 *   php api/restaurer.php api/sauvegardes/magasin-2026-10-21.json.gz --oui      → restaure
 *
 * CE QUE LA RESTAURATION REMPLACE : toutes les collections et toute la méta.
 * CE QU'ELLE NE TOUCHE PAS : les comptes (`utilisateurs`) et les sessions —
 * la sauvegarde ne les porte pas, et rouvrir des sessions d'hier serait pire
 * que de reconnecter les postes. Les postes ouverts doivent être rechargés.
 *
 * La copie relationnelle (tables de module) est reconstruite ensuite, puis la
 * parité contrôlée. Ligne de commande uniquement : une restauration ne se
 * déclenche pas depuis une page.
 * ========================================================================== */

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

require __DIR__ . '/config.php';
require_once __DIR__ . '/projection.php';

$fichier = $argv[1] ?? '';
$oui = in_array('--oui', $argv ?? [], true);

if ($fichier === '' || !is_file($fichier)) {
    fwrite(STDERR, "Usage : php api/restaurer.php <sauvegarde.json.gz> [--oui]\n");
    exit(2);
}

$brut = file_get_contents($fichier);
$json = (substr($brut, 0, 2) === "\x1f\x8b") ? gzdecode($brut) : $brut;
$tout = is_string($json) ? json_decode($json, true) : null;
if (!is_array($tout) || !isset($tout['collections']) || !is_array($tout['collections'])) {
    fwrite(STDERR, "Fichier illisible ou sans collections : rien n'est restauré.\n");
    exit(2);
}
$meta = is_array($tout['meta'] ?? null) ? $tout['meta'] : [];
$fiches = 0;
foreach ($tout['collections'] as $f) {
    $fiches += is_array($f) ? count($f) : 0;
}

fwrite(STDOUT, 'Sauvegarde : ' . basename($fichier) . ' — ' . count($tout['collections']) . ' collection(s), '
    . $fiches . ' fiche(s), version de schéma ' . ($meta['_version'] ?? '?') . "\n");
fwrite(STDOUT, 'Base cible : ' . SIGH_DSN . "\n");

if (!$oui) {
    fwrite(STDOUT, "Simulation : rien n'a été modifié. Ajouter --oui pour restaurer (le contenu actuel du magasin sera remplacé).\n");
    exit(0);
}

$pdo = sigh_pdo();
sigh_installer($pdo);
$pg = sigh_est_postgres();

/* Le contenu actuel est mis de côté AVANT de l'écraser : une restauration à la mauvaise date se rattrape. */
$dossier = __DIR__ . '/sauvegardes';
if (!is_dir($dossier)) {
    @mkdir($dossier, 0750, true);
}
$avant = ['meta' => [], 'collections' => []];
foreach ($pdo->query('SELECT cle, valeur FROM meta') as $l) {
    $avant['meta'][$l['cle']] = json_decode($l['valeur'], true);
}
foreach ($pdo->query('SELECT nom, donnees FROM collections') as $l) {
    $avant['collections'][$l['nom']] = json_decode($l['donnees'], true);
}
$sortie = $dossier . '/avant-restauration-' . gmdate('Y-m-d-His') . '.json.gz';
file_put_contents($sortie, gzencode(json_encode($avant, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES), 6));
fwrite(STDOUT, 'État précédent conservé : ' . basename($sortie) . "\n");

$pdo->beginTransaction();
try {
    $pdo->exec('DELETE FROM collections');
    $pdo->exec('DELETE FROM meta');
    $qc = $pdo->prepare($pg
        ? 'INSERT INTO collections (nom, donnees, fiches, maj) VALUES (?, ?, ?, CURRENT_TIMESTAMP)'
        : 'INSERT INTO collections (nom, donnees, fiches) VALUES (?, ?, ?)');
    foreach ($tout['collections'] as $nom => $liste) {
        if (!is_array($liste)) {
            continue;
        }
        $qc->execute([$nom, json_encode($liste, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES), count($liste)]);
    }
    $qm = $pdo->prepare($pg
        ? 'INSERT INTO meta (cle, valeur, maj) VALUES (?, ?, CURRENT_TIMESTAMP)'
        : 'INSERT INTO meta (cle, valeur) VALUES (?, ?)');
    foreach ($meta as $cle => $valeur) {
        $qm->execute([$cle, json_encode($valeur, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)]);
    }
    $pdo->commit();
} catch (Throwable $e) {
    $pdo->rollBack();
    fwrite(STDERR, "Échec, rien n'a changé : " . $e->getMessage() . "\n");
    exit(1);
}
fwrite(STDOUT, "Magasin restauré.\n");

/* La copie relationnelle suit ; son échec n'invalide pas la restauration (le magasin JSON fait autorité). */
try {
    $pdo->beginTransaction();
    sigh_proj_vider($pdo);
    $b = sigh_proj_projeter($pdo, $tout['collections']);
    $pdo->commit();
    $v = sigh_proj_verifier($pdo);
    fwrite(STDOUT, 'Projection : ' . $b['ok'] . ' collection(s) ; parité : ' . count($v['ecarts']) . " écart(s)\n");
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    fwrite(STDOUT, 'Projection à refaire (php api/projection.php) : ' . $e->getMessage() . "\n");
}
fwrite(STDOUT, "Recharger les postes ouverts.\n");
exit(0);
