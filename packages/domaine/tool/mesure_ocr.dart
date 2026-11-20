/// Mesure l'OCR sur un dossier de scans et leurs transcriptions (lot OCR-prep). Aucun moteur n'est choisi ni fourni : voir `tool/src/mesure_dossier.dart` et `docs/guides/GUIDE-mesure-ocr.md`.
///
///   dart run tool/mesure_ocr.dart --dossier <dossier> --sortie <dossier du rapport> --moteur factice-parfait,factice-sans-accents      (preuve de la mesure, scans SYNTHÉTIQUES)
///   dart run tool/mesure_ocr.dart --dossier <scans> --sortie <rapport> --commande "<ligne de commande du moteur avec {image} et {langue}>" --nom-moteur <nom> --version-moteur <version>
library;

import 'dart:io';


import 'src/mesure_dossier.dart';

Future<void> main(List<String> args) async {
  String? valeur(String nom) {
    final i = args.indexWhere((a) => a == '--$nom');
    if (i >= 0 && i + 1 < args.length) return args[i + 1];
    final p = args.where((a) => a.startsWith('--$nom=')).firstOrNull;
    return p?.substring(nom.length + 3);
  }

  if (args.contains('--aide') || args.contains('-h') || valeur('dossier') == null) {
    stdout.writeln('''Mesure de l'OCR : un dossier de scans (png, jpg, webp) avec, à côté de chacun, sa transcription de référence (même nom, extension .txt).

  --dossier <dossier>        le dossier des scans et de leurs transcriptions
  --sortie <dossier>         où écrire le rapport (Markdown et JSON) ; défaut : ./rapport-ocr
  --moteur a,b               des moteurs FACTICES (factice-parfait, factice-sans-accents, factice-perd-mots, factice-bruit) : preuve de la mesure, jamais un jugement
  --commande "<ligne>"       un moteur réel par sa ligne de commande, avec {image} et {langue} ; la sortie standard est le texte lu
  --nom-moteur <nom>         le nom du moteur pour le rapport (avec --commande)
  --version-moteur <v>       sa version (avec --commande)
  --langue <code>            la langue (défaut : fra)
  --delai <ms>               le délai maximal par page (défaut : 120000)
  --exemples                 ajoute au rapport les mots perdus en clair (à éviter sur des documents de patients)
  --synthetique              marque le rapport « scans synthétiques, moteurs factices »''');
    exit(valeur('dossier') == null && !args.contains('--aide') && !args.contains('-h') ? 2 : 0);
  }
  final langue = valeur('langue') ?? 'fra';
  final commande = valeur('commande');
  final noms = (valeur('moteur') ?? '').split(',').where((x) => x.isNotEmpty).toList();
  if (commande == null && noms.isEmpty) {
    stderr.writeln('Aucun moteur demandé : donner --moteur (factices) ou --commande (moteur réel). Le banc ne choisit aucun moteur.');
    exit(2);
  }
  try {
    final r = await mesurerDossier(
        dossier: valeur('dossier')!,
        sortie: valeur('sortie') ?? 'rapport-ocr',
        langue: langue,
        delaiMs: int.tryParse(valeur('delai') ?? '') ?? 120000,
        synthetique: args.contains('--synthetique') || (commande == null),
        avecExemples: args.contains('--exemples'),
        moteurs: (scans) => [
              for (final n in noms) moteurFactice(n, scans),
              if (commande != null) MoteurOcrCommande(commande, id: valeur('nom-moteur') ?? 'commande', version: valeur('version-moteur') ?? '', langueMoteur: langue),
            ]);
    for (final s in r.syntheses) {
      stdout.writeln('${s.moteur} ${s.version} : ${s.nbLus} scan(s) lu(s), ${s.nbRefuses} refusé(s), mots corrects ${(s.moyenneMots * 100).toStringAsFixed(1)} %, caractères ${(s.moyenneCaracteres * 100).toStringAsFixed(1)} %, ${s.motsPerdus} mot(s) perdu(s), accents ${s.tauxAccents == null ? 'sans objet' : '${(s.tauxAccents! * 100).toStringAsFixed(1)} %'}, ${s.msParPage.toStringAsFixed(0)} ms par page');
    }
    stdout.writeln('Rapport : ${r.rapport}');
  } on StateError catch (e) {
    stderr.writeln(e.message);
    exit(1);
  } on ArgumentError catch (e) {
    stderr.writeln(e.message);
    exit(2);
  }
}
