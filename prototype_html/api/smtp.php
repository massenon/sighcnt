<?php
/* =============================================================================
 * SIGH-CNT — La messagerie de la clinique (SMTP) et son test d'envoi
 * -----------------------------------------------------------------------------
 * GET    ?action=etat      → la configuration, SANS le mot de passe (administrateur, DAF)
 * POST   action=enregistrer → enregistre la configuration (administrateur, DAF)
 * POST   action=tester     → envoie un message de test et rend les ÉTAPES (administrateur, DAF)
 * POST   action=envoyer    → envoie un courriel à l'éditeur depuis « Contactez l'éditeur » (tout agent connecté)
 * POST   action=effacer    → retire la configuration (administrateur)
 *
 * LE MOT DE PASSE : saisi, chiffré (AES-256-GCM) avec une clé tirée au sort qui vit
 * dans un AUTRE fichier (`smtp.cle.local.php`), ces deux fichiers étant ignorés par
 * git. Il n'entre JAMAIS dans le magasin JSON (qu'on exporte, qu'on sauvegarde et
 * qu'on relit), il n'est JAMAIS renvoyé, et il n'est jamais journalisé. Cela
 * protège contre la copie d'une base ou d'un dépôt ; cela ne protège pas contre
 * quelqu'un qui lit le disque du serveur, où la clé et le chiffré cohabitent :
 * un serveur doit pouvoir se connecter seul, il faut donc qu'il détienne le secret.
 *
 * `envoyer` ne sert qu'à écrire à l'ÉDITEUR : les destinataires doivent figurer à
 * la liste de ses adresses, faute de quoi ce point d'entrée ferait de ce serveur
 * un relais ouvert pour n'importe quel agent connecté.
 * ========================================================================== */

require __DIR__ . '/_commun.php';
require_once __DIR__ . '/smtp_client.php';

header('Access-Control-Allow-Origin: ' . ($_SERVER['HTTP_ORIGIN'] ?? '*'));
header('Access-Control-Allow-Credentials: true');
header('Access-Control-Allow-Headers: Content-Type, X-Sigh-Jeton');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    sigh_repondre(['ok' => true]);
}

const SIGH_SMTP_EDITEUR = ['rarhodes06@gmail.com', 'contact@massenonrhodes.com'];
const SIGH_SMTP_ROLES = ['admin', 'da'];

function sigh_smtp_dossier(): string
{
    return getenv('SIGH_SMTP_DIR') ?: __DIR__;
}

/* Les fichiers de secret portent l'extension .php et s'ouvrent par une garde : demandés par HTTP, ils s'exécutent et se taisent. On les lit en TEXTE
   (jamais par include : le cache d'opcodes servirait une version périmée juste après une écriture). */
const SIGH_SMTP_GARDE = "<?php http_response_code(403); exit; ?>\n";

function sigh_smtp_lire_fichier(string $f): ?string
{
    $t = @file_get_contents($f);
    if ($t === false || strncmp($t, SIGH_SMTP_GARDE, strlen(SIGH_SMTP_GARDE)) !== 0) {
        return null;
    }
    return substr($t, strlen(SIGH_SMTP_GARDE));
}

function sigh_smtp_cle(): string
{
    $f = sigh_smtp_dossier() . '/smtp.cle.local.php';
    if (is_file($f)) {
        $k = sigh_smtp_lire_fichier($f);
        if (is_string($k) && strlen($k) === 64 && ctype_xdigit($k)) {
            return hex2bin($k);
        }
    }
    $k = bin2hex(random_bytes(32));
    file_put_contents($f, SIGH_SMTP_GARDE . $k, LOCK_EX);
    @chmod($f, 0600);
    return hex2bin($k);
}

function sigh_smtp_chiffrer(string $clair): string
{
    $iv = random_bytes(12);
    $tag = '';
    $ct = openssl_encrypt($clair, 'aes-256-gcm', sigh_smtp_cle(), OPENSSL_RAW_DATA, $iv, $tag);
    return base64_encode($iv . $tag . $ct);
}

function sigh_smtp_dechiffrer(string $b64): ?string
{
    $b = base64_decode($b64, true);
    if ($b === false || strlen($b) < 28) {
        return null;
    }
    $r = openssl_decrypt(substr($b, 28), 'aes-256-gcm', sigh_smtp_cle(), OPENSSL_RAW_DATA, substr($b, 0, 12), substr($b, 12, 16));
    return $r === false ? null : $r;
}

function sigh_smtp_lire_config(): array
{
    $t = sigh_smtp_lire_fichier(sigh_smtp_dossier() . '/smtp.local.php');
    $c = $t === null ? [] : json_decode($t, true);
    return is_array($c) ? $c : [];
}

function sigh_smtp_ecrire_config(array $c): void
{
    $f = sigh_smtp_dossier() . '/smtp.local.php';
    file_put_contents($f, SIGH_SMTP_GARDE . json_encode($c, JSON_UNESCAPED_UNICODE), LOCK_EX);
    @chmod($f, 0600);
}

