import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import '../../mere/client_mere.dart';
import 'mra_exploitation.dart';
import 'mra_source.dart';
import 'mra_supervision.dart';
import 'mrb_cle.dart';
import 'mrb_indicateurs.dart';
import 'mrb_integrite.dart';
import 'mrb_journal.dart';
import 'mrb_reinit.dart';
import 'mrb_relais.dart';
import 'mrb_sauvegardes.dart';
import 'mrc_cycle.dart';
import 'mrc_exploitation.dart';
import 'mrc_plateforme.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans du module MERE (domaine « Poste mère »). Lot (a) : supervision, appareils, conflits, « À traiter », journal des opérations, plages et
/// baux, lots de tournée (sans client, ils se dessinent en « non disponible »). Lot (b) : journal technique, sauvegardes, clé de clinique, intégrité,
/// réinitialisation, relais, indicateurs (ils lisent le service par `mrbClientMere`, posé par `ecransPortes`).
final Map<String, ConstruireEcran> ecransMERE = {
  'mere-supervision': (c, cfg) => const EcranMraSupervision(),
  'mere-appareils': (c, cfg) => const EcranMraAppareils(),
  'mere-conflits': (c, cfg) => const EcranMraConflits(),
  'mere-a-traiter': (c, cfg) => const EcranMraATraiter(),
  'mere-journal-operations': (c, cfg) => const EcranMraJournalOperations(),
  'mere-plages-baux': (c, cfg) => const EcranMraPlagesBaux(),
  'mere-lots-tournee': (c, cfg) => const EcranMraLotsTournee(),
  'mere-journal-technique': (c, cfg) => const EcranJournalTechnique(),
  'mere-sauvegardes': (c, cfg) => const EcranSauvegardesMere(),
  'mere-cle-clinique': (c, cfg) => const EcranCleClinique(),
  'mere-integrite': (c, cfg) => const EcranIntegrite(),
  'mere-reinit': (c, cfg) => const EcranReinitialisation(),
  'mere-relais': (c, cfg) => const EcranRelais(),
  'mere-indicateurs': (c, cfg) => const EcranIndicateursPublies(),
  'mere-service': (c, cfg) => EcranMereService(config: cfg),
  'mere-base': (c, cfg) => const EcranMereBase(),
  'mere-reseau': (c, cfg) => const EcranMereReseau(),
  'mere-planificateur': (c, cfg) => const EcranMerePlanificateur(),
  'mere-notifications': (c, cfg) => const EcranMereNotifications(),
  'mere-mise-en-service': (c, cfg) => EcranMereMiseEnService(config: cfg),
  'mere-mises-a-jour': (c, cfg) => const EcranMereMisesAJour(),
  'mere-import': (c, cfg) => const EcranMereImport(),
};

/// Les écrans du lot (a) branchés sur le service de la mère : c'est CETTE table que `ecransPortes` sert quand le poste est mère, avec ceux du lot (b).
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
  'mere-journal-technique': (c, cfg) => const EcranJournalTechnique(),
  'mere-sauvegardes': (c, cfg) => const EcranSauvegardesMere(),
  'mere-cle-clinique': (c, cfg) => const EcranCleClinique(),
  'mere-integrite': (c, cfg) => const EcranIntegrite(),
  'mere-reinit': (c, cfg) => const EcranReinitialisation(),
  'mere-relais': (c, cfg) => const EcranRelais(),
  'mere-indicateurs': (c, cfg) => const EcranIndicateursPublies(),
  'mere-service': (c, cfg) => EcranMereService(config: cfg),
  'mere-base': (c, cfg) => const EcranMereBase(),
  'mere-reseau': (c, cfg) => const EcranMereReseau(),
  'mere-planificateur': (c, cfg) => const EcranMerePlanificateur(),
  'mere-notifications': (c, cfg) => const EcranMereNotifications(),
  'mere-mise-en-service': (c, cfg) => EcranMereMiseEnService(config: cfg),
  'mere-mises-a-jour': (c, cfg) => const EcranMereMisesAJour(),
  'mere-import': (c, cfg) => const EcranMereImport(),
  };
}
