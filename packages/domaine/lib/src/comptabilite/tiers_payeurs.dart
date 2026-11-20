// LOT TIERS (Direction, 16/11/2026, section AQ point 36) : la FACTURE À UN TIERS PAYEUR. Port des règles pures du moteur `SIGH.tiers` de la maquette (`prototype_html/assets/js/parcours.js`) :
// l'acheteur (IFU de 13 chiffres et nom obligatoires), la fiche du tiers (versions datées), la DÉCISION du comptable sur l'AIB (le logiciel propose le taux du barème, ne décide jamais),
// le contrôle d'émission, le numéro FT-AAAA-nnnn (fabrique unique, année de la date de la pièce), la créance (dû moins lettrages) et sa balance âgée (tranches lues en base), le lettrage
// d'un règlement. Rejoué sur les vecteurs tirés de l'écran réel (`test/vecteurs/tiers.json`).
//
// Une pièce émise ne se réécrit jamais (avoir). La facture d'un PATIENT, elle, ne porte aucun AIB ni IFU d'acheteur : ces règles ne la touchent pas.
library;

import '../numerotation/reference_annuelle.dart';
import '../parametres/parametres_clinique.dart';
import 'aib.dart';

/// Les deux gestes réservés de la fiche RBAC (défaut d'origine : émettre = administrateur, caissier, DAF, comptable ; corriger = administrateur, comptable, DAF).
const String tiersGesteEmettre = 'emettre_facture_tiers';
const String tiersGesteCorriger = 'corriger_facture_tiers';

/// Les types d'un tiers payeur.
const List<String> tiersTypes = ['entreprise', 'assureur', 'convention'];

String _s(Object? v) => v == null ? '' : '$v';
bool _vide(Object? v) => v == null || v == '';
String _jour(Object? d) => _s(d).length > 10 ? _s(d).substring(0, 10) : _s(d);
bool _entier(Object? x) => x is num && x.isFinite && x == x.floor();

/// L'acheteur d'une facture à un tiers : IFU de 13 chiffres ET nom OBLIGATOIRES, contrôlés AVANT toute écriture. Rend `{ok: true, ifu, nom}` ou le refus nommé.
Map<String, Object?> tiersValiderAcheteur({Object? ifu, Object? nom}) {
  final i = aibNormaliserIfu(ifu);
  if (i.isEmpty) {
    return aibRefus('TIERS_IFU_ABSENT', 'L’IFU de l’acheteur est obligatoire sur une facture à un tiers payeur : une vente normalisée à un professionnel porte son identifiant fiscal.',
        'Renseigner l’IFU (13 chiffres) sur la fiche du tiers payeur, par une nouvelle version datée.');
  }
  if (!RegExp(r'^\d{13}$').hasMatch(i)) {
    return aibRefus('IFU_INVALIDE', 'L’IFU de l’acheteur (« $i ») doit comporter exactement 13 chiffres.', 'Corriger l’IFU du tiers payeur.');
  }
  final n = _s(nom).trim();
  if (n.isEmpty) return aibRefus('NOM_ACHETEUR_ABSENT', 'Le nom de l’acheteur est obligatoire sur une facture à un tiers payeur.', 'Renseigner le nom du tiers payeur sur sa fiche.');
  return {'ok': true, 'ifu': i, 'nom': n};
}

