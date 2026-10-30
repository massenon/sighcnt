import 'package:flutter/material.dart';

import '../../core/config_poste.dart';
import 'patients.dart';
import 'releves.dart';
import 'pieces.dart';
import 'externe.dart';
import 'documents.dart';

typedef ConstruireEcran = Widget Function(BuildContext contexte, ConfigPoste config);

/// Les écrans portés du module M1 : identifiant d'écran de la maquette → écran Flutter. Ce fichier est le SEUL point d'entrée du module dans
/// `registre.dart` ; on y ajoute une ligne par écran porté.
final Map<String, ConstruireEcran> ecransM1 = {
  'm1-patients': (c, cfg) => const EcranPatients(),
  'm1-patient-nouveau': (c, cfg) => const EcranPatientNouveau(),
  'm1-patient-profil': (c, cfg) => const EcranPatientProfil(),
  'm1-antecedents': (c, cfg) => const EcranAntecedents(),
  'm1-constantes': (c, cfg) => const EcranConstantes(),
  'm1-reference': (c, cfg) => const EcranReference(),
  'm1-contre-reference': (c, cfg) => const EcranContreReference(),
  'm1-pieces': (c, cfg) => const EcranPieces(),
  'm1-externe': (c, cfg) => const EcranExterne(),
  'm1-documents': (c, cfg) => const EcranDocuments(),
  'm1-numerisation': (c, cfg) => const EcranNumerisation(),
  'm1-dossier-medical': (c, cfg) => const EcranRenvoiM1.dossierMedical(),
  'm1-dossier-etendu': (c, cfg) => const EcranRenvoiM1.dossierEtendu(),
  'm1-certificats-externes': (c, cfg) => const EcranRenvoiM1.certificatsExternes(),
};
