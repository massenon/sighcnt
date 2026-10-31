<?php

namespace App\Http\Controllers;

use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * LE RELAIS EN LIGNE — opaque (ADR-0005, spec §12-13).
 *
 * Contrat : packages/sync/banc/relais.js (implémentation de référence, éprouvée par le banc).
 * Ce contrôleur n'importe AUCUNE fonction de chiffrement et ne détient aucune clé : il stocke des enveloppes
 * dont il ne voit que l'appareil, le sens, le rang et la taille. Il ne contacte JAMAIS la mère : c'est elle
 * qui vient le relever (cPanel mutualisé : ni WebSocket, ni démon).
 */
class RelaisController extends Controller
{
    // --- erreurs nommées --------------------------------------------------------------
    private function refus(int $statut, string $code, string $motif = ''): never
    {
        throw new HttpResponseException(response()->json(['code' => $code, 'motif' => $motif], $statut));
    }

    private function estMere(Request $r): bool
    {
        $secret = (string) config('relais.secret_mere');

        return $secret !== '' && hash_equals($secret, (string) $r->header('x-mere'));
    }

    private function exigerMere(Request $r): void
    {
        if (! $this->estMere($r)) {
            $this->refus(403, 'mere_requise');
        }
    }

    private function appareil(Request $r): object
    {
        if (! preg_match('/^Bearer ([^.]+)\.(.+)$/', (string) $r->header('Authorization'), $m)) {
            $this->refus(401, 'jeton_invalide', 'Jeton absent.');
        }
        $a = DB::table('relais_appareils')->where('uuid', $m[1])->first();
        if (! $a || ! hash_equals($a->jeton_hash, hash('sha256', $m[2]))) {
            $this->refus(401, 'jeton_invalide', 'Jeton invalide.');
        }
        if ($a->etat === 'revoque') {
            $this->refus(401, 'appareil_revoque', 'Appareil révoqué.');
        }

        return $a;
    }

    private function meta(string $k): ?string
    {
        return DB::table('relais_meta')->where('k', $k)->value('v');
    }

    private function poserMeta(string $k, string $v): void
    {
        DB::table('relais_meta')->updateOrInsert(['k' => $k], ['v' => $v]);
    }

    private function lister(string $dir, string $appareil, int $depuisN, int $limite): array
    {
        $rows = DB::table('relais_enveloppes')
            ->where('dir', $dir)->where('appareil', $appareil)->where('n', '>', $depuisN)
            ->orderBy('n')->limit($limite)
            ->get(['rid', 'id', 'appareil', 'dir', 'n', 'nonce', 'ct']);

        return ['env' => $rows, 'fin' => $rows->count() < $limite];
    }

    // --- la mère déclare un code d'appairage (par son hachage) ------------------------------
    public function code(Request $r): JsonResponse
    {
        $this->exigerMere($r);
        DB::table('relais_codes')->insertOrIgnore(['hash' => (string) $r->input('hash'), 'utilise' => false]);

        return response()->json(['ok' => true]);
    }

    // --- un appareil s'appaire : code à usage unique -> jeton --------------------------------
    public function appairage(Request $r): JsonResponse
    {
        $hash = hash('sha256', (string) $r->input('code'));
        $c = DB::table('relais_codes')->where('hash', $hash)->first();
        if (! $c) {
            $this->refus(403, 'code_invalide', 'Code inconnu.');
        }
        if ($c->utilise) {
            $this->refus(403, 'code_utilise', 'Code déjà utilisé.');
        }
        $uuid = (string) $r->input('uuid');
        if ($uuid === '' || DB::table('relais_appareils')->where('uuid', $uuid)->exists()) {
            $this->refus(422, 'uuid_invalide', 'Identifiant d\'appareil absent ou déjà connu.');
        }
        $secret = bin2hex(random_bytes(24));
        DB::transaction(function () use ($hash, $uuid, $secret) {
            DB::table('relais_codes')->where('hash', $hash)->update(['utilise' => true]);
            DB::table('relais_appareils')->insert(['uuid' => $uuid, 'jeton_hash' => hash('sha256', $secret), 'etat' => 'actif']);
        });

        return response()->json(['jeton' => $uuid.'.'.$secret]);
    }

