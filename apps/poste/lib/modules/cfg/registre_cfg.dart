import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'cfa_natures.dart';
import 'cfa_catalogue.dart';
import 'cfa_identite.dart';
import 'cfa_organisation.dart';
import 'cfa_pieces.dart';
import 'cfa_tarifs.dart';

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
  'cfg-natures-facture': (c, cfg) => const EcranNaturesFacture(),
};
