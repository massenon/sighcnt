import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'ag_commun.dart';
import 'ag_rendezvous.dart';

// --- m2-domicile ---------------------------------------------------------------------------------------------------------------------------

/// `m2-domicile` — « Consultations & soins à domicile » : seules les prestations de type Domicile (E322 : la maquette montrait les 260
/// consultations), avec le coût additionnel de déplacement (CDCT §10.5).
class EcranDomicile extends StatelessWidget with EcranMaquette {
  const EcranDomicile({super.key});

  @override
  String get titre => 'Consultations & soins à domicile';

  @override
  String get description =>
      'Planification, réalisation et facturation spécifique des prestations réalisées au domicile du patient.';

  @override
  String get regle =>
      'La facturation à domicile applique un coût additionnel de déplacement qui s’ajoute au prix des actes, analyses et médicaments (CDCT §10.5). La facture normalisée est délivrée après règlement.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    List<ChampDef> champs() => [
          const ChampDef.section('Patient et praticien'),
          ChampDef(
              nom: 'patientCode',
              libelle: 'Dossier patient',
              type: TypeChamp.select,
              requis: true,
              col: ColChamp.plein,
              options: optionsPatientsAg(c)),
          ChampDef(
              nom: 'medecin',
              libelle: 'Praticien',
              type: TypeChamp.select,
              requis: true,
              options: optionsMedecinsAg(c)),
          const ChampDef(
              nom: 'type',
              libelle: 'Type',
              type: TypeChamp.select,
              requis: true,
              options: [
                OptionChamp('Consultation'),
                OptionChamp('Contrôle'),
                OptionChamp('Urgence'),
                OptionChamp('Domicile')
              ]),
          const ChampDef.section('Rendez-vous'),
          const ChampDef(
              nom: 'date', libelle: 'Date et heure', type: TypeChamp.dateHeure, requis: true),
          const ChampDef(nom: 'motif', libelle: 'Motif', requis: true, col: ColChamp.plein),
          const ChampDef(
              nom: 'diagnostic',
              libelle: 'Diagnostic',
              type: TypeChamp.textarea,
              lignes: 2,
              col: ColChamp.plein),
          const ChampDef(nom: 'tarif', libelle: 'Tarif (FCFA)', type: TypeChamp.nombre),
          const ChampDef(
              nom: 'statut',
              libelle: 'Statut',
              type: TypeChamp.select,
              requis: true,
              options: [
                OptionChamp('planifiee', 'Planifiée'),
                OptionChamp('en_cours', 'En cours'),
                OptionChamp('terminee', 'Terminée')
              ]),
          const ChampDef(
              nom: 'fraisDeplacement',
              libelle: 'Frais de déplacement (FCFA)',
              type: TypeChamp.nombre,
              aide: 'Coût additionnel propre aux prestations à domicile.'),
          const ChampDef(
              nom: 'adresseIntervention', libelle: 'Adresse d’intervention', col: ColChamp.plein),
        ];
    return EcranCrudAg(
      collection: 'consultations',
      entite: 'intervention à domicile',
      entiteP: 'interventions à domicile',
      triInitial: 'date',
      sensInitial: 'desc',
      filtreBase: (r) => r['type'] == 'Domicile',
      colonnes: [
        colDateAg('Date'),
        colPatientAg(),
        const ColonneTableau(cle: 'motif', libelle: 'Prestation'),
        const ColonneTableau(cle: 'medecin', libelle: 'Intervenant'),
        ColonneTableau(
            cle: 'tarif',
            libelle: 'Montant',
            droite: true,
            texte: (r) => money(r['tarif'] ?? 0, avecDevise: false)),
        ColonneTableau(
            cle: 'statut',
            libelle: 'Statut',
            texte: (r) => '${r['statut'] ?? ''}',
            rendu: (_, r) => statutBadge(r['statut'])),
      ],
      intro: (_) => const NoteSigh(
          'Cet écran ne présente que les prestations de type Domicile. Les consultations réalisées à la clinique sont gérées depuis l’écran « Consultations ».'),
      kpis: (ctx, rows) {
        final k = agKpisDomicile(rows);
        return [
          kpiAg(k[0], LucideIcons.housePlus, TonSigh.navy),
          kpiAg(k[1], LucideIcons.calendarClock, TonSigh.attention),
          kpiAg(k[2], LucideIcons.circleCheck, TonSigh.succes),
          kpiAg(k[3], LucideIcons.coins, TonSigh.info),
        ];
      },
      ouvrirFormulaire: (ecran, rec) => ouvrirFormulaireAg(ecran,
          collection: 'consultations',
          entite: 'intervention à domicile',
          champs: champs,
          initial: const {
            'type': 'Domicile',
            'statut': 'planifiee',
            'tarif': '10000',
            'fraisDeplacement': '5000'
          },
          record: rec,
          transformer: (v, r) => agCompleterPatient({...v, 'type': 'Domicile'},
              record: r,
              patients: patientsAg(c),
              existantes: c.magasin.collection('consultations').toutes)),
      detail: detailRendezVousAg,
      etat: imprimerConsultationAg,
    );
  }
}

