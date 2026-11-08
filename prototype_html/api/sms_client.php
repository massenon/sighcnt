<?php
/* =============================================================================
 * SIGH-CNT, Client de la passerelle SMS (Twilio par défaut, Vonage en second)
 * -----------------------------------------------------------------------------
 * Un SMS part par UNE suite d'étapes, et c'est la suite que l'on montre :
 *
 *   configuration → numéro → plafond → heures calmes → texte → fournisseur
 *
 * La suite s'ARRÊTE à la première étape qui refuse, et le refus est NOMMÉ :
 * un `code` (liste fermée, `sigh_sms_refus()`), un `motif` lisible et le `geste`
 * qui corrige. Un « échec d'envoi » muet renverrait l'administrateur chercher
 * au mauvais endroit.
 *
 * UN ADAPTATEUR PAR FOURNISSEUR, appel REST par cURL. Aucune bibliothèque n'est
 * chargée : `vendor/` (twilio/sdk, vonage/client) n'est pas versionné et ce
 * fichier doit tourner sans lui. Le chemin par SDK n'est donc PAS emprunté ici.
 *
 * Les identifiants (SID, jeton, clé, secret) ne sont ni journalisés, ni rendus :
 * aucune réponse de ce fichier ne les contient, et un message d'erreur du
 * fournisseur qui les recopierait est masqué avant d'être montré.
 *
 * LE PUITS DE TEST (banc seulement) : avec `SIGH_BANC=1`, un secret qui commence
 * par `puits-` n'est jamais envoyé au réseau. Un faux fournisseur, dans le
 * processus, répond comme le vrai (même forme de réponse, parsée par le MÊME
 * adaptateur) : `puits-ok`, `puits-refuse` (identifiants), `puits-solde`
 * (solde insuffisant), `puits-injoignable` (réseau). Un serveur PHP intégré ne
 * traite qu'une requête à la fois : un puits joint par HTTP depuis ce processus
 * se bloquerait lui-même. Hors banc, ce chemin n'existe pas.
 * ========================================================================== */

const SIGH_SMS_FUSEAU = 'Africa/Porto-Novo';

/** Motifs d'envoi (liste fermée). `urgent` : exempt des heures calmes (alerte technique). */
const SIGH_SMS_MOTIFS = [
    'test' => ['libelle' => 'Test d’envoi', 'urgent' => true],
    'alerte_technique' => ['libelle' => 'Alerte technique', 'urgent' => true],
    'rappel_rdv' => ['libelle' => 'Rappel de rendez-vous', 'urgent' => false],
    'anniversaire' => ['libelle' => 'Souhait d’anniversaire', 'urgent' => false],
    'fete' => ['libelle' => 'Souhait de fête', 'urgent' => false],
    'relance' => ['libelle' => 'Relance', 'urgent' => false],
    'resultat_disponible' => ['libelle' => 'Résultat disponible', 'urgent' => false],
];

/**
 * QUI PEUT DEMANDER L'ENVOI d'un message de tel motif (action `envoyer`). La configuration, elle, reste à `admin` et `da` : un poste qui
 * déclenche un rappel n'a jamais accès aux réglages ni au Test SMS. PROPOSITION à valider par la Direction : seuls les profils dont le
 * poste produit le motif (accueil pour les rappels et les vœux, laboratoire pour « résultat disponible ») sont admis.
 */
const SIGH_SMS_ROLES_MOTIF = [
    'test' => ['admin', 'da'],
    'alerte_technique' => ['admin', 'da'],
    'rappel_rdv' => ['admin', 'da', 'reception', 'medecin', 'infirmier', 'dm'],
    'anniversaire' => ['admin', 'da', 'reception', 'agentadmin'],
    'fete' => ['admin', 'da', 'reception', 'agentadmin'],
    'relance' => ['admin', 'da', 'reception', 'agentadmin'],
    'resultat_disponible' => ['admin', 'da', 'reception', 'laborantin', 'medecin', 'dm'],
];

/**
 * Les refus NOMMÉS : code, motif, geste. Une seule table : l'écran, le journal et les sondes la lisent.
 * @return array{code:string,motif:string,geste:string}
 */
