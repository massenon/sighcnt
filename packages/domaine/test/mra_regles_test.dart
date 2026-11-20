import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

void main() {
  test('retard jamais négatif, à jour seulement au curseur courant', () {
    expect(mraRetard(120, 118), 2);
    expect(mraRetard(10, 12), 0);
    expect(mraAJour(5, 5), isTrue);
    expect(mraAJour(5, 4), isFalse);
  });
  test('âge lisible', () {
    expect(mraAgeLisible(null), 'jamais');
    expect(mraAgeLisible(const Duration(seconds: 12)), 'il y a 12 s');
    expect(mraAgeLisible(const Duration(minutes: 4)), 'il y a 4 min');
    expect(mraAgeLisible(const Duration(hours: 3)), 'il y a 3 h');
    expect(mraAgeLisible(const Duration(days: 2)), 'il y a 2 j');
    expect(mraAgeLisible(const Duration(seconds: -5)), 'il y a 0 s');
  });
  test('accusés : un accusé d\'un appareil non actif ne compte pas', () {
    final a = mraAccuses(['u1', 'u2', 'u3'], ['u1', 'u9']);
    expect(a.recus, ['u1']);
    expect(a.attendus, ['u2', 'u3']);
  });
  test('lot expiré à l\'instant d\'expiration', () {
    expect(mraEtatLot(1000, 999), 'actif');
    expect(mraEtatLot(1000, 1000), 'expiré');
  });
  test('taille de plage bornes comprises', () {
    expect(mraTaillePlage(101, 150), 50);
    expect(mraTaillePlage(5, 4), 0);
  });
  test('répartition des conflits', () {
    final r = mraRepartirConflits(['nom', mraChampDoublon, 'telephone']);
    expect((r.champs, r.doublons), (2, 1));
  });
}
