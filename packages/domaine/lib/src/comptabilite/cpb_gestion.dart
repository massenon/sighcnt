/// COMPTABILITÉ ANALYTIQUE, BUDGETS, IMMOBILISATIONS ET BANQUES (M12) — port de `m12-comptabilite.js` (m12-analytique, m12-budgets, m12-immobilisations,
/// m12-banques). Tout est CALCULÉ depuis les registres : rien n'est fourni. Les règles se rejouent sur `test/vecteurs/comptabilite_b.json`.
///
/// Immobilisations : l'amortissement court de la DATE D'ACQUISITION à aujourd'hui, par pas de SIX MOIS (l'annuité ne se constate qu'à la clôture et donnait
/// le même amortissement à un bien acquis en février et à un bien acquis en novembre) ; le dernier semestre SOLDE le reliquat ; un bien CÉDÉ cesse de
/// s'amortir à sa date de sortie et quitte le bilan (sa fiche reste au registre). Les totaux du registre SONT les colonnes BRUT / AMORT. / NET de l'actif
/// immobilisé du bilan, rattachées par le COMPTE SYSCOHADA — jamais par la catégorie d'usage.
library;

import '../format/format_fr.dart';
import '../format/js.dart';
import 'cpa_plan.dart' show cpaPlanComptable;
import 'cpa_referentiels.dart';

double _n(Object? v) => nombreOuZero(v);
double _som(Iterable<CpaFiche> l, String k) => l.fold<double>(0, (a, x) => a + _n(x[k]));

