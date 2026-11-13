/// LA MESURE D'UNE LECTURE OCR contre sa transcription de référence (lot OCR-prep) : taux de mots corrects, taux de caractères corrects, mots perdus, ACCENTS FRANÇAIS perdus.
///
/// Ce fichier ne choisit aucun moteur et ne promet aucune qualité : il dit, pour un texte lu et sa transcription, ce qui a été retrouvé. Le français est le risque (é è ê à ç œ) : une mesure
/// qui n'isolerait pas les accents laisserait un moteur qui les supprime passer pour bon, d'où des chiffres séparés. Les définitions sont celles du rapport (annexe de la décision) :
///
///  - un MOT est une suite de lettres et de chiffres, casse et accents compris ; la ponctuation n'est pas un mot ;
///  - TAUX DE MOTS CORRECTS = 1 moins (substitutions + oublis + ajouts) sur le nombre de mots de la référence (distance d'édition entre les deux suites de mots), borné à 0 ;
///  - TAUX DE CARACTÈRES CORRECTS = 1 moins la distance d'édition des caractères sur la longueur de la référence, espaces normalisées, borné à 0 ;
///  - MOT PERDU = un mot de la référence dont même la forme sans accent et sans casse n'est pas dans le texte lu (disparu ou déformé) ;
///  - ACCENT PERDU = une lettre accentuée de la référence qui, dans le mot retrouvé sans ses accents, a perdu son accent (é lu e, ç lu c, œ lu oe).
library;

import '../format/diacritiques.dart';

const String _accents = 'àâäéèêëîïôöùûüÿçœæÀÂÄÉÈÊËÎÏÔÖÙÛÜŸÇŒÆ';

/// Les mots d'un texte : suites de lettres et de chiffres, casse et accents conservés.
List<String> ocrMotsDeMesure(String texte) => [for (final m in texte.split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))) if (m.isNotEmpty) m];

/// La forme « pliée » d'un mot : sans accent, sans casse, œ lu oe et æ lu ae.
String ocrPlier(String m) => sansDiacritiques(m).toLowerCase().replaceAll('œ', 'oe').replaceAll('æ', 'ae');

int _nbAccents(String m) {
  var n = 0;
  for (final r in m.runes) {
    if (_accents.contains(String.fromCharCode(r))) n++;
  }
  return n;
}

/// La distance d'édition (Levenshtein) entre deux suites, en deux lignes de mémoire.
int _distance<T>(List<T> a, List<T> b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prec = List<int>.generate(b.length + 1, (j) => j);
  var cour = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    cour[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cout = a[i - 1] == b[j - 1] ? 0 : 1;
      var v = prec[j - 1] + cout;
      if (prec[j] + 1 < v) v = prec[j] + 1;
      if (cour[j - 1] + 1 < v) v = cour[j - 1] + 1;
      cour[j] = v;
    }
    final t = prec;
    prec = cour;
    cour = t;
  }
  return prec[b.length];
}

String _espaces(String t) => t.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Ce que la mesure d'un texte lu rend.
class MesureTexte {
  const MesureTexte({
    required this.motsReference,
    required this.motsLus,
    required this.motsCorrects,
    required this.tauxMots,
    required this.tauxCaracteres,
    required this.motsPerdus,
    required this.exemplesPerdus,
    required this.accentsReference,
    required this.accentsPerdus,
    required this.exemplesAccents,
    required this.distanceMots,
    required this.distanceCaracteres,
    required this.caracteresReference,
  });
  final int motsReference;
  final int motsLus;

  /// Les mots de la référence retrouvés tels quels (nombre = motsReference moins la distance d'édition, borné à 0).
  final int motsCorrects;
  final double tauxMots;
  final double tauxCaracteres;
  final int motsPerdus;
  final List<String> exemplesPerdus;
  final int accentsReference;
  final int accentsPerdus;
  final List<String> exemplesAccents;
  final int distanceMots;
  final int distanceCaracteres;
  final int caracteresReference;

  /// Le taux d'accents retrouvés ; `null` quand la référence n'en porte aucun (rien à mesurer : jamais un 100 % de complaisance).
  double? get tauxAccents => accentsReference == 0 ? null : 1 - accentsPerdus / accentsReference;

