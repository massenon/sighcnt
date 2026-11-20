import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

/// RÉCUPÉRATION DE LA CLÉ DE LA CLINIQUE PAR COURRIEL. La clé est chiffrée SUR LE POSTE par une phrase secrète que ni le poste ni le relais ne gardent : le relais
/// ne reçoit qu'un COFFRE (PBKDF2-SHA256 200 000 tours, AES-256-GCM, données associées `cle-clinique-v1`), le même format que celui de la page de consultation
/// du relais (`public/js/consultation.js`), qui sait l'ouvrir. Perdre la phrase rend le coffre inutilisable : c'est voulu.
class RecuperationCle {
  const RecuperationCle._();

  static const iterations = 200000;
  static const longueurMinimaleDePhrase = 12;
  static const _aad = 'cle-clinique-v1';

  /// Le client HTTP par défaut de l'envoi (les tests y posent un faux client ; en production : `null`, un client neuf par envoi).
  static http.Client? clientParDefaut;

  /// Pour les tests d'écran seulement : remplace la dérivation PBKDF2 (200 000 tours, qui ne tourne pas dans l'horloge simulée des tests de widgets) par un coffre
  /// déjà fabriqué. Les contrôles de la phrase et de la clé restent joués AVANT. `null` en production.
  static Future<Map<String, Object?>> Function(String cleHex, String phrase)? fabriquePourTests;

  /// Refus nommé ([StateError]) si la phrase fait moins de 12 caractères ou si la clé n'est pas de 256 bits en hexadécimal.
  static Future<Map<String, Object?>> fabriquerCoffre(String cleHex, String phrase, {Random? alea}) async {
    if (phrase.length < longueurMinimaleDePhrase) {
      throw StateError('La phrase secrète doit comporter au moins $longueurMinimaleDePhrase caractères.');
    }
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(cleHex)) throw StateError('La clé de la clinique doit faire 64 caractères hexadécimaux (256 bits).');
    if (fabriquePourTests != null) return fabriquePourTests!(cleHex, phrase);
    final r = alea ?? Random.secure();
    List<int> octets(int n) => [for (var i = 0; i < n; i++) r.nextInt(256)];
    final sel = octets(16), nonce = octets(12);
    final cle = [for (var i = 0; i < 64; i += 2) int.parse(cleHex.substring(i, i + 2), radix: 16)];
    final derivee = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256).deriveKeyFromPassword(password: phrase, nonce: sel);
    final boite = await AesGcm.with256bits().encrypt(cle, secretKey: derivee, nonce: nonce, aad: utf8.encode(_aad));
    return {
      'v': 1,
      'kdf': 'PBKDF2-SHA256',
      'iter': iterations,
      'sel': base64.encode(sel),
      'nonce': base64.encode(nonce),
      'ct': base64.encode([...boite.cipherText, ...boite.mac.bytes]),
    };
  }

  /// Rouvre un coffre avec sa phrase (la preuve que ce qu'on envoie se relit). Refus nommé si la phrase est fausse ou le coffre altéré.
  static Future<String> ouvrirCoffre(Map<String, Object?> coffre, String phrase) async {
    try {
      final derivee = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: (coffre['iter'] as num).toInt(), bits: 256)
          .deriveKeyFromPassword(password: phrase, nonce: base64.decode('${coffre['sel']}'));
      final brut = base64.decode('${coffre['ct']}');
      final clair = await AesGcm.with256bits().decrypt(
          SecretBox(brut.sublist(0, brut.length - 16), nonce: base64.decode('${coffre['nonce']}'), mac: Mac(brut.sublist(brut.length - 16))),
          secretKey: derivee,
          aad: utf8.encode(_aad));
      return clair.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    } catch (_) {
      throw StateError('Phrase secrète incorrecte, ou coffre altéré.');
    }
  }

  /// Demande au relais d'envoyer le coffre à [courriel] (route `POST /recuperation/envoyer`, jeton d'appareil). Les refus du relais sont nommés (`StateError` portant
  /// son motif) : réglage désactivé, coffre invalide, trois envois par heure dépassés.
  static Future<void> envoyer({required String relais, required String jeton, required String courriel, required Map<String, Object?> coffre, http.Client? client}) async {
    final c = client ?? clientParDefaut ?? http.Client();
    final http.Response rep;
    try {
      rep = await c
          .post(Uri.parse('${relais.replaceAll(RegExp(r'/+$'), '')}/recuperation/envoyer'),
              headers: {'content-type': 'application/json', 'authorization': 'Bearer $jeton'}, body: jsonEncode({'courriel': courriel, 'coffre': coffre}))
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw StateError('Le relais ne répond pas : $e');
    } finally {
      if (client == null && clientParDefaut == null) c.close();
    }
    if (rep.statusCode == 200) return;
    String motif = 'refus du relais (${rep.statusCode})';
    try {
      final j = jsonDecode(rep.body);
      if (j is Map && '${j['motif'] ?? ''}'.isNotEmpty) motif = '${j['motif']}';
    } catch (_) {}
    throw StateError(motif);
  }
}
