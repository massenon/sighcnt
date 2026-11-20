/// Reconnaissance d'intention de l'assistant, lot AST-0 : un OUTIL DE MESURE, jamais livré au poste.
///
/// Règles déterministes, en français : normalisation sans casse ni accents, fautes simples tolérées par une distance d'édition BORNÉE, entités (code patient, code
/// d'analyse, nom, année de naissance, numéro de facture, lit, article, fournisseur) et période relative lue contre une date de référence fournie. La sortie est une
/// INTENTION du catalogue et des paramètres typés : cet outil ne produit AUCUNE valeur de réponse (ni montant, ni quantité, ni nom de patient qu'il n'ait lu dans la question).
///
/// Étanche par construction : aucune importation hors `dart:core`, aucune socket, aucun fichier (le catalogue arrive déjà décodé). Le test d'étanchéité
/// (`test/assistant_mesure_test.dart`) échoue si une dépendance réseau y est ajoutée.
library;

/// La sortie hors catalogue (PRD section 8) : toute intention inconnue du catalogue est ramenée à ce code.
const String intentionInconnue = 'INTENTION_INCONNUE';

/// Un résultat de reconnaissance : une intention et des paramètres typés, jamais une valeur de réponse.
class Reconnaissance {
  const Reconnaissance({
    required this.statut,
    this.intention,
    this.code,
    this.parametres = const {},
    this.propositions = const [],
    this.manquants = const [],
    this.alertes = const [],
    this.ecran,
  });

  /// `comprise`, `precision_requise`, `ambigue`, `non_comprise` ou `refus`.
  final String statut;
  final String? intention;
  final String? code;
  final Map<String, Object?> parametres;
  final List<String> propositions;
  final List<String> manquants;
  final List<String> alertes;
  final String? ecran;

  Map<String, Object?> toJson() => {
        'statut': statut,
        if (intention != null) 'intention': intention,
        if (code != null) 'code': code,
        if (parametres.isNotEmpty) 'parametres': parametres,
        if (propositions.isNotEmpty) 'propositions': propositions,
        if (manquants.isNotEmpty) 'manquants': manquants,
        if (alertes.isNotEmpty) 'alertes': alertes,
        if (ecran != null) 'ecran': ecran,
      };
}

/// Le catalogue d'intentions, tel que décodé de `assistant_catalogue.json`.
class CatalogueAssistant {
  CatalogueAssistant(Map<String, Object?> json)
      : intentions = {
          for (final i in (json['intentions'] as List).cast<Map>()) '${i['id']}': i.cast<String, Object?>(),
        },
        domaines = {
          for (final e in ((json['domaines'] as Map?) ?? const {}).entries) '${e.key}': [for (final x in (e.value as List)) '$x'],
        },
        incoherences = [for (final x in ((json['incoherences'] as List?) ?? const [])) (x as Map).cast<String, Object?>()],
        ecransEcriture = [for (final x in ((json['ecransEcriture'] as List?) ?? const [])) (x as Map).cast<String, Object?>()],
        aujourdhui = '${json['aujourdhui']}';

  final Map<String, Map<String, Object?>> intentions;
  final Map<String, List<String>> domaines;
  final List<Map<String, Object?>> incoherences;
  final List<Map<String, Object?>> ecransEcriture;
  final String aujourdhui;

  bool connait(String id) => intentions.containsKey(id);

  List<String> requis(String id) => [for (final x in ((intentions[id]?['requis'] as List?) ?? const [])) '$x'];
  bool futurOk(String id) => intentions[id]?['futurOk'] == true;
  bool lectureHistorique(String id) => intentions[id]?['historique'] == true;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------------
// Normalisation
// ---------------------------------------------------------------------------------------------------------------------------------------------------------

const Map<String, String> _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i', 'í': 'i', 'ì': 'i',
  'ô': 'o', 'ö': 'o', 'ò': 'o', 'ó': 'o', 'õ': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u', 'ç': 'c', 'ñ': 'n', 'ÿ': 'y', 'œ': 'oe', 'æ': 'ae',
};

/// Sans casse ni accents ; tout ce qui n'est pas lettre ou chiffre devient une espace (apostrophe, tiret et ponctuation compris), espaces réduites.
String normaliser(String texte) {
  final b = StringBuffer();
  for (final r in texte.runes) {
    final c = String.fromCharCode(r).toLowerCase();
    b.write(_accents[c] ?? c);
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

/// Distance d'édition (transposition d'une paire adjacente comptée pour un), BORNÉE : rend [borne] + 1 dès que la distance dépasse la borne.
int distanceBornee(String a, String b, int borne) {
  if ((a.length - b.length).abs() > borne) return borne + 1;
  var avant2 = List<int>.filled(b.length + 1, 0);
  var avant = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cour = List<int>.filled(b.length + 1, 0)..[0] = i;
    var mini = cour[0];
    for (var j = 1; j <= b.length; j++) {
      final cout = a[i - 1] == b[j - 1] ? 0 : 1;
      var v = _min3(avant[j] + 1, cour[j - 1] + 1, avant[j - 1] + cout);
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        final t = avant2[j - 2] + 1;
        if (t < v) v = t;
      }
      cour[j] = v;
      if (v < mini) mini = v;
    }
    if (mini > borne) return borne + 1;
    avant2 = avant;
    avant = cour;
  }
  return avant[b.length] > borne ? borne + 1 : avant[b.length];
}

