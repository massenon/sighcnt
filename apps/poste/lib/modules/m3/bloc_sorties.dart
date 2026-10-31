import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m1/commun_m1.dart' show bandeauLectureSeule;
import 'bloc_commun.dart';

/// `m3-sorties` — « Sorties d'hospitalisation » : la préparation et la finalisation des sorties (vérification financière, signatures, bon de sortie).
///
/// RG-06 — la sortie n'est finalisable que si le solde du patient est apuré, sauf DÉROGATION motivée et tracée. RG-07 — elle requiert la signature du
/// patient, celle de l'infirmier traitant et le constat du gardien (les trois, vérifiées d'abord). Le solde est la somme des restes dus de TOUTES les
/// factures du patient. Finaliser fait sortir l'admission : le lit est libéré, le geste s'annule.
///
/// Écart E428 : « Finaliser la sortie » est une écriture — ABSENTE sans le droit (la maquette l'offrait à tout profil ; l'aperçu et le bon restent ouverts).
/// Écart E415 (corrigé dans la maquette, porté tel quel) : les indicateurs se recalculent à chaque sortie finalisée ou annulée. Écart E416 : l'état
/// « Sortie contre avis médical » du choix ne déclenche pas la procédure de RG-08 (`m3-sortie-avis-medical`) — porté fidèlement.
class EcranSorties extends StatelessWidget with EcranMaquette {
  const EcranSorties({super.key});

  @override
  String get titre => 'Sorties d’hospitalisation';

  @override
  String get description =>
      'Préparation et finalisation des sorties : vérification financière, signatures et édition du bon de sortie.';

  @override
  String get regle =>
      'RG-06 — la sortie n’est finalisable que si le solde du patient est apuré, sauf dérogation motivée et tracée. RG-07 — elle requiert la signature du patient, celle de l’infirmier traitant et le constat du gardien.';

  static List<ChampDef> champs() => [
        const ChampDef(
            nom: 'dateSortie',
            libelle: 'Date de sortie',
            type: TypeChamp.date,
            requis: true),
        ChampDef(
            nom: 'etatSortie',
            libelle: 'État à la sortie',
            type: TypeChamp.select,
            requis: true,
            options: [for (final x in blocEtatsSortie) OptionChamp(x)]),
        const ChampDef(
            nom: 'consignes',
            libelle: 'Consignes de sortie et suivi',
            type: TypeChamp.textarea,
            lignes: 2,
            col: ColChamp.plein),
        const ChampDef.section('Signatures et constat (RG-07)'),
        const ChampDef(
            nom: 'sigPatient',
            libelle: 'Signature du patient recueillie',
            type: TypeChamp.case_),
        const ChampDef(
            nom: 'sigInfirmier',
            libelle: 'Signature de l’infirmier traitant',
            type: TypeChamp.case_),
        const ChampDef(
            nom: 'constatGardien',
            libelle: 'Constat du gardien effectué',
            type: TypeChamp.case_),
        const ChampDef(
            nom: 'derogation',
            libelle: 'Dérogation de la Direction (si solde non apuré)',
            type: TypeChamp.textarea,
            lignes: 2,
            col: ColChamp.plein),
      ];

  static num solde(Magasin m, Fiche a) =>
      blocSoldePatient(m.collection('factures').actives, a['patientId']);

