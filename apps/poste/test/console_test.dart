import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/mere/console.dart';

/// Faux service de la mère : enregistre les appels reçus et répond comme le vrai (mêmes champs, mêmes refus nommés).
class FauxService {
  final List<String> appels = [];
  Map<String, Object?> etat = {
    'epoch': 3, 'seq_max': 120, 'rep_seq': 100, 'conflits_ouverts': 2, 'reinit_ouverte': false, 'derives': ['u-2'], 'bloques': [],
    'alertes': [
      {'type': 'authentification', 'appareil': 'u-1', 'n': 4, 'quand': 0}
    ],
    'appareils': [
      {'uuid': 'u-1', 'etiquette': 'Caisse', 'role': 'fileul', 'etat': 'actif', 'dernier_contact': 1000, 'dernier_seq': 118, 'derive_ms': 0},
      {'uuid': 'u-2', 'etiquette': 'Dr Yeni', 'role': 'mobile', 'etat': 'actif', 'dernier_contact': null, 'dernier_seq': 90, 'derive_ms': 700000},
      {'uuid': 'u-3', 'etiquette': 'Ancien', 'role': 'fileul', 'etat': 'revoque', 'dernier_contact': 5, 'dernier_seq': 3, 'derive_ms': 0},
    ],
  };
  List<Map<String, Object?>> conflits = [
    {'id': 7, 'collection': 'patients', 'fiche': 'p1', 'champ': 'telephone', 'a': '"222"', 'b': '"333"', 'etat': 'ouvert'},
    {'id': 8, 'collection': 'patients', 'fiche': 'p9', 'champ': 'doublon_possible', 'a': '"p1"', 'b': '"p9"', 'etat': 'ouvert'},
    {'id': 9, 'collection': 'patients', 'fiche': 'p5', 'champ': 'nom', 'a': '"x"', 'b': '"y"', 'etat': 'tranche'},
  ];
  Map<String, Object?>? refus;

  http.Client client() => MockClient((req) async {
        appels.add('${req.method} ${req.url.path}${req.body.isEmpty ? '' : ' ${req.body}'}');
        if (req.headers['x-admin'] != 'secret') return http.Response(jsonEncode({'code': 'admin_requis', 'motif': 'Accès administrateur requis.'}), 403);
        if (refus != null && req.method == 'POST') return http.Response(jsonEncode(refus), 422);
        switch ('${req.method} ${req.url.path}') {
          case 'GET /admin/etat':
            return http.Response(jsonEncode(etat), 200);
          case 'GET /admin/conflits':
            return http.Response(jsonEncode(conflits), 200);
          case 'POST /admin/code':
            return http.Response(jsonEncode({'code': 'ABCD2345'}), 200);
          case 'POST /admin/code-mobile':
            return http.Response(jsonEncode({'code': 'MOBI9999', 'cle': 'Y2xlLWRlLWNsaW5pcXVl'}), 200);
          default:
            return http.Response(jsonEncode({'ok': true}), 200);
        }
      });
}

