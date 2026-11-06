import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// La configuration du MODE PAIR d'un poste (ADR-0006), lue dans `pair.json` du dossier de données : adresse du relais, clé unique de la clinique (256 bits en
/// hexadécimal), nom du poste et, au premier lancement seulement, le code d'appairage délivré par le relais. Absent ou `actif` faux : le poste ne change pas
/// de comportement. L'écran de saisie de ces valeurs n'existe pas encore : le fichier est la seule porte, et le dit.
class ConfigPairPoste {
  const ConfigPairPoste({required this.relais, required this.cleHex, this.nom = 'poste', this.code});
  final String relais, cleHex, nom;
  final String? code;

  /// La clé LOCALE du poste (celle qui chiffre déjà le magasin : AES-256, liée à la session Windows par DPAPI), posée par `main` après `CleLocale.obtenir()`.
  /// Présente : la clé de la clinique n'est JAMAIS écrite en clair dans `pair.json` (champ `cle_chiffree`, AES-256-GCM, nom du champ lié au chiffré). Absente
  /// (`SIGH_CHIFFREMENT=non`, développement) : clair, comme le magasin. Les autres champs (adresse, nom, activation) ne sont pas des secrets et restent lisibles.
  static List<int>? cleLocale;

  static const _aad = 'pair.json:cle';
  static final _aes = AesGcm.with256bits().toSync();

  static String _chiffrerCle(String cleHex, List<int> locale) {
    final boite = _aes.encryptSync(utf8.encode(cleHex), secretKeyData: SecretKeyData(locale), aad: utf8.encode(_aad));
    return base64.encode(boite.concatenation());
  }

  /// Lève [FormatException] nommée si le champ est altéré, tronqué ou chiffré par un autre poste (jamais une clé devinée).
  static String _dechiffrerCle(String b64, List<int>? locale) {
    if (locale == null) {
      throw const FormatException('pair.json : la clé de la clinique est chiffrée par la clé locale de ce poste, qui n’est pas disponible (SIGH_CHIFFREMENT=non ?)');
    }
    try {
      final octets = base64.decode(b64);
      final boite = SecretBox.fromConcatenation(octets, nonceLength: 12, macLength: 16);
      return utf8.decode(_aes.decryptSync(boite, secretKeyData: SecretKeyData(locale), aad: utf8.encode(_aad)));
    } catch (_) {
      throw const FormatException('pair.json : la clé de la clinique est illisible (fichier altéré, ou chiffré par un autre poste ou une autre session Windows)');
    }
  }

  /// Lit le fichier, déchiffre la clé EN MÉMOIRE (champ `cle`) et rend aussi `migrer: true` si la clé était encore en clair alors qu'une clé locale existe.
  static (Map<String, Object?>, bool) _charger(String dossier) {
    final f = File('$dossier/pair.json');
    if (!f.existsSync()) return ({}, false);
    final Object? j;
    try {
      j = jsonDecode(f.readAsStringSync());
    } catch (e) {
      throw FormatException('pair.json illisible : $e');
    }
    if (j is! Map) throw const FormatException('pair.json illisible : objet attendu');
    final m = j.cast<String, Object?>();
    final chiffree = m.remove('cle_chiffree');
    if (chiffree != null) m['cle'] = _dechiffrerCle('$chiffree', cleLocale);
    m.remove('format');
    return (m, chiffree == null && m['cle'] != null && cleLocale != null);
  }

