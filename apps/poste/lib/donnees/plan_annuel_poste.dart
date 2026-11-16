import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:sigh_domaine/sigh_domaine.dart';

import 'magasin.dart';

/// LE PLAN ANNUEL DE TRAVAIL au poste (lot PTA, 16/11/2026 ; Direction : « rien ne doit rester en dur »). La colle entre le domaine (`plan_annuel.dart`, rejoué sur les vecteurs tirés
/// de l'écran réel de la maquette) et le magasin du poste : contrôle d'une fiche, GARDE de la collection (le moteur refuse aussi : masquer un bouton ne protège rien), adoption par la
/// Direction (geste réservé), version datée après adoption, reconduction, signataires lus au paramétrage, alertes de retard. Aucun axe, état, exercice, signataire ni année n'est écrit
/// ici : tout se lit en base.

bool _interne = false;

/// L'exercice (fiche `exercices`) de l'année [annee], ou `null`.
Fiche? exercicePlan(Magasin m, Object? annee) {
  final a = annee is num ? annee.toInt() : int.tryParse('$annee');
  for (final f in m.collection('exercices').actives) {
    if ((f['annee'] is num ? (f['annee'] as num).toInt() : int.tryParse('${f['annee']}')) == a) return f;
  }
  return null;
}

/// Les exercices de la comptabilité, du plus ancien au plus récent.
List<Fiche> exercicesPlan(Magasin m) => [...m.collection('exercices').actives]..sort((a, b) => '${a['annee']}'.compareTo('${b['annee']}'));

/// Les fiches d'un référentiel du plan (`axe` ou `etat`), par ordre.
List<Fiche> referentielPlan(Magasin m, String type) =>
    [for (final f in m.collection('referentielsPlan').actives) if (f['type'] == type) f]..sort((a, b) => ((a['ordre'] as num?) ?? 0).compareTo((b['ordre'] as num?) ?? 0));

/// La nature (`planifiee`, `en_cours`, `realisee`) d'un code d'état, lue au référentiel ; `null` si inconnu.
String? Function(String) natureDeEtatPlan(Magasin m) {
  final nat = {for (final e in referentielPlan(m, 'etat')) '${e['code']}': '${e['nature']}'};
  return (c) => nat[c];
}

ContextePlan contextePlan(Magasin m) => ContextePlan(
      exercices: {for (final f in exercicesPlan(m)) if (f['annee'] is num) (f['annee'] as num).toInt()},
      axes: {for (final f in referentielPlan(m, 'axe')) '${f['code']}'},
      etats: {for (final f in referentielPlan(m, 'etat')) '${f['code']}'},
      agents: {for (final f in m.collection('personnel').actives) '${f['id']}'},
      postes: {for (final f in m.collection('postes').actives) '${f['id']}'},
      budgets: {for (final f in m.collection('budgets').actives) '${f['id']}'},
    );

List<Fiche> actionsPlan(Magasin m, Object? annee) => [for (final f in m.collection('planAnnuel').actives) if ('${f['exercice']}' == '$annee') f];

Fiche? adoptionPlan(Magasin m, Object? annee) {
  for (final f in m.collection('adoptionsPlan').actives) {
    if ('${f['exercice']}' == '$annee') return f;
  }
  return null;
}

/// Le responsable d'une action, LU (jamais stocké) : agent du personnel ou poste de l'organigramme ; `null` si la référence ne se résout plus.
String? libelleResponsablePlan(Magasin m, Fiche a) {
  if (a['responsableType'] == 'agent') {
    final p = m.collection('personnel').parId(a['responsableRef']);
    if (p == null || p['statut'] == 'archive') return null;
    final poste = '${p['poste'] ?? ''}';
    return '${p['nomComplet']}${poste.isEmpty ? '' : ' ($poste)'}';
  }
  if (a['responsableType'] == 'poste') {
    final f = m.collection('postes').parId(a['responsableRef']);
    if (f == null || f['statut'] == 'archive') return null;
    final t = '${f['titulaire'] ?? ''}';
    return '${f['poste']}${t.isEmpty ? ' (poste vacant)' : ' : $t'}';
  }
  return null;
}

