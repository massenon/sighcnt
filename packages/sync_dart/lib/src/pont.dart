/// LE PONT DE LA MÈRE VERS LE RELAIS (P2) ET LES MOBILES (P3).
///
/// Tout ce qui sort est chiffré de bout en bout (AES-256-GCM, clé de clinique) ; la mère relève le relais, il ne la
/// contacte jamais. Port de la partie « pont » de `packages/sync/banc/mere.js` : réplication du journal, relève des
/// enveloppes des mobiles (rang contigu, authentification), boîtes aux lettres par appareil, lots de tournée,
/// restauration depuis le relais, battement de cœur et indicateurs sans nom de patient.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import 'commun.dart';
import 'mere.dart';

/// Chiffrement des enveloppes : même format que le banc Node (`crypto.js`) — nonce de 12 octets, `ct = chiffré ‖ tag`,
/// métadonnées authentifiées (AAD = `id|appareil|dir|n`). Une enveloppe déplacée, rejouée sous un autre rang ou altérée
/// est rejetée.
class Enveloppes {
  Enveloppes(List<int> cle) : _cle = SecretKey(cle);
  final SecretKey _cle;
  final AesGcm _aes = AesGcm.with256bits();

  Future<Map<String, Object?>> chiffrer(Map<String, Object?> charge, {required String id, required String appareil, required String dir, required int n}) async {
    final boite = await _aes.encrypt(utf8.encode(enJson(charge)), secretKey: _cle, aad: utf8.encode('$id|$appareil|$dir|$n'));
    return {
      'id': id, 'appareil': appareil, 'dir': dir, 'n': n,
      'nonce': base64.encode(boite.nonce),
      'ct': base64.encode([...boite.cipherText, ...boite.mac.bytes]),
    };
  }

  /// Lève une exception si l'authentification échoue (altération, mauvaise clé, métadonnées déplacées).
  Future<Map<String, Object?>> dechiffrer(Map env) async {
    final brut = base64.decode(env['ct'] as String);
    final boite = SecretBox(brut.sublist(0, brut.length - 16), nonce: base64.decode(env['nonce'] as String), mac: Mac(brut.sublist(brut.length - 16)));
    final clair = await _aes.decrypt(boite, secretKey: _cle, aad: utf8.encode('${env['id']}|${env['appareil']}|${env['dir']}|${env['n']}'));
    return (jsonDecode(utf8.decode(clair)) as Map).cast<String, Object?>();
  }
}

class Pont {
  Pont(this.mere) {
    final c = mere.cfg.cleBase64.isNotEmpty ? mere.cfg.cleBase64 : (mere.base.meta('cle') ?? '');
    _cleOctets = c.isNotEmpty ? base64.decode(c) : _cleAleatoire();
    mere.base.poserMeta('cle', base64.encode(_cleOctets));
    env = Enveloppes(_cleOctets);
  }

  final Mere mere;
  late final List<int> _cleOctets;
  late final Enveloppes env;
  final List<Map<String, Object?>> alertes = [];
  final HttpClient _http = HttpClient()..connectionTimeout = const Duration(milliseconds: 1500);
  final List<Timer> _minuteries = [];

  String get cleBase64 => base64.encode(_cleOctets);
  bool get actif => mere.cfg.relais.isNotEmpty;
  Base get base => mere.base;

  static List<int> _cleAleatoire() => List<int>.generate(32, (_) => int.parse(hexAlea(1), radix: 16));

  void alerter(Map<String, Object?> a) => alertes.add({'quand': maintenantMs(), ...a});

  Future<Map<String, Object?>> rel(String methode, String chemin, [Map<String, Object?>? corps]) async {
    final req = await _http.openUrl(methode, Uri.parse('${mere.cfg.relais}$chemin')).timeout(const Duration(milliseconds: 1500));
    req.headers.contentType = ContentType.json;
    req.headers.set('x-mere', mere.cfg.secretRelais);
    if (corps != null) req.add(utf8.encode(enJson(corps)));
    final rep = await req.close().timeout(const Duration(milliseconds: 1500));
    final texte = await utf8.decoder.bind(rep).join().timeout(const Duration(milliseconds: 1500));
    final j = texte.isEmpty ? <String, Object?>{} : (jsonDecode(texte) as Map).cast<String, Object?>();
    if (rep.statusCode >= 400) throw Err(rep.statusCode, '${j['code'] ?? 'http_${rep.statusCode}'}', '${j['motif'] ?? ''}');
    return j;
  }