/** La configuration prête à servir (mot de passe en clair, en mémoire seulement). */
function sigh_smtp_config_active(array $c): array
{
    $c['motDePasse'] = !empty($c['mdp']) ? (sigh_smtp_dechiffrer((string) $c['mdp']) ?? '') : '';
    return $c;
}

/** Ce que l'écran a le droit de voir : jamais le mot de passe, ni son chiffré. */
function sigh_smtp_publique(array $c): array
{
    return [
        'configure' => !empty($c['serveur']) && !empty($c['expediteur']),
        'serveur' => $c['serveur'] ?? '', 'port' => (int) ($c['port'] ?? 587),
        'chiffrement' => $c['chiffrement'] ?? 'starttls', 'identifiant' => $c['identifiant'] ?? '',
        'motDePasseDefini' => !empty($c['mdp']),
        'expediteur' => $c['expediteur'] ?? '', 'nom' => $c['nom'] ?? '',
        'repondreA' => $c['repondreA'] ?? '', 'repondreNom' => $c['repondreNom'] ?? '',
        'delai' => (int) ($c['delai'] ?? 15), 'verifierCertificat' => ($c['verifierCertificat'] ?? true) !== false,
        'testeLe' => $c['testeLe'] ?? null, 'testeOk' => $c['testeOk'] ?? null, 'testeEchec' => $c['testeEchec'] ?? null,
    ];
}

try {
    $pdo = sigh_pdo();
    sigh_installer($pdo);
} catch (Throwable $e) {
    sigh_repondre(['erreur' => 'base indisponible', 'detail' => $e->getMessage()], 503);
}

