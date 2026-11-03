import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/etat_installation.dart';
import 'package:sigh_poste/core/identifiants.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/core/service_installation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/mere/activation.dart' show ActivationRefusee;
import 'package:sigh_poste/modules/auth/acc_session.dart';
import 'package:sigh_poste/modules/auth/ins_modale.dart' show ecransConfigurationsInstallation;

import 'aide_polices.dart';

/// PLAN étapes 3 et 4, côté ÉCRAN : l'accueil à deux choix, la création du premier compte, le code de secours et la récupération.
typedef M = Map<String, Object?>;
List<M> jeu(String nom) => [for (final x in (jsonDecode(File('assets/donnees/jeu/$nom.json').readAsStringSync()) as List)) (x as Map).cast<String, Object?>()];

final donnees = DonneesNavigation.depuisDossier();
final auj = DateTime(2026, 11, 2, 9);
const secret = 'Clinique#Natitingou26';

Magasin poste() => Magasin({
      'audit': const <M>[],
      'utilisateurs': jeu('utilisateurs'),
      'rbac': jeu('rbac'),
      'tentativesConnexion': const <M>[],
      'personnel': jeu('personnel'),
      'soignants': jeu('soignants'),
      'rolesBase': jeu('rolesBase'),
      'support': const <M>[],
    }, 'POSTE');

Future<void> monter(WidgetTester t, Magasin m, SessionPoste s) async {
  t.view.physicalSize = const Size(1600, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: 'reception'),
      magasin: m,
      session: s,
      horloge: () => auj));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> saisir(WidgetTester t, String cle, String texte) async {
  await t.enterText(find.byKey(Key(cle)), texte);
  await t.pump();
}

Future<void> toucher(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> calculer(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await t.pump(const Duration(milliseconds: 50));
  }
  await t.pump(const Duration(milliseconds: 500));
}

Future<void> fin(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 10));
  ToastsSigh.viderPourTests();
}

Future<Magasin> posteNeuf(WidgetTester t) async {
  final m = poste();
  await t.runAsync(() => ServiceInstallation.de(m).attacher(StockageMemoire(), const ParametresPoste(uuidPoste: 'u')));
  return m;
}

