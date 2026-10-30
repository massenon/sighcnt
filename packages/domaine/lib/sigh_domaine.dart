/// Règles métier SIGH-CNT — un seul exemplaire, exécuté par le poste, le mobile et la mère.
/// Source de vérité du comportement : `prototype_html/` (exécutable de référence) et les
/// vecteurs de tests de `test/vecteurs/` (JSON entrée -> sortie, engendrés depuis la maquette).
library sigh_domaine;

export 'src/sync/operation.dart';
export 'src/sync/familles.dart';
export 'src/sync/codes.dart';
export 'src/format/format_fr.dart';
export 'src/referentiels/regles.dart';
export 'src/referentiels/periodes.dart';
export 'src/design/jetons.dart';
export 'src/droits/matrice.dart';
export 'src/caisse/prise_en_charge.dart';
