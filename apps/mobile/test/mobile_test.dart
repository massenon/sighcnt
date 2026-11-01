import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_mobile/main.dart';
import 'package:sigh_mobile/moteur/moteur_mobile.dart';

import 'aide_mobile.dart';

void main() {
  testWidgets('appairage : champs obligatoires, puis l\'accueil du profil que le CODE porte (la réception de secours)', (t) async {
    final m = FauxMoteur(profilDuCode: ProfilMobile.receptionSecours);
    await t.pumpWidget(SighMobile(moteur: m));
    await t.tap(find.byKey(const Key('appairer')));
    await t.pump();
    expect(find.text('Le code d’appairage et la clé de clinique sont obligatoires.'), findsOneWidget);

    // E1600 : le téléphone ne choisit NI son profil NI sa fonction, ils viennent du code émis par la console de la mère.
    expect(find.byKey(const Key('profil')), findsNothing);
    expect(find.byKey(const Key('fonction')), findsNothing);
    await t.enterText(find.byKey(const Key('code')), 'abcd2345');
    await t.enterText(find.byKey(const Key('cle')), 'Y2xl');
    await t.enterText(find.byKey(const Key('agent')), 'OROU YO Edmond');
    await t.tap(find.byKey(const Key('appairer')));
    await t.pumpAndSettle();
    expect(m.agentAppairage, 'OROU YO Edmond');
    expect(m.codeAppairage, 'ABCD2345');
    expect(m.profil, ProfilMobile.receptionSecours);
    expect(find.text('Réception de secours'), findsWidgets);
  });

  testWidgets('appairage soignant : l\'agent est obligatoire (RG-12), la fonction est celle du code, jamais une saisie', (t) async {
    final m = FauxMoteur(fonction: 'infirmier');
    await t.pumpWidget(SighMobile(moteur: m));
    await t.enterText(find.byKey(const Key('code')), 'abcd2345');
    await t.enterText(find.byKey(const Key('cle')), 'Y2xl');
    await t.tap(find.byKey(const Key('appairer')));
    await t.pump();
    expect(find.text('Le nom de l’agent est obligatoire : aucune action anonyme (RG-12).'), findsOneWidget);
    expect(m.codeAppairage, isNull);

    await t.enterText(find.byKey(const Key('agent')), 'Dr YENI M’PO Florent');
    await t.ensureVisible(find.byKey(const Key('appairer')));
    await t.tap(find.byKey(const Key('appairer')));
    await t.pumpAndSettle();
    expect(m.agentAppairage, 'Dr YENI M’PO Florent');
    expect(m.profil, ProfilMobile.soignant);
    expect(m.soignant!.session.fonction, 'infirmier', reason: 'la fonction vient du code, pas de l\'écran');
  });

  testWidgets('appairage refusé par la mère : la cause s\'affiche, on reste sur l\'écran', (t) async {
    await t.pumpWidget(SighMobile(moteur: FauxMoteur(refus: 'code_invalide')));
    await t.enterText(find.byKey(const Key('code')), 'X');
    await t.enterText(find.byKey(const Key('cle')), 'Y');
    await t.enterText(find.byKey(const Key('agent')), 'Agent');
    await t.ensureVisible(find.byKey(const Key('appairer')));
    await t.tap(find.byKey(const Key('appairer')));
    await t.pumpAndSettle();
    expect(find.textContaining('code_invalide'), findsOneWidget);
    expect(find.byKey(const Key('appairer')), findsOneWidget);
  });

  testWidgets('réception de secours : dossier visible AUSSITÔT, compteur « en attente », contrôles du formulaire', (t) async {
    final m = FauxMoteur()..profil = ProfilMobile.receptionSecours;
    await t.pumpWidget(SighMobile(moteur: m));
    await t.pumpAndSettle();
    expect(find.text('Ma tournée'), findsNothing);

    await t.tap(find.byKey(const Key('creer')));
    await t.pump();
    expect(find.text('Le nom et le prénom sont obligatoires.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('nom')), 'AKPO');
    await t.enterText(find.byKey(const Key('prenom')), 'Marc');
    await t.enterText(find.byKey(const Key('age')), '200');
    await t.tap(find.byKey(const Key('creer')));
    await t.pump();
    expect(find.text('L’âge déclaré est obligatoire (0 à 120 ans).'), findsOneWidget);
    expect(m.crees, isEmpty);

    await t.enterText(find.byKey(const Key('age')), '34');
    await t.tap(find.byKey(const Key('creer')));
    await t.pumpAndSettle();
    expect(m.crees.single.champs['origine'], 'reception_secours');
    expect(find.text('AKPO Marc'), findsOneWidget);
    expect(find.text('en attente de numéro'), findsOneWidget);
    expect(find.textContaining('1 en attente d’envoi'), findsOneWidget);
  });

  testWidgets('le bandeau dit qu\'un refus attend et ouvre « À traiter » avec son code, son motif et son geste', (t) async {
    final m = FauxMoteur(refusATraiter: const [
      RefusAffiche(operation: 'op1', code: 'droit_refuse', motif: 'Infirmier(ère) n’est pas habilité à prescrire « Médicaments ».', geste: 'Demander la prescription à un médecin')
    ])
      ..profil = ProfilMobile.soignant;
    m.etat.value = const EtatMobile(horsLigne: false, aTraiter: 1);
    await t.pumpWidget(SighMobile(moteur: m));
    await t.pumpAndSettle();
    expect(find.textContaining('1 à traiter'), findsOneWidget);
    await t.tap(find.byKey(const Key('bandeau')));
    await t.pumpAndSettle();
    expect(find.textContaining('n’est pas habilité à prescrire'), findsOneWidget);
    expect(find.textContaining('À faire : Demander la prescription à un médecin'), findsOneWidget);
    expect(find.textContaining('droit_refuse'), findsOneWidget);
  });

  testWidgets('un lot expiré se dit au bandeau', (t) async {
    final m = FauxMoteur()..profil = ProfilMobile.soignant;
    m.etat.value = EtatMobile(horsLigne: true, lotExpire: DateTime.now().millisecondsSinceEpoch - 1000);
    await t.pumpWidget(SighMobile(moteur: m));
    await t.pumpAndSettle();
    expect(find.textContaining('lot de tournée expiré'), findsOneWidget);
  });

  test('le moteur réel (sigh_sync) s\'instancie dans l\'application : non appairé, rien en attente, aucun profil', () async {
    final m = MoteurMobileSync.creer(dbChemin: ':memory:', relais: 'http://127.0.0.1:1');
    expect(m.profil, isNull);
    expect(m.soignant, isNull);
    await m.actualiser();
    expect(m.etat.value.appaire, isFalse);
    expect(m.etat.value.enAttente, 0);
    expect(m.etat.value.suspendu, isFalse);
    m.arreter();
  });

  test('l\'agent est exigé à l\'appairage (RG-12) : refus avant tout appel réseau ; le profil et la fonction ne sont plus des paramètres du téléphone', () async {
    final m = MoteurMobileSync.creer(dbChemin: ':memory:', relais: 'http://127.0.0.1:1');
    await expectLater(m.appairer(code: 'ABCD2345', cleClinique: 'Y2xl'), throwsStateError);
    m.arreter();
  });
}
