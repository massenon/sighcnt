import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'qual_enquetes.dart';
import 'qual_publique.dart';
import 'qual_satisfaction.dart';
import 'qual_validations.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module M13 : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransM13 = {
  'adm-enquetes': (c, cfg) => const EcranEnquetes(),
  'adm-satisfaction': (c, cfg) => const EcranSatisfaction(),
  'adm-validations': (c, cfg) => const EcranValidations(),
  'enquete-publique': (c, cfg) => const EnquetePubliqueDansCoque(),
};
