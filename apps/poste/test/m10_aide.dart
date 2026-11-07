import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

/// Aides communes aux tests de M10 (RH) : les écrans sont montés sur le MAGASIN du poste, à l'horloge 30/10/2026 10 h de la maquette, et rejouent les
/// vecteurs `rh.json` tirés des écrans réels.
typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List)) obj(x)];

final donnees = DonneesNavigation.depuisDossier();
final v = obj(jsonDecode(File('../../packages/domaine/test/vecteurs/rh.json').readAsStringSync()));
final auj = DateTime(2026, 10, 30, 10);
final aout = DateTime(2026, 8, 20, 10);

String sansEspaces(Object? x) => '$x'.replaceAll(RegExp(r'[\s  ]'), '');

List<M> jeu(String nom) => liste(jsonDecode(File('assets/donnees/jeu/$nom.json').readAsStringSync()));

/// Un poste dont on pose les collections (copies : un test ne salit pas le suivant).
Magasin poste(Map<String, List<M>> collections) => Magasin({
      'audit': const [],
      'personnel': jeu('personnel'),
      for (final e in collections.entries) e.key: [for (final x in e.value) {...x}],
    }, 'POSTE');

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, {String role = 'admin', DateTime? horloge}) async {
  t.view.physicalSize = const Size(1600, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: ecran,
      magasin: m,
      horloge: () => horloge ?? auj));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void kpisIdentiques(WidgetTester t, Object? attendus) {
  for (final k in liste(attendus)) {
    final w = t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == k['libelle']));
    expect(sansEspaces(w.valeur), sansEspaces(k['valeur']), reason: '${k['libelle']}');
    expect(w.indice, k['indice'], reason: 'indice ${k['libelle']}');
  }
}

/// L'ordre dans lequel les textes apparaissent à l'écran (de haut en bas) : ce que l'agent lit.
List<String> ordreAffiche(WidgetTester t, Iterable<String> refs) {
  final y = {for (final r in refs) r: find.text(r).evaluate().isEmpty ? double.infinity : t.getTopLeft(find.text(r).first).dy};
  return (y.keys.where((r) => y[r]!.isFinite).toList()..sort((a, b) => y[a]!.compareTo(y[b]!)));
}

/// Pose les valeurs dans le formulaire de la modale ouverte (le contrôleur réel), comme l'agent les saisirait.
void poser(WidgetTester t, Map<String, Object?> saisie) {
  final ctl = t.widget<FormulaireSigh>(find.byType(FormulaireSigh).last).controleur;
  for (final e in saisie.entries) {
    final x = e.value;
    if (x is bool) {
      ctl.poser(e.key, x);
    } else {
      ctl.poser(e.key, '$x');
    }
  }
}

ControleurFormulaire formulaire(WidgetTester t) => t.widget<FormulaireSigh>(find.byType(FormulaireSigh).last).controleur;

Future<void> chercher(WidgetTester t, String ref) async {
  await t.enterText(find.byWidgetPredicate((w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('Rechercher')).first, ref);
  await t.pump(const Duration(milliseconds: 500));
}

Future<void> cliquer(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> archiverLigne(WidgetTester t, String motif) async {
  await cliquer(t, find.byTooltip('Archiver').first);
  await t.enterText(find.byType(TextField).last, motif);
  await t.pump();
  await t.tap(find.widgetWithText(BoutonSigh, 'Archiver').last);
  await t.pump(const Duration(milliseconds: 400));
}

bool egal(Object? a, Object? b) {
  if (a == null && b == null) return true;
  if (a is num && b is num) return a == b;
  if (a is List && b is List) return a.length == b.length && [for (var i = 0; i < a.length; i++) egal(a[i], b[i])].every((x) => x);
  return '$a' == '$b';
}

void fichesEgales(M obtenue, M attendue, {Set<String> ignores = const {}}) {
  const tous = {'id', '_creePar', '_creeLe', '_modifiePar', '_modifieLe', 'statut', '_motifArchivage', 'statutAvantArchivage'};
  for (final k in {...obtenue.keys, ...attendue.keys}) {
    if (tous.contains(k) || ignores.contains(k)) continue;
    if ((obtenue[k] == null || obtenue[k] == '') && (attendue[k] == null || attendue[k] == '')) continue;
    expect(egal(obtenue[k], attendue[k]), isTrue, reason: '$k : écrit ${obtenue[k]}, maquette ${attendue[k]}');
  }
}

/// Tous les textes affichés, sans espaces ni casse (les libellés des listes de description sont mis en capitales par la feuille de style de la maquette).
String texteAffiche(WidgetTester t) => sansEspaces([for (final w in t.widgetList<Text>(find.byType(Text))) w.data ?? w.textSpan?.toPlainText() ?? ''].join('')).toLowerCase();

/// Chaque cellule du vecteur figure à l'écran.
void cellulesAffichees(WidgetTester t, Iterable<Object?> cellules, {String raison = ''}) {
  final txt = texteAffiche(t);
  for (final c in cellules) {
    final s = sansEspaces(c).toLowerCase();
    if (s.isEmpty || s == '—') continue;
    expect(txt.contains(s), isTrue, reason: '$raison « $c » absent de l’écran');
  }
}

/// Ordre de ligne identique : les références (première colonne) dans l'ordre de la maquette.
void ordreIdentique(WidgetTester t, Object? tableau, {int colonne = 0, int max = 15}) {
  final lignes = (obj(tableau)['lignes'] as List).cast<List>().take(max).toList();
  final refs = [for (final l in lignes) '${l[colonne]}'];
  expect(ordreAffiche(t, refs), refs);
}
