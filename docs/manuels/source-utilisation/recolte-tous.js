/* Récolte, pour CHAQUE écran du manifeste, du titre, de la phrase d'aide, des onglets, des boutons et des colonnes réels (rôle administrateur).
   Sert à rédiger le répertoire des écrans sans rien deviner. node recolte-tous.js [sortie.json] */
'use strict';
const fs = require('fs');
const O = require('./outils');
const M = require('../../../packages/referentiels/data/manifeste.json');
(async () => {
  const sortie = process.argv[2] || '/tmp/recolte-tous.json';
  const out = fs.existsSync(sortie) ? JSON.parse(fs.readFileSync(sortie, 'utf8')) : {};
  let { browser, page } = await O.ouvrirNavigateur();
  let n = 0;
  for (const e of M.ecrans) {
    if (out[e.id] && !out[e.id].erreur) continue;
    try {
      await O.ouvrir(page, e.id, 'admin');
      out[e.id] = await page.evaluate(() => {
        const net = (x) => x.textContent.replace(/\s+/g, ' ').trim();
        const vis = (el) => { const r = el.getBoundingClientRect(); return r.width > 2 && r.height > 2; };
        const pc = document.getElementById('page-content') || document.body;
        const aide = [...pc.querySelectorAll('p')].filter(vis).map(net).filter((t) => t.length > 25).slice(0, 2);
        return { url: location.pathname, h1: [...pc.querySelectorAll('h1,h2')].filter(vis).map(net).slice(0, 5), aide,
          boutons: [...new Set([...pc.querySelectorAll('button, a.btn, [role=button]')].filter(vis).map(net).filter((t) => t && t.length < 60))].slice(0, 14),
          onglets: [...pc.querySelectorAll('[role=tab], [data-onglet], [data-tab]')].filter(vis).map(net).slice(0, 12),
          colonnes: [...pc.querySelectorAll('thead th')].filter(vis).map(net).filter(Boolean).slice(0, 12), refuse: /error-403|Accès refusé/.test(location.pathname + document.title) };
      });
    } catch (err) { out[e.id] = { erreur: String(err.message).slice(0, 160) }; }
    if (++n % 25 === 0) { fs.writeFileSync(sortie, JSON.stringify(out)); console.log(n, e.id); }
  }
  fs.writeFileSync(sortie, JSON.stringify(out));
  await browser.close();
  console.log('fini', Object.keys(out).length, 'erreurs', Object.values(out).filter((v) => v.erreur).length);
})();
