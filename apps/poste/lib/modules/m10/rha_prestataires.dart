import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m4/mat_commun.dart';
import '../m4/mat_crud.dart';
import 'rha_commun.dart';

/// `m10-prestataires` — intervenants extérieurs rémunérés à l'acte. La question posée par la Direction n'est pas « qui est référencé » mais « combien
/// nous coûtent-ils, sur quels actes, et lesquels ne fournissent pas de facture normalisée » (conséquence fiscale directe : charge non déductible,
/// dépense hors circuit MECeF). Montant dû = tarif × actes réalisés, jamais saisi.
class EcranPrestataires extends StatelessWidget with EcranMaquette {
  const EcranPrestataires({super.key});
  @override
  String get titre => 'Prestataires externes';
  @override
  String get description => 'Intervenants extérieurs rémunérés à l’acte : circoncision, hydrotubation, accouchement, analyses, hospitalisation.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('prestataires');
    Fiche fiche(BuildContext ctx, Map<String, Object?> v, Fiche? existante) => rhaPrestataireEnregistrable(
        {...v, 'tarifActe': rhaNum(v['tarifActe']), 'actesRealises': rhaNum(v['actesRealises'])},
        reference: '${existante?['reference'] ?? ''}'.isNotEmpty ? '${existante!['reference']}' : admReferenceSuivante('PE-', 4, col.toutes));

