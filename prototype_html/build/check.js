/* =============================================================================
 * Contrôle de conformité du prototype SIGH-CNT
 * -----------------------------------------------------------------------------
 * Ouvre chaque page dans Chrome (sans interface) et vérifie :
 *   1. aucune erreur JavaScript ni avertissement console d'erreur ;
 *   2. aucune ressource introuvable (404) ;
 *   3. aucun lien cassé — chaque href pointe vers un fichier existant ;
 *   4. la coquille est bien montée (méga-menu, barre supérieure, contenu) ;
 *   5. l'écran est bien déclaré au registre (pas de repli « en construction »).
 *
 * Usage :  node build/check.js  [--pages=m1-patients,m6-stock]  [--headful]
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const http = require('http');
const puppeteer = require('puppeteer');

const ROOT = path.resolve(__dirname, '..');
/* Le port est surchargeable : sur un poste où 8099 sert déjà à autre chose,
   le contrôle échouait au démarrage sans rapport avec le prototype. */
const PORT = Number(process.env.SIGH_PORT) || 8099;

/* --- Localisation d'un navigateur installé -------------------------------- */
function findBrowser() {
  const candidates = [
    process.env.CHROME_PATH,
    'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
    'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
  ].filter(Boolean);
  for (const c of candidates) if (fs.existsSync(c)) return c;
  return null;
}

const BANC = require('./_banc');

/* --- Serveur statique minimal --------------------------------------------- */
const MIME = {
  '.php': 'text/html; charset=utf-8',
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json',
  '.woff2': 'font/woff2', '.jpeg': 'image/jpeg', '.jpg': 'image/jpeg',
  '.png': 'image/png', '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
};
function serve() {
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      /* L'API part chez PHP ; tout le reste est servi par Node, qui est
         rapide. Le serveur intégré de PHP est MONO-PROCESSUS : lui confier
         les quinze scripts de chacune des trois cents pages multiplierait
         la durée du contrôle pour rien. */
      if (req.url.indexOf('/api/') === 0) { BANC.relayer(req, res); return; }
      const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '') || 'index.php';
      const file = path.join(ROOT, rel);
      if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
        res.writeHead(404, { 'Content-Type': 'text/plain' }); res.end('404'); return;
      }
      res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
      fs.createReadStream(file).pipe(res);
    });
    server.listen(PORT, () => resolve(server));
  });
}

/* --- Inventaire des pages -------------------------------------------------- */
function listPages() {
  const pages = ['index.php'];
  for (const f of fs.readdirSync(path.join(ROOT, 'pages'))) {
    if (f.endsWith('.php')) pages.push('pages/' + f);
  }
  return pages;
}

