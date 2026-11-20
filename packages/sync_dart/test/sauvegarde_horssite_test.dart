// LA SAUVEGARDE HORS SITE du moteur Dart (lot 5, ADR-0007) : le chiffrement au bit près des vecteurs du banc, le client contre le VRAI relais de référence (Node, `relais.js`, lancé en
// processus), l'interopérabilité DANS LES DEUX SENS (copie faite par le banc, restaurée par Dart, et l'inverse), la destination « dossier distant monté », la rotation, le contrôle nocturne,
// l'index d'une copie incrémentale.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_sync/sigh_sync.dart';
import 'package:test/test.dart';

import 'aide_sauvegarde.dart';

void main() {
  group('chiffrement : les vecteurs du banc, au bit près', () {
    final f = (jsonDecode(File('test/vecteurs/sauvegarde_chiffrement.json').readAsStringSync()) as Map).cast<String, Object?>();
    final cle = [for (var i = 0; i < 64; i += 2) int.parse((f['cleHex'] as String).substring(i, i + 2), radix: 16)];
    final ch = ChiffreurSauvegarde(cle);
    Uint8List clairDe(Map<String, Object?> c) {
      if (c['clairHex'] != null) {
        final h = c['clairHex'] as String;
        return Uint8List.fromList([for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);
      }
      final r = (c['clairRepete'] as Map).cast<String, Object?>();
      return Uint8List.fromList(List<int>.filled(r['longueur'] as int, r['octet'] as int));
    }

    for (final c in (f['cas'] as List).cast<Map>()) {
      test('${c['genre']} ${c['type']} (${c['longueur']} octets chiffrés)', () async {
        final clair = clairDe(c.cast<String, Object?>());
        expect(sha256Octets(clair), c['clairSha256']);
        final b = await ch.sceller('${c['genre']}', '${c['type']}', clair);
        final attendu = c['blobHex'] as String;
        expect([for (final x in b.octets) x.toRadixString(16).padLeft(2, '0')].join(), attendu, reason: 'le bloc Dart est celui du banc');
        expect(b.id, c['id']);
        final ouvert = await ch.ouvrir('${c['genre']}', '${c['type']}', b.octets, b.id);
        expect(ouvert, clair);
      });
    }

    test('un autre genre, un autre type ou une autre clé n\'ouvrent pas le bloc : CLE_INCORRECTE nommée avec le bloc', () async {
      final c = (f['cas'] as List).first as Map;
      final blob = Uint8List.fromList([for (var i = 0; i < (c['blobHex'] as String).length; i += 2) int.parse((c['blobHex'] as String).substring(i, i + 2), radix: 16)]);
      expect((await refusDe(ch.ouvrir('manifeste', 'magasin', blob, 'x'))).code, 'CLE_INCORRECTE');
      expect((await refusDe(ch.ouvrir('bloc', 'fichiers', blob, 'x'))).code, 'CLE_INCORRECTE');
      expect((await refusDe(ChiffreurSauvegarde(List.filled(32, 7)).ouvrir('bloc', 'magasin', blob, 'x'))).code, 'CLE_INCORRECTE');
      final alt = Uint8List.fromList(blob)..[20] ^= 1;
      expect((await refusDe(ch.ouvrir('bloc', 'magasin', alt, 'idalt'))).refus.plus['bloc'], 'idalt');
    });
  });

  group('contre le VRAI relais de référence', () {
    late Relais relais;
    late Directory tmp;
    setUp(() async {
      relais = await lancerRelais();
      tmp = Directory.systemTemp.createTempSync('sigh-sauv-dart-src-');
    });
    tearDown(() async {
      await relais.arreter();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('dépôt, rejeu idempotent, dédoublonnage, restauration octet par octet vers une cible neuve', () async {
      final cle = cleDeTest();
      final base = alea('base', 3 * 1024 * 1024 + 777);
      final r1 = await sauvegarderHorsSite(dest: relais.dest, cle: cle, type: 'magasin', elements: [el('magasin', base)], tailleBloc: 512 * 1024, garder: 7);
      expect(r1.rejeu, isFalse);
      expect(r1.deposes, greaterThanOrEqualTo(7));
      final r2 = await sauvegarderHorsSite(dest: relais.dest, cle: cle, type: 'magasin', elements: [el('magasin', base)], tailleBloc: 512 * 1024, garder: 7);
      expect(r2.rejeu, isTrue, reason: 'le même état est la même copie');
      expect(r2.deposes, 0);
      expect(r2.copie, r1.copie);
      expect((await relais.dest.copies('magasin')).length, 1);
      final modifie = Uint8List.fromList(base)..[base.length - 3] ^= 0xff;
      final r3 = await sauvegarderHorsSite(dest: relais.dest, cle: cle, type: 'magasin', elements: [el('magasin', modifie)], tailleBloc: 512 * 1024, garder: 7);
      expect(r3.deposes, lessThanOrEqualTo(2), reason: 'seuls le bloc touché et le manifeste');
      expect(r3.dejaLa, greaterThanOrEqualTo(5));
      final cible = '${tmp.path}/restaure';
      final res = await restaurerHorsSite(dest: relais.dest, cle: cle, copieId: r1.copie, cible: cible);
      expect(res.elements, 1);
      expect(sha256Octets(File('$cible/magasin').readAsBytesSync()), sha256Octets(base));
      expect(File('$cible/magasin').lengthSync(), base.length);
    });

    test('la clé ne part dans AUCUNE requête (blocs et manifeste ne contiennent ni elle, ni son hexadécimal)', () async {
      final cle = cleDeTest();
      final capture = _Ecoute(relais.dest);
      await sauvegarderHorsSite(dest: capture, cle: cle, type: 'magasin', elements: [el('magasin', alea('x', 600 * 1024))], tailleBloc: 128 * 1024, garder: 7);
      final tout = capture.vu.toBytes();
      bool contient(List<int> aiguille) {
        for (var i = 0; i + aiguille.length <= tout.length; i++) {
          var ok = true;
          for (var j = 0; j < aiguille.length && ok; j++) {
            ok = tout[i + j] == aiguille[j];
          }
          if (ok) return true;
        }
        return false;
      }

      expect(contient(cle), isFalse);
      expect(contient(utf8.encode(cle.map((x) => x.toRadixString(16).padLeft(2, '0')).join())), isFalse);
      expect(contient(utf8.encode(base64.encode(cle))), isFalse);
      expect(tout.length, greaterThan(600 * 1024));
    });

    test('dépôt COUPÉ au milieu (refus nommé) puis repris : seuls les blocs manquants sont envoyés, aucune copie incomplète n\'est comptée', () async {
      final cle = cleDeTest();
      final base = alea('coupure', 2 * 1024 * 1024);
      final e = await refusDe(sauvegarderHorsSite(dest: relais.dest, cle: cle, type: 'magasin', elements: [el('magasin', base)], tailleBloc: 128 * 1024, garder: 7, coupureApres: 5));
      expect(e.code, 'DEPOT_COUPE');
      expect((((await relais.dest.etat())['copies'] as Map)['magasin'] as Map)['completes'], 0);
      final r = await sauvegarderHorsSite(dest: relais.dest, cle: cle, type: 'magasin', elements: [el('magasin', base)], tailleBloc: 128 * 1024, garder: 7);
      expect(r.dejaLa, greaterThanOrEqualTo(5));
      expect(r.deposes + r.dejaLa, greaterThanOrEqualTo(17));
      expect((((await relais.dest.etat())['copies'] as Map)['magasin'] as Map)['completes'], 1);
    });

    test('le plan est refusé AVANT tout dépôt : copie trop grosse, espace insuffisant (refus nommés avec geste)', () async {
      final cle = cleDeTest();
      await relais.regler('tailleMaxCopie', 1024 * 1024);
      final avant = (await relais.dest.etat())['nb_blocs'];
      final e = await refusDe(sauvegarderHorsSite(dest: relais.dest, cle: cle, type: 'magasin', elements: [el('magasin', alea('gros', 3 * 1024 * 1024))], tailleBloc: 512 * 1024, garder: 7));
      expect(e.code, 'SAUVEGARDE_TROP_GROSSE');
      expect(e.refus.geste, contains('limite par copie'));
      expect((await relais.dest.etat())['nb_blocs'], avant);
      await relais.regler('tailleMaxCopie', 1024 * 1024 * 1024);
      await relais.regler('quotaOctets', 500 * 1024);
      final e2 = await refusDe(sauvegarderHorsSite(dest: relais.dest, cle: cle, type: 'magasin', elements: [el('magasin', alea('gros2', 2 * 1024 * 1024))], tailleBloc: 512 * 1024, garder: 7));
      expect(e2.code, 'ESPACE_RELAIS_INSUFFISANT');
      expect((await relais.dest.etat())['nb_blocs'], avant);
      final e3 = await refusDe(sauvegarderHorsSite(dest: relais.dest, cle: cle, type: 'magasin', elements: [el('magasin', alea('petit', 300))], tailleBloc: 512 * 1024, garder: 1));
      expect(e3.code, 'ROTATION_HORS_BORNES');
    });

    test('un bloc altéré au relais : restauration refusée, bloc NOMMÉ, rien d\'écrit ; une mauvaise clé : CLE_INCORRECTE ; une cible existante : CIBLE_EXISTE', () async {
      final cle = cleDeTest();
      final r = await sauvegarderHorsSite(dest: relais.dest, cle: cle, type: 'magasin', elements: [el('magasin', alea('alt', 1024 * 1024))], tailleBloc: 256 * 1024, garder: 7);
      final c = await relais.dest.copie(r.copie);
      final racine = (c['racine'] as List).cast<String>();
      final ids = <String>[];
      for (final p in Directory('${relais.dir.path}/blocs-relais/blocs').listSync(recursive: true).whereType<File>()) {
        final id = p.uri.pathSegments.last;
        if (id.length == 64 && !racine.contains(id)) ids.add(id);
      }
      await relais.alterer(ids.first);
      final cibleA = '${tmp.path}/altere';
      final e = await refusDe(restaurerHorsSite(dest: relais.dest, cle: cle, copieId: r.copie, cible: cibleA));
      expect(e.code, 'BLOC_ALTERE');
      expect(e.refus.plus['bloc'], ids.first);
      expect(Directory(cibleA).existsSync(), isFalse);
      expect(tmp.listSync().where((x) => x.path.contains('reprise')), isEmpty, reason: 'aucun dossier de travail laissé');
      final cibleM = '${tmp.path}/mauvaise';
      expect((await refusDe(restaurerHorsSite(dest: relais.dest, cle: List.filled(32, 9), copieId: r.copie, cible: cibleM))).code, 'CLE_INCORRECTE');
      expect(Directory(cibleM).existsSync(), isFalse);
      Directory('${tmp.path}/existe').createSync();
      expect((await refusDe(restaurerHorsSite(dest: relais.dest, cle: cle, copieId: r.copie, cible: '${tmp.path}/existe'))).code, 'CIBLE_EXISTE');
    });

    test('INTEROPÉRABILITÉ : une copie faite par le banc (Node) se restaure par Dart, et une copie faite par Dart se restaure par le banc', () async {
      final cle = cleDeTest();
      final cleHex = cle.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
      final src = Directory('${tmp.path}/src-node')..createSync();
      final contenu = alea('node', 1500 * 1024);
      File('${src.path}/base.sqlite').writeAsBytesSync(contenu);
      final nd = await nodeJson('sauvegarde-proc.js', {'relais': relais.base, 'secret': secret, 'cle': cleHex, 'type': 'magasin', 'source': '${src.path}/base.sqlite', 'tailleBloc': 256 * 1024, 'garder': 7});
      expect(nd['ok'], isTrue, reason: '$nd');
      final cible = '${tmp.path}/par-dart';
      await restaurerHorsSite(dest: relais.dest, cle: cle, copieId: '${nd['copie']}', cible: cible);
      expect(sha256Octets(File('$cible/magasin').readAsBytesSync()), sha256Octets(contenu));
      // et l'inverse : Dart dépose un dossier de fichiers, le banc restaure
      final fic = {'${sha256Octets(alea('f1', 5000))}.jpg': alea('f1', 5000), '${sha256Octets(alea('f2', 700 * 1024))}.pdf': alea('f2', 700 * 1024)};
      final rd = await sauvegarderHorsSite(
          dest: relais.dest, cle: cle, type: 'fichiers', elements: [for (final e in fic.entries) el(e.key, e.value)], tailleBloc: 256 * 1024, garder: 14);
      final cibleN = '${tmp.path}/par-node';
      final nr = await nodeJson('sauvegarde-restaure.js', {'relais': relais.base, 'secret': secret, 'cle': cleHex, 'copie': rd.copie, 'cible': cibleN});
      expect(nr['ok'], isTrue, reason: '$nr');
      for (final e in fic.entries) {
        expect(sha256Octets(File('$cibleN/${e.key}').readAsBytesSync()), sha256Octets(e.value), reason: e.key);
      }
    });

    test('le contrôle nocturne : ok sur une copie saine, BLOC_ALTERE nommé sur une copie altérée', () async {
      final cle = cleDeTest();
      final r = await sauvegarderHorsSite(dest: relais.dest, cle: cle, type: 'magasin', elements: [el('magasin', alea('ctl', 900 * 1024))], tailleBloc: 128 * 1024, garder: 7);
      expect(await controlerHorsSite(dest: relais.dest, cle: cle, type: 'magasin', nbBlocs: 50), isNull);
      expect(await controlerHorsSite(dest: relais.dest, cle: cle, type: 'fichiers', nbBlocs: 50), isNull, reason: 'aucune copie : rien à contrôler, jamais un faux vert nommé');
      final c = await relais.dest.copie(r.copie);
      final racine = (c['racine'] as List).cast<String>();
      final id = Directory('${relais.dir.path}/blocs-relais/blocs').listSync(recursive: true).whereType<File>().map((f) => f.uri.pathSegments.last).firstWhere((i) => i.length == 64 && !racine.contains(i));
      await relais.alterer(id);
      final refus = await controlerHorsSite(dest: relais.dest, cle: cle, type: 'magasin', nbBlocs: 50);
      expect(refus, isNotNull);
      expect(['BLOC_ALTERE', 'BLOC_ALTERE_AU_RELAIS'], contains(refus!.code));
    });
  });

  group('destination « dossier distant monté »', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('sigh-sauv-dossier-'));
    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('un dossier absent n\'est JAMAIS créé : refus nommé DOSSIER_INTROUVABLE avec le geste', () async {
      final d = DestinationDossier('${tmp.path}/pas-monte');
      final e = await refusDe(sauvegarderHorsSite(dest: d, cle: cleDeTest(), type: 'magasin', elements: [el('magasin', alea('a', 100))], tailleBloc: 65536, garder: 7));
      expect(e.code, 'DOSSIER_INTROUVABLE');
      expect(e.refus.geste, isNotEmpty);
      expect(Directory('${tmp.path}/pas-monte').existsSync(), isFalse);
    });

    test('cycle complet : dépôt, rejeu, rotation par archivage, restauration octet par octet, fichiers avec leurs métadonnées', () async {
      final racine = Directory('${tmp.path}/distant')..createSync();
      final d = DestinationDossier(racine.path);
      final cle = cleDeTest();
      final etat = await d.etat();
      expect((etat['limites'] as Map).containsKey('quotaOctets'), isFalse, reason: 'aucun quota connu : absent, jamais zéro');
      final ids = <String>[];
      var t = 1000;
      for (final g in ['a', 'b', 'c', 'd']) {
        final r = await sauvegarderHorsSite(dest: d, cle: cle, type: 'magasin', elements: [el('magasin', alea(g, 200 * 1024))], tailleBloc: 65536, garder: 2, date: t++);
        ids.add(r.copie);
      }
      final liste = await d.copies('magasin');
      expect(liste.where((c) => c['etat'] == 'complete').length, 2);
      expect(liste.where((c) => c['etat'] == 'archivee').length, 2, reason: 'archivées, jamais supprimées');
      expect(liste.where((c) => c['etat'] == 'complete').map((c) => c['id']).toSet(), {ids[2], ids[3]});
      final r2 = await sauvegarderHorsSite(dest: d, cle: cle, type: 'magasin', elements: [el('magasin', alea('d', 200 * 1024))], tailleBloc: 65536, garder: 2, date: t++);
      expect(r2.rejeu, isTrue);
      // restauration d'une copie ARCHIVÉE
      final cible = '${tmp.path}/vers-neuf';
      await restaurerHorsSite(dest: d, cle: cle, copieId: ids[0], cible: cible);
      expect(sha256Octets(File('$cible/magasin').readAsBytesSync()), sha256Octets(alea('a', 200 * 1024)));
      // les fichiers, avec leurs métadonnées
      final f1 = alea('fic1', 4000), f2 = alea('fic2', 150 * 1024);
      final m1 = {'ext': 'jpg', 'usages': [{'famille': 'courrier', 'zone': 0}]};
      final rf = await sauvegarderHorsSite(
          dest: d, cle: cle, type: 'fichiers', elements: [el('${sha256Octets(f1)}.jpg', f1, meta: m1), el('${sha256Octets(f2)}.pdf', f2)], tailleBloc: 65536, garder: 14);
      final res = await restaurerHorsSite(dest: d, cle: cle, copieId: rf.copie, cible: '${tmp.path}/fichiers-neufs');
      expect(res.elements, 2);
      expect(res.metas['${sha256Octets(f1)}.jpg'], m1);
      expect(sha256Octets(File('${tmp.path}/fichiers-neufs/${sha256Octets(f2)}.pdf').readAsBytesSync()), sha256Octets(f2));
    });

    test('un bloc altéré dans le dossier : le contrôle ET la restauration le nomment ; rien n\'est restauré à moitié', () async {
      final racine = Directory('${tmp.path}/distant')..createSync();
      final d = DestinationDossier(racine.path);
      final cle = cleDeTest();
      final r = await sauvegarderHorsSite(dest: d, cle: cle, type: 'magasin', elements: [el('magasin', alea('alt', 300 * 1024))], tailleBloc: 65536, garder: 7);
      final c = await d.copie(r.copie);
      final racineIds = (c['racine'] as List).cast<String>();
      final fichier = racine.listSync(recursive: true).whereType<File>().firstWhere((f) {
        final n = f.uri.pathSegments.last;
        return n.length == 64 && !racineIds.contains(n);
      });
      final o = fichier.readAsBytesSync()..[5] ^= 1;
      fichier.writeAsBytesSync(o);
      final refus = await controlerHorsSite(dest: d, cle: cle, type: 'magasin', nbBlocs: 100);
      expect(refus?.code, 'BLOC_ALTERE');
      expect(refus?.plus['bloc'], fichier.uri.pathSegments.last);
      final cible = '${tmp.path}/jamais';
      final e = await refusDe(restaurerHorsSite(dest: d, cle: cle, copieId: r.copie, cible: cible));
      expect(e.code, 'BLOC_ALTERE');
      expect(Directory(cible).existsSync(), isFalse);
      expect(tmp.listSync().where((x) => x.path.contains('reprise')), isEmpty);
    });
  });

  group('copie incrémentale : l\'index local évite de relire ce que la destination tient déjà', () {
    test('un fichier connu de l\'index et présent à la destination n\'est pas relu ; un bloc disparu est relu et redéposé', () async {
      final tmp = Directory.systemTemp.createTempSync('sigh-sauv-index-');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final racine = Directory('${tmp.path}/distant')..createSync();
      final d = DestinationDossier(racine.path);
      final cle = cleDeTest();
      final index = <String, List<Map<String, Object?>>>{};
      var lectures = 0;
      final f = alea('inc', 150 * 1024);
      ElementASauver e() => el('${sha256Octets(f)}.pdf', f, sha: true, surLecture: () => lectures++);
      final r1 = await sauvegarderHorsSite(dest: d, cle: cle, type: 'fichiers', elements: [e()], tailleBloc: 65536, garder: 14, index: index, date: 1);
      expect(lectures, 1);
      final g = alea('inc2', 3000);
      final r2 = await sauvegarderHorsSite(dest: d, cle: cle, type: 'fichiers', elements: [e(), el('${sha256Octets(g)}.jpg', g, sha: true, surLecture: () => lectures++)], tailleBloc: 65536, garder: 14, index: index, date: 2);
      expect(lectures, 2, reason: 'le premier fichier n\'a pas été relu, seul le nouveau l\'a été');
      expect(r2.copie, isNot(r1.copie));
      // un bloc disparaît de la destination : le fichier est relu et le bloc redéposé
      final premier = (index.values.first.first['id'] as String);
      File('${racine.path}/blocs/${premier.substring(0, 2)}/$premier').deleteSync();
      final r3 = await sauvegarderHorsSite(dest: d, cle: cle, type: 'fichiers', elements: [e()], tailleBloc: 65536, garder: 14, index: index, date: 3);
      expect(lectures, 3);
      expect(r3.deposes, greaterThanOrEqualTo(1));
    });
  });
}

/// Une destination qui garde tout ce que le client lui envoie (corps des requêtes, blocs).
class _Ecoute implements DestinationSauvegarde {
  _Ecoute(this.d);
  final DestinationSauvegarde d;
  final BytesBuilder vu = BytesBuilder();
  @override
  String get libelle => d.libelle;
  @override
  Future<Map<String, Object?>> etat() => d.etat();
  @override
  Future<List<String>> manquants(List<String> ids) {
    vu.add(utf8.encode(jsonEncode(ids)));
    return d.manquants(ids);
  }

  @override
  Future<Map<String, Object?>> deposerBloc(String id, Uint8List octets) {
    vu.add(utf8.encode(id));
    vu.add(octets);
    return d.deposerBloc(id, octets);
  }

  @override
  Future<Map<String, Object?>> ouvrir(String id, String type, int date, int garder) {
    vu.add(utf8.encode(jsonEncode({'id': id, 'type': type, 'date': date, 'garder': garder})));
    return d.ouvrir(id, type, date, garder);
  }

  @override
  Future<void> attacher(String id, List<String> ids) {
    vu.add(utf8.encode(jsonEncode({'id': id, 'ids': ids})));
    return d.attacher(id, ids);
  }

  @override
  Future<Map<String, Object?>> valider(String id, List<String> racine) {
    vu.add(utf8.encode(jsonEncode({'id': id, 'racine': racine})));
    return d.valider(id, racine);
  }

  @override
  Future<List<Map<String, Object?>>> copies(String type) => d.copies(type);
  @override
  Future<Map<String, Object?>> copie(String id) => d.copie(id);
  @override
  Future<Uint8List> bloc(String id) => d.bloc(id);
}
