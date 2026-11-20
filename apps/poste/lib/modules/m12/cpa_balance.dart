import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/points_commun.dart' show champUnique, commande;
import 'cpa_commun.dart';

/// `m12-balance` — « Balance générale & âgée » : écran en LECTURE SEULE. La balance est calculée depuis les écritures de l'exercice (une ligne par
/// numéro de compte, E725) ; elle ne se saisit pas — on corrige l'écriture concernée.
///
/// E718 levé : le filtre « Écritures retenues » est EXPLICITE (validées seulement par défaut, ou toutes, brouillons compris) et le bandeau dit ce qui est
/// compté, au lieu d'annoncer des écritures validées tout en comptant les brouillons.
class EcranBalance extends StatefulWidget with EcranMaquette {
  const EcranBalance({super.key});

  @override
  State<EcranBalance> createState() => _EtatBalance();

  @override
  String get titre => 'Balance générale & âgée';

  @override
  String get description =>
      'Balance des comptes, contrôle d’équilibre et balance âgée des comptes de tiers.';

  @override
  String get regle =>
      'Écran en lecture seule. La balance est calculée à partir des écritures validées par défaut ; le filtre « Écritures retenues » permet d’y compter aussi les brouillons, et le bandeau dit ce qui est compté. Elle ne se saisit pas : corriger l’écriture concernée pour la faire évoluer.';

  static void _imprimerBalance(BuildContext ctx, ContexteEcran c, List<CpaLigneBalance> l, double td, double tc, bool toutes) {
    final eq = td == tc;
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'Balance générale des comptes',
            sousTitre: 'Exercice ${exerciceChoisi(c)} — situation au ${dateFR(c.aujourdhui)}',
            cartouche: [
              ('Comptes mouvementés', nombre(l.length)),
              ('Total débit', money(td)),
              ('Total crédit', money(tc)),
              ('Équilibre', eq ? 'Équilibrée' : 'Écart de ${money((td - tc).abs())}'),
              ('Exercice', '${exerciceChoisi(c)}'),
              ('Écritures retenues', toutes ? 'Toutes, brouillons compris' : 'Validées seulement'),
              ('Date d’édition', dateFR(c.aujourdhui)),
            ],
            tableaux: [
              TableauEtat(libelleTotal: 'TOTAUX', colonnes: [
                ColonneEtat(libelle: 'Compte', valeur: (x) => x['num']),
                ColonneEtat(libelle: 'Intitulé', valeur: (x) => x['libelle']),
                ColonneEtat(libelle: 'Mvt débit', droite: true, valeur: (x) => m(x['debit']), somme: (x) => n(x['debit'])),
                ColonneEtat(libelle: 'Mvt crédit', droite: true, valeur: (x) => m(x['credit']), somme: (x) => n(x['credit'])),
                ColonneEtat(
                    libelle: 'Solde débiteur',
                    droite: true,
                    valeur: (x) => n(x['soldeDebiteur']) != 0 ? m(x['soldeDebiteur']) : '',
                    somme: (x) => n(x['soldeDebiteur'])),
                ColonneEtat(
                    libelle: 'Solde créditeur',
                    droite: true,
                    valeur: (x) => n(x['soldeCrediteur']) != 0 ? m(x['soldeCrediteur']) : '',
                    somme: (x) => n(x['soldeCrediteur'])),
              ], lignes: trierPar([for (final x in l) _fiche(x)], (x) => x['num']))
            ],
            signatures: [signComptable, signDafCompta]));
  }

  static Fiche _fiche(CpaLigneBalance l) => {
        'id': l.num,
        'num': l.num,
        'libelle': l.libelle,
        'classe': l.classe,
        'debit': l.debit,
        'credit': l.credit,
        'soldeDebiteur': l.soldeDebiteur,
        'soldeCrediteur': l.soldeCrediteur,
        'nb': l.nb,
      };

  static Widget _solde(Object? v) => n(v) != 0
      ? Text(m(v),
          style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]))
      : const Text('—', style: TextStyle(color: JetonsShell.slate400, fontSize: 14, height: 20 / 14));

}