int _min3(int a, int b, int c) => a < b ? (a < c ? a : c) : (b < c ? b : c);

/// La tolérance (en fautes) selon la longueur du mot attendu : aucune sous cinq lettres (« lit », « lot », « prix » ne se confondent pas), une jusqu'à sept, deux au delà.
int toleranceMot(int longueur) => longueur < 5 ? 0 : (longueur < 8 ? 1 : 2);

/// Abréviations d'agent, généralistes (pas tirées d'une question) : remplacées avant la reconnaissance.
const Map<String, String> abreviations = {
  'stk': 'stock', 'cb': 'combien', 'qte': 'quantite', 'fact': 'facture', 'pharma': 'pharmacie', 'ordo': 'ordonnance', 'compta': 'comptabilite', 'nb': 'nombre',
};

// ---------------------------------------------------------------------------------------------------------------------------------------------------------
// Vocabulaire des intentions (poids : 1 indice, 2 net, 3 fort, 4 et plus décisif). Un indice en `*` est un préfixe.
// ---------------------------------------------------------------------------------------------------------------------------------------------------------

const Map<String, List<(String, int)>> _indices = {
  'I01': [('retrouve', 2), ('cherche', 2), ('trouve', 2), ('patient', 1), ('dossier', 1), ('identite', 2), ('derniere visite', 4), ('visite', 2), ('naissance', 1)],
  'I02': [('assurance', 4), ('assure', 2), ('assureur', 2), ('mutuelle', 3), ('carte', 1), ('valide', 1), ('valable', 1), ('validite', 2), ('jusqu a quand', 2), ('compagnie', 2), ('couverture', 2), ('prise en charge', 3)],
  'I03': [('doit encore', 4), ('reste a payer', 5), ('solde', 4), ('reliquat', 3), ('derniere facture', 5), ('dernier paiement', 3)],
  'I04': [('hospitalis*', 4), ('lits libres', 5), ('lit libre', 5), ('dans le lit', 4), ('lit', 3), ('lits', 3), ('occupe', 2), ('admission', 2), ('admissions', 2), ('chambre', 1)],
  'I05': [('prix', 4), ('tarif', 4), ('combien coute', 4), ('coute', 3), ('non assure', 3)],
  'I06': [('prix', 3), ('ancien', 4), ('historique', 4), ('chang*', 3), ('evolution', 2), ('versions', 1)],
  'I07': [('stock', 3), ('combien reste', 4), ('il reste', 2), ('quantite', 2), ('par lot', 2), ('lot', 1), ('lots', 1), ('fefo', 3), ('sortir en premier', 4), ('disponible', 1), ('combien de', 2)],
  'I08': [('rupture*', 5), ('sous le seuil', 5), ('seuil', 2), ('perim*', 4), ('perempt*', 4), ('reapprovisionnement', 2), ('a commander', 2), ('alerte', 1)],
  'I09': [('plus sortis', 5), ('plus sorti', 5), ('plus vendus', 5), ('top des sorties', 5), ('tourne*', 4), ('pas bouge', 5), ('bouge', 3), ('sans sortie', 4), ('rotation', 3), ('classement', 1)],
  'I10': [('valeur du stock', 6), ('valeur', 3), ('valorisation', 5), ('cump', 3), ('combien vaut', 5), ('vaut', 3)],
  'I11': [('inventaire', 5), ('ecarts', 2), ('non comptes', 4), ('comptage', 3)],
  'I12': [('fournisseur*', 5), ('livraisons', 2), ('livraison', 2), ('coordonnees', 2), ('contact', 1), ('doit on', 2), ('devons', 2)],
  'I13': [('commande*', 4), ('attente', 2), ('validation', 2), ('valider', 2), ('valide', 1)],
  'I14': [('recette*', 5), ('chiffre d affaires', 5), ('encaisse', 2), ('ventes', 1), ('par secteur', 1), ('mode de paiement', 1)],
  'I15': [('factures', 3), ('facture', 2), ('avoir*', 4), ('mecef', 5), ('non certifie*', 3)],
  'I16': [('impaye*', 5), ('creance*', 5), ('anciennete', 3), ('nous doit', 5), ('debiteur*', 4)],
  'I17': [('courrier*', 5), ('ordonnance*', 5), ('certificat*', 4), ('document*', 2), ('retrouve', 1)],
  'I18': [('certificat*', 0), ('attestation*', 0)],
  'I19': [('analyse*', 4), ('demande d analyse', 4), ('resultat*', 4), ('echo', 3), ('imagerie', 2), ('radio', 2), ('hemogramme', 1), ('nfs', 1), ('valide', 1), ('etat de la demande', 3)],
  'I20': [('garde', 5), ('permanence', 5), ('planning', 4), ('de garde', 1)],
  'I21': [('tableau de bord', 6), ('indicateurs', 3)],
  'I22': [('synchro*', 5), ('mere', 3), ('fileul*', 4), ('retard', 3), ('a jour', 3), ('alerte*', 4), ('poste', 1)],
  'I23': [('imprime*', 7), ('rapport*', 7), ('etat de', 2), ('etat des', 2), ('etat du', 2), ('rouleau', 3), ('80 mm', 2), ('genere*', 2)],
  'I24': [('comment', 5), ('ou je saisis', 5), ('ou saisir', 5), ('procedure', 4), ('ou puis je', 3)],
  'I25': [('c est quoi', 6), ('que veut dire', 6), ('qu est ce que', 6), ('qu est ce qu', 6), ('definition', 5), ('signifie', 5), ('veut dire', 5)],
};