    // --- dépôt d'une enveloppe : idempotent par id, rang unique par (appareil, sens) -------------------
    public function depot(Request $r): JsonResponse
    {
        $e = (array) $r->input('enveloppe');
        /* L'AUTORISATION AVANT LA VALIDATION : on ne dit rien de la forme d'une enveloppe à qui n'a pas le droit
           de la déposer (le même refus, quel que soit le contenu). */
        $dir = is_string($e['dir'] ?? null) ? $e['dir'] : '';
        $appareilCible = is_string($e['appareil'] ?? null) ? $e['appareil'] : '';
        if ($this->estMere($r)) {
            if (! in_array($dir, ['vers_mobile', 'journal'], true)) {
                $this->refus(403, 'depot_interdit', 'Sens inconnu.');
            }
        } else {
            $a = $this->appareil($r);
            if ($dir !== 'vers_mere' || $appareilCible !== $a->uuid) {
                $this->refus(403, 'depot_interdit', 'Un appareil ne dépose que dans sa propre boîte vers la mère.');
            }
        }
        foreach (['id', 'appareil', 'dir', 'nonce', 'ct'] as $champ) {
            if (! isset($e[$champ]) || ! is_string($e[$champ])) {
                $this->refus(422, 'enveloppe_invalide', "Champ manquant : $champ");
            }
        }
        if (! isset($e['n']) || ! is_int($e['n']) || $e['n'] < 1) {
            $this->refus(422, 'enveloppe_invalide', 'Rang invalide.');
        }
        $deja = DB::table('relais_enveloppes')->where('id', $e['id'])->first(['rid']);
        if ($deja) {
            return response()->json(['rid' => $deja->rid, 'rejeu' => true]);
        }
        try {
            $rid = DB::table('relais_enveloppes')->insertGetId([
                'id' => $e['id'], 'appareil' => $e['appareil'], 'dir' => $e['dir'], 'n' => $e['n'],
                'nonce' => $e['nonce'], 'ct' => $e['ct'], 'taille' => strlen($e['ct']),
                'recu' => (int) (microtime(true) * 1000),
            ], 'rid');
        } catch (UniqueConstraintViolationException) {
            $this->refus(409, 'rang_deja_pris', 'Ce rang est déjà occupé par une autre enveloppe.');
        }

        return response()->json(['rid' => $rid]);
    }

    // --- relève : la mère lit tout (vers_mere, journal) ; un appareil ne lit que SA boîte ---------
    public function releve(Request $r): JsonResponse
    {
        $dir = (string) $r->query('dir');
        $app = (string) $r->query('appareil');
        $n = (int) $r->query('depuis_n', 0);
        $lim = min((int) $r->query('limite', 50) ?: 50, 100);
        if ($this->estMere($r)) {
            if (! in_array($dir, ['vers_mere', 'journal'], true)) {
                $this->refus(403, 'lecture_interdite');
            }

            return response()->json($this->lister($dir, $app, $n, $lim));
        }
        $a = $this->appareil($r);
        if ($dir !== 'vers_mobile' || $app !== $a->uuid) {
            $this->refus(403, 'lecture_interdite', 'Un appareil ne lit que SA boîte.');
        }

        return response()->json($this->lister($dir, $app, $n, $lim));
    }

    public function appareilsMere(Request $r): JsonResponse
    {
        $this->exigerMere($r);
        $rows = DB::table('relais_enveloppes')->where('dir', 'vers_mere')
            ->selectRaw('appareil as uuid, MAX(n) as max_n')->groupBy('appareil')->get();

        return response()->json(['appareils' => $rows]);
    }

    public function compteur(Request $r): JsonResponse
    {
        $a = $this->appareil($r);
        $max = DB::table('relais_enveloppes')->where('dir', 'vers_mobile')->where('appareil', $a->uuid)->max('n');

        return response()->json(['max_n' => (int) $max]);
    }

    public function revoquer(Request $r): JsonResponse
    {
        $this->exigerMere($r);
        DB::table('relais_appareils')->where('uuid', (string) $r->input('uuid'))->update(['etat' => 'revoque']);

        return response()->json(['ok' => true]);
    }

    /**
     * UNE SEULE MÈRE PAR CLINIQUE (30/10/2026). Le poste qui s'active en mode mère se déclare ici ; une seconde déclaration
     * est REFUSÉE en nommant la première. Une mère silencieuse depuis plus que le seuil de battement peut être remplacée
     * explicitement (reprise après sinistre) ; une mère vivante, jamais.
     */
    public function activerMere(Request $r): JsonResponse
    {
        $this->exigerMere($r);
        $uuid = trim((string) $r->input('uuid'));
        if ($uuid === '') {
            $this->refus(422, 'uuid_requis', 'Identifiant du poste requis.');
        }
        $etiquette = mb_substr(trim((string) $r->input('etiquette', 'Poste mère')), 0, 80);
        $remplacer = (bool) $r->input('remplacer', false);
        $actuelle = json_decode((string) $this->meta('mere_active'), true);
        $maintenant = (int) (microtime(true) * 1000);

        if (is_array($actuelle) && ($actuelle['uuid'] ?? null) !== $uuid) {
            $bt = $this->meta('battement');
            $age = $bt ? $maintenant - (int) $bt : null;
            $silencieuse = $age === null || $age > (int) config('relais.seuil_battement_ms');
            if (! $remplacer) {
                $this->refus(409, 'mere_deja_active', 'Une mère est déjà active : « '.($actuelle['etiquette'] ?? '?').' » depuis le '.date('d/m/Y H:i', (int) (($actuelle['depuis'] ?? 0) / 1000)).'. Il ne peut y avoir qu\'un seul poste mère par clinique.');
            }
            if (! $silencieuse) {
                $this->refus(409, 'mere_vivante', 'La mère « '.($actuelle['etiquette'] ?? '?').' » a battu il y a '.round($age / 1000).' s : elle ne peut pas être remplacée tant qu\'elle est vivante. Arrêtez-la d\'abord.');
            }
            DB::table('relais_audit')->insert(['quand' => $maintenant, 'acteur' => 'mere:'.$uuid, 'action' => 'mere_remplacee', 'detail' => ($actuelle['etiquette'] ?? '?').' → '.$etiquette]);
        } elseif (! is_array($actuelle)) {
            DB::table('relais_audit')->insert(['quand' => $maintenant, 'acteur' => 'mere:'.$uuid, 'action' => 'mere_activee', 'detail' => $etiquette]);
        }
        $this->poserMeta('mere_active', json_encode(['uuid' => $uuid, 'etiquette' => $etiquette, 'depuis' => $maintenant], JSON_UNESCAPED_UNICODE));

        return response()->json(['ok' => true]);
    }

