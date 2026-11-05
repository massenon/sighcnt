import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/dossier_donnees.dart';

/// Phase A du PRD de l'installateur : les données ne vivent jamais dans le dossier d'installation.
void main() {
  group('resoudreDossierDonnees', () {
    test('Windows : %LOCALAPPDATA%\\SIGHCNT\\donnees, barre finale tolérée', () {
      expect(resoudreDossierDonnees(env: {'LOCALAPPDATA': r'C:\Users\Awa\AppData\Local'}, windows: true), r'C:\Users\Awa\AppData\Local\SIGHCNT\donnees');
      expect(resoudreDossierDonnees(env: {'LOCALAPPDATA': r'C:\Users\Awa\AppData\Local\'}, windows: true), r'C:\Users\Awa\AppData\Local\SIGHCNT\donnees');
    });
    test('SIGH_DONNEES l\'emporte, tel quel (développement, tests)', () {
      expect(resoudreDossierDonnees(surcharge: 'donnees-test', env: {'LOCALAPPDATA': r'C:\x'}, windows: true), 'donnees-test');
    });
    test('LOCALAPPDATA absent : refus NOMMÉ', () {
      expect(() => resoudreDossierDonnees(env: {}, windows: true), throwsA(isA<DossierDonneesInutilisable>().having((e) => e.motif, 'motif', contains('LOCALAPPDATA'))));
    });
    test('hors Windows : XDG_DATA_HOME, sinon HOME, sinon refus nommé', () {
      expect(resoudreDossierDonnees(env: {'XDG_DATA_HOME': '/d'}, windows: false), '/d/SIGHCNT/donnees');
      expect(resoudreDossierDonnees(env: {'HOME': '/home/a'}, windows: false), '/home/a/.local/share/SIGHCNT/donnees');
      expect(() => resoudreDossierDonnees(env: {}, windows: false), throwsA(isA<DossierDonneesInutilisable>()));
    });
  });

  group('preparerDossierDonnees', () {
    test('crée le dossier manquant et le rend utilisable', () async {
      final t = Directory.systemTemp.createTempSync('sigh-donnees');
      addTearDown(() => t.deleteSync(recursive: true));
      final chemin = '${t.path}${Platform.pathSeparator}a${Platform.pathSeparator}b';
      expect(await preparerDossierDonnees(chemin), chemin);
      expect(Directory(chemin).existsSync(), true);
      expect(File('$chemin${Platform.pathSeparator}.ecriture-ok').existsSync(), false, reason: 'la sonde d\'écriture ne laisse rien');
    });
    test('un chemin impossible est refusé en NOMMANT le chemin', () async {
      final t = Directory.systemTemp.createTempSync('sigh-donnees');
      addTearDown(() => t.deleteSync(recursive: true));
      final fichier = File('${t.path}${Platform.pathSeparator}fichier')..writeAsStringSync('x');
      final chemin = '${fichier.path}${Platform.pathSeparator}sous';
      await expectLater(preparerDossierDonnees(chemin), throwsA(isA<DossierDonneesInutilisable>().having((e) => e.motif, 'motif', contains(chemin))));
    });
  });
}
