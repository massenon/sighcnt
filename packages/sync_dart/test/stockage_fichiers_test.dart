// Le stockage des fichiers numérisés sur le disque d'un poste (lot D5, étape 3) : rangement par empreinte, empreinte recalculée à chaque lecture, chiffrement au repos, écriture
// atomique, morceaux d'un transfert qui reprend, jamais deux copies.
import 'dart:io';
import 'dart:typed_data';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_sync/sigh_sync.dart';
import 'package:test/test.dart';

const fixtures = '../../apps/poste/test/fixtures/fichiers';
Uint8List fx(String n) => File('$fixtures/$n').readAsBytesSync();
final cle = List<int>.generate(32, (i) => i * 7 + 3);

Future<ErreurFichier> refus(Future<Object?> Function() f) async {
  try {
    await f();
  } on ErreurFichier catch (e) {
    return e;
  }
  fail('un refus nommé était attendu');
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sigh-stock-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  for (final chiffre in [false, true]) {
    group(chiffre ? 'chiffré au repos' : 'en clair (développement)', () {
      StockageFichiers nouveau() => StockageFichiers(tmp.path, cle: chiffre ? cle : null);

      test('un fichier se range sous <aa>/<empreinte>.<ext> et se relit à l’identique, sans fichier temporaire', () async {
        final s = nouveau();
        final b = fx('courrier-texte.pdf');
        final r = await s.ranger(b, famille: 'courrier', zone: 0, deposePar: 'Agent');
        expect(r.sha256, sha256Octets(b));
        expect(r.nouveau, isTrue);
        expect(r.ext, 'pdf');
        final chemin = '${tmp.path}/${r.sha256.substring(0, 2)}/${r.sha256}.pdf';
        expect(File(chemin).existsSync(), isTrue);
        expect(await s.lire(r.sha256), b);
        expect(await s.cheminDe(r.sha256), chemin);
        final restes = tmp.listSync(recursive: true).where((f) => f.path.endsWith('.tmp'));
        expect(restes, isEmpty);
        final disque = File(chemin).readAsBytesSync();
        if (chiffre) {
          expect(disque.sublist(0, 4), [0x53, 0x47, 0x46, 0x31]);
          expect(disque, isNot(b), reason: 'au repos le fichier n’est pas en clair');
          expect(disque.length, b.length + 4 + 12 + 16);
        } else {
          expect(disque, b);
        }
      });

      test('un fichier altéré sur le disque n’est JAMAIS servi : le refus nomme l’empreinte', () async {
        final s = nouveau();
        final b = fx('scan.png');
        final r = await s.ranger(b, famille: 'courrier', zone: 0);
        final f = File(await s.cheminDe(r.sha256) as String);
        final x = f.readAsBytesSync();
        x[x.length - 5] ^= 0xff;
        f.writeAsBytesSync(x);
        final e = await refus(() => nouveau().lire(r.sha256));
        expect(e.refus.code, 'FICHIER_ALTERE');
        expect(e.refus.motif, contains(r.sha256.substring(0, 8)));
        expect(await nouveau().etat(r.sha256), EtatLocalFichier.altere);
      });

      test('redéposer les mêmes octets RÉPARE la copie altérée ; un fichier intact n’est pas réécrit (une copie)', () async {
        final s = nouveau();
        final b = fx('scan.png');
        final r1 = await s.ranger(b, famille: 'courrier', zone: 0);
        final f = File(await s.cheminDe(r1.sha256) as String);
        final avant = f.lastModifiedSync();
        final r2 = await s.ranger(b, famille: 'courrier', zone: 0);
        expect(r2.nouveau, isFalse);
        expect(r2.repare, isFalse);
        expect(f.lastModifiedSync(), avant, reason: 'un fichier intact n’est pas réécrit');
        final x = f.readAsBytesSync()..[20] ^= 1;
        f.writeAsBytesSync(x);
        final r3 = await nouveau().ranger(b, famille: 'courrier', zone: 0);
        expect(r3.repare, isTrue);
        expect(await nouveau().lire(r1.sha256), b);
        expect(tmp.listSync(recursive: true).whereType<File>().where((x) => x.path.endsWith('.png')).length, 1);
      });

      test('absent : FICHIER_ABSENT, état absent ; empreinte invalide refusée', () async {
        final s = nouveau();
        expect((await refus(() => s.lire('a' * 64))).refus.code, 'FICHIER_ABSENT');
        expect(await s.etat('a' * 64), EtatLocalFichier.absent);
        expect((await refus(() => s.lire('../etc/passwd'))).refus.code, 'EMPREINTE_INVALIDE');
      });

      test('refus nommés : format lu sur les octets, WEBP au courrier, vide, taille, empreinte annoncée fausse', () async {
        final s = nouveau();
        expect((await refus(() => s.ranger(fx('faux.exe'), famille: 'courrier', zone: 0))).refus.code, 'FORMAT_REFUSE');
        expect((await refus(() => s.ranger(fx('image.gif'), famille: 'patient', zone: 1))).refus.code, 'FORMAT_REFUSE');
        expect((await refus(() => s.ranger(fx('scan.webp'), famille: 'courrier', zone: 0))).refus.code, 'FORMAT_REFUSE');
        await s.ranger(fx('scan.webp'), famille: 'patient', zone: 1);
        expect((await refus(() => s.ranger(Uint8List(0), famille: 'courrier', zone: 0))).refus.code, 'FICHIER_VIDE');
        expect((await refus(() => s.ranger(fx('scan.png'), famille: 'courrier', zone: 0, tailleMax: 1000))).refus.code, 'TAILLE_DEPASSEE');
        final e = await refus(() => s.ranger(fx('scan.png'), famille: 'courrier', zone: 0, shaAnnonce: '0' * 64));
        expect(e.refus.code, 'EMPREINTE_DIVERGENTE');
        expect(e.refus.plus['recu'], sha256Octets(fx('scan.png')));
        expect(tmp.listSync(recursive: true).whereType<File>().where((f) => f.path.contains('scan')), isEmpty);
      });

      test('la fiche d’accompagnement cumule les usages (famille, zone) : la lecture applique le plus strict', () async {
        final s = nouveau();
        final b = fx('scan.png');
        final r = await s.ranger(b, famille: 'patient', zone: 1, deposePar: 'Accueil');
        await s.ranger(b, famille: 'patient', zone: 2, deposePar: 'Medecin');
        await s.ranger(b, famille: 'courrier', zone: 0);
        await s.ranger(b, famille: 'courrier', zone: 0);
        final m = (await s.meta(r.sha256))!;
        expect(m.usages.length, 3);
        expect(m.zoneMax('patient'), 2);
        expect(m.zoneMax('courrier'), 0);
        expect(m.sertA('courrier'), isTrue);
        expect(m.deposePar, 'Accueil', reason: 'le premier déposant reste');
        expect(m.taille, b.length);
        expect(m.mime, 'image/png');
      });

      test('empreintes() liste ce qui est rangé, rien d’autre', () async {
        final s = nouveau();
        final a = await s.ranger(fx('scan.png'), famille: 'courrier', zone: 0);
        final b = await s.ranger(fx('scan.jpg'), famille: 'courrier', zone: 0);
        expect({...await s.empreintes().toList()}, {a.sha256, b.sha256});
      });
    });
  }

  test('au repos, un fichier recopié sous une autre empreinte ne se déchiffre pas (l’empreinte est liée au chiffré)', () async {
    final s = StockageFichiers(tmp.path, cle: cle);
    final a = await s.ranger(fx('scan.png'), famille: 'courrier', zone: 0);
    final b = await s.ranger(fx('scan.jpg'), famille: 'courrier', zone: 0);
    final pa = File(await s.cheminDe(a.sha256) as String), pb = File(await s.cheminDe(b.sha256) as String);
    pb.writeAsBytesSync(pa.readAsBytesSync());
    expect((await refus(() => StockageFichiers(tmp.path, cle: cle).lire(b.sha256))).refus.code, 'FICHIER_ALTERE');
  });

  test('une autre clé ne lit pas : altéré, jamais servi', () async {
    final a = await StockageFichiers(tmp.path, cle: cle).ranger(fx('scan.png'), famille: 'courrier', zone: 0);
    final autre = StockageFichiers(tmp.path, cle: List<int>.filled(32, 9));
    expect((await refus(() => autre.lire(a.sha256))).refus.code, 'FICHIER_ALTERE');
  });

  test('un fichier en CLAIR sur un poste devenu chiffré est lu (empreinte tenue) puis réécrit chiffré', () async {
    final b = fx('scan.png');
    final clair = await StockageFichiers(tmp.path).ranger(b, famille: 'courrier', zone: 0);
    final s = StockageFichiers(tmp.path, cle: cle);
    expect(await s.lire(clair.sha256), b);
    final disque = File(await s.cheminDe(clair.sha256) as String).readAsBytesSync();
    expect(disque.sublist(0, 4), [0x53, 0x47, 0x46, 0x31]);
  });

  group('transfert par morceaux avec reprise', () {
    final b = fx('scan.jpg');
    final d = DescriptionFichier.deOctets(b, 16 * 1024);
    Uint8List morceau(int i) => Uint8List.sublistView(b, d.plan.debut(i), d.plan.fin(i));

    test('les morceaux se rangent, l’assemblage vérifie l’ensemble, le fichier est rangé et les morceaux effacés', () async {
      final s = StockageFichiers(tmp.path, cle: cle);
      final r = await s.ouvrirReception(d);
      for (var i = 0; i < d.plan.nombre; i++) {
        expect(await s.deposerMorceau(r, i, morceau(i)), isNull);
      }
      final res = await s.assembler(r, famille: 'patient', zone: 1);
      expect(res.sha256, d.sha256);
      expect(await s.lire(d.sha256), b);
      expect(Directory('${tmp.path}/_partiels/${d.sha256}').existsSync(), isFalse);
    });

    test('REPRISE après un redémarrage : seuls les morceaux déjà vérifiés comptent, le reste repart de là', () async {
      final s1 = StockageFichiers(tmp.path, cle: cle);
      final r1 = await s1.ouvrirReception(d);
      for (var i = 0; i < 3; i++) {
        expect(await s1.deposerMorceau(r1, i, morceau(i)), isNull);
      }
      // « redémarrage » : une nouvelle instance, la même base de morceaux
      final s2 = StockageFichiers(tmp.path, cle: cle);
      final r2 = await s2.ouvrirReception(d);
      expect(r2.verifies, {0, 1, 2});
      expect(r2.manquants.first, 3);
      for (final i in r2.manquants) {
        expect(await s2.deposerMorceau(r2, i, morceau(i)), isNull);
      }
      expect((await s2.assembler(r2, famille: 'patient', zone: 1)).sha256, d.sha256);
    });

    test('un morceau altéré est refusé (jamais rangé) ; un morceau abîmé sur le disque est écarté à la reprise', () async {
      final s = StockageFichiers(tmp.path, cle: cle);
      final r = await s.ouvrirReception(d);
      final m = Uint8List.fromList(morceau(1))..[10] ^= 1;
      expect((await s.deposerMorceau(r, 1, m))!.code, 'MORCEAU_ALTERE');
      expect(await s.morceauxRanges(d.sha256), isEmpty);
      expect(await s.deposerMorceau(r, 0, morceau(0)), isNull);
      final f = File('${tmp.path}/_partiels/${d.sha256}/0.part');
      final x = f.readAsBytesSync()..[30] ^= 1;
      f.writeAsBytesSync(x);
      final r2 = await StockageFichiers(tmp.path, cle: cle).ouvrirReception(d);
      expect(r2.verifies, isEmpty, reason: 'un morceau coupé en pleine écriture ne compte pas comme reçu');
      expect(f.existsSync(), isFalse);
    });

    test('au repos, un morceau en cours de transfert n’est pas en clair sur le disque', () async {
      final s = StockageFichiers(tmp.path, cle: cle);
      final r = await s.ouvrirReception(d);
      await s.deposerMorceau(r, 0, morceau(0));
      expect(File('${tmp.path}/_partiels/${d.sha256}/0.part').readAsBytesSync(), isNot(morceau(0)));
    });

    test('assembler un transfert incomplet est refusé en nommant les morceaux manquants', () async {
      final s = StockageFichiers(tmp.path);
      final r = await s.ouvrirReception(d);
      await s.deposerMorceau(r, 0, morceau(0));
      final e = await refus(() => s.assembler(r, famille: 'patient', zone: 1));
      expect(e.refus.code, 'TRANSFERT_INCOMPLET');
      expect(e.refus.plus['manquants'], isNotEmpty);
    });

    test('une description mensongère (empreinte d’ensemble fausse) : tout est jeté, rien n’est rangé', () async {
      final s = StockageFichiers(tmp.path);
      final menteuse = DescriptionFichier(sha256: sha256Octets(fx('scan.png')), taille: d.taille, tailleMorceau: d.tailleMorceau, morceaux: d.morceaux);
      final r = await s.ouvrirReception(menteuse);
      for (var i = 0; i < d.plan.nombre; i++) {
        await s.deposerMorceau(r, i, morceau(i));
      }
      expect((await refus(() => s.assembler(r, famille: 'patient', zone: 1))).refus.code, 'EMPREINTE_DIVERGENTE');
      expect(await s.existe(menteuse.sha256), isFalse);
      expect(Directory('${tmp.path}/_partiels/${menteuse.sha256}').existsSync(), isFalse);
    });

    test('un format refusé à l’assemblage (WEBP au courrier) jette les morceaux et le dit', () async {
      final w = fx('scan.webp');
      final dw = DescriptionFichier.deOctets(w, 16 * 1024);
      final s = StockageFichiers(tmp.path);
      final r = await s.ouvrirReception(dw);
      for (var i = 0; i < dw.plan.nombre; i++) {
        await s.deposerMorceau(r, i, Uint8List.sublistView(w, dw.plan.debut(i), dw.plan.fin(i)));
      }
      expect((await refus(() => s.assembler(r, famille: 'courrier', zone: 0))).refus.code, 'FORMAT_REFUSE');
      expect(await s.existe(dw.sha256), isFalse);
    });
  });
}
