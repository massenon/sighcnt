/// UN FILEUL EN MODE PAIR (ADR-0006), port Dart de `packages/sync/banc/pair-fileul.js` : un poste qui n'a PAS besoin de la mère. Il publie ses opérations (chiffrées de
/// bout en bout) dans SON journal au relais, relève les journaux des autres appareils (la mère comprise : son journal porte le `seq` qui fait foi et ses décisions),
/// et calcule son état par la règle de fusion du domaine ([etatPair]), fonction pure de l'ensemble des opérations. Tout est persisté : un SIGKILL à n'importe quel
/// moment ne perd rien (file de publication à rang contigu, curseurs, opérations reçues). Le relais ne voit que des enveloppes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';

import 'commun.dart';
import 'ordre_copie.dart';
import 'pont.dart' show Enveloppes;

class ConfigPair {
  ConfigPair({required this.port, required this.relais, required this.dbChemin, required this.cleHex, this.nom = 'poste', this.decalageMs = 0, this.intervalleMs = 120, this.cleStockage = '', this.droits, this.collectionsCopie = const {}});
  final int port, decalageMs, intervalleMs;
  final String relais, dbChemin, cleHex, nom, cleStockage;

  /// Les droits de l'échange : la matrice RBAC en production (`droitsDepuisMatrice`), la table du banc par défaut.
  final DroitsOperation? droits;

  /// Les collections dont ce poste dépose la COPIE chiffrée au relais (PRD relais consultable). Vide : aucune copie.
  final Set<String> collectionsCopie;
}

