'use strict';
/* =============================================================================
 * SIGH-CNT — BANC : le RELAIS EN LIGNE (implémentation de référence du contrat de apps/web)
 * -----------------------------------------------------------------------------
 * OPAQUE par construction : ce fichier n'importe ni `crypto.js` ni aucune clé. Il stocke des enveloppes
 * dont il ne voit que (appareil, sens, rang, taille), des indicateurs EN CLAIR sans nom de patient, et le
 * battement de cœur de la mère. Il ne contacte JAMAIS la mère : c'est elle qui vient le relever.
 * ========================================================================== */
const http = require('node:http');
const nodeCrypto = require('node:crypto');
const { DatabaseSync } = require('node:sqlite');
const arg = (n, d) => { const a = process.argv.find((x) => x.startsWith('--' + n + '=')); return a ? a.split('=').slice(1).join('=') : d; };
const PORT = +arg('port', 0); const DB = arg('db', ':memory:'); const SECRET_MERE = arg('secret-mere', 'secret-mere');
const BANC = arg('banc', '0') === '1'; const SEUIL_BATTEMENT = +arg('seuil-battement', 5 * 60 * 1000);
const sha = (s) => nodeCrypto.createHash('sha256').update(s).digest('hex');
const db = new DatabaseSync(DB);
db.exec(`PRAGMA journal_mode=WAL;
  CREATE TABLE IF NOT EXISTS codes (hash TEXT PRIMARY KEY, utilise INTEGER DEFAULT 0, profil TEXT, fonction TEXT, expire_le INTEGER);
  CREATE TABLE IF NOT EXISTS appareils (uuid TEXT PRIMARY KEY, jeton_hash TEXT, etat TEXT DEFAULT 'actif', profil TEXT, fonction TEXT);
  CREATE TABLE IF NOT EXISTS env (rid INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT UNIQUE, appareil TEXT, dir TEXT, n INTEGER, nonce TEXT, ct TEXT, taille INTEGER, recu INTEGER,
    UNIQUE (appareil, dir, n));
  CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT);`);
