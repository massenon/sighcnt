import 'dart:convert';
import 'dart:io';

import 'package:sigh_sync/src/pont.dart';
import 'package:test/test.dart';

List<int> cle(int graine) => List<int>.generate(32, (i) => (i + graine) & 0xff);

void main() {
  final env = Enveloppes(cle(0));
  const meta = (id: 'journal-1', appareil: 'mere', dir: 'journal', n: 1);
  final charge = <String, Object?>{'type': 'journal', 'nom': 'Zébulon-Éléonore', 'note': 'ça va « très » bien — 100 %'};

  Future<Map<String, Object?>> sceller() => env.chiffrer(charge, id: meta.id, appareil: meta.appareil, dir: meta.dir, n: meta.n);

  test('aller-retour : le clair revient intact, accents compris', () async {
    expect(await env.dechiffrer(await sceller()), charge);
  });

  test('deux chiffrements du même clair diffèrent (nonce aléatoire)', () async {
    final a = await sceller();
    final b = await sceller();
    expect(a['ct'], isNot(b['ct']));
    expect(a['nonce'], isNot(b['nonce']));
  });

  test('rien de lisible dans l\'enveloppe : ni nom, ni champ', () async {
    final texte = jsonEncode(await sceller());
    expect(texte, isNot(contains('Zébulon')));
    expect(texte, isNot(contains('nom')));
    expect(utf8.decode(base64.decode((await sceller())['ct']! as String), allowMalformed: true), isNot(contains('Zébulon')));
  });

  test('une enveloppe ALTÉRÉE est rejetée (authentification GCM)', () async {
    final e = await sceller();
    final octets = base64.decode(e['ct']! as String);
    octets[0] ^= 1;
    expect(() => env.dechiffrer({...e, 'ct': base64.encode(octets)}), throwsA(anything));
  });

  test('une enveloppe DÉPLACÉE est rejetée : id, appareil, sens et rang sont authentifiés', () async {
    final e = await sceller();
    for (final alteration in [{'n': 2}, {'id': 'journal-2'}, {'appareil': 'autre'}, {'dir': 'vers_mobile'}]) {
      expect(() => env.dechiffrer({...e, ...alteration}), throwsA(anything), reason: '$alteration');
    }
  });

  test('une MAUVAISE clé ne déchiffre rien', () async {
    final e = await sceller();
    expect(() => Enveloppes(cle(1)).dechiffrer(e), throwsA(anything));
  });

  test('un fichier chiffré (sauvegarde) revient intact ; modifié, il est rejeté', () async {
    final clair = utf8.encode('{"patients": ["Zébulon"]}');
    final chiffre = await env.chiffrerOctets(clair, 'sauvegarde-mere');
    expect(utf8.decode(await env.dechiffrerOctets(chiffre, 'sauvegarde-mere')), '{"patients": ["Zébulon"]}');
    expect(() => env.dechiffrerOctets(chiffre, 'autre-usage'), throwsA(anything));
    chiffre[20] ^= 1;
    expect(() => env.dechiffrerOctets(chiffre, 'sauvegarde-mere'), throwsA(anything));
  });

  test('INTEROPÉRABILITÉ : une enveloppe chiffrée par NODE (banc/crypto.js) se déchiffre en Dart', () async {
    final f = jsonDecode(File('test/vecteurs/enveloppe_node.json').readAsStringSync()) as Map;
    final hex = f['cle_hex'] as String;
    final k = [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
    final clair = await Enveloppes(k).dechiffrer(f['enveloppe'] as Map);
    expect(clair, f['charge']);
  });
}
