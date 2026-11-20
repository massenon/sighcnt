/* Exporte vers le jeu du poste les collections de M11 (paie) — SEULES, sans toucher aux autres fichiers du jeu.
   Ce que gen-jeu-collection.js ne sait pas faire : (1) poser l'horloge du 30/10/2026 10 h AVANT le chargement des modules (les amorçages
   par écran — avances, heures supplémentaires, évaluations — datent de l'horloge) ; (2) lancer le peuplement des parcours, d'où naissent
   prêts-études et participations. Vérifie au passage que `personnel` exporté est IDENTIQUE à celui du jeu (même graine, même base).
     node build/jeu-m11.js          (sous flock /tmp/sigh-banc.lock ; SIGH_PORT_PHP=<port inhabituel>) */
'use strict';
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette, ROOT } = require('./extraire');
const SORTIE = process.env.SIGH_JEU === 'sobre'
  ? path.resolve(__dirname, '..', '..', 'apps', 'poste', 'test', 'fixtures', 'jeu_sobre')
  : path.resolve(__dirname, '..', '..', 'apps', 'poste', 'assets', 'donnees', 'jeu');
const COLLECTIONS = ['planning', 'evaluations', 'grillePrimes', 'historiquePrimes', 'participations', 'pretsEtudes', 'avances', 'heuresSup', 'bulletins'];
(async () => {
  const m = await ouvrirMaquette();
  try {
    await m.page.evaluate(() => {
      const Reel = window.Date;
      const decalage = new Reel(2026, 9, 30, 10, 0, 0).getTime() - Reel.now();
      const maintenant = () => Reel.now() + decalage;
      function Decalee() {
        if (!(this instanceof Decalee)) return String(new Reel(maintenant()));
        if (arguments.length === 0) return new Reel(maintenant());
        return new (Function.prototype.bind.apply(Reel, [null].concat(Array.prototype.slice.call(arguments))))();
      }
      Decalee.prototype = Reel.prototype; Decalee.now = maintenant; Decalee.UTC = Reel.UTC; Decalee.parse = Reel.parse;
      window.Date = Decalee;
    });
    for (const f of ['m10-rh.js', 'm11-paie.js']) await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules', f) });
    if (process.env.SIGH_JEU !== 'sobre') await m.page.evaluate(() => { try { SIGH.peuplerParcours(); } catch (e) { console.error(e); } });
    await m.page.evaluate(() => {
      for (const id of ['m10-evaluations', 'm11-avances', 'm11-heures-sup', 'm10-planning']) {
        try { const r = document.createElement('div'); document.body.appendChild(r); SIGH.screens[id].render(r); r.remove(); } catch (e) { console.error(id, e); }
      }
    });
    const perso = await m.page.evaluate(() => JSON.parse(JSON.stringify(SIGH.store.collection('personnel').all().concat(SIGH.store.collection('personnel').archived()), (k, v) => (v === null ? undefined : v))));
    const existant = JSON.parse(fs.readFileSync(path.join(SORTIE, 'personnel.json'), 'utf8'));
    console.log('  personnel identique au jeu : ' + (JSON.stringify(perso) === JSON.stringify(existant)) + ' (' + perso.length + ' / ' + existant.length + ')');
    for (const nom of COLLECTIONS) {
      const lignes = await m.page.evaluate((n) => JSON.parse(JSON.stringify(SIGH.store.collection(n).all().concat(SIGH.store.collection(n).archived()), (k, v) => (v === null ? undefined : v))), nom);
      fs.writeFileSync(path.join(SORTIE, nom + '.json'), JSON.stringify(lignes));
      console.log(`  ${nom} : ${lignes.length} fiches`);
    }
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
