<?php
/* =============================================================================
 * SIGH-CNT : la sauvegarde, le contrôle et la restauration des FICHIERS numérisés (lot SAUV-F)
 * -----------------------------------------------------------------------------
 * Le lot DOCS-1 a sorti les scans du magasin : ils vivent dans `api/fichiers/<aa>/<sha256>.<ext>` (plus une fiche d'accompagnement `.json`). La sauvegarde
 * nocturne ne copiait que le magasin JSON : une panne de disque perdait les scans (E2491). Ce fichier porte ce qui manquait, pour `cron.php` (deux tâches),
 * `restaurer.php` et `controler_fichiers.php`.
 *
 * CE QUI EST GARANTI ICI :
 *   - un fichier est adressé par son empreinte, donc IMMUABLE : la copie est INCRÉMENTALE (elle ne copie que ce qui manque) et JAMAIS tournante (conservation
 *     ILLIMITÉE des pièces, décision de la Direction, section H). La rotation à 7 jours du magasin ne touche pas un seul fichier ;
 *   - l'empreinte SHA-256 est RECALCULÉE à la lecture de la source, sur les octets réellement copiés : un fichier altéré n'est jamais propagé à la sauvegarde, il
 *     est NOMMÉ. La copie écrite est relue et comparée avant d'être posée sous son nom définitif (écriture dans un `.tmp`, puis renommage) ;
 *   - une destination qui n'existe pas, n'est pas un dossier, n'est pas inscriptible ou recouvre le dossier des fichiers est REFUSÉE en le nommant (code, motif,
 *     geste). Elle n'est jamais créée : créer `/mnt/disque` sur un disque absent écrirait sur le disque du système, la panne que la sauvegarde doit couvrir ;
 *   - la restauration ne pose une copie qu'après avoir vérifié son empreinte ; un fichier présent et intact n'est JAMAIS écrasé ; un fichier présent mais altéré
 *     est mis de côté (`_alteres/`) avant d'être remplacé par la copie saine. Rien n'est supprimé (RG-14) ;
 *   - une tâche LIT et copie : elle n'écrit aucune collection du magasin (doctrine du planificateur).
 *
 * CE QUI N'EST PAS GARANTI : une copie sur le MÊME disque que les données ne protège pas d'une panne de disque. Le serveur le calcule (périphérique du
 * dossier de destination comparé à celui des fichiers) et le DIT, à l'écran et dans l'alerte : il ne le masque pas. Sous Windows le périphérique n'est pas toujours
 * lisible : la réponse est alors « indéterminé », jamais « ailleurs ».
 * ========================================================================== */

require_once __DIR__ . '/config.php';

const SIGH_SAUV_EXTENSIONS = ['pdf', 'jpg', 'png', 'webp'];

function sigh_sauv_refus(string $code, string $motif, string $geste): array
{
    return ['ok' => false, 'code' => $code, 'motif' => $motif, 'geste' => $geste];
}

function sigh_sauv_poids(int $octets): string
{
    if ($octets >= 1073741824) { return number_format($octets / 1073741824, 1, ',', ' ') . ' Go'; }
    if ($octets >= 1048576) { return number_format($octets / 1048576, 1, ',', ' ') . ' Mo'; }
    return max($octets > 0 ? 1 : 0, (int) round($octets / 1024)) . ' Ko';
}

function sigh_sauv_abrege(string $sha): string
{
    return substr($sha, 0, 12);
}

/* --------------------------------------------------------------------------
 * LA DESTINATION : réglage en base, défaut dit, vérification réelle
 * ------------------------------------------------------------------------ */

/** Le réglage de la clinique (`_reglages.sauvegardeFichiers.destination`, en base), ou null : le défaut s'applique. */
function sigh_sauv_reglage(PDO $pdo): ?string
{
    try {
        $q = $pdo->prepare('SELECT valeur FROM meta WHERE cle = ?');
        $q->execute(['_reglages']);
        $v = $q->fetchColumn();
        $r = $v ? json_decode((string) $v, true) : null;
        $d = is_array($r) ? ($r['sauvegardeFichiers']['destination'] ?? null) : null;
        return is_string($d) && trim($d) !== '' ? trim($d) : null;
    } catch (Throwable $e) {
        return null;
    }
}

