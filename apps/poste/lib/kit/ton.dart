import 'package:flutter/painting.dart';

import '../core/jetons_shell.dart';

/// Tons sémantiques de la maquette (badges, KPI, notes, toasts). Toutes les teintes viennent de `JetonsShell`.
enum TonSigh { neutre, navy, succes, attention, danger, info }

extension TonCouleurs on TonSigh {
  Color get fond50 => switch (this) {
        TonSigh.neutre => JetonsShell.slate100,
        TonSigh.navy => JetonsShell.navy50,
        TonSigh.succes => JetonsShell.success50,
        TonSigh.attention => JetonsShell.warning50,
        TonSigh.danger => JetonsShell.danger50,
        TonSigh.info => JetonsShell.info50,
      };

  /// Texte d'un badge : `text-<ton>-700` (navy : 800, neutre : slate-700).
  Color get texteBadge => switch (this) {
        TonSigh.neutre => JetonsShell.slate700,
        TonSigh.navy => JetonsShell.navy800,
        TonSigh.succes => JetonsShell.success700,
        TonSigh.attention => JetonsShell.warning700,
        TonSigh.danger => JetonsShell.danger700,
        TonSigh.info => JetonsShell.info700,
      };

  /// Icône d'un KPI : `text-<ton>-600` (navy : 700).
  Color get icone600 => switch (this) {
        TonSigh.neutre => JetonsShell.slate600,
        TonSigh.navy => JetonsShell.navy700,
        TonSigh.succes => JetonsShell.success600,
        TonSigh.attention => JetonsShell.warning600,
        TonSigh.danger => JetonsShell.danger600,
        TonSigh.info => JetonsShell.info600,
      };

  Color get bordure200 => switch (this) {
        TonSigh.neutre => JetonsShell.slate200,
        TonSigh.navy => JetonsShell.navy200,
        TonSigh.succes => JetonsShell.success200,
        TonSigh.attention => JetonsShell.warning200,
        TonSigh.danger => JetonsShell.danger200,
        TonSigh.info => JetonsShell.info200,
      };

  Color get texte900 => switch (this) {
        TonSigh.neutre => JetonsShell.slate900,
        TonSigh.navy => JetonsShell.navy900,
        TonSigh.succes => JetonsShell.success900,
        TonSigh.attention => JetonsShell.warning900,
        TonSigh.danger => JetonsShell.danger900,
        TonSigh.info => JetonsShell.info900,
      };
}
