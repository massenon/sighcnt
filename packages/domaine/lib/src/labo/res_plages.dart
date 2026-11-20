/// LES PLAGES PAR LOT DE RÉACTIF ET L'ÉCART À LA RÉFÉRENCE — port de `plagePour`, `variableALaDate`, `referenceALaDate` (m5-laboratoire.js),
/// `L.ecart` et `L.libelleReference` (data-labo.js). Vecteurs : `test/vecteurs/resultats.json` (sections `plages`).
///
/// « Les paramètres d'examen sont modifiables selon le réactif. » Les bornes de la variable valent pour le réactif en service ; un changement
/// de lot peut les déplacer. La plage est VERSIONNÉE comme la grille des primes : elle porte sa date d'entrée en service, et un résultat se
/// compare aux bornes du lot EN SERVICE À SA DATE — une borne relevée au changement de réactif ne change pas un résultat déjà rendu.
/// Sans plage enregistrée, la borne de la variable fait foi. AUCUNE plage n'est pré-remplie : aucun document n'en fournit.
library;

import '../format/format_fr.dart';
import 'res_habilitations.dart';

/// Les types qui accompagnent un résultat sans en être un (réactif, lot, expiration, commentaire) : ils ne s'écartent jamais d'une référence.
const typesAccompagnement = ['reactif', 'lot', 'expiration', 'commentaire'];

const _typesChoix = ['binaire', 'ternaire', 'liste', 'titre'];

/// `Number(v)` : `null` quand le résultat est NaN.
double? _nombreJs(Object? v) {
  if (v is num) return v.toDouble();
  if (v is bool) return v ? 1 : 0;
  if (v == null) return 0;
  if (v is String) {
    final t = v.trim();
    if (t.isEmpty) return 0;
    return double.tryParse(t);
  }
  return null;
}

/// `String(v)` côté JavaScript : un entier s'écrit sans « .0 ».
String chaineJs(Object? v) {
  if (v == null) return 'null';
  if (v is double && v.isFinite && v == v.truncateToDouble()) {
    return v.toInt().toString();
  }
  return '$v';
}

/// `L.ecart(variable, valeur)` → `bas` | `haut` | `anormal` | `null` (normal, ou pas de référence).
String? ecart(FicheLabo? variable, Object? valeur) {
  if (variable == null || valeur == null || valeur == '') return null;
  final type = variable['type'];
  if (typesAccompagnement.contains(type)) return null;
  if (_typesChoix.contains(type)) {
    final normal = variable['normal'];
    if (normal == null || normal == '') return null;
    return chaineJs(valeur) == chaineJs(normal) ? null : 'anormal';
  }
  if (type == 'texte') return null;
  final n = _nombreJs(valeur);
  if (n == null || n.isNaN) return null;
  final min = variable['min'], max = variable['max'];
  if (min != null && n < (min as num)) return 'bas';
  if (max != null && n > (max as num)) return 'haut';
  return null;
}

/// `L.libelleReference(variable)` : « 4 - 8 », « < 6 », « > 0.35 » — la notation du document, pas une autre.
String libelleReference(FicheLabo? variable) {
  if (variable == null) return '';
  final regle = variable['regle'];
  if (regle != null && regle != '') return '$regle';
  final type = variable['type'];
  if (typesAccompagnement.contains(type)) return '';
  if (_typesChoix.contains(type)) {
    final normal = variable['normal'];
    return normal != null && normal != '' ? 'Attendu : $normal' : '';
  }
  if (type == 'texte') return '';
  final min = variable['min'], max = variable['max'];
  if (min != null && max != null) return '${chaineJs(min)} - ${chaineJs(max)}';
  if (max != null) return '< ${chaineJs(max)}';
  if (min != null) return '> ${chaineJs(min)}';
  return '';
}

/// `plagePour(variable, date)` : la plage EN SERVICE à la date (la dernière dont l'entrée est antérieure ou égale), ou `null`.
/// [plagesActives] : les fiches `plagesReactif` NON archivées. Une date vide retombe sur [aujourdhui].
FicheLabo? plagePour(FicheLabo variable, Iterable<FicheLabo> plagesActives, Object? date,
    {required DateTime aujourdhui}) {
  final brut = date == null ? '' : '$date';
  final d = brut.isEmpty ? iso(aujourdhui) : (brut.length > 10 ? brut.substring(0, 10) : brut);
  final cands = [
    for (final p in plagesActives)
      if (p['variableId'] == variable['id'] &&
          (p['dateDebut'] == null || p['dateDebut'] == '' || '${p['dateDebut']}'.compareTo(d) <= 0))
        p
  ];
  // Tri STABLE sur la date d'entrée (absente = depuis toujours) : en cas d'égalité, la dernière rencontrée l'emporte.
  final ordre = [for (var i = 0; i < cands.length; i++) (i, cands[i])]
    ..sort((a, b) {
      final c = '${a.$2['dateDebut'] ?? ''}'.compareTo('${b.$2['dateDebut'] ?? ''}');
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  return ordre.isEmpty ? null : ordre.last.$2;
}

/// `variableALaDate(v, date)` : la variable, ses bornes remplacées par celles du lot en service à la date.
FicheLabo variableALaDate(FicheLabo v, Iterable<FicheLabo> plagesActives, Object? date,
    {required DateTime aujourdhui}) {
  final p = plagePour(v, plagesActives, date, aujourdhui: aujourdhui);
  return p == null ? v : {...v, 'min': p['min'], 'max': p['max']};
}

/// `referenceALaDate(v, date)` : « 5 - 7 — lot LOT-B ».
String referenceALaDate(FicheLabo v, Iterable<FicheLabo> plagesActives, Object? date,
    {required DateTime aujourdhui}) {
  final p = plagePour(v, plagesActives, date, aujourdhui: aujourdhui);
  final lib = libelleReference(p == null ? v : {...v, 'min': p['min'], 'max': p['max']});
  return p != null && lib.isNotEmpty ? '$lib — lot ${p['lot']}' : lib;
}
