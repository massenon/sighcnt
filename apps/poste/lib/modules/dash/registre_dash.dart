import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'tba_caissier.dart';
import 'tba_infirmier.dart';
import 'tba_laborantin.dart';
import 'tba_medecin.dart';
import 'tba_stock.dart';
import 'tba_pharmacien.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés des TABLEAUX DE BORD par poste (DASH) : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point
/// d'entrée du module dans `registre.dart` ; on y ajoute une ligne par écran porté. (DASH ne se déclare jamais au niveau du MODULE dans la matrice
/// des droits : les listes de chaque écran filtrent.)
final Map<String, ConstruireEcran> ecransDASH = {
  'dash-medecin': (c, cfg) => const EcranDashMedecin(),
  'dash-infirmier': (c, cfg) => const EcranDashInfirmier(),
  'dash-pharmacien': (c, cfg) => const EcranDashPharmacien(),
  'dash-laborantin': (c, cfg) => const EcranDashLaborantin(),
  'dash-stock': (c, cfg) => const EcranDashStock(),
  'dash-caissier': (c, cfg) => const EcranDashCaissier(),
};
