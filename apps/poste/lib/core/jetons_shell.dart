// ENGENDRÉ par prototype_html/build/gen-poste-assets.js depuis docs/design/design-tokens.json — NE PAS ÉDITER.
// Constantes de couleur de la coque. Les « slate » sont la palette neutre par défaut de Tailwind, utilisée par la maquette.
import 'package:flutter/painting.dart';

class JetonsShell {
  JetonsShell._();
  static const Color navy50 = Color(0xFFF1F5FB);
  static const Color navy100 = Color(0xFFE0EAF6);
  static const Color navy200 = Color(0xFFC7DAF0);
  static const Color navy300 = Color(0xFF9DC0E4);
  static const Color navy400 = Color(0xFF6C9ED4);
  static const Color navy500 = Color(0xFF4A7FC1);
  static const Color navy600 = Color(0xFF3765A6);
  static const Color navy700 = Color(0xFF2E5187);
  static const Color navy800 = Color(0xFF2A4670);
  static const Color navy900 = Color(0xFF12315E);
  static const Color navy950 = Color(0xFF0B1E3D);
  static const Color success50 = Color(0xFFEEFBF4);
  static const Color success100 = Color(0xFFD6F5E3);
  static const Color success200 = Color(0xFFB0E9CC);
  static const Color success300 = Color(0xFF7BD7AE);
  static const Color success400 = Color(0xFF45BD8B);
  static const Color success500 = Color(0xFF22A170);
  static const Color success600 = Color(0xFF15825A);
  static const Color success700 = Color(0xFF12684A);
  static const Color success800 = Color(0xFF12523C);
  static const Color success900 = Color(0xFF104433);
  static const Color warning50 = Color(0xFFFFF8EB);
  static const Color warning100 = Color(0xFFFFEDC6);
  static const Color warning200 = Color(0xFFFFD888);
  static const Color warning300 = Color(0xFFFFBE4A);
  static const Color warning400 = Color(0xFFFFA620);
  static const Color warning500 = Color(0xFFF98307);
  static const Color warning600 = Color(0xFFDD5F02);
  static const Color warning700 = Color(0xFFB74106);
  static const Color warning800 = Color(0xFF94320C);
  static const Color warning900 = Color(0xFF7A2A0D);
  static const Color danger50 = Color(0xFFFEF2F2);
  static const Color danger100 = Color(0xFFFEE2E2);
  static const Color danger200 = Color(0xFFFECACA);
  static const Color danger300 = Color(0xFFFCA5A5);
  static const Color danger400 = Color(0xFFF87171);
  static const Color danger500 = Color(0xFFEF4444);
  static const Color danger600 = Color(0xFFDC2626);
  static const Color danger700 = Color(0xFFB91C1C);
  static const Color danger800 = Color(0xFF991B1B);
  static const Color danger900 = Color(0xFF7F1D1D);
  static const Color info50 = Color(0xFFEFF8FF);
  static const Color info100 = Color(0xFFDBEEFE);
  static const Color info200 = Color(0xFFBFE2FE);
  static const Color info300 = Color(0xFF92D0FD);
  static const Color info400 = Color(0xFF61B6FA);
  static const Color info500 = Color(0xFF3B98F6);
  static const Color info600 = Color(0xFF257AEB);
  static const Color info700 = Color(0xFF1D63D8);
  static const Color info800 = Color(0xFF1E51AF);
  static const Color info900 = Color(0xFF1E468A);
  static const Color slate50 = Color(0xFFF8FAFC);
  static const Color slate100 = Color(0xFFF1F5F9);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color slate300 = Color(0xFFCBD5E1);
  static const Color slate400 = Color(0xFF94A3B8);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate600 = Color(0xFF475569);
  static const Color slate700 = Color(0xFF334155);
  static const Color slate800 = Color(0xFF1E293B);
  static const Color slate900 = Color(0xFF0F172A);
  /// Ombres de tailwind.config.js (boxShadow card / raise / pop), couleur rgb(11 30 61).
  static const Color _ombre = Color(0xFF0B1E3D);
  static const List<BoxShadow> ombreCarte = [
    BoxShadow(color: Color.fromRGBO(11, 30, 61, 0.05), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color.fromRGBO(11, 30, 61, 0.06), offset: Offset(0, 1), blurRadius: 3),
  ];
  static const List<BoxShadow> ombreRelief = [
    BoxShadow(color: Color.fromRGBO(11, 30, 61, 0.10), offset: Offset(0, 4), blurRadius: 12, spreadRadius: -2),
    BoxShadow(color: Color.fromRGBO(11, 30, 61, 0.06), offset: Offset(0, 2), blurRadius: 6, spreadRadius: -2),
  ];
  static const List<BoxShadow> ombrePop = [
    BoxShadow(color: Color.fromRGBO(11, 30, 61, 0.22), offset: Offset(0, 12), blurRadius: 32, spreadRadius: -8),
  ];
  static Color get ombre => _ombre;
}
