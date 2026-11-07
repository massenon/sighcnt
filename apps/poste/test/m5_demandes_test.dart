import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// Les demandes d'analyses (M5) : m5-demandes, m5-prelevement et les deux vues par service. Les règles sont rejouées sur les vecteurs de la maquette
/// (packages/domaine/test/dem_regles_test.dart) ; ici, l'ÉCRAN — ce qui est écrit, refusé, annulable, et ce que chaque rôle voit.
final donnees = DonneesNavigation.depuisDossier();
final aujourdhui = DateTime(2026, 10, 30);

Fiche dem(String ref, String etat, {Map<String, Object?> plus = const {}}) => {
      'id': 'D-$ref',
      'statut': 'actif',
      'reference': ref,
      'patientId': 'PAT1',
      'patient': 'DOSSOU Aline',
      'patientCode': 'CNT/1/26',
      'analyseCode': 'L01',
      'analyse': 'AKOP',
      'categorie': 'Parasitologie',
      'echantillon': 'Selles',
      'prix': 2000,
      'dateHeure': '2026-10-28T09:30',
      'prescripteur': 'Dr TEST',
      'urgent': false,
      'etatAnalyse': etat,
      ...plus,
    };

Magasin magasin({
  List<Fiche> demandes = const [],
  List<Fiche> taches = const [],
  List<Fiche> patients = const [],
}) =>
    Magasin({
      'demandesAnalyses': demandes,
      'taches': taches,
      'patients': patients.isEmpty
          ? [
              {
                'id': 'PAT1',
                'statut': 'actif',
                'code': 'CNT/1/26',
                'nom': 'DOSSOU',
                'prenom': 'Aline',
                'sexe': 'F'
              }
            ]
          : patients,
      'personnel': [
        {'id': 'P1', 'statut': 'actif', 'fonction': 'tsl', 'nomComplet': 'LABO Un'},
        {'id': 'P2', 'statut': 'actif', 'fonction': 'tsl', 'nomComplet': 'LABO Deux'},
        {'id': 'P3', 'statut': 'actif', 'fonction': 'medecin', 'nomComplet': 'Dr MEDECIN'},
      ],
      'examensLabo': const [],
      'audit': const [],
    }, 'POSTE', {
      'analyses': [
        {'code': 'L01', 'designation': 'AKOP', 'categorie': 'Parasitologie', 'prix': 2000, 'echantillon': 'Selles', 'delai': '24 h'},
        {'code': 'L02', 'designation': 'ASLO', 'categorie': 'Sérologie', 'prix': 4000, 'echantillon': 'Sang', 'delai': '24 h'},
      ],
    });

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran,
    {String role = 'admin'}) async {
  t.view.physicalSize = const Size(1600, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: ecran,
      magasin: m,
      horloge: () => aujourdhui));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> toucher(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> saisir(WidgetTester t, String champ, String valeur) async {
  await t.enterText(
      find.descendant(
          of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(TextField)),
      valeur);
  await t.pump();
}

Future<void> choisir(WidgetTester t, String champ, String cible) async {
  await toucher(
      t,
      find.descendant(
              of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(InkWell))
          .first);
  if (find.text(cible).evaluate().isEmpty) {
    await t.enterText(find.byType(TextField).last, cible);
    await t.pump(const Duration(milliseconds: 200));
  }
  await toucher(t, find.text(cible).last);
  await t.pump(const Duration(milliseconds: 400));
}

String kpi(WidgetTester t, String libelle) => t
    .widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == libelle))
    .valeur;

void cas(String nom, Future<void> Function(WidgetTester) corps) =>
    testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

