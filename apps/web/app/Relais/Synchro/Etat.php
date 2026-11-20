<?php

namespace App\Relais\Synchro;

use App\Relais\Format;
use Illuminate\Support\Facades\DB;

/**
 * L'ÉTAT DE SYNCHRONISATION que lit l'écran du panneau et que consulte la surveillance : la mère (son battement), les fileuls (ce que la MÈRE publie d'eux : le relais ne les voit pas, ils parlent
 * à la mère sur le réseau local) et les mobiles (ce que le RELAIS voit : leurs dépôts, leurs relèves, leur boîte). Des compteurs et des horodatages ; les états sont jugés sur les seuils RÉGLÉS
 * EN BASE (Reglages). Le relais SIGNALE, il ne juge jamais un contenu.
 *
 * Deux règles de lecture :
 *  - une valeur que personne n'a publiée est « non publié » ou « jamais vu », jamais zéro ;
 *  - quand la mère ne publie plus, l'état de ses fileuls n'est PAS ÉTABLI (« inconnu ») : leur silence apparent serait celui de la mère, déjà signalé par l'alerte du battement.
 */
class Etat
{
    public const A_JOUR = 'a_jour';

    public const EN_RETARD = 'en_retard';

    public const SILENCIEUX = 'silencieux';

    public const JAMAIS_VU = 'jamais_vu';

    public const INCONNU = 'inconnu';

    public const NON_PUBLIE = 'non_publie';

    public const REVOQUE = 'revoque';

    public const LIBELLES = [
        self::A_JOUR => 'À jour', self::EN_RETARD => 'En retard', self::SILENCIEUX => 'Silencieux', self::JAMAIS_VU => 'Jamais vu',
        self::INCONNU => 'Inconnu', self::NON_PUBLIE => 'Non publié', self::REVOQUE => 'Révoqué',
    ];

    /** La couleur de la puce : ok, attention, alerte (classes de panneau.css) ; l'absence de donnée n'est ni verte ni rouge. */
    public static function ton(string $etat): string
    {
        return match ($etat) {
            self::A_JOUR => 'ok', self::EN_RETARD => 'attention', self::SILENCIEUX => 'alerte', default => 'attention',
        };
    }

    public static function libelle(string $etat, ?string $feminin = null): string
    {
        if ($feminin !== null && $etat === self::SILENCIEUX) {
            return 'Silencieuse';
        }

        return self::LIBELLES[$etat] ?? $etat;
    }

    public static function fonction(?string $profil, ?string $fonction): string
    {
        if (! $profil) {
            return 'non précisé';
        }

        return $profil === 'reception' ? 'Réception de secours' : 'Soignant'.($fonction ? ' · '.str_replace('_', ' ', $fonction) : '');
    }

    /** Jugement d'un âge (ms) contre deux seuils (minutes). */
    public static function juger(?int $age, int $enRetardMin, int $silencieuxMin): string
    {
        if ($age === null) {
            return self::JAMAIS_VU;
        }
        if ($age > $silencieuxMin * 60000) {
            return self::SILENCIEUX;
        }

        return $age > $enRetardMin * 60000 ? self::EN_RETARD : self::A_JOUR;
    }

    private static function meta(string $k): ?string
    {
        $v = DB::table('relais_meta')->where('k', $k)->value('v');

        return $v === null ? null : (string) $v;
    }

    /** @return array<string, mixed> */
    public static function indicateurs(): array
    {
        $j = json_decode((string) self::meta('indicateurs'), true);

        return is_array($j) ? $j : [];
    }

    public static function mere(?int $maintenant = null): array
    {
        $maintenant ??= Format::maintenant();
        $r = Reglages::toutes();
        $bt = self::meta('battement');
        $age = $bt === null ? null : max(0, $maintenant - (int) $bt);
        $ind = self::indicateurs();
        $etat = $age === null ? self::NON_PUBLIE : ($age > $r['mere_silencieuse_min'] * 60000 ? self::SILENCIEUX : ($age > $r['mere_en_retard_min'] * 60000 ? self::EN_RETARD : self::A_JOUR));
        $seq = $ind['seq_max'] ?? ($ind['seq'] ?? null);
        $protocole = $ind['protocole'] ?? null;

        return [
            'battement' => $bt === null ? null : (int) $bt, 'age' => $age, 'etat' => $etat,
            'seq' => is_int($seq) ? $seq : null, 'protocole' => is_int($protocole) ? $protocole : null,
        ];
    }

    /** La mère ne publie plus : l'état de ses fileuls n'est pas établi. */
    public static function mereSilencieuse(?int $maintenant = null): bool
    {
        $maintenant ??= Format::maintenant();
        $le = self::meta('indicateurs_le');

        return $le === null || $maintenant - (int) $le > Reglages::valeur('mere_silencieuse_min') * 60000;
    }

