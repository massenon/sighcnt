/* Capture d'écran d'une page du prototype — node build/shot.js <page> [largeur] */
'use strict';
const fs = require('fs');
const path = require('path');
const http = require('http');
const puppeteer = require('puppeteer');

const ROOT = path.resolve(__dirname, '..');
const PORT = 8098;
const MIME = { '.php': 'text/html; charset=utf-8', '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.woff2': 'font/woff2', '.jpeg': 'image/jpeg', '.png': 'image/png' };

function findBrowser() {
  for (const c of [process.env.CHROME_PATH, 'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].filter(Boolean)) {
    if (fs.existsSync(c)) return c;
  }
  return null;
}

(async () => {
  /* On accepte encore `.html` en argument : la commande est dans les
   habitudes et dans la documentation. Elle est normalisée ici. */
const target = (process.argv[2] || 'index.php').replace(/\.html(#|$)/, '.php$1');
  const width = Number(process.argv[3] || 1440);
  const out = process.argv[4] || path.join(ROOT, 'build/shot.png');

  const server = http.createServer((req, res) => {
    const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '') || 'index.php';
    const file = path.join(ROOT, rel);
    if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  }).listen(PORT);

  const browser = await puppeteer.launch({ executablePath: findBrowser(), headless: true, args: ['--no-sandbox'] });
  const page = await browser.newPage();
  await page.setViewport({ width, height: 1000, deviceScaleFactor: 1 });
  const url = `http://127.0.0.1:${PORT}/${target.includes('/') || target === 'index.php' ? target : 'pages/' + target}`;
  await page.goto(url, { waitUntil: 'networkidle2' });
  await new Promise((r) => setTimeout(r, 700));
  await page.screenshot({ path: out, fullPage: process.argv.includes('--full') });
  await browser.close();
  server.close();
  console.log('Capture : ' + out);
})();
