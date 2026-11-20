import 'dart:math';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime(2026, 11, 2, 9);

  group('code de secours', () {
    test('25 caractères, alphabet sans ambiguïté, aléa injecté rejouable', () {
      final a = accGenererCodeSecours(Random(7));
      final b = accGenererCodeSecours(Random(7));
      expect(a, b);
      expect(a.length, accLongueurCodeSecours);
      expect(a.split('').every(accAlphabetCodeSecours.contains), isTrue);
      for (final interdit in ['0', 'O', '1', 'I', 'L']) {
        expect(accAlphabetCodeSecours.contains(interdit), isFalse, reason: interdit);
      }
      expect(accGenererCodeSecours(Random(8)), isNot(a));
    });

    test('l’affichage groupe par cinq et la saisie se normalise (casse, espaces, tirets)', () {
      final c = accGenererCodeSecours(Random(1));
      final f = accFormaterCodeSecours(c);
      expect(f.split('-').length, 5);
      expect(f.split('-').every((g) => g.length == 5), isTrue);
      expect(accNormaliserCodeSecours(f.toLowerCase().replaceAll('-', ' ')), c);
      expect(accCodeSecoursBienForme(f), isTrue);
      expect(accCodeSecoursBienForme('ABC'), isFalse);
      expect(accCodeSecoursBienForme('${c.substring(0, 24)}0'), isFalse, reason: 'le zéro n’est pas dans l’alphabet');
    });

    test('la fiche ne porte pas le code ; un code consommé n’est plus utilisable', () {
      final code = accGenererCodeSecours(Random(2));
      final f = accFicheSecours(
          utilisateurId: 'U1', hash: 'aGFjaGU=', sel: 'c2Vs', parametres: AccParametresHachage.tests, maintenant: t0, creePar: 'Installation initiale');
      expect(f.values.map((v) => '$v').any((v) => v.contains(code)), isFalse);
      expect(accSecoursUtilisable(f), isTrue);
      expect(accSecoursUtilisable({...f, 'consommeLe': t0.toIso8601String()}), isFalse);
      expect(accSecoursUtilisable(null), isFalse);
    });

    test('seul un administrateur peut s’en servir', () {
      expect(accSecoursPourRole('admin'), isTrue);
      for (final r in ['medecin', 'da', 'comptable', 'direction', 'caissier']) {
        expect(accSecoursPourRole(r), isFalse, reason: r);
      }
    });
  });

  group('blocage du chemin de récupération', () {
    test('quatre essais faux ne bloquent pas, le cinquième bloque quinze minutes', () {
      var etat = accSecoursApresSucces();
      for (var i = 1; i <= 4; i++) {
        final r = accSecoursApresEchec(etat, t0);
        expect(r.bloque, isFalse);
        etat = {...etat, ...r.patch};
        expect(accSecoursBloqueJusqua(etat, t0), isNull);
      }
      final r = accSecoursApresEchec(etat, t0);
      expect(r.bloque, isTrue);
      etat = {...etat, ...r.patch};
      expect(accSecoursBloqueJusqua(etat, t0.add(const Duration(minutes: 14))), t0.add(accDureeBlocageSecours));
      expect(accSecoursBloqueJusqua(etat, t0.add(const Duration(minutes: 15))), isNull, reason: 'le blocage se lève à l’échéance');
      expect(etat['essais'], 0, reason: 'un blocage levé donne droit à un nouvel essai complet');
    });

    test('un succès remet le compteur à zéro ; le message de refus est unique', () {
      final r = accSecoursApresEchec({'essais': 3}, t0);
      expect(r.patch['essais'], 4);
      expect(accSecoursApresSucces()['essais'], 0);
      expect(accMessageSecoursRefus, isNot(contains('inconnu')));
      expect(accMessageSecoursRefus, isNot(contains('existe')));
    });
  });

  group('réinitialisation par un administrateur', () {
    test('mot de passe temporaire : 14 caractères, conforme à la politique, valable 24 h', () {
      for (var s = 0; s < 40; s++) {
        final m = accGenererMotDePasseTemporaire(Random(s));
        expect(m.length, 14);
        expect(accRegleManquantes(m), isEmpty, reason: m);
      }
      expect(accEcheanceTemporaire(t0), t0.add(const Duration(hours: 24)));
      expect(accTemporairePerime({'temporaireJusqua': accEcheanceTemporaire(t0).toIso8601String()}, t0.add(const Duration(hours: 23))), isFalse);
      expect(accTemporairePerime({'temporaireJusqua': accEcheanceTemporaire(t0).toIso8601String()}, t0.add(const Duration(hours: 24))), isTrue);
      expect(accTemporairePerime({}, t0), isFalse, reason: 'un mot de passe ordinaire ne périme pas ici');
    });

    test('qui peut réinitialiser : refus nommés', () {
      expect(accRefusReinitialisation(acteurRole: 'admin', acteurId: 'A', cibleId: 'B'), isNull);
      expect(accRefusReinitialisation(acteurRole: 'medecin', acteurId: 'M', cibleId: 'B')!.code, 'reinit_non_admin');
      final soi = accRefusReinitialisation(acteurRole: 'admin', acteurId: 'A', cibleId: 'A')!;
      expect(soi.code, 'reinit_propre_compte');
      expect(soi.geste, contains('code de secours'));
      expect(accRefusReinitialisation(acteurRole: 'admin', acteurId: 'A', cibleId: 'S', cibleSuper: true)!.code, 'reinit_super_admin');
      expect(accRefusReinitialisation(acteurRole: 'admin', acteurId: 'S1', cibleId: 'S2', acteurSuper: true, cibleSuper: true), isNull);
    });

    test('le nouveau mot de passe diffère du temporaire et de l’ancien', () {
      const bon = 'Nouveau-Mdp#2026';
      expect(accControlerMotDePasseApresReinit(bon, bon, ancien: 'Ancien-Mdp#2025', temporaire: 'Temp-Mdp#9999'), isNull);
      expect(accControlerMotDePasseApresReinit(bon, bon, temporaire: bon), contains('temporaire'));
      expect(accControlerMotDePasseApresReinit(bon, bon, ancien: bon), contains('actuel'));
      expect(accControlerMotDePasseApresReinit(bon, 'autre'), contains('ne correspondent pas'));
      expect(accControlerMotDePasseApresReinit('court', 'court'), contains('non conforme'));
    });
  });
}
