import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m1/commun_m1.dart' show bandeauLectureSeule, valeursFormulaire;
import 'bloc_commun.dart';

/// `m3-sortie-avis-medical` — « Sortie contre avis médical » : les sorties décidées par le patient contre l'avis du médecin, avec motif et avis du
/// Procureur le cas échéant.
///
/// RG-08 — toute sortie contre avis médical est MOTIVÉE ; si la situation l'exige, l'avis du Procureur est consigné (sa RÉFÉRENCE est alors
/// obligatoire) avant clôture du dossier. Consigner une sortie fait sortir l'admission (le lit est libéré).
///
/// Écarts : E418 (corrigé dans la maquette, porté tel quel) — les indicateurs et la liste des hospitalisés sont relus à chaque geste, et l'admission de
/// la procédure reste proposée à sa modification (E419 : elle n'est plus « en cours »). E426 — annuler la consignation remet aussi le patient en
/// hospitalisation. E425 — « Modifier » et « Archiver » sont ABSENTS sans le droit (la maquette les offrait à tout profil). E427 — la décharge signée
/// est annoncée « impérative » mais n'est pas exigée : une sortie sans décharge s'enregistre et le registre la montre « Manquante », en rouge.
class EcranSortieAvisMedical extends StatelessWidget with EcranMaquette {
  const EcranSortieAvisMedical({super.key});

  @override
  String get titre => 'Sortie contre avis médical';

  @override
  String get description =>
      'Enregistrement des sorties décidées par le patient contre l’avis du médecin, avec motif et avis du Procureur le cas échéant.';

  @override
  String get regle =>
      'RG-08 — toute sortie contre avis médical est motivée ; si la situation l’exige, l’avis du Procureur est consigné avant clôture du dossier.';

  static List<ChampDef> champs(Magasin m, Fiche? record) {
    final options = [
      for (final a in hosEnCours(m.collection('admissions').actives))
        OptionChamp('${a['id']}', '${a['lit']} — ${a['patient']} (${a['patientCode']})'),
    ];
    // E419 : à la modification, l'admission de la procédure n'est plus « en cours » — elle reste proposée.
    if (record != null && '${record['admissionId'] ?? ''}'.isNotEmpty && !options.any((o) => o.valeur == record['admissionId'])) {
      options.insert(0, OptionChamp('${record['admissionId']}', '${record['lit'] ?? '—'} — ${record['patient']} (${record['patientCode']})'));
    }
    return [
      ChampDef(
          nom: 'admissionId',
          libelle: 'Patient hospitalisé',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          options: options),
      const ChampDef(nom: 'dateSortie', libelle: 'Date de sortie', type: TypeChamp.date, requis: true),
      champHeure('heureSortie', 'Heure'),
      const ChampDef(
          nom: 'motif',
          libelle: 'Motif invoqué par le patient',
          type: TypeChamp.textarea,
          lignes: 2,
          requis: true,
          col: ColChamp.plein),
      const ChampDef(
          nom: 'risques',
          libelle: 'Risques exposés au patient',
          type: TypeChamp.textarea,
          lignes: 2,
          col: ColChamp.plein),
      const ChampDef(nom: 'avisProcureur', libelle: 'Avis du Procureur requis et consigné', type: TypeChamp.case_),
      const ChampDef(nom: 'referenceProcureur', libelle: 'Référence de l’avis du Procureur'),
      const ChampDef(nom: 'decharge', libelle: 'Décharge signée par le patient', type: TypeChamp.case_),
      const ChampDef(nom: 'cloture', libelle: 'Dossier clôturé', type: TypeChamp.case_),
    ];
  }

  static String _ou(Object? v, [String vide = '—']) => '${v ?? ''}'.isEmpty ? vide : '$v';

