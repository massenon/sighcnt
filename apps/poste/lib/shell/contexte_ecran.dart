import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

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
    required super.child,
  });

  final String ecranId;
  final String role;
  final Droit droit;
  final Magasin magasin;

  /// `app.go(id)` : ouvre un autre écran (refusé par la coque s'il est fermé au rôle).
  final void Function(String id) aller;

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
      o.magasin != magasin;
}

/// Un écran qui déclare lui-même son en-tête de page (`SIGH.screen({title, description, regle, actions})`).
mixin EcranMaquette on Widget {
  String? get description => null;

  /// Texte brut (les balises de mise en forme de la maquette sont retirées).
  String? get regle => null;
  List<Widget> actionsEntete(BuildContext context) => const [];
}

/// `<strong>…</strong>` et consorts de la maquette → texte brut.
String sansBalises(String s) =>
    s.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&amp;', '&');
