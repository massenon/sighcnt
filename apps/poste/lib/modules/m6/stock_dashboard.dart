import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'stock_commun.dart';

/// `m6-dashboard` — « Tableau de bord — Stocks » : valeur du stock, produits critiques, péremptions, rotation et visualisation par catégorie. Tout est
/// CALCULÉ depuis les produits, les lots et les mouvements ; rien n'est fourni. FERMÉ au caissier (matrice RBAC : la coque ne l'ouvre pas).
class EcranDashboardStock extends StatelessWidget with EcranMaquette {
  const EcranDashboardStock({super.key});

  @override
  String get titre => 'Tableau de bord — Stocks';

  @override
  String get description =>
      'Valeur du stock, produits critiques, péremptions, rotation et visualisation par catégorie.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final cp = c.magasin.collection('produits');
    final cl = c.magasin.collection('lots');
    final cm = c.magasin.collection('mouvements');
    return ListenableBuilder(
      listenable: Listenable.merge([cp, cl, cm]),
      builder: (context, _) {
        final auj = c.aujourdhui;
        final p = cp.actives, l = cl.actives, m = cm.actives;
        final statuts = [for (final x in l) statutDuLot(x, auj)];
        final perimes = statuts.where((s) => s == 'perime').length;
        final proches = statuts.where((s) => s == 'alerte').length;
        final critiques =
            p.where((x) => sousSeuil(x['stock'], x['seuilAlerte'])).length;
        final prioritaires = aReapprovisionner(p);

        Widget deux(Widget a, Widget b) => LayoutBuilder(builder: (_, k) {
              final lg =
                  k.maxWidth >= 1024 ? (k.maxWidth - 16) / 2 : k.maxWidth;
              return Wrap(spacing: 16, runSpacing: 16, children: [
                SizedBox(width: lg, child: a),
                SizedBox(width: lg, child: b)
              ]);
            });

        final notes = <Widget>[
          if (critiques > 0)
            NoteSigh(
                '$critiques produit(s) sous le seuil d’alerte — établir un bon de commande (validation DA requise, RG-04).',
                ton: TonSigh.danger,
                icone: LucideIcons.trendingDown),
          if (perimes > 0)
            NoteSigh(
                '$perimes lot(s) périmé(s) — retour aux fournisseurs habilités (CAME, SoBAPS) et valorisation de la perte.',
                ton: TonSigh.danger,
                icone: LucideIcons.octagonAlert),
          if (noteSansSeuil(p) case final ns?) ns,
        ];

        final parCategorie = grouperPar(p, 'categorie');
        final entrees = parMois([
          for (final x in m)
            if (x['type'] == 'entree') x
        ], 'date', champValeur: 'quantite', ref: auj);
        final sorties = parMois([
          for (final x in m)
            if (x['type'] == 'sortie') x
        ], 'date', champValeur: 'quantite', ref: auj);
        final pertes = parMois([
          for (final x in m)
            if (typesPerte.contains(x['type'])) x
        ], 'date', champValeur: 'quantite', ref: auj);

        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (notes.isNotEmpty) ...[
                LayoutBuilder(builder: (_, k) {
                  final lg =
                      k.maxWidth >= 640 ? (k.maxWidth - 8) / 2 : k.maxWidth;
                  return Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final n in notes) SizedBox(width: lg, child: n)
                  ]);
                }),
                const SizedBox(height: 20),
              ],
              SectionSigh(
                titre: 'Accès rapides',
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: RaccourcisSigh(aller: c.aller, items: const [
                    RaccourciDef(
                        id: 'm6-inventaire',
                        icone: LucideIcons.clipboardCheck,
                        libelle: 'Inventaire',
                        detail: 'Physique contre théorique'),
                    RaccourciDef(
                        id: 'm6-transferts',
                        icone: LucideIcons.arrowLeftRight,
                        libelle: 'Transferts',
                        detail: 'Gros vers détail'),
                    RaccourciDef(
                        id: 'm6-lots',
                        icone: LucideIcons.calendarX,
                        libelle: 'Lots & péremptions',
                        detail: 'Principe FEFO'),
                    RaccourciDef(
                        id: 'm7-besoins',
                        icone: LucideIcons.clipboardList,
                        libelle: 'Expression de besoins',
                        detail: 'Demande interne'),
                  ]),
                ),
              ),
              const SizedBox(height: 20),
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Valeur totale du stock',
                    valeur: money(valeurStock(p)),
                    icone: LucideIcons.wallet,
                    indice: 'Valorisation au CUMP'),
                KpiSigh(
                    libelle: 'Références gérées',
                    valeur: nombre(p.length),
                    icone: LucideIcons.package,
                    ton: TonSigh.info),
                KpiSigh(
                    libelle: 'Produits critiques',
                    valeur: nombre(critiques),
                    icone: LucideIcons.trendingDown,
                    ton: TonSigh.danger),
                KpiSigh(
                    libelle: 'Produits périmés',
                    valeur: nombre(perimes),
                    icone: LucideIcons.calendarX,
                    ton: TonSigh.danger),
                KpiSigh(
                    libelle: 'Valeur stock gros',
                    valeur: money(valeurStock(p, 'stockGros')),
                    icone: LucideIcons.warehouse,
                    ton: TonSigh.neutre),
                KpiSigh(
                    libelle: 'Valeur stock détail',
                    valeur: money(valeurStock(p, 'stockDetail')),
                    icone: LucideIcons.pill,
                    ton: TonSigh.neutre),
                KpiSigh(
                    libelle: 'Mouvements du mois',
                    valeur: nombre(mouvementsDuMois(m, auj)),
                    icone: LucideIcons.arrowLeftRight,
                    ton: TonSigh.succes),
                KpiSigh(
                    libelle: 'Péremption sous $delaiPreavisPeremption j',
                    valeur: nombre(proches),
                    icone: LucideIcons.clock,
                    ton: TonSigh.attention,
                    indice: 'Application du FEFO'),
              ]),
              const SizedBox(height: 20),
              deux(
                CarteSigh(
                    titre: 'Valeur du stock par catégorie',
                    child: GraphiqueBarres(
                        horizontal: true,
                        hauteur: 320,
                        etiquettes: [
                          for (final k in parCategorie.keys) libelleCategorie(k)
                        ],
                        series: [
                          SerieGraphique('Valeur (FCFA)', [
                            for (final g in parCategorie.values) valeurStock(g)
                          ])
                        ])),
                CarteSigh(
                    titre: 'Répartition gros / détail',
                    child: GraphiqueAnneau(etiquettes: const [
                      'Stock gros (magasin)',
                      'Stock détail (pharmacie)'
                    ], valeurs: [
                      valeurStock(p, 'stockGros'),
                      valeurStock(p, 'stockDetail')
                    ])),
              ),
              const SizedBox(height: 16),
              deux(
                CarteSigh(
                    titre: 'Mouvements de stock (12 mois)',
                    child: GraphiqueBarres(
                        etiquettes: entrees.etiquettes,
                        series: [
                          SerieGraphique('Entrées', entrees.valeurs,
                              couleur: JetonsShell.success500),
                          SerieGraphique('Sorties', sorties.valeurs,
                              couleur: JetonsShell.navy900),
                          SerieGraphique('Pertes', pertes.valeurs,
                              couleur: JetonsShell.danger500),
                        ])),
                CarteSigh(
                    titre: 'État des péremptions',
                    child: GraphiqueAnneau(etiquettes: const [
                      'Périmés',
                      'Sous 90 jours',
                      'Au-delà de 90 jours'
                    ], valeurs: [
                      perimes,
                      proches,
                      l.length - perimes - proches
                    ], couleurs: const [
                      JetonsShell.danger500,
                      JetonsShell.warning500,
                      JetonsShell.success500
                    ])),
              ),
              const SizedBox(height: 20),
              SectionSigh(
                titre: 'Produits à réapprovisionner en priorité',
                actions: [
                  lienVers('Toutes les alertes', () => c.aller('m6-alertes'))
                ],
                child: prioritaires.isEmpty
                    ? const VideSigh('Aucun produit sous le seuil d’alerte.',
                        icone: LucideIcons.circleCheck)
                    : MiniTableauSigh(colonnes: [
                        ColonneMini('Code', (x) => '${x['code'] ?? ''}',
                            rendu: (x) => Text('${x['code'] ?? ''}',
                                style: const TextStyle(
                                    fontFamily: 'LiberationMono',
                                    fontSize: 12))),
                        ColonneMini(
                            'Désignation', (x) => '${x['designation'] ?? ''}'),
                        ColonneMini('Catégorie',
                            (x) => libelleCategorie(x['categorie'])),
                        ColonneMini('Stock', (x) => nombre(x['stock']),
                            droite: true),
                        ColonneMini(
                            'Seuil',
                            (x) => seuilFixe(x['seuilAlerte'])
                                ? '${x['seuilAlerte']}'
                                : '—',
                            droite: true),
                        ColonneMini(
                            'Emplacement', (x) => '${x['emplacement'] ?? ''}'),
                        ColonneMini('État', (x) => '',
                            rendu: (x) => badgeEtat(
                                etatStock(x['stock'], x['seuilAlerte']))),
                      ], lignes: prioritaires),
              ),
            ]);
      },
    );
  }
}
