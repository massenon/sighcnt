import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'rha_conges.dart';
import 'rha_contrats.dart';
import 'rha_dashboard.dart';
import 'rha_fiches_poste.dart';
import 'rha_missions.dart';
import 'rha_personnel.dart';
import 'rha_prestataires.dart';
import 'rha_profil.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module M10 : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransM10 = {
  'm10-fiches-poste': (c, cfg) => const EcranFichesPoste(),
  'm10-dashboard': (c, cfg) => const EcranDashboardRh(),
  'm10-personnel': (c, cfg) => const EcranPersonnel(),
  'm10-employe-profil': (c, cfg) => const EcranProfilEmploye(),
  'm10-contrats': (c, cfg) => const EcranContrats(),
  'm10-conges': (c, cfg) => const EcranConges(),
  'm10-missions': (c, cfg) => const EcranMissions(),
  'm10-prestataires': (c, cfg) => const EcranPrestataires(),
};
