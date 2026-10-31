import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/jetons_shell.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';
import 'parite/extracteur.dart';

/// M13 — administration & ambulance : les huit écrans rejouent les vecteurs de la maquette (`administration.json`, tirés des écrans RÉELS dans Chrome à
/// l'horloge 30/10/2026 10 h) : indicateurs, lignes, ordre, saisies (création, refus nommé, modification), archivage, droits ; la parité N1 de chaque écran
/// est mesurée contre sa fiche extraite sur le jeu complet.
typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List)) obj(x)];

final donnees = DonneesNavigation.depuisDossier();
final v = obj(jsonDecode(File('../../packages/domaine/test/vecteurs/administration.json').readAsStringSync()));
final auj = DateTime(2026, 10, 30, 10);
String _s(Object? x) => '$x'.replaceAll(RegExp(r'[\s  ]'), '');

List<M> jeu(String nom) => liste(jsonDecode(File('assets/donnees/jeu/$nom.json').readAsStringSync()));

Magasin poste(Map<String, List<M>> collections) => Magasin({
      'audit': const [],
      'personnel': jeu('personnel'),
      'patients': jeu('patients'),
      for (final e in collections.entries) e.key: [for (final x in e.value) {...x}],
    }, 'POSTE');

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, {String role = 'admin', DateTime? horloge}) async {
  t.view.physicalSize = const Size(1600, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: ecran,
      magasin: m,
      horloge: () => horloge ?? auj));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void kpisIdentiques(WidgetTester t, Object? attendus) {
  for (final k in liste(attendus)) {
    final w = t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == k['libelle']));
    expect(_s(w.valeur), _s(k['valeur']), reason: '${k['libelle']}');
    expect(w.indice, k['indice'], reason: 'indice ${k['libelle']}');
  }
}

/// L'ordre dans lequel les références apparaissent à l'écran (de haut en bas) : ce que l'agent lit.
List<String> ordreAffiche(WidgetTester t, Iterable<String> refs) {
  final y = {for (final r in refs) r: find.text(r).evaluate().isEmpty ? double.infinity : t.getTopLeft(find.text(r).first).dy};
  return (y.keys.where((r) => y[r]!.isFinite).toList()..sort((a, b) => y[a]!.compareTo(y[b]!)));
}

/// Pose les valeurs dans le formulaire de la modale ouverte (le contrôleur réel), comme l'agent les saisirait.
void poser(WidgetTester t, Map<String, Object?> saisie) {
  final ctl = t.widget<FormulaireSigh>(find.byType(FormulaireSigh).last).controleur;
  for (final e in saisie.entries) {
    final x = e.value;
    if (e.key == 'dateHeure') {
      final p = '$x'.split('T');
      ctl.poser('${e.key}Date', p[0]);
      ctl.poser('${e.key}Heure', p[1].substring(0, 5));
    } else if (x is bool) {
      ctl.poser(e.key, x);
    } else {
      ctl.poser(e.key, '$x');
    }
  }
}

