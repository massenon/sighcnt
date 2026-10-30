import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/main.dart';

/// Outillage commun des tests de l'hospitalisation (M3) : le même jeu d'essai que la maquette (`packages/domaine/test/vecteurs/hospitalisation.json`,
/// engendré par `prototype_html/build/vecteurs-hospitalisation.js`) est monté dans Flutter.
final donnees = DonneesNavigation.depuisDossier();
final vecteurs = (jsonDecode(File('../../packages/domaine/test/vecteurs/hospitalisation.json').readAsStringSync()) as Map).cast<String, Object?>();
final horlogeEssai = DateTime(2026, 8, 16, 10);

List<Fiche> liste(Object? v) => [for (final x in (v as List)) (x as Map).cast<String, Object?>()];
Map<String, Object?> carte(Object? v) => (v as Map).cast<String, Object?>();

/// Un texte sans aucune espace (ordinaire, insécable, fine) : on compare les caractères, pas la typographie.
String sansEspaces(Object? v) => '${v ?? ''}'.replaceAll(RegExp(r'[\s  ]'), '');

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, {String role = 'admin', DateTime? le}) async {
  t.view.physicalSize = const Size(1600, 2600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: ecran,
      magasin: m,
      horloge: () => le ?? horlogeEssai));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> toucher(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  // le tiroir glisse en 200 ms, la modale apparaît en 150 ms : on laisse l'animation finir avant de viser
  for (var i = 0; i < 3; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
}

Future<void> saisir(WidgetTester t, String champ, String valeur) async {
  await t.enterText(find.descendant(of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(TextField)), valeur);
  await t.pump();
}

/// Ouvre la liste du champ et y choisit la cible (en la cherchant : le panneau ne construit que les lignes visibles).
Future<void> choisir(WidgetTester t, String champ, String cible) async {
  await toucher(t, find.descendant(of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(InkWell)).first);
  if (find.text(cible).evaluate().isEmpty) {
    await t.enterText(find.byType(TextField).last, cible);
    await t.pump(const Duration(milliseconds: 200));
  }
  await toucher(t, find.text(cible).last);
  await t.pump(const Duration(milliseconds: 400));
}

void cas(String nom, Future<void> Function(WidgetTester) corps) => testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

/// Tous les `Text` affichés.
List<String> textes(WidgetTester t) => [
      for (final w in t.widgetList<Text>(find.byType(Text)))
        if ((w.data ?? w.textSpan?.toPlainText() ?? '').trim().isNotEmpty) (w.data ?? w.textSpan!.toPlainText())
    ];

bool affiche(WidgetTester t, String fragment) => textes(t).any((x) => sansEspaces(x).contains(sansEspaces(fragment)));

/// Ferme la modale ou le tiroir du dessus (Échap, comme l'agent).
Future<void> fermerDessus(WidgetTester t) async {
  await t.sendKeyEvent(LogicalKeyboardKey.escape);
  await t.pump(const Duration(milliseconds: 500));
}

/// Les textes affichés dans la bande horizontale de [ancre] (une ligne de tableau : la référence en tête de ligne) ; [rang] distingue deux ancres
/// identiques (deux relevés du même jour).
List<String> ligneDe(WidgetTester t, String ancre, {double haut = 28, double bas = 28, int rang = 0}) {
  final y = t.getTopLeft(find.text(ancre).at(rang)).dy;
  final out = <String>[];
  for (final e in find.byType(Text).evaluate()) {
    final w = e.widget as Text;
    final d = w.data;
    final ro = e.renderObject;
    if (d == null || ro is! RenderBox || !ro.attached) continue;
    final dy = ro.localToGlobal(Offset.zero).dy;
    if (dy >= y - 1 - haut && dy < y + bas) out.add(d);
  }
  return out;
}
