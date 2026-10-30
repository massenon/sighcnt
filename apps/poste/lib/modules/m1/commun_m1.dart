import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

/// Éléments communs aux écrans de M1 (`m1-patients.js`) : l'équivalent de `K.creer` + `K.actionsLigne` + `K.modifier` de la maquette, posé sur un
/// `TableauSigh`. Les RÈGLES sont dans `packages/domaine/lib/src/patients/`, rejouées sur les vecteurs des écrans réels ; ici, la mise en page.
const monoM1 = TextStyle(
    fontFamily: 'LiberationMono',
    color: JetonsShell.slate700,
    fontSize: 12,
    height: 16 / 12);

TextStyle styleM1({double t = 14, Color c = JetonsShell.slate700, FontWeight p = FontWeight.w400}) =>
    TextStyle(color: c, fontSize: t, height: t == 14 ? 20 / 14 : 16 / 12, fontWeight: p);

Widget tiret() => const Text('—', style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12));

DateTime? dateM1(Object? v) => DateTime.tryParse('${v ?? ''}');
String dateFrM1(Object? v) {
  final d = dateM1(v);
  return d == null ? '' : dateFR(d);
}

String dateHeureM1(Object? v) {
  final d = dateM1(v);
  return d == null ? '' : dateHeure(d);
}

String sansEspaces(Object? s) => '$s'.replaceAll(RegExp('[  ]'), ' ');

TonSigh tonDe(String t) => switch (t) {
      'success' => TonSigh.succes,
      'danger' => TonSigh.danger,
      'warning' => TonSigh.attention,
      'info' => TonSigh.info,
      'navy' => TonSigh.navy,
      _ => TonSigh.neutre,
    };

/// Les valeurs saisies (texte) → les valeurs enregistrées : nombres, cases, listes. Un nombre vide vaut `null` (la maquette ne stocke pas « 0 »).
Map<String, Object?> convertirSaisie(List<ChampDef> champs, Map<String, Object?> saisie) {
  final out = {...saisie};
  for (final c in champs) {
    if (c.type == TypeChamp.nombre && out.containsKey(c.nom)) {
      final v = out[c.nom];
      final n = v is num ? v : num.tryParse('${v ?? ''}'.replaceAll(',', '.'));
      out[c.nom] = n == null ? null : (n == n.truncate() ? n.truncate() : n);
    }
  }
  return out;
}

/// Les valeurs d'une fiche pour le formulaire : les nombres en texte, `null` en vide.
Map<String, Object?> valeursFormulaire(Fiche f) => {
      for (final e in f.entries)
        e.key: e.value is num ? '${e.value}' : (e.value is Map ? null : e.value)
    };

void imprimerM1(BuildContext ctx,
    {required String titre,
    String? sousTitre,
    List<(String, String)> cartouche = const [],
    List<BlocPiece> blocs = const [],
    List<Signature> signatures = const []}) {
  final c = ContexteEcran.of(ctx);
  afficherApercu(
      ctx,
      PieceA4(
          titre: titre,
          sousTitre: sousTitre,
          cartouche: cartouche,
          blocs: blocs,
          signatures: signatures,
          reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
          utilisateur: c.utilisateur,
          edite: c.aujourdhui));
}

/// `K.note` en tête d'écran : lecture seule annoncée (une restriction s'annonce).
Widget bandeauLectureSeule(ContexteEcran c) => (!c.droit.editer && c.droit.voir)
    ? Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: NoteSigh(
            'Lecture seule : le profil « ${c.role} » consulte cet écran sans pouvoir y écrire. Les droits se règlent dans la matrice des rôles.',
            ton: TonSigh.attention))
    : const SizedBox.shrink();

/// Un tableau adossé à une collection, avec création (modale), consultation (tiroir), modification et archivage motivé annulable.
/// Les commandes d'écriture sont ABSENTES (jamais grisées) sans le droit : créer / modifier → `droit.editer`, archiver → `droit.annuler`.
class RegistreM1 extends StatefulWidget {
  const RegistreM1({
    super.key,
    required this.collection,
    required this.colonnes,
    required this.entite,
    this.lignes,
    this.archive = false,
    this.filtres = const [],
    this.libelleNouveau,
    this.titreNouveau,
    this.champs,
    this.valeursInitiales,
    this.refuser,
    this.transformer,
    this.apresCreation,
    this.modifiable = true,
    this.detail,
    this.titreDetail,
    this.sousTitreDetail,
    this.etat,
    this.actionsSup,
    this.triInitial,
    this.sensInitial = 'asc',
    this.taillePage = 12,
    this.libelleRecherche = 'Rechercher…',
    this.messageVide = 'Aucun enregistrement.',
    this.taille = TailleModale.lg,
    this.titreModification,
    this.selectionnable = false,
    this.archivable = true,
    this.libelleConsulter = 'Consulter',
    this.libelleModifier = 'Modifier',
    this.creerVers,
  });

