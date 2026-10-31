import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m7/besoins_commun.dart' show notifierPoste;
export 'cpa_commun.dart';

/// Briques communes à la tranche M12 « synthèse, exercices, pilotage » (états financiers, baseline 2025, échéances, clôture, ouverture, BFR, coût à
/// l'activité). Les règles chiffrées vivent dans `packages/domaine/lib/src/comptabilite/cpc_*.dart`.

/// `exercices()` amorce la collection (une fiche par année portée par le journal, l'horloge et la liasse déposée). À appeler AVANT le premier rendu :
/// insérer pendant un rendu déclencherait les écouteurs en pleine construction.
void amorcerExercices(Magasin m, DateTime auj) {
  final col = m.collection('exercices');
  final fiches = cpcExercicesAAmorcer(col.toutes, m.collection('ecritures').toutes, auj);
  for (final f in fiches) {
    col.inserer(f);
  }
}

List<Fiche> exercicesActifs(Magasin m) => cpcListeExercices(m.collection('exercices').toutes);

/// Le nom de l'agent porté par chaque geste (RG-12). Le poste ne connaît que le libellé du rôle de la session (écart E800).
String acteurDe(ContexteEcran c) => c.utilisateur.isEmpty ? 'Utilisateur' : c.utilisateur;

/// L'écran d'un contrôle de pré-clôture, nommé comme au manifeste (« → Écritures comptables »).
const Map<String, String> libellesEcransM12 = {
  'm12-ecritures': 'Écritures comptables',
  'm12-balance': 'Balance générale & âgée',
  'm12-ouverture': 'Bilan d’ouverture & à-nouveaux',
  'm12-grand-livre': 'Grand livre',
};

/// Un refus d'écriture par la garde de la collection : toast nommé (le journal est déjà écrit par la collection).
bool refuseSiClos(BuildContext ctx, void Function() ecriture) {
  try {
    ecriture();
    return false;
  } on EcritureRefusee catch (e) {
    ToastsSigh.afficher(ctx, 'Écriture refusée.', type: TypeToast.erreur, detail: e.motif);
    return true;
  }
}

/// `PR.notifier` : une notification de POSTE.
void notifier(ContexteEcran c, {required String type, required String poste, required String libelle, String? detail, String priorite = 'normale', String? reference}) =>
    notifierPoste(c.magasin, {'type': type, 'poste': poste, 'libelle': libelle, 'detail': detail, 'priorite': priorite, 'reference': reference}, c.aujourdhui);
