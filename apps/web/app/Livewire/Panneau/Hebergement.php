<?php

namespace App\Livewire\Panneau;

use App\Relais\Format;
use App\Relais\Surveillance;
use Illuminate\Support\Facades\DB;
use Livewire\Attributes\Layout;
use Livewire\Component;

/** Santé de l'hébergement mutualisé : PHP, base, cron, disque, certificat. Lecture seule. */
#[Layout('layouts.panneau')]
class Hebergement extends Component
{
    /** Jours restants du certificat TLS de APP_URL, ou null s'il n'est pas mesurable (HTTP, réseau fermé). */
    public static function joursCertificat(): ?int
    {
        $hote = parse_url((string) config('app.url'), PHP_URL_HOST);
        if (! $hote || parse_url((string) config('app.url'), PHP_URL_SCHEME) !== 'https') {
            return null;
        }
        $ctx = stream_context_create(['ssl' => ['capture_peer_cert' => true, 'verify_peer' => false, 'SNI_enabled' => true, 'peer_name' => $hote]]);
        $f = @stream_socket_client('ssl://'.$hote.':443', $no, $str, 3, STREAM_CLIENT_CONNECT, $ctx);
        if (! $f) {
            return null;
        }
        $cert = stream_context_get_params($f)['options']['ssl']['peer_certificate'] ?? null;
        fclose($f);
        $info = $cert ? openssl_x509_parse($cert) : null;

        return $info ? (int) floor(($info['validTo_time_t'] - time()) / 86400) : null;
    }

    public function render()
    {
        $driver = DB::connection()->getDriverName();
        try {
            $version = $driver === 'sqlite' ? 'SQLite '.DB::selectOne('select sqlite_version() as v')->v
                : ($driver === 'pgsql' ? 'PostgreSQL '.preg_replace('/^PostgreSQL (\S+).*/', '$1', DB::selectOne('select version() as v')->v) : $driver);
        } catch (\Throwable) {
            $version = $driver.' (version illisible)';
        }
        $ageCron = Surveillance::ageCron();
        $libre = Surveillance::disqueLibrePct();
        $jours = self::joursCertificat();
        $storageOk = is_writable(storage_path('app')) && is_writable(storage_path('logs'));
        $pgsqlCharge = extension_loaded('pdo_pgsql');
        $seuilCron = (int) config('relais.seuil_cron_ms');

        $controles = [
            ['Cron schedule:run', $ageCron === null ? 'alerte' : ($ageCron > $seuilCron ? 'alerte' : 'ok'), $ageCron === null ? 'aucun passage enregistré' : 'dernier passage il y a '.Format::duree($ageCron)],
            ['Certificat TLS', $jours === null ? 'attention' : ($jours < 14 ? 'alerte' : ($jours < 30 ? 'attention' : 'ok')), $jours === null ? 'non mesurable (APP_URL n’est pas en https ou le réseau est fermé)' : 'valide '.$jours.' jours'],
            ['Dossier storage/', $storageOk ? 'ok' : 'alerte', $storageOk ? 'écriture possible' : 'écriture impossible'],
            ['Extension pdo_pgsql', $pgsqlCharge ? 'ok' : ($driver === 'pgsql' ? 'alerte' : 'attention'), $pgsqlCharge ? 'chargée' : 'absente'.($driver === 'pgsql' ? '' : ' (base en '.$driver.')')],
        ];

        return view('livewire.panneau.hebergement', [
            'php' => PHP_VERSION, 'base' => $version,
            'cron' => $ageCron === null ? 'jamais' : 'il y a '.Format::duree($ageCron),
            'cronEtat' => $ageCron === null || $ageCron > $seuilCron ? 'alerte' : 'ok',
            'disque' => $libre === null ? 'n/d' : round(100 - $libre).' %',
            'disqueEtat' => $libre !== null && $libre < (int) config('relais.seuil_disque_pct') ? 'alerte' : 'ok',
            'controles' => $controles,
        ]);
    }
}
