/// Accueil M2 — agenda, rendez-vous, files d'attente : les briques communes (dates à la manière de JavaScript, références, indicateurs).
///
/// Source : `prototype_html/assets/js/modules/m2-consultations.js` ; vecteurs : `test/vecteurs/ag_agenda.json`, engendrés en PILOTANT les écrans réels
/// dans Chrome à une horloge figée (16/08/2026 12:00, fuseau UTC). Les jours se lisent à l'heure LOCALE du poste, comme `C.iso` côté navigateur.
library;

import '../format/format_fr.dart';
import '../referentiels/regles.dart' show joursEntre;

typedef AgFiche = Map<String, Object?>;

/// Un indicateur de tête d'écran (`U.kpiGrid`) : libellé, valeur déjà formatée, indice facultatif.
class AgKpi {
  const AgKpi(this.libelle, this.valeur, {this.indice});
  final String libelle;
  final String valeur;
  final String? indice;
}

bool agVrai(Object? v) => v != null && v != '' && v != 0 && v != false;

final _dateSeule = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// `new Date(v)` : une date SEULE vaut minuit UTC, une date-heure sans fuseau se lit à l'heure locale, un instant avec fuseau est cet instant.
/// Une valeur illisible rend `null` (le « Invalid Date » de JavaScript).
DateTime? agDate(Object? v) {
  if (v is DateTime) return v.isUtc ? v.toLocal() : v;
  if (v == null) return null;
  final t = '$v'.trim();
  if (t.isEmpty) return null;
  final d = _dateSeule.hasMatch(t)
      ? DateTime.tryParse('${t}T00:00:00Z')
      : DateTime.tryParse(t);
  if (d == null) return null;
  return d.isUtc ? d.toLocal() : d;
}

/// `C.iso(d)` : le jour LOCAL de l'instant ; « NaN-NaN-NaN » pour une date illisible (comparable comme chaîne, comme en JavaScript).
String agJour(Object? v) {
  final d = agDate(v);
  return d == null ? 'NaN-NaN-NaN' : iso(d);
}

/// `String(v || '').slice(0, n)` : le début BRUT du texte d'une date (le jour UTC d'un instant ISO, pas le jour local).
String agDebutTexte(Object? v, int n) {
  final t = agVrai(v) ? '$v' : '';
  return t.length > n ? t.substring(0, n) : t;
}

/// `C.daysBetween(a, b)` : écart arrondi en jours ; `null` si l'une des dates est illisible.
int? agJoursEntre(Object? a, Object? b) {
  final x = agDate(a), y = agDate(b);
  if (x == null || y == null) return null;
  return joursEntre(x, y);
}

/// `C.isoLocal(d)` : la valeur d'un champ date-heure locale (« 2026-08-16T09:00 ») ; un instant ISO avec fuseau s'y relit à l'heure locale (E328).
String agIsoLocal(Object? v) {
  final d = agDate(v);
  if (d == null) return '';
  String p(int n) => n.toString().padLeft(2, '0');
  return '${iso(d)}T${p(d.hour)}:${p(d.minute)}';
}

/// `new Date().toISOString()` : l'instant en UTC, millisecondes et « Z ».
String agInstant(DateTime d) => DateTime.fromMillisecondsSinceEpoch(
        d.millisecondsSinceEpoch,
        isUtc: true)
    .toIso8601String();

/// `C.referenceSuivante(prefixe, largeur, fiches)` : le plus grand rang déjà écrit pour ce préfixe (fiches archivées comprises), plus un.
String agReferenceSuivante(
    String prefixe, int largeur, Iterable<AgFiche> fiches) {
  var max = 0;
  final entier = RegExp(r'^\s*[+-]?\d+');
  for (final f in fiches) {
    final r = agVrai(f['reference']) ? '${f['reference']}' : '';
    if (r.startsWith(prefixe)) {
      final m = entier.firstMatch(r.substring(prefixe.length));
      final n = m == null ? 0 : int.parse(m.group(0)!.trim());
      if (n > max) max = n;
    }
  }
  return '$prefixe${(max + 1).toString().padLeft(largeur, '0')}';
}

/// Tri STABLE par une clé texte (la comparaison de `String.prototype.localeCompare` sur des dates ISO se ramène à l'ordre des chaînes).
List<AgFiche> agTrierTexte(Iterable<AgFiche> lignes, String Function(AgFiche) cle,
    {bool descendant = false}) {
  final copie = [for (final (i, l) in lignes.indexed) (i, l)];
  copie.sort((a, b) {
    final c = cle(a.$2).compareTo(cle(b.$2)) * (descendant ? -1 : 1);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in copie) e.$2];
}

/// `JOURS[getDay()].slice(0, 3)` : « ven. » (les jours JS commencent le dimanche).
const _jours3 = ['dim', 'lun', 'mar', 'mer', 'jeu', 'ven', 'sam'];
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
  'décembre'
];

/// L'en-tête d'un jour de la grille : « ven. 14 » (la feuille de style le passe en majuscules).
String agEnteteJour(DateTime d) => '${_jours3[d.weekday % 7]}. ${d.day}';

/// Le mois d'un jour de la grille : « août ».
String agMoisJour(DateTime d) => _mois[d.month - 1];

/// `C.num(n)`.
String agNum(int n) => nombre(n);
