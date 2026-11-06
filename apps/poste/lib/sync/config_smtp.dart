import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import 'config_pair.dart';

/// Le dossier où vit `smtp.json` : posé par `main.dart` (comme celui de `pair.json`). Absent (tests, poste sans dossier), l'écran le dit.
class EtatSmtpPoste {
  const EtatSmtpPoste._();
  static String? dossier;
}

/// La messagerie de CE poste (serveur SMTP) : `smtp.json` du dossier de données. Le MOT DE PASSE est saisi, chiffré (AES-256-GCM sous la clé locale du poste, celle
/// qui chiffre déjà le magasin et la clé de `pair.json`) et JAMAIS relu : [lireBrut] ne rend que « défini ou non ». Sans clé locale (`SIGH_CHIFFREMENT=non`,
/// développement), il reste en clair dans le fichier, comme le magasin. Un fichier altéré ou chiffré par un autre poste n'est pas deviné : refus nommé.
class ConfigSmtpPoste {
  const ConfigSmtpPoste._();

  static const _aad = 'smtp.json:mdp';
  static final _aes = AesGcm.with256bits().toSync();

  static File _fichier(String dossier) => File('$dossier/smtp.json');

  static Map<String, Object?> _lireFichier(String dossier) {
    final f = _fichier(dossier);
    if (!f.existsSync()) return {};
    try {
      final j = jsonDecode(f.readAsStringSync());
      return j is Map ? j.cast<String, Object?>() : {};
    } catch (_) {
      return {};
    }
  }

  static void _ecrireFichier(String dossier, Map<String, Object?> m) {
    Directory(dossier).createSync(recursive: true);
    final cible = _fichier(dossier);
    final tmp = File('${cible.path}.tmp');
    tmp.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(m), flush: true);
    tmp.renameSync(cible.path);
  }

  static String _chiffrer(String clair, List<int> locale) {
    final boite = _aes.encryptSync(utf8.encode(clair), secretKeyData: SecretKeyData(locale), aad: utf8.encode(_aad));
    return base64.encode(boite.concatenation());
  }

  /// Lève [FormatException] nommée si le chiffré est altéré ou ne vient pas de ce poste.
  static String _dechiffrer(String b64, List<int>? locale) {
    if (locale == null) throw const FormatException('smtp.json : le mot de passe est chiffré par la clé locale de ce poste, qui n’est pas disponible (SIGH_CHIFFREMENT=non ?)');
    try {
      final boite = SecretBox.fromConcatenation(base64.decode(b64), nonceLength: 12, macLength: 16);
      return utf8.decode(_aes.decryptSync(boite, secretKeyData: SecretKeyData(locale), aad: utf8.encode(_aad)));
    } catch (_) {
      throw const FormatException('smtp.json : le mot de passe est illisible (fichier altéré, ou chiffré par un autre poste ou une autre session Windows)');
    }
  }

  /// Ce que l'écran a le droit de voir : jamais le mot de passe, ni son chiffré.
  static Map<String, Object?> lireBrut(String dossier) {
    final j = _lireFichier(dossier);
    final illisible = j['mdp_chiffre'] != null && _essayer(() => _dechiffrer('${j['mdp_chiffre']}', ConfigPairPoste.cleLocale)) == null;
    return {
      'configure': '${j['serveur'] ?? ''}'.isNotEmpty && '${j['expediteur'] ?? ''}'.isNotEmpty,
      'serveur': j['serveur'] ?? '',
      'port': (j['port'] as num?)?.toInt() ?? 587,
      'chiffrement': j['chiffrement'] ?? 'starttls',
      'identifiant': j['identifiant'] ?? '',
      'motDePasseDefini': j['mdp_chiffre'] != null || j['mdp'] != null,
      'mdp_illisible': illisible,
      'expediteur': j['expediteur'] ?? '',
      'nom': j['nom'] ?? '',
      'repondreA': j['repondreA'] ?? '',
      'repondreNom': j['repondreNom'] ?? '',
      'delai': (j['delai'] as num?)?.toInt() ?? 15,
      'verifierCertificat': j['verifierCertificat'] != false,
      'testeLe': j['testeLe'],
      'testeOk': j['testeOk'],
      'testeEchec': j['testeEchec'],
    };
  }

  static T? _essayer<T>(T Function() f) {
    try {
      return f();
    } on FormatException {
      return null;
    }
  }

  /// Le mot de passe en clair, EN MÉMOIRE seulement, pour l'envoi. `''` s'il n'y en a pas.
  static String motDePasse(String dossier) {
    final j = _lireFichier(dossier);
    if (j['mdp_chiffre'] != null) return _dechiffrer('${j['mdp_chiffre']}', ConfigPairPoste.cleLocale);
    return '${j['mdp'] ?? ''}';
  }

  static final _adresse = RegExp(r'^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$');

  /// Enregistre. [motDePasse] vide ou absent : « inchangé » (l'écran ne le relit jamais, il ne peut pas le renvoyer). Enregistrer rend le dernier test caduc.
  static void ecrire(String dossier,
      {required String serveur,
      required int port,
      required String chiffrement,
      String identifiant = '',
      String? motDePasse,
      required String expediteur,
      String nom = '',
      String repondreA = '',
      String repondreNom = '',
      int delai = 15,
      bool verifierCertificat = true}) {
    if (serveur.trim().isEmpty || port < 1 || port > 65535) throw const FormatException('Serveur et port (1 à 65535) sont requis.');
    if (!_adresse.hasMatch(expediteur.trim())) throw const FormatException('L’adresse d’expéditeur n’est pas une adresse de courriel valide.');
    if (repondreA.trim().isNotEmpty && !_adresse.hasMatch(repondreA.trim())) throw const FormatException('L’adresse « Répondre à » n’est pas une adresse de courriel valide.');
    if (!const ['aucun', 'starttls', 'ssl'].contains(chiffrement)) throw const FormatException('Chiffrement inconnu : aucun, starttls ou ssl.');
    final j = _lireFichier(dossier);
    j
      ..['serveur'] = serveur.trim()
      ..['port'] = port
      ..['chiffrement'] = chiffrement
      ..['identifiant'] = identifiant.trim()
      ..['expediteur'] = expediteur.trim()
      ..['nom'] = nom.trim()
      ..['repondreA'] = repondreA.trim()
      ..['repondreNom'] = repondreNom.trim()
      ..['delai'] = delai < 3 ? 3 : (delai > 60 ? 60 : delai)
      ..['verifierCertificat'] = verifierCertificat
      ..remove('testeOk')
      ..remove('testeLe')
      ..remove('testeEchec');
    if (motDePasse != null && motDePasse.isNotEmpty) {
      j.remove('mdp');
      j.remove('mdp_chiffre');
      final locale = ConfigPairPoste.cleLocale;
      if (locale != null) {
        j['mdp_chiffre'] = _chiffrer(motDePasse, locale);
      } else {
        j['mdp'] = motDePasse;
      }
    }
    _ecrireFichier(dossier, j);
  }

  /// Retient le résultat du dernier test de la configuration ENREGISTRÉE.
  static void noterTest(String dossier, {required bool ok, String? echec}) {
    final j = _lireFichier(dossier);
    if (j['serveur'] == null) return;
    j['testeOk'] = ok;
    j['testeLe'] = DateTime.now().toIso8601String();
    j['testeEchec'] = echec;
    _ecrireFichier(dossier, j);
  }

  static void effacer(String dossier) {
    final f = _fichier(dossier);
    if (f.existsSync()) f.deleteSync();
  }
}
