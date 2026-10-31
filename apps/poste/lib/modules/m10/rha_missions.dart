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

/// `m10-missions` — ordres de mission et de formation : affectation, prise en charge, validation et états signés. Un départ suppose un ORDRE ÉCRIT que la
/// Directrice Administrative valide ; valider, terminer et reporter ÉCRIVENT : ces commandes sont absentes sans le droit d'édition (E623).
class EcranMissions extends StatelessWidget with EcranMaquette {
  const EcranMissions({super.key});
  @override
  String get titre => 'Ordres de mission';
  @override
  String get description => 'Missions et formations du personnel : affectation, prise en charge, validation et états signés.';
  @override
  String? get regle =>
      'Un départ en mission ou en formation suppose un ordre écrit précisant l’agent, l’objet, la destination, les dates et la structure qui prend en charge. La Directrice Administrative valide avant le départ ; l’ordre imprimé porte les signatures de départ et de retour, et justifie l’absence au planning.';

  static const _col = 'missions';

  List<ChampDef> _champs(Magasin m) => [
        const ChampDef(nom: 'libelle', libelle: 'Libellé de la mission', requis: true, col: ColChamp.plein),
        ChampDef(nom: 'nature', libelle: 'Nature', type: TypeChamp.select, requis: true, options: rhaOptions(rhaNaturesMission)),
        const ChampDef(nom: 'objet', libelle: 'Objet détaillé', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein, requis: true),
        ChampDef(
            nom: 'agentId',
            libelle: 'Agent affecté',
            type: TypeChamp.select,
            requis: true,
            col: ColChamp.plein,
            options: [for (final e in rhaAgents(m)) OptionChamp('${e['id']}', '${e['nomComplet']}')]),
        const ChampDef(nom: 'structurePrise', libelle: 'Structure prenant en charge', requis: true, col: ColChamp.plein, aide: 'Qui supporte les frais : la clinique, l’organisme de formation ou un tiers.'),
        const ChampDef(nom: 'destination', libelle: 'Destination', requis: true),
        ChampDef(nom: 'moyen', libelle: 'Moyen de déplacement', type: TypeChamp.select, options: rhaOptions(rhaMoyensMission)),
        const ChampDef(nom: 'dateDepart', libelle: 'Date de départ', type: TypeChamp.date, requis: true),
        const ChampDef(nom: 'dateRetour', libelle: 'Date de retour', type: TypeChamp.date, requis: true),
        ChampDef(nom: 'statutMission', libelle: 'État', type: TypeChamp.select, requis: true, options: [for (final s in rhaStatutsMission) OptionChamp(s.$1, s.$2)]),
        const ChampDef(nom: 'observation', libelle: 'Observation', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
      ];

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection(_col);
    return ListenableBuilder(
        listenable: col,
        builder: (context, _) {
          final rows = col.actives;
          final aValider = rows.where((m) => m['statutMission'] == 'a_valider').length;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KpiGrilleSigh(kpis: rhaKpisW(rhaKpisMissions(rows), const [LucideIcons.briefcase, LucideIcons.stamp, LucideIcons.plane, LucideIcons.circleCheck])),
            if (aValider > 0) ...[
              const SizedBox(height: 16),
              NoteSigh('$aValider ordre(s) en attente de validation. Aucun départ ne devrait intervenir avant la signature de la Directrice Administrative.',
                  ton: TonSigh.attention, icone: LucideIcons.stamp),
            ],
            const SizedBox(height: 16),
            TableauSigh(
              titre: 'Registre des ordres de mission',
              colonnes: [
                ColonneTableau(cle: 'reference', libelle: 'N°', sansCoupure: true, rendu: (_, m) => matRef(m['reference'])),
                ColonneTableau(
                    cle: 'libelle',
                    libelle: 'Mission',
                    texte: (m) => '${m['libelle']} ${m['nature']} · ${m['destination']}',
                    rendu: (_, m) => matCelPatient('${m['libelle']}', '${m['nature']} · ${m['destination']}', mono: false)),
                ColonneTableau(cle: 'agent', libelle: 'Agent affecté', texte: (m) => '${m['agent']} ${m['fonction'] ?? ''}', rendu: (_, m) => matCelPatient('${m['agent']}', '${m['fonction'] ?? ''}', mono: false)),
                const ColonneTableau(cle: 'structurePrise', libelle: 'Prise en charge'),
                ColonneTableau(
                    cle: 'dateDepart',
                    libelle: 'Période',
                    sansCoupure: true,
                    valeur: (m) => rhaDate(m['dateDepart'])?.millisecondsSinceEpoch ?? 0,
                    texte: (m) => '${rhaDateFR(m['dateDepart'])} → ${rhaDateFR(m['dateRetour'])}',
                    rendu: (_, m) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(rhaDateFR(m['dateDepart']), style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14)),
                          Text('au ${rhaDateFR(m['dateRetour'])}', style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
                        ])),
                ColonneTableau(
                    cle: 'statutMission',
                    libelle: 'État',
                    texte: (m) => rhaStatutMission(m['statutMission']).$2,
                    rendu: (_, m) {
                      final s = rhaStatutMission(m['statutMission']);
                      return BadgeSigh(s.$2, ton: matTon(s.$3));
                    }),
                ColonneTableau(
                    cle: 'valideePar',
                    libelle: 'Validation',
                    texte: (m) => rhaVrai(m['valideePar']) ? '${m['valideePar']} ${rhaDateFR(m['valideeLe'])}' : 'non validé',
                    rendu: (_, m) => rhaVrai(m['valideePar'])
                        ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            Text('${m['valideePar']}', style: const TextStyle(color: JetonsShell.success700, fontSize: 12, height: 16 / 12)),
                            Text(rhaVrai(m['valideeLe']) ? rhaDateFR(m['valideeLe']) : '', style: const TextStyle(color: JetonsShell.slate400, fontSize: 10)),
                          ])
                        : const Text('non validé', style: TextStyle(color: JetonsShell.warning600, fontSize: 12, height: 16 / 12))),
              ],
              lignes: rows,
              taillePage: 15,
              nomExport: 'ordres-mission',
              triInitial: 'dateDepart',
              sensInitial: 'desc',
              filtres: [
                FiltreTableau(nom: 'nature', libelle: 'Nature', options: rhaOptions(rhaNaturesMission)),
                FiltreTableau(nom: 'statutMission', libelle: 'État', options: [for (final s in rhaStatutsMission) OptionChamp(s.$1, s.$2)]),
              ],
              alClicLigne: (m) => _fiche(context, c, m),
              actions: [
                if (c.droit.editer)
                  BoutonSigh(
                      libelle: 'Nouveau',
                      icone: LucideIcons.plus,
                      taille: TailleBouton.sm,
                      onPressed: () => admSaisir(context,
                          col: col,
                          champs: _champs(c.magasin),
                          titreCreation: 'Nouvel ordre de mission',
                          entite: 'Ordre de mission',
                          prefixeId: 'OM',
                          initiales: {
                            'nature': 'Mission',
                            'statutMission': 'a_valider',
                            'dateDepart': iso(c.aujourdhui),
                            'dateRetour': iso(c.aujourdhui.add(const Duration(days: 2))),
                            'structurePrise': 'CLINIQUE NASSIERA TOO SARL',
                          },
                          fiche: (v, ex) => matSansNuls(ex == null ? rhaMissionEnregistrable({...v}, rhaAgentPar(c.magasin, v['agentId']), effectifTotal: col.toutes.length) : {...v}),
                          detailToast: (f) => '${f['libelle'] ?? ''}')),
              ],
              actionsLigne: (ctx, m) => [
                if (c.droit.editer && rhaGestesMission(m['statutMission']).valider)
                  BoutonIcone(icone: LucideIcons.stamp, libelle: 'Valider (Directrice Administrative)', onPressed: () => _valider(context, c, col, m)),
                if (c.droit.editer && rhaGestesMission(m['statutMission']).terminerReporter) ...[
                  BoutonIcone(icone: LucideIcons.check, libelle: 'Marquer terminée', onPressed: () => _changerEtat(context, col, m, 'terminee', 'Mission terminée.')),
                  BoutonIcone(icone: LucideIcons.calendarClock, libelle: 'Reporter', onPressed: () => _changerEtat(context, col, m, 'reportee', 'Mission reportée.')),
                ],
                BoutonIcone(icone: LucideIcons.printer, libelle: 'Imprimer l’ordre', onPressed: () => _imprimer(context, c, m)),
                ...admActionsLigne(context, c, col, m,
                    modifier: (f) => admSaisir(context,
                        col: col, champs: _champs(c.magasin), titreCreation: '', entite: 'Ordre de mission', existante: f, fiche: (v, ex) => matSansNuls({...v}))),
              ],
            ),
          ]);
        });
  }

  Future<void> _valider(BuildContext ctx, ContexteEcran c, CollectionMagasin col, Fiche m) async {
    final ok = await confirmerSigh(ctx,
        titre: 'Valider l’ordre de mission ${m['reference']} ?',
        message:
            'La validation autorise le départ de ${m['agent']} du ${rhaDateFR(m['dateDepart'])} au ${rhaDateFR(m['dateRetour'])}, aux frais de ${m['structurePrise']}. Elle est journalisée au nom de la Directrice Administrative (RG-12).',
        libelleOk: 'Valider l’ordre');
    if (!ok || !ctx.mounted) return;
    final annuler = col.mettreAJour(m['id'], rhaCorrectifValidationMission(c.aujourdhui));
    ToastsSigh.afficher(ctx, 'Ordre de mission validé.', type: TypeToast.succes, detail: '${m['agent']} — départ le ${rhaDateFR(m['dateDepart'])}', annuler: annuler);
  }

  void _changerEtat(BuildContext ctx, CollectionMagasin col, Fiche m, String etat, String message) {
    final annuler = col.mettreAJour(m['id'], {'statutMission': etat});
    ToastsSigh.afficher(ctx, message, type: TypeToast.succes, annuler: annuler);
  }

  void _fiche(BuildContext ctx, ContexteEcran c, Fiche m) {
    afficherTiroir<void>(ctx,
        titre: '${m['reference']}',
        sousTitre: '${m['libelle']}',
        largeurMax: 672,
        corps: DescListeSigh([
          ('Agent affecté', m['agent'] as String?),
          ('Fonction', rhaVrai(m['fonction']) ? '${m['fonction']}' : '—'),
          ('Nature', m['nature'] as String?),
          ('Objet', m['objet'] as String?),
          ('Destination', m['destination'] as String?),
          ('Moyen', rhaVrai(m['moyen']) ? '${m['moyen']}' : '—'),
          ('Départ', rhaDateFR(m['dateDepart'])),
          ('Retour', rhaDateFR(m['dateRetour'])),
          ('Prise en charge', m['structurePrise'] as String?),
          ('État', rhaStatutMission(m['statutMission']).$2),
          ('Validée par', rhaVrai(m['valideePar']) ? '${m['valideePar']}' : 'non validée'),
          ('Observation', rhaVrai(m['observation']) ? '${m['observation']}' : '—'),
        ]),
        pied: (fermer) => [BoutonSigh(libelle: 'Imprimer l’ordre', icone: LucideIcons.printer, onPressed: () => _imprimer(ctx, c, m))]);
  }

  void _imprimer(BuildContext ctx, ContexteEcran c, Fiche m) {
    final fonction = rhaVrai(m['fonction']) ? '${m['fonction']}' : 'agent de la clinique';
    matImprimer(ctx,
        titre: 'Ordre de mission',
        sousTitre: '${m['reference']} — ${m['agent']}',
        cartouche: [
          ('Agent', '${m['agent']}'),
          ('Fonction', rhaVrai(m['fonction']) ? '${m['fonction']}' : '—'),
          ('Nature', '${m['nature']}'),
          ('Destination', '${m['destination']}'),
          ('Départ', rhaDateFR(m['dateDepart'])),
          ('Retour', rhaDateFR(m['dateRetour'])),
          ('Moyen de déplacement', rhaVrai(m['moyen']) ? '${m['moyen']}' : '—'),
          ('Prise en charge des frais', '${m['structurePrise']}'),
        ],
        blocs: [
          BlocTexte(
              'La Directrice Administrative de la Clinique NASSIERA TOO donne ordre à ${m['agent']}, $fonction, de se rendre à ${m['destination']} du ${rhaDateFR(m['dateDepart'])} au ${rhaDateFR(m['dateRetour'])}, à l’effet de : ${m['objet']}.'),
          BlocTexte('Les frais afférents à cette mission sont pris en charge par ${m['structurePrise']}.'),
          if (rhaVrai(m['observation'])) BlocTexte('Observation : ${m['observation']}'),
          BlocTableau(TableauEtat(colonnes: [
            ColonneEtat(libelle: 'Visa de départ', valeur: (l) => l['a']),
            ColonneEtat(libelle: 'Visa de retour', valeur: (l) => l['b']),
          ], lignes: const [
            {'a': 'Date, cachet et signature', 'b': 'Date, cachet et signature'}
          ])),
        ],
        signatures: [Signature('L’agent', nom: '${m['agent']}'), Signature('La Directrice Administrative', nom: rhaVrai(m['valideePar']) ? '${m['valideePar']}' : 'TAKI Alimatou')]);
  }
}
