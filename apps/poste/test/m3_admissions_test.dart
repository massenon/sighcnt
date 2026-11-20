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

/// `m3-admissions` : le jeu d'essai de la maquette (`vecteurs.admissions`) est monté ; KPI, lignes, tiroirs, création, refus nommés, modification et
/// bon d'admission doivent être ce que la maquette a AFFICHÉ ou ÉCRIT. Le jeu complet porte la parité N1.
Map<String, Object?> adm() => carte(vecteurs['admissions']);

Magasin magasinEssai() => Magasin({
      'admissions': [for (final x in liste(adm()['jeu'])) {...x}],
      'factures': [for (final x in liste(adm()['factures'])) {...x}],
      'patients': [for (final p in liste(adm()['patients'])) {...p, 'statut': 'actif'}],
      'personnel': [
        for (final n in ['GARBA Yahouza', 'IDRISSOU ANIKI Baba-Toundé', 'NKOUÉ Jean'])
          {'id': 'P$n', 'statut': 'actif', 'nomComplet': n, 'fonction': 'infirmier', 'poste': 'Infirmier'}
      ],
      'audit': const [],
    }, 'POSTE');

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  cas('KPI identiques à la maquette, lignes dans l\'ordre de la maquette (entrée décroissante), archivées exclues', (t) async {
    await ouvrir(t, magasinEssai(), 'm3-admissions');
    for (final k in liste(carte(adm()['ecran'])['kpis'])) {
      final w = t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == k['libelle']));
      expect(sansEspaces(w.valeur), sansEspaces(k['valeur']), reason: '${k['libelle']}');
    }
    final attendu = ((carte(adm()['ecran'])['tableaux'] as List).single as Map)['lignes'] as List;
    final tab = t.widget<TableauSigh>(find.byType(TableauSigh));
    expect(tab.lignes.length, attendu.length);
    // l'ORDRE affiché est celui de la maquette (entrée décroissante) : de haut en bas
    final hauts = [for (final l in attendu) t.getTopLeft(find.text((l as List)[1] as String)).dy];
    expect(hauts, orderedEquals([...hauts]..sort()), reason: 'ordre d\'affichage des références ${[for (final l in attendu) (l as List)[1]]}');
    for (final l in attendu) {
      final cellules = ligneDe(t, (l as List)[1] as String);
      final tout = sansEspaces(cellules.join('|'));
      for (final idx in [3, 4, 5, 6, 7, 8, 9]) {
        expect(tout.contains(sansEspaces(l[idx])), isTrue, reason: '${l[1]} : « ${l[idx]} » absent de $cellules');
      }
    }
    expect(find.text('H00006'), findsNothing, reason: 'l\'admission archivée n\'est pas au registre');
  });

  cas('tiroir : le solde dû (RG-06) est annoncé, une situation apurée aussi, une admission sortie n\'en parle pas', (t) async {
    await ouvrir(t, magasinEssai(), 'm3-admissions');
    await toucher(t, find.text('H00001'));
    expect(sansEspaces(carte(adm()['tiroirSolde'])['texte']).contains(sansEspaces('RG-06 — Reste à régler : 7 500 FCFA avant finalisation de la sortie.')), isTrue,
        reason: 'la phrase attendue est bien celle de la maquette');
    expect(affiche(t, 'RG-06 — Reste à régler : 7 500 FCFA avant finalisation de la sortie.'), isTrue);
    expect(find.widgetWithText(BoutonSigh, 'Modifier'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Archiver'), findsOneWidget);
    await fermerDessus(t);
    await toucher(t, find.text('H00002'));
    expect(affiche(t, 'RG-06 — Situation financière apurée.'), isTrue);
    expect(affiche(t, 'Reste à régler'), isFalse);
    await fermerDessus(t);
    await toucher(t, find.text('H00003'));
    expect(affiche(t, 'RG-06'), isFalse);
    expect(affiche(t, '02/08/2026'), isTrue, reason: 'date de sortie');
  });

  cas('création : champs de la maquette, valeurs par défaut, lits libres seulement ; formulaire vide refusé ; lit occupé refusé en le NOMMANT', (t) async {
    final m = magasinEssai();
    await ouvrir(t, m, 'm3-admissions');
    final col = m.collection('admissions');
    final avant = col.actives.length;
    await toucher(t, find.text('Nouveau'));
    final c = carte(adm()['creation']);
    for (final lib in (c['champs'] as List).cast<String>()) {
      expect(affiche(t, lib.replaceAll(' *', '')), isTrue, reason: lib);
    }
    // le lit proposé par défaut est le premier lit LIBRE (A1 LIT1 est occupé)
    await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
    // la maquette refuse un formulaire sans diagnostic (seul champ obligatoire resté vide : 7 champs, 6 défauts)
    expect(find.text(((carte(carte(adm()['creation'])['refusVide'])['toasts'] as List).single as List).single as String), findsOneWidget);
    expect(col.actives.length, avant, reason: 'diagnostic d\'entrée manquant : rien n\'est écrit');
    expect(find.text('Ce champ est obligatoire.'), findsOneWidget);
  });

  cas('création complète : fiche identique à celle de la maquette, référence lue sur le registre (E360), deuxième création H00009', (t) async {
    final m = magasinEssai();
    await ouvrir(t, m, 'm3-admissions');
    final col = m.collection('admissions');
    final avant = col.actives.length;
    await toucher(t, find.text('Nouveau'));
    await choisir(t, 'patientCode', 'CNT/2/26 — BAKO Boukari');
    await choisir(t, 'lit', 'A1 LIT2 — Aile A — Médecine (Standard)');
    await choisir(t, 'infirmier', 'IDRISSOU ANIKI Baba-Toundé — Infirmier');
    await saisir(t, 'diagnosticEntree', 'Paludisme grave');
    await saisir(t, 'symptomes', 'Fièvre');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
    expect(col.actives.length, avant + 1);
    final f = col.actives.first;
    final attendue = {...carte(carte(carte(adm()['creation'])['cree'])['fiche'])};
    for (final k in ['patientCode', 'lit', 'infirmier', 'dateEntree', 'priseEnCharge', 'diagnosticEntree', 'symptomes', 'patientId', 'patient', 'chambre', 'typeChambre', 'reference', 'statut']) {
      expect(f[k], attendue[k], reason: k);
    }
    expect(f['reference'], 'H00008');
    expect(find.text('Nouveau admission créé.'), findsOneWidget);
    expect(find.text('H00008'), findsWidgets, reason: 'la référence figure au toast');
    // deuxième création : la série avance (le compteur de page de la maquette redonnait H00008)
    await toucher(t, find.text('Nouveau'));
    await choisir(t, 'patientCode', 'CNT/3/26 — N’TCHA Yacoubou');
    await choisir(t, 'lit', 'B3 LIT1 — Aile B — Maternité (Standard)');
    await saisir(t, 'diagnosticEntree', 'Deuxième création');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
    expect(col.actives.first['reference'], carte(carte(carte(adm()['creation'])['deuxieme'])['fiche'])['reference']);
    expect(col.actives.first['reference'], 'H00009');
  });

  cas('un lit occupé est REFUSÉ en nommant l\'occupant (course entre l\'ouverture du formulaire et l\'enregistrement), rien n\'est écrit', (t) async {
    final m = magasinEssai();
    await ouvrir(t, m, 'm3-admissions');
    final col = m.collection('admissions');
    final avant = col.actives.length;
    await toucher(t, find.text('Nouveau'));
    // la liste ne présente que les lits libres
    await toucher(t, find.descendant(of: find.byKey(const Key('kit:champ:lit')), matching: find.byType(InkWell)).first);
    expect(find.text('A1 LIT1 — Aile A — Médecine (Standard)'), findsNothing);
    expect(find.text('A1 LIT2 — Aile A — Médecine (Standard)'), findsWidgets);
    await toucher(t, find.text('A1 LIT2 — Aile A — Médecine (Standard)').last);
    await saisir(t, 'diagnosticEntree', 'Essai');
    // entre-temps, un autre poste occupe ce lit
    col.inserer({'statut': 'en_cours', 'lit': 'A1 LIT2', 'patient': 'AUTRE Patient', 'reference': 'H00099'});
    await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
    expect(find.text('Le lit A1 LIT2 est déjà occupé par AUTRE Patient.'), findsOneWidget);
    expect(col.actives.length, avant + 1, reason: 'seule l\'insertion du test : rien n\'a été écrit par l\'écran');
    final refus = carte(carte(adm()['creation'])['refusLitOccupe'])['toasts'];
    expect(((refus as List).single as List).single, 'Le lit A1 LIT1 est déjà occupé par TCHANE Bertine.', reason: 'même forme de message que la maquette');
  });

  cas('modification : la référence reste (E360), la fiche prend le lit choisi ; un lit pris entre-temps est refusé en nommant l\'occupant, rien n\'est écrit', (t) async {
    final m = magasinEssai();
    await ouvrir(t, m, 'm3-admissions');
    final col = m.collection('admissions');
    await toucher(t, find.text('H00001'));
    await toucher(t, find.widgetWithText(BoutonSigh, 'Modifier'));
    expect(find.text('Modifier l’admission'), findsNothing);
    await saisir(t, 'diagnosticEntree', 'Diagnostic corrigé');
    await choisir(t, 'lit', 'A2 LIT2 — Aile A — Médecine (Standard)');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final f = col.parId('ADM1')!;
    final att = carte(carte(carte(adm()['modification'])['enregistre'])['fiche']);
    for (final k in ['reference', 'lit', 'chambre', 'typeChambre', 'diagnosticEntree', 'statut', 'patientCode', 'infirmier']) {
      expect(f[k], att[k], reason: k);
    }
    expect(find.text('Modifications enregistrées.'), findsOneWidget);
    // une AUTRE admission occupe le lit de ADM2 pendant que sa fiche est ouverte : refus nommé, fiche intacte
    await t.pump(const Duration(seconds: 10));
    await toucher(t, find.text('H00002'));
    await toucher(t, find.widgetWithText(BoutonSigh, 'Modifier'));
    col.inserer({'statut': 'en_cours', 'lit': 'C1 LIT1', 'patient': 'DOUBLON Patient', 'reference': 'H00098'});
    await saisir(t, 'diagnosticEntree', 'Ne doit pas passer');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    expect(find.text('Le lit C1 LIT1 est déjà occupé par DOUBLON Patient.'), findsOneWidget);
    expect(col.parId('ADM2')!['diagnosticEntree'], 'Diagnostic 2', reason: 'rien n\'est écrit sur un refus');
  });

  cas('E370 : corriger une admission SORTIE ne la rouvre pas (le lit ne se réoccupe pas)', (t) async {
    final m = magasinEssai();
    await ouvrir(t, m, 'm3-admissions');
    final col = m.collection('admissions');
    await toucher(t, find.text('H00003'));
    await toucher(t, find.widgetWithText(BoutonSigh, 'Modifier'));
    await saisir(t, 'diagnosticEntree', 'Diagnostic précisé');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final f = col.parId('ADM3')!;
    expect(f['diagnosticEntree'], 'Diagnostic précisé');
    expect(f['statut'], 'sortie');
    expect(f['dateSortie'], '2026-08-02');
  });

  cas('archivage annulable : l\'admission passe aux archives, l\'annulation la rend (RG-14)', (t) async {
    final m = magasinEssai();
    await ouvrir(t, m, 'm3-admissions');
    final col = m.collection('admissions');
    await toucher(t, find.text('H00004'));
    await toucher(t, find.widgetWithText(BoutonSigh, 'Archiver'));
    await toucher(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
    expect(col.parId('ADM4')!['statut'], 'archive');
    expect(col.parId('ADM4'), isNotNull);
    await toucher(t, find.text('Annuler'));
    expect(col.parId('ADM4')!['statut'], isNot('archive'));
  });

  cas('bon d\'admission : titre, cartouche, rubriques et trois signatures comme la maquette', (t) async {
    await ouvrir(t, magasinEssai(), 'm3-admissions');
    await toucher(t, find.text('H00001'));
    await toucher(t, find.widgetWithText(BoutonSigh, 'Imprimer'));
    final e = carte(adm()['etat']);
    expect(affiche(t, '${e['titre']}'), isTrue);
    expect(affiche(t, '${e['sousTitre']}'), isTrue);
    expect(affiche(t, 'Hospitalisation de plus de 8 heures'), isTrue);
    expect(affiche(t, 'A1 LIT1 — Standard'), isTrue);
    for (final s in liste(e['signatures'])) {
      expect(affiche(t, '${s['role']}'), isTrue, reason: '${s['role']}');
    }
  });

  cas('parité N1 = 100 % contre la fiche de la maquette (jeu complet)', (t) async {
    final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
    await ouvrir(t, m, 'm3-admissions');
    final fiche = (jsonDecode(File('../../docs/architecture/ecrans/m3-admissions.json').readAsStringSync()) as Map).cast<String, Object?>();
    final p = comparerContenu('m3-admissions', fiche, textesVisibles(t));
    expect(p.manquants, isEmpty, reason: 'taux ${p.taux}');
  });
}
