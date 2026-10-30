import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'dem_prelevement.dart';
import 'dem_registre.dart';
import 'dem_service.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module M5 : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransM5 = {
  // Demandes d'analyses (fichiers `dem_*`) : registre, vues par service, salle de prélèvement.
  'm5-demandes': (c, cfg) => const EcranDemandesAnalyses(),
  'm5-demandes-maternite': (c, cfg) => const EcranDemandesService.maternite(),
  'm5-demandes-hospitalisation': (c, cfg) => const EcranDemandesService.hospitalisation(),
  'm5-prelevement': (c, cfg) => const EcranPrelevement(),
};
