import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m2/img_commun.dart' show nouvelIdImagerie;
import '../m5/cat_commun.dart' show collectionAnalyses;
import '../m1/commun_m1.dart' show bandeauLectureSeule;
import 'bloc_commun.dart';

/// `m3-demande-examen` — « Demande d'examen » : la fiche de demande d'examen du service (identité complète, indication, urgence par examen ou bilan
/// entier).
///
/// La fiche papier exige TOUS ses champs : un bulletin d'examen anonyme ne se rattache plus à personne. L'urgence se dit PAR EXAMEN ou pour le bilan
/// entier, et le service demandeur est nommé — c'est lui qui reverra le résultat, sous le RBAC métier. La demande suit la chaîne existante, par la
/// fabrique UNIQUE `PR.ouvrirDemandeExterne` (la même que l'accueil du patient externe) : facture à lignes payables, caisse saisie, prélèvement bloqué
/// jusqu'au règlement.
///
/// Écarts : le prescripteur extérieur est enregistré sous son NOM (E412 — la maquette enregistrait la valeur « EXTERNE ») ; la liste des examens n'affiche
/// pas le tarif par ligne (le kit du poste n'a pas de détail par entrée — E424).
class EcranDemandeExamen extends StatelessWidget with EcranMaquette {
  const EcranDemandeExamen({super.key});

  @override
  String get titre => 'Demande d’examen';

  @override
  String get description =>
      'La fiche de demande d’examen du service : identité complète, indication, urgence par examen ou bilan entier.';

  @override
  String get regle =>
      'La fiche papier exige tous ses champs — nom, prénoms, âge, sexe, indication, résidence : un bulletin d’examen anonyme ne se rattache plus à personne. L’urgence se dit par examen ou pour le bilan entier, et le service demandeur est nommé — c’est lui qui reverra le résultat, sous le RBAC métier. La demande suit la chaîne existante : caisse, prélèvement, laboratoire.';

  static String libelleService(Object? id) {
    for (final s in blocServicesDemandeurs) {
      if (s.id == id) return s.label;
    }
    return '${id ?? ''}'.isEmpty ? '—' : '$id';
  }

  static List<ChampDef> champs(Magasin m) {
    final analyses = collectionAnalyses(m).actives;
    return [
      ChampDef(
          nom: 'patientCode',
          libelle: 'Patient',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          options: optionsPatientsBloc(m)),
      const ChampDef(
          nom: 'residence',
          libelle: 'Résidence',
          requis: true,
          aide: 'Reprise du dossier au choix du patient — la fiche papier l’exige.'),
      ChampDef(
          nom: 'serviceDemandeur',
          libelle: 'Service demandeur',
          type: TypeChamp.select,
          requis: true,
          options: [for (final s in blocServicesDemandeurs) OptionChamp(s.id, s.label)]),
      ChampDef(nom: 'prescripteur', libelle: 'Prescripteur', type: TypeChamp.select, requis: true, options: [
        for (final x in m.collection('soignants').actives)
          if (x['prescrit'] == true) OptionChamp('${x['nomComplet']}', '${x['nomComplet']} — ${x['poste']}'),
        const OptionChamp(blocPrescripteurExterne, '— Prescripteur extérieur à la clinique —'),
      ]),
      const ChampDef(
          nom: 'prescripteurExterne',
          libelle: 'Prescripteur extérieur — nom, qualification et structure',
          col: ColChamp.plein,
          condition: (controle: 'prescripteur', quand: [blocPrescripteurExterne]),
          aide:
              'Ex. : Dr SALIFOU Aminou, médecin généraliste, Centre de santé de Perma. C’est ce qui permet de lui renvoyer le compte rendu.'),
      const ChampDef(
          nom: 'indication',
          libelle: 'Indication clinique',
          type: TypeChamp.textarea,
          lignes: 2,
          requis: true,
          col: ColChamp.plein),
      ChampDef(
          nom: 'analyses',
          libelle: 'Examens demandés',
          type: TypeChamp.multiselect,
          requis: true,
          col: ColChamp.plein,
          options: [for (final a in analyses) OptionChamp('${a['code']}', '${a['code']} — ${a['designation']}')]),
      ChampDef(
          nom: 'urgence',
          libelle: 'Urgence',
          type: TypeChamp.select,
          requis: true,
          options: [for (final u in blocNiveauxUrgence) OptionChamp(u.id, u.label)]),
      ChampDef(nom: 'examenUrgent', libelle: 'Examen urgent (si « un examen urgent »)', type: TypeChamp.select, options: [
        const OptionChamp('', '—'),
        for (final a in analyses) OptionChamp('${a['code']}', '${a['designation']}'),
      ]),
      const ChampDef(nom: 'hospitalise', libelle: 'Patient hospitalisé', type: TypeChamp.case_),
    ];
  }

