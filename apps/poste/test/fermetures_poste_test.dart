import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show Droit, cfbEssentielles, tarCollectionsReferentiel, valCollectionValidations;
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/persistance.dart';
import 'package:sigh_poste/donnees/sms_poste.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/cfg/cfb_modules.dart';
import 'package:sigh_poste/modules/registre.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';

import 'aide_polices.dart';

/// LES QUATRE ÉCRANS NON PORTÉS SONT FERMÉS PAR LE JEU DU POSTE (Direction, 11/11/2026, ECARTS E2422 à E2425) : la fermeture est une fiche de `modulesActifs`
/// (`proprePoste`), l'inventaire des écrans ouverts à chaque rôle est éprouvé à `ecrans_sans_chantier_test.dart`. Ici : ce qui arrive à un poste D'AVANT (magasin
/// déjà posé sur le disque), et ce que l'écran des activités propose pour un écran que le poste ne porte pas.
/// Lots FISC-2 et SMS-R (16/11/2026) : les quatre écrans d'abord fermés (calendrier fiscal, barème de l'AIB, journal et passerelle SMS) sont PORTÉS, le jeu livré ne ferme plus rien.
/// Le MÉCANISME de reprise (une fermeture arrive à un poste d'avant, une réouverture est gardée) reste éprouvé avec une fiche d'ESSAI `MODPX` ajoutée au jeu livré par le test.
const quatre = {'m13-sms-journal'};

/// Les quatre écrans portés, dont les fermetures d'origine sont LEVÉES au démarrage d'un poste déjà installé.
const ecransLeves = {'m12-calendrier-fiscal', 'm13-sms-journal', 'cfg-bareme-aib', 'cfg-sms'};

