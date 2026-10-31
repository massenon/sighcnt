/// LE POSTE MÈRE — service de synchronisation (spec §1-§10). Port Dart du banc `packages/sync/banc/mere.js` :
/// mêmes routes, mêmes refus nommés, mêmes familles de fusion. Le dépôt est SQLite ou PostgreSQL (`Depot`) : la cible
/// est « le PostgreSQL du serveur local » (`--db=postgres://…`). Aucune règle n'est inventée ici : le banc est l'exécutable
/// de référence. Toute opération sur le dépôt passe par le `Verrou` : une seule connexion, une seule opération à la fois.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'commun.dart';
import 'depot.dart';
import 'pont.dart';
import 'supervision.dart';

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

const _ddl = '''
  CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT);
  CREATE TABLE IF NOT EXISTS operations (seq {AUTO}, id TEXT UNIQUE, appareil TEXT, epoch BIGINT, hlc BIGINT, collection TEXT, fiche TEXT, type TEXT, champs TEXT, famille TEXT);
  CREATE TABLE IF NOT EXISTS resultats (id TEXT PRIMARY KEY, corps TEXT);
  CREATE TABLE IF NOT EXISTS fiches (collection TEXT, id TEXT, data TEXT, fieldseq TEXT, archive INTEGER, PRIMARY KEY (collection, id));
  CREATE TABLE IF NOT EXISTS appareils (uuid TEXT PRIMARY KEY, etiquette TEXT, role TEXT, etat TEXT, jeton_hash TEXT, jeton_expire BIGINT,
    renouv_hash TEXT, dernier_contact BIGINT, dernier_seq BIGINT DEFAULT 0, derive_ms BIGINT DEFAULT 0, profil TEXT);
  CREATE TABLE IF NOT EXISTS codes (code TEXT PRIMARY KEY, etiquette TEXT, role TEXT, expire BIGINT, utilise INTEGER DEFAULT 0);
  CREATE TABLE IF NOT EXISTS conflits (id {AUTO}, collection TEXT, fiche TEXT, champ TEXT, a TEXT, b TEXT, appareil TEXT, etat TEXT DEFAULT 'ouvert', decision TEXT);
  CREATE TABLE IF NOT EXISTS plages (appareil TEXT, nom TEXT, debut BIGINT, fin BIGINT);
  CREATE TABLE IF NOT EXISTS baux (appareil TEXT, article TEXT, reste BIGINT, PRIMARY KEY (appareil, article));
  CREATE TABLE IF NOT EXISTS acks (marque TEXT, appareil TEXT, PRIMARY KEY (marque, appareil));
  CREATE TABLE IF NOT EXISTS portee (appareil TEXT, collection TEXT, fiche TEXT, PRIMARY KEY (appareil, collection, fiche));
  CREATE TABLE IF NOT EXISTS sortie (appareil TEXT, n BIGINT, charge TEXT, depose INTEGER DEFAULT 0, PRIMARY KEY (appareil, n));
  CREATE TABLE IF NOT EXISTS evenements (id {AUTO}, quand BIGINT, niveau TEXT, source TEXT, message TEXT)
''';

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
    this.dossierSauvegardes = 'sauvegardes',
    this.heureSauvegarde = 2,
    this.conservation = 7,
  });
  final int port;

  /// Chemin SQLite, `:memory:` ou `postgres://utilisateur:mot_de_passe@hôte:port/base`.
  final String dbChemin;
  final String admin;
  final int codeTtl;
  final int jetonTtl;
  final String relais;
  final String secretRelais;
  final bool restaurer;
  final String cleBase64;

  /// Sauvegarde quotidienne, CHIFFRÉE avec la clé de clinique : dossier, heure locale de déclenchement, nombre conservé.
  final String dossierSauvegardes;
  final int heureSauvegarde;
  final int conservation;
}

class Mere {
  Mere._(this.cfg, this.base);

  final ConfigMere cfg;
  final Depot base;
  final Verrou verrou = Verrou();
  late final Pont pont = Pont(this);
  HttpServer? _serveur;
  Timer? _sauvegardeur;

