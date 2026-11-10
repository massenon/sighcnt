import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/service_parametres.dart';
import 'magasin.dart';

/// Le planning RH au poste (Direction, 09/11/2026, lots L4 à L6) : la colle entre les fonctions pures de `packages/domaine/lib/src/rh/planning_rh.dart`
/// (rejouées sur les vecteurs de la maquette) et le magasin du poste. Aucune règle ici : le régime en vigueur, le contrôle de repos, la décision du circuit et
/// celle sur une proposition sont celles du domaine ; le circuit et « l'agent modifie directement » se LISENT au registre des paramètres
/// (`planning.circuitPresences`, `planning.agentModifieDirectement`, versionnés par date, synchronisés par le journal), jamais une constante. Ce fichier
/// assemble les fiches, écrit ce que le domaine rend, et journalise par les collections (RG-12).
///
/// Les écrans (carte des régimes individuels, filtres avancés, commandes de validation, écran des propositions) sont portés au lot Y (E2339 et suivants) : ils
/// n'appellent que ce fichier et le domaine, jamais une règle écrite à l'écran.
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
        return {'ok': true, 'direct': true, 'vacationId': vacationId, 'annuler': plan.archiver(vacationId)};
      }
      final regime = regimeALaDate(me, '${p['date']}');
      final fiche = <String, Object?>{
        'date': p['date'], 'employeId': me['id'], 'employe': me['nomComplet'], 'fonction': me['fonction'], 'service': me['service'], 'type': typeVacation,
        'observation': p['motif'], 'statut': 'validee', 'regimeLibelle': regime.categorie, 'regimeIndividuelId': regime.versionId, 'derogations': regime.derogations,
        'validationEtat': 'validee', 'validePar': 'l’agent (réglage « modifie directement »)', 'valideLe': aujourdhui, 'origine': 'agent', 'modifieDirectement': true,
      };
      if (type == 'ajout') {
        final r = plan.inserer(fiche, prefixe: 'PLN');
        return {'ok': true, 'direct': true, 'vacationId': r.fiche['id'], 'annuler': r.annuler};
      }
      return {'ok': true, 'direct': true, 'vacationId': vacationId, 'annuler': plan.mettreAJour(vacationId, fiche)};
    }
    final r = m.collection('propositionsPlanning').inserer({...p, 'etat': 'proposee', 'proposeeLe': aujourdhui, 'proposeePar': auteur(), 'statut': 'actif'}, prefixe: 'PPL');
    return {'ok': true, 'direct': false, 'id': r.fiche['id'], 'annuler': r.annuler};
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

  // ---------------------------------------------------------------------------------------------------------------------
  // Les gestes de l'écran : réglages, pose et retrait du planning, historique, régularisation, avis du chef, retrait d'une proposition
  // ---------------------------------------------------------------------------------------------------------------------

  /// Règle le circuit de validation : une NOUVELLE VERSION du paramètre `planning.circuitPresences` effective aujourd'hui (registre du lot L0), journalisée avec
  /// l'ancienne et la nouvelle valeur (RG-12). Réservé à l'administrateur et à la DA : le refus est nommé.
  Map<String, Object?> definirCircuit(Object? id, {String? motif}) {
    final refus = controlerReglageRh(role: role, genre: 'circuit', valeur: id);
    if (refus != null) return refus.toJson();
    final avant = circuit();
    final r = service.regler('planning.circuitPresences', id, aujourdhui, motif: motif);
    if (!r.ok) return {'ok': false, 'code': r.refus!.code, 'motif': r.refus!.motif, 'geste': r.refus!.geste};
    m.journaliser('Circuit de validation des présences', 'M10', 'reglage', 'planningCircuitPresences', {'circuit': avant}, {'circuit': id, 'motif': motif});
    return {'ok': true, 'circuit': id, 'avant': avant};
  }

  /// Règle « l'agent modifie directement son planning » (`planning.agentModifieDirectement`) : tout ce qui n'est pas vrai vaut non.
  Map<String, Object?> definirAgentDirect(Object? oui) {
    final refus = controlerReglageRh(role: role, genre: 'direct', valeur: oui);
    if (refus != null) return refus.toJson();
    final avant = agentModifieDirectement();
    final r = service.regler('planning.agentModifieDirectement', oui == true, aujourdhui);
    if (!r.ok) return {'ok': false, 'code': r.refus!.code, 'motif': r.refus!.motif, 'geste': r.refus!.geste};
    m.journaliser('Planning : l’agent modifie directement', 'M10', 'reglage', 'planningAgentModifieDirectement', {'valeur': avant}, {'valeur': oui == true});
    return {'ok': true, 'valeur': oui == true, 'avant': avant};
  }

  /// Les types de vacation qu'un agent peut recevoir à une date : ceux de son régime en vigueur (dérogation comprise), le repos, congé, absence, remplacement.
  List<String> typesAutorises(Fiche agent, String date) => typesAutorisesRh(regimeALaDate(agent, date));

  /// L'historique des versions du régime individuel d'un agent, de la plus ancienne à la plus récente (numérotées).
  List<Map<String, Object?>> historique(Object? employeId) {
    final vs = _versions(employeId)..sort((a, b) => '${a['dateEffet']}'.compareTo('${b['dateEffet']}'));
    return [
      for (final (i, v) in vs.indexed)
        {
          'id': v['id'], 'version': i + 1, 'dateEffet': v['dateEffet'], 'retourCategorie': v['retourCategorie'] == true,
          'champs': (v['champs'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{}, 'motif': v['motif'], 'creePar': v['creePar'], 'creeLe': v['creeLe'],
        }
    ];
  }

  Fiche? _agent(Object? id) {
    for (final e in m.collection('personnel').actives) {
      if (e['id'] == id) return e;
    }
    return null;
  }

  /// POSER OU REMPLACER une vacation depuis le poste : DA, surveillant (ou administrateur). Le contrôle de repos et de double affectation est celui du domaine
  /// (une seule règle, quelle que soit la voie) ; la vacation est écrite VALIDÉE (celui qui la pose est celui qui valide), avec le régime sous lequel elle l'est.
  Map<String, Object?> poserVacation({required Object? employeId, required String? date, required String? type, String? observation, Object? existantId}) {
    final reserve = peutPoserPlanningRh(role);
    if (reserve != null) return reserve.toJson();
    final ctrl = controlerVacation(employeId, date ?? '', type ?? '', ignoreId: existantId as String?);
    if (ctrl != null) return ctrl.toJson();
    final e = _agent(employeId)!;
    final d = date!.substring(0, 10);
    final regime = regimeALaDate(e, d);
    final rec = <String, Object?>{
      'date': d, 'employeId': e['id'], 'employe': e['nomComplet'], 'fonction': e['fonction'], 'service': e['service'], 'type': type,
      'observation': (observation ?? '').isEmpty ? null : observation, 'statut': 'validee', 'regimeLibelle': regime.categorie, 'regimeIndividuelId': regime.versionId,
      'derogations': [...regime.derogations], 'validationEtat': 'validee', 'validePar': auteur(), 'valideLe': aujourdhui, 'origine': 'poste',
    };
    final plan = m.collection('planning');
    if (existantId != null) {
      final annuler = plan.mettreAJour(existantId, rec);
      return {'ok': true, 'id': existantId, 'annuler': annuler};
    }
    final res = plan.inserer(rec, prefixe: 'PLN');
    return {'ok': true, 'id': res.fiche['id'], 'annuler': res.annuler};
  }

  /// RETIRER une vacation (archivage logique, annulable) : DA, surveillant ou administrateur.
  Map<String, Object?> retirerVacation(Object? id) {
    final plan = m.collection('planning');
    final refus = controlerRetraitVacationRh(role: role, vacation: plan.parId(id), id: id);
    if (refus != null) return refus.toJson();
    return {'ok': true, 'id': id, 'annuler': plan.archiver(id)};
  }

  /// Une pièce NAÎT à valider : l'état est posé à la création par la porte d'écriture de l'écran.
  Map<String, Object?> naissance() => {'validationEtat': 'a_valider', 'etapesFaites': const <Object?>[], 'saisiPar': auteur(), 'saisiLe': aujourdhui};

  /// Peut-on trancher CETTE pièce (rôle, étape attendue du circuit, auto-validation) ? Rend l'étape, ou le refus nommé : l'écran n'offre la commande que si `ok`.
  ({RefusRh? refus, String? etape}) peutTrancher(String collection, Fiche rec) {
    final me = moi();
    return peutTrancherRh(
        nom: collection, rec: rec, role: role, circuit: circuit(), acteur: auteur(), moiId: me == null ? null : '${me['id']}', moiNom: me == null ? null : '${me['nomComplet']}');
  }

  /// RÉGULARISER un pointage validé : correction DATÉE, auteur et motif consignés (la pièce reste validée).
  Map<String, Object?> regulariser(Object? id, Map<String, Object?> o) {
    final col = m.collection('presences');
    final me = moi();
    final r = regulariserPresenceRh(rec: col.parId(id), role: role, acteur: auteur(), aujourdhui: aujourdhui, o: o, moiId: me == null ? null : '${me['id']}');
    if (r.refus != null) return r.refus!.toJson();
    final avant = col.parId(id)!;
    final annuler = col.mettreAJour(id, r.patch!, journaliser: false);
    m.journaliser('Régularisation d’un pointage', 'M10', 'Presence', '$id', {'etat': avant['etat'], 'motifCode': avant['motifCode']},
        {'etat': o['etat'], 'motifCode': r.patch!.containsKey('motifCode') ? r.patch!['motifCode'] : avant['motifCode'], 'motif': o['motif']});
    return {'ok': true, 'annuler': annuler};
  }

  /// L'AVIS DU CHEF DE SERVICE sur un ordre de mission, consigné par un habilité du circuit.
  Map<String, Object?> avisMission(Object? id, Map<String, Object?> o) {
    final col = m.collection('missions');
    final r = avisMissionRh(rec: col.parId(id), role: role, acteur: auteur(), aujourdhui: aujourdhui, o: o);
    if (r.refus != null) return r.refus!.toJson();
    final avant = col.parId(id)!;
    final annuler = col.mettreAJour(id, r.patch!, journaliser: false);
    m.journaliser('Avis du chef de service sur un ordre de mission', 'M10', 'Ordre de mission', '$id', {'avis': avant['avisChefService']},
        {'avis': o['avis'], 'chef': o['chef'], 'motif': o['motif']});
    return {'ok': true, 'avis': o['avis'], 'annuler': annuler};
  }

  /// L'agent RETIRE sa propre proposition tant qu'elle n'est pas tranchée.
  Map<String, Object?> annulerProposition(Object? id) {
    final col = m.collection('propositionsPlanning');
    final me = moi();
    final r = annulerPropositionRh(proposition: col.parId(id), aujourdhui: aujourdhui, moiId: me == null ? null : '${me['id']}');
    if (r.refus != null) return r.refus!.toJson();
    final annuler = col.mettreAJour(id, r.patch!, journaliser: false);
    m.journaliser('Proposition de planning retirée', 'M10', 'propositionsPlanning', '$id', {'etat': 'proposee'}, {'etat': 'annulee'});
    return {'ok': true, 'annuler': annuler};
  }
}
