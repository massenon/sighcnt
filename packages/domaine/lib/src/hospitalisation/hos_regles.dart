/// HOSPITALISATION (M3) — règles et référentiels portés de `m3-hospitalisation.js`, `data.js` (CHAMBRES, UNITES_OBSERVATION…) et
/// `PR.administrer` / `D.secteurAdministrateur`. Vecteurs : `test/vecteurs/hospitalisation.json` (écrans réels pilotés dans Chrome).
///
/// Doctrine : un lit ne porte qu'UNE admission active (`en_cours`) ; l'observation est DISTINCTE de l'hospitalisation ; le score de Glasgow
/// est CALCULÉ ; l'échelle du pouls n'est pas linéaire (interpolation entre graduations) ; le RANG décide du secteur d'administration.
library;

import '../format/js.dart';
import 'dart:math' as math;

typedef HosFiche = Map<String, Object?>;

class HosTypeChambre {
  const HosTypeChambre(this.id, this.label, this.tarif);
  final String id;
  final String label;
  final int tarif;
}

const hosTypesChambre = [
  HosTypeChambre('standard', 'Standard', 5000),
  HosTypeChambre('vip', 'VIP', 15000),
  HosTypeChambre('vvip', 'VVIP', 25000),
];

String hosLibelleTypeChambre(Object? id) {
  for (final t in hosTypesChambre) {
    if (t.id == id) return t.label;
  }
  return '${id ?? ''}';
}

class HosChambre {
  const HosChambre(this.code, this.type, this.aile, this.lits);
  final String code;
  final String type;
  final String aile;

  /// Libellés des lits (`A1 LIT1`).
  final List<String> lits;
}

List<HosChambre> _plan() {
  const p = [
    ('A1', 'standard', 2, 'Aile A — Médecine'),
    ('A2', 'standard', 2, 'Aile A — Médecine'),
    ('A3', 'standard', 2, 'Aile A — Médecine'),
    ('A4', 'standard', 2, 'Aile A — Médecine'),
    ('B1', 'standard', 2, 'Aile B — Maternité'),
    ('B2', 'standard', 2, 'Aile B — Maternité'),
    ('B3', 'standard', 2, 'Aile B — Maternité'),
    ('C1', 'vip', 1, 'Aile C — VIP'),
    ('C2', 'vip', 1, 'Aile C — VIP'),
    ('C3', 'vip', 1, 'Aile C — VIP'),
    ('D1', 'vvip', 1, 'Aile D — VVIP'),
    ('D2', 'vvip', 1, 'Aile D — VVIP'),
  ];
  return [
    for (final c in p)
      HosChambre(c.$1, c.$2, c.$4, [for (var i = 1; i <= c.$3; i++) '${c.$1} LIT$i'])
  ];
}

/// `D.CHAMBRES` : 12 chambres, 19 lits.
final List<HosChambre> hosChambres = _plan();

class HosLit {
  const HosLit(this.chambre, this.label);
  final HosChambre chambre;
  final String label;
}

List<HosLit> hosTousLits() => [
      for (final c in hosChambres) for (final l in c.lits) HosLit(c, l)
    ];

class HosUnite {
  const HosUnite(this.id, this.label, this.places);
  final String id;
  final String label;
  final int places;
}

const hosUnitesObservation = [
  HosUnite('urgences', 'Salle d’observation — urgences', 4),
  HosUnite('medecine', 'Salle d’observation — médecine générale', 3),
  HosUnite('maternite', 'Salle d’observation — maternité', 2),
  HosUnite('pediatrie', 'Salle d’observation — pédiatrie', 2),
];

class HosOrientation {
  const HosOrientation(this.id, this.label, this.ton);
  final String id;
  final String label;
  final String ton;
}

const hosOrientations = [
  HosOrientation('domicile', 'Sortie définitive — retour à domicile', 'success'),
  HosOrientation('hospitalisation', 'Hospitalisation complète', 'warning'),
  HosOrientation('transfert', 'Transfert vers un autre établissement', 'danger'),
  HosOrientation('bloc', 'Passage au bloc opératoire', 'danger'),
];

const hosDureeObservationReference = 24;

const hosActesSoins = [
  'Injection intraveineuse',
  'Injection intramusculaire',
  'Pose de perfusion',
  'Réfection de pansement',
  'Sondage urinaire',
  'Prise de constantes',
  'Aérosol',
  'Soins de nursing',
  'Transfusion sanguine',
  'Mise en observation',
];

