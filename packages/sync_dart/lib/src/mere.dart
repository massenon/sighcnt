/// LE POSTE MÈRE — service de synchronisation (spec §1-§10). Port Dart du banc `packages/sync/banc/mere.js` :
/// mêmes routes, mêmes refus nommés, mêmes familles de fusion. Le stockage est SQLite ; la cible est PostgreSQL
/// derrière la même interface (`Base`). Aucune règle n'est inventée ici : le banc est l'exécutable de référence.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'commun.dart';
import 'pont.dart';

/// Une famille par collection (PRD §8) : A fiche descriptive · B journal · C pièce émise · D agrégat à invariant ·
/// R référentiel (la mère seule écrit).
const familles = <String, String>{
  'patients': 'A', 'rendezvous': 'A',
  'constantes': 'B', 'notes': 'B',
  'factures': 'C',
  'stock': 'D',
  'tarifs': 'R', 'chambres': 'R',
};
const essentielles = {'tarifs', 'chambres'};
const _clinique = 'NASSIERA TOO';
const _deriveMaxMs = 2 * 60 * 1000;
const autorise = <String, Set<String>>{
  'reception': {'patients', 'rendezvous', 'constantes'},
  'soignant': {'patients', 'constantes', 'notes', 'rendezvous'},
};

class Appareil {
  Appareil(this.uuid, this.role, [this.profil]);
  final String uuid;
  final String role;
  final String? profil;
}

class Fiche {
  Fiche(this.data, this.fieldseq, this.archive);
  Map<String, Object?> data;
  Map<String, Object?> fieldseq;
  bool archive;
}

class ConfigMere {
  ConfigMere({
    required this.port,
    required this.dbChemin,
    this.admin = 'admin-banc',
    this.codeTtl = 15 * 60 * 1000,
    this.jetonTtl = 24 * 3600 * 1000,
    this.relais = '',
    this.secretRelais = 'secret-mere',
    this.restaurer = false,
    this.cleBase64 = '',
  });
  final int port;
  final String dbChemin;
  final String admin;
  final int codeTtl;
  final int jetonTtl;
  final String relais;
  final String secretRelais;
  final bool restaurer;
  final String cleBase64;
}

class Mere {
  Mere(this.cfg) : base = Base(cfg.dbChemin) {
    base.exec('''
      CREATE TABLE IF NOT EXISTS operations (seq INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT UNIQUE, appareil TEXT, epoch INTEGER,
        hlc INTEGER, collection TEXT, fiche TEXT, type TEXT, champs TEXT, famille TEXT);
      CREATE TABLE IF NOT EXISTS resultats (id TEXT PRIMARY KEY, json TEXT);
      CREATE TABLE IF NOT EXISTS fiches (collection TEXT, id TEXT, data TEXT, fieldseq TEXT, archive INTEGER, PRIMARY KEY (collection, id));
      CREATE TABLE IF NOT EXISTS appareils (uuid TEXT PRIMARY KEY, etiquette TEXT, role TEXT, etat TEXT, jeton_hash TEXT, jeton_expire INTEGER,
        renouv_hash TEXT, dernier_contact INTEGER, dernier_seq INTEGER DEFAULT 0, derive_ms INTEGER DEFAULT 0, profil TEXT);
      CREATE TABLE IF NOT EXISTS codes (code TEXT PRIMARY KEY, etiquette TEXT, role TEXT, expire INTEGER, utilise INTEGER DEFAULT 0);
      CREATE TABLE IF NOT EXISTS conflits (id INTEGER PRIMARY KEY AUTOINCREMENT, collection TEXT, fiche TEXT, champ TEXT, a TEXT, b TEXT,
        appareil TEXT, etat TEXT DEFAULT 'ouvert', decision TEXT);
      CREATE TABLE IF NOT EXISTS plages (appareil TEXT, nom TEXT, debut INTEGER, fin INTEGER);
      CREATE TABLE IF NOT EXISTS baux (appareil TEXT, article TEXT, reste INTEGER, PRIMARY KEY (appareil, article));
      CREATE TABLE IF NOT EXISTS acks (marque TEXT, appareil TEXT, PRIMARY KEY (marque, appareil));
      CREATE TABLE IF NOT EXISTS portee (appareil TEXT, collection TEXT, fiche TEXT, PRIMARY KEY (appareil, collection, fiche));
      CREATE TABLE IF NOT EXISTS sortie (appareil TEXT, n INTEGER, charge TEXT, depose INTEGER DEFAULT 0, PRIMARY KEY (appareil, n));
    ''');
    if (base.meta('epoch') == null) base.poserMeta('epoch', 1);
    if (base.meta('next_patient') == null) base.poserMeta('next_patient', 1000);
    if (base.meta('reinit_ouverte') == null) base.poserMeta('reinit_ouverte', 0);
  }

