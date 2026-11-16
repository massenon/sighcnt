// LE PLAN ANNUEL DE TRAVAIL, PAR EXERCICE (lot PTA, 16/11/2026 ; Direction : « rien ne doit rester en dur »).
//
// Port des règles pures de la maquette (`prototype_html/assets/js/data.js` : `D.PLAN`, `parcours.js` : `SIGH.planAnnuel.controler`, `core.js` : `C.referenceAnnuelle`), rejoué sur les
// vecteurs tirés de l'écran réel `m13-plan-annuel` (`prototype_html/build/vecteurs-plan-annuel.js` → `test/vecteurs/plan_annuel.json`). Aucun axe, état, exercice, signataire ni
// année n'est écrit ici : ils sont lus en base (référentiels `referentielsPlan`, exercices de la comptabilité, réglage `reglagesPlan`, paramètre `plan.graceRetardJours`).
//
// Une action est une fiche de la collection `planAnnuel` : `exercice`, `reference` (`PA-<année>-NNN`), `action`, `axe` et `avancement` (CODES des référentiels), `trimestreDebut`,
// `trimestreFin`, le responsable par RÉFÉRENCE (`responsableType` agent ou poste, `responsableRef`), `budgetPrevu`, `budgetRealise`, `budgetId`, `indicateur`, `cible`,
// `valeurAtteinte`, `tauxAvancement` (0 à 100), `version`. « Non calculable » n'est jamais zéro : un champ vide est « non renseigné ».
library;

/// Le geste réservé de la fiche RBAC qui adopte le plan d'un exercice (défaut proposé : la Direction et la Directrice Administrative).
const String paGesteAdopter = 'adopter_plan_annuel';

/// Les collections de CONFIGURATION du plan (axes et états, signataires de l'impression) : posées à la mère, reçues par les fileuls par le canal de configuration, jamais vers un téléphone.
const Set<String> paCollectionsConfiguration = {'referentielsPlan', 'reglagesPlan'};

/// Les champs qui forment le CONTENU du plan : figés après l'adoption, ils ne changent plus que par version datée.
const List<String> paChampsContenu = ['action', 'axe', 'trimestreDebut', 'trimestreFin', 'responsableType', 'responsableRef', 'budgetPrevu', 'budgetId', 'indicateur', 'cible'];

/// Les champs du SUIVI : libres même après l'adoption.
const List<String> paChampsSuivi = ['avancement', 'tauxAvancement', 'budgetRealise', 'valeurAtteinte', 'observations'];

/// Un refus nommé : code, motif, geste.
class RefusPlan {
  const RefusPlan(this.code, this.motif, this.geste);
  final String code, motif, geste;
  @override
  String toString() => '$code : $motif';
}

typedef FichePlan = Map<String, Object?>;

/// `D.PLAN.finTrimestre(debutIso, q)` : le dernier jour du trimestre [q] (1 à 4) d'un exercice qui commence le [debut] (AAAA-MM-JJ). `null` si illisible.
String? paFinTrimestre(String? debut, Object? q) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(debut ?? '');
  final n = _num(q);
  if (m == null || n == null || !(n >= 1 && n <= 4)) return null;
  // Les mois de Dart sont numérotés de 1 à 12 (ceux de JavaScript de 0 à 11) : le trimestre `n` finit la veille du premier jour du mois + 3 n.
  final fin = DateTime.utc(int.parse(m[1]!), int.parse(m[2]!) + 3 * n.toInt(), int.parse(m[3]!)).subtract(const Duration(days: 1));
  return fin.toIso8601String().substring(0, 10);
}

num? _num(Object? v) {
  if (v is num) return v;
  if (v is String && v.trim().isNotEmpty) return num.tryParse(v.trim());
  return null;
}

bool _vide(Object? v) => v == null || (v is String && v.isEmpty);

/// `D.PLAN.pourcentage(v)` : un nombre de 0 à 100 (`valeur` `null` si non renseigné, jamais 0 par défaut), ou le refus `POURCENTAGE_HORS_BORNES`.
({bool ok, num? valeur, String? code}) paPourcentage(Object? v) {
  if (_vide(v)) return (ok: true, valeur: null, code: null);
  final n = _num(v);
  if (n == null || !n.isFinite || n < 0 || n > 100) return (ok: false, valeur: null, code: 'POURCENTAGE_HORS_BORNES');
  return (ok: true, valeur: n, code: null);
}

/// `D.PLAN.nombre(v)` : `valeur` `null` si non renseigné ; `invalide` si négatif ou non numérique.
({bool invalide, num? valeur}) paNombre(Object? v) {
  if (_vide(v)) return (invalide: false, valeur: null);
  final n = _num(v);
  if (n == null || !n.isFinite || n < 0) return (invalide: true, valeur: null);
  return (invalide: false, valeur: n);
}

