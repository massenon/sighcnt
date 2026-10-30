import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

void main() {
  test('recherche sans accents ni casse', () {
    expect(correspond('Hémoglobine', 'hemo'), isTrue);
    expect(correspond('Hémoglobine', 'HÉMO'), isTrue);
    expect(correspond('Natitingou', 'xyz'), isFalse);
    expect(correspond(null, 'a'), isFalse);
    expect(correspond('Zoé', 'zoe'), isTrue);
  });
  test('tri naturel : 2 avant 10, vides en dernier, nombres entre eux', () {
    expect(trierPar(['a10', 'a2', 'a1'], (s) => s), ['a1', 'a2', 'a10']);
    expect(trierPar(['a10', 'a2', 'a1'], (s) => s, descendant: true), ['a10', 'a2', 'a1']);
    expect(trierPar<Object?>([3, null, 1], (s) => s), [1, 3, null]);
    expect(trierPar([10, 9, 100], (n) => n), [9, 10, 100]);
    expect(trierPar(['Étienne', 'Eve', 'Adam'], (s) => s), ['Adam', 'Étienne', 'Eve']);
  });
  test('CSV : BOM, point-virgule, guillemets doublés, CRLF', () {
    final c = exporterCsv(['Nom', 'Note'], [
      ['A "x"', null],
      ['B', 12]
    ]);
    expect(c, '﻿"Nom";"Note"\r\n"A ""x""";""\r\n"B";"12"');
  });
}