/// `C.referenceSuivante(prefixe, largeur, fiches)` : le plus grand rang déjà écrit pour ce préfixe, plus un — lu sur les fiches EXISTANTES, jamais sur un
/// compteur de page (écart E772, corrigé dans la maquette d'abord).
String cpbReferenceSuivante(String prefixe, int largeur, Iterable<CpaFiche> fiches) {
  var max = 0;
  for (final f in fiches) {
    final r = '${f['reference'] ?? ''}';
    if (r.startsWith(prefixe)) {
      final k = int.tryParse(RegExp(r'^[+-]?\d+').firstMatch(r.substring(prefixe.length))?.group(0) ?? '') ?? 0;
      if (k > max) max = k;
    }
  }
  return '$prefixe${(max + 1).toString().padLeft(largeur, '0')}';
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// ANALYTIQUE
// ---------------------------------------------------------------------------------------------------------------------------------------------------

class CpbLigneAnalytique {
  const CpbLigneAnalytique(this.id, this.centre, this.nb, this.charges, this.produits);
  final String id, centre;
  final int nb;
  final double charges, produits;
  double get resultat => produits - charges;

  /// `Math.round((produits − charges) / produits × 100)` ; sans produit, 0 (l'écran affiche alors « — »).
  int get marge => produits != 0 ? arrondiJs(resultat / produits * 100).toInt() : 0;
}

/// `m12-analytique` : une ligne par centre de coûts du référentiel STATIQUE `D.CENTRES_COUT` (les six secteurs et la Direction). Charges = débits des
/// comptes de classe 6, produits = crédits des comptes de classe 7, portés par le centre de la ligne d'écriture.
List<CpbLigneAnalytique> cpbAnalytique(Iterable<CpaFiche> ecritures, {List<(String, String, String)> centres = cpaCentresCout}) => [
      for (final cc in centres)
        () {
          final sel = [for (final x in ecritures) if (x['centreCout'] == cc.$1) x];
          final ch = _som([for (final x in sel) if ('${x['compte'] ?? ''}'.startsWith('6') && '${x['compte']}'.isNotEmpty) x], 'debit');
          final pr = _som([for (final x in sel) if ('${x['compte'] ?? ''}'.startsWith('7') && '${x['compte']}'.isNotEmpty) x], 'credit');
          return CpbLigneAnalytique(cc.$1, cc.$2, sel.length, ch, pr);
        }()
    ];

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// BUDGETS
// ---------------------------------------------------------------------------------------------------------------------------------------------------

/// `realise(centreId)` : les débits de classe 6 du centre, sur les écritures de l'exercice choisi — QUELLE QUE SOIT la date du budget (écart E774).
double cpbRealise(Iterable<CpaFiche> ecritures, Object? centreId) =>
    _som([for (final x in ecritures) if (x['centreCout'] == centreId && '${x['compte'] ?? ''}'.startsWith('6')) x], 'debit');

/// La consommation d'un budget : `Math.round(réalisé / prévu × 100)`, 0 sans prévision.
int cpbConsommation(double prevu, double realise) => prevu != 0 ? arrondiJs(realise / prevu * 100).toInt() : 0;

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// IMMOBILISATIONS
// ---------------------------------------------------------------------------------------------------------------------------------------------------

const int cpbMoisSemestre = 6;

DateTime? _jour(Object? d) => DateTime.tryParse('${d ?? ''}');

/// Les comptes d'immobilisation proposés à la saisie : ceux de la classe 2 du plan STATIQUE (`D.PLAN_COMPTABLE`), (numéro, intitulé).
List<(String, String)> cpbComptesImmobilisation() => [
      for (final p in cpaPlanComptable)
        if (p.$3 == 2) (p.$1, p.$2)
    ];

/// `cede(im)` : une date de sortie OU l'état « Cédé ».
bool cpbCede(CpaFiche im) => ('${im['dateCession'] ?? ''}').isNotEmpty || im['etat'] == 'Cédé';

/// `semestresTotal` : la durée en années × 2, au moins un.
int cpbSemestresTotal(CpaFiche im) {
  final d = _n(im['dureeAmortissement']);
  final k = arrondiJs((d == 0 ? 1 : d) * 12 / cpbMoisSemestre).toInt();
  return k < 1 ? 1 : k;
}

/// `dotationSemestre` : la valeur d'acquisition répartie sur les semestres, arrondie.
double cpbDotationSemestre(CpaFiche im) => arrondiJs(_n(im['valeurAcquisition']) / cpbSemestresTotal(im));

/// `moisEcoules` : de la date d'acquisition au terme (la date de cession si le bien est sorti, sinon aujourd'hui), en mois pleins.
int cpbMoisEcoules(CpaFiche im, DateTime aujourdhui) {
  final d = _jour(im['dateAcquisition']);
  if (d == null) return 0;
  final cession = ('${im['dateCession'] ?? ''}').isEmpty ? null : _jour(im['dateCession']);
  final f = cession ?? aujourdhui;
  var m = (f.year - d.year) * 12 + (f.month - d.month);
  if (f.day < d.day) m--;
  return m < 0 ? 0 : m;
}

int cpbSemestresEcoules(CpaFiche im, DateTime aujourdhui) {
  final k = cpbMoisEcoules(im, aujourdhui) ~/ cpbMoisSemestre;
  final t = cpbSemestresTotal(im);
  return k < t ? k : t;
}

int cpbAnneesEcoulees(CpaFiche im, DateTime aujourdhui) => cpbMoisEcoules(im, aujourdhui) ~/ 12;

/// `amortiCumule` : le dernier semestre SOLDE le reliquat — la somme des dotations fait exactement la valeur d'acquisition, à l'arrondi près.
double cpbAmortiCumule(CpaFiche im, DateTime aujourdhui) {
  final n = cpbSemestresEcoules(im, aujourdhui);
  if (n >= cpbSemestresTotal(im)) return _n(im['valeurAcquisition']);
  return cpbDotationSemestre(im) * n;
}

/// `vnc` : valeur nette comptable, jamais négative.
double cpbVnc(CpaFiche im, DateTime aujourdhui) {
  final v = _n(im['valeurAcquisition']) - cpbAmortiCumule(im, aujourdhui);
  return v < 0 ? 0 : v;
}

class CpbLignePlan {
  const CpbLignePlan(this.rang, this.periode, this.base, this.dotation, this.cumul, this.vnc, this.couru);
  final int rang;
  final String periode;
  final double base, dotation, cumul, vnc;
  final bool couru;
}

/// `planAmortissement` : semestre par semestre ; « S1 » / « S2 » se lit sur le mois du DÉBUT du semestre, compté depuis la date d'acquisition.
List<CpbLignePlan> cpbPlanAmortissement(CpaFiche im, DateTime aujourdhui) {
  final plan = <CpbLignePlan>[];
  final val = _n(im['valeurAcquisition']);
  var reste = val;
  final total = cpbSemestresTotal(im);
  final d = _jour(im['dateAcquisition']) ?? aujourdhui;
  final ecoules = cpbSemestresEcoules(im, aujourdhui);
  for (var s = 1; s <= total; s++) {
    final dot = s == total ? reste : cpbDotationSemestre(im);
    reste -= dot;
    final debut = DateTime(d.year, d.month + (s - 1) * cpbMoisSemestre, 1);
    plan.add(CpbLignePlan(s, 'S${debut.month <= 6 ? 1 : 2} ${debut.year}', val, dot, val - reste, reste, s <= ecoules));
  }
  return plan;
}

/// Les rubriques de l'actif immobilisé du bilan (liasse DGI) et le préfixe de compte qui y mène : (réf., famille, libellé, comptes).
/// « 229 Immobilisations en cours » n'est PAS un terrain : le préfixe 22 seul l'y aurait rangé.
const List<(String, String, String, List<String>)> cpbRubriquesBilanImmo = [
  ('AE', 'AD', 'Frais de développement et de prospection', ['211']),
  ('AF', 'AD', 'Brevets, licences, logiciels et droits similaires', ['212', '213', '214']),
  ('AG', 'AD', 'Fonds commercial et droit au bail', ['215', '216']),
  ('AH', 'AD', 'Autres immobilisations incorporelles', ['217', '218']),
  ('AJ', 'AI', 'Terrains', ['221', '222', '223', '224', '225', '226', '227', '228']),
  ('AK', 'AI', 'Bâtiments', ['231', '232', '233', '234']),
  ('AL', 'AI', 'Aménagements, agencements et installations', ['235', '237', '238']),
  ('AM', 'AI', 'Matériel, mobilier et actifs biologiques', ['241', '243', '244', '246', '247', '248']),
  ('AN', 'AI', 'Matériel de transport', ['245']),
  ('AR', 'AQ', 'Titres de participation', ['26']),
  ('AS', 'AQ', 'Autres immobilisations financières', ['27']),
];

/// (réf., libellé) des trois familles : sous-totaux AD, AI et AQ du formulaire.
const List<(String, String)> cpbFamillesBilanImmo = [
  ('AD', 'IMMOBILISATIONS INCORPORELLES'),
  ('AI', 'IMMOBILISATIONS CORPORELLES'),
  ('AQ', 'IMMOBILISATIONS FINANCIÈRES'),
];

/// `rubriqueBilanDe(im)` : l'index de la rubrique du bien, par le COMPTE d'immobilisation ; `null` : compte non rattaché.
int? cpbRubriqueBilanDe(CpaFiche im) {
  final num = '${im['compte'] ?? ''}';
  for (var i = 0; i < cpbRubriquesBilanImmo.length; i++) {
    for (final p in cpbRubriquesBilanImmo[i].$4) {
      if (num.startsWith(p)) return i;
    }
  }
  return null;
}

class CpbLigneReport {
  const CpbLigneReport(this.ref, this.libelle, this.nb, this.brut, this.amort, this.net, {this.sousTotal = false});
  final String ref, libelle;
  final int nb;
  final double brut, amort, net;
  final bool sousTotal;
}

({int nb, double brut, double amort, double net}) _chiffrer(List<CpaFiche> sel, DateTime auj) => (
      nb: sel.length,
      brut: _som(sel, 'valeurAcquisition'),
      amort: sel.fold<double>(0, (a, i) => a + cpbAmortiCumule(i, auj)),
      net: sel.fold<double>(0, (a, i) => a + cpbVnc(i, auj)),
    );

/// `blocReportBilan` : le report à l'actif immobilisé, dans l'ORDRE DE LA LIASSE — chaque famille, son sous-total, puis le total (AZ). Une rubrique vide
/// reste affichée (le formulaire les porte toutes) ; un bien SORTI n'y figure pas ; un compte sans rubrique est NOMMÉ.
({List<CpbLigneReport> lignes, CpbLigneReport total, int sorties, int auBilan}) cpbReportBilan(List<CpaFiche> biens, DateTime auj) {
  final auBilan = [for (final i in biens) if (!cpbCede(i)) i];
  final sorties = biens.length - auBilan.length;
  final lignes = <CpbLigneReport>[];
  for (final f in cpbFamillesBilanImmo) {
    final deLaFamille = [
      for (final i in auBilan)
        if (cpbRubriqueBilanDe(i) != null && cpbRubriquesBilanImmo[cpbRubriqueBilanDe(i)!].$2 == f.$1) i
    ];
    final c = _chiffrer(deLaFamille, auj);
    lignes.add(CpbLigneReport(f.$1, f.$2, c.nb, c.brut, c.amort, c.net, sousTotal: true));
    for (var k = 0; k < cpbRubriquesBilanImmo.length; k++) {
      final r = cpbRubriquesBilanImmo[k];
      if (r.$2 != f.$1) continue;
      final cc = _chiffrer([for (final i in auBilan) if (cpbRubriqueBilanDe(i) == k) i], auj);
      lignes.add(CpbLigneReport(r.$1, r.$3, cc.nb, cc.brut, cc.amort, cc.net));
    }
  }
  final hors = [for (final i in auBilan) if (cpbRubriqueBilanDe(i) == null) i];
  if (hors.isNotEmpty) {
    final c = _chiffrer(hors, auj);
    lignes.add(CpbLigneReport('—', 'Compte non rattaché à une rubrique du bilan', c.nb, c.brut, c.amort, c.net));
  }
  final t = _chiffrer(auBilan, auj);
  return (lignes: lignes, total: CpbLigneReport('AZ', 'TOTAL ACTIF IMMOBILISÉ', t.nb, t.brut, t.amort, t.net), sorties: sorties, auBilan: auBilan.length);
}

/// Les trois totaux du registre (indicateurs) : les biens SORTIS en sont exclus — un bien cédé n'est plus au patrimoine.
({double brut, double amort, double net, int sorties}) cpbTotauxImmobilisations(List<CpaFiche> rows, DateTime auj) {
  final c = _chiffrer([for (final i in rows) if (!cpbCede(i)) i], auj);
  return (brut: c.brut, amort: c.amort, net: c.net, sorties: rows.where(cpbCede).length);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// BANQUES
// ---------------------------------------------------------------------------------------------------------------------------------------------------

/// `m12-banques` : « Sans écart » / « Avec écart » comptent le `statutRappro` des rapprochements actifs.
({int effectues, int sansEcart, int avecEcart}) cpbBilanRapprochements(Iterable<CpaFiche> rapprochements) => (
      effectues: rapprochements.length,
      sansEcart: rapprochements.where((r) => r['statutRappro'] == 'rapproche').length,
      avecEcart: rapprochements.where((r) => r['statutRappro'] == 'ecart').length,
    );

/// La phrase de l'état imprimé d'un rapprochement : l'écart se justifie puis se régularise par une écriture d'opérations diverses.
String cpbPhraseRapprochement(double ecart) => ecart == 0
    ? 'Le rapprochement ne fait apparaître aucun écart : la comptabilité et le relevé bancaire concordent.'
    : 'Un écart de ${money(ecart.abs())} est constaté. Il doit être justifié (chèques en circulation, virements non encore comptabilisés, frais bancaires) puis régularisé par écriture d’opérations diverses.';
