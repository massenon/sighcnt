import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/sync/fusion_activite.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/transcription_mobile.dart' show PieceSync;

/// Les règles de fusion des pièces et des compteurs (limites levées le 03/11/2026) : factures, avoirs, écritures, stock, lots, mouvements, admissions et lits.
typedef M = Map<String, Object?>;

class Journal {
  final Map<String, Map<String, M>> fiches = {};
}

class Transport implements TransportPont {
  Transport(this.j);
  final Journal j;
  @override
  Future<List<PieceSync>> liste(String c) async => [for (final e in (j.fiches[c] ?? {}).entries) PieceSync(e.key, jsonDecode(jsonEncode(e.value)) as M)];
  @override
  Future<void> ecrire(String c, String fiche, {required bool existe, required M champs}) async {
    final col = j.fiches.putIfAbsent(c, () => {});
    if (!existe && col.containsKey(fiche)) throw StateError('fiche_existe');
    col[fiche] = {...?col[fiche], ...jsonDecode(jsonEncode(champs)) as M};
  }
}

const noms = ['produits', 'lots', 'factures', 'avoirs', 'ecritures', 'mouvements', 'admissions'];

Magasin poste({int stock = 10, Map<String, Iterable<M>>? en}) => Magasin({
      for (final n in noms) n: <M>[],
      'produits': [
        {'id': 'PRD1', 'designation': 'Paracétamol', 'stockGros': stock, 'stockDetail': 0, 'stock': stock}
      ],
      'lots': [
        {'id': 'LOT1', 'produitId': 'PRD1', 'quantiteRestante': stock}
      ],
      ...?en,
    });

Future<void> tour(List<PontActivite> ps) async {
  for (var i = 0; i < 4; i++) {
    for (final p in ps) {
      await p.cycle();
    }
  }
}

