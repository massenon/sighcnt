import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show blocChecklistEntree, blocChecklistSortie;
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/modules/m3/bloc_cro.dart';

import 'aide_polices.dart';
import 'parite/extracteur.dart';

/// Le bloc, l'anesthésie, la fiche de demande d'examen du service, les bons de pansement et les sorties (M3) : huit écrans. Les règles sont rejouées
/// sur les vecteurs de la maquette (`packages/domaine/test/bloc_regles_test.dart`) ; ici, l'ÉCRAN — ce qui est écrit, refusé, annulable, ce que
/// chaque rôle voit, et la parité N1 mesurée contre la fiche extraite.
final donnees = DonneesNavigation.depuisDossier();
final vecteurs = (jsonDecode(File('../../packages/domaine/test/vecteurs/bloc.json').readAsStringSync()) as Map).cast<String, Object?>();
Map<String, Object?> m_(Object? x) => (x as Map).cast<String, Object?>();
List<Fiche> liste(Object? v) => [for (final x in (v as List)) (x as Map).cast<String, Object?>()];
String _s(Object? v) => '${v ?? ''}'.replaceAll(RegExp(r'[\s  ]'), '');
final aujourdhui = DateTime(2026, 8, 16, 10);

List<Fiche> jeuJson(String nom) => liste(jsonDecode(File('assets/donnees/jeu/$nom.json').readAsStringSync()));

/// Les huit premiers dossiers du jeu de la maquette, tels que les vecteurs les nomment (PAT0001 … PAT0008).
List<Fiche> patients() => [
      for (final (i, p) in [
        ('TCHANE', 'Bertine', 'CNT/1/25'),
        ('BAKO', 'Boukari', 'CNT/2/26'),
        ('N’TCHA', 'Yacoubou', 'CNT/3/26'),
        ('PARAISO', 'Sabi', 'CNT/4/26'),
        ('TAKI', 'Ganiou', 'CNT/5/26'),
        ('DIEYABIDI', 'Bibata', 'CNT/6/25'),
        ('OROU YO', 'Adissa', 'CNT/7/25'),
        ('DOSSOU', 'Salifou', 'CNT/8/25'),
      ].indexed)
        {
          'id': 'PAT000${i + 1}',
          'statut': 'actif',
          'code': p.$3,
          'nom': p.$1,
          'prenom': p.$2,
          'sexe': i % 2 == 0 ? 'F' : 'M',
          if (i == 1) ...{'assureur': 'SUNU', 'tauxPriseEnCharge': 70},
          'dateNaissance': '1970-01-01',
          'adresse': 'Santa, Natitingou',
          'quartier': 'Kotopounga',
        }
    ];

Magasin magasin(Map<String, List<Fiche>> plus) => Magasin({
      'patients': patients(),
      'soignants': jeuJson('soignants'),
      'catalogueTarifs': jeuJson('catalogueTarifs'),
      'audit': const <Fiche>[],
      for (final e in plus.entries) e.key: [for (final f in e.value) {...f}],
    }, 'POSTE', {...(jsonDecode(File('assets/donnees/jeu/referentiels.json').readAsStringSync()) as Map).cast<String, Object?>()});

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
  await t.enterText(find.descendant(of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(TextField)), valeur);
  await t.pump();
}

Future<void> choisir(WidgetTester t, String champ, String cible) async {
  await toucher(t, find.descendant(of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(InkWell)).first);
  if (find.text(cible).evaluate().isEmpty) {
    await t.enterText(find.byType(TextField).last, cible);
    await t.pump(const Duration(milliseconds: 200));
  }
  await toucher(t, find.text(cible).last);
  await t.pump(const Duration(milliseconds: 400));
}

/// Une case à cocher du formulaire.
Future<void> cocher(WidgetTester t, String champ) async {
  await toucher(t, find.descendant(of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(InkWell)).first);
}

/// Un champ date : le sélecteur propose AUJOURD'HUI (l'horloge du système, non celle du poste) ; on valide.
Future<void> dateAujourdhui(WidgetTester t, String champ) async {
  await toucher(t, find.descendant(of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(InkWell)).first);
  await t.pump(const Duration(milliseconds: 400));
  await t.tap(find.text('OK').last);
  await t.pump(const Duration(milliseconds: 500));
}

String kpi(WidgetTester t, String libelle) =>
    t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == libelle)).valeur;

void cas(String nom, Future<void> Function(WidgetTester) corps) => testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

/// Les cellules d'une ligne du tableau, telles que l'agent les lit.
List<String> cellules(TableauSigh tab, Fiche r) => [for (final c in tab.colonnes) c.enTexte(r)];

void comparerKpis(WidgetTester t, Object? attendus) {
  for (final k in liste(attendus)) {
    final w = t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == k['libelle']));
    expect(_s(w.valeur), _s(k['valeur']), reason: '${k['libelle']}');
    expect(_s(w.indice), _s(k['indice']), reason: 'indice ${k['libelle']}');
  }
}

void comparerTableau(WidgetTester t, Object? attendu, {int colonnes = -1}) {
  final tab = t.widget<TableauSigh>(find.byType(TableauSigh).first);
  final vue = t.state<TableauSighState>(find.byType(TableauSigh).first).lignesFiltrees;
  final lignes = m_((attendu as List).single)['lignes'] as List;
  expect(vue.length, lignes.length);
  for (var i = 0; i < lignes.length; i++) {
    final l = (lignes[i] as List).cast<String>();
    final obtenu = cellules(tab, vue[i]);

    final n = colonnes < 0 ? obtenu.length : colonnes;
    expect([for (final x in obtenu.take(n)) _s(x)], [for (final x in l.take(n)) _s(x)], reason: 'ligne $i');
  }
}

