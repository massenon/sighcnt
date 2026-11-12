<?php
/* =============================================================================
 * SIGH-CNT : les FICHIERS (scans de courriers, documents du dossier patient), hors du magasin
 * -----------------------------------------------------------------------------
 * Un scan de 500 Ko en base64 pèse 683 Ko dans le magasin JSON, et le magasin ENTIER est relu à chaque chargement de page par chaque poste
 * (mesure D0 du plan documents numérisés : dix scans, +124 % de poids). Le fichier vit donc ICI, dans un dossier que git ignore ; le magasin
 * ne garde que les métadonnées (empreinte, nom, type, taille, pages).
 *
 * POST ?action=deposer&famille=courrier|patient&nom=…[&type=…][&sha256=…]   corps = les octets du fichier
 * GET  ?action=lire&sha256=…&famille=…[&nom=…][&usage=apercu|telechargement]  rend les octets
 * GET  ?action=chemin&sha256=…&famille=…                                      dit où le fichier est rangé sur CE poste
 *
 * CE QUI EST GARANTI ICI, ET CE QUI NE L'EST PAS :
 *   - une SESSION est obligatoire pour tout (RG-12) ; l'empreinte SHA-256 est recalculée par le SERVEUR (celle que le client annonce n'est
 *     qu'une promesse qu'on vérifie), et recalculée à CHAQUE LECTURE : un fichier altéré sur le disque n'est jamais servi ;
 *   - une règle PAR FAMILLE, engendrée de `rbac.json` (api/regles-fichiers.json) : courrier = droits sur m13-courriers, patient = droits sur
 *     m1-documents ET zone du type du document (un profil non clinique ne lit pas une pièce de zone 2) ;
 *   - chaque dépôt, lecture et refus est écrit dans `acces_fichiers` (qui, quand, quelle empreinte), en plus du journal de l'écran ;
 *   - LIMITE : la matrice complète des droits vit toujours côté navigateur. La règle d'ici est la matrice d'ORIGINE, par famille : une fiche
 *     RBAC corrigée à chaud n'y est pas lue. Le pas suivant est de porter la matrice en PHP.
 *
 * Aucune suppression physique, jamais (RG-14, conservation illimitée : réponse Q6 de la Direction du 11/11/2026).
 * ========================================================================== */

require_once __DIR__ . '/_commun.php';
require_once __DIR__ . '/_pdf_texte.php';

header('Access-Control-Allow-Origin: ' . ($_SERVER['HTTP_ORIGIN'] ?? '*'));
header('Access-Control-Allow-Credentials: true');
header('Access-Control-Allow-Headers: Content-Type, X-Sigh-Jeton');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Expose-Headers: X-Sigh-Empreinte, Content-Disposition');
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    sigh_repondre(['ok' => true]);
}

/** Refus NOMMÉ : un code, un motif lisible, le geste de correction. */
function sigh_fichiers_refus(int $statut, string $code, string $motif, string $geste, array $plus = []): void
{
    sigh_repondre(array_merge(['ok' => false, 'erreur' => $code, 'code' => $code, 'motif' => $motif, 'geste' => $geste], $plus), $statut);
}

function sigh_fichiers_dossier(): string
{
    $d = sigh_fichiers_racine();
    if (!is_dir($d)) {
        @mkdir($d, 0775, true);
    }
    return $d;
}

function sigh_fichiers_regles(): array
{
    static $r = null;
    if ($r === null) {
        $f = __DIR__ . '/regles-fichiers.json';
        $r = is_file($f) ? (json_decode((string) file_get_contents($f), true) ?: []) : [];
    }
    return $r;
}

/** Le droit d'un rôle sur une famille. Retourne null si permis, sinon [code, motif, geste]. */
function sigh_fichiers_droit(string $role, string $famille, string $geste, ?string $type): ?array
{
    $regles = sigh_fichiers_regles();
    $idx = ['voir' => 0, 'editer' => 1, 'annuler' => 2][$geste] ?? 0;
    $droits = $regles['roles'][$role][$famille] ?? [0, 0, 0];
    if (empty($droits[$idx])) {
        $ecran = $regles['familles'][$famille] ?? $famille;
        return ['DROIT_REFUSE', 'le profil « ' . $role . ' » n’a pas le droit de ' . ($geste === 'voir' ? 'lire' : 'déposer') . ' sur l’écran « ' . $ecran . ' »',
            'Demander ce droit à l’administrateur (« Rôles & permissions »).'];
    }
    if ($famille === 'patient') {
        $zone = (int) ($regles['types'][(string) $type] ?? 2);
        if ($zone >= 2 && !in_array($role, $regles['zone2'] ?? [], true)) {
            return ['ZONE_REFUSEE', 'le profil « ' . $role . ' » ne lit ni ne dépose les pièces médicales du dossier patient (RG-13)',
                'Seuls les profils cliniques traitent ce type de pièce ; l’accueil dépose la pièce d’identité et la carte d’assurance.'];
        }
    }
    return null;
}

