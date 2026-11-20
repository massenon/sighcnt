import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/modules/cfg/cfb_systeme.dart' show EcranSysteme;
import 'package:sigh_poste/shell/centre_notifications.dart';
import 'package:sigh_poste/shell/son_alertes.dart';

import 'aide_polices.dart';

/// Direction du 02/11/2026 : la sonorisation des alertes (elle ne sonnait jamais : seul le bouton « Tester » jouait un son) et le menu contextuel « Actualiser ».
final donnees = DonneesNavigation.depuisDossier();
final auj = DateTime(2026, 11, 2, 9);

Magasin magasin({bool son = true, String profil = 'standard', int tempo = 30, String priorite = 'haute'}) => Magasin({
      'notifications': [
        {'id': 'N1', 'statut': 'actif', 'titre': 'Résultat à relire', 'priorite': priorite, 'poste': 'tous'},
      ],
      'reglages': [
        {'id': 'notificationsSon', 'statut': 'actif', 'valeur': {'son': son, 'profil': profil, 'temporisation': tempo}},
      ],
      'rbac': const [],
    });

CentreNotifications centre(Magasin m, DateTime Function() h) => CentreNotifications(magasin: m, donnees: () => donnees, role: () => 'admin', horloge: h);

void main() {
  setUpAll(chargerPolices);

  group('sonorisation des alertes', () {
    test('une alerte nouvelle fait sonner ; la même ne resonne pas avant la temporisation, puis resonne', () async {
      var h = auj;
      final m = magasin(tempo: 30);
      final sons = <bool>[];
      final s = SonAlertes(centre(m, () => h), horloge: () => h, disponible: () => true, jouer: ({bool fort = false}) async {
        sons.add(fort);
        return true;
      });
      s.demarrer();
      await Future<void>.delayed(Duration.zero);
      expect(s.sonneries, 1, reason: 'une alerte non acquittée sonne à l’arrivée');
      m.collection('reglages').mettreAJour('notificationsSon', {'valeur': {'son': true, 'profil': 'standard', 'temporisation': 30}});
      expect(s.sonneries, 1, reason: 'la même alerte ne resonne pas à chaque passage');
      h = auj.add(const Duration(minutes: 31));
      m.collection('reglages').mettreAJour('notificationsSon', {'valeur': {'son': true, 'profil': 'standard', 'temporisation': 30}});
      expect(s.sonneries, 2, reason: 'après la temporisation, une alerte persistante resonne');
      m.collection('notifications').inserer({'id': 'N2', 'statut': 'actif', 'titre': 'Autre', 'priorite': 'haute', 'poste': 'tous'});
      expect(s.sonneries, 3, reason: 'une alerte nouvelle sonne tout de suite');
      s.arreter();
    });

    test('son désactivé, profil silencieux, canal indisponible : aucun son, l’alerte demeure', () async {
      for (final (m, dispo) in [(magasin(son: false), true), (magasin(profil: 'silencieux'), true), (magasin(), false)]) {
        final s = SonAlertes(centre(m, () => auj), horloge: () => auj, disponible: () => dispo, jouer: ({bool fort = false}) async => true)..demarrer();
        await Future<void>.delayed(Duration.zero);
        expect(s.sonneries, 0);
        expect(centre(m, () => auj).collecter(), isNotEmpty, reason: 'cloche et badge continuent');
        s.arreter();
      }
    });

    test('une alerte acquittée ne sonne pas (entendre n’est pas traiter) ; le profil « critique » ignore les alertes ordinaires', () async {
      final m = magasin();
      final c = centre(m, () => auj);
      c.acquitter(c.collecter().first);
      final s = SonAlertes(c, horloge: () => auj, disponible: () => true, jouer: ({bool fort = false}) async => true)..demarrer();
      await Future<void>.delayed(Duration.zero);
      expect(s.sonneries, 0);
      s.arreter();
      final m2 = magasin(profil: 'critique', priorite: 'normale');
      final s2 = SonAlertes(centre(m2, () => auj), horloge: () => auj, disponible: () => true, jouer: ({bool fort = false}) async => true)..demarrer();
      await Future<void>.delayed(Duration.zero);
      expect(s2.sonneries, 0, reason: 'une alerte ordinaire n’est pas critique');
      final m3 = magasin(profil: 'critique', priorite: 'haute');
      final s3 = SonAlertes(centre(m3, () => auj), horloge: () => auj, disponible: () => true, jouer: ({bool fort = false}) async => true)..demarrer();
      await Future<void>.delayed(Duration.zero);
      expect(s3.sonneries, 1, reason: 'une alerte grave sonne même au profil critique');
      s3.arreter();
      s2.arreter();
    });

    test('une panne du lecteur ne casse rien', () async {
      final s = SonAlertes(centre(magasin(), () => auj), horloge: () => auj, disponible: () => true, jouer: ({bool fort = false}) async => throw StateError('pas de carte son'))..demarrer();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(s.sonneries, 1);
      s.arreter();
    });
  });

  testWidgets('clic droit : le menu « Actualiser » reconstruit l’écran courant et le dit', (t) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(SighPoste(
        key: UniqueKey(),
        donnees: donnees,
        config: const ConfigPoste(mode: ModePoste.fileul, role: 'admin'),
        ecranInitial: 'cfg-systeme',
        magasin: Magasin.depuisDossier([...Magasin.collectionsDuJeu]),
        horloge: () => auj));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final avant = t.state(find.byType(EcranSysteme));
    final g = await t.startGesture(const Offset(800, 500), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await g.up();
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('menu-actualiser')), findsOneWidget);
    await t.tap(find.text('Actualiser'));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('Écran actualisé.'), findsOneWidget);
    expect(identical(t.state(find.byType(EcranSysteme)), avant), isFalse, reason: 'l’écran est reconstruit');
    // F5 fait la même chose.
    final apres = t.state(find.byType(EcranSysteme));
    await t.sendKeyEvent(LogicalKeyboardKey.f5);
    await t.pump(const Duration(milliseconds: 400));
    expect(identical(t.state(find.byType(EcranSysteme)), apres), isFalse);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 10));
    ToastsSigh.viderPourTests();
  });
}