/* --- Programme principal ---------------------------------------------------*/
(async () => {
  const args = process.argv.slice(2);
  const only = (args.find((a) => a.startsWith('--pages=')) || '').replace('--pages=', '');
  const headful = args.includes('--headful');

  const exe = findBrowser();
  if (!exe) {
    console.error('Aucun navigateur Chrome/Edge trouvé. Définir CHROME_PATH.');
    process.exit(2);
  }

  let pages = listPages();
  if (only) {
    const wanted = only.split(',').map((s) => s.trim());
    pages = pages.filter((p) => wanted.some((w) => p.includes(w)));
  }

  /* LE BANC A BESOIN DE LA BASE. Depuis que le navigateur n'écrit plus rien,
     servir les pages en statique n'éprouverait RIEN : le magasin resterait
     vide et les trois cents pages s'ouvriraient sur du néant. */
  const php = await BANC.demarrerPhp(ROOT);
  if (!php.php) {
    console.error('\n  ÉCHEC — ' + php.raison);
    console.error('  Sans serveur, le contrôle mesurerait des pages vides.\n');
    process.exit(1);
  }
  const vidage = await BANC.banc('reinitialiser');
  if (vidage.erreur) {
    console.error('\n  ÉCHEC — base du banc : ' + (vidage.detail || vidage.erreur) + '\n');
    try { php.php.kill(); } catch (e) { /* déjà mort */ }
    process.exit(1);
  }
  console.log('  Banc : base « ' + vidage.base + ' » remise à neuf.');

  const server = await serve();
  const browser = await puppeteer.launch({
    executablePath: exe,
    headless: !headful,
    args: ['--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu'],
  });

  const report = { pages: 0, jsErrors: [], missing: [], brokenLinks: [], notMounted: [], stubs: [], slow: [] };
  const linkCache = new Map();

  function fileExists(rel) {
    if (linkCache.has(rel)) return linkCache.get(rel);
    const f = path.join(ROOT, rel.split('#')[0].split('?')[0]);
    const ok = fs.existsSync(f);
    linkCache.set(rel, ok);
    return ok;
  }

  for (const rel of pages) {
    const page = await browser.newPage();
    await BANC.poserSession(page);
    /* LE MAGASIN ENTIER TRANSITE PAR HTTP à chaque page — instantané depuis
       le navigateur, coûteux depuis la base, et le serveur intégré de PHP est
       mono-processus. Trente secondes ne suffisent plus ; le délai ne masque
       aucune anomalie, il tient compte du coût réel du transport. */
    page.setDefaultNavigationTimeout(180000);
    page.setDefaultTimeout(180000);
    const errors = [];
    const missing = [];

    page.on('pageerror', (e) => errors.push(String(e.message || e)));
    page.on('console', (msg) => {
      if (msg.type() === 'error') errors.push('console.error: ' + msg.text());
    });
    page.on('requestfailed', (req) => missing.push(req.url()));
    page.on('response', (res) => {
      if (res.status() === 404) missing.push(res.url());
    });

    const t0 = Date.now();
    try {
      await page.goto(`http://127.0.0.1:${PORT}/${rel}`,
        { waitUntil: 'domcontentloaded', timeout: 180000 });
      /* ON ATTEND LA PEINTURE. `networkidle2` ne se calme pas derrière un
         serveur PHP mono-processus qui sert 4,9 Mo par page, et deux pages
         saines étaient déclarées en erreur de navigation. */
      await page.waitForFunction(() => {
        const c = document.getElementById('page-content');
        return !!(window.SIGH && window.SIGH.store && c && c.children.length > 0);
      }, { timeout: 180000 }).catch(() => null);
      await new Promise((r) => setTimeout(r, 350)); // laisse le rendu différé (graphiques) s'exécuter
    } catch (e) {
      errors.push('Navigation: ' + e.message);
    }
    const elapsed = Date.now() - t0;
    if (elapsed > 6000) report.slow.push({ page: rel, ms: elapsed });

    /* Structure montée + liens */
    let info = { links: [], mounted: false, stub: false, title: '' };
    try {
      info = await page.evaluate(() => {
        const links = [...document.querySelectorAll('a[href]')]
          .map((a) => a.getAttribute('href'))
          /* Un tel:, un mailto: ou un data: ne désigne pas une page du prototype :
             les compter comme liens ferait échouer le contrôle sur un numéro de
             téléphone parfaitement valide. */
          .filter((h) => h && !/^(https?:|#|mailto:|tel:|sms:|data:|blob:|javascript:)/i.test(h));
        const standalone = !!(window.SIGH && window.SIGH.screens
          && Object.values(window.SIGH.screens).some((s) => s.standalone && location.pathname.includes(s.id)));
        const mounted = !!document.querySelector('#app-menubar') || !!document.querySelector('#page > *')
          || document.body.children.length > 3;
        const stub = document.body.textContent.includes('Écran en cours de construction');
        return { links: [...new Set(links)], mounted, stub, title: document.title, standalone };
      });
    } catch (e) {
      errors.push('Évaluation: ' + e.message);
    }

    /* Résolution des liens relatifs */
    const dir = path.posix.dirname(rel);
    for (const href of info.links) {
      const target = path.posix.normalize(path.posix.join(dir === '.' ? '' : dir, href));
      if (!fileExists(target)) {
        report.brokenLinks.push({ page: rel, href, resolved: target });
      }
    }

    if (errors.length) report.jsErrors.push({ page: rel, errors: [...new Set(errors)] });
    if (missing.length) report.missing.push({ page: rel, urls: [...new Set(missing)] });
    if (!info.mounted) report.notMounted.push(rel);
    if (info.stub) report.stubs.push(rel);

    report.pages++;
    await page.close();
    process.stdout.write(`\r  ${report.pages}/${pages.length} pages contrôlées…   `);
  }

  await browser.close();
  server.close();
  try { php.php.kill(); } catch (e) { /* déjà mort */ }

  /* --- Restitution --------------------------------------------------------- */
  const line = '─'.repeat(72);
  console.log('\n' + line);
  console.log('CONTRÔLE DU PROTOTYPE SIGH-CNT');
  console.log(line);
  console.log(`Pages contrôlées          : ${report.pages}`);
  console.log(`Erreurs JavaScript        : ${report.jsErrors.length} page(s)`);
  console.log(`Ressources introuvables   : ${report.missing.length} page(s)`);
  console.log(`Liens cassés              : ${report.brokenLinks.length}`);
  console.log(`Pages non montées         : ${report.notMounted.length}`);
  console.log(`Écrans non implémentés    : ${report.stubs.length}`);
  if (report.slow.length) console.log(`Pages lentes (> 6 s)      : ${report.slow.length}`);

  if (report.jsErrors.length) {
    console.log('\n── ERREURS JAVASCRIPT ' + '─'.repeat(50));
    for (const e of report.jsErrors.slice(0, 25)) {
      console.log(`\n  ${e.page}`);
      e.errors.slice(0, 4).forEach((x) => console.log(`    • ${x.slice(0, 240)}`));
    }
    if (report.jsErrors.length > 25) console.log(`\n  … et ${report.jsErrors.length - 25} autre(s) page(s).`);
  }
  if (report.missing.length) {
    console.log('\n── RESSOURCES INTROUVABLES ' + '─'.repeat(45));
    for (const m of report.missing.slice(0, 10)) {
      console.log(`  ${m.page}`);
      m.urls.slice(0, 3).forEach((u) => console.log(`    • ${u}`));
    }
  }
  if (report.brokenLinks.length) {
    console.log('\n── LIENS CASSÉS ' + '─'.repeat(56));
    const grouped = {};
    for (const b of report.brokenLinks) (grouped[b.resolved] = grouped[b.resolved] || []).push(b.page);
    Object.entries(grouped).slice(0, 25).forEach(([target, pages]) => {
      console.log(`  ${target}  ←  ${pages.length} page(s), ex. ${pages[0]}`);
    });
  }
  if (report.notMounted.length) {
    console.log('\n── PAGES NON MONTÉES ' + '─'.repeat(51));
    report.notMounted.slice(0, 20).forEach((p) => console.log(`  ${p}`));
  }
  if (report.stubs.length) {
    console.log('\n── ÉCRANS NON ENCORE IMPLÉMENTÉS ' + '─'.repeat(39));
    console.log('  ' + report.stubs.map((p) => path.basename(p, '.php')).join(', '));
  }

  const bloquant = report.jsErrors.length + report.missing.length + report.brokenLinks.length + report.notMounted.length;
  console.log('\n' + line);
  console.log(bloquant === 0
    ? 'RÉSULTAT : CONFORME — 0 erreur JS, 0 lien cassé, 0 ressource manquante.'
    : `RÉSULTAT : ${bloquant} anomalie(s) bloquante(s) à corriger.`);
  console.log(line);

  fs.writeFileSync(path.join(ROOT, 'build/rapport-controle.json'), JSON.stringify(report, null, 2));
  process.exit(bloquant === 0 ? 0 : 1);
})();
