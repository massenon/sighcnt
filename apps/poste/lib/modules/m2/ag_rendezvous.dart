import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'ag_commun.dart';
import 'img_commun.dart' show styleMono;

/// `K.crud` de la maquette, pour les registres de l'accueil : KPI sur la collection ENTIÈRE, plage de dates (un filtre), liste principale = une VUE
/// (`filtreBase`), onglets supplémentaires, archivage annulable avec motif (RG-14), formulaire de création / d'édition, fiche en tiroir.
/// Les commandes d'écriture sont ABSENTES (jamais grisées) sans le droit : « Nouveau » et « Modifier » → `editer` ; « Archiver » / « Restaurer » → `annuler`.
class EcranCrudAg extends StatefulWidget {
  const EcranCrudAg({
    super.key,
    required this.collection,
    required this.entite,
    this.entiteP,
    required this.colonnes,
    this.filtres = const [],
    this.kpis,
    this.intro,
    this.filtreBase,
    this.libelleListe,
    this.ongletsSupp,
    this.champPlage,
    this.ouvrirFormulaire,
    this.detail,
    this.etat,
    this.triInitial,
    this.sensInitial = 'asc',
    this.taillePage = 12,
    this.titreFiche,
    this.sousTitreFiche,
  });

  final String collection;
  final String entite;
  final String? entiteP;
  final List<ColonneTableau> colonnes;
  final List<FiltreTableau> filtres;
  final List<KpiSigh> Function(BuildContext, List<Fiche> actives)? kpis;
  final Widget Function(BuildContext)? intro;
  final bool Function(Fiche)? filtreBase;
  final String? libelleListe;
  final List<OngletDef> Function(BuildContext, List<Fiche> actives)? ongletsSupp;
  final String? champPlage;

  /// Ouvre le formulaire (création si `record` est nul).
  final void Function(BuildContext ecran, Fiche? record)? ouvrirFormulaire;
  final Widget Function(BuildContext, Fiche)? detail;
  final void Function(BuildContext, Fiche)? etat;
  final String? triInitial;
  final String sensInitial;
  final int taillePage;
  final String Function(Fiche)? titreFiche;
  final String Function(Fiche)? sousTitreFiche;

  @override
  State<EcranCrudAg> createState() => _EtatCrudAg();
}

class _EtatCrudAg extends State<EcranCrudAg> {
  String _du = '', _au = '';

  String get _p => widget.entiteP ?? '${widget.entite}s';

  bool _base(Fiche r) => widget.filtreBase?.call(r) ?? true;

  bool _dansPlage(Fiche r) =>
      widget.champPlage == null || agDansPlage(r, widget.champPlage!, _du, _au);

  Future<void> _archiver(BuildContext ecran, List<Fiche> fiches) async {
    final c = ContexteEcran.of(ecran);
    final n = fiches.length;
    final motif = await confirmerAvecMotif(ecran,
        titre: n == 1 ? 'Archiver cet enregistrement ?' : 'Archiver $n enregistrement(s) ?',
        message:
            'L’enregistrement ne sera pas supprimé : il est archivé et reste consultable dans l’onglet « Archivés ». L’opération est journalisée et peut être annulée.',
        libelleOk: 'Archiver',
        dangereux: true);
    if (motif == null) return;
    final col = c.magasin.collection(widget.collection);
    final undos = <VoidCallback>[];
    for (final f in fiches) {
      col.mettreAJour(f['id'], {'_motifArchivage': motif});
      undos.add(col.archiver(f['id']));
    }
    if (ecran.mounted) {
      ToastsSigh.afficher(
          ecran,
          n == 1 ? 'Enregistrement archivé.' : '$n enregistrement(s) archivé(s).',
          type: TypeToast.succes,
          messageAnnulation: 'Archivage annulé.',
          annuler: () {
            for (final u in undos) {
              u();
            }
          });
    }
  }

