/* Vecteurs du RUBAN : ce que `N.tree(rôle)` rend — la fonction même qu'appelle le ruban de la maquette — pour CHAQUE rôle.
   Le portage Dart (packages/domaine/lib/src/navigation) doit rendre exactement les mêmes domaines, rangées et écrans.
     node build/vecteurs-ruban.js   →   packages/domaine/test/vecteurs/ruban.json */
'use strict';
const { ouvrirMaquette, ecrire } = require('./extraire');
(async () => {
  console.log('▶ Vecteurs du ruban');
  const m = await ouvrirMaquette();
  try {
    const cas = await m.page.evaluate(() => {
      const N = SIGH.nav; N.invaliderRbac(); N.invaliderModules(); N.appliquerRenommages();
      return Object.keys(N.ROLES).map((role) => ({
        role, archive: !!N.roleArchive(role),
        domaines: N.tree(role).map((d) => ({ domaine: d.domain, rangees: d.modules.map((mo) => ({ code: mo.code, label: mo.label, hub: mo.hub || null, ecrans: mo.items.map((i) => i.id) })) })),
      }));
    });
    ecrire('packages/domaine/test/vecteurs/ruban.json', { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-ruban.js — N.tree(rôle) de la maquette. Ne pas éditer.', cas });
    console.log(`  ${cas.length} rôles · ${cas.reduce((a, c) => a + c.domaines.reduce((b, d) => b + d.rangees.reduce((x, r) => x + r.ecrans.length, 0), 0), 0)} entrées de ruban`);
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