Future<void> chercher(WidgetTester t, String ref) async {
  await t.enterText(find.byWidgetPredicate((w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('Rechercher')).first, ref);
  await t.pump(const Duration(milliseconds: 500));
}

Future<void> cliquer(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> archiverLigne(WidgetTester t, String motif) async {
  await cliquer(t, find.byTooltip('Archiver').first);
  await t.enterText(find.byType(TextField).last, motif);
  await t.pump();
  await t.tap(find.widgetWithText(BoutonSigh, 'Archiver').last);
  await t.pump(const Duration(milliseconds: 400));
}

bool egal(Object? a, Object? b) {
  if (a == null && b == null) return true;
  if (a is num && b is num) return a == b;
  if (a is List && b is List) return a.length == b.length && [for (var i = 0; i < a.length; i++) egal(a[i], b[i])].every((x) => x);
  return '$a' == '$b';
}

void fichesEgales(M obtenue, M attendue, {Set<String> ignores = const {}}) {
  const tous = {'id', '_creePar', '_creeLe', '_modifiePar', '_modifieLe', 'statut', 'patientId', 'statutAvantArchivage'};
  for (final k in {...obtenue.keys, ...attendue.keys}) {
    if (tous.contains(k) || ignores.contains(k)) continue;
    if ((obtenue[k] == null || obtenue[k] == '') && (attendue[k] == null || attendue[k] == '')) continue;
    expect(egal(obtenue[k], attendue[k]), isTrue, reason: '$k : écrit ${obtenue[k]}, maquette ${attendue[k]}');
  }
}

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  // -------------------------------------------------------------------------------------------------------------------------------------------
  group('m13-courriers', () {
    final c = obj(v['courriers']);

    testWidgets('KPI, onglets et ordre des lignes identiques à la maquette sur son registre (un archivé hors de la liste)', (t) async {
      final m = poste({'courriers': liste(c['jeu'])});
      await ouvrir(t, m, 'm13-courriers');
      kpisIdentiques(t, obj(c['ecran'])['kpis']);
      final lignes = (obj((obj(c['ecran'])['tableaux'] as List).first)['lignes'] as List).cast<List>();
      expect(ordreAffiche(t, [for (final l in lignes) '${l[0]}']), [for (final l in lignes) '${l[0]}']);
      expect(find.textContaining('Tous les courriers'), findsWidgets);
      expect(find.text('DEP-2026-0009'), findsNothing, reason: 'l’archivé n’est pas dans la liste principale');
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('création : référence de la série annuelle ARR-AAAA-NNNN (E538 levé), valeurs par défaut, refus nommé si le formulaire est vide', (t) async {
      final m = poste({'courriers': liste(c['jeu'])});
      await ouvrir(t, m, 'm13-courriers');
      final col = m.collection('courriers');
      final n0 = col.toutes.length;
      await cliquer(t, find.widgetWithText(BoutonSigh, 'Nouveau').first);
      final ctl = t.widget<FormulaireSigh>(find.byType(FormulaireSigh).last).controleur;
      final defauts = obj(obj(c['creation'])['defauts']);
      for (final k in ['sens', 'date', 'nature', 'affecteA', 'traitement']) {
        expect('${ctl[k]}', '${defauts[k]}', reason: 'défaut $k');
      }
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Le formulaire comporte des erreurs.'), findsWidgets);
      expect(col.toutes.length, n0, reason: 'refus : rien n’est écrit');
      poser(t, {'correspondant': 'DGI Natitingou', 'objet': 'Déclaration TVM', 'affecteA': 'Comptabilité'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 400));
      expect(col.toutes.length, n0 + 1);
      fichesEgales(col.toutes.first, obj(obj(c['creation'])['arrivee'])['fiche'] as M);
      expect(col.toutes.first['reference'], (obj(obj(c['creation'])['arrivee'])['fiche'] as M)['reference']);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('modification : la RÉFÉRENCE est gardée (E530) — ARR-2026-0004 ne devient pas ARR-2026-0012', (t) async {
      final m = poste({'courriers': liste(c['jeu'])});
      await ouvrir(t, m, 'm13-courriers');
      await chercher(t, 'ARR-2026-0004');
      await cliquer(t, find.byTooltip('Modifier').first);
      poser(t, {'traitement': 'traite', 'numerise': true});
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await t.pump(const Duration(milliseconds: 400));
      final f = m.collection('courriers').toutes.firstWhere((x) => x['id'] == 'COU4');
      fichesEgales(f, obj(obj(obj(c['modification'])['enregistre'])['fiche']));
      expect(f['reference'], 'ARR-2026-0004');
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('archivage : le motif est exigé, la fiche passe aux « Archivés » (RG-14), jamais supprimée', (t) async {
      final m = poste({'courriers': liste(c['jeu'])});
      await ouvrir(t, m, 'm13-courriers');
      await chercher(t, 'DEP-2026-0005');
      await archiverLigne(t, 'Doublon');
      final f = m.collection('courriers').toutes.firstWhere((x) => x['id'] == 'COU5');
      expect(f['statut'], 'archive');
      expect(m.collection('courriers').toutes.length, liste(c['jeu']).length);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('droits : le profil qui peut écrire sans annuler n’a PAS la commande « Archiver » (absente, jamais grisée)', (t) async {
      final m = poste({'courriers': liste(c['jeu'])});
      await ouvrir(t, m, 'm13-courriers', role: 'reception');
      expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsWidgets);
      expect(find.byTooltip('Modifier'), findsWidgets);
      expect(find.byTooltip('Archiver'), findsNothing);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('« Imprimer le registre » ouvre l’état avec les compteurs de la maquette', (t) async {
      final m = poste({'courriers': liste(c['jeu'])});
      await ouvrir(t, m, 'm13-courriers');
      // l'en-tête de page porte la commande ; la pièce reprend les compteurs du registre
      await cliquer(t, find.widgetWithText(BoutonSigh, 'Imprimer le registre'));
      for (final x in (obj(c['etatRegistre'])['cartouche'] as List).cast<List>().take(3)) {
        expect(find.textContaining('${x[0]}'), findsWidgets, reason: '${x[0]}');
      }
      expect(find.text('Registre du courrier'), findsWidgets);
      await t.pump(const Duration(seconds: 10));
    });
  });

  // -------------------------------------------------------------------------------------------------------------------------------------------
  group('m13-reunions', () {
    final r = obj(v['reunions']);

    testWidgets('KPI, ordre, création RU-2026-009 (série du registre, E531) et modification qui GARDE la référence', (t) async {
      final m = poste({'reunions': liste(r['jeu'])});
      await ouvrir(t, m, 'm13-reunions');
      kpisIdentiques(t, obj(r['ecran'])['kpis']);
      final lignes = (obj((obj(r['ecran'])['tableaux'] as List).first)['lignes'] as List).cast<List>();
      expect(ordreAffiche(t, [for (final l in lignes) '${l[0]}']), [for (final l in lignes) '${l[0]}']);
      expect(find.text('Tenue'), findsWidgets);
      expect(find.text('À venir'), findsWidgets);
      final col = m.collection('reunions');
      final n0 = col.toutes.length;
      await cliquer(t, find.widgetWithText(BoutonSigh, 'Nouveau').first);
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Le formulaire comporte des erreurs.'), findsWidgets, reason: 'l’ordre du jour est obligatoire');
      expect(col.toutes.length, n0);
      poser(t, {'ordreDuJour': 'Budget 2027'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 400));
      fichesEgales(col.toutes.first, obj(obj(r['creation'])['creee'])['fiche'] as M);
      expect(col.toutes.first['reference'], 'RU-2026-009');
      await chercher(t, 'RU-2026-003');
      await cliquer(t, find.byTooltip('Modifier').first);
      poser(t, {'compteRendu': true, 'resolutions': 'RAS'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await t.pump(const Duration(milliseconds: 400));
      fichesEgales(col.toutes.firstWhere((x) => x['id'] == 'REU3'), obj(obj(r['modification'])['fiche']));
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('l’heure est contrôlée (hh:mm) : un refus se nomme', (t) async {
      final m = poste({'reunions': liste(r['jeu'])});
      await ouvrir(t, m, 'm13-reunions');
      await cliquer(t, find.widgetWithText(BoutonSigh, 'Nouveau').first);
      poser(t, {'ordreDuJour': 'x', 'heure': '25:99'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Heure attendue au format HH:MM.'), findsWidgets);
      await t.pump(const Duration(seconds: 10));
    });
  });

  // -------------------------------------------------------------------------------------------------------------------------------------------
  group('m13-evenements', () {
    final e = obj(v['evenements']);

    testWidgets('KPI, prochains événements (délais, six au plus), notifications système', (t) async {
      final m = poste({'evenementsEtablissement': liste(e['jeu'])});
      await ouvrir(t, m, 'm13-evenements');
      kpisIdentiques(t, obj(e['ecran'])['kpis']);
      for (final b in (e['prochainsBrut'] as List).cast<String>()) {
        final delai = RegExp(r'(Dans \d+ j|Aujourd’hui)').firstMatch(b)!.group(0)!;
        expect(find.text(delai), findsWidgets, reason: delai);
      }
      expect(find.text('Dans 1 j'), findsOneWidget);
      expect(find.text('Formation aux gestes d’urgence'), findsWidgets);
      for (final l in (obj(e['notifications'])['lignes'] as List).cast<List>()) {
        expect(find.text('${l[0]}'), findsWidgets);
      }
      // « Dans 1 j » et « Dans 5 j » en rouge (≤ 7 jours), « Dans 20 j » en gris
      Color? couleur(String s) => t.widget<Text>(find.text(s).first).style?.color;
      expect(couleur('Dans 1 j'), JetonsShell.danger600);
      expect(couleur('Dans 8 j'), JetonsShell.slate400);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('création : EVT-0011, canal In-app, annonce sonore de la maquette en message', (t) async {
      final m = poste({'evenementsEtablissement': liste(e['jeu'])});
      await ouvrir(t, m, 'm13-evenements');
      final col = m.collection('evenementsEtablissement');
      final n0 = col.toutes.length;
      await cliquer(t, find.widgetWithText(BoutonSigh, 'Nouveau').first);
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Le formulaire comporte des erreurs.'), findsWidgets);
      expect(col.toutes.length, n0);
      poser(t, {'libelle': 'Dépistage du cancer du sein', 'lieu': 'Salle de réunion'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(seconds: 1));
      fichesEgales(col.toutes.first, obj(obj(e['creation'])['avecNotif'])['fiche'] as M);
      expect(col.toutes.first['reference'], 'EVT-0011');
      expect(find.text('Événement inscrit au calendrier de la clinique.'), findsWidgets);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('modification : cocher « notifier » pose un canal, la case décochée les retire (E532)', (t) async {
      final m = poste({'evenementsEtablissement': liste(e['jeu'])});
      await ouvrir(t, m, 'm13-evenements');
      final col = m.collection('evenementsEtablissement');
      await chercher(t, 'EV-2026-004');
      await cliquer(t, find.byTooltip('Modifier').first);
      poser(t, {'notifier': true, 'lieu': 'Extérieur'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await t.pump(const Duration(milliseconds: 400));
      fichesEgales(col.toutes.firstWhere((x) => x['id'] == 'EVT004'), obj(obj(e['modification'])['enregistre'])['fiche'] as M);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('à 15 h, « demain » se lit « Dans 1 j » et l’événement du jour « Aujourd’hui » reste annoncé, en rouge (E540)', (t) async {
      final m = poste({'evenementsEtablissement': liste(e['jeu'])});
      await ouvrir(t, m, 'm13-evenements', horloge: DateTime(2026, 10, 30, 15));
      expect(find.text('Aujourd’hui'), findsOneWidget);
      expect(find.text('Dans 1 j'), findsOneWidget);
      expect(t.widget<Text>(find.text('Aujourd’hui')).style?.color, JetonsShell.danger600);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('collection vide : le calendrier est amorcé comme la maquette (dix événements, graine 2713)', (t) async {
      final m = poste({'evenementsEtablissement': []});
      await ouvrir(t, m, 'm13-evenements');
      final a = m.collection('evenementsEtablissement').toutes;
      expect(a.length, 10);
      expect([for (final x in a) x['reference']], [for (var i = 1; i <= 10; i++) 'EV-2026-${i.toString().padLeft(3, '0')}']);
      await t.pump(const Duration(seconds: 10));
    });
  });

  // -------------------------------------------------------------------------------------------------------------------------------------------
  group('m13-plan-annuel', () {
    final p = obj(v['planAnnuel']);

    testWidgets('KPI et diagramme : une barre par trimestre couvert, du ton de l’état d’avancement', (t) async {
      final m = poste({'planAnnuel': liste(p['jeu'])});
      await ouvrir(t, m, 'm13-plan-annuel');
      kpisIdentiques(t, obj(p['ecran'])['kpis']);
      final couleurs = {'bg-success-400': JetonsShell.success400, 'bg-info-400': JetonsShell.info400, 'bg-warning-400': JetonsShell.warning400, 'bg-slate-100': JetonsShell.slate100};
      final tri = trierPar(liste(p['jeu']), (r) => r['trimestreDebut']);
      final gantt = (p['gantt'] as List).cast<List>();
      expect(tri.length, gantt.length);
      for (var i = 0; i < tri.length; i++) {
        for (var q = 1; q <= 4; q++) {
          final w = t.widget<Container>(find.byKey(Key('adm:barre:${tri[i]['reference']}:T$q')));
          expect((w.decoration as BoxDecoration).color, couleurs[gantt[i][1 + q]], reason: '${tri[i]['reference']} T$q');
        }
      }
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('modifier une action garde son ÉTAT (E533) ; changer l’état recalcule les indicateurs sans recharger', (t) async {
      final m = poste({'planAnnuel': liste(p['jeu'])});
      await ouvrir(t, m, 'm13-plan-annuel');
      await chercher(t, 'PA-2026-006');
      await cliquer(t, find.byTooltip('Modifier').first);
      poser(t, {'action': 'Campagne de dépistage communautaire', 'echeance': '2026-12-15'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await t.pump(const Duration(milliseconds: 400));
      final col = m.collection('planAnnuel');
      var f = col.toutes.firstWhere((x) => x['id'] == 'PAT006');
      fichesEgales(f, obj(obj(obj(p['modification'])['enregistre'])['fiche']), ignores: {'tauxAvancement'});
      expect(f['avancement'], 'En cours');
      await cliquer(t, find.byTooltip('Modifier').first);
      poser(t, {'avancement': 'Réalisée', 'tauxAvancement': '60'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await t.pump(const Duration(milliseconds: 400));
      f = col.toutes.firstWhere((x) => x['id'] == 'PAT006');
      fichesEgales(f, obj(obj(p['avancementNumerique'])['fiche']));
      // la maquette laisse ses indicateurs figés ; le poste les recalcule (3 réalisées, 1 en cours)
      expect(_s(t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == 'Réalisées')).valeur), '3');
      expect(_s(t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == 'En cours')).valeur), '1');
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('« Imprimer le plan » ouvre la pièce « Plan annuel de travail — Exercice 2026 »', (t) async {
      final m = poste({'planAnnuel': liste(p['jeu'])});
      await ouvrir(t, m, 'm13-plan-annuel');
      await cliquer(t, find.widgetWithText(BoutonSigh, 'Imprimer le plan'));
      expect(find.text('Exercice 2026'), findsWidgets);
      expect(find.textContaining('Actions programmées'), findsWidgets);
      await t.pump(const Duration(seconds: 10));
    });
  });

  // -------------------------------------------------------------------------------------------------------------------------------------------
  group('m13-notes-service', () {
    final n = obj(v['notes']);
    testWidgets('KPI, critères de la NS 131 (− 6 % / − 10 %…) et primes de la NS 132 (mode, fonctions)', (t) async {
      final m = poste({});
      await ouvrir(t, m, 'm13-notes-service');
      kpisIdentiques(t, obj(n['ecran'])['kpis']);
      final t131 = (obj((obj(n['ecran'])['tableaux'] as List)[0])['lignes'] as List).cast<List>();
      for (final l in t131) {
        expect(find.text('${l[1]}'), findsWidgets, reason: '${l[1]}');
        expect(find.text('${l[2]}'), findsWidgets);
        expect(find.text('${l[3]}'), findsWidgets);
      }
      final t132 = (obj((obj(n['ecran'])['tableaux'] as List)[1])['lignes'] as List).cast<List>();
      for (final l in t132) {
        expect(find.text('${l[0]}'), findsWidgets, reason: '${l[0]}');
      }
      expect(find.text('Forfait mensuel'), findsWidgets);
      expect(find.text('Par occurrence'), findsWidgets);
      expect(find.text('Ouvrir le moteur'), findsNWidgets(2));
      await t.pump(const Duration(seconds: 10));
    });
  });

  // -------------------------------------------------------------------------------------------------------------------------------------------
  group('m13-ambulance', () {
    final a = obj(v['ambulance']);

    testWidgets('KPI et ordre des interventions identiques à la maquette ; filtre « Facturation »', (t) async {
      final m = poste({'ambulance': liste(a['jeu'])});
      await ouvrir(t, m, 'm13-ambulance');
      kpisIdentiques(t, obj(a['ecran'])['kpis']);
      final lignes = (obj((obj(a['ecran'])['tableaux'] as List).first)['lignes'] as List).cast<List>();
      expect(ordreAffiche(t, [for (final l in lignes) '${l[0]}']), [for (final l in lignes) '${l[0]}']);
      expect(find.text('Facturée'), findsWidgets);
      expect(find.text('À facturer'), findsWidgets);
      final tab = t.widget<TableauSigh>(find.byType(TableauSigh).first);
      final f = tab.filtres.firstWhere((x) => x.nom == 'facture');
      final facturees = [for (final l in tab.lignes) if (f.correspond!(l, 'oui')) l['reference']];
      expect(facturees.toSet(), {for (final c in liste(a['filtreCas'])) if (c['filtre'] == 'Facturation' && c['valeur'] == 'oui') ...(c['lignes'] as List)});
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('création : montant calculé 5 000 F + 500 F/km, AM-2026-0008 (E534), patient résolu ; modification : le nom suit le patient', (t) async {
      final m = poste({'ambulance': liste(a['jeu'])});
      await ouvrir(t, m, 'm13-ambulance');
      final col = m.collection('ambulance');
      final n0 = col.toutes.length;
      await cliquer(t, find.widgetWithText(BoutonSigh, 'Nouveau').first);
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Le formulaire comporte des erreurs.'), findsWidgets);
      expect(col.toutes.length, n0, reason: 'refus : rien n’est écrit');
      final att = obj(obj(a['creation'])['tarifCalcule'])['fiche'] as M;
      poser(t, {'patientCode': att['patientCode'], 'dateHeure': '2026-10-30T09:30', 'destination': 'Centre de santé de Perma', 'kilometrage': '20'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 400));
      expect(col.toutes.length, n0 + 1);
      fichesEgales(col.toutes.first, att);
      expect(col.toutes.first['tarif'], 15000);
      expect(col.toutes.first['reference'], 'AM-2026-0008');
      await chercher(t, 'AM-2026-0003');
      await cliquer(t, find.byTooltip('Modifier').first);
      final mod = obj(obj(a['modification'])['enregistre']);
      poser(t, {'patientCode': obj(mod['patient'])['code'], 'facture': true});
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await t.pump(const Duration(milliseconds: 400));
      fichesEgales(col.toutes.firstWhere((x) => x['id'] == 'AMB3'), obj(mod['fiche']));
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('parité : la fiche imprimée porte les six lignes du cartouche', (t) async {
      final m = poste({'ambulance': liste(a['jeu'])});
      await ouvrir(t, m, 'm13-ambulance');
      await chercher(t, 'AM-2026-0002');
      await cliquer(t, find.byTooltip('Imprimer l’état').first);
      expect(find.text('Fiche d’intervention — ambulance'), findsWidgets);
      for (final k in (obj(a['etat'])['cartouche'] as List).cast<List>()) {
        expect(find.textContaining('${k[0]}'), findsWidgets, reason: '${k[0]}');
      }
      await t.pump(const Duration(seconds: 10));
    });
  });

  // -------------------------------------------------------------------------------------------------------------------------------------------
  group('m13-repertoire-ambulances', () {
    final r = obj(v['repertoire']);

    testWidgets('KPI, note « sans numéro », cartes d’appel dans l’ordre de la maquette, numéro en grand', (t) async {
      final m = poste({'ambulances': liste(r['jeu'])});
      await ouvrir(t, m, 'm13-repertoire-ambulances');
      kpisIdentiques(t, obj(r['ecran'])['kpis']);
      expect(find.textContaining('1 fiche(s) sans numéro : CHD Atacora — ambulance'), findsOneWidget);
      final fiches = liste(r['jeu']).where((x) => x['statut'] != 'archive').toList();
      final ordre = admOrdreAppelRapide(fiches);
      final y = {for (final f in ordre) '${f['id']}': t.getTopLeft(find.byKey(Key('adm:appel:${f['id']}'))).dy};
      final lus = (y.keys.toList()..sort((p, q) => y[p]!.compareTo(y[q]!)));
      // la grille passe à la ligne : on compare l'ordre de lecture (haut-bas puis gauche-droite)
      final x = {for (final f in ordre) '${f['id']}': t.getTopLeft(find.byKey(Key('adm:appel:${f['id']}'))).dx};
      lus.sort((p, q) {
        final d = y[p]!.compareTo(y[q]!);
        return d != 0 ? d : x[p]!.compareTo(x[q]!);
      });
      expect(lus, [for (final f in ordre) '${f['id']}']);
      // le numéro se lit en GRAND (24 px), la fiche sans numéro le DIT
      final texte = t.widget<Text>(find.text('+229 96 00 00 01').first);
      expect(texte.style?.fontSize, 24);
      expect(find.text('Numéro à renseigner'), findsOneWidget);
      expect(find.text('Jamais vérifié'), findsOneWidget, reason: 'plus de « depuis null jours » (E535)');
      expect(find.text('Non vérifié depuis 120 jours'), findsOneWidget);
      expect(find.text('Non vérifié depuis 91 jours'), findsOneWidget);
      expect(find.textContaining('Non vérifié depuis 90'), findsNothing, reason: '90 jours exactement n’est pas périmé');
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('JAMAIS de numéro inventé : une fiche créée sans numéro reste vide et « à compléter » (E535)', (t) async {
      final m = poste({'ambulances': liste(r['jeu'])});
      await ouvrir(t, m, 'm13-repertoire-ambulances');
      final col = m.collection('ambulances');
      final n0 = col.toutes.length;
      await cliquer(t, find.widgetWithText(BoutonSigh, 'Ajouter une ambulance'));
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Le formulaire comporte des erreurs.'), findsWidgets, reason: 'la désignation est obligatoire');
      poser(t, {'libelle': 'Sapeurs-pompiers'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 400));
      expect(col.toutes.length, n0 + 1);
      final f = col.toutes.first;
      fichesEgales(f, obj(obj(obj(r['creation'])['sansNumero'])['derniere']));
      expect(f['aCompleter'], true);
      expect(matVideOuAbsent(f['telephone']), isTrue);
      expect(f['verifieLe'], '2026-10-30');
      expect(_s(t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == 'Numéros à renseigner')).valeur), '2');
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('confirmer un numéro date la vérification du jour et NOMME le vérificateur ; changer la disponibilité remonte/descend la carte', (t) async {
      final m = poste({'ambulances': liste(r['jeu'])});
      await ouvrir(t, m, 'm13-repertoire-ambulances');
      final col = m.collection('ambulances');
      await chercher(t, 'Ambulance Alpha');
      await cliquer(t, find.byTooltip('Confirmer que ce numéro est à jour').first);
      final f = col.toutes.firstWhere((x) => x['id'] == 'AMBR4');
      expect(f['verifieLe'], '2026-10-30');
      expect('${f['verifiePar']}', isNotEmpty);
      fichesEgales(f, obj(obj(r['verification'])['fiche']), ignores: {'verifiePar'});
      await chercher(t, 'Ambulance CNT 02');
      await cliquer(t, find.byTooltip('Changer la disponibilité').first);
      poser(t, {'disponibilite': 'en_course', 'observations': 'Sortie à Tanguiéta'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Appliquer'));
      await t.pump(const Duration(milliseconds: 400));
      fichesEgales(col.toutes.firstWhere((x) => x['id'] == 'AMBR2'), obj(obj(obj(r['bascule'])['apres'])['fiche']));
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('droits (arbitrage du 31/10/2026) : l’ACCUEIL tient le répertoire à jour — il crée, vérifie, change la disponibilité', (t) async {
      final m = poste({'ambulances': liste(r['jeu'])});
      await ouvrir(t, m, 'm13-repertoire-ambulances', role: 'reception');
      expect(find.widgetWithText(BoutonSigh, 'Ajouter une ambulance'), findsOneWidget);
      expect(find.byTooltip('Changer la disponibilité'), findsWidgets);
      expect(find.textContaining('Lecture seule'), findsNothing);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('droits : l’agent qui ne peut qu’ouvrir le répertoire n’a AUCUNE commande d’écriture (absentes, jamais grisées)', (t) async {
      final m = poste({'ambulances': liste(r['jeu'])});
      await ouvrir(t, m, 'm13-repertoire-ambulances', role: 'ambulancier');
      expect(find.widgetWithText(BoutonSigh, 'Ajouter une ambulance'), findsNothing);
      expect(find.byTooltip('Confirmer que ce numéro est à jour'), findsNothing);
      expect(find.byTooltip('Changer la disponibilité'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
      expect(find.byTooltip('Consulter'), findsWidgets);
      expect(find.textContaining('Lecture seule'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('répertoire vide : amorcé avec les deux numéros de l’en-tête officiel et trois structures SANS numéro', (t) async {
      final m = poste({'ambulances': []});
      await ouvrir(t, m, 'm13-repertoire-ambulances');
      final a = m.collection('ambulances').toutes;
      expect(a.length, 5);
      expect([for (final x in a) if (x['telephone'] != null) x['telephone']].toSet(), IdentiteClinique.telephones.toSet());
      expect(a.where((x) => x['telephone'] == null).length, 3);
      expect(find.textContaining('3 fiche(s) sans numéro'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });
  });

  // -------------------------------------------------------------------------------------------------------------------------------------------
  group('m13-maintenance', () {
    final mt = obj(v['maintenance']);

    testWidgets('KPI et ordre des équipements ; la fiche non relevée le DIT (« à compléter »), l’entretien échu aussi', (t) async {
      final m = poste({'materiel': liste(mt['jeu'])});
      await ouvrir(t, m, 'm13-maintenance');
      kpisIdentiques(t, obj(mt['ecran'])['kpis']);
      final lignes = (obj((obj(mt['ecran'])['tableaux'] as List).first)['lignes'] as List).cast<List>();
      expect(ordreAffiche(t, [for (final l in lignes) '${l[0]}']), [for (final l in lignes) '${l[0]}']);
      expect(find.text('à compléter'), findsWidgets);
      expect(find.text('échu'), findsNWidgets(3), reason: 'EQ-001, EQ-004, EQ-008 — le réformé EQ-005 n’est pas échu');
      expect(find.text('jamais'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('création : EQ-009 (E536) « à compléter » sans marque, n° de série ni mise en service ; modification qui renseigne : le marquage tombe', (t) async {
      final m = poste({'materiel': liste(mt['jeu'])});
      await ouvrir(t, m, 'm13-maintenance');
      final col = m.collection('materiel');
      final n0 = col.toutes.length;
      await cliquer(t, find.widgetWithText(BoutonSigh, 'Nouveau').first);
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Le formulaire comporte des erreurs.'), findsWidgets);
      expect(col.toutes.length, n0);
      poser(t, {'libelle': 'Autoclave 2', 'categorie': 'Bloc opératoire', 'localisation': 'Bloc opératoire'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 400));
      fichesEgales(col.toutes.first, obj(obj(mt['creation'])['aCompleter'])['fiche'] as M);
      expect(col.toutes.first['reference'], 'EQ-009');
      expect(col.toutes.first['aCompleter'], true);
      await chercher(t, 'EQ-002');
      await cliquer(t, find.byTooltip('Modifier').first);
      poser(t, {'marque': 'Samsung', 'numeroSerie': 'SS-77', 'miseEnService': '2023-02-02', 'etat': 'panne'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await t.pump(const Duration(milliseconds: 400));
      final f = col.toutes.firstWhere((x) => x['id'] == 'MAT002');
      fichesEgales(f, obj(obj(obj(mt['modification'])['enregistre'])['fiche']));
      expect(f['reference'], 'EQ-002', reason: 'la référence ne change pas à la modification');
      expect(f['aCompleter'], false);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('parc vide : amorcé comme la maquette (18 équipements, graine 1348), aucune marque inventée', (t) async {
      final m = poste({'materiel': []});
      await ouvrir(t, m, 'm13-maintenance');
      final a = m.collection('materiel').toutes;
      expect(a.length, 18);
      expect([for (final x in a) x['reference']], [for (var i = 1; i <= 18; i++) 'EQ-${i.toString().padLeft(3, '0')}']);
      expect(a.every((x) => x['marque'] == null && x['numeroSerie'] == null && x['aCompleter'] == true), isTrue);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('filtre « Suivi » : en panne / entretien échu / fiche à compléter', (t) async {
      final m = poste({'materiel': liste(mt['jeu'])});
      await ouvrir(t, m, 'm13-maintenance');
      final tab = t.widget<TableauSigh>(find.byType(TableauSigh).first);
      final f = tab.filtres.firstWhere((x) => x.nom == 'suivi');
      for (final cas in liste(mt['filtreCas'])) {
        final refs = {for (final l in tab.lignes) if (f.correspond!(l, '${cas['valeur']}')) '${l['reference']}'};
        expect(refs, (cas['lignes'] as List).cast<String>().toSet(), reason: '${cas['valeur']}');
      }
      await t.pump(const Duration(seconds: 10));
    });
  });

  // -------------------------------------------------------------------------------------------------------------------------------------------
  group('parité N1 contre les fiches de la maquette (jeu complet, horloge 30/10/2026 10 h)', () {
    for (final id in [
      'm13-courriers',
      'm13-reunions',
      'm13-evenements',
      'm13-plan-annuel',
      'm13-notes-service',
      'm13-ambulance',
      'm13-repertoire-ambulances',
      'm13-maintenance',
    ]) {
      testWidgets(id, (t) async {
        final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
        await ouvrir(t, m, id);
        final fiche = obj(jsonDecode(File('../../docs/architecture/ecrans/$id.json').readAsStringSync()));
        final p = comparerContenu(id, fiche, textesVisibles(t));
        expect(p.manquants, isEmpty, reason: '$id : taux ${p.taux}');
        await t.pump(const Duration(seconds: 10));
      });
    }
  });
}

bool matVideOuAbsent(Object? v) => v == null || v == '';
