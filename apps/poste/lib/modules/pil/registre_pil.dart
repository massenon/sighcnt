import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'pil_clinique.dart';
import 'pil_direction.dart';
import 'pil_gestion.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du PILOTAGE (PIL) : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransPIL = {
  'dash-direction': (c, cfg) => const EcranDirection(),
  'dash-da': (c, cfg) => const EcranDa(),
  'dash-croise': (c, cfg) => const EcranCroise(),
  'dash-admin': (c, cfg) => const EcranAdmin(),
  'm4-stats-maternite': (c, cfg) => const EcranStatsMaternite(),
  'm2-stats-echographie': (c, cfg) => const EcranStatsImagerie(),
  'm5-stats-examens': (c, cfg) => const EcranStatsExamens(),
  'm2-stats-consultations': (c, cfg) => const EcranStatsConsultations(),
  'm3-stats-bloc': (c, cfg) => const EcranStatsBloc(),
  'm3-stats-hospitalisations': (c, cfg) => const EcranStatsHospitalisations(),
  'm10-cout-agent': (c, cfg) => const EcranCoutAgent(),
  'm12-rentabilite-groupes': (c, cfg) => const EcranRentabiliteGroupes(),
  'm12-tableau-decisionnel': (c, cfg) => const EcranTableauDecisionnel(),
};