  void _fiche(BuildContext ecran, Fiche f) {
    final c = ContexteEcran.of(ecran);
    final titre = f['nomComplet'] ?? f['designation'] ?? f['libelle'] ?? f['patient'] ?? f['code'] ?? f['reference'] ?? f['numero'] ?? 'Détail';
    afficherTiroir<void>(ecran,
        titre: widget.titreFiche?.call(f) ?? '$titre',
        sousTitre: widget.sousTitreFiche?.call(f) ?? '${f['code'] ?? f['reference'] ?? f['numero'] ?? ''}',
        largeurMax: 672,
        corps: widget.detail?.call(ecran, f) ?? const SizedBox(),
        pied: (fermer) => [
              if (widget.etat != null)
                BoutonSigh(
                    libelle: 'Imprimer',
                    icone: LucideIcons.printer,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => widget.etat!(ecran, f)),
              if (c.droit.editer && widget.ouvrirFormulaire != null)
                BoutonSigh(
                    libelle: 'Modifier',
                    icone: LucideIcons.pencil,
                    onPressed: () {
                      fermer();
                      widget.ouvrirFormulaire!(ecran, f);
                    }),
              if (c.droit.annuler)
                BoutonSigh(
                    libelle: 'Archiver',
                    icone: LucideIcons.archive,
                    variante: VarianteBouton.danger,
                    onPressed: () {
                      fermer();
                      _archiver(ecran, [f]);
                    }),
            ]);
  }

  Future<void> _imprimerSelection(BuildContext ecran, List<Fiche> sel) {
    final c = ContexteEcran.of(ecran);
    return afficherApercu(
        ecran,
        PieceA4(
          titre: 'Sélection — $_p',
          sousTitre: '${sel.length} enregistrement(s)',
          reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
          tableaux: [
            TableauEtat(colonnes: [
              for (final k in widget.colonnes)
                ColonneEtat(libelle: k.libelle, valeur: (l) => k.enTexte(l))
            ], lignes: sel)
          ],
        ));
  }

  TableauSigh _tableau(BuildContext ecran, ContexteEcran c, List<Fiche> lignes,
      {required bool archive}) {
    final col = c.magasin.collection(widget.collection);
    return TableauSigh(
      colonnes: widget.colonnes,
      lignes: lignes,
      filtres: widget.filtres,
      taillePage: widget.taillePage,
      selectionnable: !archive,
      nomExport: widget.collection,
      triInitial: widget.triInitial,
      sensInitial: widget.sensInitial,
      libelleRecherche: 'Rechercher un ${widget.entite}…',
      messageVide: archive ? 'Aucun enregistrement archivé.' : 'Aucun ${widget.entite} enregistré.',
      indiceVide: archive ? null : 'Utiliser le bouton « Nouveau » pour créer le premier enregistrement.',
      alClicLigne: (f) => _fiche(ecran, f),
      actions: [
        if (!archive && c.droit.editer && widget.ouvrirFormulaire != null)
          BoutonSigh(
              libelle: 'Nouveau',
              icone: LucideIcons.plus,
              taille: TailleBouton.sm,
              onPressed: () => widget.ouvrirFormulaire!(ecran, null)),
      ],
      actionsGroupe: archive
          ? null
          : (context, sel, effacer) => [
                BoutonSigh(
                    libelle: 'Imprimer la sélection',
                    icone: LucideIcons.printer,
                    taille: TailleBouton.sm,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => _imprimerSelection(ecran, sel)),
                if (c.droit.annuler)
                  BoutonSigh(
                      libelle: 'Archiver',
                      icone: LucideIcons.archive,
                      taille: TailleBouton.sm,
                      variante: VarianteBouton.danger,
                      onPressed: () {
                        _archiver(ecran, sel);
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
                      col.restaurer(f['id']);
                      ToastsSigh.afficher(ecran, 'Enregistrement restauré.',
                          type: TypeToast.succes);
                    }),
            ]
          : [
              BoutonIcone(
                  icone: LucideIcons.eye,
                  libelle: 'Consulter',
                  onPressed: () => _fiche(ecran, f)),
              if (widget.etat != null)
                BoutonIcone(
                    icone: LucideIcons.printer,
                    libelle: 'Imprimer l’état',
                    onPressed: () => widget.etat!(ecran, f)),
              if (c.droit.editer && widget.ouvrirFormulaire != null)
                BoutonIcone(
                    icone: LucideIcons.pencil,
                    libelle: 'Modifier',
                    onPressed: () => widget.ouvrirFormulaire!(ecran, f)),
              if (c.droit.annuler)
                BoutonIcone(
                    icone: LucideIcons.archive,
                    libelle: 'Archiver',
                    onPressed: () => _archiver(ecran, [f])),
            ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection(widget.collection);
    return ListenableBuilder(
        listenable: col,
        builder: (context, _) {
          final actives = col.actives;
          final liste = [for (final r in actives) if (_base(r) && _dansPlage(r)) r];
          final archives = [for (final r in col.archivees) if (_dansPlage(r)) r];
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
                  child: KpiGrilleSigh(kpis: widget.kpis!(context, actives))),
            if (widget.intro != null)
              Padding(padding: const EdgeInsets.only(bottom: 16), child: widget.intro!(context)),
            if (widget.champPlage != null)
              Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: BarrePlageAg(
                      aujourdhui: c.aujourdhui,
                      alChanger: (du, au) => setState(() {
                            _du = du;
                            _au = au;
                          }))),
            OngletsSigh(onglets: [
              OngletDef(
                  id: 'liste',
                  libelle: widget.libelleListe ?? 'Tous les $_p',
                  compte: actives.where(_base).length,
                  construire: (ctx) => _tableau(context, c, liste, archive: false)),
              ...?widget.ongletsSupp?.call(context, actives),
              OngletDef(
                  id: 'archives',
                  libelle: 'Archivés',
                  compte: col.archivees.length,
                  construire: (ctx) => _tableau(context, c, archives, archive: true)),
            ]),
          ]);
        });
  }
}

