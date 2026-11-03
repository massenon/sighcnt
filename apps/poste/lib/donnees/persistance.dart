import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';

typedef FichePersistee = Map<String, Object?>;

/// Où le magasin du poste se range sur disque. Une INTERFACE : le magasin ne sait pas si c'est un dossier de fichiers (aujourd'hui) ou une base locale
/// chiffrée SQLCipher (étape suivante du plan) : l'une remplace l'autre sans toucher aux écrans.
abstract class Persistance {
  /// Tout ce qui a été écrit : `collection -> fiches` (archivées comprises, RG-14). Vide au tout premier démarrage.
  Future<Map<String, List<FichePersistee>>> lireTout();

  /// Remplace le contenu d'UNE collection (le magasin n'envoie que celles qui ont changé).
  Future<void> ecrire(String collection, List<FichePersistee> fiches);

  /// Les informations du magasin lui-même (empreinte du jeu d'origine qui a servi, version) : une petite fiche, hors collections.
  Future<Map<String, Object?>> lireMeta();
  Future<void> ecrireMeta(Map<String, Object?> meta);

  /// Ce qui n'a pas pu être relu : un fichier illisible n'est jamais effacé en silence, il est mis de côté et NOMMÉ ici pour que le poste le dise.
  List<String> get problemes;
}

/// LA CLÉ DU POSTE (chiffrement au repos du magasin). Windows : une clé de 256 bits tirée au hasard, PROTÉGÉE par DPAPI (`ProtectedData`, portée utilisateur
/// Windows) : le fichier de clé ne sert qu'à la session Windows qui l'a créé, un disque volé ne l'ouvre pas. Ailleurs (macOS, Linux) : un fichier de clé en
/// lecture réservée à l'utilisateur, à côté des données : PLUS FAIBLE (qui lit le dossier lit la clé), dit comme tel dans la documentation.
class CleLocale {
  CleLocale(this.chemin);
  final String chemin;

  static List<int> _aleatoire() {
    final a = math.Random.secure();
    return [for (var i = 0; i < 32; i++) a.nextInt(256)];
  }

  /// Passe par PowerShell pour DPAPI : le secret circule par l'entrée standard, jamais par la ligne de commande.
  static Future<String> _dpapi(String mode, String b64) async {
    final cmd = mode == 'proteger'
        ? "Add-Type -AssemblyName System.Security; \$b = [Convert]::FromBase64String([Console]::In.ReadLine()); [Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Protect(\$b, \$null, 'CurrentUser'))"
        : "Add-Type -AssemblyName System.Security; \$b = [Convert]::FromBase64String([Console]::In.ReadLine()); [Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Unprotect(\$b, \$null, 'CurrentUser'))";
    final p = await Process.start('powershell', ['-NoProfile', '-NonInteractive', '-Command', cmd]);
    p.stdin.writeln(b64);
    await p.stdin.close();
    final sortie = (await utf8.decoder.bind(p.stdout).join()).trim();
    final code = await p.exitCode;
    if (code != 0 || sortie.isEmpty) throw StateError('DPAPI indisponible (code $code)');
    return sortie;
  }

  /// La clé du poste en service (posée par `main`) : l'écran « Sauvegarder la clé de chiffrement » l'exporte. `null` : poste sans chiffrement.
  static CleLocale? courante;

