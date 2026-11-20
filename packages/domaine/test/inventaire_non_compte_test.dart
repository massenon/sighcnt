import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

/// LOT INVENT-NC (décision 12 de la Direction du 15/11/2026) : un article NON COMPTÉ est enregistré « non compté » sur la ligne d'inventaire, distinct de
/// « compté, écart zéro » ; son stock n'est jamais touché (RG-03) ; la validation reste possible. Les vecteurs de l'écran réel (`stock_mouvements.json`,
/// cas « non compté ») sont rejoués par `mouvements_stock_test.dart` ; ici les invariants, cas par cas.
Map<String, Object?> produit(String id, num gros, {num detail = 0, num cump = 100}) =>
    {'id': id, 'code': 'C$id', 'designation': 'Article $id', 'unite': 'Boîte', 'stockGros': gros, 'stockDetail': detail, 'stock': gros + detail, 'cump': cump, 'categorie': 'medicament'};

InventaireValide valider(List<Map<String, Object?>> cible, Map<String, Object?> physiques) => validerInventaire(
    entete: {'magasin': 'gros', 'type': 'Mensuel', 'date': '2026-11-16', 'perimetre': 'Tous les articles', 'operateur': 'Testeur'},
    cible: cible,
    physiques: physiques,
    inventaires: const [],
    mouvements: const []);

List<Map<String, Object?>> lignes(InventaireValide v) => [for (final l in (v.inventaire['lignes'] as List)) (l as Map).cast<String, Object?>()];

void main() {
  final a = produit('A', 20), b = produit('B', 5), c = produit('C', 12);

  test('rien de saisi : toutes les lignes sont « non compté », aucun écart, aucun mouvement, aucun stock touché ; la validation passe', () {
    final v = valider([a, b, c], const {});
    expect(v.inventaire['nbArticles'], 3);
    expect(v.inventaire['nbComptes'], 0);
    expect(v.inventaire['nbNonComptes'], 3);
    expect(v.inventaire['nbEcarts'], 0);
    expect(v.mouvements, isEmpty);
    expect(v.produits, isEmpty, reason: 'RG-03 : aucun stock modifié pour un non compté');
    for (final l in lignes(v)) {
      expect(l['nonCompte'], true);
      expect(l.containsKey('physique'), isFalse, reason: 'un non compté ne porte aucun physique (jamais le théorique recopié)');
      expect(l.containsKey('ecart'), isFalse);
      expect(l.containsKey('valeur'), isFalse);
      expect(l['theorique'], isNotNull);
    }
  });

  test('compté juste n\'est pas non compté : écart zéro ENREGISTRÉ comme un comptage ; une saisie vide reste non comptée ; compter 0 est un comptage', () {
    final v = valider([a, b, c], {'A': 20, 'B': '  ', 'C': 0});
    final l = {for (final x in lignes(v)) x['code']: x};
    expect(l['CA']!['nonCompte'], isNull);
    expect(l['CA']!['physique'], 20);
    expect(l['CA']!['ecart'], 0);
    expect(l['CB']!['nonCompte'], true, reason: 'une saisie vide est un non compté');
    expect(l['CC']!['physique'], 0);
    expect(l['CC']!['ecart'], -12, reason: 'compter 0 est un comptage : écart régularisé');
    expect(v.inventaire['nbComptes'], 2);
    expect(v.inventaire['nbNonComptes'], 1);
    expect(v.inventaire['nbEcarts'], 1);
    expect(v.mouvements.single['produitId'], 'C');
    expect([for (final p in v.produits) p.id], ['C'], reason: 'seul l\'article compté avec écart est régularisé');
  });

  test('la régularisation d\'une feuille ne touche jamais une ligne non comptée, même si elle portait un écart (défense en profondeur)', () {
    final r = regulariserInventaireImporte(inventaire: {
      'reference': 'INV-0009',
      'date': '2026-11-16',
      'magasin': 'gros',
      'lignes': [
        {'produitId': 'A', 'designation': 'Article A', 'theorique': 20, 'nonCompte': true, 'ecart': -20},
        {'produitId': 'B', 'designation': 'Article B', 'theorique': 5, 'physique': 7, 'ecart': 2},
      ],
    }, produits: [a, b], mouvements: const [], operateur: 'Testeur');
    expect(r.ok, isTrue);
    expect([for (final m in r.mouvements) m['produitId']], ['B']);
  });
}
