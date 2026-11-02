import 'dart:convert';
import 'dart:io';

typedef FichePersistee = Map<String, Object?>;

/// Où le magasin du poste se range sur disque. Une INTERFACE : le magasin ne sait pas si c'est un dossier de fichiers (aujourd'hui) ou une base locale
/// chiffrée SQLCipher (étape suivante du plan) : l'une remplace l'autre sans toucher aux écrans.
abstract class Persistance {
  /// Tout ce qui a été écrit : `collection -> fiches` (archivées comprises, RG-14). Vide au tout premier démarrage.
  Future<Map<String, List<FichePersistee>>> lireTout();

  /// Remplace le contenu d'UNE collection (le magasin n'envoie que celles qui ont changé).
  Future<void> ecrire(String collection, List<FichePersistee> fiches);

  /// Ce qui n'a pas pu être relu : un fichier illisible n'est jamais effacé en silence, il est mis de côté et NOMMÉ ici pour que le poste le dise.
  List<String> get problemes;
}

/// Un dossier de fichiers JSON, un par collection. Écriture ATOMIQUE (fichier temporaire, puis renommage) : une coupure de courant pendant l'écriture
/// ne laisse jamais une collection à moitié écrite.
///
/// CE QUE CE N'EST PAS : une base chiffrée. Les fichiers sont en clair (les mots de passe y sont des hachés Argon2id, jamais en clair). Les données
/// médicales d'un vrai poste exigent SQLCipher ; cette implémentation sert à garder l'installation et les saisies d'un poste entre deux démarrages.
class PersistanceFichiers implements Persistance {
  PersistanceFichiers(this.dossier);
  final String dossier;
  final List<String> _problemes = [];

  @override
  List<String> get problemes => List.unmodifiable(_problemes);

  static final RegExp _nomValide = RegExp(r'^[A-Za-z0-9_\-]+$');

  File _fichier(String nom) => File('$dossier/$nom.json');

  @override
  Future<Map<String, List<FichePersistee>>> lireTout() async {
    final d = Directory(dossier);
    if (!await d.exists()) return {};
    final sortie = <String, List<FichePersistee>>{};
    await for (final e in d.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      final nom = e.uri.pathSegments.last.replaceFirst(RegExp(r'\.json$'), '');
      if (!_nomValide.hasMatch(nom)) continue;
      try {
        final brut = jsonDecode(await e.readAsString());
        if (brut is! List) throw const FormatException('une collection est une liste de fiches');
        sortie[nom] = [for (final f in brut) (f as Map).cast<String, Object?>()];
      } catch (err) {
        // On ne devine pas et on n'efface pas : le fichier est mis de côté, la collection retombe sur le jeu d'origine, et le problème est nommé.
        final cote = '${e.path}.corrompu-${DateTime.now().millisecondsSinceEpoch}';
        try {
          await e.rename(cote);
        } catch (_) {}
        _problemes.add('Collection « $nom » illisible ($err) : mise de côté dans ${cote.split(RegExp(r'[\\/]')).last}.');
      }
    }
    return sortie;
  }

  @override
  Future<void> ecrire(String collection, List<FichePersistee> fiches) async {
    if (!_nomValide.hasMatch(collection)) throw ArgumentError('Nom de collection invalide : $collection');
    final cible = _fichier(collection);
    await cible.parent.create(recursive: true);
    final tmp = File('${cible.path}.tmp');
    await tmp.writeAsString(jsonEncode(fiches), flush: true);
    await tmp.rename(cible.path);
  }

  /// Repartir de zéro (développement, `SIGH_REPARTIR_A_ZERO=oui`) : le dossier est mis de côté, pas supprimé.
  Future<void> mettreDeCote() async {
    final d = Directory(dossier);
    if (await d.exists()) await d.rename('$dossier.ancien-${DateTime.now().millisecondsSinceEpoch}');
  }
}

/// Persistance en mémoire (tests) : tient le même contrat sans disque.
class PersistanceMemoire implements Persistance {
  PersistanceMemoire([Map<String, List<FichePersistee>>? depart]) : contenu = {...?depart};
  final Map<String, List<FichePersistee>> contenu;
  final List<String> ecritures = [];

  @override
  List<String> get problemes => const [];

  @override
  Future<Map<String, List<FichePersistee>>> lireTout() async => {
        for (final e in contenu.entries) e.key: [for (final f in e.value) {...f}]
      };

  @override
  Future<void> ecrire(String collection, List<FichePersistee> fiches) async {
    ecritures.add(collection);
    contenu[collection] = [
      for (final f in fiches) (jsonDecode(jsonEncode(f)) as Map).cast<String, Object?>()
    ];
  }
}
