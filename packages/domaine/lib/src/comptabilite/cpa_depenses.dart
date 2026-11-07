/// DÉPENSES JOURNALIÈRES (M12) — port de `m12-depenses` (m12-comptabilite.js, vague 35 puis arbitrage du 31/08/2026).
///
/// Une dépense de trésorerie directe constate une charge sans passer par un compte fournisseur. Elle produit UNE ÉCRITURE PLATE PAR LIGNE de même
/// numéro de pièce : un DÉBIT par ligne de charge (classe 6), un CRÉDIT de trésorerie (5xx) du TOTAL. Trois règles :
///   1. RG-10 : l'équilibre est contrôlé AVANT d'écrire ;
///   2. l'écriture naît en BROUILLON (la validation comptable reste un geste humain) ;
///   3. le justificatif n'est pas bloquant mais il est COMPTÉ et signalé.
/// Le total d'une pièce est la SOMME de ses lignes, jamais un nombre saisi à part.
library;

import '../format/js.dart';
import 'cpa_ecritures.dart';
import 'cpa_referentiels.dart';

double _n(Object? v) => nombreOuZero(v);

/// `lignesDe(dep)` : une pièce d'avant l'arbitrage (libellé + compte + montant en tête) se lit comme UNE ligne.
List<CpaFiche> cpaLignesDepense(CpaFiche dep) {
  final l = dep['lignes'];
  if (l is List && l.isNotEmpty) return [for (final x in l) (x as Map).cast<String, Object?>()];
  return [
    {'libelle': dep['libelle'], 'compteCharge': dep['compteCharge'], 'montant': _n(dep['montant'])}
  ];
}

typedef CpaTotauxDepense = ({List<CpaFiche> lignes, double montant, String libelle, String compteCharge});

/// `totauxDepuisLignes` : la pièce exige au moins une ligne ; le montant est la somme des lignes ; l'objet se reprend de la première ligne s'il est
/// vide (« … (+N autre(s)) »).
CpaTotauxDepense cpaTotauxDepense(String objet, List<CpaFiche> lignes) {
  if (lignes.isEmpty) throw const CpaRefus('La pièce exige au moins une ligne de dépense.');
  final premier = '${lignes.first['libelle']}';
  return (
    lignes: lignes,
    montant: lignes.fold<double>(0, (a, l) => a + _n(l['montant'])),
    libelle: objet.trim().isNotEmpty
        ? objet.trim()
        : premier + (lignes.length > 1 ? ' (+${lignes.length - 1} autre(s))' : ''),
    compteCharge: '${lignes.first['compteCharge']}',
  );
}

/// `C.referenceSuivante('DEP-AAAA-', 4, dépenses)` : le plus grand rang déjà écrit, plus un (E712 : la maquette lisait un compteur de page).
String cpaReferenceDepense(String date, Iterable<CpaFiche> toutes) {
  final prefixe = 'DEP-${cpaAnnee(date)}-';
  var max = 0;
  for (final f in toutes) {
    final r = '${f['reference'] ?? ''}';
    if (r.startsWith(prefixe)) {
      final k = int.tryParse(RegExp(r'^[+-]?\d+').firstMatch(r.substring(prefixe.length))?.group(0) ?? '') ?? 0;
      if (k > max) max = k;
    }
  }
  return '$prefixe${(max + 1).toString().padLeft(4, '0')}';
}

