// Aides des tests de la sauvegarde hors site (lot 5) : un relais de référence (Node) lancé en processus, des octets reproductibles, des éléments à sauver.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_sync/sigh_sync.dart';
import 'package:test/test.dart';

final String banc = '${Directory.current.path}/../sync/banc';
const String secret = 'secret-mere';

Uint8List alea(String graine, int n) {
  final out = BytesBuilder();
  for (var i = 0; out.length < n; i++) {
    out.add(utf8.encode(sha256Octets(utf8.encode('$graine:$i'))));
  }
  return Uint8List.fromList(out.takeBytes().sublist(0, n));
}

List<int> cleDeTest() => List<int>.generate(32, (i) => (i * 11 + 5) & 0xff);

ElementASauver el(String ref, Uint8List octets, {Map<String, Object?>? meta, bool sha = false, void Function()? surLecture}) => ElementASauver(
    ref: ref,
    taille: octets.length,
    meta: meta,
    shaClair: sha ? sha256Octets(octets) : null,
    lire: () async {
      surLecture?.call();
      return octets;
    });

/// Un relais de référence (Node) sur un port libre, une base et un dossier de blocs NEUFS.
class Relais {
  Relais(this.dir, this.proc, this.port);
  final Directory dir;
  final Process proc;
  final int port;
  String get base => 'http://127.0.0.1:$port';
  DestinationRelais get dest => DestinationRelais(base, secret);
  Future<void> regler(String cle, int valeur) async {
    final c = HttpClient();
    final r = await c.postUrl(Uri.parse('$base/banc/sauvegarde/reglage'));
    r.headers.contentType = ContentType.json;
    r.headers.set('x-mere', secret);
    r.add(utf8.encode(jsonEncode({'cle': cle, 'valeur': valeur})));
    await (await r.close()).drain<void>();
    c.close();
  }

  Future<void> alterer(String id) async {
    final c = HttpClient();
    final r = await c.postUrl(Uri.parse('$base/banc/sauvegarde/alterer'));
    r.headers.contentType = ContentType.json;
    r.headers.set('x-mere', secret);
    r.add(utf8.encode(jsonEncode({'id': id})));
    await (await r.close()).drain<void>();
    c.close();
  }

  Future<void> arreter() async {
    proc.kill(ProcessSignal.sigkill);
    await proc.exitCode;
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

Future<Relais> lancerRelais() async {
  final dir = Directory.systemTemp.createTempSync('sigh-sauv-dart-');
  final sock = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = sock.port;
  await sock.close();
  final proc = await Process.start('node', ['--no-warnings', '$banc/relais.js', '--port=$port', '--db=${dir.path}/relais.sqlite', '--banc=1', '--sauvegardes=${dir.path}/blocs-relais']);
  proc.stdout.drain<void>();
  proc.stderr.drain<void>();
  final r = Relais(dir, proc, port);
  for (var i = 0; i < 100; i++) {
    try {
      await r.dest.etat();
      return r;
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  await r.arreter();
  throw StateError('le relais de référence ne démarre pas');
}

Future<ErreurSauvegarde> refusDe(Future<Object?> f) async {
  try {
    await f;
  } on ErreurSauvegarde catch (e) {
    return e;
  }
  fail('un refus nommé était attendu');
}

Future<Map<String, Object?>> nodeJson(String script, Map<String, Object?> arg) async {
  final r = await Process.run('node', ['--no-warnings', '$banc/$script', jsonEncode(arg)]);
  final ligne = (r.stdout as String).trim().split('\n').last;
  return (jsonDecode(ligne) as Map).cast<String, Object?>();
}

