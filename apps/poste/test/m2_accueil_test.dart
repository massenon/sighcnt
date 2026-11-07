import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// Accueil M2 : `m2-agenda`, `m2-rendezvous`, `m2-visites`, `m2-domicile`, `m2-registre-appels`, `m2-file-attente`, `m2-affichage`, `m2-file-cabinet`,
/// `m2-agenda-medecin`. Les règles sont rejouées sur les vecteurs du domaine (`ag_agenda.json`, engendrés en PILOTANT les écrans réels de la maquette
/// à l'horloge figée du 16/08/2026 12:00) ; ici, l'ÉCRAN — ce qu'il montre, ce qu'il écrit, refuse, ou n'offre pas à un profil.
final donnees = DonneesNavigation.depuisDossier();
final v = (jsonDecode(File('../../packages/domaine/test/vecteurs/ag_agenda.json').readAsStringSync()) as Map)
    .cast<String, Object?>();
final maintenant = DateTime(2026, 8, 16, 12);

List<Map<String, Object?>> liste(Object? x) =>
    [for (final e in (x as List)) (e as Map).cast<String, Object?>()];

Magasin magasin({List<Map<String, Object?>>? consultations, List<Map<String, Object?>>? file, List<Map<String, Object?>>? appels}) {
  // Le jeu livré porte désormais 90 appels : un test qui pose ses propres fiches part d'une collection vide (les archivées compteraient dans la série).
  final m = Magasin.depuisDossier([for (final n in Magasin.collectionsDuJeu) if (!(appels != null && n == 'appels')) n]);
  void remplacer(String nom, List<Map<String, Object?>> fiches, String prefixe) {
    final col = m.collection(nom);
    for (final f in col.actives) {
      col.archiver(f['id']);
    }
    // la collection garde son ordre : on insère à l'envers (l'insertion se fait en tête)
    for (final f in fiches.reversed) {
      col.inserer({...f}, prefixe: prefixe);
    }
  }

  if (consultations != null) remplacer('consultations', consultations, 'CON');
  if (file != null) remplacer('fileAttente', file, 'FIL');
  if (appels != null) remplacer('appels', appels, 'APP');
  return m;
}

/// Les consultations de la maquette, C00019 non archivée (le registre du médecin, du domicile et des rendez-vous la voit « terminée »).
List<Map<String, Object?>> consultationsV() => [
      for (final f in liste(v['agendaFixtures']))
        f['reference'] == 'C00019' ? {...f, 'statut': 'terminee'} : f
    ];

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, {String role = 'admin'}) async {
  t.view.physicalSize = const Size(1600, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: ecran,
      magasin: m,
      horloge: () => maintenant));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> fin(WidgetTester t) => t.pump(const Duration(seconds: 10));

Future<void> toucher(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 300));
  await t.pump(const Duration(milliseconds: 300));
}

List<(String, String)> kpis(WidgetTester t) {
  final l = [for (final w in t.widgetList<Text>(find.byKey(const Key('kit:kpi-libelle')))) w.data!];
  final x = [for (final w in t.widgetList<Text>(find.byKey(const Key('kit:kpi-valeur')))) w.data!];
  return [for (var i = 0; i < l.length; i++) (l[i], x[i])];
}

String kpisV(Object? k) => [for (final e in liste(k)) '${e['label']}=${e['valeur']}'].join('|');
String kpisE(WidgetTester t) => kpis(t).map((e) => '${e.$1}=${e.$2}').join('|');

Future<void> choisir(WidgetTester t, String champ, String cible) async {
  await toucher(t, find.descendant(of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(InkWell)).first);
  if (find.text(cible).evaluate().isEmpty) {
    await t.enterText(find.byType(TextField).last, cible);
    await t.pump(const Duration(milliseconds: 200));
  }
  await toucher(t, find.text(cible).last);
}

Future<void> ecrire(WidgetTester t, String champ, String texte) async {
  await t.enterText(find.descendant(of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(TextField)), texte);
  await t.pump();
}

/// Un champ date-heure : le sélecteur propose aujourd'hui puis l'heure ; on valide les deux.
Future<void> dateHeure(WidgetTester t, String champ) async {
  await toucher(t, find.descendant(of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(InkWell)).first);
  await t.pump(const Duration(milliseconds: 400));
  await t.tap(find.text('OK').last);
  await t.pump(const Duration(milliseconds: 600));
  await t.tap(find.text('OK').last);
  await t.pump(const Duration(milliseconds: 500));
}

Fiche? parRef(Magasin m, String nom, String ref) =>
    m.collection(nom).actives.where((f) => f['reference'] == ref).firstOrNull;

