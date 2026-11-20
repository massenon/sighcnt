<?php

namespace App\Console\Commands;

use App\Relais\JetonsCss;
use Illuminate\Console\Command;

/** Engendre public/css/jetons.css depuis les jetons de design du projet. Avec --verifier : ne réécrit rien, échoue si le fichier a dérivé. */
class GenererJetonsCss extends Command
{
    protected $signature = 'relais:jetons-css {--verifier : compare sans écrire}';

    protected $description = 'Engendre public/css/jetons.css depuis docs/design/design-tokens.json';

    public function handle(): int
    {
        $source = JetonsCss::chemin();
        if (! is_file($source)) {
            $this->error('Jetons introuvables : '.$source);

            return self::FAILURE;
        }
        $css = JetonsCss::css(json_decode((string) file_get_contents($source), true, 512, JSON_THROW_ON_ERROR));
        if ($this->option('verifier')) {
            if (@file_get_contents(JetonsCss::sortie()) !== $css) {
                $this->error('public/css/jetons.css a dérivé des jetons : lancer php artisan relais:jetons-css.');

                return self::FAILURE;
            }
            $this->info('jetons.css est à jour.');

            return self::SUCCESS;
        }
        file_put_contents(JetonsCss::sortie(), $css);
        $this->info('jetons.css engendré ('.substr_count($css, "\n").' lignes).');

        return self::SUCCESS;
    }
}