  final ConfigMere cfg;
  final Base base;
  late final Pont pont = Pont(this);
  HttpServer? _serveur;

  // --- fiches ------------------------------------------------------------------------------
  Fiche? lire(String c, String id) {
    final r = base.select('SELECT * FROM fiches WHERE collection=? AND id=?', [c, id]);
    if (r.isEmpty) return null;
    final x = r.first;
    return Fiche((jsonDecode(x['data'] as String) as Map).cast<String, Object?>(),
        (jsonDecode(x['fieldseq'] as String) as Map).cast<String, Object?>(), (x['archive'] as int) != 0);
  }

  void ecrire(String c, String id, Fiche f) => base.exec('''
    INSERT INTO fiches(collection,id,data,fieldseq,archive) VALUES(?,?,?,?,?)
    ON CONFLICT(collection,id) DO UPDATE SET data=excluded.data, fieldseq=excluded.fieldseq, archive=excluded.archive''',
      [c, id, enJson(f.data), enJson(f.fieldseq), f.archive ? 1 : 0]);

  int journaliser(Map op, Map<String, Object?> champs, String appareil) {
    base.exec(
        'INSERT INTO operations(id,appareil,epoch,hlc,collection,fiche,type,champs,famille) VALUES(?,?,?,?,?,?,?,?,?)',
        [op['id'], appareil, base.metaInt('epoch'), op['hlc'] ?? 0, op['collection'], op['fiche'], op['type'], enJson(champs), familles[op['collection']]]);
    return base.dernierId;
  }

  num reserve(String article) =>
      base.select('SELECT COALESCE(SUM(reste),0) AS s FROM baux WHERE article=?', [article]).first['s'] as num;

