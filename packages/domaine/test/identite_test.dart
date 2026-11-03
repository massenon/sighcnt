// A1 (identité nominative) et A5 (authentification locale) : les RÈGLES, en Dart pur. Le calcul d'Argon2id est testé côté poste (il dépend du paquet
// `cryptography`) ; ici, ce qui doit pouvoir échouer sans disque ni Flutter.
import 'dart:math';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef M = Map<String, Object?>;

final auj = DateTime.utc(2026, 10, 31, 10);

void main() {
  group('Agent : l\'identité nominative', () {
    final personnel = <M>[
      {'id': 'EMP18', 'matricule': '18', 'nomComplet': 'BADO BANI A. B. Zoulehath', 'fonction': 'sage_femme', 'service': 'Maternité'},
      {'id': 'EMP10', 'matricule': '10', 'nomComplet': 'GARBA Yahouza', 'fonction': 'infirmier', 'service': 'Soins infirmiers'},
      {'id': 'EMP99', 'matricule': '99', 'nomComplet': 'INCONNU Service', 'fonction': 'medecin', 'service': 'Service Imaginaire'},
    ];
    final soignants = <M>[
      {'id': 'SOI03', 'personnelId': 'EMP18', 'qualite': 'sage_femme', 'statut': 'actif'},
    ];

    test('un compte rattaché à son dossier RH : identifiant, matricule, nom, fonction et secteur viennent du dossier', () {
      final a = agentDepuisCompte(
          {'id': 'USR018', 'identifiant': 'z.bado', 'role': 'infirmier', 'nomComplet': 'BADO BANI A. B. Zoulehath', 'employeId': 'EMP18'},
          personnel: personnel,
          soignants: soignants);
      expect(a.utilisateurId, 'USR018');
      expect(a.matricule, '18');
      expect(a.fonction, 'sage_femme', reason: 'le rôle est « infirmier », la fonction métier est celle du dossier : le secteur de la sage-femme en dépend');
      expect(a.secteur, 'MAT');
      expect(a.personnelId, 'EMP18');
      expect(a.demonstration, isFalse);
    });

    test('un service qui n\'est pas dans la table n\'a pas de secteur : on ne devine pas', () {
      final a = agentDepuisCompte({'id': 'U9', 'identifiant': 'i.service', 'role': 'medecin', 'employeId': 'EMP99'}, personnel: personnel);
      expect(a.secteur, isNull);
      expect(a.fonction, 'medecin');
    });

    test('un compte sans dossier RH (administrateur, comptes à pourvoir) : ni fonction, ni secteur, ni matricule', () {
      final a = agentDepuisCompte({'id': 'USR000', 'identifiant': 'admin.systeme', 'role': 'admin', 'nomComplet': 'Administrateur système'});
      expect(a.fonction, isNull);
      expect(a.secteur, isNull);
      expect(a.matricule, '');
      expect(a.personnelId, isNull);
      expect(a.nom, 'Administrateur système');
    });

    test('la fiche du compte l\'emporte sur le service RH quand elle porte un secteur', () {
      final a = agentDepuisCompte({'id': 'U1', 'identifiant': 'x', 'role': 'infirmier', 'employeId': 'EMP10', 'secteur': 'SUR'}, personnel: personnel);
      expect(a.secteur, 'SUR');
    });

    test('deux agents de MÊME rôle sont deux personnes ; l\'identité se compare sur l\'identifiant du compte', () {
      final a = agentDepuisCompte({'id': 'USR1', 'identifiant': 'a', 'role': 'comptable', 'nomComplet': 'Pareil'});
      final b = agentDepuisCompte({'id': 'USR2', 'identifiant': 'b', 'role': 'comptable', 'nomComplet': 'Pareil'});
      expect(a.estLe(b), isFalse, reason: 'même rôle, même nom : deux comptes, deux personnes');
      expect(a.estLe(a), isTrue);
      expect(a.estLe(null), isFalse);
    });

    test('l\'agent de démonstration d\'un rôle est DÉTERMINISTE et se reconnaît', () {
      final x = agentDemonstration('comptable', nom: 'Comptable');
      final y = agentDemonstration('comptable', nom: 'Comptable');
      expect(x.utilisateurId, 'demo:comptable');
      expect(x, y);
      expect(x.demonstration, isTrue);
      expect(agentDemonstration('da').estLe(x), isFalse);
      expect(acteurDepuis(role: 'da', libelleRole: 'Directrice').nom, 'Directrice');
      expect(acteurDepuis(agent: x, role: 'da').utilisateurId, 'demo:comptable');
    });
  });

  group('clôture d\'exercice : demandeur ≠ validateur sur l\'IDENTIFIANT (B2)', () {
    // Un seul exercice demandé : on rejoue le contrôle avec une demande déjà posée.
    List<M> exercices({String? demandeParId}) => [
          {
            'annee': 2026,
            'etat': 'en_attente_cloture',
            'demandePar': 'KASSA Augustin',
            if (demandeParId != null) 'demandeParId': demandeParId,
          }
        ];

    test('le même agent ne valide pas sa propre demande, même sous un autre nom ou un autre rôle', () {
      final r = cpcValiderCloture(exercices(demandeParId: 'USR003'), const [], 2026,
          motif: 'Exercice conforme', acteur: 'Un autre libellé', acteurId: 'USR003', role: 'direction', maintenant: auj);
      expect(r.ok, isFalse);
      expect(r.motif, contains('Signer n’est pas saisir'));
    });

    test('deux agents de même NOM mais d\'identifiants différents sont deux personnes : le contrôle ne refuse pas sur le nom', () {
      final r = cpcValiderCloture(exercices(demandeParId: 'USR003'), const [], 2026,
          motif: 'Exercice conforme', acteur: 'KASSA Augustin', acteurId: 'USR777', role: 'direction', maintenant: auj);
      // Le refus éventuel vient d'ailleurs (pas d'écritures à clore), jamais de la séparation des tâches.
      expect(r.motif ?? '', isNot(contains('Signer n’est pas saisir')));
    });

    test('une demande ANTÉRIEURE sans identifiant retombe sur le nom, faute de mieux', () {
      final r = cpcValiderCloture(exercices(), const [], 2026,
          motif: 'Exercice conforme', acteur: 'KASSA Augustin', acteurId: 'USR003', role: 'direction', maintenant: auj);
      expect(r.motif, contains('Signer n’est pas saisir'));
    });
  });

  group('politique de mot de passe (E1076, E883) : APPLIQUÉE', () {
    test('une saisie qui échoue nomme les règles manquantes', () {
      expect(accRegleManquantes('court'), hasLength(3));
      expect(accRegleManquantes('motdepasseassezlong'), ['Au moins une majuscule et une minuscule', 'Au moins un chiffre et un caractère spécial']);
      expect(accRegleManquantes('Motdepasseassezlong1'), ['Au moins un chiffre et un caractère spécial']);
      expect(accRegleManquantes('Clinique#Natitingou26'), isEmpty);
    });

    test('huit caractères au minimum (Direction, 02/11/2026) : sept refusés, huit acceptés', () {
      expect(accRegleManquantes('Abcde#1'), contains('8 caractères minimum'));
      expect(accRegleManquantes('Abcdef#1'), isEmpty);
    });

    test('le mot de passe ne contient pas l\'identifiant de connexion', () {
      expect(accRegleManquantes('Xa.kassa#2026Zz', identifiant: 'a.kassa'), ['Ne doit pas contenir l’identifiant de connexion']);
      expect(accRegleManquantes('Xa.kassa#2026Zz', identifiant: 'ab'), isEmpty, reason: 'un identifiant de moins de quatre caractères ne se cherche pas');
    });

    test('le refus est une phrase qui nomme les règles ; null si conforme', () {
      expect(accRefusPolitique('a'), startsWith('Mot de passe non conforme à la politique : 8 caractères minimum'));
      expect(accRefusPolitique('Clinique#Natitingou26'), isNull);
    });

    test('le contrôle complet : concordance, politique, différent de l\'ancien', () {
      expect(accControlerNouveauMotDePasse('Clinique#Natitingou26', 'autre'), 'Les deux mots de passe ne correspondent pas.');
      expect(accControlerNouveauMotDePasse('a', 'a'), isNotNull, reason: 'la maquette acceptait « a » / « a »');
      expect(accControlerNouveauMotDePasse('Clinique#Natitingou26', 'Clinique#Natitingou26', ancien: 'Clinique#Natitingou26'),
          'Le nouveau mot de passe doit être différent de l’actuel.');
      expect(accControlerNouveauMotDePasse('Clinique#Natitingou26', 'Clinique#Natitingou26', ancien: 'Ancien#Natitingou25'), isNull);
    });

    test('les règles manquantes sont celles que la liste affichée à l\'écran contient', () {
      for (final r in accRegleManquantes('a')) {
        expect(accRegleMotDePasse, contains(r));
      }
    });
  });

  group('mot de passe provisoire du bootstrap', () {
    test('il respecte TOUJOURS la politique, sur mille tirages', () {
      final a = Random(7);
      for (var i = 0; i < 1000; i++) {
        final m = accGenererMotDePasseProvisoire(a);
        expect(m.length, 16);
        expect(accRegleManquantes(m), isEmpty, reason: m);
      }
    });

    test('il est ALÉATOIRE : deux tirages différents ne donnent pas le même mot de passe, une même graine le rejoue', () {
      expect(accGenererMotDePasseProvisoire(Random(1)), accGenererMotDePasseProvisoire(Random(1)));
      expect(accGenererMotDePasseProvisoire(Random(1)), isNot(accGenererMotDePasseProvisoire(Random(2))));
      expect(accGenererMotDePasseProvisoire(Random.secure()), isNot(accGenererMotDePasseProvisoire(Random.secure())));
    });

    test('il n\'utilise aucun caractère ambigu (0/O, 1/l/I)', () {
      final a = Random(3);
      for (var i = 0; i < 200; i++) {
        expect(RegExp(r'[0O1lI]').hasMatch(accGenererMotDePasseProvisoire(a)), isFalse);
      }
    });
  });

  group('verrou après échecs et renouvellement', () {
    FicheIdentifiant fiche() => accFicheIdentifiant(
        utilisateurId: 'USR1',
        hash: 'aGFjaGU=',
        sel: 'c2Vs',
        parametres: AccParametresHachage.tests,
        maintenant: auj,
        definiPar: 'Mise en service',
        doitChanger: true);

    test('la fiche porte le haché, le sel, les paramètres et les dates : JAMAIS le mot de passe', () {
      final f = fiche();
      expect(f.keys, containsAll(['hash', 'sel', 'memoireKio', 'iterations', 'parallelisme', 'longueur', 'algorithme', 'definiLe', 'expireLe', 'doitChanger']));
      expect(f['algorithme'], 'argon2id');
      expect(f.keys.where((k) => k.toLowerCase().contains('mot') || k.toLowerCase().contains('password')), isEmpty);
      expect(f['expireLe'], auj.add(const Duration(days: 90)).toIso8601String());
    });

    test('les paramètres d\'une fiche se relisent (un haché ancien reste vérifiable quand on durcit les paramètres)', () {
      final p = AccParametresHachage.depuisFiche(fiche());
      expect(p, AccParametresHachage.tests);
      expect(AccParametresHachage.production.memoireKio, 19456);
      expect(AccParametresHachage.depuisFiche(const {}), AccParametresHachage.production);
    });

    test('deux échecs comptent, le troisième pose le verrou pour quinze minutes et remet le compteur à zéro', () {
      var f = fiche();
      for (var i = 1; i <= 2; i++) {
        final r = accApresEchec(f, auj);
        expect(r.verrouille, isFalse);
        expect(r.patch['echecs'], i);
        f = {...f, ...r.patch};
      }
      final r3 = accApresEchec(f, auj);
      expect(r3.verrouille, isTrue);
      expect(r3.patch['echecs'], 0);
      f = {...f, ...r3.patch};
      final fin = accVerrouJusqua(f, auj)!;
      expect(fin, auj.add(const Duration(minutes: 15)));
      expect(accVerrouJusqua(f, auj.add(const Duration(minutes: 14))), isNotNull);
      expect(accVerrouJusqua(f, auj.add(const Duration(minutes: 15))), isNull, reason: 'le verrou tombe à l\'heure dite');
    });

    test('un succès remet le compteur et le verrou à zéro', () {
      final f = {...fiche(), 'echecs': 2, 'verrouJusqua': auj.add(const Duration(minutes: 5)).toIso8601String()};
      final apres = {...f, ...accApresSucces(auj)};
      expect(apres['echecs'], 0);
      expect(apres['verrouJusqua'], isNull);
      expect(accVerrouJusqua(apres, auj), isNull);
    });

    test('le changement est obligatoire si la fiche le demande OU si les 90 jours sont échus', () {
      expect(accChangementObligatoire(fiche(), auj), isTrue, reason: 'mot de passe provisoire');
      final definitif = {...fiche(), 'doitChanger': false};
      expect(accChangementObligatoire(definitif, auj), isFalse);
      expect(accChangementObligatoire(definitif, auj.add(const Duration(days: 89))), isFalse);
      expect(accChangementObligatoire(definitif, auj.add(const Duration(days: 90))), isTrue, reason: 'renouvellement tous les 90 jours');
      expect(accExpire(const {}, auj), isFalse, reason: 'sans date d\'expiration, rien ne périme');
    });

    test('le message du verrou nomme l\'heure de fin et la sortie (l\'administrateur)', () {
      final m = accMessageVerrou(DateTime(2026, 10, 31, 10, 15));
      expect(m, contains('10:15'));
      expect(m, contains('administrateur'));
      expect(m, contains('3 tentatives'));
    });
  });

  group('paie : générateur ≠ validateur sur l\'identifiant (A2 + A1)', () {
    final lot = <M>[
      {'periode': 'Mai 2026', 'genereePar': 'KASSA Augustin', 'genereeParId': 'USR003'}
    ];

    test('la même personne est refusée même sous un autre libellé', () {
      expect(paiControleSeparation(lot, 'Comptable', validateurId: 'USR003'), contains('Séparation des tâches'));
    });

    test('un homonyme (même nom, autre compte) n\'est pas la même personne', () {
      expect(paiControleSeparation(lot, 'KASSA Augustin', validateurId: 'USR777'), isNull);
    });

    test('une pièce antérieure, sans identifiant, retombe sur le nom', () {
      final ancien = <M>[
        {'periode': 'Avril 2026', 'genereePar': 'KASSA Augustin'}
      ];
      expect(paiControleSeparation(ancien, 'KASSA  Augustin', validateurId: 'USR003'), isNotNull);
      expect(paiControleSeparation(ancien, 'AUTRE Agent', validateurId: 'USR004'), isNull);
    });
  });
}
