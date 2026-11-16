// Les paramètres de la famille `sms` (lot SMS-R) : défauts SEMÉS, jamais une constante d'un moteur. Réglage de CLINIQUE posé au poste mère, reçu des fileuls, JAMAIS envoyé à un téléphone.
library;

import '../parametres/parametres.dart';
import 'sms_auto.dart';

const String _validee = 'Décision de la Direction du 16/11/2026 (DECISIONS-A-VALIDER, section AQ points 27 et 28) : lot SMS-R, ADR-0008';
const String _proposition = 'Proposition à valider (lot SMS-R, section AU) : aucun document ne fixe cette valeur';

const String _matin = 'Décision de la Direction du 16/11/2026 (lot SMS-R, rappel du matin même) : le défaut de 7 h et le texte du matin sont des propositions à valider';

DefinitionParametre _d(String cle, TypeParametre type, Object defaut, String libelle, String aide, String source) =>
    DefinitionParametre(cle: cle, famille: smsFamille, type: type, defaut: defaut, libelle: libelle, aide: aide, source: source, branche: true, appliquePar: 'Lot SMS-R (envois automatiques)');

final List<DefinitionParametre> definitionsSms = [
  _d(smsCleActif, TypeParametre.booleen, smsActifDefaut, 'Envois automatiques de SMS actifs', 'Désactivés par défaut (proposition) : l\'administrateur ou la Directrice Administrative les active une fois la passerelle du relais prête et testée.', _proposition),
  _d(smsCleRappelHeure, TypeParametre.entier, smsRappelHeureDefaut, 'Heure du rappel de rendez-vous', 'Heure (0 à 23, heure du Bénin) à laquelle part le rappel, le jour d\'envoi.', _validee),
  _d(smsCleRappelJoursAvant, TypeParametre.entier, smsRappelJoursAvantDefaut, 'Jours entre le rappel et le rendez-vous', '1 : le rappel part la veille du rendez-vous.', _validee),
  _d(smsCleRappelHeureMatin, TypeParametre.entier, smsRappelHeureMatinDefaut, 'Heure du rappel du matin (rendez-vous pris après l\'heure d\'envoi de la veille)', 'Heure (0 à 23, heure du Bénin) à laquelle part, le matin du rendez-vous, le rappel d\'un rendez-vous que la mère n\'a connu qu\'après l\'envoi de la veille. Jamais à l\'heure du rendez-vous ni après ; reporté à la fin des heures calmes s\'il y tombe.', _matin),
  _d(smsCleModeleRappelMatin, TypeParametre.texte, smsModeleRappelMatinDefaut, 'Modèle du rappel du matin', 'Mêmes variables et mêmes interdits que le rappel : le prénom ({{nom}}) y est ; jamais le médecin, le service ni le motif.', _matin),
  _d(smsCleAnniversaireHeure, TypeParametre.entier, smsAnniversaireHeureDefaut, 'Heure des vœux d\'anniversaire', 'Heure (0 à 23, heure du Bénin), patients et personnel.', _validee),
  _d(smsCleCalmeDebut, TypeParametre.entier, smsCalmeDebutDefaut, 'Début des heures calmes', 'Aucun envoi automatique pendant les heures calmes : il est reporté à leur fin.', 'Décision de la Direction du 07/11/2026 (PRD SMS, M2) : 21 h à 7 h'),
  _d(smsCleCalmeFin, TypeParametre.entier, smsCalmeFinDefaut, 'Fin des heures calmes', 'Heure (0 à 23) à laquelle un envoi reporté part.', 'Décision de la Direction du 07/11/2026 (PRD SMS, M2) : 21 h à 7 h'),
  _d(smsCleHorizonJours, TypeParametre.entier, smsHorizonJoursDefaut, 'Horizon de calcul (jours)', 'La mère calcule et dépose au relais les envois des jours à venir (de 1 à 14 jours) : le relais les garde planifiés.', _proposition),
  _d(smsCleToleranceMinutes, TypeParametre.entier, smsToleranceMinutesDefaut, 'Tolérance après l\'heure d\'envoi (minutes)', 'Un envoi dont l\'heure est passée depuis moins que cette durée est encore déposé (de 0 à 180 : le relais n\'envoie plus un message resté planifié plus de 3 heures).', _proposition),
  _d(smsCleModeleRappel, TypeParametre.texte, smsModeleRappelDefaut, 'Modèle du rappel de rendez-vous', 'Variables : {{nom}} {{date}} {{heure}} {{clinique}} {{telephone}}, et rien d\'autre. Aucun mot médical ; jamais le médecin, le service ni le motif.', _validee),
  _d(smsCleModeleAnniversairePatient, TypeParametre.texte, smsModeleAnniversairePatientDefaut, 'Modèle des vœux d\'anniversaire des patients', 'Mêmes variables et mêmes interdits que le rappel.', _validee),
  _d(smsCleModeleAnniversairePersonnel, TypeParametre.texte, smsModeleAnniversairePersonnelDefaut, 'Modèle des vœux d\'anniversaire du personnel', 'Mêmes variables et mêmes interdits que le rappel.', _validee),
];
