// LOT 8 : la régularisation d'une feuille d'inventaire IMPORTÉE, rejouée sur les vecteurs de la maquette (`import.json`, section `stock`, tirés de l'écran réel par
// `prototype_html/build/vecteurs-import.js` : `PR.regulariserInventaire(feuille, {strict: true})`). L'import crée la feuille et ne touche à aucun stock ; ici, un mouvement par écart sur le
// magasin compté, REFUSÉ en nommant l'article si le stock a bougé depuis le comptage.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

void main() {
  final V = lireVecteurs('import');
  final S = (V['stock'] as Map).cast<String, Object?>();
  List<Map<String, Object?>> produits() => [for (final p in liste((V['magasin'] as Map)['produits'])) {...p}];
  final feuilles = liste(S['feuilles']);
  Map<String, Object?> feuille(String magasin) => feuilles.firstWhere((f) => f['magasin'] == magasin);
  Map<String, Object?> stocks(List<Map<String, Object?>> ps, List<String> codes) => {
        for (final c in codes)
          c: {
            for (final k in ['stock', 'stockGros', 'stockDetail']) k: ps.firstWhere((p) => p['code'] == c)[k]
          }
      };

  test('le stock a bougé depuis le comptage : REGULARISATION_PERIMEE, nommée, rien n\'est écrit', () {
    final ps = produits();
    ps.firstWhere((p) => p['code'] == 'AMOXI')['stockGros'] = 31;
    final r = regulariserInventaireImporte(inventaire: feuille('gros'), produits: ps, mouvements: const [], operateur: 'ADMIN TEST');
    final att = (S['regularisationPerimee'] as Map).cast<String, Object?>();
    expect(r.ok, att['ok']);
    expect(r.code, att['code']);
    expect(r.motif, att['motif']);
    expect(r.geste, att['geste']);
    expect(r.mouvements, isEmpty);
    expect(r.produits, isEmpty);
  });

  test('un mouvement par écart sur le magasin compté, le total qui suit, et l\'état d\'avant pour l\'annulation', () {
    final ps = produits();
    final att = (S['regularisation'] as Map).cast<String, Object?>();
    final premiere = liste(att['mouvements']).first['reference'] as String;
    final rang = int.parse(premiere.substring(1));
    final r = regulariserInventaireImporte(
        inventaire: feuille('gros'), produits: ps, mouvements: [{'reference': 'M${(rang - 1).toString().padLeft(6, '0')}'}], operateur: 'ADMIN TEST');
    expect(r.ok, att['ok']);
    expect(r.mouvements.length, att['nb']);
    memes(r.mouvements, att['mouvements'], 'mouvements', ignorer: {'statut'});
    for (final p in r.produits) {
      ps.firstWhere((x) => x['id'] == p.id).addAll(p.patch);
    }
    memes(stocks(ps, ['AMOXI', 'COTON']), att['stocks'], 'stocks');
    expect(r.avant.single.patch, {'stockGros': 30, 'stockDetail': 0, 'stock': 30}, reason: 'l\'annulation restitue l\'état d\'avant');
  });

  test('un article qui n\'existe plus : PRODUIT_INCONNU ; un stock qui deviendrait négatif : RG03_STOCK_NEGATIF', () {
    final inconnu = regulariserInventaireImporte(inventaire: feuille('gros'), produits: [for (final p in produits()) if (p['code'] != 'AMOXI') p], mouvements: const [], operateur: 'X');
    expect(inconnu.code, 'PRODUIT_INCONNU');
    final f = {...feuille('gros')};
    f['lignes'] = [
      {...liste(f['lignes']).first, 'ecart': -40, 'theorique': 30}
    ];
    final neg = regulariserInventaireImporte(inventaire: f, produits: produits(), mouvements: const [], operateur: 'X');
    expect(neg.code, 'RG03_STOCK_NEGATIF');
    expect(neg.motif, contains('AMOXICILLINE'));
    expect(neg.geste, isNotEmpty);
  });

  test('une ligne sans écart ne produit aucun mouvement', () {
    final f = {...feuille('gros')};
    f['lignes'] = [
      {...liste(f['lignes']).last}
    ];
    final r = regulariserInventaireImporte(inventaire: f, produits: produits(), mouvements: const [], operateur: 'X');
    expect(r.ok, isTrue);
    expect(r.mouvements, isEmpty);
  });
}