function sigh_sms_refus(string $code, string $detail = ''): array
{
    $t = [
        'SMS_NON_CONFIGUREE' => ['La passerelle SMS n’est pas configurée : fournisseur, identifiants ou expéditeur manquants.', 'Renseigner les identifiants du fournisseur et l’expéditeur, puis enregistrer.'],
        'SMS_DESACTIVEE' => ['La passerelle SMS est configurée mais désactivée : aucun message ne part.', 'Activer la passerelle dans les Paramètres système, Passerelle SMS.'],
        'NUMERO_INVALIDE' => ['Le numéro n’est pas au format international (E.164), par exemple +22912345678.', 'Saisir le numéro avec le signe plus et l’indicatif du pays, sans espace.'],
        'IDENTIFIANTS_REFUSES' => ['Le fournisseur a refusé les identifiants de la passerelle.', 'Saisir de nouveau les identifiants du compte du fournisseur, puis refaire le test.'],
        'EXPEDITEUR_NON_AUTORISE' => ['Le fournisseur n’accepte pas cet expéditeur pour ce pays.', 'Utiliser un numéro ou un identifiant acheté ou enregistré chez le fournisseur.'],
        'SOLDE_INSUFFISANT' => ['Le solde du compte chez le fournisseur ne permet pas d’envoyer ce message.', 'Alimenter le compte du fournisseur (la DAF gère le solde), puis refaire le test.'],
        'PLAFOND_ATTEINT' => ['Le plafond d’envois du jour est atteint.', 'Attendre demain, ou relever le plafond dans les réglages de la passerelle.'],
        'FOURNISSEUR_INJOIGNABLE' => ['Le fournisseur est injoignable depuis ce serveur.', 'Vérifier la connexion Internet du serveur, puis refaire le test. Le message n’a pas été envoyé.'],
        'FOURNISSEUR_REFUS' => ['Le fournisseur a refusé le message pour une raison qui n’est pas encore classée.', 'Lire le détail du fournisseur affiché, et le signaler à l’éditeur si le cas se répète.'],
        'HEURES_CALMES' => ['Les heures calmes sont en cours : un message non urgent attend leur fin.', 'Le message peut être renvoyé à la fin des heures calmes (heure indiquée).'],
        'DONNEE_MEDICALE' => ['Le texte contient un mot de la liste médicale : aucune donnée de santé ne part par SMS.', 'Réécrire le message sans diagnostic, résultat ni motif de venue.'],
        'TEXTE_INVALIDE' => ['Le texte du message est vide ou dépasse 320 caractères.', 'Rédiger un message de 1 à 320 caractères.'],
        'MOTIF_INCONNU' => ['Le motif d’envoi n’est pas dans la liste des motifs admis.', 'Choisir un motif de la liste : ' . implode(', ', array_keys(SIGH_SMS_MOTIFS)) . '.'],
        'ACCES_REFUSE' => ['Ce profil ne règle ni n’utilise la passerelle SMS.', 'S’adresser à l’administrateur système ou à la DAF.'],
    ];
    $x = $t[$code] ?? [$code, ''];
    return ['code' => $code, 'motif' => $x[0] . ($detail !== '' ? ' ' . $detail : ''), 'geste' => $x[1]];
}

/** Numéro E.164 : espaces, points et traits retirés, signe plus puis 8 à 15 chiffres. Null si invalide. */
function sigh_sms_numero(string $n): ?string
{
    $n = preg_replace('/[\s.\-()]/', '', trim($n));
    return preg_match('/^\+[1-9][0-9]{7,14}$/', (string) $n) ? $n : null;
}

/** Le numéro MASQUÉ du journal : les quatre derniers chiffres seulement. */
function sigh_sms_masquer(string $e164): string
{
    $c = preg_replace('/\D/', '', $e164);
    return '****' . substr($c, -4);
}

/** Expéditeur : un numéro E.164, ou un identifiant alphanumérique de 1 à 11 caractères avec au moins une lettre. */
function sigh_sms_expediteur_valide(string $e): bool
{
    return sigh_sms_numero($e) !== null || (bool) preg_match('/^(?=.*[A-Za-z])[A-Za-z0-9]{1,11}$/', $e);
}

