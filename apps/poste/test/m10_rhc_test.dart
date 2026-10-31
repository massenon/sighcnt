import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/m10/rhc_evenements.dart';

import 'aide_polices.dart';
import 'm10_aide.dart';
import 'm10_rhc_aide.dart';

/// M10 (C) : les huit écrans MONTÉS sur le jeu du poste et comparés aux relevés de la maquette (packages/domaine/test/vecteurs/rhc.json, engendrés par
/// prototype_html/build/vecteurs-rh-c.js — écrans pilotés dans Chrome à l'horloge du 30/10/2026 10 h). Les règles chiffrées sont rejouées par
/// packages/domaine/test/rhc_regles_test.dart.
const ecrans = [
  'm10-badges',
  'm10-badges-verification',
  'm10-badges-modeles',
  'm10-badges-impression',
  'm10-evenements',
  'm10-participations',
  'm10-assurance-personnel',
  'm10-securite-entretien',
];

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('parité de contenu N1 : chaque libellé de la maquette figure à l’écran', () {
    for (final id in ecrans) {
      testWidgets(id, (t) async {
        await ouvrir(t, posteRhc(), id);
        expect(t.takeException(), isNull);
        expect(manquantsN1(t, id), isEmpty, reason: id);
        await fermerToasts(t);
      });
    }
  });
}
