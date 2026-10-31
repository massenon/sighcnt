import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'mrc_cycle.dart';
import 'mrc_exploitation.dart';
import 'mrc_plateforme.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module MERE (domaine « Poste mère ») : identifiant d'écran du manifeste → écran Flutter. Ce fichier est le SEUL point d'entrée du
/// module dans `registre.dart` ; on y ajoute une ligne par écran porté. Les écrans de la console qui lisent le client de la mère (supervision, appareils,
/// conflits, journal technique, réinitialisation) restent dans `registre.dart`, branchés sur `ConsoleMere`.
final Map<String, ConstruireEcran> ecransMERE = {
  // Lot MERE c : plateforme locale, exploitation, cycle de vie.
  'mere-service': (c, cfg) => EcranMereService(config: cfg),
  'mere-base': (c, cfg) => const EcranMereBase(),
  'mere-reseau': (c, cfg) => const EcranMereReseau(),
  'mere-planificateur': (c, cfg) => const EcranMerePlanificateur(),
  'mere-notifications': (c, cfg) => const EcranMereNotifications(),
  'mere-mise-en-service': (c, cfg) => EcranMereMiseEnService(config: cfg),
  'mere-mises-a-jour': (c, cfg) => const EcranMereMisesAJour(),
  'mere-import': (c, cfg) => const EcranMereImport(),
};
