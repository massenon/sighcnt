// Rejoue le ticket 80 mm engendré par la maquette (prototype_html/build/vecteurs-impression.js) et le total CALCULÉ des états.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

EntreeTicket entree(Map<String, dynamic> o) {
  final d = (o['date'] as List).cast<int>();
  num n(String k) => (o[k] as num?) ?? 0;
  num? nn(String k) => o[k] as num?;
  final m = o['mecef'] as Map<String, dynamic>?;
  return EntreeTicket(
    operateur: o['operateur'] as String,
    numero: o['numero'] as String,
    date: DateTime(d[0], d[1] + 1, d[2], d[3], d[4]),
    typeVente: (o['typeVente'] as String?) ?? 'COMPTANT',
    assureur: o['assureur'] as String?,
    assure: o['assure'] as String?,
    dossier: o['dossier'] as String?,
    lignes: [
      for (final l in (o['lignes'] as List).cast<Map<String, dynamic>>())
        LigneArticle(
            designation: l['designation'] as String,
            quantite: l['quantite'] as num,
            prixUnitaire: l['prixUnitaire'] as num,
            montant: l['montant'] as num)
    ],
    total: n('total'),
    remise: nn('remise'),
    partAssureur: nn('partAssureur'),
    partNonAssuree: nn('partNonAssuree'),
    partPatient: n('partPatient'),
    regle: nn('regle'),
    rendu: nn('rendu'),
    reste: nn('reste'),
    baseMecef: nn('baseMecef'),
    mecef: m == null
        ? null
        : BlocMecef(
            nim: m['nim'] as String?,
            code: m['code'] as String?,
            compteurs: m['compteurs'] as String?,
            heure: m['heure'] as String?),
  );
}

void main() {
  final f = File('test/vecteurs/ticket.json');
  if (!f.existsSync())
    fail(
        'vecteurs absents : lancer `node prototype_html/build/vecteurs-impression.js`');
  final cas = ((jsonDecode(f.readAsStringSync()) as Map)['cas'] as List)
      .cast<Map<String, dynamic>>();
  for (final c in cas) {
    test('ticket : ${c['nom']}', () {
      final dart = lignesTicket(entree(c['entree'] as Map<String, dynamic>))
          .map((l) => l.brut)
          .toList();
      expect(dart, (c['lignes'] as List).cast<String>());
    });
  }

  test(
      'le total d’un état est REFAIT depuis les lignes imprimées, jamais fourni',
      () {
    final t = TableauEtat(colonnes: [
      ColonneEtat(libelle: 'Désignation', valeur: (r) => r['d']),
      ColonneEtat(libelle: 'PU', valeur: (r) => r['pu'], droite: true),
      ColonneEtat(
          libelle: 'Montant',
          valeur: (r) => r['m'],
          droite: true,
          somme: (r) => r['m'] as num),
    ], lignes: const [
      {'d': 'A', 'pu': 1500, 'm': 3000},
      {'d': 'B', 'pu': 150, 'm': 300},
    ]);
    expect(t.pied, ['TOTAL', '', '3 300']);
    // Une colonne de prix unitaires n'est jamais totalisée.
    expect(t.pied![1], '');
    expect(
        const TableauEtat(
            colonnes: [ColonneEtat(libelle: 'X', valeur: _x)], lignes: []).pied,
        isNull);
  });
}

Object? _x(Map<String, Object?> r) => r['x'];
