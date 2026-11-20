// MESURE (lot MAJ) : temps de « Préparer », de la migration et de l'export sur un jeu GÉNÉRÉ de N dossiers (18 000 par défaut). Jeu synthétique : aucune donnée réelle.
// Usage : dart run tool/mesure_maj.dart [N]
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:sigh_poste/donnees/maj_poste.dart';
import 'package:sigh_poste/donnees/persistance.dart';

Future<void> main(List<String> args) async {
  final n = args.isEmpty ? 18000 : int.parse(args.first);
  final tmp = await Directory.systemTemp.createTemp('mesure-maj-');
  final d = '${tmp.path}/donnees';
  final cle = List<int>.generate(32, (i) => (i * 7 + 3) & 0xff);
  final sw = Stopwatch()..start();
  final p = PersistanceFichiers(d, cle: cle);
  await p.ecrire('patients', [for (var i = 0; i < n; i++) {'id': 'P$i', 'code': 'CNT/$i/26', 'nom': 'Patient $i', 'telephone': i % 4 == 0 ? null : '97${i.toString().padLeft(6, '0')}', 'adresse': 'Natitingou', 'archive': false}]);
  await p.ecrire('factures', [for (var i = 0; i < n * 2; i++) {'id': 'F$i', 'patientId': 'P${i % n}', 'total': 1000 + i, 'remise': null, 'lignes': [{'code': 'A', 'qte': 1}, {'code': 'B', 'qte': 2}]}]);
  await p.ecrire('audit', [for (var i = 0; i < n * 3; i++) {'id': 'A$i', 'action': 'saisie', 'quand': 1760000000000 + i}]);
  print('jeu généré : $n patients, ${n * 2} factures, ${n * 3} lignes de journal (${sw.elapsedMilliseconds} ms)');
  final s = ServiceMiseAJour(dossier: d, cle: cle);
  sw.reset();
  final essai = await s.essaiABlanc();
  print('essai à blanc : ${sw.elapsedMilliseconds} ms ; ${essai.comptes.phrase}');
  sw.reset();
  await s.preparer();
  print('préparer (copie + restauration vérifiée + relecture) : ${sw.elapsedMilliseconds} ms');
  sw.reset();
  final r = await s.migrer(geste: true);
  print('migrer (relecture de la copie, migration, contrôle) : ${sw.elapsedMilliseconds} ms ; ${r.comptes.phrase}');
  sw.reset();
  final f = await s.exporter('${tmp.path}/export.sighexp');
  print('export portable : ${sw.elapsedMilliseconds} ms, ${File(f).lengthSync()} octets');
  final neuf = ServiceMiseAJour(dossier: '${tmp.path}/m2/donnees', cle: cle);
  await neuf.preparer();
  sw.reset();
  final i = await neuf.importer(f, geste: true);
  print('import : ${sw.elapsedMilliseconds} ms ; ${i.comptes.phrase}');
  await tmp.delete(recursive: true);
}
