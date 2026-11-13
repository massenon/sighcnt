import 'dart:convert';

import 'package:sigh_domaine/sigh_domaine.dart' show synchroClesFileul, synchroVerifierIndicateurs;
import 'package:sigh_sync/src/commun.dart';
import 'package:sigh_sync/src/mere.dart';
import 'package:test/test.dart';

/// Lot RLS-SYNC : ce que la VRAIE mère Dart publie de ses fileuls au relais, lu sur sa propre base. Compteurs et horodatages seulement.
void main() {
  late Mere m;
  setUp(() async => m = await Mere.creer(ConfigMere(port: 0, dbChemin: ':memory:')));

  Future<void> poste(String uuid, String? etiquette, {int? contact, int seq = 0, String role = 'fileul', String etat = 'actif'}) =>
      m.base.exec('INSERT INTO appareils(uuid,etiquette,role,etat,dernier_contact,dernier_seq) VALUES(?,?,?,?,?,?)', [uuid, etiquette, role, etat, contact, seq]);

  Future<void> operation(int n, String appareil, {String collection = 'patients', String fiche = 'x'}) => m.base.exec(
      'INSERT INTO operations(id,appareil,epoch,hlc,collection,fiche,type,champs,famille) VALUES(?,?,?,?,?,?,?,?,?)', ['op$n', appareil, 1, n, collection, '$fiche$n', 'creer', '{}', 'A']);

  test('un fileul actif est publié avec son nom technique, son contact, son retard, ses conflits et ses demandes', () async {
    final t = maintenantMs();
    await poste('p1', 'Poste caisse', contact: t - 1000, seq: 3);
    for (var i = 1; i <= 10; i++) {
      await operation(i, 'p1');
    }
    await m.base.exec("INSERT INTO conflits(collection,fiche,champ,a,b,appareil,etat) VALUES('patients','x','telephone','1','2','p1','ouvert')");
    await m.base.exec("INSERT INTO conflits(collection,fiche,champ,a,b,appareil,etat) VALUES('patients','x','nom','1','2','p1','resolu')");
    // Deux demandes en attente déposées par p1, une tranchée, une archivée. `demandePar` porte un nom de personne : il ne doit jamais sortir.
    for (final (i, etat, statut) in [(1, 'en_attente', 'actif'), (2, 'en_attente', 'actif'), (3, 'appliquee', 'actif'), (4, 'en_attente', 'archive')]) {
      await m.base.exec('INSERT INTO fiches(collection,id,data,fieldseq,archive) VALUES(?,?,?,?,0)',
          ['demandesImport', 'DIM$i', jsonEncode({'etat': etat, 'statut': statut, 'demandePar': 'KOUASSI Awa', 'jeu': 'patients'}), '{}']);
      await operation(100 + i, 'p1', collection: 'demandesImport', fiche: 'DIM$i-');
      await m.base.exec("UPDATE operations SET fiche=? WHERE id=?", ['DIM$i', 'op${100 + i}']);
    }
    final f = (await m.pont.fileulsPublies())!;
    expect(f, hasLength(1));
    expect(f.first.keys.toList(), synchroClesFileul);
    expect(f.first['poste'], 'Poste caisse');
    expect(f.first['dernierContact'], t - 1000);
    expect(f.first['retardJournal'], 14 - 3, reason: '10 opérations de patients + 4 demandes = 14 ; le poste en a repris 3');
    expect(f.first['conflitsOuverts'], 1, reason: 'le conflit résolu ne compte pas');
    expect(f.first['demandesImportEnAttente'], 2, reason: 'ni la demande tranchée, ni l\'archivée');
    expect(synchroVerifierIndicateurs({'fileuls': f}), isNull);
    expect(jsonEncode(f), isNot(contains('KOUASSI')));
  });

  test('un poste jamais vu a un contact et un retard null, jamais zéro', () async {
    await poste('p2', 'Neuf');
    await operation(1, 'p2');
    final f = (await m.pont.fileulsPublies())!.single;
    expect(f['dernierContact'], isNull);
    expect(f['retardJournal'], isNull);
  });

  test('les mobiles et les postes révoqués ne sont pas des fileuls ; une étiquette qui n\'est pas un nom technique est remplacée', () async {
    await poste('m1', 'Mobile', role: 'mobile', contact: 1);
    await poste('p3', 'Ancien', etat: 'revoque', contact: 1);
    await poste('ab12cd34-ef56', 'Awa <awa@exemple.bj>', contact: 5);
    final f = (await m.pont.fileulsPublies())!;
    expect(f.map((x) => x['poste']), ['Poste ab12cd34']);
  });

  test('l\'état est recalculé au plus toutes les deux secondes', () async {
    await poste('p1', 'A', contact: 5);
    expect((await m.pont.fileulsPublies())!, hasLength(1));
    await poste('p2', 'B', contact: 5);
    expect((await m.pont.fileulsPublies())!, hasLength(1), reason: 'la valeur calculée il y a moins de 2 s est republiée telle quelle');
  });
}
