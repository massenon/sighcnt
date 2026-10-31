import 'package:flutter/material.dart';

import '../core/config_poste.dart';
import '../core/donnees_navigation.dart';
import '../donnees/magasin.dart';
import '../modules/auth/acc_session.dart';

/// Un écran servi SANS COQUE : plein écran, ni barre supérieure, ni ruban, ni page standard (`standalone: true` du manifeste — connexion, mot de
/// passe oublié, réinitialisation, double facteur, écran verrouillé, pages d'erreur, plan du site, page publique d'enquête). Marqueur du pendant de
/// [EcranMaquette] : la coque reconnaît l'écran qui se suffit et ne l'enveloppe de rien.
mixin EcranAutonome on Widget {}

/// Ce qu'un écran autonome reçoit de la coque (la coque ne sait pas servir un écran sans chrome → ce contexte remplace [ContexteEcran], qui exige un
/// rôle, des droits d'écran et une page standard).
///
///  * une page PUBLIQUE ([publique]) ne reçoit NI session, NI manifeste, NI navigation : seulement le magasin local et l'horloge. Une page d'enquête qui
///    offrirait un chemin vers le logiciel serait une porte — on la tend à des inconnus ;
///  * un écran d'accès reçoit la session du poste (connexion, verrou) et la navigation de la coque.
class ContexteAutonome extends InheritedWidget {
  const ContexteAutonome({
    super.key,
    required this.ecranId,
    required this.config,
    required this.magasin,
    required this.aller,
    required this.accueil,
    this.donnees,
    this.session,
    this.horloge,
    this.publique = false,
    this.parametres = const {},
    required super.child,
  });

  final String ecranId;
  final ConfigPoste config;
  final Magasin magasin;

  /// `app.go(id)` : ouvre un autre écran (écran autonome ou écran de la coque). Sans effet pour une page publique.
  final void Function(String id) aller;

  /// L'écran d'accueil du profil courant (`N.ROLES[role].home`), ou `index` quand personne n'est connecté.
  final String Function() accueil;

  /// Manifeste, droits et parité : `null` pour une page publique.
  final DonneesNavigation? donnees;

  /// La session du poste : `null` pour une page publique, ou quand le poste n'exige pas de connexion.
  final SessionPoste? session;
  final DateTime Function()? horloge;
  final bool publique;

  /// Les paramètres de l'adresse (`?jeton=…` de la page publique d'enquête).
  final Map<String, String> parametres;

  DateTime get maintenant => (horloge ?? DateTime.now)();

  /// Le rôle de l'agent connecté, `null` si personne.
  String? get role => publique ? null : (session?.role ?? config.role);

  /// Le libellé du rôle (« Réception / Accueil »).
  String? get libelleRole => role == null ? null : (donnees?.matrice.libelle(role!) ?? role);

  static ContexteAutonome of(BuildContext context) {
    final c = context.dependOnInheritedWidgetOfExactType<ContexteAutonome>();
    assert(c != null, 'ContexteAutonome absent : l’écran autonome doit être monté par la coque.');
    return c!;
  }

  static ContexteAutonome? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ContexteAutonome>();

  @override
  bool updateShouldNotify(ContexteAutonome o) =>
      o.ecranId != ecranId || o.session != session || o.magasin != magasin || o.parametres != parametres;
}
