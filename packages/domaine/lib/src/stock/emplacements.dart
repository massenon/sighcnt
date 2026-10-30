/// ÉTIQUETAGE & EMPLACEMENTS (M6) — port des règles de `m6-etiquetage` (prototype_html/assets/js/modules/m6-stock.js).
///
/// Le rangement suit le principe FEFO : à l'intérieur de chaque casier, les lots sont classés par date de péremption croissante. Un casier est un
/// RÉFÉRENTIEL (collection `emplacements`) ; l'emplacement d'un produit est le CODE du casier, porté par la fiche produit. Les vecteurs
/// (`test/vecteurs/etiquetage.json`) sont engendrés par la maquette (`prototype_html/build/vecteurs-etiquetage.js`).
///
/// Corrigé dans la maquette PUIS porté (ECARTS-MAQUETTE.md, E48) : la carte des articles SANS emplacement s'intitulait « undefined » (`groupBy` fait de
/// l'absence de clé la chaîne « undefined »). Porté fidèlement et signalé : E47 — l'archivage « avec motif » accepte un motif VIDE.
library;

import '../format/format_fr.dart';
import '../format/js.dart';
import '../format/recherche.dart';

const zonesEmplacement = [
  'Rayonnage sec',
  'Chaîne du froid',
  'Armoire sécurisée',
  'Réserve',
  'Salle de soins',
];

const temperaturesConservation = [
  'Ambiante',
  '2 à 8 °C',
  '− 20 °C',
  'Sous clé, ambiante',
];

/// Nombre d'articles rangés dans un casier : les produits dont l'`emplacement` est le CODE du casier.
int articlesRanges(Object? code, Iterable<Map<String, Object?>> produits) =>
    produits.where((p) => p['emplacement'] == code).length;

/// Un casier du plan des rayons : la clé de regroupement (le code, ou `undefined` pour l'absence d'emplacement — la clé que la maquette fabrique) et ses articles.
class CarteCasier {
  const CarteCasier(this.cle, this.articles);
  final String cle;
  final List<Map<String, Object?>> articles;

  /// L'intitulé affiché : « Sans emplacement » pour les articles qui n'en ont pas (E48).
  String get libelle => (cle.isNotEmpty && cle != 'undefined') ? cle : 'Sans emplacement';
}

/// Le plan des rayons : les produits groupés par emplacement, les casiers triés par clé (ordre naturel français), les articles dans l'ordre du magasin.
List<CarteCasier> planDesRayons(Iterable<Map<String, Object?>> produits) {
  final groupes = <String, List<Map<String, Object?>>>{};
  for (final p in produits) {
    // `groupBy` : la clé est la chaîne de la valeur — « undefined » quand l'emplacement manque.
    final cle = p['emplacement'] == null ? 'undefined' : '${p['emplacement']}';
    (groupes[cle] ??= []).add(p);
  }
  return trierPar(
      [for (final e in groupes.entries) CarteCasier(e.key, e.value)], (c) => c.cle);
}

/// L'état d'un article au regard de son stock : `rupture` (0), `critique` (au seuil ou sous le seuil), `normal`. Un seuil absent ne fait jamais « critique ».
String etatStock(Map<String, Object?> p) {
  final s = p['stock'];
  if (s == 0) return 'rupture';
  final seuil = p['seuilAlerte'];
  if (s is num && seuil is num && s <= seuil) return 'critique';
  return 'normal';
}

/// Le lot qui périme le premier (FEFO) parmi ceux d'un produit, ou `null`.
Map<String, Object?>? prochainLot(Object? produitId, Iterable<Map<String, Object?>> lots) {
  final siens = [for (final l in lots) if (l['produitId'] == produitId) l];
  if (siens.isEmpty) return null;
  return trierPar(siens, (l) => l['datePeremption']).first;
}

/// Les lignes d'une étiquette produit, dans l'ordre d'impression. [sigle] : le sigle de la clinique (`C.BRAND.sigle`).
List<String> ligneEtiquette(Map<String, Object?> p, Iterable<Map<String, Object?>> lots,
    {String sigle = 'CNT'}) {
  final prochain = prochainLot(p['id'], lots);
  final emp = p['emplacement'];
  return [
    sigle,
    '${p['designation']}',
    'Code : ${p['code']}',
    'Emplacement : ${emp == null || emp == '' ? '—' : emp}',
    if (prochain != null) ...[
      'Lot : ${prochain['numeroLot']}',
      'Péremption : ${_dateFR(prochain['datePeremption'])}',
    ],
    'P.U. : ${money(p['prixVente'], avecDevise: false)}',
  ];
}

String _dateFR(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? '' : dateFR(d);
}

/// Les quatre indicateurs de l'écran.
class KpisEtiquetage {
  const KpisEtiquetage(this.emplacements, this.articlesRanges, this.sansEmplacement, this.lotsFefo);
  final int emplacements, articlesRanges, sansEmplacement, lotsFefo;
}

KpisEtiquetage kpisEtiquetage({
  required Iterable<Map<String, Object?>> emplacements,
  required Iterable<Map<String, Object?>> produits,
  required Iterable<Map<String, Object?>> lots,
}) =>
    KpisEtiquetage(
      emplacements.length,
      produits.length,
      produits.where((p) => p['emplacement'] == null || p['emplacement'] == '').length,
      lots.length,
    );

/// La fiche d'un NOUVEL emplacement, telle que la maquette l'écrit : la capacité vide devient 0 (`Number('')`), la source nomme le jour de création.
Map<String, Object?> nouvelEmplacement(Map<String, Object?> v, DateTime jour) => {
      ...v,
      'capacite': nombreOuZero(v['capacite']),
      'source': 'Créé dans l’application le ${dateFR(jour)}',
    };

/// « 2 / 10 », « 2 », ou `null` (le casier est vide) : le contenu de la colonne « Articles rangés ». [plein] : la capacité est atteinte.
({String? texte, bool plein}) occupationCasier(int articles, Object? capacite) {
  if (articles == 0) return (texte: null, plein: false);
  final cap = nombreOuZero(capacite);
  final plein = cap != 0 && articles >= cap;
  return (texte: nombre(articles) + (cap != 0 ? ' / ${nombre(cap)}' : ''), plein: plein);
}
