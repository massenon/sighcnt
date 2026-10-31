import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

export '../m8/commun.dart' show n, m, dateDe;

/// Briques communes aux dix écrans de M9 (assurances, créances & relances).
/// Les règles chiffrées vivent dans `packages/domaine/lib/src/assurances/ass_regles.dart` ; ce fichier ne porte que de la mise en page.

const mono = TextStyle(
    fontFamily: 'LiberationMono',
    color: JetonsShell.slate800,
    fontSize: 12,
    height: 16 / 12);

Text monoTexte(Object? v, {Color? couleur, FontWeight? poids}) => Text('${v ?? ''}',
    style: mono.copyWith(color: couleur, fontWeight: poids));

Widget tiret() => const Text('—',
    style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12));

/// Les collections que M9 lit : un écran se redessine quand l'une d'elles bouge (une facture réglée, une couverture changée…).
Listenable ecoute(ContexteEcran c, List<String> noms) =>
    Listenable.merge([for (final n in noms) c.magasin.collection(n)]);

List<Fiche> actives(ContexteEcran c, String nom) => c.magasin.collection(nom).actives;

/// La validité de la carte se lit AU MOTEUR (couverture datée, RG-09) — l'écran n'en garde pas de copie.
bool carteValideLe(ContexteEcran c, Fiche p, [DateTime? date]) => carteValide(
    p, actives(c, 'couverturesAssurance'), iso(date ?? c.aujourdhui));

/// `K.charts` : deux cartes côte à côte au-delà de 1024 px.
Widget deuxCartes(Widget a, Widget b) => LayoutBuilder(builder: (_, k) {
      final l = k.maxWidth >= 1024 ? (k.maxWidth - 16) / 2 : k.maxWidth;
      return Wrap(spacing: 16, runSpacing: 16, children: [
        SizedBox(width: l, child: a),
        SizedBox(width: l, child: b)
      ]);
    });

/// `K.ranking` : un classement en barres horizontales (libellé, valeur formatée).
class ClassementSigh extends StatelessWidget {
  const ClassementSigh(this.lignes, {super.key, this.ton = JetonsShell.navy600});
  final List<({String libelle, num valeur})> lignes;
  final Color ton;

  @override
  Widget build(BuildContext context) {
    if (lignes.isEmpty) return const VideSigh('Aucune donnée.');
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
                      style: const TextStyle(
                          color: JetonsShell.slate700, fontSize: 14, height: 20 / 14))),
              Text(money(l.valeur, avecDevise: false),
                  style: const TextStyle(
                      color: JetonsShell.slate700,
                      fontSize: 14,
                      height: 20 / 14,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                    value: max == 0 ? 0 : (l.valeur / max).toDouble(),
                    minHeight: 8,
                    backgroundColor: JetonsShell.slate100,
                    color: ton)),
          ]),
        ),
    ]);
  }
}

/// La pièce A4 d'un état de M9 (en-tête officiel, pied normalisé : date, utilisateur, identifiant).
PieceA4 pieceM9(ContexteEcran c,
        {required String titre,
        String? sousTitre,
        List<(String, String)> cartouche = const [],
        List<TableauEtat> tableaux = const [],
        List<BlocPiece> blocs = const [],
        List<Signature> signatures = const []}) =>
    PieceA4(
        titre: titre,
        sousTitre: sousTitre,
        reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
        utilisateur: c.utilisateur,
        edite: c.aujourdhui,
        cartouche: cartouche,
        tableaux: tableaux,
        blocs: blocs,
        signatures: signatures);

const signDaf = Signature('La Directrice Administrative', nom: 'TAKI Alimatou');

/// Pastille de ton selon l'état d'une carte.
Widget badgeValidite(String texte, bool valide) =>
    BadgeSigh(texte, ton: !valide ? TonSigh.danger : (texte == 'Valide' ? TonSigh.succes : TonSigh.attention));

Widget montantFort(num v, {Color couleur = JetonsShell.warning700}) => Text(
    money(v, avecDevise: false),
    style: TextStyle(
        color: couleur,
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()]));

const iconeBouton = LucideIcons.printer;