  /// La décharge de responsabilité : un document officiel, trois signatures.
  static void imprimer(BuildContext ctx, Fiche r) {
    final c = ContexteEcran.of(ctx);
    afficherApercu(
        ctx,
        PieceA4(
          titre: 'Sortie contre avis médical',
          sousTitre: 'Décharge de responsabilité — ${r['reference']}',
          filigrane: 'Document officiel',
          cartouche: [
            ('Patient', '${r['patient']}'),
            ('Dossier', _ou(r['patientCode'], '')),
            ('Lit', _ou(r['lit'], '')),
            ('Date de sortie', dateBloc(r['dateSortie'])),
            ('Heure', _ou(r['heureSortie'])),
            ('Référence', '${r['reference']}'),
          ],
          blocs: [
            BlocTableau(TableauEtat(colonnes: [
              ColonneEtat(libelle: 'Rubrique', valeur: (x) => x['k']),
              ColonneEtat(libelle: 'Information', valeur: (x) => x['v']),
            ], lignes: [
              {'k': 'Motif invoqué par le patient', 'v': r['motif']},
              {'k': 'Risques exposés au patient', 'v': _ou(r['risques'])},
              {
                'k': 'Avis du Procureur',
                'v': r['avisProcureur'] == true ? 'Consigné — ${_ou(r['referenceProcureur'], '')}' : 'Sans objet'
              },
              {'k': 'Décharge signée', 'v': r['decharge'] == true ? 'Oui' : 'Non'},
            ])),
            const BlocTexte(
                'Je soussigné(e), patient(e) ou représentant légal, déclare quitter la CLINIQUE NASSIERA TOO SARL contre l’avis du médecin traitant. J’ai été pleinement informé(e) des risques encourus pour ma santé et je décharge l’établissement ainsi que son personnel de toute responsabilité quant aux conséquences de cette décision.'),
          ],
          signatures: const [
            Signature('Le Patient ou son représentant', mention: 'Signature précédée de la mention « lu et approuvé »'),
            Signature('Le Médecin', mention: 'Signature'),
            Signature('La Direction', mention: 'Visa'),
          ],
          reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
        ));
  }

