'use strict';
/* =============================================================================
 * SIGH-CNT — BANC DE SYNCHRONISATION : le POSTE FILEUL (implémentation de référence)
 * -----------------------------------------------------------------------------
 * Base locale (SQLite), file d'envoi persistée, curseur, cycle « on reçoit toujours
 * avant d'envoyer », reprise après coupure, suspension à la révocation, traitement
 * de l'époque. Une petite API de COMMANDE (HTTP local) permet au banc de piloter le
 * poste comme le ferait un utilisateur. Aucune dépendance.
 *
 * Lancement : node fileul.js --port=9101 --mere=http://127.0.0.1:9000 --db=f1.sqlite --nom=F1
 * ========================================================================== */
const http = require('node:http');
const fs = require('node:fs');
const crypto = require('node:crypto');
const { DatabaseSync } = require('node:sqlite');

const arg = (n, d) => { const a = process.argv.find((x) => x.startsWith('--' + n + '=')); return a ? a.split('=').slice(1).join('=') : d; };
const PORT = +arg('port', 0);
const MERE = arg('mere', 'http://127.0.0.1:9000');
const DB = arg('db', ':memory:');
const NOM = arg('nom', 'poste');
const DECALAGE = +arg('horloge-decalage-ms', 0);
const INTERVALLE = +arg('intervalle', 150);
const maintenant = () => Date.now() + DECALAGE;

const db = new DatabaseSync(DB);
db.exec(`
  PRAGMA journal_mode = WAL;
  CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT);
  CREATE TABLE IF NOT EXISTS confirme (collection TEXT, id TEXT, data TEXT, fieldseq TEXT, archive INTEGER, PRIMARY KEY (collection, id));
  CREATE TABLE IF NOT EXISTS file (ordre INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT UNIQUE, op TEXT, etat TEXT, resultat TEXT);
  CREATE TABLE IF NOT EXISTS plage (nom TEXT PRIMARY KEY, prochain INTEGER, fin INTEGER);
  CREATE TABLE IF NOT EXISTS baux (article TEXT PRIMARY KEY, reste INTEGER);
`);
const meta = (k, d) => { const r = db.prepare('SELECT v FROM meta WHERE k=?').get(k); return r ? r.v : d; };
const setMeta = (k, v) => db.prepare('INSERT INTO meta(k,v) VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v').run(k, String(v));
if (meta('uuid') === undefined) setMeta('uuid', uuid7());
if (meta('curseur') === undefined) setMeta('curseur', 0);
if (meta('epoch') === undefined) setMeta('epoch', 1);
const tx = (fn) => { db.exec('BEGIN IMMEDIATE'); try { const r = fn(); db.exec('COMMIT'); return r; } catch (e) { db.exec('ROLLBACK'); throw e; } };

