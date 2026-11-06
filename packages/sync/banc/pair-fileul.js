'use strict';
/* =============================================================================
 * SIGH-CNT, BANC : UN FILEUL EN MODE PAIR (ADR-0006)
 * -----------------------------------------------------------------------------
 * Un poste qui n'a PAS besoin de la mère : il publie ses opérations (chiffrées de bout en bout) dans SON journal au relais, relève les journaux des autres
 * appareils, et calcule son état par la règle de fusion de `pair.js` (fonction pure de l'ensemble des opérations). Tout est persisté : un SIGKILL à n'importe
 * quel moment ne perd rien (file de publication à rang contigu, curseurs, opérations reçues). Le relais ne voit que des enveloppes.
 * ========================================================================== */
const http = require('node:http');
const nodeCrypto = require('node:crypto');
const { DatabaseSync } = require('node:sqlite');
const { chiffrer, dechiffrer } = require('./crypto');
const { Horloge, etat, droitsBanc } = require('./pair');

const arg = (n, d) => { const a = process.argv.find((x) => x.startsWith('--' + n + '=')); return a ? a.split('=').slice(1).join('=') : d; };
const PORT = +arg('port', 0); const RELAIS = arg('relais', ''); const DB = arg('db', ':memory:'); const NOM = arg('nom', 'poste');
const COPIE = new Set(arg('copie', '').split(',').filter(Boolean));
const CLE = Buffer.from(arg('cle', ''), 'hex'); const INTERVALLE = +arg('intervalle-ms', 120); const DECALAGE = +arg('horloge-decalage-ms', 0);

const db = new DatabaseSync(DB);
db.exec(`PRAGMA journal_mode=WAL;
  CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT);
  CREATE TABLE IF NOT EXISTS ops (id TEXT PRIMARY KEY, appareil TEXT, json TEXT);
  CREATE TABLE IF NOT EXISTS sortie (n INTEGER PRIMARY KEY, id TEXT, depose INTEGER DEFAULT 0);
  CREATE TABLE IF NOT EXISTS curseurs (appareil TEXT PRIMARY KEY, n INTEGER);
  CREATE TABLE IF NOT EXISTS foi (id TEXT PRIMARY KEY, seq INTEGER);
  CREATE TABLE IF NOT EXISTS copie_sortie (n INTEGER PRIMARY KEY, id TEXT, charge TEXT, depose INTEGER DEFAULT 0);
  CREATE TABLE IF NOT EXISTS copie_etat (cle TEXT PRIMARY KEY, empreinte TEXT);
  CREATE TABLE IF NOT EXISTS anomalies (k INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT, detail TEXT);`);
const meta = (k, d = null) => { const r = db.prepare('SELECT v FROM meta WHERE k=?').get(k); return r ? r.v : d; };
const setMeta = (k, v) => db.prepare('INSERT INTO meta(k,v) VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v').run(k, String(v));

const horloge = new Horloge(() => Date.now() + DECALAGE);
horloge.dernier = +meta('hlc', 0);
let horsLigne = false; let cycles = 0;

const entetes = () => ({ 'Content-Type': 'application/json', Authorization: 'Bearer ' + meta('jeton') });
async function relais(methode, chemin, corps) {
  const r = await fetch(RELAIS + chemin, { method: methode, headers: entetes(), body: corps ? JSON.stringify(corps) : undefined, signal: AbortSignal.timeout(3000) });
  let j = {}; try { j = await r.json(); } catch (e) { /* vide */ }
  return { status: r.status, json: j };
}
/* Le `seq` qui FAIT FOI est attribué par la mère à son retour : il arrive dans son journal pair (enveloppe « foi ») et lève le statut provisoire. */
const toutesOps = () => {
  const foi = new Map(db.prepare('SELECT id,seq FROM foi').all().map((r) => [r.id, Number(r.seq)]));
  return db.prepare('SELECT json FROM ops').all().map((r) => { const o = JSON.parse(r.json); return foi.has(o.id) && o.seq == null ? Object.assign(o, { seq: foi.get(o.id) }) : o; });
};
const anomalie = (type, detail) => db.prepare('INSERT INTO anomalies(type,detail) VALUES(?,?)').run(type, JSON.stringify(detail));

