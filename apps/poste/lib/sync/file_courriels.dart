import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'config_pair.dart';

/// LA FILE D'ENVOI DES COURRIELS DU POSTE. Un courriel n'est plus envoyé « tout de suite ou perdu » : il est d'abord ÉCRIT dans `courriels.json` du dossier de
/// données (écriture atomique : fichier temporaire puis renommage, donc un `kill -9` en plein geste laisse l'ancienne version intacte), puis envoyé, avec reprise.
///
/// États : `en_file` (prochain essai à une heure dite), `en_cours` (un essai est parti), `parti`, `echec_definitif` (les essais sont épuisés ; le bouton « Renvoyer » le
/// remet en file). Délais entre essais : 1 min, 5 min, 30 min, 2 h, puis 12 h ; huit essais au plus.
///
/// ENVOI DIRECT D'ABORD, FILE ENSUITE (décision de la Direction du 06/11/2026) : `ajouter()` écrit le message puis TENTE L'ENVOI TOUT DE SUITE ; connecté, le
/// courriel part sans attendre la minuterie et l'écran dit « Parti » ; coupé, il reste en file avec l'étape en échec nommée et les reprises espacées. Le VERROU
/// est PAR MESSAGE : l'état `en_cours` est écrit de façon synchrone avant le premier `await`, si bien que l'essai immédiat et la minuterie ne peuvent jamais
/// envoyer deux fois le même courriel ; il n'y a plus de verrou global, qui faisait attendre un envoi immédiat derrière un tour de minuterie.
///
/// GARANTIE : AU MOINS UNE FOIS, jamais « exactement une ». Au redémarrage, un message resté `en_cours` repart. S'il avait été interrompu ENTRE la commande DATA et la
/// réponse du serveur, le serveur a pu l'accepter sans que le poste l'apprenne : le destinataire en reçoit alors deux. Le `Message-ID` est STABLE (l'identifiant du
/// message de la file) pour que sa messagerie puisse dédoublonner. Éviter le doublon exigerait de perdre un courriel sur une coupure : c'est le mauvais côté.
///
/// RG-14 : rien ne se supprime. Un message `parti` reste au fichier (c'est l'archive) ; un échec définitif aussi. Le MOT DE PASSE SMTP n'entre JAMAIS dans la file :
/// il est relu au moment de l'envoi. Le fichier est chiffré (AES-256-GCM, clé locale du poste) quand cette clé existe, comme `pair.json` et `smtp.json`.
class MessageCourriel {
  MessageCourriel({
    required this.id,
    required this.destinataire,
    required this.sujet,
    required this.corps,
    required this.creeLe,
    this.reference,
    this.etat = 'en_file',
    this.essais = 0,
    this.renvois = 0,
    this.prochainEssaiLe,
    this.etapeEchec,
    this.detailEchec,
    this.partiLe,
    this.repris = false,
  });

  final String id, destinataire, sujet, corps;
  final DateTime creeLe;

  /// La pièce d'origine (référence de la demande de support), pour la retrouver à l'écran.
  final String? reference;
  String etat;
  int essais, renvois;
  DateTime? prochainEssaiLe, partiLe;

  /// La dernière étape en échec (`connexion`, `authentification`…) et son détail : jamais un « Non parti » sans dire où.
  String? etapeEchec, detailEchec;

  /// Vrai si le message a été REPRIS après une interruption (il a pu partir deux fois : voir la garantie ci-dessus).
  bool repris;

  Map<String, Object?> versJson() => {
        'id': id,
        'destinataire': destinataire,
        'sujet': sujet,
        'corps': corps,
        'creeLe': creeLe.toIso8601String(),
        'reference': reference,
        'etat': etat,
        'essais': essais,
        'renvois': renvois,
        'prochainEssaiLe': prochainEssaiLe?.toIso8601String(),
        'etapeEchec': etapeEchec,
        'detailEchec': detailEchec,
        'partiLe': partiLe?.toIso8601String(),
        'repris': repris,
      };

  static MessageCourriel depuisJson(Map<String, Object?> j) => MessageCourriel(
        id: '${j['id']}',
        destinataire: '${j['destinataire']}',
        sujet: '${j['sujet']}',
        corps: '${j['corps']}',
        creeLe: DateTime.parse('${j['creeLe']}'),
        reference: j['reference'] as String?,
        etat: '${j['etat'] ?? 'en_file'}',
        essais: (j['essais'] as num?)?.toInt() ?? 0,
        renvois: (j['renvois'] as num?)?.toInt() ?? 0,
        prochainEssaiLe: j['prochainEssaiLe'] == null ? null : DateTime.parse('${j['prochainEssaiLe']}'),
        etapeEchec: j['etapeEchec'] as String?,
        detailEchec: j['detailEchec'] as String?,
        partiLe: j['partiLe'] == null ? null : DateTime.parse('${j['partiLe']}'),
        repris: j['repris'] == true,
      );
}

