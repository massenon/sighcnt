'use strict';
/* =============================================================================
 * SIGH-CNT : SAUVEGARDE HORS SITE (lot 5, ADR-0007) : le CLIENT de référence (la mère) et la restauration.
 * Chiffrement AU POSTE, clé de la clinique (AES-256-GCM, la même que le journal) ; la clé ne part JAMAIS : le relais n'en reçoit ni le clair, ni une dérivation.
 *
 * BLOC   = nonce (12) ‖ chiffré ‖ tag (16). Nonce DÉRIVÉ : HMAC-SHA-256(clé, « sigh-sauv-nonce|1|<genre>|<type>|<empreinte du clair> ») tronqué à 12 octets ;
 *          un même clair donne le même bloc (dédoublonnage, rejeu idempotent sans état local). AAD = « sigh-sauv-<genre>|1|<type> ». Identifiant = SHA-256 du BLOC.
 * GENRE  = « bloc » (données) ou « manifeste » (la liste des éléments et de leurs blocs, chiffrée et découpée comme le reste : le relais ne voit ni noms ni formats).
 * COPIE  = l'empreinte du manifeste en clair (l'identité d'une copie est celle de son CONTENU : rejouer le même état est la même copie).
 * ========================================================================== */
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const R = require('./sauvegarde-regles');

class ErreurSauvegarde extends Error {
  constructor(refus) { super(refus.code + ' : ' + refus.motif); this.refus = refus; this.code = refus.code; }
}
const sha = (b) => crypto.createHash('sha256').update(b).digest('hex');
const dormir = (ms) => new Promise((r) => setTimeout(r, ms));

class Chiffreur {
  constructor(cle) { if (!Buffer.isBuffer(cle) || cle.length !== 32) throw new Error('clé de 32 octets exigée'); this.cle = cle; }
  sceller(genre, type, clair) {
    const nonce = crypto.createHmac('sha256', this.cle).update(`sigh-sauv-nonce|1|${genre}|${type}|${sha(clair)}`).digest().subarray(0, 12);
    const c = crypto.createCipheriv('aes-256-gcm', this.cle, nonce);
    c.setAAD(Buffer.from(`sigh-sauv-${genre}|1|${type}`));
    const blob = Buffer.concat([nonce, c.update(clair), c.final(), c.getAuthTag()]);
    return { id: sha(blob), blob, clair: clair.length };
  }
  ouvrir(genre, type, blob) {
    const d = crypto.createDecipheriv('aes-256-gcm', this.cle, blob.subarray(0, 12));
    d.setAAD(Buffer.from(`sigh-sauv-${genre}|1|${type}`));
    d.setAuthTag(blob.subarray(blob.length - 16));
    return Buffer.concat([d.update(blob.subarray(12, blob.length - 16)), d.final()]);
  }
}

/* La destination « relais » : le client HTTP des routes `/sauvegarde/*` (en-tête de la mère). Un refus du relais devient un refus NOMMÉ. */
class DestRelais {
  constructor(base, secretMere) { this.base = base; this.secret = secretMere; }
  async appel(methode, chemin, corps, octets) {
    const entetes = { 'x-mere': this.secret };
    let body;
    if (octets) { body = octets; entetes['Content-Type'] = 'application/octet-stream'; } else if (corps !== undefined) { body = JSON.stringify(corps); entetes['Content-Type'] = 'application/json'; }
    const r = await fetch(this.base + chemin, { method: methode, headers: entetes, body });
    if (r.headers.get('content-type') === 'application/octet-stream') return Buffer.from(await r.arrayBuffer());
    let j = {}; try { j = await r.json(); } catch (e) { /* vide */ }
    if (r.status >= 400) throw new ErreurSauvegarde(Object.assign({ ok: false, code: j.code || 'ERREUR_RELAIS', motif: j.motif || `réponse ${r.status}`, geste: j.geste || '', statut: r.status }, j));
    return j;
  }
  etat() { return this.appel('GET', '/sauvegarde/etat'); }
  async manquants(ids) { return (await this.appel('POST', '/sauvegarde/manquants', { ids })).manquants; }
  deposerBloc(id, octets) { return this.appel('PUT', '/sauvegarde/bloc/' + id, undefined, octets); }
  ouvrir(id, type, date, garder) { return this.appel('POST', '/sauvegarde/copie', { id, type, date, garder }); }
  attacher(id, ids) { return this.appel('POST', `/sauvegarde/copie/${id}/blocs`, { ids }); }
  valider(id, racine) { return this.appel('POST', `/sauvegarde/copie/${id}/valider`, { racine }); }
  async copies(type) { return (await this.appel('GET', '/sauvegarde/copies' + (type ? '?type=' + type : ''))).copies; }
  copie(id) { return this.appel('GET', '/sauvegarde/copie/' + id); }
  bloc(id) { return this.appel('GET', '/sauvegarde/bloc/' + id); }
}

