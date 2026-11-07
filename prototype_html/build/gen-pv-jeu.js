/* JEU DES PV DE RÉCEPTION du poste Flutter : le registre `pvReceptions` est amorcé PAR SES ÉCRANS dans la maquette (`amorcerPV`, local à
   m7-achats.js), jamais par `semerAchats` — d'où le `[]` que `gen-poste-jeu.js` exporte. Ce script monte l'écran comme le ferait l'agent
   (ce qui déclenche l'amorçage, sur les livraisons du jeu) et exporte le registre, champs nuls omis comme la persistance.
     node build/gen-pv-jeu.js → apps/poste/assets/donnees/jeu/pvReceptions.json
   À terme : le même appel (charger m7-achats.js puis monter un écran PV) doit entrer dans `gen-poste-jeu.js`, qui écraserait sinon ce fichier. */
'use strict';
const fs = require('fs'), path = require('path');
const { ouvrirMaquette, ROOT } = require('./extraire');
const SORTIE = path.resolve(__dirname, '..', '..', 'apps', 'poste', 'assets', 'donnees', 'jeu');
(async () => {
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m7-achats.js') });
    const lignes = await m.page.evaluate(() => {
      SIGH.semerAchats(true);
      const root = document.createElement('div'); document.body.appendChild(root);
      SIGH.screens['m7-pv-reception-consommables'].render(root);
      return JSON.parse(JSON.stringify(SIGH.store.collection('pvReceptions').all(), (k, v) => (v === null ? undefined : v)));
    });
    fs.writeFileSync(path.join(SORTIE, 'pvReceptions.json'), JSON.stringify(lignes));
    console.log(`  pvReceptions : ${lignes.length} fiches (${lignes.filter((x) => x.nature === 'consommables').length} consommables, ${lignes.filter((x) => x.nature === 'reactifs').length} réactifs)`);
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