  // --- côté administration ------------------------------------------------------------------------------
  Future<void> declarerCode(String hash) async {
    await rel('POST', '/mere/code', {'hash': hash});
  }

  void revoquerAuRelais(String uuid) {
    if (!actif) return;
    unawaited(rel('POST', '/mere/revoquer', {'uuid': uuid}).then((_) {}).catchError((Object _) {
      alerter({'type': 'revocation_relais_differee', 'appareil': uuid});
    }));
  }

  /// Une charge pour un mobile : mise en file PERSISTANTE (rang contigu) ; elle est chiffrée au dépôt.
  void publier(String uuid, Map<String, Object?> charge) {
    final n = base.metaInt('sortie_n:$uuid') + 1;
    base.poserMeta('sortie_n:$uuid', n);
    base.exec('INSERT INTO sortie(appareil,n,charge) VALUES(?,?,?)', [uuid, n, enJson(charge)]);
  }

  Map<String, Object?> lot(Map<String, Object?> b) {
    final fiches = <Map<String, Object?>>[];
    for (final f in (b['fiches'] as List)) {
      final x = mere.lire('${(f as Map)['collection']}', '${f['id']}');
      if (x == null) continue;
      base.exec('INSERT OR IGNORE INTO portee(appareil,collection,fiche) VALUES(?,?,?)', [b['uuid'], f['collection'], f['id']]);
      fiches.add({'collection': f['collection'], 'id': f['id'], 'data': x.data, 'fieldseq': x.fieldseq, 'archive': x.archive});
    }
    publier('${b['uuid']}', {'type': 'lot', 'expire': maintenantMs() + (nb(b['ttl_ms']) == 0 ? 48 * 3600 * 1000 : nb(b['ttl_ms']).toInt()), 'fiches': fiches});
    return {'fiches': fiches.length};
  }

  // --- tours de boucle ------------------------------------------------------------------------------------------
  Future<void> expedier() async {
    for (final r in base.select('SELECT * FROM sortie WHERE depose=0 ORDER BY appareil, n').toList()) {
      final uuid = r['appareil'] as String;
      final n = r['n'] as int;
      final charge = (jsonDecode(r['charge'] as String) as Map).cast<String, Object?>();
      await rel('POST', '/depot', {'enveloppe': await env.chiffrer(charge, id: 'm-$uuid-$n', appareil: uuid, dir: 'vers_mobile', n: n)});
      base.exec('UPDATE sortie SET depose=1 WHERE appareil=? AND n=?', [uuid, n]);
    }
  }

  Future<void> repliquer() async {
    if (base.meta('restauration') == 'en_cours') return;
    if ((base.meta('marqueur_epoch') ?? '').isNotEmpty) {
      final n = base.metaInt('rep_n') + 1;
      await rel('POST', '/depot', {'enveloppe': await env.chiffrer({'type': 'epoch', 'epoch': base.metaInt('epoch')}, id: 'journal-$n', appareil: 'mere', dir: 'journal', n: n)});
      base.poserMeta('rep_n', n);
      base.poserMeta('marqueur_epoch', '');
    }
    final ops = base
        .select('SELECT seq,id,appareil,epoch,hlc,collection,fiche,type,champs,famille FROM operations WHERE seq>? ORDER BY seq LIMIT 100', [base.metaInt('rep_seq')])
        .map((o) => {...o, 'champs': jsonDecode(o['champs'] as String)})
        .toList();
    if (ops.isEmpty) return;
    final n = base.metaInt('rep_n') + 1;
    await rel('POST', '/depot', {'enveloppe': await env.chiffrer({'type': 'journal', 'ops': ops}, id: 'journal-$n', appareil: 'mere', dir: 'journal', n: n)});
    base.poserMeta('rep_n', n);
    base.poserMeta('rep_seq', ops.last['seq']);
  }

  void diffuser() {
    for (final a in base.select("SELECT uuid FROM appareils WHERE role='mobile' AND etat='actif'").toList()) {
      final uuid = a['uuid'] as String;
      final brut = base.meta('sortie_seq:$uuid');
      if (brut == null) continue;
      final cur = int.parse(brut);
      final ops = base.select('SELECT seq,id,appareil,collection,fiche,type,champs FROM operations WHERE seq>? ORDER BY seq LIMIT 100', [cur]).toList();
      if (ops.isEmpty) continue;
      final siennes = ops
          .where((o) => base.select('SELECT 1 FROM portee WHERE appareil=? AND collection=? AND fiche=?', [uuid, o['collection'], o['fiche']]).isNotEmpty)
          .map((o) => {...o, 'champs': jsonDecode(o['champs'] as String)})
          .toList();
      base.poserMeta('sortie_seq:$uuid', ops.last['seq']);
      if (siennes.isNotEmpty) publier(uuid, {'type': 'ops', 'ops': siennes});
    }
  }

