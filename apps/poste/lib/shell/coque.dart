import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/config_poste.dart';
import '../core/donnees_navigation.dart';
import '../modules/registre.dart';
import '../sync/etat_sync.dart';
import 'barre_superieure.dart';
import 'ecran_a_porter.dart';
import 'page_standard.dart';
import 'pied_legal.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../core/jetons_shell.dart';
import 'contexte_ecran.dart';
import 'contexte_autonome.dart';
import '../modules/auth/acc_session.dart';
import 'acces_rapides.dart';
import 'activite_fermee.dart';
import '../donnees/magasin.dart';
import '../kit/toast.dart';
import '../modules/cfg/cfb_notifications.dart' show CfbAudio;
import 'centre_notifications.dart';
import 'choix_exercice.dart';
import 'fenetre_poste.dart';
import 'menus_barre.dart';
import 'modal_notifications.dart';
import 'son_alertes.dart';
import '../core/service_installation.dart';
import '../modules/auth/ins_modale.dart';
import 'recherche_globale.dart';
import 'ruban.dart';

/// Coque UNIQUE du poste (fileul et mère) : barre supérieure → ruban à méga-menus → page. Elle reproduit la structure de
/// la maquette (`#app-menubar`) ; tout ce qu'elle affiche est DÉRIVÉ du manifeste et de la matrice des droits.
class CoquePoste extends StatefulWidget {
  /// Le panneau du méga-menu est-il ouvert à l'ouverture du poste et à la connexion ? NON (Direction, 03/11/2026). Les bancs de test qui ont été écrits sur
  /// la mise en page panneau ouvert le posent à `true` (`test/flutter_test_config.dart`) ; `coque_test.dart` mesure, lui, le défaut livré.
  static bool panneauOuvertAuDemarrage = false;

  const CoquePoste(
      {super.key,
      required this.config,
      required this.donnees,
      required this.ecrans,
      required this.etatSync,
      this.magasin,
      this.horloge,
      this.ecranInitial,
      this.session,
      this.fenetre,
      this.ouvrirTrancher,
      this.parametres = const {}});
  final ConfigPoste config;
  final DonneesNavigation donnees;
  final Map<String, ConstruireEcran> ecrans;
  final SourceEtatSync etatSync;

  /// Données des écrans portés (vide si absent).
  final Magasin? magasin;

  /// Horloge du poste (tests) ; absente = l'horloge réelle.
  final DateTime Function()? horloge;

  /// Ouvre directement cet écran (lien profond, mesure de parité). Sans droit sur lui, la page d'accueil du rôle s'ouvre.
  final String? ecranInitial;

  /// La session du poste (connexion, verrou d'inactivité). Absente = comportement historique : l'agent est réputé connecté sous `config.role` et rien ne
  /// verrouille. Présente : la coque sert l'écran de connexion tant que personne n'est connecté (si `exigeConnexion`), arme le verrou de quinze minutes
  /// et pose l'écran verrouillé PAR-DESSUS le travail en cours (monté, intact, caché : l'agent retrouve son écran à l'onglet près).
  final SessionPoste? session;

  /// La modale « Conflits à trancher » du mode pair (ADR-0006) ; absente hors mode pair.
  final Future<void> Function(BuildContext)? ouvrirTrancher;

  /// Les paramètres de l'adresse d'un écran autonome (`jeton` de la page publique d'enquête).
  final Map<String, String> parametres;

  /// La fenêtre du poste (plein écran). Absente : la fenêtre réelle (`window_manager`), créée au premier usage.
  final FenetrePoste? fenetre;

  @override
  State<CoquePoste> createState() => _CoquePosteState();
}

class _CoquePosteState extends State<CoquePoste> {
  String? _ecran;
  String? _domaine;
  /// À l'ouverture du poste, et à chaque connexion, le panneau du méga-menu est REPLIÉ (Direction, 03/11/2026) : l'agent arrive sur son tableau de bord, le
  /// panneau s'ouvre quand il clique sur un domaine.
  bool _panneauOuvert = CoquePoste.panneauOuvertAuDemarrage;

  /// L'écran AUTONOME affiché (plein écran, sans chrome), s'il y en a un. Il prend le pas sur l'écran de la coque sans le détruire.
  String? _autonome;
  Timer? _minuteur;
  String _courantAffiche = '';

