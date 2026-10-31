'use strict';
/* =============================================================================
 * SIGH-CNT — BANC : le MOBILE (implémentation de référence du profil « réception de secours » / « soignant »)
 * -----------------------------------------------------------------------------
 * Il ne connaît QUE le relais : pas l'adresse de la mère, jamais le réseau local. Tout ce qu'il envoie et
 * reçoit est chiffré de bout en bout (clé de clinique reçue à l'appairage). Base locale, file persistée,
 * rang d'envoi contigu, lot expirant, effacement à la révocation (avec export de ce qui n'est pas parti).
 *
 * Lancement : node mobile.js --port=9301 --relais=http://127.0.0.1:9200 --db=m1.sqlite --nom=M1
 * ========================================================================== */
const http = require('node:http');
const fs = require('node:fs');
const crypto = require('node:crypto');
const { DatabaseSync } = require('node:sqlite');
const { chiffrer, dechiffrer } = require('./crypto');

const arg = (n, d) => { const a = process.argv.find((x) => x.startsWith('--' + n + '=')); return a ? a.split('=').slice(1).join('=') : d; };
const PORT = +arg('port', 0); const RELAIS = arg('relais', ''); const DB = arg('db', ':memory:'); const NOM = arg('nom', 'mobile');
const INTERVALLE = +arg('intervalle', 150);

const db = new DatabaseSync(DB);
db.exec(`PRAGMA journal_mode=WAL;
  CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT);
  CREATE TABLE IF NOT EXISTS confirme (collection TEXT, id TEXT, data TEXT, fieldseq TEXT, archive INTEGER, dulot INTEGER DEFAULT 0, PRIMARY KEY (collection, id));
  CREATE TABLE IF NOT EXISTS file (ordre INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT UNIQUE, op TEXT, etat TEXT, resultat TEXT);
  CREATE TABLE IF NOT EXISTS envois (n INTEGER PRIMARY KEY, enveloppe TEXT, depose INTEGER DEFAULT 0, ops TEXT);`);
