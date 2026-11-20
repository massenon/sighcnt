<?php

namespace App\Relais;

use Illuminate\Support\Facades\DB;

/**
 * MESURE Q4 du PRD relais consultable : combien pèse la copie ? Une enveloppe du sens `copie` porte UNE fiche ; le relais ne voit que sa taille (octets du
 * texte chiffré en base64), jamais son contenu. La mesure rend, par appareil et au total, le nombre de fiches copiées, le volume et la taille moyenne et
 * maximale d'une fiche : c'est ce qui permet de dimensionner l'hébergement avant de décider quelles collections copier.
 */
class VolumeCopie
{
    /** @return array{fiches: int, octets: int, moyenne: ?int, maximum: int, appareils: array<int, array{appareil: string, fiches: int, octets: int, moyenne: int, maximum: int}>} */
    public static function mesurer(): array
    {
        $rows = DB::table('relais_enveloppes')->where('dir', 'copie')
            ->selectRaw('appareil, COUNT(*) as fiches, SUM(taille) as octets, MAX(taille) as maximum')->groupBy('appareil')->orderBy('appareil')->get();
        $appareils = [];
        $fiches = 0;
        $octets = 0;
        $maximum = 0;
        foreach ($rows as $r) {
            $appareils[] = ['appareil' => $r->appareil, 'fiches' => (int) $r->fiches, 'octets' => (int) $r->octets, 'moyenne' => (int) round($r->octets / $r->fiches), 'maximum' => (int) $r->maximum];
            $fiches += (int) $r->fiches;
            $octets += (int) $r->octets;
            $maximum = max($maximum, (int) $r->maximum);
        }

        return ['fiches' => $fiches, 'octets' => $octets, 'moyenne' => $fiches === 0 ? null : (int) round($octets / $fiches), 'maximum' => $maximum, 'appareils' => $appareils];
    }
}
