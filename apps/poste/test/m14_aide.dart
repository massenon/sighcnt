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

/// Aides communes aux tests des écrans de M14 (sécurité).
final donneesNav = DonneesNavigation.depuisDossier();
final aujourdhui = DateTime(2026, 10, 30, 10);

Magasin magasinM14() =>
    Magasin.depuisDossier(Magasin.collectionsDuJeu, 'test/fixtures/jeu_sobre');

/// Les mêmes données de navigation, mais le rôle [role] n'a que la LECTURE de [ecran] (voir, sans éditer ni annuler).
DonneesNavigation donneesLectureSeule(String role, String ecran) {
  final brut = (jsonDecode(File('assets/donnees/rbac.json').readAsStringSync()) as Map)
      .cast<String, Object?>();
  final parRole = (brut['parRole'] as Map).cast<String, Object?>();
  final r = ((parRole[role] as Map).cast<String, Object?>())..[ecran] = [1, 0, 0];
  parRole[role] = r;
  return DonneesNavigation(
      manifeste: donneesNav.manifeste,
      matrice: MatriceDroits.depuisJson(brut),
      parite: const {});
}

Future<void> ouvrirM14(WidgetTester t, Magasin m, String ecran,
    {String role = 'admin', DonneesNavigation? donnees, DateTime? horloge}) async {
  t.view.physicalSize = const Size(1600, 1200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees ?? donneesNav,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: ecran,
      magasin: m,
      horloge: () => horloge ?? aujourdhui));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> toucherM14(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 300));
}

/// Tape [texte] dans le champ nommé [champ] du formulaire ouvert.
Future<void> saisir(WidgetTester t, String champ, String texte) async {
  final f = find.descendant(
      of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(TextField));
  await t.ensureVisible(f);
  await t.enterText(f, texte);
  await t.pump();
}

/// Ouvre la liste du champ [champ] et y choisit [cible] (en la cherchant : le panneau ne construit que les lignes visibles).
Future<void> choisirM14(WidgetTester t, String champ, String cible) async {
  await toucherM14(
      t,
      find.descendant(
              of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(InkWell))
          .first);
  await t.pump(const Duration(milliseconds: 400));
  if (find.text(cible).evaluate().isEmpty) {
    await t.enterText(find.byType(TextField).last, cible);
    await t.pump(const Duration(milliseconds: 600));
  }
  // Le panneau est posé dans l'overlay : on le touche tel qu'il est (ensureVisible ferait défiler la page dessous).
  await t.tap(find.descendant(of: find.byType(InkWell), matching: find.text(cible)).last);
  await t.pump(const Duration(milliseconds: 400));
}

/// Coche ou décoche la case [champ].
Future<void> cocher(WidgetTester t, String champ) =>
    toucherM14(t, find.byKey(Key('kit:champ:$champ')));

void casM14(String nom, Future<void> Function(WidgetTester) corps) =>
    testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });
