/// Le profil SOIGNANT du mobile : agenda du jour, dossier en lecture, constantes, notes de consultation, prescription selon droits (spec §11).
///
/// Dart pur (aucun import Flutter) : le MÊME service tourne dans l'application, dans les tests d'écran (source en mémoire) et dans le test de
/// bout en bout contre le banc de synchronisation (source = le vrai moteur `Mobile` de `sigh_sync`).
///
/// Les règles ne sont écrites nulle part ici : ce service LIT le lot, appelle `packages/domaine` (`mob_regles.dart`) pour contrôler et construire
/// la fiche, puis écrit UNE opération par geste (`creer`, jamais de suppression : RG-14). Aucune action anonyme (RG-12) : sans agent nommé,
/// rien ne s'écrit.
library;

import 'package:sigh_domaine/sigh_domaine.dart';

/// Une fiche du lot, telle que le moteur la livre.
class LigneLot {
  const LigneLot(this.id, this.data, {this.archive = false});
  final String id;
  final Map<String, Object?> data;
  final bool archive;
}

class FichePatient {
  const FichePatient({required this.id, required this.champs});
  final String id;
  final Map<String, Object?> champs;
  String get code => '${champs['code'] ?? 'en attente de numéro'}';
  String get nom => '${champs['nom'] ?? ''} ${champs['prenom'] ?? ''}'.trim();
}

/// Ce que le service sait du moteur : lire une collection (envolées comprises), écrire une fiche, connaître la fin du lot.
abstract class SourceMobile {
  Future<List<LigneLot>> liste(String collection);

  /// Écrit une opération `creer` ; rend l'identifiant de la fiche.
  Future<String> creer(String collection, Map<String, Object?> champs);

  /// Fin de validité du lot (millisecondes d'époque), 0 ou null si aucun lot n'a été reçu.
  Future<int?> lotExpire();
}

/// Qui agit : son nom (RG-12) et sa fonction (elle décide des commandes offertes ET du contrôle refait à l'écriture).
class SessionSoignant {
  const SessionSoignant({required this.agent, required this.fonction});
  final String agent;
  final String fonction;
  String get libelleFonction => mobLibelleFonction(fonction);
}

/// Une ligne de l'agenda du jour.
class LigneAgenda {
  const LigneAgenda({required this.heure, required this.patient, required this.patientId, required this.motif, required this.type, required this.statut, required this.enSouffrance, required this.jour});
  final String heure, patient, motif, type, statut, jour;
  final String? patientId;
  final bool enSouffrance;
}

class AgendaDuJour {
  const AgendaDuJour(this.duJour, this.enSouffrance);
  final List<LigneAgenda> duJour, enSouffrance;
}

/// Le dossier en lecture : le résumé du domaine, la fiche brute et le rendez-vous du jour (le motif de la visite).
class DossierLu {
  const DossierLu({required this.patientId, required this.fiche, required this.resume, this.rendezVous, this.transcriptions = const {}});
  final String patientId;

  /// Où en est chaque prescription du dossier au poste de la clinique (clé : identifiant de la pièce) : en attente, transcrite ou refusée (E1559).
  final Map<String, MobTranscription> transcriptions;
  final Map<String, Object?> fiche;
  final MobDossier resume;
  final LigneAgenda? rendezVous;
}

const _libellesStatut = {
  'planifiee': 'Planifiée',
  'en_cours': 'En cours',
  'terminee': 'Terminée',
  'reporte': 'Reportée',
  'non_honore': 'Non honorée',
};

class ServiceSoignant {
  ServiceSoignant(this.source, {required this.session, DateTime Function()? maintenant}) : _maintenant = maintenant ?? DateTime.now;

  final SourceMobile source;
  final SessionSoignant session;
  final DateTime Function() _maintenant;

  DateTime get maintenant => _maintenant();

  // --- commandes offertes (une commande interdite est ABSENTE) -----------------------------------------------------------------------------

  bool get peutSaisirNote => mobEcranOuvert(session.fonction, 'consultation');

  /// Les natures offertes à la prescription : habilitation de la fonction ET écran ouvert au profil. Vide : la commande n'existe pas.
  List<String> get naturesPrescriptibles => mobNaturesPrescriptibles(session.fonction);

  /// Le catalogue des médicaments du lot (le téléphone CHOISIT, il ne tape plus un nom) : vide pour une fonction qui ne prescrit pas, le lot n'en porte alors aucun.
  Future<List<MobProduit>> produits() async => mobProduitsPrescriptibles([for (final l in await _actives('produits')) {...l.data, 'id': l.id}]);

  // --- lecture ----------------------------------------------------------------------------------------------------------------------------

  Future<List<LigneLot>> _actives(String c) async => [
        for (final l in await source.liste(c))
          if (!l.archive) l
      ];

  Future<List<FichePatient>> patients() async => [for (final l in await _actives('patients')) FichePatient(id: l.id, champs: l.data)];

  Future<FichePatient> _patient(String id) async {
    for (final p in await patients()) {
      if (p.id == id) return p;
    }
    throw RefusMobile('PATIENT_HORS_LOT', 'Ce patient n’est pas dans le lot de ce téléphone.', 'Recevoir le lot du jour à la prochaine synchronisation');
  }

  List<Map<String, Object?>> _avecId(List<LigneLot> l) => [for (final x in l) {...x.data, 'id': x.id}];

