/* =============================================================================
 * SIGH-CNT : LE DOSSIER « presentation » : un spécimen de chaque état imprimé
 * -----------------------------------------------------------------------------
 * Régénère `presentation/` (à la racine du dépôt) : un PDF par état imprimé du
 * logiciel, rangé par module, une page de consultation et un sommaire.
 *
 *   node build/presentation.js                  les trois phases, un seul poste
 *   node build/presentation.js --phase=capture  pilote la maquette, relève les états
 *   node build/presentation.js --phase=pdf      substitue les identités, rend les PDF
 *   node build/presentation.js --phase=index    index.html, README.md, contrôle
 *
 * Options : --worker=i/n (répartit les écrans entre n processus, chacun avec son
 * serveur PHP, son port et sa base), --modules=M8,M9, --pages=a,b, --max=N.
 *
 * MÉTHODE. Les états ne sont JAMAIS redessinés : la maquette est pilotée dans
 * Chrome (banc isolé, horloge décalée sur la date du jeu), les points d'entrée
 * de `SIGH.print` (etat, ticket, badge, planche) sont enveloppés, et la feuille
 * que le logiciel vient de bâtir est relevée telle quelle (HTML), avec le site
 * d'appel (fichier:ligne) lu dans la pile. Le PDF est obtenu en rendant cette
 * feuille dans un document propre qui charge la MÊME feuille de style.
 *
 * CONFIDENTIALITÉ. Le jeu de démonstration porte les noms du personnel réel de
 * l'organigramme : une table de substitution déterministe (jetons de noms,
 * téléphones, numéros CNSS) est appliquée au texte AVANT le PDF, et le contrôle
 * final relit la couche texte des PDF (pdftotext) à la recherche de tout nom réel.
 *
 * Aucun fichier de l'application n'est modifié : ce script ne lit que.
 * ========================================================================== */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const DEPOT = path.resolve(ROOT, '..');
const SORTIE = path.join(DEPOT, 'presentation');
const arg = (n, d) => { const m = process.argv.find((a) => a.indexOf('--' + n + '=') === 0); return m ? m.slice(n.length + 3) : d; };
const FLAG = (n) => process.argv.indexOf('--' + n) >= 0;
const PHASE = arg('phase', 'tout');
const TMP = process.env.SIGH_PRES_TMP || path.join(os.tmpdir(), 'sigh-presentation');
const WORKER = (arg('worker', '0/1')).split('/').map(Number);
const MAX_PAR_SITE = 6;

function slug(s) {
  return String(s || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase()
    .replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 70) || 'etat';
}
function attendre(ms) { return new Promise((r) => setTimeout(r, ms)); }
function trouverChrome() {
  for (const c of [process.env.CHROME_PATH, '/opt/pw-browsers/chromium', 'C:/Program Files/Google/Chrome/Application/chrome.exe']) {
    if (c && fs.existsSync(c)) return c;
  }
  return null;
}

/* --------------------------------------------------------------------------
 * Serveur de fichiers local (les états chargent la feuille de style et le logo).
 * `relais` : si fourni, `/api/` est relayé vers PHP (phase capture).
 * ----------------------------------------------------------------------- */
const MIME = { '.php': 'text/html; charset=utf-8', '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml', '.webp': 'image/webp', '.woff2': 'font/woff2', '.woff': 'font/woff', '.ttf': 'font/ttf' };
function servirFichiers(port, relais) {
  return new Promise((resolve) => {
    const srv = http.createServer((req, res) => {
      const u = decodeURIComponent((req.url || '/').split('?')[0]);
      if (relais && u.indexOf('/api/') === 0) return relais(req, res);
      let f = path.join(ROOT, u);
      if (f.indexOf(ROOT) !== 0 || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end('404'); }
      let corps = fs.readFileSync(f);
      /* Les pages sont des `.php` qui ne contiennent que du HTML statique : on les sert telles quelles. */
      res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream', 'Content-Length': corps.length });
      res.end(corps);
    });
    srv.listen(port, '127.0.0.1', () => resolve(srv));
  });
}

/* --------------------------------------------------------------------------
 * Inventaire des sites d'impression dans les sources (couverture).
 * ----------------------------------------------------------------------- */