/// `poserEcriture(dep)` : les lignes plates de l'écriture, EN BROUILLON. [tresorerie] : la fiche `banques` du compte de sortie (`null` : caisse 571000).
/// RG-10 est contrôlé AVANT d'écrire ; la garde de l'exercice clos refuse en nommant l'exercice (E714 : refus dit AVANT toute écriture).
/// Le journal est `CAI` pour une caisse, `BQE` sinon — code ABSENT de `D.JOURNAUX` (écart E719, porté fidèlement).
List<CpaFiche> cpaEcrituresDepense(CpaFiche dep, CpaFiche? tresorerie) {
  final motif = cpaGardeEcriture(dep['date']);
  if (motif != null) throw CpaRefus('Écriture refusée.', motif);
  final caisse = tresorerie != null && tresorerie['nature'] == 'caisse';
  final base = <String, Object?>{
    'numero': dep['reference'],
    'date': dep['date'],
    'journal': caisse ? 'CAI' : 'BQE',
    'journalLibelle': caisse ? 'Journal de caisse-dépenses' : 'Journal de banque',
    'libelle': dep['libelle'],
    'pieceId': dep['id'],
    'pieceNumero': dep['reference'],
    'origine': 'Dépense journalière',
    'statut': 'brouillon',
  };
  final montant = _n(dep['montant']);
  final intitule = tresorerie == null ? null : '${tresorerie['intitule']}';
  final lignes = <CpaFiche>[
    for (final l in cpaLignesDepense(dep))
      {
        ...base,
        'compte': l['compteCharge'],
        'compteLibelle': cpaCompteLibelle(l['compteCharge']),
        'libelle': l['libelle'],
        'debit': _n(l['montant']),
        'credit': 0,
      },
    {
      ...base,
      'compte': tresorerie != null ? tresorerie['compteComptable'] : '571000',
      'compteLibelle': tresorerie != null ? intitule : 'Caisse',
      'libelle': 'Décaissement — ${tresorerie != null ? intitule : 'trésorerie'}',
      'debit': 0,
      'credit': montant,
    },
  ];
  final d = lignes.fold<double>(0, (a, l) => a + _n(l['debit']));
  final c = lignes.fold<double>(0, (a, l) => a + _n(l['credit']));
  if (d != c) throw CpaRefus('Écriture refusée.', 'RG-10 — débit ${cpaMontant(d)} contre crédit ${cpaMontant(c)}.');
  return lignes;
}

/// Les quatre indicateurs (pas cinq : la « dépense moyenne » est retirée, arbitrage du 31/08/2026) sur les dépenses [rows] retenues par la plage.
class CpaIndicateursDepenses {
  const CpaIndicateursDepenses(
      {required this.duJour, required this.nbJour, required this.duMois, required this.nbMois, required this.total, required this.nb, required this.sansRecu, required this.nbSansRecu});
  final double duJour, duMois, total, sansRecu;
  final int nbJour, nbMois, nb, nbSansRecu;
}

CpaIndicateursDepenses cpaIndicateursDepenses(List<CpaFiche> rows, String jour) {
  double som(Iterable<CpaFiche> l) => l.fold<double>(0, (a, x) => a + _n(x['montant']));
  bool recu(CpaFiche r) => r['justificatif'] != null;
  final j = [for (final r in rows) if (r['date'] == jour) r];
  final m = [for (final r in rows) if ('${r['date']}'.length >= 7 && '${r['date']}'.substring(0, 7) == jour.substring(0, 7)) r];
  final s = [for (final r in rows) if (!recu(r)) r];
  return CpaIndicateursDepenses(
      duJour: som(j), nbJour: j.length, duMois: som(m), nbMois: m.length, total: som(rows), nb: rows.length, sansRecu: som(s), nbSansRecu: s.length);
}

const _mois = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];

/// « Dépenses par mois » : (étiquette « févr 26 », montant) par mois présent, triés par mois.
List<(String, double)> cpaDepensesParMois(List<CpaFiche> rows) {
  final par = <String, double>{};
  for (final r in rows) {
    final d = '${r['date']}';
    if (d.length < 7) continue;
    par[d.substring(0, 7)] = (par[d.substring(0, 7)] ?? 0) + _n(r['montant']);
  }
  final cles = par.keys.toList()..sort();
  return [
    for (final k in cles)
      (
        () {
          final i = (int.tryParse(k.split('-')[1]) ?? 0) - 1;
          final nom = i >= 0 && i < 12 ? _mois[i] : k;
          return '${nom.length > 4 ? nom.substring(0, 4) : nom} ${k.substring(2, 4)}';
        }(),
        par[k]!
      )
  ];
}

/// « Cumul par catégorie » : (catégorie, nombre, total) du plus grand au plus petit (tri stable ; clé absente = « undefined »).
List<({String id, String libelle, double total, int nombre})> cpaCumulCategories(List<CpaFiche> rows) {
  final g = cpaGrouper(rows, 'categorie');
  final l = [
    for (final k in g.keys)
      (id: k, libelle: cpaCategorieDepenseLibelle(k), total: g[k]!.fold<double>(0, (a, x) => a + _n(x['montant'])), nombre: g[k]!.length)
  ];
  final idx = [for (var i = 0; i < l.length; i++) i]..sort((a, b) {
      final c = l[b].total.compareTo(l[a].total);
      return c != 0 ? c : a.compareTo(b);
    });
  return [for (final i in idx) l[i]];
}