  static Future<Mere> creer(ConfigMere cfg) async {
    final base = await Depot.ouvrir(cfg.dbChemin);
    await base.initialiser(_ddl);
    if (await base.meta('epoch') == null) await base.poserMeta('epoch', 1);
    if (await base.meta('next_patient') == null) await base.poserMeta('next_patient', 1000);
    if (await base.meta('reinit_ouverte') == null) await base.poserMeta('reinit_ouverte', 0);
    final m = Mere._(cfg, base);
    await m.pont.initialiser();
    return m;
  }

  // --- fiches ------------------------------------------------------------------------------
  Future<Fiche?> lire(String c, String id) async {
    final r = await base.select('SELECT * FROM fiches WHERE collection=? AND id=?', [c, id]);
    if (r.isEmpty) return null;
    final x = r.first;
    return Fiche((jsonDecode(x['data'] as String) as Map).cast<String, Object?>(),
        (jsonDecode(x['fieldseq'] as String) as Map).cast<String, Object?>(), (x['archive'] as int) != 0);
  }

  Future<void> ecrire(String c, String id, Fiche f) => base.exec('''
    INSERT INTO fiches(collection,id,data,fieldseq,archive) VALUES(?,?,?,?,?)
    ON CONFLICT(collection,id) DO UPDATE SET data=excluded.data, fieldseq=excluded.fieldseq, archive=excluded.archive''',
      [c, id, enJson(f.data), enJson(f.fieldseq), f.archive ? 1 : 0]);

  Future<int> journaliser(Map op, Map<String, Object?> champs, String appareil) async {
    final r = await base.select(
        'INSERT INTO operations(id,appareil,epoch,hlc,collection,fiche,type,champs,famille) VALUES(?,?,?,?,?,?,?,?,?) RETURNING seq',
        [op['id'], appareil, await base.metaInt('epoch'), op['hlc'] ?? 0, op['collection'], op['fiche'], op['type'], enJson(champs), familles[op['collection']]]);
    return r.first['seq'] as int;
  }

  /// Journal technique de la mère (RG-12) : erreurs, alertes, gestes d'administration. Jamais de donnée de santé.
  Future<void> evenement(String niveau, String source, String message) =>
      base.exec('INSERT INTO evenements(quand,niveau,source,message) VALUES(?,?,?,?)', [maintenantMs(), niveau, source, message]);

  /// À appeler HORS verrou (alerte venue d'une minuterie, erreur interne d'une requête).
  void evenementAsync(String niveau, String source, String message) {
    unawaited(verrou.executer(() => evenement(niveau, source, message)).catchError((Object _) {}));
  }

  Future<num> reserve(String article) async =>
      (await base.select('SELECT CAST(COALESCE(SUM(reste),0) AS BIGINT) AS s FROM baux WHERE article=?', [article])).first['s'] as num;

  Future<int> seqMax() async => (await base.select('SELECT CAST(COALESCE(MAX(seq),0) AS BIGINT) AS s FROM operations')).first['s'] as int;

