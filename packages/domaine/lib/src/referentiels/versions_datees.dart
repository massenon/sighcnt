/// UNE DONNÉE DE RÉFÉRENCE QUI CHANGE ALORS QUE DES PIÈCES ONT ÉTÉ ÉMISES SOUS L'ANCIENNE SE VERSIONNE PAR DATE, JAMAIS ÉCRASÉE.
///
/// C'est le mécanisme de la grille des primes (`grillePrimes` / `historiquePrimes`), des plages par lot de réactif, des couvertures d'assurance,
/// et depuis le 06/11/2026 de l'identité légale et des obligations fiscales. La fiche COURANTE porte sa date d'effet (`dateEffet`, `null` =
/// « depuis l'ouverture ») ; chaque version antérieure est COPIÉE dans un historique avec sa date de fin (`dateFin`, la veille de la version qui
/// l'a remplacée). Lire « la version en vigueur à une date » est donc une seule règle, écrite ici une fois (`data.js : versionEnVigueur`).
library;

/// La date au jour, en ISO (`AAAA-MM-JJ`) : un [DateTime] (sa date locale) ou une chaîne ISO dont on garde les dix premiers caractères.
String isoJour(Object? d) {
  if (d == null) return '';
  if (d is DateTime) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
  final s = '$d';
  return s.length > 10 ? s.substring(0, 10) : s;
}

/// La veille d'une date ISO, en ISO (`C.addDays(d, -1)`).
String veilleIso(Object? d) {
  final s = isoJour(d);
  final x = DateTime.parse(s);
  return isoJour(DateTime(x.year, x.month, x.day - 1));
}

/// La version d'une fiche (courante ou historique) en vigueur à [dateIso] : la COURANTE si sa date d'effet est nulle ou passée, sinon la version
/// de l'historique qui couvre la date (`dateEffet <= d <= dateFin`, bornes nulles ouvertes), la plus récente d'abord ; `null` si rien ne couvre
/// (obligation créée plus tard, ou retirée avant).
Map<String, Object?>? versionEnVigueur(Map<String, Object?>? courante, Iterable<Map<String, Object?>> historique, String dateIso) {
  final d = isoJour(dateIso);
  final effet = courante?['dateEffet'];
  if (courante != null && (effet == null || d.compareTo(isoJour(effet)) >= 0)) return courante;
  final couvrantes = [
    for (final h in historique)
      if ((h['dateEffet'] == null || d.compareTo(isoJour(h['dateEffet'])) >= 0) && (h['dateFin'] == null || d.compareTo(isoJour(h['dateFin'])) <= 0)) h
  ]..sort((a, b) => isoJour(b['dateEffet']).compareTo(isoJour(a['dateEffet'])));
  return couvrantes.isEmpty ? null : couvrantes.first;
}