  /// Le bon de sortie, avec la saisie courante (même incomplète).
  static void bonSortie(BuildContext ctx, Fiche a, Map<String, Object?> v) {
    final c = ContexteEcran.of(ctx);
    final s = solde(c.magasin, a);
    final sortie = '${v['dateSortie'] ?? ''}'.isNotEmpty
        ? dateBloc(v['dateSortie'])
        : dateFR(c.aujourdhui);
    String ou(Object? x, String defaut) => '${x ?? ''}'.isEmpty ? defaut : '$x';
    final duree = hosDureeSejour(a, c.aujourdhui);
    afficherApercu(
        ctx,
        PieceA4(
          titre: 'Bon de sortie d’hospitalisation',
          sousTitre: 'Référence ${a['reference'] ?? a['id']}',
          cartouche: [
            ('Patient', '${a['patient']}'),
            ('Dossier', '${a['patientCode']}'),
            ('Date d’entrée', dateBloc(a['dateEntree'])),
            ('Date de sortie', sortie),
            ('Lit', '${a['lit']}'),
            ('Durée du séjour', '$duree jour(s)'),
          ],
          blocs: [
            BlocTableau(TableauEtat(colonnes: [
              ColonneEtat(libelle: 'Rubrique', valeur: (r) => r['k']),
              ColonneEtat(libelle: 'Information', valeur: (r) => r['v']),
            ], lignes: [
              {'k': 'Diagnostic d’entrée', 'v': a['diagnosticEntree']},
              {'k': 'État à la sortie', 'v': ou(v['etatSortie'], '—')},
              {'k': 'Consignes de sortie', 'v': ou(v['consignes'], '—')},
              {
                'k': 'Vérification financière (RG-06)',
                'v': s > 0 ? 'Solde restant dû : ${money(s)}' : 'Solde apuré'
              },
              {
                'k': 'Dérogation Direction',
                'v': ou(v['derogation'], 'Sans objet')
              },
            ])),
            const BlocTexte(
                'Conformément à la règle RG-07, la présente sortie requiert la signature du patient, celle de l’infirmier traitant et le constat du gardien.',
                italique: true),
          ],
          signatures: [
            const Signature('Le Patient', mention: 'Signature'),
            Signature('L’Infirmier traitant',
                nom: '${a['infirmier'] ?? ''}', mention: 'Signature'),
            const Signature('Le Gardien', mention: 'Constat de sortie'),
          ],
          reference: PieceA4.reference_(
              c.aujourdhui, ImpressionPoste.prochainNumero()),
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
        ));
  }

