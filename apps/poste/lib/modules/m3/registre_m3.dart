import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'hos_admissions.dart';
import 'hos_chambres.dart';
import 'hos_plan_lits.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module M3 : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransM3 = {
  'm3-admissions': (c, cfg) => const EcranAdmissions(),
  'm3-chambres': (c, cfg) => const EcranChambres(),
  'm3-plan-lits': (c, cfg) => const EcranPlanLits(),
};
