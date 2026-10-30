// Rejoue les vecteurs de PR.repartir engendrés par la maquette (prototype_html/build/vecteurs-prise-en-charge.js).
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

List<Map<String, Object?>> liste(Object? v) => ((v ?? const []) as List)
    .map((x) => (x as Map).cast<String, Object?>())
    .toList();

void main() {
  final f = File('test/vecteurs/prise_en_charge.json');
  if (!f.existsSync())
    fail(
        'vecteurs absents : lancer `node prototype_html/build/vecteurs-prise-en-charge.js`');
  final cas = liste((jsonDecode(f.readAsStringSync()) as Map)['cas']);

  Repartition rejouer(Map<String, Object?> e) => repartir(
        patient: (e['patient'] as Map?)?.cast<String, Object?>(),
        lignes: liste(e['lignes']),
        date: e['date']! as String,
        couvertures: liste(e['couvertures']),
        souscripteurs: liste(e['souscripteurs']),
        garanties: liste(e['garanties']),
      );

  test('au moins 20 situations ont été engendrées',
      () => expect(cas.length, greaterThanOrEqualTo(20)));

  for (final c in cas) {
    final e = (c['entree']! as Map).cast<String, Object?>();
    final attendu = (c['sortie']! as Map).cast<String, Object?>();
    test('${e['nom']}', () {
      final r = rejouer(e);
      expect(r.carteValide, attendu['carteValide']);
      expect(r.grilleSaisie, attendu['grilleSaisie']);
      expect(r.souscripteurId, attendu['souscripteurId']);
      expect(r.total, (attendu['total']! as num).toDouble());
      expect(r.partAssureur, (attendu['partAssureur']! as num).toDouble());
      expect(r.partPatient, (attendu['partPatient']! as num).toDouble());
      final lignes = liste(attendu['lignes']);
      expect(r.lignes.length, lignes.length);
      for (var i = 0; i < lignes.length; i++) {
        final a = lignes[i], b = r.lignes[i];
        // Les clés ABSENTES de la sortie de la maquette (exclu, accordRequis) doivent l'être aussi ici.
        expect(b.keys.toSet(), a.keys.toSet(), reason: 'ligne $i : clés');
        for (final k in a.keys) {
          final x = a[k], y = b[k];
          if (x is num) {
            expect((y as num).toDouble(), x.toDouble(),
                reason: 'ligne $i : $k');
          } else {
            expect(y, x, reason: 'ligne $i : $k');
          }
        }
      }
    });
  }

  test(
      'invariant : la somme des parts égale toujours le total (aucun franc perdu ni créé)',
      () {
    for (final c in cas) {
      final r = rejouer((c['entree']! as Map).cast<String, Object?>());
      expect(r.partAssureur + r.partPatient, r.total,
          reason: '${(c['entree']! as Map)['nom']}');
    }
  });
}
