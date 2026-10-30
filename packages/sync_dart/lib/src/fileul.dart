/// LE POSTE FILEUL — client de synchronisation (spec §3-§7). Port Dart du banc `packages/sync/banc/fileul.js` :
/// base locale, file d'envoi persistée, curseur, « on reçoit toujours avant d'envoyer », reprise après coupure,
/// suspension à la révocation, export avant purge d'époque. Une petite API de COMMANDE (HTTP local) permet au banc
/// de piloter le poste comme le ferait un utilisateur ; l'interface Flutter appellera les mêmes méthodes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'commun.dart';

class ConfigFileul {
  ConfigFileul({required this.port, required this.mere, required this.dbChemin, this.nom = 'poste', this.decalageMs = 0, this.intervalleMs = 150});
  final int port;
  final String mere;
  final String dbChemin;
  final String nom;
  final int decalageMs;
  final int intervalleMs;
}

class _Suspendu implements Exception {}

class _Epoque implements Exception {}

class _ErrHttp implements Exception {
  _ErrHttp(this.statut, this.code, this.corps);
  final int statut;
  final String? code;
  final Map<String, Object?> corps;
  @override
  String toString() => '${code ?? 'http_$statut'}';
}

class Etat {
  bool horsLigne = false;
  int tentatives = 0;
  bool suspendu = false;
  int cycles = 0;
  String? derniereErreur;
  final List<String> exports = [];
}

class _S {
  _S(this.data, this.fieldseq, this.archive, this.existe);
  Map<String, Object?> data;
  Map<String, Object?> fieldseq;
  bool archive;
  bool existe;
  Map<String, Object?> json() => {'data': data, 'fieldseq': fieldseq, 'archive': archive, 'existe': existe};
}

class Fileul {
  Fileul(this.cfg) : base = Base(cfg.dbChemin) {
    base.exec('''
      CREATE TABLE IF NOT EXISTS confirme (collection TEXT, id TEXT, data TEXT, fieldseq TEXT, archive INTEGER, PRIMARY KEY (collection, id));
      CREATE TABLE IF NOT EXISTS file (ordre INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT UNIQUE, op TEXT, etat TEXT, resultat TEXT);
      CREATE TABLE IF NOT EXISTS plage (nom TEXT PRIMARY KEY, prochain INTEGER, fin INTEGER);
      CREATE TABLE IF NOT EXISTS baux (article TEXT PRIMARY KEY, reste INTEGER);
    ''');
    if (base.meta('uuid') == null) base.poserMeta('uuid', uuid7());
    if (base.meta('curseur') == null) base.poserMeta('curseur', 0);
    if (base.meta('epoch') == null) base.poserMeta('epoch', 1);
    etat.suspendu = base.meta('suspendu') == '1';
    _client.connectionTimeout = const Duration(milliseconds: 1500);
    _client.idleTimeout = const Duration(seconds: 3);
  }

  final ConfigFileul cfg;
  final Base base;
  final Etat etat = Etat();
  final HttpClient _client = HttpClient();
  HttpServer? _serveur;
  String get uuid => base.meta('uuid')!;
  int maintenant() => maintenantMs() + cfg.decalageMs;

  // --- application d'une opération sur un état ------------------------------------------------------
  void appliquer(_S s, Map op, int seq) {
    final type = op['type'];
    final champs = ((op['champs'] ?? {}) as Map).cast<String, Object?>();
    if (type == 'creer' || type == 'modifier') {
      s.data.addAll(champs);
      if (seq != 0) for (final k in champs.keys) s.fieldseq[k] = seq;
    } else if (type == 'archiver') {
      s.archive = true;
    } else if (type == 'restaurer') {
      s.archive = false;
    } else if (type == 'sortie') {
      s.data['qte'] = (nb(s.data['qte'])) - nb(champs['qte']);
      if (seq != 0) s.fieldseq['qte'] = seq;
    }
  }

  _S lireConfirme(String c, String id) {
    final r = base.select('SELECT * FROM confirme WHERE collection=? AND id=?', [c, id]);
    if (r.isEmpty) return _S({}, {}, false, false);
    final x = r.first;
    return _S((jsonDecode(x['data'] as String) as Map).cast<String, Object?>(), (jsonDecode(x['fieldseq'] as String) as Map).cast<String, Object?>(),
        (x['archive'] as int) != 0, true);
  }