/// Les champs d'une fiche de tiers payeur (création ou nouvelle version) : refus nommé ou `{ok: true, champs}`.
Map<String, Object?> tiersLireChamps(Map<String, Object?> o) {
  final nom = _s(o['nom']).trim();
  if (nom.isEmpty) return aibRefus('TIERS_NOM_ABSENT', 'Le nom du tiers payeur est obligatoire.', 'Saisir le nom de l’entreprise, de l’assureur ou de la convention.');
  final ifu = aibNormaliserIfu(o['ifu']);
  if (ifu.isNotEmpty && !RegExp(r'^\d{13}$').hasMatch(ifu)) {
    return aibRefus('IFU_INVALIDE', 'L’IFU du tiers payeur (« $ifu ») doit comporter exactement 13 chiffres.', 'Corriger l’IFU, ou le laisser vide : il sera exigé à la première facture.');
  }
  if (!tiersTypes.contains(o['type'])) {
    return aibRefus('TIERS_TYPE_INCONNU', 'Le type « ${_s(o['type'])} » n’existe pas (entreprise, assureur, convention).', 'Choisir un type de la liste.');
  }
  num? delai;
  if (!_vide(o['delaiPaiementJours'])) {
    delai = o['delaiPaiementJours'] is num ? o['delaiPaiementJours'] as num : num.tryParse(_s(o['delaiPaiementJours']));
    if (delai == null || !_entier(delai) || delai < 0 || delai > 365) {
      return aibRefus('TIERS_DELAI_INVALIDE', 'Le délai de paiement (« ${o['delaiPaiementJours']} ») est un nombre entier de jours de 0 à 365.', 'Saisir un entier, ou laisser vide (délai non convenu : l’échéance est alors non calculable).');
    }
  }
  return {
    'ok': true,
    'champs': {'nom': nom, 'ifu': ifu.isEmpty ? null : ifu, 'type': o['type'], 'delaiPaiementJours': delai?.toInt()}
  };
}

/// La version d'un tiers EN VIGUEUR à [date] parmi les [versions] (une pièce lit SA date), ou null.
Map<String, Object?>? tiersALaDate(Iterable<Map<String, Object?>> versions, String code, String date) {
  Map<String, Object?>? r;
  final tri = [for (final v in versions) if (v['statut'] != 'archive' && v['code'] == code) v]..sort((a, b) => _s(a['dateEffet']).compareTo(_s(b['dateEffet'])));
  for (final v in tri) {
    if (_s(v['dateEffet']).compareTo(date) <= 0 && (_vide(v['dateFin']) || _s(v['dateFin']).compareTo(date) >= 0)) r = v;
  }
  return r;
}

