/* Contrôle du simulateur mobile : chaque écran s'ouvre sans erreur sous chaque profil qui y a droit, un écran fermé se NOMME,
   et le parcours « saisie hors ligne → file d'envoi → retour du réseau → acceptée » tient.   node build/check-mobile.js */
'use strict';
const fs = require('fs'), path = require('path'), http = require('http');
const { chromium } = require('playwright');
const M = require('../mobile/manifeste.js');
const ROOT = path.resolve(__dirname, '..');
const MIME = { '.php': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.jpeg': 'image/jpeg' };
const PORT = Number(process.env.SIGH_PORT_MOBILE || 8591);
let echecs = 0, total = 0;
const verifier = (nom, ok, detail) => { total++; if (!ok) { echecs++; console.log('  ✗ ' + nom + (detail ? ' — ' + detail : '')); } };

(async () => {
  const srv = http.createServer((req, res) => {
    const f = path.join(ROOT, decodeURIComponent(req.url.split('?')[0]));
    if (!f.startsWith(ROOT) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end(); }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' }); fs.createReadStream(f).pipe(res);
  }).listen(PORT);
  const nav = await chromium.launch();
  const ctx = await nav.newContext({ viewport: { width: 390, height: 844 } });
  const page = await ctx.newPage();
  let erreurs = [];
  page.on('pageerror', (e) => erreurs.push(e.message));
  const base = `http://127.0.0.1:${PORT}/mobile/ecrans/`;
  const ouvrir = async (id, profil, os, extra) => { await page.goto(`${base}${id}.php?os=${os || 'ios'}&profil=${profil}${extra || ''}`); await page.waitForSelector('.barre'); };

  console.log('▶ Ouverture de chaque écran sous chaque profil');
  for (const profil of Object.keys(M.PROFILS)) {
    for (const e of M.ECRANS) {
      erreurs = [];
      await page.goto(base + '../index.php'); await page.evaluate(() => localStorage.clear());
      await ouvrir(e.id, profil, e.id.length % 2 ? 'ios' : 'android', '&p=p4');
      const ouvert = e.profils.includes(profil);
      const texte = await page.evaluate(() => document.body.innerText);
      if (ouvert) verifier(`${e.id} / ${profil} : s'ouvre`, !/fermé au profil/.test(texte) && erreurs.length === 0, erreurs.join('|'));
      else if (!e.avantSession) verifier(`${e.id} / ${profil} : fermé et NOMMÉ`, /fermé au profil/.test(texte) && erreurs.length === 0);
    }
  }

  console.log('▶ Parcours hors ligne');
  await page.goto(base + '../index.php'); await page.evaluate(() => { localStorage.clear(); localStorage.setItem('sighm:reseau', '"hors-ligne"'); });
  await ouvrir('constantes', 'soignant', 'ios', '&p=p1');
  await page.fill('#temperature', '57'); await page.click('#ok');
  verifier('température improbable refusée EN LA NOMMANT', /valeur improbable/.test(await page.innerText('[data-champ="temperature"]')));
  await page.fill('#temperature', '38,6'); await page.fill('#pouls', '96'); await page.click('#ok');
  await page.waitForURL(/dossier\.php/);
  await ouvrir('sync', 'soignant', 'ios');
  let t = await page.innerText('main');
  verifier('hors ligne : la saisie est dans la file, « En attente »', /Constantes — DOSSOU Aline/.test(t) && /En attente/.test(t) && /Hors ligne/.test(await page.innerText('#bandeau')));
  await page.evaluate(() => localStorage.setItem('sighm:reseau', '"en-ligne"'));
  await ouvrir('sync', 'soignant', 'ios');
  t = await page.innerText('main');
  verifier('retour du réseau : la file part, « Acceptée »', /Acceptée/.test(t) && !/En attente/.test(t));

  console.log('▶ Réception de secours : numéro de la plage, doublon signalé et NON refusé');
  await page.evaluate(() => localStorage.clear());
  await ouvrir('nouveau-dossier', 'reception', 'android');
  verifier('numéro réservé affiché', /CNT\/1241\/26/.test(await page.innerText('main')));
  await page.fill('#nom', 'Akpo'); await page.fill('#prenom', 'Marc'); await page.fill('#age', '34'); await page.click('#ok');
  await page.waitForTimeout(2600);
  await ouvrir('dossiers-crees', 'reception', 'android');
  t = await page.innerText('main');
  verifier('dossier ouvert, code attribué, doublon signalé', /AKPO Marc/.test(t) && /CNT\/1241\/26/.test(t) && /Doublon/.test(t));
  await ouvrir('nouveau-dossier', 'reception', 'android');
  verifier('le numéro suivant a avancé', /CNT\/1242\/26/.test(await page.innerText('main')));

  console.log('▶ Appairage');
  await page.evaluate(() => localStorage.clear());
  await ouvrir('appairage', 'soignant', 'ios');
  await page.fill('#code', 'EXPIREE1'); await page.fill('#cle', 'x'); await page.click('#go');
  verifier('code expiré refusé et nommé', /expiré/.test(await page.innerText('[data-champ="code"]')));
  await page.fill('#code', 'ab'); await page.click('#go');
  verifier('code invalide refusé', /invalide/.test(await page.innerText('[data-champ="code"]')));

  await nav.close(); srv.close();
  console.log(`\n${total - echecs}/${total} vérifications · ${M.ECRANS.length} écrans · ${Object.keys(M.PROFILS).length} profils`);
  process.exit(echecs ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