function sigh_sauv_reglage_depuis_meta(array $meta): ?string
{
    $d = $meta['_reglages']['sauvegardeFichiers']['destination'] ?? null;
    return is_string($d) && trim($d) !== '' ? trim($d) : null;
}

function sigh_sauv_chemin_absolu(string $c): bool
{
    return $c !== '' && ($c[0] === '/' || (bool) preg_match('/^[A-Za-z]:[\\\\\\/]/', $c) || strncmp($c, '\\\\', 2) === 0);
}

/** Vrai si $a est $b ou se trouve sous $b (comparaison à la frontière d'un dossier). */
function sigh_sauv_sous(string $a, string $b): bool
{
    $a = rtrim(str_replace('\\', '/', $a), '/') . '/';
    $b = rtrim(str_replace('\\', '/', $b), '/') . '/';
    return DIRECTORY_SEPARATOR === '\\' ? stripos($a, $b) === 0 : strpos($a, $b) === 0;
}

function sigh_sauv_peripherique(string $chemin): ?int
{
    $s = @stat($chemin);
    return $s ? (int) $s['dev'] : null;
}

/** La destination est-elle sur le même disque que les fichiers (à défaut, que l'application) ? true / false / null (indéterminé). */
function sigh_sauv_meme_disque(string $destination): ?bool
{
    $src = sigh_fichiers_racine();
    $a = sigh_sauv_peripherique($destination);
    $b = sigh_sauv_peripherique(is_dir($src) ? $src : __DIR__);
    if ($a === null || $b === null) { return null; }
    return $a === $b;
}

/**
 * Vérifie un dossier de destination. Rend { ok, chemin, memeDisque } ou le refus NOMMÉ { ok:false, code, motif, geste }.
 * `$ecriture` : la sauvegarde exige un dossier inscriptible ; la restauration ne fait que LIRE (un support en lecture seule est légitime).
 */
function sigh_sauv_verifier_chemin(string $chemin, bool $creerSiDefaut = false, bool $ecriture = true): array
{
    $chemin = trim($chemin);
    if ($chemin === '' || strpos($chemin, "\0") !== false) {
        return sigh_sauv_refus('DESTINATION_VIDE', 'aucun chemin de destination n’est indiqué', 'Saisir le chemin complet du dossier de sauvegarde, ou revenir au défaut.');
    }
    if (!sigh_sauv_chemin_absolu($chemin)) {
        return sigh_sauv_refus('CHEMIN_RELATIF', 'le chemin « ' . $chemin . ' » n’est pas un chemin complet : un chemin relatif ne désigne pas le même dossier pour le serveur web et pour la tâche planifiée',
            'Saisir le chemin complet, par exemple /mnt/sauvegarde ou D:\\Sauvegardes.');
    }
    if ($creerSiDefaut && !is_dir($chemin)) {
        @mkdir($chemin, 0750, true);
    }
    if (!file_exists($chemin)) {
        return sigh_sauv_refus('DESTINATION_INEXISTANTE', 'le dossier « ' . $chemin . ' » n’existe pas (ou le disque qui le porte n’est pas branché)',
            'Brancher ou monter le disque, créer le dossier, puis le désigner de nouveau. Il n’est jamais créé automatiquement : le créer sur un disque absent écrirait sur le disque du système.');
    }
    if (!is_dir($chemin)) {
        return sigh_sauv_refus('DESTINATION_PAS_UN_DOSSIER', '« ' . $chemin . ' » est un fichier, pas un dossier', 'Désigner un dossier.');
    }
    $reel = realpath($chemin) ?: $chemin;
    $src = sigh_fichiers_racine();
    $srcReel = is_dir($src) ? (realpath($src) ?: $src) : $src;
    $cible = rtrim(str_replace('\\', '/', $reel), '/') . '/fichiers';
    if (sigh_sauv_sous($cible, $srcReel) || sigh_sauv_sous($srcReel, $cible)) {
        return sigh_sauv_refus('DESTINATION_DANS_SOURCE', 'la destination « ' . $chemin . ' » recouvre le dossier des fichiers numérisés : la copie se ferait sur elle-même et ne protégerait rien',
            'Choisir un dossier à l’extérieur du dossier des fichiers, de préférence sur un autre disque.');
    }
    if ($ecriture) {
        $sonde = $reel . DIRECTORY_SEPARATOR . '.sigh-ecriture-' . bin2hex(random_bytes(4));
        $ok = @file_put_contents($sonde, 'ok') !== false && @file_get_contents($sonde) === 'ok';
        @unlink($sonde);
        if (!$ok) {
            return sigh_sauv_refus('DESTINATION_NON_INSCRIPTIBLE', 'le serveur ne peut pas écrire dans « ' . $chemin . ' » (droits, support en lecture seule ou disque plein)',
                'Donner au compte du serveur le droit d’écrire dans ce dossier, ou en désigner un autre.');
        }
    }
    return ['ok' => true, 'chemin' => $reel, 'memeDisque' => sigh_sauv_meme_disque($reel)];
}

