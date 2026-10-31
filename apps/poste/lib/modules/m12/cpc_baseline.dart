import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m13/qual_commun.dart' show sourceQual;
import 'cpc_commun.dart';

/// `m12-baseline-2025` — « Baseline financière 2025 » : le compte de résultat RÉEL de l'exercice précédent, référence de comparaison de l'exercice courant.
///
/// Le diagnostic des écarts du classeur est CALCULÉ à l'affichage, jamais écrit en dur : 141 667 FCFA n'est pas un arrondi, c'est l'échéance mensuelle que
/// la ligne TOTAL du classeur omet — la correction porte sur le document source, pas sur le logiciel. Les trois postes sans numéro de compte reçoivent un
/// rattachement PROPOSÉ, jamais appliqué. Les données du classeur sont ENGENDRÉES (`cpc_donnees.dart`) depuis `data-compta.js`.
///
/// Écarts : E803 (l'onglet « Comparaison 2025 / 2026 » lit l'année 2026 EN DUR, comme la maquette — le jeu du poste est de 2026) ; E805 (les libellés de mois
/// des graphiques sont les quatre premières lettres suivies d'un point — « mars. 25 », « avri. 25 » : porté fidèlement, cosmétique).
class EcranBaseline2025 extends StatelessWidget with EcranMaquette {
  const EcranBaseline2025({super.key});

  @override
  String get titre => 'Baseline financière 2025';

  @override
  String get description =>
      'Compte de résultat réel de l’exercice 2025, servant de référence de comparaison à l’exercice courant.';

  @override
  String get regle =>
      'Le compte de résultat 2025 n’est pas un simple archivage : il constitue la référence de comparaison des tableaux de bord (2025 réel / 2026 réel / budget 2026), conformément au principe de reprise des documents de cadrage.';

  @override
  List<Widget> actionsEntete(BuildContext context) => [
        BoutonSigh(
            libelle: 'Imprimer le compte de résultat 2025',
            icone: LucideIcons.printer,
            onPressed: () => _imprimer(context, ContexteEcran.of(context))),
      ];

  static const _vert = Color(0xFF22A170), _rouge = Color(0xFFEF4444), _navy = Color(0xFF12315E);

  static String _cap(String s) => '${s[0].toUpperCase()}${s.substring(1)}';

