import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/flux_commun.dart' show SourceFlux;
import '../m6/stock_crud.dart';
import 'cat_commun.dart';

Widget _provenance(Map<String, Object?> u) => catProvenanceUnite(u) == 'à confirmer'
    ? const BadgeSigh('À confirmer', ton: TonSigh.attention)
    : Text(catSourceUnite(u), style: styleCat(taille: 12, couleur: JetonsShell.slate500));

/// `m5-unites` — « Unités de mesure » : les unités dans lesquelles les résultats s'expriment, pré-insérées pour que le laboratoire n'ait pas à les
/// ressaisir. Les symboles sont ceux de la FICHE de résultats de la clinique (« G/l », « T/l », « g/dl »), jamais les notations normalisées : le
/// laboratoire lit ce qu'il écrit. Création et modification en modale, archivage annulable (RG-14).
class EcranUnitesLabo extends StatelessWidget with EcranMaquette {
  const EcranUnitesLabo({super.key});

  @override
  String get titre => 'Unités de mesure';

  @override
  String get description =>
      'Unités dans lesquelles les résultats s’expriment, pré-insérées pour que le laboratoire n’ait pas à les ressaisir.';

  @override
  String get regle =>
      'Les symboles sont ceux de la fiche de résultats de la clinique — « G/l », « T/l », « g/dl » — et non les notations normalisées 10⁹/L ou g/L. Le laboratoire lit ce qu’il écrit : lui imposer une autre notation, plus « correcte », l’obligerait à traduire à chaque lecture.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CrudStock(
        collection: c.magasin.collection('unitesLabo'),
        entite: 'unité',
        entiteP: 'unités',
        prefixeId: 'UNI',
        taillePage: 25,
        triInitial: 'domaine',
        colonnes: [
          ColonneTableau(
              cle: 'symbole',
              libelle: 'Symbole',
              sansCoupure: true,
              texte: (u) => '${u['symbole'] ?? ''}',
              rendu: (_, u) => Text('${u['symbole'] ?? ''}',
                  style: monoCode.copyWith(fontSize: 14, height: 20 / 14))),
          const ColonneTableau(cle: 'libelle', libelle: 'Intitulé'),
          ColonneTableau(
              cle: 'domaine',
              libelle: 'Domaine',
              texte: (u) => '${u['domaine'] ?? ''}',
              rendu: (_, u) => BadgeSigh('${u['domaine'] ?? ''}', ton: TonSigh.navy)),
          ColonneTableau(
              cle: 'aValider',
              libelle: 'Provenance',
              texte: catProvenanceUnite,
              valeur: catProvenanceUnite,
              rendu: (_, u) => _provenance(u)),
        ],
        filtres: [
          FiltreTableau(
              nom: 'domaine',
              libelle: 'Domaine',
              options: [for (final d in catDomainesUnite) OptionChamp(d)]),
        ],
        kpis: (ctx, rows) {
          final k = catKpisUnites(rows);
          return [
            KpiSigh(
                libelle: 'Unités paramétrées',
                valeur: nombre(k.unites),
                icone: LucideIcons.ruler),
            KpiSigh(
                libelle: 'Reprises de la fiche',
                valeur: nombre(k.reprises),
                icone: LucideIcons.fileCheck2,
                ton: TonSigh.succes),
            KpiSigh(
                libelle: 'À confirmer',
                valeur: nombre(k.aConfirmer),
                icone: LucideIcons.circleHelp,
                ton: TonSigh.attention),
            KpiSigh(
                libelle: 'Domaines couverts',
                valeur: nombre(k.domaines),
                icone: LucideIcons.layers,
                ton: TonSigh.info),
          ];
        },
        champs: (m) => [
          const ChampDef(
              nom: 'symbole',
              libelle: 'Symbole',
              requis: true,
              aide: 'Tel qu’il s’imprime sur la fiche de résultats'),
          const ChampDef(
              nom: 'libelle',
              libelle: 'Intitulé complet',
              requis: true,
              col: ColChamp.plein),
          ChampDef(
              nom: 'domaine',
              libelle: 'Domaine',
              type: TypeChamp.select,
              requis: true,
              options: [for (final d in catDomainesUnite) OptionChamp(d)]),
        ],
        valeursInitiales: () => {},
        transformer: (_, v) => {...v},
        detail: (ctx, u) => DescListeSigh([
          ('Symbole', Text('${u['symbole'] ?? ''}', style: monoCode.copyWith(fontSize: 14, height: 20 / 14))),
          ('Intitulé', '${u['libelle'] ?? ''}'),
          ('Domaine', BadgeSigh('${u['domaine'] ?? ''}', ton: TonSigh.navy)),
          ('Provenance', _provenance(u)),
        ]),
        titreDetail: (u) => '${u['libelle'] ?? ''}',
        sousTitreDetail: null,
      ),
      const SourceFlux(sourceParametrageLabo),
    ]);
  }
}
