'use strict';
/* =============================================================================
 * SIGH-CNT — BANC DE SYNCHRONISATION : le POSTE MÈRE (implémentation de référence)
 * -----------------------------------------------------------------------------
 * Ce fichier n'est PAS le produit : c'est l'exécutable de référence du protocole
 * décrit dans docs/specs/SPEC-protocole-synchronisation.md. Il sert à éprouver
 * l'architecture (coupures, rejeux, conflits, bail de stock, époque) avant d'écrire
 * le service Dart. Stockage : SQLite pour le banc ; la cible est PostgreSQL derrière
 * la même interface de transactions. Aucune dépendance.
 *
 * Lancement : node mere.js --port=9000 --db=mere.sqlite --admin=secret
 * ========================================================================== */
const http = require('node:http');
const crypto = require('node:crypto');
const { DatabaseSync } = require('node:sqlite');

const arg = (n, d) => { const a = process.argv.find((x) => x.startsWith('--' + n + '=')); return a ? a.split('=').slice(1).join('=') : d; };
const PORT = +arg('port', 0);
const DB = arg('db', ':memory:');
const ADMIN = arg('admin', 'admin-banc');
const CODE_TTL = +arg('code-ttl', 15 * 60 * 1000);
const JETON_TTL = +arg('jeton-ttl', 24 * 3600 * 1000);
const CLINIQUE = 'NASSIERA TOO';
const DERIVE_MAX_MS = 2 * 60 * 1000;

/* Une famille par collection (PRD §8) : A fiche descriptive · B journal · C pièce
   émise · D agrégat à invariant · R référentiel (la mère seule écrit). */
const FAMILLES = {
  patients: 'A', rendezvous: 'A',
  constantes: 'B', notes: 'B',
  factures: 'C',
  stock: 'D',
  tarifs: 'R', chambres: 'R',
};
const ESSENTIELLES = new Set(['tarifs', 'chambres']);

const db = new DatabaseSync(DB);
db.exec(`
  PRAGMA journal_mode = WAL;
  CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT);
  CREATE TABLE IF NOT EXISTS operations (seq INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT UNIQUE, appareil TEXT, epoch INTEGER,
    hlc INTEGER, collection TEXT, fiche TEXT, type TEXT, champs TEXT, famille TEXT);
  CREATE TABLE IF NOT EXISTS resultats (id TEXT PRIMARY KEY, json TEXT);
  CREATE TABLE IF NOT EXISTS fiches (collection TEXT, id TEXT, data TEXT, fieldseq TEXT, archive INTEGER, PRIMARY KEY (collection, id));
  CREATE TABLE IF NOT EXISTS appareils (uuid TEXT PRIMARY KEY, etiquette TEXT, role TEXT, etat TEXT, jeton_hash TEXT, jeton_expire INTEGER,
    renouv_hash TEXT, dernier_contact INTEGER, dernier_seq INTEGER DEFAULT 0, derive_ms INTEGER DEFAULT 0);
  CREATE TABLE IF NOT EXISTS codes (code TEXT PRIMARY KEY, etiquette TEXT, role TEXT, expire INTEGER, utilise INTEGER DEFAULT 0);
  CREATE TABLE IF NOT EXISTS conflits (id INTEGER PRIMARY KEY AUTOINCREMENT, collection TEXT, fiche TEXT, champ TEXT, a TEXT, b TEXT,
    appareil TEXT, etat TEXT DEFAULT 'ouvert', decision TEXT);
  CREATE TABLE IF NOT EXISTS plages (appareil TEXT, nom TEXT, debut INTEGER, fin INTEGER);
  CREATE TABLE IF NOT EXISTS baux (appareil TEXT, article TEXT, reste INTEGER, PRIMARY KEY (appareil, article));
  CREATE TABLE IF NOT EXISTS acks (marque TEXT, appareil TEXT, PRIMARY KEY (marque, appareil));
`);
const meta = (k, d) => { const r = db.prepare('SELECT v FROM meta WHERE k=?').get(k); return r ? r.v : d; };
const setMeta = (k, v) => db.prepare('INSERT INTO meta(k,v) VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v').run(k, String(v));
if (meta('epoch') === undefined) setMeta('epoch', 1);
if (meta('next_patient') === undefined) setMeta('next_patient', 1000);
if (meta('reinit_ouverte') === undefined) setMeta('reinit_ouverte', 0);

