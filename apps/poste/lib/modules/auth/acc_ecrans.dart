import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import 'dart:io' show Platform;

import '../../core/identifiants.dart';
import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_autonome.dart';
import 'acc_gabarit.dart';
import 'acc_registre_sessions.dart';
import 'acc_session.dart';

/// Les écrans d'accès SANS COQUE (`auth.js`) : connexion, mot de passe oublié, réinitialisation, double facteur, écran verrouillé, pages d'erreur.
/// Règles dans `packages/domaine/lib/src/acces/` ; vecteurs : `prototype_html/build/vecteurs-acces.js`.
///
/// A5 : le poste AUTHENTIFIE. Le mot de passe est comparé au haché Argon2id de la collection `identifiants` (`ServiceIdentifiants`), un compte se verrouille
/// après trois échecs, chaque tentative est écrite dans `tentativesConnexion` (RG-12), la politique de mot de passe est appliquée. Ce que le poste ne fait
/// pas encore, et que l'écran du double facteur dit : le second facteur (aucun secret partagé à comparer).
const String noteConnexion =
    'Après $accEchecsAvantVerrou tentatives infructueuses, le compte est verrouillé 15 minutes. Toute tentative, réussie ou refusée, est journalisée (RG-12).';

/// La note de sécurité de la connexion : une information, non un avertissement de simulation.
Widget _noteSecurite(String texte) => KeyedSubtree(key: const Key('acces:securite'), child: NoteSigh(texte, icone: LucideIcons.shieldCheck));

String _horodatage(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Les initiales de `C.initials` : deux premiers mots, première lettre de chacun, majuscules.
String initialesAcces(String nom) =>
    nom.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0]).join().toUpperCase();

/// La liste des règles n'est PLUS affichée sur les écrans de saisie (Direction, 03/11/2026) : la politique reste APPLIQUÉE, et le refus nomme les règles
/// manquantes. Les appelants gardent leur emplacement ; il ne porte plus rien.
Widget _reglesPolitique(String saisie, String? identifiant) => const SizedBox.shrink();

/// Le mot de passe provisoire de l'administrateur initial, affiché UNE fois à la première mise en service : ni dans le dépôt, ni dans un fichier.
Widget _bandeauProvisoire(ProvisoireAdmin p) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Container(
        key: const Key('acces:provisoire'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: JetonsShell.warning50, border: Border.all(color: JetonsShell.warning200), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Première mise en service',
              style: TextStyle(color: JetonsShell.warning900, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text.rich(
              TextSpan(children: [
                TextSpan(text: 'Compte administrateur : ${p.identifiant}. Mot de passe provisoire (affiché une seule fois, à noter maintenant) : '),
                TextSpan(
                    text: p.motDePasse,
                    style: const TextStyle(fontFamily: 'LiberationMono', fontWeight: FontWeight.w700, color: JetonsShell.slate900)),
                const TextSpan(text: '. Il devra être changé à la première connexion.'),
              ]),
              style: const TextStyle(color: JetonsShell.warning800, fontSize: 12, height: 16 / 12)),
        ])));

/// La politique de mot de passe avec ses coches (réutilisée par l'assistant d'installation et la récupération).
Widget reglesPolitiqueAcces(String saisie, String? identifiant) => _reglesPolitique(saisie, identifiant);

Widget _lienRetour(BuildContext c, String texte, String cible) => LienAcces(texte, onTap: () => ContexteAutonome.of(c).aller(cible));

// ------------------------------------------------------------------------------------------------------------------------------------------------
// index — connexion
// ------------------------------------------------------------------------------------------------------------------------------------------------