/// Les choix de responsable : `poste:<id>` (fonction) et `agent:<id>` (personnel), pour le formulaire.
List<(String, String)> optionsResponsablesPlan(Magasin m) {
  final postes = [...m.collection('postes').actives]..sort((a, b) => '${a['poste']}'.compareTo('${b['poste']}'));
  final agents = [...m.collection('personnel').actives]..sort((a, b) => '${a['nomComplet']}'.compareTo('${b['nomComplet']}'));
  return [
    for (final f in postes) ('poste:${f['id']}', 'Fonction : ${f['poste']}'),
    for (final p in agents) ('agent:${p['id']}', 'Agent : ${p['nomComplet']}${'${p['poste'] ?? ''}'.isEmpty ? '' : ' (${p['poste']})'}'),
  ];
}

Fiche _normaliserResponsable(Fiche v) {
  final f = {...v};
  final r = f['responsable'];
  if (r is String && RegExp(r'^(agent|poste):').hasMatch(r)) {
    final i = r.indexOf(':');
    f['responsableType'] = r.substring(0, i);
    f['responsableRef'] = r.substring(i + 1);
    f.remove('responsable');
  }
  return f;
}

Fiche _sansVide(Fiche f) => {for (final e in f.entries) if (e.value != null && e.value != '') e.key: e.value};

/// La GARDE de la collection `planAnnuel` (posée par `Magasin`) : contrôle d'une fiche, plan adopté figé. `null` si l'écriture passe.
String? gardePlanAnnuelPoste(Magasin m, String op, Fiche f) {
  if (_interne) return null;
  final figee = adoptionPlan(m, f['exercice']) != null;
  if (op == 'archiver') {
    return figee ? 'PLAN_ADOPTE_FIGE : le plan de l’exercice ${f['exercice']} est adopté : une action ne s’archive pas, elle se révise par version datée.' : null;
  }
  final refus = paControler(f, contextePlan(m));
  if (refus != null) return '${refus.code} : ${refus.motif}';
  if (!figee) return null;
  if (op == 'inserer') {
    return f['ajouteApresAdoption'] == true || f['versionDe'] != null ? null : 'PLAN_ADOPTE_FIGE : le plan de l’exercice ${f['exercice']} est adopté : une action s’y ajoute par « Ajouter après adoption » (version datée).';
  }
  if (op == 'modifier') {
    final avant = m.collection('planAnnuel').parId(f['id']);
    if (avant == null) return null;
    final touche = [for (final k in paChampsContenu) if ('${avant[k] ?? ''}' != '${f[k] ?? ''}') k];
    if (touche.isNotEmpty) return 'PLAN_ADOPTE_FIGE : le plan de l’exercice ${f['exercice']} est adopté ; ${touche.join(', ')} ne se réécrit pas. Réviser l’action crée une version datée.';
  }
  return null;
}

/// Ajouter une action (plan non adopté) ou « ajouter après adoption » (motif obligatoire, version datée). Rend la fiche ou le refus nommé.
({Fiche? fiche, RefusPlan? refus, VoidCallback? annuler}) ajouterActionPlan(Magasin m, Fiche saisie, {String? motif}) {
  final v = _normaliserResponsable(saisie);
  v['exercice'] = (v['exercice'] is num) ? (v['exercice'] as num).toInt() : int.tryParse('${v['exercice']}');
  for (final k in const ['trimestreDebut', 'trimestreFin']) {
    final n = v[k] is num ? v[k] as num : num.tryParse('${v[k]}');
    if (n != null) v[k] = n.toInt();
  }
  final refus = paControler(v, contextePlan(m));
  if (refus != null) return (fiche: null, refus: refus, annuler: null);
  final adopte = adoptionPlan(m, v['exercice']) != null;
  if (adopte) {
    if ((motif ?? '').trim().length < 3) return (fiche: null, refus: const RefusPlan('MOTIF_OBLIGATOIRE', 'Le plan est adopté : ajouter une action demande un motif.', 'Saisir le motif de l’ajout.'), annuler: null);
    v['ajouteApresAdoption'] = true;
    v['dateEffet'] = parametreDateIso(m.horloge());
    v['motifVersion'] = motif!.trim();
  }
  final x = exercicePlan(m, v['exercice']);
  v['reference'] = paReferenceAnnuelle('PA-', '${x?['debut'] ?? '${v['exercice']}-01-01'}', 3, m.collection('planAnnuel').toutes);
  v['version'] = 1;
  v['statut'] = 'actif';
  try {
    final r = m.collection('planAnnuel').inserer(_sansVide(v), prefixe: 'PAT');
    return (fiche: r.fiche, refus: null, annuler: r.annuler);
  } on EcritureRefusee catch (e) {
    return (fiche: null, refus: RefusPlan('PLAN_ECRITURE_REFUSEE', e.motif, 'Relire le journal : la garde a nommé la cause.'), annuler: null);
  }
}

