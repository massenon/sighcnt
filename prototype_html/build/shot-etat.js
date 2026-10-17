/* Capture la prévisualisation d'un état officiel — node build/shot-etat.js <page> <selecteurBouton> */
'use strict';
const fs = require('fs');
const path = require('path');
const http = require('http');
const puppeteer = require('puppeteer');

const ROOT = path.resolve(__dirname, '..');
const PORT = 8097;
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.woff2': 'font/woff2', '.jpeg': 'image/jpeg' };

function findBrowser() {
  for (const c of ['C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe']) if (fs.existsSync(c)) return c;
  return null;
}

(async () => {
  const target = process.argv[2] || 'm1-patients.html';
  const label = process.argv[3] || 'Imprimer';
  const out = process.argv[4] || path.join(ROOT, 'build/shot-etat.png');

  const server = http.createServer((req, res) => {
    const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '') || 'index.html';
    const file = path.join(ROOT, rel);
    if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  }).listen(PORT);

  const browser = await puppeteer.launch({ executablePath: findBrowser(), headless: true, args: ['--no-sandbox'] });
  const page = await browser.newPage();
  await page.setViewport({ width: 1400, height: 1200 });
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e.message)));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });

  await page.goto(`http://127.0.0.1:${PORT}/pages/${target}`, { waitUntil: 'networkidle2' });
  await new Promise((r) => setTimeout(r, 500));

  // Clique le premier bouton dont le texte contient `label`
  const clicked = await page.evaluate((lbl) => {
    const btns = [...document.querySelectorAll('button, a')];
    const b = btns.find((x) => (x.textContent || '').toLowerCase().includes(lbl.toLowerCase()));
    if (b) { b.click(); return b.textContent.trim(); }
    return null;
  }, label);

  await new Promise((r) => setTimeout(r, 900));
  await page.screenshot({ path: out, fullPage: false });
  await browser.close();
  server.close();
  console.log('Bouton cliqué : ' + (clicked || 'AUCUN'));
  if (errors.length) console.log('Erreurs JS : ' + errors.join(' | '));
  else console.log('Erreurs JS : aucune');
  console.log('Capture : ' + out);
})();
