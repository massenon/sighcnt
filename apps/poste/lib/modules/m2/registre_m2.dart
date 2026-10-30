import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'img_demandes.dart';
import 'img_galerie.dart';
import 'img_poste.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module M2 : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransM2 = {
  'm2-imagerie-demandes': (c, cfg) => const EcranDemandesImagerie(),
  'm2-dashboard-imagerie': (c, cfg) => const EcranPosteImagerie(),
  'm2-echographie-galerie': (c, cfg) => const EcranGalerieClichesImagerie(),
};
