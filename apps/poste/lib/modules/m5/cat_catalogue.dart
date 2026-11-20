import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../donnees/tarifs_poste.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/flux_commun.dart' show SourceFlux;
import '../m6/stock_crud.dart';
import 'cat_commun.dart';

const _delais = ['Immédiat', '1 h', '2 h', '4 h', '6 h', '24 h', '48 h', '72 h'];

/// Le tarif d'une analyse se LIT au référentiel de prix (version en vigueur aujourd'hui) : il ne se modifie plus ici (PRD-TARIFS, lot T6), il se propose à « Tarifs et prix ».
/// LOT TARIF-FIX : la même lecture que la prescription (`TarifsPoste.ligne`, voie `analyse`) ; une analyse créée ici n'a pas de prix tant qu'aucune prestation famille
/// Analyses de MÊME code n'est décidée : la ligne le DIT (« sans prix : à tarifier dans Tarifs et prix »), jamais un zéro.
LignePrix _ligneDe(ContexteEcran c, Fiche a) => TarifsPoste.ligne(c.magasin, a['code'], aujourdhui: c.aujourdhui, voie: 'analyse');
num? _prixDe(ContexteEcran c, Fiche a) => _ligneDe(c, a).montant;
const texteSansPrixCatalogue = 'sans prix : à tarifier dans Tarifs et prix';
String _tarif(ContexteEcran c, Fiche a) {
  final l = _ligneDe(c, a);
  if (l.ok) return money(l.montant, avecDevise: false);
  return l.effectifLe != null ? l.libelleCourt : texteSansPrixCatalogue;
}

/// La commande « Tarifer » n'existe que pour un profil qui peut PROPOSER un prix (modifier « Tarifs et prix ») : ABSENTE sinon, jamais grisée.
bool _peutTarifer(ContexteEcran c) => (c.donnees?.matrice.peutEditer(c.role, 'cfg-tarifs') ?? false) && (c.ouvre?.call('cfg-tarifs') ?? true);

/// `m5-catalogue` — « Catalogue des analyses » : le référentiel des 48 analyses de la clinique (catégorie, échantillon, délai, tarif). Création et
/// modification en modale, archivage annulable (RG-14), onglet « Par catégorie », état imprimable. Les tarifs sont des valeurs d'attente : le document
/// source ne renseigne pas la colonne des prix — l'icône « Tarif à confirmer » les distingue d'un tarif arrêté, et un tarif jamais présumé.
class EcranCatalogueAnalyses extends StatelessWidget with EcranMaquette {
  const EcranCatalogueAnalyses({super.key});

  @override
  String get titre => 'Catalogue des analyses';

  @override
  String get description =>
      'Référentiel des 48 analyses réalisées par le laboratoire de la clinique, avec catégorie, échantillon, délai et tarif.';

  @override
  String get regle =>
      'Les désignations reprennent fidèlement le document « Tarifs des analyses de laboratoire » de la clinique. Les tarifs portés ici sont des valeurs d’attente : le document source ne renseigne pas la colonne des prix et ceux-ci doivent être confirmés avant recette.';

  @override
  List<Widget> actionsEntete(BuildContext context) => [
        BoutonSigh(
            libelle: 'Imprimer le catalogue',
            icone: LucideIcons.printer,
            onPressed: () => _imprimer(context)),
      ];

