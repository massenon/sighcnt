import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'points_stock.dart';
import 'points_ventes.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module M6 : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransM6 = {
  'm6-point-ventes': (_, __) => const EcranPointVentes(),
  'm6-point-stock': (_, __) => const EcranPointStock(),
};
