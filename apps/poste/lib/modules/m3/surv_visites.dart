import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'surv_commun.dart';

/// `m3-visites-patients` — « Visites aux patients hospitalisés » : le registre des visites du personnel traitant et des visites familiales, avec date et
/// heure (`K.registre` de la maquette). La visite se rattache à une ADMISSION EN COURS ; le patient, son code et son lit sont recopiés de l'admission.
///
/// Limite dite : la maquette amorce ce registre par ses écrans (`visitesHospi`, graine 401) quand il est vide ; le jeu du poste ne l'embarque pas encore
/// (collection absente de `gen-poste-jeu.js`) — l'écran s'ouvre donc vide tant que le jeu ne la fournit pas.
class EcranVisitesPatients extends StatelessWidget with EcranMaquette {
  const EcranVisitesPatients({super.key});

  @override
  String get titre => 'Visites aux patients hospitalisés';

  @override
  String get description =>
      'Enregistrement des visites du personnel traitant et des visites familiales, avec dates et heures.';

  static const types = ['Famille', 'Personnel traitant'];

  static List<Fiche> enCours(Magasin m) =>
      m.collection('admissions').actives.where((a) => a['statut'] == 'en_cours').toList();

  static String libelleAdmission(Fiche a) =>
      '${a['patient']} — lit ${a['lit']} (${a['patientCode']})';

  static List<ChampDef> champs(Magasin m) => [
        ChampDef(
            nom: 'admissionId',
            libelle: 'Patient hospitalisé',
            type: TypeChamp.select,
            requis: true,
            col: ColChamp.plein,
            options: [
              for (final a in enCours(m)) OptionChamp('${a['id']}', libelleAdmission(a))
            ]),
        const ChampDef(nom: 'date', libelle: 'Date', type: TypeChamp.date, requis: true),
        ChampDef(
            nom: 'heure',
            libelle: 'Heure',
            requis: true,
            indicatif: 'HH:mm',
            valider: (v, _) => RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch('$v')
                ? null
                : 'Heure attendue au format HH:mm.'),
        ChampDef(
            nom: 'type',
            libelle: 'Type de visite',
            type: TypeChamp.select,
            requis: true,
            options: [for (final t in types) OptionChamp(t)]),
        const ChampDef(nom: 'visiteur', libelle: 'Visiteur', requis: true),
        const ChampDef(nom: 'observation', libelle: 'Observation', col: ColChamp.plein),
      ];

  static Map<String, Object?> initiales(Fiche? r, DateTime auj) => r != null
      ? {
          for (final k in ['admissionId', 'date', 'heure', 'type', 'visiteur', 'observation']) k: r[k] ?? ''
        }
      : {
          'date': '${auj.year.toString().padLeft(4, '0')}-${auj.month.toString().padLeft(2, '0')}-${auj.day.toString().padLeft(2, '0')}',
          'heure': '10:00',
          'type': 'Famille',
        };

