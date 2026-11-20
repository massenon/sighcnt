/// ÉCRITURES, JOURNAUX, GRAND LIVRE, BALANCE ET TABLEAU DE BORD COMPTABLE (M12) — port de `m12-comptabilite.js`
/// (m12-dashboard, m12-journaux, m12-ecritures, m12-grand-livre, m12-balance).
///
/// Tout est CALCULÉ depuis les écritures de l'exercice : rien n'est fourni. Les règles se rejouent sur `test/vecteurs/comptabilite.json`, tiré des écrans
/// réels de la maquette.
///
/// RG-10 : une écriture se VALIDE équilibrée (débit = crédit) ; un brouillon peut ne pas l'être (la maquette l'accepte, et la validation le refuse).
/// Une PIÈCE est l'ensemble des lignes de même numéro : on la valide et on l'archive ENTIÈRE (écarts E710 et E716, corrigés dans la maquette d'abord).
library;

import '../format/format_fr.dart';
import '../format/js.dart';
import '../format/recherche.dart' show trierPar;
import 'cpa_referentiels.dart';

/// Refus NOMMÉ : un refus se lit, il ne se devine pas. Rien n'est écrit.
class CpaRefus implements Exception {
  const CpaRefus(this.message, [this.detail]);
  final String message;
  final String? detail;
  @override
  String toString() => detail == null ? message : '$message $detail';
}

double _n(Object? v) => nombreOuZero(v);
double _som(Iterable<CpaFiche> l, String k) => l.fold<double>(0, (a, x) => a + _n(x[k]));

