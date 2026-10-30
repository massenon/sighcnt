/// LE MOBILE — profils « soignant » et « réception de secours » (spec §11). Port Dart de `packages/sync/banc/mobile.js`.
/// Il ne connaît QUE le relais : pas l'adresse de la mère, jamais le réseau local. Tout ce qu'il envoie et reçoit est
/// chiffré de bout en bout (clé de clinique reçue à l'appairage). Base locale, file persistée, rang d'envoi contigu,
/// lot expirant, effacement à la révocation (avec export de ce qui n'est pas parti).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'commun.dart';
import 'pont.dart' show Enveloppes;

class ConfigMobile {
  ConfigMobile({required this.port, required this.relais, required this.dbChemin, this.nom = 'mobile', this.intervalleMs = 150});
  final int port;
  final String relais;
  final String dbChemin;
  final String nom;
  final int intervalleMs;
}

class _Suspendu implements Exception {}

class _ErrRelais implements Exception {
  _ErrRelais(this.statut, this.code);
  final int statut;
  final String? code;
  @override
  String toString() => code ?? 'http_$statut';
}

class _S {
  _S(this.data, this.fieldseq, this.archive, this.dulot, this.existe);
  Map<String, Object?> data;
  Map<String, Object?> fieldseq;
  bool archive;
  bool dulot;
  bool existe;
  Map<String, Object?> json() => {'data': data, 'fieldseq': fieldseq, 'archive': archive, 'dulot': dulot, 'existe': existe};
}

class Mobile {
  Mobile(this.cfg) : base = Base(cfg.dbChemin) {
    base.exec('''
      CREATE TABLE IF NOT EXISTS confirme (collection TEXT, id TEXT, data TEXT, fieldseq TEXT, archive INTEGER, dulot INTEGER DEFAULT 0, PRIMARY KEY (collection, id));
      CREATE TABLE IF NOT EXISTS file (ordre INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT UNIQUE, op TEXT, etat TEXT, resultat TEXT);
      CREATE TABLE IF NOT EXISTS envois (n INTEGER PRIMARY KEY, enveloppe TEXT, depose INTEGER DEFAULT 0, ops TEXT);
    ''');
    if (base.meta('uuid') == null) base.poserMeta('uuid', uuid7());
    suspendu = base.meta('suspendu') == '1';
    _http.connectionTimeout = const Duration(milliseconds: 1500);
  }

  final ConfigMobile cfg;
  final Base base;
  final HttpClient _http = HttpClient();
  bool horsLigne = false;
  int tentatives = 0;
  bool suspendu = false;
  final List<String> exports = [];
  final List<Map<String, Object?>> alertes = [];
  int? lotPurgeLe;
  HttpServer? _serveur;

  String get uuid => base.meta('uuid')!;
  Enveloppes get _env => Enveloppes(base64.decode(base.meta('cle')!));

  // --- état local --------------------------------------------------------------------------------------------
  void appliquer(_S s, Map op, int seq) {
    bool garde(String k) => seq == 0 || nb(s.fieldseq[k]) < seq; // jamais de régression : un op plus ancien que l'état ne s'applique pas
    final champs = ((op['champs'] ?? {}) as Map).cast<String, Object?>();
    final type = op['type'];
    if (type == 'creer' || type == 'modifier') {
      for (final e in champs.entries) {
        if (garde(e.key)) {
          s.data[e.key] = e.value;
          if (seq != 0) s.fieldseq[e.key] = seq;
        }
      }
    } else if (type == 'archiver') {
      s.archive = true;
    } else if (type == 'restaurer') {
      s.archive = false;
    } else if (type == 'sortie') {
      if (garde('qte')) {
        s.data['qte'] = nb(s.data['qte']) - nb(champs['qte']);
        if (seq != 0) s.fieldseq['qte'] = seq;
      }
    }
  }

  _S lireConfirme(String c, String id) {
    final r = base.select('SELECT * FROM confirme WHERE collection=? AND id=?', [c, id]);
    if (r.isEmpty) return _S({}, {}, false, false, false);
    final x = r.first;
    return _S((jsonDecode(x['data'] as String) as Map).cast<String, Object?>(), (jsonDecode(x['fieldseq'] as String) as Map).cast<String, Object?>(),
        (x['archive'] as int) != 0, (x['dulot'] as int) != 0, true);
  }

  void ecrireConfirme(String c, String id, _S s) => base.exec('''
    INSERT INTO confirme(collection,id,data,fieldseq,archive,dulot) VALUES(?,?,?,?,?,?)
    ON CONFLICT(collection,id) DO UPDATE SET data=excluded.data, fieldseq=excluded.fieldseq, archive=excluded.archive, dulot=excluded.dulot''',
      [c, id, enJson(s.data), enJson(s.fieldseq), s.archive ? 1 : 0, s.dulot ? 1 : 0]);

