<?php

namespace App\Relais;

use App\Mail\TestSmtpMail;
use Illuminate\Contracts\Mail\Mailable;
use Illuminate\Mail\Mailer;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Mail;
use Symfony\Component\Mailer\Exception\TransportExceptionInterface;
use Throwable;

/**
 * LA MESSAGERIE SMTP DU RELAIS : réglée dans le panneau du superadmin, jamais dans un fichier. Le mot de passe est CHIFFRÉ par la clé de l'application (APP_KEY)
 * avant d'entrer en base, n'est jamais relu ni affiché (le formulaire dit seulement « défini »), jamais journalisé. Le transport est construit à l'EXÉCUTION depuis
 * ces réglages ; sans réglage, le relais n'envoie RIEN et le dit (`smtp_non_configure`) au lieu de laisser croire qu'un courriel est parti.
 *
 * Quand un envoi échoue, l'ÉTAPE en cause est nommée : connexion, chiffrement (STARTTLS, certificat), authentification, expéditeur, destinataire, envoi. Elle se lit
 * dans la conversation SMTP que le transport garde (`getDebug`), pas en devinant sur le texte seul.
 */
class ReglagesSmtp
{
    public const CHIFFREMENTS = ['aucun', 'starttls', 'ssl'];

    private const CLES = ['hote', 'port', 'chiffrement', 'utilisateur', 'mdp', 'expediteur', 'expediteur_nom', 'repondre', 'repondre_nom', 'verifier'];

    private static function meta(string $k): ?string
    {
        return DB::table('relais_meta')->where('k', 'smtp_'.$k)->value('v');
    }

    private static function poser(string $k, ?string $v): void
    {
        DB::table('relais_meta')->updateOrInsert(['k' => 'smtp_'.$k], ['v' => $v]);
    }

    /** @return array<string,mixed> ce que le formulaire peut afficher : JAMAIS le mot de passe, seulement s'il est défini. */
    public static function lire(): array
    {
        return [
            'hote' => (string) self::meta('hote'),
            'port' => (int) (self::meta('port') ?: 587),
            'chiffrement' => self::meta('chiffrement') ?: 'starttls',
            'utilisateur' => (string) self::meta('utilisateur'),
            'mdp_defini' => (string) self::meta('mdp') !== '',
            'expediteur' => (string) self::meta('expediteur'),
            'expediteur_nom' => (string) self::meta('expediteur_nom'),
            'repondre' => (string) self::meta('repondre'),
            'repondre_nom' => (string) self::meta('repondre_nom'),
            'verifier_certificat' => self::meta('verifier') !== '0',
        ];
    }

    public static function configure(): bool
    {
        return trim((string) self::meta('hote')) !== '' && filter_var(self::meta('expediteur'), FILTER_VALIDATE_EMAIL) !== false;
    }

    /**
     * Enregistre les réglages. [$mdp] : `null` ou vide = conserver l'ancien ; [$effacerMdp] le retire. Rend les clés changées (jamais les valeurs secrètes).
     *
     * @param  array<string,mixed>  $v
     */
    public static function enregistrer(array $v, ?string $mdp, bool $effacerMdp = false): void
    {
        self::poser('hote', trim((string) $v['hote']));
        self::poser('port', (string) (int) $v['port']);
        self::poser('chiffrement', (string) $v['chiffrement']);
        self::poser('utilisateur', trim((string) ($v['utilisateur'] ?? '')));
        self::poser('expediteur', trim((string) $v['expediteur']));
        self::poser('expediteur_nom', trim((string) ($v['expediteur_nom'] ?? '')));
        self::poser('repondre', trim((string) ($v['repondre'] ?? '')));
        self::poser('repondre_nom', trim((string) ($v['repondre_nom'] ?? '')));
        self::poser('verifier', ! empty($v['verifier_certificat']) ? '1' : '0');
        if ($effacerMdp) {
            self::poser('mdp', null);
        } elseif ($mdp !== null && $mdp !== '') {
            self::poser('mdp', Crypt::encryptString($mdp));
        }
    }

    private static function motDePasse(): ?string
    {
        $c = self::meta('mdp');
        if ($c === null || $c === '') {
            return null;
        }
        try {
            return Crypt::decryptString($c);
        } catch (Throwable) {
            return null;
        }
    }

    /** Le mailer construit depuis les réglages enregistrés (nom « relais_smtp », reconstruit à chaque appel : un réglage modifié prend effet aussitôt). */
    public static function mailer(): Mailer
    {
        $chiffrement = self::meta('chiffrement') ?: 'starttls';
        $config = [
            'transport' => 'smtp',
            'host' => trim((string) self::meta('hote')),
            'port' => (int) (self::meta('port') ?: 587),
            'scheme' => $chiffrement === 'ssl' ? 'smtps' : 'smtp',
            'username' => (self::meta('utilisateur') ?: null),
            'password' => self::motDePasse(),
            'timeout' => 15,
            'verify_peer' => self::meta('verifier') !== '0',
            'local_domain' => parse_url((string) config('app.url'), PHP_URL_HOST) ?: 'localhost',
        ];
        if ($chiffrement === 'aucun') {
            $config['auto_tls'] = false;
        } elseif ($chiffrement === 'starttls') {
            $config['require_tls'] = true;
        }
        config(['mail.mailers.relais_smtp' => $config]);
        Mail::purge('relais_smtp');

        return Mail::mailer('relais_smtp');
    }

