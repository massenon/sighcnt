// ADR-0006 : les droits de l'échange entre pairs viennent de la matrice RBAC engendrée, pas d'une table écrite à part.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

void main() {
  final m = MatriceDroits.depuisJson((jsonDecode(File('../rbac/data/rbac.json').readAsStringSync()) as Map).cast<String, Object?>());
  final droits = droitsDepuisMatrice(peutEditer: m.peutEditer, peutAnnuler: m.peutAnnuler);
  OperationPair op(String collection, String type, String? role) => OperationPair(id: 'x', appareil: 'a', hlc: 1, collection: collection, fiche: 'f', type: type, role: role);

  test('écrire = éditer l\'écran de la collection', () {
    expect(droits(op('patients', 'creer', 'reception')), isTrue);
    expect(droits(op('patients', 'modifier', 'medecin')), isTrue);
    expect(droits(op('patients', 'modifier', 'direction')), isFalse, reason: 'la Direction lit le répertoire sans l\'écrire');
    expect(droits(op('patients', 'modifier', 'caissier')), isFalse);
    expect(droits(op('rendezvous', 'creer', 'caissier')), isFalse, reason: 'écran fermé au caissier');
  });

  test('archiver demande le droit d\'annuler, que la réception n\'a pas', () {
    expect(droits(op('patients', 'archiver', 'reception')), isFalse);
    expect(droits(op('patients', 'archiver', 'da')), isTrue);
  });

  test('trancher et valider sont institutionnels, sans écran requis', () {
    for (final r in ['da', 'direction', 'admin', 'mere']) {
      expect(droits(op('patients', 'trancher', r)), isTrue, reason: r);
    }
    expect(droits(op('patients', 'trancher', 'reception')), isFalse);
    expect(droits(op('besoins', 'valider', 'da')), isTrue);
    expect(droits(op('besoins', 'valider', 'medecin')), isFalse);
  });

  test('un rôle inconnu, un rôle absent ou une collection sans écran désigné : refus', () {
    expect(droits(op('patients', 'creer', 'inconnu')), isFalse);
    expect(droits(op('patients', 'creer', null)), isFalse);
    expect(droits(op('collection_nouvelle', 'creer', 'admin')), isFalse);
  });

  test('toute collection de la règle de fusion désigne un écran qui existe dans la matrice', () {
    for (final c in famillesPair.keys) {
      final e = ecranParCollectionPair[c];
      expect(e, isNotNull, reason: '$c sans écran');
      expect(m.ecransVisibles('admin').contains(e), isTrue, reason: '$c : écran $e absent de la matrice');
    }
  });
}
