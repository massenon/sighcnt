import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'dash_aide.dart';

/// `dash-stock` : comparé au relevé de l'écran réel ; un seuil NON FIXÉ n'est pas un seuil de zéro.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);
  final v = obj(vecteurs()['dash-stock']);

  testWidgets('relevé de la maquette : alertes, premier regard, indicateurs, mouvements, parcours', (t) async {
    await ouvrir(t, magasin(), 'dash-stock', role: 'stock');
    comparer(t, v);
    // Le bandeau d'alertes précède le premier regard.
    expect(t.getTopLeft(find.byKey(const Key('tba:alerte:m6-alertes'))).dy, lessThan(t.getTopLeft(find.byKey(const Key('tba:premier-regard'))).dy));
    await finir(t);
  });

  testWidgets('sans aucune alerte : pas de bandeau, premier regard à la phrase positive', (t) async {
    final m = magasin();
    for (final p in m.collection('produits').actives.toList()) {
      m.collection('produits').mettreAJour(p['id'], {'stock': 100000});
    }
    for (final l in m.collection('lots').actives.toList()) {
      m.collection('lots').mettreAJour(l['id'], {'statut': 'actif'});
    }
    await ouvrir(t, m, 'dash-stock', role: 'stock');
    expect(find.byKey(const Key('tba:alerte:m6-alertes')), findsNothing);
    expect(find.text('Aucun article sous son seuil d’alerte.'), findsOneWidget);
    expect(kpis(t).last, ('Alertes actives', '0'));
    await finir(t);
  });

  testWidgets('un article sans seuil fixé n\'est pas compté comme « sous le seuil »', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'dash-stock', role: 'stock');
    expect(find.text('Aucun article sous son seuil d’alerte.'), findsNothing, reason: 'le jeu a des articles sous leur seuil');
    // Les articles dont le seuil est retiré sortent du premier regard : un seuil non fixé ne compare rien (il ne vaut pas zéro).
    for (final x in m.collection('produits').actives.toList()) {
      m.collection('produits').mettreAJour(x['id'], {'seuilAlerte': null});
    }
    await ouvrir(t, m, 'dash-stock', role: 'stock');
    expect(find.text('Aucun article sous son seuil d’alerte.'), findsOneWidget);
    await finir(t);
  });
}
