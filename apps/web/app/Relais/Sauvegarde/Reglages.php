<?php

namespace App\Relais\Sauvegarde;

use Illuminate\Support\Facades\DB;

/**
 * LES LIMITES DE LA SAUVEGARDE HORS SITE : enregistrées EN BASE (`relais_meta`, clés `reglage.sauvegarde.*`), jamais une constante du code, défaut SEMÉ par la migration, réglables par le
 * superadmin au panneau, BORNÉES à l'écriture par le panneau (plancher et plafond dits). Toutes les valeurs par défaut sont des PROPOSITIONS « à valider » (DECISIONS-A-VALIDER.md, section AA) :
 * l'espace réel de l'hébergement n'est pas mesuré. Le client (la mère) lit ces limites par `GET /sauvegarde/etat`.
 */
class Reglages
{
    private const MIO = 1048576;

    /** @var array<string, array{defaut: int, min: int, max: int, unite: string, libelle: string}> */
    public const DEFAUTS = [
        'quota_octets' => ['defaut' => 5 * 1024 * self::MIO, 'min' => 64 * self::MIO, 'max' => 1024 * 1024 * self::MIO, 'unite' => 'octets', 'libelle' => 'Espace total des copies hors site (quota)'],
        'taille_max_copie' => ['defaut' => 1024 * self::MIO, 'min' => self::MIO, 'max' => 100 * 1024 * self::MIO, 'unite' => 'octets', 'libelle' => 'Taille maximale d’une copie'],
        'taille_bloc_max' => ['defaut' => 2 * self::MIO, 'min' => 65536, 'max' => 8 * self::MIO, 'unite' => 'octets', 'libelle' => 'Taille maximale d’un bloc (requête PHP)'],
        'rotation_plancher' => ['defaut' => 2, 'min' => 1, 'max' => 10, 'unite' => 'copies', 'libelle' => 'Plancher de rotation (copies toujours restaurables)'],
        'rotation_plafond' => ['defaut' => 60, 'min' => 2, 'max' => 365, 'unite' => 'copies', 'libelle' => 'Plafond de rotation (copies courantes)'],
        'orphelins_heures' => ['defaut' => 72, 'min' => 1, 'max' => 720, 'unite' => 'heures', 'libelle' => 'Délai avant qu’un bloc jamais rattaché soit libérable'],
    ];

    public static function cle(string $nom): string
    {
        return 'reglage.sauvegarde.'.$nom;
    }

    /** Sème les défauts SANS écraser une valeur déjà posée (rejouable). */
    public static function semer(): void
    {
        foreach (self::DEFAUTS as $nom => $d) {
            DB::table('relais_meta')->insertOrIgnore(['k' => self::cle($nom), 'v' => (string) $d['defaut']]);
        }
    }

    /** Les valeurs en vigueur, lues de la base (à défaut, le défaut). Aucune borne à la lecture : le banc règle des valeurs que le panneau refuserait. */
    public static function toutes(): array
    {
        $lues = DB::table('relais_meta')->where('k', 'like', 'reglage.sauvegarde.%')->pluck('v', 'k');
        $out = [];
        foreach (self::DEFAUTS as $nom => $d) {
            $v = $lues[self::cle($nom)] ?? null;
            $out[$nom] = is_numeric($v) ? (int) $v : $d['defaut'];
        }

        return $out;
    }

    /** Pose une limite DEPUIS LE PANNEAU : bornée, journalisée (ancienne et nouvelle valeur). Rend un refus nommé ou null. */
    public static function poser(string $nom, int $valeur, string $acteur): ?string
    {
        $d = self::DEFAUTS[$nom] ?? null;
        if ($d === null) {
            return 'Réglage inconnu.';
        }
        if ($valeur < $d['min'] || $valeur > $d['max']) {
            return $d['libelle'].' : de '.$d['min'].' à '.$d['max'].' '.$d['unite'].'.';
        }
        $tous = self::toutes();
        if ($nom === 'rotation_plancher' && $valeur > $tous['rotation_plafond']) {
            return 'Le plancher ne peut pas dépasser le plafond de rotation.';
        }
        if ($nom === 'rotation_plafond' && $valeur < $tous['rotation_plancher']) {
            return 'Le plafond ne peut pas être sous le plancher de rotation.';
        }
        $avant = $tous[$nom];
        DB::table('relais_meta')->updateOrInsert(['k' => self::cle($nom)], ['v' => (string) $valeur]);
        DB::table('relais_audit')->insert(['quand' => (int) (microtime(true) * 1000), 'acteur' => $acteur, 'action' => 'reglage_sauvegarde', 'detail' => $nom.' : '.$avant.' → '.$valeur]);

        return null;
    }
}
