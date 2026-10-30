/// Le DÉPÔT de la mère : une interface asynchrone, deux moteurs — SQLite (essais, poste unique) et PostgreSQL (la
/// cible : « le PostgreSQL du serveur local »). Le SQL de la mère est écrit dans le sous-ensemble commun aux deux
/// (`ON CONFLICT`, `RETURNING`, `CAST … AS BIGINT`) ; les rares écarts passent par ce fichier : DDL, extraction JSON,
/// séquence, sauvegarde.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:sqlite3/sqlite3.dart' as sq;

typedef Ligne = Map<String, Object?>;

/// Exclusion mutuelle : une seule opération touche le dépôt à la fois. Indispensable avec une SEULE connexion
/// PostgreSQL — sans elle, la requête d'un autre poste entrerait dans la transaction en cours.
class Verrou {
  Future<void> _fin = Future<void>.value();

  Future<T> executer<T>(Future<T> Function() f) {
    final c = Completer<T>();
    final precedent = _fin;
    _fin = c.future.then<void>((_) {}, onError: (Object _) {});
    precedent.then((_) async {
      try {
        c.complete(await f());
      } catch (e, s) {
        c.completeError(e, s);
      }
    });
    return c.future;
  }
}

abstract class Depot {
  /// `sqlite` ou `pg`.
  String get dialecte;

  Future<List<Ligne>> select(String sql, [List<Object?> p = const []]);
  Future<void> exec(String sql, [List<Object?> p = const []]);

  /// Transaction : la plus extérieure décide (les imbriquées s'y fondent).
  Future<T> tx<T>(Future<T> Function() f);

  /// Expression SQL lisant un champ texte d'une colonne qui porte du JSON (stocké en TEXT dans les deux moteurs).
  String champJson(String colonne, String champ);

  /// Pose la valeur courante d'une séquence auto-incrémentée (restauration : les `seq` rejoués gardent leur numéro).
  Future<void> recalerSequence(String table, String colonne, int valeur);

  /// Copie de sécurité AVANT un geste irréversible ; rend le chemin du fichier produit.
  Future<String> sauvegarder(String prefixe, {String? dossier});

  Future<void> fermer();

  /// Crée les tables. `{AUTO}` est remplacé par la clé auto-incrémentée du moteur.
  Future<void> initialiser(String ddl) async {
    final auto = dialecte == 'pg' ? 'BIGSERIAL PRIMARY KEY' : 'INTEGER PRIMARY KEY AUTOINCREMENT';
    for (final instruction in ddl.replaceAll('{AUTO}', auto).split(';')) {
      if (instruction.trim().isNotEmpty) await exec(instruction);
    }
  }

  // --- méta-données --------------------------------------------------------------------------------------
  Future<String?> meta(String k) async {
    final r = await select('SELECT v FROM meta WHERE k=?', [k]);
    return r.isEmpty ? null : r.first['v'] as String?;
  }

  Future<int> metaInt(String k, [int defaut = 0]) async => int.tryParse(await meta(k) ?? '') ?? defaut;

  Future<void> poserMeta(String k, Object? v) => exec('INSERT INTO meta(k,v) VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v', [k, '$v']);

  /// Ouvre le dépôt désigné : `postgres://utilisateur:mot_de_passe@hôte:port/base` ou un chemin SQLite (`:memory:` accepté).
  static Future<Depot> ouvrir(String cible) async {
    if (cible.startsWith('postgres://') || cible.startsWith('postgresql://')) return DepotPostgres.ouvrir(Uri.parse(cible));
    return DepotSqlite(cible);
  }
}

const tablesMere = ['meta', 'operations', 'resultats', 'fiches', 'appareils', 'codes', 'conflits', 'plages', 'baux', 'acks', 'portee', 'sortie'];

class DepotSqlite extends Depot {
  DepotSqlite(this.chemin) : db = chemin == ':memory:' ? sq.sqlite3.openInMemory() : sq.sqlite3.open(chemin) {
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA busy_timeout = 5000');
  }
  final String chemin;
  final sq.Database db;
  int _prof = 0;

  @override
  String get dialecte => 'sqlite';

  @override
  Future<List<Ligne>> select(String sql, [List<Object?> p = const []]) async => db.select(sql, p).map((r) => <String, Object?>{...r}).toList();

  @override
  Future<void> exec(String sql, [List<Object?> p = const []]) async => db.execute(sql, p);

