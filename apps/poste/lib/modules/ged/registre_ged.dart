import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'ged_archives.dart';
import 'ged_bibliotheque.dart';
import 'ged_workflow.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module GED : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransGED = {
  'ged-bibliotheque': (c, cfg) => const EcranBibliothequeGed(),
  'ged-workflow': (c, cfg) => const EcranWorkflowGed(),
  'ged-archives': (c, cfg) => const EcranArchivesGed(),
};
