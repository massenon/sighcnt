// Rejoue les vecteurs de la modale « Nouvelle opération » de m8-remboursements (prototype_html/build/vecteurs-remboursements.js).
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

List<Map<String, Object?>> liste(Object? v) => ((v ?? const []) as List)
    .map((x) => (x as Map).cast<String, Object?>())
    .toList();

/// Le magasin ne garde pas les champs nuls : absent et vide-nul se valent ; les chaînes vides, elles, sont écrites.
void memes(Object? obtenu, Object? attendu, String chemin,
    {Set<String> ignorer = const {}}) {
  if (attendu is Map) {
    final o = (obtenu as Map?) ?? const {};
    for (final k in {...attendu.keys, ...o.keys}) {
      if (ignorer.contains(k)) continue;
      memes(o[k], attendu[k], '$chemin.$k', ignorer: ignorer);
    }
  } else if (attendu is List) {
    final o = obtenu as List;
    expect(o.length, attendu.length, reason: '$chemin : longueur');
    for (var i = 0; i < attendu.length; i++) {
      memes(o[i], attendu[i], '$chemin[$i]', ignorer: ignorer);
    }
  } else if (attendu is num) {
    expect((obtenu as num).toDouble(), attendu.toDouble(), reason: chemin);
  } else {
    expect(obtenu, attendu, reason: chemin);
  }
}

void main() {
  final f = File('test/vecteurs/remboursements.json');
  if (!f.existsSync()) {
    fail('vecteurs absents : lancer `node prototype_html/build/vecteurs-remboursements.js`');
  }
  final cas = liste((jsonDecode(f.readAsStringSync()) as Map)['cas']);
  test('au moins dix situations ont été engendrées',
      () => expect(cas.length, greaterThanOrEqualTo(10)));

  for (final c in cas) {
    final e = (c['entree']! as Map).cast<String, Object?>();
    test('${e['nom']}', () {
      final fac = (e['facture']! as Map).cast<String, Object?>();
      final saisie = {
        'factureId': fac['id'],
        'motifAvoir': '',
        'refacturation': '',
        ...(e['saisie']! as Map).cast<String, Object?>(),
      };
      final attendues = liste(c['remboursements']);
      OperationEnregistree enregistrer() => enregistrerOperation(
          saisie: saisie,
          facture: fac,
          remboursements: liste(e['remboursements']),
          avoirs: liste(e['avoirs']),
          idAvoir: 'AVR-TEST',
          jour: e['jour']! as String,
          utilisateur: 'BASSONGUI Chabi Séko');
      if (attendues.isEmpty) {
        // Refus NOMMÉ (champ manquant, montant nul, plafond cumulé) : rien n'est écrit.
        expect(enregistrer, throwsA(isA<RefusOperation>()));
        return;
      }
      final r = enregistrer();
      memes(r.remboursement, attendues.single, 'remboursement',
          ignorer: const {'avoirId'});
      // B10 : plus de pièce négative ; la nature « Facture avoir » écrit UN avoir dans la collection `avoirs`.
      final avoirsCrees = liste(c['avoirsCrees']);
      expect(r.avoir == null, avoirsCrees.isEmpty);
      if (avoirsCrees.isNotEmpty) {
        memes(r.avoir!.avoir, avoirsCrees.single, 'avoir');
        final obtenues = [...r.avoir!.ecritures]
          ..sort((a, b) => '${a['compte']}'.compareTo('${b['compte']}'));
        final attEcr = liste(c['ecrituresCreees'])
          ..sort((a, b) => '${a['compte']}'.compareTo('${b['compte']}'));
        memes(obtenues, attEcr, 'ecritures', ignorer: const {'pieceId'});
        expect(r.remboursement['avoirId'], 'AVR-TEST');
        expect(r.remboursement['avoirNumero'], avoirsCrees.single['reference']);
        expect(r.avoir!.montantAvoirs,
            ((c['factureAvoirs']! as Map)['montantAvoirs']! as num).toDouble());
      } else {
        expect(r.remboursement.containsKey('avoirId'), isFalse);
      }
      expect(liste(c['facturesCreees']), isEmpty,
          reason: 'B10 : aucune pièce négative dans `factures`');
      final patch = (c['facturePatch']! as Map).cast<String, Object?>();
      if (r.patchFacture != null) {
        memes(r.patchFacture, {
          'statutPaiement': patch['statutPaiement'],
          'statutMecef': patch['statutMecef'],
          'annulee': patch['annulee'],
        }, 'patch');
      } else {
        // Aucun effet sur la facture : elle garde son état d'origine.
        expect(patch['statutPaiement'], fac['statutPaiement']);
        expect(patch['statutMecef'], fac['statutMecef']);
        expect(patch['annulee'], isNull);
      }
    });
  }

  test('E10 : un montant nul est refusé en le nommant', () {
    final cm = cas.firstWhere(
        (c) => '${(c['entree']! as Map)['nom']}'.startsWith('montant nul'));
    final e = (cm['entree']! as Map).cast<String, Object?>();
    final fac = (e['facture']! as Map).cast<String, Object?>();
    expect(
        () => enregistrerOperation(
            saisie: {
              'factureId': fac['id'],
              ...(e['saisie']! as Map).cast<String, Object?>()
            },
            facture: fac,
            remboursements: const []),
        throwsA(isA<RefusOperation>().having((r) => r.motif, 'motif',
            'Le montant doit être strictement supérieur à 0 FCFA.')));
  });

  test('les factures proposées sont les réglées, les plus récentes d\'abord', () {
    final l = facturesConcernables([
      {'id': 'a', 'date': '2026-01-01', 'montantPaye': 0, 'statutPaiement': 'impayee'},
      {'id': 'b', 'date': '2026-01-03', 'montantPaye': 10, 'statutPaiement': 'partielle'},
      {'id': 'c', 'date': '2026-01-02', 'montantPaye': 0, 'statutPaiement': 'soldee'},
    ]);
    expect(l.map((x) => x['id']), ['b', 'c']);
  });
}
