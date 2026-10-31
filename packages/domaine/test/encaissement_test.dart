// Rejoue les SÉQUENCES de versements engendrées par la maquette (prototype_html/build/vecteurs-encaissement.js).
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

Map<String, Object?> m(Object? v) => (v! as Map).cast<String, Object?>();
List<Map<String, Object?>> l(Object? v) =>
    ((v ?? const []) as List).map(m).toList();

void main() {
  testsCorrections();
  final f = File('test/vecteurs/encaissement.json');
  if (!f.existsSync())
    fail(
        'vecteurs absents : lancer `node prototype_html/build/vecteurs-encaissement.js`');
  final cas = l((jsonDecode(f.readAsStringSync()) as Map)['cas']);

  for (final c in cas) {
    test('${c['nom']}', () {
      var facture = m(c['facture']);
      final journal = l(c['ecrituresExistantes']);
      var i = 0;
      for (final etape in l(c['etapes'])) {
        i++;
        final opts = m(etape['opts']);
        final date = l(etape['ecritures']).isEmpty
            ? '2026-10-30'
            : '${l(etape['ecritures']).first['date']}';
        final r = encaisser(
          facture,
          lignes: (opts['lignes'] as List?)?.cast<String>(),
          montant: opts['montant'] as num?,
          mode: opts['mode'] as String?,
          aujourdhui: date,
          maintenant: '2026-10-30T10:00:00.000Z',
          ecritures: journal,
        );
        journal.addAll(r.ecritures.map((e) => {
              'numero': e['numero'],
              'pieceId': e['pieceId'],
              'compte': e['compte'],
              'statut': e['statut'],
              'journal': e['journal']
            }));
        final raison = 'versement $i';
        // E2 (corrigé le 31/10/2026) : un versement refusé NOMME le défaut, ne change rien et n'écrit rien.
        expect(r.refus, etape['refus'], reason: '$raison : refus');
        if (r.refus != null) {
          expect(r.montantRegle, 0, reason: raison);
          expect(r.ecritures, isEmpty, reason: raison);
          expect(r.lignesReglees, isEmpty, reason: raison);
          expect(r.restantDu, (etape['restantDu'] as num).toDouble(), reason: raison);
          continue;
        }
        expect(r.deja, etape['deja'], reason: raison);
        expect(r.lignesReglees, etape['lignesReglees'], reason: raison);
        expect(r.montantRegle, (etape['montantRegle'] as num?)?.toDouble(),
            reason: raison);
        expect(r.restantDu, (etape['restantDu'] as num?)?.toDouble(),
            reason: raison);

        final attendu = m(etape['facture']);
        final fa = r.deja ? facture : r.facture;
        for (final k in ['montantPaye', 'reliquat']) {
          expect(
              (fa[k] as num?)?.toDouble() ?? 0, (attendu[k] as num).toDouble(),
              reason: '$raison : $k');
        }
        for (final k in ['modePaiement', 'statutPaiement', 'statutMecef']) {
          expect(fa[k] ?? attendu[k], attendu[k], reason: '$raison : $k');
        }
        if (!r.deja) {
          expect((fa['baseMecef'] as num).toDouble(),
              (attendu['baseMecef'] as num).toDouble(),
              reason: '$raison : baseMecef');
          final dr = m(fa['dernierReglement']),
              ar = m(attendu['dernierReglement']);
          expect((dr['montant'] as num).toDouble(),
              (ar['montant'] as num).toDouble(),
              reason: '$raison : dernier règlement');
          expect(dr['mode'], ar['mode']);
          expect(dr['lignes'], ar['lignes']);
        }
        final lignesApres = l(fa['lignes']);
        final lignesAttendues = l(attendu['lignes']);
        expect(lignesApres.length, lignesAttendues.length);
        for (var k = 0; k < lignesApres.length; k++) {
          expect(lignesApres[k]['id'], lignesAttendues[k]['id']);
          expect(lignesApres[k]['statutPaiement'],
              lignesAttendues[k]['statutPaiement'],
              reason: '$raison : ligne ${lignesApres[k]['id']}');
          expect((lignesApres[k]['montantRegle'] as num?)?.toDouble(),
              (lignesAttendues[k]['montantRegle'] as num?)?.toDouble(),
              reason: '$raison : montantRegle');
        }

        // Écritures : mêmes comptes, mêmes montants, même numéro — comparées par compte (l'ordre n'a pas de sens comptable).
        final ecr = {for (final e in r.ecritures) e['compte']: e};
        final att = {for (final e in l(etape['ecritures'])) e['compte']: e};
        expect(ecr.keys.toSet(), att.keys.toSet(), reason: '$raison : comptes');
        for (final compte in att.keys) {
          for (final k in [
            'numero',
            'date',
            'journal',
            'libelle',
            'statut',
            'origine',
            'pieceNumero'
          ]) {
            expect(ecr[compte]![k], att[compte]![k],
                reason: '$raison : $compte $k');
          }
          expect((ecr[compte]!['debit'] as num).toDouble(),
              (att[compte]!['debit'] as num).toDouble(),
              reason: '$raison : $compte débit');
          expect((ecr[compte]!['credit'] as num).toDouble(),
              (att[compte]!['credit'] as num).toDouble(),
              reason: '$raison : $compte crédit');
        }
        // RG-10, sur CHAQUE écriture produite.
        final d = r.ecritures.fold(0.0, (a, e) => a + (e['debit']! as num));
        final cr = r.ecritures.fold(0.0, (a, e) => a + (e['credit']! as num));
        expect(d, cr, reason: '$raison : débit = crédit (RG-10)');

        facture = r.deja ? facture : r.facture;
      }
    });
  }

  test('l\'entrée n\'est jamais modifiée (le poste décide quand écrire)', () {
    final fac = {
      'id': 'F1',
      'numero': 'FC-2026-00001',
      'partPatient': 1000,
      'montantTTC': 1000,
      'montantPaye': 0,
      'lignes': [
        {'id': 'L1', 'partPatient': 1000, 'statutPaiement': 'du'}
      ],
    };
    final avant = jsonEncode(fac);
    encaisser(fac, lignes: ['L1'], aujourdhui: '2026-10-30', maintenant: 'x');
    expect(jsonEncode(fac), avant);
  });
}