  List<Map<String, Object?>> enVol() {
    final lignes = base.select('''
      SELECT op, resultat, etat FROM file
      WHERE etat IN ('en_attente','envoyee') OR (etat='acceptee' AND CAST(json_extract(resultat,'\$.seq') AS INTEGER) > ?) ORDER BY ordre''', [base.metaInt('curseur_seq')]);
    return lignes.map((r) {
      final op = (jsonDecode(r['op'] as String) as Map).cast<String, Object?>();
      if (r['etat'] == 'acceptee') {
        final res = jsonDecode(r['resultat'] as String) as Map;
        if (res['numero'] != null) (op['champs'] as Map)['code'] = res['numero'];
      }
      return op;
    }).toList();
  }

  _S vue(String c, String id) {
    final s = lireConfirme(c, id);
    for (final op in enVol()) {
      if (op['collection'] == c && op['fiche'] == id) {
        appliquer(s, op, 0);
        s.existe = true;
      }
    }
    return s;
  }

  List<Map<String, Object?>> liste(String c) {
    final ids = <String>{...base.select('SELECT id FROM confirme WHERE collection=?', [c]).map((r) => r['id'] as String)};
    for (final op in enVol()) {
      if (op['collection'] == c) ids.add(op['fiche'] as String);
    }
    return ids.map((id) => {'id': id, ...vue(c, id).json()}).where((x) => x['existe'] == true).toList();
  }

  String prochainNumero() {
    final d = base.metaInt('plage_prochain');
    final f = base.metaInt('plage_fin', -1);
    if (d != 0 && d <= f) {
      base.poserMeta('plage_prochain', d + 1);
      return 'CNT/$d/26';
    }
    return 'PROV-${hexAlea(4)}';
  }

  Map<String, Object?> ecrire(Map<String, Object?> cmd) {
    final champs = {...((cmd['champs'] ?? {}) as Map).cast<String, Object?>()};
    final op = <String, Object?>{
      'id': uuid7(), 'appareil': uuid, 'epoch': base.metaInt('epoch', 1), 'hlc': maintenantMs(),
      'collection': cmd['collection'], 'fiche': cmd['fiche'] ?? uuid7(), 'type': cmd['type'], 'champs': champs, 'vu': <String, Object?>{},
    };
    if (op['type'] == 'modifier') {
      final b = lireConfirme(op['collection'] as String, op['fiche'] as String);
      op['vu'] = <String, Object?>{for (final k in champs.keys) k: b.fieldseq[k] ?? 0};
    }
    if (op['type'] == 'creer' && op['collection'] == 'patients' && (champs['code'] == null || '${champs['code']}'.isEmpty)) champs['code'] = prochainNumero();
    base.exec("INSERT INTO file(id,op,etat) VALUES(?,?,'en_attente')", [op['id'], enJson(op)]);
    return {'id': op['id'], 'fiche': op['fiche'], 'champs': champs};
  }

  // --- relais ---------------------------------------------------------------------------------------------------------
  Future<Map<String, Object?>> rel(String methode, String chemin, [Map<String, Object?>? corps]) async {
    final req = await _http.openUrl(methode, Uri.parse('${cfg.relais}$chemin')).timeout(const Duration(milliseconds: 1500));
    req.headers.contentType = ContentType.json;
    final jeton = base.meta('jeton');
    if (jeton != null && jeton.isNotEmpty) req.headers.set('Authorization', 'Bearer $jeton');
    if (corps != null) req.add(utf8.encode(enJson(corps)));
    final rep = await req.close().timeout(const Duration(milliseconds: 1500));
    final texte = await utf8.decoder.bind(rep).join().timeout(const Duration(milliseconds: 1500));
    final j = texte.isEmpty ? <String, Object?>{} : (jsonDecode(texte) as Map).cast<String, Object?>();
    if (rep.statusCode == 401 && j['code'] == 'appareil_revoque') {
      revoque();
      throw _Suspendu();
    }
    if (rep.statusCode >= 400) throw _ErrRelais(rep.statusCode, j['code'] as String?);
    return j;
  }

  /// Révocation : on exporte ce qui n'est pas parti, puis on EFFACE les données de santé de l'appareil (spec §11).
  void revoque() {
    final nonEnvoyees = base.select("SELECT op FROM file WHERE etat IN ('en_attente','envoyee')").map((r) => jsonDecode(r['op'] as String)).toList();
    if (nonEnvoyees.isNotEmpty) {
      final f = '${cfg.dbChemin == ':memory:' ? cfg.nom : cfg.dbChemin}.export-${maintenantMs()}.json';
      File(f).writeAsStringSync(const JsonEncoder.withIndent(' ').convert({'operations': nonEnvoyees}));
      exports.add(f);
    }
    for (final t in ['confirme', 'file', 'envois']) {
      base.exec('DELETE FROM $t');
    }
    base.poserMeta('suspendu', 1);
    suspendu = true;
  }

