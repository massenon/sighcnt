// ADR-0006 : le mode pair ne démarre que sur un `pair.json` complet ; une configuration à moitié faite est refusée en le disant.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/sync/config_pair.dart';

void main() {
  late Directory d;
  setUp(() => d = Directory.systemTemp.createTempSync('pair-cfg'));
  tearDown(() => d.deleteSync(recursive: true));
  void ecrire(String t) => File('${d.path}/pair.json').writeAsStringSync(t);
  final cle = 'ab' * 32;

  test('sans fichier ou désactivé : le poste ne change pas de comportement', () {
    expect(ConfigPairPoste.lire(d.path), isNull);
    ecrire('{"actif":false,"relais":"http://r","cle":"$cle"}');
    expect(ConfigPairPoste.lire(d.path), isNull);
  });

  test('configuration complète', () {
    ecrire('{"actif":true,"relais":"http://r","cle":"$cle","nom":"F1","code":"XYZ"}');
    final c = ConfigPairPoste.lire(d.path)!;
    expect((c.relais, c.nom, c.code), ('http://r', 'F1', 'XYZ'));
  });

  protectionDeLaCle();

  test('clé trop courte, relais absent, JSON cassé : refus nommé', () {
    ecrire('{"actif":true,"relais":"http://r","cle":"abcd"}');
    expect(() => ConfigPairPoste.lire(d.path), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('64'))));
    ecrire('{"actif":true,"cle":"$cle"}');
    expect(() => ConfigPairPoste.lire(d.path), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('relais'))));
    ecrire('pas du json');
    expect(() => ConfigPairPoste.lire(d.path), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('illisible'))));
  });
}

// Protection de la clé sur le disque (E2220) : chiffrée par la clé locale du poste, migrée depuis le clair, altération refusée en le disant.
void protectionDeLaCle() {
  group('clé chiffrée au repos', () {
    late Directory d;
    final locale = List<int>.generate(32, (i) => i + 1);
    final cle = 'cd' * 32;
    setUp(() {
      d = Directory.systemTemp.createTempSync('pair-cle');
      ConfigPairPoste.cleLocale = locale;
    });
    tearDown(() {
      ConfigPairPoste.cleLocale = null;
      d.deleteSync(recursive: true);
    });
    String brut() => File('${d.path}/pair.json').readAsStringSync();

    test('la clé n\'est jamais écrite en clair, et se relit', () {
      ConfigPairPoste.ecrire(d.path, actif: true, relais: 'http://r', nom: 'F1', cleHex: cle);
      expect(brut(), isNot(contains(cle)));
      expect(brut(), contains('cle_chiffree'));
      expect(ConfigPairPoste.lire(d.path)!.cleHex, cle);
      expect(ConfigPairPoste.lireBrut(d.path)['cle'], cle, reason: 'l\'écran lit la clé en mémoire sans la montrer');
    });

    test('un réglage qui ne touche pas la clé la conserve', () {
      ConfigPairPoste.ecrire(d.path, actif: true, relais: 'http://r', cleHex: cle);
      ConfigPairPoste.ecrire(d.path, nom: 'F2');
      expect(ConfigPairPoste.lire(d.path)!.cleHex, cle);
      expect(brut(), isNot(contains(cle)));
    });

    test('migration : un pair.json en clair est réécrit chiffré au premier lancement', () {
      File('${d.path}/pair.json').writeAsStringSync('{"actif":true,"relais":"http://r","cle":"$cle","nom":"F1"}');
      expect(brut(), contains(cle));
      expect(ConfigPairPoste.lire(d.path)!.cleHex, cle);
      expect(brut(), isNot(contains(cle)), reason: 'le clair ne reste pas sur le disque');
      expect(ConfigPairPoste.lire(d.path)!.cleHex, cle, reason: 'et se relit après migration');
    });

    test('altération : refus nommé, jamais une clé devinée', () {
      ConfigPairPoste.ecrire(d.path, actif: true, relais: 'http://r', cleHex: cle);
      final j = jsonDecode(brut()) as Map<String, Object?>;
      final octets = base64.decode('${j['cle_chiffree']}');
      octets[octets.length - 1] ^= 1;
      j['cle_chiffree'] = base64.encode(octets);
      File('${d.path}/pair.json').writeAsStringSync(jsonEncode(j));
      expect(() => ConfigPairPoste.lire(d.path), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('illisible'))));
      expect(ConfigPairPoste.lireBrut(d.path)['cle_illisible'], true, reason: 'l\'écran le dit au lieu de proposer une clé « absente »');
    });

    test('un réglage ne remplace pas en silence une clé illisible, la régénérer reste possible', () {
      ConfigPairPoste.ecrire(d.path, actif: true, relais: 'http://r', cleHex: cle);
      final j = jsonDecode(brut()) as Map<String, Object?>..['cle_chiffree'] = base64.encode(List.filled(40, 7));
      File('${d.path}/pair.json').writeAsStringSync(jsonEncode(j));
      expect(() => ConfigPairPoste.ecrire(d.path, nom: 'F2'), throwsA(isA<FormatException>()));
      ConfigPairPoste.ecrire(d.path, cleHex: 'ef' * 32);
      expect(ConfigPairPoste.lire(d.path)!.cleHex, 'ef' * 32);
    });

    test('le fichier chiffré par un autre poste (autre clé locale) est refusé', () {
      ConfigPairPoste.ecrire(d.path, actif: true, relais: 'http://r', cleHex: cle);
      ConfigPairPoste.cleLocale = List<int>.generate(32, (i) => 200 - i);
      expect(() => ConfigPairPoste.lire(d.path), throwsA(isA<FormatException>()));
    });

    test('sans clé locale (développement, SIGH_CHIFFREMENT=non) : clair, comme le magasin ; un fichier chiffré est refusé', () {
      ConfigPairPoste.ecrire(d.path, actif: true, relais: 'http://r', cleHex: cle);
      ConfigPairPoste.cleLocale = null;
      expect(() => ConfigPairPoste.lire(d.path), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('clé locale'))));
      File('${d.path}/pair.json').deleteSync();
      ConfigPairPoste.ecrire(d.path, actif: true, relais: 'http://r', cleHex: cle);
      expect(brut(), contains(cle));
      expect(ConfigPairPoste.lire(d.path)!.cleHex, cle);
    });
  });
}