// --- colonnes communes ---------------------------------------------------------------------------------------------------------------------

/// `colDate(label)` : la date puis l'heure, sur deux lignes ; le tri se fait sur l'INSTANT.
ColonneTableau colDateAg(String libelle) => ColonneTableau(
    cle: 'date',
    libelle: libelle,
    sansCoupure: true,
    valeur: (r) => agDate(r['date'])?.millisecondsSinceEpoch,
    texte: (r) {
      final d = agDate(r['date']);
      return d == null ? 'NaN/NaN/NaN NaNhNaN' : '${dateFR(d)} ${heure(d)}';
    },
    rendu: (_, r) {
      final d = agDate(r['date']);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(d == null ? 'NaN/NaN/NaN' : dateFR(d),
            style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14)),
        Text(d == null ? 'NaNhNaN' : heure(d),
            style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
      ]);
    });

/// `colPatient` : le nom puis le code du dossier.
ColonneTableau colPatientAg() => ColonneTableau(
    cle: 'patient',
    libelle: 'Patient',
    texte: (r) => '${r['patient'] ?? ''} ${r['patientCode'] ?? ''}'.trim(),
    rendu: (_, r) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('${r['patient'] ?? ''}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: JetonsShell.slate800,
                  fontSize: 14,
                  height: 20 / 14,
                  fontWeight: FontWeight.w500)),
          Text('${r['patientCode'] ?? ''}',
              style: const TextStyle(
                  fontFamily: 'LiberationMono',
                  color: JetonsShell.slate400,
                  fontSize: 12,
                  height: 16 / 12)),
        ]));

ColonneTableau colReferenceAg([String libelle = 'N°']) => ColonneTableau(
    cle: 'reference',
    libelle: libelle,
    sansCoupure: true,
    texte: (r) => '${r['reference'] ?? '—'}',
    rendu: (_, r) => Text('${r['reference'] ?? '—'}', style: styleMono));

// --- m2-rendezvous -------------------------------------------------------------------------------------------------------------------------

/// `m2-rendezvous` — « Rendez-vous & visites » : les rendez-vous PRIS, les passages SPONTANÉS, les personnes non enregistrées et les affaires privées.
/// L'agenda est apuré par ONGLET (un honoré EST la consultation : l'archiver effacerait l'acte) ; honoré, reporté, non honoré sont trois suites distinctes.
class EcranRendezVous extends StatelessWidget with EcranMaquette {
  const EcranRendezVous({super.key});

  @override
  String get titre => 'Rendez-vous & visites';

