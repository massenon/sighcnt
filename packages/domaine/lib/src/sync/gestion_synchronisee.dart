// LOT SYNC-CFG (décision 26 de la Direction, 15/11/2026, section AH) : les BUDGETS, les IMMOBILISATIONS et les COUVERTURES D'ASSURANCE se synchronisent. Un import ou une saisie chez un
// fileul ne reste plus local à ce poste (constat 3 du lot 8b, E2637 point 6).
//
// FAMILLE A (fiche descriptive, champ à champ), pas B (ajout seul) : une couverture est une VERSION datée lue à la date de la pièce (RG-09), mais la version en cours se CLÔT la veille de
// la suivante (son champ `fin` s'écrit sur la même fiche, `assChangerCouverture`) ; un budget se corrige à l'écran « Budgets » ; un bien se cède, change d'état ou s'archive (RG-14). En
// famille B, chacun de ces gestes serait refusé (`journal_immuable`) et la couverture précédente resterait ouverte chez les autres postes : deux couvertures en vigueur à la fois.
// Une pièce émise reste lue à SA date : la version neuve s'ajoute, jamais une réécriture de l'ancienne au delà de sa fin.
//
// IDENTITÉ COMMUNE PAR LE CONTENU : deux postes qui écrivent la même chose (le même fichier importé deux fois, mère coupée ; le même budget saisi aux deux postes) ne font qu'UNE fiche, et
// le rejeu d'une opération est sans effet (clé d'opération à la mère). La clé est celle que le domaine tient déjà pour unique :
//  - budget : exercice, centre de coûts, nature (le jeu d'import refuse un second budget de ce trio) ;
//  - immobilisation : désignation, date d'acquisition, valeur (le jeu d'import refuse un « bien identique ») ;
//  - couverture : l'assuré (son identité de synchronisation) et la date d'effet (le jeu d'import ne pose qu'une couverture par assuré et par date d'effet).
// Le numéro affiché (BG-AAAA-NNN, IM-NNN) n'entre pas dans l'identité : il est attribué par chaque poste, deux postes coupés de la mère peuvent attribuer le même à deux fiches différentes
// (dit en section AN, proposition à valider).
library;

import 'dart:convert';

import '../fichiers/sha256.dart';

/// Les trois collections de gestion que le pont du poste synchronise depuis ce lot (famille A à la mère).
// Lot PLAN-INDIV (16/11/2026) : le PLANNING PERSONNALISÉ d'un agent voyage entre postes lui aussi (famille A, identité commune par le contenu : l'agent et la date d'effet), jamais vers un
// téléphone (RG-13 : aucune donnée RH de la clinique sur un appareil mobile hors espace de l'agent). Une version est figée : deux postes qui la définissent à l'identique n'en font qu'une.
const Set<String> collectionsGestionSynchronisees = {'budgets', 'immobilisations', 'couverturesAssurance', 'planningsPersonnalises'};

/// Elles ne vont JAMAIS vers un téléphone (RG-13) : la comptabilité et l'assurance d'un patient ne sont lues par aucun écran du mobile ; un téléphone perdu n'emporte ni budget, ni
/// patrimoine, ni police d'assurance.
const Set<String> collectionsGestionJamaisMobile = collectionsGestionSynchronisees;

/// Le code du refus d'un lot de tournée qui nomme l'une d'elles.
const String codeGestionInterditeAuMobile = 'gestion_interdite_au_mobile';

String _norme(Object? v) => '${v ?? ''}'.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String _jour(Object? v) {
  final s = '${v ?? ''}';
  return s.length >= 10 ? s.substring(0, 10) : s;
}

String _empreinte(List<Object?> parts) => sha256Octets(utf8.encode(parts.map(_norme).join('|'))).substring(0, 20);

/// L'identité de synchronisation COMMUNE d'une fiche de [collection] créée sur un poste, tirée de son contenu ; `null` si la collection n'est pas de ce lot ou si la clé manque (la fiche
/// garde alors l'identité propre à son poste, jamais une identité inventée). [patientSync] : l'identité de synchronisation de l'assuré (son identifiant local n'est pas le même sur tous
/// les postes pour un dossier créé chez un fileul) ; à défaut, `patientId`.
String? identiteSyncGestion(String collection, Map<String, Object?> f, {String? patientSync}) {
  switch (collection) {
    case 'budgets':
      if ('${f['exercice'] ?? ''}'.isEmpty || '${f['centreCout'] ?? ''}'.isEmpty || '${f['nature'] ?? ''}'.isEmpty) return null;
      return 'BUD-${f['exercice']}-${_empreinte([f['centreCout'], f['nature']])}';
    case 'immobilisations':
      if ('${f['designation'] ?? ''}'.isEmpty || '${f['dateAcquisition'] ?? ''}'.isEmpty) return null;
      return 'IMM-${_empreinte([f['designation'], _jour(f['dateAcquisition']), f['valeurAcquisition']])}';
    case 'planningsPersonnalises':
      final agent = '${f['matricule'] ?? ''}'.isNotEmpty ? '${f['matricule']}' : '${f['employeId'] ?? ''}';
      if (agent.isEmpty || '${f['dateEffet'] ?? ''}'.isEmpty) return null;
      return 'PPE-${_empreinte([agent, _jour(f['dateEffet'])])}';
    case 'couverturesAssurance':
      final p = (patientSync == null || patientSync.isEmpty) ? '${f['patientId'] ?? ''}' : patientSync;
      if (p.isEmpty) return null;
      return 'COU-${_empreinte([p, _jour(f['debut'])])}';
  }
  return null;
}
