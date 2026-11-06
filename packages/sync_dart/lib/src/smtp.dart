/// Client SMTP minimal (sockets, sans dépendance), port exact de `prototype_html/api/smtp_client.php` : mêmes étapes, mêmes refus nommés, mêmes textes.
///
/// Un courriel part par UNE suite d'étapes, et c'est la suite que l'on montre : un « échec d'envoi » qui ne dit pas où l'on a échoué renvoie l'administrateur
/// chercher au mauvais endroit. Chaque étape rend `{etape, ok, detail}` et la suite s'ARRÊTE à la première qui échoue :
///   connexion → salutation → chiffrement → authentification → expéditeur → destinataire → envoi.
///
/// Chiffrement : `aucun`, `starttls` (port 587) ou `ssl` (port 465). Le contrôle du certificat est ACTIF par défaut ; le désactiver est un réglage nommé.
/// Le corps part toujours en base64 UTF-8. Le mot de passe n'est ni journalisé ni rendu : les réponses du serveur qui l'afficheraient sont masquées.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

class ConfigSmtp {
  const ConfigSmtp({
    required this.serveur,
    required this.port,
    this.chiffrement = 'starttls',
    this.identifiant = '',
    this.motDePasse = '',
    required this.expediteur,
    this.nom = '',
    this.repondreA = '',
    this.repondreNom = '',
    this.delai = 15,
    this.verifierCertificat = true,
  });
  final String serveur, chiffrement, identifiant, motDePasse, expediteur, nom, repondreA, repondreNom;
  final int port, delai;
  final bool verifierCertificat;
}

class EtapeSmtp {
  const EtapeSmtp(this.etape, this.ok, this.detail);
  final String etape, detail;
  final bool ok;
}

class ResultatSmtp {
  const ResultatSmtp(this.etapes, this.echec);
  final List<EtapeSmtp> etapes;

  /// L'étape qui a échoué, `null` si le message est parti.
  final String? echec;
  bool get ok => echec == null;
}

/// Une réponse SMTP complète : lignes « 250-… » puis « 250 … ».
class _Flux {
  _Flux(this._socket, this._delai) {
    _abonner();
  }
  Socket _socket;
  final Duration _delai;
  StreamSubscription<List<int>>? _sub;
  final StringBuffer _tampon = StringBuffer();
  Completer<void>? _attente;
  bool _ferme = false;

  void _abonner() {
    _sub = _socket.listen((d) {
      _tampon.write(utf8.decode(d, allowMalformed: true));
      _attente?.complete();
      _attente = null;
    }, onDone: () {
      _ferme = true;
      _attente?.complete();
      _attente = null;
    }, onError: (_) {
      _ferme = true;
      _attente?.complete();
      _attente = null;
    });
  }

  /// Remplace la socket (STARTTLS) : l'ancien abonnement est abandonné, le tampon vidé.
  Future<void> passerEnTls(SecureSocket s) async {
    await _sub?.cancel();
    _socket = s;
    _tampon.clear();
    _ferme = false;
    _abonner();
  }

  void ecrire(String t) => _socket.add(utf8.encode(t));

  /// (code, texte) ; code 0 si le délai est dépassé ou si le serveur ferme.
  Future<(int, String)> lire() async {
    final fin = DateTime.now().add(_delai);
    for (;;) {
      final lignes = _tampon.toString().split('\r\n');
      // une réponse est complète quand une ligne « NNN␠… » (4e caractère = espace) est terminée par CRLF
      for (var i = 0; i < lignes.length - 1; i++) {
        final l = lignes[i];
        if (l.length >= 4 && l[3] == ' ') {
          final texte = lignes.sublist(0, i + 1).join('\r\n');
          final reste = lignes.sublist(i + 1).join('\r\n');
          _tampon
            ..clear()
            ..write(reste);
          return (int.tryParse(l.substring(0, 3)) ?? 0, texte.trim());
        }
      }
      if (_ferme) return (0, 'connexion fermée par le serveur');
      final restant = fin.difference(DateTime.now());
      if (restant <= Duration.zero) return (0, 'délai dépassé');
      _attente = Completer<void>();
      await _attente!.future.timeout(restant, onTimeout: () {});
    }
  }

  Future<(int, String)> cmd(String c) async {
    ecrire('$c\r\n');
    return lire();
  }

  Future<void> fermer() async {
    try {
      await _sub?.cancel();
    } catch (_) {}
    try {
      _socket.destroy();
    } catch (_) {}
  }
}

String _enteteTexte(String s) => RegExp(r'[^\x20-\x7e]').hasMatch(s) ? '=?UTF-8?B?${base64.encode(utf8.encode(s))}?=' : s;
String _nettoyer(String s) => s.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
final _adresse = RegExp(r'^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$');

