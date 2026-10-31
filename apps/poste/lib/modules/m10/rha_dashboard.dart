import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m9/commun.dart' show ecoute;
import 'rha_commun.dart';

/// `m10-dashboard` — « Tableau de bord — Ressources humaines » : effectif, plannings, présences, évaluations, primes et masse salariale. Tout est CALCULÉ
/// depuis le personnel et le planning du jour (jamais fourni) ; les règles viennent des notes NS 131 / NS 132 en vigueur.
class EcranDashboardRh extends StatelessWidget with EcranMaquette {
  const EcranDashboardRh({super.key});
  @override
  String get titre => 'Tableau de bord — Ressources humaines';
  @override
  String get description => 'Effectif, plannings, présences, évaluations, primes et masse salariale.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
        listenable: ecoute(c, ['personnel', 'planning']),
        builder: (context, _) {
          final p = c.magasin.collection('personnel').actives;
          final jour = rhaPlanningDuJour(c.magasin.collection('planning').actives, c.aujourdhui);
          final parService = rhaParService(p);
          final planning = rhaRepartitionPlanning(jour);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionSigh(
              titre: 'Accès rapides',
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: RaccourcisSigh(aller: c.aller, items: const [
                  RaccourciDef(id: 'm10-planning', icone: LucideIcons.calendarDays, libelle: 'Planning & gardes', detail: 'Garde 24h, permanence, repos'),
                  RaccourciDef(id: 'm10-evaluations', icone: LucideIcons.clipboardCheck, libelle: 'Évaluations', detail: 'Barème NS 131'),
                  RaccourciDef(id: 'm10-primes', icone: LucideIcons.gift, libelle: 'Primes', detail: 'Grille NS 132'),
                  RaccourciDef(id: 'm11-calcul', icone: LucideIcons.calculator, libelle: 'Calcul de la paie', detail: 'CNSS, ITS, VPS'),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            KpiGrilleSigh(
                kpis: rhaKpisW(rhaKpisDashboard(p, jour, c.aujourdhui), const [
              LucideIcons.usersRound,
              LucideIcons.banknote,
              LucideIcons.calculator,
              LucideIcons.award,
              LucideIcons.moon,
              LucideIcons.sun,
              LucideIcons.bed,
              LucideIcons.clipboardCheck,
            ])),
            const SizedBox(height: 16),
            rhaCartes([
              CarteSigh(
                  titre: 'Effectif par fonction',
                  child: RhaClassement([for (final x in rhaEffectifParFonction(p)) (libelle: x.libelle, valeur: x.valeur, rouge: false)])),
              CarteSigh(
                  titre: 'Répartition par service',
                  child: GraphiqueAnneau(etiquettes: [for (final x in parService) x.service], valeurs: [for (final x in parService) x.effectif])),
            ]),
            const SizedBox(height: 16),
            rhaCartes([
              CarteSigh(
                  titre: 'Masse salariale par service',
                  child: GraphiqueBarres(
                      horizontal: true,
                      hauteur: 320,
                      etiquettes: [for (final x in parService) x.service],
                      series: [SerieGraphique('Masse salariale', [for (final x in parService) x.masse])])),
              CarteSigh(
                  titre: 'Planning du jour',
                  child: GraphiqueAnneau(etiquettes: [for (final x in planning) x.libelle], valeurs: [for (final x in planning) x.nombre])),
            ]),
            const SizedBox(height: 16),
            SectionSigh(
                titre: 'Règles métier en vigueur',
                child: MiniTableauSigh(colonnes: [
                  ColonneMini('Référence', (n) => '${n['reference']}',
                      rendu: (n) => Text('${n['reference']}', style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 12, fontWeight: FontWeight.w600, color: JetonsShell.slate900))),
                  ColonneMini('Objet', (n) => '${n['objet']}'),
                  ColonneMini('Version', (n) => 'v${n['version']}'),
                  ColonneMini('Date d’effet', (n) => rhaDateFR(n['dateEffet'])),
                  ColonneMini('Statut', (n) => '${n['statut']}', rendu: (n) => BadgeSigh('${n['statut']}', ton: TonSigh.succes)),
                  ColonneMini('Signataire', (n) => '${n['signataire']}'),
                ], lignes: [
                  for (final n in [admNs131, admNs132])
                    {'reference': n.reference, 'objet': n.objet, 'version': n.version, 'dateEffet': n.dateEffet, 'statut': n.statut, 'signataire': n.signataire}
                ])),
          ]);
        });
  }
}
