import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reglages_poste_test.dart' show controleur, monter, ouvrirPoste, remplir;

/// cfg-poste : l'activation du mode mère est testée de bout en bout par `reglages_poste_test.dart` (relais, atomicité, refus nommés). Ici, ce que l'écran de
/// la MAQUETTE ajoute et que le poste reprend : les deux indicateurs (mode, service de synchronisation), la note de ce que l'activation exige, et la note
/// de ce qu'elle ouvre.
void main() {
  testWidgets('fileul : « Mode de ce poste » Fileul, « Service de synchronisation » Arrêté, la note dit où et avec quoi activer', (t) async {
    await monter(t, controleur());
    await ouvrirPoste(t);
    expect(find.text('Mode de ce poste'), findsOneWidget);
    expect(find.text('Fileul'), findsOneWidget);
    expect(find.text('Service de synchronisation'), findsOneWidget);
    expect(find.text('Arrêté'), findsOneWidget);
    expect(find.text('À faire sur le serveur local uniquement. Exige l’adresse du relais, le secret de la mère et la clé de clinique.'), findsOneWidget);
    expect(find.text('Ce poste est un poste fileul'), findsOneWidget);
    expect(find.text('Mode du poste : fileul ou mère. La mère est le même logiciel avec ses modules complémentaires (synchronisation, supervision, sauvegardes).'), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('mère après activation : les indicateurs passent à Mère / En marche et la note annonce les modules « Poste mère »', (t) async {
    final c = controleur();
    await monter(t, c);
    await ouvrirPoste(t);
    await remplir(t);
    await t.ensureVisible(find.byKey(const Key('activer')));
    await t.tap(find.byKey(const Key('activer')));
    await t.pumpAndSettle();
    // la coque se recompose en mode mère : on rouvre l'écran, comme le fait l'agent
    if (find.text('Mode de ce poste').evaluate().isEmpty) await ouvrirPoste(t);
    expect(find.text('Mère'), findsOneWidget);
    expect(find.text('En marche'), findsOneWidget);
    expect(find.text('Les modules du groupe Poste mère sont maintenant disponibles pour l’administrateur et la DAF.'), findsOneWidget);
    expect(find.byKey(const Key('activer')), findsNothing);
    await t.pump(const Duration(seconds: 10));
  });
}
