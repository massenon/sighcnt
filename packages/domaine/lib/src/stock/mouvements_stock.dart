/// MOUVEMENTS DE STOCK (M6) — transferts gros → détail multi-lignes, mouvements saisis, feuille d'inventaire, pertes.
/// Port de `prototype_html/assets/js/modules/m6-stock.js` (écrans `m6-transferts`, `m6-mouvements`, `m6-inventaire-feuille`, `m6-pertes`).
///
/// Ces règles vivent, dans la maquette, dans la FERMETURE des écrans : elles ont donc été relevées en PILOTANT les écrans réels dans Chrome
/// (`prototype_html/build/vecteurs-stock-mouvements.js` → `test/vecteurs/stock_mouvements.json`), et rejouées ici. Les fonctions reçoivent les
/// fiches EN ARGUMENT (produits, lots, bons, mouvements déjà écrits) et RENVOIENT ce qu'il faut écrire : l'écran Flutter écrit au magasin, la
/// mère ou le mobile appellent la même règle avec ce qu'ils ont.
///
/// Invariants tenus ici :
///  - RG-03 : le stock du magasin ne devient jamais négatif ; le refus NOMME l'article. Le disponible tient compte de ce qui est DÉJÀ posé sur le
///    bon. Un transfert écrit DEUX mouvements symétriques par ligne (sortie du magasin, entrée à la pharmacie), justifiés par le numéro du bon.
///  - L'annulation d'un transfert restitue TOUTES les lignes (c'est l'écran qui garde les états d'avant : voir [TransfertEmis.avant]).
///  - Une feuille d'inventaire porte sur UN MAGASIN NOMMÉ (gros ou détail, jamais le total des deux) : le théorique, l'écart et la régularisation
///    ne concernent que lui.
///  - Une perte s'enregistre comme un MOUVEMENT de stock, valorisé au CUMP, refusée si elle dépasse le stock.
///
/// Écarts de la maquette corrigés AVANT le portage (docs/architecture/ECARTS-MAQUETTE.md, E17-E19) : séries de références lues sur les fiches
/// existantes (et non sur un compteur de page), libellé de nature des pertes, numéro conservé à l'édition d'un mouvement.
library;

import '../format/format_fr.dart';
import '../format/js.dart';
import '../format/recherche.dart' show trierPar;

typedef FicheStock = Map<String, Object?>;

/// Refus NOMMÉ : un refus se lit, il ne se devine pas. Rien n'est écrit. [detail] : la seconde ligne du message (pertes).
class RefusStock implements Exception {
  const RefusStock(this.motif, {this.detail});
  final String motif;
  final String? detail;
  @override
  String toString() => motif;
}

double _n(Object? v) => nombreOuZero(v);

/// Écriture d'un nombre comme le fait JavaScript (`'' + 11` → « 11 », `'' + 1.5` → « 1.5 »).
String _js(num v) => v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

// ============================================================================
// RÉFÉRENTIELS STATIQUES de la maquette (data.js) — des constantes, pas des collections.
// ============================================================================

/// `D.CATEGORIES_PRODUIT` : (identifiant, libellé).
const categoriesProduit = <(String, String)>[
  ('medicament', 'Médicaments'),
  ('reactif', 'Réactifs de laboratoire'),
  ('conso_labo', 'Consommables de laboratoire'),
  ('conso_medical', 'Consommables médicaux'),
  ('fourniture', 'Fournitures administratives'),
  ('entretien', 'Produits d’entretien'),
  ('petit_materiel', 'Petit matériel médical'),
  ('immobilisation', 'Immobilisations'),
];

String categorieLabel(Object? id) {
  for (final c in categoriesProduit) {
    if (c.$1 == id) return c.$2;
  }
  return '$id';
}

/// `D.TYPES_MOUVEMENT` : sens +1 (entrée), −1 (sortie), 0 (neutre) ; [ton] : le ton du badge.
class TypeMouvement {
  const TypeMouvement(this.id, this.libelle, this.sens, this.ton);
  final String id;
  final String libelle;
  final int sens;
  final String ton;
}

const typesMouvement = <TypeMouvement>[
  TypeMouvement('entree', 'Entrée', 1, 'success'),
  TypeMouvement('sortie', 'Sortie', -1, 'navy'),
  TypeMouvement('transfert', 'Transfert', 0, 'info'),
  TypeMouvement('perte', 'Perte', -1, 'danger'),
  TypeMouvement('casse', 'Casse / bris', -1, 'danger'),
  TypeMouvement('peremption', 'Péremption', -1, 'warning'),
  TypeMouvement('inventaire', 'Régularisation inventaire', 0, 'neutral'),
];

