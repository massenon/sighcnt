<?php
/* =============================================================================
 * SIGH-CNT : contrôle d'intégrité des fichiers numérisés (lot SAUV-F)
 * -----------------------------------------------------------------------------
 * Relit TOUS les fichiers que le magasin référence (registre `fichiers`, courriers, documents du patient, pièces retirées comprises) et dit :
 *   - ceux qui MANQUENT sur le disque,
 *   - ceux dont l'EMPREINTE a changé (le fichier est altéré),
 *   - les fichiers présents sur le disque que personne ne référence (ORPHELINS : signalés, jamais supprimés, RG-14),
 *   - les fichiers sans fiche d'accompagnement (sans elle, la règle de lecture par famille et par zone ne s'applique plus).
 * Il ne corrige rien et ne supprime rien. `--sauvegarde` relit aussi la copie de chaque fichier dans la destination de sauvegarde.
 *
 *   php api/controler_fichiers.php                  → compte rendu
 *   php api/controler_fichiers.php --sauvegarde     → et la sauvegarde (non sauvegardés, copies altérées)
 *   php api/controler_fichiers.php --json           → le même compte rendu, lisible par une machine
 *
 * Code de sortie : 0 tout est en ordre, 3 un fichier manque ou est altéré, 1 base indisponible. La même vérification tourne chaque nuit dans le planificateur
 * (tâche `controle_fichiers`) et alerte l'administrateur et la DAF. Ligne de commande uniquement.
 * ========================================================================== */

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

require __DIR__ . '/config.php';
require_once __DIR__ . '/_sauvegarde.php';

$avecSauvegarde = in_array('--sauvegarde', $argv ?? [], true);
$json = in_array('--json', $argv ?? [], true);

try {
    $pdo = sigh_pdo();
    sigh_installer($pdo);
    $dest = null;
    if ($avecSauvegarde) {
        $dest = sigh_sauv_destination($pdo, null, false);
        if (!$dest['ok']) {
            fwrite(STDERR, 'Sauvegarde non vérifiée, destination refusée : ' . $dest['code'] . ' : ' . $dest['motif'] . ' ' . $dest['geste'] . "\n");
            $dest = null;
        }
    }
    $r = sigh_sauv_controler(sigh_sauv_collections($pdo), $dest);
} catch (Throwable $e) {
    fwrite(STDERR, 'Contrôle impossible : ' . $e->getMessage() . "\n");
    exit(1);
}

if ($json) {
    fwrite(STDOUT, json_encode($r, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT) . "\n");
} else {
    fwrite(STDOUT, 'Dossier des fichiers : ' . $r['dossier'] . ($r['dossierPresent'] ? '' : ' (absent)') . "\n");
    fwrite(STDOUT, sigh_sauv_resume_controle($r) . "\n");
    $liste = function (string $titre, array $l) {
        if (!$l) { return; }
        fwrite(STDOUT, $titre . "\n");
        foreach (array_slice($l, 0, 50) as $x) { fwrite(STDOUT, '  ' . $x['sha256'] . (isset($x['ext']) ? '.' . $x['ext'] : '') . "\n"); }
        if (count($l) > 50) { fwrite(STDOUT, '  … et ' . (count($l) - 50) . " autre(s)\n"); }
    };
    $liste('Manquants (référencés, absents du disque) :', $r['manquants']);
    $liste('Altérés (l’empreinte n’est plus celle du nom) :', $r['divergents']);
    $liste('Orphelins (sur le disque, aucune fiche, conservés) :', $r['orphelins']);
    $liste('Sans fiche d’accompagnement :', $r['sansFiche']);
    if ($r['intrus']) { fwrite(STDOUT, "Rangés dans un mauvais dossier :\n  " . implode("\n  ", array_slice($r['intrus'], 0, 50)) . "\n"); }
    $liste('Non sauvegardés :', $r['nonSauvegardes']);
    $liste('Copies altérées dans la sauvegarde :', $r['copiesAlterees']);
}
exit(($r['manquants'] || $r['divergents'] || $r['copiesAlterees']) ? 3 : 0);
