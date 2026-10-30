import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

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
          'dateNaissance': '1970-01-01',
          'adresse': 'Santa, Natitingou',
          'quartier': 'Kotopounga',
        }
    ];

Magasin magasin(Map<String, List<Fiche>> plus) => Magasin({
      'patients': patients(),
      'soignants': jeuJson('soignants'),
      'audit': const <Fiche>[],
      for (final e in plus.entries) e.key: [for (final f in e.value) {...f}],
    }, 'POSTE');

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
  final lignes = m_((attendu as List).single)['lignes'] as List;
  expect(tab.lignes.length, lignes.length);
  for (var i = 0; i < lignes.length; i++) {
    final l = (lignes[i] as List).cast<String>();
    final obtenu = cellules(tab, tab.lignes[i]);
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
}
