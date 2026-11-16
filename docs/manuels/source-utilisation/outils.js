/* Outils communs : navigateur, session de démonstration, attente de peinture, annotation. */
'use strict';
const path = require('path');
const ROOT = path.resolve(__dirname, '../../../prototype_html');
const puppeteer = require(path.join(ROOT, 'node_modules/puppeteer'));
const PORT = Number(process.env.SIGH_PORT_MANUEL || 8218);
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
const http = require('http');

function jeton() {
  return new Promise((resolve) => {
    const corps = JSON.stringify({ action: 'connexion', identifiant: 'c.bassongui', motDePasse: 'demonstration', poste: 'manuel' });
    const q = http.request({ host: '127.0.0.1', port: PORT, path: '/api/auth.php', method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(corps) } },
    (r) => { let d = ''; r.on('data', (c) => { d += c; }); r.on('end', () => { try { resolve(JSON.parse(d).jeton); } catch (e) { resolve(null); } }); });
    q.on('error', () => resolve(null)); q.end(corps);
  });
}

/** Nom affiché neutre : aucune capture ne montre le nom d'un agent réel. */
const NOM_DEMO = 'AGENT Démonstration';
const SECTEURS = { admin: 'ADM', direction: 'DIR', da: 'DIR', dm: 'DIR', medecin: 'CONS', infirmier: 'HOSP', laborantin: 'LABO', stock: 'PHAR', caissier: 'PHAR', reception: 'CONS', comptable: 'ADM' };

