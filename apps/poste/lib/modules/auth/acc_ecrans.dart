import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_autonome.dart';
import 'acc_gabarit.dart';
import 'acc_session.dart';

/// Les écrans d'accès SANS COQUE (`auth.js`) : connexion, mot de passe oublié, réinitialisation, double facteur, écran verrouillé, pages d'erreur.
/// Règles dans `packages/domaine/lib/src/acces/` ; vecteurs : `prototype_html/build/vecteurs-acces.js`.
///
/// LE POSTE N'A PAS D'AUTHENTIFICATION RÉELLE (document des limites, A5 — hachage Argon2id, sel par compte, hors périmètre ici). Chaque écran qui en
/// simule un morceau LE DIT, comme la maquette dit ce qu'elle fait : la connexion reconnaît un compte du jeu sans vérifier le mot de passe ; le mot de
/// passe oublié inscrit une demande au journal ; la réinitialisation ne conserve rien ; le double facteur ne vérifie aucun code.
const String noteConnexion =
    'Ce poste ne vérifie pas encore le mot de passe : l’authentification par compte haché n’est pas livrée (limite A5). La connexion reconnaît un compte du jeu — elle ne protège rien. Toute connexion est journalisée.';

String _horodatage(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Les initiales de `C.initials` : deux premiers mots, première lettre de chacun, majuscules.
String initialesAcces(String nom) =>
    nom.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0]).join().toUpperCase();

Widget _lienRetour(BuildContext c, String texte, String cible) => LienAcces(texte, onTap: () => ContexteAutonome.of(c).aller(cible));

// ------------------------------------------------------------------------------------------------------------------------------------------------
// index — connexion
// ------------------------------------------------------------------------------------------------------------------------------------------------

class EcranConnexion extends StatefulWidget with EcranAutonome {
  const EcranConnexion({super.key});
  @override
  State<EcranConnexion> createState() => _EtatConnexion();
}

class _EtatConnexion extends State<EcranConnexion> {
  final _id = TextEditingController();
  final _mdp = TextEditingController();
  bool _visible = false;
  bool _souvenir = false;
  int _tentatives = 0;
  String? _erreur;

  @override
  void dispose() {
    _id.dispose();
    _mdp.dispose();
    super.dispose();
  }

  void _soumettre() {
    final x = ContexteAutonome.of(context);
    if (_id.text.trim().isEmpty || _mdp.text.isEmpty) {
      setState(() => _erreur = accMessageSaisieVide(++_tentatives));
      return;
    }
    final m = x.magasin;
    final decision = accEvaluer(
      identifiant: _id.text,
      utilisateurs: m.collection('utilisateurs').toutes,
      rolesArchives: {
        for (final r in m.collection('rbac').toutes)
          if ('${r['statut']}' == 'archive') '${r['role']}'
      },
      libelleRole: (r) => x.donnees?.matrice.libelle(r) ?? r,
    );
    if (!decision.accepte) {
      _tentatives++;
      // RG-12 : la tentative est écrite, quel que soit le refus (le serveur de la maquette le fait aussi).
      m.utilisateur = _id.text.trim();
      m.collection('tentativesConnexion').inserer(accTentative(identifiant: _id.text, decision: decision, maintenant: x.maintenant), prefixe: 'TNT');
      if (decision.issue == AccIssue.roleArchive) {
        m.journaliser('Connexion refusée', 'M14', 'Session', decision.compte!.identifiant, null, {'role': decision.compte!.role, 'motif': 'rôle archivé'});
      }
      setState(() => _erreur = decision.message);
      if (decision.issue == AccIssue.roleArchive) _modaleRefus(decision, x);
      return;
    }
    final c = decision.compte!;
    m.utilisateur = c.nom;
    // Honnêteté du journal : la connexion ne dit pas « mot de passe vérifié », parce qu'il ne l'a pas été.
    m.journaliser('Connexion', 'M14', 'Session', c.identifiant, null, {'role': c.role, 'motDePasseVerifie': decision.motDePasseVerifie});
    setState(() => _erreur = null);
    final s = x.session;
    if (s != null) {
      s.connecter(c);
    } else {
      x.aller(x.donnees?.matrice.accueil(c.role) ?? 'plan-du-site');
    }
  }

