import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
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
///
/// E742 : les vecteurs `rhc.json` (participations) ont été tirés sur l'ANCIEN semis (toutes dues, sous la forme `agentId` / `regle`). Le jeu du poste porte désormais la forme que
/// l'écran écrit (`employeId` / `statutPaiement`) ; tant que `vecteurs-rh-c.js` n'est pas rejoué sur ce jeu corrigé, ces tests gardent le semis d'avant en fixture.
List<M> participationsAvantE742() => [for (final x in (jsonDecode(File('test/fixtures/m10_participations_avant_e742.json').readAsStringSync()) as List)) (x as Map).cast<String, Object?>()];

Magasin posteRhc([Map<String, List<M>> remplace = const {}]) => Magasin({
      'audit': const [],
      for (final n in collectionsRhc) n: [for (final x in (remplace[n] ?? (n == 'participations' ? participationsAvantE742() : jeu(n)))) {...x}],
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

/// L'agent connecté des tests (rôle `admin`) : la maquette tournait sous « BASSONGUI Chabi Séko » — les pièces de la maquette qui le nomment (auteur d'un retrait, d'un encaissement,
/// d'une vérification) se comparent avec ce nom-ci.
const utilisateurTest = 'Administrateur système';
const auteurMaquette = 'BASSONGUI Chabi Séko';
const champsAuteur = {'emisPar', 'retirePar', 'encaissePar', 'annulePar', '_creePar', '_modifiePar'};

int nombreFeuilles(WidgetTester t) => find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('rhc:feuille-planche')).evaluate().length;

/// Les indicateurs de la maquette (libellé, valeur, indice) : comme `kpisIdentiques`, mais les ESPACES ne comptent pas — la maquette a relevé son texte avec des espaces ordinaires,
/// le poste compose en typographie française (espace fine insécable entre les milliers, insécable avant la devise).
void kpisIdentiquesRhc(WidgetTester t, Object? attendus) {
  for (final k in liste(attendus)) {
    final w = t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == k['libelle']));
    expect(sansEspaces(w.valeur), sansEspaces(k['valeur']), reason: '${k['libelle']}');
    expect(sansEspaces(w.indice ?? ''), sansEspaces(k['indice'] ?? ''), reason: 'indice ${k['libelle']}');
  }
}

/// Appuie sur un bouton par son libellé visible ou son infobulle.
Future<void> appuyer(WidgetTester t, String libelle) async {
  final f = find.widgetWithText(BoutonSigh, libelle);
  await cliquer(t, f.evaluate().isNotEmpty ? f.last : find.byTooltip(libelle).first);
}
