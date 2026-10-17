/* =============================================================================
 * Conversion d'images WebP en PNG
 * -----------------------------------------------------------------------------
 *   node build/_webp2png.js <dossier source> <dossier sortie>
 * Le moteur de Chrome décode le WebP et le réenregistre en PNG, format que les
 * outils de lecture d'images acceptent.
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const http = require('http');
const puppeteer = require('puppeteer');

const PORT = 8095;

function findBrowser() {
  for (const c of [process.env.CHROME_PATH, 'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].filter(Boolean)) {
    if (fs.existsSync(c)) return c;
  }
  return null;
}

(async () => {
  const source = path.resolve(process.argv[2]);
  const sortie = path.resolve(process.argv[3] || 'build/webp');
  fs.mkdirSync(sortie, { recursive: true });

  const serveur = http.createServer((req, res) => {
    const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '');
    const fichier = path.join(source, rel);
    if (!fs.existsSync(fichier)) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': 'image/webp' });
    fs.createReadStream(fichier).pipe(res);
  }).listen(PORT);

  const nav = await puppeteer.launch({ executablePath: findBrowser(), headless: true, args: ['--no-sandbox'] });
  const page = await nav.newPage();

  for (const nom of fs.readdirSync(source).filter((f) => f.toLowerCase().endsWith('.webp'))) {
    await page.setContent(`<style>body{margin:0}img{display:block}</style>`
      + `<img id="i" src="http://127.0.0.1:${PORT}/${encodeURIComponent(nom)}">`, { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => { const i = document.getElementById('i'); return i && i.complete && i.naturalWidth > 0; }, { timeout: 20000 });
    const taille = await page.evaluate(() => {
      const i = document.getElementById('i');
      return { l: i.naturalWidth, h: i.naturalHeight };
    });
    await page.setViewport({ width: taille.l, height: taille.h });
    const cible = path.join(sortie, nom.replace(/\.webp$/i, '.png'));
    await page.screenshot({ path: cible });
    console.log('  → ' + cible + '  (' + taille.l + '×' + taille.h + ')');
  }

  await nav.close();
  serveur.close();
})();
