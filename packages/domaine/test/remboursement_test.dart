// Rejoue les vecteurs de la modale « Nouvelle opération » de m8-remboursements (prototype_html/build/vecteurs-remboursements.js).
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

List<Map<String, Object?>> liste(Object? v) => ((v ?? const []) as List)
    .map((x) => (x as Map).cast<String, Object?>())
    .toList();

/// Le magasin ne garde pas les champs nuls : absent et vide-nul se valent ; les chaînes vides, elles, sont écrites.
void memes(Object? obtenu, Object? attendu, String chemin) {
  if (attendu is Map) {
    final o = (obtenu as Map?) ?? const {};
    for (final k in {...attendu.keys, ...o.keys}) {
      memes(o[k], attendu[k], '$chemin.$k');
    }
  } else if (attendu is List) {
    final o = obtenu as List;
    expect(o.length, attendu.length, reason: '$chemin : longueur');
    for (var i = 0; i < attendu.length; i++) {
      memes(o[i], attendu[i], '$chemin[$i]');
    }
  } else if (attendu is num) {
    expect((obtenu as num).toDouble(), attendu.toDouble(), reason: chemin);
  } else {
    expect(obtenu, attendu, reason: chemin);
  }
}

void main() {
  final f = File('test/vecteurs/remboursements.json');
  if (!f.existsSync()) {
    fail('vecteurs absents : lancer `node prototype_html/build/vecteurs-remboursements.js`');
  }
  final cas = liste((jsonDecode(f.readAsStringSync()) as Map)['cas']);
  test('six situations ont été engendrées',
      () => expect(cas.length, greaterThanOrEqualTo(6)));

  for (final c in cas) {
    final e = (c['entree']! as Map).cast<String, Object?>();
    test('${e['nom']}', () {
      final fac = (e['facture']! as Map).cast<String, Object?>();
      final saisie = {
        'factureId': fac['id'],
        'motifAvoir': '',
        'refacturation': '',
        ...(e['saisie']! as Map).cast<String, Object?>(),
      };
      final attendues = liste(c['remboursements']);
      if (attendues.isEmpty) {
        expect(
            () => enregistrerOperation(
                saisie: saisie,
                facture: fac,
                remboursements: liste(e['remboursements']),
                rangFactures: e['rangFactures']! as int),
            throwsA(isA<RefusOperation>()));
        return;
      }
      final r = enregistrerOperation(
          saisie: saisie,
          facture: fac,
          remboursements: liste(e['remboursements']),
          rangFactures: e['rangFactures']! as int);
      memes(r.remboursement, attendues.single, 'remboursement');
      final creees = liste(c['facturesCreees']);
      expect(r.factureAvoir == null, creees.isEmpty);
      if (creees.isNotEmpty) memes(r.factureAvoir, creees.single, 'avoir');
      final patch = (c['facturePatch']! as Map).cast<String, Object?>();
      if (r.patchFacture != null) {
        memes(r.patchFacture, {
          'statutPaiement': patch['statutPaiement'],
          'statutMecef': patch['statutMecef'],
          'annulee': patch['annulee'],
        }, 'patch');
      } else {
        // Aucun effet sur la facture : elle garde son état d'origine.
        expect(patch['statutPaiement'], fac['statutPaiement']);
        expect(patch['statutMecef'], fac['statutMecef']);
        expect(patch['annulee'], isNull);
      }
    });
  }

  test('les factures proposées sont les réglées, les plus récentes d\'abord', () {
    final l = facturesConcernables([
      {'id': 'a', 'date': '2026-01-01', 'montantPaye': 0, 'statutPaiement': 'impayee'},
      {'id': 'b', 'date': '2026-01-03', 'montantPaye': 10, 'statutPaiement': 'partielle'},
      {'id': 'c', 'date': '2026-01-02', 'montantPaye': 0, 'statutPaiement': 'soldee'},
    ]);
    expect(l.map((x) => x['id']), ['b', 'c']);
  });
}
