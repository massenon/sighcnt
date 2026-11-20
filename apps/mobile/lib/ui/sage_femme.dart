import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../moteur/moteur_mobile.dart';
import 'formulaire_suite.dart';

/// Les trois écrans du profil sage-femme, ouverts depuis le dossier de la patiente : visite prénatale (CPN), visite post-natale (CPoN) et surveillance
/// mère-bébé. La commande n'existe que pour le profil que le simulateur ouvre (`ServiceSuite.peut`) ; le service refait le contrôle à l'écriture.
Future<void> ouvrirCpn(BuildContext context, ServiceSuite suite, String patientId) async {
  final nom = await suite.nomDe(patientId);
  final age = await suite.ageDe(patientId);
  if (!context.mounted) return;
  final note = mobCpnNoteAge(age);
  await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => FormulaireSuite(
            ecran: 'cpn',
            sous: nom,
            notes: [if (note != null) note],
            enregistrer: (s) => suite.enregistrerCpn(patientId, s),
            signalement: (s) => mobCpnAlerte(s) ? mobCpnToastAlerte : null,
          )));
}

Future<void> ouvrirCpon(BuildContext context, ServiceSuite suite, String patientId) async {
  final nom = await suite.nomDe(patientId);
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FormulaireSuite(ecran: 'cpon', sous: nom, enregistrer: (s) => suite.enregistrerCpon(patientId, s))));
}

Future<void> ouvrirSurveillance(BuildContext context, ServiceSuite suite, String patientId) async {
  final nom = await suite.nomDe(patientId);
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => FormulaireSuite(ecran: 'surveillance', sous: nom, notes: [mobNoteEcranSuite('surveillance')!], enregistrer: (s) => suite.enregistrerSurveillance(patientId, s))));
}
