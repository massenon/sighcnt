/* Dérive du jeu du poste les deux RÉFÉRENCES que l'écran m14-roles lit : `rolesBase` (une fiche par rôle : libellés d'origine, droits par module et par
   écran TELS QUE `packages/rbac/data/rbac.json` les donne au moteur de droits du poste) et `modulesManifeste` (une fiche par rangée du manifeste, avec
   ses écrans). Ce ne sont PAS des collections de la maquette : le poste n'a pas d'accès synchrone aux assets de navigation (`DonneesNavigation` n'est
   pas dans `ContexteEcran`), on les sert donc par le magasin, comme le jeu. Elles sont en LECTURE : l'écran ne les écrit jamais — ses décisions vont
   dans la collection `rbac`, calquée sur celle de la maquette.
   Pour les rôles ARCHIVÉS à la source, la matrice extraite est toute fermée (un rôle archivé n'ouvre rien) : on lit donc aussi leurs droits
   D'ORIGINE (`modulesOrigine`), pour qu'une restauration rende ce que la maquette rend.
   Usage : node build/gen-jeu-securite.js   (écrit jeu/ ET test/fixtures/jeu_sobre/). Prérequis : packages/rbac/data/rbac.json à jour (build/extraire.js rbac). */
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette } = require('./extraire');
const REPO = path.resolve(__dirname, '..', '..');
const SORTIES = [path.join(REPO, 'apps/poste/assets/donnees/jeu'), path.join(REPO, 'apps/poste/test/fixtures/jeu_sobre')];
(async () => {
  const rbac = JSON.parse(fs.readFileSync(path.join(REPO, 'packages/rbac/data/rbac.json'), 'utf8'));
  const man = JSON.parse(fs.readFileSync(path.join(REPO, 'packages/referentiels/data/manifeste.json'), 'utf8'));
  const m = await ouvrirMaquette();
  let origine;
  try {
    origine = await m.page.evaluate(() => {
      const N = SIGH.nav, S = SIGH.store;
      const codes = []; N.NAV.forEach((d) => d.modules.forEach((x) => { if (codes.indexOf(x.code) < 0) codes.push(x.code); }));
      const sortie = {};
      S.collection('rbac').all(); N.invaliderRbac();
      Object.keys(N.ROLES).filter((r) => N.roleArchive(r)).forEach((r) => {
        const fiches = S.collection('rbac').all().filter((f) => f.role === r);
        const avant = fiches.map((f) => f.statut);
        fiches.forEach((f) => { f.statut = 'actif'; }); N.invaliderRbac();
        sortie[r] = {};
        codes.forEach((c) => { const d = N.droits(r, c); sortie[r][c] = d.horsMatrice ? 'hors' : [d.voir ? 1 : 0, d.editer ? 1 : 0, d.annuler ? 1 : 0]; });
        fiches.forEach((f, i) => { f.statut = avant[i]; }); N.invaliderRbac();
      });
      return sortie;
    });
  } finally { await m.fermer(); }
  const roles = rbac.roles.map((r) => {
    const mods = {};
    Object.entries(rbac.matriceModules[r.id] || {}).forEach(([c, d]) => { mods[c] = d.horsMatrice ? 'hors' : [d.voir ? 1 : 0, d.editer ? 1 : 0, d.annuler ? 1 : 0]; });
    return { id: r.id, label: r.label, short: r.short, color: r.color, home: r.home || null, labelOrigine: r.labelOrigine, shortOrigine: r.shortOrigine, archive: !!r.archive,
      modules: mods, ...(origine[r.id] ? { modulesOrigine: origine[r.id] } : {}), ecrans: rbac.parRole[r.id] || {} };
  });
  const universels = new Set(man.ecrans.filter((e) => e.universel).map((e) => e.id));
  const etiquette = Object.fromEntries(man.ecrans.map((e) => [e.id, e.label]));
  const modules = man.modules.map((x, i) => ({ id: 'MAN' + String(i + 1).padStart(2, '0'), code: x.code, label: x.label, domaine: x.domaine, icone: x.icone, alias: !!x.alias, secondaire: !!x.secondaire,
    ecrans: x.ecrans.map((id) => [id, etiquette[id] || id]), universels: x.ecrans.filter((id) => universels.has(id)),
    /* les écrans d'accueil proposés à la création d'un rôle (N.ids() filtré sur dash-), portés par la première rangée */
    ...(i === 0 ? { accueils: man.ecrans.filter((e) => /^dash-/.test(e.id)).map((e) => [e.id, e.label]) } : {}) }));
  SORTIES.forEach((d) => {
    fs.writeFileSync(path.join(d, 'rolesBase.json'), JSON.stringify(roles));
    fs.writeFileSync(path.join(d, 'modulesManifeste.json'), JSON.stringify(modules));
  });
  console.log(`  rolesBase : ${roles.length} rôles · modulesManifeste : ${modules.length} rangées · origine des archivés : ${Object.keys(origine).join(', ')}`);
})().catch((e) => { console.error(e); process.exit(1); });
