import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'dash_aide.dart';

/// `dash-pharmacien` : comparé au relevé de l'écran réel. Le compte est fermé (archivé) : l'écran est ouvert ici sous l'administrateur, qui y a accès.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);
  final v = obj(vecteurs()['dash-pharmacien']);

  testWidgets('relevé de la maquette : compte fermé dit, file des ordonnances, alertes, indicateurs, produits à réapprovisionner', (t) async {
    await ouvrir(t, magasin(), 'dash-pharmacien');
    comparer(t, v);
    // Le bandeau d'alertes précède la file : trois pastilles cliquables (ruptures, périmés, péremption proche).
    expect(find.byKey(const Key('tba:alerte:m6-alertes')), findsOneWidget);
    expect(find.byKey(const Key('tba:alerte:m6-lots')), findsNWidgets(2));
    await finir(t);
  });

  testWidgets('un compte fermé n\'offre aucun lien dans le premier regard (la phrase suffit)', (t) async {
    await ouvrir(t, magasin(), 'dash-pharmacien');
    expect(find.text('Le compte Pharmacie a été fermé — la pharmacie est tenue par la caisse.'), findsOneWidget);
    expect(find.text('Y aller'), findsNothing);
    await finir(t);
  });

  testWidgets('sans produit sous le seuil : l\'état vide remplace le tableau', (t) async {
    final m = magasin();
    for (final p in m.collection('produits').actives.toList()) {
      m.collection('produits').mettreAJour(p['id'], {'stock': 10000, 'stockGros': 10000});
    }
    await ouvrir(t, m, 'dash-pharmacien');
    expect(find.text('Aucun produit sous le seuil d’alerte.'), findsOneWidget);
    await finir(t);
  });
}
