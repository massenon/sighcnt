import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'm10_aide.dart';
import 'parite/extracteur.dart';

/// Aides communes aux tests de M10 (C) : badges, événements et participations, assurance du personnel, rotation sécurité & entretien. Les écrans sont montés sur le MAGASIN du poste,
/// à l'horloge du 30/10/2026 10 h, et rejouent les vecteurs `rhc.json` tirés des écrans RÉELS pilotés dans Chrome (prototype_html/build/vecteurs-rh-c.js).
final vc = obj(jsonDecode(File('../../packages/domaine/test/vecteurs/rhc.json').readAsStringSync()));

const collectionsRhc = ['personnel', 'planning', 'regimesTravail', 'patients', 'consultations', 'demandesAnalyses', 'admissions', 'evenements', 'participations', 'badges', 'modelesBadge'];

/// Un poste portant le jeu de ces écrans (+ les référentiels statiques de la maquette : `D.ANALYSES`).
Magasin posteRhc([Map<String, List<M>> remplace = const {}]) => Magasin({
      'audit': const [],
      for (final n in collectionsRhc) n: [for (final x in (remplace[n] ?? jeu(n))) {...x}],
    }, 'POSTE', (jsonDecode(File('assets/donnees/jeu/referentiels.json').readAsStringSync()) as Map).cast<String, Object?>());

/// Les libellés d'indicateurs affichés (libellé → valeur) et leurs indices.
Map<String, String> kpisRhc(WidgetTester t) => {for (final k in t.widgetList<KpiSigh>(find.byType(KpiSigh))) k.libelle: k.valeur};

/// N1 : la parité de CONTENU de l'écran [id] avec la fiche extraite de la maquette — retourne les libellés manquants.
List<String> manquantsN1(WidgetTester t, String id) {
  final f = (jsonDecode(File('../../docs/architecture/ecrans/$id.json').readAsStringSync()) as Map).cast<String, Object?>();
  return comparerContenu(id, f, textesVisibles(t)).manquants;
}

/// Une cellule est présente à l'écran (espaces ôtés).
void presentes(WidgetTester t, Iterable<Object?> cellules, {String raison = ''}) => cellulesAffichees(t, cellules, raison: raison);

Future<void> fermerToasts(WidgetTester t) async {
  await t.pump(const Duration(seconds: 10));
}

/// Les cellules du premier tableau de la maquette (`tableaux[0].lignes`), colonne [i] de la ligne [l].
List<List<String>> lignesTableau(Object? ecran, [int tableau = 0]) => [
      for (final l in ((obj((obj(ecran)['tableaux'] as List)[tableau]))['lignes'] as List)) [for (final c in (l as List)) '$c']
    ];

/// Appuie sur un bouton par son libellé visible ou son infobulle.
Future<void> appuyer(WidgetTester t, String libelle) async {
  final f = find.widgetWithText(BoutonSigh, libelle);
  await cliquer(t, f.evaluate().isNotEmpty ? f.last : find.byTooltip(libelle).first);
}
