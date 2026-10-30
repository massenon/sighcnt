import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'points_commun.dart';

/// `m6-point-stock` — « Point du stock valorisé ». Cinq vues, et le même mot les commande toutes : « ET LEUR MONTANT ». Un ÉTAT (ce qui reste)
/// se lit à une date, un FLUX (ce qui est entré ou sorti) sur une période : la périodicité ne vaut que pour le flux. La règle vit dans
/// `packages/domaine` (`points.dart`), rejouée sur les vecteurs de la maquette.
///
/// La méthode de valorisation (prix de vente ou CUMP) est un paramètre d'exploitation de la clinique (`S.valorisationSortie()`), que le jeu
/// du poste ne porte pas encore : le prix de vente, défaut de la maquette, s'applique. Chaque ligne porte néanmoins les DEUX valeurs.
class EcranPointStock extends StatefulWidget with EcranMaquette {
  const EcranPointStock({super.key});

  @override
  String get titre => 'Point du stock valorisé';

  @override
  String get description =>
      'Stock restant, reçu, entré et sorti — au magasin et à la pharmacie — avec sa valeur en francs.';

  @override
  String get regle =>
      'Chaque vue porte sa quantité ET son montant : un état de stock sans valeur ne se rapproche d’aucune écriture. Un état se lit à une date (ce qui reste), un flux se lit sur une période (ce qui est entré ou sorti) — les confondre ferait croire que le stock restant dépend de la période choisie.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(
          libelle: 'Point des ventes',
          icone: LucideIcons.coins,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m6-point-ventes')),
    ];
  }

  @override
  State<EcranPointStock> createState() => _EtatPointStock();
}

class _EtatPointStock extends State<EcranPointStock> {
  ControleurFormulaire? _vue, _periode, _date, _familles;
  static const _methode = MethodeValorisation.prixVente;

  List<ControleurFormulaire> get _tous => [_vue!, _periode!, _date!, _familles!];

