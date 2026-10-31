/// BASELINE FINANCIÈRE 2025 (M12, `m12-baseline-2025`) — port de `m12-comptabilite.js` et de `data-compta.js` (`EXERCICE_2025`).
///
/// Le compte de résultat 2025 n'est pas un simple archivage : c'est la RÉFÉRENCE DE COMPARAISON des tableaux de bord (2025 réel / 2026 réel / budget 2026).
/// Le DIAGNOSTIC DES ÉCARTS DU CLASSEUR est CALCULÉ à chaque affichage, jamais écrit en dur : `npm run compta` régénère `data-compta.js` depuis l'Excel,
/// et un montant codé ici serait faux à la première régénération. Les données du classeur sont ENGENDRÉES (`cpc_donnees.dart`), jamais recopiées.
library;

import 'dart:convert';

import '../format/js.dart';
import '../format/recherche.dart' show trierPar;
import 'cpc_donnees.dart';

typedef CpcPoste = Map<String, Object?>;

double _n(Object? v) => nombreOuZero(v);

/// Un poste du classeur 2025 : compte (vide si « à rattacher »), libellé, douze mois, total.
class CpcPosteCharge {
  CpcPosteCharge(Map<String, Object?> j)
      : num = j['num'] == null || j['num'] == '' ? null : '${j['num']}',
        libelle = '${j['libelle']}',
        mois = [for (final x in (j['mois'] as List)) _n(x)],
        total = _n(j['total']);
  final String? num;
  final String libelle;
  final List<double> mois;
  final double total;
}

/// Le contrôle relevé sur le classeur source : total du détail, total de la ligne « TOTAL », écart, postes sans compte.
class CpcControleClasseur {
  CpcControleClasseur(Map<String, Object?> j)
      : totalDetail = _n(j['totalDetail']),
        totalClasseur = _n(j['totalClasseur']),
        ecart = _n(j['ecart']),
        postesSansCompte = _n(j['postesSansCompte']).toInt(),
        montantSansCompte = _n(j['montantSansCompte']);
  final double totalDetail, totalClasseur, ecart, montantSansCompte;
  final int postesSansCompte;
}

class CpcExercice2025 {
  CpcExercice2025(Map<String, Object?> j)
      : annee = j['annee'] as int,
        mois = [for (final m in (j['mois'] as List)) '$m'],
        chiffreAffaires = [for (final x in (j['chiffreAffaires'] as List)) _n(x)],
        totalChiffreAffaires = _n(j['totalChiffreAffaires']),
        depenses = [for (final d in (j['depenses'] as List)) CpcPosteCharge((d as Map).cast<String, Object?>())],
        horsExploitation = (j['horsExploitation'] as Map).cast<String, Object?>(),
        totalHorsExploitation = _n(j['totalHorsExploitation']),
        totalCharges = _n(j['totalCharges']),
        resultat = _n(j['resultat']),
        controle = CpcControleClasseur((j['controle'] as Map).cast<String, Object?>());
  final int annee;
  final List<String> mois;
  final List<double> chiffreAffaires;
  final double totalChiffreAffaires, totalHorsExploitation, totalCharges, resultat;
  final List<CpcPosteCharge> depenses;
  final Map<String, Object?> horsExploitation;
  final CpcControleClasseur controle;

  bool _exploitation(CpcPosteCharge d) => !horsExploitation.containsKey(d.num);

  /// `chargesDuMois(i)` : les charges d'exploitation du mois (index 0 = janvier) — les postes de bilan en sont exclus.
  double chargesDuMois(int i) => depenses.where(_exploitation).fold(0.0, (a, d) => a + d.mois[i]);

  /// `resultatDuMois(i)` : chiffre d'affaires moins charges d'exploitation.
  double resultatDuMois(int i) => chiffreAffaires[i] - chargesDuMois(i);

  /// `postesCharges()` : les postes d'exploitation par poids décroissant (tri STABLE, comme `Array.sort`).
  List<CpcPosteCharge> postesCharges() => trierPar([...depenses.where(_exploitation)], (d) => d.total, descendant: true);

  int get indiceMeilleurMois => _indiceDe(chiffreAffaires.reduce((a, b) => a > b ? a : b));
  int get indiceMoisFaible => _indiceDe(chiffreAffaires.reduce((a, b) => a < b ? a : b));
  int _indiceDe(double v) => chiffreAffaires.indexOf(v);
}

CpcExercice2025? _e25;

/// Le compte de résultat 2025 du classeur (engendré depuis `data-compta.js`).
CpcExercice2025 get cpcExercice2025 =>
    _e25 ??= CpcExercice2025((jsonDecode(cpcExercice2025Json) as Map).cast<String, Object?>());

