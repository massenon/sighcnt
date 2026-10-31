import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'rhb_stats_gardes.dart';
import 'rhb_stats_permanences.dart';
import 'rhb_stats_presence.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module M10 : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransM10 = {
  'm10-stats-gardes': (c, cfg) => const EcranStatsGardes(),
  'm10-stats-permanences': (c, cfg) => const EcranStatsPermanences(),
  'm10-stats-presence': (c, cfg) => const EcranStatsPresence(),
};
