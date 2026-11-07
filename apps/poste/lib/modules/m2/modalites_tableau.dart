import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cr_commun.dart';
import 'cr_saisie.dart';

/// `ecranTableauImagerie(o)` — UNE fabrique, CINQ modalités (vague 61) : radiographie, mammographie, scanner et IRM se branchent sur le socle de
/// l'échographie (même compte rendu par variables, même rendu au prescripteur, même registre des demandes, même verrou de caisse). Seul change le
/// FILTRE — la modalité de l'examen, lue au catalogue — et l'indicateur que l'écran met en avant. Cinq écrans écrits à la main auraient divergé
/// au premier correctif.
///
/// Écart E121 (dit) : la maquette offre sur chaque ligne un crayon « Modifier » (`K.actionsLigne` appelé SANS liste de champs) dont le clic lève
/// `Cannot read properties of null (reading 'forEach')` — aucune fenêtre ne s'ouvre. Il n'est pas porté : la voie de modification d'un brouillon est
/// « Poursuivre la saisie », qui existe à côté.
class EcranTableauImagerie extends StatelessWidget with EcranMaquette {
  const EcranTableauImagerie(
      {super.key,
      required this.modalite,
      required this.titreEcran,
      required this.descriptionEcran,
      required this.regleEcran,
      this.noteEcran,
      this.indicationHint = ''});

  final String modalite;
  final String titreEcran;
  final String descriptionEcran;
  final String regleEcran;
  final String? noteEcran;
  final String indicationHint;

  @override
  String get titre => titreEcran;

  @override
  String get description => descriptionEcran;

  @override
  String get regle => sansBalises(regleEcran);

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    final col = colCR(m);
    final demandes = colDemandesImagerie(m);
    final mod = modaliteOuInconnue(modalite);
    return ListenableBuilder(
      listenable: Listenable.merge([col, demandes]),
      builder: (context, _) {
        final examens = examensImagerie(m);
        final rows = crsDeModalite(modalite, col.actives, examens);
        final dems = [
          for (final d in demandes.actives)
            if (modaliteDeCodeExamen(examens, d['examenCode']) == modalite) d
        ];
        final aExecuter = dems.where((d) => d['statut'] == 'payee').toList();
        // `C.sortBy(rows, 'date').reverse()` : date croissante PUIS inversée (à égalité, l'ordre du magasin s'inverse).
        final ordre = trierPar(rows, (r) => r['date']).reversed.toList();
        final ex = [
          for (final x in examens)
            if (modaliteDeExamen(x) == modalite) x
        ];
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!c.droit.editer && c.droit.voir)
                Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: NoteSigh(
                        'Lecture seule : le profil « ${c.role} » consulte cet écran sans pouvoir y écrire. Les droits se règlent dans la matrice des rôles.',
                        ton: TonSigh.attention)),
              KpiGrilleSigh(kpis: [
                for (final i in indicateursImagerie(modalite, rows, aExecuter))
                  KpiSigh(
                      libelle: i.libelle,
                      valeur: nombre(i.valeur),
                      icone: iconeDe(i.icone),
                      ton: tonDe(i.ton),
                      indice: i.indice),
              ]),
              if (noteEcran != null) ...[
                const SizedBox(height: 16),
                NoteSigh(sansBalises(noteEcran!), icone: LucideIcons.penLine),
              ],
              if (mod.aValider != null) ...[
                const SizedBox(height: 16),
                NoteSigh(
                    'Examens et variables proposés, à valider. Aucun modèle de compte rendu de ${mod.label.toLowerCase()} n’a été remis : le catalogue suit la pratique radiologique courante et reste administrable depuis le catalogue de l’imagerie. Les tarifs sont des tarifs d’attente, à arrêter par la Direction. Les images elles-mêmes ne sont pas stockées au format DICOM : le logiciel tient la demande, le compte rendu et les clichés joints à la galerie.',
                    ton: TonSigh.attention,
                    icone: LucideIcons.flaskConical),
              ],
              const SizedBox(height: 16),
              TableauSigh(
                nomExport: 'imagerie-$modalite',
                taillePage: 12,
                messageVide:
                    'Aucun compte rendu de ${mod.label.toLowerCase()} enregistré.',
                lignes: ordre,
                filtres: [
                  FiltreTableau(nom: 'examenCode', libelle: 'Examen', options: [
                    for (final x in ex)
                      OptionChamp('${x['code']}', '${x['label']}')
                  ]),
                  const FiltreTableau(nom: 'statut', libelle: 'État', options: [
                    OptionChamp('rendu', 'Rendu'),
                    OptionChamp('brouillon', 'En rédaction'),
                  ]),
                ],
                actions: [
                  if (c.droit.editer)
                    BoutonSigh(
                        libelle: 'Nouveau compte rendu',
                        icone: LucideIcons.plus,
                        taille: TailleBouton.sm,
                        onPressed: () => modaleEnteteCR(context, mod,
                            retour: c.ecranId, indicationHint: indicationHint)),
                ],
                colonnes: [
                  const ColonneTableau(cle: 'reference', libelle: 'Référence'),
                  ColonneTableau(
                      cle: 'date',
                      libelle: 'Date',
                      texte: (r) => dateHeureDe(r['date'])),
                  ColonneTableau(
                      cle: 'patient',
                      libelle: 'Patient',
                      texte: (r) => '${r['patient']} — ${r['patientCode']}'),
                  const ColonneTableau(cle: 'examen', libelle: 'Examen'),
                  const ColonneTableau(
                      cle: 'prescripteur', libelle: 'Prescripteur'),
                  const ColonneTableau(
                      cle: 'realisateur', libelle: 'Réalisé par'),
                  ColonneTableau(
                      cle: 'statut',
                      libelle: 'État',
                      texte: (r) =>
                          r['statut'] == 'rendu' ? 'Rendu' : 'En rédaction',
                      rendu: (_, r) => r['statut'] == 'rendu'
                          ? const BadgeSigh('Rendu', ton: TonSigh.succes)
                          : const BadgeSigh('En rédaction',
                              ton: TonSigh.attention)),
                ],
                actionsLigne: (ctx, r) => [
                  BoutonIcone(
                      icone: LucideIcons.printer,
                      libelle: 'Imprimer le compte rendu',
                      onPressed: () => imprimerCR(ctx, r)),
                  if (c.droit.editer && r['statut'] != 'rendu') ...[
                    BoutonIcone(
                        icone: LucideIcons.pencil,
                        libelle: 'Poursuivre la saisie',
                        onPressed: () => saisirCR(c, r, retour: c.ecranId)),
                    BoutonIcone(
                        icone: LucideIcons.send,
                        libelle: 'Rendre au prescripteur',
                        onPressed: () => rendreCR(ctx, r)),
                  ],
                  BoutonIcone(
                      icone: LucideIcons.eye,
                      libelle: 'Consulter',
                      onPressed: () => consulterCR(ctx, r)),
                  if (c.droit.annuler)
                    BoutonIcone(
                        icone: LucideIcons.archive,
                        libelle: 'Archiver',
                        onPressed: () => archiverCR(ctx, r)),
                ],
              ),
            ]);
      },
    );
  }
}

