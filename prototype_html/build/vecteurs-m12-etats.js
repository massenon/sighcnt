/* =============================================================================
 * VECTEURS DE M12 — ÉTATS FINANCIERS DE SYNTHÈSE (m12-etats-financiers) : les CINQ feuillets de la liasse déposée, tirés de l'ÉCRAN RÉEL piloté dans Chrome.
 * -----------------------------------------------------------------------------
 *   node build/vecteurs-m12-etats.js      (sous flock /tmp/sigh-banc.lock ; SIGH_PORT_PHP=<port inhabituel 101xx>)
 *
 * Le JEU du poste est posé dans le magasin de la maquette, l'horloge est décalée au 30/10/2026 10 h (`_m12-outils.js`). Sortie (ENGENDRÉE) :
 * packages/domaine/test/vecteurs/etats.json
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');
const JEU_DIR = path.join(ROOT, '..', 'apps/poste/assets/donnees/jeu');
const NOMS = ['ecritures', 'exercices', 'comptes'];
const jeu = {};
NOMS.forEach((n) => { jeu[n] = JSON.parse(fs.readFileSync(path.join(JEU_DIR, n + '.json'), 'utf8')); });

(async () => {
  console.log('▶ Vecteurs de M12 — états financiers (liasse déposée)');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(__dirname, '_m12-outils.js') });
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m12-comptabilite.js') });
    const sortie = await m.page.evaluate(async (jeu) => {
      const S = SIGH.store;
      const O = window.__O;
      const { propre, texte, dormir, db } = O;
      const poserJeu = () => { Object.keys(jeu).forEach((n) => { db()[n] = propre(jeu[n]); }); };
      poserJeu();
      const navigations = [];
      SIGH.app.go = (id) => { navigations.push(id); };
      const rep = {};

      async function lireTout(root) {
        const r = { entete: O.releve(root) };
        const onglets = ['Bilan', 'Compte de résultat', 'Tableau des flux de trésorerie', 'Disponibilités', 'Fiche de synthèse'];
        r.onglets = {};
        for (const nom of onglets) {
          await O.onglet(root, new RegExp('^' + nom.replace(/[()]/g, '\\$&') + '$'));
          const rel = O.releve(root);
          r.onglets[nom] = {
            tables: rel.tables.map((t) => ({ titre: t.titre, entetes: t.entetes, lignes: t.lignes.map((l) => l.cellules) })),
            cartes: rel.cartes, notes: rel.notes,
            listes: [...root.querySelectorAll('ul')].map((u) => [...u.children].map(texte)),
            badges: [...root.querySelectorAll('span[title]')].map((b) => ({ titre: b.getAttribute('title'), texte: texte(b) })),
          };
        }
        await O.onglet(root, /^Bilan$/);
        return r;
      }

      /* ---------- le jeu tel quel : pas de colonne N-1 du journal ----------------------------------------------------------------------------- */
      {
        const root = await O.monter('m12-etats-financiers');
        rep.jeu = await lireTout(root);
        rep.jeu.texteSource = texte(root).slice(-330);
        rep.jeu.boutons = [...root.querySelectorAll('button:not(.tab)')].map(texte).filter(Boolean);
        // les impressions
        rep.pieces = {};
        const ordre = [['Imprimer le bilan', 'bilan'], ['Compte de résultat', 'resultat'], ['Flux de trésorerie', 'flux'], ['Disponibilités', 'disponibilites'], ['Fiche de synthèse', 'synthese']];
        for (const [lib, cle] of ordre) {
          const pa = O.pieces.length;
          const b = [...root.querySelectorAll('button:not(.tab)')].find((x) => texte(x) === lib);
          b.click(); await dormir(120);
          rep.pieces[cle] = O.pieces.length > pa ? O.pieces[O.pieces.length - 1] : null;
        }
        const n0 = navigations.length;
        [...root.querySelectorAll('button:not(.tab)')].find((x) => texte(x) === 'Immobilisations').click(); await dormir(60);
        rep.navigation = navigations[n0] || null;
        root.remove();
      }

      /* ---------- un journal qui porte l'exercice précédent : la colonne « Exercice 2025 (journal) » paraît ---------------------------------------- */
      {
        const lignes = [
          ['E25-1', '2025-03-01', '571000', 'Caisse', 900000, 0],
          ['E25-1', '2025-03-01', '706000', 'Prestations', 0, 900000],
          ['E25-2', '2025-04-02', '521000', 'Banque', 400000, 0],
          ['E25-2', '2025-04-02', '411000', 'Clients — Patients', 0, 400000],
          ['E25-3', '2025-05-03', '401000', 'Fournisseurs', 0, 250000],
          ['E25-3', '2025-05-03', '604100', 'Achats', 250000, 0],
        ];
        lignes.forEach((l, i) => db().ecritures.unshift({ id: 'X25-' + i, numero: l[0], date: l[1], journal: 'OD', compte: l[2], compteLibelle: l[3], debit: l[4], credit: l[5], statut: 'validee' }));
        db().ecritures.unshift({ id: 'X25-BR', numero: 'E25-BR', date: '2025-06-01', journal: 'OD', compte: '571000', debit: 777, credit: 0, statut: 'brouillon' });
        const root = await O.monter('m12-etats-financiers');
        const bil = O.releve(root);
        rep.avecN1 = { entetes: bil.tables.map((t) => t.entetes), tables: bil.tables.map((t) => t.lignes.map((l) => l.cellules)) };
        await O.onglet(root, /^Disponibilités$/);
        const d = O.releve(root);
        rep.avecN1.dispo = d.tables.map((t) => ({ entetes: t.entetes, lignes: t.lignes.map((l) => l.cellules) }));
        root.remove();
        poserJeu();
      }

      /* ---------- les comptes de tiers changent de côté selon leur sens ------------------------------------------------------------------------- */
      {
        // un client créditeur (avance) et un fournisseur débiteur : ils changent de côté
        db().ecritures.unshift({ id: 'T-1', numero: 'T1', date: '2026-06-01', journal: 'OD', compte: '411000', debit: 0, credit: 123000, statut: 'validee' });
        db().ecritures.unshift({ id: 'T-2', numero: 'T1', date: '2026-06-01', journal: 'OD', compte: '571000', debit: 123000, credit: 0, statut: 'validee' });
        db().ecritures.unshift({ id: 'T-3', numero: 'T2', date: '2026-06-02', journal: 'OD', compte: '401000', debit: 55000, credit: 0, statut: 'validee' });
        db().ecritures.unshift({ id: 'T-4', numero: 'T2', date: '2026-06-02', journal: 'OD', compte: '571000', debit: 0, credit: 55000, statut: 'validee' });
        const root = await O.monter('m12-etats-financiers');
        const rel = O.releve(root);
        rep.tiers = { tables: rel.tables.map((t) => t.lignes.map((l) => l.cellules)) };
        root.remove();
        poserJeu();
      }
      rep.ecarts = propre(SIGH.liasse.ECARTS);
      rep.toastsTotal = O.toasts.length;
      return rep;
    }, jeu);
    if (m.erreurs.length) console.log('  ⚠ erreurs JS de la page : ' + m.erreurs.slice(0, 5).join(' | '));
    ecrire('packages/domaine/test/vecteurs/etats.json', sortie);
    console.log('  ✓ ' + Object.keys(sortie).length + ' blocs');
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