  /// `transform` : le patient, son code et son lit viennent de l'admission choisie.
  static Fiche construire(Magasin m, Map<String, Object?> v, Fiche? r) {
    final a = m.collection('admissions').parId(v['admissionId']);
    return {
      if (r == null) 'statut': 'actif',
      ...v,
      if (a != null) ...{'patient': a['patient'], 'patientCode': a['patientCode'], 'lit': a['lit']},
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('visitesHospi');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final rows = col.actives;
        final famille = rows.where((r) => r['type'] == 'Famille').length;
        final patients = {for (final r in rows) r['patientCode']}.length;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!c.droit.editer && c.droit.voir)
            Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: NoteSigh(
                    'Lecture seule : le profil « ${c.role} » consulte cet écran sans pouvoir y écrire. Les droits se règlent dans la matrice des rôles.',
                    ton: TonSigh.attention)),
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Visites enregistrées', valeur: nombre(rows.length), icone: LucideIcons.users, ton: TonSigh.navy),
            KpiSigh(libelle: 'Visites familiales', valeur: nombre(famille), icone: LucideIcons.heart, ton: TonSigh.succes),
            KpiSigh(
                libelle: 'Visites du personnel',
                valeur: nombre(rows.length - famille),
                icone: LucideIcons.stethoscope,
                ton: TonSigh.info),
            KpiSigh(libelle: 'Patients visités', valeur: nombre(patients), icone: LucideIcons.bedDouble, ton: TonSigh.neutre),
          ]),
          const SizedBox(height: 16),
          OngletsSigh(onglets: [
            OngletDef(
                id: 'liste',
                libelle: 'Tous les visites',
                compte: rows.length,
                construire: (ctx) => RegistreFormulaire(
                      collection: col,
                      lignes: trierPar(rows, (r) => r['date'], descendant: true),
                      prefixe: 'VIS',
                      nomExport: 'visitesHospi',
                      messageVide: 'Aucun visite enregistré.',
                      libelleRecherche: 'Rechercher un visite…',
                      taillePage: 15,
                      triInitial: 'date',
                      sensInitial: 'desc',
                      groupe: true,
                      piedFiche: true,
                      libelleNouveau: 'Nouveau',
                      titreCreation: 'Nouveau visite',
                      toastCreation: 'Nouveau visite créé.',
                      messageArchivage:
                          'L’enregistrement ne sera pas supprimé : il est archivé et reste consultable dans l’onglet « Archivés ». L’opération est journalisée et peut être annulée.',
                      filtres: [
                        FiltreTableau(
                            nom: 'type',
                            libelle: 'Type de visite',
                            options: [for (final t in types) OptionChamp(t)]),
                      ],
                      champs: (_) => champs(c.magasin),
                      initiales: (r) => initiales(r, c.aujourdhui),
                      construire: (v, r) => construire(c.magasin, v, r),
                      titreFiche: (r) => '${r['patient']}',
                      titreModification: (r) => '${r['id']}',
                      colonnes: _colonnes,
                      detail: (ctx, r) {
                        final a = c.magasin.collection('admissions').parId(r['admissionId']);
                        return DescListeSigh([
                          ('Date', dateTexte(r['date'])),
                          ('Heure', r['heure']),
                          ('Lit', r['lit']),
                          ('Patient', r['patient']),
                          ('Type', r['type']),
                          ('Visiteur', r['visiteur']),
                          ('Observation', r['observation']),
                          ('Patient hospitalisé', a != null ? libelleAdmission(a) : null),
                        ]);
                      },
                    )),
            OngletDef(
                id: 'archives',
                libelle: 'Archivés',
                compte: col.archivees.length,
                construire: (ctx) => TableauSigh(
                      colonnes: _colonnes,
                      lignes: col.archivees,
                      taillePage: 15,
                      nomExport: 'visitesHospi',
                      triInitial: 'date',
                      sensInitial: 'desc',
                      libelleRecherche: 'Rechercher un visite…',
                      messageVide: 'Aucun enregistrement archivé.',
                      actionsLigne: (_, f) => [
                        if (c.droit.annuler)
                          BoutonIcone(
                              icone: LucideIcons.archiveRestore,
                              libelle: 'Restaurer',
                              onPressed: () {
                                col.restaurer(f['id']);
                                ToastsSigh.afficher(context, 'Enregistrement restauré.', type: TypeToast.succes);
                              }),
                      ],
                    )),
          ]),
        ]);
      },
    );
  }

  static final List<ColonneTableau> _colonnes = [
    ColonneTableau(
        cle: 'date',
        libelle: 'Date',
        sansCoupure: true,
        texte: (r) => dateTexte(r['date']),
        rendu: (_, r) => Text(dateTexte(r['date']))),
    const ColonneTableau(cle: 'heure', libelle: 'Heure', sansCoupure: true),
    const ColonneTableau(cle: 'lit', libelle: 'Lit', sansCoupure: true),
    const ColonneTableau(cle: 'patient', libelle: 'Patient'),
    ColonneTableau(
        cle: 'type',
        libelle: 'Type',
        texte: (r) => '${r['type']}',
        rendu: (_, r) => BadgeSigh('${r['type']}', ton: r['type'] == 'Famille' ? TonSigh.succes : TonSigh.info)),
    const ColonneTableau(cle: 'visiteur', libelle: 'Visiteur'),
    ColonneTableau(
        cle: 'observation',
        libelle: 'Observation',
        texte: (r) => vrai(r['observation']) ? '${r['observation']}' : '—',
        rendu: (_, r) => Text(vrai(r['observation']) ? '${r['observation']}' : '—')),
  ];
}
