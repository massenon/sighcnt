import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show Droit, cfbEssentielles, tarCollectionsReferentiel, valCollectionValidations;
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/persistance.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/cfg/cfb_modules.dart';
import 'package:sigh_poste/modules/registre.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';

import 'aide_polices.dart';

/// LES QUATRE ÉCRANS NON PORTÉS SONT FERMÉS PAR LE JEU DU POSTE (Direction, 11/11/2026, ECARTS E2422 à E2425) : la fermeture est une fiche de `modulesActifs`
/// (`proprePoste`), l'inventaire des écrans ouverts à chaque rôle est éprouvé à `ecrans_sans_chantier_test.dart`. Ici : ce qui arrive à un poste D'AVANT (magasin
/// déjà posé sur le disque), et ce que l'écran des activités propose pour un écran que le poste ne porte pas.
const quatre = {'m12-calendrier-fiscal', 'm13-sms-journal', 'cfg-bareme-aib', 'cfg-sms'};

/// Les collections fusionnables du démarrage réel (`main.dart`).
final fusionnables = {...cfbEssentielles, valCollectionValidations, ...tarCollectionsReferentiel}.difference({'utilisateurs', 'identifiants'});

/// Les fiches `proprePoste` du jeu livré : les quatre écrans non portés plus les pages de jeux d'import non portés (lot IMP-C).
int nbPropresDuJeu() => (jsonDecode(File('assets/donnees/jeu/modulesActifs.json').readAsStringSync()) as List).where((f) => (f as Map)['proprePoste'] == true).length;

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);
  final donnees = DonneesNavigation.depuisDossier();

  /// Le jeu livré par la version précédente du poste : celui de la maquette seul (aucune fermeture `proprePoste`).
  Magasin jeuDAvant() {
    final m = Magasin.depuisDossier(['rbac', 'modulesActifs']);
    final ancien = [for (final f in m.collection('modulesActifs').toutes) if (f['proprePoste'] != true) f];
    return Magasin({
      'rbac': m.collection('rbac').toutes,
      'modulesActifs': ancien,
    });
  }

  Set<String> fermesPour(Magasin m, String role) => {
        for (final id in quatre)
          if (!donnees.aChaud(m).matrice.peutVoir(role, id)) id
      };

  group('un poste d\'AVANT reçoit la fermeture par la reprise du jeu livré, sans écraser ce que l\'agent a fait à l\'écran', () {
    test('magasin déjà posé AVEC des fiches d\'activité : les quatre fermetures sont ajoutées, la réouverture de la banque de sang est gardée', () async {
      final p = PersistanceMemoire();
      final v1 = jeuDAvant();
      await v1.brancherPersistance(p, delai: Duration.zero, fusionnables: fusionnables);
      // L'agent a rouvert la banque de sang depuis la gestion des activités (fiche mise à jour, datée), et le poste l'a écrite sur le disque.
      v1.collection('modulesActifs').mettreAJour('MOD01', {'actif': true, 'rouvertLe': '2026-11-02', 'rouvertPar': 'Direction'});
      await v1.ecrireMaintenant();
      expect(fermesPour(v1, 'admin'), isEmpty, reason: 'avant la reprise, rien n\'est fermé');

      // Nouvelle version du poste : le jeu livré porte les quatre fermetures.
      final v2 = Magasin.depuisDossier(['rbac', 'modulesActifs']);
      await v2.brancherPersistance(p, fusionnables: fusionnables);
      // Les quatre écrans non portés plus les pages de jeux d'import non portés (lot IMP-C) : une fiche `proprePoste` du jeu livré par écran, comptées du fichier même.
      final nbPropres = nbPropresDuJeu();
      expect(nbPropres, 4 + 5, reason: 'quatre écrans plus les pages des jeux d\'import encore non portés (cinq après le groupe stock du lot 8 et les groupes prix, garanties et couvertures du lot 8b)');
      expect(v2.jeuxFusionnes, {'modulesActifs': nbPropres}, reason: 'les fiches propres au poste arrivent, rien d\'autre');
      final col = v2.collection('modulesActifs');
      expect([for (final id in ['MODP01', 'MODP02', 'MODP03', 'MODP04']) col.parId(id)!['actif']], everyElement(false));
      expect(col.parId('MOD01')!['actif'], true, reason: 'la réouverture faite à l\'écran n\'est pas écrasée');
      expect(col.parId('MOD01')!['rouvertLe'], '2026-11-02');
      for (final role in ['admin', 'direction', 'da', 'comptable']) {
        expect(fermesPour(v2, role), quatre, reason: role);
      }
      expect(donnees.aChaud(v2).matrice.peutVoir('admin', 'm5-banque-sang'), isTrue, reason: 'la banque de sang rouverte reste ouverte');
      expect(donnees.aChaud(v2).matrice.peutVoir('admin', 'm5-donneurs'), isFalse, reason: 'la transfusion, jamais rouverte, reste fermée');
    });

    test('magasin déjà posé SANS fiche d\'activité (cfg-modules jamais ouvert) : le jeu livré s\'applique tel quel', () async {
      final p = PersistanceMemoire();
      final v1 = Magasin({
        'rbac': Magasin.depuisDossier(['rbac']).collection('rbac').toutes,
        'modulesActifs': const [],
        'patients': [
          {'id': 'P1', 'nom': 'AGBO'}
        ]
      });
      await v1.brancherPersistance(p, delai: Duration.zero, fusionnables: fusionnables);
      v1.collection('patients').mettreAJour('P1', {'nom': 'AGBO modifié'});
      await v1.ecrireMaintenant();
      expect(p.contenu.containsKey('modulesActifs'), isFalse, reason: 'aucune écriture de cette collection sur le disque');

      final v2 = Magasin({
        ...{for (final n in ['rbac', 'modulesActifs']) n: Magasin.depuisDossier(['rbac', 'modulesActifs']).collection(n).toutes},
        'patients': [
          {'id': 'P1', 'nom': 'AGBO'}
        ]
      });
      await v2.brancherPersistance(p, fusionnables: fusionnables);
      expect(fermesPour(v2, 'admin'), quatre);
      expect(v2.collection('patients').parId('P1')!['nom'], 'AGBO modifié');
    });

    test('poste neuf (rien sur le disque) : les quatre sont fermées dès le premier lancement', () async {
      final m = Magasin.depuisDossier(['rbac', 'modulesActifs']);
      await m.brancherPersistance(PersistanceMemoire(), fusionnables: fusionnables);
      expect(fermesPour(m, 'admin'), quatre);
    });

    test('une fermeture rouverte (par donnée) puis un redémarrage : la réouverture est GARDÉE, la fusion ne referme rien', () async {
      final p = PersistanceMemoire();
      final v1 = Magasin.depuisDossier(['rbac', 'modulesActifs']);
      await v1.brancherPersistance(p, delai: Duration.zero, fusionnables: fusionnables);
      v1.collection('modulesActifs').mettreAJour('MODP04', {'actif': true, 'rouvertLe': '2026-11-12', 'rouvertPar': 'Direction'});
      await v1.ecrireMaintenant();
      final v2 = Magasin.depuisDossier(['rbac', 'modulesActifs']);
      await v2.brancherPersistance(p, fusionnables: fusionnables);
      expect(v2.jeuxFusionnes, isEmpty, reason: 'le jeu livré est connu : rien à fusionner');
      expect(v2.collection('modulesActifs').parId('MODP04')!['actif'], true);
      expect(fermesPour(v2, 'admin'), quatre.difference({'cfg-sms'}), reason: 'cfg-sms rouvert aux droits ; les trois autres restent fermés');
    });

    test('une fiche de fermeture ARCHIVÉE (corbeille) ne referme rien et n\'est pas rajoutée par la fusion', () async {
      final p = PersistanceMemoire();
      final v1 = jeuDAvant();
      await v1.brancherPersistance(p, delai: Duration.zero, fusionnables: fusionnables);
      v1.collection('modulesActifs').inserer({'id': 'MODP02', 'statut': 'archive', 'module': 'M13', 'ecrans': ['m13-sms-journal'], 'actif': false});
      await v1.ecrireMaintenant();
      final v2 = Magasin.depuisDossier(['rbac', 'modulesActifs']);
      await v2.brancherPersistance(p, fusionnables: fusionnables);
      expect(v2.jeuxFusionnes, {'modulesActifs': nbPropresDuJeu() - 1}, reason: 'la fiche MODP02 est déjà là (archivée) : toutes les autres fiches propres au poste arrivent');
      expect(fermesPour(v2, 'admin'), quatre.difference({'m13-sms-journal'}));
    });
  });

  group('cfg-modules ne propose PAS la réouverture d\'un écran que le poste ne porte pas', () {
    final portes = ecransPortes();

    Future<void> monter(WidgetTester t, {bool Function(String)? ecranPorte}) async {
      t.view.physicalSize = const Size(1600, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      final m = Magasin.depuisDossier(['rbac', 'modulesActifs', 'modulesManifeste', 'audit']);
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: ContexteEcran(
                      ecranId: 'cfg-modules',
                      role: 'admin',
                      droit: const Droit(voir: true, editer: true, annuler: true),
                      magasin: m,
                      aller: (_) {},
                      horloge: () => DateTime(2026, 11, 11, 10),
                      donnees: donnees,
                      ecranPorte: ecranPorte,
                      child: const EcranModules())))));
      await t.pump(const Duration(milliseconds: 300));
    }

    testWidgets('les quatre lignes n\'ont pas de commande de réouverture (absente, pas grisée) et la page dit lesquels et pourquoi', (t) async {
      await monter(t, ecranPorte: portes.containsKey);
      expect(find.byTooltip('Rouvrir cette activité'), findsNWidgets(2), reason: 'seules la banque de sang et la transfusion se rouvrent');
      // Les pages de jeux d'import non portés sont dans le même cas : fermées, sans commande de réouverture (leur jeu n'a pas de widget).
      expect(find.textContaining('que ce poste ne porte pas encore'), findsOneWidget);
      for (final l in ['Calendrier fiscal mensuel', 'Journal des envois SMS', 'Barème de l’AIB', 'Passerelle SMS']) {
        expect(find.textContaining('« $l »'), findsOneWidget, reason: l);
      }
      expect(find.textContaining('Non porté au poste, à porter'), findsAtLeastNWidgets(4), reason: 'le motif de chaque fiche se lit dans le tableau');
    });

    testWidgets('dès qu\'un écran a un widget, sa réouverture est proposée et il quitte la note', (t) async {
      await monter(t, ecranPorte: (id) => id == 'cfg-sms' || portes.containsKey(id));
      expect(find.byTooltip('Rouvrir cette activité'), findsNWidgets(3));
      expect(find.textContaining('« Passerelle SMS »'), findsNothing);
      expect(find.textContaining('« Barème de l’AIB »'), findsOneWidget);
    });

    testWidgets('coque qui ne dit rien (`ecranPorte` absent) : tout est réputé porté, rien ne change pour les écrans de la maquette', (t) async {
      await monter(t);
      expect(find.byTooltip('Rouvrir cette activité'), findsNWidgets((2 + nbPropresDuJeu()).clamp(0, 15)), reason: 'sans coque qui dise ce qui est porté, tout est réputé porté : la banque de sang, la transfusion et chaque fiche propre au poste (une page de quinze lignes)');
      expect(find.textContaining('que ce poste ne porte pas encore'), findsNothing);
    });
  });
}
