import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/etat_installation.dart';
import 'package:sigh_poste/core/parametres_poste.dart';

void main() {
  final t0 = DateTime(2026, 11, 2, 9);

  group('phases', () {
    test('un poste jamais installé est non installé, puis en cours, puis clos', () {
      var e = EtatInstallation.vide;
      expect(e.phase, PhaseInstallation.nonInstalle);
      e = e.creer(maintenant: t0, par: 'admin');
      expect(e.phase, PhaseInstallation.enCours);
      e = e.cloturer(maintenant: t0.add(const Duration(days: 1)), par: 'admin');
      expect(e.phase, PhaseInstallation.cloturee);
      expect(e.cloturePar, 'admin');
    });

    test('poste vide : seulement sans installation ET sans compte', () {
      expect(posteVide(EtatInstallation.vide, nombreComptes: 0), isTrue);
      expect(posteVide(EtatInstallation.vide, nombreComptes: 3), isFalse, reason: 'un poste qui porte déjà des comptes garde son chemin');
      expect(posteVide(EtatInstallation.vide.creer(maintenant: t0, par: 'a'), nombreComptes: 0), isFalse);
    });
  });

  group('étapes', () {
    test('les quatre étapes sont à faire au départ, rien n’est verrouillé que la mère ne règle', () {
      final e = EtatInstallation.vide.creer(maintenant: t0, par: 'a');
      for (final s in etapesInstallation) {
        expect(e.etat(s), EtapeEtat.aFaire);
      }
      expect(e.motifVerrou('mere'), isNull);
      for (final s in ['configurations', 'comptes', 'appairages']) {
        expect(e.motifVerrou(s), contains('Activer d’abord la mère'), reason: s);
      }
    });

    test('la mère reportée (relais injoignable) déverrouille les autres étapes ; elle n’est pas « faite »', () {
      final e = EtatInstallation.vide.creer(maintenant: t0, par: 'a').marquer('mere', EtapeEtat.reportee);
      expect(e.mereReglee, isTrue);
      expect(e.motifVerrou('configurations'), isNull);
      expect(e.toutesFaites, isFalse);
      expect(e.nombreFaites, 0);
    });

    test('toutes faites : quatre sur quatre', () {
      var e = EtatInstallation.vide.creer(maintenant: t0, par: 'a');
      for (final s in etapesInstallation) {
        e = e.marquer(s, EtapeEtat.faite);
      }
      expect(e.toutesFaites, isTrue);
      expect(e.nombreFaites, 4);
      expect(e.marquer('comptes', EtapeEtat.aFaire).toutesFaites, isFalse, reason: 'on peut rouvrir une étape');
    });

    test('une étape inconnue est refusée', () {
      expect(() => EtatInstallation.vide.marquer('mer', EtapeEtat.faite), throwsArgumentError);
    });
  });

  group('persistance dans les paramètres du poste', () {
    test('aller-retour JSON, et un fichier d’avant l’assistant donne l’état vide', () {
      final e = EtatInstallation.vide.creer(maintenant: t0, par: 'admin').marquer('mere', EtapeEtat.faite).marquer('comptes', EtapeEtat.reportee);
      final p = ParametresPoste(uuidPoste: 'u1', mode: ModePoste.mere, installation: e);
      final relu = ParametresPoste.depuisJson(p.toJson());
      expect(relu.installation.phase, PhaseInstallation.enCours);
      expect(relu.installation.etat('mere'), EtapeEtat.faite);
      expect(relu.installation.etat('comptes'), EtapeEtat.reportee);
      expect(relu.installation.creePar, 'admin');
      final ancien = ParametresPoste.depuisJson({'uuid_poste': 'u0', 'mode': 'fileul'});
      expect(ancien.installation.phase, PhaseInstallation.nonInstalle);
      expect(ancien.installation.etapes, isEmpty);
    });

    test('avec() conserve l’installation ; les clés inconnues sont ignorées à la relecture', () {
      final p = ParametresPoste(uuidPoste: 'u1', installation: EtatInstallation.vide.creer(maintenant: t0, par: 'a'));
      expect(p.avec(nomPoste: 'Caisse').installation.phase, PhaseInstallation.enCours);
      final e = EtatInstallation.depuisJson({'cree_le': t0.toIso8601String(), 'etapes': {'mere': 'faite', 'fantome': 'faite'}});
      expect(e.etapes.keys, ['mere']);
    });

    test('le stockage fichier écrit et relit l’état (écriture atomique conservée)', () async {
      final d = await Directory.systemTemp.createTemp('inst');
      addTearDown(() => d.delete(recursive: true));
      final s = StockageFichier('${d.path}/poste.json');
      await s.ecrire(ParametresPoste(uuidPoste: 'u1', installation: EtatInstallation.vide.creer(maintenant: t0, par: 'a').marquer('mere', EtapeEtat.faite)));
      final relu = await s.lire();
      expect(relu!.installation.etat('mere'), EtapeEtat.faite);
      expect(File('${d.path}/poste.json.tmp').existsSync(), isFalse);
    });
  });
}
