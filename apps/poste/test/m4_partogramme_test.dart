import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// `m4-partogramme` : le travail suivi, la ligne d'action franchie (note + indicateur), l'ouverture d'un partogramme, les mesures (tri par heure,
/// clôture à 10 cm, alerte sonore), rejoués sur les vecteurs de la maquette.
typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List)) obj(x)];

final donnees = DonneesNavigation.depuisDossier();
final reg = obj(jsonDecode(File('../../packages/domaine/test/vecteurs/mat_regles.json').readAsStringSync()));
final lect = obj(jsonDecode(File('../../packages/domaine/test/vecteurs/mat_lectures.json').readAsStringSync()));
final saisies = obj(jsonDecode(File('../../packages/domaine/test/vecteurs/mat_saisies.json').readAsStringSync()));
final part = obj(reg['partogramme']);
final auj = DateTime(2026, 8, 16, 12);

String s(Object? v) => '${v ?? ''}'.replaceAll(RegExp(r'[\s  ]'), '');

Magasin magasin() {
  final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
  final c = m.collection('partogrammes');
  for (final f in c.toutes.toList()) {
    c.archiver(f['id']);
  }
  for (final f in liste(part['fiches']).reversed) {
    c.inserer({...f}, prefixe: 'P');
  }
  return m;
}

Future<void> ouvrir(WidgetTester t, Magasin m) async {
  t.view.physicalSize = const Size(1600, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: const ConfigPoste(mode: ModePoste.fileul, role: 'admin'),
      ecranInitial: 'm4-partogramme',
      magasin: m,
      horloge: () => auj));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

String kpi(WidgetTester t, String l) => t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == l)).valeur;
ControleurFormulaire ctlModale(WidgetTester t) => t.widget<FormulaireSigh>(find.byType(FormulaireSigh).last).controleur;

void cas(String nom, Future<void> Function(WidgetTester) corps) => testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  cas('indicateurs et cartes rejouent la maquette', (t) async {
    await ouvrir(t, magasin());
    for (final k in liste(part['kpis'])) {
      expect(s(kpi(t, '${k['label']}')), s(k['valeur']), reason: '${k['label']}');
    }
    for (final c in (part['cartes'] as List)) {
      expect(find.text('$c'), findsOneWidget);
    }
    for (final b in ['Ouvrir un partogramme', 'Ajouter une mesure', 'Imprimer']) {
      expect(find.text(b), findsOneWidget);
    }
    expect(find.text('Travail suivi'), findsOneWidget);
  });

  for (final c in liste(part['cas'])) {
    cas('${c['ref']} : ${c['note'] == true ? 'ligne d\'action franchie, note affichée' : 'pas de note'} — ${(c['mesures'] as List).length} mesure(s)', (t) async {
      final m = magasin();
      await ouvrir(t, m);
      final id = m.collection('partogrammes').toutes.firstWhere((f) => f['reference'] == c['ref'])['id'];
      t.widget<FormulaireSigh>(find.byType(FormulaireSigh).first).controleur.poser('travail', '$id');
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('La ligne d’ACTION est franchie'), c['note'] == true ? findsOneWidget : findsNothing);
      expect(find.text('${c['enTete']}'), findsOneWidget);
      if ((c['mesures'] as List).isEmpty) expect(find.text('Mesures horaires'), findsOneWidget);
      for (final r in (c['mesures'] as List).cast<List>()) {
        expect(find.text('${r.first}'), findsWidgets, reason: 'heure ${r.first}');
      }
      if (c['note'] == true) {
        expect(find.textContaining('codes 1 à 7 : Rupture artificielle de la PDE'), findsOneWidget);
      }
    });
  }

  cas('ouvrir un partogramme puis y porter des mesures : tri par heure, clôture à 10 cm, alerte d\'action', (t) async {
    final m = magasin();
    await ouvrir(t, m);
    final col = m.collection('partogrammes');
    final n0 = col.toutes.length;
    final ctx = saisies['contexte'] as Map;
    await t.tap(find.widgetWithText(BoutonSigh, 'Ouvrir un partogramme'));
    await t.pump(const Duration(milliseconds: 400));
    ctlModale(t)
      ..poser('patientCode', '${ctx['femme']}')
      ..poser('debutDate', '2026-08-16')
      ..poser('debutHeure', '08:00')
      ..poser('gestite', '2')
      ..poser('parite', '1');
    await t.tap(find.widgetWithText(BoutonSigh, 'Ouvrir'));
    await t.pump(const Duration(milliseconds: 400));
    expect(col.toutes.length, n0 + 1);
    final o = obj(part['ouverture']);
    final att = liste(o['nouveau']).single;
    final f = col.toutes.first;
    expect(f['reference'], att['reference']);
    expect(f['debut'], att['debut']);
    expect(f['mesures'], isEmpty);
    expect(f['clos'], false);
    expect(f['patient'], att['patient']);
    expect(find.text('Partogramme ouvert.'), findsOneWidget);
    final id = f['id'];

    final ajouts = liste(part['ajouts']);
    for (final (i, a) in ajouts.indexed) {
      await t.tap(find.widgetWithText(BoutonSigh, 'Ajouter une mesure'));
      await t.pump(const Duration(milliseconds: 400));
      final c = ctlModale(t);
      // l'heure proposée : celle qui suit la dernière mesure
      final prerempli = {for (final p in (a['prerempli'] as List).cast<List>()) '${p[0]}': p[1]};
      if (i > 0 || true) {
        expect('${c['heure']}', '${prerempli['heure']}', reason: 'heure proposée');
      }
      for (final e in obj(a['saisie']).entries) {
        c.poser(e.key, '${e.value}');
      }
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await t.pump(const Duration(milliseconds: 400));
      final p = col.parId(id)!;
      expect([for (final x in (p['mesures'] as List)) (x as Map)['heure']], [for (final x in liste(a['mesures'])) x['heure']], reason: 'mesure $i');
      expect(p['clos'], a['clos']);
      expect(p['resume'], a['resume']);
      if ('${a['toasts']}'.contains('franchit')) {
        expect(find.textContaining('franchit la ligne d’action'), findsWidgets);
      }
    }
    // la mesure sans descente ni TA n'écrit pas de champ vide inventé
    final trois = ((col.parId(id)!['mesures'] as List).map((x) => x as Map).firstWhere((x) => x['heure'] == 3));
    expect(trois['descente'], isNull);
    expect(trois['bdf'], 40);

    await t.tap(find.widgetWithText(BoutonSigh, 'Imprimer'));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('PARTOGRAPHIE'), findsWidgets);
  });
}
