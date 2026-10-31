import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart' show BoutonSigh;
import 'package:sigh_poste/main.dart';

/// Aides communes des tests des tableaux de bord par poste (DASH). Les attendus sont les RELEVÉS de l'écran réel de la maquette
/// (`prototype_html/build/vecteurs-dash.js` → `packages/domaine/test/vecteurs/tba_dash.json`), horloge au 16/08/2026 midi (celle du banc).
final donnees = DonneesNavigation.depuisDossier();
final aujourdhui = DateTime(2026, 8, 16, 12);

typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List? ?? const [])) obj(x)];

M vecteurs() => obj(obj(jsonDecode(File('../../packages/domaine/test/vecteurs/tba_dash.json').readAsStringSync()))['ecrans']);

/// Espaces fines et insécables du formatage français → espace ordinaire (le pilote de la maquette a normalisé les siennes).
String sp(String s) => s.replaceAll(RegExp(r'[\s  ]+'), ' ').trim();

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

Future<void> finir(WidgetTester t) async => t.pump(const Duration(seconds: 10));

/// Tous les textes affichés, espaces normalisées.
List<String> textes(WidgetTester t) => [
      for (final w in t.widgetList<Text>(find.byType(Text)))
        if ((w.data ?? w.textSpan?.toPlainText()) case final d? when d.trim().isNotEmpty) sp(d)
    ];

/// Les indicateurs de l'écran : (libellé, valeur, indice), dans l'ordre de lecture.
List<(String, String)> kpis(WidgetTester t) {
  final l = [for (final w in t.widgetList<Text>(find.byKey(const Key('kit:kpi-libelle')))) sp(w.data!)];
  final v = [for (final w in t.widgetList<Text>(find.byKey(const Key('kit:kpi-valeur')))) sp(w.data!)];
  return [for (var i = 0; i < l.length; i++) (l[i], v[i])];
}

M? bloc(M v, String cle) => [for (final b in liste(v['blocs'])) if (b[cle] != null) b].firstOrNull;

List<M> cartesVecteur(M v) => [for (final b in liste(v['blocs'])) ...liste(b['cartes'])];

/// Compare ce que l'écran Flutter affiche au relevé de la maquette : premier regard, indicateurs, titres de carte (chiffres neutralisés), cellules des
/// tableaux, raccourcis, parcours (étapes, pastilles de poste, étapes fermées au profil, bouton d'ouverture).
void comparer(WidgetTester t, M v, {bool parcours = true}) {
  final tx = textes(t);
  bool a(String s) => tx.any((x) => x == sp(s) || x.contains(sp(s)));
  final neutres = [for (final x in tx) x.replaceAll(RegExp(r'\d+'), '#')];
  expect(sp(v['titre'] as String), isNotEmpty);

  // Premier regard.
  final pr = bloc(v, 'premierRegard');
  if (pr != null) {
    final p = obj(pr['premierRegard']);
    expect(a('${p['ligne']}'), isTrue, reason: 'premier regard : « ${p['ligne']} »');
    if (p['note'] != null) expect(a('${p['note']}'), isTrue, reason: 'premier regard : note');
    final lien = p['lien'] == null ? null : obj(p['lien']);
    if (lien != null) expect(a('${lien['libelle']}'), isTrue, reason: 'lien du premier regard');
  }
  // Indicateurs.
  final attendus = [for (final k in liste(bloc(v, 'kpis')!['kpis'])) (sp('${k['label']}'), sp('${k['valeur']}'))];
  expect(kpis(t), attendus, reason: 'indicateurs');
  for (final k in liste(bloc(v, 'kpis')!['kpis'])) {
    if (k['indice'] != null) expect(a('${k['indice']}'), isTrue, reason: 'indice de ${k['label']}');
  }

  for (final c in cartesVecteur(v)) {
    final titre = sp('${c['titre']}').replaceAll(RegExp(r'\d+'), '#');
    expect(neutres.any((x) => x == titre || x.contains(titre)), isTrue, reason: 'carte « ${c['titre']} »');
    for (final tb in liste(c['tables'])) {
      for (final e in (tb['entetes'] as List)) {
        expect(a('$e'), isTrue, reason: 'en-tête « $e » de « ${c['titre']} »');
      }
      for (final (i, l) in (tb['lignes'] as List).indexed) {
        for (final cell in (l as List)) {
          final s = sp('$cell');
          if (s.isEmpty || s == '—') continue;
          // Une cellule peut empiler deux textes (patient + code du dossier) que `innerText` a mis bout à bout : on accepte la coupure en deux.
          final coupee = a(s) || [for (var k = 1; k < s.length; k++) a(s.substring(0, k).trim()) && a(s.substring(k).trim())].any((x) => x);
          expect(a(s) || coupee, isTrue, reason: 'cellule « $s » (ligne $i) de « ${c['titre']} »');
        }
      }
    }
    for (final l in (c['classement'] as List)) {
      expect(a('${(l as List)[0]}'), isTrue, reason: 'classement : ${l[0]}');
    }
    for (final lien in liste(c['liens'])) {
      expect(a('${lien['libelle']}'), isTrue, reason: 'lien de carte « ${lien['libelle']} »');
    }
    for (final r in liste(c['raccourcis'])) {
      expect(a('${r['libelle']}'), isTrue, reason: 'raccourci « ${r['libelle']} »');
      if (r['detail'] != null) expect(a('${r['detail']}'), isTrue, reason: 'détail du raccourci « ${r['libelle']} »');
    }
    if (parcours) {
      for (final g in liste(c['parcours'])) {
        expect(find.byKey(Key('tba:parcours:${g['titre']}')), findsOneWidget, reason: 'parcours « ${g['titre']} »');
        for (final e in liste(g['etapes'])) {
          expect(a('${e['libelle']}'), isTrue, reason: 'étape « ${e['libelle']} »');
          if (e['poste'] != null) expect(a('${e['poste']}'), isTrue, reason: 'poste « ${e['poste']} »');
          if (e['detail'] != null) expect(a('${e['detail']}'), isTrue, reason: 'détail de « ${e['libelle']} »');
        }
        // L'étape qui ouvre un écran est cliquable SSI l'écran est ouvert au profil : le relevé dit lesquelles sont fermées.
        final fermees = liste(g['etapes']).where((e) => e['ferme'] == true).length;
        final cliquables = liste(g['etapes']).where((e) => e['ecran'] != null && e['ferme'] != true).length;
        final dansCarte = find.byKey(Key('tba:parcours:${g['titre']}'));
        expect(find.descendant(of: dansCarte, matching: find.text('— fermé à votre profil')).evaluate().length, fermees,
            reason: 'étapes fermées de « ${g['titre']} »');
        final liens = find.descendant(of: dansCarte, matching: find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('tba:etape:')));
        expect(liens.evaluate().length, cliquables, reason: 'étapes cliquables de « ${g['titre']} »');
        // Le bouton porte la PREMIÈRE action — et n'existe pas si cette étape-là est fermée (commande interdite ABSENTE).
        final act = g['action'];
        final boutons = find.descendant(of: dansCarte, matching: find.byType(BoutonSigh));
        expect(boutons.evaluate().length, act == null ? 0 : 1, reason: 'bouton d\'ouverture de « ${g['titre']} »');
        if (act != null) {
          expect(find.descendant(of: dansCarte, matching: find.text('${obj(act)['libelle']}')), findsWidgets, reason: 'libellé du bouton de « ${g['titre']} »');
        }
      }
    }
  }
}
