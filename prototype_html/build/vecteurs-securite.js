/* =============================================================================
 * VECTEURS DE M14 — SÉCURITÉ, UTILISATEURS & AUDIT (les sept écrans, PILOTÉS comme le fait l'agent)
 * -----------------------------------------------------------------------------
 * m14-utilisateurs · m14-roles · m14-soignants · m14-sessions · m14-audit · m14-sauvegardes · m14-taches.
 * Le script monte les écrans réels de `assets/js/modules/m14-securite.js`, ouvre les modales, remplit les formulaires, clique, et relit ce qui est né
 * au magasin (les mots de passe ne sont jamais écrits dans le vecteur : on enregistre qu'ils n'ont pas été gardés).
 *   node build/vecteurs-securite.js   →   packages/domaine/test/vecteurs/securite.json
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

function litteralDart(x, indent) {
  const pad = '  '.repeat(indent || 0);
  if (x === null || x === undefined) return 'null';
  if (typeof x === 'string') return "'" + x.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$').replace(/\n/g, '\\n') + "'";
  if (typeof x === 'number' || typeof x === 'boolean') return String(x);
  if (Array.isArray(x)) {
    if (!x.length) return '<Object?>[]';
    return '[\n' + x.map((v) => pad + '  ' + litteralDart(v, (indent || 0) + 1) + ',').join('\n') + '\n' + pad + ']';
  }
  const ks = Object.keys(x);
  if (!ks.length) return '<String, Object?>{}';
  return '{\n' + ks.map((k) => pad + '  ' + litteralDart(k) + ': ' + litteralDart(x[k], (indent || 0) + 1) + ',').join('\n') + '\n' + pad + '}';
}

(async () => {
  console.log('▶ Vecteurs de M14 — sécurité');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m14-securite.js') });
    const sortie = await m.page.evaluate(async () => {
      const S = SIGH.store, C = SIGH.core, N = SIGH.nav, D = SIGH.data, U = SIGH.ui;
      const propre = (x) => JSON.parse(JSON.stringify(x));
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const toasts = [];
      const toastOrig = U.toast;
      U.toast = function (msg, opts) { toasts.push({ message: msg, type: (opts && opts.type) || null, detail: (opts && opts.detail) || null }); return toastOrig.apply(U, arguments); };
      const nettoyer = () => document.querySelectorAll('.modal-root, [role=dialog], .drawer-root').forEach((e) => e.remove());
      const montrer = (id) => { nettoyer(); document.querySelectorAll('[data-vecteur]').forEach((e) => e.remove()); const r = document.createElement('div'); r.setAttribute('data-vecteur', id); document.body.appendChild(r); SIGH.screens[id].render(r); return r; };
      const bouton = (txt, dans) => [...(dans || document).querySelectorAll('button')].find((b) => b.textContent.trim() === txt || b.textContent.trim().startsWith(txt));
      const poser = (id, v) => { const e = document.getElementById('f_' + id); if (!e) throw new Error('champ ' + id); if (e.type === 'checkbox') { e.checked = !!v; } else e.value = v; e.dispatchEvent(new Event('input')); e.dispatchEvent(new Event('change')); };
      const sansSecret = (x) => { const c = Object.assign({}, x); delete c.motDePasse; delete c.motDePasseConfirmation; return c; };
      const net = (x) => { const c = sansSecret(x); ['id', '_creePar', '_creeLe', '_modifiePar', '_modifieLe'].forEach((k) => delete c[k]); return propre(c); };
      const dernierToast = () => toasts[toasts.length - 1] || null;
      const kpis = (root) => [...root.querySelectorAll('.kpi')].map((k) => [k.querySelector('.kpi-label').textContent.trim(), k.querySelector('.kpi-value').textContent.trim()]);
      const tableau = (root, n) => { const t = [...root.querySelectorAll('table')][n || 0]; return { entetes: [...t.querySelectorAll('thead th')].map((h) => h.textContent.trim()), lignes: [...t.querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('td')].map((td) => td.textContent.replace(/\s+/g, ' ').trim())) }; };
      const imprime = []; const etatOrig = SIGH.print.etat; SIGH.print.etat = function (o) { imprime.push({ titre: o.titre, sousTitre: o.sousTitre || null, cartouche: o.cartouche || null, signatures: o.signatures || null, texte: o.contenu && o.contenu.textContent ? o.contenu.textContent.replace(/\s+/g, ' ').trim().slice(0, 1500) : null }); };
      const utilisateursInitiaux = propre(S.collection('utilisateurs').active().filter((u) => u.actif).slice(0, 12).map((u) => ({ id: u.id, identifiant: u.identifiant, nomComplet: u.nomComplet, role: u.role })));
      /* ----- 0. Les sessions (calculées, sur le jeu AVANT toute écriture de ce script) ----- */
      const sessions = (() => { const root = montrer('m14-sessions'); return { utilisateurs: propre(S.collection('utilisateurs').active().filter((u) => u.actif).slice(0, 12).map((u) => ({ id: u.id, identifiant: u.identifiant, nomComplet: u.nomComplet, role: u.role }))), kpis: kpis(root), tableau: tableau(root), jour: C.iso(C.aujourdhui()) }; })();
      nettoyer();
      const sessionsCloture = await (async () => { const root = montrer('m14-sessions'); await dormir(20); const nb = toasts.length; const nbAudit = (S.raw().audit || []).length; const b = bouton('Clôturer', root); b.click(); await dormir(40); const conf = [...document.querySelectorAll('.modal-root button, [role=dialog] button')].find((x) => x.textContent.trim() === 'Clôturer la session'); const msg = (document.querySelector('.modal-root, [role=dialog]') || { textContent: '' }).textContent.replace(/\s+/g, ' ').trim(); conf.click(); await dormir(60); const a = (S.raw().audit || []); return { message: msg, toasts: toasts.slice(nb), audit: propre(a[0] || null), nbAudit: a.length - nbAudit }; })();
      nettoyer();
      /* ----- 0bis. L'écran des rôles à l'ouverture, AVANT toute écriture ----- */
      const rolesOuverture = await (async () => {
        const root = montrer('m14-roles'); await dormir(40);
        const sortie = { kpis: kpis(root) };
        const t = tableau(root); sortie.entetes = t.entetes; sortie.lignes = t.lignes.map((l) => [l[0], l[l.length - 1]]);
        sortie.libelles = Object.keys(N.ROLES).filter((r) => !N.roleArchive(r)).map((r) => [r, N.ROLES[r].label, N.ROLES[r].labelOrigine]);
        sortie.comptesParRole = {}; S.collection('utilisateurs').active().forEach((u) => { sortie.comptesParRole[u.role] = (sortie.comptesParRole[u.role] || 0) + 1; });
        const onglet = (txt) => [...root.querySelectorAll('button')].find((b) => b.textContent.trim().startsWith(txt));
        onglet('Habilitations métier').click(); await dormir(60);
        sortie.habilitations = tableau(root);
        onglet('Rôles archivés').click(); await dormir(60);
        sortie.archives = tableau(root);
        onglet('Détail par rôle').click(); await dormir(60);
        sortie.detail = [...root.querySelectorAll('.card')].filter((c) => c.querySelector('.card-body .flex.flex-wrap')).slice(0, 3).map((c) => c.textContent.replace(/\s+/g, ' ').trim());
        return sortie;
      })();
      nettoyer();

      /* ----- 1. Les comptes : le formulaire de m14-utilisateurs ----- */
      const colU = S.collection('utilisateurs');
      const personnel = S.collection('personnel').active();
      const agent = personnel.find((e) => e.nomComplet === 'TAKI Alimatou') || personnel[0];
      const agent2 = personnel.find((e) => e.id !== agent.id);
      const cas = [];
      async function creer(nom, saisie) {
        const root = montrer('m14-utilisateurs'); await dormir(20);
        const avant = new Set(colU.all().map((x) => x.id));
        const nbToasts = toasts.length;
        bouton('Nouveau', root).click(); await dormir(30);
        Object.entries(saisie).forEach(([k, v]) => poser(k, v));
        bouton('Créer').click(); await dormir(40);
        const nouveaux = colU.all().filter((x) => !avant.has(x.id));
        const t = toasts.slice(nbToasts).map((x) => x.message);
        cas.push({ nom, mode: 'creation', saisie: sansSecret(saisie), motDePasseSaisi: !!saisie.motDePasse, motDePasseLongueur: String(saisie.motDePasse || '').length,
          creee: nouveaux.map((x) => ({ fiche: net(x), definiLe: !!x.motDePasseDefiniLe, definiPar: x.motDePasseDefiniPar || null, aMotDePasse: 'motDePasse' in x, aConfirmation: 'motDePasseConfirmation' in x })),
          toasts: t, jour: C.iso(C.aujourdhui()) });
        nettoyer();
      }
      const base = { identifiant: 'v.test1', employeId: agent.id, role: 'reception', service: 'Accueil', actif: true, mfa: false, motDePasse: 'abcdefgh', motDePasseConfirmation: 'abcdefgh', doitChangerMotDePasse: true };
      await creer('création ordinaire : l\'agent est rattaché, le mot de passe n\'est pas gardé', base);
      await creer('rôle « dm » : le double facteur est imposé même décoché', Object.assign({}, base, { identifiant: 'v.test2', role: 'dm', mfa: false }));
      await creer('rôle « direction » : double facteur imposé', Object.assign({}, base, { identifiant: 'v.test3', role: 'direction' }));
      await creer('rôle « admin » : double facteur imposé', Object.assign({}, base, { identifiant: 'v.test4', role: 'admin' }));
      await creer('rôle « da » : double facteur imposé', Object.assign({}, base, { identifiant: 'v.test5', role: 'da' }));
      await creer('double facteur coché sur un rôle ordinaire : conservé', Object.assign({}, base, { identifiant: 'v.test6', mfa: true }));
      await creer('changement obligatoire décoché : conservé tel que saisi (faux)', Object.assign({}, base, { identifiant: 'v.test7', doitChangerMotDePasse: false }));
      await creer('compte désactivé à la création', Object.assign({}, base, { identifiant: 'v.test8', actif: false }));
      await creer('identifiant déjà attribué : refusé en le disant', Object.assign({}, base, { identifiant: 'admin.systeme' }));
      await creer('mot de passe de sept caractères : refusé', Object.assign({}, base, { identifiant: 'v.test9', motDePasse: 'abcdefg', motDePasseConfirmation: 'abcdefg' }));
      await creer('mot de passe de huit caractères : accepté', Object.assign({}, base, { identifiant: 'v.test10', motDePasse: '12345678', motDePasseConfirmation: '12345678' }));
      await creer('confirmation différente : refusée', Object.assign({}, base, { identifiant: 'v.test11', motDePasseConfirmation: 'abcdefgX' }));
      await creer('mot de passe de huit espaces : compte huit caractères', Object.assign({}, base, { identifiant: 'v.test12', motDePasse: '        ', motDePasseConfirmation: '        ' }));
      await creer('identifiant vide : formulaire en erreur', Object.assign({}, base, { identifiant: '' }));
      await creer('sans agent rattaché : ni nom ni matricule', Object.assign({}, base, { identifiant: 'v.test13', employeId: '' }));
      await creer('autre agent, service laissé au choix', Object.assign({}, base, { identifiant: 'v.test14', employeId: agent2.id, service: '' }));

      /* Édition : pas de champs de mot de passe, doublon d'identifiant testé contre les AUTRES comptes. */
      async function modifier(nom, cible, saisie) {
        const root = montrer('m14-utilisateurs'); await dormir(20);
        const nbToasts = toasts.length;
        const avantFiche = net(colU.get(cible.id));
        const ligne = [...root.querySelectorAll('tbody tr')].find((tr) => { const td = tr.querySelectorAll('td'); return [...td].some((c) => c.textContent.trim() === cible.identifiant); });
        let ouvert = false;
        if (ligne) { const b = [...ligne.querySelectorAll('button')].find((x) => (x.title || x.getAttribute('aria-label') || '').includes('Modifier')); if (b) { b.click(); ouvert = true; } }
        if (!ouvert) {
          /* hors de la première page : on ouvre le formulaire par l'écran lui-même */
          const rech = root.querySelector('input[type=search], input[placeholder*="Rechercher"]');
          if (rech) { rech.value = cible.identifiant; rech.dispatchEvent(new Event('input')); await dormir(400); }
          const l2 = [...root.querySelectorAll('tbody tr')].find((tr) => [...tr.querySelectorAll('td')].some((c) => c.textContent.trim() === cible.identifiant));
          const b2 = l2 && [...l2.querySelectorAll('button')].find((x) => (x.title || x.getAttribute('aria-label') || '').includes('Modifier'));
          if (!b2) throw new Error('Modifier introuvable pour ' + cible.identifiant);
          b2.click();
        }
        await dormir(30);
        const champsMdp = ['motDePasse', 'motDePasseConfirmation', 'doitChangerMotDePasse'].filter((k) => document.getElementById('f_' + k));
        Object.entries(saisie).forEach(([k, v]) => poser(k, v));
        bouton('Enregistrer').click(); await dormir(40);
        cas.push({ nom, mode: 'edition', cible: cible.id, avant: avantFiche, saisie, champsMotDePasseAffiches: champsMdp, apres: net(colU.get(cible.id)), toasts: toasts.slice(nbToasts).map((x) => x.message) });
        nettoyer();
      }
      const cibleA = colU.all().find((u) => u.identifiant === 'v.test1');
      await modifier('modifier le rôle vers « dm » : double facteur imposé', cibleA, { role: 'dm' });
      await modifier('conserver son propre identifiant : pas de doublon', cibleA, { service: 'Direction' });
      await modifier('prendre l\'identifiant d\'un autre : refusé', cibleA, { identifiant: 'admin.systeme' });
      await modifier('changer d\'agent rattaché : nom, matricule, poste suivent', cibleA, { employeId: agent2.id });
      const cibleB = colU.all().find((u) => u.identifiant === 's.bassongui');
      await modifier('modifier un compte ancien : dernier accès et échecs conservés (E591)', cibleB, { service: 'Direction' });

      /* ----- 2. Les rôles : la matrice administrable ----- */
      const colR = S.collection('rbac');
      const colT = S.collection('tentativesConnexion');
      const modules = []; N.NAV.forEach((d) => d.modules.forEach((x) => modules.push({ code: x.code, label: x.label, domaine: d.domain })));
      const matrice = () => { const o = {}; Object.keys(N.ROLES).forEach((r) => { o[r] = {}; modules.forEach((x) => { const d = N.droits(r, x.code); o[r][x.code] = d.horsMatrice ? { horsMatrice: true } : { voir: !!d.voir, editer: !!d.editer, annuler: !!d.annuler }; }); }); return o; };
      const roles = () => { const o = {}; Object.keys(N.ROLES).forEach((r) => { o[r] = { label: N.ROLES[r].label, short: N.ROLES[r].short, archive: !!N.roleArchive(r), labelOrigine: N.ROLES[r].labelOrigine, color: N.ROLES[r].color, home: N.ROLES[r].home || null }; }); return o; };
      const ficheDe = (r) => { const f = colR.all().filter((x) => x.role === r); return f.length ? propre(f) : null; };
      const sansTemps = (f) => { if (!f) return f; return f.map((x) => { const c = Object.assign({}, x); ['_creePar', '_creeLe', '_modifiePar', '_modifieLe'].forEach((k) => delete c[k]); return c; }); };
      const rolesCas = [];
      const ouvrirRoles = async () => { const root = montrer('m14-roles'); await dormir(30); return root; };
      const ligneRole = (root, r) => [...root.querySelectorAll('tbody tr')].find((tr) => { const p = tr.querySelector('td p'); return p && p.textContent.trim() === N.ROLES[r].label; });
      const iconeLigne = (tr, titre) => [...tr.querySelectorAll('button')].find((b) => (b.title || b.getAttribute('aria-label') || '') === titre);
      let roleCible = null;
      const instantane = () => { const mt = matrice(), ro = roles(); return { matrice: mt[roleCible], matriceAutres: JSON.stringify(Object.keys(mt).filter((r) => r !== roleCible).map((r) => mt[r])), roles: ro[roleCible], fiches: sansTemps(propre(colR.all().filter((x) => x.role === roleCible))) }; };

      /* 2a. Cases cochées dans « Modifier les droits » : l'état écrit */
      async function droitsRole(nom, role, geste) {
        roleCible = role;
        const root = await ouvrirRoles();
        const avant = instantane();
        iconeLigne(ligneRole(root, role), 'Modifier les droits de ce rôle').click(); await dormir(40);
        const cases = [...document.querySelectorAll('.modal-root input[type=checkbox], [role=dialog] input[type=checkbox]')];
        const lignes = modules.map((x, i) => ({ code: x.code, voir: cases[i * 4], editer: cases[i * 4 + 1], annuler: cases[i * 4 + 2], lecture: cases[i * 4 + 3] }));
        const tracer = () => lignes.map((l) => ({ code: l.code, voir: l.voir.checked, editer: l.editer.checked, annuler: l.annuler.checked, lecture: l.lecture.checked }));
        const initial = tracer();
        const clic = (c, v) => { if (c.checked !== v) { c.checked = v; c.dispatchEvent(new Event('change', { bubbles: true })); } };
        geste({ lignes, clic, bouton });
        await dormir(10);
        const saisi = tracer();
        const nbToasts = toasts.length;
        bouton('Enregistrer les droits').click(); await dormir(40);
        rolesCas.push({ nom, type: 'droits', role, avant, initial, saisi, apres: instantane(), toasts: toasts.slice(nbToasts) });
        nettoyer();
      }
      await droitsRole('lecture seule cochée : voir sans éditer ni annuler', 'reception', ({ lignes, clic }) => { const l = lignes.find((x) => x.code === 'M10'); clic(l.lecture, true); });
      await droitsRole('éditer coché ouvre aussi « voir »', 'caissier', ({ lignes, clic }) => { const l = lignes.find((x) => x.code === 'M12'); clic(l.editer, true); });
      await droitsRole('décocher « voir » retire éditer et annuler', 'medecin', ({ lignes, clic }) => { const l = lignes.find((x) => x.code === 'M8'); clic(l.voir, false); });
      await droitsRole('annuler coché seul ouvre « voir » (éditer reste faux)', 'infirmier', ({ lignes, clic }) => { const l = lignes.find((x) => x.code === 'M9'); clic(l.annuler, true); });
      await droitsRole('lecture seule décochée : le module reste visible', 'stock', ({ lignes, clic }) => { const l = lignes.find((x) => x.code === 'M5'); clic(l.lecture, true); clic(l.lecture, false); });
      await droitsRole('« Tout fermer »', 'comptable', ({ bouton }) => { bouton('Tout fermer').click(); });
      await droitsRole('« Tout en lecture seule »', 'agentadmin', ({ bouton }) => { bouton('Tout en lecture seule').click(); });
      await droitsRole('« Tout ouvrir »', 'ambulancier', ({ bouton }) => { bouton('Tout ouvrir').click(); });

      /* 2b. Réglage écran par écran */
      async function ecransRole(nom, role, codeModule, geste, retirer) {
        roleCible = role;
        const root = await ouvrirRoles();
        const avant = instantane();
        const droitsAvant = {};
        N.NAV.forEach((d) => d.modules.forEach((x) => x.items.forEach((it) => { const dd = N.droitsEcran(role, it.id, x.code); droitsAvant[it.id] = { voir: !!dd.voir, editer: !!dd.editer, annuler: !!dd.annuler, surcharge: !!dd.surchargeEcran }; })));
        iconeLigne(ligneRole(root, role), 'Régler écran par écran').click(); await dormir(40);
        const sel = document.querySelector('.modal-root select, [role=dialog] select');
        if (codeModule && sel) { sel.value = codeModule; sel.dispatchEvent(new Event('change')); await dormir(20); }
        const lignes = [...document.querySelectorAll('.modal-root tbody tr, [role=dialog] tbody tr')].map((tr) => ({ id: (tr.querySelector('.font-mono') || {}).textContent, cases: [...tr.querySelectorAll('input[type=checkbox]')], origine: tr.lastElementChild.textContent.trim() }));
        const initial = lignes.map((l) => ({ id: l.id, voir: l.cases[0].checked, editer: l.cases[1].checked, annuler: l.cases[2].checked, origine: l.origine }));
        const clic = (c, v) => { if (c.checked !== v) { c.checked = v; c.dispatchEvent(new Event('change', { bubbles: true })); } };
        if (geste) geste({ lignes, clic });
        const nbToasts = toasts.length;
        bouton(retirer ? 'Retirer tous les réglages d’écran' : 'Enregistrer').click(); await dormir(40);
        rolesCas.push({ nom, type: 'ecrans', role, module: sel ? sel.value : null, avant, initial, apres: instantane(), toasts: toasts.slice(nbToasts), nbEcransModule: lignes.length });
        nettoyer();
      }
      await ecransRole('fermer un écran du module ouvert (m1-dossier-medical au laborantin)', 'laborantin', 'M1', ({ lignes, clic }) => { const l = lignes.find((x) => x.id === 'm1-patients'); if (l) clic(l.cases[0], false); });
      await ecransRole('éditer coché sur un écran ouvre « voir »', 'reception', 'M1', ({ lignes, clic }) => { const l = lignes[1]; clic(l.cases[1], true); });
      await ecransRole('retirer tous les réglages d\'écran', 'laborantin', 'M1', null, true);

      /* 2c. Création d'un rôle */
      async function creerRole(nom, saisie) {
        roleCible = String(saisie.id).toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]/g, '');
        const root = await ouvrirRoles();
        const avant = instantane();
        const nbToasts = toasts.length;
        const act = (SIGH.screens['m14-roles'].actions ? SIGH.screens['m14-roles'].actions() : []).find((b) => b.textContent.includes('Nouveau rôle')); if (!act) throw new Error('Nouveau rôle absent'); act.click(); await dormir(40);
        Object.entries(saisie).forEach(([k, v]) => poser(k, v));
        bouton('Créer le rôle').click(); await dormir(40);
        const id = String(saisie.id).toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]/g, '');
        rolesCas.push({ nom, type: 'creation', saisie, avant, apres: instantane(), fiche: sansTemps(ficheDe(id)), idAttendu: id, toasts: toasts.slice(nbToasts), nbEcransOuverts: N.tree(id).reduce((n, d) => n + d.modules.reduce((k, mo) => k + mo.items.length, 0), 0) });
        nettoyer();
      }
      await creerRole('création d\'un rôle : tous les modules fermés', { libelle: 'Auditeur externe', libelleCourt: 'Auditeur', id: 'Auditeur Externe', couleur: 'info', accueil: 'dash-admin', motif: 'Revue de conformité' });
      await creerRole('identifiant déjà pris : refusé', { libelle: 'Autre', id: 'medecin', couleur: 'neutral', accueil: 'dash-admin' });
      await creerRole('identifiant sans caractère valable : refusé', { libelle: 'Vide', id: '---', couleur: 'neutral', accueil: 'dash-admin' });
      await creerRole('intitulé abrégé omis : reprend l\'intitulé', { libelle: 'Veilleur de nuit', id: 'veilleur', accueil: 'dash-admin' });

      /* 2d. Renommage, archivage, restauration */
      async function renommer(nom, role, libelle) {
        roleCible = role;
        const root = await ouvrirRoles();
        const avant = instantane();
        const nbToasts = toasts.length;
        iconeLigne(ligneRole(root, role), 'Renommer ce rôle').click(); await dormir(40);
        poser('libelle', libelle);
        bouton('Renommer').click(); await dormir(40);
        rolesCas.push({ nom, type: 'renommage', role, libelle, avant, apres: instantane(), fiche: sansTemps(ficheDe(role)), toasts: toasts.slice(nbToasts) });
        nettoyer();
      }
      await renommer('renommer le laborantin', 'laborantin', 'Biologiste médical (test)');
      await renommer('renommer le caissier (deux fiches RBAC fusionnées)', 'caissier', 'Caissier test');

      async function archiver(nom, role, motif) {
        roleCible = role;
        const root = await ouvrirRoles();
        const avant = instantane();
        const nbToasts = toasts.length;
        const ligne = ligneRole(root, role);
        iconeLigne(ligne, 'Archiver ce rôle').click(); await dormir(40);
        const motifChamp = document.querySelector('.modal-root textarea, [role=dialog] textarea, .modal-root input[type=text], [role=dialog] input[type=text]');
        if (motifChamp && motif) { motifChamp.value = motif; motifChamp.dispatchEvent(new Event('input')); }
        const conf = [...document.querySelectorAll('.modal-root button, [role=dialog] button')].find((b) => b.textContent.trim() === 'Archiver le rôle');
        const message = (document.querySelector('.modal-root, [role=dialog]') || { textContent: '' }).textContent;
        if (conf) conf.click(); await dormir(60);
        rolesCas.push({ nom, type: 'archivage', role, motif, avant, apres: instantane(), fiche: sansTemps(ficheDe(role)), toasts: toasts.slice(nbToasts), messageConfirmation: message.replace(/\s+/g, ' ').trim() });
        nettoyer();
      }
      S.session && (S.session().role);
      await archiver('archiver un rôle portant des comptes', 'ambulancier', 'Poste supprimé');
      await archiver('archiver un rôle sans compte', 'veilleur', 'Test');
      /* le rôle de la session en cours ne s'archive pas */
      const roleSession = (S.session() || {}).role;
      await archiver('le rôle de la session en cours ne s\'archive pas', roleSession, 'Test');

      async function restaurer(nom, role) {
        roleCible = role;
        const root = await ouvrirRoles();
        const avant = instantane();
        const nbToasts = toasts.length;
        const tab = [...root.querySelectorAll('button')].find((b) => b.textContent.trim().startsWith('Rôles archivés')); tab.click(); await dormir(30);
        const ligne = [...root.querySelectorAll('tbody tr')].find((tr) => tr.textContent.includes(N.ROLES[role].label));
        const b = ligne && [...ligne.querySelectorAll('button')].find((x) => (x.title || x.getAttribute('aria-label') || '') === 'Restaurer ce rôle');
        if (!b) throw new Error('restaurer ' + role);
        b.click(); await dormir(60);
        rolesCas.push({ nom, type: 'restauration', role, avant, apres: instantane(), fiche: sansTemps(ficheDe(role)), toasts: toasts.slice(nbToasts) });
        nettoyer();
      }
      await restaurer('restaurer un rôle archivé par l\'administrateur', 'ambulancier');
      await restaurer('restaurer un rôle archivé au socle (rh)', 'rh');
      await restaurer('restaurer un rôle archivé au socle (pharmacien)', 'pharmacien');

      /* 2e. Tentatives refusées : la connexion d'un rôle archivé est journalisée par auth.js */
      const tentativesAvant = propre(colT.all());
      colT.insert({ identifiant: 'v.test1', nom: 'Test Tentative', role: 'veilleur', motif: 'Rôle archivé', horodatage: new Date('2026-10-30T09:00:00Z').toISOString() });
      colT.insert({ identifiant: 'v.test2', nom: 'Test Deux', role: 'veilleur', motif: 'Rôle archivé', horodatage: new Date('2026-10-30T09:05:00Z').toISOString() });
      {
        const root = await ouvrirRoles();
        const kpis = [...root.querySelectorAll('.kpi, [class*=kpi]')].map((k) => k.textContent.replace(/\s+/g, ' ').trim()).slice(0, 8);
        const alerte = (root.textContent.match(/\d+ tentative\(s\) de connexion refusée\(s\)/) || [null])[0];
        const tab = [...root.querySelectorAll('button')].find((b) => b.textContent.trim().startsWith('Tentatives refusées')); tab.click(); await dormir(40);
        const lignes = [...root.querySelectorAll('tbody tr')].map((tr) => tr.textContent.replace(/\s+/g, ' ').trim());
        const ligne = [...root.querySelectorAll('tbody tr')].find((tr) => tr.textContent.includes('Test Deux'));
        const b = [...ligne.querySelectorAll('button')].find((x) => (x.title || x.getAttribute('aria-label') || '') === 'Marquer comme examinée');
        const nbToasts = toasts.length;
        b.click(); await dormir(60);
        const fiche = colT.all().find((x) => x.nom === 'Test Deux');
        rolesCas.push({ nom: 'tentatives refusées : affichage puis marquage', type: 'tentatives', kpis, alerte, lignes, apres: { traitee: fiche.traitee, examineePar: fiche.examineePar, examineeLe: fiche.examineeLe }, jour: C.iso(C.aujourdhui()), toasts: toasts.slice(nbToasts) });
        nettoyer();
      }

      /* ----- 3. Le journal d'audit : un journal fabriqué, l'horloge figée ----- */
      const auditCas = [];
      {
        const sauve = S.raw().audit; const dateNow = Date.now; const T0 = new Date('2026-10-30T10:00:00Z').getTime();
        Date.now = () => T0;
        const e = (i, dh, u, a, mo, en, ref, po, succes, av, ap) => Object.assign({ id: 'LOGT' + i, dateHeure: new Date(T0 - dh * 1000).toISOString(), utilisateur: u, action: a, module: mo, entite: en, reference: ref, poste: po }, succes === undefined ? {} : { succes }, av ? { ancienneValeur: av } : {}, ap ? { nouvelleValeur: ap } : {});
        const journal = [
          e(1, 30, 'KASSA Augustin', 'Création', 'M8', 'facture', 'FN-2026-00001', 'POSTE-CAISSE', true, null, '{"id":"F1","montant":5000}'),
          e(2, 300, 'TAKI Alimatou', 'Modification', 'M12', 'écriture', 'OD-2026-00004', 'POSTE-DAF', true, '{"statut":"brouillon"}', '{"statut":"validee"}'),
          e(3, 3 * 3600, 'KASSA Augustin', 'Archivage', 'M8', 'facture', 'FN-2026-00002', 'POSTE-CAISSE', true),
          e(4, 2 * 86400, 'OROU YO Edmond', 'Connexion', 'M14', 'session', 'v.test', 'POSTE-ACCUEIL', false),
          e(5, 29 * 86400, 'BASSONGUI Chabi Séko', 'Validation', 'M5', 'résultat', 'LAB-00012', 'POSTE-LABO', true),
          e(6, 40 * 86400, 'TAKI Alimatou', 'Impression', 'M8', 'facture', 'FN-2026-00003', null, undefined),
          e(7, 59, 'GARBA Yahouza', 'Restauration', 'M2', 'rendez-vous', 'RDV-00007', 'POSTE-SOINS', true, null, 'texte non JSON'),
          e(8, 3599, 'GARBA Yahouza', 'Suppression', 'M2', 'rendez-vous', null, 'POSTE-SOINS', true),
        ];
        S.raw().audit = journal;
        const root = montrer('m14-audit'); await dormir(60);
        const t = tableau(root);
        const cas0 = { nom: 'journal fabriqué', entrees: propre(journal), kpis: kpis(root), tableau: t,
          textes: [...root.querySelectorAll('p')].map((p) => p.textContent.replace(/\s+/g, ' ').trim()).filter((x) => /tentative|cinq ans|infructueuse/.test(x)),
          filtres: [...root.querySelectorAll('select')].map((s) => ({ nom: (s.previousElementSibling || {}).textContent || s.getAttribute('aria-label') || '', options: [...s.options].map((o) => o.textContent.trim()) })) };
        /* tiroir de la 2e ligne affichée (tri par date décroissante) */
        const lignes = [...root.querySelectorAll('tbody tr')];
        lignes.find((tr) => tr.textContent.includes('OD-2026-00004')).click(); await dormir(60);
        cas0.tiroirModifie = (document.querySelector('.drawer-root, [role=dialog]') || { textContent: '' }).textContent.replace(/\s+/g, ' ').trim();
        nettoyer();
        lignes.find((tr) => tr.textContent.includes('RDV-00007')).click(); await dormir(60);
        cas0.tiroirNonJson = (document.querySelector('.drawer-root, [role=dialog]') || { textContent: '' }).textContent.replace(/\s+/g, ' ').trim();
        nettoyer();
        lignes.find((tr) => tr.textContent.includes('FN-2026-00002')).click(); await dormir(60);
        cas0.tiroirSansValeur = (document.querySelector('.drawer-root, [role=dialog]') || { textContent: '' }).textContent.replace(/\s+/g, ' ').trim();
        nettoyer();
        bouton('Imprimer le journal', root).click(); await dormir(40);
        cas0.impression = imprime[imprime.length - 1];
        auditCas.push(cas0);
        /* sans aucun échec */
        S.raw().audit = journal.filter((x) => x.succes !== false);
        const r2 = montrer('m14-audit'); await dormir(40);
        auditCas.push({ nom: 'sans tentative infructueuse', kpis: kpis(r2), note: [...r2.querySelectorAll('p')].some((p) => /tentative\(s\) d’accès/.test(p.textContent)) });
        S.raw().audit = []; const r3 = montrer('m14-audit'); await dormir(40);
        auditCas.push({ nom: 'journal vide', kpis: kpis(r3), vide: r3.textContent.replace(/\s+/g, ' ').slice(0, 400) });
        S.raw().audit = sauve; Date.now = dateNow; nettoyer();
      }

      /* ----- 4. Les sauvegardes ----- */
      const sauvegardes = {};
      {
        const root = montrer('m14-sauvegardes'); await dormir(60);
        sauvegardes.kpis = kpis(root);
        sauvegardes.fichiers = tableau(root, 0);
        sauvegardes.historique = tableau(root, 1);
        sauvegardes.notes = [...root.querySelectorAll('p')].map((p) => p.textContent.replace(/\s+/g, ' ').trim()).filter((x) => /sauvegarde\(s\) en échec|hebdomadaire est automatique/.test(x));
        sauvegardes.fichiersSemes = propre(S.collection('fichiersSauvegarde').all());
        sauvegardes.jour = C.iso(C.aujourdhui());
        sauvegardes.nbTables = Object.keys(S.raw()).filter((k) => k.charAt(0) !== '_' && Array.isArray(S.raw()[k])).length;
        const nb = toasts.length; const nbF = S.collection('fichiersSauvegarde').all().length;
        bouton('Générer une sauvegarde', root).click(); await dormir(80);
        const nouv = S.collection('fichiersSauvegarde').all()[0];
        sauvegardes.generation = { fiche: net(nouv), nbFichiers: S.collection('fichiersSauvegarde').all().length - nbF, toasts: toasts.slice(nb).map((x) => ({ message: x.message, detail: x.detail })) };
        const confirmer = async (declencheur, libelleConf, motif) => {
          const nbT = toasts.length; const nbAudit = (S.raw().audit || []).length;
          declencheur.click(); await dormir(50);
          const message = (document.querySelector('.modal-root, [role=dialog]') || { textContent: '' }).textContent.replace(/\s+/g, ' ').trim();
          if (motif) { const ch = document.querySelector('.modal-root textarea, [role=dialog] textarea, .modal-root input[type=text], [role=dialog] input[type=text]'); if (ch) { ch.value = motif; ch.dispatchEvent(new Event('input')); } }
          [...document.querySelectorAll('.modal-root button, [role=dialog] button')].find((b) => b.textContent.trim() === libelleConf).click(); await dormir(80);
          const a = S.raw().audit || [];
          return { message, toasts: toasts.slice(nbT).map((x) => ({ message: x.message, detail: x.detail })), audit: a.length > nbAudit ? net(a[0]) : null };
        };
        sauvegardes.manuelle = await confirmer(bouton('Lancer une sauvegarde manuelle', root), 'Lancer la sauvegarde');
        sauvegardes.testRestauration = await confirmer(bouton('Tester une restauration', root), 'Lancer le test');
        sauvegardes.restauration = await confirmer(bouton('Restaurer', root), 'Restaurer', 'Test de restauration');
        sauvegardes.lignesRestaurables = tableau(root, 1).lignes.filter((l) => l[l.length - 1].includes('Restaurer')).length;
        sauvegardes.lignesSansRestaurer = tableau(root, 1).lignes.filter((l) => !l[l.length - 1].includes('Restaurer')).length;
        bouton('Exporter le journal des sauvegardes', root).click(); await dormir(40);
        sauvegardes.impression = imprime[imprime.length - 1];
        nettoyer();
      }

      /* ----- 5. Prescripteurs & exécutants de soins ----- */
      const soignants = {};
      {
        const colS = S.collection('soignants');
        const root = montrer('m14-soignants'); await dormir(60);
        soignants.kpis = kpis(root);
        soignants.onglets = [...root.querySelectorAll('button')].map((b) => b.textContent.trim()).filter((x) => /^(Tous|Prescripteurs|Exécutants)\d/.test(x));
        soignants.tableau = tableau(root);
        soignants.qualites = propre(D.QUALITES_SOIGNANT);
        soignants.secteurs = propre(D.SECTEURS_SOINS);
        soignants.dejaPresents = colS.active().length;
        const personnelLibre = S.collection('personnel').active().find((p) => !colS.all().some((s) => s.personnelId === p.id));
        const tout = async (nom, saisie) => {
          const r = montrer('m14-soignants'); await dormir(40);
          const nb = toasts.length; const avant = new Set(colS.all().map((x) => x.id));
          bouton('Nouveau soignant', r).click(); await dormir(50);
          Object.entries(saisie).forEach(([k, v]) => poser(k, v));
          bouton('Créer').click(); await dormir(60);
          const n = colS.all().filter((x) => !avant.has(x.id)).map(net);
          soignants[nom] = { saisie, creees: n, toasts: toasts.slice(nb).map((x) => ({ message: x.message, detail: x.detail })), kpis: kpis(montrer('m14-soignants')) };
          nettoyer();
        };
        await tout('infirmierSecteurs', { personnelId: personnelLibre.id, qualite: 'infirmier', prescrit: false, execute: true, supervise: false, secteurs: ['salle_soins', 'maternite'] });
        await tout('sageFemme', { personnelId: personnelLibre.id, qualite: 'sage_femme', prescrit: true, execute: true, supervise: true, secteurs: ['maternite'] });
        await tout('sansSecteur', { personnelId: personnelLibre.id, qualite: 'medecin', prescrit: true, execute: false, supervise: false, secteurs: [] });
        soignants.agentLibre = { id: personnelLibre.id, nomComplet: personnelLibre.nomComplet, poste: personnelLibre.poste, fonction: personnelLibre.fonction };
        /* détail d'une ligne et modification */
        const r = montrer('m14-soignants'); await dormir(40);
        const ligne = [...r.querySelectorAll('tbody tr')].find((tr) => tr.textContent.includes('BASSONGUI'));
        [...ligne.querySelectorAll('button')].find((b) => (b.title || b.getAttribute('aria-label') || '') === 'Consulter').click(); await dormir(60);
        soignants.detail = (document.querySelector('.drawer-root, [role=dialog]') || { textContent: '' }).textContent.replace(/\s+/g, ' ').trim();
        nettoyer();
        const nbE = toasts.length;
        const cible = colS.all().find((s) => s.nomComplet.includes('BASSONGUI'));
        [...ligne.querySelectorAll('button')].find((b) => (b.title || b.getAttribute('aria-label') || '') === 'Modifier').click(); await dormir(60);
        poser('execute', true); poser('secteurs', ['hospitalisation']);
        bouton('Enregistrer').click(); await dormir(60);
        soignants.edition = { apres: net(colS.get(cible.id)), toasts: toasts.slice(nbE).map((x) => ({ message: x.message, detail: x.detail })) };
        nettoyer();
      }

      /* ----- 6. Les tâches planifiées : le serveur est remplacé par des réponses fabriquées ----- */
      const tachesCas = [];
      {
        const fetchOrig = window.fetch; const dateNow = Date.now; const T0 = new Date('2026-10-30T10:00:00Z').getTime();
        Date.now = () => T0;
        const jeux = {
          'à jour, tout réussi': { taches: [
            { code: 'a', libelle: 'Tâche A', frequence_min: 60, derniere_le: '2026-10-30 09:30:00', dernier_statut: 'ok', dernier_message: '', duree_ms: 12, alertes: 3 },
            { code: 'b', libelle: 'Tâche B', frequence_min: 30, derniere_le: '2026-10-30 09:50:00.123456', dernier_statut: 'ok', dernier_message: '', duree_ms: null, alertes: 0 } ],
            executions: [{ id: 2, code: 'a', debut: '2026-10-30 09:30:00.5', statut: 'ok', message: '', duree_ms: 12, alertes: 3, origine: 'cron' }, { id: 1, code: 'b', debut: '2026-10-30 09:50:00', statut: 'erreur', message: 'x', duree_ms: 3, alertes: 0, origine: null }] },
          'en retard, jamais exécutée, en erreur': { taches: [
            { code: 'a', libelle: 'Tâche A', frequence_min: 60, derniere_le: '2026-10-30 06:59:59', dernier_statut: 'ok', dernier_message: '', duree_ms: 5, alertes: 2 },
            { code: 'b', libelle: 'Tâche B', frequence_min: 60, derniere_le: '2026-10-30 07:00:00', dernier_statut: 'erreur', dernier_message: 'PDO indisponible', duree_ms: 7, alertes: 1 },
            { code: 'c', libelle: 'Tâche C', frequence_min: 1440, derniere_le: null, dernier_statut: null, dernier_message: '', duree_ms: null, alertes: null } ], executions: [] },
          'registre vide': { taches: [], executions: [] },
        };
        for (const [nom, rep] of Object.entries(jeux)) {
          window.fetch = (url, opts) => Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(rep) });
          const root = montrer('m14-taches'); await dormir(120);
          const note = [...root.querySelectorAll('p')].map((p) => p.textContent.replace(/\s+/g, ' ').trim()).find((x) => /n’ont pas tourné/.test(x)) || null;
          const nbTab = root.querySelectorAll('table').length;
          tachesCas.push({ nom, reponse: rep, kpis: kpis(root), note, tableaux: Array.from({ length: nbTab }, (_, i) => tableau(root, i)), vide: root.textContent.includes('Aucune exécution enregistrée.') });
          nettoyer();
        }
        window.fetch = () => Promise.reject(new Error('Failed to fetch'));
        const rE = montrer('m14-taches'); await dormir(120);
        tachesCas.push({ nom: 'serveur injoignable', texte: rE.textContent.replace(/\s+/g, ' ').trim().slice(0, 600) });
        nettoyer();
        window.fetch = fetchOrig; Date.now = dateNow;
      }

      rolesCas.forEach((c) => { if (c.avant && c.apres && typeof c.avant.matriceAutres === "string") { c.autresIdentiques = c.avant.matriceAutres === c.apres.matriceAutres; delete c.avant.matriceAutres; delete c.apres.matriceAutres; } });
      return { comptes: cas, roles: rolesCas, modules, nbRoles: Object.keys(N.ROLES).length, sessions, sessionsCloture, rolesOuverture, audit: auditCas, sauvegardes, soignants, taches: tachesCas, services: propre(D.SERVICES), capacites: propre(D.CAPACITES), naturesPrescription: propre(D.NATURES_PRESCRIPTION) };
    });
    sortie.comptes.forEach((c) => console.log('  compte · ' + c.nom + ' → ' + (c.creee ? c.creee.length : '?') + ' créé(s) ' + JSON.stringify((c.toasts || []).slice(-1))));
    sortie.roles.forEach((c) => console.log('  rôle · ' + c.nom + ' → ' + JSON.stringify((c.toasts || []).slice(-1).map((t) => t.message))));
    /* Les référentiels que l'écran lit (D.CAPACITES, D.NATURES_PRESCRIPTION, D.QUALITES_SOIGNANT) → Dart, et seulement eux : le reste vient des fiches. */
    const donnees = { capacites: sortie.capacites, naturesPrescription: sortie.naturesPrescription, qualites: sortie.soignants.qualites };
    ecrire('packages/domaine/lib/src/securite/sec_donnees.dart', [
      '// ENGENDRÉ par prototype_html/build/vecteurs-securite.js — référentiels lus par les écrans de M14 (D.CAPACITES, D.NATURES_PRESCRIPTION, D.QUALITES_SOIGNANT).',
      '// Ne pas éditer à la main : relancer le script.',
      '// ignore_for_file: prefer_single_quotes',
      'library;',
      '',
      'const Map<String, Object?> secDonnees = ' + litteralDart(donnees, 0) + ';',
      '',
    ].join('\n'));
    delete sortie.capacites; delete sortie.naturesPrescription;
    ecrire('packages/domaine/test/vecteurs/securite.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-securite.js — les écrans de M14 pilotés. Ne pas éditer.' }, sortie));
    if (m.erreurs.length) console.log('  erreurs de page : ' + m.erreurs.slice(0, 5).join(' | '));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
