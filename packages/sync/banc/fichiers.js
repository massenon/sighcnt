'use strict';
/* =============================================================================
 * SIGH-CNT, BANC : les FICHIERS NUMÉRISÉS par la synchronisation (lot D5, EF-SYNC-18), implémentation de RÉFÉRENCE en Node
 * -----------------------------------------------------------------------------
 * Ce module est LU par la mère de référence (`mere.js`, routes `/fichiers/*`) et par le fileul de référence (`fileul.js`, commandes `/fichier/*`). Il tient le protocole que le banc
 * éprouve, et que le code Dart (`packages/sync_dart/lib/src/fichiers_mere.dart`, `stockage_fichiers.dart`) reprend :
 *
 *   - un fichier voyage À PART du journal, par son empreinte SHA-256, en morceaux de 256 Kio dont chacun porte SON empreinte ;
 *   - le fichier n'est rangé qu'après la vérification de l'empreinte de l'ENSEMBLE ; un morceau altéré est refusé (409 MORCEAU_ALTERE) et renvoyé ;
 *   - un transfert coupé REPREND au dernier morceau vérifié (les morceaux sont sur disque : une mère tuée puis relancée les retrouve) ;
 *   - une COPIE par empreinte : un second déposant du même fichier cumule son usage ;
 *   - la mère ne contacte jamais un poste ; JAMAIS vers un téléphone ; le droit est celui de l'écran de la famille PLUS la zone du type (RG-13), lu de la règle ENGENDRÉE de
 *     `rbac.json` (`prototype_html/api/regles-fichiers.json`, la même que celle du serveur de la maquette) ;
 *   - le relais en ligne n'en voit pas un octet : le binaire ne passe que par la mère et les fileuls.
 * ========================================================================== */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const REGLES = JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', '..', 'prototype_html', 'api', 'regles-fichiers.json'), 'utf8'));
const sha = (b) => crypto.createHash('sha256').update(b).digest('hex');
const MORCEAU = 256 * 1024;
const PLAFOND = REGLES.taillePlafond;

class Refus extends Error {
  constructor(statut, code, motif, geste, plus) { super(code); this.statut = statut; this.corps = Object.assign({ code, motif, geste }, plus || {}); }
}

const STATUT = { DROIT_REFUSE: 403, ZONE_REFUSEE: 403, FICHIERS_INTERDITS_AU_MOBILE: 403, PIECE_NON_RATTACHEE: 403, FICHIER_ABSENT: 404, FICHIER_ALTERE: 409, MORCEAU_ALTERE: 409,
  EMPREINTE_DIVERGENTE: 409, TRANSFERT_NON_OUVERT: 409, TRANSFERT_INCOMPLET: 409, FORMAT_REFUSE: 415, TAILLE_DEPASSEE: 413 };
const refus = (code, motif, geste, plus) => new Refus(STATUT[code] || 400, code, motif, geste, plus);