  void _modaleRefus(AccDecision d, ContexteAutonome x) {
    afficherModale<void>(context,
        titre: 'Connexion refusée',
        corps: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: JetonsShell.danger50, border: Border.all(color: JetonsShell.danger200), borderRadius: BorderRadius.circular(8)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(LucideIcons.shieldX, size: 20, color: JetonsShell.danger600),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Ce compte ne peut plus ouvrir de session.',
                      style: TextStyle(color: JetonsShell.danger900, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                      'Le profil « ${d.libelleRole} » a été archivé par l’administrateur système. Les habilitations rattachées à ce rôle sont suspendues.',
                      style: const TextStyle(color: JetonsShell.danger800, fontSize: 12, height: 16 / 12)),
                ])),
              ])),
          const SizedBox(height: 12),
          for (final l in accLignesRefus(d, _horodatage(x.maintenant)))
            Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 130, child: Text(l.$1, style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12))),
                  Expanded(child: Text(l.$2, style: const TextStyle(color: JetonsShell.slate900, fontSize: 14, height: 20 / 14))),
                ])),
          const SizedBox(height: 6),
          const Text(
              'Pour retrouver l’accès, l’administrateur doit restaurer le rôle depuis « Rôles & permissions », ou rattacher le compte à un autre profil.',
              style: TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
        ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Contacter l’assistance',
                  variante: VarianteBouton.secondaire,
                  icone: LucideIcons.lifeBuoy,
                  // La page « Contactez l'éditeur » est un écran de la coque, qui exige une session : avant la connexion, la modale donne les coordonnées.
                  onPressed: () => ToastsSigh.afficher(context, 'Écrire à l’éditeur : ${(accEditeur['emails'] as List).join(' · ')}',
                      detail: '${accEditeur['telephone']} — ${accEditeur['horaires']}')),
              BoutonSigh(libelle: 'Fermer', onPressed: fermer),
            ]);
  }

  @override
  Widget build(BuildContext context) {
    return SceneAcces(
      titre: 'Connexion',
      sousTitre: 'Authentification individuelle obligatoire — aucun compte partagé (CDCT §12.2).',
      corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ChampAcces(
            cle: const Key('acces:identifiant'),
            libelle: 'Identifiant',
            controleur: _id,
            indicatif: 'prenom.nom',
            surValidation: _soumettre),
        const SizedBox(height: 16),
        ChampAcces(
            cle: const Key('acces:motdepasse'),
            libelle: 'Mot de passe',
            controleur: _mdp,
            indicatif: '••••••••',
            masque: !_visible,
            surValidation: _soumettre,
            entete: LienAcces('Mot de passe oublié ?', petit: true, onTap: () => ContexteAutonome.of(context).aller('auth-forgot')),
            suffixe: IconButton(
                key: const Key('acces:oeil'),
                tooltip: 'Afficher le mot de passe',
                visualDensity: VisualDensity.compact,
                icon: Icon(_visible ? LucideIcons.eyeOff : LucideIcons.eye, size: 16, color: JetonsShell.slate400),
                onPressed: () => setState(() => _visible = !_visible))),
        const SizedBox(height: 16),
        InkWell(
            onTap: () => setState(() => _souvenir = !_souvenir),
            child: Row(children: [
              SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                      value: _souvenir,
                      visualDensity: VisualDensity.compact,
                      onChanged: (v) => setState(() => _souvenir = v ?? false))),
              const SizedBox(width: 8),
              const Text('Se souvenir de ce poste', style: TextStyle(color: JetonsShell.slate600, fontSize: 14, height: 20 / 14)),
            ])),
        if (_erreur != null) Padding(padding: const EdgeInsets.only(top: 16), child: MessageErreurAcces(_erreur!)),
        const SizedBox(height: 16),
        BoutonSigh(libelle: 'Se connecter', taille: TailleBouton.lg, icone: LucideIcons.logIn, onPressed: _soumettre),
        const SizedBox(height: 16),
        const NoteSimulation(noteConnexion),
      ]),
    );
  }
}

