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

  /// Exécuteur de commande (injectable : les tests n'envoient rien à une imprimante).
  static Future<ProcessResult> Function(String exe, List<String> args) lancer =
      (exe, args) => Process.run(exe, args);

  /// Système d'exploitation (injectable pour tester la commande de chaque plateforme).
  static String systeme = Platform.operatingSystem;

  /// Commande d'impression d'un PDF vers l'imprimante PAR DÉFAUT du système : `lp` (Linux, macOS, CUPS) ou le verbe « Print » du shell (Windows).
  /// Le résultat est RENDU, jamais avalé : pas d'imprimante par défaut, pas de pilote → un refus nommé que l'écran affiche.
  static (String, List<String>) commande(String chemin) => switch (systeme) {
        'windows' => (
            'powershell',
            [
              '-NoProfile',
              '-Command',
              'Start-Process -FilePath "${chemin.replaceAll('"', '')}" -Verb Print'
            ]
          ),
        _ => ('lp', [chemin]),
      };

  /// Imprime sur l'imprimante par défaut. `null` = lancée ; sinon le motif du refus. NON testé ici sur matériel réel.
  static Future<String?> imprimer(String chemin) async {
    final (exe, args) = commande(chemin);
    try {
      final r = await lancer(exe, args);
      if (r.exitCode == 0) return null;
      final detail = '${r.stderr}'.trim();
      return 'Impression refusée par le système (code ${r.exitCode})${detail.isEmpty ? '' : ' : $detail'}. Vérifier qu’une imprimante par défaut est installée.';
    } on ProcessException catch (e) {
      return 'Aucune commande d’impression disponible (${e.executable}). Enregistrer le PDF puis l’imprimer depuis un lecteur de PDF.';
    }
  }

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
            libelle: 'Enregistrer en PDF',
            icone: LucideIcons.fileDown,
            variante: VarianteBouton.secondaire,
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
