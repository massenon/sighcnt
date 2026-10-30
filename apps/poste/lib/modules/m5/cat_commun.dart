import 'package:flutter/material.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../shell/contexte_ecran.dart';

/// Éléments communs aux écrans de paramétrage du laboratoire (`cat_*.dart`) : le catalogue des analyses, les unités, les valeurs de référence et les
/// réactifs. Les RÈGLES (références, plages par lot, provenances, seuils, bon de demande) sont dans `packages/domaine/lib/src/labo/cat_regles.dart`,
/// rejouées sur les vecteurs de la maquette ; ces fichiers ne font que les mettre en page.

/// Le Laborantin chef et la Directrice Administrative signent les états du catalogue et du bon de réactifs, comme dans `m5-laboratoire.js`.
const laborantinChef = 'KINNOU Addoul Ganiou';
const directriceAdministrativeLabo = 'TAKI Alimatou';
const gestionnaireStockLabo = 'MAMAN Zoukanéri';
const directeurMedicalLabo = 'BASSONGUI Chabi Séko';

/// Source du paramétrage (`L.source`), citée au pied des écrans qui en tirent leurs valeurs.
const sourceParametrageLabo =
    'Bulletin d’analyses bio-médicales (formulaire papier) et fiche de résultats du dossier 2026080411, éditée le 21/08/2026.';

final Expando<CollectionMagasin> _analyses = Expando('analyses');

/// La collection `analyses` (le catalogue des 48 désignations de la clinique). Le jeu du poste porte le catalogue comme RÉFÉRENTIEL
/// (`referentiels.json › analyses`) et non comme collection : tant que la collection est vide, elle est amorcée UNE fois depuis le référentiel,
/// à l'image de `store.seed()` — sans écrire une seule ligne au journal (RG-12 : un amorçage n'est pas un geste d'agent). Le jour où le jeu portera
/// la collection, c'est elle qui sera lue.
CollectionMagasin collectionAnalyses(Magasin m) {
  final reelle = m.collection('analyses');
  if (reelle.toutes.isNotEmpty) return reelle;
  return _analyses[m] ??= CollectionMagasin('analyses', m.referentiel('analyses'),
      journal: m.journaliser, module: 'M5');
}

/// Police fixe des codes (`font-mono`).
const monoCode = TextStyle(
    fontFamily: 'LiberationMono',
    color: JetonsShell.navy800,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600);

TextStyle styleCat(
        {double taille = 14,
        Color couleur = JetonsShell.slate700,
        FontWeight poids = FontWeight.w400}) =>
    TextStyle(
        color: couleur,
        fontSize: taille,
        height: taille == 14 ? 20 / 14 : (taille == 12 ? 16 / 12 : 15 / taille),
        fontWeight: poids,
        fontFeatures: const [FontFeature.tabularFigures()]);

/// La pièce A4 d'un état du laboratoire (la mise en page est celle de `P.etat`).
PieceA4 pieceCat(BuildContext ctx,
    {required String titre,
    String? sousTitre,
    List<(String, String)> cartouche = const [],
    List<(String, String)> filtres = const [],
    required List<BlocPiece> blocs,
    required List<Signature> signatures}) {
  final c = ContexteEcran.of(ctx);
  return PieceA4(
    titre: titre,
    sousTitre: sousTitre,
    cartouche: cartouche,
    filtres: filtres,
    blocs: blocs,
    signatures: signatures,
    reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
    utilisateur: c.utilisateur,
    edite: c.aujourdhui,
  );
}

/// Trois cartes côte à côte au-delà de 1024 px (`lg:grid-cols-3`), empilées en dessous.
Widget troisColonnes(List<Widget> cartes) => LayoutBuilder(builder: (_, k) {
      final l = k.maxWidth >= 1024 ? (k.maxWidth - 32) / 3 : k.maxWidth;
      return Wrap(spacing: 16, runSpacing: 16, children: [
        for (final c in cartes) SizedBox(width: l, child: c)
      ]);
    });

/// Deux cartes côte à côte au-delà de 768 px (`md:grid-cols-2`), empilées en dessous.
Widget deuxColonnesMd(List<Widget> cartes) => LayoutBuilder(builder: (_, k) {
      final l = k.maxWidth >= 768 ? (k.maxWidth - 16) / 2 : k.maxWidth;
      return Wrap(spacing: 16, runSpacing: 16, children: [
        for (final c in cartes) SizedBox(width: l, child: c)
      ]);
    });

/// `K.ranking` : un classement en barres fines — libellé et valeur sur une ligne, puis la barre (largeur proportionnelle au maximum, 2 % au moins).
/// [tons] : la teinte de chaque barre (navy par défaut, danger pour une référence sous son seuil).
class ClassementCat extends StatelessWidget {
  const ClassementCat(
      {super.key, required this.lignes, required this.format});

  /// (libellé, valeur, teinte) — la teinte `danger` ou `navy`.
  final List<({String libelle, num valeur, bool alerte})> lignes;
  final String Function(num) format;

  @override
  Widget build(BuildContext context) {
    final max = lignes.fold<num>(1, (a, l) => l.valeur > a ? l.valeur : a);
    return Column(key: const Key('cat:classement'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < lignes.length; i++) ...[
        if (i > 0) const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Expanded(
              child: Text(lignes[i].libelle,
                  overflow: TextOverflow.ellipsis,
                  style: styleCat())),
          const SizedBox(width: 12),
          Text(format(lignes[i].valeur),
              style: styleCat(couleur: JetonsShell.slate900, poids: FontWeight.w600)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
            borderRadius: BorderRadius.circular(9999),
            child: Container(
                key: Key('cat:barre:${lignes[i].alerte ? 'danger' : 'navy'}'),
                height: 6,
                color: JetonsShell.slate100,
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                    widthFactor: ((lignes[i].valeur / max * 100).round().clamp(2, 100)) / 100,
                    child: Container(
                        color: lignes[i].alerte
                            ? JetonsShell.danger500
                            : JetonsShell.navy500)))),
      ],
    ]);
  }
}
