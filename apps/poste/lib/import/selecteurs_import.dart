import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as fs;

/// Un fichier choisi par l'agent : son nom et son contenu (lu en entier : un fichier d'import tient en mémoire).
class FichierChoisi {
  const FichierChoisi(this.nom, this.octets);
  final String nom;
  final Uint8List octets;
}

typedef ChoisirFichierImport = Future<FichierChoisi?> Function();

/// Enregistre un fichier produit par le poste (modèle .xlsx, rapport d'erreurs) ; rend le chemin écrit, ou `null` si l'agent annule.
typedef EnregistrerFichierImport = Future<String?> Function(String nom, Uint8List octets);

/// Les DEUX sélecteurs du module d'importation, INJECTABLES : aucun test ne dépend d'un sélecteur natif. En exploitation ils ouvrent les boîtes de
/// dialogue du système (`file_picker` pour téléverser, `file_selector` pour enregistrer le modèle dans le dossier choisi) ; un test pose les siens.
class SelecteursImport {
  SelecteursImport._();

  static ChoisirFichierImport choisir = choisirNatif;
  static EnregistrerFichierImport enregistrer = enregistrerNatif;

  /// Rend les sélecteurs natifs (tearDown d'un test).
  static void reinitialiser() {
    choisir = choisirNatif;
    enregistrer = enregistrerNatif;
  }

  static Future<FichierChoisi?> choisirNatif() async {
    final f = await FilePicker.pickFile(
        dialogTitle: 'Fichier à importer (.xlsx ou .csv)', type: FileType.custom, allowedExtensions: const ['xlsx', 'csv']);
    if (f == null) return null;
    return FichierChoisi(f.name, await f.readAsBytes());
  }

  static Future<String?> enregistrerNatif(String nom, Uint8List octets) async {
    final ext = nom.contains('.') ? nom.split('.').last : '';
    final lieu = await fs.getSaveLocation(
        suggestedName: nom,
        acceptedTypeGroups: [fs.XTypeGroup(label: ext == 'csv' ? 'Fichier CSV' : 'Classeur Excel', extensions: [ext])]);
    if (lieu == null) return null;
    await File(lieu.path).writeAsBytes(octets);
    return lieu.path;
  }
}
