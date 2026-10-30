import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/jetons_shell.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'hos_aide.dart';
import 'parite/extracteur.dart';

/// `m3-plan-lits` : le registre d'admissions de la maquette (`vecteurs.admissions.etatFinal`) est monté ; chaque lit doit porter le texte et la couleur
/// que la maquette a affichés, les KPI et les deux graphiques leurs valeurs, les tiroirs leurs phrases.
Map<String, Object?> adm() => carte(vecteurs['admissions']);
Map<String, Object?> plan() => carte(adm()['plan']);

Magasin magasinEssai({List<Fiche> factures = const []}) => Magasin({
      'admissions': [for (final x in liste(adm()['etatFinal'])) {...x}],
      'factures': factures,
      'audit': const [],
    }, 'POSTE');

Color? couleurDuPoint(WidgetTester t, String lit) {
  final c = t.widget<Container>(find.byKey(Key('plan:point:$lit')));
  return (c.decoration as BoxDecoration).color;
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  cas('KPI, texte et couleur de chacun des 19 lits identiques à la maquette', (t) async {
    await ouvrir(t, magasinEssai(), 'm3-plan-lits');
    for (final k in liste(plan()['kpis'])) {
      final w = t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == k['libelle']));
      expect(sansEspaces(w.valeur), sansEspaces(k['valeur']), reason: '${k['libelle']}');
    }
    final lits = liste(plan()['lits']);
    expect(lits.length, 19);
    final messages = [for (final w in t.widgetList<Tooltip>(find.byType(Tooltip))) w.message];
    const couleurs = {
      'success': JetonsShell.success500,
      'danger': JetonsShell.danger500,
      'warning': JetonsShell.warning500,
    };
    for (final l in lits) {
      final texte = '${l['texte']}';
      expect(messages, contains(texte), reason: texte);
      final lit = RegExp(r'^[A-D]\d LIT\d').firstMatch(texte)![0]!;
      expect(couleurDuPoint(t, lit), couleurs[l['couleur']], reason: '$lit : ${l['couleur']}');
    }
    for (final aile in (plan()['cartes'] as List).cast<String>()) {
      expect(affiche(t, aile), isTrue, reason: aile);
    }
    expect(affiche(t, 'Sortie prévue (séjour > 5 jours)'), isTrue);
  });

  cas('graphiques : séries empilées par type de chambre et durée moyenne de séjour sur douze mois, valeurs de la maquette', (t) async {
    await ouvrir(t, magasinEssai(), 'm3-plan-lits');
    final g = liste(plan()['graphiques']);
    final barres = t.widget<GraphiqueBarres>(find.byType(GraphiqueBarres));
    final a0 = (g[0]['args'] as List);
    expect(barres.empile, isTrue);
    expect(barres.etiquettes, (a0[0] as List).cast<String>());
    final series0 = liste(a0[1]);
    expect([for (final s in barres.series) s.libelle], [for (final s in series0) s['label']]);
    expect([for (final s in barres.series) s.donnees], [for (final s in series0) (s['data'] as List).cast<num>()]);
    final ligne = t.widget<GraphiqueLigne>(find.byType(GraphiqueLigne));
    final a1 = (g[1]['args'] as List);
    expect(ligne.etiquettes, (a1[0] as List).cast<String>());
    expect(ligne.series.single.donnees, (liste(a1[1]).single['data'] as List).cast<num>());
  });

  cas('un lit libre ouvre sa fiche : tarif du type, état libre, lien vers la création d\'admission', (t) async {
    await ouvrir(t, magasinEssai(), 'm3-plan-lits');
    await toucher(t, find.byKey(const Key('plan:lit:A1 LIT1')));
    final txt = '${carte(plan()['tiroirOccupe'])['texte']}';
    expect(txt, contains('Tarif journalier 5 000 FCFA'));
    for (final f in ['Lit A1 LIT1', 'Aile A — Médecine — Standard', 'Ce lit est disponible pour une nouvelle admission.']) {
      expect(affiche(t, f), isTrue, reason: f);
    }
    expect(affiche(t, '5 000 FCFA'), isTrue);
    expect(find.widgetWithText(BoutonSigh, 'Créer une admission'), findsOneWidget);
    await fermerDessus(t);
    await toucher(t, find.byKey(const Key('plan:lit:C2 LIT1')));
    expect(affiche(t, '15 000 FCFA'), isTrue, reason: 'tarif VIP');
  });

  cas('un lit occupé depuis plus de cinq jours : fiche du séjour, RG-06 soldé, liens vers la feuille de température et la sortie', (t) async {
    await ouvrir(t, magasinEssai(), 'm3-plan-lits');
    await toucher(t, find.byKey(const Key('plan:lit:A3 LIT2')));
    final long = '${carte(plan()['tiroirLong'])['texte']}';
    for (final f in [
      'N’TCHA Yacoubou',
      'CNT/3/26 — Lit A3 LIT2',
      '10/08/2026',
      '6 jour(s)',
      'Diagnostic 7',
      'RG-06 — Solde apuré : la sortie peut être finalisée.'
    ]) {
      expect(long.replaceAll(RegExp(r'\s'), ''), contains(f.replaceAll(RegExp(r'\s'), '')), reason: 'vecteur : $f');
      expect(affiche(t, f), isTrue, reason: f);
    }
    expect(find.widgetWithText(BoutonSigh, 'Feuille de température'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Préparer la sortie'), findsOneWidget);
  });

  cas('RG-06 : un solde dû est annoncé sur la fiche du lit, avec le montant', (t) async {
    final m = magasinEssai(factures: [
      {'id': 'FX1', 'statut': 'actif', 'patientId': 'PAT0003', 'reliquat': 5000},
      {'id': 'FX2', 'statut': 'actif', 'patientId': 'PAT0003', 'reliquat': 2500},
    ]);
    await ouvrir(t, m, 'm3-plan-lits');
    await toucher(t, find.byKey(const Key('plan:lit:A3 LIT2')));
    expect(affiche(t, 'RG-06 — Solde restant dû de 7 500 FCFA. La sortie ne pourra être finalisée qu’après apurement, sauf dérogation motivée de la Direction.'), isTrue);
  });

  cas('le plan suit les admissions : une sortie libère le lit (vert), une admission le reprend, et le taux d\'occupation suit', (t) async {
    final m = magasinEssai();
    await ouvrir(t, m, 'm3-plan-lits');
    final col = m.collection('admissions');
    final occupant = col.actives.firstWhere((a) => a['statut'] == 'en_cours' && a['lit'] == 'C1 LIT1');
    expect(couleurDuPoint(t, 'C1 LIT1'), JetonsShell.danger500);
    col.mettreAJour(occupant['id'], {'statut': 'sortie', 'dateSortie': '2026-08-16'});
    await t.pump();
    expect(couleurDuPoint(t, 'C1 LIT1'), JetonsShell.success500);
    final kpi = t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == 'Lits occupés'));
    expect(kpi.valeur, '5');
    expect(couleurDuPoint(t, 'A3 LIT2'), JetonsShell.warning500, reason: 'plus de cinq jours : sortie prévue');
  });

  cas('parité N1 = 100 % contre la fiche de la maquette (jeu complet, au jour où la fiche a été tirée)', (t) async {
    final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
    await ouvrir(t, m, 'm3-plan-lits', le: DateTime(2026, 10, 30, 10));
    final fiche = (jsonDecode(File('../../docs/architecture/ecrans/m3-plan-lits.json').readAsStringSync()) as Map).cast<String, Object?>();
    final p = comparerContenu('m3-plan-lits', fiche, textesVisibles(t));
    expect(p.manquants, isEmpty, reason: 'taux ${p.taux}');
  });
}
