import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/etat_installation.dart';
import 'package:sigh_poste/core/identifiants.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/core/service_installation.dart';
import 'package:sigh_poste/donnees/magasin.dart';

/// PLAN étapes 3 et 4 : le premier compte, son code de secours et la récupération, au niveau du SERVICE (sans écran). Les écrans : `installation_ecrans_test.dart`.
final auj = DateTime(2026, 11, 2, 9);
const bon = 'Clinique#Natitingou26';

Magasin magasin() => Magasin({
      'utilisateurs': [
        {'id': 'USR000', 'statut': 'actif', 'identifiant': 'admin.systeme', 'nomComplet': 'Administrateur système', 'role': 'admin'},
        {'id': 'USR001', 'statut': 'actif', 'identifiant': 'f.yeni', 'nomComplet': 'YENI Florent', 'role': 'medecin'},
      ],
    });

Future<(Magasin, ServiceInstallation)> poste({EtatInstallation? etat}) async {
  final m = magasin();
  final s = ServiceInstallation.de(m);
  await s.attacher(StockageMemoire(), ParametresPoste(uuidPoste: 'u', installation: etat ?? EtatInstallation.vide));
  return (m, s);
}

void main() {
  setUp(() => ServiceIdentifiants.parametres = AccParametresHachage.tests);
  tearDown(() => ServiceIdentifiants.parametres = AccParametresHachage.production);

  group('détection du poste vide', () {
    test('non attaché : inactif, le poste garde son chemin', () {
      final s = ServiceInstallation.de(magasin());
      expect(s.actif, isFalse);
      expect(s.propose(), isFalse);
    });

    test('attaché, sans mot de passe défini (les comptes du jeu ne se connectent pas) : l’assistant est proposé', () async {
      final (_, s) = await poste();
      expect(s.comptesConnectables(), 0);
      expect(s.propose(), isTrue);
    });

    test('dès qu’un compte a un mot de passe, l’assistant n’est plus proposé', () async {
      final (m, s) = await poste();
      await ServiceIdentifiants.de(m).definir('USR001', bon, par: 'test', doitChanger: false, maintenant: auj);
      expect(s.propose(), isFalse);
    });
  });

  group('création du premier administrateur', () {
    test('le compte, le haché et le code de secours naissent ; le mot de passe n’est écrit nulle part', () async {
      final (m, s) = await poste();
      final r = await s.creerPremierAdministrateur(identifiant: 'k.adjovi', nom: 'ADJOVI Koffi', motDePasse: bon, confirmation: bon, maintenant: auj);
      expect(r.ok, isTrue, reason: r.message);
      expect(r.compte!.role, 'admin');
      expect(accFormaterCodeSecours(r.codeSecours!).length, 29, reason: '25 caractères en cinq groupes');
      final u = m.collection('utilisateurs').toutes.firstWhere((x) => x['identifiant'] == 'k.adjovi');
      expect(u['role'], 'admin');
      expect(await ServiceIdentifiants.de(m).motDePasseActuel('${u['id']}', bon), isTrue);
      final partout = [
        for (final n in ['utilisateurs', 'identifiants', 'codesSecours', 'audit']) ...m.collection(n).toutes.map((f) => f.toString())
      ].join('\n');
      expect(partout, isNot(contains(bon)), reason: 'jamais le mot de passe');
      expect(partout, isNot(contains(accNormaliserCodeSecours(r.codeSecours!))), reason: 'jamais le code de secours');
      expect(m.collection('audit').toutes.map((f) => f['action']), contains('Installation initiale'));
      expect(s.etat.phase, PhaseInstallation.enCours);
      expect(s.propose(), isFalse, reason: 'l’assistant ne se rouvre pas en boucle');
    });

    test('refus nommés, rien n’est écrit', () async {
      final (m, s) = await poste();
      Future<String?> essai(String id, String nom, String a, String b) async =>
          (await s.creerPremierAdministrateur(identifiant: id, nom: nom, motDePasse: a, confirmation: b, maintenant: auj)).message;
      expect(await essai('', 'X Y', bon, bon), contains('obligatoire'));
      expect(await essai('AB', 'X Y', bon, bon), contains('invalide'));
      expect(await essai('Prénom Nom', 'X Y', bon, bon), contains('invalide'));
      expect(await essai('admin.systeme', 'X Y', bon, bon), contains('existe déjà'));
      expect(await essai('k.adjovi', ' ', bon, bon), contains('nom complet'));
      expect(await essai('k.adjovi', 'X Y', bon, 'autre'), contains('ne correspondent pas'));
      expect(await essai('k.adjovi', 'X Y', 'court', 'court'), contains('non conforme'));
      expect(m.collection('identifiants').toutes, isEmpty);
      expect(m.collection('utilisateurs').toutes.length, 2);
      expect(s.etat.phase, PhaseInstallation.nonInstalle);
    });
  });

  group('code de secours', () {
    Future<(Magasin, ServiceInstallation, String, String)> installe() async {
      final (m, s) = await poste();
      final r = await s.creerPremierAdministrateur(identifiant: 'k.adjovi', nom: 'ADJOVI Koffi', motDePasse: bon, confirmation: bon, maintenant: auj);
      return (m, s, '${m.collection('utilisateurs').toutes.firstWhere((x) => x['identifiant'] == 'k.adjovi')['id']}', r.codeSecours!);
    }

    const nouveau = 'Autre#Mot2Passe9';

    test('le bon code remplace le mot de passe, est consommé, et un nouveau code est rendu', () async {
      final (m, _, id, code) = await installe();
      final ident = ServiceIdentifiants.de(m);
      final r = await ident.recuperer(identifiant: 'k.adjovi', code: code.toLowerCase().replaceAll('-', ' '), nouveau: nouveau, confirmation: nouveau, maintenant: auj);
      expect(r.ok, isTrue, reason: r.message);
      expect(await ident.motDePasseActuel(id, nouveau), isTrue);
      expect(await ident.motDePasseActuel(id, bon), isFalse);
      expect(r.nouveauCode, isNot(code));
      // L'ancien code est consommé : il ne se rejoue pas.
      final rejeu = await ident.recuperer(identifiant: 'k.adjovi', code: code, nouveau: 'Encore#Un2Autre9', confirmation: 'Encore#Un2Autre9', maintenant: auj);
      expect(rejeu.ok, isFalse);
      expect(rejeu.message, accMessageSecoursRefus);
      // Le nouveau code, lui, vaut.
      final suite = await ident.recuperer(identifiant: 'k.adjovi', code: r.nouveauCode!, nouveau: 'Encore#Un2Autre9', confirmation: 'Encore#Un2Autre9', maintenant: auj);
      expect(suite.ok, isTrue);
    });

    test('même message pour identifiant inconnu, mauvais code et compte non administrateur', () async {
      final (m, _, _, code) = await installe();
      final ident = ServiceIdentifiants.de(m);
      final inconnu = await ident.recuperer(identifiant: 'fantome', code: code, nouveau: nouveau, confirmation: nouveau, maintenant: auj);
      final faux = await ident.recuperer(identifiant: 'k.adjovi', code: 'AAAAA-BBBBB-CCCCC-DDDDD-EEEEE', nouveau: nouveau, confirmation: nouveau, maintenant: auj);
      final medecin = await ident.recuperer(identifiant: 'f.yeni', code: code, nouveau: nouveau, confirmation: nouveau, maintenant: auj);
      for (final r in [inconnu, faux, medecin]) {
        expect(r.ok, isFalse);
        expect(r.message, accMessageSecoursRefus);
      }
      expect(m.collection('tentativesConnexion').toutes.length, 3, reason: 'chaque essai faux est écrit (RG-12)');
    });

    test('cinq essais faux bloquent le chemin quinze minutes, même avec le bon code', () async {
      final (m, _, id, code) = await installe();
      final ident = ServiceIdentifiants.de(m);
      ResultatSecours? dernier;
      for (var i = 0; i < 5; i++) {
        dernier = await ident.recuperer(identifiant: 'k.adjovi', code: 'AAAAA-BBBBB-CCCCC-DDDDD-EEEEE', nouveau: nouveau, confirmation: nouveau, maintenant: auj);
      }
      expect(dernier!.bloqueJusqua, auj.add(accDureeBlocageSecours));
      final bloque = await ident.recuperer(identifiant: 'k.adjovi', code: code, nouveau: nouveau, confirmation: nouveau, maintenant: auj.add(const Duration(minutes: 5)));
      expect(bloque.ok, isFalse);
      expect(bloque.message, contains('bloquée'));
      final apres = await ident.recuperer(identifiant: 'k.adjovi', code: code, nouveau: nouveau, confirmation: nouveau, maintenant: auj.add(const Duration(minutes: 16)));
      expect(apres.ok, isTrue, reason: apres.message);
      expect(await ident.motDePasseActuel(id, nouveau), isTrue);
    });

    test('un nouveau mot de passe refusé ne brûle pas le code', () async {
      final (m, _, _, code) = await installe();
      final ident = ServiceIdentifiants.de(m);
      final refuse = await ident.recuperer(identifiant: 'k.adjovi', code: code, nouveau: 'court', confirmation: 'court', maintenant: auj);
      expect(refuse.ok, isFalse);
      expect(refuse.codeBon, isTrue);
      expect(refuse.message, contains('non conforme'));
      final ok = await ident.recuperer(identifiant: 'k.adjovi', code: code, nouveau: nouveau, confirmation: nouveau, maintenant: auj);
      expect(ok.ok, isTrue);
    });

    test('un compte administrateur sans code de secours ne peut pas récupérer', () async {
      final (m, _) = await poste();
      final r = await ServiceIdentifiants.de(m).recuperer(identifiant: 'admin.systeme', code: 'AAAAA-BBBBB-CCCCC-DDDDD-EEEEE', nouveau: nouveau, confirmation: nouveau, maintenant: auj);
      expect(r.ok, isFalse);
      expect(r.message, accMessageSecoursRefus);
    });
  });
}
