'use strict';
/* =============================================================================
 * SIGH-CNT : le RELAIS DE RÉFÉRENCE, famille de routes `/sauvegarde/*` (lot 5, ADR-0007).
 * OPAQUE par construction : n'importe ni `crypto.js` ni aucune clé. Il ne connaît que des identifiants de blocs (empreintes du CHIFFRÉ), des tailles, des dates et des compteurs.
 * Il ne juge jamais un contenu. Réservée à la MÈRE : un appareil appairé reçoit 403 `sauvegarde_reservee_mere`, sans identité 403 `mere_requise`.
 * Les blocs vivent SUR DISQUE (`<dossier>/blocs/<2 premiers>/<id>`), jamais en base ; la base ne porte que des lignes (blocs, copies, liens).
 * ========================================================================== */
const fs = require('node:fs');
const path = require('node:path');
const nodeCrypto = require('node:crypto');
const R = require('./sauvegarde-regles');

const sha = (b) => nodeCrypto.createHash('sha256').update(b).digest('hex');
const ID = /^[0-9a-f]{64}$/;

module.exports = function installer({ db, dossier, Err, mereOk, getMeta, setMeta, maintenant = () => Date.now() }) {
  db.exec(`CREATE TABLE IF NOT EXISTS sauv_blocs (id TEXT PRIMARY KEY, taille INTEGER, recu INTEGER);
    CREATE TABLE IF NOT EXISTS sauv_copies (id TEXT PRIMARY KEY, type TEXT, etat TEXT, date INTEGER, recu INTEGER, garder INTEGER, nb_blocs INTEGER DEFAULT 0, taille INTEGER DEFAULT 0, racine TEXT, motif TEXT);
    CREATE TABLE IF NOT EXISTS sauv_liens (copie TEXT, bloc TEXT, PRIMARY KEY (copie, bloc));
    CREATE INDEX IF NOT EXISTS sauv_liens_bloc ON sauv_liens(bloc);`);
  const cles = { tailleBlocMax: 'sauv.taille_bloc_max', tailleMaxCopie: 'sauv.taille_max_copie', quotaOctets: 'sauv.quota_octets', rotationPlancher: 'sauv.rotation_plancher', rotationPlafond: 'sauv.rotation_plafond', orphelinsHeures: 'sauv.orphelins_heures' };
  for (const [k, v] of Object.entries(cles)) if (getMeta(v) === null) setMeta(v, R.LIMITES_RELAIS[k]); // défauts SEMÉS, jamais des constantes du code
  const limites = () => Object.fromEntries(Object.entries(cles).map(([k, v]) => [k, Number(getMeta(v))]));
  const chemin = (id) => path.join(dossier, 'blocs', id.slice(0, 2), id);
  const refus = (s, code, motif, geste, plus) => { const e = new Err(s, code, motif); e.b.geste = geste; Object.assign(e.b, plus || {}); return e; };
  const utilise = () => db.prepare('SELECT COALESCE(SUM(taille),0) AS n FROM sauv_blocs').get().n;
  const epinglesSql = "SELECT DISTINCT l.bloc FROM sauv_liens l JOIN sauv_copies c ON c.id=l.copie WHERE c.etat IN ('ouverte','complete')";

  /* Les copies « ouvertes » depuis plus que le délai des orphelins sont ABANDONNÉES : leurs blocs ne sont plus épinglés. */
  function abandonner() {
    const seuil = maintenant() - limites().orphelinsHeures * 3600 * 1000;
    db.prepare("UPDATE sauv_copies SET etat='abandonnee', motif='jamais validée dans le délai des orphelins' WHERE etat='ouverte' AND recu < ?").run(seuil);
  }
  const liberable = () => {
    abandonner();
    const seuil = maintenant() - limites().orphelinsHeures * 3600 * 1000;
    return db.prepare(`SELECT COALESCE(SUM(taille),0) AS n FROM sauv_blocs WHERE id NOT IN (${epinglesSql}) AND (id IN (SELECT bloc FROM sauv_liens) OR recu < ?)`).get(seuil).n;
  };
  function supprimerBloc(id) {
    try { fs.unlinkSync(chemin(id)); } catch (e) { /* déjà absent */ }
    db.prepare('DELETE FROM sauv_blocs WHERE id=?').run(id);
  }
  /* LIBÉRER de la place : orphelins vieux d'abord, puis les copies archivées ou abandonnées, la plus ancienne d'abord (jamais une copie courante, en cours, ni l'une des `plancher` plus récentes). */
  function liberer(besoin) {
    const lim = limites();
    const reste = () => utilise() + besoin - lim.quotaOctets;
    abandonner();
    const seuil = maintenant() - lim.orphelinsHeures * 3600 * 1000;
    const purgees = [];
    for (const b of db.prepare('SELECT id FROM sauv_blocs WHERE id NOT IN (SELECT bloc FROM sauv_liens) AND recu < ? ORDER BY recu').all(seuil)) { if (reste() <= 0) break; supprimerBloc(b.id); }
    const copies = db.prepare("SELECT id,type,etat,date FROM sauv_copies WHERE etat IN ('complete','archivee','abandonnee')").all();
    for (const id of R.ordrePurge(copies, lim.rotationPlancher)) {
      if (reste() <= 0) break;
      db.prepare("UPDATE sauv_copies SET etat='purgee', motif=? WHERE id=?").run('purgée pour libérer de la place', id);
      const siens = db.prepare('SELECT bloc FROM sauv_liens WHERE copie=?').all(id).map((r) => r.bloc);
      db.prepare('DELETE FROM sauv_liens WHERE copie=?').run(id);
      purgees.push(id);
      /* seuls les blocs de CETTE copie, et seulement ceux qu'aucune autre copie ne tient : un orphelin récent (copie en cours de dépôt) n'est jamais touché */
      for (const bloc of siens) if (!db.prepare('SELECT 1 FROM sauv_liens WHERE bloc=?').get(bloc)) supprimerBloc(bloc);
    }
    return { purgees, restant: Math.max(0, reste()) };
  }
  const copie = (id) => { const c = db.prepare('SELECT * FROM sauv_copies WHERE id=?').get(String(id)); if (!c) throw refus(404, 'COPIE_INCONNUE', 'cette copie n\'existe pas sur le relais', 'Relire la liste des copies.'); return c; };
  const vue = (c) => ({ id: c.id, type: c.type, etat: c.etat, date: c.date, recu: c.recu, garder: c.garder, nb_blocs: c.nb_blocs, taille: c.taille, motif: c.motif || null });

  const routes = {
    'GET /sauvegarde/etat': () => {
      const copies = {};
      for (const t of R.TYPES) {
        const cs = db.prepare('SELECT * FROM sauv_copies WHERE type=? ORDER BY date DESC, id').all(t);
        const compte = (e) => cs.filter((c) => c.etat === e).length;
        const derniere = cs.find((c) => c.etat === 'complete');
        copies[t] = { completes: compte('complete'), archivees: compte('archivee'), purgees: compte('purgee'), ouvertes: compte('ouverte'), derniere: derniere ? vue(derniere) : null };
      }
      return { format: R.FORMAT, limites: limites(), utilise: utilise(), liberable: liberable(), nb_blocs: db.prepare('SELECT COUNT(*) AS n FROM sauv_blocs').get().n, copies };
    },
    'POST /sauvegarde/manquants': (req, b) => {
      const ids = Array.isArray(b.ids) ? b.ids.map(String).filter((i) => ID.test(i)) : [];
      if (ids.length > 2000) throw refus(413, 'TROP_D_IDENTIFIANTS', 'plus de 2000 identifiants dans une demande', 'Demander par paquets de 2000 au plus.');
      const ont = new Set(); for (const i of ids) if (db.prepare('SELECT 1 FROM sauv_blocs WHERE id=?').get(i)) ont.add(i);
      return { manquants: ids.filter((i) => !ont.has(i)) };
    },
    'POST /sauvegarde/copie': (req, b) => {
      const id = String(b.id || ''); const type = String(b.type || '');
      if (!ID.test(id) || !R.TYPES.includes(type)) throw refus(422, 'COPIE_INVALIDE', 'identifiant ou type de copie invalide', 'Utiliser l\'identifiant calculé par le poste mère (empreinte du manifeste) et un type connu.');
      const lim = limites();
      const rot = R.rotation([], Number(b.garder), lim.rotationPlancher, lim.rotationPlafond);
      if (rot.ok === false) throw refus(422, rot.code, rot.motif, rot.geste, { plancher: rot.plancher, plafond: rot.plafond });
      const c = db.prepare('SELECT * FROM sauv_copies WHERE id=?').get(id);
      if (c) { if (c.etat === 'purgee' || c.etat === 'abandonnee') { db.prepare("UPDATE sauv_copies SET etat='ouverte', recu=?, motif=NULL WHERE id=?").run(maintenant(), id); return { etat: 'ouverte', reprise: true }; } return { etat: c.etat, rejeu: true }; }
      db.prepare("INSERT INTO sauv_copies(id,type,etat,date,recu,garder) VALUES(?,?,?,?,?,?)").run(id, type, 'ouverte', Number(b.date) || maintenant(), maintenant(), Number(b.garder));
      return { etat: 'ouverte' };
    },
    'GET /sauvegarde/copies': (req, b, q) => ({ copies: db.prepare(q.type ? 'SELECT * FROM sauv_copies WHERE type=? ORDER BY date DESC, id' : 'SELECT * FROM sauv_copies ORDER BY date DESC, id').all(...(q.type ? [q.type] : [])).map(vue) }),
  };

  /* Les routes à identifiant dans le chemin. Rend `undefined` si le chemin n'est pas de cette famille. */
  function traiter(req, u, q, brut) {
    if (!u.pathname.startsWith('/sauvegarde/')) return undefined;
    /* RÉSERVÉE À LA MÈRE : un appareil appairé (téléphone, fileul) est refusé en le nommant, avant toute lecture de la requête. */
    if (!mereOk(req)) {
      if (/^Bearer /.test(req.headers.authorization || '')) throw refus(403, 'sauvegarde_reservee_mere', 'les copies de sauvegarde ne sont accessibles qu\'à le poste mère', 'Aucun appareil appairé n\'y accède : utiliser le poste mère.');
      throw new Err(403, 'mere_requise');
    }
    let m;
    const cle = req.method + ' ' + u.pathname;
    if (routes[cle]) { let b = {}; try { b = brut.length ? JSON.parse(brut.toString()) : {}; } catch (e) { /* vide */ } return routes[cle](req, b, q); }
    if ((m = /^\/sauvegarde\/bloc\/([^/]+)$/.exec(u.pathname))) {
      const id = m[1];
      if (!ID.test(id)) throw refus(422, 'BLOC_ID_INVALIDE', 'l\'identifiant d\'un bloc est une empreinte SHA-256 en hexadécimal', 'Utiliser l\'empreinte du bloc chiffré.');
      if (req.method === 'PUT') {
        const lim = limites();
        if (brut.length === 0 || brut.length > lim.tailleBlocMax) throw refus(413, 'BLOC_TROP_GROS', `un bloc fait de 1 à ${lim.tailleBlocMax} octets, celui-ci en porte ${brut.length}`, 'Réduire la taille de bloc du réglage (1 Mio par défaut).', { limite: lim.tailleBlocMax });
        if (sha(brut) !== id) throw refus(422, 'BLOC_ALTERE_EN_ROUTE', 'les octets reçus n\'ont pas l\'empreinte annoncée : le bloc a été altéré en route', 'Renvoyer le bloc.');
        if (db.prepare('SELECT 1 FROM sauv_blocs WHERE id=?').get(id)) return { id, taille: brut.length, rejeu: true };
        if (utilise() + brut.length > lim.quotaOctets) {
          liberer(brut.length);
          if (utilise() + brut.length > lim.quotaOctets) throw refus(507, 'ESPACE_RELAIS_INSUFFISANT', `le quota du relais (${R.octets(lim.quotaOctets)}) est atteint, rien d'actuel n'a été supprimé`, 'Relever le quota du relais, réduire le nombre de copies gardées, ou choisir un dossier distant.', { utilise: utilise(), quota: lim.quotaOctets });
        }
        fs.mkdirSync(path.dirname(chemin(id)), { recursive: true });
        fs.writeFileSync(chemin(id) + '.tmp', brut); fs.renameSync(chemin(id) + '.tmp', chemin(id));
        db.prepare('INSERT INTO sauv_blocs(id,taille,recu) VALUES(?,?,?)').run(id, brut.length, maintenant());
        return { id, taille: brut.length };
      }
      if (req.method === 'GET') {
        const l = db.prepare('SELECT taille FROM sauv_blocs WHERE id=?').get(id);
        if (!l) throw refus(404, 'BLOC_ABSENT', 'ce bloc n\'est pas (ou plus) sur le relais', 'Choisir une autre copie.');
        const octets = fs.readFileSync(chemin(id));
        if (sha(octets) !== id) throw refus(409, 'BLOC_ALTERE_AU_RELAIS', 'le bloc stocké ne correspond plus à son empreinte', 'Choisir une autre copie ; signaler la panne du disque du relais.');
        return { __octets: octets };
      }
    }
    if ((m = /^\/sauvegarde\/copie\/([^/]+)(?:\/(blocs|valider))?$/.exec(u.pathname))) {
      const c = copie(m[1]);
      let b = {}; try { b = brut.length ? JSON.parse(brut.toString()) : {}; } catch (e) { /* vide */ }
      if (!m[2] && req.method === 'GET') {
        if (c.etat === 'purgee') throw refus(410, 'COPIE_PURGEE', 'cette copie a été purgée pour libérer de la place, elle n\'est plus restaurable', 'Choisir une copie plus récente.');
        if (c.etat !== 'complete' && c.etat !== 'archivee') throw refus(409, 'COPIE_INCOMPLETE', 'cette copie n\'a jamais été validée', 'Choisir une copie complète.');
        return Object.assign(vue(c), { racine: JSON.parse(c.racine || '[]') });
      }
      if (m[2] === 'blocs' && req.method === 'POST') {
        if (c.etat === 'complete') return { rejeu: true };
        if (c.etat !== 'ouverte') throw refus(409, 'COPIE_NON_OUVERTE', `cette copie est ${c.etat}`, 'Rouvrir la copie par le poste mère.');
        const ids = Array.isArray(b.ids) ? b.ids.map(String) : [];
        if (ids.length > 2000 || ids.some((i) => !ID.test(i))) throw refus(422, 'BLOC_ID_INVALIDE', 'au plus 2000 empreintes valides par demande', 'Rattacher par paquets de 2000 au plus.');
        const manquants = ids.filter((i) => !db.prepare('SELECT 1 FROM sauv_blocs WHERE id=?').get(i));
        if (manquants.length) throw refus(409, 'BLOC_MANQUANT', `${manquants.length} bloc(s) ne sont pas sur le relais`, 'Déposer d\'abord les blocs manquants.', { manquants: manquants.slice(0, 50) });
        const lim = limites();
        db.prepare('BEGIN').run();
        try {
          for (const i of ids) db.prepare('INSERT OR IGNORE INTO sauv_liens(copie,bloc) VALUES(?,?)').run(c.id, i);
          const t = db.prepare('SELECT COUNT(*) AS n, COALESCE(SUM(b.taille),0) AS s FROM sauv_liens l JOIN sauv_blocs b ON b.id=l.bloc WHERE l.copie=?').get(c.id);
          if (t.s > lim.tailleMaxCopie) { db.prepare('ROLLBACK').run(); throw refus(413, 'SAUVEGARDE_TROP_GROSSE', `la copie pèse ${R.octets(t.s)}, le maximum par copie est ${R.octets(lim.tailleMaxCopie)}`, 'Relever la limite par copie du relais, ou choisir un dossier distant.', { limite: lim.tailleMaxCopie }); }
          db.prepare('UPDATE sauv_copies SET nb_blocs=?, taille=? WHERE id=?').run(t.n, t.s, c.id);
          db.prepare('COMMIT').run();
        } catch (e) { try { db.prepare('ROLLBACK').run(); } catch (x) { /* déjà annulée */ } throw e; }
        return { rattaches: ids.length };
      }
      if (m[2] === 'valider' && req.method === 'POST') {
        if (c.etat === 'complete') return { etat: 'complete', rejeu: true, archivees: [] };
        if (c.etat !== 'ouverte') throw refus(409, 'COPIE_NON_OUVERTE', `cette copie est ${c.etat}`, 'Rouvrir la copie par le poste mère.');
        const racine = Array.isArray(b.racine) ? b.racine.map(String) : [];
        if (!racine.length) throw refus(422, 'RACINE_ABSENTE', 'une copie complète désigne les blocs de son manifeste', 'Déposer et désigner les blocs du manifeste.');
        const lies = new Set(db.prepare('SELECT bloc FROM sauv_liens WHERE copie=?').all(c.id).map((r) => r.bloc));
        const manquants = racine.filter((i) => !lies.has(i));
        if (manquants.length) throw refus(409, 'BLOC_MANQUANT', `${manquants.length} bloc(s) du manifeste ne sont pas rattachés à cette copie`, 'Rattacher les blocs du manifeste.', { manquants: manquants.slice(0, 50) });
        const lim = limites();
        const rot = R.rotation([], c.garder, lim.rotationPlancher, lim.rotationPlafond);
        if (rot.ok === false) throw refus(422, rot.code, rot.motif, rot.geste);
        db.prepare("UPDATE sauv_copies SET etat='complete', racine=? WHERE id=?").run(JSON.stringify(racine), c.id);
        const toutes = db.prepare('SELECT id,type,etat,date FROM sauv_copies WHERE type=?').all(c.type);
        const r = R.rotation(toutes, c.garder, lim.rotationPlancher, lim.rotationPlafond);
        for (const id of r.archiver) db.prepare("UPDATE sauv_copies SET etat='archivee' WHERE id=?").run(id);
        return { etat: 'complete', archivees: r.archiver };
      }
    }
    throw new Err(404, 'route_inconnue');
  }

  /* Crochets du banc (jamais en production) : régler une limite, altérer un bloc sur le disque du relais, reculer l'heure d'une copie ou d'un bloc. */
  const banc = {
    'POST /banc/sauvegarde/reglage': (req, b) => { const k = cles[b.cle]; if (!k) throw new Err(422, 'reglage_inconnu'); setMeta(k, Number(b.valeur)); return { ok: true }; },
    'POST /banc/sauvegarde/alterer': (req, b) => { const x = fs.readFileSync(chemin(b.id)); x[x.length - 1] ^= 1; fs.writeFileSync(chemin(b.id), x); return { ok: true }; },
    'POST /banc/sauvegarde/vieillir': (req, b) => { const ms = Number(b.heures) * 3600 * 1000; db.prepare('UPDATE sauv_copies SET date=date-?, recu=recu-?').run(ms, ms); db.prepare('UPDATE sauv_blocs SET recu=recu-?').run(ms); return { ok: true }; },
    'GET /banc/sauvegarde/tout': () => ({ blocs: db.prepare('SELECT * FROM sauv_blocs').all(), copies: db.prepare('SELECT * FROM sauv_copies').all(), liens: db.prepare('SELECT COUNT(*) AS n FROM sauv_liens').get().n }),
  };
  return { traiter, banc };
};