class _EtatBalance extends State<EcranBalance> {
  late final ControleurFormulaire _mode = champUnique(
      const ChampDef(
          nom: 'ecritures',
          libelle: 'Écritures retenues',
          type: TypeChamp.select,
          options: [OptionChamp('validees', 'Validées seulement'), OptionChamp('toutes', 'Toutes (brouillons compris)')]),
      'validees')
    ..addListener(() {
      if (mounted) setState(() {});
    });

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: ecouteCompta(c, const ['factures']),
      builder: (context, _) {
        final tous = ecrituresExercice(c);
        final toutes = '${_mode['ecritures']}' == 'toutes';
        final e = toutes ? tous : [for (final x in tous) if (x['statut'] == 'validee') x];
        final nbBrouillons = tous.where((x) => x['statut'] == 'brouillon').length;
        final b = cpaBalance(c.magasin.collection('comptes').actives, e);
        final lignes = [for (final x in b) EcranBalance._fiche(x)];
        final td = b.fold<double>(0, (a, x) => a + x.debit);
        final tc = b.fold<double>(0, (a, x) => a + x.credit);
        final eq = td == tc;
        final tranches = cpaBalanceAgee(c.magasin.collection('factures').actives, c.aujourdhui);
        final agees = [
          for (final t in tranches)
            {
              'id': t.libelle,
              'tranche': t.libelle,
              'nbPatients': t.nbPatients,
              'montantPatients': t.montantPatients,
              'nbAssureurs': t.nbAssureurs,
              'montantAssureurs': t.montantAssureurs,
              'total': t.total,
            }
        ];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(alignment: Alignment.centerLeft, child: commande(_mode, largeur: 280)),
          const SizedBox(height: 12),
          toutes
              ? NoteSigh(
                  'Balance calculée sur toutes les écritures de l’exercice ${exerciceChoisi(c)}, brouillons compris (${nombre(nbBrouillons)} ligne(s) en brouillon). Un brouillon n’est pas un fait comptable : choisir « Validées seulement » pour la balance opposable.',
                  ton: TonSigh.attention,
                  icone: LucideIcons.fileClock)
              : NoteSigh(
                  'Balance calculée sur les écritures validées de l’exercice ${exerciceChoisi(c)}. ${nbBrouillons > 0 ? '${nombre(nbBrouillons)} ligne(s) en brouillon sont écartées.' : 'Aucun brouillon à écarter.'}',
                  ton: TonSigh.info,
                  icone: LucideIcons.scale),
          const SizedBox(height: 16),
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Comptes mouvementés', valeur: nombre(lignes.length), icone: LucideIcons.list),
            KpiSigh(libelle: 'Total débit', valeur: money(td), icone: LucideIcons.arrowDownLeft, ton: TonSigh.attention),
            KpiSigh(libelle: 'Total crédit', valeur: money(tc), icone: LucideIcons.arrowUpRight, ton: TonSigh.succes),
            KpiSigh(
                libelle: 'Équilibre (RG-10)',
                valeur: eq ? 'Équilibrée' : money((td - tc).abs()),
                icone: eq ? LucideIcons.scale : LucideIcons.scale3d,
                ton: eq ? TonSigh.succes : TonSigh.danger),
          ]),
          const SizedBox(height: 16),
          eq
              ? const NoteSigh(
                  'La balance est équilibrée : le total des débits est égal au total des crédits (RG-10).',
                  ton: TonSigh.succes,
                  icone: LucideIcons.scale)
              : NoteSigh(
                  'Balance déséquilibrée — écart de ${money((td - tc).abs())}. Ce contrôle doit être régularisé avant toute clôture (RG-10).',
                  ton: TonSigh.danger,
                  icone: LucideIcons.scale3d),
          const SizedBox(height: 16),
          OngletsSigh(onglets: [
            OngletDef(
                id: 'generale',
                libelle: 'Balance générale',
                construire: (ctx) => TableauSigh(
                      lignes: lignes,
                      nomExport: 'balance-generale',
                      taillePage: 25,
                      triInitial: 'num',
                      filtres: [
                        FiltreTableau(
                            nom: 'classe',
                            libelle: 'Classe',
                            options: [for (var k = 1; k <= 8; k++) OptionChamp('$k', cpaClasseLibelle(k))],
                            correspond: (l, v) => '${l['classe']}' == v),
                      ],
                      actions: [
                        BoutonSigh(
                            libelle: 'Imprimer la balance',
                            icone: LucideIcons.printer,
                            taille: TailleBouton.sm,
                            variante: VarianteBouton.secondaire,
                            onPressed: () => EcranBalance._imprimerBalance(context, c, b, td, tc, toutes)),
                      ],
                      colonnes: [
                        ColonneTableau(
                            cle: 'num',
                            libelle: 'Compte',
                            sansCoupure: true,
                            rendu: (_, l) => Text('${l['num']}', style: mono.copyWith(fontWeight: FontWeight.w600))),
                        const ColonneTableau(cle: 'libelle', libelle: 'Intitulé'),
                        ColonneTableau(
                            cle: 'classe',
                            libelle: 'Classe',
                            droite: true,
                            texte: (l) => 'C${l['classe']}',
                            rendu: (_, l) => BadgeSigh('C${l['classe']}')),
                        const ColonneTableau(cle: 'nb', libelle: 'Mvts', droite: true),
                        ColonneTableau(cle: 'debit', libelle: 'Mouvement débit', droite: true, texte: (l) => m(l['debit'])),
                        ColonneTableau(cle: 'credit', libelle: 'Mouvement crédit', droite: true, texte: (l) => m(l['credit'])),
                        ColonneTableau(
                            cle: 'soldeDebiteur',
                            libelle: 'Solde débiteur',
                            droite: true,
                            texte: (l) => n(l['soldeDebiteur']) != 0 ? m(l['soldeDebiteur']) : '',
                            rendu: (_, l) => EcranBalance._solde(l['soldeDebiteur'])),
                        ColonneTableau(
                            cle: 'soldeCrediteur',
                            libelle: 'Solde créditeur',
                            droite: true,
                            texte: (l) => n(l['soldeCrediteur']) != 0 ? m(l['soldeCrediteur']) : '',
                            rendu: (_, l) => EcranBalance._solde(l['soldeCrediteur'])),
                      ],
                    )),
            OngletDef(
                id: 'agee',
                libelle: 'Balance âgée (tiers)',
                construire: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const NoteSigh(
                          'La balance âgée ventile les créances par ancienneté afin de piloter le recouvrement auprès des patients et des tiers payeurs.'),
                      const SizedBox(height: 12),
                      TableauSigh(
                        lignes: agees,
                        nomExport: 'balance-agee',
                        recherche: false,
                        taillePage: 10,
                        actions: [
                          BoutonSigh(
                              libelle: 'Imprimer la balance âgée',
                              icone: LucideIcons.printer,
                              taille: TailleBouton.sm,
                              variante: VarianteBouton.secondaire,
                              onPressed: () => _imprimerAgee(context, c, tranches)),
                        ],
                        colonnes: [
                          const ColonneTableau(cle: 'tranche', libelle: 'Ancienneté'),
                          const ColonneTableau(cle: 'nbPatients', libelle: 'Factures patients', droite: true),
                          ColonneTableau(cle: 'montantPatients', libelle: 'Créances patients', droite: true, texte: (r) => m(r['montantPatients'])),
                          const ColonneTableau(cle: 'nbAssureurs', libelle: 'Factures assureurs', droite: true),
                          ColonneTableau(cle: 'montantAssureurs', libelle: 'Créances assureurs', droite: true, texte: (r) => m(r['montantAssureurs'])),
                          ColonneTableau(
                              cle: 'total',
                              libelle: 'Total',
                              droite: true,
                              texte: (r) => m(r['total']),
                              rendu: (_, r) => Text(m(r['total']),
                                  style: const TextStyle(color: JetonsShell.navy900, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]))),
                        ],
                      ),
                    ])),
          ]),
        ]);
      },
    );
  }

  static void _imprimerAgee(BuildContext ctx, ContexteEcran c, List<CpaTrancheAgee> t) {
    double som(double Function(CpaTrancheAgee) f) => t.fold<double>(0, (a, x) => a + f(x));
    // Les tranches d'ancienneté se totalisent : c'est la somme des créances que le lecteur vient chercher, et le tableau n'est ni tronqué ni hétérogène.
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'Balance âgée des comptes de tiers',
            sousTitre: 'Situation au ${dateFR(c.aujourdhui)}',
            cartouche: [
              ('Créances totales', money(som((x) => x.total))),
              ('Dont patients', money(som((x) => x.montantPatients))),
              ('Dont assureurs', money(som((x) => x.montantAssureurs))),
              ('Date d’édition', dateFR(c.aujourdhui)),
            ],
            tableaux: [
              TableauEtat(libelleTotal: 'TOTAL DES CRÉANCES', colonnes: [
                ColonneEtat(libelle: 'Ancienneté', valeur: (r) => r['tranche']),
                ColonneEtat(libelle: 'Factures patients', droite: true, valeur: (r) => r['nbPatients'], somme: (r) => n(r['nbPatients'])),
                ColonneEtat(libelle: 'Créances patients', droite: true, valeur: (r) => m(r['montantPatients']), somme: (r) => n(r['montantPatients'])),
                ColonneEtat(libelle: 'Factures assureurs', droite: true, valeur: (r) => r['nbAssureurs'], somme: (r) => n(r['nbAssureurs'])),
                ColonneEtat(libelle: 'Créances assureurs', droite: true, valeur: (r) => m(r['montantAssureurs']), somme: (r) => n(r['montantAssureurs'])),
                ColonneEtat(libelle: 'Total', droite: true, valeur: (r) => m(r['total']), somme: (r) => n(r['total'])),
              ], lignes: [
                for (final x in t)
                  {
                    'tranche': x.libelle,
                    'nbPatients': x.nbPatients,
                    'montantPatients': x.montantPatients,
                    'nbAssureurs': x.nbAssureurs,
                    'montantAssureurs': x.montantAssureurs,
                    'total': x.total
                  }
              ])
            ],
            signatures: [signComptable, signDafCompta]));
  }
}
