import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

/// `SIGH.kit.crud()` AVEC son formulaire de création et d'édition (`openForm`), tel que `m7-fournisseurs` l'emploie. Le `CrudSigh` du kit n'a
/// pas de formulaire générique (`creerVers` renvoie à un écran de saisie) : celui-ci le porte, sur les mêmes composants du kit.
///
/// Les commandes d'écriture sont ABSENTES (jamais grisées) sans le droit : « Nouveau » et « Modifier » → `droit.editer`, « Archiver » et
/// « Restaurer » → `droit.annuler`. Archiver demande un MOTIF (journalisé, RG-12) et reste ANNULABLE ; rien n'est supprimé (RG-14).
class CrudFormulaireSigh extends StatefulWidget {
  const CrudFormulaireSigh({
    super.key,
    required this.collection,
    required this.entite,
    required this.colonnes,
    required this.champs,
    required this.versFiche,
    this.entiteP,
    this.kpis,
    this.filtres = const [],
    this.detail,
    this.titreDetail,
    this.sousTitreDetail,
    this.etat,
    this.triInitial,
    this.sensInitial = 'asc',
    this.taillePage = 12,
    this.prefixeId = 'ID',
    this.valeursCreation = const {},
    this.provenance,
  });

  final CollectionMagasin collection;
  final String entite;
  final String? entiteP;
  final List<ColonneTableau> colonnes;

  /// Les champs du formulaire (`cfg.fields`).
  final List<ChampDef> champs;

  /// Les valeurs saisies → ce qui est écrit (`cfg.transform`). Lève [FormulaireInvalide] : « Le formulaire comporte des erreurs. ».
  final Fiche Function(Map<String, Object?> saisie) versFiche;
  final Map<String, Object?> valeursCreation;
  final String prefixeId;

  /// `cfg.source` (`K.source`) : la provenance de la donnée, en pied d'écran.
  final String? provenance;
  final List<KpiSigh> Function(List<Fiche> actives)? kpis;
  final List<FiltreTableau> filtres;
  final Widget Function(Fiche)? detail;
  final String Function(Fiche)? titreDetail;
  final String Function(Fiche)? sousTitreDetail;
  final void Function(BuildContext, Fiche)? etat;
  final String? triInitial;
  final String sensInitial;
  final int taillePage;

  @override
  State<CrudFormulaireSigh> createState() => _CrudFormulaireSighState();
}

class _CrudFormulaireSighState extends State<CrudFormulaireSigh> {
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

  static String _identifiant(Fiche f) =>
      '${f['code'] ?? f['reference'] ?? f['numero'] ?? ''}';

  void _formulaire(BuildContext ctx, Fiche? record) => ouvrirFormulaireFiche(ctx,
      collection: widget.collection,
      champs: widget.champs,
      versFiche: widget.versFiche,
      entite: widget.entite,
      record: record,
      prefixeId: widget.prefixeId,
      valeursCreation: widget.valeursCreation,
      identifiant: _identifiant);

  Future<void> _archiver(BuildContext ctx, List<Fiche> fiches) async {
    final n = fiches.length;
    final titre = n == 1
        ? 'Archiver cet enregistrement ?'
        : 'Archiver $n enregistrement(s) ?';
    final message = n == 1
        ? 'L’enregistrement ne sera pas supprimé : il est archivé et reste consultable dans l’onglet « Archivés ». L’opération est journalisée et peut être annulée.'
        : 'Archivage logique : les données restent consultables et l’opération est annulable.';
    final ok = n == 1
        ? await confirmerAvecMotif(ctx,
                titre: titre,
                message: message,
                libelleOk: 'Archiver',
                dangereux: true) !=
            null
        : await confirmerSigh(ctx,
            titre: titre,
            message: message,
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
    }, messageAnnulation: n == 1 ? 'Archivage annulé.' : 'Action annulée.');
  }

  void _ouvrirDetail(BuildContext ctx, Fiche f) {
    final c = ContexteEcran.of(ctx);
    afficherTiroir<void>(ctx,
        titre: widget.titreDetail?.call(f) ?? _identifiant(f),
        sousTitre: widget.sousTitreDetail?.call(f) ?? _identifiant(f),
        largeurMax: 672,
        corps: widget.detail?.call(f) ?? const SizedBox(),
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
                    onPressed: () {
                      fermer();
                      _formulaire(ctx, f);
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

  /// « Imprimer la sélection » : un état dont chaque colonne reprend le TEXTE de la cellule affichée.
  void _imprimerSelection(BuildContext ctx, List<Fiche> sel) {
    final c = ContexteEcran.of(ctx);
    afficherApercu(
        ctx,
        PieceA4(
          titre: 'Sélection — $_p',
          sousTitre: '${sel.length} enregistrement(s)',
          reference: PieceA4.reference_(
              c.aujourdhui, ImpressionPoste.prochainNumero()),
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
          tableaux: [
            TableauEtat(colonnes: [
              for (final col in widget.colonnes)
                ColonneEtat(
                    libelle: col.libelle,
                    droite: col.droite,
                    valeur: (r) => col.enTexte(r)),
            ], lignes: sel)
          ],
        ));
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
        if (!archive && c.droit.editer)
          BoutonSigh(
              libelle: 'Nouveau',
              icone: LucideIcons.plus,
              taille: TailleBouton.sm,
              onPressed: () => _formulaire(ctx, null)),
      ],
      actionsGroupe: archive
          ? null
          : (context, sel, effacer) => [
                BoutonSigh(
                    libelle: 'Imprimer la sélection',
                    icone: LucideIcons.printer,
                    taille: TailleBouton.sm,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => _imprimerSelection(ctx, sel)),
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
              if (c.droit.editer)
                BoutonIcone(
                    icone: LucideIcons.pencil,
                    libelle: 'Modifier',
                    onPressed: () => _formulaire(ctx, f)),
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
      if (widget.provenance != null)
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              const Icon(LucideIcons.fileCheck2,
                  size: 14, color: JetonsShell.slate400),
              const SizedBox(width: 6),
              Flexible(
                  child: Text('Source : ${widget.provenance}',
                      style: const TextStyle(
                          color: JetonsShell.slate400,
                          fontSize: 12,
                          height: 16 / 12))),
            ])),
    ]);
  }
}


