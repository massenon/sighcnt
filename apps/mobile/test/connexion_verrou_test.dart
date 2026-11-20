// Bout en bout du démarrage réel (E1820 à E1824) : `Demarrage` est le widget que `main` lance, avec le vrai CoffrePinSecurise (haché PBKDF2) sur un
// stockage en mémoire. Ce que ces tests NE prouvent PAS : le Keystore Android, le lancement sur appareil, SQLCipher.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_mobile/core/coffre_pin_securise.dart';
import 'package:sigh_mobile/main.dart';
import 'package:sigh_mobile/moteur/moteur_mobile.dart';

import 'aide_suite.dart';

class Stockage implements StockageSecret {
  final Map<String, String> m = {};
  bool panne = false;
  @override
  Future<String?> lire(String cle) async => panne ? throw StateError('keystore_indisponible') : m[cle];
  @override
  Future<void> ecrire(String cle, String valeur) async {
    if (panne) throw StateError('keystore_indisponible');
    m[cle] = valeur;
  }
}

FauxMoteurSuite moteurNeuf() => FauxMoteurSuite(fonction: 'sage_femme', agent: 'Sage-femme de garde', source: lotSageFemme());
FauxMoteurSuite moteurAppaire() => moteurNeuf()..profil = ProfilMobile.soignant;

Future<void> demarrer(WidgetTester t, Stockage s, MoteurMobile m, {DateTime Function()? horloge}) async {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(Demarrage(stockage: s, creerMoteur: () => m, horlogeVerrou: horloge, iterationsPin: 1000));
  await t.pumpAndSettle();
}

Future<void> frappe(WidgetTester t, String s) async {
  for (final k in s.split('')) {
    await t.tap(find.byKey(Key('touche-$k')));
    await t.pump();
  }
  await t.pump();
}

Future<Stockage> stockageAvecCode(String code) async {
  final s = Stockage();
  await CoffrePinSecurise(s, iterations: 1000).definir(code);
  return s;
}

bool accueilVisible() => find.byKey(const Key('ouvrir-lot')).evaluate().isNotEmpty;

