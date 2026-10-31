import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'rhb_commun.dart';

/// `m10-sanctions` — « Sanctions » : écran CALCULÉ. Une sanction découle d'une évaluation NS 131 dont la retenue est supérieure à zéro ; elle ne se saisit pas
/// ici (la corriger = modifier l'évaluation d'origine, ce qui recalcule la retenue). Aucune commande d'écriture : l'écran n'en a pas.
class EcranSanctions extends StatelessWidget with EcranMaquette {
  const EcranSanctions({super.key});

  @override
  String get description => 'Sanctions issues des évaluations mensuelles et sanctions disciplinaires, avec incidence sur le salaire.';

  @override
  String get regle =>
      'Écran calculé : une sanction découle d’une évaluation NS 131 dont la retenue est supérieure à zéro. Elle ne se saisit pas ici — pour la corriger, modifier l’évaluation d’origine, ce qui recalcule la retenue et laisse trace du motif (RG-12).';

  @override
  Widget build(BuildContext context) => RhbEcoute(collections: const ['evaluations', 'personnel', 'baremeNS131', 'historiqueBareme'], construire: _corps);

  /// Les critères DONT le résultat entraîne une retenue sur cette évaluation, au barème EN VIGUEUR À SA DATE (E650 levé).
  static List<RhbCritere> critSanctionnes(Fiche e, List<Fiche> bareme, List<Fiche> historique) => [
        for (final k in rhbCriteresALaDate(bareme, historique, rhbDateBaremeDe(e)))
          if (k.sanction((e['criteres'] as Map?)?[k.id]) > 0) k
      ];