const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');
const tx = (fn) => { db.exec('BEGIN IMMEDIATE'); try { const r = fn(); db.exec('COMMIT'); return r; } catch (e) { db.exec('ROLLBACK'); throw e; } };
class Err extends Error { constructor(status, code, motif, extra) { super(motif || code); this.status = status; this.body = Object.assign({ code, motif }, extra || {}); } }

/* --- fiches ---------------------------------------------------------------- */
function lire(c, id) {
  const r = db.prepare('SELECT * FROM fiches WHERE collection=? AND id=?').get(c, id);
  return r ? { data: JSON.parse(r.data), fieldseq: JSON.parse(r.fieldseq), archive: !!r.archive } : null;
}
function ecrire(c, id, f) {
  db.prepare(`INSERT INTO fiches(collection,id,data,fieldseq,archive) VALUES(?,?,?,?,?)
    ON CONFLICT(collection,id) DO UPDATE SET data=excluded.data, fieldseq=excluded.fieldseq, archive=excluded.archive`)
    .run(c, id, JSON.stringify(f.data), JSON.stringify(f.fieldseq), f.archive ? 1 : 0);
}
function journaliser(op, champs, appareil) {
  const r = db.prepare('INSERT INTO operations(id,appareil,epoch,hlc,collection,fiche,type,champs,famille) VALUES(?,?,?,?,?,?,?,?,?)')
    .run(op.id, appareil, +meta('epoch'), op.hlc || 0, op.collection, op.fiche, op.type, JSON.stringify(champs || {}), FAMILLES[op.collection]);
  return Number(r.lastInsertRowid);
}
const reserve = (article) => db.prepare('SELECT COALESCE(SUM(reste),0) AS s FROM baux WHERE article=?').get(article).s;

