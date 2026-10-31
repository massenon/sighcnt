/// REPRISE SAGE 100 (M6) — port de `SIGH.sage` (prototype_html/assets/js/data-sage.js) et des règles de `m6-reprise`.
///
/// Le stock initial n'a pas été saisi : il provient de l'import de l'inventaire « Grand Stock » (SAGE 100, arrêté au 15/07/2026). Le document FAIT FOI sur ce
/// qu'il porte ; la valorisation que la clinique ajoute pour les références qu'il ne valorise pas vit à part (collection `valorisationsSage`, une SURCOUCHE
/// datée et signée) — écraser le document ferait perdre la distinction entre ce qu'il disait et ce que la clinique a décidé.
///
/// Les données (lot d'import, 184 articles, catalogue tarifaire) sont un référentiel STATIQUE de la maquette : `donnees_sage.dart`, ENGENDRÉ par
/// `prototype_html/build/vecteurs-reprise.js`. Les règles (unité, seuil proposé, rapprochement) sont REJOUÉES sur les vecteurs.
library;

import 'dart:convert';

import '../format/format_fr.dart';
import '../format/js.dart';
import '../format/recherche.dart';
import 'donnees_sage.dart';

/// Un article de l'inventaire SAGE tel que le document le porte.
class ArticleSage {
  const ArticleSage({
    required this.code,
    required this.designation,
    required this.quantite,
    required this.prUnitaire,
    required this.prGlobal,
    required this.cump,
    required this.categorie,
    required this.valorise,
    required this.unite,
    required this.seuil,
  });
  final String code, designation, categorie, unite;
  final num quantite, prUnitaire, prGlobal, cump, seuil;

  /// Valorisé PAR LE DOCUMENT (prix de revient global > 0).
  final bool valorise;
}

class RapprochementTarif {
  const RapprochementTarif(
      {required this.n,
      required this.designation,
      required this.article,
      required this.designationStock,
      required this.cump,
      required this.correspondance});
  final int n;
  final String designation;
  final String? article, designationStock;

  /// Le prix proposé (CMUP relevé), ou `null` : « À fixer ».
  final num? cump;

  /// `exacte`, `approchée` ou `absente`.
  final String correspondance;
}

class ReferentielSage {
  ReferentielSage._(this.lot, this.articles, this.catalogue, this.categories);
  final Map<String, Object?> lot;
  final List<ArticleSage> articles;
  final List<Map<String, Object?>> catalogue;
  final Map<String, String> categories;

  static ReferentielSage? _instance;

  /// Le référentiel de la maquette, décodé une fois.
  static ReferentielSage get instance => _instance ??= _lire(donneesSageJson);

  static ReferentielSage _lire(String json) {
    final d = (jsonDecode(json) as Map).cast<String, Object?>();
    return ReferentielSage._(
      (d['lot'] as Map).cast(),
      [
        for (final a in (d['articles'] as List).cast<Map>())
          ArticleSage(
            code: '${a['code']}',
            designation: '${a['designation']}',
            quantite: a['quantite'] as num,
            prUnitaire: a['prUnitaire'] as num,
            prGlobal: a['prGlobal'] as num,
            cump: a['cump'] as num,
            categorie: '${a['categorie']}',
            valorise: a['valorise'] == true,
            unite: '${a['unite']}',
            seuil: a['seuil'] as num,
          )
      ],
      [for (final r in (d['rapprochement'] as List).cast<Map>()) r.cast<String, Object?>()],
      {for (final c in (d['categories'] as List).cast<Map>()) '${c['id']}': '${c['label']}'},
    );
  }

  /// Libellé d'une catégorie de produit (`categorieLabel`) ; à défaut l'identifiant lui-même.
  String categorieLabel(Object? id) => categories['$id'] ?? '$id';

  /// Total des quantités du document (contrôle de cohérence avec `lot.totalUnites`).
  num get totalUnites => articles.fold<num>(0, (a, x) => a + x.quantite);
  num get totalValeur => articles.fold<num>(0, (a, x) => a + x.prGlobal);