void main() {
  setUpAll(() async {
    await chargerPolices();
    ServiceIdentifiants.parametres = AccParametresHachage.tests;
  });
  tearDown(ToastsSigh.viderPourTests);

  testWidgets('un poste neuf propose les deux chemins, et pas la connexion', (t) async {
    final m = await posteNeuf(t);
    await monter(t, m, SessionPoste(exigeConnexion: true, horloge: () => auj));
    expect(find.text('Installation du poste'), findsOneWidget);
    expect(find.byKey(const Key('ins:premiere')), findsOneWidget);
    expect(find.byKey(const Key('ins:rejoindre')), findsOneWidget);
    expect(find.byKey(const Key('acces:identifiant')), findsNothing);
    await fin(t);
  });

  testWidgets('sans service attaché (tests, SIGH_ASSISTANT=non) : la connexion, comme avant', (t) async {
    await monter(t, poste(), SessionPoste(exigeConnexion: true, horloge: () => auj));
    expect(find.byKey(const Key('acces:identifiant')), findsOneWidget);
    expect(find.text('Installation du poste'), findsNothing);
    await fin(t);
  });

  testWidgets('première installation : refus nommé, puis compte créé, code de secours, et la suite exige la case', (t) async {
    final m = await posteNeuf(t);
    final s = SessionPoste(exigeConnexion: true, horloge: () => auj);
    await monter(t, m, s);
    await toucher(t, find.byKey(const Key('ins:premiere')));
    expect(find.text('Créer l’administrateur'), findsOneWidget);
    await saisir(t, 'ins:nom', 'ADJOVI Koffi');
    await saisir(t, 'ins:identifiant', 'k.adjovi');
    await saisir(t, 'ins:motdepasse', secret);
    await saisir(t, 'ins:confirmation', 'Autre#Chose2026');
    await toucher(t, find.byKey(const Key('ins:creer')));
    await calculer(t);
    expect(find.textContaining('ne correspondent pas'), findsOneWidget);
    expect(m.collection('identifiants').toutes, isEmpty, reason: 'rien n’est écrit sur un refus');

    await saisir(t, 'ins:confirmation', secret);
    await toucher(t, find.byKey(const Key('ins:creer')));
    await calculer(t);
    expect(find.text('Votre code de secours'), findsOneWidget);
    final code = (t.widget(find.byKey(const Key('ins:code'))) as Container).child as SelectableText;
    expect(accCodeSecoursBienForme(code.data!), isTrue);
    expect(find.textContaining('aucun chemin d’urgence'), findsWidgets);
    expect(s.etat, EtatSession.deconnectee, reason: 'la session ne s’ouvre pas avant la confirmation');

    // Sans la case, le bouton ne fait rien.
    await toucher(t, find.byKey(const Key('ins:suite')));
    expect(s.etat, EtatSession.deconnectee);
    await toucher(t, find.byKey(const Key('ins:range')));
    await toucher(t, find.byKey(const Key('ins:suite')));
    expect(s.etat, EtatSession.connectee);
    expect(s.role, 'admin');
    expect(s.compte!.identifiant, 'k.adjovi');
    expect(ServiceInstallation.de(m).etat.phase, PhaseInstallation.enCours);
    await fin(t);
  });

  testWidgets('récupération : depuis la connexion, le bon code remplace le mot de passe et un nouveau code s’affiche', (t) async {
    final m = poste();
    late String code;
    late String id;
    await t.runAsync(() async {
      final s = ServiceInstallation.de(m);
      await s.attacher(StockageMemoire(), const ParametresPoste(uuidPoste: 'u'));
      final r = await s.creerPremierAdministrateur(identifiant: 'k.adjovi', nom: 'ADJOVI Koffi', motDePasse: secret, confirmation: secret, maintenant: auj);
      code = r.codeSecours!;
      id = '${r.compte!.agent?.utilisateurId ?? ''}';
    });
    final s = SessionPoste(exigeConnexion: true, horloge: () => auj);
    await monter(t, m, s);
    expect(find.byKey(const Key('acces:identifiant')), findsOneWidget, reason: 'un compte existe : la connexion');
    await toucher(t, find.text('J’ai perdu mon mot de passe administrateur'));
    expect(find.text('Mot de passe administrateur perdu'), findsOneWidget);

    await saisir(t, 'sec:identifiant', 'k.adjovi');
    await saisir(t, 'sec:code', 'AAAAA-BBBBB-CCCCC-DDDDD-EEEEE');
    await saisir(t, 'sec:motdepasse', 'Nouveau#Mot2Passe9');
    await saisir(t, 'sec:confirmation', 'Nouveau#Mot2Passe9');
    await toucher(t, find.byKey(const Key('sec:valider')));
    await calculer(t);
    expect(find.text(accMessageSecoursRefus), findsOneWidget);

    await saisir(t, 'sec:code', code);
    await toucher(t, find.byKey(const Key('sec:valider')));
    await calculer(t);
    expect(find.text('Mot de passe remplacé'), findsOneWidget);
    final nouveau = ((t.widget(find.byKey(const Key('sec:code'))) as Container).child as SelectableText).data!;
    expect(nouveau, isNot(code));
    final ok = await t.runAsync(() => ServiceIdentifiants.de(m).motDePasseActuel(
        '${m.collection('utilisateurs').toutes.firstWhere((u) => u['identifiant'] == 'k.adjovi')['id']}', 'Nouveau#Mot2Passe9'));
    expect(ok, isTrue, reason: id);
    await fin(t);
  });

  mainModale();
  mainRejoindre();
}

