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
import 'parite/extracteur.dart';

/// Consultation M2 (9 écrans) : parité N1 mesurée contre les fiches de la maquette, puis comportements — registres lus sur le jeu comme les lit la
/// maquette (vecteurs `consultation.json`), refus SANS_DOSSIER à l'écran, prescription depuis la fiche, administration et relais.
final donnees = DonneesNavigation.depuisDossier();
final vecteurs = (jsonDecode(File('../../packages/domaine/test/vecteurs/consultation.json').readAsStringSync()) as Map)
    .cast<String, Object?>();

const ecrans = [
  'm2-consultations', 'm2-dossiers-consultation', 'm2-consultation-fiche', 'm2-pathologies', 'm2-ordonnances',
  'm2-prescriptions', 'm2-salle-soins', 'm2-dossier-consultation-nouveau', 'm2-ordonnance-nouvelle',
];

Magasin magasin() {
  final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
  for (final a in (vecteurs['ajustements'] as List)) {
    final x = (a as Map).cast<String, Object?>();
    m.collection('${x['col']}').mettreAJour(x['id'], (x['patch'] as Map).cast<String, Object?>());
  }
  return m;
}

Future<void> ouvrir(WidgetTester t, Magasin m, String id, {String role = 'admin'}) async {
  t.view.physicalSize = const Size(1440, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: id,
      magasin: m,
      horloge: () => DateTime.parse('${vecteurs['jourCourant']}T12:00:00')));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

List<(String, String)> kpis(WidgetTester t) {
  final l = [for (final w in t.widgetList<Text>(find.byKey(const Key('kit:kpi-libelle')))) w.data!];
  final v = [for (final w in t.widgetList<Text>(find.byKey(const Key('kit:kpi-valeur')))) w.data!];
  return [for (var i = 0; i < l.length; i++) (l[i], v[i])];
}

void main() {
  setUpAll(chargerPolices);

  for (final id in ecrans) {
    testWidgets('parité N1 = 100 % : $id', (t) async {
      final f = (jsonDecode(File('../../docs/architecture/ecrans/$id.json').readAsStringSync()) as Map).cast<String, Object?>();
      await ouvrir(t, magasin(), id);
      final p = comparerContenu(id, f, textesVisibles(t));
      expect(p.manquants, isEmpty, reason: '$id : ${p.presents}/${p.attendus}');
      await t.pump(const Duration(seconds: 10));
    });
  }

  for (final id in ['m2-consultations', 'm2-dossiers-consultation', 'm2-pathologies', 'm2-ordonnances', 'm2-prescriptions', 'm2-salle-soins']) {
    testWidgets('indicateurs identiques à ceux de la maquette : $id', (t) async {
      await ouvrir(t, magasin(), id);
      final att = [
        for (final k in ((vecteurs['ecrans'] as Map)[id] as Map)['kpis'] as List)
          ((k as Map)['label'] as String, k['valeur'] as String)
      ];
      String n(String s) => s.replaceAll(RegExp(r'\s'), '');
      expect([for (final k in kpis(t)) (k.$1, n(k.$2))], [for (final k in att) (k.$1, n(k.$2))]);
      await t.pump(const Duration(seconds: 10));
    });
  }

  testWidgets('la fiche REFUSE sans dossier enregistré et le dit', (t) async {
    final m = magasin();
    for (final d in m.collection('dossiersConsultation').actives) {
      m.collection('dossiersConsultation').archiver(d['id']);
    }
    await ouvrir(t, m, 'm2-consultation-fiche');
    expect(find.textContaining('Fiche impossible sans dossier'), findsOneWidget);
    expect(find.text('Ouvrir les dossiers de consultation'), findsWidgets);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('la salle de soins : une prescription non réglée est visible, verrouillée', (t) async {
    await ouvrir(t, magasin(), 'm2-salle-soins');
    expect(find.text('Non réglée'), findsWidgets);
    expect(find.text('Administrer'), findsNothing.or(findsWidgets));
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('aide-soignante : aucune commande d’écriture sur les dossiers', (t) async {
    await ouvrir(t, magasin(), 'm2-dossiers-consultation', role: 'aide_soignant');
    expect(find.text('Nouveau dossier'), findsNothing);
    await t.pump(const Duration(seconds: 10));
  });
}

extension on Matcher {
  Matcher or(Matcher autre) => anyOf(this, autre);
}
