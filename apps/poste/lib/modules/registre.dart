import 'package:flutter/material.dart';

import '../core/config_poste.dart';
import '../core/controleur_poste.dart';
import '../mere/client_mere.dart';
import '../mere/console.dart';
import 'ged/registre_ged.dart';
import 'm1/registre_m1.dart';
import 'm10/registre_m10.dart';
import 'm11/registre_m11.dart';
import 'm12/registre_m12.dart';
import 'm13/registre_m13.dart';
import 'm14/registre_m14.dart';
import 'm9/registre_m9.dart';
import 'm2/registre_m2.dart';
import 'm3/registre_m3.dart';
import 'm4/registre_m4.dart';
import 'm5/registre_m5.dart';
import 'm6/registre_m6.dart';
import 'm7/registre_m7.dart';
import 'mecef/ecrans.dart';
import 'm8/avoirs.dart';
import 'm8/caisse.dart';
import 'm8/dashboard.dart';
import 'm8/facturation.dart';
import 'm8/factures.dart';
import 'm8/operations.dart';
import 'm8/paiements.dart';
import 'm8/proforma.dart';
import 'm8/recettes.dart';
import 'm8/remboursements.dart';
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
    'm8-facturation': (c, cfg) => const EcranFacturation(),
    'm8-caisse': (c, cfg) => const EcranCaisse(),
    // Tranche 2 — chaque module déclare ses écrans dans SON registre (un fichier par module : pas de conflit d'édition).
    ...ecransGED,
    ...ecransM13,
    ...ecransM14,
    ...ecransM9,
    ...ecransM1,
    ...ecransM10,
    ...ecransM11,
    ...ecransM12,
    ...ecransM2,
    ...ecransM3,
    ...ecransM4,
    ...ecransM5,
    ...ecransM6,
    ...ecransM7,
    'mecef-dashboard': (c, cfg) => const EcranMecefTableauDeBord(),
    'mecef-factures': (c, cfg) => const EcranMecefFactures(),
    'mecef-transmission': (c, cfg) => const EcranMecefTransmission(),
    'mecef-avoirs': (c, cfg) => const EcranMecefAvoirs(),
    'mecef-journal': (c, cfg) => const EcranMecefJournal(),
    'mecef-config': (c, cfg) => const EcranMecefConfig(),
    'm8-facture-avoir': (c, cfg) => const EcranFactureAvoir(),
    'm8-remboursements': (c, cfg) => const EcranRemboursements(),
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
