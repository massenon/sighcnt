import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'pv_factures_fournisseurs.dart';
import 'pv_fournisseurs.dart';
import 'pv_reception.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module M7 : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransM7 = {
  'm7-pv-reception-consommables': (c, cfg) => const EcranPvReception.consommables(),
  'm7-pv-reception-reactifs': (c, cfg) => const EcranPvReception.reactifs(),
  'm7-fournisseurs': (c, cfg) => const EcranFournisseurs(),
  'm7-factures-fournisseurs': (c, cfg) => const EcranFacturesFournisseurs(),
};