TypeMouvement? typeMouvement(Object? id) {
  for (final t in typesMouvement) {
    if (t.id == id) return t;
  }
  return null;
}

/// `D.TYPES_STOCK` : (identifiant, libellé). La maquette propose « laboratoire » à la saisie d'un mouvement alors qu'un article ne porte que
/// `stockGros` et `stockDetail` : le contrôle RG-03 retombe alors sur le stock détail (vecteur « stock laboratoire »).
const typesStock = <(String, String)>[
  ('gros', 'Stock gros (magasin central)'),
  ('detail', 'Stock détail (pharmacie d’urgence)'),
  ('labo', 'Stock laboratoire'),
];

FicheStock? _produitDe(Iterable<FicheStock> produits, Object? id) {
  for (final p in produits) {
    if (p['id'] == id) return p;
  }
  return null;
}

/// Plus grand rang d'une série de références (`PREFIXE` + chiffres), lu sur les fiches EXISTANTES — archivées comprises. Jamais un compteur de
/// page, qui repart à 1 à chaque chargement (écart E17, corrigé dans la maquette).
int rangMaxSerie(String prefixe, Iterable<FicheStock> fiches) {
  var max = 0;
  for (final f in fiches) {
    final r = '${f['reference'] ?? ''}';
    if (r.startsWith(prefixe)) {
      final k = int.tryParse(RegExp(r'^\d+').stringMatch(r.substring(prefixe.length)) ?? '') ?? 0;
      if (k > max) max = k;
    }
  }
  return max;
}

/// `C.referenceSuivante(prefixe, largeur, fiches)`.
String referenceSuivante(String prefixe, int largeur, Iterable<FicheStock> fiches) =>
    '$prefixe${(rangMaxSerie(prefixe, fiches) + 1).toString().padLeft(largeur, '0')}';

// ============================================================================
// TRANSFERT MULTI-LIGNES
// ============================================================================

/// Les lignes d'un bon — DEUX générations cohabitent : les bons émis avant le passage au multi-lignes ne portent qu'un produit, à plat sur
/// l'en-tête. On les ADAPTE à la lecture (les convertir en base réécrirait des pièces déjà signées).
List<FicheStock> lignesDeBon(FicheStock t) {
  final l = t['lignes'];
  if (l is List && l.isNotEmpty) {
    return [for (final x in l) (x as Map).cast<String, Object?>()];
  }
  return [
    {
      'produitId': t['produitId'],
      'produit': t['produit'],
      'unite': t['unite'],
      'quantite': t['quantite'],
      'cump': t['cump'],
    }
  ];
}

double valeurLigne(FicheStock l) => _n(l['quantite']) * _n(l['cump']);
double totalQuantite(Iterable<FicheStock> lg) => lg.fold(0.0, (n, l) => n + _n(l['quantite']));
double totalValeur(Iterable<FicheStock> lg) => lg.fold(0.0, (n, l) => n + valeurLigne(l));

/// Ce qui reste disponible au magasin pour un article, une fois déduit ce qui est DÉJÀ posé sur le bon en cours (hors la ligne [saufIndex]).
/// Sans cette déduction, on pourrait inscrire deux fois la totalité du stock sur le même bon.
double disponibleRestant(FicheStock? produit, List<FicheStock> lignes, Object? produitId, {int saufIndex = -1}) {
  if (produit == null) return 0;
  var pose = 0.0;
  for (var k = 0; k < lignes.length; k++) {
    if (lignes[k]['produitId'] == produitId && k != saufIndex) pose += _n(lignes[k]['quantite']);
  }
  return _n(produit['stockGros']) - pose;
}

