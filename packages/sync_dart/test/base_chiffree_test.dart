import 'dart:io';

import 'package:sigh_sync/sigh_sync.dart';
import 'package:sigh_sync/src/commun.dart' show Base, ouvrirSqlite;
import 'package:sigh_sync/src/depot.dart' show DepotSqlite;
import 'package:test/test.dart';

/// La base SQLite de la mère et celle du journal d'un poste sont CHIFFRÉES au repos (limite levée le 03/11/2026).
const cle = '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';
const autre = 'ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100';

bool lisible(String chemin, String motif) => String.fromCharCodes(File(chemin).readAsBytesSync()).contains(motif);

void main() {
  late Directory d;
  setUp(() => d = Directory.systemTemp.createTempSync('bch'));
  tearDown(() => d.deleteSync(recursive: true));

  test('une base chiffrée ne montre aucune donnée en clair et se relit avec la bonne clé seulement', () {
    final chemin = '${d.path}/mere.db';
    var b = Base(chemin, cle);
    b.db.execute('CREATE TABLE t(a)');
    b.db.execute("INSERT INTO t VALUES ('PATIENT-AGBO-confidentiel')");
    b.db.dispose();
    expect(lisible(chemin, 'PATIENT-AGBO-confidentiel'), isFalse);
    expect(lisible(chemin, 'SQLite format 3'), isFalse, reason: 'même l’en-tête SQLite est chiffré');
    b = Base(chemin, cle);
    expect(b.db.select('SELECT a FROM t').single['a'], 'PATIENT-AGBO-confidentiel');
    b.db.dispose();
    expect(() => Base(chemin, autre), throwsA(isA<StateError>().having((e) => '$e', 'message', contains('clé incorrecte'))));
    expect(() => Base(chemin), throwsA(anything), reason: 'sans clé, une base chiffrée ne s’ouvre pas');
  });

  test('MIGRATION : la base EN CLAIR d’un poste d’avant est chiffrée sur place à la première ouverture, sans perdre une ligne', () {
    final chemin = '${d.path}/poste.db';
    final clair = ouvrirSqlite(chemin);
    clair.execute('CREATE TABLE t(a)');
    clair.execute("INSERT INTO t VALUES ('avant-le-chiffrement')");
    clair.dispose();
    expect(lisible(chemin, 'avant-le-chiffrement'), isTrue);
    final b = Base(chemin, cle);
    expect(b.db.select('SELECT a FROM t').single['a'], 'avant-le-chiffrement');
    b.db.dispose();
    expect(lisible(chemin, 'avant-le-chiffrement'), isFalse);
    final encore = Base(chemin, cle);
    expect(encore.db.select('SELECT count(*) AS n FROM t').single['n'], 1);
    encore.db.dispose();
  });

  test('la sauvegarde de la mère (VACUUM INTO) reste chiffrée', () async {
    final depot = DepotSqlite('${d.path}/mere.db', cle);
    await depot.exec('CREATE TABLE t(a)');
    await depot.exec("INSERT INTO t VALUES ('donnee-de-sauvegarde')");
    final bak = await depot.sauvegarder('essai', dossier: '${d.path}/bak');
    await depot.fermer();
    expect(lisible(bak, 'donnee-de-sauvegarde'), isFalse, reason: 'une copie lisible annulerait le chiffrement');
    final relue = Base(bak, cle);
    expect(relue.db.select('SELECT a FROM t').single['a'], 'donnee-de-sauvegarde');
    relue.db.dispose();
  });

  test('sans clé (bancs, développement) : SQLite ordinaire, en mémoire comme sur disque', () {
    final b = Base(':memory:');
    b.db.execute('CREATE TABLE t(a)');
    expect(b.db.select('SELECT count(*) AS n FROM t').single['n'], 0);
    final chemin = '${d.path}/dev.db';
    Base(chemin).db.dispose();
    expect(lisible(chemin, 'SQLite format 3'), isTrue);
  });
}
