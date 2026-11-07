import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cs_commun.dart';
import 'cs_modale.dart';

const _plein = ColChamp.plein;

/// Colonne des dossiers du registre.
Fiche? _dossier(ContexteEcran c, Object? id) =>
    c.magasin.collection('dossiersConsultation').parId(id);

void ouvrirFicheSur(ContexteEcran c, Fiche d) {
  CsNav.ficheDossierId = '${d['id']}';
  c.aller('m2-consultation-fiche');
}

void saisirDossier(ContexteEcran c, Fiche? record) {
  CsNav.dossierId = record == null ? null : '${record['id']}';
  CsNav.retour = 'm2-dossiers-consultation';
  c.aller('m2-dossier-consultation-nouveau');
}

/// `m2-dossiers-consultation` — « Dossiers de consultation » : anamnèse, antécédents et examen clinique structuré (IPPOA) par appareil — le dossier
/// que la fiche de consultation récapitule. Le cycle est ordonné (EN ATTENTE → EN CONSULTATION → EN ATTENTE LABO → CLÔTURÉ), les sauts sont refusés.
class EcranDossiersConsultation extends StatelessWidget with EcranMaquette {
  const EcranDossiersConsultation({super.key});

  @override
  String get titre => 'Dossiers de consultation';

  @override
  String get description =>
      'Anamnèse, antécédents et examen clinique structuré (IPPOA) par appareil — le dossier que la fiche de consultation récapitule.';

  @override
  String get regle =>
      'Le dossier s’enregistre AVANT la fiche de consultation : la fiche en fait le récapitulatif, et c’est elle SEULE qui prescrit (médicaments, analyses, imagerie) vers la caisse. Les constantes sont celles de l’accueil, lues et non ressaisies. Le cycle est ordonné — EN ATTENTE → EN CONSULTATION → EN ATTENTE LABO → CLÔTURÉ — et les sauts sont refusés. L’accueil n’y accède pas (RG-13).';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('dossiersConsultation');
    return ListenableBuilder(
        listenable: Listenable.merge([col, c.magasin.collection('consultations')]),
        builder: (ctx, _) {
          final rows = col.actives;
          final k = csKpisDossiers(rows, iso(c.aujourdhui));
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KpiGrilleSigh(colonnes: 5, kpis: [
              KpiSigh(
                  libelle: 'En attente',
                  valeur: nombre(k.attente),
                  icone: LucideIcons.clock,
                  ton: TonSigh.neutre,
                  indice: 'Inscrits, pas encore examinés'),
              KpiSigh(
                  libelle: 'En consultation',
                  valeur: nombre(k.consultation),
                  icone: LucideIcons.stethoscope,
                  ton: TonSigh.info,
                  indice: 'Dossier enregistré — la fiche peut s’ouvrir'),
              KpiSigh(
                  libelle: 'En attente labo / imagerie',
                  valeur: nombre(k.attenteLabo),
                  icone: LucideIcons.flaskConical,
                  ton: TonSigh.attention,
                  indice: 'Examens prescrits, décision suspendue'),
              KpiSigh(
                  libelle: 'Clôturés',
                  valeur: nombre(k.cloture),
                  icone: LucideIcons.checkCheck,
                  ton: TonSigh.succes),
              KpiSigh(
                  libelle: 'Venues du jour',
                  valeur: nombre(k.duJour),
                  icone: LucideIcons.calendarDays,
                  ton: TonSigh.navy,
                  indice: dateFR(c.aujourdhui)),
            ]),
            const SizedBox(height: 16),
            const NoteSigh(
                'Enchaînement — 1. l’accueil relève les constantes · 2. vous enregistrez le dossier (anamnèse, antécédents, examen IPPOA) · 3. « Ouvrir la fiche de consultation » : synthèse, diagnostic et SEULE étape de prescription · 4. la caisse encaisse une facture globale, puis pharmacie, laboratoire et imagerie exécutent.',
                icone: LucideIcons.route),
            const SizedBox(height: 16),
            _Registre(c: c, rows: rows, ecran: ctx),
          ]);
        });
  }
}

class _Registre extends StatelessWidget {
  const _Registre({required this.c, required this.rows, required this.ecran});
  final ContexteEcran c;
  final List<Fiche> rows;
  final BuildContext ecran;

  void _detail(Fiche r) {
    final d = _dossier(c, r['id']) ?? r;
    afficherTiroir<void>(ecran,
        titre: '${d['patient']} — ${d['patientCode'] ?? d['nip'] ?? ''}',
        sousTitre: '${d['reference'] ?? d['id']}   ·   ${csEtatDossier(d['etat'])['label']}',
        largeurMax: 768,
        corps: recapDossier(c.magasin, d),
        pied: (fermer) => [
              if (csDossierEnregistre(d) && c.droit.editer)
                BoutonSigh(
                    libelle: 'Ouvrir la fiche de consultation',
                    icone: LucideIcons.clipboardList,
                    onPressed: () {
                      fermer();
                      ouvrirFicheSur(c, d);
                    }),
              BoutonSigh(
                  libelle: 'Imprimer',
                  icone: LucideIcons.printer,
                  variante: VarianteBouton.secondaire,
                  onPressed: () => imprimerDossier(ecran, d)),
            ]);
  }

