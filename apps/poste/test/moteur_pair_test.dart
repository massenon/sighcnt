// ADR-0006 : le moteur pair du poste recopie les conflits marqués dans la collection locale `conflitsPair` et les archive (RG-14) quand la décision les lève.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/sync/modale_trancher.dart';
import 'package:sigh_poste/sync/moteur_pair.dart';
import 'package:sigh_poste/sync/transport_pair.dart';
import 'package:flutter/material.dart';
import 'package:sigh_sync/sigh_sync.dart';

void main() {
  test('un conflit entre deux postes est recopié, puis archivé quand une décision le lève', () {
    final m = Magasin({}, 'POSTE', {});
    final pair = FileulPair(ConfigPair(port: 0, relais: 'http://127.0.0.1:1', dbChemin: ':memory:', cleHex: '00' * 32, nom: 'A'));
    pair.base.poserMeta('uuid', 'A');
    final creation = pair.emettre({'collection': 'patients', 'fiche': 'p1', 'type': 'creer', 'champs': {'telephone': '90'}, 'role': 'reception'});
    pair.emettre({'collection': 'patients', 'fiche': 'p1', 'type': 'modifier', 'champs': {'telephone': '91'}, 'vu': {'telephone': creation.hlc}, 'role': 'reception'});
    final distante = OperationPair(id: 'zzz-B', appareil: 'B', hlc: creation.hlc + 5, collection: 'patients', fiche: 'p1', type: 'modifier', champs: {'telephone': '92'}, vu: {'telephone': creation.hlc}, role: 'reception');
    pair.base.exec('INSERT INTO ops(id,appareil,json) VALUES(?,?,?)', [distante.id, 'B', jsonEncode(distante.versJson())]);

    final moteur = MoteurPair.creer(magasin: m, dbChemin: ':memory:', relais: 'http://127.0.0.1:1', cleHex: '00' * 32);
    // le moteur du test lit SA base : on lui donne l'état construit ci-dessus
    final miroir = MoteurPair.pour(pair, m)..recopierConflits();
    expect(m.collection('conflitsPair').actives, hasLength(1));
    expect(m.collection('conflitsPair').actives.single['champ'], 'telephone');
    miroir.recopierConflits();
    expect(m.collection('conflitsPair').actives, hasLength(1), reason: 'rejouer ne duplique pas');

    pair.emettre({'collection': 'patients', 'fiche': 'p1', 'type': 'trancher', 'champs': {'telephone': '92'}, 'role': 'da'});
    miroir.recopierConflits();
    expect(m.collection('conflitsPair').actives, isEmpty, reason: 'la décision lève le conflit : la fiche est archivée, jamais supprimée');
    expect(moteur.etat()['ops'], 0);
  });
  test('le pont pair ne porte que les familles A : ni factures, ni stock, ni lots', () {
    // dérivé de la règle de fusion : une liste recopiée ici divergerait à chaque collection ajoutée
    final a = {for (final e in famillesPair.entries) if (e.value == 'A') e.key}.difference(collectionsPairSansPontPoste);
    expect(a, containsAll(['patients', 'rendezvous']));
    expect(MoteurPair.collectionsDuPont, a);
    final m = Magasin({}, 'POSTE', {});
    final pair = FileulPair(ConfigPair(port: 0, relais: 'http://127.0.0.1:1', dbChemin: ':memory:', cleHex: '00' * 32));
    final pont = MoteurPair.pour(pair, m).pont(role: () => 'da');
    expect(pont.collections, a);
    for (final interdite in ['factures', 'produits', 'lots', 'mouvements', 'ecritures', 'avoirs', 'admissions']) {
      expect(pont.collections.contains(interdite), isFalse, reason: interdite);
    }
  });
  test('le moteur du poste dépose la copie des collections de famille A, rien d\'autre', () {
    final pair = FileulPair(ConfigPair(port: 0, relais: 'http://127.0.0.1:1', dbChemin: ':memory:', cleHex: '00' * 32, collectionsCopie: MoteurPair.collectionsDuPont));
    pair.base.poserMeta('uuid', 'A');
    pair.emettre({'collection': 'patients', 'fiche': 'p1', 'type': 'creer', 'champs': {'nom': 'x'}, 'role': 'reception'});
    pair.emettre({'collection': 'constantes', 'fiche': 'c1', 'type': 'creer', 'champs': {'pouls': 70}, 'role': 'infirmier'});
    pair.preparerCopie();
    pair.preparerCopie();
    final lignes = pair.base.select('SELECT n,charge FROM copie_sortie ORDER BY n');
    expect(lignes, hasLength(1), reason: 'une seule enveloppe : la fiche de famille A, pas les constantes, et pas deux fois la même version');
    expect(jsonDecode(lignes.single['charge'] as String)['collection'], 'patients');
  });
  suitePont();
  main2();
}