/** Retire une valeur secrète (et sa forme encodée) d'un texte avant de le montrer. */
function sigh_sms_masquer_secrets(string $s, array $secrets): string
{
    foreach ($secrets as $v) {
        $v = (string) $v;
        if (strlen($v) >= 4) {
            $s = str_replace([$v, base64_encode($v), rawurlencode($v)], '***', $s);
        }
    }
    return $s;
}

/**
 * LISTE MÉDICALE (PROPOSITION À VALIDER par le médecin : aucun document ne la fournit). Un SMS peut dire qu'un résultat est
 * DISPONIBLE, il ne dit jamais CE QUE le résultat contient ni de quoi souffre la personne.
 */
const SIGH_SMS_MOTS_MEDICAUX = [
    'diagnostic', 'pathologie', 'maladie', 'seropositif', 'seropositive', 'positif', 'positive', 'negatif', 'negative',
    'grossesse', 'enceinte', 'paludisme', 'palu', 'vih', 'sida', 'diabete', 'cancer', 'tuberculose', 'hepatite',
];

/** @return ?string le premier mot médical trouvé, ou null */
function sigh_sms_mot_medical(string $texte): ?string
{
    $t = mb_strtolower($texte, 'UTF-8');
    $t = strtr($t, ['à' => 'a', 'â' => 'a', 'ä' => 'a', 'é' => 'e', 'è' => 'e', 'ê' => 'e', 'ë' => 'e', 'î' => 'i', 'ï' => 'i', 'ô' => 'o', 'ö' => 'o', 'ù' => 'u', 'û' => 'u', 'ü' => 'u', 'ç' => 'c']);
    foreach (SIGH_SMS_MOTS_MEDICAUX as $m) {
        if (preg_match('/(?<![a-z])' . preg_quote($m, '/') . '(?![a-z])/', $t)) {
            return $m;
        }
    }
    return null;
}

/** Le jour (AAAA-MM-JJ) à l'heure du Bénin. */
function sigh_sms_jour(DateTimeImmutable $maintenant): string
{
    return $maintenant->setTimezone(new DateTimeZone(SIGH_SMS_FUSEAU))->format('Y-m-d');
}

/**
 * Heures calmes : si `$maintenant` y tombe, rend l'instant de FIN (le report), sinon null. Début et fin sont des heures entières
 * (21 et 7 : calme de 21 h à 7 h, à cheval sur minuit).
 */
function sigh_sms_heures_calmes(array $cfg, DateTimeImmutable $maintenant): ?DateTimeImmutable
{
    $debut = (int) ($cfg['calmeDebut'] ?? 21);
    $fin = (int) ($cfg['calmeFin'] ?? 7);
    if ($debut === $fin) {
        return null;
    }
    $l = $maintenant->setTimezone(new DateTimeZone(SIGH_SMS_FUSEAU));
    $h = (int) $l->format('G');
    $calme = $debut > $fin ? ($h >= $debut || $h < $fin) : ($h >= $debut && $h < $fin);
    if (!$calme) {
        return null;
    }
    $reprise = $l->setTime($fin, 0, 0);
    if ($reprise <= $l) {
        $reprise = $reprise->modify('+1 day');
    }
    return $reprise;
}

/* =============================================================================
 * Transport : cURL, ou le puits du banc
 * ========================================================================== */

/** Le dossier des fichiers locaux (celui de sms.php, surchargeable pour les bancs). */
function sigh_sms_dossier_client(): string
{
    return getenv('SIGH_SMS_DIR') ?: __DIR__;
}

const SIGH_SMS_GARDE_PUITS = "<?php http_response_code(403); exit; ?>\n";

/** Ce que le puits a REÇU (sans aucun secret) : la sonde lit ce qui a vraiment circulé. @return list<array> */
function sigh_sms_puits_lire(): array
{
    $t = @file_get_contents(sigh_sms_dossier_client() . '/sms.puits.local.php');
    if ($t === false || strncmp($t, SIGH_SMS_GARDE_PUITS, strlen(SIGH_SMS_GARDE_PUITS)) !== 0) {
        return [];
    }
    $l = json_decode(substr($t, strlen(SIGH_SMS_GARDE_PUITS)), true);
    return is_array($l) ? $l : [];
}

