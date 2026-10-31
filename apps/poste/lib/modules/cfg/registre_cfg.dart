import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'cfa_natures.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module CFG (configuration de la clinique) : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point
/// d'entrée du module dans `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransCFG = {
  'cfg-natures-facture': (c, cfg) => const EcranNaturesFacture(),
};