/// Le résultat d'UN essai d'envoi : parti, ou l'étape en échec avec son détail.
class IssueEnvoi {
  const IssueEnvoi.parti()
      : ok = true,
        etape = null,
        detail = null;
  const IssueEnvoi.echec(String this.etape, String this.detail) : ok = false;
  final bool ok;
  final String? etape, detail;
}

typedef Envoyeur = Future<IssueEnvoi> Function(MessageCourriel m);

class FileCourriels extends ChangeNotifier {
  FileCourriels(this.dossier, {required this.envoyer, DateTime Function()? maintenant, List<Duration>? delais, this.maxEssais = 8})
      : _maintenant = maintenant ?? DateTime.now,
        delais = delais ?? const [Duration(minutes: 1), Duration(minutes: 5), Duration(minutes: 30), Duration(hours: 2), Duration(hours: 12)] {
    _charger();
  }

  final String dossier;
  final Envoyeur envoyer;
  final DateTime Function() _maintenant;
  final List<Duration> delais;
  final int maxEssais;

  final List<MessageCourriel> _messages = [];
  Timer? _minuterie;

  /// Non nul si `courriels.json` n'a pas pu être lu : la file refuse alors toute écriture plutôt que d'écraser ce qu'elle ne comprend pas.
  String? erreur;

  static const _aad = 'courriels.json';
  static final _aes = AesGcm.with256bits().toSync();

  File get _fichier => File('$dossier/courriels.json');

  List<MessageCourriel> get messages => List.unmodifiable(_messages);
  MessageCourriel? message(String id) => _messages.where((m) => m.id == id).firstOrNull;
  int compter(String etat) => _messages.where((m) => m.etat == etat).length;

  // --- persistance atomique -------------------------------------------------------------------------------------------------------------------------
  void _charger() {
    if (!_fichier.existsSync()) return;
    try {
      final j = jsonDecode(_fichier.readAsStringSync()) as Map;
      List liste;
      if (j['chiffre'] != null) {
        final locale = ConfigPairPoste.cleLocale;
        if (locale == null) throw const FormatException('la file est chiffrée par la clé locale de ce poste, qui n’est pas disponible (SIGH_CHIFFREMENT=non ?)');
        final boite = SecretBox.fromConcatenation(base64.decode('${j['chiffre']}'), nonceLength: 12, macLength: 16);
        liste = (jsonDecode(utf8.decode(_aes.decryptSync(boite, secretKeyData: SecretKeyData(locale), aad: utf8.encode(_aad)))) as Map)['messages'] as List;
      } else {
        liste = j['messages'] as List;
      }
      _messages.addAll(liste.map((m) => MessageCourriel.depuisJson((m as Map).cast<String, Object?>())));
    } catch (e) {
      erreur = 'courriels.json illisible : ${e is FormatException ? e.message : e}. Le fichier n’est pas modifié.';
      _messages.clear();
    }
  }

  void _ecrire() {
    if (erreur != null) throw StateError(erreur!);
    Directory(dossier).createSync(recursive: true);
    final corps = jsonEncode({'messages': [for (final m in _messages) m.versJson()]});
    final locale = ConfigPairPoste.cleLocale;
    final contenu = locale == null
        ? '{"v":1,"messages":${jsonEncode([for (final m in _messages) m.versJson()])}}'
        : jsonEncode({'v': 1, 'chiffre': base64.encode(_aes.encryptSync(utf8.encode(corps), secretKeyData: SecretKeyData(locale), aad: utf8.encode(_aad)).concatenation())});
    final tmp = File('${_fichier.path}.tmp');
    tmp.writeAsStringSync(contenu, flush: true);
    tmp.renameSync(_fichier.path);
  }

