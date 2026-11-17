/* Sème le jeu de DÉMONSTRATION complet dans la base jetable du manuel (la remise à neuf du banc la laisse vide). node semer.js */
'use strict';
const O = require('./outils');
(async () => {
  const { browser, page } = await O.ouvrirNavigateur();
  await O.ouvrir(page, 'm10-planning', 'admin');
  await page.evaluate(() => { window.SIGH.store.reset(); });
  await new Promise((r) => setTimeout(r, 4000));
  await page.evaluate(() => window.SIGH.store.pousserMaintenant && window.SIGH.store.pousserMaintenant());
  await new Promise((r) => setTimeout(r, 15000));
  const n = await page.evaluate(() => ['patients', 'personnel', 'produits', 'lits'].map((c) => c + '=' + window.SIGH.store.collection(c).all().length).join(' '));
  console.log(n);
  await browser.close();
})();
