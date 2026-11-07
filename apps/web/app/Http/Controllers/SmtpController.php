<?php

namespace App\Http\Controllers;

use App\Relais\EnvoiEchoue;
use App\Relais\ReglagesSmtp;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * RÉGLAGE DE LA MESSAGERIE SMTP DU RELAIS, réservé au superadmin connecté (groupe `auth` du panneau). Le mot de passe se SAISIT et s'enregistre chiffré : il ne
 * revient jamais (la réponse dit seulement « défini »). Le message de test envoie VRAIMENT par SMTP et nomme l'étape en échec.
 */
class SmtpController extends Controller
{
    private function audit(string $action, string $detail): void
    {
        DB::table('relais_audit')->insert(['quand' => (int) (microtime(true) * 1000), 'acteur' => 'superadmin', 'action' => $action, 'detail' => $detail]);
    }

    private function refus(int $statut, string $code, string $motif, array $plus = []): JsonResponse
    {
        return response()->json(['code' => $code, 'motif' => $motif] + $plus, $statut);
    }

    public function reglage(): JsonResponse
    {
        return response()->json(ReglagesSmtp::lire() + ['configure' => ReglagesSmtp::configure()]);
    }

    public function enregistrer(Request $r): JsonResponse
    {
        $v = $r->validate([
            'hote' => ['required', 'string', 'max:255', 'regex:/^[A-Za-z0-9.\-]+$/'],
            'port' => ['required', 'integer', 'between:1,65535'],
            'chiffrement' => ['required', Rule::in(ReglagesSmtp::CHIFFREMENTS)],
            'utilisateur' => ['nullable', 'string', 'max:255'],
            'mdp' => ['nullable', 'string', 'max:500'],
            'effacer_mdp' => ['nullable', 'boolean'],
            'expediteur' => ['required', 'email'],
            'expediteur_nom' => ['nullable', 'string', 'max:120'],
            'repondre' => ['nullable', 'email'],
            'repondre_nom' => ['nullable', 'string', 'max:120'],
            'verifier_certificat' => ['nullable', 'boolean'],
        ]);
        ReglagesSmtp::enregistrer($v, $v['mdp'] ?? null, (bool) ($v['effacer_mdp'] ?? false));
        // Le journal dit CE QUI a changé, jamais le mot de passe ni même sa longueur.
        $this->audit('smtp_enregistre', $v['hote'].':'.$v['port'].' '.$v['chiffrement'].(($v['mdp'] ?? '') !== '' ? ' (mot de passe remplacé)' : ''));

        return response()->json(ReglagesSmtp::lire() + ['configure' => ReglagesSmtp::configure()]);
    }

    public function tester(Request $r): JsonResponse
    {
        $v = $r->validate(['destinataire' => ['required', 'email']]);
        if (! ReglagesSmtp::configure()) {
            return $this->refus(409, 'smtp_non_configure', 'Enregistrer d\'abord le serveur SMTP et l\'adresse d\'expéditeur.');
        }
        try {
            ReglagesSmtp::envoyerTest($v['destinataire']);
        } catch (EnvoiEchoue $e) {
            $this->audit('smtp_test_echec', $e->etape.' vers '.RecuperationController::masquer($v['destinataire']));

            return $this->refus(502, 'smtp_echec', ReglagesSmtp::ETAPES[$e->etape], ['etape' => $e->etape, 'detail' => $e->motif]);
        }
        $this->audit('smtp_test_ok', RecuperationController::masquer($v['destinataire']));

        return response()->json(['envoye' => true]);
    }
}