  static void _ecrireFichier(String dossier, Map<String, Object?> m) {
    final j = {...m};
    final cle = j.remove('cle');
    j['format'] = 2;
    if (cle != null) {
      if (cleLocale != null) {
        j['cle_chiffree'] = _chiffrerCle('$cle', cleLocale!);
      } else {
        j['cle'] = cle;
      }
    }
    Directory(dossier).createSync(recursive: true);
    final cible = File('$dossier/pair.json');
    final tmp = File('${cible.path}.tmp');
    tmp.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(j), flush: true);
    tmp.renameSync(cible.path);
  }

  /// Rend `null` si le mode pair n'est pas actif. Un fichier illisible ou une clé qui n'a pas 64 caractères hexadécimaux lève `FormatException` nommée : un mode
  /// pair à moitié configuré ne doit pas démarrer en silence.
  static ConfigPairPoste? lire(String dossier) {
    final (j, migrer) = _charger(dossier);
    if (j.isEmpty || j['actif'] != true) return null;
    final relais = '${j['relais'] ?? ''}', cle = '${j['cle'] ?? ''}';
    if (relais.isEmpty) throw const FormatException('pair.json : « relais » manque');
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(cle)) throw const FormatException('pair.json : « cle » doit faire 64 caractères hexadécimaux (256 bits)');
    // MIGRATION : un pair.json d'avant porte la clé en clair ; dès qu'une clé locale existe, il est réécrit chiffré (le clair ne reste pas sur le disque).
    if (migrer) _ecrireFichier(dossier, j);
    final code = j['code'] == null || '${j['code']}'.isEmpty ? null : '${j['code']}';
    return ConfigPairPoste(relais: relais, cleHex: cle, nom: '${j['nom'] ?? 'poste'}', code: code);
  }

  /// Le contenu BRUT de `pair.json` (vide si absent ou illisible), pour l'écran de réglage : il lit aussi un mode désactivé, ce que [lire] ne rend pas.
  static Map<String, Object?> lireBrut(String dossier) {
    try {
      return _charger(dossier).$1;
    } on FormatException {
      // Une clé illisible ne se montre pas comme « absente » : l'écran lit `cle_illisible` et le dit (jamais une génération silencieuse par-dessus).
      final f = File('$dossier/pair.json');
      try {
        final j = (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>()..remove('cle_chiffree')..remove('format');
        return {...j, 'cle_illisible': true};
      } catch (_) {
        return {};
      }
    }
  }

  /// Une clé de clinique neuve : 256 bits tirés du générateur sécurisé du système, en 64 caractères hexadécimaux.
  static String genererCle([Random? alea]) {
    final r = alea ?? Random.secure();
    return [for (var i = 0; i < 32; i++) r.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
  }

  /// Écrit `pair.json` en CONSERVANT ce que l'appelant ne change pas (la clé en particulier : un réglage de l'adresse ne la perd pas). [code] vide : le code
  /// d'appairage est retiré (il est à usage unique, jamais gardé). Refus nommé (`FormatException`) si le mode est activé sans relais ou sans clé valide :
  /// un fichier qui ferait échouer le démarrage ne s'écrit pas.
  static void ecrire(String dossier,
      {bool? actif, String? relais, String? nom, String? cleHex, String? code, bool? recuperation, String? courriel, String? cleLe}) {
    final j = lireBrut(dossier);
    // Une clé illisible n'est pas écrasée en silence par un réglage qui ne la remplace pas : refus nommé. La régénérer (cleHex) reste possible.
    if (j.remove('cle_illisible') == true && cleHex == null) {
      throw const FormatException('La clé de la clinique est illisible dans pair.json : la régénérer ou restaurer le fichier avant tout autre réglage.');
    }
    if (actif != null) j['actif'] = actif;
    if (relais != null) j['relais'] = relais;
    if (nom != null) j['nom'] = nom;
    if (cleHex != null) j['cle'] = cleHex;
    if (code != null) {
      if (code.isEmpty) {
        j.remove('code');
      } else {
        j['code'] = code;
      }
    }
    if (recuperation != null) j['recuperation'] = recuperation;
    if (courriel != null) j['courriel'] = courriel;
    if (cleLe != null) j['cle_le'] = cleLe;
    if (j['actif'] == true) {
      if ('${j['relais'] ?? ''}'.isEmpty) throw const FormatException('Le mode pair ne peut pas être activé sans adresse de relais.');
      if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch('${j['cle'] ?? ''}')) throw const FormatException('Le mode pair ne peut pas être activé sans clé de clinique valide.');
    }
    _ecrireFichier(dossier, j);
  }
}
