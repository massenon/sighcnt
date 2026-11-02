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
import 'package:sigh_poste/modules/auth/acc_session.dart';

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
}
