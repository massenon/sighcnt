/* =============================================================================
 * LA GRILLE TARIFAIRE IMPRIMÉE, STRUCTURE ET PAGINATION (PRD-TARIFS, lot TFIN)
 * -----------------------------------------------------------------------------
 *   node build/vecteurs-impression-grille.js [sortie.json] [dossier des images]      (défaut : apps/poste/test/vecteurs/impression_grille.json)
 *
 * Les vecteurs ne se lisent pas dans le code : ils se TIRENT de la maquette en marche. Le générateur ouvre l'écran réel « Tarifs et prix » dans Chrome,
 * clique « Imprimer la grille » et relève la STRUCTURE de la feuille (en-tête officiel, titre, colonnes, lignes, signatures, pied) et le nombre de pages A4 du PDF que Chrome en tire
 * (`page.pdf`, média print). Le poste rejoue la structure dans `test/impression_grille_test.dart`. Une comparaison PIXEL contre le poste n'est pas possible ici : voir ECARTS. Banc isolé : SIGH_PORT_PHP, SIGH_BASE_TEST (nom portant « banc »), SIGH_PORT_TEST, CHROME_PATH. L'horloge du banc est
 * le 16/08/2026 : toute date du relevé est déterministe.
 * ========================================================================== */
'use strict';
const fs = require('fs'), path = require('path'), http = require('http');
const ROOT = path.resolve(__dirname, '..');
const REPO = path.resolve(ROOT, '..');
const BANC = require('./_banc');
const puppeteer = require('puppeteer');
const PORT = Number(process.env.SIGH_PORT_TEST) || 8096;

(async () => {
  const sortie = process.argv[2] || path.join(REPO, 'apps/poste/test/vecteurs/impression_grille.json');
  const dossierImg = process.argv[3] || null;
  const php = await BANC.demarrerPhp(ROOT);
  if (!php.php) { console.error(php.raison); process.exit(1); }
  const vidage = await BANC.banc('reinitialiser');
  if (vidage.erreur) { console.error(vidage); try { php.php.kill(); } catch (e) { /* mort */ } process.exit(1); }
  const MIME = { '.php': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css', '.woff2': 'font/woff2', '.png': 'image/png', '.jpeg': 'image/jpeg' };
  const srv = http.createServer((req, res) => {
    if (req.url.indexOf('/api/') === 0) { BANC.relayer(req, res); return; }
    const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '') || 'index.php';
    const f = path.join(ROOT, rel);
    if (!fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' }); fs.createReadStream(f).pipe(res);
  }).listen(PORT);
  const br = await puppeteer.launch({ executablePath: process.env.CHROME_PATH, headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const page = await br.newPage(); await BANC.poserSession(page);
  page.setDefaultNavigationTimeout(180000); page.setDefaultTimeout(180000);
  const erreurs = []; page.on('pageerror', (e) => erreurs.push(e.message));
  await page.goto('http://127.0.0.1:' + PORT + '/pages/cfg-tarifs.php', { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => { const S = window.SIGH && window.SIGH.store; const c = document.getElementById('page-content'); return S && (!S.faitAutorite || S.faitAutorite()) && c && c.children.length > 0; }, { timeout: 150000 });
  await new Promise((r) => setTimeout(r, 800));

  await page.setViewport({ width: 1280, height: 900, deviceScaleFactor: 1 });
  await page.evaluate(() => { const b = [...document.querySelectorAll('button')].find((x) => x.textContent.trim() === 'Imprimer la grille'); b.click(); });
  await page.waitForSelector('.print-sheet', { timeout: 20000 });
  await new Promise((r) => setTimeout(r, 800));
  const R = await page.evaluate(() => {
    const feuille = document.querySelector('.print-sheet');
    const t = (e) => (e ? e.textContent.replace(/\s+/g, ' ').trim() : null);
    const table = feuille.querySelector('table');
    const lignes = [...table.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((c) => t(c)));
    return {
      _doc: 'Structure de la feuille « Imprimer la grille » de la maquette (Tarifs et prix), tirée du DOM réel ; pagination du PDF Chrome (média print, A4).',
      largeurMm: feuille.style.width, hauteurMm: feuille.style.minHeight,
      titre: t(feuille.querySelector('h1')),
      sousTitre: t(feuille.querySelector('h1').parentElement.querySelector('p')),
      entete: t(feuille.querySelector('header')) || t(feuille.firstElementChild.firstElementChild),
      colonnes: [...table.querySelectorAll('thead th')].map((th) => t(th)),
      nbLignes: lignes.length, premieres: lignes.slice(0, 3), dernieres: lignes.slice(-3),
      signatures: [...feuille.querySelectorAll('[class*="signature"], .signatures *')].map((e) => t(e)).filter(Boolean).slice(0, 8),
      texteComplet: t(feuille),
    };
  });
  await page.emulateMediaType('print');
  const pdf = await page.pdf({ format: 'A4', printBackground: true, preferCSSPageSize: false });
  R.pagesPdf = Number((Buffer.from(pdf).toString('latin1').match(/\/Count (\d+)/) || [0, 0])[1]);
  if (dossierImg) { fs.mkdirSync(dossierImg, { recursive: true }); fs.writeFileSync(path.join(dossierImg, 'grille-maquette.pdf'), Buffer.from(pdf)); await page.emulateMediaType('screen'); const f = await page.$('.print-sheet'); await f.screenshot({ path: path.join(dossierImg, 'grille-maquette-page1.png') }); }
  fs.mkdirSync(path.dirname(sortie), { recursive: true });
  fs.writeFileSync(sortie, JSON.stringify(R, null, 1));
  console.log('Structure écrite : ' + sortie + ' (' + R.nbLignes + ' lignes, ' + R.pagesPdf + ' page(s) PDF ; erreurs JS : ' + erreurs.length + ')');
  await br.close(); srv.close(); try { php.php.kill(); } catch (e) { /* mort */ }
  process.exit(erreurs.length ? 1 : 0);
})();
