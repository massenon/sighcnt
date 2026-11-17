import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/service_parametres.dart';
import 'package:sigh_poste/donnees/horssite_poste.dart';
import 'package:sigh_poste/donnees/identite_migration_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/persistance.dart' show CleLocale;
import 'package:sigh_poste/donnees/sms_poste.dart';
import 'package:sigh_poste/kit/kit.dart';

import '../test/aide_polices.dart';
import '../test/installation_ecrans_test.dart' as ins;
import 'package:sigh_poste/core/identifiants.dart';
import 'package:sigh_poste/modules/auth/acc_session.dart';
import '../test/m14_aide.dart';

/// CAPTURES FLUTTER DU MANUEL ADMINISTRATEUR (écrans propres au poste, que la maquette n'a pas ou montre autrement).
/// Un seul fichier, aucune suite : `flutter test --no-pub test_captures/captures_admin_test.dart` depuis `apps/poste`.
/// Chaque capture est écrite en PNG dans `SIGH_CAPTURES_DIR` (par défaut `test_captures/sortie`) avec, dans `rects.json`, les rectangles des éléments à encadrer :
/// `docs/manuels/source-administrateur/annoter-flutter.py` pose ensuite les cadres rouges numérotés et réduit les images.
/// Les sources de la mère et du relais sont FAUSSES et vierges (aucun envoi, aucune donnée de santé) ; l'horloge est celle du 17/11/2026.
final sortie = Directory(Platform.environment['SIGH_CAPTURES_DIR'] ?? 'test_captures/sortie')..createSync(recursive: true);
final rects = <String, List<Map<String, Object?>>>{};
final jour = DateTime(2026, 11, 17, 10, 30);

class SourceSmsVierge implements SourceSms {
  @override
  Future<Map<String, Object?>> etat() async => {
        'passerelle': {
          'fournisseur': 'twilio',
          'identifiantsDefinis': false,
          'expediteurDefini': false,
          'configuree': false,
          'envoyesAujourdhui': 0,
          'reglages': {'plafond_jour': 200}
        },
        'planifies': [
          {'type': 'rappel_rdv', 'heure': '2026-11-18T08:43', 'numeroMasque': '••••0001'},
          {'type': 'anniversaire_patient', 'heure': '2026-11-18T09:43', 'numeroMasque': '••••0002'}
        ],
        'dernier': null,
        'erreur': null,
      };
  @override
  Future<Map<String, Object?>> passe(String role) async => {'calcules': 0, 'planifies': 0, 'retires': 0, 'ecartes': {}};
  @override
  Future<Map<String, Object?>> tester(String role, String numero) async => {'ok': false, 'code': 'SECRET_NON_DEFINI', 'motif': 'Les identifiants du fournisseur ne sont pas définis au relais.', 'geste': 'Les poser dans le .env du relais.'};
  @override
  Future<List<Map<String, Object?>>> journal() async => [
        {'id': 'a' * 64, 'type': 'rappel_rdv', 'etat': 'planifie', 'code': null, 'numeroMasque': '••••0001', 'idFournisseur': null, 'maj': DateTime(2026, 11, 17, 8, 43).millisecondsSinceEpoch},
        {'id': 'b' * 64, 'type': 'anniversaire_patient', 'etat': 'planifie', 'code': null, 'numeroMasque': '••••0002', 'idFournisseur': null, 'maj': DateTime(2026, 11, 17, 8, 43).millisecondsSinceEpoch},
      ];
}

class SourceHorsSiteVierge implements SourceHorsSite {
  @override
  Future<Map<String, Object?>> etat() async => {
        'actif': false,
        'relaisRelie': true,
        'controle': null,
        'types': {
          'magasin': {'destination': 'relais', 'dernier': null, 'erreur': null, 'enRetard': false},
          'fichiers': {'destination': 'aucune', 'dernier': null, 'erreur': null},
        },
      };
  @override
  Future<Map<String, Object?>> lancer(String type) async => {'ok': true};
  @override
  Future<Map<String, Object?>> controler() async => {};
  @override
  Future<List<Map<String, Object?>>> copies(String type) async => [];
  @override
  Future<Map<String, Object?>> restaurer({required String type, required String copie, required String cible}) async => {'ok': true};
}

Future<void> taille(WidgetTester t, double l, double h) async {
  t.view.physicalSize = Size(l * 2, h * 2);
  t.view.devicePixelRatio = 2;
  await t.pump(const Duration(milliseconds: 300));
}

