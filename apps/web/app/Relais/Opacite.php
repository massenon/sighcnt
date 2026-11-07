<?php

namespace App\Relais;

use Illuminate\Support\Facades\DB;

/**
 * MESURE d'opacité sur un échantillon d'enveloppes : entropie moyenne (bits par octet) et nombre d'enveloppes dont le contenu
 * laisse lire un nom de collection ou de champ en clair. Le relais ne déchiffre rien : il regarde seulement si les octets
 * stockés ressemblent à du hasard, comme le fait le test d'opacité du banc.
 */
class Opacite
{
    public const ECHANTILLON = 200;

    /** @return array{echantillon: int, entropie: ?float, lisibles: int} */
    public static function mesurer(): array
    {
        $entropies = [];
        $lisibles = 0;
        foreach (DB::table('relais_enveloppes')->orderByDesc('rid')->limit(self::ECHANTILLON)->pluck('ct') as $ct) {
            $octets = base64_decode((string) $ct, true);
            if ($octets === false || $octets === '') {
                $octets = (string) $ct;
            }
            if ($octets === '') {
                continue;
            }
            $entropies[] = self::entropie($octets);
            if (preg_match('/"(collection|coll|nom|prenom|patient|table)\w*"\s*:|[\x20-\x7e]{24,}/i', $octets)) {
                $lisibles++;
            }
        }

        return [
            'echantillon' => count($entropies),
            'entropie' => $entropies === [] ? null : array_sum($entropies) / count($entropies),
            'lisibles' => $lisibles,
        ];
    }

    public static function entropie(string $octets): float
    {
        $n = strlen($octets);
        $h = 0.0;
        foreach (count_chars($octets, 1) as $c) {
            $p = $c / $n;
            $h -= $p * log($p, 2);
        }

        return $h;
    }

    /** La clé de clinique n'existe pas dans la configuration du relais : aucun réglage ne la désigne. */
    public static function cleDeCliniqueAuRelais(): bool
    {
        foreach (array_keys((array) config('relais')) as $k) {
            if (preg_match('/^(cle|key|secret_clinique|cle_clinique)/i', (string) $k)) {
                return true;
            }
        }

        return false;
    }
}
