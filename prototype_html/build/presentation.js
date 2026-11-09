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
const EXCLU_RE = /^(nouveau|nouvelle|ajouter|créer|archiver|supprimer|restaurer|annuler|encaisser|clôturer|cloturer|modifier|enregistrer|fermer|filtrer|rechercher|colonnes|exporter|tout |rafra|actualiser|réinitialiser|se déconnecter|déconnexion|retour|précédent|suivant|\d+$)/i;
const DIALOGUE_RE = /^(éditer|imprimer|générer|afficher|aperçu|prévisualiser|lancer|continuer|confirmer|valider|émettre|emettre|enregistrer|oui|ok|calculer|établir|produire|exporter en pdf)\b/i;

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
      return Array.prototype.map.call(document.querySelectorAll('#page-content [role=tab]'), (b, i) => {
        const id = 't' + i; b.setAttribute('data-pres-tab', id);
        return { id: id, texte: (b.textContent || '').trim().slice(0, 40) };
      });
    },
    ongletClic(id) { const el = document.querySelector('[data-pres-tab="' + id + '"]'); if (el) el.click(); return !!el; },
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
  const browser = await puppeteer.launch({ executablePath: chrome, headless: true, args: ['--no-sandbox'] });

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
    let ctx = null;
    try {
      ctx = await ouvrir(id);
      if (!ctx.ok) { log.push({ page: id, statut: 'non peinte' }); try { await ctx.page.close(); } catch (e) {} continue; }
      const { page } = ctx;
      const info = await page.evaluate((i) => { const e = window.SIGH.nav.INDEX[i]; return e ? { module: e.module, moduleLabel: e.moduleLabel, label: e.label } : { module: 'HORS', moduleLabel: 'Hors ruban', label: i }; }, id);
      if (filtreModules && filtreModules.indexOf(info.module) < 0) { await page.close(); continue; }
      const clics = new Set();
      let nbEtats = 0;
      const url0 = await page.evaluate(() => window.__pres.chemin());

      async function retablir() {
        const c = await page.evaluate(() => window.__pres.chemin()).catch(() => null);
        if (c !== url0) {
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
      const stats = await page.evaluate(() => ({ s: window.__pres.sites, t: window.__pres.tab })).catch(() => ({ s: {}, t: {} }));
      Object.keys(stats.s).forEach((k) => { sitesTouches[k] = (sitesTouches[k] || 0) + stats.s[k]; });
      Object.keys(stats.t).forEach((k) => { tablTouches[k] = (tablTouches[k] || 0) + stats.t[k]; });
      log.push({ page: id, module: info.module, etats: nbEtats, sites: Object.keys(stats.s).length, erreurs: ctx.erreurs.length, ms: Date.now() - t0 });
      console.log(id.padEnd(40), info.module.padEnd(6), 'états', nbEtats, 'sites', Object.keys(stats.s).length, (Date.now() - t0) + ' ms');
      await page.close();
    } catch (e) {
      log.push({ page: id, statut: 'erreur', detail: String(e.message).slice(0, 200) });
      console.log(id, 'ERREUR', String(e.message).slice(0, 120));
      try { if (ctx && ctx.page) await ctx.page.close(); } catch (e2) { /* déjà fermée */ }
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

  fs.writeFileSync(path.join(TMP, 'releve-' + i + '.json'), JSON.stringify({ sites: sitesTouches, tableaux: tablTouches, log: log }));
  await browser.close(); web.close(); try { dem.php.kill(); } catch (e) {}
}

/* ==========================================================================
 * PHASE 2 : PDF (substitution des identités, filigrane, rendu)
 * ======================================================================= */
const POOL_NOMS = ['ADJOVI', 'SOSSA', 'HOUNKPATIN', 'AKPLOGAN', 'DOSSOU', 'KINGBO', 'TOGNIFODE', 'AGBO', 'LOKOSSOU', 'VODOUNON',
  'ZINSOU', 'AHOUANDJINOU', 'GLELE', 'ASSOGBA', 'DEGBE', 'HOUESSOU', 'AMOUSSOU', 'FADO', 'GNANSOUNOU', 'OKE', 'SAGBO', 'TCHIBOZO',
  'AZONHE', 'BIAOU', 'CAKPO', 'DAKO', 'EDAH', 'FASSINOU', 'GBAGUIDI', 'HOUNSA', 'IDOHOU', 'JOHNSON', 'KOUTON', 'LAWSON', 'MEDEGAN',
  'NOUATIN', 'OGOUNCHI', 'PADONOU', 'QUENUM', 'ROUSSEAU', 'SAKA', 'TOKPANOU', 'UNGUENON', 'VIGNON', 'WANKPO', 'YEHOUENOU', 'ZOUNON',
  'ABOKI', 'BONOU', 'CODJIA', 'DJOSSOU', 'EGOUNLETI', 'FOLLY', 'GANDONOU', 'HOUNGBO', 'ISSIAKA', 'KPADE', 'LEGBA', 'MONTCHO', 'NAGO'];
const POOL_PRENOMS = ['Marcelle', 'Théodore', 'Prisca', 'Gaspard', 'Colette', 'Fidèle', 'Judith', 'Anicet', 'Rosine', 'Clément', 'Estelle',
  'Barnabé', 'Sylvie', 'Rodolphe', 'Léontine', 'Isidore', 'Mireille', 'Casimir', 'Ursule', 'Basile', 'Odile', 'Thaddée', 'Nadège',
  'Cyriaque', 'Honorine', 'Maxime', 'Brigitte', 'Aristide', 'Pélagie', 'Lucien', 'Yolande', 'Hilaire', 'Séverine', 'Constant',
  'Annick', 'Gildas', 'Berthe', 'Narcisse', 'Euphrasie', 'Médard', 'Adélaïde', 'Romuald', 'Clarisse', 'Vianney', 'Perpétue',
  'Armand', 'Josiane', 'Fabrice', 'Gisèle', 'Hyacinthe', 'Irène', 'Landry', 'Mélanie', 'Octave', 'Philomène', 'Quentin', 'Reine',
  'Sidoine', 'Tatiana', 'Valéry'];
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

/* Exécuté dans la page de rendu : remplace dans tout nœud texte et attribut. */
function substituerDansPage(donnees) {
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
  const tw = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  let n; while ((n = tw.nextNode())) { const v = remplacer(n.nodeValue); if (v !== n.nodeValue) n.nodeValue = v; }
  document.querySelectorAll('*').forEach((el) => {
    ['title', 'alt', 'aria-label', 'placeholder', 'value'].forEach((a) => { const v = el.getAttribute(a); if (v) { const w = remplacer(v); if (w !== v) el.setAttribute(a, w); } });
  });
}

function gabarit(largeur) {
  const w = parseFloat(largeur) || 210;
  if (largeur && /mm$/.test(largeur) && w <= 120) return { code: w <= 60 ? 'carte CR80' : 'ticket 80 mm', w: w };
  return { code: 'A4 portrait', w: 210 };
}

async function pdf() {
  const puppeteer = require('puppeteer');
  const port = 8987;
  const web = await servirFichiers(port, null);
  const ident = JSON.parse(fs.readFileSync(path.join(TMP, 'identites.json'), 'utf8'));
  const { mapping, nums } = tableSubstitution(ident);
  const donnees = { mapping: [...mapping], nums: [...nums] };
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
    const g = gabarit(c.largeur);
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
      + '.pres-filigrane{position:fixed;left:0;right:0;top:0;bottom:0;display:flex;align-items:center;justify-content:center;pointer-events:none;z-index:9999}'
      + '.pres-filigrane span{transform:rotate(-32deg);font:700 ' + (petit ? '15px' : '46px') + '/1.1 Inter,Arial,sans-serif;color:rgba(185,28,28,.16);text-transform:uppercase;letter-spacing:.06em;text-align:center;white-space:nowrap}'
      + '.pres-bandeau{position:fixed;left:0;right:0;bottom:0;text-align:center;font:600 ' + (petit ? '6px' : '8px') + '/1.4 Inter,Arial,sans-serif;color:#b91c1c;background:rgba(254,226,226,.85);padding:1px 0;z-index:9999;text-transform:uppercase;letter-spacing:.08em}'
      + '@page{size:' + (petit ? g.w + 'mm auto' : 'A4') + ';margin:0}</style></head><body>'
      + c.html + '<div class="pres-filigrane"><span>' + filigrane + '</span></div><div class="pres-bandeau">' + filigrane + '</div></body></html>';
    await page.setViewport({ width: Math.ceil(g.w / 25.4 * 96) + 2, height: 1200 });
    await page.setContent(html, { waitUntil: 'networkidle0', timeout: 60000 });
    await page.emulateMediaType('print');
    await page.evaluate(substituerDansPage, donnees);
    await attendre(80);
    const hpx = await page.evaluate(() => Math.ceil(document.querySelector('.print-sheet, article').getBoundingClientRect().height));
    fs.mkdirSync(path.join(specs, dossier), { recursive: true }); fs.mkdirSync(path.join(vign, dossier), { recursive: true });
    const opts = { printBackground: true, margin: { top: 0, right: 0, bottom: 0, left: 0 } };
    if (petit) { opts.width = g.w + 'mm'; opts.height = (Math.ceil(hpx * 25.4 / 96) + 2) + 'mm'; } else { opts.format = 'A4'; opts.preferCSSPageSize = true; }
    await page.pdf(Object.assign({ path: path.join(specs, dossier, nom + '.pdf') }, opts));
    /* Vignette : haut de la première page, JPEG léger. */
    const largeurPx = Math.ceil(g.w / 25.4 * 96);
    await page.screenshot({ path: path.join(vign, dossier, nom + '.jpg'), type: 'jpeg', quality: 55,
      clip: { x: 0, y: 0, width: largeurPx, height: Math.min(hpx, petit ? 1000 : 1123) } });
    manifeste.push({ module: c.module, moduleLabel: c.moduleLabel, dossier: dossier, fichier: nom + '.pdf', vignette: nom + '.jpg', titre: c.titre, gabarit: g.code,
      pageId: c.pageId, ecran: c.ecran, site: c.site, fonction: c.fonction, declencheur: c.declencheur });
    process.stdout.write('.');
  }
  console.log('\n' + manifeste.length + ' PDF');
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

function indexer() {
  const manifeste = JSON.parse(fs.readFileSync(path.join(TMP, 'manifeste.json'), 'utf8'));
  const sites = inventaireSites();
  const releves = fs.readdirSync(TMP).filter((f) => /^releve-\d+\.json$/.test(f)).map((f) => JSON.parse(fs.readFileSync(path.join(TMP, f), 'utf8')));
  const touches = {}, tabTouches = {}, pagesLog = [];
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
  manifeste.forEach((m) => { (groupes[m.dossier] = groupes[m.dossier] || { label: m.module + ' ' + m.moduleLabel, items: [] }).items.push(m); });
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
    p.manques.forEach((s) => { r += '- `' + s.fichier + ':' + s.ligne + '` ' + (s.titre ? '« ' + s.titre + ' »' : '(intitulé construit à l\'exécution)') + '\n'; });
    r += '\n';
  });
  if (pageNonPeintes.length) {
    r += '### Écrans non explorés\n\n' + pageNonPeintes.map((l) => '- `' + l.page + '` : ' + (l.statut || '') + (l.detail ? ' (' + l.detail + ')' : '')).join('\n') + '\n\n';
  }
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
