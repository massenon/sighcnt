import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'dem_prelevement.dart';
import 'dem_registre.dart';
import 'dem_service.dart';
import 'sang_banque.dart';
import 'sang_donneurs.dart';
import 'sang_stats.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module M5 : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransM5 = {
  // Demandes d'analyses (fichiers `dem_*`) : registre, vues par service, salle de prélèvement.
  'm5-demandes': (c, cfg) => const EcranDemandesAnalyses(),
  'm5-demandes-maternite': (c, cfg) => const EcranDemandesService.maternite(),
  'm5-demandes-hospitalisation': (c, cfg) => const EcranDemandesService.hospitalisation(),
  'm5-prelevement': (c, cfg) => const EcranPrelevement(),
  // Banque de sang et statistiques de réactifs (fichiers `sang_*`) : activité fermée à la clinique dans la maquette, écrans portés tels quels.
  'm5-reactifs-stats': (c, cfg) => const EcranStatsReactifs(),
  'm5-banque-sang': (c, cfg) => const EcranBanqueSang(),
  'm5-donneurs': (c, cfg) => const EcranDonneurs(),
};
