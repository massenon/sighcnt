/* Extrait de nav.js (la source) les rubriques de la recherche globale et les actions rapides de la barre supérieure :
     packages/referentiels/data/rubriques.json  +  apps/poste/assets/donnees/rubriques.json
   ENGENDRÉ : ne pas éditer à la main.   node build/extraire-rubriques.js */
'use strict';
const vm = require('vm'), fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..'), REPO = path.resolve(ROOT, '..');
const w = {}; w.window = w; w.SIGH = {};
vm.runInNewContext(fs.readFileSync(path.join(ROOT, 'assets/js/nav.js'), 'utf8'), w);
const N = w.SIGH.nav;
const sortie = {
  _doc: 'ENGENDRÉ par prototype_html/build/extraire-rubriques.js depuis nav.js (RUBRIQUES, ACTIONS_RAPIDES), ne pas éditer.',
  rubriques: N.RUBRIQUES.map((r) => ({ ecran: r.ecran, onglet: r.onglet || null, label: r.label, motsCles: r.motsCles || '' })),
  actionsRapides: N.ACTIONS_RAPIDES.map((a) => ({ libelle: a[0], icone: a[1], ecran: a[2] })),
};
const txt = JSON.stringify(sortie, null, 1) + '\n';
for (const rel of ['packages/referentiels/data/rubriques.json', 'apps/poste/assets/donnees/rubriques.json']) {
  fs.mkdirSync(path.dirname(path.join(REPO, rel)), { recursive: true });
  fs.writeFileSync(path.join(REPO, rel), txt);
  console.log('  écrit : ' + rel);
}
console.log(`  ${sortie.rubriques.length} rubriques · ${sortie.actionsRapides.length} actions rapides`);
