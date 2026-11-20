/// M10, lot L7 (10/11/2026, Direction, Planning Q5, Q6, Q8) : l'espace « Mes » de l'agent, la copie de la fiche de paie pour le téléphone, « Mon assurance du
/// personnel ».
///
/// Port de `SIGH.espaceMes` (`prototype_html/assets/js/parcours.js`, fin du fichier) ; vecteurs `test/vecteurs/mes_pointage.json`, engendrés par
/// `prototype_html/build/vecteurs-mes-pointage.js`. Fonctions PURES : elles reçoivent le nom de l'acteur, le personnel et les collections lues au magasin, et
/// rendent la lecture ou un refus nommé (code, motif, geste) ; elles n'écrivent rien.
///
/// L'ESPACE LIT, IL N'ÉCRIT RIEN : chaque rubrique est filtrée sur l'agent de la session (rattaché au personnel par son NOM, comme partout), sans droit d'écran sur
/// la collection entière (RG-13). Un compte NON NOMINATIF reçoit le refus `COMPTE_NON_NOMINATIF`, jamais l'espace d'un autre.
///
/// LA COPIE DE LA FICHE DE PAIE (Q5) : les pièces ÉMISES (bulletins DIFFUSÉS) de l'agent DEMANDEUR seul, chiffrées au téléphone, jamais recalculées. Le réglage
/// `paie.copieFichePaieTelephone` (oui par défaut) la commande ; il reste NON mobile (la famille `paie` est réservée au téléphone) : le téléphone ne lit jamais le
/// réglage, c'est la mère qui décide de publier ou de retirer la copie.
library;

import 'planning_rh.dart';

typedef FicheMes = Map<String, Object?>;

class RubriqueMes {
  const RubriqueMes(this.n, this.id, this.libelle, this.ecran, {this.source, this.lien, this.calcule, this.emise = false, this.sensible = false, this.lectureSeule = false});
  final int n;
  final String id, libelle, ecran;
  final String? source, lien, calcule;
  final bool emise, sensible, lectureSeule;
}

/// Les dix-sept rubriques du PRD M10, dans l'ordre.
const List<RubriqueMes> rubriquesMes = [
  RubriqueMes(1, 'fiche_poste', 'Ma fiche de poste', 'm10-fiches-poste', source: 'fichesPoste', lien: 'poste'),
  RubriqueMes(2, 'fiche_paie', 'Ma fiche de paie', 'm11-bulletins', source: 'bulletins', lien: 'employeId', emise: true, sensible: true),
  RubriqueMes(3, 'contrat', 'Mon contrat', 'm10-contrats', source: 'contrats', lien: 'employeId', sensible: true),
  RubriqueMes(4, 'planning', 'Mes planning et gardes', 'm10-planning', source: 'planning', lien: 'employeId'),
  RubriqueMes(5, 'stats_garde', 'Mes statistiques de garde', 'm10-stats-gardes', calcule: 'garde'),
  RubriqueMes(6, 'stats_permanence', 'Mes statistiques des permanences', 'm10-stats-permanences', calcule: 'permanence'),
  RubriqueMes(7, 'taux_presence', 'Mon taux de présence par service', 'm10-stats-presence', calcule: 'presence'),
  RubriqueMes(8, 'presences', 'Mes présences et absences', 'm10-presences', source: 'presences', lien: 'employeId'),
  RubriqueMes(9, 'conges', 'Mes congés', 'm10-conges', source: 'conges', lien: 'employeId'),
  RubriqueMes(10, 'missions', 'Mes ordres de mission', 'm10-missions', source: 'missions', lien: 'agentId'),
  RubriqueMes(11, 'primes', 'Mes primes', 'm10-primes', source: 'bulletins', lien: 'employeId', emise: true, sensible: true),
  RubriqueMes(12, 'evenements', 'Événements du personnel', 'm10-evenements', source: 'evenements', lien: 'evenementsDeLAgent'),
  RubriqueMes(13, 'participations', 'Mes frais de participation', 'm10-participations', source: 'participations', lien: 'employeId'),
  RubriqueMes(14, 'assurance', 'Mon assurance du personnel', 'm10-assurance-personnel', calcule: 'assurance', lectureSeule: true),
  RubriqueMes(15, 'notes_service', 'Notes de service', 'm13-notes-service', calcule: 'notes'),
  RubriqueMes(16, 'agenda', 'Mon agenda', 'm2-agenda', source: 'consultations', lien: 'medecinId'),
  RubriqueMes(17, 'rendez_vous', 'Mes rendez-vous et visites', 'm2-rendezvous', source: 'consultations', lien: 'patientDeLAgent'),
];

/// LA GARDE SOINS COMPTE COMME GARDE (Direction, 11/11/2026, P4) : « Mes statistiques de garde » comptait la garde de 24 h (`garde`, `garde_hospi`) et laissait la garde
/// soins de 08h à 18h30 (`garde_soins`) à la seule rubrique du planning ; un agent du régime « garde soins » y lisait zéro garde.
const Map<String, List<String>> _travailMes = {
  'garde': ['garde', 'garde_hospi', 'garde_soins'],
  'permanence': ['permanence'],
};