  /// L'émission : la fabrique UNIQUE du parcours, puis la fiche imprimée. Rend le récapitulatif, ou lève [PatRefus].
  static PatDemandeExterne emettre(ContexteEcran c, Fiche pt, Map<String, Object?> v) {
    final m = c.magasin;
    final r = patOuvrirDemandeExterne(
        saisie: {
          'urgence': v['urgence'],
          'examenUrgent': '${v['examenUrgent'] ?? ''}'.isEmpty ? null : v['examenUrgent'],
          'prescripteur': blocNomPrescripteur(v['prescripteur'], v['prescripteurExterne']),
          'serviceDemandeur': v['serviceDemandeur'],
          'indication': v['indication'],
          'hospitalise': v['hospitalise'] == true,
          'residence': v['residence'],
          // La fiche du SERVICE : le résultat revient au prescripteur, sous le RBAC métier du secteur.
          'origineFiche': 'service',
          'origineDemande': 'service',
          'secteurDemandeur': blocSecteurDemandeur(v['serviceDemandeur']),
        },
        codesAnalyses: [for (final x in (v['analyses'] as List)) '$x'],
        catalogue: collectionAnalyses(m).actives,
        patients: m.collection('patients').toutes,
        demandesExistantes: m.collection('demandesAnalyses').toutes,
        nbFactures: m.collection('factures').toutes.length,
        nouvelId: nouvelIdImagerie,
        date: c.aujourdhui,
        patientRepertoire: pt);
    for (final d in r.demandes) {
      m.collection('demandesAnalyses').inserer(d, prefixe: 'DEM');
    }
    m.collection('factures').inserer(r.facture, prefixe: 'FAC');
    for (final t in r.taches) {
      m.collection('taches').inserer(t, prefixe: 'TCH');
    }
    return r;
  }

  static void imprimerFiche(BuildContext ctx, Fiche pt, Map<String, Object?> v, PatDemandeExterne r) {
    final c = ContexteEcran.of(ctx);
    final niveau = blocNiveauxUrgence.where((u) => u.id == v['urgence']).firstOrNull;
    final prescripteur = blocNomPrescripteur(v['prescripteur'], v['prescripteurExterne']);
    afficherApercu(
        ctx,
        PieceA4(
          titre: 'FICHE DE DEMANDE D’EXAMEN',
          sousTitre: '${r.demandes.firstOrNull?['codeAnalyse'] ?? r.facture['numero']}',
          cartouche: [
            ('Nom', '${pt['nom']}'),
            ('Prénoms', '${pt['prenom']}'),
            ('Âge', blocAgeTexte(pt['dateNaissance'], c.aujourdhui)),
            ('Sexe', pt['sexe'] == 'F' ? 'Féminin' : 'Masculin'),
            ('Résidence', '${v['residence']}'),
            ('Service demandeur', libelleService(v['serviceDemandeur'])),
            ('Prescripteur', prescripteur),
            ('Hospitalisé', v['hospitalise'] == true ? 'Oui' : 'Non'),
          ],
          blocs: [
            BlocTexte('Indication clinique : ${v['indication']}'),
            BlocTexte(
                'Urgence : ${niveau?.label ?? '—'}${v['urgence'] == 'examen' && '${v['examenUrgent'] ?? ''}'.isNotEmpty ? ' — ${v['examenUrgent']}' : ''}',
                gras: true),
            BlocTableau(TableauEtat(colonnes: [
              ColonneEtat(libelle: 'Code', valeur: (x) => x['analyseCode']),
              ColonneEtat(libelle: 'Examen demandé', valeur: (x) => x['analyse']),
              ColonneEtat(libelle: 'Échantillon', valeur: (x) => x['echantillon']),
              ColonneEtat(
                  libelle: 'Tarif',
                  droite: true,
                  valeur: (x) => money(x['prix'], avecDevise: false),
                  somme: (x) => nombreOuZero(x['prix'])),
            ], lignes: r.demandes)),
          ],
          signatures: [Signature('Le prescripteur', nom: prescripteur)],
          reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
        ));
  }

