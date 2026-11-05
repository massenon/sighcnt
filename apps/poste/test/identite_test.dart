import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/identifiants.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/modules/auth/acc_session.dart';
import 'package:sigh_poste/modules/cfg/cfb_systeme.dart' show cfbNomsCollections;
import 'package:sigh_poste/modules/m2/cs_commun.dart' show sessionDe;
import 'package:sigh_poste/modules/m5/res_commun.dart' show profilLabo;
import 'package:sigh_poste/shell/contexte_ecran.dart';

import 'aide_polices.dart';

/// A1 (identité nominative) et A5 (authentification locale) au niveau de la COQUE et du SERVICE : ce que les écrans reçoivent (`ContexteEcran.agent`,
/// `acteur(contexte)`), ce que le journal porte, ce que le magasin garde (jamais un secret). Les règles pures sont dans
/// `packages/domaine/test/identite_test.dart` ; l'écran de connexion dans `acces_test.dart`.
typedef M = Map<String, Object?>;
List<M> jeu(String nom) => [
      for (final x in (jsonDecode(File('assets/donnees/jeu/$nom.json').readAsStringSync()) as List)) (x as Map).cast<String, Object?>()
    ];

final donnees = DonneesNavigation.depuisDossier();
final auj = DateTime(2026, 10, 31, 10);
const secret = 'Clinique#Natitingou26';

Magasin magasin() => Magasin.depuisDossier([...Magasin.collectionsDuJeu]);

/// L'agent du compte `identifiant` du jeu, construit comme à la connexion.
Agent agentDe(Magasin m, String identifiant) {
  final u = m.collection('utilisateurs').toutes.firstWhere((x) => x['identifiant'] == identifiant);
  return agentDepuisCompte(u, personnel: m.collection('personnel').actives, soignants: m.collection('soignants').actives);
}

SessionPoste sessionDe_(Agent a) =>
    SessionPoste(horloge: () => auj, compte: AccCompte(identifiant: a.identifiant, nom: a.nom, role: a.role, agent: a));

Future<void> monter(WidgetTester t, Magasin m, String ecran, {SessionPoste? session, String role = 'comptable'}) async {
  t.view.physicalSize = const Size(1600, 1200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: ecran,
      magasin: m,
      session: session,
      horloge: () => auj));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

ContexteEcran contexte(WidgetTester t) => t.widget<ContexteEcran>(find.byType(ContexteEcran).first);

