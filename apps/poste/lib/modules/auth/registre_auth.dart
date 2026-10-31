import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'acc_ecrans.dart';
import 'acc_support.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés des écrans d'ACCÈS (AUTH) et de SUPPORT (SUP) : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point
/// d'entrée du module dans `registre.dart`.
///
/// Les huit premiers sont AUTONOMES (`EcranAutonome`) : la coque les sert en plein écran, sans barre, sans ruban, sans page standard. `aide-apropos` et
/// `contact-editeur` sont des écrans ordinaires de la coque, hors ruban.
final Map<String, ConstruireEcran> ecransAUTH = {
  'index': (c, cfg) => const EcranConnexion(),
  'auth-forgot': (c, cfg) => const EcranMotDePasseOublie(),
  'auth-reset': (c, cfg) => const EcranReinitialisation(),
  'auth-2fa': (c, cfg) => const EcranDoubleFacteur(),
  'auth-lock': (c, cfg) => const EcranVerrou(),
  'error-404': (c, cfg) => page404,
  'error-403': (c, cfg) => page403,
  'plan-du-site': (c, cfg) => const EcranPlanDuSite(),
  'aide-apropos': (c, cfg) => const EcranAide(),
  'contact-editeur': (c, cfg) => const EcranContactEditeur(),
};
