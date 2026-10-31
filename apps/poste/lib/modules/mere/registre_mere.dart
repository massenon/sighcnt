import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'mrb_cle.dart';
import 'mrb_indicateurs.dart';
import 'mrb_integrite.dart';
import 'mrb_journal.dart';
import 'mrb_reinit.dart';
import 'mrb_relais.dart';
import 'mrb_sauvegardes.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module MERE (domaine « Poste mère », réservé aux rôles admin et da, et à la mère). Ce fichier est le SEUL point d'entrée du
/// module dans `registre.dart`. Plusieurs lots y ajoutent leurs lignes : chacun ne touche que les siennes.
///
/// Lot (b), sécurité, continuité et liaison avec le relais : les écrans lisent le service de la mère par `MrbSource` (voir `mrb_source.dart`).
final Map<String, ConstruireEcran> ecransMERE = {
  'mere-journal-technique': (c, cfg) => const EcranJournalTechnique(),
  'mere-sauvegardes': (c, cfg) => const EcranSauvegardesMere(),
  'mere-cle-clinique': (c, cfg) => const EcranCleClinique(),
  'mere-integrite': (c, cfg) => const EcranIntegrite(),
  'mere-reinit': (c, cfg) => const EcranReinitialisation(),
  'mere-relais': (c, cfg) => const EcranRelais(),
  'mere-indicateurs': (c, cfg) => const EcranIndicateursPublies(),
};