  // --- le cœur : une opération → un résultat NOMMÉ -----------------------------------------------
  Map<String, Object?> traiter(Map op, Appareil app) {
    final id = op['id'];
    final collection = op['collection'] as String;
    final fam = familles[collection];
    Map<String, Object?> refus(String code, String motif, String geste) =>
        {'id': id, 'statut': 'refusee', 'code': code, 'motif': motif, 'geste': geste};
    if (fam == null) return refus('collection_inconnue', 'Collection inconnue : $collection', 'Mettre le poste à jour');
    final type = op['type'];
    if (type == 'supprimer') return refus('suppression_interdite', 'Aucune suppression physique (RG-14).', 'Archiver la fiche');
    if (fam == 'R' && app.role != 'mere') {
      return refus('droit_refuse', 'Un référentiel ne se modifie qu’à la console de la mère.', 'Demander la modification à l’administrateur');
    }
    final ficheId = op['fiche'] as String;
    final champsOp = ((op['champs'] ?? {}) as Map).cast<String, Object?>();
    final f = lire(collection, ficheId);

    if (fam == 'D') {
      if (type == 'creer') {
        if (app.role != 'mere') return refus('droit_refuse', 'Le stock initial s’ouvre à la console de la mère.', 'Contacter l’administrateur');
        final seq = journaliser(op, champsOp, app.uuid);
        ecrire(collection, ficheId, Fiche({'qte': nb(champsOp['qte'])}, {'qte': seq}, false));
        return {'id': id, 'statut': 'acceptee', 'seq': seq};
      }
      if (type == 'sortie') {
        if (f == null) return refus('fiche_inconnue', 'Article inconnu : $ficheId', 'Vérifier la référence');
        final q = nb(champsOp['qte']);
        final bail = base.select('SELECT reste FROM baux WHERE appareil=? AND article=?', [app.uuid, ficheId]);
        var surBail = false;
        if (op['bail'] == true && bail.isNotEmpty && (bail.first['reste'] as num) >= q) {
          base.exec('UPDATE baux SET reste=reste-? WHERE appareil=? AND article=?', [q, app.uuid, ficheId]);
          surBail = true;
        } else {
          final dispo = (f.data['qte'] as num) - reserve(ficheId);
          if (dispo < q) {
            return refus('invariant_viole', 'Stock insuffisant pour $ficheId : disponible $dispo, demandé $q (RG-03).',
                'Réduire la quantité ou attendre un réapprovisionnement');
          }
        }
        f.data['qte'] = (f.data['qte'] as num) - q;
        final seq = journaliser(op, {'qte': q}, app.uuid);
        f.fieldseq['qte'] = seq;
        ecrire(collection, ficheId, f);
        return {'id': id, 'statut': 'acceptee', 'seq': seq, 'surBail': surBail};
      }
      return refus('type_invalide', 'Opération non prévue sur le stock : $type', 'Utiliser une sortie');
    }

    if (fam == 'B') {
      if (type != 'creer') return refus('journal_immuable', 'Un journal ne se modifie pas : on ajoute une ligne.', 'Ajouter une nouvelle ligne');
      if (f != null) return refus('fiche_existe', 'Cette ligne existe déjà.', 'Aucun');
      final seq = journaliser(op, champsOp, app.uuid);
      ecrire(collection, ficheId, Fiche({...champsOp}, {for (final k in champsOp.keys) k: seq}, false));
      return {'id': id, 'statut': 'acceptee', 'seq': seq};
    }

    // A, C et R : fusion par champ
    if (type == 'creer') {
      if (f != null) return refus('fiche_existe', 'Cette fiche existe déjà.', 'Aucun');
      final champs = {...champsOp};
      String? numero;
      if (collection == 'patients') {
        final code = '${champs['code'] ?? ''}';
        final m = RegExp(r'^CNT/(\d+)/26$').firstMatch(code);
        if (code.isEmpty || code.startsWith('PROV-')) {
          final n = base.metaInt('next_patient');
          base.poserMeta('next_patient', n + 1);
          champs['code'] = 'CNT/$n/26';
          numero = '${champs['code']}';
        } else if (m == null) {
          return refus('numero_invalide', 'Code patient mal formé : $code', 'Laisser le poste attribuer le code');
        } else {
          final n = int.parse(m.group(1)!);
          final ok = base.select('SELECT 1 FROM plages WHERE appareil=? AND nom=? AND debut<=? AND fin>=?', [app.uuid, 'patients', n, n]);
          if (ok.isEmpty) return refus('numero_hors_plage', 'Le code $code n’appartient pas à la plage de ce poste.', 'Demander une nouvelle plage');
        }
        final dup = base.select("SELECT 1 FROM fiches WHERE collection='patients' AND json_extract(data,'\$.code')=?", ['${champs['code']}']);
        if (dup.isNotEmpty) return refus('doublon_numero', 'Code patient déjà attribué : ${champs['code']}', 'Demander une nouvelle plage');
      }
      String? doublon;
      if (collection == 'patients' && champs['nom'] != null && '${champs['nom']}'.isNotEmpty && champs['naissance'] != null && '${champs['naissance']}'.isNotEmpty) {
        final nomK = '${champs['nom']}'.trim().toLowerCase();
        for (final r in base.select("SELECT id,data FROM fiches WHERE collection='patients'")) {
          final d = (jsonDecode(r['data'] as String) as Map);
          if ('${d['nom'] ?? ''}'.trim().toLowerCase() == nomK && '${d['naissance'] ?? ''}' == '${champs['naissance']}') {
            doublon = r['id'] as String;
            break;
          }
        }
      }
      final seq = journaliser(op, champs, app.uuid);
      ecrire(collection, ficheId, Fiche(champs, {for (final k in champs.keys) k: seq}, false));
      if (doublon != null) {
        base.exec('INSERT INTO conflits(collection,fiche,champ,a,b,appareil) VALUES(?,?,?,?,?,?)',
            [collection, ficheId, 'doublon_possible', enJson(doublon), enJson(ficheId), app.uuid]);
      }
      return {'id': id, 'statut': 'acceptee', 'seq': seq, 'numero': ?numero, 'doublon_possible': ?doublon};
    }
    if (f == null) return refus('fiche_inconnue', 'Fiche inconnue : $ficheId', 'Rafraîchir le poste');
    if (type == 'archiver' || type == 'restaurer') {
      f.archive = type == 'archiver';
      final seq = journaliser(op, {}, app.uuid);
      ecrire(collection, ficheId, f);
      return {'id': id, 'statut': 'acceptee', 'seq': seq};
    }
    if (type == 'modifier') {
      if (f.archive) return refus('fiche_archivee', 'La fiche est archivée : restaurez-la d’abord (RG-14).', 'Restaurer la fiche');
      if (fam == 'C' && (f.data['emise'] == true)) {
        return refus('piece_emise_immuable', 'Une pièce émise ne se réécrit jamais : émettre un avoir.', 'Établir une pièce de correction');
      }
      final appliques = <String, Object?>{};
      final conflits = <Map<String, Object?>>[];
      final vu = ((op['vu'] ?? {}) as Map);
      for (final e in champsOp.entries) {
        final dejaVu = nb(vu[e.key]);
        final courant = (f.fieldseq[e.key] == null) ? 0 : nb(f.fieldseq[e.key]);
        if (courant > dejaVu && enJson(f.data[e.key]) != enJson(e.value)) {
          base.exec('INSERT INTO conflits(collection,fiche,champ,a,b,appareil) VALUES(?,?,?,?,?,?)',
              [collection, ficheId, e.key, enJson(f.data[e.key]), enJson(e.value), app.uuid]);
          conflits.add({'conflit': base.dernierId, 'champ': e.key});
        } else {
          appliques[e.key] = e.value;
        }
      }
      int? seq;
      if (appliques.isNotEmpty) {
        seq = journaliser(op, appliques, app.uuid);
        for (final k in appliques.keys) {
          f.data[k] = appliques[k];
          f.fieldseq[k] = seq;
        }
        ecrire(collection, ficheId, f);
      }
      return conflits.isNotEmpty
          ? {'id': id, 'statut': 'fusionnee', 'seq': seq, 'conflits': conflits}
          : {'id': id, 'statut': 'acceptee', 'seq': seq};
    }
    return refus('type_invalide', 'Type d’opération inconnu : $type', 'Mettre le poste à jour');
  }

