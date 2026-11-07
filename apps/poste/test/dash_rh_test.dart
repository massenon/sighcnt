import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'dash_aide.dart';

/// `dash-rh` : comparé au relevé de l'écran réel. Le compte RH est archivé : l'écran est ouvert sous l'administrateur.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);
  final v = obj(vecteurs()['dash-rh']);

  testWidgets('relevé de la maquette : compte fermé dit, indicateurs, effectif par fonction', (t) async {
    await ouvrir(t, magasin(), 'dash-rh');
    comparer(t, v);
    expect(find.text('Le compte RH a été fermé — les ressources humaines relèvent de la DAF.'), findsOneWidget);
    expect(find.text('Y aller'), findsNothing, reason: 'un compte fermé n\'offre aucun lien');
    await finir(t);
  });

  testWidgets('l\'effectif se recompte : un agent de plus, un agent de plus au total et à la masse salariale', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'dash-rh');
    final avant = {for (final k in kpis(t)) k.$1: k.$2};
    m.collection('personnel').inserer({'nom': 'TEST', 'prenom': 'Dash', 'fonction': 'infirmier', 'service': 'Direction', 'salaireBase': 100000, 'statut': 'actif'});
    await t.pump(const Duration(milliseconds: 300));
    final apres = {for (final k in kpis(t)) k.$1: k.$2};
    expect(int.parse(apres['Effectif total']!), int.parse(avant['Effectif total']!) + 1);
    expect(apres['Masse salariale (base)'], isNot(avant['Masse salariale (base)']));
    await finir(t);
  });
}
