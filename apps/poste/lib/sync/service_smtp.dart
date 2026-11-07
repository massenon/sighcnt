import 'package:sigh_sync/sigh_sync.dart';

import 'config_smtp.dart';
import 'file_courriels.dart';

export 'package:sigh_sync/sigh_sync.dart' show EtapeSmtp, ResultatSmtp;

/// L'envoi de courriel du poste : le client SMTP du moteur (`packages/sync_dart`) alimenté par la configuration de `smtp.json`. L'interface appelle ces trois
/// gestes et ne connaît pas le moteur.
class ServiceSmtp {
  const ServiceSmtp._();

  static bool configure(String dossier) => ConfigSmtpPoste.lireBrut(dossier)['configure'] == true;
  static bool? testeOk(String dossier) => ConfigSmtpPoste.lireBrut(dossier)['testeOk'] as bool?;

  /// Envoie un message de test avec les réglages du formulaire, enregistrés ou non. Un mot de passe vide reprend celui qui est enregistré. Le résultat n'est retenu
  /// comme « dernier test » que si le formulaire ne change ni serveur, ni port, ni identifiant, ni chiffrement, ni mot de passe.
  static Future<ResultatSmtp> tester(String dossier, Map<String, Object?> f, String destinataire) async {
    final stocke = ConfigSmtpPoste.lireBrut(dossier);
    final saisi = '${f['motDePasse'] ?? ''}';
    final port = int.tryParse('${f['port']}') ?? 0;
    final chiffrement = '${f['chiffrement'] ?? 'starttls'}';
    final cfg = ConfigSmtp(
      serveur: '${f['serveur'] ?? ''}'.trim(),
      port: port,
      chiffrement: chiffrement,
      identifiant: '${f['identifiant'] ?? ''}'.trim(),
      motDePasse: saisi.isNotEmpty ? saisi : ConfigSmtpPoste.motDePasse(dossier),
      expediteur: '${f['expediteur'] ?? ''}'.trim(),
      nom: '${f['nom'] ?? ''}',
      repondreA: '${f['repondreA'] ?? ''}',
      repondreNom: '${f['repondreNom'] ?? ''}',
      delai: int.tryParse('${f['delai']}') ?? 15,
      verifierCertificat: f['verifierCertificat'] != false,
    );
    final r = await envoyerSmtp(cfg, [destinataire.trim()], 'SIGH-CNT : test de la messagerie',
        'Ceci est un message de test envoyé depuis SIGH-CNT.\nSi vous le lisez, la messagerie de la clinique est correctement configurée : accents é è à ç ô, symbole €.');
    final meme = stocke['serveur'] == cfg.serveur &&
        stocke['port'] == cfg.port &&
        stocke['identifiant'] == cfg.identifiant &&
        stocke['chiffrement'] == cfg.chiffrement &&
        saisi.isEmpty &&
        cfg.serveur.isNotEmpty;
    if (meme) ConfigSmtpPoste.noterTest(dossier, ok: r.ok, echec: r.echec);
    return r;
  }

  /// Écrit à l'ÉDITEUR depuis « Contactez l'éditeur » avec la messagerie enregistrée. `null` si elle n'est pas configurée.
  static Future<ResultatSmtp?> ecrireALEditeur(String dossier, {required String destinataire, required String sujet, required String corps}) async {
    final b = ConfigSmtpPoste.lireBrut(dossier);
    if (b['configure'] != true) return null;
    final cfg = ConfigSmtp(
      serveur: '${b['serveur']}',
      port: b['port'] as int,
      chiffrement: '${b['chiffrement']}',
      identifiant: '${b['identifiant']}',
      motDePasse: ConfigSmtpPoste.motDePasse(dossier),
      expediteur: '${b['expediteur']}',
      nom: '${b['nom']}',
      repondreA: '${b['repondreA']}',
      repondreNom: '${b['repondreNom']}',
      delai: b['delai'] as int,
      verifierCertificat: b['verifierCertificat'] == true,
    );
    return envoyerSmtp(cfg, [destinataire], sujet, corps);
  }

  /// Un essai d'envoi d'un message de la FILE (`FileCourriels`) avec la messagerie ENREGISTRÉE, relue à cet instant (le mot de passe ne vit jamais dans la file).
  /// Le `Message-ID` est celui du message : stable d'un essai à l'autre. Messagerie absente ou illisible : échec nommé, l'essai suivant la retrouvera réglée.
  static Future<IssueEnvoi> envoyerDepuisFile(String dossier, MessageCourriel m) async {
    final b = ConfigSmtpPoste.lireBrut(dossier);
    if (b['configure'] != true) return const IssueEnvoi.echec('configuration', 'La messagerie du poste n’est pas configurée.');
    final String mdp;
    try {
      mdp = ConfigSmtpPoste.motDePasse(dossier);
    } on FormatException catch (e) {
      return IssueEnvoi.echec('configuration', e.message);
    }
    final cfg = ConfigSmtp(
      serveur: '${b['serveur']}',
      port: b['port'] as int,
      chiffrement: '${b['chiffrement']}',
      identifiant: '${b['identifiant']}',
      motDePasse: mdp,
      expediteur: '${b['expediteur']}',
      nom: '${b['nom']}',
      repondreA: '${b['repondreA']}',
      repondreNom: '${b['repondreNom']}',
      delai: b['delai'] as int,
      verifierCertificat: b['verifierCertificat'] == true,
    );
    final r = await envoyerSmtp(cfg, [m.destinataire], m.sujet, m.corps, messageId: m.id);
    if (r.ok) return const IssueEnvoi.parti();
    final e = r.etapes.where((x) => !x.ok).firstOrNull;
    return IssueEnvoi.echec(r.echec ?? 'envoi', e?.detail ?? 'Échec sans détail.');
  }
}
