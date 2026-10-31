/* =============================================================================
 * VECTEURS DE M11 — Paie & primes (9 écrans) — tirés des ÉCRANS RÉELS pilotés dans Chrome
 * -----------------------------------------------------------------------------
 *   node build/vecteurs-paie.js          (sous flock /tmp/sigh-banc.lock ; SIGH_PORT_PHP=<port inhabituel>)
 *
 * Le JEU du poste (apps/poste/assets/donnees/jeu) est posé dans le magasin de la maquette ; l'horloge de la page est celle de la fiche de
 * parité : 30/10/2026 10 h (posée AVANT le chargement du module, qui fige AUJ). Les écrans sont MONTÉS et LUS comme l'agent les lit (tableaux
 * sur toutes leurs pages, indicateurs, tiroirs, pièces imprimées capturées), les gestes d'écriture (génération des bulletins, validation du
 * lot, déclaration d'heures, avance, prêt) sont ACCOMPLIS par les boutons de l'écran et l'écart du magasin est enregistré.
 * Deux scénarios de données : S0 = le jeu tel quel ; S1 = le jeu auquel on ajoute ce qu'il ne contient pas (sanctions NS 131 sur le mois,
 * participations imputées sur salaire, grille de primes DATÉE avec son historique) — sans quoi ces chemins du moteur ne seraient pas rejoués.
 * Sortie (ENGENDRÉE) : packages/domaine/test/vecteurs/paie.json
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');
const JEU_DIR = path.join(ROOT, '..', 'apps/poste/assets/donnees/jeu');
const NOMS = ['personnel', 'planning', 'evaluations', 'avances', 'participations', 'grillePrimes', 'historiquePrimes', 'heuresSup', 'pretsEtudes', 'bulletins'];
const jeu = {};
NOMS.forEach((n) => { jeu[n] = JSON.parse(fs.readFileSync(path.join(JEU_DIR, n + '.json'), 'utf8')); });

(async () => {
  console.log('▶ Vecteurs de M11 (9 écrans)');
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
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m11-paie.js') });
    const sortie = await m.page.evaluate(async (jeu) => {
      const S = SIGH.store, C = SIGH.core, D = SIGH.data;
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
      const texte = (e) => (e.innerText || '').replace(/\s+/g, ' ').trim();
      const db = () => S.raw();
      const poserJeu = () => { Object.keys(jeu).forEach((n) => { db()[n] = propre(jeu[n]); }); };
      poserJeu();

      const pieces = [];
      const etatReel = SIGH.print.etat;
      SIGH.print.etat = function (o) {
        pieces.push({
          titre: o.titre, sousTitre: o.sousTitre || null, cartouche: propre(o.cartouche || []),
          contenu: o.contenu ? texte(o.contenu) : null,
          tables: o.contenu && o.contenu.querySelectorAll ? (o.contenu.tagName === 'TABLE' ? [o.contenu] : [...o.contenu.querySelectorAll('table')]).map((tb) => ({
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
        const onglets = [...root.querySelectorAll('button.tab')].map(texte);
        const cartes = [...root.querySelectorAll('.card-title')].map(texte);
        const boutons = [...root.querySelectorAll('button')].map((b) => b.getAttribute('title') || b.getAttribute('aria-label') || texte(b)).filter(Boolean);
        const filtres = [...root.querySelectorAll('select[aria-label]')].map((s) => ({ label: s.getAttribute('aria-label'), options: [...s.options].map((o) => [o.value, texte(o)]) }));
        const notes = [...root.querySelectorAll('.note, [class*="note"]')].map(texte).filter(Boolean);
        return { kpis, onglets, cartes, boutons, filtres, notes, texte: texte(root) };
      }
      async function monter(id) {
        const root = document.createElement('div'); document.body.appendChild(root);
        SIGH.screens[id].render(root); await dormir(150);
        return root;
      }
      const bouton = (portee, re) => [...portee.querySelectorAll('button')].find((b) => re.test(texte(b)) || re.test(b.getAttribute('title') || ''));
      async function cliquer(portee, re) { const b = bouton(portee, re); if (!b) throw new Error('bouton introuvable : ' + re); b.click(); await dormir(150); return b; }
      async function onglet(root, re) { const b = [...root.querySelectorAll('button.tab')].find((x) => re.test(texte(x))); if (!b) throw new Error('onglet introuvable ' + re); b.click(); await dormir(120); }
      function poser(portee, nom, valeur) {
        const e = portee.querySelector('#f_' + nom) || portee.querySelector('[name="' + nom + '"]');
        if (!e) throw new Error('champ introuvable : ' + nom);
        if (e.type === 'checkbox') { e.checked = !!valeur; } else { e.value = valeur; }
        e.dispatchEvent(new Event('input', { bubbles: true })); e.dispatchEvent(new Event('change', { bubbles: true }));
      }
      const lignesDe = (tb) => !tb ? [] : [...tb.querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('td')].map(texte));
      /* Toutes les pages d'un tableau : on clique les numéros de page puis on revient à la première. */
      async function tableComplet(root, i) {
        const tb = root.querySelectorAll('table')[i || 0];
        if (!tb) return { entetes: [], lignes: [], pages: 0 };
        const carte = tb.closest('.card');
        const entetes = [...tb.querySelectorAll('thead th')].map(texte);
        const num = () => [...carte.querySelectorAll('button')].filter((b) => /^\d+$/.test(texte(b)));
        const pages = num().length || 1;
        let lignes = lignesDe(tb);
        for (let p = 2; p <= pages; p++) {
          const b = num().find((x) => texte(x) === String(p)); if (!b) break;
          b.click(); await dormir(60);
          lignes = lignes.concat(lignesDe(root.querySelectorAll('table')[i || 0]));
        }
        if (pages > 1) { const b1 = num().find((x) => texte(x) === '1'); if (b1) { b1.click(); await dormir(60); } }
        const titre = carte && carte.querySelector('.card-title');
        return { titre: titre ? texte(titre) : null, entetes, lignes, pages, pied: (() => { const t = [...carte.querySelectorAll('p.text-xs')].find((x) => /Affichage|Aucun enregistrement/.test(texte(x))); return t ? texte(t) : null; })() };
      }
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
      function selectMois(root, i) {
        const s = root.querySelector('select.select');
        s.value = String(i); s.dispatchEvent(new Event('change', { bubbles: true }));
      }
      const toasts = () => [...document.querySelectorAll('[role=status], [role=alert], .toast')].map(texte);

      const MOIS12 = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
      /* Lecture d'un mois sur les trois écrans de calcul. */
      async function lireMois(mois, avecTiroirs) {
        const sortie = {};
        { const root = await monter('m11-calcul'); selectMois(root, mois); await dormir(200);
          const r = releve(root); r.table = await tableComplet(root, 0);
          if (avecTiroirs) {
            r.tiroirs = {};
            for (const mat of avecTiroirs) {
              const tr = [...root.querySelectorAll('table tbody tr')].find((x) => texte(x.querySelector('td')) === mat);
              const tbl = await tableComplet(root, 0);
              if (!tr) { // l'agent peut être sur une autre page : filtrer par recherche
                const rech = root.querySelector('input[type=search], input[placeholder*="echerch"]');
                if (rech) { rech.value = mat; rech.dispatchEvent(new Event('input', { bubbles: true })); await dormir(200); }
              }
              const tr2 = [...root.querySelectorAll('table tbody tr')].find((x) => texte(x.querySelector('td')) === mat);
              if (!tr2) { r.tiroirs[mat] = null; continue; }
              tr2.click(); await dormir(250);
              const d = dialogue();
              const tiroir = { texte: texte(d), tables: [...d.querySelectorAll('table')].map((tb) => ({ entetes: [...tb.querySelectorAll('thead th')].map(texte), lignes: lignesDe(tb) })), kpis: [...d.querySelectorAll('.kpi')].map((k) => [texte(k.querySelector('.kpi-label')), texte(k.querySelector('.kpi-value'))]) };
              const n0 = pieces.length;
              const be = [...d.querySelectorAll('button')].find((b) => /Éditer le bulletin/.test(texte(b)));
              if (be) { be.click(); await dormir(150); }
              tiroir.piece = pieces.length > n0 ? derniere() : null;
              r.tiroirs[mat] = tiroir; fermerDialogues();
              const rech2 = root.querySelector('input[type=search], input[placeholder*="echerch"]');
              if (rech2) { rech2.value = ''; rech2.dispatchEvent(new Event('input', { bubbles: true })); await dormir(100); }
            }
          }
          sortie.calcul = r; root.remove(); }
        { const root = await monter('m11-cotisations'); selectMois(root, mois); await dormir(200);
          const r = releve(root); r.table = await tableComplet(root, 0); r.bareme = await tableComplet(root, 1);
          sortie.cotisations = r; root.remove(); }
        { const root = await monter('m11-ortb'); selectMois(root, mois); await dormir(200);
          const r = releve(root); r.table = await tableComplet(root, 0);
          sortie.ortb = r; root.remove(); }
        return sortie;
      }
      /* Les cinq états de cotisations et le journal de paie d'un mois. */
      async function etatsDuMois(mois) {
        const o = {};
        { const root = await monter('m11-cotisations'); selectMois(root, mois); await dormir(200);
          for (const t of ['CNSS', 'ITS', 'VPS', 'ORTB']) { const n0 = pieces.length; await cliquer(root, new RegExp('^État ' + t)); o[t] = pieces.length > n0 ? derniere() : null; }
          root.remove(); }
        { const root = await monter('m11-calcul'); selectMois(root, mois); await dormir(200);
          const n0 = pieces.length; await cliquer(root, /Éditer le journal de paie/); o.journal = pieces.length > n0 ? derniere() : null; root.remove(); }
        { const root = await monter('m11-ortb'); selectMois(root, mois); await dormir(200);
          const n0 = pieces.length; await cliquer(root, /Imprimer l’état/); o.ortb = pieces.length > n0 ? derniere() : null; root.remove(); }
        return o;
      }

      const scenarios = {};
      const entrees = (nom) => ({
        personnel: propre(db().personnel), planning: propre(db().planning).map((p) => ({ employeId: p.employeId, type: p.type, date: p.date })),
        evaluations: propre(db().evaluations), avances: propre(db().avances), participations: propre(db().participations),
        grillePrimes: propre(db().grillePrimes), historiquePrimes: propre(db().historiquePrimes),
        heuresSup: propre(db().heuresSup), pretsEtudes: propre(db().pretsEtudes),
      });
      const mat = (i) => db().personnel[i].matricule;
      const tiroirs = [mat(0), mat(2), mat(5), mat(8), mat(12), mat(20), mat(30), mat(43)];

      /* ---------- S0 : le jeu tel quel ---------------------------------------------------------------------------------------------- */
      {
        const s = { entrees: entrees(), mois: {} };
        for (const mo of MOIS12) s.mois[mo] = await lireMois(mo, [2, 5, 9].includes(mo) ? tiroirs : null);
        s.etats = { 2: await etatsDuMois(2), 5: await etatsDuMois(5), 9: await etatsDuMois(9) };
        scenarios.S0 = s;
      }

      /* ---------- S1 : sanctions, participations sur salaire, grille datée -------------------------------------------------------- */
      {
        poserJeu();
        const p = db().personnel;
        const ev = db().evaluations;
        const inf = p.filter((x) => x.fonction === 'infirmier').slice(0, 2);
        const agents = [p[0], p[3], inf[0], inf[1], p.find((x) => x.fonction === 'sage_femme'), p.find((x) => x.fonction === 'caissiere'), p.find((x) => x.fonction === 'aide_soignant')].filter(Boolean);
        // sanctions : NS 131 du mois d'octobre et de mars
        [['Octobre 2026', 10], ['Octobre 2026', 5], ['Mars 2026', 20]].forEach(([periode, pct], i) => {
          const a = agents[i];
          ev.push({ id: 'EVT-S1-' + i, employeId: a.id, periode, prelevementPct: pct, statut: 'actif' });
        });
        // une évaluation ARCHIVÉE ne compte pas
        ev.push({ id: 'EVT-S1-ARCH', employeId: agents[3].id, periode: 'Octobre 2026', prelevementPct: 50, statut: 'archive' });
        // participations imputées sur salaire : octobre, mars (autre mois), comptant (jamais retenue), archivée
        const part = db().participations;
        [[agents[0], 'salaire', '2026-10', 1000, 'Mariage — A'], [agents[0], 'salaire', '2026-10', 2500, 'Décès — B'], [agents[1], 'salaire', '2026-03', 1000, 'Naissance — C'],
          [agents[2], 'comptant', '2026-10', 1000, 'Mariage — A'], [agents[4], 'salaire', '2026-10', 1000, 'Naissance — D']].forEach(([a, mode, per, montant, lib], i) => {
          part.push({ id: 'PAR-S1-' + i, employeId: a.id, mode, periodeRetenue: per, montant, evenementLibelle: lib, statut: 'actif' });
        });
        part.push({ id: 'PAR-S1-ARCH', employeId: agents[5].id, mode: 'salaire', periodeRetenue: '2026-10', montant: 9000, evenementLibelle: 'Archivée', statut: 'archive' });
        // avances : une soldée (ne compte pas), une en cours supplémentaire sur le même agent (cumul), une archivée
        const av = db().avances;
        av.push({ id: 'AV-S1-1', employeId: agents[5].id, montant: 100000, mensualite: 25000, rembourse: 25000, statutAvance: 'en_cours', statut: 'actif' });
        av.push({ id: 'AV-S1-2', employeId: agents[5].id, montant: 60000, mensualite: 20000, rembourse: 60000, statutAvance: 'solde', statut: 'actif' });
        av.push({ id: 'AV-S1-3', employeId: agents[5].id, montant: 60000, mensualite: 10000, rembourse: 0, statutAvance: 'en_cours', statut: 'archive' });
        // B6 / E691 : heures supplémentaires, validée du mois (compte), validée d'un autre mois, en attente, archivée, d'un autre agent
        const hs = db().heuresSup;
        hs.length = 0;
        [[agents[0], 'Octobre 2026', 12, 2400, true, 'actif'], [agents[0], 'Octobre 2026', 3, 800, true, 'actif'], [agents[0], 'Mars 2026', 5, 1000, true, 'actif'],
          [agents[1], 'Octobre 2026', 8, 1900, false, 'actif'], [agents[2], 'Octobre 2026', 6, 1500, true, 'archive'], [agents[4], 'Mars 2026', 10, 3100, true, 'actif']].forEach(([a, periode, heures, taux, valide, statut], i) => {
          hs.push({ id: 'HS-S1-' + i, statut, reference: 'HS-S1-' + i, periode, employeId: a.id, employe: a.nomComplet, heures, tauxHoraire: taux, majoration: 25, montant: heures * taux, valide });
        });
        // B6 / E689 : prêts, une échéance au SEUL mois de l'échéance (reliquat sur la dernière), prêt archivé, prêt d'un autre agent, prêt déjà retenu par le jeu
        const pr = db().pretsEtudes;
        pr.length = 0;
        [['PRT-S1-A', agents[0], 'pret_etudes', 100001, '2026-09', 3, []], ['PRT-S1-B', agents[0], 'avance', 60000, '2026-10', 2, []], ['PRT-S1-C', agents[1], 'pret_social', 90000, '2026-03', 3, ['2026-03']],
          ['PRT-S1-D', agents[2], 'pret_etudes', 50000, '2026-10', 1, [], 'archive'], ['PRT-S1-E', agents[5], 'pret_etudes', 300000, '2026-08', 12, ['2026-08', '2026-09']]].forEach(([reference, a, nature, montant, premiereEcheance, nbEcheances, retenues, statut], i) => {
          pr.push({ id: 'PRT-S1-' + i, statut: statut || 'actif', reference, employeId: a.id, agent: a.nomComplet, nature, objet: 'Objet ' + reference, montant, dateAccord: '2026-02-01', premiereEcheance, nbEcheances, autorisePar: 'TAKI Alimatou', retenues });
        });
        // grille de primes DATÉE : la version courante prend effet le 15/10/2026 ; l'historique garde celle de juillet (jusqu'au 14/10) et une plus ancienne
        const gr = db().grillePrimes;
        db().historiquePrimes = [];
        gr.forEach((g) => {
          const hist = { id: 'H-' + g.id, statut: 'actif', primeId: g.primeId, montants: propre(g.montants), dateEffet: g.dateEffet, dateFin: '2026-10-14', version: 1 };
          db().historiquePrimes.push(hist);
          db().historiquePrimes.push({ id: 'H0-' + g.id, statut: 'actif', primeId: g.primeId, montants: Object.fromEntries(Object.entries(g.montants).map(([k, v]) => [k, Math.round(v / 2)])), dateEffet: '2026-01-01', dateFin: '2026-07-12', version: 0 });
          g.dateEffet = '2026-10-15'; g.version = 2;
          g.montants = Object.fromEntries(Object.entries(g.montants).map(([k, v]) => [k, v + 100]));
        });
        const s = { entrees: entrees(), mois: {}, agents: agents.map((a) => a.matricule) };
        for (const mo of MOIS12) s.mois[mo] = await lireMois(mo, [2, 9].includes(mo) ? agents.map((a) => a.matricule) : null);
        s.etats = { 9: await etatsDuMois(9) };
        scenarios.S1 = s;
      }
      poserJeu();

      /* ---------- Les gestes d'écriture : génération, bulletins, validation du lot ------------------------------------------------- */
      const gestes = {};
      const viderToasts = () => { const h = document.getElementById('toast-host'); if (h) h.innerHTML = ''; };
      const lesToasts = () => [...document.querySelectorAll('#toast-host > div')].map(texte);
      const btnTitre = (tr, re) => [...tr.querySelectorAll('button')].find((b) => re.test(b.getAttribute('title') || ''));
      const tablesDe = (d) => [...d.querySelectorAll('table')].map((tb) => ({ entetes: [...tb.querySelectorAll('thead th')].map(texte), lignes: lignesDe(tb) }));
      const filtrerTout = async (root, r) => {
        r.filtresResultats = {};
        for (const f of r.filtres) {
          const sel = () => [...root.querySelectorAll('select[aria-label]')].find((x) => x.getAttribute('aria-label') === f.label);
          for (const [val] of f.options) {
            if (val === '') continue;
            sel().value = val; sel().dispatchEvent(new Event('change', { bubbles: true })); await dormir(80);
            r.filtresResultats[f.label + '|' + val] = lignesDe(root.querySelector('table')).map((l) => l[0]);
          }
          sel().value = ''; sel().dispatchEvent(new Event('change', { bubbles: true })); await dormir(80);
        }
      };
      {
        poserJeu(); fermerDialogues(); viderToasts();
        const g = {};
        const SESSION = localStorage.getItem('sigh-cnt:session');
        const sous = (nom) => { const s0 = JSON.parse(SESSION); s0.nom = nom; localStorage.setItem('sigh-cnt:session', JSON.stringify(s0)); };
        { const root = await monter('m11-validation'); g.validationVide = releve(root); root.remove(); }
        { const root = await monter('m11-bulletins'); g.bulletinsVide = releve(root); root.remove(); }
        for (const mo of [9, 4]) {
          const root = await monter('m11-calcul'); selectMois(root, mo); await dormir(200);
          const avant = instantane(['bulletins']);
          await cliquer(root, /Générer les bulletins/);
          const dlg = dialogue(); const confirmation = texte(dlg);
          await cliquer(dlg, /^Générer$/);
          g['generation' + mo] = { confirmation, toasts: lesToasts(), ecart: ecart(avant, instantane(['bulletins'])) };
          viderToasts(); root.remove();
        }
        { const root = await monter('m11-calcul'); selectMois(root, 6); await dormir(200);
          const avant = instantane(['bulletins']);
          await cliquer(root, /Générer les bulletins/); await cliquer(dialogue(), /^Annuler$/);
          g.generationAnnulee = { ecart: ecart(avant, instantane(['bulletins'])) }; root.remove(); fermerDialogues(); }
        { const root = await monter('m11-bulletins');
          const r = releve(root); r.table = await tableComplet(root, 0);
          await filtrerTout(root, r);
          root.querySelector('table tbody tr').click(); await dormir(250);
          const d = dialogue();
          r.tiroir = { texte: texte(d), tables: tablesDe(d), boutons: [...d.querySelectorAll('button')].map((b) => b.getAttribute('title') || texte(b)).filter(Boolean) };
          const n0 = pieces.length; const be = [...d.querySelectorAll('button')].find((b) => /Imprimer/.test(texte(b))); if (be) { be.click(); await dormir(150); }
          r.tiroir.piece = pieces.length > n0 ? derniere() : null; fermerDialogues();
          g.bulletins = r; root.remove(); }
        { const root = await monter('m11-validation');
          const r = releve(root); r.table = await tableComplet(root, 0);
          const n0 = pieces.length;
          btnTitre(root.querySelector('table tbody tr'), /Journal de paie/).click(); await dormir(150);
          r.journal = pieces.length > n0 ? derniere() : null;
          sous('TAKI Alimatou');   // A2 : la validation se fait sous une AUTRE session que la génération
          const avant = instantane(['bulletins', 'ecritures']);
          const trAValider = [...root.querySelectorAll('table tbody tr')].find((x) => /à valider/.test(texte(x)));
          r.ligneValidee = texte(trAValider.querySelector('td'));
          await cliquer(trAValider, /Valider le lot/);
          const dlg = dialogue(); r.confirmation = texte(dlg);
          await cliquer(dlg, /^Valider la paie$/);
          r.toasts = lesToasts(); r.apres = releve(root); r.apres.table = await tableComplet(root, 0);
          r.ecart = ecart(avant, instantane(['bulletins', 'ecritures'])); r.nbModifs = (r.ecart.modifs.bulletins || []).length;
          r.ecart.modifs = { bulletins: (r.ecart.modifs.bulletins || []).slice(0, 2) };
          r.bulletinsDuLot = propre(db().bulletins.filter((b) => b.periode === r.ligneValidee)).map(net);
          viderToasts(); g.validation = r; root.remove(); sous(JSON.parse(SESSION).nom); }

        /* A2 / B6 : la séparation des tâches, l'écriture de paie, la diffusion. On GÉNÈRE sous une session, puis on tente de VALIDER sous
           la même (refus nommé, rien d'écrit), puis sous une AUTRE (validée, validePar = l'agent connecté, pièce SAL en brouillon). */
        {
          poserJeu(); fermerDialogues(); viderToasts();
          const ligneDe = (root, re) => [...root.querySelectorAll('table tbody tr')].find((x) => re.test(texte(x)));
          const r = { generateur: JSON.parse(SESSION).nom };
          { const root = await monter('m11-calcul'); selectMois(root, 8); await dormir(200);
            await cliquer(root, /Générer les bulletins/); await cliquer(dialogue(), /^Générer$/); viderToasts(); root.remove(); }
          r.bulletinsGeneres = propre(db().bulletins.filter((b) => b.periode === 'Septembre 2026')).map(net);
          { const root = await monter('m11-validation');
            const avant = instantane(['bulletins', 'ecritures']);
            const tr = ligneDe(root, /Septembre 2026/);
            await cliquer(tr, /Valider le lot/); await cliquer(dialogue(), /^Valider la paie$/);
            r.memePersonne = { toasts: lesToasts(), ecart: ecart(avant, instantane(['bulletins', 'ecritures'])) }; viderToasts();
            sous('TAKI Alimatou');
            const avant2 = instantane(['bulletins', 'ecritures']);
            await cliquer(ligneDe(root, /Septembre 2026/), /Valider le lot/); const dlg = dialogue(); r.confirmation = texte(dlg); await cliquer(dlg, /^Valider la paie$/);
            r.autrePersonne = { toasts: lesToasts(), ecart: ecart(avant2, instantane(['bulletins', 'ecritures'])) }; viderToasts();
            r.apresValidation = releve(root); r.apresValidation.table = await tableComplet(root, 0);
            // diffusion
            const avant3 = instantane(['bulletins', 'ecritures']);
            await cliquer(ligneDe(root, /Septembre 2026/), /^Diffuser$/); const dlg2 = dialogue(); r.confirmationDiffusion = texte(dlg2); await cliquer(dlg2, /^Diffuser$/);
            r.diffusion = { toasts: lesToasts(), ecart: ecart(avant3, instantane(['bulletins', 'ecritures'])) }; viderToasts();
            r.apresDiffusion = releve(root); r.apresDiffusion.table = await tableComplet(root, 0);
            root.remove(); }
          // un second lot de la même période : la pièce existe déjà, refus nommé
          { sous(JSON.parse(SESSION).nom);
            { const root = await monter('m11-calcul'); selectMois(root, 8); await dormir(200);
              await cliquer(root, /Générer les bulletins/); await cliquer(dialogue(), /^Générer$/); viderToasts(); root.remove(); }
            sous('TAKI Alimatou');
            const root = await monter('m11-validation');
            const avant = instantane(['bulletins', 'ecritures']);
            await cliquer(ligneDe(root, /à valider/), /Valider le lot/); await cliquer(dialogue(), /^Valider la paie$/);
            r.secondLot = { toasts: lesToasts(), ecart: ecart(avant, instantane(['bulletins', 'ecritures'])) }; viderToasts(); root.remove(); }
          // un lot déséquilibré (net trafiqué) : RG-10 refuse AVANT toute écriture
          { poserJeu(); sous(JSON.parse(SESSION).nom);
            { const rc = await monter('m11-calcul'); selectMois(rc, 6); await dormir(200);
              await cliquer(rc, /Générer les bulletins/); await cliquer(dialogue(), /^Générer$/); viderToasts(); rc.remove(); }
            const per = 'Juillet 2026';
            db().bulletins.filter((b) => b.periode === per && b.statutBulletin === 'a_valider')[0].net += 777;
            sous('TAKI Alimatou');
            const root = await monter('m11-validation');
            const avant = instantane(['bulletins', 'ecritures']);
            await cliquer(ligneDe(root, new RegExp(per)), /Valider le lot/); await cliquer(dialogue(), /^Valider la paie$/);
            r.desequilibre = { periode: per, bulletins: propre(db().bulletins.filter((b) => b.periode === per)).map(net), toasts: lesToasts(), ecart: ecart(avant, instantane(['bulletins', 'ecritures'])) }; viderToasts(); root.remove(); }
          localStorage.setItem('sigh-cnt:session', SESSION);
          g.separation = r;
        }
        gestes.paie = g;
      }

      /* ---------- Heures supplémentaires ------------------------------------------------------------------------------------------- */
      {
        poserJeu(); fermerDialogues(); viderToasts();
        const g = {};
        const root = await monter('m11-heures-sup');
        const r = releve(root); r.table = await tableComplet(root, 0);
        await filtrerTout(root, r);
        g.lecture = r;
        { root.querySelector('table tbody tr').click(); await dormir(250); const d = dialogue(); g.tiroir = { texte: texte(d) }; fermerDialogues(); }
        const e = db().personnel[10];
        await cliquer(root, /^Nouveau$/);
        let dlg = dialogue();
        g.formulaire = [...dlg.querySelectorAll('label')].map(texte);
        const val = (d, n) => { const x = d.querySelector('#f_' + n); return x ? (x.type === 'checkbox' ? x.checked : x.value) : null; };
        g.valeursInitiales = { majoration: val(dlg, 'majoration'), periode: val(dlg, 'periode'), valide: val(dlg, 'valide') };
        { const n = db().heuresSup.length; await cliquer(dlg, /^Créer$/); g.incomplet = { ajoutees: db().heuresSup.length - n, dialogueOuvert: !!dialogue(), toasts: lesToasts() }; viderToasts(); }
        const avant = instantane(['heuresSup']);
        poser(dlg, 'employeId', e.id); poser(dlg, 'periode', 'Octobre 2026'); poser(dlg, 'heures', '10'); poser(dlg, 'majoration', '50'); poser(dlg, 'motif', 'Urgence'); poser(dlg, 'valide', true);
        await cliquer(dlg, /^Créer$/);
        g.creation = { agent: { matricule: e.matricule, salaireBase: e.salaireBase }, toasts: lesToasts(), ecart: ecart(avant, instantane(['heuresSup'])), kpis: releve(root).kpis }; viderToasts(); fermerDialogues();
        { const a2 = instantane(['heuresSup']); await cliquer(root, /^Nouveau$/); dlg = dialogue();
          poser(dlg, 'employeId', db().personnel[3].id); poser(dlg, 'periode', 'Mars 2026'); poser(dlg, 'heures', '4'); poser(dlg, 'majoration', '0'); poser(dlg, 'motif', 'Remplacement');
          await cliquer(dlg, /^Créer$/); g.creationMajorationZero = { salaireBase: db().personnel[3].salaireBase, ecart: ecart(a2, instantane(['heuresSup'])) }; viderToasts(); fermerDialogues(); }
        { const a3 = instantane(['heuresSup']);
          btnTitre(root.querySelector('table tbody tr'), /Modifier/).click(); await dormir(200);
          dlg = dialogue(); g.formulaireEdition = [...dlg.querySelectorAll('label')].map(texte);
          poser(dlg, 'heures', '7'); await cliquer(dlg, /Enregistrer/);
          g.modification = { ecart: ecart(a3, instantane(['heuresSup'])), kpis: releve(root).kpis }; viderToasts(); fermerDialogues(); }
        { const a4 = instantane(['heuresSup']);
          btnTitre(root.querySelector('table tbody tr'), /Archiver/).click(); await dormir(200);
          const dg = dialogue(); g.archivageDialogue = texte(dg);
          await cliquer(dg, /^Archiver$/);
          g.archivage = { ecart: ecart(a4, instantane(['heuresSup'])), kpis: releve(root).kpis }; viderToasts(); fermerDialogues(); }
        gestes.heuresSup = g; root.remove();
      }

      /* ---------- Avances sur salaire ------------------------------------------------------------------------------------------------ */
      {
        poserJeu(); fermerDialogues(); viderToasts();
        const g = {};
        const root = await monter('m11-avances');
        const r = releve(root); r.table = await tableComplet(root, 0);
        await filtrerTout(root, r);
        g.lecture = r;
        { root.querySelector('table tbody tr').click(); await dormir(250); const d = dialogue(); g.tiroir = { texte: texte(d), boutons: [...d.querySelectorAll('button')].map((b) => b.getAttribute('title') || texte(b)).filter(Boolean) };
          const n0 = pieces.length; const be = [...d.querySelectorAll('button')].find((b) => /Imprimer/.test(texte(b))); if (be) { be.click(); await dormir(150); }
          g.tiroir.piece = pieces.length > n0 ? derniere() : null; fermerDialogues(); }
        const e = db().personnel[10];
        await cliquer(root, /^Nouveau$/);
        let dlg = dialogue();
        g.formulaire = [...dlg.querySelectorAll('label')].map(texte);
        const val = (d, n) => { const x = d.querySelector('#f_' + n); return x ? x.value : null; };
        g.valeursInitiales = { date: val(dlg, 'date'), nbMensualites: val(dlg, 'nbMensualites'), statutAvance: val(dlg, 'statutAvance') };
        { const a0 = instantane(['avances']);
          poser(dlg, 'employeId', e.id); poser(dlg, 'montant', String(e.salaireBase * 3 + 1)); poser(dlg, 'nbMensualites', '4'); poser(dlg, 'motif', 'Frais de santé');
          await cliquer(dlg, /^Créer$/);
          g.refusPlafond = { salaireBase: e.salaireBase, toasts: lesToasts(), dialogueOuvert: !!dialogue(), ecart: ecart(a0, instantane(['avances'])) }; viderToasts(); }
        { const a1 = instantane(['avances']);
          poser(dlg, 'montant', String(e.salaireBase * 3)); poser(dlg, 'nbMensualites', '7');
          await cliquer(dlg, /^Créer$/);
          g.creationPlafond = { ecart: ecart(a1, instantane(['avances'])), toasts: lesToasts(), kpis: releve(root).kpis }; viderToasts(); fermerDialogues(); }
        { const a1 = instantane(['avances']); await cliquer(root, /^Nouveau$/); dlg = dialogue();
          poser(dlg, 'employeId', db().personnel[20].id); poser(dlg, 'montant', '50000'); poser(dlg, 'nbMensualites', '3'); poser(dlg, 'motif', 'Besoin personnel');
          await cliquer(dlg, /^Créer$/);
          g.creation = { salaireBase: db().personnel[20].salaireBase, ecart: ecart(a1, instantane(['avances'])), kpis: releve(root).kpis }; viderToasts(); fermerDialogues(); }
        { const a3 = instantane(['avances']);
          // une avance DÉJÀ en partie remboursée : la modification ne doit ni la renuméroter ni remettre « remboursé » à zéro
          const trA = [...root.querySelectorAll('table tbody tr')].find((x) => /AVS-0011/.test(texte(x)));
          btnTitre(trA, /Modifier/).click(); await dormir(200);
          dlg = dialogue(); g.formulaireEdition = [...dlg.querySelectorAll('label')].map(texte);
          poser(dlg, 'nbMensualites', '4'); await cliquer(dlg, /Enregistrer/);
          g.modification = { ecart: ecart(a3, instantane(['avances'])) }; viderToasts(); fermerDialogues(); }
        gestes.avances = g; root.remove();
      }

      /* ---------- Prêts-études et avances -------------------------------------------------------------------------------------------- */
      {
        poserJeu(); fermerDialogues(); viderToasts();
        const g = {};
        const root = await monter('m11-prets-etudes');
        const r = releve(root); r.table = await tableComplet(root, 0); g.lecture = r;
        g.tiroirs = [];
        for (const i of [0, 1, 2, 3]) {
          const tr = [...root.querySelectorAll('table tbody tr')][i]; if (!tr) continue;
          btnTitre(tr, /Consulter/).click(); await dormir(250);
          const d = dialogue(); g.tiroirs.push({ ligne: [...tr.querySelectorAll('td')].map(texte), texte: texte(d), tables: tablesDe(d) }); fermerDialogues();
        }
        await cliquer(root, /Nouveau prêt ou avance/);
        let dlg = dialogue();
        g.formulaire = [...dlg.querySelectorAll('label')].map(texte);
        const e = db().personnel[7];
        { const n0 = db().pretsEtudes.length; await cliquer(dlg, /^Créer$/); g.incomplet = { ajoutees: db().pretsEtudes.length - n0, toasts: lesToasts() }; viderToasts(); }
        const avant = instantane(['pretsEtudes']);
        poser(dlg, 'employeId', e.id); poser(dlg, 'nature', 'pret_etudes'); poser(dlg, 'objet', 'Formation continue'); poser(dlg, 'montant', '100001');
        poser(dlg, 'dateAccord', '2026-10-30'); poser(dlg, 'premiereEcheance', '2026-12'); poser(dlg, 'nbEcheances', '3'); poser(dlg, 'autorisePar', 'TAKI Alimatou');
        await cliquer(dlg, /^Créer$/);
        g.creation = { agent: { matricule: e.matricule, nomComplet: e.nomComplet }, toasts: lesToasts(), ecart: ecart(avant, instantane(['pretsEtudes'])), kpis: releve(root).kpis }; viderToasts(); fermerDialogues();
        { btnTitre(root.querySelector('table tbody tr'), /Consulter/).click(); await dormir(250);
          const d = dialogue(); g.tiroirCree = { texte: texte(d), tables: tablesDe(d) }; fermerDialogues(); }
        { const a2 = instantane(['pretsEtudes']); await cliquer(root, /Nouveau prêt ou avance/); dlg = dialogue();
          poser(dlg, 'employeId', db().personnel[8].id); poser(dlg, 'nature', 'avance'); poser(dlg, 'objet', 'Passage d’année'); poser(dlg, 'montant', '250000');
          poser(dlg, 'dateAccord', '2026-10-30'); poser(dlg, 'premiereEcheance', '2026-11'); poser(dlg, 'nbEcheances', '5'); poser(dlg, 'autorisePar', 'TAKI Alimatou');
          await cliquer(dlg, /^Créer$/); g.creationAnnee = { ecart: ecart(a2, instantane(['pretsEtudes'])) }; viderToasts(); fermerDialogues();
          btnTitre(root.querySelector('table tbody tr'), /Consulter/).click(); await dormir(250);
          const d = dialogue(); g.tiroirAnnee = { tables: tablesDe(d) }; fermerDialogues(); }
        { const a3 = instantane(['pretsEtudes']);
          btnTitre(root.querySelector('table tbody tr'), /Modifier/).click(); await dormir(200);
          dlg = dialogue(); g.formulaireEdition = [...dlg.querySelectorAll('label')].map(texte);
          poser(dlg, 'nbEcheances', '2'); await cliquer(dlg, /Enregistrer/);
          g.modification = { ecart: ecart(a3, instantane(['pretsEtudes'])), kpis: releve(root).kpis }; viderToasts(); fermerDialogues(); }
        { const a4 = instantane(['pretsEtudes']);
          btnTitre(root.querySelector('table tbody tr'), /Archiver/).click(); await dormir(200);
          const dg = dialogue(); g.archivageDialogue = texte(dg);
          bouton(dg, /^Archiver$/).click(); await dormir(120);
          g.sansMotif = { dialogueOuvert: !!dialogue(), ecart: ecart(a4, instantane(['pretsEtudes'])) };
          const ta = dialogue() && dialogue().querySelector('textarea');
          if (ta) { ta.value = 'Erreur de saisie'; ta.dispatchEvent(new Event('input', { bubbles: true })); }
          const b2 = dialogue() && bouton(dialogue(), /^Archiver$/); if (b2) { b2.click(); await dormir(150); }
          g.archivage = { ecart: ecart(a4, instantane(['pretsEtudes'])), kpis: releve(root).kpis }; viderToasts(); fermerDialogues(); }
        gestes.prets = g; root.remove();
      }
      poserJeu();

      SIGH.print.etat = etatReel;
      return {
        auj: C.iso(new Date()), aujInstant: new Date().toISOString(),
        param: propre(D.PARAM_PAIE), ns132: propre(D.NS132.primes), ns132Meta: propre({ dateEffet: D.NS132.dateEffet, version: D.NS132.version }),
        fonctions: propre(D.FONCTIONS), services: propre(D.SERVICES), scenarios, gestes,
      };
    }, jeu);
    ecrire('packages/domaine/test/vecteurs/paie.json', JSON.stringify(sortie) + '\n');
    if (m.erreurs.length) console.log('  (erreurs de page : ' + m.erreurs.slice(0, 5).join(' | ') + ')');
    console.log('  scénarios : ' + Object.keys(sortie.scenarios).join(', '));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
