import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/points_commun.dart' show champUnique, commande;
import 'cpb_commun.dart';

/// `m12-seuil-rentabilite` — « Seuil de rentabilité ». Le seuil repose sur UNE distinction : les charges qui suivent l'activité et celles qui tombent
/// qu'on travaille ou non. Cette répartition est un JUGEMENT de gestion, pas une donnée du plan comptable : elle est PROPOSÉE (`cpbNatureChargeReferentiel`),
/// affichée compte par compte et corrigeable d'un clic — la correction vit au magasin (collection `reglages`, fiche `naturesCharges`, comme
/// `S.reglage('naturesCharges')` de la maquette) et survit au rechargement. Un seuil incalculable est un DIAGNOSTIC, pas un défaut d'affichage.
///
/// Écart E771 : la maquette range la correction dans `_reglages` du magasin SANS la journaliser ; le poste l'écrit dans la collection `reglages`, donc
/// RG-12 la journalise (qui, quand, avant/après). « Basculer » est ABSENT sans le droit d'écrire (la maquette consulte `K.droits('M12').editer`).
class EcranSeuilRentabilite extends StatefulWidget with EcranMaquette {
  const EcranSeuilRentabilite({super.key});

  @override
  String get titre => 'Seuil de rentabilité';

  @override
  String get description => 'Charges fixes et variables, marge sur coût variable, seuil, point mort et marge de sécurité.';

  @override
  String get regle =>
      'Le seuil repose sur une distinction et une seule : les charges qui suivent l’activité et celles qui tombent qu’on travaille ou non. Cette répartition est un jugement de gestion, pas une donnée du plan comptable : elle est proposée, affichée et corrigeable compte par compte. La cacher donnerait un seuil qui a l’air d’un fait alors qu’il dépend d’un choix.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(
          libelle: 'Compte de résultat',
          icone: LucideIcons.chartNoAxesCombined,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m12-compte-resultat')),
    ];
  }

  @override
  State<EcranSeuilRentabilite> createState() => _EtatSeuil();
}

