/// Mesure de la reconnaissance de l'assistant (lot AST-0) : jugement question par question, taux (global, réglage, contrôle, par intention), cas limites,
/// valeurs inventées, temps, contrôle d'étanchéité, matrice de droits tirée de `rbac.json`, droits manquants.
///
/// Étanche comme `assistant_comprehension.dart` : aucune importation hors `dart:core` et le moteur voisin.
library;

import 'assistant_comprehension.dart';

/// Le jeu de réglage est celui des numéros IMPAIRS, le jeu de contrôle celui des PAIRS : règle écrite d'avance, jamais ajustée.
String jeuDe(int n) => n.isOdd ? 'reglage' : 'controle';

class Jugement {
  const Jugement({required this.n, required this.ok, required this.raison, required this.paramsOk, required this.raisonParams});
  final int n;

  /// La BONNE INTENTION (ou la bonne réaction pour un cas limite) : statut, intention, code, alerte, écran, propositions.
  final bool ok;
  final String raison;

  /// Les paramètres typés attendus, quand le vecteur en déclare ; `null` quand il n'en déclare pas.
  final bool? paramsOk;
  final String raisonParams;
}

/// Compare la réaction à celle du vecteur.
Jugement juger(Map<String, Object?> q, Reconnaissance r) {
  final n = q['n'] as int;
  final att = (q['reaction'] as Map).cast<String, Object?>();
  final raisons = <String>[];
  if (r.statut != att['statut']) raisons.add('statut « ${r.statut}», attendu « ${att['statut']}»');
  if (att['intention'] != null && r.intention != att['intention']) raisons.add('intention ${r.intention ?? 'aucune'}, attendue ${att['intention']}');
  if (att['code'] != null && r.code != att['code']) raisons.add('code ${r.code ?? 'aucun'}, attendu ${att['code']}');
  if (att['alerte'] != null && !r.alertes.contains(att['alerte'])) raisons.add('alerte ${att['alerte']} absente');
  if (att['ecran'] != null && r.ecran != att['ecran']) raisons.add('écran ${r.ecran ?? 'aucun'}, attendu ${att['ecran']}');
  if (att['propositions'] != null && r.propositions.length != att['propositions']) raisons.add('${r.propositions.length} propositions, attendu ${att['propositions']}');
  if (att['propose'] != null && !(att['propose'] as List).every((x) => r.propositions.contains(x))) raisons.add('proposition ${att['propose']} absente (${r.propositions})');
  bool? pOk;
  var rp = '';
  final attendus = (q['parametres'] as Map?)?.cast<String, Object?>();
  if (attendus != null) {
    final manques = <String>[];
    attendus.forEach((k, v) {
      if (!_egalProfond(r.parametres[k], v, partiel: true)) manques.add('$k lu ${r.parametres[k]}, attendu $v');
    });
    pOk = manques.isEmpty;
    rp = manques.join(' ; ');
  }
  return Jugement(n: n, ok: raisons.isEmpty, raison: raisons.join(' ; '), paramsOk: pOk, raisonParams: rp);
}

bool _egalProfond(Object? lu, Object? attendu, {bool partiel = false}) {
  if (attendu is Map) {
    if (lu is! Map) return false;
    for (final e in attendu.entries) {
      if (!_egalProfond(lu[e.key], e.value, partiel: partiel)) return false;
    }
    return partiel || lu.length == attendu.length;
  }
  return lu == attendu;
}

/// Le nombre de VALEURS INVENTÉES d'une sortie : un paramètre texte qui n'est pas lu dans la question (après normalisation), une clé de réponse (valeur, montant, quantité,
/// reponse) ou une intention hors catalogue. Les bornes de période (calculées de la date de référence) et les drapeaux fermés ne sont pas des valeurs de réponse.
int valeursInventees(String question, Reconnaissance r, CatalogueAssistant cat) {
  var n = 0;
  final qn = ' ${normaliser(question)} ';
  final json = r.toJson();
  for (final cle in const ['valeur', 'montant', 'quantite', 'reponse', 'total', 'nom']) {
    if (json.containsKey(cle)) n++;
  }
  if (r.intention != null && !cat.connait(r.intention!)) n++;
  for (final e in r.parametres.entries) {
    if (e.key == 'periode' || e.key == 'periodeComparee' || e.key == 'secteur' || e.key == 'gabarit' || e.key == 'patient') continue;
    final v = e.value;
    if (v is String) {
      final vn = normaliser(v);
      if (vn.isEmpty) continue;
      // Un article ou un nom : chaque mot doit être dans la question ; un code se compare chiffre à chiffre.
      final ok = vn.split(' ').every((m) => qn.contains(m));
      if (!ok) n++;
    } else if (v is int) {
      if (!qn.contains(' $v ') && !qn.contains('$v')) n++;
    }
  }
  return n;
}

