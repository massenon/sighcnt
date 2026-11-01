import 'dart:convert';

/// Une rubrique interne d'un écran (`N.RUBRIQUES` de la maquette) : la recherche globale ouvre la page ET l'onglet visé.
class RubriqueRecherche {
  const RubriqueRecherche({required this.ecran, required this.onglet, required this.label, required this.motsCles});
  final String ecran;
  final String? onglet;
  final String label, motsCles;
}

/// Une entrée du menu « Actions » (`N.ACTIONS_RAPIDES`) : libellé, icône, écran.
class ActionRapideBarre {
  const ActionRapideBarre({required this.libelle, required this.icone, required this.ecran});
  final String libelle, icone, ecran;
}

/// Ce que la barre supérieure lit au manifeste en plus des écrans : les rubriques de la recherche globale et les actions rapides. ENGENDRÉ par
/// `prototype_html/build/extraire-rubriques.js` (source : `nav.js`), jamais écrit à la main.
class ReferentielBarre {
  const ReferentielBarre({this.rubriques = const [], this.actions = const []});
  final List<RubriqueRecherche> rubriques;
  final List<ActionRapideBarre> actions;

  factory ReferentielBarre.depuisJson(String json) {
    final j = (jsonDecode(json) as Map).cast<String, Object?>();
    return ReferentielBarre(
      rubriques: [
        for (final r in (j['rubriques'] as List))
          RubriqueRecherche(
              ecran: '${(r as Map)['ecran']}', onglet: r['onglet'] == null ? null : '${r['onglet']}', label: '${r['label']}', motsCles: '${r['motsCles'] ?? ''}')
      ],
      actions: [
        for (final a in (j['actionsRapides'] as List))
          ActionRapideBarre(libelle: '${(a as Map)['libelle']}', icone: '${a['icone']}', ecran: '${a['ecran']}')
      ],
    );
  }
}