/* SAUVEGARDER. `elements` : [{ ref, taille, lire() -> Buffer, meta? }]. `options.coupureApres` : le dépôt est COUPÉ (exception) après tant de blocs déposés (banc).
   `options.lentMs` : une pause par bloc déposé (le banc tue le processus au milieu). Rend { copie, deposes, dejaLa, octetsDeposes, rejeu }. */
async function sauvegarder({ dest, cle, type, elements, tailleBloc = R.DEFAUTS.tailleBloc, garder = R.DEFAUTS.copiesMagasin, date = Date.now(), coupureApres = null, lentMs = 0 }) {
  if (!R.TYPES.includes(type)) throw new ErreurSauvegarde(R.refus('TYPE_INCONNU', `le type « ${type} » n'existe pas`, 'Choisir magasin ou fichiers.'));
  const ch = new Chiffreur(cle);
  const etat = await dest.etat();
  const pre = R.verifierPlan({ octetsCopie: elements.reduce((s, e) => s + R.tailleChiffree(e.taille, tailleBloc), 0), etat });
  if (pre) throw new ErreurSauvegarde(pre);
  if (etat.limites && tailleBloc > etat.limites.tailleBlocMax) throw new ErreurSauvegarde(R.refus('BLOC_TROP_GROS', `la taille de bloc réglée (${tailleBloc}) dépasse celle du relais (${etat.limites.tailleBlocMax})`, 'Réduire la taille de bloc du réglage.'));
  const ids = []; let deposes = 0; let dejaLa = 0; let octetsDeposes = 0; let lot = [];
  const vider = async () => {
    if (!lot.length) return;
    const manque = new Set(await dest.manquants(lot.map((b) => b.id)));
    for (const b of lot) {
      if (!manque.has(b.id)) { dejaLa++; continue; }
      if (coupureApres !== null && deposes >= coupureApres) throw new ErreurSauvegarde(R.refus('DEPOT_COUPE', `le dépôt a été coupé après ${deposes} bloc(s)`, 'Relancer : la reprise ne renvoie que les blocs manquants.', { deposes }));
      await dest.deposerBloc(b.id, b.blob); deposes++; octetsDeposes += b.blob.length;
      if (lentMs) await dormir(lentMs);
    }
    lot = [];
  };
  const mans = [];
  for (const e of elements) {
    const clair = e.lire();
    if (clair.length !== e.taille) throw new ErreurSauvegarde(R.refus('ELEMENT_CHANGE', 'un élément a changé de taille pendant la lecture', 'Relancer la copie.'));
    const blocs = [];
    for (const p of R.decouper(clair.length, tailleBloc)) {
      const b = ch.sceller('bloc', type, clair.subarray(p.debut, p.debut + p.longueur));
      blocs.push({ id: b.id, taille: b.blob.length, clair: b.clair }); ids.push(b.id); lot.push(b);
      if (lot.length >= 16) await vider();
    }
    mans.push({ ref: e.ref, taille: clair.length, sha256: sha(clair), meta: e.meta, blocs });
  }
  await vider();
  const m = R.manifeste({ type, elements: mans, tailleBloc });
  const clairM = Buffer.from(JSON.stringify(m));
  const racine = []; const blocsM = [];
  for (const p of R.decouper(clairM.length, tailleBloc)) { const b = ch.sceller('manifeste', type, clairM.subarray(p.debut, p.debut + p.longueur)); racine.push(b.id); blocsM.push(b); }
  lot = blocsM; await vider();
  const copie = sha(clairM);
  const ouv = await dest.ouvrir(copie, type, date, garder);
  if (ouv.etat === 'complete') return { copie, deposes, dejaLa, octetsDeposes, rejeu: true };
  const tous = [...new Set([...ids, ...racine])];
  for (let i = 0; i < tous.length; i += 1000) await dest.attacher(copie, tous.slice(i, i + 1000));
  const v = await dest.valider(copie, racine);
  return { copie, deposes, dejaLa, octetsDeposes, rejeu: false, archivees: v.archivees || [] };
}

