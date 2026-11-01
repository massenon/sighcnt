/* =============================================================================
 * VECTEURS DES SESSIONS ET DE LA SÉCURITÉ DES UTILISATEURS (retour de la Direction du 01/11/2026)
 * -----------------------------------------------------------------------------
 * m14-sessions (« Clôturer » change le statut) · m14-securite-utilisateurs (politique, comptes bloqués, réinitialisation imposée).
 * Les écrans RÉELS de la maquette sont montés dans la page d'extraction ; le script clique « Clôturer », confirme, lit la modale, le toast, les
 * indicateurs, la ligne du tableau et la fiche née au magasin. Les moteurs (SIGH.sessions, SIGH.securiteUtilisateurs) sont appelés sur des fiches
 * construites pour chaque cas. Les horodatages ne sont pas figés : le vecteur note leur PRÉSENCE et leur heure locale seulement.
 *   SIGH_PORT_PHP=<port> flock /tmp/sigh-banc.lock node build/vecteurs-sessions.js   →   packages/domaine/test/vecteurs/sessions_securite.json
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs des sessions et de la sécurité des utilisateurs');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m14-securite.js') });
    const sortie = await m.page.evaluate(async () => {
      const S = SIGH.store, C = SIGH.core, N = SIGH.nav, U = SIGH.ui;
      const propre = (x) => JSON.parse(JSON.stringify(x));
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const toasts = [];
      const toastOrig = U.toast;
      U.toast = function (msg, opts) { toasts.push({ message: msg, type: (opts && opts.type) || null, detail: (opts && opts.detail) || null }); return toastOrig.apply(U, arguments); };
      const nettoyer = () => document.querySelectorAll('.modal-root, [role=dialog], .drawer-root').forEach((e) => e.remove());
      const montrer = async (id) => { nettoyer(); document.querySelectorAll('[data-vecteur]').forEach((e) => e.remove()); const r = document.createElement('div'); r.setAttribute('data-vecteur', id); document.body.appendChild(r); SIGH.screens[id].render(r); await dormir(40); return r; };
      const kpis = (root) => [...root.querySelectorAll('.kpi')].map((k) => [k.querySelector('.kpi-label').textContent.trim(), k.querySelector('.kpi-value').textContent.trim()]);
      const tableau = (root, n) => { const t = [...root.querySelectorAll('table')][n || 0]; return t ? { entetes: [...t.querySelectorAll('thead th')].map((h) => h.textContent.trim()), lignes: [...t.querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('td')].map((td) => td.textContent.replace(/\s+/g, ' ').trim())) } : null; };
      const modale = () => { const mo = document.querySelector('.modal-root, [role=dialog]'); return mo ? { titre: (mo.querySelector('h2,h3') || {}).textContent, texte: mo.textContent.replace(/\s+/g, ' ').trim(), boutons: [...mo.querySelectorAll('button')].map((b) => b.textContent.trim()) } : null; };
      const cliquerModale = async (lib) => { for (let i = 0; i < 40; i++) { const b = [...document.querySelectorAll('.modal-root button, [role=dialog] button')].find((x) => x.textContent.trim() === lib); if (b) { b.click(); return true; } await dormir(100); } return false; };
      const heureLocale = (iso) => { const d = new Date(iso); return String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0'); };
      const resume = (r) => ({ ok: r.ok, code: r.code || null, motif: r.motif || null, geste: r.geste || null });
      const net = (f) => { const c = {}; Object.keys(f).forEach((k) => { if (!/^_/.test(k)) c[k] = f[k]; }); return c; };
      const sessionBanc = JSON.parse(localStorage.getItem('sigh-cnt:session'));
      const M = SIGH.sessions;

      /* ----- 1. Le jeu de démonstration amorcé par l'écran ----- */
      M.assurer();
      const moi = M.courante();
      let root = await montrer('m14-sessions');
      const comptes = propre(S.collection('utilisateurs').active().filter((u) => u.actif).slice(0, 12).map((u) => ({ id: u.id, identifiant: u.identifiant, nomComplet: u.nomComplet, role: u.role, actif: !!u.actif })));
      const demoFiches = S.raw().sessionsUtilisateur.filter((f) => f.source === 'demonstration').map((f) => ({
        id: f.id, utilisateurId: f.utilisateurId, identifiant: f.identifiant, nomComplet: f.nomComplet, role: f.role, poste: f.poste, adresseIp: f.adresseIp,
        inactivite: f.inactivite, etat: f.etat, heureDebut: heureLocale(f.debut), source: f.source, statut: f.statut }));
      const ouverture = { jour: C.iso(C.aujourdhui()), kpis: kpis(root), tableau: tableau(root), moi: { identifiant: moi.identifiant, nomComplet: moi.nomComplet, role: moi.role, etat: moi.etat, source: moi.source, adresseIp: moi.adresseIp || null }, sessionId: S.session().sessionId };

      /* ----- 2. Le geste complet sur la session d'un autre agent ----- */
      const cible = S.raw().sessionsUtilisateur.find((f) => f.source === 'demonstration' && f.etat === 'active');
      const clic = (identifiant, lib) => { const tr = [...document.querySelectorAll('[data-vecteur] tbody tr')].find((t) => [...t.querySelectorAll('td')].some((c) => c.textContent.trim() === identifiant)); const b = tr && [...tr.querySelectorAll('button')].find((x) => x.textContent.trim() === lib); if (b) b.click(); return !!b; };
      const geste = {};
      geste.boutonOffert = clic(cible.identifiant, 'Clôturer'); await dormir(250);
      geste.confirmation = modale();
      await cliquerModale('Annuler'); await dormir(100);
      geste.apresAnnulation = S.raw().sessionsUtilisateur.find((f) => f.id === cible.id).etat;
      const nbToasts = toasts.length;
      clic(cible.identifiant, 'Clôturer'); await dormir(250); await cliquerModale('Clôturer la session'); await dormir(400);
      const fiche = S.raw().sessionsUtilisateur.find((f) => f.id === cible.id);
      geste.fiche = { etat: fiche.etat, clotureLePresent: !!fiche.clotureLe, cloturePar: fiche.cloturePar, clotureParIdentifiant: fiche.clotureParIdentifiant, clotureMotif: fiche.clotureMotif == null ? null : fiche.clotureMotif, cloturePropre: fiche.cloturePropre, statut: fiche.statut };
      geste.toasts = toasts.slice(nbToasts);
      geste.audit = (() => { const a = S.raw().audit[0]; return { action: a.action, module: a.module, entite: a.entite, reference: a.reference }; })();
      root = document.querySelector('[data-vecteur]');
      geste.kpisApres = kpis(root);
      const trApres = [...root.querySelectorAll('tbody tr')].find((t) => [...t.querySelectorAll('td')].some((c) => c.textContent.trim() === cible.identifiant));
      geste.ligneApres = trApres ? [...trApres.querySelectorAll('td')].map((td) => td.textContent.replace(/\s+/g, ' ').trim()) : null;
      geste.boutonApres = trApres ? [...trApres.querySelectorAll('button')].some((b) => b.textContent.trim() === 'Clôturer') : null;
      const sel = [...root.querySelectorAll('select')].find((s) => s.getAttribute('aria-label') === 'État');
      geste.filtreOptions = sel ? [...sel.options].map((o) => [o.value, o.textContent.trim()]) : null;
      sel.value = 'cloturee'; sel.dispatchEvent(new Event('change')); await dormir(200);
      geste.filtreClotures = root.querySelectorAll('tbody tr').length;
      sel.value = 'ouverte'; sel.dispatchEvent(new Event('change')); await dormir(200);
      geste.filtreOuvertes = root.querySelectorAll('tbody tr').length;
      sel.value = ''; sel.dispatchEvent(new Event('change')); await dormir(100);
      /* La confirmation de la session PROPRE */
      geste.proprePresent = clic(moi.identifiant, 'Clôturer'); await dormir(250);
      geste.confirmationPropre = modale();
      await cliquerModale('Annuler'); await dormir(100);

      /* ----- 3. Le moteur sur des fiches construites ----- */
      const col = M.collection();
      const reprendre = (id, patch) => { const f = col.get(id); Object.assign(f, patch); };
      const autres = S.raw().sessionsUtilisateur.filter((f) => f.source === 'demonstration' && f.etat !== 'cloturee');
      const cas = [];
      const run = (nom, id, opts, role) => {
        const sauve = localStorage.getItem('sigh-cnt:session');
        if (role) localStorage.setItem('sigh-cnt:session', JSON.stringify(Object.assign(JSON.parse(sauve), { role: role })));
        const avant = id && col.get(id) ? net(col.get(id)) : null;
        const r = M.cloturer(id, opts);
        localStorage.setItem('sigh-cnt:session', sauve);
        const apres = id && col.get(id) ? col.get(id) : null;
        cas.push({ nom: nom, id: id, opts: opts || {}, role: role || sessionBanc.role, avantEtat: avant && avant.etat, resultat: resume(r),
          patch: r.ok ? { etat: apres.etat, clotureLePresent: !!apres.clotureLe, cloturePar: apres.cloturePar, clotureParIdentifiant: apres.clotureParIdentifiant, clotureMotif: apres.clotureMotif == null ? null : apres.clotureMotif, cloturePropre: apres.cloturePropre } : null });
      };
      run('session inconnue', 'SES-INEXISTANTE');
      run('profil sans droit d’édition (caissier)', autres[0].id, {}, 'caissier');
      run('session d’un autre agent, avec motif', autres[0].id, { motif: 'Poste laissé ouvert' });
      run('déjà clôturée', autres[0].id);
      run('sa propre session sans confirmation', moi.id);
      run('sa propre session, confirmée', moi.id, { confirmePropre: true });
      run('session d’un autre agent, sans motif', autres[1].id);

      /* ----- 4. La sécurité des utilisateurs ----- */
      const X = SIGH.securiteUtilisateurs;
      await montrer('m14-securite-utilisateurs');
      root = document.querySelector('[data-vecteur]');
      const secOuverture = { kpis: kpis(root), onglets: [...root.querySelectorAll('[role=tab]')].map((t) => t.textContent.trim()), politique: tableau(root), parametres: propre(X.PARAMETRES), defaut: propre(X.politique()),
        rolesDoubleFacteur: propre(X.ROLES_DOUBLE_FACTEUR) };
      const colU = S.collection('utilisateurs');
      const demo = colU.active().find((u) => u.identifiant === 'demo.anesthesiste');
      const comptesCas = [];
      const compteRun = (nom, fn) => { const avant = net(colU.get(demo.id)); const r = fn(); const apres = net(colU.get(demo.id)); const diff = {}; Object.keys(apres).forEach((k) => { if (JSON.stringify(apres[k]) !== JSON.stringify(avant[k])) diff[k] = /Le$/.test(k) ? '<date>' : apres[k]; });
        comptesCas.push({ nom: nom, avant: { bloque: !!avant.bloque, echecs: avant.echecs || 0, doitChanger: avant.doitChangerMotDePasse === true, motDePasseDefiniLe: avant.motDePasseDefiniLe || null }, resultat: resume(r), diff: r.ok ? diff : {} }); };
      compteRun('bloquer sans motif', () => X.bloquer(demo.id, '  '));
      compteRun('bloquer un compte inconnu', () => X.bloquer('USR-INCONNU', 'motif'));
      compteRun('débloquer un compte non bloqué', () => X.debloquer(demo.id));
      const sauveS = localStorage.getItem('sigh-cnt:session');
      localStorage.setItem('sigh-cnt:session', JSON.stringify(Object.assign(JSON.parse(sauveS), { identifiant: 'demo.anesthesiste' })));
      compteRun('bloquer son propre compte', () => X.bloquer(demo.id, 'essai'));
      localStorage.setItem('sigh-cnt:session', sauveS);
      compteRun('bloquer avec motif', () => X.bloquer(demo.id, '  Départ du poste  '));
      compteRun('bloquer deux fois', () => X.bloquer(demo.id, 'encore'));
      compteRun('débloquer', () => X.debloquer(demo.id));
      colU.update(demo.id, { echecs: 3 });
      compteRun('débloquer un compte bloqué par ses échecs', () => X.debloquer(demo.id));
      compteRun('imposer la réinitialisation', () => X.imposerReinitialisation(demo.id));
      compteRun('imposer la réinitialisation deux fois', () => X.imposerReinitialisation(demo.id));
      const politiqueCas = [];
      const base = propre(X.politique());
      const pol = (nom, v) => { const r = X.enregistrerPolitique(Object.assign({}, base, v)); politiqueCas.push({ nom: nom, valeurs: v, resultat: { ok: r.ok, code: r.code || null, motif: r.motif || null, geste: r.geste || null }, politique: propre(X.politique()) }); };
      pol('longueur trop courte', { longueurMin: 7 });
      pol('longueur trop longue', { longueurMin: 65 });
      pol('expiration négative', { expirationJours: -1 });
      pol('expiration à zéro (n’expire pas)', { expirationJours: 0 });
      pol('historique à 24', { historique: 24 });
      pol('échecs à zéro', { echecsMax: 0 });
      pol('échecs à dix', { echecsMax: 10 });
      pol('blocage à 1441', { blocageMin: 1441 });
      pol('inactivité à 120', { inactiviteMin: 120 });
      pol('inactivité fractionnaire', { inactiviteMin: 10.5 });
      X.enregistrerPolitique(base);
      /* Expiration et réinitialisation : le calcul est celui de l'écran, sur des dates fixes. */
      const jour = C.aujourdhui();
      const jours = (n) => new Date(jour.getTime() - n * 86400000).toISOString();
      const expiration = [0, 10, 89, 90, 91, 200].map((n) => { const u = { motDePasseDefiniLe: jours(n) }; return { age: n, restant: X.joursAvantExpiration(u), reinit: X.aReinitialiser(u) }; });
      expiration.push({ age: null, restant: X.joursAvantExpiration({}), reinit: X.aReinitialiser({}) });
      expiration.push({ age: 5, imposee: true, restant: X.joursAvantExpiration({ motDePasseDefiniLe: jours(5), doitChangerMotDePasse: true }), reinit: X.aReinitialiser({ motDePasseDefiniLe: jours(5), doitChangerMotDePasse: true }) });
      const bloquage = [[0, false], [2, false], [3, true], [7, true]].map(([e, b]) => ({ echecs: e, bloque: false, attendu: X.estBloque({ echecs: e }) })).concat([{ echecs: 0, bloque: true, attendu: X.estBloque({ echecs: 0, bloque: true }) }]);

      /* Le geste « Bloquer » par la modale, sur l'onglet des comptes */
      root.querySelector('[data-tab="comptes"]').click(); await dormir(150);
      const comptesOnglet = { kpisAvant: kpis(root), tableau: (() => { const t = tableau(root); return { entetes: t.entetes, nbLignes: t.lignes.length }; })(), filtreOptions: (() => { const s = [...root.querySelectorAll('select')].find((x) => x.getAttribute('aria-label') === 'Situation'); return s ? [...s.options].map((o) => [o.value, o.textContent.trim()]) : null; })() };
      const rech = root.querySelector('input[type=search]'); rech.value = 'demo.anesthesiste'; rech.dispatchEvent(new Event('input')); await dormir(400);
      const ligneAvant = [...root.querySelectorAll('tbody tr')].find((t) => /demo\.anesthesiste/.test(t.textContent));
      comptesOnglet.boutonsAvant = [...ligneAvant.querySelectorAll('button')].map((b) => b.textContent.trim());
      [...ligneAvant.querySelectorAll('button')].find((b) => b.textContent.trim() === 'Bloquer').click(); await dormir(300);
      comptesOnglet.modaleBlocage = modale();
      document.getElementById('motif-blocage').value = 'Accès à retirer';
      await cliquerModale('Bloquer le compte'); await dormir(400);
      root = document.querySelector('[data-vecteur]');
      comptesOnglet.kpisApres = kpis(root);
      comptesOnglet.toasts = toasts.slice(-2).map((t) => [t.message, t.detail]);
      X.debloquer(demo.id);

      return { jour: C.iso(C.aujourdhui()), comptes, demoFiches, ouverture, geste, cas, secOuverture, comptesCas, politiqueCas, expiration, bloquage, comptesOnglet,
        etats: propre(M.ETATS), idDemo: demo.id };
    });
    ecrire('packages/domaine/test/vecteurs/sessions_securite.json', sortie);
    if (m.erreurs.length) console.log('  erreurs JS de la page :', m.erreurs.slice(0, 3));
  } finally {
    await m.fermer();
  }
})().catch((e) => { console.error(e); process.exit(1); });