Fiche demande(Magasin m, String ref) => m
    .collection('demandesAnalyses')
    .toutes
    .firstWhere((d) => d['reference'] == ref);

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  group('m5-prelevement — le circuit : caisse, prélèvement, transmission, réception', () {
    Magasin jeu() => magasin(demandes: [
          dem('LAB-1', 'en_attente', plus: {'bloqueParPaiement': true}),
          dem('LAB-2', 'attente_prelevement', plus: {'statutPaiement': 'soldee', 'urgent': true}),
          dem('LAB-3', 'preleve', plus: {'preleveLe': '2026-10-29T08:00:00.000Z'}),
          dem('LAB-4', 'en_cours', plus: {
            'preleveLe': '2026-10-29T08:00:00.000Z',
            'recuLaboLe': '2026-10-29T09:00:00.000Z'
          }),
        ]);

    cas('les quatre indicateurs et les trois onglets suivent les fiches', (t) async {
      await ouvrir(t, jeu(), 'm5-prelevement');
      expect(kpi(t, 'À prélever'), '1');
      expect(kpi(t, 'En attente de règlement'), '1');
      expect(kpi(t, 'Prélevés, à transmettre'), '1');
      expect(kpi(t, 'Reçus au laboratoire'), '1');
      expect(find.text('Réglée — à prélever'), findsOneWidget);
      expect(find.text('En attente de caisse'), findsOneWidget);
    });

    cas('demande impayée : le verrou est visible et parle, le prélèvement est impossible', (t) async {
      final m = jeu();
      await ouvrir(t, m, 'm5-prelevement');
      expect(find.byTooltip('Règlement requis avant prélèvement'), findsOneWidget);
      expect(find.byTooltip('Enregistrer le prélèvement'), findsOneWidget,
          reason: 'seule la demande réglée peut être prélevée');
      await toucher(t, find.byTooltip('Règlement requis avant prélèvement'));
      expect(find.text('Prélèvement impossible.'), findsOneWidget);
      expect(find.textContaining('passer à la caisse'), findsOneWidget);
      expect(demande(m, 'LAB-1')['preleveLe'], isNull);
    });

    cas('prélever : la salle écrit le prélèvement, journalise, et le geste s\'annule', (t) async {
      final m = jeu();
      await ouvrir(t, m, 'm5-prelevement');
      await toucher(t, find.byTooltip('Enregistrer le prélèvement'));
      expect(find.text('Une fois le prélèvement enregistré, le patient peut partir. L’échantillon reste à acheminer au laboratoire avec son bon.'),
          findsOneWidget);
      await saisir(t, 'observationPrelevement', 'À jeun');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Prélèvement effectué'));
      final d = demande(m, 'LAB-2');
      expect(d['preleveLe'], isNotNull);
      expect(d['preleveur'], 'LABO Un');
      expect(d['natureEchantillon'], 'Selles', reason: 'reprise de la demande');
      expect(d['observationPrelevement'], 'À jeun');
      expect(d['etatAnalyse'], 'attente_prelevement', reason: 'E141 : l\'état ne change pas');
      expect(find.text('Prélèvement enregistré.'), findsOneWidget);
      expect(
          m.collection('audit').toutes.any((e) => e['action'] == 'Prélèvement effectué'),
          isTrue);
      expect(kpi(t, 'Prélevés, à transmettre'), '2');
      expect(kpi(t, 'À prélever'), '0');
      await toucher(t, find.text('Annuler').last);
      expect(demande(m, 'LAB-2')['preleveLe'], isNull);
      expect(kpi(t, 'À prélever'), '1');
    });

    cas('prélever avec une nature d\'échantillon vide : formulaire en erreur, rien n\'est écrit', (t) async {
      final m = jeu();
      await ouvrir(t, m, 'm5-prelevement');
      await toucher(t, find.byTooltip('Enregistrer le prélèvement'));
      await saisir(t, 'natureEchantillon', '');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Prélèvement effectué'));
      expect(find.text('Ce champ est obligatoire.'), findsOneWidget);
      expect(demande(m, 'LAB-2')['preleveLe'], isNull);
    });

    cas('transmettre : confirmation, puis l\'échantillon est REÇU et le laboratoire peut saisir', (t) async {
      final m = jeu();
      await ouvrir(t, m, 'm5-prelevement');
      await toucher(t, find.text('À transmettre'));
      await toucher(t, find.byTooltip('Transmettre au laboratoire'));
      expect(find.text('Transmettre l’échantillon au laboratoire ?'), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Transmettre'));
      final d = demande(m, 'LAB-3');
      expect(d['recuLaboLe'], isNotNull);
      expect(d['etatAnalyse'], 'en_cours');
      expect(d['recuPar'], isNotNull);
      expect(find.text('Échantillon transmis au laboratoire.'), findsOneWidget);
      expect(kpi(t, 'Reçus au laboratoire'), '2');
    });

    cas('pas de saisie avant réception : « Saisir le résultat » n\'existe que sur l\'onglet des échantillons reçus', (t) async {
      await ouvrir(t, jeu(), 'm5-prelevement');
      expect(find.byTooltip('Saisir le résultat'), findsNothing);
      await toucher(t, find.text('À transmettre'));
      expect(find.byTooltip('Saisir le résultat'), findsNothing);
      // « Reçus au laboratoire » est aussi un indicateur : on vise l'onglet.
      await toucher(
          t,
          find.descendant(
              of: find.byKey(const Key('kit:onglets-barre')),
              matching: find.textContaining('Reçus au laboratoire')));
      expect(find.byTooltip('Saisir le résultat'), findsOneWidget);
    });

    cas('profil en lecture seule : le bon s\'imprime, aucune commande d\'écriture n\'est offerte', (t) async {
      await ouvrir(t, jeu(), 'm5-prelevement', role: 'echographiste');
      expect(find.byTooltip('Imprimer le bon d’analyse'), findsNWidgets(2));
      expect(find.byTooltip('Enregistrer le prélèvement'), findsNothing);
      expect(find.byTooltip('Règlement requis avant prélèvement'), findsNothing);
    });
  });

  group('m5-demandes — registre, file des prélèvements, création', () {
    cas('file des prélèvements : « Prendre en charge » ne touche que les demandes encore en attente, et clôt la tâche (E146)', (t) async {
      final m = magasin(demandes: [
        dem('LAB-1', 'en_attente', plus: {'ordonnanceId': 'ORD-9'}),
        dem('LAB-2', 'en_attente', plus: {'ordonnanceId': 'ORD-9'}),
        dem('LAB-3', 'attente_prelevement', plus: {'ordonnanceId': 'ORD-9'}),
        dem('LAB-4', 'en_attente', plus: {'ordonnanceId': 'ORD-AUTRE'}),
      ], taches: [
        {
          'id': 'T1',
          'statut': 'en_attente',
          'type': 'prelevement',
          'ordonnanceId': 'ORD-9',
          'reference': 'ORD-9',
          'patient': 'DOSSOU Aline',
          'patientCode': 'CNT/1/26',
          'detail': '3 analyse(s)',
          'montant': 6000,
          'date': '2026-10-29'
        }
      ]);
      await ouvrir(t, m, 'm5-demandes');
      await toucher(t, find.byTooltip('Prendre en charge'));
      expect(demande(m, 'LAB-1')['etatAnalyse'], 'en_cours');
      expect(demande(m, 'LAB-2')['etatAnalyse'], 'en_cours');
      expect(demande(m, 'LAB-3')['etatAnalyse'], 'attente_prelevement');
      expect(demande(m, 'LAB-4')['etatAnalyse'], 'en_attente', reason: 'autre ordonnance');
      expect(m.collection('taches').parId('T1')!['statut'], 'fait');
      expect(find.text('3 analyse(s) prise(s) en charge.'), findsOneWidget);
      expect(find.text('Aucun prélèvement en attente.'), findsOneWidget);
    });

    cas('tâche bloquée par la caisse : verrou, rien ne bouge', (t) async {
      final m = magasin(demandes: [
        dem('LAB-1', 'en_attente', plus: {'ordonnanceId': 'ORD-9'})
      ], taches: [
        {
          'id': 'T1',
          'statut': 'bloque',
          'type': 'prelevement',
          'ordonnanceId': 'ORD-9',
          'reference': 'ORD-9',
          'patient': 'DOSSOU Aline',
          'patientCode': 'CNT/1/26',
          'detail': '1 analyse(s)',
          'montant': 2000,
          'date': '2026-10-29'
        }
      ]);
      await ouvrir(t, m, 'm5-demandes');
      expect(find.byTooltip('Prendre en charge'), findsNothing);
      await toucher(t, find.byTooltip('Bloquée jusqu’à l’encaissement'));
      expect(find.text('Cette opération attend le passage en caisse.'), findsOneWidget);
      expect(m.collection('taches').parId('T1')!['statut'], 'bloque');
      expect(demande(m, 'LAB-1')['etatAnalyse'], 'en_attente');
    });

    Magasin avecRegistre() => magasin(demandes: [
          dem('LAB-00007', 'valide', plus: {'codeAnalyse': '00012-2026', 'origine': 'ordonnance', 'ordonnanceNumero': 'ORD-2026-00007'}),
        ]);

    cas('Nouveau : la demande prend la référence et le code d\'analyse SUIVANTS du registre, l\'analyse vient du catalogue', (t) async {
      final m = avecRegistre();
      await ouvrir(t, m, 'm5-demandes');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
      await choisir(t, 'patientCode', 'CNT/1/26 — DOSSOU Aline');
      await choisir(t, 'analyseCode', 'L02 — ASLO');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      final d = m.collection('demandesAnalyses').actives.first;
      expect(d['reference'], 'LAB-00008', reason: 'le plus grand rang du registre + 1, pas un compteur de page (E142)');
      expect(d['codeAnalyse'], '00013-2026');
      expect(d['analyse'], 'ASLO');
      expect(d['prix'], 4000);
      expect(d['patient'], 'DOSSOU Aline');
      expect(d['patientId'], 'PAT1');
      expect(d['urgent'], false);
      expect(d['etatAnalyse'], 'en_attente');
      expect((d['dateHeure'] as String).startsWith('2026-10-30T00:00'), isTrue);
      expect(find.text('Nouveau demande d’analyse créé.'), findsOneWidget);
      expect(find.text('LAB-00008'), findsWidgets);
      expect(m.collection('patients').toutes.length, 1, reason: 'aucun dossier créé');
    });

    cas('patient adressé de l\'extérieur : son dossier naît (âge déclaré daté), la demande le désigne', (t) async {
      final m = avecRegistre();
      await ouvrir(t, m, 'm5-demandes');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
      await saisir(t, 'nom', 'Kassa');
      await saisir(t, 'prenom', 'Imorou');
      await choisir(t, 'sexe', 'Masculin');
      await choisir(t, 'naissanceConnue', 'Inconnue — indiquer l’âge déclaré');
      await saisir(t, 'age', '41');
      await choisir(t, 'analyseCode', 'L01 — AKOP');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      final p = m.collection('patients').actives.first;
      expect(p['code'], 'CNT/901/26');
      expect(p['nom'], 'KASSA');
      expect(p['externe'], true);
      expect(p['age'], 41);
      expect(p['ageReferenceLe'], '2026-10-30');
      expect(p['origineDossier'], 'Patient externe — laboratoire');
      final d = m.collection('demandesAnalyses').actives.first;
      expect(d['patientCode'], 'CNT/901/26');
      expect(d['patientId'], p['id']);
      expect(d['patient'], 'KASSA Imorou');
      expect(d['origineDemande'], 'externe');
      expect(d.containsKey('nom'), isFalse, reason: 'l\'identité n\'est pas gardée sur la demande');
      expect(d.containsKey('age'), isFalse);
    });

    cas('ni dossier ni identité : refus nommé, la modale reste ouverte, rien n\'est écrit', (t) async {
      final m = avecRegistre();
      await ouvrir(t, m, 'm5-demandes');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
      await choisir(t, 'analyseCode', 'L01 — AKOP');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(
          find.text('Sélectionner un patient du répertoire, ou renseigner le nom ET les prénoms du patient adressé de l’extérieur.'),
          findsOneWidget);
      expect(m.collection('demandesAnalyses').actives.length, 1);
      expect(find.widgetWithText(BoutonSigh, 'Créer'), findsOneWidget);
    });

    cas('Modifier : la référence et le code d\'analyse déjà attribués sont CONSERVÉS (E149)', (t) async {
      final m = avecRegistre();
      await ouvrir(t, m, 'm5-demandes');
      await toucher(t, find.byTooltip('Modifier'));
      await choisir(t, 'analyseCode', 'L02 — ASLO');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final d = demande(m, 'LAB-00007');
      expect(d['reference'], 'LAB-00007');
      expect(d['codeAnalyse'], '00012-2026');
      expect(d['analyse'], 'ASLO');
      expect(d['prix'], 4000);
      expect(m.collection('demandesAnalyses').toutes.length, 1);
      expect(find.text('Modification enregistrée.'), findsOneWidget);
    });

    cas('archiver est annulable (RG-14) et le profil sans droit d\'annuler n\'a pas la commande', (t) async {
      final m = avecRegistre();
      await ouvrir(t, m, 'm5-demandes');
      await toucher(t, find.byTooltip('Archiver'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Archiver'));
      expect(m.collection('demandesAnalyses').actives, isEmpty);
      expect(m.collection('demandesAnalyses').archivees.length, 1);
      await toucher(t, find.text('Annuler').last);
      expect(m.collection('demandesAnalyses').actives.length, 1);
      // Le directeur médical écrit mais n'annule pas : la commande est ABSENTE.
      await ouvrir(t, avecRegistre(), 'm5-demandes', role: 'dm');
      expect(find.byTooltip('Modifier'), findsOneWidget);
      expect(find.byTooltip('Archiver'), findsNothing);
    });
  });

  group('vues par service demandeur', () {
    Magasin jeu() => magasin(demandes: [
          dem('LAB-M1', 'en_attente', plus: {'secteurDemandeur': 'MATERNITÉ'}),
          dem('LAB-M2', 'attente_prelevement', plus: {'serviceDemandeur': 'Maternité'}),
          dem('LAB-M3', 'valide', plus: {'serviceDemandeur': 'maternite'}),
          dem('LAB-H1', 'en_attente', plus: {'hospitalise': true}),
          dem('LAB-H2', 'rectifie', plus: {'secteurDemandeur': 'MISE EN OBSERVATION'}),
          dem('LAB-X1', 'en_attente', plus: {'secteurDemandeur': 'CHIRURGIE', 'hospitalise': false}),
          dem('LAB-M4', 'valide', plus: {'secteurDemandeur': 'MATERNITÉ', 'statut': 'archive'}),
        ]);

    cas('maternité : le service se lit dans le secteur ET dans le libellé (E145)', (t) async {
      await ouvrir(t, jeu(), 'm5-demandes-maternite');
      for (final r in ['LAB-M1', 'LAB-M2', 'LAB-M3']) {
        expect(find.text(r), findsWidgets, reason: r);
      }
      for (final r in ['LAB-H1', 'LAB-H2', 'LAB-X1', 'LAB-M4']) {
        expect(find.text(r), findsNothing, reason: r);
      }
      expect(kpi(t, 'Demandes du service'), '3');
      expect(kpi(t, 'En attente de règlement'), '1');
      expect(kpi(t, 'À prélever / transmettre'), '1');
      expect(kpi(t, 'Résultats rendus'), '1');
    });

    cas('hospitalisation : patients hospitalisés ou en observation', (t) async {
      await ouvrir(t, jeu(), 'm5-demandes-hospitalisation');
      expect(find.text('LAB-H1'), findsWidgets);
      expect(find.text('LAB-H2'), findsWidgets);
      expect(find.text('LAB-M1'), findsNothing);
      expect(kpi(t, 'Demandes du service'), '2');
      expect(kpi(t, 'Résultats rendus'), '1', reason: 'rectifiée = rendue');
    });

    cas('cliquer une ligne ouvre la fiche en tiroir', (t) async {
      await ouvrir(t, jeu(), 'm5-demandes-hospitalisation');
      await toucher(t, find.text('LAB-H1').first);
      expect(find.text('Résultat non encore saisi.'), findsOneWidget);
    });
  });
}
