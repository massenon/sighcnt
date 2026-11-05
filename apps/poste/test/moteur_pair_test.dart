// ADR-0006 : le moteur pair du poste recopie les conflits marqués dans la collection locale `conflitsPair` et les archive (RG-14) quand la décision les lève.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/sync/moteur_pair.dart';
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
}
