import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// Comportement de `m8-factures` (tranche 1) : les mêmes gestes que le scénario de la maquette — compte des KPI = recompte du magasin, onglets
/// avec leur compte, fiche en tiroir, archivage annulable et visible, commandes d'écriture ABSENTES sans le droit (jamais grisées).
final donnees = DonneesNavigation.depuisDossier();

Future<Magasin> magasin() async =>
    Magasin.depuisDossier(Magasin.collectionsDuJeu);

Future<void> ouvrir(WidgetTester t, Magasin m, {String role = 'admin'}) async {
  t.view.physicalSize = const Size(1600, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: 'm8-factures',
      magasin: m));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> toucher(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  testWidgets(
      'les KPI sont recalculés depuis le magasin (comme la maquette), pas recopiés',
      (t) async {
    final m = await magasin();
    await ouvrir(t, m);
    final f = m.collection('factures').actives;
    num somme(String k) => f.fold<num>(0, (a, r) => a + ((r[k] as num?) ?? 0));
    final valeurs = [
      for (final w
          in t.widgetList<Text>(find.byKey(const Key('kit:kpi-valeur'))))
        w.data
    ];
    expect(valeurs, [
      nombre(f.length),
      money(somme('montantTTC')),
      money(somme('montantPaye')),
      money(somme('reliquat'))
    ]);
  });

  testWidgets(
      'onglets « Tous les factures » et « Archivés » avec leurs comptes ; 15 lignes par page',
      (t) async {
    final m = await magasin();
    await ouvrir(t, m);
    expect(find.byKey(const Key('kit:onglet:liste:actif')), findsOneWidget);
    expect(
        find.text(
            'Affichage de 1 à 15 sur ${m.collection('factures').actives.length} enregistrements'),
        findsOneWidget);
    await toucher(t, find.byKey(const Key('kit:onglet:archives')));
    await t.pump();
    expect(find.text('Aucun enregistrement archivé.'), findsOneWidget);
  });

  testWidgets(
      'archiver est confirmé, visible et ANNULABLE ; la fiche reste au magasin (RG-14)',
      (t) async {
    final m = await magasin();
    await ouvrir(t, m);
    final col = m.collection('factures');
    final avant = col.actives.length;
    final cible = (col.actives
          ..sort((a, b) => '${b['date']}'.compareTo('${a['date']}')))
        .first;
    await toucher(t, find.byTooltip('Archiver').first);
    await t.pumpAndSettle();
    expect(find.text('Archiver cet enregistrement ?'), findsOneWidget);
    await t.tap(find.text('Archiver').last);
    await t.pumpAndSettle();
    expect(col.actives.length, avant - 1);
    expect(col.parId(cible['id']), isNotNull,
        reason: 'archivage LOGIQUE : jamais de suppression physique');
    expect(find.text('Enregistrement archivé.'), findsOneWidget);
    await t.tap(find.text('Annuler'));
    await t.pumpAndSettle();
    expect(col.actives.length, avant);
    expect(find.text('Action annulée.'), findsOneWidget,
        reason: 'l’annulation doit être VISIBLE');
    await t.pump(
        const Duration(seconds: 10)); // les messages se referment d'eux-mêmes
  });

  testWidgets(
      'clic sur une ligne : fiche en tiroir avec le détail et l’archivage au pied',
      (t) async {
    final m = await magasin();
    await ouvrir(t, m);
    final f = (m.collection('factures').actives
          ..sort((a, b) => '${b['date']}'.compareTo('${a['date']}')))
        .first;
    await toucher(t, find.text('${f['patient']}').first);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('kit:tiroir-panneau')), findsOneWidget);
    expect(find.text('Montant TTC'), findsOneWidget);
    expect(find.text('Mode de règlement'), findsOneWidget);
    expect(find.text('Archiver'), findsWidgets);
  });

  testWidgets(
      'RBAC : le caissier (voir+éditer, sans annuler) n’a AUCUNE commande d’archivage ; la direction (lecture) n’a pas « Nouveau »',
      (t) async {
    final m = await magasin();
    await ouvrir(t, m, role: 'caissier');
    expect(find.text('Nouveau'), findsOneWidget);
    expect(find.byTooltip('Archiver'), findsNothing,
        reason: 'commande ABSENTE, pas grisée');
    expect(find.byTooltip('Consulter'), findsWidgets);
    await ouvrir(t, m, role: 'direction');
    expect(find.text('Nouveau'), findsNothing);
    expect(find.widgetWithText(BoutonSigh, 'Nouvelle facture'), findsNothing);
    expect(find.textContaining('Lecture seule'), findsOneWidget,
        reason: 'une restriction s’annonce');
    expect(find.byTooltip('Archiver'), findsNothing);
  });

  testWidgets('un magasin vide affiche l’état vide, pas une erreur', (t) async {
    await ouvrir(t, Magasin());
    expect(find.text('Aucun facture enregistré.'), findsOneWidget);
    expect(find.text('Affichage'), findsNothing);
  });

  test('le jeu de démonstration est celui de la maquette (engendré, non édité)',
      () {
    final f =
        jsonDecode(File('assets/donnees/jeu/factures.json').readAsStringSync())
            as List;
    expect(f.length, greaterThan(100));
    expect((f.first as Map).containsKey('numero'), isTrue);
  });
}
