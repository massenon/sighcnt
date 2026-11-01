/// Formats français de la maquette (`core.js`). Un montant ne se coupe pas en fin de ligne :
/// U+202F entre les milliers, U+00A0 avant la devise (CLAUDE.md, « typographie française »).
library;

import 'js.dart';

const String devise = 'FCFA';

/// `C.money(v, withCurrency)` — pas de décimale.
String money(Object? v, {bool avecDevise = true}) {
  final n = nombreOuZero(v);
  var s = grouperMilliers(arrondiJs(n.abs()).toStringAsFixed(0));
  if (n < 0) s = '-$s';
  return avecDevise ? '$s $devise' : s;
}

/// Le nombre que porte [v], ou `null` s'il n'en porte pas (absent, vide, texte non numérique). Un zéro ET un inconnu ne sont pas la même chose.
num? nombreOuNul(Object? v) {
  if (v == null) return null;
  if (v is num) return v.isFinite ? v : null;
  final t = '$v'.trim();
  if (t.isEmpty) return null;
  final n = num.tryParse(t);
  return n != null && n.isFinite ? n : null;
}

/// `C.sumOuNul(arr, key)` : la somme des seules valeurs numériques, `null` quand aucune ligne n'en porte (masse salariale d'un jeu vidé de ses salaires).
num? sommeOuNul(Iterable<Object?> valeurs) {
  num? t;
  for (final v in valeurs) {
    final n = nombreOuNul(v);
    if (n != null) t = (t ?? 0) + n;
  }
  return t;
}

/// `C.moyenneOuNul(arr, key)` : moyenne des seules valeurs numériques, `null` s'il n'y en a aucune.
num? moyenneOuNul(Iterable<Object?> valeurs) {
  var n = 0;
  num t = 0;
  for (final v in valeurs) {
    final x = nombreOuNul(v);
    if (x != null) {
      t += x;
      n++;
    }
  }
  return n == 0 ? null : t / n;
}

/// `C.moneyOu(v, mention, withCurrency)` : le montant, ou [mention] (« Non renseigné », « Non calculable ») quand la valeur est inconnue.
String moneyOu(Object? v, [String mention = 'Non renseigné', bool avecDevise = true]) => nombreOuNul(v) == null ? mention : money(v, avecDevise: avecDevise);

/// `C.num(v, dec)`.
String nombre(Object? v, [int? decimales]) =>
    grouperMilliers(toFixedJs(nombreOuZero(v), decimales ?? 0));

/// `C.pct(v, dec)` — une décimale par défaut.
String pourcent(Object? v, [int? decimales]) =>
    '${nombre(v, decimales ?? 1)}\u00A0%';

const _unites = [
  'zéro',
  'un',
  'deux',
  'trois',
  'quatre',
  'cinq',
  'six',
  'sept',
  'huit',
  'neuf',
  'dix',
  'onze',
  'douze',
  'treize',
  'quatorze',
  'quinze',
  'seize',
];
const _dizaines = [
  '',
  '',
  'vingt',
  'trente',
  'quarante',
  'cinquante',
  'soixante',
  'soixante',
  'quatre-vingt',
  'quatre-vingt',
];

String _centaine(int n) {
  if (n < 17) return _unites[n];
  if (n < 20) return 'dix-${_unites[n - 10]}';
  if (n < 100) {
    final d = n ~/ 10;
    var u = n % 10;
    final base = _dizaines[d];
    if (d == 7 || d == 9) u += 10;
    if (u == 0) return d == 8 ? '${base}s' : base;
    if (u == 1 && d != 8 && d != 7 && d != 9) return '$base et un';
    if (u == 11 && d == 7) return '$base et onze';
    return '$base-${u < 17 ? _unites[u] : 'dix-${_unites[u - 10]}'}';
  }
  final c = n ~/ 100;
  final r = n % 100;
  final tete = c == 1 ? 'cent' : '${_unites[c]} cent';
  if (r == 0) return c == 1 ? 'cent' : '${tete}s';
  return '$tete ${_centaine(r)}';
}

/// `C.nombreEnLettres(n)` — accords français : « quatre-vingts » et « cents » prennent un s en fin de nombre.
String nombreEnLettres(Object? v) {
  var n = arrondiJs(nombreOuZero(v).abs()).toInt();
  if (n == 0) return 'zéro';
  final mots = <String>[];
  for (final t in const [
    (1000000000, 'milliard', 'milliards'),
    (1000000, 'million', 'millions'),
    (1000, 'mille', 'mille'),
  ]) {
    final q = n ~/ t.$1;
    if (q == 0) continue;
    n -= q * t.$1;
    if (t.$1 == 1000 && q == 1) {
      mots.add('mille');
    } else {
      mots.add('${_centaine(q)} ${q > 1 ? t.$3 : t.$2}');
    }
  }
  if (n > 0) mots.add(_centaine(n));
  return mots.join(' ');
}

/// `C.montantEnLettres(v)` — mention légale des factures normalisées.
String montantEnLettres(Object? v) => '${nombreEnLettres(v)} francs CFA';

const _mois = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];
const _jours = [
  'dimanche',
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi'
];

String _pad(int n, [int largeur = 2]) => n.toString().padLeft(largeur, '0');

/// `C.dateFR` — 16/08/2026.
String dateFR(DateTime d) => '${_pad(d.day)}/${_pad(d.month)}/${d.year}';

/// `C.dateLong` — 16 août 2026.
String dateLong(DateTime d) => '${d.day} ${_mois[d.month - 1]} ${d.year}';

/// `C.dateJour` — dimanche 16 août 2026 (JS : dimanche = 0).
String dateJour(DateTime d) =>
    '${_jours[d.weekday % 7]} ${d.day} ${_mois[d.month - 1]} ${d.year}';

/// `C.heure` — 09h05.
String heure(DateTime d) => '${_pad(d.hour)}h${_pad(d.minute)}';

/// `C.dateHeure` — 16/08/2026 à 09h05.
String dateHeure(DateTime d) => '${dateFR(d)} à ${heure(d)}';

/// `C.iso` — 2026-08-16.
String iso(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)}';

/// `C.moisAnnee` — août 2026.
String moisAnnee(DateTime d) => '${_mois[d.month - 1]} ${d.year}';