/// `C.toDate` : une date seule (`AAAA-MM-JJ`) est lue en UTC, comme JavaScript.
DateTime? hosVersDate(Object? v) {
  if (v is DateTime) return v;
  final s = '${v ?? ''}'.trim();
  if (s.isEmpty) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m != null) {
    return DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }
  return DateTime.tryParse(s);
}

/// `C.daysBetween` : `Math.round((b − a) / 86 400 000)`.
int hosJoursEntre(Object? a, Object? b) {
  final x = hosVersDate(a), y = hosVersDate(b);
  if (x == null || y == null) return 0;
  return arrondiJs(y.difference(x).inMilliseconds / 86400000).toInt();
}

/// Un nombre comme JavaScript l'écrit (`3.5`, `3`).
String hosNum(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

// --------------------------------------------------------------------------------------------- admissions et lits

List<HosFiche> hosEnCours(Iterable<HosFiche> admissions) =>
    [for (final a in admissions) if (a['statut'] == 'en_cours') a];

HosFiche? hosLitOccupePar(String lit, Iterable<HosFiche> admissionsActives) {
  for (final a in admissionsActives) {
    if (a['statut'] == 'en_cours' && a['lit'] == lit) return a;
  }
  return null;
}

int hosDureeSejour(HosFiche a, DateTime auj) =>
    hosJoursEntre(a['dateEntree'], a['dateSortie'] ?? auj);

/// Refus nommé d'une admission sur un lit déjà occupé (`beforeSave`), ou `null`.
String? hosRefusAdmission(
    String? lit, HosFiche? fiche, Iterable<HosFiche> admissionsActives) {
  final o = hosLitOccupePar('$lit', admissionsActives);
  if (o != null && (fiche == null || o['id'] != fiche['id'])) {
    return 'Le lit $lit est déjà occupé par ${o['patient']}.';
  }
  return null;
}

/// `transform` de la création / modification d'une admission : identité du patient, chambre et type tirés du lit, référence conservée
/// (E360) ou lue sur le registre.
HosFiche hosConstruireAdmission(Map<String, Object?> v, HosFiche? fiche,
    Iterable<HosFiche> patients, Iterable<HosFiche> admissionsToutes,
    {required String Function(String, int, Iterable<HosFiche>) reference}) {
  final r = {...v};
  for (final p in patients) {
    if (p['code'] == v['patientCode']) {
      r['patientId'] = p['id'];
      r['patient'] = '${p['nom']} ${p['prenom']}';
      break;
    }
  }
  for (final l in hosTousLits()) {
    if (l.label == v['lit']) {
      r['chambre'] = l.chambre.code;
      r['typeChambre'] = l.chambre.type;
      break;
    }
  }
  if (r['reference'] == null || r['reference'] == '') {
    r['reference'] = fiche?['reference'] ??
        reference('H', 5, admissionsToutes);
  }
  // E370 : une admission existante GARDE son statut (le formulaire n'en porte pas) — sinon corriger une admission sortie la rouvrirait.
  r['statut'] ??= fiche?['statut'] ?? 'en_cours';
  return r;
}

({int admissions, int enCours, double taux, double dms}) hosKpisAdmissions(
    List<HosFiche> rows, DateTime auj) {
  final ec = rows.where((a) => a['statut'] == 'en_cours').length;
  final term = rows.where((a) => a['dateSortie'] != null && a['dateSortie'] != '').toList();
  var dms = 0.0;
  if (term.isNotEmpty) {
    final s = term.fold<int>(0, (n, a) => n + hosDureeSejour(a, auj));
    dms = arrondiJs(s / term.length * 10) / 10;
  }
  return (
    admissions: rows.length,
    enCours: ec,
    taux: ec / hosTousLits().length * 100,
    dms: dms
  );
}

// --------------------------------------------------------------------------------------------- observation

int hosHeuresEcoulees(HosFiche o, DateTime maintenant) {
  final fin = o['dateSortie'] != null ? hosVersDate(o['dateSortie'])! : maintenant;
  final d = hosVersDate(o['dateEntree'])!;
  return math.max(0, arrondiJs(fin.difference(d).inMilliseconds / 3600000).toInt());
}

bool hosDepasse(HosFiche o, DateTime maintenant) =>
    hosHeuresEcoulees(o, maintenant) > hosDureeObservationReference;

HosOrientation? hosOrientation(Object? id) {
  for (final o in hosOrientations) {
    if (o.id == id) return o;
  }
  return null;
}

/// L'admission ouverte par l'orientation « hospitalisation complète » : le séjour commence, l'observation reste un autre objet.
HosFiche hosAdmissionDepuisObservation(
        HosFiche o, DateTime sortie, String conclusion, String reference) =>
    {
      'reference': reference,
      'patientId': o['patientId'],
      'patient': o['patient'],
      'patientCode': o['patientCode'],
      'dateEntree':
          '${sortie.year.toString().padLeft(4, '0')}-${sortie.month.toString().padLeft(2, '0')}-${sortie.day.toString().padLeft(2, '0')}',
      'dateSortie': null,
      'diagnosticEntree': conclusion,
      'symptomes': o['motif'],
      'priseEnCharge': 'plus_8h',
      'infirmier': o['infirmier'],
      'statut': 'en_cours',
      'origineObservation': o['reference'],
    };

// --------------------------------------------------------------------------------------------- feuille de température

class HosEchelle {
  const HosEchelle(this.code, this.label, this.unite, this.graduations, this.couleur);
  final String code;
  final String label;
  final String unite;
  final List<num> graduations;
  final String couleur;
}

const hosEchelles = [
  HosEchelle('ta', 'TA', 'cmHg', [5, 10, 15, 20, 25, 30], '#7c3aed'),
  HosEchelle('pouls', 'Pouls', 'bpm', [60, 80, 100, 120, 140, 180], '#dc2626'),
  HosEchelle('temperature', 'T°', '°C', [36, 37, 38, 39, 40, 41], '#0f766e'),
  HosEchelle('fr', 'FR', '/min', [10, 20, 30, 40, 50, 60], '#2563eb'),
  HosEchelle('diurese', 'Diurèse', 'L', [0, 0.5, 1, 1.5, 2, 2.5], '#ca8a04'),
];

const hosMoments = [
  ('matin', 'M', 'Matin'),
  ('midi', 'Mi', 'Midi'),
  ('soir', 'S', 'Soir'),
];

/// Position (0..1) d'une valeur entre deux graduations — PAS une règle de trois : l'échelle du pouls n'est pas linéaire.
double? hosPositionSurEchelle(HosEchelle e, num? valeur) {
  final g = e.graduations;
  if (valeur == null || valeur.isNaN) return null;
  if (valeur <= g.first) return 0;
  if (valeur >= g.last) return 1;
  for (var i = 0; i < g.length - 1; i++) {
    if (valeur >= g[i] && valeur <= g[i + 1]) {
      final dans = (valeur - g[i]) / (g[i + 1] - g[i]);
      return (i + dans) / (g.length - 1);
    }
  }
  return null;
}

String hosMomentDe(Object? heure) {
  final h = int.tryParse(RegExp(r'^\s*\d+').firstMatch('${heure ?? ''}'.padRight(2).substring(0, 2))?.group(0) ?? '');
  if (h == null) return 'matin';
  if (h < 11) return 'matin';
  if (h < 17) return 'midi';
  return 'soir';
}

double? hosSystoliqueDe(Object? tension) {
  final m = RegExp(r'^\s*(\d+(?:[.,]\d+)?)').firstMatch('${tension ?? ''}');
  return m == null ? null : double.parse(m[1]!.replaceAll(',', '.'));
}

String _hm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';

/// Les relevés d'un patient : UNE série, DEUX sources (accueil + lit du patient), triée par date puis heure.
List<HosFiche> hosRelevesDe(String patientId,
    {required Iterable<HosFiche> constantes,
    required Iterable<HosFiche> admissions,
    required Iterable<HosFiche> releves}) {
  final out = <HosFiche>[];
  for (final c in constantes) {
    if (c['patientId'] != patientId) continue;
    final dh = hosVersDate(c['dateHeure']);
    final h = dh == null ? '' : _hm(dh);
    final sys = c['tensionSys'];
    out.add({
      'date': '${c['dateHeure'] ?? ''}'.substring(0, math.min(10, '${c['dateHeure'] ?? ''}'.length)),
      'moment': c['moment'] ?? hosMomentDe(h),
      'heure': h,
      'temperature': c['temperature'],
      'ta': sys != null ? sys : hosSystoliqueDe(c['tension']),
      'tension': c['tension'],
      'pouls': c['pouls'],
      'fr': c['fr'],
      'spo2': c['spo2'],
      'diurese': c['diurese'],
      'par': c['releveePar'],
      'origine': 'Accueil',
    });
  }
  final ids = {
    for (final a in admissions)
      if (a['patientId'] == patientId) a['id']
  };
  if (ids.isNotEmpty) {
    for (final r in releves) {
      if (!ids.contains(r['admissionId'])) continue;
      final d = r['diurese'];
      out.add({
        'date': r['date'],
        'moment': hosMomentDe(r['heure']),
        'heure': r['heure'],
        'temperature': r['temperature'] is num
            ? r['temperature']
            : (r['temperature'] == null ? null : num.tryParse('${r['temperature']}')),
        'ta': hosSystoliqueDe(r['tension']),
        'tension': r['tension'],
        'pouls': r['fc'],
        'fr': r['fr'],
        'spo2': r['spo2'],
        // saisie en millilitres, échelle graduée en litres
        'diurese': d != null ? arrondiJs((d as num) / 1000 * 100) / 100 : null,
        'par': r['saisiPar'],
        'origine': 'Hospitalisation',
      });
    }
  }
  out.sort((a, b) {
    final d = '${a['date']}'.compareTo('${b['date']}');
    return d != 0 ? d : '${a['heure']}'.compareTo('${b['heure']}');
  });
  return out;
}

class HosPoint {
  const HosPoint(this.x, this.y);
  final double x;
  final double y;
}

class HosCourbe {
  HosCourbe(this.largeurTotale, this.hauteurTotale, this.colonnes, this.polylignes,
      this.graduations);
  final double largeurTotale;
  final double hauteurTotale;

  /// (jour, moment) de chaque colonne.
  final List<(String, String)> colonnes;

  /// Une liste de points par échelle (code → points), dans l'ordre de `hosEchelles`.
  final Map<String, List<HosPoint>> polylignes;

  /// Textes des six lignes de grille, du bas vers le haut (`5 60 36 10 0`).
  final List<String> graduations;
  static const double h = 260, l = 60;
}

/// La courbe à cinq échelles : sept dates, trois moments par date, six lignes de grille partagées.
HosCourbe hosCourbe(List<HosFiche> rel) {
  final jours = <String>[];
  for (final r in rel) {
    final j = '${r['date']}';
    if (!jours.contains(j)) jours.add(j);
  }
  final sept = jours.length > 7 ? jours.sublist(jours.length - 7) : jours;
  final colonnes = <(String, String)>[];
  final cellules = <HosFiche?>[];
  for (final j in sept) {
    for (final m in hosMoments) {
      colonnes.add((j, m.$1));
      HosFiche? t;
      for (final r in rel) {
        if (r['date'] == j && r['moment'] == m.$1) {
          t = r;
          break;
        }
      }
      cellules.add(t);
    }
  }
  const h = HosCourbe.h, l = HosCourbe.l;
  final n = colonnes.length;
  final largeur = math.max(n * 34, 300).toDouble();
  final pas = largeur / math.max(n, 1);
  final poly = <String, List<HosPoint>>{};
  for (final e in hosEchelles) {
    final pts = <HosPoint>[];
    for (var k = 0; k < n; k++) {
      final r = cellules[k];
      if (r == null) continue;
      final brute = r[e.code];
      if (brute == null || brute == '') continue; // E365 : absent ≠ zéro
      final v = brute is num ? brute : num.tryParse('$brute');
      final pos = hosPositionSurEchelle(e, v);
      if (pos == null) continue;
      pts.add(HosPoint(l + k * pas + pas / 2, h - pos * h));
    }
    poly[e.code] = pts;
  }
  String g(num x) => x % 1 != 0 ? x.toStringAsFixed(1) : '${x.round()}';
  return HosCourbe(l + largeur + 12, h + 46, colonnes, poly, [
    for (var i = 0; i < 6; i++) hosEchelles.map((e) => g(e.graduations[i])).join(' ')
  ]);
}

// --------------------------------------------------------------------------------------------- Glasgow

const hosGlasgow = [
  (
    'Ouverture des yeux',
    [('Spontanée', 4), ('Au bruit, à la parole', 3), ('À la douleur', 2), ('Aucune réponse', 1)]
  ),
  (
    'Réponse verbale',
    [('Normale', 5), ('Confuse', 4), ('Inappropriée', 3), ('Incompréhensible', 2), ('Aucune réponse', 1)]
  ),
  (
    'Réponse motrice',
    [
      ('À la commande', 6),
      ('Localise la douleur', 5),
      ('Se retire à la douleur', 4),
      ('Flexion à la douleur', 3),
      ('Extension à la douleur', 2),
      ('Aucune réponse', 1)
    ]
  ),
];

/// Le score est la SOMME des trois axes (3 à 15) : calculé, jamais saisi.
({List<HosFiche> axes, int score}) hosScoreGlasgow(List<int> points) {
  final axes = <HosFiche>[];
  var score = 0;
  for (var i = 0; i < hosGlasgow.length; i++) {
    final p = points[i];
    String lib = '—';
    for (final it in hosGlasgow[i].$2) {
      if (it.$2 == p) lib = it.$1;
    }
    axes.add({'axe': hosGlasgow[i].$1, 'libelle': lib, 'points': p});
    score += p;
  }
  return (axes: axes, score: score);
}

/// `danger` (≤ 8), `warning` (9 à 12), `success`.
String hosTonGlasgow(num score) => score <= 8 ? 'danger' : (score <= 12 ? 'warning' : 'success');

// --------------------------------------------------------------------------------------------- transfusion

const hosTempsTransfusion = [
  ('t0', 'Avant la pose'),
  ('t15', '15 min'),
  ('t30', '30 min'),
  ('t60', '60 min'),
  ('t90', '90 min'),
  ('fin', 'Fin'),
  ('h1', '1 heure après'),
  ('h2', '2 heures après'),
];

const hosElementsTransfusion = [
  ('temperature', 'Température', '°C'),
  ('ta', 'Tension artérielle', ''),
  ('fr', 'Fréquence respiratoire', '/min'),
  ('fc', 'Fréquence cardiaque', 'bpm'),
  ('spo2', 'SpO₂', '%'),
  ('urines', 'Aspect des urines', ''),
  ('conscience', 'Conscience', ''),
  ('autre', 'Autre élément surveillé', ''),
];

/// Les valeurs saisies → (valeurs par temps, nombre de temps relevés). Un temps compte dès qu'un de ses éléments est rempli.
({Map<String, Map<String, Object?>> valeurs, int releves}) hosValeursTransfusion(
    Map<String, Object?> saisie) {
  final valeurs = <String, Map<String, Object?>>{};
  var n = 0;
  for (final t in hosTempsTransfusion) {
    final m = <String, Object?>{};
    var rempli = false;
    for (final e in hosElementsTransfusion) {
      final x = saisie['${t.$1}_${e.$1}'];
      m[e.$1] = x;
      if (x != null && x != '') rempli = true;
    }
    valeurs[t.$1] = m;
    if (rempli) n++;
  }
  return (valeurs: valeurs, releves: n);
}

// --------------------------------------------------------------------------------------------- relais d'administration

/// `D.secteurAdministrateur` : le RANG décide du secteur.
({String secteur, String motif}) hosSecteurAdministrateur(Object? modalite, int rang) {
  if (modalite == 'ambulatoire') {
    return (
      secteur: 'salle_soins',
      motif: 'Traitement ambulatoire : toutes les administrations reviennent à la salle de soins.'
    );
  }
  if (rang <= 1) {
    return (
      secteur: 'salle_soins',
      motif: 'Première administration d’un traitement hospitalier : elle revient à la salle de soins.'
    );
  }
  return (
    secteur: 'hospitalisation',
    motif: 'Administration n° $rang : le relais est passé à l’hospitalisation.'
  );
}

/// `D.CAPACITES[fonction].executerSoins` (vecteur `executerSoins`).
const hosExecuteSoins = {'sage_femme': true, 'infirmier': true};

int hosRangSuivant(Iterable<HosFiche> administrationsActives, Object? prescriptionId, int ligne) =>
    administrationsActives
        .where((a) => a['prescriptionId'] == prescriptionId && a['ligneIndex'] == ligne)
        .length +
    1;

class HosSoinDu {
  HosSoinDu(this.prescription, this.index, this.ligne, this.rang, this.total, this.motif, this.bloque);
  final HosFiche prescription;
  final int index;
  final HosFiche ligne;
  final int rang;
  final int total;
  final String motif;
  final bool bloque;
}

List<HosSoinDu> hosSoinsDuSecteur(String secteur, Iterable<HosFiche> prescriptionsActives,
    Iterable<HosFiche> administrationsActives) {
  final out = <HosSoinDu>[];
  for (final p in prescriptionsActives) {
    if (p['statut'] != 'en_cours') continue;
    final lignes = (p['lignes'] as List? ?? const []);
    for (var i = 0; i < lignes.length; i++) {
      final l = (lignes[i] as Map).cast<String, Object?>();
      final rang = hosRangSuivant(administrationsActives, p['id'], i);
      final total = (l['nbAdministrations'] as num?)?.toInt() ?? 1;
      final att = hosSecteurAdministrateur(p['modalite'], rang);
      if (rang <= total && att.secteur == secteur) {
        out.add(HosSoinDu(p, i, l, rang, total, att.motif, p['statutPaiement'] != 'payee'));
      }
    }
  }
  return out;
}

class HosErreur implements Exception {
  HosErreur(this.message);
  final String message;
  @override
  String toString() => message;
}

class HosAdministration {
  HosAdministration({required this.ok, this.motif, this.rang, this.secteur, this.fiche, this.termine = false});
  final bool ok;
  final String? motif;
  final int? rang;
  final String? secteur;

  /// La fiche à insérer (`administrations`) ; `termine` : la prescription est servie en entier.
  final HosFiche? fiche;
  final bool termine;
}

/// `PR.administrer` : refus NOMMÉS (non réglée, mauvais secteur, exécutant qui n'exécute pas), jamais muets.
HosAdministration hosAdministrer(
  HosFiche? prescription,
  Iterable<HosFiche> administrationsActives, {
  required Iterable<HosFiche> soignants,
  required int ligneIndex,
  String? secteur,
  String? executantId,
  String? observation,
  required DateTime dateHeure,
  required String reference,
  bool forcer = false,
}) {
  if (prescription == null) throw HosErreur('Prescription introuvable.');
  final lignes = (prescription['lignes'] as List? ?? const []);
  if (ligneIndex < 0 || ligneIndex >= lignes.length) {
    throw HosErreur('Ligne de prescription introuvable.');
  }
  final ligne = (lignes[ligneIndex] as Map).cast<String, Object?>();
  if (prescription['statutPaiement'] != 'payee' && !forcer) {
    return HosAdministration(
        ok: false,
        motif: 'Prescription non réglée — l’administration reste bloquée jusqu’à l’encaissement.');
  }
  final rang = hosRangSuivant(administrationsActives, prescription['id'], ligneIndex);
  final att = hosSecteurAdministrateur(prescription['modalite'], rang);
  if (secteur != null && secteur != att.secteur) {
    return HosAdministration(ok: false, rang: rang, secteur: att.secteur, motif: att.motif);
  }
  HosFiche? exec;
  for (final x in soignants) {
    if (x['id'] == executantId) exec = x;
  }
  if (exec != null && exec['execute'] != true) {
    return HosAdministration(
        ok: false, rang: rang, motif: '${exec['nomComplet']} (${exec['poste']}) n’exécute pas les soins.');
  }
  final total = (ligne['nbAdministrations'] as num?)?.toInt() ?? 1;
  final fiche = <String, Object?>{
    'reference': reference,
    'prescriptionId': prescription['id'],
    'prescriptionRef': prescription['reference'],
    'ligneIndex': ligneIndex,
    'libelle': ligne['libelle'],
    'patientId': prescription['patientId'],
    'patientCode': prescription['patientCode'],
    'patient': prescription['patient'],
    'dateHeure': dateHeure.toUtc().toIso8601String(),
    'rang': rang,
    'total': total,
    'secteur': att.secteur,
    'motifSecteur': att.motif,
    'executantId': executantId,
    'executant': exec != null ? exec['nomComplet'] : '—',
    'observation': observation ?? '',
    'modalite': prescription['modalite'],
  };
  // la prescription se termine quand toutes ses lignes sont servies (la fiche à insérer compte déjà)
  var reste = false;
  for (var i = 0; i < lignes.length; i++) {
    final li = (lignes[i] as Map).cast<String, Object?>();
    final t = (li['nbAdministrations'] as num?)?.toInt() ?? 1;
    final deja = administrationsActives
            .where((a) => a['prescriptionId'] == prescription['id'] && a['ligneIndex'] == i)
            .length +
        (i == ligneIndex ? 1 : 0);
    if (deja + 1 <= t) reste = true;
  }
  return HosAdministration(
      ok: true, rang: rang, secteur: att.secteur, fiche: fiche, termine: !reste);
}