  Map<String, Object?> toJson() => {
        'motsReference': motsReference,
        'motsLus': motsLus,
        'motsCorrects': motsCorrects,
        'tauxMots': tauxMots,
        'tauxCaracteres': tauxCaracteres,
        'motsPerdus': motsPerdus,
        'exemplesPerdus': exemplesPerdus,
        'accentsReference': accentsReference,
        'accentsPerdus': accentsPerdus,
        'tauxAccents': tauxAccents,
        'exemplesAccents': exemplesAccents,
        'distanceMots': distanceMots,
        'distanceCaracteres': distanceCaracteres,
        'caracteresReference': caracteresReference,
      };
}

double _borne(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// Mesure le texte [lu] contre sa transcription de [reference].
MesureTexte ocrMesurer(String reference, String lu) {
  final mr = ocrMotsDeMesure(reference), ml = ocrMotsDeMesure(lu);
  final dm = _distance<String>(mr, ml);
  final cr = _espaces(reference).runes.toList(), cl = _espaces(lu).runes.toList();
  final dc = _distance<int>(cr, cl);
  final tauxMots = mr.isEmpty ? (ml.isEmpty ? 1.0 : 0.0) : _borne(1 - dm / mr.length);
  final tauxCar = cr.isEmpty ? (cl.isEmpty ? 1.0 : 0.0) : _borne(1 - dc / cr.length);

  // Les mots perdus et les accents perdus se comptent sur des multi-ensembles : un mot dit deux fois dans la référence doit être lu deux fois.
  final exact = <String, int>{};
  final plie = <String, List<String>>{};
  for (final m in ml) {
    exact[m] = (exact[m] ?? 0) + 1;
    plie.putIfAbsent(ocrPlier(m), () => []).add(m);
  }
  var perdus = 0;
  var accRef = 0, accPerdus = 0;
  final exPerdus = <String>[], exAccents = <String>[];
  // Première passe : les mots lus à l'identique consomment leur exemplaire.
  final restes = <String>[];
  for (final m in mr) {
    accRef += _nbAccents(m);
    final k = exact[m] ?? 0;
    if (k > 0) {
      exact[m] = k - 1;
      final l = plie[ocrPlier(m)]!;
      l.remove(m);
    } else {
      restes.add(m);
    }
  }
  // Seconde passe : ce qui reste cherche sa forme pliée parmi les mots lus non consommés.
  for (final m in restes) {
    final l = plie[ocrPlier(m)];
    if (l != null && l.isNotEmpty) {
      final lu1 = l.removeAt(0);
      final perte = _nbAccents(m) - _nbAccents(lu1);
      if (perte > 0) {
        accPerdus += perte;
        if (exAccents.length < 20) exAccents.add('$m lu $lu1');
      }
    } else {
      perdus++;
      if (exPerdus.length < 20) exPerdus.add(m);
    }
  }
  return MesureTexte(
    motsReference: mr.length,
    motsLus: ml.length,
    motsCorrects: (mr.length - dm) < 0 ? 0 : mr.length - dm,
    tauxMots: tauxMots,
    tauxCaracteres: tauxCar,
    motsPerdus: perdus,
    exemplesPerdus: exPerdus,
    accentsReference: accRef,
    accentsPerdus: accPerdus,
    exemplesAccents: exAccents,
    distanceMots: dm,
    distanceCaracteres: dc,
    caracteresReference: cr.length,
  );
}

/// La mesure d'UN scan par UN moteur : le texte lu et sa mesure, ou le refus nommé du moteur ; le temps de lecture et le nombre de pages (le temps par page s'en déduit).
class MesureScan {
  const MesureScan({required this.fichier, required this.pages, required this.dureeMs, this.mesure, this.refusCode, this.refusMotif});
  final String fichier;
  final int pages;
  final int dureeMs;
  final MesureTexte? mesure;
  final String? refusCode;
  final String? refusMotif;
  bool get lu => mesure != null;
  double get msParPage => pages <= 0 ? 0 : dureeMs / pages;

  Map<String, Object?> toJson() => {'fichier': fichier, 'pages': pages, 'dureeMs': dureeMs, 'msParPage': msParPage, 'lu': lu, 'refusCode': refusCode, 'refusMotif': refusMotif, 'mesure': mesure?.toJson()};
}

/// L'ensemble des scans d'un moteur : taux moyens (chaque scan compte pour un) et taux sur l'ensemble des mots (un long scan pèse plus), temps moyen par page. Un scan que le moteur
/// refuse compte pour ZÉRO mot correct (jamais exclu : un moteur qui refuse la moitié des scans ne se mesure pas sur l'autre moitié).
class SyntheseMoteur {
  SyntheseMoteur(this.moteur, this.version, this.scans);
  final String moteur;
  final String version;
  final List<MesureScan> scans;

  int get nbScans => scans.length;
  int get nbLus => scans.where((s) => s.lu).length;
  int get nbRefuses => nbScans - nbLus;
  double _moy(double Function(MesureScan) f) => scans.isEmpty ? 0 : scans.map(f).reduce((a, b) => a + b) / scans.length;
  double get moyenneMots => _moy((s) => s.mesure?.tauxMots ?? 0);
  double get moyenneCaracteres => _moy((s) => s.mesure?.tauxCaracteres ?? 0);
  int get motsReference => scans.fold(0, (a, s) => a + (s.mesure?.motsReference ?? 0));
  int get motsPerdus => scans.fold(0, (a, s) => a + (s.mesure?.motsPerdus ?? 0));
  int get accentsReference => scans.fold(0, (a, s) => a + (s.mesure?.accentsReference ?? 0));
  int get accentsPerdus => scans.fold(0, (a, s) => a + (s.mesure?.accentsPerdus ?? 0));
  double? get tauxAccents => accentsReference == 0 ? null : 1 - accentsPerdus / accentsReference;
  double get msParPage {
    final pages = scans.fold<int>(0, (a, s) => a + s.pages);
    final ms = scans.fold<int>(0, (a, s) => a + s.dureeMs);
    return pages == 0 ? 0 : ms / pages;
  }

  /// Le taux de mots corrects sur l'ensemble des mots de référence.
  double get tauxMotsEnsemble {
    final total = scans.fold<int>(0, (a, s) => a + (s.mesure?.motsReference ?? 0));
    if (total == 0) return 0;
    return scans.fold<int>(0, (a, s) => a + (s.mesure?.motsCorrects ?? 0)) / total;
  }

  Map<String, Object?> toJson() => {
        'moteur': moteur,
        'version': version,
        'scans': nbScans,
        'lus': nbLus,
        'refuses': nbRefuses,
        'moyenneMots': moyenneMots,
        'moyenneCaracteres': moyenneCaracteres,
        'tauxMotsEnsemble': tauxMotsEnsemble,
        'motsReference': motsReference,
        'motsPerdus': motsPerdus,
        'accentsReference': accentsReference,
        'accentsPerdus': accentsPerdus,
        'tauxAccents': tauxAccents,
        'msParPage': msParPage,
        'detail': [for (final s in scans) s.toJson()],
      };
}

String _pc(double v) => '${(v * 100).toStringAsFixed(1).replaceFirst('.', ',')} %';

/// Le rapport en Markdown, à mettre en annexe de la décision. Il dit ce qu'il mesure, sur combien de scans, et ce qu'il NE permet PAS de conclure.
String ocrRapportMarkdown({required List<SyntheseMoteur> syntheses, required String date, required String dossier, required String machine, required int nbSansTranscription, required bool synthetique, bool avecExemples = false}) {
  final b = StringBuffer();
  b.writeln('# Mesure de la lecture OCR : rapport du $date');
  b.writeln();
  b.writeln('Dossier mesuré : `$dossier` ; machine : $machine.');
  b.writeln();
  if (synthetique) {
    b.writeln('> **Cette mesure porte sur des scans SYNTHÉTIQUES et des moteurs FACTICES.** Elle prouve que la mesure est juste (un moteur parfait donne 100 %, un moteur qui supprime les accents le montre), elle ne dit RIEN de la qualité d’un moteur réel sur les documents de la clinique.');
    b.writeln();
  } else {
    final n = syntheses.isEmpty ? 0 : syntheses.first.nbScans;
    b.writeln('> Mesure sur **$n scan${n > 1 ? 's' : ''}**. La décision de la Direction (Q7) est d’essayer sur TROIS vrais scans de la clinique : ${n < 3 ? 'ce rapport en porte moins de trois, il ne suffit pas pour décider.' : 'un échantillon de cette taille indique, il ne démontre pas.'} Aucun moteur n’est choisi par ce rapport.');
    b.writeln();
  }
  if (nbSansTranscription > 0) {
    b.writeln('$nbSansTranscription scan${nbSansTranscription > 1 ? 's' : ''} du dossier ${nbSansTranscription > 1 ? 'n’ont' : 'n’a'} pas de transcription de référence (`.txt` de même nom) : ${nbSansTranscription > 1 ? 'ils sont ignorés' : 'il est ignoré'} et nommé${nbSansTranscription > 1 ? 's' : ''} ci-dessous.');
    b.writeln();
  }
  b.writeln('## Définitions');
  b.writeln();
  b.writeln('- **Mot** : suite de lettres et de chiffres, casse et accents compris.');
  b.writeln('- **Mots corrects** : 1 moins la distance d’édition des mots sur le nombre de mots de la référence, borné à 0.');
  b.writeln('- **Caractères corrects** : 1 moins la distance d’édition des caractères sur la longueur de la référence (espaces normalisées), borné à 0.');
  b.writeln('- **Mot perdu** : mot de la référence dont même la forme sans accent et sans casse n’est pas dans le texte lu.');
  b.writeln('- **Accent perdu** : lettre accentuée de la référence retrouvée sans son accent (é lu e, ç lu c, œ lu oe).');
  b.writeln('- **Temps par page** : durée de lecture mesurée sur cette machine, divisée par le nombre de pages. Elle ne vaut que pour cette machine.');
  b.writeln('- Un scan que le moteur REFUSE compte pour zéro mot correct : il n’est jamais exclu de la moyenne.');
  b.writeln();
  b.writeln('## Comparaison');
  b.writeln();
  b.writeln('| Moteur | Scans lus / refusés | Mots corrects (moyenne) | Mots corrects (ensemble) | Caractères corrects | Mots perdus | Accents retrouvés | Temps par page |');
  b.writeln('|---|---|---|---|---|---|---|---|');
  for (final s in syntheses) {
    b.writeln('| ${s.moteur} ${s.version} | ${s.nbLus} / ${s.nbRefuses} | ${_pc(s.moyenneMots)} | ${_pc(s.tauxMotsEnsemble)} | ${_pc(s.moyenneCaracteres)} | ${s.motsPerdus} sur ${s.motsReference} | ${s.tauxAccents == null ? 'sans objet (aucun accent en référence)' : '${_pc(s.tauxAccents!)} (${s.accentsPerdus} perdus sur ${s.accentsReference})'} | ${s.msParPage.toStringAsFixed(0)} ms |');
  }
  b.writeln();
  for (final s in syntheses) {
    b.writeln('## ${s.moteur} ${s.version}');
    b.writeln();
    b.writeln('| Scan | Pages | Mots corrects | Caractères corrects | Mots perdus | Accents perdus | Temps par page |');
    b.writeln('|---|---|---|---|---|---|---|');
    for (final x in s.scans) {
      if (x.mesure == null) {
        b.writeln('| ${x.fichier} | ${x.pages} | refusé : ${x.refusCode} | | | | |');
      } else {
        final m = x.mesure!;
        b.writeln('| ${x.fichier} | ${x.pages} | ${_pc(m.tauxMots)} | ${_pc(m.tauxCaracteres)} | ${m.motsPerdus} sur ${m.motsReference} | ${m.accentsReference == 0 ? 'sans objet' : '${m.accentsPerdus} sur ${m.accentsReference}'} | ${x.msParPage.toStringAsFixed(0)} ms |');
      }
    }
    b.writeln();
    for (final x in s.scans) {
      if (x.mesure == null) {
        b.writeln('- ${x.fichier} : refus ${x.refusCode}, ${x.refusMotif}.');
      } else {
        if (avecExemples && x.mesure!.exemplesPerdus.isNotEmpty) b.writeln('- ${x.fichier}, mots perdus (au plus vingt) : ${x.mesure!.exemplesPerdus.join(', ')}.');
        if (avecExemples && x.mesure!.exemplesAccents.isNotEmpty) b.writeln('- ${x.fichier}, accents perdus (au plus vingt) : ${x.mesure!.exemplesAccents.join(' ; ')}.');
      }
    }
    b.writeln();
  }
  b.writeln('## Ce que ce rapport ne dit pas');
  b.writeln();
  b.writeln('- Il ne dit pas quel moteur choisir : la décision appartient à la Direction, après l’essai sur les trois vrais scans.');
  b.writeln('- Il ne mesure ni la licence, ni la taille de l’installeur Windows, ni la charge d’un poste de clinique au repos : ces contraintes se relèvent à part.');
  b.writeln(avecExemples
      ? '- Les exemples de mots perdus ci-dessus sont tirés des transcriptions : sur des documents réels ils peuvent contenir des noms ; relire avant de joindre ce rapport à la décision, ou relancer sans `--exemples`.'
      : '- Ce rapport ne cite AUCUN mot des documents (ni mot perdu, ni accent perdu en clair) : il ne porte que des nombres. `--exemples` ajoute les mots perdus, pour qui veut comprendre une erreur sur des documents sans donnée de patient.');
  return b.toString();
}
