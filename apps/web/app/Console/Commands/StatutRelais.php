<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/** Volumes du relais (aucun contenu : tout est chiffré), pour une surveillance par cron ou un contrôle à la main. */
class StatutRelais extends Command
{
    protected $signature = 'relais:statut';

    protected $description = 'Affiche les volumes du relais (appareils, enveloppes par sens, octets, dernier battement)';

    public function handle(): int
    {
        $app = DB::table('relais_appareils')->selectRaw('etat, count(*) as n')->groupBy('etat')->pluck('n', 'etat');
        $this->line('Appareils : '.($app->isEmpty() ? 'aucun' : $app->map(fn ($n, $e) => "$e=$n")->implode(', ')));
        foreach (DB::table('relais_enveloppes')->selectRaw('dir, count(*) as n, coalesce(sum(taille),0) as octets')->groupBy('dir')->get() as $l) {
            $this->line(sprintf('Enveloppes %-11s : %d (%s)', $l->dir, $l->n, number_format((int) $l->octets / 1024, 1, ',', ' ').' Ko'));
        }
        $b = DB::table('relais_meta')->where('k', 'battement')->value('v');
        $this->line('Dernier battement de la mère : '.($b ? date('Y-m-d H:i:s', (int) ((int) $b / 1000)) : 'jamais'));

        return self::SUCCESS;
    }
}
