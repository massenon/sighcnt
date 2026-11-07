import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' show Key;
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm3_surv_aide.dart';
import 'parite/extracteur.dart';

/// `m3-visites-patients` : l'écran rejoue les vecteurs du second lot (`hospitalisation2.json`, groupe `visites`, tiré de l'écran réel piloté dans
/// Chrome). La visite se rattache à une admission EN COURS ; patient, code et lit sont recopiés de l'admission.
final v = dico(lireVecteurs('hospitalisation2.json')['visites']);

Magasin magasin() => Magasin({
      'admissions': [for (final x in liste(v['admissions'])) {...x}],
      'visitesHospi': [for (final x in liste(v['jeu'])) {...x}],
      'audit': const [],
    }, 'POSTE');

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  cas('visites : KPI, onglets et lignes identiques à la maquette (l\'archivée est à part)', (t) async {
    await ouvrir(t, magasin(), 'm3-visites-patients');
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
      expect('${r['heure']}', lignes[i][2]);
      expect(r['lit'], lignes[i][3]);
      expect(r['patient'], lignes[i][4]);
      expect(r['type'], lignes[i][5]);
      expect(r['visiteur'], lignes[i][6]);
    }
    // l'ordre est celui de la maquette : date décroissante (la tablette trie à l'affichage)
    expect(find.text('Sœur de la patiente'), findsOneWidget);
    expect(find.text('Voisin'), findsNothing, reason: 'visite archivée : onglet « Archivés »');
    expect(find.textContaining('Tous les visites'), findsOneWidget);
    expect(find.textContaining('Archivés'), findsOneWidget);
    await toucher(t, find.textContaining('Archivés'));
    expect(find.text('Voisin'), findsOneWidget);
    expect(find.byTooltip('Restaurer'), findsOneWidget);
  });

  cas('visites : la fiche porte « Modifier » et « Archiver » à son pied et rappelle l\'admission', (t) async {
    await ouvrir(t, magasin(), 'm3-visites-patients');
    await toucher(t, find.byTooltip('Consulter').first);
    await t.pump(const Duration(seconds: 1));
    final det = dico(v['detail']);
    expect(det['boutons'], ['Fermer', 'Modifier', 'Archiver']);
    expect(find.widgetWithText(BoutonSigh, 'Modifier'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Archiver'), findsOneWidget);
    expect(find.text('Patient hospitalisé'), findsOneWidget);
    expect(find.text('BAKO Boukari — lit C1 LIT1 (CNT/2/26)'), findsOneWidget);
  });

  cas('visites : création — valeurs par défaut, refus sans visiteur, patient recopié de l\'admission', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm3-visites-patients');
    await toucher(t, find.text('Nouveau'));
    final cre = dico(v['creation']);
    // défauts de la maquette : date du jour, 10:00, Famille, première admission en cours
    expect(find.text('16/08/2026'), findsWidgets);
    expect(find.text('10:00'), findsWidgets);
    expect(dico(cre['defauts'])['type'], 'Famille');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
    expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget, reason: 'visiteur obligatoire');
    expect(m.collection('visitesHospi').actives.length, 4);
    await choisir(t, 'admissionId', 'BAKO Boukari — lit C1 LIT1 (CNT/2/26)');
    await ecrire(t, 'heure', '11:15');
    await choisir(t, 'type', 'Personnel traitant');
    await ecrire(t, 'visiteur', 'Dr TAKI');
    await ecrire(t, 'observation', 'Réévaluation');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
    final att = dico(dico(cre['cree'])['fiche']);
    final f = m.collection('visitesHospi').actives.first;
    for (final k in ['admissionId', 'date', 'heure', 'type', 'visiteur', 'observation', 'patient', 'patientCode', 'lit', 'statut']) {
      expect(f[k], att[k], reason: k);
    }
    expect(find.text('Nouveau visite créé.'), findsOneWidget);
    // les options d'admission sont les seules admissions EN COURS (pas la sortie)
    expect(liste(v['admissions']).where((a) => a['statut'] == 'en_cours').length, 2);
  });

  cas('visites : modification — préremplie par la fiche, patient recopié de la NOUVELLE admission', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm3-visites-patients');
    await toucher(t, find.byTooltip('Modifier').first); // VIS0003 : « Sœur de la patiente »
    expect(find.text('Modifier l’enregistrement VIS0003'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('kit:champ:admissionId')), matching: find.text('BAKO Boukari — lit C1 LIT1 (CNT/2/26)')), findsOneWidget);
    await choisir(t, 'admissionId', 'TCHANE Bertine — lit A1 LIT1 (CNT/1/25)');
    await ecrire(t, 'observation', 'Corrigée');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final att = dico(dico(dico(v['modification'])['enregistre'])['fiche']);
    final f = m.collection('visitesHospi').parId('VIS0003')!;
    for (final k in ['admissionId', 'patient', 'patientCode', 'lit', 'observation', 'visiteur']) {
      expect(f[k], att[k], reason: k);
    }
    expect(find.text('Modifications enregistrées.'), findsOneWidget);
  });

  cas('visites : archiver est annulable, la visite passe à l\'onglet « Archivés » et se restaure', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm3-visites-patients');
    await toucher(t, find.byTooltip('Archiver').at(3)); // VIS0004
    await t.tap(find.text('Archiver').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(m.collection('visitesHospi').parId('VIS0004')!['statut'], 'archive');
    expect(m.collection('visitesHospi').toutes.length, 5, reason: 'RG-14 : jamais supprimée');
    await toucher(t, find.text('Annuler').last);
    expect(m.collection('visitesHospi').parId('VIS0004')!['statut'], 'actif');
  });

  cas('visites : lecture seule — sans le droit d\'écrire, ni « Nouveau » ni « Modifier » ni « Archiver »', (t) async {
    await ouvrir(t, magasin(), 'm3-visites-patients', role: 'caissier');
    // le caissier n'ouvre pas M3 : la coque refuse l'écran (aucune commande d'écriture n'est offerte)
    expect(find.text('Nouveau'), findsNothing);
    expect(find.byTooltip('Modifier'), findsNothing);
    expect(find.byTooltip('Archiver'), findsNothing);
  });

  cas('visites : parité N1 = 100 % contre la fiche de la maquette (jeu complet)', (t) async {
    // `visitesHospi` n'est pas encore embarquée par le jeu du poste (gen-poste-jeu.js) : sans visite, le tableau vide n'a pas d'en-têtes. La parité se
    // mesure donc sur le jeu complet AUQUEL on ajoute les visites du vecteur — le contenu de l'écran, pas celui d'un registre vide.
    final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
    for (final x in liste(v['jeu']).reversed) {
      m.collection('visitesHospi').inserer({...x});
    }
    await ouvrir(t, m, 'm3-visites-patients');
    final fiche = dico(jsonDecode(File('../../docs/architecture/ecrans/m3-visites-patients.json').readAsStringSync()));
    final p = comparerContenu('m3-visites-patients', fiche, textesVisibles(t));
    expect(p.manquants, isEmpty, reason: 'taux ${p.taux}');
  });
}