/// « Ajouter » : ajoute [quantite] de [produitId] au bon. RG-03 ligne par ligne, en NOMMANT l'article. Le même article deux fois se CUMULE
/// (le magasinier compte des caisses, pas des lignes). Le lot FEFO (RG-05) et la famille voyagent avec la ligne. Rend les NOUVELLES lignes.
List<FicheStock> ajouterLigneTransfert({
  required List<FicheStock> lignes,
  required String? produitId,
  required Object? quantite,
  required List<FicheStock> produits,
  required List<FicheStock> lots,
}) {
  final qte = _n(quantite);
  if (produitId == null || produitId.isEmpty) throw const RefusStock('Choisir un article.');
  if (qte <= 0) throw const RefusStock('Indiquer une quantité supérieure à zéro.');
  final pr = _produitDe(produits, produitId);
  if (pr == null) throw const RefusStock('Choisir un article.');
  final reste = disponibleRestant(pr, lignes, produitId);
  if (qte > reste) {
    final gros = _n(pr['stockGros']);
    throw RefusStock('RG-03 — « ${pr['designation']} » : ${nombre(reste)} ${pr['unite']} encore disponible(s) au magasin'
        '${reste < gros ? ' (déjà ${nombre(gros - reste)} sur ce bon)' : ''}.');
  }
  final sortie = [for (final l in lignes) {...l}];
  final i = sortie.indexWhere((l) => l['produitId'] == produitId);
  if (i >= 0) {
    sortie[i]['quantite'] = _n(sortie[i]['quantite']) + qte;
    return sortie;
  }
  // Lot FEFO : le premier à périmer, hors périmé et hors épuisé (comparaison de chaînes ISO, comme la maquette).
  final candidats = [
    for (final x in lots)
      if (x['produitId'] == produitId && x['statut'] != 'perime' && _n(x['quantiteRestante']) > 0) x
  ]..sort((a, b) => '${a['datePeremption']}'.compareTo('${b['datePeremption']}'));
  final lot = candidats.isEmpty ? null : candidats.first;
  sortie.add({
    'produitId': produitId,
    'code': pr['code'],
    'produit': pr['designation'],
    'categorie': pr['categorie'],
    'unite': pr['unite'],
    'cump': pr['cump'],
    'quantite': qte,
    'lot': lot?['numeroLot'],
    'peremption': lot?['datePeremption'],
  });
  return sortie;
}

/// « Modifier la quantité » d'une ligne : contrôlée contre le disponible RESTANT, la ligne elle-même exclue.
List<FicheStock> modifierQuantiteLigne({
  required List<FicheStock> lignes,
  required int rang,
  required Object? quantite,
  required List<FicheStock> produits,
}) {
  final l = lignes[rang];
  final reste = disponibleRestant(_produitDe(produits, l['produitId']), lignes, l['produitId'], saufIndex: rang);
  final q = _n(quantite);
  if (q > reste) {
    throw RefusStock('RG-03 — « ${l['produit']} » : ${nombre(reste)} ${l['unite']} disponible(s) seulement.');
  }
  return [
    for (var k = 0; k < lignes.length; k++) k == rang ? {...lignes[k], 'quantite': q} : lignes[k]
  ];
}

/// Dernier contrôle RG-03 avant écriture : le stock a pu bouger pendant la saisie. Le refus nomme la ligne fautive (la DERNIÈRE, comme la maquette).
void controlerBonAvantEcriture(List<FicheStock> lignes, List<FicheStock> produits) {
  if (lignes.isEmpty) throw const RefusStock('Ajouter au moins un article au bon.');
  FicheStock? faute;
  for (final l in lignes) {
    final pr = _produitDe(produits, l['produitId']);
    if (pr == null || _n(l['quantite']) > _n(pr['stockGros'])) faute = l;
  }
  if (faute != null) {
    throw RefusStock('RG-03 — « ${faute['produit']} » : le stock du magasin ne couvre plus ${nombre(faute['quantite'])} ${faute['unite']}.');
  }
}

/// `TR-NNNNN` : le numéro suit le REGISTRE (plus grand rang existant + 1, archivés compris), pas un compteur de page.
String referenceTransfert(Iterable<FicheStock> bons) => referenceSuivante('TR-', 5, bons);

/// Ce qu'un transfert validé écrit.
class TransfertEmis {
  const TransfertEmis({required this.reference, required this.bon, required this.mouvements, required this.produits, required this.avant});

  final String reference;

  /// La fiche `transferts` à insérer.
  final FicheStock bon;

  /// Les mouvements, dans l'ORDRE D'ÉCRITURE : par ligne, la sortie du magasin PUIS l'entrée à la pharmacie.
  final List<FicheStock> mouvements;

  /// Pour chaque produit touché : l'identifiant et le correctif `{stockGros, stockDetail}` à appliquer.
  final List<({String id, FicheStock patch})> produits;