  @override
  String get description =>
      'Prise de rendez-vous et enregistrement des venues — patients, individus non enregistrés, affaires privées.';

  @override
  String get regle =>
      'Écran UNIQUE (Bug 3 des Instructions, fusion achevée le 06/09/2026) : rendez-vous de consultation, de contrôle, passages sans rendez-vous et affaires privées s’enregistrent ici, pour un patient du répertoire ou une personne non enregistrée — dont on relève nom, prénom, quartier et téléphone sans lui ouvrir de dossier ni consommer de code CNT (RG-01). Deux filtres les distinguent — « Venue » et « Venu » — parce qu’une même population lue selon deux axes vaut mieux que deux registres qui divergent. La plage de dates FILTRE la liste : « les rendez-vous du 21 août » ne se répond pas en triant.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(
          libelle: 'Agenda',
          icone: LucideIcons.calendarDays,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m2-agenda')),
      if (c.droit.editer)
        BoutonSigh(
            libelle: 'Passage sans rendez-vous',
            icone: LucideIcons.userCheck,
            onPressed: () => passageSansRendezVousAg(context)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final aujourdhui = c.aujourdhui;
    List<OptionChamp> medecins() => optionsMedecinsAg(c);
    return EcranCrudAg(
      collection: 'consultations',
      entite: 'rendez-vous',
      entiteP: 'rendez-vous',
      triInitial: 'date',
      sensInitial: 'desc',
      libelleListe: 'Agenda — à venir, reportés, non honorés',
      filtreBase: (r) => !agEstApure(r),
      champPlage: 'date',
      colonnes: [
        colReferenceAg(),
        colDateAg('Date et heure'),
        colPatientAg(),
        const ColonneTableau(cle: 'medecin', libelle: 'Praticien'),
        const ColonneTableau(cle: 'motif', libelle: 'Motif'),
        ColonneTableau(
            cle: 'type',
            libelle: 'Type',
            rendu: (_, r) => BadgeSigh('${r['type'] ?? ''}',
                ton: r['type'] == 'Urgence' ? TonSigh.danger : TonSigh.navy)),
        ColonneTableau(
            cle: 'statut',
            libelle: 'Statut',
            texte: (r) => '${r['statut'] ?? ''}',
            rendu: (_, r) => statutBadge(r['statut'])),
      ],
      filtres: [
        const FiltreTableau(nom: 'statut', libelle: 'Statut', options: [
          OptionChamp('planifiee', 'Planifiée'),
          OptionChamp('en_cours', 'En cours'),
          OptionChamp('reporte', 'Reporté'),
          OptionChamp('non_honore', 'Non honoré'),
          OptionChamp('terminee', 'Honoré'),
        ]),
        FiltreTableau(
            nom: 'souffrance',
            libelle: 'À statuer',
            options: const [
              OptionChamp('oui', 'Date passée, rien de constaté'),
              OptionChamp('non', 'À jour')
            ],
            correspond: (r, v) => agFiltreSouffrance(r, v, aujourdhui)),
        FiltreTableau(
            nom: 'type',
            libelle: 'Type',
            options: [for (final t in agTypesRdv) OptionChamp(t)]),
        FiltreTableau(nom: 'medecin', libelle: 'Praticien', options: medecins()),
        FiltreTableau(
            nom: 'venu',
            libelle: 'Venu',
            options: const [
              OptionChamp('patient', 'Patients du répertoire'),
              OptionChamp('externe', 'Personnes non enregistrées')
            ],
            correspond: agFiltreVenu),
        FiltreTableau(
            nom: 'venue',
            libelle: 'Venue',
            options: const [
              OptionChamp('rdv', 'Sur rendez-vous'),
              OptionChamp('sans', 'Sans rendez-vous')
            ],
            correspond: agFiltreVenue),
      ],
      kpis: (ctx, rows) {
        final k = agKpisRendezVous(rows, aujourdhui);
        return [
          kpiAg(k[0], LucideIcons.calendarDays, TonSigh.navy),
          kpiAg(k[1], LucideIcons.clock, TonSigh.info),
          kpiAg(k[2], LucideIcons.calendarClock, TonSigh.attention),
          kpiAg(k[3], LucideIcons.userX, TonSigh.danger),
        ];
      },
      ongletsSupp: (ctx, actives) {
        final honores = [for (final r in actives) if (agEstApure(r)) r];
        return [
          OngletDef(
              id: 'honores',
              libelle: 'Honorés (apurés de l’agenda)',
              compte: honores.length,
              construire: (_) => _Honores(honores)),
        ];
      },
      ouvrirFormulaire: (ecran, rec) => formulaireRendezVousAg(ecran, record: rec),
      detail: detailRendezVousAg,
      etat: imprimerConsultationAg,
    );
  }
}

