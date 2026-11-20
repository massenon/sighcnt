<?php

namespace App\Http\Controllers;

use App\Relais\Sauvegarde\Entrepot;
use App\Relais\Sauvegarde\Reglages;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;

/**
 * LA SAUVEGARDE HORS SITE (lot 5, ADR-0007) : famille de routes `/sauvegarde/*`, RÉSERVÉE À LA MÈRE (en-tête `x-mere`). Un appareil appairé (téléphone, fileul) est refusé en le nommant
 * (403 `sauvegarde_reservee_mere`) AVANT toute lecture de la requête ; sans identité : 403 `mere_requise`. Contrat : `packages/sync/banc/relais-sauvegarde.js`.
 * Ce contrôleur n'importe AUCUNE fonction de chiffrement et ne détient aucune clé : des blocs opaques, leurs identifiants, tailles, dates.
 */
class SauvegardeController extends Controller
{
    private function exigerMere(Request $r): void
    {
        $secret = (string) config('relais.secret_mere');
        if ($secret !== '' && hash_equals($secret, (string) $r->header('x-mere'))) {
            return;
        }
        if (preg_match('/^Bearer /', (string) $r->header('Authorization'))) {
            Entrepot::refus(403, 'sauvegarde_reservee_mere', 'les copies de sauvegarde ne sont accessibles qu\'à le poste mère', 'Aucun appareil appairé n\'y accède : utiliser le poste mère.');
        }
        Entrepot::refus(403, 'mere_requise', '', '');
    }

    public function etat(Request $r): JsonResponse
    {
        $this->exigerMere($r);

        return response()->json(Entrepot::etat());
    }

    public function manquants(Request $r): JsonResponse
    {
        $this->exigerMere($r);

        return response()->json(['manquants' => Entrepot::manquants((array) $r->input('ids', []))]);
    }

    public function deposerBloc(Request $r, string $id): JsonResponse
    {
        $this->exigerMere($r);

        return response()->json(Entrepot::deposerBloc($id, $r->getContent()));
    }

    public function lireBloc(Request $r, string $id): Response
    {
        $this->exigerMere($r);

        return response(Entrepot::lireBloc($id), 200, ['Content-Type' => 'application/octet-stream']);
    }

    public function ouvrir(Request $r): JsonResponse
    {
        $this->exigerMere($r);

        return response()->json(Entrepot::ouvrir((string) $r->input('id'), (string) $r->input('type'), (int) $r->input('date'), $r->input('garder')));
    }

    public function attacher(Request $r, string $id): JsonResponse
    {
        $this->exigerMere($r);

        return response()->json(Entrepot::attacher($id, (array) $r->input('ids', [])));
    }

    public function valider(Request $r, string $id): JsonResponse
    {
        $this->exigerMere($r);

        return response()->json(Entrepot::valider($id, (array) $r->input('racine', [])));
    }

    public function copies(Request $r): JsonResponse
    {
        $this->exigerMere($r);

        return response()->json(['copies' => Entrepot::copies($r->query('type') ? (string) $r->query('type') : null)]);
    }

    public function copie(Request $r, string $id): JsonResponse
    {
        $this->exigerMere($r);

        return response()->json(Entrepot::lireCopie($id));
    }

    // --- crochets du banc (config relais.banc) : jamais en production ----------------------------------------------
    private function exigerBanc(): void
    {
        if (! config('relais.banc')) {
            Entrepot::refus(404, 'route_inconnue', '', '');
        }
    }

    public function bancReglage(Request $r): JsonResponse
    {
        $this->exigerBanc();
        $noms = ['tailleBlocMax' => 'taille_bloc_max', 'tailleMaxCopie' => 'taille_max_copie', 'quotaOctets' => 'quota_octets', 'rotationPlancher' => 'rotation_plancher', 'rotationPlafond' => 'rotation_plafond', 'orphelinsHeures' => 'orphelins_heures'];
        $nom = $noms[(string) $r->input('cle')] ?? null;
        if ($nom === null) {
            Entrepot::refus(422, 'reglage_inconnu', '', '');
        }
        DB::table('relais_meta')->updateOrInsert(['k' => Reglages::cle($nom)], ['v' => (string) (int) $r->input('valeur')]);

        return response()->json(['ok' => true]);
    }

    public function bancAlterer(Request $r): JsonResponse
    {
        $this->exigerBanc();
        $chemin = Entrepot::chemin((string) $r->input('id'));
        $octets = (string) file_get_contents($chemin);
        $octets[strlen($octets) - 1] = chr(ord($octets[strlen($octets) - 1]) ^ 1);
        file_put_contents($chemin, $octets);

        return response()->json(['ok' => true]);
    }

    public function bancVieillir(Request $r): JsonResponse
    {
        $this->exigerBanc();
        $ms = (int) ((float) $r->input('heures') * 3600 * 1000);
        DB::table('relais_sauv_copies')->update(['date' => DB::raw('date - '.$ms), 'recu' => DB::raw('recu - '.$ms)]);
        DB::table('relais_sauv_blocs')->update(['recu' => DB::raw('recu - '.$ms)]);

        return response()->json(['ok' => true]);
    }

    public function bancTout(): JsonResponse
    {
        $this->exigerBanc();

        return response()->json(['blocs' => DB::table('relais_sauv_blocs')->get(), 'copies' => DB::table('relais_sauv_copies')->get(), 'liens' => (int) DB::table('relais_sauv_liens')->count()]);
    }
}
