import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/donnees_navigation.dart';
import '../donnees/magasin.dart';

/// Ce qu'un écran porté reçoit de la coque : son identifiant, le rôle de l'agent, ses droits SUR CET ÉCRAN (jamais ceux d'un autre module),
/// le magasin de données et la navigation. Équivalent de `K.droits()` et de `app.go()` de la maquette.
class ContexteEcran extends InheritedWidget {
  const ContexteEcran({
    super.key,
    required this.ecranId,
    required this.role,
    required this.droit,
    required this.magasin,
    required this.aller,
    this.utilisateur = '',
    this.horloge,
    this.ouvre,
    this.donnees,
    required super.child,
  });

  final String ecranId;
  final String role;
  final Droit droit;
  final Magasin magasin;

  /// `app.go(id)` : ouvre un autre écran (refusé par la coque s'il est fermé au rôle).
  final void Function(String id) aller;

  /// `ecranOuvert(id)` : l'écran est-il ouvert au profil de l'agent ? (parcours des tableaux de bord : une étape fermée reste visible mais non cliquable). `null` = non branché : tout est réputé ouvert.
  final bool Function(String id)? ouvre;

  /// Manifeste, droits et parité (écrans qui décrivent le logiciel lui-même : aide, plan du site). `null` = non branché.
  final DonneesNavigation? donnees;

  /// Nom affiché de l'agent connecté (RG-12 : aucune action anonyme).
  final String utilisateur;

  /// Horloge du poste, fixable par un test ; `null` = l'horloge réelle (`C.aujourdhui()`).
  final DateTime Function()? horloge;
  DateTime get aujourdhui => (horloge ?? DateTime.now)();

  static ContexteEcran of(BuildContext context) {
    final c = context.dependOnInheritedWidgetOfExactType<ContexteEcran>();
    assert(c != null,
        'ContexteEcran absent : l’écran doit être monté par la coque.');
    return c!;
  }

  static ContexteEcran? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContexteEcran>();

  @override
  bool updateShouldNotify(ContexteEcran o) =>
      o.ecranId != ecranId ||
      o.role != role ||
      o.droit != droit ||
      o.magasin != magasin ||
      o.ouvre != ouvre;
}

/// Un écran qui déclare lui-même son en-tête de page (`SIGH.screen({title, description, regle, actions})`).
mixin EcranMaquette on Widget {
  /// Titre de la page quand il diffère de l'intitulé du ruban (`SIGH.screen({title})`).
  String? get titre => null;

  String? get description => null;

  /// Texte brut (les balises de mise en forme de la maquette sont retirées).
  String? get regle => null;
  List<Widget> actionsEntete(BuildContext context) => const [];
}

/// `<strong>…</strong>` et consorts de la maquette → texte brut.
String sansBalises(String s) =>
    s.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&amp;', '&');
