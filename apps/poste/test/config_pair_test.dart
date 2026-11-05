// ADR-0006 : le mode pair ne démarre que sur un `pair.json` complet ; une configuration à moitié faite est refusée en le disant.
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

  test('clé trop courte, relais absent, JSON cassé : refus nommé', () {
    ecrire('{"actif":true,"relais":"http://r","cle":"abcd"}');
    expect(() => ConfigPairPoste.lire(d.path), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('64'))));
    ecrire('{"actif":true,"cle":"$cle"}');
    expect(() => ConfigPairPoste.lire(d.path), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('relais'))));
    ecrire('pas du json');
    expect(() => ConfigPairPoste.lire(d.path), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('illisible'))));
  });
}
