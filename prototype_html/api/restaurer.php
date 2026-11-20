<?php
/* =============================================================================
 * SIGH-CNT : restaurer le magasin et les fichiers numérisés depuis une sauvegarde du planificateur
 * -----------------------------------------------------------------------------
 * `api/cron.php` écrit chaque nuit `magasin-AAAA-MM-JJ.json.gz` (méta + collections) et copie, de façon incrémentale et vérifiée, les fichiers numérisés
 * sous `fichiers/<aa>/<sha256>.<ext>` dans la destination de sauvegarde (par défaut `api/sauvegardes/`, ou le réglage de la clinique). Une sauvegarde qu'on ne
 * sait pas relire n'est pas une sauvegarde : ce script est le chemin inverse.
 *
 *   php api/restaurer.php api/sauvegardes/magasin-2026-10-21.json.gz            → simulation (magasin ET fichiers)
 *   php api/restaurer.php api/sauvegardes/magasin-2026-10-21.json.gz --oui      → restaure
 *   php api/restaurer.php --fichiers                                            → simulation, FICHIERS seuls (le magasin n'est pas touché)
 *   php api/restaurer.php --fichiers --oui                                      → restaure les fichiers manquants ou altérés
 *   options : --sans-fichiers (magasin seul), --destination=<dossier> (la sauvegarde des fichiers, si le réglage est perdu),
 *             --rapport=<fichier.json> (le compte rendu des fichiers, lisible par une machine)
 *
 * CE QUE LA RESTAURATION DU MAGASIN REMPLACE : toutes les collections et toute la méta.
 * CE QU'ELLE NE TOUCHE PAS : les comptes (`utilisateurs`) et les sessions —
 * la sauvegarde ne les porte pas, et rouvrir des sessions d'hier serait pire
 * que de reconnecter les postes. Les postes ouverts doivent être rechargés.
 *
 * LES FICHIERS : chaque fichier de la sauvegarde est vérifié (empreinte SHA-256) AVANT d'être posé. Un fichier présent et intact n'est JAMAIS écrasé. Un fichier
 * présent mais altéré est mis de côté dans `_alteres/` puis remplacé par la copie saine. Une copie altérée n'est jamais posée : elle est nommée au compte rendu.
 * Rien n'est supprimé (RG-14). Le compte rendu dit : restaurés, déjà présents, altérés, introuvables dans la sauvegarde.
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
require_once __DIR__ . '/_sauvegarde.php';

$positionnels = [];
$options = [];
foreach (array_slice($argv ?? [], 1) as $a) {
    if (strncmp($a, '--', 2) === 0) {
        $kv = explode('=', substr($a, 2), 2);
        $options[$kv[0]] = $kv[1] ?? true;
    } else {
        $positionnels[] = $a;
    }
}
$fichier = $positionnels[0] ?? '';
$oui = isset($options['oui']);
$fichiersSeuls = isset($options['fichiers']) && $fichier === '';
$sansFichiers = isset($options['sans-fichiers']);

if (($fichier === '' && !$fichiersSeuls) || ($fichier !== '' && !is_file($fichier))) {
    fwrite(STDERR, "Usage : php api/restaurer.php <sauvegarde.json.gz> [--oui] [--sans-fichiers] [--destination=<dossier>]\n"
        . "        php api/restaurer.php --fichiers [--oui] [--destination=<dossier>] [--rapport=<fichier.json>]\n");
    exit(2);
}

$tout = null;
$meta = [];
if ($fichier !== '') {
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
    } else {
        $pdo = sigh_pdo();
        sigh_installer($pdo);
        $pg = sigh_est_postgres();

        /* Le contenu actuel est mis de côté AVANT de l'écraser : une restauration à la mauvaise date se rattrape. */
        $dossier = sigh_sauvegardes_racine();
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
    }
}

/* --------------------------------------------------------------------------
 * LES FICHIERS NUMÉRISÉS (lot SAUV-F)
 * ------------------------------------------------------------------------ */