function uuid7() {
  const b = crypto.randomBytes(16); const t = BigInt(Date.now());
  for (let i = 0; i < 6; i++) b[i] = Number((t >> BigInt(8 * (5 - i))) & 255n);
  b[6] = (b[6] & 0x0f) | 0x70; b[8] = (b[8] & 0x3f) | 0x80;
  const h = b.toString('hex');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

const etat = { hors_ligne: false, tentatives: 0, suspendu: meta('suspendu') === '1', cycles: 0, derniere_erreur: null, exports: [] };

/* --- application d'une opération sur un état {data, fieldseq, archive} ------ */
function appliquer(s, op, seq) {
  if (op.type === 'creer' || op.type === 'modifier') {
    Object.assign(s.data, op.champs);
    if (seq) for (const k of Object.keys(op.champs)) s.fieldseq[k] = seq;
  } else if (op.type === 'archiver') s.archive = true;
  else if (op.type === 'restaurer') s.archive = false;
  else if (op.type === 'sortie') { s.data.qte = (s.data.qte || 0) - (+op.champs.qte); if (seq) s.fieldseq.qte = seq; }
  return s;
}
function lireConfirme(c, id) {
  const r = db.prepare('SELECT * FROM confirme WHERE collection=? AND id=?').get(c, id);
  return r ? { data: JSON.parse(r.data), fieldseq: JSON.parse(r.fieldseq), archive: !!r.archive, existe: true } : { data: {}, fieldseq: {}, archive: false, existe: false };
}
function ecrireConfirme(c, id, s) {
  db.prepare(`INSERT INTO confirme(collection,id,data,fieldseq,archive) VALUES(?,?,?,?,?)
    ON CONFLICT(collection,id) DO UPDATE SET data=excluded.data, fieldseq=excluded.fieldseq, archive=excluded.archive`)
    .run(c, id, JSON.stringify(s.data), JSON.stringify(s.fieldseq), s.archive ? 1 : 0);
}
/** La vue de l'utilisateur : le confirmé, avec par-dessus ses opérations pas encore acceptées. */
/** Les opérations encore « en l'air » : en attente d'envoi, OU acceptées par la mère mais pas encore
 *  revenues dans le flux (seq > curseur). Sans ce second cas, un dossier qu'on vient de créer
 *  DISPARAÎT de l'écran entre l'accusé et le tirage suivant — le clignotement que l'agent prendrait
 *  pour une perte. Le numéro réel attribué par la mère remplace aussitôt le numéro provisoire. */
function enVol() {
  const lignes = db.prepare(`SELECT op, resultat, etat FROM file
    WHERE etat='en_attente' OR (etat='acceptee' AND CAST(json_extract(resultat,'$.seq') AS INTEGER) > ?) ORDER BY ordre`).all(+meta('curseur'));
  return lignes.map((r) => {
    const op = JSON.parse(r.op);
    if (r.etat === 'acceptee') { const res = JSON.parse(r.resultat); if (res.numero) op.champs.code = res.numero; }
    return op;
  });
}
function vue(c, id) {
  const s = lireConfirme(c, id);
  for (const op of enVol()) if (op.collection === c && op.fiche === id) { appliquer(s, op, 0); s.existe = true; }
  return s;
}
function liste(c) {
  const ids = new Set(db.prepare('SELECT id FROM confirme WHERE collection=?').all(c).map((r) => r.id));
  for (const op of enVol()) if (op.collection === c) ids.add(op.fiche);
  return Array.from(ids).map((id) => Object.assign({ id }, vue(c, id))).filter((x) => x.existe);
}

/* --- numéros : plage réservée, sinon provisoire ---------------------------- */
function prochainNumero() {
  const p = db.prepare("SELECT * FROM plage WHERE nom='patients'").get();
  if (p && p.prochain <= p.fin) { db.prepare("UPDATE plage SET prochain=prochain+1 WHERE nom='patients'").run(); return `CNT/${p.prochain}/26`; }
  return 'PROV-' + crypto.randomBytes(4).toString('hex');
}

/* --- écriture d'un geste : visible tout de suite, file persistée ------------- */
function ecrire(cmd) {
  const op = { id: uuid7(), appareil: meta('uuid'), epoch: +meta('epoch'), hlc: maintenant(), collection: cmd.collection, fiche: cmd.fiche || uuid7(),
    type: cmd.type, champs: Object.assign({}, cmd.champs || {}), vu: {} };
  if (cmd.bail) op.bail = true;
  if (op.type === 'modifier') { const base = lireConfirme(op.collection, op.fiche); for (const k of Object.keys(op.champs)) op.vu[k] = base.fieldseq[k] || 0; }
  if (op.type === 'creer' && op.collection === 'patients' && !op.champs.code) op.champs.code = prochainNumero();
  if (op.type === 'sortie' && op.bail) {
    const b = db.prepare('SELECT reste FROM baux WHERE article=?').get(op.fiche);
    if (!b || b.reste < +op.champs.qte) return { refus: 'bail_insuffisant', motif: `Quota local insuffisant pour ${op.fiche} (reste ${b ? b.reste : 0}).` };
    db.prepare('UPDATE baux SET reste=reste-? WHERE article=?').run(+op.champs.qte, op.fiche);
  }
  db.prepare("INSERT INTO file(id,op,etat) VALUES(?,?,'en_attente')").run(op.id, JSON.stringify(op));
  return { id: op.id, fiche: op.fiche, champs: op.champs };
}

/* --- réseau ------------------------------------------------------------------ */
async function http1(method, chemin, corps, essai) {
  const jeton = meta('jeton');
  const h = { 'Content-Type': 'application/json' }; if (jeton) h.Authorization = 'Bearer ' + jeton;
  const r = await fetch(MERE + chemin, { method, headers: h, body: corps ? JSON.stringify(corps) : undefined, signal: AbortSignal.timeout(1500) });
  const j = await r.json();
  if (r.status === 401 && j.code === 'jeton_expire' && !essai) { await renouveler(); return http1(method, chemin, corps, true); }
  if (r.status === 401 && j.code === 'appareil_revoque') { setMeta('suspendu', 1); etat.suspendu = true; throw Object.assign(new Error('suspendu'), { code: 'suspendu' }); }
  if (r.status === 409 && j.code === 'epoch_inconnue') { traiterEpoque(j.epoch_mere); throw Object.assign(new Error('epoque'), { code: 'epoque' }); }
  if (!r.ok) throw Object.assign(new Error(j.code || 'http_' + r.status), { code: j.code, status: r.status, corps: j });
  return j;
}
async function renouveler() {
  const r = await fetch(MERE + '/renouveler', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ renouvellement: meta('renouvellement') }), signal: AbortSignal.timeout(1500) });
  const j = await r.json();
  if (!r.ok) { if (j.code === 'appareil_revoque') { setMeta('suspendu', 1); etat.suspendu = true; } throw Object.assign(new Error(j.code), { code: j.code }); }
  setMeta('jeton', j.jeton); setMeta('renouvellement', j.renouvellement);
}

