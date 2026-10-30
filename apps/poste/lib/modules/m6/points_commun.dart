import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

/// Briques communes aux deux « points » du gestionnaire de stock (`m6-point-ventes`, `m6-point-stock`) : les commandes du bandeau de
/// filtres, les cellules de tableau et le passage d'un état du domaine à la pièce A4.

/// Une commande du bandeau = un contrôleur à UN champ (la maquette les range en ligne, à largeur naturelle, pas sur la grille d'un formulaire).
ControleurFormulaire champUnique(ChampDef def, Object? valeur) =>
    ControleurFormulaire([def], {def.nom: valeur});

/// Le champ lui-même, à la largeur [largeur] (`null` : toute la largeur offerte).
Widget commande(ControleurFormulaire c, {double? largeur, bool inactive = false}) {
  Widget w = FormulaireSigh(controleur: c);
  if (largeur != null) w = SizedBox(width: largeur, child: w);
  // `select.disabled` : la valeur reste affichée mais ne se touche plus (l'état d'un stock ne dépend pas de la périodicité).
  return inactive ? IgnorePointer(child: Opacity(opacity: 0.5, child: w)) : w;
}

/// `new Date(y, m, d)` d'une date ISO saisie ; une saisie vide ou illisible retombe sur [repli].
DateTime jourSaisi(Object? iso, DateTime repli) {
  final d = DateTime.tryParse('${iso ?? ''}');
  return d == null ? repli : DateTime(d.year, d.month, d.day);
}

List<String> choix(Object? v) =>
    v is List ? [for (final x in v) '$x'] : const <String>[];

/// Le texte du bouton d'une liste à choix multiples (`U.combo`) : un ou deux libellés, puis « N sélectionnées ».
String resumeChoix(List<String> valeurs, Map<String, String> libelles) =>
    valeurs.length <= 2
        ? valeurs.map((v) => libelles[v] ?? v).join(', ')
        : '${valeurs.length} sélectionnées';

num n(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);
String m(Object? v) => money(v, avecDevise: false);
String dateTexte(Object? v) {
  final d = jourDe(v);
  return d == null ? '' : dateFR(d);
}

const _tab = [FontFeature.tabularFigures()];

TextStyle styleTexte(
        {double taille = 14,
        Color couleur = JetonsShell.slate700,
        FontWeight poids = FontWeight.w400,
        String? police}) =>
    TextStyle(
        fontFamily: police,
        color: couleur,
        fontSize: taille,
        height: taille == 14
            ? 20 / 14
            : (taille == 12 ? 16 / 12 : 15 / taille),
        fontWeight: poids,
        fontFeatures: _tab);

/// Un tiret gris : « rien à dire ici » (ni zéro ni valeur manquante).
Widget tiret() => Text('—',
    style: styleTexte(couleur: JetonsShell.slate300));

/// Deux lignes : la valeur, puis une précision de 10 px en gris.
Widget deuxLignes(String haut, String bas,
        {Color couleur = JetonsShell.slate800,
        FontWeight poids = FontWeight.w400}) =>
    Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(haut, style: styleTexte(couleur: couleur, poids: poids)),
          if (bas.isNotEmpty)
            Text(bas,
                style: styleTexte(taille: 10, couleur: JetonsShell.slate400)),
        ]);

/// Un montant coloré, ou un tiret quand il est nul (colonnes Remise, Assureur, Personnel).
ColonneTableau colMontantPc(String cle, String libelle,
        {required String Function(Fiche) texte,
        required Color couleur,
        required String Function(Fiche) pc,
        bool tiretSiNul = true}) =>
    ColonneTableau(
        cle: cle,
        libelle: libelle,
        droite: true,
        texte: texte,
        rendu: (_, r) => tiretSiNul && n(r[cle]) == 0
            ? tiret()
            : deuxLignes(m(r[cle]), pc(r), couleur: couleur));

ColonneTableau colMontant(String cle, String libelle,
        {Color? couleur,
        FontWeight poids = FontWeight.w400,
        bool tiretSiNul = false}) =>
    ColonneTableau(
        cle: cle,
        libelle: libelle,
        droite: true,
        texte: (r) => m(r[cle]),
        rendu: (_, r) => tiretSiNul && n(r[cle]) == 0
            ? tiret()
            : Text(m(r[cle]),
                style: styleTexte(
                    couleur: couleur ?? JetonsShell.slate700, poids: poids)));

/// Deux cartes côte à côte au-delà de 1024 px (`grid lg:grid-cols-2`), empilées en dessous.
Widget deuxColonnes(List<Widget> cartes) => LayoutBuilder(builder: (_, k) {
      final l = k.maxWidth >= 1024 ? (k.maxWidth - 16) / 2 : k.maxWidth;
      return Wrap(spacing: 16, runSpacing: 16, children: [
        for (final c in cartes) SizedBox(width: l, child: c)
      ]);
    });

/// Un état du domaine → la pièce A4 de l'aperçu (la mise en page est celle de `P.etat`).
PieceA4 piecePoint(BuildContext ctx, EtatPoint e,
    {List<(String, String)> filtres = const []}) {
  final c = ContexteEcran.of(ctx);
  return PieceA4(
    titre: e.titre,
    sousTitre: e.sousTitre,
    reference:
        PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
    utilisateur: c.utilisateur,
    edite: c.aujourdhui,
    cartouche: e.cartouche,
    filtres: filtres,
    blocs: [
      for (final b in e.blocs)
        switch (b) {
          BlocEtatTexte() => BlocTexte(b.texte, gras: b.gras),
          BlocEtatTableau() => BlocTableau(b.tableau),
        }
    ],
    signatures: const [
      Signature('Le Gestionnaire de Stock'),
      Signature('La Directrice Administrative', nom: 'TAKI Alimatou'),
    ],
  );
}

Future<void> imprimerPoint(BuildContext ctx, EtatPoint e,
        {List<(String, String)> filtres = const []}) =>
    afficherApercu(ctx, piecePoint(ctx, e, filtres: filtres));
