import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart' show Fiche;
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/points_commun.dart' show champUnique, commande;
import 'cpc_commun.dart';

/// `m12-cout-activite` — « Coût à l'activité » : les consommables réellement sortis pour un séjour ou un acte, face au montant facturé — marge sur
/// consommables par groupe de prestation.
///
/// CE QUI EST CALCULABLE L'EST ; CE QUI NE L'EST PAS SE DIT. Le consommable réel se lit (sortie de stock au CUMP, rattachée par son justificatif, RG-03) ;
/// le coût de PERSONNEL n'est PAS imputable à un séjour — aucun document ne donne la clé de répartition, et en inventer une donnerait un coût de revient
/// qui a l'air d'un fait. L'écran calcule donc une MARGE SUR CONSOMMABLES, la nomme ainsi, et dit ce qu'elle ne comprend pas. Les sorties qui ne se
/// rattachent à aucun groupe facturé sont comptées À PART plutôt que réparties. La prévision saisonnière est une projection, pas une prévision budgétaire.
class EcranCoutActivite extends StatefulWidget with EcranMaquette {
  const EcranCoutActivite({super.key});

  @override
  String get titre => 'Coût à l’activité';

  @override
  String get description =>
      'Consommables réellement sortis pour un séjour ou un acte, face au montant facturé — marge sur consommables par groupe de prestation.';

  @override
  String get regle =>
      'Le coût retenu est celui des consommables réellement sortis, valorisés au CUMP et rattachés par le justificatif de la sortie (RG-03). Le coût de personnel n’est PAS imputé : aucun document ne fournit de clé de répartition par séjour, et en inventer une donnerait un coût de revient qui a l’air d’un fait. Ce qui est affiché est donc une marge sur consommables, jamais un résultat.';

  @override
  List<Widget> actionsEntete(BuildContext context) => [
        BoutonSigh(
            libelle: 'Recettes & charges par groupe',
            icone: LucideIcons.scale,
            variante: VarianteBouton.secondaire,
            onPressed: () => ContexteEcran.of(context).aller('m12-rentabilite-groupes')),
        BoutonSigh(
            libelle: 'Coût global de l’agent',
            icone: LucideIcons.userCog,
            variante: VarianteBouton.secondaire,
            onPressed: () => ContexteEcran.of(context).aller('m10-cout-agent')),
      ];

  @override
  State<EcranCoutActivite> createState() => _EtatCout();
}