// --- m2-registre-appels --------------------------------------------------------------------------------------------------------------------

/// `m2-registre-appels` — appels entrants et sortants relevés au standard (rendez-vous, résultats, suivi). Un appel saisi à la main reçoit la
/// référence suivante de la série (E327) ; sa date proposée est l'instant présent (E323).
class EcranRegistreAppels extends StatelessWidget with EcranMaquette {
  const EcranRegistreAppels({super.key});

  @override
  String get titre => 'Registre des appels';

  @override
  String get description =>
      'Appels entrants et sortants liés à la prise de rendez-vous, aux résultats et au suivi des patients.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    List<ChampDef> champs() => [
          const ChampDef(
              nom: 'dateHeure',
              libelle: 'Date et heure',
              type: TypeChamp.dateHeure,
              requis: true),
          const ChampDef(
              nom: 'sens',
              libelle: 'Sens de l’appel',
              type: TypeChamp.select,
              requis: true,
              options: [OptionChamp('entrant', 'Entrant'), OptionChamp('sortant', 'Sortant')]),
          const ChampDef(nom: 'interlocuteur', libelle: 'Interlocuteur', requis: true),
          const ChampDef(nom: 'telephone', libelle: 'Téléphone', type: TypeChamp.tel),
          ChampDef(
              nom: 'objet',
              libelle: 'Objet de l’appel',
              type: TypeChamp.select,
              requis: true,
              col: ColChamp.plein,
              options: [for (final o in agObjetsAppel) OptionChamp(o)]),
          const ChampDef(nom: 'agent', libelle: 'Traité par', requis: true),
          ChampDef(
              nom: 'suite',
              libelle: 'Suite donnée',
              type: TypeChamp.select,
              options: [for (final o in agSuitesAppel) OptionChamp(o)]),
          const ChampDef(
              nom: 'observations',
              libelle: 'Observations',
              type: TypeChamp.textarea,
              lignes: 2,
              col: ColChamp.plein),
        ];
    String sens(Fiche r) => r['sens'] == 'entrant' ? 'Entrant' : 'Sortant';
    return EcranCrudAg(
      collection: 'appels',
      entite: 'appel',
      entiteP: 'appels',
      triInitial: 'dateHeure',
      sensInitial: 'desc',
      taillePage: 15,
      colonnes: [
        colReferenceAg(),
        ColonneTableau(
            cle: 'dateHeure',
            libelle: 'Date et heure',
            sansCoupure: true,
            valeur: (r) => agDate(r['dateHeure'])?.millisecondsSinceEpoch,
            texte: (r) => texteDateHeureAg(r['dateHeure'])),
        ColonneTableau(
            cle: 'sens',
            libelle: 'Sens',
            texte: sens,
            rendu: (_, r) => BadgeSigh(sens(r),
                ton: r['sens'] == 'entrant' ? TonSigh.info : TonSigh.succes)),
        const ColonneTableau(cle: 'interlocuteur', libelle: 'Interlocuteur'),
        const ColonneTableau(cle: 'telephone', libelle: 'Téléphone', sansCoupure: true),
        const ColonneTableau(cle: 'objet', libelle: 'Objet'),
        const ColonneTableau(cle: 'agent', libelle: 'Traité par'),
        const ColonneTableau(cle: 'suite', libelle: 'Suite donnée'),
      ],
      filtres: [
        const FiltreTableau(nom: 'sens', libelle: 'Sens', options: [
          OptionChamp('entrant', 'Entrant'),
          OptionChamp('sortant', 'Sortant')
        ]),
        FiltreTableau(
            nom: 'objet', libelle: 'Objet', options: [for (final o in agObjetsAppel) OptionChamp(o)]),
      ],
      kpis: (ctx, rows) {
        final k = agKpisAppels(rows);
        return [
          kpiAg(k[0], LucideIcons.phone, TonSigh.navy),
          kpiAg(k[1], LucideIcons.phoneIncoming, TonSigh.info),
          kpiAg(k[2], LucideIcons.phoneOutgoing, TonSigh.succes),
          kpiAg(k[3], LucideIcons.phoneCall, TonSigh.attention),
        ];
      },
      ouvrirFormulaire: (ecran, rec) => ouvrirFormulaireAg(ecran,
          collection: 'appels',
          entite: 'appel',
          champs: champs,
          initial: {
            'dateHeure': agIsoLocal(c.aujourdhui),
            'sens': 'entrant',
            'agent': c.utilisateur
          },
          record: rec,
          prefixe: 'APP',
          transformer: (v, r) => agCompleterAppel(v,
              record: r, existantes: c.magasin.collection('appels').toutes)),
      detail: (ctx, r) => DescListeSigh([
        ('Référence', r['reference']),
        ('Date et heure', texteDateHeureAg(r['dateHeure'])),
        ('Sens', sens(r)),
        ('Interlocuteur', r['interlocuteur']),
        ('Téléphone', r['telephone']),
        ('Objet', r['objet']),
        ('Traité par', r['agent']),
        ('Suite donnée', agVrai(r['suite']) ? r['suite'] : '—'),
        ('Observations', agVrai(r['observations']) ? r['observations'] : '—'),
      ]),
    );
  }
}

