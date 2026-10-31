/* =============================================================================
 * VECTEURS DES ACHATS (M7) — les écrans réels de m7-achats.js PILOTÉS comme le fait l'agent
 * -----------------------------------------------------------------------------
 * Cinq écrans : m7-besoins (quatre vues sur une collection, arbitrage de la DAF, saisie), m7-commandes (RG-04), m7-livraisons, m7-receptions
 * (entrée en stock gros, CUMP, écarts), m7-ecarts. Le script monte chaque écran dans la page d'extraction, change de profil, clique, remplit les
 * formulaires et relit ce qui est né au magasin — les fonctions de rendu et de gestes vivent dans la fermeture de l'écran, on ne peut pas les
 * appeler seules.
 *   node build/vecteurs-achats.js   →   packages/domaine/test/vecteurs/achats-{besoins,commandes,reception}.json
 *
 * Deux aménagements du banc, qui ne changent rien au calcul : `app.go` est remplacé par un enregistreur (la page d'extraction n'a pas de routeur),
 * et `location.reload()` — appelé par la création d'un bon de livraison — par un compteur (recharger détruirait le contexte du banc).
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs des achats (M7)');
  const m = await ouvrirMaquette();
  try {
    const source = fs.readFileSync(path.join(ROOT, 'assets/js/modules/m7-achats.js'), 'utf8')
      .replace('global.location.reload();', 'window.__rechargements = (window.__rechargements || 0) + 1;');
    await m.page.addScriptTag({ content: source });
    const sortie = await m.page.evaluate(async () => {
      const S = SIGH.store, C = SIGH.core, U = SIGH.ui;
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const propre = (x) => JSON.parse(JSON.stringify(x));
      const net = (x) => { const c = propre(x); ['_creePar', '_creeLe', '_modifiePar', '_modifieLe', 'arbitreLe', 'prepareLe', 'distribueLe'].forEach((k) => { if (typeof c[k] === 'string' || c[k] === undefined) delete c[k]; }); return c; };
      const J = {};   /* sorties */
      J.jour = C.iso(C.aujourdhui());
      J.produits = JSON.parse(JSON.stringify(S.collection('produits').active().slice(0, 3)));

      /* --- Espions : les messages (U.toast) et la navigation (app.go) ------------------------------------------------------------------------ */
      const toasts = []; const allers = [];
      const toastOrigine = U.toast;
      U.toast = function (message, opts) { toasts.push({ message: String(message), type: (opts && opts.type) || 'info', detail: (opts && opts.detail) || null, undo: opts && opts.undo }); return toastOrigine.apply(this, arguments); };
      SIGH.app.go = function (id) { allers.push(id); };
      const toastsDepuis = (n) => toasts.slice(n).map((t) => ({ message: t.message, type: t.type, detail: t.detail }));

      const poserProfil = (role, nom) => {
        const s = JSON.parse(localStorage.getItem('sigh-cnt:session'));
        localStorage.setItem('sigh-cnt:session', JSON.stringify(Object.assign({}, s, { role, nom })));
      };
      const profilBanc = JSON.parse(localStorage.getItem('sigh-cnt:session'));
      /* Le banc n'a pas de page courante : on rejoue à l'identique la résolution de droits de app.js (droitsCourants) pour l'écran monté. */
      let ecranCourant = null;
      SIGH.app.droits = (code) => { const session = S.session() || {}; const e = ecranCourant ? SIGH.nav.get(ecranCourant) : null; const c = code || (e ? e.module : null);
        return SIGH.nav.droitsEcran(session.role, SIGH.nav.ecranDesDroits(e), c); };
      const monter = async (ecran) => { ecranCourant = ecran; const root = document.createElement('div'); document.body.appendChild(root); SIGH.screens[ecran].render(root); await dormir(80); return root; };
      const nettoyer = (root) => { document.querySelectorAll('.drawer-backdrop').forEach((e) => e.remove()); if (root) root.remove(); };
      const fenetre = () => { const l = [...document.querySelectorAll('.drawer-backdrop')]; return l[l.length - 1] || null; };
      const bouton = (cont, texte) => [...cont.querySelectorAll('button')].find((b) => b.textContent.trim() === texte);
      const titreBouton = (b) => b.getAttribute('title') || b.getAttribute('aria-label') || b.textContent.trim();
      const saisir = (el, v) => { el.value = v; el.dispatchEvent(new Event('input', { bubbles: true })); el.dispatchEvent(new Event('change', { bubbles: true })); };
      const poserChamp = (id, v) => { const e = document.getElementById('f_' + id); if (!e) throw new Error('champ ' + id); saisir(e, v); };
      const ligneDe = (root, ref) => [...root.querySelectorAll('tbody tr')].find((tr) => tr.children[0] && tr.children[0].textContent.trim() === ref);
      const onglet = async (root, debut) => { const t = [...root.querySelectorAll('[role=tab]')].find((x) => x.textContent.trim().startsWith(debut)); if (!t) throw new Error('onglet ' + debut); t.click(); await dormir(60); };
      const kpis = (root) => [...root.querySelector('.grid').children].map((k) => [...k.querySelectorAll('p')].slice(0, 2).map((p) => p.textContent.trim()));
      const refsPage = (root) => [...root.querySelectorAll('tbody tr')].map((tr) => tr.children[0].textContent.trim());
      const confirmer = async (libelle) => { await dormir(40); const f = fenetre(); const b = bouton(f, libelle); if (!b) throw new Error('confirmation ' + libelle); b.click(); await dormir(60); };
      /* L'amorçage des achats se fait à l'OUVERTURE de l'écran (amorcer() de m7) : on monte l'écran une fois AVANT d'injecter quoi que ce soit, sinon les bons
         injectés précèdent le jeu et l'instantané des bons est incomplet. */
      nettoyer(await monter('m7-besoins'));
      const colB = S.collection('besoins'), colC = S.collection('commandes'), colL = S.collection('livraisons'), colP = S.collection('produits'), colMv = S.collection('mouvements'), colN = S.collection('notifications');
      const ids = (col) => new Set(col.all().map((x) => x.id));
      const nouveaux = (col, avant) => col.all().filter((x) => !avant.has(x.id));
      const ligne = (pid, dem, acc, extra) => { const p = colP.get(pid); return Object.assign({ produitId: pid, produit: p.designation, unite: p.unite, quantiteDemandee: dem, quantiteAccordee: acc === undefined ? null : acc, quantiteLivree: null, prixAchat: p.prixAchat }, extra || {}); };
      const articles = colP.active().slice(0, 3).map((p) => p.id);   /* ABAISSE LANGUE, … : les mêmes que ceux du jeu du poste */

      /* ======================================================================================================================================
       * 1. LES QUATRE VUES D'UNE COLLECTION
       * ==================================================================================================================================== */
      const pose = (extra) => colB.insert(Object.assign({ reference: 'BEB-2099-0001', date: '2099-01-01', service: 'Accueil', demandeur: 'GARBA Yahouza', etape: 'soumis', motif: 'Vecteur', lignes: [ligne(articles[0], 10, null)], montantEstime: 6500 }, extra)).record;
      pose({ reference: 'BEB-2099-0001', etape: 'soumis', lignes: [ligne(articles[0], 10, null)] });
      pose({ reference: 'BEB-2099-0002', etape: 'livre', demandeur: 'BASSONGUI Chabi Séko', date: '2099-01-02', lignes: [ligne(articles[1], 4, 3, { quantiteLivree: 3 })], montantEstime: 4 * colP.get(articles[1]).prixAchat });
      pose({ reference: 'BEB-2099-0003', etape: 'rejete', date: '2099-01-03', lignes: [ligne(articles[2], 2, null)], montantEstime: 2 * colP.get(articles[2]).prixAchat });
      pose({ reference: 'BEB-2099-0004', etape: 'complement', date: '2099-01-04', demandeur: 'BASSONGUI Chabi Séko', lignes: [ligne(articles[2], 1, null)], montantEstime: colP.get(articles[2]).prixAchat });
      pose({ reference: 'BEB-2099-0005', etape: 'distribue', date: '2099-01-05' });
      const bons = propre(colB.active().map(net));
      const roles = [['admin', 'GARBA Yahouza'], ['admin', 'BASSONGUI Chabi Séko'], ['da', 'GARBA Yahouza'], ['direction', 'GARBA Yahouza'], ['stock', 'GARBA Yahouza'],
        ['comptable', 'GARBA Yahouza'], ['aide_comptable', 'GARBA Yahouza'], ['laborantin', 'GARBA Yahouza'], ['medecin', 'GARBA Yahouza'], ['caissier', 'GARBA Yahouza']];
      const vues = [];
      for (const [role, nom] of roles) {
        poserProfil(role, nom);
        const root = await monter('m7-besoins');
        const onglets = [...root.querySelectorAll('[role=tab]')].map((t) => { const x = /^(.*?)(\d+)$/.exec(t.textContent.trim()); return { libelle: x ? x[1] : t.textContent.trim(), badge: x ? Number(x[2]) : null }; });
        const circuit = [...root.querySelectorAll('span.inline-flex.rounded-lg')].map((s) => { const sp = s.querySelectorAll('span'); return [sp[0].textContent.trim(), Number(sp[1].textContent)]; });
        const cas = { role, nom, onglets, kpis: kpis(root), circuit, vues: {} };
        for (const o of onglets) {
          await onglet(root, o.libelle);
          const tr = root.querySelector('tbody tr');
          cas.vues[o.libelle] = { refs: refsPage(root), nouveauBon: !!bouton(root, 'Nouveau bon'), actionsPremiereLigne: tr ? [...tr.querySelectorAll('button')].map(titreBouton) : [] };
        }
        nettoyer(root); vues.push(cas);
      }
      poserProfil(profilBanc.role, profilBanc.nom);
      J.vues = { _doc: 'Les quatre vues de m7-besoins par profil : onglets visibles (avec leur compte), KPI, ruban du circuit, première page de chaque onglet (tri date décroissant) et commandes de la première ligne.', bons, cas: vues };

      /* ======================================================================================================================================
       * 2. L'ARBITRAGE DE LA DAF — trois réponses, deux exigent leur motif
       * ==================================================================================================================================== */
      const arbitrages = [];
      let rang = 100;
      async function arbitrer(nom, etape, quoi, motif) {
        poserProfil('da', 'TAKI Alimatou');
        rang++;
        const bon = colB.insert({ reference: 'BEB-2098-' + String(rang).padStart(4, '0'), date: '2098-01-01', service: 'Maternité', demandeur: 'GARBA Yahouza', etape, motif: 'Dotation',
          lignes: [ligne(articles[0], 10, 8), ligne(articles[1], 5, null)], montantEstime: 10 * colP.get(articles[0]).prixAchat + 5 * colP.get(articles[1]).prixAchat }).record;
        const avant = propre(net(colB.get(bon.id)));
        const avantN = ids(colN), nT = toasts.length, nA = allers.length;
        const root = await monter('m7-besoins');
        await onglet(root, 'Arbitrage');
        const tr = ligneDe(root, bon.reference);
        const titre = { valider: 'Valider le besoin', rejeter: 'Rejeter avec motif', complement: 'Demander un complément' }[quoi];
        const b = [...tr.querySelectorAll('button')].find((x) => titreBouton(x) === titre);
        b.click(); await dormir(60);
        const f = fenetre();
        const entete = f.querySelector('h2, h3') ? f.querySelector('h2, h3').textContent.trim() : '';
        const libelleMotif = [...f.querySelectorAll('label')].map((l) => l.textContent.trim());
        if (motif) poserChamp('motif', motif);
        const libelle = { valider: 'Valider et informer', rejeter: 'Rejeter', complement: 'Demander' }[quoi];
        bouton(f, libelle).click(); await dormir(80);
        const resteOuverte = !!fenetre();
        const apres = propre(net(colB.get(bon.id)));
        const notifs = nouveaux(colN, avantN).map((n) => propre({ type: n.type, poste: n.poste, libelle: n.libelle, detail: n.detail, priorite: n.priorite, reference: n.reference }));
        arbitrages.push({ nom, quoi, motif, entete, libelles: libelleMotif, avant, apres, notifications: notifs, resteOuverte, toasts: toastsDepuis(nT), rafraichi: allers.slice(nA)[0] || null });
        nettoyer(root);
      }
      await arbitrer('valider sans observation', 'validation_da', 'valider', '');
      await arbitrer('valider avec observation', 'soumis', 'valider', 'Budget disponible');
      await arbitrer('rejeter avec motif', 'validation_da', 'rejeter', 'Déjà en stock');
      await arbitrer('rejeter SANS motif : refusé, rien n\'est écrit', 'validation_da', 'rejeter', '');
      await arbitrer('complément avec motif', 'controle_stock', 'complement', 'Préciser la marque');
      await arbitrer('complément SANS motif : refusé', 'soumis', 'complement', '');
      poserProfil(profilBanc.role, profilBanc.nom);

      /* ======================================================================================================================================
       * 3. LES GESTES DE L'ACHAT : transformer en commande, marquer distribué
       * ==================================================================================================================================== */
      const achats = [];
      for (const [quoi, titre, ok] of [['versCommande', 'Transformer en bon de commande', 'Ouvrir les commandes'], ['distribuer', 'Marquer distribué au service', 'Distribuer']]) {
        poserProfil('stock', 'MAMAN Zoukanéri');
        rang++;
        const bon = colB.insert({ reference: 'BEB-2097-' + String(rang).padStart(4, '0'), date: '2097-01-01', service: 'Laboratoire', demandeur: 'GARBA Yahouza', etape: 'accorde', motif: 'Réactifs',
          lignes: [ligne(articles[0], 6, 6)], montantEstime: 6 * colP.get(articles[0]).prixAchat }).record;
        const nA = allers.length, nT = toasts.length;
        const root = await monter('m7-besoins');
        await onglet(root, 'Besoins validés');
        const tr = ligneDe(root, bon.reference);
        [...tr.querySelectorAll('button')].find((x) => titreBouton(x) === titre).click();
        await dormir(60);
        const f = fenetre(); const message = f.textContent.replace(/\s+/g, ' ').trim();
        await confirmer(ok);
        achats.push({ quoi, avant: propre(net(Object.assign({}, bon, { etape: 'accorde' }))), apres: propre(net(colB.get(bon.id))), allers: allers.slice(nA), toasts: toastsDepuis(nT), message });
        nettoyer(root);
      }
      poserProfil(profilBanc.role, profilBanc.nom);
      J.arbitrage = { _doc: 'L\'arbitrage de la DAF (valider / rejeter / complément) et les gestes de l\'achat, pilotés dans l\'onglet de leur vue.', arbitrages, achats };

      /* ======================================================================================================================================
       * 4. LA SAISIE D'UN BON : le formulaire s'adapte à qui l'ouvre
       * ==================================================================================================================================== */
      const saisies = [];
      async function nouveauBon(nom, role, cfg) {
        poserProfil(role, cfg.nom || 'GARBA Yahouza');
        const avant = ids(colB), nT = toasts.length;
        const root = await monter('m7-besoins');
        bouton(root, 'Nouveau bon').click(); await dormir(80);
        const f = fenetre();
        const champs = [...f.querySelectorAll('[id^=f_]')].map((e) => e.id.slice(2));
        const defauts = {}; champs.forEach((c) => { const e = document.getElementById('f_' + c); defauts[c] = e.type === 'checkbox' ? e.checked : e.value; });
        const optionsEtape = document.getElementById('f_etape') ? [...document.getElementById('f_etape').options].map((o) => o.value) : null;
        const ajout = [...f.querySelectorAll('div')].find((d) => d.className.includes('items-end') && d.className.includes('gap-2'));
        const combo = ajout.children[0].lastElementChild; const nums = ajout.querySelectorAll('input[type=number]');
        for (const l of cfg.lignes || []) {
          combo.value = l.produitId; saisir(nums[0], String(l.dem)); saisir(nums[1], l.acc == null ? '' : String(l.acc));
          bouton(ajout, 'Ajouter').click(); await dormir(40);
        }
        const lignesAffichees = [...f.querySelectorAll('tbody tr')].length;
        Object.entries(cfg.champs || {}).forEach(([k, v]) => { const e = document.getElementById('f_' + k); if (e.type === 'checkbox') { e.checked = v; e.dispatchEvent(new Event('change', { bubbles: true })); } else saisir(e, v); });
        bouton(f, 'Créer le bon').click(); await dormir(100);
        const cree = nouveaux(colB, avant)[0];
        saisies.push({ nom, role, cfg: { champs: cfg.champs || {}, lignes: cfg.lignes || [] }, champs, defauts, optionsEtape, lignesAffichees, bon: cree ? propre(net(cree)) : null, ouverte: !!fenetre(), toasts: toastsDepuis(nT), demandeur: cfg.nom || 'GARBA Yahouza' });
        nettoyer(root);
      }
      const L1 = { produitId: articles[0], dem: 10, acc: null }, L2 = { produitId: articles[1], dem: 4, acc: 3 };
      await nouveauBon('gestionnaire de stock : choisit l\'étape (brouillon par défaut)', 'stock', { lignes: [L1], champs: { service: 'Laboratoire', categorie: 'Consommables médicaux', motif: 'Rupture' } });
      await nouveauBon('médecin : pas d\'étape à choisir, le bon part SOUMIS', 'medecin', { lignes: [L1, L2], champs: { service: 'Hospitalisation', categorie: 'Consommables médicaux', urgent: true, motif: 'Urgence' } });
      await nouveauBon('comptable : pilote le circuit comme le stock (brouillon par défaut)', 'comptable', { lignes: [L2], champs: { service: 'Administration', categorie: 'Autre — à préciser' } });
      await nouveauBon('stock choisit « Validation DA » : le validateur est posé d\'office', 'stock', { lignes: [L1], champs: { service: 'Maternité', categorie: 'Consommables médicaux', etape: 'validation_da' } });
      await nouveauBon('stock choisit « Quantité accordée » (écart signalé E73 : la DAF est portée validatrice)', 'stock', { lignes: [L2], champs: { service: 'Maternité', categorie: 'Consommables médicaux', etape: 'accorde' } });
      await nouveauBon('SANS ligne : refusé', 'medecin', { lignes: [], champs: { service: 'Accueil', categorie: 'Autre — à préciser' } });
      await nouveauBon('quantité accordée > demandée : la ligne est refusée', 'medecin', { lignes: [{ produitId: articles[0], dem: 5, acc: 9 }], champs: { service: 'Accueil', categorie: 'Autre — à préciser' } });
      await nouveauBon('quantité demandée nulle : la ligne est refusée', 'medecin', { lignes: [{ produitId: articles[0], dem: 0, acc: null }], champs: { service: 'Accueil', categorie: 'Autre — à préciser' } });
      poserProfil(profilBanc.role, profilBanc.nom);
      const modifsBon = [];
      async function modifierBon(nom, depart, champs) {
        poserProfil('stock', 'MAMAN Zoukanéri'); rang++;
        const b = colB.insert(Object.assign({ reference: 'BEB-2095-' + String(rang).padStart(4, '0'), date: '2099-12-31', service: 'Accueil', demandeur: 'GARBA Yahouza', etape: 'soumis', categorie: 'Autre — à préciser', motif: 'Départ',
          lignes: [ligne(articles[0], 10, null)], montantEstime: 6500 }, depart)).record;
        const avant = propre(net(b)), nT = toasts.length;
        const root = await monter('m7-besoins');
        await onglet(root, 'Tous les bons');
        const tr = ligneDe(root, b.reference);
        [...tr.querySelectorAll('button')].find((x) => titreBouton(x) === 'Modifier').click(); await dormir(80);
        const fe = fenetre();
        const defauts = {}; [...fe.querySelectorAll('[id^=f_]')].forEach((e) => { defauts[e.id.slice(2)] = e.type === 'checkbox' ? e.checked : e.value; });
        Object.entries(champs).forEach(([k, v]) => poserChamp(k, v));
        bouton(fe, 'Enregistrer').click(); await dormir(100);
        modifsBon.push({ nom, avant, defauts, champs, apres: propre(net(colB.get(b.id))), toasts: toastsDepuis(nT) });
        nettoyer(root);
      }
      await modifierBon('étape portée à « Validation DA » : le validateur est posé (E73)', {}, { etape: 'validation_da' });
      await modifierBon('étape portée à « Validation DA », validateur déjà connu : conservé', { valideePar: 'AUTRE Personne' }, { etape: 'validation_da' });
      await modifierBon('étape ramenée à « Brouillon » : rien de posé', { etape: 'soumis' }, { etape: 'brouillon', motif: 'Revu' });
      poserProfil(profilBanc.role, profilBanc.nom);
      J.modifsBon = modifsBon;
      /* référence : DEUX créations de suite doivent donner deux numéros distincts, à la suite de la série existante (E70) */
      const nBons = colB.all().filter((b) => /^BEB-2026-/.test(b.reference)).map((b) => b.reference).sort();
      J.saisie = { _doc: 'La saisie d\'un bon par profil (champs offerts, défauts, résultat enregistré) et les refus de ligne.', saisies, serie2026: nBons };

      /* ======================================================================================================================================
       * 5. LES COMMANDES — RG-04
       * ==================================================================================================================================== */
      const cmdLigne = (pid, q, pu) => { const p = colP.get(pid) || { designation: 'ARTICLE HORS RÉFÉRENTIEL', unite: 'Unité' }; return { produitId: pid, produit: p.designation, unite: p.unite, quantite: q, prixUnitaire: pu, montant: q * pu }; };
      const commandes = { validations: [], creations: [], gardes: [] };
      async function validerCommande(role) {
        poserProfil(role, 'TAKI Alimatou');
        rang++;
        const c = colC.insert({ reference: 'BC-2098-' + String(rang).padStart(4, '0'), date: '2098-02-01', fournisseur: 'CAME', fournisseurNom: 'CAME — Centrale d\'Achat des Médicaments Essentiels', lignes: [cmdLigne(articles[0], 10, 650)], montant: 6500, statutCommande: 'attente_validation', delaiLivraison: 7 }).record;
        const avant = propre(net(c)); const nT = toasts.length;
        const root = await monter('m7-commandes');
        const tr = ligneDe(root, c.reference);
        const actions = [...tr.querySelectorAll('button')].map(titreBouton);
        const note = root.querySelector('.note, [class*=warning]') ? true : false;
        const kp = kpis(root);
        const b = [...tr.querySelectorAll('button')].find((x) => titreBouton(x) === 'Valider (DA)');
        let apres = null, message = null;
        if (b) { b.click(); await dormir(60); message = fenetre().textContent.replace(/\s+/g, ' ').trim(); await confirmer('Valider la commande'); apres = propre(net(colC.get(c.id))); }
        commandes.validations.push({ role, actions, avant, apres, message, toasts: toastsDepuis(nT), kpisAvant: kp });
        nettoyer(root);
      }
      await validerCommande('da'); await validerCommande('comptable'); await validerCommande('stock');
      poserProfil(profilBanc.role, profilBanc.nom);
      async function nouvelleCommande(nom, cfg) {
        const avant = ids(colC), nT = toasts.length;
        const root = await monter('m7-commandes');
        bouton(root, 'Nouvelle commande').click(); await dormir(80);
        const f = fenetre();
        const defauts = {}; [...f.querySelectorAll('[id^=f_]')].forEach((e) => { defauts[e.id.slice(2)] = e.value; });
        const ajout = [...f.querySelectorAll('div')].find((d) => d.className.includes('items-end') && d.className.includes('gap-2'));
        const combo = ajout.children[0].lastElementChild; const nums = ajout.querySelectorAll('input[type=number]');
        for (const l of cfg.lignes) { combo.value = l.produitId; await dormir(20); const puDefaut = nums[1].value; if (l.pu != null) saisir(nums[1], String(l.pu)); saisir(nums[0], String(l.q)); bouton(ajout, 'Ajouter').click(); await dormir(40); l.puDefaut = puDefaut; }
        Object.entries(cfg.champs).forEach(([k, v]) => poserChamp(k, v));
        bouton(f, 'Créer la commande').click(); await dormir(100);
        const cree = nouveaux(colC, avant)[0];
        commandes.creations.push({ nom, defauts, champs: cfg.champs, lignes: cfg.lignes, commande: cree ? propre(net(cree)) : null, ouverte: !!fenetre(), toasts: toastsDepuis(nT) });
        nettoyer(root);
      }
      await nouvelleCommande('brouillon, prix proposé = prix d\'achat du référentiel', { lignes: [{ produitId: articles[0], q: 12, pu: null }, { produitId: articles[1], q: 3, pu: 1000 }], champs: { date: '2026-10-30', fournisseur: 'CAME', statutCommande: 'brouillon' } });
      await nouvelleCommande('en attente de validation : pas de validateur', { lignes: [{ produitId: articles[2], q: 5, pu: 400 }], champs: { date: '2026-10-30', fournisseur: 'MEDIPLUS', statutCommande: 'attente_validation' } });
      await nouvelleCommande('« Transmise » choisie à la saisie : le validateur est posé d\'office (E72, RG-04)', { lignes: [{ produitId: articles[0], q: 2, pu: 700 }], champs: { date: '2026-10-30', fournisseur: 'SOBAPS', statutCommande: 'transmise' } });
      await nouvelleCommande('« Soldée » à la saisie : idem', { lignes: [{ produitId: articles[0], q: 1, pu: 500 }], champs: { date: '2026-10-30', fournisseur: 'NATIFOURN', statutCommande: 'soldee' } });
      await nouvelleCommande('SANS ligne : refusée', { lignes: [], champs: { date: '2026-10-30', fournisseur: 'CAME', statutCommande: 'brouillon' } });
      commandes.modifications = [];
      async function modifierCommande(nom, depart, statut) {
        poserProfil('da', 'TAKI Alimatou'); rang++;
        const c = colC.insert(Object.assign({ reference: 'BC-2095-' + String(rang).padStart(4, '0'), date: '2099-06-01', fournisseur: 'CAME', fournisseurNom: 'CAME', lignes: [cmdLigne(articles[0], 10, 650)], montant: 6500, delaiLivraison: 7 }, depart)).record;
        const avant = propre(net(c)), nT = toasts.length;
        const root = await monter('m7-commandes');
        const tr = ligneDe(root, c.reference);
        [...tr.querySelectorAll('button')].find((x) => titreBouton(x) === 'Modifier').click(); await dormir(80);
        const fe = fenetre();
        const defauts = {}; [...fe.querySelectorAll('[id^=f_]')].forEach((e) => { defauts[e.id.slice(2)] = e.value; });
        poserChamp('statutCommande', statut);
        bouton(fe, 'Enregistrer').click(); await dormir(100);
        commandes.modifications.push({ nom, avant, defauts, statut, apres: propre(net(colC.get(c.id))), toasts: toastsDepuis(nT) });
        nettoyer(root);
      }
      await modifierCommande('brouillon → « Validée » : la DAF est portée validatrice (E72)', { statutCommande: 'brouillon' }, 'validee');
      await modifierCommande('déjà validée par quelqu\'un d\'autre → « Transmise » : le validateur reste', { statutCommande: 'validee', valideePar: 'AUTRE Personne', dateValidation: '2026-01-02' }, 'transmise');
      await modifierCommande('brouillon → en attente : aucun validateur', { statutCommande: 'brouillon' }, 'attente_validation');
      poserProfil(profilBanc.role, profilBanc.nom);
      commandes.serieBC = colC.all().map((c) => c.reference).filter((r) => /^BC-2026-/.test(r)).sort();
      /* Les gardes de statut : les commandes affichées par statut et par profil. */
      for (const role of ['admin', 'da', 'direction', 'comptable', 'stock']) {
        poserProfil(role, 'TAKI Alimatou');
        const root = await monter('m7-commandes');
        commandes.gardes.push({ role, nouvelle: !!bouton(root, 'Nouvelle commande'), kpis: kpis(root), refs: refsPage(root), note: root.firstElementChild.textContent.slice(0, 160) });
        nettoyer(root);
      }
      poserProfil(profilBanc.role, profilBanc.nom);
      commandes.commandes = propre(colC.active().map(net));
      J.commandes = commandes;

      /* ======================================================================================================================================
       * 6. LA RÉCEPTION : entrée en stock gros, CUMP, bon de livraison, écarts
       * ==================================================================================================================================== */
      const receptions = [];
      async function receptionner(nom, cfg) {
        poserProfil('stock', 'MAMAN Zoukanéri');
        rang++;
        const prods = cfg.produits;
        const cmd = colC.insert({ reference: 'BC-2096-' + String(rang).padStart(4, '0'), date: '2096-03-01', fournisseur: 'CAME', fournisseurNom: 'CAME — Centrale d\'Achat des Médicaments Essentiels', delaiLivraison: 7, statutCommande: cfg.statut || 'validee', valideePar: 'TAKI Alimatou',
          lignes: prods.map((p) => cmdLigne(p.id, p.q, p.pu)), montant: prods.reduce((a, p) => a + p.q * p.pu, 0) }).record;
        const avantProduits = propre(prods.map((p) => { const x = colP.get(p.id); return x ? { id: x.id, stockGros: x.stockGros, stock: x.stock, cump: x.cump } : null; }).filter(Boolean));
        const avantL = ids(colL), avantMv = ids(colMv), nT = toasts.length;
        const root = await monter('m7-receptions');
        const kpAvant = kpis(root);
        const tr = ligneDe(root, cmd.reference);
        bouton(tr, 'Réceptionner').click(); await dormir(80);
        const f = fenetre();
        const defauts = {}; [...f.querySelectorAll('[id^=f_]')].forEach((e) => { defauts[e.id.slice(2)] = e.value; });
        const champsRecu = [...f.querySelectorAll('tbody input')];
        const recusParDefaut = champsRecu.map((i) => Number(i.value));
        champsRecu.forEach((inp, i) => { if (cfg.recus && cfg.recus[i] != null) saisir(inp, String(cfg.recus[i])); });
        const ecartsAffiches = [...f.querySelectorAll('tbody tr')].map((tr) => tr.children[3].textContent.trim());
        Object.entries(cfg.champs).forEach(([k, v]) => poserChamp(k, v));
        bouton(f, 'Valider la réception').click(); await dormir(120);
        const bl = nouveaux(colL, avantL)[0];
        const mvts = nouveaux(colMv, avantMv).map((x) => propre(net(x)));
        const apresProduits = propre(prods.map((p) => { const x = colP.get(p.id); return x ? { id: x.id, stockGros: x.stockGros, stock: x.stock, cump: x.cump } : null; }).filter(Boolean));
        const t = toasts.slice(nT).filter((x) => x.undo).pop();
        const cas = { nom, commande: propre(net(cmd)), commandeApres: propre(net(colC.get(cmd.id))), defauts, recusParDefaut, ecartsAffiches, saisieRecus: cfg.recus || null, champs: cfg.champs,
          avantProduits, apresProduits, bl: bl ? propre(net(bl)) : null, mouvements: mvts, ouverte: !!fenetre(), toasts: toastsDepuis(nT), kpisAvant: kpAvant };
        if (t) {
          t.undo(); await dormir(60);
          cas.apresAnnulation = { produits: propre(prods.map((p) => { const x = colP.get(p.id); return x ? { id: x.id, stockGros: x.stockGros, stock: x.stock, cump: x.cump } : null; }).filter(Boolean)),
            commande: colC.get(cmd.id).statutCommande, blActif: bl ? colL.active().some((x) => x.id === bl.id) : null, mouvementsActifs: colMv.active().filter((x) => !avantMv.has(x.id)).length };
        }
        receptions.push(cas);
        nettoyer(root);
      }
      const prod = (i) => colP.get(articles[i]);
      const pr = (i) => ({ id: articles[i], pu: prod(i).prixAchat });
      const base = { referenceBL: '26LNA00099', date: '2026-10-30', controleur1: 'MAMAN Zoukanéri', controleur2: 'DIEYABIDI Aïssatou', controleur3: '', observations: '' };
      await receptionner('conforme : tout est reçu', { produits: [Object.assign(pr(0), { q: 20 }), Object.assign(pr(1), { q: 7 })], champs: base });
      await receptionner('manquant sur une ligne, surplus sur l\'autre, rien sur la troisième', { produits: [Object.assign(pr(0), { q: 20 }), Object.assign(pr(1), { q: 7 }), Object.assign(pr(2), { q: 5 })], recus: [15, 9, 0], champs: Object.assign({}, base, { referenceBL: '26LNA00100', controleur3: 'KINNOU Addoul Ganiou', observations: 'Carton endommagé' }) });
      await receptionner('prix de commande différent du CUMP : le CUMP bouge', { produits: [{ id: articles[0], q: 10, pu: prod(0).prixAchat * 2 + 37 }], champs: Object.assign({}, base, { referenceBL: '26LNA00101' }) });
      await receptionner('article inconnu du référentiel : le bon est écrit, le stock ne bouge pas', { produits: [{ id: 'PRD-INCONNU', q: 4, pu: 900 }, Object.assign(pr(1), { q: 2 })], champs: Object.assign({}, base, { referenceBL: '26LNA00102' }) });
      await receptionner('commande « transmise » : réceptionnable aussi', { statut: 'transmise', produits: [Object.assign(pr(2), { q: 3 })], champs: Object.assign({}, base, { referenceBL: '26LNA00103' }) });
      await receptionner('SANS numéro de bordereau : refusée, rien n\'est écrit', { produits: [Object.assign(pr(0), { q: 5 })], champs: Object.assign({}, base, { referenceBL: '' }) });
      poserProfil(profilBanc.role, profilBanc.nom);
      const serieMv = colMv.all().map((x) => x.reference).filter((r) => /^M\d{6}$/.test(r)).sort();
      J.reception = { _doc: 'La réception d\'une commande : bordereau, écarts, entrée en stock gros, CUMP, mouvement, annulation.', receptions, serieMouvements: serieMv.slice(-8) };

      /* ======================================================================================================================================
       * 7. LIVRAISONS, RÉCEPTIONS (file), ÉCARTS — KPI et registres lus sur les écrans, puis la création d'un bon de livraison
       * ==================================================================================================================================== */
      const lecture = { livraisons: [], receptions: [], ecarts: [], gardes: [] };
      for (const role of ['admin', 'da', 'direction', 'comptable', 'aide_comptable', 'laborantin']) {
        poserProfil(role, 'TAKI Alimatou');
        const o = { role };
        let root = await monter('m7-livraisons'); o.livraisons = { kpis: kpis(root), refs: refsPage(root), nouveau: !!bouton(root, 'Nouveau'), actionsPremiereLigne: [...root.querySelector('tbody tr').querySelectorAll('button')].map(titreBouton) }; nettoyer(root);
        root = await monter('m7-receptions'); o.receptions = { kpis: kpis(root), refs: refsPage(root), actionsPremiereLigne: root.querySelector('tbody tr:last-child') ? [...root.querySelectorAll('tbody tr')].slice(-1).map((tr) => [...tr.querySelectorAll('button')].map(titreBouton)) : [] }; nettoyer(root);
        root = await monter('m7-ecarts'); o.ecarts = { kpis: kpis(root), refs: refsPage(root).slice(0, 15) }; nettoyer(root);
        lecture.gardes.push(o);
      }
      poserProfil(profilBanc.role, profilBanc.nom);
      /* la lecture complète du registre des écarts : chaque ligne (BL, article, commandé, livré, écart, valeur) pour pouvoir la recalculer */
      { const root = await monter('m7-ecarts');
        lecture.ecartsLignes = [...root.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => td.textContent.trim()));
        lecture.ecartsEntete = [...root.querySelectorAll('thead th')].map((th) => th.textContent.trim());
        nettoyer(root); }
      lecture.livraisons = propre(colL.active().map(net));
      lecture.commandes = propre(colC.active().map(net));
      /* création d'un bon de livraison à la main (K.creer) */
      const creationsBL = [];
      async function nouveauBL(nom, champs) {
        const avant = ids(colL), nT = toasts.length, r0 = window.__rechargements || 0;
        const root = await monter('m7-livraisons');
        bouton(root, 'Nouveau').click(); await dormir(80);
        const f = fenetre();
        const defauts = {}; [...f.querySelectorAll('[id^=f_]')].forEach((e) => { defauts[e.id.slice(2)] = e.value; });
        Object.entries(champs).forEach(([k, v]) => poserChamp(k, v));
        bouton(f, 'Créer').click(); await dormir(100);
        const cree = nouveaux(colL, avant)[0];
        creationsBL.push({ nom, defauts, champs, bl: cree ? propre(net(cree)) : null, ouverte: !!fenetre(), rechargements: (window.__rechargements || 0) - r0, toasts: toastsDepuis(nT) });
        nettoyer(root);
      }
      await nouveauBL('avec montant et contrôleur', { commandeRef: 'BC-2026-0001', fournisseur: 'NATIFOURN', date: '2026-10-30', montant: '125000', statutReception: 'conforme', controlePar: 'MAMAN Zoukanéri' });
      await nouveauBL('sans montant ni contrôleur, écart constaté', { commandeRef: 'BC-2026-0002', fournisseur: 'CAME', date: '2026-10-30', montant: '', statutReception: 'ecart', controlePar: '' });
      await nouveauBL('sans commande rattachée : refusé', { commandeRef: '', fournisseur: 'CAME', date: '2026-10-30', montant: '', statutReception: 'conforme', controlePar: '' });
      /* modification d'un bon de livraison (K.actionsLigne → K.modifier) */
      const modifsBL = [];
      async function modifierBL(nom, champs) {
        const bl = colL.insert({ reference: '26LNA-M' + (modifsBL.length + 1), commandeRef: 'BC-M', date: '2099-02-0' + (modifsBL.length + 1), fournisseur: 'CAME', fournisseurNom: 'CAME', statutReception: 'conforme', controlePar: ['MAMAN Zoukanéri', 'DIEYABIDI Aïssatou'], lignes: [], montant: 1000 }).record;
        const avant = propre(net(bl)), nT = toasts.length;
        const root = await monter('m7-livraisons');
        const tr = ligneDe(root, bl.reference);
        [...tr.querySelectorAll('button')].find((x) => titreBouton(x) === 'Modifier').click(); await dormir(80);
        const fe = fenetre();
        const defauts = {}; [...fe.querySelectorAll('[id^=f_]')].forEach((e) => { defauts[e.id.slice(2)] = e.value; });
        Object.entries(champs).forEach(([k, v]) => poserChamp(k, v));
        bouton(fe, 'Enregistrer').click(); await dormir(100);
        modifsBL.push({ nom, avant, defauts, champs, apres: propre(net(colL.get(bl.id))), toasts: toastsDepuis(nT) });
        nettoyer(root);
      }
      await modifierBL('contrôleurs inchangés : la liste est conservée', {});
      await modifierBL('contrôleurs réécrits, avec espaces et virgule vide', { controlePar: ' A ,B,, C ', statutReception: 'ecart', montant: '2500' });
      lecture.modifsBL = modifsBL;
      lecture.creationsBL = creationsBL;
      /* Le registre des écarts sur des livraisons choisies : un manquant, un surplus, un bon sans écart de ligne, un bon conforme (ignoré). */
      const lg = (pid, nom, q, pu, livre) => ({ produitId: pid, produit: nom, unite: 'Unité', quantite: q, prixUnitaire: pu, montant: q * pu, quantiteLivree: livre, ecart: livre - q });
      colL.insert({ reference: '26LNA-X1', commandeRef: 'BC-X1', date: '2099-01-01', fournisseur: 'CAME', fournisseurNom: 'CAME — Centrale d’Achat des Médicaments Essentiels', statutReception: 'ecart', controlePar: ['A', 'B'],
        lignes: [lg('P1', 'GANT TAILLE M', 10, 100, 7), lg('P2', 'COMPRESSE', 4, 50, 6), lg('P3', 'SERINGUE', 8, 25, 8)], montant: 1000 + 200 + 200 });
      colL.insert({ reference: '26LNA-X2', commandeRef: 'BC-X2', date: '2099-01-02', fournisseur: 'MEDIPLUS', fournisseurNom: 'MEDIPLUS Équipements', statutReception: 'ecart', controlePar: ['A', 'B'],
        lignes: [{ produitId: 'P4', produit: 'TENSIOMÈTRE', unite: 'Unité', quantite: 2, prixUnitaire: 30000, montant: 60000, quantiteLivree: 2 }], montant: 60000 });
      colL.insert({ reference: '26LNA-X3', commandeRef: 'BC-X3', date: '2099-01-03', fournisseur: 'CAME', fournisseurNom: 'CAME — Centrale d’Achat des Médicaments Essentiels', statutReception: 'conforme', controlePar: ['A', 'B'],
        lignes: [lg('P5', 'COTON', 5, 650, 4)], montant: 3250 });
      { const root = await monter('m7-ecarts');
        lecture.ecartsExtra = { kpis: kpis(root), lignes: [...root.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => td.textContent.trim())), livraisons: propre(colL.active().map(net)) };
        nettoyer(root); }
      { const root = await monter('m7-livraisons'); lecture.livraisonsExtra = { kpis: kpis(root) }; nettoyer(root); }
      J.lecture = lecture;
      J.fournisseurs = propre(S.collection('fournisseurs').active().map((f) => ({ code: f.code, nom: f.nom, delai: f.delai })));
      return J;
    });

    const marque = 'ENGENDRÉ par prototype_html/build/vecteurs-achats.js — les écrans de m7-achats.js pilotés dans Chrome. Ne pas éditer.';
    const enregistrer = (nom, objet) => ecrire('packages/domaine/test/vecteurs/' + nom + '.json', Object.assign({ _doc: marque }, objet));
    enregistrer('achats-besoins', { jour: sortie.jour, produits: sortie.produits, vues: sortie.vues, arbitrage: sortie.arbitrage, saisie: sortie.saisie, modifications: sortie.modifsBon });
    enregistrer('achats-commandes', Object.assign({ jour: sortie.jour, produits: sortie.produits }, sortie.commandes));
    enregistrer('achats-reception', { jour: sortie.jour, produits: sortie.produits, reception: sortie.reception, lecture: sortie.lecture, fournisseurs: sortie.fournisseurs });
    sortie.arbitrage.arbitrages.forEach((a) => console.log('  arbitrage — ' + a.nom + ' → ' + (a.apres.etape) + ' · notifications ' + a.notifications.length));
    sortie.saisie.saisies.forEach((s) => console.log('  saisie — ' + s.nom + ' → ' + (s.bon ? s.bon.reference + ' ' + s.bon.etape : 'refusée : ' + s.toasts.map((t) => t.message))));
    sortie.commandes.creations.forEach((s) => console.log('  commande — ' + s.nom + ' → ' + (s.commande ? s.commande.reference + ' ' + s.commande.statutCommande + ' ' + (s.commande.valideePar || '') : 'refusée')));
    sortie.reception.receptions.forEach((s) => console.log('  réception — ' + s.nom + ' → ' + (s.bl ? s.bl.statutReception : 'refusée') + ' · ' + s.mouvements.length + ' mouvement(s)'));
    if (m.erreurs.length) console.log('  avertissements de chargement : ' + m.erreurs.length + ' ' + m.erreurs.slice(0, 3));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
