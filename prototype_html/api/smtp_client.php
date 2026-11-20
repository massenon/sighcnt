<?php
/* =============================================================================
 * SIGH-CNT — Client SMTP minimal (sockets), sans dépendance
 * -----------------------------------------------------------------------------
 * Un courriel part par UNE suite d'étapes, et c'est la suite que l'on montre :
 * un « échec d'envoi » qui ne dit pas où l'on a échoué (le serveur est-il
 * joignable ? le certificat est-il refusé ? le mot de passe est-il mauvais ? le
 * destinataire est-il refusé ?) renvoie l'administrateur chercher au mauvais
 * endroit. Chaque étape rend donc `{ etape, ok, detail }` et la suite s'ARRÊTE
 * à la première qui échoue.
 *
 *   connexion → salutation → chiffrement → authentification
 *             → expéditeur → destinataire → envoi
 *
 * Chiffrement : `aucun`, `starttls` (port 587) ou `ssl` (port 465). Le contrôle
 * du certificat est ACTIF par défaut ; le désactiver est un réglage nommé, jamais
 * un défaut. Le corps est toujours envoyé en base64 UTF-8 : un accent ne dépend
 * pas de la prise en charge de 8BITMIME par le serveur.
 *
 * Le mot de passe n'est ni journalisé ni rendu : aucune réponse de ce fichier
 * ne le contient, les réponses du serveur qui l'afficheraient sont masquées.
 * ========================================================================== */

/** Lit une réponse SMTP complète (lignes « 250-… » puis « 250 … »). @return array{0:int,1:string} */
function sigh_smtp_lire($flux): array
{
    $texte = '';
    $code = 0;
    while (($ligne = fgets($flux, 2048)) !== false) {
        $texte .= $ligne;
        if (strlen($ligne) >= 4 && $ligne[3] === ' ') {
            $code = (int) substr($ligne, 0, 3);
            return [$code, trim($texte)];
        }
        if (strlen($ligne) < 4) {
            break;
        }
    }
    $meta = stream_get_meta_data($flux);
    return [0, $meta['timed_out'] ? 'délai dépassé' : 'connexion fermée par le serveur'];
}

function sigh_smtp_cmd($flux, string $cmd): array
{
    fwrite($flux, $cmd . "\r\n");
    return sigh_smtp_lire($flux);
}

/** En-tête encodé UTF-8 (RFC 2047) si nécessaire. */
function sigh_smtp_entete_texte(string $s): string
{
    return preg_match('/[^\x20-\x7e]/', $s) ? '=?UTF-8?B?' . base64_encode($s) . '?=' : $s;
}

/** Ôte les retours à la ligne d'une valeur d'en-tête : aucune injection d'en-tête possible. */
function sigh_smtp_nettoyer(string $s): string
{
    return trim(preg_replace('/[\r\n]+/', ' ', $s));
}

/**
 * @param array{serveur:string,port:int,chiffrement:string,identifiant?:string,motDePasse?:string,expediteur:string,nom?:string,repondreA?:string,repondreNom?:string,delai?:int,verifierCertificat?:bool} $cfg
 * @return array{ok:bool,etapes:list<array{etape:string,ok:bool,detail:string}>,echec:?string}
 */