/**
 * La destination EN FORCE : le réglage de la clinique, sinon le défaut (`api/sauvegardes/`). Un réglage INATTEIGNABLE n'est jamais remplacé en silence par le
 * défaut : il est refusé en le nommant, et l'appelant alerte.
 */
function sigh_sauv_destination(PDO $pdo, ?string $surcharge = null, bool $ecriture = true): array
{
    $demande = $surcharge !== null ? trim($surcharge) : sigh_sauv_reglage($pdo);
    $defaut = $demande === null || $demande === '';
    $chemin = $defaut ? sigh_sauvegardes_racine() : $demande;
    $r = sigh_sauv_verifier_chemin($chemin, $defaut, $ecriture);
    $r['defaut'] = $defaut;
    $r['demande'] = $chemin;
    return $r;
}

/** Le mot sur le disque, dit tel quel (écran, alerte, message de tâche). */
function sigh_sauv_mot_disque(?bool $memeDisque): string
{
    if ($memeDisque === true) {
        return 'Même disque que les données : cette copie ne protège PAS d’une panne de disque. Désigner un autre disque ou un partage réseau.';
    }
    if ($memeDisque === null) {
        return 'Le serveur ne peut pas dire si la destination est sur un autre disque que les données : à vérifier.';
    }
    return 'Autre disque que les données.';
}

/** L'état lu par l'écran des tâches (le serveur calcule, l'écran n'invente rien). */
function sigh_sauv_etat(PDO $pdo): array
{
    $d = sigh_sauv_destination($pdo);
    return [
        'destination' => $d['ok'] ? $d['chemin'] : $d['demande'],
        'defaut' => $d['defaut'],
        'ok' => $d['ok'],
        'memeDisque' => $d['ok'] ? $d['memeDisque'] : null,
        'code' => $d['ok'] ? null : $d['code'],
        'motif' => $d['ok'] ? null : $d['motif'],
        'geste' => $d['ok'] ? null : $d['geste'],
        'mot' => $d['ok'] ? sigh_sauv_mot_disque($d['memeDisque']) : null,
        'dossierFichiers' => sigh_fichiers_racine(),
        'dossierPresent' => is_dir(sigh_fichiers_racine()),
    ];
}

/** Le temps accordé à une passe de copie : sans limite pour le planificateur du système, borné quand c'est une requête de poste (le serveur intégré de PHP n'a qu'un processus). */
function sigh_sauv_budget(string $origine): ?float
{
    if ($origine === 'systeme') { return null; }
    $b = getenv('SIGH_SAUVEGARDE_BUDGET_S');
    return is_string($b) && is_numeric($b) ? (float) $b : 15.0;
}

/* --------------------------------------------------------------------------
 * L'INVENTAIRE D'UN DOSSIER DE FICHIERS (la source, ou la sauvegarde)
 * ------------------------------------------------------------------------ */
function sigh_sauv_inventaire(string $racine): array
{
    $out = ['existe' => is_dir($racine), 'fichiers' => [], 'fiches' => [], 'intrus' => [], 'octets' => 0];
    if (!$out['existe']) { return $out; }
    foreach (scandir($racine) ?: [] as $aa) {
        if (!preg_match('/^[0-9a-f]{2}$/', $aa) || !is_dir($racine . '/' . $aa)) { continue; }
        foreach (scandir($racine . '/' . $aa) ?: [] as $f) {
            if ($f === '.' || $f === '..') { continue; }
            $chemin = $racine . '/' . $aa . '/' . $f;
            if (preg_match('/^([0-9a-f]{64})\.(pdf|jpg|png|webp)$/', $f, $m)) {
                if (substr($m[1], 0, 2) !== $aa) { $out['intrus'][] = $aa . '/' . $f; continue; }
                $t = (int) @filesize($chemin);
                $out['fichiers'][$m[1]] = ['ext' => $m[2], 'chemin' => $chemin, 'taille' => $t];
                $out['octets'] += $t;
            } elseif (preg_match('/^([0-9a-f]{64})\.json$/', $f, $m)) {
                $out['fiches'][$m[1]] = $chemin;
            }
        }
    }
    ksort($out['fichiers']);
    return $out;
}

