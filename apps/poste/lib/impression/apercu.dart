import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../kit/kit.dart';
import 'feuilles.dart';
import 'pdf.dart';
import 'piece.dart';

/// Écriture du PDF : injectable (le poste y branchera l'imprimante / le dossier d'archivage ; les tests, un faux). Par défaut : le dossier
/// temporaire du système — l'impression physique n'est PAS branchée ici et l'écran le dit en annonçant le chemin.
class ImpressionPoste {
  ImpressionPoste._();
  static Future<String> Function(List<int> pdf, String nom) enregistrer =
      (pdf, nom) async {
    final f = File('${Directory.systemTemp.path}/$nom.pdf');
    await f.writeAsBytes(pdf);
    return f.path;
  };
  static int _compteur = 0;
  static int prochainNumero() => ++_compteur;
}

/// Aperçu commun (`afficher()` de print.js) : la feuille dans une modale large, « Fermer » et « Imprimer / PDF ».
Future<void> afficherApercu(BuildContext context, PieceA4 piece) =>
    afficherModale<void>(
      context,
      titre: piece.titre,
      sousTitre: piece.reference,
      taille: TailleModale.xl,
      corps: Container(
        color: const Color(0xFFE2E8F0),
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Center(child: FeuilleA4(piece: piece))),
      ),
      pied: (fermer) => [
        BoutonSigh(
            libelle: 'Fermer',
            variante: VarianteBouton.secondaire,
            onPressed: fermer),
        BoutonSigh(
            libelle: 'Imprimer / PDF',
            icone: LucideIcons.printer,
            onPressed: () async {
              final p = await PolicesPdf.charger();
              final octets = await pdfA4(piece, p);
              final chemin =
                  await ImpressionPoste.enregistrer(octets, piece.reference);
              if (context.mounted)
                ToastsSigh.afficher(context, 'PDF enregistré.',
                    type: TypeToast.succes, detail: chemin);
            }),
      ],
    );