/// Le résultat d'une mesure complète.
class ResultatMesure {
  ResultatMesure(this.jugements, this.reconnaissances, this.questions, this.inventees);
  final List<Jugement> jugements;
  final List<Reconnaissance> reconnaissances;
  final List<Map<String, Object?>> questions;
  final int inventees;

  double taux(bool Function(Map<String, Object?> q) filtre) {
    var tot = 0, ok = 0;
    for (var i = 0; i < questions.length; i++) {
      if (!filtre(questions[i])) continue;
      tot++;
      if (jugements[i].ok) ok++;
    }
    return tot == 0 ? 0 : ok / tot;
  }

  int compte(bool Function(Map<String, Object?> q) filtre, {bool seulementOk = false}) {
    var c = 0;
    for (var i = 0; i < questions.length; i++) {
      if (filtre(questions[i]) && (!seulementOk || jugements[i].ok)) c++;
    }
    return c;
  }

  double get global => taux((_) => true);
  double get reglage => taux((q) => jeuDe(q['n'] as int) == 'reglage');
  double get controle => taux((q) => jeuDe(q['n'] as int) == 'controle');

  /// La réaction attendue vise une intention (comprise ou précision requise), donc compte dans le taux de l'intention.
  String? intentionVisee(Map<String, Object?> q) => (q['reaction'] as Map)['intention'] as String?;

  /// Par intention : (réussies, total) sur les questions qui visent cette intention.
  Map<String, (int, int)> parIntention(Iterable<String> ids) => {
        for (final id in ids) id: (compte((q) => intentionVisee(q) == id, seulementOk: true), compte((q) => intentionVisee(q) == id)),
      };

  List<(Map<String, Object?>, Jugement)> get echecs => [
        for (var i = 0; i < questions.length; i++)
          if (!jugements[i].ok) (questions[i], jugements[i])
      ];

  List<(Map<String, Object?>, Jugement)> get echecsParametres => [
        for (var i = 0; i < questions.length; i++)
          if (jugements[i].paramsOk == false) (questions[i], jugements[i])
      ];
}

ResultatMesure mesurer(List<Map<String, Object?>> questions, ReconnaisseurAssistant moteur, {String? aujourdhui}) {
  final jug = <Jugement>[];
  final recs = <Reconnaissance>[];
  var inv = 0;
  for (final q in questions) {
    final r = moteur.reconnaitre('${q['question']}', aujourdhui: aujourdhui);
    recs.add(r);
    jug.add(juger(q, r));
    inv += valeursInventees('${q['question']}', r, moteur.catalogue);
  }
  return ResultatMesure(jug, recs, questions, inv);
}