/** Époque inconnue : on N'EFFACE RIEN avant d'avoir exporté ce qui n'est pas parti. */
function traiterEpoque(epochMere) {
  const nonEnvoyees = db.prepare("SELECT op FROM file WHERE etat='en_attente' ORDER BY ordre").all().map((r) => JSON.parse(r.op));
  if (nonEnvoyees.length) {
    const fichier = `${DB === ':memory:' ? NOM : DB}.export-${Date.now()}.json`;
    fs.writeFileSync(fichier, JSON.stringify({ epoch_locale: +meta('epoch'), operations: nonEnvoyees }, null, 1));
    etat.exports.push(fichier);
  }
  tx(() => {
    db.exec('DELETE FROM confirme; DELETE FROM file; DELETE FROM plage; DELETE FROM baux;');
    setMeta('curseur', 0); setMeta('epoch', epochMere); setMeta('resync_ack', '');
  });
}

async function tirer() {
  let plein = false;
  for (;;) {
    const j = await http1('GET', `/sync/pull?depuis=${meta('curseur')}&limite=500&epoch=${meta('epoch')}`);
    if (j.resync && j.resync !== meta('resync_ack', '') && !plein) {
      plein = true; db.exec('DELETE FROM confirme'); setMeta('curseur', 0);
      continue;
    }
    tx(() => {
      for (const op of j.ops) {
        const s = lireConfirme(op.collection, op.fiche);
        appliquer(s, op, op.seq);
        ecrireConfirme(op.collection, op.fiche, s);
        setMeta('curseur', op.seq);
      }
    });
    if (j.fin) {
      if (j.resync && j.resync !== meta('resync_ack', '')) { await http1('POST', '/sync/ack-resync', { marque: j.resync }); setMeta('resync_ack', j.resync); }
      return;
    }
  }
}
async function envoyer() {
  const lot = db.prepare("SELECT op FROM file WHERE etat='en_attente' ORDER BY ordre LIMIT 200").all().map((r) => JSON.parse(r.op));
  if (!lot.length) return;
  const rep = await http1('POST', '/sync/push', { epoch: +meta('epoch'), horloge: maintenant(), ops: lot });
  tx(() => {
    for (const r of rep.resultats) {
      db.prepare('UPDATE file SET etat=?, resultat=? WHERE id=?').run(r.statut, JSON.stringify(r), r.id);
    }
  });
}
async function cycle() {
  if (etat.suspendu) return;
  etat.cycles++;
  try {
    await tirer(); await envoyer(); await tirer();
    etat.hors_ligne = false; etat.tentatives = 0; etat.derniere_erreur = null;
  } catch (e) {
    etat.derniere_erreur = e.code || e.message;
    if (e.code === 'suspendu' || e.code === 'epoque') return;
    etat.hors_ligne = true; etat.tentatives++;
  }
}
(async function boucle() {
  for (;;) {
    await cycle();
    await new Promise((r) => setTimeout(r, Math.min(INTERVALLE * 2 ** Math.min(etat.tentatives, 3), 1000)));
  }
})();

