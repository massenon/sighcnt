// Aides communes des tests de la qualité (M13 : enquêtes, satisfaction, validations, page publique) et de la GED.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart' as d show nombre;
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'parite/extracteur.dart';

final donnees = DonneesNavigation.depuisDossier();
final aujourdhui = DateTime(2026, 8, 16, 10);

Map<String, Object?> m_(Object? x) => (x as Map).cast<String, Object?>();
List<Fiche> liste(Object? v) => [for (final x in (v as List)) (x as Map).cast<String, Object?>()];

/// Espaces fines et insécables de `money()` / `nombre()` : comparées comme des espaces ordinaires, puis retirées.
String sp(Object? v) => '${v ?? ''}'.replaceAll(RegExp(r'[\s  ]+'), '');

final vecteurs = m_(jsonDecode(File('../../packages/domaine/test/vecteurs/qualite.json').readAsStringSync()));

List<Fiche> jeuJson(String nom) => liste(jsonDecode(File('assets/donnees/jeu/$nom.json').readAsStringSync()));

/// Un magasin dont les collections sont posées par le test (les autres sont vides).
Magasin magasinDe(Map<String, List<Fiche>> collections) => Magasin({
      'audit': const <Fiche>[],
      for (final e in collections.entries) e.key: [for (final f in e.value) {...f}],
    }, 'POSTE', {...(jsonDecode(File('assets/donnees/jeu/referentiels.json').readAsStringSync()) as Map).cast<String, Object?>()});

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, {String role = 'admin'}) async {
  t.view.physicalSize = const Size(1600, 1100);
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
  // Une route (modale, tiroir) se monte à la première image et s'anime à la suivante : deux pas, sinon le bouton d'un tiroir est encore hors champ.
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> saisir(WidgetTester t, String champ, String valeur) async {
  await t.enterText(find.descendant(of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(TextField)), valeur);
  await t.pump();
}

/// Choisit une entrée d'une liste (select) du formulaire ; au-delà de huit entrées le panneau est paresseux : on cherche d'abord.
Future<void> choisir(WidgetTester t, String champ, String cible) async {
  await toucher(t, find.descendant(of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(InkWell)).first);
  if (find.text(cible).evaluate().isEmpty) {
    await t.enterText(find.byType(TextField).last, cible);
    await t.pump(const Duration(milliseconds: 200));
  }
  await toucher(t, find.text(cible).last);
  await t.pump(const Duration(milliseconds: 400));
}

String kpi(WidgetTester t, String libelle) =>
    t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == libelle)).valeur;

void cas(String nom, Future<void> Function(WidgetTester) corps) => testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

/// Les cellules d'une ligne du tableau, telles que l'agent les lit.
List<String> cellules(TableauSigh tab, Fiche r) => [for (final c in tab.colonnes) c.enTexte(r)];

/// Parité N1 (contenu) contre la fiche extraite de la maquette.
Future<void> parite(WidgetTester t, String id) async {
  final f = m_(jsonDecode(File('../../docs/architecture/ecrans/$id.json').readAsStringSync()));
  final p = comparerContenu(id, f, textesVisibles(t));
  expect(p.manquants, isEmpty, reason: '$id : N1 = ${(p.taux * 100).toStringAsFixed(1)} %');
}

/// Un rôle qui VOIT l'écran sans pouvoir y écrire (ou l'inverse) : les droits sont ceux de la matrice, pas une supposition du test.
String? roleSelonDroit(String ecran, {required bool editer}) {
  for (final r in ['comptable', 'caissier', 'medecin', 'infirmier', 'reception', 'stock', 'laborantin', 'da', 'dm', 'direction', 'agentadmin', 'aide_soignant', 'surveillant', 'assistant_comptable', 'aide_comptable', 'ambulancier']) {
    final dr = donnees.matrice.droit(r, ecran);
    if (dr.voir && dr.editer == editer) return r;
  }
  return null;
}

String nb(num n) => d.nombre(n);
