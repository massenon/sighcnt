/// Règles métier SIGH-CNT — un seul exemplaire, exécuté par le poste, le mobile et la mère.
/// Source de vérité du comportement : `prototype_html/` (exécutable de référence) et les
/// vecteurs de tests de `test/vecteurs/` (JSON entrée -> sortie, engendrés depuis la maquette).
library sigh_domaine;

export 'src/sync/operation.dart';
export 'src/sync/familles.dart';
export 'src/sync/codes.dart';
export 'src/format/format_fr.dart';
export 'src/format/recherche.dart';
export 'src/format/js.dart' show nombreOuZero, arrondiJs;
export 'src/referentiels/regles.dart';
export 'src/referentiels/periodes.dart';
export 'src/design/jetons.dart';
export 'src/droits/matrice.dart';
export 'src/navigation/manifeste.dart';
export 'src/caisse/prise_en_charge.dart';
export 'src/caisse/encaissement.dart';
export 'src/caisse/emission.dart';
export 'src/caisse/avoir.dart';
export 'src/caisse/remboursement.dart';
export 'src/caisse/mecef.dart';
export 'src/achats/pv_reception.dart';
export 'src/achats/fournisseurs_m7.dart';
export 'src/achats/factures_fournisseurs.dart';
export 'src/stock/referentiels_stock.dart';
export 'src/stock/stock.dart';
export 'src/stock/points.dart';
export 'src/graphiques/echelle.dart';
export 'src/stock/mouvements_stock.dart';
export 'src/impression/identite.dart';
export 'src/impression/ticket.dart';
export 'src/impression/etat.dart';
