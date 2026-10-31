import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'cpa_dashboard.dart';
import 'cpa_journaux.dart';
import 'cpa_plan_comptable.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module M12 : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransM12 = {
  'm12-dashboard': (c, cfg) => const EcranDashboardCompta(),
  'm12-plan-comptable': (c, cfg) => const EcranPlanComptable(),
  'm12-journaux': (c, cfg) => const EcranJournaux(),
};
