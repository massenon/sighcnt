import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../../sync/config_smtp.dart';
import '../../sync/service_smtp.dart';
import 'cfa_commun.dart';
import 'cfb_commun.dart';

/// `cfg-smtp` : la messagerie de la clinique (serveur SMTP) et son TEST D'ENVOI. Le bouton de test envoie VRAIMENT un message et montre la suite d'étapes
/// (connecté, chiffré, authentifié, envoyé) ou l'étape où cela échoue. Le mot de passe est saisi, chiffré dans `smtp.json` et JAMAIS relu : l'écran ne l'affiche pas.
class EcranSmtp extends StatefulWidget with EcranMaquette {
  const EcranSmtp({super.key});
  @override
  String get titre => 'Messagerie (SMTP)';
  @override
  String get description => 'Serveur de courriel de la clinique et test d’envoi : sert à écrire à l’éditeur et, plus tard, à tout envoi de la clinique.';
  @override
  String get regle =>
      'Le mot de passe n’est jamais relu : l’écran ne l’affiche pas, le magasin exporté ne le contient pas. Le test envoie un vrai message et dit à quelle étape il échoue.';

  @override
  State<EcranSmtp> createState() => _EtatSmtp();
}

const _libellesEtapes = {
  'connexion': 'Connexion au serveur',
  'salutation': 'Salutation',
  'chiffrement': 'Chiffrement',
  'authentification': 'Authentification',
  'expéditeur': 'Expéditeur',
  'destinataire': 'Destinataire',
  'envoi': 'Envoi du message',
};

/// La configuration fournie par la clinique (valeurs NON secrètes), proposée tant que rien n'est enregistré. Le mot de passe n'y figure pas : il se saisit.
const Map<String, Object?> smtpDefauts = {
  'serveur': 'mail.sigh.nassieratoo.com',
  'port': 587,
  'chiffrement': 'starttls',
  'delai': 20,
  'identifiant': 'contact@sigh.nassieratoo.com',
  'expediteur': 'contact@sigh.nassieratoo.com',
  'nom': 'Clinique Nassièra Too',
  'repondreA': 'cliniquenassiera@gmail.com',
  'repondreNom': 'Clinique Nassièra Too',
};

class _EtatSmtp extends State<EcranSmtp> {
  ControleurFormulaire? _config, _test;
  Map<String, Object?> _brut = {};
  ResultatSmtp? _dernier;
  bool _enCours = false, _pret = false;
  String _adresseTest = '';

  String? get _dossier => EtatSmtpPoste.dossier;

