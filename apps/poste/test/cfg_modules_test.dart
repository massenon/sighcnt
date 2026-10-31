import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// cfg-modules : les règles (fermetures, écrans retirés, noyau, code d'activité) sont rejouées sur les vecteurs de la maquette
/// (packages/domaine/test/cfb_regles_test.dart) ; ici, l'ÉCRAN — la bascule d'un module (motif obligatoire, journal avant / après), le refus nommé du
/// noyau, la fiche archivée qui ne ferme plus rien, et la commande ABSENTE sans le droit.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  casM14('ouverture : 300 écrans au périmètre, 2 activités fermées (banque de sang, transfusion), 2 écrans retirés, 22 modules pilotables', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-modules');
    for (final k in ['Écrans au périmètre', 'Activités fermées', 'Écrans retirés du menu', 'Écrans ouverts', '300', '298']) {
      expect(find.text(k), findsWidgets, reason: k);
    }
    expect(find.text('Banque de sang'), findsWidgets);
    expect(find.text('Donneurs & transfusions'), findsWidgets);
    expect(find.text('La clinique ne pratique pas la banque de sang.'), findsWidgets);
    expect(find.text('21/08/2026'), findsWidgets);
    expect(find.byTooltip('Fermer le module M7'), findsOneWidget);
    expect(find.byTooltip('Fermer le module GED'), findsOneWidget);
    expect(find.byTooltip('Fermer le module DASH'), findsNothing, reason: 'le NOYAU ne se ferme pas : la bascule est absente de sa carte');
    expect(find.byTooltip('Fermer le module CFG'), findsNothing);
    expect(find.text('Toujours ouvert'), findsNWidgets(2));
    expect(find.textContaining('NOYAU : porte cet interrupteur'), findsOneWidget);
  });

  casM14('fermer M7 : le motif est exigé ; fermé, 9 écrans quittent le menu (11 retirés), la fiche et le journal disent avant / après', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-modules');
    await toucherM14(t, find.byTooltip('Fermer le module M7'));
    expect(find.textContaining('Le module M7 entier disparaîtra du méga-menu'), findsOneWidget);
    await t.tap(find.widgetWithText(BoutonSigh, 'Fermer l’activité').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(m.collection('modulesActifs').actives.where((f) => f['actif'] == false).length, 2, reason: 'sans motif, rien ne ferme');
    await t.enterText(find.byType(TextField).last, 'Pas de service d’achats pour le test');
    await t.pump();
    await t.tap(find.widgetWithText(BoutonSigh, 'Fermer l’activité').last);
    await t.pump(const Duration(milliseconds: 400));
    final f = m.collection('modulesActifs').actives.firstWhere((x) => x['module'] == 'M7');
    expect([f['code'], f['actif'], f['motif'], f['fermeLe'], f['fermePar']], ['MODULE-M7', false, 'Pas de service d’achats pour le test', '2026-10-30', 'Administrateur système']);
    expect(find.text('Activité fermée.'), findsOneWidget);
    expect(find.text('11'), findsWidgets, reason: 'écrans retirés du menu : 2 + 9');
    expect(find.text('289'), findsWidgets);
    expect(find.text('Bons de commande'), findsWidgets, reason: 'la liste des écrans retirés le montre');
    final j = m.collection('audit').toutes.firstWhere((a) => a['action'] == 'Fermeture d’une activité');
    expect([j['module'], j['entite'], j['reference']], ['CFG', 'Activité', 'MODULE-M7']);
    expect(j['avant'], {'actif': true});
    expect(j['apres'], {'actif': false}, reason: 'la maquette écrivait la même valeur avant et après (E881)');
  });

  casM14('rouvrir M7 : aucune donnée n’a bougé, la fiche garde son motif, la réouverture est datée, signée et journalisée', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-modules');
    await toucherM14(t, find.byTooltip('Fermer le module M7'));
    await t.enterText(find.byType(TextField).last, 'Essai');
    await t.pump();
    await t.tap(find.widgetWithText(BoutonSigh, 'Fermer l’activité').last);
    await t.pump(const Duration(milliseconds: 400));
    await toucherM14(t, find.byTooltip('Rouvrir le module M7'));
    expect(find.textContaining('Le module M7 réapparaîtra au méga-menu, avec leurs données inchangées.'), findsOneWidget);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Rouvrir l’activité'));
    final f = m.collection('modulesActifs').actives.firstWhere((x) => x['module'] == 'M7');
    expect([f['actif'], f['motif'], f['fermeLe'], f['rouvertLe'], f['rouvertPar']], [true, 'Essai', null, '2026-10-30', 'Administrateur système']);
    expect(find.text('Activité rouverte.'), findsOneWidget);
    expect(find.text('298'), findsWidgets);
    expect(m.collection('modulesActifs').toutes.length, 3, reason: 'la fiche reste : fermer et rouvrir ne supprime rien');
  });

  casM14('le NOYAU ne se ferme pas, quelle que soit la porte : une activité déclarée sur CFG entier est refusée en le disant', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-modules');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Piloter une activité'));
    await saisir(t, 'libelle', 'Activité noyau test');
    // 22 modules : la liste a sa recherche ; on y tape le nom avant de toucher l'option
    await toucherM14(t, find.descendant(of: find.byKey(const Key('kit:champ:module')), matching: find.byType(InkWell)).first);
    await t.pump(const Duration(milliseconds: 400));
    await t.enterText(find.byType(TextField).last, 'Configuration');
    await t.pump(const Duration(milliseconds: 600));
    await t.tap(find.descendant(of: find.byType(InkWell), matching: find.text('CFG — Configuration Clinique')).last);
    await t.pump(const Duration(milliseconds: 400));
    await saisir(t, 'motif', 'Essai du noyau');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Déclarer'));
    final f = m.collection('modulesActifs').actives.firstWhere((x) => x['module'] == 'CFG');
    expect([f['code'], f['actif'], f['ecrans']], ['CFG-ACTIVITN', true, <String>[]]);
    expect(find.text('Activité déclarée.'), findsOneWidget);
    await toucherM14(t, find.byTooltip('Fermer cette activité').first);
    expect(find.text('Le module CFG ne se ferme pas.'), findsOneWidget);
    expect(find.textContaining('Il porte cet interrupteur'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Fermer l’activité'), findsNothing, reason: 'aucune confirmation n’est même proposée');
    expect(m.collection('modulesActifs').actives.firstWhere((x) => x['module'] == 'CFG')['actif'], true);
  });

  casM14('une fiche ARCHIVÉE ne ferme plus rien (RG-14) : un seul écran reste retiré du menu', (t) async {
    final m = magasinM14();
    m.collection('modulesActifs').archiver('MOD01');
    await ouvrirM14(t, m, 'cfg-modules');
    expect(find.text('Banque de sang'), findsNothing, reason: 'la fiche archivée n’est plus montrée par l’écran de pilotage');
    expect(find.text('299'), findsWidgets);
    expect(find.text('Donneurs & transfusions'), findsWidgets);
  });

  casM14('droits : en lecture seule, « Piloter une activité » et les bascules sont ABSENTES (jamais grisées) et le bandeau le dit', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-modules', role: 'admin', donnees: donneesLectureSeule('admin', 'cfg-modules'));
    expect(find.widgetWithText(BoutonSigh, 'Piloter une activité'), findsNothing);
    expect(find.byTooltip('Fermer le module M7'), findsNothing);
    expect(find.byTooltip('Rouvrir cette activité'), findsNothing);
    expect(find.textContaining('Lecture seule'), findsOneWidget);
    expect(find.text('Modules du logiciel — activer seulement ce que l’établissement exerce'), findsOneWidget);
  });
}