void main() {
  group('démarrage à froid', () {
    testWidgets('sans appairage : l\'appairage vient en premier, ni PIN ni accueil ; puis le code se choisit AVANT l\'accueil, sous le nom de l\'agent', (t) async {
      final s = Stockage();
      final m = moteurNeuf();
      await demarrer(t, s, m);
      expect(find.byKey(const Key('appairer')), findsOneWidget);
      expect(find.text('Code PIN'), findsNothing);
      expect(find.text('Choisissez un code à 4 chiffres.'), findsNothing);
      expect(accueilVisible(), isFalse);

      await t.enterText(find.byKey(const Key('code')), 'abcd2345');
      await t.enterText(find.byKey(const Key('cle')), 'Y2xl');
      await t.enterText(find.byKey(const Key('agent')), 'SOUROU Mariam');
      await t.ensureVisible(find.byKey(const Key('appairer')));
      await t.tap(find.byKey(const Key('appairer')));
      await t.pumpAndSettle();
      // L'appairage est fait : le choix du code passe devant l'accueil du profil.
      expect(find.text('Choisissez un code à 4 chiffres.'), findsOneWidget);
      expect(find.byKey(const Key('identite-agent')), findsOneWidget);
      expect(tester(find.byKey(const Key('identite-agent'))), 'Sage-femme de garde', reason: 'l\'agent identifié est celui de la session du moteur appairé (le faux moteur fixe le sien), jamais saisi sur l\'écran de verrou');
      expect(find.byKey(const Key('identite-profil')), findsOneWidget);
      expect(accueilVisible(), isFalse, reason: 'aucune commande métier tant que le code n\'est pas choisi');

      await frappe(t, '4321');
      await frappe(t, '4321');
      await t.pumpAndSettle();
      expect(accueilVisible(), isTrue, reason: 'le code choisi ouvre l\'accueil du profil');
      expect(s.m.keys.any((k) => s.m[k] == '4321'), isFalse, reason: 'le code n\'est jamais rangé en clair');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('appairé : le verrou vient AVANT tout écran métier, avec l\'agent et son profil lus du code', (t) async {
      final s = await stockageAvecCode('1234');
      await demarrer(t, s, moteurAppaire());
      expect(find.text('Code PIN'), findsOneWidget);
      expect(find.byKey(const Key('identite-agent')), findsOneWidget);
      expect(find.text('Sage-femme de garde'), findsOneWidget);
      expect(find.text('Sage-femme'), findsOneWidget, reason: 'le profil vient de la fonction du code d\'appairage');
      expect(find.byKey(const Key('appairer')), findsNothing, reason: 'on n\'a pas à s\'appairer deux fois');
      expect(accueilVisible(), isFalse);
      expect(find.text('Ma tournée'), findsNothing);
      // Les commandes métier sont montées mais cachées et inertes : elles n'existent pas pour l'utilisateur.
      expect(find.byKey(const Key('ouvrir-lot'), skipOffstage: false), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('trois mauvais codes bloquent 30 s, le bon code est alors ignoré, puis le bon code ouvre', (t) async {
      final s = await stockageAvecCode('1234');
      var maintenant = DateTime(2026, 11, 1, 9);
      await demarrer(t, s, moteurAppaire(), horloge: () => maintenant);
      await frappe(t, '0000');
      expect(find.text('Code incorrect (1/3).'), findsOneWidget);
      await frappe(t, '0000');
      await frappe(t, '0000');
      expect(find.textContaining('réessayez dans 30 s'), findsOneWidget);
      await frappe(t, '1234');
      expect(accueilVisible(), isFalse, reason: 'bloqué, même le bon code est ignoré');
      maintenant = maintenant.add(const Duration(seconds: 31));
      await t.pump(const Duration(seconds: 31));
      await t.pump();
      expect(find.textContaining('réessayez dans 30 s'), findsNothing);
      await frappe(t, '1234');
      await t.pumpAndSettle();
      expect(accueilVisible(), isTrue);
      expect(find.text('Ma tournée'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('le blocage survit au redémarrage : relancer l\'application ne rend pas les essais', (t) async {
      final s = await stockageAvecCode('1234');
      final maintenant = DateTime(2026, 11, 1, 9);
      await demarrer(t, s, moteurAppaire(), horloge: () => maintenant);
      await frappe(t, '0000');
      await frappe(t, '0000');
      await frappe(t, '0000');
      await t.pumpWidget(const SizedBox());
      await demarrer(t, s, moteurAppaire(), horloge: () => maintenant);
      expect(find.textContaining('réessayez dans 30 s'), findsOneWidget);
      await frappe(t, '1234');
      expect(accueilVisible(), isFalse);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('verrou en cours d\'usage', () {
    Future<void> ouvrirAccueil(WidgetTester t, Stockage s, {DateTime Function()? horloge}) async {
      await demarrer(t, s, moteurAppaire(), horloge: horloge);
      await frappe(t, '1234');
      await t.pumpAndSettle();
      expect(accueilVisible(), isTrue);
    }

    testWidgets('5 minutes sans toucher : le verrou revient, et l\'écran qu\'on avait est retrouvé après le code', (t) async {
      final s = await stockageAvecCode('1234');
      await ouvrirAccueil(t, s);
      await t.tap(find.byKey(const Key('onglet-dossiers')));
      await t.pumpAndSettle();
      await t.pump(const Duration(minutes: 4, seconds: 59));
      expect(find.text('Code PIN'), findsNothing);
      await t.pump(const Duration(seconds: 2));
      await t.pump();
      expect(find.text('Code PIN'), findsOneWidget);
      expect(find.byKey(const Key('identite-agent')), findsOneWidget);
      expect(accueilVisible(), isFalse, reason: 'aucune commande métier accessible tant que verrouillé');
      expect(find.byKey(const Key('patient-p4')), findsNothing);
      await frappe(t, '1234');
      await t.pumpAndSettle();
      expect(find.byKey(const Key('patient-p4')), findsOneWidget, reason: 'retour à l\'onglet qu\'on avait');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('retour d\'arrière-plan après plus de 5 minutes : reverrouillé ; avant 5 minutes : non', (t) async {
      final s = await stockageAvecCode('1234');
      var maintenant = DateTime(2026, 11, 1, 9);
      await ouvrirAccueil(t, s, horloge: () => maintenant);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      maintenant = maintenant.add(const Duration(minutes: 2));
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      expect(find.text('Code PIN'), findsNothing, reason: 'deux minutes dehors : pas de verrou');
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      maintenant = maintenant.add(const Duration(minutes: 6));
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      expect(find.text('Code PIN'), findsOneWidget);
      expect(accueilVisible(), isFalse);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('réinitialiser l\'appairage lève le verrou et ramène à l\'appairage ; le nouvel appairage repasse par le code', (t) async {
      final s = await stockageAvecCode('1234');
      final m = moteurAppaire();
      await demarrer(t, s, m);
      await frappe(t, '1234');
      await t.pumpAndSettle();
      m.profil = null;
      m.etat.value = const EtatMobile(horsLigne: true, enAttente: 1);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('appairer')), findsOneWidget);
      expect(find.text('Code PIN'), findsNothing);
      await t.enterText(find.byKey(const Key('code')), 'abcd2345');
      await t.enterText(find.byKey(const Key('cle')), 'Y2xl');
      await t.enterText(find.byKey(const Key('agent')), 'SOUROU Mariam');
      await t.ensureVisible(find.byKey(const Key('appairer')));
      await t.tap(find.byKey(const Key('appairer')));
      await t.pumpAndSettle();
      expect(find.text('Code PIN'), findsOneWidget, reason: 'le code existe déjà : il est redemandé avant l\'accueil du nouveau profil');
      expect(accueilVisible(), isFalse);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('stockage sécurisé indisponible : repli nommé, jamais un contournement', () {
    testWidgets('la cause est dite, aucun écran métier ni appairage, aucun moteur créé ; le retour du coffre rouvre le démarrage', (t) async {
      final s = Stockage()..panne = true;
      var moteursCrees = 0;
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(Demarrage(stockage: s, creerMoteur: () {
        moteursCrees++;
        return moteurAppaire();
      }, iterationsPin: 1000));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('stockage-titre')), findsOneWidget);
      expect(find.textContaining('keystore_indisponible'), findsOneWidget);
      expect(find.byKey(const Key('appairer')), findsNothing);
      expect(accueilVisible(), isFalse);
      expect(moteursCrees, 0, reason: 'la base locale n\'est pas ouverte sans coffre');
      s.panne = false;
      await t.tap(find.byKey(const Key('stockage-reessayer')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('stockage-titre')), findsNothing);
      expect(moteursCrees, 1);
      expect(find.text('Choisissez un code à 4 chiffres.'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  });
}

String tester(Finder f) => (f.evaluate().single.widget as Text).data ?? '';
