<?php

namespace App\Relais;

use Illuminate\Support\Facades\DB;

/**
 * Export de la base du RELAIS (jamais des comptes ni des sessions) : un fichier gzip, une ligne JSON par enregistrement.
 * Le contenu est déjà chiffré de bout en bout : l'export ne contient aucune donnée lisible. Il sert à restaurer la mère
 * (journal chiffré) et à revenir en arrière après une migration.
 */
class Exporteur
{
    public const TABLES = ['relais_codes', 'relais_appareils', 'relais_enveloppes', 'relais_meta', 'relais_audit', 'relais_alertes', 'relais_indicateurs_historique'];

    public static function dossier(): string
    {
        return storage_path('app/exports');
    }

    public static function exporter(bool $avantMigration, string $acteur): object
    {
        if (! is_dir(self::dossier())) {
            mkdir(self::dossier(), 0770, true);
        }
        $quand = Format::maintenant();
        $fichier = 'relais-'.date('Ymd-His', (int) ($quand / 1000)).($avantMigration ? '-avant-migration' : '').'.jsonl.gz';
        $chemin = self::dossier().'/'.$fichier;
        $h = gzopen($chemin, 'wb6');
        foreach (self::TABLES as $table) {
            foreach (DB::table($table)->cursor() as $ligne) {
                gzwrite($h, json_encode(['t' => $table, 'r' => $ligne], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)."\n");
            }
        }
        gzclose($h);
        $taille = (int) filesize($chemin);
        $id = DB::table('relais_exports')->insertGetId(['quand' => $quand, 'taille' => $taille, 'avant_migration' => $avantMigration, 'fichier' => $fichier]);
        DB::table('relais_audit')->insert(['quand' => $quand, 'acteur' => $acteur, 'action' => 'export_base', 'detail' => $fichier.($avantMigration ? ' (avant migration)' : '')]);

        return DB::table('relais_exports')->where('id', $id)->first();
    }
}
