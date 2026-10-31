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
import 'contexte_ecran.dart';
import 'contexte_autonome.dart';
import '../modules/auth/acc_session.dart';
import 'acces_rapides.dart';
import '../donnees/magasin.dart';
import 'ruban.dart';

/// Coque UNIQUE du poste (fileul et mère) : barre supérieure → ruban à méga-menus → page. Elle reproduit la structure de
/// la maquette (`#app-menubar`) ; tout ce qu'elle affiche est DÉRIVÉ du manifeste et de la matrice des droits.
class CoquePoste extends StatefulWidget {
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

  /// Les paramètres de l'adresse d'un écran autonome (`jeton` de la page publique d'enquête).
  final Map<String, String> parametres;

  @override
  State<CoquePoste> createState() => _CoquePosteState();
}

class _CoquePosteState extends State<CoquePoste> {
  String? _ecran;
  String? _domaine;
  bool _panneauOuvert = true;

  /// L'écran AUTONOME affiché (plein écran, sans chrome), s'il y en a un. Il prend le pas sur l'écran de la coque sans le détruire.
  String? _autonome;
  Timer? _minuteur;
  String _courantAffiche = '';

  SessionPoste? get _session => widget.session;
  String get _role => _session?.role ?? widget.config.role;

  /// Un écran de la liste des écrans servis sans coque ET porté : sans les deux, la coque l'enveloppe comme avant.
  bool _estAutonome(String id) => accEcransPleinEcran.contains(id) && widget.ecrans.containsKey(id);

  @override
  void initState() {
    super.initState();
    final demande = widget.ecranInitial;
    if (demande != null && _estAutonome(demande)) _autonome = demande;
    final s = _session;
    _compteVu = s?.compte;
    if (s != null) {
      s.addListener(_surSession);
      HardwareKeyboard.instance.addHandler(_surClavier);
      // Le délai est mesuré sur l'horloge INJECTÉE de la session ; le minuteur ne fait que la consulter.
      _minuteur = Timer.periodic(const Duration(seconds: 2), (_) => _verifierVerrou());
    }
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    _session?.removeListener(_surSession);
    if (_session != null) HardwareKeyboard.instance.removeHandler(_surClavier);
    super.dispose();
  }