  static void _imprimer(BuildContext ctx, ContexteEcran c) {
    final e = cpcExercice2025;
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'Compte de résultat — exercice 2025',
            sousTitre: 'Baseline financière de référence',
            cartouche: [
              ('Exercice', '2025'),
              ('Chiffre d’affaires', money(e.totalChiffreAffaires)),
              ('Charges d’exploitation', money(e.totalCharges)),
              ('Résultat', money(e.resultat)),
              ('Hors exploitation', money(e.totalHorsExploitation)),
              ('Date d’édition', dateFR(c.aujourdhui)),
            ],
            blocs: [
              const BlocTexte('Chiffre d’affaires mensuel', gras: true),
              BlocTableau(TableauEtat(libelleTotal: 'TOTAL 2025', colonnes: [
                ColonneEtat(libelle: 'Mois', valeur: (l) => l['m']),
                ColonneEtat(libelle: 'Chiffre d’affaires', droite: true, valeur: (l) => m(l['ca']), somme: (l) => n(l['ca'])),
                ColonneEtat(libelle: 'Charges', droite: true, valeur: (l) => m(l['ch']), somme: (l) => n(l['ch'])),
                ColonneEtat(libelle: 'Résultat', droite: true, valeur: (l) => m(l['res']), somme: (l) => n(l['res'])),
              ], lignes: [
                for (var i = 0; i < 12; i++)
                  {
                    'm': _cap(e.mois[i]),
                    'ca': e.chiffreAffaires[i],
                    'ch': arrondiJs(e.chargesDuMois(i)),
                    'res': arrondiJs(e.resultatDuMois(i)),
                  }
              ])),
              const BlocTexte('Postes de charges', gras: true),
              BlocTableau(TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Compte', valeur: (p) => p['num'] ?? '(à rattacher)'),
                ColonneEtat(libelle: 'Libellé', valeur: (p) => p['libelle']),
                ColonneEtat(libelle: 'Total 2025', droite: true, valeur: (p) => m(p['total']), somme: (p) => n(p['total'])),
                ColonneEtat(libelle: 'Poids', droite: true, valeur: (p) => pourcent(n(p['total']) / e.totalCharges * 100)),
              ], lignes: [
                for (final p in e.postesCharges()) {'num': p.num, 'libelle': p.libelle, 'total': p.total}
              ])),
              const BlocTexte(
                  'Les postes « emprunt », « dépôts et cautionnements » et « matériel de bureau » figurant au classeur des dépenses constituent des mouvements de bilan et sont exclus des charges d’exploitation retenues ci-dessus.'),
            ],
            signatures: [
              signComptable,
              signDafCompta,
              const Signature('Le Directeur Médical', nom: 'BASSONGUI Chabi Séko'),
            ]));
  }

  Widget _controles(CpcExercice2025 e) {
    final ctrl = e.controle;
    if (ctrl.postesSansCompte == 0 && ctrl.ecart == 0) return const SizedBox.shrink();
    final enfants = <Widget>[];
    if (ctrl.ecart != 0) {
      final d = cpcExpliquerEcart(e);
      enfants.add(NoteSigh(
          'Écart de ${money(ctrl.ecart.abs())} entre la ligne « TOTAL » du classeur (${money(ctrl.totalClasseur)}) et la somme de son propre détail (${money(ctrl.totalDetail)}).',
          ton: TonSigh.danger,
          icone: LucideIcons.scale3d));
      if (d != null && d.incoherentes.isEmpty && d.mensuelles.isNotEmpty) {
        final l = d.mensuelles.first;
        final mois = l.mois.map((i) => e.mois[i]).join(' et ');
        enfants
          ..add(const SizedBox(height: 12))
          ..add(NoteSigh(
              'Diagnostic : l’écart n’est pas un arrondi. Les ${e.depenses.length} lignes du détail somment exactement à leur propre total — le détail est cohérent avec lui-même. Et le montant de l’écart, ${money(d.ecart)}, est précisément l’échéance mensuelle de la ligne « ${l.ligne.libelle} » ($mois). La ligne « TOTAL » du classeur omet une échéance ; c’est elle qui est fautive, non le détail.\n'
              'Conséquence retenue : la baseline s’appuie sur le détail, soit ${money(ctrl.totalDetail)}. Le service comptable est invité à corriger la formule de totalisation du classeur — la correction porte sur le document source, pas sur le logiciel.',
              icone: LucideIcons.searchCheck));
      } else if (d != null && d.incoherentes.isNotEmpty) {
        enfants
          ..add(const SizedBox(height: 12))
          ..add(NoteSigh(
              '${d.incoherentes.length} ligne(s) ne somment pas à leur propre total : l’écart vient du détail lui-même et non de la ligne TOTAL. À reprendre ligne par ligne avec le service comptable.',
              ton: TonSigh.attention,
              icone: LucideIcons.triangleAlert));
      }
    }
    if (ctrl.postesSansCompte != 0) {
      final sans = e.depenses.where((d) => d.num == null).toList();
      enfants
        ..add(const SizedBox(height: 12))
        ..add(NoteSigh(
            '${ctrl.postesSansCompte} poste(s) de dépense sans numéro de compte dans le classeur source, pour ${money(ctrl.montantSansCompte)}. Les trois relèvent du même emprunt bancaire. Un rattachement est proposé ci-dessous : c’est une proposition à valider par le service comptable, pas une imputation appliquée — rattacher d’office un montant à un compte fausserait la balance sans que personne ne l’ait décidé.',
            ton: TonSigh.attention,
            icone: LucideIcons.circleHelp))
        ..add(const SizedBox(height: 12))
        ..add(MiniTableauSigh(colonnes: [
          ColonneMini('Poste du classeur', (r) => '${r['poste']}'),
          ColonneMini('Montant 2025', (r) => '${r['montant']}', droite: true),
          ColonneMini('Compte proposé', (r) => r['compte'] == null ? 'à déterminer' : '${r['compte']} ${r['intitule']}',
              rendu: (r) => r['compte'] == null
                  ? const Text('à déterminer', style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12, fontStyle: FontStyle.italic))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      monoTexte(r['compte'], poids: FontWeight.w600),
                      Text('${r['intitule']}', style: const TextStyle(color: JetonsShell.slate500, fontSize: 10, height: 14 / 10)),
                    ])),
          ColonneMini('Pourquoi ce compte', (r) => '${r['motif']}',
              rendu: (r) => Text('${r['motif']}', style: const TextStyle(color: JetonsShell.slate600, fontSize: 12, height: 16 / 12))),
        ], lignes: [
          for (final d in sans)
            () {
              final pr = cpcPropositionCompte(d.libelle);
              return <String, Object?>{
                'poste': d.libelle,
                'montant': m(d.total),
                'compte': pr?.compte,
                'intitule': pr?.intitule ?? '',
                'motif': pr?.motif ?? 'Aucune proposition : le libellé ne permet pas de trancher.',
              };
            }()
        ]));
    }
    return CarteSigh(titre: 'Contrôles de cohérence du document source', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: enfants));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final e = cpcExercice2025;
    final courts = [for (final mo in e.mois) '${mo.substring(0, mo.length < 4 ? mo.length : 4)}. 25'];
    final meilleur = e.indiceMeilleurMois, faible = e.indiceMoisFaible;
    final postes = e.postesCharges();
    return ListenableBuilder(
      listenable: c.magasin.collection('factures'),
      builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        KpiGrilleSigh(kpis: [
          KpiSigh(libelle: 'Chiffre d’affaires 2025', valeur: money(e.totalChiffreAffaires), icone: LucideIcons.trendingUp, ton: TonSigh.succes),
          KpiSigh(libelle: 'Charges d’exploitation', valeur: money(e.totalCharges), icone: LucideIcons.trendingDown, ton: TonSigh.attention),
          KpiSigh(
              libelle: 'Résultat 2025',
              valeur: money(e.resultat),
              icone: e.resultat >= 0 ? LucideIcons.smile : LucideIcons.frown,
              ton: e.resultat >= 0 ? TonSigh.succes : TonSigh.danger,
              indice: '${pourcent(e.totalChiffreAffaires != 0 ? e.resultat / e.totalChiffreAffaires * 100 : 0)} du chiffre d’affaires'),
          KpiSigh(libelle: 'Chiffre d’affaires moyen', valeur: money(e.totalChiffreAffaires / 12), icone: LucideIcons.calendar, indice: 'par mois'),
          KpiSigh(libelle: 'Meilleur mois', valeur: e.mois[meilleur], icone: LucideIcons.award, ton: TonSigh.succes, indice: money(e.chiffreAffaires[meilleur])),
          KpiSigh(libelle: 'Mois le plus faible', valeur: e.mois[faible], icone: LucideIcons.trendingDown, ton: TonSigh.neutre, indice: money(e.chiffreAffaires[faible])),
          KpiSigh(libelle: 'Postes de charges', valeur: nombre(postes.length), icone: LucideIcons.list, ton: TonSigh.info),
          KpiSigh(
              libelle: 'Hors exploitation',
              valeur: money(e.totalHorsExploitation),
              icone: LucideIcons.landmark,
              ton: TonSigh.neutre,
              indice: 'Emprunt, cautionnements, immobilisation'),
        ]),
        const SizedBox(height: 16),
        _controles(e),
        if (e.controle.postesSansCompte != 0 || e.controle.ecart != 0) const SizedBox(height: 16),
        deuxCartes(
          CarteSigh(
              titre: 'Chiffre d’affaires mensuel 2025',
              child: GraphiqueBarres(etiquettes: courts, series: [SerieGraphique('Chiffre d’affaires', e.chiffreAffaires, couleur: _vert)])),
          CarteSigh(
              titre: 'Chiffre d’affaires, charges et résultat',
              child: GraphiqueLigne(etiquettes: courts, series: [
                SerieGraphique('Chiffre d’affaires', e.chiffreAffaires, couleur: _vert, aire: false),
                SerieGraphique('Charges', [for (var i = 0; i < 12; i++) arrondiJs(e.chargesDuMois(i))], couleur: _rouge, aire: false),
                SerieGraphique('Résultat', [for (var i = 0; i < 12; i++) arrondiJs(e.resultatDuMois(i))], couleur: _navy, aire: false),
              ])),
        ),
        const SizedBox(height: 16),
        OngletsSigh(onglets: [
          OngletDef(id: 'mensuel', libelle: 'Détail mensuel', construire: (_) => _mensuel(e)),
          OngletDef(id: 'charges', libelle: 'Postes de charges', compte: postes.length, construire: (_) => _charges(e, postes)),
          OngletDef(id: 'comparaison', libelle: 'Comparaison 2025 / 2026', construire: (_) => _comparaison(c, e, courts)),
        ]),
        sourceQual('Classeur comptable SYSCOHADA et compte de résultat 2025 — feuilles « DEPENSES25 » et « Recette ».'),
      ]),
    );
  }

  Widget _mensuel(CpcExercice2025 e) => TableauSigh(
        lignes: [
          for (var i = 0; i < 12; i++)
            {
              'id': '$i',
              'mois': '${_cap(e.mois[i])} 2025',
              'ca': e.chiffreAffaires[i],
              'charges': arrondiJs(e.chargesDuMois(i)),
              'resultat': arrondiJs(e.resultatDuMois(i)),
              'marge': cpcMargeMois(e, i),
            }
        ],
        nomExport: 'baseline-2025-mensuel',
        taillePage: 13,
        recherche: false,
        colonnes: [
          const ColonneTableau(cle: 'mois', libelle: 'Mois', sansCoupure: true),
          ColonneTableau(
              cle: 'ca',
              libelle: 'Chiffre d’affaires',
              droite: true,
              texte: (r) => m(r['ca']),
              rendu: (_, r) => Text(m(r['ca']), style: const TextStyle(color: JetonsShell.success700, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600))),
          ColonneTableau(
              cle: 'charges',
              libelle: 'Charges',
              droite: true,
              texte: (r) => m(r['charges']),
              rendu: (_, r) => Text(m(r['charges']), style: const TextStyle(color: JetonsShell.danger600, fontSize: 14, height: 20 / 14))),
          ColonneTableau(
              cle: 'resultat',
              libelle: 'Résultat',
              droite: true,
              texte: (r) => m(r['resultat']),
              rendu: (_, r) => Text(m(r['resultat']),
                  style: TextStyle(
                      color: n(r['resultat']) >= 0 ? JetonsShell.success700 : JetonsShell.danger600, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w700))),
          ColonneTableau(
              cle: 'marge',
              libelle: 'Marge',
              droite: true,
              texte: (r) => '${r['marge']} %',
              rendu: (_, r) => BadgeSigh('${r['marge']} %', ton: n(r['marge']) >= 0 ? TonSigh.succes : TonSigh.danger)),
        ],
      );

  Widget _charges(CpcExercice2025 e, List<CpcPosteCharge> postes) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClassementSigh([for (final p in postes.take(12)) (libelle: p.libelle, valeur: p.total)], ton: JetonsShell.warning600),
        const SizedBox(height: 12),
        TableauSigh(
          lignes: [
            for (final p in postes) {'id': p.libelle, 'num': p.num, 'libelle': p.libelle, 'total': p.total}
          ],
          nomExport: 'baseline-2025-charges',
          taillePage: 20,
          triInitial: 'total',
          sensInitial: 'desc',
          colonnes: [
            ColonneTableau(
                cle: 'num',
                libelle: 'Compte',
                sansCoupure: true,
                texte: (p) => '${p['num'] ?? 'À rattacher'}',
                rendu: (_, p) => p['num'] != null ? monoTexte(p['num'], poids: FontWeight.w600) : const BadgeSigh('À rattacher', ton: TonSigh.attention)),
            const ColonneTableau(cle: 'libelle', libelle: 'Poste de charge'),
            ColonneTableau(
                cle: 'total',
                libelle: 'Total 2025',
                droite: true,
                texte: (p) => m(p['total']),
                rendu: (_, p) => Text(m(p['total']), style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600))),
            ColonneTableau(cle: 'moyenne', libelle: 'Moyenne mensuelle', droite: true, valeur: (p) => n(p['total']) / 12, texte: (p) => m(n(p['total']) / 12)),
            ColonneTableau(
                cle: 'poids',
                libelle: 'Poids',
                droite: true,
                valeur: (p) => n(p['total']) / e.totalCharges * 100,
                texte: (p) => pourcent(n(p['total']) / e.totalCharges * 100),
                rendu: (_, p) => BadgeSigh(pourcent(n(p['total']) / e.totalCharges * 100))),
          ],
        ),
      ]);

  Widget _comparaison(ContexteEcran c, CpcExercice2025 e, List<String> courts) {
    final rows = cpcComparaison(e, c.magasin.collection('factures').actives);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const NoteSigh(
          'L’exercice 2026 est alimenté par le jeu de démonstration du prototype : la comparaison illustre le mécanisme, elle ne reflétera l’activité réelle qu’après la bascule en production.'),
      const SizedBox(height: 12),
      CarteSigh(
          titre: 'Chiffre d’affaires 2025 et 2026',
          child: GraphiqueBarres(etiquettes: [for (final k in courts) k.substring(0, k.length < 4 ? k.length : 4)], series: [
            SerieGraphique('2025 (réel)', [for (final r in rows) r.ca2025], couleur: _navy),
            SerieGraphique('2026 (prototype)', [for (final r in rows) r.ca2026], couleur: _vert),
          ])),
      const SizedBox(height: 12),
      TableauSigh(
        lignes: [
          for (final (i, r) in rows.indexed)
            {'id': '$i', 'mois': r.mois, 'ca2025': r.ca2025, 'ca2026': r.ca2026, 'ecart': r.ecart, 'evolution': r.evolution}
        ],
        nomExport: 'comparaison-2025-2026',
        taillePage: 13,
        recherche: false,
        colonnes: [
          const ColonneTableau(cle: 'mois', libelle: 'Mois', sansCoupure: true),
          ColonneTableau(cle: 'ca2025', libelle: 'CA 2025 (réel)', droite: true, texte: (r) => m(r['ca2025'])),
          ColonneTableau(cle: 'ca2026', libelle: 'CA 2026', droite: true, texte: (r) => m(r['ca2026'])),
          ColonneTableau(
              cle: 'ecart',
              libelle: 'Écart',
              droite: true,
              texte: (r) => m(r['ecart']),
              rendu: (_, r) => Text('${n(r['ecart']) > 0 ? '+' : ''}${m(r['ecart'])}',
                  style: TextStyle(color: n(r['ecart']) >= 0 ? JetonsShell.success700 : JetonsShell.danger600, fontSize: 14, height: 20 / 14))),
          ColonneTableau(
              cle: 'evolution',
              libelle: 'Évolution',
              droite: true,
              texte: (r) => '${r['evolution']} %',
              rendu: (_, r) => BadgeSigh('${n(r['evolution']) > 0 ? '+' : ''}${r['evolution']} %', ton: n(r['evolution']) >= 0 ? TonSigh.succes : TonSigh.danger)),
        ],
      ),
    ]);
  }
}
