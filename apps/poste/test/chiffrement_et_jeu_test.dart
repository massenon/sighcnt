import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/persistance.dart';

/// Direction du 03/11/2026 : le magasin du poste est CHIFFRÉ au repos, et un jeu d'origine qui change ne se perd pas.
Magasin neuf(List<Map<String, Object?>> actes) => Magasin({
      'actes': actes,
      'patients': [
        {'id': 'P1', 'nom': 'AGBO'}
      ],
    });

final cle = List<int>.generate(32, (i) => i + 1);

void main() {
  late Directory d;
  setUp(() async => d = await Directory.systemTemp.createTemp('chif'));
  tearDown(() => d.delete(recursive: true));

  group('chiffrement au repos', () {
    test('les fichiers sont illisibles sans la clé et ne contiennent aucune donnée en clair', () async {
      final p = PersistanceFichiers('${d.path}/m', cle: cle);
      final m = neuf([]);
      await m.brancherPersistance(p, delai: Duration.zero);
      m.collection('patients').inserer({'id': 'P2', 'nom': 'ADJOVI Koffi', 'telephone': '97000000'});
      await m.ecrireMaintenant();
      final fichiers = Directory('${d.path}/m').listSync().whereType<File>().toList();
      expect(fichiers.any((f) => f.path.endsWith('patients.sigh')), isTrue);
      expect(fichiers.any((f) => f.path.endsWith('.json')), isFalse, reason: 'aucun clair');
      for (final f in fichiers) {
        final brut = latin1.decode(f.readAsBytesSync());
        expect(brut, isNot(contains('ADJOVI')), reason: f.path);
        expect(brut, isNot(contains('97000000')));
      }
      final relu = neuf([]);
      await relu.brancherPersistance(PersistanceFichiers('${d.path}/m', cle: cle));
      expect(relu.collection('patients').toutes.map((f) => f['nom']), contains('ADJOVI Koffi'));
    });

    test('une mauvaise clé, un fichier altéré ou renommé : mis de côté et NOMMÉS, jamais lus', () async {
      final p = PersistanceFichiers('${d.path}/m', cle: cle);
      await p.ecrire('patients', [
        {'id': 'P1', 'nom': 'AGBO'}
      ]);
      final mauvaise = PersistanceFichiers('${d.path}/m', cle: List<int>.filled(32, 9));
      expect(await mauvaise.lireTout(), isEmpty);
      expect(mauvaise.problemes.single, contains('patients'));
      expect(Directory('${d.path}/m').listSync().any((e) => e.path.contains('.corrompu-')), isTrue);

      final q = PersistanceFichiers('${d.path}/n', cle: cle);
      await q.ecrire('patients', [
        {'id': 'P1'}
      ]);
      File('${d.path}/n/patients.sigh').copySync('${d.path}/n/factures.sigh');
      final r = PersistanceFichiers('${d.path}/n', cle: cle);
      final lu = await r.lireTout();
      expect(lu.keys, ['patients'], reason: 'un fichier recopié sous un autre nom ne se déchiffre pas (le nom est lié au chiffré)');
      expect(r.problemes.single, contains('factures'));

      final altere = File('${d.path}/n/patients.sigh')..writeAsBytesSync([...File('${d.path}/n/patients.sigh').readAsBytesSync()]..[30] ^= 0xff);
      expect(altere.existsSync(), isTrue);
      final s = PersistanceFichiers('${d.path}/n', cle: cle);
      expect(await s.lireTout(), isEmpty);
    });

    test('migration : les fichiers en clair d’un poste d’avant sont réécrits chiffrés et le clair est SUPPRIMÉ', () async {
      Directory('${d.path}/m').createSync();
      File('${d.path}/m/patients.json').writeAsStringSync(jsonEncode([
        {'id': 'P1', 'nom': 'AGBO'}
      ]));
      final p = PersistanceFichiers('${d.path}/m', cle: cle);
      final lu = await p.lireTout();
      expect(lu['patients']!.single['nom'], 'AGBO');
      expect(File('${d.path}/m/patients.json').existsSync(), isFalse, reason: 'le clair ne reste pas');
      expect(File('${d.path}/m/patients.sigh').existsSync(), isTrue);
    });

    test('la clé locale : créée au premier usage, relue à l’identique, 256 bits', () async {
      final k = CleLocale('${d.path}/cle.bin');
      final a = await k.obtenir();
      expect(a.length, 32);
      expect(await k.obtenir(), a);
    }, skip: Platform.isWindows ? 'DPAPI : essayé sur Windows seulement' : false);
  });

  group('SAUVEGARDE DE LA CLÉ', () {
    test('la clé exportée sous phrase de passe se relit à l’identique ; mauvaise phrase, fichier altéré ou étranger : refus nommé, rien d’écrasé', () async {
      final k = CleLocale('${d.path}/cle.bin');
      final cle = await k.obtenir();
      final fichier = await k.exporter('${d.path}/coffre/cle.cle', 'phrase de passe longue');
      expect(File(fichier).readAsBytesSync().length, 4 + 16 + 12 + 32 + 16);
      expect(latin1.decode(File(fichier).readAsBytesSync()), isNot(contains(base64.encode(cle))));
      // Le poste est remplacé : le fichier de clé a disparu.
      File('${d.path}/cle.bin').deleteSync();
      final neuf = CleLocale('${d.path}/cle.bin');
      expect(await neuf.importer(fichier, 'phrase de passe longue'), cle);
      expect(await neuf.obtenir(), cle, reason: 'la clé est remise en service');
      // Les données chiffrées par l'ancienne clé se rouvrent avec la clé restaurée.
      final p = PersistanceFichiers('${d.path}/m', cle: cle);
      await p.ecrire('patients', [
        {'id': 'P1', 'nom': 'AGBO'}
      ]);
      expect((await PersistanceFichiers('${d.path}/m', cle: await neuf.obtenir()).lireTout())['patients']!.single['nom'], 'AGBO');
      await expectLater(neuf.importer(fichier, 'autre phrase de passe'), throwsA(isA<StateError>().having((e) => '$e', 'message', contains('incorrecte'))));
      final altere = File('${d.path}/altere.cle')..writeAsBytesSync([...File(fichier).readAsBytesSync()]..[40] ^= 1);
      await expectLater(neuf.importer(altere.path, 'phrase de passe longue'), throwsA(isA<StateError>()));
      File('${d.path}/etranger.cle').writeAsStringSync('rien à voir');
      await expectLater(neuf.importer('${d.path}/etranger.cle', 'phrase de passe longue'), throwsA(isA<StateError>()));
      await expectLater(k.exporter('${d.path}/x.cle', 'courte'), throwsA(isA<StateError>().having((e) => '$e', 'message', contains('12 caractères'))));
    });
  });

  group('un jeu d’origine qui change ne se perd pas', () {
    test('les fiches de référentiel nouvelles sont ajoutées, rien n’est écrasé ni retiré, l’activité de démonstration ne revient pas', () async {
      final p = PersistanceMemoire();
      final v1 = neuf([
        {'id': 'A1', 'libelle': 'Consultation', 'prix': 3000},
      ]);
      await v1.brancherPersistance(p, delai: Duration.zero, fusionnables: {'actes'});
      // L'agent modifie un tarif et vide les patients de démonstration.
      v1.collection('actes').mettreAJour('A1', {'prix': 3500});
      v1.collection('patients').remplacerContenu(const []);
      await v1.ecrireMaintenant();

      // Nouvelle version du poste : un acte de plus au jeu, un patient de démonstration de plus.
      final v2 = Magasin({
        'actes': [
          {'id': 'A1', 'libelle': 'Consultation', 'prix': 3000},
          {'id': 'A2', 'libelle': 'Pansement', 'prix': 9000},
        ],
        'patients': [
          {'id': 'P1', 'nom': 'AGBO'},
          {'id': 'P9', 'nom': 'NOUVEAU DEMO'},
        ],
      });
      await v2.brancherPersistance(p, fusionnables: {'actes'});
      expect(v2.jeuxFusionnes, {'actes': 1});
      expect(v2.collection('actes').parId('A1')!['prix'], 3500, reason: 'la modification de l’agent est conservée');
      expect(v2.collection('actes').parId('A2')!['libelle'], 'Pansement', reason: 'l’apport de la nouvelle version arrive');
      expect(v2.collection('patients').toutes, isEmpty, reason: 'l’activité de démonstration n’est jamais rajoutée');
      // Au lancement suivant, rien à fusionner : le jeu est connu.
      final v3 = Magasin({
        'actes': [
          {'id': 'A1'},
          {'id': 'A2'},
        ],
      });
      await v3.brancherPersistance(p, fusionnables: {'actes'});
      expect(v3.jeuxFusionnes, isEmpty);
    });

    test('un poste neuf (rien d’enregistré) prend le jeu tel quel et mémorise son empreinte', () async {
      final p = PersistanceMemoire();
      final m = neuf([
        {'id': 'A1'}
      ]);
      await m.brancherPersistance(p, fusionnables: {'actes'});
      expect(m.jeuxFusionnes, isEmpty);
      expect(p.meta['jeu'], isNotNull);
    });
  });
}
