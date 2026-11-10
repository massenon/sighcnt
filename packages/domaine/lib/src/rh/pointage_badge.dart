/// M10, lot L8 (10/11/2026, Direction, Planning Q7) : le badge sert de POINTAGE.
///
/// Port de `SIGH.pointageBadge` (`prototype_html/assets/js/modules/m10-rh.js`, à côté du verdict du badge) ; vecteurs `test/vecteurs/mes_pointage.json`, engendrés par
/// `prototype_html/build/vecteurs-mes-pointage.js` (le moteur de la maquette piloté dans Chrome). Fonctions PURES : elles reçoivent les fiches lues au magasin, le
/// rôle, l'instant (`jour` AAAA-MM-JJ, `heure` HH:MM) et les réglages ; elles rendent ce qu'il faut écrire ou un refus nommé (code, motif, geste) ; elles n'écrivent
/// rien et ne lisent jamais l'horloge. L'appelant écrit, journalise (RG-12) et met en file de synchronisation.
///
/// Décision du 09/11/2026 (la remarque l'emporte sur la case « différer ») : réglage oui par défaut (`planning.badgeSertDePointage`), relié au registre des présences :
/// un badge vérifié VALIDE crée une présence « à valider » (arrivée, puis départ au passage suivant) qui suit le circuit du lot L5 et ne compte pas tant qu'elle n'est
/// pas validée (RG-11). Le QR ne porte que le matricule et le numéro de série (vague 54) : la vérification passe par le logiciel, qui lit le badge au registre. Le DÉLAI
/// entre deux pointages est un paramètre en base (`planning.delaiEntrePointagesBadge`) : aucun document ne le fixe, le défaut de 5 minutes est une PROPOSITION « à
/// valider ». Le badge n'infère PAS le retard (aucune heure d'arrivée attendue n'est documentée) : l'état naît « présent », le surveillant régularise s'il y a lieu.
library;

import 'planning_rh.dart';
import 'rhc_regles.dart';

/// Le délai d'attente entre deux pointages, en minutes : valeur d'attente, à valider par la Direction.
const int delaiPointageBadgeDefaut = 5;

/// Les rôles qui pointent un badge : ceux de l'écran de vérification qui peuvent agir (surveillant, DAF, Direction, administrateur, RH).
const List<String> rolesPointageBadge = ['surveillant', 'da', 'admin', 'direction', 'rh'];

/// Le résultat d'un pointage : un refus nommé, ou le geste (`arrivee` ou `depart`) avec la fiche à écrire.
class ResultatPointage {
  const ResultatPointage.refuse(RefusRh this.refus)
      : ok = false,
        geste = null,
        agentId = null,
        badgeId = null,
        heure = null,
        etat = null,
        presenceId = null,
        creation = null,
        patch = null;
  const ResultatPointage.ok({
    required String this.geste,
    required String this.agentId,
    required String this.badgeId,
    required String this.heure,
    required String this.etat,
    this.presenceId,
    this.creation,
    this.patch,
  })  : ok = true,
        refus = null;
  final bool ok;
  final RefusRh? refus;
  final String? geste, agentId, badgeId, heure, etat, presenceId;

  /// Arrivée : la présence à créer (sans identifiant).
  final Map<String, Object?>? creation;

  /// Départ : les champs à poser sur la présence ouverte.
  final Map<String, Object?>? patch;
}

/// Le réglage « délai » est-il admissible ? Un entier de minutes, de 0 à 720 ; sinon le refus nommé `DELAI_INVALIDE`.
RefusRh? controlerReglagePointageBadge({required String role, Object? delai}) {
  if (role != 'admin' && role != 'da') {
    return const RefusRh('REGLAGE_RESERVE', 'Ce réglage se fait par l’administrateur ou la Directrice Administrative.', 'Demander à la Directrice Administrative.');
  }
  final n = delai is num ? delai : (delai is String && delai.trim().isNotEmpty ? num.tryParse(delai) : null);
  if (n == null || !n.isFinite || n < 0 || n != n.floor() || n > 720) {
    return const RefusRh('DELAI_INVALIDE', 'Le délai entre deux pointages est un nombre entier de minutes, de 0 à 720.', 'Saisir un nombre entier de minutes.');
  }
  return null;
}

int? _minutesHeure(Object? h) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch('${h ?? ''}');
  return m == null ? null : int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
}

String _hhmm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

