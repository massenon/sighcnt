<?php

namespace App\Http\Controllers;

use App\Relais\Satisfaction\Entrepot;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;

/**
 * LA SATISFACTION EN LIGNE (lot SAT, ADR-0009). Deux surfaces :
 *  - PUBLIQUE, sans cookie ni session : `GET /s/{jeton}` (le formulaire) et `POST /s/{jeton}` (le dépôt d'une enveloppe scellée dans le navigateur). Un jeton inconnu, expiré ou révoqué : une seule réponse, générique.
 *  - RÉSERVÉE À LA MÈRE (en-tête `x-mere`) : `POST /satisfaction/publier` (clé publique et liens) et `GET /satisfaction/releve`. Un appareil appairé : 403 nommé `satisfaction_reservee_mere`.
 * Ce contrôleur ne détient aucune clé privée et ne lit aucune réponse.
 */
class SatisfactionController extends Controller
{
    private function exigerMere(Request $r): void
    {
        $secret = (string) config('relais.secret_mere');
        if ($secret !== '' && hash_equals($secret, (string) $r->header('x-mere'))) {
            return;
        }
        if (preg_match('/^Bearer /', (string) $r->header('Authorization'))) {
            Entrepot::refus(403, 'satisfaction_reservee_mere', 'la satisfaction en ligne ne se publie et ne se relève qu\'au poste mère', 'Aucun appareil appairé n\'y accède : utiliser le poste mère.');
        }
        Entrepot::refus(403, 'mere_requise', '', '');
    }

    private function sansTrace(Response $rep): Response
    {
        return $rep->header('Cache-Control', 'no-store')->header('Referrer-Policy', 'no-referrer')->header('X-Robots-Tag', 'noindex, nofollow')
            ->header('Content-Security-Policy', "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'none'");
    }

    public function formulaire(Request $r, string $jeton): Response
    {
        $lien = Entrepot::lienOuvert($jeton);
        if ($lien === null) {
            return $this->sansTrace(response()->view('satisfaction.indisponible', [], 404));
        }

        return $this->sansTrace(response()->view('satisfaction.formulaire', ['charge' => json_decode($lien->charge, true), 'cle' => Entrepot::cle()]));
    }

    public function deposer(Request $r, string $jeton): JsonResponse
    {
        return response()->json(Entrepot::deposer($jeton, $r->getContent(), (string) $r->ip()), 200, ['Cache-Control' => 'no-store']);
    }

    public function publier(Request $r): JsonResponse
    {
        $this->exigerMere($r);

        return response()->json(Entrepot::publier((array) $r->json()->all()));
    }

    public function releve(Request $r): JsonResponse
    {
        $this->exigerMere($r);

        return response()->json(Entrepot::releve((int) $r->query('apres', 0), (int) $r->query('limite', 100)));
    }
}
