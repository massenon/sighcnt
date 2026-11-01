// Les écrans du profil soignant : agenda du jour, dossier en lecture, constantes, note, prescription. Le moteur est faux mais le SERVICE est le vrai :
// ce que l'écran affiche et refuse vient des règles de packages/domaine.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_mobile/main.dart';
import 'package:sigh_mobile/moteur/moteur_mobile.dart';

import 'aide_mobile.dart';

/// Le médicament se CHOISIT dans le catalogue du lot (E1559) : on ouvre la liste et on touche la ligne.
Future<void> choisirMedicament(WidgetTester t, String designation) async {
  await t.tap(find.byKey(const Key('champ-med')));
  await t.pumpAndSettle();
  await t.tap(find.textContaining(designation).last);
  await t.pumpAndSettle();
}

Future<FauxMoteur> ouvrir(WidgetTester t, {String fonction = 'medecin', SourceMemoire? source}) async {
  t.view.physicalSize = const Size(800, 1800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final m = FauxMoteur(fonction: fonction, source: source)..profil = ProfilMobile.soignant;
  await t.pumpWidget(SighMobile(moteur: m));
  await t.pumpAndSettle();
  return m;
}

Future<void> ouvrirDossierDe(WidgetTester t, String id) async {
  await t.tap(find.byKey(const Key('onglet-dossiers')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(Key('patient-$id')));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('agenda du jour : les rendez-vous par heure, le planifié d\'un jour passé signalé à part ; un toucher ouvre le dossier', (t) async {
    await ouvrir(t);
    expect(find.text('Ma tournée'), findsOneWidget);
    expect(find.text('09h30'), findsOneWidget);
    expect(find.text('DOSSOU Aline'), findsOneWidget);
    expect(find.textContaining('Suivi HTA'), findsOneWidget);
    expect(find.text('10h45'), findsOneWidget);
    expect(find.byKey(const Key('en-souffrance')), findsOneWidget);
    expect(find.text('TAMOU Félix'), findsOneWidget);
    expect(find.textContaining('demain et après'), findsNothing, reason: 'un rendez-vous futur n\'est pas dans l\'agenda du jour');
    expect(find.textContaining('archivé'), findsNothing);

    await t.tap(find.byKey(const Key('rdv-0')));
    await t.pumpAndSettle();
    expect(find.text('DOSSOU Aline'), findsWidgets);
    expect(find.text('Carte valide'), findsOneWidget);
  });

  testWidgets('agenda vide : l\'écran le dit', (t) async {
    await ouvrir(t, source: SourceMemoire({'patients': []}));
    expect(find.byKey(const Key('agenda-vide')), findsOneWidget);
  });

  testWidgets('dossier en lecture : couverture, allergies, motif, dernières constantes hors bornes', (t) async {
    await ouvrir(t);
    await ouvrirDossierDe(t, 'p1');
    expect(find.text('Carte valide'), findsOneWidget);
    expect(find.byKey(const Key('allergies')), findsOneWidget);
    expect(find.text('Pénicilline'), findsOneWidget);
    expect(find.textContaining('Visite à 09h30'), findsOneWidget);
    expect(find.textContaining('T° 38.6'), findsOneWidget);
    expect(find.textContaining('TA 120/80'), findsOneWidget);
    expect(find.text('Hors bornes : température'), findsOneWidget);
    expect(find.byKey(const Key('notes-vide')), findsOneWidget);

    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('patient-p2')));
    await t.pumpAndSettle();
    expect(find.text('CARTE NON VALIDE'), findsOneWidget);
    expect(find.textContaining('facturation intégrale au patient (RG-09)'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('patient-p3')));
    await t.pumpAndSettle();
    expect(find.text('Non assuré'), findsOneWidget);
    expect(find.byKey(const Key('constantes-vide')), findsOneWidget);
  });

  testWidgets('les commandes du médecin : constantes, note et prescription', (t) async {
    await ouvrir(t);
    await ouvrirDossierDe(t, 'p1');
    await t.scrollUntilVisible(find.byKey(const Key('prescrire')), 300, scrollable: find.byType(Scrollable).last);
    expect(find.byKey(const Key('saisir-constantes')), findsOneWidget);
    expect(find.byKey(const Key('nouvelle-note')), findsOneWidget);
    expect(find.byKey(const Key('prescrire')), findsOneWidget);
  });

  testWidgets('les commandes de l\'infirmier : les constantes seulement, les autres commandes sont ABSENTES', (t) async {
    await ouvrir(t, fonction: 'infirmier');
    await ouvrirDossierDe(t, 'p1');
    await t.scrollUntilVisible(find.byKey(const Key('saisir-constantes')), 300, scrollable: find.byType(Scrollable).last);
    expect(find.byKey(const Key('saisir-constantes')), findsOneWidget);
    expect(find.byKey(const Key('nouvelle-note')), findsNothing);
    expect(find.byKey(const Key('prescrire')), findsNothing);
  });

  testWidgets('la sage-femme (habilitée mais écran fermé au profil du simulateur) n\'a pas la commande de prescription', (t) async {
    await ouvrir(t, fonction: 'sage_femme');
    await ouvrirDossierDe(t, 'p1');
    await t.scrollUntilVisible(find.byKey(const Key('saisir-constantes')), 300, scrollable: find.byType(Scrollable).last);
    expect(find.byKey(const Key('prescrire')), findsNothing);
    expect(find.byKey(const Key('nouvelle-note')), findsNothing);
  });

  testWidgets('constantes : refus nommé sur le champ, puis enregistrement nommé à l\'agent', (t) async {
    final m = await ouvrir(t);
    await ouvrirDossierDe(t, 'p1');
    await t.tap(find.byKey(const Key('saisir-constantes')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('champ-temperature')), 'chaud');
    await t.tap(find.byKey(const Key('enregistrer')));
    await t.pump();
    expect(find.text('La température doit être un nombre.'), findsOneWidget);
    expect(m.source.de('constantes'), isEmpty);

    await t.enterText(find.byKey(const Key('champ-temperature')), '57');
    await t.tap(find.byKey(const Key('enregistrer')));
    await t.pump();
    expect(find.text('La température : valeur improbable (30 à 45).'), findsOneWidget);

    await t.enterText(find.byKey(const Key('champ-temperature')), '38,5');
    await t.enterText(find.byKey(const Key('champ-sys')), '120');
    await t.enterText(find.byKey(const Key('champ-dia')), '80');
    await t.tap(find.byKey(const Key('enregistrer')));
    await t.pumpAndSettle();
    final c = m.source.de('constantes').single;
    expect(c['temperature'], 38.5);
    expect(c['tension'], '120/80');
    expect(c['releveePar'], 'Dr YENI M’PO Florent');
    expect(find.textContaining('Fièvre (38,5 °C)'), findsOneWidget);
  });

  testWidgets('note de consultation puis prescription : sans note, refus affiché avec code, motif et geste ; après la note, l\'ordonnance part', (t) async {
    final m = await ouvrir(t);
    await ouvrirDossierDe(t, 'p1');
    await t.scrollUntilVisible(find.byKey(const Key('prescrire')), 300, scrollable: find.byType(Scrollable).last);
    await t.tap(find.byKey(const Key('prescrire')));
    await t.pumpAndSettle();
    await choisirMedicament(t, 'PARACETAMOL 500 MG');
    await t.enterText(find.byKey(const Key('champ-quantite')), '2');
    await t.enterText(find.byKey(const Key('champ-poso')), '1 cp x 3/j');
    await t.enterText(find.byKey(const Key('champ-duree')), '5');
    await t.tap(find.byKey(const Key('envoyer-prescription')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('refus-code')), findsOneWidget);
    expect(find.text('SANS_NOTE'), findsOneWidget);
    expect(find.text('Texte proposé, à valider.'), findsOneWidget, reason: 'la durée « du jour » de la note n\'a pas de source : le dire à l\'écran (E1557)');
    expect(find.textContaining('la prescription se fait après l’enregistrement de la fiche'), findsOneWidget);
    expect(find.text('À faire : Enregistrer d’abord la note de consultation'), findsOneWidget);
    expect(m.source.de('prescriptions'), isEmpty);
    await t.pageBack();
    await t.pumpAndSettle();

    // La note : motif repris du rendez-vous, diagnostic « Autre » exigeant sa précision.
    await t.scrollUntilVisible(find.byKey(const Key('nouvelle-note')), 300, scrollable: find.byType(Scrollable).last);
    await t.tap(find.byKey(const Key('nouvelle-note')));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Suivi HTA'), findsOneWidget, reason: 'le motif du rendez-vous du jour est repris');
    await t.enterText(find.byKey(const Key('champ-motif')), '');
    await t.scrollUntilVisible(find.byKey(const Key('enregistrer-note')), 300, scrollable: find.byType(Scrollable).last);
    await t.tap(find.byKey(const Key('enregistrer-note')));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const Key('champ-motif')), -300, scrollable: find.byType(Scrollable).last);
    expect(find.text('Le motif est obligatoire.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('champ-motif')), 'Suivi HTA');
    await t.scrollUntilVisible(find.byKey(const Key('champ-diagnostic')), 300, scrollable: find.byType(Scrollable).last);
    await t.tap(find.byKey(const Key('champ-diagnostic')));
    await t.pumpAndSettle();
    await t.tap(find.text('Autre (à préciser)').last);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const Key('enregistrer-note')), 300, scrollable: find.byType(Scrollable).last);
    await t.tap(find.byKey(const Key('enregistrer-note')));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const Key('champ-precision')), -300, scrollable: find.byType(Scrollable).last);
    expect(find.text('Rédiger le diagnostic retenu.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('champ-precision')), 'Dermatose');
    await t.scrollUntilVisible(find.byKey(const Key('enregistrer-note')), 300, scrollable: find.byType(Scrollable).last);
    await t.tap(find.byKey(const Key('enregistrer-note')));
    await t.pumpAndSettle();
    final n = m.source.de('notes').single;
    expect(n['diagnostic'], 'Dermatose');
    expect(n['redigePar'], 'Dr YENI M’PO Florent');
    expect(find.textContaining('Suivi HTA : Dermatose'), findsOneWidget, reason: 'la note se relit au dossier');

    await t.scrollUntilVisible(find.byKey(const Key('prescrire')), 300, scrollable: find.byType(Scrollable).last);
    await t.tap(find.byKey(const Key('prescrire')));
    await t.pumpAndSettle();
    await choisirMedicament(t, 'PARACETAMOL 500 MG');
    await t.enterText(find.byKey(const Key('champ-quantite')), '2');
    await t.enterText(find.byKey(const Key('champ-poso')), '1 cp x 3/j');
    await t.enterText(find.byKey(const Key('champ-duree')), '0');
    await t.tap(find.byKey(const Key('envoyer-prescription')));
    await t.pumpAndSettle();
    expect(find.text('La durée : valeur improbable (1 à 90).'), findsOneWidget);
    await t.enterText(find.byKey(const Key('champ-duree')), '5');
    await t.tap(find.byKey(const Key('envoyer-prescription')));
    await t.pumpAndSettle();
    expect(m.source.de('prescriptions').single['emise'], isTrue);
    expect(find.textContaining('Ordonnance : PARACETAMOL 500 MG'), findsOneWidget, reason: 'la prescription se relit au dossier');
  });

  testWidgets('le catalogue du lot : stock insuffisant refusé en le nommant (RG-03), médicament hors catalogue, quantité exigée', (t) async {
    final m = await ouvrir(t);
    await m.soignant!.enregistrerNote('p1', {'motif': 'm', 'diagnostic': 'Gastro-entérite'});
    await ouvrirDossierDe(t, 'p1');
    await t.scrollUntilVisible(find.byKey(const Key('prescrire')), 300, scrollable: find.byType(Scrollable).last);
    await t.tap(find.byKey(const Key('prescrire')));
    await t.pumpAndSettle();
    expect(find.textContaining('La prescription part à la clinique par le relais.'), findsOneWidget);
    expect(find.textContaining('Prescrire génère l’ordonnance'), findsNothing, reason: 'la phrase de la maquette n\'est vraie qu\'après la transcription par le poste');
    await t.tap(find.byKey(const Key('envoyer-prescription')));
    await t.pumpAndSettle();
    expect(find.text('Le médicament est obligatoire.'), findsOneWidget);
    expect(find.text('La quantité est obligatoire.'), findsOneWidget);
    await choisirMedicament(t, 'AMOXICILLINE 500 MG');
    await t.enterText(find.byKey(const Key('champ-quantite')), '3');
    await t.enterText(find.byKey(const Key('champ-poso')), '1');
    await t.enterText(find.byKey(const Key('champ-duree')), '3');
    await t.tap(find.byKey(const Key('envoyer-prescription')));
    await t.pumpAndSettle();
    expect(find.text('Stock insuffisant pour « AMOXICILLINE 500 MG » : disponible : 2 ; demandé : 3 (RG-03).'), findsWidgets);
    expect(m.source.de('prescriptions'), isEmpty, reason: 'rien n\'est écrit');
  });

  testWidgets('au dossier : la prescription attend, puis le compte rendu du poste dit « transcrite » (et seulement alors, la phrase de la maquette) ou « refusée »', (t) async {
    final m = await ouvrir(t);
    await m.soignant!.enregistrerNote('p1', {'motif': 'm', 'diagnostic': 'Gastro-entérite'});
    final id = await m.soignant!.prescrireMedicament('p1', {'med': 'PRD0001', 'quantite': '2', 'poso': '1 cp x 3/j', 'duree': '5'});
    await ouvrirDossierDe(t, 'p1');
    await t.scrollUntilVisible(find.byKey(Key('transcription-$id')), 300, scrollable: find.byType(Scrollable).last);
    expect(find.text('En attente de transcription par la clinique.'), findsOneWidget);
    expect(find.textContaining('Prescrire génère'), findsNothing);

    m.source.donnees['transcriptions'] = [
      LigneLot('t1', {'prescriptionId': id, 'etat': 'transcrite', 'ordonnance': 'ORD-2026-00007', 'facture': 'FP-2026-00012', 'montant': 1000})
    ];
    await t.pageBack();
    await t.pumpAndSettle();
    await ouvrirDossierDe(t, 'p1');
    await t.scrollUntilVisible(find.byKey(Key('transcription-$id')), 300, scrollable: find.byType(Scrollable).last);
    expect(find.textContaining('Transcrite par la clinique : ordonnance ORD-2026-00007, facture FP-2026-00012.'), findsOneWidget);
    expect(find.textContaining('Prescrire génère l’ordonnance et la facture de la caisse.'), findsOneWidget);

    m.source.donnees['transcriptions'] = [
      LigneLot('t2', {'prescriptionId': id, 'etat': 'refusee', 'code': 'STOCK_INSUFFISANT', 'motif': 'Stock insuffisant (RG-03).', 'geste': 'Corriger la quantité.', 'date': '2026-10-31T11:00'})
    ];
    await t.pageBack();
    await t.pumpAndSettle();
    await ouvrirDossierDe(t, 'p1');
    await t.scrollUntilVisible(find.byKey(Key('transcription-$id')), 300, scrollable: find.byType(Scrollable).last);
    expect(find.textContaining('Refusée par la clinique : Stock insuffisant (RG-03).'), findsOneWidget);
    expect(find.textContaining('À faire : Corriger la quantité. (STOCK_INSUFFISANT)'), findsOneWidget);
    expect(find.textContaining('Prescrire génère'), findsNothing);
  });

  testWidgets('demande d\'analyses : aucun examen refusé avec le texte de l\'écran, puis la demande part', (t) async {
    final m = await ouvrir(t);
    await m.soignant!.enregistrerNote('p1', {'motif': 'm', 'diagnostic': 'Gastro-entérite'});
    await ouvrirDossierDe(t, 'p1');
    await t.scrollUntilVisible(find.byKey(const Key('prescrire')), 300, scrollable: find.byType(Scrollable).last);
    await t.tap(find.byKey(const Key('prescrire')));
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: find.byKey(const Key('nature')), matching: find.text('Analyses de laboratoire')));
    await t.pumpAndSettle();
    expect(find.textContaining('Rien ne se prélève avant le paiement'), findsOneWidget);
    await t.tap(find.byKey(const Key('envoyer-prescription')));
    await t.pumpAndSettle();
    expect(find.text('Cochez au moins un examen.'), findsOneWidget);
    await t.tap(find.byKey(const Key('examen-NFS')));
    await t.pump();
    await t.tap(find.byKey(const Key('envoyer-prescription')));
    await t.pumpAndSettle();
    expect(m.source.de('prescriptions').single['examens'], ['NFS']);
  });

  testWidgets('lot expiré : la saisie est refusée en le disant, le bouton ne ment pas', (t) async {
    final src = lotDeDemonstration()..fin = horloge.millisecondsSinceEpoch - 1000;
    final m = await ouvrir(t, source: src);
    await ouvrirDossierDe(t, 'p1');
    await t.tap(find.byKey(const Key('saisir-constantes')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('champ-temperature')), '37');
    await t.tap(find.byKey(const Key('enregistrer')));
    await t.pumpAndSettle();
    expect(find.text('LOT_EXPIRE'), findsOneWidget);
    expect(find.textContaining('Le lot de la tournée a expiré le 31/10/2026'), findsOneWidget);
    expect(m.source.ecritures, isEmpty);
  });
}
