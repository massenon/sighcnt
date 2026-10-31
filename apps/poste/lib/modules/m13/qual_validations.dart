import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'qual_commun.dart';

/// `adm-validations` — « Validations en attente » : le centre qui répond à « qu'est-ce qui attend une validation, et de QUI ? ». Il ORIENTE, il ne valide
/// JAMAIS en masse : la validation est un geste humain, porté à SON POSTE, par la personne qui engage sa responsabilité (doctrine des deux verrous du
/// laboratoire). Quatre familles : les gestes de poste (comptés depuis les registres), les référentiels qui attendent un PROFESSIONNEL nommé, ce qui
/// attend un ARBITRAGE de la Direction, et ce que la Direction a déjà validé le 01/09.
///
/// Une file amorcée par un écran d'un autre module (bons de besoins, commandes) s'annonce « non amorcée » plutôt que d'afficher un 0 faux. L'écran ne
/// porte AUCUNE commande d'écriture : « Y aller » et « Ouvrir » naviguent, rien ne se valide ici. Les règles sont dans `qual_validations.dart`.
class EcranValidations extends StatelessWidget with EcranMaquette {
  const EcranValidations({super.key});

  @override
  String get titre => 'Validations en attente';

  @override
  String get description =>
      'Tout ce qui attend une validation, classé par poste et par responsable — avec le chemin vers le geste.';

  @override
  String get regle =>
      'Cet écran oriente, il ne valide jamais en masse : la validation est un geste humain, porté à son poste — le biologiste valide au laboratoire, le comptable au journal, la DA sur le bon. Les validations écrites des professionnels nommés sont arrivées le 01/09/2026 (biologiste, médecins, praticiens du bloc) ; ce qui reste en attente est une donnée manquante ou récurrente, jamais une signature que la Direction pourrait porter à leur place.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    final noms = [
      'demandesAnalyses',
      'ecritures',
      'besoins',
      'commandes',
      'factures',
      'resultatsImagerie',
      'echeancesFiscales',
      'materiel',
      'plagesReactif'
    ];
    return ListenableBuilder(
        listenable: Listenable.merge([for (final n in noms) m.collection(n)]),
        builder: (context, _) {
          final files = qualFilesValidation(
              demandesAnalyses: m.collection('demandesAnalyses').toutes,
              ecritures: m.collection('ecritures').toutes,
              besoinsToutes: m.collection('besoins').toutes,
              commandesToutes: m.collection('commandes').toutes,
              factures: m.collection('factures').toutes,
              resultatsImagerie: m.collection('resultatsImagerie').toutes,
              echeancesFiscales: m.collection('echeancesFiscales').toutes,
              aujourdhui: jourIso(c));
          final pros = qualProfessionnels(
              materiel: m.collection('materiel').toutes,
              plagesReactif: m.collection('plagesReactif').toutes);
          final bilan = qualBilanValidations(files, pros);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KpiGrilleSigh(kpis: [
              KpiSigh(
                  libelle: 'Gestes de validation en attente',
                  valeur: nombre(bilan.gestes),
                  icone: LucideIcons.listChecks,
                  ton: bilan.gestes > 0 ? TonSigh.attention : TonSigh.succes),
              KpiSigh(
                  libelle: 'Files concernées',
                  valeur: bilan.filesTexte,
                  icone: LucideIcons.layoutGrid,
                  ton: TonSigh.neutre),
              KpiSigh(
                  libelle: 'Référentiels en attente d’un professionnel',
                  valeur: nombre(bilan.professionnels),
                  icone: LucideIcons.userCheck,
                  ton: TonSigh.info),
              KpiSigh(
                  libelle: 'Validés par la Direction le 01/09',
                  valeur: nombre(bilan.validees),
                  icone: LucideIcons.circleCheck,
                  ton: TonSigh.succes),
            ]),
            const SizedBox(height: 16),
            CarteSigh(
                titre: 'À valider À SON POSTE — l’écran oriente, le poste valide',
                child: LayoutBuilder(builder: (context, k) {
                  final deux = k.maxWidth >= 768;
                  final l = deux ? (k.maxWidth - 12) / 2 : k.maxWidth;
                  return Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final f in files) SizedBox(width: l, child: _file(c, f)),
                  ]);
                })),
            const SizedBox(height: 16),
            CarteSigh(
                titre:
                    'Référentiels en attente d’un PROFESSIONNEL nommé — la Direction ne signe pas à sa place',
                child: Column(children: [
                  for (final (i, p) in pros.indexed) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _bloc(c, p.titre, '${p.qui} · ${p.motif}', p.ecran, attention: false),
                  ]
                ])),
            const SizedBox(height: 16),
            CarteSigh(
                titre: 'En attente d’un ARBITRAGE de la Direction — elle seule peut trancher',
                child: Column(children: [
                  for (final (i, a) in qualArbitrages.indexed) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _bloc(c, a.libelle, a.detail, a.ecran, attention: true),
                  ]
                ])),
            const SizedBox(height: 16),
            CarteSigh(
                titre: 'Validées par la DIRECTION le 01/09/2026 (vague 49)',
                sansRemplissage: true,
                child: MiniTableauSigh(colonnes: [
                  ColonneMini('Référentiel', (x) => '${x['libelle']}'),
                  ColonneMini('Décision', (x) => '${x['detail']}'),
                ], lignes: [
                  for (final v in qualValidees) {'libelle': v.$1, 'detail': v.$2}
                ])),
            sourceQual('Compté à chaque affichage depuis les registres du magasin — rien n’est fourni.'),
          ]);
        });
  }

  /// Une file de gestes : icône, intitulé, poste (ou « non amorcée »), compte, « Y aller ».
  Widget _file(ContexteEcran c, QualFile f) => Container(
      padding: const EdgeInsets.all(20),
      decoration: decorationCarte(),
      child: Row(children: [
        Icon(iconeQual(f.icone), size: 24, color: JetonsShell.navy600),
        const SizedBox(width: 12),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(f.libelle,
              style: const TextStyle(
                  color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500)),
          Text(f.sousTitre,
              style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
        ])),
        const SizedBox(width: 12),
        Text(f.compte == null ? '—' : nombre(f.compte),
            key: Key('qual:compte:${f.ecran}'),
            style: TextStyle(
                color: (f.compte ?? 0) > 0 ? JetonsShell.warning700 : JetonsShell.slate300,
                fontSize: 18,
                height: 28 / 18,
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 12),
        BoutonSigh(
            libelle: 'Y aller',
            icone: LucideIcons.arrowRight,
            taille: TailleBouton.sm,
            variante: VarianteBouton.secondaire,
            onPressed: () => c.aller(f.ecran)),
      ]));

  Widget _bloc(ContexteEcran c, String titre, String detail, String ecran, {required bool attention}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: attention ? JetonsShell.warning50 : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: attention ? JetonsShell.warning200 : JetonsShell.slate200)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titre,
              style: const TextStyle(
                  color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500)),
          Text(detail,
              style: TextStyle(
                  color: attention ? JetonsShell.slate600 : JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
        ])),
        const SizedBox(width: 12),
        BoutonSigh(
            libelle: 'Ouvrir',
            icone: LucideIcons.arrowRight,
            taille: TailleBouton.sm,
            variante: VarianteBouton.secondaire,
            onPressed: () => c.aller(ecran)),
      ]));
}