Future<FauxService> monter(WidgetTester t, {FauxService? faux}) async {
  final f = faux ?? FauxService();
  t.view.physicalSize = const Size(1400, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(MaterialApp(
    home: ConsoleMere(
      client: ClientMere(base: Uri.parse('http://mere.test'), secretAdmin: 'secret', client: f.client()),
      intervalle: const Duration(hours: 1),
      maintenant: () => DateTime.fromMillisecondsSinceEpoch(61000),
    ),
  ));
  await t.pumpAndSettle();
  return f;
}

void main() {
  testWidgets('supervision : époque, opérations, retard vers le relais, conflits, alertes nommées', (t) async {
    await monter(t);
    expect(find.text('3'), findsOneWidget); // époque
    expect(find.text('120'), findsOneWidget);
    expect(find.text('20'), findsOneWidget); // retard 120 − 100
    expect(find.text('2'), findsOneWidget); // conflits ouverts
    expect(find.textContaining('Enveloppe altérée'), findsOneWidget);
    expect(find.textContaining('Horloge à vérifier'), findsOneWidget);
  });

  testWidgets('appareils : liste, retard par appareil, horloge à vérifier, révoqué sans bouton', (t) async {
    final f = await monter(t);
    await t.tap(find.text('Appareils'));
    await t.pumpAndSettle();
    expect(find.text('Caisse'), findsOneWidget);
    expect(find.textContaining('retard : 2 op.'), findsOneWidget);
    expect(find.textContaining('HORLOGE À VÉRIFIER'), findsOneWidget);
    expect(find.text('Révoqué'), findsOneWidget);
    expect(find.text('Révoquer'), findsNWidgets(2)); // un par appareil actif
    await t.tap(find.text('Révoquer').first);
    await t.pumpAndSettle();
    expect(find.text('Révoquer cet appareil ?'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Révoquer'));
    await t.pumpAndSettle();
    expect(f.appels.any((a) => a.startsWith('POST /admin/revoquer') && a.contains('u-1')), isTrue);
  });

  testWidgets('appairer un poste : le code s\'affiche, à usage unique', (t) async {
    final f = await monter(t);
    await t.tap(find.text('Appareils'));
    await t.pumpAndSettle();
    await t.tap(find.text('Appairer un poste'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Réception');
    await t.tap(find.text('Générer le code'));
    await t.pumpAndSettle();
    expect(find.text('ABCD2345'), findsOneWidget);
    expect(find.textContaining('usage unique'), findsOneWidget);
    expect(f.appels.any((a) => a.contains('/admin/code ') && a.contains('Réception')), isTrue);
  });

  testWidgets('appairer un mobile : le code ET la clé de clinique s\'affichent', (t) async {
    await monter(t);
    await t.tap(find.text('Appareils'));
    await t.pumpAndSettle();
    await t.tap(find.text('Appairer un mobile'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Dr Yeni');
    await t.tap(find.text('Générer le code'));
    await t.pumpAndSettle();
    expect(find.text('MOBI9999'), findsOneWidget);
    expect(find.text('Y2xlLWRlLWNsaW5pcXVl'), findsOneWidget);
    expect(find.textContaining('ne jamais l’envoyer par messagerie'), findsOneWidget);
  });

  testWidgets('conflits : seuls les conflits OUVERTS ; garder B et classer un doublon appellent la mère', (t) async {
    final f = await monter(t);
    await t.tap(find.text('Conflits'));
    await t.pumpAndSettle();
    expect(find.textContaining('champ « telephone »'), findsOneWidget);
    expect(find.textContaining('Doublon possible'), findsOneWidget);
    expect(find.textContaining('« nom »'), findsNothing); // le conflit tranché n'est pas affiché
    await t.tap(find.text('Garder B'));
    await t.pumpAndSettle();
    expect(f.appels.any((a) => a.startsWith('POST /admin/trancher') && a.contains('"id":7') && a.contains('"decision":"b"')), isTrue);
    await t.tap(find.text('Classer sans fusion'));
    await t.pumpAndSettle();
    expect(f.appels.any((a) => a.startsWith('POST /admin/trancher') && a.contains('"id":8') && a.contains('"decision":"a"')), isTrue);
  });

  testWidgets('maintenance : fenêtre fermée → la réinitialisation est ABSENTE ; ouverte → saisie préservée', (t) async {
    final f = await monter(t);
    await t.tap(find.text('Maintenance'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Réinitialiser'), findsNothing);
    expect(find.textContaining('absente, pas grisée'), findsOneWidget);
    f.etat = {...f.etat, 'reinit_ouverte': true};
    await t.tap(find.byType(Switch)); // la mère répond ensuite « ouverte »
    await t.pumpAndSettle();
    expect(f.appels.any((a) => a.startsWith('POST /admin/reinit-fenetre')), isTrue);
    expect(find.widgetWithText(FilledButton, 'Réinitialiser'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'Tapez le nom de la clinique pour confirmer'), 'NASSIERA TOO');
    await t.enterText(find.widgetWithText(TextField, 'Second profil confirmant (DAF ou Direction)'), 'DAF');
    await t.tap(find.widgetWithText(FilledButton, 'Réinitialiser'));
    await t.pumpAndSettle();
    expect(f.appels.any((a) => a.startsWith('POST /admin/reinitialiser') && a.contains('NASSIERA TOO') && a.contains('DAF')), isTrue);
  });

  testWidgets('un refus de la mère s\'affiche avec SA cause, sans reformulation', (t) async {
    final f = await monter(t);
    f.refus = {'code': 'second_profil_requis', 'motif': 'Un second profil (DAF ou Direction) doit confirmer.'};
    await t.tap(find.text('Maintenance'));
    await t.pumpAndSettle();
    await t.tap(find.text('Renvoyer'));
    await t.pumpAndSettle();
    expect(find.textContaining('second_profil_requis'), findsOneWidget);
    expect(find.textContaining('Un second profil (DAF ou Direction) doit confirmer.'), findsOneWidget);
  });

  testWidgets('service injoignable : bandeau explicite, pas de page blanche', (t) async {
    final client = ClientMere(base: Uri.parse('http://mere.test'), secretAdmin: 'secret', client: MockClient((_) async => throw Exception('connexion refusée')));
    await t.pumpWidget(MaterialApp(home: ConsoleMere(client: client, intervalle: const Duration(hours: 1))));
    await t.pump();
    await t.pump();
    expect(find.textContaining('Le service de la mère ne répond pas'), findsOneWidget);
  });
}