const meta = (k, d) => { const r = db.prepare('SELECT v FROM meta WHERE k=?').get(k); return r ? r.v : d; };
const setMeta = (k, v) => db.prepare('INSERT INTO meta(k,v) VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v').run(k, String(v));
const uuid7 = () => { const b = crypto.randomBytes(16); const t = BigInt(Date.now()); for (let i = 0; i < 6; i++) b[i] = Number((t >> BigInt(8 * (5 - i))) & 255n); b[6] = (b[6] & 0x0f) | 0x70; b[8] = (b[8] & 0x3f) | 0x80; const h = b.toString('hex'); return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`; };
if (meta('uuid') === undefined) setMeta('uuid', uuid7());
const UUID = meta('uuid');
const cle = () => Buffer.from(meta('cle'), 'base64');
const etat = { hors_ligne: false, tentatives: 0, suspendu: meta('suspendu') === '1', exports: [], alertes: [] };

function appliquer(s, op, seq) {
  const garde = (k) => !seq || (s.fieldseq[k] || 0) < seq; /* jamais de régression : un op plus ancien que l'état ne s'applique pas */
  if (op.type === 'creer' || op.type === 'modifier') { for (const [k, v] of Object.entries(op.champs)) if (garde(k)) { s.data[k] = v; if (seq) s.fieldseq[k] = seq; } }
  else if (op.type === 'archiver') s.archive = true; else if (op.type === 'restaurer') s.archive = false;
  else if (op.type === 'sortie') { if (garde('qte')) { s.data.qte = (s.data.qte || 0) - (+op.champs.qte); if (seq) s.fieldseq.qte = seq; } }
  return s;
}
const lireConfirme = (c, id) => { const r = db.prepare('SELECT * FROM confirme WHERE collection=? AND id=?').get(c, id); return r ? { data: JSON.parse(r.data), fieldseq: JSON.parse(r.fieldseq), archive: !!r.archive, dulot: !!r.dulot, existe: true } : { data: {}, fieldseq: {}, archive: false, dulot: false, existe: false }; };
const ecrireConfirme = (c, id, s) => db.prepare(`INSERT INTO confirme(collection,id,data,fieldseq,archive,dulot) VALUES(?,?,?,?,?,?)
  ON CONFLICT(collection,id) DO UPDATE SET data=excluded.data, fieldseq=excluded.fieldseq, archive=excluded.archive, dulot=excluded.dulot`).run(c, id, JSON.stringify(s.data), JSON.stringify(s.fieldseq), s.archive ? 1 : 0, s.dulot ? 1 : 0);
function enVol() {
  return db.prepare(`SELECT op, resultat, etat FROM file WHERE etat IN ('en_attente','envoyee') OR (etat='acceptee' AND CAST(json_extract(resultat,'$.seq') AS INTEGER) > ?) ORDER BY ordre`)
    .all(+meta('curseur_seq', 0)).map((r) => { const op = JSON.parse(r.op); if (r.etat === 'acceptee') { const res = JSON.parse(r.resultat); if (res.numero) op.champs.code = res.numero; } return op; });
}
function vue(c, id) { const s = lireConfirme(c, id); for (const op of enVol()) if (op.collection === c && op.fiche === id) { appliquer(s, op, 0); s.existe = true; } return s; }
function liste(c) {
  const ids = new Set(db.prepare('SELECT id FROM confirme WHERE collection=?').all(c).map((r) => r.id));
  for (const op of enVol()) if (op.collection === c) ids.add(op.fiche);
  return Array.from(ids).map((id) => Object.assign({ id }, vue(c, id))).filter((x) => x.existe);
}
function prochainNumero() {
  const d = +meta('plage_prochain', 0); const f = +meta('plage_fin', -1);
  if (d && d <= f) { setMeta('plage_prochain', d + 1); return `CNT/${d}/26`; }
  return 'PROV-' + crypto.randomBytes(4).toString('hex');
}
function ecrire(cmd) {
  const op = { id: uuid7(), appareil: UUID, epoch: +meta('epoch', 1), hlc: Date.now(), collection: cmd.collection, fiche: cmd.fiche || uuid7(), type: cmd.type, champs: Object.assign({}, cmd.champs || {}), vu: {} };
  if (op.type === 'modifier') { const b = lireConfirme(op.collection, op.fiche); for (const k of Object.keys(op.champs)) op.vu[k] = b.fieldseq[k] || 0; }
  if (op.type === 'creer' && op.collection === 'patients' && !op.champs.code) op.champs.code = prochainNumero();
  db.prepare("INSERT INTO file(id,op,etat) VALUES(?,?,'en_attente')").run(op.id, JSON.stringify(op));
  return { id: op.id, fiche: op.fiche, champs: op.champs };
}

/* --- relais ---------------------------------------------------------------------- */
async function rel(methode, chemin, corps) {
  const h = { 'Content-Type': 'application/json' }; if (meta('jeton')) h.Authorization = 'Bearer ' + meta('jeton');
  const r = await fetch(RELAIS + chemin, { method: methode, headers: h, body: corps ? JSON.stringify(corps) : undefined, signal: AbortSignal.timeout(1500) });
  const j = await r.json();
  if (r.status === 401 && j.code === 'appareil_revoque') { revoque(); throw Object.assign(new Error('suspendu'), { code: 'suspendu' }); }
  if (!r.ok) throw Object.assign(new Error(j.code || 'http_' + r.status), { code: j.code, status: r.status });
  return j;
}
/** Révocation : on exporte ce qui n'est pas parti, puis on EFFACE les données de santé de l'appareil (spec §11). */
function revoque() {
  const nonEnvoyees = db.prepare("SELECT op FROM file WHERE etat IN ('en_attente','envoyee')").all().map((r) => JSON.parse(r.op));
  if (nonEnvoyees.length) { const f = `${DB === ':memory:' ? NOM : DB}.export-${Date.now()}.json`; fs.writeFileSync(f, JSON.stringify({ operations: nonEnvoyees }, null, 1)); etat.exports.push(f); }
  db.exec('DELETE FROM confirme; DELETE FROM file; DELETE FROM envois;');
  setMeta('suspendu', 1); etat.suspendu = true;
}
function purgerLotExpire() {
  const exp = +meta('lot_expire', 0);
  if (!exp || Date.now() < exp) return;
  const aSuppr = db.prepare('SELECT collection,id FROM confirme WHERE dulot=1').all();
  const enAttente = new Set(db.prepare("SELECT op FROM file WHERE etat IN ('en_attente','envoyee')").all().map((r) => { const o = JSON.parse(r.op); return o.collection + '|' + o.fiche; }));
  for (const f of aSuppr) if (!enAttente.has(f.collection + '|' + f.id)) db.prepare('DELETE FROM confirme WHERE collection=? AND id=?').run(f.collection, f.id);
  setMeta('lot_expire', 0); etat.lot_purge_le = Date.now();
}
function recevoir(p) {
  if (p.type === 'bienvenue') { setMeta('epoch', p.epoch); setMeta('plage_prochain', p.plage.debut); setMeta('plage_fin', p.plage.fin); setMeta('bienvenu', 1); }
  else if (p.type === 'lot') {
    setMeta('lot_expire', p.expire);
    for (const f of p.fiches) ecrireConfirme(f.collection, f.id, { data: f.data, fieldseq: f.fieldseq, archive: f.archive, dulot: true });
  } else if (p.type === 'ops') {
    for (const op of p.ops) { const s = lireConfirme(op.collection, op.fiche); appliquer(s, op, op.seq); ecrireConfirme(op.collection, op.fiche, s); setMeta('curseur_seq', Math.max(+meta('curseur_seq', 0), op.seq)); }
  } else if (p.type === 'accuse') {
    if (p.erreur === 'epoch_inconnue') { revoque(); setMeta('suspendu', 0); etat.suspendu = false; setMeta('epoch', p.epoch_mere); return; }
    for (const r of p.resultats) db.prepare('UPDATE file SET etat=?, resultat=? WHERE id=?').run(r.statut, JSON.stringify(r), r.id);
    db.prepare("UPDATE envois SET depose=2 WHERE depose=1").run();
  }
}
async function cycle() {
  if (etat.suspendu || !meta('jeton')) return;
  try {
    purgerLotExpire();
    /* 1. ma boîte */
    const { max_n } = await rel('GET', '/compteur');
    let dernier = +meta('curseur_n', 0);
    while (max_n > dernier) {
      const { env } = await rel('GET', `/releve?dir=vers_mobile&appareil=${UUID}&depuis_n=${dernier}&limite=50`);
      if (!env.length) break;
      for (const e of env) {
        if (e.n !== dernier + 1) { etat.alertes.push({ type: 'trou', attendu: dernier + 1, recu: e.n }); return; }
        let p; try { p = dechiffrer(cle(), e); } catch (x) { etat.alertes.push({ type: 'authentification', n: e.n }); return; }
        db.exec('BEGIN'); try { recevoir(p); setMeta('curseur_n', e.n); db.exec('COMMIT'); } catch (x) { db.exec('ROLLBACK'); throw x; }
        dernier = e.n;
      }
    }
    /* 2. envoyer : un rang n'est alloué qu'UNE fois et persisté avant le dépôt ; il se redépose à l'identique */
    if (!db.prepare('SELECT 1 FROM envois WHERE depose=0').get()) {
      const lot = db.prepare("SELECT id,op FROM file WHERE etat='en_attente' ORDER BY ordre LIMIT 100").all();
      if (lot.length) {
        const n = +meta('sortie_n', 0) + 1; setMeta('sortie_n', n);
        const ops = lot.map((r) => JSON.parse(r.op));
        const env = chiffrer(cle(), { type: 'push', epoch: +meta('epoch', 1), ops }, { id: `${UUID}-${n}`, appareil: UUID, dir: 'vers_mere', n });
        db.prepare('INSERT INTO envois(n,enveloppe,ops) VALUES(?,?,?)').run(n, JSON.stringify(env), JSON.stringify(lot.map((r) => r.id)));
      }
    }
    for (const e of db.prepare('SELECT * FROM envois WHERE depose=0 ORDER BY n').all()) {
      await rel('POST', '/depot', { enveloppe: JSON.parse(e.enveloppe) });
      db.prepare('UPDATE envois SET depose=1 WHERE n=?').run(e.n);
      for (const id of JSON.parse(e.ops)) db.prepare("UPDATE file SET etat='envoyee' WHERE id=? AND etat='en_attente'").run(id);
    }
    etat.hors_ligne = false; etat.tentatives = 0;
  } catch (e) { if (e.code === 'suspendu') return; etat.hors_ligne = true; etat.tentatives++; }
}
(async function boucle() { for (;;) { await cycle(); await new Promise((r) => setTimeout(r, Math.min(INTERVALLE * 2 ** Math.min(etat.tentatives, 3), 1000))); } })();

/* --- commande ---------------------------------------------------------------------- */
const commandes = {
  'POST /appairer': async (b) => {
    setMeta('cle', b.cle); setMeta('profil', b.profil || 'soignant');
    const r = await fetch(RELAIS + '/appairage', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ code: b.code, uuid: UUID }) });
    const j = await r.json(); if (!r.ok) return [r.status, j];
    setMeta('jeton', j.jeton); setMeta('epoch', 1); setMeta('suspendu', 0); etat.suspendu = false;
    const n = 1; setMeta('sortie_n', 1);
    const env = chiffrer(cle(), { type: 'hello', code: b.code, profil: meta('profil'), plateforme: 'banc' }, { id: `${UUID}-1`, appareil: UUID, dir: 'vers_mere', n });
    db.prepare('INSERT INTO envois(n,enveloppe,ops) VALUES(?,?,?)').run(n, JSON.stringify(env), '[]');
    return [200, { uuid: UUID }];
  },
  'GET /secret': () => [200, { jeton: meta('jeton') }],
  'POST /ecrire': (b) => [200, ecrire(b)],
  'GET /vue': (b, q) => [200, vue(q.collection, q.id)],
  'GET /liste': (b, q) => [200, liste(q.collection)],
  'GET /etat': () => [200, Object.assign({}, etat, {
    uuid: UUID, bienvenu: meta('bienvenu') === '1', epoch: +meta('epoch', 1), curseur_n: +meta('curseur_n', 0), lot_expire: +meta('lot_expire', 0),
    en_attente: db.prepare("SELECT COUNT(*) AS n FROM file WHERE etat IN ('en_attente','envoyee')").get().n,
    a_traiter: db.prepare("SELECT resultat FROM file WHERE etat='refusee'").all().map((r) => JSON.parse(r.resultat)),
    resultats: db.prepare('SELECT id,etat,resultat FROM file ORDER BY ordre').all().map((r) => Object.assign({ id: r.id, etat: r.etat }, r.resultat ? JSON.parse(r.resultat) : {})),
    plage: { prochain: +meta('plage_prochain', 0), fin: +meta('plage_fin', -1) },
  })],
};
http.createServer((req, res) => {
  const ch = []; req.on('data', (c) => ch.push(c));
  req.on('end', async () => {
    const u = new URL(req.url, 'http://x'); const q = Object.fromEntries(u.searchParams);
    let b = {}; try { b = ch.length ? JSON.parse(Buffer.concat(ch).toString()) : {}; } catch (e) { /* vide */ }
    const h = commandes[req.method + ' ' + u.pathname]; let st = 404; let out = { code: 'commande_inconnue' };
    if (h) { try { [st, out] = await h(b, q); } catch (e) { st = 500; out = { code: e.code || 'erreur', motif: e.message }; } }
    const t = JSON.stringify(out); res.writeHead(st, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(t) }); res.end(t);
  });
}).listen(PORT, '127.0.0.1', function () { if (process.send) process.send({ pret: true, port: this.address().port }); });
