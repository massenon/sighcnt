import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m13/adm_commun.dart';
import '../m4/mat_commun.dart';
import 'rha_commun.dart';

/// `m10-fiches-poste` — description de poste : identification, missions et INDICATEURS CHIFFRÉS (ce sont eux qui rendent l'évaluation NS 131
/// mesurable), relations fonctionnelles, compétences. Seules deux fiches viennent d'un document remis par la clinique ; les autres postes sont recensés
/// à l'organigramme et leur fiche est VIDE, marquée « à rédiger » — jamais inventée.
class EcranFichesPoste extends StatelessWidget with EcranMaquette {
  const EcranFichesPoste({super.key});
  @override
  String get titre => 'Fiches de poste';
  @override
  String get description => 'Identification, missions, indicateurs de performance, relations fonctionnelles et compétences requises.';
  @override
  String? get regle =>
      'Le gabarit est celui des deux descriptions de poste remises par la clinique. Les indicateurs chiffrés en sont le cœur : ce sont eux qui rendent l’évaluation NS 131 mesurable. Les postes sans document reçoivent une fiche vide et marquée — les inventer donnerait à la clinique des missions qu’elle n’a jamais écrites.';

  static List<ChampDef> get _champs => const [
        ChampDef(nom: 'intitule', libelle: 'Intitulé du poste', requis: true),
        ChampDef(nom: 'archivage', libelle: 'Numéro d’archivage'),
        ChampDef(nom: 'elaboration', libelle: 'Date d’élaboration', type: TypeChamp.date),
        ChampDef(nom: 'miseAJour', libelle: 'Date de mise à jour', type: TypeChamp.date),
        ChampDef(nom: 'rattachement', libelle: 'Structure de rattachement', requis: true),
        ChampDef(nom: 'niveauN', libelle: 'Niveau hiérarchique — N'),
        ChampDef(nom: 'niveauSup', libelle: 'Niveau hiérarchique — N+1'),
        ChampDef(nom: 'niveauInf', libelle: 'Niveau hiérarchique — N−1'),
        ChampDef(nom: 'statut', libelle: 'Statut du titulaire'),
        ChampDef(nom: 'textes', libelle: 'Textes réglementaires liés au poste', type: TypeChamp.textarea, lignes: 2),
        ChampDef(nom: 'resume', libelle: 'Résumé succinct du poste', type: TypeChamp.textarea, lignes: 2, requis: true),
        ChampDef.section('Relations fonctionnelles et environnement'),
        ChampDef(nom: 'relationsInternes', libelle: 'Relations internes', type: TypeChamp.textarea, lignes: 2),
        ChampDef(nom: 'relationsExternes', libelle: 'Relations externes', type: TypeChamp.textarea, lignes: 2),
        ChampDef(nom: 'environnement', libelle: 'Environnement et moyens de travail', type: TypeChamp.textarea, lignes: 2),
        ChampDef.section('Compétences et qualifications requises'),
        ChampDef(nom: 'diplomes', libelle: 'Diplômes attendus', type: TypeChamp.textarea, lignes: 2),
        ChampDef(nom: 'savoirFaire', libelle: 'Compétences techniques (savoir-faire)', type: TypeChamp.textarea, lignes: 3),
        ChampDef(nom: 'savoirEtre', libelle: 'Savoir-être', type: TypeChamp.textarea, lignes: 3),
      ];

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('fichesPoste');
    return ListenableBuilder(
        listenable: col,
        builder: (context, _) {
          final rows = col.actives;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KpiGrilleSigh(kpis: rhaKpisW(rhaKpisFichesPoste(rows), const [LucideIcons.fileBadge, LucideIcons.checkCheck, LucideIcons.target, LucideIcons.gauge])),
            const SizedBox(height: 16),
            const NoteSigh(
                'Seules deux fiches proviennent d’un document remis par la clinique. Les autres postes sont recensés depuis l’organigramme et leur fiche est vide, marquée « à rédiger » — les inventer donnerait à la clinique des missions qu’elle n’a jamais écrites, et ces missions serviraient ensuite à évaluer des agents.',
                ton: TonSigh.attention,
                icone: LucideIcons.fileQuestionMark),
            const SizedBox(height: 16),
            TableauSigh(
              colonnes: [
                const ColonneTableau(cle: 'intitule', libelle: 'Intitulé du poste'),
                const ColonneTableau(cle: 'rattachement', libelle: 'Rattachement'),
                ColonneTableau(cle: 'archivage', libelle: 'N° d’archivage', texte: (r) => rhaVrai(r['archivage']) ? '${r['archivage']}' : '—'),
                ColonneTableau(cle: 'missions', libelle: 'Missions', texte: (r) => nombre(rhaMissionsDeFiche(r).length)),
                ColonneTableau(
                    cle: 'redigee',
                    libelle: 'État',
                    texte: (r) => rhaVrai(r['redigee']) ? 'Rédigée' : 'À rédiger',
                    rendu: (_, r) => rhaVrai(r['redigee']) ? const BadgeSigh('Rédigée', ton: TonSigh.succes) : const BadgeSigh('À rédiger', ton: TonSigh.attention)),
              ],
              lignes: trierPar(rows, (r) => r['intitule']),
              messageVide: 'Aucune fiche de poste.',
              nomExport: 'fichesPoste',
              actions: [
                if (c.droit.editer)
                  BoutonSigh(
                      libelle: 'Nouvelle fiche de poste',
                      icone: LucideIcons.plus,
                      taille: TailleBouton.sm,
                      onPressed: () => admSaisir(context,
                          col: col,
                          champs: _champs,
                          titreCreation: 'Fiche de poste',
                          entite: 'Fiche de poste',
                          prefixeId: 'FDP',
                          taille: TailleModale.lg,
                          fiche: (v, ex) => ex == null ? rhaFicheDePosteEnregistrable({...v}) : {...v})),
              ],
              actionsLigne: (ctx, r) => [
                BoutonIcone(icone: LucideIcons.printer, libelle: 'Imprimer la fiche de poste', onPressed: () => _imprimer(context, r)),
                BoutonIcone(
                    icone: LucideIcons.eye,
                    libelle: 'Consulter',
                    onPressed: () => afficherTiroir<void>(context, titre: '${r['intitule']}', largeurMax: 672, corps: _detail(r))),
                ...admActionsLigne(context, c, col, r,
                    modifier: (f) => admSaisir(context, col: col, champs: _champs, titreCreation: '', entite: 'Fiche de poste', taille: TailleModale.lg, existante: f, fiche: (v, ex) => {...v})),
              ],
            ),
          ]);
        });
  }

  Widget _section(String titre, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: CarteSigh(titre: titre, child: child));

  Widget _detail(Fiche r) {
    String t(Object? v) => rhaVrai(v) ? '$v' : '—';
    final missions = rhaMissionsDeFiche(r);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: DescListeSigh([
            ('Intitulé du poste', r['intitule'] as String?),
            ('Numéro d’archivage', t(r['archivage'])),
            ('Élaboration', rhaVrai(r['elaboration']) ? rhaDateFR(r['elaboration']) : '—'),
            ('Mise à jour', rhaVrai(r['miseAJour']) ? rhaDateFR(r['miseAJour']) : '—'),
            ('Structure de rattachement', t(r['rattachement'])),
            ('Niveau N', t(r['niveauN'])),
            ('Niveau N+1', t(r['niveauSup'])),
            ('Niveau N−1', t(r['niveauInf'])),
            ('Statut du titulaire', t(r['statut'])),
            ('Source', t(r['source'])),
          ])),
      if (rhaVrai(r['anomalie'])) Padding(padding: const EdgeInsets.only(bottom: 16), child: NoteSigh('${r['anomalie']}', ton: TonSigh.attention, icone: LucideIcons.triangleAlert)),
      if (rhaVrai(r['resume']))
        _section('Résumé succinct du poste', Text('${r['resume']}', style: const TextStyle(color: JetonsShell.slate600, fontSize: 14, height: 20 / 14))),
      for (final (i, m) in missions.indexed)
        _section(
            'Mission ${i + 1} — ${m['mission']}',
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              MiniTableauSigh(colonnes: [ColonneMini('Activités et tâches', (l) => '${l['a']}')], lignes: [for (final a in (m['activites'] as List? ?? const [])) {'a': a}]),
              const SizedBox(height: 12),
              if ((m['indicateurs'] as List? ?? const []).isNotEmpty) ...[
                const Text('RÉSULTATS ATTENDUS ET INDICATEURS',
                    style: TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, letterSpacing: 0.6)),
                const SizedBox(height: 4),
                MiniTableauSigh(colonnes: [ColonneMini('Indicateur', (l) => '${l['a']}')], lignes: [for (final a in (m['indicateurs'] as List)) {'a': a}]),
              ] else
                const Text('Aucun indicateur chiffré au document.', style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12, fontStyle: FontStyle.italic)),
            ])),
      if (missions.isEmpty)
        const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: NoteSigh('Cette fiche n’a pas encore été rédigée : la clinique n’a remis de description de poste que pour l’Infirmier Général et l’Assistant de Direction.',
                ton: TonSigh.attention, icone: LucideIcons.fileQuestionMark)),
      _section(
          'Relations fonctionnelles et compétences',
          MiniTableauSigh(colonnes: [
            ColonneMini('Rubrique', (l) => '${l['k']}'),
            ColonneMini('Contenu', (l) => '${l['v']}'),
          ], lignes: [
            {'k': 'Relations internes', 'v': t(r['relationsInternes'])},
            {'k': 'Relations externes', 'v': t(r['relationsExternes'])},
            {'k': 'Environnement et moyens', 'v': t(r['environnement'])},
            {'k': 'Diplômes attendus', 'v': t(r['diplomes'])},
            {'k': 'Savoir-faire', 'v': t(r['savoirFaire'])},
            {'k': 'Savoir-être', 'v': t(r['savoirEtre'])},
          ])),
    ]);
  }

  /// La description de poste imprimée : quatre parties dans l'ordre du document (I identification, II missions et indicateurs, III relations, IV compétences).
  void _imprimer(BuildContext ctx, Fiche r) {
    String t(Object? v) => rhaVrai(v) ? '$v' : '—';
    TableauEtat rub(List<(String, String)> l, {String c2 = 'Contenu'}) => TableauEtat(colonnes: [
          ColonneEtat(libelle: 'Rubrique', valeur: (x) => x['k']),
          ColonneEtat(libelle: c2, valeur: (x) => x['v']),
        ], lignes: [
          for (final x in l) {'k': x.$1, 'v': x.$2}
        ]);
    matImprimer(ctx,
        titre: 'DESCRIPTION DE POSTE',
        sousTitre: '${r['intitule']}',
        blocs: [
          const BlocTexte('I — Identification du poste', gras: true),
          BlocTableau(rub([
            ('Intitulé du poste', '${r['intitule']}'),
            ('Numéro d’archivage', t(r['archivage'])),
            ('Élaboration', rhaVrai(r['elaboration']) ? rhaDateFR(r['elaboration']) : '—'),
            ('Structure de rattachement', t(r['rattachement'])),
            ('Niveau hiérarchique', 'N : ${t(r['niveauN'])}   N+1 : ${t(r['niveauSup'])}   N−1 : ${t(r['niveauInf'])}'),
            ('Statut du titulaire', t(r['statut'])),
            ('Textes réglementaires', t(r['textes'])),
            ('Résumé succinct', t(r['resume'])),
          ])),
          const BlocTexte('II — Missions, activités et tâches', gras: true),
          for (final (i, m) in rhaMissionsDeFiche(r).indexed) ...[
            BlocTexte('Mission ${i + 1} : ${m['mission']}', gras: true),
            BlocTableau(TableauEtat(colonnes: [
              ColonneEtat(libelle: 'Activités et tâches', valeur: (x) => x['a']),
              ColonneEtat(libelle: 'Résultats attendus et indicateurs', valeur: (x) => x['i']),
            ], lignes: [
              for (final (j, a) in (m['activites'] as List? ?? const []).indexed)
                {'a': 'Activité ${j + 1} : $a', 'i': j < (m['indicateurs'] as List? ?? const []).length ? (m['indicateurs'] as List)[j] : ''}
            ])),
          ],
          const BlocTexte('III — Relations fonctionnelles et environnement de travail', gras: true),
          BlocTableau(rub([
            ('Au plan interne', t(r['relationsInternes'])),
            ('Au plan externe', t(r['relationsExternes'])),
            ('Environnement et moyens de travail', t(r['environnement'])),
          ])),
          const BlocTexte('IV — Compétences et qualifications requises', gras: true),
          BlocTableau(TableauEtat(colonnes: [
            ColonneEtat(libelle: 'Diplômes attendus', valeur: (x) => x['d']),
            ColonneEtat(libelle: 'Compétences techniques (savoir-faire)', valeur: (x) => x['sf']),
            ColonneEtat(libelle: 'Savoir-être', valeur: (x) => x['se']),
          ], lignes: [
            {'d': t(r['diplomes']), 'sf': t(r['savoirFaire']), 'se': t(r['savoirEtre'])}
          ])),
        ],
        signatures: const [Signature('Le titulaire du poste', nom: ''), Signature('La Direction', nom: '', mention: 'Signature et cachet')]);
  }
}