/// Réviser une action d'un plan ADOPTÉ : nouvelle fiche (version + 1, date d'effet du jour, motif), l'ancienne archivée. [patch] : champs du contenu seulement.
({Fiche? fiche, RefusPlan? refus}) reviserActionPlan(Magasin m, Object? id, Fiche patch, String? motif) {
  final col = m.collection('planAnnuel');
  final a = col.parId(id);
  if (a == null || a['statut'] == 'archive') return (fiche: null, refus: const RefusPlan('ACTION_INCONNUE', 'Action introuvable ou déjà remplacée par une version plus récente.', 'Rafraîchir l’écran.'));
  if (adoptionPlan(m, a['exercice']) == null) return (fiche: null, refus: RefusPlan('PLAN_NON_ADOPTE', 'Le plan de l’exercice ${a['exercice']} n’est pas adopté : l’action se modifie directement.', 'Utiliser « Modifier ».'));
  if ((motif ?? '').trim().length < 3) return (fiche: null, refus: const RefusPlan('MOTIF_OBLIGATOIRE', 'Une révision demande un motif.', 'Saisir le motif de la révision.'));
  final p = _normaliserResponsable(patch);
  final hors = [for (final k in p.keys) if (!paChampsContenu.contains(k)) k];
  if (hors.isNotEmpty) return (fiche: null, refus: RefusPlan('CHAMP_HORS_REVISION', 'Seul le contenu du plan se révise par version (${hors.join(', ')} est du suivi).', 'Modifier le suivi directement.'));
  for (final k in const ['trimestreDebut', 'trimestreFin']) {
    final n = p[k] is num ? p[k] as num : num.tryParse('${p[k] ?? ''}');
    if (n != null) p[k] = n.toInt();
  }
  final neuve = {...a, ...p};
  for (final k in const ['id', '_creePar', '_creeLe', '_modifiePar', '_modifieLe', '_archivePar', '_archiveLe', '_motifArchivage']) {
    neuve.remove(k);
  }
  neuve['statut'] = 'actif';
  neuve['version'] = ((a['version'] as num?) ?? 1).toInt() + 1;
  neuve['versionDe'] = a['id'];
  neuve['dateEffet'] = parametreDateIso(m.horloge());
  neuve['motifVersion'] = motif!.trim();
  final refus = paControler(neuve, contextePlan(m));
  if (refus != null) return (fiche: null, refus: refus);
  Fiche? creee;
  _interne = true;
  try {
    creee = col.inserer(_sansVide(neuve), prefixe: 'PAT').fiche;
    col.archiver(a['id']);
  } finally {
    _interne = false;
  }
  m.journaliser('Plan annuel : action révisée (version datée)', 'M13', 'PlanAnnuelTravail', '${neuve['reference']}', {'id': a['id'], 'version': a['version'] ?? 1},
      {'reference': neuve['reference'], 'version': neuve['version'], 'dateEffet': neuve['dateEffet'], 'motif': neuve['motifVersion']});
  return (fiche: creee, refus: null);
}

/// Adopter le plan d'un exercice (geste réservé `adopter_plan_annuel`). Rend `null` si adopté, sinon le refus nommé.
RefusPlan? adopterPlan(Magasin m, {required Object? annee, required String? motif, required bool gesteAccorde, required String libelleRole}) {
  if (!gesteAccorde) {
    return RefusPlan('ADOPTION_RESERVEE', 'Adopter le plan annuel est un droit réservé de la fiche du rôle : « $libelleRole » ne l’a pas.',
        'Demander à un rôle qui détient le droit « Adopter le plan annuel de travail » (matrice des droits).');
  }
  if (exercicePlan(m, annee) == null) return RefusPlan('EXERCICE_INCONNU', 'L’exercice « $annee » n’est pas un exercice de la comptabilité.', 'Choisir un exercice de la liste.');
  final deja = adoptionPlan(m, annee);
  if (deja != null) return RefusPlan('PLAN_DEJA_ADOPTE', 'Le plan de l’exercice $annee est déjà adopté (le ${dateFR(DateTime.parse('${deja['dateAdoption']}'))}).', 'Réviser une action par version datée.');
  final n = actionsPlan(m, annee).length;
  if (n == 0) return RefusPlan('PLAN_VIDE', 'Le plan de l’exercice $annee ne porte aucune action : il n’y a rien à adopter.', 'Programmer au moins une action.');
  if ((motif ?? '').trim().length < 3) return const RefusPlan('MOTIF_OBLIGATOIRE', 'Un motif est obligatoire pour adopter le plan.', 'Saisir le motif de l’adoption (délibération, décision).');
  final jour = parametreDateIso(m.horloge());
  final exo = annee is num ? annee.toInt() : int.parse('$annee');
  m.collection('adoptionsPlan').inserer({'statut': 'actif', 'exercice': exo, 'dateAdoption': jour, 'motif': motif!.trim(), 'adoptePar': m.utilisateur, 'nbActions': n}, prefixe: 'ADP');
  m.journaliser('Plan annuel : adoption par la Direction', 'M13', 'adoptionsPlan', '$exo', null, {'exercice': exo, 'dateAdoption': jour, 'motif': motif.trim(), 'nbActions': n});
  return null;
}

