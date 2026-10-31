import 'package:flutter/material.dart';

import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../shell/contexte_ecran.dart';
import 'commun.dart';

String _ref(ContexteEcran c) =>
    PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero());

/// Aperçu de la facture (ou pro-forma) : la pièce est établie à l'instant de l'impression, par l'agent connecté (RG-12).
Future<void> imprimerFacture(BuildContext ctx, Fiche f,
    {bool proforma = false, Fiche? jumelle}) {
  final c = ContexteEcran.of(ctx);
  return afficherApercu(
      ctx,
      pieceFacture(f,
          proforma: proforma,
          jumelle: jumelle,
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
          reference: _ref(c)));
}

Future<void> imprimerRecu(BuildContext ctx, Fiche f, {Fiche? versement}) {
  final c = ContexteEcran.of(ctx);
  return afficherApercu(
      ctx,
      pieceRecu(f,
          versement: versement,
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
          reference: _ref(c)));
}

Future<void> imprimerEngagement(BuildContext ctx, Fiche f) {
  final c = ContexteEcran.of(ctx);
  return afficherApercu(
      ctx,
      pieceEngagement(f,
          utilisateur: c.utilisateur, edite: c.aujourdhui, reference: _ref(c)));
}