    return CrudMat(
      collection: col,
      entite: 'prestataire',
      entiteP: 'prestataires',
      prefixeId: 'PRE',
      triInitial: 'nom',
      taillePage: 15,
      apresTableau: (ctx) => Padding(padding: const EdgeInsets.only(top: 16), child: _graphiques(col.actives)),
      colonnes: [
        ColonneTableau(cle: 'reference', libelle: 'N°', sansCoupure: true, rendu: (_, r) => matRef(r['reference'])),
        const ColonneTableau(cle: 'nom', libelle: 'Prestataire'),
        ColonneTableau(cle: 'specialite', libelle: 'Spécialité / acte', rendu: (_, r) => BadgeSigh('${r['specialite']}', ton: TonSigh.navy)),
        const ColonneTableau(cle: 'telephone', libelle: 'Téléphone', sansCoupure: true),
        ColonneTableau(cle: 'tarifActe', libelle: 'Tarif par acte', droite: true, texte: (r) => money(r['tarifActe'], avecDevise: false)),
        const ColonneTableau(cle: 'actesRealises', libelle: 'Actes réalisés', droite: true),
        ColonneTableau(
            cle: 'montantDu',
            libelle: 'Montant dû',
            droite: true,
            valeur: rhaMontantDuPrestataire,
            texte: (r) => money(rhaMontantDuPrestataire(r), avecDevise: false),
            rendu: (_, r) => Text(money(rhaMontantDuPrestataire(r), avecDevise: false), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: JetonsShell.slate800))),
        ColonneTableau(
            cle: 'ifu',
            libelle: 'IFU',
            sansCoupure: true,
            rendu: (_, r) => rhaVrai(r['ifu']) ? matRef(r['ifu']) : const BadgeSigh('Non renseigné', ton: TonSigh.attention)),
        ColonneTableau(
            cle: 'factureNormalisee',
            libelle: 'Facture normalisée',
            texte: (r) => rhaVrai(r['factureNormalisee']) ? 'Oui' : 'Non',
            rendu: (_, r) => rhaVrai(r['factureNormalisee']) ? const BadgeSigh('Fournie', ton: TonSigh.succes) : const BadgeSigh('Manquante', ton: TonSigh.danger)),
      ],
      champs: (m) => [
        const ChampDef(nom: 'nom', libelle: 'Nom du prestataire', requis: true, col: ColChamp.plein),
        ChampDef(nom: 'specialite', libelle: 'Spécialité / type d’acte', type: TypeChamp.select, requis: true, options: rhaOptions([...rhaSpecialitesPrestataire, 'Autre'])),
        const ChampDef(nom: 'telephone', libelle: 'Téléphone', type: TypeChamp.tel),
        const ChampDef(nom: 'tarifActe', libelle: 'Tarif par acte (FCFA)', type: TypeChamp.nombre, requis: true),
        const ChampDef(nom: 'actesRealises', libelle: 'Actes réalisés (mois en cours)', type: TypeChamp.nombre),
        const ChampDef(nom: 'ifu', libelle: 'IFU du prestataire'),
        const ChampDef(nom: 'factureNormalisee', libelle: 'Facture normalisée fournie', type: TypeChamp.case_, col: ColChamp.plein),
      ],
      valeursInitiales: () => {'actesRealises': '0', 'factureNormalisee': false},
      transformer: (ctx, v) => fiche(ctx, v, null),
      transformerExistante: fiche,
      referenceToast: (f) => '${f['reference'] ?? ''}',
      filtres: [FiltreTableau(nom: 'specialite', libelle: 'Spécialité', options: rhaOptions(rhaSpecialitesPrestataire))],
      kpis: (ctx, rows) => rhaKpisW(rhaKpisPrestataires(rows), const [LucideIcons.userCheck, LucideIcons.activity, LucideIcons.wallet, LucideIcons.fileX]),
      etat: (ctx, p) => matImprimer(ctx,
          titre: 'État de rémunération — prestataire externe',
          sousTitre: '${p['nom']}',
          cartouche: [
            ('Prestataire', '${p['nom']}'),
            ('Référence', '${p['reference']}'),
            ('Spécialité', '${p['specialite']}'),
            ('IFU', rhaVrai(p['ifu']) ? '${p['ifu']}' : 'Non renseigné'),
            ('Tarif par acte', money(p['tarifActe'])),
            ('Facture normalisée', rhaVrai(p['factureNormalisee']) ? 'Fournie' : 'Manquante'),
          ],
          blocs: [
            rhaBlocRubriques([
              ('Nombre d’actes réalisés', nombre(rhaNum(p['actesRealises']))),
              ('Tarif unitaire', money(p['tarifActe'], avecDevise: false)),
              ('MONTANT TOTAL DÛ', money(rhaMontantDuPrestataire(p), avecDevise: false)),
            ], col2: 'Valeur', droiteValeur: true),
          ],
          signatures: [Signature('Le Prestataire', nom: '${p['nom']}'), const Signature('Le Comptable', nom: 'KASSA Augustin'), rhaSignDa]),
    );
  }

  /// Les prestations externes vues d'ensemble : montant dû par spécialité, actes par spécialité, facture normalisée, les huit mieux rémunérés.
  Widget _graphiques(List<Fiche> rows) {
    if (rows.isEmpty) return const CarteSigh(titre: 'Statistiques des prestations externes', child: VideSigh('Aucun prestataire référencé.', icone: LucideIcons.handshake));
    final st = rhaStatsPrestataires(rows);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      rhaCartes(colonnes: 3, [
        CarteSigh(titre: 'Montant dû par spécialité', child: GraphiqueBarres(horizontal: true, etiquettes: st.specialites, series: [SerieGraphique('FCFA', st.montants, couleur: JetonsShell.navy900)])),
        CarteSigh(titre: 'Actes réalisés par spécialité', child: GraphiqueAnneau(trou: 0, etiquettes: st.specialites, valeurs: st.actes)),
        CarteSigh(
            titre: 'Facture normalisée',
            child: GraphiqueAnneau(etiquettes: const ['Fournie', 'Manquante'], valeurs: [st.facturesFournies, st.facturesManquantes], couleurs: const [JetonsShell.success500, JetonsShell.danger500])),
      ]),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Les huit prestataires les plus rémunérés',
          child: RhaClassement(argent: true, [for (final x in st.classement) (libelle: x.libelle, valeur: x.valeur, rouge: x.sansFacture)])),
      const SizedBox(height: 16),
      const NoteSigh(
          'Un prestataire sans facture normalisée expose la clinique : la charge n’est pas déductible et la dépense reste hors du circuit MECeF. Ces lignes apparaissent en rouge au classement ci-dessus.',
          ton: TonSigh.attention,
          icone: LucideIcons.fileX),
    ]);
  }
}
