/* Compare deux captures de build/capture-prix-produits.js, référence par référence. Sort en erreur au premier écart inattendu (il les liste tous).
   Un écart ATTENDU est déclaré dans un fichier JSON facultatif (3e argument) : { "chemin/exact": "raison" }.
   node build/tarifs/comparer-prix-produits.js avant.json apres.json [attendus.json] */
'use strict';
const fs = require('fs');
const [a, b] = process.argv.slice(2, 4).map((f) => JSON.parse(fs.readFileSync(f, 'utf8')));
const ATT = process.argv[4] ? JSON.parse(fs.readFileSync(process.argv[4], 'utf8')) : {};
let ecarts = 0, compares = 0, attendus = 0;
const sortir = (chemin, x, y) => { ecarts++; if (ecarts <= 40) console.log('ECART ' + chemin + '\n   avant : ' + JSON.stringify(x) + '\n   après : ' + JSON.stringify(y)); };
function cmp(chemin, x, y) {
  if (x !== null && y !== null && typeof x === 'object' && typeof y === 'object') {
    const ks = Array.from(new Set(Object.keys(x).concat(Object.keys(y)))).sort();
    ks.forEach((k) => cmp(chemin + '/' + k, x[k], y[k]));
    return;
  }
  compares++;
  if (JSON.stringify(x) !== JSON.stringify(y)) {
    if (ATT[chemin]) { attendus++; console.log('ATTENDU ' + chemin + ' : ' + ATT[chemin]); return; }
    sortir(chemin, x, y);
  }
}
['patients', 'produits', 'totaux', 'fiches', 'valeurs', 'sorties', 'prescrire', 'caisseManuelle'].forEach((k) => cmp(k, a[k], b[k]));
console.log('Comparaisons : ' + compares + ' valeurs ; ' + ecarts + ' écart(s) INATTENDU(S) ; ' + attendus + ' écart(s) attendu(s).');
process.exit(ecarts ? 1 : 0);
