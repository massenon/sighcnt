import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'tba_commun.dart';

/// `dash-rh` — « Tableau de bord — Ressources humaines » : le compte RH est FERMÉ depuis le 24/08/2026 (archivé, non supprimé) et les ressources
/// humaines relèvent de la DAF. Le premier regard dit la décision plutôt que d'afficher un tableau comme si de rien n'était.
class EcranDashRh extends StatelessWidget with EcranMaquette {
  const EcranDashRh({super.key});

  @override
  String get titre => 'Tableau de bord — Ressources humaines';

  @override
  String get description =>
      'Effectif, plannings, présences, évaluations NS 131, primes NS 132 et masse salariale.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: tbaEcoute(c, ['personnel', 'planning']),
      builder: (context, _) {
        final d = tbaRh(personnel: tbaActives(c, 'personnel'), planning: tbaActives(c, 'planning'), auj: c.aujourdhui);
        return TbaDash(
          premier: d.premier,
          rapides: [
            tbaAccesRapides(c, const [
              ('m10-planning', 'calendar-days', 'Planning & gardes', 'Garde 24h, permanence'),
              ('m10-evaluations', 'clipboard-check', 'Évaluations NS 131', '4 critères, barème de sanction'),
              ('m10-primes', 'gift', 'Primes NS 132', 'Grille par fonction'),
              ('m11-calcul', 'calculator', 'Calcul de la paie', 'CNSS, ITS, VPS'),
            ]),
          ],
          kpis: d.kpis,
          sections: [
            tbaCarte('Effectif par fonction', ClassementTba([for (final f in d.parFonction) (f.$1, f.$2)]),
                actions: [tbaLien(c, 'm10-personnel', 'Gérer le personnel', 'arrow-right')]),
            tbaDeuxCartes(
              CarteSigh(
                  titre: 'Répartition du personnel par service',
                  child: GraphiqueAnneau(etiquettes: d.parService.etiquettes, valeurs: d.parService.series.first.donnees)),
              CarteSigh(
                  titre: 'Planning du jour',
                  child: GraphiqueBarres(
                      horizontal: true,
                      hauteur: 240,
                      etiquettes: d.planningDuJour.etiquettes,
                      series: [SerieGraphique('Agents', d.planningDuJour.series.first.donnees)])),
            ),
          ],
        );
      },
    );
  }
}