function sigh_smtp_envoyer(array $cfg, array $destinataires, string $sujet, string $corps): array
{
    $etapes = [];
    $fin = function (?string $echec) use (&$etapes): array {
        return ['ok' => $echec === null, 'etapes' => $etapes, 'echec' => $echec];
    };
    $ajouter = function (string $etape, bool $ok, string $detail) use (&$etapes): bool {
        $etapes[] = ['etape' => $etape, 'ok' => $ok, 'detail' => $detail];
        return $ok;
    };
    $masquer = function (string $s) use ($cfg): string {
        $mdp = (string) ($cfg['motDePasse'] ?? '');
        if ($mdp !== '') {
            $s = str_replace([$mdp, base64_encode($mdp)], '***', $s);
        }
        return $s;
    };

    $delai = max(3, min(60, (int) ($cfg['delai'] ?? 15)));
    $chiffrement = (string) ($cfg['chiffrement'] ?? 'starttls');
    $verifier = ($cfg['verifierCertificat'] ?? true) !== false;
    $hote = (string) $cfg['serveur'];
    $port = (int) $cfg['port'];
    $expediteur = sigh_smtp_nettoyer((string) $cfg['expediteur']);

    if ($hote === '' || $port <= 0 || !filter_var($expediteur, FILTER_VALIDATE_EMAIL)) {
        $ajouter('connexion', false, 'Configuration incomplète : serveur, port et adresse d’expéditeur valides sont requis.');
        return $fin('connexion');
    }
    foreach ($destinataires as $d) {
        if (!filter_var($d, FILTER_VALIDATE_EMAIL)) {
            $ajouter('destinataire', false, 'Adresse de destinataire invalide : ' . sigh_smtp_nettoyer((string) $d));
            return $fin('destinataire');
        }
    }

    /* --- 1. connexion --------------------------------------------------- */
    $ctx = stream_context_create(['ssl' => [
        'verify_peer' => $verifier, 'verify_peer_name' => $verifier, 'allow_self_signed' => !$verifier,
        'peer_name' => $hote, 'SNI_enabled' => true,
    ]]);
    $cible = ($chiffrement === 'ssl' ? 'ssl://' : 'tcp://') . $hote . ':' . $port;
    $errno = 0;
    $errstr = '';
    $flux = @stream_socket_client($cible, $errno, $errstr, $delai, STREAM_CLIENT_CONNECT, $ctx);
    if (!$flux) {
        $certificat = $chiffrement === 'ssl' && (stripos($errstr, 'certificate') !== false || stripos($errstr, 'SSL') !== false);
        $ajouter($certificat ? 'chiffrement' : 'connexion', false,
            $certificat ? 'Connexion chiffrée refusée (certificat ou protocole) : ' . $errstr
                        : 'Serveur injoignable sur ' . $hote . ':' . $port . ' (' . ($errstr ?: 'erreur ' . $errno) . ').');
        return $fin($certificat ? 'chiffrement' : 'connexion');
    }
    stream_set_timeout($flux, $delai);
    [$code, $rep] = sigh_smtp_lire($flux);
    if ($code !== 220) {
        $ajouter('connexion', false, 'Le serveur n’a pas accueilli la connexion : ' . $masquer($rep));
        fclose($flux);
        return $fin('connexion');
    }
    $ajouter('connexion', true, 'Connecté à ' . $hote . ':' . $port . '.');

    $nomLocal = preg_replace('/[^A-Za-z0-9.-]/', '', (string) (gethostname() ?: 'sigh-cnt')) ?: 'sigh-cnt';
    $quitter = function () use ($flux): void {
        @fwrite($flux, "QUIT\r\n");
        @fclose($flux);
    };

    /* --- 2. salutation -------------------------------------------------- */
    [$code, $rep] = sigh_smtp_cmd($flux, 'EHLO ' . $nomLocal);
    if ($code !== 250) {
        [$code, $rep] = sigh_smtp_cmd($flux, 'HELO ' . $nomLocal);
    }
    if ($code !== 250) {
        $ajouter('salutation', false, 'Le serveur refuse la salutation : ' . $masquer($rep));
        $quitter();
        return $fin('salutation');
    }
    $ajouter('salutation', true, 'Salutation acceptée.');

    /* --- 3. chiffrement ------------------------------------------------- */
    if ($chiffrement === 'starttls') {
        if (stripos($rep, 'STARTTLS') === false) {
            $ajouter('chiffrement', false, 'Le serveur n’annonce pas STARTTLS : choisir « SSL » ou « Aucun ».');
            $quitter();
            return $fin('chiffrement');
        }
        [$code, $r2] = sigh_smtp_cmd($flux, 'STARTTLS');
        if ($code !== 220) {
            $ajouter('chiffrement', false, 'STARTTLS refusé : ' . $masquer($r2));
            $quitter();
            return $fin('chiffrement');
        }
        $ok = @stream_socket_enable_crypto($flux, true, STREAM_CRYPTO_METHOD_TLS_CLIENT);
        if ($ok !== true) {
            $ajouter('chiffrement', false, 'Négociation TLS refusée' . ($verifier ? ' (certificat non reconnu : l’autorité n’est pas de confiance, ou le nom ne correspond pas)' : '') . '.');
            @fclose($flux);
            return $fin('chiffrement');
        }
        $ajouter('chiffrement', true, 'Connexion chiffrée (STARTTLS)' . ($verifier ? ', certificat vérifié.' : ', certificat NON vérifié (réglage).'));
        [$code, $rep] = sigh_smtp_cmd($flux, 'EHLO ' . $nomLocal);
        if ($code !== 250) {
            $ajouter('salutation', false, 'Salutation refusée après chiffrement : ' . $masquer($rep));
            $quitter();
            return $fin('salutation');
        }
    } elseif ($chiffrement === 'ssl') {
        $ajouter('chiffrement', true, 'Connexion chiffrée (SSL)' . ($verifier ? ', certificat vérifié.' : ', certificat NON vérifié (réglage).'));
    } else {
        $ajouter('chiffrement', true, 'Aucun chiffrement (réglage) : le mot de passe circulerait en clair.');
    }

    /* --- 4. authentification -------------------------------------------- */
    $id = (string) ($cfg['identifiant'] ?? '');
    $mdp = (string) ($cfg['motDePasse'] ?? '');
    if ($id !== '') {
        [$code, $r2] = sigh_smtp_cmd($flux, 'AUTH PLAIN ' . base64_encode("\0" . $id . "\0" . $mdp));
        if ($code !== 235) {
            [$c1, $r1] = sigh_smtp_cmd($flux, 'AUTH LOGIN');
            if ($c1 === 334) {
                [$c2] = sigh_smtp_cmd($flux, base64_encode($id));
                if ($c2 === 334) {
                    [$code, $r2] = sigh_smtp_cmd($flux, base64_encode($mdp));
                }
            }
        }
        if ($code !== 235) {
            $ajouter('authentification', false, 'Identifiant ou mot de passe refusé par le serveur : ' . $masquer($r2));
            $quitter();
            return $fin('authentification');
        }
        $ajouter('authentification', true, 'Authentifié comme ' . $id . '.');
    } else {
        $ajouter('authentification', true, 'Aucune authentification demandée (identifiant vide).');
    }

    /* --- 5. expéditeur, 6. destinataires -------------------------------- */
    [$code, $rep] = sigh_smtp_cmd($flux, 'MAIL FROM:<' . $expediteur . '>');
    if ($code !== 250) {
        $ajouter('expéditeur', false, 'Adresse d’expéditeur refusée : ' . $masquer($rep));
        $quitter();
        return $fin('expéditeur');
    }
    $ajouter('expéditeur', true, 'Expéditeur accepté.');
    foreach ($destinataires as $d) {
        [$code, $rep] = sigh_smtp_cmd($flux, 'RCPT TO:<' . $d . '>');
        if ($code !== 250 && $code !== 251) {
            $ajouter('destinataire', false, 'Destinataire refusé (' . $d . ') : ' . $masquer($rep));
            $quitter();
            return $fin('destinataire');
        }
    }
    $ajouter('destinataire', true, count($destinataires) . ' destinataire(s) accepté(s).');

    /* --- 7. envoi ------------------------------------------------------- */
    [$code, $rep] = sigh_smtp_cmd($flux, 'DATA');
    if ($code !== 354) {
        $ajouter('envoi', false, 'Le serveur refuse le contenu : ' . $masquer($rep));
        $quitter();
        return $fin('envoi');
    }
    $nom = sigh_smtp_nettoyer((string) ($cfg['nom'] ?? ''));
    $domaine = substr(strrchr($expediteur, '@') ?: '@sigh-cnt.local', 1);
    /* « Répondre à » : une adresse valide, avec son nom si on en donne un ; invalide ou vide, l'en-tête est omis (jamais une adresse devinée). */
    $rep = sigh_smtp_nettoyer((string) ($cfg['repondreA'] ?? ''));
    $repNom = sigh_smtp_nettoyer((string) ($cfg['repondreNom'] ?? ''));
    $replyTo = filter_var($rep, FILTER_VALIDATE_EMAIL) ? ($repNom !== '' ? sigh_smtp_entete_texte($repNom) . ' <' . $rep . '>' : $rep) : null;
    $entetes = [
        'Date: ' . date('r'),
        'From: ' . ($nom !== '' ? sigh_smtp_entete_texte($nom) . ' <' . $expediteur . '>' : $expediteur),
        'To: ' . implode(', ', $destinataires),
        ...($replyTo !== null ? ['Reply-To: ' . $replyTo] : []),
        'Subject: ' . sigh_smtp_entete_texte(sigh_smtp_nettoyer($sujet)),
        'Message-ID: <' . bin2hex(random_bytes(12)) . '@' . $domaine . '>',
        'MIME-Version: 1.0',
        'Content-Type: text/plain; charset=UTF-8',
        'Content-Transfer-Encoding: base64',
    ];
    $message = implode("\r\n", $entetes) . "\r\n\r\n" . chunk_split(base64_encode($corps), 76, "\r\n");
    /* dot-stuffing : une ligne qui commence par un point en gagne un second */
    $message = preg_replace('/^\./m', '..', $message);
    fwrite($flux, $message . "\r\n.\r\n");
    [$code, $rep] = sigh_smtp_lire($flux);
    if ($code !== 250) {
        $ajouter('envoi', false, 'Le serveur a refusé le message : ' . $masquer($rep));
        $quitter();
        return $fin('envoi');
    }
    $ajouter('envoi', true, 'Message accepté par le serveur : ' . $masquer($rep));
    $quitter();
    return $fin(null);
}