  /// `SG.rapprochement()` recalculé à partir des désignations du catalogue : les vecteurs le comparent à celui de la maquette.
  List<RapprochementTarif> rapprochement() {
    String cle(String s) => normaliser(s).replaceAll(RegExp(r'[^a-z0-9]'), '');
    final index = <String, ArticleSage>{for (final a in articles) cle(a.designation): a};
    return [
      for (final t in catalogue)
        () {
          final dt = '${t['designation']}';
          final exact = index[cle(dt)];
          ArticleSage? approche = exact;
          if (approche == null) {
            final kt = cle(dt);
            String debut(String s) => s.length > 10 ? s.substring(0, 10) : s;
            for (final a in articles) {
              final ka = cle(a.designation);
              if (ka.startsWith(debut(kt)) || kt.startsWith(debut(ka))) {
                approche = a;
                break;
              }
            }
          }
          return RapprochementTarif(
            n: (t['n'] as num).toInt(),
            designation: dt,
            article: approche?.code,
            designationStock: approche?.designation,
            cump: approche != null && approche.prUnitaire != 0 ? approche.prUnitaire : null,
            correspondance: exact != null ? 'exacte' : (approche != null ? 'approchée' : 'absente'),
          );
        }(),
    ];
  }
}

/// `SG.seuilPropose(quantite)` : absent du document, proposé à 20 % de la quantité relevée (minimum 5) — à valider article par article.
int seuilPropose(num quantite) {
  final v = arrondiJs(quantite * 0.2).toInt();
  return v < 5 ? 5 : v;
}

/// La valorisation que la clinique a saisie pour une référence (la surcoche), ou `null`.
Map<String, Object?>? valorisationDe(Object? code, Iterable<Map<String, Object?>> valorisations) =>
    valorisations.where((v) => v['code'] == code).firstOrNull;

/// Le prix retenu : celui du document s'il existe, sinon celui qu'on a saisi (`null` : à saisir).
num? prixRevient(ArticleSage a, Iterable<Map<String, Object?>> valorisations) {
  if (a.valorise) return a.cump;
  final v = valorisationDe(a.code, valorisations);
  return v == null ? null : v['prixRevient'] as num?;
}

/// « Non valorisé » veut dire : ni par le document, ni par la clinique.
bool resteSansPrix(ArticleSage a, Iterable<Map<String, Object?>> valorisations) =>
    !a.valorise && valorisationDe(a.code, valorisations) == null;

/// Les cinq indicateurs de l'écran.
class KpisReprise {
  const KpisReprise(
      {required this.articles,
      required this.unites,
      required this.valeur,
      required this.nonValorises,
      required this.valorisesParClinique,
      required this.valeurAjoutee});
  final int articles, nonValorises, valorisesParClinique;
  final num unites, valeur, valeurAjoutee;

  /// « 1 320 094 FCFA ajoutés à la valeur du stock », ou « aucune saisie à ce jour ».
  String get indiceValorises => valorisesParClinique > 0
      ? '${money(valeurAjoutee)} ajoutés à la valeur du stock'
      : 'aucune saisie à ce jour';
}

KpisReprise kpisReprise(
    List<ArticleSage> articles, Iterable<Map<String, Object?>> valorisations) {
  final sans = articles.where((a) => resteSansPrix(a, valorisations)).toList();
  final repris = articles.where((a) => !a.valorise && !resteSansPrix(a, valorisations)).toList();
  final ajoute = repris.fold<num>(
      0, (t, a) => t + (prixRevient(a, valorisations) ?? 0) * a.quantite);
  return KpisReprise(
    articles: articles.length,
    unites: articles.fold<num>(0, (t, a) => t + a.quantite),
    valeur: articles.fold<num>(0, (t, a) => t + a.prGlobal),
    nonValorises: sans.length,
    valorisesParClinique: repris.length,
    valeurAjoutee: ajoute,
  );
}

/// La fiche de surcouche à écrire (`saisirValorisation`). [auteur] : l'identifiant de l'agent ; [jour] : `YYYY-MM-DD`.
Map<String, Object?> ficheValorisation(ArticleSage a,
        {required num prixRevient,
        required String source,
        String? observation,
        required String auteur,
        required String jour}) =>
    {
      'code': a.code,
      'designation': a.designation,
      'prixRevient': prixRevient,
      'source': source,
      if (observation != null && observation.isNotEmpty) 'observation': observation,
      'auteur': auteur,
      'date': jour,
    };

/// Le message de succès d'une valorisation : « Référence valorisée. » et son détail.
String detailValorisation(ArticleSage a, num prixRevient) =>
    '${a.designation} — ${money(prixRevient, avecDevise: false)} l’unité, soit ${money(prixRevient * a.quantite, avecDevise: false)} de stock.';
