/* =============================================================================
 * SIGH-CNT : LE DOSSIER « presentation » : un spécimen de chaque état imprimé
 * -----------------------------------------------------------------------------
 * Régénère `presentation/` (à la racine du dépôt) : un PDF par état imprimé du
 * logiciel, rangé par module, une page de consultation et un sommaire.
 *
 *   node build/presentation.js                  les trois phases, un seul poste
 *   node build/presentation.js --phase=capture  pilote la maquette, relève les états
 *   node build/presentation.js --phase=complements  joue les 13 sites que la capture n'atteint pas (banc dédié, --n=1,2 pour un sous-ensemble)
 *   node build/presentation.js --phase=pdf      substitue les identités, rend les PDF
 *   node build/presentation.js --phase=index    index.html, README.md, contrôle
 *   --incremental (phases pdf et index) : ne rend que les captures présentes et ne retouche que leurs lignes de l'index et du README
 *     (ex. un seul état : --phase=capture --pages=cfg-organisation, puis --phase=pdf --incremental, puis --phase=index --incremental,
 *     avec SIGH_PRES_TMP sur un dossier neuf et SIGH_PORT_PHP / SIGH_BASE_TEST à soi).
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
    peint() {
      const c = document.getElementById('page-content');
      if (c) return !!(c.children.length && c.textContent.trim().length > 20);
      /* Page autonome, sans coquille ni #page-content (le plan du site) : peinte quand son titre et sa liste le sont. */
      return /\/plan-du-site\.php$/.test(location.pathname) && document.body.innerText.length > 300;
    },
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
 * PHASE 1 bis : COMPLEMENTS (les 13 sites que l'exploration générique n'atteint pas)
 * --------------------------------------------------------------------------
 * Chaque site est joué par SON écran, geste après geste, sur un banc dédié (base
 * jetable, port propre) : saisie du formulaire, enregistrement, puis impression.
 * Les captures sont écrites dans le même dossier que celles de la phase capture,
 * au même format : la phase pdf les rend avec les autres.
 *
 * Deux sites ne s'impriment pas par un geste d'écran (code mort, ou registre que rien
 * n'alimente) : ils sont évalués à partir de leur copie dans le source. Chaque cas est
 * dit dans la note du spécimen et au README. Aucun fichier de l'application n'est modifié.
 * ======================================================================= */
const COMPLEMENTS = [
  { n: 1, site: 'assets/js/modules/configuration.js:3338', page: 'cfg-certificats',
    comment: 'Le registre des certificats est VIDE sur le jeu : la commande de réédition n\'existe que sur une ligne du registre. Le certificat est donc délivré par l\'écran (carte « Certificat médical de repos », durée et date saisies, « Délivrer »), et c\'est la délivrance qui imprime.', note: null },
  { n: 2, site: 'assets/js/modules/m1-patients.js:2304', page: 'm1-externe',
    comment: 'Demande d\'analyses d\'un patient externe saisie à l\'accueil (identité, ordonnance extérieure, deux examens cochés), enregistrée, puis « Imprimer le bulletin » dans la fenêtre « Demande enregistrée ».',
    note: null },
  { n: 3, site: 'assets/js/modules/m10-rh.js:2462', page: 'm10-evaluations',
    comment: 'Écran des évaluations : « Imprimer la note » (note de service du barème NS 131), sans geste préalable.',
    note: null },
  { n: 4, site: 'assets/js/modules/m12-comptabilite.js:2396', page: 'm12-cloture',
    comment: 'Sur le banc dédié : les brouillons sont validés par l\'écran des écritures, la pré-clôture est contrôlée, le comptable (KASSA, connexion réelle) démarre la clôture de 2026, la Direction administrative (TAKI, connexion réelle) la valide, puis « Procès-verbal » est imprimé.',
    note: 'Clôture de l\'exercice 2026 jouée sur une base jetable de banc, jamais sur une base partagée.' },
  { n: 5, site: 'assets/js/modules/m2-consultations.js:483', page: 'm2-consultation-fiche',
    comment: 'Fiche de consultation enregistrée sur un dossier de consultation enregistré (pathologie, diagnostic, un médicament, deux analyses), puis « Bulletin d\'analyses » dans la fenêtre « Consultation enregistrée ».', note: null },
  { n: 6, site: 'assets/js/modules/m2-consultations.js:2902', page: 'm2-ordonnances',
    comment: 'Code mort : `etatOrdonnanceAncienne` n\'est appelée nulle part. Sa copie exacte dans le source est évaluée dans la page (mêmes lignes, même fichier source) et appelée sur une ordonnance du jeu.',
    note: 'Code mort, rendu par appel direct de la fonction (copie du source évaluée dans la page) : aucun écran du logiciel ne l\'appelle.' },
  { n: 7, site: 'assets/js/modules/m3-hospitalisation.js:3623', page: 'm3-demande-examen',
    comment: 'Fiche remplie en entier : patient, résidence, service demandeur, prescripteur, indication, deux examens cochés, urgence « un examen urgent » nommant l\'examen. Elle s\'imprime à l\'émission.', note: null },
  { n: 8, site: 'assets/js/modules/m5-laboratoire.js:3446', page: 'm5-banque-sang',
    comment: 'L\'activité « Banque de sang » est rouverte par l\'écran des activités (cfg-modules) sur le banc seulement, puis « Bon de demande de sang » est imprimé.',
    note: 'Activité rouverte sur le banc : la clinique ne pratique pas la banque de sang, l\'activité est fermée dans le dépôt.' },
  { n: 9, site: 'assets/js/modules/m5-laboratoire.js:3579', page: 'm5-donneurs',
    comment: 'Même réouverture (activité « Donneurs & transfusions »), puis « Imprimer l\'état » sur la première fiche de donneur.',
    note: 'Activité rouverte sur le banc : la clinique ne pratique pas la transfusion, l\'activité est fermée dans le dépôt.' },
  { n: 10, site: 'assets/js/modules/m6-stock.js:1808', page: 'm6-inventaire',
    comment: 'Inventaire lancé (stock gros, périmètre « Fournitures administratives »), huit articles comptés dont quatre écarts, validé sur la feuille de saisie, puis « Imprimer l\'état » sur la ligne du registre.', note: null },
  { n: 11, site: 'assets/js/modules/m6-stock.js:2568', page: 'm6-dispensation',
    comment: 'Chaîne complète jouée par les écrans : fiche de consultation avec un médicament, encaissement de la facture à la caisse, délivrance sur la file de la pharmacie (sortie de stock, justificatif = n° d\'ordonnance). Le bon ne s\'imprime que depuis le registre des dispensations, que la délivrance n\'alimente pas : la fonction du bon est donc appelée directement.',
    note: 'Bon rendu par appel direct de la fonction du source : la délivrance de la file écrit les sorties de stock mais aucune ligne au registre `dispensations` (seul point d\'impression du bon), et la création manuelle y est retirée. Les lignes, le patient et les prix sont ceux de l\'ordonnance réellement encaissée et servie.' },
  { n: 12, site: 'assets/js/modules/m8-facturation.js:1934', page: 'm8-reliquats',
    comment: 'Une facture avec reliquat est choisie, l\'engagement de paiement est saisi (échéancier en trois tranches, reçu par le comptable), puis « Enregistrer et éditer » imprime l\'engagement.', note: null },
  { n: 13, site: 'assets/js/modules/m8-facturation.js:2120', page: 'm8-remboursements',
    comment: 'Opération « Remboursement » saisie (facture réglée, montant, motif, autorisation), enregistrée, puis « Imprimer » sur la ligne créée.', note: null },
];

/* Aides injectées dans la page : remplissage de formulaire et gestes sur les composants maison. */
function aidesPage() {
  window.__w = (ms) => new Promise((r) => setTimeout(r, ms));
  const ev = (i) => { i.dispatchEvent(new Event('input', { bubbles: true })); i.dispatchEvent(new Event('change', { bubbles: true })); };
  window.__set = (racine, nom, v) => {
    const i = racine.querySelector('[name="' + nom + '"]'); if (!i) return false;
    i.value = v; ev(i); return true;
  };
  window.__fill = (racine) => {
    let n = 0;
    racine.querySelectorAll('input[type=number]').forEach((i) => { if (i.value || i.disabled) return; i.value = '3'; ev(i); n++; });
    racine.querySelectorAll('select').forEach((s) => { if (s.disabled || (s.value && s.selectedIndex > 0)) return; const k = Array.from(s.options).findIndex((o) => o.value); if (k >= 0) { s.selectedIndex = k; ev(s); n++; } });
    racine.querySelectorAll('textarea, input[type=text], input:not([type])').forEach((i) => { if (i.value || i.disabled || i.classList.contains('combo-search') || i.type === 'search') return; i.value = 'Spécimen de démonstration'; ev(i); n++; });
    racine.querySelectorAll('input[type=date], input[type=datetime-local], input[type=time]').forEach((i) => {
      if (i.value || i.disabled) return;
      const d = new Date(), z = (x) => String(x).padStart(2, '0');
      const j = d.getFullYear() + '-' + z(d.getMonth() + 1) + '-' + z(d.getDate());
      i.value = i.type === 'date' ? j : (i.type === 'time' ? z(d.getHours()) + ':' + z(d.getMinutes()) : j + 'T' + z(d.getHours()) + ':' + z(d.getMinutes()));
      ev(i); n++;
    });
    return n;
  };
  window.__dlg = () => Array.from(document.querySelectorAll('[role=dialog]')).pop() || null;
  window.__btnx = async (re, scope) => {
    const R = new RegExp(re, 'i');
    const racine = scope === 'dialog' ? window.__dlg() : document.getElementById('page-content');
    if (!racine) return null;
    const b = Array.from(racine.querySelectorAll('button')).find((x) => R.test((x.textContent || '').trim()) && x.getBoundingClientRect().width && !x.disabled);
    if (!b) return null;
    b.click(); await window.__w(800); return (b.textContent || '').trim().slice(0, 40);
  };
  window.__combo = async (racine, idx, match) => {
    const cb = racine.querySelectorAll('button.combo-input')[idx]; if (!cb) return 'nocombo';
    cb.click(); await window.__w(250);
    const pan = Array.from(document.querySelectorAll('.combo-panel')).find((x) => !x.hidden); if (!pan) return 'nopanel';
    const opts = Array.from(pan.querySelectorAll('.combo-option'));
    const o = typeof match === 'number' ? opts[match] : opts.find((x) => x.textContent.includes(match));
    if (!o) { cb.click(); return 'noopt:' + opts.length; }
    o.dispatchEvent(new MouseEvent('mousedown', { bubbles: true })); o.click(); await window.__w(250);
    return cb.textContent.trim().slice(0, 60);
  };
  /* Liste à cases (multiselect) : le panneau reste ouvert d'un choix à l'autre. */
  window.__multi = async (racine, idx, ks) => {
    const cb = racine.querySelectorAll('button.combo-input')[idx]; if (!cb) return 'nocombo';
    cb.click(); await window.__w(250);
    const pan = Array.from(document.querySelectorAll('.combo-panel')).find((x) => !x.hidden); if (!pan) return 'nopanel';
    const opts = pan.querySelectorAll('.combo-option');
    for (const k of ks) { const o = opts[k]; if (!o) continue; o.dispatchEvent(new MouseEvent('mousedown', { bubbles: true })); o.click(); await window.__w(200); }
    cb.click(); await window.__w(200);
    return cb.textContent.trim().slice(0, 80);
  };
  window.__toast = () => { const t = document.getElementById('toast-host'); return t ? t.textContent.replace(/\s+/g, ' ').slice(0, 260) : ''; };
}

/* Copie d'une fonction locale d'un écran, évaluable dans la page : MÊME fichier source, MÊMES numéros de ligne (le préfixe de
   l'enveloppe tient sur la ligne 1, la fonction commence à sa ligne d'origine), si bien que le site d'appel relevé est celui du source.
   Ne sert que pour une fonction qu'aucun geste d'écran n'atteint (code mort, ou registre que rien n'alimente). */
function copieDeFonction(fichierRel, nomFonction, portWeb, marqueur) {
  const L = fs.readFileSync(path.join(ROOT, fichierRel), 'utf8').split('\n');
  const re = new RegExp('function ' + nomFonction + '\\(');
  let i = -1, j = -1;
  for (let k = 0; k < L.length; k++) {
    if (!re.test(L[k])) continue;
    const ind = L[k].match(/^\s*/)[0];
    let f = k + 1; while (f < L.length && !(L[f].trim() === '}' && L[f].startsWith(ind + '}'))) f++;
    if (!marqueur || L.slice(k, f + 1).join('\n').indexOf(marqueur) >= 0) { i = k; j = f; break; }
  }
  if (i < 0) throw new Error(nomFonction + ' introuvable dans ' + fichierRel);
  return '(function(P,C,el,S,D,K,PR,U,G,AUJ){' + '\n'.repeat(i) + L.slice(i, j + 1).join('\n') + '\nreturn ' + nomFonction + ';\n})\n//# sourceURL=http://127.0.0.1:' + portWeb + '/' + fichierRel;
}
const APPEL_COPIE = '(src) => { const SG = window.SIGH, C = SG.core; return (0, eval)(src)(SG.print, C, C.el, SG.store, SG.data, SG.kit, SG.parcours, SG.ui, SG.charts, C.aujourdhui()); }';

async function complements() {
  const puppeteer = require('puppeteer');
  const portPhp = Number(process.env.SIGH_PORT_PHP || 8946);
  const portWeb = portPhp + 1;
  process.env.SIGH_PORT_PHP = String(portPhp);
  process.env.SIGH_BASE_TEST = process.env.SIGH_BASE_TEST || 'sigh_banc_l12c';
  const BANC = require('./_banc.js');
  const dem = await BANC.demarrerPhp(ROOT);
  if (!dem.php) { console.error('PHP KO : ' + dem.raison); process.exit(1); }
  const web = await servirFichiers(portWeb, BANC.relayer);
  console.log('[complements] php ' + portPhp + ' web ' + portWeb + ' base ' + process.env.SIGH_BASE_TEST);
  await BANC.banc('reinitialiser');
  const capDir = path.join(TMP, 'captures'); fs.mkdirSync(capDir, { recursive: true });
  const chrome = trouverChrome();
  const browser = await puppeteer.launch({ executablePath: chrome, headless: true, args: ['--no-sandbox'] });
  const bilan = [];
  const filtre = arg('n') ? arg('n').split(',').map(Number) : null;
  let page = null;
  const url = (id, hash) => 'http://127.0.0.1:' + portWeb + '/pages/' + id + '.php' + (hash || '');

  async function ouvrir(id, hash) {
    if (page) await page.close().catch(() => {});
    page = await browser.newPage();
    await page.setViewport({ width: 1440, height: 900 });
    await BANC.poserSession(page);
    await page.evaluateOnNewDocument(instrumentation);
    await page.evaluateOnNewDocument(aidesPage);
    page.on('dialog', (d) => { d.dismiss().catch(() => {}); });
    page.__erreurs = [];
    page.on('pageerror', (e) => page.__erreurs.push(String(e.message).slice(0, 160)));
    await page.goto(url(id, hash), { waitUntil: 'domcontentloaded', timeout: 120000 });
    await peinte();
  }
  async function peinte() {
    let ok = false;
    for (let k = 0; k < 90; k++) {
      await attendre(500);
      try { if (await page.evaluate(() => window.__pres && window.__pres.peint() && window.SIGH && window.SIGH.print)) { ok = true; break; } } catch (e) { /* contexte détruit */ }
    }
    if (!ok) throw new Error('page non peinte');
    await attendre(700);
    await page.evaluate(() => window.__pres.installer());
  }
  const ev = (fn, ...a) => page.evaluate(fn, ...a);
  /* Rôle réel : la connexion se fait auprès de api/auth.php (haché vérifié), la session est posée puis la page rechargée. */
  async function seConnecter(ident, role, fonction, secteur, poste, nom) {
    const r = await BANC.connecter(ident);
    if (!r || !r.jeton) throw new Error('connexion refusée : ' + ident + ' ' + JSON.stringify(r).slice(0, 100));
    await ev((s, j) => { localStorage.setItem('sigh-cnt:session', JSON.stringify(s)); localStorage.setItem('sigh-cnt:jeton', j); },
      { role: role, nom: nom, poste: poste, identifiant: ident, fonction: fonction, secteur: secteur }, r.jeton);
  }
  async function retablirAdmin() {
    const r = await BANC.connecter(BANC.SESSION_BANC.identifiant);
    await ev((s, j) => { localStorage.setItem('sigh-cnt:session', JSON.stringify(s)); localStorage.setItem('sigh-cnt:jeton', j); }, BANC.SESSION_BANC, r.jeton);
  }
  async function enregistrer(c, caps, contexte, declencheur, note) {
    const garde = caps.filter((x) => x.site === c.site);
    if (!garde.length) return 0;
    const x = garde[garde.length - 1];
    const info = await ev((i) => { const e = window.SIGH.nav.INDEX[i]; return e ? { module: e.module, moduleLabel: e.moduleLabel, label: e.label } : { module: 'HORS', moduleLabel: 'Hors ruban', label: i }; }, c.page);
    const dossier = path.join(capDir, c.page); fs.mkdirSync(dossier, { recursive: true });
    const nom = 'c' + String(c.n).padStart(2, '0') + '-' + slug(x.titre) + '.json';
    fs.writeFileSync(path.join(dossier, nom), JSON.stringify(Object.assign({ pageId: c.page, module: info.module, moduleLabel: info.moduleLabel, ecran: info.label,
      declencheur: declencheur, contexte: contexte }, x, { note: note || c.note || null })));
    return 1;
  }
  const vider = async () => ev(() => window.__pres.vider());
  const exiger = (cond, msg) => { if (!cond) throw new Error(msg); };

  /* ---------------------------------------------------------------- scénarios */
  const SC = {};

  SC[1] = async (c) => {
    await ouvrir(c.page);
    exiger(await ev(() => window.__btnx('Certificat médical de repos')), 'carte du certificat introuvable');
    await ev(() => { const d = window.__dlg(); window.__fill(d); window.__set(d, 'duree', '3'); });
    exiger(await ev(() => window.__btnx('Délivrer le certificat', 'dialog')), 'bouton Délivrer absent');
    await attendre(1200);
    return { caps: await vider(), declencheur: 'Délivrer le certificat (carte « Certificat médical de repos »)' };
  };

  SC[2] = async (c) => {
    await ouvrir(c.page);
    exiger(await ev(() => window.__btnx('Nouvelle demande externe')), 'bouton Nouvelle demande externe absent');
    await ev(async () => {
      const d = window.__dlg();
      window.__set(d, 'nom', 'TOGBE'); window.__set(d, 'prenom', 'Rosalie'); window.__set(d, 'sexe', 'F');
      window.__set(d, 'naissanceConnue', 'date'); window.__set(d, 'dateNaissance', '1991-05-14');
      window.__set(d, 'telephone', '0197000042'); window.__set(d, 'residence', 'Natitingou, quartier Yimporima');
      window.__set(d, 'prescripteur', 'Dr ADEOTI, centre de santé de Boukoumbé'); window.__set(d, 'indication', 'Fièvre et fatigue, bilan demandé');
      window.__set(d, 'serviceDemandeur', d.querySelector('[name=serviceDemandeur]').options[1].value);
      await window.__multi(d, 1, [0, 1]);
    });
    await ev(() => { window.__fill(window.__dlg()); });
    exiger(await ev(() => window.__btnx('Enregistrer et envoyer', 'dialog')), 'bouton Enregistrer absent');
    await attendre(1500);
    const txt = await ev(() => (window.__dlg() ? window.__dlg().innerText.slice(0, 80) : 'aucune fenêtre'));
    exiger(/Demande enregistrée/.test(txt), 'demande non enregistrée : ' + txt + ' ' + (await ev(() => window.__toast())));
    exiger(await ev(() => window.__btnx('Imprimer le bulletin', 'dialog')), 'bouton Imprimer le bulletin absent');
    await attendre(1000);
    return { caps: await vider(), declencheur: 'Imprimer le bulletin (après « Enregistrer et envoyer à la caisse »)' };
  };

  SC[3] = async (c) => {
    await ouvrir(c.page);
    exiger(await ev(() => window.__btnx('Imprimer la note')), 'bouton Imprimer la note absent');
    await attendre(1200);
    return { caps: await vider(), declencheur: 'Imprimer la note' };
  };

  SC[5] = async (c) => {
    /* Un dossier de consultation ENREGISTRÉ (en consultation ou en attente du labo), d'un patient sans assurance ni dossier d'agent. */
    await ouvrir('m2-dossiers-consultation');
    const dos = await ev(() => {
      const S = window.SIGH.store;
      const ok = S.collection('dossiersConsultation').active().filter((d) => d.etat === 'consultation' || d.etat === 'attente_labo').map((d) => {
        const p = S.collection('patients').active().filter((x) => x.code === d.patientCode)[0];
        return { id: d.id, ref: d.reference, patient: p, code: d.patientCode };
      }).filter((x) => x.patient && !x.patient.personnelId);
      const choix = ok.filter((x) => !x.patient.assureur)[0] || ok[0];
      return choix ? { id: choix.id, ref: choix.ref, code: choix.code } : null;
    });
    exiger(dos, 'aucun dossier de consultation enregistré');
    await ouvrir(c.page, '#onglet=' + dos.id);
    await attendre(1500);
    /* Médicament : un produit réellement servable en pharmacie (stock de détail). */
    const med = await ev(() => {
      const ps = window.SIGH.store.collection('produits').active().filter((p) => p.categorie === 'medicament' && (p.stockDetail || 0) >= 10);
      return ps.length ? ps[0].designation : null;
    });
    exiger(med, 'aucun médicament en stock de détail');
    await ev(async (medNom) => {
      const root = document.getElementById('page-content');
      await window.__multi(root, 1, [0]);
      await window.__combo(root, 2, medNom);
      const q = Array.from(root.querySelectorAll('input[type=number]')).filter((i) => !i.name);
      q.forEach((i) => { i.value = '2'; i.dispatchEvent(new Event('input', { bubbles: true })); i.dispatchEvent(new Event('change', { bubbles: true })); });
      const pos = Array.from(root.querySelectorAll('input')).filter((i) => /Posologie/.test(i.placeholder))[0];
      if (pos) { pos.value = '1 comprimé matin et soir'; pos.dispatchEvent(new Event('input', { bubbles: true })); }
      const dur = Array.from(root.querySelectorAll('input')).filter((i) => /^Durée/.test(i.placeholder))[0];
      if (dur) { dur.value = '5 jours'; dur.dispatchEvent(new Event('input', { bubbles: true })); }
      await window.__multi(root, 3, [0, 1]);
      window.__set(root, 'diagnostic', 'Paludisme simple confirmé'); window.__set(root, 'resumeSyndromique', 'Fièvre depuis trois jours');
      window.__set(root, 'hypotheses', 'Paludisme'); window.__set(root, 'conduite', 'Traitement ambulatoire'); window.__set(root, 'traitementEmblee', 'Antipyrétique');
    }, med);
    exiger(await ev(() => { const b = Array.from(document.querySelectorAll('#page-content button')).find((x) => /Enregistrer et prescrire/.test(x.textContent)); if (!b) return null; b.click(); return 'ok'; }), 'bouton Enregistrer et prescrire absent');
    await attendre(2500);
    const modale = await ev(() => (window.__dlg() ? window.__dlg().innerText : ''));
    exiger(/Consultation enregistrée/.test(modale), 'fiche non enregistrée : ' + (await ev(() => window.__toast())));
    SC.chaine = { facture: (/facture (FP-[\w-]+)/.exec(modale) || [])[1], ordonnance: (/Ordonnance (ORD-[\w-]+)/.exec(modale) || [])[1], medicament: med, dossier: dos.ref };
    exiger(await ev(() => { const b = Array.from(document.querySelectorAll('[role=dialog] button')).find((x) => /Bulletin d.analyses/.test(x.textContent)); if (!b) return null; b.click(); return 'ok'; }), 'bouton Bulletin d\'analyses absent');
    await attendre(1200);
    return { caps: await vider(), declencheur: 'Bulletin d\'analyses (fenêtre « Consultation enregistrée », dossier ' + dos.ref + ')' };
  };

  SC[6] = async (c) => {
    await ouvrir(c.page);
    const code = copieDeFonction('assets/js/modules/m2-consultations.js', 'etatOrdonnanceAncienne', portWeb, 'Ordonnance médicale');
    const r = await ev((src, appel) => {
      const S = window.SIGH.store;
      const o = S.collection('ordonnances').active().filter((x) => (x.medicaments || []).length && x.statutPaiement === 'soldee')[0] || S.collection('ordonnances').active().filter((x) => (x.medicaments || []).length)[0];
      if (!o) return 'aucune ordonnance';
      (0, eval)(appel)(src)(o);
      return o.numero;
    }, code, APPEL_COPIE);
    exiger(/^ORD/.test(r), 'appel direct impossible : ' + r);
    await attendre(1000);
    return { caps: await vider(), declencheur: 'appel direct de etatOrdonnanceAncienne sur ' + r };
  };

  SC[7] = async (c) => {
    await ouvrir(c.page);
    exiger(await ev(() => window.__btnx('Nouvelle fiche de demande')), 'bouton Nouvelle fiche absent');
    await ev(async () => {
      const d = window.__dlg();
      await window.__combo(d, 0, 3);
      window.__set(d, 'serviceDemandeur', 'medecine');
      const pr = d.querySelector('[name=prescripteur]'); if (pr) { pr.selectedIndex = 1; pr.dispatchEvent(new Event('change', { bubbles: true })); }
      window.__set(d, 'urgence', 'examen');
      window.__set(d, 'residence', 'Natitingou, quartier Bassosi'); window.__set(d, 'indication', 'Fièvre persistante, bilan infectieux');
      await window.__multi(d, 1, [0, 1]);
    });
    const premier = await ev(() => { const t = window.__dlg().querySelectorAll('button.combo-input')[1].textContent; return (/— (.+?)(,|$)/.exec(t) || [])[1] || ''; });
    exiger(premier, 'examen coché illisible');
    await ev(async (nom) => { await window.__combo(window.__dlg(), 2, nom); }, premier.trim());
    exiger(await ev(() => window.__btnx('Émettre la fiche', 'dialog')), 'bouton Émettre absent');
    await attendre(2000);
    return { caps: await vider(), declencheur: 'Émettre la fiche (urgence « un examen urgent » : ' + premier.trim() + ')' };
  };

  SC[89] = async () => {
    /* Réouverture des deux activités par l'écran cfg-modules, puis les deux états. */
    await ouvrir('cfg-modules');
    for (let k = 0; k < 2; k++) {
      const ok = await ev(() => { const b = document.querySelector('#page-content tbody button[title="Rouvrir cette activité"]'); if (!b) return false; b.click(); return true; });
      if (!ok) break;
      await attendre(800);
      exiger(await ev(() => window.__btnx('Rouvrir l.activité', 'dialog')), 'confirmation de réouverture absente');
      await attendre(1500);
    }
    const etats = await ev(() => Array.from(document.querySelectorAll('#page-content tbody tr')).slice(0, 2).map((t) => t.innerText.replace(/\s+/g, ' ').slice(0, 90)));
    exiger(etats.length === 2 && etats.every((t) => /Ouverte/.test(t)), 'activités non rouvertes : ' + etats.join(' / '));
    await attendre(1500);
    const sorties = {};
    await ouvrir('m5-banque-sang');
    exiger(await ev(() => window.__btnx('Bon de demande de sang')), 'bouton Bon de demande de sang absent');
    await attendre(1000);
    sorties[8] = { caps: await vider(), declencheur: 'Bon de demande de sang (activité rouverte sur le banc)' };
    await ouvrir('m5-donneurs');
    exiger(await ev(() => { const b = document.querySelector('#page-content tbody tr button[title="Imprimer l’état"]'); if (!b) return false; b.click(); return true; }), 'bouton Imprimer l\'état absent');
    await attendre(1000);
    sorties[9] = { caps: await vider(), declencheur: 'Imprimer l\'état, première fiche de donneur (activité rouverte sur le banc)' };
    return sorties;
  };

  SC[10] = async (c) => {
    await ouvrir(c.page);
    exiger(await ev(() => window.__btnx('Lancer un inventaire')), 'bouton Lancer un inventaire absent');
    await ev(async () => {
      const d = window.__dlg();
      window.__set(d, 'magasin', 'gros'); window.__set(d, 'type', 'Mensuel');
      await window.__combo(d, 0, 'Fourniture');
    });
    exiger(await ev(() => window.__btnx('Ouvrir la feuille', 'dialog')), 'bouton Ouvrir la feuille absent');
    await attendre(2500);
    const n = await ev(() => {
      const rows = Array.from(document.querySelectorAll('#page-content tbody tr')); const dec = [0, -2, 3, 0, -1, 0, 0, 1];
      rows.forEach((tr, i) => { const inp = tr.querySelector('input[type=number]'); if (!inp) return; inp.value = String(Math.max(0, Number(inp.value) + (dec[i] || 0))); inp.dispatchEvent(new Event('input', { bubbles: true })); });
      return rows.length;
    });
    exiger(n > 0, 'feuille d\'inventaire vide');
    exiger(await ev(() => { const b = Array.from(document.querySelectorAll('button')).find((x) => /Valider l.inventaire/.test(x.textContent) && x.getBoundingClientRect().width); if (!b) return null; b.click(); return 'ok'; }), 'bouton Valider l\'inventaire absent');
    await attendre(1500);
    exiger(await ev(() => window.__btnx('Revenir au registre')), 'retour au registre absent');
    await attendre(2500);
    await ev(() => window.__pres.installer());
    exiger(await ev(() => { const b = document.querySelector('#page-content tbody tr button[title="Imprimer l’état"]'); if (!b) return false; b.click(); return true; }), 'ligne du registre absente');
    await attendre(1200);
    return { caps: await vider(), declencheur: 'Imprimer l\'état (registre des inventaires, ' + n + ' articles comptés)' };
  };

  SC[11] = async (c) => {
    const ch = SC.chaine; exiger(ch && ch.facture, 'chaîne de consultation absente (scénario 5 non joué)');
    /* Encaissement à la caisse. */
    await ouvrir('m8-caisse');
    exiger(await ev((num) => {
      const tr = Array.from(document.querySelectorAll('#page-content tbody tr')).find((t) => t.innerText.includes(num) && /Encaisser le reste/.test(t.innerText));
      const b = tr && Array.from(tr.querySelectorAll('button')).find((x) => /Encaisser le reste/.test(x.textContent)); if (!b) return false; b.click(); return true;
    }, ch.facture), 'pièce ' + ch.facture + ' introuvable à la caisse');
    await attendre(1000);
    exiger(await ev(() => window.__btnx('Valider l.encaissement', 'dialog')), 'bouton Valider l\'encaissement absent');
    await attendre(2200);
    const fin = await ev(() => window.__toast());
    exiger(!/impossible|refus/i.test(fin), 'encaissement refusé : ' + fin);
    /* Délivrance sur la file de la pharmacie. */
    await ouvrir('m6-dispensation');
    /* La file porte toutes les ordonnances du jeu : on la filtre sur le patient de l'ordonnance (la file est cherchable). */
    const patient = await ev((num) => { const o = window.SIGH.store.collection('ordonnances').active().filter((x) => x.numero === num)[0]; return o ? o.patient : null; }, ch.ordonnance);
    exiger(patient, 'ordonnance ' + ch.ordonnance + ' introuvable au magasin');
    await ev(async (nom) => {
      const i = document.querySelector('#page-content input[type=search]'); i.value = nom; i.dispatchEvent(new Event('input', { bubbles: true })); await window.__w(600);
    }, patient);
    exiger(await ev(() => {
      const b = document.querySelector('#page-content tbody tr button[title="Délivrer"]'); if (!b) return false; b.click(); return true;
    }), 'ordonnance de ' + patient + ' sans commande Délivrer : ' + (await ev(() => Array.from(document.querySelectorAll('#page-content tbody tr')).slice(0, 2).map((t) => t.innerText.replace(/\s+/g, ' ') + ' [' + Array.from(t.querySelectorAll('button')).map((b) => b.textContent.trim() + '/' + b.disabled + '/' + (b.title || '')).join(',') + ']').join(' || '))));
    await attendre(1000);
    exiger(await ev(() => window.__btnx('Confirmer la délivrance', 'dialog')), 'bouton Confirmer la délivrance absent (stock insuffisant ?)');
    await attendre(2000);
    const delivre = await ev(() => window.__toast());
    exiger(/délivrés/i.test(delivre), 'délivrance non faite : ' + delivre);
    /* Le registre des dispensations est le SEUL écran qui imprime le bon, et la délivrance de la file n'y écrit rien : on le constate
       (aucune ligne, commande de création manuelle retirée le 02/09/2026). Le bon est donc rendu par la fonction du source, appelée sur la
       dispensation que la chaîne vient de produire (lignes, patient et prix de l'ordonnance servie). */
    await ouvrir('m6-dispensation');
    const reg = await ev(() => document.querySelectorAll('#page-content button[title="Imprimer"]').length);
    exiger(reg === 0, 'le registre porte désormais une ligne imprimable : le scénario doit passer par elle');
    const code = copieDeFonction('assets/js/modules/m6-stock.js', 'etat', portWeb, 'Bon de sortie de stock');
    const ref = await ev((src, appel, num) => {
      const S = window.SIGH.store, C = window.SIGH.core;
      const o = S.collection('ordonnances').active().filter((x) => x.numero === num)[0];
      if (!o || o.statutDispensation !== 'servie') return 'ordonnance non servie';
      const lignes = (o.medicaments || []).map((l) => ({ produitId: l.produitId, produit: l.produit, unite: l.unite, quantite: l.quantite, prix: l.prix }));
      const d = { reference: 'DISP-' + String(S.collection('dispensations').all().length + 1).padStart(5, '0'), date: C.iso(C.aujourdhui()), patient: o.patient, patientCode: o.patientCode,
        lignes: lignes, montant: lignes.reduce((t, l) => t + l.quantite * l.prix, 0), dispensePar: S.currentUser() };
      (0, eval)(appel)(src)(d);
      return d.reference;
    }, code, APPEL_COPIE, ch.ordonnance);
    exiger(/^DISP/.test(ref), 'appel direct impossible : ' + ref);
    await attendre(1200);
    return { caps: await vider(), declencheur: 'appel direct de la fonction du bon sur la dispensation produite par la chaîne (' + ch.facture + ' encaissée, ' + ch.ordonnance + ' délivrée) ; registre vide' };
  };

  SC[12] = async (c) => {
    await ouvrir(c.page);
    exiger(await ev(() => { const b = document.querySelector('#page-content tbody tr button[title="Engagement de paiement"]'); if (!b) return false; b.click(); return true; }), 'aucune facture avec reliquat');
    await attendre(900);
    await ev(() => {
      const d = window.__dlg();
      window.__set(d, 'modalite', 'echeancier'); window.__set(d, 'tranches', '3'); window.__set(d, 'recuPar', 'KASSA Augustin');
      window.__set(d, 'observation', 'Le patient s\'engage à régler le solde en trois tranches mensuelles.');
    });
    exiger(await ev(() => window.__btnx('Enregistrer et éditer', 'dialog')), 'bouton Enregistrer et éditer absent');
    await attendre(1500);
    return { caps: await vider(), declencheur: 'Enregistrer et éditer (engagement en trois tranches)' };
  };

  SC[13] = async (c) => {
    await ouvrir(c.page);
    exiger(await ev(() => window.__btnx('Nouvelle opération')), 'bouton Nouvelle opération absent');
    await ev(async () => {
      const d = window.__dlg();
      window.__set(d, 'nature', 'Remboursement'); window.__set(d, 'motifAvoir', 'remboursement');
      window.__set(d, 'montant', '1000'); window.__set(d, 'motif', 'Trop-perçu constaté à la caisse, remboursé au patient');
      window.__set(d, 'autorisePar', 'TAKI Alimatou');
      window.__fill(d);
    });
    const cree = await ev(() => { const m = window.__dlg().querySelector('[name=montant]'); return m ? m.value : null; });
    exiger(await ev(() => window.__btnx('^Enregistrer$', 'dialog')), 'bouton Enregistrer absent');
    await attendre(1800);
    const toast = await ev(() => window.__toast());
    exiger(/enregistré/i.test(toast), 'opération refusée : ' + toast + ' (montant ' + cree + ')');
    exiger(await ev(() => { const b = document.querySelector('#page-content tbody tr button[title="Imprimer"]'); if (!b) return false; b.click(); return true; }), 'impression absente');
    await attendre(1200);
    return { caps: await vider(), declencheur: 'Imprimer (opération « Remboursement » créée)' };
  };

  SC[4] = async (c) => {
    /* 1. brouillons validés par l'écran des écritures (filtre « Brouillon », bouton Valider de chaque ligne) */
    await ouvrir('m12-ecritures');
    const avant = await ev(async () => {
      const s = document.querySelector('#page-content select[aria-label=Statut]'); s.value = 'brouillon'; s.dispatchEvent(new Event('change', { bubbles: true })); await window.__w(500);
      const sel = () => Array.from(document.querySelectorAll('#page-content tbody button[title=Valider], #page-content tbody button[aria-label=Valider]'));
      let n = 0; for (let i = 0; i < 400; i++) { const b = sel()[0]; if (!b) break; b.click(); n++; await window.__w(120); }
      return n;
    });
    await attendre(3000);
    const pre = await ev(() => { const p = window.SIGH.exercice.preCloture(window.SIGH.exercice.choisi()); return p.controles.filter((x) => !x.ok && x.bloquant).map((x) => x.libelle + ' : ' + x.detail); });
    exiger(!pre.length, 'pré-clôture bloquée : ' + pre.join(' | '));
    /* 2. comptable : pré-clôture (lue à l'écran) puis démarrage de la clôture, par l'écran */
    await ouvrir('m12-cloture');
    await seConnecter('a.kassa', 'comptable', 'comptable', 'ADM', 'Comptable', 'KASSA Augustin');
    await ouvrir('m12-cloture');
    exiger(await ev(() => window.__btnx('^Pré-clôture')), 'bouton Pré-clôture absent');
    const preTxt = await ev(() => window.__dlg().innerText.slice(0, 120));
    await ev(() => window.__btnx('Démarrer la clôture', 'dialog'));
    await attendre(500);
    await ev(() => { const d = window.__dlg(); const b = Array.from(d.querySelectorAll('button')).find((x) => x.textContent.trim() === 'Démarrer la clôture'); b.click(); });
    await attendre(4000);
    /* 3. Direction administrative : validation. Le geste de l'écran recharge la page aussitôt, avant l'envoi complet des
       collections : la validation passe donc par le moteur que le bouton appelle (SIGH.exercice.valider), puis on attend l'envoi. */
    await ouvrir('m12-cloture');
    await seConnecter('a.taki', 'da', 'direction', 'ADM', 'Directrice Administrative', 'TAKI Alimatou');
    await ouvrir('m12-cloture');
    exiger(await ev(() => window.__btnx('Clôturer définitivement')), 'bouton Clôturer définitivement absent (exercice non en clôture ?)');
    const valide = await ev(async () => {
      const d = window.__dlg(); const ta = d.querySelector('textarea'); ta.value = 'Validation de la clôture, spécimen de présentation';
      ta.dispatchEvent(new Event('input', { bubbles: true })); ta.dispatchEvent(new Event('change', { bubbles: true }));
      const annee = window.SIGH.exercice.liste().filter((x) => x.etat === 'en_cloture')[0].annee;
      const r = window.SIGH.exercice.valider(annee, ta.value);
      return JSON.stringify({ annee: annee, ok: r.ok, motif: r.motif || null, resultat: r.resultat });
    });
    const vr = JSON.parse(valide); exiger(vr.ok, 'clôture refusée : ' + vr.motif);
    await attendre(6000);
    /* 4. le procès-verbal, lu au registre des exercices */
    await ouvrir('m12-cloture');
    const etat = await ev(() => window.SIGH.exercice.liste().map((x) => x.annee + ':' + x.etat).join(' '));
    exiger(new RegExp(vr.annee + ':clos').test(etat), 'exercice non clos après validation : ' + etat);
    exiger(await ev(() => window.__btnx('Procès-verbal')), 'bouton Procès-verbal absent');
    await attendre(1200);
    await retablirAdmin();
    return { caps: await vider(), declencheur: 'Procès-verbal (exercice ' + vr.annee + ' clos : ' + avant + ' brouillons validés, demande KASSA, validation TAKI, pré-clôture « ' + preTxt.replace(/\s+/g, ' ').slice(0, 60) + ' »)' };
  };

  /* L'ordre compte : la clôture de 2026 (scénario 4) ferme l'exercice aux encaissements, elle passe donc en dernier. */
  const ordre = [1, 2, 3, 5, 6, 7, 89, 10, 11, 12, 13, 4];
  for (const k of ordre) {
    const sites = k === 89 ? COMPLEMENTS.filter((x) => x.n === 8 || x.n === 9) : COMPLEMENTS.filter((x) => x.n === k);
    if (filtre && !sites.some((x) => filtre.indexOf(x.n) >= 0) && !(k === 5 && filtre.indexOf(11) >= 0)) continue;
    const t0 = Date.now();
    try {
      const sortie = await SC[k](sites[0]);
      const parSite = k === 89 ? sortie : { [sites[0].n]: sortie };
      for (const c of sites) {
        const s = parSite[c.n];
        const n = await enregistrer(c, s.caps, 'complément ' + c.n, s.declencheur, c.note);
        bilan.push({ n: c.n, site: c.site, produit: n > 0, declencheur: s.declencheur, vus: s.caps.map((x) => x.site + ' ' + x.titre), erreurs: page ? page.__erreurs.slice(0, 3) : [] });
        console.log('  complément ' + String(c.n).padStart(2) + (n > 0 ? ' PRODUIT ' : ' ABSENT  ') + c.site + ' | ' + s.declencheur.slice(0, 90) + ' | ' + (Date.now() - t0) + ' ms');
      }
    } catch (e) {
      for (const c of sites) { bilan.push({ n: c.n, site: c.site, produit: false, erreur: String(e.message).slice(0, 300) }); console.log('  complément ' + c.n + ' ÉCHEC ' + c.site + ' : ' + String(e.message).slice(0, 300)); }
      try { await page.screenshot({ path: path.join(TMP, 'echec-complement-' + k + '.png') }); } catch (e2) { /* sans capture */ }
    }
  }

  /* plan-du-site : page autonome, sans #page-content ; on constate qu'elle se peint et qu'aucune commande d'impression n'y figure. */
  try {
    await ouvrir('plan-du-site');
    const plan = await ev(() => ({ chemin: location.pathname, longueur: document.body.innerText.length,
      impression: Array.from(document.querySelectorAll('button, a')).filter((b) => /imprim|pdf|export/i.test(b.textContent + (b.title || ''))).length }));
    bilan.push({ ecran: 'plan-du-site', peint: true, detail: plan });
    console.log('  plan-du-site peint (' + plan.longueur + ' caractères), commandes d\'impression : ' + plan.impression);
  } catch (e) { bilan.push({ ecran: 'plan-du-site', peint: false, erreur: String(e.message).slice(0, 200) }); console.log('  plan-du-site : ' + e.message); }

  fs.writeFileSync(path.join(TMP, 'complements.json'), JSON.stringify(bilan, null, 1));
  await browser.close(); web.close(); try { dem.php.kill(); } catch (e) { /* déjà arrêté */ }
  const ko = bilan.filter((b) => b.n && !b.produit);
  console.log('compléments : ' + bilan.filter((b) => b.n && b.produit).length + ' produits, ' + ko.length + ' manquants');
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
  /* Quatrième gabarit : le A4 paysage (organigramme, 10/11/2026), reconnu à la largeur de la feuille. */
  if (largeur && /mm$/.test(largeur) && w >= 290) return { code: 'A4 paysage', w: 297, paysage: true };
  return { code: 'A4 portrait', w: 210 };
}

/* Chrome écrit les polices variables d'Inter en Type 3, dupliquées : on dédoublonne les objets identiques
   et on recompresse les flux (pypdf). Sans Python ou sans pypdf, les PDF restent tels que Chrome les écrit. */
function compresserPdf(dossier, seulement) {
  const code = [
    'import sys, os, warnings',
    'warnings.filterwarnings("ignore")',
    'from pypdf import PdfReader, PdfWriter',
    'avant = apres = 0',
    'for racine, _, fichiers in os.walk(sys.argv[1]):',
    '    for f in fichiers:',
    '        if not f.endswith(".pdf"): continue',
    '        if len(sys.argv) > 2 and f not in sys.argv[2].split("|"): continue',
    '        p = os.path.join(racine, f)',
    '        avant += os.path.getsize(p)',
    '        w = PdfWriter(clone_from=PdfReader(p))',
    '        for page in w.pages: page.compress_content_streams(level=9)',
    '        w.compress_identical_objects(remove_identicals=True, remove_orphans=True)',
    '        w.write(p + ".tmp"); os.replace(p + ".tmp", p)',
    '        apres += os.path.getsize(p)',
    'print("compression: %.1f Mo -> %.1f Mo" % (avant / 1048576, apres / 1048576))',
  ].join('\n');
  const r = spawnSync('python3', ['-I', '-c', code, dossier].concat(seulement ? [seulement.join('|')] : []), { encoding: 'utf8', maxBuffer: 1 << 26 });
  console.log(r.status === 0 ? r.stdout.trim() : 'compression ignorée (python3 ou pypdf absent) : ' + String(r.stderr).slice(-160));
}

async function pdf() {
  const puppeteer = require('puppeteer');
  /* Port propre (SIGH_PORT_PDF) : jamais celui d'un banc voisin. */
  const port = Number(process.env.SIGH_PORT_PDF || 8949);
  const web = await servirFichiers(port, null);
  const ident = JSON.parse(fs.readFileSync(path.join(TMP, 'identites.json'), 'utf8'));
  const { mapping, nums } = tableSubstitution(ident);
  const donnees = { mapping: [...mapping], nums: [...nums] };
  const remplacerTexte = fabriquerRemplacer(donnees);
  fs.writeFileSync(path.join(TMP, 'table-substitution-jetons.json'), JSON.stringify({ nbJetonsNoms: mapping.size, nbNumeros: nums.size }));
  const browser = await puppeteer.launch({ executablePath: trouverChrome(), headless: true, args: ['--no-sandbox'] });
  const capDir = path.join(TMP, 'captures');
  const specs = path.join(SORTIE, 'specimens'); const vign = path.join(SORTIE, 'vignettes');
  /* --incremental : ne rend QUE les captures présentes (régénérer un spécimen sans retoucher les 181 autres). */
  if (!FLAG('incremental')) { fs.rmSync(specs, { recursive: true, force: true }); fs.rmSync(vign, { recursive: true, force: true }); }
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
      + '@page{' + (petit ? '' : (g.paysage ? 'size:A4 landscape;' : 'size:A4;')) + 'margin:0}</style></head><body>'
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
    } else { opts.format = 'A4'; opts.preferCSSPageSize = true; if (g.paysage) opts.landscape = true; }
    await page.pdf(Object.assign({ path: path.join(specs, dossier, nom + '.pdf') }, opts));
    /* Vignette : haut de la première page, JPEG léger. */
    const largeurPx = Math.ceil(g.w / 25.4 * 96);
    await page.screenshot({ path: path.join(vign, dossier, nom + '.jpg'), type: 'jpeg', quality: 45,
      clip: { x: 0, y: 0, width: largeurPx, height: Math.min(hpx, petit ? 1000 : (g.paysage ? 794 : 1123)), scale: petit ? 0.5 : (g.paysage ? 0.3 : 0.36) } });
    manifeste.push({ module: c.module, moduleLabel: c.moduleLabel, dossier: dossier, fichier: nom + '.pdf', vignette: nom + '.jpg', titre: c.titre, gabarit: g.code,
      pageId: c.pageId, ecran: c.ecran, site: c.site, fonction: c.fonction, declencheur: c.declencheur, note: c.note || null });
    process.stdout.write('.');
  }
  console.log('\n' + manifeste.length + ' PDF');
  if (FLAG('incremental')) [...new Set(manifeste.map((m) => m.dossier))].forEach((d) => compresserPdf(path.join(specs, d), manifeste.filter((m) => m.dossier === d).map((m) => m.fichier)));
  else compresserPdf(specs);
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
    + '4. Les identités sont substituées dans le texte (voir Confidentialité), puis la feuille est rendue en PDF par Chrome (`page.pdf`) avec la même feuille de style que le logiciel : A4 portrait ou paysage, ticket 80 mm, carte CR80 aux dimensions réelles.\n'
    + '5. Les ' + COMPLEMENTS.length + ' états que cette exploration n\'atteint pas seule (formulaire à champs obligatoires, plusieurs postes en chaîne, autre profil, activité fermée) sont joués par des scénarios dédiés sur un banc à part (voir « Les 13 spécimens produits par un scénario dédié »).\n'
    + '6. Régénération : `npm run presentation` depuis `prototype_html/` (`build/presentation.js`, phases `capture`, `complements`, `pdf`, `index`).\n\n';
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
    g.items.forEach((m) => { r += '| ' + m.titre.replace(/\|/g, '/') + (m.note ? ' (voir la section « Les 13 spécimens produits par un scénario dédié »)' : '') + ' | ' + m.gabarit + ' | [`specimens/' + d + '/' + m.fichier + '`](specimens/' + d + '/' + m.fichier + ') |\n'; });
    r += '\n';
  });
  const dejaScenarises = new Set(COMPLEMENTS.map((c) => c.page));
  const bilanCompl = fs.existsSync(path.join(TMP, 'complements.json')) ? JSON.parse(fs.readFileSync(path.join(TMP, 'complements.json'), 'utf8')) : [];
  const nbManques = etatsSites.length - nbAtt;
  r += '## Sites sans spécimen\n\n';
  if (!nbManques) {
    r += 'Aucun. Les ' + etatsSites.length + ' sites d\'appel d\'un état figurent au dossier. ' + COMPLEMENTS.length + ' d\'entre eux ont exigé un scénario dédié, décrit ci-dessous : l\'exploration générique ne sait pas saisir un formulaire à champs obligatoires, enchaîner plusieurs postes, ni se connecter sous un autre profil.\n\n';
  } else {
    r += 'Sites d\'état de la maquette qu\'aucun scénario n\'a atteints (' + nbManques + ').\n\n';
    Object.keys(parModule).sort().forEach((m) => {
      const p = parModule[m]; if (!p.manques.length) return;
      r += '### ' + m + ' : ' + p.manques.length + ' non atteint(s)\n\n';
      p.manques.forEach((s) => { r += '- `' + s.fichier + ':' + s.ligne + '` ' + (s.titre ? '« ' + s.titre + ' »' : '(intitulé construit à l\'exécution)') + ' : ' + (RAISONS[s.cle] || 'non atteint, cause non élucidée') + '\n'; });
      r += '\n';
    });
  }
  r += '## Les 13 spécimens produits par un scénario dédié\n\n'
    + 'Chacun est joué par SON écran sur un banc dédié (`npm run presentation`, phase `complements` : base jetable, port propre, une session par rôle quand le geste l\'exige). '
    + 'Les scénarios sont codés dans `build/presentation.js` (`COMPLEMENTS` et `SC[n]`). Aucun fichier de l\'application n\'est modifié.\n\n'
    + '| N° | Site | État | Comment | Fichier |\n|---|---|---|---|---|\n';
  COMPLEMENTS.forEach((c) => {
    const m = manifeste.filter((x) => x.site === c.site && x.pageId === c.page)[0] || manifeste.filter((x) => x.site === c.site)[0];
    r += '| ' + c.n + ' | `' + c.site.replace('assets/js/modules/', '') + '` | ' + (m ? m.titre.replace(/\|/g, '/') : 'NON PRODUIT') + ' | ' + c.comment.replace(/\|/g, '/')
      + (c.note ? ' **Remarque : ' + c.note.replace(/\|/g, '/') + '**' : '') + ' | ' + (m ? '[`' + m.fichier + '`](specimens/' + m.dossier + '/' + m.fichier + ')' : 'aucun') + ' |\n';
  });
  r += '\n**Quatre spécimens exigent une réserve que le lecteur doit connaître** : (6) et (11) viennent de fonctions qu\'aucun geste d\'écran n\'atteint, appelées directement à partir de leur copie dans le source. '
    + '(8) et (9) viennent d\'activités que la clinique ne pratique pas, rouvertes sur le banc seulement. Les 9 autres sont des gestes d\'écran de bout en bout (le bulletin du patient externe et la note de service des évaluations, qui levaient une ReferenceError, s\'impriment désormais par le seul clic).\n\n';
  const defauts = ['`m6-stock.js` : la délivrance de la file de la pharmacie (`PR.delivrer`) n\'écrit aucune ligne au registre des dispensations, seul point d\'impression du « Bon de sortie de stock », et la création manuelle y est retirée : le bon n\'est imprimable par aucun geste d\'écran.'];
  r += '### Défaut de la maquette relevé en les produisant\n\n' + defauts.map((x) => '- ' + x).join('\n') + '\n\nIl est signalé, non corrigé : ce dossier ne modifie aucun fichier de l\'application. Quatre autres défauts relevés à la première production (bulletin du patient externe, note de service, titre de la fenêtre d\'encaissement, clôture de l\'exercice rechargée trop tôt) sont corrigés dans la maquette (écarts E2304 à E2307).\n\n';
  r += '### Écrans autrefois non explorés\n\n'
    + '- `m5-banque-sang`, `m5-donneurs` : activités fermées dans le dépôt, rouvertes sur le banc par `cfg-modules` (spécimens 8 et 9).\n'
    + '- `plan-du-site` : page autonome, sans coquille ni `#page-content` : l\'exploration la déclarait « non peinte » à tort. Elle est peinte (' + ((bilanCompl.filter((b) => b.ecran === 'plan-du-site')[0] || {}).detail || {}).longueur + ' caractères au dernier passage) et ne porte aucune commande d\'impression : aucun état à y relever.\n\n';
  const nonPeintesRestantes = pageNonPeintes.filter((l) => ['m5-banque-sang', 'm5-donneurs', 'plan-du-site'].indexOf(l.page) < 0);
  if (nonPeintesRestantes.length) {
    r += '### Autres écrans non explorés\n\n' + nonPeintesRestantes.map((l) => '- `' + l.page + '` : ' + (l.statut || '') + (l.detail ? ' (' + l.detail + ')' : '')).join('\n') + '\n\n';
  }
  r += '## Limites\n\n'
    + '- Les montants et les lignes sont ceux du jeu de démonstration, à la date du banc (16/08/2026) : un état peut sortir avec des zéros ou des tableaux vides quand le jeu n\'a rien à cette date (l\'arrêté de caisse du jour, par exemple). Rien n\'est inventé pour le remplir.\n'
    + '- Un site d\'impression peut produire plusieurs documents (selon le patient, la modalité, le mois) : seuls les premiers intitulés distincts sont gardés (au plus ' + MAX_PAR_SITE + ' par site).\n'
    + '- Les écrans sont explorés avec le profil administrateur : un état réservé à un autre profil par surcharge d\'écran reste atteignable tant que l\'écran s\'ouvre à l\'administrateur ; les écrans fermés à tous (activités désactivées) ne sont explorés que par les scénarios dédiés (banque de sang).\n'
    + '- Les états de la maquette sont en A4 portrait, sauf le ticket de caisse (rouleau 80 mm), le badge (carte CR80, recto et verso sur une feuille de 93,6 mm) et l\'organigramme (A4 paysage, quatrième gabarit de `print.js`).\n'
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

