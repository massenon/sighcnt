import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/controleur_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/mere/activation.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/modules/registre.dart';
import 'package:sigh_poste/shell/coque.dart';
import 'package:sigh_poste/shell/ecran_hub.dart';
import 'package:sigh_poste/shell/menus_barre.dart' show actionsRapidesDuRole;
import 'package:sigh_poste/shell/recherche_globale.dart' show ecranOuvertAuRole, rechercheGlobale;

import 'activation_test.dart' show FauxService;
import 'aide_polices.dart';

/// PLUS AUCUN ÉCRAN DE CHANTIER (Direction, 01/11/2026, point 5).
///
/// Le gabarit « Écran de la maquette à convertir » (`EcranAPorter`) n'est plus qu'un filet : il ne doit JAMAIS apparaître à un agent. Le garde :
///  1. pour CHAQUE rôle non archivé et CHAQUE mode (fileul, mère), tout écran que le profil peut ouvrir (ruban, pages d'accueil de module, accueil du rôle,
///     écrans hors ruban atteignables par la recherche) a un widget dans `ecransPortes`, construit comme `SighPoste` le construit (le client de la mère
///     n'existe qu'en mode mère, le contrôleur du poste toujours) ;
///  2. aucun texte « à convertir », « à venir » ou « non commencé » ne reste dans `lib/` comme gabarit d'écran ;
///  3. rendus de bout en bout : les écrans qui dépendent du mode (les réglages du poste, le domaine Poste mère) se dessinent sans le gabarit de chantier.
///
/// LES QUATRE ÉCRANS NON PORTÉS SONT FERMÉS (Direction, 11/11/2026, ECARTS E2422) : par une fermeture d'activité du JEU du poste (collection `modulesActifs`, une fiche
/// `proprePoste` par écran), pour tous les rôles, administrateur compris, jamais par un nom de rôle. L'inventaire se mesure donc sur les droits À CHAUD (matrice
/// engendrée superposée aux fiches du jeu, comme la coque) et ne dispense PLUS ces écrans : s'ils redevenaient ouvrables sans être portés, il échoue ; et la
/// liste des fermetures du jeu doit être exactement la liste nommée, de sorte qu'on ne retire pas la fermeture sans porter l'écran, ni ne porte l'écran sans
/// retirer la fermeture.
void main() {
  setUpAll(chargerPolices);
  final donnees = DonneesNavigation.depuisDossier();
  final roles = [
    for (final r in donnees.matrice.rolesBruts)
      if (r['archive'] != true) '${r['id']}'
  ];

  ControleurPoste controleur(ModePoste mode) => ControleurPoste(
      activation: ActivationMere(stockage: StockageMemoire(), service: FauxService(), relaisPour: (_, __) => throw StateError('hors sujet')),
      config: ConfigPoste(mode: mode, nomPoste: 'Test'));

  Set<String> portes(ModePoste mode) => ecransPortes(
          controleur: controleur(mode),
          client: mode == ModePoste.mere ? ClientMere(base: Uri.parse('http://x'), secretAdmin: 's') : null)
      .keys
      .toSet();

  // Écrans de la maquette ENTRÉS AU MANIFESTE avant d'être portés (lots A5 et SMS, régénération du 11/11/2026, ECARTS E2380) : le poste n'a pas encore leur widget. Liste
  // NOMMÉE et fermée, jamais « tout écran non porté » : tout autre écran manquant fait échouer l'inventaire. Chaque entrée doit être déclarée « non commencé » à
  // `parite-statuts.json` et rester absente de `ecransPortes` : dès qu'un écran est porté, il sort de cette liste (le test l'y oblige).
  // Lot IMP-C : s'y ajoutent les PAGES DE JEU d'import que le poste ne porte pas encore (leur jeu n'est pas au registre `jeuxImport`) ; porter un jeu retire sa page d'ici, de
  // `gen-poste-jeu.js` (`JEUX_IMPORT_NON_PORTES`) et de `parite-statuts.json`.
  const impNonPortes = {
    'imp-tarifs-produits', 'imp-produits-referentiel',
    'imp-immobilisations', 'imp-budgets', 'imp-courriers',
  };
  const nonPortesNommes = {'m12-calendrier-fiscal', 'm13-sms-journal', 'cfg-bareme-aib', 'cfg-sms', ...impNonPortes};

  // Les droits EN FORCE au poste : la matrice engendrée superposée aux fiches `rbac` et `modulesActifs` du jeu livré (la coque fait ce calcul à chaque écriture).
  final magasinDuJeu = Magasin.depuisDossier(['rbac', 'modulesActifs']);
  final chaud = donnees.aChaud(magasinDuJeu);
  List<Map<String, Object?>> fichesDuJeu() => [
        for (final f in (jsonDecode(File('assets/donnees/jeu/modulesActifs.json').readAsStringSync()) as List)) (f as Map).cast<String, Object?>()
      ];

  test('l\'inventaire des rôles n\'est pas vide', () => expect(roles.length, greaterThan(10)));

  test('la liste des écrans non portés est nommée, déclarée « non commencé » et réellement absente de ecransPortes', () {
    final statuts = (jsonDecode(File('../../docs/architecture/parite-statuts.json').readAsStringSync()) as Map).cast<String, Object?>();
    final p = portes(ModePoste.mere);
    for (final id in nonPortesNommes) {
      expect(donnees.manifeste.ecran(id), isNotNull, reason: '$id n\'est plus au manifeste : le retirer de la liste');
      expect(p.contains(id), isFalse, reason: '$id est porté : le retirer de la liste des écrans non portés');
      expect(statuts[id], 'non commencé', reason: '$id doit être déclaré « non commencé » à parite-statuts.json');
    }
  });

  test('FERMETURE : le jeu du poste ferme exactement la liste nommée, une fiche par écran, avec un motif et une date', () {
    final propres = [for (final f in fichesDuJeu()) if (f['proprePoste'] == true) f];
    final ecransFermes = [for (final f in propres) ...(f['ecrans'] as List).map((e) => '$e')];
    expect(ecransFermes.toSet(), nonPortesNommes, reason: 'la liste des fermetures du jeu doit être la liste nommée : porter un écran retire les DEUX');
    expect(ecransFermes.length, nonPortesNommes.length, reason: 'une fiche par écran, jamais deux');
    for (final f in propres) {
      final ecrans = (f['ecrans'] as List);
      expect(ecrans.length, 1, reason: '${f['id']} ferme un seul écran');
      expect(f['actif'], false, reason: '${f['id']} doit être fermée');
      expect(f['statut'], isNot('archive'), reason: 'une fiche archivée ne ferme plus rien (RG-14)');
      final jeuImport = impNonPortes.contains('${ecrans.single}');
      expect('${f['motif']}', jeuImport ? contains('Jeu d’import non porté au poste (lot IMP-C), à porter') : allOf(contains('Non porté au poste, à porter'), contains('11/11/2026')),
          reason: '${f['id']} : motif écrit et daté');
      expect(f['fermeLe'], jeuImport ? '2026-11-12' : '2026-11-11');
      expect('${f['fermePar']}', isNotEmpty, reason: 'RG-12 : une fermeture a un auteur');
      expect(f['module'], donnees.manifeste.ecran('${ecrans.single}')!.module, reason: 'le module de la fiche est celui de l\'écran');
    }
    // La maquette ne les ferme pas : la RÉFÉRENCE de la matrice engendrée n'en connaît aucune.
    expect([for (final f in donnees.referenceModules!) if (f['proprePoste'] == true) f['id']], isEmpty);
    // Le jeu sobre (fixture des vecteurs de la maquette) n'en porte aucune.
    final sobre = (jsonDecode(File('test/fixtures/jeu_sobre/modulesActifs.json').readAsStringSync()) as List).cast<Map>();
    expect(sobre.where((f) => f['proprePoste'] == true), isEmpty);
  });

  test('SONDE : sans la fermeture, les quatre écrans seraient ouvrables à des rôles (la fermeture est bien ce qui les masque)', () {
    final ouvertsSansFermeture = [
      for (final id in nonPortesNommes)
        if (roles.any((r) => ecranOuvertAuRole(donnees, r, id))) id
    ];
    expect(ouvertsSansFermeture.toSet(), nonPortesNommes, reason: 'la matrice engendrée seule les ouvre : le garde ne vaut que si la fermeture agit');
  });

  test('ABSENTS de tout : ruban, accueil, cartes de hub, actions rapides et recherche globale, pour chaque rôle et chaque mode', () {
    final libelles = [for (final id in nonPortesNommes) donnees.manifeste.ecran(id)!.label];
    final fautes = <String>[];
    for (final role in roles) {
      for (final estMere in [false, true]) {
        final ruban = chaud.manifeste.ruban(chaud.matrice, role, estMere: estMere);
        for (final d in ruban) {
          for (final r in d.rangees) {
            for (final e in r.ecrans) {
              if (nonPortesNommes.contains(e.id)) fautes.add('ruban ${e.id} ($role, mère $estMere)');
            }
          }
        }
        final accueil = chaud.matrice.accueil(role);
        if (accueil != null && nonPortesNommes.contains(accueil)) fautes.add('accueil $accueil ($role)');
      }
      for (final id in nonPortesNommes) {
        if (ecranOuvertAuRole(chaud, role, id)) fautes.add('ouvert $id ($role)');
        if (chaud.matrice.peutVoir(role, id)) fautes.add('peutVoir $id ($role)');
      }
      for (final h in hubsDuManifeste) {
        final entree = chaud.manifeste.ecran(h);
        final mod = entree == null ? null : ModuleHub.depuis(chaud.manifeste, entree.module);
        if (mod == null) continue;
        for (final c in cartesDuHub(mod, chaud, (id) => ecranOuvertAuRole(chaud, role, id))) {
          if (nonPortesNommes.contains(c.id)) fautes.add('carte ${c.id} dans $h ($role)');
        }
      }
      for (final a in actionsRapidesDuRole(chaud, role)) {
        if (nonPortesNommes.contains(a.ecran)) fautes.add('action rapide ${a.ecran} ($role)');
      }
      for (final l in libelles) {
        for (final g in rechercheGlobale(requete: l, role: role, nav: chaud, magasin: magasinDuJeu, aujourdhui: DateTime(2026, 11, 11))) {
          for (final r in g.resultats) {
            if (nonPortesNommes.contains(r.ecran)) fautes.add('recherche « $l » mène à ${r.ecran} ($role)');
          }
        }
      }
    }
    expect(fautes, isEmpty, reason: fautes.join('\n'));
    // Et la sonde de la recherche peut échouer : sans fermeture, l'administrateur trouve au moins l'un des quatre.
    final trouves = {
      for (final l in libelles)
        for (final g in rechercheGlobale(requete: l, role: 'admin', nav: donnees, magasin: magasinDuJeu, aujourdhui: DateTime(2026, 11, 11)))
          for (final r in g.resultats) r.ecran
    };
    expect(trouves.intersection(nonPortesNommes), isNotEmpty, reason: 'la recherche globale doit pouvoir les trouver sans la fermeture');
  });

  for (final mode in [ModePoste.fileul, ModePoste.mere]) {
    test('INVENTAIRE ${mode.name} : tout écran ouvert à un rôle autorisé est porté (aucun gabarit de chantier possible)', () {
      final p = portes(mode);
      final estMere = mode == ModePoste.mere;
      final manques = <String>{};
      for (final role in roles) {
        final ouverts = <String>{
          for (final d in chaud.manifeste.ruban(chaud.matrice, role, estMere: estMere))
            for (final r in d.rangees) ...[r.hub, for (final e in r.ecrans) e.id],
          for (final e in chaud.manifeste.tousLesEcrans)
            if (ecranOuvertAuRole(chaud, role, e.id) && (estMere || !domainesMere.contains(e.domaine))) e.id,
        };
        final accueil = chaud.matrice.accueil(role);
        if (accueil != null && chaud.matrice.peutVoir(role, accueil)) ouverts.add(accueil);
        // AUCUNE dispense : les quatre écrans non portés sont fermés, donc absents de `ouverts`. Si l'un devenait ouvrable sans widget, il manquerait ici.
        for (final id in ouverts) {
          if (!p.contains(id)) manques.add('$id ($role, ${mode.name})');
        }
      }
      expect(manques, isEmpty, reason: 'écrans ouverts à un rôle autorisé mais sans widget (gabarit de chantier) :\n${manques.join('\n')}');
    });
  }

  test('le manifeste entier est porté en mode mère (aucun écran ne reste hors de ecransPortes)', () {
    final p = portes(ModePoste.mere);
    final manques = [for (final e in donnees.manifeste.tousLesEcrans) if (!p.contains(e.id) && !nonPortesNommes.contains(e.id)) e.id]..sort();
    expect(manques, isEmpty, reason: 'écrans du manifeste sans widget : $manques');
  });

  test('SOURCE : aucun texte de chantier (« à convertir », « Écran de la maquette à ») dans lib/', () {
    final fautes = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lignes = f.readAsLinesSync();
      for (var i = 0; i < lignes.length; i++) {
        final t = lignes[i].trimLeft();
        if (t.startsWith('//') || t.startsWith('*')) continue;
        if (lignes[i].contains('à convertir') || lignes[i].contains('Écran de la maquette à')) fautes.add('${f.path}:${i + 1}');
      }
    }
    expect(fautes, isEmpty);
  });

  testWidgets('RENDU : les réglages du poste (fileul) et la console de la mère se dessinent sans le gabarit de chantier', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    for (final (mode, ecran) in [(ModePoste.fileul, 'cfg-poste'), (ModePoste.mere, 'cfg-poste'), (ModePoste.mere, 'mere-supervision'), (ModePoste.fileul, 'hub-m8')]) {
      final ctl = controleur(mode);
      await t.pumpWidget(SighPoste(
          donnees: donnees,
          controleur: ctl,
          client: mode == ModePoste.mere ? ClientMere(base: Uri.parse('http://x'), secretAdmin: 's') : null,
          ecranInitial: ecran,
          horloge: () => DateTime(2026, 10, 30, 10),
          magasin: Magasin.depuisDossier(Magasin.collectionsDuJeu)));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(CoquePoste), findsOneWidget);
      expect(find.byKey(const Key('ecran-a-porter')), findsNothing, reason: '$ecran (${mode.name}) affiche le gabarit de chantier');
    }
  });
  testWidgets('RENDU : ouverts par leur adresse, les quatre écrans non portés disent « Activité fermée » avec leur motif, jamais le gabarit de chantier', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    for (final ecran in nonPortesNommes) {
      final ctl = controleur(ModePoste.mere);
      await t.pumpWidget(SighPoste(
          donnees: donnees,
          controleur: ctl,
          client: ClientMere(base: Uri.parse('http://x'), secretAdmin: 's'),
          ecranInitial: ecran,
          horloge: () => DateTime(2026, 11, 11, 10),
          magasin: Magasin.depuisDossier(Magasin.collectionsDuJeu)));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('ecran-a-porter')), findsNothing, reason: '$ecran affiche le gabarit de chantier');
      expect(find.byKey(const Key('activite-fermee')), findsOneWidget, reason: '$ecran doit dire qu\'il est fermé');
      expect(find.textContaining(impNonPortes.contains(ecran) ? 'Jeu d’import non porté au poste (lot IMP-C), à porter' : 'Non porté au poste, à porter'), findsOneWidget,
          reason: '$ecran : le motif de la fiche');
    }
  });
}
