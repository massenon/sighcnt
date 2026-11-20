import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';

/// Le LOGO de la clinique (`assets/img/logo.png`, converti du JPEG le 02/11/2026 ; déclaré par `assets/img/` dans `pubspec.yaml`). UN seul endroit le charge pour la barre, la connexion,
/// le verrou et la feuille A4 : un logo qui manque ne doit JAMAIS disparaître en silence (retour de terrain du 01/11/2026, poste Windows : l'ancien
/// `errorBuilder` rendait une boîte vide, et rien ne disait que le fichier n'avait pas été lu). En cas d'échec, le monogramme « CNT » prend la place et
/// la cause est écrite dans la console.
class LogoClinique extends StatelessWidget {
  const LogoClinique({super.key, this.largeur = 48, this.hauteur = 48, this.fondSombre = false});

  /// Chemin de l'asset (testé : il doit figurer dans les assets déclarés et se décoder).
  static const asset = 'assets/img/logo.png';

  final double largeur, hauteur;

  /// Le monogramme de repli se lit sur fond sombre (texte blanc) ou clair (texte navy).
  final bool fondSombre;

  @override
  Widget build(BuildContext context) => Image.asset(
        asset,
        key: const Key('logo-clinique'),
        width: largeur,
        height: hauteur,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'Logo de la clinique',
        errorBuilder: (_, erreur, __) {
          debugPrint('Logo de la clinique illisible ($asset) : $erreur');
          return SizedBox(
              key: const Key('logo-clinique-repli'),
              width: largeur,
              height: hauteur,
              child: Center(
                  child: Text(IdentiteClinique.sigle,
                      style: TextStyle(
                          color: fondSombre ? Colors.white : JetonsShell.navy900,
                          fontWeight: FontWeight.w700,
                          fontSize: (hauteur * 0.34).clamp(10, 24)))));
        },
      );
}