async function ouvrirNavigateur() {
  const browser = await puppeteer.launch({ executablePath: CHROME, headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage', '--font-render-hinting=none'] });
  const page = await browser.newPage();
  await page.setViewport({ width: 1440, height: 900, deviceScaleFactor: 2 });
  page.setDefaultTimeout(120000); page.setDefaultNavigationTimeout(120000);
  const j = await jeton();
  /* L'horloge de la page est décalée sur la date du jeu de démonstration (16/08/2026), comme le banc. */
  const decalage = new Date(2026, 7, 16, 10, 30, 0).getTime() - Date.now();
  await page.evaluateOnNewDocument((jt, dec) => {
    try { if (jt) localStorage.setItem('sigh-cnt:jeton', jt); } catch (e) { /* stockage absent */ }
    try {
      const Reel = window.Date; const maintenant = () => Reel.now() + dec;
      function D() { if (!(this instanceof D)) return String(new Reel(maintenant())); if (arguments.length === 0) return new Reel(maintenant());
        return new (Function.prototype.bind.apply(Reel, [null].concat(Array.prototype.slice.call(arguments))))(); }
      D.prototype = Reel.prototype; D.now = maintenant; D.UTC = Reel.UTC; D.parse = Reel.parse; window.Date = D;
    } catch (e) { /* heure réelle */ }
  }, j, decalage);
  return { browser, page };
}

async function poserRole(page, role) {
  await page.evaluate((r, nom, sect) => {
    localStorage.setItem('sigh-cnt:session', JSON.stringify({ role: r, fonction: r, nom: nom, nomComplet: nom, identifiant: 'c.bassongui', secteur: sect, poste: 'Démonstration' }));
  }, role, NOM_DEMO, SECTEURS[role] || 'DIR');
}

async function attendrePeinture(page, limite) {
  const fin = Date.now() + (limite || 120000);
  while (Date.now() < fin) {
    try {
      await page.waitForFunction(() => {
        const S = window.SIGH && window.SIGH.store; if (!S) return false;
        if (/error-403|\/auth-|\/index\.php/.test(location.pathname)) return true;
        if (S.faitAutorite && !S.faitAutorite()) return false;
        const c = document.getElementById('page-content'); return !!(c && c.children.length > 0);
      }, { timeout: 4000 });
      return true;
    } catch (e) { /* rechargement ou pas prêt */ }
  }
  return false;
}

async function ouvrir(page, ecran, role, opts) {
  opts = opts || {};
  if (!page.url().startsWith('http')) { await page.goto(`http://127.0.0.1:${PORT}/pages/aide-apropos.php`, { waitUntil: 'domcontentloaded' }); await attendrePeinture(page); }
  if (role) await poserRole(page, role);
  await page.evaluate((ouvert) => { try { window.SIGH.storage.set('sigh-cnt:ruban', ouvert ? 'ouvert' : 'ferme'); } catch (e) { /* socle absent */ } }, !!opts.ruban);
  const url = ecran.startsWith('/') ? `http://127.0.0.1:${PORT}${ecran}` : `http://127.0.0.1:${PORT}/pages/${ecran}.php`;
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  await attendrePeinture(page);
  /* Le ruban : replié pour montrer l'écran, déplié seulement quand la capture le montre. Bouton « Réduire le menu / Afficher le menu ». */
  await page.evaluate((ouvert) => {
    const p = document.getElementById('app-ribbon'); const btn = document.querySelector('button[aria-controls="app-ribbon"]');
    if (p && btn && p.hidden === ouvert) btn.click();
  }, !!opts.ruban);
  await new Promise((r) => setTimeout(r, 900));
  /* Les notifications éphémères ne doivent pas encombrer la capture. */
  await page.evaluate(() => { const h = document.querySelector('#toast-host'); if (h) h.innerHTML = ''; });
}

/** Trouve un élément visible par sélecteur CSS ou par texte exact (préfixe « texte: »). */
async function trouver(page, cible) {
  return page.evaluateHandle((c) => {
    const vis = (el) => { const r = el.getBoundingClientRect(); return r.width > 2 && r.height > 2 && getComputedStyle(el).visibility !== 'hidden'; };
    if (c.startsWith('texte:') || c.startsWith('contient:')) {
      const exact = c.startsWith('texte:'); const t = c.replace(/^(texte|contient):/, '').trim();
      const els = [...document.querySelectorAll('button, a, [role=tab], label, th, h1, h2, h3, summary, span, div, li')].filter(vis);
      const net = (el) => el.textContent.replace(/\s+/g, ' ').trim();
      let el = els.find((e) => (exact ? net(e) === t : net(e).includes(t)) && /^(BUTTON|A)$/.test(e.tagName));
      if (!el) el = els.filter((e) => (exact ? net(e) === t : net(e).includes(t))).sort((a, b) => a.textContent.length - b.textContent.length)[0];
      return el || null;
    }
    return [...document.querySelectorAll(c)].find(vis) || null;
  }, cible);
}

/** Pose un cadre rouge vif (et une étiquette numérotée) autour de chaque cible ; rend les cibles non trouvées. */
async function annoter(page, cibles) {
  const manquantes = [];
  let n = 0;
  for (const c of cibles) {
    n++;
    const h = await trouver(page, c);
    const el = h && h.asElement();
    if (!el) { manquantes.push(c); continue; }
    if (n === 1) await el.evaluate((e) => { const r = e.getBoundingClientRect(); if (r.bottom > window.innerHeight - 20 || r.top < 0) e.scrollIntoView({ block: 'center', behavior: 'instant' }); });
    await el.evaluate((e, num, total) => {
      const r = e.getBoundingClientRect(); const m = 4;
      const cadre = document.createElement('div');
      cadre.className = 'annot-manuel';
      const sx = window.scrollX, sy = window.scrollY;
      Object.assign(cadre.style, { position: 'absolute', left: (r.left + sx - m) + 'px', top: (r.top + sy - m) + 'px', width: (r.width + 2 * m) + 'px', height: (r.height + 2 * m) + 'px',
        border: '3px solid #e11d1d', borderRadius: '6px', boxShadow: '0 0 0 3px rgba(225,29,29,.25)', zIndex: 2147483646, pointerEvents: 'none' });
      document.body.appendChild(cadre);
      if (total > 1) {
        const b = document.createElement('div'); b.className = 'annot-manuel'; b.textContent = String(num);
        const gauche = r.left - 14 < 2 ? r.right + 2 : r.left - 14;
        Object.assign(b.style, { position: 'absolute', left: (gauche + sx) + 'px', top: (r.top + sy - 14) + 'px', width: '24px', height: '24px', borderRadius: '50%', background: '#e11d1d', color: '#fff',
          font: '700 13px/24px Arial, sans-serif', textAlign: 'center', zIndex: 2147483647, pointerEvents: 'none' });
        document.body.appendChild(b);
      }
    }, n, cibles.length);
  }
  return manquantes;
}

async function effacerAnnotations(page) { await page.evaluate(() => document.querySelectorAll('.annot-manuel').forEach((e) => e.remove())); }

module.exports = { ROOT, PORT, ouvrirNavigateur, poserRole, ouvrir, attendrePeinture, trouver, annoter, effacerAnnotations, NOM_DEMO };

/** Remplace dans la page les noms du personnel (collection `personnel`) par un nom neutre : aucune capture ne montre un agent réel. */
async function masquer(page) {
  await page.evaluate(() => {
    let noms = [];
    try {
      const P = window.SIGH.store.collection('personnel').all() || [];
      P.forEach((p) => {
        const n = (p.nom || '').trim(); const pr = (p.prenom || p.prenoms || '').trim();
        if (n && pr) { noms.push(n + ' ' + pr, pr + ' ' + n); }
        if (p.nomComplet) noms.push(String(p.nomComplet).trim());
      });
    } catch (e) { /* magasin absent */ }
    noms = [...new Set(noms.filter((x) => x.length > 5))].sort((a, b) => b.length - a.length);
    if (!noms.length) return;
    const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    const nodes = []; while (w.nextNode()) nodes.push(w.currentNode);
    nodes.forEach((t) => { let v = t.nodeValue; let ch = false; noms.forEach((n) => { if (v.includes(n)) { v = v.split(n).join('Agent de démonstration'); ch = true; } }); if (ch) t.nodeValue = v; });
    document.querySelectorAll('option, input').forEach((o) => { noms.forEach((n) => { if (o.textContent && o.textContent.includes(n)) o.textContent = o.textContent.split(n).join('Agent de démonstration'); if (o.value && o.tagName === 'INPUT' && o.value.includes(n)) o.value = o.value.split(n).join('Agent de démonstration'); }); });
  });
}
module.exports.masquer = masquer;
