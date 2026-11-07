import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

/// Un lieu où ranger un secret : le coffre du système sur un vrai téléphone (Keystore Android, Keychain iOS), une table en mémoire en test.
abstract class StockageSecret {
  Future<String?> lire(String cle);
  Future<void> ecrire(String cle, String valeur);
}

/// L'adaptation à `flutter_secure_storage`. NON ÉPROUVÉE : elle se compile et se lit, mais n'a jamais tourné sur un appareil (aucune chaîne native dans
/// l'environnement de rédaction, ECARTS-MAQUETTE E1658).
class StockageFlutterSecure implements StockageSecret {
  StockageFlutterSecure([FlutterSecureStorage? s]) : _s = s ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  @override
  Future<String?> lire(String cle) => _s.read(key: cle);

  @override
  Future<void> ecrire(String cle, String valeur) => _s.write(key: cle, value: valeur);
}

/// Le coffre du code PIN : un HACHÉ SALÉ (PBKDF2-HMAC-SHA256) range dans le stockage secret, jamais le code. Les essais et le blocage y sont retenus
/// aussi : un redémarrage ne rend pas les essais (E1656).
///
/// Limite à connaître (E1657) : le code n'a que quatre chiffres, soit dix mille possibilités. Le hachage ralentit un attaquant qui a COPIÉ le stockage,
/// il ne le met pas hors de portée ; c'est le coffre du système (qui protège le haché) et le blocage qui font la protection. À arbitrer par la revue de sécurité.
class CoffrePinSecurise implements CoffrePin {
  CoffrePinSecurise(this._stockage, {this.iterations = 120000});
  final StockageSecret _stockage;
  final int iterations;

  static const _kSel = 'pin.sel', _kHache = 'pin.hache', _kEssais = 'pin.essais', _kBloque = 'pin.bloque';

  Future<List<int>> _derive(String code, List<int> sel) async {
    final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
    final cle = await kdf.deriveKeyFromPassword(password: code, nonce: sel);
    return cle.extractBytes();
  }

  @override
  Future<bool> aUnCode() async => (await _stockage.lire(_kHache)) != null;

  @override
  Future<void> definir(String code) async {
    final r = mobPinRefusFormat(code);
    if (r != null) throw r;
    final rng = Random.secure();
    final sel = List<int>.generate(16, (_) => rng.nextInt(256));
    await _stockage.ecrire(_kSel, base64Encode(sel));
    await _stockage.ecrire(_kHache, base64Encode(await _derive(code, sel)));
    await poserCompteur(const MobPinCompteur());
  }

  @override
  Future<bool> verifier(String code) async {
    final sel = await _stockage.lire(_kSel), hache = await _stockage.lire(_kHache);
    if (sel == null || hache == null) return false;
    final a = await _derive(code, base64Decode(sel)), b = base64Decode(hache);
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  @override
  Future<MobPinCompteur> compteur() async {
    final bloque = int.tryParse(await _stockage.lire(_kBloque) ?? '');
    return MobPinCompteur(essais: int.tryParse(await _stockage.lire(_kEssais) ?? '') ?? 0, bloqueJusquaMs: bloque == null || bloque == 0 ? null : bloque);
  }

  @override
  Future<void> poserCompteur(MobPinCompteur c) async {
    await _stockage.ecrire(_kEssais, '${c.essais}');
    await _stockage.ecrire(_kBloque, '${c.bloqueJusquaMs ?? 0}');
  }
}

/// Sonde du stockage sécurisé, au démarrage : écrit une valeur, la relit, compare. Rend `null` quand le coffre du système répond, sinon la CAUSE en
/// français. Il n'y a aucun repli silencieux (E1820) : sans coffre, l'application refuse de s'ouvrir et le dit, elle ne range jamais le haché du code
/// ailleurs. NON ÉPROUVÉE sur appareil (aucune chaîne native ici).
Future<String?> sonderStockage(StockageSecret stockage) async {
  const cle = 'sonde.stockage', valeur = 'ok';
  try {
    await stockage.ecrire(cle, valeur);
    final relu = await stockage.lire(cle);
    if (relu != valeur) return 'Le coffre du système n’a pas restitué la valeur de contrôle.';
    return null;
  } catch (e) {
    return 'Le coffre du système répond par une erreur : $e';
  }
}