// ------------------------------------------------------------------------------------------------------------------------------------------------
// auth-forgot — mot de passe oublié
// ------------------------------------------------------------------------------------------------------------------------------------------------

class EcranMotDePasseOublie extends StatefulWidget with EcranAutonome {
  const EcranMotDePasseOublie({super.key});
  @override
  State<EcranMotDePasseOublie> createState() => _EtatOubli();
}

class _EtatOubli extends State<EcranMotDePasseOublie> {
  final _id = TextEditingController();
  String? _erreur;
  Timer? _suite;

  @override
  void dispose() {
    _suite?.cancel();
    _id.dispose();
    super.dispose();
  }

  void _envoyer() {
    final x = ContexteAutonome.of(context);
    if (_id.text.trim().isEmpty) {
      setState(() => _erreur = 'Renseigner l’identifiant ou l’adresse électronique.');
      return;
    }
    setState(() => _erreur = null);
    // Ce que le poste FAIT vraiment : la demande est inscrite au journal (RG-12), que l'administrateur lit à « Journal d'audit ». Rien n'est envoyé.
    x.magasin.utilisateur = _id.text.trim();
    x.magasin.journaliser('Demande de réinitialisation du mot de passe', 'M14', 'Session', _id.text.trim(), null, null);
    ToastsSigh.afficher(context, 'Demande transmise à l’administrateur système.',
        type: TypeToast.succes, detail: 'La réinitialisation est effectuée par l’Administrateur (CDCT §12.2).');
    _suite = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) x.aller('auth-reset');
    });
  }

  @override
  Widget build(BuildContext context) => SceneAcces(
        icone: LucideIcons.keyRound,
        titre: 'Mot de passe oublié',
        sousTitre: 'La réinitialisation est prise en charge par l’Administrateur système et journalisée.',
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ChampAcces(
              cle: const Key('acces:identifiant'),
              libelle: 'Identifiant ou adresse électronique',
              controleur: _id,
              indicatif: 'prenom.nom',
              surValidation: _envoyer),
          if (_erreur != null) Padding(padding: const EdgeInsets.only(top: 16), child: MessageErreurAcces(_erreur!)),
          const SizedBox(height: 16),
          BoutonSigh(libelle: 'Envoyer les instructions', taille: TailleBouton.lg, onPressed: _envoyer),
          const SizedBox(height: 16),
          const NoteSimulation(
              'Aucun message n’est envoyé : la demande est inscrite au journal d’audit de ce poste, que l’administrateur consulte (M14). L’envoi d’instructions suppose un service de messagerie que le poste n’a pas.'),
        ]),
        pied: _lienRetour(context, '← Retour à la connexion', 'index'),
      );
}

// ------------------------------------------------------------------------------------------------------------------------------------------------
// auth-reset — réinitialisation
// ------------------------------------------------------------------------------------------------------------------------------------------------

class EcranReinitialisation extends StatefulWidget with EcranAutonome {
  const EcranReinitialisation({super.key});
  @override
  State<EcranReinitialisation> createState() => _EtatReinit();
}

