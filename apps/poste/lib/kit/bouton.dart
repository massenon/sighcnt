import 'package:flutter/material.dart';

import '../core/jetons_shell.dart';

enum VarianteBouton { primaire, secondaire, fantome, succes, attention, danger }

enum TailleBouton { sm, md, lg }

/// `.btn` de la maquette : rayon 8, espace 8 entre icône et texte, police 500. md = 14/20 px 14·8 (h 36), sm = 12/16
/// px 10·6 (h 28), lg = 16/24 px 20·10 (h 44). Seul le secondaire porte une bordure (h 38). Désactivé : opacité 50 %.
class BoutonSigh extends StatelessWidget {
  const BoutonSigh({
    super.key,
    required this.libelle,
    this.onPressed,
    this.variante = VarianteBouton.primaire,
    this.taille = TailleBouton.md,
    this.icone,
    this.libelleVisible = true,
  });

  final String libelle;

  /// `false` : icône seule dans un bouton de taille normale (pagination) ; le libellé reste lu par les lecteurs d'écran.
  final bool libelleVisible;
  final VoidCallback? onPressed;
  final VarianteBouton variante;
  final TailleBouton taille;
  final IconData? icone;

  static (Color, Color, Color?) couleurs(VarianteBouton v) => switch (v) {
        VarianteBouton.primaire => (JetonsShell.navy900, Colors.white, null),
        VarianteBouton.secondaire => (
            Colors.white,
            JetonsShell.slate700,
            JetonsShell.slate300
          ),
        VarianteBouton.fantome => (
            Colors.transparent,
            JetonsShell.slate600,
            null
          ),
        VarianteBouton.succes => (JetonsShell.success600, Colors.white, null),
        VarianteBouton.attention => (
            JetonsShell.warning500,
            Colors.white,
            null
          ),
        VarianteBouton.danger => (JetonsShell.danger600, Colors.white, null),
      };

  static Color survol(VarianteBouton v) => switch (v) {
        VarianteBouton.primaire => JetonsShell.navy800,
        VarianteBouton.secondaire => JetonsShell.slate50,
        VarianteBouton.fantome => JetonsShell.slate100,
        VarianteBouton.succes => JetonsShell.success700,
        VarianteBouton.attention => JetonsShell.warning600,
        VarianteBouton.danger => JetonsShell.danger700,
      };

  @override
  Widget build(BuildContext context) {
    final (fond, texte, bord) = couleurs(variante);
    final (px, py, taillePolice, hauteurLigne) = switch (taille) {
      TailleBouton.sm => (10.0, 6.0, 12.0, 16.0),
      TailleBouton.md => (14.0, 8.0, 14.0, 20.0),
      TailleBouton.lg => (20.0, 10.0, 16.0, 24.0),
    };
    final actif = onPressed != null;
    return Semantics(
      button: true,
      enabled: actif,
      focusable: actif,
      label: libelle,
      excludeSemantics: true,
      onTap: onPressed,
      child: Opacity(
        opacity: actif ? 1 : 0.5,
        child: Material(
          color: fond,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: bord == null
                  ? BorderSide.none
                  : BorderSide(color: bord, width: 1)),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            hoverColor: survol(variante),
            focusColor: JetonsShell.navy500.withValues(alpha: 0.25),
            onTap: onPressed,
            child: Padding(
              // La bordure CSS s'ajoute à la boîte (secondaire : h 38) ; la bordure Flutter se dessine à l'intérieur.
              padding: EdgeInsets.symmetric(
                  horizontal: px + (bord == null ? 0 : 1),
                  vertical: py + (bord == null ? 0 : 1)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icone != null) ...[
                  Icon(icone, size: 16, color: texte),
                  if (libelleVisible) const SizedBox(width: 8),
                ],
                if (libelleVisible)
                  Text(libelle,
                      style: TextStyle(
                          color: texte,
                          fontSize: taillePolice,
                          height: hauteurLigne / taillePolice,
                          fontWeight: FontWeight.w500)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.btn.btn-icon` : carré de 36 px, sans remplissage. Le libellé d'accessibilité est OBLIGATOIRE (une icône seule ne se lit pas).
class BoutonIcone extends StatelessWidget {
  const BoutonIcone({
    super.key,
    required this.icone,
    required this.libelle,
    this.onPressed,
    this.variante = VarianteBouton.fantome,
  });

  final IconData icone;
  final String libelle;
  final VoidCallback? onPressed;
  final VarianteBouton variante;

  @override
  Widget build(BuildContext context) {
    final (fond, texte, bord) = BoutonSigh.couleurs(variante);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      focusable: onPressed != null,
      label: libelle,
      excludeSemantics: true,
      onTap: onPressed,
      child: Tooltip(
        message: libelle,
        child: Opacity(
          opacity: onPressed != null ? 1 : 0.5,
          child: Material(
            color: fond,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: bord == null
                    ? BorderSide.none
                    : BorderSide(color: bord, width: 1)),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              hoverColor: BoutonSigh.survol(variante),
              onTap: onPressed,
              child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(icone, size: 16, color: texte)),
            ),
          ),
        ),
      ),
    );
  }
}
