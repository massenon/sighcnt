/* =============================================================================
 * Rendu des pages d'un PDF scanné en images PNG
 * -----------------------------------------------------------------------------
 * Les documents de cadrage sont des numérisations CamScanner : ils ne portent
 * aucune couche texte. On les rend donc via le moteur de Chrome (pdf.js dans la
 * page, canvas fourni par le navigateur) afin de pouvoir les lire.
 *     node build/_pdf2png.js "../docs/fichier.pdf" dossierSortie [echelle]
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const http = require('http');
const puppeteer = require('puppeteer');

const ROOT = path.resolve(__dirname, '..');
const PORT = 8094;

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
  const echelle = Number(process.argv[4] || 2);
  if (!fs.existsSync(pdfPath)) { console.error('Fichier introuvable : ' + pdfPath); process.exit(1); }
  fs.mkdirSync(outDir, { recursive: true });

  const pdfBuf = fs.readFileSync(pdfPath);

  /* Page hôte : charge pdf.js et expose une fonction de rendu. */
  const hote = `<!doctype html><html><head><meta charset="utf-8"></head><body>
<script type="module">
  import * as pdfjs from '/vendor/pdf.mjs';
  pdfjs.GlobalWorkerOptions.workerSrc = '/vendor/pdf.worker.mjs';
  window.__pret = (async () => {
    const rep = await fetch('/document.pdf');
    const buf = new Uint8Array(await rep.arrayBuffer());
    window.__doc = await pdfjs.getDocument({ data: buf }).promise;
    return window.__doc.numPages;
  })();
  window.__rendre = async (n, echelle) => {
    const page = await window.__doc.getPage(n);
    const viewport = page.getViewport({ scale: echelle });
    const canvas = document.createElement('canvas');
    canvas.width = Math.floor(viewport.width);
    canvas.height = Math.floor(viewport.height);
    await page.render({ canvasContext: canvas.getContext('2d'), viewport }).promise;
    return canvas.toDataURL('image/png');
  };
</script></body></html>`;

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
  page.on('console', (m) => { if (m.type() === 'error') console.error('Console :', m.text()); });
  page.on('requestfailed', (r) => console.error('Requête échouée :', r.url(), r.failure() && r.failure().errorText));
  await page.goto(`http://127.0.0.1:${PORT}/`, { waitUntil: 'networkidle2' });

  /* Le script est un module : il se charge de façon asynchrone et les gros PDF
     mettent plusieurs secondes à s'ouvrir. On attend donc explicitement. */
  await page.waitForFunction(() => typeof window.__pret !== 'undefined', { timeout: 120000 });
  const nbPages = await page.evaluate(() => window.__pret);
  console.log(path.basename(pdfPath) + ' — ' + nbPages + ' page(s)');

  const base = path.basename(pdfPath, '.pdf').replace(/[^a-zA-Z0-9]+/g, '-').replace(/^-|-$/g, '');
  for (let i = 1; i <= nbPages; i++) {
    const dataUrl = await page.evaluate((n, e) => window.__rendre(n, e), i, echelle);
    const out = path.join(outDir, `${base}-p${String(i).padStart(2, '0')}.png`);
    fs.writeFileSync(out, Buffer.from(dataUrl.split(',')[1], 'base64'));
    console.log('  → ' + path.relative(ROOT, out));
  }

  await browser.close();
  server.close();
})().catch((e) => { console.error('ERREUR :', e.message); process.exit(1); });
