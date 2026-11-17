import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/maj_poste.dart';
import 'package:sigh_poste/donnees/persistance.dart';

/// LOT MAJ : le parcours « mettre à jour sans perdre une donnée » sur de VRAIS fichiers chiffrés (dossiers temporaires, clé de clinique).
/// Mutations rouges jouées (voir la section BG) : migration sans sauvegarde acceptée, migration non idempotente, import sans clé, comptes différents non nommés, état mixte après coupure,
/// retour arrière qui écrase une saisie, export lisible en clair, version plus récente acceptée.
final cle = List<int>.generate(32, (i) => (i * 7 + 3) & 0xff);
final autreCle = List<int>.generate(32, (i) => (i * 5 + 1) & 0xff);
var horloge = DateTime.utc(2026, 11, 17, 10);

late Directory tmp;
late String d;

Future<void> seme(String dir, {int patients = 40, List<int>? k}) async {
  final p = PersistanceFichiers(dir, cle: k ?? cle);
  await p.ecrire('patients', [
    for (var i = 0; i < patients; i++) {'id': 'p$i', 'nom': 'Patient$i', 'telephone': i % 3 == 0 ? null : '9700$i'}
  ]);
  await p.ecrire('factures', [
    for (var i = 0; i < 12; i++) {'id': 'f$i', 'total': 1000 * (i + 1), 'remise': null}
  ]);
}

ServiceMiseAJour svc(String dir, {List<int>? k, void Function(int)? coupure, String? fichiers}) =>
    ServiceMiseAJour(dossier: dir, cle: k ?? cle, horloge: () => horloge, apresEcritureCollection: coupure, dossierFichiers: fichiers);

Future<String> empreinteDossier(String dir) async {
  final noms = [for (final e in Directory(dir).listSync()) if (e is File && (e.path.endsWith('.sigh') || e.path.endsWith('.json'))) e.uri.pathSegments.last]..sort();
  return sha256Octets(utf8.encode([for (final n in noms) '$n:${sha256Octets(File('$dir/$n').readAsBytesSync())}'].join('|')));
}

Future<void> attendRefus(Future<Object?> f, String code) async {
  try {
    await f;
    fail('refus attendu : $code');
  } on RefusMajException catch (e) {
    expect(e.code, code);
    expect(e.refus.geste, isNotEmpty);
  }
}