function sigh_sms_puits_ecrire(array $l): void
{
    $f = sigh_sms_dossier_client() . '/sms.puits.local.php';
    file_put_contents($f, SIGH_SMS_GARDE_PUITS . json_encode(array_slice($l, -200), JSON_UNESCAPED_UNICODE), LOCK_EX);
    @chmod($f, 0600);
}

function sigh_sms_est_puits(string $secret): bool
{
    return getenv('SIGH_BANC') === '1' && strncmp($secret, 'puits-', 6) === 0;
}

/**
 * Le faux fournisseur : même forme de réponse que le vrai. Le mode vient du SECRET lui-même (jamais d'un réglage serveur).
 * @return array{statut:int,corps:string,erreur:?string}
 */
function sigh_sms_puits(string $fournisseur, array $champs, string $secret): array
{
    $mode = substr($secret, 6);
    $enreg = ['fournisseur' => $fournisseur, 'mode' => $mode, 'a' => $champs['to'] ?? $champs['To'] ?? '', 'de' => $champs['from'] ?? $champs['From'] ?? ($champs['MessagingServiceSid'] ?? ''), 'texte' => $champs['text'] ?? $champs['Body'] ?? '', 'le' => date('c')];
    $l = sigh_sms_puits_lire();
    $l[] = $enreg;
    sigh_sms_puits_ecrire($l);
    if (strncmp($mode, 'injoignable', 11) === 0) {
        return ['statut' => 0, 'corps' => '', 'erreur' => 'Could not resolve host (puits)'];
    }
    $mauvaisNumero = substr((string) $enreg['a'], -4) === '0000';
    $mauvaisExpediteur = $enreg['de'] === 'REFUSE';
    if ($fournisseur === 'twilio') {
        if (strncmp($mode, 'refuse', 6) === 0) {
            return ['statut' => 401, 'corps' => json_encode(['code' => 20003, 'message' => 'Authenticate', 'status' => 401]), 'erreur' => null];
        }
        if (strncmp($mode, 'solde', 5) === 0) {
            return ['statut' => 402, 'corps' => json_encode(['code' => 20003, 'message' => 'Account balance is too low', 'status' => 402]), 'erreur' => null];
        }
        if ($mauvaisNumero) {
            return ['statut' => 400, 'corps' => json_encode(['code' => 21211, 'message' => 'Invalid To phone number', 'status' => 400]), 'erreur' => null];
        }
        if ($mauvaisExpediteur) {
            return ['statut' => 400, 'corps' => json_encode(['code' => 21606, 'message' => 'From phone number not usable', 'status' => 400]), 'erreur' => null];
        }
        return ['statut' => 201, 'corps' => json_encode(['sid' => 'SM' . bin2hex(random_bytes(12)), 'status' => 'queued']), 'erreur' => null];
    }
    /* Vonage : toujours HTTP 200, l'état est dans messages[0].status */
    $statut = '0';
    if (strncmp($mode, 'refuse', 6) === 0) {
        $statut = '4';
    } elseif (strncmp($mode, 'solde', 5) === 0) {
        $statut = '9';
    } elseif ($mauvaisNumero) {
        $statut = '3';
    } elseif ($mauvaisExpediteur) {
        $statut = '15';
    }
    $m = $statut === '0' ? ['status' => '0', 'message-id' => bin2hex(random_bytes(8))] : ['status' => $statut, 'error-text' => 'Refus du puits (' . $statut . ')'];
    return ['statut' => 200, 'corps' => json_encode(['message-count' => '1', 'messages' => [$m]]), 'erreur' => null];
}

/**
 * POST d'un formulaire. `$auth` : [utilisateur, secret] pour l'authentification de base (Twilio), sinon null.
 * @return array{statut:int,corps:string,erreur:?string}
 */
