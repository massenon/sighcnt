import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'commun.dart';

/// `m8-dashboard` — « Tableau de bord — Facturation & Caisse » : tout est CALCULÉ depuis les factures, rien n'est fourni.
class EcranDashboardFacturation extends StatelessWidget with EcranMaquette {
  const EcranDashboardFacturation({super.key});

  @override
  String get titre => 'Tableau de bord — Facturation & Caisse';

  @override
  String get description =>
      'Chiffre d’affaires, encaissements, reliquats, répartition des règlements et recettes par activité.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('factures');
    final auj = c.aujourdhui;
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final f = col.actives;
        num som(Iterable<Fiche> r, String k) =>
            r.fold<num>(0, (a, x) => a + n(x[k]));
        final jour = iso(auj);
        final fj = [
          for (final x in f)
            if (x['date'] != null && '${x['date']}'.startsWith(jour)) x
        ];
        final fm = [
          for (final x in f)
            if (DateTime.tryParse('${x['date']}') case final d?
                when d.year == auj.year && d.month == auj.month)
              x
        ];
        final fa = parMois(f, 'date', champValeur: 'montantTTC', ref: auj);
        final en = parMois(f, 'date', champValeur: 'montantPaye', ref: auj);
        final parType = <String, num>{};
        final parMode = <String, num>{};
        for (final x in f) {
          parType['${x['type']}'] =
              (parType['${x['type']}'] ?? 0) + n(x['montantTTC']);
          parMode['${x['modePaiement']}'] =
              (parMode['${x['modePaiement']}'] ?? 0) + n(x['montantPaye']);
        }
        final jours = [for (var d = 1; d <= auj.day; d++) d];
        final parJour = [
          for (final d in jours)
            f
                .where((x) => '${x['date']}'
                    .startsWith(iso(DateTime(auj.year, auj.month, d))))
                .length
        ];
        final derniers = f.take(10).toList();

        Widget deux(Widget a, Widget b) => LayoutBuilder(builder: (_, k) {
              final l = k.maxWidth >= 1024 ? (k.maxWidth - 16) / 2 : k.maxWidth;
              return Wrap(spacing: 16, runSpacing: 16, children: [
                SizedBox(width: l, child: a),
                SizedBox(width: l, child: b)
              ]);
            });

        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Chiffre d’affaires du jour',
                    valeur: money(som(fj, 'montantTTC')),
                    icone: LucideIcons.trendingUp),
                KpiSigh(
                    libelle: 'Encaissé aujourd’hui',
                    valeur: money(som(fj, 'montantPaye')),
                    icone: LucideIcons.banknote,
                    ton: TonSigh.succes),
                KpiSigh(
                    libelle: 'Chiffre d’affaires du mois',
                    valeur: money(som(fm, 'montantTTC')),
                    icone: LucideIcons.calendar,
                    ton: TonSigh.info),
                KpiSigh(
                    libelle: 'Encaissé sur le mois',
                    valeur: money(som(fm, 'montantPaye')),
                    icone: LucideIcons.wallet,
                    ton: TonSigh.succes),
                KpiSigh(
                    libelle: 'Nombre de factures',
                    valeur: nombre(f.length),
                    icone: LucideIcons.receipt,
                    ton: TonSigh.neutre),
                KpiSigh(
                    libelle: 'Reliquats en cours',
                    valeur: money(som(f, 'reliquat')),
                    icone: LucideIcons.handCoins,
                    ton: TonSigh.attention),
                KpiSigh(
                    libelle: 'Factures impayées',
                    valeur: nombre(f
                        .where((x) => x['statutPaiement'] == 'impayee')
                        .length),
                    icone: LucideIcons.fileX,
                    ton: TonSigh.danger),
                KpiSigh(
                    libelle: 'Part assurance à recouvrer',
                    valeur: money(som(f.where((x) => x['assureur'] != null),
                        'partAssurance')),
                    icone: LucideIcons.shieldCheck,
                    ton: TonSigh.info),
              ]),
              const SizedBox(height: 16),
              deux(
                CarteSigh(
                    titre: 'Évolution du chiffre d’affaires (12 mois)',
                    child: GraphiqueLigne(etiquettes: fa.etiquettes, series: [
                      SerieGraphique('Facturé', fa.valeurs,
                          couleur: JetonsShell.navy900),
                      SerieGraphique('Encaissé', en.valeurs,
                          couleur: JetonsShell.success500),
                    ])),
                CarteSigh(
                    titre: 'Recettes par activité',
                    child: GraphiqueAnneau(
                        etiquettes: parType.keys.toList(),
                        valeurs: parType.values.toList())),
              ),
              const SizedBox(height: 16),
              deux(
                CarteSigh(
                    titre: 'Répartition des modes de paiement',
                    child: GraphiqueBarres(horizontal: true, etiquettes: [
                      for (final k in parMode.keys) modeLabel(k)
                    ], series: [
                      SerieGraphique(
                          'Montant encaissé', parMode.values.toList())
                    ])),
                CarteSigh(
                    titre: 'Factures par jour (mois en cours)',
                    child: GraphiqueBarres(etiquettes: [
                      for (final d in jours) '$d'
                    ], series: [
                      SerieGraphique('Factures', parJour,
                          couleur: JetonsShell.navy600)
                    ])),
              ),
              const SizedBox(height: 16),
              SectionSigh(
                titre: 'Dernières factures',
                actions: [
                  lienVers('Toutes les factures', () => c.aller('m8-factures'))
                ],
                child: MiniTableauSigh(colonnes: [
                  ColonneMini('N°', (x) => '${x['numero']}',
                      rendu: (x) => Text('${x['numero']}',
                          style: const TextStyle(
                              fontFamily: 'LiberationMono',
                              fontSize: 12,
                              color: JetonsShell.slate700))),
                  ColonneMini('Date', (x) => dateDe(x['date'])),
                  ColonneMini('Patient', (x) => '${x['patient'] ?? ''}'),
                  ColonneMini('Nature', (x) => '${x['type'] ?? ''}'),
                  ColonneMini('Montant', (x) => m(x['montantTTC']),
                      droite: true),
                  ColonneMini('Réglé', (x) => m(x['montantPaye']),
                      droite: true),
                  ColonneMini('Statut', (x) => '',
                      rendu: (x) => statutBadge(x['statutPaiement'])),
                ], lignes: derniers),
              ),
              const SizedBox(height: 16),
              SectionSigh(
                titre: 'Accès rapides',
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: RaccourcisSigh(aller: c.aller, items: const [
                    RaccourciDef(
                        id: 'm8-facturation',
                        icone: LucideIcons.filePlus,
                        libelle: 'Nouvelle facture',
                        detail: 'Actes, analyses, médicaments'),
                    RaccourciDef(
                        id: 'm8-paiements',
                        icone: LucideIcons.banknote,
                        libelle: 'Encaisser',
                        detail: 'Espèces, TPE, Mobile Money'),
                    RaccourciDef(
                        id: 'm8-reliquats',
                        icone: LucideIcons.handCoins,
                        libelle: 'Reliquats',
                        detail: 'Règlements différés'),
                    RaccourciDef(
                        id: 'm8-caisse',
                        icone: LucideIcons.printer,
                        libelle: 'État de caisse',
                        detail: 'Arrêté journalier'),
                  ]),
                ),
              ),
            ]);
      },
    );
  }
}
