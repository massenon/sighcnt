/* Compare deux captures de build/capture-prix.js, voie par voie et code par code. Sort en erreur au premier écart (il les liste tous).
   node build/tarifs/comparer-prix.js avant.json apres.json */
'use strict';
const fs = require('fs');
const [a, b] = process.argv.slice(2).map((f) => JSON.parse(fs.readFileSync(f, 'utf8')));
let ecarts = 0, compares = 0;
const sortir = (chemin, x, y) => { ecarts++; if (ecarts <= 40) console.log('ECART ' + chemin + '\n   avant : ' + JSON.stringify(x) + '\n   après : ' + JSON.stringify(y)); };
function cmp(chemin, x, y) {
  if (x !== null && y !== null && typeof x === 'object' && typeof y === 'object') {
    const ks = Array.from(new Set(Object.keys(x).concat(Object.keys(y)))).sort();
    ks.forEach((k) => cmp(chemin + '/' + k, x[k], y[k]));
    return;
  }
  compares++;
  if (JSON.stringify(x) !== JSON.stringify(y)) sortir(chemin, x, y);
}
['patients', 'espaces', 'codes', 'voies', 'collections'].forEach((k) => cmp(k, a[k], b[k]));
console.log('Comparaisons : ' + compares + ' valeurs, ' + ecarts + ' écart(s).');
process.exit(ecarts ? 1 : 0);
