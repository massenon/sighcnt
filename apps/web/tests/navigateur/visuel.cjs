'use strict';
/* Mesure visuelle du panneau du relais dans un VRAI navigateur (Chromium via Playwright) contre `php artisan serve` et une base SQLite jetable.
   Usage : node tests/navigateur/visuel.cjs [--sortie=<dossier de captures>] [--sans-capture]  (depuis apps/web ; requiert playwright, php, node).
   Aux quatre largeurs (1440 bureau, 1280 portable, 820 tablette, 390 mobile), sur la page de connexion et les quinze pages du panneau :
   SEUIL 1 : aucun débordement horizontal de la page (scrollWidth <= largeur de fenêtre) ;
   SEUIL 2 : sous 1024 px, toute cible tactile visible (lien de navigation, bouton, champ) mesure au moins 44 x 44 px ;
   SEUIL 3 : aucune erreur JavaScript, aucune page qui ne s'ouvre pas ; la barre latérale est visible à 1024 px et plus, repliée avec un bouton « Menu » en dessous ;
   RELEVÉ (non bloquant) : tout texte de moins de 12 px.
   Sort en code 1 au premier seuil franchi. Le serveur est local, la base est jetable : le relais réel n'est jamais touché. */
const { spawn, execFileSync } = require('node:child_process');
const fs = require('node:fs'); const os = require('node:os'); const path = require('node:path');
const { chromium } = require('playwright');

const arg = (n) => (process.argv.find((a) => a.startsWith('--' + n + '=')) || '').split('=')[1];
const SORTIE = arg('sortie'); const CAPTURES = !process.argv.includes('--sans-capture') && !!SORTIE;
if (CAPTURES) fs.mkdirSync(SORTIE, { recursive: true });
const PORT = 19000 + Math.floor(Math.random() * 900); const BASE = `http://127.0.0.1:${PORT}`;
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'relais-visuel-')); const dbf = path.join(dir, 'relais.sqlite'); fs.writeFileSync(dbf, '');
const racine = path.join(__dirname, '..', '..');
const env = Object.assign({}, process.env, { DB_CONNECTION: 'sqlite', DB_DATABASE: dbf, RELAIS_SECRET_MERE: 'secret-visuel', APP_ENV: 'local', SESSION_DRIVER: 'file', CACHE_STORE: 'file', APP_KEY: process.env.APP_KEY || 'base64:' + Buffer.alloc(32, 7).toString('base64') });
const art = (...a) => execFileSync('php', ['artisan', ...a], { env, cwd: racine, encoding: 'utf8' });
const LARGEURS = [['bureau', 1440, 900], ['portable', 1280, 800], ['tablette', 820, 1180], ['mobile', 390, 844]];
const PAGES = ['', 'appareils', 'boites', 'codes', 'indicateurs', 'synchronisation', 'alertes', 'journal', 'superadmin', 'parametres', 'hebergement', 'sauvegarde', 'sms', 'opacite', 'consultation'];
const echecs = []; let bons = 0; const notes = [];
const verifier = (l, ok, d) => { if (ok) bons++; else { echecs.push(l + (d !== undefined ? ' -> ' + JSON.stringify(d) : '')); console.log('   X ' + l + (d !== undefined ? ' -> ' + JSON.stringify(d) : '')); } };

