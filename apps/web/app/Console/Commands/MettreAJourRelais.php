<?php

namespace App\Console\Commands;

use App\Relais\Exporteur;
use App\Relais\LecteurExport;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Artisan;

/**
 * Mise à jour du relais (lot MAJ) : la base est EXPORTÉE puis RELUE avant toute migration Laravel ; si l'export est illisible la migration ne part PAS (refus nommé
 * `MAJ_SANS_SAUVEGARDE`). Retour arrière : `php artisan relais:relire-export <fichier> --restaurer` sur une base neuve, avec l'ancien code.
 */
class MettreAJourRelais extends Command
{
    protected $signature = 'relais:mise-a-jour {--essai : dit ce qui serait fait, sans exporter ni migrer}';

    protected $description = 'Exporte et relit la base du relais, puis lance les migrations (jamais de migration sans export relu)';

    public function handle(): int
    {
        if ($this->option('essai')) {
            $this->line('Essai à blanc : un export « avant migration » serait fait et relu, puis php artisan migrate --force. Rien n’est écrit.');
            Artisan::call('migrate:status');
            $this->line(Artisan::output());

            return self::SUCCESS;
        }
        $e = Exporteur::exporter(true, 'console');
        $chemin = Exporteur::dossier().'/'.$e->fichier;
        try {
            $r = LecteurExport::lire($chemin);
            if ($r['anomalies'] !== []) {
                throw new \RuntimeException(implode(' ; ', $r['anomalies']));
            }
        } catch (\RuntimeException $ex) {
            $this->error('MAJ_SANS_SAUVEGARDE : l’export d’avant migration est illisible ('.$ex->getMessage().'). Geste : régler le problème de disque puis relancer, aucune migration n’a été faite.');

            return self::FAILURE;
        }
        $this->info('Export relu : '.$e->fichier.' ('.$r['lignes'].' ligne(s)).');
        $code = Artisan::call('migrate', ['--force' => true]);
        $this->line(Artisan::output());
        if ($code !== 0) {
            $this->error('La migration a échoué. Retour arrière : relais:relire-export '.$e->fichier.' --restaurer, sur une base neuve, avec le code de l\'ancienne version.');
        }

        return $code === 0 ? self::SUCCESS : self::FAILURE;
    }
}
