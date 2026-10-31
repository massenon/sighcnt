import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show cfbEssentielles, cfbPlanVidage;
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/cfg/cfb_systeme.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// cfg-systeme : les règles (corbeille, bilan d'un vidage, libellés de collection) sont rejouées sur les vecteurs de la maquette
/// (packages/domaine/test/cfb_regles_test.dart) ; ici, l'ÉCRAN — la corbeille qui restaure (RG-14), la porte du barème NS 131 (motif, journal, réglage lu par
/// l'écran des évaluations), la bascule des jeux de test (bouton ABSENT quand elle est fermée), le vidage qui garde l'essentiel, l'export, la régénération.
void main() {
  setUpAll(chargerPolices);
  tearDown(() {
    ToastsSigh.viderPourTests();
    CfbPersistance.disponible = () => false;
  });

  Future<void> onglet(WidgetTester t, String id) => toucherM14(t, find.byKey(Key('kit:onglet:$id')));
  Fiche? reglage(Magasin m, String id) => m.collection('reglages').actives.where((f) => f['id'] == id).firstOrNull;

  casM14('ouverture : quatre onglets, quatre indicateurs CALCULÉS sur le magasin, persistance dite honnêtement (en mémoire)', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-systeme');
    for (final k in ['Installation et données', 'Corbeille', 'Barème NS 131', 'Jeux de test']) {
      expect(find.text(k), findsWidgets, reason: k);
    }
    final noms = cfbNomsCollections();
    final total = noms.fold<int>(0, (a, n) => a + m.collection(n).toutes.length);
    expect(find.text('${noms.length}'), findsWidgets);
    expect(find.byWidgetPredicate((w) => w is Text && (w.data ?? '').replaceAll(RegExp(r'[\s  ]'), '') == '$total'), findsWidgets);
    expect(find.text('Mémoire'), findsOneWidget);
    expect(find.text('Version du prototype'), findsOneWidget);
    expect(find.text('Architecture cible — proposition'), findsOneWidget);
    expect(find.textContaining('Cette architecture est une proposition technique, pas une décision'), findsOneWidget);
    for (final b in ['Réinitialiser le jeu de données', 'Exporter les données', 'Plan du site', 'Sauvegardes']) {
      expect(find.widgetWithText(BoutonSigh, b), findsOneWidget, reason: b);
    }
  });

  casM14('la corbeille balaie TOUS les modules : une fiche archivée à un endroit se retrouve ici, restaurée d’un geste et journalisée', (t) async {
    final m = magasinM14();
    m.collection('centresCouts').archiver(m.collection('centresCouts').actives.first['id']);
    final fiche = m.collection('centresCouts').archivees.single;
    await ouvrirM14(t, m, 'cfg-systeme');
    await onglet(t, 'corbeille');
    expect(find.text('Fiches archivées'), findsWidgets);
    expect(find.text('Centres de coûts'), findsWidgets, reason: 'le type de fiche vient de la table de libellés de la maquette');
    expect(find.text('${fiche['id']}'), findsOneWidget);
    expect(find.text('Impossible'), findsOneWidget);
    await toucherM14(t, find.byTooltip('Restaurer').first);
    expect(find.textContaining('La fiche réapparaîtra dans Centres de coûts (M12) et redeviendra modifiable.'), findsOneWidget);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Restaurer').last);
    expect(m.collection('centresCouts').archivees, isEmpty);
    expect(m.collection('centresCouts').actives.length, 7, reason: 'restaurée : rien n’est perdu');
    expect(find.text('Fiche restaurée dans Centres de coûts.'), findsOneWidget);
    final j = m.collection('audit').toutes.firstWhere((a) => a['action'] == 'Restauration');
    expect(j['reference'], fiche['code']);
  });

  casM14('corbeille vide : l’écran le dit au lieu d’un tableau vide', (t) async {
    final m = magasinM14();
    for (final n in cfbNomsCollections()) {
      for (final f in m.collection(n).archivees) {
        m.collection(n).restaurer(f['id']);
      }
    }
    await ouvrirM14(t, m, 'cfg-systeme');
    await onglet(t, 'corbeille');
    expect(find.text('La corbeille est vide — aucune fiche archivée.'), findsOneWidget);
  });

  casM14('barème NS 131 : fermé par défaut ; l’ouvrir exige un motif, écrit la porte aux réglages (lue par l’écran des évaluations), journalise ; la refermer aussi', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-systeme');
    await onglet(t, 'bareme');
    expect(find.text('Fermée'), findsOneWidget);
    expect(find.text('NS 131/07/DM/DA/CNT/2026'), findsWidgets);
    expect(find.text('13/07/2026'), findsOneWidget);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Autoriser la modification'));
    expect(find.textContaining('Le barème fixe les retenues sur salaire.'), findsOneWidget);
    await t.tap(find.widgetWithText(BoutonSigh, 'Autoriser la modification').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(reglage(m, 'baremeModifiable'), isNull, reason: 'sans motif, la porte reste fermée');
    await t.enterText(find.byType(TextField).last, 'Révision du barème');
    await t.pump();
    await t.tap(find.widgetWithText(BoutonSigh, 'Autoriser la modification').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(reglage(m, 'baremeModifiable')!['valeur'], true);
    expect(find.text('Modification du barème autorisée.'), findsOneWidget);
    expect(find.text('Ouverte'), findsOneWidget);
    final j = m.collection('audit').toutes.firstWhere((a) => a['action'] == 'Ouverture de la modification du barème');
    expect([j['module'], j['entite'], j['reference']], ['M10', 'Barème', 'NS 131/07/DM/DA/CNT/2026']);
    expect(j['apres'], {'motif': 'Révision du barème'});
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Refermer la modification'));
    expect(reglage(m, 'baremeModifiable')!['valeur'], false);
    expect(find.text('Modification du barème refermée.'), findsOneWidget);
    expect(m.collection('audit').toutes.any((a) => a['action'] == 'Fermeture de la modification du barème'), isTrue);
  });

  casM14('jeux de test verrouillés : AUCUN bouton d’effacement (absent, non grisé), le message dit où l’autoriser', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-systeme');
    await onglet(t, 'reinitialisation');
    expect(find.text('Verrouillée'), findsOneWidget);
    expect(find.text('Aucun effacement possible'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Vider les jeux de test'), findsNothing);
    expect(find.widgetWithText(BoutonSigh, 'Régénérer le jeu de démonstration complet'), findsNothing);
    expect(find.text('Réinitialisation verrouillée — activer l’autorisation ci-dessus pour la rendre possible.'), findsOneWidget);
    expect(find.textContaining('produits (184)'), findsOneWidget, reason: 'ce qui serait conservé est montré avec ses effectifs');
  });

  casM14('le bouton de maintenance, tant que les jeux de test sont verrouillés, REFUSE en le disant — rien n’est effacé', (t) async {
    final m = magasinM14();
    final avant = m.collection('patients').toutes.length;
    await ouvrirM14(t, m, 'cfg-systeme');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Réinitialiser le jeu de données'));
    expect(find.text('Réinitialisation verrouillée.'), findsOneWidget);
    expect(find.textContaining('Autoriser d’abord l’effacement'), findsOneWidget);
    expect(m.collection('patients').toutes.length, avant);
  });

  casM14('autoriser puis vider : motif exigé ; les données d’ACTIVITÉ partent, le paramétrage, les droits et le journal restent ; le vidage est la 1re entrée du journal', (t) async {
    final m = magasinM14();
    final produits = m.collection('produits').toutes.length;
    final patients = m.collection('patients').toutes.length;
    final auditAvant = m.collection('audit').toutes.length;
    final plan = cfbPlanVidage({for (final n in cfbNomsCollections()) n: m.collection(n).toutes.length}, {...cfbEssentielles, ...cfbCollectionsTechniques});
    await ouvrirM14(t, m, 'cfg-systeme');
    await onglet(t, 'reinitialisation');
    await toucherM14(t, find.byKey(const Key('cfb:reinit:bascule')));
    expect(find.textContaining('Sur un poste en production, la laisser fermée est la seule position raisonnable'), findsOneWidget);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Autoriser'));
    expect(reglage(m, 'reinitAutorisee')!['valeur'], true);
    expect(find.text('Autorisée'), findsOneWidget);
    expect(m.collection('audit').toutes.any((a) => a['action'] == 'Déverrouillage'), isTrue);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Vider les jeux de test'));
    expect(find.textContaining('Les ${plan.tables} tables d’activité seront vidées'), findsOneWidget);
    await t.tap(find.widgetWithText(BoutonSigh, 'Vider les jeux de test').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(m.collection('patients').toutes.length, patients, reason: 'sans motif, rien ne part');
    await t.enterText(find.byType(TextField).last, 'Fin de la recette');
    await t.pump();
    await t.tap(find.widgetWithText(BoutonSigh, 'Vider les jeux de test').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(m.collection('patients').toutes, isEmpty);
    expect(m.collection('factures').toutes, isEmpty);
    expect(m.collection('produits').toutes.length, produits, reason: 'les référentiels sont conservés');
    expect(m.collection('rbac').toutes, isNotEmpty);
    expect(m.collection('modulesActifs').toutes, isNotEmpty);
    expect(m.collection('modulesManifeste').toutes, isNotEmpty, reason: 'la matrice engendrée du poste survit à tout vidage');
    expect(m.collection('echeancesFiscales').toutes.length, 63, reason: 'le calendrier, dérivé d’un document, revient SANS règlement');
    expect(m.collection('echeancesFiscales').toutes.any((e) => e['paye'] == true), isFalse);
    expect(m.collection('audit').toutes.length, greaterThanOrEqualTo(auditAvant), reason: 'le journal se garde : il trace ce que le vidage conserve');
    final j = m.collection('audit').toutes.first;
    expect([j['action'], j['module'], j['entite'], j['reference']], ['Réinitialisation des jeux de test', 'CFG', 'Base', 'vidage']);
    expect(j['apres'], {'tables': plan.tables, 'enregistrements': plan.enregistrements, 'motif': 'Fin de la recette'});
    expect(find.textContaining('table(s) vidée(s)'), findsOneWidget);
    // verrouiller de nouveau : les boutons disparaissent
    await toucherM14(t, find.byKey(const Key('cfb:reinit:bascule')));
    expect(reglage(m, 'reinitAutorisee')!['valeur'], false);
    expect(find.widgetWithText(BoutonSigh, 'Vider les jeux de test'), findsNothing);
    expect(m.collection('audit').toutes.any((a) => a['action'] == 'Verrouillage'), isTrue);
  });

  casM14('régénérer le jeu complet : tout revient du jeu initial, la porte des jeux de test reste dans son état', (t) async {
    final m = magasinM14();
    final patients = m.collection('patients').toutes.length;
    CfbJeu.charger = (nom) async => File('test/fixtures/jeu_sobre/$nom.json').readAsStringSync();
    m.collection('reglages').inserer({'id': 'reinitAutorisee', 'statut': 'actif', 'valeur': true});
    m.collection('reglages').inserer({'id': 'valorisationSortie', 'statut': 'actif', 'valeur': 'cump'});
    await ouvrirM14(t, m, 'cfg-systeme');
    await onglet(t, 'reinitialisation');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Vider les jeux de test'));
    await t.enterText(find.byType(TextField).last, 'Essai');
    await t.pump();
    await t.tap(find.widgetWithText(BoutonSigh, 'Vider les jeux de test').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(m.collection('patients').toutes, isEmpty);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Régénérer le jeu de démonstration complet'));
    expect(find.textContaining('Toute la base est remplacée par le jeu initial, paramétrage compris.'), findsOneWidget);
    await t.enterText(find.byType(TextField).last, 'Reprise de la démonstration');
    await t.pump();
    await t.runAsync(() async {
      await t.tap(find.widgetWithText(BoutonSigh, 'Régénérer').last);
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await t.pump(const Duration(milliseconds: 400));
    expect(m.collection('patients').toutes.length, patients);
    expect(reglage(m, 'reinitAutorisee')!['valeur'], true, reason: 'l’autorisation est une bascule du poste, non une donnée du jeu');
    expect(reglage(m, 'valorisationSortie'), isNull, reason: 'le paramétrage revient au jeu initial');
    expect(m.collection('audit').toutes.first['action'], 'Régénération du jeu de démonstration');
    expect(find.text('Jeu de démonstration régénéré.'), findsOneWidget);
  });

  casM14('exporter les données : un fichier JSON daté, toutes les collections, le chemin annoncé ; un échec est DIT', (t) async {
    final m = magasinM14();
    String? nom, contenu;
    CfbExport.ecrire = (n, c) async {
      nom = n;
      contenu = c;
      return '/tmp/$n';
    };
    await ouvrirM14(t, m, 'cfg-systeme');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Exporter les données'));
    await t.pump(const Duration(milliseconds: 300));
    expect(nom, 'sigh-cnt-donnees-2026-10-30.json');
    final j = jsonDecode(contenu!) as Map;
    expect(j.keys.toSet(), cfbNomsCollections().toSet());
    expect((j['centresCouts'] as List).length, 7);
    expect(find.text('Export JSON généré.'), findsOneWidget);
    CfbExport.ecrire = (n, c) async => throw const FileSystemException('disque plein');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Exporter les données'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Export impossible'), findsOneWidget);
  });

  casM14('droits : en lecture seule, la porte du barème, la bascule des jeux de test, la restauration et la maintenance sont ABSENTES', (t) async {
    final m = magasinM14();
    m.collection('centresCouts').archiver(m.collection('centresCouts').actives.first['id']);
    final d = donneesLectureSeule('admin', 'cfg-systeme');
    await ouvrirM14(t, m, 'cfg-systeme', role: 'admin', donnees: d);
    expect(find.widgetWithText(BoutonSigh, 'Réinitialiser le jeu de données'), findsNothing);
    await onglet(t, 'corbeille');
    expect(find.byTooltip('Restaurer'), findsNothing);
    await onglet(t, 'bareme');
    expect(find.widgetWithText(BoutonSigh, 'Autoriser la modification'), findsNothing);
    expect(find.text('Fermée'), findsOneWidget);
  });
}
