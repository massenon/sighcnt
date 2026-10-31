import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'cfa_natures.dart';
import 'cfa_catalogue.dart';
import 'cfa_identite.dart';
import 'cfa_imagerie.dart';
import 'cfa_organisation.dart';
import 'cfa_pieces.dart';
import 'cfa_rappels.dart';
import 'cfa_tarifs.dart';
import 'cfb_centres.dart';
import 'cfb_compte.dart';
import 'cfb_fiscal.dart';
import 'cfb_modules.dart';
import 'cfb_notifications.dart';
import 'cfb_regles.dart';
import 'cfb_systeme.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module CFG (configuration de la clinique) : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point
/// d'entrée du module dans `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransCFG = {
  'cfg-organisation': (c, cfg) => const EcranOrganisation(),
  'cfg-tarifs': (c, cfg) => const EcranTarifs(),
  'cfg-catalogue': (c, cfg) => const EcranCatalogue(),
  'cfg-branding': (c, cfg) => const EcranBranding(),
  'cfg-entetes': (c, cfg) => const EcranEntetes(),
  'cfg-types-piece': (c, cfg) => const EcranTypesPiece(),
  'cfg-certificats': (c, cfg) => const EcranCertificats(),
  'cfg-rappels': (c, cfg) => const EcranRappels(),
  'cfg-imagerie-catalogue': (c, cfg) => const EcranImagerieCatalogue(),
  'cfg-natures-facture': (c, cfg) => const EcranNaturesFacture(),
  // CFG (B)
  'cfg-centres-couts': (c, cfg) => const EcranCentresCouts(),
  'cfg-regles': (c, cfg) => const EcranRegles(),
  'cfg-fiscalite': (c, cfg) => const EcranFiscalite(),
  'cfg-comptabilite': (c, cfg) => const EcranComptabilite(),
  'cfg-notifications': (c, cfg) => const EcranNotifications(),
  'cfg-compte': (c, cfg) => const EcranCompte(),
  'cfg-modules': (c, cfg) => const EcranModules(),
  'cfg-systeme': (c, cfg) => const EcranSysteme(),
};
