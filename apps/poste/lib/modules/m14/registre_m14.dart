import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'audit.dart';
import 'sauvegardes.dart';
import 'sessions.dart';
import 'soignants.dart';
import 'utilisateurs.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module M14 : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransM14 = {
  'm14-utilisateurs': (c, cfg) => const EcranUtilisateurs(),
  'm14-soignants': (c, cfg) => const EcranSoignants(),
  'm14-sessions': (c, cfg) => const EcranSessions(),
  'm14-audit': (c, cfg) => const EcranAudit(),
  'm14-sauvegardes': (c, cfg) => const EcranSauvegardes(),
};
