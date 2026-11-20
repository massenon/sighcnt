import 'dart:convert';
import 'dart:math';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_sync/src/copie_mere.dart';
import 'package:sigh_sync/src/mere.dart';
import 'package:sigh_sync/src/pair.dart';
import 'package:sigh_sync/src/ordre_copie.dart';
import 'package:test/test.dart';

/// PRD relais consultable : l'ordre global des versions de la copie, et la copie INCRÉMENTALE de la mère (seules les fiches touchées sont recalculées, et le résultat
/// est celui du calcul complet).
void main() {
  OperationPair op(String id, String app, int hlc, String fiche, String type, Map<String, Object?> champs, {Map<String, Object?>? vu, int? seq}) =>
      OperationPair(id: id, appareil: app, hlc: hlc, collection: 'patients', fiche: fiche, type: type, champs: champs, vu: vu, role: 'reception', seq: seq);

  test('une version qui sait plus (plus d\'opérations connues) a un ordre plus grand, quel que soit l\'appareil qui la dépose', () {
    final a = op('a', 'F1', 10, 'p', 'creer', {'t': '1'});
    final b = op('b', 'F1', 20, 'p', 'modifier', {'t': '2'}, vu: {'t': 10});
    final c = op('c', 'F2', 15, 'p', 'modifier', {'u': 'x'}, vu: {});
    final v1 = chargeCopieDeFiche('patients', 'p', [a, b])!;
    final v2 = chargeCopieDeFiche('patients', 'p', [a, c])!;
    final v3 = chargeCopieDeFiche('patients', 'p', [a, b, c])!;
    expect(v3['ordre'], [3, 20, 'F1', 'b']);
    expect(comparerOrdreCopie((v3['ordre'] as List), (v1['ordre'] as List)), greaterThan(0));
    expect(comparerOrdreCopie((v3['ordre'] as List), (v2['ordre'] as List)), greaterThan(0));
    expect(comparerOrdreCopie((v1['ordre'] as List), (v2['ordre'] as List)), isNot(0), reason: 'deux postes qui ne se sont pas vus se départagent sans égalité');
    expect(comparerOrdreCopie(null, (v1['ordre'] as List)), lessThan(0), reason: 'une ancienne enveloppe sans ordre est la plus ancienne');
  });

  test('le seq de la mère est porté à titre informatif et ne change pas l\'ordre', () {
    final a = op('a', 'F1', 10, 'p', 'creer', {'t': '1'});
    final avec = chargeCopieDeFiche('patients', 'p', [op('a', 'F1', 10, 'p', 'creer', {'t': '1'}, seq: 7)])!;
    final sans = chargeCopieDeFiche('patients', 'p', [a])!;
    expect(avec['seq'], 7);
    expect(sans.containsKey('seq'), isFalse);
    expect(avec['ordre'], sans['ordre']);
  });

  test('le contenu seul décide de redéposer (jamais l\'ordre ni le seq)', () {
    final a = op('a', 'F1', 10, 'p', 'creer', {'t': '1'});
    final sans = chargeCopieDeFiche('patients', 'p', [a])!;
    final autre = chargeCopieDeFiche('patients', 'p', [a, op('z', 'F2', 5, 'p', 'modifier', {'t': '1'}, vu: {'t': 10})])!;
    expect(jsonEncode(contenuCopie(sans)), jsonEncode(contenuCopie(autre)), reason: 'même contenu : rien à redéposer même si le poste sait davantage');
  });

  test('l\'ordre est total : lexicographique, transitif, antisymétrique (propriété sur des ordres tirés au hasard)', () {
    final r = Random(7);
    List<Object?> tire() => [r.nextInt(3), r.nextInt(3), ['A', 'B'][r.nextInt(2)], 'o${r.nextInt(3)}'];
    for (var i = 0; i < 300; i++) {
      final x = tire(), y = tire(), z = tire();
      expect(comparerOrdreCopie(x, y), -comparerOrdreCopie(y, x));
      if (comparerOrdreCopie(x, y) <= 0 && comparerOrdreCopie(y, z) <= 0) expect(comparerOrdreCopie(x, z), lessThanOrEqualTo(0));
    }
  });

  test('copie incrémentale de la mère : par tours, seules les fiches touchées partent, et l\'ensemble égale le calcul complet', () async {
    final m = await Mere.creer(ConfigMere(port: 0, dbChemin: ':memory:'));
    final copie = CopieMere(m);
    await copie.tourPreparer();
    final r = Random(11);
    final toutes = <OperationPair>[];
    final versRetenues = <String, Map<String, Object?>>{};
    var h = 100;
    Future<void> poser(OperationPair o) async {
      toutes.add(o);
      await m.base.exec('INSERT INTO pair_ops(id,json) VALUES(?,?)', [o.id, jsonEncode(o.versJson())]);
    }
    Future<Set<String>> tour() async {
      await copie.preparer();
      final lignes = await m.base.select('SELECT n,enveloppe FROM copie_mere_sortie ORDER BY n');
      final touchees = <String>{};
      for (final l in lignes.where((x) => !versRetenues.containsKey('n${x['n']}'))) {
        versRetenues['n${l['n']}'] = {};
        final env = jsonDecode(l['enveloppe'] as String) as Map;
        final charge = await m.pont.env.dechiffrer(env.cast<String, Object?>());
        for (final f in (charge['lot'] as List).cast<Map>()) {
          final k = '${f['collection']}/${f['fiche']}';
          touchees.add(k);
          versRetenues[k] = f.cast<String, Object?>();
        }
      }
      return touchees;
    }

    // tour 1 : 30 fiches ; tour 2 : 3 fiches seulement modifiées ; tour 3 : rien
    for (var i = 0; i < 30; i++) {
      await poser(op('c$i', 'F1', h++, 'p$i', 'creer', {'nom': 'N$i', 'tel': '$i'}));
    }
    expect((await tour()).length, 30);
    for (final i in [3, 11, 20]) {
      await poser(op('m$i', ['F1', 'F2'][r.nextInt(2)], h++, 'p$i', 'modifier', {'tel': 'x$i'}, vu: {'tel': 100 + i}));
    }
    final t2 = await tour();
    expect(t2, {'patients/p3', 'patients/p11', 'patients/p20'}, reason: 'seules les fiches touchées sont recalculées et redéposées');
    expect((await tour()), isEmpty, reason: 'aucune opération nouvelle : rien à déposer');
    // l'ensemble retenu = le calcul complet
    final complet = etatPair(toutes, droits: m.pair.droits).fiches;
    for (final e in complet.entries) {
      expect(versRetenues[e.key]!['data'], e.value['data'], reason: e.key);
      expect(versRetenues[e.key]!['archive'], e.value['archive'] == true);
    }
  });

  test('copie incrémentale du poste, répartie sur plusieurs tours : une seule version par fiche, égale au calcul complet', () {
    final pair = FileulPair(ConfigPair(port: 0, relais: 'http://127.0.0.1:1', dbChemin: ':memory:', cleHex: '00' * 32, collectionsCopie: {'patients'}, droits: (_) => true));
    pair.base.poserMeta('uuid', 'F1');
    const fiches = 300;
    final total = FileulPair.opsParTour * 2 + 500; // oblige au moins trois tours d'indexation
    pair.base.tx(() {
      for (var i = 0; i < total; i++) {
        final creation = i < fiches;
        final o = OperationPair(id: 'o$i', appareil: i.isEven ? 'F1' : 'F2', hlc: 1000 + i, collection: 'patients', fiche: 'p${i % fiches}', type: creation ? 'creer' : 'modifier', role: 'x', champs: creation ? {'nom': 'N$i', 't': '0'} : {'t': '$i'}, vu: creation ? null : {'t': 1000 + (i % fiches)});
        pair.base.exec('INSERT INTO ops(id,appareil,json) VALUES(?,?,?)', [o.id, o.appareil, jsonEncode(o.versJson())]);
      }
    });
    var tours = 0;
    do {
      pair.preparerCopie();
      tours++;
    } while (pair.copieEnRetard && tours < 100);
    expect(tours, greaterThanOrEqualTo(3));
    final file = pair.base.select('SELECT charge FROM copie_sortie ORDER BY n').map((r) => jsonDecode(r['charge'] as String) as Map).toList();
    expect(file, hasLength(fiches), reason: 'une fiche n\'est recalculée qu\'une fois TOUTES les opérations indexées : aucune version intermédiaire déposée');
    final complet = pair.etatActuel().fiches;
    for (final c in file) {
      final e = complet['patients/${c['fiche']}']!;
      expect(c['data'], e['data'], reason: '${c['fiche']}');
    }
    expect(file.every((c) => (c['ordre'] as List)[0] >= total ~/ fiches), isTrue, reason: 'chaque version porte le nombre d\'opérations connues de sa fiche');
    pair.preparerCopie();
    expect(pair.base.select('SELECT COUNT(*) AS n FROM copie_sortie').first['n'], fiches, reason: 'plus rien de nouveau : rien de redéposé');
  });
}
