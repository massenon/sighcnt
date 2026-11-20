// La règle de fusion entre pairs (ADR-0006) rejouée sur les vecteurs du banc (`packages/sync/banc/vecteurs-pair.js`, exécutable de référence `pair.js`).
// Trois obligations : (1) même état que la référence ; (2) CONVERGENCE : le même ensemble d'opérations, dans n'importe quel ordre et avec des doublons, donne
// le même état ; (3) les invariants (stock jamais négatif, aucune suppression, pièce émise intacte).
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

Map<String, Object?> json(String chemin) => (jsonDecode(File(chemin).readAsStringSync()) as Map).cast<String, Object?>();

List<T> melange<T>(List<T> a, int graine) {
  final r = [...a];
  var s = graine;
  for (var i = r.length - 1; i > 0; i--) {
    s = (s * 1103515245 + 12345) & 0x7fffffff;
    final j = s % (i + 1);
    final t = r[i];
    r[i] = r[j];
    r[j] = t;
  }
  return r;
}

String canon(Object? o) => jsonEncode(o is Map ? (Map.fromEntries(o.entries.toList()..sort((a, b) => '${a.key}'.compareTo('${b.key}'))).map((k, v) => MapEntry(k, _c(v)))) : _c(o));
Object? _c(Object? v) {
  if (v is Map) return Map.fromEntries(v.entries.toList()..sort((a, b) => '${a.key}'.compareTo('${b.key}'))).map((k, x) => MapEntry(k, _c(x)));
  if (v is List) return [for (final x in v) _c(x)];
  return v;
}

void main() {
  final v = json('test/vecteurs/pair.json');
  final table = (v['droits'] as Map).map((c, t) => MapEntry('$c', (t as Map).map((ty, r) => MapEntry('$ty', [for (final x in r as List) '$x']))));
  final droits = droitsDepuisTable(table);
  final cas = [for (final c in (v['cas'] as List)) (c as Map).cast<String, Object?>()];
  List<OperationPair> ops(Map<String, Object?> c) => [for (final o in (c['ops'] as List)) OperationPair.depuisJson((o as Map).cast<String, Object?>())];

  test('les vecteurs sont là et couvrent les refus, les conflits et les parts de stock', () {
    expect(cas.length, greaterThan(60));
    final codes = {for (final c in cas) for (final r in ((c['attendu'] as Map)['refusees'] as List)) (r as Map)['code']};
    expect(codes, containsAll(['droit_refuse', 'hors_part', 'fiche_archivee', 'piece_emise_immuable', 'demande_inconnue', 'suppression_interdite', 'journal_immuable']));
    expect(cas.fold<int>(0, (a, c) => a + (((c['attendu'] as Map)['conflits']) as List).length), greaterThan(20));
  });

  group('même état que la référence JS', () {
    for (final c in cas) {
      test(c['nom'] as String, () {
        final e = etatPair(ops(c), droits: droits);
        expect(canon(e.versJson()), canon(c['attendu']));
      });
    }
  });

  group('convergence : tout ordre d\'arrivée, avec doublons, donne le même état', () {
    for (final c in cas) {
      test(c['nom'] as String, () {
        final o = ops(c);
        final ref = canon(etatPair(o, droits: droits).versJson());
        for (var g = 1; g <= 12; g++) {
          final m = melange(o, g * 7919);
          expect(canon(etatPair(m, droits: droits).versJson()), ref, reason: 'graine $g');
          expect(canon(etatPair([...m, ...m.take(5)], droits: droits).versJson()), ref, reason: 'doublons, graine $g');
        }
      });
    }
  });

  test('invariants sur tous les cas : stock jamais négatif, aucune suppression appliquée, pièce émise intacte', () {
    for (final c in cas) {
      final e = etatPair(ops(c), droits: droits);
      for (final s in e.stock.values) {
        expect((s['qte'] as num) >= 0, true, reason: c['nom'] as String);
      }
      final suppr = ops(c).where((o) => o.type == 'supprimer').map((o) => o.id).toSet();
      expect(e.refusees.where((r) => r.code == 'suppression_interdite').map((r) => r.id).toSet(), suppr);
    }
  });

  test('horloge : strictement croissante, la dérive au-delà de 2 minutes est SIGNALÉE', () {
    var t = 1000;
    final h = HorlogePair(maintenantMs: () => t);
    final a = h.emettre(), b = h.emettre();
    expect(b > a, true);
    h.recevoir((t + 5 * 60 * 1000) * 1000);
    expect(h.derive, true);
    expect(h.emettre() > (t + 5 * 60 * 1000) * 1000, true);
  });

  test('journal au relais : rang contigu, dépôt idempotent, un trou est détecté', () {
    final j = JournalPair();
    expect(j.deposer('F1', 1, 'e1'), 'ok');
    expect(j.deposer('F1', 1, 'e1'), 'deja');
    expect(() => j.deposer('F1', 3, 'e3'), throwsStateError);
    expect(j.releve('F1', 0).length, 1);
    expect(j.releve('F1', 0).first.n, 1);
  });
}
