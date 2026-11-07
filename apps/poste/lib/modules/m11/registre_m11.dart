import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'pai_bulletins.dart';
import 'pai_calcul.dart';
import 'pai_cotisations.dart';
import 'pai_heures_avances.dart';
import 'pai_ortb.dart';
import 'pai_prets.dart';
import 'pai_tableau_bord.dart';
import 'pai_validation.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module M11 : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransM11 = {
  'm11-dashboard': (c, cfg) => const EcranDashboardPaie(),
  'm11-calcul': (c, cfg) => const EcranCalculPaie(),
  'm11-bulletins': (c, cfg) => const EcranBulletins(),
  'm11-cotisations': (c, cfg) => const EcranCotisations(),
  'm11-heures-sup': (c, cfg) => const EcranHeuresSup(),
  'm11-avances': (c, cfg) => const EcranAvances(),
  'm11-validation': (c, cfg) => const EcranValidationPaie(),
  'm11-ortb': (c, cfg) => const EcranOrtb(),
  'm11-prets-etudes': (c, cfg) => const EcranPretsEtudes(),
};