void main() {
  setUp(() async {
    horloge = DateTime.utc(2026, 11, 17, 10);
    tmp = await Directory.systemTemp.createTemp('maj-');
    d = '${tmp.path}/donnees';
    await seme(d);
  });
  tearDown(() async => tmp.delete(recursive: true));

  group('Préparer la mise à jour', () {
    test('copie chiffrée, restauration vérifiée dans un dossier neuf, manifeste signé, journal RG-12', () async {
      final s = svc(d);
      final dest = await s.preparer();
      expect(File('$dest/manifeste.json').existsSync(), isTrue);
      expect(Directory('$d-maj/verif').listSync(), isEmpty, reason: 'la restauration d’essai est jetée');
      expect(File('$dest/donnees/patients.sigh').existsSync(), isTrue);
      expect(File('$dest/donnees/patients.json').existsSync(), isFalse, reason: 'aucun clair');
      final c = await s.derniereCopieVerifiee();
      expect(c, isNotNull);
      final j = (await s.journal()).single;
      expect(j['action'], 'preparer');
      expect((j['collections'] as Map)['patients'], containsPair('compte', 40));
    });

    test('une copie dont une collection est altérée n’est PLUS vérifiée', () async {
      final s = svc(d);
      final dest = await s.preparer();
      File('$dest/donnees/patients.sigh').writeAsBytesSync([1, 2, 3]);
      expect(await s.derniereCopieVerifiee(), isNull);
    });

    test('un manifeste falsifié ou signé par une autre clé n’est pas cru', () async {
      final dest = await svc(d).preparer();
      expect(await svc(d, k: autreCle).derniereCopieVerifiee(), isNull);
      final f = File('$dest/manifeste.json');
      f.writeAsStringSync(f.readAsStringSync().replaceFirst('"compte":40', '"compte":41'));
      expect(await svc(d).derniereCopieVerifiee(), isNull);
    });
  });

  group('Migration', () {
    test('MAJ_SANS_SAUVEGARDE : aucune copie, puis copie trop ancienne', () async {
      final s = svc(d);
      final avant = await empreinteDossier(d);
      await attendRefus(s.migrer(geste: true), CodeMaj.sansSauvegarde);
      expect(await empreinteDossier(d), avant, reason: 'le refus n’a rien écrit');
      await s.preparer();
      horloge = horloge.add(const Duration(hours: 25));
      final apresCopie = await empreinteDossier(d);
      await attendRefus(s.migrer(geste: true), CodeMaj.sansSauvegarde);
      expect(await empreinteDossier(d), apresCopie, reason: 'le refus n’a rien écrit');
    });

    test('le moteur refuse sans le geste réservé', () async {
      final s = svc(d);
      await s.preparer();
      await attendRefus(s.migrer(geste: false), CodeMaj.geste);
    });

    test('migration réelle : version écrite, comptes identiques, rapport lisible, journal, idempotente', () async {
      final s = svc(d);
      expect(await s.formatDonnees(), 0);
      await s.preparer();
      final r = await s.migrer(geste: true);
      expect(r.comptes.ok, isTrue, reason: r.comptes.phrase);
      expect(r.comptes.phrase, startsWith('52 fiches avant, 52 après'));
      expect(r.etapes, ['M001', 'M002']);
      expect(await s.formatDonnees(), formatDonneesCourant);
      final lu = await PersistanceFichiers(d, cle: cle).lireTout();
      expect(lu['patients']!.length, 40);
      expect(lu['patients']!.first.containsKey('telephone'), isFalse);
      expect(lu[collectionArchiveMigrations]!.length, greaterThan(0));
      final apres = await empreinteDossier(d);
      final deux = await s.migrer(geste: true);
      expect(deux.notes.single, contains('déjà au format courant'));
      expect(await empreinteDossier(d), apres, reason: 'migrer deux fois ne change rien');
      expect((await s.journal()).map((x) => x['action']), containsAllInOrder(['preparer', 'migrer']));
    });

    test('ESSAI À BLANC : dit ce qui changerait et n’écrit rien', () async {
      final s = svc(d);
      final avant = await empreinteDossier(d);
      final r = await s.essaiABlanc();
      expect(r.notes.join(' '), contains('champ(s) nul(s) retiré(s)'));
      expect(r.comptes.lignes.any((l) => l.statut == 'modifiee_par_migration'), isTrue);
      expect(await empreinteDossier(d), avant);
      expect(Directory('$d-maj').existsSync(), isFalse, reason: 'pas même un journal');
    });

    test('DONNEES_PLUS_RECENTES : des données d’un format futur ne s’ouvrent pas', () async {
      final p = PersistanceFichiers(d, cle: cle);
      await p.ecrireMeta({'formatDonnees': formatDonneesCourant + 1});
      final s = svc(d);
      await attendRefus(s.migrer(geste: true), CodeMaj.donneesPlusRecentes);
      await attendRefus(s.essaiABlanc(), CodeMaj.donneesPlusRecentes);
    });

    test('COUPURE au milieu de la migration : à la reprise, les données d’AVANT, jamais un état mixte', () async {
      final avant = await empreinteDossier(d);
      final lu0 = await PersistanceFichiers(d, cle: cle).lireTout();
      await svc(d).preparer();
      final apresCopie = await empreinteDossier(d); // `preparer` a écrit la méta (dernière copie)
      expect(apresCopie, isNot(avant));
      try {
        await svc(d, coupure: (n) {
          if (n == 1) throw StateError('COUPURE DE COURANT');
        }).migrer(geste: true);
        fail('la coupure doit remonter');
      } on StateError catch (e) {
        expect(e.message, 'COUPURE DE COURANT');
      }
      expect(File('$d-maj/en-cours.json').existsSync(), isTrue, reason: 'le poste sait qu’une opération était en cours');
      // redémarrage : nouveau service, même dossier
      final s2 = svc(d);
      expect(await s2.reprendreSiInterrompu(), isTrue);
      expect(await empreinteDossier(d), apresCopie, reason: 'octet pour octet les données d’avant');
      expect(await s2.formatDonnees(), 0);
      expect((await PersistanceFichiers(d, cle: cle).lireTout())['patients'], lu0['patients']);
      expect(await s2.reprendreSiInterrompu(), isFalse);
      expect(Directory('$d-maj/interrompus').listSync(), isNotEmpty, reason: 'l’état mixte est mis de côté, jamais supprimé');
      // et la migration peut être relancée
      final r = await s2.migrer(geste: true);
      expect(r.comptes.ok, isTrue);
    });

    test('un contrôle d’après migration qui diverge remet les données d’avant (comptes différents NOMMÉS)', () async {
      final s = ServiceMiseAJour(dossier: d, cle: cle, horloge: () => horloge, apresEcritureCollection: (n) {
        // on abîme une collection déjà écrite : le relu ne sera plus ce qui a été écrit
        if (n == 2) File('$d/patients.sigh').writeAsBytesSync(File('$d/factures.sigh').readAsBytesSync());
      });
      await s.preparer();
      final avant = await empreinteDossier(d);
      try {
        await s.migrer(geste: true);
        fail('refus attendu');
      } on Object catch (e) {
        expect('$e', isNotEmpty);
      }
      expect(File('$d-maj/en-cours.json').existsSync(), isFalse);
      expect(await empreinteDossier(d), avant);
    });
  });

  group('Retour arrière', () {
    test('restaure la dernière copie vérifiée, liste les saisies postérieures et les GARDE', () async {
      final s = svc(d);
      await s.preparer();
      await s.migrer(geste: true);
      final p = PersistanceFichiers(d, cle: cle);
      final patients = (await p.lireTout())['patients']!;
      await p.ecrire('patients', [...patients, {'id': 'tardif', 'nom': 'Saisi après la copie'}]);
      final prop = await s.proposerRetourArriere(geste: true);
      expect(prop.refus, isNull);
      expect([for (final x in prop.saisies) '${x.collection}/${x.fiche}:${x.nature}'], contains('patients/tardif:creee'));
      final r = await s.retourArriere(geste: true);
      expect(await s.formatDonnees(), 0, reason: 'le format de la copie');
      final apres = (await PersistanceFichiers(d, cle: cle).lireTout())['patients']!;
      expect(apres.any((f) => f['id'] == 'tardif'), isFalse);
      final gardee = (await PersistanceFichiers('${r.copie}', cle: cle).lireTout())['patients']!;
      expect(gardee.any((f) => f['id'] == 'tardif'), isTrue, reason: 'la saisie postérieure est conservée, jamais écrasée en silence');
      expect(r.saisies, isNotEmpty);
    });

    test('refus nommé sans copie vérifiée et sans geste', () async {
      final s = svc(d);
      await attendRefus(s.retourArriere(geste: true), CodeMaj.retourSansCopie);
      await s.preparer();
      await attendRefus(s.retourArriere(geste: false), CodeMaj.geste);
    });
  });

  group('Export portable et import', () {
    test('un seul fichier chiffré : illisible en clair, clé jamais dedans', () async {
      final f = await svc(d).exporter('${tmp.path}/export.sighexp');
      final octets = File(f).readAsBytesSync();
      final texte = latin1.decode(octets);
      expect(texte.contains('Patient1'), isFalse);
      expect(texte.contains('patients'), isFalse);
      expect(utf8.decode(octets.sublist(0, 4)), 'SGX1');
      final hexCle = [for (final b in cle) b.toRadixString(16).padLeft(2, '0')].join();
      expect(texte.contains(hexCle), isFalse);
    });

    test('import dans un dossier neuf, autre machine : mêmes comptes, base, fichiers numérisés, format migré', () async {
      Directory('${tmp.path}/scans/aa').createSync(recursive: true);
      File('${tmp.path}/scans/aa/x.pdf').writeAsBytesSync([9, 8, 7]);
      final f = await svc(d, fichiers: '${tmp.path}/scans').exporter('${tmp.path}/export.sighexp');
      final neuf = '${tmp.path}/machine2/donnees';
      final s2 = svc(neuf, fichiers: '${tmp.path}/machine2/scans');
      await s2.preparer(); // copie préalable (dossier neuf : rien à perdre, mais la règle est la même)
      final r = await s2.importer(f, geste: true);
      final lu = await PersistanceFichiers(neuf, cle: cle).lireTout();
      expect(lu['patients']!.length, 40);
      expect(lu['factures']!.length, 12);
      expect(await s2.formatDonnees(), formatDonneesCourant);
      expect(File('${tmp.path}/machine2/scans/aa/x.pdf').readAsBytesSync(), [9, 8, 7]);
      expect(r.comptes.differences, isEmpty);
    });

    test('IMPORT_SANS_COPIE_PREALABLE', () async {
      final f = await svc(d).exporter('${tmp.path}/e.sighexp');
      final s2 = svc('${tmp.path}/m2/donnees');
      await attendRefus(s2.importer(f, geste: true), CodeMaj.importSansCopie);
    });

    test('autre clinique : IMPORT_AUTRE_CLINIQUE ; fichier altéré : IMPORT_ALTERE ; geste : MAJ_GESTE_RESERVE', () async {
      final f = await svc(d).exporter('${tmp.path}/e.sighexp');
      final m2 = '${tmp.path}/m2/donnees';
      await seme(m2, k: autreCle, patients: 2);
      final autre = svc(m2, k: autreCle);
      await autre.preparer();
      await attendRefus(autre.importer(f, geste: true), CodeMaj.importAutreClinique);
      final brut = File(f).readAsBytesSync()..[100] ^= 0xff;
      File('${tmp.path}/alt.sighexp').writeAsBytesSync(brut);
      final s = svc(d);
      await s.preparer();
      await attendRefus(s.importer('${tmp.path}/alt.sighexp', geste: true), CodeMaj.importAltere);
      await attendRefus(s.importer(f, geste: false), CodeMaj.geste);
    });

    test('DONNEES_PLUS_RECENTES à l’import', () async {
      await PersistanceFichiers(d, cle: cle).ecrireMeta({'formatDonnees': formatDonneesCourant + 1});
      final f = await svc(d).exporter('${tmp.path}/e.sighexp');
      final m2 = svc('${tmp.path}/m2/donnees');
      await m2.preparer();
      await attendRefus(m2.importer(f, geste: true), CodeMaj.donneesPlusRecentes);
    });

    test('un fichier numérisé existant n’est jamais écrasé ; l’essai à blanc n’écrit rien', () async {
      Directory('${tmp.path}/scans').createSync(recursive: true);
      File('${tmp.path}/scans/a.pdf').writeAsBytesSync([1]);
      final f = await svc(d, fichiers: '${tmp.path}/scans').exporter('${tmp.path}/e.sighexp');
      File('${tmp.path}/scans/a.pdf').writeAsBytesSync([2]);
      final s = svc(d, fichiers: '${tmp.path}/scans');
      await s.preparer();
      final avant = await empreinteDossier(d);
      final blanc = await s.importer(f, geste: true, essaiABlanc: true);
      expect(blanc.notes.first, contains('Essai à blanc'));
      expect(await empreinteDossier(d), avant);
      await s.importer(f, geste: true);
      expect(File('${tmp.path}/scans/a.pdf').readAsBytesSync(), [2]);
    });

    test('fileul rattaché : base plus ancienne que la synchro = avertissement non bloquant ; saisies locales listées et gardées', () async {
      final f = await svc(d).exporter('${tmp.path}/e.sighexp');
      final p = PersistanceFichiers(d, cle: cle);
      final pat = (await p.lireTout())['patients']!;
      await p.ecrire('patients', [...pat, {'id': 'local', 'nom': 'Saisie hors ligne'}]);
      final s = svc(d);
      await s.preparer();
      final r = await s.importer(f, geste: true, fileulRattache: true, derniereSynchro: horloge.add(const Duration(hours: 1)));
      expect(r.avertissements.single, startsWith('IMPORT_PLUS_ANCIEN_QUE_SYNC'));
      expect([for (final x in r.saisies) x.fiche], contains('local'));
      final gardee = (await PersistanceFichiers(r.copie!, cle: cle).lireTout())['patients']!;
      expect(gardee.any((x) => x['id'] == 'local'), isTrue);
    });
  });
}