  void purgerLotExpire() {
    final exp = base.metaInt('lot_expire');
    if (exp == 0 || maintenantMs() < exp) return;
    final enAttente = base.select("SELECT op FROM file WHERE etat IN ('en_attente','envoyee')").map((r) {
      final o = jsonDecode(r['op'] as String) as Map;
      return '${o['collection']}|${o['fiche']}';
    }).toSet();
    for (final f in base.select('SELECT collection,id FROM confirme WHERE dulot=1').toList()) {
      if (!enAttente.contains('${f['collection']}|${f['id']}')) base.exec('DELETE FROM confirme WHERE collection=? AND id=?', [f['collection'], f['id']]);
    }
    base.poserMeta('lot_expire', 0);
    lotPurgeLe = maintenantMs();
  }

  void recevoir(Map<String, Object?> p) {
    switch (p['type']) {
      case 'bienvenue':
        base.poserMeta('epoch', p['epoch']);
        final plage = (p['plage'] as Map);
        base.poserMeta('plage_prochain', plage['debut']);
        base.poserMeta('plage_fin', plage['fin']);
        base.poserMeta('bienvenu', 1);
      case 'lot':
        base.poserMeta('lot_expire', p['expire']);
        for (final f in (p['fiches'] as List)) {
          final x = (f as Map);
          ecrireConfirme(x['collection'] as String, x['id'] as String,
              _S((x['data'] as Map).cast<String, Object?>(), (x['fieldseq'] as Map).cast<String, Object?>(), x['archive'] == true, true, true));
        }
      case 'ops':
        for (final o in (p['ops'] as List)) {
          final op = (o as Map);
          final s = lireConfirme(op['collection'] as String, op['fiche'] as String);
          appliquer(s, op, (op['seq'] as num).toInt());
          ecrireConfirme(op['collection'] as String, op['fiche'] as String, s);
          final cs = base.metaInt('curseur_seq');
          if ((op['seq'] as num) > cs) base.poserMeta('curseur_seq', op['seq']);
        }
      case 'accuse':
        if (p['erreur'] == 'epoch_inconnue') {
          revoque();
          base.poserMeta('suspendu', 0);
          suspendu = false;
          base.poserMeta('epoch', p['epoch_mere']);
          return;
        }
        for (final r in (p['resultats'] as List)) {
          final res = (r as Map);
          base.exec('UPDATE file SET etat=?, resultat=? WHERE id=?', [res['statut'], enJson(res), res['id']]);
        }
        base.exec('UPDATE envois SET depose=2 WHERE depose=1');
    }
  }

  Future<void> cycle() async {
    if (suspendu || (base.meta('jeton') ?? '').isEmpty) return;
    try {
      purgerLotExpire();
      // 1. ma boîte
      final maxN = (await rel('GET', '/compteur'))['max_n'] as int;
      var dernier = base.metaInt('curseur_n');
      while (maxN > dernier) {
        final envs = (await rel('GET', '/releve?dir=vers_mobile&appareil=$uuid&depuis_n=$dernier&limite=50'))['env'] as List;
        if (envs.isEmpty) break;
        for (final e in envs) {
          final enveloppe = e as Map;
          final n = enveloppe['n'] as int;
          if (n != dernier + 1) {
            alertes.add({'type': 'trou', 'attendu': dernier + 1, 'recu': n});
            return;
          }
          Map<String, Object?> p;
          try {
            p = await _env.dechiffrer(enveloppe);
          } catch (_) {
            alertes.add({'type': 'authentification', 'n': n});
            return;
          }
          base.tx(() {
            recevoir(p);
            base.poserMeta('curseur_n', n);
          });
          dernier = n;
        }
      }
      // 2. envoyer : un rang n'est alloué qu'UNE fois et persisté avant le dépôt ; il se redépose à l'identique
      if (base.select('SELECT 1 FROM envois WHERE depose=0').isEmpty) {
        final lot = base.select("SELECT id,op FROM file WHERE etat='en_attente' ORDER BY ordre LIMIT 100").toList();
        if (lot.isNotEmpty) {
          final n = base.metaInt('sortie_n') + 1;
          base.poserMeta('sortie_n', n);
          final ops = lot.map((r) => jsonDecode(r['op'] as String)).toList();
          final env = await _env.chiffrer({'type': 'push', 'epoch': base.metaInt('epoch', 1), 'ops': ops}, id: '$uuid-$n', appareil: uuid, dir: 'vers_mere', n: n);
          base.exec('INSERT INTO envois(n,enveloppe,ops) VALUES(?,?,?)', [n, enJson(env), enJson(lot.map((r) => r['id']).toList())]);
        }
      }
      for (final e in base.select('SELECT * FROM envois WHERE depose=0 ORDER BY n').toList()) {
        await rel('POST', '/depot', {'enveloppe': jsonDecode(e['enveloppe'] as String)});
        base.exec('UPDATE envois SET depose=1 WHERE n=?', [e['n']]);
        for (final id in (jsonDecode(e['ops'] as String) as List)) {
          base.exec("UPDATE file SET etat='envoyee' WHERE id=? AND etat='en_attente'", [id]);
        }
      }
      horsLigne = false;
      tentatives = 0;
    } on _Suspendu {
      return;
    } catch (_) {
      horsLigne = true;
      tentatives++;
    }
  }

