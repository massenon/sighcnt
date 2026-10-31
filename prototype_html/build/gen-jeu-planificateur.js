/* Exporte le REGISTRE DU PLANIFICATEUR (api/cron.php) vers le jeu du poste : `tachesPlanifiees` et `executionsTaches`.
   Ces deux registres ne sont pas des collections du magasin de la maquette — ils vivent dans PostgreSQL (taches_planifiees, executions_taches) et
   l'écran m14-taches les lit par `api/notifications.php?action=taches`. On les lit donc par le MÊME appel, sous le rôle admin du banc.
   Usage : node build/gen-jeu-planificateur.js   (SIGH_JEU=sobre → fixture de test). C'est un INSTANTANÉ du registre : le poste n'a pas de planificateur. */
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette } = require('./extraire');
const SORTIE = process.env.SIGH_JEU === 'sobre'
  ? path.resolve(__dirname, '..', '..', 'apps', 'poste', 'test', 'fixtures', 'jeu_sobre')
  : path.resolve(__dirname, '..', '..', 'apps', 'poste', 'assets', 'donnees', 'jeu');
(async () => {
  const m = await ouvrirMaquette();
  try {
    const o = await m.page.evaluate(async () => {
      const r = await fetch('api/notifications.php?action=taches', { headers: { 'X-Sigh-Jeton': SIGH.store.jetonServeur() || '' } });
      return { statut: r.status, corps: await r.json() };
    });
    if (o.statut !== 200) throw new Error('registre inaccessible : ' + JSON.stringify(o));
    const taches = o.corps.taches.map((t) => ({ id: t.code, ...t }));
    const executions = o.corps.executions.map((e) => ({ id: 'EXT' + e.id, ...e }));
    fs.writeFileSync(path.join(SORTIE, 'tachesPlanifiees.json'), JSON.stringify(taches));
    fs.writeFileSync(path.join(SORTIE, 'executionsTaches.json'), JSON.stringify(executions));
    console.log(`  tachesPlanifiees : ${taches.length} · executionsTaches : ${executions.length}`);
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
