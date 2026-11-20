import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m1/commun_m1.dart' show valeursFormulaire;
import 'bloc_commun.dart';

/// `U.dataTable` + `K.creer` + `K.actionsLigne` de la maquette : un tableau adossé à une collection SANS onglets « Tous / Archivés », avec un bouton de
/// création nommé par l'écran, et par ligne « Imprimer », « Consulter », « Modifier », « Archiver ». Le contrôle métier de l'appelant ([avant]) refuse
/// EN LE DISANT (son propre toast, message ET détail) et rien n'est écrit ; il vaut à la création comme à la modification.
///
/// Les commandes d'écriture sont ABSENTES (jamais grisées) sans le droit : créer et modifier → `droit.editer`, archiver → `droit.annuler`.
class RegistreBloc extends StatefulWidget {
  const RegistreBloc({
    super.key,
    required this.collection,
    required this.colonnes,
    required this.entite,
    required this.prefixeId,
    this.libelleNouveau,
    this.titreNouveau,
    this.champs,
    this.lignes,
    this.valeursInitiales,
    this.avant,
    this.transformer,
    this.detail,
    this.titreDetail,
    this.actionsSup,
    this.modifiable = true,
    this.taille = TailleModale.lg,
    this.taillePage = 12,
    this.titre,
    this.triInitial,
    this.sensInitial = 'asc',
    this.messageVide = 'Aucun enregistrement.',
    this.actionsBarre = const [],
    this.nomExport,
  });

  final CollectionMagasin collection;
  final List<ColonneTableau> colonnes;

  /// `opts.entite` : « CPA créé. »
  final String entite;
  final String prefixeId;
  final String? libelleNouveau;
  final String? titreNouveau;
  final List<ChampDef> Function(ContexteEcran, Fiche? existante)? champs;
  final List<Fiche> Function(List<Fiche> actives)? lignes;
  final Map<String, Object?> Function(ContexteEcran)? valeursInitiales;

  /// `opts.avant(v, record)` : le refus NOMMÉ, ou `null`.
  final BlocRefus? Function(ContexteEcran, Map<String, Object?> saisie, Fiche? existante)? avant;

  /// `opts.transform` : la fiche à écrire depuis la saisie (création : sans fiche existante ; modification : avec).
  final Fiche Function(ContexteEcran, Map<String, Object?> saisie, Fiche? existante)? transformer;
  final Widget Function(BuildContext, Fiche)? detail;
  final String Function(Fiche)? titreDetail;
  final List<Widget> Function(BuildContext, Fiche)? actionsSup;
  final bool modifiable;
  final TailleModale taille;
  final int taillePage;
  final String? titre;
  final String? triInitial;
  final String sensInitial;
  final String messageVide;
  final List<Widget> actionsBarre;
  final String? nomExport;

  @override
  State<RegistreBloc> createState() => _RegistreBlocState();
}

class _RegistreBlocState extends State<RegistreBloc> {
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

  Future<void> _archiver(BuildContext ctx, Fiche f) async {
    final motif = await confirmerAvecMotif(ctx,
        titre: 'Archiver cet enregistrement ?',
        message: 'Archivage logique (RG-14) : la donnée reste consultable et l’opération est annulable.',
        libelleOk: 'Archiver',
        dangereux: true);
    if (motif == null || !ctx.mounted) return;
    final annuler = widget.collection.archiver(f['id']);
    widget.collection.mettreAJour(f['id'], {'_motifArchivage': motif});
    ToastsSigh.afficher(ctx, 'Enregistrement archivé.',
        type: TypeToast.succes, annuler: annuler, messageAnnulation: 'Archivage annulé.');
  }

  void _saisir(BuildContext ctx, {Fiche? existante}) {
    final c = ContexteEcran.of(ctx);
    final defs = widget.champs!(c, existante);
    final ctl = ControleurFormulaire(
        defs, existante != null ? valeursFormulaire(existante) : (widget.valeursInitiales?.call(c) ?? const {}));
    afficherModale<void>(ctx,
        titre: existante == null ? widget.titreNouveau ?? 'Nouvel enregistrement' : 'Modifier l’enregistrement',
        sousTitre: existante == null
            ? 'Les champs marqués d’un astérisque sont obligatoires.'
            : '${existante['reference'] ?? existante['numero'] ?? existante['code'] ?? existante['id']}',
        taille: widget.taille,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: existante == null ? 'Créer' : 'Enregistrer',
                  icone: existante == null ? LucideIcons.plus : LucideIcons.save,
                  onPressed: () {
                    final brut = ctl.valider();
                    if (brut == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    final saisie = {...brut};
                    final refus = widget.avant?.call(c, saisie, existante);
                    if (refus != null) {
                      toastRefus(ctx, refus);
                      return;
                    }
                    final fiche = widget.transformer?.call(c, saisie, existante) ?? saisie;
                    fermer();
                    if (existante == null) {
                      final r = widget.collection.inserer({'statut': 'actif', ...fiche}, prefixe: widget.prefixeId);
                      final f = r.fiche;
                      final detail = '${f['libelle'] ?? f['designation'] ?? f['code'] ?? ''}';
                      ToastsSigh.afficher(ctx, '${widget.entite} créé.',
                          type: TypeToast.succes,
                          detail: detail.isEmpty ? null : detail,
                          annuler: r.annuler,
                          messageAnnulation: 'Création annulée — la fiche est archivée.');
                    } else {
                      final annuler = widget.collection.mettreAJour(existante['id'], fiche);
                      ToastsSigh.afficher(ctx, 'Modifications enregistrées.', type: TypeToast.succes, annuler: annuler);
                    }
                  }),
            ]);
  }

  void _ouvrirDetail(BuildContext ctx, Fiche f) {
    if (widget.detail == null) return;
    afficherTiroir<void>(ctx,
        titre: widget.titreDetail?.call(f) ?? '${f['reference'] ?? f['numero'] ?? f['code'] ?? 'Détail'}',
        largeurMax: 672,
        corps: widget.detail!(ctx, f));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final actives = widget.collection.actives;
    final lignes = widget.lignes != null ? widget.lignes!(actives) : actives;
    return TableauSigh(
      titre: widget.titre,
      colonnes: widget.colonnes,
      lignes: lignes,
      taillePage: widget.taillePage,
      nomExport: widget.nomExport ?? widget.collection.nom,
      triInitial: widget.triInitial,
      sensInitial: widget.sensInitial,
      messageVide: widget.messageVide,
      actions: [
        ...widget.actionsBarre,
        if (c.droit.editer && widget.libelleNouveau != null && widget.champs != null)
          BoutonSigh(
              libelle: widget.libelleNouveau!,
              icone: LucideIcons.plus,
              taille: TailleBouton.sm,
              onPressed: () => _saisir(context)),
      ],
      actionsLigne: (ctx, f) => [
        if (widget.actionsSup != null) ...widget.actionsSup!(ctx, f),
        if (widget.detail != null)
          BoutonIcone(icone: LucideIcons.eye, libelle: 'Consulter', onPressed: () => _ouvrirDetail(ctx, f)),
        if (widget.modifiable && widget.champs != null && c.droit.editer)
          BoutonIcone(icone: LucideIcons.pencil, libelle: 'Modifier', onPressed: () => _saisir(ctx, existante: f)),
        if (c.droit.annuler)
          BoutonIcone(icone: LucideIcons.archive, libelle: 'Archiver', onPressed: () => _archiver(ctx, f)),
      ],
    );
  }
}
