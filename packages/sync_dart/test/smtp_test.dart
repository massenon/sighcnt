// Client SMTP Dart contre le PUITS SMTP de la maquette (prototype_html/build/_smtp_sink.js, processus Node) : un vrai message part par le protocole,
// chaque refus est nommé par son étape, le mot de passe n'est jamais rendu.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sigh_sync/sigh_sync.dart';
import 'package:test/test.dart';

class Puits {
  Puits(this.proc, this.port, this.messages);
  final Process proc;
  final int port;
  final List<Map<String, Object?>> messages;
  Future<void> fermer() async {
    proc.kill();
    await proc.exitCode;
  }

  Future<Map<String, Object?>> attendreMessage(int n) async {
    for (var i = 0; i < 100 && messages.length < n; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return messages.last;
  }
}

Future<Puits> demarrer(String mode, {String refuser = '', bool echo = false}) async {
  final proc = await Process.start('node', ['../../prototype_html/build/_smtp_sink.js', '--user=clinique', '--pass=Zx9-secret-ç€', '--mode=$mode', '--refuser=$refuser', if (echo) '--echo=1']);
  final pret = Completer<int>();
  final messages = <Map<String, Object?>>[];
  proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
    if (l.startsWith('PRET ')) pret.complete(int.parse(l.substring(5)));
    if (l.startsWith('MSG ')) messages.add((jsonDecode(l.substring(4)) as Map).cast<String, Object?>());
  });
  return Puits(proc, await pret.future.timeout(const Duration(seconds: 20)), messages);
}

ConfigSmtp cfg(int port, String mode, {String mdp = 'Zx9-secret-ç€', bool verifier = false, String identifiant = 'clinique', String repondreA = '', String repondreNom = ''}) => ConfigSmtp(
    serveur: '127.0.0.1', port: port, chiffrement: mode, identifiant: identifiant, motDePasse: mdp, expediteur: 'cnt@clinique.bj', nom: 'Clinique Nassiéra', repondreA: repondreA, repondreNom: repondreNom, verifierCertificat: verifier);

void main() {
  for (final mode in ['aucun', 'starttls', 'ssl']) {
    test('un message part vraiment ($mode) : objet, corps, accents, dot-stuffing, nom décodé', () async {
      final p = await demarrer(mode);
      addTearDown(p.fermer);
      final r = await envoyerSmtp(cfg(p.port, mode), ['dg@clinique.bj'], 'Rapport é à €', 'Bonjour\n.point seul\nfin ôô');
      expect(r.ok, isTrue, reason: r.etapes.map((e) => '${e.etape}:${e.detail}').join(' | '));
      final m = await p.attendreMessage(1);
      expect((m['entetes']! as Map)['subject'], 'Rapport é à €');
      expect(m['corps'], 'Bonjour\n.point seul\nfin ôô');
      expect(m['a'], ['dg@clinique.bj']);
      expect((m['entetes']! as Map)['from'], contains('Clinique Nassiéra'));
      if (mode == 'starttls') {
        final c = (m['commandes']! as List).cast<String>();
        expect(c.indexOf('AUTH PLAIN ok'), greaterThan(c.indexOf('STARTTLS')), reason: 'le mot de passe ne circule qu\'après le chiffrement');
      }
    });
  }

  test('« Répondre à » : l\'en-tête Reply-To est reçu (adresse et nom décodés) ; invalide ou vide, il est omis', () async {
    final p = await demarrer('starttls');
    addTearDown(p.fermer);
    var r = await envoyerSmtp(cfg(p.port, 'starttls', repondreA: 'cliniquenassiera@gmail.com', repondreNom: 'Clinique Nassièra Too'), ['dg@clinique.bj'], 's', 'c');
    expect(r.ok, isTrue);
    final m = await p.attendreMessage(1);
    expect((m['entetes']! as Map)['reply-to'], 'Clinique Nassièra Too <cliniquenassiera@gmail.com>');
    r = await envoyerSmtp(cfg(p.port, 'starttls', repondreA: 'pas-une-adresse', repondreNom: 'X'), ['dg@clinique.bj'], 's', 'c');
    expect(r.ok, isTrue);
    final m2 = await p.attendreMessage(2);
    expect((m2['entetes']! as Map).containsKey('reply-to'), isFalse, reason: 'jamais une adresse devinée');
  });

  test('mauvais mot de passe : refusé à l\'étape « authentification », sans envoi, mot de passe jamais rendu', () async {
    final p = await demarrer('starttls');
    addTearDown(p.fermer);
    final r = await envoyerSmtp(cfg(p.port, 'starttls', mdp: 'faux-mdp-123'), ['dg@clinique.bj'], 's', 'c');
    expect(r.echec, 'authentification');
    expect(r.etapes.map((e) => e.detail).join(' '), isNot(contains('faux-mdp-123')));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(p.messages, isEmpty);
  });

  test('un serveur maladroit qui recopie le mot de passe dans son refus : le client le masque', () async {
    final p = await demarrer('starttls', echo: true);
    addTearDown(p.fermer);
    final r = await envoyerSmtp(cfg(p.port, 'starttls', mdp: 'faux-mdp-123'), ['dg@clinique.bj'], 's', 'c');
    expect(r.echec, 'authentification');
    final detail = r.etapes.last.detail;
    expect(detail, contains('reçu : ***'), reason: 'le serveur a bien recopié quelque chose, masqué');
    expect(detail, isNot(contains('faux-mdp-123')));
  });

  test('port fermé : refusé à l\'étape « connexion »', () async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = s.port;
    await s.close();
    final r = await envoyerSmtp(cfg(port, 'starttls'), ['dg@clinique.bj'], 's', 'c');
    expect(r.echec, 'connexion');
    expect(r.etapes.last.detail, contains('injoignable'));
  });

  test('destinataire refusé : étape « destinataire », l\'adresse est nommée', () async {
    final p = await demarrer('starttls', refuser: 'interdit@clinique.bj');
    addTearDown(p.fermer);
    final r = await envoyerSmtp(cfg(p.port, 'starttls'), ['interdit@clinique.bj'], 's', 'c');
    expect(r.echec, 'destinataire');
    expect(r.etapes.last.detail, contains('interdit@clinique.bj'));
  });

  test('certificat auto-signé : refusé à l\'étape « chiffrement » quand le contrôle est actif (STARTTLS et SSL)', () async {
    for (final mode in ['starttls', 'ssl']) {
      final p = await demarrer(mode);
      addTearDown(p.fermer);
      final r = await envoyerSmtp(cfg(p.port, mode, verifier: true), ['dg@clinique.bj'], 's', 'c');
      expect(r.echec, 'chiffrement', reason: mode);
    }
  });

  test('STARTTLS demandé à un serveur qui ne l\'annonce pas : refus nommé ; configuration incomplète ; adresse invalide', () async {
    final p = await demarrer('aucun');
    addTearDown(p.fermer);
    expect((await envoyerSmtp(cfg(p.port, 'starttls'), ['dg@clinique.bj'], 's', 'c')).echec, 'chiffrement');
    expect((await envoyerSmtp(const ConfigSmtp(serveur: '', port: 0, expediteur: 'x'), ['a@b.cc'], 's', 'c')).echec, 'connexion');
    expect((await envoyerSmtp(cfg(p.port, 'aucun'), ['pas-une-adresse'], 's', 'c')).echec, 'destinataire');
  });
}