function sigh_sms_http(string $fournisseur, string $url, array $champs, ?array $auth, string $secretPuits, int $delai): array
{
    if (sigh_sms_est_puits($secretPuits)) {
        return sigh_sms_puits($fournisseur, $champs, $secretPuits);
    }
    if (!function_exists('curl_init')) {
        return ['statut' => 0, 'corps' => '', 'erreur' => 'extension cURL absente'];
    }
    $c = curl_init($url);
    curl_setopt_array($c, [
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => http_build_query($champs),
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT => $delai,
        CURLOPT_TIMEOUT => $delai,
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_SSL_VERIFYHOST => 2,
        CURLOPT_HTTPHEADER => ['Accept: application/json'],
    ]);
    if ($auth !== null) {
        curl_setopt($c, CURLOPT_USERPWD, $auth[0] . ':' . $auth[1]);
    }
    $corps = curl_exec($c);
    $erreur = $corps === false ? curl_error($c) : null;
    $statut = (int) curl_getinfo($c, CURLINFO_RESPONSE_CODE);
    curl_close($c);
    return ['statut' => $statut, 'corps' => is_string($corps) ? $corps : '', 'erreur' => $erreur];
}

/* =============================================================================
 * Les adaptateurs : demande + lecture de la réponse du fournisseur
 *
 * LA CORRESPONDANCE « code du fournisseur → refus nommé » est écrite d'après la documentation publique des deux fournisseurs
 * et NON ÉPROUVÉE contre un vrai compte : à confirmer à la recette (le solde insuffisant de Twilio, en particulier, n'a pas de code
 * que cette maquette ait pu vérifier). Un code non classé n'est jamais pris pour un succès : il sort en FOURNISSEUR_REFUS.
 * ========================================================================== */

/**
 * @param array $cfg {fournisseur, expediteur, serviceSid?, secrets:{twilioSid,twilioToken,vonageCle,vonageSecret}, delai?}
 * @return array{ok:bool,code:?string,detail:string,idMessage:?string}
 */
function sigh_sms_adaptateur(array $cfg, string $e164, string $texte): array
{
    $s = (array) ($cfg['secrets'] ?? []);
    $delai = max(3, min(60, (int) ($cfg['delai'] ?? 15)));
    $secrets = array_values($s);
    $echec = function (string $code, string $detail = '') use ($secrets): array {
        return ['ok' => false, 'code' => $code, 'detail' => sigh_sms_masquer_secrets($detail, $secrets), 'idMessage' => null];
    };

    if (($cfg['fournisseur'] ?? 'twilio') === 'vonage') {
        $r = sigh_sms_http('vonage', 'https://rest.nexmo.com/sms/json', [
            'api_key' => (string) ($s['vonageCle'] ?? ''), 'api_secret' => (string) ($s['vonageSecret'] ?? ''),
            'from' => (string) $cfg['expediteur'], 'to' => ltrim($e164, '+'), 'text' => $texte, 'type' => 'unicode',
        ], null, (string) ($s['vonageSecret'] ?? ''), $delai);
        if ($r['erreur'] !== null) {
            return $echec('FOURNISSEUR_INJOIGNABLE');
        }
        $j = json_decode($r['corps'], true);
        $m = is_array($j) ? ($j['messages'][0] ?? null) : null;
        if (!is_array($m)) {
            return $echec('FOURNISSEUR_REFUS', 'Réponse illisible (HTTP ' . $r['statut'] . ').');
        }
        $st = (string) ($m['status'] ?? '');
        if ($st === '0') {
            return ['ok' => true, 'code' => null, 'detail' => '', 'idMessage' => (string) ($m['message-id'] ?? '')];
        }
        $texteF = (string) ($m['error-text'] ?? '');
        $carte = ['4' => 'IDENTIFIANTS_REFUSES', '9' => 'SOLDE_INSUFFISANT', '15' => 'EXPEDITEUR_NON_AUTORISE', '3' => 'NUMERO_INVALIDE', '7' => 'NUMERO_INVALIDE'];
        return isset($carte[$st]) ? $echec($carte[$st]) : $echec('FOURNISSEUR_REFUS', 'Vonage, statut ' . $st . ($texteF !== '' ? ' : ' . $texteF : '') . '.');
    }

    $sid = (string) ($s['twilioSid'] ?? '');
    $champs = ['To' => $e164, 'Body' => $texte];
    if (!empty($cfg['serviceSid'])) {
        $champs['MessagingServiceSid'] = (string) $cfg['serviceSid'];
    } else {
        $champs['From'] = (string) $cfg['expediteur'];
    }
    $r = sigh_sms_http('twilio', 'https://api.twilio.com/2010-04-01/Accounts/' . rawurlencode($sid) . '/Messages.json', $champs,
        [$sid, (string) ($s['twilioToken'] ?? '')], (string) ($s['twilioToken'] ?? ''), $delai);
    if ($r['erreur'] !== null) {
        return $echec('FOURNISSEUR_INJOIGNABLE');
    }
    $j = json_decode($r['corps'], true);
    $j = is_array($j) ? $j : [];
    if ($r['statut'] >= 200 && $r['statut'] < 300 && !empty($j['sid'])) {
        return ['ok' => true, 'code' => null, 'detail' => '', 'idMessage' => (string) $j['sid']];
    }
    $cf = (int) ($j['code'] ?? 0);
    $texteF = (string) ($j['message'] ?? '');
    if ($r['statut'] === 402) {
        return $echec('SOLDE_INSUFFISANT');
    }
    if ($r['statut'] === 401 || $cf === 20003) {
        return $echec('IDENTIFIANTS_REFUSES');
    }
    if (in_array($cf, [21211, 21614], true)) {
        return $echec('NUMERO_INVALIDE');
    }
    if (in_array($cf, [21212, 21606, 21612], true)) {
        return $echec('EXPEDITEUR_NON_AUTORISE');
    }
    return $echec('FOURNISSEUR_REFUS', 'Twilio, HTTP ' . $r['statut'] . ($cf ? ', code ' . $cf : '') . ($texteF !== '' ? ' : ' . $texteF : '') . '.');
}

