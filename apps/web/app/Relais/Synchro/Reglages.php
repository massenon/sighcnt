<?php

namespace App\Relais\Synchro;

use App\Relais\Format;
use Illuminate\Support\Facades\DB;

/**
 * LES RÉGLAGES DE L'ÉCRAN « SYNCHRONISATION » : enregistrés EN BASE (`relais_meta`, clés `reglage.synchro.*`), jamais une constante du code, avec un défaut semé par la migration, modifiables
 * par le superadmin dans les paramètres du panneau, BORNÉS (plancher et plafond dits, jamais une valeur hors borne enregistrée). Toutes les valeurs par défaut sont des PROPOSITIONS
 * « à valider » par la Direction (DECISIONS-A-VALIDER.md, section U). Chaque changement est journalisé (ancienne et nouvelle valeur, RG-12).
 *
 * Le tableau DEFAUTS est la seule description : la migration en sème les lignes, l'écran des paramètres en tire ses champs et ses bornes, la lecture borne ce qu'elle trouve.
 */
class Reglages
{
    /** @var array<string, array{defaut: int, min: int, max: int, unite: string, libelle: string}> */
    public const DEFAUTS = [
        'conservation_jours' => ['defaut' => 90, 'min' => 30, 'max' => 365, 'unite' => 'jours', 'libelle' => 'Durée de conservation de l’historique'],
        'echantillon_minutes' => ['defaut' => 10, 'min' => 1, 'max' => 60, 'unite' => 'min', 'libelle' => 'Intervalle entre deux relevés de l’historique'],
        'mere_en_retard_min' => ['defaut' => 2, 'min' => 1, 'max' => 120, 'unite' => 'min', 'libelle' => 'Mère en retard au-delà de'],
        'mere_silencieuse_min' => ['defaut' => 5, 'min' => 2, 'max' => 1440, 'unite' => 'min', 'libelle' => 'Mère silencieuse au-delà de'],
        'fileul_en_retard_min' => ['defaut' => 30, 'min' => 5, 'max' => 1440, 'unite' => 'min', 'libelle' => 'Fileul en retard au-delà de'],
        'fileul_silencieux_min' => ['defaut' => 240, 'min' => 10, 'max' => 10080, 'unite' => 'min', 'libelle' => 'Fileul silencieux au-delà de'],
        'fileul_retard_journal' => ['defaut' => 500, 'min' => 10, 'max' => 100000, 'unite' => 'opérations', 'libelle' => 'Fileul en retard au-delà de (journal)'],
        'mobile_en_retard_min' => ['defaut' => 720, 'min' => 30, 'max' => 10080, 'unite' => 'min', 'libelle' => 'Mobile en retard au-delà de'],
        'mobile_silencieux_min' => ['defaut' => 2880, 'min' => 60, 'max' => 43200, 'unite' => 'min', 'libelle' => 'Mobile silencieux au-delà de'],
        'boite_enveloppes_max' => ['defaut' => 200, 'min' => 10, 'max' => 100000, 'unite' => 'enveloppes', 'libelle' => 'Boîte qui grossit au-delà de'],
    ];

    /** Les paires « en retard < silencieux » : un seuil de silence plus court que celui du retard rendrait l’état « en retard » inatteignable. */
    public const ORDRES = [
        ['mere_en_retard_min', 'mere_silencieuse_min'],
        ['fileul_en_retard_min', 'fileul_silencieux_min'],
        ['mobile_en_retard_min', 'mobile_silencieux_min'],
    ];

    public static function cle(string $nom): string
    {
        return 'reglage.synchro.'.$nom;
    }

    /** Sème les défauts SANS écraser une valeur déjà posée (rejouable). */
    public static function semer(): void
    {
        foreach (self::DEFAUTS as $nom => $d) {
            DB::table('relais_meta')->insertOrIgnore(['k' => self::cle($nom), 'v' => (string) $d['defaut']]);
        }
    }

    /** Toutes les valeurs en vigueur : celles de la base, ramenées dans leurs bornes ; à défaut, le défaut. */
    public static function toutes(): array
    {
        $lues = DB::table('relais_meta')->where('k', 'like', 'reglage.synchro.%')->pluck('v', 'k');
        $out = [];
        foreach (self::DEFAUTS as $nom => $d) {
            $v = $lues[self::cle($nom)] ?? null;
            $n = is_numeric($v) ? (int) $v : $d['defaut'];
            $out[$nom] = max($d['min'], min($d['max'], $n));
        }

        return $out;
    }

    public static function valeur(string $nom): int
    {
        return self::toutes()[$nom];
    }

    /**
     * Enregistre un lot de valeurs, TOUT OU RIEN. Rend la liste des refus nommés (clé, motif, geste) ; vide si tout est enregistré.
     *
     * @param  array<string, mixed>  $valeurs
     * @return list<array{cle: string, motif: string, geste: string}>
     */
    public static function poser(array $valeurs, string $acteur): array
    {
        $refus = [];
        $apres = self::toutes();
        foreach ($valeurs as $nom => $v) {
            $d = self::DEFAUTS[$nom] ?? null;
            if ($d === null) {
                $refus[] = ['cle' => (string) $nom, 'motif' => 'Réglage inconnu.', 'geste' => 'Utiliser un des réglages listés.'];

                continue;
            }
            if (is_string($v) && preg_match('/^\s*\d+\s*$/', $v)) {
                $v = (int) $v;
            }
            if (! is_int($v)) {
                $refus[] = ['cle' => $nom, 'motif' => $d['libelle'].' : un nombre entier est attendu.', 'geste' => 'Saisir un entier en '.$d['unite'].'.'];

                continue;
            }
            if ($v < $d['min'] || $v > $d['max']) {
                $refus[] = ['cle' => $nom, 'motif' => $d['libelle'].' : '.$v.' '.$d['unite'].' est hors des bornes ('.$d['min'].' à '.$d['max'].').', 'geste' => 'Saisir une valeur de '.$d['min'].' à '.$d['max'].' '.$d['unite'].'.'];

                continue;
            }
            $apres[$nom] = $v;
        }
        if ($refus === []) {
            foreach (self::ORDRES as [$court, $long]) {
                if ($apres[$court] >= $apres[$long]) {
                    $refus[] = ['cle' => $long, 'motif' => self::DEFAUTS[$long]['libelle'].' doit dépasser '.mb_strtolower(self::DEFAUTS[$court]['libelle']).' ('.$apres[$court].' '.self::DEFAUTS[$court]['unite'].').',
                        'geste' => 'Choisir un seuil de silence supérieur au seuil de retard.'];
                }
            }
        }
        if ($refus !== []) {
            return $refus;
        }
        $avant = self::toutes();
        foreach ($valeurs as $nom => $_) {
            if ($apres[$nom] === $avant[$nom]) {
                continue;
            }
            DB::table('relais_meta')->updateOrInsert(['k' => self::cle($nom)], ['v' => (string) $apres[$nom]]);
            DB::table('relais_audit')->insert(['quand' => Format::maintenant(), 'acteur' => $acteur, 'action' => 'reglage_synchro', 'detail' => $nom.' : '.$avant[$nom].' → '.$apres[$nom]]);
        }

        return [];
    }
}
