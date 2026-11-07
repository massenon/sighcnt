import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'img_commun.dart';
import 'img_demandes.dart';

/// `m2-dashboard-imagerie` — « Poste d’imagerie médicale » : le premier regard du poste. Il LIT les registres (demandes, comptes rendus, tâches), il
/// n'ouvre aucune saisie propre : la donnée n'existe qu'une fois.
class EcranPosteImagerie extends StatelessWidget with EcranMaquette {
  const EcranPosteImagerie({super.key});

  @override
  String get titre => 'Poste d’imagerie médicale';

  @override
  String get description =>
      'Le premier regard du poste : les examens payés à exécuter, les comptes rendus en rédaction, la file d’attente.';

  @override
  String get regle =>
      'Un examen ne s’exécute qu’une fois réglé — la file du poste ne porte que les demandes payées. Ce tableau LIT les registres, il n’ouvre aucune saisie propre : la donnée n’existe qu’une fois.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    final dems = m.collection('demandesImagerie');
    final crs = m.collection('resultatsImagerie');
    return ListenableBuilder(
      listenable: Listenable.merge([dems, crs, m.collection('examensImagerie')]),
      builder: (context, _) {
        final p = posteImagerie(
            demandes: dems.actives,
            comptesRendus: crs.actives,
            catalogue: catalogueExamens(m),
            moisCourant: iso(c.aujourdhui).substring(0, 7));
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Payés — à exécuter',
                    valeur: nombre(p.payees.length),
                    icone: LucideIcons.scanLine,
                    ton: p.payees.isNotEmpty ? TonSigh.attention : TonSigh.succes,
                    indice: p.payees.isNotEmpty
                        ? 'Le premier regard du poste'
                        : 'Rien n’attend'),
                KpiSigh(
                    libelle: 'En attente de caisse',
                    valeur: nombre(p.attente.length),
                    icone: LucideIcons.wallet,
                    ton: TonSigh.neutre,
                    indice: 'Visibles, non exécutables'),
                KpiSigh(
                    libelle: 'CR en rédaction',
                    valeur: nombre(p.redaction.length),
                    icone: LucideIcons.pencil,
                    ton: p.redaction.isNotEmpty ? TonSigh.info : TonSigh.neutre),
                KpiSigh(
                    libelle: 'Rendus ce mois-ci',
                    valeur: nombre(p.rendusMois.length),
                    icone: LucideIcons.fileCheck2,
                    ton: TonSigh.succes),
              ]),
              const SizedBox(height: 16),
              if (p.payees.isNotEmpty)
                TableauSigh(
                  titre: 'À exécuter — examens réglés',
                  lignes: p.payees,
                  taillePage: 8,
                  nomExport: 'imagerie-a-executer',
                  triInitial: 'dateHeure',
                  sensInitial: 'asc',
                  colonnes: [
                    ColonneTableau(
                        cle: 'reference',
                        libelle: 'N°',
                        rendu: (_, r) =>
                            Text('${r['reference']}', style: styleMono)),
                    const ColonneTableau(cle: 'patient', libelle: 'Patient'),
                    const ColonneTableau(cle: 'examen', libelle: 'Examen'),
                    ColonneTableau(
                        cle: 'urgent',
                        libelle: 'Priorité',
                        texte: (r) => r['urgent'] == true ? 'Urgent' : 'Courante',
                        rendu: (_, r) => r['urgent'] == true
                            ? const BadgeSigh('Urgent', ton: TonSigh.danger)
                            : const Text('Courante',
                                style: TextStyle(
                                    color: JetonsShell.slate400,
                                    fontSize: 12,
                                    height: 16 / 12))),
                  ],
                  actionsLigne: (ctx, r) => [
                    if (c.droit.editer)
                      BoutonSigh(
                          libelle: 'Saisir le CR',
                          icone: LucideIcons.filePenLine,
                          taille: TailleBouton.sm,
                          onPressed: () => saisirCompteRendu(ctx, r)),
                  ],
                )
              else
                const CarteSigh(
                    titre: 'À exécuter',
                    child: VideSigh(
                        'Aucun examen réglé en attente : rien ne vous attend.',
                        icone: LucideIcons.circleCheck)),
              const SizedBox(height: 16),
              // Les cinq modalités d'un coup d'œil : où la charge se trouve, et le tableau où la traiter.
              TableauSigh(
                titre: 'Activité par modalité',
                lignes: [
                  for (final l in p.parModalite)
                    {
                      'label': l.modalite.libelle,
                      'ecran': l.modalite.ecran,
                      'icone': l.modalite.icone,
                      'attente': l.attente,
                      'payees': l.payees,
                      'redaction': l.redaction,
                      'rendus': l.rendus,
                    }
                ],
                taillePage: 5,
                recherche: false,
                nomExport: 'imagerie-par-modalite',
                colonnes: [
                  ColonneTableau(
                      cle: 'label',
                      libelle: 'Modalité',
                      rendu: (_, r) => Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(iconeModalite('${r['icone']}'),
                                size: 16, color: JetonsShell.navy600),
                            const SizedBox(width: 8),
                            Flexible(
                                child: Text('${r['label']}',
                                    style: const TextStyle(
                                        color: JetonsShell.slate800,
                                        fontSize: 14,
                                        height: 20 / 14,
                                        fontWeight: FontWeight.w500))),
                          ])),
                  const ColonneTableau(
                      cle: 'attente', libelle: 'Attente caisse', droite: true),
                  ColonneTableau(
                      cle: 'payees',
                      libelle: 'À exécuter',
                      droite: true,
                      texte: (r) => '${r['payees']}',
                      rendu: (_, r) => (r['payees'] as int) > 0
                          ? Text('${r['payees']}',
                              style: const TextStyle(
                                  color: JetonsShell.warning700,
                                  fontSize: 14,
                                  height: 20 / 14,
                                  fontWeight: FontWeight.w600))
                          : const Text('0',
                              style: TextStyle(
                                  color: JetonsShell.slate700,
                                  fontSize: 14,
                                  height: 20 / 14))),
                  const ColonneTableau(
                      cle: 'redaction',
                      libelle: 'CR en rédaction',
                      droite: true),
                  const ColonneTableau(
                      cle: 'rendus', libelle: 'Rendus ce mois', droite: true),
                ],
                // Jamais de porte vers un tableau fermé au profil (RG-13) : la coque refuse l'ouverture d'un écran fermé (écart E104).
                alClicLigne: (r) => c.aller('${r['ecran']}'),
              ),
              const SizedBox(height: 16),
              FileAttenteSigh(
                type: 'imagerie',
                titre: 'File d’attente du poste',
                vide: 'Aucune tâche d’imagerie en file.',
                icone: LucideIcons.scanLine,
                // Dans la maquette, `K.fileAttente('imagerie', …)` ne reçoit pas d'`onAction` : le bouton ne fait rien (écart E105).
                surAction: (_, __) {},
              ),
            ]);
      },
    );
  }
}
