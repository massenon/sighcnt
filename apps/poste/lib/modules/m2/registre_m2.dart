import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'img_demandes.dart';
import 'img_galerie.dart';
import 'img_poste.dart';
import 'cr_saisie.dart';
import 'modalites_tableau.dart';
import 'cs_consultations.dart';
import 'cs_dossiers.dart';
import 'cs_fiche.dart';
import 'cs_ordonnances.dart';
import 'cs_pathologies.dart';
import 'cs_prescriptions.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module M2 : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransM2 = {
  'm2-imagerie-demandes': (c, cfg) => const EcranDemandesImagerie(),
  'm2-dashboard-imagerie': (c, cfg) => const EcranPosteImagerie(),
  'm2-echographie-galerie': (c, cfg) => const EcranGalerieClichesImagerie(),
  'm2-imagerie': (c, cfg) => echographieTableau,
  'm2-imagerie-radiographie': (c, cfg) => radiographieTableau,
  'm2-imagerie-mammographie': (c, cfg) => mammographieTableau,
  'm2-imagerie-scanner': (c, cfg) => scannerTableau,
  'm2-imagerie-irm': (c, cfg) => irmTableau,
  'm2-imagerie-cr': (c, cfg) => const EcranCompteRenduImagerie(),
  'm2-consultations': (c, cfg) => const EcranConsultations(),
  'm2-dossiers-consultation': (c, cfg) => const EcranDossiersConsultation(),
  'm2-dossier-consultation-nouveau': (c, cfg) => const EcranDossierConsultationNouveau(),
  'm2-consultation-fiche': (c, cfg) => const EcranFicheConsultation(),
  'm2-pathologies': (c, cfg) => const EcranPathologies(),
  'm2-ordonnances': (c, cfg) => const EcranOrdonnances(),
  'm2-ordonnance-nouvelle': (c, cfg) => const EcranOrdonnanceNouvelle(),
  'm2-prescriptions': (c, cfg) => const EcranPrescriptions(),
  'm2-salle-soins': (c, cfg) => const EcranSalleSoins(),
};