/* =============================================================================
 * La suite d'étapes : ce que la passerelle contrôle AVANT de parler au fournisseur
 * ========================================================================== */

/** La configuration est-elle complète pour le fournisseur choisi ? Rend le détail de ce qui manque, ou null. */
function sigh_sms_manque(array $cfg): ?string
{
    $s = (array) ($cfg['secrets'] ?? []);
    $manque = [];
    if (($cfg['fournisseur'] ?? 'twilio') === 'vonage') {
        foreach (['vonageCle' => 'clé API', 'vonageSecret' => 'secret API'] as $k => $l) {
            if (empty($s[$k])) {
                $manque[] = $l . ' Vonage';
            }
        }
    } else {
        foreach (['twilioSid' => 'Account SID', 'twilioToken' => 'jeton d’authentification'] as $k => $l) {
            if (empty($s[$k])) {
                $manque[] = $l . ' Twilio';
            }
        }
    }
    $exp = (string) ($cfg['expediteur'] ?? '');
    $svc = (string) ($cfg['serviceSid'] ?? '');
    if (($cfg['fournisseur'] ?? 'twilio') === 'twilio' && $svc !== '') {
        if (!preg_match('/^MG[0-9a-fA-F]{32}$/', $svc)) {
            $manque[] = 'Messaging Service SID valide (MG puis 32 caractères hexadécimaux)';
        }
    } elseif ($exp === '') {
        $manque[] = 'expéditeur';
    } elseif (!sigh_sms_expediteur_valide($exp)) {
        $manque[] = 'expéditeur valide (numéro E.164, ou identifiant de 1 à 11 caractères avec une lettre)';
    }
    return $manque ? 'Manque : ' . implode(', ', $manque) . '.' : null;
}

/**
 * @param array $cfg  configuration prête à servir (secrets en clair, en mémoire seulement)
 * @return array{ok:bool,statut:string,code:?string,motif:string,geste:?string,etapes:list<array>,idMessage:?string,numeroMasque:string,reporteA:?string,fournisseur:string}
 */
