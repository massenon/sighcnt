import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

/// `SIGH.kit.crud()` pour les registres de la banque de sang (donneurs) : la copie fidèle de `CrudStock` (m6), aux textes EXACTS de `K.crud` de la
/// maquette là où `CrudStock` s'en écarte — fenêtre « Modifier l'enregistrement », message « Modifications enregistrées. », archivage unitaire avec
/// MOTIF obligatoire (`requireMotif`) et « Imprimer la sélection » qui imprime réellement la sélection. Les commandes d'écriture sont ABSENTES (jamais
/// grisées) sans le droit : « Nouveau » et « Modifier » → `droit.editer` ; « Archiver » et « Restaurer » → `droit.annuler`.
class CrudSang extends StatefulWidget {
  const CrudSang({
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
    this.valeursEdition,
    this.transformerExistante,
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

  /// Valeurs du formulaire d'une fiche EXISTANTE (par défaut : ses champs, les nombres en texte). Utile quand un champ du formulaire n'est pas un champ
  /// de la fiche (une date et une heure saisies à part, enregistrées ensemble).
  final Map<String, Object?> Function(Fiche)? valeursEdition;

  /// Comme [transformer], mais reçoit la fiche corrigée (`transform(values, record)` de la maquette) : permet de garder ce que le formulaire ne porte pas
  /// (référence, code déjà attribués).
  final Fiche Function(BuildContext, Map<String, Object?>, Fiche?)?
      transformerExistante;

  @override
  State<CrudSang> createState() => _CrudSangState();
}

class _CrudSangState extends State<CrudSang> {
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

  /// Archivage ANNULABLE (RG-14). Unitaire : le motif est obligatoire (`requireMotif`, journalisé) ; groupé : simple confirmation, comme la maquette.
  void _archiver(BuildContext ctx, List<Fiche> fiches) async {
    final n = fiches.length;
    if (n == 1) {
      final motif = await confirmerAvecMotif(ctx,
          titre: 'Archiver cet enregistrement ?',
          message:
              'L’enregistrement ne sera pas supprimé : il est archivé et reste consultable dans l’onglet « Archivés ». L’opération est journalisée et peut être annulée.',
          libelleOk: 'Archiver',
          dangereux: true);
      if (motif == null || !ctx.mounted) return;
    } else {
      final ok = await confirmerSigh(ctx,
          titre: 'Archiver $n enregistrement(s) ?',
          message:
              'Archivage logique : les données restent consultables et l’opération est annulable.',
          libelleOk: 'Archiver',
          dangereux: true);
      if (!ok || !ctx.mounted) return;
    }
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

  /// « Imprimer la sélection » : l'état `Sélection — <pluriel>` porte les colonnes du tableau, telles qu'affichées.
  void _imprimerSelection(BuildContext ctx, List<Fiche> sel) {
    final c = ContexteEcran.of(ctx);
    final cols = [for (final k in widget.colonnes) k];
    afficherApercu(
        ctx,
        PieceA4(
            titre: 'Sélection — ${widget.entiteP}',
            sousTitre: '${sel.length} enregistrement(s)',
            blocs: [
              BlocTableau(TableauEtat(colonnes: [
                for (final k in cols)
                  ColonneEtat(
                      libelle: k.libelle,
                      valeur: (l) => k.enTexte(l),
                      droite: k.droite),
              ], lignes: sel)),
            ],
            reference:
                PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
            utilisateur: c.utilisateur,
            edite: c.aujourdhui));
  }

  static Map<String, Object?> _enTexte(Fiche f) => {
        for (final e in f.entries)
          e.key: e.value is num ? '${e.value}' : e.value
      };

  /// La saisie (création ou modification) : modale à six colonnes, champs obligatoires contrôlés, refus nommé (`beforeSave`), annulation visible.
  void _saisir(BuildContext ctx, {Fiche? existante}) {
    final c = ContexteEcran.of(ctx);
    final ctl = ControleurFormulaire(widget.champs(c.magasin),
        existante != null
            ? (widget.valeursEdition?.call(existante) ?? _enTexte(existante))
            : widget.valeursInitiales());
    afficherModale<void>(ctx,
        titre: existante == null
            ? 'Nouveau ${widget.entite}'
            : 'Modifier l’enregistrement',
        sousTitre: existante == null
            ? 'Les champs marqués d’un astérisque sont obligatoires.'
            : '${existante['reference'] ?? existante['id']}',
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              BoutonSigh(
                  libelle: existante == null ? 'Créer' : 'Enregistrer',
                  icone: existante == null ? LucideIcons.plus : LucideIcons.save,
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
                    final fiche = widget.transformerExistante != null
                        ? widget.transformerExistante!(ctx, saisie, existante)
                        : widget.transformer(ctx, saisie);
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
                      ToastsSigh.afficher(ctx, 'Modifications enregistrées.',
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