/// Le diagnostic de l'écart du classeur : les lignes dont une ÉCHÉANCE MENSUELLE vaut exactement l'écart (l'explication, si elle existe), celles dont le
/// total vaut l'écart, et les lignes qui ne somment pas à leur propre total (alors l'écart vient du détail et non de la ligne TOTAL).
class CpcDiagnostic {
  const CpcDiagnostic(this.ecart, this.mensuelles, this.totales, this.incoherentes);
  final double ecart;
  final List<({CpcPosteCharge ligne, List<int> mois})> mensuelles;
  final List<CpcPosteCharge> totales, incoherentes;
}

/// `expliquerEcart(E)` : `null` si le classeur ne présente aucun écart.
CpcDiagnostic? cpcExpliquerEcart(CpcExercice2025 e) {
  final ecart = e.controle.ecart.abs();
  if (ecart == 0) return null;
  final mensuelles = <({CpcPosteCharge ligne, List<int> mois})>[];
  final totales = <CpcPosteCharge>[];
  for (final d in e.depenses) {
    final mois = [for (var i = 0; i < d.mois.length; i++) if (arrondiJs(d.mois[i]) == ecart) i];
    if (mois.isNotEmpty) mensuelles.add((ligne: d, mois: mois));
    if (arrondiJs(d.total) == ecart) totales.add(d);
  }
  final incoherentes = [
    for (final d in e.depenses)
      if (arrondiJs((d.mois.fold(0.0, (a, b) => a + b) - d.total) * 100) != 0) d
  ];
  return CpcDiagnostic(ecart, mensuelles, totales, incoherentes);
}

/// Le rattachement PROPOSÉ d'un poste sans numéro de compte : une PROPOSITION à valider par le service comptable, jamais une imputation appliquée —
/// rattacher d'office un montant à un compte fausserait la balance sans que personne ne l'ait décidé.
class CpcProposition {
  const CpcProposition(this.compte, this.intitule, this.motif);
  final String compte, intitule, motif;
}

const Map<String, CpcProposition> cpcComptesProposes = {
  'FONDS DE GARANTIE': CpcProposition('275000', 'Dépôts et cautionnements versés',
      'Un fonds de garantie adossé à un emprunt est un dépôt, non une charge. Le classeur porte déjà ce compte pour ses autres cautionnements.'),
  'FRAIS DOSSIER SUR EMPRUNT': CpcProposition('631800', 'Autres frais bancaires',
      'Frais perçus par la banque à l’ouverture du dossier : même nature que les comptes 631810, 631820 et 631830 déjà utilisés par le classeur.'),
  'TAXE SUR EMPRUNT': CpcProposition('646800', 'Autres droits',
      'Droit assis sur l’emprunt, de même nature que la cotisation CCIB déjà imputée à ce compte dans le classeur.'),
};

CpcProposition? cpcPropositionCompte(String? libelle) => cpcComptesProposes[(libelle ?? '').trim().toUpperCase()];

/// La comparaison mensuelle 2025 (réel) / 2026 (jeu du poste) : le chiffre d'affaires 2026 est la somme des `montantTTC` des factures actives du mois.
/// L'année 2026 est CELLE DE LA MAQUETTE (écrite en dur) : porté fidèlement (écart E803).
class CpcComparaisonMois {
  const CpcComparaisonMois(this.mois, this.ca2025, this.ca2026, this.ecart, this.evolution);
  final String mois;
  final double ca2025, ca2026, ecart;
  final int evolution;
}

List<CpcComparaisonMois> cpcComparaison(CpcExercice2025 e, Iterable<Map<String, Object?>> facturesActives) => [
      for (var i = 0; i < e.mois.length; i++)
        () {
          final ca2026 = facturesActives.where((f) {
            final d = DateTime.tryParse('${f['date']}');
            return d != null && d.year == 2026 && d.month == i + 1;
          }).fold(0.0, (a, f) => a + _n(f['montantTTC']));
          final ca2025 = e.chiffreAffaires[i];
          return CpcComparaisonMois('${e.mois[i][0].toUpperCase()}${e.mois[i].substring(1)}', ca2025, ca2026, ca2026 - ca2025,
              ca2025 != 0 ? arrondiJs((ca2026 - ca2025) / ca2025 * 100).toInt() : 0);
        }()
    ];

/// La marge mensuelle de l'onglet « Détail mensuel » : `Math.round(résultat / CA × 100)`.
int cpcMargeMois(CpcExercice2025 e, int i) =>
    e.chiffreAffaires[i] != 0 ? arrondiJs(e.resultatDuMois(i) / e.chiffreAffaires[i] * 100).toInt() : 0;
