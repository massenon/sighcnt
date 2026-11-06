// MESURE du tour de copie de la MÈRE (SQLite en mémoire) à l'échelle d'une grosse clinique. Usage : dart run tool/mesure_copie_mere.dart [--patients=18000] [--ops=200000]
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_sync/src/commun.dart';
import 'package:sigh_sync/src/copie_mere.dart';
import 'package:sigh_sync/src/mere.dart';

Future<void> main(List<String> args) async {
  final patients = int.parse(arg(args, 'patients', '18000'));
  final totalOps = int.parse(arg(args, 'ops', '200000'));
  final m = await Mere.creer(ConfigMere(port: 0, dbChemin: ':memory:'));
  final copie = CopieMere(m);
  await copie.tourPreparer();
  final s0 = Stopwatch()..start();
  await m.base.tx(() async {
    for (var i = 0; i < totalOps; i++) {
      final creation = i < patients;
      final o = OperationPair(id: 'o$i', appareil: i.isEven ? 'F1' : 'F2', hlc: 1000 + i, collection: 'patients', fiche: 'p${i % patients}', type: creation ? 'creer' : 'modifier', role: 'reception', champs: creation ? {'nom': 'N$i', 'tel': '0'} : {'tel': '$i'}, vu: creation ? null : {'tel': 1000 + (i % patients)});
      await m.base.exec('INSERT INTO pair_ops(id,json) VALUES(?,?)', [o.id, jsonEncode(o.versJson())]);
    }
  });
  final sortie = <String, Object?>{'patients': patients, 'ops': totalOps, 'peuplement_ms': s0.elapsedMilliseconds};
  var s = Stopwatch()..start();
  var tours = 0, pire = 0;
  do {
    final t = Stopwatch()..start();
    await copie.preparer();
    tours++;
    if (t.elapsedMilliseconds > pire) pire = t.elapsedMilliseconds;
  } while (await copie.enRetard());
  sortie['premier_passage_total_ms'] = s.elapsedMilliseconds;
  sortie['premier_passage_tours'] = tours;
  sortie['premier_passage_pire_tour_ms'] = pire;
  sortie['enveloppes'] = (await m.base.select('SELECT COUNT(*) AS n FROM copie_mere_sortie')).first['n'];
  s = Stopwatch()..start();
  await copie.preparer();
  sortie['tour_sans_changement_ms'] = s.elapsedMilliseconds;
  sortie['rss_mo'] = ProcessInfo.currentRss ~/ (1024 * 1024);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(sortie));
  exit(0);
}
