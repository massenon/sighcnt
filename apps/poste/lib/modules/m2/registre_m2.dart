import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'cr_saisie.dart';
import 'modalites_tableau.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module M2 : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransM2 = {
  'm2-imagerie': (c, cfg) => echographieTableau,
  'm2-imagerie-radiographie': (c, cfg) => radiographieTableau,
  'm2-imagerie-mammographie': (c, cfg) => mammographieTableau,
  'm2-imagerie-scanner': (c, cfg) => scannerTableau,
  'm2-imagerie-irm': (c, cfg) => irmTableau,
  'm2-imagerie-cr': (c, cfg) => const EcranCompteRenduImagerie(),
};
