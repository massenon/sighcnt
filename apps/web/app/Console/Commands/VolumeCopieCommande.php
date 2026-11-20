<?php

namespace App\Console\Commands;

use App\Relais\VolumeCopie;
use Illuminate\Console\Command;

/** Mesure Q4 : le volume de la copie consultable, par appareil (taille du texte chiffré, jamais le contenu). */
class VolumeCopieCommande extends Command
{
    protected $signature = 'relais:copie-volume';

    protected $description = 'Volume de la copie consultable : fiches, octets, taille moyenne et maximale par fiche';

    public function handle(): int
    {
        $m = VolumeCopie::mesurer();
        if ($m['fiches'] === 0) {
            $this->info('Aucune copie reçue.');

            return self::SUCCESS;
        }
        $this->table(['Appareil', 'Fiches', 'Octets', 'Moyenne', 'Maximum'], array_map(fn ($a) => [$a['appareil'], $a['fiches'], $a['octets'], $a['moyenne'], $a['maximum']], $m['appareils']));
        $this->info("Total : {$m['fiches']} fiche(s), {$m['octets']} octets, {$m['moyenne']} octets en moyenne par fiche, {$m['maximum']} au maximum.");

        return self::SUCCESS;
    }
}
