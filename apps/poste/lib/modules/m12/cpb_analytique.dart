import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cpb_commun.dart';

/// `m12-analytique` — « Comptabilité analytique » : écran en LECTURE SEULE. La ventilation analytique est DÉDUITE du centre de coûts porté par chaque écriture
/// de l'exercice (charges = débits de classe 6, produits = crédits de classe 7) ; elle se corrige en modifiant l'écriture. Les règles sont dans le domaine
/// (`cpbAnalytique`, rejouée sur les vecteurs de la maquette).
///
/// Écart E776 : les centres sont ceux du référentiel STATIQUE `D.CENTRES_COUT` (six secteurs + Direction), non ceux de la collection administrable
/// `centresCouts` : un centre créé à l'écran n'y figure pas — porté fidèlement et dit.
class EcranAnalytique extends StatelessWidget with EcranMaquette {
  const EcranAnalytique({super.key});

  @override
  String get titre => 'Comptabilité analytique';

  @override
  String get description => 'Charges et produits ventilés par centre de coûts et par secteur d’activité.';

  @override
  String get regle =>
      'Écran en lecture seule. La ventilation analytique est déduite du centre de coûts porté par chaque écriture. Elle se corrige en modifiant l’écriture.';

  static Fiche _fiche(CpbLigneAnalytique r) => {
        'id': r.id,
        'centre': r.centre,
        'nb': r.nb,
        'produits': r.produits,
        'charges': r.charges,
        'resultat': r.resultat,
        'marge': r.marge,
      };

  static void _imprimer(BuildContext ctx, ContexteEcran c, List<CpbLigneAnalytique> rows) {
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'Balance analytique',
            sousTitre: 'Résultat par centre de coûts — exercice ${exerciceChoisi(c)}',
            cartouche: [
              ('Centres de coûts', nombre(rows.length)),
              ('Produits', money(rows.fold<double>(0, (a, r) => a + r.produits))),
              ('Charges', money(rows.fold<double>(0, (a, r) => a + r.charges))),
              ('Résultat', money(rows.fold<double>(0, (a, r) => a + r.resultat))),
            ],
            tableaux: [
              TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Centre de coûts', valeur: (x) => x['centre']),
                ColonneEtat(libelle: 'Écritures', droite: true, valeur: (x) => x['nb']),
                ColonneEtat(libelle: 'Produits', droite: true, valeur: (x) => m(x['produits']), somme: (x) => n(x['produits'])),
                ColonneEtat(libelle: 'Charges', droite: true, valeur: (x) => m(x['charges']), somme: (x) => n(x['charges'])),
                ColonneEtat(libelle: 'Résultat', droite: true, valeur: (x) => m(x['resultat']), somme: (x) => n(x['resultat'])),
              ], lignes: [for (final r in rows) _fiche(r)])
            ],
            signatures: const [signComptable, Signature('La Direction', nom: 'BASSONGUI Chabi Séko')]));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: ecouteCompta(c),
      builder: (context, _) {
        final rows = cpbAnalytique(ecrituresExercice(c));
        final tot = rows.fold<double>(0, (a, r) => a + r.resultat);
        final tri = trierPar([...rows], (r) => r.resultat, descendant: true);
        final avec = rows.where((r) => r.produits > 0).toList();
        return pile([
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Centres de coûts', valeur: nombre(rows.length), icone: LucideIcons.layers, ton: TonSigh.navy),
            KpiSigh(
                libelle: 'Produits analysés',
                valeur: money(rows.fold<double>(0, (a, r) => a + r.produits)),
                icone: LucideIcons.trendingUp,
                ton: TonSigh.succes),
            KpiSigh(
                libelle: 'Charges analysées',
                valeur: money(rows.fold<double>(0, (a, r) => a + r.charges)),
                icone: LucideIcons.trendingDown,
                ton: TonSigh.attention),
            KpiSigh(libelle: 'Résultat analytique', valeur: money(tot), icone: LucideIcons.scale, ton: tot >= 0 ? TonSigh.succes : TonSigh.danger),
          ]),
          TableauSigh(
            key: const ValueKey('analytique'),
            titre: 'Résultat par centre de coûts',
            lignes: [for (final r in rows) _fiche(r)],
            nomExport: 'analytique',
            taillePage: 15,
            recherche: false,
            triInitial: 'resultat',
            sensInitial: 'desc',
            actions: [
              BoutonSigh(
                  libelle: 'Imprimer la balance analytique',
                  icone: LucideIcons.printer,
                  taille: TailleBouton.sm,
                  variante: VarianteBouton.secondaire,
                  onPressed: () => _imprimer(context, c, rows)),
            ],
            colonnes: [
              const ColonneTableau(cle: 'centre', libelle: 'Centre de coûts / secteur'),
              const ColonneTableau(cle: 'nb', libelle: 'Écritures', droite: true),
              ColonneTableau(
                  cle: 'produits',
                  libelle: 'Produits',
                  droite: true,
                  texte: (r) => m(r['produits']),
                  rendu: (_, r) => Text(m(r['produits']), style: _style(JetonsShell.success700))),
              ColonneTableau(
                  cle: 'charges',
                  libelle: 'Charges',
                  droite: true,
                  texte: (r) => m(r['charges']),
                  rendu: (_, r) => Text(m(r['charges']), style: _style(JetonsShell.danger600))),
              ColonneTableau(
                  cle: 'resultat',
                  libelle: 'Résultat',
                  droite: true,
                  texte: (r) => m(r['resultat']),
                  rendu: (_, r) => Text(m(r['resultat']),
                      style: _style(n(r['resultat']) >= 0 ? JetonsShell.success700 : JetonsShell.danger600, gras: true))),
              ColonneTableau(
                  cle: 'marge',
                  libelle: 'Marge',
                  droite: true,
                  texte: (r) => n(r['produits']) != 0 ? '${r['marge']} %' : '—',
                  rendu: (_, r) => n(r['produits']) != 0
                      ? BadgeSigh('${r['marge']} %', ton: n(r['marge']) >= 0 ? TonSigh.succes : TonSigh.danger)
                      : const Text('—', style: TextStyle(color: JetonsShell.slate400, fontSize: 14, height: 20 / 14))),
            ],
          ),
          grilleCartes([
            CarteSigh(
                titre: 'Résultat par centre de coûts',
                child: GraphiqueBarres(horizontal: true, hauteur: 340, etiquettes: [
                  for (final r in tri) r.centre
                ], series: [
                  SerieGraphique('Produits', [for (final r in tri) r.produits], couleur: tonVert),
                  SerieGraphique('Charges', [for (final r in tri) r.charges], couleur: tonRouge),
                ])),
            CarteSigh(
                titre: 'Poids des secteurs dans les produits',
                child: GraphiqueAnneau(etiquettes: [for (final r in avec) r.centre], valeurs: [for (final r in avec) r.produits])),
          ]),
        ]);
      },
    );
  }

  static TextStyle _style(Color c, {bool gras = false}) => TextStyle(
      color: c, fontSize: 14, height: 20 / 14, fontWeight: gras ? FontWeight.w700 : FontWeight.w400, fontFeatures: const [FontFeature.tabularFigures()]);
}
