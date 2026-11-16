<?php

namespace App\Relais\Satisfaction;

use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Support\Facades\DB;

/**
 * LA SATISFACTION EN LIGNE DU RELAIS (lot SAT, ADR-0009). Ce fichier n'importe AUCUNE fonction de déchiffrement et ne détient AUCUNE clé privée : il vérifie la FORME d'une enveloppe
 * (version, identifiant, clé éphémère de 32 octets, vecteur de 12 octets, texte chiffré d'une des tailles de rembourrage), sa TAILLE (16 Kio au plus) et le DÉBIT par empreinte d'adresse,
 * puis stocke l'enveloppe telle quelle. Il ne sait ni qui répond ni ce qui est répondu. Contrat de l'enveloppe : docs/architecture/adr/ADR-0009-satisfaction-en-ligne.md.
 */
class Entrepot
{
    public const ENVELOPPE_MAX = 16384;
    public const LIENS_MAX = 200;
    public const DEBIT_MAX = 10;
    public const DEBIT_FENETRE_MS = 600000;
    public const CHARGE_MAX = 24576;

    /** Les tailles du texte chiffré : une des quatre tailles de rembourrage (1, 2, 4, 8 Kio) plus les 16 octets de l'étiquette GCM. */
    public const TAILLES_CHIFFRE = [1040, 2064, 4112, 8208];

    public static function refus(int $statut, string $code, string $motif, string $geste, array $entetes = []): never
    {
        throw new HttpResponseException(response()->json(['code' => $code, 'motif' => $motif, 'geste' => $geste], $statut, $entetes));
    }

    public static function maintenant(): int
    {
        return (int) (microtime(true) * 1000);
    }

    public static function empreinteJeton(string $jeton): string
    {
        return hash('sha256', $jeton);
    }

    private static function b64(string $v, int $octets): ?string
    {
        $o = base64_decode($v, true);

        return ($o !== false && strlen($o) === $octets) ? $o : null;
    }