/// Ouvre la session d'un compte DÉJÀ vérifié (connexion, changement obligatoire, première installation, récupération) : acteur du journal, fiche du registre
/// des sessions, délai de verrou de la politique de sécurité ; sans session de poste, aiguille vers l'accueil du rôle.
void ouvrirSessionAcces(ContexteAutonome x, AccCompte c) {
  final m = x.magasin;
  // L'administrateur a ouvert sa session : le mot de passe provisoire n'est plus affiché (il ne l'était qu'une fois).
  if (ServiceIdentifiants.provisoireAffiche?.identifiant == c.identifiant) ServiceIdentifiants.provisoireAffiche = null;
  m.poserActeur(c.agent ?? agentDemonstration(c.role, nom: c.nom));
  // Le journal dit ce qui s'est passé : le mot de passe a été VÉRIFIÉ contre le haché.
  m.journaliser('Connexion', 'M14', 'Session', c.identifiant, null, {'role': c.role, 'motDePasseVerifie': true});
  final s = x.session;
  if (s != null) {
    s.connecter(c);
    // Le REGISTRE des sessions : une fiche nouvelle à chaque connexion (jamais la réouverture d'une session clôturée), un contrôle de clôture au
    // prochain geste, le verrou qui suspend et reprend la fiche.
    final reg = RegistreSessions.de(m);
    final id = reg.ouvrir(identifiant: c.identifiant, nomComplet: c.nom, role: c.role, poste: Platform.localHostname, maintenant: x.maintenant);
    s.sessionId = id;
    s.estCloturee = reg.estCloturee;
    s.surEtat = (i, e) => reg.changerEtat(i, e, x.maintenant);
    reg.surCloturePropre = s.fermerParCloture;
    reg.appliquerDelaiVerrou = (d) => s.verrou.delai = d;
    // Le délai d'inactivité de la politique de sécurité, quand l'administrateur l'a réglée.
    final pol = m.collection('politiqueSecurite').actives.firstOrNull;
    if (pol != null) s.verrou.delai = Duration(minutes: secPolitique(pol)['inactiviteMin']!);
  } else {
    x.aller(x.donnees?.matrice.accueil(c.role) ?? 'plan-du-site');
  }
}

class EcranConnexion extends StatefulWidget with EcranAutonome {
  const EcranConnexion({super.key});
  @override
  State<EcranConnexion> createState() => _EtatConnexion();
}

class _EtatConnexion extends State<EcranConnexion> {
  final _id = TextEditingController();
  final _mdp = TextEditingController();
  bool _visible = false;
  int _tentatives = 0;
  String? _erreur;
  bool _occupe = false;

  /// Le compte dont le mot de passe est juste mais à CHANGER avant d'ouvrir la session (mot de passe provisoire, première connexion, renouvellement échu).
  AccCompte? _aChanger;
  final _nouveau = TextEditingController();
  final _confirmation = TextEditingController();

  @override
  void dispose() {
    _id.dispose();
    _mdp.dispose();
    _nouveau.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _nouveau.addListener(() {
      if (mounted && _aChanger != null) setState(() {});
    });
  }

