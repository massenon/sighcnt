import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/identifiants.dart';
import '../../core/jetons_shell.dart';
import '../../core/service_installation.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_autonome.dart';
import 'acc_ecrans.dart';
import 'acc_gabarit.dart';

/// PREMIÈRE INSTALLATION (PRD-POSTE-premiere-installation, PLAN étapes 3 et 4). Écrans AUTONOMES (sans coque) : un poste sans compte ne peut rien ouvrir d'autre.
/// ÉCRANS DE LA CIBLE : la maquette n'a pas d'assistant d'installation (voir ECARTS-MAQUETTE, E2100).

/// La route `index` : l'assistant sur un poste jamais installé et sans compte connectable, sinon la connexion. Le service est inactif tant qu'aucun stockage
/// ne lui est attaché : les tests et `SIGH_ASSISTANT=non` gardent leur chemin d'avant.
class EcranIndex extends StatelessWidget with EcranAutonome {
  const EcranIndex({super.key});

  @override
  Widget build(BuildContext context) {
    final x = ContexteAutonome.of(context);
    final service = ServiceInstallation.de(x.magasin);
    return ListenableBuilder(
        listenable: service,
        builder: (_, __) => service.propose() ? const EcranAccueilInstallation() : const EcranConnexion());
  }
}

/// Les deux chemins d'un poste neuf.
class EcranAccueilInstallation extends StatelessWidget {
  const EcranAccueilInstallation({super.key});

  @override
  Widget build(BuildContext context) => SceneAcces(
        icone: LucideIcons.rocket,
        titre: 'Installation du poste',
        sousTitre: 'Ce poste n’a encore aucun compte. Choisissez ce que vous voulez faire.',
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          BoutonSigh(
              key: const Key('ins:premiere'),
              libelle: 'Première installation de la clinique',
              taille: TailleBouton.lg,
              icone: LucideIcons.building2,
              onPressed: () => ContexteAutonome.of(context).aller('ins-premiere')),
          const SizedBox(height: 8),
          const Text('Ce poste devient le poste principal : vous créez le compte administrateur, puis vous configurez la clinique.',
              style: TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
          const SizedBox(height: 24),
          BoutonSigh(
              key: const Key('ins:rejoindre'),
              libelle: 'Rejoindre une clinique existante',
              variante: VarianteBouton.secondaire,
              taille: TailleBouton.lg,
              icone: LucideIcons.link,
              onPressed: () => ContexteAutonome.of(context).aller('ins-rejoindre')),
          const SizedBox(height: 8),
          const Text('La clinique est déjà installée sur un autre poste : vous saisissez l’adresse de ce poste et un code d’appairage. Aucune configuration à refaire.',
              style: TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
        ]),
      );
}

/// Création du premier compte administrateur, puis affichage UNIQUE de son code de secours.
class EcranPremiereInstallation extends StatefulWidget with EcranAutonome {
  const EcranPremiereInstallation({super.key});
  @override
  State<EcranPremiereInstallation> createState() => _EtatPremiere();
}

class _EtatPremiere extends State<EcranPremiereInstallation> {
  final _nom = TextEditingController();
  final _id = TextEditingController();
  final _mdp = TextEditingController();
  final _conf = TextEditingController();
  String? _erreur;
  bool _occupe = false;

  /// Renseignés une fois le compte créé : l'écran bascule sur le code de secours.
  AccCompte? _compte;
  String? _code;
  bool _range = false;

