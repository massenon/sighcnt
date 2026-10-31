import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cfa_commun.dart';

/// `cfg-imagerie-catalogue` — « Catalogue de l'imagerie » : les examens et les variables de leurs comptes rendus vivent AU MAGASIN (la doctrine du laboratoire
/// appliquée à l'imagerie), administrables. Une variable se FERME sans se supprimer : les comptes rendus déjà rendus la conservent. La modalité est une
/// propriété de l'EXAMEN (échographie, radiographie, mammographie, scanner, IRM) : c'est le catalogue qui range l'examen dans son tableau, jamais le compte rendu.
/// « Annexes » et « Conclusion » ne se paramètrent pas : texte libre, « à remplir par moi-même », écrit de la main de l'échographiste.
class EcranImagerieCatalogue extends StatelessWidget with EcranMaquette {
  const EcranImagerieCatalogue({super.key});
  @override
  String get titre => 'Catalogue de l’imagerie';
  @override
  String get description => 'Examens d’imagerie et variables de leurs comptes rendus : listes de choix, mesures, rubriques.';
  @override
  String get regle =>
      'Les listes pré-insérées viennent du brouillon manuscrit de l’échographiste et des cinq comptes rendus réels. Une variable se ferme sans se supprimer : les comptes rendus déjà rendus la conservent. « Annexes » et « Conclusion » ne se paramètrent pas : elles restent en texte libre — « à remplir par moi-même », écrit de sa main.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final examens = c.magasin.collection('examensImagerie');
    final variables = c.magasin.collection('variablesImagerie');
    return ListenableBuilder(
        listenable: Listenable.merge([examens, variables]),
        builder: (ctx, _) {
          final vars = variables.actives;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            cfaLectureSeule(c),
            cfaKpis(cfaKpisImagerie(
                examens: examens.actives.length,
                variables: vars.length,
                fermees: vars.where((v) => v['actif'] == false).length,
                listes: vars.where((v) => v['type'] == 'liste' || v['type'] == 'binaire').length)),
            const SizedBox(height: 16),
            OngletsSigh(onglets: [
              OngletDef(id: 'examens', libelle: 'Examens', compte: examens.actives.length, construire: (_) => const _OngletExamens()),
              OngletDef(id: 'variables', libelle: 'Variables', compte: vars.length, construire: (_) => const _OngletVariables()),
            ]),
          ]);
        });
  }
}

class _OngletExamens extends StatelessWidget {
  const _OngletExamens();

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final variables = c.magasin.collection('variablesImagerie');
    return CfaTableau(
      collection: 'examensImagerie',
      entite: 'Examen',
      libelleNouveau: 'Nouvel examen',
      titreCreation: 'Examen d’imagerie',
      prefixeId: 'EXI',
      taillePage: 10,
      messageVide: 'Aucun examen au catalogue.',
      nomExport: 'imagerie-examens',
      colonnes: [
        ColonneTableau(cle: 'code', libelle: 'Code', texte: (x) => '${x['code'] ?? ''}', rendu: (_, x) => cfaCode(x['code'])),
        const ColonneTableau(cle: 'label', libelle: 'Intitulé'),
        ColonneTableau(cle: 'modalite', libelle: 'Modalité', valeur: (x) => _modalite(x), texte: (x) => _modalite(x)),
        ColonneTableau(
            cle: 'aValider',
            libelle: 'Origine',
            valeur: (x) => cfaVrai(x['aValider']) ? 'Proposition à valider' : 'Documentée',
            texte: (x) => cfaVrai(x['aValider']) ? 'Proposition à valider' : 'Documentée',
            rendu: (_, x) => cfaVrai(x['aValider']) ? const BadgeSigh('Proposition à valider', ton: TonSigh.attention) : const BadgeSigh('Documentée', ton: TonSigh.succes)),
        ColonneTableau(cle: 'voie', libelle: 'Voie d’abord', texte: (x) => cfaOuTiret(x['voie'])),
        ColonneTableau(
            cle: 'variables',
            libelle: 'Variables',
            droite: true,
            valeur: (x) => variables.actives.where((v) => v['examen'] == x['code']).length,
            texte: (x) => '${variables.actives.where((v) => v['examen'] == x['code']).length}'),
      ],
      champs: (e) => [
        const ChampDef(nom: 'code', libelle: 'Code', requis: true, aide: 'Aligné sur le code du référentiel tarifaire : un examen est un acte facturable.'),
        const ChampDef(nom: 'label', libelle: 'Intitulé', requis: true, col: ColChamp.plein),
        // La modalité range l'examen dans SON tableau : c'est le catalogue qui en décide, jamais le compte rendu.
        ChampDef(nom: 'modalite', libelle: 'Modalité', type: TypeChamp.select, requis: true, options: [for (final m in modalitesImagerie) OptionChamp(m.code, m.label)]),
        const ChampDef(nom: 'voie', libelle: 'Voie d’abord', aide: 'sus-pubienne, transpariétale…'),
        const ChampDef(nom: 'tarifCode', libelle: 'Code tarifaire (si différent)', aide: 'L’obstétricale du 1er trimestre se facture comme l’obstétricale.'),
      ],
      fiche: (s, e) => {...s},
      titreDetail: (x) => '${x['label']}',
    );
  }

  static String _modalite(Fiche x) => modaliteOuInconnue(modaliteDeExamen(x)).label;
}