/** Une fiche d'accompagnement saine : un objet JSON dont l'empreinte est celle du nom. */
function sigh_sauv_fiche_saine(string $chemin, string $sha): bool
{
    $j = json_decode((string) @file_get_contents($chemin), true);
    return is_array($j) && ($j['sha256'] ?? '') === $sha;
}

/**
 * COPIE UN FICHIER en recalculant son empreinte SUR LES OCTETS COPIÉS, jamais sur une lecture à part (un fichier qui change entre le calcul et la copie ne passerait pas).
 * Écrit dans un `.tmp`, relit la copie, compare, et SEULEMENT ALORS la pose sous son nom définitif. Rend { ok } ou { ok:false, etat : altere | illisible | ecriture | copie_differente }.
 */
function sigh_sauv_copier(string $src, string $cible, string $attendu, bool $remplacer = false): array
{
    $in = @fopen($src, 'rb');
    if (!$in) { return ['ok' => false, 'etat' => 'illisible']; }
    @mkdir(dirname($cible), 0775, true);
    $tmp = $cible . '.' . bin2hex(random_bytes(4)) . '.tmp';
    $out = @fopen($tmp, 'wb');
    if (!$out) { fclose($in); return ['ok' => false, 'etat' => 'ecriture']; }
    $h = hash_init('sha256');
    $n = 0;
    $court = false;
    while (!feof($in)) {
        $b = fread($in, 1048576);
        if ($b === false) { $court = true; break; }
        if ($b === '') { continue; }
        hash_update($h, $b);
        if (@fwrite($out, $b) !== strlen($b)) { $court = true; break; }
        $n += strlen($b);
    }
    fclose($in);
    $ferme = @fclose($out);
    if ($court || !$ferme) { @unlink($tmp); return ['ok' => false, 'etat' => 'ecriture']; }
    if (hash_final($h) !== $attendu) { @unlink($tmp); return ['ok' => false, 'etat' => 'altere']; }
    if (hash_file('sha256', $tmp) !== $attendu) { @unlink($tmp); return ['ok' => false, 'etat' => 'copie_differente']; }
    if ($remplacer && is_file($cible)) { @unlink($cible); }
    if (!@rename($tmp, $cible)) { @unlink($tmp); return ['ok' => false, 'etat' => 'ecriture']; }
    return ['ok' => true, 'octets' => $n];
}

/** Copie une fiche d'accompagnement (petit fichier mutable : ses usages se cumulent), atomiquement. */
function sigh_sauv_copier_fiche(string $src, string $cible): bool
{
    $contenu = @file_get_contents($src);
    if ($contenu === false) { return false; }
    @mkdir(dirname($cible), 0775, true);
    $tmp = $cible . '.' . bin2hex(random_bytes(4)) . '.tmp';
    if (@file_put_contents($tmp, $contenu) !== strlen($contenu)) { @unlink($tmp); return false; }
    if (is_file($cible)) { @unlink($cible); }
    if (!@rename($tmp, $cible)) { @unlink($tmp); return false; }
    return true;
}

/* --------------------------------------------------------------------------
 * LA SAUVEGARDE : incrémentale, vérifiée, jamais tournante
 * ------------------------------------------------------------------------ */
