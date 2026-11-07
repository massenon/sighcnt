// Rejoue les vecteurs de la MECeF (simulation) engendrés en pilotant `mecef.js` de la maquette (prototype_html/build/vecteurs-mecef.js).
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

List<Map<String, Object?>> liste(Object? v) => ((v ?? const []) as List)
    .map((x) => (x as Map).cast<String, Object?>())
    .toList();

List<List<String>> lignes(TableauEtat t) => [
      [for (final c in t.colonnes) c.libelle],
      ...t.cellules,
      if (t.pied != null) t.pied!,
    ];

void main() {
  final f = File('test/vecteurs/mecef.json');
  if (!f.existsSync()) {
    fail('vecteurs absents : lancer `node prototype_html/build/vecteurs-mecef.js`');
  }
  final j = (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>();

  group('facture normalisée imprimée', () {
    for (final c in liste(j['impressions'])) {
      test('${c['regime']} · ${c['nom']}', () {
        final p = ParamFiscal(regimeTva: '${c['regime']}');
        final fac = factureNormalisee((c['facture']! as Map).cast(), p);
        final tables = (c['tables']! as List)
            .map((t) => (t as List).map((r) => (r as List).cast<String>()).toList())
            .toList();
        expect(lignes(fac.lignes), tables[0], reason: 'lignes');
        expect(lignes(fac.taxes), tables[1], reason: 'taxes');
        expect(lignes(fac.totaux), tables[2], reason: 'totaux');
        final para = (c['paragraphes']! as List).cast<String>();
        expect(para, contains('Devise : FCFA'));
        expect(para, contains('${p.mentionMontant} :'));
        expect(para, contains(fac.enLettres));
        expect(para, contains(fac.codeDgi));
        expect(para, contains('MECeF NIM : ${fac.nim}'));
        expect(para, contains('MECeF Compteurs : ${fac.compteurs}'));
        // La mention d'exonération n'existe qu'à taux 0.
        expect(para.contains(p.mentionExoneration), p.tauxTva == 0);
        expect(fac.mentionExoneration != null, p.tauxTva == 0);
      });
    }
  });

  group('synchronisation avec le dispositif (tirage graine)', () {
    for (final c in liste(j['synchronisations'])) {
      test('un lot de ${c['nb']} facture(s)', () {
        final r = synchroniser(c['nb']! as int, c['jour']! as String);
        // Le vecteur liste les factures dans l'ordre de leur CRÉATION ; le dispositif les traite dans l'ordre de la liste, qui insère en tête (ÉCART E16) :
        // la dernière créée est donc la première traitée.
        final att = liste(c['resultats']).reversed.toList();
        expect(r.length, att.length);
        for (var i = 0; i < att.length; i++) {
          expect(r[i].statutMecef, att[i]['statutMecef'], reason: 'facture $i');
          expect(r[i].numeroMecef, att[i]['numeroMecef'], reason: 'facture $i');
          expect(r[i].codeRetour, att[i]['codeRetour'], reason: 'facture $i');
          expect(r[i].dateTransmission, att[i]['dateTransmission']);
        }
      });
    }
    test('le lot de 21 contient des rejets : le tirage n\'est pas un « tout accepté »', () {
      final r = synchroniser(21, '2026-10-30');
      expect(r.where((x) => x.statutMecef == 'rejete'), isNotEmpty);
      expect(r.where((x) => x.statutMecef == 'valide'), isNotEmpty);
    });
  });

  group('avoir MECeF (B10 : le moteur unique, plafond cumulé, montant > 0)', () {
    for (final c in liste(j['avoirs'])) {
      final e = (c['entree']! as Map).cast<String, Object?>();
      test('${e['nom']}', () {
        final fac = (e['facture']! as Map).cast<String, Object?>();
        final saisie = {
          'factureId': fac['id'],
          'observations': '',
          ...(e['saisie']! as Map).cast<String, Object?>()
        };
        final attendus = liste(c['avoirs']);
        AvoirMecefEmis emettre() => avoirMecef(
            facture: fac,
            saisie: saisie,
            avoirs: liste(e['avoirs']),
            idAvoir: 'AVR-TEST',
            utilisateur: 'BASSONGUI Chabi Séko');
        if (attendus.isEmpty) {
          expect(emettre, throwsA(isA<RefusAvoirMecef>()));
          return;
        }
        final r = emettre();
        final a = attendus.single;
        for (final k in a.keys) {
          if (k == 'ecritureIds' || k.startsWith('_')) continue;
          final x = a[k], y = r.fiche[k];
          if (x is num) {
            expect((y as num).toDouble(), x.toDouble(), reason: k);
          } else {
            expect(y, x, reason: k);
          }
        }
        expect(r.fiche['origine'], 'mecef');
        // Le moteur unique a contre-passé : deux lignes plates équilibrées (RG-10).
        final debit = r.emission.ecritures.fold<double>(0, (t, x) => t + (x['debit']! as num));
        final credit = r.emission.ecritures.fold<double>(0, (t, x) => t + (x['credit']! as num));
        expect(debit, credit);
      });
    }

    test('E10 : un montant nul est refusé en le nommant', () {
      final cm = liste(j['avoirs']).firstWhere(
          (c) => '${(c['entree']! as Map)['nom']}'.startsWith('montant nul'));
      final e = (cm['entree']! as Map).cast<String, Object?>();
      expect(
          () => avoirMecef(
              facture: (e['facture']! as Map).cast(),
              saisie: {
                'factureId': 'x',
                ...(e['saisie']! as Map).cast<String, Object?>()
              },
              avoirs: const []),
          throwsA(isA<RefusAvoirMecef>().having((r) => r.motif, 'motif',
              'Le montant doit être strictement supérieur à 0 FCFA.')));
    });
  });

  group('IFU client (E14)', () {
    test('l\'IFU du client, vide si inconnu, jamais celui de la clinique', () {
      expect(ifuClientDe({'ifuClient': '3201912345678'}), '3201912345678');
      expect(ifuClientDe({}, {'ifu': '3200000000001'}), '3200000000001');
      expect(ifuClientDe({}), '');
      expect(ifuClientDe({}), isNot(IdentiteClinique.ifu));
    });
    for (final c in liste(j['impressions']).where((c) => '${c['nom']}'.startsWith('IFU du client'))) {
      test('${c['regime']} : ${c['nom']}', () {
        final cartouche = (c['cartouche']! as List).map((x) => (x as List).cast<String>()).toList();
        final ifu = cartouche.firstWhere((x) => x[0] == 'IFU client')[1];
        expect(ifu, ifuClientDe((c['facture']! as Map).cast()));
        expect(ifu, isNot(IdentiteClinique.ifu));
      });
    }
  });

  test('l\'identifiant simulé a la forme MECEF + 7 chiffres, et la graine le fixe', () {
    final a = numeroMecefSimule(12345);
    expect(RegExp(r'^MECEF\d{7}$').hasMatch(a), isTrue);
    expect(numeroMecefSimule(12345), a);
    expect(numeroMecefSimule(12346), isNot(a));
  });

  test('transmettre une facture : acceptée d\'office, OK-200', () {
    final r = transmettreUne(777, '2026-10-30');
    expect(r.statutMecef, 'valide');
    expect(r.codeRetour, 'OK-200');
    expect(r.numeroMecef, startsWith('MECEF'));
  });
}
