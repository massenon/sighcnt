import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'surv_commun.dart';

/// `m3-glasgow` — « Score de Glasgow » : le score est la SOMME des trois axes, calculé et jamais saisi (3 à 15). Règles : `hosGlasgow`,
/// `hosScoreGlasgow`, `hosTonGlasgow` (packages/domaine). E364 : la modification relit le patient et les axes de la fiche et RECALCULE le score.
class EcranGlasgow extends StatelessWidget with EcranMaquette {
  const EcranGlasgow({super.key});

  @override
  String get titre => 'Score de Glasgow';

  @override
  String get description =>
      'Évaluation de la conscience, adulte et enfant : ouverture des yeux, réponse verbale, réponse motrice.';

  @override
  String get regle =>
      'Le score est calculé, jamais saisi : il vaut de 3 à 15, chaque axe valant au minimum 1. Une saisie libre autoriserait un « 2/15 » qui n’existe pas — et c’est la borne basse que les soignants vérifient en premier en relisant une feuille.';

  static String _codePatientDe(Magasin m, Fiche? r) {
    if (r == null) return '';
    if (vrai(r['patientCode'])) return '${r['patientCode']}';
    final p = m.collection('patients').actives.where((x) => x['id'] == r['patientId']).firstOrNull;
    return p == null ? '' : '${p['code']}';
  }

  static List<ChampDef> champs(Magasin m, Fiche? r) => [
        ChampDef(
            nom: 'patientCode',
            libelle: 'Patient',
            type: TypeChamp.select,
            requis: true,
            options: optionsPatientsM3(m)),
        const ChampDef(
            nom: 'nip', libelle: 'NIP', aide: 'Recopié du dossier, comme sur la feuille papier.'),
        ...champsDateHeure('dateHeure', 'de l’évaluation'),
        for (var i = 0; i < hosGlasgow.length; i++)
          ChampDef(
              nom: 'axe$i',
              libelle: hosGlasgow[i].$1,
              type: TypeChamp.select,
              requis: true,
              options: [
                for (final it in hosGlasgow[i].$2)
                  OptionChamp('${it.$2}', '${it.$1} — ${it.$2} point(s)')
              ]),
        const ChampDef(
            nom: 'observation',
            libelle: 'Observation',
            type: TypeChamp.textarea,
            lignes: 2,
            col: ColChamp.plein),
        ChampDef(
            nom: 'evaluePar',
            libelle: 'Évalué par',
            type: TypeChamp.select,
            requis: true,
            options: optionsSoignants(m, (x) => x['execute'] == true || x['prescrit'] == true)),
      ];

  static Map<String, Object?> initiales(Magasin m, Fiche? r) {
    if (r == null) return {};
    final axes = (r['axes'] as List?) ?? const [];
    return {
      'patientCode': _codePatientDe(m, r),
      'nip': r['nip'] ?? '',
      ...separerDateHeure('dateHeure', r['dateHeure']),
      for (var i = 0; i < axes.length && i < 3; i++) 'axe$i': '${(axes[i] as Map)['points']}',
      'observation': r['observation'] ?? '',
      'evaluePar': r['evaluePar'] ?? '',
    };
  }