/// La DÉCISION du comptable sur l'AIB d'un brouillon : `{ok: true, decision}` ou le refus nommé, dans l'ordre de la maquette : droit (`imputer_aib`), pièce émise (jamais réécrite),
/// décision ABSENTE (le logiciel ne décide jamais), puis (non appliqué) motif, ou (appliqué) ligne, taux, motif d'un taux hors barème. [facture] porte `statut`, `date`.
Map<String, Object?> tiersDeciderAib(
  AibDonnees d, {
  required bool droit,
  required Map<String, Object?> facture,
  required Map<String, Object?> saisie,
  required String acteur,
  required String libelleRole,
  required DateTime maintenant,
}) {
  if (!droit) {
    return aibRefus('IMPUTATION_AIB_RESERVEE', 'Imputer l’AIB est un droit réservé de la fiche du rôle : « $libelleRole » ne l’a pas. Le logiciel propose un taux, il ne décide jamais.',
        'Demander à un rôle qui détient le droit « Imputer l’AIB » (matrice des droits), en général le comptable.');
  }
  if (facture['statut'] != 'brouillon') {
    return aibRefus('FACTURE_TIERS_EMISE', 'La facture ${_s(facture['numero'])} est émise : une pièce émise ne se réécrit jamais, son AIB non plus.', 'La corriger par un avoir, puis refaire la facture.');
  }
  final appliquer = saisie['appliquer'];
  if (appliquer != true && appliquer != false) {
    return aibRefus('AIB_DECISION_ABSENTE', 'Le comptable n’a pas décidé : appliquer l’AIB à cette facture ou non. Le logiciel propose un taux, il ne décide jamais.', 'Répondre « appliquer » ou « ne pas appliquer ».');
  }
  final date = _jour(facture['date']);
  final motif = _s(saisie['motif']).trim();
  final dec = <String, Object?>{'appliquer': appliquer, 'decidePar': acteur, 'decideRole': libelleRole, 'decideLe': maintenant.toUtc().toIso8601String()};
  if (appliquer == false) {
    if (motif.isEmpty) {
      return aibRefus('AIB_MOTIF_ABSENT', 'Ne pas appliquer l’AIB se motive (l’acheteur paie lui-même son AIB, exonération).', 'Saisir le motif de la décision.');
    }
    dec['motif'] = motif;
  } else {
    if (_vide(saisie['situation'])) {
      return aibRefus('AIB_LIGNE_ABSENTE', 'La ligne du barème n’est pas choisie : le comptable choisit la ligne à chaque opération.', 'Choisir la ligne du barème (situation de l’acheteur).');
    }
    final sit = [for (final s in d.situations) if (s['statut'] != 'archive' && s['code'] == saisie['situation']) s];
    if (sit.isEmpty) return aibRefus('AIB_SITUATION_INCONNUE', 'La ligne « ${saisie['situation']} » n’existe pas au barème de l’AIB.', 'Choisir une ligne du barème.');
    final prop = aibTauxALaDate(d, '${saisie['situation']}', date);
    if (_vide(saisie['taux'])) {
      return aibRefus('AIB_TAUX_ABSENT', 'Le taux n’est pas posé : le logiciel le propose${prop['ok'] == true ? ' (${prop['taux']} % au ${aibDateFr(date)})' : ''}, le comptable le retient ou le change.', 'Saisir le taux retenu.');
    }
    final taux = saisie['taux'] is num ? saisie['taux'] as num : num.tryParse(_s(saisie['taux']));
    if (taux == null || !_entier(taux) || taux < 0 || taux > 100) {
      return aibRefus('AIB_TAUX_INVALIDE', 'Le taux (« ${saisie['taux']} ») doit être un pourcentage entier de 0 à 100.', 'Saisir un entier, par exemple 1.');
    }
    final hors = prop['ok'] != true || prop['taux'] != taux;
    if (hors && motif.isEmpty) {
      return aibRefus('AIB_MOTIF_ABSENT', 'Le taux retenu ($taux %) n’est pas celui du barème de cette ligne à la date de la pièce${prop['ok'] == true ? ' (${prop['taux']} %)' : ' (aucune version ne couvre cette date)'} : il se motive.', 'Saisir le motif.');
    }
    dec['situation'] = saisie['situation'];
    dec['taux'] = taux.toInt();
    dec['horsProposition'] = hors;
    dec['propositionTaux'] = prop['ok'] == true ? prop['taux'] : null;
    dec['propositionVersion'] = prop['ok'] == true ? prop['versionId'] : null;
    dec['propositionArretee'] = prop['ok'] == true ? prop['arrete'] == true : null;
    if (motif.isNotEmpty) dec['motif'] = motif;
  }
  return {'ok': true, 'decision': dec};
}

/// Le contrôle d'ÉMISSION d'un brouillon : le droit d'émettre, la pièce encore brouillon, l'acheteur valide, puis la DÉCISION du comptable posée. Rend le refus nommé ou null.
Map<String, Object?>? tiersControleEmission({required bool droit, required String libelleRole, required Map<String, Object?> facture}) {
  if (!droit) {
    return aibRefus('FACTURE_TIERS_RESERVEE', 'Émettre une facture à un tiers payeur est un droit réservé de la fiche du rôle (« $tiersGesteEmettre ») : « $libelleRole » ne l’a pas.',
        'Demander ce geste à un rôle qui détient le droit « $tiersGesteEmettre ».');
  }
  if (facture['statut'] != 'brouillon') {
    return aibRefus('FACTURE_TIERS_DEJA_EMISE', 'La facture ${_s(facture['numero'])} est déjà émise : elle ne se réémet ni ne se réécrit.', 'La corriger par un avoir.');
  }
  final ach = tiersValiderAcheteur(ifu: facture['ifuAcheteur'], nom: facture['nomAcheteur']);
  if (ach['ok'] != true) return ach;
  final dec = facture['aibDecision'];
  if (dec is! Map || (dec['appliquer'] != true && dec['appliquer'] != false)) {
    return aibRefus('TIERS_AIB_DECISION_ABSENTE', 'Le comptable n’a pas décidé de l’AIB de cette facture : le logiciel propose le taux du barème, il ne l’impose jamais.',
        'Faire poser la décision (appliquer ou non, ligne, taux) par un rôle qui détient le droit « Imputer l’AIB ».');
  }
  return null;
}

