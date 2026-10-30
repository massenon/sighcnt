import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/config_poste.dart';
import '../core/donnees_navigation.dart';
import '../modules/registre.dart';
import '../sync/etat_sync.dart';
import 'barre_superieure.dart';
import 'ecran_a_porter.dart';
import 'page_standard.dart';
import 'contexte_ecran.dart';
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
      this.ecranInitial});
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

  @override
  State<CoquePoste> createState() => _CoquePosteState();
}

class _CoquePosteState extends State<CoquePoste> {
  String? _ecran;
  String? _domaine;
  bool _panneauOuvert = true;

  List<DomaineRuban> get _ruban =>
      widget.donnees.manifeste.ruban(widget.donnees.matrice, widget.config.role,
          estMere: widget.config.estMere);

  /// Page d'accueil du rôle (`home` de la maquette) si le rôle la voit, sinon le premier écran de son ruban.
  String? _accueil(List<DomaineRuban> ruban) {
    final home = widget.donnees.matrice.accueil(widget.config.role);
    if (home != null &&
        widget.donnees.matrice.peutVoir(widget.config.role, home)) return home;
    return ruban.isEmpty ? null : ruban.first.rangees.first.ecrans.first.id;
  }

  void _ouvrir(String id) {
    final e = widget.donnees.manifeste.ecran(id);
    setState(() {
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

  @override
  Widget build(BuildContext context) {
    final ruban = _ruban;
    final libelleMode = widget.config.estMere ? 'poste mère' : 'poste fileul';
    final nomRole = widget.donnees.matrice.libelle(widget.config.role) ??
        widget.config.role;
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
        (widget.donnees.matrice.peutVoir(widget.config.role, demande) ||
            demande.startsWith('hub-'));
    final courant = _ecran ?? (visible ? demande : _accueil(ruban)!);
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
    return Builder(builder: (context) {
      // Les droits sont ceux de l'ÉCRAN (une surcharge d'écran l'emporte sur son module) ; un servant hérite du registre qu'il alimente.
      final droit = widget.donnees.matrice.droit(widget.config.role, id);
      return ContexteEcran(
        ecranId: id,
        role: widget.config.role,
        droit: droit,
        magasin: widget.magasin ?? _magasinVide,
        utilisateur: widget.donnees.matrice.libelle(widget.config.role) ??
            widget.config.role,
        horloge: widget.horloge,
        aller: (cible) {
          if (widget.donnees.matrice.peutVoir(widget.config.role, cible))
            _ouvrir(cible);
        },
        child: Builder(builder: (context) {
          final w = porte(context, widget.config);
          return PageStandard(
              titre: e.label,
              fil: fil,
              module: e.module,
              defilable: w is EcranMaquette ? true : false,
              description: w is EcranMaquette ? w.description : null,
              regle: w is EcranMaquette ? w.regle : null,
              actions: w is EcranMaquette ? w.actionsEntete(context) : const [],
              child: w);
        }),
      );
    });
  }

  static final Magasin _magasinVide = Magasin();
}