  void _relire() => _brut = _dossier == null ? {} : ConfigSmtpPoste.lireBrut(_dossier!);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pret) return;
    _pret = true;
    _relire();
    // Rien d'enregistré : le formulaire PROPOSE la configuration de la clinique (valeurs non secrètes) ; une fois enregistrée, c'est elle qui fait foi. Le mot de passe
    // n'a aucune valeur par défaut.
    final v0 = _brut['configure'] == true ? _brut : {..._brut, ...smtpDefauts};
    _config = ControleurFormulaire(const [
      ChampDef(nom: 'serveur', libelle: 'Serveur SMTP', requis: true, aide: 'Exemple : smtp.exemple.bj'),
      ChampDef(nom: 'port', libelle: 'Port', type: TypeChamp.nombre, requis: true, col: ColChamp.tiers, aide: '587 (STARTTLS), 465 (SSL), 25 (aucun)'),
      ChampDef(
          nom: 'chiffrement',
          libelle: 'Chiffrement',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.tiers,
          options: [OptionChamp('starttls', 'STARTTLS'), OptionChamp('ssl', 'SSL'), OptionChamp('aucun', 'Aucun (déconseillé)')]),
      ChampDef(nom: 'delai', libelle: 'Délai (secondes)', type: TypeChamp.nombre, col: ColChamp.tiers),
      ChampDef(nom: 'identifiant', libelle: 'Identifiant', aide: 'Laisser vide si le serveur n’exige aucune authentification.'),
      ChampDef(nom: 'motDePasse', libelle: 'Mot de passe', type: TypeChamp.motDePasse, aide: 'Jamais relu après enregistrement.'),
      ChampDef(nom: 'expediteur', libelle: 'Adresse d’expéditeur', type: TypeChamp.email, requis: true),
      ChampDef(nom: 'nom', libelle: 'Nom affiché de l’expéditeur'),
      ChampDef(nom: 'repondreA', libelle: 'Répondre à (adresse)', type: TypeChamp.email, aide: 'Les réponses des destinataires iront à cette adresse (en-tête Reply-To).'),
      ChampDef(nom: 'repondreNom', libelle: 'Répondre à (nom)'),
      ChampDef(nom: 'verifierCertificat', libelle: 'Vérifier le certificat du serveur', type: TypeChamp.case_, col: ColChamp.plein),
    ], {
      'serveur': v0['serveur'] ?? '',
      'port': '${v0['port'] ?? 587}',
      'chiffrement': v0['chiffrement'] ?? 'starttls',
      'delai': '${v0['delai'] ?? 15}',
      'identifiant': v0['identifiant'] ?? '',
      'motDePasse': '',
      'expediteur': v0['expediteur'] ?? '',
      'nom': v0['nom'] ?? '',
      'repondreA': v0['repondreA'] ?? '',
      'repondreNom': v0['repondreNom'] ?? '',
      'verifierCertificat': v0['verifierCertificat'] != false,
    });
    _test = ControleurFormulaire(const [
      ChampDef(nom: 'destinataire', libelle: 'Adresse de test', type: TypeChamp.email, requis: true, col: ColChamp.plein, aide: 'Un message de test y sera envoyé avec les réglages ci-dessus, enregistrés ou non.'),
    ]);
  }

  @override
  void dispose() {
    _config?.dispose();
    _test?.dispose();
    super.dispose();
  }

  void _enregistrer(BuildContext ctx, ContexteEcran c) {
    final v = _config!.valider();
    final d = _dossier;
    if (v == null) {
      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
      return;
    }
    if (d == null) {
      ToastsSigh.afficher(ctx, 'Le dossier des données de ce poste est inconnu : la messagerie ne peut pas être enregistrée.', type: TypeToast.erreur);
      return;
    }
    try {
      ConfigSmtpPoste.ecrire(d,
          serveur: '${v['serveur']}',
          port: int.tryParse('${v['port']}') ?? 0,
          chiffrement: '${v['chiffrement']}',
          identifiant: '${v['identifiant'] ?? ''}',
          motDePasse: '${v['motDePasse'] ?? ''}',
          expediteur: '${v['expediteur']}',
          nom: '${v['nom'] ?? ''}',
          repondreA: '${v['repondreA'] ?? ''}',
          repondreNom: '${v['repondreNom'] ?? ''}',
          delai: int.tryParse('${v['delai']}') ?? 15,
          verifierCertificat: v['verifierCertificat'] == true);
    } on FormatException catch (e) {
      ToastsSigh.afficher(ctx, e.message, type: TypeToast.erreur);
      return;
    }
    c.magasin.journaliser('Modification', 'CFG', 'Messagerie (SMTP)', '${v['serveur']}', null,
        {'serveur': v['serveur'], 'port': v['port'], 'chiffrement': v['chiffrement'], 'motDePasse': '${v['motDePasse'] ?? ''}'.isEmpty ? 'inchangé' : 'changé'});
    _config!.poser('motDePasse', '');
    ToastsSigh.afficher(ctx, 'Messagerie enregistrée. Le dernier test n’est plus valable : refaire un test d’envoi.', type: TypeToast.succes);
    setState(() {
      _dernier = null;
      _relire();
    });
  }

  Future<void> _tester(BuildContext ctx, ContexteEcran c) async {
    final v = _config!.valider(), t = _test!.valider();
    final d = _dossier;
    if (v == null || t == null) {
      ToastsSigh.afficher(ctx, 'Renseigner les réglages du serveur et l’adresse de test.', type: TypeToast.erreur);
      return;
    }
    if (d == null) {
      ToastsSigh.afficher(ctx, 'Le dossier des données de ce poste est inconnu : le test ne peut pas partir.', type: TypeToast.erreur);
      return;
    }
    setState(() {
      _enCours = true;
      _adresseTest = '${t['destinataire']}';
    });
    ResultatSmtp r;
    try {
      r = await ServiceSmtp.tester(d, v, '${t['destinataire']}');
    } on FormatException catch (e) {
      if (mounted) {
        setState(() => _enCours = false);
        ToastsSigh.afficher(ctx, e.message, type: TypeToast.erreur);
      }
      return;
    }
    c.magasin.journaliser('Test d’envoi', 'CFG', 'Messagerie (SMTP)', '${v['serveur']}', null, {'ok': r.ok, 'echec': r.echec});
    if (!mounted) return;
    _config!.poser('motDePasse', '');
    setState(() {
      _enCours = false;
      _dernier = r;
      _relire();
    });
  }

  Widget _rendreEtapes(ResultatSmtp r) => cfaPile([
        cfbNote(
            r.ok
                ? 'Message de test envoyé. Vérifier sa réception dans la boîte du destinataire.'
                : 'Échec à l’étape « ${_libellesEtapes[r.echec] ?? r.echec} ». Corriger ce réglage puis refaire le test.',
            ton: r.ok ? 'success' : 'danger',
            icone: r.ok ? LucideIcons.mailCheck : LucideIcons.mailX),
        for (final e in r.etapes)
          Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(e.ok ? LucideIcons.circleCheck : LucideIcons.circleX, size: 16, color: e.ok ? JetonsShell.success600 : JetonsShell.danger600)),
                const SizedBox(width: 8),
                Expanded(child: Text('${_libellesEtapes[e.etape] ?? e.etape} : ${e.detail}', key: Key('smtp:etape-${e.etape}'), style: const TextStyle(fontSize: 14))),
              ])),
      ]);

  static String _dateFr(String iso) {
    final p = iso.split('T').first.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final configure = _brut['configure'] == true;
    final testeOk = _brut['testeOk'] as bool?;
    final chiffrement = _brut['chiffrement'] ?? 'starttls';
    final defini = _brut['motDePasseDefini'] == true;
    return ListenableBuilder(
        listenable: Listenable.merge([_config!, _test!]),
        builder: (ctx, _) => cfaPile([
              KpiGrilleSigh(kpis: [
                KpiSigh(libelle: 'Messagerie', valeur: configure ? 'Configurée' : 'Non configurée', icone: LucideIcons.mail, ton: configure ? TonSigh.succes : TonSigh.attention),
                KpiSigh(
                    libelle: 'Dernier test',
                    valeur: testeOk == true ? 'Réussi' : (testeOk == false ? 'Échoué' : 'Jamais fait'),
                    icone: LucideIcons.send,
                    ton: testeOk == true ? TonSigh.succes : (testeOk == false ? TonSigh.danger : TonSigh.neutre)),
                KpiSigh(
                    libelle: 'Chiffrement',
                    valeur: const {'aucun': 'Aucun', 'starttls': 'STARTTLS', 'ssl': 'SSL'}['$chiffrement'] ?? '',
                    icone: LucideIcons.lock,
                    ton: chiffrement == 'aucun' ? TonSigh.attention : TonSigh.navy),
                KpiSigh(libelle: 'Mot de passe', valeur: defini ? 'Défini' : 'Non défini', icone: LucideIcons.keyRound, ton: defini ? TonSigh.succes : TonSigh.neutre),
              ]),
              if (_brut['mdp_illisible'] == true)
                cfbNote('Le mot de passe enregistré est ILLISIBLE (fichier altéré, ou chiffré par un autre poste ou une autre session Windows) : le saisir de nouveau.', ton: 'danger', icone: LucideIcons.keyRound),
              CarteSigh(
                  titre: 'Serveur de courriel',
                  child: cfaPile([
                    FormulaireSigh(controleur: _config!),
                    if (c.droit.editer)
                      Align(alignment: Alignment.centerLeft, child: BoutonSigh(libelle: 'Enregistrer la messagerie', icone: LucideIcons.save, onPressed: () => _enregistrer(ctx, c))),
                  ])),
              CarteSigh(
                  titre: 'Test d’envoi',
                  child: cfaPile([
                    FormulaireSigh(controleur: _test!),
                    if (c.droit.editer)
                      Align(
                          alignment: Alignment.centerLeft,
                          child: BoutonSigh(libelle: 'Envoyer un message de test', icone: LucideIcons.send, onPressed: _enCours ? null : () => _tester(ctx, c))),
                    if (_enCours)
                      const Text('Envoi en cours…', style: TextStyle(fontSize: 14, color: JetonsShell.slate500))
                    else if (_dernier != null)
                      _rendreEtapes(_dernier!)
                    else if (testeOk != null && _brut['testeLe'] != null)
                      Text('Dernier test (${_dateFr('${_brut['testeLe']}')}) : ${testeOk ? 'réussi.' : 'échoué à l’étape « ${_libellesEtapes['${_brut['testeEchec']}'] ?? _brut['testeEchec']} ».'}',
                          style: const TextStyle(fontSize: 14, color: JetonsShell.slate600)),
                    if (_adresseTest.isEmpty) const SizedBox.shrink(),
                  ])),
            ]));
  }
}