  Future<void> boucle() async {
    for (;;) {
      await cycle();
      await Future<void>.delayed(Duration(milliseconds: min(cfg.intervalleMs * (1 << min(tentatives, 3)), 1000)));
    }
  }

  // --- commande ---------------------------------------------------------------------------------------------------
  Future<(int, Object?)> commande(String cle, Map<String, Object?> b, Map<String, String> q) async {
    switch (cle) {
      case 'POST /appairer':
        base.poserMeta('cle', b['cle']);
        base.poserMeta('profil', b['profil'] ?? 'soignant');
        final req = await _http.postUrl(Uri.parse('${cfg.relais}/appairage'));
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(enJson({'code': b['code'], 'uuid': uuid})));
        final rep = await req.close();
        final j = (jsonDecode(await utf8.decoder.bind(rep).join()) as Map).cast<String, Object?>();
        if (rep.statusCode >= 400) return (rep.statusCode, j);
        base.poserMeta('jeton', j['jeton']);
        base.poserMeta('epoch', 1);
        base.poserMeta('suspendu', 0);
        suspendu = false;
        base.poserMeta('sortie_n', 1);
        final env = await _env.chiffrer({'type': 'hello', 'code': b['code'], 'profil': base.meta('profil'), 'plateforme': 'banc'}, id: '$uuid-1', appareil: uuid, dir: 'vers_mere', n: 1);
        base.exec('INSERT INTO envois(n,enveloppe,ops) VALUES(?,?,?)', [1, enJson(env), '[]']);
        return (200, {'uuid': uuid});
      case 'GET /secret':
        return (200, {'jeton': base.meta('jeton')});
      case 'POST /ecrire':
        return (200, ecrire(b));
      case 'GET /vue':
        return (200, vue(q['collection'] ?? '', q['id'] ?? '').json());
      case 'GET /liste':
        return (200, liste(q['collection'] ?? ''));
      case 'GET /etat':
        return (200, {
          'hors_ligne': horsLigne, 'tentatives': tentatives, 'suspendu': suspendu, 'exports': exports, 'alertes': alertes,
          'uuid': uuid, 'bienvenu': base.meta('bienvenu') == '1', 'epoch': base.metaInt('epoch', 1), 'curseur_n': base.metaInt('curseur_n'),
          'lot_expire': base.metaInt('lot_expire'),
          'en_attente': base.select("SELECT COUNT(*) AS n FROM file WHERE etat IN ('en_attente','envoyee')").first['n'],
          'a_traiter': base.select("SELECT resultat FROM file WHERE etat='refusee'").map((r) => jsonDecode(r['resultat'] as String)).toList(),
          'resultats': base.select('SELECT id,etat,resultat FROM file ORDER BY ordre').map((r) => {
                'id': r['id'], 'etat': r['etat'], ...(r['resultat'] == null ? {} : (jsonDecode(r['resultat'] as String) as Map).cast<String, Object?>()),
              }).toList(),
          'plage': {'prochain': base.metaInt('plage_prochain'), 'fin': base.metaInt('plage_fin', -1)},
          if (lotPurgeLe != null) 'lot_purge_le': lotPurgeLe,
        });
    }
    return (404, {'code': 'commande_inconnue'});
  }

  Future<void> demarrer() async {
    _serveur = await HttpServer.bind(InternetAddress.loopbackIPv4, cfg.port);
    unawaited(boucle());
    _serveur!.listen((req) async {
      final b = await corpsJson(req);
      int st;
      Object? out;
      try {
        (st, out) = await commande('${req.method} ${req.uri.path}', b, req.uri.queryParameters);
      } catch (e) {
        st = 500;
        out = {'code': e is _ErrRelais ? e.code : 'erreur', 'motif': '$e'};
      }
      try {
        await repondre(req, st, out);
      } catch (_) {/* le client est parti */}
    });
    annoncerPret(_serveur!.port);
  }
}
