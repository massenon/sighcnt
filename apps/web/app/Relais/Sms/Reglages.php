<?php

namespace App\Relais\Sms;

use Illuminate\Support\Facades\DB;

/**
 * LES LIMITES DE LA PASSERELLE SMS : EN BASE (`relais_meta`, clés `reglage.sms.*`), défaut SEMÉ par la migration, bornées à l'écriture par le panneau, journalisées. Jamais une constante du code.
 * Défauts : plafond 200 par jour (Direction, 07/11/2026, M2), 5 tentatives quand le fournisseur ne répond pas (Direction, 16/11/2026, AQ 27). Le délai de reprise (5 minutes) et la péremption
 * (3 heures) sont des PROPOSITIONS « à valider » : la Direction ne les a pas fixés.
 */
class Reglages
{
    /** @var array<string, array{defaut: int, min: int, max: int, unite: string, libelle: string}> */
    public const DEFAUTS = [
        'plafond_jour' => ['defaut' => 200, 'min' => 1, 'max' => 5000, 'unite' => 'messages', 'libelle' => 'Plafond de messages par jour (heure du Bénin)'],
        'tentatives_max' => ['defaut' => 5, 'min' => 1, 'max' => 20, 'unite' => 'tentatives', 'libelle' => 'Tentatives quand le fournisseur ne répond pas'],
        'reprise_secondes' => ['defaut' => 300, 'min' => 30, 'max' => 86400, 'unite' => 'secondes', 'libelle' => 'Délai entre deux tentatives'],
        'peremption_minutes' => ['defaut' => 180, 'min' => 5, 'max' => 2880, 'unite' => 'minutes', 'libelle' => 'Un message resté planifié plus longtemps après son heure n’est plus envoyé'],
        'conservation_jours' => ['defaut' => 365, 'min' => 30, 'max' => 3650, 'unite' => 'jours', 'libelle' => 'Conservation du journal des envois (sans numéro ni texte)'],
    ];

    /** Longueur maximale d'un texte (Direction, brief du lot : 320 caractères) : une règle du protocole, pas un réglage. */
    public const TEXTE_MAX = 320;

    public static function cle(string $nom): string
    {
        return 'reglage.sms.'.$nom;
    }

    public static function semer(): void
    {
        foreach (self::DEFAUTS as $nom => $d) {
            DB::table('relais_meta')->insertOrIgnore(['k' => self::cle($nom), 'v' => (string) $d['defaut']]);
        }
    }

    /** @return array<string, int> */
    public static function toutes(): array
    {
        $lues = DB::table('relais_meta')->where('k', 'like', 'reglage.sms.%')->pluck('v', 'k');
        $out = [];
        foreach (self::DEFAUTS as $nom => $d) {
            $v = $lues[self::cle($nom)] ?? null;
            $out[$nom] = is_numeric($v) ? (int) $v : $d['defaut'];
        }

        return $out;
    }

    public static function poser(string $nom, int $valeur, string $acteur): ?string
    {
        $d = self::DEFAUTS[$nom] ?? null;
        if ($d === null) {
            return 'Réglage inconnu.';
        }
        if ($valeur < $d['min'] || $valeur > $d['max']) {
            return $d['libelle'].' : de '.$d['min'].' à '.$d['max'].' '.$d['unite'].'.';
        }
        $avant = self::toutes()[$nom];
        DB::table('relais_meta')->updateOrInsert(['k' => self::cle($nom)], ['v' => (string) $valeur]);
        DB::table('relais_audit')->insert(['quand' => (int) (microtime(true) * 1000), 'acteur' => $acteur, 'action' => 'reglage_sms', 'detail' => $nom.' : '.$avant.' → '.$valeur]);

        return null;
    }
}
