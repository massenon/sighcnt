<?php

namespace App\Console\Commands;

use App\Relais\Format;
use App\Relais\Surveillance;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/** Passage du cron (chaque minute) : marque le passage, évalue les alertes, purge l'historique des indicateurs (48 h). */
class SurveillerRelais extends Command
{
    protected $signature = 'relais:surveiller';

    protected $description = 'Marque le passage du cron et évalue les alertes techniques du relais';

    public function handle(): int
    {
        DB::table('relais_meta')->updateOrInsert(['k' => 'cron_dernier'], ['v' => (string) Format::maintenant()]);
        DB::table('relais_indicateurs_historique')->where('quand', '<', Format::maintenant() - 48 * 3600 * 1000)->delete();
        Surveillance::evaluer();
        $this->info('Surveillance évaluée.');

        return self::SUCCESS;
    }
}
