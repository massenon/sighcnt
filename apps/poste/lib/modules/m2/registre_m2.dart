import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'ag_agenda.dart';
import 'ag_file.dart';
import 'ag_registres.dart';
import 'ag_rendezvous.dart';
import 'img_demandes.dart';
import 'img_galerie.dart';
import 'img_poste.dart';
import 'cr_saisie.dart';
import 'modalites_tableau.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module M2 : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransM2 = {
  'm2-agenda': (c, cfg) => const EcranAgenda(),
  'm2-rendezvous': (c, cfg) => const EcranRendezVous(),
  'm2-visites': (c, cfg) => const EcranVisites(),
  'm2-domicile': (c, cfg) => const EcranDomicile(),
  'm2-registre-appels': (c, cfg) => const EcranRegistreAppels(),
  'm2-file-attente': (c, cfg) => const EcranFileAttente(),
  'm2-affichage': (c, cfg) => const EcranAffichage(),
  'm2-file-cabinet': (c, cfg) => const EcranFileCabinet(),
  'm2-agenda-medecin': (c, cfg) => const EcranAgendaMedecin(),
  'm2-imagerie-demandes': (c, cfg) => const EcranDemandesImagerie(),
  'm2-dashboard-imagerie': (c, cfg) => const EcranPosteImagerie(),
  'm2-echographie-galerie': (c, cfg) => const EcranGalerieClichesImagerie(),
  'm2-imagerie': (c, cfg) => echographieTableau,
  'm2-imagerie-radiographie': (c, cfg) => radiographieTableau,
  'm2-imagerie-mammographie': (c, cfg) => mammographieTableau,
  'm2-imagerie-scanner': (c, cfg) => scannerTableau,
  'm2-imagerie-irm': (c, cfg) => irmTableau,
  'm2-imagerie-cr': (c, cfg) => const EcranCompteRenduImagerie(),
};
