import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m1/commun_m1.dart' show bandeauLectureSeule, imprimerM1;
import 'bloc_commun.dart';
import 'bloc_registre.dart';

/// `m3-cr-anesthesie` — « Comptes rendus d'anesthésie » : le déroulé anesthésique de l'intervention (technique, agents, incidents, réveil et décision
/// de sortie).
///
/// Le compte rendu d'anesthésie complète le compte rendu opératoire : deux pièces, deux responsabilités. Il couvre l'induction, l'entretien et le
/// RÉVEIL — la surveillance d'étage reste sur la fiche de surveillance (`m3-surveillance`). Un incident per-opératoire SE NOMME ; « aucun incident »
/// s'écrit aussi (un champ vide ne distingue pas l'absence d'incident de l'oubli).
class EcranCra extends StatelessWidget with EcranMaquette {
  const EcranCra({super.key});

  @override
  String get titre => 'Comptes rendus d’anesthésie';

  @override
  String get description =>
      'Le déroulé anesthésique de l’intervention : technique, agents, incidents, réveil et décision de sortie.';

  @override
  String get regle =>
      'Le compte rendu d’anesthésie complète le compte rendu opératoire : deux pièces, deux responsabilités. Il couvre l’induction, l’entretien et le réveil — la surveillance d’étage, elle, reste sur la fiche de surveillance (m3-surveillance). Un incident per-opératoire se nomme ; « aucun incident » s’écrit aussi.';

  static List<ChampDef> champs(Magasin m) => [
        ChampDef(
            nom: 'patientCode',
            libelle: 'Patient',
            type: TypeChamp.select,
            requis: true,
            options: optionsPatientsBloc(m)),
        const ChampDef(nom: 'dateOperation', libelle: 'Date de l’intervention', type: TypeChamp.date, requis: true),
        ChampDef(nom: 'croReference', libelle: 'Compte rendu opératoire lié', type: TypeChamp.select, options: [
          const OptionChamp('', '— aucun (acte sans CRO) —'),
          for (final c in m.collection('crOperatoires').actives)
            OptionChamp('${c['reference']}', '${c['reference']} — ${c['patient']}'),
        ]),
        ChampDef(
            nom: 'technique',
            libelle: 'Technique employée',
            type: TypeChamp.select,
            requis: true,
            options: [for (final x in blocTechniques) OptionChamp(x)]),
        const ChampDef(
            nom: 'agents',
            libelle: 'Agents et produits employés',
            type: TypeChamp.textarea,
            lignes: 2,
            requis: true),
        champHeure('heureInduction', 'Heure d’induction', requis: true),
        champHeure('heureFin', 'Heure de fin d’anesthésie', requis: true),
        const ChampDef(
            nom: 'incidents',
            libelle: 'Incidents per-opératoires',
            type: TypeChamp.textarea,
            lignes: 2,
            requis: true,
            aide: '« Aucun incident » s’écrit : un champ vide ne distingue pas l’absence d’incident de l’oubli.'),
        const ChampDef(
            nom: 'surveillancePerop',
            libelle: 'Surveillance per-opératoire (constantes, remplissage)',
            type: TypeChamp.textarea,
            lignes: 3),
        champHeure('heureArriveeReveil', 'Arrivée en salle de réveil', requis: true),
        const ChampDef(
            nom: 'etatReveil', libelle: 'État au réveil', type: TypeChamp.textarea, lignes: 2, requis: true),
        ChampDef(
            nom: 'decisionSortie',
            libelle: 'Décision de sortie de salle de réveil',
            type: TypeChamp.select,
            requis: true,
            options: [for (final x in blocDecisionsReveil) OptionChamp(x)]),
        const ChampDef(nom: 'anesthesiste', libelle: 'Anesthésiste', requis: true),
      ];

  static Fiche construire(ContexteEcran c, Map<String, Object?> v, Fiche? existante) =>
      blocConstruirePatientCode(v,
          patient: patientParCodeBloc(c.magasin, v['patientCode']),
          prefixeReference: existante == null ? 'CRA-2026-' : null,
          toutes: c.magasin.collection('crAnesthesie').toutes);

  static String _ou(Object? v) => '${v ?? ''}'.isEmpty ? '—' : '$v';