  // --- authentification ---------------------------------------------------------------------------
  Appareil auth(HttpRequest req) {
    final m = RegExp(r'^Bearer ([^.]+)\.(.+)$').firstMatch(req.headers.value('authorization') ?? '');
    if (m == null) throw Err(401, 'jeton_invalide', 'Jeton absent.');
    final r = base.select('SELECT * FROM appareils WHERE uuid=?', [m.group(1)]);
    if (r.isEmpty) throw Err(401, 'jeton_invalide', 'Appareil inconnu.');
    final a = r.first;
    if (a['etat'] == 'revoque') throw Err(401, 'appareil_revoque', 'Cet appareil a été révoqué.');
    if (sha256hex(m.group(2)!) != a['jeton_hash']) throw Err(401, 'jeton_invalide', 'Jeton invalide.');
    if (maintenantMs() > (a['jeton_expire'] as int)) throw Err(401, 'jeton_expire', 'Jeton expiré.');
    base.exec('UPDATE appareils SET dernier_contact=? WHERE uuid=?', [maintenantMs(), a['uuid']]);
    return Appareil(a['uuid'] as String, a['role'] as String, a['profil'] as String?);
  }

  void adminOk(HttpRequest req) {
    if (req.headers.value('x-admin') != cfg.admin) throw Err(403, 'admin_requis', 'Accès administrateur requis.');
  }

