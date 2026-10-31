/* =============================================================================
 * EXTRACTION DU CONTENU ET DE LA STRUCTURE DE CHAQUE ÉCRAN (parité N1 / N2)
 * -----------------------------------------------------------------------------
 * Ouvre chaque page de la maquette sous un profil qui la voit, attend sa peinture, et relève ce que l'écran DIT
 * (titre, description, devise, fil d'Ariane, règle, onglets, libellés de KPI, titres de cartes, en-têtes de colonnes,
 * libellés de commandes et de champs) — jamais les VALEURS des données, qui dépendent du jeu. L'application Flutter est
 * mesurée contre ces fichiers : même contenu (N1), même structure (N2).
 *
 *   node build/extraire-ecrans.js [--pages=m8-,m14-]   →   docs/architecture/ecrans/<id>.json  +  ecrans.index.json
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette, REPO } = require('./extraire');
const BANC = require('./_banc');

const filtre = (process.argv.find((a) => a.startsWith('--pages=')) || '').replace('--pages=', '').split(',').filter(Boolean);
const SORTIE = path.join(REPO, 'docs', 'architecture', 'ecrans');

(async () => {
  console.log('▶ Extraction du contenu et de la structure des écrans');
  const m = await ouvrirMaquette();
  const manifeste = JSON.parse(fs.readFileSync(path.join(REPO, 'packages/referentiels/data/manifeste.json'), 'utf8'));
  fs.mkdirSync(SORTIE, { recursive: true });
  const ecrans = manifeste.ecrans.filter((e) => !e.standalone || /^(hub|m|rls|mere|cfg|dash|adm|auth|error|enquete|support|aide)/.test(e.id)).filter((e) => !filtre.length || filtre.some((f) => e.id.startsWith(f)));
  const page = m.page;
  await page.setViewportSize({ width: 1440, height: 900 });
  const index = [];
  let n = 0;
  for (const e of ecrans) {
    n++;
    const url = `http://127.0.0.1:${BANC.PORT_PHP}/pages/${e.id}.php`;
    let res;
    try {
      await page.goto(url, { waitUntil: 'domcontentloaded' });
      await page.waitForSelector('#page-content', { timeout: 12000 });
      await page.waitForTimeout(700);
      res = await page.evaluate(() => {
        const txt = (el) => (el ? el.textContent.replace(/\s+/g, ' ').trim() : '');
        const visibles = (sel, racine) => Array.from((racine || document).querySelectorAll(sel)).filter((x) => x.offsetParent !== null);
        const contenu = document.querySelector('#page-content');
        if (!contenu) return { acces: 'absent' };
        const entete = document.querySelector('main h1') || document.querySelector('h1');
        const bloc = entete ? entete.closest('div') : null;
        return {
          acces: /403|Accès refusé|accès non autoris/i.test(document.title + ' ' + txt(entete)) ? 'refuse' : 'ouvert',
          titre: entete && entete.childNodes[0] ? entete.childNodes[0].textContent.replace(/\s+/g, ' ').trim() : txt(entete),
          module: txt(entete && entete.querySelector('.badge')),
          description: txt(entete && entete.parentElement && entete.parentElement.querySelector('p')),
          fil: visibles('nav[aria-label*="Ariane"] a, nav[aria-label*="Ariane"] span').map(txt).filter(Boolean),
          actions: visibles('#page-actions a, #page-actions button').map(txt).filter(Boolean),
          regle: visibles('#page-content .rounded-lg.border').map(txt).filter((t) => t.length > 20).slice(0, 3),
          onglets: visibles('#page-content .tab').map(txt).map((t) => t.replace(/\s*\d+$/, '')),
          kpis: visibles('#page-content .kpi-label').map(txt),
          cartes: visibles('#page-content .card-title, #page-content h2, #page-content h3').map(txt).filter(Boolean),
          tableaux: visibles('#page-content table').map((t) => Array.from(t.querySelectorAll('thead th')).map(txt).filter(Boolean)),
          commandes: Array.from(new Set(visibles('#page-content button, #page-content a.btn').map(txt).filter((t) => t && t.length < 60))),
          champs: visibles('#page-content label').map(txt).filter(Boolean),
          nbTableaux: document.querySelectorAll('#page-content table').length,
          nbKpis: document.querySelectorAll('#page-content .kpi').length,
        };
      });
    } catch (err) { res = { acces: 'erreur', erreur: String(err.message || err).slice(0, 120) }; }
    const fiche = { id: e.id, module: e.module, domaine: e.domaine, libelleManifeste: e.label, ...res };
    fs.writeFileSync(path.join(SORTIE, e.id + '.json'), JSON.stringify(fiche, null, 1) + '\n');
    index.push({ id: e.id, acces: res.acces, titre: res.titre || null, kpis: (res.kpis || []).length, tableaux: (res.tableaux || []).length, onglets: (res.onglets || []).length, commandes: (res.commandes || []).length });
    if (n % 25 === 0) console.log(`  ${n}/${ecrans.length}`);
  }
  if (!filtre.length) fs.writeFileSync(path.join(SORTIE, 'ecrans.index.json'), JSON.stringify({ _doc: 'ENGENDRÉ par prototype_html/build/extraire-ecrans.js — ne pas éditer.', ecrans: index }, null, 1) + '\n');
  const par = index.reduce((a, x) => (a[x.acces] = (a[x.acces] || 0) + 1, a), {});
  console.log('  ' + ecrans.length + ' écrans · ' + JSON.stringify(par));
  await m.fermer();
})().catch((e) => { console.error(e); process.exit(1); });
