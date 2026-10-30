import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/modules/module_sigh.dart';
import 'package:sigh_poste/modules/registre.dart';

ClientMere clientVide() => ClientMere(
      base: Uri.parse('http://mere.test'),
      secretAdmin: 's',
      client: MockClient((req) async => http.Response('{"epoch":1,"seq_max":0,"appareils":[],"etat":"ok","controles":[]}', 200)),
    );

Future<void> monter(WidgetTester t, SighPoste app) async {
  t.view.physicalSize = const Size(1400, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(app);
  await t.pump();
}

void main() {
  test('le registre : un module de la mère n\'est JAMAIS visible d\'un fileul, la mère voit tout', () {
    final tous = [...modulesCommuns(), ...modulesMere(clientVide())];
    final fileul = modulesVisibles(const ConfigPoste(mode: ModePoste.fileul), tous: tous);
    final mere = modulesVisibles(const ConfigPoste(mode: ModePoste.mere), tous: tous);
    expect(fileul.map((m) => m.id), ['accueil-poste']);
    expect(mere.map((m) => m.id), containsAll(fileul.map((m) => m.id)));
    expect(mere.length, fileul.length + 5);
    expect(mere.where((m) => m.id.startsWith('mere-')).length, 5);
  });

  test('le filtre de droits retire un module du mode sans le rendre accessible à un autre', () {
    final tous = [...modulesCommuns(), ...modulesMere(clientVide())];
    final v = modulesVisibles(const ConfigPoste(mode: ModePoste.mere), tous: tous, droit: (m) => m.id != 'mere-maintenance');
    expect(v.any((m) => m.id == 'mere-maintenance'), isFalse);
    expect(v.any((m) => m.id == 'mere-conflits'), isTrue);
  });

  testWidgets('poste fileul : annonce son mode, aucun module de la mère dans la navigation', (t) async {
    await monter(t, const SighPoste(config: ConfigPoste(mode: ModePoste.fileul)));
    expect(find.text('SIGH-CNT — poste fileul'), findsOneWidget);
    expect(find.text('Accueil du poste'), findsOneWidget);
    for (final libelle in ['Supervision', 'Appareils', 'Conflits', 'Journal technique', 'Maintenance']) {
      expect(find.text(libelle), findsNothing, reason: libelle);
    }
    expect(find.textContaining('Hors ligne'), findsOneWidget);
  });

  testWidgets('poste mère : mêmes modules communs PLUS les siens, on navigue de l\'un à l\'autre', (t) async {
    await monter(t, SighPoste(config: const ConfigPoste(mode: ModePoste.mere), client: clientVide()));
    expect(find.text('SIGH-CNT — poste mère'), findsOneWidget);
    expect(find.text('Accueil du poste'), findsOneWidget);
    for (final libelle in ['Supervision', 'Appareils', 'Conflits', 'Journal technique', 'Maintenance']) {
      expect(find.text(libelle), findsOneWidget, reason: libelle);
    }
    await t.tap(find.text('Journal technique'));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Aucun évènement enregistré.'), findsOneWidget);
  });

  testWidgets('aucun module ouvert au profil : le dit, pas d\'écran blanc', (t) async {
    await monter(t, const SighPoste(config: ConfigPoste(mode: ModePoste.fileul), droit: _aucun));
    expect(find.text('Aucun module n’est ouvert à votre profil.'), findsOneWidget);
  });
}

bool _aucun(ModuleSigh m) => false;