/* --- API de commande (le « clavier » du banc) ----------------------------------- */
const commandes = {
  'POST /appairer': async (b) => {
    const r = await fetch(MERE + '/appairage', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ code: b.code, uuid: meta('uuid'), plateforme: 'banc' }) });
    const j = await r.json(); if (!r.ok) return [r.status, j];
    setMeta('jeton', j.jeton); setMeta('renouvellement', j.renouvellement); setMeta('epoch', j.epoch); setMeta('suspendu', 0); etat.suspendu = false;
    return [200, { uuid: meta('uuid') }];
  },
  'POST /plage': async (b) => {
    const j = await http1('POST', '/sync/plage', { nom: 'patients', taille: b.taille || 50 });
    db.prepare("INSERT INTO plage(nom,prochain,fin) VALUES('patients',?,?) ON CONFLICT(nom) DO UPDATE SET prochain=excluded.prochain, fin=excluded.fin").run(j.debut, j.fin);
    return [200, j];
  },
  'POST /bail': async (b) => {
    const j = await http1('POST', '/sync/bail', { article: b.article, qte: b.qte });
    db.prepare('INSERT INTO baux(article,reste) VALUES(?,?) ON CONFLICT(article) DO UPDATE SET reste=reste+excluded.reste').run(b.article, j.accorde);
    return [200, j];
  },
  'POST /ecrire': (b) => [200, ecrire(b)],
  'POST /renouveler-force': async () => { try { await renouveler(); return [200, { ok: true }]; } catch (e) { return [401, { code: e.code }]; } },
  'POST /expirer-jeton': () => { setMeta('jeton', 'x.' + 'invalide'); return [200, {}]; },
  'GET /renouv': () => [200, { renouvellement: meta('renouvellement') }],
  'GET /vue': (b, q) => [200, vue(q.collection, q.id)],
  'GET /liste': (b, q) => [200, liste(q.collection)],
  'GET /etat': () => [200, Object.assign({}, etat, {
    uuid: meta('uuid'), epoch: +meta('epoch'), curseur: +meta('curseur'),
    en_attente: db.prepare("SELECT COUNT(*) AS n FROM file WHERE etat='en_attente'").get().n,
    a_traiter: db.prepare("SELECT resultat FROM file WHERE etat='refusee'").all().map((r) => JSON.parse(r.resultat)),
    fusionnees: db.prepare("SELECT resultat FROM file WHERE etat='fusionnee'").all().map((r) => JSON.parse(r.resultat)),
    acceptees: db.prepare("SELECT COUNT(*) AS n FROM file WHERE etat='acceptee'").get().n,
    resultats: db.prepare('SELECT id,etat,resultat FROM file ORDER BY ordre').all().map((r) => Object.assign({ id: r.id, etat: r.etat }, r.resultat ? JSON.parse(r.resultat) : {})),
  })],
};
http.createServer((req, res) => {
  const chunks = []; req.on('data', (c) => chunks.push(c));
  req.on('end', async () => {
    const u = new URL(req.url, 'http://x'); const q = Object.fromEntries(u.searchParams);
    let b = {}; try { b = chunks.length ? JSON.parse(Buffer.concat(chunks).toString()) : {}; } catch (e) { /* vide */ }
    const h = commandes[req.method + ' ' + u.pathname]; let st = 404; let out = { code: 'commande_inconnue' };
    if (h) { try { [st, out] = await h(b, q); } catch (e) { st = 500; out = { code: e.code || 'erreur', motif: e.message }; } }
    const t = JSON.stringify(out); res.writeHead(st, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(t) }); res.end(t);
  });
}).listen(PORT, '127.0.0.1', function () { if (process.send) process.send({ pret: true, port: this.address().port }); });
