import 'package:sigh_domaine/sigh_domaine.dart' as d;

import '../core/service_parametres.dart';
import 'magasin.dart';

/// Le MODE de certification MECeF en vigueur à [maintenant] (lot L3, décision de la Direction du 09/11/2026) : le paramètre `mecef.mode` du registre du lot L0,
/// LU en base (défaut `boitier`, versionné par date, synchronisé par le journal), jamais une constante. Une valeur inconnue retombe sur le défaut.
///
/// Le mode ne s'inscrit pas dans `usagesParametres` : il ne fixe aucun contenu de la pièce (la pièce porte le mode sous lequel la tentative a eu lieu,
/// `modeMecef`), et l'inscrire interdirait de le rebasculer le jour même.
String modeMecefDuPoste(Magasin m, DateTime maintenant) {
  final service = serviceParametres(m, auteur: () => m.utilisateur, horloge: () => maintenant);
  return d.mecefModeEnVigueur(service.valeur(d.mecefCleMode, d.parametreDateIso(maintenant)));
}

/// L'adaptateur du mode en vigueur. Tant qu'aucun adaptateur réel n'existe (lot M3 : le modèle, l'interface et le protocole du boîtier, et le dossier
/// d'interface e-MECeF de la DGI ne figurent dans aucun document remis), c'est l'adaptateur « non configuré » : il REFUSE en nommant et ne fabrique aucun numéro.
d.AdaptateurMecef adaptateurDuPoste(Magasin m, DateTime maintenant) => d.adaptateurPourMode(modeMecefDuPoste(m, maintenant));