    /**
     * Un fileul par ligne, tel que la mère le publie. `null` : la mère n'a rien publié sur ses fileuls (« non publié »), à ne pas confondre avec une liste vide (aucun fileul).
     *
     * @return list<array<string, mixed>>|null
     */
    public static function fileuls(?int $maintenant = null): ?array
    {
        $maintenant ??= Format::maintenant();
        $ind = self::indicateurs();
        if (! isset($ind['fileuls']) || ! is_array($ind['fileuls'])) {
            return null;
        }
        $r = Reglages::toutes();
        $mereMuette = self::mereSilencieuse($maintenant);
        $out = [];
        foreach ($ind['fileuls'] as $f) {
            if (! is_array($f)) {
                continue;
            }
            $contact = isset($f['dernierContact']) && is_int($f['dernierContact']) ? $f['dernierContact'] : null;
            $retard = isset($f['retardJournal']) && is_int($f['retardJournal']) ? $f['retardJournal'] : null;
            $age = $contact === null ? null : max(0, $maintenant - $contact);
            if ($mereMuette) {
                $etat = self::INCONNU;
            } else {
                $etat = self::juger($age, $r['fileul_en_retard_min'], $r['fileul_silencieux_min']);
                if ($etat === self::A_JOUR && $retard !== null && $retard > $r['fileul_retard_journal']) {
                    $etat = self::EN_RETARD;
                }
            }
            $out[] = [
                'poste' => (string) ($f['poste'] ?? ''), 'dernier_contact' => $contact, 'age' => $age, 'retard_journal' => $retard,
                'conflits' => isset($f['conflitsOuverts']) && is_int($f['conflitsOuverts']) ? $f['conflitsOuverts'] : null,
                'demandes' => isset($f['demandesImportEnAttente']) && is_int($f['demandesImportEnAttente']) ? $f['demandesImportEnAttente'] : null,
                'etat' => $etat,
            ];
        }

        return $out;
    }

    /** @return list<array<string, mixed>> */
    public static function mobiles(?int $maintenant = null): array
    {
        $maintenant ??= Format::maintenant();
        $r = Reglages::toutes();
        $depots = DB::table('relais_enveloppes')->where('dir', 'vers_mere')->selectRaw('appareil, MAX(recu) as dernier')->groupBy('appareil')->pluck('dernier', 'appareil');
        $attente = DB::table('relais_enveloppes as e')->join('relais_appareils as a', 'a.uuid', '=', 'e.appareil')->where('e.dir', 'vers_mobile')->whereColumn('e.n', '>', 'a.releve_n')
            ->selectRaw('e.appareil, COUNT(*) as n')->groupBy('e.appareil')->pluck('n', 'appareil');
        $out = [];
        foreach (DB::table('relais_appareils')->orderBy('uuid')->get() as $a) {
            $depot = isset($depots[$a->uuid]) ? (int) $depots[$a->uuid] : null;
            $releve = $a->dernier_releve === null ? null : (int) $a->dernier_releve;
            $dernier = max($depot ?? 0, $releve ?? 0) ?: null;
            $age = $dernier === null ? null : max(0, $maintenant - $dernier);
            $etat = $a->etat === 'revoque' ? self::REVOQUE : self::juger($age, $r['mobile_en_retard_min'], $r['mobile_silencieux_min']);
            $out[] = [
                'uuid' => $a->uuid, 'profil' => $a->profil, 'fonction' => $a->fonction, 'actif' => $a->etat === 'actif',
                'dernier_depot' => $depot, 'dernier_releve' => $releve, 'dernier' => $dernier, 'age' => $age,
                'attente' => (int) ($attente[$a->uuid] ?? 0), 'etat' => $etat,
            ];
        }

        return $out;
    }

    /**
     * Ce que la surveillance compte : fileuls silencieux (contact connu, au-delà du seuil, la mère publiant), mobiles actifs silencieux, boîtes qui dépassent le seuil.
     *
     * @return array{fileuls_silencieux: int, mobiles_silencieux: int, boites: int}
     */
    public static function resume(?int $maintenant = null): array
    {
        $fileuls = self::fileuls($maintenant) ?? [];
        $r = Reglages::toutes();
        $mobiles = array_filter(self::mobiles($maintenant), fn ($m) => $m['actif']);

        return [
            'fileuls_silencieux' => count(array_filter($fileuls, fn ($f) => $f['etat'] === self::SILENCIEUX)),
            'mobiles_silencieux' => count(array_filter($mobiles, fn ($m) => $m['etat'] === self::SILENCIEUX)),
            'boites' => count(array_filter($mobiles, fn ($m) => $m['attente'] > $r['boite_enveloppes_max'])),
        ];
    }
}
