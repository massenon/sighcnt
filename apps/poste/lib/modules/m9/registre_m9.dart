import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'assures.dart';
import 'compagnies.dart';
import 'tableau_bord.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module M9 : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransM9 = {
  'm9-dashboard': (c, cfg) => const EcranDashboardAssurances(),
  'm9-compagnies': (c, cfg) => const EcranCompagnies(),
  'm9-assures': (c, cfg) => const EcranAssures(),
};
