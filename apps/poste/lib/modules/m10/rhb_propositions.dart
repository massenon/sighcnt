import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../donnees/planning_rh_poste.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'rhb_circuit.dart';
import 'rhb_commun.dart';

/// `m10-propositions-planning` — « Propositions de planning » (lot L6, Direction, 09/11/2026, Planning Q4) : l'agent PROPOSE une modification ou un échange de
/// son planning, le surveillant VALIDE. Une proposition ne change JAMAIS le planning validé tant qu'elle n'est pas validée ; le contrôle d'incompatibilité est
/// fait à la proposition (l'agent l'apprend tout de suite, rien n'est enregistré si refus) et refait à la validation. L'écran est celui de TOUT agent
/// (`universel` au manifeste) : chacun n'y voit que SES propositions (RG-13) ; le surveillant, la DAF et l'administrateur voient tout et tranchent.
class EcranPropositionsPlanning extends StatelessWidget with EcranMaquette {
  const EcranPropositionsPlanning({super.key});

  @override
  String get description => 'L’agent propose une modification ou un échange de son planning ; le surveillant valide.';

  @override
  String get regle =>
      'Une proposition ne change jamais le planning validé tant qu’elle n’est pas validée par le surveillant. Le contrôle d’incompatibilité (repos après une garde) est fait à la proposition puis refait à la validation. Chaque agent ne voit que ses propres propositions. Selon le réglage du poste, l’agent peut aussi modifier directement ses vacations ; un échange avec un collègue passe toujours par la validation.';

  @override
  Widget build(BuildContext context) =>
      RhbEcoute(collections: const ['propositionsPlanning', 'planning', 'personnel', 'regimesTravail', 'regimesIndividuels', 'parametres'], construire: _corps);

  static String _typeLabel(Object? id) => typesPropositionRh.where((t) => t.id == id).map((t) => t.libelle).firstOrNull ?? '$id';

  static String _dateFr(Object? d) => d == null || '$d'.isEmpty || DateTime.tryParse('$d') == null ? '—' : dateFR(DateTime.parse('$d'));

