/* =============================================================================
 * Extraction de la COUCHE TEXTE d'un PDF — quand il en a une
 * -----------------------------------------------------------------------------
 * Les documents de cadrage sont pour la plupart des numérisations CamScanner,
 * sans couche texte : il faut les rendre en images et les lire (_pdf2png.js).
 * Certains, en revanche, sont des PDF ENGENDRÉS — le plan comptable SYSCOHADA
 * en est un — et portent leur texte. Les lire page par page en image serait
 * alors du gaspillage : trente et une images là où un fichier texte suffit.
 *     node build/_pdftext.js "../fichier.pdf" dossierSortie
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const http = require('http');
const puppeteer = require('puppeteer');

const ROOT = path.resolve(__dirname, '..');
const PORT = 8095;

function findBrowser() {
  for (const c of [process.env.CHROME_PATH, 'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].filter(Boolean)) {
    if (fs.existsSync(c)) return c;
  }
  return null;
}

const MIME = {
  '.html': 'text/html; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8', '.pdf': 'application/pdf', '.map': 'application/json',
};

(async () => {
  const pdfPath = path.resolve(process.argv[2]);
  const outDir = path.resolve(process.argv[3] || path.join(ROOT, 'build/pdf-pages'));
  if (!fs.existsSync(pdfPath)) { console.error('Fichier introuvable : ' + pdfPath); process.exit(1); }
  fs.mkdirSync(outDir, { recursive: true });

  const pdfBuf = fs.readFileSync(pdfPath);

  const hote = '<!doctype html><html><head><meta charset="utf-8"></head><body>'
    + '<script type="module">'
    + "import * as pdfjs from '/vendor/pdf.mjs';"
    + "pdfjs.GlobalWorkerOptions.workerSrc = '/vendor/pdf.worker.mjs';"
    + 'window.__pret = (async () => {'
    + "  const rep = await fetch('/document.pdf');"
    + '  const buf = new Uint8Array(await rep.arrayBuffer());'
    + '  window.__doc = await pdfjs.getDocument({ data: buf }).promise;'
    + '  return window.__doc.numPages;'
    + '})();'
    /* Le retour à la ligne se déduit du saut vertical entre deux fragments :
       pdf.js rend des morceaux positionnés, pas des lignes. */
    + 'window.__texte = async (n) => {'
    + '  const page = await window.__doc.getPage(n);'
    + '  const tc = await page.getTextContent();'
    + "  let out = '', y = null;"
    + '  for (const it of tc.items) {'
    + '    const ty = it.transform ? Math.round(it.transform[5]) : null;'
    + "    if (y !== null && ty !== null && Math.abs(ty - y) > 2) out += String.fromCharCode(10);"
    + '    out += it.str;'
    + '    y = ty;'
    + '  }'
    + '  return out;'
    + '};'
    + '</script></body></html>';

  const vendorDir = path.join(ROOT, 'node_modules/pdfjs-dist/build');
  const server = http.createServer((req, res) => {
    const url = req.url.split('?')[0];
    if (url === '/' || url === '/index.html') {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }); res.end(hote); return;
    }
    if (url === '/document.pdf') {
      res.writeHead(200, { 'Content-Type': 'application/pdf' }); res.end(pdfBuf); return;
    }
    if (url.startsWith('/vendor/')) {
      const f = path.join(vendorDir, url.replace('/vendor/', ''));
      if (fs.existsSync(f)) {
        res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' });
        fs.createReadStream(f).pipe(res); return;
      }
    }
    res.writeHead(404); res.end();
  }).listen(PORT);

  const browser = await puppeteer.launch({ executablePath: findBrowser(), headless: true, args: ['--no-sandbox'] });
  const page = await browser.newPage();
  page.on('pageerror', (e) => console.error('Erreur page :', e.message));
  await page.goto('http://127.0.0.1:' + PORT + '/', { waitUntil: 'networkidle2' });
  await page.waitForFunction(() => typeof window.__pret !== 'undefined', { timeout: 120000 });
  const nbPages = await page.evaluate(() => window.__pret);
  console.log(path.basename(pdfPath) + ' — ' + nbPages + ' page(s)');

  const lignes = [];
  for (let i = 1; i <= nbPages; i++) {
    lignes.push('===== PAGE ' + i + ' =====');
    lignes.push(await page.evaluate((n) => window.__texte(n), i));
  }
  const texte = lignes.join('\n');
  const sortie = path.join(outDir,
    path.basename(pdfPath, '.pdf').replace(/[^a-zA-Z0-9]+/g, '-') + '.txt');
  fs.writeFileSync(sortie, texte);
  console.log('  → ' + path.relative(ROOT, sortie) + ' (' + texte.length + ' caractères)');
  if (texte.replace(/=====[^=]*=====/g, '').trim().length < 200) {
    console.log('  ⚠ Ce PDF ne porte pas de couche texte : le rendre en images (build/_pdf2png.js).');
  }

  await browser.close();
  server.close();
})();