  static Widget detail(BuildContext ctx, Fiche r) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DescListeSigh([
          ('Référence', r['reference']),
          ('Date', dateBloc(r['dateOperation'])),
          ('Patient', r['patient']),
          ('CRO lié', _ou(r['croReference'])),
          ('Technique', r['technique']),
          ('Induction', _ou(r['heureInduction'])),
          ('Fin', _ou(r['heureFin'])),
          ('Arrivée en réveil', _ou(r['heureArriveeReveil'])),
          ('Décision de sortie', r['decisionSortie']),
          ('Anesthésiste', r['anesthesiste']),
        ]),
        sectionBloc('Agents et produits', texteBloc(_ou(r['agents']))),
        sectionBloc('Incidents per-opératoires', texteBloc(_ou(r['incidents']))),
        if ('${r['surveillancePerop'] ?? ''}'.isNotEmpty)
          sectionBloc('Surveillance per-opératoire', texteBloc('${r['surveillancePerop']}')),
        sectionBloc('État au réveil', texteBloc(_ou(r['etatReveil']))),
      ]);

  static void imprimer(BuildContext ctx, Fiche r) => imprimerM1(ctx,
      titre: 'COMPTE RENDU D’ANESTHÉSIE',
      sousTitre: '${r['reference']} — ${r['patient']}',
      cartouche: [
        ('Patient', '${r['patient']}'),
        ('Dossier', _ou(r['patientCode'])),
        ('Date de l’intervention', dateBloc(r['dateOperation'])),
        ('CRO lié', _ou(r['croReference'])),
        ('Technique', '${r['technique']}'),
        ('Induction — fin', '${_ou(r['heureInduction'])} — ${_ou(r['heureFin'])}'),
      ],
      blocs: [
        BlocTexte('Agents et produits : ${_ou(r['agents'])}'),
        BlocTexte('Incidents per-opératoires : ${_ou(r['incidents'])}'),
        if ('${r['surveillancePerop'] ?? ''}'.isNotEmpty)
          BlocTexte('Surveillance per-opératoire : ${r['surveillancePerop']}'),
        BlocTexte('Arrivée en salle de réveil : ${_ou(r['heureArriveeReveil'])}'),
        BlocTexte('État au réveil : ${_ou(r['etatReveil'])}'),
        BlocTexte('Décision de sortie : ${r['decisionSortie']}', gras: true),
      ],
      signatures: [
        Signature('L’anesthésiste', nom: '${r['anesthesiste']}'),
        const Signature('L’opérateur', mention: 'Pour information'),
      ]);

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('crAnesthesie');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final k = blocKpisCra(col.actives);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          bandeauLectureSeule(c),
          kpisBloc([
            KpiSigh(libelle: 'Comptes rendus', valeur: nombre(k.total), icone: LucideIcons.syringe),
            KpiSigh(
                libelle: 'Avec incident nommé',
                valeur: nombre(k.incidents),
                icone: LucideIcons.triangleAlert,
                ton: k.incidents > 0 ? TonSigh.attention : TonSigh.neutre),
            KpiSigh(
                libelle: 'Surveillances prolongées',
                valeur: nombre(k.prolonges),
                icone: LucideIcons.clock,
                ton: TonSigh.info),
            KpiSigh(
                libelle: 'CRO liés', valeur: nombre(k.cro), icone: LucideIcons.scissors, ton: TonSigh.neutre),
          ]),
          RegistreBloc(
            collection: col,
            entite: 'Compte rendu d’anesthésie',
            prefixeId: 'CRA',
            libelleNouveau: 'Nouveau compte rendu',
            titreNouveau: 'Compte rendu d’anesthésie',
            messageVide: 'Aucun compte rendu d’anesthésie enregistré.',
            lignes: (a) => trierPar([...a], (r) => r['dateOperation']).reversed.toList(),
            champs: (c, _) => champs(c.magasin),
            transformer: construire,
            detail: detail,
            actionsSup: (ctx, r) => [
              BoutonIcone(
                  icone: LucideIcons.printer,
                  libelle: 'Imprimer le compte rendu',
                  onPressed: () => imprimer(ctx, r)),
            ],
            colonnes: [
              const ColonneTableau(cle: 'reference', libelle: 'Référence'),
              ColonneTableau(
                  cle: 'dateOperation',
                  libelle: 'Date',
                  texte: (r) => dateBloc(r['dateOperation']),
                  valeur: (r) => '${r['dateOperation'] ?? ''}'),
              const ColonneTableau(cle: 'patient', libelle: 'Patient'),
              const ColonneTableau(cle: 'technique', libelle: 'Technique'),
              ColonneTableau(
                  cle: 'incidents',
                  libelle: 'Incidents',
                  texte: (r) => blocIncidentNomme(r['incidents']) ? 'Incident nommé' : 'Aucun',
                  rendu: (_, r) => blocIncidentNomme(r['incidents'])
                      ? const BadgeSigh('Incident nommé', ton: TonSigh.attention)
                      : const Text('Aucun',
                          style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12))),
              const ColonneTableau(cle: 'decisionSortie', libelle: 'Sortie de réveil'),
              const ColonneTableau(cle: 'anesthesiste', libelle: 'Anesthésiste'),
            ],
          ),
        ]);
      },
    );
  }
}
