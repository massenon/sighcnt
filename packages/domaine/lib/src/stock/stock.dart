/// Règles chiffrées des écrans de stock du module M6 (`m6-stock.js`) : état du stock et seuils, valeur au CUMP, échéance de péremption (RG-05),
/// ordre de sortie FEFO, quantité « à commander », période des mouvements, transformation d'une fiche produit ou lot à l'enregistrement.
///
/// Source de vérité : la maquette, pilotée dans Chrome (`prototype_html/build/vecteurs-stock.js` → `test/vecteurs/stock.json`). Les règles vivent
/// dans les écrans de la maquette ; ce fichier les isole pour que le poste, le mobile et la mère les exécutent en UN exemplaire.
///
/// Trois écarts assumés avec la maquette, consignés dans `docs/architecture/ECARTS-MAQUETTE.md` (E17 à E19) :
///  - l'échéance se compte en jours CALENDAIRES (la maquette arrondit un écart en millisecondes : l'après-midi, un lot qui périme demain vaut « 0 j »)
///  - un seuil d'alerte NON FIXÉ n'est pas un seuil de zéro : l'article est signalé à part, et sa quantité « à commander » n'est pas calculable
///  - le statut d'un lot se recalcule à la date du jour (la maquette lit un statut figé à la saisie, alors que sa règle dit « recalculées en continu »)
library;

import '../format/js.dart';
import '../format/recherche.dart';
import 'referentiels_stock.dart';

/// Une fiche du magasin (produit, lot, mouvement).
typedef FicheStock = Map<String, Object?>;

/// RG-05 : préavis de péremption, en jours (paramétrable dans la configuration du module).
const int delaiPreavisPeremption = 90;

/// En deçà, l'échéance s'affiche en rouge (le lot doit être servi sans attendre).
const int delaiEcheanceUrgente = 30;

bool _faux(Object? v) =>
    v == null || v == '' || v == 0 || v == false || (v is double && v.isNaN);

/// Le seuil d'alerte est FIXÉ par la clinique, article par article : un seuil absent n'est pas un seuil de zéro.
bool seuilFixe(Object? seuil) {
  if (seuil == null || seuil == '') return false;
  if (seuil is num) return !seuil.isNaN;
  return double.tryParse('$seuil'.trim()) != null;
}

double _seuil(Object? s) => nombreOuZero(s);

/// `etatStock` : `rupture` (stock nul), `critique` (stock ≤ seuil), sinon `normal`. Sans seuil fixé, seule la rupture est signalée.
String etatStock(Object? stock, Object? seuil) {
  final q = nombreOuZero(stock);
  if (q == 0) return 'rupture';
  if (seuilFixe(seuil) && q <= _seuil(seuil)) return 'critique';
  return 'normal';
}

/// `stock <= seuilAlerte` : sous le seuil, rupture comprise. Sans seuil fixé : rupture seulement.
bool sousSeuil(Object? stock, Object? seuil) {
  final q = nombreOuZero(stock);
  return seuilFixe(seuil) ? q <= _seuil(seuil) : q == 0;
}

/// `stock <= seuilAlerte && stock > 0` : sous le seuil SANS être en rupture (KPI « Sous le seuil » du référentiel, onglet « Sous le seuil »).
bool sousSeuilHorsRupture(Object? stock, Object? seuil) =>
    nombreOuZero(stock) > 0 && sousSeuil(stock, seuil);

/// Quantité à commander pour revenir à deux fois le seuil : `max(2 × seuil − stock, 0)`. NON CALCULABLE (`null`) sans seuil fixé.
double? aCommander(Object? stock, Object? seuil) {
  if (!seuilFixe(seuil)) return null;
  final v = _seuil(seuil) * 2 - nombreOuZero(stock);
  return v > 0 ? v : 0;
}

/// `C.sum(rows, p => p[champ] * p.cump)` : valeur au CUMP d'une liste de produits (`champ` : `stock`, `stockGros` ou `stockDetail`).
double valeurStock(Iterable<FicheStock> produits, [String champ = 'stock']) =>
    produits.fold<double>(
        0,
        (a, p) =>
            a + nombreOuZero(nombreOuZero(p[champ]) * nombreOuZero(p['cump'])));

/// `C.sum(rows, champ)`.
double sommeChamp(Iterable<FicheStock> lignes, String champ) =>
    lignes.fold<double>(0, (a, p) => a + nombreOuZero(p[champ]));

