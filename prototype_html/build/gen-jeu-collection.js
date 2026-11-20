/* Exporte UNIQUEMENT les collections nommées vers le jeu du poste, sans toucher aux autres fichiers (le jeu complet n'est pas déterministe :
   le régénérer change les tirages aléatoires sur lesquels les vecteurs existants ont été tirés).
   Usage : node build/gen-jeu-collection.js [--ecran=<id>[,<id>]] [--module=<fichier.js>[,…]] <collection> [<collection>…]
   --module charge assets/js/modules/<fichier>, --ecran monte l'écran (qui amorce sa collection comme dans la maquette). SIGH_JEU=sobre → fixture de test.
   --peupler lance le peuplement des parcours (SIGH.peuplerParcours), d'où naissent les collections de M10 (participations, prêts) : à passer avec --module=m10-rh.js. */
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette, ROOT } = require('./extraire');
const args = process.argv.slice(2);
const opt = (n) => (args.find((a) => a.startsWith('--' + n + '=')) || '').split('=')[1];
const noms = args.filter((a) => !a.startsWith('--'));
const ecrans = (opt('ecran') || '').split(',').filter(Boolean);
const modules = (opt('module') || '').split(',').filter(Boolean);
const peupler = args.includes('--peupler');
const SORTIE = process.env.SIGH_JEU === 'sobre'
  ? path.resolve(__dirname, '..', '..', 'apps', 'poste', 'test', 'fixtures', 'jeu_sobre')
  : path.resolve(__dirname, '..', '..', 'apps', 'poste', 'assets', 'donnees', 'jeu');
(async () => {
  if (!noms.length) { console.error('Aucune collection nommée.'); process.exit(2); }
  const m = await ouvrirMaquette();
  try {
    for (const f of modules) await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules', f) });
    if (peupler) await m.page.evaluate(() => { try { SIGH.peuplerParcours(); } catch (e) { console.error(e); } });
    for (const id of ecrans) {
      await m.page.evaluate((i) => { try { const r = document.createElement('div'); document.body.appendChild(r); SIGH.screens[i].render(r); r.remove(); } catch (e) { console.error(i, e); } }, id);
    }
    for (const nom of noms) {
      const lignes = await m.page.evaluate((n) => JSON.parse(JSON.stringify(SIGH.store.collection(n).all().concat(SIGH.store.collection(n).archived()), (k, v) => (v === null ? undefined : v))), nom);
      fs.writeFileSync(path.join(SORTIE, nom + '.json'), JSON.stringify(lignes));
      console.log(`  ${nom} : ${lignes.length} fiches`);
    }
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