const _reglesRadiologie =
    'Le tableau se branche sur le <strong>socle commun de l’imagerie</strong> : la demande naît <strong>bloquée par le paiement</strong>, le compte rendu se saisit par <strong>variables</strong> sur une demande réglée, puis se <strong>rend au prescripteur</strong> — après quoi il ne se modifie plus. Le plan du compte rendu est celui de la radiologie : technique, résultats, <strong>conclusion obligatoire</strong>, recommandation.';

/// Les cinq déclarations de `ecranTableauImagerie({…})` de la maquette.
const echographieTableau = EcranTableauImagerie(
  modalite: 'echographie',
  titreEcran: 'Tableau Échographie',
  descriptionEcran:
      'Comptes rendus d’échographie et d’électrocardiogramme, saisis par variables et rendus au prescripteur.',
  regleEcran:
      'Les résultats se saisissent par <strong>listes de choix</strong> — c’est la demande écrite de l’échographiste ; les <strong>mesures se saisissent en texte</strong>, et un champ de précision n’apparaît que lorsque la valeur l’appelle (« Autre », « hétérogène »). Seule la <strong>Conclusion</strong> reste en texte libre — « Annexes » a été retirée à sa demande (14/09/2026). Le compte rendu porte le <strong>prescripteur</strong>, le <strong>réalisateur</strong> et la <strong>provenance</strong>.',
  noteEcran:
      'Les listes de choix pré-insérées viennent du <strong>brouillon manuscrit de l’échographiste</strong>, des cinq comptes rendus réels et de ses <strong>corrections du 14/09/2026</strong>. Deux ou trois sacs gestationnels déclarés font paraître autant de blocs de sac, repliables.',
  indicationHint:
      'Ce que le prescripteur cherche — « Kyste ovarien ? », « RAU », « Terme », « Croissance ».',
);

const radiographieTableau = EcranTableauImagerie(
  modalite: 'radiographie',
  titreEcran: 'Tableau Radiographie',
  descriptionEcran:
      'Comptes rendus de radiographie standard — thorax, bassin, rachis, membres, crâne, ASP.',
  regleEcran:
      '$_reglesRadiologie Un cliché de <strong>qualité insuffisante</strong> se dit sur la pièce : un « normal » lu sur une image inexploitable est une fausse assurance.',
  indicationHint:
      'Traumatisme, toux fébrile, douleur lombaire, bilan préopératoire…',
);

const mammographieTableau = EcranTableauImagerie(
  modalite: 'mammographie',
  titreEcran: 'Tableau Mammographie',
  descriptionEcran:
      'Comptes rendus de mammographie — densité, masses, microcalcifications, classification ACR par sein.',
  regleEcran:
      '$_reglesRadiologie La <strong>classification ACR se porte sein par sein</strong> : c’est la conduite à tenir qui en découle, et elle diffère d’un côté à l’autre.',
  indicationHint: 'Dépistage, nodule palpé, écoulement, surveillance…',
);

const scannerTableau = EcranTableauImagerie(
  modalite: 'scanner',
  titreEcran: 'Tableau Scanner',
  descriptionEcran:
      'Comptes rendus de tomodensitométrie — technique, injection de produit de contraste, résultats.',
  regleEcran:
      '$_reglesRadiologie L’<strong>injection</strong> est une donnée de sécurité : produit, volume, créatininémie, allergie et réaction se consignent, et « aucune réaction » <strong>s’écrit</strong>.',
  indicationHint:
      'Céphalées, traumatisme crânien, bilan d’extension, colique néphrétique…',
);

const irmTableau = EcranTableauImagerie(
  modalite: 'irm',
  titreEcran: 'Tableau IRM — imagerie par résonance magnétique',
  descriptionEcran:
      'Comptes rendus d’IRM — contre-indications, séquences, gadolinium, résultats.',
  regleEcran:
      '$_reglesRadiologie Les <strong>contre-indications</strong> (pacemaker, clip métallique, grossesse) se vérifient et se consignent <strong>avant</strong> l’examen ; les séquences réalisées sont portées sur la pièce.',
  indicationHint: 'Sciatique, épilepsie, entorse du genou, masse pelvienne…',
);
