import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/demarrage_maj.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/maj_poste.dart';
import 'package:sigh_poste/donnees/persistance.dart';

/// LOT MAJ, parcours de bout en bout avec le DÉMARRAGE du poste (`demarrerMiseAJour`, appelé par `main.dart`) sur un dossier de données d'AVANT (format 0 : aucun repère ; format 1 : jeu marqué), fait de
/// VRAIES collections du poste (jeu sobre, écrites par le magasin comme le poste les écrit) : démarrer ne migre rien en silence, « Préparer » puis « Migrer » donnent « N avant, N après », le poste
/// redémarre au format 2 et rouvre son magasin sans perdre une fiche ; une coupure au milieu de la migration est ramenée aux données d'avant au démarrage suivant.
final cle = List<int>.generate(32, (i) => (i * 17 + 2) & 0xff);

Future<Map<String, int>> compte(String dir) async => {for (final e in (await PersistanceFichiers(dir, cle: cle).lireTout()).entries) e.key: e.value.length};

/// Un dossier de données « d'avant » : le magasin du jeu sobre écrit sur le disque, avec des champs NULS comme les écrivait l'ancien format (jamais retirés).
Future<String> dossierDAvant(Directory tmp, {int format = 0}) async {
  final dir = '${tmp.path}/donnees';
  final m = Magasin.depuisDossier(Magasin.collectionsDuJeu, 'test/fixtures/jeu_sobre');
  final p = PersistanceFichiers('$dir/magasin', cle: cle);
  for (final n in Magasin.collectionsDuJeu) {
    final fiches = [for (final f in m.collection(n).toutes) {...f}];
    if (n == 'patients' && fiches.isNotEmpty) fiches.first['telephoneSecours'] = null; // l'ancien format écrivait des champs nuls
    await p.ecrire(n, fiches);
  }
  if (format > 0) await p.ecrireMeta({'formatDonnees': format});
  return dir;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('maj-demarrage-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  for (final format in [0, 1]) {
    test('format $format : démarrer ne migre pas en silence ; Préparer, Migrer, redémarrer : format ${formatDonneesCourant}, magasin rouvert sans perdre une fiche', () async {
      final dir = await dossierDAvant(tmp, format: format);
      final avant = await compte('$dir/magasin');
      expect(avant['patients'], greaterThan(0));
      final d0 = await demarrerMiseAJour(dossierDonnees: dir, cle: cle);
      expect(d0.format, format);
      expect(d0.refus, isNull);
      expect(d0.plan.etapes, isNotEmpty, reason: 'des migrations attendent le geste explicite');
      expect(await compte('$dir/magasin'), avant, reason: 'rien n’a été migré au démarrage');
      // les gestes de l'écran, dans l'ordre : sans copie vérifiée la migration refuse nommément
      try {
        await d0.service.migrer(geste: true);
        fail('MAJ_SANS_SAUVEGARDE attendu');
      } on RefusMajException catch (e) {
        expect(e.code, CodeMaj.sansSauvegarde);
      }
      await d0.service.preparer();
      final r = await d0.service.migrer(geste: true);
      expect(r.comptes.ok, isTrue, reason: r.comptes.phrase);
      expect(r.comptes.totalAvant, avant.values.fold<int>(0, (a, b) => a + b));
      // REDÉMARRAGE : le format stocké est repris, plus rien à migrer, le magasin se rouvre normalement
      final d1 = await demarrerMiseAJour(dossierDonnees: dir, cle: cle);
      expect(d1.format, formatDonneesCourant);
      expect(d1.plan.aRien, isTrue);
      final m = Magasin.depuisDossier(Magasin.collectionsDuJeu, 'test/fixtures/jeu_sobre');
      await m.brancherPersistance(PersistanceFichiers('$dir/magasin', cle: cle), delai: Duration.zero);
      expect(m.collection('patients').toutes.length, avant['patients'], reason: 'aucune fiche perdue à la migration');
      expect(m.collection('patients').toutes.first.containsKey('telephoneSecours'), isFalse, reason: 'le champ nul est retiré (M002), son nom est archivé');
      expect((await PersistanceFichiers('$dir/magasin', cle: cle).lireTout())[collectionArchiveMigrations], isNotEmpty);
      expect(Directory('$dir/magasin-maj/copies').listSync(), hasLength(1));
    });
  }

  test('COUPURE au milieu de la migration réelle : le démarrage suivant ramène les données d’avant, puis la migration se rejoue', () async {
    final dir = await dossierDAvant(tmp);
    final d0 = await demarrerMiseAJour(dossierDonnees: dir, cle: cle);
    await d0.service.preparer();
    final apresCopie = await compte('$dir/magasin');
    final service = ServiceMiseAJour(dossier: '$dir/magasin', cle: cle, apresEcritureCollection: (n) {
      if (n == 3) throw StateError('COUPURE DE COURANT');
    });
    await expectLater(service.migrer(geste: true), throwsA(isA<StateError>()));
    expect(File('$dir/magasin-maj/en-cours.json').existsSync(), isTrue);
    final d1 = await demarrerMiseAJour(dossierDonnees: dir, cle: cle);
    expect(d1.reprise, isTrue);
    expect(d1.format, 0, reason: 'les données d’avant, jamais un état mixte');
    expect(await compte('$dir/magasin'), apresCopie);
    final r = await d1.service.migrer(geste: true);
    expect(r.comptes.ok, isTrue);
  });

  test('un dossier NEUF reçoit le format courant sans migration ; des données PLUS RÉCENTES ne s’ouvrent pas (refus nommé, rien n’est écrit)', () async {
    final neuf = await demarrerMiseAJour(dossierDonnees: '${tmp.path}/neuf', cle: cle);
    expect(neuf.format, formatDonneesCourant);
    expect(neuf.plan.aRien, isTrue);
    final futur = '${tmp.path}/futur';
    await PersistanceFichiers('$futur/magasin', cle: cle).ecrire('patients', [{'id': 'p'}]);
    await PersistanceFichiers('$futur/magasin', cle: cle).ecrireMeta({'formatDonnees': formatDonneesCourant + 1});
    final d = await demarrerMiseAJour(dossierDonnees: futur, cle: cle);
    expect(d.refus!.code, CodeMaj.donneesPlusRecentes);
    expect(await compte('$futur/magasin'), {'patients': 1});
  });
}
