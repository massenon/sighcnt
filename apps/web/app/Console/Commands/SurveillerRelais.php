<?php

namespace App\Console\Commands;

use App\Relais\Format;
use App\Relais\Surveillance;
use App\Relais\Synchro\Historique;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/** Passage du cron (chaque minute) : marque le passage, évalue les alertes, purge l'historique des indicateurs (48 h) et celui de la synchronisation (durée réglée). */
class SurveillerRelais extends Command
{
    protected $signature = 'relais:surveiller';

    protected $description = 'Marque le passage du cron et évalue les alertes techniques du relais';

    public function handle(): int
    {
        DB::table('relais_meta')->updateOrInsert(['k' => 'cron_dernier'], ['v' => (string) Format::maintenant()]);
        DB::table('relais_indicateurs_historique')->where('quand', '<', Format::maintenant() - 48 * 3600 * 1000)->delete();
        // Lot RLS-SYNC : l'historique de synchronisation, relevé à l'intervalle réglé puis purgé au-delà de la durée réglée (3 mois par défaut), mère vivante ou non.
        Historique::echantillonnerRelais();
        Historique::purger();
        Surveillance::evaluer();
        $this->info('Surveillance évaluée.');

        return self::SUCCESS;
    }
}