  /// `ouvrir(record)` : la modale de consignation (création) ou de correction (modification).
  static void ouvrir(BuildContext ctx, Fiche? record) {
    final c = ContexteEcran.of(ctx);
    final m = c.magasin;
    final col = m.collection('sortiesAvisMedical');
    final defs = champs(m, record);
    final ctl = ControleurFormulaire(defs, record != null ? valeursFormulaire(record) : {'dateSortie': iso(c.aujourdhui)});
    afficherModale<void>(ctx,
        titre: record != null ? 'Modifier la procédure' : 'Sortie contre avis médical',
        sousTitre: 'RG-08 — motif obligatoire, avis du Procureur si la situation l’exige.',
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: record != null ? 'Enregistrer' : 'Consigner',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    final refus = blocRefusAvisMedical(v);
                    if (refus != null) {
                      toastRefus(ctx, refus);
                      return;
                    }
                    final adm = m.collection('admissions').toutes.where((x) => x['id'] == v['admissionId']).firstOrNull;
                    final fiche = blocConstruireAvis(v, admission: adm, existante: record, toutes: col.toutes);
                    final VoidCallback annulerFiche;
                    VoidCallback? annulerAdmission;
                    if (record != null) {
                      annulerFiche = col.mettreAJour(record['id'], fiche);
                    } else {
                      annulerFiche = col.inserer({'statut': 'actif', ...fiche}, prefixe: 'SOR').annuler;
                      // Consigner la sortie fait sortir l'admission : le lit est libéré (E426 : annuler la remet en hospitalisation).
                      if (adm != null) {
                        annulerAdmission = m
                            .collection('admissions')
                            .mettreAJour(adm['id'], {'statut': 'sortie', 'dateSortie': v['dateSortie']});
                      }
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, record != null ? 'Procédure mise à jour.' : 'Sortie contre avis médical consignée.',
                        type: TypeToast.succes, annuler: () {
                      annulerFiche();
                      annulerAdmission?.call();
                    });
                  }),
            ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('sortiesAvisMedical');
    final adm = c.magasin.collection('admissions');
    return ListenableBuilder(
      listenable: Listenable.merge([col, adm]),
      builder: (context, _) {
        final k = blocKpisAvis(col.actives, adm.actives);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          bandeauLectureSeule(c),
          kpisBloc([
            KpiSigh(
                libelle: 'Sorties contre avis médical',
                valeur: nombre(k.sorties),
                icone: LucideIcons.fileWarning,
                ton: TonSigh.danger),
            KpiSigh(
                libelle: 'Avec avis du Procureur',
                valeur: nombre(k.procureur),
                icone: LucideIcons.gavel,
                ton: TonSigh.attention),
            KpiSigh(libelle: 'Patients hospitalisés', valeur: nombre(k.hospitalises), icone: LucideIcons.bedDouble),
            KpiSigh(
                libelle: 'Dossiers clôturés',
                valeur: nombre(k.clotures),
                icone: LucideIcons.archive,
                ton: TonSigh.succes),
          ]),
          const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: NoteSigh(
                  'Cette procédure dégage la responsabilité de la clinique. Le motif du refus de soins et la décharge signée du patient sont impératifs.',
                  ton: TonSigh.attention,
                  icone: LucideIcons.triangleAlert)),
          TableauSigh(
            titre: 'Registre des sorties contre avis médical',
            lignes: col.actives,
            nomExport: 'sorties-contre-avis-medical',
            taillePage: 10,
            messageVide: 'Aucune sortie contre avis médical enregistrée.',
            indiceVide: c.droit.editer ? 'Utiliser le bouton « Enregistrer » pour consigner une nouvelle procédure.' : null,
            actions: [
              if (c.droit.editer)
                BoutonSigh(
                    libelle: 'Enregistrer',
                    icone: LucideIcons.plus,
                    taille: TailleBouton.sm,
                    onPressed: () => ouvrir(context, null)),
            ],
            actionsLigne: (ctx, r) => [
              BoutonIcone(icone: LucideIcons.printer, libelle: 'Imprimer le document', onPressed: () => imprimer(ctx, r)),
              if (c.droit.editer)
                BoutonIcone(icone: LucideIcons.pencil, libelle: 'Modifier', onPressed: () => ouvrir(ctx, r)),
              if (c.droit.annuler)
                BoutonIcone(
                    icone: LucideIcons.archive,
                    libelle: 'Archiver',
                    onPressed: () {
                      final annuler = col.archiver(r['id']);
                      ToastsSigh.afficher(ctx, 'Enregistrement archivé.', type: TypeToast.succes, annuler: annuler);
                    }),
            ],
            colonnes: [
              ColonneTableau(
                  cle: 'reference',
                  libelle: 'N°',
                  sansCoupure: true,
                  rendu: (_, r) => Text('${r['reference'] ?? ''}',
                      style: const TextStyle(
                          fontFamily: 'LiberationMono', fontSize: 12, height: 16 / 12, color: JetonsShell.slate700))),
              const ColonneTableau(cle: 'patient', libelle: 'Patient'),
              ColonneTableau(
                  cle: 'dateSortie',
                  libelle: 'Date de sortie',
                  sansCoupure: true,
                  valeur: (r) => '${r['dateSortie'] ?? ''}',
                  texte: (r) => dateBloc(r['dateSortie'])),
              const ColonneTableau(cle: 'motif', libelle: 'Motif invoqué'),
              ColonneTableau(
                  cle: 'avisProcureur',
                  libelle: 'Procureur',
                  texte: (r) => r['avisProcureur'] == true ? 'Avis consigné' : 'Sans objet',
                  rendu: (_, r) => r['avisProcureur'] == true
                      ? const BadgeSigh('Avis consigné', ton: TonSigh.attention)
                      : const Text('Sans objet',
                          style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12))),
              ColonneTableau(
                  cle: 'decharge',
                  libelle: 'Décharge',
                  texte: (r) => r['decharge'] == true ? 'Signée' : 'Manquante',
                  rendu: (_, r) => r['decharge'] == true
                      ? const BadgeSigh('Signée', ton: TonSigh.succes)
                      : const BadgeSigh('Manquante', ton: TonSigh.danger)),
              ColonneTableau(
                  cle: 'cloture',
                  libelle: 'Dossier',
                  texte: (r) => r['cloture'] == true ? 'Clôturé' : 'Ouvert',
                  rendu: (_, r) => r['cloture'] == true
                      ? const BadgeSigh('Clôturé', ton: TonSigh.neutre)
                      : const BadgeSigh('Ouvert', ton: TonSigh.info)),
            ],
          ),
        ]);
      },
    );
  }
}