    /** Envoie [$mail] à [$a] par le SMTP réglé. Lève [EnvoiEchoue] avec l'étape en cause ; [$mail] reçoit l'expéditeur réglé. */
    public static function envoyer(string $a, Mailable $mail): void
    {
        $expediteur = (string) self::meta('expediteur');
        $nom = (string) self::meta('expediteur_nom');
        if (method_exists($mail, 'from')) {
            $mail->from($expediteur, $nom !== '' ? $nom : null);
        }
        $repondre = (string) self::meta('repondre');
        if ($repondre !== '' && method_exists($mail, 'replyTo')) {
            $nomRepondre = (string) self::meta('repondre_nom');
            $mail->replyTo($repondre, $nomRepondre !== '' ? $nomRepondre : null);
        }
        try {
            self::mailer()->to($a)->sendNow($mail);
        } catch (Throwable $e) {
            throw self::classer($e);
        }
    }

    /** Le message de test du bouton : accents compris, pour vérifier l'encodage de bout en bout. */
    public static function envoyerTest(string $a): void
    {
        self::envoyer($a, new TestSmtpMail);
    }

    /** L'étape en cause, déduite de la DERNIÈRE commande SMTP émise (conversation gardée par le transport) puis du message. */
    public static function classer(Throwable $e): EnvoiEchoue
    {
        $message = $e->getMessage();
        $debug = $e instanceof TransportExceptionInterface ? $e->getDebug() : '';
        $mdp = self::motDePasse();
        // La commande qui a reçu la PREMIÈRE réponse d'erreur (4xx ou 5xx) : après elle le transport envoie RSET et QUIT, qui ne disent rien de la cause.
        $derniere = '';
        $fautive = '';
        foreach (preg_split('/\R/', $debug) ?: [] as $l) {
            // chaque ligne du transport porte un horodatage : « [2026-…] > RCPT TO:<…> » (commande émise) ou « [2026-…] < 550 … » (réponse)
            if (! preg_match('/^(?:\[[^\]]*\]\s+)?([<>])\s(.*)$/', $l, $x)) {
                continue;
            }
            if ($x[1] === '>') {
                $derniere = strtoupper(substr($x[2], 0, 12));
            } elseif ($fautive === '' && preg_match('/^[45]\d\d/', $x[2])) {
                $fautive = $derniere;
            }
        }
        if ($fautive !== '') {
            $derniere = $fautive;
        }
        if (stripos($message, 'Connection could not be established') !== false || stripos($message, 'Connection refused') !== false || stripos($message, 'getaddrinfo') !== false) {
            $etape = 'connexion';
        } elseif (stripos($message, 'Failed to authenticate') !== false || str_starts_with($derniere, 'AUTH') || stripos($message, 'got code "535"') !== false || stripos($message, 'got code "530"') !== false) {
            $etape = 'authentification';
        } elseif (stripos($message, 'STARTTLS') !== false || stripos($message, 'crypto') !== false || stripos($message, 'SSL') !== false || stripos($message, 'certificate') !== false || str_starts_with($derniere, 'STARTTLS')) {
            $etape = 'chiffrement';
        } elseif (str_starts_with($derniere, 'RCPT')) {
            $etape = 'destinataire';
        } elseif (str_starts_with($derniere, 'MAIL')) {
            $etape = 'expediteur';
        } elseif (stripos($message, 'timed out') !== false || stripos($message, 'Unable to read') !== false) {
            $etape = 'connexion';
        } else {
            $etape = 'envoi';
        }
        // Le motif ne doit JAMAIS porter le mot de passe, même si un serveur le répétait.
        if ($mdp !== null && $mdp !== '') {
            $message = str_replace($mdp, '••••••••', $message);
        }

        return new EnvoiEchoue($etape, mb_substr(trim(preg_replace('/\s+/', ' ', $message) ?? $message), 0, 400), $e);
    }

    /** Les libellés lisibles des étapes, pour l'écran. */
    public const ETAPES = [
        'connexion' => 'Connexion au serveur impossible : vérifier l\'adresse, le port et le pare-feu.',
        'chiffrement' => 'Chiffrement refusé : vérifier le mode (STARTTLS ou SSL) et le certificat du serveur.',
        'authentification' => 'Identifiant ou mot de passe refusé par le serveur.',
        'expediteur' => 'Adresse d\'expéditeur refusée par le serveur.',
        'destinataire' => 'Adresse du destinataire refusée par le serveur.',
        'envoi' => 'Le serveur a refusé ou perdu le message.',
    ];
}
