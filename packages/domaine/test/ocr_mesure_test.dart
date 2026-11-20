// La MESURE de l'OCR et le banc de mesure (lot OCR-prep), éprouvés sur des fixtures SYNTHÉTIQUES (aucun document de la clinique, aucune donnée de patient) et des moteurs FACTICES : ce qui est
// prouvé ici, c'est que la MESURE est juste (un moteur parfait donne 100 %, un moteur qui supprime les accents le montre, un moteur qui refuse n'est pas exclu), jamais la qualité d'un moteur.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import '../tool/src/mesure_dossier.dart';

const dossier = 'test/fixtures/ocr_banc';

void main() {
  group('les définitions de la mesure', () {
    test('un texte lu à l’identique : 100 % partout, aucun mot ni accent perdu', () {
      final m = ocrMesurer('Hyperglycémie sévère : père déjà traité.', 'Hyperglycémie sévère : père déjà traité.');
      expect(m.tauxMots, 1);
      expect(m.tauxCaracteres, 1);
      expect(m.motsPerdus, 0);
      expect(m.accentsPerdus, 0);
      expect(m.accentsReference, 7);
      expect(m.tauxAccents, 1);
    });
    test('un moteur qui SUPPRIME LES ACCENTS ne passe pas pour parfait : les mots corrects baissent, les accents sont tous perdus, aucun mot n’est « perdu » (il est retrouvé sans accent)', () {
      final ref = 'Hyperglycémie sévère : père déjà traité à Natitingou, œuf de ç.';
      final m = ocrMesurer(ref, sansDiacritiques(ref).replaceAll('œ', 'oe'));
      expect(m.tauxMots, lessThan(1));
      expect(m.tauxCaracteres, lessThan(1));
      expect(m.tauxAccents, 0, reason: 'chaque lettre accentuée de la référence a perdu son accent');
      expect(m.accentsPerdus, m.accentsReference);
      expect(m.motsPerdus, 0, reason: 'le mot est là, sans son accent : c’est un accent perdu, pas un mot perdu');
      expect(m.exemplesAccents, contains('père lu pere'));
    });
    test('un mot absent est PERDU ; la distance d’édition donne le taux (un mot sur quatre : 75 %)', () {
      final m = ocrMesurer('un deux trois quatre', 'un deux quatre');
      expect(m.tauxMots, 0.75);
      expect(m.motsPerdus, 1);
      expect(m.exemplesPerdus, ['trois']);
      expect(m.motsCorrects, 3);
    });
    test('un mot dit deux fois doit être lu deux fois ; la casse change le mot mais pas sa forme pliée', () {
      final m = ocrMesurer('Fièvre fièvre FIÈVRE', 'Fièvre fièvre');
      expect(m.motsPerdus, 1);
      final c = ocrMesurer('Natitingou', 'natitingou');
      expect(c.tauxMots, 0, reason: 'la casse compte dans le taux de mots corrects');
      expect(c.motsPerdus, 0, reason: 'mais le mot n’est pas perdu');
    });
    test('référence sans accent : le taux d’accents est SANS OBJET (jamais un 100 % de complaisance)', () {
      final m = ocrMesurer('paludisme grave', 'paludisme grave');
      expect(m.accentsReference, 0);
      expect(m.tauxAccents, isNull);
    });
    test('texte vide : lu vide contre référence vide donne 100 % ; lu vide contre une référence donne 0 %', () {
      expect(ocrMesurer('', '').tauxMots, 1);
      expect(ocrMesurer('abc def', '').tauxMots, 0);
      expect(ocrMesurer('abc def', '').tauxCaracteres, 0);
    });
    test('une lecture mauvaise est bornée à 0 (jamais un taux négatif)', () {
      final m = ocrMesurer('un', 'a b c d e f g h');
      expect(m.tauxMots, 0);
    });
  });

  group('le banc sur le dossier synthétique', () {
    late Directory sortie;
    setUp(() => sortie = Directory.systemTemp.createTempSync('sigh-mesure-ocr-'));
    tearDown(() => sortie.deleteSync(recursive: true));

    test('un moteur parfait donne 100 % ; un moteur qui supprime les accents le montre ; la comparaison est dans le rapport', () async {
      final r = await mesurerDossier(
          dossier: dossier,
          sortie: sortie.path,
          synthetique: true,
          avecExemples: true,
          maintenant: DateTime(2026, 11, 13),
          moteurs: (scans) => [moteurFactice('factice-parfait', scans), moteurFactice('factice-sans-accents', scans), moteurFactice('factice-perd-mots', scans), moteurFactice('factice-bruit', scans)]);
      final parfait = r.syntheses[0], sans = r.syntheses[1], perd = r.syntheses[2], bruit = r.syntheses[3];
      expect(parfait.nbScans, 3);
      expect(parfait.nbLus, 3);
      expect(parfait.moyenneMots, 1);
      expect(parfait.moyenneCaracteres, 1);
      expect(parfait.tauxMotsEnsemble, 1);
      expect(parfait.motsPerdus, 0);
      expect(parfait.tauxAccents, 1);
      expect(sans.moyenneMots, lessThan(1), reason: 'sans accents, des mots ne sont plus lus à l’identique : jamais 100 %');
      expect(sans.moyenneCaracteres, lessThan(1));
      expect(sans.tauxAccents, 0);
      expect(sans.accentsReference, greaterThan(10));
      expect(sans.motsPerdus, 0);
      expect(perd.motsPerdus, greaterThan(0));
      expect(perd.moyenneMots, lessThan(1));
      expect(bruit.moyenneCaracteres, lessThan(1));
      expect(parfait.msParPage, greaterThanOrEqualTo(0));
      // le rapport
      final md = File(r.rapport).readAsStringSync();
      expect(md, startsWith('# Mesure de la lecture OCR : rapport du 2026-11-13'));
      expect(md, contains('scans SYNTHÉTIQUES et des moteurs FACTICES'));
      expect(md, contains('factice-parfait 0.1'));
      expect(md, contains('100,0 %'));
      expect(md, contains('| factice-sans-accents 0.1 | 3 / 0 |'));
      expect(md, contains('Ce que ce rapport ne dit pas'));
      expect(md, contains('Il ne dit pas quel moteur choisir'));
      expect(md, contains('hyperglycémie lu hyperglycemie'));
      // le JSON se relit
      final j = jsonDecode(File(r.json).readAsStringSync()) as Map;
      expect(j['synthetique'], true);
      expect((j['moteurs'] as List), hasLength(4));
    });

    test('sans l’option « exemples », le rapport ne cite AUCUN mot des documents (des nombres seulement)', () async {
      final r = await mesurerDossier(
          dossier: dossier, sortie: sortie.path, moteurs: (scans) => [moteurFactice('factice-sans-accents', scans), moteurFactice('factice-perd-mots', scans)], maintenant: DateTime(2026, 11, 13));
      final md = File(r.rapport).readAsStringSync();
      expect(md, isNot(contains('hyperglycémie lu hyperglycemie')));
      expect(md, isNot(contains('hyperglycémie')));
      expect(md, contains('ne cite AUCUN mot des documents'));
      expect(md, isNot(contains('SYNTHÉTIQUES')), reason: 'un rapport de scans réels n’annonce pas des moteurs factices (c’est l’option --synthetique qui le dit)');
    });

    test('un moteur qui REFUSE un scan n’est pas exclu de la moyenne : zéro mot correct, refus nommé au rapport', () async {
      final scans = lireDossier(dossier).scans;
      final refus = MoteurOcrFactice(id: 'refuse-tout', refus: ocrRefus(CodeOcr.imageIllisible, 'image illisible'));
      final s = await mesurerMoteur(refus, scans);
      expect(s.nbRefuses, 3);
      expect(s.nbLus, 0);
      expect(s.moyenneMots, 0);
      expect(s.scans.first.refusCode, 'IMAGE_ILLISIBLE');
      final partiel = MoteurOcrFactice(id: 'moitie', textes: {for (final x in scans.take(2)) sha256Octets(x.octets): x.reference});
      final p = await mesurerMoteur(partiel, scans);
      expect(p.nbLus, 2);
      expect(p.nbRefuses, 1, reason: 'le troisième rend un texte vide : AUCUN_TEXTE, jamais une lecture');
      expect(p.moyenneMots, closeTo(2 / 3, 1e-9), reason: 'la moyenne porte sur les TROIS scans, pas sur les deux lus');
    });

    test('un dossier vide, des scans sans transcription, un PDF : dits, jamais ignorés en silence', () async {
      final vide = Directory.systemTemp.createTempSync('sigh-mesure-vide-');
      try {
        await expectLater(mesurerDossier(dossier: vide.path, sortie: sortie.path, moteurs: (_) => []), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('aucun scan avec sa transcription'))));
        File('${vide.path}/seul.png').writeAsBytesSync(File('$dossier/ordonnance-synthetique.png').readAsBytesSync());
        File('${vide.path}/avec.png').writeAsBytesSync(File('$dossier/ordonnance-synthetique.png').readAsBytesSync());
        File('${vide.path}/avec.txt').writeAsStringSync('Ordonnance de démonstration');
        File('${vide.path}/doc.pdf').writeAsBytesSync([0x25, 0x50, 0x44, 0x46, 0x2d, 0x31]);
        final r = await mesurerDossier(dossier: vide.path, sortie: sortie.path, moteurs: (s) => [moteurFactice('factice-parfait', s)], maintenant: DateTime(2026, 11, 13));
        final md = File(r.rapport).readAsStringSync();
        expect(md, contains('Scans sans transcription (ignorés)'));
        expect(md, contains('- seul.png'));
        expect(md, contains('PDF non mesurés'));
        expect(md, contains('- doc.pdf'));
        expect(md, contains('Mesure sur **1 scan**'));
        expect(md, contains('ne suffit pas pour décider'), reason: 'moins de trois scans : le rapport le dit');
      } finally {
        vide.deleteSync(recursive: true);
      }
    });
  }, tags: const []);

  group('le moteur par commande (le jour où un moteur est installé)', () {
    final posix = !Platform.isWindows;
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('sigh-commande-ocr-'));
    tearDown(() => tmp.deleteSync(recursive: true));
    EntreeOcr entree() => EntreeOcr(octets: File('$dossier/ordonnance-synthetique.png').readAsBytesSync(), format: 'png', langue: 'fra');

    test('la sortie standard est le texte lu ; {image} et {langue} sont remplacés', () async {
      final script = File('${tmp.path}/moteur.sh')..writeAsStringSync('#!/bin/sh\necho "lu \$2 depuis \$(basename \$1)"\n');
      Process.runSync('chmod', ['+x', script.path]);
      final m = MoteurOcrCommande('${script.path} {image} {langue}', id: 'script', version: '1');
      final r = await m.lire(entree());
      expect(r.texte.trim(), 'lu fra depuis scan.png');
      expect(r.moteur, 'script');
    }, skip: posix ? false : 'POSIX seulement');
    test('un code de sortie non nul : MOTEUR_EN_ECHEC nommé avec le message du moteur', () async {
      final script = File('${tmp.path}/echec.sh')..writeAsStringSync('#!/bin/sh\necho "données de langue absentes" 1>&2\nexit 3\n');
      Process.runSync('chmod', ['+x', script.path]);
      final r = await ocrLireFichier(moteur: MoteurOcrCommande(script.path), octets: entree().octets, formatId: 'png', mime: null, langue: 'fra', delaiMs: 5000);
      expect(r.ok, isFalse);
      expect(r.refus!.code, CodeOcr.moteurEnEchec);
      expect(r.refus!.motif, contains('code 3'));
      expect(r.refus!.motif, contains('données de langue absentes'));
    }, skip: posix ? false : 'POSIX seulement');
    test('une commande absente du poste : MOTEUR_ABSENT nommé, jamais un texte vide', () async {
      final r = await ocrLireFichier(moteur: MoteurOcrCommande('/chemin/inexistant/moteur-ocr {image}'), octets: entree().octets, formatId: 'png', mime: null, langue: 'fra', delaiMs: 5000);
      expect(r.ok, isFalse);
      expect(r.refus!.code, CodeOcr.moteurAbsent);
    });
  });

  group('la ligne de commande du banc', () {
    test('sans moteur demandé, le banc REFUSE de choisir (code 2) ; avec --aide il explique', () async {
      final r = await Process.run(Platform.resolvedExecutable, ['run', 'tool/mesure_ocr.dart', '--dossier', dossier]);
      expect(r.exitCode, 2);
      expect('${r.stderr}', contains('Le banc ne choisit aucun moteur'));
      final a = await Process.run(Platform.resolvedExecutable, ['run', 'tool/mesure_ocr.dart', '--aide']);
      expect(a.exitCode, 0);
      expect('${a.stdout}', contains('--commande'));
    });
    test('un moteur factice sur le dossier synthétique : le rapport est écrit', () async {
      final sortie = Directory.systemTemp.createTempSync('sigh-cli-ocr-');
      try {
        final r = await Process.run(Platform.resolvedExecutable, ['run', 'tool/mesure_ocr.dart', '--dossier', dossier, '--sortie', sortie.path, '--moteur', 'factice-parfait,factice-sans-accents']);
        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect('${r.stdout}', contains('factice-parfait 0.1 : 3 scan(s) lu(s), 0 refusé(s), mots corrects 100.0 %'));
        expect(sortie.listSync().map((e) => e.path.split('/').last), contains(startsWith('rapport-ocr-')));
      } finally {
        sortie.deleteSync(recursive: true);
      }
    });
  });
}
