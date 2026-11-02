import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/persistance.dart';

Magasin neuf() => Magasin({
      'patients': [
        {'id': 'P1', 'nom': 'AGBO'}
      ],
      'utilisateurs': [
        {'id': 'U1', 'identifiant': 'admin.systeme'}
      ],
    });

void main() {
  test('un geste est écrit sur le disque, et un nouveau démarrage le retrouve', () async {
    final p = PersistanceMemoire();
    final a = neuf();
    await a.brancherPersistance(p, delai: Duration.zero);
    a.collection('patients').inserer({'id': 'P2', 'nom': 'BIO'});
    await a.ecrireMaintenant();
    final b = neuf();
    await b.brancherPersistance(p);
    final noms = b.collection('patients').toutes.map((f) => f['nom']).toList();
    expect(noms, containsAll(['AGBO', 'BIO']));
    expect(b.collection('patients').toutes.length, 2, reason: 'le contenu écrit REMPLACE le jeu, il ne s’y ajoute pas');
  });

  test('seules les collections modifiées sont réécrites', () async {
    final p = PersistanceMemoire();
    final a = neuf();
    await a.brancherPersistance(p, delai: Duration.zero);
    a.collection('utilisateurs'); // simple lecture
    a.collection('patients').mettreAJour('P1', {'nom': 'AGBO-2'});
    await a.ecrireMaintenant();
    expect(p.ecritures.toSet().contains('patients'), isTrue);
    expect(p.ecritures.contains('utilisateurs'), isFalse);
    p.ecritures.clear();
    await a.ecrireMaintenant();
    expect(p.ecritures, isEmpty, reason: 'rien n’a changé depuis');
  });

  test('le journal d’audit est écrit lui aussi (RG-12), et l’archivage survit (RG-14)', () async {
    final p = PersistanceMemoire();
    final a = neuf();
    await a.brancherPersistance(p, delai: Duration.zero);
    a.collection('patients').archiver('P1');
    await a.ecrireMaintenant();
    expect(p.contenu['audit'], isNotEmpty);
    final b = neuf();
    await b.brancherPersistance(p);
    expect(b.collection('patients').archivees.single['id'], 'P1');
    expect(b.collection('patients').actives, isEmpty);
  });

  test('la persistance se branche une fois, avant toute lecture', () async {
    final m = neuf();
    m.collection('patients');
    expect(() => m.brancherPersistance(PersistanceMemoire()), throwsStateError);
    final n = neuf();
    await n.brancherPersistance(PersistanceMemoire());
    expect(() => n.brancherPersistance(PersistanceMemoire()), throwsStateError);
  });

  test('une écriture qui échoue est reprogrammée et DITE, puis l’alerte retombe', () async {
    final p = _Capricieuse();
    final a = neuf();
    await a.brancherPersistance(p, delai: const Duration(hours: 1));
    a.collection('patients').mettreAJour('P1', {'nom': 'X'});
    await a.ecrireMaintenant();
    expect(a.erreurPersistance.value, contains('patients'));
    p.refuse = false;
    await a.ecrireMaintenant();
    expect(a.erreurPersistance.value, isNull);
    expect(p.contenu['patients']!.single['nom'], 'X', reason: 'la donnée n’a pas été perdue');
  });

  group('fichiers sur disque', () {
    late Directory d;
    setUp(() async => d = await Directory.systemTemp.createTemp('mag'));
    tearDown(() => d.delete(recursive: true));

    test('écriture atomique : le fichier existe, aucun temporaire ne reste', () async {
      final p = PersistanceFichiers('${d.path}/magasin');
      final a = neuf();
      await a.brancherPersistance(p, delai: Duration.zero);
      a.collection('patients').inserer({'id': 'P9', 'nom': 'ÉLÈVE'});
      await a.ecrireMaintenant();
      final noms = Directory('${d.path}/magasin').listSync().map((e) => e.uri.pathSegments.last).toList();
      expect(noms, contains('patients.json'));
      expect(noms.any((n) => n.endsWith('.tmp')), isFalse);
      final b = neuf();
      await b.brancherPersistance(PersistanceFichiers('${d.path}/magasin'));
      expect(b.collection('patients').toutes.map((f) => f['nom']), contains('ÉLÈVE'), reason: 'l’UTF-8 survit');
    });

    test('un fichier illisible est mis de côté et NOMMÉ ; la collection retombe sur le jeu', () async {
      Directory('${d.path}/magasin').createSync();
      File('${d.path}/magasin/patients.json').writeAsStringSync('{pas du json');
      final p = PersistanceFichiers('${d.path}/magasin');
      final m = neuf();
      await m.brancherPersistance(p);
      expect(m.problemesPersistance.single, contains('patients'));
      expect(m.collection('patients').toutes.single['id'], 'P1');
      final noms = Directory('${d.path}/magasin').listSync().map((e) => e.uri.pathSegments.last);
      expect(noms.any((n) => n.startsWith('patients.json.corrompu-')), isTrue, reason: 'rien n’est effacé');
    });

    test('un nom de collection hostile est refusé', () async {
      final p = PersistanceFichiers('${d.path}/magasin');
      expect(() => p.ecrire('../evil', []), throwsArgumentError);
    });

    test('mettreDeCote renomme le dossier sans rien supprimer', () async {
      final p = PersistanceFichiers('${d.path}/magasin');
      await p.ecrire('patients', [
        {'id': 'P1'}
      ]);
      await p.mettreDeCote();
      expect(Directory('${d.path}/magasin').existsSync(), isFalse);
      expect(d.listSync().any((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last.startsWith('magasin.ancien-')), isTrue);
      expect(jsonDecode(File('${d.listSync().whereType<Directory>().first.path}/patients.json').readAsStringSync()), isNotEmpty);
    });
  });
}

class _Capricieuse extends PersistanceMemoire {
  bool refuse = true;
  @override
  Future<void> ecrire(String collection, List<FichePersistee> fiches) async {
    if (refuse) throw const FileSystemException('disque plein');
    await super.ecrire(collection, fiches);
  }
}