class _EtatCout extends State<EcranCoutActivite> {
  ControleurFormulaire? _du, _au;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_du != null) return;
    final c = ContexteEcran.of(context);
    final a = c.aujourdhui;
    _du = champUnique(const ChampDef(nom: 'du', libelle: 'Du', type: TypeChamp.date, col: ColChamp.plein), iso(DateTime(a.year, a.month, a.day - 90, a.hour, a.minute, a.second)));
    _au = champUnique(const ChampDef(nom: 'au', libelle: 'au', type: TypeChamp.date, col: ColChamp.plein), iso(a));
    for (final x in [_du!, _au!]) {
      x.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  String get _d => '${_du!['du'] ?? ''}';
  String get _f => '${_au!['au'] ?? ''}';

  CpcCoutActivite _calcul(ContexteEcran c) => cpcCoutActivite(
      factures: c.magasin.collection('factures').actives,
      mouvements: c.magasin.collection('mouvements').actives,
      produits: c.magasin.collection('produits').actives,
      du: _d,
      au: _f,
      secteurParCode: secteursDesActes(c.magasin.collection('actes').toutes));

  void _imprimer(BuildContext ctx, ContexteEcran c) {
    final r = _calcul(c);
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'Coût à l’activité — marge sur consommables',
            sousTitre: 'Du ${dateDe(_d)} au ${dateDe(_f)}',
            cartouche: [
              ('Prestations facturées', money(r.recette)),
              ('Consommables sortis', money(r.cout)),
              ('Marge sur consommables', money(r.recette - r.cout)),
              ('Coût de personnel', 'non imputé — aucune clé de répartition documentée'),
            ],
            tableaux: [
              TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Groupe de prestation', valeur: (x) => x['groupe']),
                ColonneEtat(libelle: 'Lignes', droite: true, valeur: (x) => x['nbLignes']),
                ColonneEtat(libelle: 'Facturé', droite: true, valeur: (x) => m(x['recette']), somme: (x) => n(x['recette'])),
                ColonneEtat(libelle: 'Consommables', droite: true, valeur: (x) => m(x['cout']), somme: (x) => n(x['cout'])),
                ColonneEtat(libelle: 'Marge', droite: true, valeur: (x) => m(x['marge']), somme: (x) => n(x['marge'])),
              ], lignes: [for (final g in r.lignes) _fiche(g)])
            ],
            signatures: [const Signature('Le Comptable'), signDafCompta]));
  }

  static Fiche _fiche(CpcGroupeActivite g) => {
        'id': g.id,
        'groupe': g.groupe,
        'nbLignes': g.nbLignes,
        'recette': g.recette,
        'cout': g.cout,
        'marge': g.marge,
        'taux': g.taux,
      };

  Widget _prevision(ContexteEcran c) {
    final b = cpcBfr(
        factures: c.magasin.collection('factures').actives,
        produits: c.magasin.collection('produits').actives,
        facturesFournisseurs: c.magasin.collection('facturesFournisseurs').actives,
        auj: c.aujourdhui,
        fin: _f.isEmpty ? iso(c.aujourdhui) : _f);
    final p = cpcPrevisionSaisonniere(c.magasin.collection('admissions').actives, b.bfr);
    if (p == null) {
      return const CarteSigh(
          titre: 'Prévision saisonnière',
          child: VideSigh(
              'Moins de trois mois d’admissions renseignés : aucun profil saisonnier ne peut être déduit. Un indice calculé sur deux mois ne serait pas une prévision, ce serait une coïncidence.',
              icone: LucideIcons.calendarOff));
    }
    return CarteSigh(
        titre: 'Prévision saisonnière du besoin de financement',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const NoteSigh(
              'Une projection, pas une prévision budgétaire. L’indice est le rapport des admissions du mois à la moyenne des mois observés ; le BFR projeté applique cet indice au besoin constaté. Il suppose que le besoin suit l’activité proportionnellement, ce qui est vrai des stocks et des créances, faux des charges fixes. À lire comme un ordre de grandeur.',
              icone: LucideIcons.chartLine),
          const SizedBox(height: 12),
          MiniTableauSigh(colonnes: [
            ColonneMini('Mois', (x) => '${x['mois']}'),
            ColonneMini('Admissions', (x) => '${x['admissions']}', droite: true),
            ColonneMini('Indice', (x) => x['indice'] == null ? '—' : nombre(x['indice'], 2), droite: true),
            ColonneMini('BFR projeté', (x) => x['bfrProjete'] == null ? '—' : m(x['bfrProjete']), droite: true),
          ], lignes: [
            for (final x in p) {'mois': x.mois, 'admissions': x.admissions, 'indice': x.indice, 'bfrProjete': x.bfrProjete}
          ]),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(
          [for (final k in ['factures', 'mouvements', 'produits', 'actes', 'admissions', 'facturesFournisseurs']) c.magasin.collection(k)]),
      builder: (context, _) {
        final r = _calcul(c);
        final recette = r.recette, cout = r.cout;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CarteSigh(
              child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
            commande(_du!, largeur: 200),
            commande(_au!, largeur: 200),
            BoutonSigh(libelle: 'Imprimer l’analyse', icone: LucideIcons.printer, onPressed: () => _imprimer(context, c)),
          ])),
          const SizedBox(height: 16),
          const NoteSigh(
              'Marge sur consommables, et non coût de revient. Le coût de personnel n’est pas réparti par séjour : aucun document de la clinique ne donne la clé qui le permettrait, et l’inventer donnerait un chiffre qui aurait l’air d’un fait. Le coût employeur se lit agent par agent au Coût global de l’agent, les charges par centre au Recettes & charges par groupe.',
              ton: TonSigh.attention,
              icone: LucideIcons.triangleAlert),
          const SizedBox(height: 16),
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Prestations facturées', valeur: money(recette), icone: LucideIcons.receipt),
            KpiSigh(libelle: 'Consommables sortis', valeur: money(cout), icone: LucideIcons.packageMinus, ton: TonSigh.attention),
            KpiSigh(
                libelle: 'Marge sur consommables',
                valeur: money(recette - cout),
                icone: LucideIcons.scale,
                ton: recette - cout >= 0 ? TonSigh.succes : TonSigh.danger),
            KpiSigh(
                libelle: 'Taux de marge',
                valeur: recette != 0 ? pourcent((recette - cout) / recette * 100) : '—',
                icone: LucideIcons.percent,
                ton: TonSigh.info,
                indice: 'hors personnel et charges de structure'),
          ]),
          if (r.lignes.isNotEmpty) ...[
            const SizedBox(height: 16),
            CarteSigh(
                titre: 'Recette et consommation par groupe',
                child: GraphiqueBarres(hauteur: 260, etiquettes: [for (final g in r.lignes) g.groupe], series: [
                  SerieGraphique('Facturé', [for (final g in r.lignes) g.recette]),
                  SerieGraphique('Consommables', [for (final g in r.lignes) g.cout]),
                ])),
          ],
          const SizedBox(height: 16),
          TableauSigh(
            titre: 'Marge sur consommables par groupe de prestation',
            lignes: [for (final g in r.lignes) _fiche(g)],
            nomExport: 'cout-activite',
            taillePage: 12,
            triInitial: 'recette',
            sensInitial: 'desc',
            colonnes: [
              const ColonneTableau(cle: 'groupe', libelle: 'Groupe de prestation'),
              const ColonneTableau(cle: 'nbLignes', libelle: 'Lignes facturées', droite: true),
              ColonneTableau(cle: 'recette', libelle: 'Facturé', droite: true, texte: (x) => m(x['recette'])),
              ColonneTableau(cle: 'cout', libelle: 'Consommables', droite: true, texte: (x) => m(x['cout'])),
              ColonneTableau(
                  cle: 'marge',
                  libelle: 'Marge',
                  droite: true,
                  texte: (x) => m(x['marge']),
                  rendu: (_, x) => Text(m(x['marge']),
                      style: TextStyle(
                          color: n(x['marge']) >= 0 ? JetonsShell.success600 : JetonsShell.danger600,
                          fontSize: 14,
                          height: 20 / 14,
                          fontWeight: FontWeight.w600))),
              ColonneTableau(cle: 'taux', libelle: 'Taux', droite: true, texte: (x) => x['taux'] == null ? '—' : pourcent(x['taux'])),
            ],
          ),
          if (r.horsGroupe > 0) ...[
            const SizedBox(height: 16),
            NoteSigh(
                '${money(r.horsGroupe)} de sorties ne se rattachent à aucun groupe facturé sur la période — fournitures, entretien, petit matériel. Elles sont comptées à part plutôt que réparties : les imputer à un groupe au prorata fabriquerait une clé que rien ne justifie.'),
          ],
          const SizedBox(height: 16),
          _prevision(c),
        ]);
      },
    );
  }
}