  /// L'état d'AVANT de chaque produit touché : l'annulation restitue TOUTES les lignes, un transfert partiellement annulé laisserait le stock faux.
  final List<({String id, FicheStock patch})> avant;
}

/// Valide un transfert (le contrôle de bon doit avoir été fait : [controlerBonAvantEcriture]).
TransfertEmis emettreTransfert({
  required String date,
  required String demandeur,
  required String motif,
  required List<FicheStock> lignes,
  required List<FicheStock> produits,
  required List<FicheStock> bons,
  required String utilisateur,
}) {
  final reference = referenceTransfert(bons);
  final mvts = <FicheStock>[];
  final maj = <({String id, FicheStock patch})>[];
  final avant = <({String id, FicheStock patch})>[];
  for (final l in lignes) {
    final pr = _produitDe(produits, l['produitId'])!;
    final q = _n(l['quantite']);
    avant.add((id: '${pr['id']}', patch: {'stockGros': pr['stockGros'], 'stockDetail': pr['stockDetail']}));
    maj.add((id: '${pr['id']}', patch: {'stockGros': _n(pr['stockGros']) - q, 'stockDetail': _n(pr['stockDetail']) + q}));
    // DEUX MOUVEMENTS SYMÉTRIQUES (RG-03) : le magasin débité, la pharmacie créditée.
    FicheStock mvt(String libelle, String stock) => {
          'reference': reference,
          'date': date,
          'produitId': pr['id'],
          'produit': pr['designation'],
          'type': 'transfert',
          'typeLabel': libelle,
          'quantite': q,
          'stockType': stock,
          'justificatif': 'Bon de transfert $reference',
          'utilisateur': utilisateur,
        };
    mvts.add(mvt('Transfert — sortie magasin', 'gros'));
    mvts.add(mvt('Transfert — entrée pharmacie', 'detail'));
  }
  final qtot = totalQuantite(lignes);
  final bon = <String, Object?>{
    'date': date,
    'demandeur': demandeur,
    'motif': motif,
    'reference': reference,
    'lignes': [for (final l in lignes) {...l}],
    'nbLignes': lignes.length,
    'quantiteTotale': qtot,
    'valeur': totalValeur(lignes),
    'operateur': utilisateur,
    'etat': 'receptionne',
    'dateReception': date,
    // Compatibilité avec les bons antérieurs, qui ne portaient qu'un produit : le registre lit ces champs.
    'produit': lignes.length == 1 ? lignes[0]['produit'] : '${lignes.length} articles',
    'unite': lignes.length == 1 ? lignes[0]['unite'] : '',
    'quantite': qtot,
  };
  return TransfertEmis(reference: reference, bon: bon, mouvements: mvts, produits: maj, avant: avant);
}

// ============================================================================
// MOUVEMENTS SAISIS (K.crud de m6-mouvements)
// ============================================================================

/// RG-03 à l'enregistrement d'un mouvement (création ET édition) : une sortie (sens négatif) ne dépasse pas le stock CONCERNÉ — `gros`, sinon le
/// stock détail. Rend le message de refus, ou `null`.
String? controleMouvement({
  required FicheStock? produit,
  required Object? type,
  required Object? stockType,
  required Object? quantite,
}) {
  final t = typeMouvement(type);
  if (produit != null && t != null && t.sens < 0) {
    final dispo = stockType == 'gros' ? _n(produit['stockGros']) : _n(produit['stockDetail']);
    final q = quantite is num ? quantite : (num.tryParse('$quantite') ?? 0);
    if (_n(q) > dispo) {
      return 'RG-03 — sortie de ${_js(q)} impossible : stock disponible de ${_js(dispo)} seulement.';
    }
  }
  return null;
}

/// `transform` du formulaire : le produit et le libellé du type sont recopiés, l'opérateur est l'agent connecté, et le numéro (`M` + 6 chiffres)
/// suit la série des mouvements existants. Un mouvement ÉDITÉ GARDE son numéro (écart E19, corrigé dans la maquette).
FicheStock preparerMouvement(
  Map<String, Object?> valeurs, {
  FicheStock? existant,
  required List<FicheStock> produits,
  required List<FicheStock> mouvements,
  required String utilisateur,
}) {
  final v = {...valeurs};
  final p = _produitDe(produits, v['produitId']);
  if (p != null) v['produit'] = p['designation'];
  final t = typeMouvement(v['type']);
  if (t != null) v['typeLabel'] = t.libelle;
  v['utilisateur'] = utilisateur;
  final ref = v['reference'];
  if (ref == null || ref == '') v['reference'] = existant?['reference'] ?? referenceSuivante('M', 6, mouvements);
  return v;
}

