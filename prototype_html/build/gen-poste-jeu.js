/* JEU DE DÉMONSTRATION du poste Flutter : exporte de la maquette amorcée les collections dont les écrans PORTÉS ont besoin, telles que
   le magasin les tient (champs nuls omis, comme la persistance). Source de vérité = la maquette ; ne pas éditer à la main.
     node build/gen-poste-jeu.js → apps/poste/assets/donnees/jeu/<collection>.json */
'use strict';
const fs = require('fs'), path = require('path');
const { ouvrirMaquette } = require('./extraire');
const COLLECTIONS = ['factures', 'patients', 'avoirs', 'taches', 'demandesAnalyses', 'demandesImagerie', 'ordonnances', 'ecritures', 'audit'];
const SORTIE = path.resolve(__dirname, '..', '..', 'apps', 'poste', 'assets', 'donnees', 'jeu');
(async () => {
  fs.mkdirSync(SORTIE, { recursive: true });
  const m = await ouvrirMaquette();
  try {
    for (const nom of COLLECTIONS) {
      const lignes = await m.page.evaluate((n) => JSON.parse(JSON.stringify(SIGH.store.collection(n).all().concat(SIGH.store.collection(n).archived()), (k, v) => (v === null ? undefined : v))), nom);
      fs.writeFileSync(path.join(SORTIE, nom + '.json'), JSON.stringify(lignes));
      console.log(`  ${nom} : ${lignes.length} fiches, ${(fs.statSync(path.join(SORTIE, nom + '.json')).size / 1024).toFixed(0)} Ko`);
    }
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
