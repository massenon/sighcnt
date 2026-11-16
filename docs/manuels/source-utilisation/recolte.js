/* Récolte des libellés réels d'écrans (titres, boutons, onglets) pour rédiger le manuel sans deviner.
   node recolte.js <role> <ecran> [<ecran>...] ; sortie JSON sur stdout. */
'use strict';
const O = require('./outils');
(async () => {
  const [role, ...ecrans] = process.argv.slice(2);
  const { browser, page } = await O.ouvrirNavigateur();
  const out = {};
  for (const e of ecrans) {
    try {
      await O.ouvrir(page, e, role);
      out[e] = await page.evaluate(() => {
        const net = (x) => x.textContent.replace(/\s+/g, ' ').trim();
        const vis = (el) => { const r = el.getBoundingClientRect(); return r.width > 2 && r.height > 2; };
        const pc = document.getElementById('page-content') || document.body;
        return { url: location.pathname, h1: [...pc.querySelectorAll('h1,h2')].filter(vis).map(net).slice(0, 6),
          boutons: [...new Set([...pc.querySelectorAll('button, a.btn, [role=button]')].filter(vis).map(net).filter(Boolean))].slice(0, 40),
          onglets: [...pc.querySelectorAll('[role=tab], [data-onglet], [data-tab]')].filter(vis).map(net).slice(0, 20),
          champs: [...pc.querySelectorAll('label')].filter(vis).map(net).filter(Boolean).slice(0, 30),
          colonnes: [...pc.querySelectorAll('thead th')].filter(vis).map(net).filter(Boolean).slice(0, 20) };
      });
    } catch (err) { out[e] = { erreur: String(err.message).slice(0, 200) }; }
  }
  await browser.close();
  console.log(JSON.stringify(out, null, 1));
})();
