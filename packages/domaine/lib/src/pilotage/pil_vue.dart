/// PILOTAGE (PIL) — briques communes des treize écrans de statistiques et de tableaux de bord de la Direction (`dashboards.js`, vagues 9, 46, 53, 60, 64).
///
/// TOUT est CALCULÉ depuis les registres, rien n'est fourni, et chaque proxy ou proposition SE DIT. Les fonctions `pil*` du domaine reçoivent des fiches
/// ACTIVES (non archivées) et rendent une [PilVue] : les indicateurs, les graphiques, les classements et les tableaux tels que la maquette les
/// dessine — c'est cette vue que les vecteurs (`test/vecteurs/pilotage.json`, tirés de l'écran réel piloté dans Chrome) comparent, et c'est elle que
/// l'écran Flutter peint, sans rien recalculer.
library;

import '../format/format_fr.dart';
import '../format/js.dart';

typedef PilFiche = Map<String, Object?>;

/// Un indicateur : libellé, valeur formatée, indice facultatif (le « hint » de la maquette).
class PilKpi {
  const PilKpi(this.libelle, this.valeur, {this.indice, this.ton = 'neutre'});
  final String libelle, valeur;
  final String? indice;

  /// `navy` · `succes` · `info` · `attention` · `danger` · `neutre`.
  final String ton;
  @override
  String toString() => '$libelle=$valeur';
}

class PilSerie {
  const PilSerie(this.libelle, this.donnees);
  final String libelle;
  final List<num> donnees;
}

/// Un graphique : `barres`, `ligne` ou `anneau` (une seule série de valeurs pour l'anneau).
class PilGraphique {
  const PilGraphique(this.type, this.etiquettes, this.series, {this.horizontal = false, this.titre});
  final String type;
  final List<String> etiquettes;
  final List<PilSerie> series;
  final bool horizontal;
  final String? titre;
}

class PilTable {
  const PilTable(this.titre, this.entetes, this.lignes);
  final String? titre;
  final List<String> entetes;
  final List<List<String>> lignes;
}

/// `K.ranking` : libellé → valeur, du plus grand au plus petit.
class PilClassement {
  const PilClassement(this.items);
  final List<(String, num)> items;
}

class PilVue {
  PilVue({
    List<PilKpi>? kpis,
    List<PilGraphique>? graphiques,
    List<PilClassement>? classements,
    List<PilTable>? tables,
    List<String>? notes,
  })  : kpis = kpis ?? [],
        graphiques = graphiques ?? [],
        classements = classements ?? [],
        tables = tables ?? [],
        notes = notes ?? [];
  final List<PilKpi> kpis;
  final List<PilGraphique> graphiques;
  final List<PilClassement> classements;
  final List<PilTable> tables;
  final List<String> notes;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// Briques JavaScript reprises à l'identique
// ---------------------------------------------------------------------------------------------------------------------------------------------------

double pilN(Object? v) => nombreOuZero(v);

/// `!!v` de JavaScript.
bool pilVrai(Object? v) => !(v == null || v == false || v == '' || (v is num && (v == 0 || v.isNaN)));

/// `String(d || '').slice(0, 10)`.
String pilJour(Object? d) {
  final s = pilVrai(d) ? '$d' : '';
  return s.length > 10 ? s.substring(0, 10) : s;
}

/// `String(d || '').slice(0, 7)`.
String pilMois(Object? d) {
  final s = pilVrai(d) ? '$d' : '';
  return s.length > 7 ? s.substring(0, 7) : s;
}

/// La plage « du / au » des écrans de statistiques : une borne vide est ouverte.
bool pilDansPlage(Object? d, String du, String au) {
  final x = pilJour(d);
  if (du.isNotEmpty && x.compareTo(du) < 0) return false;
  if (au.isNotEmpty && x.compareTo(au) > 0) return false;
  return true;
}

/// `String(v)` d'une clé de regroupement : une valeur absente donne la clé « undefined », comme `acc[undefined]` de `C.groupBy`.
String pilCle(Object? v) => v == null ? 'undefined' : '$v';

/// `C.groupBy(rows, key)` : l'ordre d'insertion des clés est celui de la collection.
Map<String, List<T>> pilGrouper<T>(Iterable<T> l, String Function(T) cle) {
  final out = <String, List<T>>{};
  for (final x in l) {
    (out[cle(x)] ??= []).add(x);
  }
  return out;
}

/// `Array.prototype.sort` d'un tri décroissant `b.v − a.v` : STABLE (les ex æquo gardent l'ordre de la collection) — `List.sort` de Dart ne l'est pas.
List<T> pilTriDesc<T>(Iterable<T> l, num Function(T) v) {
  final c = [for (final (i, x) in l.indexed) (i, x)];
  c.sort((a, b) {
    final d = v(b.$2).compareTo(v(a.$2));
    return d != 0 ? d : a.$1.compareTo(b.$1);
  });
  return [for (final e in c) e.$2];
}

/// `Object.keys(o).sort()` : l'ordre des unités de code UTF-16, celui de `String.compareTo`.
List<String> pilClesTriees(Iterable<String> k) => k.toList()..sort();

/// Un nombre JavaScript écrit en texte (`7.6`, `8`, jamais `8.0`).
String pilTexteNombre(num v) {
  if (v is int) return '$v';
  if (v == v.truncateToDouble() && v.abs() < 1e15) return '${v.toInt()}';
  return '$v';
}

/// `C.pct(total ? n / total * 100 : 0)`.
String pilPctDe(num n, num total) => pourcent(total != 0 ? n / total * 100 : 0);

/// Somme d'un champ.
double pilSomme(Iterable<PilFiche> l, String k) => l.fold(0.0, (a, x) => a + pilN(x[k]));

/// `C.age(naissance)` : années révolues, jamais négatives ; `null` si la date manque.
int? pilAge(Object? naissance, DateTime maintenant) {
  if (!pilVrai(naissance)) return null;
  final d = DateTime.tryParse('$naissance');
  if (d == null) return null;
  final nais = d.isUtc ? d : DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second);
  final jours = arrondiJs(maintenant.toUtc().difference(nais).inMilliseconds / 86400000).toInt();
  final a = (jours / 365.25).floor();
  return a < 0 ? 0 : a;
}

/// `K.parMois(rows, cle, valeur, nb)` : somme (ou compte) par mois sur les `nb` derniers mois, le mois de référence en dernier. [ref] : la maquette
/// l'ancre EN DUR au 1ᵉʳ août 2026 (E20) ; le poste passe son horloge.
({List<String> etiquettes, List<num> valeurs}) pilParMois(Iterable<PilFiche> rows, String champDate,
    {String? champValeur, int nb = 12, required DateTime ref}) {
  const noms = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
  final etiq = <String>[];
  for (var i = nb - 1; i >= 0; i--) {
    final d = DateTime(ref.year, ref.month - i, 1);
    final m = noms[d.month - 1];
    etiq.add('${m.substring(0, m.length < 4 ? m.length : 4)}. ${(d.year % 100).toString().padLeft(2, '0')}');
  }
  final b = List<num>.filled(nb, 0);
  for (final r in rows) {
    final d = DateTime.tryParse('${r[champDate]}');
    if (d == null) continue;
    final idx = nb - 1 - ((ref.year - d.year) * 12 + (ref.month - d.month));
    if (idx >= 0 && idx < nb) b[idx] += champValeur != null ? pilN(r[champValeur]) : 1;
  }
  return (etiquettes: etiq, valeurs: b);
}
