import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/stock_commun.dart' show cellule;

/// `m5-reactifs-stats` — « Statistiques des réactifs » : état du stock de réactifs et consommables de laboratoire (valeur, seuils, péremptions) et
/// demandes par section. Les chiffres sont CALCULÉS depuis le stock, les lots et le registre des demandes — jamais fournis ; les sorties détaillées
/// vivent au module M6 (mouvements), cet écran lit l'ÉTAT. Écran en lecture seule : aucune commande d'écriture.
///
/// Les règles (références suivies, sous le seuil, sans seuil, lots en défaut, section d'une demande) sont dans `packages/domaine`
/// (`sang_regles.dart`), rejouées sur les vecteurs de la maquette.
class EcranStatsReactifs extends StatelessWidget with EcranMaquette {
  const EcranStatsReactifs({super.key});

  @override
  String get titre => 'Statistiques des réactifs';

  @override
  String get description =>
      'État du stock de réactifs et consommables de laboratoire : valeur, seuils, péremptions, demandes par section.';

  @override
  String get regle =>
      'Les chiffres sont calculés depuis le stock, les lots et le registre des demandes — jamais fournis. Les sorties de stock détaillées vivent au module M6 (mouvements) : cet écran lit l’état, M6 tient le flux.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    final colProduits = m.collection('produits');
    final colLots = m.collection('lots');
    final colDemandes = m.collection('demandesAnalyses');
    final colExamens = m.collection('examensLabo');
    return ListenableBuilder(
      listenable:
          Listenable.merge([colProduits, colLots, colDemandes, colExamens]),
      builder: (context, _) {
        final st = sangStatsReactifs(
            produits: colProduits.actives,
            lots: colLots.actives,
            demandes: colDemandes.actives,
            examens: colExamens.actives);
        final sans = st.sansSeuil.length;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Références suivies',
                    valeur: nombre(st.references.length),
                    icone: LucideIcons.testTubes,
                    ton: TonSigh.navy,
                    indice: 'Réactifs et consommables de laboratoire'),
                KpiSigh(
                    libelle: 'Valeur du stock',
                    valeur: money(st.valeur),
                    icone: LucideIcons.wallet,
                    ton: TonSigh.info),
                KpiSigh(
                    libelle: 'Sous le seuil d’alerte',
                    valeur: nombre(st.sousSeuil.length),
                    icone: LucideIcons.triangleAlert,
                    ton: st.sousSeuil.isNotEmpty
                        ? TonSigh.danger
                        : TonSigh.neutre,
                    indice: sans > 0
                        ? '${nombre(sans)} référence(s) sans seuil fixé'
                        : null),
                KpiSigh(
                    libelle: 'Lots périmés / en alerte',
                    valeur: '${nombre(st.perimes)} / ${nombre(st.alerte)}',
                    icone: LucideIcons.calendarX,
                    ton: (st.perimes > 0 || st.alerte > 0)
                        ? TonSigh.attention
                        : TonSigh.neutre,
                    indice: 'Alerte : péremption sous 90 jours'),
              ]),
              if (sans > 0) ...[
                const SizedBox(height: 16),
                NoteSigh(
                    '${nombre(sans)} référence(s) sans seuil d’alerte. Sans seuil, aucune alerte n’est possible : le seuil se fixe référence par référence à l’écran « Réactifs & consommables » — le document SAGE ne renseigne pas cette colonne.',
                    ton: TonSigh.attention,
                    icone: LucideIcons.triangleAlert),
              ],
              const SizedBox(height: 16),
              CarteSigh(
                  titre:
                      'Demandes d’analyses par section — activité qui consomme les réactifs',
                  child: GraphiqueBarres(
                    horizontal: true,
                    hauteur: 260,
                    etiquettes: [for (final s in st.parSection) s.section],
                    series: [
                      SerieGraphique(
                          'Demandes', [for (final s in st.parSection) s.demandes])
                    ],
                  )),
              const SizedBox(height: 16),
              TableauSigh(
                titre: 'Références de laboratoire — état du stock',
                lignes: st.references,
                taillePage: 15,
                nomExport: 'reactifs-stats',
                triInitial: 'stock',
                colonnes: [
                  const ColonneTableau(cle: 'designation', libelle: 'Désignation'),
                  ColonneTableau(
                      cle: 'categorie',
                      libelle: 'Catégorie',
                      texte: (p) => p['categorie'] == 'reactif'
                          ? 'Réactif'
                          : 'Consommable labo',
                      rendu: (_, p) => p['categorie'] == 'reactif'
                          ? const BadgeSigh('Réactif', ton: TonSigh.info)
                          : const BadgeSigh('Consommable labo')),
                  ColonneTableau(
                      cle: 'stock',
                      libelle: 'Stock',
                      droite: true,
                      valeur: (p) => nombreOuZero(p['stock']),
                      texte: (p) => nombre(nombreOuZero(p['stock'])),
                      rendu: (_, p) =>
                          cellule(nombre(nombreOuZero(p['stock'])), droite: true)),
                  ColonneTableau(
                      cle: 'seuilAlerte',
                      libelle: 'Seuil',
                      droite: true,
                      texte: (p) =>
                          p['seuilAlerte'] == null ? 'non fixé' : '${p['seuilAlerte']}',
                      rendu: (_, p) {
                        if (p['seuilAlerte'] == null) {
                          return const Text('non fixé',
                              style: TextStyle(
                                  color: JetonsShell.warning700,
                                  fontSize: 12,
                                  height: 16 / 12));
                        }
                        final bas = sangSousSeuil(p);
                        return cellule('${p['seuilAlerte']}',
                            droite: true,
                            couleur: bas
                                ? JetonsShell.danger700
                                : JetonsShell.slate700,
                            poids: bas ? FontWeight.w600 : FontWeight.w400);
                      }),
                  ColonneTableau(
                      cle: 'valeur',
                      libelle: 'Valeur (P.A.)',
                      droite: true,
                      valeur: sangValeurReference,
                      texte: (p) =>
                          money(sangValeurReference(p), avecDevise: false),
                      rendu: (_, p) => cellule(
                          money(sangValeurReference(p), avecDevise: false),
                          droite: true)),
                ],
              ),
            ]);
      },
    );
  }
}