/* --- le cœur : une opération → un résultat NOMMÉ ----------------------------- */
function traiter(op, app) {
  const fam = FAMILLES[op.collection];
  const refus = (code, motif, geste) => ({ id: op.id, statut: 'refusee', code, motif, geste });
  if (!fam) return refus('collection_inconnue', 'Collection inconnue : ' + op.collection, 'Mettre le poste à jour');
  if (op.type === 'supprimer') return refus('suppression_interdite', 'Aucune suppression physique (RG-14).', 'Archiver la fiche');
  if (fam === 'R' && app.role !== 'mere') return refus('droit_refuse', 'Un référentiel ne se modifie qu’à la console de la mère.', 'Demander la modification à l’administrateur');

  const f = lire(op.collection, op.fiche);

  if (fam === 'D') {
    if (op.type === 'creer') {
      if (app.role !== 'mere') return refus('droit_refuse', 'Le stock initial s’ouvre à la console de la mère.', 'Contacter l’administrateur');
      const seq = journaliser(op, op.champs, app.uuid);
      ecrire(op.collection, op.fiche, { data: { qte: +op.champs.qte || 0 }, fieldseq: { qte: seq }, archive: false });
      return { id: op.id, statut: 'acceptee', seq };
    }
    if (op.type === 'sortie') {
      if (!f) return refus('fiche_inconnue', 'Article inconnu : ' + op.fiche, 'Vérifier la référence');
      const q = +op.champs.qte;
      const bail = db.prepare('SELECT reste FROM baux WHERE appareil=? AND article=?').get(app.uuid, op.fiche);
      let surBail = false;
      if (op.bail && bail && bail.reste >= q) {
        db.prepare('UPDATE baux SET reste=reste-? WHERE appareil=? AND article=?').run(q, app.uuid, op.fiche);
        surBail = true;
      } else {
        const dispo = f.data.qte - reserve(op.fiche);
        if (dispo < q) return refus('invariant_viole', `Stock insuffisant pour ${op.fiche} : disponible ${dispo}, demandé ${q} (RG-03).`, 'Réduire la quantité ou attendre un réapprovisionnement');
      }
      f.data.qte -= q;
      const seq = journaliser(op, { qte: q }, app.uuid);
      f.fieldseq.qte = seq;
      ecrire(op.collection, op.fiche, f);
      return { id: op.id, statut: 'acceptee', seq, surBail };
    }
    return refus('type_invalide', 'Opération non prévue sur le stock : ' + op.type, 'Utiliser une sortie');
  }

  if (fam === 'B') {
    if (op.type !== 'creer') return refus('journal_immuable', 'Un journal ne se modifie pas : on ajoute une ligne.', 'Ajouter une nouvelle ligne');
    if (f) return refus('fiche_existe', 'Cette ligne existe déjà.', 'Aucun');
    const seq = journaliser(op, op.champs, app.uuid);
    ecrire(op.collection, op.fiche, { data: op.champs, fieldseq: Object.fromEntries(Object.keys(op.champs).map((k) => [k, seq])), archive: false });
    return { id: op.id, statut: 'acceptee', seq };
  }

  /* A, C et R : fusion par champ */
  if (op.type === 'creer') {
    if (f) return refus('fiche_existe', 'Cette fiche existe déjà.', 'Aucun');
    const champs = Object.assign({}, op.champs);
    let numero;
    if (op.collection === 'patients') {
      const m = /^CNT\/(\d+)\/26$/.exec(String(champs.code || ''));
      if (!champs.code || String(champs.code).startsWith('PROV-')) {
        const n = +meta('next_patient'); setMeta('next_patient', n + 1);
        champs.code = `CNT/${n}/26`; numero = champs.code;
      } else if (!m) {
        return refus('numero_invalide', 'Code patient mal formé : ' + champs.code, 'Laisser le poste attribuer le code');
      } else {
        const n = +m[1];
        const ok = db.prepare('SELECT 1 FROM plages WHERE appareil=? AND nom=? AND debut<=? AND fin>=?').get(app.uuid, 'patients', n, n);
        if (!ok) return refus('numero_hors_plage', `Le code ${champs.code} n’appartient pas à la plage de ce poste.`, 'Demander une nouvelle plage');
      }
      const dup = db.prepare("SELECT 1 FROM fiches WHERE collection='patients' AND json_extract(data,'$.code')=?").get(champs.code);
      if (dup) return refus('doublon_numero', 'Code patient déjà attribué : ' + champs.code, 'Demander une nouvelle plage');
    }
    const seq = journaliser(op, champs, app.uuid);
    ecrire(op.collection, op.fiche, { data: champs, fieldseq: Object.fromEntries(Object.keys(champs).map((k) => [k, seq])), archive: false });
    return Object.assign({ id: op.id, statut: 'acceptee', seq }, numero ? { numero } : {});
  }
  if (!f) return refus('fiche_inconnue', 'Fiche inconnue : ' + op.fiche, 'Rafraîchir le poste');
  if (op.type === 'archiver' || op.type === 'restaurer') {
    f.archive = op.type === 'archiver';
    const seq = journaliser(op, {}, app.uuid);
    ecrire(op.collection, op.fiche, f);
    return { id: op.id, statut: 'acceptee', seq };
  }
  if (op.type === 'modifier') {
    if (f.archive) return refus('fiche_archivee', 'La fiche est archivée : restaurez-la d’abord (RG-14).', 'Restaurer la fiche');
    if (fam === 'C' && f.data.emise) return refus('piece_emise_immuable', 'Une pièce émise ne se réécrit jamais : émettre un avoir.', 'Établir une pièce de correction');
    const appliques = {}; const conflits = [];
    for (const [champ, val] of Object.entries(op.champs)) {
      const vu = (op.vu && op.vu[champ]) || 0;
      if ((f.fieldseq[champ] || 0) > vu && JSON.stringify(f.data[champ]) !== JSON.stringify(val)) {
        const r = db.prepare('INSERT INTO conflits(collection,fiche,champ,a,b,appareil) VALUES(?,?,?,?,?,?)')
          .run(op.collection, op.fiche, champ, JSON.stringify(f.data[champ] === undefined ? null : f.data[champ]), JSON.stringify(val), app.uuid);
        conflits.push({ conflit: Number(r.lastInsertRowid), champ });
      } else appliques[champ] = val;
    }
    let seq = null;
    if (Object.keys(appliques).length) {
      seq = journaliser(op, appliques, app.uuid);
      for (const k of Object.keys(appliques)) { f.data[k] = appliques[k]; f.fieldseq[k] = seq; }
      ecrire(op.collection, op.fiche, f);
    }
    return conflits.length ? { id: op.id, statut: 'fusionnee', seq, conflits } : { id: op.id, statut: 'acceptee', seq };
  }
  return refus('type_invalide', 'Type d’opération inconnu : ' + op.type, 'Mettre le poste à jour');
}

