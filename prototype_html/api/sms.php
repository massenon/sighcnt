<?php
/* =============================================================================
 * SIGH-CNT, La passerelle SMS (Twilio par défaut, Vonage en second) et son test d'envoi
 * -----------------------------------------------------------------------------
 * GET    ?action=etat       : la configuration SANS les identifiants (administrateur, DAF, Direction en lecture)
 * POST   action=enregistrer : enregistre la configuration (administrateur, DAF)
 * POST   action=tester      : envoie le message de contrôle à un numéro et rend les ÉTAPES (administrateur, DAF)
 * POST   action=envoyer     : envoie un message de motif admis (administrateur, DAF ; l'ouverture aux déclencheurs relève de l'étape S2)
 * POST   action=effacer     : retire la configuration (administrateur)
 *
 * LES IDENTIFIANTS DU FOURNISSEUR (SID, jeton, clé, secret) : saisis, chiffrés (AES-256-GCM) avec une clé tirée au sort qui vit dans un
 * AUTRE fichier (`sms.cle.local.php`), ces fichiers étant ignorés par git. Écriture SEULE : ils n'entrent JAMAIS dans le magasin JSON, ne sont
 * JAMAIS renvoyés (l'écran lit « enregistré »), jamais journalisés. Cela protège contre la copie d'une base ou d'un dépôt ; cela ne protège
 * pas contre quelqu'un qui lit le disque du serveur, où la clé et le chiffré cohabitent (un serveur doit pouvoir se connecter seul).
 *
 * LE JOURNAL : le serveur écrit l'audit (RG-12) avec le numéro MASQUÉ (quatre derniers chiffres), le motif, le statut et l'identifiant du
 * message ; jamais le texte, jamais un secret. Il rend aussi l'`entree` que l'écran range dans la collection `messagesSms`.
 * LE PLAFOND est compté ICI (compteur du jour, heure du Bénin) : un poste ne peut pas le contourner en effaçant son navigateur.
 * ========================================================================== */

require __DIR__ . '/_commun.php';
require_once __DIR__ . '/sms_client.php';

header('Access-Control-Allow-Origin: ' . ($_SERVER['HTTP_ORIGIN'] ?? '*'));
header('Access-Control-Allow-Credentials: true');
header('Access-Control-Allow-Headers: Content-Type, X-Sigh-Jeton');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    sigh_repondre(['ok' => true]);
}

const SIGH_SMS_ROLES_ECRITURE = ['admin', 'da'];
const SIGH_SMS_ROLES_LECTURE = ['admin', 'da', 'direction'];
const SIGH_SMS_SECRETS = ['twilioSid', 'twilioToken', 'vonageCle', 'vonageSecret'];
const SIGH_SMS_TEST_TEXTE = 'SIGH-CNT : message de test de la passerelle SMS. Si vous le lisez, l’envoi fonctionne.';

function sigh_sms_dossier(): string
{
    return sigh_sms_dossier_client();
}

/* Les fichiers de secret portent l'extension .php et s'ouvrent par une garde : demandés par HTTP, ils s'exécutent et se taisent. On les lit en TEXTE
   (jamais par include : le cache d'opcodes servirait une version périmée juste après une écriture). */
const SIGH_SMS_GARDE = "<?php http_response_code(403); exit; ?>\n";

function sigh_sms_lire_fichier(string $f): ?string
{
    $t = @file_get_contents($f);
    if ($t === false || strncmp($t, SIGH_SMS_GARDE, strlen(SIGH_SMS_GARDE)) !== 0) {
        return null;
    }
    return substr($t, strlen(SIGH_SMS_GARDE));
}

function sigh_sms_cle(): string
{
    $f = sigh_sms_dossier() . '/sms.cle.local.php';
    if (is_file($f)) {
        $k = sigh_sms_lire_fichier($f);
        if (is_string($k) && strlen($k) === 64 && ctype_xdigit($k)) {
            return hex2bin($k);
        }
    }
    $k = bin2hex(random_bytes(32));
    file_put_contents($f, SIGH_SMS_GARDE . $k, LOCK_EX);
    @chmod($f, 0600);
    return hex2bin($k);
}

function sigh_sms_chiffrer(string $clair): string
{
    $iv = random_bytes(12);
    $tag = '';
    $ct = openssl_encrypt($clair, 'aes-256-gcm', sigh_sms_cle(), OPENSSL_RAW_DATA, $iv, $tag);
    return base64_encode($iv . $tag . $ct);
}

