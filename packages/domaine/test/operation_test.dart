import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

void main() {
  test('une opération survit à un aller-retour JSON', () {
    final op = Operation(
      id: '0192-test',
      appareil: 'poste-1',
      epoch: 1,
      hlc: 1,
      collection: 'patients',
      fiche: 'p1',
      type: 'modifier',
      champs: {'telephone': '222'},
      vu: {'telephone': 7},
    );
    final relue = Operation.fromJson(op.toJson());
    expect(relue.toJson(), equals(op.toJson()));
  });

  test('aucun code ne désigne une suppression physique', () {
    expect(CodeSync.suppressionInterdite, 'suppression_interdite');
  });
}