class _EtatReinit extends State<EcranReinitialisation> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  Timer? _suite;

  @override
  void dispose() {
    _suite?.cancel();
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _definir() {
    final x = ContexteAutonome.of(context);
    final refus = accControlerReinitialisation(_a.text, _b.text);
    if (refus != null) {
      ToastsSigh.afficher(context, refus, type: TypeToast.erreur);
      return;
    }
    // Le secret n'est ni gardé ni journalisé : seul le geste l'est. Le poste ne stocke aucun mot de passe (A5).
    x.magasin.journaliser('Réinitialisation du mot de passe (saisie contrôlée, non conservée)', 'M14', 'Session', x.session?.compte?.identifiant ?? '—', null, null);
    ToastsSigh.afficher(context, 'Saisie contrôlée — aucun mot de passe n’est conservé sur ce poste.',
        type: TypeToast.info, detail: 'La maquette écrit « Mot de passe mis à jour. » : le poste ne stocke pas de secret (limite A5).');
    _suite = Timer(const Duration(milliseconds: 1000), () {
      if (mounted) x.aller('index');
    });
  }

  @override
  Widget build(BuildContext context) => SceneAcces(
        icone: LucideIcons.lockKeyhole,
        titre: 'Réinitialiser le mot de passe',
        sousTitre: 'Politique de mot de passe de la clinique (CDCT §12.2).',
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ChampAcces(cle: const Key('acces:nouveau'), libelle: 'Nouveau mot de passe', controleur: _a, indicatif: '••••••••', masque: true),
          const SizedBox(height: 16),
          ChampAcces(
              cle: const Key('acces:confirmation'),
              libelle: 'Confirmer le mot de passe',
              controleur: _b,
              indicatif: '••••••••',
              masque: true,
              surValidation: _definir),
          const SizedBox(height: 16),
          Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: JetonsShell.slate50, borderRadius: BorderRadius.circular(8)),
              child: Column(children: [
                for (final r in accRegleMotDePasse)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        const Icon(LucideIcons.check, size: 14, color: JetonsShell.success600),
                        const SizedBox(width: 8),
                        Expanded(child: Text(r, style: const TextStyle(color: JetonsShell.slate600, fontSize: 12, height: 16 / 12))),
                      ])),
              ])),
          const SizedBox(height: 16),
          BoutonSigh(libelle: 'Définir le mot de passe', taille: TailleBouton.lg, onPressed: _definir),
          const SizedBox(height: 16),
          const NoteSimulation(
              'Seule la concordance des deux saisies est contrôlée (comme la maquette : la politique est affichée, non appliquée). Le poste ne conserve aucun mot de passe.'),
        ]),
        pied: _lienRetour(context, '← Retour à la connexion', 'index'),
      );
}

// ------------------------------------------------------------------------------------------------------------------------------------------------
// auth-2fa — double facteur
// ------------------------------------------------------------------------------------------------------------------------------------------------

class EcranDoubleFacteur extends StatefulWidget with EcranAutonome {
  const EcranDoubleFacteur({super.key});
  @override
  State<EcranDoubleFacteur> createState() => _EtatDoubleFacteur();
}

class _EtatDoubleFacteur extends State<EcranDoubleFacteur> {
  final _ctl = List.generate(6, (_) => TextEditingController());
  final _foc = List.generate(6, (_) => FocusNode());
  Timer? _suite;

  @override
  void dispose() {
    _suite?.cancel();
    for (final c in _ctl) {
      c.dispose();
    }
    for (final f in _foc) {
      f.dispose();
    }
    super.dispose();
  }

  void _verifier() {
    final x = ContexteAutonome.of(context);
    // La maquette accepte n'importe quelle saisie, même vide. Le poste n'a aucun secret partagé à comparer : il ne VÉRIFIE rien, et le dit.
    x.magasin.journaliser('Double facteur : code reçu, non vérifié', 'M14', 'Session', x.session?.compte?.identifiant ?? '—', null, null);
    ToastsSigh.afficher(context, 'Code reçu — non vérifié sur ce poste.',
        type: TypeToast.info, detail: 'La maquette écrit « Vérification réussie. » : le poste n’a aucun secret partagé à comparer (limite A5).');
    _suite = Timer(const Duration(milliseconds: 900), () {
      if (mounted) x.aller(x.accueil());
    });
  }

