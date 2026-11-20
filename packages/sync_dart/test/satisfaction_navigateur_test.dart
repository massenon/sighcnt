// L'ENVELOPPE D'UN VRAI CHROME (lot SAT, ADR-0009) : `apps/web/tests/navigateur/satisfaction.cjs` charge la page publique servie par le relais Laravel, la remplit, clique « Envoyer » et capture
// l'enveloppe réellement postée (WebCrypto : X25519, HKDF-SHA-256, AES-256-GCM, rembourrage). La mère Dart l'OUVRE avec la clé dérivée de la clé de la clinique de test : c'est la preuve
// d'interopérabilité entre le navigateur et le poste mère (deux implémentations indépendantes). Régénération : voir l'en-tête du script.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_sync/src/satisfaction_sceau.dart';
import 'package:test/test.dart';

List<int> cleDeTest() => List<int>.generate(32, (i) => (i * 11 + 5) & 0xff);

void main() {
  final f = (jsonDecode(File('test/vecteurs/satisfaction_navigateur.json').readAsStringSync()) as Map).cast<String, Object?>();
  final env = (f['enveloppe'] as Map).cast<String, Object?>();

  test('la clé publique publiée est celle que la mère dérive de la clé de la clinique', () async {
    expect(base64.encode(await clePubliqueSatisfaction(cleDeTest())), f['cle']);
  });

  test('l’enveloppe fabriquée par Chrome est ouverte par la mère Dart : le clair est exactement ce que le patient a saisi, plus l’identifiant', () async {
    final clair = (await ouvrirEnveloppe(env, '${env['id']}', await paireSatisfaction(cleDeTest())) as Map).cast<String, Object?>();
    final attendu = (f['clairAttendu'] as Map).cast<String, Object?>();
    expect({...clair}..remove('id'), attendu);
    expect(clair['id'], env['id']);
  });

  test('l’enveloppe est rembourrée (palier de 1 Kio), ne porte que {v, id, epk, iv, ct, piege} et n’a posé aucun cookie', () {
    expect(base64.decode('${env['ct']}').length, 1040);
    expect(env.keys.toSet(), {'v', 'id', 'epk', 'iv', 'ct', 'piege'});
    expect(env['piege'], '', reason: 'le champ piège reste vide pour un humain');
    expect(f['cookies'], isEmpty);
  });

  test('toute altération est refusée : octet changé, mauvaise donnée associée (identifiant), mauvaise clé', () async {
    final paire = await paireSatisfaction(cleDeTest());
    final ct = base64.decode('${env['ct']}')..[10] ^= 1;
    await expectLater(ouvrirEnveloppe({...env, 'ct': base64.encode(ct)}, '${env['id']}', paire), throwsA(isA<EnveloppeIllisible>()));
    await expectLater(ouvrirEnveloppe(env, 'ffffffffffffffffffffffffffffffff', paire), throwsA(isA<EnveloppeIllisible>()));
    await expectLater(ouvrirEnveloppe(env, '${env['id']}', await paireSatisfaction(List<int>.generate(32, (i) => i))), throwsA(isA<EnveloppeIllisible>()));
  });

  test('aller-retour Dart : sceller puis ouvrir, rembourrage au palier suivant pour un long commentaire', () async {
    final pub = await clePubliqueSatisfaction(cleDeTest());
    final court = await sceller({'a': 1}, 'a' * 32, pub);
    final long = await sceller({'t': 'x' * 1500}, 'b' * 32, pub);
    expect(base64.decode('${court['ct']}').length, 1040);
    expect(base64.decode('${long['ct']}').length, 2064);
    expect(await ouvrirEnveloppe(long, 'b' * 32, await paireSatisfaction(cleDeTest())), {'t': 'x' * 1500});
  });
}