  void traiterEnveloppe(String uuid, Map<String, Object?> p) {
    if (p['type'] == 'hello') {
      if (base.select('SELECT 1 FROM appareils WHERE uuid=?', [uuid]).isNotEmpty) return;
      final r = base.select('SELECT * FROM codes WHERE code=?', ['${p['code'] ?? ''}']);
      final c = r.isEmpty ? null : r.first;
      if (c == null || c['role'] != 'mobile' || (c['utilise'] as int) != 0 || maintenantMs() > (c['expire'] as int)) {
        alerter({'type': 'appareil_inconnu', 'appareil': uuid});
        base.poserMeta('bloque:$uuid', 'inconnu');
        return;
      }
      base.exec('UPDATE codes SET utilise=1 WHERE code=?', [c['code']]);
      base.exec("INSERT INTO appareils(uuid,etiquette,role,etat,profil) VALUES(?,?,'mobile','actif',?)", [uuid, c['etiquette'], p['profil']]);
      final debut = base.metaInt('next_patient');
      final fin = debut + 19;
      base.poserMeta('next_patient', fin + 1);
      base.exec('INSERT INTO plages(appareil,nom,debut,fin) VALUES(?,?,?,?)', [uuid, 'patients', debut, fin]);
      base.poserMeta('sortie_seq:$uuid', mere.seqMax());
      publier(uuid, {'type': 'bienvenue', 'epoch': base.metaInt('epoch'), 'plage': {'debut': debut, 'fin': fin}});
      return;
    }
    final r = base.select('SELECT * FROM appareils WHERE uuid=?', [uuid]);
    if (r.isEmpty || r.first['etat'] == 'revoque') return;
    final app = Appareil(uuid, r.first['role'] as String, r.first['profil'] as String?);
    if (p['type'] == 'push') {
      try {
        publier(uuid, {'type': 'accuse', 'resultats': mere.pousser(app, p)['resultats']});
      } on Err catch (e) {
        publier(uuid, {'type': 'accuse', 'erreur': e.code, 'epoch_mere': e.corps['epoch_mere']});
      }
    }
  }

  Future<void> relever() async {
    final liste = (await rel('GET', '/mere/appareils'))['appareils'] as List;
    for (final a in liste) {
      final uuid = (a as Map)['uuid'] as String;
      if ((base.meta('bloque:$uuid') ?? '').isNotEmpty) continue;
      final dernier = base.metaInt('recu_n:$uuid');
      if ((a['max_n'] as int) <= dernier) continue;
      final envs = (await rel('GET', '/releve?dir=vers_mere&appareil=$uuid&depuis_n=$dernier&limite=50'))['env'] as List;
      for (final e in envs) {
        final enveloppe = e as Map;
        final attendu = base.metaInt('recu_n:$uuid') + 1;
        final n = enveloppe['n'] as int;
        if (n < attendu) continue;
        if (n > attendu) {
          alerter({'type': 'trou', 'appareil': uuid, 'attendu': attendu, 'recu': n});
          base.poserMeta('bloque:$uuid', 'trou');
          break;
        }
        Map<String, Object?> p;
        try {
          p = await env.dechiffrer(enveloppe);
        } catch (_) {
          alerter({'type': 'authentification', 'appareil': uuid, 'n': n});
          base.poserMeta('bloque:$uuid', 'auth');
          break;
        }
        base.tx(() {
          traiterEnveloppe(uuid, p);
          base.poserMeta('recu_n:$uuid', n);
        });
      }
    }
  }