  /// Les données de navigation EN FORCE : la matrice engendrée (`rbac.json`) superposée, À CHAUD, aux collections `rbac` (surcharges de m14-roles) et
  /// `modulesActifs` (activités fermées de cfg-modules), comme `N.can()` de la maquette. Recalculées à chaque écriture de l'une ou l'autre.
  late DonneesNavigation _nav;
  Listenable? _ecouteDroits;

  /// Le moteur de notifications du poste : la cloche en compte les alertes non acquittées, routées pour le rôle connecté.
  CentreNotifications? _centreNotif;
  Magasin? _centreSur;
  FenetrePoste? _fenetreSysteme;
  FenetrePoste get _fenetre => widget.fenetre ?? (_fenetreSysteme ??= FenetreSysteme());
  bool _rechercheOuverte = false;

  DateTime _maintenant() => (widget.horloge ?? _session?.horloge ?? DateTime.now)();

  CentreNotifications get _centre {
    final m = widget.magasin ?? _magasinVide;
    if (_centreNotif == null || !identical(_centreSur, m)) {
      _son?.arreter();
      _centreNotif?.dispose();
      _centreSur = m;
      _centreNotif = CentreNotifications(
          magasin: m, donnees: () => _nav, role: () => _role, horloge: _maintenant, audioDisponible: () => CfbAudio.disponible());
      // La sonorisation : le son est un canal, il écoute le centre et sonne pour toute alerte nouvelle non acquittée.
      _son = SonAlertes(_centreNotif!, horloge: _maintenant)..demarrer();
    }
    return _centreNotif!;
  }

  DonneesNavigation _calculerNav() {
    final m = widget.magasin;
    return m == null ? widget.donnees : widget.donnees.aChaud(m);
  }

  void _brancherDroits() {
    _ecouteDroits?.removeListener(_surDroits);
    _ecouteDroits = null;
    _nav = _calculerNav();
    final m = widget.magasin;
    if (m != null) {
      _ecouteDroits = Listenable.merge([m.collection('rbac'), m.collection('modulesActifs')])..addListener(_surDroits);
    }
  }

  void _surDroits() {
    if (!mounted) return;
    setState(() => _nav = _calculerNav());
  }

  SessionPoste? get _session => widget.session;
  String get _role => _session?.role ?? widget.config.role;

  /// L'agent qui agit (A1) : celui de la session si le compte porte son identité nominative, sinon l'agent de démonstration du rôle. Le nom d'un agent de
  /// démonstration est le libellé du rôle (ou, pour un écran autonome, le nom du compte reconnu), comme avant la session nominative.
  Agent _agent({bool autonome = false}) {
    final c = _session?.compte;
    if (c?.agent != null) return c!.agent!;
    final libelle = _nav.matrice.libelle(_role) ?? _role;
    return agentDemonstration(_role, nom: autonome ? (c?.nom ?? libelle) : libelle);
  }

  /// Un écran de la liste des écrans servis sans coque ET porté : sans les deux, la coque l'enveloppe comme avant.
  bool _estAutonome(String id) => accEcransPleinEcran.contains(id) && widget.ecrans.containsKey(id);