/// Écrit la capture et mémorise les rectangles (en pixels logiques) des éléments à encadrer, numérotés dans l'ordre donné.
Future<void> capter(WidgetTester t, String nom, [List<Finder> cadres = const []]) async {
  await t.pump(const Duration(milliseconds: 500));
  rects[nom] = [
    for (var i = 0; i < cadres.length; i++)
      if (cadres[i].evaluate().isNotEmpty)
        () {
          final r = t.getRect(cadres[i].first);
          return {'n': i + 1, 'x': r.left, 'y': r.top, 'l': r.width, 'h': r.height};
        }()
  ];
  await expectLater(find.byType(MaterialApp).first, matchesGoldenFile('$nom.png'));
  File('${sortie.path}/rects.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(rects));
}

Magasin magasinMere() {
  final m = magasinM14();
  m.utilisateur = 'AGENT Démo 1';
  serviceParametres(m, auteur: () => 'semis', horloge: () => jour).semerDefauts();
  migrerIdentiteVersion2(m);
  return m;
}

void main() {
  setUpAll(() async {
    await chargerPolices();
    ServiceIdentifiants.parametres = AccParametresHachage.tests;
    goldenFileComparator = _Ecrivain(sortie.path);
    autoUpdateGoldenFiles = true;
  });
  tearDown(ToastsSigh.viderPourTests);

  testWidgets('cfg-sms du poste', (t) async {
    final m = magasinMere();
    SmsPoste(m, estFileul: () => false, estMere: () => true, source: SourceSmsVierge(), gesteDe: (r) => r == 'admin' || r == 'da').installer();
    await ouvrirM14(t, m, 'cfg-sms', horloge: jour);
    await taille(t, 1440, 1700);
    await capter(t, 'f-cfg-sms', [find.widgetWithText(BoutonSigh, 'Enregistrer la passerelle'), find.widgetWithText(BoutonSigh, 'Tester l’envoi')]);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('m13-sms-journal du poste', (t) async {
    final m = magasinMere();
    SmsPoste(m, estFileul: () => false, estMere: () => true, source: SourceSmsVierge(), gesteDe: (r) => r == 'admin' || r == 'da').installer();
    await ouvrirM14(t, m, 'm13-sms-journal', horloge: jour);
    await taille(t, 1440, 900);
    await capter(t, 'f-m13-sms-journal');
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('sauvegardes : carte Sauvegarde hors site', (t) async {
    final m = magasinMere();
    HorsSitePoste(m, estFileul: () => false, estMere: () => true, source: SourceHorsSiteVierge()).installer();
    await ouvrirM14(t, m, 'm14-sauvegardes', horloge: jour);
    await taille(t, 1440, 1500);
    await capter(t, 'f-m14-sauvegardes', [find.widgetWithText(BoutonSigh, 'Régler la copie hors site')]);
    final b = find.widgetWithText(BoutonSigh, 'Régler la copie hors site');
    if (b.evaluate().isNotEmpty) {
      await toucherM14(t, b);
      await taille(t, 1440, 1500);
      await capter(t, 'f-horssite-reglage', [find.widgetWithText(BoutonSigh, 'Enregistrer')]);
    }
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('cfg-systeme : onglet Installation et données, clé de chiffrement', (t) async {
    final m = magasinMere();
    CleLocale.courante = CleLocale('${Directory.systemTemp.path}/cle-demo-manuel.bin');
    addTearDown(() => CleLocale.courante = null);
    await ouvrirM14(t, m, 'cfg-systeme', horloge: jour);
    await taille(t, 1440, 1300);
    await toucherM14(t, find.text('Installation et données'));
    await taille(t, 1440, 1300);
    await capter(t, 'f-cfg-systeme-installation', [find.widgetWithText(BoutonSigh, 'Sauvegarder la clé de chiffrement')]);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Sauvegarder la clé de chiffrement'));
    await taille(t, 1440, 900);
    await capter(t, 'f-cle-chiffrement', [find.widgetWithText(BoutonSigh, 'Exporter la clé')]);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('cfg-systeme : onglet Paramètres (registre en base)', (t) async {
    final m = magasinMere();
    await ouvrirM14(t, m, 'cfg-systeme', horloge: jour);
    await taille(t, 1440, 2000);
    final onglet = find.text('Paramètres');
    if (onglet.evaluate().isNotEmpty) await toucherM14(t, onglet.first);
    await taille(t, 1440, 2000);
    await capter(t, 'f-cfg-systeme-parametres');
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('mecef-config du poste', (t) async {
    final m = magasinMere();
    await ouvrirM14(t, m, 'mecef-config', horloge: jour);
    await taille(t, 1440, 1700);
    await capter(t, 'f-mecef-config', [find.widgetWithText(BoutonSigh, 'Régler le mode'), find.widgetWithText(BoutonSigh, 'Régler l’imprimante')]);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('installation du poste : accueil, premier administrateur, code de secours', (t) async {
    final m = await ins.posteNeuf(t);
    final sess = SessionPoste(exigeConnexion: true, horloge: () => jour);
    await ins.monter(t, m, sess);
    await taille(t, 1440, 900);
    await capter(t, 'f-ins-accueil', [find.byKey(const Key('ins:premiere')), find.byKey(const Key('ins:rejoindre'))]);
    await ins.toucher(t, find.byKey(const Key('ins:premiere')));
    await ins.saisir(t, 'ins:nom', 'NOM Prénom');
    await ins.saisir(t, 'ins:identifiant', 'prenom.nom');
    await ins.saisir(t, 'ins:motdepasse', 'MotDePasse#Demo2026');
    await ins.saisir(t, 'ins:confirmation', 'MotDePasse#Demo2026');
    await taille(t, 1440, 900);
    await capter(t, 'f-ins-admin', [find.byKey(const Key('ins:creer'))]);
    await ins.toucher(t, find.byKey(const Key('ins:creer')));
    await ins.calculer(t);
    await taille(t, 1440, 1000);
    await capter(t, 'f-ins-code-secours', [find.byKey(const Key('ins:code')), find.byKey(const Key('ins:suite'))]);
    await ins.fin(t);
  });
}

/// Écrit la capture dans le dossier de sortie au lieu de la comparer à un fichier de référence.
class _Ecrivain extends GoldenFileComparator {
  _Ecrivain(this.dossier);
  final String dossier;
  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async => true;
  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async => File('$dossier/${golden.pathSegments.last}').writeAsBytesSync(imageBytes);
}