const setMeta = (k, v) => db.prepare('INSERT INTO meta(k,v) VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v').run(k, String(v));
const getMeta = (k) => { const r = db.prepare('SELECT v FROM meta WHERE k=?').get(k); return r ? r.v : null; };
class Err extends Error { constructor(s, code, motif) { super(code); this.s = s; this.b = { code, motif }; } }
const mereOk = (req) => req.headers['x-mere'] === SECRET_MERE;
function appareil(req) {
  const m = /^Bearer ([^.]+)\.(.+)$/.exec(req.headers.authorization || '');
  if (!m) throw new Err(401, 'jeton_invalide', 'Jeton absent.');
  const a = db.prepare('SELECT * FROM appareils WHERE uuid=?').get(m[1]);
  if (!a || sha(m[2]) !== a.jeton_hash) throw new Err(401, 'jeton_invalide', 'Jeton invalide.');
  if (a.etat === 'revoque') throw new Err(401, 'appareil_revoque', 'Appareil révoqué.');
  return a;
}
function lister(dir, appareilUuid, depuisN, limite) {
  const rows = db.prepare('SELECT rid,id,appareil,dir,n,nonce,ct FROM env WHERE dir=? AND appareil=? AND n>? ORDER BY n LIMIT ?').all(dir, appareilUuid, depuisN, limite);
  return { env: rows, fin: rows.length < limite };
}
const routes = {
  /* Le profil et la fonction ne sont ici qu'une ÉTIQUETTE d'affichage déclarée par la mère (E1600) : le relais n'en tire aucun droit, la mère relit SA table. */
  'POST /mere/code': (req, b) => { if (!mereOk(req)) throw new Err(403, 'mere_requise'); db.prepare('INSERT OR IGNORE INTO codes(hash,profil,fonction,expire_le) VALUES(?,?,?,?)').run(b.hash, b.profil ? String(b.profil).slice(0, 32) : null, b.fonction ? String(b.fonction).slice(0, 32) : null, Number(b.expire_le) > 0 ? Number(b.expire_le) : null); return { ok: true }; },
  'POST /appairage': (req, b) => {
    const c = db.prepare('SELECT * FROM codes WHERE hash=?').get(sha(String(b.code || '')));
    if (!c) throw new Err(403, 'code_invalide', 'Code inconnu.');
    if (c.utilise) throw new Err(403, 'code_utilise', 'Code déjà utilisé.');
    if (c.expire_le && Date.now() > c.expire_le) throw new Err(403, 'code_expire', 'Ce code a expiré : demander un nouveau code à la console de la mère.');
    if (db.prepare('SELECT 1 FROM appareils WHERE uuid=?').get(String(b.uuid || ''))) throw new Err(409, 'appareil_deja_appaire', 'Cet appareil est déjà appairé : pour changer sa fonction, le révoquer puis l’appairer avec un nouveau code.');
    db.prepare('UPDATE codes SET utilise=1 WHERE hash=?').run(c.hash);
    const secret = nodeCrypto.randomBytes(24).toString('hex');
    db.prepare('INSERT INTO appareils(uuid,jeton_hash,profil,fonction) VALUES(?,?,?,?)').run(b.uuid, sha(secret), c.profil, c.fonction);
    return { jeton: b.uuid + '.' + secret };
  },
  'POST /depot': (req, b) => {
    const e = b.enveloppe; const mere = mereOk(req);
    if (!mere) {
      const a = appareil(req);
      /* ADR-0006 : un appareil dépose dans sa propre boîte vers la mère OU dans son PROPRE journal « pair » (lu par les autres appareils, jamais écrit par eux). */
      /* PRD relais consultable : la COPIE chiffrée de ses fiches (sens « copie »), jamais lue par un appareil. */
      if (!['vers_mere', 'pair', 'copie'].includes(e.dir) || e.appareil !== a.uuid) throw new Err(403, 'depot_interdit', 'Un appareil ne dépose que dans sa propre boîte vers la mère, dans son propre journal pair ou dans sa propre copie.');
    } else if (!(['vers_mobile', 'journal'].includes(e.dir) || (['pair', 'copie'].includes(e.dir) && e.appareil === 'mere'))) throw new Err(403, 'depot_interdit', 'Sens inconnu.'); /* ADR-0006 : la mère de retour publie dans SON journal pair (appareil « mere »), jamais dans celui d'un autre */
    const deja = db.prepare('SELECT rid,appareil,dir,n FROM env WHERE id=?').get(e.id);
    if (deja) return { rid: deja.rid, rejeu: true };
    try {
      const r = db.prepare('INSERT INTO env(id,appareil,dir,n,nonce,ct,taille,recu) VALUES(?,?,?,?,?,?,?,?)').run(e.id, e.appareil, e.dir, e.n, e.nonce, e.ct, e.ct.length, Date.now());
      return { rid: Number(r.lastInsertRowid) };
    } catch (x) { throw new Err(409, 'rang_deja_pris', 'Ce rang est déjà occupé par une autre enveloppe.'); }
  },
  'GET /releve': (req, b, q) => {
    const dir = q.dir; const app = q.appareil; const n = +q.depuis_n || 0; const lim = Math.min(+q.limite || 50, 100);
    if (mereOk(req)) { if (!['vers_mere', 'journal', 'pair'].includes(dir)) throw new Err(403, 'lecture_interdite'); return lister(dir, app, n, lim); }
    const a = appareil(req);
    /* ADR-0006 : le journal « pair » de n'importe quel appareil appairé se lit par tout appareil appairé (même clinique) ; la boîte « vers_mobile » reste privée. */
    if (dir === 'pair') return lister(dir, app, n, lim);
    if (dir !== 'vers_mobile' || app !== a.uuid) throw new Err(403, 'lecture_interdite', 'Un appareil ne lit que SA boîte.');
    return lister(dir, app, n, lim);
  },
  /* PRD relais consultable : la lecture de la copie est celle du SUPERADMIN (panneau), jamais d'un appareil ni de la mère. Le relais de référence la simule par un secret. */
  'GET /superadmin/copie': (req, b, q) => {
    if (req.headers['x-superadmin'] !== 'secret-superadmin') throw new Err(403, 'superadmin_requis');
    return lister('copie', q.appareil, +q.depuis_n || 0, Math.min(+q.limite || 100, 500));
  },
  'GET /superadmin/copie/appareils': (req) => {
    if (req.headers['x-superadmin'] !== 'secret-superadmin') throw new Err(403, 'superadmin_requis');
    return { appareils: db.prepare("SELECT appareil AS uuid, MAX(n) AS max_n FROM env WHERE dir='copie' GROUP BY appareil").all() };
  },
  'GET /mere/appareils': (req) => {
    if (!mereOk(req)) throw new Err(403, 'mere_requise');
    return { appareils: db.prepare("SELECT appareil AS uuid, MAX(n) AS max_n FROM env WHERE dir='vers_mere' GROUP BY appareil").all() };
  },
  /* ADR-0006 : les journaux pair existants (appareil, dernier rang), pour que chaque appareil sache quoi relever. Aucun contenu. */
  'GET /pair/appareils': (req) => { if (!mereOk(req)) appareil(req); return { appareils: db.prepare("SELECT appareil AS uuid, MAX(n) AS max_n FROM env WHERE dir='pair' GROUP BY appareil").all() }; },
  'GET /compteur': (req, b, q) => { const a = appareil(req); return { max_n: db.prepare("SELECT COALESCE(MAX(n),0) AS m FROM env WHERE dir='vers_mobile' AND appareil=?").get(a.uuid).m }; },
  'POST /mere/revoquer': (req, b) => { if (!mereOk(req)) throw new Err(403, 'mere_requise'); db.prepare("UPDATE appareils SET etat='revoque' WHERE uuid=?").run(b.uuid); return { ok: true }; },
  'POST /mere/battement': (req, b) => { if (!mereOk(req)) throw new Err(403, 'mere_requise'); setMeta('battement', Date.now()); return { ok: true }; },
  'POST /mere/indicateurs': (req, b) => { if (!mereOk(req)) throw new Err(403, 'mere_requise'); setMeta('indicateurs', JSON.stringify(b.indicateurs || {})); return { ok: true }; },
  'GET /admin/etat': (req) => {
    if (!mereOk(req)) throw new Err(403, 'mere_requise');
    const bt = getMeta('battement'); const age = bt ? Date.now() - +bt : null;
    return { age_battement_ms: age, alerte_battement: age === null ? true : age > SEUIL_BATTEMENT,
      indicateurs: JSON.parse(getMeta('indicateurs') || '{}'), nb_enveloppes: db.prepare('SELECT COUNT(*) AS n FROM env').get().n };
  },
};
if (BANC) { /* crochets réservés au banc : altérer ou retirer une enveloppe, vider le relais pour inspection */
  routes['POST /banc/alterer'] = (req, b) => { const r = db.prepare('SELECT ct FROM env WHERE id=?').get(b.id); const x = Buffer.from(r.ct, 'base64'); x[0] ^= 1; db.prepare('UPDATE env SET ct=? WHERE id=?').run(x.toString('base64'), b.id); return { ok: true }; };
  routes['POST /banc/retirer'] = (req, b) => { db.prepare('DELETE FROM env WHERE id=?').run(b.id); return { ok: true }; };
  routes['GET /banc/tout'] = () => ({ lignes: db.prepare('SELECT * FROM env').all(), codes: db.prepare('SELECT * FROM codes').all(), appareils: db.prepare('SELECT uuid FROM appareils').all(), meta: db.prepare('SELECT * FROM meta').all() });
  routes['GET /banc/ids'] = (req, b, q) => ({ ids: db.prepare('SELECT id,appareil,dir,n FROM env WHERE dir=? ORDER BY rid').all(q.dir) });
}
http.createServer((req, res) => {
  const ch = []; req.on('data', (c) => ch.push(c));
  req.on('end', () => {
    const u = new URL(req.url, 'http://x'); const q = Object.fromEntries(u.searchParams);
    let b = {}; try { b = ch.length ? JSON.parse(Buffer.concat(ch).toString()) : {}; } catch (e) { /* vide */ }
    let st = 200; let out;
    try { const h = routes[req.method + ' ' + u.pathname]; if (!h) throw new Err(404, 'route_inconnue'); out = h(req, b, q); }
    catch (e) { if (e instanceof Err) { st = e.s; out = e.b; } else { st = 500; out = { code: 'erreur_interne', motif: String(e.message) }; } }
    const t = JSON.stringify(out); res.writeHead(st, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(t) }); res.end(t);
  });
}).listen(PORT, '127.0.0.1', function () { if (process.send) process.send({ pret: true, port: this.address().port }); });