  @override
  void initState() {
    super.initState();
    _mdp.addListener(() {
      if (mounted && _compte == null) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final c in [_nom, _id, _mdp, _conf]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _creer() async {
    if (_occupe) return;
    final x = ContexteAutonome.of(context);
    setState(() {
      _occupe = true;
      _erreur = null;
    });
    final r = await ServiceInstallation.de(x.magasin)
        .creerPremierAdministrateur(identifiant: _id.text, nom: _nom.text, motDePasse: _mdp.text, confirmation: _conf.text, maintenant: x.maintenant);
    if (!mounted) return;
    setState(() {
      _occupe = false;
      if (r.ok) {
        _compte = r.compte;
        _code = r.codeSecours;
        // Le mot de passe n'a plus de raison de rester dans le champ.
        _mdp.clear();
        _conf.clear();
      } else {
        _erreur = r.message;
      }
    });
  }

  Widget _formulaire() => SceneAcces(
        icone: LucideIcons.userRoundPlus,
        titre: 'Créer l’administrateur',
        sousTitre: 'Le premier compte du poste. Vous choisissez vous-même votre mot de passe : il n’est écrit nulle part.',
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ChampAcces(cle: const Key('ins:nom'), libelle: 'Nom complet', controleur: _nom, indicatif: 'NOM Prénom', autofocus: true),
          const SizedBox(height: 16),
          ChampAcces(cle: const Key('ins:identifiant'), libelle: 'Identifiant', controleur: _id, indicatif: 'prenom.nom'),
          const SizedBox(height: 16),
          ChampAcces(cle: const Key('ins:motdepasse'), libelle: 'Mot de passe', controleur: _mdp, indicatif: '••••••••••••', masque: true),
          const SizedBox(height: 16),
          ChampAcces(
              cle: const Key('ins:confirmation'),
              libelle: 'Confirmer le mot de passe',
              controleur: _conf,
              indicatif: '••••••••••••',
              masque: true,
              surValidation: _creer),
          const SizedBox(height: 16),
          reglesPolitiqueAcces(_mdp.text, _id.text.trim()),
          if (_erreur != null) Padding(padding: const EdgeInsets.only(top: 16), child: MessageErreurAcces(_erreur!)),
          const SizedBox(height: 16),
          BoutonSigh(key: const Key('ins:creer'), libelle: 'Créer le compte', taille: TailleBouton.lg, icone: LucideIcons.userRoundPlus, onPressed: _creer),
        ]),
        pied: LienAcces('← Retour', onTap: () => ContexteAutonome.of(context).aller('index')),
      );

  @override
  Widget build(BuildContext context) {
    if (_compte == null) return _formulaire();
    return SceneCodeSecours(
        cle: 'ins',
        titre: 'Votre code de secours',
        sousTitre: 'Il permet de retrouver l’accès administrateur si vous perdez votre mot de passe.',
        code: _code!,
        auteur: _compte!.nom,
        confirmation: _range,
        surConfirmation: (v) => setState(() => _range = v),
        libelleSuite: 'Ouvrir le tableau de bord',
        surSuite: () => ouvrirSessionAcces(ContexteAutonome.of(context), _compte!));
  }
}

/// L'affichage UNIQUE d'un code de secours : copier, imprimer, et une case « je l'ai rangé » qui conditionne la suite. Sans lui, le poste n'a aucun chemin
/// d'urgence : l'écran le dit en toutes lettres.
class SceneCodeSecours extends StatelessWidget {
  const SceneCodeSecours({
    super.key,
    required this.cle,
    required this.titre,
    required this.sousTitre,
    required this.code,
    required this.auteur,
    required this.confirmation,
    required this.surConfirmation,
    required this.libelleSuite,
    required this.surSuite,
  });
  final String cle, titre, sousTitre, code, auteur, libelleSuite;
  final bool confirmation;
  final ValueChanged<bool> surConfirmation;
  final VoidCallback surSuite;

  PieceA4 _piece(BuildContext c) => PieceA4(
        titre: 'Code de secours de l’administrateur',
        sousTitre: 'Document confidentiel à ranger au coffre',
        reference: PieceA4.reference_(DateTime.now(), ImpressionPoste.prochainNumero()),
        utilisateur: auteur,
        edite: DateTime.now(),
        blocs: [
          const BlocTexte('Ce code permet de retrouver l’accès administrateur de ce poste si le mot de passe est perdu. Il ne fonctionne qu’une fois : un nouveau code est affiché après chaque usage.'),
          BlocTexte(code, gras: true),
          const BlocTexte('Sans ce code, il n’existe aucun chemin d’urgence : réinstaller le poste supprimerait les saisies non synchronisées. Ne le photographiez pas, ne l’envoyez pas par message.', italique: true),
        ],
        signatures: const [],
        lieuDate: true,
      );

