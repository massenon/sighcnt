import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'stock_alertes.dart';
import 'stock_dashboard.dart';
import 'stock_lots.dart';
import 'stock_niveaux.dart';
import 'stock_produits.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module M6 : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransM6 = {
  'm6-dashboard': (c, cfg) => const EcranDashboardStock(),
  'm6-produits': (c, cfg) => const EcranProduitsStock(),
  'm6-stock-gros': (c, cfg) => const EcranNiveauStock.gros(),
  'm6-stock-detail': (c, cfg) => const EcranNiveauStock.detail(),
  'm6-lots': (c, cfg) => const EcranLotsStock(),
  'm6-alertes': (c, cfg) => const EcranAlertesStock(),
};
