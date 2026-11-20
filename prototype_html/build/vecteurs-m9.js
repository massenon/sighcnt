/* =============================================================================
 * VECTEURS DE M9 — Assurances, créances & relances (10 écrans) — tirés des ÉCRANS RÉELS pilotés dans Chrome
 * -----------------------------------------------------------------------------
 *   node build/vecteurs-m9.js          (sous flock /tmp/sigh-banc.lock ; SIGH_PORT_PHP=<port inhabituel>)
 *
 * Le JEU du poste (apps/poste/assets/donnees/jeu) est posé dans le magasin de la maquette : c'est lui que les tests Flutter chargent. L'horloge de la
 * page est décalée au 16/08/2026 midi (comme le banc : `HORLOGE_BANC`) — le jeu est daté de l'été 2026. Les écrans sont MONTÉS, leurs indicateurs,
 * tableaux, filtres, tiroirs et pièces imprimées sont LUS comme l'agent les lit ; les gestes d'écriture (couverture, grille, émission de la facture
 * mère, règlement, relance) sont ACCOMPLIS par les boutons de l'écran, et l'écart du magasin est enregistré.
 * Sortie (ENGENDRÉE) : packages/domaine/test/vecteurs/ass_m9.json
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');
const JEU_DIR = path.join(ROOT, '..', 'apps/poste/assets/donnees/jeu');
const NOMS = ['assureurs', 'patients', 'factures', 'souscripteurs', 'garanties', 'couverturesAssurance', 'facturesMere', 'relances', 'actes', 'audit'];
const jeu = {};
NOMS.forEach((n) => { jeu[n] = JSON.parse(fs.readFileSync(path.join(JEU_DIR, n + '.json'), 'utf8')); });

(async () => {
  console.log('▶ Vecteurs de M9 (10 écrans)');
  const m = await ouvrirMaquette();
  try {
    /* L'horloge AVANT le chargement du module (qui fige AUJ à son chargement). */
    await m.page.evaluate(() => {
      const Reel = window.Date;
      const decalage = new Reel(2026, 7, 16, 12, 0, 0).getTime() - Reel.now();
      const maintenant = () => Reel.now() + decalage;
      function Decalee() {
        if (!(this instanceof Decalee)) return String(new Reel(maintenant()));
        if (arguments.length === 0) return new Reel(maintenant());
        return new (Function.prototype.bind.apply(Reel, [null].concat(Array.prototype.slice.call(arguments))))();
      }
      Decalee.prototype = Reel.prototype; Decalee.now = maintenant; Decalee.UTC = Reel.UTC; Decalee.parse = Reel.parse;
      window.Date = Decalee;
    });
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m9-assurances.js') });
    const sortie = await m.page.evaluate(async (jeu) => {
      const S = SIGH.store, C = SIGH.core, D = SIGH.data, PR = SIGH.parcours;
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
      const texte = (e) => (e.innerText || '').replace(/\s+/g, ' ').trim();
      const db = () => S.raw();
      const poserJeu = () => { Object.keys(jeu).forEach((n) => { db()[n] = propre(jeu[n]); }); };
      poserJeu();

      /* La pièce imprimée est CAPTURÉE (P.etat remplacé) : titre, cartouche, texte du contenu, signatures. */
      const pieces = [];
      const etatReel = SIGH.print.etat;
      SIGH.print.etat = function (o) {
        pieces.push({
          titre: o.titre, sousTitre: o.sousTitre || null, cartouche: propre(o.cartouche || []),
          contenu: o.contenu ? texte(o.contenu) : null,
          tables: o.contenu && o.contenu.querySelectorAll ? [...o.contenu.querySelectorAll('table')].map((tb) => ({
            entetes: [...tb.querySelectorAll('thead th')].map(texte),
            lignes: [...tb.querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('td')].map(texte)),
            pied: [...tb.querySelectorAll('tfoot td, tfoot th')].map(texte),
          })) : [],
          signatures: propre(o.signatures || []),
        });
      };
      const derniere = () => pieces[pieces.length - 1];

      function releve(root) {
        const kpis = [...root.querySelectorAll('.kpi')].map((k) => ({
          label: texte(k.querySelector('.kpi-label')), valeur: texte(k.querySelector('.kpi-value')),
          indice: (() => { const h = k.querySelector('p.mt-1.text-xs.text-slate-400'); return h ? texte(h) : null; })(),
        }));
        const tables = [...root.querySelectorAll('table')].map((tb) => {
          const carte = tb.closest('.card');
          const h = carte && carte.querySelector('.card-title');
          return {
            titre: h ? texte(h) : null,
            entetes: [...tb.querySelectorAll('thead th')].map(texte).filter((s) => s !== ''),
            lignes: [...tb.querySelectorAll('tbody tr')].map((tr) => ({
              cellules: [...tr.querySelectorAll('td')].map(texte),
              boutons: [...tr.querySelectorAll('button')].map((b) => b.getAttribute('title') || b.getAttribute('aria-label') || texte(b)).filter(Boolean),
            })),
          };
        });
        const onglets = [...root.querySelectorAll('button.tab')].map(texte);
        const cartes = [...root.querySelectorAll('.card-title')].map(texte);
        const boutons = [...root.querySelectorAll('button')].map((b) => b.getAttribute('title') || b.getAttribute('aria-label') || texte(b)).filter(Boolean);
        const filtres = [...root.querySelectorAll('select[aria-label]')].map((s) => ({ label: s.getAttribute('aria-label'), options: [...s.options].map((o) => [o.value, texte(o)]) }));
        return { kpis, tables, onglets, cartes, boutons, filtres, texte: texte(root) };
      }
      async function monter(id) {
        const root = document.createElement('div'); document.body.appendChild(root);
        SIGH.screens[id].render(root); await dormir(120);
        return root;
      }
      const bouton = (portee, re) => [...portee.querySelectorAll('button')].find((b) => re.test(texte(b)) || re.test(b.getAttribute('title') || ''));
      async function cliquer(portee, re) { const b = bouton(portee, re); if (!b) throw new Error('bouton introuvable : ' + re); b.click(); await dormir(120); return b; }
      async function onglet(root, re) { const b = [...root.querySelectorAll('button.tab')].find((x) => re.test(texte(x))); if (!b) throw new Error('onglet introuvable ' + re); b.click(); await dormir(120); }
      function poser(portee, nom, valeur) {
        const e = portee.querySelector('#f_' + nom) || portee.querySelector('[name="' + nom + '"]');
        if (!e) throw new Error('champ introuvable : ' + nom);
        e.value = valeur; e.dispatchEvent(new Event('input', { bubbles: true })); e.dispatchEvent(new Event('change', { bubbles: true }));
      }
      async function filtrer(root, label, valeur) {
        const s = [...root.querySelectorAll('select[aria-label]')].find((x) => x.getAttribute('aria-label') === label);
        if (!s) throw new Error('filtre introuvable : ' + label + ' parmi ' + [...root.querySelectorAll('select[aria-label]')].map((x) => x.getAttribute('aria-label')).join(','));
        s.value = valeur; s.dispatchEvent(new Event('change', { bubbles: true })); await dormir(80);
        return s;
      }
      const lignesDe = (root, i) => [...(root.querySelectorAll('table')[i || 0] || { querySelectorAll: () => [] }).querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('td')].map(texte));
      const fermerDialogues = () => { document.querySelectorAll('[role=dialog]').forEach((d) => d.remove()); };
      const dialogue = () => [...document.querySelectorAll('[role=dialog]')].pop();
      const instantane = (noms) => { const o = {}; noms.forEach((n) => { o[n] = propre(db()[n] || []); }); return o; };
      const IGN = new Set(['_creePar', '_creeLe', '_modifiePar', '_modifieLe', '_archivePar', '_archiveLe']);
      const net = (f) => { const c = propre(f); IGN.forEach((k) => delete c[k]); return c; };
      function ecart(avant, apres) {
        const inserts = {}, modifs = {};
        Object.keys(apres).forEach((n) => {
          const a = new Map((avant[n] || []).map((f) => [f.id, f]));
          apres[n].forEach((f) => {
            if (!a.has(f.id)) { (inserts[n] = inserts[n] || []).push(net(f)); return; }
            const b = a.get(f.id), patch = {};
            Object.keys(f).forEach((k) => { if (!IGN.has(k) && JSON.stringify(f[k]) !== JSON.stringify(b[k])) patch[k] = f[k]; });
            Object.keys(b).forEach((k) => { if (!IGN.has(k) && !(k in f)) patch[k] = null; });
            if (Object.keys(patch).length) (modifs[n] = modifs[n] || []).push({ id: f.id, patch: propre(patch) });
          });
        });
        return { inserts, modifs };
      }
      const COL = ['patients', 'couverturesAssurance', 'garanties', 'souscripteurs', 'factures', 'facturesMere', 'relances'];

      const souscripteurCreation = {};
      const ecrans = {};
      const moisCourant = C.iso(new Date()).slice(0, 7);

      /* ---------- 1. m9-dashboard --------------------------------------------------------------------------------------------------- */
      { const root = await monter('m9-dashboard'); ecrans['m9-dashboard'] = releve(root); root.remove(); }

      /* ---------- 2. m9-compagnies ------------------------------------------------------------------------------------------------- */
      {
        const root = await monter('m9-compagnies');
        const r = releve(root);
        const filtres = {};
        for (const f of r.filtres) {
          for (const [val] of f.options) {
            if (val === '') continue;
            await filtrer(root, f.label, val);
            filtres[f.label + '|' + val] = lignesDe(root).map((l) => l[1]);
          }
          await filtrer(root, f.label, '');
        }
        r.filtresResultats = filtres;
        // tiroir de la 2e compagnie (NSIA)
        const tr = root.querySelectorAll('table tbody tr')[1]; tr.click(); await dormir(200);
        const d = dialogue();
        r.tiroir = { texte: texte(d), tabs: [...d.querySelectorAll('button.tab')].map(texte) };
        for (const t of [...d.querySelectorAll('button.tab')]) { t.click(); await dormir(100); r.tiroir['onglet:' + texte(t).replace(/\d+$/, '').trim()] = texte(d); }
        const pieceAvant = pieces.length;
        const bi = [...d.querySelectorAll('button')].find((b) => /Imprimer/.test(texte(b)));
        if (bi) { bi.click(); await dormir(100); }
        r.piece = pieces.length > pieceAvant ? derniere() : null;
        fermerDialogues();
        // création : le formulaire et la fiche obtenue
        const avant = instantane(['assureurs']);
        await cliquer(root, /^Nouveau$/);
        const dlg = dialogue();
        r.formulaire = [...dlg.querySelectorAll('label')].map(texte);
        poser(dlg, 'code', 'TST'); poser(dlg, 'nom', 'COMPAGNIE DE TEST');
        poser(dlg, 'email', 'test@exemple.bj'); poser(dlg, 'convention', 'Suspendue'); poser(dlg, 'contact', 'M. Test');
        await cliquer(dlg, /^Créer$/);
        r.creation = ecart(avant, instantane(['assureurs']));
        ecrans['m9-compagnies'] = r; root.remove(); fermerDialogues(); poserJeu();
      }

      /* ---------- 3. m9-assures ---------------------------------------------------------------------------------------------------- */
      {
        const root = await monter('m9-assures');
        const r = releve(root);
        const filtres = {};
        for (const [lib, vals] of [['Validité de la carte', ['valide', 'expiree']], ['Compagnie', ['NSIA']], ['Catégorie', ['entreprise', 'particulier', 'personnel']]]) {
          for (const v of vals) { await filtrer(root, lib, v); filtres[lib + '|' + v] = lignesDe(root).map((l) => l[0]); }
          await filtrer(root, lib, '');
        }
        r.filtresResultats = filtres;
        // vérification d'une carte valide, d'une carte expirée
        const lignes = [...root.querySelectorAll('table tbody tr')];
        r.verifications = {};
        const choix = { valide: null, expiree: null };
        for (const tr of lignes) {
          const t = texte(tr);
          if (!choix.expiree && /Expirée/.test(t)) choix.expiree = tr;
          if (!choix.valide && /Valide|Expire dans/.test(t) && !/Expirée/.test(t)) choix.valide = tr;
        }
        for (const k of Object.keys(choix)) {
          const tr = choix[k]; if (!tr) continue;
          tr.click(); await dormir(200);
          const d = dialogue();
          r.verifications[k] = { code: texte(tr.querySelector('td')), texte: texte(d), boutons: [...d.querySelectorAll('button')].map(texte).filter(Boolean) };
          const pieceAvant = pieces.length;
          const ba = [...d.querySelectorAll('button')].find((b) => /Attestation/.test(texte(b)));
          if (ba) { ba.click(); await dormir(100); }
          r.verifications[k].piece = pieces.length > pieceAvant ? derniere() : null;
          fermerDialogues();
        }
        ecrans['m9-assures'] = r; root.remove();
      }
      // le geste « Mettre à jour la couverture » : moteur de la maquette, appelé comme le fait la modale
      const changements = [];
      {
        poserJeu();
        const pats = db().patients.filter((p) => p.assureur && p.statut !== 'archive');
        const patNeuf = pats[0], patHist = db().couverturesAssurance.length ? db().patients.find((p) => p.id === db().couverturesAssurance[0].patientId) : null;
        const essai = (nom, patientId, v, prep) => {
          poserJeu(); if (prep) prep();
          const p = db().patients.find((x) => x.id === patientId);
          const avant = instantane(['patients', 'couverturesAssurance']);
          const entree = { patient: propre(p), historique: propre(db().couverturesAssurance.filter((c) => c.patientId === patientId)), v };
          const res = PR.changerCouverture(p, v);
          const apres = instantane(['patients', 'couverturesAssurance']);
          changements.push({ nom, entree, sortie: { ok: res.ok, motif: res.motif || null }, ecart: ecart(avant, apres), patientApres: propre(db().patients.find((x) => x.id === patientId)) });
        };
        const base = { dateEffet: '2026-09-01', motif: 'Changement d’employeur', assureur: 'NSIA', assureurNom: 'NSIA ASSURANCE', numeroPolice: 'NSIA/2026/9999', categorieAssurance: 'entreprise', tauxPriseEnCharge: 70, carteExpiration: '2027-06-30', souscripteurId: null };
        essai('premier changement d’un dossier ancien', patNeuf.id, base);
        essai('sans date d’effet', patNeuf.id, Object.assign({}, base, { dateEffet: '' }));
        essai('sans motif', patNeuf.id, Object.assign({}, base, { motif: '' }));
        essai('devenu non assuré', patNeuf.id, Object.assign({}, base, { assureur: '', assureurNom: null, numeroPolice: '', categorieAssurance: '', tauxPriseEnCharge: 0, carteExpiration: '', motif: 'Fin de couverture — patient redevenu non assuré' }));
        essai('date d’effet dans le passé (effet immédiat sur la fiche)', patNeuf.id, Object.assign({}, base, { dateEffet: '2026-07-01' }));
        // second changement : la date d'effet doit être postérieure au début de la couverture en cours
        poserJeu(); PR.changerCouverture(db().patients.find((x) => x.id === patNeuf.id), base);
        const avant2 = propre(db().couverturesAssurance), pat2 = propre(db().patients.find((x) => x.id === patNeuf.id));
        const sav = propre(db()); // l'état « après le premier changement » sert d'entrée au second
        const r2 = PR.changerCouverture(db().patients.find((x) => x.id === patNeuf.id), Object.assign({}, base, { dateEffet: '2026-09-01', motif: 'Changement de police' }));
        changements.push({ nom: 'date d’effet non postérieure au début de la couverture en cours', entree: { patient: pat2, historique: avant2, v: Object.assign({}, base, { motif: 'Changement de police' }) }, sortie: { ok: r2.ok, motif: r2.motif || null }, ecart: { inserts: {}, modifs: {} }, patientApres: null });
        const r3 = PR.changerCouverture(db().patients.find((x) => x.id === patNeuf.id), Object.assign({}, base, { dateEffet: '2026-10-15', motif: 'Changement de police', numeroPolice: 'NSIA/2026/0002' }));
        changements.push({ nom: 'bascule datée du mois prochain : la fiche garde la couverture en force aujourd’hui', entree: { patient: pat2, historique: avant2, v: Object.assign({}, base, { dateEffet: '2026-10-15', motif: 'Changement de police', numeroPolice: 'NSIA/2026/0002' }) }, sortie: { ok: r3.ok, motif: r3.motif || null }, ecart: { inserts: {}, modifs: {} }, patientApres: propre(db().patients.find((x) => x.id === patNeuf.id)), historiqueApres: propre(db().couverturesAssurance.filter((c) => c.patientId === patNeuf.id)) });
        poserJeu();
      }

      /* ---------- 4. m9-conventions ------------------------------------------------------------------------------------------------ */
      {
        poserJeu();
        const root = await monter('m9-conventions');
        const r = releve(root);
        r.parOnglet = { souscripteurs: releve(root) };
        const filtres = {};
        for (const [lib, vals] of [['Catégorie', ['entreprise', 'particulier', 'personnel']], ['Convention', ['oui', 'non']]]) {
          for (const v of vals) { await filtrer(root, lib, v); filtres[lib + '|' + v] = lignesDe(root).map((l) => l[0]); }
          await filtrer(root, lib, '');
        }
        r.filtresResultats = filtres;
        // l'onglet des grilles AVANT toute saisie : le jeu n'en porte aucune
        await onglet(root, /Grilles de garanties/); r.parOnglet.garantiesVide = releve(root);
        await onglet(root, /Souscripteurs/);
        const trs = [...root.querySelectorAll('table tbody tr')];
        const sans = trs.find((tr) => /À collecter/.test(texte(tr)));
        const nomS = texte(sans.querySelector('td p'));
        r.fiches = {};
        sans.click(); await dormir(200);
        let d = dialogue();
        r.fiches.sansGrille = { ligne: [...sans.querySelectorAll('td')].map(texte), texte: texte(d), boutons: [...d.querySelectorAll('button')].map((b) => texte(b) || b.getAttribute('title')).filter(Boolean) };
        // saisie de la grille depuis le barème de référence
        const avant = instantane(['garanties', 'souscripteurs']);
        await cliquer(d, /Saisir la grille depuis le barème/);
        d = dialogue();
        r.modaleBareme = { labels: [...d.querySelectorAll('label')].map(texte), texte: texte(d).slice(0, 700) };
        poser(d, 'taux_0', 75); poser(d, 'plafond_0', 6000); poser(d, 'plafond_1', '');
        await cliquer(d, /Enregistrer la convention/);
        r.saisieBareme = { souscripteur: nomS, ecart: ecart(avant, instantane(['garanties', 'souscripteurs'])) };
        fermerDialogues();
        // la fiche AVEC grille et sa convention imprimée
        root.remove();
        const root2 = await monter('m9-conventions');
        r.parOnglet.apresSaisie = releve(root2);
        const trAvec = [...root2.querySelectorAll('table tbody tr')].find((tr) => texte(tr.querySelector('td p')) === nomS);
        trAvec.click(); await dormir(200);
        d = dialogue();
        r.fiches.avecGrille = { ligne: [...trAvec.querySelectorAll('td')].map(texte), texte: texte(d), boutons: [...d.querySelectorAll('button')].map((b) => texte(b) || b.getAttribute('title')).filter(Boolean) };
        { const n0 = pieces.length; await cliquer(d, /Imprimer la convention/); r.fiches.avecGrille.piece = pieces.length > n0 ? derniere() : null; }
        // modifier la grille
        { const av = instantane(['garanties']); await cliquer(d, /Modifier la grille/); const dd = dialogue();
          r.editionGrille = { labels: [...dd.querySelectorAll('label')].map(texte).slice(0, 4), nbChamps: [...dd.querySelectorAll('label')].length };
          poser(dd, 'taux_2', 55); await cliquer(dd, /^Enregistrer$/); r.editionGrille.ecart = ecart(av, instantane(['garanties'])); fermerDialogues(); }
        // exclusions et accords
        { trAvec.click(); await dormir(200); const dd = dialogue(); const av = instantane(['souscripteurs']);
          const bm = [...dd.querySelectorAll('button')].find((b) => /^Modifier$/.test(texte(b))); bm.click(); await dormir(150);
          const d3 = dialogue(); r.editionExclusions = { labels: [...d3.querySelectorAll('label')].map(texte) };
          const bs = [...d3.querySelectorAll('button')].find((b) => /^Enregistrer$/.test(texte(b))); bs.click(); await dormir(150);
          r.editionExclusions.ecart = ecart(av, instantane(['souscripteurs'])); fermerDialogues(); }
        // création d'un souscripteur (K.creer + transform), puis correction (K.modifier)
        { const av = instantane(['souscripteurs']); await cliquer(root2, /^Nouveau$/); const dd = dialogue();
          souscripteurCreation.labels = [...dd.querySelectorAll('label')].map(texte);
          souscripteurCreation.titre = texte(dd.querySelector('h2, h3') || dd).slice(0, 80);
          poser(dd, 'nom', 'Employeur de test'); poser(dd, 'assureur', 'NSIA'); poser(dd, 'police', 'NSIA/2026/7777'); poser(dd, 'categorie', 'particulier');
          poser(dd, 'effectif', 12); poser(dd, 'contact', 'Mme Test'); poser(dd, 'dateDebut', '2026-08-01');
          const nbBtn = [...dd.querySelectorAll('button')].map(texte).filter(Boolean); souscripteurCreation.boutons = nbBtn;
          const bc = [...dd.querySelectorAll('button')].find((b) => /Créer|Enregistrer/.test(texte(b))); bc.click(); await dormir(200);
          souscripteurCreation.ecart = ecart(av, instantane(['souscripteurs']));
          fermerDialogues(); }
        await onglet(root2, /Grilles de garanties/);
        r.parOnglet.garanties = releve(root2);
        r.garantiesFiltre = {};
        await filtrer(root2, 'Catégorie', 'consultation'); r.garantiesFiltre.consultation = lignesDe(root2); await filtrer(root2, 'Catégorie', '');
        await filtrer(root2, 'Souscripteur', nomS); r.garantiesFiltre.souscripteur = lignesDe(root2).length; await filtrer(root2, 'Souscripteur', '');
        await onglet(root2, /Simulateur/);
        r.parOnglet.simulateur = releve(root2);
        const sousId = db().souscripteurs.find((x) => x.nom === nomS).id;
        const assures = db().patients.filter((p) => p.assureur && p.statut !== 'archive');
        const echant = [];
        const ajouter = (p) => { if (p && !echant.find((x) => x.id === p.id)) echant.push(p); };
        ajouter(assures.find((p) => p.souscripteurId === sousId && PR.carteValide(p, new Date())));
        ajouter(assures.find((p) => p.souscripteurId === sousId && !PR.carteValide(p, new Date())));
        ajouter(assures.find((p) => p.souscripteurId !== sousId && PR.carteValide(p, new Date())));
        ajouter(assures.find((p) => !p.souscripteurId));
        r.simulations = [];
        const cible = [...root2.querySelectorAll('div, span')].find((e) => Object.getOwnPropertyDescriptor(e, 'value'));
        for (const p of echant) {
          cible.value = p.id; cible.dispatchEvent(new Event('change', { bubbles: true })); await dormir(150);
          r.simulations.push({ patient: propre(p), texte: texte(root2), tables: [...root2.querySelectorAll('table')].map((tb) => [...tb.querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('td')].map(texte))) });
        }
        r.garantiesPosees = propre(db().garanties.filter((g) => g.souscripteurId === sousId));
        r.souscripteurApres = propre(db().souscripteurs.find((x) => x.id === sousId));
        ecrans['m9-conventions'] = r; root2.remove(); fermerDialogues(); poserJeu();
      }

      /* ---------- 5. m9-prises-en-charge ------------------------------------------------------------------------------------------- */
      {
        poserJeu();
        const root = await monter('m9-prises-en-charge');
        const r = releve(root);
        const filtres = {};
        for (const [lib, vals] of [['Niveau de prise en charge', ['totale', 'partielle']], ['Compagnie', ['NSIA']]]) {
          for (const v of vals) { await filtrer(root, lib, v); filtres[lib + '|' + v] = { total: texte(root.querySelector('.card-title') || root).slice(0, 0), lignes: lignesDe(root).length, premieres: lignesDe(root).slice(0, 3) }; }
          await filtrer(root, lib, '');
        }
        r.filtresResultats = filtres;
        const tr = root.querySelector('table tbody tr');
        r.boutonsLigne = [...tr.querySelectorAll('button')].map((b) => b.getAttribute('title') || texte(b));
        const btn = [...tr.querySelectorAll('button')].find((b) => /Modifier/.test(b.getAttribute('title') || ''));
        if (btn) {
          btn.click(); await dormir(200);
          const d = dialogue();
          r.formulaire = { labels: [...d.querySelectorAll('label')].map(texte), titre: texte(d).slice(0, 160) };
          const code = texte(tr.querySelector('td'));
          const avant = instantane(['factures']);
          poser(d, 'tauxPriseEnCharge', 60); poser(d, 'partAssurance', 1234); poser(d, 'partPatient', 4321); poser(d, 'observations', 'Corrigé au guichet');
          const bs = [...d.querySelectorAll('button')].find((b) => /Enregistrer/.test(texte(b)));
          bs.click(); await dormir(200);
          r.modification = { facture: code, ecart: ecart(avant, instantane(['factures'])) };
          fermerDialogues();
        }
        ecrans['m9-prises-en-charge'] = r; root.remove(); poserJeu();
      }

      /* ---------- 6. m9-factures-assureur ------------------------------------------------------------------------------------------- */
      {
        const fa = db().factures.filter((f) => f.assureur && f.statut !== 'archive');
        const paires = {};
        fa.forEach((f) => { const k = f.assureur + '|' + new Date(f.date).getMonth(); paires[k] = (paires[k] || 0) + 1; });
        const top = Object.keys(paires).sort((a, b) => paires[b] - paires[a]);
        const vides = db().assureurs.map((a) => a.code).filter((c) => !fa.some((f) => f.assureur === c && new Date(f.date).getMonth() === 7));
        const choix = [top[0], top[1], top[2]];
        if (vides.length) choix.push(vides[0] + '|7');
        const root = await monter('m9-factures-assureur');
        const r = { base: releve(root), cas: [] };
        const combo = [...root.querySelectorAll('div, span')].find((e) => Object.getOwnPropertyDescriptor(e, 'value'));
        const selMois = root.querySelector('select.select');
        for (const k of choix) {
          const [code, mois] = k.split('|');
          combo.value = code; combo.dispatchEvent(new Event('change', { bubbles: true }));
          selMois.value = mois; selMois.dispatchEvent(new Event('change', { bubbles: true })); await dormir(150);
          const cas = { assureur: code, mois: Number(mois), vue: releve(root), pieces: {} };
          cas.vue.tables.forEach((t) => delete t.boutons);
          const ongl = [...root.querySelectorAll('button.tab')];
          if (ongl.length) {
            ongl[1].click(); await dormir(120);
            cas.facture = releve(root);
            ongl[0].click(); await dormir(100);
            for (const [cle, re] of [['releve', /Éditer le relevé/], ['facture', /Éditer la facture mensuelle/]]) {
              const n0 = pieces.length;
              await cliquer(root, re);
              cas.pieces[cle] = pieces.length > n0 ? derniere() : null;
            }
          } else {
            const n0 = pieces.length;
            await cliquer(root, /Éditer le relevé/);
            cas.pieces.releve = pieces.length > n0 ? derniere() : null;
          }
          r.cas.push(cas);
        }
        ecrans['m9-factures-assureur'] = r; root.remove();
      }

      /* ---------- 7. m9-facture-mere ------------------------------------------------------------------------------------------------ */
      {
        poserJeu();
        const root = await monter('m9-facture-mere');
        const r = { base: releve(root), grille: [] };
        const combo = [...root.querySelectorAll('div, span')].find((e) => Object.getOwnPropertyDescriptor(e, 'value'));
        const selPer = () => root.querySelector('select');
        const codes = db().assureurs.map((a) => a.code);
        for (const code of codes) {
          for (const per of ['mois', 'trimestre', 'semestre', 'annee']) {
            const cb = [...root.querySelectorAll('div, span')].find((e) => Object.getOwnPropertyDescriptor(e, 'value'));
            cb.value = code; cb.dispatchEvent(new Event('change', { bubbles: true })); await dormir(60);
            const sp = selPer(); sp.value = per; sp.dispatchEvent(new Event('change', { bubbles: true })); await dormir(60);
            const v = releve(root);
            r.grille.push({ assureur: code, periode: per, kpis: v.kpis, boutons: v.boutons.filter((b) => /Émettre|Aperçu/.test(b)), note: v.texte.match(/(La facture mère ne peut pas être émise\.[^]*?(?=Compagnie et périodicité|$))/) ? 'refus' : (/Les trois niveaux concordent/.test(v.texte) ? 'concordant' : (/Aucune prestation assurée pour cette compagnie/.test(v.texte) ? 'vide' : 'autre')), texteNote: (v.texte.match(/Souscripteurs facturés.*/) || [''])[0].slice(0, 0) });
          }
        }
        // un cas concordant : le détail des trois onglets, l'aperçu, l'émission, le règlement partiel puis le solde
        const concordant = r.grille.find((g) => g.note === 'concordant');
        r.emission = null;
        if (concordant) {
          const cb = [...root.querySelectorAll('div, span')].find((e) => Object.getOwnPropertyDescriptor(e, 'value'));
          cb.value = concordant.assureur; cb.dispatchEvent(new Event('change', { bubbles: true })); await dormir(60);
          const sp = selPer(); sp.value = concordant.periode; sp.dispatchEvent(new Event('change', { bubbles: true })); await dormir(150);
          const d1 = releve(root);
          const detail = { assureur: concordant.assureur, periode: concordant.periode, consolidation: d1.tables[0] || null, texte: d1.texte };
          await onglet(root, /Détail par ligne/); const d2 = releve(root);
          detail.lignes = { entetes: d2.tables[0] && d2.tables[0].entetes, nb: d2.tables[0] ? d2.tables[0].lignes.length : 0, premieres: d2.tables[0] ? d2.tables[0].lignes.slice(0, 3).map((l) => l.cellules) : [] };
          await onglet(root, /Consolidation/);
          const n0 = pieces.length; await cliquer(root, /Aperçu de la facture mère/); detail.apercu = pieces.length > n0 ? derniere() : null;
          // voir les pièces filles du 1er souscripteur
          const oeil = [...root.querySelectorAll('table tbody tr')][0].querySelector('button'); oeil.click(); await dormir(150);
          detail.tiroirFilles = texte(dialogue()); fermerDialogues();
          r.detail = detail;
          const avant = instantane(['facturesMere']);
          await cliquer(root, /Émettre la facture mère/);
          let dlg = dialogue(); const messageConfirm = texte(dlg);
          const n1 = pieces.length;
          await cliquer(dlg, /Émettre et transmettre/);
          await dormir(200);
          r.emission = { assureur: concordant.assureur, periode: concordant.periode, confirmation: messageConfirm, ecart: ecart(avant, instantane(['facturesMere'])), piece: pieces.length > n1 ? derniere() : null };
          fermerDialogues();
          await onglet(root, /Factures mères émises/);
          const v3 = releve(root); r.apresEmission = { onglets: v3.onglets, table: v3.tables[0] };
          const emise = r.emission.ecart.inserts.facturesMere[0];
          const ligneEmise = () => [...root.querySelectorAll('table tbody tr')].find((tr) => texte(tr).includes(emise.numero));
          // détail de la pièce émise
          const tr0 = ligneEmise();
          const oeil2 = [...tr0.querySelectorAll('button')].find((b) => /Détail/.test(b.getAttribute('title') || '')); oeil2.click(); await dormir(150);
          r.detailEmise = texte(dialogue()); fermerDialogues();
          const n2 = pieces.length;
          const reimp = [...tr0.querySelectorAll('button')].find((b) => /Réimprimer/.test(b.getAttribute('title') || '')); reimp.click(); await dormir(100);
          r.reimpression = pieces.length > n2 ? derniere() : null;
          // règlement partiel, puis solde
          const reg = async (montant, ref) => {
            await onglet(root, /Factures mères émises/);
            const t0 = ligneEmise();
            const b = [...t0.querySelectorAll('button')].find((x) => /Enregistrer le règlement/.test(texte(x))); b.click(); await dormir(150);
            const dd = dialogue(); const labels = [...dd.querySelectorAll('label')].map(texte);
            const av = instantane(['facturesMere', 'ecritures']);
            poser(dd, 'dateReglement', '2026-08-20'); poser(dd, 'montantRegle', montant); poser(dd, 'reference', ref);
            await cliquer(dd, /^Enregistrer$/);
            await onglet(root, /Factures mères émises/);
            const res = { labels, ecart: ecart(av, instantane(['facturesMere', 'ecritures'])), table: releve(root).tables[0] };
            fermerDialogues(); return res;
          };
          r.reglementPartiel = await reg(1000, 'VIR-001');
          r.reglementSolde = await reg(emise ? (emise.montantReclame - 1000) : 0, 'VIR-002');
          /* B5 (31/10/2026) : le moteur des règlements CUMULATIFS, appelé directement sur une mère posée pour l'occasion (le jeu d'essai de la
             modale ne suffit pas à tester les refus). Chaque appel : refus NOMMÉ, ou fiche après règlement + écritures posées. */
          const colM = S.collection('facturesMere'), colE = S.collection('ecritures');
          const mere = colM.insert({ numero: 'FM-2026-9001', compagnie: 'TEST Compagnie', compagnieCode: 'TST', montantReclame: 30140, etat: 'transmise', piecesFilles: [], souscripteurs: [] }).record;
          const sequence = [];
          const jouerMoteur = (nom, params) => {
            const ecrAvant = new Set(colE.all().map((e) => e.id));
            const res = SIGH.reglerFactureMere(mere.id, params);
            const apres = colM.get(mere.id);
            const ecr = colE.all().filter((e) => !ecrAvant.has(e.id)).map((e) => { const c = propre(e); ['id', '_creePar', '_creeLe', 'statut2', 'pieceId'].forEach((k) => delete c[k]); return c; });
            const reglements = (apres.reglements || []).map((x) => { const c = propre(x); ['id', 'ecritureIds', 'horodatage', 'saisiPar'].forEach((k) => delete c[k]); return c; });
            sequence.push({ nom, params, erreur: res.erreur || null, solde: res.solde === undefined ? null : res.solde,
              fiche: { etat: apres.etat, montantRegle: apres.montantRegle === undefined ? null : apres.montantRegle, reliquat: apres.reliquat === undefined ? null : apres.reliquat,
                dateReglement: apres.dateReglement || null, referenceReglement: apres.referenceReglement || null, reglements }, ecritures: ecr });
          };
          jouerMoteur('premier règlement partiel : 1 000 sur 30 140', { date: '2026-08-20', montant: 1000, reference: 'VIR-001' });
          jouerMoteur('le second règlement S\'AJOUTE : 29 140 solde la pièce (E501 levé)', { date: '2026-08-21', montant: 29140, reference: 'VIR-002' });
          jouerMoteur('pièce soldée : un règlement de plus est refusé', { date: '2026-08-22', montant: 1, reference: 'VIR-003' });
          const mere2 = colM.insert({ numero: 'FM-2026-9002', compagnie: 'TEST Compagnie', compagnieCode: 'TST', montantReclame: 30140, etat: 'transmise', piecesFilles: [], souscripteurs: [] }).record;
          mere.id = mere2.id;
          jouerMoteur('plafond : jamais plus que le dû (30 141 sur 30 140)', { date: '2026-08-20', montant: 30141, reference: 'VIR-010' });
          jouerMoteur('montant nul refusé', { date: '2026-08-20', montant: 0, reference: 'VIR-011' });
          jouerMoteur('montant négatif refusé', { date: '2026-08-20', montant: -5, reference: 'VIR-012' });
          jouerMoteur('date absente refusée', { date: '', montant: 100, reference: 'VIR-013' });
          jouerMoteur('référence absente refusée', { date: '2026-08-20', montant: 100, reference: '  ' });
          jouerMoteur('trois règlements cumulés : 10 000, 10 000, 5 000', { date: '2026-08-20', montant: 10000, reference: 'VIR-020' });
          jouerMoteur('trois règlements cumulés (suite)', { date: '2026-08-25', montant: 10000, reference: 'VIR-021' });
          jouerMoteur('trois règlements cumulés (fin) : reste 10 140, 5 000 laissent 5 140', { date: '2026-09-02', montant: 5000, reference: 'VIR-022' });
          jouerMoteur('plafond sur le reste : 5 141 refusé quand 5 140 restent dus', { date: '2026-09-03', montant: 5141, reference: 'VIR-023' });
          jouerMoteur('le solde exact', { date: '2026-09-03', montant: 5140, reference: 'VIR-024' });
          r.moteurReglements = sequence;
        }
        ecrans['m9-facture-mere'] = r; root.remove(); poserJeu();
      }

      /* ---------- 8. m9-historique -------------------------------------------------------------------------------------------------- */
      {
        const root = await monter('m9-historique');
        const r = { base: releve(root), cas: [] };
        const combo = [...root.querySelectorAll('div, span')].find((e) => Object.getOwnPropertyDescriptor(e, 'value'));
        const dates = [...root.querySelectorAll('input[type=date]')];
        r.dates = dates.map((x) => x.value);
        const filtresBase = {};
        for (const [lib, ] of [['Nature'], ['Règlement'], ['Souscripteur']]) {
          const s = [...root.querySelectorAll('select[aria-label]')].find((x) => x.getAttribute('aria-label') === lib);
          if (!s) continue;
          for (const [val] of [...s.options].map((o) => [o.value]).filter((x) => x[0] !== '').slice(0, 3)) {
            await filtrer(root, lib, val); filtresBase[lib + '|' + val] = lignesDe(root, 0).length;
          }
          await filtrer(root, lib, '');
        }
        r.filtresResultats = filtresBase;
        const premiere = root.querySelectorAll('table')[0] && root.querySelector('table tbody tr');
        if (premiere) { premiere.click(); await dormir(200); r.tiroir = texte(dialogue()); fermerDialogues(); }
        for (const [code, du, au] of [['NSIA', '2026-06-01', '2026-08-16'], ['DAYO', '2026-07-01', '2026-07-31'], ['SANLAM', '2026-01-01', '2026-02-01'], ['', '2026-08-01', '2026-08-16']]) {
          combo.value = code; combo.dispatchEvent(new Event('change', { bubbles: true }));
          dates[0].value = du; dates[0].dispatchEvent(new Event('change', { bubbles: true }));
          dates[1].value = au; dates[1].dispatchEvent(new Event('change', { bubbles: true })); await dormir(150);
          const v = releve(root);
          r.cas.push({ assureur: code, du, au, kpis: v.kpis, texte: v.texte, entetes: v.tables[0] && v.tables[0].entetes, nbLignes: v.tables[0] ? v.tables[0].lignes.length : 0, premieres: v.tables[0] ? v.tables[0].lignes.slice(0, 4).map((l) => l.cellules) : [] });
        }
        ecrans['m9-historique'] = r; root.remove();
      }

      /* ---------- 9. m9-creances ----------------------------------------------------------------------------------------------------- */
      {
        const root = await monter('m9-creances');
        const r = { base: releve(root), cas: [] };
        const champs = () => [...root.querySelectorAll('.card-body select, .card-body input')];
        const [fDu, fAu] = [...root.querySelectorAll('input[type=date]')];
        const [fComp, fAnc, fSeuil] = [...root.querySelectorAll('select')].slice(0, 3);
        const p = async (du, au, comp, anc, seuil) => {
          fDu.value = du; fAu.value = au; fComp.value = comp; fAnc.value = anc; fSeuil.value = seuil;
          fDu.dispatchEvent(new Event('change', { bubbles: true })); await dormir(150);
          const v = releve(root);
          r.cas.push({ du, au, comp, anc, seuil, kpis: v.kpis, lignes: (v.tables[0] || { lignes: [] }).lignes.map((l) => l.cellules), texte: v.texte });
        };
        await p('', '', '', '', '');
        await p('', '', '', 'plus90', '');
        await p('', '', '', '30a90', '');
        await p('', '', '', 'moins30', '');
        await p('2026-07-01', '2026-07-31', '', '', '');
        await p('2026-08-01', '', '', '', '');
        await p('', '', 'NSIA', '', '');
        await p('', '', '', '', '200000');
        await p('', '', '', '', '1000000');
        await p('2030-01-01', '', '', '', '');
        await p('', '', '', '', '');
        const n0 = pieces.length; await cliquer(root, /Éditer l’état des créances/);
        r.piece = pieces.length > n0 ? derniere() : null;
        ecrans['m9-creances'] = r; root.remove();
      }

      /* ---------- 10. m9-relances ---------------------------------------------------------------------------------------------------- */
      {
        poserJeu();
        const root = await monter('m9-relances');
        const r = { base: releve(root), cas: [] };
        const creerRelance = async (v) => {
          const avant = instantane(['relances']);
          await cliquer(root, /Nouvelle relance/);
          const d = dialogue();
          const labels = [...d.querySelectorAll('label')].map(texte);
          const montantDefaut = d.querySelector('#f_montant') ? d.querySelector('#f_montant').value : null;
          poser(d, 'assureur', v.assureur);
          const montantApresChoix = d.querySelector('#f_montant').value;
          poser(d, 'date', v.date); poser(d, 'periode', v.periode); poser(d, 'montant', v.montant); poser(d, 'niveau', v.niveau); poser(d, 'canal', v.canal);
          if (v.observations) poser(d, 'observations', v.observations);
          const n0 = pieces.length;
          await cliquer(d, /Enregistrer et éditer/);
          await dormir(150);
          const cas = { entree: v, labels, montantDefaut, montantApresChoix, ecart: ecart(avant, instantane(['relances'])), piece: pieces.length > n0 ? derniere() : null, table: releve(root).tables[0] };
          fermerDialogues(); r.cas.push(cas); return cas;
        };
        await creerRelance({ assureur: 'NSIA', date: '2026-08-16', periode: 'juin – juillet 2026', montant: 150000, niveau: '1re relance', canal: 'Courrier électronique' });
        await creerRelance({ assureur: 'OLEA', date: '2026-08-16', periode: 'avril – mai 2026', montant: 90000, niveau: 'Mise en demeure', canal: 'Courrier recommandé', observations: 'Dernier rappel avant suspension' });
        await creerRelance({ assureur: 'DAYO', date: '2026-08-16', periode: 'mai 2026', montant: 40000, niveau: '2e relance', canal: 'Appel téléphonique' });
        // refus du formulaire incomplet (période vide)
        { await cliquer(root, /Nouvelle relance/); const d = dialogue(); poser(d, 'periode', ''); const n = db().relances.length;
          await cliquer(d, /Enregistrer et éditer/); r.formulaireIncomplet = { ajoutees: db().relances.length - n, dialogueOuvert: !!dialogue() }; fermerDialogues(); }
        r.kpisApres = releve(root).kpis;
        // modification d'une relance : suite donnée
        { const tr0 = root.querySelector('table tbody tr'); const avant = instantane(['relances']);
          [...tr0.querySelectorAll('button')].find((b) => /Modifier/.test(b.getAttribute('title') || '')).click(); await dormir(150);
          const d = dialogue(); r.formulaireEdition = [...d.querySelectorAll('label')].map(texte);
          poser(d, 'statutRelance', 'regularisee');
          await cliquer(d, /Enregistrer|Modifier/);
          r.modification = { ecart: ecart(avant, instantane(['relances'])), kpis: releve(root).kpis }; fermerDialogues(); }
        // impression d'une lettre existante (mise en demeure)
        { const trs = [...root.querySelectorAll('table tbody tr')]; const tr = trs.find((x) => /Mise en demeure/.test(texte(x)));
          const n0 = pieces.length; [...tr.querySelectorAll('button')].find((b) => /Imprimer/.test(b.getAttribute('title') || '')).click(); await dormir(100);
          r.lettreMiseEnDemeure = pieces.length > n0 ? derniere() : null; }
        // archivage
        { const tr0 = root.querySelector('table tbody tr'); const avant = instantane(['relances']);
          [...tr0.querySelectorAll('button')].find((b) => /Archiver/.test(b.getAttribute('title') || '')).click(); await dormir(150);
          r.archivage = { ecart: ecart(avant, instantane(['relances'])), kpis: releve(root).kpis }; }
        ecrans['m9-relances'] = r; root.remove(); poserJeu();
      }

      SIGH.print.etat = etatReel;
      return { auj: C.iso(new Date()), aujInstant: new Date().toISOString(), ecrans, changements, souscripteurCreation };
    }, jeu);
    ecrire('packages/domaine/test/vecteurs/ass_m9.json', JSON.stringify(sortie) + '\n');
    if (m.erreurs.length) console.log('  (erreurs de page : ' + m.erreurs.slice(0, 5).join(' | ') + ')');
    console.log('  écrans lus : ' + Object.keys(sortie.ecrans).join(', '));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
