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

  Future<Parite?> mesurer(WidgetTester t, String id, String role) async {
    final f = fiche(id);
    if (f == null || f['acces'] != 'ouvert') return null;
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    final client = ClientMere(
        base: Uri.parse('http://x'),
        secretAdmin: 's',
        client: MockClient((r) async => http.Response('[]', 200)));
    final act = ActivationMere(
        stockage: StockageMemoire(),
        service: FauxService(),
        relaisPour: (_, __) => throw StateError('hors sujet'));
    final ctl = ControleurPoste(
        activation: act,
        config: ConfigPoste(
            mode: id.startsWith('mere-') ? ModePoste.mere : ModePoste.fileul,
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
    return comparerContenu(id, f, textesVisibles(t));
  }

  final portes = ecransPortes(
          controleur: ControleurPoste(
              activation: ActivationMere(
                  stockage: StockageMemoire(),
                  service: FauxService(),
                  relaisPour: (_, __) => throw StateError('x')),
              config: const ConfigPoste(mode: ModePoste.fileul)),
          client: ClientMere(base: Uri.parse('http://x'), secretAdmin: 's'))
      .keys
      .toList()
    ..sort();

  testWidgets(
      'rapport de parité N1 des écrans portés + garde des statuts déclarés',
      (t) async {
    final rapport = <Map<String, Object?>>[];
    for (final id in portes) {
      final p = await mesurer(t, id, 'admin');
      if (p == null) {
        rapport.add({
          'id': id,
          'mesure': false,
          'raison': 'aucune fiche de la maquette (lancer extraire-ecrans.js)'
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
