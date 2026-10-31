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
import 'package:sigh_poste/modules/m5/cat_commun.dart' show collectionAnalyses;

import 'aide_polices.dart';

/// Le paramétrage du laboratoire (M5) : m5-catalogue, m5-unites, m5-valeurs-reference, m5-reactifs. Les règles sont rejouées sur les vecteurs de la
/// maquette (packages/domaine/test/cat_regles_test.dart) ; ici, l'ÉCRAN — ce qui est écrit, refusé, annulable, et ce que chaque rôle voit.
final donnees = DonneesNavigation.depuisDossier();
final aujourdhui = DateTime(2026, 10, 30, 12);

/// Le nom que la coque porte au journal et aux états : le libellé du rôle connecté (le poste n'a pas encore de comptes nominatifs).
final qui = donnees.matrice.libelle('admin') ?? 'admin';

Map<String, Object?> vecteurs(String nom) => (jsonDecode(File(
            '../../packages/domaine/test/vecteurs/$nom.json')
        .readAsStringSync()) as Map)
    .cast<String, Object?>();

/// Le jeu de la maquette : les collections du laboratoire, le référentiel des 48 analyses, le journal.
Magasin jeu() => Magasin.depuisDossier([
      'audit',
      'examensLabo',
      'unitesLabo',
      'variablesLabo',
      'plagesReactif',
      'produits',
      'mouvements'
    ]);

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
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> saisir(WidgetTester t, String champ, String valeur) async {
  await t.enterText(
      find.descendant(
          of: find.byKey(Key('kit:champ:$champ')),
          matching: find.byType(TextField)),
      valeur);
  await t.pump();
}

/// Choisit [cible] dans la liste du champ [champ] (la recherche d'abord quand la liste est longue : le panneau ne construit que les lignes visibles).
Future<void> choisir(WidgetTester t, String champ, String cible,
    {bool dansModale = false}) async {
  // Une modale et la page peuvent porter le même nom de champ (le filtre « examen » et la variable) : on vise celui de la modale quand on le dit.
  final portee = dansModale
      ? find.descendant(
          of: find.byKey(const Key('kit:modale-panneau')),
          matching: find.byKey(Key('kit:champ:$champ')))
      : find.byKey(Key('kit:champ:$champ'));
  await toucher(t, find.descendant(of: portee, matching: find.byType(InkWell)).first);
  if (find.text(cible).evaluate().isEmpty) {
    await t.enterText(find.byType(TextField).last, cible);
    await t.pump(const Duration(milliseconds: 200));
  }
  await toucher(t, find.text(cible).last);
  await t.pump(const Duration(milliseconds: 400));
}

/// Un filtre de tableau (menu déroulant d'étiquette [filtre]) : on l'ouvre par son infobulle puis on choisit l'entrée.
Future<void> filtrer(WidgetTester t, String filtre, String entree) async {
  await toucher(t, find.byTooltip(filtre));
  await toucher(t, find.text(entree).last);
}

String kpi(WidgetTester t, String libelle) => t
    .widget<KpiSigh>(
        find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == libelle))
    .valeur;

String? indice(WidgetTester t, String libelle) => t
    .widget<KpiSigh>(
        find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == libelle))
    .indice;

/// Comparaison de valeurs affichées : les espaces fines insécables de `money()` valent « espace » (comme `\s` côté JS).
String norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

void cas(String nom, Future<void> Function(WidgetTester) corps) =>
    testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

Fiche fiche(Magasin m, String col, bool Function(Fiche) ou) =>
    m.collection(col).toutes.firstWhere(ou);

