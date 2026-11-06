// Le coffre de la clé : fabriqué sur le poste par une phrase secrète d'au moins 12 caractères, relisible avec elle seule, jamais la clé nue.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sigh_poste/sync/recuperation_cle.dart';

void main() {
  final cle = '0123456789abcdef' * 4;

  test('un coffre se rouvre avec sa phrase et seulement elle', () async {
    final c = await RecuperationCle.fabriquerCoffre(cle, 'phrase secrete longue');
    expect(c['kdf'], 'PBKDF2-SHA256');
    expect(c['iter'], 200000);
    expect(jsonEncode(c), isNot(contains(cle)), reason: 'jamais la clé nue');
    expect(base64.decode('${c['ct']}'), hasLength(48), reason: '32 octets de clé et 16 d\'étiquette GCM : le format que le relais exige');
    expect(await RecuperationCle.ouvrirCoffre(c, 'phrase secrete longue'), cle);
    await expectLater(RecuperationCle.ouvrirCoffre(c, 'une autre phrase longue'), throwsA(isA<StateError>()));
  });

  test('une phrase de moins de 12 caractères est refusée, nommément', () async {
    await expectLater(RecuperationCle.fabriquerCoffre(cle, 'onze-carac'), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('12 caractères'))));
  });

  test('une clé qui n\'est pas de 256 bits est refusée', () async {
    await expectLater(RecuperationCle.fabriquerCoffre('abcd', 'phrase secrete longue'), throwsA(isA<StateError>()));
  });

  test('l\'envoi poste le coffre seul, sous le jeton de l\'appareil ; les refus du relais sont nommés', () async {
    final c = await RecuperationCle.fabriquerCoffre(cle, 'phrase secrete longue');
    late http.Request vue;
    final ok = MockClient((r) async {
      vue = r;
      return http.Response('{"envoye":true}', 200);
    });
    await RecuperationCle.envoyer(relais: 'http://relais/', jeton: 'u.s', courriel: 'a@b.bj', coffre: c, client: ok);
    expect(vue.url.toString(), 'http://relais/recuperation/envoyer');
    expect(vue.headers['authorization'], 'Bearer u.s');
    expect(vue.body, isNot(contains(cle)));
    expect(vue.body, isNot(contains('phrase secrete longue')));
    expect((jsonDecode(vue.body) as Map).keys, {'courriel', 'coffre'});

    final refus = MockClient((r) async => http.Response('{"code":"recuperation_desactivee","motif":"La récupération de la clé par courriel est désactivée sur ce relais."}', 409));
    await expectLater(RecuperationCle.envoyer(relais: 'http://relais', jeton: 'u.s', courriel: 'a@b.bj', coffre: c, client: refus),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('désactivée'))));
    // Le destinataire n'est plus choisi par le poste : le relais n'écrit qu'à l'adresse enregistrée par le superadmin, et ses deux refus s'affichent tels quels.
    final autre = MockClient((r) async => http.Response('{"code":"destinataire_non_autorise","motif":"Le coffre ne part qu\'à l\'adresse de récupération enregistrée par le superadmin."}', 422));
    await expectLater(RecuperationCle.envoyer(relais: 'http://relais', jeton: 'u.s', courriel: 'autre@b.bj', coffre: c, client: autre),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('adresse de récupération enregistrée'))));
    final sans = MockClient((r) async => http.Response('{"code":"adresse_non_enregistree","motif":"Aucune adresse de récupération n\'est enregistrée sur ce relais : le superadmin doit l\'enregistrer dans ses paramètres."}', 409));
    await expectLater(RecuperationCle.envoyer(relais: 'http://relais', jeton: 'u.s', courriel: 'a@b.bj', coffre: c, client: sans),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('le superadmin doit l\'enregistrer'))));
    final panne = MockClient((r) async => throw Exception('réseau coupé'));
    await expectLater(RecuperationCle.envoyer(relais: 'http://relais', jeton: 'u.s', courriel: 'a@b.bj', coffre: c, client: panne),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('ne répond pas'))));
  });
}
