// Lot MIL (16/11/2026) : la fabrique unique des numéros annuels et les agrégats à l'exercice du jour, horloge posée au 31/12/2026 puis au 01/01/2027.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

void main() {
  final veille = DateTime(2026, 12, 31, 12);
  final jour = DateTime(2027, 1, 1, 12);
  final fiches = <Map<String, Object?>>[
    {'reference': 'BEB-2026-0007'},
    {'reference': 'BEB-2027-0002'},
    {'reference': 'BC-2026-0099'},
  ];

  test('l\'année est celle de la DATE DE LA PIÈCE, le compteur est par année', () {
    expect(referenceAnnuelle('BEB-', '2026-12-31', 4, fiches, maintenant: jour), 'BEB-2026-0008');
    expect(referenceAnnuelle('BEB-', '2027-01-01', 4, fiches, maintenant: veille), 'BEB-2027-0003');
    expect(referenceAnnuelle('BC-', '2027-01-01', 4, fiches, maintenant: veille), 'BC-2027-0001');
    expect(referenceAnnuelle('BC-', '2025-06-01', 4, fiches, maintenant: jour), 'BC-2025-0001');
  });

  test('sans date lisible, l\'horloge : 2026 la veille, 2027 le jour', () {
    expect(referenceAnnuelle('RU-', null, 3, const [], maintenant: veille), 'RU-2026-001');
    expect(referenceAnnuelle('RU-', null, 3, const [], maintenant: jour), 'RU-2027-001');
    expect(anneeDePiece('2026-12-31T23:59:00', jour), 2026);
    expect(anneeDePiece(DateTime(2027, 1, 1), veille), 2027);
  });

  test('le champ du numéro est au choix (CERT sur `numero`)', () {
    expect(referenceAnnuelle('CERT-', jour, 4, [{'numero': 'CERT-2027-0004'}], maintenant: jour, champ: 'numero'), 'CERT-2027-0005');
    expect(cfaNumeroCertificat(const [], veille), 'CERT-2026-0001');
    expect(cfaNumeroCertificat([{'numero': 'CERT-2026-0001'}], jour), 'CERT-2027-0001');
  });

  test('la numérotation affichée et les 12 mois glissants suivent l\'exercice donné', () {
    expect(cfbNumerotation(2027).first.$2, 'FN-2027-');
    expect(cfbNumerotation(2026).first.$2, 'FN-2026-');
    final g26 = paiMoisGlissants(veille), g27 = paiMoisGlissants(jour);
    expect([g26.first, g26.last], ['janv. 26', 'déce. 26']);
    expect([g27.first, g27.last], ['févr. 26', 'janv. 27']);
  });

  test('l\'exercice du comparatif mensuel est celui qu\'on donne', () {
    final factures = [
      {'date': '2026-12-20', 'montantTTC': 100},
      {'date': '2027-01-15', 'montantTTC': 40},
    ];
    final a = cpcComparaison(cpcExercice2025, factures, exercice: 2026);
    final b = cpcComparaison(cpcExercice2025, factures, exercice: 2027);
    expect(a[11].ca2026, 100);
    expect(a[0].ca2026, 0);
    expect(b[0].ca2026, 40);
    expect(b[11].ca2026, 0);
  });
}