// --- m2-agenda-medecin ---------------------------------------------------------------------------------------------------------------------

/// `m2-agenda-medecin` — une VUE du registre des consultations, filtrée sur UN praticien (la donnée n'existe qu'une fois). Un médecin connecté s'ouvre
/// sur son propre agenda.
class EcranAgendaMedecin extends StatefulWidget with EcranMaquette {
  const EcranAgendaMedecin({super.key});

  @override
  String get titre => 'Agenda du médecin';

  @override
  String get description =>
      'Les consultations d’un praticien — passées, du jour et à venir — lues depuis le registre.';

  @override
  String get regle =>
      'Une VUE du registre des consultations, filtrée sur UN praticien : la donnée n’existe qu’une fois. Un médecin connecté s’ouvre sur son propre agenda.';

  @override
  State<EcranAgendaMedecin> createState() => _EtatAgendaMedecin();
}

class _EtatAgendaMedecin extends State<EcranAgendaMedecin> {
  ControleurFormulaire? _f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_f != null) return;
    final c = ContexteEcran.of(context);
    final med = medecinsAg(c);
    final moi = med.where((a) => a['nomComplet'] == c.utilisateur).firstOrNull;
    _f = ControleurFormulaire([
      ChampDef(
          nom: 'praticien',
          libelle: 'Praticien',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.tiers,
          options: [
            for (final a in med)
              OptionChamp('${a['nomComplet']}', '${a['nomComplet']} — ${a['poste'] ?? ''}')
          ])
    ], {
      if (moi != null) 'praticien': '${moi['nomComplet']}'
    })
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _f?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('consultations');
    return ListenableBuilder(
        listenable: col,
        builder: (context, _) {
          final nom = '${_f!['praticien'] ?? ''}';
          final rows = agAgendaDuMedecin(col.actives, nom);
          final k = agKpisAgendaMedecin(rows, c.aujourdhui);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CarteSigh(child: FormulaireSigh(controleur: _f!)),
            const SizedBox(height: 16),
            KpiGrilleSigh(kpis: [
              kpiAg(k[0], LucideIcons.stethoscope, TonSigh.navy),
              kpiAg(k[1], LucideIcons.calendar,
                  rows.any((r) => agDebutTexte(r['date'], 10) == iso(c.aujourdhui))
                      ? TonSigh.attention
                      : TonSigh.neutre),
              kpiAg(k[2], LucideIcons.calendarPlus, TonSigh.info),
              kpiAg(k[3], LucideIcons.circleCheck, TonSigh.succes),
            ]),
            const SizedBox(height: 16),
            TableauSigh(
              titre: 'Agenda — $nom',
              lignes: rows,
              taillePage: 12,
              nomExport: 'agenda-medecin',
              messageVide: 'Aucune consultation au registre pour ce praticien.',
              colonnes: [
                ColonneTableau(
                    cle: 'date',
                    libelle: 'Date et heure',
                    valeur: (r) => '${r['date']}',
                    texte: (r) => texteDateHeureAg(r['date'])),
                ColonneTableau(
                    cle: 'patient',
                    libelle: 'Patient',
                    texte: (r) =>
                        '${r['patient']} — ${agVrai(r['patientCode']) ? r['patientCode'] : '—'}'),
                const ColonneTableau(cle: 'motif', libelle: 'Motif'),
                ColonneTableau(
                    cle: 'type',
                    libelle: 'Type',
                    texte: (r) => '${agVrai(r['type']) ? r['type'] : 'Consultation'}',
                    rendu: (_, r) => BadgeSigh('${agVrai(r['type']) ? r['type'] : 'Consultation'}',
                        ton: r['type'] == 'Urgence' ? TonSigh.danger : TonSigh.neutre)),
                ColonneTableau(
                    cle: 'statut',
                    libelle: 'État',
                    texte: (r) => '${r['statut'] ?? ''}',
                    rendu: (_, r) => statutBadge(r['statut'])),
              ],
            ),
          ]);
        });
  }
}
