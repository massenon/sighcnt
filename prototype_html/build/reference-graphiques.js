/* Captures de référence des GRAPHIQUES de la maquette (Chart.js) : barres, ligne, anneau, sparkline, à largeur et données fixes.
     node build/reference-graphiques.js → apps/poste/test/references/kit/graphique-*.png + graphiques.json */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire } = require('./extraire');
const SORTIE = path.resolve(__dirname, '..', '..', 'apps', 'poste', 'test', 'references', 'kit');
const CAS = {
  barres: () => SIGH.charts.barres(['Mai', 'Juin', 'Juil.', 'Août'], [{ label: 'Recettes', data: [120, 180, 90, 210] }, { label: 'Dépenses', data: [80, 100, 70, 150], color: '#f98307' }], { height: 260 }),
  ligne: () => SIGH.charts.ligne(['Mai', 'Juin', 'Juil.', 'Août', 'Sept.'], [{ label: 'Admissions', data: [12, 30, 22, 40, 35] }], { height: 260 }),
  anneau: () => SIGH.charts.anneau(['Consultation', 'Laboratoire', 'Pharmacie'], [50, 30, 20], { height: 260 }),
  sparkline: () => SIGH.charts.sparkline([3, 5, 4, 8, 6, 9], undefined),
};
(async () => {
  const m = await ouvrirMaquette();
  try {
    const meta = {};
    for (const [id, fab] of Object.entries(CAS)) {
      await m.page.evaluate(({ f }) => { document.body.innerHTML = '<div id="c" style="width:600px;padding:0;background:#fff"></div>'; document.getElementById('c').appendChild(new Function('return (' + f + ')()')()); Chart.defaults.animation = false; }, { f: fab.toString() });
      await new Promise((r) => setTimeout(r, 1800));
      const info = await m.page.evaluate(() => { const c = Chart.getChart(document.querySelector('#c canvas')); const a = c.chartArea; return { zone: { x: +a.left.toFixed(1), y: +a.top.toFixed(1), l: +a.width.toFixed(1), h: +a.height.toFixed(1) }, taille: [c.width, c.height] }; });
      meta[id] = info;
      await (await m.page.$('#c')).screenshot({ path: path.join(SORTIE, 'graphique-' + id + '.png') });
    }
    ecrire('apps/poste/test/references/kit/graphiques.json', { _doc: 'ENGENDRÉ par prototype_html/build/reference-graphiques.js. Ne pas éditer.', ...meta });
    console.log(JSON.stringify(meta));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
