import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/shell/choix_exercice.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// Le sélecteur d'exercice de la barre supérieure (arbitrage du 05/11/2026) : seulement sur les écrans « à année », choix tenu en session, flèches absentes aux bornes.
void main() {
  setUpAll(chargerPolices);

  casM14('présent sur un écran à année, avec l\'exercice ouvert le plus récent ; flèche suivante ABSENTE à la borne', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm12-balance');
    expect(find.byKey(const Key('selecteur-exercice')), findsOneWidget);
    expect(find.text('Exercice 2026 · ouvert'), findsOneWidget);
    expect(find.byKey(const Key('exercice-precedent')), findsOneWidget);
    expect(find.byKey(const Key('exercice-suivant')), findsNothing, reason: 'pas d\'exercice après le dernier : la flèche est absente, non grisée');
  });

  casM14('choisir l\'exercice précédent change l\'affichage, tient pour la session, et se lit dans la lecture de l\'écran', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm12-balance');
    await toucherM14(t, find.byKey(const Key('exercice-precedent')));
    expect(find.text('Exercice 2025 · clos'), findsOneWidget);
    expect(ChoixExercice.valeur.value, 2025);
    expect(find.byKey(const Key('exercice-suivant')), findsOneWidget);
    await toucherM14(t, find.byKey(const Key('exercice-precedent')));
    expect(find.text('Exercice 2024 · clos'), findsOneWidget, reason: 'les deux exercices de la liasse déposée existent');
    expect(find.byKey(const Key('exercice-precedent')), findsNothing, reason: 'premier exercice connu : flèche absente');
    await t.pump(const Duration(seconds: 10));
  });

  casM14('ABSENT des écrans du jour et des tableaux de bord de poste', (t) async {
    final m = magasinM14();
    for (final id in ['m8-caisse', 'dash-da', 'm12-ouverture']) {
      await ouvrirM14(t, m, id);
      expect(find.byKey(const Key('selecteur-exercice')), findsNothing, reason: id);
    }
  });
}
