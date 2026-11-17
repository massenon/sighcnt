<?php

namespace App\Console\Commands;

use App\Relais\LecteurExport;
use Illuminate\Console\Command;

/** Relit un export du relais (comptes par table, anomalies nommées) ; avec --restaurer, le remet dans une base NEUVE (retour arrière). */
class RelireExport extends Command
{
    protected $signature = 'relais:relire-export {fichier : chemin d\'un relais-*.jsonl.gz} {--restaurer : remet les lignes dans une base neuve (refus nommé si une table n\'est pas vide)}';

    protected $description = 'Relit un export du relais sans rien modifier, ou le restaure dans une base neuve (retour arrière après une migration)';

    public function handle(): int
    {
        try {
            $r = LecteurExport::lire((string) $this->argument('fichier'));
        } catch (\RuntimeException $e) {
            $this->error($e->getMessage());

            return self::FAILURE;
        }
        foreach ($r['tables'] as $t => $n) {
            $this->line(sprintf('%-34s %d', $t, $n));
        }
        $this->info($r['lignes'].' ligne(s) lue(s), '.count($r['anomalies']).' anomalie(s).');
        foreach ($r['anomalies'] as $a) {
            $this->warn($a);
        }
        if (! $this->option('restaurer')) {
            return $r['anomalies'] === [] ? self::SUCCESS : self::FAILURE;
        }
        try {
            $res = LecteurExport::restaurer((string) $this->argument('fichier'));
        } catch (\RuntimeException $e) {
            $this->error($e->getMessage());

            return self::FAILURE;
        }
        $this->info('Restauré : '.json_encode($res['restaurees']));

        return self::SUCCESS;
    }
}
