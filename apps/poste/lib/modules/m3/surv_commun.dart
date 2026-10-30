import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

/// Briques communes aux six écrans de surveillance de M3 (`m3-administrations`, `-surveillance`, `-transfusion`, `-glasgow`, `-rapport`,
/// `-visites-patients`) : les listes de choix de la maquette (`optionsPatients3`, `optionsSoignants`, `nomSoignant`, `patientParCode3`), les
/// dates, et le REGISTRE à formulaire (`K.creer` + `K.actionsLigne` + `K.registre` de la maquette).

bool vrai(Object? v) => v != null && v != '' && v != false;

/// `patientParCode3` : le patient actif portant ce code dossier.
Fiche? patientParCode(Magasin m, Object? code) => m
    .collection('patients')
    .actives
    .where((p) => p['code'] == code)
    .firstOrNull;

/// `optionsPatients3` : « code — nom prénom », triés par code (tri naturel de la maquette).
List<OptionChamp> optionsPatientsM3(Magasin m) => [
      for (final p in trierPar(m.collection('patients').actives, (p) => p['code']))
        OptionChamp('${p['code']}', '${p['code']} — ${p['nom']} ${p['prenom']}')
    ];

List<Fiche> soignantsActifs(Magasin m) => m.collection('soignants').actives;

/// `optionsSoignants(filtre)` : « nom — poste », valeur = identifiant du soignant.
List<OptionChamp> optionsSoignants(Magasin m, [bool Function(Fiche)? filtre]) => [
      for (final x in soignantsActifs(m).where(filtre ?? (_) => true))
        OptionChamp('${x['id']}', '${x['nomComplet']} — ${x['poste']}')
    ];

String nomSoignant(Magasin m, Object? id) {
  final x = soignantsActifs(m).where((y) => y['id'] == id).firstOrNull;
  return x == null ? '—' : '${x['nomComplet']}';
}

/// `C.dateFR` d'une date seule ou d'un horodatage ; vide → « — » est laissé à l'appelant.
String dateTexte(Object? v) {
  final s = '${v ?? ''}';
  final d = hosVersDate(s.length >= 10 ? s.substring(0, 10) : s);
  return d == null ? '' : dateFR(d);
}

/// `C.dateHeure` : « 15/08/2026 à 11h00 » (un horodatage à fuseau est ramené à l'heure locale du poste, comme le navigateur).
String dateHeureTexte(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}')?.toLocal();
  return d == null ? '' : dateHeure(d);
}

/// Le kit n'a pas de champ date-heure (limite dite, E367) : deux champs — la date, puis l'heure `HH:mm`.
List<ChampDef> champsDateHeure(String nom, String libelle, {bool requis = true}) => [
      ChampDef(nom: '${nom}_d', libelle: 'Date $libelle', type: TypeChamp.date, requis: requis),
      ChampDef(
          nom: '${nom}_h',
          libelle: 'Heure $libelle (HH:mm)',
          requis: requis,
          indicatif: 'HH:mm',
          valider: (v, _) => RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch('$v')
              ? null
              : 'Heure attendue au format HH:mm.'),
    ];

/// Valeurs initiales d'un champ date-heure à partir de `AAAA-MM-JJTHH:mm`.
Map<String, Object?> separerDateHeure(String nom, Object? v) {
  final s = '${v ?? ''}';
  if (s.length < 16) return {};
  return {'${nom}_d': s.substring(0, 10), '${nom}_h': s.substring(11, 16)};
}

String? joindreDateHeure(Map<String, Object?> v, String nom) =>
    vrai(v['${nom}_d']) && vrai(v['${nom}_h']) ? '${v['${nom}_d']}T${v['${nom}_h']}' : null;

/// `K.section(titre, contenu)` : un intertitre de fiche suivi de son contenu.
Widget sectionDetail(String titre, Widget contenu) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(titre,
              style: const TextStyle(
                  color: Color(0xFF334155),
                  fontSize: 14,
                  height: 20 / 14,
                  fontWeight: FontWeight.w600))),
      contenu,
    ]));

Widget paragrapheDetail(String texte) => Text(texte,
    style: const TextStyle(color: Color(0xFF475569), fontSize: 14, height: 20 / 14));

TonSigh tonDe(String t) => switch (t) {
      'danger' => TonSigh.danger,
      'warning' => TonSigh.attention,
      'success' => TonSigh.succes,
      _ => TonSigh.neutre,
    };

