import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'mat_registres.dart';
import 'mat_suivis.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module M4 : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransM4 = {
  'm4-maternite': (c, cfg) => const EcranSuiviMaternite(),
  'm4-accouchements': (c, cfg) => const EcranAccouchements(),
  'm4-naissances': (c, cfg) => const EcranNaissances(),
  'm4-dossier-bebe': (c, cfg) => const EcranDossierBebe(),
  'm4-deces': (c, cfg) => const EcranDeces(),
  'm4-cpn': (c, cfg) => const EcranCpn(),
  'm4-cpon': (c, cfg) => const EcranCpon(),
  'm4-planification': (c, cfg) => const EcranPlanification(),
  'm4-sonu': (c, cfg) => const EcranSonu(),
  'm4-ptme': (c, cfg) => const EcranPtme(),
  'm4-soins-curatifs': (c, cfg) => const EcranSoinsCuratifs(),
};
