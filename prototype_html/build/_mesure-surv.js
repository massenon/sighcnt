'use strict';
const { ouvrirMaquette } = require('./extraire');
(async () => {
  const m = await ouvrirMaquette();
  try {
    const r = await m.page.evaluate(() => {
      const N = SIGH.nav, S = SIGH.store, R = SIGH.planningRh;
      try { S.collection('rbac').all(); } catch (e) {}
      N.invaliderRbac(); N.invaliderModules(); N.appliquerRenommages();
      const sess0 = S.session();
      const out = [];
      ['surveillant', 'admin', 'da', 'rh', 'infirmier'].forEach((role) => {
        const ligne = { role };
        ['m10-employe-profil', 'm10-personnel', 'm10-planning', 'm10-fiche-equipe'].forEach((e) => { const x = N.get(e); ligne[e] = x ? !!N.can(role, x) : 'absent'; });
        ['regler_planning_personnalise', 'regler_regime_individuel', 'confirmer_valeur_attente_personnel', 'ouvrir_fiche_personnel_equipe'].forEach((g) => { ligne[g] = N.geste(g) ? !!N.droitGeste(role, g) : 'absent'; });
        out.push(ligne);
      });
      const pers = S.collection('personnel').active();
      const surv = pers.filter((e) => e.fonction === 'surveillant' || /surveill/i.test(e.poste || ''));
      return { out, nbPersonnel: pers.length, services: Array.from(new Set(pers.map((e) => e.service))), surveillants: surv.map((e) => ({ id: e.id, nom: e.nomComplet, service: e.service, fonction: e.fonction, poste: e.poste })), fonctions: Array.from(new Set(pers.map((e) => e.fonction))) };
    });
    console.log(JSON.stringify(r, null, 1));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