RubriqueMes? rubriqueMes(Object? id) {
  for (final r in rubriquesMes) {
    if (r.id == id) return r;
  }
  return null;
}

/// L'agent de la session : un agent du personnel actif à ce nom, sinon `COMPTE_NON_NOMINATIF`.
({FicheMes? agent, RefusRh? refus}) agentDeMes({required String acteur, required List<FicheMes> personnelActif}) {
  for (final e in personnelActif) {
    if (e['nomComplet'] == acteur) return (agent: e, refus: null);
  }
  return (
    agent: null,
    refus: RefusRh(
        'COMPTE_NON_NOMINATIF',
        'Le compte « $acteur » ne correspond à aucun agent du personnel : l’espace « Mes » est celui d’une personne, pas d’un poste.',
        'Se connecter avec son compte nominatif (poste partagé : fermer la session de l’agent précédent).')
  );
}

/// Un montant PORTÉ est un nombre ; son absence est « non renseigné » (`null`), jamais un zéro ni le prix courant du catalogue (vague 20, Q8).
num? montantPorte(Object? v) {
  if (v == null || v == '') return null;
  final n = v is num ? v : num.tryParse('$v');
  return n != null && n.isFinite ? n : null;
}

String _jour10(Object? v) {
  final s = '${v ?? ''}';
  return s.length >= 10 ? s.substring(0, 10) : s;
}

class LigneAssurance {
  const LigneAssurance(this.id, this.nature, this.date, this.valeur);
  final String id, nature, date;
  final num? valeur;
}

class AssuranceMes {
  const AssuranceMes(this.lignes, this.total, this.sansMontant);
  final List<LigneAssurance> lignes;
  final num total;
  final int sansMontant;
}

/// Consultations, analyses et hospitalisations de l'agent soigné à 100 % (dossiers patient rattachés par `personnelId`).
AssuranceMes assuranceDeLAgent({
  required Object? agentId,
  required List<FicheMes> patients,
  required List<FicheMes> consultations,
  required List<FicheMes> demandesAnalyses,
  required List<FicheMes> admissions,
}) {
  final pids = [
    for (final p in patients)
      if (p['personnelId'] == agentId) p['id']
  ];
  final lignes = <LigneAssurance>[];
  for (final c in consultations) {
    if (pids.contains(c['patientId'])) lignes.add(LigneAssurance('${c['id']}', 'Consultation', _jour10(c['date']), montantPorte(c['tarif'])));
  }
  for (final a in demandesAnalyses) {
    if (pids.contains(a['patientId'])) {
      final montant = a['montant'] != null && a['montant'] != '' ? a['montant'] : a['prix'];
      lignes.add(LigneAssurance('${a['id']}', 'Analyse', _jour10(a['date'] ?? a['dateDemande'] ?? a['dateHeure']), montantPorte(montant)));
    }
  }
  for (final h in admissions) {
    if (pids.contains(h['patientId'])) lignes.add(LigneAssurance('${h['id']}', 'Hospitalisation', _jour10(h['dateEntree']), montantPorte(h['montant'])));
  }
  num total = 0;
  var sans = 0;
  for (final l in lignes) {
    if (l.valeur == null) {
      sans++;
    } else {
      total += l.valeur!;
    }
  }
  return AssuranceMes(lignes, total, sans);
}

class LectureMes {
  const LectureMes({this.refus, this.rubrique, this.agentId, this.lectureSeule = false, this.ids = const [], this.total = 0, this.valeur, this.sansMontant, this.presents, this.retards, this.absents});
  final RefusRh? refus;
  final String? rubrique;
  final String? agentId;
  final bool lectureSeule;
  final List<String> ids;
  final int total;
  final num? valeur;
  final int? sansMontant, presents, retards, absents;
  bool get ok => refus == null;
}

