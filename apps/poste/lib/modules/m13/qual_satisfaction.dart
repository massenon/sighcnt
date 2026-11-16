import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../donnees/satisfaction_poste.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'qual_commun.dart';

/// `adm-satisfaction` — « Satisfaction des patients » : la LECTURE de l'enquête de satisfaction (notes moyennes par question, recommandation, derniers
/// commentaires). Tout est CALCULÉ depuis les réponses recueillies, à chaque affichage — le recueil se fait à l'écran des enquêtes. L'écran est en
/// lecture seule : aucune commande d'écriture. Le questionnaire, proposé faute de document de cadrage, a été validé par la Direction le 01/09/2026.
///
/// Les calculs (moyennes arrondies au dixième, notes nulles ou non numériques ignorées, recommandation reconnue par le code ou le libellé, huit derniers
/// commentaires) sont ceux de `qualSatisfaction`, rejoués sur les vecteurs de la maquette.
class EcranSatisfaction extends StatefulWidget with EcranMaquette {
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
  State<EcranSatisfaction> createState() => _EtatSatisfaction();
}

class _EtatSatisfaction extends State<EcranSatisfaction> {
  // Lot SAT : les filtres de la carte « Analyse » (période, point de collecte, version du questionnaire, canal).
  String _du = '', _au = '', _point = '', _version = '', _canal = '';

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
            _carteAnalyse(context, enq, reponses.actives),
            sourceQual('Réponses de l’enquête « ${enq['titre']} » — recalculé à chaque affichage.'),
          ]);
        });
  }

  /// La carte « Analyse » (lot SAT) : filtres et indicateurs recalculés des réponses. « Non calculable » n'est pas zéro ; le taux de réponse demande les passages comptés à l'accueil.
  Widget _carteAnalyse(BuildContext context, Fiche enq, Iterable<Fiche> reponses) {
    final c = ContexteEcran.of(context);
    final points = pointsCollectePoste(c.magasin, c.aujourdhui);
    final a = qualAnalyse(enq, reponses, du: _du, au: _au, point: _point, version: _version, canal: _canal, points: points);
    final versions = qualVersionsDe(enq);
    Widget liste(String cle, String libelle, String valeur, List<(String, String)> options, void Function(String) surChoix) => SizedBox(
        width: 190,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LibelleChamp(libelle),
          DropdownButtonFormField<String>(
              key: Key('qual:an:$cle'),
              initialValue: valeur,
              isExpanded: true,
              decoration: decorationChamp(),
              items: [for (final o in options) DropdownMenuItem(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => surChoix(v ?? ''))),
        ]));
    Widget date(String cle, String libelle, String valeur, void Function(String) surChoix) => SizedBox(
        width: 170,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LibelleChamp(libelle),
          TextFormField(
              key: Key('qual:an:$cle'),
              initialValue: valeur,
              decoration: decorationChamp().copyWith(hintText: 'AAAA-MM-JJ'),
              onChanged: (v) {
                if (v.isEmpty || RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) setState(() => surChoix(v));
              }),
        ]));
    return CarteSigh(
        titre: 'Analyse',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 12, runSpacing: 12, children: [
            date('du', 'Du', _du, (v) => _du = v),
            date('au', 'Au', _au, (v) => _au = v),
            liste('point', 'Point de collecte', _point, [('', 'Tous les points'), for (final p in points) (p.code, p.libelle)], (v) => _point = v),
            liste('version', 'Version du questionnaire', _version, [('', 'Toutes les versions'), for (final v in versions) ('${v['version']}', '${v['version']} (depuis le ${dateJj(v['effetLe'])})')], (v) => _version = v),
            liste('canal', 'Canal', _canal, [('', 'Tous les canaux'), for (final x in [...qualCanaux, qualCanalPublic]) (x, x)], (v) => _canal = v),
          ]),
          const SizedBox(height: 12),
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Réponses (filtre)', valeur: nombre(a.reponses), icone: LucideIcons.messagesSquare, ton: TonSigh.navy),
            KpiSigh(libelle: 'Taux de satisfaction', valeur: qualPctOuNC(a.satisfaction), icone: LucideIcons.smile, ton: TonSigh.succes, indice: 'Notes 4 ou 5 sur 5'),
            KpiSigh(libelle: 'Taux de recommandation', valeur: qualPctOuNC(a.recommandation), icone: LucideIcons.thumbsUp, ton: TonSigh.info),
            KpiSigh(libelle: 'Taux de réponse', valeur: qualPctOuNC(a.tauxReponse), icone: LucideIcons.percent, ton: TonSigh.neutre, indice: 'Passages à l’accueil non comptés'),
          ]),
          const SizedBox(height: 12),
          MiniTableauSigh(colonnes: [
            ColonneMini('Question', (l) => '${l['a']}'),
            ColonneMini('Notes', (l) => '${l['b']}'),
            ColonneMini('Moyenne', (l) => '${l['c']}'),
            ColonneMini('Satisfaction', (l) => '${l['d']}'),
          ], lignes: [
            for (final q in a.parQuestion) {'a': q.libelle, 'b': nombre(q.n), 'c': q.moyenne == null ? 'Non calculable' : nombre(q.moyenne, 1), 'd': qualPctOuNC(q.satisfaction)}
          ]),
          const SizedBox(height: 12),
          MiniTableauSigh(colonnes: [
            ColonneMini('Mois', (l) => '${l['a']}'),
            ColonneMini('Réponses', (l) => '${l['b']}'),
            ColonneMini('Satisfaction', (l) => '${l['c']}'),
          ], lignes: [
            for (final x in a.parMois) {'a': x.mois, 'b': nombre(x.n), 'c': qualPctOuNC(x.satisfaction)}
          ]),
          const SizedBox(height: 12),
          MiniTableauSigh(colonnes: [
            ColonneMini('Point de collecte', (l) => '${l['a']}'),
            ColonneMini('Réponses', (l) => '${l['b']}'),
            ColonneMini('Satisfaction', (l) => '${l['c']}'),
          ], lignes: [
            for (final x in a.parPoint) {'a': x.libelle, 'b': nombre(x.n), 'c': qualPctOuNC(x.satisfaction)}
          ]),
        ]));
  }
}
