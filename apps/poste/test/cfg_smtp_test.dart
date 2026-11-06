import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/sync/config_pair.dart';
import 'package:sigh_poste/sync/config_smtp.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// cfg-smtp : la messagerie de la clinique et son test d'envoi, EXERCÉ contre le puits SMTP de la maquette (prototype_html/build/_smtp_sink.js, processus Node) :
/// un vrai message part par le protocole, chaque refus est nommé par son étape, le mot de passe n'est jamais relu ni écrit en clair, et « Contactez l'éditeur »
/// dit la vérité sur ce qui part.
const mdp = 'Zx9-secret-ç€-7Qp';

class Puits {
  Puits(this.proc, this.port, this.messages);
  final Process proc;
  final int port;
  final List<Map<String, Object?>> messages;
  Future<void> fermer() async {
    proc.kill();
    await proc.exitCode;
  }
}

Future<Puits> demarrer({String mode = 'starttls'}) async {
  final proc = await Process.start('node', ['../../prototype_html/build/_smtp_sink.js', '--user=clinique', '--pass=$mdp', '--mode=$mode']);
  final pret = Completer<int>();
  final messages = <Map<String, Object?>>[];
  proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
    if (l.startsWith('PRET ')) pret.complete(int.parse(l.substring(5)));
    if (l.startsWith('MSG ')) messages.add((jsonDecode(l.substring(4)) as Map).cast<String, Object?>());
  });
  return Puits(proc, await pret.future.timeout(const Duration(seconds: 20)), messages);
}