/// Le registre à formulaire de la maquette : tableau (recherche, filtres, tri, pagination, sélection), commande de création, consultation en tiroir,
/// modification en modale, archivage ANNULABLE (RG-14) — chaque commande d'écriture est ABSENTE (jamais grisée) sans le droit de l'ÉCRAN.
///
/// `construire(valeurs, fiche)` est le `transform` de la maquette : il rend la fiche à insérer (création) ou le correctif (modification).
class RegistreFormulaire extends StatefulWidget {
  const RegistreFormulaire({
    super.key,
    required this.collection,
    required this.lignes,
    required this.colonnes,
    required this.titreFiche,
    required this.detail,
    required this.champs,
    required this.construire,
    this.libelleNouveau,
    this.titreCreation = '',
    this.sousTitreCreation,
    this.toastCreation = 'Enregistrement créé.',
    this.libelleCreer = 'Créer',
    this.initiales,
    this.tailleCreation = TailleModale.md,
    this.modifiable = true,
    this.filtres = const [],
    this.nomExport = 'export',
    this.messageVide = 'Aucun enregistrement.',
    this.taillePage = 12,
    this.archivable = true,
    this.messageArchivage =
        'Archivage logique (RG-14) : la donnée reste consultable et l’opération est annulable.',
    this.actionsLigneSupp,
    this.piedFiche = false,
    this.apresCreation,
    this.avant,
    this.libelleRecherche = 'Rechercher…',
    this.prefixe = 'ID',
    this.groupe = false,
    this.toastApres,
  });

  final CollectionMagasin collection;

  /// Les lignes à afficher, déjà ordonnées (la maquette trie avant de rendre).
  final List<Fiche> lignes;
  final List<ColonneTableau> colonnes;
  final String Function(Fiche) titreFiche;
  final Widget Function(BuildContext, Fiche) detail;

  /// Les champs du formulaire ; la fiche est `null` à la création.
  final List<ChampDef> Function(Fiche? fiche) champs;
  final Fiche Function(Map<String, Object?> valeurs, Fiche? fiche) construire;
  final String? libelleNouveau;
  final String titreCreation;
  final String? sousTitreCreation;
  final String toastCreation;
  final String libelleCreer;
  final Map<String, Object?> Function(Fiche? fiche)? initiales;
  final TailleModale tailleCreation;

  /// Faux : pas de commande « Modifier » (E366 — la maquette lève une exception, l'écran ne la porte pas).
  final bool modifiable;
  final List<FiltreTableau> filtres;
  final String nomExport;
  final String messageVide;
  final int taillePage;
  final bool archivable;
  final String messageArchivage;
  final List<Widget> Function(BuildContext, Fiche)? actionsLigneSupp;

  /// Vrai : « Modifier » et « Archiver » figurent aussi au pied de la fiche (`K.crud`).
  final bool piedFiche;
  final void Function(Fiche creee)? apresCreation;

  /// Contrôle métier de l'appelant : un message refuse l'enregistrement (rien n'est écrit).
  final String? Function(Map<String, Object?> valeurs, Fiche? fiche)? avant;
  final String libelleRecherche;
  final String prefixe;

  /// Remplace le message de création par défaut (la surveillance transfusionnelle signale un protocole incomplet ou un incident).
  final void Function(BuildContext ctx, Fiche creee, VoidCallback annuler)? toastApres;

  /// Vrai : actions de sélection multiple de `K.crud` (imprimer la sélection, archiver).
  final bool groupe;

  @override
  State<RegistreFormulaire> createState() => _EtatRegistre();
}

class _EtatRegistre extends State<RegistreFormulaire> {
  CollectionMagasin get _col => widget.collection;

