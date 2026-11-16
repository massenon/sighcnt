/// L'ENVELOPPE DE LA SATISFACTION EN LIGNE (lot SAT, ADR-0009), côté mère : ouverture d'une enveloppe scellée dans le navigateur, et scellement (utilisé par les tests pour jouer le
/// navigateur et par la mesure d'interopérabilité avec une enveloppe produite par un vrai Chrome). X25519 éphémère, HKDF-SHA-256 (sel : clé éphémère puis clé publique de la clinique,
/// info `sigh-satisfaction-v1`), AES-256-GCM (donnée associée : l'identifiant de la réponse), texte clair rembourré à 1, 2, 4 ou 8 Kio (deux octets de longueur puis zéros).
///
/// La PAIRE de la clinique est DÉRIVÉE de la clé de la clinique (HKDF, info `sigh-satisfaction-cle-v1`) : aucun secret de plus à sauvegarder. La clé privée n'existe qu'ici ; le relais
/// ne reçoit que la clé PUBLIQUE.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const _infoEnveloppe = 'sigh-satisfaction-v1';
const _infoCle = 'sigh-satisfaction-cle-v1';
const paliersRembourrage = [1024, 2048, 4096, 8192];

class EnveloppeIllisible implements Exception {
  EnveloppeIllisible(this.motif);
  final String motif;
  @override
  String toString() => 'enveloppe_illisible : $motif';
}

/// La paire X25519 de la clinique, tirée de sa clé (32 octets).
Future<SimpleKeyPair> paireSatisfaction(List<int> cleClinique) async {
  final graine = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(secretKey: SecretKey(cleClinique), nonce: const <int>[], info: utf8.encode(_infoCle));
  return X25519().newKeyPairFromSeed(await graine.extractBytes());
}

Future<List<int>> clePubliqueSatisfaction(List<int> cleClinique) async => (await (await paireSatisfaction(cleClinique)).extractPublicKey()).bytes;

Future<SecretKey> _cleEnveloppe(SecretKey partage, List<int> epk, List<int> pub) =>
    Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(secretKey: partage, nonce: [...epk, ...pub], info: utf8.encode(_infoEnveloppe));

/// Ouvre une enveloppe `{v, epk, iv, ct}` d'identifiant [id] ; rend le JSON clair, ou lève [EnveloppeIllisible] (jamais une réponse à demi lue).
Future<Object?> ouvrirEnveloppe(Map bloc, String id, SimpleKeyPair paire) async {
  try {
    if (bloc['v'] != 1) throw EnveloppeIllisible('version inconnue');
    final epk = base64.decode('${bloc['epk']}'), iv = base64.decode('${bloc['iv']}'), ct = base64.decode('${bloc['ct']}');
    if (epk.length != 32 || iv.length != 12 || ct.length < 17) throw EnveloppeIllisible('forme');
    final pub = (await paire.extractPublicKey()).bytes;
    final partage = await X25519().sharedSecretKey(keyPair: paire, remotePublicKey: SimplePublicKey(epk, type: KeyPairType.x25519));
    final cle = await _cleEnveloppe(partage, epk, pub);
    final clair = await AesGcm.with256bits().decrypt(SecretBox(ct.sublist(0, ct.length - 16), nonce: iv, mac: Mac(ct.sublist(ct.length - 16))), secretKey: cle, aad: utf8.encode(id));
    if (clair.length < 2) throw EnveloppeIllisible('rembourrage');
    final n = (clair[0] << 8) | clair[1];
    if (2 + n > clair.length) throw EnveloppeIllisible('longueur');
    return jsonDecode(utf8.decode(clair.sublist(2, 2 + n)));
  } on EnveloppeIllisible {
    rethrow;
  } catch (e) {
    throw EnveloppeIllisible('${e.runtimeType}');
  }
}

/// Scelle [donnees] pour la clé publique [pub] (ce que fait la page publique). [epkSeed] et [iv] : déterministes pour les vecteurs.
Future<Map<String, Object?>> sceller(Object? donnees, String id, List<int> pub, {List<int>? epkSeed, List<int>? iv}) async {
  final x = X25519();
  final eph = epkSeed == null ? await x.newKeyPair() : await x.newKeyPairFromSeed(epkSeed);
  final epk = (await eph.extractPublicKey()).bytes;
  final partage = await x.sharedSecretKey(keyPair: eph, remotePublicKey: SimplePublicKey(pub, type: KeyPairType.x25519));
  final cle = await _cleEnveloppe(partage, epk, pub);
  final clair = utf8.encode(jsonEncode(donnees));
  final taille = paliersRembourrage.firstWhere((p) => clair.length + 2 <= p, orElse: () => throw EnveloppeIllisible('trop long'));
  final rembourre = Uint8List(taille)
    ..[0] = (clair.length >> 8) & 255
    ..[1] = clair.length & 255
    ..setRange(2, 2 + clair.length, clair);
  final boite = await AesGcm.with256bits().encrypt(rembourre, secretKey: cle, nonce: iv, aad: utf8.encode(id));
  return {'v': 1, 'id': id, 'epk': base64.encode(epk), 'iv': base64.encode(boite.nonce), 'ct': base64.encode([...boite.cipherText, ...boite.mac.bytes])};
}
