// La FILE D'ENVOI des courriels du poste : écriture avant essai, reprise, délais, plafond, doublon, RG-14, chiffrement ; et la preuve réelle contre le puits SMTP.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/sync/config_pair.dart';
import 'package:sigh_poste/sync/config_smtp.dart';
import 'package:sigh_poste/sync/file_courriels.dart';
import 'package:sigh_poste/sync/service_smtp.dart';

import 'cfg_smtp_test.dart' show demarrer, mdp;

void main() {
  late Directory d;
  late DateTime horloge;
  setUp(() {
    d = Directory.systemTemp.createTempSync('file-courriels');
    horloge = DateTime(2026, 11, 6, 9);
    ConfigPairPoste.cleLocale = null;
  });
  tearDown(() {
    EtatSmtpPoste.oublierFilesPourTests();
    EtatSmtpPoste.dossier = null;
    ConfigPairPoste.cleLocale = null;
    d.deleteSync(recursive: true);
  });

  FileCourriels creer(Envoyeur e, {int max = 8}) => FileCourriels(d.path, envoyer: e, maintenant: () => horloge, maxEssais: max);
  const echec = IssueEnvoi.echec('connexion', 'Serveur injoignable.');
  File fichier() => File('${d.path}/courriels.json');

  test('le message est ÉCRIT sur disque avant tout essai, sans mot de passe ; le premier essai le fait partir et il RESTE au fichier (RG-14)', () async {
    var appels = 0;
    final f = creer((m) async {
      appels++;
      expect(fichier().readAsStringSync(), contains('"en_cours"'), reason: 'l’état « en cours » est sur disque AVANT l’envoi');
      return const IssueEnvoi.parti();
    });
    final m = f.ajouter(destinataire: 'a@b.cc', sujet: 'S', corps: 'C', reference: 'SUP-1', immediat: false);
    expect(fichier().existsSync(), isTrue);
    expect(fichier().readAsStringSync(), contains('"en_file"'));
    await f.traiter();
    expect(appels, 1);
    expect(f.message(m.id)!.etat, 'parti');
    expect(f.message(m.id)!.partiLe, horloge);
    await f.traiter();
    expect(appels, 1, reason: 'un message parti ne repart jamais');
    expect(fichier().readAsStringSync(), contains('"parti"'), reason: 'archivé, jamais supprimé');
    expect(fichier().readAsStringSync().toLowerCase(), isNot(contains('motdepasse')));
  });

  test('les délais : 1 min, 5 min, 30 min, 2 h, puis 12 h ; rien ne part avant l’heure dite', () async {
    var appels = 0;
    final f = creer((m) async {
      appels++;
      return echec;
    });
    final m = f.ajouter(destinataire: 'a@b.cc', sujet: 'S', corps: 'C', immediat: false);
    final attendus = [const Duration(minutes: 1), const Duration(minutes: 5), const Duration(minutes: 30), const Duration(hours: 2), const Duration(hours: 12), const Duration(hours: 12), const Duration(hours: 12)];
    for (var i = 0; i < attendus.length; i++) {
      await f.traiter();
      expect(appels, i + 1);
      expect(f.message(m.id)!.etat, 'en_file');
      expect(f.message(m.id)!.prochainEssaiLe, horloge.add(attendus[i]), reason: 'après l’essai ${i + 1}');
      // trop tôt : rien
      horloge = f.message(m.id)!.prochainEssaiLe!.subtract(const Duration(seconds: 1));
      await f.traiter();
      expect(appels, i + 1, reason: 'avant l’heure, aucun essai');
      horloge = f.message(m.id)!.prochainEssaiLe!;
    }
    expect(f.message(m.id)!.etapeEchec, 'connexion');
    expect(f.message(m.id)!.detailEchec, 'Serveur injoignable.');
  });

  test('le plafond : le huitième essai en échec rend l’échec DÉFINITIF (étape nommée) ; plus aucun essai ; « Renvoyer » le remet en file à zéro', () async {
    var appels = 0;
    final f = creer((m) async {
      appels++;
      return echec;
    });
    final m = f.ajouter(destinataire: 'a@b.cc', sujet: 'S', corps: 'C', immediat: false);
    for (var i = 0; i < 8; i++) {
      horloge = horloge.add(const Duration(days: 1));
      await f.traiter();
    }
    expect(appels, 8);
    expect(f.message(m.id)!.etat, 'echec_definitif');
    expect(f.message(m.id)!.essais, 8);
    expect(f.message(m.id)!.etapeEchec, 'connexion');
    horloge = horloge.add(const Duration(days: 30));
    await f.traiter();
    expect(appels, 8, reason: 'un échec définitif ne repart pas tout seul');
    f.renvoyer(m.id);
    expect(f.message(m.id)!.etat, 'en_file');
    expect(f.message(m.id)!.essais, 0);
    expect(f.message(m.id)!.renvois, 1);
    await f.traiter();
    expect(appels, 9);
  });

  test('kill -9 pendant un essai : le message est retrouvé « en cours », repart au redémarrage, une fois, marqué « repris » (au moins une fois)', () async {
    final bloque = Completer<IssueEnvoi>();
    var envoyes = 0;
    final f1 = creer((m) {
      envoyes++;
      return bloque.future; // l'essai ne rend jamais la main : le poste est « tué » ici
    });
    final m = f1.ajouter(destinataire: 'a@b.cc', sujet: 'S', corps: 'C', immediat: false);
    unawaited(f1.traiter());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(envoyes, 1);
    // le poste redémarre : une AUTRE instance relit le fichier tel qu'il est sur disque
    var envoyes2 = 0;
    final f2 = creer((x) async {
      envoyes2++;
      return const IssueEnvoi.parti();
    });
    expect(f2.message(m.id)!.etat, 'en_cours', reason: 'l’interruption est repérable sur disque');
    f2.reprendre();
    expect(f2.message(m.id)!.etat, 'en_file');
    expect(f2.message(m.id)!.repris, isTrue);
    await f2.traiter();
    await f2.traiter();
    expect(envoyes2, 1, reason: 'après la reprise, UN seul envoi');
    expect(f2.message(m.id)!.etat, 'parti');
    bloque.complete(const IssueEnvoi.parti());
  });

  test('écriture atomique : un fichier temporaire resté d’un arrêt en pleine écriture ne corrompt rien, l’ancienne version est intacte', () async {
    final f = creer((m) async => const IssueEnvoi.parti());
    final m = f.ajouter(destinataire: 'a@b.cc', sujet: 'S', corps: 'C', immediat: false);
    File('${d.path}/courriels.json.tmp').writeAsStringSync('{"v":1,"messages":[{trop-court');
    final f2 = creer((m) async => const IssueEnvoi.parti());
    expect(f2.erreur, isNull);
    expect(f2.message(m.id), isNotNull);
    f2.ajouter(destinataire: 'x@y.zz', sujet: 'T', corps: 'D', immediat: false);
    expect(creer((m) async => const IssueEnvoi.parti()).messages, hasLength(2));
  });

  test('un fichier illisible n’est jamais écrasé : la file le dit et refuse d’ajouter', () {
    fichier().writeAsStringSync('pas du json');
    final f = creer((m) async => const IssueEnvoi.parti());
    expect(f.erreur, contains('illisible'));
    expect(() => f.ajouter(destinataire: 'a@b.cc', sujet: 'S', corps: 'C'), throwsA(isA<StateError>()));
    expect(fichier().readAsStringSync(), 'pas du json');
  });

  test('chiffrée au repos avec la clé locale : ni sujet ni corps en clair ; une autre clé est refusée en le disant', () {
    ConfigPairPoste.cleLocale = List<int>.generate(32, (i) => i + 1);
    final f = creer((m) async => const IssueEnvoi.parti());
    f.ajouter(destinataire: 'a@b.cc', sujet: 'Sujet secret é', corps: 'Corps confidentiel', immediat: false);
    final brut = fichier().readAsStringSync();
    expect(brut, isNot(contains('Sujet secret')));
    expect(brut, isNot(contains('Corps confidentiel')));
    expect(creer((m) async => const IssueEnvoi.parti()).messages.single.sujet, 'Sujet secret é');
    ConfigPairPoste.cleLocale = List<int>.generate(32, (i) => 99 - i);
    expect(creer((m) async => const IssueEnvoi.parti()).erreur, contains('illisible'));
  });

  test('PREUVE RÉELLE : hors ligne, l’essai immédiat échoue à « connexion » et met en file ; le serveur qui revient reçoit UNE fois le message au Message-ID stable', () async {
    ConfigPairPoste.cleLocale = List<int>.generate(32, (i) => i + 1);
    EtatSmtpPoste.dossier = d.path;
    // 1. serveur injoignable (port fermé) : l'essai échoue à l'étape « connexion »
    final libre = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final portFerme = libre.port;
    await libre.close();
    ConfigSmtpPoste.ecrire(d.path, serveur: '127.0.0.1', port: portFerme, chiffrement: 'aucun', identifiant: 'clinique', motDePasse: mdp, expediteur: 'cnt@clinique.bj', delai: 3);
    final f = FileCourriels(d.path, envoyer: (m) => ServiceSmtp.envoyerDepuisFile(d.path, m), maintenant: () => horloge);
    final m = await f.ajouterEtEnvoyer(destinataire: 'rarhodes06@gmail.com', sujet: 'Question é €', corps: 'Bonjour, accents é à ç.');
    expect(f.message(m.id)!.essais, 1, reason: 'l’essai IMMÉDIAT a eu lieu, sans minuterie ni traiter()');
    expect(f.message(m.id)!.etat, 'en_file');
    expect(f.message(m.id)!.etapeEchec, 'connexion');
    expect(f.message(m.id)!.prochainEssaiLe, horloge.add(const Duration(minutes: 1)));
    // 2. le serveur revient : la messagerie est ré-enregistrée, l'essai suivant passe
    final p = await demarrer(mode: 'aucun');
    addTearDown(p.fermer);
    ConfigSmtpPoste.ecrire(d.path, serveur: '127.0.0.1', port: p.port, chiffrement: 'aucun', identifiant: 'clinique', motDePasse: mdp, expediteur: 'cnt@clinique.bj', delai: 5);
    horloge = horloge.add(const Duration(minutes: 2));
    await f.traiter();
    await f.traiter();
    expect(f.message(m.id)!.etat, 'parti');
    // le puits annonce le message sur sa sortie standard, de façon ASYNCHRONE : on attend qu'elle arrive (sous charge, la suite complète la retarde), puis on laisse
    // le temps à un éventuel second de se montrer
    for (var i = 0; i < 100 && p.messages.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(p.messages, hasLength(1), reason: 'UN message reçu, pas deux');
    final msg = p.messages.single;
    expect(msg['a'], ['rarhodes06@gmail.com']);
    expect((msg['entetes']! as Map)['message-id'], contains(m.id));
    expect(msg['corps'], contains('accents é à ç.'));
    // le mot de passe n'est ni dans la file ni dans ses états
    expect(jsonEncode(f.messages.map((x) => x.versJson()).toList()), isNot(contains(mdp)));
    expect(fichier().readAsStringSync(), isNot(contains(mdp)));
  });

  test('ENVOI DIRECT : ajouter() tente l’envoi TOUT DE SUITE, sans minuterie ni traiter() ; connecté, le message est « Parti » aussitôt', () async {
    var appels = 0;
    final f = creer((m) async {
      appels++;
      expect(fichier().readAsStringSync(), contains('"en_cours"'), reason: '« en cours » est sur disque AVANT l’envoi, même pour l’essai immédiat');
      return const IssueEnvoi.parti();
    });
    final m = f.ajouter(destinataire: 'a@b.cc', sujet: 'S', corps: 'C');
    expect(f.message(m.id)!.etat, 'en_cours', reason: 'le verrou (état en cours) est posé de façon synchrone par ajouter()');
    for (var i = 0; i < 50 && f.message(m.id)!.etat != 'parti'; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(appels, 1);
    expect(f.message(m.id)!.etat, 'parti');
    expect(fichier().readAsStringSync(), contains('"parti"'));
  });

  test('ENVOI DIRECT, PREUVE RÉELLE : connecté, le puits SMTP reçoit le message dans la seconde, sans traiter() ni demarrer()', () async {
    EtatSmtpPoste.dossier = d.path;
    final p = await demarrer(mode: 'aucun');
    addTearDown(p.fermer);
    ConfigSmtpPoste.ecrire(d.path, serveur: '127.0.0.1', port: p.port, chiffrement: 'aucun', identifiant: 'clinique', motDePasse: mdp, expediteur: 'cnt@clinique.bj', delai: 5);
    final f = FileCourriels(d.path, envoyer: (m) => ServiceSmtp.envoyerDepuisFile(d.path, m), maintenant: () => horloge);
    final debut = DateTime.now();
    final m = f.ajouter(destinataire: 'rarhodes06@gmail.com', sujet: 'Direct é', corps: 'Parti tout de suite.');
    for (var i = 0; i < 100 && p.messages.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(p.messages, hasLength(1), reason: 'reçu sans attendre aucune minuterie');
    expect(DateTime.now().difference(debut), lessThan(const Duration(seconds: 1)));
    for (var i = 0; i < 50 && f.message(m.id)!.etat != 'parti'; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(f.message(m.id)!.etat, 'parti');
    expect((p.messages.single['entetes']! as Map)['message-id'], contains(m.id));
  });

  test('PAS DE DOUBLON : l’essai immédiat et la minuterie (traiter) ne peuvent pas envoyer deux fois le même message ; le verrou est PAR message', () async {
    final bloque = Completer<IssueEnvoi>();
    var appels = 0;
    final f = creer((m) {
      appels++;
      return bloque.future; // un envoi LENT : l'essai immédiat est en vol
    });
    final m = f.ajouter(destinataire: 'a@b.cc', sujet: 'S', corps: 'C');
    expect(appels, 1);
    // la minuterie passe DEUX fois, et l'essai immédiat est rejoué (le chemin de ajouter), pendant que l'envoi est en vol
    await f.traiter();
    await f.traiter();
    await f.essayer(m.id);
    expect(appels, 1, reason: 'un message en cours n’est jamais renvoyé par un autre chemin');
    // un AUTRE message, lui, part : le verrou ne bloque pas la file entière
    final m2 = f.ajouter(destinataire: 'c@d.ee', sujet: 'T', corps: 'D');
    expect(appels, 2);
    expect(f.message(m2.id)!.etat, 'en_cours');
    bloque.complete(const IssueEnvoi.parti());
    for (var i = 0; i < 50 && f.message(m.id)!.etat != 'parti'; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(f.message(m.id)!.etat, 'parti');
    await f.traiter();
    expect(appels, 2, reason: 'après le départ, plus aucun essai sur ces deux messages');
  });
}
