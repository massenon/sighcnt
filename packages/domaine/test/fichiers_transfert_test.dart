// Le transfert d'un fichier par morceaux avec reprise (EF-SYNC-18) et l'état d'un fichier au poste : règles PURES, sans disque ni réseau.
import 'dart:typed_data';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

Uint8List fichier(int n) => Uint8List.fromList([for (var i = 0; i < n; i++) (i * 7 + (i >> 8)) & 255]);

void main() {
  group('plan des morceaux', () {
    test('découpage exact, dernier morceau plus court, fichier vide sans morceau', () {
      const p = PlanMorceaux(1000, 300);
      expect(p.nombre, 4);
      expect([for (var i = 0; i < 4; i++) p.longueur(i)], [300, 300, 300, 100]);
      expect(p.debut(3), 900);
      expect(p.fin(3), 1000);
      expect(const PlanMorceaux(0).nombre, 0);
      expect(const PlanMorceaux(fichierTailleMorceau).nombre, 1);
      expect(const PlanMorceaux(fichierTailleMorceau + 1).nombre, 2);
    });
  });

  group('description et incohérences', () {
    test('une description valide ne dit rien, une description incohérente est refusée en nommant', () {
      final b = fichier(5000);
      final d = DescriptionFichier.deOctets(b, 2048);
      expect(d.incoherence(), isNull);
      expect(d.morceaux.length, 3);
      expect(DescriptionFichier(sha256: 'zz', taille: 10, tailleMorceau: 2048, morceaux: const []).incoherence()!.code, 'EMPREINTE_INVALIDE');
      expect(DescriptionFichier(sha256: d.sha256, taille: 0, tailleMorceau: 2048, morceaux: const []).incoherence()!.code, 'FICHIER_VIDE');
      expect(DescriptionFichier(sha256: d.sha256, taille: 5000, tailleMorceau: 10, morceaux: d.morceaux).incoherence()!.code, 'PLAN_INVALIDE');
      expect(DescriptionFichier(sha256: d.sha256, taille: 5000, tailleMorceau: 2048, morceaux: d.morceaux.sublist(1)).incoherence()!.code, 'PLAN_INVALIDE');
      expect(DescriptionFichier(sha256: d.sha256, taille: 5000, tailleMorceau: 2048, morceaux: [...d.morceaux.sublist(1), 'xyz']).incoherence()!.code, 'PLAN_INVALIDE');
      expect(DescriptionFichier(sha256: d.sha256, taille: 5000, tailleMorceau: 2048, morceaux: d.morceaux).incoherence(tailleMax: 4000)!.code, 'TAILLE_DEPASSEE');
    });
    test('aller-retour JSON', () {
      final d = DescriptionFichier.deOctets(fichier(5000), 2048);
      final r = DescriptionFichier.depuisJson(d.toJson());
      expect(r.sha256, d.sha256);
      expect(r.morceaux, d.morceaux);
      expect(r.taille, 5000);
      expect(r.tailleMorceau, 2048);
    });
  });

  group('réception avec reprise', () {
    final b = fichier(10000);
    final d = DescriptionFichier.deOctets(b, 2048);
    Uint8List morceau(int i) => Uint8List.sublistView(b, d.plan.debut(i), d.plan.fin(i));

    test('tous les morceaux vérifiés, puis l’ensemble : le fichier est complet et rangeable', () {
      final r = ReceptionFichier(d);
      expect(r.manquants, [0, 1, 2, 3, 4]);
      for (var i = 0; i < 5; i++) {
        expect(r.accepter(i, morceau(i)), isNull);
      }
      expect(r.complet, isTrue);
      expect(r.manquants, isEmpty);
      expect(r.verifierEnsemble(b), isNull);
    });
    test('un morceau altéré est refusé et RENVOYÉ : il ne compte pas comme reçu', () {
      final r = ReceptionFichier(d);
      final m = Uint8List.fromList(morceau(1))..[100] ^= 1;
      final refus = r.accepter(1, m)!;
      expect(refus.code, 'MORCEAU_ALTERE');
      expect(refus.plus['morceau'], 1);
      expect(r.verifies, isEmpty);
      expect(r.accepter(1, morceau(1)), isNull);
      expect(r.verifies, {1});
    });
    test('un morceau tronqué ou en trop est refusé, un rang hors plan aussi', () {
      final r = ReceptionFichier(d);
      expect(r.accepter(0, morceau(0).sublist(1))!.code, 'MORCEAU_ALTERE');
      expect(r.accepter(0, Uint8List.fromList([...morceau(0), 0]))!.code, 'MORCEAU_ALTERE');
      expect(r.accepter(5, morceau(0))!.code, 'MORCEAU_HORS_PLAN');
      expect(r.accepter(-1, morceau(0))!.code, 'MORCEAU_HORS_PLAN');
      expect(r.accepter(0, morceau(1))!.code, 'MORCEAU_ALTERE', reason: 'un morceau valide à la mauvaise place n’est pas accepté');
    });
    test('REPRISE : un transfert coupé repart du premier morceau manquant, sans refaire les morceaux vérifiés', () {
      final avant = ReceptionFichier(d)..accepter(0, morceau(0))..accepter(1, morceau(1));
      final reprise = ReceptionFichier(d, deja: avant.verifies);
      expect(reprise.manquants, [2, 3, 4]);
      for (final i in reprise.manquants) {
        expect(reprise.accepter(i, morceau(i)), isNull);
      }
      expect(reprise.complet, isTrue);
    });
    test('IDEMPOTENCE : un morceau reçu deux fois ne change rien', () {
      final r = ReceptionFichier(d);
      expect(r.accepter(2, morceau(2)), isNull);
      expect(r.accepter(2, morceau(2)), isNull);
      expect(r.verifies, {2});
      expect(r.manquants, [0, 1, 3, 4]);
    });
    test('l’ensemble est vérifié avant de ranger : des morceaux justes assemblés dans le mauvais ordre sont refusés', () {
      final r = ReceptionFichier(d);
      final faux = Uint8List.fromList([...morceau(1), ...morceau(0), ...morceau(2), ...morceau(3), ...morceau(4)]);
      expect(r.verifierEnsemble(faux)!.code, 'EMPREINTE_DIVERGENTE');
      expect(r.verifierEnsemble(Uint8List.sublistView(b, 0, 9999))!.code, 'EMPREINTE_DIVERGENTE');
    });
    test('une description mensongère (empreinte d’ensemble fausse) est détectée à l’assemblage', () {
      final menteuse = DescriptionFichier(sha256: sha256Octets(fichier(10001)), taille: d.taille, tailleMorceau: d.tailleMorceau, morceaux: d.morceaux);
      final r = ReceptionFichier(menteuse);
      for (var i = 0; i < 5; i++) {
        expect(r.accepter(i, morceau(i)), isNull);
      }
      expect(r.verifierEnsemble(b)!.code, 'EMPREINTE_DIVERGENTE');
    });
  });

  group('état d’un fichier au poste (EF-SYNC-17 : jamais un écran vide)', () {
    EtatFichierPoste e({bool ref = true, bool? copie, bool mere = true, bool zone = true}) =>
        fichierEtatPoste(referenceParFiche: ref, copieLocale: copie, mereJoignable: mere, zoneAutorisee: zone);
    test('présent, altéré, en cours de transfert, non disponible hors ligne, sans fichier, zone refusée', () {
      expect(e(copie: true), EtatFichierPoste.present);
      expect(e(copie: false), EtatFichierPoste.altere);
      expect(e(), EtatFichierPoste.enCoursDeTransfert, reason: 'mère joignable, fichier pas encore arrivé : le poste vient le chercher');
      expect(e(mere: false), EtatFichierPoste.nonDisponibleHorsLigne);
      expect(e(ref: false), EtatFichierPoste.sansFichier);
      expect(e(zone: false, copie: true), EtatFichierPoste.zoneRefusee, reason: 'la zone décide avant la copie locale (RG-13)');
    });
    test('chaque état a un libellé qui dit quoi faire', () {
      for (final s in EtatFichierPoste.values) {
        expect(fichierLibelleEtatPoste(s, sha: 'ab' * 32), isNotEmpty);
      }
      expect(fichierLibelleEtatPoste(EtatFichierPoste.nonDisponibleHorsLigne, sha: 'ab' * 32), contains('non disponible hors ligne'));
      expect(fichierLibelleEtatPoste(EtatFichierPoste.enCoursDeTransfert, sha: 'ab' * 32), contains('en cours de transfert'));
    });
  });
}