/// `C.groupBy` : clés dans l'ordre de première apparition.
Map<String, List<FicheStock>> grouperPar(
    Iterable<FicheStock> lignes, String cle) {
  final g = <String, List<FicheStock>>{};
  for (final l in lignes) {
    (g['${l[cle]}'] ??= []).add(l);
  }
  return g;
}

/// Tri STABLE par une clé (les égalités gardent l'ordre de la collection, comme `Array.prototype.sort`) ; les valeurs absentes passent en dernier.
List<FicheStock> trierStable(
        Iterable<FicheStock> lignes, Object? Function(FicheStock) cle,
        {bool descendant = false}) =>
    trierPar(lignes.toList(), cle, descendant: descendant);

/// « Produits à réapprovisionner en priorité » : les produits sous le seuil, du plus bas stock au plus haut, dix au plus.
List<FicheStock> aReapprovisionner(Iterable<FicheStock> produits,
    {int limite = 10}) {
  final r = trierStable([
    for (final p in produits)
      if (sousSeuil(p['stock'], p['seuilAlerte'])) p
  ], (p) => nombreOuZero(p['stock']));
  return r.length > limite ? r.sublist(0, limite) : r;
}

/// Ceux dont le seuil n'a pas été fixé : ils sont signalés À PART, jamais comptés comme « seuil zéro ».
List<FicheStock> sansSeuilFixe(Iterable<FicheStock> produits) => [
      for (final p in produits)
        if (!seuilFixe(p['seuilAlerte'])) p
    ];

String libelleCategorie(Object? id) {
  for (final c in categoriesProduit) {
    if (c.id == id) return c.label;
  }
  return '${id ?? ''}';
}

/// `C.daysBetween(AUJ, date)` en jours CALENDAIRES (écart E17). `null` si la date est illisible.
int? joursAvantPeremption(DateTime auj, Object? datePeremption) {
  final d = DateTime.tryParse('$datePeremption'.trim());
  if (d == null) return null;
  final a = DateTime.utc(auj.year, auj.month, auj.day);
  final b = DateTime.utc(d.year, d.month, d.day);
  return b.difference(a).inDays;
}

/// Statut d'un lot : `perime` (échéance dépassée), `alerte` (dans le délai de préavis, y compris le jour même), `actif`.
String statutLot(int? jours, {int preavis = delaiPreavisPeremption}) {
  if (jours == null) return 'actif';
  if (jours < 0) return 'perime';
  if (jours <= preavis) return 'alerte';
  return 'actif';
}

/// Teinte d'une échéance : `danger` (périmé ou ≤ 30 j), `attention` (≤ 90 j), `neutre` au-delà.
String teinteEcheance(int? jours, {int preavis = delaiPreavisPeremption}) {
  if (jours == null) return 'neutre';
  if (jours < 0 || jours <= delaiEcheanceUrgente) return 'danger';
  if (jours <= preavis) return 'attention';
  return 'neutre';
}

/// Texte de la colonne « Échéance » du registre des lots : « Périmé depuis 10 j », « Dans 29 j », « 91 j ».
String texteEcheance(int? jours) {
  if (jours == null) return '—';
  if (jours < 0) return 'Périmé depuis ${jours.abs()} j';
  if (jours <= delaiPreavisPeremption) return 'Dans $jours j';
  return '$jours j';
}

/// Texte de la colonne « Échéance » de l'onglet « Péremptions » des alertes : « Périmé » ou « Dans N j ».
String texteEcheanceAlerte(int? jours) {
  if (jours == null) return '—';
  return jours < 0 ? 'Périmé' : 'Dans $jours j';
}

/// Texte de l'onglet « Lots (FEFO) » de la fiche produit : « Périmé », « Dans N j » (dans le préavis) ou « Valide ».
String texteEtatLotFiche(int? jours) {
  if (jours == null) return 'Valide';
  if (jours < 0) return 'Périmé';
  if (jours <= delaiPreavisPeremption) return 'Dans $jours j';
  return 'Valide';
}

/// Ordre de sortie FEFO (RG-05) : les lots qui ont encore de la quantité, du plus proche de la péremption au plus lointain ; à date égale, l'ordre
/// de la collection.
List<FicheStock> ordreFefo(Iterable<FicheStock> lots) => trierStable([
      for (final l in lots)
        if (nombreOuZero(l['quantiteRestante']) > 0) l
    ], (l) => l['datePeremption']);