  /// `ouvrirSortie(a)` : le tiroir de la préparation. Le solde est lu à l'ouverture (RG-06), comme la maquette.
  static void ouvrirSortie(BuildContext ctx, Fiche a) {
    final c = ContexteEcran.of(ctx);
    final m = c.magasin;
    final s = solde(m, a);
    final defs = champs();
    final ctl = ControleurFormulaire(defs, {'dateSortie': iso(c.aujourdhui)});
    afficherTiroir<void>(ctx,
        titre: 'Sortie d’hospitalisation',
        sousTitre: '${a['patient']} — lit ${a['lit']}',
        largeurMax: 672,
        corps:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Patient', a['patient']),
            (
              'Dossier',
              Text('${a['patientCode']}',
                  style: const TextStyle(
                      fontFamily: 'LiberationMono',
                      fontSize: 14,
                      height: 20 / 14,
                      color: JetonsShell.slate800,
                      fontWeight: FontWeight.w500))
            ),
            ('Lit', a['lit']),
            ('Entrée', dateBloc(a['dateEntree'])),
            ('Durée du séjour', '${hosDureeSejour(a, c.aujourdhui)} jour(s)'),
            ('Diagnostic', a['diagnosticEntree']),
          ]),
          const SizedBox(height: 16),
          s > 0
              ? NoteSigh(
                  'RG-06 — vérification financière non satisfaite. Solde restant dû : ${money(s)}. La sortie exige soit l’encaissement du solde à la caisse, soit une dérogation motivée de la Direction, qui sera tracée dans le journal d’audit.',
                  ton: TonSigh.danger,
                  icone: LucideIcons.wallet)
              : const NoteSigh(
                  'RG-06 — Vérification financière satisfaite : le solde du patient est apuré.',
                  ton: TonSigh.succes,
                  icone: LucideIcons.circleCheck),
          const SizedBox(height: 16),
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Éditer le bon de sortie',
                  icone: LucideIcons.printer,
                  variante: VarianteBouton.secondaire,
                  onPressed: () =>
                      bonSortie(ctx, a, ctl.valider() ?? const {})),
              if (c.droit.editer)
                BoutonSigh(
                    libelle: 'Finaliser la sortie',
                    icone: LucideIcons.check,
                    onPressed: () {
                      final v = ctl.valider();
                      if (v == null) {
                        ToastsSigh.afficher(
                            ctx, 'Le formulaire comporte des erreurs.',
                            type: TypeToast.erreur);
                        return;
                      }
                      final refus = blocRefusSortie(v, s);
                      if (refus != null) {
                        toastRefus(ctx, refus);
                        return;
                      }
                      final annuler = m
                          .collection('admissions')
                          .mettreAJour(a['id'], blocPatchSortie(v));
                      fermer();
                      ToastsSigh.afficher(ctx,
                          'Sortie finalisée — le lit ${a['lit']} est libéré.',
                          type: TypeToast.succes, annuler: annuler);
                    }),
            ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final adm = c.magasin.collection('admissions');
    final fac = c.magasin.collection('factures');
    return ListenableBuilder(
      listenable: Listenable.merge([adm, fac]),
      builder: (context, _) {
        final k = blocKpisSorties(adm.actives, fac.actives);
        final ec = hosEnCours(adm.actives);
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              bandeauLectureSeule(c),
              kpisBloc([
                KpiSigh(
                    libelle: 'Patients hospitalisés',
                    valeur: nombre(k.hospitalises),
                    icone: LucideIcons.bedDouble),
                KpiSigh(
                    libelle: 'Sorties finalisables',
                    valeur: nombre(k.finalisables),
                    icone: LucideIcons.circleCheck,
                    ton: TonSigh.succes),
                KpiSigh(
                    libelle: 'Bloquées par le solde',
                    valeur: nombre(k.bloquees),
                    icone: LucideIcons.wallet,
                    ton: TonSigh.danger,
                    indice: 'RG-06'),
                KpiSigh(
                    libelle: 'Sorties réalisées',
                    valeur: nombre(k.realisees),
                    icone: LucideIcons.doorOpen,
                    ton: TonSigh.info),
              ]),
              TableauSigh(
                titre: 'Patients en cours d’hospitalisation',
                lignes: ec,
                nomExport: 'sorties-a-preparer',
                messageVide: 'Aucun patient hospitalisé.',
                alClicLigne: (a) => ouvrirSortie(context, a),
                actionsLigne: (ctx, a) => [
                  BoutonSigh(
                      libelle: 'Préparer la sortie',
                      icone: LucideIcons.doorOpen,
                      taille: TailleBouton.sm,
                      variante: VarianteBouton.secondaire,
                      onPressed: () => ouvrirSortie(ctx, a)),
                ],
                colonnes: [
                  ColonneTableau(
                      cle: 'lit',
                      libelle: 'Lit',
                      sansCoupure: true,
                      rendu: (_, a) => Text('${a['lit']}',
                          style: const TextStyle(
                              fontFamily: 'LiberationMono',
                              fontSize: 12,
                              height: 16 / 12,
                              fontWeight: FontWeight.w600,
                              color: JetonsShell.slate700))),
                  ColonneTableau(
                      cle: 'patient',
                      libelle: 'Patient',
                      texte: (a) => '${a['patient']} ${a['patientCode']}',
                      rendu: (_, a) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${a['patient']}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: JetonsShell.slate800,
                                        fontSize: 14,
                                        height: 20 / 14,
                                        fontWeight: FontWeight.w500)),
                                Text('${a['patientCode']}',
                                    style: const TextStyle(
                                        fontFamily: 'LiberationMono',
                                        color: JetonsShell.slate400,
                                        fontSize: 12,
                                        height: 16 / 12)),
                              ])),
                  ColonneTableau(
                      cle: 'dateEntree',
                      libelle: 'Entrée',
                      sansCoupure: true,
                      valeur: (a) => '${a['dateEntree'] ?? ''}',
                      texte: (a) => dateBloc(a['dateEntree'])),
                  ColonneTableau(
                      cle: 'duree',
                      libelle: 'Séjour',
                      droite: true,
                      valeur: (a) => hosDureeSejour(a, c.aujourdhui),
                      texte: (a) => '${hosDureeSejour(a, c.aujourdhui)} j'),
                  const ColonneTableau(
                      cle: 'diagnosticEntree', libelle: 'Diagnostic'),
                  ColonneTableau(
                      cle: 'solde',
                      libelle: 'Solde (RG-06)',
                      droite: true,
                      valeur: (a) => solde(c.magasin, a),
                      texte: (a) => solde(c.magasin, a) > 0
                          ? money(solde(c.magasin, a), avecDevise: false)
                          : 'Apuré',
                      rendu: (_, a) {
                        final s = solde(c.magasin, a);
                        return s > 0
                            ? Text(money(s, avecDevise: false),
                                style: const TextStyle(
                                    color: JetonsShell.danger600,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    height: 20 / 14))
                            : const BadgeSigh('Apuré', ton: TonSigh.succes);
                      }),
                ],
              ),
            ]);
      },
    );
  }
}
