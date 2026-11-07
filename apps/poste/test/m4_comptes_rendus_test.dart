import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// `m4-comptes-rendus` : trois pièces aux rubriques propres, formulaire engendré depuis la déclaration, rejoués sur la maquette.
typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List)) obj(x)];

final donnees = DonneesNavigation.depuisDossier();
final cr = obj(obj(jsonDecode(File('../../packages/domaine/test/vecteurs/mat_lectures.json').readAsStringSync()))['comptesRendus']);
final auj = DateTime(2026, 8, 16, 12);

String s(Object? v) => '${v ?? ''}'.replaceAll(RegExp(r'[\s  ]'), '');

Future<void> ouvrir(WidgetTester t, Magasin m) async {
  t.view.physicalSize = const Size(1600, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: const ConfigPoste(mode: ModePoste.fileul, role: 'admin'),
      ecranInitial: 'm4-comptes-rendus',
      magasin: m,
      horloge: () => auj));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> onglet(WidgetTester t, String libelle) async {
  await t.tap(find.descendant(of: find.byType(OngletsSigh), matching: find.textContaining(libelle)).first);
  await t.pump(const Duration(milliseconds: 300));
}

void cas(String nom, Future<void> Function(WidgetTester) corps) => testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  cas('indicateurs, onglets, note et tableau de chaque pièce', (t) async {
    await ouvrir(t, Magasin.depuisDossier(Magasin.collectionsDuJeu));
    for (final k in liste(cr['kpis'])) {
      expect(s(t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == '${k['label']}')).valeur), s(k['valeur']), reason: '${k['label']}');
    }
    expect(find.textContaining('NON COUVERTS par les assurances'), findsOneWidget);
    for (final o in liste(cr['parOnglet'])) {
      await onglet(t, '${o['onglet']}'.replaceAll(RegExp(r'\d+$'), ''));
      final tab = t.state<TableauSighState>(find.byType(TableauSigh).first);
      expect(tab.lignesFiltrees.length, o['nb'], reason: '${o['onglet']}');
      final cols = t.widget<TableauSigh>(find.byType(TableauSigh).first).colonnes;
      expect(s(cols.map((c) => c.enTexte(tab.lignesFiltrees.first)).join()), s((o['page1'] as List).first.sublist(0, 4).join()), reason: 'première ligne ${o['onglet']}');
      if (o['note'] != null) expect(find.textContaining('TOUS non couverts'), findsOneWidget);
    }
  });

  for (final c in liste(cr['creations'])) {
    cas('création — ${c['nom']}', (t) async {
      final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
      final col = m.collection('crMaternite');
      final n0 = col.toutes.length;
      await ouvrir(t, m);
      final planning = '${c['nom']}'.startsWith('planning');
      await onglet(t, planning ? 'de planning familial' : 'd’AMIU');
      await t.tap(find.widgetWithText(BoutonSigh, planning ? 'Nouveau — de planning familial' : 'Nouveau — d’AMIU'));
      await t.pump(const Duration(milliseconds: 400));
      final ctl = t.widget<FormulaireSigh>(find.byType(FormulaireSigh).last).controleur;
      for (final p in (c['initial'] as List).cast<List>()) {
        if (p[0] == 'methode' || p[0] == 'geste') expect('${ctl['${p[0]}']}', '${p[1]}', reason: 'proposé : ${p[0]}');
      }
      for (final e in obj(c['saisie']).entries) {
        if (e.key == 'dateHeure') {
          final p = '${e.value}'.split('T');
          ctl.poser('dateHeureDate', p[0]);
          ctl.poser('dateHeureHeure', p[1]);
        } else {
          e.value is bool ? ctl.poser(e.key, e.value) : ctl.poser(e.key, '${e.value}');
        }
      }
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 500));
      final att = liste(c['nouvelles']);
      if (att.isEmpty) {
        expect(col.toutes.length, n0);
        expect(find.text('Le formulaire comporte des erreurs.'), findsWidgets);
        return;
      }
      expect(col.toutes.length, n0 + 1);
      final f = col.toutes.first, a = att.single;
      for (final k in ['typeCr', 'typeLabel', 'patient', 'patientCode', 'sageFemme', 'sageFemmeId', 'methode', 'geste', 'counseling', 'effetsSecondaires', 'dateActe', 'dateHeure', 'indication', 'operateurId']) {
        expect('${f[k] ?? ''}', '${a[k] ?? ''}', reason: k);
      }
      expect('${f['reference']}'.startsWith('CRM-'), isTrue);
      expect(find.text('Compte rendu créé.'), findsOneWidget);
    });
  }

  cas('la fiche de chaque pièce liste ses rubriques', (t) async {
    for (final (i, f) in liste(cr['fiches']).indexed) {
      await ouvrir(t, Magasin.depuisDossier(Magasin.collectionsDuJeu));
      final titre = '${f['titre']}';
      await onglet(t, const ['d’accouchement', 'de planning familial', 'd’AMIU'][i]);
      await t.tap(find.byTooltip('Consulter').first);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text(titre), findsWidgets);
      expect(find.byType(MiniTableauSigh), findsWidgets);
    }
  });
}
