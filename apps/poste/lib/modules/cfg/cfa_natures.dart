import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cfa_commun.dart';

/// `cfg-natures-facture` — « Natures de facture » : la liste des natures proposées à l'émission, administrable. En ajouter une la rend IMMÉDIATEMENT
/// disponible à l'émission, sans intervention sur le logiciel (l'option « Ajouter » demandée par la Direction). Archivage annulable (RG-14).
class EcranNaturesFacture extends StatelessWidget with EcranMaquette {
  const EcranNaturesFacture({super.key});
  @override
  String get titre => 'Natures de facture';
  @override
  String get description => 'Liste des natures proposées à l’émission d’une facture, administrable par la clinique.';
  @override
  String get regle =>
      'La caisse choisit la nature d’une facture dans cette liste. En ajouter une ici la rend immédiatement disponible à l’émission, sans intervention sur le logiciel — c’est l’option « Ajouter » demandée par la Direction.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(libelle: 'Émettre une facture', icone: LucideIcons.receipt, onPressed: () => c.aller('m8-facturation')),
      BoutonSigh(libelle: 'Référentiel tarifaire', icone: LucideIcons.tag, variante: VarianteBouton.secondaire, onPressed: () => c.aller('cfg-tarifs')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('naturesFacture');
    final secteurs = cfaSecteursActivite(c.magasin);
    return ListenableBuilder(
        listenable: col,
        builder: (ctx, _) {
          final rows = col.actives;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            cfaLectureSeule(c),
            cfaKpis(cfaKpisNatures(natures: rows.length, secteurs: cfaDistincts(rows, 'secteur').length, archivees: col.archivees.length)),
            const SizedBox(height: 16),
            CfaTableau(
              collection: 'naturesFacture',
              titre: 'Natures proposées à l’émission',
              entite: 'Nature',
              libelleNouveau: 'Nouveau',
              titreCreation: 'Nouvelle nature de facture',
              prefixeId: 'NAT',
              taillePage: 20,
              triInitial: 'ordre',
              nomExport: 'natures-facture',
              filtres: [FiltreTableau(nom: 'secteur', libelle: 'Secteur', options: [for (final s in cfaDistincts(rows, 'secteur')) OptionChamp(s)])],
              colonnes: [
                ColonneTableau(cle: 'code', libelle: 'Code', sansCoupure: true, texte: (n) => '${n['code'] ?? ''}', rendu: (_, n) => cfaCode(n['code'])),
                ColonneTableau(cle: 'libelle', libelle: 'Nature', texte: (n) => '${n['libelle'] ?? ''}', rendu: (_, n) => cfaGras('${n['libelle'] ?? ''}')),
                ColonneTableau(cle: 'secteur', libelle: 'Secteur émetteur', texte: (n) => '${n['secteur'] ?? ''}', rendu: (_, n) => BadgeSigh('${n['secteur'] ?? ''}', ton: TonSigh.navy)),
                ColonneTableau(
                    cle: 'source',
                    libelle: 'Origine',
                    texte: (n) => cfaOuTiret(n['source']),
                    rendu: (_, n) => Text(cfaOuTiret(n['source']), style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500))),
              ],
              champs: (e) => [
                const ChampDef(nom: 'libelle', libelle: 'Nature de la facture', requis: true, col: ColChamp.plein),
                const ChampDef(nom: 'code', libelle: 'Code', aide: 'Quatre lettres, laisser vide pour une attribution automatique.'),
                ChampDef(nom: 'secteur', libelle: 'Secteur émetteur', type: TypeChamp.select, requis: true, options: [for (final s in secteurs) OptionChamp(s)]),
                const ChampDef(nom: 'source', libelle: 'Origine', col: ColChamp.plein),
              ],
              valeursInitiales: () => {'secteur': secteurs.isEmpty ? '' : secteurs.first, 'source': 'Décision de la Direction'},
              fiche: (s, e) => e == null ? cfaFicheNature(s, col.toutes.length) : {...s},
            ),
          ]);
        });
  }
}
