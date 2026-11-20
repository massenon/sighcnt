// Rejoue les vecteurs de `SIGH.emettreAvoir` engendrés par la maquette (prototype_html/build/vecteurs-avoir.js).
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

List<Map<String, Object?>> liste(Object? v) => ((v ?? const []) as List)
    .map((x) => (x as Map).cast<String, Object?>())
    .toList();

void memes(Object? obtenu, Object? attendu, String chemin,
    {Set<String> ignorer = const {}}) {
  if (attendu is Map) {
    final o = (obtenu as Map?) ?? const {};
    for (final k in {...attendu.keys, ...o.keys}) {
      if (ignorer.contains(k) || '$k'.startsWith('_')) continue;
      memes(o[k], attendu[k], '$chemin.$k', ignorer: ignorer);
    }
  } else if (attendu is List) {
    final o = obtenu as List;
    expect(o.length, attendu.length, reason: '$chemin : longueur');
    for (var i = 0; i < attendu.length; i++) {
      memes(o[i], attendu[i], '$chemin[$i]', ignorer: ignorer);
    }
  } else if (attendu is num) {
    expect((obtenu as num).toDouble(), attendu.toDouble(), reason: chemin);
  } else {
    expect(obtenu, attendu, reason: chemin);
  }
}

void main() {
  final f = File('test/vecteurs/avoir.json');
  if (!f.existsSync()) {
    fail('vecteurs absents : lancer `node prototype_html/build/vecteurs-avoir.js`');
  }
  final cas = liste((jsonDecode(f.readAsStringSync()) as Map)['cas']);
  test('au moins 25 situations ont été engendrées',
      () => expect(cas.length, greaterThanOrEqualTo(25)));

  for (final c in cas) {
    final e = (c['entree']! as Map).cast<String, Object?>();
    final attendu = (c['sortie']! as Map).cast<String, Object?>();
    final p = (e['params']! as Map).cast<String, Object?>();
    test('${e['nom']}', () {
      AvoirEmis emettre() => emettreAvoir(
            // « Facture introuvable » : la maquette cherche par identifiant au magasin ; ici l'appelant n'a rien trouvé.
            facture: (e['facture']! as Map)['id'] == 'INCONNUE' ? null : (e['facture']! as Map).cast(),
            idAvoir: 'AVR-TEST',
            lignes: liste(p['lignes']),
            motif: p['motif']! as String,
            remboursement: p['remboursement'] as String?,
            observations: p['observations'] as String?,
            date: p['date'] as String?,
            origine: p['origine'] as String?,
            jour: e['jour']! as String,
            utilisateur: e['utilisateur']! as String,
            facturesMere: liste(e['facturesMere']),
            avoirs: liste(e['avoirs']),
          );
      if (attendu.containsKey('erreur')) {
        expect(emettre, throwsA(isA<RefusAvoir>().having((r) => r.motif, 'motif', attendu['erreur'])));
        return;
      }
      final r = emettre();
      memes(r.avoir, attendu['avoir'], 'avoir');
      // Les écritures : même contenu (l'ordre de lecture du magasin n'est pas une règle), pièce = l'avoir.
      final obtenues = [...r.ecritures]..sort((a, b) => '${a['compte']}'.compareTo('${b['compte']}'));
      final attendues = liste(attendu['ecritures'])..sort((a, b) => '${a['compte']}'.compareTo('${b['compte']}'));
      memes(obtenues, attendues, 'ecritures', ignorer: const {'pieceId'});
      expect(obtenues.every((x) => x['pieceId'] == 'AVR-TEST'), isTrue);
      // RG-10 : l'équilibre est construit.
      final debit = r.ecritures.fold<double>(0, (a, x) => a + (x['debit']! as num));
      final credit = r.ecritures.fold<double>(0, (a, x) => a + (x['credit']! as num));
      expect(debit, credit);
      expect(r.montantAvoirs, ((attendu['facture']! as Map)['montantAvoirs']! as num).toDouble());
    });
  }
}
