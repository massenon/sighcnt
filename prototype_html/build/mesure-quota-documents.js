/* =============================================================================
 * MESURE D0 DU LOT DOCS-1 : combien pèsent les documents numérisés dans le magasin
 * -----------------------------------------------------------------------------
 *   SIGH_PORT_PHP=9201 SIGH_BASE_TEST=sigh_banc_d0 SIGH_PORT_TEST=9202 CHROME_PATH=/opt/pw-browsers/chromium node build/mesure-quota-documents.js
 *
 * Ouvre l'écran des documents du patient sur un banc ISOLÉ, puis relève : le poids de `documentsPatient` et de `courriers`, la somme des
 * tailles DÉCLARÉES par les fiches de démonstration, le poids du magasin entier lu de `api/magasin.php`, et ce que coûtent dix scans de
 * 500 Ko déposés en base64 (sonde jetable : la base du banc est jetée). Écrit sur la sortie standard, ne modifie aucun fichier du dépôt.
 * ========================================================================== */
'use strict';
const path = require('path'), http = require('http'), fs = require('fs');
const BANC = require('./_banc');
const puppeteer = require('puppeteer');
const ROOT = path.resolve(__dirname, '..');
const MIME = { '.php': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css', '.woff2': 'font/woff2', '.jpeg': 'image/jpeg', '.png': 'image/png' };
(async () => {
  const php = await BANC.demarrerPhp(ROOT);
  if (!php.php) { console.error(php.raison); process.exit(1); }
  await BANC.banc('reinitialiser');
  const port = Number(process.env.SIGH_PORT_TEST || 9202);
  const server = http.createServer((req, res) => {
    if (req.url.indexOf('/api/') === 0) { BANC.relayer(req, res); return; }
    const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '') || 'index.php';
    const file = path.join(ROOT, rel);
    if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  }).listen(port);
  const browser = await puppeteer.launch({ executablePath: process.env.CHROME_PATH, headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const page = await browser.newPage();
  await BANC.poserSession(page);
  page.setDefaultNavigationTimeout(180000);
  await page.goto('http://127.0.0.1:' + port + '/pages/m1-documents.php');
  await page.waitForFunction(() => { const c = document.getElementById('page-content'); return c && c.children.length > 0 && window.SIGH.store.faitAutorite && window.SIGH.store.faitAutorite(); }, { timeout: 170000 });
  await new Promise((r) => setTimeout(r, 3000));
  const m = await page.evaluate(() => {
    const raw = window.SIGH.store.raw();
    const gros = Object.keys(raw).filter((k) => Array.isArray(raw[k])).map((k) => [k, raw[k].length, JSON.stringify(raw[k]).length]).sort((a, b) => b[2] - a[2]).slice(0, 5);
    const d = raw.documentsPatient || [], c = raw.courriers || [];
    return { magasinChars: JSON.stringify(raw).length, gros,
      documentsPatient: { fiches: d.length, chars: JSON.stringify(d).length, avecBase64: d.filter((x) => x.donnees).length, tailleDeclareeOctets: d.reduce((s, x) => s + (x.taille || 0), 0) },
      courriers: { fiches: c.length, chars: JSON.stringify(c).length, numerise: c.filter((x) => x.numerise).length, avecFichier: c.filter((x) => x.fichier && x.fichier.sha256).length } };
  });
  const poids = await page.evaluate(async () => {
    const S = window.SIGH.store; const jeton = S.jetonServeur();
    async function lire() { const t0 = performance.now(); const r = await fetch('/api/magasin.php', { headers: { 'X-Sigh-Jeton': jeton } }); const b = await r.arrayBuffer(); return { octets: b.byteLength, ms: Math.round(performance.now() - t0) }; }
    const med = async () => { const a = []; for (let i = 0; i < 3; i++) a.push(await lire()); a.sort((x, y) => x.ms - y.ms); return a[1]; };
    const sorties = { base: await med() };
    const b64 = (n) => 'data:application/pdf;base64,' + 'A'.repeat(Math.ceil(n / 3) * 4);
    const col = S.collection('documentsPatient');
    for (let i = 0; i < 10; i++) col.insert({ reference: 'GED-SONDE' + i, code: 'X', patient: 'sonde', type: 'Ordonnance', date: '2026-08-16', fichier: 's.pdf', format: 'PDF', taille: 500 * 1024, donnees: b64(500 * 1024), etat: 'valide', depose: 'sonde' });
    S.pousserMaintenant && S.pousserMaintenant();
    for (let i = 0; i < 80 && S.fileEnAttente && S.fileEnAttente() > 0; i++) await new Promise((r) => setTimeout(r, 250));
    await new Promise((r) => setTimeout(r, 2500));
    sorties.dixScans500Ko = await med();
    return sorties;
  });
  console.log(JSON.stringify(Object.assign({}, m, { lectureMagasin: poids }), null, 1));
  await browser.close(); server.close(); php.php.kill();
})().catch((e) => { console.error(e); process.exit(1); });