  void _formulaire(BuildContext ctx, ContexteEcran c, Fiche? fiche) {
    final champs = widget.champs(fiche);
    final ctl = ControleurFormulaire(
        champs, {...?widget.initiales?.call(fiche)});
    final creation = fiche == null;
    afficherModale<void>(ctx,
            titre: creation
                ? widget.titreCreation
                : 'Modifier l’enregistrement ${widget.titreFiche(fiche)}',
            sousTitre: creation ? widget.sousTitreCreation : null,
            taille: widget.tailleCreation,
            corps: FormulaireSigh(controleur: ctl),
            pied: (fermer) => [
                  BoutonSigh(
                      libelle: 'Annuler',
                      variante: VarianteBouton.secondaire,
                      onPressed: fermer),
                  BoutonSigh(
                      libelle: creation ? widget.libelleCreer : 'Enregistrer',
                      icone: LucideIcons.check,
                      onPressed: () {
                        final v = ctl.valider();
                        if (v == null) {
                          ToastsSigh.afficher(
                              ctx, 'Le formulaire comporte des erreurs.',
                              type: TypeToast.erreur);
                          return;
                        }
                        final refus = widget.avant?.call(v, fiche);
                        if (refus != null) {
                          ToastsSigh.afficher(ctx, refus, type: TypeToast.erreur);
                          return;
                        }
                        final donnees = widget.construire(v, fiche);
                        fermer();
                        if (creation) {
                          final r = _col.inserer(donnees, prefixe: widget.prefixe);
                          widget.apresCreation?.call(r.fiche);
                          if (widget.toastApres != null) {
                            widget.toastApres!(ctx, r.fiche, r.annuler);
                          } else {
                            ToastsSigh.afficher(ctx, widget.toastCreation,
                                type: TypeToast.succes, annuler: r.annuler);
                          }
                        } else {
                          final annuler = _col.mettreAJour(fiche['id'], donnees);
                          ToastsSigh.afficher(ctx, 'Modifications enregistrées.',
                              type: TypeToast.succes, annuler: annuler);
                        }
                      }),
                ])
        .whenComplete(ctl.dispose);
  }

  Future<void> _archiver(BuildContext ctx, List<Fiche> fiches) async {
    final n = fiches.length;
    final ok = await confirmerSigh(ctx,
        titre: n == 1 ? 'Archiver cet enregistrement ?' : 'Archiver $n enregistrement(s) ?',
        message: widget.messageArchivage,
        libelleOk: 'Archiver',
        dangereux: true);
    if (!ok || !ctx.mounted) return;
    final annulations = [for (final f in fiches) _col.archiver(f['id'])];
    ToastsSigh.afficher(ctx, n == 1 ? 'Enregistrement archivé.' : '$n enregistrement(s) archivé(s).',
        type: TypeToast.succes, annuler: () {
      for (final u in annulations) {
        u();
      }
    });
  }

  void _ouvrir(BuildContext ctx, ContexteEcran c, Fiche f) => afficherTiroir<void>(ctx,
      titre: widget.titreFiche(f),
      largeurMax: 672,
      corps: widget.detail(ctx, f),
      pied: widget.piedFiche
          ? (fermer) => [
                if (widget.modifiable && c.droit.editer)
                  BoutonSigh(
                      libelle: 'Modifier',
                      icone: LucideIcons.pencil,
                      variante: VarianteBouton.secondaire,
                      onPressed: () {
                        fermer();
                        _formulaire(ctx, c, f);
                      }),
                if (widget.archivable && c.droit.annuler)
                  BoutonSigh(
                      libelle: 'Archiver',
                      icone: LucideIcons.archive,
                      variante: VarianteBouton.danger,
                      onPressed: () {
                        fermer();
                        _archiver(ctx, [f]);
                      }),
              ]
          : null);

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return TableauSigh(
      colonnes: widget.colonnes,
      lignes: widget.lignes,
      filtres: widget.filtres,
      taillePage: widget.taillePage,
      selectionnable: true,
      nomExport: widget.nomExport,
      messageVide: widget.messageVide,
      libelleRecherche: widget.libelleRecherche,
      alClicLigne: (f) => _ouvrir(context, c, f),
      actions: [
        if (c.droit.editer && widget.libelleNouveau != null)
          BoutonSigh(
              libelle: widget.libelleNouveau!,
              icone: LucideIcons.plus,
              taille: TailleBouton.sm,
              onPressed: () => _formulaire(context, c, null)),
      ],
      actionsGroupe: widget.groupe
          ? (context, sel, effacer) => [
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
                        _archiver(context, sel);
                        effacer();
                      }),
              ]
          : null,
      actionsLigne: (ctx, f) => [
        ...?widget.actionsLigneSupp?.call(ctx, f),
        BoutonIcone(
            icone: LucideIcons.eye,
            libelle: 'Consulter',
            onPressed: () => _ouvrir(ctx, c, f)),
        if (widget.modifiable && c.droit.editer)
          BoutonIcone(
              icone: LucideIcons.pencil,
              libelle: 'Modifier',
              onPressed: () => _formulaire(ctx, c, f)),
        if (widget.archivable && c.droit.annuler)
          BoutonIcone(
              icone: LucideIcons.archive,
              libelle: 'Archiver',
              onPressed: () => _archiver(ctx, [f])),
      ],
    );
  }
}
