import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cfa_commun.dart';

/// `cfg-centres-couts` — « Centres de coûts » : les axes d'imputation analytique des écritures, administrables. Chaque écriture peut être imputée à un
/// centre ; la liste se complète ici ou depuis la saisie des écritures. Archivage annulable (RG-14) ; commandes d'écriture ABSENTES sans le droit.
class EcranCentresCouts extends StatelessWidget with EcranMaquette {
  const EcranCentresCouts({super.key});
  @override
  String get titre => 'Centres de coûts';
  @override
  String get description => 'Axes d’imputation analytique des écritures comptables, administrables par la clinique.';
  @override
  String get regle =>
      'Chaque écriture peut être imputée à un centre de coûts : c’est ce qui permet de mesurer ce que coûte et ce que rapporte chaque service. La liste se complète ici — ou directement depuis la saisie des écritures, sans quitter l’écran.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(libelle: 'Saisie des écritures', icone: LucideIcons.pencilLine, onPressed: () => c.aller('m12-ecritures')),
      BoutonSigh(libelle: 'Comptabilité analytique', icone: LucideIcons.chartPie, variante: VarianteBouton.secondaire, onPressed: () => c.aller('m12-analytique')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('centresCouts');
    return ListenableBuilder(
        listenable: col,
        builder: (ctx, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              cfaLectureSeule(c),
              cfaKpis(cfbKpisCentres(col.actives)),
              const SizedBox(height: 16),
              CfaTableau(
                collection: 'centresCouts',
                titre: 'Axes analytiques',
                entite: 'Centre',
                libelleNouveau: 'Nouveau',
                titreCreation: 'Nouveau centre de coûts',
                prefixeId: 'CC',
                taillePage: 20,
                triInitial: 'code',
                nomExport: 'centres-couts',
                filtres: const [
                  FiltreTableau(nom: 'type', libelle: 'Type', options: [OptionChamp('exploitation', 'Exploitation'), OptionChamp('support', 'Support')])
                ],
                colonnes: [
                  ColonneTableau(cle: 'code', libelle: 'Code', sansCoupure: true, texte: (x) => '${x['code'] ?? ''}', rendu: (_, x) => cfaCode(x['code'])),
                  ColonneTableau(cle: 'libelle', libelle: 'Centre', texte: (x) => '${x['libelle'] ?? ''}', rendu: (_, x) => cfaGras('${x['libelle'] ?? ''}')),
                  ColonneTableau(
                      cle: 'type',
                      libelle: 'Type',
                      texte: (x) => x['type'] == 'support' ? 'Support' : 'Exploitation',
                      rendu: (_, x) => x['type'] == 'support' ? const BadgeSigh('Support', ton: TonSigh.info) : const BadgeSigh('Exploitation', ton: TonSigh.succes)),
                  ColonneTableau(
                      cle: 'responsable',
                      libelle: 'Responsable',
                      texte: (x) => cfaVrai(x['responsable']) ? '${x['responsable']}' : 'non désigné',
                      rendu: (_, x) => cfaVrai(x['responsable'])
                          ? Text('${x['responsable']}', style: const TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate700))
                          : const Text('non désigné', style: TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate300))),
                ],
                champs: (e) => const [
                  ChampDef(nom: 'libelle', libelle: 'Intitulé du centre', requis: true, col: ColChamp.plein),
                  ChampDef(nom: 'code', libelle: 'Code', aide: 'Laisser vide pour une attribution automatique.'),
                  ChampDef(
                      nom: 'type',
                      libelle: 'Type',
                      type: TypeChamp.select,
                      requis: true,
                      options: [OptionChamp('exploitation', 'Centre d’exploitation'), OptionChamp('support', 'Centre de support')]),
                  ChampDef(nom: 'responsable', libelle: 'Responsable', col: ColChamp.plein),
                  ChampDef(nom: 'source', libelle: 'Origine', col: ColChamp.plein),
                ],
                valeursInitiales: () => {'type': 'exploitation', 'source': 'Décision de la Direction'},
                fiche: (s, e) => e == null ? cfbFicheCentre(s, col.toutes.length) : {...s},
              ),
            ]));
  }
}
