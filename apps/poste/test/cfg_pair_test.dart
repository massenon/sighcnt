import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sigh_poste/sync/recuperation_cle.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/sync/config_pair.dart';
import 'package:sigh_poste/sync/etat_pair.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// cfg-pair : le réglage du mode pair d'un poste (ADR-0006). Ce que l'écran écrit dans `pair.json`, la clé qui ne s'affiche qu'UNE fois, les refus nommés
/// (adresse sans schéma, activation sans clé, phrase secrète trop courte), le droit (admin et DAF seulement), et la récupération par courriel fermée par défaut.
void main() {
  late Map<String, Object?> coffreFixe;
  setUpAll(() async {
    await chargerPolices();
    // un VRAI coffre, fabriqué hors de l'horloge simulée des tests de widgets (la dérivation PBKDF2 y resterait suspendue)
    coffreFixe = await RecuperationCle.fabriquerCoffre('ab' * 32, 'phrase assez longue');
  });
  tearDown(() {
    ToastsSigh.viderPourTests();
    EtatPairPoste.dossier = null;
    EtatPairPoste.source = null;
  });

  late Directory d;
  setUp(() {
    d = Directory.systemTemp.createTempSync('cfg-pair');
    EtatPairPoste.dossier = d.path;
  });
  tearDown(() => d.deleteSync(recursive: true));

  Map<String, Object?> fichier() => ConfigPairPoste.lireBrut(d.path);
  final enregistrer = find.widgetWithText(BoutonSigh, 'Enregistrer la configuration');

  casM14('ouverture : désactivé, non appairé, récupération par courriel FERMÉE (ni courriel ni phrase secrète)', (t) async {
    await ouvrirM14(t, magasinM14(), 'cfg-pair');
    for (final k in ['Mode pair', 'Appairage', 'Conflits à trancher', 'Opérations en attente', 'Configuration du mode pair', 'Clé unique de la clinique', 'Récupération de la clé par courriel', 'État du mode pair', 'Désactivé', 'Non appairé']) {
      expect(find.text(k), findsWidgets, reason: k);
    }
    expect(find.byKey(const Key('kit:champ:courriel')), findsNothing);
    expect(find.byKey(const Key('kit:champ:phrase')), findsNothing);
    expect(find.widgetWithText(BoutonSigh, 'Générer la clé'), findsOneWidget);
    expect(fichier(), isEmpty, reason: 'rien n’est écrit tant qu’on n’a rien fait');
  });

  casM14('adresse sans http(s) refusée, activation sans clé refusée : en le disant, rien n’est écrit', (t) async {
    await ouvrirM14(t, magasinM14(), 'cfg-pair');
    await saisir(t, 'relais', 'relais-sans-schema');
    await saisir(t, 'nom', 'Poste test');
    await toucherM14(t, enregistrer);
    expect(find.text('L’adresse du relais doit commencer par http:// ou https://.'), findsOneWidget);
    expect(fichier(), isEmpty);
    ToastsSigh.viderPourTests();
    await saisir(t, 'relais', 'https://relais.exemple.bj/');
    await toucherM14(t, find.text('Activer le mode pair sur ce poste'));
    await toucherM14(t, enregistrer);
    expect(find.textContaining('Générer d’abord la clé unique'), findsOneWidget);
    expect(fichier()['actif'], isNot(true));
  });

  casM14('la clé : 256 bits affichés UNE fois, copiables, puis plus jamais ; la nouvelle clé se confirme', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-pair');
    await toucherM14(t, find.byKey(const Key('pair:generer')));
    final cle = (t.widget<SelectableText>(find.byKey(const Key('pair:cle')))).data!;
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(cle), isTrue, reason: cle);
    expect(fichier()['cle'], cle, reason: 'le moteur lira la clé dans pair.json');
    expect(find.text('Copier la clé'), findsOneWidget);
    expect(m.collection('audit').toutes.any((a) => a['entite'] == 'Clé du mode pair' && jsonEncode(a).contains(cle) == false), isTrue, reason: 'journalisée, sans la clé');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'J’ai noté la clé'));
    expect(find.byKey(const Key('pair:cle')), findsNothing);
    expect(find.textContaining(cle), findsNothing);
    expect(find.textContaining('n’est plus affichée'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Générer une nouvelle clé'), findsOneWidget);
  });

  casM14('avec relais, nom et clé : le mode s’active ; l’adresse est normalisée, le code d’appairage est écrit pour le premier lancement', (t) async {
    ConfigPairPoste.ecrire(d.path, cleHex: ConfigPairPoste.genererCle());
    await ouvrirM14(t, magasinM14(), 'cfg-pair');
    await saisir(t, 'relais', 'https://relais.exemple.bj/');
    await saisir(t, 'nom', 'Poste test');
    await saisir(t, 'code', 'ABC123');
    await toucherM14(t, find.text('Activer le mode pair sur ce poste'));
    await toucherM14(t, enregistrer);
    final f = fichier();
    expect([f['actif'], f['relais'], f['nom'], f['code']], [true, 'https://relais.exemple.bj', 'Poste test', 'ABC123']);
    expect(ConfigPairPoste.lire(d.path)?.relais, 'https://relais.exemple.bj', reason: 'le fichier écrit par l’écran est celui que main.dart sait lire');
  });

  casM14('récupération par courriel : ouvrir le réglage fait paraître courriel et phrase secrète ; phrase trop courte refusée ; la phrase n’est jamais écrite', (t) async {
    ConfigPairPoste.ecrire(d.path, cleHex: ConfigPairPoste.genererCle());
    await ouvrirM14(t, magasinM14(), 'cfg-pair');
    await toucherM14(t, find.text('Permettre la récupération de la clé par courriel'));
    expect(fichier()['recuperation'], true);
    expect(find.byKey(const Key('kit:champ:courriel')), findsOneWidget);
    expect(find.byKey(const Key('kit:champ:phrase')), findsOneWidget);
    await saisir(t, 'courriel', 'dg@clinique.bj');
    await saisir(t, 'phrase', 'court');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Envoyer la clé par courriel'));
    expect(find.text('La phrase secrète doit comporter au moins 12 caractères.'), findsOneWidget);
    expect(fichier()['courriel'], isNull);
    ToastsSigh.viderPourTests();
    await saisir(t, 'phrase', 'phrase assez longue');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Envoyer la clé par courriel'));
    expect(find.text('Adresse de récupération enregistrée, mais rien n’a été envoyé.'), findsOneWidget, reason: 'poste non appairé : le relais n\'est pas joignable, et l\'écran le dit');
    expect(fichier()['courriel'], 'dg@clinique.bj');
    expect(jsonEncode(fichier()).contains('phrase'), isFalse);
  });

  casM14('appairé : « Envoyer la clé par courriel » envoie le COFFRE au relais, jamais la clé ni la phrase', (t) async {
    final cle = 'ab' * 32;
    ConfigPairPoste.ecrire(d.path, relais: 'https://relais.exemple.bj', cleHex: cle);
    RecuperationCle.fabriquePourTests = (_, __) async => coffreFixe;
    EtatPairPoste.jeton = () => 'uuid.secret';
    String? corps, auth;
    RecuperationCle.clientParDefaut = MockClient((r) async {
      corps = r.body;
      auth = r.headers['authorization'];
      return http.Response('{"envoye":true}', 200);
    });
    addTearDown(() {
      RecuperationCle.clientParDefaut = null;
      RecuperationCle.fabriquePourTests = null;
      EtatPairPoste.jeton = null;
    });
    await ouvrirM14(t, magasinM14(), 'cfg-pair');
    await toucherM14(t, find.text('Permettre la récupération de la clé par courriel'));
    await saisir(t, 'courriel', 'dg@clinique.bj');
    await saisir(t, 'phrase', 'phrase assez longue');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Envoyer la clé par courriel'));
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 100));
    expect(auth, 'Bearer uuid.secret');
    expect(corps, isNotNull, reason: 'le relais a reçu la demande');
    expect(corps!, isNot(contains(cle)));
    expect(corps!, isNot(contains('phrase assez longue')));
    final envoye = jsonDecode(corps!) as Map;
    expect(envoye['courriel'], 'dg@clinique.bj');
    expect(envoye['coffre'], coffreFixe, reason: 'le relais reçoit le coffre fabriqué, rien d\'autre');
    expect(find.text('Coffre envoyé par courriel.'), findsOneWidget);
  });

  test('ConfigPairPoste.ecrire : conserve la clé, refuse un mode activé sans clé, retire le code', () {
    ConfigPairPoste.ecrire(d.path, relais: 'https://r', nom: 'A', cleHex: 'ab' * 32, code: 'XYZ');
    ConfigPairPoste.ecrire(d.path, relais: 'https://r2');
    expect(fichier()['cle'], 'ab' * 32);
    ConfigPairPoste.ecrire(d.path, code: '');
    expect(fichier().containsKey('code'), isFalse);
    final sansCle = Directory.systemTemp.createTempSync('cfg-pair-sans');
    addTearDown(() => sansCle.deleteSync(recursive: true));
    expect(() => ConfigPairPoste.ecrire(sansCle.path, actif: true, relais: 'https://r'), throwsA(isA<FormatException>()));
    expect(ConfigPairPoste.genererCle(), isNot(ConfigPairPoste.genererCle()));
  });

  casM14('l’état du moteur se lit sans l’importer : appairé, opérations en attente, derniers échanges', (t) async {
    EtatPairPoste.source = ValueNotifier(const InstantanePair(appaire: true, enAttente: 3, cycles: 12));
    await ouvrirM14(t, magasinM14(), 'cfg-pair');
    expect(find.text('Appairé'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    expect(find.text('12 cycle(s), en ligne'), findsOneWidget);
  });

  casM14('conflits à trancher : le compteur suit la collection locale', (t) async {
    final m = magasinM14();
    m.collection('conflitsPair').inserer({'statut': 'actif', 'collection': 'patients', 'fiche': 'p1', 'champ': 'telephone'});
    await ouvrirM14(t, m, 'cfg-pair');
    expect(find.text('Conflits à trancher'), findsWidgets);
    expect(find.text('1'), findsWidgets);
  });
}