  Widget _etat(Fiche p) {
    final m = switch (p['etat']) {
      'proposee' => ('À valider', TonSigh.attention),
      'validee' => ('Validée', TonSigh.succes),
      'refusee' => ('Refusée', TonSigh.danger),
      'annulee' => ('Retirée', TonSigh.neutre),
      var x => ('$x', TonSigh.neutre),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      BadgeSigh(m.$1, ton: m.$2),
      if (p['motifRefus'] != null && p['motifRefus'] != '') Text('Motif du refus : ${p['motifRefus']}', style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12, height: 16 / 12)),
    ]);
  }

  Widget _corps(BuildContext context, ContexteEcran c) {
    final p = rhbPlanningPoste(c);
    final moi = p.moi();
    final valideur = const ['surveillant', 'da', 'admin'].contains(c.role);
    final rows = trierPar(p.propositionsVisibles(), (x) => '${x['proposeeLe'] ?? ''}', descendant: true);
    int n(String e) => rows.where((x) => x['etat'] == e).length;
    return rhbEspace([
      const RhbCarteReglages(),
      KpiGrilleSigh(kpis: [
        KpiSigh(libelle: 'À valider', valeur: nombre(n('proposee')), icone: LucideIcons.hourglass, ton: TonSigh.attention),
        KpiSigh(libelle: 'Validées', valeur: nombre(n('validee')), icone: LucideIcons.circleCheck, ton: TonSigh.succes),
        KpiSigh(libelle: 'Refusées', valeur: nombre(n('refusee')), icone: LucideIcons.circleX, ton: TonSigh.danger),
      ]),
      if (moi == null && !valideur)
        const NoteSigh('Votre compte ne correspond à aucun agent du personnel : aucune proposition ne peut être rattachée. Se connecter avec le compte nominatif de l’agent.',
            ton: TonSigh.attention),
      TableauSigh(
        titre: valideur ? 'Propositions des agents' : 'Mes propositions',
        lignes: rows,
        taillePage: 15,
        nomExport: 'propositions-planning',
        actions: [
          if (moi != null) BoutonSigh(libelle: 'Proposer une modification', icone: LucideIcons.calendarPlus, taille: TailleBouton.sm, onPressed: () => _proposer(context, c, p, moi)),
        ],
        colonnes: [
          ColonneTableau(cle: 'proposeeLe', libelle: 'Proposée le', sansCoupure: true, texte: (x) => _dateFr(x['proposeeLe'])),
          const ColonneTableau(cle: 'employe', libelle: 'Agent'),
          ColonneTableau(cle: 'type', libelle: 'Demande', texte: (x) => _typeLabel(x['type'])),
          ColonneTableau(
              cle: 'vacation',
              libelle: 'Vacation visée',
              valeur: (x) => x['vacationDate'] != null && x['vacationDate'] != '' ? '${_dateFr(x['vacationDate'])} · ${rhbTypePlanningLabel(x['vacationType'])}' : '',
              texte: (x) => x['vacationDate'] != null && x['vacationDate'] != '' ? '${_dateFr(x['vacationDate'])} · ${rhbTypePlanningLabel(x['vacationType'])}' : ''),
          ColonneTableau(
              cle: 'propose',
              libelle: 'Proposition',
              valeur: _propose,
              texte: _propose),
          const ColonneTableau(cle: 'motif', libelle: 'Motif'),
          ColonneTableau(cle: 'etat', libelle: 'État', texte: (x) => '${x['etat']}', rendu: (_, x) => _etat(x)),
        ],
        actionsLigne: (ctx, x) {
          if (x['etat'] != 'proposee') return const [];
          return [
            if (moi != null && x['employeId'] == moi['id'])
              BoutonIcone(
                  icone: LucideIcons.undo2,
                  libelle: 'Retirer ma proposition',
                  onPressed: () {
                    final r = p.annulerProposition(x['id']);
                    if (r['ok'] != true) {
                      rhbToastRefus(ctx, r);
                      return;
                    }
                    ToastsSigh.afficher(ctx, 'Proposition retirée.', type: TypeToast.succes, annuler: r['annuler'] as VoidCallback);
                  }),
            if (valideur) ...[
              BoutonIcone(icone: LucideIcons.check, libelle: 'Valider cette proposition', onPressed: () => _trancher(ctx, p, x, 'valider')),
              BoutonIcone(icone: LucideIcons.x, libelle: 'Refuser cette proposition', onPressed: () => _trancher(ctx, p, x, 'refuser')),
            ],
          ];
        },
      ),
    ]);
  }

  static String _propose(Fiche x) {
    if (x['type'] == 'retrait') return 'Retirer la vacation';
    if (x['type'] == 'echange') {
      return 'Avec ${x['contrepartie'] ?? '—'} (${_dateFr(x['contrepartieDate'])} · ${rhbTypePlanningLabel(x['contrepartieType'])})';
    }
    return '${_dateFr(x['date'])} · ${rhbTypePlanningLabel(x['typeVacation'])}';
  }

  Future<void> _trancher(BuildContext ctx, PlanningRhPoste p, Fiche x, String decision) async {
    final resume = '${_typeLabel(x['type'])} · ${x['employe']}';
    String? motif;
    if (decision == 'valider') {
      final ok = await confirmerSigh(ctx, titre: 'Valider cette proposition ?', message: '$resume. Le planning est modifié à la validation, le contrôle du repos étant refait.', libelleOk: 'Valider');
      if (!ok || !ctx.mounted) return;
    } else {
      motif = await confirmerAvecMotif(ctx, titre: 'Refuser cette proposition ?', message: '$resume. Le refus exige son motif : l’agent le lira.', libelleOk: 'Refuser', dangereux: true, motifObligatoire: false);
      if (motif == null || !ctx.mounted) return;
    }
    final r = p.trancherProposition(x['id'], decision, motif: motif);
    if (r['ok'] != true) {
      rhbToastRefus(ctx, r);
      return;
    }
    // Une validation a modifié le planning : elle ne s'annule pas d'un clic, une nouvelle proposition corrige.
    ToastsSigh.afficher(ctx, decision == 'valider' ? 'Proposition validée : planning modifié.' : 'Proposition refusée.', type: TypeToast.succes);
  }

  void _proposer(BuildContext ctx, ContexteEcran c, PlanningRhPoste p, Fiche moi) {
    final auj = iso(c.aujourdhui);
    final plan = c.magasin.collection('planning').actives;
    final miennes = trierPar([for (final v in plan) if (v['employeId'] == moi['id'] && '${v['date']}'.compareTo(auj) >= 0) v], (v) => v['date']);
    final autres = trierPar([
      for (final v in plan)
        if (v['employeId'] != moi['id'] && '${v['date']}'.compareTo(auj) >= 0 && (rhbTypePlanning(v['type'])?.duree ?? 0) > 0) v
    ], (v) => v['date']);
    final ctl = ControleurFormulaire([
      ChampDef(nom: 'type', libelle: 'Demande', type: TypeChamp.select, requis: true, col: ColChamp.plein, options: [for (final t in typesPropositionRh) OptionChamp(t.id, t.libelle)]),
      ChampDef(
          nom: 'vacationId',
          libelle: 'Ma vacation',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          condition: (controle: 'type', quand: const ['modification', 'retrait', 'echange']),
          options: [for (final v in miennes) OptionChamp('${v['id']}', '${_dateFr(v['date'])} · ${rhbTypePlanningLabel(v['type'])}')]),
      ChampDef(
          nom: 'contrepartieId',
          libelle: 'Vacation du collègue',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          condition: (controle: 'type', quand: const ['echange']),
          options: [for (final v in autres) OptionChamp('${v['id']}', '${v['employe']} · ${_dateFr(v['date'])} · ${rhbTypePlanningLabel(v['type'])}')]),
      const ChampDef(nom: 'date', libelle: 'Date', type: TypeChamp.date, requis: true, condition: (controle: 'type', quand: ['ajout', 'modification'])),
      ChampDef(
          nom: 'typeVacation',
          libelle: 'Vacation',
          type: TypeChamp.select,
          requis: true,
          condition: (controle: 'type', quand: const ['ajout', 'modification']),
          options: [for (final t in rhbTypesPlanning) OptionChamp(t.id, t.label)]),
      const ChampDef(nom: 'motif', libelle: 'Motif', type: TypeChamp.textarea, lignes: 2, requis: true, col: ColChamp.plein),
    ], {'type': 'ajout', 'date': iso(ajouterJours(c.aujourdhui, 1))});
    afficherModale<void>(ctx,
        titre: 'Proposer une modification de mon planning',
        sousTitre: '${moi['nomComplet']}',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          NoteSigh(p.agentModifieDirectement()
              ? 'Réglage du poste : vos modifications s’appliquent aussitôt (le contrôle du repos reste opposable). Un échange passe toujours par la validation du surveillant.'
              : 'Votre proposition ne change rien tant que le surveillant ne l’a pas validée.'),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Transmettre la proposition',
                  icone: LucideIcons.send,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    final r = p.proposer(
                        type: '${v['type']}',
                        date: v['date'] as String?,
                        typeVacation: v['typeVacation'] as String?,
                        vacationId: v['vacationId'] as String?,
                        contrepartieId: v['contrepartieId'] as String?,
                        motif: v['motif'] as String?);
                    if (r['ok'] != true) {
                      rhbToastRefus(ctx, r);
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, r['direct'] == true ? 'Planning modifié directement.' : 'Proposition transmise au surveillant.',
                        type: TypeToast.succes, annuler: r['annuler'] as VoidCallback?);
                  }),
            ]);
  }
}
