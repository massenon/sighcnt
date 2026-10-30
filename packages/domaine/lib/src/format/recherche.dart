/// Recherche et tri des tableaux, à l'identique de `C.matches` / `C.sortBy` / `exportCSV` de la maquette.
///
/// `C.norm` = NFD sans diacritiques, en minuscules ; on n'a pas `String.normalize` en Dart sans dépendance, donc la
/// table couvre les lettres accentuées du français et de l'alphabet latin étendu usuel au Bénin.
const _de = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿœæÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜÝŸŒÆ';
const _vers = 'aaaaaaceeeeiiiinooooouuuuyyoaAAAAAACEEEEIIIINOOOOOUUUUYYOA';

String normaliser(Object? s) {
  if (s == null) return '';
  final b = StringBuffer();
  for (final r in s.toString().runes) {
    final c = String.fromCharCode(r);
    final i = _de.indexOf(c);
    b.write(i >= 0 ? _vers[i] : c);
  }
  return b.toString().toLowerCase();
}

bool correspond(Object? botte, String aiguille) =>
    normaliser(botte).contains(normaliser(aiguille));

/// Rang d'un caractère à la manière d'ICU (`localeCompare(…, 'fr', {numeric: true})`) : ponctuation et symboles, puis chiffres, puis lettres.
int _rang(String c) {
  final u = c.codeUnitAt(0);
  if (u >= 0x30 && u <= 0x39) return 1;
  // Les apostrophes typographiques (‘ ’) sont de la ponctuation, pas des lettres : « N’TCHA » précède « NKOUÉ », comme avec l'apostrophe droite.
  final lettre = (u >= 0x61 && u <= 0x7a) || (u > 0x7f && u != 0x2018 && u != 0x2019);
  return lettre ? 2 : 0;
}

/// Ordre de la ponctuation dans la collation racine d'ICU : l'espace, puis « _ - , ; : ! ? . » et le reste.
const _ordrePonctuation = ' _-,;:!?.\'‘’"()[]{}@*/\\&#%`^+<=>|~\$';
int _cle(String c) {
  final r = _rang(c);
  if (r != 0) return r * 1000 + c.codeUnitAt(0);
  final k = _ordrePonctuation.indexOf(c);
  return k >= 0 ? k : 500 + c.codeUnitAt(0) % 400;
}

/// Comparaison « naturelle » française : les suites de chiffres se comparent comme nombres, le reste sans accents ni casse,
/// et `CNT/1/25` précède `CNT900/25` (la ponctuation passe avant les chiffres, comme dans `Intl`).
int comparerNaturel(Object? a, Object? b) {
  final x = normaliser(a), y = normaliser(b);
  var i = 0, j = 0;
  while (i < x.length && j < y.length) {
    final p = x[i], q = y[j];
    final pn = _rang(p) == 1, qn = _rang(q) == 1;
    if (pn && qn) {
      var ie = i, je = j;
      while (ie < x.length && _rang(x[ie]) == 1) {
        ie++;
      }
      while (je < y.length && _rang(y[je]) == 1) {
        je++;
      }
      final c = BigInt.parse(x.substring(i, ie)).compareTo(BigInt.parse(y.substring(j, je)));
      if (c != 0) return c;
      i = ie;
      j = je;
      continue;
    }
    if (p != q) return _cle(p).compareTo(_cle(q));
    i++;
    j++;
  }
  final reste = (x.length - i).compareTo(y.length - j);
  if (reste != 0) return reste;
  // Égalité à la casse près : la minuscule précède la majuscule (« a1 » avant « A1 »).
  final sa = a.toString(), sb = b.toString();
  for (var k = 0; k < sa.length && k < sb.length; k++) {
    if (sa[k] != sb[k]) {
      final minA = sa[k] == sa[k].toLowerCase();
      final minB = sb[k] == sb[k].toLowerCase();
      if (minA != minB) return minA ? -1 : 1;
    }
  }
  return 0;
}

/// `C.sortBy` : les valeurs absentes passent en dernier, les nombres se comparent entre eux.
List<T> trierPar<T>(List<T> lignes, Object? Function(T) cle,
    {bool descendant = false}) {
  final d = descendant ? -1 : 1;
  final copie = [...lignes];
  copie.sort((a, b) {
    final x = cle(a), y = cle(b);
    if (x == null) return 1;
    if (y == null) return -1;
    if (x is num && y is num) return (x - y).sign.toInt() * d;
    return comparerNaturel(x, y) * d;
  });
  return copie;
}

/// Export CSV d'Excel FR : séparateur « ; », BOM, champs entre guillemets, fin de ligne CRLF.
String exporterCsv(List<String> entetes, List<List<Object?>> lignes) {
  String q(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
  return '﻿${[
    entetes.map(q).join(';'),
    ...lignes.map((l) => l.map(q).join(';')),
  ].join('\r\n')}';
}
