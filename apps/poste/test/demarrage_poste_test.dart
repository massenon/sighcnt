// LE DÉMARRAGE DU POSTE (Direction, 01/11/2026) : connexion activée par défaut, plein écran, pied de page légal.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/modules/auth/acc_session.dart';
import 'package:sigh_poste/shell/fenetre_poste.dart';

import 'aide_polices.dart';

const _mention = 'CLINIQUE NASSIERA TOO SARL — IFU 3201642748214 — RCCM RB/NAT/2016-B-268.';

void main() {
  setUpAll(chargerPolices);
  final donnees = DonneesNavigation.depuisDossier();
  var maintenant = DateTime(2026, 11, 1, 9);

  Future<SessionPoste?> monter(WidgetTester t,
      {SessionPoste? session, FenetrePoste? fenetre, String? ecran, String role = 'da'}) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(SighPoste(
        key: UniqueKey(),
        donnees: donnees,
        config: ConfigPoste(mode: ModePoste.fileul, role: role),
        ecranInitial: ecran,
        magasin: Magasin.depuisDossier(Magasin.collectionsDuJeu),
        session: session,
        fenetre: fenetre,
        horloge: () => maintenant));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    return session;
  }

  Future<void> fin(WidgetTester t) async {
    ToastsSigh.viderPourTests();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 10));
  }

  group('1. connexion activée par défaut', () {
    test('la constante de démarrage exige la connexion ; seul SIGH_CONNEXION=non la retire', () {
      expect(connexionExigee, 'oui');
      expect(sessionDemarrage(), isNotNull);
      expect(sessionDemarrage()!.exigeConnexion, isTrue);
      expect(sessionDemarrage()!.etat, EtatSession.deconnectee);
      expect(sessionDemarrage(connexion: 'non'), isNull, reason: 'l\'ancien mode sans connexion ne reste qu\'en test');
    });

    testWidgets('le poste démarre sur la page de connexion de la maquette (index) : identifiant, mot de passe avec oeil, oubli, souvenir, bouton', (t) async {
      await monter(t, session: sessionDemarrage(horloge: () => maintenant));
      expect(find.byKey(const Key('barre-superieure')), findsNothing, reason: 'la connexion est servie sans barre');
      expect(find.text('Identifiant'), findsOneWidget);
      expect(find.text('Mot de passe'), findsOneWidget);
      expect(find.byKey(const Key('acces:oeil')), findsOneWidget);
      expect(find.text('Mot de passe oublié ?'), findsOneWidget);
      expect(find.text('Se souvenir de ce poste'), findsNothing, reason: 'case retirée : elle ne retenait rien (fausse sauvegarde)');
      expect(find.text('Se connecter'), findsOneWidget);
      await fin(t);
    });

    testWidgets('après la connexion : le tableau de bord du rôle et le modal « À votre arrivée » ; le verrou de 15 minutes joue dans ce mode par défaut', (t) async {
      maintenant = DateTime(2026, 11, 1, 9);
      final s = sessionDemarrage(horloge: () => maintenant)!;
      await monter(t, session: s);
      s.connecter(const AccCompte(identifiant: 'da', nom: 'GBEDJI Hervé', role: 'da'));
      await t.pump();
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 150));
      }
      expect(find.byKey(const Key('barre-superieure')), findsOneWidget, reason: 'la coque du rôle s\'ouvre');
      expect(find.byKey(const Key('kit:modale-titre')), findsOneWidget);
      expect(find.text('À votre arrivée'), findsOneWidget, reason: 'le modal de notifications d\'ouverture');
      await t.tap(find.text('J’ai pris connaissance'));
      await t.pumpAndSettle();
      // Quinze minutes d'inactivité (horloge injectée) : le minuteur de 2 s de la coque verrouille la session.
      maintenant = maintenant.add(const Duration(minutes: 16));
      await t.pump(const Duration(seconds: 3));
      await t.pump(const Duration(milliseconds: 300));
      expect(s.etat, EtatSession.verrouillee, reason: 'le verrou fonctionne avec la connexion par défaut');
      await fin(t);
    });
  });

  group('2. plein écran au démarrage', () {
    test('le démarrage est MAXIMISÉ par défaut (barre des tâches visible) ; F11 et la barre basculent en plein écran', () {
      expect(pleinEcranAuDemarrage, 'non');
    });

    test('FenetreMemoire : le démarrage passe en plein écran, ou nomme son repli', () async {
      final ok = FenetreMemoire();
      await ok.demarrerPleinEcran();
      expect(ok.pleinEcran.value, isTrue);
      expect(ok.refusDemarrage, isNull);
      final refus = FenetreMemoire(refuse: true);
      await refus.demarrerPleinEcran();
      expect(refus.pleinEcran.value, isFalse);
      expect(refus.refusDemarrage, contains('Plein écran indisponible'));
      expect(refus.refusDemarrage, contains('F11'));
    });

    testWidgets('si la plateforme refuse, la coque le DIT au premier affichage (message du kit), sans bloquer le travail', (t) async {
      final refus = FenetreMemoire(refuse: true);
      await refus.demarrerPleinEcran();
      await monter(t, fenetre: refus);
      expect(find.textContaining('Plein écran indisponible sur ce poste'), findsOneWidget);
      expect(find.byKey(const Key('barre-superieure')), findsOneWidget);
      await fin(t);
    });

    testWidgets('quand le plein écran réussit, aucun message', (t) async {
      final ok = FenetreMemoire();
      await ok.demarrerPleinEcran();
      await monter(t, fenetre: ok);
      expect(find.textContaining('Plein écran indisponible'), findsNothing);
      await fin(t);
    });
  });

  group('3. pied de page légal', () {
    test('le texte exact de la Direction, lu de l\'identité unique', () {
      expect(IdentiteClinique.mentionLegale, _mention);
    });

    test('la maquette porte le même pied (core.js : C.mentionLegale, lu de C.BRAND), sur la coque et les pages autonomes', () {
      final core = File('../../prototype_html/assets/js/core.js').readAsStringSync();
      expect(core, contains("BRAND.nom + ' — IFU ' + BRAND.ifu + ' — RCCM ' + BRAND.rccm + '.'"));
      final app = File('../../prototype_html/assets/js/app.js').readAsStringSync();
      expect(RegExp(r"C\.mentionLegale\(\)").allMatches(app).length, 2, reason: 'une fois dans la coque, une fois sur les pages autonomes');
      expect(app, isNot(contains('Prototype SIGH-CNT, jeu de données')));
    });

    test('la mention n\'est écrite en dur nulle part ailleurs dans lib/', () {
      final fautes = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        // La règle d'écran de `cfg-entetes` reprend mot pour mot celle de la maquette (parité N1) : c'est un texte, pas une seconde source de l'identité.
        if (f.path.endsWith('cfa_identite.dart')) continue;
        final lignes = f.readAsLinesSync();
        for (var i = 0; i < lignes.length; i++) {
          if (lignes[i].contains('3201642748214') && !lignes[i].trimLeft().startsWith('//')) fautes.add('${f.path}:${i + 1}');
        }
      }
      expect(fautes, isEmpty, reason: 'l\'IFU se lit de IdentiteClinique : $fautes');
    });

    testWidgets('sur tous les écrans de la coque : accueil du rôle, hub de module, écran ordinaire, activité fermée', (t) async {
      for (final ecran in [null, 'hub-m8', 'm8-caisse', 'm2-agenda']) {
        await monter(t, ecran: ecran);
        expect(find.byKey(const Key('pied-legal')), findsOneWidget, reason: '${ecran ?? 'accueil'} : pied absent');
        expect(find.byKey(const Key('pied-legal:texte')), findsOneWidget);
        expect((t.widget(find.byKey(const Key('pied-legal:texte'))) as Text).data, _mention);
        await fin(t);
      }
    });

    testWidgets('sur les pages autonomes : connexion, mot de passe oublié, plan du site, erreur 404', (t) async {
      for (final ecran in ['index', 'auth-forgot', 'plan-du-site', 'error-404']) {
        await monter(t, ecran: ecran, session: SessionPoste(exigeConnexion: true, horloge: () => maintenant));
        expect(find.byKey(const Key('pied-legal')), findsOneWidget, reason: '$ecran : pied absent');
        expect((t.widget(find.byKey(const Key('pied-legal:texte'))) as Text).data, _mention);
        await fin(t);
      }
    });
  });
}
