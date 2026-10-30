import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'mvt_inventaire.dart';
import 'mvt_inventaire_feuille.dart';
import 'mvt_mouvements.dart';
import 'mvt_pertes.dart';
import 'mvt_transferts.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module M6 : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransM6 = {
  // Mouvements de stock : transferts multi-lignes, mouvements, inventaires et leur feuille, pertes (fichiers `mvt_*`).
  'm6-transferts': (c, cfg) => const EcranTransferts(),
  'm6-mouvements': (c, cfg) => const EcranMouvements(),
  'm6-inventaire': (c, cfg) => const EcranInventaires(),
  'm6-inventaire-feuille': (c, cfg) => const EcranInventaireFeuille(),
  'm6-pertes': (c, cfg) => const EcranPertes(),
};
