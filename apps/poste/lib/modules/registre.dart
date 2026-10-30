import 'package:flutter/material.dart';

import '../core/config_poste.dart';
import '../core/controleur_poste.dart';
import '../mere/client_mere.dart';
import '../mere/console.dart';
import 'm8/caisse.dart';
import 'm8/dashboard.dart';
import 'm8/factures.dart';
import 'm8/operations.dart';
import 'm8/paiements.dart';
import 'm8/proforma.dart';
import 'm8/recettes.dart';
import 'm8/reliquats.dart';
import 'reglages_poste.dart';

typedef ConstruireEcran = Widget Function(
    BuildContext contexte, ConfigPoste config);

/// Qui administre la mère (DAF, administrateur système) : la console « DAF/admin » de l'architecture du 29/10/2026.
const rolesAdminMere = {'admin', 'da'};

/// LES ÉCRANS PORTÉS : identifiant d'écran de la maquette → écran Flutter. Tout écran du manifeste qui n'est pas ici
/// s'affiche comme « à porter » avec sa tranche — la navigation est complète dès le premier jour, et la parité se MESURE
/// (nombre d'identifiants présents ici / nombre d'écrans du manifeste).
///
/// Les droits ne sont PAS décidés ici : le ruban n'affiche que ce que la matrice RBAC ouvre au rôle.
Map<String, ConstruireEcran> ecransPortes(
    {ControleurPoste? controleur, ClientMere? client}) {
  Widget console(SectionMere s) => ConsoleMere(client: client!, section: s);
  return {
    // Tranche 1 — Caisse, MECeF, impression.
    'm8-dashboard': (c, cfg) => const EcranDashboardFacturation(),
    'm8-caisse': (c, cfg) => const EcranCaisse(),
    'm8-factures': (c, cfg) => const EcranFactures(),
    'm8-paiements': (c, cfg) => const EcranPaiements(),
    'm8-proforma': (c, cfg) => const EcranProforma(),
    'm8-reliquats': (c, cfg) => const EcranReliquats(),
    'm8-recettes': (c, cfg) => const EcranRecettes(),
    'm8-operations': (c, cfg) => const EcranOperations(),
    if (controleur != null)
      'cfg-poste': (c, cfg) => ReglagesPoste(controleur: controleur),
    // Modules complémentaires de la MÈRE (le domaine « Poste mère » n'existe que sur la mère, voir Manifeste.ruban).
    if (client != null) ...{
      'mere-supervision': (c, cfg) => console(SectionMere.supervision),
      'mere-appareils': (c, cfg) => console(SectionMere.appareils),
      'mere-conflits': (c, cfg) => console(SectionMere.conflits),
      'mere-journal-technique': (c, cfg) => console(SectionMere.journal),
      'mere-reinit': (c, cfg) => console(SectionMere.maintenance),
    },
  };
}
