import 'package:sigh_domaine/sigh_domaine.dart' show Agent;

import '../shell/contexte_autonome.dart';
import '../shell/contexte_ecran.dart';

/// `acteur(contexte)` : UNE fabrique, pour tout geste qui s'attribue (validateur, demandeur, préleveur, encaisseur, auteur d'une pièce, pied d'état).
///
/// A1 du document des limites : l'acteur n'est plus le libellé du rôle mais l'AGENT de la session (identifiant du compte, matricule, nom, fonction,
/// secteur). Sans session nominative, c'est l'agent de démonstration du rôle (déterministe, nom = libellé du rôle) : les écrans n'ont pas à distinguer
/// les deux cas. Écrire `acteur(c).nom` pour un nom, `acteur(c).utilisateurId` pour une comparaison de personnes : ne JAMAIS comparer des libellés.
Agent acteur(ContexteEcran c) => c.agent;

/// Le même acteur pour un écran sans coque (connexion, verrou). `null` tant que personne n'est connecté.
Agent? acteurAutonome(ContexteAutonome c) => c.agent;

/// Le nom à écrire sur une pièce : celui de l'acteur, ou « Utilisateur » si le nom est vide (RG-12 : jamais de ligne anonyme).
String acteurNom(ContexteEcran c) {
  final n = c.agent.nom;
  return n.isEmpty ? 'Utilisateur' : n;
}
