// Rejoue les vecteurs des PV de réception (prototype_html/build/vecteurs-m7-achats.js) : les écrans RÉELS pilotés dans Chrome.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

List<Map<String, Object?>> liste(Object? v) => ((v ?? const []) as List)
    .map((x) => (x as Map).cast<String, Object?>())
    .toList();

/// Le magasin ne garde pas les champs nuls : absent et nul se valent ; les chaînes vides, elles, sont écrites.
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
  final f = File('test/vecteurs/pv_reception.json');
  if (!f.existsSync()) {
    fail(
        'vecteurs absents : lancer `node prototype_html/build/vecteurs-m7-achats.js`');
  }
  final doc = (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>();
  final cas = liste(doc['cas']);

  test('douze situations ont été engendrées sur les deux écrans',
      () => expect(cas.length, greaterThanOrEqualTo(12)));

  for (final c in cas) {
    final e = (c['entree']! as Map).cast<String, Object?>();
    final s = (c['sortie']! as Map).cast<String, Object?>();
    final nature = '${c['nature']}';

    test('${c['nom']}', () {
      final livraisons = liste(e['livraisons']);
      final produits = liste(e['produits']);
      final refs = [for (final r in (e['references']! as List)) '$r'];
      final saisie = (e['saisie']! as Map).cast<String, Object?>();
      if (s['pv'] == null) {
        final messages = liste(s['messages']);
        try {
          etablirPv(
              nature: nature,
              saisie: saisie,
              livraisons: livraisons,
              produits: produits,
              references: refs);
          fail('le PV aurait dû être refusé');
        } on RefusPv catch (r) {
          expect(r.motif, messages.isEmpty ? isNull : messages.first['message'],
              reason: 'un champ obligatoire vide ne produit aucun message global');
        }
        return;
      }
      final pv = etablirPv(
          nature: nature,
          saisie: saisie,
          livraisons: livraisons,
          produits: produits,
          references: refs);
      memes(pv, s['pv'], 'pv');
    });

    test('${c['nom']} — le bon proposé', () {
      final m = (c['modale']! as Map).cast<String, Object?>();
      final options = [
        for (final l in livraisonsPourPv(
            liste((c['entree']! as Map)['livraisons']),
            nature,
            liste((c['entree']! as Map)['produits'])))
          '${l['reference']} — ${l['fournisseurNom']}'
      ];
      expect(options, (m['optionsLivraison']! as List).cast<String>());
    });
  }

  test(
      'la série est lue sur les PV EXISTANTS (archivés compris) et repart à 1 chaque année (écart E17 corrigé dans la maquette)',
      () {
    expect(referencePvSuivante('consommables', '2026-10-30', const []),
        'PV-CON-2026-0001');
    expect(
        referencePvSuivante('reactifs', '2026-10-30',
            ['PV-REA-2026-0007', 'PV-REA-2026-0009', 'PV-CON-2026-0042']),
        'PV-REA-2026-0010');
    expect(
        referencePvSuivante('reactifs', '2027-01-02', ['PV-REA-2026-0009']),
        'PV-REA-2027-0001');
  });

  test('la nature se lit sur la catégorie du produit ; un article hors catalogue est un consommable',
      () {
    final produits = [
      {'id': 'A', 'categorie': 'reactif'},
      {'id': 'B', 'categorie': 'conso_labo'},
      {'id': 'C', 'categorie': 'conso_medical'},
    ];
    expect(estReactif('A', produits), isTrue);
    expect(estReactif('B', produits), isTrue);
    expect(estReactif('C', produits), isFalse);
    expect(estReactif('INCONNU', produits), isFalse);
  });

  group('registres', () {
    for (final r in liste(doc['registres'])) {
      test('indicateurs du registre « ${r['nature']} » = recompte des PV', () {
        final res = resumerPv(liste(r['pvs']));
        expect([
          for (final k in (r['kpis']! as List))
            [(k as List)[0], '${k[1]}']
        ], [
          ['PV établis', nombre(res.etablis)],
          ['Conformes', nombre(res.conformes)],
          ['Avec réserves', nombre(res.avecReserves)],
          ['Non conformes', nombre(res.nonConformes)],
        ]);
      });
    }
    test('sans livraison de la nature : refus nommé, aucune modale', () {
      for (final x in liste(doc['sansLivraison'])) {
        final m = liste(x['messages']);
        expect(m.single['message'], messageSansLivraison('${x['nature']}'));
        expect(x['modaleOuverte'], isFalse);
      }
    });
  });
}