Future<ResultatSmtp> envoyerSmtp(ConfigSmtp cfg, List<String> destinataires, String sujet, String corps) async {
  final etapes = <EtapeSmtp>[];
  ResultatSmtp fin(String? echec) => ResultatSmtp(etapes, echec);
  bool ajouter(String etape, bool ok, String detail) {
    etapes.add(EtapeSmtp(etape, ok, detail));
    return ok;
  }

  String masquer(String s) {
    final m = cfg.motDePasse;
    return m.isEmpty ? s : s.replaceAll(m, '***').replaceAll(base64.encode(utf8.encode(m)), '***');
  }

  final delai = Duration(seconds: max(3, min(60, cfg.delai)));
  final expediteur = _nettoyer(cfg.expediteur);
  if (cfg.serveur.isEmpty || cfg.port <= 0 || !_adresse.hasMatch(expediteur)) {
    ajouter('connexion', false, 'Configuration incomplète : serveur, port et adresse d’expéditeur valides sont requis.');
    return fin('connexion');
  }
  for (final d in destinataires) {
    if (!_adresse.hasMatch(d)) {
      ajouter('destinataire', false, 'Adresse de destinataire invalide : ${_nettoyer(d)}');
      return fin('destinataire');
    }
  }

  // --- 1. connexion
  Socket socket;
  try {
    if (cfg.chiffrement == 'ssl') {
      socket = await SecureSocket.connect(cfg.serveur, cfg.port,
          timeout: delai, onBadCertificate: cfg.verifierCertificat ? null : (_) => true);
    } else {
      socket = await Socket.connect(cfg.serveur, cfg.port, timeout: delai);
    }
  } on HandshakeException catch (e) {
    ajouter('chiffrement', false, 'Connexion chiffrée refusée (certificat ou protocole) : ${e.message}');
    return fin('chiffrement');
  } catch (e) {
    final raison = e is SocketException ? (e.osError?.message ?? e.message) : '$e';
    ajouter('connexion', false, 'Serveur injoignable sur ${cfg.serveur}:${cfg.port} ($raison).');
    return fin('connexion');
  }
  final flux = _Flux(socket, delai);
  Future<void> quitter() async {
    try {
      flux.ecrire('QUIT\r\n');
      await Future<void>.delayed(const Duration(milliseconds: 30));
    } catch (_) {}
    await flux.fermer();
  }

  var (code, rep) = await flux.lire();
  if (code != 220) {
    ajouter('connexion', false, 'Le serveur n’a pas accueilli la connexion : ${masquer(rep)}');
    await flux.fermer();
    return fin('connexion');
  }
  ajouter('connexion', true, 'Connecté à ${cfg.serveur}:${cfg.port}.');

  final nomLocal = (Platform.localHostname).replaceAll(RegExp(r'[^A-Za-z0-9.-]'), '');
  final nom = nomLocal.isEmpty ? 'sigh-cnt' : nomLocal;

  // --- 2. salutation
  (code, rep) = await flux.cmd('EHLO $nom');
  if (code != 250) (code, rep) = await flux.cmd('HELO $nom');
  if (code != 250) {
    ajouter('salutation', false, 'Le serveur refuse la salutation : ${masquer(rep)}');
    await quitter();
    return fin('salutation');
  }
  ajouter('salutation', true, 'Salutation acceptée.');

  // --- 3. chiffrement
  if (cfg.chiffrement == 'starttls') {
    if (!rep.toUpperCase().contains('STARTTLS')) {
      ajouter('chiffrement', false, 'Le serveur n’annonce pas STARTTLS : choisir « SSL » ou « Aucun ».');
      await quitter();
      return fin('chiffrement');
    }
    final (c2, r2) = await flux.cmd('STARTTLS');
    if (c2 != 220) {
      ajouter('chiffrement', false, 'STARTTLS refusé : ${masquer(r2)}');
      await quitter();
      return fin('chiffrement');
    }
    try {
      final s = await SecureSocket.secure(socket, host: cfg.serveur, onBadCertificate: cfg.verifierCertificat ? null : (_) => true);
      await flux.passerEnTls(s);
      socket = s;
    } catch (_) {
      ajouter('chiffrement', false,
          'Négociation TLS refusée${cfg.verifierCertificat ? ' (certificat non reconnu : l’autorité n’est pas de confiance, ou le nom ne correspond pas)' : ''}.');
      await flux.fermer();
      return fin('chiffrement');
    }
    ajouter('chiffrement', true, 'Connexion chiffrée (STARTTLS)${cfg.verifierCertificat ? ', certificat vérifié.' : ', certificat NON vérifié (réglage).'}');
    (code, rep) = await flux.cmd('EHLO $nom');
    if (code != 250) {
      ajouter('salutation', false, 'Salutation refusée après chiffrement : ${masquer(rep)}');
      await quitter();
      return fin('salutation');
    }
  } else if (cfg.chiffrement == 'ssl') {
    ajouter('chiffrement', true, 'Connexion chiffrée (SSL)${cfg.verifierCertificat ? ', certificat vérifié.' : ', certificat NON vérifié (réglage).'}');
  } else {
    ajouter('chiffrement', true, 'Aucun chiffrement (réglage) : le mot de passe circulerait en clair.');
  }

  // --- 4. authentification
  if (cfg.identifiant.isNotEmpty) {
    var (c, r) = await flux.cmd('AUTH PLAIN ${base64.encode(utf8.encode('\u0000${cfg.identifiant}\u0000${cfg.motDePasse}'))}');
    if (c != 235) {
      final (c1, _) = await flux.cmd('AUTH LOGIN');
      if (c1 == 334) {
        final (c2, _) = await flux.cmd(base64.encode(utf8.encode(cfg.identifiant)));
        if (c2 == 334) (c, r) = await flux.cmd(base64.encode(utf8.encode(cfg.motDePasse)));
      }
    }
    if (c != 235) {
      ajouter('authentification', false, 'Identifiant ou mot de passe refusé par le serveur : ${masquer(r)}');
      await quitter();
      return fin('authentification');
    }
    ajouter('authentification', true, 'Authentifié comme ${cfg.identifiant}.');
  } else {
    ajouter('authentification', true, 'Aucune authentification demandée (identifiant vide).');
  }

  // --- 5. expéditeur, 6. destinataires
  (code, rep) = await flux.cmd('MAIL FROM:<$expediteur>');
  if (code != 250) {
    ajouter('expéditeur', false, 'Adresse d’expéditeur refusée : ${masquer(rep)}');
    await quitter();
    return fin('expéditeur');
  }
  ajouter('expéditeur', true, 'Expéditeur accepté.');
  for (final d in destinataires) {
    (code, rep) = await flux.cmd('RCPT TO:<$d>');
    if (code != 250 && code != 251) {
      ajouter('destinataire', false, 'Destinataire refusé ($d) : ${masquer(rep)}');
      await quitter();
      return fin('destinataire');
    }
  }
  ajouter('destinataire', true, '${destinataires.length} destinataire(s) accepté(s).');

  // --- 7. envoi
  (code, rep) = await flux.cmd('DATA');
  if (code != 354) {
    ajouter('envoi', false, 'Le serveur refuse le contenu : ${masquer(rep)}');
    await quitter();
    return fin('envoi');
  }
  final nomAffiche = _nettoyer(cfg.nom);
  final domaine = expediteur.contains('@') ? expediteur.split('@').last : 'sigh-cnt.local';
  final alea = Random.secure();
  final id = [for (var i = 0; i < 12; i++) alea.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
  final b64 = base64.encode(utf8.encode(corps));
  final corpsB64 = [for (var i = 0; i < b64.length; i += 76) b64.substring(i, min(i + 76, b64.length))].join('\r\n');
  // « Répondre à » : une adresse valide, avec son nom si on en donne un ; invalide ou vide, l'en-tête est omis (jamais une adresse devinée).
  final repAdresse = _nettoyer(cfg.repondreA), repNom = _nettoyer(cfg.repondreNom);
  final replyTo = _adresse.hasMatch(repAdresse) ? (repNom.isNotEmpty ? '${_enteteTexte(repNom)} <$repAdresse>' : repAdresse) : null;
  final entetes = [
    'Date: ${HttpDate.format(DateTime.now().toUtc()).replaceFirst('GMT', '+0000')}',
    'From: ${nomAffiche.isNotEmpty ? '${_enteteTexte(nomAffiche)} <$expediteur>' : expediteur}',
    'To: ${destinataires.join(', ')}',
    if (replyTo != null) 'Reply-To: $replyTo',
    'Subject: ${_enteteTexte(_nettoyer(sujet))}',
    'Message-ID: <$id@$domaine>',
    'MIME-Version: 1.0',
    'Content-Type: text/plain; charset=UTF-8',
    'Content-Transfer-Encoding: base64',
  ];
  var message = '${entetes.join('\r\n')}\r\n\r\n$corpsB64\r\n';
  message = message.replaceAll(RegExp(r'^\.', multiLine: true), '..'); // dot-stuffing
  flux.ecrire('$message\r\n.\r\n');
  (code, rep) = await flux.lire();
  if (code != 250) {
    ajouter('envoi', false, 'Le serveur a refusé le message : ${masquer(rep)}');
    await quitter();
    return fin('envoi');
  }
  ajouter('envoi', true, 'Message accepté par le serveur : ${masquer(rep)}');
  await quitter();
  return fin(null);
}
