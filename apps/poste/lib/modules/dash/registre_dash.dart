import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'tba_agent_admin.dart';
import 'tba_caissier.dart';
import 'tba_comptable.dart';
import 'tba_infirmier.dart';
import 'tba_laborantin.dart';
import 'tba_medecin.dart';
import 'tba_pharmacien.dart';
import 'tba_reception.dart';
import 'tba_rh.dart';
import 'tba_stock.dart';
import 'tbb_bloc.dart';
import 'tbb_maternite.dart';
import 'tbb_patient.dart';
import 'tbb_postes.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les tableaux de bord PORTÉS (DASH) : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée des tableaux de bord
/// dans `registre.dart` ; on y ajoute une ligne par écran porté. (DASH ne se déclare jamais au niveau du MODULE dans la matrice des droits : les
/// listes de chaque écran filtrent.)
final Map<String, ConstruireEcran> ecransDASH = {
  'dash-medecin': (c, cfg) => const EcranDashMedecin(),
  'dash-infirmier': (c, cfg) => const EcranDashInfirmier(),
  'dash-pharmacien': (c, cfg) => const EcranDashPharmacien(),
  'dash-laborantin': (c, cfg) => const EcranDashLaborantin(),
  'dash-stock': (c, cfg) => const EcranDashStock(),
  'dash-caissier': (c, cfg) => const EcranDashCaissier(),
  'dash-comptable': (c, cfg) => const EcranDashComptable(),
  'dash-rh': (c, cfg) => const EcranDashRh(),
  'dash-receptionniste': (c, cfg) => const EcranDashReception(),
  'dash-admin-agent': (c, cfg) => const EcranDashAgentAdmin(),
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