  Widget _corps(BuildContext context, ContexteEcran c) {
    final evals = [for (final e in rhbActives(c, 'evaluations')) if ((e['prelevementPct'] as num? ?? 0) > 0) e];
    num somme(Iterable<Fiche> l, String k) => l.fold<num>(0, (s, e) => s + ((e[k] as num?) ?? 0));
    final personnel = rhbActives(c, 'personnel');
    String serviceDe(Fiche e) {
      final s = e['service'];
      if (s != null && s != '') return '$s';
      final a = personnel.where((x) => x['id'] == e['employeId']).firstOrNull;
      final sa = a?['service'];
      return sa == null || sa == '' ? 'Non renseigné' : '$sa';
    }

    final moy = evals.isNotEmpty ? arrondiJs(somme(evals, 'prelevementPct') / evals.length).toInt() : 0;
    final bareme = rhbActives(c, 'baremeNS131'), historiqueB = rhbActives(c, 'historiqueBareme');
    final parCritere = trierPar([
      for (final k in rhbCriteresALaDate(bareme, historiqueB, iso(c.aujourdhui)))
        (() {
          final touchees = [
            for (final e in evals)
              if ((rhbCriteresALaDate(bareme, historiqueB, rhbDateBaremeDe(e)).where((x) => x.id == k.id).firstOrNull?.sanction((e['criteres'] as Map?)?[k.id]) ?? 0) > 0) e
          ];
          return (label: k.label, n: touchees.length, montant: somme(touchees, 'prelevementMontant'));
        })()
    ], (x) => x.n, descendant: true);
    final parService = rhbGrouper(evals, serviceDe);
    final parPeriode = rhbGrouper(evals, (e) => '${e['periode']}');
    final periodes = parPeriode.keys.toList();
    return rhbEspace([
      KpiGrilleSigh(kpis: [
        KpiSigh(libelle: 'Sanctions prononcées', valeur: nombre(evals.length), icone: LucideIcons.gavel, ton: TonSigh.danger),
        KpiSigh(libelle: 'Agents concernés', valeur: nombre(evals.map((e) => e['employeId']).toSet().length), icone: LucideIcons.users, ton: TonSigh.attention),
        KpiSigh(libelle: 'Montant total retenu', valeur: money(somme(evals, 'prelevementMontant')), icone: LucideIcons.wallet, ton: TonSigh.danger),
        KpiSigh(libelle: 'Prélèvement moyen', valeur: '$moy %', icone: LucideIcons.percent, ton: TonSigh.neutre),
      ]),
      const NoteSigh('Les sanctions sont exclusivement issues du barème $rhbNs131Reference. Aucune retenue ne peut être appliquée hors de ce cadre.',
          ton: TonSigh.attention, icone: LucideIcons.shieldAlert),
      TableauSigh(
        titre: 'Registre des sanctions',
        lignes: evals,
        taillePage: 15,
        triInitial: 'periode',
        sensInitial: 'desc',
        nomExport: 'sanctions',
        selectionnable: true,
        messageVide: 'Aucune sanction prononcée.',
        actionsLigne: (ctx, e) => [BoutonIcone(icone: LucideIcons.printer, libelle: 'Notification de sanction', onPressed: () => _notification(ctx, c, e))],
        colonnes: [
          ColonneTableau(cle: 'reference', libelle: 'N°', sansCoupure: true, rendu: (_, e) => Text('${e['reference']}', style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 12))),
          const ColonneTableau(cle: 'periode', libelle: 'Période'),
          const ColonneTableau(cle: 'employe', libelle: 'Agent'),
          const ColonneTableau(cle: 'service', libelle: 'Service'),
          ColonneTableau(
              cle: 'motifs',
              libelle: 'Critères sanctionnés',
              triable: false,
              texte: (e) => critSanctionnes(e, bareme, historiqueB).map((k) => k.label).join(', '),
              rendu: (_, e) {
                final l = critSanctionnes(e, bareme, historiqueB);
                if (l.isEmpty) return const Text('—');
                return Wrap(spacing: 4, runSpacing: 4, children: [for (final k in l) BadgeSigh(k.label, ton: TonSigh.danger)]);
              }),
          ColonneTableau(
              cle: 'prelevementPct',
              libelle: 'Retenue',
              droite: true,
              texte: (e) => '${e['prelevementPct']} %',
              rendu: (_, e) => Text('${e['prelevementPct']} %', style: const TextStyle(color: JetonsShell.danger600, fontSize: 14, fontWeight: FontWeight.w600))),
          ColonneTableau(cle: 'prelevementMontant', libelle: 'Montant', droite: true, texte: (e) => money(e['prelevementMontant'], avecDevise: false), rendu: (_, e) => Text(money(e['prelevementMontant'], avecDevise: false))),
        ],
      ),
      if (evals.isNotEmpty) ...[
        rhbTroisCartes([
          CarteSigh(
              titre: 'Sanctions par direction et service',
              child: GraphiqueBarres(
                  horizontal: true,
                  hauteur: 260,
                  etiquettes: parService.keys.toList(),
                  series: [SerieGraphique('Sanctions', [for (final l in parService.values) l.length], couleur: rhbTonRouge)])),
          CarteSigh(
              titre: 'Critères sanctionnés (NS 131)',
              child: GraphiqueBarres(
                  horizontal: true,
                  hauteur: 260,
                  etiquettes: [for (final x in parCritere) x.label],
                  series: [SerieGraphique('Agents concernés', [for (final x in parCritere) x.n], couleur: rhbTonOrange)])),
          CarteSigh(
              titre: 'Montant retenu par critère',
              child: GraphiqueAnneau(
                  trou: 0,
                  hauteur: 260,
                  etiquettes: [for (final x in parCritere) if (x.montant > 0) x.label],
                  valeurs: [for (final x in parCritere) if (x.montant > 0) x.montant])),
        ]),
        if (periodes.length > 1)
          CarteSigh(
              titre: 'Évolution des retenues',
              child: GraphiqueLigne(
                  hauteur: 240,
                  etiquettes: periodes,
                  series: [SerieGraphique('Sanctions', [for (final p in periodes) parPeriode[p]!.length], couleur: rhbTonRouge)])),
        const NoteSigh(
            'Les quatre axes du barème $rhbNs131Reference — ponctualité et assiduité, exécution des tâches, attitude envers les patients, respect de la hiérarchie — ne pèsent pas du même poids. Ce croisement montre lequel appelle une action de la Direction, plutôt que de traiter les sanctions une à une.'),
      ],
    ]);
  }

  void _notification(BuildContext ctx, ContexteEcran c, Fiche e) {
    final cr = (e['criteres'] as Map?) ?? const {};
    String lib(Object? n) => switch (n) { 'bonne' => 'Bonne', 'moyenne' => 'Moyenne', 'faible' => 'Faible à mauvaise', _ => '—' };
    afficherApercu(
        ctx,
        rhbPiece(c,
            titre: 'Notification de sanction',
            sousTitre: '${e['reference']} — ${e['periode']}',
            cartouche: [
              ('Agent', '${e['employe']}'),
              ('Matricule', '${e['matricule']}'),
              ('Service', '${e['service']}'),
              ('Période', '${e['periode']}'),
              ('Retenue', '${e['prelevementPct']} %'),
              ('Montant', money(e['prelevementMontant'])),
            ],
            blocs: [
              BlocTexte(
                  'À la suite de l’évaluation du rendement du mois de ${e['periode']}, et en application du barème $rhbNs131Reference, il est procédé à une retenue de ${e['prelevementPct']} % sur votre salaire brut, soit un montant de ${money(e['prelevementMontant'])}.'),
              BlocTableau(TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Élément d’évaluation', valeur: (r) => r['label']),
                ColonneEtat(libelle: 'Résultat', valeur: (r) => r['res']),
                ColonneEtat(libelle: 'Retenue', valeur: (r) => r['ret'], droite: true),
              ], lignes: [
                for (final k in rhbCriteresALaDate(rhbActives(c, 'baremeNS131'), rhbActives(c, 'historiqueBareme'), rhbDateBaremeDe(e)))
                  {'label': k.label, 'res': lib(cr[k.id]), 'ret': k.sanction(cr[k.id]) > 0 ? '${k.sanction(cr[k.id])} %' : '—'}
              ])),
              if ('${e['observations'] ?? ''}'.isNotEmpty) BlocTexte('Observations : ${e['observations']}', italique: true),
            ],
            signatures: [
              Signature('L’Agent', nom: '${e['employe']}', mention: 'Pris connaissance'),
              rhbSignDaf,
              rhbSignDm,
            ]));
  }
}
