import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'hos_chambres.dart';
import 'surv_glasgow.dart';
import 'surv_rapport.dart';
import 'surv_transfusion.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module M3 : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransM3 = {
  'm3-chambres': (c, cfg) => const EcranChambres(),
  'm3-glasgow': (c, cfg) => const EcranGlasgow(),
  'm3-transfusion': (c, cfg) => const EcranTransfusion(),
  'm3-rapport': (c, cfg) => const EcranRapport(),
};
