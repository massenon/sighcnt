import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'stock_commun.dart';

/// `m6-alertes` — « Alertes & seuils » : ruptures, stocks sous le seuil, péremptions. Écran en LECTURE SEULE, recalculé à chaque affichage depuis les
/// stocks, les seuils et les dates de péremption.
///
/// L'alerte SIGNALE, le circuit COMMANDE (décision du 02/09/2026) : l'écran n'établit plus de bon de commande, il renvoie aux bons de besoins de M7
/// (validation de la DA, RG-04). Un seuil non fixé n'est PAS un seuil de zéro : l'article est signalé à part (écart E18).
class EcranAlertesStock extends StatelessWidget with EcranMaquette {
  const EcranAlertesStock({super.key});

  @override
  String get titre => 'Alertes & seuils';

  @override
  String get description =>
      'Centralisation des alertes de rupture, de seuil minimal et de péremption imminente.';

  @override
  String get regle =>
      'Écran en lecture seule. Les alertes sont recalculées en continu à partir des stocks, des seuils et des dates de péremption. Pour les faire évoluer, ajuster le seuil de l’article ou régulariser le stock.';

  Widget _tableProduits(BuildContext ctx, List<Fiche> rows, String titre,
      String vide, ContexteEcran c) {
    return TableauSigh(
      titre: titre,
      lignes: rows,
      taillePage: 15,
      nomExport: 'alertes-stock',
      messageVide: vide,
      colonnes: [
        colCode(),
        colDesignation(),
        colStock('stockGros', 'Gros'),
        colStock('stockDetail', 'Détail'),
        colStock('stock', 'Total'),
        colSeuil(),
        ColonneTableau(
            cle: 'aCommander',
            libelle: 'À commander',
            droite: true,
            valeur: (p) => aCommander(p['stock'], p['seuilAlerte']),
            texte: (p) {
              final q = aCommander(p['stock'], p['seuilAlerte']);
              return q == null ? '—' : nombre(q);
            },
            rendu: (_, p) {
              final q = aCommander(p['stock'], p['seuilAlerte']);
              // Sans seuil fixé, la quantité à commander n'est pas calculable : un tiret, pas un zéro.
              return q == null
                  ? cellule('—', droite: true)
                  : cellule(nombre(q),
                      couleur: JetonsShell.navy800,
                      poids: FontWeight.w600,
                      droite: true);
            }),
        const ColonneTableau(cle: 'fournisseur', libelle: 'Fournisseur'),
        colEtat(),
      ],
      // L'alerte SIGNALE, le circuit COMMANDE : bon d'expression de besoins → validation DA (RG-04) → bon de commande.
      actions: [
        BoutonSigh(
            libelle: 'Ouvrir les bons de besoins (M7)',
            taille: TailleBouton.sm,
            icone: LucideIcons.clipboardList,
            onPressed: () => c.aller('m7-besoins')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(
          [c.magasin.collection('produits'), c.magasin.collection('lots')]),
      builder: (context, _) {
        final auj = c.aujourdhui;
        final prods = produitsActifs(c.magasin);
        final lots = lotsActifs(c.magasin);
        final ruptures = [
          for (final p in prods)
            if (qte(p['stock']) == 0) p
        ];
        final critiques = [
          for (final p in prods)
            if (sousSeuilHorsRupture(p['stock'], p['seuilAlerte'])) p
        ];
        final perimes = [
          for (final l in lots)
            if (statutDuLot(l, auj) == 'perime') l
        ];
        final proches = [
          for (final l in lots)
            if (statutDuLot(l, auj) == 'alerte') l
        ];
        final peremptions =
            trierStable([...perimes, ...proches], (l) => l['datePeremption']);
        final sansSeuil = noteSansSeuil(prods);

        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Ruptures de stock',
                    valeur: nombre(ruptures.length),
                    icone: LucideIcons.circleX,
                    ton: TonSigh.danger),
                KpiSigh(
                    libelle: 'Sous le seuil d’alerte',
                    valeur: nombre(critiques.length),
                    icone: LucideIcons.trendingDown,
                    ton: TonSigh.attention),
                KpiSigh(
                    libelle: 'Lots périmés',
                    valeur: nombre(perimes.length),
                    icone: LucideIcons.calendarX,
                    ton: TonSigh.danger),
                KpiSigh(
                    libelle: 'Péremption sous $delaiPreavisPeremption j',
                    valeur: nombre(proches.length),
                    icone: LucideIcons.clock,
                    ton: TonSigh.attention),
              ]),
              if (sansSeuil != null) ...[
                const SizedBox(height: 16),
                sansSeuil,
              ],
              const SizedBox(height: 16),
              OngletsSigh(onglets: [
                OngletDef(
                    id: 'rupture',
                    libelle: 'Ruptures',
                    compte: ruptures.length,
                    construire: (ctx) => _tableProduits(
                        ctx,
                        ruptures,
                        'Produits en rupture de stock',
                        'Aucune rupture de stock.',
                        c)),
                OngletDef(
                    id: 'seuil',
                    libelle: 'Sous le seuil',
                    compte: critiques.length,
                    construire: (ctx) => _tableProduits(
                        ctx,
                        critiques,
                        'Produits sous le seuil d’alerte',
                        'Aucun produit sous le seuil.',
                        c)),
                OngletDef(
                    id: 'peremption',
                    libelle: 'Péremptions',
                    compte: perimes.length + proches.length,
                    construire: (ctx) => TableauSigh(
                          titre: 'Lots périmés ou à péremption proche',
                          lignes: peremptions,
                          taillePage: 15,
                          nomExport: 'alertes-peremption',
                          messageVide: 'Aucune alerte de péremption.',
                          colonnes: [
                            const ColonneTableau(
                                cle: 'produit', libelle: 'Produit'),
                            ColonneTableau(
                                cle: 'numeroLot',
                                libelle: 'N° lot',
                                texte: (l) => '${l['numeroLot'] ?? ''}',
                                rendu: (_, l) => Text('${l['numeroLot'] ?? ''}',
                                    style: typographieMono)),
                            ColonneTableau(
                                cle: 'datePeremption',
                                libelle: 'Péremption',
                                sansCoupure: true,
                                texte: (l) => dateFiche(l['datePeremption']),
                                valeur: (l) => l['datePeremption']),
                            ColonneTableau(
                                cle: 'restant',
                                libelle: 'Échéance',
                                droite: true,
                                valeur: (l) => joursAvantPeremption(
                                    auj, l['datePeremption']),
                                texte: (l) => texteEcheanceAlerte(
                                    joursAvantPeremption(
                                        auj, l['datePeremption'])),
                                rendu: (_, l) {
                                  final j = joursAvantPeremption(
                                      auj, l['datePeremption']);
                                  return BadgeSigh(texteEcheanceAlerte(j),
                                      ton: j != null && (j < 0 || j <= 30)
                                          ? TonSigh.danger
                                          : TonSigh.attention);
                                }),
                            ColonneTableau(
                                cle: 'quantiteRestante',
                                libelle: 'Quantité',
                                droite: true,
                                texte: (l) => '${l['quantiteRestante'] ?? ''}'),
                            const ColonneTableau(
                                cle: 'emplacement', libelle: 'Emplacement'),
                          ],
                        )),
              ]),
              const SizedBox(height: 16),
              const NoteSigh(
                  'Le seuil d’alerte est paramétrable par article dans le référentiel produits. Le délai de préavis de péremption est de $delaiPreavisPeremption jours et se règle dans la configuration du module (RG-05).'),
            ]);
      },
    );
  }
}