class _OngletVariables extends StatelessWidget {
  const _OngletVariables();

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final examens = c.magasin.collection('examensImagerie');
    final col = c.magasin.collection('variablesImagerie');
    String libelleType(Object? code) => cfaTypesVariableImagerie.where((t) => t.$1 == code).map((t) => t.$2).firstOrNull ?? '$code';
    return CfaTableau(
      collection: 'variablesImagerie',
      entite: 'Variable',
      libelleNouveau: 'Nouvelle variable',
      titreCreation: 'Variable de compte rendu',
      prefixeId: 'VIM',
      taillePage: 15,
      messageVide: 'Aucune variable paramétrée.',
      nomExport: 'imagerie-variables',
      colonnes: [
        ColonneTableau(
            cle: 'examen',
            libelle: 'Examen',
            texte: (v) => '${examens.actives.where((x) => x['code'] == v['examen']).map((x) => x['label']).firstOrNull ?? v['examen']} ${v['rubrique'] ?? ''}',
            rendu: (_, v) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('${examens.actives.where((x) => x['code'] == v['examen']).map((x) => x['label']).firstOrNull ?? v['examen']}',
                      overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate700)),
                  Text('${v['rubrique'] ?? ''}', style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate400)),
                ])),
        const ColonneTableau(cle: 'libelle', libelle: 'Variable'),
        ColonneTableau(cle: 'type', libelle: 'Type', texte: (v) => libelleType(v['type']), rendu: (_, v) => BadgeSigh(libelleType(v['type']), ton: TonSigh.info)),
        ColonneTableau(
            cle: 'options',
            libelle: 'Choix / unité',
            texte: (v) => v['options'] is List && (v['options'] as List).isNotEmpty ? (v['options'] as List).join(' · ') : cfaOuTiret(v['unite']),
            rendu: (_, v) => v['options'] is List && (v['options'] as List).isNotEmpty
                ? Text((v['options'] as List).join(' · '), style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate600))
                : Text(cfaOuTiret(v['unite']), style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 12, height: 16 / 12, color: JetonsShell.slate500))),
        ColonneTableau(
            cle: 'actif',
            libelle: 'État',
            droite: true,
            texte: (v) => v['actif'] == false ? 'Fermée' : 'Active',
            rendu: (_, v) => v['actif'] == false ? const BadgeSigh('Fermée') : const BadgeSigh('Active', ton: TonSigh.succes)),
      ],
      champs: (e) => [
        ChampDef(
            nom: 'examen',
            libelle: 'Examen',
            type: TypeChamp.select,
            requis: true,
            col: ColChamp.plein,
            options: [for (final x in examens.actives) OptionChamp('${x['code']}', '${x['label']}')]),
        const ChampDef(nom: 'code', libelle: 'Code de la variable', requis: true),
        const ChampDef(nom: 'libelle', libelle: 'Intitulé', requis: true, col: ColChamp.plein),
        ChampDef(nom: 'type', libelle: 'Type', type: TypeChamp.select, requis: true, options: [for (final t in cfaTypesVariableImagerie) OptionChamp(t.$1, t.$2)]),
        const ChampDef(nom: 'optionsTexte', libelle: 'Choix proposés (séparés par |)', col: ColChamp.plein, aide: 'Pour une liste ou un binaire — par exemple « homogène|hétérogène ».'),
        const ChampDef(nom: 'unite', libelle: 'Unité', aide: 'mm, g, ml… pour une mesure.'),
        const ChampDef(nom: 'rubrique', libelle: 'Rubrique du compte rendu', requis: true),
        const ChampDef(nom: 'normal', libelle: 'Valeur normale attendue', aide: 'Ce qui s’en écarte est mis en gras sur la pièce.'),
        const ChampDef(nom: 'ordre', libelle: 'Rang de rendu', type: TypeChamp.nombre, requis: true),
      ],
      // À l'édition, les choix se relisent dans le champ texte : le formulaire est prérempli depuis la fiche.
      preparer: (v) => {...v, 'optionsTexte': cfaOptionsTexte(v)},
      fiche: (s, e) => cfaTransformVariableImagerie(s),
      taille: TailleModale.lg,
      titreDetail: (v) => '${v['libelle']}',
      // Fermer une variable la retire des comptes rendus à venir sans toucher à ceux déjà rendus : c'est un geste d'écriture, ABSENT sans le droit.
      actionsLigneApres: (ctx, v) => [
        if (c.droit.editer)
          BoutonIcone(
              icone: v['actif'] == false ? LucideIcons.eye : LucideIcons.eyeOff,
              libelle: v['actif'] == false ? 'Rouvrir la variable' : 'Fermer la variable',
              onPressed: () {
                // L'état se lit AVANT l'écriture (écart E845).
                final etaitFermee = v['actif'] == false;
                col.mettreAJour(v['id'], {'actif': etaitFermee});
                final m = cfaMessageBascule(etaitFermee: etaitFermee);
                ToastsSigh.afficher(ctx, m.message, type: TypeToast.succes, detail: m.detail);
              }),
      ],
    );
  }
}
