import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';
import 'parite/extracteur.dart';

/// MESURE de la parité N1 (contenu) des NEUF écrans de M11 contre les fiches de la maquette (`docs/architecture/ecrans/m11-*.json`), horloge épinglée au
/// 30/10/2026 10 h (celle de l'extraction des fiches). C'est la même mesure que `parite_ecrans_test.dart`, restreinte à M11 pour tourner seule ; le taux
/// de chaque écran doit valoir 1,0 et rien ne doit manquer.
void main() {
  setUpAll(chargerPolices);
  final donnees = DonneesNavigation.depuisDossier();
  const ecrans = [
    'm11-dashboard',
    'm11-calcul',
    'm11-bulletins',
    'm11-cotisations',
    'm11-heures-sup',
    'm11-avances',
    'm11-validation',
    'm11-ortb',
    'm11-prets-etudes',
  ];

  for (final id in ecrans) {
    testWidgets('parité N1 de $id = 100 %', (t) async {
      final f = (jsonDecode(File('../../docs/architecture/ecrans/$id.json').readAsStringSync()) as Map).cast<String, Object?>();
      t.view.physicalSize = const Size(1440, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(SighPoste(
          donnees: donnees,
          config: const ConfigPoste(mode: ModePoste.fileul, role: 'admin'),
          ecranInitial: id,
          magasin: Magasin.depuisDossier(Magasin.collectionsDuJeu),
          horloge: () => DateTime(2026, 10, 30, 10)));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final p = comparerContenu(id, f, textesVisibles(t));
      expect(p.manquants, isEmpty, reason: '$id : il manque ${p.manquants} (taux ${p.taux})');
      expect(p.taux, 1.0);
      await t.pump(const Duration(seconds: 10));
    });
  }
}