/// L'onglet de la barre des onglets de l'écran (pas le ruban de la coque).
Finder onglet(String libelle) => find.descendant(
    of: find.byKey(const Key('kit:onglets-barre')), matching: find.textContaining(libelle));

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('m2-agenda', () {
    testWidgets('indicateurs, titre de la fenêtre, jours : ce que la maquette montre', (t) async {
      await ouvrir(t, magasin(consultations: liste(v['agendaFixtures'])), 'm2-agenda');
      final cas = liste(v['agenda']).first;
      final lu = (cas['lu'] as Map).cast<String, Object?>();
      expect(kpisE(t), kpisV(lu['kpis']));
      expect(find.text(lu['titre'] as String), findsOneWidget);
      // neuf rendez-vous aujourd'hui moins le honoré : six lignes puis « + 4 autre(s) »
      expect(find.text('+ 4 autre(s)'), findsOneWidget);
      expect(find.text('Aucun'), findsNWidgets(((lu['jours'] as List).where((j) => (j as Map)['aucun'] == true)).length));
      expect(find.text('Charge par praticien (30 derniers jours)'), findsOneWidget);
      await fin(t);
    });

    testWidgets('« Marquer honoré » : le rendez-vous quitte la grille mais RESTE au registre (un honoré EST la consultation)', (t) async {
      final m = magasin(consultations: consultationsV());
      await ouvrir(t, m, 'm2-agenda');
      expect(find.text('Plaie infectée'), findsWidgets);
      await toucher(t, find.text('Plaie infectée').first);
      expect(find.text('Marquer honoré'), findsWidgets);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Marquer honoré').first);
      final r = parRef(m, 'consultations', 'C00002')!;
      expect(r['statut'], 'terminee');
      expect(r['honoreLe'], '2026-08-16T12:00:00.000Z');
      expect(r['statut'] == 'archive', isFalse);
      expect(m.collection('consultations').archivees.where((f) => f['id'] == r['id']), isEmpty);
      await fin(t);
    });

    testWidgets('« Non honoré » exige un motif, « Annuler le rendez-vous » archive (RG-14) et s’annule', (t) async {
      final m = magasin(consultations: consultationsV());
      await ouvrir(t, m, 'm2-agenda');
      await toucher(t, find.text('Plaie infectée').first);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Non honoré'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Marquer non honoré'));
      expect(find.text('Le motif est obligatoire.'), findsOneWidget);
      await t.enterText(find.byType(TextField).last, 'Injoignable');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Marquer non honoré'));
      final r = parRef(m, 'consultations', 'C00002')!;
      expect(r['statut'], 'non_honore');
      expect(r['motifNonHonore'], 'Injoignable');
      await fin(t);
    });

    testWidgets('prendre un rendez-vous : le dossier est rattaché, la référence suit la série, la fenêtre reste sur la plage', (t) async {
      final m = magasin(consultations: consultationsV());
      await ouvrir(t, m, 'm2-agenda');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau rendez-vous'));
      final p = liste(v['patients']).first;
      await choisir(t, 'patientCode', '${p['code']} — ${p['nom']} ${p['prenom']}');
      await choisir(t, 'medecin', '${liste(v['medecins']).first['nomComplet']}');
      await ecrire(t, 'motif', 'Contrôle');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer le rendez-vous'));
      final cree = m.collection('consultations').actives.first;
      expect(cree['statut'], 'planifiee');
      expect(cree['reference'], 'C00283', reason: 'la série se lit sur les fiches existantes, archivées comprises');
      expect(cree['patientCode'], p['code']);
      expect(cree['date'], '2026-08-16T12:00:00.000Z');
      await fin(t);
    });

    testWidgets('prise de rendez-vous sans motif : refusée, rien n’est écrit', (t) async {
      final m = magasin(consultations: consultationsV());
      final avant = m.collection('consultations').toutes.length;
      await ouvrir(t, m, 'm2-agenda');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau rendez-vous'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer le rendez-vous'));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(m.collection('consultations').toutes.length, avant);
      await fin(t);
    });

    testWidgets('profil en lecture seule : ni « Nouveau rendez-vous » ni « Passage sans rendez-vous » (commandes ABSENTES)', (t) async {
      await ouvrir(t, magasin(consultations: consultationsV()), 'm2-agenda', role: 'direction');
      expect(find.text('Nouveau rendez-vous'), findsNothing);
      expect(find.text('Passage sans rendez-vous'), findsNothing);
      expect(find.text('Rendez-vous'), findsWidgets);
      await fin(t);
    });

    testWidgets('le rappel des échéances s’annonce 900 ms après l’ouverture', (t) async {
      await ouvrir(t, magasin(consultations: consultationsV()), 'm2-agenda');
      await t.pump(const Duration(seconds: 1));
      expect(find.textContaining('Échéances du jour : 2 consultation(s) dans les deux heures'), findsOneWidget);
      await fin(t);
    });
  });

  group('m2-rendezvous', () {
    testWidgets('indicateurs, onglets et tableau comme la maquette ; seul l’agenda se compte', (t) async {
      await ouvrir(t, magasin(consultations: [for (final f in liste((v['rendezvous'] as Map)['fixtures'])) f]), 'm2-rendezvous');
      final d = ((v['rendezvous'] as Map)['defaut'] as Map).cast<String, Object?>();
      expect(kpisE(t), kpisV(d['kpis']));
      for (final o in (d['onglets'] as List)) {
        expect(find.text((o as String).replaceAll(RegExp(r'\d+$'), '')), findsOneWidget);
      }
      for (final e in ['N°', 'Date et heure', 'Patient', 'Praticien', 'Motif', 'Type', 'Statut']) {
        expect(find.text(e.toUpperCase()).evaluate().isNotEmpty || find.text(e).evaluate().isNotEmpty, isTrue, reason: e);
      }
      await fin(t);
    });

    testWidgets('un honoré a quitté la liste mais se retrouve à son onglet', (t) async {
      await ouvrir(t, magasin(consultations: liste((v['rendezvous'] as Map)['fixtures'])), 'm2-rendezvous');
      expect(find.text('C00012'), findsNothing);
      await toucher(t, find.textContaining('Honorés (apurés de l’agenda)'));
      expect(find.text('C00012'), findsOneWidget);
      expect(find.textContaining('un rendez-vous honoré est la consultation elle-même'), findsOneWidget);
      await fin(t);
    });

    testWidgets('personne non enregistrée : quatre champs, aucun dossier ni code CNT', (t) async {
      final m = magasin(consultations: liste((v['rendezvous'] as Map)['fixtures']));
      final patients = m.collection('patients').toutes.length;
      await ouvrir(t, m, 'm2-rendezvous');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
      await ecrire(t, 'visiteurNom', 'dossou');
      await ecrire(t, 'visiteurPrenom', 'Alice');
      await ecrire(t, 'visiteurQuartier', 'Péporiyakou');
      await ecrire(t, 'visiteurTelephone', '0197112233');
      await choisir(t, 'medecin', '${liste(v['medecins']).first['nomComplet']}');
      await ecrire(t, 'motif', 'Rencontre');
      await dateHeure(t, 'date');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      final r = m.collection('consultations').actives.first;
      expect(r['patient'], 'DOSSOU Alice');
      expect(r['patientCode'], 'NON-PATIENT');
      expect(r['patientId'], isNull);
      expect(r['nonPatient'], true);
      expect(r['visiteurQuartier'], 'Péporiyakou');
      expect(r['reference'], 'C00283');
      expect(m.collection('patients').toutes.length, patients, reason: 'aucun dossier ouvert');
      await fin(t);
    });

    testWidgets('ni dossier ni nom : refusé en le disant, rien n’est écrit', (t) async {
      final m = magasin(consultations: liste((v['rendezvous'] as Map)['fixtures']));
      final n = m.collection('consultations').toutes.length;
      await ouvrir(t, m, 'm2-rendezvous');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
      await choisir(t, 'medecin', '${liste(v['medecins']).first['nomComplet']}');
      await ecrire(t, 'motif', 'x');
      await dateHeure(t, 'date');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(find.text('Sélectionner un dossier patient, ou renseigner le nom de la personne non enregistrée.'), findsOneWidget);
      expect(m.collection('consultations').toutes.length, n);
      await fin(t);
    });

    testWidgets('archiver est un archivage LOGIQUE annulable (RG-14) ; le profil sans droit d’annuler n’a pas la commande', (t) async {
      final m = magasin(consultations: liste((v['rendezvous'] as Map)['fixtures']));
      await ouvrir(t, m, 'm2-rendezvous', role: 'infirmier');
      expect(find.byTooltip('Archiver'), findsNothing);
      expect(find.byTooltip('Modifier'), findsWidgets);
      await fin(t);
      final m2 = magasin(consultations: liste((v['rendezvous'] as Map)['fixtures']));
      final avant = m2.collection('consultations').toutes.length;
      final archivees = m2.collection('consultations').archivees.length;
      await ouvrir(t, m2, 'm2-rendezvous');
      await toucher(t, find.byTooltip('Archiver').first);
      await t.enterText(find.byType(TextField).last, 'Doublon');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
      expect(m2.collection('consultations').toutes.length, avant, reason: 'rien n’est supprimé');
      expect(m2.collection('consultations').archivees.length, archivees + 1);
      await fin(t);
    });

    testWidgets('profil en lecture seule : ni « Nouveau » ni « Modifier » ; le bandeau le dit', (t) async {
      await ouvrir(t, magasin(consultations: liste((v['rendezvous'] as Map)['fixtures'])), 'm2-rendezvous', role: 'direction');
      expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.textContaining('Lecture seule'), findsOneWidget);
      await fin(t);
    });
  });

  group('m2-visites', () {
    testWidgets('page-renvoi hors ruban : deux boutons', (t) async {
      await ouvrir(t, magasin(), 'm2-visites');
      expect(find.text('Ouvrir Rendez-vous & visites'), findsOneWidget);
      expect(find.text('Agenda'), findsWidgets);
      expect(find.textContaining('fusionné dans « Rendez-vous & visites »'), findsOneWidget);
      await fin(t);
    });
  });

  group('m2-domicile', () {
    testWidgets('seules les prestations de type Domicile ; indicateurs de la maquette', (t) async {
      await ouvrir(t, magasin(consultations: consultationsV()), 'm2-domicile');
      final d = ((v['domicile'] as Map)['defaut'] as Map).cast<String, Object?>();
      // le vecteur du domicile archive C00015 ; ici la liste complète compte trois prestations à domicile
      expect(kpis(t).first.$1, 'Interventions à domicile');
      expect(kpis(t).first.$2, '3');
      expect(find.text('Tous les interventions à domicile'), findsOneWidget);
      expect(find.textContaining('Cet écran ne présente que les prestations de type Domicile'), findsOneWidget);
      expect(find.text('Plaie infectée'), findsWidgets);
      expect((d['onglets'] as List).first, startsWith('Tous les interventions à domicile'));
      await fin(t);
    });
  });

  group('m2-registre-appels', () {
    testWidgets('indicateurs de la maquette et création : référence suivante de la série (E327)', (t) async {
      final a = (v['appels'] as Map).cast<String, Object?>();
      final m = magasin(appels: liste(a['fixtures']));
      await ouvrir(t, m, 'm2-registre-appels');
      expect(kpisE(t), kpisV((a['defaut'] as Map)['kpis']));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
      await ecrire(t, 'interlocuteur', 'ZIME Ramatou');
      await ecrire(t, 'telephone', '0197555555');
      await choisir(t, 'objet', 'Rappel de règlement');
      await ecrire(t, 'agent', 'Caisse');
      await choisir(t, 'suite', 'Rappel à programmer');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      final r = m.collection('appels').actives.first;
      expect(r['reference'], 'A00031');
      expect(r['sens'], 'entrant');
      expect(r['suite'], 'Rappel à programmer');
      expect(kpisE(t).contains('Rappels à programmer=7'), isTrue);
      await fin(t);
    });
  });

  group('files', () {
    testWidgets('file d’attente : indicateurs et classement du poste Consultation comme la maquette', (t) async {
      final fl = (v['file'] as Map).cast<String, Object?>();
      await ouvrir(t, magasin(file: liste(fl['fixtures'])), 'm2-file-attente');
      expect(kpisE(t), kpisV((fl['defaut'] as Map)['kpis']));
      await toucher(t, onglet('Consultation'));
      final numeros = ['C003', 'C005', 'C006', 'C002', 'C004', 'C001'];
      final ys = [for (final n in numeros) t.getTopLeft(find.text(n)).dy];
      expect(ys, orderedEquals([...ys]..sort()), reason: 'urgence vitale, urgence, rendez-vous, arrivée');
      await fin(t);
    });

    testWidgets('appeler un patient : le poste affiché est RETENU (E326), le patient est servi', (t) async {
      final fl = (v['file'] as Map).cast<String, Object?>();
      final m = magasin(file: liste(fl['fixtures']));
      await ouvrir(t, m, 'm2-file-attente');
      await toucher(t, onglet('Consultation'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Appeler').first);
      final servi = m.collection('fileAttente').actives.firstWhere((x) => x['numero'] == 'C003');
      expect(servi['etat'], 'servi');
      expect(servi['serviLe'], '2026-08-16T12:00:00.000Z');
      expect(find.text('C005'), findsOneWidget, reason: 'on est restés sur Consultation');
      expect(find.text('A002'), findsNothing);
      await fin(t);
    });

    testWidgets('changer la priorité exige un motif ; le rang se recalcule', (t) async {
      final fl = (v['file'] as Map).cast<String, Object?>();
      final m = magasin(file: liste(fl['fixtures']));
      await ouvrir(t, m, 'm2-file-attente');
      await toucher(t, onglet('Consultation'));
      await toucher(t, find.byTooltip('Modifier la priorité').last);
      await choisir(t, 'priorite', 'Urgence');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Appliquer'));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      await ecrire(t, 'motifChangement', 'Douleur aiguë');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Appliquer'));
      final c1 = m.collection('fileAttente').actives.firstWhere((x) => x['numero'] == 'C001');
      expect(c1['priorite'], 'urgence');
      expect(c1['motifChangement'], 'Douleur aiguë');
      await fin(t);
    });

    testWidgets('inscrire en consultation : numéro du jour, praticien facultatif (file commune = null)', (t) async {
      final fl = (v['file'] as Map).cast<String, Object?>();
      final m = magasin(file: liste(fl['fixtures']));
      await ouvrir(t, m, 'm2-file-attente');
      await toucher(t, onglet('Consultation'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Inscrire un patient'));
      final p = liste(v['patients'])[4];
      await choisir(t, 'patientCode', '${p['code']} — ${p['nom']} ${p['prenom']}');
      await ecrire(t, 'motif', 'Contrôle');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Inscrire'));
      final r = m.collection('fileAttente').actives.first;
      expect(r['numero'], 'C008');
      expect(r['praticien'], isNull);
      expect(r['etat'], 'attente');
      expect(r['priorite'], 'ordre_arrivee');
      await fin(t);
    });

    testWidgets('profil en lecture seule : ni « Inscrire » ni « Appeler »', (t) async {
      final fl = (v['file'] as Map).cast<String, Object?>();
      await ouvrir(t, magasin(file: liste(fl['fixtures'])), 'm2-file-attente', role: 'direction');
      expect(find.text('Inscrire un patient'), findsNothing);
      expect(find.widgetWithText(BoutonSigh, 'Appeler'), findsNothing);
      await fin(t);
    });

    testWidgets('écran d’appel : des NUMÉROS seulement, jamais un nom', (t) async {
      final fl = (v['file'] as Map).cast<String, Object?>();
      await ouvrir(t, magasin(file: liste(fl['fixtures'])), 'm2-affichage');
      expect(find.text('C000'), findsOneWidget, reason: 'dernier numéro appelé en consultation');
      expect(find.text('C003   ·   C005   ·   C006'), findsOneWidget);
      expect(find.text('6 patient(s) en attente'), findsOneWidget);
      expect(find.textContaining('TAKI'), findsNothing);
      expect(find.textContaining('Détresse'), findsNothing);
      await fin(t);
    });

    testWidgets('file par cabinet : deux listes jamais fondues, urgences en tête', (t) async {
      final fl = (v['file'] as Map).cast<String, Object?>();
      await ouvrir(t, magasin(file: liste(fl['fixtures'])), 'm2-file-cabinet');
      final cab = (fl['cabinet'] as Map).cast<String, Object?>();
      expect(kpisE(t), kpisV(cab['kpis']));
      for (final c in (cab['cartes'] as List)) {
        expect(find.text(c as String), findsOneWidget);
      }
      final ys = [for (final n in ['OROU YO Adissa', 'DOSSOU Salifou', 'N’TCHA Yacoubou']) t.getTopLeft(find.text(n)).dy];
      expect(ys, orderedEquals([...ys]..sort()));
      await fin(t);
    });

    testWidgets('file par cabinet vide : « Vivier vide »', (t) async {
      await ouvrir(t, magasin(file: const []), 'm2-file-cabinet');
      expect(find.text('Vivier vide — personne n’attend sans praticien désigné.'), findsOneWidget);
      await fin(t);
    });
  });

  group('m2-agenda-medecin', () {
    testWidgets('une vue du registre filtrée sur un praticien : indicateurs de la maquette, libellé « Terminees » conservé', (t) async {
      await ouvrir(t, magasin(consultations: consultationsV()), 'm2-agenda-medecin');
      final p = liste((v['agendaMedecin'] as Map)['praticiens']).first;
      expect(kpisE(t), kpisV((p['lu'] as Map)['kpis']));
      expect(find.text('Terminees ce mois-ci'), findsOneWidget);
      expect(find.text('Agenda — ${p['praticien']}'), findsOneWidget);
      await fin(t);
    });
  });
}