  void ecrireConfirme(String c, String id, _S s) => base.exec('''
    INSERT INTO confirme(collection,id,data,fieldseq,archive) VALUES(?,?,?,?,?)
    ON CONFLICT(collection,id) DO UPDATE SET data=excluded.data, fieldseq=excluded.fieldseq, archive=excluded.archive''',
      [c, id, enJson(s.data), enJson(s.fieldseq), s.archive ? 1 : 0]);

  /// Les opérations « en l'air » : en attente d'envoi, OU acceptées par la mère mais pas encore revenues dans le flux
  /// (seq > curseur). Sans ce second cas, un dossier qu'on vient de créer DISPARAÎT de l'écran entre l'accusé et le tirage.
  List<Map<String, Object?>> enVol() {
    final lignes = base.select('''
      SELECT op, resultat, etat FROM file
      WHERE etat='en_attente' OR (etat='acceptee' AND CAST(json_extract(resultat,'\$.seq') AS INTEGER) > ?) ORDER BY ordre''', [base.metaInt('curseur')]);
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
    final p = base.select("SELECT * FROM plage WHERE nom='patients'");
    if (p.isNotEmpty && (p.first['prochain'] as int) <= (p.first['fin'] as int)) {
      final n = p.first['prochain'] as int;
      base.exec("UPDATE plage SET prochain=prochain+1 WHERE nom='patients'");
      return 'CNT/$n/26';
    }
    return 'PROV-${hexAlea(4)}';
  }

  /// Un geste d'écriture : visible tout de suite, file persistée. Rend `{id, fiche, champs}` ou `{refus, motif}`.
  Map<String, Object?> ecrire(Map<String, Object?> cmd) {
    final champs = {...((cmd['champs'] ?? {}) as Map).cast<String, Object?>()};
    final op = <String, Object?>{
      'id': uuid7(), 'appareil': uuid, 'epoch': base.metaInt('epoch'), 'hlc': maintenant(),
      'collection': cmd['collection'], 'fiche': cmd['fiche'] ?? uuid7(), 'type': cmd['type'], 'champs': champs, 'vu': <String, Object?>{},
    };
    if (cmd['bail'] == true) op['bail'] = true;
    if (op['type'] == 'modifier') {
      final b = lireConfirme(op['collection'] as String, op['fiche'] as String);
      op['vu'] = <String, Object?>{for (final k in champs.keys) k: b.fieldseq[k] ?? 0};
    }
    if (op['type'] == 'creer' && op['collection'] == 'patients' && (champs['code'] == null || '${champs['code']}'.isEmpty)) {
      champs['code'] = prochainNumero();
    }
    if (op['type'] == 'sortie' && op['bail'] == true) {
      final b = base.select('SELECT reste FROM baux WHERE article=?', [op['fiche']]);
      final qte = nb(champs['qte']);
      if (b.isEmpty || (b.first['reste'] as num) < qte) {
        return {'refus': 'bail_insuffisant', 'motif': 'Quota local insuffisant pour ${op['fiche']} (reste ${b.isEmpty ? 0 : b.first['reste']}).'};
      }
      base.exec('UPDATE baux SET reste=reste-? WHERE article=?', [qte, op['fiche']]);
    }
    base.exec("INSERT INTO file(id,op,etat) VALUES(?,?,'en_attente')", [op['id'], enJson(op)]);
    return {'id': op['id'], 'fiche': op['fiche'], 'champs': champs};
  }

  // --- réseau ---------------------------------------------------------------------------------------------
  Future<Map<String, Object?>> http1(String methode, String chemin, [Map<String, Object?>? corps, bool essai = false]) async {
    final jeton = base.meta('jeton');
    final req = await _client.openUrl(methode, Uri.parse('${cfg.mere}$chemin')).timeout(const Duration(milliseconds: 1500));
    req.headers.contentType = ContentType.json;
    if (jeton != null && jeton.isNotEmpty) req.headers.set('Authorization', 'Bearer $jeton');
    if (corps != null) req.add(utf8.encode(enJson(corps)));
    final rep = await req.close().timeout(const Duration(milliseconds: 1500));
    final texte = await utf8.decoder.bind(rep).join().timeout(const Duration(milliseconds: 1500));
    final j = (jsonDecode(texte) as Map).cast<String, Object?>();
    final code = j['code'] as String?;
    if (rep.statusCode == 401 && code == 'jeton_expire' && !essai) {
      await _renouveler();
      return http1(methode, chemin, corps, true);
    }
    if (rep.statusCode == 401 && code == 'appareil_revoque') {
      base.poserMeta('suspendu', 1);
      etat.suspendu = true;
      throw _Suspendu();
    }
    if (rep.statusCode == 409 && code == 'epoch_inconnue') {
      traiterEpoque(nb(j['epoch_mere']).toInt());
      throw _Epoque();
    }
    if (rep.statusCode >= 400) throw _ErrHttp(rep.statusCode, code, j);
    return j;
  }