function sigh_sms_dechiffrer(string $b64): ?string
{
    $b = base64_decode($b64, true);
    if ($b === false || strlen($b) < 28) {
        return null;
    }
    $r = openssl_decrypt(substr($b, 28), 'aes-256-gcm', sigh_sms_cle(), OPENSSL_RAW_DATA, substr($b, 0, 12), substr($b, 12, 16));
    return $r === false ? null : $r;
}

function sigh_sms_lire_config(): array
{
    $t = sigh_sms_lire_fichier(sigh_sms_dossier() . '/sms.local.php');
    $c = $t === null ? [] : json_decode($t, true);
    return is_array($c) ? $c : [];
}

function sigh_sms_ecrire_config(array $c): void
{
    $f = sigh_sms_dossier() . '/sms.local.php';
    file_put_contents($f, SIGH_SMS_GARDE . json_encode($c, JSON_UNESCAPED_UNICODE), LOCK_EX);
    @chmod($f, 0600);
}

/** La configuration prête à servir : secrets en clair, en mémoire seulement. */
function sigh_sms_config_active(array $c): array
{
    $c['secrets'] = [];
    foreach (SIGH_SMS_SECRETS as $k) {
        if (!empty($c['sec'][$k])) {
            $c['secrets'][$k] = sigh_sms_dechiffrer((string) $c['sec'][$k]) ?? '';
        }
    }
    unset($c['sec']);
    return $c;
}

/** L'instant de référence : l'horloge du serveur, ou (banc seulement) celle que la sonde impose. */
function sigh_sms_maintenant(?array $corps): DateTimeImmutable
{
    if (getenv('SIGH_BANC') === '1' && !empty($corps['maintenant'])) {
        try {
            return new DateTimeImmutable((string) $corps['maintenant']);
        } catch (Throwable $e) {
            /* date illisible : l'horloge réelle */
        }
    }
    return new DateTimeImmutable('now');
}

function sigh_sms_envoyes(array $c, DateTimeImmutable $maintenant): int
{
    $k = $c['compteur'] ?? [];
    return ($k['jour'] ?? '') === sigh_sms_jour($maintenant) ? (int) ($k['n'] ?? 0) : 0;
}

/** Ce que l'écran a le droit de voir : jamais un identifiant, ni son chiffré. */
function sigh_sms_publique(array $c, ?DateTimeImmutable $maintenant = null): array
{
    $maintenant = $maintenant ?? new DateTimeImmutable('now');
    $actif = sigh_sms_config_active($c);
    return [
        'configure' => sigh_sms_manque($actif) === null,
        'actif' => !empty($c['actif']),
        'fournisseur' => ($c['fournisseur'] ?? 'twilio') === 'vonage' ? 'vonage' : 'twilio',
        'expediteur' => $c['expediteur'] ?? '', 'serviceSid' => $c['serviceSid'] ?? '',
        'secretsDefinis' => array_reduce(SIGH_SMS_SECRETS, function ($o, $k) use ($c) { $o[$k] = !empty($c['sec'][$k]); return $o; }, []),
        'plafondJour' => (int) ($c['plafondJour'] ?? 200),
        'calmeDebut' => (int) ($c['calmeDebut'] ?? 21), 'calmeFin' => (int) ($c['calmeFin'] ?? 7),
        'envoyesAujourdhui' => sigh_sms_envoyes($c, $maintenant),
        'testeLe' => $c['testeLe'] ?? null, 'testeOk' => $c['testeOk'] ?? null, 'testeCode' => $c['testeCode'] ?? null,
        'motifs' => array_map(function ($m) { return $m['libelle']; }, SIGH_SMS_MOTIFS),
    ];
}

