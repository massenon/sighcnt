/// LE PLAN DU SITE EST UN RÉGLAGE, DÉSACTIVÉ PAR DÉFAUT (lot U, Direction, 11/11/2026).
///
/// Port de `SIGH.planDuSite` (`prototype_html/assets/js/parcours.js`, fin du fichier), de `N.ouvertParReglage` (`nav.js`) et des textes des pages d'erreur
/// (`modules/auth.js`) ; vecteurs `test/vecteurs/acces.json` (section `planDuSite`), engendrés par `prototype_html/build/vecteurs-acces.js`. Fonctions PURES.
///
/// Le réglage est un PARAMÈTRE EN BASE (`affichage.planDuSite`, voir `parametres/definitions.dart`), jamais une constante ni un masquage écrit à côté d'un écran : l'écran
/// reste au manifeste, et tout ce qui offre son lien (commande des paramètres, pages 403 et 404) lit ce réglage. Désactivé, son adresse directe se comporte
/// comme une adresse inconnue : la page 404 (Direction, 11/11/2026), jamais une page vide. La case se règle à « Installation et données », carte « Affichage ». Réglable par l'administrateur et la Directrice Administrative seuls,
/// journalisé avec l'ancienne et la nouvelle valeur (RG-12). Réglage de branche : il voyage aux fileuls par le journal de configuration, jamais aux mobiles.
library;

import '../rh/planning_rh.dart' show RefusRh;

/// La clé du paramètre (registre des paramètres du poste).
const String cleAffichagePlanDuSite = 'affichage.planDuSite';

/// La valeur quand rien n'est réglé : NON (le plan du site est désactivé par défaut).
const bool planDuSiteDefaut = false;

/// Les rôles qui règlent l'affichage du plan du site.
const List<String> rolesPlanDuSite = ['admin', 'da'];

/// Le plan du site est-il affiché ? Seule la valeur booléenne vraie l'affiche : absent, faux, texte, nombre ou nul ne l'affichent pas.
bool planDuSiteAffiche(Object? reglage) => reglage == true;

/// Le réglage de l'affichage : `null` s'il est permis, sinon le refus nommé (REGLAGE_RESERVE, VALEUR_INVALIDE).
RefusRh? controlerReglagePlanDuSite({required String role, required Object? valeur}) {
  if (!rolesPlanDuSite.contains(role)) {
    return const RefusRh('REGLAGE_RESERVE', 'Ce réglage se fait par l’administrateur ou la Directrice Administrative.', 'Demander à la Directrice Administrative.');
  }
  if (valeur is! bool) {
    return const RefusRh('VALEUR_INVALIDE', 'Le plan du site est affiché ou masqué : oui ou non.', 'Cocher ou décocher la case.');
  }
  return null;
}

/// Le texte de la page 404 : elle ne renvoie vers le plan du site que s'il est affiché.
String accMessage404({required bool planAffiche}) =>
    'L’écran demandé n’existe pas ou a été déplacé.${planAffiche ? ' Utiliser le plan du site pour retrouver le module recherché.' : ''}';

/// Le texte de la page 403 (le même plan du site affiché ou non : désactivé, son adresse mène à la page 404, jamais à un refus nommé).
const String accMessage403 =
    'Votre profil ne dispose pas des habilitations requises pour cet écran. L’accès est régi par la matrice RBAC (CDCT §12.1) et toute tentative est journalisée.';
