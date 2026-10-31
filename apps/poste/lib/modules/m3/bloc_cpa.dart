import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m1/commun_m1.dart' show bandeauLectureSeule, imprimerM1;
import 'bloc_commun.dart';
import 'bloc_registre.dart';

/// `m3-cpa` — « Consultation pré-anesthésique » : évaluation avant anesthésie (classe ASA, score de Mallampati, technique proposée, conclusion
/// d'aptitude). Les règles (réserves nommées, interventions sans CPA signalées) sont dans `packages/domaine/lib/src/hospitalisation/bloc_regles.dart`.
///
/// La CPA précède l'intervention : une intervention SANS CPA est SIGNALÉE, jamais bloquée — l'urgence vitale n'attend pas une fiche. Une CPA
/// « avec réserves » ou « à reporter » EXIGE ses réserves nommées, à la création comme à la modification. Les échelles ASA et Mallampati et la
/// liste des techniques ont été ARRÊTÉES par les praticiens du bloc le 01/09/2026 (validation écrite).
///
/// Comme la maquette (`amorcerAnesthesie`), l'écran sème six CPA adossées aux admissions quand la collection est vide (écart E417 : le jeu du poste
/// n'en porte pas).
class EcranCpa extends StatefulWidget with EcranMaquette {
  const EcranCpa({super.key});

  @override
  String get titre => 'Consultation pré-anesthésique';

  @override
  String get description =>
      'Évaluation avant anesthésie : classe ASA, score de Mallampati, technique proposée, conclusion d’aptitude.';

  @override
  String get regle =>
      'La CPA précède l’intervention : une intervention sans CPA est signalée, jamais bloquée — l’urgence vitale n’attend pas une fiche. Les échelles proposées (ASA, Mallampati) ne viennent d’aucun document remis : comme les check-listes du bloc, elles ont été arrêtées par les praticiens du bloc le 01/09/2026 (validation écrite).';

  static List<ChampDef> champs(Magasin m) => [
        ChampDef(
            nom: 'patientCode',
            libelle: 'Patient',
            type: TypeChamp.select,
            requis: true,
            options: optionsPatientsBloc(m)),
        const ChampDef(nom: 'date', libelle: 'Date de la consultation', type: TypeChamp.date, requis: true),
        ChampDef(
            nom: 'asa',
            libelle: 'Classe ASA',
            type: TypeChamp.select,
            requis: true,
            options: [for (final x in blocAsa) OptionChamp(x.id, x.label)]),
        ChampDef(
            nom: 'mallampati',
            libelle: 'Score de Mallampati',
            type: TypeChamp.select,
            requis: true,
            options: [for (final x in blocMallampati) OptionChamp(x.id, x.label)]),
        ChampDef(
            nom: 'technique',
            libelle: 'Technique d’anesthésie proposée',
            type: TypeChamp.select,
            requis: true,
            options: [for (final x in blocTechniques) OptionChamp(x)]),
        const ChampDef(
            nom: 'antecedentsAnesthesiques',
            libelle: 'Antécédents anesthésiques',
            type: TypeChamp.textarea,
            lignes: 2,
            requis: true,
            aide: '« Aucun » se dit — un champ vide ne distingue pas l’absence d’antécédent de l’oubli.'),
        const ChampDef(nom: 'allergies', libelle: 'Allergies', requis: true),
        const ChampDef(
            nom: 'jeuneConsigne',
            libelle: 'Consigne de jeûne pré-opératoire donnée',
            type: TypeChamp.case_),
        ChampDef(
            nom: 'conclusion',
            libelle: 'Conclusion',
            type: TypeChamp.select,
            requis: true,
            options: [for (final x in blocConclusionsCpa) OptionChamp(x)]),
        const ChampDef(
            nom: 'observations',
            libelle: 'Observations et réserves',
            type: TypeChamp.textarea,
            lignes: 2,
            aide: 'Obligatoires dès que la conclusion n’est pas « Apte à l’anesthésie ».'),
        const ChampDef(nom: 'anesthesiste', libelle: 'Anesthésiste', requis: true),
      ];

