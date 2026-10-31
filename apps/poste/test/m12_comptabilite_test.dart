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

/// M12 — comptabilité de base : m12-dashboard, m12-plan-comptable, m12-journaux, m12-ecritures, m12-depenses, m12-grand-livre, m12-balance.
/// Les règles sont rejouées sur les vecteurs de la maquette (packages/domaine/test/cpa_comptabilite_test.dart) ; ici, l'ÉCRAN : la PARITÉ N1 mesurée
/// contre la fiche extraite de la maquette, puis ce qui est lu, saisi, refusé, écrit, journalisé — et ce qui n'est JAMAIS offert sans le droit.
const ecransCompta = [
  'm12-dashboard',
  'm12-plan-comptable',
  'm12-journaux',
  'm12-ecritures',
  'm12-depenses',
  'm12-grand-livre',
  'm12-balance',
];

Map<String, Object?> fiche(String id) =>
    (jsonDecode(File('../../docs/architecture/ecrans/$id.json').readAsStringSync()) as Map).cast<String, Object?>();

Magasin magasinComplet() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

String nt(Object? s) => '$s'.replaceAll(RegExp(r'[\s  ]+'), ' ').trim();

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, {String role = 'admin', DateTime? horloge}) =>
    ouvrirM14(t, m, ecran, role: role, horloge: horloge);

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('parité N1 : chaque libellé que la maquette affiche figure à l\'écran', () {
    for (final id in ecransCompta) {
      casM14('$id : N1 = 100 %', (t) async {
        final m = magasinComplet();
        await ouvrir(t, m, id);
        final p = comparerContenu(id, fiche(id), textesVisibles(t));
        expect(p.manquants, isEmpty, reason: '$id : ${p.presents}/${p.attendus}');
        expect(p.taux, 1.0);
      });
    }
  });

  group('m12-dashboard', () {
    casM14('les huit indicateurs sont CALCULÉS depuis les écritures de l\'exercice, l\'alerte compte les brouillons', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-dashboard');
      final e = cpaEcrituresExercice(m.collection('ecritures').actives, 2026);
      final td = cpaTableauDeBord(e);
      expect(find.textContaining('${td.brouillons} écriture(s) en brouillon à valider.'), findsOneWidget);
      expect(find.textContaining(money(td.chiffreAffaires)), findsWidgets);
      expect(find.textContaining(money(td.charges)), findsWidgets);
      expect(find.text(td.equilibre ? 'Équilibré' : money(td.ecart)), findsWidgets);
    });

    casM14('un déséquilibre est DIT : la note danger nomme l\'écart', (t) async {
      final m = magasinComplet();
      m.collection('ecritures').inserer({
        'numero': 'OD-2026-99999', 'date': '2026-10-30', 'journal': 'OD', 'compte': '601100', 'debit': 1234, 'credit': 0, 'statut': 'validee', 'origine': 'Saisie manuelle'
      });
      await ouvrir(t, m, 'm12-dashboard');
      final e = cpaEcrituresExercice(m.collection('ecritures').actives, 2026);
      expect(find.textContaining('RG-10 — déséquilibre constaté', findRichText: true), findsOneWidget);
      expect(find.textContaining(money(cpaTableauDeBord(e).ecart), findRichText: true), findsWidgets);
    });

    casM14('un exercice sans écriture ne casse pas l\'écran', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-dashboard', horloge: DateTime(2027, 3, 1, 10));
      expect(find.text('Trésorerie disponible'), findsOneWidget);
      expect(find.text('Équilibré'), findsWidgets);
    });
  });
}