  Future<void> _renouveler() async {
    final req = await _client.postUrl(Uri.parse('${cfg.mere}/renouveler')).timeout(const Duration(milliseconds: 1500));
    req.headers.contentType = ContentType.json;
    req.add(utf8.encode(enJson({'renouvellement': base.meta('renouvellement')})));
    final rep = await req.close().timeout(const Duration(milliseconds: 1500));
    final j = (jsonDecode(await utf8.decoder.bind(rep).join()) as Map).cast<String, Object?>();
    if (rep.statusCode >= 400) {
      if (j['code'] == 'appareil_revoque') {
        base.poserMeta('suspendu', 1);
        etat.suspendu = true;
      }
      throw _ErrHttp(rep.statusCode, j['code'] as String?, j);
    }
    base.poserMeta('jeton', j['jeton']);
    base.poserMeta('renouvellement', j['renouvellement']);
  }

  /// Époque inconnue : on N'EFFACE RIEN avant d'avoir exporté ce qui n'est pas parti.
  void traiterEpoque(int epochMere) {
    final nonEnvoyees = base.select("SELECT op FROM file WHERE etat='en_attente' ORDER BY ordre").map((r) => jsonDecode(r['op'] as String)).toList();
    if (nonEnvoyees.isNotEmpty) {
      final f = '${cfg.dbChemin == ':memory:' ? cfg.nom : cfg.dbChemin}.export-${maintenantMs()}.json';
      File(f).writeAsStringSync(const JsonEncoder.withIndent(' ').convert({'epoch_locale': base.metaInt('epoch'), 'operations': nonEnvoyees}));
      etat.exports.add(f);
    }
    base.tx(() {
      for (final t in ['confirme', 'file', 'plage', 'baux']) {
        base.exec('DELETE FROM $t');
      }
      base.poserMeta('curseur', 0);
      base.poserMeta('epoch', epochMere);
      base.poserMeta('resync_ack', '');
    });
  }

  Future<void> tirer() async {
    var plein = false;
    for (;;) {
      final j = await http1('GET', '/sync/pull?depuis=${base.meta('curseur')}&limite=500&epoch=${base.meta('epoch')}');
      final resync = j['resync'] as String?;
      if (resync != null && resync != (base.meta('resync_ack') ?? '') && !plein) {
        plein = true;
        base.exec('DELETE FROM confirme');
        base.poserMeta('curseur', 0);
        continue;
      }
      base.tx(() {
        for (final o in (j['ops'] as List)) {
          final op = (o as Map);
          final s = lireConfirme(op['collection'] as String, op['fiche'] as String);
          appliquer(s, op, (op['seq'] as num).toInt());
          ecrireConfirme(op['collection'] as String, op['fiche'] as String, s);
          base.poserMeta('curseur', op['seq']);
        }
      });
      if (j['fin'] == true) {
        if (resync != null && resync != (base.meta('resync_ack') ?? '')) {
          await http1('POST', '/sync/ack-resync', {'marque': resync});
          base.poserMeta('resync_ack', resync);
        }
        return;
      }
    }
  }

  Future<void> envoyer() async {
    final lot = base.select("SELECT op FROM file WHERE etat='en_attente' ORDER BY ordre LIMIT 200").map((r) => jsonDecode(r['op'] as String)).toList();
    if (lot.isEmpty) return;
    final rep = await http1('POST', '/sync/push', {'epoch': base.metaInt('epoch'), 'horloge': maintenant(), 'ops': lot});
    base.tx(() {
      for (final r in (rep['resultats'] as List)) {
        final res = (r as Map);
        base.exec('UPDATE file SET etat=?, resultat=? WHERE id=?', [res['statut'], enJson(res), res['id']]);
      }
    });
  }

