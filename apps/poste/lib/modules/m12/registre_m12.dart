import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'cpa_dashboard.dart';
import 'cpa_balance.dart';
import 'cpa_depenses.dart';
import 'cpa_ecritures.dart';
import 'cpa_grand_livre.dart';
import 'cpa_journaux.dart';
import 'cpa_plan_comptable.dart';
import 'cpb_analytique.dart';
import 'cpb_banques.dart';
import 'cpb_budgets.dart';
import 'cpb_feuillets.dart';
import 'cpb_immobilisations.dart';
import 'cpb_seuil.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module M12 : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransM12 = {
  'm12-dashboard': (c, cfg) => const EcranDashboardCompta(),
  'm12-plan-comptable': (c, cfg) => const EcranPlanComptable(),
  'm12-journaux': (c, cfg) => const EcranJournaux(),
  'm12-ecritures': (c, cfg) => const EcranEcritures(),
  'm12-depenses': (c, cfg) => const EcranDepenses(),
  'm12-grand-livre': (c, cfg) => const EcranGrandLivre(),
  'm12-balance': (c, cfg) => const EcranBalance(),
  'm12-analytique': (c, cfg) => const EcranAnalytique(),
  'm12-budgets': (c, cfg) => const EcranBudgets(),
  'm12-immobilisations': (c, cfg) => const EcranImmobilisations(),
  'm12-banques': (c, cfg) => const EcranBanques(),
  'm12-compte-resultat': (c, cfg) => const EcranCompteResultat(),
  'm12-flux-tresorerie': (c, cfg) => const EcranFluxTresorerie(),
  'm12-seuil-rentabilite': (c, cfg) => const EcranSeuilRentabilite(),
};
