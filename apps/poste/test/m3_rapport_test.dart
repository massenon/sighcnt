import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/m3/surv_commun.dart' show dateTexte;

import 'aide_polices.dart';
import 'm3_surv_aide.dart';
import 'parite/extracteur.dart';

/// `m3-rapport` : l'écran rejoue les vecteurs du second lot (`hospitalisation2.json`, groupe `rapport`, tiré de l'écran réel piloté dans Chrome par
/// `prototype_html/build/vecteurs-hospitalisation2.js`). E380 : la référence `RAP-` suit le registre.
final v = dico(lireVecteurs('hospitalisation2.json')['rapport']);
final soignants = liste(jsonDecode(File('assets/donnees/jeu/soignants.json').readAsStringSync()));

/// Les trois patients du vecteur, avec les champs que la maquette recopie sur le rapport (âge calculé depuis la naissance relevée).
final patients = [
  {'id': 'PAT0001', 'code': 'CNT/1/25', 'nom': 'TCHANE', 'prenom': 'Bertine', 'sexe': 'F', 'quartier': 'Boukoumbé', 'telephone': '0372398919', 'dateNaissance': '1995-05-01'},
  {'id': 'PAT0002', 'code': 'CNT/2/26', 'nom': 'BAKO', 'prenom': 'Boukari', 'sexe': 'M', 'quartier': 'Yimporima', 'telephone': '0395837962', 'dateNaissance': '1969-12-10'},
  {'id': 'PAT0003', 'code': 'CNT/3/26', 'nom': 'N’TCHA', 'prenom': 'Yacoubou', 'sexe': 'M', 'quartier': 'Kouandé', 'telephone': '0673723379', 'dateNaissance': '1993-01-01'},
];

