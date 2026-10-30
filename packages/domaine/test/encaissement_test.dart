// Rejoue les SÉQUENCES de versements engendrées par la maquette (prototype_html/build/vecteurs-encaissement.js).
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

Map<String, Object?> m(Object? v) => (v! as Map).cast<String, Object?>();
List<Map<String, Object?>> l(Object? v) => ((v ?? const []) as List).map(m).toList();

void main() {
  final f = File('test/vecteurs/encaissement.json');
  if (!f.existsSync()) fail('vecteurs absents : lancer `node prototype_html/build/vecteurs-encaissement.js`');
  final cas = l((jsonDecode(f.readAsStringSync()) as Map)['cas']);

  for (final c in cas) {
    test('${c['nom']}', () {
      var facture = m(c['facture']);
      var i = 0;
      for (final etape in l(c['etapes'])) {
        i++;
        final opts = m(etape['opts']);
        final date = l(etape['ecritures']).isEmpty ? '2026-10-30' : '${l(etape['ecritures']).first['date']}';
        final r = encaisser(
          facture,
          lignes: (opts['lignes'] as List?)?.cast<String>(),
          montant: opts['montant'] as num?,
          mode: opts['mode'] as String?,
          aujourdhui: date,
          maintenant: '2026-10-30T10:00:00.000Z',
        );
        final raison = 'versement $i';
        expect(r.deja, etape['deja'], reason: raison);
        expect(r.lignesReglees, etape['lignesReglees'], reason: raison);
        expect(r.montantRegle, (etape['montantRegle'] as num?)?.toDouble(), reason: raison);
        expect(r.restantDu, (etape['restantDu'] as num?)?.toDouble(), reason: raison);

        final attendu = m(etape['facture']);
        final fa = r.deja ? facture : r.facture;
        for (final k in ['montantPaye', 'reliquat']) {
          expect((fa[k] as num?)?.toDouble() ?? 0, (attendu[k] as num).toDouble(), reason: '$raison : $k');
        }
        for (final k in ['modePaiement', 'statutPaiement', 'statutMecef']) {
          expect(fa[k] ?? attendu[k], attendu[k], reason: '$raison : $k');
        }
        if (!r.deja) {
          expect((fa['baseMecef'] as num).toDouble(), (attendu['baseMecef'] as num).toDouble(), reason: '$raison : baseMecef');
          final dr = m(fa['dernierReglement']), ar = m(attendu['dernierReglement']);
          expect((dr['montant'] as num).toDouble(), (ar['montant'] as num).toDouble(), reason: '$raison : dernier règlement');
          expect(dr['mode'], ar['mode']);
          expect(dr['lignes'], ar['lignes']);
        }
        final lignesApres = l(fa['lignes']);
        final lignesAttendues = l(attendu['lignes']);
        expect(lignesApres.length, lignesAttendues.length);
        for (var k = 0; k < lignesApres.length; k++) {
          expect(lignesApres[k]['id'], lignesAttendues[k]['id']);
          expect(lignesApres[k]['statutPaiement'], lignesAttendues[k]['statutPaiement'], reason: '$raison : ligne ${lignesApres[k]['id']}');
          expect((lignesApres[k]['montantRegle'] as num?)?.toDouble(), (lignesAttendues[k]['montantRegle'] as num?)?.toDouble(), reason: '$raison : montantRegle');
        }

        // Écritures : mêmes comptes, mêmes montants, même numéro — comparées par compte (l'ordre n'a pas de sens comptable).
        final ecr = {for (final e in r.ecritures) e['compte']: e};
        final att = {for (final e in l(etape['ecritures'])) e['compte']: e};
        expect(ecr.keys.toSet(), att.keys.toSet(), reason: '$raison : comptes');
        for (final compte in att.keys) {
          for (final k in ['numero', 'date', 'journal', 'libelle', 'statut', 'origine', 'pieceNumero']) {
            expect(ecr[compte]![k], att[compte]![k], reason: '$raison : $compte $k');
          }
          expect((ecr[compte]!['debit'] as num).toDouble(), (att[compte]!['debit'] as num).toDouble(), reason: '$raison : $compte débit');
          expect((ecr[compte]!['credit'] as num).toDouble(), (att[compte]!['credit'] as num).toDouble(), reason: '$raison : $compte crédit');
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
      'id': 'F1', 'numero': 'FC-2026-00001', 'partPatient': 1000, 'montantTTC': 1000, 'montantPaye': 0,
      'lignes': [{'id': 'L1', 'partPatient': 1000, 'statutPaiement': 'du'}],
    };
    final avant = jsonEncode(fac);
    encaisser(fac, lignes: ['L1'], aujourdhui: '2026-10-30', maintenant: 'x');
    expect(jsonEncode(fac), avant);
  });
}