  @override
  Widget build(BuildContext context) => SceneAcces(
        icone: LucideIcons.smartphone,
        titre: 'Vérification en 2 étapes',
        sousTitre: 'Exigée pour les profils à privilèges élevés : Administrateur et Direction (CDCT §12.2).',
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            for (var i = 0; i < 6; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                  child: Semantics(
                      textField: true,
                      label: 'Chiffre ${i + 1}',
                      child: KeyboardListener(
                          focusNode: FocusNode(skipTraversal: true, canRequestFocus: false),
                          onKeyEvent: (e) {
                            if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.backspace && _ctl[i].text.isEmpty && i > 0) _foc[i - 1].requestFocus();
                          },
                          child: TextField(
                              key: Key('acces:chiffre$i'),
                              controller: _ctl[i],
                              focusNode: _foc[i],
                              maxLength: 1,
                              textAlign: TextAlign.center,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: JetonsShell.slate900, fontSize: 20, height: 28 / 20, fontWeight: FontWeight.w600),
                              decoration: decorationChamp().copyWith(counterText: '', contentPadding: const EdgeInsets.symmetric(vertical: 14)),
                              onChanged: (v) {
                                if (v.isNotEmpty && i < 5) _foc[i + 1].requestFocus();
                              })))),
            ],
          ]),
          const SizedBox(height: 16),
          BoutonSigh(libelle: 'Vérifier', taille: TailleBouton.lg, onPressed: _verifier),
          const SizedBox(height: 16),
          const Text('Code non reçu ? Un nouvel envoi est possible dans 30 secondes.',
              textAlign: TextAlign.center, style: TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
          const SizedBox(height: 16),
          const NoteSimulation('Aucun code n’est envoyé ni comparé : le poste n’a pas de second facteur (limite A5). L’écran existe pour que le parcours se voie.'),
        ]),
        pied: _lienRetour(context, '← Utiliser un autre compte', 'index'),
      );
}

// ------------------------------------------------------------------------------------------------------------------------------------------------
// auth-lock — écran verrouillé
// ------------------------------------------------------------------------------------------------------------------------------------------------

class EcranVerrou extends StatefulWidget with EcranAutonome {
  const EcranVerrou({super.key});
  @override
  State<EcranVerrou> createState() => _EtatVerrou();
}

class _EtatVerrou extends State<EcranVerrou> {
  final _mdp = TextEditingController();
  String? _erreur;

  @override
  void dispose() {
    _mdp.dispose();
    super.dispose();
  }

  AccCompte _compte(ContexteAutonome x) =>
      x.session?.compte ?? AccCompte(identifiant: x.config.role, nom: x.libelleRole ?? x.config.role, role: x.config.role);

  void _deverrouiller() {
    final x = ContexteAutonome.of(context);
    if (_mdp.text.isEmpty) {
      setState(() => _erreur = 'Saisir le mot de passe.');
      return;
    }
    final s = x.session;
    final c = _compte(x);
    final surCouche = s?.etat == EtatSession.verrouillee;
    final retour = s?.retour;
    x.magasin.utilisateur = c.nom;
    x.magasin.journaliser('Déverrouillage de session', 'M14', 'Session', c.identifiant, null, {'retour': retour?.adresse()});
    // L'adresse de retour est à USAGE UNIQUE : le déverrouillage la consomme. Verrouillée en surcouche, le travail en cours est resté monté sous cet écran :
    // le retirer suffit pour retrouver l'écran, à l'onglet près. Sans verrou posé (adresse directe), retour à l'accueil du profil.
    s?.deverrouiller();
    if (!surCouche) x.aller(x.accueil());
  }

  void _autreCompte() {
    final x = ContexteAutonome.of(context);
    x.session?.abandonner();
    x.aller('index');
  }