  Map<String, Object?> emettreJetons(String uuid) {
    final secret = hexAlea(24);
    final renouv = hexAlea(24);
    base.exec('UPDATE appareils SET jeton_hash=?, jeton_expire=?, renouv_hash=? WHERE uuid=?',
        [sha256hex(secret), maintenantMs() + cfg.jetonTtl, sha256hex(renouv), uuid]);
    return {'jeton': '$uuid.$secret', 'renouvellement': '$uuid.$renouv'};
  }

  String codeAppairage() {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(8, (_) => alphabet[r.nextInt(alphabet.length)]).join();
  }

  /// L'envoi d'un lot, commun aux postes (P1) et aux mobiles (P2/P3).
  Map<String, Object?> pousser(Appareil app, Map b) {
    final epoch = base.metaInt('epoch');
    if (b['epoch'] != epoch) throw Err(409, 'epoch_inconnue', 'Époque inconnue de la mère.', {'epoch_mere': epoch});
    final derive = (maintenantMs() - (b['horloge'] is num ? (b['horloge'] as num).toInt() : maintenantMs())).abs();
    base.exec('UPDATE appareils SET derive_ms=? WHERE uuid=?', [derive, app.uuid]);
    final resultats = base.tx(() => ((b['ops'] ?? []) as List).map((o) {
          final op = (o as Map);
          final deja = base.select('SELECT json FROM resultats WHERE id=?', [op['id']]);
          if (deja.isNotEmpty) return {...(jsonDecode(deja.first['json'] as String) as Map).cast<String, Object?>(), 'rejeu': true};
          Map<String, Object?> r;
          if (app.role == 'mobile' && !(autorise[app.profil] ?? <String>{}).contains(op['collection'])) {
            r = {
              'id': op['id'], 'statut': 'refusee', 'code': 'droit_refuse',
              'motif': 'Le profil « ${app.profil} » ne couvre pas la collection ${op['collection']}.', 'geste': 'Utiliser un poste',
            };
          } else {
            r = traiter(op, app);
          }
          if (app.role == 'mobile' && r['statut'] == 'acceptee' && op['type'] == 'creer') {
            base.exec('INSERT OR IGNORE INTO portee(appareil,collection,fiche) VALUES(?,?,?)', [app.uuid, op['collection'], op['fiche']]);
          }
          base.exec('INSERT INTO resultats(id,json) VALUES(?,?)', [op['id'], enJson(r)]);
          return r;
        }).toList());
    return {'resultats': resultats, 'seq_max': seqMax()};
  }

  int seqMax() => base.select('SELECT COALESCE(MAX(seq),0) AS s FROM operations').first['s'] as int;

