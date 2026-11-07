/// BESOIN EN FONDS DE ROULEMENT ET COÛT À L'ACTIVITÉ (M12, `m12-bfr`, `m12-cout-activite`) — port de `PR.bfr` (`parcours.js`, vague 64) et de
/// `m12-comptabilite.js`, rejoués sur `test/vecteurs/bfr.json` tiré du moteur et des écrans réels de la maquette.
///
/// LE BFR N'INVENTE RIEN : il agrège trois composantes déjà tenues ailleurs — créances (la MÊME définition que la balance âgée de M9 : part assureur des
/// factures assurées + restes à charge), stocks (valorisés selon la méthode que la Direction a choisie) et dettes fournisseurs (M7). BFR = créances +
/// stocks − dettes. UN COMPOSANT NON AMORCÉ SE DIT (`incomplet`) : un BFR amputé de ses dettes est SURESTIMÉ, et un chiffre faux qui a l'air juste est pire
/// qu'une case vide. L'encours se lit À UNE DATE, le flux SUR UNE PÉRIODE.
///
/// LE COÛT À L'ACTIVITÉ calcule ce qui est calculable — le consommable réel sorti du stock, au CUMP — et NOMME ce qui ne l'est pas : le coût de personnel
/// n'est PAS imputable à un séjour (aucun document ne donne la clé de répartition), l'écran calcule donc une MARGE SUR CONSOMMABLES et le dit.
library;

import 'dart:convert';

import '../format/format_fr.dart';
import '../format/js.dart';
import 'cpa_referentiels.dart' show CpaFiche;
import '../format/recherche.dart' show trierPar;
import '../stock/points.dart' show MethodeValorisation, groupePrestation, valeurUnitaire;
import 'cpc_donnees.dart';

double _n(Object? v) => nombreOuZero(v);
bool _vrai(Object? v) => !(v == null || v == false || v == '' || (v is num && v == 0));
double _som(Iterable<CpaFiche> l, String k) => l.fold(0.0, (a, x) => a + _n(x[k]));

