/* =============================================================================
 * VECTEURS DE LA FICHE DE L'ÉQUIPE (lot SURV, 16/11/2026) : SIGH.planningRh (porteePersonnel, ficheEquipe, equipeDeLaSession, controlerPerimetreEquipe), PILOTÉ dans Chrome
 * -----------------------------------------------------------------------------
 * Chaque cas se connecte sous un rôle et un nom (le Surveillant GARBA Yahouza du jeu, l'administrateur, un rôle sans le geste, un compte qui n'est pas un agent), appelle le moteur
 * de la maquette et enregistre ce qu'il rend avec ses ENTRÉES : la portée (lecture complète, geste), l'agent de la session, la fiche lue, le refus nommé (code, motif, geste).
 * Le domaine Dart (`packages/domaine/lib/src/rh/fiche_equipe.dart`) rejoue chaque cas sur les MÊMES entrées.
 *   node build/vecteurs-fiche-equipe.js   →   packages/domaine/test/vecteurs/fiche_equipe.json
 * ========================================================================== */
'use strict';
const { ouvrirMaquette, ecrire } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs de la fiche de l’équipe (lot SURV)');
  const m = await ouvrirMaquette();
  try {
    const sortie = await m.page.evaluate(() => {
      const S = window.SIGH.store, R = window.SIGH.planningRh, N = window.SIGH.nav;
      try { S.collection('rbac').all(); } catch (e) { /* amorçage */ }
      N.invaliderRbac(); N.invaliderModules(); N.appliquerRenommages();
      const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
      const sess0 = S.session();
      const seConnecter = (role, nom) => S.setSession(Object.assign({}, sess0, { role: role, nom: nom, nomComplet: nom }));
      const personnel = S.collection('personnel').active();
      const moiAgent = personnel.filter((e) => e.nomComplet === 'GARBA Yahouza')[0];
      const equipe = personnel.filter((e) => e.service === moiAgent.service && e.id !== moiAgent.id);
      const hors = personnel.filter((e) => e.service !== moiAgent.service);
      const A = equipe[0], H = hors[0];
      const entrees = (role, nom) => {
        seConnecter(role, nom);
        return { role: role, nomSession: nom, lectureComplete: !!N.can(role, N.get('m10-personnel')), geste: !!N.droitGeste(role, R.GESTE_FICHE_EQUIPE), portee: R.porteePersonnel(),
          moi: propre(personnel.filter((e) => e.nomComplet === nom)[0] || null) };
      };
      const refus = (r) => (r.ok ? null : { code: r.code, motif: r.motif, geste: r.geste });
      const cas = [];
      const sessions = [['surveillant', 'GARBA Yahouza'], ['admin', 'ADMIN VECTEUR'], ['infirmier', 'ANONYME VECTEUR'], ['surveillant', 'COMPTE SANS AGENT']];
      sessions.forEach((s) => {
        const e = entrees(s[0], s[1]);
        [['agent de l’équipe', A], ['agent d’un autre service', H], ['le Surveillant lui-même', moiAgent], ['agent introuvable', { id: 'EMP-INCONNU', nomComplet: 'Inconnu' }]].forEach((c) => {
          const agent = c[1];
          const r = c[0] === 'agent introuvable' ? R.ficheEquipe('EMP-INCONNU') : R.ficheEquipe(agent.id);
          cas.push(Object.assign({ nom: s[0] + ' / ' + s[1] + ' : ' + c[0] }, e, { agent: c[0] === 'agent introuvable' ? null : propre(S.collection('personnel').get(agent.id)), idDemande: agent.id, attendu: { ok: !!r.ok, refus: refus(r), fiche: r.ok ? propre(r.fiche) : null, porteeRendue: r.ok ? r.portee : null } }));
        });
      });
      const equipes = sessions.map((s) => {
        const e = entrees(s[0], s[1]);
        const r = R.equipeDeLaSession();
        return Object.assign({ nom: s[0] + ' / ' + s[1] + ' : équipe' }, e, { attendu: { ok: !!r.ok, refus: refus(r), agents: r.ok ? propre(r.agents) : null, portee: r.ok ? r.portee : null } });
      });
      /* le périmètre seul : le contrôle rend null (permis) ou le refus */
      const perimetres = [];
      sessions.forEach((s) => {
        const e = entrees(s[0], s[1]);
        [A, H, moiAgent].forEach((agent) => { const r = R.controlerPerimetreEquipe(agent); perimetres.push(Object.assign({ nom: s[0] + ' / ' + s[1] + ' : périmètre de ' + agent.nomComplet }, e, { agent: propre(agent), attendu: r ? { code: r.code, motif: r.motif, geste: r.geste } : null })); });
      });
      seConnecter(sess0.role, sess0.nom);
      return { personnelActif: propre(personnel), cas, equipes, perimetres, defauts: { detenteurs: N.rolesAvecGeste(R.GESTE_FICHE_EQUIPE).slice().sort(), champsBlancs: R.CHAMPS_FICHE_EQUIPE.slice() } };
    });
    ecrire('packages/domaine/test/vecteurs/fiche_equipe.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-fiche-equipe.js : fiche de l’équipe et périmètre d’équipe (lot SURV), tirés du moteur de la maquette piloté dans Chrome. Ne pas éditer.' }, sortie));
    console.log('  ' + sortie.cas.length + ' cas de fiche · ' + sortie.equipes.length + ' équipes · ' + sortie.perimetres.length + ' périmètres');
    if (m.erreurs.length) console.log('  avertissements : ' + m.erreurs.slice(0, 3).join(' | '));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