  /// `creerVers` : la création se fait sur une PAGE (gabarit de saisie), non en modale.
  final String? creerVers;

  final CollectionMagasin collection;
  final List<ColonneTableau> colonnes;
  final String entite;

  /// Les lignes à montrer, depuis les fiches actives (vue d'un onglet) ; `null` : toutes les actives.
  final List<Fiche> Function(ContexteEcran, List<Fiche> actives)? lignes;
  final bool archive;
  final List<FiltreTableau> filtres;
  final String? libelleNouveau;
  final String? titreNouveau;
  final List<ChampDef> Function(ContexteEcran, Fiche? existante)? champs;
  final Map<String, Object?> Function(ContexteEcran)? valeursInitiales;

  /// `avant` : le refus NOMMÉ de l'appelant (son propre message) ; rien n'est écrit.
  final String? Function(ContexteEcran, Map<String, Object?> saisie, Fiche? existante)? refuser;

  /// `transform` : la fiche à écrire depuis la saisie (peut porter des effets, comme la pièce de caisse d'un certificat).
  final Fiche Function(ContexteEcran, Map<String, Object?> saisie, Fiche? existante)? transformer;
  final void Function(ContexteEcran, Fiche creee)? apresCreation;
  final bool modifiable;
  final Widget Function(BuildContext, Fiche)? detail;
  final String Function(Fiche)? titreDetail;
  final String? Function(Fiche)? sousTitreDetail;
  final void Function(BuildContext, Fiche)? etat;
  final List<Widget> Function(BuildContext, Fiche)? actionsSup;
  final String? triInitial;
  final String sensInitial;
  final int taillePage;
  final String libelleRecherche;
  final String messageVide;
  final TailleModale taille;
  final String? titreModification;
  final bool selectionnable;
  final bool archivable;
  final String libelleConsulter;
  final String libelleModifier;

  @override
  State<RegistreM1> createState() => _RegistreM1State();
}