/// `D.PLAN.atteinteIndicateur(a)` : valeur atteinte / cible en pour cent (une décimale, non borné). Cible absente ou nulle, valeur absente : NON CALCULABLE (jamais zéro).
({bool calculable, num? pct, String? motif}) paAtteinteIndicateur(FichePlan a) {
  final cible = paNombre(a['cible']), val = paNombre(a['valeurAtteinte']);
  if (cible.invalide || cible.valeur == null || cible.valeur == 0) return (calculable: false, pct: null, motif: 'cible non définie');
  if (val.invalide || val.valeur == null) return (calculable: false, pct: null, motif: 'valeur atteinte non renseignée');
  return (calculable: true, pct: (val.valeur! / cible.valeur! * 1000).round() / 10, motif: null);
}

/// Les totaux CALCULÉS d'une liste d'actions (`D.PLAN.totaux`).
class TotauxPlan {
  TotauxPlan({required this.nb, this.prevu, this.realise, required this.nbSansPrevu, required this.nbSansRealise, this.ecart, this.tauxMoyen, required this.nbSansTaux, required this.parNature});
  final int nb, nbSansPrevu, nbSansRealise, nbSansTaux;
  final num? prevu, realise, ecart, tauxMoyen;
  final Map<String, int> parNature;
}

/// `D.PLAN.totaux(actions)` : budget prévu et réalisé sur les actions qui les portent (null s'il n'y en a aucune), écart seulement si les deux sommes existent, pourcentage moyen des
/// actions qui en portent un. [natureDe] : la nature (`planifiee`, `en_cours`, `realisee`) d'un code d'état, lue au référentiel ; `null` si l'état est inconnu.
TotauxPlan paTotaux(List<FichePlan> actions, String? Function(String code) natureDe) {
  num? prevu, realise;
  var sansPrevu = 0, sansRealise = 0, sansTaux = 0, nTaux = 0;
  num somTaux = 0;
  final nat = <String, int>{'planifiee': 0, 'en_cours': 0, 'realisee': 0, 'inconnue': 0};
  for (final a in actions) {
    final p = paNombre(a['budgetPrevu']), r = paNombre(a['budgetRealise']);
    if (p.valeur == null) {
      sansPrevu++;
    } else {
      prevu = (prevu ?? 0) + p.valeur!;
    }
    if (r.valeur == null) {
      sansRealise++;
    } else {
      realise = (realise ?? 0) + r.valeur!;
    }
    final tx = paPourcentage(a['tauxAvancement']);
    if (tx.ok && tx.valeur != null) {
      somTaux += tx.valeur!;
      nTaux++;
    } else {
      sansTaux++;
    }
    final k = natureDe('${a['avancement'] ?? ''}') ?? 'inconnue';
    nat[k] = (nat[k] ?? 0) + 1;
  }
  return TotauxPlan(
    nb: actions.length, prevu: prevu, realise: realise, nbSansPrevu: sansPrevu, nbSansRealise: sansRealise,
    ecart: (prevu != null && realise != null) ? prevu - realise : null,
    tauxMoyen: nTaux > 0 ? (somTaux / nTaux * 10).round() / 10 : null, nbSansTaux: sansTaux, parNature: nat,
  );
}

/// `D.PLAN.retard(a, debutExercice, auj, grace)` : une action non réalisée dont le dernier jour du trimestre de fin, plus la tolérance, est passé.
({bool enRetard, String? motif, String? finTrimestre, String? limite, int? jours}) paRetard(FichePlan a, String? debutExercice, String auj, int grace, String? Function(String code) natureDe) {
  final nature = natureDe('${a['avancement'] ?? ''}');
  if (nature == null || nature == 'realisee') return (enRetard: false, motif: nature == 'realisee' ? 'realisee' : 'etat_inconnu', finTrimestre: null, limite: null, jours: null);
  final fin = paFinTrimestre(debutExercice, a['trimestreFin']);
  if (fin == null) return (enRetard: false, motif: 'trimestre_illisible', finTrimestre: null, limite: null, jours: null);
  final limite = DateTime.parse('${fin}T00:00:00Z').add(Duration(days: grace)).toIso8601String().substring(0, 10);
  final jour = auj.length >= 10 ? auj.substring(0, 10) : auj;
  if (jour.compareTo(limite) <= 0) return (enRetard: false, motif: 'dans_les_delais', finTrimestre: fin, limite: limite, jours: null);
  final jours = (DateTime.parse('${jour}T00:00:00Z').difference(DateTime.parse('${fin}T00:00:00Z')).inHours / 24).round();
  return (enRetard: true, motif: null, finTrimestre: fin, limite: limite, jours: jours);
}

/// La référence `PA-<année de la date>-NNN` est celle de la FABRIQUE UNIQUE des numéros annuels (`referenceAnnuelle`, `numerotation/reference_annuelle.dart`, lot MIL) : plus aucune copie ici.

/// Ce que le contrôle d'une fiche lit en base : les exercices de la comptabilité, les codes des référentiels, les agents, les postes et les lignes de budget.
class ContextePlan {
  const ContextePlan({required this.exercices, required this.axes, required this.etats, required this.agents, required this.postes, required this.budgets});
  final Set<int> exercices;
  final Set<String> axes, etats, agents, postes, budgets;
}