/// Le taux d'AIB effectif d'une pièce : celui de la DÉCISION du comptable (0 si « ne pas appliquer »). Jamais un taux imposé : sans décision, refus.
int tiersTauxEffectif(Map<String, Object?> facture) {
  final dec = facture['aibDecision'];
  if (dec is! Map || dec['appliquer'] != true) return 0;
  return (dec['taux'] as num).toInt();
}

/// Le numéro `FT-AAAA-nnnn` : l'année est celle de la DATE DE LA PIÈCE, le rang se lit sur les pièces existantes (archivées comprises).
String tiersNumeroFacture(Object? date, Iterable<Map<String, Object?>> factures, {required DateTime maintenant}) =>
    referenceAnnuelle('FT-', date, 4, factures, maintenant: maintenant, champ: 'numero');


/// Le lien d'un lettrage ou d'un avoir à sa FACTURE : l'identifiant local, ou, entre postes (l'identifiant local d'une fiche reçue n'est pas celui du poste qui l'a créée), le couple
/// (tiers, numéro de la pièce) que le lettrage ou l'avoir porte.
bool tiersLieAFacture(Map<String, Object?> piece, Map<String, Object?> f) {
  if (piece['factureTiersId'] != null && piece['factureTiersId'] == f['id']) return true;
  final n = _s(piece['factureNumero']);
  return n.isNotEmpty && n == _s(f['numero']) && _s(piece['tiersCode'] ?? f['tiersCode']) == _s(f['tiersCode']);
}

/// Le lien d'un lettrage à son RÈGLEMENT : l'identifiant local, ou (tiers, référence du paiement), unique par tiers (`REGLEMENT_TIERS_DEJA_SAISI`).
bool tiersLieAReglement(Map<String, Object?> lettrage, Map<String, Object?> r) {
  if (lettrage['reglementId'] != null && lettrage['reglementId'] == r['id']) return true;
  final ref = _s(lettrage['reglementRef']).toLowerCase();
  return ref.isNotEmpty && ref == _s(r['referencePaiement']).toLowerCase() && _s(lettrage['tiersCode']) == _s(r['tiersCode']);
}

/// L'avoir actif d'une facture, ou null.
Map<String, Object?>? tiersAvoirDe(Iterable<Map<String, Object?>> avoirs, Map<String, Object?> f) {
  for (final a in avoirs) {
    if (a['statut'] != 'archive' && tiersLieAFacture(a, f)) return a;
  }
  return null;
}

/// La créance d'UNE facture émise : montant dû (`net`) moins les lettrages actifs ; 0 si un avoir l'annule ou si la pièce n'est pas émise. Jamais négative.
int tiersCreanceFacture(Map<String, Object?> f, Iterable<Map<String, Object?>> lettrages, Iterable<Map<String, Object?>> avoirs) {
  if (f['statut'] != 'emise') return 0;
  if (tiersAvoirDe(avoirs, f) != null) return 0;
  var l = 0;
  for (final x in lettrages) {
    if (x['statut'] != 'archive' && tiersLieAFacture(x, f)) l += (x['montant'] as num).toInt();
  }
  final dette = (f['net'] as num).toInt() - l;
  return dette < 0 ? 0 : dette;
}

/// Le reste à lettrer d'un règlement reçu.
int tiersResteNonLettre(Map<String, Object?> r, Iterable<Map<String, Object?>> lettrages) {
  var l = 0;
  for (final x in lettrages) {
    if (x['statut'] != 'archive' && tiersLieAReglement(x, r)) l += (x['montant'] as num).toInt();
  }
  return (r['montant'] as num).toInt() - l;
}

