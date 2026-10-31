import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show Droit;
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/dash/tba_caissier.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';

import 'aide_polices.dart';
import 'dash_aide.dart';

/// `dash-caissier` : comparé au relevé de l'écran réel ; les encaissements du jour se recomptent sur les factures posées par le test.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);
  final v = obj(vecteurs()['dash-caissier']);

  testWidgets('relevé de la maquette : file à encaisser, premier regard, indicateurs, factures, parcours', (t) async {
    await ouvrir(t, magasin(), 'dash-caissier', role: 'caissier');
    comparer(t, v);
    await finir(t);
  });

  testWidgets('une facture du jour réglée en partie se recompte : encaissé, factures du jour, reliquat et impayées', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'dash-caissier', role: 'caissier');
    final avant = {for (final k in kpis(t)) k.$1: k.$2};
    m.collection('factures').inserer({
      'numero': 'FA-TEST-1',
      'date': '2026-08-16',
      'patient': 'TEST Dash',
      'type': 'Consultation',
      'montantTTC': 10000,
      'montantPaye': 4000,
      'reliquat': 6000,
      'statutPaiement': 'partielle',
      'modePaiement': 'especes'
    });
    await t.pump(const Duration(milliseconds: 300));
    final apres = {for (final k in kpis(t)) k.$1: k.$2};
    expect(apres['Factures du jour'], '${int.parse(avant['Factures du jour']!) + 1}');
    expect(sp(apres['Encaissé aujourd’hui']!), '4 000 FCFA');
    expect(find.text('FA-TEST-1'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Text && sp(w.data ?? '') == '6 000'), findsWidgets, reason: 'le reste dû s\'affiche sur la ligne');
    await finir(t);
  });

  testWidgets('« Nouvelle facture » est une écriture : absente d\'un profil qui ne peut pas ouvrir la facturation', (t) async {
    t.view.physicalSize = const Size(1600, 1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    Future<void> monter(bool Function(String) ouvre) async {
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: ContexteEcran(
                      ecranId: 'dash-caissier',
                      role: 'caissier',
                      droit: const Droit(voir: true, editer: false, annuler: false),
                      magasin: magasin(),
                      aller: (_) {},
                      horloge: () => aujourdhui,
                      ouvre: ouvre,
                      child: const EcranDashCaissier())))));
      await t.pump(const Duration(milliseconds: 300));
    }

    await monter((_) => true);
    expect(find.text('Nouvelle facture'), findsWidgets);
    await monter((id) => id != 'm8-facturation');
    expect(find.widgetWithText(BoutonSigh, 'Nouvelle facture'), findsNothing);
    expect(find.widgetWithText(BoutonSigh, 'État de caisse'), findsOneWidget);
    await finir(t);
  });
}