function sigh_sauv_sauvegarder(array $dest, ?float $budget = null, ?int $auj = null): array
{
    $debut = microtime(true);
    $src = sigh_fichiers_racine();
    $inv = sigh_sauv_inventaire($src);
    $rap = [
        'source' => $src, 'destination' => $dest['chemin'], 'memeDisque' => $dest['memeDisque'] ?? null,
        'totalSource' => count($inv['fichiers']), 'octetsSource' => $inv['octets'],
        'dejaPresents' => 0, 'copies' => 0, 'octetsCopies' => 0, 'reparees' => 0, 'restants' => 0,
        'alteres' => [], 'illisibles' => [], 'echecs' => [],
        'fiches' => ['copiees' => 0, 'illisibles' => []], 'manifeste' => null, 'liste' => [], 'rienACopier' => false,
    ];
    if (!$inv['fichiers'] && !$inv['fiches']) {
        $rap['rienACopier'] = true;
        return $rap;
    }
    $racineDest = $dest['chemin'] . '/fichiers';
    $traites = 0;
    foreach ($inv['fichiers'] as $sha => $f) {
        $cible = $racineDest . '/' . substr($sha, 0, 2) . '/' . $sha . '.' . $f['ext'];
        $existe = is_file($cible);
        if ($existe && (int) filesize($cible) === $f['taille']) {
            $rap['dejaPresents']++;
            $rap['liste'][] = [$sha, $f['ext'], $f['taille']];
            continue;
        }
        /* Au moins UN fichier par passe (la copie avance toujours), puis le temps accordé borne le reste : ce qui n'est pas copié l'est à la passe suivante. */
        if ($budget !== null && $traites > 0 && (microtime(true) - $debut) > $budget) {
            $rap['restants']++;
            continue;
        }
        $traites++;
        $c = sigh_sauv_copier($f['chemin'], $cible, $sha, $existe);
        if ($c['ok']) {
            $rap['copies']++;
            $rap['octetsCopies'] += $c['octets'];
            if ($existe) { $rap['reparees']++; }
            $rap['liste'][] = [$sha, $f['ext'], $f['taille']];
        } elseif ($c['etat'] === 'altere') {
            /* La source n'a plus son empreinte : elle n'est PAS copiée. On dit si la sauvegarde en garde une copie saine. */
            $saine = $existe ? (hash_file('sha256', $cible) === $sha) : false;
            $rap['alteres'][] = ['sha256' => $sha, 'ext' => $f['ext'], 'taille' => $f['taille'], 'sauvegardeSaine' => $saine];
            if ($saine) { $rap['liste'][] = [$sha, $f['ext'], $f['taille']]; }
        } elseif ($c['etat'] === 'illisible') {
            $rap['illisibles'][] = ['sha256' => $sha, 'ext' => $f['ext']];
        } else {
            $rap['echecs'][] = ['sha256' => $sha, 'ext' => $f['ext'], 'etat' => $c['etat']];
        }
    }
    foreach ($inv['fiches'] as $sha => $chemin) {
        $cible = $racineDest . '/' . substr($sha, 0, 2) . '/' . $sha . '.json';
        if (!sigh_sauv_fiche_saine($chemin, $sha)) { $rap['fiches']['illisibles'][] = $sha; continue; }
        if (is_file($cible) && @file_get_contents($cible) === @file_get_contents($chemin)) { continue; }
        if (sigh_sauv_copier_fiche($chemin, $cible)) { $rap['fiches']['copiees']++; } else { $rap['echecs'][] = ['sha256' => $sha, 'ext' => 'json', 'etat' => 'ecriture']; }
    }
    /* Le manifeste daté, à côté de celui du magasin. */
    $jour = gmdate('Y-m-d', ($auj ?? (int) floor(time() / 86400)) * 86400);
    $manifeste = [
        'version' => 1, 'date' => $jour, 'genereLe' => gmdate('c'),
        'source' => ['dossier' => $src, 'fichiers' => $rap['totalSource'], 'octets' => $rap['octetsSource']],
        'destination' => ['dossier' => $dest['chemin'], 'memeDisque' => $rap['memeDisque']],
        'totalSauvegardes' => count($rap['liste']), 'dejaPresents' => $rap['dejaPresents'], 'copies' => $rap['copies'], 'octetsCopies' => $rap['octetsCopies'],
        'reparees' => $rap['reparees'], 'restants' => $rap['restants'], 'alteres' => $rap['alteres'], 'illisibles' => $rap['illisibles'], 'echecs' => $rap['echecs'],
        'fichesCopiees' => $rap['fiches']['copiees'], 'fichesIllisibles' => $rap['fiches']['illisibles'],
        'fichiers' => $rap['liste'],
    ];
    $nom = $dest['chemin'] . '/fichiers-' . $jour . '.json.gz';
    $tmp = $nom . '.' . bin2hex(random_bytes(4)) . '.tmp';
    $ecrit = @file_put_contents($tmp, gzencode(json_encode($manifeste, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES), 6));
    if ($ecrit !== false) {
        if (is_file($nom)) { @unlink($nom); }
        if (@rename($tmp, $nom)) { $rap['manifeste'] = $nom; } else { @unlink($tmp); }
    }
    if ($rap['manifeste'] === null) {
        $rap['echecs'][] = ['sha256' => '', 'ext' => 'manifeste', 'etat' => 'ecriture'];
    }
    return $rap;
}

