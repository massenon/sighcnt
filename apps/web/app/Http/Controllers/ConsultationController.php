<?php

namespace App\Http\Controllers;

use App\Mail\CoffreCleMail;
use App\Relais\EnvoiEchoue;
use App\Relais\ReglagesSmtp;
use App\Relais\VolumeCopie;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * CONSULTATION DES COPIES (PRD relais consultable, option B). Le relais sert des enveloppes chiffrées au superadmin connecté ; le déchiffrement se fait dans
 * son navigateur (public/js/consultation.js) avec la clé qu'il y saisit. Ce contrôleur n'importe AUCUN chiffrement et ne reçoit JAMAIS la clé de clinique ni
 * la phrase secrète : pour la récupération par courriel il ne conserve que le COFFRE (clé chiffrée dans le navigateur par une phrase).
 */
class ConsultationController extends Controller
{
    private const CLES = ['cle_recup_actif', 'cle_recup_courriel', 'cle_recup_coffre'];

    private function refus(int $statut, string $code, string $motif = ''): JsonResponse
    {
        return response()->json(['code' => $code, 'motif' => $motif], $statut);
    }

    private function meta(string $k): ?string
    {
        return DB::table('relais_meta')->where('k', $k)->value('v');
    }

    private function poser(string $k, ?string $v): void
    {
        DB::table('relais_meta')->updateOrInsert(['k' => $k], ['v' => $v]);
    }

    private function audit(string $action, string $detail = ''): void
    {
        DB::table('relais_audit')->insert(['quand' => (int) (microtime(true) * 1000), 'acteur' => 'superadmin', 'action' => $action, 'detail' => $detail]);
    }

    /** Les appareils qui ont déposé une copie, avec le volume mesuré (Q4). */
    public function appareils(): JsonResponse
    {
        $rows = DB::table('relais_enveloppes')->where('dir', 'copie')->selectRaw('appareil as uuid, MAX(n) as max_n')->groupBy('appareil')->orderBy('appareil')->get();

        return response()->json(['appareils' => $rows, 'volume' => VolumeCopie::mesurer()]);
    }

    /** Les enveloppes d'un appareil, par rangs : ce que le navigateur déchiffrera. */
    public function enveloppes(Request $r): JsonResponse
    {
        $appareil = (string) $r->query('appareil');
        if ($appareil === '') {
            return $this->refus(422, 'appareil_requis');
        }
        $limite = min(max((int) $r->query('limite', 100), 1), 200);
        $rows = DB::table('relais_enveloppes')->where('dir', 'copie')->where('appareil', $appareil)->where('n', '>', (int) $r->query('depuis_n', 0))
            ->orderBy('n')->limit($limite)->get(['id', 'appareil', 'dir', 'n', 'nonce', 'ct']);
        $this->audit('copie_lue', $appareil.' : '.$rows->count().' enveloppe(s)');

        return response()->json(['env' => $rows, 'fin' => $rows->count() < $limite]);
    }

    public function reglage(): JsonResponse
    {
        return response()->json([
            'actif' => $this->meta('cle_recup_actif') === '1',
            'courriel' => $this->meta('cle_recup_courriel'),
            'coffre' => $this->meta('cle_recup_coffre') !== null,
        ]);
    }

    /** Un coffre est un objet {v, kdf, iter, sel, nonce, ct} : toute autre forme, une clé nue en particulier, est refusée. */
    public static function coffreValide(mixed $c): bool
    {
        if (! is_array($c) || ($c['v'] ?? null) !== 1 || ($c['kdf'] ?? null) !== 'PBKDF2-SHA256' || ! is_int($c['iter'] ?? null) || $c['iter'] < 200000) {
            return false;
        }
        foreach (['sel', 'nonce', 'ct'] as $champ) {
            $b = isset($c[$champ]) && is_string($c[$champ]) ? base64_decode($c[$champ], true) : false;
            if ($b === false || $b === '') {
                return false;
            }
        }

        // 32 octets de clé + 16 d'étiquette GCM : un texte chiffré plus court n'est pas une clé chiffrée.
        return strlen((string) base64_decode($c['ct'], true)) === 48 && strlen((string) base64_decode($c['nonce'], true)) === 12 && strlen((string) base64_decode($c['sel'], true)) >= 16;
    }

    public function enregistrerReglage(Request $r): JsonResponse
    {
        $actif = $r->boolean('actif');
        if (! $actif) {
            // Désactiver EFFACE le coffre et le courriel : rien ne reste qui permette une récupération.
            foreach (self::CLES as $k) {
                DB::table('relais_meta')->where('k', $k)->delete();
            }
            $this->audit('cle_recuperation_desactivee');

            return response()->json(['actif' => false]);
        }
        $courriel = mb_strtolower(trim((string) $r->input('courriel')));
        if (! filter_var($courriel, FILTER_VALIDATE_EMAIL)) {
            return $this->refus(422, 'courriel_invalide', 'Un courriel valide est nécessaire pour activer la récupération.');
        }
        if (! self::coffreValide($r->input('coffre'))) {
            return $this->refus(422, 'coffre_invalide', 'Le coffre doit être la clé chiffrée par une phrase secrète dans le navigateur, jamais la clé elle-même.');
        }
        $this->poser('cle_recup_actif', '1');
        $this->poser('cle_recup_courriel', $courriel);
        $this->poser('cle_recup_coffre', json_encode($r->input('coffre'), JSON_UNESCAPED_SLASHES));
        $this->audit('cle_recuperation_activee', $courriel);

        return response()->json(['actif' => true]);
    }

    /** Envoie le COFFRE (jamais la clé, jamais la phrase) à l'adresse enregistrée ; sans la phrase secrète il ne sert à rien. */
    public function envoyerCoffre(): JsonResponse
    {
        if ($this->meta('cle_recup_actif') !== '1') {
            return $this->refus(409, 'recuperation_desactivee', 'La récupération de la clé par courriel est désactivée.');
        }
        if (! ReglagesSmtp::configure()) {
            return $this->refus(409, 'smtp_non_configure', 'Aucun serveur SMTP n\'est réglé : renseigner la messagerie SMTP des paramètres du relais.');
        }
        $courriel = (string) $this->meta('cle_recup_courriel');
        $coffre = json_decode((string) $this->meta('cle_recup_coffre'), true);
        try {
            ReglagesSmtp::envoyer($courriel, new CoffreCleMail(is_array($coffre) ? $coffre : []));
        } catch (EnvoiEchoue $e) {
            $this->audit('cle_coffre_envoi_echoue', $e->etape);

            return response()->json(['code' => 'envoi_echoue', 'motif' => ReglagesSmtp::ETAPES[$e->etape], 'etape' => $e->etape], 502);
        }
        $this->audit('cle_coffre_envoye', $courriel);

        return response()->json(['envoye' => true]);
    }
}
