import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cpa_commun.dart';

/// `m12-dashboard` — « Tableau de bord — Comptabilité SYSCOHADA » : tout est CALCULÉ depuis les écritures de l'exercice, rien n'est fourni.
///
/// Écart E720 : « Produits et charges (12 mois) » lit `K.parMois`, dont le mois de référence est ÉCRIT EN DUR (1er août 2026) dans la maquette : les
/// douze mois s'arrêtent à août 2026 quelle que soit la date du jour. Porté fidèlement (ancre [cpaRefParMois]) et dit.
final cpaRefParMois = DateTime(2026, 8, 1);

class EcranDashboardCompta extends StatelessWidget with EcranMaquette {
  const EcranDashboardCompta({super.key});

  @override
  String get titre => 'Tableau de bord — Comptabilité SYSCOHADA';

  @override
  String get description =>
      'Équilibre des journaux, trésorerie, charges et produits, créances et dettes.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: ecouteCompta(c),
      builder: (context, _) {
        final e = ecrituresExercice(c);
        final t = cpaTableauDeBord(e);
        final prod = parMois([for (final x in e) if ('${x['compte']}'.startsWith('7')) x], 'date', champValeur: 'credit', ref: cpaRefParMois);
        final ch = parMois([for (final x in e) if ('${x['compte']}'.startsWith('6')) x], 'date', champValeur: 'debit', ref: cpaRefParMois);
        final parJournal = cpaGrouper(e, 'journal');
        final parOrigine = cpaGrouper(e, 'origine');
        final centres = cpaChargesParCentre(e, (k) => libelleCentre(c, k));
        final alertes = <Widget>[
          if (t.totalDebit != t.totalCredit)
            NoteSigh(
                'RG-10 — déséquilibre constaté : écart de ${money(t.ecart)} entre le total des débits et celui des crédits. À régulariser avant clôture.',
                ton: TonSigh.danger,
                icone: LucideIcons.scale3d),
          if (t.brouillons > 0)
            NoteSigh('${t.brouillons} écriture(s) en brouillon à valider.',
                ton: TonSigh.attention, icone: LucideIcons.fileClock),
        ];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (alertes.isNotEmpty) ...[
            LayoutBuilder(builder: (_, k) {
              final l = k.maxWidth >= 640 ? (k.maxWidth - 8) / 2 : k.maxWidth;
              return Wrap(spacing: 8, runSpacing: 8, children: [for (final a in alertes) SizedBox(width: l, child: a)]);
            }),
            const SizedBox(height: 16),
          ],
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Trésorerie disponible', valeur: money(t.tresorerie), icone: LucideIcons.wallet),
            KpiSigh(libelle: 'Chiffre d’affaires', valeur: money(t.chiffreAffaires), icone: LucideIcons.trendingUp, ton: TonSigh.succes),
            KpiSigh(libelle: 'Charges', valeur: money(t.charges), icone: LucideIcons.trendingDown, ton: TonSigh.attention),
            KpiSigh(
                libelle: 'Résultat',
                valeur: money(t.resultat),
                icone: t.resultat >= 0 ? LucideIcons.smile : LucideIcons.frown,
                ton: t.resultat >= 0 ? TonSigh.succes : TonSigh.danger),
            KpiSigh(libelle: 'Créances clients', valeur: money(t.clients), icone: LucideIcons.handCoins, ton: TonSigh.info),
            KpiSigh(libelle: 'Dettes fournisseurs', valeur: money(t.fournisseurs), icone: LucideIcons.truck, ton: TonSigh.attention),
            KpiSigh(libelle: 'Écritures de l’exercice', valeur: nombre(t.nbEcritures), icone: LucideIcons.bookOpenCheck, ton: TonSigh.neutre),
            KpiSigh(
                libelle: 'Équilibre (RG-10)',
                valeur: t.equilibre ? 'Équilibré' : money(t.ecart),
                icone: LucideIcons.scale,
                ton: t.equilibre ? TonSigh.succes : TonSigh.danger),
          ]),
          const SizedBox(height: 16),
          deuxCartes(
            CarteSigh(
                titre: 'Produits et charges (12 mois)',
                child: GraphiqueLigne(etiquettes: prod.etiquettes, series: [
                  SerieGraphique('Produits', prod.valeurs, couleur: JetonsShell.success500),
                  SerieGraphique('Charges', ch.valeurs, couleur: JetonsShell.danger500),
                ])),
            CarteSigh(
                titre: 'Écritures par journal',
                child: GraphiqueAnneau(
                    etiquettes: [for (final k in parJournal.keys) cpaJournalLibelle(k)],
                    valeurs: [for (final k in parJournal.keys) parJournal[k]!.length])),
          ),
          const SizedBox(height: 16),
          deuxCartes(
            CarteSigh(
                titre: 'Charges par centre de coûts',
                child: ClassementSigh([for (final x in centres) (libelle: x.$1, valeur: x.$2)])),
            CarteSigh(
                titre: 'Origine des écritures',
                child: GraphiqueBarres(horizontal: true, hauteur: 260, etiquettes: parOrigine.keys.toList(), series: [
                  SerieGraphique('Écritures', [for (final k in parOrigine.keys) parOrigine[k]!.length])
                ])),
          ),
          const SizedBox(height: 16),
          SectionSigh(
            titre: 'Automatisation des écritures',
            child: MiniTableauSigh(colonnes: [
              ColonneMini('Opération métier', (x) => '${x['op']}'),
              ColonneMini('Module d’origine', (x) => '${x['mod']}'),
              ColonneMini('Journal', (x) => '${x['journal']}', rendu: (x) => BadgeSigh('${x['journal']}', ton: TonSigh.navy)),
              ColonneMini('Compte débité', (x) => '${x['debit']}', rendu: (x) => Text('${x['debit']}', style: mono)),
              ColonneMini('Compte crédité', (x) => '${x['credit']}', rendu: (x) => Text('${x['credit']}', style: mono)),
            ], lignes: [
              for (final a in cpaAutomatisations) {'op': a.$1, 'mod': a.$2, 'journal': a.$3, 'debit': a.$4, 'credit': a.$5}
            ]),
          ),
          const SizedBox(height: 16),
          SectionSigh(
            titre: 'Accès rapides',
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: RaccourcisSigh(aller: c.aller, items: const [
                RaccourciDef(id: 'm12-ecritures', icone: LucideIcons.pencilLine, libelle: 'Saisir une écriture', detail: 'Équilibre contrôlé (RG-10)'),
                RaccourciDef(id: 'm12-grand-livre', icone: LucideIcons.bookOpen, libelle: 'Grand livre', detail: 'Par compte'),
                RaccourciDef(id: 'm12-balance', icone: LucideIcons.scale, libelle: 'Balance', detail: 'Générale et âgée'),
                RaccourciDef(id: 'm12-etats-financiers', icone: LucideIcons.fileSpreadsheet, libelle: 'États financiers', detail: 'Bilan et résultat'),
              ]),
            ),
          ),
        ]);
      },
    );
  }
}
