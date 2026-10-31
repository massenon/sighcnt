import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import '../../mere/client_mere.dart';
import 'mra_exploitation.dart';
import 'mra_source.dart';
import 'mra_supervision.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans du module MERE (domaine « Poste mère »), partie (a) : supervision, appareils, conflits, « À traiter », journal des opérations,
/// plages et baux, lots de tournée. Sans client, chaque écran lit `FournisseurMra.parDefaut` et se dessine en « non disponible » à défaut.
final Map<String, ConstruireEcran> ecransMERE = {
  'mere-supervision': (c, cfg) => const EcranMraSupervision(),
  'mere-appareils': (c, cfg) => const EcranMraAppareils(),
  'mere-conflits': (c, cfg) => const EcranMraConflits(),
  'mere-a-traiter': (c, cfg) => const EcranMraATraiter(),
  'mere-journal-operations': (c, cfg) => const EcranMraJournalOperations(),
  'mere-plages-baux': (c, cfg) => const EcranMraPlagesBaux(),
  'mere-lots-tournee': (c, cfg) => const EcranMraLotsTournee(),
};

/// Les mêmes écrans branchés sur le service de la mère : c'est CETTE table que `ecransPortes` sert quand le poste est mère.
Map<String, ConstruireEcran> ecransMEREPour(ClientMere client) {
  final source = SourceMraClient(client);
  return {
    'mere-supervision': (c, cfg) => EcranMraSupervision(source: source),
    'mere-appareils': (c, cfg) => EcranMraAppareils(source: source),
    'mere-conflits': (c, cfg) => EcranMraConflits(source: source),
    'mere-a-traiter': (c, cfg) => EcranMraATraiter(source: source),
    'mere-journal-operations': (c, cfg) => EcranMraJournalOperations(source: source),
    'mere-plages-baux': (c, cfg) => EcranMraPlagesBaux(source: source),
    'mere-lots-tournee': (c, cfg) => EcranMraLotsTournee(source: source),
  };
}