  static Fiche construire(ContexteEcran c, Map<String, Object?> v, Fiche? existante) =>
      blocConstruirePatientCode(v,
          patient: patientParCodeBloc(c.magasin, v['patientCode']),
          prefixeReference: existante == null ? 'CPA-2026-' : null,
          toutes: c.magasin.collection('cpa').toutes);

  static void imprimer(BuildContext ctx, Fiche r) => imprimerM1(ctx,
      titre: 'CONSULTATION PRÉ-ANESTHÉSIQUE',
      sousTitre: '${r['reference']} — ${r['patient']}',
      cartouche: [
        ('Patient', '${r['patient']}'),
        ('Dossier', r['patientCode'] == null || r['patientCode'] == '' ? '—' : '${r['patientCode']}'),
        ('Date', dateBloc(r['date'])),
        ('Classe ASA', 'ASA ${r['asa']}'),
        ('Mallampati', '${r['mallampati']}'),
        ('Technique proposée', '${r['technique']}'),
      ],
      blocs: [
        BlocTexte('Antécédents anesthésiques : ${_ou(r['antecedentsAnesthesiques'])}'),
        BlocTexte('Allergies : ${_ou(r['allergies'])}'),
        BlocTexte('Consigne de jeûne pré-opératoire : ${r['jeuneConsigne'] == true ? 'donnée' : 'NON donnée'}'),
        BlocTexte('Conclusion : ${r['conclusion']}', gras: true),
        if ('${r['observations'] ?? ''}'.isNotEmpty) BlocTexte('Réserves : ${r['observations']}'),
      ],
      signatures: [Signature('L’anesthésiste', nom: '${r['anesthesiste'] ?? ''}')]);

  static String _ou(Object? v) => '${v ?? ''}'.isEmpty ? '—' : '$v';

  static Widget detail(BuildContext ctx, Fiche r) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DescListeSigh([
          ('Référence', r['reference']),
          ('Date', dateBloc(r['date'])),
          ('Patient', r['patient']),
          ('Dossier', r['patientCode'] ?? '—'),
          ('Classe ASA', 'ASA ${r['asa']}'),
          ('Mallampati', r['mallampati']),
          ('Technique proposée', r['technique']),
          ('Jeûne consigné', r['jeuneConsigne'] == true ? 'Oui' : 'Non'),
          ('Anesthésiste', r['anesthesiste']),
        ]),
        sectionBloc('Antécédents anesthésiques', texteBloc(_ou(r['antecedentsAnesthesiques']))),
        sectionBloc('Allergies', texteBloc(_ou(r['allergies']))),
        sectionBloc(
            'Conclusion',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Align(
                  alignment: Alignment.centerLeft,
                  child: BadgeSigh('${r['conclusion']}',
                      ton: r['conclusion'] == blocConclusionsCpa[0] ? TonSigh.succes : TonSigh.attention)),
              if ('${r['observations'] ?? ''}'.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 8), child: texteBloc('${r['observations']}')),
            ])),
      ]);

  @override
  State<EcranCpa> createState() => _EtatCpa();
}

class _EtatCpa extends State<EcranCpa> {
  bool _amorce = false;