  @override
  Widget build(BuildContext context) {
    final x = ContexteAutonome.of(context);
    final c = _compte(x);
    final retour = x.session?.retour;
    final cible = retour == null ? null : x.donnees?.manifeste.ecran(retour.ecran);
    final message = accMessageRetour(cible?.label);
    return SceneAcces(
      icone: LucideIcons.lock,
      titre: 'Session verrouillée',
      sousTitre: accSousTitreVerrou(x.session?.verrou.delai ?? accDelaiVerrou),
      corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: JetonsShell.slate50, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: JetonsShell.navy900, shape: BoxShape.circle),
                  child: Text(initialesAcces(c.nom),
                      style: const TextStyle(color: Colors.white, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600))),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.nom, style: const TextStyle(color: JetonsShell.slate900, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
                Text(x.libelleRole ?? '', style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
              ])),
            ])),
        // Ce que l'agent va retrouver : le dire lève l'inquiétude de perdre la saisie en cours.
        if (message != null)
          Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Container(
                  key: const Key('acces:retour'),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: JetonsShell.info50, border: Border.all(color: JetonsShell.info200), borderRadius: BorderRadius.circular(8)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(LucideIcons.history, size: 16, color: JetonsShell.info600),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text(accTitreRetour,
                          style: TextStyle(color: JetonsShell.info900, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600)),
                      Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(message, style: const TextStyle(color: JetonsShell.info800, fontSize: 12, height: 16 / 12))),
                    ])),
                  ]))),
        const SizedBox(height: 16),
        ChampAcces(
            cle: const Key('acces:motdepasse'),
            libelle: 'Mot de passe',
            controleur: _mdp,
            indicatif: '••••••••',
            masque: true,
            autofocus: true,
            surValidation: _deverrouiller),
        if (_erreur != null) Padding(padding: const EdgeInsets.only(top: 16), child: MessageErreurAcces(_erreur!)),
        const SizedBox(height: 16),
        BoutonSigh(libelle: 'Déverrouiller', taille: TailleBouton.lg, icone: LucideIcons.lockOpen, onPressed: _deverrouiller),
        const SizedBox(height: 16),
        const NoteSimulation('Le mot de passe n’est pas vérifié : le poste n’a pas d’authentification réelle (limite A5). Le déverrouillage est journalisé.'),
      ]),
      pied: LienAcces('Se connecter avec un autre compte', onTap: _autreCompte),
    );
  }
}

// ------------------------------------------------------------------------------------------------------------------------------------------------
// error-404 / error-403 — pages d'erreur
// ------------------------------------------------------------------------------------------------------------------------------------------------

class PageErreur extends StatelessWidget with EcranAutonome {
  const PageErreur({super.key, required this.code, required this.titre, required this.message, required this.icone});
  final String code;
  final String titre;
  final String message;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    final x = ContexteAutonome.of(context);
    return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(color: JetonsShell.navy50, borderRadius: BorderRadius.circular(16)),
                      child: Icon(icone, size: 32, color: JetonsShell.navy800)),
                  const SizedBox(height: 24),
                  Text(code,
                      style: const TextStyle(color: JetonsShell.navy950, fontSize: 48, height: 1, fontWeight: FontWeight.w700, letterSpacing: -1.2)),
                  const SizedBox(height: 8),
                  Semantics(
                      header: true,
                      child: Text(titre,
                          style: const TextStyle(color: JetonsShell.slate900, fontSize: 20, height: 28 / 20, fontWeight: FontWeight.w600))),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 448),
                      child: Text(message,
                          textAlign: TextAlign.center, style: const TextStyle(color: JetonsShell.slate500, fontSize: 14, height: 20 / 14))),
                  const SizedBox(height: 24),
                  Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                    BoutonSigh(libelle: 'Retour à l’accueil', icone: LucideIcons.house, onPressed: () => x.aller(x.accueil())),
                    BoutonSigh(
                        libelle: 'Plan du site',
                        variante: VarianteBouton.secondaire,
                        icone: LucideIcons.map,
                        onPressed: () => x.aller('plan-du-site')),
                  ]),
                  const SizedBox(height: 40),
                  const Text('${IdentiteClinique.nom} — SIGH-CNT', style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
                ]))));
  }
}

const PageErreur page404 = PageErreur(
    code: '404',
    titre: 'Page introuvable',
    message: 'L’écran demandé n’existe pas ou a été déplacé. Utiliser le plan du site pour retrouver le module recherché.',
    icone: LucideIcons.fileQuestionMark);
const PageErreur page403 = PageErreur(
    code: '403',
    titre: 'Accès refusé',
    message:
        'Votre profil ne dispose pas des habilitations requises pour cet écran. L’accès est régi par la matrice RBAC (CDCT §12.1) et toute tentative est journalisée.',
    icone: LucideIcons.shieldX);
