import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/m3/surv_commun.dart' show dateHeureTexte;

import 'aide_polices.dart';
import 'm3_surv_aide.dart';
import 'parite/extracteur.dart';

/// `m3-glasgow` : l'écran rejoue les vecteurs de la maquette (`hospitalisation.json`, groupe `glasgow`, tiré de l'écran réel piloté dans Chrome)
/// et sa parité N1 est mesurée contre la fiche extraite.
final v = dico(lireVecteurs('hospitalisation.json')['glasgow']);
final patients = liste(dico(lireVecteurs('hospitalisation.json')['transfusion'])['patients']);
final soignants = liste(jsonDecode(File('assets/donnees/jeu/soignants.json').readAsStringSync()));

Magasin magasin() => Magasin({
      'scoresGlasgow': [for (final x in liste(v['jeu'])) {...x}],
      'patients': patients,
      'soignants': soignants,
      'audit': const [],
    }, 'POSTE');

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  cas('glasgow : KPI, lignes et couleur du score identiques à la maquette', (t) async {
    await ouvrir(t, magasin(), 'm3-glasgow');
    final ecran = dico(v['ecran']);
    for (final k in liste(ecran['kpis'])) {
      final w = t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == k['libelle']));
      expect(sans(w.valeur), sans(k['valeur']), reason: '${k['libelle']}');
    }
    final lignes = (dico((ecran['tableaux'] as List).single)['lignes'] as List).cast<List>();
    final tab = t.widget<TableauSigh>(find.byType(TableauSigh));
    expect(tab.lignes.length, lignes.length, reason: 'une évaluation archivée ne se compte pas');
    for (var i = 0; i < lignes.length; i++) {
      final r = tab.lignes[i];
      expect(r['reference'], lignes[i][0]);
      expect(dateHeureTexte(r['dateHeure']), lignes[i][1]);
      expect('${r['patient']} — NIP ${r['nip']}', lignes[i][2]);
      expect('${r['score']} / 15', lignes[i][3]);
      expect(r['evaluateur'], lignes[i][4]);
    }
    final tons = [for (final b in t.widgetList<BadgeSigh>(find.byType(BadgeSigh)).where((b) => b.libelle.endsWith('/ 15'))) b.ton];
    // maquette : success, warning, danger, danger, warning (15, 12, 7, 3, 10)
    expect(tons, [TonSigh.succes, TonSigh.attention, TonSigh.danger, TonSigh.danger, TonSigh.attention]);
  });

  cas('glasgow : le score est CALCULÉ à la création (jamais saisi) et un formulaire vide est refusé', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm3-glasgow');
    final avant = m.collection('scoresGlasgow').actives.length;
    await toucher(t, find.text('Nouvelle évaluation'));
    // la maquette présélectionne la première entrée des listes obligatoires : patient, axes 4/5/6, évaluateur
    await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
    expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget, reason: 'sans date : refus nommé');
    expect(m.collection('scoresGlasgow').actives.length, avant);
    await choisir(t, 'patientCode', 'CNT/2/26 — BAKO Boukari');
    await dater(t, 'dateHeure_d', 16);
    await ecrire(t, 'dateHeure_h', '09:00');
    await choisir(t, 'axe0', 'À la douleur — 2 point(s)');
    await choisir(t, 'axe1', 'Inappropriée — 3 point(s)');
    await choisir(t, 'axe2', 'Se retire à la douleur — 4 point(s)');
    await ecrire(t, 'observation', 'Obnubilé');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
    final f = m.collection('scoresGlasgow').actives.first;
    final attendu = dico(dico(dico(v['creation'])['cree'])['fiche']);
    expect(f['score'], attendu['score']);
    expect(f['axes'], attendu['axes']);
    expect(f['reference'], attendu['reference'], reason: 'GCS-0007 : série lue sur le registre (E360)');
    expect(f['patient'], attendu['patient']);
    expect(f['nip'], attendu['nip'], reason: 'NIP absent → le code dossier');
    expect(f['evaluateur'], attendu['evaluateur']);
    expect(f['statut'], 'actif');
    expect('${f['dateHeure']}'.endsWith('T09:00'), isTrue);
    expect(find.text('Évaluation créé.'), findsOneWidget);
  });

  cas('glasgow : modifier relit le patient et les axes de la fiche et RECALCULE le score (E364)', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm3-glasgow');
    final modif = dico(v['modification']);
    final val = dico(modif['valeurs']);
    // GCS-0003 est la 3e ligne du tableau (tri par date décroissante)
    await toucher(t, find.byTooltip('Modifier').at(2));
    // le formulaire s'ouvre sur LA fiche : patient CNT/3/26, axes 2/2/3 — pas sur le premier patient et les meilleures réponses
    expect(find.descendant(of: find.byKey(const Key('kit:champ:patientCode')), matching: find.textContaining('${val['patientCode']}')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('kit:champ:axe0')), matching: find.text('À la douleur — 2 point(s)')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('kit:champ:axe1')), matching: find.text('Incompréhensible — 2 point(s)')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('kit:champ:axe2')), matching: find.text('Flexion à la douleur — 3 point(s)')), findsOneWidget);
    await choisir(t, 'axe0', 'Aucune réponse — 1 point(s)');
    await ecrire(t, 'observation', 'Corrigée');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final f = m.collection('scoresGlasgow').parId('GCS3')!;
    final att = dico(dico(modif['enregistre'])['fiche']);
    expect(f['score'], att['score'], reason: 'axes 1 + 2 + 3 = 6');
    expect(f['axes'], att['axes']);
    expect(f['observation'], 'Corrigée');
    expect(f['reference'], 'GCS-0003', reason: 'la référence ne change pas à la modification');
    expect(find.text('Modifications enregistrées.'), findsOneWidget);
  });

  cas('glasgow : l\'archivage est annulable et la fiche reste au registre (RG-14)', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm3-glasgow');
    
    await toucher(t, find.byTooltip('Archiver').first);
    await t.tap(find.text('Archiver').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(m.collection('scoresGlasgow').parId('GCS1')!['statut'], 'archive');
    expect(m.collection('scoresGlasgow').toutes.length, 6);
    await toucher(t, find.text('Annuler').last);
    expect(m.collection('scoresGlasgow').parId('GCS1')!['statut'], 'actif');
  });

  cas('glasgow : parité N1 = 100 % contre la fiche de la maquette (jeu complet)', (t) async {
    await ouvrir(t, Magasin.depuisDossier(Magasin.collectionsDuJeu), 'm3-glasgow');
    final fiche = dico(jsonDecode(File('../../docs/architecture/ecrans/m3-glasgow.json').readAsStringSync()));
    final p = comparerContenu('m3-glasgow', fiche, textesVisibles(t));
    expect(p.manquants, isEmpty, reason: 'taux ${p.taux}');
  });
}