  void _surChangement() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_vue != null) return;
    final auj = ContexteEcran.of(context).aujourdhui;
    ChampDef def(String nom, String libelle, TypeChamp type,
            {List<OptionChamp> options = const [], String? indicatif}) =>
        ChampDef(
            nom: nom,
            libelle: libelle,
            type: type,
            options: options,
            indicatif: indicatif,
            col: ColChamp.plein);
    _vue = champUnique(
        def('vue', 'Vue', TypeChamp.select, options: [
          for (final v in vuesStock) OptionChamp(v.id, v.label)
        ]),
        vuesStock.first.id);
    _periode = champUnique(
        def('periode', 'Périodicité (flux)', TypeChamp.select, options: [
          for (final p in periodes) OptionChamp(p.id, p.label)
        ]),
        'mois');
    _date = champUnique(def('date', 'Arrêté au', TypeChamp.date),
        iso(DateTime(auj.year, auj.month, auj.day)));
    _familles = champUnique(
        def('familles', 'Famille d’articles', TypeChamp.multiselect,
            options: [
              for (final f in famillesArticles) OptionChamp(f.id, f.label)
            ],
            indicatif: 'Toutes les familles'),
        <String>[]);
    for (final k in _tous) {
      k.addListener(_surChangement);
    }
  }

  @override
  void dispose() {
    if (_vue != null) {
      for (final k in _tous) {
        k.removeListener(_surChangement);
        k.dispose();
      }
    }
    super.dispose();
  }

  VueStock get _vueCourante =>
      vuesStock.firstWhere((v) => v.id == _vue!['vue'], orElse: () => vuesStock.first);

  List<(String, String)> _filtresEnForce(DateTime auj) {
    final p = periodes.firstWhere((x) => x.id == '${_periode!['periode']}');
    final fam = choix(_familles!['familles']);
    return [
      ('Vue', _vueCourante.label),
      ('Périodicité (flux)', p.label),
      if ('${_date!['date']}'.isNotEmpty)
        ('Arrêté au', dateFR(jourSaisi(_date!['date'], auj))),
      if (fam.isNotEmpty)
        (
          'Famille d’articles',
          resumeChoix(fam, {for (final f in famillesArticles) f.id: f.label})
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final auj = c.aujourdhui;
    final jourAuj = DateTime(auj.year, auj.month, auj.day);
    final produits = c.magasin.collection('produits');
    final mouvements = c.magasin.collection('mouvements');
    return ListenableBuilder(
      listenable: Listenable.merge([produits, mouvements]),
      builder: (context, _) {
        final vue = _vueCourante;
        final flux = vue.flux;
        final fin = jourSaisi(_date!['date'], jourAuj);
        final b = bornes('${_periode!['periode']}', fin);
        final familles = choix(_familles!['familles']);

        // L'écran totalise, cumule et dessine sur les lignes telles que le mouvement les a données ; seul le tableau les classe.
        final brutes = lignesVueStock(
            vue, produits.actives, mouvements.actives, b, _methode,
            familles: familles);
        final lignes = trierParMontant(brutes);
        final tot = totauxStock(brutes);
        final cumul = cumulParFamille(brutes);

        const icones = [
          (LucideIcons.list, TonSigh.navy),
          (LucideIcons.boxes, TonSigh.info),
          (LucideIcons.wallet, TonSigh.succes),
          (LucideIcons.scale, TonSigh.neutre),
        ];
        final kpis = [
          for (final (i, k) in indicateursStock(vue, tot).indexed)
            KpiSigh(
                libelle: k.libelle,
                valeur: k.valeur,
                icone: icones[i].$1,
                ton: icones[i].$2,
                indice: k.indice)
        ];

        final nomsFamilles = (lignes.map((l) => l.famille).toSet().toList()
          ..sort());

        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CarteSigh(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        children: [
                          commande(_vue!, largeur: 280),
                          commande(_periode!, largeur: 190, inactive: !flux),
                          commande(_date!, largeur: 160),
                          commande(_familles!, largeur: 256),
                        ]),
                    const SizedBox(height: 12),
                    Align(
                        alignment: Alignment.centerLeft,
                        child: BoutonSigh(
                            libelle: 'Imprimer le point',
                            icone: LucideIcons.printer,
                            onPressed: () => imprimerPoint(
                                context,
                                etatStock(vue, lignes, b, fin, _methode,
                                    familles: familles.length),
                                filtres: _filtresEnForce(jourAuj)))),
                  ])),
              const SizedBox(height: 16),
              NoteSigh(sansBalises(noteStock(vue, b)),
                  icone: flux ? LucideIcons.calendarRange : LucideIcons.camera),
              const SizedBox(height: 16),
              KpiGrilleSigh(kpis: kpis),
              const SizedBox(height: 16),
              TableauSigh(
                lignes: [for (final l in lignes) l.toMap()],
                taillePage: 25,
                nomExport: 'point-stock-${vue.id}',
                filtres: [
                  FiltreTableau(nom: 'famille', libelle: 'Famille', options: [
                    for (final f in nomsFamilles) OptionChamp(f)
                  ]),
                ],
                colonnes: [
                  ColonneTableau(
                      cle: 'code',
                      libelle: 'Réf.',
                      sansCoupure: true,
                      texte: (r) => '${r['code'] ?? ''}',
                      rendu: (_, r) => Text('${r['code'] ?? ''}',
                          style: styleTexte(
                              taille: 12,
                              police: 'LiberationMono',
                              couleur: JetonsShell.slate700))),
                  const ColonneTableau(cle: 'designation', libelle: 'Article'),
                  ColonneTableau(
                      cle: 'famille',
                      libelle: 'Famille',
                      texte: (r) => '${r['famille']}',
                      rendu: (_, r) => Align(
                          alignment: Alignment.centerLeft,
                          child: BadgeSigh('${r['famille']}', ton: TonSigh.navy))),
                  ColonneTableau(
                      cle: 'quantite',
                      libelle: flux ? 'Quantité mouvementée' : 'Quantité en stock',
                      droite: true,
                      texte: (r) =>
                          '${nombre(r['quantite'])} ${r['unite'] ?? ''}',
                      rendu: (_, r) {
                        final q = Text(
                            '${nombre(r['quantite'])} ${r['unite'] ?? ''}',
                            style: styleTexte(
                                couleur: JetonsShell.slate700,
                                poids: FontWeight.w600));
                        if (r['sousSeuil'] != true) return q;
                        return Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              q,
                              Text('sous le seuil',
                                  style: styleTexte(
                                      taille: 10,
                                      couleur: JetonsShell.danger600)),
                            ]);
                      }),
                  colMontant('pu', 'P.U.'),
                  colMontant('montant', 'Montant',
                      couleur: JetonsShell.navy800, poids: FontWeight.w700),
                  colMontant('montantCump', 'Montant au CUMP',
                      couleur: JetonsShell.slate500),
                ],
              ),
              // La lecture par famille : le cumul « par familles d'articles » que la Direction demande, sur la vue affichée.
              if (cumul.length > 1) ...[
                const SizedBox(height: 16),
                CarteSigh(
                    titre: 'Cumul par famille d’articles',
                    sansRemplissage: true,
                    child: TableauSigh(
                      lignes: cumulParFamilleTrie(brutes),
                      taillePage: 10,
                      recherche: false,
                      nomExport: 'point-stock-familles',
                      colonnes: [
                        const ColonneTableau(cle: 'famille', libelle: 'Famille'),
                        const ColonneTableau(
                            cle: 'references', libelle: 'Références', droite: true),
                        ColonneTableau(
                            cle: 'quantite',
                            libelle: 'Quantité',
                            droite: true,
                            texte: (r) => nombre(r['quantite'])),
                        colMontant('montant', 'Montant', poids: FontWeight.w600),
                      ],
                    )),
                const SizedBox(height: 16),
                deuxColonnes([
                  CarteSigh(
                      titre: 'Répartition de la valeur par famille',
                      child: GraphiqueBarres(
                          etiquettes: [for (final r in cumul) '${r['famille']}'],
                          series: [
                            SerieGraphique(
                                'Montant', [for (final r in cumul) n(r['montant'])],
                                couleur: JetonsShell.navy900)
                          ],
                          horizontal: true,
                          hauteur: 260)),
                ]),
              ],
            ]);
      },
    );
  }
}