/* 1. publier, dans l'ordre des rangs, ce qui n'est pas encore déposé (un dépôt rejoué est idempotent au relais) */
async function publier() {
  const uuid = meta('uuid'); if (!uuid) return;
  for (const l of db.prepare('SELECT n,id FROM sortie WHERE depose=0 ORDER BY n').all()) {
    const op = JSON.parse(db.prepare('SELECT json FROM ops WHERE id=?').get(l.id).json);
    const env = chiffrer(CLE, op, { id: `${uuid}-pair-${l.n}`, appareil: uuid, dir: 'pair', n: l.n });
    const r = await relais('POST', '/depot', { enveloppe: env });
    if (r.status !== 200) { if (r.status === 401) setMeta('revoque', 1); return; }
    db.prepare('UPDATE sortie SET depose=1 WHERE n=?').run(l.n);
  }
}

/* 2. relever les journaux des autres : rangs contigus, authentification GCM, idempotence */
async function relever() {
  const uuid = meta('uuid'); if (!uuid) return;
  const liste = await relais('GET', '/pair/appareils');
  if (liste.status !== 200) return;
  for (const a of liste.json.appareils.filter((x) => x.uuid !== uuid)) {
    for (;;) {
      const depuis = (db.prepare('SELECT n FROM curseurs WHERE appareil=?').get(a.uuid) || { n: 0 }).n;
      const r = await relais('GET', `/releve?dir=pair&appareil=${encodeURIComponent(a.uuid)}&depuis_n=${depuis}&limite=50`);
      if (r.status !== 200 || !r.json.env.length) break;
      let attendu = depuis + 1;
      for (const env of r.json.env) {
        if (env.n !== attendu) { anomalie('trou', { appareil: a.uuid, attendu, recu: env.n }); return; }
        let charge;
        try { charge = dechiffrer(CLE, env); } catch (e) { anomalie('enveloppe_alteree', { appareil: a.uuid, n: env.n }); return; }
        // le journal d'un pair porte des opérations ; celui de la MÈRE porte aussi ses décisions (`op`) et le seq qui fait foi (`foi`)
        const op = charge.type === 'op' ? charge.op : charge.type === 'foi' ? null : charge;
        db.exec('BEGIN');
        if (charge.type === 'foi') for (const [id, seq] of charge.liste) db.prepare('INSERT OR REPLACE INTO foi(id,seq) VALUES(?,?)').run(id, seq);
        if (op) db.prepare('INSERT OR IGNORE INTO ops(id,appareil,json) VALUES(?,?,?)').run(op.id, op.appareil, JSON.stringify(op));
        db.prepare('INSERT INTO curseurs(appareil,n) VALUES(?,?) ON CONFLICT(appareil) DO UPDATE SET n=excluded.n').run(a.uuid, env.n);
        db.exec('COMMIT');
        if (op) { horloge.recevoir(op.hlc); setMeta('hlc', horloge.dernier); }
        attendu += 1;
      }
      if (r.json.fin) break;
    }
  }
}

/* 3. COPIE (PRD relais consultable) : une enveloppe par fiche nouvelle ou changée, sens « copie » de CE poste, rang contigu, charge persistée avant dépôt. */
const tx = (f) => { db.exec('BEGIN'); try { f(); db.exec('COMMIT'); } catch (e) { db.exec('ROLLBACK'); throw e; } };
function preparerCopie() {
  const uuid = meta('uuid'); if (!uuid || !COPIE.size) return;
  const fiches = etat(toutesOps(), droitsBanc).fiches;
  for (const [cle, f] of Object.entries(fiches)) {
    const i = cle.indexOf('/'); const col = cle.slice(0, i); if (!COPIE.has(col)) continue;
    const texte = JSON.stringify({ collection: col, fiche: cle.slice(i + 1), data: f.data, archive: f.archive === true });
    const deja = db.prepare('SELECT empreinte FROM copie_etat WHERE cle=?').get(cle);
    if (deja && deja.empreinte === texte) continue;
    tx(() => {
      const n = db.prepare('SELECT COALESCE(MAX(n),0) AS m FROM copie_sortie').get().m + 1;
      db.prepare('INSERT INTO copie_sortie(n,id,charge) VALUES(?,?,?)').run(n, `${uuid}-copie-${n}`, texte);
      db.prepare('INSERT INTO copie_etat(cle,empreinte) VALUES(?,?) ON CONFLICT(cle) DO UPDATE SET empreinte=excluded.empreinte').run(cle, texte);
    });
  }
}
async function deposerCopie() {
  const uuid = meta('uuid'); if (!uuid) return;
  for (const l of db.prepare('SELECT n,id,charge FROM copie_sortie WHERE depose=0 ORDER BY n').all()) {
    const env = chiffrer(CLE, JSON.parse(l.charge), { id: l.id, appareil: uuid, dir: 'copie', n: l.n });
    const r = await relais('POST', '/depot', { enveloppe: env });
    if (r.status !== 200) return;
    db.prepare('UPDATE copie_sortie SET depose=1 WHERE n=?').run(l.n);
  }
}

