import 'dart:io';

import 'package:flutter/services.dart';

/// Charge les VRAIES polices (Inter, Lucide) dans un test : sans cela Flutter dessine tout en carrés « Ahem » et les
/// captures de comparaison visuelle (N3) ne disent rien.
Future<void> chargerPolices() async {
  final inter = FontLoader('Inter');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold', 'Italic']) {
    inter.addFont(Future.value(ByteData.view(
        File('assets/polices/Inter-$f.otf').readAsBytesSync().buffer)));
  }
  await inter.load();
  final lucide = FontLoader('packages/lucide_icons_flutter/Lucide');
  final cfg = File('.dart_tool/package_config.json').readAsStringSync();
  final m =
      RegExp(r'"name":\s*"lucide_icons_flutter",\s*"rootUri":\s*"([^"]+)"')
          .firstMatch(cfg)!;
  final racine = m.group(1)!.replaceFirst('file://', '');
  lucide.addFont(Future.value(ByteData.view(
      File('$racine/assets/lucide.ttf').readAsBytesSync().buffer)));
  await lucide.load();
}
