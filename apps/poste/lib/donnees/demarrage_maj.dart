import 'package:sigh_domaine/sigh_domaine.dart';

import 'maj_poste.dart';

/// Ce que `main.dart` fait de la mise à jour AVANT d'ouvrir le magasin (lot MAJ) : extrait ici pour être joué par un test d'intégration sur un dossier de données d'AVANT, exactement comme au démarrage.
///  1. une migration ou un import INTERROMPU par une coupure est ramené aux données d'avant (jamais un état mixte) ;
///  2. un dossier NEUF reçoit le format courant (rien à migrer) ; un dossier d'avant (format 0 ou 1) n'est PAS migré en silence : la migration est un geste explicite, après « Préparer la mise à jour » ;
///  3. des données plus RÉCENTES que ce logiciel ne s'ouvrent pas (refus nommé).
class DemarrageMaj {
  const DemarrageMaj({required this.service, required this.format, required this.plan, required this.reprise});
  final ServiceMiseAJour service;

  /// Le format STOCKÉ : celui que la mère tient et que le fileul dit à chaque requête (426 hors tolérance).
  final int format;
  final PlanMigration plan;

  /// Une opération interrompue a été ramenée aux données d'avant.
  final bool reprise;
  RefusMaj? get refus => plan.refus;
}

Future<DemarrageMaj> demarrerMiseAJour({required String dossierDonnees, required List<int> cle}) async {
  final maj = ServiceMiseAJour(dossier: '$dossierDonnees/magasin', cle: cle, dossierFichiers: '$dossierDonnees/fichiers');
  final reprise = await maj.reprendreSiInterrompu();
  await maj.marquerNeuf();
  final plan = await maj.plan();
  return DemarrageMaj(service: maj, format: await maj.formatDonnees(), plan: plan, reprise: reprise);
}