/* --- authentification ---------------------------------------------------------- */
function auth(req) {
  const m = /^Bearer ([^.]+)\.(.+)$/.exec(req.headers.authorization || '');
  if (!m) throw new Err(401, 'jeton_invalide', 'Jeton absent.');
  const a = db.prepare('SELECT * FROM appareils WHERE uuid=?').get(m[1]);
  if (!a) throw new Err(401, 'jeton_invalide', 'Appareil inconnu.');
  if (a.etat === 'revoque') throw new Err(401, 'appareil_revoque', 'Cet appareil a été révoqué.');
  if (sha(m[2]) !== a.jeton_hash) throw new Err(401, 'jeton_invalide', 'Jeton invalide.');
  if (Date.now() > a.jeton_expire) throw new Err(401, 'jeton_expire', 'Jeton expiré.');
  db.prepare('UPDATE appareils SET dernier_contact=? WHERE uuid=?').run(Date.now(), a.uuid);
  return a;
}
const adminOk = (req) => { if (req.headers['x-admin'] !== ADMIN) throw new Err(403, 'admin_requis', 'Accès administrateur requis.'); };
function emettreJetons(uuid) {
  const secret = crypto.randomBytes(24).toString('hex');
  const renouv = crypto.randomBytes(24).toString('hex');
  db.prepare('UPDATE appareils SET jeton_hash=?, jeton_expire=?, renouv_hash=? WHERE uuid=?').run(sha(secret), Date.now() + JETON_TTL, sha(renouv), uuid);
  return { jeton: uuid + '.' + secret, renouvellement: uuid + '.' + renouv };
}

