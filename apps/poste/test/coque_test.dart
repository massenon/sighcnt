import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/shell/coque.dart';
import 'package:sigh_poste/sync/etat_sync.dart';

import 'aide_polices.dart';

final donnees = DonneesNavigation.depuisDossier();

ClientMere clientVide() => ClientMere(
      base: Uri.parse('http://mere.test'),
      secretAdmin: 's',
      client: MockClient((req) async => http.Response(
          '{"epoch":1,"seq_max":0,"appareils":[],"etat":"ok","controles":[]}',
          200)),
    );

Future<void> monter(WidgetTester t,
    {required ConfigPoste config, ClientMere? client}) async {
  t.view.physicalSize = const Size(1600, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t
      .pumpWidget(SighPoste(donnees: donnees, config: config, client: client));
  await t.pump();
}

/// Un domaine du ruban, puis une pastille : le geste de l'agent.
Future<void> ouvrir(WidgetTester t, String domaine, String ecran) async {
  await t.tap(find.byKey(Key('domaine-$domaine')));
  await t.pump();
  await t.tap(find.byKey(Key('pastille-$ecran')));
  await t.pump(const Duration(milliseconds: 200));
}

void main() {
  // Les VRAIES polices : en Ahem, chaque lettre est un carré de 14 px et le ruban déborde, ce que la maquette ne fait pas.
  setUpAll(chargerPolices);
  // Le défaut LIVRÉ : le panneau du méga-menu est replié à l'ouverture.
  setUp(() => CoquePoste.panneauOuvertAuDemarrage = false);
  tearDownAll(() => CoquePoste.panneauOuvertAuDemarrage = true);

  testWidgets(
      'le ruban est celui de la maquette : barre supérieure, onglets de domaine, panneau à rangées de pastilles',
      (t) async {
    await monter(t,
        config: const ConfigPoste(
            mode: ModePoste.fileul,
            role: 'admin',
            nomPoste: 'BASSONGUI Chabi Séko'));
    expect(find.byKey(const Key('barre-superieure')), findsOneWidget);
    expect(find.text('NASSIERA TOO'), findsOneWidget);
    expect(find.byKey(const Key('recherche-globale')), findsOneWidget);
    expect(find.text('Ctrl K'), findsOneWidget);
    expect(find.byKey(const Key('role-courant')), findsOneWidget);
    for (final d in [
      'Accueil',
      'Soins',
      'Logistique',
      'Financier',
      'RH',
      'Administration',
      'Système',
      'Pilotage'
    ]) {
      expect(find.byKey(Key('domaine-$d')), findsOneWidget, reason: d);
    }
    // À l'ouverture du poste le panneau du méga-menu est REPLIÉ (Direction, 03/11/2026) : aucun domaine n'étale ses pastilles.
    expect(find.byKey(const Key('pastille-dash-admin')), findsNothing, reason: 'le méga-menu de Pilotage ne s\'affiche pas à l\'ouverture');
    await t.tap(find.byKey(const Key('domaine-Pilotage')));
    await t.pump();
    expect(find.byKey(const Key('panneau-ruban')), findsOneWidget);
    // Le panneau s'ouvre sur le domaine cliqué (Pilotage), pas sur les autres.
    expect(find.byKey(const Key('pastille-dash-admin')), findsOneWidget);
    expect(find.byKey(const Key('pastille-m14-utilisateurs')), findsNothing,
        reason: 'le panneau n\'ouvre que le domaine courant');
    await t.tap(find.byKey(const Key('domaine-Système')));
    await t.pump();
    expect(find.byKey(const Key('pastille-m14-utilisateurs')), findsOneWidget);
    expect(find.byKey(const Key('pastille-dash-admin')), findsNothing);
  });

  testWidgets(
      'l\'ouverture se fait sur la page d\'accueil DU RÔLE, et les raccourcis permanents sont là',
      (t) async {
    await monter(t,
        config: const ConfigPoste(mode: ModePoste.fileul, role: 'admin'));
    expect(find.byKey(const Key('pastille-dash-admin')), findsNothing, reason: 'panneau replié à l\'ouverture');
    for (final r in ['Patients', 'Consultations', 'Pharmacie', 'Facturation']) {
      expect(find.byKey(Key('raccourci-$r')), findsOneWidget, reason: r);
    }
    await t.tap(find.byKey(const Key('raccourci-Pharmacie')));
    await t.pump();
    // La page d'accueil du module est PORTÉE (E1741) : une carte par écran du module, plus la coque « à convertir ».
    expect(find.byKey(const Key('hub')), findsOneWidget);
    expect(find.byKey(const Key('ecran-a-porter')), findsNothing);
    expect(find.byKey(const Key('hub-carte:m6-produits')), findsOneWidget);
  });

  testWidgets(
      'un POSTE FILEUL n\'a pas le domaine « Poste mère », même pour l\'administrateur',
      (t) async {
    await monter(t,
        config: const ConfigPoste(mode: ModePoste.fileul, role: 'admin'));
    expect(find.byKey(const Key('domaine-Poste mère')), findsNothing);
    expect(find.text('SIGH — Gestion hospitalière'), findsOneWidget);
  });

  testWidgets(
      'la MÈRE a les mêmes domaines PLUS « Poste mère » ; on y ouvre ses modules',
      (t) async {
    await monter(t,
        config: const ConfigPoste(mode: ModePoste.mere, role: 'admin'),
        client: clientVide());
    expect(find.byKey(const Key('domaine-Soins')), findsOneWidget,
        reason: 'la mère garde les écrans du fileul');
    expect(find.byKey(const Key('domaine-Poste mère')), findsOneWidget);
    expect(find.text('SIGH — poste mère'), findsOneWidget);
    await ouvrir(t, 'Poste mère', 'mere-journal-technique');
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('titre-page')), findsOneWidget);
    expect(find.text('Journal technique'), findsWidgets);
    expect(find.text('Aucun évènement enregistré.'), findsOneWidget,
        reason: 'écran porté : la console de la mère');
  });

  testWidgets(
      'les droits viennent de la matrice : le caissier n\'a ni « Système » ni « Poste mère », même sur la mère',
      (t) async {
    await monter(t,
        config: const ConfigPoste(mode: ModePoste.mere, role: 'caissier'),
        client: clientVide());
    expect(find.byKey(const Key('domaine-Système')), findsNothing);
    expect(find.byKey(const Key('domaine-Poste mère')), findsNothing);
    expect(find.byKey(const Key('domaine-Financier')), findsOneWidget);
  });

  testWidgets(
      'un identifiant sans widget se NOMME : tranche, domaine et module, jamais une page vide ni un chantier',
      (t) async {
    // Tous les écrans du manifeste sont désormais portés : le repli de la coque se vérifie avec un registre d'écrans VIDE, comme au premier jour.
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(MaterialApp(
        home: CoquePoste(
            config: const ConfigPoste(mode: ModePoste.fileul, role: 'admin'),
            donnees: donnees,
            ecrans: const {},
            ecranInitial: 'rls-tableau',
            etatSync: ValueNotifier(const EtatSync(niveau: NiveauSync.horsLigne)))));
    await t.pump();
    expect(find.byKey(const Key('ecran-a-porter')), findsOneWidget);
    expect(find.textContaining('Identifiant : rls-tableau'), findsOneWidget);
    expect(find.textContaining('tranche 6'), findsOneWidget);
    // L'état dit où l'écran vit et ce qu'il faut faire ; jamais « à convertir » (Direction, 01/11/2026).
    expect(find.text('Cet écran n’est pas disponible sur ce poste'), findsOneWidget);
    expect(find.textContaining('signaler l’incident'), findsOneWidget);
    expect(find.textContaining('à convertir'), findsNothing);
    expect(find.byKey(const Key('fil-ariane')), findsOneWidget);
  });

  testWidgets(
      'une pastille referme le panneau (la page s\'ouvre menu replié) ; la bascule le rouvre',
      (t) async {
    await monter(t,
        config: const ConfigPoste(mode: ModePoste.fileul, role: 'admin'));
    await ouvrir(t, 'Système', 'cfg-poste');
    expect(find.byKey(const Key('panneau-ruban')), findsNothing);
    await t.tap(find.byKey(const Key('ruban-bascule')));
    await t.pump();
    expect(find.byKey(const Key('panneau-ruban')), findsOneWidget);
  });

  testWidgets(
      'aucun module ouvert au profil : le dit, pas d\'écran blanc (rôle archivé)',
      (t) async {
    await monter(t,
        config: const ConfigPoste(mode: ModePoste.fileul, role: 'pharmacien'));
    expect(
        find.text('Aucun module n’est ouvert à votre profil.'), findsOneWidget);
  });

  test(
      'la table des écrans portés ne contient que des écrans du manifeste (aucun identifiant mort)',
      () {
    final connus = donnees.manifeste.tousLesEcrans.map((e) => e.id).toSet();
    for (final id in [
      'cfg-poste',
      'mere-supervision',
      'mere-appareils',
      'mere-conflits',
      'mere-journal-technique',
      'mere-reinit'
    ]) {
      expect(connus, contains(id));
    }
  });
}