  // --- routes ---------------------------------------------------------------------------------------
  Future<Object?> route(String cle, HttpRequest req, Map<String, Object?> b, Map<String, String> q) async {
    switch (cle) {
      case 'POST /admin/code':
        adminOk(req);
        final code = codeAppairage();
        base.exec('INSERT INTO codes(code,etiquette,role,expire) VALUES(?,?,?,?)',
            [code, b['etiquette'] ?? '', b['role'] ?? 'fileul', maintenantMs() + cfg.codeTtl]);
        return {'code': code};
      case 'POST /appairage':
        final r = base.select('SELECT * FROM codes WHERE code=?', ['${b['code'] ?? ''}']);
        if (r.isEmpty) throw Err(403, 'code_invalide', 'Code d’appairage inconnu.');
        final c = r.first;
        if ((c['utilise'] as int) != 0) throw Err(403, 'code_utilise', 'Ce code a déjà servi (usage unique).');
        if (maintenantMs() > (c['expire'] as int)) throw Err(403, 'code_expire', 'Ce code a expiré.');
        base.exec('UPDATE codes SET utilise=1 WHERE code=?', [c['code']]);
        base.exec('INSERT INTO appareils(uuid,etiquette,role,etat) VALUES(?,?,?,?)', [b['uuid'], c['etiquette'], c['role'], 'actif']);
        return {'epoch': base.metaInt('epoch'), ...emettreJetons(b['uuid'] as String)};
      case 'POST /renouveler':
        final m = RegExp(r'^([^.]+)\.(.+)$').firstMatch('${b['renouvellement'] ?? ''}');
        final rr = m == null ? null : base.select('SELECT * FROM appareils WHERE uuid=?', [m.group(1)]);
        if (rr == null || rr.isEmpty || rr.first['etat'] == 'revoque') throw Err(401, 'appareil_revoque', 'Appareil révoqué.');
        final a = rr.first;
        if (sha256hex(m!.group(2)!) != a['renouv_hash']) {
          base.exec("UPDATE appareils SET etat='revoque' WHERE uuid=?", [a['uuid']]);
          throw Err(401, 'appareil_revoque', 'Renouvellement rejoué : appareil révoqué par précaution.');
        }
        return emettreJetons(a['uuid'] as String);
      case 'POST /sync/push':
        return pousser(auth(req), b);
      case 'GET /sync/pull':
        auth(req);
        final epoch = base.metaInt('epoch');
        if ((int.tryParse(q['epoch'] ?? '') ?? -1) != epoch) throw Err(409, 'epoch_inconnue', 'Époque inconnue de la mère.', {'epoch_mere': epoch});
        final depuis = int.tryParse(q['depuis'] ?? '') ?? 0;
        final limite = min(int.tryParse(q['limite'] ?? '') ?? 500, 500);
        final ops = base
            .select('SELECT seq,id,appareil,collection,fiche,type,champs FROM operations WHERE seq>? ORDER BY seq LIMIT ?', [depuis, limite])
            .map((o) => {...o, 'champs': jsonDecode(o['champs'] as String)})
            .toList();
        final app = auth(req);
        base.exec('UPDATE appareils SET dernier_seq=MAX(dernier_seq,?) WHERE uuid=?', [depuis, app.uuid]);
        final marque = base.meta('resync');
        return {'ops': ops, 'fin': ops.length < limite, 'epoch': epoch, 'resync': (marque == null || marque.isEmpty) ? null : marque};
      case 'POST /sync/plage':
        final app2 = auth(req);
        final taille = max(1, min(nb(b['taille']).toInt() == 0 ? 50 : nb(b['taille']).toInt(), 1000));
        return base.tx(() {
          final debut = base.metaInt('next_patient');
          final fin = debut + taille - 1;
          base.poserMeta('next_patient', fin + 1);
          base.exec('INSERT INTO plages(appareil,nom,debut,fin) VALUES(?,?,?,?)', [app2.uuid, b['nom'] ?? 'patients', debut, fin]);
          return {'debut': debut, 'fin': fin};
        });
      case 'POST /sync/bail':
        final app3 = auth(req);
        return base.tx(() {
          final f = lire('stock', '${b['article']}');
          if (f == null) throw Err(422, 'fiche_inconnue', 'Article inconnu : ${b['article']}');
          final dispo = (f.data['qte'] as num) - reserve('${b['article']}');
          final accorde = max(0, min(nb(b['qte']), dispo));
          base.exec('INSERT INTO baux(appareil,article,reste) VALUES(?,?,?) ON CONFLICT(appareil,article) DO UPDATE SET reste=reste+excluded.reste',
              [app3.uuid, b['article'], accorde]);
          final reste = base.select('SELECT reste FROM baux WHERE appareil=? AND article=?', [app3.uuid, b['article']]).first['reste'];
          return {'accorde': accorde, 'reste': reste};
        });
      case 'POST /sync/ack-resync':
        final app4 = auth(req);
        base.exec('INSERT OR IGNORE INTO acks(marque,appareil) VALUES(?,?)', ['${b['marque']}', app4.uuid]);
        return {'ok': true};
      case 'POST /admin/revoquer':
        adminOk(req);
        base.exec("UPDATE appareils SET etat='revoque' WHERE uuid=?", [b['uuid']]);
        pont.revoquerAuRelais('${b['uuid']}');
        return {'ok': true};
      case 'POST /admin/code-mobile':
        adminOk(req);
        final code = codeAppairage();
        base.exec('INSERT INTO codes(code,etiquette,role,expire) VALUES(?,?,?,?)', [code, b['etiquette'] ?? '', 'mobile', maintenantMs() + cfg.codeTtl]);
        await pont.declarerCode(sha256hex(code));
        return {'code': code, 'cle': pont.cleBase64};
      case 'POST /admin/lot':
        adminOk(req);
        return pont.lot(b);
      case 'POST /admin/debloquer':
        adminOk(req);
        base.poserMeta('bloque:${b['uuid']}', '');
        return {'ok': true};
      case 'POST /admin/resync':
        adminOk(req);
        final m2 = '${maintenantMs()}';
        base.poserMeta('resync', m2);
        return {'marque': m2};
      case 'GET /admin/etat':
        adminOk(req);
        final marque = base.meta('resync');
        final marqueOk = (marque == null || marque.isEmpty) ? null : marque;
        return {
          'epoch': base.metaInt('epoch'),
          'seq_max': seqMax(),
          'appareils': base.select('SELECT uuid,etiquette,role,etat,dernier_contact,dernier_seq,derive_ms FROM appareils').map((x) => {...x}).toList(),
          'derives': base.select('SELECT uuid FROM appareils WHERE derive_ms>?', [_deriveMaxMs]).map((x) => x['uuid']).toList(),
          'conflits_ouverts': base.select("SELECT COUNT(*) AS n FROM conflits WHERE etat='ouvert'").first['n'],
          'resync': {
            'marque': marqueOk,
            'acks': marqueOk == null ? [] : base.select('SELECT appareil FROM acks WHERE marque=?', [marqueOk]).map((x) => x['appareil']).toList(),
          },
          'reinit_ouverte': base.meta('reinit_ouverte') == '1',
          'nb_operations': base.select('SELECT COUNT(*) AS n FROM operations').first['n'],
          'rep_seq': base.metaInt('rep_seq'),
          'rep_n': base.metaInt('rep_n'),
          'alertes': pont.alertes,
          'restauration': base.meta('restauration'),
          'bloques': base.select("SELECT k FROM meta WHERE k LIKE 'bloque:%' AND v<>''").map((x) => (x['k'] as String).substring(7)).toList(),
        };
      case 'GET /admin/fiche':
        adminOk(req);
        final f = lire(q['collection'] ?? '', q['id'] ?? '');
        return f == null ? {'absente': true} : {'data': f.data, 'fieldseq': f.fieldseq, 'archive': f.archive};
      case 'GET /admin/compte':
        adminOk(req);
        return {'n': base.select('SELECT COUNT(*) AS n FROM fiches WHERE collection=? AND archive=0', [q['collection']]).first['n']};
      case 'GET /admin/empreinte':
        adminOk(req);
        final rows = base.select('SELECT collection,id,data,archive FROM fiches ORDER BY collection,id').map((x) => {...x}).toList();
        return {'empreinte': sha256hex(enJson(rows)), 'n': rows.length};
      case 'GET /admin/conflits':
        adminOk(req);
        return base.select('SELECT * FROM conflits').map((x) => {...x}).toList();
      case 'POST /admin/trancher':
        adminOk(req);
        return base.tx(() {
          final r = base.select('SELECT * FROM conflits WHERE id=?', [b['id']]);
          if (r.isEmpty || r.first['etat'] != 'ouvert') throw Err(422, 'conflit_inconnu', 'Conflit inexistant ou déjà tranché.');
          final c = r.first;
          if (b['decision'] == 'b') {
            final f = lire(c['collection'] as String, c['fiche'] as String)!;
            final val = jsonDecode(c['b'] as String);
            final op = {'id': 'tranche-${c['id']}-${uuid7()}', 'collection': c['collection'], 'fiche': c['fiche'], 'type': 'modifier', 'champs': {c['champ']: val}, 'hlc': maintenantMs()};
            final seq = journaliser(op, {c['champ'] as String: val}, 'mere');
            f.data[c['champ'] as String] = val;
            f.fieldseq[c['champ'] as String] = seq;
            ecrire(c['collection'] as String, c['fiche'] as String, f);
          }
          base.exec("UPDATE conflits SET etat='tranche', decision=? WHERE id=?", [b['decision'], c['id']]);
          return {'ok': true};
        });
      case 'POST /admin/referentiel':
        adminOk(req);
        return base.tx(() {
          final existe = lire('${b['collection']}', '${b['fiche']}');
          final champs = ((b['champs'] ?? {}) as Map).cast<String, Object?>();
          final op = <String, Object?>{
            'id': 'ref-${uuid7()}', 'collection': b['collection'], 'fiche': b['fiche'], 'type': existe != null ? 'modifier' : 'creer',
            'champs': champs, 'hlc': maintenantMs(), 'vu': <String, Object?>{},
          };
          if (existe != null) op['vu'] = {for (final k in champs.keys) k: nb(existe.fieldseq[k])};
          return traiter(op, Appareil('mere', 'mere'));
        });
      case 'POST /admin/stock':
        adminOk(req);
        return base.tx(() => traiter({
              'id': 'stk-${uuid7()}', 'collection': 'stock', 'fiche': b['article'], 'type': 'creer', 'champs': {'qte': b['qte']}, 'hlc': maintenantMs(),
            }, Appareil('mere', 'mere')));
      case 'POST /admin/reinit-fenetre':
        adminOk(req);
        base.poserMeta('reinit_ouverte', b['ouvrir'] == true ? 1 : 0);
        return {'ouverte': b['ouvrir'] == true};
      case 'POST /admin/reinitialiser':
        adminOk(req);
        if (base.meta('reinit_ouverte') != '1') throw Err(403, 'reinit_fermee', 'La réinitialisation est fermée : l’administrateur doit ouvrir la fenêtre.');
        if (b['confirmation'] != _clinique) throw Err(422, 'confirmation_invalide', 'Saisir le nom de la clinique pour confirmer.');
        if (b['second'] == null || b['second'] == '' || b['second'] == false) throw Err(422, 'second_profil_requis', 'Un second profil (DAF ou Direction) doit confirmer.');
        final sauvegarde = '${cfg.dbChemin == ':memory:' ? 'mere' : cfg.dbChemin}.avant-reinit-${maintenantMs()}.bak';
        base.exec("VACUUM INTO '${sauvegarde.replaceAll("'", '')}'");
        base.tx(() {
          final liste = essentielles.map((c) => "'$c'").join(',');
          base.exec('DELETE FROM operations WHERE collection NOT IN ($liste)');
          base.exec('DELETE FROM fiches WHERE collection NOT IN ($liste)');
          for (final t in ['resultats', 'conflits', 'plages', 'baux', 'acks', 'portee']) {
            base.exec('DELETE FROM $t');
          }
          base.poserMeta('epoch', base.metaInt('epoch') + 1);
          base.poserMeta('reinit_ouverte', 0);
          base.poserMeta('next_patient', 1000);
          base.poserMeta('marqueur_epoch', 1);
        });
        return {'sauvegarde': sauvegarde, 'epoch': base.metaInt('epoch')};
    }
    throw Err(404, 'route_inconnue', 'Route inconnue.');
  }

  Future<void> demarrer() async {
    _serveur = await HttpServer.bind(InternetAddress.loopbackIPv4, cfg.port);
    pont.demarrer();
    _serveur!.listen((req) async {
      final b = await corpsJson(req);
      final q = req.uri.queryParameters;
      int statut = 200;
      Object? out;
      try {
        out = await route('${req.method} ${req.uri.path}', req, b, q);
      } on Err catch (e) {
        statut = e.statut;
        out = e.corps;
      } catch (e, s) {
        statut = 500;
        out = {'code': 'erreur_interne', 'motif': '$e', 'pile': '$s'.split('\n').take(3).join(' | ')};
      }
      try {
        await repondre(req, statut, out);
      } catch (_) {/* le client est parti */}
    });
    annoncerPret(_serveur!.port);
  }

  Future<void> arreter() async => _serveur?.close(force: true);
}
