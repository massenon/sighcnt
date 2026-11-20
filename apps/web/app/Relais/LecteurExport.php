<?php

namespace App\Relais;

use Illuminate\Support\Facades\DB;

/**
 * Relecture d'un export `relais-*.jsonl.gz` (lot MAJ) : l'outil qui manquait pour le retour arrière du relais.
 *
 * `lire()` ne modifie RIEN : il compte les lignes par table, nomme tout ce qui est illisible (ligne non JSON, table inconnue, enregistrement mal formé) et rend un rapport.
 * `restaurer()` remet les lignes dans leurs tables, mais REFUSE (en le nommant) si une table visée n'est pas vide : il ne mélange jamais un export à une base vivante et n'écrase rien.
 * Le contenu de l'export est déjà chiffré de bout en bout : cet outil ne déchiffre rien et ne voit aucune donnée de santé.
 */
class LecteurExport
{
    /** @return array{lignes:int, tables:array<string,int>, anomalies:list<string>} */
    public static function lire(string $chemin): array
    {
        if (! is_file($chemin)) {
            throw new \RuntimeException('EXPORT_INTROUVABLE : le fichier '.$chemin.' n’existe pas. Geste : donner le chemin d’un export de storage/app/exports.');
        }
        $h = @gzopen($chemin, 'rb');
        if ($h === false) {
            throw new \RuntimeException('EXPORT_ILLISIBLE : le fichier n’est pas un gzip valide. Geste : refaire un export (relais:exporter).');
        }
        $tables = [];
        $anomalies = [];
        $n = 0;
        $i = 0;
        while (($ligne = gzgets($h)) !== false) {
            $i++;
            if (trim($ligne) === '') {
                continue;
            }
            $j = json_decode($ligne, true);
            if (! is_array($j) || ! isset($j['t'], $j['r']) || ! is_array($j['r'])) {
                $anomalies[] = "ligne $i : enregistrement mal formé";

                continue;
            }
            if (! in_array($j['t'], Exporteur::TABLES, true)) {
                $anomalies[] = "ligne $i : table inconnue « {$j['t']} »";

                continue;
            }
            $tables[$j['t']] = ($tables[$j['t']] ?? 0) + 1;
            $n++;
        }
        $fin = gzeof($h);
        gzclose($h);
        if (! $fin) {
            $anomalies[] = 'le fichier est tronqué (fin de flux gzip non atteinte)';
        }

        return ['lignes' => $n, 'tables' => $tables, 'anomalies' => $anomalies];
    }

    /** @return array{restaurees:array<string,int>} */
    public static function restaurer(string $chemin): array
    {
        $rapport = self::lire($chemin);
        if ($rapport['anomalies'] !== []) {
            throw new \RuntimeException('EXPORT_ANOMALIES : '.implode(' ; ', $rapport['anomalies']).'. Geste : ne rien restaurer, refaire un export.');
        }
        foreach (array_keys($rapport['tables']) as $t) {
            // `relais_meta` est SEMÉE par les migrations (réglages par défaut) : une base neuve n'est jamais vide de ce côté ; l'export l'emporte, clé par clé (réglages de la clinique).
            if ($t !== 'relais_meta' && DB::table($t)->count() > 0) {
                throw new \RuntimeException("RESTAURATION_BASE_NON_VIDE : la table $t contient déjà des lignes, rien n'est écrasé. Geste : restaurer sur une base neuve (migrate:fresh sur une base vide).");
            }
        }
        $restaurees = [];
        DB::transaction(function () use ($chemin, &$restaurees) {
            $h = gzopen($chemin, 'rb');
            while (($ligne = gzgets($h)) !== false) {
                if (trim($ligne) === '') {
                    continue;
                }
                $j = json_decode($ligne, true);
                if ($j['t'] === 'relais_meta') {
                    DB::table('relais_meta')->updateOrInsert(['k' => $j['r']['k']], $j['r']);
                } else {
                    DB::table($j['t'])->insert($j['r']);
                }
                $restaurees[$j['t']] = ($restaurees[$j['t']] ?? 0) + 1;
            }
            gzclose($h);
        });

        return ['restaurees' => $restaurees];
    }
}
