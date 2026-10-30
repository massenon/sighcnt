import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'hos_admissions.dart';
import 'bloc_cpa.dart';
import 'bloc_cro.dart';
import 'bloc_cra.dart';
import 'bloc_checklist.dart';
import 'hos_chambres.dart';
import 'surv_administrations.dart';
import 'surv_glasgow.dart';
import 'surv_rapport.dart';
import 'surv_surveillance.dart';
import 'surv_transfusion.dart';
import 'surv_visites.dart';
import 'hos_observation.dart';
import 'hos_plan_lits.dart';
import 'hos_soins.dart';
import 'hos_temperature.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module M3 : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransM3 = {
  'm3-admissions': (c, cfg) => const EcranAdmissions(),
  'm3-chambres': (c, cfg) => const EcranChambres(),
  'm3-administrations': (c, cfg) => const EcranAdministrations(),
  'm3-glasgow': (c, cfg) => const EcranGlasgow(),
  'm3-surveillance': (c, cfg) => const EcranSurveillance(),
  'm3-transfusion': (c, cfg) => const EcranTransfusion(),
  'm3-rapport': (c, cfg) => const EcranRapport(),
  'm3-visites-patients': (c, cfg) => const EcranVisitesPatients(),
  'm3-observation': (c, cfg) => const EcranObservation(),
  'm3-plan-lits': (c, cfg) => const EcranPlanLits(),
  'm3-feuille-temperature': (c, cfg) => const EcranFeuilleTemperature(),
  'm3-soins': (c, cfg) => const EcranSoins(),
  'm3-cpa': (c, cfg) => const EcranCpa(),
  'm3-bloc-cro': (c, cfg) => const EcranCro(),
  'm3-cr-anesthesie': (c, cfg) => const EcranCra(),
  'm3-bloc-checklist': (c, cfg) => const EcranChecklistBloc(),
};
