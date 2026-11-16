<?php

namespace App\Http\Controllers;

use App\Relais\Sms\Messages;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * LA PASSERELLE SMS (lot SMS-R, ADR-0008) : famille de routes `/sms/*`, RÉSERVÉE À LA MÈRE (en-tête `x-mere`). Un appareil appairé (téléphone, fileul) est refusé en le nommant
 * (403 `sms_reserve_mere`) AVANT toute lecture de la requête ; sans identité : 403 `mere_requise`. Aucune route ne rend un identifiant du fournisseur, un numéro en clair ou un texte.
 */
class SmsController extends Controller
{
    private function exigerMere(Request $r): void
    {
        $secret = (string) config('relais.secret_mere');
        if ($secret !== '' && hash_equals($secret, (string) $r->header('x-mere'))) {
            return;
        }
        if (preg_match('/^Bearer /', (string) $r->header('Authorization'))) {
            Messages::refus(403, 'sms_reserve_mere', 'la passerelle SMS n’est accessible qu’au poste mère', 'Aucun appareil appairé n’y accède : utiliser le poste mère.');
        }
        Messages::refus(403, 'mere_requise', '', '');
    }

    public function etat(Request $r): JsonResponse
    {
        $this->exigerMere($r);

        return response()->json(Messages::etat());
    }

    public function deposer(Request $r): JsonResponse
    {
        $this->exigerMere($r);

        return response()->json(['messages' => Messages::deposer((array) $r->input('messages', []))]);
    }

    public function annuler(Request $r): JsonResponse
    {
        $this->exigerMere($r);

        return response()->json(['messages' => Messages::annuler((array) $r->input('ids', []))]);
    }

    public function tester(Request $r): JsonResponse
    {
        $this->exigerMere($r);

        return response()->json(Messages::tester((string) $r->input('numero')));
    }

    public function journal(Request $r): JsonResponse
    {
        $this->exigerMere($r);

        return response()->json(['messages' => Messages::journal((int) $r->query('limite', 200), $r->query('depuis') !== null ? (int) $r->query('depuis') : null)]);
    }
}