function sigh_fichiers_journal(PDO $pdo, ?array $s, string $action, string $famille, string $sha, bool $ok, ?string $motif): void
{
    try {
        if (sigh_est_postgres()) {
            $pdo->exec('CREATE TABLE IF NOT EXISTS acces_fichiers (id BIGSERIAL PRIMARY KEY, quand TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                identifiant VARCHAR(64), nom VARCHAR(128), role VARCHAR(48), action VARCHAR(24) NOT NULL, famille VARCHAR(16), sha256 VARCHAR(64), ok BOOLEAN NOT NULL, motif VARCHAR(255))');
        } else {
            $pdo->exec('CREATE TABLE IF NOT EXISTS acces_fichiers (id BIGINT AUTO_INCREMENT PRIMARY KEY, quand DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                identifiant VARCHAR(64), nom VARCHAR(128), role VARCHAR(48), action VARCHAR(24) NOT NULL, famille VARCHAR(16), sha256 VARCHAR(64), ok TINYINT(1) NOT NULL, motif VARCHAR(255)) ENGINE=InnoDB');
        }
        $pdo->prepare('INSERT INTO acces_fichiers (identifiant, nom, role, action, famille, sha256, ok, motif) VALUES (?, ?, ?, ?, ?, ?, ?, ?)')
            ->execute([$s['identifiant'] ?? null, $s['nom'] ?? null, $s['role'] ?? null, $action, $famille, $sha, $ok ? 1 : 0, $motif ? mb_substr($motif, 0, 250) : null]);
    } catch (Throwable $e) {
        /* Le journal ne doit jamais faire échouer la lecture ; l'échec se dit au journal d'erreurs du serveur. */
        error_log('[SIGH] journal des fichiers : ' . $e->getMessage());
    }
}

/** La taille maximale réglée par la clinique (octets), sinon le défaut ; toujours bornée par le plafond. */
function sigh_fichiers_taille_max(PDO $pdo): int
{
    $regles = sigh_fichiers_regles();
    $max = (int) ($regles['tailleDefaut'] ?? 10485760);
    try {
        $q = $pdo->prepare('SELECT valeur FROM meta WHERE cle = ?');
        $q->execute(['_reglages']);
        $v = $q->fetchColumn();
        if ($v) {
            $r = json_decode((string) $v, true);
            $x = $r['documentsBornes']['tailleMax'] ?? null;
            if (is_numeric($x) && $x > 0) {
                $max = (int) $x;
            }
        }
    } catch (Throwable $e) {
        /* meta absente : le défaut s'applique */
    }
    return min($max, (int) ($regles['taillePlafond'] ?? 67108864));
}

/** Détecte le format par les premiers octets, jamais par ce que le client déclare. */
function sigh_fichiers_format(string $octets): ?array
{
    if (strncmp($octets, '%PDF-', 5) === 0) { return ['id' => 'pdf', 'mime' => 'application/pdf', 'ext' => 'pdf']; }
    if (strncmp($octets, "\xFF\xD8\xFF", 3) === 0) { return ['id' => 'jpeg', 'mime' => 'image/jpeg', 'ext' => 'jpg']; }
    if (strncmp($octets, "\x89PNG\r\n\x1a\n", 8) === 0) { return ['id' => 'png', 'mime' => 'image/png', 'ext' => 'png']; }
    if (strncmp($octets, 'RIFF', 4) === 0 && substr($octets, 8, 4) === 'WEBP') { return ['id' => 'webp', 'mime' => 'image/webp', 'ext' => 'webp']; }
    return null;
}

function sigh_fichiers_chemin(string $sha, ?string $ext = null): string
{
    $dir = sigh_fichiers_dossier() . '/' . substr($sha, 0, 2);
    if ($ext !== null) {
        return $dir . '/' . $sha . '.' . $ext;
    }
    foreach (['pdf', 'jpg', 'png', 'webp'] as $e) {
        if (is_file($dir . '/' . $sha . '.' . $e)) { return $dir . '/' . $sha . '.' . $e; }
    }
    return $dir . '/' . $sha . '.bin';
}