// Suite : écritures du poste par le transport pair, et la modale « Conflits à trancher ».
void suitePont() {
  test('le pont d’activité écrit par opérations pair : création, modification en connaissance de cause (aucun conflit), concurrence marquée', () async {
    final pair = FileulPair(ConfigPair(port: 0, relais: 'http://127.0.0.1:1', dbChemin: ':memory:', cleHex: '00' * 32, nom: 'A'));
    pair.base.poserMeta('uuid', 'A');
    final t = TransportPair(pair, () => 'reception');
    await t.ecrire('patients', 'p1', existe: false, champs: {'nom': 'Awa', 'telephone': '90'});
    await t.ecrire('patients', 'p1', existe: true, champs: {'nom': 'Awa', 'telephone': '91'});
    expect(pair.conflits(), isEmpty, reason: 'l’auteur avait vu la version courante');
    final liste = await t.liste('patients');
    expect(liste.single.data['telephone'], '91');
    final vu = pair.etatActuel().fiches['patients/p1']!['hlc'] as Map;
    final autre = OperationPair(id: 'zz-B', appareil: 'B', hlc: (vu['telephone'] as int) + 9, collection: 'patients', fiche: 'p1', type: 'modifier', champs: {'telephone': '92'}, vu: {'telephone': vu['telephone'] as int}, role: 'reception');
    final autre2 = OperationPair(id: 'zz-C', appareil: 'C', hlc: (vu['telephone'] as int) + 10, collection: 'patients', fiche: 'p1', type: 'modifier', champs: {'telephone': '93'}, vu: {'telephone': vu['telephone'] as int}, role: 'reception');
    for (final o in [autre, autre2]) {
      pair.base.exec('INSERT INTO ops(id,appareil,json) VALUES(?,?,?)', [o.id, o.appareil, jsonEncode(o.versJson())]);
    }
    expect(pair.conflits(), hasLength(1), reason: 'deux postes ont écrit le même champ sans se voir');
  });

  testWidgets('la modale tranche par un bouton ; un rôle sans droit reçoit un refus nommé et le conflit reste', (tester) async {
    final m = Magasin({}, 'POSTE', {});
    final pair = FileulPair(ConfigPair(port: 0, relais: 'http://127.0.0.1:1', dbChemin: ':memory:', cleHex: '00' * 32, nom: 'A'));
    pair.base.poserMeta('uuid', 'A');
    final t = TransportPair(pair, () => 'reception');
    unawaited(t.ecrire('patients', 'p1', existe: false, champs: {'telephone': '90'}));
    await tester.pump();
    final h = pair.etatActuel().fiches['patients/p1']!['hlc'] as Map;
    final base = h['telephone'] as int;
    for (final o in [
      OperationPair(id: 'zz-B', appareil: 'B', hlc: base + 9, collection: 'patients', fiche: 'p1', type: 'modifier', champs: {'telephone': '92'}, vu: {'telephone': base - 1}, role: 'reception'),
      OperationPair(id: 'zz-C', appareil: 'C', hlc: base + 10, collection: 'patients', fiche: 'p1', type: 'modifier', champs: {'telephone': '93'}, vu: {'telephone': base - 1}, role: 'reception'),
    ]) {
      pair.base.exec('INSERT INTO ops(id,appareil,json) VALUES(?,?,?)', [o.id, o.appareil, jsonEncode(o.versJson())]);
    }
    final moteur = MoteurPair.pour(pair, m)..recopierConflits();
    expect(m.collection('conflitsPair').actives, hasLength(1));
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    unawaited(ouvrirModaleTrancher(ctx, magasin: m, moteur: moteur, role: 'reception'));
    await tester.pumpAndSettle();
    final id = m.collection('conflitsPair').actives.single['id'];
    await tester.tap(find.byKey(Key('pair:trancher-$id-0')));
    await tester.pumpAndSettle();
    expect(m.collection('conflitsPair').actives, hasLength(1), reason: 'la réception ne tranche pas : refus, conflit intact');
    expect(() => moteur.trancher(m.collection('conflitsPair').actives.single, '90', role: 'reception'), throwsA(isA<Object>()));
    moteur.trancher(m.collection('conflitsPair').actives.single, '90', role: 'da');
    await tester.pumpAndSettle();
    expect(m.collection('conflitsPair').actives, isEmpty);
    expect((await t.liste('patients')).single.data['telephone'], '90');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });
}

void main2() {
  test('droits de la MATRICE RBAC : le caissier ne peut pas écrire un patient, la réception si', () {
    final matrice = MatriceDroits.depuisJson((jsonDecode(File('../../packages/rbac/data/rbac.json').readAsStringSync()) as Map).cast<String, Object?>());
    final droits = droitsDepuisMatrice(peutEditer: matrice.peutEditer, peutAnnuler: matrice.peutAnnuler);
    final pair = FileulPair(ConfigPair(port: 0, relais: 'http://127.0.0.1:1', dbChemin: ':memory:', cleHex: '00' * 32, droits: droits));
    pair.base.poserMeta('uuid', 'A');
    expect(() => pair.emettre({'collection': 'patients', 'fiche': 'p1', 'type': 'creer', 'champs': {'nom': 'x'}, 'role': 'caissier'}), throwsA(isA<Err>()));
    expect(pair.emettre({'collection': 'patients', 'fiche': 'p1', 'type': 'creer', 'champs': {'nom': 'x'}, 'role': 'reception'}).fiche, 'p1');
  });
}
