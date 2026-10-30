/* Vecteurs des GRAPHIQUES : l'échelle verticale (graduations) que Chart.js calcule pour des séries données, relevée sur les VRAIS
   graphiques de la maquette (`SIGH.charts.barres` / `ligne`). Le portage Dart (packages/domaine/lib/src/graphiques) doit produire les mêmes
   graduations à partir de la même hauteur d'axe.
     node build/vecteurs-graphiques.js   →   packages/domaine/test/vecteurs/echelle.json */
'use strict';
const { ouvrirMaquette, ecrire } = require('./extraire');
const SERIES = [
  [[0, 0, 0]], [[1, 2, 3]], [[5, 12, 7, 20]], [[100, 250, 175]], [[1250000, 980000, 1500000]], [[0.2, 0.5, 0.35]], [[3, 3, 3]], [[7]],
  [[12, 48, 33, 91, 60, 77]], [[1000, 2000], [1500, 500]], [[4200, 300, 150]], [[999, 1001]], [[17, 2, 0, 9]], [[1, 1000000]],
];
const HAUTEURS = [180, 260, 320];
(async () => {
  console.log('▶ Vecteurs des graphiques (échelle Chart.js)');
  const m = await ouvrirMaquette();
  try {
    const cas = [];
    for (const h of HAUTEURS) for (const series of SERIES) {
      const r = await m.page.evaluate(async ({ series, h }) => {
        const labels = series[0].map((_, i) => 'L' + i);
        const n = SIGH.charts.barres(labels, series.map((d, i) => ({ label: 'S' + i, data: d })), { height: h });
        n.style.width = '600px'; document.body.appendChild(n);
        await new Promise((r) => setTimeout(r, 120));
        const c = Chart.getChart(n.querySelector('canvas'));
        const y = c.scales.y;
        const sortie = { graduations: y.ticks.map((t) => t.value), min: y.min, max: y.max, hauteurAxe: +y.height.toFixed(2), hauteurTrace: +c.chartArea.height.toFixed(2) };
        c.destroy(); n.remove();
        return sortie;
      }, { series, h });
      cas.push({ series, hauteur: h, ...r });
    }
    ecrire('packages/domaine/test/vecteurs/echelle.json', { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-graphiques.js — échelle verticale Chart.js (barres, beginAtZero). Ne pas éditer.', cas });
    console.log('  ' + cas.length + ' échelles ; exemple : ' + JSON.stringify(cas[9]));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
