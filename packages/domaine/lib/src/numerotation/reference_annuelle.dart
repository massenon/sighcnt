/// LA FABRIQUE UNIQUE DES NUMÉROS ANNUELS (lot MIL, 16/11/2026), port de `C.referenceAnnuelle` et `C.anneeDePiece` de la maquette (`core.js`).
///
/// L'ANNÉE d'un numéro (`BEB-2027-0001`) est celle de la DATE DE LA PIÈCE, jamais une constante ; sans date lisible, l'année de l'horloge [maintenant]
/// (l'horloge est donnée, jamais lue ici : un test pose la sienne). Le rang suivant est LU sur les fiches existantes de CETTE année (archivées
/// comprises) : le compteur repart à 1 chaque année, et une pièce d'un exercice passé garde la série de son exercice. Un numéro émis ne se réécrit
/// jamais : l'appelant ne l'invoque qu'à la création.
library;

/// L'année d'une date de pièce : « 2027-01-01 », « 2026-12-31T23:59 » ou un [DateTime] ; à défaut, l'année de [maintenant].
int anneeDePiece(Object? date, DateTime maintenant) {
  if (date is DateTime) return date.year;
  final m = RegExp(r'^(\d{4})-\d{2}-\d{2}').firstMatch('${date ?? ''}');
  if (m != null) return int.parse(m.group(1)!);
  final d = DateTime.tryParse('${date ?? ''}');
  return d?.year ?? maintenant.year;
}

/// `préfixe` + année de la pièce + `-` + rang suivant sur [largeur] chiffres, lu dans [champ] (`reference` par défaut) des [fiches].
String referenceAnnuelle(String prefixe, Object? date, int largeur, Iterable<Map<String, Object?>> fiches,
    {required DateTime maintenant, String champ = 'reference'}) {
  final p = '$prefixe${anneeDePiece(date, maintenant)}-';
  var max = 0;
  for (final f in fiches) {
    final r = '${f[champ] ?? ''}';
    if (r.startsWith(p)) {
      final n = int.tryParse(RegExp(r'^\s*[+-]?\d+').firstMatch(r.substring(p.length))?.group(0) ?? '') ?? 0;
      if (n > max) max = n;
    }
  }
  return '$p${(max + 1).toString().padLeft(largeur, '0')}';
}
