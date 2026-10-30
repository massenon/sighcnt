import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'patients.dart';
import 'releves.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module M1 : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransM1 = {
  'm1-patients': (c, cfg) => const EcranPatients(),
  'm1-patient-nouveau': (c, cfg) => const EcranPatientNouveau(),
  'm1-patient-profil': (c, cfg) => const EcranPatientProfil(),
  'm1-antecedents': (c, cfg) => const EcranAntecedents(),
  'm1-constantes': (c, cfg) => const EcranConstantes(),
  'm1-reference': (c, cfg) => const EcranReference(),
  'm1-contre-reference': (c, cfg) => const EcranContreReference(),
};