// ============================================================================
// FEUILLE D'INVENTAIRE
// ============================================================================

String magasinLabelInventaire(String magasin) =>
    magasin == 'detail' ? 'Stock détail (pharmacie d’urgence)' : 'Stock gros (magasin central)';

/// Le stock du magasin compté, jamais le total des deux.
double stockTheorique(FicheStock produit, String magasin) =>
    _n(magasin == 'detail' ? produit['stockDetail'] : produit['stockGros']);

/// Les articles du périmètre, triés par désignation. [perimetre] : « Tous les articles » ou le libellé d'une famille.
List<FicheStock> ciblesInventaire(List<FicheStock> produits, String perimetre) {
  final cible = perimetre == 'Tous les articles' ? produits : [for (final p in produits) if (categorieLabel(p['categorie']) == perimetre) p];
  return trierPar(cible, (p) => p['designation']);
}

/// Une ligne de la feuille : théorique, physique compté, écart, valeur (écart × CUMP).
FicheStock ligneComptage(FicheStock produit, String magasin, Object? physique) {
  final th = stockTheorique(produit, magasin);
  final phys = _n(physique);
  final e = phys - th;
  return {'produit': produit, 'theorique': th, 'physique': phys, 'ecart': e, 'valeur': e * _n(produit['cump'])};
}

/// Ce que valide une feuille d'inventaire.
class InventaireValide {
  const InventaireValide({required this.inventaire, required this.mouvements, required this.produits, required this.avant});

  /// La fiche `inventaires` à insérer.
  final FicheStock inventaire;

  /// Un mouvement de régularisation par écart (RG-03, justificatif = référence de l'inventaire), dans l'ordre d'écriture.
  final List<FicheStock> mouvements;

  /// Correctifs de stock par produit en écart : `stock` (total) et le stock du magasin compté — jamais sous zéro.
  final List<({String id, FicheStock patch})> produits;
  final List<({String id, FicheStock patch})> avant;
}

/// « Valider l'inventaire ». [physiques] : le stock compté par identifiant de produit (un article non saisi garde son théorique, écart nul).
InventaireValide validerInventaire({
  required Map<String, Object?> entete,
  required List<FicheStock> cible,
  required Map<String, Object?> physiques,
  required List<FicheStock> inventaires,
  required List<FicheStock> mouvements,
}) {
  final magasin = '${entete['magasin']}' == 'detail' ? 'detail' : 'gros';
  final label = magasinLabelInventaire(magasin);
  final vals = [for (final p in cible) ligneComptage(p, magasin, physiques.containsKey('${p['id']}') ? physiques['${p['id']}'] : stockTheorique(p, magasin))];
  final ecarts = [for (final x in vals) if (_n(x['ecart']) != 0) x];
  final valeurEcart = ecarts.fold(0.0, (n, x) => n + _n(x['valeur']));
  final inventaire = <String, Object?>{
    'reference': referenceSuivante('INV-', 4, inventaires),
    'date': entete['date'],
    'type': entete['type'],
    'perimetre': entete['perimetre'],
    'magasin': magasin,
    'magasinLabel': label,
    'operateur': entete['operateur'],
    'statutInv': 'valide',
    'nbArticles': vals.length,
    'nbEcarts': ecarts.length,
    'valeurEcart': valeurEcart,
    'lignes': [
      for (final x in vals)
        {
          'code': (x['produit'] as Map)['code'],
          'designation': (x['produit'] as Map)['designation'],
          'unite': (x['produit'] as Map)['unite'],
          'theorique': x['theorique'],
          'physique': x['physique'],
          'ecart': x['ecart'],
          'cump': (x['produit'] as Map)['cump'],
          'valeur': x['valeur'],
        }
    ],
  };
  final mvts = <FicheStock>[];
  final maj = <({String id, FicheStock patch})>[];
  final avant = <({String id, FicheStock patch})>[];
  for (final x in ecarts) {
    final pr = x['produit'] as FicheStock;
    final e = _n(x['ecart']);
    final cle = magasin == 'detail' ? 'stockDetail' : 'stockGros';
    avant.add((id: '${pr['id']}', patch: {'stockGros': pr['stockGros'], 'stockDetail': pr['stockDetail'], 'stock': pr['stock']}));
    // La régularisation porte sur le magasin compté, et le total qui en découle — jamais sous zéro.
    final patch = <String, Object?>{'stock': _max0(_n(pr['stock']) + e), cle: _max0(_n(pr[cle]) + e)};
    maj.add((id: '${pr['id']}', patch: patch));
    mvts.add({
      'reference': referenceSuivante('M', 6, [...mouvements, ...mvts]),
      'date': entete['date'],
      'produitId': pr['id'],
      'produit': pr['designation'],
      'type': 'inventaire',
      'typeLabel': 'Régularisation inventaire',
      'quantite': e.abs(),
      'stockType': magasin,
      'justificatif': 'Inventaire ${inventaire['reference']}',
      'utilisateur': entete['operateur'],
    });
  }
  return InventaireValide(inventaire: inventaire, mouvements: mvts, produits: maj, avant: avant);
}