    /** La mère publie sa clé PUBLIQUE et l'ensemble de ses liens anonymes. @return array{liens: int, cle: string} */
    public static function publier(array $in): array
    {
        $cle = (string) ($in['cle'] ?? '');
        if (self::b64($cle, 32) === null) {
            self::refus(422, 'cle_invalide', 'la clé publique doit être une clé X25519 de 32 octets en base64', 'Republier depuis le poste mère');
        }
        $liens = $in['liens'] ?? [];
        if (! is_array($liens)) {
            self::refus(422, 'liens_invalides', 'liste de liens attendue', 'Republier depuis le poste mère');
        }
        if (count($liens) > self::LIENS_MAX) {
            self::refus(422, 'liens_trop_nombreux', 'au plus '.self::LIENS_MAX.' liens de collecte', 'Révoquer ou archiver des liens au poste mère');
        }
        $lignes = [];
        foreach ($liens as $l) {
            $e = (string) ($l['empreinte'] ?? '');
            $charge = $l['charge'] ?? null;
            if (! preg_match('/^[0-9a-f]{64}$/', $e) || ! is_array($charge)) {
                self::refus(422, 'lien_invalide', 'chaque lien porte une empreinte SHA-256 et son questionnaire', 'Republier depuis le poste mère');
            }
            $json = json_encode($charge, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            if (strlen($json) > self::CHARGE_MAX) {
                self::refus(422, 'questionnaire_trop_grand', 'le questionnaire d\'un lien dépasse '.self::CHARGE_MAX.' octets', 'Réduire le questionnaire');
            }
            $lignes[$e] = ['empreinte' => $e, 'charge' => $json, 'expire' => isset($l['expire']) ? (int) $l['expire'] : null, 'revoque' => isset($l['revoque']) ? (int) $l['revoque'] : null, 'maj' => self::maintenant()];
        }
        DB::transaction(function () use ($cle, $lignes) {
            DB::table('relais_sat_cle')->updateOrInsert(['id' => 1], ['cle' => $cle, 'cle_id' => substr(hash('sha256', (string) base64_decode($cle)), 0, 16), 'publiee' => self::maintenant()]);
            DB::table('relais_sat_liens')->delete();
            foreach ($lignes as $l) {
                DB::table('relais_sat_liens')->insert($l);
            }
        });

        return ['liens' => count($lignes), 'cle' => substr(hash('sha256', (string) base64_decode($cle)), 0, 16)];
    }

    /** Le lien OUVERT d'un jeton (inconnu, expiré, révoqué : `null`, une seule réponse). */
    public static function lienOuvert(string $jeton): ?object
    {
        if (! preg_match('/^[a-z0-9]{8,64}$/', $jeton)) {
            return null;
        }
        $l = DB::table('relais_sat_liens')->where('empreinte', self::empreinteJeton($jeton))->first();
        if ($l === null || $l->revoque !== null || ($l->expire !== null && (int) $l->expire < self::maintenant())) {
            return null;
        }

        return DB::table('relais_sat_cle')->where('id', 1)->exists() ? $l : null;
    }

    public static function cle(): ?string
    {
        $c = DB::table('relais_sat_cle')->where('id', 1)->value('cle');

        return $c === null ? null : (string) $c;
    }

    private static function empreinteAdresse(string $adresse): string
    {
        return hash_hmac('sha256', $adresse, (string) config('app.key'));
    }

    /** Dépose une enveloppe. @return array{ok: bool, rejeu?: bool} */
    public static function deposer(string $jeton, string $corps, string $adresse): array
    {
        if (strlen($corps) > self::ENVELOPPE_MAX) {
            self::refus(413, 'enveloppe_trop_grande', 'enveloppe de plus de 16 Kio', 'Réduire le texte libre');
        }
        $lien = self::lienOuvert($jeton);
        if ($lien === null) {
            self::refus(404, 'lien_indisponible', '', '');
        }
        // Le champ PIÈGE : un champ caché que seul un robot remplit. Réponse identique à un succès, rien n'est stocké, rien n'est compté.
        $apercu = json_decode($corps, true);
        if (is_array($apercu) && isset($apercu['piege']) && $apercu['piege'] !== '') {
            return ['ok' => true];
        }
        // Le débit : 10 réponses par empreinte d'adresse par 10 minutes ; l'empreinte est effacée avec la fenêtre.
        $maintenant = self::maintenant();
        DB::table('relais_sat_debit')->where('t', '<', $maintenant - self::DEBIT_FENETRE_MS)->delete();
        $emp = self::empreinteAdresse($adresse);
        if (DB::table('relais_sat_debit')->where('empreinte', $emp)->count() >= self::DEBIT_MAX) {
            self::refus(429, 'debit_depasse', 'trop de réponses depuis cette connexion', 'Réessayer dans quelques minutes', ['Retry-After' => '600']);
        }
        DB::table('relais_sat_debit')->insert(['empreinte' => $emp, 't' => $maintenant]);

        $e = json_decode($corps, true);
        if (! is_array($e) || ($e['v'] ?? null) !== 1 || ! isset($e['id'], $e['epk'], $e['iv'], $e['ct'])
            || ! is_string($e['id']) || ! preg_match('/^[0-9a-f]{32}$/', $e['id'])
            || ! is_string($e['epk']) || ! is_string($e['iv']) || ! is_string($e['ct'])) {
            self::refus(422, 'enveloppe_invalide', 'forme d\'enveloppe inconnue', 'Recharger la page');
        }
        $epk = self::b64($e['epk'], 32);
        $iv = self::b64($e['iv'], 12);
        $ct = base64_decode($e['ct'], true);
        if ($epk === null || $iv === null || $ct === false || ! in_array(strlen($ct), self::TAILLES_CHIFFRE, true)) {
            self::refus(422, 'enveloppe_invalide', 'clé éphémère, vecteur ou taille du texte chiffré hors format', 'Recharger la page');
        }
        // Le bloc stocké est RECONSTRUIT des seuls champs validés : rien d'autre que du chiffré et des nombres.
        $bloc = json_encode(['v' => 1, 'epk' => $e['epk'], 'iv' => $e['iv'], 'ct' => $e['ct']]);
        $deja = DB::table('relais_sat_reponses')->where('id', $e['id'])->exists();
        if (! $deja) {
            DB::table('relais_sat_reponses')->insert(['id' => $e['id'], 'lien' => $lien->empreinte, 'bloc' => $bloc, 'taille' => strlen($bloc), 'recu' => $maintenant]);
        }

        return $deja ? ['ok' => true, 'rejeu' => true] : ['ok' => true];
    }

    /** Le relevé de la mère : les enveloppes après un curseur. */
    public static function releve(int $apres, int $limite): array
    {
        $limite = max(1, min(200, $limite));
        $lignes = DB::table('relais_sat_reponses')->where('seq', '>', $apres)->orderBy('seq')->limit($limite)->get();
        $reponses = [];
        foreach ($lignes as $l) {
            $reponses[] = ['seq' => (int) $l->seq, 'id' => $l->id, 'lien' => $l->lien, 'recu' => (int) $l->recu, 'bloc' => json_decode($l->bloc, true)];
        }
        $reste = DB::table('relais_sat_reponses')->where('seq', '>', $reponses === [] ? $apres : end($reponses)['seq'])->count();

        return ['reponses' => $reponses, 'reste' => $reste, 'cle' => DB::table('relais_sat_cle')->where('id', 1)->value('cle_id')];
    }

    /** MESURE d'opacité : entropie moyenne (bits par octet) des textes chiffrés, nombre d'enveloppes qui laissent lire une suite de 16 caractères imprimables ou une clé d'identité. */
    public static function mesurerOpacite(int $max = 200): array
    {
        $entropies = [];
        $lisibles = 0;
        foreach (DB::table('relais_sat_reponses')->orderByDesc('seq')->limit($max)->pluck('bloc') as $bloc) {
            $b = json_decode((string) $bloc, true);
            $ct = base64_decode((string) ($b['ct'] ?? ''), true) ?: '';
            if ($ct === '') {
                continue;
            }
            $f = count_chars($ct, 1);
            $h = 0.0;
            foreach ($f as $n) {
                $p = $n / strlen($ct);
                $h -= $p * log($p, 2);
            }
            $entropies[] = $h;
            if (preg_match('/[\x20-\x7e]{16,}/', $ct) || preg_match('/(nom|prenom|telephone|email|dossier|patient)\w*"\s*:/i', $ct)) {
                $lisibles++;
            }
        }

        return ['echantillon' => count($entropies), 'entropie' => $entropies === [] ? null : array_sum($entropies) / count($entropies), 'lisibles' => $lisibles];
    }
}
