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

bool correspond(Object? botte, String aiguille) => normaliser(botte).contains(normaliser(aiguille));

/// Comparaison « naturelle » française : les nombres se comparent comme nombres, le reste sans accents ni casse.
int comparerNaturel(Object? a, Object? b) {
  final x = normaliser(a), y = normaliser(b);
  final re = RegExp(r'(\d+)|(\D+)');
  final xs = re.allMatches(x).map((m) => m[0]!).toList();
  final ys = re.allMatches(y).map((m) => m[0]!).toList();
  for (var i = 0; i < xs.length && i < ys.length; i++) {
    final p = xs[i], q = ys[i];
    final pn = int.tryParse(p), qn = int.tryParse(q);
    final c = (pn != null && qn != null) ? pn.compareTo(qn) : p.compareTo(q);
    if (c != 0) return c;
  }
  return xs.length.compareTo(ys.length);
}

/// `C.sortBy` : les valeurs absentes passent en dernier, les nombres se comparent entre eux.
List<T> trierPar<T>(List<T> lignes, Object? Function(T) cle, {bool descendant = false}) {
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
