// Aides communes des tests qui rejouent des vecteurs engendrés par la maquette.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

List<Map<String, Object?>> liste(Object? v) =>
    ((v ?? const []) as List).map((x) => (x as Map).cast<String, Object?>()).toList();

Map<String, Object?> lireVecteurs(String nom) {
  final f = File('test/vecteurs/$nom.json');
  if (!f.existsSync()) fail('vecteurs absents : lancer le script de prototype_html/build qui engendre $nom.json');
  return (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>();
}

/// Compare [obtenu] à [attendu] champ par champ (les champs `_…` et ceux de [ignorer] sont laissés de côté) ; les nombres se comparent en valeur.
void memes(Object? obtenu, Object? attendu, String chemin,
    {Set<String> ignorer = const {}, bool sousEnsemble = false}) {
  if (attendu is Map) {
    final o = (obtenu as Map?) ?? const {};
    for (final k in sousEnsemble ? attendu.keys : {...attendu.keys, ...o.keys}) {
      if (ignorer.contains(k) || '$k'.startsWith('_')) continue;
      memes(o[k], attendu[k], '$chemin.$k', ignorer: ignorer, sousEnsemble: sousEnsemble);
    }
  } else if (attendu is List) {
    final o = obtenu as List;
    expect(o.length, attendu.length, reason: '$chemin : longueur');
    for (var i = 0; i < attendu.length; i++) {
      memes(o[i], attendu[i], '$chemin[$i]', ignorer: ignorer, sousEnsemble: sousEnsemble);
    }
  } else if (attendu is num) {
    expect(obtenu is num ? obtenu.toDouble() : obtenu, attendu.toDouble(), reason: chemin);
  } else {
    expect(obtenu, attendu, reason: chemin);
  }
}