  LigneAgenda _ligne(Map<String, Object?> r, List<FichePatient> patients, {required bool souffrance}) {
    FichePatient? p;
    for (final x in patients) {
      if (x.id == r['patientId'] || (r['patientCode'] != null && x.champs['code'] == r['patientCode'])) p = x;
    }
    final nom = p?.nom ?? '${r['patient'] ?? r['visiteurNom'] ?? 'Personne non enregistrée'}';
    return LigneAgenda(
      heure: mobHeureRendezVous(r),
      patient: nom,
      patientId: p?.id,
      motif: '${r['motif'] ?? ''}',
      type: '${r['type'] ?? ''}',
      statut: _libellesStatut['${r['statut']}'] ?? '${r['statut'] ?? ''}',
      enSouffrance: souffrance,
      jour: dateFR(DateTime.tryParse('${r['date']}')?.toLocal() ?? maintenant),
    );
  }

  /// L'agenda du jour, lu dans le lot : les rendez-vous d'aujourd'hui du plus tôt au plus tard ; les planifiés d'un jour passé sont signalés à part.
  Future<AgendaDuJour> agenda() async {
    final pats = await patients();
    final rdv = [for (final l in await _actives('rendezvous')) l.data];
    final a = mobAgendaDuJour(rdv, maintenant);
    return AgendaDuJour(
      [for (final r in a.duJour) _ligne(r, pats, souffrance: false)],
      [for (final r in a.enSouffrance) _ligne(r, pats, souffrance: true)],
    );
  }

  /// Le dossier d'un patient du lot, en LECTURE seule.
  Future<DossierLu> dossier(String patientId) async {
    final p = await _patient(patientId);
    final resume = mobDossier(
      patient: p.champs,
      patientId: patientId,
      maintenant: maintenant,
      constantes: [for (final l in await _actives('constantes')) l.data],
      notes: [for (final l in await _actives('notes')) l.data],
      prescriptions: [for (final l in await _actives('prescriptions')) {...l.data, 'id': l.id}],
    );
    final comptes = [for (final l in await _actives('transcriptions')) l.data];
    final transcriptions = {for (final p in resume.prescriptions) '${p['id']}': mobTranscriptionDe('${p['id']}', comptes)};
    final ag = await agenda();
    LigneAgenda? rdv;
    for (final l in ag.duJour) {
      if (l.patientId == patientId) rdv ??= l;
    }
    return DossierLu(patientId: patientId, fiche: p.champs, resume: resume, rendezVous: rdv, transcriptions: transcriptions);
  }

  // --- écriture : un geste = une opération --------------------------------------------------------------------------------------------------

  /// Contrôles communs : un agent nommé (RG-12), un lot encore valide, un patient du lot.
  Future<FichePatient> _preparer(String patientId) async {
    if (session.agent.trim().isEmpty) {
      throw const RefusMobile('ACTEUR_INCONNU', 'Aucune action anonyme : le nom de l’agent n’est pas renseigné sur ce téléphone (RG-12).', 'Réappairer le téléphone en indiquant l’agent');
    }
    mobControlerLot(await source.lotExpire(), maintenant);
    return _patient(patientId);
  }

  Future<String> enregistrerConstantes(String patientId, Map<String, String> saisie) async {
    final p = await _preparer(patientId);
    final champs = mobChampsConstantes(patient: p.champs, patientId: patientId, saisie: saisie, acteur: session.agent, maintenant: maintenant);
    return source.creer('constantes', champs);
  }

  Future<String> enregistrerNote(String patientId, Map<String, String> saisie) async {
    if (!peutSaisirNote) {
      throw RefusMobile('ECRAN_FERME_AU_PROFIL', '${session.libelleFonction} : la consultation à domicile n’est pas ouverte à ce profil.', 'Utiliser un poste de la clinique');
    }
    final p = await _preparer(patientId);
    final champs = mobChampsNote(
      patient: p.champs,
      patientId: patientId,
      saisie: saisie,
      acteur: session.agent,
      fonction: session.fonction,
      maintenant: maintenant,
      constantes: [for (final l in await _actives('constantes')) l.data],
    );
    return source.creer('notes', champs);
  }

  Future<String> _noteDuJour(String patientId, String nature) async {
    final notes = _avecId(await _actives('notes'));
    mobControlerPrescription(
      fonction: session.fonction,
      nature: nature,
      patientId: patientId,
      notes: notes,
      maintenant: maintenant,
      lotExpire: await source.lotExpire(),
    );
    return '${mobNoteDuJour(notes, patientId, maintenant)!['id']}';
  }

  /// Prescrit un médicament. Le contrôle (fonction, écran, note du jour, lot) est REFAIT ici : un bouton absent ne protège rien.
  Future<String> prescrireMedicament(String patientId, Map<String, String> saisie) async {
    final p = await _preparer(patientId);
    final noteId = await _noteDuJour(patientId, 'medicament');
    final champs = mobChampsOrdonnance(
        patient: p.champs, patientId: patientId, noteId: noteId, saisie: saisie, acteur: session.agent, fonction: session.fonction, maintenant: maintenant, produits: [for (final l in await _actives('produits')) {...l.data, 'id': l.id}]);
    return source.creer('prescriptions', champs);
  }

  /// Demande des analyses. Rien ne se prélève avant le paiement : la demande part, le patient règle à la caisse de la clinique.
  Future<String> prescrireAnalyses(String patientId, List<String> examens, String urgence) async {
    final p = await _preparer(patientId);
    final noteId = await _noteDuJour(patientId, 'analyse');
    final champs = mobChampsDemandeAnalyses(
        patient: p.champs, patientId: patientId, noteId: noteId, examens: examens, urgence: urgence, acteur: session.agent, fonction: session.fonction, maintenant: maintenant);
    return source.creer('prescriptions', champs);
  }
}