  @override
  Widget build(BuildContext context) => SceneAcces(
        icone: LucideIcons.shieldCheck,
        titre: titre,
        sousTitre: sousTitre,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
              key: Key('$cle:code'),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: JetonsShell.slate50, border: Border.all(color: JetonsShell.slate200), borderRadius: BorderRadius.circular(8)),
              child: SelectableText(code,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'LiberationMono', fontWeight: FontWeight.w700, fontSize: 18, color: JetonsShell.slate900))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: BoutonSigh(
                    key: Key('$cle:copier'),
                    libelle: 'Copier',
                    variante: VarianteBouton.secondaire,
                    icone: LucideIcons.copy,
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: code));
                      if (context.mounted) ToastsSigh.afficher(context, 'Code copié.', type: TypeToast.succes);
                    })),
            const SizedBox(width: 8),
            Expanded(
                child: BoutonSigh(
                    key: Key('$cle:imprimer'),
                    libelle: 'Imprimer',
                    variante: VarianteBouton.secondaire,
                    icone: LucideIcons.printer,
                    onPressed: () => afficherApercu(context, _piece(context)))),
          ]),
          const SizedBox(height: 16),
          const NoteSigh(
              'Ce code ne s’affiche qu’UNE fois. Rangez-le au coffre maintenant. Sans lui, si vous perdez votre mot de passe et qu’aucun autre administrateur ne peut le réinitialiser, il n’existe aucun chemin d’urgence : réinstaller le poste supprimerait les saisies non synchronisées.',
              icone: LucideIcons.triangleAlert),
          const SizedBox(height: 12),
          InkWell(
              key: Key('$cle:range'),
              onTap: () => surConfirmation(!confirmation),
              child: Row(children: [
                SizedBox(
                    width: 24, height: 24, child: Checkbox(value: confirmation, visualDensity: VisualDensity.compact, onChanged: (v) => surConfirmation(v ?? false))),
                const SizedBox(width: 8),
                const Expanded(
                    child: Text('J’ai rangé ce code en lieu sûr.', style: TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14))),
              ])),
          const SizedBox(height: 16),
          BoutonSigh(
              key: Key('$cle:suite'), libelle: libelleSuite, taille: TailleBouton.lg, icone: LucideIcons.arrowRight, onPressed: confirmation ? surSuite : null),
        ]),
      );
}

/// « J'ai perdu mon mot de passe administrateur » : identifiant, code de secours, nouveau mot de passe.
class EcranRecuperationAdmin extends StatefulWidget with EcranAutonome {
  const EcranRecuperationAdmin({super.key});
  @override
  State<EcranRecuperationAdmin> createState() => _EtatRecuperation();
}

class _EtatRecuperation extends State<EcranRecuperationAdmin> {
  final _id = TextEditingController();
  final _code = TextEditingController();
  final _mdp = TextEditingController();
  final _conf = TextEditingController();
  String? _erreur;
  bool _occupe = false;
  String? _nouveauCode;
  bool _range = false;