/* RESTAURER dans une cible NEUVE. Tout est téléchargé, déchiffré et VÉRIFIÉ (empreinte du bloc, authentification, longueur, empreinte du clair de chaque élément) AVANT que la cible
   n'existe : un bloc altéré ou manquant est refusé et NOMMÉ, rien n'est restauré à moitié. La cible est écrite dans un dossier de travail puis RENOMMÉE d'un coup. */
async function restaurer({ dest, cle, copieId, cible }) {
  const ch = new Chiffreur(cle);
  if (fs.existsSync(cible)) throw new ErreurSauvegarde(R.refus('CIBLE_EXISTE', `« ${cible} » existe déjà`, 'Restaurer vers un dossier NEUF : la restauration ne remplace jamais ce qui existe.'));
  const c = await dest.copie(copieId);
  const lire = async (genre, type, id) => {
    let blob;
    try { blob = await dest.bloc(id); } catch (e) { if (e instanceof ErreurSauvegarde && ['BLOC_ABSENT', 'BLOC_ALTERE_AU_RELAIS'].includes(e.code)) throw new ErreurSauvegarde(R.refus(e.code === 'BLOC_ABSENT' ? 'BLOC_MANQUANT' : 'BLOC_ALTERE', `le bloc ${id} ${e.code === 'BLOC_ABSENT' ? 'est absent' : 'est altéré au relais'}`, 'Choisir une autre copie.', { bloc: id })); throw e; }
    if (sha(blob) !== id) throw new ErreurSauvegarde(R.refus('BLOC_ALTERE', `le bloc ${id} ne correspond pas à son empreinte`, 'Choisir une autre copie : celle-ci est altérée.', { bloc: id }));
    try { return ch.ouvrir(genre, type, blob); } catch (e) { throw new ErreurSauvegarde(R.refus('CLE_INCORRECTE', `le bloc ${id} est intact mais ne s'ouvre pas avec cette clé`, 'Utiliser la clé de la clinique qui a fait la copie (export de clé, copie papier sous scellé).', { bloc: id })); }
  };
  const clairM = Buffer.concat(await sequence(c.racine.map((id) => () => lire('manifeste', c.type, id))));
  if (sha(clairM) !== copieId) throw new ErreurSauvegarde(R.refus('MANIFESTE_ALTERE', 'le manifeste ne correspond pas à l\'identité de la copie', 'Choisir une autre copie.'));
  let m; try { m = JSON.parse(clairM.toString()); } catch (e) { throw new ErreurSauvegarde(R.refus('MANIFESTE_ILLISIBLE', 'le manifeste ne se lit pas', 'Choisir une autre copie.')); }
  const refusM = R.verifierManifeste(m);
  if (refusM) throw new ErreurSauvegarde(refusM);
  const travail = cible + '.reprise-' + crypto.randomBytes(4).toString('hex');
  fs.mkdirSync(travail, { recursive: true });
  try {
    for (const e of m.elements) {
      const morceaux = [];
      for (const b of e.blocs) {
        const clair = await lire('bloc', m.type, b.id);
        if (clair.length !== b.clair) throw new ErreurSauvegarde(R.refus('BLOC_ALTERE', `le bloc ${b.id} n'a pas la longueur annoncée`, 'Choisir une autre copie.', { bloc: b.id }));
        morceaux.push(clair);
      }
      const tout = Buffer.concat(morceaux);
      if (sha(tout) !== e.sha256) throw new ErreurSauvegarde(R.refus('EMPREINTE_CLAIR_DIVERGENTE', `l'élément ${e.ref} ne correspond pas à son empreinte`, 'Choisir une autre copie.', { element: e.ref }));
      fs.writeFileSync(path.join(travail, e.ref), tout);
    }
  } catch (x) { fs.rmSync(travail, { recursive: true, force: true }); throw x; }
  fs.renameSync(travail, cible);
  return { elements: m.elements.length, octets: m.total, type: m.type };
}
async function sequence(fs_) { const out = []; for (const f of fs_) out.push(await f()); return out; }

module.exports = { Chiffreur, DestRelais, ErreurSauvegarde, sauvegarder, restaurer, sha };