/// Le LETTRAGE d'un règlement sur des factures : `{ok: true, lettre, resteNonLettre}` ou le refus nommé, dans l'ordre de la maquette (droit, règlement, vide, puis par facture : doublon,
/// émise, autre tiers, avoir, montant entier positif, au-delà du dû ; enfin au-delà du reste du règlement). N'écrit rien.
Map<String, Object?> tiersLettrer({
  required bool droit,
  required String libelleRole,
  required Map<String, Object?>? reglement,
  required List<Map<String, Object?>> affectations,
  required Iterable<Map<String, Object?>> factures,
  required Iterable<Map<String, Object?>> lettrages,
  required Iterable<Map<String, Object?>> avoirs,
}) {
  if (!droit) {
    return aibRefus('LETTRAGE_TIERS_RESERVE', 'Lettrer un règlement de tiers payeur est un droit réservé de la fiche du rôle (« $tiersGesteCorriger ») : « $libelleRole » ne l’a pas.', 'Demander ce geste à un rôle qui détient le droit « $tiersGesteCorriger ».');
  }
  if (reglement == null || reglement['statut'] == 'archive') return aibRefus('REGLEMENT_TIERS_INTROUVABLE', 'Le règlement demandé n’existe pas.', 'Choisir un règlement de la liste.');
  if (affectations.isEmpty) return aibRefus('LETTRAGE_TIERS_VIDE', 'Aucune facture n’est choisie : un lettrage affecte le règlement à au moins une facture.', 'Choisir la ou les factures.');
  final reste = tiersResteNonLettre(reglement, lettrages);
  var somme = 0;
  final vues = <Object?>{};
  for (final a in affectations) {
    final id = a['factureTiersId'];
    final f = [for (final x in factures) if (x['id'] == id) x].firstOrNull;
    if (!vues.add(id)) return aibRefus('LETTRAGE_TIERS_FACTURE_DOUBLE', 'La facture est répétée dans le lettrage.', 'Une ligne par facture.');
    if (f == null || f['statut'] != 'emise') return aibRefus('LETTRAGE_TIERS_FACTURE_INCONNUE', 'La facture « ${_s(id)} » n’existe pas ou n’est pas émise.', 'Choisir une facture émise.');
    if (f['tiersCode'] != reglement['tiersCode']) {
      return aibRefus('LETTRAGE_TIERS_AUTRE_TIERS', 'La facture ${f['numero']} est celle du tiers ${f['tiersCode']}, le règlement vient de ${reglement['tiersCode']}.', 'Lettrer un règlement sur les factures de SON tiers.');
    }
    if (tiersAvoirDe(avoirs, f) != null) {
      return aibRefus('LETTRAGE_TIERS_FACTURE_ANNULEE', 'La facture ${f['numero']} est annulée par un avoir.', 'Choisir une facture due.');
    }
    final m = a['montant'] is num ? a['montant'] as num : num.tryParse(_s(a['montant']));
    if (m == null || !_entier(m) || m <= 0) {
      return aibRefus('LETTRAGE_TIERS_MONTANT_INVALIDE', 'Le montant lettré sur ${f['numero']} (« ${_s(a['montant'])} ») est un entier de FCFA strictement positif.', 'Saisir le montant.');
    }
    final du = tiersCreanceFacture(f, lettrages, avoirs);
    if (m > du) return aibRefus('LETTRAGE_TIERS_DEPASSE', 'Le montant lettré sur ${f['numero']} dépasse ce qui reste dû ($du).', 'Réduire le montant.');
    somme += m.toInt();
  }
  if (somme > reste) return aibRefus('LETTRAGE_TIERS_AU_DELA_DU_REGLEMENT', 'Le lettrage ($somme) dépasse le reste à lettrer du règlement ${reglement['numero']} ($reste).', 'Réduire les montants.');
  return {'ok': true, 'lettre': somme, 'resteNonLettre': reste - somme};
}

