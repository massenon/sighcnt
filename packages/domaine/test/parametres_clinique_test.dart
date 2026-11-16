import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

/// LOT PARAM-CLINIQUE : les règles des paramètres de clinique rejouées sur les vecteurs tirés de l'écran réel de la maquette (« Règles métier versionnées »,
/// `prototype_html/build/vecteurs-parametres-clinique.js`).
final v = (jsonDecode(File('test/vecteurs/parametres_clinique.json').readAsStringSync()) as Map).cast<String, Object?>();
List<Map<String, Object?>> lm(Object? o) => [for (final x in (o as List)) (x as Map).cast<String, Object?>()];

void main() {
  test('les définitions (défaut semé, bornes) sont celles de la maquette, et l\'écran réel peint les défauts semés', () {
    final defs = lm(v['definitions']);
    expect(defs.map((d) => d['cle']).toList(), pcDefinitions.map((d) => d.cle).toList());
    for (final d in defs) {
      final def = pcDefinitions.firstWhere((x) => x.cle == d['cle']);
      expect(def.defaut, d['defaut'], reason: '${d['cle']}');
      expect(def.libelle, d['libelle'], reason: '${d['cle']}');
      expect(pcBornesDe('${d['cle']}')!.min, d['min']);
      expect(pcBornesDe('${d['cle']}')!.max, d['max']);
      expect(def.famille, pcFamille);
      expect(def.mobile, isFalse);
    }
    for (final e in lm(v['ecran'])) {
      expect(e['texte'], '${pcDefinitions.firstWhere((x) => x.cle == e['cle']).defaut} jours', reason: 'l\'écran réel au défaut semé');
    }
  });

  test('contrôles : bornes, entier, vide, cohérence des tranches, clé inconnue (mêmes codes que la maquette)', () {
    final cas = lm(v['controles']);
    expect(cas.length, greaterThanOrEqualTo(20));
    for (final c in cas) {
      final r = pcControler('${c['cle']}', c['valeur'], autres: (c['autres'] as Map).cast<String, Object?>());
      expect(r?.code, c['code'], reason: '${c['cle']} = ${c['valeur']} avec ${c['autres']}');
    }
  });

  test('tranches de la balance âgée et leurs libellés, selon les bornes lues', () {
    for (final c in lm(v['tranches'])) {
      final t = (c['t'] as Map);
      expect(pcTrancheCreance((c['jours'] as num).toInt(), TranchesCreances((t['courte'] as num).toInt(), (t['longue'] as num).toInt())), c['tranche'], reason: '$c');
    }
    for (final c in lm(v['libelles'])) {
      final t = (c['t'] as Map), l = (c['libelles'] as Map);
      final r = pcLibellesTranches(TranchesCreances((t['courte'] as num).toInt(), (t['longue'] as num).toInt()));
      expect([r.moins30, r.de30a90, r.plus90], [l['moins30'], l['30a90'], l['plus90']]);
      final courts = l['courts'] as Map;
      expect([r.courtMoins30, r.courtDe30a90, r.courtPlus90], [courts['moins30'], courts['30a90'], courts['plus90']]);
    }
  });

  test('résolution à la date (plus grande date d\'effet, à égalité la plus récente, archivées ignorées, défaut sinon) et statut des lots à la date', () {
    final versions = lm(v['versions']);
    for (final c in lm(v['resolutions'])) {
      final r = pcResoudreFiches(versions, '${c['cle']}', '${c['date']}');
      expect(r.valeur, c['valeur'], reason: '${c['cle']} au ${c['date']}');
      expect(r.origine, c['origine'], reason: '${c['cle']} au ${c['date']}');
      expect(r.versionId, c['versionId'], reason: '${c['cle']} au ${c['date']}');
    }
    for (final c in lm(v['lots'])) {
      final preavis = pcResoudreFiches(versions, pcCleDelaiPeremption, '${c['date']}').valeur!.toInt();
      final lot = <String, Object?>{'statut': c['statutEcrit'], if (c['datePeremption'] != null) 'datePeremption': c['datePeremption']};
      expect(pcStatutLot(lot, '${c['date']}', preavis), c['statut'], reason: '$c (préavis $preavis)');
    }
  });

  test('la lecture du registre L0 du poste rejoue la même résolution (versions à la date, défaut semé sans version)', () {
    // Les mêmes versions, sous la forme du registre L0 (une version par date d'effet, numérotée dans l'ordre de création ; archivées exclues).
    final maquette = lm(v['versions']).where((f) => f['statut'] != 'archive').toList();
    final l0 = <Map<String, Object?>>[];
    for (final cle in [pcCleDelaiPeremption, pcCleTrancheCourte, pcCleTrancheLongue]) {
      final def = pcDefinitions.firstWhere((d) => d.cle == cle);
      var n = 0;
      for (final f in maquette.where((f) => f['cle'] == cle)) {
        final p = f['dateEffet'] == null ? Parametres.semer(def) : Parametre.fromJson({...Parametres.semer(def).toJson(), 'valeur': f['valeur'], 'dateEffet': f['dateEffet'], 'version': ++n});
        l0.add({'statut': 'actif', ...p.toJson()});
      }
    }
    for (final c in lm(v['resolutions'])) {
      expect(pcValeur(l0, '${c['cle']}', '${c['date']}'), c['valeur'], reason: '${c['cle']} au ${c['date']}');
    }
    expect(pcDelaiPeremption(const [], '2026-11-16'), 90, reason: 'aucune version : le défaut semé de la définition');
    expect(pcTranches(const [], '2026-11-16').courte, 30);
    expect(pcTranches(const [], '2026-11-16').longue, 90);
  });
}