/// Reconduire les actions NON RÉALISÉES de [source] dans [cible] : copie datée, suivi remis à zéro, source jamais réécrite, une action déjà reconduite n'est pas dupliquée.
({List<String> copiees, List<String> ignorees, RefusPlan? refus}) reconduirePlan(Magasin m, Object? source, Object? cible) {
  RefusPlan? r(String c, String mo, String g) => RefusPlan(c, mo, g);
  if (exercicePlan(m, source) == null || exercicePlan(m, cible) == null) {
    return (copiees: const [], ignorees: const [], refus: r('EXERCICE_INCONNU', 'La source et la cible doivent être des exercices de la comptabilité.', 'Choisir deux exercices de la liste.'));
  }
  if ('$source' == '$cible') return (copiees: const [], ignorees: const [], refus: r('RECONDUCTION_MEME_EXERCICE', 'La source et la cible sont le même exercice.', 'Choisir un exercice cible différent.'));
  if (adoptionPlan(m, cible) != null) return (copiees: const [], ignorees: const [], refus: r('PLAN_ADOPTE_FIGE', 'Le plan de l’exercice $cible est adopté : on n’y reconduit pas en bloc.', 'Ajouter chaque action après adoption (version datée).'));
  final planifie = referentielPlan(m, 'etat').where((e) => e['nature'] == 'planifiee').firstOrNull;
  if (planifie == null) return (copiees: const [], ignorees: const [], refus: r('ETAT_INCONNU', 'Aucun état de nature « planifiée » dans le référentiel des états.', 'Ajouter l’état au référentiel.'));
  final plan = paReconduire(actionsPlan(m, source), actionsPlan(m, cible),
      etatPlanifie: '${planifie['code']}', natureDe: natureDeEtatPlan(m), responsableExiste: (f) => libelleResponsablePlan(m, f) != null);
  final exo = cible is num ? cible.toInt() : int.parse('$cible');
  final x = exercicePlan(m, cible);
  final jour = parametreDateIso(m.horloge());
  final refs = <String>[];
  for (final f in plan.copiees) {
    final ref = paReferenceAnnuelle('PA-', '${x?['debut'] ?? '$exo-01-01'}', 3, m.collection('planAnnuel').toutes);
    final fiche = {...f, 'statut': 'actif', 'exercice': exo, 'reference': ref, 'reconduiteLe': jour};
    m.collection('planAnnuel').inserer(fiche, prefixe: 'PAT');
    m.journaliser('Plan annuel : action reconduite', 'M13', 'PlanAnnuelTravail', ref, {'exercice': source, 'reference': f['reconduiteDepuis']}, {'exercice': exo, 'reference': ref});
    refs.add(ref);
  }
  return (copiees: refs, ignorees: plan.ignorees, refus: null);
}

