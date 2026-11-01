import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/config_poste.dart';
import 'imp_ecrans.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module IMP (Importation de données) : l'accueil, puis un écran par jeu d'import. `m6-import-grand-stock` (« Importation Grand
/// Stock ») est l'écran du premier jeu : il vit dans la rangée du module M6 du manifeste, mais son moteur est celui du module IMP, d'où sa place ici.
final Map<String, ConstruireEcran> ecransIMP = {
  'imp-accueil': (c, cfg) => const EcranImportAccueil(),
  for (final j in jeuxImport) j.ecran: (c, cfg) => EcranImportJeu(j.id),
};
