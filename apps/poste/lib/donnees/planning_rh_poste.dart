import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/service_parametres.dart';
import 'magasin.dart';

/// Le planning RH au poste (Direction, 09/11/2026, lots L4 à L6) : la colle entre les fonctions pures de `packages/domaine/lib/src/rh/planning_rh.dart`
/// (rejouées sur les vecteurs de la maquette) et le magasin du poste. Aucune règle ici : le régime en vigueur, le contrôle de repos, la décision du circuit et
/// celle sur une proposition sont celles du domaine ; le circuit et « l'agent modifie directement » se LISENT au registre des paramètres
/// (`planning.circuitPresences`, `planning.agentModifieDirectement`, versionnés par date, synchronisés par le journal), jamais une constante. Ce fichier
/// assemble les fiches, écrit ce que le domaine rend, et journalise par les collections (RG-12).
///
/// Ce qui n'est PAS porté ici (voir ECARTS-MAQUETTE E2333) : les écrans (filtres avancés, cartes, commandes de validation, écran des propositions).
class PlanningRhPoste {
  PlanningRhPoste(this.m, {required this.auteur, required this.role, DateTime Function()? horloge}) : _horloge = horloge ?? DateTime.now;
  final Magasin m;
  final String Function() auteur;
  final String role;
  final DateTime Function() _horloge;

  String get aujourdhui => parametreDateIso(_horloge());
  ServiceParametres get service => serviceParametres(m, auteur: auteur, horloge: _horloge);

  /// Le circuit de validation en vigueur AUJOURD'HUI (défaut : surveillant seul).
  String circuit() => circuitRhEnVigueur(service.valeur('planning.circuitPresences', aujourdhui));

  /// Le réglage « l'agent modifie directement » en vigueur aujourd'hui (défaut : non).
  bool agentModifieDirectement() => service.valeur('planning.agentModifieDirectement', aujourdhui) == true;

  /// L'agent de la session, retrouvé par son nom (la session ne porte pas d'identifiant de personnel).
  Fiche? moi() {
    final nom = auteur();
    for (final e in m.collection('personnel').actives) {
      if (e['nomComplet'] == nom) return e;
    }
    return null;
  }

  List<Fiche> _versions(Object? employeId) => [
        for (final v in m.collection('regimesIndividuels').actives)
          if (v['employeId'] == employeId) v
      ];

  /// Le régime en vigueur d'un agent à une date : sa catégorie, puis les champs dérogés de la dernière version à date d'effet atteinte.
  RegimeRhResolu regimeALaDate(Fiche agent, String date) => regimeRhALaDate(
        regimesActifs: m.collection('regimesTravail').actives,
        versions: _versions(agent['id']),
        fonction: agent['fonction'] as String?,
        date: date,
      );