  static final _pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 200000, bits: 256);
  static const _enteteCle = 'SGHK';

  /// SAUVEGARDE DE LA CLÉ (limite levée le 03/11/2026) : une clé perdue rend toutes les données du poste illisibles. L'export écrit la clé CHIFFRÉE par une
  /// phrase de passe (PBKDF2-SHA256 200 000 tours, AES-256-GCM) : le fichier peut être rangé au coffre ou sur une clé USB sans exposer les données. Refus
  /// nommé si la phrase fait moins de 12 caractères.
  Future<String> exporter(String destination, String phrase) async {
    if (phrase.length < 12) throw StateError('La phrase de passe doit comporter au moins 12 caractères.');
    final cle = await obtenir();
    final sel = _aleatoire().sublist(0, 16);
    final derivee = await _pbkdf2.deriveKeyFromPassword(password: phrase, nonce: sel);
    final boite = await AesGcm.with256bits().encrypt(cle, secretKey: derivee, aad: utf8.encode(_enteteCle));
    final f = File(destination);
    await f.parent.create(recursive: true);
    await f.writeAsBytes([...utf8.encode(_enteteCle), ...sel, ...boite.concatenation()], flush: true);
    return f.path;
  }

  /// Relit une clé sauvegardée et la REMET en service (la protège de nouveau par DPAPI sous Windows). Mauvaise phrase ou fichier altéré : refus nommé, rien
  /// n'est écrasé. À utiliser quand le fichier de clé du poste est perdu (poste remplacé, session Windows réinstallée).
  Future<List<int>> importer(String source, String phrase) async {
    final brut = await File(source).readAsBytes();
    if (brut.length < 4 + 16 + 12 + 16 || utf8.decode(brut.sublist(0, 4), allowMalformed: true) != _enteteCle) {
      throw StateError('Ce fichier n’est pas une sauvegarde de clé SIGH.');
    }
    final sel = brut.sublist(4, 20);
    final derivee = await _pbkdf2.deriveKeyFromPassword(password: phrase, nonce: sel);
    List<int> cle;
    try {
      cle = await AesGcm.with256bits().decrypt(SecretBox.fromConcatenation(brut.sublist(20), nonceLength: 12, macLength: 16), secretKey: derivee, aad: utf8.encode(_enteteCle));
    } catch (_) {
      throw StateError('Phrase de passe incorrecte, ou sauvegarde de clé altérée.');
    }
    if (cle.length != 32) throw StateError('Sauvegarde de clé invalide.');
    final f = File(chemin);
    await f.parent.create(recursive: true);
    if (Platform.isWindows) {
      await f.writeAsString(await _dpapi('proteger', base64.encode(cle)), flush: true);
    } else {
      await f.writeAsString(base64.encode(cle), flush: true);
      try {
        await Process.run('chmod', ['600', f.path]);
      } catch (_) {}
    }
    return cle;
  }

  /// Rend la clé (la crée au premier usage). Lève [StateError] si elle est illisible : on ne devine jamais une clé.
  Future<List<int>> obtenir() async {
    final f = File(chemin);
    if (Platform.isWindows) {
      if (await f.exists()) return base64.decode(await _dpapi('ouvrir', (await f.readAsString()).trim()));
      final cle = _aleatoire();
      final protegee = await _dpapi('proteger', base64.encode(cle));
      await f.parent.create(recursive: true);
      await f.writeAsString(protegee, flush: true);
      return cle;
    }
    if (await f.exists()) {
      final b = base64.decode((await f.readAsString()).trim());
      if (b.length != 32) throw StateError('Fichier de clé du poste invalide.');
      return b;
    }
    final cle = _aleatoire();
    await f.parent.create(recursive: true);
    await f.writeAsString(base64.encode(cle), flush: true);
    try {
      await Process.run('chmod', ['600', f.path]);
    } catch (_) {}
    return cle;
  }
}

/// Un dossier de fichiers, un par collection. Écriture ATOMIQUE (fichier temporaire, puis renommage) : une coupure de courant pendant l'écriture ne laisse
/// jamais une collection à moitié écrite.
///
/// CHIFFRÉ AU REPOS quand une [cle] est fournie (Direction, 03/11/2026) : AES-256-GCM, un nonce frais à chaque écriture, le nom de la collection lié au chiffré
/// (un fichier recopié sous un autre nom ne se déchiffre pas). Fichiers `<collection>.sigh`. Les fichiers EN CLAIR d'un poste d'avant (`.json`) sont lus puis
/// réécrits chiffrés et le clair est SUPPRIMÉ : la migration ne laisse pas de copie lisible. Sans [cle] : JSON en clair (développement, `SIGH_CHIFFREMENT=non`).
///
/// CE QUE CE N'EST PAS : SQLCipher (une base SQL chiffrée) ni un coffre matériel. C'est un chiffrement de fichiers dont la clé est liée à la session Windows.
class PersistanceFichiers implements Persistance {
  PersistanceFichiers(this.dossier, {List<int>? cle}) : _cle = cle;
  final String dossier;
  final List<int>? _cle;
  final List<String> _problemes = [];
  static final _aes = AesGcm.with256bits();
  static const _entete = [0x53, 0x47, 0x48, 0x31]; // « SGH1 »

  bool get chiffre => _cle != null;

  @override
  List<String> get problemes => List.unmodifiable(_problemes);

  static final RegExp _nomValide = RegExp(r'^[A-Za-z0-9_\-]+$');

  File _fichier(String nom) => File('$dossier/$nom.${chiffre ? 'sigh' : 'json'}');

  Future<List<int>> _chiffrer(String nom, List<int> clair) async {
    final boite = await _aes.encrypt(clair, secretKey: SecretKey(_cle!), aad: utf8.encode(nom));
    return [..._entete, ...boite.concatenation()];
  }

  Future<List<int>> _dechiffrer(String nom, List<int> brut) async {
    if (brut.length < 4 + 12 + 16 || !(brut[0] == _entete[0] && brut[1] == _entete[1] && brut[2] == _entete[2] && brut[3] == _entete[3])) {
      throw const FormatException('fichier chiffré invalide');
    }
    final boite = SecretBox.fromConcatenation(brut.sublist(4), nonceLength: 12, macLength: 16);
    return _aes.decrypt(boite, secretKey: SecretKey(_cle!), aad: utf8.encode(nom));
  }

