<?php

namespace App\Relais;

use Carbon\Carbon;

/** Mises en forme du panneau : dates en Africa/Porto-Novo, durées lisibles, tailles. Aucune règle métier. */
class Format
{
    public static function maintenant(): int
    {
        return (int) (microtime(true) * 1000);
    }

    public static function date(?int $ms): string
    {
        return $ms ? Carbon::createFromTimestampMs($ms)->timezone('Africa/Porto-Novo')->format('d/m/Y H:i:s') : 'jamais';
    }

    public static function depuis(?int $ms): string
    {
        if (! $ms) {
            return 'jamais';
        }

        return 'il y a '.self::duree(max(0, self::maintenant() - $ms));
    }

    public static function duree(int $ms): string
    {
        $s = intdiv($ms, 1000);
        if ($s < 60) {
            return $s.' s';
        }
        if ($s < 3600) {
            return intdiv($s, 60).' min';
        }
        if ($s < 86400) {
            return intdiv($s, 3600).' h';
        }

        return intdiv($s, 86400).' j';
    }

    public static function taille(int $octets): string
    {
        if ($octets >= 1048576) {
            return number_format($octets / 1048576, 1, ',', ' ').' Mo';
        }

        return number_format($octets / 1024, 1, ',', ' ').' Ko';
    }
}
