import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'flux_dispensation.dart';
import 'flux_etiquetage.dart';
import 'flux_pharmacie.dart';
import 'flux_reprise.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module M6 : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransM6 = {
  'm6-pharmacie-interne': (c, cfg) => const EcranPharmacieInterne(),
  'm6-pharmacie-externe': (c, cfg) => const EcranPharmacieExterne(),
  'm6-dispensation': (c, cfg) => const EcranDispensation(),
  'm6-etiquetage': (c, cfg) => const EcranEtiquetage(),
  'm6-reprise': (c, cfg) => const EcranReprise(),
};