/// Les temps de reconnaissance : moyenne et pire cas (en microsecondes) sur [repetitions] passages de chaque question.
({double moyenneUs, int pireUs, String pireQuestion}) mesurerTemps(List<Map<String, Object?>> questions, ReconnaisseurAssistant moteur, {int repetitions = 50}) {
  final sw = Stopwatch();
  var total = 0;
  var passages = 0;
  var pire = 0;
  var pireQ = '';
  for (var k = 0; k < repetitions; k++) {
    for (final q in questions) {
      sw
        ..reset()
        ..start();
      moteur.reconnaitre('${q['question']}');
      sw.stop();
      final us = sw.elapsedMicroseconds;
      total += us;
      passages++;
      if (us > pire) {
        pire = us;
        pireQ = '${q['question']}';
      }
    }
  }
  return (moyenneUs: total / passages, pireUs: pire, pireQuestion: pireQ);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------------
// Droits
// ---------------------------------------------------------------------------------------------------------------------------------------------------------

/// Le droit d'un profil sur une intention, lu dans `rbac.json` : au moins UN des écrans de lecture de l'intention est visible d'au moins un rôle du profil. Une intention
/// sans écran de lecture (aide, glossaire) est ouverte à tout profil (le geste d'entrée du volet n'existe pas encore, voir [droitsManquants]).
bool profilALeDroit(Map<String, Object?> rbac, CatalogueAssistant cat, String intention, List<String> roles) {
  final ecrans = [for (final e in ((cat.intentions[intention]!['ecransLecture'] as List?) ?? const [])) '$e'];
  if (ecrans.isEmpty) return true;
  final parRole = (rbac['parRole'] as Map).cast<String, Object?>();
  for (final r in roles) {
    final fiche = (parRole[r] as Map?)?.cast<String, Object?>() ?? const {};
    for (final e in ecrans) {
      final d = fiche[e];
      if (d is List && d.isNotEmpty && d.first == 1) return true;
    }
  }
  return false;
}

/// La matrice intention × profil (les dix profils types) : `true` quand le profil a le droit de lecture.
List<Map<String, Object?>> matriceDroits(Map<String, Object?> rbac, Map<String, Object?> cat, CatalogueAssistant c) {
  final profils = (cat['profils'] as Map).cast<String, Object?>();
  return [
    for (final id in (c.intentions.keys.toList()..sort()))
      {
        'intention': id,
        'ecrans': c.intentions[id]!['ecransLecture'],
        'profils': {
          for (final p in profils.entries) p.key: profilALeDroit(rbac, c, id, [for (final r in (p.value as List)) '$r']),
        },
      }
  ];
}

/// Les écrans de lecture du catalogue qui n'existent dans aucune fiche de `rbac.json` : un droit que la matrice ne sait pas exprimer.
List<String> ecransInconnusDeRbac(Map<String, Object?> rbac, CatalogueAssistant c) {
  final parRole = (rbac['parRole'] as Map).cast<String, Object?>();
  final connus = {for (final f in parRole.values) ...(f as Map).keys.map((k) => '$k')};
  final inconnus = <String>{};
  for (final i in c.intentions.values) {
    for (final e in ((i['ecransLecture'] as List?) ?? const [])) {
      if (!connus.contains('$e')) inconnus.add('$e');
    }
  }
  return inconnus.toList()..sort();
}

/// Les droits MANQUANTS : ce que l'assistant exige et que `rbac.json` ne sait pas exprimer aujourd'hui. Aucun n'est ajouté dans ce lot (mesure seulement).
List<Map<String, Object?>> droitsManquants(Map<String, Object?> rbac, CatalogueAssistant c) {
  final jeux = [for (final j in (((rbac['gestes'] as Map?)?['jeux']) as List? ?? const [])) '${(j as Map)['id']}'];
  final m = <Map<String, Object?>>[];
  if (!jeux.contains('utiliser_assistant')) {
    m.add({
      'code': 'GESTE_UTILISER_ASSISTANT',
      'libelle': 'Le geste réservé « utiliser l\'assistant » (accordé d\'origine à tous les rôles qui ont un poste, réglable par rôle comme corriger_texte_ocr) n\'est pas déclaré dans `gestes.jeux` de rbac.json.',
      'intentions': 'toutes',
    });
  }
  for (final e in ecransInconnusDeRbac(rbac, c)) {
    m.add({'code': 'ECRAN_INCONNU', 'libelle': 'L\'écran « $e » n\'est dans aucune fiche de rbac.json.', 'intentions': 'voir le catalogue'});
  }
  m.addAll(const [
    {
      'code': 'AXE_SECTEUR',
      'libelle': 'Aucun axe de secteur dans rbac.json (aucune occurrence du mot) : le périmètre d\'un profil restreint à un secteur (stock et valorisation de la pharmacie ou du laboratoire) ne s\'exprime pas.',
      'intentions': 'I07, I08, I10',
    },
    {
      'code': 'AXE_FONCTION_ET_SECTEUR_RESULTAT',
      'libelle': 'Fonction et secteur du résultat de laboratoire vivent dans `SessionLabo` (res_habilitations.dart), pas dans rbac.json : l\'assistant doit porter la même session.',
      'intentions': 'I19',
    },
    {
      'code': 'ZONE_EN_DUR',
      'libelle': 'La liste des rôles de zone médicale (zone 2) est une constante du domaine (fichiers_donnees.dart, docRolesZone2), absente de rbac.json : deux sources. Aucun attribut de zone n\'existe au niveau du patient.',
      'intentions': 'I01, I04, I17, I19',
    },
    {
      'code': 'DROIT_DE_L_ETAT_OUVERT',
      'libelle': 'Générer un rapport exige le droit de la bibliothèque ET celui de l\'écran de l\'état visé : le second dépend de la question, aucun vecteur global ne l\'exprime.',
      'intentions': 'I23',
    },
    {
      'code': 'FICHE_PAR_ROLE_DESTINATAIRE',
      'libelle': 'Une fiche de connaissance réservée à un rôle destinataire n\'a pas d\'équivalent dans rbac.json (PRD section 7).',
      'intentions': 'I24, I25',
    },
  ]);
  return m;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------------
// Tableau de couverture (bloc engendré du document)
// ---------------------------------------------------------------------------------------------------------------------------------------------------------

const String balisesDebut = '<!-- DEBUT TABLEAU ENGENDRE : dart run tool/mesure_assistant.dart --tableau -->';
const String balisesFin = '<!-- FIN TABLEAU ENGENDRE -->';

String _statutLibelle(String s) => switch (s) {
      'calculable' => 'calculable aujourd\'hui',
      'petit_lot' => 'calculable après un petit lot',
      'non_disponible' => 'non disponible faute de donnée',
      _ => s,
    };

/// Le tableau de couverture, une ligne par intention, engendré du catalogue.
String tableauCouverture(Map<String, Object?> cat, Map<String, Object?> rbac, CatalogueAssistant c) {
  final b = StringBuffer()
    ..writeln(balisesDebut)
    ..writeln()
    ..writeln('| Int. | Intention | Source lue dans le code | Droit (écrans de lecture, un parmi) | Statut | Raison | Refus nommés |')
    ..writeln('|---|---|---|---|---|---|---|');
  for (final id in (c.intentions.keys.toList()..sort())) {
    final i = c.intentions[id]!;
    final ecrans = [for (final e in ((i['ecransLecture'] as List?) ?? const [])) '`$e`'];
    String liste(Object? l, String sep) => [for (final x in (l as List)) '$x'].join(sep);
    b.writeln('| $id | ${i['libelle']} | ${liste(i['sources'], ' ; ')} | ${ecrans.isEmpty ? 'aucun écran (universel, geste à créer)' : ecrans.join(', ')} | **${_statutLibelle('${i['statut']}')}** | ${i['raison']} | ${liste(i['refus'], ', ')} |');
  }
  b
    ..writeln()
    ..writeln(balisesFin);
  return b.toString();
}

/// Le décompte des statuts du catalogue.
Map<String, int> decompteStatuts(CatalogueAssistant c) {
  final d = <String, int>{'calculable': 0, 'petit_lot': 0, 'non_disponible': 0};
  for (final i in c.intentions.values) {
    d['${i['statut']}'] = (d['${i['statut']}'] ?? 0) + 1;
  }
  return d;
}

String pct(double x) => '${(x * 100).toStringAsFixed(1).replaceAll('.', ',')} %';

/// Les questions de l'annexe dont le PROFIL TYPE n'a pas, d'après `rbac.json`, le droit de lecture de l'intention visée : l'annexe suppose un accès que la matrice ne donne pas.
List<Map<String, Object?>> incoherencesAnnexe(List<Map<String, Object?>> questions, Map<String, Object?> rbac, Map<String, Object?> cat, CatalogueAssistant c) {
  final roles = (cat['rolesAnnexe'] as Map).cast<String, Object?>();
  final out = <Map<String, Object?>>[];
  for (final q in questions) {
    if (q['limite'] == true) continue;
    final id = (q['reaction'] as Map)['intention'] as String?;
    final profil = '${q['profilAnnexe']}';
    final rr = roles[profil];
    if (id == null || rr == null) continue;
    final ok = profilALeDroit(rbac, c, id, [for (final r in (rr as List)) '$r']);
    if (!ok) out.add({'n': q['n'], 'question': q['question'], 'profil': profil, 'roles': rr, 'intention': id, 'ecrans': c.intentions[id]!['ecransLecture']});
  }
  return out;
}

/// Pour chaque intention, les profils types SANS le droit (la seconde exécution de l'annexe doit refuser en nommant `LECTURE_NON_AUTORISEE`).
Map<String, List<String>> profilsSansDroit(List<Map<String, Object?>> matrice) => {
      for (final l in matrice)
        '${l['intention']}': [
          for (final e in (l['profils'] as Map).entries)
            if (e.value == false) '${e.key}'
        ],
    };

// ---------------------------------------------------------------------------------------------------------------------------------------------------------
// Robustesse : la MÊME question abîmée de quatre façons déterministes. Ce n'est pas une mesure de généralisation (voir le rapport), seulement de la tolérance aux accents,
// à la casse et aux fautes simples.
// ---------------------------------------------------------------------------------------------------------------------------------------------------------

const List<String> variantesRobustesse = ['sans_accents', 'majuscules', 'lettre_oubliee', 'lettres_inversees'];

/// Une question abîmée. La faute porte sur le PLUS LONG mot purement alphabétique d'au moins six lettres (à égalité, le premier), jamais sur un code ; sans tel mot, la
/// question est rendue telle quelle.
String abimer(String question, String variante) {
  const de = 'àâäáãåéèêëîïíìôöòóõùûüúçñÿ';
  const vers = 'aaaaaaeeeeiiiiooooouuuucny';
  switch (variante) {
    case 'sans_accents':
      return [for (final r in question.split('')) de.contains(r.toLowerCase()) ? vers[de.indexOf(r.toLowerCase())] : r].join();
    case 'majuscules':
      return question.toUpperCase();
    default:
      final mots = RegExp(r'[A-Za-zÀ-ÿ]{6,}').allMatches(question).toList();
      if (mots.isEmpty) return question;
      mots.sort((a, b) => b.group(0)!.length.compareTo(a.group(0)!.length));
      final m = mots.first;
      final mot = m.group(0)!;
      final k = mot.length ~/ 2;
      final faute = variante == 'lettre_oubliee' ? mot.substring(0, k) + mot.substring(k + 1) : mot.substring(0, k) + mot[k + 1] + mot[k] + mot.substring(k + 2);
      return question.replaceRange(m.start, m.end, faute);
  }
}

/// Pour chaque variante : (questions dont la réaction reste la même que celle de la question propre, questions). Les mots de la question propre ne sont pas jugés ici.
Map<String, (int, int)> mesurerRobustesse(List<Map<String, Object?>> questions, ReconnaisseurAssistant moteur) {
  final out = <String, (int, int)>{};
  for (final v in variantesRobustesse) {
    var ok = 0;
    for (final q in questions) {
      final propre = moteur.reconnaitre('${q['question']}');
      final abimee = moteur.reconnaitre(abimer('${q['question']}', v));
      if (abimee.statut == propre.statut && abimee.intention == propre.intention && abimee.code == propre.code) ok++;
    }
    out[v] = (ok, questions.length);
  }
  return out;
}

const String balisesMatriceDebut = '<!-- DEBUT MATRICE ENGENDREE : dart run tool/mesure_assistant.dart --matrice -->';
const String balisesMatriceFin = '<!-- FIN MATRICE ENGENDREE -->';

/// La matrice intention par profil type, en tableau Markdown (« oui » : le profil a le droit de lecture d'après rbac.json).
String tableauDroits(List<Map<String, Object?>> matrice, Map<String, Object?> profils) {
  final noms = profils.keys.toList();
  final b = StringBuffer()
    ..writeln(balisesMatriceDebut)
    ..writeln()
    ..writeln('| Int. | ${noms.join(' | ')} |')
    ..writeln('|---|${noms.map((_) => '---').join('|')}|');
  for (final l in matrice) {
    final p = (l['profils'] as Map).cast<String, Object?>();
    b.writeln('| ${l['intention']} | ${noms.map((n) => p[n] == true ? 'oui' : 'non').join(' | ')} |');
  }
  b
    ..writeln()
    ..writeln(balisesMatriceFin);
  return b.toString();
}