/// L'onglet « Honorés (apurés de l'agenda) » : sortis de l'agenda, restés au dossier — un rendez-vous honoré est la consultation elle-même.
class _Honores extends StatelessWidget {
  const _Honores(this.rows);
  final List<Fiche> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const VideSigh('Aucun rendez-vous honoré.', icone: LucideIcons.circleCheck);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const NoteSigh(
          'Ces rendez-vous ont été honorés : ils sont sortis de l’agenda mais restent au dossier du patient — un rendez-vous honoré est la consultation elle-même, l’archiver effacerait l’acte.',
          ton: TonSigh.succes,
          icone: LucideIcons.archive),
      const SizedBox(height: 12),
      TableauSigh(
        titre: 'Rendez-vous honorés',
        colonnes: [
          colReferenceAg(),
          ColonneTableau(
              cle: 'date',
              libelle: 'Date et heure',
              sansCoupure: true,
              valeur: (r) => '${r['date']}',
              texte: (r) => texteDateHeureAg(r['date']).replaceFirst(' à ', ' à ')),
          const ColonneTableau(cle: 'patient', libelle: 'Patient'),
          const ColonneTableau(cle: 'medecin', libelle: 'Praticien'),
          const ColonneTableau(cle: 'motif', libelle: 'Motif'),
          const ColonneTableau(cle: 'type', libelle: 'Type'),
        ],
        lignes: agTrierTexte(rows, (r) => '${r['date']}', descendant: true),
        taillePage: 15,
        nomExport: 'rendez-vous-honores',
        alClicLigne: (r) {
          afficherTiroir<void>(context,
              titre: '${r['patient']}',
              sousTitre: '${r['patientCode']} — ${agDate(r['date']) == null ? 'NaN/NaN/NaN' : dateFR(agDate(r['date'])!)}',
              largeurMax: 672,
              corps: detailRendezVousAg(context, r),
              pied: (fermer) => [
                    BoutonSigh(
                        libelle: 'Imprimer',
                        icone: LucideIcons.printer,
                        variante: VarianteBouton.secondaire,
                        onPressed: () => imprimerConsultationAg(context, r)),
                  ]);
        },
      ),
    ]);
  }
}

/// `m2-visites` — page-renvoi hors ruban : le registre des visites est fusionné dans « Rendez-vous & visites ».
class EcranVisites extends StatelessWidget with EcranMaquette {
  const EcranVisites({super.key});

  @override
  String get titre => 'Registre des visites de suivi clinique';

  @override
  String get description =>
      'Fusionné dans « Rendez-vous & visites » — un seul écran tient les venues, avec ou sans rendez-vous.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 576),
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const NoteSigh(
                      'Le registre des visites est fusionné dans « Rendez-vous & visites » : les venues sur rendez-vous et les passages spontanés s’y tiennent ensemble, et le filtre Venue les sépare. C’est là aussi que s’enregistre une personne non enregistrée — nom, prénom, quartier, téléphone — sans lui ouvrir de dossier.',
                      icone: LucideIcons.merge),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                    BoutonSigh(
                        libelle: 'Ouvrir Rendez-vous & visites',
                        icone: LucideIcons.calendarCheck,
                        onPressed: () => c.aller('m2-rendezvous')),
                    BoutonSigh(
                        libelle: 'Agenda',
                        icone: LucideIcons.calendarDays,
                        variante: VarianteBouton.secondaire,
                        onPressed: () => c.aller('m2-agenda')),
                  ]),
                ]))));
  }
}