  /// Restauration depuis le relais : TOUT est déchiffré et vérifié AVANT la moindre écriture.
  Future<void> restaurer() async {
    base.poserMeta('restauration', 'en_cours');
    try {
      final charges = <Map<String, Object?>>[];
      var n = 0;
      for (;;) {
        final rep = await rel('GET', '/releve?dir=journal&appareil=mere&depuis_n=$n&limite=100');
        for (final e in (rep['env'] as List)) {
          final enveloppe = e as Map;
          if (enveloppe['n'] != n + 1) throw 'trou dans le journal au rang ${n + 1}';
          charges.add(await env.dechiffrer(enveloppe));
          n = enveloppe['n'] as int;
        }
        if (rep['fin'] == true) break;
      }
      if (charges.isEmpty) throw 'journal vide';
      var maxSeq = 0;
      var maxEpoch = 1;
      base.tx(() {
        for (final p in charges) {
          if (p['type'] == 'epoch') {
            final liste = essentielles.map((c) => "'$c'").join(',');
            base.exec('DELETE FROM operations WHERE collection NOT IN ($liste)');
            base.exec('DELETE FROM fiches WHERE collection NOT IN ($liste)');
            maxEpoch = maxEpoch > (p['epoch'] as int) ? maxEpoch : p['epoch'] as int;
            continue;
          }
          for (final o in (p['ops'] as List)) {
            final op = (o as Map).cast<String, Object?>();
            final champs = (op['champs'] as Map).cast<String, Object?>();
            base.exec('INSERT INTO operations(seq,id,appareil,epoch,hlc,collection,fiche,type,champs,famille) VALUES(?,?,?,?,?,?,?,?,?,?)',
                [op['seq'], op['id'], op['appareil'], op['epoch'], op['hlc'], op['collection'], op['fiche'], op['type'], enJson(champs), op['famille']]);
            final f = mere.lire(op['collection'] as String, op['fiche'] as String) ?? Fiche({}, {}, false);
            final seq = op['seq'] as int;
            switch (op['type']) {
              case 'creer' || 'modifier':
                f.data.addAll(champs);
                for (final k in champs.keys) {
                  f.fieldseq[k] = seq;
                }
              case 'archiver':
                f.archive = true;
              case 'restaurer':
                f.archive = false;
              case 'sortie':
                f.data['qte'] = nb(f.data['qte']) - nb(champs['qte']);
                f.fieldseq['qte'] = seq;
            }
            mere.ecrire(op['collection'] as String, op['fiche'] as String, f);
            if (seq > maxSeq) maxSeq = seq;
            if ((op['epoch'] as int) > maxEpoch) maxEpoch = op['epoch'] as int;
          }
        }
        final nums = base
            .select("SELECT json_extract(data,'\$.code') AS c FROM fiches WHERE collection='patients'")
            .map((r) => int.tryParse(RegExp(r'^CNT/(\d+)/26$').firstMatch('${r['c'] ?? ''}')?.group(1) ?? '') ?? 0)
            .toList();
        final plusGrand = nums.fold<int>(1000, (a, b) => a > b ? a : b);
        base.poserMeta('next_patient', plusGrand + 1);
        base.poserMeta('rep_seq', maxSeq);
        base.poserMeta('rep_n', n);
        base.poserMeta('epoch', maxEpoch + 1);
        base.exec("INSERT OR REPLACE INTO sqlite_sequence(name,seq) VALUES('operations',?)", [maxSeq]);
      });
      base.poserMeta('restauration', 'terminee');
    } catch (e) {
      base.poserMeta('restauration', 'echec: $e');
    }
  }

  void demarrer() {
    if (!actif) return;
    if (mere.cfg.restaurer && (base.select('SELECT COUNT(*) AS n FROM operations').first['n'] as int) == 0) unawaited(restaurer());
    void tour(Future<void> Function() f, int ms) {
      var occupe = false;
      _minuteries.add(Timer.periodic(Duration(milliseconds: ms), (_) async {
        if (occupe) return;
        occupe = true;
        try {
          await f();
        } catch (_) {/* relais injoignable : on réessaie au tour suivant */}
        occupe = false;
      }));
    }

    tour(() async => base.meta('restauration') == 'en_cours' ? null : await relever(), 250);
    tour(() async {
      diffuser();
      await expedier();
    }, 250);
    tour(repliquer, 250);
    tour(() async {
      await rel('POST', '/mere/battement', {});
      final seq = mere.seqMax();
      await rel('POST', '/mere/indicateurs', {
        'indicateurs': {
          'patients_actifs': base.select("SELECT COUNT(*) AS n FROM fiches WHERE collection='patients' AND archive=0").first['n'],
          'seq_max': seq,
          'retard_replication': seq - base.metaInt('rep_seq'),
        },
      });
    }, 300);
  }
}
