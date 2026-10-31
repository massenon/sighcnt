/// LES FEUILLETS DE LA LIASSE DÉPOSÉS OU CALCULÉS (M12) — port de `m12-comptabilite.js` (vague 61) : le compte de résultat (feuillet 7/51) et le tableau
/// des flux de trésorerie (feuillet 8/51), `m12-compte-resultat` et `m12-flux-tresorerie`.
///
/// DEUX SOURCES POUR UNE COLONNE, JAMAIS MÉLANGÉES : un exercice DÉPOSÉ se CITE (`cpbLiasse`, des faits qui ne se recalculent pas) ; un exercice du
/// journal se CALCULE — chaque écriture VALIDÉE va à la ligne dont le préfixe de compte est le PLUS LONG, puis les sous-totaux suivent les formules
/// imprimées sur le formulaire (« XC = XB + RA + RB + somme TE à RJ »). Le sous-total n'est jamais saisi.
///
/// Les règles se rejouent sur `test/vecteurs/comptabilite_b.json`, tiré des écrans réels de la maquette.
library;

import '../format/format_fr.dart';
import '../format/js.dart';
import '../referentiels/periodes.dart';
import '../referentiels/regles.dart' show joursEntre;
import 'cpa_referentiels.dart' show CpaFiche;
import 'cpb_donnees.dart';
import 'cpb_liasse.dart';

double _n(Object? v) => nombreOuZero(v);

/// Une ligne du formulaire (`SIGH.liasse.RESULTAT` / `FLUX`) : une `section` (intertitre), un sous-total (`t`) ou une ligne de détail.
class CpbLigneFormulaire {
  const CpbLigneFormulaire({
    this.section,
    this.ref,
    this.libelle = '',
    this.t,
    this.signe,
    this.repere,
    this.note,
    this.n,
    this.n1,
    this.comptes,
    this.ecart,
  });
  final String? section, ref, t, signe, repere, note, ecart;
  final String libelle;
  final double? n, n1;
  final List<String>? comptes;

  /// `cleLigne(l)` : la ligne « Variation du BF » n'a pas de référence sur le formulaire — on lui donne une CLÉ interne, jamais affichée.
  String get cle => (ref != null && ref!.isNotEmpty) ? ref! : (ecart == 'bf' ? 'BF' : '');
}

List<CpbLigneFormulaire> _lignes(Object? liste) => [
      for (final x in (liste as List).cast<Map>())
        CpbLigneFormulaire(
          section: x['section'] as String?,
          ref: x['ref'] as String?,
          libelle: (x['libelle'] ?? '') as String,
          t: x['t'] as String?,
          signe: x['signe'] as String?,
          repere: x['repere'] as String?,
          note: x['note'] as String?,
          n: (x['n'] as num?)?.toDouble(),
          n1: (x['n1'] as num?)?.toDouble(),
          comptes: (x['comptes'] as List?)?.cast<String>(),
          ecart: x['ecart'] as String?,
        )
    ];

/// `L.RESULTAT` et `L.FLUX`.
final List<CpbLigneFormulaire> cpbLignesResultat = _lignes(cpbLiasse['RESULTAT']);
final List<CpbLigneFormulaire> cpbLignesFlux = _lignes(cpbLiasse['FLUX']);

Map<String, Object?> get cpbDepot => (cpbLiasse['DEPOT'] as Map).cast<String, Object?>();
int get cpbExerciceN => cpbDepot['exerciceN'] as int;
int get cpbExerciceN1 => cpbDepot['exerciceN1'] as int;

/// `L.ECARTS` : les écarts internes du document déposé, CONSERVÉS et non arbitrés.
List<Map<String, Object?>> get cpbEcarts => [for (final x in (cpbLiasse['ECARTS'] as List).cast<Map>()) x.cast<String, Object?>()];

/// `L.ecart(cle)`.
Map<String, Object?>? cpbEcart(String cle) {
  for (final x in cpbEcarts) {
    if (x['cle'] == cle) return x;
  }
  return null;
}

