// Rejoue les vecteurs de l'émission de facture engendrés en PILOTANT l'écran m8-facturation de la maquette
// (prototype_html/build/vecteurs-emission.js).
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

List<Map<String, Object?>> liste(Object? v) => ((v ?? const []) as List)
    .map((x) => (x as Map).cast<String, Object?>())
    .toList();

/// Le magasin ne garde pas les champs nuls (`sansNuls`) : absent et nul se valent.
void memes(Object? obtenu, Object? attendu, String chemin) {
  if (attendu is Map) {
    final o = (obtenu as Map?) ?? const {};
    for (final k in {...attendu.keys, ...o.keys}) {
      if (const {'id', 'statut', '_creePar', '_creeLe'}.contains(k)) continue;
      memes(o[k], attendu[k], '$chemin.$k');
    }
  } else if (attendu is List) {
    final o = obtenu as List;
    expect(o.length, attendu.length, reason: '$chemin : longueur');
    for (var i = 0; i < attendu.length; i++) {
      memes(o[i], attendu[i], '$chemin[$i]');
    }
  } else if (attendu is num) {
    expect((obtenu as num).toDouble(), attendu.toDouble(), reason: chemin);
  } else {
    expect(obtenu, attendu, reason: chemin);
  }
}

void main() {
  final f = File('test/vecteurs/emission.json');
  if (!f.existsSync()) {
    fail('vecteurs absents : lancer `node prototype_html/build/vecteurs-emission.js`');
  }
  final cas = liste((jsonDecode(f.readAsStringSync()) as Map)['cas']);
  test('au moins 20 situations ont été engendrées',
      () => expect(cas.length, greaterThanOrEqualTo(20)));

  for (final c in cas) {
    final e = (c['entree']! as Map).cast<String, Object?>();
    test('${e['nom']}', () {
      // 1. la saisie : chaque ajout passe par `ligneSaisie` ; un refus laisse la ligne hors de la pièce.
      final lignes = <Map<String, Object?>>[];
      for (final s in liste(e['saisie'])) {
        final deja = lignes
            .where((l) => l['produitId'] != null && l['produitId'] == s['produitId'])
            .fold<num>(0, (a, l) => a + (l['quantite']! as num));
        try {
          lignes.add(ligneSaisie(
            nature: s['nature']! as String,
            designation: s['designation']! as String,
            quantite: s['quantite']! as num,
            prixUnitaire: s['prixUnitaire']! as num,
            produitId: s['produitId'] as String?,
            secteur: s['secteur'] as String?,
            remise: s['remise']! as num,
            typeRemise: s['typeRemise']! as String,
            motifRemise: s['motif'] as String?,
            stockDetail: s['stockDetail'] as num?,
            dejaSurLaFacture: deja,
          ));
          expect(s['ajoutee'], true, reason: 'la maquette a refusé cet ajout');
        } on RefusEmission {
          expect(s['ajoutee'], false, reason: 'la maquette a accepté cet ajout');
        }
      }
      final attendues = liste(c['pieces'])
        ..sort((a, b) => '${a['numero']}'.compareTo('${b['numero']}'));
      if (lignes.isEmpty) {
        expect(attendues, isEmpty);
        expect(
            () => emettreFacture(
                patient: (e['patient']! as Map).cast(),
                lignes: lignes,
                dateRepartition: e['date']! as String,
                dateFacture: e['date']! as String,
                type: e['type']! as String,
                mode: e['mode']! as String,
                rangDebut: e['rangDebut']! as int),
            throwsA(isA<RefusEmission>()));
        return;
      }
      // 2. l'émission.
      final r = emettreFacture(
        patient: (e['patient']! as Map).cast(),
        lignes: lignes,
        dateRepartition: e['date']! as String,
        dateFacture: e['date']! as String,
        type: e['type']! as String,
        mode: e['mode']! as String,
        rangDebut: e['rangDebut']! as int,
        reglement: e['reglement'] as num?,
        proforma: e['proforma']! as bool,
        dissocier: e['dissocier']! as bool,
        couvertures: liste(e['couvertures']),
        souscripteurs: liste(e['souscripteurs']),
        garanties: liste(e['garanties']),
        produits: liste(e['produits']),
      );
      final obtenues = [...r.pieces]
        ..sort((a, b) => '${a['numero']}'.compareTo('${b['numero']}'));
      memes(obtenues, attendues, 'pieces');

      // 3. les sorties de stock.
      final attSorties = liste(c['sorties']);
      expect(r.sorties.length, attSorties.length);
      for (var i = 0; i < attSorties.length; i++) {
        expect(r.sorties[i].produitId, attSorties[i]['produitId']);
        expect(r.sorties[i].quantite, (attSorties[i]['quantite']! as num).toDouble());
        expect(r.sorties[i].justificatif, attSorties[i]['justificatif']);
      }
      final attStocks = liste(c['stocks']);
      for (final a in attStocks) {
        final s = r.sorties.lastWhere((x) => x.produitId == a['produitId']);
        expect(s.apres.stockDetail, ((a['apres']! as Map)['stockDetail']! as num).toDouble());
        expect(s.apres.stock, ((a['apres']! as Map)['stock']! as num).toDouble());
      }
    });
  }

  group('E6 : série annuelle des numéros de facture (corrigé le 31/10/2026)', () {
    test('le préfixe lit le millésime de la DATE de la pièce, pro-forma dans sa propre série', () {
      expect(prefixeSerieFacture(proforma: false, dateFacture: '2026-12-31'), 'FN-2026-');
      expect(prefixeSerieFacture(proforma: false, dateFacture: '2027-01-04'), 'FN-2027-');
      expect(prefixeSerieFacture(proforma: true, dateFacture: '2027-01-04'), 'PRO-2027-');
    });
    test('le rang est celui de la série : le plus grand rang du préfixe + 1 (suffixes -A et -B ignorés), la série repart chaque année', () {
      final fs = [
        {'numero': 'FN-2026-00237-A'},
        {'numero': 'FN-2026-00237-B'},
        {'numero': 'FN-2026-00040'},
        {'numero': 'FP-2026-00999'},
        {'numero': 'PRO-2026-00007'},
      ];
      expect(rangSerieFactures('FN-2026-', fs), 238);
      expect(rangSerieFactures('FN-2027-', fs), 1);
      expect(rangSerieFactures('PRO-2026-', fs), 8);
      expect(rangSerieFactures('FN-2026-', const []), 1);
    });
  });
}