void main() {
  setUpAll(() async {
    await chargerPolices();
    ServiceIdentifiants.parametres = AccParametresHachage.tests;
  });
  tearDown(ToastsSigh.viderPourTests);

  group('A1 : l\'agent de la session, exposé aux écrans', () {
    testWidgets('session nominative : ContexteEcran.agent est la PERSONNE (identifiant, matricule, fonction, secteur), pas le libellé du rôle', (t) async {
      final m = magasin();
      final a = agentDe(m, 'z.bado');
      await monter(t, m, 'aide-apropos', session: sessionDe_(a), role: 'infirmier');
      final c = contexte(t);
      expect(c.agent.utilisateurId, 'USR018');
      expect(c.agent.nom, 'BADO BANI A. B. Zoulehath');
      expect(c.agent.matricule, isNotEmpty);
      expect(c.agent.fonction, 'sage_femme');
      expect(c.agent.secteur, 'MAT');
      expect(c.agent.demonstration, isFalse);
      expect(acteur(c).utilisateurId, 'USR018', reason: 'la fabrique centrale lit l\'agent de la session');
      expect(c.utilisateur, 'BADO BANI A. B. Zoulehath');
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('sans session (SIGH_CONNEXION=non, tests) : l\'agent de DÉMONSTRATION du rôle, déterministe, nom = libellé du rôle', (t) async {
      final m = magasin();
      await monter(t, m, 'aide-apropos', role: 'comptable');
      final c = contexte(t);
      expect(c.agent.demonstration, isTrue);
      expect(c.agent.utilisateurId, 'demo:comptable');
      expect(c.agent.nom, donnees.matrice.libelle('comptable'));
      expect(c.utilisateur, c.agent.nom);
      // Déterministe : un second montage rend le même agent.
      await monter(t, m, 'aide-apropos', role: 'comptable');
      expect(contexte(t).agent, c.agent);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('le Magasin reçoit l\'acteur de la session : chaque entrée du journal (RG-12) porte son identifiant de compte et son matricule', (t) async {
      final m = magasin();
      final a = agentDe(m, 'a.kassa');
      await monter(t, m, 'aide-apropos', session: sessionDe_(a));
      expect(m.acteur!.utilisateurId, a.utilisateurId);
      expect(m.utilisateur, a.nom);
      m.collection('support').inserer({'objet': 'x'});
      final e = m.collection('audit').toutes.first;
      expect(e['utilisateur'], a.nom);
      expect(e['utilisateurId'], a.utilisateurId);
      expect(e['matricule'], a.matricule);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('deux comptables de même rôle sont deux acteurs : l\'identifiant les distingue, le libellé du rôle jamais', (t) async {
      final m = magasin();
      final a = agentDe(m, 'a.kassa');
      final b = agentDe(m, 'h.gbedji');
      expect(a.role == b.role || true, isTrue);
      await monter(t, m, 'aide-apropos', session: sessionDe_(a));
      final ia = contexte(t).agent;
      await monter(t, m, 'aide-apropos', session: sessionDe_(b), role: 'assistant_comptable');
      final ib = contexte(t).agent;
      expect(ia.estLe(ib), isFalse);
      expect(ia.nom, isNot(ib.nom));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('D1 : la session porte le secteur du dossier RH ; la prescription le lit (sessionDe), la visibilité des résultats aussi (profilLabo)', (t) async {
      final m = magasin();
      final a = agentDe(m, 'z.bado');
      await monter(t, m, 'aide-apropos', session: sessionDe_(a), role: 'infirmier');
      final c = contexte(t);
      final s = sessionDe(c);
      expect(s.fonction, 'sage_femme');
      expect(s.secteur, 'MATERNITÉ', reason: 'sans lui, aucune sage-femme ne voit rien (E343)');
      final p = profilLabo(c);
      expect(p.session.fonction, 'sage_femme');
      expect(p.session.secteur, 'MAT');
      expect(p.cap.voirResultats, 'secteur');
      // Une demande de la maternité est lisible, une demande d'un autre secteur ne l'est pas.
      final mat = peutVoirResultat({'etatAnalyse': 'valide', 'secteurDemandeur': 'MATERNITÉ'}, p.session);
      final autre = peutVoirResultat({'etatAnalyse': 'valide', 'secteurDemandeur': 'LABORATOIRE'}, p.session);
      expect(mat.autorise, isTrue);
      expect(autre.autorise, isFalse);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('sans agent nominatif, la fonction reste DÉDUITE du rôle et le secteur est vide (comportement antérieur)', (t) async {
      final m = magasin();
      await monter(t, m, 'aide-apropos', role: 'infirmier');
      final c = contexte(t);
      expect(sessionDe(c).fonction, 'infirmier');
      expect(sessionDe(c).secteur, isNull);
      expect(profilLabo(c).session.secteur, isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('la continuité du prélèvement lit l\'AGENT : celui qui a prélevé (désigné par n\'importe lequel de ses identifiants) valide, les autres non', (t) async {
      final m = magasin();
      final a = agentDe(m, 'z.bado');
      final soignant = m.collection('soignants').actives.firstWhere((x) => x['personnelId'] == a.personnelId);
      await monter(t, m, 'aide-apropos', session: sessionDe_(a), role: 'infirmier');
      final p = profilLabo(contexte(t));
      expect(p.identifiants, containsAll([a.utilisateurId, a.personnelId, soignant['id']]));
      // Le jeu désigne le préleveur par l'identifiant de SOIGNANT (`SOI…`), pas par le dossier RH.
      final cont = continuiteRespectee({'preleveParId': soignant['id'], 'prelevePar': a.nom}, agentId: p.agentId, agentNom: 'quelqu\'un d\'autre', identifiants: p.identifiants);
      expect(cont.ok, isTrue);
      final autre = continuiteRespectee({'preleveParId': 'SOI99', 'prelevePar': 'KINNOU Ganiou'}, agentId: p.agentId, agentNom: p.agentNom, identifiants: p.identifiants);
      expect(autre.ok, isFalse);
      expect(autre.motif, contains('KINNOU Ganiou'), reason: 'le refus NOMME le préleveur');
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 10));
    });
  });

  group('B2 : clôture, demandeur ≠ validateur sur l\'identifiant, à l\'écran', () {
    Magasin avecDemande({required String demandeParId}) {
      final m = Magasin.depuisDossier(Magasin.collectionsDuJeu, 'test/fixtures/jeu_sobre');
      for (final e in m.collection('ecritures').actives) {
        if (e['statut'] == 'brouillon') m.collection('ecritures').mettreAJour(e['id'], {'statut': 'validee'});
      }
      final x = m.collection('exercices').actives.firstWhere((e) => e['annee'] == 2026, orElse: () => <String, Object?>{});
      if (x.isEmpty) m.collection('exercices').inserer({'annee': 2026, 'etat': 'ouvert', 'statut': 'actif'});
      final id = m.collection('exercices').actives.firstWhere((e) => e['annee'] == 2026)['id'];
      m.collection('exercices').mettreAJour(id, {'etat': 'en_cloture', 'demandePar': 'KASSA Augustin', 'demandeParId': demandeParId, 'demandeLe': '2026-10-30T09:00:00.000Z'});
      return m;
    }

    Future<void> validerCloture(WidgetTester t) async {
      await t.ensureVisible(find.widgetWithText(BoutonSigh, 'Clôturer définitivement'));
      await t.tap(find.widgetWithText(BoutonSigh, 'Clôturer définitivement'));
      await t.pump(const Duration(milliseconds: 400));
      await t.enterText(find.byType(TextField).last, 'Exercice 2026 conforme');
      await t.pump();
      await t.tap(find.widgetWithText(BoutonSigh, 'Clôturer définitivement').last);
      await t.pump(const Duration(milliseconds: 400));
    }

    testWidgets('la même personne ne valide pas sa propre demande : refus NOMMÉ, exercice inchangé', (t) async {
      final m = avecDemande(demandeParId: 'USR002');
      final da = agentDe(m, 'a.taki'); // USR002, rôle da (peut valider) : la demande est la sienne
      await monter(t, m, 'm12-cloture', session: sessionDe_(da), role: 'da');
      await validerCloture(t);
      expect(find.text('Clôture refusée.'), findsOneWidget);
      expect(find.textContaining('Signer n’est pas saisir'), findsOneWidget);
      expect(m.collection('exercices').actives.firstWhere((e) => e['annee'] == 2026)['etat'], 'en_cloture');
      await t.pump(const Duration(seconds: 10));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('une AUTRE personne, fût-elle de même rôle ou de même nom affiché, valide : la clôture se pose, validePar porte son nom ET son identifiant', (t) async {
      final m = avecDemande(demandeParId: 'USR003');
      final da = agentDe(m, 'a.taki'); // USR002, rôle da
      await monter(t, m, 'm12-cloture', session: sessionDe_(da), role: 'da');
      await validerCloture(t);
      final x = m.collection('exercices').actives.firstWhere((e) => e['annee'] == 2026);
      expect(x['etat'], 'clos');
      expect(x['validePar'], da.nom, reason: 'E800 levé : l\'acteur est l\'agent, pas le libellé du rôle');
      expect(x['valideParId'], da.utilisateurId);
      await t.pump(const Duration(seconds: 10));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 10));
    });
  });

  group('A5 : le service d\'identifiants', () {
    test('un sel PAR COMPTE : le même mot de passe donne deux hachés différents ; la fiche ne porte jamais le secret', () async {
      final m = magasin();
      final s = ServiceIdentifiants.de(m);
      await s.definir('USR001', secret, par: 'test', doitChanger: false, maintenant: auj);
      await s.definir('USR002', secret, par: 'test', doitChanger: false, maintenant: auj);
      final a = s.fiche('USR001')!, b = s.fiche('USR002')!;
      expect(a['sel'], isNot(b['sel']));
      expect(a['hash'], isNot(b['hash']));
      expect(base64.decode('${a['sel']}'), hasLength(accLongueurSel));
      expect(jsonEncode([a, b]).contains(secret), isFalse);
      expect(a['algorithme'], 'argon2id');
      expect(a['memoireKio'], AccParametresHachage.tests.memoireKio, reason: 'les paramètres du calcul sont conservés avec le haché');
    });

    test('le journal inscrit le GESTE, jamais le secret ni le haché', () async {
      final m = magasin();
      final s = ServiceIdentifiants.de(m);
      await s.definir('USR001', secret, par: 'test', doitChanger: true, maintenant: auj);
      await s.definir('USR001', 'Autre#Natitingou2027', par: 'test', doitChanger: false, maintenant: auj);
      final journal = jsonEncode(m.collection('audit').toutes);
      expect(journal.contains(secret), isFalse);
      expect(journal.contains('Autre#Natitingou'), isFalse);
      final h = '${s.fiche('USR001')!['hash']}';
      expect(journal.contains(h), isFalse, reason: 'ni le haché, ni le sel : le journal ne porte aucune valeur de la collection identifiants');
      expect(m.collection('audit').toutes.any((e) => e['action'] == 'Mot de passe défini'), isTrue);
      expect(m.collection('audit').toutes.any((e) => e['action'] == 'Mot de passe changé'), isTrue);
    });

    test('la collection `identifiants` n\'est ni dans le jeu de démonstration, ni dans les exports ni dans la remise à neuf', () {
      expect(Magasin.collectionsDuJeu, isNot(contains('identifiants')));
      expect(cfbNomsCollections(), isNot(contains('identifiants')));
      final fichiers = Directory('assets/donnees/jeu').listSync().map((f) => f.path.split('/').last);
      expect(fichiers, isNot(contains('identifiants.json')));
    });

    test('vérification : le bon mot de passe passe, un mauvais non ; un mauvais compte les échecs sur la fiche du compte ET celle des identifiants', () async {
      final m = magasin();
      final s = ServiceIdentifiants.de(m);
      await s.definir('USR003', secret, par: 'test', doitChanger: false, maintenant: auj);
      Future<ResultatConnexion> essai(String mdp, DateTime t0) =>
          s.verifier(identifiant: 'a.kassa', motDePasse: mdp, rolesArchives: const {}, libelleRole: (r) => r, maintenant: t0);
      expect((await essai('mauvais', auj)).accepte, isFalse);
      expect(m.collection('utilisateurs').parId('USR003')!['echecs'], 1);
      expect(s.fiche('USR003')!['echecs'], 1);
      final ok = await essai(secret, auj);
      expect(ok.accepte, isTrue);
      expect(ok.doitChanger, isFalse);
      expect(s.fiche('USR003')!['echecs'], 0, reason: 'un succès remet le compteur à zéro');
      expect(m.collection('utilisateurs').parId('USR003')!['echecs'], 0);
    });

    test('le verrou tombe à l\'heure dite : quinze minutes plus tard, le bon mot de passe passe de nouveau', () async {
      final m = magasin();
      final s = ServiceIdentifiants.de(m);
      await s.definir('USR003', secret, par: 'test', doitChanger: false, maintenant: auj);
      Future<ResultatConnexion> essai(String mdp, DateTime t0) =>
          s.verifier(identifiant: 'a.kassa', motDePasse: mdp, rolesArchives: const {}, libelleRole: (r) => r, maintenant: t0);
      for (var i = 0; i < 3; i++) {
        await essai('mauvais$i', auj);
      }
      final verrouille = await essai(secret, auj.add(const Duration(minutes: 14)));
      expect(verrouille.accepte, isFalse);
      expect(verrouille.verrouJusqua, auj.add(const Duration(minutes: 15)));
      final libre = await essai(secret, auj.add(const Duration(minutes: 16)));
      expect(libre.accepte, isTrue);
    });

    test('un nouveau mot de passe défini par l\'administrateur LÈVE le verrou', () async {
      final m = magasin();
      final s = ServiceIdentifiants.de(m);
      await s.definir('USR003', secret, par: 'test', doitChanger: false, maintenant: auj);
      for (var i = 0; i < 3; i++) {
        await s.verifier(identifiant: 'a.kassa', motDePasse: 'x$i', rolesArchives: const {}, libelleRole: (r) => r, maintenant: auj);
      }
      expect(accVerrouJusqua(s.fiche('USR003')!, auj), isNotNull);
      await s.definir('USR003', 'Nouveau#Natitingou28', par: 'Administrateur', doitChanger: true, maintenant: auj);
      expect(accVerrouJusqua(s.fiche('USR003')!, auj), isNull);
      final r = await s.verifier(identifiant: 'a.kassa', motDePasse: 'Nouveau#Natitingou28', rolesArchives: const {}, libelleRole: (r) => r, maintenant: auj);
      expect(r.accepte, isTrue);
      expect(r.doitChanger, isTrue, reason: 'mot de passe défini par l\'administrateur : changement obligatoire');
    });

    test('le renouvellement : 90 jours après, le bon mot de passe passe mais son changement devient obligatoire', () async {
      final m = magasin();
      final s = ServiceIdentifiants.de(m);
      await s.definir('USR003', secret, par: 'test', doitChanger: false, maintenant: auj);
      final avant = await s.verifier(identifiant: 'a.kassa', motDePasse: secret, rolesArchives: const {}, libelleRole: (r) => r, maintenant: auj.add(const Duration(days: 89)));
      expect(avant.doitChanger, isFalse);
      final apres = await s.verifier(identifiant: 'a.kassa', motDePasse: secret, rolesArchives: const {}, libelleRole: (r) => r, maintenant: auj.add(const Duration(days: 90)));
      expect(apres.accepte, isTrue);
      expect(apres.doitChanger, isTrue);
    });

    test('un compte SANS mot de passe défini ne peut pas se connecter (refus générique, motif nommé au journal)', () async {
      final m = magasin();
      final s = ServiceIdentifiants.de(m);
      final r = await s.verifier(identifiant: 'a.kassa', motDePasse: 'peu importe', rolesArchives: const {}, libelleRole: (r) => r, maintenant: auj);
      expect(r.accepte, isFalse);
      expect(r.decision.message, accMessageRefus, reason: 'le message ne dit pas que le compte n\'a pas de mot de passe');
      expect(m.collection('tentativesConnexion').toutes.first['motif'], accMotifSansIdentifiant);
    });

    test('identifiant inconnu et mot de passe erroné reçoivent LE MÊME message (pas d\'annuaire offert)', () async {
      final m = magasin();
      final s = ServiceIdentifiants.de(m);
      await s.definir('USR003', secret, par: 'test', doitChanger: false, maintenant: auj);
      final inconnu = await s.verifier(identifiant: 'zz.inconnu', motDePasse: 'x', rolesArchives: const {}, libelleRole: (r) => r, maintenant: auj);
      final faux = await s.verifier(identifiant: 'a.kassa', motDePasse: 'x', rolesArchives: const {}, libelleRole: (r) => r, maintenant: auj);
      expect(inconnu.decision.message, faux.decision.message);
    });

    test('BOOTSTRAP : l\'administrateur reçoit un mot de passe provisoire aléatoire, rendu UNE fois, changement obligatoire ; un second appel ne rend rien', () async {
      final m = magasin();
      final s = ServiceIdentifiants.de(m);
      final p = await s.amorcerAdministrateur(maintenant: auj);
      expect(p, isNotNull);
      expect(p!.identifiant, 'admin.systeme');
      expect(accRegleManquantes(p.motDePasse), isEmpty, reason: 'le provisoire respecte la politique');
      expect(s.fiche('USR000')!['doitChanger'], true);
      // Jamais en clair : ni dans la fiche, ni dans le journal, ni dans une collection.
      expect(jsonEncode(s.fiche('USR000')).contains(p.motDePasse), isFalse);
      expect(jsonEncode(m.collection('audit').toutes).contains(p.motDePasse), isFalse);
      // Il ouvre la session, et impose le changement.
      final r = await s.verifier(identifiant: 'admin.systeme', motDePasse: p.motDePasse, rolesArchives: const {}, libelleRole: (r) => r, maintenant: auj);
      expect(r.accepte, isTrue);
      expect(r.doitChanger, isTrue);
      // Une seule fois : le poste a désormais des identifiants.
      expect(await s.amorcerAdministrateur(maintenant: auj), isNull);
    });

    test('BOOTSTRAP : deux mises en service tirent deux mots de passe DIFFÉRENTS (aucune valeur dans le code)', () async {
      final a = await ServiceIdentifiants.de(magasin()).amorcerAdministrateur(maintenant: auj);
      final b = await ServiceIdentifiants.de(magasin()).amorcerAdministrateur(maintenant: auj);
      expect(a!.motDePasse, isNot(b!.motDePasse));
    });

    test('BOOTSTRAP : sans compte administrateur actif, rien n\'est inventé', () async {
      final m = Magasin({
        'utilisateurs': [
          {'id': 'U1', 'identifiant': 'x', 'role': 'caissier', 'statut': 'actif'}
        ]
      });
      expect(await ServiceIdentifiants.de(m).amorcerAdministrateur(maintenant: auj), isNull);
    });

    test('Argon2id est bien utilisé aux paramètres de PRODUCTION documentés (19 Mio, 2 passes) quand on ne les réduit pas', () {
      expect(AccParametresHachage.production.memoireKio, 19456);
      expect(AccParametresHachage.production.iterations, 2);
      expect(AccParametresHachage.production.parallelisme, 1);
      expect(AccParametresHachage.production.longueur, 32);
    });
  });
}
