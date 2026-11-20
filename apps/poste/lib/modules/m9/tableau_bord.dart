import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'commun.dart';

/// `m9-dashboard` — « Tableau de bord — Assurances » : tout est CALCULÉ (assurés, validité des cartes, créances), rien n'est fourni.
/// La validité de la carte se lit au moteur (couverture datée, RG-09) ; les créances sont la part assureur des factures prises en charge.
class EcranDashboardAssurances extends StatelessWidget with EcranMaquette {
  const EcranDashboardAssurances({super.key});

  @override
  String get titre => 'Tableau de bord — Assurances';

  @override
  String get description =>
      'Assurés, validité des cartes, prises en charge, créances par compagnie et relances.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: ecoute(c, [
        'assureurs',
        'patients',
        'factures',
        'couverturesAssurance'
      ]),
      builder: (context, _) {
        final assureurs = actives(c, 'assureurs');
        final patients = actives(c, 'patients');
        final factures = actives(c, 'factures');
        final fa = assFacturesAssurance(factures);
        final assures = assAssures(patients);
        final k = assKpisDashboard(
            assureurs: assureurs,
            patients: patients,
            factures: factures,
            carteValide: (p) => carteValideLe(c, p));
        final creances = [
          for (final a in assureurs)
            (libelle: '${a['code']}', valeur: assCreance(fa, '${a['code']}'))
        ].where((x) => x.valeur > 0).toList()
          ..sort((a, b) => b.valeur.compareTo(a.valeur));
        final parCompagnie = <String, int>{};
        for (final p in assures) {
          parCompagnie['${p['assureur']}'] =
              (parCompagnie['${p['assureur']}'] ?? 0) + 1;
        }
        final prises =
            parMois(fa, 'date', champValeur: 'partAssurance', ref: c.aujourdhui);

        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (k.expirees > 0) ...[
                NoteSigh(
                    '${k.expirees} carte(s) d’assurance expirée(s). En application de la règle RG-09, la facturation de ces patients doit être intégrale tant que la carte n’est pas renouvelée.',
                    ton: TonSigh.danger,
                    icone: LucideIcons.shieldAlert),
                const SizedBox(height: 16),
              ],
              SectionSigh(
                titre: 'Accès rapides',
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: RaccourcisSigh(aller: c.aller, items: const [
                    RaccourciDef(
                        id: 'm9-compagnies',
                        icone: LucideIcons.building2,
                        libelle: 'Compagnies',
                        detail: 'Référentiel et conventions'),
                    RaccourciDef(
                        id: 'm9-assures',
                        icone: LucideIcons.idCard,
                        libelle: 'Assurés & cartes',
                        detail: 'Vérification de validité'),
                    RaccourciDef(
                        id: 'm9-factures-assureur',
                        icone: LucideIcons.fileText,
                        libelle: 'Facture mensuelle',
                        detail: 'Par assureur'),
                    RaccourciDef(
                        id: 'm9-relances',
                        icone: LucideIcons.send,
                        libelle: 'Relances',
                        detail: 'Créances en souffrance'),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Compagnies partenaires',
                    valeur: nombre(k.compagnies),
                    indice: 'Référentiel de la clinique',
                    icone: LucideIcons.building2),
                KpiSigh(
                    libelle: 'Patients assurés',
                    valeur: nombre(k.assures),
                    icone: LucideIcons.users,
                    ton: TonSigh.info),
                KpiSigh(
                    libelle: 'Cartes valides',
                    valeur: nombre(k.valides),
                    icone: LucideIcons.shieldCheck,
                    ton: TonSigh.succes),
                KpiSigh(
                    libelle: 'Cartes expirées',
                    valeur: nombre(k.expirees),
                    icone: LucideIcons.shieldAlert,
                    ton: TonSigh.danger),
                KpiSigh(
                    libelle: 'Factures avec prise en charge',
                    valeur: nombre(k.facturesAssurance),
                    icone: LucideIcons.receipt),
                KpiSigh(
                    libelle: 'Créances assureurs',
                    valeur: money(k.creances),
                    icone: LucideIcons.handCoins,
                    ton: TonSigh.attention),
                KpiSigh(
                    libelle: 'Montant total pris en charge',
                    valeur: money(k.creances),
                    icone: LucideIcons.wallet,
                    ton: TonSigh.info),
                KpiSigh(
                    libelle: 'Taux moyen de prise en charge',
                    valeur: pourcent(k.tauxMoyen),
                    icone: LucideIcons.percent,
                    ton: TonSigh.neutre),
              ]),
              const SizedBox(height: 16),
              deuxCartes(
                CarteSigh(
                    titre: 'Créances par compagnie',
                    child: ClassementSigh(creances,
                        ton: JetonsShell.warning500)),
                CarteSigh(
                    titre: 'Répartition des assurés par compagnie',
                    child: GraphiqueAnneau(
                        etiquettes: parCompagnie.keys.toList(),
                        valeurs: parCompagnie.values.toList())),
              ),
              const SizedBox(height: 16),
              deuxCartes(
                CarteSigh(
                    titre: 'Prises en charge (12 mois)',
                    child: GraphiqueBarres(
                        etiquettes: prises.etiquettes,
                        series: [
                          SerieGraphique('Part assurance', prises.valeurs,
                              couleur: JetonsShell.info600)
                        ])),
                CarteSigh(
                    titre: 'Validité des cartes',
                    child: GraphiqueAnneau(
                        etiquettes: const ['Cartes valides', 'Cartes expirées'],
                        valeurs: [k.valides, k.expirees],
                        couleurs: const [
                          JetonsShell.success500,
                          JetonsShell.danger600
                        ])),
              ),
            ]);
      },
    );
  }
}