void main() {
  late Journal j;
  late Magasin ma, mb, mm;
  late PontActivite pa, pb, pm;
  void monter({int stock = 10}) {
    j = Journal();
    ma = poste(stock: stock);
    mb = poste(stock: stock);
    mm = poste(stock: stock);
    pm = PontActivite(mm, Transport(j), etiquette: 'M');
    pa = PontActivite(ma, Transport(j), etiquette: 'A');
    pb = PontActivite(mb, Transport(j), etiquette: 'B');
  }

  num stockDe(Magasin m, [String champ = 'stockGros']) => m.collection('produits').parId('PRD1')![champ] as num;

  setUp(() => monter());

  group('STOCK (RG-03) : des variations additionnées, jamais un stock remplacé', () {
    test('deux sorties simultanées de deux postes se retranchent TOUTES les deux ; le jeu d’origine n’est pas dupliqué', () async {
      await tour([pm, pa, pb]);
      expect(ma.collection('produits').toutes, hasLength(1), reason: 'la fiche du jeu d’origine garde son identité sur tous les postes');
      expect(stockDe(ma), 10, reason: 'trois postes au même stock de départ : rien n’est compté trois fois');
      ma.collection('produits').mettreAJour('PRD1', {'stockGros': 7, 'stock': 7});
      mb.collection('produits').mettreAJour('PRD1', {'stockGros': 6, 'stock': 6});
      await tour([pa, pb, pm]);
      for (final m in [ma, mb, mm]) {
        expect(stockDe(m), 3, reason: '10 - 3 - 4, quel que soit l’ordre');
        expect(stockDe(m, 'stock'), 3);
      }
    });

    test('un poste qui rejoint la clinique avec ses PROPRES sorties les publie et reçoit celles des autres ; un redémarrage ne compte rien deux fois', () async {
      await tour([pm, pa]);
      ma.collection('produits').mettreAJour('PRD1', {'stockGros': 8});
      await tour([pa, pm]);
      // C a travaillé seul avant de rejoindre : il a sorti 5 unités (10 -> 5).
      final mc = poste();
      mc.collection('produits').mettreAJour('PRD1', {'stockGros': 5});
      final pc = PontActivite(mc, Transport(j), etiquette: 'C');
      await tour([pc, pa, pm]);
      expect(stockDe(mc), 3, reason: '10 - 2 (A) - 5 (C)');
      expect(stockDe(ma), 3);
      expect(stockDe(mm), 3);
      // Redémarrage de A : un nouveau pont sur le MÊME magasin (l'état est au magasin) ne rejoue rien.
      final pa2 = PontActivite(ma, Transport(j), etiquette: 'A');
      await tour([pa2, pm, pc]);
      expect([stockDe(ma), stockDe(mm), stockDe(mc)], [3, 3, 3]);
    });

    test('deux dernières unités sorties hors ligne par deux postes : le stock devient négatif, c’est DÉTECTÉ et marqué (RG-03), jamais effacé', () async {
      await tour([pm, pa, pb]);
      ma.collection('produits').mettreAJour('PRD1', {'stockGros': 2});
      mb.collection('produits').mettreAJour('PRD1', {'stockGros': 2});
      await tour([pa, pb, pm]);
      // 10 - 8 - 8 = -6
      for (final m in [ma, mb, mm]) {
        expect(stockDe(m), -6);
        expect(m.collection('produits').parId('PRD1')!['stockNegatifDetecte'], isTrue);
      }
      expect(pm.stocksNegatifs.value, 1);
      // Un réapprovisionnement ramène le stock au-dessus de zéro : le marqueur tombe.
      ma.collection('produits').mettreAJour('PRD1', {'stockGros': 14});
      await tour([pa, pb, pm]);
      expect(stockDe(mb), 14, reason: 'A voyait -6 et l\'a ramené à 14 : une entrée de +20');
      expect(mb.collection('produits').parId('PRD1')!.containsKey('stockNegatifDetecte'), isFalse);
    });

    test('les lots : la quantité restante suit la même règle ; un cycle sans geste n’écrit rien', () async {
      await tour([pm, pa, pb]);
      ma.collection('lots').mettreAJour('LOT1', {'quantiteRestante': 6});
      mb.collection('lots').mettreAJour('LOT1', {'quantiteRestante': 7});
      await tour([pa, pb, pm]);
      expect(mm.collection('lots').parId('LOT1')!['quantiteRestante'], 3);
      final avant = j.fiches[collectionDeltas]!.length;
      await tour([pa, pb, pm]);
      expect(j.fiches[collectionDeltas]!.length, avant);
    });
  });

  group('FACTURES : un règlement ne se perd pas', () {
    M facture() => {
          'id': 'FAC1',
          'numero': 'FP-2026-00001',
          'montantPaye': 0,
          'reliquat': 1500,
          'statutPaiement': 'impayee',
          'lignes': [
            {'id': 'L1', 'designation': 'Consultation', 'montant': 1000, 'statutPaiement': 'du'},
            {'id': 'L2', 'designation': 'Pansement', 'montant': 500, 'statutPaiement': 'du'},
          ],
        };

    test('deux guichets règlent deux lignes différentes en même temps : les deux règlements survivent, le montant s’additionne, le statut avance', () async {
      ma.collection('factures').inserer(facture(), prefixe: 'FAC');
      await tour([pa, pb, pm]);
      final fa = ma.collection('factures').toutes.single, fb = mb.collection('factures').toutes.single;
      expect(fb['numero'], 'FP-2026-00001');
      ma.collection('factures').mettreAJour(fa['id'], {
        'montantPaye': 500,
        'reliquat': 1000,
        'statutPaiement': 'partielle',
        'lignes': [
          {'id': 'L1', 'designation': 'Consultation', 'montant': 1000, 'statutPaiement': 'du'},
          {'id': 'L2', 'designation': 'Pansement', 'montant': 500, 'statutPaiement': 'paye', 'payePar': 'A', 'payeLe': '2026-11-03T10:00:00Z'},
        ],
      });
      mb.collection('factures').mettreAJour(fb['id'], {
        'montantPaye': 1000,
        'reliquat': 500,
        'statutPaiement': 'partielle',
        'lignes': [
          {'id': 'L1', 'designation': 'Consultation', 'montant': 1000, 'statutPaiement': 'paye', 'payePar': 'B', 'payeLe': '2026-11-03T10:00:05Z'},
          {'id': 'L2', 'designation': 'Pansement', 'montant': 500, 'statutPaiement': 'du'},
        ],
      });
      await tour([pa, pb, pm]);
      for (final m in [ma, mb, mm]) {
        final f = m.collection('factures').toutes.single;
        expect(f['montantPaye'], 1500, reason: '500 + 1000');
        expect(f['reliquat'], 0);
        expect(f['statutPaiement'], 'soldee');
        expect((f['lignes'] as List).every((l) => (l as Map)['statutPaiement'] == 'paye'), isTrue, reason: 'aucune ligne réglée n’est redevenue due');
        expect(f.containsKey('encaissementEnDoublon'), isFalse);
      }
    });

    test('la même ligne encaissée par deux guichets : conservée une fois et SIGNALÉE', () {
      final ici = {'id': 'F', 'montantPaye': 500, 'reliquat': 0, 'statutPaiement': 'soldee', 'lignes': [{'id': 'L1', 'statutPaiement': 'paye', 'payePar': 'A', 'payeLe': '2026-11-03T10:00:09Z'}]};
      final la = {'id': 'F', 'montantPaye': 500, 'reliquat': 0, 'statutPaiement': 'soldee', 'lignes': [{'id': 'L1', 'statutPaiement': 'paye', 'payePar': 'B', 'payeLe': '2026-11-03T10:00:01Z'}]};
      final r = fusionnerFacture({...ici}, ici, la);
      expect(r['encaissementEnDoublon'], ['L1']);
      expect(((r['lignes'] as List).single as Map)['payePar'], 'B', reason: 'le règlement le plus ancien est conservé');
    });

    test('NUMÉROS : deux pièces au même numéro sont MARQUÉES (jamais renumérotées) ; une écriture à deux lignes n’est pas un doublon', () async {
      ma.collection('factures').inserer({'numero': 'FP-2026-00005', 'montantPaye': 0}, prefixe: 'FAC');
      mb.collection('factures').inserer({'numero': 'FP-2026-00005', 'montantPaye': 0}, prefixe: 'FAC');
      ma.collection('avoirs').inserer({'reference': 'AV-1'}, prefixe: 'AVO');
      mb.collection('avoirs').inserer({'reference': 'AV-1'}, prefixe: 'AVO');
      // Une pièce comptable : deux lignes, même numéro, même pièce d'origine.
      ma.collection('ecritures').inserer({'numero': 'CAI-1', 'pieceId': 'P1', 'debit': 100}, prefixe: 'ECR');
      ma.collection('ecritures').inserer({'numero': 'CAI-1', 'pieceId': 'P1', 'credit': 100}, prefixe: 'ECR');
      // Deux pièces DIFFÉRENTES au même numéro.
      ma.collection('ecritures').inserer({'numero': 'CAI-2', 'pieceId': 'P2', 'debit': 5}, prefixe: 'ECR');
      mb.collection('ecritures').inserer({'numero': 'CAI-2', 'pieceId': 'P3', 'debit': 7}, prefixe: 'ECR');
      await tour([pa, pb, pm]);
      for (final m in [ma, mb, mm]) {
        expect(m.collection('factures').toutes, hasLength(2));
        expect(m.collection('factures').toutes.every((f) => f['numeroEnDoublon'] == true && f['numero'] == 'FP-2026-00005'), isTrue);
        expect(m.collection('avoirs').toutes.every((f) => f['numeroEnDoublon'] == true), isTrue);
        final e = m.collection('ecritures').toutes;
        expect(e.where((f) => f['numero'] == 'CAI-1').every((f) => f['numeroEnDoublon'] != true), isTrue, reason: 'une pièce à deux lignes');
        expect(e.where((f) => f['numero'] == 'CAI-2').every((f) => f['numeroEnDoublon'] == true), isTrue);
      }
      expect(pm.doublonsDeNumero['factures'], 2);
    });

    test('les mouvements de stock (journal) et les écritures voyagent sans doublon d’identité, d’un poste à l’autre', () async {
      ma.collection('mouvements').inserer({'reference': 'TR-1', 'produitId': 'PRD1', 'quantite': 3}, prefixe: 'MOU');
      mb.collection('mouvements').inserer({'reference': 'TR-2', 'produitId': 'PRD1', 'quantite': 2}, prefixe: 'MOU');
      await tour([pa, pb, pm]);
      for (final m in [ma, mb, mm]) {
        expect(m.collection('mouvements').toutes.map((f) => f['reference']).toSet(), {'TR-1', 'TR-2'});
        expect(m.collection('mouvements').toutes, hasLength(2), reason: 'ni perdu, ni dupliqué');
      }
    });
  });

  group('LITS : un lit, une admission active', () {
    test('deux admissions actives sur le même lit, à deux postes : les deux sont marquées ; la sortie de l’une lève le marqueur', () async {
      ma.collection('admissions').inserer({'lit': 'B1 LIT2', 'statut': 'en_cours', 'patient': 'X'}, prefixe: 'ADM');
      mb.collection('admissions').inserer({'lit': 'B1 LIT2', 'statut': 'en_cours', 'patient': 'Y'}, prefixe: 'ADM');
      await tour([pa, pb, pm]);
      for (final m in [ma, mb, mm]) {
        expect(m.collection('admissions').toutes, hasLength(2));
        expect(m.collection('admissions').toutes.every((f) => f['litEnConflit'] == true), isTrue);
      }
      expect(pm.litsEnConflitCompte.value, 2);
      final a = ma.collection('admissions').toutes.firstWhere((f) => f['patient'] == 'X');
      ma.collection('admissions').mettreAJour(a['id'], {'statut': 'sortie'});
      await tour([pa, pb, pm]);
      for (final m in [ma, mb, mm]) {
        expect(m.collection('admissions').toutes.any((f) => f['litEnConflit'] == true), isFalse);
      }
    });
  });
}
