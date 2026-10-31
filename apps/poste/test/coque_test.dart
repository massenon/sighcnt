import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/mere/client_mere.dart';

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
    expect(find.byKey(const Key('panneau-ruban')), findsOneWidget);
    // Le panneau s'ouvre sur le domaine de la page d'accueil du rôle (Pilotage pour l'administrateur), pas sur les autres.
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
    expect(find.byKey(const Key('pastille-dash-admin')), findsOneWidget);
    for (final r in ['Patients', 'Consultations', 'Pharmacie', 'Facturation']) {
      expect(find.byKey(Key('raccourci-$r')), findsOneWidget, reason: r);
    }
    await t.tap(find.byKey(const Key('raccourci-Pharmacie')));
    await t.pump();
    expect(find.textContaining('Identifiant : hub-m6'), findsOneWidget);
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
      'un écran de la maquette pas encore converti se NOMME : tranche et parité, jamais une page vide',
      (t) async {
    await monter(t,
        config: const ConfigPoste(mode: ModePoste.fileul, role: 'admin'));
    await ouvrir(t, 'Relais en ligne', 'rls-tableau');
    expect(find.byKey(const Key('ecran-a-porter')), findsOneWidget);
    expect(find.textContaining('Identifiant : rls-tableau'), findsOneWidget);
    expect(find.textContaining('tranche 6'), findsOneWidget);
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