List<int> _octets(String hex) => [for (var i = 0; i + 1 < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];

class FileulPair {
  FileulPair(this.cfg)
      : base = Base(cfg.dbChemin, cfg.cleStockage),
        env = Enveloppes(_octets(cfg.cleHex)),
        horloge = HorlogePair(maintenantMs: () => maintenantMs() + cfg.decalageMs) {
    base.exec('''CREATE TABLE IF NOT EXISTS ops (id TEXT PRIMARY KEY, appareil TEXT, json TEXT);
      CREATE TABLE IF NOT EXISTS sortie (n INTEGER PRIMARY KEY, id TEXT, depose INTEGER DEFAULT 0);
      CREATE TABLE IF NOT EXISTS curseurs (appareil TEXT PRIMARY KEY, n INTEGER);
      CREATE TABLE IF NOT EXISTS foi (id TEXT PRIMARY KEY, seq INTEGER);
      CREATE TABLE IF NOT EXISTS copie_sortie (n INTEGER PRIMARY KEY, id TEXT, charge TEXT, depose INTEGER DEFAULT 0);
      CREATE TABLE IF NOT EXISTS copie_etat (cle TEXT PRIMARY KEY, empreinte TEXT);
      CREATE TABLE IF NOT EXISTS copie_ops (id TEXT PRIMARY KEY, cle TEXT);
      CREATE TABLE IF NOT EXISTS copie_a_faire (cle TEXT PRIMARY KEY);
      CREATE INDEX IF NOT EXISTS copie_ops_cle ON copie_ops(cle);
      CREATE TABLE IF NOT EXISTS anomalies (k INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT, detail TEXT);''');
    horloge.dernier = base.metaInt('hlc');
    droits = cfg.droits ?? droitsDepuisTable(droitsBancPair);
  }

  final ConfigPair cfg;
  final Base base;
  final Enveloppes env;
  final HorlogePair horloge;
  late final DroitsOperation droits;
  final HttpClient _client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  HttpServer? _serveur;
  bool horsLigne = false, _enCours = false;
  int cycles = 0;

  Future<(int, Map<String, Object?>)> _relais(String methode, String chemin, [Object? corps]) async {
    final req = await _client.openUrl(methode, Uri.parse('${cfg.relais}$chemin')).timeout(const Duration(seconds: 3));
    req.headers.contentType = ContentType.json;
    final jeton = base.meta('jeton');
    if (jeton != null) req.headers.set('Authorization', 'Bearer $jeton');
    if (corps != null) req.add(utf8.encode(enJson(corps)));
    final rep = await req.close().timeout(const Duration(seconds: 3));
    final texte = await utf8.decoder.bind(rep).join().timeout(const Duration(seconds: 3));
    Map<String, Object?> j = {};
    try {
      final d = jsonDecode(texte);
      if (d is Map) j = d.cast<String, Object?>();
    } catch (_) {/* corps vide */}
    return (rep.statusCode, j);
  }

  List<OperationPair> toutesOps() {
    final foi = {for (final r in base.select('SELECT id,seq FROM foi')) r['id'] as String: r['seq'] as int};
    return [
      for (final r in base.select('SELECT json FROM ops'))
        () {
          final j = (jsonDecode(r['json'] as String) as Map).cast<String, Object?>();
          if (j['seq'] == null && foi.containsKey(j['id'])) j['seq'] = foi[j['id']];
          return OperationPair.depuisJson(j);
        }()
    ];
  }

  void _anomalie(String type, Object? detail) => base.exec('INSERT INTO anomalies(type,detail) VALUES(?,?)', [type, enJson(detail)]);

  /// 1. publier, dans l'ordre des rangs, ce qui n'est pas encore déposé (un dépôt rejoué est idempotent au relais).
  Future<void> publier() async {
    final uuid = base.meta('uuid');
    if (uuid == null) return;
    for (final l in base.select('SELECT n,id FROM sortie WHERE depose=0 ORDER BY n')) {
      final op = jsonDecode(base.select('SELECT json FROM ops WHERE id=?', [l['id']]).first['json'] as String) as Map<String, Object?>;
      final enveloppe = await env.chiffrer(op, id: '$uuid-pair-${l['n']}', appareil: uuid, dir: 'pair', n: l['n'] as int);
      final (st, _) = await _relais('POST', '/depot', {'enveloppe': enveloppe});
      if (st != 200) {
        if (st == 401) base.poserMeta('revoque', 1);
        return;
      }
      base.exec('UPDATE sortie SET depose=1 WHERE n=?', [l['n']]);
    }
  }

  /// 2. relever les journaux des autres : rangs contigus, authentification GCM, idempotence.
  Future<void> relever() async {
    final uuid = base.meta('uuid');
    if (uuid == null) return;
    final (st, liste) = await _relais('GET', '/pair/appareils');
    if (st != 200) return;
    for (final a in (liste['appareils'] as List).cast<Map>().where((x) => x['uuid'] != uuid)) {
      final appareil = '${a['uuid']}';
      for (;;) {
        final depuis = base.select('SELECT n FROM curseurs WHERE appareil=?', [appareil]).map((r) => r['n'] as int).firstOrNull ?? 0;
        final (s, r) = await _relais('GET', '/releve?dir=pair&appareil=${Uri.encodeQueryComponent(appareil)}&depuis_n=$depuis&limite=50');
        final lot = (r['env'] as List?)?.cast<Map>() ?? const [];
        if (s != 200 || lot.isEmpty) break;
        var attendu = depuis + 1;
        for (final e in lot) {
          if (e['n'] != attendu) {
            _anomalie('trou', {'appareil': appareil, 'attendu': attendu, 'recu': e['n']});
            return;
          }
          Map<String, Object?> charge;
          try {
            charge = await env.dechiffrer(e);
          } catch (_) {
            _anomalie('enveloppe_alteree', {'appareil': appareil, 'n': e['n']});
            return;
          }
          // le journal d'un pair porte des opérations ; celui de la MÈRE porte aussi ses décisions (`op`) et le seq qui fait foi (`foi`)
          final type = charge['type'];
          final op = type == 'op' ? (charge['op'] as Map).cast<String, Object?>() : (type == 'foi' ? null : charge);
          base.tx(() {
            if (type == 'foi') {
              for (final p in (charge['liste'] as List)) {
                base.exec('INSERT OR REPLACE INTO foi(id,seq) VALUES(?,?)', [(p as List)[0], p[1]]);
              }
            }
            if (op != null) base.exec('INSERT OR IGNORE INTO ops(id,appareil,json) VALUES(?,?,?)', [op['id'], op['appareil'], enJson(op)]);
            base.exec('INSERT INTO curseurs(appareil,n) VALUES(?,?) ON CONFLICT(appareil) DO UPDATE SET n=excluded.n', [appareil, e['n']]);
          });
          if (op != null) {
            horloge.recevoir((op['hlc'] as num).toInt());
            base.poserMeta('hlc', horloge.dernier);
          }
          attendu += 1;
        }
        if (r['fin'] == true) break;
      }
    }
  }

  /// 3. COPIE (PRD relais consultable) : l'état fusionné des collections choisies, une enveloppe par fiche NOUVELLE ou CHANGÉE, dans le sens `copie` de CE poste.
  /// Rang contigu, charge persistée avant dépôt (un SIGKILL ne perd rien et ne duplique rien : le dépôt rejoué est idempotent par id). L'archivage voyage
  /// comme un champ (RG-14) ; aucune suppression.
  /// Bornes d'UN tour : le poste calcule sur le fil de l'interface, un premier tour sur 200 000 opérations (migration, premier démarrage) ne doit pas la figer. Le travail se
  /// répartit sur plusieurs tours : indexation de [opsParTour] opérations au plus, puis recalcul de [fichesParTour] fiches au plus, dans cet ordre.
  static const int opsParTour = 20000, fichesParTour = 1500;

  /// Vrai tant qu'il reste des opérations à indexer ou des fiches à recalculer : le cycle repart aussitôt au lieu d'attendre le prochain battement.
  bool get copieEnRetard => base.select('SELECT 1 AS x FROM copie_a_faire LIMIT 1').isNotEmpty || base.select('SELECT 1 AS x FROM ops o LEFT JOIN copie_ops c ON c.id=o.id WHERE c.id IS NULL LIMIT 1').isNotEmpty;

  void preparerCopie() {
    if (cfg.collectionsCopie.isEmpty || base.meta('uuid') == null) return;
    // INCRÉMENTAL : seules les opérations NOUVELLES depuis le dernier tour (anti-jointure sur l'index `copie_ops`) désignent les fiches à recalculer ; chaque fiche
    // se refait depuis SES opérations seules (famille A : indépendantes). Le coût d'un tour suit ce qui a changé, plus l'historique entier. Une fiche n'est recalculée
    // qu'une fois TOUTES les opérations connues indexées (sinon on déposerait des versions intermédiaires). Chaque étape est une transaction : un SIGKILL ne laisse
    // jamais une opération « vue » sans que sa fiche soit en attente de recalcul, ni une fiche recalculée sans sa mise en file.
    final neuves = base.select('SELECT o.id AS id, o.json AS json FROM ops o LEFT JOIN copie_ops c ON c.id=o.id WHERE c.id IS NULL LIMIT $opsParTour');
    if (neuves.isNotEmpty) {
      base.tx(() {
        for (final r in neuves) {
          final j = (jsonDecode(r['json'] as String) as Map).cast<String, Object?>();
          final cle = '${j['collection']}/${j['fiche']}';
          base.exec('INSERT INTO copie_ops(id,cle) VALUES(?,?)', [r['id'], cle]);
          if (cfg.collectionsCopie.contains('${j['collection']}')) base.exec('INSERT OR IGNORE INTO copie_a_faire(cle) VALUES(?)', [cle]);
        }
      });
      if (neuves.length >= opsParTour) return; // il en reste : le tour suivant continue l'indexation
    }
    final aFaire = [for (final r in base.select('SELECT cle FROM copie_a_faire LIMIT $fichesParTour')) r['cle'] as String];
    if (aFaire.isEmpty) return;
    base.tx(() {
      for (final cle in aFaire) {
        base.exec('DELETE FROM copie_a_faire WHERE cle=?', [cle]);
        final i = cle.indexOf('/');
        final ops = [
          for (final r in base.select('SELECT o.json AS json, f.seq AS seq FROM ops o JOIN copie_ops c ON c.id=o.id LEFT JOIN foi f ON f.id=o.id WHERE c.cle=?', [cle]))
            OperationPair.depuisJson({
              ...(jsonDecode(r['json'] as String) as Map).cast<String, Object?>(),
              if (r['seq'] != null) 'seq': (r['seq'] as num).toInt(),
            })
        ];
        final charge = chargeCopieDeFiche(cle.substring(0, i), cle.substring(i + 1), ops, droits: droits);
        if (charge == null) continue;
        final texte = enJson(contenuCopie(charge));
        final deja = base.select('SELECT empreinte FROM copie_etat WHERE cle=?', [cle]).map((r) => r['empreinte'] as String).firstOrNull;
        if (deja == texte) continue;
        final n = (base.select('SELECT COALESCE(MAX(n),0) AS m FROM copie_sortie').first['m'] as int) + 1;
        base.exec('INSERT INTO copie_sortie(n,id,charge) VALUES(?,?,?)', [n, '${base.meta('uuid')}-copie-$n', enJson(charge)]);
        base.exec('INSERT INTO copie_etat(cle,empreinte) VALUES(?,?) ON CONFLICT(cle) DO UPDATE SET empreinte=excluded.empreinte', [cle, texte]);
      }
    });
  }

  Future<void> deposerCopie() async {
    final uuid = base.meta('uuid');
    if (uuid == null) return;
    for (final l in base.select('SELECT n,id,charge FROM copie_sortie WHERE depose=0 ORDER BY n LIMIT 500')) {
      final charge = (jsonDecode(l['charge'] as String) as Map).cast<String, Object?>();
      final enveloppe = await env.chiffrer(charge, id: l['id'] as String, appareil: uuid, dir: 'copie', n: l['n'] as int);
      final (st, _) = await _relais('POST', '/depot', {'enveloppe': enveloppe});
      if (st != 200) return;
      base.exec('UPDATE copie_sortie SET depose=1 WHERE n=?', [l['n']]);
    }
  }

  Future<void> cycle() async {
    if (_enCours) return;
    _enCours = true;
    try {
      await publier();
      await relever();
      preparerCopie();
      await deposerCopie();
      horsLigne = false;
    } catch (_) {
      horsLigne = true;
    } finally {
      cycles += 1;
      _enCours = false;
    }
  }

  /// Une opération émise par ce poste : droits vérifiés à l'ÉMISSION (et à la réception chez les autres), écriture locale + file de publication dans UNE transaction.
  OperationPair emettre(Map<String, Object?> c) {
    final uuid = base.meta('uuid');
    if (uuid == null) throw Err(409, 'non_appaire', 'poste non appairé');
    final op = OperationPair(
        id: uuid7(),
        appareil: uuid,
        hlc: horloge.emettre(),
        collection: '${c['collection']}',
        fiche: '${c['fiche']}',
        type: '${c['type']}',
        champs: ((c['champs'] ?? const <String, Object?>{}) as Map).cast<String, Object?>(),
        vu: c['vu'] == null ? null : (c['vu'] as Map).cast<String, Object?>(),
        role: c['role'] as String?);
    if (!droits(op)) throw Err(403, 'erreur', 'droit refusé : ${c['role']} ne peut pas ${c['type']} sur ${c['collection']}');
    base.tx(() {
      final n = (base.select('SELECT COALESCE(MAX(n),0) AS m FROM sortie').first['m'] as int) + 1;
      base.exec('INSERT INTO ops(id,appareil,json) VALUES(?,?,?)', [op.id, uuid, enJson(op.versJson())]);
      base.exec('INSERT INTO sortie(n,id) VALUES(?,?)', [n, op.id]);
    });
    base.poserMeta('hlc', horloge.dernier);
    return op;
  }

  /// Forme JSON de l'état, dans le MÊME ordre de clés que `pair-fileul.js` (deux postes, Node ou Dart, rendent le même texte).
  Map<String, Object?> fiches() {
    final e = etatPair(toutesOps(), droits: droits);
    return {
      'fiches': e.fiches,
      'stock': e.stock,
      'besoins': e.besoins,
      'conflits': e.conflits,
      'tranches': e.tranches,
      'refusees': [for (final r in e.refusees) {'id': r.id, 'appareil': r.appareil, 'code': r.code, 'motif': r.motif}],
      'provisoire': e.provisoire.toList()..sort(),
    };
  }

  /// L'état fusionné actuel (fiches, conflits, décisions) : fonction pure de toutes les opérations connues.
  EtatPair etatActuel() => etatPair(toutesOps(), droits: droits);

  /// Les conflits MARQUÉS, tels que la règle de fusion les voit aujourd'hui (le poste les recopie dans sa collection locale `conflitsPair`).
  List<Map<String, Object?>> conflits() => etatPair(toutesOps(), droits: droits).conflits;

  /// Boucle sans serveur de commande (l'application n'expose aucun port) : publier, relever, recommencer.
  Future<void> boucle() async {
    for (;;) {
      await cycle();
      await Future<void>.delayed(Duration(milliseconds: cfg.intervalleMs));
    }
  }

  Map<String, Object?> etat() => {
        'uuid': base.meta('uuid'),
        'nom': cfg.nom,
        'ops': base.select('SELECT COUNT(*) AS n FROM ops').first['n'],
        'en_attente': base.select('SELECT COUNT(*) AS n FROM sortie WHERE depose=0').first['n'],
        'copie_en_attente': base.select('SELECT COUNT(*) AS n FROM copie_sortie WHERE depose=0').first['n'],
        'copie_deposee': base.select('SELECT COUNT(*) AS n FROM copie_sortie WHERE depose=1').first['n'],
        'curseurs': {for (final r in base.select('SELECT appareil,n FROM curseurs')) r['appareil'] as String: r['n']},
        'anomalies': [for (final r in base.select('SELECT type,detail FROM anomalies')) {'type': r['type'], 'detail': r['detail']}],
        'derive': horloge.derive,
        'hors_ligne': horsLigne,
        'cycles': cycles,
        'revoque': base.meta('revoque') == '1',
      };

  Future<(int, Object?)> commande(String route, Map<String, Object?> b) async {
    switch (route) {
      case 'POST /appairer':
        final uuid = uuid7();
        final (st, j) = await _relais('POST', '/appairage', {'code': b['code'], 'uuid': uuid});
        if (st != 200) return (st, j);
        base.poserMeta('uuid', uuid);
        base.poserMeta('jeton', j['jeton']);
        return (200, {'uuid': uuid});
      case 'POST /emettre':
        final op = emettre(b);
        return (200, {'id': op.id, 'hlc': op.hlc});
      case 'GET /etat':
        return (200, etat());
      case 'GET /fiches':
        return (200, fiches());
    }
    return (404, {'code': 'route_inconnue'});
  }

  Future<void> demarrer() async {
    _serveur = await HttpServer.bind(InternetAddress.loopbackIPv4, cfg.port);
    Timer.periodic(Duration(milliseconds: cfg.intervalleMs), (_) => unawaited(cycle()));
    _serveur!.listen((req) async {
      final b = await corpsJson(req);
      int st;
      Object? out;
      try {
        (st, out) = await commande('${req.method} ${req.uri.path}', b);
      } on Err catch (e) {
        st = e.statut;
        out = {'code': e.code, 'motif': e.motif};
      } catch (e) {
        st = 500;
        out = {'code': 'erreur', 'motif': '$e'};
      }
      try {
        await repondre(req, st, out);
      } catch (_) {/* le client est parti */}
    });
    annoncerPret(_serveur!.port);
  }
}