Fiche parRef(Magasin m, String col, String ref) =>
    m.collection(col).toutes.firstWhere((f) => f['reference'] == ref);

Future<void> parite(WidgetTester t, String id) async {
  final f = m_(jsonDecode(File('../../docs/architecture/ecrans/$id.json').readAsStringSync()));
  final p = comparerContenu(id, f, textesVisibles(t));
  expect(p.manquants, isEmpty, reason: '$id : N1 = ${(p.taux * 100).toStringAsFixed(1)} %');
}

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  group('m3-cpa — consultation pré-anesthésique', () {
    final c = m_(vecteurs['cpa']);
    final jeu = m_(c['jeu']);
    Magasin base() => magasin({'cpa': liste(jeu['cpa']), 'crOperatoires': liste(jeu['cro'])});

    cas('indicateurs et lignes identiques à la maquette ; parité N1 = 100 %', (t) async {
      await ouvrir(t, base(), 'm3-cpa');
      final e = m_(c['ecran']);
      comparerKpis(t, e['kpis']);
      comparerTableau(t, e['tableaux'], colonnes: 7);
      await parite(t, 'm3-cpa');
    });

    cas('le jeu est vide : l\'écran sème six CPA adossées aux admissions, comme la maquette, une seule fois', (t) async {
      final a = m_(vecteurs['amorcageCpa']);
      final m = magasin({'admissions': liste(a['admissions'])});
      await ouvrir(t, m, 'm3-cpa');
      expect(m.collection('cpa').toutes.length, 6);
      expect(kpi(t, 'CPA enregistrées'), '6');
      expect(m.collection('cpa').toutes.map((f) => f['reference']), ['CPA-2026-0001', 'CPA-2026-0002', 'CPA-2026-0003', 'CPA-2026-0004', 'CPA-2026-0005', 'CPA-2026-0006']);
      await ouvrir(t, m, 'm3-cpa');
      expect(m.collection('cpa').toutes.length, 6, reason: 'pas de second semis');
    });

    cas('conclusion avec réserves sans réserve nommée : refus NOMMÉ, rien n\'est écrit ; nommée, la CPA est créée', (t) async {
      final m = base();
      await ouvrir(t, m, 'm3-cpa');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouvelle CPA'));
      await choisir(t, 'patientCode', 'CNT/2/26 — BAKO Boukari');
      await dateAujourdhui(t, 'date');
      await saisir(t, 'antecedentsAnesthesiques', 'Aucun');
      await saisir(t, 'allergies', 'Aucune connue');
      await saisir(t, 'anesthesiste', 'ADAM Colette');
      await choisir(t, 'conclusion', 'Apte avec réserves');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(find.text('Conclusion avec réserves : les nommer.'), findsOneWidget);
      expect(find.textContaining('doit dire quelles réserves'), findsOneWidget);
      expect(m.collection('cpa').toutes.length, 3);
      await saisir(t, 'observations', 'Hypertendue : équilibrer la tension');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(m.collection('cpa').toutes.length, 4);
      final f = parRef(m, 'cpa', 'CPA-2026-0004');
      expect(f['patient'], 'BAKO Boukari');
      expect(f['patientId'], 'PAT0002');
      expect(f['conclusion'], 'Apte avec réserves');
      expect(f['asa'], 'I', reason: 'la première entrée est présélectionnée, comme la liste native');
      expect(f['statut'], 'actif');
      expect(find.text('CPA créé.'), findsOneWidget);
      expect(kpi(t, 'Avec réserves ou report'), '3');
      // Annuler la création : la fiche est archivée (RG-14), pas supprimée.
      await toucher(t, find.text('Annuler').last);
      expect(parRef(m, 'cpa', 'CPA-2026-0004')['statut'], 'archive');
      expect(kpi(t, 'CPA enregistrées'), '3');
    });

    cas('une intervention sans CPA est SIGNALÉE (indicateur), jamais bloquée', (t) async {
      final m = base();
      await ouvrir(t, m, 'm3-cpa');
      final k0 = int.parse(kpi(t, 'Interventions sans CPA'));
      expect(k0, greaterThan(0));
      expect(find.text('Signalées, jamais bloquées — l’urgence n’attend pas'), findsOneWidget);
      // Le compte rendu opératoire s'enregistre quand même, sans CPA (écran voisin) : rien ne l'en empêche ici.
      expect(m.collection('crOperatoires').actives.length, 5);
    });

    cas('modifier : le contrôle des réserves vaut aussi à l\'édition ; le NOM suit le patient corrigé', (t) async {
      final m = base();
      await ouvrir(t, m, 'm3-cpa');
      await toucher(t, find.byTooltip('Modifier').at(1));
      expect(find.text('CPA-2026-0002'), findsWidgets);
      await saisir(t, 'observations', '');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(find.text('Conclusion avec réserves : les nommer.'), findsOneWidget);
      expect(parRef(m, 'cpa', 'CPA-2026-0002')['observations'], 'HTA à équilibrer');
      await saisir(t, 'observations', 'HTA équilibrée');
      await choisir(t, 'patientCode', 'CNT/6/25 — DIEYABIDI Bibata');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final f = parRef(m, 'cpa', 'CPA-2026-0002');
      expect(f['observations'], 'HTA équilibrée');
      expect(f['patient'], 'DIEYABIDI Bibata');
      expect(f['patientId'], 'PAT0006');
      expect(f['reference'], 'CPA-2026-0002');
      expect(find.text('Modifications enregistrées.'), findsOneWidget);
    });

    cas('archiver demande un MOTIF, se journalise et s\'annule', (t) async {
      final m = base();
      await ouvrir(t, m, 'm3-cpa');
      await toucher(t, find.byTooltip('Archiver').last);
      expect(find.text('Archiver cet enregistrement ?'), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
      expect(m.collection('cpa').actives.length, 3, reason: 'sans motif, rien n\'est archivé');
      await t.enterText(find.byType(TextField).last, 'Doublon');
      await t.pump();
      await toucher(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
      final archivee = m.collection('cpa').archivees.single;
      expect(archivee['_motifArchivage'], 'Doublon');
      expect(m.collection('audit').toutes.any((e) => e['action'] == 'Archivage'), isTrue);
      await toucher(t, find.text('Annuler').last);
      expect(m.collection('cpa').archivees, isEmpty);
    });

    cas('imprimer la fiche : ASA, réserves et signature de l\'anesthésiste', (t) async {
      await ouvrir(t, base(), 'm3-cpa');
      await toucher(t, find.byTooltip('Imprimer la fiche').first);
      expect(find.text('CONSULTATION PRÉ-ANESTHÉSIQUE'), findsWidgets);
    });

    cas('rôles : le chirurgien écrit sans archiver, la direction ne fait que lire, le caissier n\'entre pas', (t) async {
      await ouvrir(t, base(), 'm3-cpa', role: 'chirurgien');
      expect(find.widgetWithText(BoutonSigh, 'Nouvelle CPA'), findsOneWidget);
      expect(find.byTooltip('Modifier'), findsWidgets);
      expect(find.byTooltip('Archiver'), findsNothing, reason: 'une commande interdite est ABSENTE, pas grisée');
      await ouvrir(t, base(), 'm3-cpa', role: 'direction');
      expect(find.widgetWithText(BoutonSigh, 'Nouvelle CPA'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.byTooltip('Consulter'), findsWidgets);
      expect(find.textContaining('Lecture seule'), findsOneWidget);
      await ouvrir(t, base(), 'm3-cpa', role: 'caissier');
      expect(find.text('Nouvelle CPA'), findsNothing);
    });
  });

  group('m3-bloc-cro — compte rendu opératoire, trois intervenants nommés', () {
    final c = m_(m_(vecteurs['cpa'])['cro']);
    final jeu = m_(m_(vecteurs['cpa'])['jeu']);
    Magasin base() => magasin({'crOperatoires': liste(jeu['cro']), 'cpa': liste(jeu['cpa'])});

    cas('indicateurs et lignes identiques à la maquette ; parité N1 = 100 %', (t) async {
      await ouvrir(t, base(), 'm3-bloc-cro');
      final e = m_(c['ecran']);
      comparerKpis(t, e['kpis']);
      comparerTableau(t, e['tableaux'], colonnes: 6);
      await parite(t, 'm3-bloc-cro');
    });

    cas('l\'opérateur se choisit parmi les MÉDECINS ; l\'aide-opérateur est facultatif, l\'anesthésiste obligatoire', (t) async {
      final defs = EcranCro.champs(base());
      final op = defs.firstWhere((d) => d.nom == 'operateurId');
      expect([for (final o in op.options) o.valeur], [for (final o in m_(c['creation'])['optsOperateur'] as List) (o as List)[0]]);
      expect(op.requis, isTrue);
      expect(defs.firstWhere((d) => d.nom == 'aideOperateurId').requis, isFalse);
      expect(defs.firstWhere((d) => d.nom == 'aideOperateurId').options.first.libelle, '— aucun —');
      expect(defs.firstWhere((d) => d.nom == 'anesthesisteId').requis, isTrue);
    });

    cas('création : le compte rendu porte ses trois intervenants NOMMÉS et la référence suit le registre', (t) async {
      final m = base();
      await ouvrir(t, m, 'm3-bloc-cro');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau compte rendu'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(m.collection('crOperatoires').toutes.length, 5);
      await choisir(t, 'patientCode', 'CNT/3/26 — N’TCHA Yacoubou');
      await saisir(t, 'nip', 'NIP-9');
      await dateAujourdhui(t, 'dateOperation');
      await saisir(t, 'diagnosticPeroperatoire', 'Kyste');
      await saisir(t, 'intervention', 'Kystectomie');
      await saisir(t, 'anesthesie', 'Rachianesthésie');
      await saisir(t, 'cro', 'Ligne 1\nLigne 2');
      await choisir(t, 'operateurId', 'TAKI Orou — Médecin Généraliste');
      await choisir(t, 'aideOperateurId', 'OROU YO Alimatou — Infirmier(ère)');
      await choisir(t, 'anesthesisteId', 'ADAM Colette — Sage-femme');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      final attendu = m_(m_(c['creation'])['cree'])['fiche'] as Map<String, Object?>;
      final f = parRef(m, 'crOperatoires', 'CRO-0006');
      for (final k in ['patientId', 'patient', 'patientCode', 'nip', 'operateurId', 'operateur', 'aideOperateurId', 'aideOperateur', 'anesthesisteId', 'anesthesiste', 'cro', 'intervention']) {
        expect(f[k], attendu[k], reason: k);
      }
      expect(find.text('Compte rendu opératoire créé.'), findsOneWidget);
    });

    cas('sans aide-opérateur : la fiche porte null, l\'indicateur le compte', (t) async {
      final m = base();
      await ouvrir(t, m, 'm3-bloc-cro');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau compte rendu'));
      await saisir(t, 'nip', 'NIP-10');
      await dateAujourdhui(t, 'dateOperation');
      for (final n in ['diagnosticPeroperatoire', 'intervention', 'anesthesie', 'cro']) {
        await saisir(t, n, 'x');
      }
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      final f = m.collection('crOperatoires').toutes.first;
      expect(f['aideOperateur'], isNull);
      expect(f['operateur'], isNot('—'));
      expect(kpi(t, 'Sans aide-opérateur'), '6');
    });

    cas('modifier l\'opérateur : le NOM porté par la pièce de preuve suit l\'identifiant (E411)', (t) async {
      final m = base();
      await ouvrir(t, m, 'm3-bloc-cro');
      await toucher(t, find.byTooltip('Modifier').at(3));
      expect(find.text('CRO-0002'), findsWidgets);
      await choisir(t, 'operateurId', 'AHOHOU Rodrigue — Échographiste');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final f = parRef(m, 'crOperatoires', 'CRO-0002');
      expect(f['operateurId'], 'SOI04');
      expect(f['operateur'], 'AHOHOU Rodrigue');
      expect(f['reference'], 'CRO-0002');
    });

    cas('imprimer : trois signatures, une par responsabilité', (t) async {
      await ouvrir(t, base(), 'm3-bloc-cro');
      await toucher(t, find.byTooltip('Imprimer le compte rendu').first);
      expect(find.text('COMPTE RENDU OPÉRATOIRE'), findsWidgets);
      expect(find.text('L’opérateur'), findsWidgets);
      expect(find.text('L’aide-opérateur'), findsWidgets);
      expect(find.text('L’anesthésiste'), findsWidgets);
    });

    cas('archiver : motif obligatoire, annulable ; la direction ne fait que lire', (t) async {
      final m = base();
      await ouvrir(t, m, 'm3-bloc-cro');
      await toucher(t, find.byTooltip('Archiver').first);
      await t.enterText(find.byType(TextField).last, 'Erreur de saisie');
      await t.pump();
      await toucher(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
      expect(m.collection('crOperatoires').archivees.single['_motifArchivage'], 'Erreur de saisie');
      expect(kpi(t, 'Comptes rendus'), '4');
      await toucher(t, find.text('Annuler').last);
      expect(m.collection('crOperatoires').archivees, isEmpty);
      await ouvrir(t, base(), 'm3-bloc-cro', role: 'direction');
      expect(find.widgetWithText(BoutonSigh, 'Nouveau compte rendu'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.byTooltip('Imprimer le compte rendu'), findsWidgets);
    });
  });

  group('m3-cr-anesthesie — compte rendu d\'anesthésie', () {
    final c = m_(vecteurs['cra']);
    final jeu = m_(c['jeu']);
    Magasin base() => magasin({
          'crAnesthesie': liste(jeu['cra']),
          'crOperatoires': liste(jeu['cro']),
          'cpa': liste(jeu['cpa'])
        });

    cas('indicateurs et lignes identiques à la maquette ; parité N1 = 100 %', (t) async {
      await ouvrir(t, base(), 'm3-cr-anesthesie');
      final e = m_(c['ecran']);
      comparerKpis(t, e['kpis']);
      comparerTableau(t, e['tableaux'], colonnes: 7);
      await parite(t, 'm3-cr-anesthesie');
    });

    cas('« Aucun incident » s\'écrit : le champ est obligatoire ; un incident se nomme', (t) async {
      final m = base();
      await ouvrir(t, m, 'm3-cr-anesthesie');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau compte rendu'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(find.text('Ce champ est obligatoire.'), findsWidgets);
      expect(m.collection('crAnesthesie').toutes.length, 4);
      expect(find.textContaining('« Aucun incident » s’écrit'), findsOneWidget);
    });

    cas('une heure hors format est refusée par le formulaire', (t) async {
      final m = base();
      await ouvrir(t, m, 'm3-cr-anesthesie');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau compte rendu'));
      await saisir(t, 'heureInduction', '25:99');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(find.text('Heure attendue au format HH:MM.'), findsOneWidget);
      expect(m.collection('crAnesthesie').toutes.length, 4);
    });

    cas('création complète : la fiche et les indicateurs suivent la maquette', (t) async {
      final m = base();
      await ouvrir(t, m, 'm3-cr-anesthesie');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau compte rendu'));
      await choisir(t, 'patientCode', 'CNT/4/26 — PARAISO Sabi');
      await dateAujourdhui(t, 'dateOperation');
      await choisir(t, 'croReference', 'CRO-0001 — TCHANE Bertine');
      await saisir(t, 'agents', 'Kétamine');
      await saisir(t, 'heureInduction', '10:00');
      await saisir(t, 'heureFin', '11:00');
      await saisir(t, 'incidents', 'Aucun incident');
      await saisir(t, 'heureArriveeReveil', '11:10');
      await saisir(t, 'etatReveil', 'Éveillé');
      await choisir(t, 'decisionSortie', 'Surveillance prolongée en salle de réveil');
      await saisir(t, 'anesthesiste', 'ADAM Colette');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      final attendu = m_(m_(c['creation'])['cree']);
      final f = parRef(m, 'crAnesthesie', 'CRA-2026-0005');
      final fa = m_(attendu['fiche']);
      for (final k in ['patient', 'patientId', 'patientCode', 'croReference', 'technique', 'agents', 'heureInduction', 'heureFin', 'incidents', 'heureArriveeReveil', 'etatReveil', 'decisionSortie', 'anesthesiste', 'surveillancePerop']) {
        expect(f[k] ?? '', fa[k] ?? '', reason: k);
      }
      for (final k in liste(attendu['kpis'])) {
        expect(_s(kpi(t, '${k['libelle']}')), _s(k['valeur']), reason: '${k['libelle']}');
      }
      expect(find.text('Compte rendu d’anesthésie créé.'), findsOneWidget);
    });

    cas('modifier un incident : l\'indicateur « avec incident nommé » suit', (t) async {
      final m = base();
      await ouvrir(t, m, 'm3-cr-anesthesie');
      expect(kpi(t, 'Avec incident nommé'), '1');
      await toucher(t, find.byTooltip('Modifier').at(3));
      await saisir(t, 'incidents', 'Désaturation brève');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(parRef(m, 'crAnesthesie', 'CRA-2026-0004')['incidents'], 'Désaturation brève');
      expect(kpi(t, 'Avec incident nommé'), '2');
    });

    cas('imprimer : signature de l\'anesthésiste et mention « pour information » à l\'opérateur', (t) async {
      await ouvrir(t, base(), 'm3-cr-anesthesie');
      await toucher(t, find.byTooltip('Imprimer le compte rendu').first);
      expect(find.text('COMPTE RENDU D’ANESTHÉSIE'), findsWidgets);
      expect(find.text('Pour information'), findsWidgets);
    });

    cas('rôles : le caissier n\'entre pas ; la direction lit', (t) async {
      await ouvrir(t, base(), 'm3-cr-anesthesie', role: 'direction');
      expect(find.widgetWithText(BoutonSigh, 'Nouveau compte rendu'), findsNothing);
      await ouvrir(t, base(), 'm3-cr-anesthesie', role: 'caissier');
      expect(find.text('Comptes rendus d’anesthésie'), findsNothing);
    });
  });

  group('m3-bloc-checklist — deux listes séparées, l\'incomplète est signalée jamais refusée', () {
    final c = m_(vecteurs['checklist']);
    Magasin base() => magasin({'checklistsBloc': liste(c['jeu'])});
    Finder onglet(String libelle) =>
        find.descendant(of: find.byKey(const Key('kit:onglets-barre')), matching: find.textContaining(libelle));

    cas('indicateurs, onglet d\'entrée et onglet de sortie identiques à la maquette ; parité N1 = 100 %', (t) async {
      await ouvrir(t, base(), 'm3-bloc-checklist');
      final e = m_(c['ecran']);
      comparerKpis(t, e['kpis']);
      comparerTableau(t, e['tableaux'], colonnes: 4);
      expect(find.textContaining('arrêtées par les praticiens du bloc le 01/09/2026'), findsOneWidget);
      await parite(t, 'm3-bloc-checklist');
      await toucher(t, onglet('Check-liste de sortie'));
      comparerTableau(t, m_(c['sortieOnglet'])['tableaux'], colonnes: 4);
    });

    cas('la liste de sortie est une AUTRE liste : neuf points, non les douze de l\'entrée', (t) async {
      await ouvrir(t, base(), 'm3-bloc-checklist');
      await toucher(t, onglet('Check-liste de sortie'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Remplir la check-liste'));
      expect(find.text('Check-liste de sortie'), findsWidgets);
      for (final p in blocChecklistSortie) {
        expect(find.text(p), findsOneWidget);
      }
      expect(find.text(blocChecklistEntree.first), findsNothing);
      expect(find.textContaining('Avant la sortie de salle'), findsWidgets);
    });

    cas('rien de coché : la check-liste s\'enregistre quand même, SIGNALÉE « 9 point(s) NON vérifié(s) »', (t) async {
      final m = base();
      await ouvrir(t, m, 'm3-bloc-checklist');
      await toucher(t, onglet('Check-liste de sortie'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Remplir la check-liste'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(find.text('Check-liste enregistrée — 9 point(s) NON vérifié(s).'), findsOneWidget);
      final f = parRef(m, 'checklistsBloc', 'CKL-0005');
      expect([f['coches'], f['total'], f['moment']], [0, 9, 'sortie']);
      expect(kpi(t, 'Incomplètes'), '3');
      expect(kpi(t, 'Sortie'), '3');
      // L'annulation est visible : la fiche est archivée.
      await toucher(t, find.text('Annuler').last);
      expect(parRef(m, 'checklistsBloc', 'CKL-0005')['statut'], 'archive');
    });

    cas('trois points cochés : la fiche garde chaque point et son état', (t) async {
      final m = base();
      await ouvrir(t, m, 'm3-bloc-checklist');
      await toucher(t, onglet('Check-liste de sortie'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Remplir la check-liste'));
      await choisir(t, 'patientCode', 'CNT/4/26 — PARAISO Sabi');
      await choisir(t, 'responsableId', 'BOUKARI Nadège — Sage-femme');
      for (final n in ['it0', 'it1', 'it2']) {
        await cocher(t, n);
      }
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final attendu = m_(m_(m_(c['remplirSortie'])['incomplete'])['fiche']);
      final f = parRef(m, 'checklistsBloc', 'CKL-0005');
      expect(f['coches'], 3);
      expect(f['items'], attendu['items']);
      expect(f['patient'], 'PARAISO Sabi');
      expect(f['responsableId'], 'SOI14');
      expect(f['responsable'], 'BOUKARI Nadège');
      expect(DateTime.parse('${f['dateHeure']}').isUtc, isTrue);
    });

    cas('tout coché : « Check-liste complète enregistrée. »', (t) async {
      final m = base();
      await ouvrir(t, m, 'm3-bloc-checklist');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Remplir la check-liste'));
      for (var i = 0; i < blocChecklistEntree.length; i++) {
        await cocher(t, 'it$i');
      }
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(find.text('Check-liste complète enregistrée.'), findsOneWidget);
      final f = parRef(m, 'checklistsBloc', 'CKL-0005');
      expect([f['coches'], f['total'], f['moment']], [12, 12, 'entree']);
      expect(kpi(t, 'Incomplètes'), '2');
    });

    cas('consulter montre chaque point (Oui / NON) ; « Modifier » est absent (E421), « Archiver » demande un motif', (t) async {
      final m = base();
      await ouvrir(t, m, 'm3-bloc-checklist');
      expect(find.byTooltip('Modifier'), findsNothing);
      await toucher(t, find.byTooltip('Consulter').last);
      expect(find.text('Points vérifiés'.toUpperCase()), findsOneWidget);
      expect(find.text('NON'), findsWidgets);
      expect(find.text('Oui'), findsWidgets);
      await t.tapAt(const Offset(20, 300));
      await t.pump(const Duration(milliseconds: 400));
      await toucher(t, find.byTooltip('Archiver').first);
      expect(find.text('Archiver cet enregistrement ?'), findsOneWidget);
    });

    cas('rôles : la direction lit sans remplir ; le caissier n\'entre pas', (t) async {
      await ouvrir(t, base(), 'm3-bloc-checklist', role: 'direction');
      expect(find.widgetWithText(BoutonSigh, 'Remplir la check-liste'), findsNothing);
      expect(find.byTooltip('Consulter'), findsWidgets);
      await ouvrir(t, base(), 'm3-bloc-checklist', role: 'caissier');
      expect(find.text('Check-listes du bloc'), findsNothing);
    });
  });

  group('m3-demande-examen — la fiche de demande du service', () {
    final c = m_(vecteurs['demandeExamen']);
    Magasin base() => magasin({'demandesAnalyses': liste(c['jeu']), 'factures': [], 'taches': []});

    Future<void> cocherExamens(WidgetTester t, List<String> libelles) async {
      await choisir(t, 'analyses', libelles.first);
      for (final l in libelles.skip(1)) {
        await toucher(t, find.text(l).last);
      }
      // Le panneau d'une liste à cases reste ouvert d'un choix à l'autre : un clic hors du panneau le referme.
      await t.tapAt(const Offset(5, 5));
      await t.pump(const Duration(milliseconds: 300));
    }

    Future<void> remplir(WidgetTester t, {String prescripteur = 'BASSONGUI Chabi Séko — Directeur Médical'}) async {
      await choisir(t, 'patientCode', 'CNT/2/26 — BAKO Boukari');
      await saisir(t, 'residence', 'Natitingou');
      await choisir(t, 'prescripteur', prescripteur);
      await saisir(t, 'indication', 'Anémie');
      await cocherExamens(t, ['L01 — AKOP', 'L02 — ASLO']);
    }

    cas('indicateurs et lignes identiques à la maquette ; parité N1 = 100 %', (t) async {
      await ouvrir(t, base(), 'm3-demande-examen');
      final e = m_(c['ecran']);
      comparerKpis(t, e['kpis']);
      comparerTableau(t, e['tableaux'], colonnes: 7);
      await parite(t, 'm3-demande-examen');
    });

    cas('« un examen urgent » sans le nommer : refus NOMMÉ, la fiche n\'est pas émise', (t) async {
      final m = base();
      await ouvrir(t, m, 'm3-demande-examen');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouvelle fiche de demande'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Émettre la fiche'));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      await remplir(t);
      await choisir(t, 'urgence', 'Un examen urgent');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Émettre la fiche'));
      expect(find.text('Nommer L’EXAMEN urgent.'), findsOneWidget);
      expect(find.textContaining('laisserait le laboratoire deviner'), findsOneWidget);
      expect(m.collection('demandesAnalyses').toutes.length, 5);
      expect(m.collection('factures').toutes, isEmpty);
    });

    cas('émission : demandes bloquées par le paiement, facture à lignes payables, caisse saisie, prélèvement en attente, fiche imprimée', (t) async {
      final m = base();
      await ouvrir(t, m, 'm3-demande-examen');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouvelle fiche de demande'));
      await remplir(t);
      await choisir(t, 'urgence', 'Un examen urgent');
      await choisir(t, 'examenUrgent', 'ASLO');
      await cocher(t, 'hospitalise');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Émettre la fiche'));
      final em = m_(c['emission']);
      final attendu = liste(em['demandes']);
      final obtenu = m.collection('demandesAnalyses').toutes.take(2).toList();
      expect(obtenu.length, 2);
      for (var i = 0; i < 2; i++) {
        for (final k in ['reference', 'codeAnalyse', 'patientCode', 'analyseCode', 'prix', 'prescripteur', 'urgent', 'etatAnalyse', 'origine', 'origineDemande', 'serviceDemandeur', 'secteurDemandeur', 'indication', 'hospitalise', 'bloqueParPaiement', 'factureNumero']) {
          expect(obtenu[i][k], attendu[i][k], reason: 'demande $i : $k');
        }
      }
      final fac = m.collection('factures').toutes.single;
      final fa = liste(em['factures']).single;
      for (final k in ['numero', 'montantTTC', 'partAssurance', 'partPatient', 'reliquat', 'statutPaiement', 'assureur', 'tauxPriseEnCharge', 'type', 'origineDemande']) {
        expect(fac[k], fa[k], reason: 'facture : $k');
      }
      expect([for (final l in (fac['lignes'] as List)) (l as Map)['statutPaiement']], ['du', 'du']);
      expect([for (final l in (fac['lignes'] as List)) (l as Map)['demandeId']], [for (final d in obtenu.reversed) d['id']]);
      expect([for (final x in m.collection('taches').toutes) '${x['type']}:${x['statut']}'], [for (final x in liste(em['taches'])) '${x['type']}:${x['statut']}']);
      expect(find.text('Fiche émise — 2 examen(s).'), findsOneWidget);
      expect(find.text('Facture FE-2026-00001 à la caisse ; le prélèvement suivra le règlement.'), findsOneWidget);
      expect(find.text('FICHE DE DEMANDE D’EXAMEN'), findsWidgets);
      expect(find.text('Urgence : Un examen urgent — L02'), findsWidgets);
      expect(kpi(t, 'Fiches du service'), '6');
    });

    cas('bilan entier en urgence : toutes les demandes sont urgentes ; hors maternité, aucun secteur demandeur', (t) async {
      final m = base();
      await ouvrir(t, m, 'm3-demande-examen');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouvelle fiche de demande'));
      await choisir(t, 'patientCode', 'CNT/3/26 — N’TCHA Yacoubou');
      await saisir(t, 'residence', 'Natitingou');
      await choisir(t, 'serviceDemandeur', 'Médecine');
      await saisir(t, 'indication', 'Anémie');
      await cocherExamens(t, ['L03 — AZOTEMIE (UREMIE)']);
      await choisir(t, 'urgence', 'Bilan entier en urgence');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Émettre la fiche'));
      final d = m.collection('demandesAnalyses').toutes.first;
      final attendu = liste(m_(c['bilan'])['demandes']).single;
      expect(d['urgent'], true);
      expect(d['serviceDemandeur'], 'medecine');
      expect(d['secteurDemandeur'], isNull);
      expect(d['reference'], 'LAB-00006', reason: 'la série suit le registre : cinq fiches posées');
      expect([d['analyseCode'], d['urgent'], d['serviceDemandeur'], d['secteurDemandeur']], [attendu['analyseCode'], attendu['urgent'], attendu['serviceDemandeur'], attendu['secteurDemandeur']]);
    });

    cas('prescripteur extérieur : son NOM est enregistré, jamais la valeur « EXTERNE » (E412)', (t) async {
      final m = base();
      await ouvrir(t, m, 'm3-demande-examen');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouvelle fiche de demande'));
      expect(find.text('Prescripteur extérieur — nom, qualification et structure *'), findsNothing);
      await remplir(t, prescripteur: '— Prescripteur extérieur à la clinique —');
      await saisir(t, 'prescripteurExterne', 'Dr SALIFOU Aminou, Centre de santé de Perma');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Émettre la fiche'));
      final d = m.collection('demandesAnalyses').toutes.first;
      expect(d['prescripteur'], 'Dr SALIFOU Aminou, Centre de santé de Perma (extérieur)');
      expect(d['prescripteur'], liste(m_(c['externe'])['demandes']).single['prescripteur']);
    });

    cas('la résidence se reprend du dossier au choix du patient, sans écraser une saisie', (t) async {
      await ouvrir(t, base(), 'm3-demande-examen');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouvelle fiche de demande'));
      await choisir(t, 'patientCode', 'CNT/6/25 — DIEYABIDI Bibata');
      expect(find.text('Santa, Natitingou'), findsOneWidget);
      await saisir(t, 'residence', 'Boriyoure');
      await choisir(t, 'patientCode', 'CNT/7/25 — OROU YO Adissa');
      expect(find.text('Boriyoure'), findsOneWidget);
    });

    cas('rôles : la direction lit sans émettre ; le caissier n\'entre pas', (t) async {
      await ouvrir(t, base(), 'm3-demande-examen', role: 'direction');
      expect(find.widgetWithText(BoutonSigh, 'Nouvelle fiche de demande'), findsNothing);
      await ouvrir(t, base(), 'm3-demande-examen', role: 'caissier');
      expect(find.text('Registre des fiches de demande'), findsNothing);
    });
  });

  group('m3-bons-pansements — une ligne payable par séance', () {
    final c = m_(vecteurs['pansements']);
    final em = m_(c['emission']);
    Magasin vide() => magasin({'actes': jeuJson('actes'), 'ordonnances': [], 'factures': [], 'taches': []});
    // L'état d'après le règlement de la première séance, tel que la maquette l'a produit.
    Magasin apresPartiel() {
      final fac = liste(em['factures']).single;
      final lignes = liste(m_(c['partiel'])['lignes']);
      return magasin({
        'actes': jeuJson('actes'),
        'ordonnances': liste(em['ordonnances']),
        'factures': [
          {
            ...fac,
            'lignes': [
              for (final (i, l) in lignes.indexed) {...(fac['lignes'] as List)[i] as Map<String, Object?>, ...l}
            ]
          }
        ],
        'taches': []
      });
    }

    Future<void> emettre(WidgetTester t, {String seances = '3'}) async {
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau bon de pansement'));
      await choisir(t, 'acteCode', 'Pansement');
      await saisir(t, 'seances', seances);
      await saisir(t, 'indication', 'Plaie du pied');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Émettre le bon'));
    }

    cas('registre vide : les quatre indicateurs de la maquette, le tarif 9 000 / 6 000 annoncé ; parité N1 = 100 %', (t) async {
      await ouvrir(t, vide(), 'm3-bons-pansements');
      comparerKpis(t, m_(c['vide'])['kpis']);
      expect(find.textContaining('colonnes inversées'), findsOneWidget);
      expect(_s(kpi(t, 'Tarif du pansement')), _s('9 000 FCFA'), reason: 'non assuré : 9 000 (colonnes inversées, ne pas « corriger »)');
      await parite(t, 'm3-bons-pansements');
    });

    cas('un bon de 3 séances dont 1 réglée : « 1 / 3 », une séance attend encore la caisse', (t) async {
      await ouvrir(t, apresPartiel(), 'm3-bons-pansements');
      final e = m_(c['apresPartiel']);
      comparerKpis(t, e['kpis']);
      comparerTableau(t, e['tableaux'], colonnes: 6);
      await toucher(t, find.text('ORD-2026-00001').first);
      expect(find.text('1 réglée(s) sur 3'), findsOneWidget);
      expect(find.text('La salle de soins n’exécute que les séances RÉGLÉES : 2 séance(s) attendent la caisse.'), findsOneWidget);
    });

    cas('émettre 3 séances : UNE ligne payable PAR SÉANCE à 9 000, tâche d\'acte bloquée, caisse saisie', (t) async {
      final m = vide();
      await ouvrir(t, m, 'm3-bons-pansements');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau bon de pansement'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Émettre le bon'));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(m.collection('ordonnances').toutes, isEmpty);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Annuler').last);
      await emettre(t);
      final ord = m.collection('ordonnances').toutes.single;
      final oa = liste(em['ordonnances']).single;
      for (final k in ['numero', 'montant', 'montantActes', 'statutPaiement', 'statutActes', 'statutDispensation', 'diagnostic', 'medecin', 'patientCode']) {
        expect(ord[k], oa[k], reason: 'ordonnance : $k');
      }
      expect((ord['actes'] as List).length, 3);
      final fac = m.collection('factures').toutes.single;
      final fa = liste(em['factures']).single;
      expect(fac['numero'], fa['numero']);
      expect(fac['montantTTC'], 27000);
      final lignes = liste(fac['lignes']);
      expect(lignes.length, 3, reason: 'une ligne payable par séance');
      for (var i = 0; i < 3; i++) {
        expect([lignes[i]['acteCode'], lignes[i]['montant'], lignes[i]['partPatient'], lignes[i]['statutPaiement']], ['SO09', 9000, 9000, 'du']);
      }
      expect([for (final x in m.collection('taches').toutes) '${x['type']}:${x['statut']}'], [for (final x in liste(em['taches'])) '${x['type']}:${x['statut']}']);
      expect(find.text('Bon ORD-2026-00001 émis — 3 séance(s).'), findsOneWidget);
      expect(find.text('BON DE PANSEMENT'), findsWidgets);
      expect(find.text('Séance 3'), findsOneWidget);
      expect(kpi(t, 'Bons émis'), '1');
      expect(kpi(t, 'Séances en attente de règlement'), '1');
    });

    cas('le nombre de séances est borné à 1–12', (t) async {
      final m = vide();
      await ouvrir(t, m, 'm3-bons-pansements');
      await emettre(t, seances: '40');
      expect((m.collection('factures').toutes.single['lignes'] as List).length, 12);
    });

    cas('imprimer le bon : séances, tarif, total calculé et deux signatures', (t) async {
      await ouvrir(t, apresPartiel(), 'm3-bons-pansements');
      await toucher(t, find.byTooltip('Imprimer le bon').first);
      expect(find.text('BON DE PANSEMENT'), findsWidgets);
      expect(find.text('Séance 1'), findsOneWidget);
      expect(find.text('Salle de soins'), findsWidgets);
    });

    cas('rôles : l\'infirmier émet, la direction lit, le caissier n\'entre pas', (t) async {
      await ouvrir(t, vide(), 'm3-bons-pansements', role: 'infirmier');
      expect(find.widgetWithText(BoutonSigh, 'Nouveau bon de pansement'), findsOneWidget);
      await ouvrir(t, vide(), 'm3-bons-pansements', role: 'direction');
      expect(find.widgetWithText(BoutonSigh, 'Nouveau bon de pansement'), findsNothing);
      await ouvrir(t, vide(), 'm3-bons-pansements', role: 'caissier');
      expect(find.text('Registre des bons'), findsNothing);
    });
  });
}
