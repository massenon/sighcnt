// Rejoue les échelles relevées sur les vrais graphiques Chart.js de la maquette (prototype_html/build/vecteurs-graphiques.js).
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

void main() {
  final f = File('test/vecteurs/echelle.json');
  if (!f.existsSync())
    fail(
        'vecteurs absents : lancer `node prototype_html/build/vecteurs-graphiques.js`');
  final cas = ((jsonDecode(f.readAsStringSync()) as Map)['cas'] as List)
      .cast<Map<String, dynamic>>();
  var i = 0;
  for (final c in cas) {
    final valeurs = [
      for (final s in c['series'] as List) ...(s as List).cast<num>()
    ];
    test('échelle #${i++} ${c['series']} à ${c['hauteur']} px', () {
      final e = echelleVerticale(valeurs,
          hauteurAxe: (c['hauteurAxe'] as num).toDouble());
      expect(
          e.graduations,
          (c['graduations'] as List)
              .cast<num>()
              .map((x) => x.toDouble())
              .toList());
    });
  }
}