  @override
  void initState() {
    super.initState();
    ChoixExercice.reinitialiser();
    ChoixExercice.valeur.addListener(_surChoixExercice);
    _brancherDroits();
    _suivreInstallation();
    final demande = widget.ecranInitial;
    if (demande != null && _estAutonome(demande)) _autonome = demande;
    final s = _session;
    _compteVu = s?.compte;
    HardwareKeyboard.instance.addHandler(_surClavier);
    // Le repli du plein écran du démarrage est DIT, jamais muet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final refus = widget.fenetre?.refusDemarrage ?? _fenetreSysteme?.refusDemarrage;
      if (mounted && refus != null) ToastsSigh.afficher(context, refus, type: TypeToast.attention);
    });
    if (s != null) {
      s.addListener(_surSession);
      // Le délai est mesuré sur l'horloge INJECTÉE de la session ; le minuteur ne fait que la consulter.
      _minuteur = Timer.periodic(const Duration(seconds: 2), (_) => _verifierVerrou());
    }
  }

  @override
  void didUpdateWidget(CoquePoste ancien) {
    super.didUpdateWidget(ancien);
    if (!identical(ancien.magasin, widget.magasin) || !identical(ancien.donnees, widget.donnees)) _brancherDroits();
  }

  @override
  void dispose() {
    ChoixExercice.valeur.removeListener(_surChoixExercice);
    _ecouteDroits?.removeListener(_surDroits);
    _minuteur?.cancel();
    _session?.removeListener(_surSession);
    HardwareKeyboard.instance.removeHandler(_surClavier);
    _service?.removeListener(_majInstallation);
    _installationEnCours.dispose();
    _son?.arreter();
    _centreNotif?.dispose();
    super.dispose();
  }

  /// Le choix d'exercice a changé : l'écran à année se repeint (sa clé en porte la valeur).
  void _surChoixExercice() {
    if (mounted) setState(() {});
  }

  bool _aExercice(String id) {
    final e = _nav.manifeste.ecran(id);
    return e != null && cpcAExercice(id, e.module);
  }

  bool _surClavier(KeyEvent e) {
    _session?.activite();
    if (e is! KeyDownEvent || !_barreActive) return false;
    final k = HardwareKeyboard.instance;
    // Ctrl K (Cmd K sur Mac) : la recherche globale, de partout, comme la maquette. F11 : le plein écran.
    if ((k.isControlPressed || k.isMetaPressed) && e.logicalKey == LogicalKeyboardKey.keyK) {
      _ouvrirRecherche();
      return true;
    }
    if (e.logicalKey == LogicalKeyboardKey.f11) {
      _basculerPleinEcran();
      return true;
    }
    if (e.logicalKey == LogicalKeyboardKey.f5) {
      _actualiser();
      return true;
    }
    return false;
  }

  /// La barre est-elle sous les yeux de l'agent ? Ni sur un écran autonome, ni derrière la connexion, ni sous le verrou.
  bool get _barreActive {
    final s = _session;
    if (!mounted || _autonome != null) return false;
    if (s != null && (s.etat != EtatSession.connectee)) return false;
    return true;
  }

  // ------------------------------------------------------------------------------------------------------------------------------------------
  // LES BOUTONS DE LA BARRE SUPÉRIEURE : chacun agit.
  // ------------------------------------------------------------------------------------------------------------------------------------------

  /// Une destination atteinte depuis la barre (résultat de recherche, action rapide, alerte, lien du profil) : l'écran s'ouvre si le profil le voit (RG-13),
  /// sinon rien ne s'ouvre en silence : la tentative est dite.
  void _allerDepuisBarre(String id, {String? onglet}) {
    if (id == 'pair-trancher') {
      widget.ouvrirTrancher?.call(context);
      return;
    }
    if (_estAutonome(id)) {
      _ouvrir(id);
      return;
    }
    if (ecranOuvertAuRole(_nav, _role, id) || (_nav.manifeste.ecran(id)?.standalone ?? false)) {
      _ouvrir(id);
      return;
    }
    ToastsSigh.afficher(context, 'Cet écran n’est pas ouvert à votre profil.', type: TypeToast.attention);
  }

  Future<void> _ouvrirRecherche() async {
    if (_rechercheOuverte) return;
    _rechercheOuverte = true;
    try {
      await ouvrirRechercheGlobale(context,
          nav: () => _nav, role: () => _role, magasin: widget.magasin ?? _magasinVide, aller: (e, {onglet}) => _allerDepuisBarre(e, onglet: onglet));
    } finally {
      _rechercheOuverte = false;
    }
  }

  Future<void> _ouvrirActions() =>
      ouvrirActionsRapides(context, nav: _nav, role: _role, aller: (e) => _allerDepuisBarre(e));

  Future<void> _basculerPleinEcran() async {
    try {
      await _fenetre.basculerPleinEcran();
    } catch (_) {
      if (mounted) ToastsSigh.afficher(context, 'Plein écran indisponible sur ce poste.', type: TypeToast.erreur);
    }
  }

  /// Les écrans qui se règlent sur la MÈRE : sur un poste fileul rattaché à une clinique ils sont en LECTURE SEULE (le moteur refuse aussi l'écriture, voir
  /// `ApplicateurConfiguration`). Les écrans de configuration (module CFG), les droits, les comptes et la configuration fiscale.
  static const Set<String> _reglesSurLaMere = {'m14-roles', 'm14-utilisateurs', 'mecef-config'};

  /// Sur un fileul rattaché, un écran réglé sur la mère le DIT en tête de sa règle (et pas seulement par le refus d'écriture).
  String? _regleAvecMere(String id, String? regle) {
    if (!_surLaMere(id)) return regle;
    const phrase = 'Réglé sur la mère : cette configuration se modifie sur le poste principal, puis elle est reprise ici. Cet écran est en lecture seule sur ce poste.';
    return regle == null || regle.isEmpty ? phrase : '$phrase $regle';
  }

  bool _surLaMere(String id) {
    if (!(_service?.rattache ?? false)) return false;
    return _nav.manifeste.ecran(id)?.module == 'CFG' || _reglesSurLaMere.contains(id);
  }

  Droit _droitDe(String id) {
    final d = _nav.matrice.droit(_role, id);
    if (!(_service?.rattache ?? false)) return d;
    return _surLaMere(id) ? Droit(voir: d.voir, editer: false, annuler: false) : d;
  }

  // --- L'assistant de première installation : la pastille de la barre, et la modale qui s'ouvre seule sur le tableau de bord de l'administrateur. ---
  SonAlertes? _son;
  late final ValueNotifier<bool> _installationEnCours = ValueNotifier<bool>(false);

  ServiceInstallation? get _service => widget.magasin == null ? null : ServiceInstallation.de(widget.magasin!);

  /// L'assistant est-il à proposer à cet agent ? En cours sur ce poste, et l'agent est administrateur.
  bool get _installationVisible => (_service?.enCours ?? false) && _role == 'admin';

  void _suivreInstallation() {
    final s = _service;
    if (s == null) return;
    s.removeListener(_majInstallation);
    s.addListener(_majInstallation);
    _majInstallation();
  }

  void _majInstallation() {
    if (mounted) _installationEnCours.value = _installationVisible;
  }

  Future<void> _ouvrirInstallation() {
    final m = widget.magasin;
    if (m == null) return Future.value();
    return ouvrirModaleInstallation(context,
        magasin: m,
        aller: (e) => _allerDepuisBarre(e),
        estMere: widget.config.estMere,
        ouvert: (e) => ecranOuvertAuRole(_nav, _role, e));
  }

  Future<void> _ouvrirNotifications({bool ouverture = false}) =>
      ouvrirCentreNotifications(context, centre: _centre, ouverture: ouverture, aller: (e) => _allerDepuisBarre(e));

  Future<void> _ouvrirProfil() => ouvrirMenuProfil(context,
      nav: _nav,
      role: _role,
      nom: _nomAffiche(),
      libelleRole: _nav.matrice.libelle(_role) ?? _role,
      aller: (e) => _allerDepuisBarre(e),
      verrouiller: _session == null ? null : _verrouillerMaintenant,
      deconnecter: _deconnecter);

  /// « Verrouiller l'écran » : la session est SUSPENDUE (jamais fermée), l'écran courant est retenu pour le retour ; le geste est journalisé (RG-12).
  void _verrouillerMaintenant() {
    final s = _session;
    if (s == null) return;
    final id = _courantAffiche;
    if (s.verrouillerMaintenant(id)) {
      widget.magasin?.journaliser('Verrouillage manuel', 'M14', 'Session', s.compte?.identifiant ?? _role, null, {'ecran': id});
    }
  }

  /// « Se déconnecter » : la session se ferme et la connexion s'ouvre. Journalisé (RG-12).
  void _deconnecter() {
    final s = _session;
    widget.magasin?.journaliser('Déconnexion', 'M14', 'Session', s?.compte?.identifiant ?? _role, null, {'role': _role});
    s?.deconnecter();
    if (_estAutonome('index')) {
      setState(() {
        _autonome = 'index';
        _ecran = null;
        _domaine = null;
      });
    }
  }

  void _verifierVerrou() {
    final s = _session;
    // La maquette n'arme pas le verrou sur un écran autonome (`armerVerrou` : `entry.standalone`) : on regarde un plan du site, on ne travaille pas.
    if (s == null || !mounted || _autonome != null) return;
    final avant = s.etat;
    final id = _autonome ?? _courantAffiche;
    if (s.verifier(id) && avant != s.etat) {
      // RG-12 : le verrouillage est journalisé, avec l'écran retenu et le délai.
      widget.magasin?.journaliser('Verrouillage pour inactivité', 'M14', 'Session', s.compte?.identifiant ?? _role, null,
          {'ecran': id, 'delaiMinutes': s.verrou.delai.inMinutes});
    }
  }

  /// La session change (connexion, déverrouillage, changement de compte) : l'écran autonome affiché cède la place, l'écran courant repart de l'accueil.
  AccCompte? _compteVu;
  EtatSession? _etatVu;
  void _surSession() {
    final s = _session!;
    setState(() {
      // Un NOUVEAU compte (connexion, autre compte) repart de l'accueil de son profil ; le déverrouillage, lui, rend le même compte à son travail.
      if (s.etat == EtatSession.connectee && !identical(_compteVu, s.compte)) {
        _ecran = null;
        _domaine = null;
        _autonome = null;
        _panneauOuvert = CoquePoste.panneauOuvertAuDemarrage;
        _notifierALArrivee = s.compte != null;
      }
      // L'écran autonome ne cède la place QU'À L'INSTANT où la session se ferme : toute autre notification de la session (minuteur, horloge) le laissait
      // revenir à la connexion, si bien que « Rejoindre une clinique existante » s'ouvrait puis disparaissait aussitôt.
      if (s.etat == EtatSession.deconnectee && _etatVu != EtatSession.deconnectee) _autonome = null;
      _etatVu = s.etat;
      _compteVu = s.compte;
    });
    _suivreInstallation();
    // À la CONNEXION, le centre de notifications s'ouvre de lui-même sur le tableau de bord du poste : ce qui attend l'agent, routé par son rôle. Tant que
    // l'assistant d'installation est en cours, c'est SA modale qui s'ouvre à la place (les alertes restent à la cloche).
    if (_notifierALArrivee) {
      _notifierALArrivee = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_barreActive) return;
        if (_installationVisible) {
          _ouvrirInstallation();
        } else {
          _ouvrirNotifications(ouverture: true);
        }
      });
    }
  }

  bool _notifierALArrivee = false;

  List<DomaineRuban> get _ruban =>
      _nav.manifeste.ruban(_nav.matrice, _role,
          estMere: widget.config.estMere);

  /// Page d'accueil du rôle (`home` de la maquette) si le rôle la voit, sinon le premier écran de son ruban.
  String? _accueil(List<DomaineRuban> ruban) {
    final home = _nav.matrice.accueil(_role);
    if (home != null && _nav.matrice.peutVoir(_role, home)) return home;
    return ruban.isEmpty ? null : ruban.first.rangees.first.ecrans.first.id;
  }

  void _ouvrir(String id) {
    if (_estAutonome(id)) {
      setState(() => _autonome = id);
      return;
    }
    final e = _nav.manifeste.ecran(id);
    setState(() {
      _autonome = null;
      _ecran = id;
      if (e != null)
        _domaine = _ruban
                .where((d) => d.rangees
                    .any((r) => r.ecrans.any((x) => x.id == id) || r.hub == id))
                .map((d) => d.nom)
                .firstOrNull ??
            _domaine;
      // Un clic sur une pastille referme le panneau : la page appelée s'ouvre menu replié (comme la maquette).
      _panneauOuvert = false;
    });
  }

  /// La fiche de `modulesActifs` qui ferme l'écran (`fermeturePour`), `null` s'il est ouvert. Un rôle archivé n'est pas informé : il n'ouvre plus rien.
  Map<String, Object?>? _fermeturePour(String id) {
    final e = _nav.manifeste.ecran(id);
    if (e == null || _nav.matrice.estArchive(_role)) return null;
    return _nav.matrice.fermetures?.fermeturePour(id, e.module);
  }

  /// L'accueil du profil courant : sa page d'accueil si le rôle la voit, sinon le premier écran de son ruban, sinon le plan du site.
  String _accueilDuRole() {
    final ruban = _ruban;
    return (ruban.isEmpty ? null : _accueil(ruban)) ?? 'plan-du-site';
  }

  /// La navigation d'un écran autonome : personne n'est connecté → la connexion ; écran inconnu → 404 ; écran fermé au profil → 403 (la tentative est
  /// journalisée, RG-12 et RG-13). Les écrans ordinaires ne se vérifient pas ici : c'est la matrice qui décide, et la coque la suit.
  void _allerDepuisAutonome(String id) {
    final s = _session;
    if (_estAutonome(id)) {
      _ouvrir(id);
      return;
    }
    if (s != null && s.exigeConnexion && s.etat == EtatSession.deconnectee) {
      _ouvrir('index');
      return;
    }
    final connu = _nav.manifeste.ecran(id) != null || id.startsWith('hub-');
    if (!connu) {
      if (_estAutonome('error-404')) _ouvrir('error-404');
      return;
    }
    if (!id.startsWith('hub-') && !_nav.matrice.peutVoir(_role, id)) {
      widget.magasin?.journaliser('Accès refusé', 'M14', 'Ecran', id, null, {'role': _role});
      if (_estAutonome('error-403')) _ouvrir('error-403');
      return;
    }
    _ouvrir(id);
  }

  /// Sert un écran AUTONOME en plein écran : aucune barre, aucun ruban, aucune page standard. Une page publique ne reçoit ni session, ni manifeste, ni
  /// navigation.
  Widget _pleinEcran(String id) {
    final porte = widget.ecrans[id];
    if (porte == null) return const Scaffold(body: Center(child: Text('Écran inconnu.')));
    final publique = accEcransPublics.contains(id);
    widget.magasin?.poserActeur(_agent(autonome: true));
    if (widget.horloge != null) widget.magasin?.horloge = widget.horloge!;
    return KeyedSubtree(
        key: ValueKey('autonome|$id'),
        child: Builder(
            builder: (_) => ContexteAutonome(
                ecranId: id,
                config: widget.config,
                magasin: widget.magasin ?? _magasinVide,
                donnees: publique ? null : _nav,
                session: publique ? null : _session,
                horloge: widget.horloge ?? _session?.horloge,
                publique: publique,
                parametres: publique ? widget.parametres : const {},
                aller: publique ? (_) {} : _allerDepuisAutonome,
                accueil: () => (_session?.exigeConnexion ?? false) && _session!.etat == EtatSession.deconnectee ? 'index' : _accueilDuRole(),
                child: Builder(
                    builder: (c) => Column(children: [
                          Expanded(child: porte(c, widget.config)),
                          const PiedLegal(fond: JetonsShell.slate100),
                        ])))));
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    // Sans session : comportement historique (un écran autonome demandé prend simplement la place de la coque).
    if (s == null) return _avecMenuContextuel(_autonome != null ? _pleinEcran(_autonome!) : _coquePrincipale(context));
    final deconnecte = s.exigeConnexion && s.etat == EtatSession.deconnectee;
    final Widget corps;
    if (deconnecte) {
      // Personne n'est connecté : la connexion et ses écrans voisins (mot de passe oublié, réinitialisation, plan du site, page publique), rien d'autre.
      corps = _pleinEcran(_autonome ?? 'index');
    } else {
      // La session est SUSPENDUE par le verrou, jamais fermée : le travail en cours reste monté sous l'écran verrouillé (caché, sans focus, sans
      // animation, intact) — l'agent le retrouve à l'onglet près. La structure est la même verrouillée ou non : rien ne se reconstruit.
      final verrouille = s.etat == EtatSession.verrouillee;
      corps = Stack(fit: StackFit.expand, children: [
        ExcludeFocus(
            excluding: verrouille,
            child: TickerMode(
                enabled: !verrouille,
                child: Offstage(offstage: verrouille, child: _autonome != null ? _pleinEcran(_autonome!) : _coquePrincipale(context)))),
        if (verrouille) _pleinEcran('auth-lock'),
      ]);
    }
    // Un geste de l'agent relance le compte à rebours du verrou (le clavier est écouté par `HardwareKeyboard`).
    return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => s.activite(),
        onPointerMove: (_) => s.activite(),
        onPointerSignal: (_) => s.activite(),
        // La structure reste la MÊME verrouillée ou non (le travail en cours reste monté sous l'écran verrouillé) : seul le geste est coupé.
        child: _avecMenuContextuel(corps, actif: s.etat != EtatSession.verrouillee));
  }

  // --- Actualiser : le clic droit sur un écran offre le menu contextuel « Actualiser », F5 aussi. ---
  int _actualisations = 0;

  /// Enveloppe l'écran : un clic droit (hors champ de saisie, qui garde son propre menu copier/coller) ouvre « Actualiser ». Actualiser reconstruit l'écran
  /// courant : il relit le magasin et repart de son état d'ouverture, comme une page rechargée.
  Widget _avecMenuContextuel(Widget corps, {bool actif = true}) => GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapUp: actif ? (d) => _ouvrirMenuContextuel(d.globalPosition) : null,
      child: KeyedSubtree(key: ValueKey('actualisation-$_actualisations'), child: corps));

  Future<void> _ouvrirMenuContextuel(Offset position) async {
    final choix = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
        items: const [
          PopupMenuItem<String>(
              key: Key('menu-actualiser'),
              value: 'actualiser',
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(LucideIcons.refreshCw, size: 16, color: JetonsShell.slate600),
                SizedBox(width: 8),
                Text('Actualiser', style: TextStyle(fontSize: 14, color: JetonsShell.slate800)),
                SizedBox(width: 16),
                Text('F5', style: TextStyle(fontSize: 12, color: JetonsShell.slate400)),
              ])),
        ]);
    if (choix == 'actualiser') _actualiser();
  }

  /// Reconstruit l'écran courant (relecture du magasin, état d'ouverture) et le dit.
  void _actualiser() {
    if (!mounted) return;
    setState(() => _actualisations++);
    ToastsSigh.afficher(context, 'Écran actualisé.', type: TypeToast.succes);
  }

  Widget _coquePrincipale(BuildContext context) {
    final ruban = _ruban;
    final libelleMode = widget.config.estMere ? 'poste mère' : 'poste fileul';
    final nomRole = _nav.matrice.libelle(_role) ??
        _role;
    if (ruban.isEmpty) {
      return Scaffold(
          body: Column(children: [
        _barre(nomRole, null),
        const Expanded(
            child: Center(
                child: Text('Aucun module n’est ouvert à votre profil.'))),
        const PiedLegal(),
      ]));
    }
    final demande = widget.ecranInitial;
    final visible = demande != null &&
        _nav.manifeste.ecran(demande) != null &&
        (_nav.matrice.peutVoir(_role, demande) ||
            demande.startsWith('hub-'));
    // Une ACTIVITÉ FERMÉE ouverte par son adresse : la coque le dit (motif de la fiche) au lieu de renvoyer à l'accueil muet.
    final fermee = demande != null && !visible && _fermeturePour(demande) != null;
    final courant = _ecran ?? (visible || fermee ? demande : _accueil(ruban)!);
    _courantAffiche = courant;
    final domaine = _domaine ??
        ruban
            .where((d) =>
                d.rangees.any((r) => r.ecrans.any((e) => e.id == courant)))
            .map((d) => d.nom)
            .firstOrNull ??
        ruban.first.nom;
    return Scaffold(
      body: Column(children: [
        _barre(nomRole, () => _ouvrir(_accueil(ruban)!)),
        Ruban(
          domaines: ruban,
          raccourcis: _nav.manifeste.raccourcis(ruban),
          domaineOuvert: domaine,
          ecranCourant: courant,
          panneauOuvert: _panneauOuvert,
          surDomaine: (nom) => setState(() {
            _panneauOuvert = !(_panneauOuvert && domaine == nom);
            _domaine = nom;
          }),
          surEcran: _ouvrir,
          surBascule: () => setState(() => _panneauOuvert = !_panneauOuvert),
        ),
        Expanded(
            child: KeyedSubtree(
                key: ValueKey('$courant|${widget.config.mode.name}${_aExercice(courant) ? '|exo${ChoixExercice.valeur.value}' : ''}'),
                child: _page(courant, ruban, libelleMode))),
        const PiedLegal(),
      ]),
    );
  }

  /// Le nom affiché au profil : celui de l'agent nominatif de la session ; à défaut le nom du compte (sauf s'il n'est que l'identifiant du rôle) ; à défaut
  /// l'agent de démonstration du rôle.
  String _nomAffiche() {
    final c = _session?.compte;
    if (c?.agent != null) return c!.agent!.nom;
    if (c != null && c.nom.trim().isNotEmpty && c.nom != c.identifiant && c.nom != c.role) return c.nom;
    return _agent().nom;
  }

  Widget _barre(String nomRole, VoidCallback? surAccueil) => BarreSuperieure(
      config: widget.config,
      etatSync: widget.etatSync,
      nomRole: nomRole,
      nomAgent: _nomAffiche(),
      surAccueil: surAccueil,
      centre: _centre,
      surRecherche: _ouvrirRecherche,
      surActions: _ouvrirActions,
      surPleinEcran: _basculerPleinEcran,
      pleinEcran: _fenetre.pleinEcran,
      surNotifications: _ouvrirNotifications,
      surProfil: _ouvrirProfil,
      installation: _installationEnCours,
      surInstallation: _ouvrirInstallation,
      selecteurExercice: _aExercice(_courantAffiche)
          ? SelecteurExercice(magasin: widget.magasin ?? _magasinVide, aujourdhui: _maintenant())
          : null);

  /// Les maillons cliquables du fil (comme la maquette) : « Accueil » ramène à la page d'accueil du rôle ; l'intitulé du module ouvre la page d'accueil du module
  /// (sauf sur cette page elle-même), s'il est ouvert au profil.
  Map<int, VoidCallback> _liensDuFil(List<String> fil, EcranNav e, EcranNav? hub) => {
        0: () => _ouvrir(_accueilDuRole()),
        if (!e.hub && hub != null && ecranOuvertAuRole(_nav, _role, hub.id)) fil.indexOf(e.moduleLabel): () => _ouvrir(hub.id),
      };

  Widget _page(String id, List<DomaineRuban> ruban, String libelleMode) {
    final e = _nav.manifeste.ecran(id);
    // Le fil d'Ariane est celui de la maquette : Accueil, le domaine CANONIQUE de l'écran (jamais « Accueil > Accueil » : le premier maillon nomme déjà
    // le domaine Accueil), l'intitulé du module, puis l'écran (absent sur la page d'accueil d'un module, qui est le module).
    final fil = [
      'Accueil',
      if (e != null && e.domaine != 'Accueil') e.domaine,
      if (e != null) e.moduleLabel,
      if (e != null && !e.hub) e.label,
    ];
    if (e == null) return const Center(child: Text('Écran inconnu.'));
    final hubDuModule = _nav.manifeste.ecran('hub-${e.module.toLowerCase()}');
    final fermeture = _fermeturePour(id);
    if (fermeture != null) return PageActiviteFermee(ecran: e, fermeture: fermeture, fil: fil);
    final porte = widget.ecrans[id];
    if (porte == null) {
      return EcranAPorter(ecran: e, donnees: _nav, fil: fil);
    }
    widget.magasin?.poserActeur(_agent());
    if (widget.horloge != null) widget.magasin?.horloge = widget.horloge!;
    return Builder(builder: (context) {
      // Les droits sont ceux de l'ÉCRAN (une surcharge d'écran l'emporte sur son module) ; un servant hérite du registre qu'il alimente.
      final droit = _droitDe(id);
      return ContexteEcran(
        ecranId: id,
        role: _role,
        droit: droit,
        magasin: widget.magasin ?? _magasinVide,
        utilisateur: _agent().nom,
        agentConnecte: _session?.compte?.agent,
        horloge: widget.horloge,
        ouvre: (cible) => _nav.matrice.peutVoir(_role, cible),
        donnees: _nav,
        aller: (cible) {
          if (_nav.matrice.peutVoir(_role, cible))
            _ouvrir(cible);
        },
        child: Builder(builder: (context) {
          final w = porte(context, widget.config);
          return PageStandard(
              titre: (w is EcranMaquette ? w.titre : null) ?? e.label,
              fil: fil,
              surFil: _liensDuFil(fil, e, hubDuModule),
              module: e.module,
              defilable: w is EcranMaquette ? true : false,
              description: w is EcranMaquette ? w.description : null,
              regle: _regleAvecMere(id, w is EcranMaquette ? w.regle : null),
              actions: _actions(context, e, ruban, w),
              child: w);
        }),
      );
    });
  }

  List<Widget> _actions(
      BuildContext context, EcranNav e, List<DomaineRuban> ruban, Widget w) {
    final declarees =
        w is EcranMaquette ? w.actionsEntete(context) : <Widget>[];
    return [
      ...declarees,
      if (w is EcranMaquette)
        ...accesRapides(
            ecran: e, ruban: ruban, declarees: declarees, aller: _ouvrir),
    ];
  }

  static final Magasin _magasinVide = Magasin();
}
