/// Référentiels STATIQUES du stock (`D.CATEGORIES_PRODUIT`, `D.TYPES_STOCK`, `D.TYPES_MOUVEMENT` de `data.js`) : ce ne sont pas des collections du
/// magasin, le jeu du poste ne les porte pas. Ils sont recopiés ici et GARDÉS par `test/stock_test.dart`, qui les compare à ceux que la maquette
/// a exportés dans `test/vecteurs/stock.json`.
library;

class CategorieProduit {
  const CategorieProduit(this.id, this.label);
  final String id;
  final String label;
}

const categoriesProduit = [
  CategorieProduit('medicament', 'Médicaments'),
  CategorieProduit('reactif', 'Réactifs de laboratoire'),
  CategorieProduit('conso_labo', 'Consommables de laboratoire'),
  CategorieProduit('conso_medical', 'Consommables médicaux'),
  CategorieProduit('fourniture', 'Fournitures administratives'),
  CategorieProduit('entretien', 'Produits d’entretien'),
  CategorieProduit('petit_materiel', 'Petit matériel médical'),
  CategorieProduit('immobilisation', 'Immobilisations'),
];

class TypeMouvement {
  const TypeMouvement(this.id, this.label, this.badge);
  final String id;
  final String label;

  /// Teinte du badge : `success`, `navy`, `info`, `danger`, `warning`, `neutral`.
  final String badge;
}

const typesMouvement = [
  TypeMouvement('entree', 'Entrée', 'success'),
  TypeMouvement('sortie', 'Sortie', 'navy'),
  TypeMouvement('transfert', 'Transfert', 'info'),
  TypeMouvement('perte', 'Perte', 'danger'),
  TypeMouvement('casse', 'Casse / bris', 'danger'),
  TypeMouvement('peremption', 'Péremption', 'warning'),
  TypeMouvement('inventaire', 'Régularisation inventaire', 'neutral'),
];

class TypeStock {
  const TypeStock(this.id, this.label);
  final String id;
  final String label;
}

const typesStock = [
  TypeStock('gros', 'Stock gros (magasin central)'),
  TypeStock('detail', 'Stock détail (pharmacie d’urgence)'),
  TypeStock('labo', 'Stock laboratoire'),
];
