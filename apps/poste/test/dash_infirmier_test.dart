import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'dash_aide.dart';

/// `dash-infirmier` : comparé au relevé de l'écran réel ; la règle de relais (administrations dues à la salle de soins) est comptée sur la file.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);
  final v = obj(vecteurs()['dash-infirmier']);

  testWidgets('relevé de la maquette : premier regard (administrations dues), indicateurs, hospitalisés, parcours', (t) async {
    await ouvrir(t, magasin(), 'dash-infirmier', role: 'infirmier');
    comparer(t, v);
    await finir(t);
  });

  testWidgets('sans patient hospitalisé : l\'état vide le dit, les lits sont tous libres', (t) async {
    final m = magasin();
    for (final a in m.collection('admissions').actives.toList()) {
      m.collection('admissions').archiver(a['id']);
    }
    await ouvrir(t, m, 'dash-infirmier', role: 'infirmier');
    expect(find.text('Aucun patient hospitalisé actuellement.'), findsOneWidget);
    expect(kpis(t).take(2).toList(), [('Patients hospitalisés', '0'), ('Lits libres', '19')]);
    await finir(t);
  });

  testWidgets('sans aucune administration due : le premier regard énonce sa phrase positive et n\'offre aucun lien', (t) async {
    final m = magasin();
    for (final p in m.collection('prescriptions').actives.toList()) {
      m.collection('prescriptions').archiver(p['id']);
    }
    await ouvrir(t, m, 'dash-infirmier', role: 'infirmier');
    expect(find.text('Aucune administration due à votre poste.'), findsOneWidget);
    expect(find.text('Salle de soins'), findsWidgets, reason: 'le bouton du parcours reste, pas celui du bandeau');
    await finir(t);
  });
}