function sigh_sauv_resume_sauvegarde(array $r): string
{
    if (!empty($r['rienACopier'])) {
        return 'Rien à copier : le dossier des fichiers numérisés est vide ou n’existe pas encore.';
    }
    $t = $r['totalSource'] . ' fichier(s) à la source (' . sigh_sauv_poids($r['octetsSource']) . ') : ' . $r['dejaPresents'] . ' déjà sauvegardé(s), '
        . $r['copies'] . ' copié(s) (' . sigh_sauv_poids($r['octetsCopies']) . '), ' . count($r['alteres']) . ' altéré(s) non copié(s)';
    if ($r['restants'] > 0) { $t .= ', ' . $r['restants'] . ' restant(s) pour la prochaine passe'; }
    if ($r['echecs']) { $t .= ', ' . count($r['echecs']) . ' échec(s) d’écriture'; }
    return $t . '. Destination : ' . $r['destination'] . ' (' . ($r['memeDisque'] === true ? 'même disque que les données' : ($r['memeDisque'] === null ? 'disque indéterminé' : 'autre disque')) . ').';
}

/* --------------------------------------------------------------------------
 * LES RÉFÉRENCES : ce que le magasin dit posséder
 * ------------------------------------------------------------------------ */
function sigh_sauv_collection(PDO $pdo, string $nom): array
{
    $q = $pdo->prepare('SELECT donnees FROM collections WHERE nom = ?');
    $q->execute([$nom]);
    $d = $q->fetchColumn();
    $o = $d ? json_decode((string) $d, true) : [];
    return is_array($o) ? $o : [];
}

/** Les trois collections qui portent une empreinte : le registre `fichiers`, les courriers et les documents du patient. Les fiches ARCHIVÉES comptent (RG-14 : elles gardent leur pièce). */
function sigh_sauv_collections(PDO $pdo): array
{
    $c = [];
    foreach (['fichiers', 'courriers', 'documentsPatient'] as $nom) {
        $c[$nom] = sigh_sauv_collection($pdo, $nom);
    }
    return $c;
}

/** sha256 => { registre, fiches } pour chaque empreinte référencée, pièces retirées comprises (elles restent à l'historique, donc sur le disque). */
function sigh_sauv_references(array $collections): array
{
    $refs = [];
    $noter = function ($sha, $cle) use (&$refs) {
        if (is_string($sha) && preg_match('/^[0-9a-f]{64}$/', $sha)) {
            $refs[$sha] = $refs[$sha] ?? ['registre' => false, 'fiches' => 0];
            $refs[$sha][$cle] = $cle === 'fiches' ? $refs[$sha]['fiches'] + 1 : true;
        }
    };
    foreach ((array) ($collections['fichiers'] ?? []) as $f) {
        if (is_array($f)) { $noter($f['sha256'] ?? null, 'registre'); }
    }
    foreach (['courriers', 'documentsPatient'] as $nom) {
        foreach ((array) ($collections[$nom] ?? []) as $f) {
            if (!is_array($f)) { continue; }
            if (is_array($f['fichier'] ?? null)) { $noter($f['fichier']['sha256'] ?? null, 'fiches'); }
            foreach ((array) ($f['fichiersRetires'] ?? []) as $x) {
                if (is_array($x)) { $noter($x['sha256'] ?? null, 'fiches'); }
            }
        }
    }
    return $refs;
}

/* --------------------------------------------------------------------------
 * LE CONTRÔLE D'INTÉGRITÉ : relit tout, ne corrige rien, ne supprime rien
 * ------------------------------------------------------------------------ */
