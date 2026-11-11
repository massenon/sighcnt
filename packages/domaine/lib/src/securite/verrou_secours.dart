/// LE VERROU D'UN POSTE DE SECOURS (lot ORG2, Direction, 11/11/2026, décision P3).
///
/// Port de `SIGH.verrouSecours` (`prototype_html/assets/js/parcours.js`, fin du fichier) et de la lecture du délai dans `app.js` (`delaiVerrou`) ; vecteurs
/// `test/vecteurs/organigramme.json` (section `secours`), engendrés par `prototype_html/build/vecteurs-organigramme.js`. Fonctions PURES.
///
/// Sur un poste partagé de secours (un agent sans téléphone y ouvre sa propre session, planning Q6), l'écran se verrouille plus vite que sur un poste ordinaire : 5 minutes par
/// défaut, contre 15 (CDCT 12.2, politique de sécurité). Le délai est un PARAMÈTRE EN BASE (`securite.delaiVerrouPosteSecours`, voir `definitions.dart`), jamais une constante :
/// valeur d'attente de l'équipe, MARQUÉE « à valider » (aucun document ne la fixe), réglable par l'administrateur ou la Directrice Administrative seuls, journalisé avec l'ancienne et
/// la nouvelle valeur (RG-12). Quel poste est « de secours » est une propriété du POSTE lui-même (donnée locale du poste, jamais synchronisée), pas de la session ni de l'agent ;
/// désigner un poste ne change aucun accès.
library;

import '../rh/planning_rh.dart' show RefusRh;

/// La clé du paramètre (registre des paramètres du poste).
const String cleDelaiVerrouSecours = 'securite.delaiVerrouPosteSecours';

/// Le délai d'un poste de secours quand rien n'est réglé : valeur d'attente de l'équipe, à valider.
const int delaiVerrouSecoursDefautMin = 5;

/// Les bornes du réglage, en minutes (celles de la politique de sécurité pour l'inactivité).
const int delaiVerrouSecoursMin = 1;
const int delaiVerrouSecoursMax = 120;

/// Le délai d'un poste ordinaire quand la politique de sécurité ne le fixe pas (CDCT 12.2).
const int delaiVerrouOrdinaireDefautMin = 15;

/// Les rôles qui règlent le délai et désignent un poste de secours.
const List<String> rolesVerrouSecours = ['admin', 'da'];

double _nombre(Object? v) {
  if (v is num) return v.toDouble();
  if (v is bool) return v ? 1 : 0;
  if (v == null) return 0;
  final t = '$v'.trim();
  if (t.isEmpty) return 0;
  return double.tryParse(t.replaceAll(',', '.')) ?? double.nan;
}

/// Le délai de secours EN FORCE : la valeur réglée si c'est un entier dans les bornes, sinon la valeur d'attente.
int delaiVerrouSecoursMinutes(Object? reglage) {
  if (reglage == null) return delaiVerrouSecoursDefautMin;
  final v = _nombre(reglage);
  return v.isFinite && v == v.floorToDouble() && v >= delaiVerrouSecoursMin && v <= delaiVerrouSecoursMax ? v.toInt() : delaiVerrouSecoursDefautMin;
}

/// Le délai du poste ordinaire : l'inactivité de la politique de sécurité quand elle est écrite et positive, sinon quinze minutes.
int delaiVerrouOrdinaireMinutes(Object? politiqueInactiviteMin) {
  if (politiqueInactiviteMin != null) {
    final v = _nombre(politiqueInactiviteMin);
    if (v.isFinite && v > 0) return v.toInt();
  }
  return delaiVerrouOrdinaireDefautMin;
}

/// Le délai de verrou EN FORCE sur CE poste, en minutes : celui du secours si le poste est désigné tel, sinon l'ordinaire.
int delaiVerrouPosteMinutes({required bool posteDeSecours, required Object? reglageSecours, required Object? politiqueInactiviteMin}) =>
    posteDeSecours ? delaiVerrouSecoursMinutes(reglageSecours) : delaiVerrouOrdinaireMinutes(politiqueInactiviteMin);

/// Le réglage du délai : `null` s'il est permis, sinon le refus nommé (REGLAGE_RESERVE, DELAI_INVALIDE).
RefusRh? controlerReglageDelaiSecours({required String role, required Object? minutes}) {
  if (!rolesVerrouSecours.contains(role)) {
    return const RefusRh('REGLAGE_RESERVE', 'Ce réglage se fait par l’administrateur ou la Directrice Administrative.', 'Demander à la Directrice Administrative.');
  }
  final m = _nombre(minutes);
  if (minutes == null || minutes == '' || !m.isFinite || m != m.floorToDouble() || m < delaiVerrouSecoursMin || m > delaiVerrouSecoursMax) {
    return const RefusRh('DELAI_INVALIDE', 'Le délai de verrou d’un poste de secours est un nombre entier de minutes, de $delaiVerrouSecoursMin à $delaiVerrouSecoursMax.', 'Saisir un nombre entier de minutes.');
  }
  return null;
}

/// La désignation de CE poste comme poste de secours : `null` si permise, sinon le refus nommé.
RefusRh? controlerDesignationPosteSecours({required String role}) => rolesVerrouSecours.contains(role)
    ? null
    : const RefusRh('REGLAGE_RESERVE', 'Cette désignation se fait par l’administrateur ou la Directrice Administrative.', 'Demander à la Directrice Administrative.');
