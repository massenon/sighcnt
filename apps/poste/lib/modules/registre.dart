import 'package:flutter/material.dart';

import '../core/config_poste.dart';
import '../mere/client_mere.dart';
import '../mere/console.dart';
import 'module_sigh.dart';

const _tous = {ModePoste.fileul, ModePoste.mere};
const _mere = {ModePoste.mere};

/// Modules présents sur TOUT poste. Les tranches métier (caisse + MECeF, pharmacie, laboratoire…) s'ajoutent ici,
/// dans l'ordre de `docs/architecture/PARITE-MAQUETTE.md` ; aucune n'est portée à ce jour.
List<ModuleSigh> modulesCommuns() => [
      ModuleSigh(
        id: 'accueil-poste',
        libelle: 'Accueil du poste',
        icone: Icons.home_outlined,
        modes: _tous,
        construire: (c, cfg) => Center(child: Text(cfg.estMere ? 'Poste mère — aucun module métier porté pour l’instant.' : 'Poste fileul — aucun module métier porté pour l’instant.')),
      ),
    ];

/// Modules RÉSERVÉS à la mère : la console, rubrique par rubrique. Le client du service local est injecté.
List<ModuleSigh> modulesMere(ClientMere client) {
  Widget rubrique(SectionMere s) => ConsoleMere(client: client, section: s);
  return [
    ModuleSigh(id: 'mere-supervision', libelle: 'Supervision', icone: Icons.monitor_heart_outlined, modes: _mere, groupe: 'Poste mère', construire: (c, cfg) => rubrique(SectionMere.supervision)),
    ModuleSigh(id: 'mere-appareils', libelle: 'Appareils', icone: Icons.devices_other_outlined, modes: _mere, groupe: 'Poste mère', construire: (c, cfg) => rubrique(SectionMere.appareils)),
    ModuleSigh(id: 'mere-conflits', libelle: 'Conflits', icone: Icons.call_split, modes: _mere, groupe: 'Poste mère', construire: (c, cfg) => rubrique(SectionMere.conflits)),
    ModuleSigh(id: 'mere-journal', libelle: 'Journal technique', icone: Icons.receipt_long_outlined, modes: _mere, groupe: 'Poste mère', construire: (c, cfg) => rubrique(SectionMere.journal)),
    ModuleSigh(id: 'mere-maintenance', libelle: 'Maintenance', icone: Icons.build_outlined, modes: _mere, groupe: 'Poste mère', construire: (c, cfg) => rubrique(SectionMere.maintenance)),
  ];
}

/// Source unique de la navigation : les modules du mode, dans l'ordre déclaré, filtrés par `droit` (matrice RBAC).
List<ModuleSigh> modulesVisibles(ConfigPoste config, {required List<ModuleSigh> tous, bool Function(ModuleSigh)? droit}) =>
    tous.where((m) => m.disponiblePour(config) && (droit == null || droit(m))).toList();