/** Le format lu sur les PREMIERS OCTETS (jamais sur un nom). */
function format(b) {
  if (b.length >= 5 && b.subarray(0, 5).toString('latin1') === '%PDF-') return { id: 'pdf', mime: 'application/pdf', ext: 'pdf' };
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return { id: 'jpeg', mime: 'image/jpeg', ext: 'jpg' };
  if (b.length >= 8 && b.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return { id: 'png', mime: 'image/png', ext: 'png' };
  if (b.length >= 12 && b.subarray(0, 4).toString('latin1') === 'RIFF' && b.subarray(8, 12).toString('latin1') === 'WEBP') return { id: 'webp', mime: 'image/webp', ext: 'webp' };
  return null;
}

/** Le droit d'un rôle sur une famille, pour un geste (`voir`, `editer`) : l'écran de la famille PLUS la zone du type (même règle que `api/fichiers.php`). `null` si permis. */
function droit(role, famille, geste, type) {
  const idx = geste === 'editer' ? 1 : (geste === 'annuler' ? 2 : 0);
  const d = (REGLES.roles[role] || {})[famille] || [0, 0, 0];
  if (!d[idx]) return refus('DROIT_REFUSE', `le profil « ${role} » n’a pas le droit de ${geste === 'voir' ? 'lire' : 'déposer'} sur l’écran « ${REGLES.familles[famille]} »`, 'Demander ce droit à l’administrateur (« Rôles & permissions »).');
  if (famille === 'patient') {
    const zone = Number(REGLES.types[type] == null ? 2 : REGLES.types[type]);
    if (zone >= 2 && !REGLES.zone2.includes(role)) return refus('ZONE_REFUSEE', `le profil « ${role} » ne lit ni ne dépose les pièces médicales du dossier patient (RG-13)`, 'Seuls les profils cliniques traitent ce type de pièce ; l’accueil dépose la pièce d’identité et la carte d’assurance.');
  }
  return null;
}
const zoneDe = (famille, type) => (famille === 'patient' ? Number(REGLES.types[type] == null ? 2 : REGLES.types[type]) : 0);

/** Les empreintes de chaque morceau d'un fichier. */
function description(octets, tailleMorceau = MORCEAU) {
  const morceaux = [];
  for (let o = 0; o < octets.length; o += tailleMorceau) morceaux.push(sha(octets.subarray(o, Math.min(o + tailleMorceau, octets.length))));
  return { sha256: sha(octets), taille: octets.length, tailleMorceau, morceaux };
}
function incoherence(d) {
  if (!/^[0-9a-f]{64}$/.test(String(d.sha256))) return refus('EMPREINTE_INVALIDE', 'l’empreinte annoncée n’est pas un SHA-256 (64 caractères hexadécimaux)', 'Ouvrir la pièce depuis sa fiche.');
  if (!(d.taille > 0)) return refus('FICHIER_VIDE', 'le fichier annoncé ne contient aucun octet', 'Choisir un fichier numérisé non vide.');
  if (d.taille > PLAFOND) return refus('TAILLE_DEPASSEE', 'le fichier annoncé dépasse le maximum', 'Numériser en résolution plus basse.');
  if (!(d.tailleMorceau >= 1024 && d.tailleMorceau <= 4 * 1024 * 1024)) return refus('PLAN_INVALIDE', 'la taille de morceau annoncée est hors de 1 Kio à 4 Mio', 'Rejouer le transfert.');
  if (!Array.isArray(d.morceaux) || d.morceaux.length !== Math.ceil(d.taille / d.tailleMorceau) || d.morceaux.some((m) => !/^[0-9a-f]{64}$/.test(String(m)))) return refus('PLAN_INVALIDE', 'le plan des morceaux ne correspond pas à la taille annoncée', 'Rejouer le transfert depuis le fichier d’origine.');
  return null;
}

/** Le stockage d'un poste : `<aa>/<sha>.<ext>`, écriture atomique, empreinte recalculée à chaque lecture, morceaux en cours sous `_partiels/<sha>/`. */
class Stockage {
  constructor(dossier) { this.dossier = dossier; fs.mkdirSync(dossier, { recursive: true }); }
  dir(s) { return path.join(this.dossier, s.slice(0, 2)); }
  chemin(s) { for (const e of ['pdf', 'jpg', 'png', 'webp']) { const p = path.join(this.dir(s), s + '.' + e); if (fs.existsSync(p)) return p; } return null; }
  atomique(p, octets) { fs.mkdirSync(path.dirname(p), { recursive: true }); const t = p + '.' + crypto.randomBytes(4).toString('hex') + '.tmp'; fs.writeFileSync(t, octets); fs.renameSync(t, p); }
  meta(s) { const p = path.join(this.dir(s), s + '.json'); return fs.existsSync(p) ? JSON.parse(fs.readFileSync(p, 'utf8')) : null; }
  /** Les octets, EMPREINTE VÉRIFIÉE : absent ou altéré, jamais servi. */
  lire(s) {
    const p = this.chemin(s);
    if (!p) throw refus('FICHIER_ABSENT', 'ce fichier n’est pas (encore) arrivé sur ce poste', 'Attendre la synchronisation des fichiers.');
    const b = fs.readFileSync(p);
    if (sha(b) !== s) throw refus('FICHIER_ALTERE', `le fichier rangé n’a plus son empreinte (${s.slice(0, 8)}) : il n’est pas servi`, 'Redemander le fichier à la mère.');
    return b;
  }
  etat(s) { if (!this.chemin(s)) return 'absent'; try { this.lire(s); return 'present'; } catch (e) { return 'altere'; } }
  ranger(octets, famille, zone, annonce) {
    if (!octets.length) throw refus('FICHIER_VIDE', 'le fichier ne contient aucun octet', 'Choisir un fichier numérisé non vide.');
    const f = format(octets); const ok = f && REGLES.formats.find((x) => x.id === f.id && x.familles.includes(famille));
    if (!ok) throw refus('FORMAT_REFUSE', 'le contenu du fichier n’est pas un format admis', 'Enregistrer la numérisation en PDF, JPEG ou PNG.');
    const s = sha(octets);
    if (annonce && annonce !== s) throw refus('EMPREINTE_DIVERGENTE', 'le fichier reçu n’a pas l’empreinte annoncée', 'Déposer de nouveau le fichier.', { recu: s, annonce });
    const p = path.join(this.dir(s), s + '.' + f.ext);
    let nouveau = true;
    if (fs.existsSync(p)) { nouveau = false; if (sha(fs.readFileSync(p)) !== s) { this.atomique(p, octets); } } else this.atomique(p, octets);
    const m = this.meta(s) || { sha256: s, mime: f.mime, ext: f.ext, taille: octets.length, usages: [] };
    if (!m.usages.some((u) => u.famille === famille && u.zone === zone)) m.usages.push({ famille, zone });
    this.atomique(path.join(this.dir(s), s + '.json'), JSON.stringify(m));
    return { sha256: s, nouveau, taille: octets.length };
  }
  ajouterUsage(s, famille, zone) {
    const m = this.meta(s); if (!m || !this.chemin(s)) return false;
    if (!m.usages.some((u) => u.famille === famille && u.zone === zone)) { m.usages.push({ famille, zone }); this.atomique(path.join(this.dir(s), s + '.json'), JSON.stringify(m)); }
    return true;
  }
  partiel(s, i) { return path.join(this.dossier, '_partiels', s, i + '.part'); }
  /** Rouvre une réception : les morceaux déjà rangés sont RELUS ET RE-VÉRIFIÉS ; seuls les bons comptent. */
  recus(d) {
    const out = [];
    for (let i = 0; i < d.morceaux.length; i++) {
      const p = this.partiel(d.sha256, i);
      if (!fs.existsSync(p)) continue;
      const b = fs.readFileSync(p);
      if (sha(b) === d.morceaux[i] && b.length === Math.min(d.tailleMorceau, d.taille - i * d.tailleMorceau)) out.push(i); else fs.rmSync(p, { force: true });
    }
    return out;
  }
  morceau(d, i, octets) {
    if (!(i >= 0 && i < d.morceaux.length)) throw refus('MORCEAU_HORS_PLAN', `le morceau ${i} n’existe pas dans ce fichier`, 'Reprendre avec la liste des morceaux manquants.');
    const attendu = Math.min(d.tailleMorceau, d.taille - i * d.tailleMorceau);
    if (octets.length !== attendu || sha(octets) !== d.morceaux[i]) throw refus('MORCEAU_ALTERE', `le morceau ${i} n’a pas l’empreinte annoncée (transport altéré)`, 'Renvoyer ce morceau.', { morceau: i });
    this.atomique(this.partiel(d.sha256, i), octets);
  }
  assembler(d, famille, zone) {
    const manquants = []; const parts = [];
    for (let i = 0; i < d.morceaux.length; i++) { const p = this.partiel(d.sha256, i); if (fs.existsSync(p)) parts.push(fs.readFileSync(p)); else manquants.push(i); }
    if (manquants.length) throw refus('TRANSFERT_INCOMPLET', `il manque ${manquants.length} morceau(x)`, 'Reprendre le transfert.', { manquants });
    const tout = Buffer.concat(parts);
    const jeter = () => fs.rmSync(path.join(this.dossier, '_partiels', d.sha256), { recursive: true, force: true });
    if (tout.length !== d.taille || sha(tout) !== d.sha256) { jeter(); throw refus('EMPREINTE_DIVERGENTE', 'le fichier assemblé n’a pas l’empreinte annoncée', 'Redemander le fichier.'); }
    try { const r = this.ranger(tout, famille, zone, d.sha256); jeter(); return r; } catch (e) { jeter(); throw e; }
  }
  nbCopies() {
    let n = 0;
    for (const a of fs.existsSync(this.dossier) ? fs.readdirSync(this.dossier) : []) {
      if (a.length !== 2) continue;
      for (const f of fs.readdirSync(path.join(this.dossier, a))) if (/^[0-9a-f]{64}\.(pdf|jpg|png|webp)$/.test(f)) n++;
    }
    return n;
  }
}

/** LA MÈRE : les cinq routes. `ctx.auth(req)` rend l'appareil ({uuid, role}) ou lève. */
function mere(stockage, ctx) {
  const receptions = new Map();
  const json = (res, st, o) => { const t = JSON.stringify(o); res.writeHead(st, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(t) }); res.end(t); };
  return async function traiter(req, res, corps, u) {
    try {
      const app = ctx.auth(req);
      if (app.role === 'mobile') throw refus('FICHIERS_INTERDITS_AU_MOBILE', 'les fichiers numérisés ne sont jamais envoyés à un téléphone (RG-13)', 'Consulter la pièce depuis un poste de la clinique.');
      const role = req.headers['x-sigh-role'] || '';
      if (!role) throw refus('ROLE_REQUIS', 'le rôle de l’agent n’est pas déclaré', 'Mettre le poste à jour.');
      const q = Object.fromEntries(u.searchParams);
      const cle = req.method + ' ' + u.pathname;
      const famille = (f) => { if (!['courrier', 'patient'].includes(f)) throw refus('FAMILLE_INCONNUE', `la famille « ${f} » n’existe pas`, 'Indiquer courrier ou patient.'); return f; };
      const lecture = (fam, s) => {
        if (!/^[0-9a-f]{64}$/.test(String(s))) throw refus('EMPREINTE_INVALIDE', 'l’empreinte demandée n’est pas un SHA-256 (64 caractères hexadécimaux)', 'Ouvrir la pièce depuis sa fiche.');
        const m = stockage.meta(s);
        const zoneMax = m ? Math.max(0, ...m.usages.filter((x) => x.famille === fam).map((x) => x.zone)) : 0;
        const d = droit(role, fam, 'voir', zoneMax >= 2 ? '__zone2__' : (fam === 'patient' ? 'Pièce d’identité' : null));
        if (d) throw d;
        if (m && !m.usages.some((x) => x.famille === fam)) throw refus('PIECE_NON_RATTACHEE', `cette empreinte n’est pas rattachée à la famille « ${fam} »`, 'Ouvrir la pièce depuis la fiche qui la porte.');
        return m;
      };
      if (cle === 'POST /fichiers/ouvrir') {
        const b = JSON.parse(corps.toString() || '{}'); const fam = famille(b.famille);
        const d = droit(role, fam, 'editer', b.type || null); if (d) throw d;
        const desc = b.description || {}; const inco = incoherence(desc); if (inco) throw inco;
        const zone = zoneDe(fam, b.type);
        if (stockage.etat(desc.sha256) === 'present') { stockage.ajouterUsage(desc.sha256, fam, zone); receptions.delete(desc.sha256); return json(res, 200, { ok: true, complet: true, sha256: desc.sha256, recus: [], morceaux: desc.morceaux.length }); }
        fs.mkdirSync(path.join(stockage.dossier, '_partiels', desc.sha256), { recursive: true });
        receptions.set(desc.sha256, { desc, famille: fam, zone, appareil: app.uuid });
        return json(res, 200, { ok: true, complet: false, sha256: desc.sha256, recus: stockage.recus(desc), morceaux: desc.morceaux.length });
      }
      if (cle === 'PUT /fichiers/morceau') {
        const r = receptions.get(q.sha256);
        if (!r || r.appareil !== app.uuid) throw refus('TRANSFERT_NON_OUVERT', 'aucun dépôt ouvert pour cette empreinte (la mère a pu redémarrer)', 'Rouvrir le dépôt : il reprend au dernier morceau vérifié.');
        stockage.morceau(r.desc, +q.i, corps);
        return json(res, 200, { ok: true, recus: stockage.recus(r.desc).length, morceaux: r.desc.morceaux.length });
      }
      if (cle === 'POST /fichiers/terminer') {
        const b = JSON.parse(corps.toString() || '{}'); const r = receptions.get(b.sha256);
        if (!r) { if (stockage.etat(b.sha256) === 'present') return json(res, 200, { ok: true, sha256: b.sha256, nouveau: false }); throw refus('TRANSFERT_NON_OUVERT', 'aucun dépôt ouvert pour cette empreinte', 'Rouvrir le dépôt.'); }
        try { const x = stockage.assembler(r.desc, r.famille, r.zone); receptions.delete(b.sha256); return json(res, 200, { ok: true, sha256: b.sha256, nouveau: x.nouveau }); } catch (e) { if (!e.corps || e.corps.code !== 'TRANSFERT_INCOMPLET') receptions.delete(b.sha256); throw e; }
      }
      if (cle === 'GET /fichiers/info') {
        const fam = famille(q.famille); const m = lecture(fam, q.sha256); const b = stockage.lire(q.sha256);
        return json(res, 200, { ok: true, description: description(b, +q.morceau || MORCEAU), mime: m && m.mime, ext: m && m.ext });
      }
      if (cle === 'GET /fichiers/morceau') {
        const fam = famille(q.famille); lecture(fam, q.sha256); const b = stockage.lire(q.sha256);
        const t = +q.morceau || MORCEAU; const i = +q.i;
        if (!(i >= 0 && i * t < b.length)) throw refus('MORCEAU_HORS_PLAN', `le morceau ${i} n’existe pas dans ce fichier`, 'Reprendre avec la liste des morceaux manquants.');
        const part = b.subarray(i * t, Math.min((i + 1) * t, b.length));
        res.writeHead(200, { 'Content-Type': 'application/octet-stream', 'Content-Length': part.length, 'x-sigh-morceau-sha256': sha(part) }); return res.end(part);
      }
      throw refus('ACTION_INCONNUE', 'route de fichiers inconnue', 'Mettre le poste à jour.');
    } catch (e) {
      if (e instanceof Refus) return json(res, e.statut, e.corps);
      if (e && e.status && e.body) return json(res, e.status, e.body); /* Err de mere.js (authentification) */
      return json(res, 500, { code: 'erreur_interne', motif: String(e && e.message) });
    }
  };
}

