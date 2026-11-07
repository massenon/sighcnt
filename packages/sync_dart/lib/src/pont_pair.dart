/// LE RETOUR DE LA MÈRE EN MODE PAIR (ADR-0006), port de la section « pair » de `packages/sync/banc/mere.js`.
///
/// Pendant son absence, les fileuls se sont échangé leurs opérations dans leurs journaux « pair » au relais. À son retour, la mère les RELÈVE, les rejoue par la
/// règle de fusion du domaine ([etatPair], même résultat que les fileuls), leur attribue un `seq` qui FAIT FOI (le provisoire tombe) et publie ce résultat dans SON
/// journal pair (appareil `mere`) : les fileuls le relèvent comme celui d'un pair. Les conflits restent MARQUÉS : la mère ne les tranche pas seule, la console (la
/// personne habilitée) le fait par une décision `trancher`, publiée de la même façon. Le relais ne voit que des enveloppes chiffrées.
library;

import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';

import 'commun.dart';
import 'depot.dart';
import 'mere.dart';

/// Les droits de l'échange : la MATRICE RBAC engendrée (production) ou la table du banc. Refus nommé (`StateError`) si la matrice est introuvable ou illisible :
/// une mère qui démarrerait sans droits les accorderait à tous, ou à personne, sans le dire.
DroitsOperation chargerDroitsPair(String mode, String chemin) {
  if (mode == 'banc') return droitsDepuisTable(droitsBancPair);
  if (mode != 'matrice') throw StateError('droits pair inconnus : « $mode » (matrice ou banc)');
  var f = chemin.isEmpty ? null : File(chemin);
  if (f == null) {
    var d = Directory.current.absolute;
    for (var i = 0; i < 8 && f == null; i++) {
      final c = File('${d.path}/packages/rbac/data/rbac.json');
      if (c.existsSync()) f = c;
      d = d.parent;
    }
  }
  if (f == null || !f.existsSync()) throw StateError('matrice RBAC introuvable (rbac.json) : indiquer --matrice=chemin ou lancer depuis le dépôt');
  try {
    final m = MatriceDroits.depuisJson((jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>());
    return droitsDepuisMatrice(peutEditer: m.peutEditer, peutAnnuler: m.peutAnnuler);
  } catch (e) {
    throw StateError('matrice RBAC illisible (${f.path}) : $e');
  }
}

class PontPair {
  PontPair(this.mere)
      : horloge = HorlogePair(maintenantMs: maintenantMs),
        droits = chargerDroitsPair(mere.cfg.droits, mere.cfg.matriceChemin);
  final Mere mere;
  final HorlogePair horloge;
  final DroitsOperation droits;

  Depot get base => mere.base;

  Future<void> initialiser() async {
    horloge.dernier = await base.metaInt('pair_hlc');
  }

  /// Toutes les opérations connues de la mère, avec le `seq` qu'elle leur a attribué (absent tant qu'elle ne les a pas vues).
  Future<List<OperationPair>> ops() async => [
        for (final r in await base.select('SELECT json, seq FROM pair_ops'))
          OperationPair.depuisJson({
            ...(jsonDecode(r['json'] as String) as Map).cast<String, Object?>(),
            if (r['seq'] != null) 'seq': (r['seq'] as num).toInt(),
          })
      ];

  /// Écrit une enveloppe dans le journal pair de la mère (à rang contigu). Appelé SOUS le verrou, dans la transaction de l'appelant.
  Future<void> publier(Map<String, Object?> charge) async {
    final n = await base.metaInt('pair_n') + 1;
    await base.poserMeta('pair_n', n);
    final env = await mere.pont.env.chiffrer(charge, id: 'pair-mere-$n', appareil: 'mere', dir: 'pair', n: n);
    await base.exec('INSERT INTO pair_sortie(n,enveloppe,depose) VALUES(?,?,0)', [n, enJson(env)]);
  }

  /// Dépose au relais ce qui n'y est pas encore, dans l'ordre des rangs (un dépôt rejoué est idempotent au relais).
  Future<void> expedier() async {
    final lignes = await mere.verrou.executer(() => base.select('SELECT n,enveloppe FROM pair_sortie WHERE depose=0 ORDER BY n'));
    for (final r in lignes) {
      await mere.pont.rel('POST', '/depot', {'enveloppe': jsonDecode(r['enveloppe'] as String)});
      await mere.verrou.executer(() => base.exec('UPDATE pair_sortie SET depose=1 WHERE n=?', [r['n']]));
    }
  }

  /// Relève les journaux pair des autres appareils : rangs contigus, authentification GCM, idempotence ; attribue le seq qui fait foi et le publie.
  Future<void> relever() async {
    final appareils = ((await mere.pont.rel('GET', '/pair/appareils'))['appareils'] as List).cast<Map>();
    for (final a in appareils.where((x) => x['uuid'] != 'mere')) {
      final uuid = '${a['uuid']}';
      if ((await mere.verrou.executer(() => base.meta('pair_bloque:$uuid')) ?? '').isNotEmpty) continue;
      for (;;) {
        final depuis = await mere.verrou.executer(() async => (await base.select('SELECT n FROM pair_curseurs WHERE appareil=?', [uuid])).map((r) => (r['n'] as num).toInt()).firstOrNull ?? 0);
        final r = await mere.pont.rel('GET', '/releve?dir=pair&appareil=${Uri.encodeQueryComponent(uuid)}&depuis_n=$depuis&limite=50');
        final lot = (r['env'] as List).cast<Map>();
        if (lot.isEmpty) break;
        var attendu = depuis + 1;
        final nouveaux = <OperationPair>[];
        for (final e in lot) {
          if (e['n'] != attendu) {
            mere.pont.alerter({'type': 'trou_pair', 'appareil': uuid, 'attendu': attendu, 'recu': e['n']});
            await mere.verrou.executer(() => base.poserMeta('pair_bloque:$uuid', 'trou'));
            break;
          }
          Map<String, Object?> charge;
          try {
            charge = await mere.pont.env.dechiffrer(e);
          } catch (_) {
            mere.pont.alerter({'type': 'authentification_pair', 'appareil': uuid, 'n': e['n']});
            await mere.verrou.executer(() => base.poserMeta('pair_bloque:$uuid', 'auth'));
            break;
          }
          final op = OperationPair.depuisJson(charge);
          await mere.verrou.executer(() => base.tx(() async {
                final deja = (await base.select('SELECT 1 AS x FROM pair_ops WHERE id=?', [op.id])).isNotEmpty;
                if (!deja) {
                  await base.exec('INSERT INTO pair_ops(id,json) VALUES(?,?)', [op.id, enJson(charge)]);
                  nouveaux.add(op);
                }
                await base.exec('INSERT INTO pair_curseurs(appareil,n) VALUES(?,?) ON CONFLICT(appareil) DO UPDATE SET n=excluded.n', [uuid, e['n']]);
                horloge.recevoir(op.hlc);
                await base.poserMeta('pair_hlc', horloge.dernier);
              }));
          attendu += 1;
        }
        // le seq qui FAIT FOI : attribué à l'acceptation, dans l'ordre total de la fusion, jamais l'horloge murale
        if (nouveaux.isNotEmpty) {
          await mere.verrou.executer(() => base.tx(() async {
                final liste = <List<Object?>>[];
                for (final op in nouveaux..sort(comparerOperationsPair)) {
                  final seq = await base.metaInt('pair_seq') + 1;
                  await base.poserMeta('pair_seq', seq);
                  await base.exec('UPDATE pair_ops SET seq=? WHERE id=?', [seq, op.id]);
                  liste.add([op.id, seq]);
                }
                await publier({'type': 'foi', 'liste': liste});
              }));
        }
        if (r['fin'] == true || attendu == depuis + 1) break;
      }
    }
  }

  Future<void> tour() async {
    await relever();
    await expedier();
  }

  /// `GET /admin/pair/etat` : l'état pair vu par la mère (fonction pure des opérations relevées). Appelé sous le verrou de la route.
  Future<Map<String, Object?>> etat() async {
    final liste = await ops();
    final e = etatPair(liste, droits: droits);
    return {
      'fiches': e.fiches,
      'stock': e.stock,
      'besoins': e.besoins,
      'conflits': e.conflits,
      'tranches': e.tranches,
      'refusees': [for (final r in e.refusees) {'id': r.id, 'appareil': r.appareil, 'code': r.code, 'motif': r.motif}],
      'provisoire': e.provisoire.toList()..sort(),
      'ops': liste.length,
      'seq_max': await base.metaInt('pair_seq'),
    };
  }

  /// `POST /admin/pair/trancher` : la personne habilitée (console de la mère) tranche un conflit MARQUÉ. Refus nommé (409) s'il n'y en a aucun sur ce champ : la mère
  /// ne décide jamais seule, et ne « tranche » pas ce qui ne l'est pas. Appelé sous le verrou de la route.
  Future<Map<String, Object?>> trancher(Map<String, Object?> b) async {
    final cle = '${b['fiche'] ?? ''}';
    final i = cle.indexOf('/');
    final collection = i < 0 ? cle : cle.substring(0, i), fiche = i < 0 ? '' : cle.substring(i + 1);
    final e = etatPair(await ops(), droits: droits);
    if (!e.conflits.any((c) => c['fiche'] == cle && c['champ'] == b['champ'])) {
      throw Err(409, 'aucun_conflit', 'Aucun conflit marqué sur ce champ : rien à trancher.');
    }
    final op = OperationPair(
        id: 'mere-trancher-${uuid7()}', appareil: 'mere', hlc: horloge.emettre(), collection: collection, fiche: fiche, type: 'trancher', champs: {'${b['champ']}': b['valeur']}, role: 'mere');
    await base.poserMeta('pair_hlc', horloge.dernier);
    final seq = await base.metaInt('pair_seq') + 1;
    await base.poserMeta('pair_seq', seq);
    await base.tx(() async {
      await base.exec('INSERT INTO pair_ops(id,json,seq) VALUES(?,?,?)', [op.id, enJson(op.versJson()), seq]);
      await publier({'type': 'op', 'op': {...op.versJson(), 'seq': seq}});
    });
    return {'ok': true, 'id': op.id, 'seq': seq};
  }
}