function sigh_fichiers_sha_valide(string $sha): bool
{
    return (bool) preg_match('/^[0-9a-f]{64}$/', $sha);
}

try {
    $pdo = sigh_pdo();
    sigh_installer($pdo);
} catch (Throwable $e) {
    sigh_repondre(['erreur' => 'base indisponible', 'detail' => $e->getMessage()], 503);
}

$methode = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$action = (string) ($_GET['action'] ?? '');
$session = sigh_session($pdo);
if ($session === null) {
    sigh_fichiers_refus(401, 'SESSION_REQUISE', 'aucune session de poste ouverte', 'Ouvrir une session (api/auth.php) avant de déposer ou de lire un fichier (RG-12).');
}
$role = (string) ($session['role'] ?? '');
$famille = (string) ($_GET['famille'] ?? '');

/* Le JOURNAL SERVEUR (qui, quand, quelle empreinte) se relit : réservé à l'administrateur, comme toute lecture de trace. */
if ($methode === 'GET' && $action === 'journal') {
    if ($role !== 'admin') {
        sigh_fichiers_refus(403, 'DROIT_REFUSE', 'le journal des accès aux fichiers est réservé à l’administrateur', 'Demander la lecture à l’administrateur.');
    }
    $sha = strtolower((string) ($_GET['sha256'] ?? ''));
    try {
        $q = $pdo->prepare('SELECT quand, identifiant, nom, role, action, famille, sha256, ok, motif FROM acces_fichiers WHERE (? = \'\' OR sha256 = ?) ORDER BY id DESC LIMIT 100');
        $q->execute([$sha, $sha]);
        sigh_repondre(['ok' => true, 'lignes' => $q->fetchAll()]);
    } catch (Throwable $e) {
        sigh_repondre(['ok' => true, 'lignes' => []]);
    }
}

if (!in_array($famille, ['courrier', 'patient'], true)) {
    sigh_fichiers_refus(400, 'FAMILLE_INCONNUE', 'la famille « ' . $famille . ' » n’existe pas', 'Indiquer courrier ou patient.');
}

/* --------------------------------------------------------------------------
 * DÉPÔT
 * ------------------------------------------------------------------------ */