/// Les signataires de l'impression à une date : le réglage en vigueur (`reglagesPlan`, versions datées) et, pour chacun, la FONCTION (poste) et le TITULAIRE lus à l'organigramme.
List<({String? posteId, String? fonction, String? nom})> signatairesPlan(Magasin m, String jour) {
  Fiche? v;
  final tries = [...m.collection('reglagesPlan').actives]..sort((a, b) {
      final c = '${a['dateEffet'] ?? ''}'.compareTo('${b['dateEffet'] ?? ''}');
      return c != 0 ? c : '${a['creeLe'] ?? ''}'.compareTo('${b['creeLe'] ?? ''}');
    });
  for (final r in tries) {
    final d = r['dateEffet'];
    if (d == null || '$d'.length < 10 || '$d'.substring(0, 10).compareTo(jour) <= 0) v = r;
  }
  if (v == null) return const [];
  return [
    for (final s in (v['signataires'] as List? ?? const []))
      () {
        final id = (s as Map)['posteId'];
        final p = m.collection('postes').parId(id);
        final t = p == null ? null : '${p['titulaire'] ?? ''}';
        return (posteId: '$id', fonction: p == null ? null : '${p['poste']}', nom: (t == null || t.isEmpty) ? null : t);
      }()
  ];
}

/// Régler les signataires (geste réservé « régler les paramètres de clinique ») : nouvelle version datée, jamais une réécriture.
RefusPlan? definirSignatairesPlan(Magasin m, {required List<String> posteIds, required String dateEffet, required String? motif, required bool gesteAccorde, required String libelleRole}) {
  if (!gesteAccorde) {
    return RefusPlan('PARAMETRE_CLINIQUE_RESERVE', 'Régler les signataires du plan est réservé au droit « Régler les paramètres de clinique » : « $libelleRole » ne l’a pas.', 'Demander à un rôle qui détient ce droit.');
  }
  if ((motif ?? '').trim().length < 3) return const RefusPlan('PARAMETRE_MOTIF_OBLIGATOIRE', 'Un motif est obligatoire pour changer les signataires.', 'Saisir le motif.');
  if (posteIds.isEmpty || posteIds.length > 4) return const RefusPlan('SIGNATAIRES_NOMBRE', 'Un à quatre signataires.', 'Choisir de un à quatre postes.');
  final inconnus = [for (final id in posteIds) if (m.collection('postes').parId(id) == null || m.collection('postes').parId(id)!['statut'] == 'archive') id];
  if (inconnus.isNotEmpty) return RefusPlan('SIGNATAIRE_INCONNU', 'Un signataire n’est pas un poste de l’organigramme (${inconnus.join(', ')}).', 'Choisir des postes de la liste.');
  final derniere = [for (final r in m.collection('reglagesPlan').actives) if (r['dateEffet'] != null) '${r['dateEffet']}'.substring(0, 10)].fold<String?>(null, (a, b) => a == null || b.compareTo(a) > 0 ? b : a);
  if (derniere != null && dateEffet.compareTo(derniere) < 0) {
    return const RefusPlan('DATE_EFFET_ANTERIEURE', 'La date d’effet précède celle de la dernière version : une version ne s’insère pas dans le passé.', 'Choisir une date égale ou postérieure.');
  }
  final avant = signatairesPlan(m, dateEffet).map((s) => s.posteId).toList();
  m.collection('reglagesPlan').inserer({'statut': 'actif', 'dateEffet': dateEffet, 'signataires': [for (final id in posteIds) {'posteId': id}], 'motif': motif!.trim(), 'creeLe': m.horloge().toIso8601String(), 'creePar': m.utilisateur}, prefixe: 'RPL');
  m.journaliser('Plan annuel : signataires de l’impression, nouvelle version', 'M13', 'reglagesPlan', dateEffet, {'postes': avant}, {'postes': posteIds, 'dateEffet': dateEffet, 'motif': motif.trim()});
  return null;
}

/// La tolérance (jours) lue à la date.
int graceRetardPlan(Magasin m, String jour) => pcValeur(m.collection(parCollectionParametres).toutes, pcCleGraceRetardPlan, jour);

/// Les alertes de retard à [jour] : UNE par action active, dérivées (jamais écrites : elles retombent quand l'action est réalisée ou replanifiée).
List<({Fiche action, int jours, String finTrimestre})> alertesRetardPlan(Magasin m, String jour) {
  final nat = natureDeEtatPlan(m), grace = graceRetardPlan(m, jour);
  final out = <({Fiche action, int jours, String finTrimestre})>[];
  for (final a in m.collection('planAnnuel').actives) {
    final x = exercicePlan(m, a['exercice']);
    if (x == null) continue;
    final r = paRetard(a, '${x['debut']}', jour, grace, nat);
    if (r.enRetard) out.add((action: a, jours: r.jours!, finTrimestre: r.finTrimestre!));
  }
  return out;
}
