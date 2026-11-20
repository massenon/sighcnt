<?php

namespace App\Console\Commands;

use App\Relais\Exporteur;
use App\Relais\Format;
use Illuminate\Console\Command;

/** Export de la base du relais (fichier gzip dans storage/app/exports). À lancer par cron avant toute migration. */
class ExporterRelais extends Command
{
    protected $signature = 'relais:exporter {--avant-migration : marque l\'export comme précédant une migration}';

    protected $description = 'Exporte la base du relais (enveloppes chiffrées, codes hachés, audit) dans storage/app/exports';

    public function handle(): int
    {
        $e = Exporteur::exporter((bool) $this->option('avant-migration'), 'console');
        $this->info($e->fichier.' ('.Format::taille((int) $e->taille).')');

        return self::SUCCESS;
    }
}
