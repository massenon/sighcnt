import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

/// `SIGH.kit.crud()` pour les registres de stock (produits, lots) : KPI, onglets « Tous les X » / ONGLETS SUPPLÉMENTAIRES / « Archivés » (avec leur
/// compte), tableau trié / filtré / paginé, fiche en tiroir, CRÉATION et MODIFICATION en modale, archivage ANNULABLE (RG-14 : jamais de suppression).
///
/// Le `CrudSigh` du kit renvoie la création à un écran de saisie (`creerVers`) et n'a ni onglet supplémentaire ni formulaire : un registre de stock
/// se crée et se corrige dans une modale, comme dans la maquette, et le registre des lots porte un onglet « Ordre de sortie FEFO ». Les commandes
/// d'écriture sont ABSENTES (jamais grisées) sans le droit : « Nouveau » et « Modifier » → `droit.editer` ; « Archiver » et « Restaurer » → `droit.annuler`.
class CrudStock extends StatefulWidget {
  const CrudStock({
    super.key,
    required this.collection,
    required this.entite,
    required this.entiteP,
    required this.colonnes,
    required this.kpis,
    required this.champs,
    required this.valeursInitiales,
    required this.transformer,
    required this.detail,
    required this.titreDetail,
    this.sousTitreDetail,
    this.refuser,
    this.filtres = const [],
    this.triInitial,
    this.sensInitial = 'asc',
    this.taillePage = 15,
    this.largeurTiroir = 768,
    this.prefixeId = 'ID',
    this.etat,
    this.ongletsSup,
    this.referenceToast,
    this.libelleRecherche,
  });

  final CollectionMagasin collection;
  final String entite;
  final String entiteP;
  final List<ColonneTableau> colonnes;
  final List<KpiSigh> Function(BuildContext, List<Fiche> actives) kpis;
  final List<ChampDef> Function(Magasin) champs;
  final Map<String, Object?> Function() valeursInitiales;

  /// `transform` : la fiche à enregistrer, depuis les valeurs saisies (texte).
  final Fiche Function(BuildContext, Map<String, Object?>) transformer;

  /// `beforeSave` : motif du refus, ou `null`.
  final String? Function(Map<String, Object?>)? refuser;
  final Widget Function(BuildContext, Fiche) detail;
  final String Function(Fiche) titreDetail;
  final String? Function(Fiche)? sousTitreDetail;
  final List<FiltreTableau> filtres;
  final String? triInitial;
  final String sensInitial;
  final int taillePage;
  final double largeurTiroir;
  final String prefixeId;
  final void Function(BuildContext, Fiche)? etat;
  final List<OngletDef> Function(BuildContext)? ongletsSup;
  final String? Function(Fiche)? referenceToast;
  final String? libelleRecherche;

  @override
  State<CrudStock> createState() => _CrudStockState();
}

class _CrudStockState extends State<CrudStock> {
  @override
  void initState() {
    super.initState();
    widget.collection.addListener(_maj);
  }

  @override
  void dispose() {
    widget.collection.removeListener(_maj);
    super.dispose();
  }

  void _maj() => setState(() {});

  void _archiver(BuildContext ctx, List<Fiche> fiches) async {
    final n = fiches.length;
    final ok = await confirmerSigh(ctx,
        titre: n == 1
            ? 'Archiver cet enregistrement ?'
            : 'Archiver $n enregistrement(s) ?',
        message:
            'Archivage logique : les données restent consultables dans l’onglet « Archivés » et l’opération est annulable.',
        libelleOk: 'Archiver',
        dangereux: true);
    if (!ok || !ctx.mounted) return;
    final annulations = [
      for (final f in fiches) widget.collection.archiver(f['id'])
    ];
    ToastsSigh.afficher(ctx,
        n == 1 ? 'Enregistrement archivé.' : '$n enregistrement(s) archivé(s).',
        type: TypeToast.succes, annuler: () {
      for (final u in annulations) {
        u();
      }
    });
  }

  static Map<String, Object?> _enTexte(Fiche f) => {
        for (final e in f.entries)
          e.key: e.value is num ? '${e.value}' : e.value
      };