  void _etat(Fiche r) {
    final courant = csEtatDossier(r['etat']);
    final suivants = [
      for (final s in (courant['suivants'] as List? ?? const []))
        (csEtatDossier(s))
    ];
    if (suivants.isEmpty) {
      ToastsSigh.afficher(ecran, 'Le dossier est clôturé : aucun état suivant.');
      return;
    }
    modaleFormulaire(ecran,
        titre: 'État du dossier — ${r['reference'] ?? r['id']}',
        sousTitre: 'Actuellement : ${courant['label']}',
        taille: TailleModale.md,
        libelleOk: 'Appliquer',
        avant: NoteSigh(
            'Les sauts d’état sont refusés : clôturer un dossier resté « en attente » signerait une consultation qui n’a pas eu lieu. Depuis « ${courant['label']} », les états accessibles sont : ${suivants.map((x) => x['label']).join(', ')}.',
            icone: LucideIcons.route),
        champs: [
          ChampDef(
              nom: 'etat',
              libelle: 'Nouvel état',
              type: TypeChamp.select,
              requis: true,
              col: _plein,
              options: [
                for (final s in suivants) OptionChamp('${s['code']}', '${s['label']}')
              ]),
          const ChampDef(nom: 'motifEtat', libelle: 'Précision', col: _plein),
        ],
        valider: (v) {
          final FicheCs patch;
          try {
            patch = csPatchEtatDossier(
                r, '${v['etat']}', v['motifEtat'] as String?, c.aujourdhui);
          } on RefusCs catch (e) {
            return e.message;
          }
          c.magasin.collection('dossiersConsultation').mettreAJour(r['id'], patch);
          ToastsSigh.afficher(ecran, 'Dossier ${csEtatDossier(v['etat'])['label']}.',
              type: TypeToast.succes, detail: '${r['reference']}');
          return null;
        });
  }