  bool _motifLu = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Une session CLOTURÉE par un administrateur renvoie ici, et le DIT (comme la maquette : `?motif=session-cloturee`).
    if (!_motifLu) {
      _motifLu = true;
      if (ContexteAutonome.of(context).session?.motifFermeture == 'cloturee') _erreur = accMessageSessionCloturee;
    }
  }

  Set<String> _rolesArchives(ContexteAutonome x) => {
        for (final r in x.magasin.collection('rbac').toutes)
          if ('${r['statut']}' == 'archive') '${r['role']}'
      };

  Future<void> _soumettre() async {
    if (_occupe) return;
    final x = ContexteAutonome.of(context);
    if (_id.text.trim().isEmpty || _mdp.text.isEmpty) {
      setState(() => _erreur = accMessageSaisieVide(++_tentatives));
      return;
    }
    final m = x.magasin;
    setState(() => _occupe = true);
    // A5 : le mot de passe est VÉRIFIÉ contre le haché Argon2id ; le service écrit lui-même chaque tentative refusée dans `tentativesConnexion` (RG-12).
    final r = await ServiceIdentifiants.de(m).verifier(
        identifiant: _id.text,
        motDePasse: _mdp.text,
        rolesArchives: _rolesArchives(x),
        libelleRole: (ro) => x.donnees?.matrice.libelle(ro) ?? ro,
        maintenant: x.maintenant);
    if (!mounted) return;
    setState(() => _occupe = false);
    final decision = r.decision;
    if (!decision.accepte) {
      _tentatives++;
      if (decision.issue == AccIssue.roleArchive) {
        m.journaliser('Connexion refusée', 'M14', 'Session', decision.compte!.identifiant, null, {'role': decision.compte!.role, 'motif': 'rôle archivé'});
      }
      setState(() => _erreur = decision.message);
      if (decision.issue == AccIssue.roleArchive) _modaleRefus(decision, x);
      return;
    }
    final c = decision.compte!;
    if (r.doitChanger) {
      setState(() {
        _aChanger = c;
        _erreur = null;
      });
      return;
    }
    _ouvrirSession(x, c);
  }

  void _ouvrirSession(ContexteAutonome x, AccCompte c) {
    ouvrirSessionAcces(x, c);
    setState(() => _erreur = null);
  }

  /// Le changement OBLIGATOIRE : le nouveau mot de passe respecte la politique et diffère de l'actuel ; il remplace le provisoire, puis la session s'ouvre.
  Future<void> _changer() async {
    final x = ContexteAutonome.of(context);
    final c = _aChanger!;
    final refus = accControlerNouveauMotDePasse(_nouveau.text, _confirmation.text, identifiant: c.identifiant, ancien: _mdp.text);
    if (refus != null) {
      setState(() => _erreur = refus);
      return;
    }
    if (_occupe) return;
    setState(() => _occupe = true);
    final id = c.agent?.utilisateurId ?? c.identifiant;
    // Après une réinitialisation par un administrateur, le nouveau mot de passe ne peut pas être celui d'AVANT (EF-INST-09).
    if (await ServiceIdentifiants.de(x.magasin).memeQuePrecedent(id, _nouveau.text)) {
      if (!mounted) return;
      setState(() {
        _occupe = false;
        _erreur = 'Le nouveau mot de passe doit être différent de l’ancien.';
      });
      return;
    }
    await ServiceIdentifiants.de(x.magasin).definir(id, _nouveau.text, par: c.nom, doitChanger: false, maintenant: x.maintenant);
    if (!mounted) return;
    setState(() {
      _occupe = false;
      _aChanger = null;
    });
    _ouvrirSession(x, c);
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

  Widget _panneauChangement() => SceneAcces(
        icone: LucideIcons.lockKeyhole,
        titre: 'Choisir un nouveau mot de passe',
        sousTitre: 'Le mot de passe provisoire doit être remplacé avant d’ouvrir la session.',
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ChampAcces(cle: const Key('acces:nouveau'), libelle: 'Nouveau mot de passe', controleur: _nouveau, indicatif: '••••••••', masque: true, autofocus: true),
          const SizedBox(height: 16),
          ChampAcces(
              cle: const Key('acces:confirmation'),
              libelle: 'Confirmer le mot de passe',
              controleur: _confirmation,
              indicatif: '••••••••',
              masque: true,
              surValidation: _changer),
          const SizedBox(height: 16),
          _reglesPolitique(_nouveau.text, _aChanger?.identifiant),
          if (_erreur != null) Padding(padding: const EdgeInsets.only(top: 16), child: MessageErreurAcces(_erreur!)),
          const SizedBox(height: 16),
          BoutonSigh(libelle: 'Définir le mot de passe et se connecter', taille: TailleBouton.lg, onPressed: _changer),
        ]),
        pied: LienAcces('← Utiliser un autre compte', onTap: () => setState(() {
              _aChanger = null;
              _mdp.clear();
              _erreur = null;
            })),
      );

  @override
  Widget build(BuildContext context) {
    if (_aChanger != null) return _panneauChangement();
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
        if (_erreur != null) Padding(padding: const EdgeInsets.only(top: 16), child: MessageErreurAcces(_erreur!)),
        const SizedBox(height: 16),
        BoutonSigh(libelle: 'Se connecter', taille: TailleBouton.lg, icone: LucideIcons.logIn, onPressed: _soumettre),
        const SizedBox(height: 16),
        Center(child: LienAcces('J’ai perdu mon mot de passe administrateur', petit: true, onTap: () => ContexteAutonome.of(context).aller('auth-secours'))),
        const SizedBox(height: 16),
        _noteSecurite(noteConnexion),
        if (ServiceIdentifiants.provisoireAffiche != null) _bandeauProvisoire(ServiceIdentifiants.provisoireAffiche!),
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
    // Ce que le poste FAIT vraiment : la demande est inscrite au journal (RG-12) ET marquée sur le compte (`reinitialisationDemandeeLe`), que
    // l'écran « Utilisateurs » ne relit PAS encore (l'administrateur la trouve au journal d'audit) avant de définir un nouveau mot de passe. Rien n'est envoyé. La réponse est la MÊME que le compte existe ou non :
    // dire lequel serait un annuaire offert à qui essaie.
    final m = x.magasin;
    final id = _id.text.trim();
    m.utilisateur = id;
    final compte = m.collection('utilisateurs').toutes.where((u) => '${u['identifiant']}' == id || '${u['email'] ?? ''}' == id).firstOrNull;
    if (compte != null) {
      m.collection('utilisateurs').mettreAJour(compte['id'], {'reinitialisationDemandeeLe': x.maintenant.toIso8601String()});
    }
    m.journaliser('Demande de réinitialisation du mot de passe', 'M14', 'Session', id, null, null);
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
              'Aucun message n’est envoyé : la demande est inscrite au journal d’audit de ce poste et marquée sur le compte ; l’écran des utilisateurs (M14) ne l’affiche pas encore, l’administrateur la retrouve au journal d’audit avant de définir un nouveau mot de passe. L’envoi d’instructions suppose un service de messagerie que le poste n’a pas.'),
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
  final _identifiant = TextEditingController();
  final _actuel = TextEditingController();
  final _a = TextEditingController();
  final _b = TextEditingController();
  Timer? _suite;
  bool _occupe = false;
  bool _prerempli = false;

  @override
  void dispose() {
    _suite?.cancel();
    _identifiant.dispose();
    _actuel.dispose();
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Les règles de la politique se cochent à la frappe.
    _a.addListener(_rafraichir);
  }

  void _rafraichir() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prerempli) return;
    _prerempli = true;
    _identifiant.text = ContexteAutonome.of(context).session?.compte?.identifiant ?? '';
  }

  /// A5 : la réinitialisation est RÉELLE. Elle prouve d'abord l'identité (identifiant + mot de passe actuel ou provisoire, vérifié contre le haché, avec le
  /// même verrou que la connexion), applique la politique (8 caractères, familles, différent de l'actuel), puis remplace le haché. Le secret n'est ni
  /// gardé ni journalisé : seul le geste l'est.
  Future<void> _definir() async {
    if (_occupe) return;
    final x = ContexteAutonome.of(context);
    final id = _identifiant.text.trim();
    if (id.isEmpty || _actuel.text.isEmpty) {
      ToastsSigh.afficher(context, 'Renseigner l’identifiant et le mot de passe actuel (ou provisoire).', type: TypeToast.erreur);
      return;
    }
    final refus = accControlerNouveauMotDePasse(_a.text, _b.text, identifiant: id, ancien: _actuel.text);
    if (refus != null) {
      ToastsSigh.afficher(context, refus, type: TypeToast.erreur);
      return;
    }
    final m = x.magasin;
    setState(() => _occupe = true);
    final r = await ServiceIdentifiants.de(m).verifier(
        identifiant: id,
        motDePasse: _actuel.text,
        rolesArchives: {
          for (final ro in m.collection('rbac').toutes)
            if ('${ro['statut']}' == 'archive') '${ro['role']}'
        },
        libelleRole: (ro) => x.donnees?.matrice.libelle(ro) ?? ro,
        maintenant: x.maintenant,
        poste: 'Réinitialisation du mot de passe');
    if (!mounted) return;
    if (!r.accepte) {
      setState(() => _occupe = false);
      ToastsSigh.afficher(context, r.decision.message, type: TypeToast.erreur);
      return;
    }
    final c = r.decision.compte!;
    await ServiceIdentifiants.de(m).definir(c.agent?.utilisateurId ?? c.identifiant, _a.text, par: c.nom, doitChanger: false, maintenant: x.maintenant);
    if (!mounted) return;
    setState(() => _occupe = false);
    if (ServiceIdentifiants.provisoireAffiche?.identifiant == c.identifiant) ServiceIdentifiants.provisoireAffiche = null;
    ToastsSigh.afficher(context, 'Mot de passe mis à jour.', type: TypeToast.succes, detail: 'Conservé haché (Argon2id) ; reconnexion avec le nouveau mot de passe.');
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
          ChampAcces(cle: const Key('acces:identifiant'), libelle: 'Identifiant', controleur: _identifiant, indicatif: 'prenom.nom'),
          const SizedBox(height: 16),
          ChampAcces(
              cle: const Key('acces:actuel'), libelle: 'Mot de passe actuel ou provisoire', controleur: _actuel, indicatif: '••••••••', masque: true),
          const SizedBox(height: 16),
          ChampAcces(
              cle: const Key('acces:nouveau'),
              libelle: 'Nouveau mot de passe',
              controleur: _a,
              indicatif: '••••••••',
              masque: true),
          const SizedBox(height: 16),
          ChampAcces(
              cle: const Key('acces:confirmation'),
              libelle: 'Confirmer le mot de passe',
              controleur: _b,
              indicatif: '••••••••',
              masque: true,
              surValidation: _definir),
          const SizedBox(height: 16),
          _reglesPolitique(_a.text, _identifiant.text),
          const SizedBox(height: 16),
          BoutonSigh(libelle: 'Définir le mot de passe', taille: TailleBouton.lg, onPressed: _definir),
          const SizedBox(height: 16),
          _noteSecurite('Le mot de passe actuel est vérifié, la politique est appliquée, le nouveau mot de passe est conservé haché (Argon2id) et jamais en clair.'),
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

  Future<void> _deverrouiller() async {
    final x = ContexteAutonome.of(context);
    if (_mdp.text.isEmpty) {
      setState(() => _erreur = 'Saisir le mot de passe.');
      return;
    }
    final s = x.session;
    final c = _compte(x);
    // A5 : si le compte de la session a un mot de passe, le déverrouillage le VÉRIFIE (même service, même verrou après échecs que la connexion). Un compte
    // sans identifiant (poste de développement `SIGH_ROLE`, agent de démonstration) garde le comportement d'origine.
    final svc = ServiceIdentifiants.de(x.magasin);
    final uid = c.agent?.utilisateurId;
    if (uid != null && !(c.agent?.demonstration ?? true) && svc.possede(uid)) {
      final r = await svc.verifier(
          identifiant: c.identifiant,
          motDePasse: _mdp.text,
          rolesArchives: const {},
          libelleRole: (ro) => ro,
          maintenant: x.maintenant,
          poste: 'Écran verrouillé');
      if (!mounted) return;
      if (!r.accepte) {
        setState(() => _erreur = r.decision.message);
        return;
      }
    }
    final surCouche = s?.etat == EtatSession.verrouillee;
    final retour = s?.retour;
    x.magasin.poserActeur(c.agent ?? agentDemonstration(c.role, nom: c.nom));
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
        _noteSecurite('Le mot de passe est vérifié pour les comptes qui en ont un. Le déverrouillage est journalisé.'),
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