$code = 0;
if (!$sansFichiers) {
    $collections = null;
    $pdoF = null;
    if ($tout !== null) {
        $collections = $tout['collections'];
    } else {
        try {
            $pdoF = sigh_pdo();
            sigh_installer($pdoF);
            $collections = sigh_sauv_collections($pdoF);
        } catch (Throwable $e) {
            fwrite(STDOUT, "Références du magasin non lues (base indisponible) : les fichiers introuvables ne seront pas comptés.\n");
        }
    }
    /* La destination : celle qu'on indique, sinon le réglage que la sauvegarde porte (ou celui de la base en cours), sinon le défaut. */
    if (isset($options['destination']) && is_string($options['destination']) && $options['destination'] !== '') {
        $dChemin = $options['destination'];
        $origineDest = 'indiquée (--destination)';
    } else {
        $reg = $tout !== null ? sigh_sauv_reglage_depuis_meta($meta) : ($pdoF ? sigh_sauv_reglage($pdoF) : null);
        $dChemin = $reg ?? sigh_sauvegardes_racine();
        $origineDest = $reg !== null ? 'réglage de la clinique' : 'défaut';
    }
    $v = sigh_sauv_verifier_chemin($dChemin, false, false);
    if (!$v['ok']) {
        fwrite(STDERR, 'Fichiers non restaurés, destination refusée : ' . $v['code'] . ' : ' . $v['motif'] . ' ' . $v['geste'] . "\n");
        fwrite(STDERR, "Indiquer le dossier de la sauvegarde avec --destination=<dossier>.\n");
        exit(3);
    }
    $r = sigh_sauv_restaurer($collections ?? [], $v['chemin'], $oui);
    fwrite(STDOUT, 'Fichiers : sauvegarde lue dans ' . $v['chemin'] . ' (' . $origineDest . '), dossier cible ' . $r['dossier'] . "\n");
    $verbe = $oui ? 'restaurés' : 'à restaurer';
    fwrite(STDOUT, 'Fichiers ' . $verbe . ' : ' . count($r['restaures']) . ' (' . sigh_sauv_poids($r['octets']) . ")\n");
    fwrite(STDOUT, 'Fichiers déjà présents et intacts (jamais écrasés) : ' . $r['dejaPresents'] . "\n");
    fwrite(STDOUT, 'Fichiers altérés ' . ($oui ? 'remplacés' : 'à remplacer') . ' par la copie saine (l’altéré est conservé dans _alteres/) : ' . count($r['remplaces']) . "\n");
    fwrite(STDOUT, 'Copies altérées dans la sauvegarde, non posées : ' . count($r['alteresSauvegarde']) . "\n");
    foreach ($r['alteresSauvegarde'] as $a) {
        fwrite(STDOUT, '  copie altérée : ' . $a['sha256'] . '.' . $a['ext'] . "\n");
    }
    fwrite(STDOUT, 'Fichiers introuvables dans la sauvegarde (référencés, absents partout) : ' . count($r['introuvables']) . "\n");
    foreach (array_slice($r['introuvables'], 0, 20) as $a) {
        fwrite(STDOUT, '  introuvable : ' . $a['sha256'] . "\n");
    }
    fwrite(STDOUT, 'Fiches d’accompagnement ' . ($oui ? 'restaurées' : 'à restaurer') . ' : ' . $r['fiches']['restaurees'] . ' ; déjà présentes : ' . $r['fiches']['dejaPresentes'] . "\n");
    if ($r['echecs']) {
        fwrite(STDOUT, 'Échecs d’écriture : ' . count($r['echecs']) . "\n");
    }
    if (!$oui) {
        fwrite(STDOUT, "Simulation : aucun fichier n'a été modifié. Ajouter --oui pour restaurer les fichiers.\n");
    }
    if (isset($options['rapport']) && is_string($options['rapport'])) {
        file_put_contents($options['rapport'], json_encode($r, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT));
    }
    if ($r['alteresSauvegarde'] || $r['introuvables'] || $r['echecs']) {
        $code = 3;
    }
}
exit($code);
