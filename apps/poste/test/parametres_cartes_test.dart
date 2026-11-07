import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// « Relais en ligne » quitte le ruban pour des cartes dans Paramètres système ; l'onglet Système n'est affiché qu'à l'admin et à la DA (arbitrage du 05/11/2026).
Future<void> monter(WidgetTester t, String ecran, {required String role, ModePoste mode = ModePoste.mere}) async {
  t.view.physicalSize = const Size(1600, 1200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(), donnees: donneesNav, config: ConfigPoste(mode: mode, role: role), ecranInitial: ecran, magasin: magasinM14(), horloge: () => aujourdhui));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(chargerPolices);

  casM14('admin sur la mère : le ruban garde Système et Poste mère, plus Relais en ligne', (t) async {
    await monter(t, 'm14-utilisateurs', role: 'admin');
    expect(find.byKey(const Key('domaine-Système')), findsOneWidget);
    expect(find.byKey(const Key('domaine-Poste mère')), findsOneWidget);
    expect(find.byKey(const Key('domaine-Relais en ligne')), findsNothing);
    expect(find.byKey(const Key('domaine-Soins')), findsOneWidget);
  });

  casM14('admin : Paramètres système porte l\'onglet Relais en ligne, une carte par écran du relais', (t) async {
    await monter(t, 'cfg-systeme', role: 'admin');
    await toucherM14(t, find.text('Relais en ligne').last);
    final attendu = donneesNav.manifeste
        .cartesParametres(donneesNav.matrice, 'admin', estMere: true, domaines: const {'Relais en ligne'})
        .expand((d) => d.rangees)
        .expand((r) => r.ecrans)
        .length;
    expect(attendu, greaterThanOrEqualTo(10));
    expect(find.byKey(const Key('groupes-cartes')), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('hub-carte:rls-')), findsNWidgets(attendu));
  });

  casM14('direction : pas d\'onglet Système au ruban ; le profil ouvre la page de cartes, sans aucun écran interdit', (t) async {
    await monter(t, 'm14-utilisateurs', role: 'direction');
    expect(find.byKey(const Key('domaine-Système')), findsNothing);
    expect(find.byKey(const Key('domaine-Relais en ligne')), findsNothing);
    await toucherM14(t, find.byKey(const Key('barre-profil')));
    expect(find.byKey(const Key('profil-lien:parametres-hub')), findsOneWidget);
    await toucherM14(t, find.byKey(const Key('profil-lien:parametres-hub')));
    expect(find.byKey(const Key('groupes-cartes')), findsOneWidget);
    final ids = find
        .byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('hub-carte:'))
        .evaluate()
        .map((e) => '${(e.widget.key as ValueKey).value}'.substring('hub-carte:'.length))
        .toList();
    expect(ids, isNotEmpty);
    expect(ids.every((id) => donneesNav.matrice.peutVoir('direction', id)), true, reason: 'jamais une carte vers un écran interdit (RG-13)');
    expect(ids.any((id) => id.startsWith('rls-')), false, reason: 'le relais est réservé à l\'administrateur');
  });

  casM14('poste FILEUL : ni Poste mère ni Relais en ligne, ni au ruban ni en cartes', (t) async {
    await monter(t, 'm14-utilisateurs', role: 'admin', mode: ModePoste.fileul);
    expect(find.byKey(const Key('domaine-Poste mère')), findsNothing);
    expect(find.byKey(const Key('domaine-Relais en ligne')), findsNothing);
    final cartes = donneesNav.manifeste.cartesParametres(donneesNav.matrice, 'admin', estMere: false, domaines: const {'Système', 'Poste mère', 'Relais en ligne'});
    expect(cartes.map((d) => d.nom), isNot(contains('Relais en ligne')));
    expect(cartes.map((d) => d.nom), isNot(contains('Poste mère')));
  });

  casM14('profil de l\'administrateur : le bouton mène à l\'écran complet cfg-systeme', (t) async {
    await monter(t, 'm14-utilisateurs', role: 'admin');
    await toucherM14(t, find.byKey(const Key('barre-profil')));
    expect(find.byKey(const Key('profil-lien:cfg-systeme')), findsOneWidget);
  });
}