  // --- le cœur : une opération → un résultat NOMMÉ -----------------------------------------------
  Future<Map<String, Object?>> traiter(Map op, Appareil app) async {
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
    final f = await lire(collection, ficheId);

    if (fam == 'D') {
      if (type == 'creer') {
        if (app.role != 'mere') return refus('droit_refuse', 'Le stock initial s’ouvre à la console de la mère.', 'Contacter l’administrateur');
        final seq = await journaliser(op, champsOp, app.uuid);
        await ecrire(collection, ficheId, Fiche({'qte': nb(champsOp['qte'])}, {'qte': seq}, false));
        return {'id': id, 'statut': 'acceptee', 'seq': seq};
      }
      if (type == 'sortie') {
        if (f == null) return refus('fiche_inconnue', 'Article inconnu : $ficheId', 'Vérifier la référence');
        final q = nb(champsOp['qte']);
        final bail = await base.select('SELECT reste FROM baux WHERE appareil=? AND article=?', [app.uuid, ficheId]);
        var surBail = false;
        if (op['bail'] == true && bail.isNotEmpty && (bail.first['reste'] as num) >= q) {
          await base.exec('UPDATE baux SET reste=reste-? WHERE appareil=? AND article=?', [q, app.uuid, ficheId]);
          surBail = true;
        } else {
          final dispo = (f.data['qte'] as num) - await reserve(ficheId);
          if (dispo < q) {
            return refus('invariant_viole', 'Stock insuffisant pour $ficheId : disponible $dispo, demandé $q (RG-03).',
                'Réduire la quantité ou attendre un réapprovisionnement');
          }
        }
        f.data['qte'] = (f.data['qte'] as num) - q;
        final seq = await journaliser(op, {'qte': q}, app.uuid);
        f.fieldseq['qte'] = seq;
        await ecrire(collection, ficheId, f);
        return {'id': id, 'statut': 'acceptee', 'seq': seq, 'surBail': surBail};
      }
      return refus('type_invalide', 'Opération non prévue sur le stock : $type', 'Utiliser une sortie');
    }

    if (fam == 'B') {
      if (type != 'creer') return refus('journal_immuable', 'Un journal ne se modifie pas : on ajoute une ligne.', 'Ajouter une nouvelle ligne');
      if (f != null) return refus('fiche_existe', 'Cette ligne existe déjà.', 'Aucun');
      final seq = await journaliser(op, champsOp, app.uuid);
      await ecrire(collection, ficheId, Fiche({...champsOp}, {for (final k in champsOp.keys) k: seq}, false));
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
          final n = await base.metaInt('next_patient');
          await base.poserMeta('next_patient', n + 1);
          champs['code'] = 'CNT/$n/26';
          numero = '${champs['code']}';
        } else if (m == null) {
          return refus('numero_invalide', 'Code patient mal formé : $code', 'Laisser le poste attribuer le code');
        } else {
          final n = int.parse(m.group(1)!);
          final ok = await base.select('SELECT 1 FROM plages WHERE appareil=? AND nom=? AND debut<=? AND fin>=?', [app.uuid, 'patients', n, n]);
          if (ok.isEmpty) return refus('numero_hors_plage', 'Le code $code n’appartient pas à la plage de ce poste.', 'Demander une nouvelle plage');
        }
        final dup = await base.select("SELECT 1 FROM fiches WHERE collection='patients' AND ${base.champJson('data', 'code')}=?", ['${champs['code']}']);
        if (dup.isNotEmpty) return refus('doublon_numero', 'Code patient déjà attribué : ${champs['code']}', 'Demander une nouvelle plage');
      }
      String? doublon;
      if (collection == 'patients' && champs['nom'] != null && '${champs['nom']}'.isNotEmpty && champs['naissance'] != null && '${champs['naissance']}'.isNotEmpty) {
        final nomK = '${champs['nom']}'.trim().toLowerCase();
        for (final r in await base.select("SELECT id,data FROM fiches WHERE collection='patients'")) {
          final d = (jsonDecode(r['data'] as String) as Map);
          if ('${d['nom'] ?? ''}'.trim().toLowerCase() == nomK && '${d['naissance'] ?? ''}' == '${champs['naissance']}') {
            doublon = r['id'] as String;
            break;
          }
        }
      }
      final seq = await journaliser(op, champs, app.uuid);
      await ecrire(collection, ficheId, Fiche(champs, {for (final k in champs.keys) k: seq}, false));
      if (doublon != null) {
        await base.exec('INSERT INTO conflits(collection,fiche,champ,a,b,appareil) VALUES(?,?,?,?,?,?)',
            [collection, ficheId, 'doublon_possible', enJson(doublon), enJson(ficheId), app.uuid]);
      }
      return {'id': id, 'statut': 'acceptee', 'seq': seq, 'numero': ?numero, 'doublon_possible': ?doublon};
    }
    if (f == null) return refus('fiche_inconnue', 'Fiche inconnue : $ficheId', 'Rafraîchir le poste');
    if (type == 'archiver' || type == 'restaurer') {
      f.archive = type == 'archiver';
      final seq = await journaliser(op, {}, app.uuid);
      await ecrire(collection, ficheId, f);
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
          final r = await base.select('INSERT INTO conflits(collection,fiche,champ,a,b,appareil) VALUES(?,?,?,?,?,?) RETURNING id',
              [collection, ficheId, e.key, enJson(f.data[e.key]), enJson(e.value), app.uuid]);
          conflits.add({'conflit': r.first['id'], 'champ': e.key});
        } else {
          appliques[e.key] = e.value;
        }
      }
      int? seq;
      if (appliques.isNotEmpty) {
        seq = await journaliser(op, appliques, app.uuid);
        for (final k in appliques.keys) {
          f.data[k] = appliques[k];
          f.fieldseq[k] = seq;
        }
        await ecrire(collection, ficheId, f);
      }
      return conflits.isNotEmpty
          ? {'id': id, 'statut': 'fusionnee', 'seq': seq, 'conflits': conflits}
          : {'id': id, 'statut': 'acceptee', 'seq': seq};
    }
    return refus('type_invalide', 'Type d’opération inconnu : $type', 'Mettre le poste à jour');
  }

  // --- authentification ---------------------------------------------------------------------------
  Future<Appareil> auth(HttpRequest req) async {
    final m = RegExp(r'^Bearer ([^.]+)\.(.+)$').firstMatch(req.headers.value('authorization') ?? '');
    if (m == null) throw Err(401, 'jeton_invalide', 'Jeton absent.');
    final r = await base.select('SELECT * FROM appareils WHERE uuid=?', [m.group(1)]);
    if (r.isEmpty) throw Err(401, 'jeton_invalide', 'Appareil inconnu.');
    final a = r.first;
    if (a['etat'] == 'revoque') throw Err(401, 'appareil_revoque', 'Cet appareil a été révoqué.');
    if (sha256hex(m.group(2)!) != a['jeton_hash']) throw Err(401, 'jeton_invalide', 'Jeton invalide.');
    if (maintenantMs() > (a['jeton_expire'] as int)) throw Err(401, 'jeton_expire', 'Jeton expiré.');
    await base.exec('UPDATE appareils SET dernier_contact=? WHERE uuid=?', [maintenantMs(), a['uuid']]);
    return Appareil(a['uuid'] as String, a['role'] as String, a['profil'] as String?);
  }

  void adminOk(HttpRequest req) {
    if (req.headers.value('x-admin') != cfg.admin) throw Err(403, 'admin_requis', 'Accès administrateur requis.');
  }

  Future<Map<String, Object?>> emettreJetons(String uuid) async {
    final secret = hexAlea(24);
    final renouv = hexAlea(24);
    await base.exec('UPDATE appareils SET jeton_hash=?, jeton_expire=?, renouv_hash=? WHERE uuid=?',
        [sha256hex(secret), maintenantMs() + cfg.jetonTtl, sha256hex(renouv), uuid]);
    return {'jeton': '$uuid.$secret', 'renouvellement': '$uuid.$renouv'};
  }

  String codeAppairage() {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(8, (_) => alphabet[r.nextInt(alphabet.length)]).join();
  }

  /// L'envoi d'un lot, commun aux postes (P1) et aux mobiles (P2/P3).
  Future<Map<String, Object?>> pousser(Appareil app, Map b) async {
    final epoch = await base.metaInt('epoch');
    if (b['epoch'] != epoch) throw Err(409, 'epoch_inconnue', 'Époque inconnue de la mère.', {'epoch_mere': epoch});
    final derive = (maintenantMs() - (b['horloge'] is num ? (b['horloge'] as num).toInt() : maintenantMs())).abs();
    await base.exec('UPDATE appareils SET derive_ms=? WHERE uuid=?', [derive, app.uuid]);
    final resultats = await base.tx(() async {
      final sortie = <Map<String, Object?>>[];
      for (final o in ((b['ops'] ?? []) as List)) {
        final op = (o as Map);
        final deja = await base.select('SELECT corps FROM resultats WHERE id=?', [op['id']]);
        if (deja.isNotEmpty) {
          sortie.add({...(jsonDecode(deja.first['corps'] as String) as Map).cast<String, Object?>(), 'rejeu': true});
          continue;
        }
        Map<String, Object?> r;
        if (app.role == 'mobile' && !(autorise[app.profil] ?? <String>{}).contains(op['collection'])) {
          r = {
            'id': op['id'], 'statut': 'refusee', 'code': 'droit_refuse',
            'motif': 'Le profil « ${app.profil} » ne couvre pas la collection ${op['collection']}.', 'geste': 'Utiliser un poste',
          };
        } else {
          r = await traiter(op, app);
        }
        if (app.role == 'mobile' && r['statut'] == 'acceptee' && op['type'] == 'creer') {
          await base.exec('INSERT INTO portee(appareil,collection,fiche) VALUES(?,?,?) ON CONFLICT DO NOTHING', [app.uuid, op['collection'], op['fiche']]);
        }
        await base.exec('INSERT INTO resultats(id,corps) VALUES(?,?)', [op['id'], enJson(r)]);
        sortie.add(r);
      }
      return sortie;
    });
    return {'resultats': resultats, 'seq_max': await seqMax()};
  }

  // --- routes ---------------------------------------------------------------------------------------
  Future<Object?> route(String cle, HttpRequest req, Map<String, Object?> b, Map<String, String> q) async {
    switch (cle) {
      case 'POST /admin/code':
        adminOk(req);
        final code = codeAppairage();
        await base.exec('INSERT INTO codes(code,etiquette,role,expire) VALUES(?,?,?,?)',
            [code, b['etiquette'] ?? '', b['role'] ?? 'fileul', maintenantMs() + cfg.codeTtl]);
        return {'code': code};
      case 'POST /appairage':
        final r = await base.select('SELECT * FROM codes WHERE code=?', ['${b['code'] ?? ''}']);
        if (r.isEmpty) throw Err(403, 'code_invalide', 'Code d’appairage inconnu.');
        final c = r.first;
        if ((c['utilise'] as int) != 0) throw Err(403, 'code_utilise', 'Ce code a déjà servi (usage unique).');
        if (maintenantMs() > (c['expire'] as int)) throw Err(403, 'code_expire', 'Ce code a expiré.');
        await base.exec('UPDATE codes SET utilise=1 WHERE code=?', [c['code']]);
        await base.exec('INSERT INTO appareils(uuid,etiquette,role,etat) VALUES(?,?,?,?)', [b['uuid'], c['etiquette'], c['role'], 'actif']);
        await evenement('info', 'appairage', 'Appareil appairé : ${c['etiquette']} (${c['role']})');
        return {'epoch': await base.metaInt('epoch'), ...await emettreJetons(b['uuid'] as String)};
      case 'POST /renouveler':
        final m = RegExp(r'^([^.]+)\.(.+)$').firstMatch('${b['renouvellement'] ?? ''}');
        final rr = m == null ? null : await base.select('SELECT * FROM appareils WHERE uuid=?', [m.group(1)]);
        if (rr == null || rr.isEmpty || rr.first['etat'] == 'revoque') throw Err(401, 'appareil_revoque', 'Appareil révoqué.');
        final a = rr.first;
        if (sha256hex(m!.group(2)!) != a['renouv_hash']) {
          await base.exec("UPDATE appareils SET etat='revoque' WHERE uuid=?", [a['uuid']]);
          throw Err(401, 'appareil_revoque', 'Renouvellement rejoué : appareil révoqué par précaution.');
        }
        return emettreJetons(a['uuid'] as String);
      case 'POST /sync/push':
        return pousser(await auth(req), b);
      case 'GET /sync/pull':
        final app = await auth(req);
        final epoch = await base.metaInt('epoch');
        if ((int.tryParse(q['epoch'] ?? '') ?? -1) != epoch) throw Err(409, 'epoch_inconnue', 'Époque inconnue de la mère.', {'epoch_mere': epoch});
        final depuis = int.tryParse(q['depuis'] ?? '') ?? 0;
        final limite = min(int.tryParse(q['limite'] ?? '') ?? 500, 500);
        final ops = (await base.select('SELECT seq,id,appareil,collection,fiche,type,champs FROM operations WHERE seq>? ORDER BY seq LIMIT ?', [depuis, limite]))
            .map((o) => {...o, 'champs': jsonDecode(o['champs'] as String)})
            .toList();
        await base.exec('UPDATE appareils SET dernier_seq = CASE WHEN dernier_seq > ? THEN dernier_seq ELSE ? END WHERE uuid=?', [depuis, depuis, app.uuid]);
        final marque = await base.meta('resync');
        return {'ops': ops, 'fin': ops.length < limite, 'epoch': epoch, 'resync': (marque == null || marque.isEmpty) ? null : marque};
      case 'POST /sync/plage':
        final app2 = await auth(req);
        final taille = max(1, min(nb(b['taille']).toInt() == 0 ? 50 : nb(b['taille']).toInt(), 1000));
        return base.tx(() async {
          final debut = await base.metaInt('next_patient');
          final fin = debut + taille - 1;
          await base.poserMeta('next_patient', fin + 1);
          await base.exec('INSERT INTO plages(appareil,nom,debut,fin) VALUES(?,?,?,?)', [app2.uuid, b['nom'] ?? 'patients', debut, fin]);
          return {'debut': debut, 'fin': fin};
        });
      case 'POST /sync/bail':
        final app3 = await auth(req);
        return base.tx(() async {
          final f = await lire('stock', '${b['article']}');
          if (f == null) throw Err(422, 'fiche_inconnue', 'Article inconnu : ${b['article']}');
          final dispo = (f.data['qte'] as num) - await reserve('${b['article']}');
          final accorde = max(0, min(nb(b['qte']), dispo));
          await base.exec('INSERT INTO baux(appareil,article,reste) VALUES(?,?,?) ON CONFLICT(appareil,article) DO UPDATE SET reste=baux.reste+excluded.reste',
              [app3.uuid, b['article'], accorde]);
          final reste = (await base.select('SELECT reste FROM baux WHERE appareil=? AND article=?', [app3.uuid, b['article']])).first['reste'];
          return {'accorde': accorde, 'reste': reste};
        });
      case 'POST /sync/ack-resync':
        final app4 = await auth(req);
        await base.exec('INSERT INTO acks(marque,appareil) VALUES(?,?) ON CONFLICT DO NOTHING', ['${b['marque']}', app4.uuid]);
        return {'ok': true};
      case 'POST /admin/revoquer':
        adminOk(req);
        await base.exec("UPDATE appareils SET etat='revoque' WHERE uuid=?", [b['uuid']]);
        await evenement('info', 'administration', 'Appareil révoqué : ${b['uuid']}');
        pont.revoquerAuRelais('${b['uuid']}');
        return {'ok': true};
      case 'POST /admin/lot':
        adminOk(req);
        return pont.lot(b);
      case 'POST /admin/debloquer':
        adminOk(req);
        await base.poserMeta('bloque:${b['uuid']}', '');
        return {'ok': true};
      case 'POST /admin/resync':
        adminOk(req);
        final m2 = '${maintenantMs()}';
        await base.poserMeta('resync', m2);
        return {'marque': m2};
      case 'GET /admin/etat':
        adminOk(req);
        final marque = await base.meta('resync');
        final marqueOk = (marque == null || marque.isEmpty) ? null : marque;
        return {
          'epoch': await base.metaInt('epoch'),
          'seq_max': await seqMax(),
          'appareils': (await base.select('SELECT uuid,etiquette,role,etat,dernier_contact,dernier_seq,derive_ms FROM appareils')).toList(),
          'derives': (await base.select('SELECT uuid FROM appareils WHERE derive_ms>?', [_deriveMaxMs])).map((x) => x['uuid']).toList(),
          'conflits_ouverts': (await base.select("SELECT COUNT(*) AS n FROM conflits WHERE etat='ouvert'")).first['n'],
          'resync': {
            'marque': marqueOk,
            'acks': marqueOk == null ? [] : (await base.select('SELECT appareil FROM acks WHERE marque=?', [marqueOk])).map((x) => x['appareil']).toList(),
          },
          'reinit_ouverte': await base.meta('reinit_ouverte') == '1',
          'nb_operations': (await base.select('SELECT COUNT(*) AS n FROM operations')).first['n'],
          'rep_seq': await base.metaInt('rep_seq'),
          'rep_n': await base.metaInt('rep_n'),
          'alertes': pont.alertes,
          'restauration': await base.meta('restauration'),
          'bloques': (await base.select("SELECT k FROM meta WHERE k LIKE 'bloque:%' AND v<>''")).map((x) => (x['k'] as String).substring(7)).toList(),
          'depot': base.dialecte,
        };
      case 'POST /admin/sauvegarder':
        adminOk(req);
        return {'fichier': await sauvegarderChiffre(prefixe: 'manuelle')};
      case 'GET /admin/supervision':
        adminOk(req);
        final controles = await controlesMere(this);
        return {'etat': etatGlobal(controles), 'controles': controles, 'depot': base.dialecte, 'quand': maintenantMs()};
      case 'GET /admin/journal':
        adminOk(req);
        final lim = min(int.tryParse(q['limite'] ?? '') ?? 100, 500);
        return (await base.select('SELECT id,quand,niveau,source,message FROM evenements ORDER BY id DESC LIMIT ?', [lim])).toList();
      case 'GET /admin/fiche':
        adminOk(req);
        final f = await lire(q['collection'] ?? '', q['id'] ?? '');
        return f == null ? {'absente': true} : {'data': f.data, 'fieldseq': f.fieldseq, 'archive': f.archive};
      case 'GET /admin/compte':
        adminOk(req);
        return {'n': (await base.select('SELECT COUNT(*) AS n FROM fiches WHERE collection=? AND archive=0', [q['collection']])).first['n']};
      case 'GET /admin/empreinte':
        adminOk(req);
        final rows = (await base.select('SELECT collection,id,data,archive FROM fiches ORDER BY collection,id')).toList();
        return {'empreinte': sha256hex(enJson(rows)), 'n': rows.length};
      case 'GET /admin/conflits':
        adminOk(req);
        return (await base.select('SELECT * FROM conflits ORDER BY id')).toList();
      case 'POST /admin/trancher':
        adminOk(req);
        return base.tx(() async {
          final r = await base.select('SELECT * FROM conflits WHERE id=?', [b['id']]);
          if (r.isEmpty || r.first['etat'] != 'ouvert') throw Err(422, 'conflit_inconnu', 'Conflit inexistant ou déjà tranché.');
          final c = r.first;
          if (b['decision'] == 'b') {
            final f = (await lire(c['collection'] as String, c['fiche'] as String))!;
            final val = jsonDecode(c['b'] as String);
            final op = {'id': 'tranche-${c['id']}-${uuid7()}', 'collection': c['collection'], 'fiche': c['fiche'], 'type': 'modifier', 'champs': {c['champ']: val}, 'hlc': maintenantMs()};
            final seq = await journaliser(op, {c['champ'] as String: val}, 'mere');
            f.data[c['champ'] as String] = val;
            f.fieldseq[c['champ'] as String] = seq;
            await ecrire(c['collection'] as String, c['fiche'] as String, f);
          }
          await base.exec("UPDATE conflits SET etat='tranche', decision=? WHERE id=?", [b['decision'], c['id']]);
          return {'ok': true};
        });
      case 'POST /admin/referentiel':
        adminOk(req);
        return base.tx(() async {
          final existe = await lire('${b['collection']}', '${b['fiche']}');
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
        await base.poserMeta('reinit_ouverte', b['ouvrir'] == true ? 1 : 0);
        return {'ouverte': b['ouvrir'] == true};
      case 'POST /admin/reinitialiser':
        adminOk(req);
        if (await base.meta('reinit_ouverte') != '1') throw Err(403, 'reinit_fermee', 'La réinitialisation est fermée : l’administrateur doit ouvrir la fenêtre.');
        if (b['confirmation'] != _clinique) throw Err(422, 'confirmation_invalide', 'Saisir le nom de la clinique pour confirmer.');
        if (b['second'] == null || b['second'] == '' || b['second'] == false) throw Err(422, 'second_profil_requis', 'Un second profil (DAF ou Direction) doit confirmer.');
        final sauvegarde = await base.sauvegarder('avant-reinit');
        await evenement('alerte', 'administration', 'Réinitialisation des données (sauvegarde préalable : $sauvegarde)');
        await base.tx(() async {
          final liste = essentielles.map((c) => "'$c'").join(',');
          await base.exec('DELETE FROM operations WHERE collection NOT IN ($liste)');
          await base.exec('DELETE FROM fiches WHERE collection NOT IN ($liste)');
          for (final t in ['resultats', 'conflits', 'plages', 'baux', 'acks', 'portee']) {
            await base.exec('DELETE FROM $t');
          }
          await base.poserMeta('epoch', await base.metaInt('epoch') + 1);
          await base.poserMeta('reinit_ouverte', 0);
          await base.poserMeta('next_patient', 1000);
          await base.poserMeta('marqueur_epoch', 1);
        });
        return {'sauvegarde': sauvegarde, 'epoch': await base.metaInt('epoch')};
    }
    throw Err(404, 'route_inconnue', 'Route inconnue.');
  }

  /// Sauvegarde chiffrée (AES-256-GCM, clé de clinique) : le fichier en clair n'existe que le temps de l'écriture.
  /// Conserve les `conservation` dernières ; rend le chemin du fichier chiffré. Appelée sous le verrou.
  Future<String> sauvegarderChiffre({String prefixe = 'quotidienne'}) async {
    final clair = await base.sauvegarder(prefixe, dossier: cfg.dossierSauvegardes);
    final fichier = File(clair);
    final chiffre = File('$clair.enc');
    chiffre.writeAsBytesSync(await pont.env.chiffrerOctets(fichier.readAsBytesSync(), 'sauvegarde-mere'));
    fichier.deleteSync();
    final dossier = Directory(cfg.dossierSauvegardes);
    final anciennes = dossier.listSync().whereType<File>().where((f) => f.path.contains('.$prefixe-') && f.path.endsWith('.enc')).toList()..sort((a, b) => a.path.compareTo(b.path));
    for (final f in anciennes.take(anciennes.length > cfg.conservation ? anciennes.length - cfg.conservation : 0)) {
      f.deleteSync();
    }
    await base.poserMeta('derniere_sauvegarde', maintenantMs());
    await evenement('info', 'sauvegarde', 'Sauvegarde chiffrée : ${chiffre.path}');
    return chiffre.path;
  }

  /// Le code d'un mobile : la base d'abord (sous verrou), puis le relais (réseau, hors verrou — une panne d'Internet
  /// ne doit jamais bloquer les postes de la clinique).
  Future<Object?> codeMobile(HttpRequest req, Map<String, Object?> b) async {
    adminOk(req);
    final code = codeAppairage();
    await verrou.executer(() => base.exec('INSERT INTO codes(code,etiquette,role,expire) VALUES(?,?,?,?)', [code, b['etiquette'] ?? '', 'mobile', maintenantMs() + cfg.codeTtl]));
    await pont.declarerCode(sha256hex(code));
    return {'code': code, 'cle': pont.cleBase64};
  }

  Future<void> demarrer() async {
    _serveur = await HttpServer.bind(InternetAddress.loopbackIPv4, cfg.port);
    pont.demarrer();
    // Sauvegarde quotidienne : toutes les 5 minutes on regarde si l'heure est venue et si la dernière a plus de 20 h.
    _sauvegardeur = Timer.periodic(const Duration(minutes: 5), (_) async {
      try {
        final due = DateTime.now().hour >= cfg.heureSauvegarde && maintenantMs() - await base.metaInt('derniere_sauvegarde') > 20 * 3600 * 1000;
        if (due) await verrou.executer(() => sauvegarderChiffre());
      } catch (e) {
        evenementAsync('erreur', 'sauvegarde', 'Sauvegarde quotidienne impossible : $e');
      }
    });
    _serveur!.listen((req) async {
      final b = await corpsJson(req);
      final q = req.uri.queryParameters;
      int statut = 200;
      Object? out;
      try {
        final cle = '${req.method} ${req.uri.path}';
        out = cle == 'POST /admin/code-mobile' ? await codeMobile(req, b) : await verrou.executer(() => route(cle, req, b, q));
      } on Err catch (e) {
        statut = e.statut;
        out = e.corps;
      } catch (e, s) {
        statut = 500;
        out = {'code': 'erreur_interne', 'motif': '$e', 'pile': '$s'.split('\n').take(3).join(' | ')};
        evenementAsync('erreur', 'requete', '${req.method} ${req.uri.path} : $e');
      }
      try {
        await repondre(req, statut, out);
      } catch (_) {/* le client est parti */}
    });
    annoncerPret(_serveur!.port);
  }

  Future<void> arreter() async {
    _sauvegardeur?.cancel();
    await _serveur?.close(force: true);
    await base.fermer();
  }
}