/// Les formules que le formulaire imprime dans ses libellés.
const Map<String, List<String>> cpbFormulesResultat = {
  'XA': ['TA', 'RA', 'RB'],
  'XB': ['TA', 'TB', 'TC', 'TD'],
  'XC': ['XB', 'RA', 'RB', 'TE', 'TF', 'TG', 'TH', 'TI', 'RC', 'RD', 'RE', 'RF', 'RG', 'RH', 'RI', 'RJ'],
  'XD': ['XC', 'RK'],
  'XE': ['XD', 'TJ', 'RL'],
  'XF': ['TK', 'TL', 'TM', 'RM', 'RN'],
  'XG': ['XE', 'XF'],
  'XH': ['TN', 'TO', 'RO', 'RP'],
  'XI': ['XG', 'XH', 'RQ', 'RS'],
};
const Map<String, List<String>> cpbFormulesFlux = {
  'BF': ['FB', 'FC', 'FD', 'FE'],
  'ZB': ['FA', 'FB', 'FC', 'FD', 'FE'],
  'ZC': ['FF', 'FG', 'FH', 'FI', 'FJ'],
  'ZD': ['FK', 'FL', 'FM', 'FN'],
  'ZE': ['FO', 'FP', 'FQ'],
  'ZF': ['ZD', 'ZE'],
  'ZG': ['ZB', 'ZC', 'ZF'],
  'ZH': ['ZG', 'ZA'],
};

/// `appliquerFormules` : dans l'ORDRE du formulaire, chaque sous-total est la somme de ses composantes déjà calculées.
void cpbAppliquerFormules(List<CpbLigneFormulaire> lignes, Map<String, List<String>> formules, Map<String, double> v) {
  for (final l in lignes) {
    final cle = l.cle;
    final f = cle.isEmpty ? null : formules[cle];
    if (f == null) continue;
    v[cle] = f.fold<double>(0, (a, r) => a + (v[r] ?? 0));
  }
}

/// `valeursDeposees` : les valeurs d'un exercice DÉPOSÉ, lues telles quelles.
Map<String, double> cpbValeursDeposees(List<CpbLigneFormulaire> lignes, int annee) {
  final v = <String, double>{};
  for (final l in lignes) {
    if (l.cle.isEmpty) continue;
    final x = annee == cpbExerciceN ? l.n : l.n1;
    if (x != null) v[l.cle] = x;
  }
  return v;
}

class CpbControleSousTotal {
  const CpbControleSousTotal(this.ref, this.depose, this.recalcule);
  final String ref;
  final double depose, recalcule;
  double get ecart => depose - recalcule;
}

