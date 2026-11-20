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
///
/// LOT PTA (16/11/2026) : le PLAN ANNUEL DE TRAVAIL (`planAnnuel`) et son ADOPTION par la Direction (`adoptionsPlan`) rejoignent ces collections, pour la même raison : famille A (une action se
/// SUIT champ à champ, état, pourcentage, réalisé, par un responsable sur son poste ; l'adoption est une fiche ajoutée une fois), identité par le contenu, jamais vers un téléphone.
///  - action : exercice, libellé normalisé, version (une révision après adoption est une AUTRE identité : elle ne fusionne pas avec la version qu'elle remplace) ;
///  - adoption : l'exercice (une adoption par exercice : la seconde, écrite sur un autre poste, fusionne ; une date ou un motif différents sont un conflit nommé, jamais écrasés).
/// Les référentiels du plan (`referentielsPlan`) et le réglage des signataires (`reglagesPlan`) sont de la CONFIGURATION de la mère : ils voyagent par le canal de configuration, pas ici.
///
/// LOT TIERS (16/11/2026) : la FACTURE À UN TIERS PAYEUR et ses quatre pièces voyagent aussi (famille A : un brouillon se complète champ à champ, la décision de l'AIB puis l'émission s'écrivent sur la même
/// fiche ; un lettrage se défait par archive), identité par le contenu, jamais vers un téléphone (RG-13 : créance, IFU d'entreprise et prestations d'un patient ne se lisent pas sur un téléphone).
///  - tiers : son code et la date d'effet de la version (une version est figée) ;
///  - facture : le tiers, la date et les prestations rattachées (`sourcesCle` : numéro de la facture du patient, ligne, montant), jamais le numéro affiché FT-AAAA-nnnn (attribué par chaque poste) ;
///  - avoir : le numéro de la facture annulée (un seul avoir par pièce) ; règlement : le tiers, la date, le montant et la référence du paiement ; lettrage : la référence du règlement et la facture lettrée.
/// Une pièce émise ne se réécrit jamais (`refusRejeuFactureTiers`, tenu par la mère au rejeu comme par le magasin du poste).
const Set<String> collectionsTiersSynchronisees = {'tiersPayeurs', 'facturesTiers', 'avoirsTiers', 'reglementsTiers', 'lettragesTiers'};
const Set<String> collectionsGestionSynchronisees = {'budgets', 'immobilisations', 'couverturesAssurance', 'planAnnuel', 'adoptionsPlan', 'planningsPersonnalises', ...collectionsTiersSynchronisees};

/// Elles ne vont JAMAIS vers un téléphone (RG-13) : la comptabilité et l'assurance d'un patient ne sont lues par aucun écran du mobile ; un téléphone perdu n'emporte ni budget, ni
/// patrimoine, ni police d'assurance.
const Set<String> collectionsGestionJamaisMobile = {...collectionsGestionSynchronisees, 'referentielsPlan', 'reglagesPlan'};

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
    case 'planAnnuel':
      if ('${f['exercice'] ?? ''}'.isEmpty || '${f['action'] ?? ''}'.trim().isEmpty) return null;
      return 'PTA-${f['exercice']}-${_empreinte([f['action']])}-v${f['version'] ?? 1}';
    case 'adoptionsPlan':
      if ('${f['exercice'] ?? ''}'.isEmpty) return null;
      return 'ADP-${f['exercice']}';
    case 'tiersPayeurs':
      if ('${f['code'] ?? ''}'.isEmpty || '${f['dateEffet'] ?? ''}'.isEmpty) return null;
      return 'TPY-${_empreinte([f['code'], _jour(f['dateEffet'])])}';
    case 'facturesTiers':
      if ('${f['tiersCode'] ?? ''}'.isEmpty || '${f['sourcesCle'] ?? ''}'.isEmpty || '${f['date'] ?? ''}'.isEmpty) return null;
      return 'FTP-${_empreinte([f['tiersCode'], _jour(f['date']), f['sourcesCle']])}';
    case 'avoirsTiers':
      if ('${f['sourcesCle'] ?? ''}'.isEmpty) return null;
      return 'ATP-${_empreinte([f['sourcesCle']])}';
    case 'reglementsTiers':
      if ('${f['tiersCode'] ?? ''}'.isEmpty || '${f['referencePaiement'] ?? ''}'.isEmpty || '${f['montant'] ?? ''}'.isEmpty) return null;
      return 'RTP-${_empreinte([f['tiersCode'], _jour(f['date']), f['montant'], f['referencePaiement']])}';
    case 'lettragesTiers':
      if ('${f['reglementRef'] ?? ''}'.isEmpty || '${f['factureNumero'] ?? ''}'.isEmpty) return null;
      return 'LTP-${_empreinte([f['tiersCode'], f['reglementRef'], f['factureNumero'], f['montant']])}';
    case 'couverturesAssurance':
      final p = (patientSync == null || patientSync.isEmpty) ? '${f['patientId'] ?? ''}' : patientSync;
      if (p.isEmpty) return null;
      return 'COU-${_empreinte([p, _jour(f['debut'])])}';
  }
  return null;
}