  @override
  Widget build(BuildContext context) {
    final auj = c.aujourdhui;
    return TableauSigh(
      titre: 'Dossiers de consultation',
      lignes: rows,
      taillePage: 15,
      triInitial: 'dateArrivee',
      sensInitial: 'desc',
      nomExport: 'dossiers-consultation',
      libelleRecherche: 'Patient, NIP, motif, praticien…',
      messageVide: 'Aucun dossier de consultation.',
      filtres: [
        FiltreTableau(nom: 'etat', libelle: 'État', options: [
          for (final e in csEtatsDossier) OptionChamp('${e['code']}', '${e['label']}')
        ]),
        FiltreTableau(nom: 'typeVenue', libelle: 'Type de venue', options: [
          for (final t in csTypesVenue) OptionChamp('${t['value']}', '${t['label']}')
        ]),
        const FiltreTableau(nom: 'sexe', libelle: 'Sexe', options: [
          OptionChamp('F', 'Féminin'),
          OptionChamp('M', 'Masculin')
        ]),
        FiltreTableau(
            nom: 'jour',
            libelle: 'Période',
            options: const [
              OptionChamp('jour', 'Aujourd’hui'),
              OptionChamp('semaine', '7 derniers jours')
            ],
            correspond: (r, v) => csDansPeriode(r, v, auj)),
      ],
      colonnes: [
        ColonneTableau(
            cle: 'reference',
            libelle: 'Dossier',
            sansCoupure: true,
            texte: (r) => '${r['reference'] ?? r['id']}',
            rendu: (_, r) =>
                Text('${r['reference'] ?? r['id']}', style: styleMonoCs)),
        ColonneTableau(
            cle: 'dateArrivee',
            libelle: 'Venue',
            sansCoupure: true,
            texte: (r) =>
                '${texteDateCs(r['dateArrivee'])}${vrai(r['heureArrivee']) ? ' ${r['heureArrivee']}' : ''}'),
        colPatientCs(),
        ColonneTableau(
            cle: 'typeVenue',
            libelle: 'Venue',
            texte: (r) => csLibelleTypeVenue(r['typeVenue']),
            valeur: (r) => csLibelleTypeVenue(r['typeVenue'])),
        const ColonneTableau(cle: 'motifVenue', libelle: 'Motif'),
        ColonneTableau(
            cle: 'examen',
            libelle: 'Examen IPPOA',
            valeur: (r) => csSyntheseExamen(csExamensPhysiquesDe(r)).length,
            texte: (r) {
              final n = csSyntheseExamen(csExamensPhysiquesDe(r)).length;
              return n > 0 ? '$n appareil(s)' : 'non consigné';
            },
            rendu: (_, r) {
              final n = csSyntheseExamen(csExamensPhysiquesDe(r)).length;
              return n > 0
                  ? BadgeSigh('$n appareil(s)', ton: TonSigh.info)
                  : const Text('non consigné',
                      style: TextStyle(color: JetonsShell.slate400, fontSize: 12));
            }),
        ColonneTableau(
            cle: 'soignant',
            libelle: 'Praticien',
            texte: (r) => vrai(r['soignant']) ? '${r['soignant']}' : '—'),
        ColonneTableau(
            cle: 'etat',
            libelle: 'État',
            texte: (r) => '${csEtatDossier(r['etat'])['label']}',
            valeur: (r) => csEtatDossier(r['etat'])['label'],
            rendu: (_, r) {
              final e = csEtatDossier(r['etat']);
              return BadgeSigh('${e['label']}', ton: tonCs(e['couleur']));
            }),
      ],
      alClicLigne: _detail,
      actions: [
        if (c.droit.editer)
          BoutonSigh(
              libelle: 'Nouveau dossier',
              icone: LucideIcons.plus,
              taille: TailleBouton.sm,
              onPressed: () => saisirDossier(c, null)),
      ],
      actionsLigne: (context, r) => [
        if (c.droit.editer && csDossierEnregistre(r))
          BoutonIcone(
              icone: LucideIcons.clipboardList,
              libelle: 'Ouvrir la fiche de consultation',
              onPressed: () => ouvrirFicheSur(c, r)),
        if (c.droit.editer && r['etat'] != 'cloture')
          BoutonIcone(
              icone: LucideIcons.stethoscope,
              libelle: r['etat'] == 'attente'
                  ? 'Examiner — saisir le dossier'
                  : 'Compléter le dossier',
              onPressed: () => saisirDossier(c, r)),
        if (c.droit.editer && r['etat'] != 'cloture')
          BoutonIcone(
              icone: LucideIcons.arrowRight,
              libelle: 'Changer l’état du dossier',
              onPressed: () => _etat(r)),
        BoutonIcone(
            icone: LucideIcons.printer,
            libelle: 'Imprimer le dossier',
            onPressed: () => imprimerDossier(ecran, r)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// LA SAISIE DU DOSSIER EN PAGE PLEINE — m2-dossier-consultation-nouveau
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `m2-dossier-consultation-nouveau` — la saisie complète du dossier : anamnèse, antécédents, données préalables et examen clinique IPPOA par
/// appareil. Le dossier s'enregistre AVANT la fiche, qui en fait le récapitulatif et qui SEULE prescrit. Les constantes de l'accueil sont reprises et
/// affichées en lecture — jamais ressaisies. Un second dossier ouvert pour le même patient est refusé en nommant le premier.
class EcranDossierConsultationNouveau extends StatefulWidget with EcranMaquette {
  const EcranDossierConsultationNouveau({super.key});

  @override
  String get titre => 'Dossier de consultation';

  @override
  String get description =>
      'Anamnèse, antécédents, données préalables et examen clinique IPPOA par appareil — la saisie complète du dossier.';

  @override
  String get regle =>
      'Le dossier s’enregistre AVANT la fiche de consultation, qui en fait le récapitulatif et qui SEULE prescrit. Les constantes de l’accueil sont reprises et affichées en lecture — jamais ressaisies. Un second dossier ouvert pour le même patient est refusé en nommant le premier.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.maybeOf(context);
    if (c == null || !c.droit.editer) return const [];
    return [
      BoutonSigh(
          libelle: 'Enregistrer le dossier',
          icone: LucideIcons.save,
          taille: TailleBouton.sm,
          onPressed: () => _EtatDossierNouveau._courant?.enregistrer()),
    ];
  }

  @override
  State<EcranDossierConsultationNouveau> createState() => _EtatDossierNouveau();
}

class _EtatDossierNouveau extends State<EcranDossierConsultationNouveau> {
  static _EtatDossierNouveau? _courant;

  bool _pret = false;
  Fiche? _record;
  String _retour = 'm2-dossiers-consultation';
  bool _introuvable = false;
  late ControleurFormulaire _ident, _anam, _ant, _prealables, _obst, _eg, _obsEx, _chir;
  final Map<String, ControleurFormulaire> _examens = {};
  final Map<String, GlobalKey<RepliableSighState>> _cles = {};
  bool _chirurgien = false;

  @override
  void initState() {
    super.initState();
    _courant = this;
  }

  @override
  void dispose() {
    if (_courant == this) _courant = null;
    if (_pret) {
      for (final f in [_ident, _anam, _ant, _prealables, _obst, _eg, _obsEx, _chir, ..._examens.values]) {
        f.dispose();
      }
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pret) return;
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    _retour = CsNav.retour;
    final id = CsNav.dossierId;
    _record = id == null ? null : m.collection('dossiersConsultation').parId(id);
    _introuvable = id != null && _record == null;
    final r = _record ?? const <String, Object?>{};
    _chirurgien = c.role == 'chirurgien';

    _ident = ControleurFormulaire([
      const ChampDef.section('Patient et venue'),
      ChampDef(
          nom: 'patientCode',
          libelle: 'Dossier patient',
          type: TypeChamp.select,
          requis: true,
          col: _plein,
          options: optionsPatientsCs(m),
          aide: _record != null
              ? 'Le patient d’un dossier enregistré ne se change pas — ouvrir un autre dossier.'
              : null),
      ChampDef(
          nom: 'soignant',
          libelle: 'Praticien',
          type: TypeChamp.select,
          requis: true,
          options: optionsPraticiensCs(m)),
      ChampDef(
          nom: 'typeVenue',
          libelle: 'Type de venue',
          type: TypeChamp.select,
          requis: true,
          options: [
            for (final t in csTypesVenue) OptionChamp('${t['value']}', '${t['label']}')
          ]),
      const ChampDef(
          nom: 'dateArrivee',
          libelle: 'Date de la venue',
          type: TypeChamp.date,
          requis: true),
      const ChampDef(
          nom: 'heureArrivee', libelle: 'Heure d’arrivée', indicatif: '08h30'),
      const ChampDef(
          nom: 'motifVenue',
          libelle: 'Motif de consultation',
          requis: true,
          col: _plein),
    ], {
      'dateArrivee': iso(c.aujourdhui),
      ..._chaines(r),
    });
    _anam = ControleurFormulaire(const [
      ChampDef(
          nom: 'histoire',
          libelle: 'Histoire de la maladie',
          type: TypeChamp.textarea,
          lignes: 4,
          requis: true,
          col: _plein,
          aide: 'Le récit clinique : début, évolution, signes associés, ce qui a déjà été tenté.'),
      ChampDef(
          nom: 'traitementEnCours',
          libelle: 'Traitements en cours et habituels',
          type: TypeChamp.textarea,
          lignes: 2,
          col: _plein,
          aide: 'Y compris l’automédication — c’est elle qu’on oublie.'),
    ], _chaines(r));
    _ant = ControleurFormulaire([
      for (final cat in csCategoriesAntecedent)
        ChampDef(
            nom: 'ant_${cat['code']}',
            libelle: '${cat['label']}',
            type: TypeChamp.textarea,
            lignes: 2,
            col: _plein,
            aide: '${cat['note']}')
    ], _chaines(r));
    _prealables = ControleurFormulaire(const [
      ChampDef(nom: 'allergies', libelle: 'Allergies'),
      ChampDef(
          nom: 'allergiesMedicamenteuses',
          libelle: 'Allergies médicamenteuses',
          aide: 'Affichée en rouge au récapitulatif : elle conditionne la prescription.'),
      ChampDef(nom: 'statutVaccinal', libelle: 'Statut vaccinal', type: TypeChamp.select, options: [
        OptionChamp('À jour'), OptionChamp('Incomplet'), OptionChamp('Non vacciné'), OptionChamp('Inconnu')
      ]),
      ChampDef(nom: 'groupeSanguin', libelle: 'Groupe sanguin', type: TypeChamp.select, options: [
        OptionChamp('A+'), OptionChamp('A-'), OptionChamp('B+'), OptionChamp('B-'),
        OptionChamp('AB+'), OptionChamp('AB-'), OptionChamp('O+'), OptionChamp('O-'), OptionChamp('Inconnu')
      ]),
      ChampDef(
          nom: 'electrophoreseHb',
          libelle: 'Électrophorèse de l’hémoglobine',
          type: TypeChamp.select,
          options: [
            OptionChamp('AA'), OptionChamp('AS'), OptionChamp('AC'), OptionChamp('SS'),
            OptionChamp('SC'), OptionChamp('CC'), OptionChamp('Non faite')
          ]),
      ChampDef(
          nom: 'depistage',
          libelle: 'Dépistage',
          aide: 'VIH, hépatite B, syphilis… — résultat et date.'),
      ChampDef(
          nom: 'enqueteSociale',
          libelle: 'Enquête sociale',
          type: TypeChamp.textarea,
          lignes: 2,
          col: _plein),
    ], _chaines(r));
    final ao = (r['antecedentsObstetricaux'] as Map?)?.cast<String, Object?>() ?? const {};
    _obst = ControleurFormulaire([
      const ChampDef(nom: 'gestite', libelle: 'Gestité', type: TypeChamp.nombre),
      const ChampDef(nom: 'parite', libelle: 'Parité', type: TypeChamp.nombre),
      const ChampDef(nom: 'enfantsVivants', libelle: 'Enfants vivants', type: TypeChamp.nombre),
      const ChampDef(nom: 'faussesCouches', libelle: 'Fausses couches', type: TypeChamp.nombre),
      const ChampDef(nom: 'enfantsDecedes', libelle: 'Enfants décédés', type: TypeChamp.nombre),
      const ChampDef(
          nom: 'ageDerniereGrossesse',
          libelle: 'Âge à la dernière grossesse',
          type: TypeChamp.nombre),
      const ChampDef(
          nom: 'ddr', libelle: 'Date des dernières règles (DDR)', type: TypeChamp.date),
      ChampDef(
          nom: 'pathologiesObst',
          libelle: 'Pathologies antérieures',
          type: TypeChamp.multiselect,
          col: _plein,
          options: [for (final x in csPathologiesObstetricales) OptionChamp(x)]),
      const ChampDef(
          nom: 'procreateur',
          libelle: 'Antécédents du procréateur',
          type: TypeChamp.textarea,
          lignes: 2,
          col: _plein),
    ], {
      ..._chaines(ao),
      'pathologiesObst': [for (final x in (ao['pathologies'] as List? ?? const [])) '$x'],
    });
    _eg = ControleurFormulaire([
      ChampDef(
          nom: 'etatGeneral',
          libelle: 'État général',
          type: TypeChamp.select,
          requis: true,
          options: [
            for (final t in csEtatsGeneraux) OptionChamp('${t['value']}', '${t['label']}')
          ]),
      const ChampDef(
          nom: 'etatGeneralPrecision',
          libelle: 'Précision (en fonction de la maladie)',
          aide:
              'Exigée si l’état général n’est pas bon — « altéré » sans dire en quoi ne se relit pas.'),
    ], _chaines(r));
    final examens = csExamensPhysiquesDe(r);
    for (final ap in csAppareils) {
      final valeurs = (examens['${ap['code']}'] as Map?)?.cast<String, Object?>() ?? const {};
      _examens['${ap['code']}'] = ControleurFormulaire([
        for (final t in csTempsExamenDe(ap))
          ChampDef(
              nom: '${t['code']}',
              libelle: '${t['ordre']}. ${t['label']}',
              type: TypeChamp.textarea,
              lignes: 2,
              indicatif: () {
                final a = ((ap['aides'] as Map?)?['${t['code']}']) as String?;
                return a != null && a != '—' ? a : null;
              }())
      ], _chaines(valeurs));
      _cles['${ap['code']}'] = GlobalKey<RepliableSighState>();
    }
    final eo = (r['examenObstetrical'] as Map?)?.cast<String, Object?>() ?? const {};
    _obsEx = ControleurFormulaire([
      for (final x in csExamenObstetrical)
        ChampDef(
            nom: 'obs_${x['code']}',
            libelle: '${x['label']}',
            type: switch (x['type']) {
              'textarea' => TypeChamp.textarea,
              'number' => TypeChamp.nombre,
              'select' => TypeChamp.select,
              _ => TypeChamp.texte
            },
            lignes: 2,
            col: x['type'] == 'textarea' ? _plein : ColChamp.demi,
            options: [
              for (final o in (x['options'] as List? ?? const [])) OptionChamp('$o')
            ])
    ], {for (final e in eo.entries) 'obs_${e.key}': '${e.value ?? ''}'});
    _chir = ControleurFormulaire([
      for (final rub in csRubriquesChirurgicales)
        ChampDef(
            nom: rub,
            libelle: _libChirSaisie[rub] ?? rub,
            type: TypeChamp.textarea,
            lignes: 2)
    ], _chaines(r));
    _pret = true;
  }

  static const _libChirSaisie = {
    'actesChirurgicaux': 'Actes chirurgicaux envisagés ou pratiqués',
    'indicationOperatoire': 'Indication opératoire',
    'blocPrevu': 'Programmation au bloc',
    'risqueOperatoire': 'Risque opératoire évalué',
  };

  static Map<String, Object?> _chaines(Map<String, Object?> r) => {
        for (final e in r.entries)
          if (e.value is String || e.value is num) e.key: '${e.value}'
      };

  Fiche? _patientCourant(ContexteEcran c) {
    final code = _ident['patientCode'];
    if (code == null || '$code'.isEmpty) return null;
    return c.magasin.collection('patients').actives.where((p) => p['code'] == code).firstOrNull;
  }

  Object? _nombre(Object? v) {
    final t = '${v ?? ''}'.trim();
    if (t.isEmpty) return null;
    final n = num.tryParse(t);
    return n == null ? null : (n == n.truncate() ? n.toInt() : n);
  }

  void enregistrer() {
    if (!mounted || !_pret) return;
    final c = ContexteEcran.of(context);
    if (!c.droit.editer) return;
    final a = _ident.valider(), b = _anam.valider(), cc = _ant.valider(), d = _prealables.valider();
    final e = _obst.valider(), g = _eg.valider(), h = _obsEx.valider();
    if (a == null || b == null || cc == null || d == null || e == null || g == null || h == null) {
      ToastsSigh.afficher(
          context, 'Le formulaire comporte des erreurs — champs obligatoires à compléter.',
          type: TypeToast.erreur);
      return;
    }
    final k = _chirurgien ? (_chir.valider() ?? const <String, Object?>{}) : <String, Object?>{};
    if ('${g['etatGeneral']}' != 'bon' && '${g['etatGeneralPrecision'] ?? ''}'.trim().isEmpty) {
      ToastsSigh.afficher(context,
          'État général « ${csLibelleEtatGeneral(g['etatGeneral'])} » : préciser en quoi.',
          type: TypeToast.erreur);
      return;
    }
    if (_record != null) a['patientCode'] = _record!['patientCode'];
    final p = c.magasin.collection('patients').actives.where((x) => x['code'] == a['patientCode']).firstOrNull;
    final femme = p != null && p['sexe'] == 'F';
    final examensPhysiques = <String, Object?>{};
    for (final ap in csAppareils) {
      if (csVrai(ap['femme']) && !femme) continue;
      final f = _examens['${ap['code']}']!;
      final bloc = <String, Object?>{};
      for (final t in csTempsExamenDe(ap)) {
        if (t['code'] == 'menstruation' && !femme) continue;
        final v = '${f['${t['code']}'] ?? ''}'.trim();
        if (v.isNotEmpty) bloc['${t['code']}'] = v;
      }
      // Seuls les appareils EXAMINÉS entrent au JSON : un appareil vide n'est pas « normal », il n'a pas été examiné.
      if (bloc.isNotEmpty) examensPhysiques['${ap['code']}'] = bloc;
    }
    Map<String, Object?>? antObst, examObst;
    if (femme) {
      antObst = {
        'gestite': _nombre(e['gestite']),
        'parite': _nombre(e['parite']),
        'enfantsVivants': _nombre(e['enfantsVivants']),
        'faussesCouches': _nombre(e['faussesCouches']),
        'enfantsDecedes': _nombre(e['enfantsDecedes']),
        'ageDerniereGrossesse': _nombre(e['ageDerniereGrossesse']),
        'ddr': '${e['ddr'] ?? ''}'.isEmpty ? null : e['ddr'],
        'pathologies': e['pathologiesObst'] ?? <String>[],
        'procreateur': e['procreateur'] ?? '',
      };
      if (!antObst.values.any((v) => v is List ? v.isNotEmpty : (v != null && v != ''))) {
        antObst = null;
      }
      examObst = {};
      for (final x in csExamenObstetrical) {
        final v = h['obs_${x['code']}'];
        if (v != null && v != '') {
          examObst[x['code'] as String] = x['type'] == 'number' ? _nombre(v) : v;
        }
      }
      if (examObst.isEmpty) examObst = null;
    }
    final valeurs = <String, Object?>{
      ...a, ...b, ...cc, ...d, ...g, ...k,
      'examensPhysiques': examensPhysiques,
      'antecedentsObstetricaux': antObst,
      'examenObstetrical': examObst,
    };
    final ResultatDossier res;
    try {
      res = csEnregistrerDossier(stockDe(c), valeurs, _record, sessionDe(c));
    } on RefusCs catch (err) {
      ToastsSigh.afficher(context, 'Enregistrement refusé.',
          type: TypeToast.erreur, detail: err.message, duree: const Duration(seconds: 9));
      return;
    }
    ToastsSigh.afficher(context,
        'Dossier ${res.dossier['reference'] ?? ''} enregistré — la fiche de consultation peut s’ouvrir.',
        type: TypeToast.succes, duree: const Duration(seconds: 8));
    CsNav.vider();
    c.aller(_retour);
  }

  void _annuler(ContexteEcran c) {
    CsNav.vider();
    c.aller(_retour);
  }

  Widget _grille(ControleurFormulaire f) => FormulaireSigh(controleur: f);

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    if (_introuvable) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const NoteSigh(
            'Ce dossier est introuvable — il a pu être archivé depuis que le lien a été ouvert. Revenez au registre pour le retrouver.',
            ton: TonSigh.attention,
            icone: LucideIcons.triangleAlert),
        const SizedBox(height: 12),
        BoutonSigh(
            libelle: 'Revenir au registre',
            icone: LucideIcons.arrowLeft,
            onPressed: () => _annuler(c)),
      ]);
    }
    if (!c.droit.editer) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const NoteSigh(
            'Votre profil consulte les dossiers de consultation sans les modifier. La saisie appartient au praticien qui examine.',
            ton: TonSigh.attention,
            icone: LucideIcons.lock),
        const SizedBox(height: 12),
        BoutonSigh(
            libelle: 'Revenir au registre',
            variante: VarianteBouton.secondaire,
            icone: LucideIcons.arrowLeft,
            onPressed: () => _annuler(c)),
      ]);
    }
    return ListenableBuilder(
        listenable: _ident,
        builder: (ctx, _) {
          final p = _patientCourant(c);
          final femme = p == null || p['sexe'] == 'F';
          ({Map<String, Object?> valeurs, String source})? cst =
              _record != null ? csConstantesDuDossier(_record) : null;
          if (cst == null && p != null) {
            final rl = csDernierReleve(stockDe(c), p['code'], p['id']);
            cst = rl == null ? null : (valeurs: csCopieReleve(rl)!, source: 'accueil');
          }
          bool femmeApp(Map<String, Object?> ap) => !csVrai(ap['femme']) || femme;
          final corps = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CarteSigh(titre: 'Patient et venue', child: _grille(_ident)),
            const SizedBox(height: 16),
            CarteSigh(
                titre: 'Zone 1 — constantes de l’accueil (lecture seule)',
                child: blocConstantes(cst)),
            const SizedBox(height: 16),
            RepliableSigh(
                titre: '1. Anamnèse — motif, histoire, traitements',
                icone: LucideIcons.notebookPen,
                ouvert: true,
                contenu: _grille(_anam)),
            const SizedBox(height: 16),
            RepliableSigh(
                titre: '2. Antécédents — trois catégories strictes',
                icone: LucideIcons.history,
                ouvert: true,
                contenu: _grille(_ant)),
            const SizedBox(height: 16),
            RepliableSigh(
                titre: '3. Données préalables — allergies, vaccins, groupe, dépistage',
                icone: LucideIcons.shieldPlus,
                ouvert: vrai(_record?['allergies']) || vrai(_record?['statutVaccinal']),
                contenu: _grille(_prealables)),
            if (femme) ...[
              const SizedBox(height: 16),
              RepliableSigh(
                  titre: 'Antécédents obstétricaux (femme)',
                  icone: LucideIcons.baby,
                  ouvert: _record?['antecedentsObstetricaux'] != null,
                  contenu: _grille(_obst)),
            ],
            const SizedBox(height: 16),
            RepliableSigh(
                titre: '4. État général',
                icone: LucideIcons.activity,
                ouvert: true,
                contenu: _grille(_eg)),
            const SizedBox(height: 16),
            CarteSigh(
                titre:
                    '5. Examen physique par appareil — Inspection · Palpation · Percussion · Auscultation',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const NoteSigh(
                      'Dépliez les appareils pertinents pour le motif. Normal par défaut pose « RAS » dans les champs restés vides : vous n’écrivez que l’anormal.',
                      icone: LucideIcons.stethoscope),
                  for (final ap in csAppareils)
                    if (femmeApp(ap)) ...[
                      const SizedBox(height: 8),
                      RepliableSigh(
                          key: _cles['${ap['code']}'],
                          cle: '${ap['code']}',
                          titre: '${ap['label']}',
                          icone: _icone('${ap['icone']}'),
                          ouvert: _examens['${ap['code']}']!
                              .champs
                              .any((ch) => '${_examens['${ap['code']}']![ch.nom] ?? ''}'.trim().isNotEmpty),
                          extra: BoutonSigh(
                              libelle: 'Normal par défaut',
                              icone: LucideIcons.checkCheck,
                              taille: TailleBouton.sm,
                              variante: VarianteBouton.secondaire,
                              onPressed: () {
                                // « RAS » dans les champs RESTÉS VIDES seulement ; la menstruation n'est pas un temps d'examen.
                                final f = _examens['${ap['code']}']!;
                                for (final ch in f.champs) {
                                  if (ch.nom != 'menstruation' &&
                                      '${f[ch.nom] ?? ''}'.trim().isEmpty) {
                                    f.poser(ch.nom, csMentionNormale);
                                  }
                                }
                                _cles['${ap['code']}']!.currentState?.deplier();
                              }),
                          contenu: _grille(_examens['${ap['code']}']!)),
                    ],
                ])),
            if (femme) ...[
              const SizedBox(height: 16),
              RepliableSigh(
                  titre: 'Examen obstétrical spécifique (femme)',
                  icone: LucideIcons.baby,
                  ouvert: _record?['examenObstetrical'] != null,
                  contenu: _grille(_obsEx)),
            ],
            const SizedBox(height: 16),
            RepliableSigh(
                titre: 'Actes chirurgicaux et bloc${_chirurgien ? '' : ' — lecture seule'}',
                icone: LucideIcons.scissors,
                ouvert: csRubriquesChirurgicales.any((x) => vrai(_record?[x])),
                contenu: _chirurgien
                    ? _grille(_chir)
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        for (final rub in csRubriquesChirurgicales) ...[
                          Text(_libChirSaisie[rub] ?? rub,
                              style: const TextStyle(
                                  color: JetonsShell.slate600,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500)),
                          Text(vrai(_record?[rub]) ? '${_record![rub]}' : '—',
                              style: const TextStyle(color: JetonsShell.slate800, fontSize: 14)),
                          const SizedBox(height: 8),
                        ],
                        const Text(
                            'Renseigné par le chirurgien seulement. Vous le lisez — c’est votre patient aussi.',
                            style: TextStyle(color: JetonsShell.slate500, fontSize: 12)),
                      ])),
          ]);
          final aside = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CarteSigh(titre: 'Enchaînement du parcours', child: _chaine(const [
              ('Accueil — Zone 1', 'Identité, couverture et constantes déjà saisies', 'Étape 1', TonSigh.succes),
              ('Dossier de consultation', 'Anamnèse, antécédents, examen IPPOA — vous y êtes', 'Étape 2', TonSigh.navy),
              ('Fiche de consultation', 'Synthèse, diagnostic et conduite à tenir', 'Étape 3', TonSigh.info),
              ('Prescription', 'Médicaments, analyses, imagerie — sur la fiche, jamais ici', 'Étape 4', TonSigh.info),
              ('Caisse', 'Facture globale ; l’aval se débloque au règlement (M8)', 'Étape 5', TonSigh.attention),
            ])),
            const SizedBox(height: 16),
            const CarteSigh(
                titre: 'Ce que le dossier engage',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  NoteSigh(
                      'Le dossier s’enregistre avant la fiche : celle-ci le refuse tant qu’il n’existe pas, et en fait ensuite le récapitulatif.',
                      icone: LucideIcons.clipboardCheck),
                  SizedBox(height: 12),
                  NoteSigh(
                      'Les constantes de l’accueil sont reprises et affichées en lecture — jamais ressaisies : deux saisies de la même mesure finiraient par diverger.',
                      ton: TonSigh.neutre,
                      icone: LucideIcons.activity),
                ])),
          ]);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_record != null) ...[
              NoteSigh(
                  'Dossier ${_record!['reference'] ?? ''} — ${_record!['patient'] ?? ''} · ${_record!['patientCode'] ?? ''}.',
                  icone: LucideIcons.user),
              const SizedBox(height: 16),
            ],
            LayoutBuilder(builder: (_, w) {
              if (w.maxWidth >= 1024) {
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 2, child: corps),
                  const SizedBox(width: 16),
                  Expanded(child: aside),
                ]);
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                corps,
                const SizedBox(height: 16),
                aside,
              ]);
            }),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.only(top: 16),
              decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: JetonsShell.slate200))),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                BoutonSigh(
                    libelle: 'Annuler',
                    icone: LucideIcons.x,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => _annuler(c)),
                const SizedBox(width: 8),
                BoutonSigh(
                    libelle: 'Enregistrer le dossier',
                    icone: LucideIcons.save,
                    onPressed: enregistrer),
              ]),
            ),
          ]);
        });
  }
}