  Future<void> cycle() async {
    if (etat.suspendu) return;
    etat.cycles++;
    try {
      await tirer();
      await envoyer();
      await tirer();
      etat.horsLigne = false;
      etat.tentatives = 0;
      etat.derniereErreur = null;
    } on _Suspendu {
      etat.derniereErreur = 'suspendu';
    } on _Epoque {
      etat.derniereErreur = 'epoque';
    } catch (e) {
      etat.derniereErreur = e is _ErrHttp ? (e.code ?? 'http_${e.statut}') : '$e';
      etat.horsLigne = true;
      etat.tentatives++;
    }
  }

  Future<void> boucle() async {
    for (;;) {
      await cycle();
      await Future<void>.delayed(Duration(milliseconds: min(cfg.intervalleMs * (1 << min(etat.tentatives, 3)), 1000)));
    }
  }

  // --- commande (le « clavier » du banc) ---------------------------------------------------------------------
  Future<(int, Object?)> commande(String cle, Map<String, Object?> b, Map<String, String> q) async {
    switch (cle) {
      case 'POST /appairer':
        final req = await _client.postUrl(Uri.parse('${cfg.mere}/appairage'));
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(enJson({'code': b['code'], 'uuid': uuid, 'plateforme': 'banc'})));
        final rep = await req.close();
        final j = (jsonDecode(await utf8.decoder.bind(rep).join()) as Map).cast<String, Object?>();
        if (rep.statusCode >= 400) return (rep.statusCode, j);
        base.poserMeta('jeton', j['jeton']);
        base.poserMeta('renouvellement', j['renouvellement']);
        base.poserMeta('epoch', j['epoch']);
        base.poserMeta('suspendu', 0);
        etat.suspendu = false;
        return (200, {'uuid': uuid});
      case 'POST /plage':
        final j = await http1('POST', '/sync/plage', {'nom': 'patients', 'taille': b['taille'] ?? 50});
        base.exec("INSERT INTO plage(nom,prochain,fin) VALUES('patients',?,?) ON CONFLICT(nom) DO UPDATE SET prochain=excluded.prochain, fin=excluded.fin", [j['debut'], j['fin']]);
        return (200, j);
      case 'POST /bail':
        final j2 = await http1('POST', '/sync/bail', {'article': b['article'], 'qte': b['qte']});
        base.exec('INSERT INTO baux(article,reste) VALUES(?,?) ON CONFLICT(article) DO UPDATE SET reste=reste+excluded.reste', [b['article'], j2['accorde']]);
        return (200, j2);
      case 'POST /ecrire':
        return (200, ecrire(b));
      case 'POST /renouveler-force':
        try {
          await _renouveler();
          return (200, {'ok': true});
        } on _ErrHttp catch (e) {
          return (401, {'code': e.code});
        }
      case 'POST /expirer-jeton':
        base.poserMeta('jeton', 'x.invalide');
        return (200, {});
      case 'GET /renouv':
        return (200, {'renouvellement': base.meta('renouvellement')});
      case 'GET /vue':
        return (200, vue(q['collection'] ?? '', q['id'] ?? '').json());
      case 'GET /liste':
        return (200, liste(q['collection'] ?? ''));
      case 'GET /etat':
        return (200, {
          'hors_ligne': etat.horsLigne, 'tentatives': etat.tentatives, 'suspendu': etat.suspendu, 'cycles': etat.cycles,
          'derniere_erreur': etat.derniereErreur, 'exports': etat.exports,
          'uuid': uuid, 'epoch': base.metaInt('epoch'), 'curseur': base.metaInt('curseur'),
          'en_attente': base.select("SELECT COUNT(*) AS n FROM file WHERE etat='en_attente'").first['n'],
          'a_traiter': base.select("SELECT resultat FROM file WHERE etat='refusee'").map((r) => jsonDecode(r['resultat'] as String)).toList(),
          'fusionnees': base.select("SELECT resultat FROM file WHERE etat='fusionnee'").map((r) => jsonDecode(r['resultat'] as String)).toList(),
          'acceptees': base.select("SELECT COUNT(*) AS n FROM file WHERE etat='acceptee'").first['n'],
          'resultats': base.select('SELECT id,etat,resultat FROM file ORDER BY ordre').map((r) => {
                'id': r['id'], 'etat': r['etat'], ...(r['resultat'] == null ? {} : (jsonDecode(r['resultat'] as String) as Map).cast<String, Object?>()),
              }).toList(),
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
        out = {'code': e is _ErrHttp ? e.code : 'erreur', 'motif': '$e'};
      }
      try {
        await repondre(req, st, out);
      } catch (_) {/* le client est parti */}
    });
    annoncerPret(_serveur!.port);
  }
}