  static void nouvelleFiche(BuildContext ctx, Magasin m) {
    final c = ContexteEcran.of(ctx);
    final defs = champs(m);
    final ctl = ControleurFormulaire(defs, const {'urgence': 'aucune'});
    // La résidence se reprend du dossier au choix du patient — sans écraser une saisie déjà faite.
    var dernier = '${ctl['patientCode']}';
    ctl.addListener(() {
      final courant = '${ctl['patientCode']}';
      if (courant == dernier) return;
      dernier = courant;
      final pt = patientParCodeBloc(m, courant);
      if (pt != null && '${ctl['residence']}'.isEmpty) {
        ctl.poser('residence', '${pt['adresse'] ?? pt['quartier'] ?? ''}');
      }
    });
    afficherModale<void>(ctx,
        titre: 'Fiche de demande d’examen',
        sousTitre: 'Tous les champs de la fiche papier sont obligatoires.',
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Émettre la fiche',
                  icone: LucideIcons.send,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    final refus = blocRefusDemandeExamen(v);
                    if (refus != null) {
                      toastRefus(ctx, refus);
                      return;
                    }
                    final pt = patientParCodeBloc(m, v['patientCode']);
                    if (pt == null) {
                      ToastsSigh.afficher(ctx, 'Patient introuvable.', type: TypeToast.erreur);
                      return;
                    }
                    final PatDemandeExterne r;
                    try {
                      r = emettre(c, pt, v);
                    } on PatRefus catch (e) {
                      ToastsSigh.afficher(ctx, e.message, type: TypeToast.erreur);
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, 'Fiche émise — ${r.demandes.length} examen(s).',
                        type: TypeToast.succes,
                        duree: const Duration(seconds: 8),
                        detail: 'Facture ${r.facture['numero']} à la caisse ; le prélèvement suivra le règlement.');
                    imprimerFiche(ctx, pt, v, r);
                  }),
            ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('demandesAnalyses');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final rows = blocDemandesService(col.actives);
        final k = blocKpisDemandes(rows);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          bandeauLectureSeule(c),
          kpisBloc([
            KpiSigh(libelle: 'Fiches du service', valeur: nombre(k.fiches), icone: LucideIcons.clipboardList),
            KpiSigh(
                libelle: 'En attente de règlement',
                valeur: nombre(k.attente),
                icone: LucideIcons.wallet,
                ton: TonSigh.attention),
            KpiSigh(libelle: 'Urgentes', valeur: nombre(k.urgentes), icone: LucideIcons.siren, ton: TonSigh.danger),
            KpiSigh(
                libelle: 'Résultats rendus',
                valeur: nombre(k.rendus),
                icone: LucideIcons.fileCheck2,
                ton: TonSigh.succes),
          ]),
          TableauSigh(
            titre: 'Registre des fiches de demande',
            lignes: rows,
            nomExport: 'demandes-examen-service',
            triInitial: 'dateHeure',
            sensInitial: 'desc',
            messageVide: 'Aucune fiche de demande émise par les services.',
            actions: [
              if (c.droit.editer)
                BoutonSigh(
                    libelle: 'Nouvelle fiche de demande',
                    icone: LucideIcons.plus,
                    taille: TailleBouton.sm,
                    onPressed: () => nouvelleFiche(context, c.magasin)),
            ],
            colonnes: [
              ColonneTableau(
                  cle: 'reference',
                  libelle: 'N°',
                  sansCoupure: true,
                  texte: (r) => '${r['reference'] ?? ''}${'${r['codeAnalyse'] ?? ''}'.isEmpty ? '' : ' ${r['codeAnalyse']}'}',
                  rendu: (_, r) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${r['reference'] ?? ''}',
                                style: const TextStyle(
                                    fontFamily: 'LiberationMono',
                                    fontSize: 12,
                                    height: 16 / 12,
                                    color: JetonsShell.slate700)),
                            if ('${r['codeAnalyse'] ?? ''}'.isNotEmpty)
                              Text('${r['codeAnalyse']}',
                                  style: const TextStyle(
                                      fontFamily: 'LiberationMono',
                                      fontSize: 10,
                                      height: 15 / 10,
                                      color: JetonsShell.navy700)),
                          ])),
              ColonneTableau(
                  cle: 'dateHeure',
                  libelle: 'Date',
                  valeur: (r) => DateTime.tryParse('${r['dateHeure'] ?? ''}')?.millisecondsSinceEpoch ?? 0,
                  texte: (r) => dateBloc(r['dateHeure'])),
              ColonneTableau(
                  cle: 'patient',
                  libelle: 'Patient',
                  texte: (r) => '${r['patient']} — ${'${r['patientCode'] ?? ''}'.isEmpty ? '—' : r['patientCode']}'),
              const ColonneTableau(cle: 'analyse', libelle: 'Examen'),
              ColonneTableau(
                  cle: 'serviceDemandeur', libelle: 'Service', texte: (r) => libelleService(r['serviceDemandeur'])),
              ColonneTableau(
                  cle: 'urgent',
                  libelle: 'Urgence',
                  texte: (r) => r['urgent'] == true ? 'Urgent' : 'Courant',
                  rendu: (_, r) => r['urgent'] == true
                      ? const BadgeSigh('Urgent', ton: TonSigh.danger)
                      : const Text('Courant',
                          style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12))),
              ColonneTableau(
                  cle: 'etatAnalyse',
                  libelle: 'État',
                  texte: (r) => statutsMetier['${r['etatAnalyse']}']?.$1 ?? '${r['etatAnalyse'] ?? ''}',
                  rendu: (_, r) => statutBadge(r['etatAnalyse'])),
            ],
          ),
        ]);
      },
    );
  }
}
