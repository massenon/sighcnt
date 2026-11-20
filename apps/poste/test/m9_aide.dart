import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/main.dart';

/// Aides communes des tests de M9. L'horloge du poste est posée au 16/08/2026 midi — celle du pilote des vecteurs (`vecteurs-m9.js`) : le jeu est
/// daté de l'été 2026, et les valeurs lues sur l'écran réel de la maquette (27 cartes valides, 1 733 134 F de créances…) en dépendent.
final donnees = DonneesNavigation.depuisDossier();
/// L'instant EXACT du pilote (16/08/2026 12:00:28) : les anciennetés et « Expire dans N j » s'arrondissent (`Math.round`), une demi-journée pile
/// bascule d'un jour avec quelques secondes d'écart.
final aujourdhui = DateTime.parse('${vecteurs()['aujInstant']}');

typedef M = Map<String, Object?>;

Finder texteSp(String s) =>
    find.byWidgetPredicate((w) => w is Text && w.data != null && sp(w.data!) == s);

Magasin magasin() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

Map<String, Object?> vecteurs() => (jsonDecode(
        File('../../packages/domaine/test/vecteurs/ass_m9.json')
            .readAsStringSync()) as Map)
    .cast<String, Object?>();

M m9(Object? x) => (x as Map).cast<String, Object?>();
List<M> lm(Object? x) => [for (final y in (x as List? ?? const [])) m9(y)];

/// Les espaces insécables du formatage français deviennent des espaces ordinaires (le pilote de la maquette a normalisé les siennes).
String sp(String s) => s.replaceAll(' ', ' ').replaceAll(' ', ' ');

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran,
    {String role = 'admin', DateTime? le}) async {
  t.view.physicalSize = const Size(1600, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: ecran,
      magasin: m,
      horloge: () => le ?? aujourdhui));
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

Future<void> choisir(WidgetTester t, String champ, String cible) async {
  await toucher(
      t,
      find
          .descendant(
              of: find.byKey(Key('kit:champ:$champ')),
              matching: find.byType(InkWell))
          .first);
  if (find.text(cible).evaluate().isEmpty) {
    await t.enterText(find.byType(TextField).last, cible);
    await t.pump(const Duration(milliseconds: 200));
  }
  await toucher(t, find.text(cible).last);
  await t.pump(const Duration(milliseconds: 400));
}

Finder champ(String nom) => find.descendant(
    of: find.byKey(Key('kit:champ:$nom')), matching: find.byType(TextField));

Future<void> saisir(WidgetTester t, String nom, String texte) =>
    t.enterText(champ(nom), texte);

void cas(String nom, Future<void> Function(WidgetTester) corps) =>
    testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

List<String> kpis(WidgetTester t) => [
      for (final w in t.widgetList<Text>(find.byKey(const Key('kit:kpi-valeur'))))
        sp(w.data ?? '')
    ];

/// Tous les textes affichés (Text.data), espaces normalisées.
List<String> textes(WidgetTester t) => [
      for (final w in t.widgetList<Text>(find.byType(Text)))
        if (w.data != null) sp(w.data!)
    ];

/// Les cellules des lignes du tableau [i] d'un écran, telles que la maquette les a affichées (vecteurs).
List<List<String>> cellulesVecteur(Map<String, Object?> v, String ecran, [int i = 0]) => [
      for (final l in lm(m9(m9(v['ecrans'])[ecran])['tables'] is List
          ? m9(((m9(v['ecrans'])[ecran] as Map)['tables'] as List)[i])['lignes']
          : const []))
        [for (final c in (l['cellules'] as List)) '$c']
    ];

/// Pose une date par le sélecteur du système : le jour [jour] du mois affiché (celui de la valeur courante du champ).
Future<void> dater(WidgetTester t, String champ, int jour) async {
  await toucher(t,
      find.descendant(of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(InkWell)).first);
  await t.pump(const Duration(seconds: 1));
  final j = find.descendant(of: find.byType(DatePickerDialog), matching: find.text('$jour'));
  await t.tap(j.last);
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(find.text('OK'));
  await t.pump(const Duration(seconds: 1));
}

/// Choisit une option d'un filtre de tableau (`PopupMenuButton` dont l'infobulle est le libellé du filtre).
Future<void> filtrer(WidgetTester t, String filtre, String option) async {
  await t.tap(find.byTooltip(filtre).first);
  await t.pumpAndSettle();
  await t.tap(find.text(option).last);
  await t.pumpAndSettle();
}