  /// « Imprimer le catalogue » : toutes les analyses actives, dans l'ordre du catalogue (N°) — pas les lignes filtrées de l'écran.
  void _imprimer(BuildContext ctx) {
    final c = ContexteEcran.of(ctx);
    final rows = trierPar(collectionAnalyses(c.magasin).actives, (a) => a['n']);
    afficherApercu(
        ctx,
        pieceCat(ctx,
            titre: 'Tarifs des analyses de laboratoire',
            sousTitre: '${rows.length} désignations — tarifs en vigueur',
            blocs: [
              BlocTableau(TableauEtat(colonnes: [
                ColonneEtat(libelle: 'N°', valeur: (r) => r['n'], droite: true),
                ColonneEtat(libelle: 'Désignation', valeur: (r) => r['designation']),
                ColonneEtat(libelle: 'Catégorie', valeur: (r) => r['categorie']),
                ColonneEtat(libelle: 'Échantillon', valeur: (r) => r['echantillon']),
                ColonneEtat(libelle: 'Tarif', valeur: (r) => _tarif(c, r), droite: true),
              ], lignes: rows)),
            ],
            signatures: const [
              Signature('Le Laborantin chef', nom: laborantinChef),
              Signature('La Directrice Administrative', nom: directriceAdministrativeLabo),
            ]));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = collectionAnalyses(c.magasin);
    // Les listes de filtre et de formulaire viennent du RÉFÉRENTIEL des analyses (`D.ANALYSES`), triées comme la maquette.
    final ref = c.magasin.referentiel('analyses');
    final categories = catValeursDistinctes(ref, 'categorie');
    final echantillons = catValeursDistinctes(ref, 'echantillon');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CrudStock(
        collection: col,
        entite: 'analyse',
        entiteP: 'analyses',
        prefixeId: 'ANA',
        taillePage: 20,
        triInitial: 'n',
        referenceToast: (a) => '${a['code'] ?? ''}',
        colonnes: [
          const ColonneTableau(cle: 'n', libelle: 'N°', droite: true, sansCoupure: true),
          ColonneTableau(
              cle: 'code',
              libelle: 'Code',
              sansCoupure: true,
              texte: (a) => '${a['code'] ?? ''}',
              rendu: (_, a) => Text('${a['code'] ?? ''}', style: monoCode)),
          const ColonneTableau(cle: 'designation', libelle: 'Désignation'),
          ColonneTableau(
              cle: 'categorie',
              libelle: 'Catégorie',
              texte: (a) => '${a['categorie'] ?? ''}',
              rendu: (_, a) => BadgeSigh('${a['categorie'] ?? ''}', ton: TonSigh.navy)),
          const ColonneTableau(cle: 'echantillon', libelle: 'Échantillon'),
          ColonneTableau(
              cle: 'prix',
              libelle: 'Tarif (lecture)',
              droite: true,
              valeur: (a) => nombreOuZero(_prixDe(c, a)),
              texte: (a) => _tarif(c, a),
              rendu: (_, a) => !_ligneDe(c, a).ok
                  ? Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 4, children: [
                      Tooltip(
                          message: '${_ligneDe(c, a).motif} ${_ligneDe(c, a).geste}',
                          child: Text(_tarif(c, a), key: ValueKey('sans-prix-${a['code']}'), style: styleCat(taille: 12, couleur: JetonsShell.danger600))),
                      if (_peutTarifer(c))
                        BoutonSigh(
                            key: ValueKey('tarifer-${a['code']}'),
                            libelle: 'Tarifer',
                            icone: LucideIcons.coins,
                            taille: TailleBouton.sm,
                            variante: VarianteBouton.fantome,
                            onPressed: () => c.aller('cfg-tarifs')),
                    ])
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(_tarif(c, a), style: styleCat(couleur: JetonsShell.slate700, poids: FontWeight.w600)),
                      if (a['tarifProvisoire'] == true) ...[
                        const SizedBox(width: 4),
                        const Tooltip(
                            message: 'Tarif à confirmer',
                            child: Icon(LucideIcons.circleHelp, size: 14, color: JetonsShell.warning500)),
                      ],
                    ])),
          ColonneTableau(
              cle: 'statut',
              libelle: 'Statut',
              texte: (a) => '${a['statut'] ?? ''}',
              rendu: (_, a) => statutBadge(a['statut'])),
        ],
        filtres: [
          FiltreTableau(
              nom: 'categorie',
              libelle: 'Catégorie',
              options: [for (final x in categories) OptionChamp(x)]),
          FiltreTableau(
              nom: 'echantillon',
              libelle: 'Échantillon',
              options: [for (final x in echantillons) OptionChamp(x)]),
        ],
        kpis: (ctx, rows) {
          final k = catKpisCatalogue([for (final a in rows) {...a, 'prix': _prixDe(c, a)}]);
          return [
            KpiSigh(
                libelle: 'Analyses au catalogue',
                valeur: nombre(k.analyses),
                icone: LucideIcons.listChecks),
            KpiSigh(
                libelle: 'Catégories',
                valeur: nombre(k.categories),
                icone: LucideIcons.layers,
                ton: TonSigh.info),
            KpiSigh(
                libelle: 'Tarif moyen',
                valeur: k.tarifMoyen,
                icone: LucideIcons.coins,
                ton: TonSigh.succes),
            KpiSigh(
                key: const ValueKey('kpi-analyses-sans-prix'),
                libelle: 'Analyses sans prix',
                valeur: nombre(rows.where((a) => !_ligneDe(c, a).ok).length),
                icone: LucideIcons.circleAlert,
                ton: TonSigh.danger,
                indice: 'Sans prix : à tarifier dans « Tarifs et prix » (Nouvelle prestation, famille Analyses de laboratoire, même code).'),
            KpiSigh(
                libelle: 'Tarifs à confirmer',
                valeur: nombre(k.aConfirmer),
                icone: LucideIcons.circleHelp,
                ton: TonSigh.attention),
          ];
        },
        champs: (m) => [
          const ChampDef(nom: 'code', libelle: 'Code', requis: true),
          const ChampDef(
              nom: 'designation',
              libelle: 'Désignation',
              requis: true,
              col: ColChamp.plein),
          ChampDef(
              nom: 'categorie',
              libelle: 'Catégorie',
              type: TypeChamp.select,
              requis: true,
              options: [for (final x in categories) OptionChamp(x)]),
          ChampDef(
              nom: 'echantillon',
              libelle: 'Type d’échantillon',
              type: TypeChamp.select,
              options: [for (final x in echantillons) OptionChamp(x)]),
          ChampDef(
              nom: 'delai',
              libelle: 'Délai de rendu',
              type: TypeChamp.select,
              options: [for (final x in _delais) OptionChamp(x)]),
          // Le TARIF n'est plus saisi ici : il se propose à « Tarifs et prix » (Oui ou Non, date d'effet) ; cet écran garde la désignation, la catégorie, l'échantillon et le délai.
        ],
        valeursInitiales: () => {},
        transformer: (_, v) => catTransformAnalyse(v),
        detail: (ctx, a) => DescListeSigh([
          ('N°', '${a['n'] ?? ''}'),
          ('Code', Text('${a['code'] ?? ''}', style: monoCode)),
          ('Désignation', '${a['designation'] ?? ''}'),
          ('Catégorie', BadgeSigh('${a['categorie'] ?? ''}', ton: TonSigh.navy)),
          ('Échantillon', '${a['echantillon'] ?? ''}'),
          ('Tarif', _tarif(c, a)),
          ('Statut', statutBadge(a['statut'])),
          ('Délai de rendu', '${a['delai'] ?? ''}'),
        ]),
        titreDetail: (a) => '${a['designation'] ?? ''}',
        sousTitreDetail: (a) => '${a['code'] ?? ''}',
        // « Imprimer l'état » (ligne) et « Imprimer » (fiche) : la maquette déclare un `etat` vide, « remplacé par l'action d'en-tête » — des boutons
        // qui n'impriment rien (écart E186). Ils sont ABSENTS ici : l'impression se fait par « Imprimer le catalogue ».
        ongletsSup: (ctx) => [
          OngletDef(
              id: 'categories',
              libelle: 'Par catégorie',
              construire: (_) => _ParCategorie(c, col)),
        ],
      ),
      const SourceFlux('Tarifs des analyses de laboratoire — 48 désignations.'),
    ]);
  }
}

/// L'onglet « Par catégorie » : une carte par catégorie, ses analyses classées par désignation avec leur tarif.
class _ParCategorie extends StatelessWidget {
  const _ParCategorie(this.c, this.col);
  final ContexteEcran c;
  final CollectionMagasin col;

  @override
  Widget build(BuildContext context) {
    final groupes = catParCategorie(col.actives);
    return deuxColonnesMd([
      for (final g in groupes)
        CarteSigh(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: Text(g.categorie,
                    style: styleCat(couleur: JetonsShell.slate800, poids: FontWeight.w600))),
            BadgeSigh('${g.analyses.length} analyse${g.analyses.length > 1 ? 's' : ''}',
                ton: TonSigh.navy),
          ]),
          const SizedBox(height: 8),
          for (final a in g.analyses)
            Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Expanded(
                      child: Text('${a['designation']}',
                          style: styleCat(taille: 12, couleur: JetonsShell.slate600))),
                  const SizedBox(width: 12),
                  Text(_tarif(c, a),
                      style: styleCat(taille: 12, couleur: JetonsShell.slate800, poids: FontWeight.w500)),
                ])),
        ])),
    ]);
  }
}
