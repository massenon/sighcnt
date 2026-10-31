import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'commun_m14.dart';

/// `SIGH.kit.crud()` AVEC son formulaire (`openForm`) tel que `m14-utilisateurs` l'emploie : onglets « Tous les X » / « Archivés », KPI, tableau,
/// fiche en tiroir, création et modification en modale, archivage avec MOTIF, annulable (RG-14 : rien n'est supprimé, RG-12 : le motif est journalisé).
///
/// Ce qui le distingue du CRUD générique du kit : les champs dépendent de la fiche (le mot de passe n'existe qu'à la création) et un contrôle
/// métier [avant] REFUSE EN LE DISANT (son propre message, pas « Le formulaire comporte des erreurs. »), comme `cfg.beforeSave` de la maquette.
/// Les commandes d'écriture sont ABSENTES (jamais grisées) sans le droit : « Nouveau » et « Modifier » → `droit.editer` ; « Archiver » et
/// « Restaurer » → `droit.annuler`.
class CrudM14 extends StatefulWidget {
  const CrudM14({
    super.key,
    required this.collection,
    required this.entite,
    required this.colonnes,
    required this.champs,
    required this.transformer,
    this.entiteP,
    this.avant,
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

  /// Les champs du formulaire pour [record] (`null` : création).
  final List<ChampDef> Function(BuildContext, Fiche? record) champs;

  /// `cfg.beforeSave` : un message de refus, ou `null`. Rien n'est écrit sur un refus.
  final String? Function(BuildContext, Map<String, Object?> saisie, Fiche? record)? avant;

  /// `cfg.transform` : les valeurs saisies → ce qui est ÉCRIT.
  final Fiche Function(BuildContext, Map<String, Object?> saisie, Fiche? record) transformer;
  final Map<String, Object?> valeursCreation;
  final String prefixeId;
  final String? provenance;
  final List<KpiSigh> Function(List<Fiche> actives)? kpis;
  final List<FiltreTableau> filtres;
  final Widget Function(BuildContext, Fiche)? detail;
  final String Function(Fiche)? titreDetail;
  final String Function(Fiche)? sousTitreDetail;
  final void Function(BuildContext, Fiche)? etat;
  final String? triInitial;
  final String sensInitial;
  final int taillePage;

  @override
  State<CrudM14> createState() => _CrudM14State();
}

class _CrudM14State extends State<CrudM14> {
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
      '${f['code'] ?? f['reference'] ?? f['numero'] ?? f['identifiant'] ?? f['id']}';

  static Object? _versChamp(ChampDef c, Object? v) {
    if (c.type == TypeChamp.case_) return v == true;
    if (v == null) return '';
    if (c.type == TypeChamp.multiselect && v is List) return [for (final x in v) '$x'];
    return '$v';
  }

  void _formulaire(BuildContext ctx, Fiche? record) {
    final champs = widget.champs(ctx, record);
    final edition = record != null;
    // Les accolades comptent : sans elles le « else » se rattacherait au « if » du champ, et les valeurs par défaut d'une création seraient perdues.
    final initial = <String, Object?>{};
    if (edition) {
      for (final c in champs) {
        if (c.nom.isNotEmpty) initial[c.nom] = _versChamp(c, record[c.nom]);
      }
    } else {
      initial.addAll(widget.valeursCreation);
    }
    final controleur = ControleurFormulaire(champs, initial);
    afficherModale<void>(ctx,
        titre: edition ? 'Modifier l’enregistrement' : 'Nouveau ${widget.entite}',
        sousTitre: edition
            ? _identifiant(record)
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
                    if (saisie == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.',
                          type: TypeToast.erreur);
                      return;
                    }
                    final refus = widget.avant?.call(ctx, saisie, record);
                    if (refus != null) {
                      ToastsSigh.afficher(ctx, refus, type: TypeToast.erreur);
                      return;
                    }
                    final valeurs = widget.transformer(ctx, saisie, record);
                    final VoidCallback annuler;
                    if (edition) {
                      annuler = widget.collection.mettreAJour(record['id'], valeurs);
                    } else {
                      annuler = widget.collection
                          .inserer({...valeurs, 'statut': 'actif'}, prefixe: widget.prefixeId)
                          .annuler;
                    }
                    fermer();
                    ToastsSigh.afficher(
                        ctx,
                        edition
                            ? 'Modifications enregistrées.'
                            : 'Nouveau ${widget.entite} créé.',
                        type: TypeToast.succes,
                        annuler: annuler);
                  }),
            ]);
  }

  /// Archivage AVEC MOTIF, journalisé (RG-12), annulable et visible ; rien n'est supprimé (RG-14).
  Future<void> _archiver(BuildContext ctx, List<Fiche> fiches) async {
    final n = fiches.length;
    final c = ContexteEcran.of(ctx);
    String? motif;
    if (n == 1) {
      motif = await confirmerAvecMotif(ctx,
          titre: 'Archiver cet enregistrement ?',
          message:
              'L’enregistrement ne sera pas supprimé : il est archivé et reste consultable dans l’onglet « Archivés ». L’opération est journalisée et peut être annulée.',
          libelleOk: 'Archiver',
          dangereux: true);
      if (motif == null) return;
    } else {
      final ok = await confirmerSigh(ctx,
          titre: 'Archiver $n enregistrement(s) ?',
          message:
              'Archivage logique : les données restent consultables et l’opération est annulable.',
          libelleOk: 'Archiver',
          dangereux: true);
      if (!ok) return;
    }
    if (!ctx.mounted) return;
    final annulations = [for (final f in fiches) widget.collection.archiver(f['id'])];
    if (motif != null) {
      c.magasin.journaliser('Motif d’archivage', 'M14', widget.entite,
          _identifiant(fiches.first), null, {'motif': motif});
    }
    ToastsSigh.afficher(
        ctx, n == 1 ? 'Enregistrement archivé.' : '$n enregistrement(s) archivé(s).',
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
        corps: widget.detail?.call(ctx, f) ?? const SizedBox(),
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

  void _imprimerSelection(BuildContext ctx, List<Fiche> sel) {
    final c = ContexteEcran.of(ctx);
    afficherApercu(
        ctx,
        PieceA4(
          titre: 'Sélection — $_p',
          sousTitre: '${sel.length} enregistrement(s)',
          reference: referenceImpression(c),
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
          tableaux: [
            TableauEtat(colonnes: [
              for (final col in widget.colonnes)
                ColonneEtat(libelle: col.libelle, droite: col.droite, valeur: (r) => col.enTexte(r)),
            ], lignes: sel)
          ],
        ));
  }

  TableauSigh _tableau(BuildContext ctx, ContexteEcran c, {required bool archive}) {
    final lignes = archive ? widget.collection.archivees : widget.collection.actives;
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
      messageVide: archive ? 'Aucun enregistrement archivé.' : 'Aucun ${widget.entite} enregistré.',
      indiceVide: archive ? null : 'Utiliser le bouton « Nouveau » pour créer le premier enregistrement.',
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
                      ToastsSigh.afficher(ctx, 'Enregistrement restauré.', type: TypeToast.succes);
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
              const Icon(LucideIcons.fileCheck2, size: 14, color: JetonsShell.slate400),
              const SizedBox(width: 6),
              Flexible(
                  child: Text('Source : ${widget.provenance}',
                      style: const TextStyle(
                          color: JetonsShell.slate400, fontSize: 12, height: 16 / 12))),
            ])),
    ]);
  }
}