const mesurer = () => {
  const visible = (e) => { const r = e.getBoundingClientRect(); const s = getComputedStyle(e); return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none' && !e.closest('[hidden],[inert]'); };
  const cibles = [...document.querySelectorAll('a[href], button, input:not([type=hidden]), select, textarea, summary')].filter(visible)
    .filter((e) => !(e.tagName === 'A' && e.closest('p, td, li.texte')))
    .filter((e) => { if (e.type !== 'radio' && e.type !== 'checkbox') return true; const l = e.closest('label'); const r = l ? l.getBoundingClientRect() : e.getBoundingClientRect(); return r.height < 44 || r.width < 44; }) // la cible d'une case est son étiquette
    .map((e) => { const r = e.getBoundingClientRect(); return { t: e.tagName.toLowerCase() + (e.id ? '#' + e.id : '') + ':' + (e.textContent || e.name || '').trim().slice(0, 24), w: Math.round(r.width), h: Math.round(r.height) }; })
    .filter((c) => c.w < 44 || c.h < 44);
  const petits = new Set();
  for (const e of document.querySelectorAll('main *, nav *')) { if (!e.childNodes.length || ![...e.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim())) continue; if (!visible(e)) continue; const px = parseFloat(getComputedStyle(e).fontSize); if (px < 12) petits.add(e.tagName + ':' + px); }
  const bouton = document.querySelector('[data-menu-bouton]'); const barre = document.querySelector('nav[aria-label]');
  const aside = document.querySelector('[data-barre]');
  const debordent = document.documentElement.scrollWidth > window.innerWidth ? [...document.querySelectorAll('body *')].filter((e) => { const r = e.getBoundingClientRect(); return r.width > 0 && r.right > window.innerWidth + 0.5 && !e.closest('.defile'); }).slice(0, 4).map((e) => e.tagName.toLowerCase() + '.' + e.className + ' ' + Math.round(e.getBoundingClientRect().right)) : [];
  return { debordent, sw: document.documentElement.scrollWidth, iw: window.innerWidth, cibles, petits: [...petits],
    menuVisible: !!bouton && visible(bouton), barreVisible: !!aside && visible(aside) && aside.getBoundingClientRect().right > 0 && aside.getBoundingClientRect().left >= 0, nav: !!barre };
};

(async () => {
  art('migrate', '--force'); art('relais:superadmin', 'visuel@exemple.bj', '--mot-de-passe=motdepasse-visuel');
  const srv = spawn('php', ['artisan', 'serve', '--host=127.0.0.1', `--port=${PORT}`], { env: Object.assign({}, env, { PHP_CLI_SERVER_WORKERS: '1' }), cwd: racine, stdio: 'ignore', detached: true });
  let nav;
  try {
    for (let i = 0; i < 60; i++) { try { await fetch(BASE + '/panneau/connexion'); break; } catch (e) { await new Promise((r) => setTimeout(r, 250)); } }
    // Données jetables pour que les tableaux ne soient pas vides : trois appareils appairés (jamais de donnée de santé).
    const post = (u, c, h) => fetch(BASE + u, { method: 'POST', headers: Object.assign({ 'content-type': 'application/json', accept: 'application/json' }, h || {}), body: JSON.stringify(c) });
    for (const n of ['poste-visuel-aaaa1111', 'poste-visuel-bbbb2222', 'mobile-visuel-cccc3333']) {
      const code = 'CODE-' + n; await post('/mere/code', { hash: require('node:crypto').createHash('sha256').update(code).digest('hex') }, { 'x-mere': 'secret-visuel' }); await post('/appairage', { code, uuid: n });
    }
    await post('/mere/code', { hash: require('node:crypto').createHash('sha256').update('CODE-LIBRE').digest('hex') }, { 'x-mere': 'secret-visuel' });
    nav = await chromium.launch({ args: ['--no-sandbox'] });
    for (const [nom, w, h] of LARGEURS) {
      const ctx = await nav.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: 1, hasTouch: w < 1024 });
      const page = await ctx.newPage(); const erreurs = []; page.on('pageerror', (e) => erreurs.push(String(e)));
      console.log(`== ${nom} ${w}px`);
      await page.goto(BASE + '/panneau/connexion');
      let m = await page.evaluate(mesurer);
      verifier(`connexion@${w} sans débordement`, m.sw <= m.iw, m);
      if (w < 1024) verifier(`connexion@${w} cibles tactiles >= 44`, m.cibles.length === 0, m.cibles);
      if (CAPTURES) await page.screenshot({ path: path.join(SORTIE, `connexion-${w}.png`), fullPage: true });
      await page.fill('#courriel', 'visuel@exemple.bj'); await page.fill('#mot_de_passe', 'motdepasse-visuel');
      await Promise.all([page.waitForURL(/\/panneau\/?$/), page.click('button[type=submit]')]);
      for (const p of PAGES) {
        const rep = await page.goto(BASE + '/panneau' + (p ? '/' + p : ''), { waitUntil: 'networkidle' });
        const id = `${p || 'tableau'}@${w}`;
        verifier(`${id} s'ouvre`, rep && rep.status() === 200, rep && rep.status());
        m = await page.evaluate(mesurer);
        verifier(`${id} sans débordement horizontal`, m.sw <= m.iw, { sw: m.sw, iw: m.iw, debordent: m.debordent });
        if (w < 1024) verifier(`${id} cibles tactiles >= 44`, m.cibles.length === 0, m.cibles.slice(0, 4));
        if (m.petits.length) notes.push(`${id} texte < 12 px : ${m.petits.join(' ')}`);
        if (w >= 1024) verifier(`${id} barre latérale visible`, m.barreVisible);
        else { verifier(`${id} bouton Menu visible, barre repliée`, m.menuVisible && !m.barreVisible, { menu: m.menuVisible, barre: m.barreVisible }); }
        if (CAPTURES && (p === '' || p === 'appareils' || p === 'synchronisation' || p === 'consultation' || p === 'parametres')) await page.screenshot({ path: path.join(SORTIE, `${p || 'tableau'}-${w}.png`), fullPage: true });
      }
      if (w < 1024) { // le tiroir s'ouvre, se ferme à Échap, garde le focus
        await page.goto(BASE + '/panneau/appareils');
        if (!(await page.$('[data-menu-bouton]'))) { verifier(`tiroir@${w} existe`, false); await ctx.close(); continue; }
        await page.click('[data-menu-bouton]'); await page.waitForTimeout(400);
        const ouvert = await page.evaluate(() => document.querySelector('[data-menu-bouton]').getAttribute('aria-expanded') === 'true' && document.querySelector('[data-barre]').getBoundingClientRect().left >= 0);
        verifier(`tiroir@${w} s'ouvre (aria-expanded)`, ouvert);
        const cibles = await page.evaluate(() => [...document.querySelectorAll('[data-barre] a, [data-barre] button')].map((e) => { const r = e.getBoundingClientRect(); return { h: Math.round(r.height), w: Math.round(r.width) }; }).filter((c) => c.h < 44 || c.w < 44));
        verifier(`tiroir@${w} cibles >= 44`, cibles.length === 0, cibles);
        if (CAPTURES) await page.screenshot({ path: path.join(SORTIE, `tiroir-${w}.png`) });
        await page.keyboard.press('Escape');
        const ferme = await page.evaluate(() => document.querySelector('[data-menu-bouton]').getAttribute('aria-expanded') === 'false');
        verifier(`tiroir@${w} se ferme à Échap`, ferme);
      }
      verifier(`aucune erreur JavaScript@${w}`, erreurs.length === 0, erreurs);
      await ctx.close();
    }
  } finally {
    if (nav) await nav.close(); try { process.kill(-srv.pid); } catch (e) { /* déjà arrêté */ }
    try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) { /* sans effet */ }
  }
  if (notes.length) { console.log('-- relevés non bloquants (texte de moins de 12 px) :'); [...new Set(notes)].slice(0, 12).forEach((n) => console.log('   ' + n)); }
  console.log(`\n${bons} vérifications bonnes, ${echecs.length} mauvaises`);
  process.exit(echecs.length ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
