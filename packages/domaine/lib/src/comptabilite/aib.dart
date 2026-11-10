// LE BARÈME DE L'AIB ET SES RÉGLAGES (Direction, 09/11/2026, lots A1 et L2), portés de `SIGH.baremeAib` et `SIGH.reglagesAib` (parcours.js) et rejoués sur les
// vecteurs `test/vecteurs/aib.json` (engendrés par `prototype_html/build/vecteurs-aib.js`, le moteur réel piloté dans Chrome).
//
// Fonctions PURES : l'appelant (magasin du poste) fournit les fiches ([AibDonnees]) et la date, écrit les fiches rendues, journalise (RG-12) et notifie. Aucune
// horloge, aucun taux, aucune date, aucun numéro de compte n'est codé ici : le taux se lit à la version datée du barème, la charge des 5 % et le branchement sur
// les achats à la version datée du réglage, les deux comptes sont CHOISIS par le comptable. Un taux ou un réglage sans version à la date se REFUSE en le nommant
// (AIB_SANS_BAREME, AIB_REGLAGE_SANS_VERSION) : jamais zéro, jamais une valeur supposée.
//
// Décisions de la Direction : Q3 le taux suit la situation de l'acheteur, versionné par date ; Q5 le branchement sur les écritures d'achat est DIFFÉRÉ
// (désactivé par défaut : le moteur liste, n'écrit rien) ; Q7 qui supporte les 5 % est un réglage (défaut « clinique », non arrêté : le texte officiel manque, aucun
// effet comptable n'en découle). Symboles préfixés `aib` / `Aib`.

import '../parametres/definitions.dart' show definitionDeParametre;
import '../parametres/parametres.dart' show Parametre;

typedef AibFiche = Map<String, Object?>;

/// Les rôles qui écrivent le barème et ses réglages (comme `ROLES_ECRITURE_AIB`) : la Direction lit, ne les écrit pas.
const List<String> aibRolesEcriture = ['comptable', 'admin', 'da'];

/// Les fiches que les fonctions lisent : une collection chacune, les fiches archivées (`statut == 'archive'`) sont ignorées.
class AibDonnees {
  const AibDonnees({
    this.situations = const [],
    this.bareme = const [],
    this.reglages = const [],
    this.comptes = const [],
    this.fournisseurs = const [],
    this.facturesFournisseurs = const [],
    this.ecritures = const [],
  });
  final List<AibFiche> situations;
  final List<AibFiche> bareme;
  final List<AibFiche> reglages;
  final List<AibFiche> comptes;
  final List<AibFiche> fournisseurs;
  final List<AibFiche> facturesFournisseurs;
  final List<AibFiche> ecritures;
}

/// Un refus NOMMÉ, dans la forme de la maquette : `{ok: false, code, motif, geste, …extra}`.
AibFiche aibRefus(String code, String motif, String? geste, [Map<String, Object?> extra = const {}]) => {'ok': false, 'code': code, 'motif': motif, 'geste': geste, ...extra};

/// Les définitions des quatre réglages (`D.REGLAGES_AIB`) : ce que le réglage ADMET, jamais sa valeur en vigueur.
const List<Map<String, Object?>> aibDefinitionsReglages = [
  {
    'cle': 'chargePrelevement',
    'type': 'choix',
    'libelle': 'Qui supporte le prélèvement de 5 %',
    'valeurs': [
      {'value': 'clinique', 'label': 'La clinique'},
      {'value': 'acheteur', 'label': 'L’acheteur'},
    ],
    'defaut': 'clinique',
    'aide': 'Texte officiel manquant : réglage non arrêté. Aucun effet comptable n’en découle, la valeur est portée par chaque vente et listée aux achats.',
  },
  {
    'cle': 'branchementAchats',
    'type': 'choix',
    'libelle': 'Brancher l’AIB sur les écritures d’achat',
    'valeurs': [
      {'value': 'desactive', 'label': 'Désactivé (le moteur liste, n’écrit rien)'},
      {'value': 'actif', 'label': 'Activé (écrit ce qui est listé)'},
    ],
    'defaut': 'desactive',
    'aide': 'Désactivé par défaut. L’activation exige le compte d’acompte, le compte de contrepartie et le réglage de la charge arrêtés.',
  },
  {
    'cle': 'compteAcompte',
    'type': 'compte',
    'libelle': 'Compte d’acompte (débit)',
    'defaut': null,
    'aide': 'Choisi par le comptable dans le plan comptable : aucun numéro n’est proposé d’office.',
  },
  {
    'cle': 'compteContrepartie',
    'type': 'compte',
    'libelle': 'Compte de contrepartie (crédit)',
    'defaut': null,
    'aide': 'Choisi par le comptable dans le plan comptable : une écriture s’équilibre sur deux comptes que la clinique désigne.',
  },
];

