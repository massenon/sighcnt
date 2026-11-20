import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show InkWell, Key;
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm3_surv_aide.dart';
import 'parite/extracteur.dart';

/// `m3-administrations` : l'écran rejoue les vecteurs de la maquette (`hospitalisation.json`, groupe `administrations`, tiré de l'écran réel piloté dans
/// Chrome). Le RANG du passage décide du secteur : ce poste ne voit jamais la première administration d'un traitement hospitalier.
final v = dico(lireVecteurs('hospitalisation.json')['administrations']);
final soignants = liste(jsonDecode(File('assets/donnees/jeu/soignants.json').readAsStringSync()));

Magasin magasin() => Magasin({
      'prescriptions': [for (final x in liste(v['prescriptions'])) {...x}],
      'administrations': [for (final x in liste(v['administrations'])) {...x}],
      'soignants': soignants,
      'audit': const [],
    }, 'POSTE');

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  cas('administrations : KPI et lignes dues identiques à la maquette (rang ≥ 2, hospitalier, non terminées)', (t) async {
    await ouvrir(t, magasin(), 'm3-administrations');
    final ecran = dico(v['ecran']);
    for (final k in liste(ecran['kpis'])) {
      final w = t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == k['libelle']));
      expect(sans(w.valeur), sans(k['valeur']), reason: '${k['libelle']}');
    }
    final lignes = (dico((ecran['tableaux'] as List).single)['lignes'] as List).cast<List>();
    final tab = t.widget<TableauSigh>(find.byType(TableauSigh));
    expect(tab.lignes.length, lignes.length);
    for (var i = 0; i < lignes.length; i++) {
      final r = tab.lignes[i];
      expect(r['reference'], lignes[i][0]);
      expect('${r['patient']} — ${r['patientCode']}', lignes[i][1]);
      expect(r['libelle'], lignes[i][2]);
      expect('${r['rang']} / ${r['total']}', lignes[i][3]);
      expect(r['motif'], lignes[i][4]);
      expect(r['bloque'] == true ? 'Non réglée' : 'Exécutable', lignes[i][5]);
    }
    expect(find.text('Non réglée'), findsOneWidget);
    expect(find.text('Exécutable'), findsOneWidget);
    // PRS-00003 est ambulatoire, la 2e ligne de PRS-00001 n'en est qu'à son 1er passage, PRS-00004 est à son 3e sur 2 : aucune n'est due ici
    expect(find.text('Injection IM'), findsNothing);
    expect(find.text('Perfusion de sérum'), findsNothing);
    expect(find.text('Paracétamol IV'), findsNothing);
  });

  cas('administrations : une prescription non réglée est visible mais NON exécutable — le verrou le dit', (t) async {
    await ouvrir(t, magasin(), 'm3-administrations');
    expect(find.widgetWithText(BoutonSigh, 'Administrer'), findsOneWidget, reason: 'seule PRS-00001 est réglée');
    await toucher(t, find.byTooltip('Bloquée : la prescription n’est pas réglée'));
    final message = (((v['bloquee'] as Map)['toasts'] as List).first as List).first as String;
    expect(find.text(message), findsOneWidget);
  });

  cas('administrations : l\'historique ne montre que les administrations de CE poste (hospitalisation), pas les archivées', (t) async {
    await ouvrir(t, magasin(), 'm3-administrations');
    await toucher(t, find.textContaining('Historique'));
    final hist = dico((dico(v['historique'])['tableaux'] as List).single);
    final lignes = (hist['lignes'] as List).cast<List>();
    expect(lignes.length, 1);
    expect(find.text('${lignes.first[0]}'), findsOneWidget);
    expect(find.text('${lignes.first[3]}'), findsOneWidget);
    expect(find.text('${lignes.first[5]}'), findsOneWidget);
    expect(find.text('ADM-00005'), findsNothing, reason: 'archivée');
    expect(find.text('ADM-00001'), findsNothing, reason: 'salle de soins : pas ce poste');
  });

  cas('administrations : Administrer — liste des exécutants, note du relais, fiche écrite, prescription non terminée', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm3-administrations');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Administrer'));
    final modale = dico(v['modale']);
    expect(find.text('Administrer — Ceftriaxone 1 g'), findsOneWidget);
    expect(find.textContaining('passage 2 sur 3'), findsOneWidget);
    expect(find.text('Administration n° 2 : le relais est passé à l’hospitalisation.'), findsWidgets);
    // la liste est celle de la maquette : les soignants qui EXÉCUTENT et servent l'hospitalisation — pas le médecin
    final attendus = [for (final o in (modale['options'] as List)) (o as List)[1] as String];
    await toucher(t, find.descendant(of: find.byKey(const Key('kit:champ:executantId')), matching: find.byType(InkWell)).first);
    for (final a in attendus) {
      expect(find.text(a), findsWidgets, reason: a);
    }
    expect(find.textContaining('BASSONGUI Chabi Séko'), findsNothing, reason: 'Le médecin prescrit, il n’exécute pas les soins.');
    await toucher(t, find.text('NKOUÉ Jean — Infirmier').last);
    await ecrire(t, 'observation', 'Bien toléré');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Confirmer l’administration'));
    final att = dico(dico(v['administre'])['fiche']);
    final f = m.collection('administrations').actives.first;
    for (final k in ['reference', 'prescriptionId', 'prescriptionRef', 'ligneIndex', 'libelle', 'patientId', 'patientCode', 'patient', 'rang', 'total', 'secteur', 'motifSecteur', 'executantId', 'executant', 'observation', 'modalite', 'statut']) {
      expect(f[k], att[k], reason: k);
    }
    expect(f['reference'], 'ADM-00006', reason: 'série lue sur le registre (E363), archivées comprises');
    expect(f['dateHeure'], att['dateHeure']);
    expect(m.collection('prescriptions').parId('PRS1')!['statut'], 'en_cours', reason: 'la perfusion n\'a pas eu son premier passage');
    expect(find.text('Administration n° 2 enregistrée.'), findsOneWidget);
    // l'écran se met à jour : « Déjà administrées ici » passe à 2, le passage suivant est dû (3 / 3)
    final apres = dico(v['apres']);
    for (final k in liste(apres['kpis'])) {
      final w = t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == k['libelle']));
      expect(sans(w.valeur), sans(k['valeur']), reason: 'après : ${k['libelle']}');
    }
    expect(find.text('3 / 3'), findsOneWidget);
  });

  cas('administrations : le dernier passage termine la prescription quand toutes ses lignes sont servies', (t) async {
    final m = magasin();
    // PRS4 : un seul passage restant (2 / 2) une fois le 1er ôté de la salle de soins ; on retire la ligne « Perfusion » de PRS1 pour que la prescription n'ait qu'une ligne
    final pres = m.collection('prescriptions').parId('PRS1')!;
    pres['lignes'] = [(pres['lignes'] as List).first];
    await ouvrir(t, m, 'm3-administrations');
    for (var i = 0; i < 2; i++) {
      await toucher(t, find.widgetWithText(BoutonSigh, 'Administrer'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Confirmer l’administration'));
      await t.pump(const Duration(seconds: 5));
      if (i == 0) expect(m.collection('prescriptions').parId('PRS1')!['statut'], 'en_cours');
    }
    expect(m.collection('prescriptions').parId('PRS1')!['statut'], 'termine');
    expect(find.widgetWithText(BoutonSigh, 'Administrer'), findsNothing, reason: 'rien n\'est plus dû à ce poste');
  });

  cas('administrations : jeu vide — quatre KPI à zéro et le message du tableau (E368)', (t) async {
    final m = Magasin({'prescriptions': const [], 'administrations': const [], 'soignants': soignants, 'audit': const []}, 'POSTE');
    await ouvrir(t, m, 'm3-administrations');
    final vide = dico(v['vide']);
    for (final k in liste(vide['kpis'])) {
      final w = t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == k['libelle']));
      expect(sans(w.valeur), '0');
    }
    expect(find.text('Aucun enregistrement.'), findsOneWidget, reason: 'E368 : le message propre de la maquette n\'est jamais affiché');
  });

  cas('administrations : parité N1 = 100 % contre la fiche de la maquette (jeu complet)', (t) async {
    await ouvrir(t, Magasin.depuisDossier(Magasin.collectionsDuJeu), 'm3-administrations');
    final fiche = dico(jsonDecode(File('../../docs/architecture/ecrans/m3-administrations.json').readAsStringSync()));
    final p = comparerContenu('m3-administrations', fiche, textesVisibles(t));
    expect(p.manquants, isEmpty, reason: 'taux ${p.taux}');
  });
}
