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

/// `m3-soins` : le jeu d'essai de la maquette (`vecteurs.soins`) est monté — admissions, actes de soins, file des actes prescrits et ordonnance. La
/// capacité « exécuter les soins » (infirmiers et sages-femmes) décide du geste : un refus est NOMMÉ ; l'exécution clôt la tâche et marque l'ordonnance.
Map<String, Object?> soi() => carte(vecteurs['soins']);

Magasin magasinEssai() => Magasin({
      'admissions': [for (final x in liste(soi()['admissions'])) {...x}],
      'soins': [for (final x in liste(soi()['soins'])) {...x}],
      'taches': [for (final x in liste(soi()['taches'])) {...x}],
      'ordonnances': [
        {'id': 'ORD1', 'numero': 'ORD-T1', 'statut': 'actif', 'patientCode': 'CNT/1/25', 'patient': 'TCHANE Bertine'}
      ],
      'audit': const [],
    }, 'POSTE');

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  cas('KPI, file des actes (urgent d\'abord, le bloqué après) et registre — identiques à la maquette', (t) async {
    await ouvrir(t, magasinEssai(), 'm3-soins');
    final e = carte(soi()['ecran']);
    for (final k in liste(e['kpis'])) {
      final w = t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == k['libelle']));
      expect(sansEspaces(w.valeur), sansEspaces(k['valeur']), reason: '${k['libelle']}');
    }
    expect(affiche(t, (e['cartes'] as List).single as String), isTrue, reason: 'titre de la file, avec ses comptes');
    final tableaux = liste(e['tableaux']);
    // la file : ORD-T1 (urgent), ORD-T3, ORD-T2 (en attente de caisse), de haut en bas
    final ys = [for (final l in (tableaux[0]['lignes'] as List)) t.getTopLeft(find.text(((l as List)[0] as String).replaceAll('Urgent', ''))).dy];
    expect(ys, orderedEquals([...ys]..sort()));
    expect(affiche(t, 'Attente encaissement'), isTrue);
    // le registre : le plus récent d'abord ; l'acte archivé est exclu
    final reg = (tableaux[1]['lignes'] as List);
    final tab = t.widgetList<TableauSigh>(find.byType(TableauSigh)).last;
    expect(tab.lignes.length, reg.length);
    expect(tab.lignes.any((r) => r['id'] == 'SOI5'), isFalse);
    final vues = <String, int>{};
    for (final l in reg) {
      final date = (l as List)[1] as String;
      final rang = vues[date] = (vues[date] ?? -1) + 1;
      final cellules = sansEspaces(ligneDe(t, date, rang: rang).join('|'));
      for (final idx in [2, 3, 4, 5, 6, 7, 8]) {
        expect(cellules.contains(sansEspaces(l[idx])), isTrue, reason: '$date : « ${l[idx]} » absent de $cellules');
      }
    }
  });

  cas('la Direction (fonction sans la capacité) : la règle est annoncée, et « Marquer le soin fait » est REFUSÉ en le nommant — rien n\'est écrit', (t) async {
    final m = magasinEssai();
    await ouvrir(t, m, 'm3-soins', role: 'admin');
    expect(affiche(t, ((soi()['directionNote'] as List).single as String)), isTrue);
    await toucher(t, find.byTooltip('Marquer le soin fait').first);
    final toast = ((carte(soi()['refusDirection'])['toasts'] as List).single as List).cast<String>();
    for (final ligne in toast) {
      expect(find.text(ligne), findsOneWidget);
    }
    expect(find.text('Soin fait ?'), findsNothing, reason: 'aucune confirmation n\'est offerte à qui ne peut pas exécuter');
    expect(m.collection('taches').parId('TCH1')!['statut'], 'en_attente');
    expect(m.collection('ordonnances').parId('ORD1')!['statutActes'], isNull);
  });

  cas('l\'infirmier exécute : confirmation de la maquette, puis tâche close (heure, agent) et ordonnance marquée « fait »', (t) async {
    final m = magasinEssai();
    await ouvrir(t, m, 'm3-soins', role: 'infirmier');
    expect(affiche(t, 'ne vous revient pas'), isFalse, reason: 'l\'infirmier n\'a pas la note de refus');
    await toucher(t, find.byTooltip('Marquer le soin fait').first);
    final conf = carte(soi()['confirmation']);
    expect(affiche(t, 'Soin fait ?'), isTrue);
    expect(affiche(t, 'Les actes de la prescription ORD-T1 seront marqués exécutés, avec l’heure d’exécution et votre nom. Un acte non coché reste réputé non fait.'), isTrue);
    expect('${conf['texte']}'.replaceAll(' ', ''), contains('Soinfait?Lesactesdelaprescription'.replaceAll(' ', '')));
    expect(m.collection('taches').parId('TCH1')!['statut'], 'en_attente', reason: 'rien n\'est écrit avant la confirmation');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Soin fait'));
    final fait = carte(soi()['fait']);
    final tache = m.collection('taches').parId('TCH1')!;
    final att = carte(fait['tache']);
    expect(tache['statut'], att['statut']);
    expect(tache['faitLe'], att['faitLe']);
    expect('${tache['faitPar']}', isNotEmpty);
    final ord = m.collection('ordonnances').parId('ORD1')!;
    final attOrd = carte(fait['ordonnance']);
    expect(ord['statutActes'], attOrd['statutActes']);
    expect(ord['actesFaitsLe'], attOrd['actesFaitsLe']);
    expect(ord['actesFaitsPar'], tache['faitPar']);
    for (final ligne in ((fait['toasts'] as List).single as List).cast<String>()) {
      expect(find.text(ligne), findsOneWidget);
    }
    expect(affiche(t, 'ORD-T1'), isFalse, reason: 'la tâche faite quitte la file');
  });

  cas('une tâche bloquée par la caisse est visible mais non exécutable : la commande le dit', (t) async {
    final m = magasinEssai();
    await ouvrir(t, m, 'm3-soins', role: 'infirmier');
    await toucher(t, find.byTooltip('Bloquée jusqu’à l’encaissement'));
    expect(find.text(((carte(soi()['bloquee'])['toasts'] as List).single as List).single as String), findsOneWidget);
    expect(m.collection('taches').parId('TCH2')!['statut'], 'bloque');
  });

  cas('tiroir de l\'acte et feuille de soins imprimée : phrases de la maquette', (t) async {
    await ouvrir(t, magasinEssai(), 'm3-soins');
    await toucher(t, find.text('Pose de perfusion').last);
    final d = '${carte(soi()['detail'])['texte']}';
    for (final f in ['Date et heure 15/08/2026 à 12:00', 'Dossier CNT/1/25', 'Lit A1 LIT1', 'Planifié']) {
      expect(sansEspaces(d).contains(sansEspaces(f)), isTrue, reason: 'vecteur : $f');
    }
    expect(affiche(t, '15/08/2026 à 12:00'), isTrue);
    expect(affiche(t, 'Produit administré'), isTrue);
    expect(find.widgetWithText(BoutonSigh, 'Modifier'), findsOneWidget);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Imprimer'));
    final e = carte(soi()['etat']);
    expect(affiche(t, '${e['titre']}'), isTrue);
    expect(affiche(t, '${e['sousTitre']}'), isTrue);
    for (final s in liste(e['signatures'])) {
      expect(affiche(t, '${s['role']}'), isTrue);
    }
    expect(affiche(t, 'Pose de perfusion'), isTrue);
  });

  cas('création : champs de la maquette ; sans soignant → refusé ; complète → fiche de la maquette (références recopiées de l\'admission), KPI à jour', (t) async {
    final m = magasinEssai();
    await ouvrir(t, m, 'm3-soins');
    final col = m.collection('soins');
    final avant = col.toutes.length;
    await toucher(t, find.text('Nouveau'));
    final c = carte(soi()['creation']);
    for (final lib in (c['champs'] as List).cast<String>()) {
      expect(affiche(t, lib.replaceAll(' *', '')), isTrue, reason: lib);
    }
    await saisir(t, 'soignant', '');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
    expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
    expect(col.toutes.length, avant);
    await t.pump(const Duration(seconds: 10));
    await choisir(t, 'admissionId', 'BAKO Boukari — lit A2 LIT1 (CNT/2/26)');
    await choisir(t, 'acte', 'Injection intramusculaire');
    await saisir(t, 'produit', 'Ceftriaxone');
    await saisir(t, 'quantite', '1');
    await saisir(t, 'soignant', 'NKOUÉ Jean');
    await saisir(t, 'observations', 'Bien toléré');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
    final f = col.actives.first;
    final att = carte(carte(c['cree'])['fiche']);
    for (final k in ['statut', 'admissionId', 'date', 'heure', 'acte', 'produit', 'quantite', 'soignant', 'etat', 'observations', 'patient', 'patientCode', 'patientId', 'lit']) {
      expect(f[k], att[k], reason: k);
    }
    expect(find.text('Nouveau acte de soins créé.'), findsOneWidget);
    final kp = liste(carte(soi()['apres'])['kpis']);
    for (final k in kp) {
      final w = t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == k['libelle']));
      expect(sansEspaces(w.valeur), sansEspaces(k['valeur']), reason: '${k['libelle']}');
    }
  });

  cas('modification : changer de patient recopie son lit et ses références ; « Modifications enregistrées. »', (t) async {
    final m = magasinEssai();
    await ouvrir(t, m, 'm3-soins');
    final col = m.collection('soins');
    await toucher(t, find.text('Soins de nursing').last); // SOI4 : BAKO Boukari, lit A2 LIT1
    await toucher(t, find.widgetWithText(BoutonSigh, 'Modifier'));
    await choisir(t, 'admissionId', 'TCHANE Bertine — lit A1 LIT1 (CNT/1/25)');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final f = col.parId('SOI4')!;
    expect(f['patient'], 'TCHANE Bertine');
    expect(f['lit'], 'A1 LIT1');
    expect(f['patientCode'], 'CNT/1/25');
    expect(f['admissionId'], 'ADM1');
    expect(find.text('Modifications enregistrées.'), findsOneWidget);
    final att = carte(carte(carte(soi()['modification'])['enregistre'])['fiche']);
    expect(att['lit'], 'A1 LIT1', reason: 'même résultat que la maquette (autre acte, même transformation)');
  });

  cas('droits : un profil en lecture voit la feuille mais n\'a ni Nouveau, ni Modifier, ni Archiver, ni exécution de la file', (t) async {
    await ouvrir(t, magasinEssai(), 'm3-soins', role: 'reception');
    expect(affiche(t, 'Actes prescrits à exécuter'), isTrue, reason: 'l\'écran s\'ouvre en lecture à la réception');
    expect(find.byTooltip('Votre profil consulte cette file sans l’exécuter'), findsWidgets);
    expect(find.text('Nouveau'), findsNothing);
    expect(find.byTooltip('Modifier'), findsNothing);
    expect(find.byTooltip('Archiver'), findsNothing);
    expect(find.byTooltip('Marquer le soin fait'), findsNothing);
  });

  cas('archivage d\'un acte : annulable (RG-14)', (t) async {
    final m = magasinEssai();
    await ouvrir(t, m, 'm3-soins');
    final col = m.collection('soins');
    await toucher(t, find.byTooltip('Archiver').first);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
    expect(col.actives.length, 3);
    expect(col.parId('SOI4')!['statut'], 'archive');
    await toucher(t, find.text('Annuler'));
    expect(col.parId('SOI4')!['statut'], isNot('archive'));
  });

  cas('parité N1 = 100 % contre la fiche de la maquette (jeu complet)', (t) async {
    final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
    await ouvrir(t, m, 'm3-soins', le: DateTime(2026, 10, 30, 10));
    final fiche = (jsonDecode(File('../../docs/architecture/ecrans/m3-soins.json').readAsStringSync()) as Map).cast<String, Object?>();
    final p = comparerContenu('m3-soins', fiche, textesVisibles(t));
    expect(p.manquants, isEmpty, reason: 'taux ${p.taux}');
  });
}
