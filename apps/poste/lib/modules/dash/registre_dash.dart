import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'tbb_bloc.dart';
import 'tbb_maternite.dart';
import 'tbb_patient.dart';
import 'tbb_postes.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les tableaux de bord PORTÉS : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée des tableaux de bord dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransDASH = {
  'dash-ambulancier': (c, cfg) => const EcranDashAmbulancier(),
  'dash-aide-soignant': (c, cfg) => const EcranDashAideSoignant(),
  'dash-echographiste': (c, cfg) => const EcranDashEchographiste(),
  'dash-surveillant': (c, cfg) => const EcranDashSurveillant(),
  'dash-assistant-comptable': (c, cfg) => const EcranDashAssistantDirection(),
  'dash-chirurgien': (c, cfg) => const EcranDashChirurgien(),
  'dash-anesthesiste': (c, cfg) => const EcranDashAnesthesiste(),
  'dash-aide-comptable': (c, cfg) => const EcranDashAideComptable(),
  'dash-maternite': (c, cfg) => const EcranDashMaternite(),
  'dash-patient': (c, cfg) => const EcranDashPatient(),
};
