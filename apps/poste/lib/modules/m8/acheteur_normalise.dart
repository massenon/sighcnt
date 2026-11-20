import 'package:flutter/material.dart';

import '../../donnees/normalisation_mecef.dart';
import '../../kit/kit.dart';

/// PLUS DE BLOC « FACTURE NORMALISÉE » (Direction, 16/11/2026, lot FISC-2). La facture d'un PATIENT ne porte ni IFU de l'acheteur, ni nom de l'acheteur, ni taux
/// d'AIB : le patient paie le montant total, seul affiché sur sa facture de caisse. La vente reste NORMALISÉE (sans acheteur : particulier, AIB nul) ; le domaine
/// refuse aussi un taux demandé (`AIB_FACTURE_PATIENT`). L'AIB s'impute à « Barème de l'AIB », onglet « Imputations ». Ce fichier ne garde que l'annonce de la normalisation.

/// Ce que la normalisation a rendu, dit au guichet : une pièce refusée se DIT, avec son code, son motif et son geste. Rien à dire en mode désactivé.
void annoncerNormalisation(BuildContext ctx, ResultatNormalisation? n) {
  if (n == null || n.ignore) return;
  if (n.ok) {
    ToastsSigh.afficher(ctx, 'Vente normalisée : ${n.numero}.',
        type: TypeToast.succes,
        detail: 'Numéro déjà porté par la pièce : il n’est jamais réécrit (lot L3 : le poste ne fabrique aucun numéro).');
    return;
  }
  ToastsSigh.afficher(ctx,
      'Normalisation non aboutie (${n.code}) : la vente est encaissée mais pas normalisée.',
      type: TypeToast.attention,
      detail: '${n.motif} ${n.geste}',
      duree: const Duration(seconds: 12));
}