IconData _icone(String nom) => switch (nom) {
      'heart-pulse' => LucideIcons.heartPulse,
      'wind' => LucideIcons.wind,
      'soup' => LucideIcons.soup,
      'droplets' => LucideIcons.droplets,
      'bone' => LucideIcons.bone,
      'ear' => LucideIcons.ear,
      'brain' => LucideIcons.brain,
      'baby' => LucideIcons.baby,
      'hand' => LucideIcons.hand,
      _ => LucideIcons.circle,
    };

/// `U.timeline` : étapes numérotées de l'enchaînement du parcours.
Widget _chaine(List<(String, String, String, TonSigh)> etapes) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final e in etapes)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 5, right: 10),
                    decoration: BoxDecoration(
                        color: e.$4.icone600, shape: BoxShape.circle)),
                Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                        child: Text(e.$1,
                            style: const TextStyle(
                                color: JetonsShell.slate800,
                                fontSize: 14,
                                fontWeight: FontWeight.w500))),
                    Text(e.$3,
                        style: const TextStyle(color: JetonsShell.slate400, fontSize: 12)),
                  ]),
                  Text(e.$2,
                      style: const TextStyle(
                          color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
                ])),
              ]),
            ),
        ]);

/// Rendu partagé de la chaîne du parcours (fiche, ordonnance).
Widget chaineParcours(List<(String, String, String, TonSigh)> etapes) => _chaine(etapes);