/// La fiche d'essai : un écran « non porté » fermé par le jeu livré (le jeu réel n'en ferme plus aucun).
const Map<String, Object?> ficheEssai = {
  'id': 'MODPX',
  'code': 'ESSAI',
  'libelle': 'Journal des envois SMS',
  'module': 'M13',
  'ecrans': ['m13-sms-journal'],
  'actif': false,
  'motif': 'Non porté au poste, à porter (fiche d\'essai du test).',
  'fermeLe': '2026-11-11',
  'fermePar': 'Direction',
  'proprePoste': true
};

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

  /// Le jeu livré d'une version FUTURE du poste qui fermerait encore un écran : le jeu réel plus la fiche d'essai.
  Magasin jeuLivre() {
    final m = Magasin.depuisDossier(['rbac', 'modulesActifs']);
    return Magasin({
      'rbac': m.collection('rbac').toutes,
      'modulesActifs': [...m.collection('modulesActifs').toutes, {...ficheEssai}],
    });
  }

  Set<String> fermesPour(Magasin m, String role) => {
        for (final id in quatre)
          if (!donnees.aChaud(m).matrice.peutVoir(role, id)) id
      };

  Set<String> fermesPour2(Magasin m, String role) => {
        for (final id in ecransLeves)
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
      final v2 = jeuLivre();
      await v2.brancherPersistance(p, fusionnables: fusionnables);
      // Les quatre écrans non portés plus les pages de jeux d'import non portés (lot IMP-C) : une fiche `proprePoste` du jeu livré par écran, comptées du fichier même.
      final nbPropres = nbPropresDuJeu();
      expect(nbPropres, 0, reason: 'plus aucun écran du poste n\'est fermé par le jeu livré (calendrier fiscal et barème de l\'AIB : lot FISC-2 ; écrans SMS : lot SMS-R ; jeux d\'import : lot TFIN-2)');
      expect(v2.jeuxFusionnes, {'modulesActifs': 1}, reason: 'la fiche d\'essai (propre au poste) arrive, rien d\'autre');
      final col = v2.collection('modulesActifs');
      expect(col.parId('MODPX')!['actif'], false);
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
        ...{for (final n in ['rbac', 'modulesActifs']) n: jeuLivre().collection(n).toutes},
        'patients': [
          {'id': 'P1', 'nom': 'AGBO'}
        ]
      });
      await v2.brancherPersistance(p, fusionnables: fusionnables);
      expect(fermesPour(v2, 'admin'), quatre);
      expect(v2.collection('patients').parId('P1')!['nom'], 'AGBO modifié');
    });

    test('poste neuf (rien sur le disque) : les quatre sont fermées dès le premier lancement', () async {
      final m = jeuLivre();
      await m.brancherPersistance(PersistanceMemoire(), fusionnables: fusionnables);
      expect(fermesPour(m, 'admin'), quatre);
    });

    test('une fermeture rouverte (par donnée) puis un redémarrage : la réouverture est GARDÉE, la fusion ne referme rien', () async {
      final p = PersistanceMemoire();
      final v1 = jeuLivre();
      await v1.brancherPersistance(p, delai: Duration.zero, fusionnables: fusionnables);
      v1.collection('modulesActifs').mettreAJour('MODPX', {'actif': true, 'rouvertLe': '2026-11-12', 'rouvertPar': 'Direction'});
      await v1.ecrireMaintenant();
      final v2 = jeuLivre();
      await v2.brancherPersistance(p, fusionnables: fusionnables);
      expect(v2.jeuxFusionnes, isEmpty, reason: 'le jeu livré est connu : rien à fusionner');
      expect(v2.collection('modulesActifs').parId('MODPX')!['actif'], true);
      expect(fermesPour(v2, 'admin'), isEmpty, reason: 'l\'écran d\'essai rouvert aux droits');
    });

    test('une fiche de fermeture ARCHIVÉE (corbeille) ne referme rien et n\'est pas rajoutée par la fusion', () async {
      final p = PersistanceMemoire();
      final v1 = jeuDAvant();
      await v1.brancherPersistance(p, delai: Duration.zero, fusionnables: fusionnables);
      v1.collection('modulesActifs').inserer({'id': 'MODPX', 'statut': 'archive', 'module': 'M13', 'ecrans': ['m13-sms-journal'], 'actif': false});
      await v1.ecrireMaintenant();
      final v2 = jeuLivre();
      await v2.brancherPersistance(p, fusionnables: fusionnables);
      expect(v2.jeuxFusionnes['modulesActifs'] ?? 0, 0, reason: 'la fiche MODPX est déjà là (archivée) : aucune autre fiche propre au poste n\'arrive');
      expect(fermesPour(v2, 'admin'), isEmpty);
    });
  });

  group('lots FISC-2 et SMS-R : un poste déjà installé rouvre les quatre écrans portés au démarrage, une fois', () {
    Magasin posteInstalle({String fermeLe = '2026-11-11'}) {
      final m = Magasin.depuisDossier(['rbac', 'modulesActifs']);
      for (final (id, mod, ecran) in [('MODP01', 'M12', 'm12-calendrier-fiscal'), ('MODP02', 'M13', 'm13-sms-journal'), ('MODP03', 'CFG', 'cfg-bareme-aib'), ('MODP04', 'CFG', 'cfg-sms')]) {
        m.collection('modulesActifs').inserer({'id': id, 'module': mod, 'ecrans': [ecran], 'actif': false, 'proprePoste': true, 'fermeLe': fermeLe, 'fermePar': 'Direction'});
      }
      return m;
    }

    test('les fiches fermées d\'origine sont rouvertes ; tous les rôles voient alors les écrans que leur matrice leur donne', () {
      final m = posteInstalle();
      expect(fermesPour2(m, 'admin'), ecransLeves, reason: 'avant : fermés');
      expect(reouvrirFermeturesLevees(m), ['MODP01', 'MODP02', 'MODP03', 'MODP04']);
      expect(fermesPour2(m, 'admin'), isEmpty);
      expect(m.collection('modulesActifs').parId('MODP04')!['rouvertPar'], 'Lots FISC-2 et SMS-R (écran porté au poste)');
      expect(reouvrirFermeturesLevees(m), isEmpty, reason: 'idempotent : une fois');
    });

    test('une fermeture refaite depuis par un agent (autre date) est GARDÉE', () {
      final m = posteInstalle(fermeLe: '2026-11-20');
      expect(reouvrirFermeturesLevees(m), isEmpty);
      expect(fermesPour2(m, 'admin'), ecransLeves);
    });

    test('un poste neuf (jeu livré sans ces fermetures) : rien à rouvrir', () {
      final m = Magasin.depuisDossier(['rbac', 'modulesActifs']);
      expect(reouvrirFermeturesLevees(m), isEmpty);
      expect(fermesPour2(m, 'admin'), isEmpty);
    });
  });

  group('cfg-modules ne propose PAS la réouverture d\'un écran que le poste ne porte pas', () {
    final portes = ecransPortes();
    // Le jeu réel ne ferme plus aucun écran : deux fiches d'ESSAI (journal et passerelle SMS) rejouent le cas d'un écran que le poste ne porte pas.
    bool nonPortesEssai(String id) => id != 'm13-sms-journal' && id != 'cfg-sms' && portes.containsKey(id);

    Future<void> monter(WidgetTester t, {bool Function(String)? ecranPorte, bool avecEssai = false}) async {
      t.view.physicalSize = const Size(1600, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      final m = Magasin.depuisDossier(['rbac', 'modulesActifs', 'modulesManifeste', 'audit']);
      if (avecEssai) {
        m.collection('modulesActifs').inserer({...ficheEssai});
        m.collection('modulesActifs').inserer({...ficheEssai, 'id': 'MODPY', 'code': 'ESSAI2', 'libelle': 'Passerelle SMS', 'module': 'CFG', 'ecrans': ['cfg-sms']});
      }
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

    testWidgets('les deux lignes (écrans SMS) n\'ont pas de commande de réouverture (absente, pas grisée) et la page dit lesquels et pourquoi', (t) async {
      await monter(t, ecranPorte: nonPortesEssai, avecEssai: true);
      expect(find.byTooltip('Rouvrir cette activité'), findsNWidgets(2), reason: 'seules la banque de sang et la transfusion se rouvrent');
      // Les pages de jeux d'import non portés sont dans le même cas : fermées, sans commande de réouverture (leur jeu n'a pas de widget).
      expect(find.textContaining('que ce poste ne porte pas encore'), findsOneWidget);
      for (final l in ['Journal des envois SMS', 'Passerelle SMS']) {
        expect(find.textContaining('« $l »'), findsOneWidget, reason: l);
      }
      expect(find.textContaining('Non porté au poste, à porter'), findsAtLeastNWidgets(2), reason: 'le motif de chaque fiche se lit dans le tableau');
    });

    testWidgets('dès qu\'un écran a un widget, sa réouverture est proposée et il quitte la note', (t) async {
      await monter(t, ecranPorte: (id) => id == 'cfg-sms' || nonPortesEssai(id), avecEssai: true);
      expect(find.byTooltip('Rouvrir cette activité'), findsNWidgets(3));
      expect(find.textContaining('« Passerelle SMS »'), findsNothing);
      expect(find.textContaining('« Journal des envois SMS »'), findsOneWidget);
    });

    testWidgets('coque qui ne dit rien (`ecranPorte` absent) : tout est réputé porté, rien ne change pour les écrans de la maquette', (t) async {
      await monter(t);
      expect(find.byTooltip('Rouvrir cette activité'), findsNWidgets((2 + nbPropresDuJeu()).clamp(0, 15)), reason: 'sans coque qui dise ce qui est porté, tout est réputé porté : la banque de sang, la transfusion et chaque fiche propre au poste (une page de quinze lignes)');
      expect(find.textContaining('que ce poste ne porte pas encore'), findsNothing);
    });
  });
}