class _EtatSeuil extends State<EcranSeuilRentabilite> {
  ControleurFormulaire? _periode, _arrete;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_periode != null) return;
    final c = ContexteEcran.of(context);
    _periode = champUnique(
        ChampDef(
            nom: 'periode',
            libelle: 'Période',
            type: TypeChamp.select,
            col: ColChamp.plein,
            requis: true,
            options: [for (final p in periodes) OptionChamp(p.id, p.label)]),
        'annee');
    _arrete = champUnique(ChampDef(nom: 'arrete', libelle: 'Arrêté au', type: TypeChamp.date, col: ColChamp.plein), iso(c.aujourdhui));
    _periode!.addListener(_rafraichir);
    _arrete!.addListener(_rafraichir);
  }

  void _rafraichir() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _periode?.removeListener(_rafraichir);
    _arrete?.removeListener(_rafraichir);
    _periode?.dispose();
    _arrete?.dispose();
    super.dispose();
  }

  /// `S.reglage('naturesCharges', {})` : les natures CORRIGÉES par la clinique (compte → `fixe` / `variable`).
  static Map<String, String> naturesCorrigees(ContexteEcran c) {
    final f = c.magasin.collection('reglages').parId('naturesCharges');
    final v = f?['valeur'];
    return v is Map ? {for (final e in v.entries) '${e.key}': '${e.value}'} : <String, String>{};
  }

  /// `corrigerNature(num, nature)` : la décision est écrite au magasin (partagée, elle survit au rechargement).
  static void corrigerNature(ContexteEcran c, String compte, String nature) {
    final corr = naturesCorrigees(c)..[compte] = nature;
    final col = c.magasin.collection('reglages');
    if (col.parId('naturesCharges') == null) {
      col.inserer({'id': 'naturesCharges', 'valeur': corr});
    } else {
      col.mettreAJour('naturesCharges', {'valeur': corr});
    }
  }

  Bornes _bornes(ContexteEcran c) {
    final d = DateTime.tryParse('${_arrete!['arrete'] ?? ''}') ?? c.aujourdhui;
    return bornes('${_periode!['periode']}', DateTime(d.year, d.month, d.day));
  }

  CpbSeuil _calcul(ContexteEcran c) => cpbSeuilRentabilite(ecrituresToutes(c), _bornes(c),
      natures: naturesCorrigees(c), libelleCompte: cpaCompteLibelle);

  void _imprimer(BuildContext ctx, ContexteEcran c) {
    final r = _calcul(c);
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'Seuil de rentabilité',
            sousTitre: libellePeriode(r.bornes),
            cartouche: [
              ('Période', libellePeriode(r.bornes)),
              ('Chiffre d’affaires', money(r.ca)),
              ('Charges variables', money(r.variable)),
              ('Charges fixes', money(r.fixe)),
              ('Marge sur coût variable', money(r.marge)),
              ('Taux de marge', pourcent(r.taux * 100)),
              ('Seuil de rentabilité', r.seuil != null ? money(r.seuil) : 'incalculable'),
              ('Point mort', r.pointMort != null ? dateFR(r.pointMort!) : 'non atteint sur la période'),
            ],
            blocs: [
              const BlocTexte('Méthode', gras: true),
              const BlocTexte(
                  'Marge sur coût variable = chiffre d’affaires − charges variables. Seuil de rentabilité = charges fixes ÷ taux de marge. Marge de sécurité = chiffre d’affaires − seuil : c’est ce que la clinique peut perdre avant de perdre de l’argent.'),
              const BlocTexte('Réserve', gras: true),
              const BlocTexte(
                  'La répartition fixe / variable est une proposition de gestion, non une donnée du plan comptable. Le seuil suppose en outre la structure constante : il vaut pour un niveau d’activité voisin de l’actuel.'),
              const BlocTexte('Détail des charges', gras: true),
              BlocTableau(TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Compte', valeur: (x) => x['compte']),
                ColonneEtat(libelle: 'Intitulé', valeur: (x) => x['libelle']),
                ColonneEtat(libelle: 'Nature', valeur: (x) => x['nature'] == 'variable' ? 'Variable' : 'Fixe'),
                ColonneEtat(libelle: 'Montant', droite: true, valeur: (x) => money(x['montant'], avecDevise: false), somme: (x) => nombreOuZero(x['montant'])),
              ], lignes: [
                for (final x in r.comptes) {'compte': x.compte, 'libelle': x.libelle, 'nature': x.nature, 'montant': x.montant}
              ])),
            ],
            signatures: const [Signature('Le Comptable'), signDafFinances]));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: ecouteCompta(c, const ['reglages']),
      builder: (context, _) {
        final r = _calcul(c);
        final editer = c.droit.editer;
        final lignes = <Fiche>[
          for (final x in r.comptes) {'id': x.compte, 'compte': x.compte, 'libelle': x.libelle, 'nature': x.nature, 'montant': x.montant}
        ];
        final Widget verdict = r.seuil == null
            ? const NoteSigh(
                'Le seuil ne peut pas être calculé. La marge sur coût variable est nulle ou négative : chaque prestation vendue coûte plus qu’elle ne rapporte, et aucun volume d’activité ne couvrirait les charges fixes. Ce n’est pas un défaut d’affichage, c’est le diagnostic.',
                ton: TonSigh.danger,
                icone: LucideIcons.triangleAlert)
            : NoteSigh(
                '${money(r.seuil)} de chiffre d’affaires couvrent les charges. Au-delà, chaque franc encaissé rapporte ${pourcent(r.taux * 100)} de marge.${r.pointMort != null ? ' Point mort atteint le ${dateFR(r.pointMort!)} — en supposant l’activité régulière sur la période, ce qu’une clinique n’est jamais tout à fait.' : ' Le seuil n’est pas atteint sur la période retenue.'}\nLe seuil suppose la structure constante : il vaut pour un niveau d’activité voisin de l’actuel. L’extrapoler au double serait faux — il faudrait embaucher, et les charges fixes changeraient de palier.',
                ton: r.securite! >= 0 ? TonSigh.succes : TonSigh.danger,
                icone: LucideIcons.target);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CarteSigh(
              child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
            commande(_periode!, largeur: 220),
            commande(_arrete!, largeur: 200),
            BoutonSigh(libelle: 'Imprimer l’analyse', icone: LucideIcons.printer, onPressed: () => _imprimer(context, c)),
          ])),
          const SizedBox(height: 16),
          pile([
            const NoteSigh(
                'La répartition fixe / variable est une proposition. Aucun plan comptable ne la porte : elle relève de l’analyse de gestion. Elle est affichée compte par compte ci-dessous et se corrige d’un clic — le seuil se recalcule aussitôt.',
                ton: TonSigh.attention,
                icone: LucideIcons.triangleAlert),
            KpiGrilleSigh(kpis: [
              KpiSigh(libelle: 'Chiffre d’affaires', valeur: money(r.ca), icone: LucideIcons.trendingUp, ton: TonSigh.succes),
              KpiSigh(
                  libelle: 'Charges variables',
                  valeur: money(r.variable),
                  indice: r.ca != 0 ? '${pourcent(r.variable / r.ca * 100)} du CA' : null,
                  icone: LucideIcons.activity,
                  ton: TonSigh.info),
              KpiSigh(libelle: 'Charges fixes', valeur: money(r.fixe), icone: LucideIcons.anchor, ton: TonSigh.attention),
              KpiSigh(
                  libelle: 'Marge sur coût variable',
                  valeur: money(r.marge),
                  indice: 'taux : ${pourcent(r.taux * 100)}',
                  icone: LucideIcons.scale,
                  ton: TonSigh.navy),
              KpiSigh(
                  libelle: 'Seuil de rentabilité',
                  valeur: r.seuil != null ? money(r.seuil) : 'incalculable',
                  indice: r.seuil == null ? 'marge sur coût variable nulle ou négative' : 'CA à atteindre',
                  icone: LucideIcons.target,
                  ton: TonSigh.navy),
              KpiSigh(
                  libelle: 'Marge de sécurité',
                  valeur: r.securite != null ? money(r.securite) : '—',
                  indice: r.securite != null && r.ca != 0 ? '${pourcent(r.securite! / r.ca * 100)} du CA' : null,
                  icone: r.securite != null && r.securite! >= 0 ? LucideIcons.shieldCheck : LucideIcons.shieldAlert,
                  ton: r.securite != null && r.securite! >= 0 ? TonSigh.succes : TonSigh.danger),
            ]),
            verdict,
            grilleCartes([
              CarteSigh(
                  titre: 'Couverture des charges par le chiffre d’affaires',
                  child: GraphiqueBarres(
                      horizontal: true,
                      hauteur: 240,
                      etiquettes: const ['Chiffre d’affaires', 'Charges variables', 'Charges fixes', 'Seuil de rentabilité'],
                      series: [
                        SerieGraphique('Montant', [r.ca, r.variable, r.fixe, r.seuil ?? 0], couleur: tonNavy),
                      ])),
            ]),
            TableauSigh(
              key: const ValueKey('seuil-natures'),
              titre: 'Nature des charges — proposition corrigeable',
              lignes: lignes,
              nomExport: 'nature-charges',
              taillePage: 20,
              filtres: const [
                FiltreTableau(nom: 'nature', libelle: 'Nature', options: [OptionChamp('fixe', 'Fixe'), OptionChamp('variable', 'Variable')]),
              ],
              colonnes: [
                ColonneTableau(
                    cle: 'compte',
                    libelle: 'Compte',
                    sansCoupure: true,
                    rendu: (_, x) => Text('${x['compte']}', style: mono)),
                const ColonneTableau(cle: 'libelle', libelle: 'Intitulé'),
                ColonneTableau(
                    cle: 'nature',
                    libelle: 'Nature retenue',
                    texte: (x) => x['nature'] == 'variable' ? 'Variable — suit l’activité' : 'Fixe — tombe de toute façon',
                    rendu: (_, x) => x['nature'] == 'variable'
                        ? const BadgeSigh('Variable — suit l’activité', ton: TonSigh.info)
                        : const BadgeSigh('Fixe — tombe de toute façon', ton: TonSigh.attention)),
                ColonneTableau(
                    cle: 'montant',
                    libelle: 'Montant',
                    droite: true,
                    texte: (x) => m(x['montant']),
                    rendu: (_, x) => Text(m(x['montant']),
                        style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]))),
              ],
              // Sans le droit d'écrire, la commande est ABSENTE (jamais grisée) : la matrice (M14) décide de cette ouverture.
              actionsLigne: !editer
                  ? null
                  : (ctx, x) {
                      final variable = x['nature'] == 'variable';
                      return [
                        BoutonIcone(
                            icone: LucideIcons.repeat,
                            libelle: 'Basculer en ${variable ? 'fixe' : 'variable'}',
                            onPressed: () {
                              corrigerNature(c, '${x['compte']}', variable ? 'fixe' : 'variable');
                              ToastsSigh.afficher(ctx, 'Nature corrigée.',
                                  type: TypeToast.succes,
                                  detail: '${x['compte']} — ${variable ? 'désormais fixe' : 'désormais variable'}. Le seuil est recalculé.');
                            }),
                      ];
                    },
            ),
            if (!editer)
              const NoteSigh(
                  'Votre profil consulte l’analyse sans corriger la nature des charges. La matrice des droits (M14) décide de cette ouverture.',
                  ton: TonSigh.neutre,
                  icone: LucideIcons.lock),
          ]),
        ]);
      },
    );
  }
}
