import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'hos_aide.dart';
import 'parite/extracteur.dart';

/// `m3-observation` : le jeu d'essai de la maquette (`vecteurs.observation.jeu`) est monté à 16/08/2026 10 h. KPI, alerte de dépassement, occupation des
/// unités, tableaux, fiche, feuille imprimée, admission, relevé, orientation (dont l'admission ouverte) et prescription doivent être ce que la maquette
/// a affiché ou écrit.
Map<String, Object?> obs() => carte(vecteurs['observation']);

Magasin magasinEssai() {
  final a = carte(vecteurs['admissions']);
  return Magasin({
    'observations': [for (final x in liste(obs()['jeu'])) {...x}],
    'admissions': const [],
    'patients': [for (final p in liste(a['patients'])) {...p, 'statut': 'actif'}],
    'personnel': [
      for (final n in ((obs()['admission'] as Map)['optionsMedecin'] as List))
        {'id': 'M${(n as List)[0]}', 'statut': 'actif', 'nomComplet': n[0], 'fonction': 'medecin', 'poste': 'Médecin'},
      for (final n in ((obs()['admission'] as Map)['optionsInfirmier'] as List).take(3))
        {'id': 'I${(n as List)[0]}', 'statut': 'actif', 'nomComplet': n[0], 'fonction': 'infirmier', 'poste': 'Infirmier'},
    ],
    'audit': const [],
  }, 'POSTE');
}

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  cas('KPI, alerte de dépassement, occupation des unités et séjours en cours — identiques à la maquette', (t) async {
    await ouvrir(t, magasinEssai(), 'm3-observation');
    final e = carte(obs()['ecran']);
    for (final k in liste(e['kpis'])) {
      final w = t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == k['libelle']));
      expect(sansEspaces(w.valeur), sansEspaces(k['valeur']), reason: '${k['libelle']}');
      expect(w.indice ?? '', k['indice'] ?? '', reason: 'indice ${k['libelle']}');
    }
    expect(affiche(t, (e['notes'] as List).single as String), isTrue, reason: 'le dépassement des 24 h est SIGNALÉ');
    final tableaux = liste(e['tableaux']);
    for (final l in (tableaux[0]['lignes'] as List)) {
      final cellules = (l as List).cast<String>();
      final bande = sansEspaces(ligneDe(t, cellules[0]).join('|'));
      for (final x in cellules) {
        expect(bande.contains(sansEspaces(x)), isTrue, reason: 'unité ${cellules[0]} : « $x »');
      }
    }
    final vues = <String, int>{};
    for (final l in (tableaux[1]['lignes'] as List)) {
      final cellules = (l as List).cast<String>();
      final ref = cellules[0];
      final bande = sansEspaces(ligneDe(t, ref, rang: vues[ref] ?? 0).join('|')).replaceAll('|', '');
      for (final idx in [3, 4, 5, 6, 7]) {
        expect(bande.contains(sansEspaces(cellules[idx])), isTrue, reason: '$ref : « ${cellules[idx]} » absent de $bande');
      }
    }
    // l'ordre : entrée décroissante
    final ys = [for (final l in (tableaux[1]['lignes'] as List)) t.getTopLeft(find.text((l as List)[0] as String)).dy];
    expect(ys, orderedEquals([...ys]..sort()));
    expect(find.text('OBS-2026-0007'), findsNothing, reason: 'l\'observation archivée n\'est pas au registre');
    for (final o in (e['onglets'] as List).cast<String>()) {
      expect(affiche(t, o.replaceAll(RegExp(r'\d+$'), '')), isTrue, reason: o);
    }
  });

  cas('l\'onglet « Séjours clos » porte l\'issue de chaque séjour (badge de l\'orientation)', (t) async {
    await ouvrir(t, magasinEssai(), 'm3-observation');
    await toucher(t, find.text('Séjours clos').last);
    final clos = (liste(carte(obs()['ecran'])['closTableaux'])[1]['lignes'] as List);
    for (final l in clos) {
      final cellules = (l as List).cast<String>();
      final bande = sansEspaces(ligneDe(t, cellules[0]).join('|')).replaceAll('|', '');
      for (final idx in [3, 4, 5, 6, 7]) {
        expect(bande.contains(sansEspaces(cellules[idx])), isTrue, reason: '${cellules[0]} : « ${cellules[idx]} » absent de $bande');
      }
    }
    expect(find.byTooltip('Relever les constantes'), findsNothing, reason: 'un séjour clos ne se relève plus');
    expect(find.byTooltip('Imprimer la feuille'), findsNWidgets(2));
  });

  cas('fiche d\'un séjour dépassé : phrases, relevés, évolution (températures et pouls) et commandes — comme la maquette', (t) async {
    await ouvrir(t, magasinEssai(), 'm3-observation');
    await toucher(t, find.text('OBS-2026-0003').first);
    final f = carte(obs()['fiche']);
    for (final x in [
      'N’TCHA Yacoubou — Salle d’observation — médecine générale',
      'Entrée 15/08/2026 à 09h00',
      'Durée 25 h — au-delà de la référence',
      'Issue en cours',
    ]) {
      expect(sansEspaces('${f['texte']}').contains(sansEspaces(x)), isTrue, reason: 'vecteur : $x');
    }
    expect(affiche(t, '25 h — au-delà de la référence'), isTrue);
    expect(affiche(t, '15/08/2026 à 09h00'), isTrue);
    for (final lib in ['Relever les constantes', 'Prescrire', 'Imprimer la feuille', 'Décider de l’orientation']) {
      expect(find.widgetWithText(BoutonSigh, lib), findsOneWidget, reason: lib);
    }
    final tab = ((f['tables'] as List).single as Map)['lignes'] as List;
    for (final l in tab) {
      final cellules = (l as List).cast<String>();
      final bande = sansEspaces(ligneDe(t, cellules[0]).join('|'));
      for (final x in cellules.where((x) => x.isNotEmpty)) {
        expect(bande.contains(sansEspaces(x)), isTrue, reason: '${cellules[0]} : « $x »');
      }
    }
    final g = t.widget<GraphiqueLigne>(find.byType(GraphiqueLigne));
    final att = (liste(f['graphiques'])[0]['args'] as List);
    expect(g.etiquettes, (att[0] as List).cast<String>());
    expect([for (final s in g.series) s.libelle], [for (final s in liste(att[1])) s['label']]);
    expect([for (final s in g.series) s.donnees], [for (final s in liste(att[1])) (s['data'] as List).cast<num>()]);
    expect(g.series[1].aire, isFalse, reason: '`fill: false` sur le pouls');
  });

  cas('séjour sans relevé : « Aucun relevé enregistré. », pas d\'évolution, la durée n\'est pas dite dépassée', (t) async {
    await ouvrir(t, magasinEssai(), 'm3-observation');
    await toucher(t, find.text('OBS-2026-0002').first);
    expect(affiche(t, 'Aucun relevé enregistré.'), isTrue);
    expect(find.byType(GraphiqueLigne), findsNothing);
    expect(affiche(t, 'au-delà de la référence'), isFalse);
    expect(sansEspaces(carte(obs()['ficheSansReleve'])['texte']).contains(sansEspaces('Durée 20 h')), isTrue);
  });

  cas('feuille imprimée : cartouche, relevés, conclusion et signatures de la maquette', (t) async {
    await ouvrir(t, magasinEssai(), 'm3-observation');
    await toucher(t, find.text('OBS-2026-0003').first);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Imprimer la feuille'));
    final e = carte(obs()['etat']);
    expect(affiche(t, '${e['titre']}'), isTrue);
    expect(affiche(t, '${e['sousTitre']}'), isTrue);
    for (final c in (e['cartouche'] as List)) {
      expect(affiche(t, '${(c as List)[1]}'), isTrue, reason: '${c[0]}');
    }
    for (final s in liste(e['signatures'])) {
      expect(affiche(t, '${s['role']}'), isTrue);
    }
    for (final l in (((e['tableaux'] as List).single as Map)['lignes'] as List)) {
      expect(affiche(t, '${(l as List)[1]}'), isTrue, reason: 'température ${l[1]}');
    }
  });

  cas('mise en observation : unités et places libres annoncées, formulaire sans motif refusé ; fiche créée = celle de la maquette, annulable', (t) async {
    final m = magasinEssai();
    await ouvrir(t, m, 'm3-observation');
    final col = m.collection('observations');
    final avant = col.actives.length;
    await toucher(t, find.widgetWithText(BoutonSigh, 'Mettre en observation'));
    final a = carte(obs()['admission']);
    for (final lib in (a['champs'] as List).cast<String>()) {
      expect(affiche(t, lib.replaceAll(' *', '')), isTrue, reason: lib);
    }
    expect(affiche(t, 'L’heure d’entrée est tracée'), isTrue);
    await toucher(t, find.descendant(of: find.byKey(const Key('kit:champ:unite')), matching: find.byType(InkWell)).first);
    for (final o in (a['optionsUnite'] as List)) {
      expect(find.text('${(o as List)[1]}'), findsWidgets, reason: '${o[1]}');
    }
    await fermerDessus(t);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Mettre en observation').last);
    expect(col.actives.length, avant, reason: 'motif manquant : rien n\'est écrit');
    expect(find.text('Ce champ est obligatoire.'), findsWidgets);
    await choisir(t, 'patientCode', 'CNT/4/26 — PARAISO Sabi');
    await choisir(t, 'unite', 'Salle d’observation — pédiatrie (2 place(s) libre(s))');
    await saisir(t, 'motif', 'Malaise');
    await saisir(t, 'place', 'P2');
    await saisir(t, 'heureEntree', '08:30');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Mettre en observation').last);
    expect(col.actives.length, avant + 1);
    final f = col.actives.first;
    final att = carte(carte(a['cree'])['fiche']);
    for (final k in ['statut', 'reference', 'patientId', 'patient', 'patientCode', 'unite', 'uniteLabel', 'place', 'motif', 'dateEntree', 'medecin', 'statutObservation']) {
      expect(f[k], att[k], reason: k);
    }
    expect(f['infirmier'], isNull);
    expect(f['constantes'], isEmpty);
    for (final ligne in ((carte(a['cree'])['toasts'] as List).single as List).cast<String>()) {
      expect(find.text(ligne), findsOneWidget);
    }
    await toucher(t, find.text('Annuler'));
    expect(col.parId(f['id'])!['statut'], 'archive', reason: 'RG-14');
  });

  cas('relevé de constantes : ajouté à la feuille (nombres lus comme Number, saturation vide → null), toast de la maquette, annulable', (t) async {
    final m = magasinEssai();
    await ouvrir(t, m, 'm3-observation');
    final col = m.collection('observations');
    await toucher(t, find.byTooltip('Relever les constantes').at(2)); // ligne OBS-2026-0003
    final r = carte(obs()['releve']);
    for (final lib in (r['champs'] as List).cast<String>()) {
      expect(affiche(t, lib.replaceAll(' *', '')), isTrue, reason: lib);
    }
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer le relevé'));
    expect((col.parId('OBS0003')!['constantes'] as List).length, 3, reason: 'champs obligatoires vides : rien n\'est écrit');
    await saisir(t, 'heure', '09:45');
    await saisir(t, 'temperature', '38.2');
    await saisir(t, 'tension', '11/7');
    await saisir(t, 'pouls', '90');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer le relevé'));
    final cs = (col.parId('OBS0003')!['constantes'] as List).cast<Map>();
    expect(cs.length, 4);
    final att = ((carte(r['enregistre'])['constantes'] as List).last as Map);
    final n = cs.last;
    for (final k in ['heure', 'temperature', 'tension', 'pouls', 'spo2', 'observation']) {
      expect(n[k], att[k], reason: k);
    }
    for (final ligne in ((carte(r['enregistre'])['toasts'] as List).single as List).cast<String>()) {
      expect(find.text(ligne), findsOneWidget);
    }
    await toucher(t, find.text('Annuler'));
    expect((col.parId('OBS0003')!['constantes'] as List).length, 3);
  });

  cas('orientation « domicile » : le séjour est clos avec sa conclusion et l\'heure ; aucune admission n\'est ouverte', (t) async {
    final m = magasinEssai();
    await ouvrir(t, m, 'm3-observation');
    final col = m.collection('observations');
    await toucher(t, find.byTooltip('Décider de l’orientation').at(2));
    final o = carte(obs()['orientation']);
    for (final lib in (o['champs'] as List).cast<String>()) {
      expect(affiche(t, lib.replaceAll(' *', '')), isTrue, reason: lib);
    }
    expect(affiche(t, 'Une hospitalisation complète ouvre une admission dans le module M3'), isTrue);
    for (final opt in (o['optionsOrientation'] as List)) {
      // la liste des décisions est celle de la maquette
      expect(sansEspaces('${o['texte']}').contains(sansEspaces('${(opt as List)[1]}')), isTrue);
    }
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer la décision'));
    expect(col.parId('OBS0003')!['statutObservation'], 'en_cours', reason: 'sans conclusion : rien n\'est écrit');
    await saisir(t, 'conclusion', 'Évolution favorable');
    await saisir(t, 'heureSortie', '09:50');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer la décision'));
    final f = col.parId('OBS0003')!;
    final att = carte(carte(o['domicile'])['fiche']);
    for (final k in ['statutObservation', 'orientation', 'orientationLabel', 'conclusion', 'dateSortie', 'decidePar']) {
      expect(f[k], att[k], reason: k);
    }
    expect(f['destination'], isNull);
    expect(m.collection('admissions').toutes, isEmpty);
    expect(find.text('Orientation enregistrée — Sortie définitive — retour à domicile.'), findsOneWidget);
    expect(m.collection('audit').actives.any((l) => l['action'] == 'Orientation d’observation' && l['reference'] == 'OBS-2026-0003'), isTrue,
        reason: 'RG-12 : la décision est journalisée');
  });

  cas('orientation « hospitalisation complète » : une admission s\'ouvre (origine = l\'observation), les deux restent distinctes ; annuler défait les deux', (t) async {
    final m = magasinEssai();
    await ouvrir(t, m, 'm3-observation');
    final col = m.collection('observations');
    final adm = m.collection('admissions');
    await toucher(t, find.byTooltip('Décider de l’orientation').first); // OBS-2026-0001
    await choisir(t, 'orientation', 'Hospitalisation complète');
    await saisir(t, 'conclusion', 'Aggravation constatée');
    await saisir(t, 'heureSortie', '09:55');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer la décision'));
    final h = carte(carte(obs()['orientation'])['hospitalisation']);
    final f = col.parId('OBS0001')!;
    for (final k in ['statutObservation', 'orientation', 'orientationLabel', 'conclusion', 'dateSortie', 'decidePar']) {
      expect(f[k], carte(h['fiche'])[k], reason: k);
    }
    expect(adm.toutes.length, h['admissionsCreees']);
    final a = adm.toutes.first;
    final att = carte(h['admission']);
    for (final k in ['statut', 'reference', 'patientId', 'patient', 'patientCode', 'dateEntree', 'diagnosticEntree', 'symptomes', 'priseEnCharge', 'infirmier', 'origineObservation']) {
      expect(a[k], att[k], reason: k);
    }
    for (final ligne in ((h['toasts'] as List).single as List).cast<String>()) {
      expect(find.text(ligne), findsOneWidget);
    }
    await toucher(t, find.text('Annuler'));
    expect(col.parId('OBS0001')!['statutObservation'], 'en_cours');
    expect(adm.actives, isEmpty, reason: 'l\'annulation archive l\'admission ouverte (RG-14)');
  });

  cas('prescription pendant l\'observation : l\'ordonnance, la demande d\'analyse (secteur = l\'unité) et la facture naissent d\'un geste ; rien de choisi → refus dit', (t) async {
    final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
    await ouvrir(t, m, 'm3-observation', le: DateTime(2026, 10, 30, 10));
    final col = m.collection('observations');
    final o = col.actives.firstWhere((x) => x['statutObservation'] == 'en_cours');
    final ord = m.collection('ordonnances').toutes.length;
    final dem = m.collection('demandesAnalyses').toutes.length;
    final fac = m.collection('factures').toutes.length;
    await toucher(t, find.text('${o['reference']}').first);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Prescrire'));
    expect(affiche(t, 'Prescriptions ciblées : bilans de contrôle et soins rapides'), isTrue);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Prescrire et transmettre'));
    expect(find.text('Choisir au moins un examen ou un soin.'), findsOneWidget);
    expect(m.collection('ordonnances').toutes.length, ord);
    await t.pump(const Duration(seconds: 10));
    final analyse = m.referentiel('analyses').first;
    await toucher(t, find.descendant(of: find.byKey(const Key('kit:champ:analyses')), matching: find.byType(InkWell)).first);
    await t.enterText(find.byType(TextField).last, '${analyse['designation']}');
    await t.pump(const Duration(milliseconds: 300));
    await toucher(t, find.text('${analyse['designation']}').last);
    await fermerDessus(t);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Prescrire et transmettre'));
    expect(m.collection('ordonnances').toutes.length, ord + 1);
    expect(m.collection('demandesAnalyses').toutes.length, dem + 1);
    expect(m.collection('factures').toutes.length, fac + 1);
    final d = m.collection('demandesAnalyses').toutes.first;
    expect(d['secteurDemandeur'], o['uniteLabel'], reason: 'le secteur prescripteur est porté par la demande (RBAC métier)');
    expect(m.collection('ordonnances').toutes.first['diagnostic'], 'Observation — ${o['motif']}');
    expect(find.textContaining('transmise.'), findsOneWidget);
  });

  cas('droits : un profil en lecture voit la surveillance mais n\'a ni « Mettre en observation », ni relevé, ni orientation (E372)', (t) async {
    await ouvrir(t, magasinEssai(), 'm3-observation', role: 'reception');
    expect(affiche(t, 'Occupation des unités d’observation'), isTrue);
    expect(find.widgetWithText(BoutonSigh, 'Mettre en observation'), findsNothing);
    expect(find.byTooltip('Relever les constantes'), findsNothing);
    expect(find.byTooltip('Décider de l’orientation'), findsNothing);
    expect(find.byTooltip('Imprimer la feuille'), findsWidgets);
    await toucher(t, find.text('OBS-2026-0003').first);
    expect(find.widgetWithText(BoutonSigh, 'Prescrire'), findsNothing);
    expect(find.widgetWithText(BoutonSigh, 'Décider de l’orientation'), findsNothing);
    expect(find.widgetWithText(BoutonSigh, 'Imprimer la feuille'), findsOneWidget);
  });

  cas('parité N1 = 100 % contre la fiche de la maquette (jeu complet, observations amorcées comme la maquette)', (t) async {
    final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
    expect(m.collection('observations').actives.length, 18, reason: 'le jeu porte les 18 séjours amorcés à l\'ouverture de l\'écran');
    await ouvrir(t, m, 'm3-observation', le: DateTime(2026, 10, 30, 10));
    final fiche = (jsonDecode(File('../../docs/architecture/ecrans/m3-observation.json').readAsStringSync()) as Map).cast<String, Object?>();
    final p = comparerContenu('m3-observation', fiche, textesVisibles(t));
    expect(p.manquants, isEmpty, reason: 'taux ${p.taux}');
  });
}
