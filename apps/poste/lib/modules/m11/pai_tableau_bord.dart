import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'pai_commun.dart';

/// `m11-dashboard` — « Tableau de bord — Paie » : tout est CALCULÉ par le moteur de la paie sur le mois de l'horloge du poste. Coût employeur et retenues
/// de l'AGENT sont deux grandeurs distinctes (jamais additionnées). La courbe « Évolution » est un tirage à graine autour des salaires de base : une
/// illustration, que la maquette porte telle quelle.
class EcranDashboardPaie extends StatelessWidget with EcranMaquette {
  const EcranDashboardPaie({super.key});

  @override
  String get titre => 'Tableau de bord — Paie';

  @override
  String get description => 'Masse salariale, primes, cotisations sociales et fiscales, avances et coût employeur.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: ecoutePaie(c),
      builder: (context, _) {
        final calc = calculerTousPaie(c, c.aujourdhui.month - 1);
        final parService = <String, List<PaiCalcul>>{};
        for (final x in calc) {
          parService.putIfAbsent('${x.employe['service']}', () => []).add(x);
        }
        final classement = [
          for (final e in parService.entries) (libelle: e.key, valeur: paiSomme(e.value, (x) => x.brut))
        ];
        // `Array.prototype.sort` est stable : les ex æquo gardent l'ordre d'apparition.
        final tries = trierPar(classement, (l) => l.valeur, descendant: true);
        final labels = paiMoisGlissants(12);
        // `C.sum(personnel(), 'salaireBase')` : le personnel ACTIF, indépendamment du calcul.
        final masse = paiEvolutionMasse(c.magasin.collection('personnel').actives.fold<num>(0, (a, p) => a + nombreOuZero(p['salaireBase'])));

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionSigh(
            titre: 'Accès rapides',
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: RaccourcisSigh(aller: c.aller, items: const [
                RaccourciDef(id: 'm11-calcul', icone: LucideIcons.calculator, libelle: 'Calculer la paie', detail: 'Période en cours'),
                RaccourciDef(id: 'm11-bulletins', icone: LucideIcons.fileText, libelle: 'Bulletins de paie', detail: 'Édition et archivage'),
                RaccourciDef(id: 'm11-cotisations', icone: LucideIcons.landmark, libelle: 'Cotisations', detail: 'CNSS, ITS, VPS'),
                RaccourciDef(id: 'm11-validation', icone: LucideIcons.badgeCheck, libelle: 'Validation Direction', detail: 'Avant diffusion'),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Masse salariale brute', valeur: money(paiSomme(calc, (x) => x.brut)), icone: LucideIcons.banknote),
            KpiSigh(libelle: 'Net à payer', valeur: money(paiSomme(calc, (x) => x.net)), icone: LucideIcons.wallet, ton: TonSigh.succes),
            KpiSigh(libelle: 'Total des primes', valeur: money(paiSomme(calc, (x) => x.totalPrimes)), icone: LucideIcons.gift, ton: TonSigh.info, indice: 'Barème NS 132'),
            KpiSigh(libelle: 'Sanctions (NS 131)', valeur: money(paiSomme(calc, (x) => x.sanction)), icone: LucideIcons.trendingDown, ton: TonSigh.danger),
            KpiSigh(
                libelle: 'CNSS part ouvrière',
                valeur: money(paiSomme(calc, (x) => x.cnssOuvriere)),
                icone: LucideIcons.shield,
                ton: TonSigh.attention,
                indice: '${paiNum(paiCnssOuvriere)} %'),
            KpiSigh(
                libelle: 'CNSS part patronale',
                valeur: money(paiSomme(calc, (x) => x.cnssPatronale)),
                icone: LucideIcons.building2,
                ton: TonSigh.attention,
                indice: '${paiNum(paiCnssPatronale)} %'),
            KpiSigh(libelle: 'ITS retenu', valeur: money(paiSomme(calc, (x) => x.its)), icone: LucideIcons.landmark, ton: TonSigh.info),
            KpiSigh(libelle: 'Coût employeur total', valeur: money(paiSomme(calc, (x) => x.coutEmployeur)), icone: LucideIcons.calculator, ton: TonSigh.neutre),
          ]),
          const SizedBox(height: 16),
          deuxCartes(
            CarteSigh(
                titre: 'Décomposition de la masse salariale',
                child: GraphiqueAnneau(
                    etiquettes: const ['Salaires de base', 'Primes NS 132', 'Prime d’ancienneté'],
                    valeurs: [paiSomme(calc, (x) => x.salaireBase), paiSomme(calc, (x) => x.totalPrimes), paiSomme(calc, (x) => x.primeAnciennete)])),
            CarteSigh(
                titre: 'Répartition des charges et retenues',
                child: GraphiqueBarres(
                    etiquettes: const ['CNSS ouvrière', 'CNSS patronale', 'VPS', 'ITS', 'ORTB'],
                    horizontal: true,
                    hauteur: 260,
                    series: [
                      SerieGraphique('Montant', [
                        paiSomme(calc, (x) => x.cnssOuvriere),
                        paiSomme(calc, (x) => x.cnssPatronale),
                        paiSomme(calc, (x) => x.vps),
                        paiSomme(calc, (x) => x.its),
                        paiSomme(calc, (x) => x.ortb),
                      ])
                    ])),
          ),
          const SizedBox(height: 16),
          deuxCartes(
            CarteSigh(titre: 'Masse salariale par service', child: ClassementSigh(tries)),
            CarteSigh(
                titre: 'Évolution de la masse salariale (12 mois)',
                child: GraphiqueLigne(etiquettes: labels, series: [SerieGraphique('Masse salariale', masse, couleur: JetonsShell.navy900)])),
          ),
        ]);
      },
    );
  }
}
