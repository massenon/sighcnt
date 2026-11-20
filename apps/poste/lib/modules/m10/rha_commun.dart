import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import '../../impression/piece.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../m4/mat_commun.dart';

/// Briques communes aux écrans RH du premier lot (M10) : mise en page seulement — les règles chiffrées vivent dans
/// `packages/domaine/lib/src/rh/rha_regles.dart`.

const Signature rhaSignDa = Signature('La Directrice Administrative', nom: 'TAKI Alimatou');

/// Un indicateur du domaine devient une carte (`U.kpiGrid`) ; les icônes viennent de la déclaration de l'écran, dans l'ordre des indicateurs.
List<KpiSigh> rhaKpisW(List<RhaKpi> kpis, List<IconData> icones) => [
      for (final (i, k) in kpis.indexed)
        KpiSigh(libelle: k.libelle, valeur: k.valeur, indice: k.indice, icone: icones[i], ton: matTon(k.ton)),
    ];

/// Les agents ACTIFS, triés par nom complet (`C.sortBy(personnel(), 'nomComplet')`).
List<Fiche> rhaAgents(Magasin m) => trierPar(m.collection('personnel').actives, (e) => e['nomComplet']);

/// `optionsEmployes()` : « matricule — nom (poste) ».
List<OptionChamp> rhaOptionsEmployes(Magasin m) => [
      for (final e in rhaAgents(m)) OptionChamp('${e['id']}', '${e['matricule']} — ${e['nomComplet']} (${e['poste']})'),
    ];

List<OptionChamp> rhaOptionsFonctions() => [for (final e in admFonctions.entries) OptionChamp(e.key, e.value)];

List<OptionChamp> rhaOptions(Iterable<String> l) => [for (final x in l) OptionChamp(x)];

Fiche? rhaAgentPar(Magasin m, Object? id) {
  for (final e in m.collection('personnel').actives) {
    if (e['id'] == id) return e;
  }
  return null;
}

/// Deux cartes côte à côte au-delà de 1024 px (`K.charts`), trois au-delà de 1024 px quand la maquette en met trois (`lg:grid-cols-3`).
Widget rhaCartes(List<Widget> cartes, {int colonnes = 2}) => LayoutBuilder(builder: (_, k) {
      final n = k.maxWidth >= 1024 ? colonnes : 1;
      final l = (k.maxWidth - 16 * (n - 1)) / n;
      return Wrap(spacing: 16, runSpacing: 16, children: [for (final c in cartes) SizedBox(width: l, child: c)]);
    });

/// `K.ranking` : barres horizontales, libellé et valeur en chiffres groupés ; `rouge` colore la barre (prestataire sans facture normalisée).
class RhaClassement extends StatelessWidget {
  const RhaClassement(this.lignes, {super.key, this.vide = 'Aucune donnée.', this.argent = false});
  final List<({String libelle, num valeur, bool rouge})> lignes;
  final String vide;

  /// Valeurs en FCFA (`format: C.money(v, false)`) plutôt qu'en nombres entiers.
  final bool argent;

  @override
  Widget build(BuildContext context) {
    if (lignes.isEmpty) return VideSigh(vide);
    final max = lignes.fold<num>(0, (a, l) => l.valeur > a ? l.valeur : a);
    return Column(children: [
      for (final l in lignes)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(l.libelle,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14))),
              Text(argent ? money(l.valeur, avecDevise: false) : nombre(l.valeur),
                  style: const TextStyle(
                      color: JetonsShell.slate700, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                    value: max == 0 ? 0 : (l.valeur / max).toDouble(),
                    minHeight: 8,
                    backgroundColor: JetonsShell.slate100,
                    valueColor: AlwaysStoppedAnimation(l.rouge ? JetonsShell.danger600 : JetonsShell.navy600))),
          ]),
        ),
    ]);
  }
}

Widget rhaTexteMuet(String t) => Text(t, style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12));

/// Les nombres saisis arrivent en texte : « 150000 » → 150000 ; vide → 0.
num rhaNombreSaisi(Object? v) => rhaNum(v);

/// Un état A4 « Rubrique / valeur » à deux colonnes.
BlocPiece rhaBlocRubriques(List<(String, String)> l, {String col2 = 'Information', bool droiteValeur = false}) => BlocTableau(TableauEtat(colonnes: [
      ColonneEtat(libelle: 'Rubrique', valeur: (x) => x['k']),
      ColonneEtat(libelle: col2, valeur: (x) => x['v'], droite: droiteValeur),
    ], lignes: [
      for (final x in l) {'k': x.$1, 'v': x.$2}
    ]));

/// Le badge d'un code (`U.statut`) : libellé et ton du référentiel de la maquette.
Widget rhaBadgeStatut(Object? code) {
  final s = rhaStatutBadge(code);
  return BadgeSigh(s.$1, ton: matTon(s.$2));
}