function sigh_sms_refuser(string $code, int $http = 403, string $detail = ''): void
{
    $r = sigh_sms_refus($code, $detail);
    sigh_repondre(['ok' => false, 'statut' => 'refuse', 'code' => $r['code'], 'erreur' => $r['code'], 'detail' => $r['motif'], 'motif' => $r['motif'], 'geste' => $r['geste']], $http);
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
$ecrit = in_array($role, SIGH_SMS_ROLES_ECRITURE, true);
$lit = in_array($role, SIGH_SMS_ROLES_LECTURE, true);

if (!$lit) {
    sigh_sms_refuser('ACCES_REFUSE');
}
if ($action === 'etat') {
    sigh_repondre(sigh_sms_publique(sigh_sms_lire_config()));
}
if (!$ecrit) {
    sigh_sms_refuser('ACCES_REFUSE', 403, 'Ce profil lit la passerelle sans la modifier.');
}

/** Fusionne le formulaire dans la configuration. Un identifiant VIDE veut dire « inchangé » : l'écran ne les relit jamais. */
$lire_form = function (array $corps, array $ancien): array {
    $c = $ancien;
    if (isset($corps['fournisseur']) && in_array($corps['fournisseur'], ['twilio', 'vonage'], true)) {
        $c['fournisseur'] = $corps['fournisseur'];
    }
    foreach (['expediteur', 'serviceSid'] as $k) {
        if (array_key_exists($k, $corps)) {
            $c[$k] = trim((string) $corps[$k]);
        }
    }
    if (isset($corps['plafondJour'])) {
        $c['plafondJour'] = max(1, min(100000, (int) $corps['plafondJour']));
    }
    foreach (['calmeDebut', 'calmeFin'] as $k) {
        if (isset($corps[$k])) {
            $c[$k] = max(0, min(23, (int) $corps[$k]));
        }
    }
    if (array_key_exists('actif', $corps)) {
        $c['actif'] = (bool) $corps['actif'];
    }
    foreach (SIGH_SMS_SECRETS as $k) {
        $v = trim((string) ($corps[$k] ?? ''));
        if ($v !== '') {
            $c['sec'][$k] = sigh_sms_chiffrer($v);
        }
    }
    return $c;
};

/** Journalise (RG-12) SANS texte et SANS secret : numéro masqué, motif, statut, identifiant du message. */
$auditer = function (string $acte, string $motif, array $r) use ($pdo, $session): void {
    sigh_journaliser($pdo, $session, $acte, 'CFG', 'Passerelle SMS', null, [
        'motif' => $motif, 'statut' => $r['statut'], 'code' => $r['code'], 'a' => $r['numeroMasque'], 'fournisseur' => $r['fournisseur'], 'id' => $r['idMessage'],
    ]);
};

/** L'entrée du journal des envois que l'écran range dans `messagesSms` : jamais le numéro en clair, jamais le texte. */
$entree = function (array $r, string $motif, int $longueur) use ($session): array {
    return [
        'date' => date('Y-m-d'), 'heure' => date('H:i'), 'motif' => $motif, 'motifLibelle' => SIGH_SMS_MOTIFS[$motif]['libelle'] ?? $motif,
        'statut' => $r['statut'], 'code' => $r['code'], 'detail' => $r['ok'] ? '' : $r['motif'],
        'fournisseur' => $r['fournisseur'], 'numeroMasque' => $r['numeroMasque'], 'idMessage' => $r['idMessage'],
        'longueur' => $longueur, 'reporteA' => $r['reporteA'], 'par' => $session['nom'] ?: $session['identifiant'],
    ];
};

/** Compte l'envoi accepté dans le compteur du jour (verrou de fichier : deux envois simultanés ne se comptent pas pour un). */
$compter = function (DateTimeImmutable $maintenant): void {
    $f = sigh_sms_dossier() . '/sms.local.php';
    $h = @fopen($f, 'c+');
    if (!$h) {
        return;
    }
    flock($h, LOCK_EX);
    $t = stream_get_contents($h);
    $c = [];
    if (is_string($t) && strncmp($t, SIGH_SMS_GARDE, strlen(SIGH_SMS_GARDE)) === 0) {
        $c = json_decode(substr($t, strlen(SIGH_SMS_GARDE)), true) ?: [];
    }
    $jour = sigh_sms_jour($maintenant);
    $k = $c['compteur'] ?? [];
    $c['compteur'] = ['jour' => $jour, 'n' => (($k['jour'] ?? '') === $jour ? (int) ($k['n'] ?? 0) : 0) + 1];
    ftruncate($h, 0);
    rewind($h);
    fwrite($h, SIGH_SMS_GARDE . json_encode($c, JSON_UNESCAPED_UNICODE));
    fflush($h);
    flock($h, LOCK_UN);
    fclose($h);
};

if ($action === 'enregistrer') {
    $c = $lire_form($corps, sigh_sms_lire_config());
    if (!empty($c['expediteur']) && !sigh_sms_expediteur_valide((string) $c['expediteur'])) {
        sigh_repondre(['erreur' => 'configuration invalide', 'detail' => 'L’expéditeur doit être un numéro E.164 ou un identifiant de 1 à 11 caractères avec au moins une lettre.'], 422);
    }
    if (!empty($c['actif'])) {
        $manque = sigh_sms_manque(sigh_sms_config_active($c));
        if ($manque !== null) {
            sigh_sms_refuser('SMS_NON_CONFIGUREE', 422, $manque);
        }
    }
    /* changer le fournisseur, l'expéditeur ou un identifiant rend le dernier test caduc */
    $c['testeOk'] = null;
    $c['testeLe'] = null;
    $c['testeCode'] = null;
    sigh_sms_ecrire_config($c);
    $changes = [];
    foreach (SIGH_SMS_SECRETS as $k) {
        if (trim((string) ($corps[$k] ?? '')) !== '') {
            $changes[] = $k;
        }
    }
    sigh_journaliser($pdo, $session, 'Modification', 'CFG', 'Passerelle SMS', null, [
        'fournisseur' => $c['fournisseur'] ?? 'twilio', 'actif' => !empty($c['actif']), 'plafondJour' => $c['plafondJour'] ?? 200,
        'identifiantsChanges' => $changes ?: 'aucun',
    ]);
    sigh_repondre(sigh_sms_publique($c));
}

if ($action === 'tester' || $action === 'envoyer') {
    $maintenant = sigh_sms_maintenant($corps);
    $stocke = sigh_sms_lire_config();
    if ($action === 'tester') {
        $motif = 'test';
        $texte = SIGH_SMS_TEST_TEXTE;
        /* le test peut porter sur le formulaire non encore enregistré ; un identifiant vide reprend celui qui est enregistré */
        $c = $lire_form($corps, $stocke);
        $exigerActif = false;
    } else {
        $motif = (string) ($corps['motif'] ?? '');
        $texte = (string) ($corps['texte'] ?? '');
        $c = $stocke;
        $exigerActif = true;
    }
    $r = sigh_sms_suite(sigh_sms_config_active($c), $motif, (string) ($corps['destinataire'] ?? ''), $texte, $maintenant, sigh_sms_envoyes($stocke, $maintenant), $exigerActif);
    if ($r['ok']) {
        $compter($maintenant);
    }
    if ($action === 'tester') {
        /* le résultat n'est retenu qu'à titre du dernier test de la configuration ENREGISTRÉE, si le formulaire n'y a rien changé */
        $identique = true;
        foreach (['fournisseur', 'expediteur', 'serviceSid'] as $k) {
            $identique = $identique && (($stocke[$k] ?? null) === ($c[$k] ?? null));
        }
        foreach (SIGH_SMS_SECRETS as $k) {
            $identique = $identique && trim((string) ($corps[$k] ?? '')) === '';
        }
        if ($identique && sigh_sms_manque(sigh_sms_config_active($stocke)) === null) {
            $fresh = sigh_sms_lire_config();
            $fresh['testeOk'] = $r['ok'];
            $fresh['testeLe'] = date('c');
            $fresh['testeCode'] = $r['code'];
            sigh_sms_ecrire_config($fresh);
        }
    }
    $auditer($action === 'tester' ? 'Test d’envoi' : 'Envoi de SMS', $motif, $r);
    $r['entree'] = $entree($r, $motif, mb_strlen($texte, 'UTF-8'));
    sigh_repondre($r);
}

if ($action === 'effacer') {
    if ($role !== 'admin') {
        sigh_sms_refuser('ACCES_REFUSE', 403, 'Seul l’administrateur système retire la configuration.');
    }
    /* le compteur du jour SURVIT : effacer puis ressaisir ne remet pas le plafond à zéro */
    $ancien = sigh_sms_lire_config();
    sigh_sms_ecrire_config(isset($ancien['compteur']) ? ['compteur' => $ancien['compteur']] : []);
    sigh_journaliser($pdo, $session, 'Suppression de la configuration', 'CFG', 'Passerelle SMS', null, null);
    sigh_repondre(sigh_sms_publique(sigh_sms_lire_config()));
}

sigh_repondre(['erreur' => 'action inconnue', 'detail' => $action], 400);
