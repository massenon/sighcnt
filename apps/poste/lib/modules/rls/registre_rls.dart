import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'rls_ecrans_a.dart';
import 'rls_ecrans_b.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les douze écrans du module RLS (domaine « Relais en ligne »), portés dans le poste le 1er novembre 2026 : ils remplacent « porté (apps/web) » de
/// la décision du 31/10. Ils lisent le relais par la mère (`ClientMere`) ; ce que seul le relais connaît s'affiche « non disponible » avec le lien
/// vers le panneau web. Droits : module RLS, administrateur seul (`packages/rbac/data/rbac.json`).
final Map<String, ConstruireEcran> ecransRLS = {
  'rls-tableau': (c, cfg) => const EcranRlsTableau(),
  'rls-appareils': (c, cfg) => const EcranRlsAppareils(),
  'rls-boites': (c, cfg) => const EcranRlsBoites(),
  'rls-codes': (c, cfg) => const EcranRlsCodes(),
  'rls-indicateurs': (c, cfg) => const EcranRlsIndicateurs(),
  'rls-alertes': (c, cfg) => const EcranRlsAlertes(),
  'rls-journal': (c, cfg) => const EcranRlsJournal(),
  'rls-superadmin': (c, cfg) => const EcranRlsSuperadmin(),
  'rls-parametres': (c, cfg) => const EcranRlsParametres(),
  'rls-hebergement': (c, cfg) => const EcranRlsHebergement(),
  'rls-sauvegarde': (c, cfg) => const EcranRlsSauvegarde(),
  'rls-opacite': (c, cfg) => const EcranRlsOpacite(),
};