  @override
  void initState() {
    super.initState();
    _mdp.addListener(() {
      if (mounted && _nouveauCode == null) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final c in [_id, _code, _mdp, _conf]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _recuperer() async {
    if (_occupe) return;
    final x = ContexteAutonome.of(context);
    setState(() {
      _occupe = true;
      _erreur = null;
    });
    final r = await ServiceIdentifiants.de(x.magasin)
        .recuperer(identifiant: _id.text, code: _code.text, nouveau: _mdp.text, confirmation: _conf.text, maintenant: x.maintenant);
    if (!mounted) return;
    setState(() {
      _occupe = false;
      if (r.ok) {
        _nouveauCode = r.nouveauCode;
        _mdp.clear();
        _conf.clear();
        _code.clear();
      } else {
        _erreur = r.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_nouveauCode != null) {
      return SceneCodeSecours(
          cle: 'sec',
          titre: 'Mot de passe remplacé',
          sousTitre: 'Votre ancien code est consommé. Voici le nouveau, à ranger au coffre.',
          code: _nouveauCode!,
          auteur: _id.text.trim(),
          confirmation: _range,
          surConfirmation: (v) => setState(() => _range = v),
          libelleSuite: 'Retour à la connexion',
          surSuite: () => ContexteAutonome.of(context).aller('index'));
    }
    return SceneAcces(
      icone: LucideIcons.keyRound,
      titre: 'Mot de passe administrateur perdu',
      sousTitre: 'Saisissez votre identifiant, le code de secours de 25 caractères et un nouveau mot de passe.',
      corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ChampAcces(cle: const Key('sec:identifiant'), libelle: 'Identifiant', controleur: _id, indicatif: 'prenom.nom', autofocus: true),
        const SizedBox(height: 16),
        ChampAcces(cle: const Key('sec:code'), libelle: 'Code de secours', controleur: _code, indicatif: 'XXXXX-XXXXX-XXXXX-XXXXX-XXXXX'),
        const SizedBox(height: 16),
        ChampAcces(cle: const Key('sec:motdepasse'), libelle: 'Nouveau mot de passe', controleur: _mdp, indicatif: '••••••••••••', masque: true),
        const SizedBox(height: 16),
        ChampAcces(
            cle: const Key('sec:confirmation'),
            libelle: 'Confirmer le mot de passe',
            controleur: _conf,
            indicatif: '••••••••••••',
            masque: true,
            surValidation: _recuperer),
        const SizedBox(height: 16),
        reglesPolitiqueAcces(_mdp.text, _id.text.trim()),
        if (_erreur != null) Padding(padding: const EdgeInsets.only(top: 16), child: MessageErreurAcces(_erreur!)),
        const SizedBox(height: 16),
        BoutonSigh(key: const Key('sec:valider'), libelle: 'Remplacer le mot de passe', taille: TailleBouton.lg, icone: LucideIcons.keyRound, onPressed: _recuperer),
      ]),
      pied: LienAcces('← Retour à la connexion', onTap: () => ContexteAutonome.of(context).aller('index')),
    );
  }
}

/// REJOINDRE UNE CLINIQUE : l'adresse de la mère et un code d'appairage (8 caractères, 15 minutes, usage unique). Aucune configuration à refaire : la mère
/// diffuse les siennes, ce poste les reprend. L'écran attend les comptes et dit où il en est.
class EcranRejoindre extends StatefulWidget with EcranAutonome {
  const EcranRejoindre({super.key});
  @override
  State<EcranRejoindre> createState() => _EtatRejoindre();
}

class _EtatRejoindre extends State<EcranRejoindre> {
  final _adresse = TextEditingController(text: 'http://');
  final _code = TextEditingController();
  String? _erreur;
  bool _occupe = false;
  bool _rattache = false;
  int _attente = 0;
  Timer? _sonde;

  @override
  void dispose() {
    _sonde?.cancel();
    _adresse.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _rejoindre() async {
    if (_occupe) return;
    final x = ContexteAutonome.of(context);
    setState(() {
      _occupe = true;
      _erreur = null;
    });
    final refus = await ServiceInstallation.de(x.magasin).rejoindre(adresse: _adresse.text, code: _code.text, maintenant: x.maintenant);
    if (!mounted) return;
    setState(() {
      _occupe = false;
      _erreur = refus;
      _rattache = refus == null;
    });
    if (refus == null) {
      _sonde = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!mounted) return;
        setState(() => _attente++);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final x = ContexteAutonome.of(context);
    if (_rattache) {
      final service = ServiceInstallation.de(x.magasin);
      final recus = service.comptesConnectables();
      final pret = recus > 0;
      return SceneAcces(
        icone: pret ? LucideIcons.circleCheck : LucideIcons.refreshCw,
        titre: pret ? 'Poste rattaché' : 'Réception de la configuration',
        sousTitre: pret
            ? 'La configuration et les comptes de la clinique ont été repris de la mère. Vous pouvez vous connecter.'
            : 'Le poste est appairé. La mère diffuse sa configuration : cela prend quelques secondes.',
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!pret && _attente > 20)
            const NoteSigh(
                'La mère n’a encore rien diffusé. Vérifiez qu’elle est démarrée et que sa configuration est faite (étape « Configurer la clinique »). Vous pouvez attendre ici : la reprise est automatique.',
                icone: LucideIcons.triangleAlert),
          const SizedBox(height: 12),
          BoutonSigh(
              key: const Key('ins:vers-connexion'),
              libelle: 'Aller à la connexion',
              taille: TailleBouton.lg,
              icone: LucideIcons.logIn,
              onPressed: pret ? () => x.aller('index') : null),
        ]),
      );
    }
    return SceneAcces(
      icone: LucideIcons.link,
      titre: 'Rejoindre une clinique',
      sousTitre: 'Saisissez l’adresse du poste principal et le code d’appairage affiché sur sa console.',
      corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ChampAcces(cle: const Key('rej:adresse'), libelle: 'Adresse de la mère', controleur: _adresse, indicatif: 'http://192.168.1.10:9000', autofocus: true),
        const SizedBox(height: 16),
        ChampAcces(cle: const Key('rej:code'), libelle: 'Code d’appairage', controleur: _code, indicatif: 'XXXXXXXX', surValidation: _rejoindre),
        if (_erreur != null) Padding(padding: const EdgeInsets.only(top: 16), child: MessageErreurAcces(_erreur!)),
        const SizedBox(height: 16),
        BoutonSigh(key: const Key('rej:valider'), libelle: 'Rejoindre', taille: TailleBouton.lg, icone: LucideIcons.link, onPressed: _rejoindre),
        const SizedBox(height: 16),
        const NoteSigh(
            'Le code vaut 15 minutes et ne sert qu’une fois. Il s’émet sur la mère, à « Appareils et appairage ». Aucune configuration n’est à refaire sur ce poste.',
            icone: LucideIcons.shieldCheck),
      ]),
      pied: LienAcces('← Retour', onTap: () => ContexteAutonome.of(context).aller('index')),
    );
  }
}