/// `controleSousTotaux` : chaque sous-total se compare à SES composantes DÉPOSÉES, sans cascade — un écart en amont ne doit pas faire accuser à tort les
/// totaux d'aval qui, eux, se recoupent (ZG = ZB + ZC + ZF avec le ZB déposé).
List<CpbControleSousTotal> cpbControleSousTotaux(List<CpbLigneFormulaire> lignes, Map<String, List<String>> formules, int annee) {
  final dep = cpbValeursDeposees(lignes, annee);
  return [
    for (final k in formules.keys)
      if (dep[k] != null) CpbControleSousTotal(k, dep[k]!, formules[k]!.fold<double>(0, (a, r) => a + (dep[r] ?? 0)))
  ];
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// EXERCICES ET BORNES
// ---------------------------------------------------------------------------------------------------------------------------------------------------

DateTime? _date(Object? d) => DateTime.tryParse('${d ?? ''}');

/// `exercicesDuJournal` : l'année du jour et celles des écritures actives, de la plus récente à la plus ancienne.
List<int> cpbExercicesDuJournal(Iterable<CpaFiche> ecritures, DateTime aujourdhui) {
  final annees = <int>{aujourdhui.year};
  for (final e in ecritures) {
    final d = e['date'] == null || e['date'] == '' ? null : _date(e['date']);
    if (d != null) annees.add(d.year);
  }
  return annees.toList()..sort((a, b) => b.compareTo(a));
}

/// `bornesExercice(annee, arrete)` : du 1er janvier à la date arrêtée, jamais au-delà du 31 décembre de l'exercice.
Bornes cpbBornesExercice(int annee, DateTime? arrete) {
  final debut = DateTime(annee, 1, 1), finAn = DateTime(annee, 12, 31);
  var fin = arrete ?? finAn;
  if (fin.year != annee || fin.isAfter(finAn)) fin = finAn;
  return Bornes(debut, fin, 'Exercice $annee', joursEntre(debut, fin) + 1);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// ÉCRITURES RETENUES, SOLDES DE GESTION, CHARGES FIXES ET VARIABLES
// ---------------------------------------------------------------------------------------------------------------------------------------------------

/// `ecrituresRetenues(bornes)` : on ne retient QUE les écritures VALIDÉES. Un brouillon n'est pas un fait comptable : le compter donnerait un résultat
/// qui change quand le comptable rectifie une saisie. Le nombre de brouillons écartés est ANNONCÉ.
({List<CpaFiche> lignes, int brouillons}) cpbEcrituresRetenues(Iterable<CpaFiche> toutes, [Bornes? b]) {
  var brouillons = 0;
  final retenues = <CpaFiche>[];
  for (final e in toutes) {
    if (b != null) {
      final d = _date(e['date']);
      if (d == null || !dansBornes(d, b)) continue;
    }
    if (e['statut'] == 'brouillon') {
      brouillons++;
      continue;
    }
    retenues.add(e);
  }
  return (lignes: retenues, brouillons: brouillons);
}

/// `D.rubriqueDuCompte(num)` : la rubrique d'un compte par PRÉFIXE — le plus long l'emporte.
Map<String, Object?>? cpbRubriqueDuCompte(Object? num) {
  final s = '${num ?? ''}';
  Map<String, Object?>? trouvee;
  var longueur = -1;
  for (final r in cpbRubriquesResultat) {
    for (final p in (r['prefixes'] as List).cast<String>()) {
      if (s.startsWith(p) && p.length > longueur) {
        trouvee = r;
        longueur = p.length;
      }
    }
  }
  return trouvee;
}

/// `D.natureCharge(num)` : fixe ou variable, le préfixe le plus long l'emporte ; sans préfixe, `fixe`.
String cpbNatureCharge(Object? num) {
  final s = '${num ?? ''}';
  String? val;
  var longueur = -1;
  cpbNatureChargeDefaut.forEach((p, nature) {
    if (s.startsWith(p) && p.length > longueur) {
      val = nature;
      longueur = p.length;
    }
  });
  return val ?? 'fixe';
}

/// `NATURE_CHARGE` réduit à ses préfixes (les clés `aValider` et `note` ne sont pas des préfixes).
final Map<String, String> cpbNatureChargeDefaut = {
  for (final e in cpbNatureChargeReferentiel.entries)
    if (e.value is String && e.key != 'note') e.key: e.value as String
};

class CpbSoldesGestion {
  const CpbSoldesGestion({
    required this.rubriques,
    required this.margeCommerciale,
    required this.production,
    required this.valeurAjoutee,
    required this.ebe,
    required this.exploitation,
    required this.financier,
    required this.net,
    required this.chiffreAffaires,
    required this.brouillons,
    required this.nbLignes,
  });
  final Map<String, double> rubriques;
  final double margeCommerciale, production, valeurAjoutee, ebe, exploitation, financier, net, chiffreAffaires;
  final int brouillons, nbLignes;
}

/// `soldeRubrique` : un produit vit au CRÉDIT, une charge au DÉBIT — les avoirs et annulations se déduisent d'eux-mêmes.
double _soldeRubrique(List<CpaFiche> lignes, Map<String, Object?> rubrique) {
  var total = 0.0;
  for (final e in lignes) {
    final r = cpbRubriqueDuCompte(e['compte']);
    if (r == null || r['id'] != rubrique['id']) continue;
    total += rubrique['sens'] == 'produit' ? _n(e['credit']) - _n(e['debit']) : _n(e['debit']) - _n(e['credit']);
  }
  return total;
}

/// `soldesGestion(bornes)` : la cascade SYSCOHADA — chaque solde retranche au précédent.
CpbSoldesGestion cpbSoldesGestion(Iterable<CpaFiche> toutes, [Bornes? b]) {
  final src = cpbEcrituresRetenues(toutes, b);
  final r = <String, double>{};
  for (final rub in cpbRubriquesResultat) {
    r['${rub['id']}'] = _soldeRubrique(src.lignes, rub);
  }
  double g(String k) => r[k] ?? 0;
  final marge = g('ventes_march') - g('achats_march');
  final production = g('production');
  final va = marge + production - g('consommations');
  final ebe = va - g('personnel') - g('impots');
  final exploitation = ebe - g('dotations') - g('autres_charges');
  final financier = g('produits_fin') - g('charges_fin');
  return CpbSoldesGestion(
    rubriques: r,
    margeCommerciale: marge,
    production: production,
    valeurAjoutee: va,
    ebe: ebe,
    exploitation: exploitation,
    financier: financier,
    net: exploitation + financier - g('impot_societes'),
    chiffreAffaires: g('ventes_march') + production,
    brouillons: src.brouillons,
    nbLignes: src.lignes.length,
  );
}

class CpbCompteCharge {
  const CpbCompteCharge(this.compte, this.libelle, this.montant, this.nature);
  final String compte, libelle, nature;
  final double montant;
}

class CpbChargesParNature {
  const CpbChargesParNature(this.fixe, this.variable, this.comptes, this.brouillons);
  final double fixe, variable;
  final List<CpbCompteCharge> comptes;
  final int brouillons;
}

/// `chargesParNature(bornes)` — le socle du seuil de rentabilité. `natures` : les corrections de la clinique (compte → nature), qui l'emportent sur le
/// référentiel ; `libelleCompte` : `compteLibelle`.
CpbChargesParNature cpbChargesParNature(Iterable<CpaFiche> toutes, Bornes b,
    {Map<String, String> natures = const {}, required String Function(String) libelleCompte}) {
  final src = cpbEcrituresRetenues(toutes, b);
  var fixe = 0.0, variable = 0.0;
  final ordre = <String>[];
  final par = <String, ({String libelle, double montant, String nature})>{};
  for (final e in src.lignes) {
    final num = '${e['compte'] ?? ''}';
    if (!num.startsWith('6')) continue;
    final montant = _n(e['debit']) - _n(e['credit']);
    if (montant == 0) continue;
    final nature = natures[num] ?? cpbNatureCharge(num);
    if (nature == 'variable') {
      variable += montant;
    } else {
      fixe += montant;
    }
    final cur = par[num];
    if (cur == null) ordre.add(num);
    par[num] = (libelle: libelleCompte(num), montant: (cur?.montant ?? 0) + montant, nature: nature);
  }
  final liste = [for (final k in ordre) CpbCompteCharge(k, par[k]!.libelle, par[k]!.montant, par[k]!.nature)];
  // tri `C.sortBy(…, 'montant', 'desc')` : stable, du plus grand au plus petit
  final idx = [for (var i = 0; i < liste.length; i++) i]..sort((a, c) {
      final d = liste[c].montant.compareTo(liste[a].montant);
      return d != 0 ? d : a.compareTo(c);
    });
  return CpbChargesParNature(fixe, variable, [for (final i in idx) liste[i]], src.brouillons);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// LE COMPTE DE RÉSULTAT CALCULÉ
// ---------------------------------------------------------------------------------------------------------------------------------------------------

class CpbResultatCalcule {
  const CpbResultatCalcule(this.valeurs, this.alimentees, this.orphelins, this.brouillons, this.nbLignes);
  final Map<String, double> valeurs;
  final Set<String> alimentees;
  final Map<String, double> orphelins;
  final int brouillons, nbLignes;
}

/// `resultatCalcule(b)` : LE PRÉFIXE LE PLUS LONG GAGNE (« 654 » — cessions — avant « 65 »). Produit comme charge : crédit − débit, si bien que le
/// formulaire porte les charges en NÉGATIF. Un compte de gestion sans ligne est NOMMÉ (orphelin), jamais compté en silence.
CpbResultatCalcule cpbResultatCalcule(Iterable<CpaFiche> toutes, Bornes b) {
  final prefixes = <({String p, String ref})>[];
  for (final l in cpbLignesResultat) {
    if (l.t == null && l.comptes != null) {
      for (final p in l.comptes!) {
        prefixes.add((p: p, ref: l.ref!));
      }
    }
  }
  final idx = [for (var i = 0; i < prefixes.length; i++) i]..sort((a, c) {
      final d = prefixes[c].p.length - prefixes[a].p.length;
      return d != 0 ? d : a.compareTo(c); // tri JavaScript STABLE
    });
  final tries = [for (final i in idx) prefixes[i]];
  final src = cpbEcrituresRetenues(toutes, b);
  final v = <String, double>{};
  final alimentees = <String>{};
  final orphelins = <String, double>{};
  for (final e in src.lignes) {
    final num = '${e['compte'] ?? ''}';
    if (num.isEmpty || !'678'.contains(num[0])) continue;
    ({String p, String ref})? hit;
    for (final x in tries) {
      if (num.startsWith(x.p)) {
        hit = x;
        break;
      }
    }
    final montant = _n(e['credit']) - _n(e['debit']);
    if (hit == null) {
      orphelins[num] = (orphelins[num] ?? 0) + montant;
      continue;
    }
    v[hit.ref] = (v[hit.ref] ?? 0) + montant;
    alimentees.add(hit.ref);
  }
  cpbAppliquerFormules(cpbLignesResultat, cpbFormulesResultat, v);
  return CpbResultatCalcule(v, alimentees, orphelins, src.brouillons, src.lignes.length);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// LE TABLEAU DES FLUX CALCULÉ — méthode indirecte du SYSCOHADA
// ---------------------------------------------------------------------------------------------------------------------------------------------------

const List<String> cpbNonDecaissables = ['68', '69', '79', '81', '82', '654', '754'];
const List<String> cpbTiersHorsBf = ['465', '481', '482', '485', '488'];

class CpbFluxCalcule {
  const CpbFluxCalcule(this.valeurs, this.controle, this.nonClasses, this.brouillons, this.nbLignes);
  final Map<String, double> valeurs;
  final double controle;
  final Map<String, double> nonClasses;
  final int brouillons, nbLignes;
  double get ecart => controle - (valeurs['ZH'] ?? 0);
}

bool _commence(String num, Iterable<String> liste) => liste.any(num.startsWith);

double _somme(Map<String, double> obj, List<String> liste, [List<String>? exclus]) {
  var t = 0.0;
  obj.forEach((num, x) {
    if (_commence(num, liste) && !(exclus != null && _commence(num, exclus))) t += x;
  });
  return t;
}

/// `fluxCalcule(b)` : la CAFG part des charges et produits DÉCAISSABLES ; la variation du besoin de financement se lit sur les soldes des stocks et des
/// tiers ; investissements et financement sur les mouvements des classes 1 et 2. Les à-nouveaux (journal AN) forment l'OUVERTURE, jamais un flux. Le
/// CONTRÔLE final est celui que le formulaire imprime : trésorerie par les flux (ZH) = trésorerie des comptes de classe 5 ; un écart NOMME les comptes
/// que le tableau ne classe pas.
CpbFluxCalcule cpbFluxCalcule(Iterable<CpaFiche> toutes, Bornes b) {
  final tDebut = b.debut.millisecondsSinceEpoch, tFin = b.fin.millisecondsSinceEpoch;
  final annee = b.debut.year;
  final ouverture = <String, double>{}, mouv = <String, double>{}, debits = <String, double>{}, credits = <String, double>{};
  var brouillons = 0, nb = 0;
  for (final e in toutes) {
    if (e['date'] == null || e['date'] == '') continue;
    final d = _date(e['date']);
    if (d == null) continue;
    final t = d.millisecondsSinceEpoch;
    if (t > tFin) continue;
    final aNouveau = e['journal'] == 'AN' && d.year == annee;
    if (e['statut'] == 'brouillon') {
      if (t >= tDebut) brouillons++;
      continue;
    }
    final num = '${e['compte'] ?? ''}';
    final dd = _n(e['debit']), cc = _n(e['credit']);
    if (t < tDebut || aNouveau) {
      ouverture[num] = (ouverture[num] ?? 0) + dd - cc;
      continue;
    }
    nb++;
    mouv[num] = (mouv[num] ?? 0) + dd - cc;
    debits[num] = (debits[num] ?? 0) + dd;
    credits[num] = (credits[num] ?? 0) + cc;
  }
  double tresorerie(Map<String, double> soldes) => _somme(soldes, ['5'], ['59']);
  final comptes = <String>{...ouverture.keys, ...mouv.keys};
  final cloture = {for (final k in comptes) k: (ouverture[k] ?? 0) + (mouv[k] ?? 0)};

  // Créances et dettes : un compte de tiers change de côté selon son solde (SYSCOHADA) ; on le suit compte par compte.
  var dActif = 0.0, dPassif = 0.0;
  for (final num in comptes) {
    if (!num.startsWith('4') || _commence(num, cpbTiersHorsBf)) continue;
    final o = ouverture[num] ?? 0, f = cloture[num]!;
    dActif += (f > 0 ? f : 0) - (o > 0 ? o : 0);
    dPassif += (-f > 0 ? -f : 0) - (-o > 0 ? -o : 0);
  }
  double neg(double x) => x == 0 ? 0 : -x; // `-0` n'existe pas dans un montant affiché
  final v = <String, double>{
    'ZA': tresorerie(ouverture),
    'FA': neg(_somme(mouv, ['6', '7', '8'], cpbNonDecaissables)),
    'FB': neg(_somme(mouv, ['485', '488'])),
    'FC': neg(_somme(mouv, ['3'])),
    'FD': neg(dActif),
    'FE': dPassif,
    'FF': neg(_somme(debits, ['21'])),
    'FG': neg(_somme(debits, ['22', '23', '24'])),
    'FH': neg(_somme(debits, ['26', '27'])),
    'FI': _somme(credits, ['82', '754']),
    'FJ': 0,
    'FK': _somme(credits, ['101', '102', '103', '104']),
    'FL': _somme(credits, ['14']),
    'FM': neg(_somme(debits, ['101', '102', '103', '104', '109'])),
    'FN': neg(_somme(debits, ['465'])),
    'FO': _somme(credits, ['16', '17']),
    'FP': _somme(credits, ['18']),
    'FQ': neg(_somme(debits, ['16', '17', '18'])),
  };
  cpbAppliquerFormules(cpbLignesFlux, cpbFormulesFlux, v);

  final controle = tresorerie(cloture);
  // Ce que le tableau ne classe pas : affectation du résultat, provisions, amortissements et cessions (neutres deux à deux quand la pièce est complète),
  // dettes sur immobilisations. S'ils ne s'annulent pas, l'écart du contrôle les nomme.
  const classes = ['5', '6', '7', '8', '3', '4', '21', '22', '23', '24', '26', '27', '10', '14', '16', '17', '18'];
  final nonClasses = <String, double>{};
  final exclus = ['59', '481', '482', '485', '488', ...cpbNonDecaissables];
  final immo = RegExp(r'^(22|23|24|21|26|27|10|16|17|18)');
  mouv.forEach((num, x) {
    var classe = _commence(num, classes) && !_commence(num, exclus);
    if (_commence(num, ['485', '488', '465'])) classe = true;
    if (immo.hasMatch(num) && (credits[num] ?? 0) != 0 && !_commence(num, ['16', '17', '18', '101', '102', '103', '104'])) {
      classe = false; // la sortie d'une immobilisation n'est pas un flux : sa contrepartie est au 81
    }
    if (!classe && x.abs() > 0.5) nonClasses[num] = x;
  });
  return CpbFluxCalcule(v, controle, nonClasses, brouillons, nb);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// LES COLONNES D'UN FEUILLET
// ---------------------------------------------------------------------------------------------------------------------------------------------------

class CpbColonne {
  const CpbColonne({
    required this.depose,
    required this.annee,
    required this.titre,
    required this.sous,
    required this.valeurs,
    this.alimentees,
    this.orphelins = const {},
    this.brouillons = 0,
    this.nbLignes = 0,
    this.bornes,
    this.controle = 0,
    this.ecart = 0,
    this.nonClasses = const {},
  });
  final bool depose;
  final int annee;
  final String titre, sous;
  final Map<String, double> valeurs;
  final Set<String>? alimentees;
  final Map<String, double> orphelins, nonClasses;
  final int brouillons, nbLignes;
  final Bornes? bornes;
  final double controle, ecart;

  /// `val(c, ref)` : `c.valeurs[ref] || 0`.
  double val(String ref) => valeurs[ref] ?? 0;
}

/// `sourceColonne(genre, annee, b)` : `genre` vaut `resultat` ou `flux`. `b == null` sur un exercice déposé : on CITE ; sinon on CALCULE.
CpbColonne cpbSourceColonne(String genre, int annee, Bornes? b, Iterable<CpaFiche> ecritures) {
  final lignes = genre == 'resultat' ? cpbLignesResultat : cpbLignesFlux;
  final depose = annee == cpbExerciceN || annee == cpbExerciceN1;
  if (b == null && depose) {
    return CpbColonne(
        depose: true,
        annee: annee,
        titre: 'Exercice au 31/12/$annee',
        sous: 'déposé — liasse ${cpbDepot['code']}',
        valeurs: cpbValeursDeposees(lignes, annee));
  }
  final bb = b ?? cpbBornesExercice(annee, null);
  if (genre == 'resultat') {
    final c = cpbResultatCalcule(ecritures, bb);
    return CpbColonne(
        depose: false,
        annee: annee,
        titre: 'Exercice $annee',
        sous: 'calculé — arrêté au ${dateFR(bb.fin)}',
        valeurs: c.valeurs,
        alimentees: c.alimentees,
        orphelins: c.orphelins,
        brouillons: c.brouillons,
        nbLignes: c.nbLignes,
        bornes: bb);
  }
  final c = cpbFluxCalcule(ecritures, bb);
  return CpbColonne(
      depose: false,
      annee: annee,
      titre: 'Exercice $annee',
      sous: 'calculé — arrêté au ${dateFR(bb.fin)}',
      valeurs: c.valeurs,
      nonClasses: c.nonClasses,
      brouillons: c.brouillons,
      nbLignes: c.nbLignes,
      bornes: bb,
      controle: c.controle,
      ecart: c.ecart);
}

/// `colonnesFeuillet(genre, choix, arrete)` : les deux colonnes N et N-1. `choix` : `depose` ou une année. L'exercice précédent se CITE s'il a été
/// déposé, sinon il se calcule.
List<CpbColonne> cpbColonnesFeuillet(String genre, String choix, DateTime? arrete, Iterable<CpaFiche> ecritures) {
  if (choix == 'depose') {
    return [cpbSourceColonne(genre, cpbExerciceN, null, ecritures), cpbSourceColonne(genre, cpbExerciceN1, null, ecritures)];
  }
  final annee = int.parse(choix);
  final n = cpbSourceColonne(genre, annee, cpbBornesExercice(annee, arrete), ecritures);
  final precedent = annee - 1;
  final depose = precedent == cpbExerciceN || precedent == cpbExerciceN1;
  final n1 = depose
      ? cpbSourceColonne(genre, precedent, null, ecritures)
      : cpbSourceColonne(genre, precedent, cpbBornesExercice(precedent, null), ecritures);
  return [n, n1];
}

/// `montantFeuillet` : le texte d'une cellule — `null` (« — ») pour une valeur absente OU pour une ligne de détail que le journal n'alimente pas (un zéro y
/// ferait croire à un solde nul là où il n'y a pas de donnée) ; le formulaire déposé, lui, porte ses zéros — on les cite.
String? cpbMontantFeuillet(CpbColonne col, CpbLigneFormulaire l) {
  final cle = l.cle;
  final v = col.valeurs[cle];
  final vide = !col.depose &&
      l.t == null &&
      col.alimentees != null &&
      !col.alimentees!.contains(cle) &&
      (v == null || v == 0) &&
      l.comptes != null;
  if (v == null || vide) return null;
  return money(v, avecDevise: false);
}

/// La note de source d'un feuillet : (texte de la ligne de colonne, nombre de brouillons écartés dans les colonnes calculées).
int cpbBrouillonsEcartes(List<CpbColonne> cols) => cols.where((c) => !c.depose).fold<int>(0, (a, c) => a + c.brouillons);
