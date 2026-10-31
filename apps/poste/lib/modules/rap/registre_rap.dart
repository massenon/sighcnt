import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'rap_bibliotheque.dart';
import 'rap_direction.dart';
import 'rap_generateur.dart';
import 'rap_historique.dart';

typedef ConstruireEcran = Widget Function(
    BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module RAP (rapports, impression & états officiels) : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL
/// point d'entrée du module dans `registre.dart`.
final Map<String, ConstruireEcran> ecransRAP = {
  'rapports-bibliotheque': (c, cfg) => const EcranRapBibliotheque(),
  'rapports-direction': (c, cfg) => const EcranRapDirection(),
  'rapports-generateur': (c, cfg) => const EcranRapGenerateur(),
  'rapports-historique': (c, cfg) => const EcranRapHistorique(),
};
