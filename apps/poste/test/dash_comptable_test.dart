import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'dash_aide.dart';

/// `dash-comptable` : comparé au relevé de l'écran réel ; l'équilibre RG-10 se lit, une pièce déséquilibrée se DIT.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);
  final v = obj(vecteurs()['dash-comptable']);

  testWidgets('relevé de la maquette : brouillons, équilibre, dernières écritures, parcours', (t) async {
    await ouvrir(t, magasin(), 'dash-comptable', role: 'comptable');
    comparer(t, v);
    expect(find.text('Débit = Crédit'), findsOneWidget);
    await finir(t);
  });

  testWidgets('une écriture déséquilibrée remplace « Équilibré » par l\'écart à régulariser', (t) async {
    final m = magasin();
    m.collection('ecritures').inserer({
      'numero': 'OD-TEST-1',
      'date': '2026-08-16',
      'journal': 'OD',
      'compte': '571000',
      'libelle': 'Pièce bancale',
      'debit': 1234,
      'credit': 0,
      'statut': 'brouillon'
    });
    await ouvrir(t, m, 'dash-comptable', role: 'comptable');
    expect(kpis(t).last, ('Équilibre (RG-10)', '1 234 FCFA'));
    expect(find.text('Écart à régulariser'), findsOneWidget);
    expect(find.text('Débit = Crédit'), findsNothing);
    await finir(t);
  });

  testWidgets('sans brouillon : la phrase positive remplace le compte', (t) async {
    final m = magasin();
    for (final e in m.collection('ecritures').actives.toList()) {
      m.collection('ecritures').mettreAJour(e['id'], {'statut': 'valide', 'etat': 'valide'});
    }
    await ouvrir(t, m, 'dash-comptable', role: 'comptable');
    expect(find.text('Aucune écriture en attente de validation.'), findsOneWidget);
    await finir(t);
  });
}