/// PLAN étapes 6 à 8 : la modale « Configurations à faire », l'activation de la mère (reportable), la clôture qui exige un second administrateur.
Future<(Magasin, SessionPoste, ServiceInstallation)> installeEtConnecte(WidgetTester t) async {
  final m = await posteNeuf(t);
  final s = SessionPoste(exigeConnexion: true, horloge: () => auj);
  await monter(t, m, s);
  await toucher(t, find.byKey(const Key('ins:premiere')));
  await saisir(t, 'ins:nom', 'ADJOVI Koffi');
  await saisir(t, 'ins:identifiant', 'k.adjovi');
  await saisir(t, 'ins:motdepasse', secret);
  await saisir(t, 'ins:confirmation', secret);
  await toucher(t, find.byKey(const Key('ins:creer')));
  await calculer(t);
  await toucher(t, find.byKey(const Key('ins:range')));
  await toucher(t, find.byKey(const Key('ins:suite')));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
  return (m, s, ServiceInstallation.de(m));
}

void mainModale() {
  group('modale « Configurations à faire »', () {
    testWidgets('elle s’ouvre seule sur le tableau de bord de l’administrateur, avec la pastille de la barre', (t) async {
      final (_, s, _) = await installeEtConnecte(t);
      expect(s.etat, EtatSession.connectee);
      expect(find.text('Configurations à faire avant l’utilisation'), findsOneWidget);
      expect(find.byKey(const Key('ins:progression')), findsOneWidget);
      expect(find.textContaining('0 étape(s) faite(s) sur 4'), findsOneWidget);
      await toucher(t, find.byKey(const Key('ins:modale-fermer')));
      expect(find.text('Configurations à faire avant l’utilisation'), findsNothing);
      expect(find.byKey(const Key('barre-installation')), findsOneWidget, reason: 'la pastille rouvre la modale');
      await toucher(t, find.byKey(const Key('barre-installation')));
      expect(find.text('Configurations à faire avant l’utilisation'), findsOneWidget);
      await fin(t);
    });

    Future<void> champ(WidgetTester t, String nom, String texte) async {
      await t.enterText(find.descendant(of: find.byKey(Key('kit:champ:$nom')), matching: find.byType(TextField)), texte);
      await t.pump();
    }

    Future<void> remplirActivation(WidgetTester t) async {
      await toucher(t, find.byKey(const Key('ins:activer')));
      await champ(t, 'relais', 'https://relais.exemple.bj');
      await champ(t, 'secret', 'secret-de-la-mere');
      await champ(t, 'cle', 'cle-de-clinique-0123456789');
      await toucher(t, find.byKey(const Key('ins:activer-valider')));
      for (var i = 0; i < 3; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('les étapes B, C, D sont verrouillées avec leur motif tant que la mère n’est pas réglée ; l’activation échoue en le disant, puis se reporte', (t) async {
      final (_, _, service) = await installeEtConnecte(t);
      for (final id in ['configurations', 'comptes', 'appairages']) {
        expect((t.widget(find.byKey(Key('ins:motif-$id'))) as Text).data, contains('Activer d’abord la mère'));
        expect(find.byKey(Key('ins:verifier-cfg-entetes')), findsNothing, reason: 'une étape verrouillée n’offre aucune commande');
      }
      service.activerMere = ({required relais, required secretMere, required cleClinique, nomPoste}) async =>
          throw ActivationRefusee('relais_injoignable', 'Le relais n’a pas répondu : l’activation exige de le joindre.');
      await remplirActivation(t);
      expect(find.byKey(const Key('ins:erreur-activation')), findsOneWidget);
      expect(find.textContaining('Le relais n’a pas répondu'), findsOneWidget);
      expect(service.etat.etat('mere'), EtapeEtat.aFaire, reason: 'un échec ne marque rien');
      await toucher(t, find.byKey(const Key('ins:reporter')));
      expect(service.etat.etat('mere'), EtapeEtat.reportee);
      expect(find.byKey(const Key('ins:verifier-cfg-entetes')), findsOneWidget, reason: 'reportée, la mère déverrouille les autres étapes');
      await fin(t);
    });

    testWidgets('l’activation réussie marque l’étape et passe par le geste réel du poste', (t) async {
      final (_, _, service) = await installeEtConnecte(t);
      Map<String, String?>? recu;
      service.activerMere = ({required relais, required secretMere, required cleClinique, nomPoste}) async =>
          recu = {'relais': relais, 'secret': secretMere, 'cle': cleClinique};
      await remplirActivation(t);
      expect(recu!['relais'], 'https://relais.exemple.bj');
      expect(service.etat.etat('mere'), EtapeEtat.faite);
      expect(find.text('La mère est activée.'), findsOneWidget);
      await fin(t);
    });

    testWidgets('la clôture exige les quatre étapes ET un second administrateur ; une fois close, la pastille disparaît et le dernier administrateur ne s’archive plus', (t) async {
      final (m, _, service) = await installeEtConnecte(t);
      service.activerMere = ({required relais, required secretMere, required cleClinique, nomPoste}) async {};
      await remplirActivation(t);
      expect((t.widget(find.byKey(const Key('ins:cloturer'))) as BoutonSigh).onPressed, isNull, reason: 'il reste des étapes');
      expect(find.textContaining('second administrateur est obligatoire'), findsOneWidget);
      // Les étapes se DÉTECTENT : configurations (écrites ou vérifiées), appairages (un appareil connu de la mère) ; les comptes, quand le second administrateur existe.
      service.compterAppareils = () async => 2;
      for (final (id, _) in ecransConfigurationsInstallation) {
        await toucher(t, find.byKey(Key('ins:verifier-$id')));
      }
      await t.pump(const Duration(milliseconds: 300));
      expect(service.etat.etat('configurations'), EtapeEtat.faite, reason: 'sept écrans vérifiés : l’étape se termine toute seule');
      expect(service.etat.etat('appairages'), EtapeEtat.faite, reason: 'deux appareils appairés détectés');
      expect(service.etat.etat('comptes'), EtapeEtat.aFaire, reason: 'un seul administrateur');
      expect(find.byKey(const Key('ins:fait-comptes')), findsNothing, reason: 'plus rien à cocher');
      expect(find.byKey(const Key('ins:refus-cloture')), findsOneWidget);
      expect(find.textContaining('second administrateur est obligatoire'), findsOneWidget);
      expect((t.widget(find.byKey(const Key('ins:cloturer'))) as BoutonSigh).onPressed, isNull);

      // Un second administrateur, avec un mot de passe : la clôture s'ouvre.
      m.collection('utilisateurs').inserer({'id': 'USR900', 'statut': 'actif', 'identifiant': 'a.second', 'nomComplet': 'SECOND Admin', 'role': 'admin'});
      await t.runAsync(() => ServiceIdentifiants.de(m).definir('USR900', secret, par: 'test', doitChanger: false, maintenant: auj));
      await t.runAsync(() => service.detecter());
      await t.pump(const Duration(milliseconds: 100));
      expect(service.etat.etat('comptes'), EtapeEtat.faite, reason: 'deux administrateurs : détecté');
      expect(find.byKey(const Key('ins:refus-cloture')), findsNothing);
      await toucher(t, find.byKey(const Key('ins:cloturer')));
      expect(service.etat.phase, PhaseInstallation.cloturee);
      expect(find.text('L’assistant est clos.'), findsOneWidget);
      expect(m.collection('audit').toutes.map((f) => f['action']), contains('Assistant d’installation clos'));

      // Le moteur refuse d'archiver un administrateur qui laisserait moins de deux administrateurs actifs.
      final premier = m.collection('utilisateurs').toutes.firstWhere((u) => u['identifiant'] == 'k.adjovi');
      expect(() => m.collection('utilisateurs').archiver(premier['id']), throwsA(isA<EcritureRefusee>()));
      expect(m.collection('utilisateurs').parId(premier['id'])!['statut'], 'actif');
      await toucher(t, find.byKey(const Key('ins:modale-fermer')));
      expect(find.byKey(const Key('barre-installation')), findsNothing, reason: 'l’assistant clos n’a plus de pastille');
      await fin(t);
    });
  });
}

void mainRejoindre() {
  group('rejoindre une clinique', () {
    testWidgets('adresse et code : refus nommés, puis rattachement ; l’écran attend les comptes de la mère', (t) async {
      final m = await posteNeuf(t);
      final service = ServiceInstallation.de(m);
      var appels = 0;
      service.rattacherMoteur = ({required adresse, required code}) async {
        appels++;
        if (code == 'EXPIRE23') throw StateError('code_expire — Ce code a expiré.');
        if (code == 'DEJAUTI2') throw StateError('code_utilise');
        if (adresse.contains('mort')) throw const SocketException('connexion refusée');
      };
      final s = SessionPoste(exigeConnexion: true, horloge: () => auj);
      await monter(t, m, s);
      await toucher(t, find.byKey(const Key('ins:rejoindre')));
      expect(find.text('Rejoindre une clinique'), findsOneWidget);

      await saisir(t, 'rej:adresse', 'nimporte quoi');
      await saisir(t, 'rej:code', 'ABCD2345');
      await toucher(t, find.byKey(const Key('rej:valider')));
      await calculer(t);
      expect(find.textContaining('Adresse invalide'), findsOneWidget);
      expect(appels, 0, reason: 'une adresse invalide ne part pas');

      await saisir(t, 'rej:adresse', 'http://192.168.1.10:9000');
      await saisir(t, 'rej:code', 'expire23');
      await toucher(t, find.byKey(const Key('rej:valider')));
      await calculer(t);
      expect(find.textContaining('a expiré'), findsOneWidget);
      await saisir(t, 'rej:code', 'DEJAUTI2');
      await toucher(t, find.byKey(const Key('rej:valider')));
      await calculer(t);
      expect(find.textContaining('a déjà servi'), findsOneWidget);
      await saisir(t, 'rej:adresse', 'http://mort:9000');
      await saisir(t, 'rej:code', 'ABCD2345');
      await toucher(t, find.byKey(const Key('rej:valider')));
      await calculer(t);
      expect(find.textContaining('n’a pas répondu'), findsOneWidget);
      expect(service.rattache, isFalse, reason: 'aucun échec ne rattache');

      await saisir(t, 'rej:adresse', 'http://192.168.1.10:9000/');
      await saisir(t, 'rej:code', 'ABCD2345');
      await toucher(t, find.byKey(const Key('rej:valider')));
      await calculer(t);
      expect(service.rattache, isTrue);
      expect(service.parametres!.adresseMere, 'http://192.168.1.10:9000', reason: 'l’adresse est rangée sans la barre finale');
      expect(service.etat.phase, PhaseInstallation.cloturee, reason: 'un poste rattaché n’a plus d’assistant à proposer');
      expect(find.text('Réception de la configuration'), findsOneWidget);
      expect((t.widget(find.byKey(const Key('ins:vers-connexion'))) as BoutonSigh).onPressed, isNull, reason: 'pas de compte tant que la mère n’a rien diffusé');

      // La mère diffuse ses comptes : l'écran le voit et ouvre la connexion.
      await t.runAsync(() => ServiceIdentifiants.de(m).definir('USR001', secret, par: 'mère', doitChanger: false, maintenant: auj));
      await t.pump(const Duration(milliseconds: 600));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Poste rattaché'), findsOneWidget);
      await toucher(t, find.byKey(const Key('ins:vers-connexion')));
      expect(find.byKey(const Key('acces:identifiant')), findsOneWidget, reason: 'la connexion, avec les comptes de la clinique');
      expect(appels, 4);
      await fin(t);
    });
  });
}