/* --- routes ------------------------------------------------------------------- */
const routes = {
  'POST /admin/code': (req, b) => {
    adminOk(req);
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    const code = Array.from(crypto.randomBytes(8)).map((x) => alphabet[x % alphabet.length]).join('');
    db.prepare('INSERT INTO codes(code,etiquette,role,expire) VALUES(?,?,?,?)').run(code, b.etiquette || '', b.role || 'fileul', Date.now() + CODE_TTL);
    return { code };
  },
  'POST /appairage': (req, b) => {
    const c = db.prepare('SELECT * FROM codes WHERE code=?').get(String(b.code || ''));
    if (!c) throw new Err(403, 'code_invalide', 'Code d’appairage inconnu.');
    if (c.utilise) throw new Err(403, 'code_utilise', 'Ce code a déjà servi (usage unique).');
    if (Date.now() > c.expire) throw new Err(403, 'code_expire', 'Ce code a expiré.');
    db.prepare('UPDATE codes SET utilise=1 WHERE code=?').run(c.code);
    db.prepare('INSERT INTO appareils(uuid,etiquette,role,etat) VALUES(?,?,?,?)').run(b.uuid, c.etiquette, c.role, 'actif');
    return Object.assign({ epoch: +meta('epoch') }, emettreJetons(b.uuid));
  },
  'POST /renouveler': (req, b) => {
    const m = /^([^.]+)\.(.+)$/.exec(String(b.renouvellement || ''));
    const a = m && db.prepare('SELECT * FROM appareils WHERE uuid=?').get(m[1]);
    if (!a || a.etat === 'revoque') throw new Err(401, 'appareil_revoque', 'Appareil révoqué.');
    if (sha(m[2]) !== a.renouv_hash) {
      db.prepare("UPDATE appareils SET etat='revoque' WHERE uuid=?").run(a.uuid);
      throw new Err(401, 'appareil_revoque', 'Renouvellement rejoué : appareil révoqué par précaution.');
    }
    return emettreJetons(a.uuid);
  },
  'POST /sync/push': (req, b) => {
    const app = auth(req);
    if (b.epoch !== +meta('epoch')) throw new Err(409, 'epoch_inconnue', 'Époque inconnue de la mère.', { epoch_mere: +meta('epoch') });
    const derive = Math.abs(Date.now() - (b.horloge || Date.now()));
    db.prepare('UPDATE appareils SET derive_ms=? WHERE uuid=?').run(derive, app.uuid);
    const resultats = tx(() => (b.ops || []).map((op) => {
      const deja = db.prepare('SELECT json FROM resultats WHERE id=?').get(op.id);
      if (deja) return Object.assign(JSON.parse(deja.json), { rejeu: true });
      const r = traiter(op, app);
      db.prepare('INSERT INTO resultats(id,json) VALUES(?,?)').run(op.id, JSON.stringify(r));
      return r;
    }));
    return { resultats, seq_max: Number(db.prepare('SELECT COALESCE(MAX(seq),0) AS s FROM operations').get().s) };
  },
  'GET /sync/pull': (req, b, q) => {
    const app = auth(req);
    if (+q.epoch !== +meta('epoch')) throw new Err(409, 'epoch_inconnue', 'Époque inconnue de la mère.', { epoch_mere: +meta('epoch') });
    const depuis = +q.depuis || 0; const limite = Math.min(+q.limite || 500, 500);
    const ops = db.prepare('SELECT seq,id,appareil,collection,fiche,type,champs FROM operations WHERE seq>? ORDER BY seq LIMIT ?').all(depuis, limite)
      .map((o) => Object.assign({}, o, { champs: JSON.parse(o.champs) }));
    db.prepare('UPDATE appareils SET dernier_seq=MAX(dernier_seq,?) WHERE uuid=?').run(depuis, app.uuid);
    return { ops, fin: ops.length < limite, epoch: +meta('epoch'), resync: meta('resync') || null };
  },
  'POST /sync/plage': (req, b) => {
    const app = auth(req);
    const taille = Math.max(1, Math.min(+b.taille || 50, 1000));
    return tx(() => {
      const debut = +meta('next_patient'); const fin = debut + taille - 1; setMeta('next_patient', fin + 1);
      db.prepare('INSERT INTO plages(appareil,nom,debut,fin) VALUES(?,?,?,?)').run(app.uuid, b.nom || 'patients', debut, fin);
      return { debut, fin };
    });
  },
  'POST /sync/bail': (req, b) => {
    const app = auth(req);
    return tx(() => {
      const f = lire('stock', b.article);
      if (!f) throw new Err(422, 'fiche_inconnue', 'Article inconnu : ' + b.article);
      const dispo = f.data.qte - reserve(b.article);
      const accorde = Math.max(0, Math.min(+b.qte, dispo));
      db.prepare('INSERT INTO baux(appareil,article,reste) VALUES(?,?,?) ON CONFLICT(appareil,article) DO UPDATE SET reste=reste+excluded.reste').run(app.uuid, b.article, accorde);
      return { accorde, reste: db.prepare('SELECT reste FROM baux WHERE appareil=? AND article=?').get(app.uuid, b.article).reste };
    });
  },
  'POST /sync/ack-resync': (req, b) => { const app = auth(req); db.prepare('INSERT OR IGNORE INTO acks(marque,appareil) VALUES(?,?)').run(String(b.marque), app.uuid); return { ok: true }; },

  'POST /admin/revoquer': (req, b) => { adminOk(req); db.prepare("UPDATE appareils SET etat='revoque' WHERE uuid=?").run(b.uuid); return { ok: true }; },
  'POST /admin/resync': (req) => { adminOk(req); const m = String(Date.now()); setMeta('resync', m); return { marque: m }; },
  'GET /admin/etat': (req) => {
    adminOk(req);
    const marque = meta('resync') || null;
    return {
      epoch: +meta('epoch'),
      seq_max: Number(db.prepare('SELECT COALESCE(MAX(seq),0) AS s FROM operations').get().s),
      appareils: db.prepare('SELECT uuid,etiquette,role,etat,dernier_contact,dernier_seq,derive_ms FROM appareils').all(),
      derives: db.prepare('SELECT uuid FROM appareils WHERE derive_ms>?').all(DERIVE_MAX_MS).map((x) => x.uuid),
      conflits_ouverts: db.prepare("SELECT COUNT(*) AS n FROM conflits WHERE etat='ouvert'").get().n,
      resync: { marque, acks: marque ? db.prepare('SELECT appareil FROM acks WHERE marque=?').all(marque).map((x) => x.appareil) : [] },
      reinit_ouverte: meta('reinit_ouverte') === '1',
      nb_operations: Number(db.prepare('SELECT COUNT(*) AS n FROM operations').get().n),
    };
  },
  'GET /admin/fiche': (req, b, q) => { adminOk(req); return lire(q.collection, q.id) || { absente: true }; },
  'GET /admin/compte': (req, b, q) => { adminOk(req); return { n: db.prepare('SELECT COUNT(*) AS n FROM fiches WHERE collection=? AND archive=0').get(q.collection).n }; },
  'GET /admin/conflits': (req) => { adminOk(req); return db.prepare('SELECT * FROM conflits').all(); },
  'POST /admin/trancher': (req, b) => tx(() => {
    adminOk(req);
    const c = db.prepare('SELECT * FROM conflits WHERE id=?').get(b.id);
    if (!c || c.etat !== 'ouvert') throw new Err(422, 'conflit_inconnu', 'Conflit inexistant ou déjà tranché.');
    if (b.decision === 'b') {
      const f = lire(c.collection, c.fiche);
      const val = JSON.parse(c.b);
      const op = { id: 'tranche-' + c.id + '-' + crypto.randomUUID(), collection: c.collection, fiche: c.fiche, type: 'modifier', champs: { [c.champ]: val }, hlc: Date.now() };
      const seq = journaliser(op, op.champs, 'mere');
      f.data[c.champ] = val; f.fieldseq[c.champ] = seq; ecrire(c.collection, c.fiche, f);
    }
    db.prepare("UPDATE conflits SET etat='tranche', decision=? WHERE id=?").run(b.decision, c.id);
    return { ok: true };
  }),
  'POST /admin/referentiel': (req, b) => tx(() => {
    adminOk(req);
    const op = { id: 'ref-' + crypto.randomUUID(), collection: b.collection, fiche: b.fiche, type: lire(b.collection, b.fiche) ? 'modifier' : 'creer', champs: b.champs, hlc: Date.now(), vu: {} };
    if (op.type === 'modifier') { const f = lire(b.collection, b.fiche); op.vu = Object.fromEntries(Object.keys(b.champs).map((k) => [k, f.fieldseq[k] || 0])); }
    return traiter(op, { uuid: 'mere', role: 'mere' });
  }),
  'POST /admin/stock': (req, b) => tx(() => {
    adminOk(req);
    return traiter({ id: 'stk-' + crypto.randomUUID(), collection: 'stock', fiche: b.article, type: 'creer', champs: { qte: b.qte }, hlc: Date.now() }, { uuid: 'mere', role: 'mere' });
  }),
  'POST /admin/reinit-fenetre': (req, b) => { adminOk(req); setMeta('reinit_ouverte', b.ouvrir ? 1 : 0); return { ouverte: !!b.ouvrir }; },
  'POST /admin/reinitialiser': (req, b) => {
    adminOk(req);
    if (meta('reinit_ouverte') !== '1') throw new Err(403, 'reinit_fermee', 'La réinitialisation est fermée : l’administrateur doit ouvrir la fenêtre.');
    if (b.confirmation !== CLINIQUE) throw new Err(422, 'confirmation_invalide', 'Saisir le nom de la clinique pour confirmer.');
    if (!b.second) throw new Err(422, 'second_profil_requis', 'Un second profil (DAF ou Direction) doit confirmer.');
    const sauvegarde = `${DB === ':memory:' ? 'mere' : DB}.avant-reinit-${Date.now()}.bak`;
    db.exec(`VACUUM INTO '${sauvegarde.replace(/'/g, '')}'`);
    tx(() => {
      const liste = Array.from(ESSENTIELLES).map((c) => `'${c}'`).join(',');
      db.exec(`DELETE FROM operations WHERE collection NOT IN (${liste});
               DELETE FROM fiches WHERE collection NOT IN (${liste});
               DELETE FROM resultats; DELETE FROM conflits; DELETE FROM plages; DELETE FROM baux; DELETE FROM acks;`);
      setMeta('epoch', +meta('epoch') + 1); setMeta('reinit_ouverte', 0); setMeta('next_patient', 1000);
    });
    return { sauvegarde, epoch: +meta('epoch') };
  },
};

const serveur = http.createServer((req, res) => {
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', () => {
    const u = new URL(req.url, 'http://x');
    const q = Object.fromEntries(u.searchParams);
    let body = {};
    try { body = chunks.length ? JSON.parse(Buffer.concat(chunks).toString()) : {}; } catch (e) { /* corps vide */ }
    const h = routes[req.method + ' ' + u.pathname];
    let status = 200; let out;
    try {
      if (!h) throw new Err(404, 'route_inconnue', 'Route inconnue.');
      out = h(req, body, q);
    } catch (e) {
      if (e instanceof Err) { status = e.status; out = e.body; } else { status = 500; out = { code: 'erreur_interne', motif: String(e && e.message) }; }
    }
    const txt = JSON.stringify(out);
    res.writeHead(status, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(txt) });
    res.end(txt);
  });
});
serveur.listen(PORT, '127.0.0.1', () => { if (process.send) process.send({ pret: true, port: serveur.address().port }); });
process.on('SIGTERM', () => process.exit(0));