Magasin magasin() => Magasin({
      'rapportsMedicaux': [for (final x in liste(v['jeu'])) {...x}],
      'patients': [for (final p in patients) {...p}],
      'soignants': soignants,
      'audit': const [],
    }, 'POSTE');

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  cas('rapport : KPI et lignes identiques à la maquette, séjour en cours signalé', (t) async {
    await ouvrir(t, magasin(), 'm3-rapport');
    final ecran = dico(v['ecran']);
    for (final k in liste(ecran['kpis'])) {
      final w = t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == k['libelle']));
      expect(sans(w.valeur), sans(k['valeur']), reason: '${k['libelle']}');
      expect(w.indice, k['indice'], reason: 'indice ${k['libelle']}');
    }
    final lignes = (dico((ecran['tableaux'] as List).single)['lignes'] as List).cast<List>();
    final tab = t.widget<TableauSigh>(find.byType(TableauSigh));
    expect(tab.lignes.length, lignes.length, reason: 'une fiche archivée ne se compte pas');
    for (var i = 0; i < lignes.length; i++) {
      final r = tab.lignes[i];
      expect(r['reference'], lignes[i][0]);
      expect('${r['patient']} — ${r['patientCode']}', lignes[i][1]);
      expect(dateTexte(r['dateEntree']), lignes[i][2]);
      expect(r['dateSortie'] == null ? 'en cours' : dateTexte(r['dateSortie']), lignes[i][3]);
      expect(r['diagnosticSortie'], lignes[i][4]);
      expect(r['medecin'], lignes[i][5]);
    }
    expect(find.text('en cours'), findsWidgets);
    // maquette : Imprimer le rapport, Consulter, Modifier, Archiver sur chaque ligne
    expect(find.byTooltip('Imprimer le rapport'), findsNWidgets(3));
    expect(find.byTooltip('Modifier'), findsNWidgets(3));
  });

  cas('rapport : la fiche ne montre que les rubriques RENSEIGNÉES, et dit « séjour en cours »', (t) async {
    await ouvrir(t, magasin(), 'm3-rapport');
    await toucher(t, find.byTooltip('Consulter').at(0)); // RAP-0003 : séjour clos, évolution et traitement de sortie renseignés
    expect(find.text('Évolution et traitement des complications'), findsOneWidget);
    expect(find.text('Favorable'), findsOneWidget);
    expect(find.text('Traitement réajusté'), findsNothing, reason: 'rubrique vide : non affichée');
    expect(find.text('33 ans'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.byTooltip('Fermer'));
    await t.pump(const Duration(seconds: 1));
    await toucher(t, find.byTooltip('Consulter').at(1)); // RAP-0001 : séjour en cours
    expect(find.text('séjour en cours'), findsOneWidget);
    expect(find.text('Examens paracliniques'), findsNothing);
  });

  cas('rapport : la référence suit le REGISTRE (E380), l\'identité est recopiée du patient et un formulaire vide est refusé', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm3-rapport');
    await toucher(t, find.text('Nouveau rapport'));
    await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
    expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
    expect(m.collection('rapportsMedicaux').toutes.length, 4);
    await choisir(t, 'patientCode', 'CNT/2/26 — BAKO Boukari');
    await dater(t, 'dateEntree', 12);
    await ecrire(t, 'motif', 'Fièvre');
    await ecrire(t, 'anamnese', 'Depuis 3 jours');
    await ecrire(t, 'examenPhysique', 'T° 39');
    await ecrire(t, 'hypotheses', 'Paludisme');
    await ecrire(t, 'traitementEntree', 'Artésunate');
    await ecrire(t, 'diagnosticRetenu', 'Paludisme grave');
    await ecrire(t, 'diagnosticSortie', 'Guérison');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
    final att = dico(dico(dico(v['creation'])['cree'])['fiche']);
    final f = m.collection('rapportsMedicaux').actives.first;
    expect(f['reference'], att['reference'], reason: 'RAP-0005, et non RAP-0001 : un doublon de la fiche existante');
    for (final k in ['patientCode', 'patientId', 'patient', 'age', 'sexe', 'adresse', 'telephone', 'medecin', 'medecinId', 'motif', 'anamnese', 'examenPhysique', 'hypotheses', 'traitementEntree', 'diagnosticRetenu', 'diagnosticSortie', 'dateSortie', 'examensParacliniques']) {
      expect(f[k], att[k], reason: k);
    }
    expect('${f['dateEntree']}'.endsWith('-12'), isTrue);
    expect(find.text('Rapport médical créé.'), findsOneWidget);
  });

  cas('rapport : modifier ne touche que les champs du formulaire — référence conservée, identité d\'origine gardée (E381)', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm3-rapport');
    await toucher(t, find.byTooltip('Modifier').at(1)); // RAP-0001
    expect(find.text('Sortie 1'), findsWidgets, reason: 'la modale est préremplie par la fiche');
    await dater(t, 'dateSortie', 15);
    await ecrire(t, 'diagnosticSortie', 'Sortie corrigée');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final f = m.collection('rapportsMedicaux').parId('RAP1')!;
    final att = dico(dico(dico(v['modification'])['enregistre'])['fiche']);
    expect(f['reference'], att['reference']);
    expect(f['diagnosticSortie'], att['diagnosticSortie']);
    expect('${f['dateSortie']}'.endsWith('-15'), isTrue);
    expect(f['patient'], att['patient']);
    expect(find.text('Modifications enregistrées.'), findsOneWidget);
  });

  cas('rapport : « Imprimer le rapport » ouvre la pièce RAPPORT MÉDICAL signée du médecin traitant', (t) async {
    await ouvrir(t, magasin(), 'm3-rapport');
    await toucher(t, find.byTooltip('Imprimer le rapport').at(0));
    final imp = dico(v['impression']);
    expect(find.textContaining('${imp['titre']}'), findsWidgets);
    expect(find.textContaining('${imp['sousTitre']}'), findsWidgets);
    expect(find.textContaining('Le Médecin traitant'), findsWidgets);
  });

  cas('rapport : l\'archivage est annulable (RG-14)', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm3-rapport');
    await toucher(t, find.byTooltip('Archiver').at(2)); // RAP-0002
    await t.tap(find.text('Archiver').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(m.collection('rapportsMedicaux').parId('RAP2')!['statut'], 'archive');
    await toucher(t, find.text('Annuler').last);
    expect(m.collection('rapportsMedicaux').parId('RAP2')!['statut'], 'actif');
  });

  cas('rapport : parité N1 = 100 % contre la fiche de la maquette (jeu complet)', (t) async {
    await ouvrir(t, Magasin.depuisDossier(Magasin.collectionsDuJeu), 'm3-rapport');
    final fiche = dico(jsonDecode(File('../../docs/architecture/ecrans/m3-rapport.json').readAsStringSync()));
    final p = comparerContenu('m3-rapport', fiche, textesVisibles(t));
    expect(p.manquants, isEmpty, reason: 'taux ${p.taux}');
  });
}
