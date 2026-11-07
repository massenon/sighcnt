import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/transcription_mobile.dart' show PieceSync;

/// Un journal partagé par les postes de la clinique (la mère en tient la vérité).
class Journal {
  final Map<String, Map<String, Map<String, Object?>>> fiches = {};
}

class TransportFictif implements TransportPont {
  TransportFictif(this.j);
  final Journal j;
  int ecritures = 0;
  @override
  Future<List<PieceSync>> liste(String c) async =>
      [for (final e in (j.fiches[c] ?? {}).entries) PieceSync(e.key, jsonDecode(jsonEncode(e.value)) as Map<String, Object?>)];
  @override
  Future<void> ecrire(String c, String fiche, {required bool existe, required Map<String, Object?> champs}) async {
    ecritures++;
    final col = j.fiches.putIfAbsent(c, () => {});
    col[fiche] = {...?col[fiche], ...jsonDecode(jsonEncode(champs)) as Map<String, Object?>};
  }
}

Magasin poste() => Magasin({'patients': [], 'identifiants': [], 'rendezvous': []});

Future<void> tour(List<PontActivite> ponts) async {
  for (var i = 0; i < 3; i++) {
    for (final p in ponts) {
      await p.cycle();
    }
  }
}

void main() {
  late Journal j;
  late Magasin ma, mb, mm;
  late PontActivite pa, pb, pm;
  setUp(() {
    j = Journal();
    ma = poste();
    mb = poste();
    mm = poste();
    pa = PontActivite(ma, TransportFictif(j), etiquette: 'A');
    pb = PontActivite(mb, TransportFictif(j), etiquette: 'B');
    pm = PontActivite(mm, TransportFictif(j), etiquette: 'M');
  });

  test('une fiche créée sur un poste arrive aux autres, une seule fois, sans doublon chez son auteur', () async {
    ma.collection('patients').inserer({'nom': 'AGBO', 'code': 'CNT/1/26'}, prefixe: 'PAT');
    await tour([pa, pb, pm]);
    expect(mb.collection('patients').toutes.single['nom'], 'AGBO');
    expect(mm.collection('patients').toutes.single['nom'], 'AGBO');
    expect(ma.collection('patients').toutes, hasLength(1), reason: 'l’auteur ne se réimporte pas');
    expect(mb.collection('patients').toutes.single['id'], ma.collection('patients').toutes.single['idSync']);
  });

  test('deux postes qui créent le MÊME identifiant local gardent deux fiches distinctes partout', () async {
    ma.collection('rendezvous').inserer({'motif': 'Contrôle'}, prefixe: 'RDV');
    mb.collection('rendezvous').inserer({'motif': 'Pansement'}, prefixe: 'RDV');
    expect(ma.collection('rendezvous').toutes.single['id'], mb.collection('rendezvous').toutes.single['id'], reason: 'le piège : même rang local');
    await tour([pa, pb, pm]);
    for (final m in [ma, mb, mm]) {
      expect(m.collection('rendezvous').toutes.map((f) => f['motif']).toSet(), {'Contrôle', 'Pansement'});
    }
  });

  test('champs différents modifiés en même temps sur deux postes : les deux changements survivent', () async {
    ma.collection('patients').inserer({'nom': 'AGBO', 'telephone': '1', 'quartier': 'X', 'code': 'CNT/1/26'}, prefixe: 'PAT');
    await tour([pa, pb, pm]);
    final ida = ma.collection('patients').toutes.single['id'];
    final idb = mb.collection('patients').toutes.single['id'];
    ma.collection('patients').mettreAJour(ida, {'telephone': '2'});
    mb.collection('patients').mettreAJour(idb, {'quartier': 'Y'});
    await tour([pa, pb, pm]);
    for (final m in [ma, mb, mm]) {
      final f = m.collection('patients').toutes.single;
      expect([f['telephone'], f['quartier']], ['2', 'Y']);
    }
  });

  test('un archivage voyage (RG-14) et rien n’est supprimé', () async {
    ma.collection('patients').inserer({'nom': 'AGBO', 'code': 'CNT/1/26'}, prefixe: 'PAT');
    await tour([pa, pb]);
    mb.collection('patients').archiver(mb.collection('patients').toutes.single['id']);
    await tour([pa, pb]);
    expect(ma.collection('patients').toutes.single['statut'], 'archive');
    expect(ma.collection('patients').toutes, hasLength(1));
  });

  test('un cycle sans geste n’écrit plus rien dans le journal', () async {
    final t = TransportFictif(j);
    final p = PontActivite(ma, t, etiquette: 'A');
    ma.collection('patients').inserer({'nom': 'AGBO', 'code': 'CNT/1/26'}, prefixe: 'PAT');
    await p.cycle();
    final n = t.ecritures;
    await p.cycle();
    await p.cycle();
    expect(t.ecritures, n);
  });

  test('MOT DE PASSE : changé sur un fileul, il remonte à la mère puis aux autres fileuls ; un plus ancien ne le remplace jamais', () async {
    final ancien = {'id': 'agent1', 'hache': 'H-ancien', 'sel': 'S1', 'definiLe': '2026-11-01T08:00:00'};
    mm.collection('identifiants').ajouterSansJournal(ancien);
    await tour([pm, pa, pb]);
    expect(ma.collection('identifiants').parId('agent1')!['hache'], 'H-ancien', reason: 'la mère diffuse');
    // L'agent change son mot de passe sur le fileul A.
    ma.collection('identifiants').appliquerDistante({'id': 'agent1', 'hache': 'H-nouveau', 'sel': 'S2', 'definiLe': '2026-11-03T09:00:00'});
    await tour([pa, pm, pb]);
    for (final m in [mm, mb, ma]) {
      final f = m.collection('identifiants').parId('agent1')!;
      expect([f['hache'], f['sel']], ['H-nouveau', 'S2'], reason: 'le haché et son sel voyagent EN UN BLOC');
    }
    // Un poste resté en retard ne fait pas revenir l’ancien.
    mb.collection('identifiants').appliquerDistante(ancien);
    await tour([pb, pm, pa]);
    expect(mm.collection('identifiants').parId('agent1')!['hache'], 'H-nouveau');
    expect(mb.collection('identifiants').parId('agent1')!['hache'], 'H-nouveau');
  });

  test('RG-01 : deux dossiers au même code après rencontre de deux postes sont MARQUÉS, jamais renumérotés en silence', () async {
    ma.collection('patients').inserer({'nom': 'AGBO', 'code': 'CNT/7/26'}, prefixe: 'PAT');
    mb.collection('patients').inserer({'nom': 'ZANNOU', 'code': 'CNT/7/26'}, prefixe: 'PAT');
    await tour([pa, pb, pm]);
    expect(pm.doublonsDeCode.value, 2);
    for (final m in [ma, mb, mm]) {
      final fs = m.collection('patients').toutes;
      expect(fs, hasLength(2));
      expect(fs.every((f) => f['codeEnDoublon'] == true && f['code'] == 'CNT/7/26'), isTrue);
    }
  });

  test('ce qui porte une règle de fusion voyage ; le reste (journal, état du pont, plages) reste propre au poste', () {
    for (final c in ['factures', 'avoirs', 'ecritures', 'produits', 'lots', 'mouvements', 'admissions']) {
      expect(collectionsActivite.contains(c), isTrue, reason: c);
    }
    for (final c in ['audit', 'pontEtat', 'plagesCodes', 'sessions', 'codesSecours']) {
      expect(collectionsActivite.contains(c), isFalse, reason: c);
    }
  });
}