/// La BALANCE ÂGÉE des tiers payeurs à [date] : une ligne par tiers (facturé, dû, tranches lues en base), les règlements non lettrés dits à part. Les factures annulées par avoir
/// et les pièces non émises n'y comptent pas ; une échéance sans délai convenu est NON CALCULABLE (comptée à part, jamais zéro).
Map<String, Object?> tiersCreances({
  required String date,
  required Iterable<Map<String, Object?>> factures,
  required Iterable<Map<String, Object?>> lettrages,
  required Iterable<Map<String, Object?>> avoirs,
  required Iterable<Map<String, Object?>> reglements,
  required TranchesCreances tranches,
}) {
  final par = <String, Map<String, Object?>>{};
  for (final f in factures) {
    if (f['statut'] != 'emise') continue;
    if (tiersAvoirDe(avoirs, f) != null) continue;
    final dette = tiersCreanceFacture(f, lettrages, avoirs);
    final l = par.putIfAbsent('${f['tiersCode']}',
        () => {'code': f['tiersCode'], 'nom': f['tiersNom'], 'factures': 0, 'facture': 0, 'du': 0, 'moins30': 0, 'de30a90': 0, 'plus90': 0, 'enRetard': 0, 'echeanceIncalculable': 0});
    l['factures'] = (l['factures'] as int) + 1;
    l['facture'] = (l['facture'] as int) + (f['net'] as num).toInt();
    l['du'] = (l['du'] as int) + dette;
    if (dette > 0) {
      final age = DateTime.parse('${date}T00:00:00Z').difference(DateTime.parse('${_jour(f['date'])}T00:00:00Z')).inDays;
      final tr = pcTrancheCreance(age, tranches);
      final t = tr == '30a90' ? 'de30a90' : tr;
      l[t] = (l[t] as int) + dette;
      final delai = f['delaiPaiementJours'];
      if (delai == null) {
        l['echeanceIncalculable'] = (l['echeanceIncalculable'] as int) + dette;
      } else {
        final ech = DateTime.parse('${_jour(f['date'])}T00:00:00Z').add(Duration(days: (delai as num).toInt())).toIso8601String().substring(0, 10);
        if (ech.compareTo(date) < 0) l['enRetard'] = (l['enRetard'] as int) + dette;
      }
    }
  }
  final cles = par.keys.toList()..sort();
  final lignes = [for (final k in cles) par[k]!];
  final nonLettres = [
    for (final r in reglements)
      if (r['statut'] != 'archive' && tiersResteNonLettre(r, lettrages) > 0) {'id': r['id'], 'reste': tiersResteNonLettre(r, lettrages)}
  ];
  return {
    'lignes': lignes,
    'total': lignes.fold<int>(0, (n, l) => n + (l['du'] as int)),
    'nonLettre': nonLettres.fold<int>(0, (n, r) => n + (r['reste'] as int)),
  };
}

/// Les champs d'une facture à un tiers payeur qui ne se réécrivent plus une fois la pièce ÉMISE (les traces MECeF, elles, évoluent ; un numéro MECeF posé ne change plus).
const List<String> tiersChampsFiges = [
  'tiersCode', 'tiersVersionId', 'tiersVersion', 'tiersNom', 'ifuAcheteur', 'nomAcheteur', 'tiersAdresse', 'delaiPaiementJours', 'patientId', 'patientNom', 'patientCode', 'date', 'lignes',
  'base', 'ht', 'tva', 'numero', 'aibDecision', 'aibTaux', 'aibMontant', 'net', 'partPatientRestante', 'sourcesCle'
];

/// Le refus d'une écriture qui réécrit une pièce émise, tenu par la MÈRE au rejeu comme par le magasin du poste. [avant] : la fiche d'avant (null à la création) ; [apres] : la fiche telle
/// qu'elle serait. Rend `{code, motif, geste}` ou null.
Map<String, String>? refusRejeuFactureTiers(Map<String, Object?>? avant, Map<String, Object?> apres) {
  if (avant == null || avant['statut'] != 'emise') return null;
  String j(Object? o) => _s(o is Map || o is List ? o.toString() : o);
  for (final k in tiersChampsFiges) {
    if (j(avant[k]) != j(apres[k])) {
      return {
        'code': 'FACTURE_TIERS_FIGEE',
        'motif': 'La facture à un tiers payeur ${_s(avant['numero'])} est émise : le champ « $k » ne se réécrit jamais (une pièce émise se corrige par un avoir).',
        'geste': 'Émettre un avoir, puis refaire la facture.'
      };
    }
  }
  if (_s(avant['numeroMecef']).isNotEmpty && _s(avant['numeroMecef']) != _s(apres['numeroMecef'])) {
    return {'code': 'FACTURE_TIERS_NUMERO_MECEF_FIGE', 'motif': 'Un numéro MECeF posé ne se réécrit jamais.', 'geste': 'Laisser le numéro tel que l\'appareil l\'a rendu.'};
  }
  return null;
}