/// Présente un badge au pointage. [badges] : TOUTES les fiches de la collection (archivées comprises : la fiche d'un badge perdu est celle qu'on ressort) ;
/// [personnel] : tout le personnel ; [presences] : les présences ACTIVES (le jour est filtré ici).
ResultatPointage pointerParBadge({
  required String role,
  required bool actif,
  required int delai,
  required String texte,
  required String jour,
  required String heure,
  required List<Map<String, Object?>> badges,
  required List<Map<String, Object?>> personnel,
  required List<Map<String, Object?>> presences,
  required String acteur,
  required String aujourdhui,
}) {
  ResultatPointage refus(String code, String motif, String geste, [Map<String, Object?> extra = const {}]) => ResultatPointage.refuse(RefusRh(code, motif, geste, extra));

  if (!rolesPointageBadge.contains(role)) {
    return refus('POINTAGE_RESERVE', 'Le pointage par badge se fait au poste d’un habilité (surveillant, Directrice Administrative, Direction, administrateur).', 'Présenter le badge à un habilité.');
  }
  if (!actif) {
    return refus('POINTAGE_DESACTIVE', 'Le badge ne sert pas de pointage : le réglage est coupé au poste de la mère.',
        'Vérifier le badge seulement, ou demander à la Directrice Administrative d’activer le pointage par badge.');
  }
  final lu = rhcLireBadgeQR(texte);
  if (lu == null) return refus('BADGE_ILLISIBLE', 'Aucun numéro de badge n’a été lu.', 'Scanner le badge ou saisir son numéro de série.');
  final b = rhcBadgeDuNumero(badges, lu.numero);
  final v = rhcVerdictBadge(b, DateTime.parse(jour));
  if (v.code != 'valide') {
    const codes = {'inconnu': 'BADGE_INCONNU', 'retire': 'BADGE_RETIRE', 'expire': 'BADGE_EXPIRE', 'non_remis': 'BADGE_NON_REMIS'};
    return refus(codes[v.code] ?? 'BADGE_REFUSE', '${v.label}. ${v.message}',
        v.code == 'expire' ? 'Faire rééditer le badge, et déclarer la présence au registre.' : 'Ne pas pointer ; déclarer la présence au registre, ou signaler le badge à la RH.');
  }
  final badge = b!;
  final matBadge = '${badge['matricule'] ?? ''}';
  if (lu.matricule != null && matBadge.isNotEmpty && lu.matricule != matBadge) {
    return refus('BADGE_INCOHERENT', 'Le code présenté annonce le matricule ${lu.matricule}, le registre porte le matricule $matBadge pour ce numéro de série.', 'Retenir le badge et le signaler à la RH.');
  }
  Map<String, Object?>? agent;
  for (final e in personnel) {
    if (e['id'] == badge['personnelId']) agent = e;
  }
  if (agent == null || agent['statut'] == 'archive') return refus('AGENT_INTROUVABLE', 'L’agent de ce badge n’existe plus au personnel.', 'Signaler le badge à la RH.');
  final nom = '${agent['nomComplet']}';

  final duJour = [
    for (final p in presences)
      if (p['statut'] != 'archive' && p['employeId'] == agent['id'] && p['date'] == jour) p
  ];
  final h = _minutesHeure(heure) ?? 0;
  int? dernier;
  for (final x in duJour) {
    for (final t in [x['heureArrivee'], x['heureDepart']]) {
      final m = _minutesHeure(t);
      if (m != null && (dernier == null || m > dernier)) dernier = m;
    }
  }
  if (dernier != null && delai > 0 && h - dernier < delai) {
    return refus(
        'POINTAGE_TROP_RAPPROCHE',
        'Deux pointages de $nom à moins de $delai minute${delai > 1 ? 's' : ''} d’intervalle : le dernier date de ${_hhmm(dernier)}.',
        'Attendre ${delai - (h - dernier)} minute(s) avant de pointer de nouveau.',
        {'delai': delai});
  }
  Map<String, Object?>? ouverte, autre;
  for (final x in duJour) {
    final arr = x['heureArrivee'];
    final dep = x['heureDepart'];
    if (ouverte == null && arr != null && arr != '' && (dep == null || dep == '')) ouverte = x;
    if (autre == null && (arr == null || arr == '')) autre = x;
  }
  if (ouverte != null) {
    if (ouverte['validationEtat'] == 'valide') {
      return refus('POINTAGE_PRESENCE_VALIDEE', 'La présence du jour de $nom est déjà validée : un pointage validé ne se modifie pas.',
          'La régulariser au registre des présences (motif, date et auteur consignés).');
    }
    return ResultatPointage.ok(
        geste: 'depart',
        agentId: '${agent['id']}',
        badgeId: '${badge['id']}',
        heure: heure,
        etat: etatValidationRh('presences', ouverte),
        presenceId: '${ouverte['id']}',
        patch: {'heureDepart': heure, 'departParBadge': badge['id']});
  }
  if (duJour.isNotEmpty) {
    return refus(
        autre != null ? 'POINTAGE_PRESENCE_EXISTANTE' : 'POINTAGE_JOURNEE_COMPLETE',
        autre != null ? 'Une présence du jour est déjà portée pour $nom (${autre['etat']}) sans heure d’arrivée.' : 'L’arrivée et le départ de $nom sont déjà pointés aujourd’hui.',
        autre != null ? 'La régulariser au registre des présences.' : 'Aucun pointage de plus aujourd’hui ; régulariser au registre si une heure est fausse.');
  }
  return ResultatPointage.ok(geste: 'arrivee', agentId: '${agent['id']}', badgeId: '${badge['id']}', heure: heure, etat: 'a_valider', creation: {
    'date': jour,
    'employeId': agent['id'],
    'employe': agent['nomComplet'],
    'matricule': agent['matricule'],
    'service': agent['service'],
    'etat': 'present',
    'heureArrivee': heure,
    'origine': 'badge',
    'badgeId': badge['id'],
    'badgeNumero': badge['numero'],
    'validationEtat': 'a_valider',
    'etapesFaites': <Object?>[],
    'saisiPar': acteur,
    'saisiLe': aujourdhui,
  });
}
