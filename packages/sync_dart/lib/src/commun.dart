/// Outils communs au moteur de synchronisation : arguments, JSON, hachage, identifiants, base locale.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as c;
import 'package:sqlite3/sqlite3.dart';

/// `--nom=valeur` → valeur (ou le défaut).
String arg(List<String> args, String nom, String defaut) {
  for (final a in args) {
    if (a.startsWith('--$nom=')) return a.substring(nom.length + 3);
  }
  return defaut;
}

String sha256hex(String s) => c.sha256.convert(utf8.encode(s)).toString();

final Random _alea = Random.secure();
String hexAlea(int octets) => List.generate(octets, (_) => _alea.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

/// UUID v7 : horodatage en millisecondes (48 bits) puis hasard — l'ordre alphabétique suit l'ordre de création.
String uuid7() {
  final b = List<int>.generate(16, (_) => _alea.nextInt(256));
  final t = DateTime.now().millisecondsSinceEpoch;
  for (var i = 0; i < 6; i++) {
    b[i] = (t >> (8 * (5 - i))) & 0xff;
  }
  b[6] = (b[6] & 0x0f) | 0x70;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

int maintenantMs() => DateTime.now().millisecondsSinceEpoch;

/// Normalise pour comparer comme JavaScript : un double entier vaut l'entier (`1.0` s'écrit `1`).
Object? norm(Object? v) {
  if (v is double && v.isFinite && v == v.truncateToDouble() && v.abs() < 9e15) return v.toInt();
  if (v is Map) return v.map((k, x) => MapEntry(k, norm(x)));
  if (v is List) return v.map(norm).toList();
  return v;
}

/// `JSON.stringify` à la JavaScript.
String enJson(Object? v) => jsonEncode(norm(v));

/// `+x` : conversion numérique JavaScript (« » et null donnent 0, le reste non numérique NaN → 0 ici).
num nb(Object? v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v.trim()) ?? 0;
  return 0;
}

/// Erreur nommée du protocole : statut HTTP + corps `{code, motif, …}`.
class Err implements Exception {
  Err(this.statut, this.code, [this.motif = '', Map<String, Object?>? extra])
      : corps = {'code': code, 'motif': motif, ...?extra};
  final int statut;
  final String code;
  final String motif;
  final Map<String, Object?> corps;
  @override
  String toString() => 'Err($statut, $code, $motif)';
}

/// Base locale SQLite : méta-données, transactions (la plus extérieure décide).
class Base {
  Base(String chemin) : db = chemin == ':memory:' ? sqlite3.openInMemory() : sqlite3.open(chemin) {
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA busy_timeout = 5000');
    db.execute('CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT)');
  }

  final Database db;
  int _profondeur = 0;

  String? meta(String k, [String? defaut]) {
    final r = db.select('SELECT v FROM meta WHERE k=?', [k]);
    return r.isEmpty ? defaut : r.first['v'] as String?;
  }

  int metaInt(String k, [int defaut = 0]) => int.tryParse(meta(k) ?? '') ?? defaut;

  void poserMeta(String k, Object? v) =>
      db.execute('INSERT INTO meta(k,v) VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v', [k, '$v']);

  T tx<T>(T Function() f) {
    if (_profondeur > 0) return f();
    _profondeur++;
    db.execute('BEGIN IMMEDIATE');
    try {
      final r = f();
      db.execute('COMMIT');
      return r;
    } catch (e) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      _profondeur--;
    }
  }

  ResultSet select(String sql, [List<Object?> p = const []]) => db.select(sql, p);
  void exec(String sql, [List<Object?> p = const []]) => db.execute(sql, p);
  int get dernierId => db.lastInsertRowId;
}

/// Lit un corps JSON de requête HTTP (vide → `{}`).
Future<Map<String, Object?>> corpsJson(HttpRequest req) async {
  final texte = await utf8.decoder.bind(req).join();
  if (texte.trim().isEmpty) return {};
  try {
    final j = jsonDecode(texte);
    return j is Map ? j.cast<String, Object?>() : {};
  } catch (_) {
    return {};
  }
}

Future<void> repondre(HttpRequest req, int statut, Object? corps) async {
  final octets = utf8.encode(enJson(corps));
  req.response
    ..statusCode = statut
    ..headers.contentType = ContentType.json
    ..headers.contentLength = octets.length
    ..add(octets);
  await req.response.close();
}

/// Annonce au processus parent (le banc) que le serveur écoute : une ligne `PRET <port>` sur la sortie standard.
void annoncerPret(int port) {
  stdout.writeln('PRET $port');
}