/// La lecture d'UNE rubrique par l'agent de la session. [collections] : les collections ACTIVES lues au magasin, par nom ; [notes] : les références des notes de
/// service en vigueur.
LectureMes lireMes({
  required Object? rubriqueId,
  required String acteur,
  required List<FicheMes> personnelActif,
  required Map<String, List<FicheMes>> collections,
  required List<String> notes,
}) {
  final r = rubriqueMes(rubriqueId);
  if (r == null) {
    return LectureMes(refus: RefusRh('RUBRIQUE_INCONNUE', 'La rubrique « $rubriqueId » n’existe pas.', 'Choisir l’une des dix-sept rubriques de l’espace « Mes ».'));
  }
  final a = agentDeMes(acteur: acteur, personnelActif: personnelActif);
  if (a.refus != null) return LectureMes(refus: a.refus);
  final e = a.agent!;
  final id = '${e['id']}';
  List<FicheMes> col(String nom) => collections[nom] ?? const [];
  LectureMes sortie(List<String> ids, {num? valeur, int? sansMontant, int? presents, int? retards, int? absents}) => LectureMes(
      rubrique: r.id, agentId: id, lectureSeule: r.lectureSeule, ids: ids, total: ids.length, valeur: valeur, sansMontant: sansMontant, presents: presents, retards: retards, absents: absents);

  switch (r.calcule) {
    case 'notes':
      return sortie(notes);
    case 'assurance':
      final as = assuranceDeLAgent(
          agentId: e['id'], patients: col('patients'), consultations: col('consultations'), demandesAnalyses: col('demandesAnalyses'), admissions: col('admissions'));
      return sortie([for (final l in as.lignes) l.id], valeur: as.total, sansMontant: as.sansMontant);
    case 'garde':
    case 'permanence':
      return sortie([
        for (final x in col('planning'))
          if (x['employeId'] == e['id'] && _travailMes[r.calcule]!.contains(x['type']) && (x['validationEtat'] == null || x['validationEtat'] == '' || x['validationEtat'] == 'validee')) '${x['id']}'
      ]);
    case 'presence':
      final pts = [
        for (final x in col('presences'))
          if (x['employeId'] == e['id'] && compteRh('presences', x)) x
      ];
      return sortie([for (final x in pts) '${x['id']}'],
          presents: pts.where((x) => x['etat'] == 'present').length, retards: pts.where((x) => x['etat'] == 'retard').length, absents: pts.where((x) => x['etat'] == 'absent').length);
  }
  final dossiers = [
    for (final p in col('patients'))
      if (p['personnelId'] == e['id']) p['id']
  ];
  final fiches = <String>[];
  for (final x in col(r.source!)) {
    bool garde;
    if (r.lien == 'poste') {
      garde = e['poste'] != null && e['poste'] != '' && x['intitule'] == e['poste'];
    } else if (r.lien == 'evenementsDeLAgent') {
      garde = x['beneficiaireId'] == e['id'] || col('participations').any((p) => p['evenementId'] == x['id'] && p['employeId'] == e['id']);
    } else if (r.lien == 'patientDeLAgent') {
      garde = dossiers.contains(x['patientId']);
    } else if (r.emise && x['statutBulletin'] != 'diffuse') {
      garde = false;
    } else {
      garde = '${x[r.lien]}' == '$id';
    }
    if (garde) fiches.add('${x['id']}');
  }
  return sortie(fiches);
}

class CopiePaie {
  const CopiePaie({this.refus, this.agentId, this.ids = const [], this.references = const []});
  final RefusRh? refus;
  final String? agentId;
  final List<String> ids, references;
  bool get ok => refus == null;
  int get total => ids.length;

  /// Chiffrée au téléphone, jamais recalculée à l'appareil : une pièce émise ne se réécrit pas.
  bool get chiffree => true;
  bool get recalculee => false;
}

/// La copie de la fiche de paie pour le téléphone : les pièces ÉMISES (diffusées) de l'agent DEMANDEUR, jamais celles d'un autre, jamais l'ensemble de la paie.
CopiePaie copiePaieAgent({
  required bool actif,
  required String acteur,
  required List<FicheMes> personnelActif,
  required List<FicheMes> bulletins,
  Object? agentIdDemande,
}) {
  if (!actif) {
    return const CopiePaie(
        refus: RefusRh('COPIE_PAIE_DESACTIVEE', 'La copie de la fiche de paie sur le téléphone est désactivée au poste de la mère.', 'Demander à la Directrice Administrative de l’activer (paramètres, famille Paie).'));
  }
  final a = agentDeMes(acteur: acteur, personnelActif: personnelActif);
  if (a.refus != null) return CopiePaie(refus: a.refus);
  final e = a.agent!;
  if (agentIdDemande != null && agentIdDemande != '' && '$agentIdDemande' != '${e['id']}') {
    return const CopiePaie(
        refus: RefusRh('COPIE_PAIE_AUTRE_AGENT', 'Une copie de fiche de paie ne se délivre qu’à l’agent concerné : celle d’un autre agent n’est jamais descendue (RG-13).', 'L’agent demande sa propre copie depuis son compte.'));
  }
  final pieces = [
    for (final b in bulletins)
      if ('${b['employeId']}' == '${e['id']}' && b['statutBulletin'] == 'diffuse') b
  ];
  return CopiePaie(agentId: '${e['id']}', ids: [for (final b in pieces) '${b['id']}'], references: [for (final b in pieces) '${b['reference']}']);
}

/// Le réglage de la copie se fait par l'administrateur ou la Directrice Administrative : `null` si permis.
RefusRh? controlerReglageCopiePaie(String role) => role == 'admin' || role == 'da'
    ? null
    : const RefusRh('REGLAGE_RESERVE', 'Ce réglage se fait par l’administrateur ou la Directrice Administrative.', 'Demander à la Directrice Administrative.');