const List<String> _motsVides = [
  'le', 'la', 'les', 'l', 'un', 'une', 'des', 'du', 'de', 'd', 'en', 'et', 'ou', 'a', 'au', 'aux', 'ce', 'cet', 'cette', 'ces', 'est', 'sont', 'qui', 'que', 'quoi',
  'quel', 'quelle', 'quels', 'quelles', 'pour', 'par', 'sur', 'dans', 'avec', 'mon', 'ma', 'mes', 'il', 'elle', 'ils', 'elles', 't', 'y', 'on', 'nous', 'vous', 'je', 'tu',
  'me', 'moi', 'toi', 'se', 's', 'qu', 'c', 'n', 'ne', 'pas', 'ont', 'a', 'es', 'si', 'ok', 'merci', 'svp', 'plus', 'moins', 'tout', 'tous', 'toute', 'toutes', 'montre', 'donne',
  'voir', 'fait', 'faire', 'dis', 'dire', 'liste', 'quand', 'ou', 'combien', 'ce', 'soir', 'depuis', 'jusqu', 'quand',
];

const List<String> _motsPeriode = [
  'aujourd', 'hui', 'hier', 'demain', 'cette', 'semaine', 'mois', 'dernier', 'derniere', 'derniers', 'passe', 'passee', 'annee', 'jour', 'jours', 'prochain', 'prochains',
  'precedent', 'janvier', 'fevrier', 'mars', 'avril', 'mai', 'juin', 'juillet', 'aout', 'septembre', 'octobre', 'novembre', 'decembre', 'lundi', 'mardi', 'mercredi',
  'jeudi', 'vendredi', 'samedi', 'dimanche', 'compares', 'compare', 'comparees', 'comparee', 'comparaison',
];

const List<String> _verbesEcriture = [
  'annule', 'supprime', 'efface', 'modifie', 'change', 'fais', 'fait', 'encaisse', 'enregistre', 'cree', 'ajoute', 'emets', 'emet', 'signe', 'rembourse', 'corrige',
  'valide', 'transmets', 'lance', 'declare', 'retire', 'regle', 'paye', 'creer', 'saisis', 'mets', 'met',
];

const List<String> _preambulesPoliteSse = ['peux tu', 'peut tu', 'pouvez vous', 'je veux', 'je voudrais', 'veuillez', 'merci de', 's il te plait', 's il vous plait'];

const List<String> _termesDiagnostic = [
  'traitement*', 'dose', 'doses', 'posologie*', 'diagnostic*', 'soigne*', 'guerir', 'symptome*', 'maladie*', 'prescri*', 'therapeut*', 'diabete', 'paludisme', 'palu',
  'hypertension', 'vih', 'sida', 'cancer', 'typhoide', 'tuberculose', 'anemie', 'drepanocytose', 'hepatite', 'asthme', 'epilepsie', 'ulcere', 'infection*',
];

const Map<String, String> _mois = {
  'janvier': '01', 'fevrier': '02', 'mars': '03', 'avril': '04', 'mai': '05', 'juin': '06', 'juillet': '07', 'aout': '08', 'septembre': '09', 'octobre': '10',
  'novembre': '11', 'decembre': '12',
};

const List<String> _joursSemaine = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];

// ---------------------------------------------------------------------------------------------------------------------------------------------------------
// Le moteur
// ---------------------------------------------------------------------------------------------------------------------------------------------------------

/// Le réglage d'un passage : l'écriture ou le diagnostic peuvent être coupés pour la MESURE d'une mutation, jamais au poste.
class ReglageReconnaissance {
  const ReglageReconnaissance({this.accents = true, this.tolerance = true, this.garderCatalogue = true, this.refuserEcriture = true, this.refuserDiagnostic = true});
  final bool accents, tolerance, garderCatalogue, refuserEcriture, refuserDiagnostic;
}