    public function desactiverMere(Request $r): JsonResponse
    {
        $this->exigerMere($r);
        $actuelle = json_decode((string) $this->meta('mere_active'), true);
        if (is_array($actuelle) && ($actuelle['uuid'] ?? null) === (string) $r->input('uuid')) {
            DB::table('relais_meta')->where('k', 'mere_active')->delete();
            DB::table('relais_audit')->insert(['quand' => (int) (microtime(true) * 1000), 'acteur' => 'mere:'.$actuelle['uuid'], 'action' => 'mere_desactivee', 'detail' => $actuelle['etiquette'] ?? '']);
        }

        return response()->json(['ok' => true]);
    }

    public function battement(Request $r): JsonResponse
    {
        $this->exigerMere($r);
        $this->poserMeta('battement', (string) (int) (microtime(true) * 1000));

        return response()->json(['ok' => true]);
    }

    /** Agrégats SANS nom de patient : le seul contenu en clair que le relais accepte de la mère. */
    public function indicateurs(Request $r): JsonResponse
    {
        $this->exigerMere($r);
        $this->poserMeta('indicateurs', json_encode($r->input('indicateurs', []), JSON_UNESCAPED_UNICODE));

        return response()->json(['ok' => true]);
    }

    public function etat(Request $r): JsonResponse
    {
        $this->exigerMere($r);
        $bt = $this->meta('battement');
        $age = $bt === null ? null : (int) (microtime(true) * 1000) - (int) $bt;
        $ind = json_decode($this->meta('indicateurs') ?? '{}', true) ?: [];

        return response()->json([
            'age_battement_ms' => $age,
            'alerte_battement' => $age === null || $age > (int) config('relais.seuil_battement_ms'),
            'indicateurs' => (object) $ind,
            'nb_enveloppes' => DB::table('relais_enveloppes')->count(),
        ]);
    }

    // --- crochets du banc (config relais.banc) : jamais en production --------------------------------
    private function exigerBanc(): void
    {
        if (! config('relais.banc')) {
            $this->refus(404, 'route_inconnue');
        }
    }

    public function bancAlterer(Request $r): JsonResponse
    {
        $this->exigerBanc();
        $ct = DB::table('relais_enveloppes')->where('id', (string) $r->input('id'))->value('ct');
        $octets = base64_decode((string) $ct, true) ?: '';
        $octets[0] = chr(ord($octets[0]) ^ 1);
        DB::table('relais_enveloppes')->where('id', (string) $r->input('id'))->update(['ct' => base64_encode($octets)]);

        return response()->json(['ok' => true]);
    }

    public function bancRetirer(Request $r): JsonResponse
    {
        $this->exigerBanc();
        DB::table('relais_enveloppes')->where('id', (string) $r->input('id'))->delete();

        return response()->json(['ok' => true]);
    }

    public function bancTout(): JsonResponse
    {
        $this->exigerBanc();

        return response()->json([
            'lignes' => DB::table('relais_enveloppes')->get(),
            'codes' => DB::table('relais_codes')->get(),
            'appareils' => DB::table('relais_appareils')->get(['uuid']),
            'meta' => DB::table('relais_meta')->get()->map(fn ($m) => ['k' => $m->k, 'v' => $m->v]),
        ]);
    }

    public function bancIds(Request $r): JsonResponse
    {
        $this->exigerBanc();

        return response()->json(['ids' => DB::table('relais_enveloppes')->where('dir', (string) $r->query('dir'))->orderBy('rid')->get(['id', 'appareil', 'dir', 'n'])]);
    }
}