  @override
  Future<T> tx<T>(Future<T> Function() f) async {
    if (_prof > 0) return f();
    _prof++;
    db.execute('BEGIN IMMEDIATE');
    try {
      final r = await f();
      db.execute('COMMIT');
      return r;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      _prof--;
    }
  }

  @override
  String champJson(String colonne, String champ) => "json_extract($colonne,'\$.$champ')";

  @override
  Future<void> recalerSequence(String table, String colonne, int valeur) async =>
      db.execute("INSERT OR REPLACE INTO sqlite_sequence(name,seq) VALUES(?,?)", [table, valeur]);

  @override
  Future<String> sauvegarder(String prefixe, {String? dossier}) async {
    final nom = '${chemin == ':memory:' ? 'mere' : chemin.split(RegExp(r'[\\/]')).last}.$prefixe-${DateTime.now().millisecondsSinceEpoch}.bak';
    final f = dossier != null ? '${Directory(dossier).absolute.path}/$nom' : '${chemin == ':memory:' ? Directory.systemTemp.path : File(chemin).parent.path}/$nom';
    Directory(File(f).parent.path).createSync(recursive: true);
    db.execute("VACUUM INTO '${f.replaceAll("'", '')}'");
    return f;
  }

  @override
  Future<void> fermer() async => db.close();
}

class DepotPostgres extends Depot {
  DepotPostgres._(this.conn, this.nom);
  final pg.Connection conn;
  final String nom;
  int _prof = 0;

  static Future<DepotPostgres> ouvrir(Uri u) async {
    final info = u.userInfo.split(':');
    final conn = await pg.Connection.open(
      pg.Endpoint(
        host: u.host,
        port: u.hasPort ? u.port : 5432,
        database: u.pathSegments.isEmpty ? 'postgres' : u.pathSegments.first,
        username: Uri.decodeComponent(info.first),
        password: info.length > 1 ? Uri.decodeComponent(info.sublist(1).join(':')) : null,
      ),
      settings: pg.ConnectionSettings(sslMode: pg.SslMode.disable),
    );
    return DepotPostgres._(conn, u.pathSegments.isEmpty ? 'postgres' : u.pathSegments.first);
  }

  /// `?` → `$1`, `$2`… (aucune requête de la mère ne porte de `?` dans un littéral).
  String _p(String sql) {
    var i = 0;
    return sql.replaceAllMapped('?', (_) => '\$${++i}');
  }

  @override
  String get dialecte => 'pg';

  @override
  Future<List<Ligne>> select(String sql, [List<Object?> p = const []]) async {
    final r = await conn.execute(_p(sql), parameters: p);
    return r.map((x) => x.toColumnMap()).toList();
  }

  @override
  Future<void> exec(String sql, [List<Object?> p = const []]) async {
    await conn.execute(_p(sql), parameters: p);
  }

  @override
  Future<T> tx<T>(Future<T> Function() f) async {
    if (_prof > 0) return f();
    _prof++;
    await conn.execute('BEGIN');
    try {
      final r = await f();
      await conn.execute('COMMIT');
      return r;
    } catch (_) {
      await conn.execute('ROLLBACK');
      rethrow;
    } finally {
      _prof--;
    }
  }

  @override
  String champJson(String colonne, String champ) => "(($colonne)::jsonb ->> '$champ')";

  @override
  Future<void> recalerSequence(String table, String colonne, int valeur) async {
    if (valeur < 1) return;
    await conn.execute(pg.Sql.named("SELECT setval(pg_get_serial_sequence('$table','$colonne'), @v, true)"), parameters: {'v': valeur});
  }

  /// Sauvegarde logique en JSON (indépendante de la présence de `pg_dump` sur le poste) : toutes les tables de la mère.
  /// La sauvegarde SYSTÈME (pg_dump chiffré, réplica hors site) reste celle de l'exploitation (spec §10).
  @override
  Future<String> sauvegarder(String prefixe, {String? dossier}) async {
    final d = dossier ?? Directory.systemTemp.path;
    Directory(d).createSync(recursive: true);
    final f = '${Directory(d).absolute.path}/mere-$nom.$prefixe-${DateTime.now().millisecondsSinceEpoch}.json';
    final sortie = <String, Object?>{};
    for (final t in tablesMere) {
      sortie[t] = await select('SELECT * FROM $t');
    }
    File(f).writeAsStringSync(jsonEncode(sortie));
    return f;
  }

  @override
  Future<void> fermer() => conn.close();
}