class ReconnaisseurAssistant {
  ReconnaisseurAssistant(this.catalogue, {this.reglage = const ReglageReconnaissance()});

  final CatalogueAssistant catalogue;
  final ReglageReconnaissance reglage;

  String _norm(String t) => reglage.accents ? normaliser(t) : _sansAccentsRetires(t);

  /// Sans le traitement des accents (mutation) : la ponctuation tombe, les lettres accentuées restent des lettres.
  String _sansAccentsRetires(String t) => t.toLowerCase().replaceAll(RegExp(r'[^a-z0-9àâäáãåéèêëîïíìôöòóõùûüúçñÿœæ]+'), ' ').trim();

  bool _egal(String mot, String cible) {
    if (mot == cible) return true;
    if (!reglage.tolerance) return false;
    final t = toleranceMot(cible.length);
    if (t == 0 || mot.length < 4) return false;
    return distanceBornee(mot, cible, t) <= t;
  }

  /// Un indice (une ou plusieurs formes consécutives, `*` pour un préfixe) trouvé dans les mots ; rend l'indice du premier mot couvert, ou -1.
  int _trouve(List<String> mots, String indice) {
    final formes = indice.split(' ');
    for (var i = 0; i + formes.length <= mots.length; i++) {
      var ok = true;
      for (var k = 0; k < formes.length; k++) {
        final f = formes[k];
        final m = mots[i + k];
        final bon = f.endsWith('*') ? _prefixe(m, f.substring(0, f.length - 1)) : _egal(m, f);
        if (!bon) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }

  /// Un préfixe (indice en `*`) : le mot commence par lui, ou, hors des préfixes courts, le début du mot s'en écarte d'une faute simple.
  bool _prefixe(String mot, String prefixe) {
    if (mot.startsWith(prefixe)) return true;
    if (!reglage.tolerance) return false;
    final t = toleranceMot(prefixe.length);
    if (t == 0 || mot.length < 4) return false;
    final debut = mot.length >= prefixe.length ? mot.substring(0, prefixe.length) : mot;
    return distanceBornee(debut, prefixe, t) <= t;
  }

  bool _a(List<String> mots, String indice) => _trouve(mots, indice) >= 0;

  /// La reconnaissance d'une question. [aujourdhui] : `AAAA-MM-JJ` (l'outil ne lit jamais l'horloge).
  Reconnaissance reconnaitre(String question, {String? aujourdhui}) {
    final jour = _jour(aujourdhui ?? catalogue.aujourdhui);
    final brut = question.trim();
    var mots = [for (final m in _norm(brut).split(' ')) if (m.isNotEmpty) abreviations[m] ?? m];
    final texte = ' ${mots.join(' ')} ';

    // 1. Les refus, avant toute intention (une commande interdite est ABSENTE, jamais exécutée).
    final params = <String, Object?>{};
    final utilises = <int>{};
    _entites(brut, mots, params);
    final nomSeul = params.remove('_nomSeul') == true;
    final refus = _refus(brut, mots, params);
    if (refus != null) return refus;

    // 2. Période.
    final periode = _periode(texte, mots, jour, params);

    // 3. Incohérence déclarée au catalogue (par exemple une rupture de patients).
    for (final inc in catalogue.incoherences) {
      final mm = [for (final x in (inc['mots'] as List)) '$x'];
      if (mm.every((x) => _a(mots, x) || _a(mots, '$x*'))) {
        return Reconnaissance(statut: 'non_comprise', code: intentionInconnue, propositions: _bornes([for (final x in (inc['propose'] as List)) '$x']));
      }
    }

    // 4. Scores par intention.
    final scores = <String, int>{};
    final couverts = <String, Set<int>>{};
    var motsScore = mots;
    // « assuré et non assuré » est du vocabulaire de prix, pas une question d'assurance.
    final iNA = _trouve(mots, 'non assure');
    if (iNA >= 0) {
      motsScore = [...mots]..replaceRange(iNA, iNA + 2, ['', '']);
    }
    for (final e in _indices.entries) {
      var s = 0;
      // Les indices d'une intention ne se cumulent pas sur les MÊMES mots (« facture » et « factures », « lit » et « lits ») : le plus lourd d'abord, un mot déjà couvert ne compte plus.
      final ordonnes = [...e.value]..sort((x, y) => y.$2 != x.$2 ? y.$2.compareTo(x.$2) : y.$1.length.compareTo(x.$1.length));
      final pris = <int>{};
      for (final (indice, poids) in ordonnes) {
        final i = _trouve(motsScore, indice);
        if (i < 0 || poids <= 0) continue;
        final n = indice.split(' ').length;
        final positions = [for (var k = 0; k < n; k++) i + k];
        if (positions.any(pris.contains)) continue;
        s += poids;
        pris.addAll(positions);
        (couverts[e.key] ??= {}).addAll(positions);
      }
      if (s > 0) scores[e.key] = s;
    }
    if (iNA >= 0) scores['I05'] = (scores['I05'] ?? 0) + 3;
    // Entités de patient : un indice léger pour la recherche d'un patient.
    if (params.containsKey('codePatient') || params.containsKey('nomPatient')) scores['I01'] = (scores['I01'] ?? 0) + 1;
    if (nomSeul) scores['I01'] = (scores['I01'] ?? 0) + 3;
    if (params.containsKey('anneeNaissance')) scores['I01'] = (scores['I01'] ?? 0) + 1;
    if (params.containsKey('codeAnalyse')) scores['I19'] = (scores['I19'] ?? 0) + 3;
    // Conjonctions décisives.
    final certif = _a(mots, 'certificat*') || _a(mots, 'attestation*');
    final prix = _a(mots, 'prix') || _a(mots, 'tarif') || _a(mots, 'coute') || _a(mots, 'combien');
    if (certif && prix) scores['I18'] = (scores['I18'] ?? 0) + 8;
    final stats = _a(mots, 'consultation*') || _a(mots, 'admission*') || _a(mots, 'analyse*') || _a(mots, 'examen*');
    if ((_a(mots, 'combien de') || _a(mots, 'nombre de') || _a(mots, 'nombre d')) && stats) scores['I21'] = (scores['I21'] ?? 0) + 5;

    // 5. Un énoncé réduit à un mot de domaine est ambigu : trois intentions proches.
    final informatifs = [for (final m in mots) if (m.isNotEmpty && !_motsVides.contains(m)) m];
    if (informatifs.isNotEmpty && informatifs.length <= 2) {
      for (final d in catalogue.domaines.entries) {
        if (informatifs.every((m) => m == d.key || _egal(m, d.key)) && (scores.values.isEmpty || scores.values.reduce((a, b) => a > b ? a : b) < 3)) {
          return Reconnaissance(statut: 'ambigue', code: 'QUESTION_AMBIGUE', propositions: _bornes(d.value), parametres: {'secteur': d.key});
        }
      }
    }

    if (scores.isEmpty) return const Reconnaissance(statut: 'non_comprise', code: intentionInconnue);
    final tries = scores.entries.toList()..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
    final premier = tries.first;
    final second = tries.length > 1 ? tries[1] : null;
    if (premier.value < 2) {
      return Reconnaissance(statut: 'non_comprise', code: intentionInconnue, propositions: _bornes([for (final t in tries) t.key]));
    }
    if (second != null && second.value == premier.value) {
      return Reconnaissance(statut: 'ambigue', code: 'QUESTION_AMBIGUE', propositions: _bornes([for (final t in tries.where((t) => t.value >= premier.value - 1)) t.key]));
    }
    var id = premier.key;
    if (reglage.garderCatalogue && !catalogue.connait(id)) {
      return const Reconnaissance(statut: 'non_comprise', code: intentionInconnue);
    }
    if (id == 'I18' || (certif && prix)) id = 'I18';

    // 6. Paramètres propres à l'intention.
    _parametresPropres(id, mots, couverts[id] ?? const {}, params, utilises);
    final alertes = <String>[];
    if (periode != null) {
      final debut = periode['debut'] as String?;
      if (debut != null && debut.compareTo(iso(jour)) > 0 && !catalogue.futurOk(id)) alertes.add('PERIODE_FUTURE');
      if (debut != null && debut.compareTo(iso(jour)) < 0 && !catalogue.lectureHistorique(id) && periode['type'] == 'date') alertes.add('NON_CALCULABLE_HISTORIQUE');
    }
    final manquants = [
      for (final r in catalogue.requis(id))
        if (!_possede(r, params)) r
    ];
    if (manquants.isNotEmpty) {
      return Reconnaissance(statut: 'precision_requise', intention: id, code: 'PRECISION_REQUISE', manquants: manquants, parametres: params, alertes: alertes);
    }
    return Reconnaissance(statut: 'comprise', intention: id, parametres: params, alertes: alertes);
  }

  bool _possede(String requis, Map<String, Object?> p) => switch (requis) {
        'patient' => p.containsKey('codePatient') || p.containsKey('nomPatient') || p.containsKey('patient'),
        'acte' => p['acte'] != null && '${p['acte']}'.isNotEmpty,
        'article' => p['article'] != null && '${p['article']}'.isNotEmpty,
        'fournisseur' => p['fournisseur'] != null && '${p['fournisseur']}'.isNotEmpty,
        _ => p.containsKey(requis),
      };

  List<String> _bornes(List<String> l) => [for (final x in l.take(3)) x];

  // --- refus ----------------------------------------------------------------------------------------------------------------------------------------

  Reconnaissance? _refus(String brut, List<String> mots, Map<String, Object?> entites) {
    final texte = mots.join(' ');
    // Injonction : contourner les règles, ou extraire tous les patients.
    if (((_a(mots, 'ignore') || _a(mots, 'oublie') || _a(mots, 'desactive')) && (_a(mots, 'regles') || _a(mots, 'consignes') || _a(mots, 'instructions'))) ||
        texte.contains('tous les patients')) {
      return const Reconnaissance(statut: 'refus', code: 'INJONCTION_REFUSEE');
    }
    // Envoi hors de la clinique.
    if ((_a(mots, 'envoie') || _a(mots, 'envoyer') || _a(mots, 'transmets') || _a(mots, 'partage')) &&
        (_a(mots, 'mail') || _a(mots, 'email') || _a(mots, 'adresse') || _a(mots, 'whatsapp') || _a(mots, 'sms') || _a(mots, 'cloud'))) {
      return const Reconnaissance(statut: 'refus', code: 'ENVOI_EXTERNE_REFUSE');
    }
    // Diagnostic et avis thérapeutique (hors périmètre).
    if (reglage.refuserDiagnostic && _termesDiagnostic.any((t) => _a(mots, t))) {
      return const Reconnaissance(statut: 'refus', code: 'AVIS_MEDICAL_REFUSE');
    }
    // Écriture : une commande à l'impératif en tête d'énoncé.
    if (reglage.refuserEcriture) {
      var debut = mots;
      for (final p in _preambulesPoliteSse) {
        final pm = p.split(' ');
        if (mots.length > pm.length && List.generate(pm.length, (i) => mots[i]).join(' ') == p) {
          debut = mots.sublist(pm.length);
          break;
        }
      }
      if (debut.isNotEmpty && _verbesEcriture.any((v) => _egal(debut.first, v) && (v.length >= 5 || debut.first == v))) {
        String? ecran;
        for (final e in catalogue.ecransEcriture) {
          if ([for (final x in (e['mots'] as List)) '$x'].any((m) => mots.contains(m))) {
            ecran = '${e['ecran']}';
            break;
          }
        }
        return Reconnaissance(statut: 'refus', code: 'ECRITURE_ABSENTE', ecran: ecran, parametres: {...entites});
      }
    }
    return null;
  }

  // --- entités --------------------------------------------------------------------------------------------------------------------------------------

  static final RegExp _codePatient = RegExp(r'\bCNT\s*/?\s*(\d{1,6})\s*/\s*(\d{2})\b', caseSensitive: false);
  static final RegExp _codeAnalyse = RegExp(r'\b(\d{5})-(\d{4})\b');
  static final RegExp _facture = RegExp(r'\bfacture\s+n?°?\s*(\d{3,})\b', caseSensitive: false);
  static final RegExp _lit = RegExp(r'\blit\s+n?°?\s*(\d{1,3})\b', caseSensitive: false);
  static final RegExp _naissance = RegExp(r'\bn[ée]e?\s+en\s+(\d{4})\b', caseSensitive: false, unicode: true);
  static final RegExp _civilite = RegExp(r"\b(?:Mme|Mlle|Mr|Madame|Monsieur|Mademoiselle|M\.|M)\s+([A-ZÀ-Ý][A-Za-zÀ-ÿ'’-]+)", unicode: true);

  void _entites(String brut, List<String> mots, Map<String, Object?> p) {
    final c = _codePatient.firstMatch(brut);
    if (c != null) {
      final avecBarre = RegExp(r'CNT\s*/', caseSensitive: false).hasMatch(c.group(0)!);
      p['codePatient'] = avecBarre ? 'CNT/${c.group(1)}/${c.group(2)}' : 'CNT${c.group(1)}/${c.group(2)}';
    }
    final a = _codeAnalyse.firstMatch(brut);
    if (a != null) p['codeAnalyse'] = '${a.group(1)}-${a.group(2)}';
    final f = _facture.firstMatch(brut);
    if (f != null) p['numeroFacture'] = f.group(1);
    final l = _lit.firstMatch(brut);
    if (l != null) p['lit'] = int.parse(l.group(1)!);
    final n = _naissance.firstMatch(brut);
    if (n != null) p['anneeNaissance'] = int.parse(n.group(1)!);
    final cv = _civilite.firstMatch(brut);
    if (cv != null) {
      p['nomPatient'] = cv.group(1);
      // « M. Sossou » seul : une civilité et un nom, rien d'autre, c'est une recherche de patient.
      if (brut.replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ').trim().split(RegExp(r'\s+')).length <= 2) p['_nomSeul'] = true;
    } else if (c == null) {
      // Un seul mot, avec majuscule, qui n'est ni du vocabulaire connu ni un mot vide : un nom (« Adjovi » seul).
      final seul = brut.replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ').trim().split(RegExp(r'\s+'));
      if (seul.length == 1 && RegExp(r'^[A-ZÀ-Ý][a-zà-ÿ]+$', unicode: true).hasMatch(seul.first) && !_connu(seul.first)) {
        p['nomPatient'] = seul.first;
        p['_nomSeul'] = true;
      }
    }
    if (_a(mots, 'ce patient') || _a(mots, 'le patient') || _a(mots, 'cette patiente') || _a(mots, 'ce dossier')) {
      if (!p.containsKey('codePatient') && !p.containsKey('nomPatient')) p['patient'] = 'contexte';
    }
  }

  bool _connu(String mot) {
    final m = _norm(mot);
    if (_motsVides.contains(m) || _motsPeriode.contains(m)) return true;
    if (catalogue.domaines.keys.any((d) => _egal(m, d))) return true;
    for (final e in _indices.entries) {
      for (final (indice, _) in e.value) {
        if (indice.split(' ').any((f) => f.endsWith('*') ? m.startsWith(f.substring(0, f.length - 1)) : _egal(m, f))) return true;
      }
    }
    return false;
  }

  void _parametresPropres(String id, List<String> mots, Set<int> couverts, Map<String, Object?> p, Set<int> utilises) {
    // Secteur nommé.
    for (final d in catalogue.domaines.keys) {
      if (d != 'patient' && d != 'fournisseur' && mots.any((m) => m == d || _egal(m, d))) {
        p['secteur'] = d;
        break;
      }
    }
    if (mots.contains('labo')) p['secteur'] = 'laboratoire';
    final texte = mots.join(' ');
    final top = RegExp(r'\b(\d{1,3}) (?:articles|produits|medicaments)\b').firstMatch(texte);
    if (id == 'I09' && top != null) p['topN'] = int.parse(top.group(1)!);
    if (id == 'I23') {
      if (texte.contains('rouleau') || texte.contains('80 mm')) {
        p['gabarit'] = 'rouleau80';
      } else if (texte.contains('a4')) {
        p['gabarit'] = 'a4';
      }
    }
    // Fournisseur : ce qui suit « fournisseur de/d' ».
    final iF = mots.indexWhere((m) => m.startsWith('fournisseur'));
    if (iF >= 0 && iF + 1 < mots.length) {
      final reste = [
        for (var k = iF + 1; k < mots.length; k++)
          if (!_motsVides.contains(mots[k]) && !_motsPeriode.contains(mots[k]) && !RegExp(r'^\d+$').hasMatch(mots[k])) mots[k]
      ];
      if (reste.isNotEmpty) p['fournisseur'] = reste.join(' ');
    }
    // Article ou acte : les mots qui restent une fois retirés mots vides, indices de l'intention, entités et période.
    if (const ['I05', 'I06', 'I07'].contains(id)) {
      final indicesIntention = {for (final (i, _) in (_indices[id] ?? const <(String, int)>[])) ...i.split(' ').map((x) => x.replaceAll('*', ''))};
      final entitesTexte = {
        for (final v in [p['codePatient'], p['nomPatient'], p['codeAnalyse']])
          if (v != null) ..._norm('$v').split(' '),
      };
      final per = p['periode'] as Map<String, Object?>?;
      final chiffresPeriode = per == null
          ? const <String>{}
          : {if (per['n'] != null) '${per['n']}', if (per['type'] == 'date') ...mots.where((m) => RegExp(r'^\d{1,2}$').hasMatch(m))};
      final reste = <String>[];
      for (var k = 0; k < mots.length; k++) {
        final m = mots[k];
        if (m.isEmpty || _motsVides.contains(m) || _motsPeriode.contains(m) || entitesTexte.contains(m) || couverts.contains(k)) continue;
        if (chiffresPeriode.contains(m)) continue;
        if (indicesIntention.any((x) => x == m || (x.length >= 5 && _egal(m, x)))) continue;
        if (const ['assure', 'non', 'avant'].contains(m)) continue;
        reste.add(m);
      }
      final nom = reste.join(' ').trim();
      if (nom.isNotEmpty) p[id == 'I07' ? 'article' : 'acte'] = nom;
    }
  }

  // --- période --------------------------------------------------------------------------------------------------------------------------------------

  Map<String, Object?>? _periode(String texte, List<String> mots, DateTime jour, Map<String, Object?> p) {
    Map<String, Object?> j(String type, DateTime d, DateTime f, {int? n}) => {'type': type, 'debut': iso(d), 'fin': iso(f), if (n != null) 'n': n};
    Map<String, Object?>? principale;
    Map<String, Object?>? comparee;
    final lundi = jour.subtract(Duration(days: jour.weekday - 1));
    final mois0 = DateTime.utc(jour.year, jour.month, 1);
    final moisFin = DateTime.utc(jour.year, jour.month + 1, 0);
    final moisPrec0 = DateTime.utc(jour.year, jour.month - 1, 1);
    final moisPrecFin = DateTime.utc(jour.year, jour.month, 0);
    bool a(String s) => texte.contains(' $s ');

    final plusDe = RegExp(r' plus de (\d{1,4}) jours? ').firstMatch(texte);
    final njours = RegExp(r' (\d{1,4}) (?:derniers )?jours? ').firstMatch(texte);
    final nmois = RegExp(r' (\d{1,3}) mois ').firstMatch(texte);
    final dateExplicite = RegExp(r' (\d{1,2}) (janvier|fevrier|mars|avril|mai|juin|juillet|aout|septembre|octobre|novembre|decembre)( dernier)? ').firstMatch(texte);
    final moisNomme = RegExp(r' (janvier|fevrier|mars|avril|mai|juin|juillet|aout|septembre|octobre|novembre|decembre) ').firstMatch(texte);

    if (plusDe != null) {
      principale = {'type': 'anciennete_jours', 'n': int.parse(plusDe.group(1)!)};
    } else if (dateExplicite != null) {
      final jj = int.parse(dateExplicite.group(1)!);
      final mm = int.parse(_mois[dateExplicite.group(2)]!);
      var an = jour.year;
      final dernier = dateExplicite.group(3) != null;
      var d = DateTime.utc(an, mm, jj);
      if (dernier && !d.isBefore(jour)) d = DateTime.utc(an - 1, mm, jj);
      principale = j('date', d, d);
    } else if (a('aujourd hui') || a('ce soir') || a('ce matin') || a('du jour')) {
      principale = j('aujourdhui', jour, jour);
    } else if (a('hier')) {
      final d = jour.subtract(const Duration(days: 1));
      principale = j('hier', d, d);
    } else if (a('demain')) {
      final d = jour.add(const Duration(days: 1));
      principale = j('demain', d, d);
    } else if (texte.contains('compar') && (a('mois dernier') || a('mois passe')) && (a('du mois') || a('ce mois') || a('de ce mois'))) {
      principale = j('mois', mois0, moisFin);
    } else if (a('semaine derniere') || a('semaine passee')) {
      final d = lundi.subtract(const Duration(days: 7));
      principale = j('semaine_derniere', d, d.add(const Duration(days: 6)));
    } else if (a('semaine') && (a('cette') || a('de la') || a('la'))) {
      principale = j('semaine', lundi, lundi.add(const Duration(days: 6)));
    } else if (nmois != null && (a('dans les ${nmois.group(1)} mois') || a('dans ${nmois.group(1)} mois') || a('prochains ${nmois.group(1)} mois'))) {
      final n = int.parse(nmois.group(1)!);
      principale = j('horizon_mois', jour, _plusMois(jour, n), n: n);
    } else if (nmois != null) {
      final n = int.parse(nmois.group(1)!);
      principale = j('n_mois', _plusMois(jour, -n), jour, n: n);
    } else if (njours != null) {
      final n = int.parse(njours.group(1)!);
      principale = j('n_jours', jour.subtract(Duration(days: n)), jour, n: n);
    } else if (a('annee derniere') || a('annee passee')) {
      principale = j('annee_derniere', DateTime.utc(jour.year - 1, 1, 1), DateTime.utc(jour.year - 1, 12, 31));
    } else if (a('mois dernier') || a('mois passe') || a('mois precedent')) {
      principale = j('mois_dernier', moisPrec0, moisPrecFin);
    } else if (moisNomme != null && (a('mois d ${moisNomme.group(1)}') || !a('mois'))) {
      final mm = int.parse(_mois[moisNomme.group(1)]!);
      final an = mm <= jour.month ? jour.year : jour.year - 1;
      principale = j('mois_nomme', DateTime.utc(an, mm, 1), DateTime.utc(an, mm + 1, 0));
    } else if (a('ce mois') || a('du mois') || a('de ce mois') || a('mois')) {
      principale = j('mois', mois0, moisFin);
    } else if (a('cette annee') || a('de l annee')) {
      principale = j('annee', DateTime.utc(jour.year, 1, 1), DateTime.utc(jour.year, 12, 31));
    } else {
      for (final js in _joursSemaine) {
        if (a(js)) {
          final cible = _joursSemaine.indexOf(js) + 1;
          var d = jour;
          while (d.weekday != cible) {
            d = d.add(const Duration(days: 1));
          }
          principale = j('jour_semaine', d, d);
          break;
        }
      }
    }
    // Comparaison : « comparées au mois dernier » lorsque le mois courant est la période principale.
    if (principale != null && principale['type'] == 'mois' && (a('mois dernier') || a('mois passe')) && (texte.contains('compar'))) {
      comparee = j('mois_dernier', moisPrec0, moisPrecFin);
    }
    if (principale != null) p['periode'] = principale;
    if (comparee != null) p['periodeComparee'] = comparee;
    return principale;
  }

  DateTime _plusMois(DateTime d, int n) {
    final m0 = d.month - 1 + n;
    final an = d.year + (m0 / 12).floor();
    final mm = (m0 % 12) + 1;
    final dernierJour = DateTime.utc(an, mm + 1, 0).day;
    return DateTime.utc(an, mm, d.day > dernierJour ? dernierJour : d.day);
  }

  DateTime _jour(String s) => DateTime.utc(int.parse(s.substring(0, 4)), int.parse(s.substring(5, 7)), int.parse(s.substring(8, 10)));
}

/// `AAAA-MM-JJ`.
String iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
