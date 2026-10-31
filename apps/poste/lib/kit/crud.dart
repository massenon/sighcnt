import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../donnees/magasin.dart';
import '../shell/contexte_ecran.dart';
import 'bouton.dart';
import 'carte.dart';
import 'modale.dart';
import 'onglets.dart';
import 'tableau.dart';
import 'toast.dart';
import 'ton.dart';

/// `SIGH.kit.crud()` : l'écran de gestion de la maquette — KPI, onglets « Tous les X » / « Archivés » (avec leur compte), tableau trié/filtré/
/// paginé, sélection multiple, fiche en tiroir, archivage ANNULABLE (RG-14, jamais de suppression). Les commandes d'écriture sont ABSENTES (jamais
/// grisées) sans le droit : « Nouveau » et « Modifier » → `droit.editer` ; « Archiver » et « Restaurer » → `droit.annuler`.
///
/// Écarts assumés avec le K.crud de la maquette, dits : pas de formulaire générique de création/modification (`creerVers` renvoie à l'écran de
/// saisie, comme les écrans de facture) ; pas de journal d'audit tant que le journal d'opérations (plan S4) n'est pas branché.
class CrudSigh extends StatefulWidget {
  const CrudSigh({
    super.key,
    required this.collection,
    required this.entite,
    required this.colonnes,
    this.entiteP,
    this.kpis,
    this.filtres = const [],
    this.creerVers,
    this.detail,
    this.titreDetail,
    this.sousTitreDetail,
    this.etat,
    this.triInitial,
    this.sensInitial = 'asc',
    this.taillePage = 12,
    this.largeurTiroir = 672,
    this.intro,
  });

  /// `cfg.intro` : l'encadré d'explication posé APRÈS les indicateurs et avant les onglets (un écran en lecture seule dit pourquoi).
  final Widget Function(BuildContext)? intro;

  final CollectionMagasin collection;
  final String entite;
  final String? entiteP;
  final List<ColonneTableau> colonnes;
  final List<KpiSigh> Function(List<Fiche> actives)? kpis;
  final List<FiltreTableau> filtres;

  /// `app.go(creerVers)` : l'écran de saisie complet (une facture se compose de lignes, de remises et d'une répartition).
  final String? creerVers;
  final Widget Function(Fiche)? detail;
  final String Function(Fiche)? titreDetail;
  final String Function(Fiche)? sousTitreDetail;

  /// Impression de la pièce (`cfg.etat`).
  final void Function(BuildContext, Fiche)? etat;
  final String? triInitial;
  final String sensInitial;
  final int taillePage;
  final double largeurTiroir;

  @override
  State<CrudSigh> createState() => _CrudSighState();
}

class _CrudSighState extends State<CrudSigh> {
  String get _p => widget.entiteP ?? '${widget.entite}s';

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

  void _ouvrirDetail(BuildContext ctx, Fiche f) {
    final c = ContexteEcran.of(ctx);
    afficherTiroir<void>(ctx,
        titre: widget.titreDetail?.call(f) ??
            '${f['numero'] ?? f['code'] ?? f['id']}',
        sousTitre: widget.sousTitreDetail?.call(f),
        largeurMax: widget.largeurTiroir,
        corps: widget.detail?.call(f) ?? const SizedBox(),
        pied: (fermer) => [
              if (widget.etat != null)
                BoutonSigh(
                    libelle: 'Imprimer',
                    icone: LucideIcons.printer,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => widget.etat!(ctx, f)),
              // « Archiver » est AUSSI au pied de la fiche (Bug 10 des Instructions) ; absent sans le droit.
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
      filtres: widget.filtres,
      taillePage: widget.taillePage,
      selectionnable: !archive,
      nomExport: widget.collection.nom,
      triInitial: widget.triInitial,
      sensInitial: widget.sensInitial,
      libelleRecherche: 'Rechercher un ${widget.entite}…',
      messageVide: archive
          ? 'Aucun enregistrement archivé.'
          : 'Aucun ${widget.entite} enregistré.',
      indiceVide: archive
          ? null
          : 'Utiliser le bouton « Nouveau » pour créer le premier enregistrement.',
      alClicLigne: (f) => _ouvrirDetail(ctx, f),
      actions: [
        if (!archive && c.droit.editer && widget.creerVers != null)
          BoutonSigh(
              libelle: 'Nouveau',
              icone: LucideIcons.plus,
              taille: TailleBouton.sm,
              onPressed: () => c.aller(widget.creerVers!)),
      ],
      actionsGroupe: archive
          ? null
          : (context, sel, effacer) => [
                BoutonSigh(
                    libelle: 'Imprimer la sélection',
                    icone: LucideIcons.printer,
                    taille: TailleBouton.sm,
                    variante: VarianteBouton.secondaire,
                    onPressed: () {}),
                if (c.droit.annuler)
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
      if (widget.kpis != null)
        Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: KpiGrilleSigh(kpis: widget.kpis!(actives))),
      if (widget.intro != null)
        Padding(padding: const EdgeInsets.only(bottom: 16), child: widget.intro!(context)),
      OngletsSigh(onglets: [
        OngletDef(
            id: 'liste',
            libelle: 'Tous les $_p',
            compte: actives.length,
            construire: (ctx) => _tableau(ctx, c, archive: false)),
        OngletDef(
            id: 'archives',
            libelle: 'Archivés',
            compte: widget.collection.archivees.length,
            construire: (ctx) => _tableau(ctx, c, archive: true)),
      ]),
    ]);
  }
}
