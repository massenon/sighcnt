<?php
/* Sonde du banc SAUV-F (jamais servie par le serveur : ligne de commande seulement).
 *   php build/_sonde-sauvegarde.php <dossier> <secondes>   une passe de copie du dossier des fichiers (SIGH_FICHIERS_DIR) vers <dossier>, temps accordé <secondes> ('' = sans limite)
 *   php build/_sonde-sauvegarde.php magasin                l'empreinte de TOUTES les collections en base (la tâche de sauvegarde n'en écrit aucune)
 * Elle appelle les fonctions de api/_sauvegarde.php telles quelles et rend du JSON. */
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
require __DIR__ . '/../api/_sauvegarde.php';

if (($argv[1] ?? '') === 'magasin') {
    $pdo = sigh_pdo();
    $e = $pdo->query("SELECT md5(string_agg(nom || ':' || donnees::text, ',' ORDER BY nom)) AS m, count(*) AS n FROM collections")->fetch();
    echo json_encode(['empreinte' => $e['m'], 'collections' => (int) $e['n']]), "\n";
    exit(0);
}
$dossier = $argv[1] ?? '';
$budget = ($argv[2] ?? '') === '' ? null : (float) $argv[2];
$r = sigh_sauv_sauvegarder(['chemin' => $dossier, 'memeDisque' => null], $budget);
echo json_encode(['copies' => $r['copies'], 'restants' => $r['restants'], 'totalSource' => $r['totalSource'], 'alteres' => count($r['alteres']), 'dejaPresents' => $r['dejaPresents']]), "\n";
