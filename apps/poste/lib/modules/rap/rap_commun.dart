import 'package:flutter/material.dart';

import '../../core/jetons_shell.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

/// Ce que partagent les quatre écrans de RAP (rapports, impression & états officiels). Les règles sont dans `packages/domaine/lib/src/rapports/`.

/// `K.lien(id, …)` / `<a href=A.href(id)>` : ouvre un autre écran. La coque refuse en silence un écran fermé au profil ; ici le refus se NOMME (la
/// maquette menait à la page 403) — un bouton « Éditer » qui ne fait rien ferait croire à une panne.
void rapOuvrir(BuildContext ctx, String id, {String? libelle}) {
  final c = ContexteEcran.of(ctx);
  final ouvre = c.ouvre;
  if (ouvre != null && !ouvre(id)) {
    ToastsSigh.afficher(ctx, 'Écran fermé à votre profil.',
        type: TypeToast.attention,
        detail:
            '${libelle ?? id} — la matrice des rôles ne l’ouvre pas à « ${c.role} ».');
    return;
  }
  c.aller(id);
}

/// Référence suivante `CNT-AAAAMMJJ-NNNN` de la pièce imprimée.
String rapReference(ContexteEcran c) =>
    PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero());

/// Une grille de cartes à N colonnes : 1 sous 640 px, 2 jusqu'à 1024 px, 3 au-delà (`sm:grid-cols-2 lg:grid-cols-3`), espace [ecart].
class RapGrille extends StatelessWidget {
  const RapGrille({super.key, required this.enfants, this.ecart = 8});
  final List<Widget> enfants;
  final double ecart;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, k) {
        final n = k.maxWidth >= 1024 ? 3 : (k.maxWidth >= 640 ? 2 : 1);
        final l = (k.maxWidth - (n - 1) * ecart) / n - 0.001;
        return Wrap(
            spacing: ecart,
            runSpacing: ecart,
            children: [for (final e in enfants) SizedBox(width: l, child: e)]);
      });
}

/// Deux colonnes au-delà de 1024 px (`lg:grid-cols-2`), une en dessous.
Widget rapDeux(Widget a, Widget b) => LayoutBuilder(builder: (_, k) {
      final l = k.maxWidth >= 1024 ? (k.maxWidth - 16) / 2 : k.maxWidth;
      return Wrap(spacing: 16, runSpacing: 16, children: [
        SizedBox(width: l, child: a),
        SizedBox(width: l, child: b)
      ]);
    });

/// Une espace insécable fine ne se coupe pas : les libellés comparés par les tests passent par ce nettoyage.
String rapSansEspaces(String s) => s.replaceAll(RegExp(r'[\s  ]'), '');

const TextStyle rapMono = TextStyle(
    fontFamily: 'LiberationMono',
    fontSize: 12,
    height: 16 / 12,
    color: JetonsShell.slate700);

/// Les filtres EN FORCE à porter sur la pièce (`filtresDeLaPage()` de print.js) : (libellé, valeur) des seules commandes portant une valeur.
List<(String, String)> rapFiltresEnForce(Iterable<(String, String)> filtres) {
  final vus = <String>{};
  return [
    for (final (l, v) in filtres)
      if (l.isNotEmpty && v.isNotEmpty && vus.add('$l=$v')) (l, v)
  ];
}

/// L'aperçu A4 d'une pièce de RAP.
Future<void> rapApercu(BuildContext ctx, PieceA4 piece) =>
    afficherApercu(ctx, piece);
