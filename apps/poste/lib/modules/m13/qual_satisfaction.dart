import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'qual_commun.dart';

/// `adm-satisfaction` — « Satisfaction des patients » : la LECTURE de l'enquête de satisfaction (notes moyennes par question, recommandation, derniers
/// commentaires). Tout est CALCULÉ depuis les réponses recueillies, à chaque affichage — le recueil se fait à l'écran des enquêtes. L'écran est en
/// lecture seule : aucune commande d'écriture. Le questionnaire, proposé faute de document de cadrage, a été validé par la Direction le 01/09/2026.
///
/// Les calculs (moyennes arrondies au dixième, notes nulles ou non numériques ignorées, recommandation reconnue par le code ou le libellé, huit derniers
/// commentaires) sont ceux de `qualSatisfaction`, rejoués sur les vecteurs de la maquette.
class EcranSatisfaction extends StatelessWidget with EcranMaquette {
  const EcranSatisfaction({super.key});

  @override
  String get titre => 'Satisfaction des patients';

  @override
  String get description =>
      'La lecture de l’enquête de satisfaction : notes moyennes par question, recommandation, derniers commentaires.';

  @override
  String get regle =>
      'Tout est calculé depuis les réponses recueillies — le recueil se fait à l’écran des enquêtes. Le questionnaire, proposé faute de document de cadrage, a été validé par la Direction le 01/09/2026 ; il reste modifiable à l’écran des enquêtes.';

  @override
  Widget build(BuildContext context) {
    final m = ContexteEcran.of(context).magasin;
    final enquetes = colEnquetes(m), reponses = colReponses(m);
    return ListenableBuilder(
        listenable: Listenable.merge([enquetes, reponses]),
        builder: (context, _) {
          final enq = qualEnqueteSatisfaction(enquetes.actives);
          if (enq == null) {
            return const VideSigh('Aucune enquête de satisfaction — en créer une à l’écran des enquêtes.',
                icone: LucideIcons.clipboardList);
          }
          final s = qualSatisfaction(enq, reponses.actives);
          final avecNotes = s.notes.isNotEmpty;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KpiGrilleSigh(kpis: [
              KpiSigh(
                  libelle: 'Réponses recueillies',
                  valeur: nombre(s.reponses),
                  icone: LucideIcons.messagesSquare,
                  ton: TonSigh.navy),
              KpiSigh(
                  libelle: 'Note moyenne globale',
                  valeur: s.noteGlobale,
                  icone: LucideIcons.star,
                  ton: (s.globale ?? 0) >= 4 ? TonSigh.succes : TonSigh.attention),
              KpiSigh(
                  libelle: 'Recommanderaient la clinique',
                  valeur: s.recommandation,
                  icone: LucideIcons.thumbsUp,
                  ton: TonSigh.info),
              KpiSigh(
                  libelle: 'Avec commentaire libre',
                  valeur: nombre(s.avecCommentaire),
                  icone: LucideIcons.messageSquareText,
                  ton: TonSigh.neutre),
            ]),
            const SizedBox(height: 16),
            if (enq['aValider'] == true)
              const NoteSigh(
                  'Le questionnaire est une proposition à valider par la Direction — aucun document de cadrage n’en fixe le contenu.',
                  ton: TonSigh.attention,
                  icone: LucideIcons.circleHelp)
            else
              NoteSigh(
                  'Questionnaire validé par la Direction${enq['valideLe'] != null ? ' le ${dateJj(enq['valideLe'])}' : ''}. Les réponses du jeu de démonstration restent marquées comme telles par leur champ « saisi par ».',
                  icone: LucideIcons.circleCheck),
            const SizedBox(height: 16),
            CarteSigh(
                titre: 'Note moyenne par question',
                child: avecNotes
                    ? GraphiqueBarres(
                        horizontal: true,
                        hauteur: 220,
                        etiquettes: [for (final n in s.notes) n.libelle],
                        series: [
                          SerieGraphique('Moyenne / 5', [for (final n in s.notes) n.moyenne ?? 0])
                        ])
                    : const VideSigh('Aucune question de type note.', icone: LucideIcons.star)),
            const SizedBox(height: 16),
            CarteSigh(
                titre: 'Derniers commentaires',
                child: s.commentaires.isEmpty
                    ? const VideSigh('Aucun commentaire libre recueilli.', icone: LucideIcons.messageSquareText)
                    : Column(children: [
                        for (final (i, x) in s.commentaires.indexed)
                          Container(
                              width: double.infinity,
                              margin: EdgeInsets.only(top: i == 0 ? 0 : 8),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: JetonsShell.slate200)),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('« ${x.texte} »',
                                    style: const TextStyle(
                                        color: JetonsShell.slate700, fontSize: 14, height: 20 / 14)),
                                Text(dateJj(x.date),
                                    style: const TextStyle(
                                        color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
                              ])),
                      ])),
            sourceQual('Réponses de l’enquête « ${enq['titre']} » — recalculé à chaque affichage.'),
          ]);
        });
  }
}
