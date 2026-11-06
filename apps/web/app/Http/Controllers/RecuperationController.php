<?php

namespace App\Http\Controllers;

use App\Mail\CoffreCleMail;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\RateLimiter;

/**
 * ENVOI DU COFFRE DE LA CLÉ PAR COURRIEL, à la demande d'un POSTE appairé (jeton d'appareil). Le relais reste opaque : il reçoit un COFFRE (la clé chiffrée sur
 * le poste par une phrase secrète : PBKDF2-SHA256, AES-GCM), jamais la clé nue ni la phrase, et refuse tout ce qui n'a pas cette forme. L'envoi n'a lieu que si le
 * réglage « récupération par courriel » est ACTIVÉ côté relais (désactivé par défaut), au plus trois fois par heure et par appareil. Le journal d'audit ne garde
 * ni le coffre ni l'adresse en clair (adresse masquée).
 */
class RecuperationController extends Controller
{
    public const PAR_HEURE = 3;

    private function refus(int $statut, string $code, string $motif = ''): JsonResponse
    {
        return response()->json(['code' => $code, 'motif' => $motif], $statut);
    }

    private function appareil(Request $r): ?object
    {
        if (! preg_match('/^Bearer ([^.]+)\.(.+)$/', (string) $r->header('Authorization'), $m)) {
            return null;
        }
        $a = DB::table('relais_appareils')->where('uuid', $m[1])->first();
        if (! $a || ! hash_equals($a->jeton_hash, hash('sha256', $m[2])) || $a->etat === 'revoque') {
            return null;
        }

        return $a;
    }

    /** « a***@domaine » : assez pour reconnaître l'adresse au journal, trop peu pour la réutiliser. */
    public static function masquer(string $courriel): string
    {
        [$local, $domaine] = array_pad(explode('@', $courriel, 2), 2, '');

        return mb_substr($local, 0, 1).'***@'.$domaine;
    }

    public function envoyer(Request $r): JsonResponse
    {
        $a = $this->appareil($r);
        if (! $a) {
            return $this->refus(401, 'jeton_invalide', 'Appareil non reconnu.');
        }
        if (DB::table('relais_meta')->where('k', 'cle_recup_actif')->value('v') !== '1') {
            return $this->refus(409, 'recuperation_desactivee', 'La récupération de la clé par courriel est désactivée sur ce relais.');
        }
        // La clé nue et la phrase secrète ne doivent JAMAIS arriver ici, même jointes à un coffre valide : une demande qui les porte est refusée en le disant.
        if ($r->has('phrase') || $r->has('cle')) {
            return $this->refus(422, 'secret_en_clair', 'La clé et la phrase secrète ne doivent jamais être envoyées au relais : seul le coffre l\'est.');
        }
        $courriel = mb_strtolower(trim((string) $r->input('courriel')));
        if (! filter_var($courriel, FILTER_VALIDATE_EMAIL)) {
            return $this->refus(422, 'courriel_invalide', 'Un courriel valide est nécessaire.');
        }
        if (! ConsultationController::coffreValide($r->input('coffre'))) {
            return $this->refus(422, 'coffre_invalide', 'Seul un coffre (la clé chiffrée par une phrase secrète d\'au moins 12 caractères) est accepté, jamais la clé elle-même.');
        }
        $cle = 'coffre:'.$a->uuid;
        if (RateLimiter::tooManyAttempts($cle, self::PAR_HEURE)) {
            return $this->refus(429, 'trop_de_demandes', 'Trois envois par heure au plus : réessayer dans '.RateLimiter::availableIn($cle).' s.');
        }
        RateLimiter::hit($cle, 3600);
        Mail::to($courriel)->queue(new CoffreCleMail($r->input('coffre')));
        DB::table('relais_audit')->insert(['quand' => (int) (microtime(true) * 1000), 'acteur' => $a->uuid, 'action' => 'cle_coffre_envoye_par_poste', 'detail' => self::masquer($courriel)]);

        return response()->json(['envoye' => true]);
    }
}
