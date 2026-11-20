import 'package:sigh_domaine/sigh_domaine.dart';

/// Les écrans qui se règlent sur la MÈRE mais où un fileul rattaché DÉPOSE au lieu de lire seulement (lot TFIN-2, décision T11 : la Direction est fileul ; PRD-TARIFS 6.2, tableau des droits).
/// « Tarifs et prix » : la proposition et la décision d'un prix partent en DEMANDE (famille B) que la mère applique après avoir refait les contrôles ; le fileul n'écrit jamais une version (famille R).
const Set<String> ecransQuiDeposentSurFileul = {'cfg-tarifs'};

/// Le droit EFFECTIF d'un écran sur un poste fileul RATTACHÉ à une mère. [reglageDeLaMere] : l'écran se règle sur la mère (module CFG, droits, comptes, fiscalité). Hors de ce cas, le droit est celui de la
/// matrice. Un écran réglé sur la mère est en LECTURE SEULE, SAUF un écran qui dépose ([ecransQuiDeposentSurFileul]) pour un rôle de la liste de la famille (admin, da, direction, `tarPeutDecider`) : les
/// autres rôles restent en lecture. Le moteur refuse aussi : un geste masqué ne protège rien (le fileul refuse d'écrire une version, la mère refait chaque contrôle sous le rôle de l'auteur).
Droit droitSurFileulRattache({required String ecran, required String role, required Droit droit, required bool reglageDeLaMere}) {
  if (!reglageDeLaMere) return droit;
  if (ecransQuiDeposentSurFileul.contains(ecran) && tarPeutDecider(role)) return Droit(voir: droit.voir, editer: droit.editer, annuler: false);
  return Droit(voir: droit.voir, editer: false, annuler: false);
}

/// La règle d'un écran réglé sur la mère, telle que le fileul la lit en tête de l'écran : celle des écrans qui déposent dit ce qui arrive à leurs gestes.
String phraseReglageDeLaMere(String ecran, String role) => ecransQuiDeposentSurFileul.contains(ecran) && tarPeutDecider(role)
    ? 'Poste rattaché : vos propositions et vos décisions de prix sont déposées à la mère, qui les applique après avoir refait les contrôles ; le verdict revient ici. Rien n’est écrit sur ce poste avant.'
    : 'Réglé sur la mère : cette configuration se modifie sur le poste principal, puis elle est reprise ici. Cet écran est en lecture seule sur ce poste.';