/// Les deux versions SEMÉES (défauts de la Direction), à la date d'effet d'attente du début de l'exercice 2026 ; aucun compte n'est semé.
const List<Map<String, Object?>> aibSemencesReglages = [
  {
    'cle': 'chargePrelevement',
    'valeur': 'clinique',
    'libelle': 'Qui supporte le prélèvement de 5 % : la clinique',
    'dateEffet': '2026-01-01',
    'source': 'Décision de la Direction du 09/11/2026 (Q7) : la clinique supporte le prélèvement, réglage à arrêter avec le texte officiel',
    'motif': 'Défaut de la Direction (date d’effet d’attente : début de l’exercice 2026).',
  },
  {
    'cle': 'branchementAchats',
    'valeur': 'desactive',
    'libelle': 'Brancher l’AIB sur les écritures d’achat : désactivé',
    'dateEffet': '2026-01-01',
    'source': 'Décision de la Direction du 09/11/2026 (Q5) : branchement différé',
    'motif': 'Défaut de la Direction : le moteur liste, il n’écrit rien (date d’effet d’attente : début de l’exercice 2026).',
  },
];

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Petits outils (les mêmes que la maquette : dates ISO AAAA-MM-JJ, arrondi à l'entier comme la caisse)
// ---------------------------------------------------------------------------------------------------------------------------------------------

bool _actif(AibFiche f) => f['statut'] != 'archive';
String _s(Object? v) => v == null ? '' : '$v';
bool _vide(Object? v) => v == null || v == '';
String _jour(String d) => d.length > 10 ? d.substring(0, 10) : d;
int _comparer(String a, String b) => a.compareTo(b);

/// `C.dateFR` d'une date ISO.
String aibDateFr(String iso) {
  final j = _jour(iso);
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(j);
  return m == null ? j : '${m[3]}/${m[2]}/${m[1]}';
}

/// La veille d'une date ISO.
String aibVeille(String iso) {
  final p = _jour(iso).split('-').map(int.parse).toList();
  final d = DateTime.utc(p[0], p[1], p[2]).subtract(const Duration(days: 1));
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// `divArrondi` : `floor((2a + b) / (2b))`, l'arrondi à l'entier de la caisse (moitié vers le haut).
int aibDivArrondi(num a, num b) => ((2 * a + b) / (2 * b)).floor();

/// Les espaces, y compris l'insécable et la fine insécable, sont retirés d'un IFU.
String aibNormaliserIfu(Object? x) => _s(x).replaceAll(RegExp('[\\s  ]'), '');

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Le barème : taux de la situation à la date
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les situations actives, dans l'ordre d'affichage (puis par code).
List<AibFiche> aibSituationsActives(AibDonnees d) {
  final l = d.situations.where(_actif).toList();
  num ordre(AibFiche f) => (f['ordre'] is num && f['ordre'] != 0) ? f['ordre'] as num : 99;
  l.sort((a, b) {
    final c = ordre(a).compareTo(ordre(b));
    return c != 0 ? c : _comparer(_s(a['code']), _s(b['code']));
  });
  return l;
}

/// Les versions du barème d'une situation, de la plus ancienne à la plus récente.
List<AibFiche> aibVersionsBareme(AibDonnees d, String situation) =>
    (d.bareme.where((v) => _actif(v) && v['situation'] == situation).toList())..sort((a, b) => _comparer(_s(a['dateEffet']), _s(b['dateEffet'])));

/// Le taux de la situation à la date : `{ok, taux, arrete, dateEffet, dateFin, version, versionId, situation, libelle, source, date}` ou le refus nommé AIB_SANS_BAREME.
AibFiche aibTauxALaDate(AibDonnees d, String situation, String date) {
  final j = _jour(date);
  AibFiche? sit;
  for (final s in d.situations) {
    if (_actif(s) && s['code'] == situation) {
      sit = s;
      break;
    }
  }
  if (sit == null) {
    return aibRefus(
        'AIB_SANS_BAREME',
        'La situation « $situation » n’est pas active au barème de l’AIB : aucun taux ne peut être rendu (un tiret n’est pas un zéro).',
        'Choisir une situation listée, ou la créer puis lui donner une version à l’écran « Barème de l’AIB ».',
        {'situation': situation, 'date': j});
  }
  final toutes = aibVersionsBareme(d, situation);
  final couvrantes = toutes.where((v) => _s(v['dateEffet']).compareTo(j) <= 0 && (_vide(v['dateFin']) || _s(v['dateFin']).compareTo(j) >= 0)).toList();
  final v = couvrantes.isEmpty ? null : couvrantes.last;
  final taux = v == null ? null : (v['taux'] is num ? v['taux'] as num : num.tryParse(_s(v['taux'])));
  if (v == null || _vide(v['taux']) || taux == null || !taux.isFinite) {
    return aibRefus(
        'AIB_SANS_BAREME',
        'Aucune version du barème de l’AIB ne couvre la situation « ${sit['libelle']} » au ${aibDateFr(j)} : le taux n’est pas arrêté, il ne vaut pas zéro.',
        'Ajouter une version de cette situation à l’écran « Barème de l’AIB » (taux, date d’effet, source), ou choisir une autre date.',
        {'situation': situation, 'date': j});
  }
  return {
    'ok': true,
    'taux': taux,
    'arrete': v['aValider'] != true,
    'dateEffet': v['dateEffet'],
    'dateFin': _vide(v['dateFin']) ? null : v['dateFin'],
    'version': toutes.indexOf(v) + 1,
    'versionId': v['id'],
    'situation': situation,
    'libelle': sit['libelle'],
    'source': _vide(v['source']) ? null : v['source'],
    'date': j,
  };
}

/// La situation d'un acheteur d'après son IFU, et le taux de la date. Un IFU de 13 chiffres est PRÉSUMÉ actif (la DGI n'est pas interrogeable ici).
AibFiche aibTauxPourAcheteur(AibDonnees d, {Object? ifu, required String date}) {
  final i = aibNormaliserIfu(ifu);
  final String declencheur;
  if (i == '') {
    declencheur = 'ifu_absent';
  } else if (RegExp(r'^\d{13}$').hasMatch(i)) {
    declencheur = 'ifu_renseigne';
  } else {
    return aibRefus('IFU_INVALIDE', 'L’IFU de l’acheteur (« $i ») doit comporter exactement 13 chiffres.', 'Corriger l’IFU, ou le laisser vide pour un particulier.');
  }
  AibFiche? sit;
  for (final s in aibSituationsActives(d)) {
    if (s['declencheur'] == declencheur) {
      sit = s;
      break;
    }
  }
  if (sit == null) {
    return aibRefus(
        'AIB_SANS_BAREME',
        'Aucune situation active du barème de l’AIB ne se choisit d’office quand ${declencheur == 'ifu_absent' ? 'aucun IFU n’est saisi' : 'un IFU est saisi'}.',
        'Régler le déclencheur d’une situation à l’écran « Barème de l’AIB », ou choisir le taux à la main.',
        {'date': _jour(date)});
  }
  final r = aibTauxALaDate(d, '${sit['code']}', date);
  if (r['ok'] != true) return r;
  final presomption = declencheur == 'ifu_renseigne';
  return {...r, 'presomption': presomption, 'avertissement': presomption ? 'IFU présumé actif : la maquette ne peut pas interroger la DGI, l’activité de l’IFU n’est pas vérifiée.' : null};
}

/// Les taux PROPOSÉS à la caisse à la date : un choix par situation active qui a un taux en vigueur, et le défaut selon l'IFU saisi.
AibFiche aibTauxProposes(AibDonnees d, {Object? ifu, required String date}) {
  final j = _jour(date);
  final choix = <AibFiche>[];
  for (final s in aibSituationsActives(d)) {
    final r = aibTauxALaDate(d, '${s['code']}', j);
    if (r['ok'] == true) {
      choix.add({'situation': s['code'], 'libelle': s['libelle'], 'declencheur': s['declencheur'], 'taux': r['taux'], 'arrete': r['arrete'], 'version': r['version'], 'versionId': r['versionId']});
    }
  }
  final defaut = aibTauxPourAcheteur(d, ifu: ifu, date: j);
  return {'ok': true, 'date': j, 'choix': choix, 'defaut': defaut['ok'] == true ? defaut : null, 'defautRefus': defaut['ok'] == true ? null : defaut};
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Les réglages : valeur à la date, charge, branchement
// ---------------------------------------------------------------------------------------------------------------------------------------------

AibFiche? aibDefinitionReglage(String cle) {
  for (final d in aibDefinitionsReglages) {
    if (d['cle'] == cle) return d;
  }
  return null;
}

/// Les versions d'un réglage, de la plus ancienne à la plus récente.
List<AibFiche> aibVersionsReglage(AibDonnees d, String cle) =>
    (d.reglages.where((v) => _actif(v) && v['cle'] == cle).toList())..sort((a, b) => _comparer(_s(a['dateEffet']), _s(b['dateEffet'])));

/// Le compte du plan comptable (actif) de ce numéro, ou null.
AibFiche? aibCompteDuPlan(AibDonnees d, Object? numero) {
  final n = _s(numero).trim();
  if (n.isEmpty) return null;
  for (final c in d.comptes) {
    if (_actif(c) && _s(c['num']) == n) return c;
  }
  return null;
}

/// La valeur du réglage à la date, ou le refus nommé AIB_REGLAGE_SANS_VERSION (jamais une valeur inventée).
AibFiche aibReglageALaDate(AibDonnees d, String cle, String date) {
  final j = _jour(date);
  final def = aibDefinitionReglage(cle);
  if (def == null) {
    return aibRefus('AIB_REGLAGE_INCONNU', 'Le réglage « $cle » n’existe pas parmi les réglages de l’AIB.', 'Choisir un réglage listé à l’écran « Barème de l’AIB ».', {'cle': cle});
  }
  final toutes = aibVersionsReglage(d, cle);
  final couvrantes = toutes.where((v) => _s(v['dateEffet']).compareTo(j) <= 0 && (_vide(v['dateFin']) || _s(v['dateFin']).compareTo(j) >= 0)).toList();
  final v = couvrantes.isEmpty ? null : couvrantes.last;
  if (v == null || _vide(v['valeur'])) {
    return aibRefus(
        'AIB_REGLAGE_SANS_VERSION',
        'Aucune version du réglage « ${def['libelle']} » ne couvre le ${aibDateFr(j)} : la valeur n’est pas arrêtée, rien n’est supposé.',
        def['type'] == 'compte' ? 'Choisir le compte à l’écran « Barème de l’AIB », onglet « Réglages ».' : 'Ajouter une version de ce réglage à l’écran « Barème de l’AIB », onglet « Réglages ».',
        {'cle': cle, 'date': j});
  }
  return {
    'ok': true,
    'cle': cle,
    'valeur': v['valeur'],
    'arrete': v['aValider'] != true,
    'dateEffet': v['dateEffet'],
    'dateFin': _vide(v['dateFin']) ? null : v['dateFin'],
    'version': toutes.indexOf(v) + 1,
    'versionId': v['id'],
    'source': _vide(v['source']) ? null : v['source'],
    'date': j,
  };
}

/// Qui supporte les 5 % à la date. Un réglage non arrêté se DIT (`arrete: false`, `message`) ; il ne change aucune écriture.
AibFiche aibChargeALaDate(AibDonnees d, String date) {
  final r = aibReglageALaDate(d, 'chargePrelevement', date);
  if (r['ok'] != true) return r;
  final def = aibDefinitionReglage('chargePrelevement')!;
  final valeurs = (def['valeurs'] as List).cast<Map<String, Object?>>();
  String lib = '${r['valeur']}';
  for (final x in valeurs) {
    if (x['value'] == r['valeur']) {
      lib = '${x['label']}';
      break;
    }
  }
  return {
    ...r,
    'libelle': lib,
    'message': r['arrete'] == true ? null : 'Réglage non arrêté : le texte officiel manque. L’AIB reste affiché comme un acompte imputable, sans écriture.',
  };
}

/// L'état du branchement sur les achats à la date. `actif` n'est vrai que si la version est « actif » ET arrêtée, les deux comptes choisis et arrêtés, la charge arrêtée.
AibFiche aibBranchementALaDate(AibDonnees d, String date) {
  final j = _jour(date);
  final b = aibReglageALaDate(d, 'branchementAchats', j);
  final raisons = <String>[];
  final out = <String, Object?>{
    'ok': true,
    'date': j,
    'actif': false,
    'valeur': b['ok'] == true ? b['valeur'] : 'desactive',
    'arrete': b['ok'] == true ? b['arrete'] : null,
    'versionId': b['ok'] == true ? b['versionId'] : null,
    'compteAcompte': null,
    'compteContrepartie': null,
    'raisons': raisons,
  };
  final a = aibReglageALaDate(d, 'compteAcompte', j);
  final c = aibReglageALaDate(d, 'compteContrepartie', j);
  final ch = aibChargeALaDate(d, j);
  if (a['ok'] == true) {
    out['compteAcompte'] = '${a['valeur']}';
    out['compteAcompteArrete'] = a['arrete'];
  }
  if (c['ok'] == true) {
    out['compteContrepartie'] = '${c['valeur']}';
    out['compteContrepartieArrete'] = c['arrete'];
  }
  out['chargeArretee'] = ch['ok'] == true ? ch['arrete'] : false;
  if (b['ok'] != true || b['valeur'] != 'actif') {
    raisons.add('Le branchement est désactivé : le moteur liste, il n’écrit rien.');
    return out;
  }
  if (b['arrete'] != true) raisons.add('Le réglage du branchement n’est pas arrêté.');
  if (a['ok'] != true) {
    raisons.add('Le compte d’acompte n’est pas choisi.');
  } else if (a['arrete'] != true) {
    raisons.add('Le compte d’acompte n’est pas arrêté.');
  }
  if (c['ok'] != true) {
    raisons.add('Le compte de contrepartie n’est pas choisi.');
  } else if (c['arrete'] != true) {
    raisons.add('Le compte de contrepartie n’est pas arrêté.');
  }
  if (ch['ok'] != true || ch['arrete'] != true) raisons.add('Le réglage de la charge des 5 % n’est pas arrêté.');
  out['actif'] = raisons.isEmpty;
  return out;
}

/// La garde d'une version de réglage : sa valeur, son réglage et sa date d'effet ne se réécrivent pas. Rend le refus (texte), ou null.
String? aibVersionFigee(AibFiche avant, AibFiche apres) {
  if (_s(avant['valeur']) != _s(apres['valeur']) || avant['cle'] != apres['cle'] || _s(avant['dateEffet']) != _s(apres['dateEffet'])) {
    return 'AIB_VERSION_FIGEE : une version de réglage ne se réécrit pas (valeur, réglage, date d’effet). Ajouter une nouvelle version à une date d’effet postérieure.';
  }
  return null;
}

/// Qui peut écrire : le rôle (libellé fourni pour le motif), et le poste (un fileul lit, la mère écrit). Rend le refus nommé, ou null.
AibFiche? aibMotifEcriture({required String role, required String libelleRole, bool fileul = false}) {
  if (!aibRolesEcriture.contains(role)) {
    return aibRefus('AIB_ECRITURE_RESERVEE', 'Le barème de l’AIB se tient par le comptable, la Directrice Administrative ou l’administrateur. Profil : $libelleRole.',
        'Demander la modification au comptable ; la Direction consulte le barème sans l’écrire.');
  }
  if (fileul) {
    return aibRefus('AIB_POSTE_FILEUL', 'Ce poste est un fileul : le barème de l’AIB est tenu par la mère et se lit ici sans s’y écrire.', 'Faire la modification depuis le poste mère.');
  }
  return null;
}

/// Une version nouvelle d'un réglage (`SIGH.reglagesAib.definir`) : valeur admise, date d'effet postérieure à la plus récente, motif. Elle FERME la précédente à la veille.
/// Rend, en cas de succès, la sortie de la maquette plus `fiche` (la fiche à INSÉRER, avec [id] et le [marquage] : le patch de validation du profil, par exemple
/// `{'aValider': false, 'valideLe': …, 'validePar': …, 'valideRole': …}` ; sans marquage la version naît « à valider ») et `fermeture` (`{id, dateFin}` de la
/// précédente à fermer, ou null). `creeLe` : AAAA-MM-JJ du jour ; `auteur` : qui écrit.
AibFiche aibDefinirReglage(
  AibDonnees d,
  AibFiche entree, {
  required String role,
  required String libelleRole,
  bool fileul = false,
  required String id,
  required String creeLe,
  required String auteur,
  Map<String, Object?>? marquage,
}) {
  final refus = aibMotifEcriture(role: role, libelleRole: libelleRole, fileul: fileul);
  if (refus != null) return refus;
  final cle = _s(entree['cle']);
  final def = aibDefinitionReglage(cle);
  if (def == null) return aibRefus('AIB_REGLAGE_INCONNU', 'Le réglage « $cle » n’existe pas parmi les réglages de l’AIB.', 'Choisir un réglage listé.');
  final valeur = _s(entree['valeur']).trim();
  final valeurs = ((def['valeurs'] as List?) ?? const []).cast<Map<String, Object?>>();
  if (def['type'] == 'choix' && !valeurs.any((x) => x['value'] == valeur)) {
    return aibRefus('AIB_VALEUR_INVALIDE', 'La valeur « $valeur » n’est pas admise pour « ${def['libelle']} » (${valeurs.map((x) => x['value']).join(', ')}).', 'Choisir une valeur proposée.');
  }
  if (def['type'] == 'compte' && aibCompteDuPlan(d, valeur) == null) {
    return aibRefus('AIB_COMPTE_INCONNU', 'Le compte « $valeur » n’est pas au plan comptable : aucun numéro n’est inventé.', 'Choisir un compte du plan comptable (ou le créer d’abord à l’écran du plan).');
  }
  final brute = entree['dateEffet'];
  final dateEffet = _vide(brute) ? '' : _jour(_s(brute));
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateEffet)) {
    return aibRefus('AIB_DATE_INVALIDE', 'La date d’effet est absente ou illisible.', 'Choisir la date à partir de laquelle le réglage s’applique.');
  }
  if (_s(entree['motif']).trim().isEmpty) return aibRefus('AIB_MOTIF_ABSENT', 'Le motif de cette version est obligatoire.', 'Dire pourquoi le réglage change.');
  final existantes = aibVersionsReglage(d, cle);
  final derniere = existantes.isEmpty ? null : existantes.last;
  if (existantes.any((v) => _s(v['dateEffet']) == dateEffet)) {
    return aibRefus('AIB_DATE_EXISTANTE', 'Une version de ce réglage commence déjà le ${aibDateFr(dateEffet)} : une version ne se réécrit pas.', 'Choisir une date d’effet postérieure.');
  }
  if (derniere != null && _s(derniere['dateEffet']).compareTo(dateEffet) > 0) {
    return aibRefus(
        'AIB_DATE_ANTERIEURE',
        'La version la plus récente de ce réglage commence le ${aibDateFr(_s(derniere['dateEffet']))} : une version insérée avant elle masquerait l’historique.',
        'Choisir une date d’effet postérieure au ${aibDateFr(_s(derniere['dateEffet']))}.');
  }
  if (cle == 'branchementAchats' && valeur == 'actif') {
    final a = aibReglageALaDate(d, 'compteAcompte', dateEffet);
    final c = aibReglageALaDate(d, 'compteContrepartie', dateEffet);
    final ch = aibChargeALaDate(d, dateEffet);
    final manque = <String>[];
    if (a['ok'] != true) {
      manque.add('le compte d’acompte n’est pas choisi');
    } else if (a['arrete'] != true) {
      manque.add('le compte d’acompte n’est pas arrêté');
    }
    if (c['ok'] != true) {
      manque.add('le compte de contrepartie n’est pas choisi');
    } else if (c['arrete'] != true) {
      manque.add('le compte de contrepartie n’est pas arrêté');
    }
    if (ch['ok'] != true || ch['arrete'] != true) manque.add('le réglage de la charge des 5 % n’est pas arrêté');
    if (manque.isNotEmpty) {
      return aibRefus('AIB_BRANCHEMENT_INCOMPLET', 'L’activation est refusée : ${manque.join(', ')}.',
          'Choisir les deux comptes à une date d’effet antérieure ou égale, arrêter la charge des 5 %, puis activer.', {'manque': manque});
    }
  }
  final veillee = aibVeille(dateEffet);
  AibFiche? fermeture;
  if (derniere != null && (_vide(derniere['dateFin']) || _s(derniere['dateFin']).compareTo(veillee) > 0)) {
    fermeture = {'id': derniere['id'], 'dateFin': veillee};
  }
  String libValeur = valeur;
  if (def['type'] == 'choix') {
    for (final x in valeurs) {
      if (x['value'] == valeur) {
        libValeur = '${x['label']}';
        break;
      }
    }
  }
  final source = _s(entree['source']).trim();
  final patch = marquage ?? const {'aValider': true};
  final fiche = <String, Object?>{
    'id': id,
    'statut': 'actif',
    'cle': cle,
    'valeur': valeur,
    'libelle': '${def['libelle']} : $libValeur',
    'dateEffet': dateEffet,
    'dateFin': null,
    'source': source.isEmpty ? null : source,
    'motif': _s(entree['motif']).trim(),
    'creeLe': creeLe,
    'creePar': auteur,
    ...patch,
  };
  return {
    'ok': true,
    'id': id,
    'version': existantes.length + 1,
    'cle': cle,
    'valeur': valeur,
    'dateEffet': dateEffet,
    'precedente': derniere?['id'],
    'precedenteFermeeLe': fermeture == null ? null : veillee,
    'enAttenteDeValidation': patch['aValider'] == true,
    'fiche': fiche,
    'fermeture': fermeture,
  };
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Les achats : ce qu'il faudrait écrire, puis ce qui s'écrit quand le branchement est actif
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Ce que le branchement sur les achats écrirait, facture par facture, SANS rien écrire. La situation du fournisseur se tire de son IFU (même règle que la caisse),
/// le taux du barème de la date de la facture, la charge du réglage de la même date. Une ligne sans taux porte son refus nommé, jamais un montant à zéro. La base est
/// le montant facturé, le montant est arrondi à l'entier comme la caisse. [aujourdhui] : AAAA-MM-JJ, la borne par défaut de la période.
AibFiche aibAchatsAEcrire(AibDonnees d, {String? du, String? au, required String aujourdhui}) {
  final fin = _vide(au) ? aujourdhui : _jour(au!);
  final debut = _vide(du) ? '${fin.substring(0, 4)}-01-01' : _jour(du!);
  final br = aibBranchementALaDate(d, fin);
  final fournisseurs = <String, AibFiche>{for (final f in d.fournisseurs) _s(f['code']): f};
  final posees = <String, String>{};
  for (final e in d.ecritures) {
    if (e['statut'] != 'archive' && !_vide(e['aibFactureId'])) posees['${e['aibFactureId']}'] = _s(e['numero']);
  }
  final factures = d.facturesFournisseurs.where((f) => _actif(f) && !_vide(f['date']) && _s(f['date']).compareTo(debut) >= 0 && _s(f['date']).compareTo(fin) <= 0).toList()
    ..sort((a, b) {
      final c = _comparer(_s(a['date']), _s(b['date']));
      return c != 0 ? c : _comparer(_s(a['reference']), _s(b['reference']));
    });
  final lignes = <AibFiche>[];
  for (final f in factures) {
    final four = fournisseurs['${f['fournisseur']}'] ?? const <String, Object?>{};
    final nom = !_vide(f['fournisseurNom']) ? f['fournisseurNom'] : (!_vide(four['nom']) ? four['nom'] : f['fournisseur']);
    final dateF = _jour(_s(f['date']));
    final base = f['montantFacture'] is num ? f['montantFacture'] as num : (num.tryParse(_s(f['montantFacture'])) ?? 0);
    final ligne = <String, Object?>{
      'factureId': f['id'],
      'reference': f['reference'],
      'date': dateF,
      'fournisseur': nom,
      'ifu': _vide(four['ifu']) ? null : four['ifu'],
      'base': base,
      'ecriteSous': posees['${f['id']}'],
    };
    final t = aibTauxPourAcheteur(d, ifu: four['ifu'] ?? '', date: dateF);
    final ch = aibChargeALaDate(d, dateF);
    ligne['supporte'] = ch['ok'] == true ? ch['valeur'] : null;
    ligne['chargeArretee'] = ch['ok'] == true ? ch['arrete'] : null;
    if (t['ok'] != true) {
      ligne['refus'] = t['code'];
      ligne['motif'] = t['motif'];
      lignes.add(ligne);
      continue;
    }
    ligne['taux'] = t['taux'];
    ligne['situation'] = t['situation'];
    ligne['versionId'] = t['versionId'];
    ligne['arrete'] = t['arrete'];
    ligne['aib'] = aibDivArrondi(base * (t['taux'] as num), 100);
    lignes.add(ligne);
  }
  bool aEcrire(AibFiche l) => l['refus'] == null && l['ecriteSous'] == null && (l['aib'] as num? ?? 0) > 0;
  final actif = br['actif'] == true;
  return {
    'ok': true,
    'du': debut,
    'au': fin,
    'branchement': br,
    'lignes': lignes,
    'aEcrire': lignes.where(aEcrire).length,
    'ecrire': actif,
    'message': actif
        ? 'Branchement actif : « Écrire » pose en brouillon une pièce par facture listée, rien d’autre.'
        : 'Branchement non actif : la liste est un APERÇU, aucune écriture n’est posée. ${(br['raisons'] as List).join(' ')}',
  };
}

/// Écrit EXACTEMENT ce que la liste affiche, quand le branchement est actif : une pièce de deux lignes (débit acompte, crédit contrepartie) par facture, en brouillon,
/// équilibrée (RG-10), jamais deux fois la même facture. Désactivé ou incomplet : refus nommé AIB_BRANCHEMENT_DESACTIVE, RIEN n'est écrit.
/// Rend `{ok, pieces, refusees, du, au, lignesEcritures}` : `lignesEcritures` sont les fiches d'écriture à INSÉRER, dans l'ordre (le débit puis le crédit de chaque pièce).
AibFiche aibEcrireAchats(
  AibDonnees d, {
  String? du,
  String? au,
  required String aujourdhui,
  required String role,
  required String libelleRole,
  bool fileul = false,
}) {
  final refus = aibMotifEcriture(role: role, libelleRole: libelleRole, fileul: fileul);
  if (refus != null) return refus;
  final ap = aibAchatsAEcrire(d, du: du, au: au, aujourdhui: aujourdhui);
  final br = ap['branchement'] as AibFiche;
  if (br['actif'] != true) {
    return aibRefus(
        'AIB_BRANCHEMENT_DESACTIVE',
        'Le branchement de l’AIB sur les écritures d’achat n’est pas actif : aucune écriture n’est posée. ${(br['raisons'] as List).join(' ')}',
        'Le comptable choisit les deux comptes, arrête la charge puis active le branchement à l’écran « Barème de l’AIB », onglet « Réglages ».',
        {'raisons': br['raisons']});
  }
  final cA = aibCompteDuPlan(d, br['compteAcompte']);
  final cC = aibCompteDuPlan(d, br['compteContrepartie']);
  if (cA == null || cC == null) {
    return aibRefus('AIB_COMPTE_INCONNU', 'Un des deux comptes choisis n’est plus au plan comptable : aucune écriture n’est posée.', 'Rechoisir le compte à l’écran « Barème de l’AIB ».');
  }
  final pieces = <AibFiche>[];
  final ecritures = <AibFiche>[];
  for (final l in (ap['lignes'] as List).cast<AibFiche>()) {
    if (l['refus'] != null || l['ecriteSous'] != null || !((l['aib'] as num? ?? 0) > 0)) continue;
    final numero = 'AIB-${l['reference']}';
    final base = <String, Object?>{
      'numero': numero,
      'date': l['date'],
      'journal': 'OD',
      'journalLibelle': 'Opérations diverses',
      'libelle': 'AIB sur achat ${l['reference']} (${l['taux']} %), ${l['fournisseur']}',
      'pieceId': l['factureId'],
      'pieceNumero': l['reference'],
      'aibFactureId': l['factureId'],
      'aibTaux': l['taux'],
      'aibSupporte': l['supporte'],
      'origine': 'Automatique : AIB sur achat',
      'statut': 'brouillon',
    };
    ecritures.add({...base, 'compte': _s(cA['num']), 'compteLibelle': cA['libelle'], 'debit': l['aib'], 'credit': 0});
    ecritures.add({...base, 'compte': _s(cC['num']), 'compteLibelle': cC['libelle'], 'debit': 0, 'credit': l['aib']});
    pieces.add({'factureId': l['factureId'], 'numero': numero, 'montant': l['aib']});
  }
  return {'ok': true, 'pieces': pieces, 'refusees': <Object?>[], 'du': ap['du'], 'au': ap['au'], 'lignesEcritures': ecritures};
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Les réglages au REGISTRE DES PARAMÈTRES du poste (lot L0) : une version datée de `parametres` devient une fiche de réglage
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Le préfixe des quatre réglages au registre des paramètres : `bareme_aib.chargePrelevement`, `bareme_aib.branchementAchats`, `bareme_aib.compteAcompte`,
/// `bareme_aib.compteContrepartie`.
const String aibPrefixeParametre = 'bareme_aib.';

/// Les versions du registre des paramètres relues sous la forme des fiches de réglage que les fonctions ci-dessus lisent. Le registre est le SEUL endroit où
/// le poste tient ces valeurs (famille R : la mère écrit, les fileuls reçoivent) ; cette fonction ne stocke rien.
///
/// Une version posée par un agent (date d'effet) est ARRÊTÉE : elle l'a été par un profil qui peut régler le paramètre. La version 0, semée avec le défaut de la
/// Direction (date d'effet absente, « depuis toujours »), est « à valider » : elle ne devient arrêtée que lorsqu'une version datée la remplace. Une version sans valeur
/// (compte vide) n'est pas une valeur : elle se lit « sans version ». La date de fin de chaque version est la veille de la date d'effet de la suivante, comme la
/// maquette la pose à la fermeture. Sans version 0 en base (poste qui n'a pas encore reçu la mère), la définition du registre porte le défaut.
List<AibFiche> aibReglagesDepuisParametres(Iterable<Parametre> versions) {
  final out = <AibFiche>[];
  for (final def in aibDefinitionsReglages) {
    final cle = '${def['cle']}';
    final vs = versions.where((v) => v.cle == '$aibPrefixeParametre$cle').toList()
      ..sort((a, b) {
        final c = (a.dateEffet ?? '').compareTo(b.dateEffet ?? '');
        return c != 0 ? c : a.version.compareTo(b.version);
      });
    if (!vs.any((v) => v.dateEffet == null)) {
      final d = definitionDeParametre('$aibPrefixeParametre$cle');
      if (d != null) {
        out.add({'id': '$aibPrefixeParametre$cle@defaut@0', 'statut': 'actif', 'cle': cle, 'valeur': d.defaut, 'dateEffet': '0001-01-01', 'dateFin': null, 'aValider': true,
          'source': d.source, 'motif': 'Défaut semé', 'creePar': 'semis'});
      }
    }
    final fiches = <AibFiche>[
      for (final v in vs)
        {
          'id': v.id,
          'statut': 'actif',
          'cle': cle,
          'valeur': v.valeur,
          'dateEffet': v.dateEffet ?? '0001-01-01',
          'dateFin': null,
          'aValider': v.dateEffet == null,
          'source': v.source,
          'motif': v.motif,
          'creeLe': v.creeLe,
          'creePar': v.auteur,
        }
    ];
    // La version 0 semée passe en tête (elle porte « depuis toujours »).
    final existante = out.where((f) => f['cle'] == cle).toList();
    final toutes = [...existante, ...fiches]..sort((a, b) => _comparer(_s(a['dateEffet']), _s(b['dateEffet'])));
    out.removeWhere((f) => f['cle'] == cle);
    for (var i = 0; i < toutes.length; i++) {
      final suivante = toutes.skip(i + 1).where((x) => _s(x['dateEffet']).compareTo(_s(toutes[i]['dateEffet'])) > 0).toList();
      out.add({...toutes[i], 'dateFin': suivante.isEmpty ? null : aibVeille(_s(suivante.first['dateEffet']))});
    }
  }
  return out;
}