/// L'année d'une date `YYYY-MM-DD…` (`C.toDate(d).getFullYear()`), `null` si illisible.
int? cpaAnnee(Object? date) {
  final d = DateTime.tryParse('${date ?? ''}');
  return d?.year;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// EXERCICES — ce que le poste sait de `SIGH.exercice` (sélecteur et clôture non portés : voir ECARTS-MAQUETTE E717)
// ---------------------------------------------------------------------------------------------------------------------------------------------------

/// La liasse DÉPOSÉE à la DGI (data-liasse.js `DEPOT`) : les exercices 2024 et 2025 sont CLOS d'office, faits par la liasse.
const int cpaLiasseExerciceN = 2025;
const int cpaLiasseExerciceN1 = 2024;
const String cpaLiasseDateDepot = '2026-05-15';

/// `exercice(annee).etat` : `clos` pour les deux exercices de la liasse déposée, `ouvert` sinon. Les clôtures VALIDÉES au poste (deux gestes) ne sont
/// pas portées : aucune n'existe au jeu.
String cpaEtatExercice(int annee) =>
    annee == cpaLiasseExerciceN || annee == cpaLiasseExerciceN1 ? 'clos' : 'ouvert';

/// La garde de lecture seule POSÉE SUR LA COLLECTION `ecritures` (`S.garder`) : le motif du refus, ou `null`. Toute écriture dont la date tombe dans un
/// exercice clos est refusée, d'où qu'elle vienne.
String? cpaGardeEcriture(Object? date) {
  final a = cpaAnnee(date);
  if (a == null || cpaEtatExercice(a) != 'clos') return null;
  final fin = DateTime.parse(cpaLiasseDateDepot);
  return 'Exercice $a clos le ${dateFR(fin)} — lecture seule. La correction passe par une écriture de l’exercice en cours.';
}

/// `ecritures()` : les écritures de l'exercice choisi. Les à-nouveaux PROVISOIRES sont vides tant que l'exercice précédent est celui de la liasse
/// déposée (il est clos d'office, `provisoires` rend `[]`).
List<CpaFiche> cpaEcrituresExercice(Iterable<CpaFiche> actives, int annee) =>
    [for (final e in actives) if (cpaAnnee(e['date']) == annee) e];

/// `soldeCompte(num)`.
({double debit, double credit, double solde, int nb}) cpaSoldeCompte(
    Iterable<CpaFiche> ecritures, String compte) {
  final e = [for (final x in ecritures) if (x['compte'] == compte) x];
  final d = _som(e, 'debit'), c = _som(e, 'credit');
  return (debit: d, credit: c, solde: d - c, nb: e.length);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// TABLEAU DE BORD
// ---------------------------------------------------------------------------------------------------------------------------------------------------

class CpaTableauDeBord {
  const CpaTableauDeBord({
    required this.tresorerie,
    required this.chiffreAffaires,
    required this.charges,
    required this.clients,
    required this.fournisseurs,
    required this.nbEcritures,
    required this.totalDebit,
    required this.totalCredit,
    required this.brouillons,
  });
  final double tresorerie, chiffreAffaires, charges, clients, fournisseurs;
  final int nbEcritures, brouillons;
  final double totalDebit, totalCredit;
  double get resultat => chiffreAffaires - charges;
  bool get equilibre => totalDebit == totalCredit;
  double get ecart => (totalDebit - totalCredit).abs();
}

/// Les huit indicateurs du tableau de bord : trésorerie = solde des comptes 571000 + 521000 ; CA = crédits de classe 7 ; charges = débits de classe 6 ;
/// créances clients = 411000 + 411200 ; dettes fournisseurs = |solde 401000|.
CpaTableauDeBord cpaTableauDeBord(List<CpaFiche> e) {
  bool classe(CpaFiche x, String c) => '${x['compte']}'.startsWith(c);
  double solde(String c) => cpaSoldeCompte(e, c).solde;
  return CpaTableauDeBord(
    tresorerie: solde('571000') + solde('521000'),
    chiffreAffaires: _som([for (final x in e) if (classe(x, '7')) x], 'credit'),
    charges: _som([for (final x in e) if (classe(x, '6')) x], 'debit'),
    clients: solde('411000') + solde('411200'),
    fournisseurs: solde('401000').abs(),
    nbEcritures: e.length,
    totalDebit: _som(e, 'debit'),
    totalCredit: _som(e, 'credit'),
    brouillons: e.where((x) => x['statut'] == 'brouillon').length,
  );
}

/// Un groupement `C.groupBy` : l'ordre des clés est celui de la PREMIÈRE apparition ; une clé absente se lit « undefined » (JavaScript).
Map<String, List<CpaFiche>> cpaGrouper(Iterable<CpaFiche> l, String cle) {
  final m = <String, List<CpaFiche>>{};
  for (final x in l) {
    (m['${x[cle] ?? 'undefined'}'] ??= []).add(x);
  }
  return m;
}

/// « Charges par centre de coûts » : les lignes de classe 6 au débit, par centre, du plus grand au plus petit (tri stable).
List<(String, double)> cpaChargesParCentre(List<CpaFiche> e, String Function(String) libelleCentre) {
  final g = cpaGrouper([for (final x in e) if (_n(x['debit']) > 0 && '${x['compte']}'.startsWith('6')) x], 'centreCout');
  final l = [for (final k in g.keys) (libelleCentre(k), _som(g[k]!, 'debit'))];
  final idx = [for (var i = 0; i < l.length; i++) i];
  idx.sort((a, b) {
    final c = l[b].$2.compareTo(l[a].$2);
    return c != 0 ? c : a.compareTo(b);
  });
  return [for (final i in idx) l[i]];
}

/// Les huit lignes du tableau « Automatisation des écritures » : (opération, module d'origine, journal, compte débité, compte crédité).
const List<(String, String, String, String, String)> cpaAutomatisations = [
  ('Encaissement d’une facture patient', 'M8 — Caisse', 'CAI', '571000', '411000'),
  ('Facturation d’une prestation', 'M8 — Facturation', 'VTE', '411000', '706000'),
  ('Vente de médicaments', 'M6 — Pharmacie', 'VTE', '411000', '701000'),
  ('Réception d’une commande', 'M7 — Achats', 'ACH', '601100', '401000'),
  ('Facture assureur', 'M9 — Assurances', 'VTE', '411200', '706000'),
  ('Salaires du mois', 'M11 — Paie', 'SAL', '661100', '422000'),
  ('Cotisations CNSS', 'M11 — Paie', 'SAL', '641200', '431000'),
  ('Perte ou casse de stock', 'M6 — Stock', 'OD', '651100', '311000'),
];

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// JOURNAUX
// ---------------------------------------------------------------------------------------------------------------------------------------------------

class CpaLigneJournal {
  const CpaLigneJournal(this.code, this.libelle, this.contrepartie, this.nb, this.debit, this.credit);
  final String code, libelle;
  final String? contrepartie;
  final int nb;
  final double debit, credit;
  bool get equilibre => debit == credit;
  double get ecart => (debit - credit).abs();
}

/// La vue des écritures d'une nature donnée : un journal ne se saisit pas.
List<CpaLigneJournal> cpaLignesJournaux(List<CpaFiche> e) => [
      for (final j in cpaJournaux)
        () {
          final sel = [for (final x in e) if (x['journal'] == j.$1) x];
          return CpaLigneJournal(j.$1, j.$2, j.$3, sel.length, _som(sel, 'debit'), _som(sel, 'credit'));
        }()
    ];

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// BALANCE
// ---------------------------------------------------------------------------------------------------------------------------------------------------

class CpaLigneBalance {
  const CpaLigneBalance(this.num, this.libelle, this.classe, this.debit, this.credit, this.nb);
  final String num, libelle;
  final int classe;
  final double debit, credit;
  final int nb;
  double get soldeDebiteur => debit - credit > 0 ? debit - credit : 0;
  double get soldeCrediteur => debit - credit < 0 ? credit - debit : 0;
}

/// La balance : UNE ligne par numéro de compte du plan, ceux qui n'ont aucun mouvement sont écartés. Calculée sur TOUTES les écritures de l'exercice,
/// brouillons compris — comme la maquette, dont le bandeau dit pourtant « écritures validées » (écart E718, porté fidèlement et dit).
/// Écart E725 (corrigé dans la maquette d'abord) : deux fiches du plan au même numéro (631810) faisaient compter deux fois les mouvements du compte, et la
/// balance annonçait un déséquilibre RG-10 de 1 954 000 F que le journal ne porte pas.
List<CpaLigneBalance> cpaBalance(Iterable<CpaFiche> comptes, List<CpaFiche> e) {
  final vus = <String>{};
  return [
    for (final c in comptes)
      if (vus.add('${c['num']}'))
        () {
          final s = cpaSoldeCompte(e, '${c['num']}');
          return s.nb == 0
              ? null
              : CpaLigneBalance('${c['num']}', '${c['libelle']}', _n(c['classe']).toInt(), s.debit, s.credit, s.nb);
        }()
  ].whereType<CpaLigneBalance>().toList();
}

class CpaTrancheAgee {
  const CpaTrancheAgee(this.libelle, this.nbPatients, this.montantPatients, this.nbAssureurs, this.montantAssureurs);
  final String libelle;
  final int nbPatients, nbAssureurs;
  final double montantPatients, montantAssureurs;
  double get total => montantPatients + montantAssureurs;
}

/// `C.daysBetween(a, b)` : `Math.round((b − a) / 86 400 000)`, dates lues à minuit local.
int cpaJoursEntre(Object? a, DateTime b) {
  final d = DateTime.tryParse('${a ?? ''}');
  if (d == null) return 0;
  final x = DateTime(d.year, d.month, d.day, d.hour, d.minute, d.second);
  return arrondiJs(b.difference(x).inMilliseconds / 86400000).toInt();
}

/// La balance âgée des comptes de tiers, lue sur les FACTURES : patients (reliquat > 0) et assureurs (toute facture assurée, part assureur) par tranche
/// d'ancienneté. [auj] : l'horloge du poste.
List<CpaTrancheAgee> cpaBalanceAgee(Iterable<CpaFiche> factures, DateTime auj) {
  const tranches = [
    ('Moins de 30 jours', 0, 30),
    ('30 à 60 jours', 30, 60),
    ('60 à 90 jours', 60, 90),
    ('Plus de 90 jours', 90, 99999),
  ];
  return [
    for (final t in tranches)
      () {
        bool dans(CpaFiche f) {
          final j = cpaJoursEntre(f['date'], auj);
          return j >= t.$2 && j < t.$3;
        }

        final sel = [for (final f in factures) if (_n(f['reliquat']) > 0 && dans(f)) f];
        final selAss = [for (final f in factures) if (f['assureur'] != null && f['assureur'] != '' && dans(f)) f];
        return CpaTrancheAgee(t.$1, sel.length, _som(sel, 'reliquat'), selAss.length, _som(selAss, 'partAssurance'));
      }()
  ];
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// GRAND LIVRE
// ---------------------------------------------------------------------------------------------------------------------------------------------------

/// Le grand livre d'un compte : mouvements triés par date (stable), avec `soldeProgressif`.
List<CpaFiche> cpaGrandLivre(List<CpaFiche> e, String compte) {
  final mv = trierPar([for (final x in e) if (x['compte'] == compte) x], (x) => x['date']);
  var solde = 0.0;
  return [
    for (final x in mv)
      {...x, 'soldeProgressif': solde += _n(x['debit']) - _n(x['credit'])}
  ];
}

/// Les comptes MOUVEMENTÉS (au moins une écriture dans l'exercice), triés par numéro, UNE entrée par numéro : la liste du grand livre (E724, corrigé
/// dans la maquette d'abord : le plan porte deux fiches au numéro 631810 et la liste proposait le compte deux fois).
List<CpaFiche> cpaComptesMouvementes(Iterable<CpaFiche> comptes, List<CpaFiche> e) {
  final vus = <String>{};
  return trierPar([for (final c in comptes) if (cpaSoldeCompte(e, '${c['num']}').nb > 0 && vus.add('${c['num']}')) c], (c) => c['num']);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// SAISIE D'UNE ÉCRITURE EN PARTIE DOUBLE
// ---------------------------------------------------------------------------------------------------------------------------------------------------

/// Les deux contrôles de la ligne qu'on ajoute : un montant, et un seul sens.
void cpaVerifierLigne(num debit, num credit) {
  if (debit == 0 && credit == 0) {
    throw const CpaRefus('Renseigner un montant au débit ou au crédit.');
  }
  if (debit > 0 && credit > 0) {
    throw const CpaRefus('Une ligne ne peut être simultanément au débit et au crédit.');
  }
}

/// Le rang suivant d'une pièce de la série `journal-exercice-` : le plus grand déjà écrit (lu sur TOUTES les fiches, archivées comprises), plus un
/// (E711 : « lignes actives + 1 » redonnait un numéro déjà attribué après un archivage).
String cpaNumeroPiece(String journal, int exercice, Iterable<CpaFiche> toutes) {
  final prefixe = '$journal-$exercice-';
  var max = 0;
  for (final x in toutes) {
    final n = '${x['numero'] ?? ''}';
    if (n.startsWith(prefixe)) {
      final k = int.tryParse(RegExp(r'^[+-]?\d+').firstMatch(n.substring(prefixe.length))?.group(0) ?? '') ?? 0;
      if (k > max) max = k;
    }
  }
  return '$prefixe${(max + 1).toString().padLeft(5, '0')}';
}

/// RG-10 sur un ensemble de lignes : le refus nomme l'écart.
void cpaControlerEquilibre(Iterable<CpaFiche> lignes, {String? piece}) {
  final td = _som(lignes, 'debit'), tc = _som(lignes, 'credit');
  if (td != tc) {
    throw CpaRefus('RG-10 — écriture déséquilibrée : validation impossible.',
        piece == null ? 'Écart de ${money((td - tc).abs())}.' : 'Pièce $piece : écart de ${money((td - tc).abs())}.');
  }
}

/// Les lignes plates d'une écriture saisie (une par ligne : même numéro, même date, un compte et un sens chacune), prêtes à insérer. [lignes] :
/// `{compte, debit, credit}` ; [toutes] : les écritures déjà écrites (archivées comprises, pour la numérotation) ; [exercice] : l'exercice choisi.
/// Refus nommés : aucune ligne, déséquilibre d'une écriture qu'on VALIDE (un brouillon déséquilibré est accepté), exercice clos.
List<CpaFiche> cpaEcrituresDeSaisie({
  required String date,
  required String journal,
  required String libelle,
  required String centreCout,
  required String piece,
  required List<CpaFiche> lignes,
  required String statut,
  required int exercice,
  required Iterable<CpaFiche> toutes,
}) {
  if (lignes.isEmpty) throw const CpaRefus('Ajouter au moins une ligne.');
  if (statut == 'validee') cpaControlerEquilibre(lignes);
  final motif = cpaGardeEcriture(date);
  if (motif != null) throw CpaRefus('Écriture refusée.', motif);
  final numero = cpaNumeroPiece(journal, exercice, toutes);
  return [
    for (final l in lignes)
      {
        'numero': numero,
        'date': date,
        'journal': journal,
        'journalLibelle': cpaJournalLibelle(journal),
        'compte': l['compte'],
        'compteLibelle': l['compteLibelle'] ?? cpaCompteLibelle(l['compte']),
        'libelle': libelle,
        'debit': _n(l['debit']),
        'credit': _n(l['credit']),
        'centreCout': centreCout,
        'piece': piece,
        'origine': 'Saisie manuelle',
        'statut': statut,
      }
  ];
}

/// Les lignes d'une même PIÈCE (même numéro) parmi [actives], dans l'ordre de la collection.
List<CpaFiche> cpaPiece(Iterable<CpaFiche> actives, Object? numero, {String? statut}) =>
    [for (final x in actives) if (x['numero'] == numero && (statut == null || x['statut'] == statut)) x];

/// Valider une pièce brouillon : RG-10 contrôlé sur l'ENSEMBLE des lignes de même numéro, AVANT. Rend les lignes à passer en `validee`.
List<CpaFiche> cpaValiderPiece(Iterable<CpaFiche> actives, CpaFiche ligne) {
  final piece = cpaPiece(actives, ligne['numero'], statut: 'brouillon');
  cpaControlerEquilibre(piece, piece: '${ligne['numero']}');
  return piece;
}