  // --- gestes -----------------------------------------------------------------------------------------------------------------------------------------
  /// Met un courriel en file : il est ÉCRIT sur disque avant que cette méthode rende la main (rien à perdre ensuite), puis, par défaut, l'essai d'envoi part
  /// TOUT DE SUITE en arrière-plan ([immediat] ; `false` pour laisser la minuterie faire, ou pour attendre soi-même l'issue par [essayer]). Lève [StateError] si la
  /// file est illisible.
  MessageCourriel ajouter({required String destinataire, required String sujet, required String corps, String? reference, bool immediat = true}) {
    final m = MessageCourriel(
      id: _identifiant(),
      destinataire: destinataire,
      sujet: sujet,
      corps: corps,
      creeLe: _maintenant(),
      reference: reference,
      prochainEssaiLe: _maintenant(),
    );
    _messages.add(m);
    try {
      _ecrire();
    } catch (_) {
      _messages.remove(m);
      rethrow;
    }
    notifyListeners();
    if (immediat) unawaited(essayer(m.id));
    return m;
  }

  /// Met en file PUIS attend l'issue du premier essai : l'appelant sait, au retour, si le courriel est parti ou pourquoi il attend.
  Future<MessageCourriel> ajouterEtEnvoyer({required String destinataire, required String sujet, required String corps, String? reference}) async {
    final m = ajouter(destinataire: destinataire, sujet: sujet, corps: corps, reference: reference, immediat: false);
    await essayer(m.id);
    return m;
  }

  /// Au démarrage du poste : un message resté `en_cours` (le poste s'est arrêté pendant l'essai) repart tout de suite, marqué « repris ».
  void reprendre() {
    var change = false;
    for (final m in _messages.where((m) => m.etat == 'en_cours')) {
      m.etat = 'en_file';
      m.repris = true;
      m.prochainEssaiLe = _maintenant();
      change = true;
    }
    if (change) {
      _ecrire();
      notifyListeners();
    }
  }

  /// Remet en file un échec définitif (bouton « Renvoyer ») : le compteur d'essais repart de zéro, l'historique des renvois reste.
  void renvoyer(String id) {
    final m = message(id);
    if (m == null || m.etat != 'echec_definitif') return;
    m.etat = 'en_file';
    m.essais = 0;
    m.renvois += 1;
    m.prochainEssaiLe = _maintenant();
    _ecrire();
    notifyListeners();
  }

  /// UN essai pour UN message. Le message passe `en_cours` sur disque AVANT l'envoi (une interruption le laisse repérable), de façon SYNCHRONE : c'est le verrou
  /// par message. Un message qui n'est plus `en_file` (déjà en cours, parti, ou en échec définitif) est ignoré : l'essai immédiat et la minuterie ne se doublent pas.
  Future<void> essayer(String id) async {
    if (erreur != null) return;
    final m = message(id);
    if (m == null || m.etat != 'en_file') return;
    m.etat = 'en_cours';
    _ecrire();
    notifyListeners();
    IssueEnvoi issue;
    try {
      issue = await envoyer(m);
    } catch (e) {
      issue = IssueEnvoi.echec('envoi', 'Erreur inattendue : $e');
    }
    m.essais += 1;
    if (issue.ok) {
      m
        ..etat = 'parti'
        ..partiLe = _maintenant()
        ..prochainEssaiLe = null
        ..etapeEchec = null
        ..detailEchec = null;
    } else {
      m
        ..etapeEchec = issue.etape
        ..detailEchec = issue.detail;
      if (m.essais >= maxEssais) {
        m
          ..etat = 'echec_definitif'
          ..prochainEssaiLe = null;
      } else {
        m
          ..etat = 'en_file'
          ..prochainEssaiLe = _maintenant().add(delais[(m.essais - 1).clamp(0, delais.length - 1)]);
      }
    }
    _ecrire();
    notifyListeners();
  }

  /// Traite les messages DUS (la minuterie, ou un appel explicite), l'un après l'autre. Un message déjà en cours d'envoi est laissé à son essai.
  Future<void> traiter() async {
    if (erreur != null) return;
    final auj = _maintenant();
    for (final m in _messages.where((m) => m.etat == 'en_file' && !(m.prochainEssaiLe ?? auj).isAfter(auj)).toList()) {
      await essayer(m.id);
    }
  }

  /// Lance la reprise puis une minuterie (30 s) qui traite ce qui est dû. Sans appel, rien ne tourne en arrière-plan (tests).
  void demarrer({Duration periode = const Duration(seconds: 30)}) {
    reprendre();
    _minuterie?.cancel();
    _minuterie = Timer.periodic(periode, (_) => unawaited(traiter()));
    unawaited(traiter());
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    super.dispose();
  }

  int _n = 0;
  String _identifiant() {
    final t = _maintenant().microsecondsSinceEpoch.toRadixString(16);
    final a = (DateTime.now().microsecondsSinceEpoch ^ (++_n * 2654435761)).toRadixString(16);
    return 'm$t$a';
  }
}
