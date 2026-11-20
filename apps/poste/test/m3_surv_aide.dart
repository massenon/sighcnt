import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/main.dart';

/// Aides communes des tests des écrans de surveillance de M3 : mêmes gestes que l'agent (ouvrir un écran, remplir un champ, choisir dans une liste).
final donnees = DonneesNavigation.depuisDossier();
final aujourdhui = DateTime(2026, 8, 16, 10);

Map<String, Object?> lireVecteurs(String fichier) =>
    (jsonDecode(File('../../packages/domaine/test/vecteurs/$fichier').readAsStringSync()) as Map).cast<String, Object?>();

List<Fiche> liste(Object? v) => [for (final x in (v as List)) (x as Map).cast<String, Object?>()];
Map<String, Object?> dico(Object? v) => (v as Map).cast<String, Object?>();

/// Espaces ordinaires, insécables et fines neutralisés (typographie française de `money()` et des dates).
String sans(Object? v) => '${v ?? ''}'.replaceAll(RegExp(r'[\s  ]'), '');

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
  await t.pump(const Duration(milliseconds: 300));
}

Finder _champ(String nom) => find.byKey(Key('kit:champ:$nom'));

/// Ouvre la liste du champ [champ] et y choisit [cible] (en la cherchant : le panneau ne construit que les lignes visibles).
Future<void> choisir(WidgetTester t, String champ, String cible) async {
  await toucher(t, find.descendant(of: _champ(champ), matching: find.byType(InkWell)).first);
  if (find.text(cible).evaluate().isEmpty) {
    await t.enterText(find.byType(TextField).last, cible);
    await t.pump(const Duration(milliseconds: 200));
  }
  await toucher(t, find.text(cible).last);
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> ecrire(WidgetTester t, String champ, String valeur) async {
  final f = find.descendant(of: _champ(champ), matching: find.byType(TextField));
  await t.ensureVisible(f);
  await t.enterText(f, valeur);
  await t.pump();
}

/// Pose une date par le sélecteur du système : le jour [jour] du mois affiché (le mois courant du poste).
Future<void> dater(WidgetTester t, String champ, int jour) async {
  await toucher(t, find.descendant(of: _champ(champ), matching: find.byType(InkWell)).first);
  await t.pump(const Duration(seconds: 1));
  final j = find.descendant(of: find.byType(DatePickerDialog), matching: find.text('$jour'));
  await t.tap(j.last);
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(find.text('OK'));
  await t.pump(const Duration(seconds: 1));
}

bool afficheTexte(WidgetTester t, String texte) =>
    find.textContaining(texte).evaluate().isNotEmpty;

void cas(String nom, Future<void> Function(WidgetTester) corps) => testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });
