import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show HosCourbe;
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/m3/surv_surveillance.dart' show PeintreCourbe;

import 'aide_polices.dart';
import 'm3_surv_aide.dart';
import 'parite/extracteur.dart';

/// `m3-surveillance` : l'écran rejoue les vecteurs de la maquette (`hospitalisation.json`, groupe `surveillance`, tiré de l'écran réel piloté dans
/// Chrome, dessin SVG intercepté). Deux sources (accueil + lit du patient), une série ; cinq échelles dont le pouls non linéaire ; mesure absente non tracée.
final v = dico(lireVecteurs('hospitalisation.json')['surveillance']);

Magasin magasin({bool vide = false}) {
  final pats = liste(v['patients']);
  return Magasin({
    'patients': pats,
    'admissions': vide
        ? const []
        : [
            for (var i = 0; i < 2; i++) {'id': 'ADM${i + 1}', 'statut': 'en_cours', 'patientId': pats[i]['id']}
          ],
    'constantes': vide ? const [] : [for (final x in liste(v['constantes'])) {...x}],
    'releves': vide ? const [] : [for (final x in liste(v['releves'])) {...x}],
    'audit': const [],
  }, 'POSTE');
}

HosCourbe courbe(WidgetTester t) =>
    (t.widget<CustomPaint>(find.byKey(const Key('m3:courbe'))).painter as PeintreCourbe).courbe;

void verifierTable(WidgetTester t, Map<String, Object?> groupe) {
  final lignes = (dico((groupe['tableaux'] as List).single)['lignes'] as List).cast<List>();
  final tab = t.widget<TableauSigh>(find.byType(TableauSigh));
  expect(tab.lignes.length, lignes.length);
  for (var i = 0; i < lignes.length; i++) {
    for (var j = 0; j < 10; j++) {
      final col = tab.colonnes[j];
      final texte = col.texte != null ? col.texte!(tab.lignes[i]) : '${tab.lignes[i][col.cle] ?? ''}';
      expect(texte, lignes[i][j], reason: 'ligne $i, colonne ${col.libelle}');
    }
  }
}

void verifierDessin(WidgetTester t, Map<String, Object?> dessin) {
  final c = courbe(t);
  final taille = t.getSize(find.byKey(const Key('m3:courbe')));
  expect(taille.width, (dessin['largeur'] as num).toDouble());
  expect(taille.height, (dessin['hauteur'] as num).toDouble());
  final pl = liste(dessin['polylignes']);
  var total = 0;
  var k = 0;
  for (final code in c.polylignes.keys) {
    final pts = c.polylignes[code]!;
    total += pts.length;
    if (pts.length > 1) {
      final att = '${pl[k]['points']}'.split(' ').map((p) => p.split(',').map(double.parse).toList()).toList();
      expect(pts.length, att.length, reason: code);
      for (var i = 0; i < pts.length; i++) {
        expect(pts[i].x, closeTo(att[i][0], 1e-6), reason: code);
        expect(pts[i].y, closeTo(att[i][1], 1e-6), reason: code);
      }
      k++;
    }
  }
  expect(k, pl.length, reason: 'une polyligne par échelle à deux points ou plus');
  expect(total, (dessin['cercles'] as List).length, reason: 'un point par mesure PRÉSENTE (E365)');
}

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  cas('surveillance : KPI, cartes et relevés réunis (accueil + lit) identiques à la maquette', (t) async {
    await ouvrir(t, magasin(), 'm3-surveillance');
    final p = dico(v['premier']);
    for (final k in liste(p['kpis'])) {
      final w = t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == k['libelle']));
      expect(sans(w.valeur), sans(k['valeur']), reason: '${k['libelle']}');
      expect(w.indice, k['indice'], reason: 'indice ${k['libelle']}');
    }
    for (final c in (p['cartes'] as List)) {
      expect(find.text('$c'), findsOneWidget, reason: '$c');
    }
    verifierTable(t, p);
    // la source de chaque relevé est un badge : 2 de l'accueil, 9 du lit du patient (le menu porte aussi ces mots)
    final sources = [for (final b in t.widgetList<BadgeSigh>(find.byType(BadgeSigh))) b.libelle];
    expect(sources.where((x) => x == 'Accueil').length, 2);
    expect(sources.where((x) => x == 'Hospitalisation').length, 9);
  });

  cas('surveillance : la courbe à cinq échelles reprend les points de la maquette (pouls non linéaire, mesure absente non tracée)', (t) async {
    await ouvrir(t, magasin(), 'm3-surveillance');
    verifierDessin(t, dico(dico(v['premier'])['dessin']));
    final c = courbe(t);
    // six lignes de grille partagées par les cinq échelles
    expect(c.graduations, ['5 60 36 10 0', '10 80 37 20 0.5', '15 100 38 30 1', '20 120 39 40 1.5', '25 140 40 50 2', '30 180 41 60 2.5']);
    for (final leg in ['TA (cmHg) — 5 à 30', 'Pouls (bpm) — 60 à 180', 'T° (°C) — 36 à 41', 'FR (/min) — 10 à 60', 'Diurèse (L) — 0 à 2.5']) {
      expect(find.text(leg), findsOneWidget, reason: leg);
    }
    // E365 : la fréquence respiratoire non relevée (REL2, REL7) n'est pas tracée à zéro — 7 jours affichés, 9 colonnes remplies, 7 FR présentes
    expect(c.polylignes['fr']!.length, lessThan(c.polylignes['pouls']!.length));
  });

  cas('surveillance : changer de patient redessine la courbe et le tableau', (t) async {
    await ouvrir(t, magasin(), 'm3-surveillance');
    await choisir(t, 'patient', 'CNT/2/26 — BAKO Boukari');
    final s = dico(v['second']);
    expect(find.text('Feuille de température — BAKO Boukari'), findsOneWidget);
    verifierTable(t, s);
    verifierDessin(t, dico(s['dessin']));
  });

  cas('surveillance : sans constante, l\'écran le dit et renvoie au relevé', (t) async {
    await ouvrir(t, magasin(vide: true), 'm3-surveillance');
    expect(find.text('Aucune constante relevée.'), findsOneWidget);
    expect(find.textContaining('Les constantes se saisissent à l’accueil ou au lit du patient'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Relever des constantes'), findsOneWidget);
    expect(find.byType(KpiSigh), findsNothing);
  });

  cas('surveillance : parité N1 = 100 % contre la fiche de la maquette (jeu complet)', (t) async {
    await ouvrir(t, Magasin.depuisDossier(Magasin.collectionsDuJeu), 'm3-surveillance');
    final fiche = dico(jsonDecode(File('../../docs/architecture/ecrans/m3-surveillance.json').readAsStringSync()));
    final p = comparerContenu('m3-surveillance', fiche, textesVisibles(t));
    expect(p.manquants, isEmpty, reason: 'taux ${p.taux}');
  });
}