  /// Le contrôle d'incompatibilité d'une vacation (repos, double affectation), refait à TOUTE saisie quelle que soit la voie. `null` : acceptable.
  RefusRh? controlerVacation(Object? employeId, String date, String type, {String? ignoreId}) {
    Fiche? agent;
    for (final e in m.collection('personnel').actives) {
      if (e['id'] == employeId) agent = e;
    }
    final d = date.length >= 10 ? date.substring(0, 10) : date;
    return controlerVacationRh(
      agent: agent,
      planningActif: m.collection('planning').actives,
      regime: agent == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d) ? null : regimeALaDate(agent, d),
      date: date,
      type: type,
      ignoreId: ignoreId,
    );
  }

  /// POSER UNE DÉROGATION (ou le retour à la catégorie) : contrôlée par le domaine, écrite comme une version immuable. Réservée à l'administrateur et à la DA.
  /// Rend `{'ok': true, 'id': …}` ou le refus nommé.
  Map<String, Object?> deroger({
    required Object? employeId,
    required String? dateEffet,
    required Map<String, Object?> champs,
    required String? motif,
    bool retourCategorie = false,
  }) {
    Fiche? e;
    for (final x in m.collection('personnel').actives) {
      if (x['id'] == employeId) e = x;
    }
    final versions = _versions(employeId);
    final r = validerDerogationRh(
      role: role,
      agentExiste: e != null,
      dateEffet: dateEffet,
      motif: motif,
      retourCategorie: retourCategorie,
      champs: champs,
      versions: versions,
      aujourdhui: aujourdhui,
    );
    if (r.refus != null) return r.refus!.toJson();
    final avant = regimeALaDate(e!, dateEffet!);
    final res = m.collection('regimesIndividuels').inserer({
      'employeId': e['id'], 'employe': e['nomComplet'], 'matricule': e['matricule'], 'fonction': e['fonction'], 'categorie': avant.categorie,
      'champs': r.champs, 'retourCategorie': retourCategorie, 'dateEffet': dateEffet, 'motif': (motif ?? '').trim(), 'version': versions.length + 1,
      'creeLe': aujourdhui, 'creePar': auteur(), 'statut': 'actif',
    }, prefixe: 'RGI');
    return {'ok': true, 'id': res.fiche['id'], 'version': versions.length + 1, 'derogations': (r.champs ?? const {}).keys.toList(), 'retourCategorie': retourCategorie};
  }

  /// TRANCHER une pièce (pointage, congé, ordre de mission) selon le circuit en vigueur : le patch du domaine est écrit sur la fiche, le circuit consigné.
  Map<String, Object?> trancher(String collection, Object? id, String decision, {String? motif}) {
    final col = m.collection(collection);
    final rec = col.parId(id);
    final me = moi();
    final r = trancherRh(
      collection: collection,
      rec: rec,
      decision: decision,
      motif: motif,
      role: role,
      circuit: circuit(),
      acteur: auteur(),
      aujourdhui: aujourdhui,
      moiId: me == null ? null : '${me['id']}',
      moiNom: me == null ? null : '${me['nomComplet']}',
    );
    if (r.refus != null) return r.refus!.toJson();
    final annuler = col.mettreAJour(id, r.patch!);
    return {'ok': true, 'etat': r.etat, 'etape': r.etape, 'complet': r.complet, 'circuit': circuit(), 'annuler': annuler};
  }

  /// Une pièce COMPTE seulement validée (primes, taux de présence, soldes).
  bool compte(String collection, Fiche rec) => compteRh(collection, rec);

  /// Les propositions que le rôle courant peut lire (l'agent : les siennes seulement, RG-13).
  List<Fiche> propositionsVisibles() => propositionsVisiblesRh(m.collection('propositionsPlanning').actives, role, moi()?['id'] as String?);

  RefusRh? _controlerProposition(Fiche p) {
    final personnel = {for (final e in m.collection('personnel').actives) '${e['id']}': e};
    return controlerPropositionRh(
      proposition: p,
      planningActif: m.collection('planning').actives,
      personnel: personnel,
      regimeDe: (agent, date) => regimeALaDate(agent, date),
    );
  }

  /// L'agent PROPOSE : le contrôle est fait tout de suite (l'agent l'apprend), la proposition naît « à valider » et ne change JAMAIS le planning validé.
  /// Application directe (réglage du poste) : pour SES vacations seulement, jamais pour un échange.
  Map<String, Object?> proposer({
    required String type,
    required String? motif,
    String? date,
    String? typeVacation,
    String? vacationId,
    String? contrepartieId,
  }) {
    final me = moi();
    if (me == null) {
      return const RefusRh('AGENT_NON_IDENTIFIE', 'La session ne correspond à aucun agent du personnel : aucune proposition ne peut être rattachée.', 'Se connecter avec le compte nominatif de l’agent.').toJson();
    }
    if (!typesPropositionRh.any((t) => t.id == type)) {
      return RefusRh('TYPE_PROPOSITION_INCONNU', 'Le type de proposition « $type » n’existe pas.', 'Choisir ajout, modification, retrait ou échange.').toJson();
    }
    if ((motif ?? '').trim().isEmpty) {
      return const RefusRh('MOTIF_OBLIGATOIRE', 'Le motif de la proposition est obligatoire : le surveillant doit savoir pourquoi.', 'Dire pourquoi le planning doit changer.').toJson();
    }
    final plan = m.collection('planning');
    final p = <String, Object?>{
      'type': type, 'employeId': me['id'], 'employe': me['nomComplet'], 'fonction': me['fonction'], 'service': me['service'], 'motif': motif!.trim(),
      'date': date == null || date.isEmpty ? null : date.substring(0, 10), 'typeVacation': typeVacation, 'vacationId': vacationId, 'contrepartieId': contrepartieId,
    };
    if (type != 'retrait' && type != 'echange' && (typeVacation ?? '').isEmpty) {
      return const RefusRh('TYPE_INCONNU', 'Le type de vacation est obligatoire.', 'Choisir un type du référentiel.').toJson();
    }
    if (type == 'ajout' && p['date'] == null) return const RefusRh('DATE_INVALIDE', 'La date de la vacation est obligatoire.', 'Choisir une date.').toJson();
    final cv = vacationId == null ? null : plan.parId(vacationId);
    if (cv != null) {
      p['date'] ??= cv['date'];
      p['vacationType'] = cv['type'];
      p['vacationDate'] = cv['date'];
    }
    final cb = contrepartieId == null ? null : plan.parId(contrepartieId);
    if (cb != null) {
      p['contrepartie'] = cb['employe'];
      p['contrepartieDate'] = cb['date'];
      p['contrepartieType'] = cb['type'];
    }
    final refus = _controlerProposition(p);
    if (refus != null) return refus.toJson();
    if (agentModifieDirectement() && type != 'echange') {
      if (type == 'retrait') {
        plan.archiver(vacationId);
        return {'ok': true, 'direct': true, 'vacationId': vacationId};
      }
      final regime = regimeALaDate(me, '${p['date']}');
      final fiche = <String, Object?>{
        'date': p['date'], 'employeId': me['id'], 'employe': me['nomComplet'], 'fonction': me['fonction'], 'service': me['service'], 'type': typeVacation,
        'observation': p['motif'], 'statut': 'validee', 'regimeLibelle': regime.categorie, 'regimeIndividuelId': regime.versionId, 'derogations': regime.derogations,
        'validationEtat': 'validee', 'validePar': 'l’agent (réglage « modifie directement »)', 'valideLe': aujourdhui, 'origine': 'agent', 'modifieDirectement': true,
      };
      if (type == 'ajout') {
        final r = plan.inserer(fiche, prefixe: 'PLN');
        return {'ok': true, 'direct': true, 'vacationId': r.fiche['id']};
      }
      plan.mettreAJour(vacationId, fiche);
      return {'ok': true, 'direct': true, 'vacationId': vacationId};
    }
    final r = m.collection('propositionsPlanning').inserer({...p, 'etat': 'proposee', 'proposeeLe': aujourdhui, 'proposeePar': auteur(), 'statut': 'actif'}, prefixe: 'PPL');
    return {'ok': true, 'direct': false, 'id': r.fiche['id']};
  }

  /// La décision du surveillant : le refus nommé, ou la proposition appliquée au planning (le contrôle est REFAIT à la validation).
  Map<String, Object?> trancherProposition(Object? id, String decision, {String? motif}) {
    final col = m.collection('propositionsPlanning');
    final p = col.parId(id);
    final me = moi();
    final refus = peutTrancherPropositionRh(proposition: p, role: role, decision: decision, motif: motif, moiId: me == null ? null : '${me['id']}');
    if (refus != null) return refus.toJson();
    if (decision == 'refuser') {
      col.mettreAJour(id, {'etat': 'refusee', 'motifRefus': (motif ?? '').trim(), 'tranchePar': auteur(), 'trancheLe': aujourdhui});
      return {'ok': true, 'etat': 'refusee'};
    }
    final ctrl = _controlerProposition(p!);
    if (ctrl != null) {
      return {...ctrl.toJson(), 'cause': ctrl.code, 'code': 'CONTROLE_ECHOUE', 'motif': 'Le planning a changé depuis la proposition : ${ctrl.motif}'};
    }
    final plan = m.collection('planning');
    final marque = <String, Object?>{'validationEtat': 'validee', 'validePar': auteur(), 'valideLe': aujourdhui, 'origine': 'proposition', 'propositionId': p['id']};
    Fiche vac(Fiche agent, String date, Object? type) {
      final regime = regimeALaDate(agent, date);
      return {
        'date': date, 'employeId': agent['id'], 'employe': agent['nomComplet'], 'fonction': agent['fonction'], 'service': agent['service'], 'type': type,
        'observation': p['motif'], 'statut': 'validee', 'regimeLibelle': regime.categorie, 'regimeIndividuelId': regime.versionId, 'derogations': regime.derogations, ...marque,
      };
    }

    Fiche agentDe(Object? employeId) => m.collection('personnel').actives.firstWhere((e) => e['id'] == employeId);
    final appliquees = <Object?>[];
    final type = p['type'];
    if (type == 'ajout') {
      final r = plan.inserer(vac(agentDe(p['employeId']), '${p['date']}', p['typeVacation']), prefixe: 'PLN');
      appliquees.add(r.fiche['id']);
    } else if (type == 'modification') {
      plan.mettreAJour(p['vacationId'], vac(agentDe(p['employeId']), '${p['date']}', p['typeVacation']));
      appliquees.add(p['vacationId']);
    } else if (type == 'retrait') {
      plan.archiver(p['vacationId']);
      appliquees.add(p['vacationId']);
    } else {
      final cv = plan.parId(p['vacationId'])!, cb = plan.parId(p['contrepartieId'])!;
      final eA = agentDe(cv['employeId']), eB = agentDe(cb['employeId']);
      plan.mettreAJour(cv['id'], {'employeId': eB['id'], 'employe': eB['nomComplet'], 'fonction': eB['fonction'], 'service': eB['service'], ...marque, 'echangeAvec': eA['nomComplet']});
      plan.mettreAJour(cb['id'], {'employeId': eA['id'], 'employe': eA['nomComplet'], 'fonction': eA['fonction'], 'service': eA['service'], ...marque, 'echangeAvec': eB['nomComplet']});
      appliquees..add(cv['id'])..add(cb['id']);
    }
    col.mettreAJour(id, {'etat': 'validee', 'tranchePar': auteur(), 'trancheLe': aujourdhui, 'appliquees': appliquees, 'motifValidation': (motif ?? '').trim().isEmpty ? null : motif!.trim()});
    return {'ok': true, 'etat': 'validee', 'appliquees': appliquees};
  }
}