double _max0(double v) => v < 0 ? 0 : v;

// ============================================================================
// PERTES, CASSES & REBUTS
// ============================================================================

/// La nature d'une perte, telle que la liste de la déclaration la propose : (identifiant, libellé).
const naturesPerte = <(String, String)>[
  ('casse', 'Casse ou bris'),
  ('peremption', 'Péremption'),
  ('perte', 'Perte ou disparition'),
];

/// Les mouvements qui sont des pertes (le registre des pertes les lit au même registre que les mouvements : elle n'existe qu'une fois).
bool estPerte(FicheStock m) => const ['perte', 'casse', 'peremption'].contains(m['type']);

/// Valeur d'une perte : celle que le mouvement porte, sinon quantité × CUMP du produit (mouvements antérieurs à la valorisation).
double valeurPerte(FicheStock m, List<FicheStock> produits) {
  if (m['valeur'] != null) return _n(m['valeur']);
  final p = _produitDe(produits, m['produitId']);
  return _n(m['quantite']) * (p == null ? 0 : _n(p['cump']));
}

class PerteDeclaree {
  const PerteDeclaree({required this.mouvement, required this.stockAvant, required this.stockApres, required this.valeur, required this.detail});
  final FicheStock mouvement;
  final double stockAvant;
  final double stockApres;
  final double valeur;

  /// La seconde ligne du message de succès.
  final String detail;
}

/// « Déclarer la perte » : RG-03 — le stock ne peut pas devenir négatif, le refus NOMME l'article. Le stock décroît d'autant (champ `stock`), la
/// perte est valorisée au CUMP. [mouvements] : tous ceux déjà écrits (la référence `MVT-NNNNN` suit leur série).
PerteDeclaree declarerPerte({
  required FicheStock produit,
  required String type,
  required Object? quantite,
  required String date,
  required String justificatif,
  required String constatePar,
  String? observation,
  required String utilisateur,
  required List<FicheStock> mouvements,
}) {
  final q = _n(quantite);
  final dispo = produit['stock'] != null ? _n(produit['stock']) : 0.0;
  if (q > dispo) {
    throw RefusStock('Perte supérieure au stock.',
        detail: '${produit['designation']} — ${nombre(dispo)} en stock, ${nombre(q)} déclaré(s). RG-03 : le stock ne peut pas devenir négatif.');
  }
  final valeur = q * _n(produit['cump']);
  final obs = (observation ?? '').isEmpty ? null : observation;
  final mvt = <String, Object?>{
    'reference': referenceSuivante('MVT-', 5, mouvements),
    'date': date,
    'type': type,
    'typeLabel': typeMouvement(type)?.libelle,
    'produitId': produit['id'],
    'produit': produit['designation'],
    'unite': produit['unite'],
    'quantite': q,
    'sens': 'sortie',
    'valeur': valeur,
    'cump': produit['cump'] ?? 0,
    'justificatif': justificatif,
    'constatePar': constatePar,
    'observation': obs,
    'utilisateur': utilisateur,
  };
  return PerteDeclaree(
    mouvement: mvt,
    stockAvant: dispo,
    stockApres: dispo - q,
    valeur: valeur,
    detail: '${produit['designation']} — ${nombre(q)} ${produit['unite'] ?? ''}, ${money(valeur)} au CUMP. Stock ramené à ${nombre(dispo - q)}.',
  );
}
