import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/fichiers_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/sauvegarde_fichiers_poste.dart';
import 'package:sigh_poste/kit/sauvegarde_fichiers_ui.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// La SAUVEGARDE DES FICHIERS NUMÉRISÉS DU POSTE (lot D5, étape 7) : destination propre au poste (un fichier local, jamais une collection du magasin), réglage réservé à
/// l'administrateur et à la DAF, motivé et journalisé, destination vérifiée et jamais créée, passe incrémentale, panne de destination dite, restauration.
Uint8List fx(String n) => File('test/fixtures/fichiers/$n').readAsBytesSync();
final cle = List<int>.generate(32, (i) => i + 9);

Magasin nouveau() => Magasin({'audit': const [], 'personnel': const [], 'patients': const [], 'courriers': const [], 'reglages': const []}, 'POSTE')
  ..utilisateur = 'Agent Test'
  ..horloge = () => DateTime.utc(2026, 11, 13, 9);

void main() {
  late Directory tmp;
  late Directory donnees, disque;
  late Magasin m;
  late FichiersPoste fp;
  late SauvegardeFichiersPoste s;
  late String reglage;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sigh-sfp-');
    donnees = Directory('${tmp.path}/donnees')..createSync();
    disque = Directory('${tmp.path}/externe')..createSync();
    m = nouveau();
    fp = FichiersPoste(m, StockageFichiers('${donnees.path}/fichiers', cle: cle))..installer();
    reglage = '${donnees.path}/sauvegarde-fichiers.json';
    s = SauvegardeFichiersPoste(m, fp, fichierReglage: reglage, dossierDonnees: donnees.path, cle: cle, horloge: () => DateTime.utc(2026, 11, 13, 9))..installer();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('le réglage est réservé à l’administrateur et à la DAF, motivé, vérifié, jamais créé, journalisé, et propre à ce poste (un fichier, pas le magasin)', () async {
    expect((await s.definirDestination(role: 'caissier', chemin: disque.path, motif: 'essai'))!.code, 'REGLAGE_RESERVE');
    expect((await s.definirDestination(role: 'admin', chemin: disque.path, motif: ' '))!.code, 'MOTIF_REQUIS');
    final absent = '${tmp.path}/disque-debranche';
    expect((await s.definirDestination(role: 'admin', chemin: absent, motif: 'essai'))!.code, 'DESTINATION_INEXISTANTE');
    expect(Directory(absent).existsSync(), isFalse, reason: 'jamais créée');
    Directory('${donnees.path}/fichiers').createSync();
    expect((await s.definirDestination(role: 'admin', chemin: '${donnees.path}/fichiers', motif: 'essai'))!.code, 'DESTINATION_RECOUVRE_LES_FICHIERS');
    expect(s.destination, isNull);
    expect(File(reglage).existsSync(), isFalse);
    expect(await s.definirDestination(role: 'da', chemin: disque.path, motif: 'Disque externe de la direction'), isNull);
    expect(s.destination, disque.path);
    expect(s.memeDisque, MemeDisque.indetermine, reason: 'le poste ne sait pas dire qu’un chemin est sur un autre disque');
    expect(m.collection('audit').toutes.where((a) => a['action'] == 'Destination de la sauvegarde des fichiers numérisés'), hasLength(1));
    expect(m.collection('reglages').toutes, isEmpty, reason: 'un chemin local ne voyage pas vers les autres postes');
    // un autre démarrage relit le réglage
    final s2 = SauvegardeFichiersPoste(m, fp, fichierReglage: reglage, dossierDonnees: donnees.path, cle: cle);
    expect(s2.destination, disque.path);
    expect(s2.reglePar, 'Agent Test');
  });

  test('une destination DANS le dossier des données est dite « même disque », avec certitude', () async {
    final dedans = Directory('${donnees.path}/copie')..createSync();
    expect(await s.definirDestination(role: 'admin', chemin: dedans.path, motif: 'Essai'), isNull);
    expect(s.memeDisque, MemeDisque.certain);
  });

  test('une passe copie, une seconde ne recopie rien, rien ne se supprime ; sans destination, rien ne part', () async {
    await s.lancer();
    expect(s.dernier, isNull);
    final sha = (await fp.stockage.ranger(fx('scan.png'), famille: 'courrier', zone: 0)).sha256;
    await fp.stockage.ranger(fx('courrier-texte.pdf'), famille: 'patient', zone: 2);
    expect(await s.definirDestination(role: 'admin', chemin: disque.path, motif: 'Disque externe'), isNull);
    await s.lancer(manuel: true);
    expect(s.dernier!.copies, 2);
    expect(s.dernier!.complet, isTrue);
    await s.lancer();
    expect(s.dernier!.copies, 0);
    expect(s.dernier!.dejaCopies, 2);
    final (ctl, refus) = await s.controler();
    expect(refus, isNull);
    expect(ctl!.sain, isTrue);
    expect(File('${disque.path}/$dossierSauvegardeFichiers/${sha.substring(0, 2)}/$sha.png').existsSync(), isTrue);
  });

  test('une destination qui DISPARAÎT donne une exécution EN ERREUR et une entrée de journal, jamais un « ok » ni une copie sur le disque des données', () async {
    await fp.stockage.ranger(fx('scan.png'), famille: 'courrier', zone: 0);
    expect(await s.definirDestination(role: 'admin', chemin: disque.path, motif: 'Disque externe'), isNull);
    await s.lancer();
    expect(s.derniereErreur, isNull);
    disque.deleteSync(recursive: true);
    await s.lancer();
    expect(s.derniereErreur!.code, 'DESTINATION_INEXISTANTE');
    expect(s.dernier, isNull);
    expect(Directory(disque.path).existsSync(), isFalse);
    expect(m.collection('audit').toutes.where((a) => a['action'] == 'Sauvegarde des fichiers numérisés en erreur'), hasLength(1));
    final (_, r) = await s.controler();
    expect(r!.code, 'DESTINATION_INEXISTANTE');
  });

  test('la restauration : réservée aux deux rôles, simulation par défaut, journalisée quand elle écrit', () async {
    final sha = (await fp.stockage.ranger(fx('scan.jpg'), famille: 'courrier', zone: 0)).sha256;
    expect(await s.definirDestination(role: 'admin', chemin: disque.path, motif: 'Disque externe'), isNull);
    await s.lancer();
    File('${donnees.path}/fichiers/${sha.substring(0, 2)}/$sha.jpg').deleteSync();
    expect((await s.restaurer(role: 'caissier')).$2!.code, 'REGLAGE_RESERVE');
    final (sim, _) = await s.restaurer(role: 'admin');
    expect(sim!.simulation, isTrue);
    expect(sim.aRestaurer, 1);
    expect(await fp.stockage.existe(sha), isFalse);
    final (reel, _) = await s.restaurer(role: 'admin', simulation: false);
    expect(reel!.restaures, 1);
    expect(await fp.stockage.etat(sha), EtatLocalFichier.present);
    expect(m.collection('audit').toutes.where((a) => a['action'] == 'Restauration des fichiers numérisés'), hasLength(1));
  });

  testWidgets('la carte : commandes de réglage et de restauration ABSENTES sans le droit, avertissement « même disque » ou « disque non déterminé », sans service la carte n’existe pas', (t) async {
    t.view.physicalSize = const Size(1200, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    Widget monter(String role) => MaterialApp(
        home: ContexteEcran(
            ecranId: 'm14-sauvegardes',
            role: role,
            droit: const Droit(voir: true, editer: true, annuler: true),
            magasin: m,
            aller: (_) {},
            child: Scaffold(body: SingleChildScrollView(child: CarteSauvegardeFichiers(role: role)))));
    await t.pumpWidget(monter('medecin'));
    expect(find.byKey(const Key('sauvfic:carte')), findsOneWidget);
    expect(find.textContaining('Aucune destination réglée'), findsOneWidget);
    expect(find.byKey(const Key('sauvfic:regler')), findsNothing, reason: 'absente, jamais grisée');
    await t.pumpWidget(monter('admin'));
    expect(find.byKey(const Key('sauvfic:regler')), findsOneWidget);
    expect(find.byKey(const Key('sauvfic:lancer')), findsNothing, reason: 'rien à lancer sans destination');
    await t.runAsync(() => s.definirDestination(role: 'admin', chemin: disque.path, motif: 'Disque externe'));
    await t.pump();
    expect(find.byKey(const Key('sauvfic:lancer')), findsOneWidget);
    expect(find.byKey(const Key('sauvfic:controler')), findsOneWidget);
    expect(find.byKey(const Key('sauvfic:restaurer')), findsOneWidget);
    expect(find.textContaining('Disque non déterminé'), findsOneWidget);
    await t.pumpWidget(monter('medecin'));
    expect(find.byKey(const Key('sauvfic:lancer')), findsOneWidget, reason: 'tout profil peut lancer une passe, seul le réglage est réservé');
    expect(find.byKey(const Key('sauvfic:controler')), findsNothing);
    expect(find.byKey(const Key('sauvfic:restaurer')), findsNothing);
    final autre = nouveau();
    await t.pumpWidget(MaterialApp(
        home: ContexteEcran(
            ecranId: 'm14-sauvegardes',
            role: 'admin',
            droit: const Droit(voir: true, editer: true, annuler: true),
            magasin: autre,
            aller: (_) {},
            child: const Scaffold(body: CarteSauvegardeFichiers(role: 'admin')))));
    expect(find.byKey(const Key('sauvfic:carte')), findsNothing);
  });
}