/// `SIGH.planAnnuel.controler(f)` : `null` si la fiche est recevable, sinon le refus nommé (mêmes codes, même ordre que la maquette).
RefusPlan? paControler(FichePlan f, ContextePlan ctx) {
  final action = '${f['action'] ?? ''}';
  if (action.trim().length < 3) return const RefusPlan('ACTION_VIDE', 'Le libellé de l’action est obligatoire.', 'Saisir ce que l’action programme.');
  final ex = _num(f['exercice']);
  if (ex == null || !ctx.exercices.contains(ex.toInt())) return RefusPlan('EXERCICE_INCONNU', 'L’exercice « ${f['exercice']} » n’est pas un exercice de la comptabilité.', 'Choisir un exercice de la liste.');
  if (!ctx.axes.contains('${f['axe']}')) return RefusPlan('AXE_INCONNU', 'L’axe « ${f['axe']} » n’est pas dans le référentiel des axes.', 'Choisir un axe du référentiel.');
  if (!ctx.etats.contains('${f['avancement']}')) return RefusPlan('ETAT_INCONNU', 'L’état d’avancement « ${f['avancement']} » n’est pas dans le référentiel des états.', 'Choisir un état du référentiel.');
  final d = _num(f['trimestreDebut']), e = _num(f['trimestreFin']);
  if (!(d != null && e != null && d >= 1 && d <= 4 && e >= 1 && e <= 4 && d <= e)) {
    return const RefusPlan('TRIMESTRES_INCOHERENTS', 'La période doit aller d’un trimestre de début à un trimestre de fin, de T1 à T4, la fin non avant le début.', 'Corriger les trimestres.');
  }
  if (!_vide(f['responsable'])) {
    return const RefusPlan('RESPONSABLE_TEXTE_LIBRE', 'Le responsable n’est pas un texte libre : il se choisit parmi le personnel ou les postes de l’organigramme.', 'Choisir le responsable dans la liste.');
  }
  final type = f['responsableType'], ref = '${f['responsableRef']}';
  final trouve = (type == 'agent' && ctx.agents.contains(ref)) || (type == 'poste' && ctx.postes.contains(ref));
  if (!trouve) return const RefusPlan('RESPONSABLE_INCONNU', 'Le responsable désigné n’existe pas (ou n’est plus actif) au personnel ni à l’organigramme.', 'Choisir un agent ou un poste de la liste.');
  final tx = paPourcentage(f['tauxAvancement']);
  if (!tx.ok) return RefusPlan('POURCENTAGE_HORS_BORNES', 'Le pourcentage d’avancement est un nombre de 0 à 100 (reçu « ${f['tauxAvancement']} »).', 'Saisir un nombre de 0 à 100, ou laisser vide (non renseigné).');
  for (final c in const ['budgetPrevu', 'budgetRealise', 'cible', 'valeurAtteinte']) {
    if (paNombre(f[c]).invalide) return RefusPlan('MONTANT_INVALIDE', 'Le champ « $c » est un nombre positif ou nul (reçu « ${f[c]} »).', 'Saisir un nombre, ou laisser vide (non renseigné).');
  }
  if (!_vide(f['budgetId']) && !ctx.budgets.contains('${f['budgetId']}')) return const RefusPlan('BUDGET_INCONNU', 'La ligne de budget rattachée n’existe pas.', 'Choisir une ligne du module Budgets, ou « non rattaché ».');
  return null;
}

/// Ce que « Reconduire » fait de [source] vers [cible] : les actions NON RÉALISÉES (nature lue au référentiel) qui ne sont pas déjà reconduites, copiées avec le suivi remis à zéro
/// (état de nature « planifiée », `reconduiteDe`) ; `ignorees` : les références déjà reconduites ou sans responsable résolu. L'exercice source n'est jamais réécrit.
({List<FichePlan> copiees, List<String> ignorees}) paReconduire(List<FichePlan> source, List<FichePlan> cible, {required String etatPlanifie, required String? Function(String code) natureDe, required bool Function(FichePlan) responsableExiste}) {
  final deja = <String>{for (final a in cible) if (!_vide(a['reconduiteDe'])) '${a['reconduiteDe']}'};
  final copiees = <FichePlan>[];
  final ignorees = <String>[];
  for (final a in source) {
    if (natureDe('${a['avancement']}') == 'realisee') continue;
    if (deja.contains('${a['id']}')) {
      ignorees.add('${a['reference']}');
      continue;
    }
    final n = <String, Object?>{
      'action': a['action'], 'axe': a['axe'], 'trimestreDebut': a['trimestreDebut'], 'trimestreFin': a['trimestreFin'], 'avancement': etatPlanifie,
      'responsableType': a['responsableType'], 'responsableRef': a['responsableRef'], 'version': 1, 'reconduiteDe': a['id'], 'reconduiteDepuis': a['reference'],
    };
    for (final k in const ['budgetPrevu', 'budgetId', 'indicateur', 'cible']) {
      if (!_vide(a[k])) n[k] = a[k];
    }
    if (!responsableExiste(n)) {
      ignorees.add('${a['reference']} (responsable introuvable)');
      continue;
    }
    copiees.add(n);
  }
  return (copiees: copiees, ignorees: ignorees);
}
