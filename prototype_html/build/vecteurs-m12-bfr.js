/* =============================================================================
 * VECTEURS DE M12 — BESOIN EN FONDS DE ROULEMENT et COÛT À L'ACTIVITÉ (m12-bfr, m12-cout-activite) : le MOTEUR `SIGH.bfr` appelé tel quel et les deux
 * ÉCRANS réels pilotés dans Chrome.
 * -----------------------------------------------------------------------------
 *   node build/vecteurs-m12-bfr.js      (sous flock /tmp/sigh-banc.lock ; SIGH_PORT_PHP=<port inhabituel 101xx>)
 *
 * Le JEU du poste est posé dans le magasin de la maquette, l'horloge est décalée au 30/10/2026 10 h (`_m12-outils.js`).
 * Sortie (ENGENDRÉE) : packages/domaine/test/vecteurs/bfr.json
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');
const JEU_DIR = path.join(ROOT, '..', 'apps/poste/assets/donnees/jeu');
const NOMS = ['factures', 'produits', 'facturesFournisseurs', 'mouvements', 'admissions', 'assureurs', 'facturesMere', 'objectifsPilotage', 'actes'];
const jeu = {};
NOMS.forEach((n) => { jeu[n] = JSON.parse(fs.readFileSync(path.join(JEU_DIR, n + '.json'), 'utf8')); });

(async () => {
  console.log('▶ Vecteurs de M12 — BFR et coût à l\'activité');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(__dirname, '_m12-outils.js') });
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m12-comptabilite.js') });
    const sortie = await m.page.evaluate(async (jeu) => {
      const S = SIGH.store, C = SIGH.core;
      const O = window.__O;
      const { propre, texte, dormir, db } = O;
      const poserJeu = () => { Object.keys(jeu).forEach((n) => { db()[n] = propre(jeu[n]); }); };
      poserJeu();
      const navigations = [];
      SIGH.app.go = (id) => { navigations.push(id); };
      const rep = {};
      const fixer = (e) => { const c = propre(e); return c; };

      /* ---------- le moteur ----------------------------------------------------------------------------------------------------------- */
      const moteur = {};
      const calc = (opts) => { const b = SIGH.bfr.calculer(opts); return propre(b); };
      moteur.defaut = calc({ fin: '2026-10-30', jours: 90 });
      moteur.sansOptions = calc();
      moteur.j30 = calc({ fin: '2026-10-30', jours: 30 });
      moteur.j180 = calc({ fin: '2026-10-30', jours: 180 });
      moteur.j365 = calc({ fin: '2026-10-30', jours: 365 });
      moteur.aout = calc({ fin: '2026-08-16', jours: 90 });
      moteur.futur = calc({ fin: '2027-03-01', jours: 90 });
      moteur.sansCA = calc({ fin: '2024-01-01', jours: 30 });
      moteur.valorisation = S.valorisationSortie();
      {
        const sv = propre(db().facturesFournisseurs);
        db().facturesFournisseurs = [];
        moteur.sansDettes = calc({ fin: '2026-10-30', jours: 90 });
        const sp = propre(db().produits);
        db().produits = [];
        moteur.sansRien = calc({ fin: '2026-10-30', jours: 90 });
        db().facturesFournisseurs = sv; db().produits = sp;
      }
      moteur.nbParStatut = { factures: db().factures.filter((f) => f.statut !== 'archive').length };
      moteur.alertes = propre(SIGH.bfr.alertes({ fin: '2026-10-30' }));
      moteur.alertesAout = propre(SIGH.bfr.alertes({ fin: '2026-08-16' }));
      moteur.alertesSansFin = propre(SIGH.bfr.alertes());
      {
        const col = db().objectifsPilotage;
        const o = col.find((x) => x.id === 'creance_agee');
        const ancienne = o.cible;
        o.cible = 45;
        moteur.alertesSeuil45 = propre(SIGH.bfr.alertes({ fin: '2026-10-30' }));
        o.cible = 120;
        moteur.alertesSeuil120 = propre(SIGH.bfr.alertes({ fin: '2026-10-30' }));
        o.cible = ancienne;
        const sv = propre(db().objectifsPilotage);
        db().objectifsPilotage = [];
        moteur.alertesSemence = propre(SIGH.bfr.alertes({ fin: '2026-10-30' }));
        moteur.objectifsSemence = propre(SIGH.bfr.objectifs().map((x) => x.id));
        db().objectifsPilotage = sv;
        moteur.creanceAgee = propre(SIGH.bfr.objectifs().find((x) => x.id === 'creance_agee'));
      }
      rep.moteur = moteur;

      /* ---------- l'écran m12-bfr ------------------------------------------------------------------------------------------------------ */
      const B = {};
      {
        O.graphiques.length = 0;
        const root = await O.monter('m12-bfr');
        const rel = O.releve(root);
        B.defaut = { kpis: rel.kpis, notes: rel.notes, cartes: rel.cartes, boutons: rel.boutons, tables: rel.tables, graphiques: propre(O.graphiques) };
        B.controles = { labels: [...root.querySelectorAll('label')].map(texte), date: root.querySelector('input[type=date]').value,
          periode: root.querySelector('select').value, options: [...root.querySelector('select').options].map((o) => [o.value, texte(o)]) };
        // les variations
        const sel = root.querySelector('select'), inDate = root.querySelector('input[type=date]');
        async function regler(date, jours) {
          inDate.value = date; inDate.dispatchEvent(new Event('change', { bubbles: true }));
          sel.value = String(jours); sel.dispatchEvent(new Event('change', { bubbles: true }));
          await dormir(200);
          const r = O.releve(root);
          return { kpis: r.kpis.map((k) => [k.label, k.valeur, k.indice]), notes: r.notes, nbTables: r.tables.length, alertes: r.tables.filter((t) => /Créances au-delà/.test(t.titre || '')).map((t) => ({ titre: t.titre, lignes: t.lignes.map((l) => l.cellules) })) };
        }
        B.variations = {};
        for (const [k, d, j] of [['j30', '2026-10-30', 30], ['j180', '2026-10-30', 180], ['j365', '2026-10-30', 365], ['aout', '2026-08-16', 90], ['futur', '2027-03-01', 90]]) B.variations[k] = await regler(d, j);
        await regler('2026-10-30', 90);
        // l'impression
        const pa = O.pieces.length;
        await O.cliquer(root, /Imprimer l’état du BFR/);
        B.piece = O.pieces.length > pa ? O.pieces[O.pieces.length - 1] : null;
        // les sources
        const ids = [];
        for (const re of [/balance âgée des créances/, /point de stock/, /factures fournisseurs/, /relances/]) {
          const b = O.bouton(root, re); if (!b) { ids.push(null); continue; }
          const n0 = navigations.length; b.click(); await dormir(60); ids.push(navigations[n0] || null);
        }
        B.navigations = ids;
        B.entetes = [...SIGH.screens['m12-bfr'].actions().map((b) => texte(b))];
        root.remove();
      }
      // composant non amorcé : la note danger
      {
        const sv = propre(db().facturesFournisseurs);
        db().facturesFournisseurs = [];
        const root = await O.monter('m12-bfr');
        B.incomplet = { notes: O.releve(root).notes, kpis: O.releve(root).kpis.map((k) => [k.label, k.valeur, k.indice]) };
        root.remove();
        db().facturesFournisseurs = sv;
      }
      // pas de créance au-delà du seuil
      {
        const sv = propre(db().factures);
        db().factures.forEach((f) => { f.partAssurance = 0; });
        const root = await O.monter('m12-bfr');
        B.sansAlerte = { texte: texte(root).slice(-260), notes: O.releve(root).notes };
        root.remove();
        db().factures = sv;
      }
      rep.ecranBfr = B;

      /* ---------- l'écran m12-cout-activite --------------------------------------------------------------------------------------------- */
      const A = {};
      A.bfrAvant = calc({ fin: '2026-10-30' });
      {
        O.graphiques.length = 0;
        const root = await O.monter('m12-cout-activite');
        const dates = () => [...root.querySelectorAll('input[type=date]')];
        A.controles = { du: dates()[0].value, au: dates()[1].value, labels: [...root.querySelectorAll('label')].map(texte) };
        const lire = () => {
          const r = O.releve(root);
          const tables = r.tables;
          return { kpis: r.kpis.map((k) => [k.label, k.valeur, k.indice]), notes: r.notes, groupes: tables[0] ? tables[0].lignes.map((l) => l.cellules) : [],
            entetes: tables[0] ? tables[0].entetes : [], prevision: tables[1] ? { entetes: tables[1].entetes, lignes: tables[1].lignes.map((l) => l.cellules) } : null,
            cartes: r.cartes, texte: texte(root).slice(0, 1800) };
        };
        A.defaut = lire();
        A.bfrPendant = calc({ fin: dates()[1].value });
        A.graphiques = propre(O.graphiques);
        async function periode(du, au) {
          const [a, b] = dates();
          a.value = du; a.dispatchEvent(new Event('change', { bubbles: true }));
          b.value = au; b.dispatchEvent(new Event('change', { bubbles: true }));
          await dormir(200);
          return lire();
        }
        A.parPeriode = {};
        for (const [k, du, au] of [['aout', '2026-08-01', '2026-08-31'], ['tout', '', ''], ['futur', '2027-01-01', '2027-12-31'], ['sansDebut', '', '2026-08-31'], ['sansFin', '2026-09-01', ''], ['juillet', '2026-07-01', '2026-07-31']]) A.parPeriode[k] = await periode(du, au);
        await periode(A.controles.du, A.controles.au);
        const pa = O.pieces.length;
        await O.cliquer(root, /Imprimer l’analyse/);
        A.piece = O.pieces.length > pa ? O.pieces[O.pieces.length - 1] : null;
        A.entetes = [...SIGH.screens['m12-cout-activite'].actions().map((b) => texte(b))];
        const n0 = navigations.length;
        for (const re of [/Recettes & charges par groupe/, /Coût global de l’agent/]) { O.bouton(root, re); }
        root.remove();
      }
      // peu d'admissions : aucune prévision
      {
        const sv = propre(db().admissions);
        db().admissions = db().admissions.slice(0, 2);
        const root = await O.monter('m12-cout-activite');
        A.sansPrevision = { texte: texte(root).slice(-420) };
        root.remove();
        db().admissions = sv;
      }
      A.admissionsParMois = (() => { const p = new Array(12).fill(0); db().admissions.filter((a) => a.statut !== 'archive').forEach((a) => { const d = String(a.dateEntree || '').slice(0, 10); if (d) { const k = Number(d.slice(5, 7)) - 1; if (k >= 0 && k < 12) p[k]++; } }); return p; })();
      rep.ecranCout = A;
      rep.toastsTotal = O.toasts.length;
      return rep;
    }, jeu);
    if (m.erreurs.length) console.log('  ⚠ erreurs JS de la page : ' + m.erreurs.slice(0, 5).join(' | '));
    ecrire('packages/domaine/test/vecteurs/bfr.json', sortie);
    console.log('  ✓ ' + Object.keys(sortie).length + ' blocs');
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