/// `C.daysBetween(a, b)` : `Math.round((b − a) / 86 400 000)`.
int cpcJoursEntre(Object? a, Object? b) {
  final x = a is DateTime ? a : DateTime.tryParse('$a'), y = b is DateTime ? b : DateTime.tryParse('$b');
  if (x == null || y == null) return 0;
  return arrondiJs(y.difference(x).inMilliseconds / 86400000).toInt();
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// OBJECTIFS DU PILOTAGE — l'alerte de recouvrement route, elle ne décide pas du seuil
// ---------------------------------------------------------------------------------------------------------------------------------------------------

/// `objectifsPilotage()` : la collection VIVANTE (non archivée) ; repli sur la semence si elle a été vidée — un poste dont la collection est vide doit
/// encore pouvoir lire ses indicateurs, sans cible arrêtée.
List<CpaFiche> cpcObjectifsPilotage(Iterable<CpaFiche> collection) {
  final vivants = [for (final o in collection) if (o['statut'] != 'archive') o];
  if (vivants.isNotEmpty) return vivants;
  return [for (final o in (jsonDecode(cpcObjectifsPilotageJson) as List)) (o as Map).cast<String, Object?>()];
}

CpaFiche? cpcObjectif(Iterable<CpaFiche> collection, String id) {
  for (final o in cpcObjectifsPilotage(collection)) {
    if (o['id'] == id) return o;
  }
  return null;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// LE BFR
// ---------------------------------------------------------------------------------------------------------------------------------------------------

/// La fenêtre d'observation : `jours` glissants (90 par défaut) jusqu'à `fin`, bornes nommées en ISO. [fin] absent : l'horloge du poste.
({String debut, String fin, int jours}) cpcFenetre({Object? fin, Object? debut, int? jours, required DateTime auj}) {
  final f = fin == null || fin == '' ? auj : (DateTime.tryParse('$fin') ?? auj);
  final d = debut == null || debut == '' ? DateTime(f.year, f.month, f.day - (jours == null || jours == 0 ? 90 : jours), f.hour, f.minute, f.second) : (DateTime.tryParse('$debut') ?? f);
  final nb = cpcJoursEntre(d, f);
  return (debut: iso(d), fin: iso(f), jours: nb < 1 ? 1 : nb);
}

bool _dansFenetre(Object? d, ({String debut, String fin, int jours}) f) {
  final x = '${d ?? ''}'.length >= 10 ? '$d'.substring(0, 10) : '${d ?? ''}';
  return x.isNotEmpty && x.compareTo(f.debut) >= 0 && x.compareTo(f.fin) <= 0;
}

/// Le résultat de `PR.bfr`.
class CpcBfr {
  const CpcBfr({
    required this.arrete,
    required this.fenetre,
    required this.creancesAssureurs,
    required this.restesACharge,
    required this.stocks,
    required this.dettes,
    required this.caPeriode,
    required this.bfrJours,
    required this.nbFacturesAssurees,
    required this.nbDettes,
    required this.incomplet,
  });
  final String arrete;
  final ({String debut, String fin, int jours}) fenetre;
  final double creancesAssureurs, restesACharge, stocks, dettes, caPeriode;
  final int? bfrJours;
  final int nbFacturesAssurees, nbDettes;

  /// Les composants NON amorcés sur ce poste (nommés) : le BFR affiché est alors surestimé de ce qui manque.
  final List<String> incomplet;

  double get creances => creancesAssureurs + restesACharge;
  double get bfr => creances + stocks - dettes;
}

bool _dettePayee(CpaFiche x) => const ['payee', 'soldee'].contains('${x['statutPaiement'] ?? ''}');

/// `PR.bfr({fin, jours})` : les trois composantes et leur somme algébrique. [factures], [produits] et [facturesFournisseurs] sont les fiches ACTIVES.
CpcBfr cpcBfr({
  required Iterable<CpaFiche> factures,
  required Iterable<CpaFiche> produits,
  required Iterable<CpaFiche> facturesFournisseurs,
  required DateTime auj,
  Object? fin,
  int? jours,
  MethodeValorisation methode = MethodeValorisation.prixVente,
}) {
  final f = cpcFenetre(fin: fin, jours: jours, auj: auj);
  final manquants = <String>[];
  // 1 — EN-COURS CLIENTS : la part assureur suit la définition de la balance âgée de M9, au mot près.
  final assurees = [for (final x in factures) if (_vrai(x['assureur'])) x];
  final creancesAssureurs = _som(assurees, 'partAssurance');
  final restes = factures
      .where((x) => x['statutPaiement'] != 'soldee')
      .fold(0.0, (a, x) => a + (_n(x['reliquat']) > 0 ? _n(x['reliquat']) : 0));
  // 2 — STOCKS, selon la méthode de valorisation en vigueur
  if (produits.isEmpty) manquants.add('les produits du stock');
  final stocks = produits.fold(0.0, (a, p) => a + _n(p['stock']) * valeurUnitaire(p, methode));
  // 3 — DETTES FOURNISSEURS : « payée » et « soldée » désignent la même chose selon l'écran par lequel la pièce est passée
  if (facturesFournisseurs.isEmpty) manquants.add('les factures fournisseurs');
  final dues = [for (final x in facturesFournisseurs) if (!_dettePayee(x)) x];
  final dettes = _som(dues, 'montantFacture');
  final caPeriode = _som([for (final x in factures) if (_dansFenetre(x['date'], f)) x], 'montantTTC');
  final creances = creancesAssureurs + restes;
  return CpcBfr(
    arrete: f.fin,
    fenetre: f,
    creancesAssureurs: creancesAssureurs,
    restesACharge: restes,
    stocks: stocks,
    dettes: dettes,
    caPeriode: caPeriode,
    bfrJours: caPeriode > 0 ? arrondiJs((creances + stocks - dettes) / (caPeriode / f.jours)).toInt() : null,
    nbFacturesAssurees: assurees.length,
    nbDettes: dues.length,
    incomplet: manquants,
  );
}

/// Une compagnie dont la créance dépasse le seuil d'ancienneté retenu.
class CpcAlerteRecouvrement {
  const CpcAlerteRecouvrement(this.seuil, this.assureur, this.montant, this.nb, this.jours);
  final num seuil;
  final String assureur;
  final double montant;
  final int nb, jours;
}

/// `PR.alertesRecouvrement({fin})` : consommé par le moteur de notifications, qui ROUTE sans décider du seuil — celui-ci vit dans `objectifsPilotage`, où la
/// Direction le règle (60 jours à défaut).
List<CpcAlerteRecouvrement> cpcAlertesRecouvrement({
  required Iterable<CpaFiche> factures,
  required Iterable<CpaFiche> objectifs,
  required DateTime auj,
  Object? fin,
}) {
  final f = cpcFenetre(fin: fin, auj: auj);
  final o = cpcObjectif(objectifs, 'creance_agee');
  final seuil = o != null ? _n(o['cible']) : 60;
  final par = <String, ({double montant, int nb, int jours})>{};
  for (final x in factures) {
    if (!_vrai(x['assureur']) || !(_n(x['partAssurance']) > 0)) continue;
    final j = cpcJoursEntre(x['date'], f.fin);
    if (j <= seuil) continue;
    final e = par['${x['assureur']}'] ?? (montant: 0.0, nb: 0, jours: 0);
    par['${x['assureur']}'] = (montant: e.montant + _n(x['partAssurance']), nb: e.nb + 1, jours: j > e.jours ? j : e.jours);
  }
  final l = [for (final k in par.keys) CpcAlerteRecouvrement(seuil, k, par[k]!.montant, par[k]!.nb, par[k]!.jours)];
  return trierPar(l, (e) => e.montant, descendant: true);
}

/// Les quatre lignes du tableau « Ce que le cycle finance » (et de la pièce imprimée) : la dette se DÉDUIT.
List<CpaFiche> cpcLignesBfr(CpcBfr b) => [
      {'quoi': 'Part assureur des factures', 'ou': 'M9 — Créances assureurs', 'montant': b.creancesAssureurs},
      {'quoi': 'Restes à charge non soldés', 'ou': 'M8 — Factures', 'montant': b.restesACharge},
      {'quoi': 'Stock détenu', 'ou': 'M6 — Point de stock', 'montant': b.stocks},
      {'quoi': 'Dettes fournisseurs (à déduire)', 'ou': 'M7 — Factures fournisseurs', 'montant': -b.dettes},
    ];

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// COÛT À L'ACTIVITÉ
// ---------------------------------------------------------------------------------------------------------------------------------------------------

class CpcGroupeActivite {
  CpcGroupeActivite(this.id, this.groupe);
  final String id, groupe;
  double recette = 0, cout = 0;
  int nbLignes = 0;
  double get marge => recette - cout;
  double? get taux => recette != 0 ? marge / recette * 100 : null;
}

class CpcCoutActivite {
  const CpcCoutActivite(this.lignes, this.horsGroupe);
  final List<CpcGroupeActivite> lignes;

  /// Les sorties de stock qui ne se rattachent à aucun groupe facturé sur la période : comptées À PART plutôt que réparties — les imputer au prorata
  /// fabriquerait une clé que rien ne justifie.
  final double horsGroupe;
  double get recette => lignes.fold(0.0, (a, x) => a + x.recette);
  double get cout => lignes.fold(0.0, (a, x) => a + x.cout);
}

const List<String> cpcSortiesStock = ['sortie', 'perte', 'casse', 'peremption'];

/// Le calcul de l'écran « Coût à l'activité » : la recette par groupe (les lignes de facture, comme partout ailleurs : c'est la seule façon de comparer
/// deux écrans) face aux sorties de stock de la période valorisées au CUMP et rattachées au groupe par la CATÉGORIE de l'article — un pansement sorti
/// pèse sur l'hospitalisation, un réactif sur le laboratoire. [du] et [au] : dates ISO (vides = pas de borne).
CpcCoutActivite cpcCoutActivite({
  required Iterable<CpaFiche> factures,
  required Iterable<CpaFiche> mouvements,
  required Iterable<CpaFiche> produits,
  required String du,
  required String au,
  Map<String, String?> secteurParCode = const {},
}) {
  bool dans(Object? d) {
    final x = '${d ?? ''}'.length >= 10 ? '$d'.substring(0, 10) : '${d ?? ''}';
    return x.isNotEmpty && (du.isEmpty || x.compareTo(du) >= 0) && (au.isEmpty || x.compareTo(au) <= 0);
  }

  final prods = {for (final p in produits) p['id']: p};
  final recettes = <String, CpcGroupeActivite>{};
  for (final f in factures) {
    if (!dans(f['date'])) continue;
    for (final raw in (f['lignes'] as List? ?? const [])) {
      final l = (raw as Map).cast<String, Object?>();
      final g = groupePrestation(l['categorie'], l, secteurParCode);
      final cle = g?.id ?? 'autre';
      final e = recettes.putIfAbsent(cle, () => CpcGroupeActivite(cle, g?.label ?? cle));
      e.recette += _n(l['montant']);
      e.nbLignes += 1;
    }
  }
  var horsGroupe = 0.0;
  for (final m in mouvements) {
    if (!cpcSortiesStock.contains(m['type']) || !dans(m['date'])) continue;
    final p = prods[m['produitId']];
    if (p == null) continue;
    final pu = _vrai(p['cump']) ? _n(p['cump']) : _n(p['prixAchat']);
    final valeur = _n(m['quantite']) * pu;
    final cle = p['categorie'] == 'medicament'
        ? 'pharmacie'
        : (p['categorie'] == 'reactif' || p['categorie'] == 'conso_labo')
            ? 'laboratoire'
            : 'hospitalisation';
    final e = recettes[cle];
    if (e == null) {
      horsGroupe += valeur;
    } else {
      e.cout += valeur;
    }
  }
  return CpcCoutActivite(trierPar(recettes.values.toList(), (x) => x.recette, descendant: true), horsGroupe);
}

/// Une ligne de la prévision saisonnière : le mois, ses admissions, l'indice (rapport à la moyenne des mois observés) et le BFR projeté.
class CpcPrevisionMois {
  const CpcPrevisionMois(this.mois, this.admissions, this.indice, this.bfrProjete);
  final String mois;
  final int admissions;
  final double? indice;
  final int? bfrProjete;
}

const List<String> cpcMois = ['Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'];

/// La prévision saisonnière : l'historique des admissions donne un profil mensuel, et c'est tout ce qu'il donne. L'indice applique au BFR constaté le
/// rapport des admissions du mois à la moyenne des mois OBSERVÉS ; moins de trois mois renseignés : `null` (un indice sur deux mois ne serait pas une
/// prévision, ce serait une coïncidence). Une PROJECTION, pas une prévision budgétaire.
List<CpcPrevisionMois>? cpcPrevisionSaisonniere(Iterable<CpaFiche> admissions, double bfr) {
  final parMois = List<int>.filled(12, 0);
  for (final a in admissions) {
    final d = '${a['dateEntree'] ?? ''}';
    if (d.isEmpty) continue;
    final m = (int.tryParse(d.length >= 7 ? d.substring(5, 7) : '') ?? 0) - 1;
    if (m >= 0 && m < 12) parMois[m] += 1;
  }
  final observes = [for (final n in parMois) if (n > 0) n];
  if (observes.length < 3) return null;
  final moyenne = observes.fold(0, (a, n) => a + n) / observes.length;
  return [
    for (var i = 0; i < 12; i++)
      if (parMois[i] > 0)
        () {
          // L'indice AFFICHÉ est arrondi au centième ; la projection, elle, applique l'indice EXACT (comme la maquette).
          final exact = parMois[i] != 0 && moyenne != 0 ? parMois[i] / moyenne : null;
          return CpcPrevisionMois(cpcMois[i], parMois[i], exact == null ? null : arrondiJs(exact * 100) / 100,
              exact == null ? null : arrondiJs(bfr * exact).toInt());
        }()
  ];
}