void testsCorrections() {
  Map<String, Object?> facture() => {
        'id': 'F9',
        'numero': 'FC-2026-00009',
        'patient': 'T',
        'assureur': 'ASS-A',
        'partPatient': 3000,
        'partAssureur': 14000,
        'montantTTC': 17000,
        'montantPaye': 0,
        'lignes': [
          {'id': 'A1', 'partPatient': 2000, 'statutPaiement': 'du'},
          {'id': 'A2', 'partPatient': 1000, 'statutPaiement': 'du'},
        ],
      };

  test(
      'E1 corrigé : la créance assureur est constatée UNE fois sur la vie de la facture (706 = facturé, 411 = part assureur, 571 = part patient)',
      () {
    final journal = <Map<String, Object?>>[];
    var f = facture();
    final toutes = <Map<String, Object?>>[];
    for (final ligne in ['A1', 'A2']) {
      final r = encaisser(f,
          lignes: [ligne],
          aujourdhui: '2026-10-30',
          maintenant: 'x',
          ecritures: journal);
      journal.addAll(r.ecritures);
      toutes.addAll(r.ecritures);
      f = r.facture;
    }
    double somme(String compte, String sens) => toutes
        .where((e) => e['compte'] == compte)
        .fold(0.0, (a, e) => a + (e[sens]! as num));
    expect(somme('411110', 'debit'), 14000);
    expect(somme('571000', 'debit'), 3000);
    expect(somme('706000', 'credit'), 17000);
    expect(toutes.fold(0.0, (a, e) => a + (e['debit']! as num)),
        toutes.fold(0.0, (a, e) => a + (e['credit']! as num)));
  });

  test(
      'E3 corrigé : série annuelle (millésime de la date, rang suivant), reprise par les versements d\'une même facture',
      () {
    final journal = <Map<String, Object?>>[
      {
        'numero': 'CAI-2026-00007',
        'pieceId': 'AUTRE',
        'compte': '571000',
        'journal': 'CAI'
      },
      {
        'numero': 'CAI-2027-00002',
        'pieceId': 'AUTRE2',
        'compte': '571000',
        'journal': 'CAI'
      },
    ];
    final r1 = encaisser(facture(),
        lignes: ['A1'],
        aujourdhui: '2026-10-30',
        maintenant: 'x',
        ecritures: journal);
    expect(r1.ecritures.first['numero'], 'CAI-2026-00008');
    journal.addAll(r1.ecritures);
    final r2 = encaisser(r1.facture,
        lignes: ['A2'],
        aujourdhui: '2026-10-31',
        maintenant: 'x',
        ecritures: journal);
    expect(r2.ecritures.first['numero'], 'CAI-2026-00008',
        reason: 'même facture, même pièce');
    final autre = {...facture(), 'id': 'F10', 'numero': 'FC-2027-00009'};
    final r3 = encaisser(autre,
        lignes: ['A1'],
        aujourdhui: '2027-01-05',
        maintenant: 'x',
        ecritures: journal);
    expect(r3.ecritures.first['numero'], 'CAI-2027-00003',
        reason: 'millésime de la date, plus 2026 en dur');
  });
}