/** LE FILEUL : envoi et réception par morceaux. `appel(methode, chemin, corps, entetes)` rend { status, octets, entetes } et lève si la mère est injoignable. */
function client(appel, stockage) {
  const jsonDe = (r) => { try { return JSON.parse(Buffer.from(r.octets).toString()); } catch (e) { return {}; } };
  async function envoyer(o) {
    const octets = stockage.lire(o.sha256); const tm = o.tailleMorceau || MORCEAU; const d = description(octets, tm);
    const ent = { 'x-sigh-role': o.role };
    const ouvrir = () => appel('POST', '/fichiers/ouvrir', Buffer.from(JSON.stringify({ famille: o.famille, type: o.type || null, description: d })), Object.assign({ 'Content-Type': 'application/json' }, ent));
    let r = await ouvrir(); let j = jsonDe(r);
    const sortie = { envoyes: 0, renvoyes: 0, complet: false, coupe: false, ouverts: 1 };
    if (r.status !== 200) return Object.assign(sortie, { refus: j, statut: r.status });
    if (j.complet) return Object.assign(sortie, { complet: true });
    let recus = new Set(j.recus);
    for (let i = 0; i < d.morceaux.length; i++) {
      if (recus.has(i)) continue;
      if (o.coupureApres != null && sortie.envoyes >= o.coupureApres) return Object.assign(sortie, { coupe: true });
      let ok = false;
      for (let essai = 0; essai < 3 && !ok; essai++) {
        let part = Buffer.from(octets.subarray(i * tm, Math.min((i + 1) * tm, octets.length)));
        if (o.alterer === i && essai === 0) part[10] ^= 0xff; /* altération en route, une fois */
        const p = await appel('PUT', `/fichiers/morceau?sha256=${o.sha256}&i=${i}`, part, ent); const pj = jsonDe(p);
        if (p.status === 200) { ok = true; sortie.envoyes++; } else if (pj.code === 'MORCEAU_ALTERE') sortie.renvoyes++;
        else if (pj.code === 'TRANSFERT_NON_OUVERT') { r = await ouvrir(); sortie.ouverts++; j = jsonDe(r); if (j.complet) return Object.assign(sortie, { complet: true }); recus = new Set(j.recus); if (recus.has(i)) ok = true; }
        else return Object.assign(sortie, { refus: pj, statut: p.status });
      }
      if (!ok) throw new Error('le morceau ' + i + ' n’a pas pu être envoyé');
    }
    const f = await appel('POST', '/fichiers/terminer', Buffer.from(JSON.stringify({ sha256: o.sha256 })), Object.assign({ 'Content-Type': 'application/json' }, ent)); const fj = jsonDe(f);
    if (f.status === 200) return Object.assign(sortie, { complet: true });
    return Object.assign(sortie, { refus: fj, statut: f.status });
  }
  async function recevoir(o) {
    const tm = o.tailleMorceau || MORCEAU; const ent = { 'x-sigh-role': o.role };
    const sortie = { recus: 0, renvoyes: 0, present: false, absentMere: false, coupe: false };
    const info = await appel('GET', `/fichiers/info?sha256=${o.sha256}&famille=${o.famille}&morceau=${tm}`, null, ent); const ij = jsonDe(info);
    if (info.status === 404) return Object.assign(sortie, { absentMere: true });
    if (info.status !== 200) return Object.assign(sortie, { refus: ij, statut: info.status });
    const d = ij.description; if (d.sha256 !== o.sha256) return Object.assign(sortie, { refus: { code: 'EMPREINTE_DIVERGENTE' } });
    const deja = new Set(stockage.recus(d));
    for (let i = 0; i < d.morceaux.length; i++) {
      if (deja.has(i)) continue;
      if (o.coupureApres != null && sortie.recus >= o.coupureApres) return Object.assign(sortie, { coupe: true });
      let ok = false;
      for (let essai = 0; essai < 3 && !ok; essai++) {
        const g = await appel('GET', `/fichiers/morceau?sha256=${o.sha256}&i=${i}&famille=${o.famille}&morceau=${tm}`, null, ent);
        if (g.status !== 200) return Object.assign(sortie, { refus: jsonDe(g), statut: g.status });
        let octets = Buffer.from(g.octets); if (o.alterer === i && essai === 0) octets[5] ^= 0xff;
        try { stockage.morceau(d, i, octets); ok = true; sortie.recus++; } catch (e) { if (e instanceof Refus) sortie.renvoyes++; else throw e; }
      }
      if (!ok) throw new Error('le morceau ' + i + ' n’a pas pu être reçu');
    }
    try { stockage.assembler(d, o.famille, zoneDe(o.famille, o.type)); sortie.present = true; } catch (e) { if (e instanceof Refus) return Object.assign(sortie, { refus: e.corps }); throw e; }
    return sortie;
  }
  return { envoyer, recevoir };
}

module.exports = { Stockage, Refus, mere, client, description, droit, format, sha, REGLES, MORCEAU };
