import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import 'jetons_shell.dart';

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

  static final RoundedRectangleBorder _forme12 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  static final RoundedRectangleBorder _forme12Bord =
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: JetonsShell.slate200));

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
      // LES SURFACES FLOTTANTES de Material (dialogue, menu contextuel, sélecteurs de date et d'heure, info-bulle, feuille basse, bandeau de message) portent
      // le fond, le rayon, l'ombre et le texte du design system : fond de carte blanc, rayon 12, ombre `pop`, aucune teinte de surface. Les modales du poste
      // passent par le kit ; ces thèmes ne sont que le filet de sécurité d'un composant natif que le kit habille déjà (menu des filtres, sélecteurs de date).
      dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shadowColor: JetonsShell.navy950,
          elevation: 8,
          shape: _forme12),
      popupMenuTheme: PopupMenuThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          shadowColor: JetonsShell.navy950,
          elevation: 8,
          shape: _forme12,
          textStyle: const TextStyle(color: JetonsShell.slate700, fontSize: 14)),
      datePickerTheme: DatePickerThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shadowColor: JetonsShell.navy950,
          shape: _forme12),
      timePickerTheme: TimePickerThemeData(backgroundColor: Colors.white, shape: _forme12),
      bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          modalBarrierColor: JetonsShell.scrim,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12)))),
      dropdownMenuTheme: DropdownMenuThemeData(
          menuStyle: MenuStyle(
              backgroundColor: const WidgetStatePropertyAll(Colors.white),
              surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
              shadowColor: const WidgetStatePropertyAll(JetonsShell.navy950),
              shape: WidgetStatePropertyAll(_forme12))),
      menuTheme: MenuThemeData(
          style: MenuStyle(
              backgroundColor: const WidgetStatePropertyAll(Colors.white),
              surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
              shadowColor: const WidgetStatePropertyAll(JetonsShell.navy950),
              shape: WidgetStatePropertyAll(_forme12))),
      snackBarTheme: SnackBarThemeData(
          backgroundColor: Colors.white,
          contentTextStyle: const TextStyle(color: JetonsShell.slate900, fontSize: 14),
          behavior: SnackBarBehavior.floating,
          shape: _forme12Bord),
      tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(color: JetonsShell.navy950, borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(color: Colors.white, fontSize: 12)),
      // Texte jamais sous 11 pt (CDCT) : le corps de texte garde 14.
      textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 14),
          bodySmall: TextStyle(fontSize: 12)),
    );
  }
}
