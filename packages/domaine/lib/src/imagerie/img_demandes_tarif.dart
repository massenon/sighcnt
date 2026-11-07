/// Le prix d'un examen d'imagerie — port de `D.tarifPrix(code, assure)` (`data-tarifs.js`), rejoué sur TOUT le catalogue tarifaire de la maquette.
///
/// RG-09 : le prix applicable dépend d'une seule question — la carte est-elle valide à la date de facturation ? Elle ne dépend PAS du fait que
/// le patient possède une carte. Trois états dans la colonne assurée : un montant · NON COUVERT (l'assuré paie le tarif non assuré, motif à
/// l'appui) · une valeur manquante (`null`), qui n'est ni un zéro ni une exclusion et BLOQUE la facturation.
library;

import 'img_demandes_ouverture.dart' show PrixImagerie;

/// [entree] : une ligne du catalogue tarifaire (`prixNonAssure`, `prixAssure`, `nonCouvert`, `assurable` ∈ {true, false, 'sos'}) ; `null` si
/// le code est absent du catalogue.
PrixImagerie prixTarif(Map<String, Object?>? entree, bool assure) {
  if (entree == null) {
    return const PrixImagerie(null, 'Acte absent du catalogue tarifaire.');
  }
  final nonAssure = entree['prixNonAssure'] as num?;
  if (!assure) return PrixImagerie(nonAssure);
  if (entree['assurable'] == false || entree['nonCouvert'] == true) {
    return PrixImagerie(nonAssure,
        'Acte NON COUVERT par les assurances — facturé au patient au tarif non assuré.');
  }
  if (entree['assurable'] == 'sos') {
    return PrixImagerie(nonAssure,
        'Les certificats ne sont couverts que par SOS — vérifier la compagnie.');
  }
  return PrixImagerie(entree['prixAssure'] as num?);
}