function sigh_sauv_controler(array $collections, ?array $dest = null): array
{
    $refs = sigh_sauv_references($collections);
    $inv = sigh_sauv_inventaire(sigh_fichiers_racine());
    $r = ['dossier' => sigh_fichiers_racine(), 'dossierPresent' => $inv['existe'], 'references' => count($refs), 'surDisque' => count($inv['fichiers']), 'relus' => 0, 'octets' => 0,
        'manquants' => [], 'divergents' => [], 'orphelins' => [], 'sansFiche' => [], 'intrus' => $inv['intrus'],
        'nonSauvegardes' => [], 'copiesAlterees' => [], 'sauvegardeVerifiee' => false];
    foreach ($refs as $sha => $info) {
        if (!isset($inv['fichiers'][$sha])) { $r['manquants'][] = ['sha256' => $sha, 'registre' => $info['registre'], 'fiches' => $info['fiches']]; }
    }
    $racineDest = $dest ? $dest['chemin'] . '/fichiers' : null;
    foreach ($inv['fichiers'] as $sha => $f) {
        $r['relus']++;
        $r['octets'] += $f['taille'];
        $intact = hash_file('sha256', $f['chemin']) === $sha;
        if (!$intact) { $r['divergents'][] = ['sha256' => $sha, 'ext' => $f['ext'], 'taille' => $f['taille'], 'reference' => isset($refs[$sha])]; }
        if (!isset($refs[$sha])) { $r['orphelins'][] = ['sha256' => $sha, 'ext' => $f['ext'], 'taille' => $f['taille']]; }
        if (!isset($inv['fiches'][$sha])) { $r['sansFiche'][] = ['sha256' => $sha, 'ext' => $f['ext']]; }
        if ($racineDest !== null && $intact) {
            $copie = $racineDest . '/' . substr($sha, 0, 2) . '/' . $sha . '.' . $f['ext'];
            if (!is_file($copie)) { $r['nonSauvegardes'][] = ['sha256' => $sha, 'ext' => $f['ext']]; }
            elseif (hash_file('sha256', $copie) !== $sha) { $r['copiesAlterees'][] = ['sha256' => $sha, 'ext' => $f['ext']]; }
        }
    }
    $r['sauvegardeVerifiee'] = $racineDest !== null;
    return $r;
}

function sigh_sauv_resume_controle(array $r): string
{
    if (!$r['dossierPresent'] && !$r['references']) {
        return 'Rien à contrôler : aucun fichier numérisé n’est référencé et le dossier des fichiers n’existe pas encore.';
    }
    $t = $r['relus'] . ' fichier(s) relu(s) (' . sigh_sauv_poids($r['octets']) . ') pour ' . $r['references'] . ' référence(s) du magasin : '
        . count($r['manquants']) . ' manquant(s), ' . count($r['divergents']) . ' altéré(s), ' . count($r['orphelins']) . ' sans fiche (orphelin(s), conservés), '
        . count($r['sansFiche']) . ' sans fiche d’accompagnement.';
    if ($r['sauvegardeVerifiee']) {
        $t .= ' Sauvegarde : ' . count($r['nonSauvegardes']) . ' non sauvegardé(s), ' . count($r['copiesAlterees']) . ' copie(s) altérée(s).';
    }
    return $t;
}

/* --------------------------------------------------------------------------
 * LA RESTAURATION : vérifier avant de poser, ne jamais écraser un fichier intact
 * ------------------------------------------------------------------------ */
