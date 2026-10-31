import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/main.dart';

/// Aides communes des tests de M11 (paie). L'horloge du poste est posée au 30/10/2026 10 h — celle du pilote des vecteurs (`vecteurs-paie.js`) : les
/// anciennetés (`Math.floor(jours / 365,25)`), le mois courant des écrans et les valeurs lues sur l'écran RÉEL de la maquette en dépendent.
final donnees = DonneesNavigation.depuisDossier();
final aujourdhui = DateTime(2026, 10, 30, 10, 1, 17);

typedef M = Map<String, Object?>;

M mm(Object? x) => (x as Map).cast<String, Object?>();
List<M> lm(Object? x) => [for (final y in (x as List? ?? const [])) mm(y)];

final _vecteurs = (jsonDecode(File('../../packages/domaine/test/vecteurs/paie.json').readAsStringSync()) as Map).cast<String, Object?>();
M vecteurs() => _vecteurs;

/// Les espaces insécables du formatage français deviennent des espaces ordinaires (le pilote de la maquette a normalisé les siennes).
String sp(String s) => s.replaceAll(' ', ' ').replaceAll(' ', ' ');

Magasin magasin() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, {String role = 'admin', DateTime? le}) async {
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

/// Choisit [cible] dans la liste du champ [champ] (le panneau ne construit que les lignes visibles : on tape d'abord dans la recherche).
Future<void> choisir(WidgetTester t, String champ, String cible) async {
  await toucher(t, find.descendant(of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(InkWell)).first);
  if (find.text(cible).evaluate().isEmpty) {
    await t.enterText(find.byType(TextField).last, cible);
    await t.pump(const Duration(milliseconds: 200));
  }
  await toucher(t, find.text(cible).last);
  await t.pump(const Duration(milliseconds: 400));
}

Finder champ(String nom) => find.descendant(of: find.byKey(Key('kit:champ:$nom')), matching: find.byType(TextField));

Future<void> saisir(WidgetTester t, String nom, String texte) => t.enterText(champ(nom), texte);

void cas(String nom, Future<void> Function(WidgetTester) corps) => testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

List<String> kpis(WidgetTester t) => [for (final w in t.widgetList<Text>(find.byKey(const Key('kit:kpi-valeur')))) sp(w.data ?? '')];

List<String> libellesKpi(WidgetTester t) => [for (final w in t.widgetList<Text>(find.byKey(const Key('kit:kpi-libelle')))) sp(w.data ?? '')];

/// Tous les textes affichés (Text.data ET Text.rich — le cartouche d'une pièce est « libellé : valeur »), espaces normalisées.
List<String> textes(WidgetTester t) => [
      for (final w in t.widgetList<Text>(find.byType(Text)))
        if (w.data != null) sp(w.data!) else if (w.textSpan != null) sp(w.textSpan!.toPlainText())
    ];

Finder texteSp(String s) => find.byWidgetPredicate((w) => w is Text && w.data != null && sp(w.data!) == s);

/// Les KPI de la maquette : libellé → valeur.
Map<String, String> kpisVecteur(Object? liste) => {for (final k in lm(liste)) '${k['label']}': sp('${k['valeur']}')};

Map<String, String> kpisAffiches(WidgetTester t) => {for (final (i, l) in libellesKpi(t).indexed) l: kpis(t)[i]};

/// Les bulletins que la maquette a écrits à la génération (octobre puis mai), prêts à être posés dans le registre : le plus récent en tête.
List<M> bulletinsVecteur() {
  final p = mm(mm(vecteurs()['gestes'])['paie']);
  List<M> ins(String k) => lm(mm(mm(mm(p[k])['ecart'])['inserts'])['bulletins']);
  return [...ins('generation4'), ...ins('generation9')];
}

/// Pose les bulletins de la maquette dans le magasin (fiches actives, comme après « Générer »).
void poserBulletins(Magasin m) {
  final col = m.collection('bulletins');
  for (final b in bulletinsVecteur().reversed) {
    col.inserer({...b, 'statut': 'actif'});
  }
}