if ($methode === 'POST' && $action === 'deposer') {
    $type = isset($_GET['type']) ? (string) $_GET['type'] : null;
    $nom = (string) ($_GET['nom'] ?? 'fichier');
    $refus = sigh_fichiers_droit($role, $famille, 'editer', $type);
    if ($refus) {
        sigh_fichiers_journal($pdo, $session, 'depot', $famille, '', false, $refus[1]);
        sigh_fichiers_refus(403, $refus[0], $refus[1], $refus[2]);
    }
    $octets = (string) file_get_contents('php://input');
    $taille = strlen($octets);
    if ($taille === 0) {
        sigh_fichiers_refus(400, 'FICHIER_VIDE', 'le fichier ne contient aucun octet', 'Choisir un fichier numérisé non vide.');
    }
    $max = sigh_fichiers_taille_max($pdo);
    if ($taille > $max) {
        sigh_fichiers_journal($pdo, $session, 'depot', $famille, '', false, 'taille dépassée');
        sigh_fichiers_refus(413, 'TAILLE_DEPASSEE', 'le fichier pèse ' . round($taille / 1048576, 1) . ' Mo, le maximum réglé est ' . round($max / 1048576, 1) . ' Mo',
            'Numériser en résolution plus basse, ou demander à l’administrateur de relever la taille maximale.');
    }
    $fmt = sigh_fichiers_format($octets);
    $regles = sigh_fichiers_regles();
    $admis = [];
    foreach (($regles['formats'] ?? []) as $f) { if (in_array($famille, $f['familles'], true)) { $admis[] = $f['id']; } }
    if ($fmt === null || !in_array($fmt['id'], $admis, true)) {
        sigh_fichiers_journal($pdo, $session, 'depot', $famille, '', false, 'format refusé');
        sigh_fichiers_refus(415, 'FORMAT_REFUSE', 'le contenu du fichier n’est pas un format admis (' . strtoupper(implode(', ', $admis)) . ')',
            'Enregistrer la numérisation en PDF, JPEG ou PNG' . ($famille === 'patient' ? ' (WEBP admis au dossier patient)' : '') . '.');
    }
    $sha = hash('sha256', $octets);
    $annonce = strtolower((string) ($_GET['sha256'] ?? ''));
    if ($annonce !== '' && $annonce !== $sha) {
        sigh_fichiers_journal($pdo, $session, 'depot', $famille, $sha, false, 'empreinte divergente');
        sigh_fichiers_refus(409, 'EMPREINTE_DIVERGENTE', 'le fichier reçu n’a pas l’empreinte annoncée (transport altéré)', 'Déposer de nouveau le fichier.',
            ['recu' => $sha, 'annonce' => $annonce]);
    }
    $chemin = sigh_fichiers_chemin($sha, $fmt['ext']);
    @mkdir(dirname($chemin), 0775, true);
    /* Le fichier existe déjà sous cette empreinte ? On vérifie qu'il est intact, sinon on le RÉPARE avec les octets reçus. */
    if (!is_file($chemin) || hash_file('sha256', $chemin) !== $sha) {
        $aEcrire = $octets;
        if (getenv('SIGH_BANC') === '1' && is_file(sigh_fichiers_dossier() . '/.alterer-depot')) {
            $aEcrire[strlen($aEcrire) - 1] = chr(ord($aEcrire[strlen($aEcrire) - 1]) ^ 0xFF);   /* altération de BANC : le disque ne garde pas ce qu'on lui donne */
        }
        $tmp = $chemin . '.' . bin2hex(random_bytes(4)) . '.tmp';
        if (file_put_contents($tmp, $aEcrire) === false || !@rename($tmp, $chemin)) {
            @unlink($tmp);
            sigh_fichiers_refus(500, 'ECRITURE_IMPOSSIBLE', 'le serveur n’a pas pu ranger le fichier', 'Vérifier les droits d’écriture du dossier des fichiers.');
        }
    }
    /* La fiche d'accompagnement : les usages (famille, zone) sont CUMULÉS, la lecture applique le plus strict. */
    $meta = [];
    $mf = sigh_fichiers_dossier() . '/' . substr($sha, 0, 2) . '/' . $sha . '.json';
    if (is_file($mf)) { $meta = json_decode((string) file_get_contents($mf), true) ?: []; }
    $zone = $famille === 'patient' ? (int) ($regles['types'][(string) $type] ?? 2) : 0;
    $usages = $meta['usages'] ?? [];
    $cle = $famille . ':' . $zone;
    $trouve = false;
    foreach ($usages as $u) { if (($u['famille'] ?? '') . ':' . ($u['zone'] ?? 0) === $cle) { $trouve = true; } }
    if (!$trouve) { $usages[] = ['famille' => $famille, 'zone' => $zone]; }
    $meta = array_merge($meta, ['sha256' => $sha, 'mime' => $fmt['mime'], 'ext' => $fmt['ext'], 'taille' => $taille, 'usages' => $usages]);
    if (empty($meta['premiereLe'])) { $meta['premiereLe'] = date('c'); $meta['deposePar'] = $session['nom'] ?? ($session['identifiant'] ?? 'inconnu'); }
    file_put_contents($mf, json_encode($meta, JSON_UNESCAPED_UNICODE));

    $pages = null; $texte = ['indexe' => false, 'mots' => [], 'raison' => null];
    if ($fmt['id'] === 'pdf') {
        try {
            $t = sigh_pdf_texte($octets);
            $pages = $t['pages'];
            $texte = $t;
        } catch (Throwable $e) {
            $texte['raison'] = 'extraction du texte en échec';
        }
    } else {
        $texte['raison'] = 'image sans couche texte';
    }
    $mots = $texte['mots'];
    $tronque = false;
    if (count($mots) > 4000) { $mots = array_slice($mots, 0, 4000); $tronque = true; }
    sigh_fichiers_journal($pdo, $session, 'depot', $famille, $sha, true, null);
    sigh_repondre([
        'ok' => true, 'sha256' => $sha, 'taille' => $taille, 'mime' => $fmt['mime'], 'format' => $fmt['id'], 'ext' => $fmt['ext'], 'nom' => $nom,
        'pages' => $pages, 'texteIndexe' => (bool) $texte['indexe'], 'mots' => $mots, 'motsTronques' => $tronque, 'raison' => $texte['raison'],
    ]);
}

/* --------------------------------------------------------------------------
 * LECTURE ET CHEMIN
 * ------------------------------------------------------------------------ */