  /// `transformerGlasgow` : le score est RECALCULÉ à la création comme à la modification (E364).
  static Fiche construire(Magasin m, CollectionMagasin col, Map<String, Object?> v, Fiche? r) {
    final pt = patientParCode(m, v['patientCode']);
    final calcul = hosScoreGlasgow([for (var i = 0; i < 3; i++) int.tryParse('${v['axe$i']}') ?? 0]);
    return {
      if (r == null) 'statut': 'actif',
      'patientCode': v['patientCode'],
      'nip': vrai(v['nip']) ? v['nip'] : v['patientCode'],
      'dateHeure': joindreDateHeure(v, 'dateHeure'),
      'axe0': v['axe0'],
      'axe1': v['axe1'],
      'axe2': v['axe2'],
      'observation': v['observation'],
      'evaluePar': v['evaluePar'],
      'reference': r?['reference'] ?? referenceSuivante('GCS-', 4, col.toutes),
      'patientId': pt?['id'],
      'patient': pt != null ? '${pt['nom']} ${pt['prenom']}' : v['patientCode'],
      'axes': calcul.axes,
      'score': calcul.score,
      'evaluateur': nomSoignant(m, v['evaluePar']),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('scoresGlasgow');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final rows = col.actives;
        final graves = rows.where((r) => (r['score'] as num) <= 8).length;
        final moyens = rows.where((r) => (r['score'] as num) >= 9 && (r['score'] as num) <= 12).length;
        final patients = {for (final r in rows) if (vrai(r['patientId'])) r['patientId']}.length;
        final tri = trierPar(rows, (r) => r['dateHeure']).reversed.toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Évaluations', valeur: nombre(rows.length), icone: LucideIcons.brain, ton: TonSigh.navy),
            KpiSigh(
                libelle: 'Score ≤ 8 — coma',
                valeur: nombre(graves),
                icone: LucideIcons.siren,
                ton: graves > 0 ? TonSigh.danger : TonSigh.succes),
            KpiSigh(
                libelle: 'Score 9 à 12',
                valeur: nombre(moyens),
                icone: LucideIcons.triangleAlert,
                ton: moyens > 0 ? TonSigh.attention : TonSigh.neutre),
            KpiSigh(libelle: 'Patients évalués', valeur: nombre(patients), icone: LucideIcons.users, ton: TonSigh.info),
          ]),
          const SizedBox(height: 16),
          const NoteSigh(
              'Le logiciel calcule et signale ; il ne diagnostique pas. Un score de 8 ou moins est classiquement le seuil du coma, mais l’appréciation clinique revient au médecin — et un score isolé ne vaut rien sans son évolution.',
              ton: TonSigh.info,
              icone: LucideIcons.brain),
          const SizedBox(height: 16),
          RegistreFormulaire(
            collection: col,
            lignes: tri,
            prefixe: 'GCS',
            nomExport: 'scoresGlasgow',
            messageVide: 'Aucune évaluation enregistrée.',
            libelleNouveau: 'Nouvelle évaluation',
            titreCreation: 'Score de Glasgow',
            toastCreation: 'Évaluation créé.',
            champs: (r) => champs(c.magasin, r),
            initiales: (r) => initiales(c.magasin, r),
            construire: (v, r) => construire(c.magasin, col, v, r),
            titreFiche: (r) => '${r['reference']} — ${r['score']}/15',
            colonnes: [
              const ColonneTableau(cle: 'reference', libelle: 'Référence'),
              ColonneTableau(
                  cle: 'dateHeure',
                  libelle: 'Date et heure',
                  texte: (r) => dateHeureTexte(r['dateHeure']),
                  rendu: (_, r) => Text(dateHeureTexte(r['dateHeure']))),
              ColonneTableau(
                  cle: 'patient',
                  libelle: 'Patient',
                  texte: (r) => '${r['patient']} — NIP ${vrai(r['nip']) ? r['nip'] : '—'}'),
              ColonneTableau(
                  cle: 'score',
                  libelle: 'Score',
                  texte: (r) => '${r['score']} / 15',
                  rendu: (_, r) => BadgeSigh('${r['score']} / 15', ton: tonDe(hosTonGlasgow(r['score'] as num)))),
              const ColonneTableau(cle: 'evaluateur', libelle: 'Évalué par'),
            ],
            detail: (ctx, r) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DescListeSigh([
                ('Référence', r['reference']),
                ('Patient', r['patient']),
                ('NIP', vrai(r['nip']) ? r['nip'] : '—'),
                ('Date et heure', dateHeureTexte(r['dateHeure'])),
                ('Score total', '${r['score']} / 15 (calculé)'),
                ('Évalué par', r['evaluateur']),
              ]),
              sectionDetail(
                  'Détail par axe',
                  MiniTableauSigh(colonnes: [
                    ColonneMini('Axe', (a) => '${a['axe']}'),
                    ColonneMini('Réponse observée', (a) => '${a['libelle']}'),
                    ColonneMini('Points', (a) => '${a['points']}'),
                  ], lignes: [
                    for (final a in (r['axes'] as List? ?? const [])) (a as Map).cast<String, Object?>()
                  ])),
              if (vrai(r['observation'])) sectionDetail('Observation', paragrapheDetail('${r['observation']}')),
            ]),
          ),
        ]);
      },
    );
  }
}
