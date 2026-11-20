/* Récolte après un clic : libellés du formulaire ouvert (page ou fenêtre) et infobulles des actions de la première ligne.
   node recolte2.js <role> "<ecran>::<texte du bouton>" ... */
'use strict';
const O = require('./outils');
(async () => {
  const [role, ...paires] = process.argv.slice(2);
  const { browser, page } = await O.ouvrirNavigateur();
  const out = {};
  for (const p of paires) {
    const [ecran, clic] = p.split('::');
    try {
      await O.ouvrir(page, ecran, role);
      const lignes = await page.evaluate(() => {
        const tr = document.querySelector('#page-content table tbody tr');
        return tr ? [...tr.querySelectorAll('button[title], a[title], button[aria-label]')].map((b) => b.getAttribute('title') || b.getAttribute('aria-label')) : [];
      });
      let apres = null;
      if (clic) {
        const h = await O.trouver(page, 'texte:' + clic); const el = h && h.asElement();
        if (el) {
          await Promise.all([el.click(), new Promise((r) => setTimeout(r, 1800))]);
          await O.attendrePeinture(page); await new Promise((r) => setTimeout(r, 800));
          apres = await page.evaluate(() => {
            const net = (x) => x.textContent.replace(/\s+/g, ' ').trim();
            const vis = (el) => { const r = el.getBoundingClientRect(); return r.width > 2 && r.height > 2; };
            const dlg = [...document.querySelectorAll('[role=dialog], dialog[open], .modal')].filter(vis).pop();
            const z = dlg || document.getElementById('page-content') || document.body;
            return { url: location.pathname + location.search + location.hash, fenetre: !!dlg, titres: [...z.querySelectorAll('h1,h2,h3,legend')].filter(vis).map(net).slice(0, 12),
              champs: [...z.querySelectorAll('label')].filter(vis).map(net).filter(Boolean).slice(0, 45),
              boutons: [...new Set([...z.querySelectorAll('button')].filter(vis).map(net).filter(Boolean))].slice(0, 30) };
          });
        } else apres = 'BOUTON INTROUVABLE';
      }
      out[p] = { actionsLigne: [...new Set(lignes)], apres };
    } catch (err) { out[p] = { erreur: String(err.message).slice(0, 200) }; }
  }
  await browser.close();
  console.log(JSON.stringify(out, null, 1));
})();
