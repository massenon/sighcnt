<?php

namespace App\Relais\Synchro;

/**
 * LA LISTE BLANCHE DES INDICATEURS DE SYNCHRONISATION (lot RLS-SYNC, décision de la Direction du 13/11/2026) : la mère publie, dans ses indicateurs de battement, un tableau `fileuls` de
 * COMPTEURS ET D'HORODATAGES. Jamais un identifiant de patient, un nom de personne, un libellé de pièce ni un motif. Le relais est opaque : il REFUSE en nommant (code, motif, geste, chemin
 * de la valeur, jamais la valeur recopiée) tout ce qui sort de la liste, et n'enregistre RIEN d'un envoi refusé.
 *
 * Une seule règle, quatre lecteurs : packages/domaine/lib/src/mere/synchro_fileuls.dart (la mère Dart OMET), packages/sync/banc/synchro.js (la mère et le relais de référence), ce fichier.
 * Les vecteurs sont communs : packages/domaine/test/vecteurs/synchro_fileuls.json (tests/Feature/Synchro/ListeBlancheTest.php). Le relais ne juge pas un contenu métier : il vérifie la FORME
 * d'un envoi, comme il vérifie celle d'une enveloppe.
 */
class ListeBlanche
{
    public const MAX = 200;

    public const CLES = ['poste', 'dernierContact', 'retardJournal', 'conflitsOuverts', 'demandesImportEnAttente'];

    public const NULLABLES = ['dernierContact', 'retardJournal'];

    /** Nom technique d'un poste : 40 caractères, lettres (accentuées comprises), chiffres, espace, point, deux-points, tiret, tiret bas. `\z` : pas de saut de ligne final toléré. */
    public const POSTE = '/^[A-Za-z0-9\x{00C0}-\x{00FF}][A-Za-z0-9\x{00C0}-\x{00FF} _.:-]{0,39}\z/u';

    private const CLE_SURE = '/^[a-z][A-Za-z0-9_]{0,39}\z/';

    private static function refus(string $code, string $motif, string $geste, string $chemin): array
    {
        return ['code' => $code, 'motif' => $motif, 'geste' => $geste, 'chemin' => $chemin];
    }

    private static function entier(mixed $v): bool
    {
        return is_int($v) && $v >= 0;
    }

    public static function posteValide(mixed $poste): bool
    {
        return is_string($poste) && preg_match(self::POSTE, $poste) === 1;
    }

    /**
     * Vérifie la partie « synchronisation » d'un envoi d'indicateurs (`fileuls` et `protocole`) ; les autres clés ne sont pas jugées ici.
     *
     * @return array{code: string, motif: string, geste: string, chemin: string}|null null si tout est permis, sinon le PREMIER refus
     */
    public static function verifier(array $indicateurs): ?array
    {
        if (array_key_exists('protocole', $indicateurs)) {
            $p = $indicateurs['protocole'];
            if (! is_int($p) || $p < 1 || $p > 9999) {
                return self::refus('indicateur_valeur_invalide', 'La version du protocole est un entier de 1 à 9999.', 'Publier un entier, ou ne rien publier.', 'protocole');
            }
        }
        if (! array_key_exists('fileuls', $indicateurs)) {
            return null;
        }
        $liste = $indicateurs['fileuls'];
        if (! is_array($liste) || ! array_is_list($liste) || count($liste) > self::MAX) {
            return self::refus('indicateur_forme_invalide', 'fileuls doit être une liste de '.self::MAX.' éléments au plus.', 'Publier un tableau d\'objets de cinq clés permises.', 'fileuls');
        }
        foreach ($liste as $i => $f) {
            if (! is_array($f) || ($f !== [] && array_is_list($f))) {
                return self::refus('indicateur_forme_invalide', 'Chaque élément de fileuls doit être un objet.', 'Publier un objet par fileul.', "fileuls[$i]");
            }
            foreach (array_keys($f) as $cle) {
                if (! in_array($cle, self::CLES, true)) {
                    $sure = is_string($cle) && preg_match(self::CLE_SURE, $cle) === 1;
                    $nom = $sure ? $cle : '(cle non conforme)';

                    return self::refus('indicateur_cle_inconnue', 'La clé « '.($sure ? $cle : 'non conforme').' » n\'est pas permise : seuls un nom de poste, des compteurs et des horodatages sont publiés.',
                        'Retirer la clé ; les clés permises sont '.implode(', ', self::CLES).'.', "fileuls[$i].$nom");
                }
            }
            if (! self::posteValide($f['poste'] ?? null)) {
                return self::refus('indicateur_valeur_invalide', 'Le nom du poste est absent ou n\'est pas un nom technique (40 caractères, lettres, chiffres, espace, point, deux-points, tiret).',
                    'Publier l\'étiquette de l\'appairage du poste.', "fileuls[$i].poste");
            }
            foreach (array_slice(self::CLES, 1) as $cle) {
                if (! array_key_exists($cle, $f)) {
                    continue;
                }
                $v = $f[$cle];
                if ($v === null && in_array($cle, self::NULLABLES, true)) {
                    continue;
                }
                if (! self::entier($v)) {
                    return self::refus('indicateur_valeur_invalide', 'La valeur de '.$cle.' doit être un entier positif ou nul'.(in_array($cle, self::NULLABLES, true) ? ' (ou null quand elle n\'est pas calculable)' : '').'.',
                        'Publier un compteur numérique.', "fileuls[$i].$cle");
                }
            }
        }

        return null;
    }
}