/* Mise à jour de l'index et du README après un rendu --incremental : seules les lignes des spécimens rendus changent
   (intitulé, gabarit), plus les totaux. La couverture et le contrôle de confidentialité sont rejoués sur tous les PDF. */
function indexerIncremental() {
  const manifeste = JSON.parse(fs.readFileSync(path.join(TMP, 'manifeste.json'), 'utf8'));
  const rd = path.join(SORTIE, 'README.md'), ix = path.join(SORTIE, 'index.html');
  let readme = fs.readFileSync(rd, 'utf8'), index = fs.readFileSync(ix, 'utf8');
  manifeste.forEach((m) => {
    const lien = 'specimens/' + m.dossier + '/' + m.fichier;
    readme = readme.split('\n').map((l) => l.indexOf('`' + lien + '`') < 0 ? l : '| ' + m.titre.replace(/\|/g, '/') + (m.note ? ' (voir la section « Les 13 spécimens produits par un scénario dédié »)' : '') + ' | ' + m.gabarit + ' | [`' + lien + '`](' + lien + ') |').join('\n');
    index = index.replace(new RegExp('(<a class="carte" href="' + lien.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '">)(<img[^>]*>)<div><b>[^<]*</b><span>[^<]*</span></div>'),
      (_, a, img) => a + img + '<div><b>' + esc(m.titre) + '</b><span>' + esc(m.gabarit) + ' · ' + esc(m.ecran || m.pageId) + '</span></div>');
  });
  const taille = tailleDossier(SORTIE);
  readme = readme.replace(/\*\*(\d+) spécimens\*\*, [\d.]+ Mo\./, (_, n) => '**' + n + ' spécimens**, ' + (taille / 1048576).toFixed(1) + ' Mo.');
  readme = readme.replace(/- Les états de la maquette sont tous en A4 portrait, sauf le ticket de caisse \(rouleau 80 mm\) et le badge \(carte CR80, recto et verso sur une feuille de 93,6 mm\)\./,
    '- Les états de la maquette sont en A4 portrait, sauf le ticket de caisse (rouleau 80 mm), le badge (carte CR80, recto et verso sur une feuille de 93,6 mm) et l\'organigramme (A4 paysage, quatrième gabarit de `print.js`).');
  readme = readme.replace('A4 portrait, ticket 80 mm, carte CR80 aux dimensions réelles.', 'A4 portrait ou paysage, ticket 80 mm, carte CR80 aux dimensions réelles.');
  index = index.replace(/(<p>)(\d+) spécimens, par module/, (_, a, n) => a + n + ' spécimens, par module');
  fs.writeFileSync(rd, readme); fs.writeFileSync(ix, index);
  const conf = controleConfidentialite();
  console.log('index.html, README.md mis à jour (' + manifeste.length + ' spécimen(s) rendu(s)), ' + (taille / 1048576).toFixed(2) + ' Mo, confidentialité : ' + conf.nbPdf + ' PDF relus, ' + conf.trouvailles.length + ' trouvaille(s)');
  if (conf.trouvailles.length) console.log(JSON.stringify(conf.trouvailles.slice(0, 20)));
  if (taille > 60 * 1048576) { console.error('TAILLE > 60 Mo'); process.exit(1); }
}

if (require.main !== module) {
  module.exports = { instrumentation, servirFichiers, trouverChrome, slug, attendre, ROOT, SORTIE, TMP, aidesPage };
} else (async () => {
  fs.mkdirSync(TMP, { recursive: true });
  if (PHASE === 'capture' || PHASE === 'tout') await capture();
  if (PHASE === 'complements') await complements();
  if (PHASE === 'tout') {
    /* Dans son propre processus : banc, port et base distincts de ceux de la capture. */
    const r = spawnSync(process.execPath, [__filename, '--phase=complements'], { stdio: 'inherit', env: process.env });
    if (r.status !== 0) { console.error('phase complements en échec'); process.exit(1); }
  }
  if (PHASE === 'pdf' || PHASE === 'tout') await pdf();
  if (PHASE === 'index' || PHASE === 'tout') (FLAG('incremental') ? indexerIncremental : indexer)();
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
