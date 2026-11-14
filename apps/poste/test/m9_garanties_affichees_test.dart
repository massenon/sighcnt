import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/modules/m9/conventions.dart';

/// LOT TFIN (constat 2 du lot 8b) : l'écran « Conventions & garanties » compte et liste UNE version par série de garantie, celle EN VIGUEUR au jour dit (comme la prise en charge,
/// RG-09, et l'écran de la maquette). Avant : toutes les versions (« 5 garanties » pour trois séries).
typedef F = Map<String, Object?>;
void main() {
  final lignes = <F>[
    {'id': 'G1', 'souscripteurId': 'S1', 'categorie': 'A', 'libelle': 'Consultation', 'taux': 70, 'version': 1},
    {'id': 'G2', 'souscripteurId': 'S1', 'categorie': 'A', 'libelle': 'Consultation', 'taux': 80, 'version': 2, 'dateEffet': '2026-11-01'},
    {'id': 'G3', 'souscripteurId': 'S1', 'categorie': 'A', 'libelle': 'Consultation', 'taux': 90, 'version': 3, 'dateEffet': '2026-12-01'},
    {'id': 'G4', 'souscripteurId': 'S1', 'categorie': 'A', 'libelle': 'Hospitalisation', 'taux': 60, 'version': 1},
    {'id': 'G5', 'souscripteurId': 'S2', 'categorie': 'A', 'libelle': 'Consultation', 'taux': 50, 'version': 1},
  ];
  test('une version par série, celle en vigueur au jour dit ; une version future ne compte pas ; un autre souscripteur non plus', () {
    final au14 = garantiesAffichees(lignes, 'S1', '2026-11-14');
    expect(au14.map((g) => g['id']), ['G2', 'G4'], reason: 'deux séries, pas quatre lignes ; la version du 01/12 n\'est pas encore en vigueur');
    expect(garantiesAffichees(lignes, 'S1', '2026-12-02').map((g) => g['id']), ['G3', 'G4']);
    expect(garantiesAffichees(lignes, 'S1', '2026-10-01').map((g) => g['id']), ['G1', 'G4']);
    expect(garantiesAffichees(lignes, 'S2', '2026-11-14').map((g) => g['id']), ['G5']);
    expect(garantiesAffichees(lignes, 'S9', '2026-11-14'), isEmpty);
  });
}
