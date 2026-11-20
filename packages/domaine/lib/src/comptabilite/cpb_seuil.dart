/// SEUIL DE RENTABILITÉ (M12, `m12-seuil-rentabilite`) — port de `m12-comptabilite.js`.
///
/// Le seuil repose sur UNE distinction : les charges qui suivent l'activité (variables) et celles qui tombent qu'on travaille ou non (fixes). Cette
/// répartition est un JUGEMENT de gestion, pas une donnée du plan comptable : elle est PROPOSÉE (`cpbNatureChargeReferentiel`), affichée compte par
/// compte et corrigeable — la correction vit au magasin (`reglages`, clé `naturesCharges`). Un seuil incalculable (marge sur coût variable nulle ou
/// négative) est un DIAGNOSTIC, pas un défaut d'affichage.
library;

import '../format/js.dart';
import '../referentiels/periodes.dart';
import 'cpa_referentiels.dart' show CpaFiche;
import 'cpb_feuillets.dart';

class CpbSeuil {
  const CpbSeuil({
    required this.bornes,
    required this.ca,
    required this.fixe,
    required this.variable,
    required this.marge,
    required this.taux,
    required this.seuil,
    required this.securite,
    required this.pointMort,
    required this.comptes,
    required this.brouillons,
  });
  final Bornes bornes;
  final double ca, fixe, variable, marge, taux;

  /// `null` : INCALCULABLE (taux de marge nul ou négatif).
  final double? seuil, securite;

  /// La date à laquelle le seuil est atteint, en supposant l'activité régulière sur la période (une approximation, dite à l'écran).
  final DateTime? pointMort;
  final List<CpbCompteCharge> comptes;
  final int brouillons;
}

/// `calcul()` de l'écran : CA = soldes de gestion (ventes de marchandises + production) ; marge = CA − charges variables ; taux = marge / CA ; seuil =
/// charges fixes / taux ; marge de sécurité = CA − seuil.
CpbSeuil cpbSeuilRentabilite(Iterable<CpaFiche> toutes, Bornes b,
    {Map<String, String> natures = const {}, required String Function(String) libelleCompte}) {
  final s2 = cpbSoldesGestion(toutes, b);
  final ch = cpbChargesParNature(toutes, b, natures: natures, libelleCompte: libelleCompte);
  final ca = s2.chiffreAffaires;
  final marge = ca - ch.variable;
  final taux = ca != 0 ? marge / ca : 0.0;
  final seuil = taux > 0 ? ch.fixe / taux : null;
  final securite = seuil != null ? ca - seuil : null;
  final pointMort = (seuil != null && ca > 0 && seuil <= ca) ? ajouterJours(b.debut, arrondiJs(seuil / ca * b.jours).toInt()) : null;
  return CpbSeuil(
      bornes: b,
      ca: ca,
      fixe: ch.fixe,
      variable: ch.variable,
      marge: marge,
      taux: taux,
      seuil: seuil,
      securite: securite,
      pointMort: pointMort,
      comptes: ch.comptes,
      brouillons: ch.brouillons);
}
