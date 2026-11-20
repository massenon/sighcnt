// MESURE de la copie consultable à l'échelle d'une grosse clinique (18 000 patients, ~200 000 opérations) : coût d'un tour de copie AVANT (état fusionné de TOUTES
// les opérations à chaque tour) et APRÈS (incrémental), mémoire, taille des enveloppes déposées. Sortie JSON sur la sortie standard.
// Usage : dart run tool/mesure_copie.dart [--patients=18000] [--ops=200000] [--avant=oui]
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_sync/src/commun.dart';
import 'package:sigh_sync/src/pair.dart';
import 'package:sigh_sync/src/pont.dart' show Enveloppes;

int _rss() => ProcessInfo.currentRss ~/ (1024 * 1024);

Future<void> main(List<String> args) async {
  final patients = int.parse(arg(args, 'patients', '18000'));
  final totalOps = int.parse(arg(args, 'ops', '200000'));
  final mesurerAvant = arg(args, 'avant', 'oui') == 'oui';
  final sortie = <String, Object?>{'patients': patients, 'ops': totalOps};
  final cle = '00' * 32;
  final pair = FileulPair(ConfigPair(port: 0, relais: 'http://127.0.0.1:1', dbChemin: ':memory:', cleHex: cle, collectionsCopie: {'patients'}, droits: (_) => true));
  pair.base.poserMeta('uuid', 'F1');
  final noms = ['AKPO', 'KOUA', 'DOSSOU', 'ADJOVI', 'SOGLO', 'HOUNKPATIN', 'TCHANDO', 'BIO'];
  var h = 1000;
  final t0 = Stopwatch()..start();
  pair.base.tx(() {
    for (var i = 0; i < patients; i++) {
      final o = OperationPair(id: 'c$i', appareil: 'F1', hlc: h++, collection: 'patients', fiche: 'p$i', type: 'creer', role: 'x', champs: {'nom': noms[i % 8], 'prenom': 'Prénom$i', 'tel': '9${i.toString().padLeft(7, '0')}', 'quartier': 'Quartier ${i % 40}', 'naissance': '19${60 + i % 40}-01-01'});
      pair.base.exec('INSERT INTO ops(id,appareil,json) VALUES(?,?,?)', [o.id, 'F1', jsonEncode(o.versJson())]);
    }
    for (var j = 0; j < totalOps - patients; j++) {
      final i = (j * 7919) % patients;
      final o = OperationPair(id: 'm$j', appareil: j.isEven ? 'F1' : 'F2', hlc: h++, collection: 'patients', fiche: 'p$i', type: 'modifier', role: 'x', champs: {'tel': '9${(j % 10000000).toString().padLeft(7, '0')}'}, vu: {'tel': 1000 + i});
      pair.base.exec('INSERT INTO ops(id,appareil,json) VALUES(?,?,?)', [o.id, o.appareil, jsonEncode(o.versJson())]);
    }
  });
  sortie['peuplement_ms'] = t0.elapsedMilliseconds;
  sortie['rss_mo_apres_peuplement'] = _rss();

  if (mesurerAvant) {
    // AVANT : à chaque tour, l'état fusionné de TOUTES les opérations (l'ancien preparerCopie)
    final s = Stopwatch()..start();
    final e = pair.etatActuel();
    sortie['avant_tour_ms'] = s.elapsedMilliseconds;
    sortie['avant_fiches'] = e.fiches.length;
    sortie['rss_mo_apres_etat_complet'] = _rss();
  }

  // APRÈS : premier tour (construit l'index et met toutes les fiches en file), puis tours incrémentaux
  var s = Stopwatch()..start();
  var tours = 0, pireTour = 0;
  do {
    final t = Stopwatch()..start();
    pair.preparerCopie();
    tours++;
    if (t.elapsedMilliseconds > pireTour) pireTour = t.elapsedMilliseconds;
  } while (pair.copieEnRetard);
  sortie['apres_premier_passage_total_ms'] = s.elapsedMilliseconds;
  sortie['apres_premier_passage_tours'] = tours;
  sortie['apres_premier_passage_pire_tour_ms'] = pireTour;
  sortie['apres_en_file'] = pair.base.select('SELECT COUNT(*) AS n FROM copie_sortie').first['n'];
  sortie['rss_mo_apres_premier_tour'] = _rss();

  s = Stopwatch()..start();
  pair.preparerCopie();
  sortie['apres_tour_sans_changement_ms'] = s.elapsedMilliseconds;

  // 50 fiches modifiées depuis le dernier tour
  pair.base.tx(() {
    for (var j = 0; j < 50; j++) {
      final o = OperationPair(id: 'n$j', appareil: 'F2', hlc: h++, collection: 'patients', fiche: 'p${j * 13}', type: 'modifier', role: 'x', champs: {'quartier': 'Nouveau $j'}, vu: {});
      pair.base.exec('INSERT INTO ops(id,appareil,json) VALUES(?,?,?)', [o.id, 'F2', jsonEncode(o.versJson())]);
    }
  });
  final avantFile = pair.base.select('SELECT COUNT(*) AS n FROM copie_sortie').first['n'] as int;
  s = Stopwatch()..start();
  pair.preparerCopie();
  sortie['apres_tour_50_fiches_ms'] = s.elapsedMilliseconds;
  sortie['apres_50_fiches_en_file'] = (pair.base.select('SELECT COUNT(*) AS n FROM copie_sortie').first['n'] as int) - avantFile;

  // taille des enveloppes chiffrées au relais (réel : AES-256-GCM + base64), sur un échantillon extrapolé
  final env = Enveloppes([for (var i = 0; i < 32; i++) 0]);
  var octets = 0, n = 0;
  final ech = Stopwatch()..start();
  for (final r in pair.base.select('SELECT n,id,charge FROM copie_sortie ORDER BY n LIMIT 500')) {
    final e = await env.chiffrer((jsonDecode(r['charge'] as String) as Map).cast<String, Object?>(), id: r['id'] as String, appareil: 'F1', dir: 'copie', n: r['n'] as int);
    octets += utf8.encode(jsonEncode(e)).length;
    n++;
  }
  sortie['enveloppe_moyenne_octets'] = (octets / n).round();
  sortie['copie_totale_estimee_mo'] = double.parse((octets / n * patients / (1024 * 1024)).toStringAsFixed(1));
  sortie['chiffrement_500_ms'] = ech.elapsedMilliseconds;
  sortie['rss_mo_final'] = _rss();
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(sortie));
}
