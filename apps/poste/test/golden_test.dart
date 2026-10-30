import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// Capture de la coque pour la comparaison visuelle (N3) avec la maquette : `flutter test --update-goldens test/golden_test.dart`
/// écrit `test/golden/*.png`. La comparaison à l'œil se fait contre `build/shot.js` de la maquette (même rôle, même écran, 1440 px).
void main() {
  setUpAll(chargerPolices);

  // Les captures dépendent des polices et du moteur de rendu de la machine : comparées seulement sur demande (SIGH_GOLDEN=1).
  testWidgets('coque — administrateur, domaine Financier, 1440 × 900', skip: !const bool.fromEnvironment('SIGH_GOLDEN') && !_demande, (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(SighPoste(donnees: DonneesNavigation.depuisDossier(), config: const ConfigPoste(mode: ModePoste.fileul, role: 'admin', nomPoste: 'BASSONGUI Chabi Séko')));
    await t.pump();
    await t.tap(find.byKey(const Key('domaine-Financier')));
    await t.pump();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('golden/coque_financier.png'));
  });
}

final bool _demande = const String.fromEnvironment('SIGH_GOLDEN') == '1';