  /// `amorcerAnesthesie()` : six CPA adossées aux admissions, une seule fois, quand la collection est vide (archivées comprises).
  void _amorcer(ContexteEcran c) {
    if (_amorce) return;
    _amorce = true;
    final col = c.magasin.collection('cpa');
    if (col.toutes.isNotEmpty) return;
    for (final f in blocAmorcerCpa(c.magasin.collection('admissions').actives).reversed) {
      col.inserer(f, prefixe: 'CPA');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    _amorcer(c);
    final cpa = c.magasin.collection('cpa');
    final cro = c.magasin.collection('crOperatoires');
    return ListenableBuilder(
      listenable: Listenable.merge([cpa, cro]),
      builder: (context, _) {
        final k = blocKpisCpa(cpa.actives, cro.actives);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          bandeauLectureSeule(c),
          kpisBloc([
            KpiSigh(libelle: 'CPA enregistrées', valeur: nombre(k.cpa), icone: LucideIcons.stethoscope),
            KpiSigh(
                libelle: 'Aptes sans réserve',
                valeur: nombre(k.aptes),
                icone: LucideIcons.circleCheck,
                ton: TonSigh.succes),
            KpiSigh(
                libelle: 'Avec réserves ou report',
                valeur: nombre(k.reserves),
                icone: LucideIcons.triangleAlert,
                ton: k.reserves > 0 ? TonSigh.attention : TonSigh.neutre),
            KpiSigh(
                libelle: 'Interventions sans CPA',
                valeur: nombre(k.sansCpa),
                icone: LucideIcons.shieldAlert,
                ton: k.sansCpa > 0 ? TonSigh.danger : TonSigh.neutre,
                indice: 'Signalées, jamais bloquées — l’urgence n’attend pas'),
          ]),
          const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: NoteSigh(
                  'Les échelles ASA et Mallampati et la liste des techniques sont des arrêtées par les praticiens du bloc le 01/09/2026 — proposées à l’origine, aucun document de la clinique ne les fixait ; la provenance reste dite. Les fiches déjà saisies conservent leurs valeurs telles quelles.',
                  icone: LucideIcons.circleCheck)),
          RegistreBloc(
            collection: cpa,
            entite: 'CPA',
            prefixeId: 'CPA',
            libelleNouveau: 'Nouvelle CPA',
            titreNouveau: 'Consultation pré-anesthésique',
            messageVide: 'Aucune consultation pré-anesthésique enregistrée.',
            lignes: (a) => trierPar([...a], (r) => r['date']).reversed.toList(),
            champs: (c, _) => EcranCpa.champs(c.magasin),
            avant: (c, v, _) => blocRefusCpa(v),
            transformer: EcranCpa.construire,
            detail: EcranCpa.detail,
            actionsSup: (ctx, r) => [
              BoutonIcone(
                  icone: LucideIcons.printer,
                  libelle: 'Imprimer la fiche',
                  onPressed: () => EcranCpa.imprimer(ctx, r)),
            ],
            colonnes: [
              const ColonneTableau(cle: 'reference', libelle: 'Référence'),
              ColonneTableau(
                  cle: 'date',
                  libelle: 'Date',
                  texte: (r) => dateBloc(r['date']),
                  valeur: (r) => '${r['date'] ?? ''}'),
              ColonneTableau(
                  cle: 'patient',
                  libelle: 'Patient',
                  texte: (r) => '${r['patient']} — ${_code(r)}'),
              ColonneTableau(
                  cle: 'asa',
                  libelle: 'ASA',
                  texte: (r) => 'ASA ${r['asa']}',
                  rendu: (_, r) => BadgeSigh('ASA ${r['asa']}',
                      ton: ['III', 'IV', 'V'].contains(r['asa']) ? TonSigh.attention : TonSigh.info)),
              const ColonneTableau(cle: 'mallampati', libelle: 'Mallampati'),
              const ColonneTableau(cle: 'technique', libelle: 'Technique proposée'),
              ColonneTableau(
                  cle: 'conclusion',
                  libelle: 'Conclusion',
                  rendu: (_, r) => BadgeSigh('${r['conclusion']}',
                      ton: r['conclusion'] == blocConclusionsCpa[0]
                          ? TonSigh.succes
                          : (r['conclusion'] == blocConclusionsCpa[2] ? TonSigh.danger : TonSigh.attention))),
            ],
          ),
        ]);
      },
    );
  }

  static String _code(Fiche r) => '${r['patientCode'] ?? ''}'.isEmpty ? '—' : '${r['patientCode']}';
}
