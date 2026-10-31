<?php

namespace App\Relais;

use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Mail;

/**
 * Évalue les quatre alertes techniques du relais et tient leur historique (ouverture, résolution).
 * Le relais ne juge JAMAIS un contenu : il regarde le battement de la mère, le nombre d'appareils bloqués qu'ELLE publie,
 * l'espace disque et le passage du cron. Idempotent : peut être rappelé à chaque affichage et à chaque minute.
 */
class Surveillance
{
    public const BATTEMENT = 'battement';

    public const BLOQUE = 'appareil_bloque';

    public const DISQUE = 'disque';

    public const CRON = 'cron';

    public static function libelle(string $type): string
    {
        foreach (config('relais.alertes') as $r) {
            if ($r['type'] === $type) {
                return $r['libelle'];
            }
        }

        return $type;
    }

    public static function disqueLibrePct(): ?float
    {
        $dir = storage_path();
        $libre = @disk_free_space($dir);
        $total = @disk_total_space($dir);

        return ($libre === false || ! $total) ? null : round(100 * $libre / $total, 1);
    }

    public static function ageBattement(): ?int
    {
        $bt = DB::table('relais_meta')->where('k', 'battement')->value('v');

        return $bt === null ? null : Format::maintenant() - (int) $bt;
    }

    public static function ageCron(): ?int
    {
        $c = DB::table('relais_meta')->where('k', 'cron_dernier')->value('v');

        return $c === null ? null : Format::maintenant() - (int) $c;
    }

    /** @return array<string, array{0: bool, 1: string}> type => [levée ?, détail technique] */
    public static function conditions(): array
    {
        $age = self::ageBattement();
        $ind = json_decode((string) DB::table('relais_meta')->where('k', 'indicateurs')->value('v'), true) ?: [];
        $bloques = (int) ($ind['appareils_bloques'] ?? 0);
        $libre = self::disqueLibrePct();
        $ageCron = self::ageCron();

        return [
            self::BATTEMENT => [$age === null || $age > (int) config('relais.seuil_battement_ms'), $age === null ? 'aucun battement reçu' : 'silence de '.Format::duree($age)],
            self::BLOQUE => [$bloques > 0, $bloques.' appareil(s) bloqué(s) déclaré(s) par la mère'],
            self::DISQUE => [$libre !== null && $libre < (int) config('relais.seuil_disque_pct'), 'espace libre '.$libre.' %'],
            self::CRON => [$ageCron === null || $ageCron > (int) config('relais.seuil_cron_ms'), $ageCron === null ? 'aucun passage enregistré' : 'dernier passage il y a '.Format::duree($ageCron)],
        ];
    }

    public static function evaluer(): void
    {
        $maintenant = Format::maintenant();
        $actives = collect(config('relais.alertes'))->where('active', true)->pluck('canal', 'type');
        foreach (self::conditions() as $type => [$levee, $detail]) {
            if (! $actives->has($type)) {
                continue;
            }
            $ouverte = DB::table('relais_alertes')->where('type', $type)->whereNull('fin')->first();
            if ($levee && ! $ouverte) {
                DB::table('relais_alertes')->insert(['type' => $type, 'detail' => $detail, 'debut' => $maintenant]);
                DB::table('relais_audit')->insert(['quand' => $maintenant, 'acteur' => 'système', 'action' => 'alerte_'.$type, 'detail' => $detail]);
                if (str_contains((string) $actives[$type], 'Courriel')) {
                    self::courriel($type, $detail);
                }
            } elseif (! $levee && $ouverte) {
                DB::table('relais_alertes')->where('id', $ouverte->id)->update(['fin' => $maintenant]);
                DB::table('relais_audit')->insert(['quand' => $maintenant, 'acteur' => 'système', 'action' => 'alerte_resolue', 'detail' => $type]);
            }
        }
    }

    /** Un courriel d'alerte porte le type, l'heure et le détail technique : jamais un nom de patient. */
    public static function courriel(string $type, string $detail): void
    {
        try {
            $adresses = User::pluck('email')->all();
            if ($adresses === []) {
                return;
            }
            Mail::raw('Alerte du relais SIGH-CNT : '.self::libelle($type).' ('.$detail.') à '.Format::date(Format::maintenant()).'.', function ($m) use ($adresses, $type) {
                $m->to($adresses)->subject('Relais SIGH-CNT : '.self::libelle($type));
            });
        } catch (\Throwable $e) {
            DB::table('relais_audit')->insert(['quand' => Format::maintenant(), 'acteur' => 'système', 'action' => 'courriel_echec', 'detail' => mb_substr(class_basename($e), 0, 120)]);
        }
    }
}