function sigh_sms_suite(array $cfg, string $motif, string $numeroBrut, string $texte, DateTimeImmutable $maintenant, int $envoyesAujourdhui, bool $exigerActif): array
{
    $etapes = [];
    $fournisseur = ($cfg['fournisseur'] ?? 'twilio') === 'vonage' ? 'vonage' : 'twilio';
    $e164 = sigh_sms_numero($numeroBrut);
    $masque = sigh_sms_masquer($e164 ?? $numeroBrut);
    $fin = function (string $code, string $detail = '', ?string $reporteA = null) use (&$etapes, $fournisseur, $masque): array {
        $r = sigh_sms_refus($code, $detail);
        return ['ok' => false, 'statut' => $code === 'HEURES_CALMES' ? 'reporte' : 'refuse', 'code' => $code, 'motif' => $r['motif'], 'geste' => $r['geste'],
            'etapes' => $etapes, 'idMessage' => null, 'numeroMasque' => $masque, 'reporteA' => $reporteA, 'fournisseur' => $fournisseur];
    };
    $etape = function (string $nom, bool $ok, string $detail) use (&$etapes): bool {
        $etapes[] = ['etape' => $nom, 'ok' => $ok, 'detail' => $detail];
        return $ok;
    };

    if (!isset(SIGH_SMS_MOTIFS[$motif])) {
        $etape('motif', false, 'Motif inconnu.');
        return $fin('MOTIF_INCONNU');
    }
    $etape('motif', true, SIGH_SMS_MOTIFS[$motif]['libelle'] . '.');

    $manque = sigh_sms_manque($cfg);
    if ($manque !== null) {
        $etape('configuration', false, $manque);
        return $fin('SMS_NON_CONFIGUREE', $manque);
    }
    if ($exigerActif && empty($cfg['actif'])) {
        $etape('configuration', false, 'Passerelle désactivée.');
        return $fin('SMS_DESACTIVEE');
    }
    $etape('configuration', true, 'Fournisseur ' . ($fournisseur === 'vonage' ? 'Vonage' : 'Twilio') . ', identifiants et expéditeur renseignés.');

    if ($e164 === null) {
        $etape('numero', false, 'Format refusé.');
        return $fin('NUMERO_INVALIDE');
    }
    $etape('numero', true, 'Numéro valide ' . $masque . '.');

    $longueur = mb_strlen($texte, 'UTF-8');
    if ($longueur < 1 || $longueur > 320) {
        $etape('texte', false, $longueur . ' caractères.');
        return $fin('TEXTE_INVALIDE');
    }
    $mot = sigh_sms_mot_medical($texte);
    if ($mot !== null) {
        $etape('texte', false, 'Mot de la liste médicale : « ' . $mot . ' ».');
        return $fin('DONNEE_MEDICALE', 'Mot repéré : « ' . $mot . ' ».');
    }
    $etape('texte', true, $longueur . ' caractères, aucun mot de la liste médicale.');

    $plafond = max(1, (int) ($cfg['plafondJour'] ?? 200));
    if ($envoyesAujourdhui >= $plafond) {
        $etape('plafond', false, $envoyesAujourdhui . ' envoi(s) aujourd’hui sur ' . $plafond . '.');
        return $fin('PLAFOND_ATTEINT', 'Aujourd’hui : ' . $envoyesAujourdhui . ' sur ' . $plafond . '.');
    }
    $etape('plafond', true, $envoyesAujourdhui . ' envoi(s) aujourd’hui sur ' . $plafond . '.');

    $calme = sigh_sms_heures_calmes($cfg, $maintenant);
    if ($calme !== null && !SIGH_SMS_MOTIFS[$motif]['urgent']) {
        $etape('heures_calmes', false, 'Report à ' . $calme->format('H\hi') . '.');
        return $fin('HEURES_CALMES', 'Reprise à ' . $calme->format('H\hi') . ' (heure du Bénin).', $calme->format('c'));
    }
    $etape('heures_calmes', true, $calme !== null ? 'Heures calmes en cours, message urgent : exempté.' : 'Hors des heures calmes.');

    $r = sigh_sms_adaptateur($cfg, $e164, $texte);
    if (!$r['ok']) {
        $etape('fournisseur', false, $r['detail'] !== '' ? $r['detail'] : 'Refusé.');
        return $fin((string) $r['code'], $r['detail']);
    }
    $etape('fournisseur', true, 'Accepté par le fournisseur, identifiant ' . $r['idMessage'] . '.');
    return ['ok' => true, 'statut' => 'accepte', 'code' => null, 'motif' => 'Message accepté par le fournisseur. Accepté ne veut pas dire reçu : le rapport de livraison viendra en P1.', 'geste' => null,
        'etapes' => $etapes, 'idMessage' => $r['idMessage'], 'numeroMasque' => $masque, 'reporteA' => null, 'fournisseur' => $fournisseur];
}