  /// La saisie (création ou modification) : modale à six colonnes, champs obligatoires contrôlés, refus nommé (`beforeSave`), annulation visible.
  void _saisir(BuildContext ctx, {Fiche? existante}) {
    final c = ContexteEcran.of(ctx);
    final ctl = ControleurFormulaire(widget.champs(c.magasin),
        existante != null ? _enTexte(existante) : widget.valeursInitiales());
    afficherModale<void>(ctx,
        titre: existante == null
            ? 'Nouveau ${widget.entite}'
            : 'Modifier le ${widget.entite}',
        sousTitre: 'Les champs marqués d’un astérisque sont obligatoires.',
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              BoutonSigh(
                  libelle: existante == null ? 'Créer' : 'Enregistrer',
                  icone: LucideIcons.check,
                  onPressed: () {
                    final saisie = ctl.valider();
                    if (saisie == null) {
                      ToastsSigh.afficher(
                          ctx, 'Le formulaire comporte des erreurs.',
                          type: TypeToast.erreur);
                      return;
                    }
                    final motif = widget.refuser?.call(saisie);
                    if (motif != null) {
                      ToastsSigh.afficher(ctx, motif, type: TypeToast.erreur);
                      return;
                    }
                    final fiche = widget.transformer(ctx, saisie);
                    fermer();
                    if (existante == null) {
                      final r = widget.collection.inserer({
                        'statut': 'actif',
                        ...fiche,
                        '_creePar': c.utilisateur,
                        '_creeLe': c.aujourdhui.toIso8601String(),
                      }, prefixe: widget.prefixeId);
                      ToastsSigh.afficher(ctx, 'Nouveau ${widget.entite} créé.',
                          type: TypeToast.succes,
                          detail: widget.referenceToast?.call(r.fiche),
                          annuler: r.annuler);
                    } else {
                      final annuler =
                          widget.collection.mettreAJour(existante['id'], fiche);
                      ToastsSigh.afficher(ctx, 'Modification enregistrée.',
                          type: TypeToast.succes,
                          detail: widget.referenceToast?.call(existante),
                          annuler: annuler);
                    }
                  }),
            ]);
  }

  void _ouvrirDetail(BuildContext ctx, Fiche f) {
    final c = ContexteEcran.of(ctx);
    afficherTiroir<void>(ctx,
        titre: widget.titreDetail(f),
        sousTitre: widget.sousTitreDetail?.call(f),
        largeurMax: widget.largeurTiroir,
        corps: widget.detail(ctx, f),
        pied: (fermer) => [
              if (widget.etat != null)
                BoutonSigh(
                    libelle: 'Imprimer',
                    icone: LucideIcons.printer,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => widget.etat!(ctx, f)),
              if (c.droit.editer)
                BoutonSigh(
                    libelle: 'Modifier',
                    icone: LucideIcons.pencil,
                    variante: VarianteBouton.secondaire,
                    onPressed: () {
                      fermer();
                      _saisir(ctx, existante: f);
                    }),
              if (c.droit.annuler)
                BoutonSigh(
                    libelle: 'Archiver',
                    icone: LucideIcons.archive,
                    variante: VarianteBouton.danger,
                    onPressed: () {
                      fermer();
                      _archiver(ctx, [f]);
                    }),
            ]);
  }

  TableauSigh _tableau(BuildContext ctx, ContexteEcran c,
      {required bool archive}) {
    final lignes =
        archive ? widget.collection.archivees : widget.collection.actives;
    return TableauSigh(
      colonnes: widget.colonnes,
      lignes: lignes,
      filtres: archive ? const [] : widget.filtres,
      taillePage: widget.taillePage,
      selectionnable: !archive,
      nomExport: widget.collection.nom,
      triInitial: widget.triInitial,
      sensInitial: widget.sensInitial,
      libelleRecherche:
          widget.libelleRecherche ?? 'Rechercher un ${widget.entite}…',
      messageVide: archive
          ? 'Aucun enregistrement archivé.'
          : 'Aucun ${widget.entite} enregistré.',
      indiceVide: archive
          ? null
          : (c.droit.editer
              ? 'Utiliser le bouton « Nouveau » pour créer le premier enregistrement.'
              : null),
      alClicLigne: (f) => _ouvrirDetail(ctx, f),
      actions: [
        if (!archive && c.droit.editer)
          BoutonSigh(
              libelle: 'Nouveau',
              icone: LucideIcons.plus,
              taille: TailleBouton.sm,
              onPressed: () => _saisir(ctx)),
      ],
      actionsGroupe: archive || !c.droit.annuler
          ? null
          : (context, sel, effacer) => [
                BoutonSigh(
                    libelle: 'Archiver',
                    icone: LucideIcons.archive,
                    taille: TailleBouton.sm,
                    variante: VarianteBouton.danger,
                    onPressed: () {
                      _archiver(ctx, sel);
                      effacer();
                    }),
              ],
      actionsLigne: (context, f) => archive
          ? [
              if (c.droit.annuler)
                BoutonIcone(
                    icone: LucideIcons.archiveRestore,
                    libelle: 'Restaurer',
                    onPressed: () {
                      widget.collection.restaurer(f['id']);
                      ToastsSigh.afficher(ctx, 'Enregistrement restauré.',
                          type: TypeToast.succes);
                    }),
            ]
          : [
              BoutonIcone(
                  icone: LucideIcons.eye,
                  libelle: 'Consulter',
                  onPressed: () => _ouvrirDetail(ctx, f)),
              if (c.droit.editer)
                BoutonIcone(
                    icone: LucideIcons.pencil,
                    libelle: 'Modifier',
                    onPressed: () => _saisir(ctx, existante: f)),
              if (widget.etat != null)
                BoutonIcone(
                    icone: LucideIcons.printer,
                    libelle: 'Imprimer l’état',
                    onPressed: () => widget.etat!(ctx, f)),
              if (c.droit.annuler)
                BoutonIcone(
                    icone: LucideIcons.archive,
                    libelle: 'Archiver',
                    onPressed: () => _archiver(ctx, [f])),
            ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final actives = widget.collection.actives;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!c.droit.editer && c.droit.voir)
        Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: NoteSigh(
                'Lecture seule : le profil « ${c.role} » consulte cet écran sans pouvoir y écrire. Les droits se règlent dans la matrice des rôles.',
                ton: TonSigh.attention)),
      Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: KpiGrilleSigh(kpis: widget.kpis(context, actives))),
      OngletsSigh(onglets: [
        OngletDef(
            id: 'liste',
            libelle: 'Tous les ${widget.entiteP}',
            compte: actives.length,
            construire: (ctx) => _tableau(ctx, c, archive: false)),
        ...?widget.ongletsSup?.call(context),
        OngletDef(
            id: 'archives',
            libelle: 'Archivés',
            compte: widget.collection.archivees.length,
            construire: (ctx) => _tableau(ctx, c, archive: true)),
      ]),
    ]);
  }
}