  Future<void> _ecrireOctets(File cible, List<int> octets) async {
    await cible.parent.create(recursive: true);
    final tmp = File('${cible.path}.tmp');
    await tmp.writeAsBytes(octets, flush: true);
    await tmp.rename(cible.path);
  }

  Future<void> _mettreDeCoteIllisible(File e, String nom, Object err) async {
    // On ne devine pas et on n'efface pas : le fichier est mis de côté, la collection retombe sur le jeu d'origine, et le problème est nommé.
    final cote = '${e.path}.corrompu-${DateTime.now().millisecondsSinceEpoch}';
    try {
      await e.rename(cote);
    } catch (_) {}
    _problemes.add('Collection « $nom » illisible ($err) : mise de côté dans ${cote.split(RegExp(r'[\\/]')).last}.');
  }

  @override
  Future<Map<String, List<FichePersistee>>> lireTout() async {
    final d = Directory(dossier);
    if (!await d.exists()) return {};
    final sortie = <String, List<FichePersistee>>{};
    final aMigrer = <String>[];
    await for (final e in d.list()) {
      if (e is! File) continue;
      final nomFichier = e.uri.pathSegments.last;
      final estSigh = nomFichier.endsWith('.sigh');
      final estJson = nomFichier.endsWith('.json');
      if (!estSigh && !estJson) continue;
      if (nomFichier == '_meta.json' || nomFichier == '_meta.sigh') continue;
      final nom = nomFichier.replaceFirst(RegExp(r'\.(sigh|json)$'), '');
      if (!_nomValide.hasMatch(nom)) continue;
      // Un fichier chiffré l'emporte sur un clair du même nom (reste d'une migration interrompue).
      if (estJson && File('$dossier/$nom.sigh').existsSync() && chiffre) continue;
      try {
        final String texte;
        if (estSigh) {
          if (!chiffre) throw const FormatException('fichier chiffré mais aucune clé n’est disponible');
          texte = utf8.decode(await _dechiffrer(nom, await e.readAsBytes()));
        } else {
          texte = await e.readAsString();
          if (chiffre) aMigrer.add(nom);
        }
        final brut = jsonDecode(texte);
        if (brut is! List) throw const FormatException('une collection est une liste de fiches');
        sortie[nom] = [for (final f in brut) (f as Map).cast<String, Object?>()];
      } catch (err) {
        await _mettreDeCoteIllisible(e, nom, err);
      }
    }
    // MIGRATION : les collections lues en clair sont réécrites chiffrées, puis le clair est supprimé.
    for (final nom in aMigrer) {
      final clair = File('$dossier/$nom.json');
      try {
        await ecrire(nom, sortie[nom]!);
        if (await File('$dossier/$nom.sigh').exists()) await clair.delete();
      } catch (err) {
        _problemes.add('Migration chiffrée de « $nom » impossible ($err) : le fichier en clair est conservé.');
      }
    }
    return sortie;
  }

  @override
  Future<void> ecrire(String collection, List<FichePersistee> fiches) async {
    if (!_nomValide.hasMatch(collection)) throw ArgumentError('Nom de collection invalide : $collection');
    final octets = utf8.encode(jsonEncode(fiches));
    await _ecrireOctets(_fichier(collection), chiffre ? await _chiffrer(collection, octets) : octets);
  }

  @override
  Future<Map<String, Object?>> lireMeta() async {
    for (final ext in chiffre ? ['sigh', 'json'] : ['json']) {
      final f = File('$dossier/_meta.$ext');
      if (!await f.exists()) continue;
      try {
        final texte = ext == 'sigh' ? utf8.decode(await _dechiffrer('_meta', await f.readAsBytes())) : await f.readAsString();
        return (jsonDecode(texte) as Map).cast<String, Object?>();
      } catch (_) {
        return {};
      }
    }
    return {};
  }

  @override
  Future<void> ecrireMeta(Map<String, Object?> meta) async {
    final octets = utf8.encode(jsonEncode(meta));
    await _ecrireOctets(File('$dossier/_meta.${chiffre ? 'sigh' : 'json'}'), chiffre ? await _chiffrer('_meta', octets) : octets);
    if (chiffre) {
      final clair = File('$dossier/_meta.json');
      if (await clair.exists()) await clair.delete();
    }
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
  Map<String, Object?> meta = {};

  @override
  Future<Map<String, Object?>> lireMeta() async => {...meta};

  @override
  Future<void> ecrireMeta(Map<String, Object?> m) async => meta = {...m};

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