function inventaireSites() {
  const dossiers = [path.join(ROOT, 'assets/js'), path.join(ROOT, 'assets/js/modules')];
  const sites = [];
  const vus = new Set();
  dossiers.forEach((d) => {
    fs.readdirSync(d).filter((f) => f.endsWith('.js')).forEach((f) => {
      if (f === 'print.js') return;
      const rel = path.relative(ROOT, path.join(d, f)).split(path.sep).join('/');
      if (vus.has(rel)) return; vus.add(rel);
      const lignes = fs.readFileSync(path.join(d, f), 'utf8').split('\n');
      lignes.forEach((l, i) => {
        const code = l.replace(/\/\*.*?\*\//g, '').replace(/\/\/.*$/, '');
        const re = /\b(?:P|print|SIGH\.print|Print)\.(etat|ticket|badge|planche|tableau)\s*\(/g;
        let m;
        while ((m = re.exec(code))) {
          const fenetre = lignes.slice(i, i + 10).join(' ');
          const t = /titre:\s*['"`]([^'"`]{3,80})/.exec(fenetre);
          sites.push({ cle: rel + ':' + (i + 1), fichier: rel, ligne: i + 1, type: m[1], titre: t ? t[1] : null });
        }
      });
    });
  });
  return sites;
}

/* ==========================================================================
 * PHASE 1 : CAPTURE
 * ======================================================================= */
const PRINT_RE = /imprim|éditer|edition|édition|reçu|bulletin|certificat|attestation|ordonnance|\bbon\b|facture|relevé|état|\bpdf\b|badge|planche|ticket|fiche|compte rendu|rapport|courrier|quittance|justificatif|arrêté|registre|liasse|balance|grand livre|journal|bilan|lettre|convocation|planning|résultat|aperçu|prévisualis|printer|file-text|receipt|file-down|file-check|clipboard/i;
const EXCLU_RE = /^(nouveau|nouvelle|ajouter|créer|archiver|supprimer|restaurer|annuler|encaisser|clôturer|cloturer|modifier|enregistrer|fermer|filtrer|rechercher|colonnes|exporter$|tout |rafra|actualiser|réinitialiser|se déconnecter|déconnexion|retour|précédent|suivant|\d+$)/i;
const DIALOGUE_RE = /^(éditer|imprimer|générer|afficher|aperçu|prévisualiser|lancer|continuer|confirmer|valider|émettre|emettre|enregistrer|oui|ok|calculer|établir|produire|exporter en pdf)\b/i;

/* Scénarios ciblés : gestes que l'exploration générique ne sait pas faire seule (encaisser, valider une fenêtre,
   cocher une sélection). Chaque étape est [portée, expression]; la portée est « page » ou « dialog ». */
const SCENARIOS = [
  { page: 'm9-compagnies', etapes: [['page', '^Exporter$'], ['dialog', 'PDF / Impression'], ['recharger', ''], ['case', ''], ['page', 'Imprimer la sélection']] },
  { page: 'm8-facturation', etapes: [['page', 'Ajouter'], ['page', 'Ticket de caisse']] },
  { page: 'm8-caisse', etapes: [['page', 'Encaisser'], ['dialog', 'Tout cocher'], ['dialog', 'Valider l.encaissement'], ['dialog', 'Imprimer le reçu']] },
  { page: 'm8-facture-avoir', etapes: [['page', 'Émettre un avoir'], ['combos', ''], ['cases', ''], ['remplir', ''], ['dialog', 'Émettre l.avoir'], ['recharger', ''], ['ligne', ''], ['dialog', 'Imprimer l.avoir']] },
  { page: 'm12-immobilisations', etapes: [['page', 'Report au bilan'], ['page', 'Imprimer le report']] },
  { page: 'm10-badges-impression', etapes: [['case', ''], ['passe', '']] },
  { page: 'm3-bons-pansements', etapes: [['page', 'Nouveau bon'], ['combos', ''], ['remplir', ''], ['dialog', 'Enregistrer|Créer|Valider|Émettre'], ['passe', '']] },
  { page: 'm3-sortie-avis-medical', etapes: [['page', 'Enregistrer'], ['combos', ''], ['remplir', ''], ['dialog', 'Consigner|Enregistrer'], ['passe', '']] },
  { page: 'm3-cr-anesthesie', etapes: [['page', 'Nouveau compte rendu'], ['combos', ''], ['remplir', ''], ['dialog', 'Enregistrer|Créer|Valider|Émettre'], ['passe', '']] },
  { page: 'm3-demande-examen', etapes: [['page', 'Nouvelle fiche'], ['combos', ''], ['cases', ''], ['remplir', ''], ['dialog', 'Enregistrer|Créer|Valider|Émettre'], ['passe', '']] },
  { page: 'm6-inventaire', etapes: [['page', 'Lancer un inventaire'], ['combos', ''], ['remplir', ''], ['passe', '']] },
  { page: 'm2-dossier-consultation-nouveau', etapes: [['combos', ''], ['remplir', ''], ['page', 'Enregistrer le dossier'], ['passe', '']] },
  { page: 'mecef-avoirs', etapes: [['page', 'Émettre un avoir'], ['combos', ''], ['cases', ''], ['remplir', ''], ['dialog', 'Émettre|Enregistrer|Créer'], ['passe', '']] },
  { page: 'm9-relances', etapes: [['page', 'Nouvelle relance'], ['combos', ''], ['remplir', ''], ['dialog', 'Enregistrer|Créer|Valider|Émettre'], ['passe', '']] },
  { page: 'm8-remboursements', etapes: [['page', 'Nouvelle opération'], ['combos', ''], ['remplir', ''], ['dialog', 'Enregistrer|Créer|Valider|Émettre'], ['passe', '']] },
];

/* Fonctions injectées dans chaque document : elles ne dépendent de SIGH qu'à l'installation. */
function instrumentation() {
  window.__pres = {
    caps: [], sites: {}, tab: {}, n: 0,
    siteDe() {
      const pile = (new Error()).stack.split('\n').slice(1);
      for (const l of pile) {
        if (/print\.js/.test(l)) continue;
        const m = /(assets\/js\/[^\s):]+\.js):(\d+):\d+/.exec(l);
        if (m) return m[1] + ':' + m[2];
      }
      return null;
    },
    installer() {
      const P = window.SIGH && window.SIGH.print; if (!P || P.__pres) return false;
      const me = this;
      ['etat', 'ticket', 'badge', 'planche'].forEach((nom) => {
        const orig = P[nom];
        P[nom] = function () {
          const site = me.siteDe();
          if (site) me.sites[site] = (me.sites[site] || 0) + 1;
          let r, err = null;
          try { r = orig.apply(this, arguments); } catch (e) { err = e; }
          try { me.releve(nom, site, arguments); } catch (e) { /* relevé impossible */ }
          if (err) throw err;
          return r;
        };
      });
      const tabl = P.tableau;
      P.tableau = function () { const site = me.siteDe(); if (site) me.tab[site] = (me.tab[site] || 0) + 1; return tabl.apply(this, arguments); };
      P.__pres = true;
      return true;
    },
    releve(nom, site, args) {
      const overlays = document.querySelectorAll('.print-chrome');
      const ov = overlays[overlays.length - 1]; if (!ov) return;
      const feuille = ov.querySelector('.print-sheet') || ov.querySelector('article');
      if (!feuille) return;
      const cadre = feuille.parentElement;
      const span = ov.querySelector('span');
      const o = (args[0] && typeof args[0] === 'object') ? args[0] : {};
      this.caps.push({
        fonction: nom, site: site, titre: ((span && span.textContent) || o.titre || nom).trim(),
        largeur: (cadre && cadre.style && cadre.style.width) || '210mm',
        html: feuille.outerHTML,
      });
      ov.remove();
      const r = document.getElementById('print-root'); if (r) r.innerHTML = '';
      document.body.style.overflow = '';
    },
    vider() { const c = this.caps; this.caps = []; return c; },
    lister(racines) {
      const out = [];
      document.querySelectorAll(racines).forEach((racine) => {
        racine.querySelectorAll('button, [role=button]').forEach((el) => {
          if (el.closest('#app-topbar, #app-menubar, #app-ribbon, #toast-host, .print-chrome')) return;
          const r = el.getBoundingClientRect(); if (!r.width && !r.height) return;
          if (el.disabled || el.getAttribute('aria-disabled') === 'true') return;
          if (el.getAttribute('role') === 'tab') return;
          const svg = el.querySelector('svg, i[data-lucide]');
          const icone = svg ? ((svg.getAttribute('class') || '') + ' ' + (svg.getAttribute('data-lucide') || '')) : '';
          const texte = (el.textContent || '').replace(/\s+/g, ' ').trim();
          const titre = ((el.title || '') + ' ' + (el.getAttribute('aria-label') || '')).trim();
          const id = 'p' + (++this.n); el.setAttribute('data-pres', id);
          out.push({ id: id, texte: texte, titre: titre, icone: icone, dialogue: !!el.closest('[role=dialog]') });
        });
      });
      return out;
    },
    clic(id) { const el = document.querySelector('[data-pres="' + id + '"]'); if (!el) return false; el.click(); return true; },
    onglets() {
      return Array.prototype.map.call(document.querySelectorAll('#page-content [role=tab]'), (b, i) => ({ id: i, texte: (b.textContent || '').trim().slice(0, 40) }));
    },
    ongletClic(i) { const el = document.querySelectorAll('#page-content [role=tab]')[i]; if (el) el.click(); return !!el; },
    lignes() {
      return Array.prototype.map.call(document.querySelectorAll('#page-content tbody tr'), (tr, i) => {
        const r = tr.getBoundingClientRect(); if (!r.width) return null;
        tr.setAttribute('data-pres-tr', 'r' + i); return 'r' + i;
      }).filter(Boolean).slice(0, 2);
    },
    ligneClic(id) { const el = document.querySelector('[data-pres-tr="' + id + '"]'); if (el) { el.click(); } return !!el; },
    dialogues() { return document.querySelectorAll('[role=dialog]').length; },
    fermerDialogues() {
      let n = 0;
      document.querySelectorAll('[role=dialog]').forEach((d) => {
        const b = Array.prototype.find.call(d.querySelectorAll('button'), (x) => /^(fermer|annuler|×|x)$/i.test((x.textContent || '').trim()) || /fermer|close/i.test((x.getAttribute('aria-label') || x.title || '')));
        if (b) { b.click(); n++; }
      });
      document.querySelectorAll('[role=dialog]').forEach((d) => d.remove());
      document.body.style.overflow = '';
      return n;
    },
    agir(scope, re) {
      const R = new RegExp(re, 'i'); let hit = null;
      const sel = scope === 'dialog' ? '[role=dialog]' : '#page-content, #page-actions';
      document.querySelectorAll(sel).forEach((r) => r.querySelectorAll('button, [role=button], tbody tr, [role=tab], input[type=checkbox]').forEach((b) => {
        if (hit) return; const rc = b.getBoundingClientRect(); if (!rc.width) return;
        if (b.closest('#app-topbar, #app-menubar, #app-ribbon, .print-chrome')) return;
        const t = ((b.textContent || '') + ' ' + (b.title || '') + ' ' + (b.getAttribute('aria-label') || '')).trim();
        if (b.tagName === 'INPUT' ? re === 'CASE' : R.test(t)) hit = b;
      }));
      if (!hit) return null; hit.click(); return (hit.textContent || hit.tagName).trim().slice(0, 40);
    },
    choisir(scope, n, k) {
      const racine = scope === 'dialog' ? document.querySelector('[role=dialog]') : document.getElementById('page-content');
      if (!racine) return null;
      const b = racine.querySelectorAll('button.combo-input')[n]; if (!b) return null;
      b.click();
      const p = Array.prototype.find.call(document.querySelectorAll('.combo-panel'), (x) => !x.hidden);
      const o = p && p.querySelectorAll('.combo-option')[k]; if (!o) { b.click(); return null; }
      o.dispatchEvent(new MouseEvent('mousedown', { bubbles: true })); o.click();
      return (o.textContent || '').trim().slice(0, 40);
    },
    combosVides(scope) {
      const racine = scope === 'dialog' ? document.querySelector('[role=dialog]') : document.getElementById('page-content');
      if (!racine) return 0; let n = 0;
      racine.querySelectorAll('button.combo-input').forEach((b, i) => {
        const v = b.querySelector('.combo-value'); const t = (v && v.textContent || '').trim();
        if (!t || /^—/.test(t) || (v && v.classList.contains('text-slate-400'))) { const r = this.choisir(scope, i, 0); if (r) n++; }
      });
      return n;
    },
    remplir(scope) {
      const racine = scope === 'dialog' ? document.querySelector('[role=dialog]') : document.getElementById('page-content');
      if (!racine) return 0; let n = 0;
      racine.querySelectorAll('textarea, input[type=text], input:not([type])').forEach((i) => {
        if (i.value || i.classList.contains('combo-search') || i.type === 'search' || i.disabled) return;
        i.value = 'Spécimen de démonstration'; i.dispatchEvent(new Event('input', { bubbles: true })); i.dispatchEvent(new Event('change', { bubbles: true })); n++;
      });
      racine.querySelectorAll('input[type=date], input[type=datetime-local], input[type=time]').forEach((i) => {
        if (i.value || i.disabled) return;
        const d = new Date(), z = (x) => String(x).padStart(2, '0');
        const jour = d.getFullYear() + '-' + z(d.getMonth() + 1) + '-' + z(d.getDate());
        i.value = i.type === 'date' ? jour : (i.type === 'time' ? z(d.getHours()) + ':' + z(d.getMinutes()) : jour + 'T' + z(d.getHours()) + ':' + z(d.getMinutes()));
        i.dispatchEvent(new Event('input', { bubbles: true })); i.dispatchEvent(new Event('change', { bubbles: true })); n++;
      });
      return n;
    },
    peint() { const c = document.getElementById('page-content'); return !!(c && c.children.length && c.textContent.trim().length > 20); },
    chemin() { return location.pathname; },
  };
}

async function capture() {
  const puppeteer = require('puppeteer');
  const i = WORKER[0], n = WORKER[1];
  const portPhp = Number(process.env.SIGH_PORT_PHP || (8921 + 10 + 4 * i));
  const portWeb = portPhp + 1;
  process.env.SIGH_PORT_PHP = String(portPhp);
  process.env.SIGH_BASE_TEST = process.env.SIGH_BASE_TEST || (i === 0 ? 'sigh_banc_l11' : 'sigh_banc_l11' + String.fromCharCode(97 + i));
  const BANC = require('./_banc.js');
  const dem = await BANC.demarrerPhp(ROOT);
  if (!dem.php) { console.error('PHP KO : ' + dem.raison); process.exit(1); }
  const web = await servirFichiers(portWeb, BANC.relayer);
  console.log('[worker ' + i + '/' + n + '] php ' + portPhp + ' web ' + portWeb + ' base ' + process.env.SIGH_BASE_TEST);
  await BANC.banc('reinitialiser');
  const chrome = trouverChrome();
  const lancerNavigateur = () => puppeteer.launch({ executablePath: chrome, headless: true, args: ['--no-sandbox'] });
  let browser = await lancerNavigateur();

  /* Liste des écrans : fichiers de pages, sans connexion, erreurs, hubs, enquête publique. */
  let pages = fs.readdirSync(path.join(ROOT, 'pages')).filter((f) => f.endsWith('.php')).map((f) => f.slice(0, -4))
    .filter((id) => !/^(hub-|auth-|error-)/.test(id) && id !== 'enquete-publique').sort();
  if (arg('pages')) pages = arg('pages').split(',');
  pages = pages.filter((p, k) => k % n === i);
  const filtreModules = arg('modules') ? arg('modules').split(',') : null;
  const capDir = path.join(TMP, 'captures'); fs.mkdirSync(capDir, { recursive: true });
  const parSite = {}; const sitesTouches = {}; const tablTouches = {};
  const log = [];
  let pageIdx = 0;
  const maxPages = Number(arg('max', 100000));

  async function ouvrir(id) {
    const page = await browser.newPage();
    await page.setViewport({ width: 1440, height: 900 });
    await BANC.poserSession(page);
    await page.evaluateOnNewDocument(instrumentation);
    page.on('dialog', (d) => { d.dismiss().catch(() => {}); });
    const erreurs = [];
    page.on('pageerror', (e) => erreurs.push(String(e.message).slice(0, 160)));
    await page.goto('http://127.0.0.1:' + portWeb + '/pages/' + id + '.php', { waitUntil: 'domcontentloaded', timeout: 120000 });
    let ok = false;
    for (let k = 0; k < 90; k++) {
      await attendre(500);
      try { if (await page.evaluate(() => window.__pres && window.__pres.peint() && window.SIGH && window.SIGH.print)) { ok = true; break; } } catch (e) { /* contexte détruit */ }
    }
    if (ok) { await attendre(700); await page.evaluate(() => window.__pres.installer()); }
    return { page, ok, erreurs };
  }

  async function relever(page, id, moduleInfo, contexte, etiquette, compteur) {
    let caps = [];
    try { caps = await page.evaluate(() => window.__pres.vider()); } catch (e) { return 0; }
    let gardes = 0;
    for (const c of caps) {
      const cle = c.site + '|' + c.titre.replace(/[0-9]+/g, '#').replace(/\s+/g, ' ');
      parSite[c.site] = parSite[c.site] || new Set();
      if (parSite[c.site].has(cle)) continue;
      if (parSite[c.site].size >= MAX_PAR_SITE) continue;
      parSite[c.site].add(cle);
      const dossier = path.join(capDir, id); fs.mkdirSync(dossier, { recursive: true });
      const nom = String(Object.keys(parSite).length).padStart(4, '0') + '-' + slug(c.titre) + '.json';
      fs.writeFileSync(path.join(dossier, nom), JSON.stringify(Object.assign({ pageId: id, module: moduleInfo.module, moduleLabel: moduleInfo.moduleLabel, ecran: moduleInfo.label, declencheur: etiquette, contexte: contexte }, c)));
      gardes++;
    }
    return caps.length;
  }

  for (const id of pages) {
    if (pageIdx++ >= maxPages) break;
    const t0 = Date.now();
    fs.rmSync(path.join(capDir, id), { recursive: true, force: true });
    let ctx = null;
    const travail = (async () => {
    try {
      ctx = await ouvrir(id);
      if (!ctx.ok) { log.push({ page: id, statut: 'non peinte' }); try { await ctx.page.close(); } catch (e) {} return; }
      const { page } = ctx;
      const info = await page.evaluate((i) => { const e = window.SIGH.nav.INDEX[i]; return e ? { module: e.module, moduleLabel: e.moduleLabel, label: e.label } : { module: 'HORS', moduleLabel: 'Hors ruban', label: i }; }, id);
      if (filtreModules && filtreModules.indexOf(info.module) < 0) { await page.close(); return; }
      const clics = new Set();
      let nbEtats = 0;
      const url0 = await page.evaluate(() => window.__pres.chemin());

      async function retablir() {
        const c = await page.evaluate(() => window.__pres.chemin()).catch(() => null);
        if (c !== url0) {
          await collecter();
          await page.goto('http://127.0.0.1:' + portWeb + '/pages/' + id + '.php', { waitUntil: 'domcontentloaded', timeout: 120000 }).catch(() => {});
          for (let k = 0; k < 60; k++) { await attendre(500); if (await page.evaluate(() => window.__pres && window.__pres.peint() && window.SIGH && window.SIGH.print).catch(() => false)) break; }
          await attendre(500); await page.evaluate(() => window.__pres.installer()).catch(() => {});
          return true;
        }
        return false;
      }

      async function passe(contexte, racines) {
        for (let tour = 0; tour < 14; tour++) {
          if (Date.now() - t0 > 100000) return;
          const cands = await page.evaluate((r) => window.__pres.lister(r), racines).catch(() => []);
          const ciblee = cands.find((c) => {
            const lib = (c.texte + ' ' + c.titre + ' ' + c.icone);
            if (EXCLU_RE.test(c.texte.trim()) && !/pdf|imprim/i.test(c.titre + c.icone)) return false;
            if (!PRINT_RE.test(lib)) return false;
            return !clics.has(contexte + '|' + c.dialogue + '|' + c.texte + '|' + c.titre + '|' + c.icone);
          });
          if (!ciblee) return;
          clics.add(contexte + '|' + ciblee.dialogue + '|' + ciblee.texte + '|' + ciblee.titre + '|' + ciblee.icone);
          await page.evaluate((x) => window.__pres.clic(x), ciblee.id).catch(() => {});
          await attendre(450);
          let vus = await relever(page, id, info, contexte, ciblee.texte || ciblee.titre);
          if (!vus) {
            /* Une fenêtre s'est ouverte : on tente d'en valider une étape (période, filtre, confirmation). */
            for (let etape = 0; etape < 3 && !vus; etape++) {
              const nd = await page.evaluate(() => window.__pres.dialogues()).catch(() => 0);
              if (!nd) break;
              const dc = await page.evaluate((r) => window.__pres.lister(r), '[role=dialog]').catch(() => []);
              const pos = dc.find((c) => DIALOGUE_RE.test(c.texte.trim()) && !clics.has('d|' + contexte + '|' + c.texte + etape + ciblee.texte));
              if (!pos) break;
              clics.add('d|' + contexte + '|' + pos.texte + etape + ciblee.texte);
              await page.evaluate((x) => window.__pres.clic(x), pos.id).catch(() => {});
              await attendre(500);
              vus = await relever(page, id, info, contexte, ciblee.texte + ' > ' + pos.texte);
            }
          }
          nbEtats += vus;
          await page.evaluate(() => window.__pres.fermerDialogues()).catch(() => {});
          if (await retablir()) { /* la page a navigué : on la rouvre, la liste des clics est conservée */ }
        }
      }

      async function contexteComplet(contexte) {
        await passe(contexte, '#page-actions, #page-content');
        /* Fiches : une ligne de tableau ouvre un tiroir qui porte ses propres commandes. */
        const lignes = await page.evaluate(() => window.__pres.lignes()).catch(() => []);
        for (const l of lignes) {
          if (Date.now() - t0 > 100000) return;
          await page.evaluate((x) => window.__pres.ligneClic(x), l).catch(() => {});
          await attendre(500);
          if (await page.evaluate(() => window.__pres.dialogues()).catch(() => 0)) await passe(contexte + '|ligne', '[role=dialog]');
          await page.evaluate(() => window.__pres.fermerDialogues()).catch(() => {});
          await retablir();
        }
      }

      await contexteComplet('base');
      const onglets = await page.evaluate(() => window.__pres.onglets()).catch(() => []);
      for (const o of onglets.slice(0, 12)) {
        if (Date.now() - t0 > 100000) break;
        await page.evaluate((x) => window.__pres.ongletClic(x), o.id).catch(() => {});
        await attendre(500);
        await contexteComplet('onglet:' + o.texte);
        await retablir();
      }
      async function collecter() {
        const stats = await page.evaluate(() => ({ s: window.__pres.sites, t: window.__pres.tab })).catch(() => ({ s: {}, t: {} }));
        Object.keys(stats.s).forEach((k) => { sitesTouches[k] = (sitesTouches[k] || 0) + stats.s[k]; });
        Object.keys(stats.t).forEach((k) => { tablTouches[k] = (tablTouches[k] || 0) + stats.t[k]; });
      }
      await collecter();
      for (const sc of SCENARIOS.filter((x) => x.page === id)) {
        await page.goto('http://127.0.0.1:' + portWeb + '/pages/' + id + '.php', { waitUntil: 'domcontentloaded', timeout: 120000 }).catch(() => {});
        for (let k = 0; k < 60; k++) { await attendre(500); if (await page.evaluate(() => window.__pres && window.__pres.peint() && window.SIGH && window.SIGH.print).catch(() => false)) break; }
        await attendre(600); await page.evaluate(() => window.__pres.installer()).catch(() => {});
        let ok = true;
        for (const [portee, re] of sc.etapes) {
          let r;
          if (portee === 'combos') { for (let t = 0; t < 3; t++) { await page.evaluate(() => window.__pres.combosVides('dialog')).catch(() => 0); await attendre(300); await page.evaluate(() => window.__pres.combosVides('page')).catch(() => 0); await attendre(300); } r = 'ok'; }
          else if (portee === 'remplir') { await page.evaluate(() => { window.__pres.remplir('dialog'); window.__pres.remplir('page'); }).catch(() => 0); r = 'ok'; }
          else if (portee === 'combo') { const [cn, ck] = re.split(':').map(Number); r = await page.evaluate((x, y) => window.__pres.choisir('dialog', x, y) || window.__pres.choisir('page', x, y), cn, ck).catch(() => null); }
          else if (portee === 'ligne') { r = await page.evaluate(() => { const tr = document.querySelector('#page-content tbody tr'); if (!tr) return null; tr.click(); return 'ligne'; }).catch(() => null); }
          else if (portee === 'cases') { r = await page.evaluate(() => { const rac = document.querySelector('[role=dialog]') || document.getElementById('page-content'); let n = 0; rac.querySelectorAll('input[type=checkbox]').forEach((c) => { if (!c.checked && !c.disabled) { c.click(); n++; } }); return 'cases ' + n; }).catch(() => null); }
          else if (portee === 'case') { r = await page.evaluate(() => { const c = document.querySelector('#page-content thead input[type=checkbox], #page-content input[type=checkbox]'); if (!c) return null; c.click(); return 'case'; }).catch(() => null); }
          else if (portee === 'recharger') {
            await page.goto('http://127.0.0.1:' + portWeb + '/pages/' + id + '.php', { waitUntil: 'domcontentloaded', timeout: 120000 }).catch(() => {});
            for (let k = 0; k < 60; k++) { await attendre(500); if (await page.evaluate(() => window.__pres && window.__pres.peint() && window.SIGH && window.SIGH.print).catch(() => false)) break; }
            await attendre(600); await page.evaluate(() => window.__pres.installer()).catch(() => {}); r = 'ok';
          }
          else if (portee === 'passe') { clics.clear(); await passe('scénario', '[role=dialog], #page-actions, #page-content'); r = 'ok'; }
          else r = await page.evaluate((a, b) => window.__pres.agir(a, b), portee, re).catch(() => null);
          if (r === null) { console.log('  scénario ' + id + ' : étape introuvable ' + portee + ':' + re); ok = false; break; }
          await attendre(800);
          nbEtats += await relever(page, id, info, 'scénario', portee + ':' + re);
          if (process.env.PRES_DEBUG) console.log('    étape', portee, re, '=>', r, '| toast:', await page.evaluate(() => { const t = document.getElementById('toast-host'); return t ? t.textContent.replace(/\s+/g, ' ').slice(0, 200) : ''; }).catch(() => ''));
        }
        log.push({ page: id, scenario: sc.etapes.map((e) => e[1]).join(' > '), abouti: ok });
      }
      await collecter();
      log.push({ page: id, module: info.module, etats: nbEtats, sites: Object.keys(sitesTouches).length, erreurs: ctx.erreurs.length, ms: Date.now() - t0 });
      console.log(id.padEnd(40), info.module.padEnd(6), 'états', nbEtats, 'sites', Object.keys(sitesTouches).length, (Date.now() - t0) + ' ms');
      await page.close();
    } catch (e) {
      log.push({ page: id, statut: 'erreur', detail: String(e.message).slice(0, 200) });
      console.log(id, 'ERREUR', String(e.message).slice(0, 120));
      try { if (ctx && ctx.page) await ctx.page.close(); } catch (e2) { /* déjà fermée */ }
    }
    })();
    /* Garde-fou : un écran qui fige le navigateur est abandonné, le navigateur relancé. */
    const issue = await Promise.race([travail.then(() => 'ok'), attendre(170000).then(() => 'delai')]);
    if (issue === 'delai' || !browser.connected) {
      log.push({ page: id, statut: 'erreur', detail: 'délai dépassé, navigateur relancé' });
      console.log(id, 'DELAI, navigateur relancé');
      try { await browser.close(); } catch (e) { /* mort */ }
      browser = await lancerNavigateur();
    }
  }

  /* Les identités du jeu : relevées UNE fois, sur le premier poste. */
  if (i === 0) {
    const page = await browser.newPage();
    await BANC.poserSession(page);
    await page.goto('http://127.0.0.1:' + portWeb + '/pages/m10-personnel.php', { waitUntil: 'domcontentloaded' }).catch(() => {});
    for (let k = 0; k < 60; k++) { await attendre(500); if (await page.evaluate(() => !!(window.SIGH && window.SIGH.store && window.SIGH.data)).catch(() => false)) break; }
    await attendre(1500);
    const ident = await page.evaluate(() => {
      const S = window.SIGH.store, out = { personnel: [], titulaires: [], comptes: [], session: null };
      try { out.personnel = S.collection('personnel').all().map((p) => ({ nom: p.nom, prenom: p.prenom, nomComplet: p.nomComplet, telephone: p.telephone, cnss: p.cnss, matricule: p.matricule, salaireBase: p.salaireBase })); } catch (e) {}
      try { (function walk(n) { if (n.titulaire) out.titulaires.push(n.titulaire); (n.enfants || []).forEach(walk); })(window.SIGH.data.ORGANIGRAMME.racine); } catch (e) {}
      ['comptes', 'utilisateurs', 'soignants'].forEach((c) => { try { out.comptes = out.comptes.concat(S.collection(c).all().map((x) => ({ nom: x.nom || x.nomComplet || x.libelle, identifiant: x.identifiant, telephone: x.telephone }))); } catch (e) {} });
      try { out.session = S.session(); } catch (e) {}
      return out;
    }).catch((e) => ({ erreur: String(e.message) }));
    fs.writeFileSync(path.join(TMP, 'identites.json'), JSON.stringify(ident));
    await page.close();
  }

  fs.writeFileSync(path.join(TMP, 'releve-' + i + (arg('pages') ? '-sous-ensemble-' + Date.now() : '') + '.json'), JSON.stringify({ sites: sitesTouches, tableaux: tablTouches, log: log }));
  await browser.close(); web.close(); try { dem.php.kill(); } catch (e) {}
}

/* ==========================================================================
 * PHASE 2 : PDF (substitution des identités, filigrane, rendu)
 * ======================================================================= */
const POOL_NOMS = ['ADJOVI', 'SOSSA', 'HOUNKPATIN', 'AKPLOGAN', 'DOSSOU', 'KINGBO', 'TOGNIFODE', 'AGBO', 'LOKOSSOU', 'VODOUNON',
  'ZINSOU', 'AHOUANDJINOU', 'GLELE', 'ASSOGBA', 'DEGBE', 'HOUESSOU', 'AMOUSSOU', 'FADO', 'GNANSOUNOU', 'OKE', 'SAGBO', 'TCHIBOZO',
  'AZONHE', 'BIAOU', 'CAKPO', 'DAKO', 'EDAH', 'FASSINOU', 'GBAGUIDI', 'HOUNSA', 'IDOHOU', 'JOHNSON', 'KOUTON', 'LAWSON', 'MEDEGAN',
  'NOUATIN', 'OGOUNCHI', 'PADONOU', 'QUENUM', 'ROUSSEAU', 'SAKA', 'TOKPANOU', 'UNGUENON', 'VIGNON', 'WANKPO', 'YEHOUENOU', 'ZOUNON',
  'ABOKI', 'BONOU', 'CODJIA', 'DJOSSOU', 'EGOUNLETI', 'FOLLY', 'GANDONOU', 'HOUNGBO', 'ISSIAKA', 'KPADE', 'LEGBA', 'MONTCHO', 'NAGO',
  'ATCHADE', 'BANKOLE', 'CHABI', 'DANSOU', 'ESSOU', 'FAGLA', 'GOUDOU', 'HESSOU', 'IMOROU', 'JAKPOR', 'KEKE', 'LANTONKPODE', 'MATHIAS', 'NOUMON',
  'OLOUDE', 'POGNON', 'QUAKOU', 'RAHA', 'SOGLO', 'TOSSOU', 'UBALD', 'VIDEGLA', 'WADAGNI', 'YOVO', 'ZANNOU', 'AKOTEGNON', 'BOKO', 'CAPO', 'DOVONOU',
  'ELEGBEDE', 'FANOU', 'GOGAN', 'HODONOU', 'ITA', 'KAKPO', 'LISSANON', 'MEHOU', 'NATA', 'OROU', 'PRAGA', 'SEHOUETO', 'TCHOKPON'];
const POOL_PRENOMS = ['Marcelle', 'Théodore', 'Prisca', 'Gaspard', 'Colette', 'Fidèle', 'Judith', 'Anicet', 'Rosine', 'Clément', 'Estelle',
  'Barnabé', 'Sylvie', 'Rodolphe', 'Léontine', 'Isidore', 'Mireille', 'Casimir', 'Ursule', 'Basile', 'Odile', 'Thaddée', 'Nadège',
  'Cyriaque', 'Honorine', 'Maxime', 'Brigitte', 'Aristide', 'Pélagie', 'Lucien', 'Yolande', 'Hilaire', 'Séverine', 'Constant',
  'Annick', 'Gildas', 'Berthe', 'Narcisse', 'Euphrasie', 'Médard', 'Adélaïde', 'Romuald', 'Clarisse', 'Vianney', 'Perpétue',
  'Armand', 'Josiane', 'Fabrice', 'Gisèle', 'Hyacinthe', 'Irène', 'Landry', 'Mélanie', 'Octave', 'Philomène', 'Quentin', 'Reine',
  'Sidoine', 'Tatiana', 'Valéry', 'Aurélie', 'Bertrand', 'Chloé', 'Désiré', 'Éliane', 'Flavien', 'Ghislaine', 'Herbert', 'Inès', 'Jérémie', 'Karine',
  'Léopold', 'Mathilde', 'Noël', 'Océane', 'Pascal', 'Raïssa', 'Serge', 'Thérèse', 'Urbain', 'Virginie', 'Wilfried', 'Yvette', 'Zacharie', 'Albane', 'Bruno',
  'Cécile', 'Damien', 'Emmanuelle', 'Félix', 'Gabrielle', 'Hugues', 'Isabelle', 'Joël', 'Laure', 'Martial', 'Nicole', 'Olivier', 'Paulette', 'Rémi'];
const PARTICULES = /^(épse|epse|ep|dit|de|du|la|le|des|et|dr|pr|mme|mlle|m)$/i;

function jetons(chaine) {
  /* Trois lettres au moins, deux pour un nom de famille écrit en capitales (« YO »). */
  return String(chaine || '').split(/[\s\-]+/).map((t) => t.replace(/^[’'.,]+|[’'.,]+$/g, ''))
    .filter((t) => (t.length >= 3 || (t.length === 2 && t === t.toUpperCase() && /^\p{L}+$/u.test(t))) && !PARTICULES.test(t));
}

function tableSubstitution(ident) {
  const noms = new Map(), prenoms = new Map();
  const reels = []; /* pour le contrôle final */
  const ajouter = (p) => {
    jetons(p.nom).forEach((t) => { if (!noms.has(t.toUpperCase())) noms.set(t.toUpperCase(), null); });
    jetons(p.prenom).forEach((t) => { if (!prenoms.has(t.toUpperCase()) && !noms.has(t.toUpperCase())) prenoms.set(t.toUpperCase(), null); });
  };
  (ident.personnel || []).forEach(ajouter);
  (ident.titulaires || []).forEach((t) => {
    /* « NOM Prénom » : jetons en capitales = nom, autres = prénom. */
    String(t).split(/[\s]+/).forEach((tok) => {
      const j = jetons(tok)[0]; if (!j) return;
      if (j === j.toUpperCase()) { if (!noms.has(j.toUpperCase())) noms.set(j.toUpperCase(), null); }
      else if (!prenoms.has(j.toUpperCase()) && !noms.has(j.toUpperCase())) prenoms.set(j.toUpperCase(), null);
    });
  });
  const sess = ident.session || {};
  String(sess.nom || '').split(/\s+/).forEach((tok) => { const j = jetons(tok)[0]; if (!j) return;
    if (j === j.toUpperCase()) { if (!noms.has(j.toUpperCase())) noms.set(j.toUpperCase(), null); } else if (!prenoms.has(j.toUpperCase()) && !noms.has(j.toUpperCase())) prenoms.set(j.toUpperCase(), null); });
  const reelsMajuscules = new Set([...noms.keys(), ...prenoms.keys()]);
  /* Les fictifs ne doivent pas être des jetons réels. */
  const poolN = POOL_NOMS.filter((x) => !reelsMajuscules.has(x)), poolP = POOL_PRENOMS.filter((x) => !reelsMajuscules.has(x.toUpperCase()));
  let a = 0, b = 0;
  [...noms.keys()].sort().forEach((k) => { noms.set(k, poolN[a % poolN.length] + (a >= poolN.length ? String.fromCharCode(65 + Math.floor(a / poolN.length)) : '')); a++; });
  [...prenoms.keys()].sort().forEach((k) => { prenoms.set(k, poolP[b % poolP.length] + (b >= poolP.length ? 'a' : '')); b++; });
  const mapping = new Map([...noms, ...prenoms]);
  /* Téléphones et numéros CNSS : remplacés chiffre à chiffre par des suites fictives. */
  const nums = new Map();
  let q = 0;
  (ident.personnel || []).forEach((p) => {
    [p.telephone, p.cnss].forEach((v) => { const d = String(v || '').replace(/\D/g, ''); if (d.length >= 8 && !nums.has(d)) { nums.set(d, '0' + String(100000000 + (++q) * 7919).slice(-(d.length - 1))); } });
  });
  return { mapping, nums, reelsMajuscules };
}

/* Substituteur pur (sans DOM) : sert à la page de rendu ET aux intitulés, noms de fichiers et sommaires. */
function fabriquerRemplacer(donnees) {
  const map = new Map(donnees.mapping);
  const cles = [...map.keys()].sort((x, y) => y.length - x.length);
  const re = cles.length ? new RegExp('(?<![\\p{L}])(' + cles.map((k) => k.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|') + ')(?![\\p{L}])', 'giu') : null;
  const casse = (src, cible) => (src === src.toUpperCase() ? cible.toUpperCase() : (src === src.toLowerCase() ? cible.toLowerCase() : cible));
  const nums = donnees.nums;
  const reNum = nums.length ? new RegExp('(?<![0-9])(' + nums.map((n) => n[0].split('').join('[\\s.\\-]?')).join('|') + ')(?![0-9])', 'g') : null;
  function remplacer(s) {
    if (!s) return s;
    let r = s;
    if (re) r = r.replace(re, (m) => casse(m, map.get(m.toUpperCase()) || m));
    if (reNum) r = r.replace(reNum, (m) => { const d = m.replace(/\D/g, ''); const f = nums.find((x) => x[0] === d); return f ? f[1] : m; });
    return r;
  }
  return remplacer;
}

/* Exécuté dans la page de rendu : applique le substituteur à tout nœud texte et attribut. */
function substituerDansPage(src, donnees) {
  const remplacer = (new Function('return ' + src))()(donnees);
  const tw = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  let n; while ((n = tw.nextNode())) { const v = remplacer(n.nodeValue); if (v !== n.nodeValue) n.nodeValue = v; }
  document.querySelectorAll('*').forEach((el) => {
    ['title', 'alt', 'aria-label', 'placeholder', 'value'].forEach((a) => { const v = el.getAttribute(a); if (v) { const w = remplacer(v); if (w !== v) el.setAttribute(a, w); } });
  });
}

function gabarit(largeur, fonction) {
  const w = parseFloat(largeur) || 210;
  if (largeur && /mm$/.test(largeur) && w <= 120) return { code: fonction === 'badge' ? 'carte CR80 (recto et verso)' : 'ticket 80 mm', w: w };
  return { code: 'A4 portrait', w: 210 };
}

/* Chrome écrit les polices variables d'Inter en Type 3, dupliquées : on dédoublonne les objets identiques
   et on recompresse les flux (pypdf). Sans Python ou sans pypdf, les PDF restent tels que Chrome les écrit. */
function compresserPdf(dossier) {
  const code = [
    'import sys, os, warnings',
    'warnings.filterwarnings("ignore")',
    'from pypdf import PdfReader, PdfWriter',
    'avant = apres = 0',
    'for racine, _, fichiers in os.walk(sys.argv[1]):',
    '    for f in fichiers:',
    '        if not f.endswith(".pdf"): continue',
    '        p = os.path.join(racine, f)',
    '        avant += os.path.getsize(p)',
    '        w = PdfWriter(clone_from=PdfReader(p))',
    '        for page in w.pages: page.compress_content_streams(level=9)',
    '        w.compress_identical_objects(remove_identicals=True, remove_orphans=True)',
    '        w.write(p + ".tmp"); os.replace(p + ".tmp", p)',
    '        apres += os.path.getsize(p)',
    'print("compression: %.1f Mo -> %.1f Mo" % (avant / 1048576, apres / 1048576))',
  ].join('\n');
  const r = spawnSync('python3', ['-I', '-c', code, dossier], { encoding: 'utf8', maxBuffer: 1 << 26 });
  console.log(r.status === 0 ? r.stdout.trim() : 'compression ignorée (python3 ou pypdf absent) : ' + String(r.stderr).slice(-160));
}

async function pdf() {
  const puppeteer = require('puppeteer');
  const port = 8987;
  const web = await servirFichiers(port, null);
  const ident = JSON.parse(fs.readFileSync(path.join(TMP, 'identites.json'), 'utf8'));
  const { mapping, nums } = tableSubstitution(ident);
  const donnees = { mapping: [...mapping], nums: [...nums] };
  const remplacerTexte = fabriquerRemplacer(donnees);
  fs.writeFileSync(path.join(TMP, 'table-substitution-jetons.json'), JSON.stringify({ nbJetonsNoms: mapping.size, nbNumeros: nums.size }));
  const browser = await puppeteer.launch({ executablePath: trouverChrome(), headless: true, args: ['--no-sandbox'] });
  const capDir = path.join(TMP, 'captures');
  const specs = path.join(SORTIE, 'specimens'); const vign = path.join(SORTIE, 'vignettes');
  fs.rmSync(specs, { recursive: true, force: true }); fs.rmSync(vign, { recursive: true, force: true });
  const fichiers = [];
  fs.readdirSync(capDir).sort().forEach((p) => fs.readdirSync(path.join(capDir, p)).sort().forEach((f) => fichiers.push(path.join(capDir, p, f))));
  const manifeste = [];
  const pris = new Set();
  const page = await browser.newPage();
  await page.setViewport({ width: 1000, height: 1200 });
  for (const f of fichiers) {
    const c = JSON.parse(fs.readFileSync(f, 'utf8'));
    ['titre', 'ecran', 'declencheur'].forEach((k) => { if (c[k]) c[k] = remplacerTexte(c[k]); });
    const g = gabarit(c.largeur, c.fonction);
    const dossier = (c.module + '-' + slug(c.moduleLabel));
    let base = slug(c.pageId + '--' + c.titre);
    let nom = base, k = 2; while (pris.has(dossier + '/' + nom)) nom = base + '-' + (k++);
    pris.add(dossier + '/' + nom);
    const filigrane = 'SPÉCIMEN, données fictives';
    const petit = g.w < 120;
    const html = '<!doctype html><html lang="fr"><head><meta charset="utf-8"><base href="http://127.0.0.1:' + port + '/pages/">'
      + '<link rel="stylesheet" href="../assets/css/tailwind.css">'
      + '<style>html,body{margin:0;padding:0;background:#fff}'
      + '.print-sheet{box-shadow:none!important;margin:0!important}'
      + (petit ? '.print-sheet,article{min-height:0!important;height:auto!important}' : '')
      + '.pres-filigrane{position:fixed;left:0;right:0;top:0;bottom:0;display:flex;align-items:center;justify-content:center;pointer-events:none;z-index:9999}'
      + '.pres-filigrane span{transform:rotate(-32deg);font:700 ' + (petit ? '15px' : '46px') + '/1.1 Inter,Arial,sans-serif;color:rgba(185,28,28,.16);text-transform:uppercase;letter-spacing:.06em;text-align:center;white-space:nowrap}'
      + '.pres-bandeau{position:fixed;left:0;right:0;bottom:0;text-align:center;font:600 ' + (petit ? '6px' : '8px') + '/1.4 Inter,Arial,sans-serif;color:#b91c1c;background:rgba(254,226,226,.85);padding:1px 0;z-index:9999;text-transform:uppercase;letter-spacing:.08em}'
      + '@page{' + (petit ? '' : 'size:A4;') + 'margin:0}</style></head><body>'
      + c.html + '<div class="pres-filigrane"><span>' + filigrane + '</span></div><div class="pres-bandeau">' + filigrane + '</div></body></html>';
    await page.setViewport({ width: Math.ceil(g.w / 25.4 * 96) + 2, height: 1200 });
    await page.setContent(html, { waitUntil: 'load', timeout: 60000 });
    await page.evaluate(() => document.fonts.ready.then(() => 1));
    await page.emulateMediaType('print');
    await page.evaluate(substituerDansPage, fabriquerRemplacer.toString(), donnees);
    await attendre(80);
    const hpx = await page.evaluate((court) => {
      const f = document.querySelector('.print-sheet, article');
      if (!court) return Math.ceil(f.getBoundingClientRect().height);
      let m = 0; f.querySelectorAll('*').forEach((e) => { const r = e.getBoundingClientRect(); if (r.height > 0 && r.bottom > m) m = r.bottom; });
      return Math.ceil(m) + 12;
    }, petit);
    fs.mkdirSync(path.join(specs, dossier), { recursive: true }); fs.mkdirSync(path.join(vign, dossier), { recursive: true });
    const opts = { printBackground: true, margin: { top: 0, right: 0, bottom: 0, left: 0 } };
    if (petit) {
      /* La feuille de style du logiciel déclare @page A4 : le format réduit se redéclare ici, au mm près. */
      await page.addStyleTag({ content: '@page{size:' + g.w + 'mm ' + (Math.ceil(hpx * 25.4 / 96) + 2) + 'mm;margin:0}' });
      opts.preferCSSPageSize = true;
    } else { opts.format = 'A4'; opts.preferCSSPageSize = true; }
    await page.pdf(Object.assign({ path: path.join(specs, dossier, nom + '.pdf') }, opts));
    /* Vignette : haut de la première page, JPEG léger. */
    const largeurPx = Math.ceil(g.w / 25.4 * 96);
    await page.screenshot({ path: path.join(vign, dossier, nom + '.jpg'), type: 'jpeg', quality: 45,
      clip: { x: 0, y: 0, width: largeurPx, height: Math.min(hpx, petit ? 1000 : 1123), scale: petit ? 0.5 : 0.36 } });
    manifeste.push({ module: c.module, moduleLabel: c.moduleLabel, dossier: dossier, fichier: nom + '.pdf', vignette: nom + '.jpg', titre: c.titre, gabarit: g.code,
      pageId: c.pageId, ecran: c.ecran, site: c.site, fonction: c.fonction, declencheur: c.declencheur });
    process.stdout.write('.');
  }
  console.log('\n' + manifeste.length + ' PDF');
  compresserPdf(specs);
  fs.writeFileSync(path.join(TMP, 'manifeste.json'), JSON.stringify(manifeste));
  await browser.close(); web.close();
}

/* ==========================================================================
 * PHASE 3 : INDEX, README, CONTRÔLES
 * ======================================================================= */
function tailleDossier(d) {
  let t = 0; fs.readdirSync(d, { withFileTypes: true }).forEach((e) => { const p = path.join(d, e.name); t += e.isDirectory() ? tailleDossier(p) : fs.statSync(p).size; });
  return t;
}
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function controleConfidentialite() {
  const ident = JSON.parse(fs.readFileSync(path.join(TMP, 'identites.json'), 'utf8'));
  const { reelsMajuscules, nums } = tableSubstitution(ident);
  const rien = { pdftotext: spawnSync('pdftotext', ['-v'], { encoding: 'utf8' }).error ? false : true };
  const specs = path.join(SORTIE, 'specimens');
  const trouvailles = []; let nbPdf = 0;
  const nomsComplets = new Set();
  (ident.personnel || []).forEach((p) => { if (p.nomComplet) nomsComplets.add(p.nomComplet.toUpperCase()); });
  (ident.titulaires || []).forEach((t) => nomsComplets.add(String(t).toUpperCase()));
  const longs = [...reelsMajuscules];
  fs.readdirSync(specs).forEach((d) => fs.readdirSync(path.join(specs, d)).filter((f) => f.endsWith('.pdf')).forEach((f) => {
    nbPdf++;
    const chemin = path.join(specs, d, f);
    let texte = '';
    if (rien.pdftotext) texte = spawnSync('pdftotext', ['-layout', chemin, '-'], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }).stdout || '';
    else texte = spawnSync('node', [path.join(__dirname, '_pdftext.js'), chemin, TMP], { encoding: 'utf8' }).stdout || '';
    const maj = texte.toUpperCase().replace(/\s+/g, ' ');
    longs.forEach((t) => { if (new RegExp('(^|[^A-ZÀ-ÖØ-Þ])' + t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '($|[^A-ZÀ-ÖØ-Þ])').test(maj)) trouvailles.push({ pdf: d + '/' + f, jeton: t }); });
    const chiffres = texte.replace(/[\s.\-]/g, '');
    nums.forEach((_, d9) => { if (chiffres.indexOf(d9) >= 0) trouvailles.push({ pdf: d + '/' + f, numero: d9.replace(/\d(?=\d{3})/g, '*') }); });
    if (/\bIBAN\b|\bRIB\b|mot de passe|password|jeton|token|secret/i.test(texte)) trouvailles.push({ pdf: d + '/' + f, motif: 'mot sensible' });
  }));
  return { outilTexte: rien.pdftotext ? 'pdftotext -layout' : 'build/_pdftext.js', nbPdf, jetonsRecherches: longs.length, nomsCompletsRecherches: nomsComplets.size, numerosRecherches: nums.size, trouvailles };
}

/* Causes connues des états non atteints (vérifiées dans les sources ou au banc). Ce qui n'est pas vérifié le dit. */
const RAISONS = {
  'assets/js/modules/m2-consultations.js:2902': 'code mort : `etatOrdonnanceAncienne` n\'est appelée nulle part (l\'ordonnance s\'imprime par `etatOrdonnanceMedicale`)',
  'assets/js/modules/m5-laboratoire.js:3446': 'activité Banque de sang fermée (cfg-modules) : écran inaccessible à tous les profils, administrateur compris',
  'assets/js/modules/m5-laboratoire.js:3579': 'activité Banque de sang fermée (cfg-modules) : écran inaccessible à tous les profils, administrateur compris',
  'assets/js/modules/m6-stock.js:2568': 'aucune création manuelle (RG-03) : le bon naît d\'une dispensation, qui exige une ordonnance encaissée puis servie ; chaîne non rejouée',
  'assets/js/modules/m6-stock.js:1808': 'exige une feuille d\'inventaire comptée (registre vide sur le jeu) ; saisie de comptage non rejouée',
  'assets/js/modules/m3-hospitalisation.js:3623': 'le formulaire exige des examens cochés et l\'urgence par examen : la saisie automatique est refusée (erreurs de formulaire)',
  'assets/js/modules/m8-facturation.js:1934': 'exige un patient débiteur et la saisie d\'un engagement de paiement ; non rejoué',
  'assets/js/modules/m8-facturation.js:2120': 'opération de remboursement à saisir (champs obligatoires) ; non rejouée',
  'assets/js/modules/m12-comptabilite.js:2396': 'exige une clôture en deux gestes (demande, puis validation Direction) après une pré-clôture sans brouillon ; le jeu porte des brouillons',
  'assets/js/modules/m10-rh.js:2462': 'le clic sur « Imprimer la note » n\'ouvre aucun aperçu sur le banc (cause non élucidée)',
  'assets/js/modules/m1-patients.js:2304': 'proposé après la saisie d\'une demande d\'analyses de patient externe, en fenêtre ; non rejoué',
  'assets/js/modules/m2-consultations.js:483': 'exige une consultation portant des analyses prescrites ; non rejoué',
  'assets/js/modules/configuration.js:3338': 'impression d\'un certificat du registre : cause non vérifiée (probablement aucune ligne imprimable sur le jeu)',
};

function indexer() {
  const manifeste = JSON.parse(fs.readFileSync(path.join(TMP, 'manifeste.json'), 'utf8'));
  const sites = inventaireSites();
  const releves = fs.readdirSync(TMP).filter((f) => /^releve-.*\.json$/.test(f)).map((f) => JSON.parse(fs.readFileSync(path.join(TMP, f), 'utf8')));
  const touches = {}, tabTouches = {}, pagesLog = [];
  manifeste.forEach((m) => { if (m.site) touches[m.site] = 1; });
  releves.forEach((r) => { Object.keys(r.sites).forEach((k) => { touches[k] = (touches[k] || 0) + r.sites[k]; }); Object.keys(r.tableaux).forEach((k) => { tabTouches[k] = 1; }); (r.log || []).forEach((l) => pagesLog.push(l)); });
  const etatsSites = sites.filter((s) => s.type !== 'tableau');
  const tabSites = sites.filter((s) => s.type === 'tableau');
  const atteint = (s) => !!touches[s.cle];
  /* Module d'un site non atteint : par le fichier de script, via MODULE_FILES. */
  const FICHIER_MODULE = { 'm1-patients.js': 'M1', 'm2-consultations.js': 'M2', 'm3-hospitalisation.js': 'M3', 'm4-maternite.js': 'M4', 'm5-laboratoire.js': 'M5', 'm6-stock.js': 'M6',
    'm7-achats.js': 'M7', 'm8-facturation.js': 'M8', 'm9-assurances.js': 'M9', 'm10-rh.js': 'M10', 'm11-paie.js': 'M11', 'm12-comptabilite.js': 'M12', 'm13-administration.js': 'M13',
    'm14-securite.js': 'M14', 'mecef.js': 'MECEF', 'ged.js': 'GED', 'rapports.js': 'RAP', 'dashboards.js': 'DASH', 'configuration.js': 'CFG', 'support.js': 'SUP', 'import.js': 'IMP', 'mere.js': 'MERE', 'relais.js': 'RELAIS', 'auth.js': 'AUTH' };
  const modDe = (s) => FICHIER_MODULE[path.basename(s.fichier)] || 'SOCLE (' + path.basename(s.fichier) + ')';
  const parModule = {};
  etatsSites.forEach((s) => { const m = modDe(s); parModule[m] = parModule[m] || { total: 0, atteints: 0, manques: [] }; parModule[m].total++; if (atteint(s)) parModule[m].atteints++; else parModule[m].manques.push(s); });
  const nbAtt = etatsSites.filter(atteint).length;
  const nbTabAtt = tabSites.filter((s) => tabTouches[s.cle]).length;

  /* ---- index.html ---- */
  const groupes = {};
  manifeste.forEach((m) => { (groupes[m.dossier] = groupes[m.dossier] || { label: (m.module + ' ' + m.moduleLabel).replace(/\s[—–]\s/g, ' : '), items: [] }).items.push(m); });
  const ordre = Object.keys(groupes).sort((a, b) => { const na = parseInt(a.replace(/\D+/, ''), 10), nb = parseInt(b.replace(/\D+/, ''), 10); return (isNaN(na) ? 999 : na) - (isNaN(nb) ? 999 : nb) || a.localeCompare(b); });
  let h = '<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>SIGH-CNT : spécimens des états imprimés</title>'
    + '<style>:root{--navy:#14284b;--bord:#d7dde8;--fond:#f4f6fa}*{box-sizing:border-box}body{margin:0;font:14px/1.45 Inter,Segoe UI,Arial,sans-serif;background:var(--fond);color:#1e293b}'
    + 'header{background:var(--navy);color:#fff;padding:18px 24px}header h1{margin:0;font-size:20px}header p{margin:4px 0 0;color:#cbd5e1;font-size:13px}'
    + 'nav{padding:10px 24px;background:#fff;border-bottom:1px solid var(--bord);display:flex;flex-wrap:wrap;gap:6px;position:sticky;top:0;z-index:5}nav a{font-size:12px;padding:3px 9px;border:1px solid var(--bord);border-radius:99px;color:var(--navy);text-decoration:none;background:#fff}'
    + 'main{padding:8px 24px 40px}h2{margin:28px 0 10px;font-size:16px;color:var(--navy)}h2 small{font-weight:400;color:#64748b}'
    + '.grille{display:grid;grid-template-columns:repeat(auto-fill,minmax(168px,1fr));gap:12px}.carte{background:#fff;border:1px solid var(--bord);border-radius:8px;overflow:hidden;text-decoration:none;color:inherit;display:flex;flex-direction:column}'
    + '.carte:hover{box-shadow:0 2px 10px rgba(20,40,75,.18)}.carte img{width:100%;height:170px;object-fit:cover;object-position:top;background:#fff;border-bottom:1px solid var(--bord)}'
    + '.carte div{padding:7px 9px;font-size:12px}.carte b{display:block;font-weight:600;margin-bottom:2px}.carte span{color:#64748b;font-size:11px}</style></head><body>'
    + '<header><h1>SIGH-CNT : spécimens des états imprimés</h1><p>' + manifeste.length + ' spécimens, par module. Tous les PDF portent la mention « SPÉCIMEN, données fictives ». Mise en page réelle du logiciel, données du jeu de démonstration, identités du personnel remplacées.</p></header>'
    + '<nav>' + ordre.map((d) => '<a href="#' + esc(d) + '">' + esc(groupes[d].label.split(' ')[0]) + ' (' + groupes[d].items.length + ')</a>').join('') + '</nav><main>';
  ordre.forEach((d) => {
    const g = groupes[d];
    h += '<h2 id="' + esc(d) + '">' + esc(g.label) + ' <small>' + g.items.length + ' spécimen(s)</small></h2><div class="grille">';
    g.items.forEach((m) => { h += '<a class="carte" href="specimens/' + esc(d) + '/' + esc(m.fichier) + '"><img loading="lazy" alt="" src="vignettes/' + esc(d) + '/' + esc(m.vignette) + '"><div><b>' + esc(m.titre) + '</b><span>' + esc(m.gabarit) + ' · ' + esc(m.ecran || m.pageId) + '</span></div></a>'; });
    h += '</div>';
  });
  h += '</main></body></html>';
  fs.writeFileSync(path.join(SORTIE, 'index.html'), h);

  /* ---- README.md ---- */
  const conf = controleConfidentialite();
  const taille = tailleDossier(SORTIE);
  const pageNonPeintes = pagesLog.filter((l) => l.statut === 'non peinte' || l.statut === 'erreur');
  let r = '# Spécimens des états imprimés de SIGH-CNT\n\n';
  r += 'Dossier de présentation du projet : un spécimen PDF de chaque état imprimé que le logiciel sait produire, rangé par module. '
    + 'Ouvrir `index.html` pour la consultation en vignettes (aucune dépendance réseau).\n\n';
  r += '**' + manifeste.length + ' spécimens**, ' + (taille / 1048576).toFixed(1) + ' Mo. Tous portent le filigrane et le bandeau « SPÉCIMEN, données fictives ».\n\n';
  r += '## Méthode\n\n'
    + '1. La maquette (`prototype_html/`) est pilotée dans Chrome sur un banc isolé (base jetable, horloge décalée sur la date du jeu, 16/08/2026).\n'
    + '2. Les points d\'entrée de l\'impression (`SIGH.print.etat`, `ticket`, `badge`, `planche`) sont enveloppés : la feuille que le logiciel bâtit est relevée telle quelle, avec le site d\'appel (fichier et ligne) lu dans la pile. Rien n\'est redessiné.\n'
    + '3. Chaque écran est exploré : commandes d\'impression de la page, de chaque onglet, des tiroirs de fiche et des fenêtres de paramétrage. Un spécimen est gardé par site d\'appel et par intitulé d\'état (au plus ' + MAX_PAR_SITE + ' variantes par site).\n'
    + '4. Les identités sont substituées dans le texte (voir Confidentialité), puis la feuille est rendue en PDF par Chrome (`page.pdf`) avec la même feuille de style que le logiciel : A4 portrait, ticket 80 mm, carte CR80 aux dimensions réelles.\n'
    + '5. Régénération : `npm run presentation` depuis `prototype_html/` (`build/presentation.js`, phases `capture`, `pdf`, `index`).\n\n';
  r += '## Couverture mesurée\n\n'
    + 'Inventaire : ' + etatsSites.length + ' sites d\'appel d\'un état (`P.etat`, `P.ticket`, `P.badge`, `P.planche`) dans les sources de la maquette ; ' + tabSites.length + ' sites `P.tableau` (corps de tableau, toujours imprimés à l\'intérieur d\'un état).\n\n'
    + '**États atteints : ' + nbAtt + ' / ' + etatsSites.length + ' sites (' + Math.round(100 * nbAtt / etatsSites.length) + ' %).** Sites `P.tableau` traversés : ' + nbTabAtt + ' / ' + tabSites.length + ' (' + Math.round(100 * nbTabAtt / tabSites.length) + ' %). Un site peut produire plusieurs états (variantes d\'intitulé) ; un état n\'est compté qu\'une fois par site.\n\n'
    + '| Module (fichier source) | Sites d\'état | Atteints | Taux |\n|---|---|---|---|\n';
  Object.keys(parModule).sort().forEach((m) => { const p = parModule[m]; r += '| ' + m + ' | ' + p.total + ' | ' + p.atteints + ' | ' + Math.round(100 * p.atteints / p.total) + ' % |\n'; });
  r += '\n';
  r += '## Sommaire par module\n\n';
  ordre.forEach((d) => {
    const g = groupes[d];
    r += '### ' + g.label + ' (' + g.items.length + ')\n\n| État | Gabarit | Fichier |\n|---|---|---|\n';
    g.items.forEach((m) => { r += '| ' + m.titre.replace(/\|/g, '/') + ' | ' + m.gabarit + ' | [`specimens/' + d + '/' + m.fichier + '`](specimens/' + d + '/' + m.fichier + ') |\n'; });
    r += '\n';
  });
  r += '## Ce qui n\'a pas pu être produit\n\n'
    + 'Sites d\'état de la maquette que l\'exploration automatique n\'a pas atteints (' + (etatsSites.length - nbAtt) + '). La raison générale est la même : l\'état n\'est offert qu\'après un geste que l\'exploration ne sait pas faire seule (saisie d\'un formulaire à champs obligatoires, état métier particulier du jeu, sélection multiple, état déclenché par un événement ou par un rôle autre que l\'administrateur) ou l\'écran est fermé au profil du banc. Aucun fichier de l\'application n\'a été modifié pour les atteindre.\n\n';
  Object.keys(parModule).sort().forEach((m) => {
    const p = parModule[m]; if (!p.manques.length) return;
    r += '### ' + m + ' : ' + p.manques.length + ' non atteint(s)\n\n';
    p.manques.forEach((s) => { r += '- `' + s.fichier + ':' + s.ligne + '` ' + (s.titre ? '« ' + s.titre + ' »' : '(intitulé construit à l\'exécution)') + ' : ' + (RAISONS[s.cle] || 'non atteint par l\'exploration, cause non élucidée') + '\n'; });
    r += '\n';
  });
  if (pageNonPeintes.length) {
    r += '### Écrans non explorés\n\n' + pageNonPeintes.map((l) => '- `' + l.page + '` : ' + (l.statut || '') + (/banque-sang|donneurs/.test(l.page) ? ' (activité Banque de sang fermée)' : '') + (l.detail ? ' (' + l.detail + ')' : '')).join('\n') + '\n\n';
  }
  r += '## Limites\n\n'
    + '- Les montants et les lignes sont ceux du jeu de démonstration, à la date du banc (16/08/2026) : un état peut sortir avec des zéros ou des tableaux vides quand le jeu n\'a rien à cette date (l\'arrêté de caisse du jour, par exemple). Rien n\'est inventé pour le remplir.\n'
    + '- Un site d\'impression peut produire plusieurs documents (selon le patient, la modalité, le mois) : seuls les premiers intitulés distincts sont gardés (au plus ' + MAX_PAR_SITE + ' par site).\n'
    + '- Les écrans sont explorés avec le profil administrateur : un état réservé à un autre profil par surcharge d\'écran reste atteignable tant que l\'écran s\'ouvre à l\'administrateur ; les écrans fermés à tous (activités désactivées) ne sont pas explorés.\n'
    + '- Les états de la maquette sont tous en A4 portrait, sauf le ticket de caisse (rouleau 80 mm) et le badge (carte CR80, recto et verso sur une feuille de 93,6 mm).\n'
    + '- La taille tient à Chrome, qui écrit la police Inter (variable) en Type 3 ; les objets identiques sont dédoublonnés après coup (pypdf), sans perte.\n\n';
  r += '## Confidentialité\n\n'
    + 'Le jeu de démonstration porte les noms du personnel de l\'organigramme réel. Avant le PDF, une table de substitution déterministe remplace dans le texte de chaque état ('
    + 'noms et prénoms par jetons, y compris dans les identifiants de connexion, téléphones et numéros CNSS) par des identités fictives. '
    + 'Les noms de patients du jeu sont générés et sont conservés. L\'en-tête légal de la clinique (dénomination, IFU, RCCM) est conservé tel quel : c\'est la mise en page réelle des pièces. '
    + 'Aucune pièce ne porte de compte bancaire, de mot de passe ni de jeton.\n\n'
    + '**Contrôle fait** : relecture de la couche texte de ' + conf.nbPdf + ' PDF avec `' + conf.outilTexte + '`, recherche de ' + conf.jetonsRecherches + ' jetons de noms réels (personnel, titulaires de l\'organigramme, comptes), '
    + conf.numerosRecherches + ' téléphones et numéros CNSS réels, et des mots IBAN, RIB, mot de passe, jeton. Résultat : **' + (conf.trouvailles.length ? conf.trouvailles.length + ' occurrence(s) restante(s)' : 'aucune occurrence') + '**.\n\n';
  if (conf.trouvailles.length) r += conf.trouvailles.slice(0, 60).map((t) => '- `' + t.pdf + '` : ' + (t.jeton || t.numero || t.motif)).join('\n') + '\n\n';
  r += 'Les salaires affichés (bulletins, états de paie) sont des valeurs de démonstration du jeu, non des salaires réels (voir `CLAUDE.md`, champs de test conservés au vidage).\n';
  fs.writeFileSync(path.join(SORTIE, 'README.md'), r);
  console.log('index.html, README.md écrits. ' + manifeste.length + ' spécimens, ' + (taille / 1048576).toFixed(1) + ' Mo, couverture ' + nbAtt + '/' + etatsSites.length + ', confidentialité: ' + conf.trouvailles.length + ' trouvaille(s).');
  fs.writeFileSync(path.join(TMP, 'couverture.json'), JSON.stringify({ atteints: nbAtt, total: etatsSites.length, parModule: Object.keys(parModule).map((m) => [m, parModule[m].atteints, parModule[m].total]), conf: conf }, null, 1));
}

(async () => {
  fs.mkdirSync(TMP, { recursive: true });
  if (PHASE === 'capture' || PHASE === 'tout') await capture();
  if (PHASE === 'pdf' || PHASE === 'tout') await pdf();
  if (PHASE === 'index' || PHASE === 'tout') indexer();
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
