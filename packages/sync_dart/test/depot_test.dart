import 'dart:io';

import 'package:sigh_sync/src/depot.dart';
import 'package:test/test.dart';

/// Le MÊME contrat sur les deux moteurs : SQLite toujours ; PostgreSQL si `SIGH_PG_URL` est défini
/// (postgres://utilisateur:motdepasse@hôte:port — une base jetable est créée puis supprimée).
void main() {
  final pgUrl = Platform.environment['SIGH_PG_URL'];
  final moteurs = <String, Future<(Depot, Future<void> Function())> Function()>{
    'sqlite': () async => (DepotSqlite(':memory:') as Depot, () async {}),
    if (pgUrl != null && pgUrl.isNotEmpty)
      'postgresql': () async {
        final admin = await Depot.ouvrir('$pgUrl/postgres');
        final nom = 'sigh_test_depot_${DateTime.now().microsecondsSinceEpoch}';
        await admin.exec('CREATE DATABASE $nom');
        final d = await Depot.ouvrir('$pgUrl/$nom');
        return (d, () async {
          await d.fermer();
          await admin.exec('DROP DATABASE IF EXISTS $nom WITH (FORCE)');
          await admin.fermer();
        });
      },
  };

  for (final entree in moteurs.entries) {
    group('dépôt ${entree.key}', () {
      late Depot d;
      late Future<void> Function() nettoyer;
      setUp(() async {
        final (depot, fin) = await entree.value();
        d = depot;
        nettoyer = fin;
        await d.initialiser('CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT); CREATE TABLE IF NOT EXISTS t (id {AUTO}, d TEXT, n BIGINT)');
      });
      tearDown(() => nettoyer());

      test('méta-données : écrire, relire, réécrire (ON CONFLICT)', () async {
        expect(await d.meta('x'), isNull);
        await d.poserMeta('x', 1);
        await d.poserMeta('x', 2);
        expect(await d.metaInt('x'), 2);
        expect(await d.metaInt('absent', 7), 7);
      });

      test('RETURNING rend la clé auto-incrémentée, strictement croissante', () async {
        final a = (await d.select('INSERT INTO t(d,n) VALUES(?,?) RETURNING id', ['a', 1])).first['id'] as int;
        final b = (await d.select('INSERT INTO t(d,n) VALUES(?,?) RETURNING id', ['b', 2])).first['id'] as int;
        expect(b, greaterThan(a));
      });

      test('une transaction qui échoue est ANNULÉE en entier', () async {
        await d.exec('INSERT INTO t(d,n) VALUES(?,?)', ['avant', 1]);
        await expectLater(d.tx(() async {
          await d.exec('INSERT INTO t(d,n) VALUES(?,?)', ['dedans', 2]);
          throw StateError('échec au milieu');
        }), throwsStateError);
        expect((await d.select('SELECT d FROM t ORDER BY id')).map((r) => r['d']), ['avant']);
      });

      test('une transaction imbriquée se fond dans la plus extérieure', () async {
        await expectLater(d.tx(() async {
          await d.tx(() => d.exec('INSERT INTO t(d,n) VALUES(?,?)', ['interne', 1]));
          throw StateError('la plus extérieure décide');
        }), throwsStateError);
        expect(await d.select('SELECT * FROM t'), isEmpty);
      });

      test('extraction JSON identique : champJson', () async {
        await d.exec('INSERT INTO t(d,n) VALUES(?,?)', ['{"code":"CNT/12/26","x":1}', 1]);
        final r = await d.select('SELECT ${d.champJson('d', 'code')} AS c FROM t');
        expect(r.first['c'], 'CNT/12/26');
      });

      test('les sommes sont des entiers (CAST … AS BIGINT) sur les deux moteurs', () async {
        await d.exec('INSERT INTO t(d,n) VALUES(?,?)', ['a', 5]);
        await d.exec('INSERT INTO t(d,n) VALUES(?,?)', ['b', 7]);
        final s = (await d.select('SELECT CAST(COALESCE(SUM(n),0) AS BIGINT) AS s FROM t')).first['s'];
        expect(s, isA<int>());
        expect(s, 12);
      });

      test('recalerSequence : les clés rejouées gardent leur numéro, la suite repart de là', () async {
        await d.exec('INSERT INTO t(id,d,n) VALUES(?,?,?)', [41, 'rejoue', 1]);
        await d.recalerSequence('t', 'id', 41);
        final suivant = (await d.select('INSERT INTO t(d,n) VALUES(?,?) RETURNING id', ['suite', 2])).first['id'] as int;
        expect(suivant, 42);
      });
    });
  }
}