/// Valeur perdue d'un lot périmé : quantité restante × CUMP du produit (0 si le produit est introuvable).
double valeurPerdue(FicheStock lot, Iterable<FicheStock> produits) {
  for (final p in produits) {
    if (p['id'] == lot['produitId']) {
      return nombreOuZero(
          nombreOuZero(lot['quantiteRestante']) * nombreOuZero(p['cump']));
    }
  }
  return 0;
}

/// Les mouvements d'un stock (`gros` ou `detail`) entre deux dates incluses (`AAAA-MM-JJ`, comparées comme des chaînes) : un mouvement qui ne porte
/// pas de type de stock figure dans les deux. Du plus récent au plus ancien (tri croissant stable PUIS inversé : à date égale, c'est l'ordre inverse
/// de la collection qui sort).
List<FicheStock> mouvementsDuStock(Iterable<FicheStock> mouvements,
    String typeStock, String? debut, String? fin) {
  final r = <FicheStock>[];
  for (final m in mouvements) {
    final d = '${m['date'] ?? ''}'.length >= 10
        ? '${m['date']}'.substring(0, 10)
        : '${m['date'] ?? ''}';
    final st = m['stockType'];
    if (!_faux(st) && st != typeStock) continue;
    if (!_faux(debut) && d.compareTo(debut!) < 0) continue;
    if (!_faux(fin) && d.compareTo(fin!) > 0) continue;
    r.add(m);
  }
  return trierStable(r, (m) => m['date']).reversed.toList();
}

/// Mouvements d'un mois civil (KPI « Mouvements du mois »).
int mouvementsDuMois(Iterable<FicheStock> mouvements, DateTime ref) {
  var n = 0;
  for (final m in mouvements) {
    final d = DateTime.tryParse('${m['date']}');
    if (d != null && d.month == ref.month && d.year == ref.year) n++;
  }
  return n;
}

/// Types de mouvement qui sont des pertes (graphique « Mouvements de stock », indicateur « Pertes et casses »).
const typesPerte = ['perte', 'casse', 'peremption'];

num? _nombreSaisi(Object? v) {
  if (v == null) return null;
  if (v is num) return v;
  final t = '$v'.trim();
  return t.isEmpty ? null : num.tryParse(t);
}

/// `transform` du référentiel produits : le stock total est la somme gros + détail, RG-02 (un médicament se vend au prix d'achat, sans marge),
/// le CUMP part du prix d'achat s'il n'est pas saisi. Les valeurs numériques saisies sous forme de texte sont converties.
FicheStock transformerProduit(Map<String, Object?> saisie) {
  final v = {...saisie};
  for (final k in const ['prixAchat', 'prixVente', 'cump', 'seuilAlerte']) {
    if (v.containsKey(k)) {
      final n = _nombreSaisi(v[k]);
      if (n == null) {
        v.remove(k);
      } else {
        v[k] = n;
      }
    }
  }
  final gros = nombreOuZero(v['stockGros']);
  final detail = nombreOuZero(v['stockDetail']);
  v['stockGros'] = _entier(gros);
  v['stockDetail'] = _entier(detail);
  v['stock'] = _entier(gros + detail);
  if (v['categorie'] == 'medicament' || _faux(v['prixVente'])) {
    v['prixVente'] = v['prixAchat'];
  }
  if (_faux(v['cump'])) v['cump'] = v['prixAchat'];
  return v;
}

Object _entier(double d) => d == d.truncateToDouble() ? d.toInt() : d;

/// `beforeSave` du référentiel produits : RG-03, le stock ne devient jamais négatif. Renvoie le motif du refus, ou `null`.
String? refuserProduit(Map<String, Object?> saisie) {
  if (_nombreSaisiOuZero(saisie['stockGros']) < 0 ||
      _nombreSaisiOuZero(saisie['stockDetail']) < 0) {
    return 'RG-03 — le stock ne peut pas devenir négatif.';
  }
  return null;
}

double _nombreSaisiOuZero(Object? v) {
  final n = _nombreSaisi(v);
  return n == null ? 0 : n.toDouble();
}

/// `transform` du registre des lots : le produit est libellé sur le lot, le statut se déduit de l'échéance.
FicheStock transformerLot(
    Map<String, Object?> saisie, DateTime auj, Iterable<FicheStock> produits) {
  final v = {...saisie};
  final q = _nombreSaisi(v['quantiteRestante']);
  if (q != null) v['quantiteRestante'] = q;
  for (final p in produits) {
    if (p['id'] == v['produitId']) {
      v['produit'] = p['designation'];
      break;
    }
  }
  v['statut'] = statutLot(joursAvantPeremption(auj, v['datePeremption']));
  return v;
}