let enCours = false;
async function cycle() {
  if (enCours) return; enCours = true;
  try { await publier(); await relever(); preparerCopie(); await deposerCopie(); horsLigne = false; } catch (e) { horsLigne = true; } finally { cycles += 1; enCours = false; }
}
setInterval(cycle, INTERVALLE);

/* --- commandes (le banc pilote le poste comme le ferait un utilisateur) ---------------------------------------- */
function emettre(c) {
  const uuid = meta('uuid'); if (!uuid) throw Object.assign(new Error('poste non appairé'), { s: 409 });
  const op = { id: nodeCrypto.randomUUID(), appareil: uuid, hlc: horloge.emettre(), collection: c.collection, fiche: c.fiche, type: c.type, champs: c.champs || {}, vu: c.vu, role: c.role };
  if (!droitsBanc(op)) throw Object.assign(new Error(`droit refusé : ${c.role} ne peut pas ${c.type} sur ${c.collection}`), { s: 403 });
  const n = (db.prepare('SELECT COALESCE(MAX(n),0) AS m FROM sortie').get().m) + 1;
  db.exec('BEGIN');
  db.prepare('INSERT INTO ops(id,appareil,json) VALUES(?,?,?)').run(op.id, uuid, JSON.stringify(op));
  db.prepare('INSERT INTO sortie(n,id) VALUES(?,?)').run(n, op.id);
  db.exec('COMMIT');
  setMeta('hlc', horloge.dernier);
  return op;
}
const serialiser = (e) => ({ fiches: e.fiches, stock: e.stock, besoins: e.besoins, conflits: e.conflits, tranches: e.tranches, refusees: e.refusees, provisoire: [...e.provisoire].sort() });
const routes = {
  'POST /appairer': async (b) => {
    const uuid = nodeCrypto.randomUUID();
    const r = await fetch(RELAIS + '/appairage', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ code: b.code, uuid }) });
    const j = await r.json(); if (r.status !== 200) return [r.status, j];
    setMeta('uuid', uuid); setMeta('jeton', j.jeton); return [200, { uuid }];
  },
  'POST /emettre': (b) => { const op = emettre(b); return [200, { id: op.id, hlc: op.hlc }]; },
  'GET /etat': () => {
    const uuid = meta('uuid');
    return [200, { uuid, nom: NOM, ops: toutesOps().length, en_attente: db.prepare('SELECT COUNT(*) AS n FROM sortie WHERE depose=0').get().n, copie_en_attente: db.prepare('SELECT COUNT(*) AS n FROM copie_sortie WHERE depose=0').get().n, copie_deposee: db.prepare('SELECT COUNT(*) AS n FROM copie_sortie WHERE depose=1').get().n, curseurs: Object.fromEntries(db.prepare('SELECT appareil,n FROM curseurs').all().map((r) => [r.appareil, r.n])),
      anomalies: db.prepare('SELECT type,detail FROM anomalies').all(), derive: horloge.derive, hors_ligne: horsLigne, cycles, revoque: meta('revoque') === '1' }];
  },
  'GET /fiches': () => [200, serialiser(etat(toutesOps(), droitsBanc))],
};
http.createServer((req, res) => {
  const ch = []; req.on('data', (c) => ch.push(c));
  req.on('end', async () => {
    const u = new URL(req.url, 'http://x'); let b = {}; try { b = ch.length ? JSON.parse(Buffer.concat(ch).toString()) : {}; } catch (e) { /* vide */ }
    let st = 200; let out;
    try { const h = routes[req.method + ' ' + u.pathname]; if (!h) { st = 404; out = { code: 'route_inconnue' }; } else [st, out] = await h(b); }
    catch (e) { st = e.s || 500; out = { code: 'erreur', motif: String(e.message) }; }
    const t = JSON.stringify(out); res.writeHead(st, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(t) }); res.end(t);
  });
}).listen(PORT, '127.0.0.1', function () { if (process.send) process.send({ pret: true, port: this.address().port }); });
