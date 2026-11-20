/* Compare deux captures de build/capture-prix.js, voie par voie et code par code. Sort en erreur au premier écart (il les liste tous).
   node build/tarifs/comparer-prix.js avant.json apres.json */
'use strict';
const fs = require('fs');
const [a, b] = process.argv.slice(2).map((f) => JSON.parse(fs.readFileSync(f, 'utf8')));
let ecarts = 0, compares = 0, attendus = 0;
const ATTENDUS = new Set(b.attendus || []);
const VOIES_GRILLE = ['accesseur.tarif', 'accesseur.tarifPrix', 'soins', 'imagerie'];
const sortir = (chemin, x, y) => { ecarts++; if (ecarts <= 40) console.log('ECART ' + chemin + '\n   avant : ' + JSON.stringify(x) + '\n   après : ' + JSON.stringify(y)); };
function cmp(chemin, x, y) {
  if (x !== null && y !== null && typeof x === 'object' && typeof y === 'object') {
    const ks = Array.from(new Set(Object.keys(x).concat(Object.keys(y)))).sort();
    ks.forEach((k) => cmp(chemin + '/' + k, x[k], y[k]));
    return;
  }
  compares++;
  if (JSON.stringify(x) !== JSON.stringify(y)) {
    /* Le catalogue tarifaire (collection de lecture) porte, pour une ligne LABO fusionnée, le prix FACTURÉ : même écart attendu. */
    if (chemin.indexOf('collections/catalogueTarifs/') === 0 && Array.isArray(a.collections.catalogueTarifs[Number(chemin.split('/')[2])]) && ATTENDUS.has(a.collections.catalogueTarifs[Number(chemin.split('/')[2])][1])) { attendus++; return; }
    const m = chemin.split('/');
    if (m[0] === 'voies' && VOIES_GRILLE.indexOf(m[1]) >= 0 && ATTENDUS.has(m[2])) { attendus++; return; }
    sortir(chemin, x, y);
  }
}
['patients', 'espaces', 'codes', 'voies', 'collections'].forEach((k) => cmp(k, a[k], b[k]));
console.log('Comparaisons : ' + compares + ' valeurs ; ' + ecarts + ' écart(s) INATTENDU(S) ; ' + attendus + ' écart(s) attendu(s) (' + ATTENDUS.size + ' lignes LABO de la grille fusionnées avec leur analyse, version 2 proposée).');
process.exit(ecarts ? 1 : 0);
