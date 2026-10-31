<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

/* Purge quotidienne de l'AUDIT (jamais des enveloppes). Sur cPanel, c'est le cron d'une minute `schedule:run` qui la déclenche. */
Illuminate\Support\Facades\Schedule::command('relais:purger --oui')->dailyAt('03:10');

/* Surveillance chaque minute : marque le passage du cron (écran Hébergement) et lève ou résout les alertes. */
Illuminate\Support\Facades\Schedule::command('relais:surveiller')->everyMinute();

/* Export quotidien de la base du relais. */
Illuminate\Support\Facades\Schedule::command('relais:exporter')->dailyAt('03:00');
