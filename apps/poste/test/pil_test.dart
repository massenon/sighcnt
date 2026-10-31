import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';
import 'parite/extracteur.dart';

/// PILOTAGE (PIL) — les treize écrans de statistiques et de tableaux de bord de la Direction. Les règles (filtres, durée moyenne sur les séjours terminés,
/// deux colonnes jamais additionnées, rapprochement arrêté, « non calculable » ≠ zéro, périodes calendaires…) sont rejouées sur les vecteurs de la maquette
/// (`packages/domaine/test/pilotage_test.dart`) ; ici, l'ÉCRAN : la parité N1, puis ce qui est lu, annoncé, refusé — et ce qui n'est JAMAIS inventé.
Map<String, Object?> fiche(String id) => (jsonDecode(File('../../docs/architecture/ecrans/$id.json').readAsStringSync()) as Map).cast<String, Object?>();

Magasin magasinComplet() => Magasin.depuisDossier(Magasin.collectionsDuJeu);
String nt(Object? s) => '$s'.replaceAll(RegExp(r'[\s  ]+'), ' ').trim();

/// Pose [valeur] dans le champ [champ] (un champ de date : la saisie est une chaîne ISO, comme celle que rend le sélecteur de dates).
Future<void> poserChamp(WidgetTester t, String champ, String valeur) async {
  final f = t.widgetList<FormulaireSigh>(find.byType(FormulaireSigh)).firstWhere((x) => x.controleur.champs.any((c) => c.nom == champ));
  f.controleur.poser(champ, valeur);
  await t.pump(const Duration(milliseconds: 300));
}

const ecrans = [
  'dash-direction',
  'dash-da',
  'dash-croise',
  'dash-admin',
  'm4-stats-maternite',
  'm2-stats-echographie',
  'm5-stats-examens',
  'm2-stats-consultations',
  'm3-stats-bloc',
  'm3-stats-hospitalisations',
  'm10-cout-agent',
  'm12-rentabilite-groupes',
  'm12-tableau-decisionnel',
];

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('parité N1', () {
    for (final id in ecrans) {
      casM14('$id : N1 = 100 %', (t) async {
        final m = magasinComplet();
        await ouvrirM14(t, m, id);
        final p = comparerContenu(id, fiche(id), textesVisibles(t));
        expect(p.manquants, isEmpty, reason: '$id : ${p.presents}/${p.attendus}');
        expect(p.taux, 1.0);
      });
    }
  });
}
