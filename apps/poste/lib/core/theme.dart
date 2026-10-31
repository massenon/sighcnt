import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

/// Thème SIGH-CNT : bleu institutionnel (navy), fonds blanc/gris clair, sémantique vert/orange/rouge. Toutes les valeurs
/// viennent des jetons de la maquette (`JetonsSigh`, engendrés) — aucune couleur en dur ailleurs (PRD Flutter, P0-3).
class ThemeSigh {
  ThemeSigh._();

  static Color _c(Map<int, int> palette, int nuance) => Color(palette[nuance]!);

  static Color get navy => _c(JetonsSigh.navy, 900);
  static Color get navyDoux => _c(JetonsSigh.navy, 50);
  static Color get succes => _c(JetonsSigh.success, 600);
  static Color get succesFond => _c(JetonsSigh.success, 100);
  static Color get attention => _c(JetonsSigh.warning, 600);
  static Color get attentionFond => _c(JetonsSigh.warning, 100);
  static Color get danger => _c(JetonsSigh.danger, 700);
  static Color get dangerFond => _c(JetonsSigh.danger, 100);

  static ThemeData clair() {
    final schema = ColorScheme.fromSeed(
        seedColor: navy, primary: navy, error: danger, surface: Colors.white);
    return ThemeData(
      useMaterial3: true,
      colorScheme: schema,
      fontFamily: JetonsSigh.policeSans.first,
      fontFamilyFallback: JetonsSigh.policeSans.skip(1).toList(),
      scaffoldBackgroundColor: _c(JetonsSigh.navy, 50),
      appBarTheme:
          AppBarTheme(backgroundColor: navy, foregroundColor: Colors.white),
      cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      // Texte jamais sous 11 pt (CDCT) : le corps de texte garde 14.
      textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 14),
          bodySmall: TextStyle(fontSize: 12)),
    );
  }
}