  bool _surClavier(KeyEvent e) {
    _session?.activite();
    return false;
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
  void _surSession() {
    final s = _session!;
    setState(() {
      // Un NOUVEAU compte (connexion, autre compte) repart de l'accueil de son profil ; le déverrouillage, lui, rend le même compte à son travail.
      if (s.etat == EtatSession.connectee && !identical(_compteVu, s.compte)) {
        _ecran = null;
        _domaine = null;
        _autonome = null;
      }
      if (s.etat == EtatSession.deconnectee) _autonome = null;
      _compteVu = s.compte;
    });
  }

  List<DomaineRuban> get _ruban =>
      widget.donnees.manifeste.ruban(widget.donnees.matrice, _role,
          estMere: widget.config.estMere);

  /// Page d'accueil du rôle (`home` de la maquette) si le rôle la voit, sinon le premier écran de son ruban.
  String? _accueil(List<DomaineRuban> ruban) {
    final home = widget.donnees.matrice.accueil(_role);
    if (home != null && widget.donnees.matrice.peutVoir(_role, home)) return home;
    return ruban.isEmpty ? null : ruban.first.rangees.first.ecrans.first.id;
  }

  void _ouvrir(String id) {
    if (_estAutonome(id)) {
      setState(() => _autonome = id);
      return;
    }
    final e = widget.donnees.manifeste.ecran(id);
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
    final connu = widget.donnees.manifeste.ecran(id) != null || id.startsWith('hub-');
    if (!connu) {
      if (_estAutonome('error-404')) _ouvrir('error-404');
      return;
    }
    if (!id.startsWith('hub-') && !widget.donnees.matrice.peutVoir(_role, id)) {
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
    widget.magasin?.utilisateur = _session?.compte?.nom ?? widget.donnees.matrice.libelle(_role) ?? _role;
    if (widget.horloge != null) widget.magasin?.horloge = widget.horloge!;
    return KeyedSubtree(
        key: ValueKey('autonome|$id'),
        child: Builder(
            builder: (_) => ContexteAutonome(
                ecranId: id,
                config: widget.config,
                magasin: widget.magasin ?? _magasinVide,
                donnees: publique ? null : widget.donnees,
                session: publique ? null : _session,
                horloge: widget.horloge ?? _session?.horloge,
                publique: publique,
                parametres: publique ? widget.parametres : const {},
                aller: publique ? (_) {} : _allerDepuisAutonome,
                accueil: () => (_session?.exigeConnexion ?? false) && _session!.etat == EtatSession.deconnectee ? 'index' : _accueilDuRole(),
                child: Builder(builder: (c) => porte(c, widget.config)))));
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    // Sans session : comportement historique (un écran autonome demandé prend simplement la place de la coque).
    if (s == null) return _autonome != null ? _pleinEcran(_autonome!) : _coquePrincipale(context);
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
        child: corps);
  }

  Widget _coquePrincipale(BuildContext context) {
    final ruban = _ruban;
    final libelleMode = widget.config.estMere ? 'poste mère' : 'poste fileul';
    final nomRole = widget.donnees.matrice.libelle(_role) ??
        _role;
    if (ruban.isEmpty) {
      return Scaffold(
          body: Column(children: [
        BarreSuperieure(
            config: widget.config, etatSync: widget.etatSync, nomRole: nomRole),
        const Expanded(
            child: Center(
                child: Text('Aucun module n’est ouvert à votre profil.')))
      ]));
    }
    final demande = widget.ecranInitial;
    final visible = demande != null &&
        widget.donnees.manifeste.ecran(demande) != null &&
        (widget.donnees.matrice.peutVoir(_role, demande) ||
            demande.startsWith('hub-'));
    final courant = _ecran ?? (visible ? demande : _accueil(ruban)!);
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
        BarreSuperieure(
            config: widget.config,
            etatSync: widget.etatSync,
            nomRole: nomRole,
            surAccueil: () => _ouvrir(_accueil(ruban)!)),
        Ruban(
          domaines: ruban,
          raccourcis: widget.donnees.manifeste.raccourcis(ruban),
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
                key: ValueKey('$courant|${widget.config.mode.name}'),
                child: _page(courant, ruban, libelleMode))),
      ]),
    );
  }

  Widget _page(String id, List<DomaineRuban> ruban, String libelleMode) {
    final e = widget.donnees.manifeste.ecran(id);
    final rangee = ruban
        .expand((d) => d.rangees.map((r) => (d, r)))
        .where((x) => x.$2.hub == id || x.$2.ecrans.any((s) => s.id == id))
        .firstOrNull;
    final fil = [
      'Accueil',
      if (rangee != null) rangee.$1.nom,
      if (rangee != null) rangee.$2.label,
      e?.label ?? id
    ];
    if (e == null) return const Center(child: Text('Écran inconnu.'));
    final porte = widget.ecrans[id];
    if (porte == null) {
      return EcranAPorter(ecran: e, donnees: widget.donnees, fil: fil);
    }
    widget.magasin?.utilisateur =
        widget.donnees.matrice.libelle(_role) ??
            _role;
    if (widget.horloge != null) widget.magasin?.horloge = widget.horloge!;
    return Builder(builder: (context) {
      // Les droits sont ceux de l'ÉCRAN (une surcharge d'écran l'emporte sur son module) ; un servant hérite du registre qu'il alimente.
      final droit = widget.donnees.matrice.droit(_role, id);
      return ContexteEcran(
        ecranId: id,
        role: _role,
        droit: droit,
        magasin: widget.magasin ?? _magasinVide,
        utilisateur: widget.donnees.matrice.libelle(_role) ??
            _role,
        horloge: widget.horloge,
        ouvre: (cible) => widget.donnees.matrice.peutVoir(_role, cible),
        donnees: widget.donnees,
        aller: (cible) {
          if (widget.donnees.matrice.peutVoir(_role, cible))
            _ouvrir(cible);
        },
        child: Builder(builder: (context) {
          final w = porte(context, widget.config);
          return PageStandard(
              titre: (w is EcranMaquette ? w.titre : null) ?? e.label,
              fil: fil,
              module: e.module,
              defilable: w is EcranMaquette ? true : false,
              description: w is EcranMaquette ? w.description : null,
              regle: w is EcranMaquette ? w.regle : null,
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
