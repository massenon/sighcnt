import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

/// Règles de la console du poste mère, lot (b). Les listes fermées (champs publiés, essentiels du moteur) sont rejouées CONTRE les sources du moteur :
/// si `pont.dart` ou `mere.dart` changent, ce test échoue avant que l'écran ne mente.
void main() {
  const h = 3600 * 1000;
  const maintenant = 1000 * h;

  MrbLigneJournal l(int il, String niveau, [String message = 'm']) =>
      MrbLigneJournal(quand: maintenant - il, niveau: niveau, source: 's', message: message);

  group('journal technique', () {
    test('seules les 24 dernières heures comptent, par niveau', () {
      final c = mrbCompterJournal([
        l(1 * h, 'info'),
        l(2 * h, 'alerte'),
        l(3 * h, 'erreur'),
        l(23 * h, 'erreur'),
        l(25 * h, 'erreur'), // hors fenêtre
      ], maintenantMs: maintenant, limite: 500);
      expect((c.evenements, c.alertes, c.erreurs, c.tronque), (4, 1, 2, false));
    });

    test('lecture tronquée dans la fenêtre : le compte est un minimum et le dit', () {
      final lignes = [for (var i = 1; i <= 5; i++) l(i * 1000, 'info')];
      expect(mrbCompterJournal(lignes, maintenantMs: maintenant, limite: 5).tronque, isTrue);
      // La plus ancienne est hors fenêtre : le journal lu couvre toute la fenêtre, le compte est complet.
      expect(mrbCompterJournal([...lignes, l(30 * h, 'info')], maintenantMs: maintenant, limite: 6).tronque, isFalse);
      expect(mrbCompterJournal([], maintenantMs: maintenant, limite: 5).tronque, isFalse);
    });
  });

  group('intégrité', () {
    test('causes nommées, type inconnu non reformulé', () {
      expect(mrbCauseAlteration('authentification'), contains('altérée'));
      expect(mrbCauseAlteration('trou'), contains('manquante'));
      expect(mrbCauseAlteration('autre'), isNull);
    });

    test('le rang vient du moteur : n pour une altération, attendu/reçu pour un trou', () {
      expect(mrbRangAlteration({'type': 'authentification', 'n': 4}), '4');
      expect(mrbRangAlteration({'type': 'trou', 'attendu': 3, 'recu': 5}), 'attendu 3, reçu 5');
      expect(mrbRangAlteration({'type': 'authentification'}), isNull);
      expect(mrbRangAlteration({'type': 'appareil_inconnu'}), isNull);
    });

    test('le compte 30 jours lit les messages du moteur, pas un autre niveau', () {
      final c = mrbCompterAlterations([
        l(1 * h, 'alerte', 'Alerte authentification (appareil u1)'),
        l(2 * h, 'alerte', 'Alerte trou (appareil u1)'),
        l(3 * h, 'alerte', 'Alerte trou (appareil u2)'),
        l(4 * h, 'info', 'Alerte trou (appareil u3)'), // niveau info : pas une alerte
        l(31 * 24 * h, 'alerte', 'Alerte trou (appareil u4)'), // hors 30 jours
        l(5 * h, 'alerte', 'Alerte revocation_relais_differee (appareil u5)'),
      ], maintenantMs: maintenant);
      expect((c.alterees, c.trous), (1, 2));
    });
  });

  group('clé de clinique', () {
    test('seule une vraie empreinte SHA-256 donne 8 caractères', () {
      final hex = 'ab12cd34' * 8;
      expect(mrbEmpreinteCourte(hex), 'AB12CD34');
      expect(mrbEmpreinteCourte(hex.toUpperCase()), 'AB12CD34');
      expect(mrbEmpreinteCourte('Y2xlLWRlLWNsaW5pcXVl'), isNull, reason: 'une clé Base64 n’est pas une empreinte : jamais affichée');
      expect(mrbEmpreinteCourte('ab12'), isNull);
      expect(mrbEmpreinteCourte(null), isNull);
    });

    test('le QR porte le code et la clé ; mrbSansCle retire la clé de tout message', () {
      const cle = 'Y2xlLWRlLWNsaW5pcXVlLTAxMjM0NTY3ODk=';
      final p = mrbPayloadQrMobile(code: 'ABCD2345', cleBase64: cle);
      expect(p, contains('ABCD2345'));
      expect(p, contains(cle));
      expect(mrbSansCle('Erreur sur $p', cle), isNot(contains(cle)));
      expect(mrbSansCle('Erreur sur $p', cle), contains('[clé masquée]'));
      expect(mrbSansCle('rien', null), 'rien');
    });

    test('l’attestation nomme détenteur, scellé et contrôleur', () {
      expect(mrbChampsAttestationManquants(), ['Détenteur', 'Scellé n°', 'Contrôlé par']);
      expect(mrbChampsAttestationManquants(detenteur: 'Mme X', scelle: '  ', controlePar: 'M. Y'), ['Scellé n°']);
      expect(mrbChampsAttestationManquants(detenteur: 'a', scelle: 'b', controlePar: 'c'), isEmpty);
    });
  });

  group('réinitialisation de production', () {
    MrbRefus? refus({
      bool droit = true,
      bool fenetre = true,
      String confirmation = 'NASSIERA TOO',
      String second = 'Mme DAF',
      String auteur = 'Admin',
    }) =>
        mrbRefusReinit(
            droitAnnuler: droit, fenetreOuverte: fenetre, confirmation: confirmation, nomClinique: 'NASSIERA TOO', second: second, auteur: auteur);

    test('chaque garde refuse en se nommant, dans l’ordre', () {
      expect(refus(droit: false)!.code, 'droit_refuse');
      expect(refus(fenetre: false)!.code, 'reinit_fermee');
      expect(refus(confirmation: 'nassiera')!.code, 'confirmation_invalide');
      expect(refus(confirmation: '')!.code, 'confirmation_invalide');
      expect(refus(second: '  ')!.code, 'second_profil_requis');
      expect(refus(second: 'admin')!.code, 'second_profil_identique');
      expect(refus(), isNull);
    });

    test('un nom de clinique vide ne se confirme jamais par une saisie vide', () {
      expect(mrbRefusReinit(droitAnnuler: true, fenetreOuverte: true, confirmation: '', nomClinique: '', second: 'x', auteur: 'y')!.code,
          'confirmation_invalide');
    });

    test('la fenêtre dure 30 minutes et s’éteint à zéro', () {
      final t0 = DateTime(2026, 10, 31, 10);
      expect(mrbFenetreRestante(ouverteLe: t0, maintenant: t0.add(const Duration(minutes: 10))), const Duration(minutes: 20));
      expect(mrbFenetreRestante(ouverteLe: t0, maintenant: t0.add(const Duration(minutes: 31))), Duration.zero);
      expect(mrbFenetreRestante(ouverteLe: null, maintenant: t0), isNull, reason: 'ouverture inconnue : pas de reste inventé');
    });

    test('les essentiels du moteur sont ceux de mere.dart', () {
      final src = File('../sync_dart/lib/src/mere.dart').readAsStringSync();
      final m = RegExp(r"const essentielles = \{([^}]*)\};").firstMatch(src)!;
      final dansMoteur = RegExp(r"'(\w+)'").allMatches(m.group(1)!).map((x) => x.group(1)!).toList();
      expect(mrbEssentielsMoteur, dansMoteur);
    });
  });

  group('indicateurs publiés et opacité du relais', () {
    test('la liste fermée est exactement celle que le moteur publie (pont.dart)', () {
      final src = File('../sync_dart/lib/src/pont.dart').readAsStringSync();
      final bloc = RegExp(r"'/mere/indicateurs'.*?\}\s*,\s*\}\)", dotAll: true).firstMatch(src)!.group(0)!;
      final cles = RegExp(r"'(\w+)':").allMatches(bloc).map((x) => x.group(1)!).where((k) => k != 'indicateurs').toList();
      expect(mrbChampsPublies, cles);
    });

    test('un champ hors liste ou une valeur textuelle (un nom) est refusé', () {
      expect(mrbVerifierIndicateurs({'patients_actifs': 12, 'seq_max': 5, 'retard_replication': 0}).sansDonneeDeSante, isTrue);
      final v = mrbVerifierIndicateurs({'patients_actifs': 'KOUASSI Awa', 'nom': 'x'});
      expect(v.sansDonneeDeSante, isFalse);
      expect(v.horsListe, ['nom']);
      expect(v.nonNumeriques, ['patients_actifs', 'nom']);
    });

    test('opacité : une enveloppe chiffrée passe, un champ en clair ou un nom de collection non', () {
      final bonne = {
        'enveloppe': {'id': 'journal-1', 'appareil': 'mere', 'dir': 'journal', 'n': 1, 'nonce': 'AAAAAAAAAAAAAAAA', 'ct': 'QUJDREVGR0g='}
      };
      expect(mrbDefautsOpacite(bonne, interdits: ['patients', 'KOUASSI']), isEmpty);
      final mauvaise = {
        'enveloppe': {'id': 'x', 'appareil': 'mere', 'dir': 'journal', 'n': 1, 'nonce': 'AAAA', 'ct': 'pas du base64 !', 'collection': 'patients'}
      };
      final d = mrbDefautsOpacite(mauvaise, interdits: ['patients']);
      expect(d, contains('champ en clair : collection'));
      expect(d, contains('ct n’est pas du Base64'));
      expect(d.any((x) => x.contains('patients')), isTrue);
      expect(mrbDefautsOpacite({}), ['pas d’enveloppe']);
    });

    test('sens des échanges', () {
      expect(mrbLibelleSens('depot'), 'Mère vers relais');
      expect(mrbLibelleSens('releve'), 'Relais vers mère');
      expect(mrbLibelleSens('autre'), 'autre');
    });
  });
}
