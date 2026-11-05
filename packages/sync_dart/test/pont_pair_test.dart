import 'dart:convert';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_sync/src/commun.dart';
import 'package:sigh_sync/src/mere.dart';
import 'package:test/test.dart';

/// ADR-0006 : la mère Dart rejoue les opérations relevées par la règle de fusion du domaine ; elle ne tranche jamais seule et refuse en nommant ce qui n'est pas un conflit.
void main() {
  late Mere m;
  setUp(() async => m = await Mere.creer(ConfigMere(port: 0, dbChemin: ':memory:')));

  Future<void> poser(OperationPair o) => m.base.exec('INSERT INTO pair_ops(id,json) VALUES(?,?)', [o.id, jsonEncode(o.versJson())]);
  OperationPair op(String id, String app, int hlc, String type, Map<String, Object?> champs, {Map<String, Object?>? vu}) =>
      OperationPair(id: id, appareil: app, hlc: hlc, collection: 'patients', fiche: 'p1', type: type, champs: champs, vu: vu, role: 'reception');

  test('un conflit entre deux appareils est marqué, la décision de la mère le lève, un second essai est refusé en le nommant', () async {
    await poser(op('a', 'F1', 10, 'creer', {'telephone': '90'}));
    await poser(op('b', 'F1', 20, 'modifier', {'telephone': '91'}, vu: {'telephone': 10}));
    await poser(op('c', 'F2', 21, 'modifier', {'telephone': '92'}, vu: {'telephone': 10}));
    var e = await m.pair.etat();
    expect((e['conflits'] as List), hasLength(1));
    final r = await m.pair.trancher({'fiche': 'patients/p1', 'champ': 'telephone', 'valeur': '91'});
    expect(r['seq'], 1);
    e = await m.pair.etat();
    expect((e['conflits'] as List), isEmpty);
    expect(((e['fiches'] as Map)['patients/p1'] as Map)['data'], {'telephone': '91'});
    await expectLater(m.pair.trancher({'fiche': 'patients/p1', 'champ': 'telephone', 'valeur': '91'}), throwsA(isA<Err>().having((x) => x.code, 'code', 'aucun_conflit')));
  });

  test('trancher un champ sans conflit est refusé (409), rien n\'est écrit', () async {
    await poser(op('a', 'F1', 10, 'creer', {'telephone': '90'}));
    await expectLater(m.pair.trancher({'fiche': 'patients/p1', 'champ': 'nom', 'valeur': 'x'}), throwsA(isA<Err>().having((x) => x.statut, 'statut', 409)));
    expect(await m.base.metaInt('pair_seq'), 0);
    expect((await m.base.select('SELECT COUNT(*) AS n FROM pair_sortie')).first['n'], 0);
  });
}
