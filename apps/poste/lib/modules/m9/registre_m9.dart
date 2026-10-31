import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'assures.dart';
import 'compagnies.dart';
import 'conventions.dart';
import 'creances.dart';
import 'facture_mere.dart';
import 'historique.dart';
import 'prises_en_charge.dart';
import 'releve.dart';
import 'relances.dart';
import 'tableau_bord.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module M9 : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransM9 = {
  'm9-dashboard': (c, cfg) => const EcranDashboardAssurances(),
  'm9-compagnies': (c, cfg) => const EcranCompagnies(),
  'm9-assures': (c, cfg) => const EcranAssures(),
  'm9-conventions': (c, cfg) => const EcranConventions(),
  'm9-prises-en-charge': (c, cfg) => const EcranPrisesEnCharge(),
  'm9-historique': (c, cfg) => const EcranHistoriqueAssureur(),
  'm9-creances': (c, cfg) => const EcranCreances(),
  'm9-relances': (c, cfg) => const EcranRelances(),
  'm9-factures-assureur': (c, cfg) => const EcranReleveAssureur(),
  'm9-facture-mere': (c, cfg) => const EcranFactureMere(),
};