class _RegistreM1State extends State<RegistreM1> {
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
        message:
            'Archivage logique (RG-14) : la donnée reste consultable et l’opération est annulable.',
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
        defs,
        existante != null
            ? valeursFormulaire(existante)
            : (widget.valeursInitiales?.call(c) ?? const {}));
    afficherModale<void>(ctx,
        titre: existante == null
            ? (widget.titreNouveau ?? 'Nouvel enregistrement')
            : (widget.titreModification ?? 'Modifier l’enregistrement'),
        sousTitre: existante == null
            ? 'Les champs marqués d’un astérisque sont obligatoires.'
            : '${existante['reference'] ?? existante['numero'] ?? existante['code'] ?? existante['id']}',
        taille: widget.taille,
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
                    final brut = ctl.valider();
                    if (brut == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.',
                          type: TypeToast.erreur);
                      return;
                    }
                    final saisie = convertirSaisie(defs, brut);
                    final refus = widget.refuser?.call(c, saisie, existante);
                    if (refus != null) {
                      ToastsSigh.afficher(ctx, refus,
                          type: TypeToast.erreur, duree: const Duration(seconds: 8));
                      return;
                    }
                    final Fiche fiche;
                    try {
                      fiche = widget.transformer?.call(c, saisie, existante) ?? saisie;
                    } on PatRefus catch (e) {
                      ToastsSigh.afficher(ctx, e.message, type: TypeToast.erreur);
                      return;
                    }
                    fermer();
                    if (existante == null) {
                      final r = widget.collection.inserer({'statut': 'actif', ...fiche});
                      widget.apresCreation?.call(c, r.fiche);
                      ToastsSigh.afficher(ctx, '${widget.entite} créé.',
                          type: TypeToast.succes,
                          detail: '${r.fiche['libelle'] ?? r.fiche['designation'] ?? r.fiche['code'] ?? ''}'
                                  .isEmpty
                              ? null
                              : '${r.fiche['libelle'] ?? r.fiche['designation'] ?? r.fiche['code']}',
                          annuler: r.annuler,
                          messageAnnulation: 'Création annulée — la fiche est archivée.');
                    } else {
                      final annuler = widget.collection.mettreAJour(existante['id'], fiche);
                      ToastsSigh.afficher(ctx, 'Modifications enregistrées.',
                          type: TypeToast.succes, annuler: annuler);
                    }
                  }),
            ]);
  }

  void _ouvrirDetail(BuildContext ctx, Fiche f) {
    if (widget.detail == null) return;
    afficherTiroir<void>(ctx,
        titre: widget.titreDetail?.call(f) ?? '${f['reference'] ?? f['numero'] ?? f['code'] ?? 'Détail'}',
        sousTitre: widget.sousTitreDetail?.call(f),
        largeurMax: 672,
        corps: widget.detail!(ctx, f));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final toutes = widget.archive ? widget.collection.archivees : widget.collection.actives;
    final lignes = widget.lignes != null ? widget.lignes!(c, toutes) : toutes;
    final peutCreer = !widget.archive && c.droit.editer && (widget.champs != null || widget.creerVers != null) && widget.libelleNouveau != null;
    return TableauSigh(
      colonnes: widget.colonnes,
      lignes: lignes,
      filtres: widget.filtres,
      taillePage: widget.taillePage,
      selectionnable: widget.selectionnable,
      nomExport: widget.collection.nom,
      triInitial: widget.triInitial,
      sensInitial: widget.sensInitial,
      libelleRecherche: widget.libelleRecherche,
      messageVide: widget.messageVide,
      alClicLigne: widget.detail != null ? (f) => _ouvrirDetail(context, f) : null,
      actions: [
        if (peutCreer)
          BoutonSigh(
              libelle: widget.libelleNouveau!,
              icone: LucideIcons.plus,
              taille: TailleBouton.sm,
              onPressed: () => widget.creerVers != null ? c.aller(widget.creerVers!) : _saisir(context)),
      ],
      actionsLigne: (ctx, f) => widget.archive
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
              if (widget.actionsSup != null) ...widget.actionsSup!(ctx, f),
              if (widget.detail != null)
                BoutonIcone(
                    icone: LucideIcons.eye,
                    libelle: widget.libelleConsulter,
                    onPressed: () => _ouvrirDetail(ctx, f)),
              if (widget.etat != null)
                BoutonIcone(
                    icone: LucideIcons.printer,
                    libelle: 'Imprimer l’état',
                    onPressed: () => widget.etat!(ctx, f)),
              if (widget.modifiable && widget.champs != null && c.droit.editer)
                BoutonIcone(
                    icone: LucideIcons.pencil,
                    libelle: widget.libelleModifier,
                    onPressed: () => _saisir(ctx, existante: f)),
              if (widget.archivable && c.droit.annuler)
                BoutonIcone(
                    icone: LucideIcons.archive,
                    libelle: 'Archiver',
                    onPressed: () => _archiver(ctx, f)),
            ],
    );
  }
}

/// `K.section` : un intertitre et son contenu, dans un tiroir de détail.
Widget sectionM1(String titre, Widget corps) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(titre.toUpperCase(),
          style: const TextStyle(
              color: JetonsShell.slate500,
              fontSize: 12,
              height: 16 / 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6)),
      const SizedBox(height: 8),
      corps,
    ]));

Widget paragrapheM1(String t) => Text(t,
    style: const TextStyle(color: JetonsShell.slate600, fontSize: 14, height: 20 / 14));

/// Les deux colonnes d'un tableau de détail à deux lignes : « libellé / valeur ».
Widget enMono(String t) => Text(t,
    style: const TextStyle(
        fontFamily: 'LiberationMono',
        color: JetonsShell.slate800,
        fontSize: 12,
        height: 16 / 12));

/// Le dossier choisi dans la liste du répertoire (`optionsPatientsM1`) : « CNT/1/26 — NOM Prénom », triés par code.
List<OptionChamp> optionsPatientsM1(Magasin m) {
  final l = trierPar([...m.collection('patients').actives], (p) => p['code']);
  return [for (final p in l) OptionChamp('${p['code']}', '${p['code']} — ${p['nom']} ${p['prenom']}')];
}
