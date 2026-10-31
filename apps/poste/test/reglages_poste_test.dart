import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/controleur_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/mere/activation.dart';
import 'package:sigh_poste/mere/client_mere.dart';

import 'activation_test.dart' show FauxService;

/// Relais simulé qui applique la règle du vrai : une seule mère.
RelaisMere relaisUnique(List<String> journal, {String? dejaActive}) =>
    RelaisMereHttp(
      base: Uri.parse('https://relais.test'),
      secretMere: 's3cret',
      client: MockClient((req) async {
        journal.add('${req.method} ${req.url.path} ${req.headers['x-mere']}');
        if (dejaActive != null && req.url.path == '/mere/activer') {
          return http.Response(
              '{"code":"mere_deja_active","motif":"Une mère est déjà active : « $dejaActive »."}',
              409);
        }
        return http.Response('{"ok":true}', 200);
      }),
    );

final donnees = DonneesNavigation.depuisDossier();

ControleurPoste controleur(
    {String? dejaActive, List<String>? journal, FauxService? service}) {
  final j = journal ?? <String>[];
  final act = ActivationMere(
      stockage: StockageMemoire(),
      service: service ?? FauxService(),
      relaisPour: (_, __) => relaisUnique(j, dejaActive: dejaActive));
  return ControleurPoste(
      activation: act,
      config: const ConfigPoste(mode: ModePoste.fileul, role: 'admin'));
}

Future<void> monter(WidgetTester t, ControleurPoste c) async {
  t.view.physicalSize = const Size(1800, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      donnees: donnees,
      controleur: c,
      client: ClientMere(base: Uri.parse('http://x'), secretAdmin: 's')));
  await t.pump();
}

/// « Système » → « Ce poste (mode fileul / mère) » : le geste de l'agent dans le ruban.
Future<void> ouvrirPoste(WidgetTester t) async {
  await t.tap(find.byKey(const Key('domaine-Système')));
  await t.pump();
  await t.tap(find.byKey(const Key('pastille-cfg-poste')));
  await t.pumpAndSettle();
}

Future<void> remplir(WidgetTester t) async {
  await t.enterText(find.byKey(const Key('relais')), 'https://relais.test');
  await t.enterText(find.byKey(const Key('secret')), 's3cret');
  await t.enterText(find.byKey(const Key('cle')), 'CLE-DE-CLINIQUE-0123456789');
}

void main() {
  testWidgets(
      'un poste FILEUL activé devient MÈRE sans recompiler : les modules « Poste mère » apparaissent',
      (t) async {
    final c = controleur();
    await monter(t, c);
    expect(find.byKey(const Key('domaine-Poste mère')), findsNothing);
    await ouvrirPoste(t);
    expect(find.text('Ce poste est un poste fileul'), findsOneWidget);
    await remplir(t);
    await t.tap(find.byKey(const Key('activer')));
    await t.pumpAndSettle();
    expect(find.text('SIGH — poste mère'), findsOneWidget);
    expect(find.byKey(const Key('domaine-Poste mère')), findsOneWidget);
    expect(find.byKey(const Key('domaine-Soins')), findsOneWidget,
        reason: 'la mère garde les domaines du fileul');
  });

  testWidgets(
      'une mère déjà active : le refus du relais s\'affiche TEL QUEL, le poste reste fileul',
      (t) async {
    final c = controleur(dejaActive: 'Serveur DAF');
    await monter(t, c);
    await ouvrirPoste(t);
    await remplir(t);
    await t.tap(find.byKey(const Key('activer')));
    await t.pumpAndSettle();
    expect(find.textContaining('Serveur DAF'), findsOneWidget);
    expect(find.text('SIGH — Gestion hospitalière'), findsOneWidget);
    expect(find.byKey(const Key('domaine-Poste mère')), findsNothing);
    expect(find.byKey(const Key('remplacer')), findsOneWidget,
        reason: 'la reprise explicite n\'est proposée qu\'après ce refus');
  });

  testWidgets('la reprise explicite n\'est PAS proposée d\'emblée', (t) async {
    await monter(t, controleur());
    await ouvrirPoste(t);
    expect(find.byKey(const Key('remplacer')), findsNothing);
  });

  testWidgets(
      'une clé de clinique trop courte est refusée en la nommant, sans appeler le relais',
      (t) async {
    final journal = <String>[];
    await monter(t, controleur(journal: journal));
    await ouvrirPoste(t);
    await t.enterText(find.byKey(const Key('relais')), 'https://relais.test');
    await t.enterText(find.byKey(const Key('secret')), 's3cret');
    await t.enterText(find.byKey(const Key('cle')), 'courte');
    await t.tap(find.byKey(const Key('activer')));
    await t.pumpAndSettle();
    expect(
        find.textContaining('clé de clinique est obligatoire'), findsOneWidget);
    expect(journal, isEmpty);
  });

  testWidgets(
      'désactivation : le poste redevient fileul et les modules de la mère disparaissent',
      (t) async {
    final c = controleur();
    await monter(t, c);
    await ouvrirPoste(t);
    await remplir(t);
    await t.tap(find.byKey(const Key('activer')));
    await t.pumpAndSettle();
    await ouvrirPoste(t);
    await t.enterText(find.byKey(const Key('secret')), 's3cret');
    await t.tap(find.byKey(const Key('desactiver')));
    await t.pumpAndSettle();
    expect(find.text('SIGH — Gestion hospitalière'), findsOneWidget);
    expect(find.byKey(const Key('domaine-Poste mère')), findsNothing);
  });

  testWidgets(
      'un agent sans droit d\'administrer (caissier) ne voit pas « Ce poste »',
      (t) async {
    final act = ActivationMere(
        stockage: StockageMemoire(),
        service: FauxService(),
        relaisPour: (_, __) => relaisUnique([]));
    final c = ControleurPoste(
        activation: act,
        config: const ConfigPoste(mode: ModePoste.fileul, role: 'caissier'));
    await monter(t, c);
    expect(find.byKey(const Key('domaine-Système')), findsNothing,
        reason: 'le caissier n\'a pas « Ce poste »');
    expect(find.byKey(const Key('domaine-Financier')), findsOneWidget);
  });
}
