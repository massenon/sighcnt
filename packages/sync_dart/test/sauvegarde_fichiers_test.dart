// La sauvegarde, le contrôle et la restauration des fichiers numérisés d'un poste (lot D5, étape 7) : incrémentale, jamais tournante, vérifiée, destination jamais créée.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_sync/sigh_sync.dart';
import 'package:test/test.dart';

const fixtures = '../../apps/poste/test/fixtures/fichiers';
Uint8List fx(String n) => File('$fixtures/$n').readAsBytesSync();
final cle = List<int>.generate(32, (i) => i * 5 + 1);

void main() {
  late Directory tmp;
  late Directory src, dst;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sigh-sauv-');
    src = Directory('${tmp.path}/donnees/fichiers')..createSync(recursive: true);
    dst = Directory('${tmp.path}/disque-externe')..createSync();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  for (final chiffre in [false, true]) {
    group(chiffre ? 'chiffré' : 'en clair', () {
      List<int>? k() => chiffre ? cle : null;
      StockageFichiers source() => StockageFichiers(src.path, cle: k());

      Future<List<String>> remplir(StockageFichiers s) async => [
            (await s.ranger(fx('courrier-texte.pdf'), famille: 'courrier', zone: 0, deposePar: 'A')).sha256,
            (await s.ranger(fx('scan.png'), famille: 'patient', zone: 2, deposePar: 'B')).sha256,
            (await s.ranger(fx('scan.jpg'), famille: 'courrier', zone: 0)).sha256,
          ];

      test('copie les fichiers vérifiés, avec leur fiche d’accompagnement et un manifeste daté ; la seconde passe ne recopie rien', () async {
        final s = source();
        final shas = await remplir(s);
        final r = await sauvegarderFichiers(s, destination: dst.path, cle: k(), horloge: () => DateTime(2026, 11, 13, 10));
        expect(r.copies, 3);
        expect(r.dejaCopies, 0);
        expect(r.complet, isTrue);
        expect(r.chiffre, chiffre);
        final copie = StockageFichiers('${dst.path}/$dossierSauvegardeFichiers', cle: k());
        for (final sha in shas) {
          expect(await copie.etat(sha), EtatLocalFichier.present);
          expect(sha256Octets(await copie.lire(sha)), sha);
        }
        expect((await copie.meta(shas[1]))!.usages, [
          {'famille': 'patient', 'zone': 2}
        ], reason: 'la zone suit le fichier (RG-13) : sans elle la règle de zone ne s’applique plus après restauration');
        expect(File('${dst.path}/$dossierSauvegardeFichiers/manifestes/fichiers-2026-11-13.json').existsSync(), isTrue);
        final manifeste = jsonDecode(File(r.manifeste!).readAsStringSync()) as Map;
        expect((manifeste['fichiers'] as List).length, 3);
        expect(File(r.manifeste!).readAsStringSync().contains('ADJOVI'), isFalse, reason: 'jamais un nom de patient dans un manifeste');
        // seconde passe : INCRÉMENTALE
        final r2 = await sauvegarderFichiers(s, destination: dst.path, cle: k());
        expect(r2.copies, 0);
        expect(r2.dejaCopies, 3);
        // au repos, la destination n'est pas lisible quand la source est chiffrée
        if (chiffre) {
          final brut = File('${dst.path}/$dossierSauvegardeFichiers/${shas[0].substring(0, 2)}/${shas[0]}.pdf').readAsBytesSync();
          expect(sha256Octets(brut) == shas[0], isFalse);
        }
      });

      test('JAMAIS TOURNANTE : rien ne se supprime à la destination, même quand le fichier a disparu de la source', () async {
        final s = source();
        final shas = await remplir(s);
        await sauvegarderFichiers(s, destination: dst.path, cle: k());
        File('${src.path}/${shas[2].substring(0, 2)}/${shas[2]}.jpg').deleteSync();
        final r = await sauvegarderFichiers(s, destination: dst.path, cle: k());
        expect(r.dejaCopies, 2);
        expect(File('${dst.path}/$dossierSauvegardeFichiers/${shas[2].substring(0, 2)}/${shas[2]}.jpg').existsSync(), isTrue, reason: 'conservation illimitée');
      });

      test('un fichier ALTÉRÉ à la source n’est jamais propagé : nommé, jamais copié ; les autres le sont', () async {
        final s = source();
        final shas = await remplir(s);
        final p = '${src.path}/${shas[0].substring(0, 2)}/${shas[0]}.pdf';
        final b = File(p).readAsBytesSync();
        b[b.length ~/ 2] ^= 0xff;
        File(p).writeAsBytesSync(b);
        final r = await sauvegarderFichiers(s, destination: dst.path, cle: k());
        expect(r.alteres, [shas[0]]);
        expect(r.copies, 2);
        expect(r.complet, isFalse);
        expect(File('${dst.path}/$dossierSauvegardeFichiers/${shas[0].substring(0, 2)}/${shas[0]}.pdf').existsSync(), isFalse);
      });

      test('bornée en temps : au moins un fichier par passe, le reste à la passe suivante, sans curseur', () async {
        final s = source();
        await remplir(s);
        final r1 = await sauvegarderFichiers(s, destination: dst.path, cle: k(), borne: Duration.zero);
        expect(r1.copies, 1);
        expect(r1.restants, 2);
        final r2 = await sauvegarderFichiers(s, destination: dst.path, cle: k(), borne: Duration.zero);
        expect(r2.copies, 1);
        expect(r2.dejaCopies, 1);
        expect(r2.restants, 1);
        final r3 = await sauvegarderFichiers(s, destination: dst.path, cle: k());
        expect(r1.copies + r2.copies + r3.copies, 3);
        expect(r3.dejaCopies, 2);
        expect(r3.restants, 0);
      });

      test('le contrôle relit toute la destination : manquant et copie altérée sont nommés', () async {
        final s = source();
        final shas = await remplir(s);
        await sauvegarderFichiers(s, destination: dst.path, cle: k());
        expect((await controlerSauvegardeFichiers(s, destination: dst.path, cle: k())).sain, isTrue);
        final base = '${dst.path}/$dossierSauvegardeFichiers';
        File('$base/${shas[2].substring(0, 2)}/${shas[2]}.jpg').deleteSync();
        final p = '$base/${shas[0].substring(0, 2)}/${shas[0]}.pdf';
        final b = File(p).readAsBytesSync();
        b[b.length ~/ 3] ^= 0x55;
        File(p).writeAsBytesSync(b);
        final c = await controlerSauvegardeFichiers(s, destination: dst.path, cle: k());
        expect(c.manquants, [shas[2]]);
        expect(c.alteres, [shas[0]]);
        expect(c.intacts, 1);
      });

      test('RESTAURATION : simulation par défaut ; un fichier intact n’est jamais écrasé ; un altéré est mis de côté puis remplacé ; une copie altérée n’est jamais posée', () async {
        final s = source();
        final shas = await remplir(s);
        await sauvegarderFichiers(s, destination: dst.path, cle: k());
        final base = '${dst.path}/$dossierSauvegardeFichiers';
        // poste sinistré : un fichier perdu, un fichier altéré, un intact ; et UNE copie de la sauvegarde altérée
        File('${src.path}/${shas[0].substring(0, 2)}/${shas[0]}.pdf').deleteSync();
        final pa = '${src.path}/${shas[1].substring(0, 2)}/${shas[1]}.png';
        final ba = File(pa).readAsBytesSync();
        ba[ba.length ~/ 2] ^= 0xff;
        File(pa).writeAsBytesSync(ba);
        final intact = File('${src.path}/${shas[2].substring(0, 2)}/${shas[2]}.jpg');
        final avant = intact.readAsBytesSync();
        final sim = await restaurerFichiers(s, source: dst.path, cle: k());
        expect(sim.simulation, isTrue);
        expect(sim.aRestaurer, 2);
        expect(sim.restaures, 0);
        expect(File('${src.path}/${shas[0].substring(0, 2)}/${shas[0]}.pdf').existsSync(), isFalse, reason: 'la simulation ne pose rien');
        // une copie de la sauvegarde altérée : jamais posée
        final pc = '$base/${shas[1].substring(0, 2)}/${shas[1]}.png';
        final bc = File(pc).readAsBytesSync();
        final bcOriginal = Uint8List.fromList(bc);
        bc[bc.length ~/ 2] ^= 0x33;
        File(pc).writeAsBytesSync(bc);
        final r = await restaurerFichiers(s, source: dst.path, cle: k(), simulation: false);
        expect(r.restaures, 1);
        expect(r.copiesAlterees, [shas[1]]);
        expect(r.sain, isFalse);
        expect(await s.etat(shas[0]), EtatLocalFichier.present);
        expect(await s.etat(shas[1]), EtatLocalFichier.altere, reason: 'la copie altérée n’a pas remplacé le fichier du poste');
        expect(intact.readAsBytesSync(), avant, reason: 'un fichier intact n’est jamais écrasé');
        // la copie de la sauvegarde réparée : la restauration remplace l'altéré, met de côté l'ancien
        File(pc).writeAsBytesSync(bcOriginal);
        final r2 = await restaurerFichiers(s, source: dst.path, cle: k(), simulation: false);
        expect(r2.restaures, 1);
        expect(r2.misDeCote, 1);
        expect(await s.etat(shas[1]), EtatLocalFichier.present);
        expect(Directory('${src.path}/_alteres').listSync().length, 1);
        expect((await s.meta(shas[1]))!.usages, [
          {'famille': 'patient', 'zone': 2}
        ]);
      });

      test('une sauvegarde introuvable est un refus nommé', () async {
        try {
          await restaurerFichiers(source(), source: dst.path, cle: k());
          fail('refus attendu');
        } on ErreurFichier catch (e) {
          expect(e.refus.code, 'SAUVEGARDE_INTROUVABLE');
        }
      });
    });
  }

  group('la destination', () {
    Future<String?> code(String d) async => (await verifierDestinationSauvegarde(d, src.path))?.code;

    test('refus nommés : absente, relative, inexistante, pas un dossier, recouvrant les fichiers ; jamais créée', () async {
      expect(await code(''), 'DESTINATION_ABSENTE');
      expect(await code('sauvegardes'), 'DESTINATION_RELATIVE');
      final absent = '${tmp.path}/disque-debranche';
      expect(await code(absent), 'DESTINATION_INEXISTANTE');
      expect(Directory(absent).existsSync(), isFalse, reason: 'le poste ne crée JAMAIS la destination');
      File('${tmp.path}/fichier.txt').writeAsStringSync('x');
      expect(await code('${tmp.path}/fichier.txt'), 'DESTINATION_PAS_UN_DOSSIER');
      expect(await code(src.path), 'DESTINATION_RECOUVRE_LES_FICHIERS');
      expect(await code('${src.path}/sous'), 'DESTINATION_INEXISTANTE');
      Directory('${src.path}/sous').createSync();
      expect(await code('${src.path}/sous'), 'DESTINATION_RECOUVRE_LES_FICHIERS');
      expect(await code('${tmp.path}/donnees'), 'DESTINATION_RECOUVRE_LES_FICHIERS', reason: 'la destination qui CONTIENT les fichiers les recouvre aussi');
      expect(await code(dst.path), isNull);
    });

    test('une destination non inscriptible est refusée par une écriture réelle (pas par une lecture des droits)', () async {
      if (Platform.isWindows || Process.runSync('id', ['-u']).stdout.toString().trim() == '0') {
        // Sous root (ce banc), aucune écriture n'est refusée : le cas n'est pas éprouvable ici et le dit.
        markTestSkipped('écriture interdite non éprouvable sous root ou Windows');
        return;
      }
      Process.runSync('chmod', ['555', dst.path]);
      addTearDown(() => Process.runSync('chmod', ['755', dst.path]));
      expect(await code(dst.path), 'DESTINATION_NON_INSCRIPTIBLE');
    });

    test('une destination qui disparaît entre deux passes donne un refus nommé, jamais une copie sur le disque des données', () async {
      final s = StockageFichiers(src.path);
      await s.ranger(fx('scan.png'), famille: 'courrier', zone: 0);
      await sauvegarderFichiers(s, destination: dst.path);
      dst.deleteSync(recursive: true);
      try {
        await sauvegarderFichiers(s, destination: dst.path);
        fail('refus attendu');
      } on ErreurFichier catch (e) {
        expect(e.refus.code, 'DESTINATION_INEXISTANTE');
      }
      expect(Directory(dst.path).existsSync(), isFalse);
    });
  });
}