function sigh_sauv_restaurer(array $collections, string $destination, bool $appliquer): array
{
    $srcRoot = sigh_fichiers_racine();
    $invD = sigh_sauv_inventaire($destination . '/fichiers');
    $invS = sigh_sauv_inventaire($srcRoot);
    $refs = sigh_sauv_references($collections);
    $maintenant = gmdate('Ymd-His');
    $r = ['appliquer' => $appliquer, 'destination' => $destination, 'dossier' => $srcRoot, 'restaures' => [], 'dejaPresents' => 0, 'remplaces' => [], 'alteresSauvegarde' => [],
        'introuvables' => [], 'octets' => 0, 'echecs' => [],
        'fiches' => ['restaurees' => 0, 'dejaPresentes' => 0, 'remplacees' => 0, 'illisibles' => []]];
    foreach ($invD['fichiers'] as $sha => $f) {
        $cible = $srcRoot . '/' . substr($sha, 0, 2) . '/' . $sha . '.' . $f['ext'];
        $surDisque = $invS['fichiers'][$sha]['chemin'] ?? null;
        $aReplacer = false;
        if ($surDisque !== null) {
            if (hash_file('sha256', $surDisque) === $sha) {
                $r['dejaPresents']++;   /* présent et intact : JAMAIS écrasé */
                continue;
            }
            $aReplacer = true;
        }
        /* La copie est vérifiée AVANT d'être posée, et avant que l'altéré de la source soit mis de côté : une copie altérée n'est jamais posée. */
        if (hash_file('sha256', $f['chemin']) !== $sha) {
            $r['alteresSauvegarde'][] = ['sha256' => $sha, 'ext' => $f['ext'], 'surDisqueAltere' => $aReplacer];
            continue;
        }
        if ($aReplacer) {
            $quarantaine = $srcRoot . '/_alteres/' . $sha . '.' . $f['ext'] . '.' . $maintenant;
            $r['remplaces'][] = ['sha256' => $sha, 'ext' => $f['ext'], 'misDeCote' => '_alteres/' . basename($quarantaine)];
            if ($appliquer) {
                @mkdir(dirname($quarantaine), 0775, true);
                if (!@rename($surDisque, $quarantaine)) { $r['echecs'][] = ['sha256' => $sha, 'ext' => $f['ext'], 'etat' => 'mise_de_cote']; array_pop($r['remplaces']); continue; }
            }
        } else {
            $r['restaures'][] = ['sha256' => $sha, 'ext' => $f['ext'], 'taille' => $f['taille']];
        }
        if ($appliquer) {
            $c = sigh_sauv_copier($f['chemin'], $cible, $sha);
            if (!$c['ok']) {
                if ($c['etat'] === 'altere' || $c['etat'] === 'copie_differente') {
                    $r['alteresSauvegarde'][] = ['sha256' => $sha, 'ext' => $f['ext'], 'surDisqueAltere' => $aReplacer];
                } else {
                    $r['echecs'][] = ['sha256' => $sha, 'ext' => $f['ext'], 'etat' => $c['etat']];
                }
                if ($aReplacer) { array_pop($r['remplaces']); } else { array_pop($r['restaures']); }
                continue;
            }
            $r['octets'] += $c['octets'];
        } else {
            $r['octets'] += $f['taille'];
        }
    }
    /* Les fiches d'accompagnement (usages, zone) : sans elles, la règle de lecture par famille et par zone ne s'applique plus (RG-13). */
    foreach ($invD['fiches'] as $sha => $chemin) {
        $cible = $srcRoot . '/' . substr($sha, 0, 2) . '/' . $sha . '.json';
        if (!sigh_sauv_fiche_saine($chemin, $sha)) { $r['fiches']['illisibles'][] = $sha; continue; }
        if (is_file($cible)) {
            if (sigh_sauv_fiche_saine($cible, $sha)) { $r['fiches']['dejaPresentes']++; continue; }
            $r['fiches']['remplacees']++;
            if ($appliquer) {
                $q = $srcRoot . '/_alteres/' . $sha . '.json.' . $maintenant;
                @mkdir(dirname($q), 0775, true);
                @rename($cible, $q);
                sigh_sauv_copier_fiche($chemin, $cible);
            }
            continue;
        }
        $r['fiches']['restaurees']++;
        if ($appliquer && !sigh_sauv_copier_fiche($chemin, $cible)) { $r['echecs'][] = ['sha256' => $sha, 'ext' => 'json', 'etat' => 'ecriture']; $r['fiches']['restaurees']--; }
    }
    /* Introuvables : référencés par le magasin, absents du disque ET de la sauvegarde (ou présents mais altérés dans la sauvegarde, donc non posés). */
    $alteresSha = array_column($r['alteresSauvegarde'], 'sha256');
    foreach ($refs as $sha => $info) {
        if (isset($invS['fichiers'][$sha]) || isset($invD['fichiers'][$sha])) { continue; }
        $r['introuvables'][] = ['sha256' => $sha];
    }
    foreach ($alteresSha as $sha) {
        if (!isset($invS['fichiers'][$sha]) && isset($refs[$sha])) { $r['introuvables'][] = ['sha256' => $sha, 'copieAltereeSeulement' => true]; }
    }
    return $r;
}
