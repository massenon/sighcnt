<?php

namespace App\Relais\Synchro;

use App\Relais\Format;
use Illuminate\Support\Facades\DB;

/**
 * L'HISTORIQUE DE SYNCHRONISATION (table `relais_synchro_historique`, À PART de l'historique des indicateurs purgé à 48 h) : un relevé par appareil à intervalle réglé, conservé pour la durée
 * réglée (90 jours par défaut, bornée). Des compteurs et des horodatages : `ref` est le nom technique d'un poste, l'identifiant d'un appareil ou « mere ».
 *
 * Le battement de la mère part toutes les quelques secondes : écrire une ligne par envoi remplirait la base. Un relevé n'est donc pris que si le précédent date de l'intervalle réglé.
 */
class Historique
{
    public const PORTE_FILEULS = 'synchro_echantillon_fileuls';

    public const PORTE_RELAIS = 'synchro_echantillon_relais';

    private static function porteOuverte(string $cle, int $maintenant): bool
    {
        $dernier = DB::table('relais_meta')->where('k', $cle)->value('v');

        return $dernier === null || $maintenant - (int) $dernier >= Reglages::valeur('echantillon_minutes') * 60000;
    }

    private static function fermerPorte(string $cle, int $maintenant): void
    {
        DB::table('relais_meta')->updateOrInsert(['k' => $cle], ['v' => (string) $maintenant]);
    }

    /**
     * Un relevé des fileuls que la mère vient de publier (déjà validés par la liste blanche).
     *
     * @param  list<array<string, mixed>>  $fileuls
     */
    public static function echantillonnerFileuls(array $fileuls, ?int $maintenant = null): int
    {
        $maintenant ??= Format::maintenant();
        if ($fileuls === [] || ! self::porteOuverte(self::PORTE_FILEULS, $maintenant)) {
            return 0;
        }
        $n = 0;
        foreach ($fileuls as $f) {
            DB::table('relais_synchro_historique')->insert([
                'quand' => $maintenant, 'nature' => 'fileul', 'ref' => (string) $f['poste'],
                'dernier_contact' => $f['dernierContact'] ?? null, 'retard_journal' => $f['retardJournal'] ?? null,
                'conflits' => $f['conflitsOuverts'] ?? null, 'demandes' => $f['demandesImportEnAttente'] ?? null, 'attente' => null,
            ]);
            $n++;
        }
        self::fermerPorte(self::PORTE_FILEULS, $maintenant);

        return $n;
    }

    /** Un relevé de ce que le RELAIS voit lui-même : le battement de la mère et chaque mobile (activité, enveloppes en attente). Passe par le cron, mère vivante ou non. */
    public static function echantillonnerRelais(?int $maintenant = null): int
    {
        $maintenant ??= Format::maintenant();
        if (! self::porteOuverte(self::PORTE_RELAIS, $maintenant)) {
            return 0;
        }
        $bt = DB::table('relais_meta')->where('k', 'battement')->value('v');
        $n = 0;
        DB::table('relais_synchro_historique')->insert([
            'quand' => $maintenant, 'nature' => 'mere', 'ref' => 'mere', 'dernier_contact' => $bt === null ? null : (int) $bt,
            'retard_journal' => null, 'conflits' => null, 'demandes' => null, 'attente' => null,
        ]);
        $n++;
        foreach (Etat::mobiles($maintenant) as $m) {
            if (! $m['actif']) {
                continue;
            }
            DB::table('relais_synchro_historique')->insert([
                'quand' => $maintenant, 'nature' => 'mobile', 'ref' => (string) $m['uuid'], 'dernier_contact' => $m['dernier'],
                'retard_journal' => null, 'conflits' => null, 'demandes' => null, 'attente' => $m['attente'],
            ]);
            $n++;
        }
        self::fermerPorte(self::PORTE_RELAIS, $maintenant);

        return $n;
    }

    /** Purge ce qui dépasse la durée réglée (jamais en dessous : elle est bornée par un plancher). Rend le nombre de lignes retirées. */
    public static function purger(?int $maintenant = null): int
    {
        $maintenant ??= Format::maintenant();
        $limite = $maintenant - Reglages::valeur('conservation_jours') * 86400 * 1000;

        return DB::table('relais_synchro_historique')->where('quand', '<', $limite)->delete();
    }
}
