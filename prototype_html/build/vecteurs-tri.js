/* Vecteurs du TRI NATUREL : `C.sortBy` (localeCompare 'fr' numérique) rendu par la maquette pour des chaînes difficiles (codes patient, accents, ponctuation).
     node build/vecteurs-tri.js   →   packages/domaine/test/vecteurs/tri.json */
'use strict';
const { ouvrirMaquette, ecrire } = require('./extraire');
const ENTREES = [
  ['codes patient mêlant formats', ['CNT900/25', 'CNT/10/25', 'CNT/1/25', 'CNT/100/25', 'CNT/2/26', 'CNT/1/26', 'CNT/101/26']],
  ['nombres, lettres, accents', ['b2', 'a10', 'a2', 'é1', 'e2', 'A1', 'a1', '10', '9']],
  ['ponctuation avant chiffres avant lettres', ['x-1', 'x1', 'xa', 'x 1', 'x_1', 'x.1']],
  ['préfixes', ['FN-2026-00010', 'FN-2026-00009', 'FN-2026-00009-A', 'FN-2026-00009-B', 'FN-2026-9']],
];
(async () => {
  const m = await ouvrirMaquette();
  try {
    const cas = [];
    for (const [nom, liste] of ENTREES) {
      const triee = await m.page.evaluate((l) => SIGH.core.sortBy(l, (x) => x), liste);
      cas.push({ nom, entree: liste, sortie: triee });
      console.log('  ' + nom + ' → ' + triee.join(' | '));
    }
    ecrire('packages/domaine/test/vecteurs/tri.json', { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-tri.js — C.sortBy. Ne pas éditer.', cas });
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