void main() {
  setUpAll(chargerPolices);
  late Directory d;
  setUp(() {
    d = Directory.systemTemp.createTempSync('cfg-smtp');
    EtatSmtpPoste.dossier = d.path;
    ConfigPairPoste.cleLocale = List<int>.generate(32, (i) => i + 1);
  });
  tearDown(() {
    ToastsSigh.viderPourTests();
    EtatSmtpPoste.oublierFilesPourTests();
    EtatSmtpPoste.dossier = null;
    ConfigPairPoste.cleLocale = null;
    d.deleteSync(recursive: true);
  });

  /// Attend, EN TEMPS RÉEL (les sockets ne tournent pas dans l'horloge simulée des tests de widgets), que [ok] soit vrai.
  Future<void> attendre(WidgetTester t, bool Function() ok) async {
    for (var i = 0; i < 120 && !ok(); i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> remplir(WidgetTester t, int port, {String motDePasse = mdp, String chiffrement = 'starttls'}) async {
    await saisir(t, 'serveur', '127.0.0.1');
    await saisir(t, 'port', '$port');
    await saisir(t, 'identifiant', 'clinique');
    await saisir(t, 'motDePasse', motDePasse);
    await saisir(t, 'expediteur', 'cnt@clinique.bj');
  }

  String? courrielDe(Magasin m, String objet) {
    for (final f in m.collection('support').actives) {
      if (f['objet'] == objet) return f['courriel'] as String?;
    }
    return null;
  }

  final enregistrer = find.widgetWithText(BoutonSigh, 'Enregistrer la messagerie');
  final tester = find.widgetWithText(BoutonSigh, 'Envoyer un message de test');
  String texteEtapes(WidgetTester t) => find.byWidgetPredicate((w) => w is Text && (w.key?.toString().contains('smtp:etape-') ?? false)).evaluate().map((e) => (e.widget as Text).data).join(' | ');

  casM14('ouverture : non configurée, jamais testée, champs nommés, mot de passe masqué', (t) async {
    await ouvrirM14(t, magasinM14(), 'cfg-smtp');
    for (final k in ['Messagerie', 'Dernier test', 'Chiffrement', 'Mot de passe', 'Serveur de courriel', 'Test d’envoi', 'Non configurée', 'Jamais fait', 'Non défini']) {
      expect(find.text(k), findsWidgets, reason: k);
    }
    expect(find.text('Serveur SMTP *'), findsOneWidget);
    expect(find.text('Adresse d’expéditeur *'), findsOneWidget);
    final champ = t.widget<TextField>(find.descendant(of: find.byKey(const Key('kit:champ:motDePasse')), matching: find.byType(TextField)));
    expect(champ.obscureText, isTrue);
    expect(File('${d.path}/smtp.json').existsSync(), isFalse, reason: 'rien n’est écrit tant qu’on n’a rien fait');
  });

  casM14('rien d’enregistré : le formulaire PROPOSE la configuration de la clinique ; le mot de passe n’a AUCUNE valeur par défaut ; « configurée » reste faux', (t) async {
    await ouvrirM14(t, magasinM14(), 'cfg-smtp');
    String v(String champ) => t.widget<TextField>(find.descendant(of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(TextField))).controller!.text;
    expect({for (final k in ['serveur', 'port', 'delai', 'identifiant', 'expediteur', 'nom', 'repondreA', 'repondreNom', 'motDePasse']) k: v(k)}, {
      'serveur': 'mail.sigh.nassieratoo.com',
      'port': '587',
      'delai': '20',
      'identifiant': 'contact@sigh.nassieratoo.com',
      'expediteur': 'contact@sigh.nassieratoo.com',
      'nom': 'Clinique Nassièra Too',
      'repondreA': 'cliniquenassiera@gmail.com',
      'repondreNom': 'Clinique Nassièra Too',
      'motDePasse': '',
    });
    expect(find.text('Non configurée'), findsOneWidget);
    expect(File('${d.path}/smtp.json').existsSync(), isFalse, reason: 'proposer n’est pas enregistrer');
    expect(ConfigSmtpPoste.lireBrut(d.path)['configure'], false);
  });

  casM14('un envoi réel : le puits REÇOIT le message, les étapes s’affichent, le test réussi est retenu', (t) async {
    final p = (await t.runAsync(demarrer))!;
    addTearDown(p.fermer);
    await ouvrirM14(t, magasinM14(), 'cfg-smtp');
    await remplir(t, p.port);
    await toucherM14(t, find.text('Vérifier le certificat du serveur')); // décoché : le puits a un certificat auto-signé
    await toucherM14(t, enregistrer);
    expect(find.textContaining('Messagerie enregistrée'), findsOneWidget);
    expect(find.text('Configurée'), findsOneWidget);
    expect(find.text('Défini'), findsOneWidget);
    await saisir(t, 'destinataire', 'dg@clinique.bj');
    await toucherM14(t, tester);
    await attendre(t, () => find.textContaining('Message de test envoyé').evaluate().isNotEmpty);
    expect(find.textContaining('Message de test envoyé'), findsOneWidget, reason: texteEtapes(t));
    final etapes = texteEtapes(t);
    for (final k in ['Connexion au serveur', 'Chiffrement : Connexion chiffrée (STARTTLS)', 'Authentification : Authentifié comme clinique', 'Envoi du message']) {
      expect(etapes, contains(k));
    }
    await attendre(t, () => p.messages.isNotEmpty);
    final m = p.messages.single;
    expect(m['de'], 'cnt@clinique.bj');
    expect(m['a'], ['dg@clinique.bj']);
    expect((m['entetes']! as Map)['subject'], 'SIGH-CNT : test de la messagerie');
    expect(m['corps'], contains('é è à ç ô, symbole €'));
    expect((m['entetes']! as Map)['reply-to'], 'Clinique Nassièra Too <cliniquenassiera@gmail.com>', reason: 'En-tête Reply-To proposé par défaut, reçu par le puits');
    final c = (m['commandes']! as List).cast<String>();
    expect(c.indexOf('AUTH PLAIN ok'), greaterThan(c.indexOf('STARTTLS')));
    expect(ConfigSmtpPoste.lireBrut(d.path)['testeOk'], true, reason: 'le dernier test réussi est retenu');
  });

  casM14('mauvais mot de passe : « Authentification », sans envoi ; le mot de passe ne s’affiche ni ne s’écrit en clair', (t) async {
    final p = (await t.runAsync(demarrer))!;
    addTearDown(p.fermer);
    await ouvrirM14(t, magasinM14(), 'cfg-smtp');
    await remplir(t, p.port, motDePasse: 'mauvais-mot-de-passe');
    await toucherM14(t, find.text('Vérifier le certificat du serveur'));
    await saisir(t, 'destinataire', 'dg@clinique.bj');
    await toucherM14(t, tester);
    await attendre(t, () => find.textContaining('Échec à l’étape').evaluate().isNotEmpty);
    expect(find.textContaining('Échec à l’étape « Authentification »'), findsOneWidget, reason: texteEtapes(t));
    expect(find.textContaining('mauvais-mot-de-passe'), findsNothing);
    expect(p.messages, isEmpty);
  });

  casM14('port fermé : « Connexion au serveur »', (t) async {
    final s = (await t.runAsync(() => ServerSocket.bind(InternetAddress.loopbackIPv4, 0)))!;
    final port = s.port;
    await t.runAsync(s.close);
    await ouvrirM14(t, magasinM14(), 'cfg-smtp');
    await remplir(t, port);
    await saisir(t, 'destinataire', 'dg@clinique.bj');
    await toucherM14(t, tester);
    await attendre(t, () => find.textContaining('Échec à l’étape').evaluate().isNotEmpty);
    expect(find.textContaining('Échec à l’étape « Connexion au serveur »'), findsOneWidget, reason: texteEtapes(t));
    expect(texteEtapes(t), contains('injoignable'));
  });

  test('le mot de passe est chiffré dans smtp.json, jamais rendu, illisible ailleurs, refus nommé si altéré', () {
    ConfigSmtpPoste.ecrire(d.path, serveur: 'smtp.exemple.bj', port: 587, chiffrement: 'starttls', identifiant: 'u', motDePasse: mdp, expediteur: 'cnt@clinique.bj');
    final brut = File('${d.path}/smtp.json').readAsStringSync();
    expect(brut.contains(mdp), isFalse, reason: 'aucun clair sur le disque');
    expect(brut, contains('mdp_chiffre'));
    final lu = ConfigSmtpPoste.lireBrut(d.path);
    expect(lu['motDePasseDefini'], true);
    expect(jsonEncode(lu).contains(mdp), isFalse);
    expect(lu.containsKey('mdp') || lu.containsKey('mdp_chiffre'), isFalse);
    expect(ConfigSmtpPoste.motDePasse(d.path), mdp);
    // un mot de passe vide à l'enregistrement = inchangé
    ConfigSmtpPoste.ecrire(d.path, serveur: 'smtp2.exemple.bj', port: 465, chiffrement: 'ssl', motDePasse: '', expediteur: 'cnt@clinique.bj');
    expect(ConfigSmtpPoste.motDePasse(d.path), mdp);
    // altération
    final j = jsonDecode(File('${d.path}/smtp.json').readAsStringSync()) as Map;
    final octets = base64.decode('${j['mdp_chiffre']}');
    octets[octets.length - 1] ^= 1;
    j['mdp_chiffre'] = base64.encode(octets);
    File('${d.path}/smtp.json').writeAsStringSync(jsonEncode(j));
    expect(() => ConfigSmtpPoste.motDePasse(d.path), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('illisible'))));
    expect(ConfigSmtpPoste.lireBrut(d.path)['mdp_illisible'], true);
    // une autre clé locale (autre poste, autre session) ne le lit pas non plus
    ConfigPairPoste.cleLocale = List<int>.generate(32, (i) => 99 - i);
    expect(() => ConfigSmtpPoste.motDePasse(d.path), throwsA(isA<FormatException>()));
    // refus nommés à l'écriture
    expect(() => ConfigSmtpPoste.ecrire(d.path, serveur: '', port: 25, chiffrement: 'aucun', expediteur: 'a@b.cc'), throwsA(isA<FormatException>()));
    expect(() => ConfigSmtpPoste.ecrire(d.path, serveur: 's', port: 25, chiffrement: 'aucun', expediteur: 'pas-une-adresse'), throwsA(isA<FormatException>()));
  });

  casM14('« Contactez l’éditeur » : sans messagerie l’écran le DIT et n’envoie rien ; avec messagerie testée, le courriel PART vraiment', (t) async {
    t.view.physicalSize = const Size(1600, 3000);
    final m = magasinM14();
    await ouvrirM14(t, m, 'contact-editeur');
    t.view.physicalSize = const Size(1600, 3000);
    await t.pump();
    expect(find.byKey(const Key('support:sans-messagerie:message')), findsOneWidget);
    expect(find.byKey(const Key('support:courriel:message')), findsNothing);
    await saisir(t, 'objet', 'Sans messagerie');
    await saisir(t, 'message', 'Texte');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Envoyer le message'));
    expect(find.text('Message enregistré dans le logiciel.'), findsOneWidget);
    expect(find.textContaining('Aucun courriel n’a été envoyé à l’éditeur.'), findsOneWidget);

    // avec une messagerie configurée ET testée
    final p = (await t.runAsync(demarrer))!;
    addTearDown(p.fermer);
    ConfigSmtpPoste.ecrire(d.path, serveur: '127.0.0.1', port: p.port, chiffrement: 'starttls', identifiant: 'clinique', motDePasse: mdp, expediteur: 'cnt@clinique.bj', nom: 'Clinique Nassiera Too', repondreA: 'cliniquenassiera@gmail.com', repondreNom: 'Clinique Nassièra Too', verifierCertificat: false);
    ConfigSmtpPoste.noterTest(d.path, ok: true);
    ToastsSigh.viderPourTests();
    await ouvrirM14(t, m, 'contact-editeur');
    t.view.physicalSize = const Size(1600, 3000);
    await t.pump();
    expect(find.byKey(const Key('support:courriel:message')), findsOneWidget, reason: 'la case est offerte');
    expect(find.byKey(const Key('support:sans-messagerie:message')), findsNothing);
    await saisir(t, 'objet', 'Question sur la comptabilité');
    await saisir(t, 'message', 'Bonjour, où règle-t-on le plan ? Merci é à ç.');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Envoyer le message'));
    await attendre(t, () => p.messages.isNotEmpty);
    expect(p.messages, hasLength(1));
    final msg = p.messages.single;
    expect(msg['a'], ['rarhodes06@gmail.com']);
    expect((msg['entetes']! as Map)['subject'], '[SIGH-CNT] Question sur la comptabilité');
    expect(msg['corps'], contains('où règle-t-on le plan ? Merci é à ç.'));
    expect(msg['corps'], contains('Référence : SUP-'));
    expect((msg['entetes']! as Map)['reply-to'], 'Clinique Nassièra Too <cliniquenassiera@gmail.com>');
    await attendre(t, () => EtatSmtpPoste.file!.messages.isNotEmpty && EtatSmtpPoste.file!.messages.single.etat == 'parti');
    await t.pump(const Duration(milliseconds: 300));
    // le courriel est passé par la FILE D'ENVOI (état « parti », Message-ID stable = identifiant du message) et la demande porte son identifiant
    expect(courrielDe(m, 'Question sur la comptabilité'), 'file');
    expect(EtatSmtpPoste.file!.messages.single.etat, 'parti');
    expect((msg['entetes']! as Map)['message-id'], contains(EtatSmtpPoste.file!.messages.single.id));
    expect(find.text('Message envoyé par courriel à l’éditeur.'), findsOneWidget);
  });

  casM14('« Contactez l’éditeur » : un serveur absent met le courriel EN FILE (heure du prochain essai dite, rien de perdu) ; un échec définitif propose « Renvoyer »', (t) async {
    t.view.physicalSize = const Size(1600, 3000);
    final m = magasinM14();
    // messagerie configurée sur un port fermé : le premier essai échoue à l'étape « connexion »
    final libre = await t.runAsync(() => ServerSocket.bind(InternetAddress.loopbackIPv4, 0));
    final portFerme = libre!.port;
    await t.runAsync(libre.close);
    ConfigSmtpPoste.ecrire(d.path, serveur: '127.0.0.1', port: portFerme, chiffrement: 'aucun', expediteur: 'cnt@clinique.bj', delai: 3);
    ConfigSmtpPoste.noterTest(d.path, ok: true);
    await ouvrirM14(t, m, 'contact-editeur');
    t.view.physicalSize = const Size(1600, 3000);
    await t.pump();
    await saisir(t, 'objet', 'Serveur absent');
    await saisir(t, 'message', 'Texte');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Envoyer le message'));
    await attendre(t, () => EtatSmtpPoste.file!.messages.isNotEmpty && EtatSmtpPoste.file!.messages.single.etat == 'en_file' && EtatSmtpPoste.file!.messages.single.essais == 1);
    await t.pump(const Duration(milliseconds: 300));
    final msg = EtatSmtpPoste.file!.messages.single;
    expect(msg.etat, 'en_file');
    expect(msg.etapeEchec, 'connexion');
    expect(find.text('Demande enregistrée, le courriel est en file.'), findsOneWidget);
    expect(find.textContaining('En file, prochain essai à'), findsWidgets, reason: 'l’heure du prochain essai est DITE à l’écran');
    expect(find.text('Non parti'), findsNothing);
    ToastsSigh.viderPourTests();
    await t.pump(const Duration(seconds: 30));

    // échec définitif : le bouton « Renvoyer » remet en file
    msg.etat = 'echec_definitif';
    msg.essais = 8;
    msg.prochainEssaiLe = null;
    await ouvrirM14(t, m, 'contact-editeur');
    t.view.physicalSize = const Size(1600, 3000);
    await t.pump();
    expect(find.text('Échec définitif'), findsWidgets);
    final renvoyer = find.byKey(Key('support:renvoyer:${msg.id}'));
    expect(renvoyer, findsOneWidget);
    await toucherM14(t, renvoyer);
    expect(msg.etat, 'en_file', reason: 'renvoyé : de nouveau en file, essais remis à zéro');
    expect(msg.essais, 0);
    expect(msg.renvois, 1);
  });

  casM14('lecture seule : ni « Enregistrer la messagerie » ni « Envoyer un message de test » (commande absente)', (t) async {
    await ouvrirM14(t, magasinM14(), 'cfg-smtp', donnees: donneesLectureSeule('admin', 'cfg-smtp'));
    expect(enregistrer, findsNothing);
    expect(tester, findsNothing);
  });
}