if ($methode === 'GET' && ($action === 'lire' || $action === 'chemin')) {
    $sha = strtolower((string) ($_GET['sha256'] ?? ''));
    if (!sigh_fichiers_sha_valide($sha)) {
        sigh_fichiers_refus(400, 'EMPREINTE_INVALIDE', 'l’empreinte demandée n’est pas un SHA-256 (64 caractères hexadécimaux)', 'Ouvrir la pièce depuis sa fiche.');
    }
    $mf = sigh_fichiers_dossier() . '/' . substr($sha, 0, 2) . '/' . $sha . '.json';
    $meta = is_file($mf) ? (json_decode((string) file_get_contents($mf), true) ?: []) : [];
    $chemin = sigh_fichiers_chemin($sha, $meta['ext'] ?? null);
    $present = is_file($chemin);
    /* La règle de la famille D'ABORD, avant de dire si le fichier existe : un refus qui dirait « absent » renseignerait sur ce qui existe. */
    $familles = array_map(function ($u) { return $u['famille'] ?? ''; }, $meta['usages'] ?? []);
    $zoneMax = 0;
    foreach (($meta['usages'] ?? []) as $u) { if (($u['famille'] ?? '') === $famille) { $zoneMax = max($zoneMax, (int) ($u['zone'] ?? 0)); } }
    $typeFictif = $zoneMax >= 2 ? '__zone2__' : ($famille === 'patient' ? 'Pièce d’identité' : null);
    $refus = sigh_fichiers_droit($role, $famille, 'voir', $typeFictif);
    if (!$refus && $meta && !in_array($famille, $familles, true)) {
        $refus = ['PIECE_NON_RATTACHEE', 'cette empreinte n’est pas rattachée à la famille « ' . $famille . ' »', 'Ouvrir la pièce depuis la fiche qui la porte.'];
    }
    if ($refus) {
        sigh_fichiers_journal($pdo, $session, $action === 'chemin' ? 'chemin' : 'lecture', $famille, $sha, false, $refus[1]);
        sigh_fichiers_refus(403, $refus[0], $refus[1], $refus[2]);
    }
    if ($action === 'chemin') {
        sigh_repondre(['ok' => true, 'present' => $present, 'sha256' => $sha,
            'chemin' => $present ? str_replace('\\', '/', (string) realpath($chemin)) : null,
            'nomStockage' => $present ? basename($chemin) : null, 'taille' => $present ? filesize($chemin) : null]);
    }
    if (!$present) {
        sigh_fichiers_journal($pdo, $session, 'lecture', $famille, $sha, false, 'fichier absent');
        sigh_fichiers_refus(404, 'FICHIER_ABSENT', 'ce fichier n’est pas (encore) arrivé sur ce poste', 'Attendre la synchronisation des fichiers, ou redéposer le scan depuis la fiche.');
    }
    if (hash_file('sha256', $chemin) !== $sha) {
        sigh_fichiers_journal($pdo, $session, 'lecture', $famille, $sha, false, 'fichier altéré');
        sigh_fichiers_refus(409, 'FICHIER_ALTERE', 'le fichier rangé sur ce poste n’a plus son empreinte : il n’est pas servi', 'Redéposer le scan depuis la fiche (le fichier d’origine est conservé sur le poste du déposant).');
    }
    $usage = (string) ($_GET['usage'] ?? 'apercu') === 'telechargement' ? 'telechargement' : 'apercu';
    sigh_fichiers_journal($pdo, $session, $usage, $famille, $sha, true, null);
    $nomSortie = preg_replace('/[^A-Za-z0-9._-]+/', '_', (string) ($_GET['nom'] ?? ($sha . '.' . ($meta['ext'] ?? 'bin'))));
    $contenu = (string) file_get_contents($chemin);
    if (getenv('SIGH_BANC') === '1' && is_file(sigh_fichiers_dossier() . '/.alterer-lecture') && $contenu !== '') {
        $contenu[strlen($contenu) - 1] = chr(ord($contenu[strlen($contenu) - 1]) ^ 0xFF);   /* altération de BANC : une corruption de transport que la vérification du serveur ne voit pas */
    }
    header('Content-Type: ' . ($meta['mime'] ?? 'application/octet-stream'));
    header('Content-Length: ' . strlen($contenu));
    header('Content-Disposition: ' . ($usage === 'telechargement' ? 'attachment' : 'inline') . '; filename="' . $nomSortie . '"');
    header('X-Sigh-Empreinte: ' . $sha);
    header('Cache-Control: private, no-store');
    header('X-Content-Type-Options: nosniff');
    echo $contenu;
    exit;
}

sigh_fichiers_refus(400, 'ACTION_INCONNUE', 'action « ' . $action . ' » non prise en charge', 'Actions : deposer (POST), lire, chemin (GET).');