/// Le catalogue des analyses : le jeu le porte comme référentiel, l'écran en tient la collection (voir `collectionAnalyses`).
Fiche ficheAnalyse(Magasin m, bool Function(Fiche) ou) =>
    collectionAnalyses(m).toutes.firstWhere(ou);

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  // =========================================================================================================================================
  group('m5-catalogue', () {
    final doc = vecteurs('cat_catalogue');

    cas('les quatre indicateurs, les onglets et la première page sont ceux de la maquette', (t) async {
      await ouvrir(t, jeu(), 'm5-catalogue');
      final k = [
        for (final a in ((doc['catalogue'] as Map)['kpis'] as List)) norm('${(a as Map)['valeur']}')
      ];
      expect([
        norm(kpi(t, 'Analyses au catalogue')),
        norm(kpi(t, 'Catégories')),
        norm(kpi(t, 'Tarif moyen')),
        norm(kpi(t, 'Tarifs à confirmer'))
      ], k);
      expect(find.textContaining('Tous les analyses'), findsOneWidget);
      expect(find.text('Par catégorie'), findsOneWidget);
      expect(find.text('AKOP'), findsOneWidget);
      expect(find.textContaining('sur 48 enregistrements'), findsOneWidget);
      expect(find.byTooltip('Tarif à confirmer'), findsWidgets);
    });

    cas('« Imprimer le catalogue » ouvre l\'aperçu : 48 désignations, tarifs en vigueur', (t) async {
      await ouvrir(t, jeu(), 'm5-catalogue');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Imprimer le catalogue'));
      expect(find.text('48 désignations — tarifs en vigueur'), findsOneWidget);
      expect(find.text('Le Laborantin chef'), findsOneWidget);
      expect(find.text('La Directrice Administrative'), findsOneWidget);
    });

    cas('E186 : « Imprimer l\'état » ne fait rien dans la maquette — la commande est ABSENTE ici', (t) async {
      await ouvrir(t, jeu(), 'm5-catalogue');
      expect(find.byTooltip('Imprimer l’état'), findsNothing);
      expect(find.byTooltip('Modifier'), findsWidgets);
    });

    cas('onglet « Par catégorie » : une carte par catégorie, ses analyses et leur tarif', (t) async {
      await ouvrir(t, jeu(), 'm5-catalogue');
      await toucher(t, find.text('Par catégorie'));
      expect(find.text('Andrologie'), findsWidgets);
      expect(find.text('3 analyses'), findsWidgets);
      expect(find.text('SPERMOGRAMME GRAS SAVOY / ECBK'), findsOneWidget);
      expect(find.text('7 analyses'), findsWidgets);
    });

    cas('création : la fiche est écrite (tarif en nombre), l\'indicateur suit, le geste est journalisé et s\'annule', (t) async {
      final m = jeu();
      await ouvrir(t, m, 'm5-catalogue');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
      await saisir(t, 'code', 'L99');
      await saisir(t, 'designation', 'TEST ANALYSE');
      await choisir(t, 'categorie', 'Biochimie');
      await saisir(t, 'prix', '1500');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      final f = ficheAnalyse(m, (x) => x['code'] == 'L99');
      expect(f['statut'], 'actif');
      expect(f['prix'], 1500);
      expect(f['categorie'], 'Biochimie');
      expect(f['echantillon'], '');
      expect(find.text('Nouveau analyse créé.'), findsOneWidget);
      expect(kpi(t, 'Analyses au catalogue'), '49');
      expect(
          m.collection('audit').toutes.any((e) => e['module'] == 'M5' && e['action'] == 'Création'),
          isTrue,
          reason: 'RG-12 : aucune action anonyme');
      await toucher(t, find.text('Annuler').last);
      expect(kpi(t, 'Analyses au catalogue'), '48', reason: 'l\'annulation ARCHIVE, elle ne supprime pas (RG-14)');
      expect(ficheAnalyse(m, (x) => x['code'] == 'L99')['statut'], 'archive');
    });

    cas('désignation manquante : le formulaire reste ouvert, rien n\'est écrit', (t) async {
      final m = jeu();
      await ouvrir(t, m, 'm5-catalogue');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
      await saisir(t, 'code', 'L97');
      await saisir(t, 'prix', '800');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(find.text('Ce champ est obligatoire.'), findsOneWidget);
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(collectionAnalyses(m).toutes.any((x) => x['code'] == 'L97'), isFalse);
    });

    cas('modification du tarif : seul le tarif change, il reste un nombre', (t) async {
      final m = jeu();
      await ouvrir(t, m, 'm5-catalogue');
      await toucher(t, find.byTooltip('Modifier').first);
      await saisir(t, 'prix', '2300');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final f = ficheAnalyse(m, (x) => x['code'] == 'L01');
      expect(f['prix'], 2300);
      expect(f['designation'], 'AKOP');
      expect(f['tarifProvisoire'], true, reason: 'modifier ne confirme pas un tarif');
    });

    cas('archiver est annulable (RG-14) et passe l\'analyse dans l\'onglet « Archivés »', (t) async {
      final m = jeu();
      await ouvrir(t, m, 'm5-catalogue');
      await toucher(t, find.byTooltip('Archiver').first);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Archiver'));
      expect(kpi(t, 'Analyses au catalogue'), '47');
      expect(collectionAnalyses(m).archivees.length, 1);
      expect(find.textContaining('Archivés'), findsWidgets);
      await toucher(t, find.text('Annuler').last);
      expect(kpi(t, 'Analyses au catalogue'), '48');
    });

    cas('lecture seule (direction) : ni Nouveau, ni Modifier, ni Archiver — la commande est absente, et l\'écran le dit', (t) async {
      await ouvrir(t, jeu(), 'm5-catalogue', role: 'direction');
      expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
      expect(find.textContaining('Lecture seule'), findsOneWidget);
      // …mais l'état s'imprime : le catalogue est une pièce de lecture
      expect(find.widgetWithText(BoutonSigh, 'Imprimer le catalogue'), findsOneWidget);
    });

    cas('un tarif ARRÊTÉ n\'a pas l\'icône « à confirmer » ; un tarif d\'attente l\'a', (t) async {
      final m = Magasin({'audit': const []}, 'POSTE', {
        'analyses': [
          {'id': 'A1', 'n': 1, 'code': 'L01', 'designation': 'ARRÊTÉ', 'categorie': 'Biochimie', 'prix': 2000, 'echantillon': 'Sang', 'delai': '24 h', 'statut': 'Actif', 'tarifProvisoire': false},
          {'id': 'A2', 'n': 2, 'code': 'L02', 'designation': 'D\'ATTENTE', 'categorie': 'Biochimie', 'prix': 3000, 'echantillon': 'Sang', 'delai': '24 h', 'statut': 'Actif', 'tarifProvisoire': true},
        ]
      });
      await ouvrir(t, m, 'm5-catalogue');
      expect(find.byTooltip('Tarif à confirmer'), findsOneWidget);
      expect(kpi(t, 'Tarifs à confirmer'), '1');
      expect(norm(kpi(t, 'Tarif moyen')), norm('2 500 FCFA'));
    });
  });

  // =========================================================================================================================================
  group('m5-unites', () {
    final doc = vecteurs('cat_unites');

    cas('indicateurs et première ligne du jeu : triées par domaine, provenance dite', (t) async {
      await ouvrir(t, jeu(), 'm5-unites');
      final k = [for (final a in ((doc['unites'] as Map)['kpis'] as List)) '${(a as Map)['valeur']}'];
      expect([
        kpi(t, 'Unités paramétrées'),
        kpi(t, 'Reprises de la fiche'),
        kpi(t, 'À confirmer'),
        kpi(t, 'Domaines couverts')
      ], k);
      expect(find.text('10⁶/ml'), findsOneWidget);
      expect(find.text('À confirmer'), findsWidgets);
      expect(find.text('Fiche de résultats CNT'), findsWidgets);
      final y = (t.getTopLeft(find.text('10⁶/ml')).dy);
      expect(y, lessThan(t.getTopLeft(find.text('mg/l')).dy), reason: 'Andrologie avant Biochimie');
    });

    cas('création d\'une unité : écrite, sans « à confirmer » — elle porte alors la source de la fiche', (t) async {
      final m = jeu();
      await ouvrir(t, m, 'm5-unites');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
      await saisir(t, 'symbole', 'mg/dl');
      await saisir(t, 'libelle', 'milligramme par décilitre');
      await choisir(t, 'domaine', 'Biochimie');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      final u = fiche(m, 'unitesLabo', (x) => x['symbole'] == 'mg/dl');
      expect(u['statut'], 'actif');
      expect(u['domaine'], 'Biochimie');
      expect(u.containsKey('aValider'), isFalse);
      expect(find.text('Nouveau unité créé.'), findsOneWidget);
      expect(kpi(t, 'Unités paramétrées'), '24');
    });

    cas('symbole manquant : refus, rien n\'est écrit', (t) async {
      final m = jeu();
      await ouvrir(t, m, 'm5-unites');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
      await saisir(t, 'libelle', 'sans symbole');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(find.text('Ce champ est obligatoire.'), findsOneWidget);
      expect(m.collection('unitesLabo').toutes.length, 23);
    });

    cas('provenance : « à confirmer » ou la source propre de la fiche (jamais les deux)', (t) async {
      final m = Magasin({
        'audit': const [],
        'unitesLabo': [
          {'id': 'u1', 'statut': 'actif', 'symbole': 'aa', 'libelle': 'alpha', 'domaine': 'Biochimie', 'source': 'Ma source'},
          {'id': 'u2', 'statut': 'actif', 'symbole': 'bb', 'libelle': 'bravo', 'domaine': 'Biochimie', 'aValider': true},
          {'id': 'u3', 'statut': 'actif', 'symbole': 'cc', 'libelle': 'charlie', 'domaine': 'Général'},
        ]
      });
      await ouvrir(t, m, 'm5-unites');
      expect(find.text('Ma source'), findsOneWidget);
      expect(find.text('À confirmer'), findsNWidgets(2), reason: 'le KPI et le badge');
      expect(find.text('Fiche de résultats CNT'), findsOneWidget);
      expect(kpi(t, 'À confirmer'), '1');
      expect(kpi(t, 'Reprises de la fiche'), '2');
    });

    cas('archiver une unité est annulable ; la direction (lecture) n\'a aucune commande d\'écriture', (t) async {
      final m = jeu();
      await ouvrir(t, m, 'm5-unites');
      await toucher(t, find.byTooltip('Archiver').first);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Archiver'));
      expect(kpi(t, 'Unités paramétrées'), '22');
      await toucher(t, find.text('Annuler').last);
      expect(kpi(t, 'Unités paramétrées'), '23');
      await ouvrir(t, jeu(), 'm5-unites', role: 'direction');
      expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
    });
  });

  // =========================================================================================================================================
  group('m5-valeurs-reference', () {
    final doc = vecteurs('cat_valeurs');

    cas('indicateurs : documentées, validées par le biologiste et fermées sont TROIS comptes distincts', (t) async {
      await ouvrir(t, jeu(), 'm5-valeurs-reference');
      final k = [for (final a in (((doc['valeurs'] as Map)['kpis']) as List)) '${(a as Map)['valeur']}'];
      expect([
        kpi(t, 'Variables paramétrées'),
        kpi(t, 'Documentées'),
        kpi(t, 'Validées par le biologiste'),
        kpi(t, 'Variables fermées')
      ], k);
      expect(indice(t, 'Validées par le biologiste'), 'Validation écrite du 01/09/2026');
      expect(indice(t, 'Documentées'), 'Fiche de résultats du 21/08/2026');
      expect(find.textContaining('sur 163 enregistrements'), findsOneWidget);
      expect(find.textContaining('on peut les fermer'), findsOneWidget);
    });

    cas('première ligne : la notation du document (« 4 - 8 », unité « G/l »), sous-variable en retrait', (t) async {
      await ouvrir(t, jeu(), 'm5-valeurs-reference');
      expect(find.text('Globules blancs'), findsOneWidget);
      expect(find.text('4 - 8'), findsOneWidget);
      expect(find.text('G/l'), findsWidgets);
      expect(find.text('↳ Lymphocytes'), findsOneWidget);
      expect(find.text('1 - 4.5'), findsOneWidget);
    });

    cas('filtrer par section recompte ; choisir un examen restreint encore ; « Toutes les sections » rend tout', (t) async {
      await ouvrir(t, jeu(), 'm5-valeurs-reference');
      await choisir(t, 'section', 'Hématologie');
      expect(find.textContaining('sur 26 enregistrements'), findsOneWidget);
      await choisir(t, 'examen', 'NFS complète (hémogramme)');
      expect(find.textContaining('sur 13 enregistrements'), findsOneWidget);
      await choisir(t, 'section', 'Toutes les sections');
      expect(find.textContaining('sur 163 enregistrements'), findsOneWidget,
          reason: 'changer de section repart des examens de la section : « Tous les examens »');
    });

    cas('les trois provenances et la fermeture sont portées par les mêmes badges que la maquette', (t) async {
      final fiches = ((doc['etats'] as Map)['fiches'] as List).cast<Map>().map((x) => x.cast<String, Object?>()).toList();
      final m = Magasin({
        'audit': const [],
        'examensLabo': [
          {'id': 'E1', 'code': 'NFS', 'designation': 'NFS complète (hémogramme)', 'section': 'hematologie', 'statut': 'actif'}
        ],
        'unitesLabo': const [],
        'plagesReactif': const [],
        'variablesLabo': fiches,
      });
      await ouvrir(t, m, 'm5-valeurs-reference');
      expect(find.text('Documentée'), findsWidgets);
      expect(find.text('Validée (biologiste)'), findsOneWidget);
      expect(find.text('À valider'), findsWidgets);
      expect(find.text('Fermée'), findsWidgets);
      expect(find.text('Commentaire de l’examen'), findsOneWidget);
      expect(kpi(t, 'Variables paramétrées'), '9', reason: 'la variable archivée n\'est pas comptée');
      expect(kpi(t, 'Variables fermées'), '2');
    });

    cas('modifier une borne documentée : l\'avertissement paraît, et la source DIT que la borne a bougé', (t) async {
      final m = jeu();
      await ouvrir(t, m, 'm5-valeurs-reference');
      await toucher(t, find.byTooltip('Modifier les paramètres').first);
      expect(find.textContaining('Cette borne est reprise de la fiche de résultats du 21/08/2026'), findsOneWidget);
      await saisir(t, 'min', '3.8');
      await saisir(t, 'max', '8.5');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final v = fiche(m, 'variablesLabo', (x) => x['id'] == 'VAR-NFS-GB');
      expect(v['min'], 3.8);
      expect(v['max'], 8.5);
      expect(v['source'], 'Modifiée par $qui le 30/10/2026 — précédemment : 4 - 8');
      expect(v['aValider'], false, reason: 'la provenance affichée ne change pas ; la source le dit');
      expect(find.text('Paramètres enregistrés.'), findsOneWidget);
      expect(m.collection('audit').toutes.first['action'], 'Modification d’une valeur de référence');
    });

    cas('E182 : corriger seulement l\'intitulé ne fait PAS sortir la borne du document', (t) async {
      final m = jeu();
      await ouvrir(t, m, 'm5-valeurs-reference');
      await toucher(t, find.byTooltip('Modifier les paramètres').at(1)); // Lymphocytes
      await saisir(t, 'libelle', 'Lymphocytes (corrigé)');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final v = fiche(m, 'variablesLabo', (x) => x['id'] == 'VAR-NFS-LY');
      expect(v['libelle'], 'Lymphocytes (corrigé)');
      expect(v['source'], 'Fiche de résultats CNT du 21/08/2026');
      expect(v['min'], 1);
      expect(v['max'], 4.5);
    });

    cas('nouvelle variable : repart « à valider », rétractable si c\'est un réactif', (t) async {
      final m = jeu();
      await ouvrir(t, m, 'm5-valeurs-reference');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouvelle variable'));
      await choisir(t, 'examen', 'VIH', dansModale: true);
      await saisir(t, 'code', 'ZZ2');
      await saisir(t, 'libelle', 'Réactif test');
      await choisir(t, 'type', 'Réactif employé', dansModale: true);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      final v = fiche(m, 'variablesLabo', (x) => x['code'] == 'ZZ2');
      expect(v['aValider'], true);
      expect(v['actif'], true);
      expect(v['accompagnement'], true);
      expect(v['retractable'], true);
      expect(v['section'], 'serologie');
      expect(v['examenLibelle'], 'VIH');
      expect(v['source'], 'Créée dans l’application le 30/10/2026 — à valider');
      expect(m.collection('audit').toutes.first['action'], 'Création d’une variable de résultat');
    });

    cas('intitulé manquant : refus, rien n\'est écrit', (t) async {
      final m = jeu();
      await ouvrir(t, m, 'm5-valeurs-reference');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouvelle variable'));
      await saisir(t, 'code', 'ZZ3');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(find.text('Ce champ est obligatoire.'), findsWidgets);
      expect(m.collection('variablesLabo').toutes.length, 163);
    });

    cas('fermer / rouvrir une variable d\'accompagnement : confirmée, journalisée, jamais supprimée', (t) async {
      final m = jeu();
      await ouvrir(t, m, 'm5-valeurs-reference');
      await choisir(t, 'examen', 'VIH');
      expect(find.byTooltip('Fermer cette variable'), findsWidgets);
      // seule une variable d'accompagnement porte la commande : 13 lignes, mais moins de commandes de fermeture
      expect(find.byTooltip('Modifier les paramètres').evaluate().length,
          greaterThan(find.byTooltip('Fermer cette variable').evaluate().length));
      await toucher(t, find.byTooltip('Fermer cette variable').first);
      expect(find.textContaining('Cette variable disparaîtra des nouvelles saisies'), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Fermer la variable'));
      final id = (vecteurs('cat_valeurs')['valeurs'] as Map)['exemplesFermables'] as List;
      final v = fiche(m, 'variablesLabo', (x) => x['id'] == id.first);
      expect(v['actif'], false);
      expect(v['fermeeLe'], '2026-10-30');
      expect(v['fermeePar'], qui);
      expect(m.collection('variablesLabo').toutes.length, 163, reason: 'RG-14 : rien n\'est supprimé');
      expect(find.text('Variable fermée.'), findsOneWidget);
      expect(kpi(t, 'Variables fermées'), '1');
      expect(find.byTooltip('Rouvrir cette variable'), findsOneWidget);
      await toucher(t, find.byTooltip('Rouvrir cette variable'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Rouvrir'));
      expect(fiche(m, 'variablesLabo', (x) => x['id'] == id.first)['actif'], true);
      expect(kpi(t, 'Variables fermées'), '0');
    });

    cas('fermer puis « Annuler » dans la confirmation : rien ne change', (t) async {
      final m = jeu();
      await ouvrir(t, m, 'm5-valeurs-reference');
      await choisir(t, 'examen', 'VIH');
      final avant = m.collection('audit').toutes.length;
      await toucher(t, find.byTooltip('Fermer cette variable').first);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Annuler'));
      expect(kpi(t, 'Variables fermées'), '0');
      expect(fiche(m, 'variablesLabo', (x) => x['id'] == 'VAR-VIH-T1R')['actif'], true);
      expect(m.collection('audit').toutes.length, avant, reason: 'rien n\'est journalisé : rien ne s\'est passé');
    });

    group('plages par lot de réactif', () {
      cas('aucune plage au départ : l\'écran dit que les bornes des variables font foi', (t) async {
        await ouvrir(t, jeu(), 'm5-valeurs-reference');
        expect(find.textContaining('Aucune plage par lot enregistrée'), findsOneWidget);
        expect(find.text('Plages de référence par lot de réactif'), findsOneWidget);
      });

      cas('une plage sans aucune borne est REFUSÉE en le disant', (t) async {
        final m = jeu();
        await ouvrir(t, m, 'm5-valeurs-reference');
        await toucher(t, find.widgetWithText(BoutonSigh, 'Nouvelle plage de lot'));
        await choisir(t, 'variableId', 'NFS complète (hémogramme) — Globules blancs', dansModale: true);
        await saisir(t, 'lot', 'LOT-VIDE');
        await saisir(t, 'source', 'Notice');
        await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer la plage'));
        expect(find.text('Une plage sans aucune borne ne compare rien.'), findsOneWidget);
        expect(find.text('Renseigner au moins une borne, ou ne pas enregistrer de plage.'), findsOneWidget);
        expect(m.collection('plagesReactif').toutes, isEmpty);
      });

      cas('une plage valide : écrite avec sa variable, datée, journalisée ; le tableau affiche ses bornes', (t) async {
        final m = jeu();
        await ouvrir(t, m, 'm5-valeurs-reference');
        await toucher(t, find.widgetWithText(BoutonSigh, 'Nouvelle plage de lot'));
        await choisir(t, 'variableId', 'NFS complète (hémogramme) — Globules blancs', dansModale: true);
        await saisir(t, 'lot', 'LOT-2026-A');
        await saisir(t, 'min', '3.5');
        await saisir(t, 'max', '9.5');
        await saisir(t, 'source', 'Notice du réactif Sysmex');
        await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer la plage'));
        final p = m.collection('plagesReactif').toutes.single;
        expect(p['variableId'], 'VAR-NFS-GB');
        expect(p['variableLibelle'], 'Globules blancs');
        expect(p['examen'], 'NFS');
        expect(p['min'], 3.5);
        expect(p['max'], 9.5);
        expect(p['dateDebut'], '2026-10-30', reason: 'la date d\'entrée en service propose le jour');
        expect(p['statut'], 'actif');
        expect(find.text('Plage enregistrée.'), findsOneWidget);
        expect(find.text('3.5 – 9.5'), findsOneWidget);
        expect(find.text('LOT-2026-A'), findsOneWidget);
        expect(m.collection('audit').toutes.first['action'], 'Plage par lot créée');
      });

      cas('archiver une plage : confirmé, la plage reste au registre (RG-14)', (t) async {
        final m = jeu();
        m.collection('plagesReactif').inserer({
          'statut': 'actif', 'variableId': 'VAR-NFS-GB', 'variableLibelle': 'Globules blancs', 'examenLibelle': 'NFS complète (hémogramme)', 'lot': 'LOT-X',
          'dateDebut': '2026-09-01', 'min': 3.5, 'max': 9, 'source': 'Notice'
        }, prefixe: 'PLG');
        await ouvrir(t, m, 'm5-valeurs-reference');
        expect(find.text('LOT-X'), findsOneWidget);
        await toucher(t, find.byTooltip('Archiver la plage'));
        expect(find.text('Archiver la plage du lot LOT-X ?'), findsOneWidget);
        await toucher(t, find.widgetWithText(BoutonSigh, 'Archiver'));
        expect(find.text('Plage archivée.'), findsOneWidget);
        expect(m.collection('plagesReactif').toutes.single['statut'], 'archive');
        expect(find.text('LOT-X'), findsNothing);
      });
    });

    cas('impression filtrée : l\'état dit le filtre en force (Section : Sérologie) et ses 26 variables', (t) async {
      await ouvrir(t, jeu(), 'm5-valeurs-reference');
      await choisir(t, 'section', 'Sérologie');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Imprimer le référentiel'));
      expect(find.text('Référentiel des valeurs de référence'), findsOneWidget);
      expect(find.textContaining('Laboratoire d’analyses biomédicales — situation au 30/10/2026'), findsOneWidget);
      expect(find.text('Section : Sérologie'), findsOneWidget);
      expect(find.text('Le Biologiste médical'), findsOneWidget);
    });

    cas('lecture seule (direction) : les bornes se lisent, rien ne se modifie ni ne se ferme', (t) async {
      await ouvrir(t, jeu(), 'm5-valeurs-reference', role: 'direction');
      expect(find.widgetWithText(BoutonSigh, 'Nouvelle variable'), findsNothing);
      expect(find.widgetWithText(BoutonSigh, 'Nouvelle plage de lot'), findsNothing);
      expect(find.byTooltip('Modifier les paramètres'), findsNothing);
      expect(find.byTooltip('Fermer cette variable'), findsNothing);
      expect(find.widgetWithText(BoutonSigh, 'Imprimer le référentiel'), findsOneWidget);
    });
  });

  // =========================================================================================================================================
  group('m5-reactifs', () {
    final doc = vecteurs('cat_reactifs');
    final r = doc['reactifs'] as Map;

    Magasin jeuPose() => Magasin({
          'audit': const [],
          'examensLabo': [
            {'id': 'E1', 'code': 'NFS', 'designation': 'NFS complète (hémogramme)', 'section': 'hematologie', 'statut': 'actif'},
            {'id': 'E2', 'code': 'VIH', 'designation': 'VIH', 'section': 'serologie', 'statut': 'actif'},
          ],
          'produits': [
            for (final p in r['produits'] as List) (p as Map).cast<String, Object?>()
          ],
          'mouvements': [
            for (final p in r['mouvements'] as List) (p as Map).cast<String, Object?>()
          ],
        });

    cas('indicateurs : « sous le seuil » compte les ruptures ; les références sans seuil sont signalées À PART', (t) async {
      await ouvrir(t, jeuPose(), 'm5-reactifs');
      final k = [for (final a in r['kpis'] as List) norm('${(a as Map)['valeur']}')];
      expect([
        norm(kpi(t, 'Références suivies')),
        norm(kpi(t, 'Valeur du stock')),
        norm(kpi(t, 'Sous le seuil d’alerte')),
        norm(kpi(t, 'En rupture'))
      ], k);
      expect(indice(t, 'Valeur du stock'), 'Valorisation au CUMP');
      expect(find.textContaining('2 référence(s) sans seuil d’alerte.'), findsOneWidget);
    });

    cas('lignes : seuil absent = « — » (pas zéro), états rupture / critique / normal', (t) async {
      await ouvrir(t, jeuPose(), 'm5-reactifs');
      expect(find.text('Rupture'), findsNWidgets(2));
      expect(find.text('Critique'), findsNWidgets(3));
      expect(find.text('Normal'), findsNWidgets(3));
      expect(find.text('—'), findsNWidgets(2), reason: 'A5 et A6 : seuil non fixé');
      expect(find.text('D A7'), findsNothing, reason: 'un médicament n\'est pas un réactif');
      expect(find.text('D A9'), findsNothing, reason: 'une référence archivée n\'est pas suivie');
    });

    cas('filtre « Sans seuil défini » : les deux références dont le seuil n\'est pas fixé', (t) async {
      await ouvrir(t, jeuPose(), 'm5-reactifs');
      await filtrer(t, 'Niveau de stock', 'Sans seuil défini');
      expect(find.textContaining('sur 2 enregistrements'), findsOneWidget);
      expect(find.text('D A5'), findsWidgets);
      expect(find.text('D A6'), findsWidgets);
    });

    cas('filtre « Sous le seuil » : hors rupture', (t) async {
      await ouvrir(t, jeuPose(), 'm5-reactifs');
      await filtrer(t, 'Niveau de stock', 'Sous le seuil');
      expect(find.textContaining('sur 3 enregistrements'), findsOneWidget);
    });

    cas('la périodicité COMMANDE le classement des plus consommés (E183 : le sélecteur n\'écoutait rien)', (t) async {
      await ouvrir(t, jeuPose(), 'm5-reactifs');
      expect(find.text('Les plus consommés — mois'), findsOneWidget);
      expect(find.text('10 unité(s)'), findsOneWidget);
      expect(find.text('9 unité(s)'), findsOneWidget, reason: 'A4 (10/10) est dans les trente jours');
      await choisir(t, 'periode', 'Semaine');
      expect(find.text('Les plus consommés — semaine'), findsOneWidget);
      expect(find.text('9 unité(s)'), findsNothing, reason: 'A4 date du 10/10 : hors de la semaine');
      await choisir(t, 'periode', 'Année');
      expect(find.text('Les plus consommés — année'), findsOneWidget);
      expect(find.text('20 unité(s)'), findsOneWidget);
      expect(find.text('8 unité(s)'), findsOneWidget);
    });

    cas('le classement de valeur : barre rouge sous le seuil, bleue sinon', (t) async {
      await ouvrir(t, jeuPose(), 'm5-reactifs');
      expect(find.byKey(const Key('cat:barre:danger')), findsWidgets);
      expect(find.byKey(const Key('cat:barre:navy')), findsWidgets);
      expect(find.text('Valeur du stock par référence'), findsOneWidget);
    });

    cas('bon de demande : les références sous leur seuil FIXÉ, quantité à deux fois le seuil, une unité au moins', (t) async {
      await ouvrir(t, jeuPose(), 'm5-reactifs');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Bon de demande de réactifs'));
      expect(find.text('Bon d’expression de besoins — Laboratoire'), findsOneWidget);
      expect(find.text('Réactifs et consommables sous le seuil d’alerte'), findsOneWidget);
      expect(find.text('Période de consommation : Mois'), findsOneWidget);
      expect(find.text('Le Gestionnaire de Stock'), findsOneWidget);
    });

    cas('bon de demande sans rien sous le seuil : le message dit les références SANS seuil (jamais un faux « tout va bien »)', (t) async {
      final m = Magasin({
        'audit': const [],
        'produits': [
          {'id': 'B1', 'code': 'B1', 'designation': 'D B1', 'categorie': 'reactif', 'unite': 'U', 'stock': 50, 'seuilAlerte': 10, 'cump': 10, 'statut': 'actif'},
          {'id': 'B2', 'code': 'B2', 'designation': 'D B2', 'categorie': 'conso_labo', 'unite': 'U', 'stock': 8, 'seuilAlerte': null, 'cump': 10, 'statut': 'actif'},
        ],
        'mouvements': const [],
      });
      await ouvrir(t, m, 'm5-reactifs');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Bon de demande de réactifs'));
      expect(find.text('Aucune référence sous son seuil d’alerte.'), findsOneWidget);
      expect(find.textContaining('1 référence(s) n’ont pas de seuil défini'), findsOneWidget);
      expect(find.text('Bon d’expression de besoins — Laboratoire'), findsNothing);
    });

    cas('création : le code suit le registre (E180), le seuil est tracé, le seuil critique reste VIDE (E184)', (t) async {
      final m = jeuPose();
      m.collection('produits').inserer({'id': 'Q1', 'code': 'LAB-0007', 'designation': 'ANCIEN', 'categorie': 'reactif', 'unite': 'U', 'stock': 1, 'seuilAlerte': 1, 'cump': 1, 'statut': 'archive'}, prefixe: 'PRD');
      await ouvrir(t, m, 'm5-reactifs');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau réactif'));
      await saisir(t, 'designation', 'KIT TEST');
      await saisir(t, 'unite', 'Kit');
      await saisir(t, 'stock', '12');
      await saisir(t, 'seuilAlerte', '5');
      await saisir(t, 'cump', '1500');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      final f = fiche(m, 'produits', (x) => x['designation'] == 'KIT TEST');
      expect(f['code'], 'LAB-0008', reason: 'le plus grand rang LAB- du registre (archivés compris) + 1');
      expect(f['stock'], 12);
      expect(f['seuilAlerte'], 5);
      expect(f['cump'], 1500);
      expect(f['seuilCritique'], isNull);
      expect(f['seuilDefiniPar'], qui);
      expect(f['seuilDefiniLe'], '2026-10-30');
      expect(f['statut'], 'actif');
      expect(find.text('Référence créé.'), findsOneWidget);
      expect(kpi(t, 'Références suivies'), '9');
      await toucher(t, find.text('Annuler').last);
      expect(kpi(t, 'Références suivies'), '8', reason: 'l\'annulation ARCHIVE');
    });

    cas('RG-03 : un stock négatif est refusé en le disant, rien n\'est écrit (E185)', (t) async {
      final m = jeuPose();
      await ouvrir(t, m, 'm5-reactifs');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau réactif'));
      await saisir(t, 'designation', 'NEG');
      await saisir(t, 'unite', 'U');
      await saisir(t, 'stock', '-1');
      await saisir(t, 'seuilAlerte', '3');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(find.text('Le stock ne peut pas être négatif.'), findsOneWidget);
      expect(find.text('RG-03 — corriger la quantité saisie.'), findsOneWidget);
      expect(m.collection('produits').toutes.any((x) => x['designation'] == 'NEG'), isFalse);
    });

    cas('le seuil d\'alerte est OBLIGATOIRE : vide, le formulaire est refusé (un seuil vide n\'est pas zéro)', (t) async {
      final m = jeuPose();
      await ouvrir(t, m, 'm5-reactifs');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau réactif'));
      await saisir(t, 'designation', 'SANS SEUIL');
      await saisir(t, 'unite', 'U');
      await saisir(t, 'seuilAlerte', '');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(find.text('Ce champ est obligatoire.'), findsOneWidget);
      expect(m.collection('produits').toutes.any((x) => x['designation'] == 'SANS SEUIL'), isFalse);
    });

    cas('modifier le stock et le seuil : écrit, annulable, la fiche garde son code', (t) async {
      final m = jeuPose();
      await ouvrir(t, m, 'm5-reactifs');
      await toucher(t, find.byTooltip('Modifier').at(1)); // A2
      await saisir(t, 'stock', '25');
      await saisir(t, 'seuilAlerte', '8');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final f = fiche(m, 'produits', (x) => x['code'] == 'A2');
      expect(f['stock'], 25);
      expect(f['seuilAlerte'], 8);
      expect(f['designation'], 'D A2');
      expect(find.text('Modifications enregistrées.'), findsOneWidget);
      expect(kpi(t, 'Sous le seuil d’alerte'), '3', reason: 'A2 (25 > 8) sort des références sous le seuil');
      await toucher(t, find.text('Annuler').last);
      expect(fiche(m, 'produits', (x) => x['code'] == 'A2')['stock'], 5);
    });

    cas('lecture seule (direction) : ni Nouveau réactif ni Modifier — mais le bon de demande reste offert', (t) async {
      await ouvrir(t, jeuPose(), 'm5-reactifs', role: 'direction');
      expect(find.widgetWithText(BoutonSigh, 'Nouveau réactif'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.widgetWithText(BoutonSigh, 'Bon de demande de réactifs'), findsOneWidget);
    });

    cas('l\'assistant comptable écrit sur les réactifs (accordé nommément par sa fiche RBAC)', (t) async {
      expect(donnees.matrice.peutVoir('assistant_comptable', 'm5-reactifs'), isTrue);
      await ouvrir(t, jeuPose(), 'm5-reactifs', role: 'assistant_comptable');
      expect(find.widgetWithText(BoutonSigh, 'Nouveau réactif'), findsOneWidget);
      expect(find.byTooltip('Modifier'), findsWidgets);
    });

    cas('le caissier n\'a aucun des quatre écrans : la coque ne les ouvre pas', (t) async {
      for (final id in ['m5-catalogue', 'm5-unites', 'm5-valeurs-reference', 'm5-reactifs']) {
        expect(donnees.matrice.peutVoir('caissier', id), isFalse, reason: id);
      }
    });
  });
}
