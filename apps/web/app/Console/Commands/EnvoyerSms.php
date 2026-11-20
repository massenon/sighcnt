<?php

namespace App\Console\Commands;

use App\Relais\Sms\Messages;
use Illuminate\Console\Command;

/** Envoie les SMS arrivés à l'heure (ADR-0008). Planifié chaque minute, sans chevauchement. Efface le clair dès l'envoi ; ne reporte jamais un message bloqué par le plafond. */
class EnvoyerSms extends Command
{
    protected $signature = 'relais:sms-envoyer';

    protected $description = 'Envoie les SMS planifiés arrivés à l’heure (passerelle SMS du relais).';

    public function handle(): int
    {
        $b = Messages::passer();
        $this->info('SMS : '.$b['envoye'].' envoyé(s), '.$b['refuse'].' refusé(s), '.$b['planifie'].' en attente.');

        return self::SUCCESS;
    }
}
