import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/core/controleur_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/mere/activation.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/modules/registre.dart';

import 'aide_polices.dart';
import 'activation_test.dart' show FauxService;
import 'parite/extracteur.dart';

/// MESURE DE PARITÉ N1 (contenu) de chaque écran PORTÉ contre la fiche extraite de la maquette
/// (`docs/architecture/ecrans/<id>.json`, engendrée par `node build/extraire-ecrans.js`).
///
/// Deux obligations :
///  1. un écran déclaré « porté » ou « recetté » dans `docs/architecture/parite-statuts.json` DOIT être à 100 % ;
///  2. le rapport de TOUS les écrans présents dans `ecransPortes()` est écrit (`docs/architecture/rapport-parite-flutter.json`).
/// Un statut ne se déclare donc jamais « à l'œil » : il se MESURE.
void main() {
  setUpAll(chargerPolices);
  final donnees = DonneesNavigation.depuisDossier();
  final statuts =
      File('../../docs/architecture/parite-statuts.json').existsSync()
          ? (jsonDecode(File('../../docs/architecture/parite-statuts.json')
                  .readAsStringSync()) as Map)
              .cast<String, Object?>()
          : <String, Object?>{};

  Map<String, Object?>? fiche(String id) {
    final f = File('../../docs/architecture/ecrans/$id.json');
    return f.existsSync()
        ? (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>()
        : null;
  }

  final magasin = Magasin.depuisDossier(Magasin.collectionsDuJeu);
  // Le jeu de la maquette n'a aucune prescription en file (elles naissent d'une consultation) : on en pose deux pour que la file se DESSINE
  // et que sa parité soit mesurée sur une file réelle, pas sur son état vide.
  final f0 = magasin.collection('factures').actives.first;
  magasin.collection('taches').inserer({
    'id': 'T1',
    'type': 'encaissement',
    'statut': 'en_attente',
    'factureId': f0['id'],
    'reference': 'ORD-1',
    'patient': f0['patient'],
    'patientCode': f0['patientCode'],
    'detail': 'Encaisser',
    'montant': 1000,
    'date': '2026-08-16'
  });
  magasin.collection('taches').inserer({
    'id': 'T2',
    'type': 'dispensation',
    'statut': 'bloque',
    'factureId': f0['id'],
    'reference': 'ORD-1',
    'patient': f0['patient'],
    'patientCode': f0['patientCode'],
    'detail': 'Délivrer',
    'montant': 1000,
    'date': '2026-08-16'
  });

  // m6-pharmacie-interne / -externe : le jeu n'a aucune ordonnance (la maquette ne les sème qu'à l'ouverture de M2) ; une ordonnance réglée à deux lignes
  // (une par voie) fait DESSINER le tableau des deux pharmacies, dont les en-têtes n'existent pas à l'état vide.
  final pharma = magasin.collection('produits').actives.first;
  magasin.collection('ordonnances').inserer({
    'id': 'ORD-PARITE',
    'numero': 'ORD-PARITE',
    'date': '2026-08-16',
    'patient': 'TEST Parité',
    'patientCode': 'CNT/1/26',
    'statutPaiement': 'soldee',
    'statutDispensation': 'en_attente',
    'medicaments': [
      {'produitId': pharma['id'], 'produit': pharma['designation'], 'quantite': 1, 'posologie': '1/j', 'voie': 'orale'},
      {'produitId': pharma['id'], 'produit': pharma['designation'], 'quantite': 1, 'posologie': '1/j', 'voie': 'parenterale'},
    ],
  });

  // ACTIVITÉS FERMÉES (modulesActifs, E203) : la coque ne sert pas un écran dont l'activité est fermée, pour aucun rôle (elle affiche « Activité
  // fermée » avec le motif). Les fiches de la maquette de ces écrans sont extraites ACTIVITÉ ROUVERTE : leur N1 se mesure donc sur le même état,
  // fiche de fermeture archivée (RG-14) le temps de la mesure, puis restaurée. Paramètres additifs de `mesurer` : `activiteRouverte` (rouvre l'activité
  // de l'écran) et `fixture` (collections posées le temps de la mesure : la maquette amorce poches et donneurs À L'OUVERTURE de l'écran, le jeu du poste
  // n'en porte pas, et les en-têtes d'un tableau vide ne se dessinent pas ; ce sont les jeux des vecteurs de la maquette, ceux de `m5_sang_test`).
  final fermes = <String>{
    for (final f in magasin.collection('modulesActifs').actives)
      for (final e in ((f['ecrans'] as List?) ?? const [])) '$e'
  };
  final vecteursSang = (jsonDecode(File('../../packages/domaine/test/vecteurs/sang.json').readAsStringSync()) as Map).cast<String, Object?>();
  List<Map<String, Object?>> lignes(Object? v) => [for (final x in (v as List)) (x as Map).cast<String, Object?>()];
  final fixtures = <String, Map<String, List<Map<String, Object?>>>>{
    'm5-banque-sang': {'poches': lignes((vecteursSang['banque'] as Map)['poches'])},
    'm5-donneurs': {'donneurs': lignes((vecteursSang['donneurs'] as Map)['donneurs'])},
  };
  // Les écrans du module RLS lisent le relais PAR LA MÈRE (`/admin/etat`, `/admin/supervision`) : sans appareil, la commande « Révoquer » (une par ligne
  // d'appareil non révoqué) ne se dessine pas, et ses en-têtes de tableau non plus. Une mère qui répond avec un appareil actif, un appareil bloqué et un
  // contrôle de liaison fait DESSINER ces écrans comme le panneau de la maquette.
  final reponsesMere = <String, Object?>{
    '/admin/etat': {
      'epoch': 1,
      'seq_max': 120,
      'rep_seq': 118,
      'rep_n': 118,
      'appareils': [
        {'uuid': 'u-01', 'etiquette': 'Poste Caisse principale', 'role': 'fileul', 'etat': 'actif', 'dernier_contact': 1782000000000, 'dernier_seq': 120, 'derive_ms': 0},
        {'uuid': 'u-07', 'etiquette': 'Mobile Sage-femme de garde', 'role': 'mobile', 'etat': 'actif', 'dernier_contact': 1782000000000, 'dernier_seq': 100, 'derive_ms': 0},
      ],
      'bloques': ['u-07'],
      'derives': [],
      'alertes': [
        {'quand': 1782000000000, 'type': 'trou', 'appareil': 'u-07'}
      ],
      'conflits_ouverts': 0,
      'reinit_ouverte': false,
    },
    '/admin/supervision': {
      'etat': 'ok',
      'depot': 'sqlite',
      'controles': [
        {'nom': 'Relais en ligne', 'etat': 'ok', 'detail': 'dernier échange réussi'}
      ],
    },
    '/admin/compte': {'n': 42},
    '/admin/journal': {
      'liste': [
        {'quand': 1782000000000, 'niveau': 'info', 'source': 'relais', 'message': 'Appareil révoqué : u-09'}
      ]
    },
  };
  Future<Parite?> mesurer(WidgetTester t, String id, String role,
      {bool activiteRouverte = false, Map<String, List<Map<String, Object?>>> fixture = const {}}) async {
    final f = fiche(id);
    if (f == null || f['acces'] != 'ouvert') return null;
    // Les neuf écrans AUTONOMES (sans coque) ont leur propre mesure, qui les monte comme la coque le fait (session, jeton, placeholders et étiquettes
    // lus) : `parite_autonomes_test.dart`, contre des fiches extraites de leurs pages réelles (`build/extraire-autonomes.js`).
    if (f['autonome'] == true) return null;
    // `remplacerContenu` ne journalise pas : la mesure ne laisse aucune trace dans le journal d'audit que d'autres écrans affichent.
    final colModules = magasin.collection('modulesActifs');
    final avant = [for (final fm in colModules.toutes) {...fm}];
    if (activiteRouverte) {
      colModules.remplacerContenu([
        for (final fm in avant)
          ((fm['ecrans'] as List?) ?? const []).contains(id) ? {...fm, 'statut': 'archive'} : fm
      ]);
    }
    final avantFixture = {
      for (final k in fixture.keys) k: [for (final fm in magasin.collection(k).toutes) {...fm}]
    };
    fixture.forEach((k, v) => magasin.collection(k).remplacerContenu(v));

    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    final client = ClientMere(
        base: Uri.parse('http://x'),
        secretAdmin: 's',
        client: MockClient((r) async =>
            id.startsWith('rls-') && reponsesMere.containsKey(r.url.path) ? http.Response(jsonEncode(reponsesMere[r.url.path]), 200) : http.Response('[]', 200)));
    final act = ActivationMere(
        stockage: StockageMemoire(),
        service: FauxService(),
        relaisPour: (_, __) => throw StateError('hors sujet'));
    final ctl = ControleurPoste(
        activation: act,
        config: ConfigPoste(
            mode: id.startsWith('mere-') || id.startsWith('rls-') ? ModePoste.mere : ModePoste.fileul,
            role: role,
            nomPoste: 'Test'));
    await t.pumpWidget(SighPoste(
        donnees: donnees,
        controleur: ctl,
        client: client,
        ecranInitial: id,
        // Les fiches de la maquette ont été extraites le 30/10/2026 à 10 h : certains libellés (durées de séjour du plan des lits) en dépendent.
        horloge: () => DateTime(2026, 10, 30, 10),
        magasin: magasin));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    // GARDE (1er novembre 2026) : un écran déclaré porté doit être RENDU, pas la coque « Écran de la maquette à convertir ». Le test acceptait un
    // statut « porté » pour un identifiant absent de `ecransPortes` : la Direction a ouvert 22 pages d'accueil de module qui disaient « non commencé ».
    expect(find.byKey(const Key('ecran-a-porter')), findsNothing,
        reason: '$id affiche la coque EcranAPorter : il est dans ecransPortes mais ne se rend pas');
    final mesure = comparerContenu(id, f, textesVisibles(t));
    // L'activité est refermée aussitôt : les écrans mesurés ensuite retrouvent le jeu tel qu'il est.
    if (activiteRouverte) colModules.remplacerContenu(avant);
    avantFixture.forEach((k, v) => magasin.collection(k).remplacerContenu(v));
    return mesure;
  }

  // Écrans de la CIBLE sans équivalent à la maquette (assistant de première installation, récupération administrateur) : hors manifeste, donc hors de la
  // parité N1 ; ils sont couverts par `installation_ecrans_test.dart`. Le test ci-dessous vérifie qu'ils sont bien absents du manifeste.
  const ecransDeLaCible = {'ins-premiere', 'ins-rejoindre', 'auth-secours'};

  final portes = ecransPortes(
          controleur: ControleurPoste(
              activation: ActivationMere(
                  stockage: StockageMemoire(),
                  service: FauxService(),
                  relaisPour: (_, __) => throw StateError('x')),
              config: const ConfigPoste(mode: ModePoste.fileul)),
          client: ClientMere(base: Uri.parse('http://x'), secretAdmin: 's'))
      .keys
      .where((id) => !ecransDeLaCible.contains(id))
      .toList()
    ..sort();

  // INVENTAIRE HONNÊTE : un statut « porté » ou « recetté » n'est valable que si l'identifiant est dans `ecransPortes` (un widget Flutter existe) ET
  // si l'écran est mesuré ci-dessous (fiche N1) ou mesuré à part (écran autonome, `parite_autonomes_test.dart`). Dans l'autre sens, un écran de
  // `ecransPortes` doit être déclaré : un statut en retard fait mentir `PARITE-MAQUETTE.md`.
  test('statuts déclarés et ecransPortes disent la même chose', () {
    final manifeste = {for (final e in donnees.manifeste.tousLesEcrans) e.id};
    expect(manifeste.intersection(ecransDeLaCible), isEmpty, reason: 'un écran de la cible ne figure pas au manifeste de la maquette');
    final declares = {
      for (final e in statuts.entries)
        if (e.value == 'porté' || e.value == 'recetté') e.key
    };
    final absents = declares.where((id) => !portes.contains(id)).toList()..sort();
    expect(absents, isEmpty, reason: 'déclarés porté ou recetté mais absents de ecransPortes (aucun widget Flutter) : $absents');
    final nonDeclares = portes.where((id) => !declares.contains(id)).toList()..sort();
    expect(nonDeclares, isEmpty, reason: 'présents dans ecransPortes mais non déclarés portés dans parite-statuts.json : $nonDeclares');
    final inconnus = statuts.keys.where((id) => !manifeste.contains(id)).toList()..sort();
    expect(inconnus, isEmpty, reason: 'statuts d’identifiants absents du manifeste : $inconnus');
    // Tout écran du manifeste (hubs compris) a un statut explicite.
    final sansStatut = manifeste.where((id) => !statuts.containsKey(id)).toList()..sort();
    expect(sansStatut, isEmpty, reason: 'écrans du manifeste sans statut : $sansStatut');
    // Un écran déclaré est mesuré : il a une fiche de la maquette (N1), ou c'est un écran autonome mesuré à part.
    final sansMesure = declares.where((id) {
      final f = fiche(id);
      return f == null || (f['acces'] != 'ouvert') && f['autonome'] != true;
    }).toList()..sort();
    expect(sansMesure, isEmpty, reason: 'déclarés portés mais sans fiche mesurable : $sansMesure');
  });

  testWidgets(
      'rapport de parité N1 des écrans portés + garde des statuts déclarés',
      (t) async {
    final rapport = <Map<String, Object?>>[];
    for (final id in portes) {
      final p = await mesurer(t, id, 'admin', activiteRouverte: fermes.contains(id), fixture: fixtures[id] ?? const {});
      if (p == null) {
        rapport.add({
          'id': id,
          'mesure': false,
          'raison': 'aucune fiche de la maquette (lancer extraire-ecrans.js), ou écran autonome mesuré à part (parite_autonomes_test.dart)'
        });
        continue;
      }
      rapport.add({
        'id': id,
        'mesure': true,
        'attendus': p.attendus,
        'presents': p.presents,
        'taux': double.parse(p.taux.toStringAsFixed(3)),
        'manquants': p.manquants
      });
      final declare = '${statuts[id] ?? 'non commencé'}';
      if (declare == 'porté' || declare == 'recetté') {
        expect(p.manquants, isEmpty,
            reason:
                '$id est déclaré « $declare » mais il manque : ${p.manquants}');
      }
    }
    File('../../docs/architecture/rapport-parite-flutter.json')
        .writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
      '_doc':
          'ENGENDRÉ par apps/poste/test/parite_ecrans_test.dart — ne pas éditer. Parité N1 (contenu) des écrans Flutter portés contre la maquette.',
      'ecrans_du_manifeste':
          donnees.manifeste.tousLesEcrans.where((e) => !e.hub).length,
      'ecrans_portes': portes.length,
      'ecrans': rapport,
    }));
  });
}
