<?php

namespace App\Relais;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

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

    /** Lot RLS-SYNC : les SEULES colonnes de l'historique de synchronisation. Des horodatages et des compteurs, plus la référence de l'appareil. */
    public const COLONNES_SYNCHRO = ['id', 'quand', 'nature', 'ref', 'dernier_contact', 'retard_journal', 'conflits', 'demandes', 'attente'];

    /**
     * Lot RLS-SYNC : l'historique de synchronisation ne détient aucun contenu. Deux mesures : (1) la table n'a que les colonnes numériques et la référence listées ci-dessus (une colonne ajoutée
     * un jour, `libelle` ou `motif`, serait signalée) ; (2) chaque `ref` est un nom technique de poste, « mere » ou l'identifiant d'un appareil appairé : une valeur qui ressemble à un
     * dossier ou à une phrase est comptée. La mesure ne peut pas distinguer un nom de personne d'un nom de poste : elle prouve la FORME, pas l'intention.
     *
     * @return array{lignes: int, colonnes_hors_liste: list<string>, refs_hors_liste: int}
     */
    public static function historiqueSynchro(): array
    {
        $colonnes = array_values(array_diff(Schema::getColumnListing('relais_synchro_historique'), self::COLONNES_SYNCHRO));
        $hors = 0;
        foreach (DB::table('relais_synchro_historique')->distinct()->pluck('ref') as $ref) {
            if (! preg_match('/^[A-Za-z0-9\x{00C0}-\x{00FF}][A-Za-z0-9\x{00C0}-\x{00FF} _.:-]{0,63}\z/u', (string) $ref)) {
                $hors++;
            }
        }

        return ['lignes' => (int) DB::table('relais_synchro_historique')->count(), 'colonnes_hors_liste' => $colonnes, 'refs_hors_liste' => $hors];
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
