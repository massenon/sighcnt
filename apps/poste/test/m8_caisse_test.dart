import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// Paiements, reliquats, pro-forma : les gestes de la caisse. Encaisser refuse plus que le reste dû, l'annulation est visible, l'insolvabilité exige
/// un motif et n'efface jamais la créance, les commandes d'écriture sont ABSENTES sans le droit.
final donnees = DonneesNavigation.depuisDossier();
final aujourdhui = DateTime(2026, 10, 30);

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran,
    {String role = 'admin'}) async {
  t.view.physicalSize = const Size(1600, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: ecran,
      magasin: m,
      horloge: () => aujourdhui));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> toucher(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 300));
}

Magasin magasin() => Magasin.depuisDossier(Magasin.collectionsDuJeu);
Fiche aRegler(Magasin m) => (m
        .collection('factures')
        .actives
        .where((f) => (f['reliquat'] as num) > 0)
        .toList()
      ..sort((a, b) => '${b['date']}'.compareTo('${a['date']}')))
    .first;

void main() {
  setUpAll(chargerPolices);
  setUp(
      () => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  testWidgets(
      'paiements : les quatre KPI par mode sont recalculés depuis le magasin',
      (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm8-paiements');
    final f = m.collection('factures').actives;
    num pour(String mode) => f
        .where((x) => x['modePaiement'] == mode)
        .fold<num>(0, (a, r) => a + ((r['montantPaye'] as num?) ?? 0));
    final v = [
      for (final w
          in t.widgetList<Text>(find.byKey(const Key('kit:kpi-valeur'))))
        w.data
    ];
    expect(v, [
      money(pour('especes')),
      money(pour('tpe')),
      money(pour('mtn')),
      money(pour('moov'))
    ]);
  });

  testWidgets(
      'encaisser : plus que le reste dû est REFUSÉ en le disant, rien n’est écrit',
      (t) async {
    final m = magasin();
    final f = aRegler(m);
    final avant = f['montantPaye'];
    await ouvrir(t, m, 'm8-paiements');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Encaisser').first);
    expect(find.text('Encaissement'), findsOneWidget);
    await t.enterText(
        find.descendant(
            of: find.byKey(const Key('kit:champ:montant')),
            matching: find.byType(TextField)),
        '${(f['reliquat'] as num) + 1}');
    await toucher(t, find.text('Valider l’encaissement'));
    expect(find.textContaining('dépasse le reste dû'), findsOneWidget);
    expect(m.collection('factures').parId(f['id'])!['montantPaye'], avant);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets(
      'encaisser le reste solde la facture, l’annulation la rétablit et le dit ; le reçu s’ouvre',
      (t) async {
    final m = magasin();
    final avantTout = {
      for (final x in m.collection('factures').actives) x['id']: {...x}
    };
    await ouvrir(t, m, 'm8-paiements');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Encaisser').first);
    await toucher(t, find.text('Valider l’encaissement'));
    final changee = m
        .collection('factures')
        .actives
        .where((x) => x['reliquat'] != avantTout[x['id']]!['reliquat'])
        .toList();
    expect(changee.length, 1,
        reason: 'un seul encaissement, une seule facture touchée');
    final f = avantTout[changee.first['id']]!;
    final reste = f['reliquat'] as num;
    final apres = m.collection('factures').parId(f['id'])!;
    expect(apres['reliquat'], 0);
    expect(apres['statutPaiement'], 'soldee');
    expect(apres['montantPaye'], (f['montantPaye'] as num) + reste);
    expect(find.text('Reçu de paiement'), findsWidgets,
        reason: 'le reçu détaillé s’ouvre après l’encaissement');
    expect(find.textContaining('ENCAISSÉ CE JOUR'), findsOneWidget);
    expect(find.text('Facture soldée.'), findsOneWidget);
    // On ferme l'aperçu puis on annule.
    await toucher(t, find.text('Fermer').last);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Annuler').last);
    final retabli = m.collection('factures').parId(f['id'])!;
    expect(retabli['reliquat'], reste);
    expect(retabli.containsKey('dernierReglement'),
        f.containsKey('dernierReglement'));
    expect(find.text('Action annulée.'), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets(
      'RBAC : sans droit d’éditer (aide comptable), « Encaisser » est ABSENT',
      (t) async {
    await ouvrir(t, magasin(), 'm8-paiements', role: 'aide_comptable');
    expect(find.widgetWithText(BoutonSigh, 'Encaisser'), findsNothing);
  });

  testWidgets(
      'reliquats : ancienneté lue à l’horloge du poste, KPI et deux graphiques',
      (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm8-reliquats');
    final rows = m
        .collection('factures')
        .actives
        .where((f) => (f['reliquat'] as num) > 0)
        .toList();
    final total = rows.fold<num>(0, (a, r) => a + (r['reliquat'] as num));
    final v = [
      for (final w
          in t.widgetList<Text>(find.byKey(const Key('kit:kpi-valeur'))))
        w.data
    ];
    expect(v[0], nombre(rows.length));
    expect(v[1], money(total));
    expect(find.byKey(const Key('graphique:barres-h')), findsOneWidget);
    expect(find.byKey(const Key('graphique:anneau')), findsOneWidget);
    final f = (rows
          ..sort(
              (a, b) => (b['reliquat'] as num).compareTo(a['reliquat'] as num)))
        .first;
    final jours = aujourdhui.difference(DateTime.parse('${f['date']}')).inDays;
    expect(find.text('$jours j'), findsWidgets);
  });

  testWidgets(
      'insolvable : le motif est OBLIGATOIRE ; la créance reste due ; annulable',
      (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm8-reliquats');
    final premiere = (m
            .collection('factures')
            .actives
            .where((f) => (f['reliquat'] as num) > 0)
            .toList()
          ..sort(
              (a, b) => (b['reliquat'] as num).compareTo(a['reliquat'] as num)))
        .first;
    await toucher(t, find.byTooltip('Déclarer insolvable').first);
    await toucher(t, find.text('Déclarer insolvable').last);
    expect(find.text('Le motif est obligatoire.'), findsOneWidget);
    expect(
        m.collection('factures').parId(premiere['id'])!['insolvable'], isNull);
    await t.enterText(
        find.byType(TextField).last, 'Recouvrement amiable échoué');
    await toucher(t, find.text('Déclarer insolvable').last);
    final f = m.collection('factures').parId(premiere['id'])!;
    expect(f['insolvable'], true);
    expect(f['motifInsolvabilite'], 'Recouvrement amiable échoué');
    expect(f['reliquat'], premiere['reliquat'],
        reason: 'la créance n’est jamais effacée');
    expect(f['declarePar'], isNotEmpty,
        reason: 'RG-12 : aucune action anonyme');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Annuler').last);
    expect(
        m.collection('factures').parId(premiere['id'])!['insolvable'], isNull);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets(
      'engagement : échéancier enregistré, pièce éditée avec reconnaissance de dette',
      (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm8-reliquats');
    await toucher(t, find.byTooltip('Engagement de paiement').first);
    expect(find.text('Engagement de paiement'), findsWidgets);
    await toucher(t, find.text('Enregistrer et éditer'));
    final avecEngagement =
        m.collection('factures').actives.where((f) => f['engagement'] != null);
    expect(avecEngagement.length, 1);
    expect((avecEngagement.first['engagement'] as Map)['tranches'], 1);
    expect(find.textContaining('reconnais devoir à la Clinique NASSIERA TOO'),
        findsOneWidget);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets(
      'RBAC reliquats : la direction (lecture) n’a ni engagement ni insolvabilité',
      (t) async {
    await ouvrir(t, magasin(), 'm8-reliquats', role: 'direction');
    expect(find.byTooltip('Engagement de paiement'), findsNothing);
    expect(find.byTooltip('Déclarer insolvable'), findsNothing);
    expect(find.byTooltip('Imprimer la facture'), findsWidgets);
  });

  testWidgets(
      'pro-forma : le jeu n’en contient aucune → état vide dit, KPI à zéro',
      (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm8-proforma');
    expect(find.text('Aucune facture pro-forma établie.'), findsOneWidget);
    expect(find.text(nombre(m.collection('factures').actives.length)),
        findsWidgets,
        reason: 'toutes les factures sont « normalisées »');
  });

  testWidgets(
      'pro-forma : une pro-forma s’imprime avec filigrane et mention non fiscale',
      (t) async {
    final m = Magasin({
      'factures': [
        {
          'id': 'P1',
          'numero': 'PRO-2026-00001',
          'proforma': true,
          'patient': 'AWA K.',
          'patientCode': 'CNT/1/26',
          'type': 'Consultation',
          'date': '2026-10-01',
          'montantTTC': 5000,
          'partPatient': 5000,
          'montantPaye': 0,
          'reliquat': 5000
        }
      ]
    });
    await ouvrir(t, m, 'm8-proforma');
    expect(find.text('PRO-2026-00001'), findsOneWidget);
    await toucher(t, find.byTooltip('Imprimer').first);
    expect(find.textContaining('document non fiscal'), findsOneWidget);
    expect(find.textContaining('Facture pro-forma'), findsWidgets);
  });
}