/// Une valeur de la fiche → ce que le champ affiche (nombre → texte ; case → booléen).
Object? _versChamp(ChampDef c, Object? v) {
  if (c.type == TypeChamp.case_) return v == true;
  if (v == null) return '';
  return '$v';
}

/// `openForm(record)` de `K.crud` et `modifier()` de `K.actionsLigne` : la modale de création (« Nouveau X ») ou d'édition (« Modifier
/// l'enregistrement »), préremplie par les champs de la fiche — SOUS LEUR NOM DE CHAMP : un champ du formulaire qui n'est pas une clé de la
/// fiche s'affiche vide. Un formulaire en erreur ne produit que « Le formulaire comporte des erreurs. ». [detailMessage] : la référence
/// citée sous le message de succès (K.crud la cite, K.actionsLigne non).
void ouvrirFormulaireFiche(
  BuildContext ctx, {
  required CollectionMagasin collection,
  required List<ChampDef> champs,
  required Fiche Function(Map<String, Object?> saisie) versFiche,
  required String entite,
  required String Function(Fiche) identifiant,
  Fiche? record,
  String prefixeId = 'ID',
  Map<String, Object?> valeursCreation = const {},
  bool detailMessage = true,
}) {
  final edition = record != null;
  final controleur = ControleurFormulaire(champs, {
    if (edition)
      for (final c in champs)
        if (c.nom.isNotEmpty) c.nom: _versChamp(c, record[c.nom])
    else
      ...valeursCreation,
  });
  afficherModale<void>(ctx,
      titre: edition ? 'Modifier l’enregistrement' : 'Nouveau $entite',
      sousTitre: edition
          ? (identifiant(record).isEmpty ? '${record['id']}' : identifiant(record))
          : 'Les champs marqués d’un astérisque sont obligatoires.',
      taille: TailleModale.lg,
      corps: FormulaireSigh(controleur: controleur),
      pied: (fermer) => [
            BoutonSigh(
                libelle: 'Annuler',
                variante: VarianteBouton.secondaire,
                onPressed: fermer),
            BoutonSigh(
                libelle: edition ? 'Enregistrer' : 'Créer',
                icone: edition ? LucideIcons.save : LucideIcons.plus,
                onPressed: () {
                  final saisie = controleur.valider();
                  Fiche? valeurs;
                  if (saisie != null) {
                    try {
                      valeurs = versFiche(saisie);
                    } on FormulaireInvalide {
                      valeurs = null;
                    }
                  }
                  if (valeurs == null) {
                    ToastsSigh.afficher(
                        ctx, 'Le formulaire comporte des erreurs.',
                        type: TypeToast.erreur);
                    return;
                  }
                  final VoidCallback annuler;
                  final String ref;
                  if (edition) {
                    annuler = collection.mettreAJour(record['id'], valeurs);
                    ref = identifiant({...record, ...valeurs});
                  } else {
                    final r = collection.inserer(
                        {...valeurs, 'statut': 'actif'},
                        prefixe: prefixeId);
                    annuler = r.annuler;
                    ref = identifiant(r.fiche);
                  }
                  fermer();
                  ToastsSigh.afficher(
                      ctx,
                      edition
                          ? 'Modifications enregistrées.'
                          : 'Nouveau $entite créé.',
                      type: TypeToast.succes,
                      detail: detailMessage && ref.isNotEmpty ? ref : null,
                      annuler: annuler);
                }),
          ]);
}

/// L'archivage d'UNE fiche tel que `K.actionsLigne` le pose : confirmation AVEC MOTIF (journalisée, RG-12), annulable et visible.
Future<void> archiverAvecMotif(BuildContext ctx, CollectionMagasin collection, Fiche f) async {
  final motif = await confirmerAvecMotif(ctx,
      titre: 'Archiver cet enregistrement ?',
      message:
          'Archivage logique (RG-14) : la donnée reste consultable et l’opération est annulable.',
      libelleOk: 'Archiver',
      dangereux: true);
  if (motif == null || !ctx.mounted) return;
  final annuler = collection.archiver(f['id']);
  ToastsSigh.afficher(ctx, 'Enregistrement archivé.',
      type: TypeToast.succes,
      annuler: annuler,
      messageAnnulation: 'Archivage annulé.');
}
