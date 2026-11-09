// Rejoue les vecteurs des montants entiers de la MECeF et de la validation de l'acheteur (prototype_html/build/vecteurs-mecef-montants.js, E2299).
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

Map<String, Object?> m(Object? x) => (x as Map).cast<String, Object?>();

ResultatMontants calculer(Map<String, Object?> e) => mecefMontants(
      lignes: [for (final l in (e['lignes'] as List)) m(l)],
      remiseGlobale: e['remiseGlobale'] as num?,
      totalAttendu: e['totalAttendu'] as num?,
      paiements: (e['paiements'] as List?)?.cast<num>(),
      seulementPayees: e['seulementPayees'] == true,
      aibTaux: e['aibTaux'] as num?,
      tauxTva: e['tauxTva'] as num?,
    );

void main() {
  final f = File('test/vecteurs/mecef_montants.json');
  if (!f.existsSync()) {
    fail('vecteurs absents : lancer `node prototype_html/build/vecteurs-mecef-montants.js`');
  }
  final j = m(jsonDecode(f.readAsStringSync()));

  group('montants entiers : cas fixes', () {
    for (final c in (j['cas'] as List).map(m)) {
      test('${c['nom']}', () {
        final r = calculer(m(c['entree']));
        expect(jsonEncode(r.toJson()), jsonEncode(c['sortie']),
            reason: 'octet pour octet');
      });
    }
  });

  group('montants entiers : ventes tirées au hasard', () {
    final cas = (j['hasard'] as List).map(m).toList();
    test('${cas.length} ventes, sortie identique à la maquette', () {
      expect(cas.length, 300);
      for (var i = 0; i < cas.length; i++) {
        final r = calculer(m(cas[i]['entree']));
        expect(jsonEncode(r.toJson()), jsonEncode(cas[i]['sortie']),
            reason: 'vente $i');
      }
    });
    test('propriétés : tout est entier, les parts totalisent le net, la base est la part patient', () {
      var acceptees = 0;
      for (final c in cas) {
        final res = calculer(m(c['entree']));
        if (!res.ok) continue; // un refus nommé n'a pas de montants : il se rejoue au test précédent
        acceptees++;
        final r = res.montants!;
        expect(r.total, r.partAssureur + r.partPersonnel + r.partPatient);
        expect(r.base, r.partPatient);
        expect(r.total, r.lignes.fold<int>(0, (n, l) => n + l.net));
        expect(r.net, r.base + r.aib);
        expect(r.brut - r.remises, r.total);
        for (final l in r.lignes) {
          expect(l.net, l.brut - l.remise);
          expect(l.partPatient >= 0, isTrue);
        }
      }
      expect(acceptees, greaterThan(100));
    });
  });

  group('refus nommés', () {
    test('chaque code attendu est produit avec son motif et son geste', () {
      final codes = <String>{};
      for (final c in (j['cas'] as List).map(m)) {
        final s = m(c['sortie']);
        if (s['ok'] == false) {
          codes.add('${s['code']}');
          final r = calculer(m(c['entree'])).refus!;
          expect(r.motif, isNotEmpty);
          expect(r.geste, isNotEmpty);
        }
      }
      expect(codes, containsAll([
        'TOTAL_INCOHERENT',
        'QUANTITE_INVALIDE',
        'PRIX_DECIMAL',
        'REMISE_INVALIDE',
        'AUCUNE_LIGNE',
      ]));
    });
    test('MONTANT_DECIMAL : montant brut ou part non entier', () {
      final a = mecefMontants(lignes: [
        {'designation': 'x', 'quantite': 1, 'montantBrut': 10.5}
      ]);
      expect(a.refus!.code, 'MONTANT_DECIMAL');
      final b = mecefMontants(lignes: [
        {'designation': 'x', 'quantite': 1, 'prixUnitaire': 1000, 'partAssureur': 10.5}
      ]);
      expect(b.refus!.code, 'MONTANT_DECIMAL');
    });
    test('AIB_TAUX_INVALIDE : un taux qui n\'est pas un pourcentage entier', () {
      final r = mecefMontants(lignes: [
        {'designation': 'x', 'quantite': 1, 'prixUnitaire': 1000}
      ], aibTaux: 150);
      expect(r.refus!.code, 'AIB_TAUX_INVALIDE');
    });
    test('un refus ne devient jamais un zéro silencieux : pas de montants', () {
      final r = mecefMontants(lignes: const []);
      expect(r.ok, isFalse);
      expect(r.montants, isNull);
    });
  });

  group('acheteur de la fenêtre « Facture normalisée »', () {
    for (final c in (j['acheteurs'] as List).map(m)) {
      final e = m(c['entree']);
      test('${jsonEncode(e)}', () {
        final r = validerAcheteurMecef(
            ifu: e['ifu'], nom: e['nom'], aibTaux: e['aibTaux']);
        final att = m(c['sortie']);
        if (att['ok'] == true) {
          expect(r.refus, isNull);
          expect(jsonEncode(r.acheteur!.toJson()), jsonEncode(att['acheteur']));
        } else {
          expect(r.acheteur, isNull);
          expect(jsonEncode(r.refus!.toJson()), jsonEncode(att));
        }
      });
    }
  });

  group('états de la pièce', () {
    test('cinq états, identifiants stockés valide et rejete conservés', () {
      expect(etatsMecef.map((e) => e.id),
          ['normalisee', 'en_attente', 'a_verifier', 'refusee', 'expiree']);
      expect(etatMecefDe('valide')!.id, 'normalisee');
      expect(etatMecefDe({'statutMecef': 'rejete'})!.id, 'refusee');
      expect(etatMecefDe('sans_objet'), isNull);
      expect(etatMecefDe(null), isNull);
    });
    test('le bloc fiscal exige l\'état normalisé ET un numéro', () {
      expect(porteBlocFiscal({'statutMecef': 'valide', 'numeroMecef': 'MECEF1'}), isTrue);
      expect(porteBlocFiscal({'statutMecef': 'valide'}), isFalse);
      expect(porteBlocFiscal({'statutMecef': 'en_attente', 'numeroMecef': 'MECEF1'}), isFalse);
      expect(bandeauDemoMecef({'statutMecef': 'a_verifier'}).first, 'DEMO : pièce non normalisée');
    });
  });
}