$corps = ($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST' ? sigh_corps() : null;
$session = sigh_exiger_session($pdo, $corps);
$role = (string) ($session['role'] ?? '');
$action = (string) ($_GET['action'] ?? ($corps['action'] ?? 'etat'));
$gere = in_array($role, SIGH_SMTP_ROLES, true);

if ($action === 'envoyer') {
    $dest = array_values(array_filter(array_map('strval', (array) ($corps['destinataires'] ?? []))));
    $sujet = (string) ($corps['sujet'] ?? '');
    $texte = (string) ($corps['corps'] ?? '');
    if ($sujet === '' || $texte === '' || !$dest) {
        sigh_repondre(['erreur' => 'message incomplet', 'detail' => 'Objet, texte et destinataire sont requis.'], 422);
    }
    foreach ($dest as $d) {
        if (!in_array(strtolower($d), SIGH_SMTP_EDITEUR, true)) {
            sigh_repondre(['erreur' => 'destinataire refusé', 'detail' => 'Ce point d’entrée n’écrit qu’à l’éditeur du logiciel.'], 403);
        }
    }
    $c = sigh_smtp_lire_config();
    if (empty($c['serveur']) || empty($c['expediteur'])) {
        sigh_repondre(['erreur' => 'messagerie non configurée', 'detail' => 'La messagerie du poste n’est pas configurée : Paramètres système, Messagerie.'], 409);
    }
    $pied = "\n\n-- \nEnvoyé depuis SIGH-CNT par " . ($session['nom'] ?: $session['identifiant']) . ' (' . $role . ').';
    $r = sigh_smtp_envoyer(sigh_smtp_config_active($c), $dest, $sujet, $texte . $pied);
    sigh_journaliser($pdo, $session, 'Envoi de courriel', 'SUP', 'Contact éditeur', null, ['ok' => $r['ok'], 'echec' => $r['echec']]);
    sigh_repondre($r, $r['ok'] ? 200 : 502);
}

/* Ce que TOUT agent a le droit de savoir : la messagerie est-elle prête ? (aucun réglage, aucun secret) */
if ($action === 'disponible') {
    $c = sigh_smtp_lire_config();
    sigh_repondre(['configure' => !empty($c['serveur']) && !empty($c['expediteur']), 'testeOk' => $c['testeOk'] ?? null]);
}

if (!$gere) {
    sigh_repondre(['erreur' => 'accès refusé', 'detail' => 'La messagerie se règle depuis les Paramètres système, par l’administrateur ou la DAF.'], 403);
}

if ($action === 'etat') {
    sigh_repondre(sigh_smtp_publique(sigh_smtp_lire_config()));
}

$lire_form = function (array $corps, array $ancien): array {
    $c = $ancien;
    foreach (['serveur', 'identifiant', 'nom', 'repondreA', 'repondreNom'] as $k) {
        if (array_key_exists($k, $corps)) {
            $c[$k] = trim((string) $corps[$k]);
        }
    }
    if (array_key_exists('expediteur', $corps)) {
        $c['expediteur'] = trim((string) $corps['expediteur']);
    }
    if (isset($corps['port'])) {
        $c['port'] = (int) $corps['port'];
    }
    if (isset($corps['chiffrement']) && in_array($corps['chiffrement'], ['aucun', 'starttls', 'ssl'], true)) {
        $c['chiffrement'] = $corps['chiffrement'];
    }
    if (isset($corps['delai'])) {
        $c['delai'] = max(3, min(60, (int) $corps['delai']));
    }
    if (array_key_exists('verifierCertificat', $corps)) {
        $c['verifierCertificat'] = (bool) $corps['verifierCertificat'];
    }
    return $c;
};

if ($action === 'enregistrer') {
    $c = $lire_form($corps, sigh_smtp_lire_config());
    if (empty($c['serveur']) || ($c['port'] ?? 0) < 1 || ($c['port'] ?? 0) > 65535) {
        sigh_repondre(['erreur' => 'configuration invalide', 'detail' => 'Serveur et port (1 à 65535) sont requis.'], 422);
    }
    if (!filter_var((string) ($c['expediteur'] ?? ''), FILTER_VALIDATE_EMAIL)) {
        sigh_repondre(['erreur' => 'configuration invalide', 'detail' => 'L’adresse d’expéditeur n’est pas une adresse de courriel valide.'], 422);
    }
    if (($c['repondreA'] ?? '') !== '' && !filter_var((string) $c['repondreA'], FILTER_VALIDATE_EMAIL)) {
        sigh_repondre(['erreur' => 'configuration invalide', 'detail' => 'L’adresse « Répondre à » n’est pas une adresse de courriel valide.'], 422);
    }
    /* un mot de passe VIDE à l'enregistrement veut dire « inchangé » : l'écran ne le relit jamais, il ne peut donc pas le renvoyer */
    $mdp = (string) ($corps['motDePasse'] ?? '');
    if ($mdp !== '') {
        $c['mdp'] = sigh_smtp_chiffrer($mdp);
    }
    /* changer le serveur ou l'identifiant rend le dernier test caduc */
    $c['testeOk'] = null;
    $c['testeLe'] = null;
    $c['testeEchec'] = null;
    sigh_smtp_ecrire_config($c);
    sigh_journaliser($pdo, $session, 'Modification', 'CFG', 'Messagerie (SMTP)', null, [
        'serveur' => $c['serveur'], 'port' => $c['port'], 'chiffrement' => $c['chiffrement'] ?? 'starttls', 'motDePasse' => $mdp !== '' ? 'changé' : 'inchangé',
    ]);
    sigh_repondre(sigh_smtp_publique($c));
}

if ($action === 'tester') {
    $dest = trim((string) ($corps['destinataire'] ?? ''));
    if (!filter_var($dest, FILTER_VALIDATE_EMAIL)) {
        sigh_repondre(['erreur' => 'destinataire invalide', 'detail' => 'Renseigner l’adresse à laquelle envoyer le message de test.'], 422);
    }
    $stocke = sigh_smtp_lire_config();
    /* le test peut porter sur le formulaire non encore enregistré ; un mot de passe vide reprend celui qui est enregistré */
    $c = $lire_form($corps, $stocke);
    $actif = sigh_smtp_config_active($c);
    if (($corps['motDePasse'] ?? '') !== '') {
        $actif['motDePasse'] = (string) $corps['motDePasse'];
    }
    $sujet = 'SIGH-CNT : test de la messagerie';
    $texte = "Ceci est un message de test envoyé depuis SIGH-CNT.\nSi vous le lisez, la messagerie de la clinique est correctement configurée : accents é è à ç ô, symbole €.";
    $r = sigh_smtp_envoyer($actif, [$dest], $sujet, $texte);
    /* le résultat n'est retenu qu'à titre du dernier test de la configuration ENREGISTRÉE, si le formulaire ne l'a pas changée */
    $memeServeur = ($stocke['serveur'] ?? null) === ($c['serveur'] ?? null) && (int) ($stocke['port'] ?? 0) === (int) ($c['port'] ?? 0)
        && ($stocke['identifiant'] ?? null) === ($c['identifiant'] ?? null) && ($stocke['chiffrement'] ?? null) === ($c['chiffrement'] ?? null)
        && ($corps['motDePasse'] ?? '') === '';
    if ($memeServeur && !empty($stocke['serveur'])) {
        $stocke['testeOk'] = $r['ok'];
        $stocke['testeLe'] = date('c');
        $stocke['testeEchec'] = $r['echec'];
        sigh_smtp_ecrire_config($stocke);
    }
    sigh_journaliser($pdo, $session, 'Test d’envoi', 'CFG', 'Messagerie (SMTP)', null, ['ok' => $r['ok'], 'echec' => $r['echec'], 'serveur' => $c['serveur'] ?? '']);
    sigh_repondre($r);
}

if ($action === 'effacer') {
    if ($role !== 'admin') {
        sigh_repondre(['erreur' => 'accès refusé', 'detail' => 'Seul l’administrateur système retire la configuration de la messagerie.'], 403);
    }
    sigh_smtp_ecrire_config([]);
    sigh_journaliser($pdo, $session, 'Suppression de la configuration', 'CFG', 'Messagerie (SMTP)', null, null);
    sigh_repondre(sigh_smtp_publique([]));
}

sigh_repondre(['erreur' => 'action inconnue', 'detail' => $action], 400);
