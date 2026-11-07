/* =============================================================================
 * VECTEURS DU PILOTAGE (PIL) — les treize écrans de statistiques et de tableaux de bord de la Direction, PILOTÉS dans Chrome :
 * dash-direction, dash-da, dash-croise, dash-admin, m4-stats-maternite, m2-stats-echographie, m5-stats-examens, m2-stats-consultations,
 * m3-stats-bloc, m3-stats-hospitalisations, m10-cout-agent, m12-rentabilite-groupes, m12-tableau-decisionnel.
 * -----------------------------------------------------------------------------
 *   node build/vecteurs-pilotage.js     (sous flock /tmp/sigh-banc.lock ; SIGH_PORT_PHP=<port inhabituel 106xx>)
 *
 * Le JEU du poste (apps/poste/assets/donnees/jeu) est posé dans le magasin de la maquette et l'horloge est décalée au 30/10/2026 10 h
 * (`_m12-outils.js`). Quatre registres du jeu sont VIDES (cpa, crAnesthesie, bulletins, tentativesConnexion) : le script en pose quelques fiches
 * (consignées sous `injections`, rejouées telles quelles par le test du domaine) pour que les écrans aient quelque chose à compter.
 * Sortie (ENGENDRÉE) : packages/domaine/test/vecteurs/pilotage.json
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');
const JEU_DIR = path.join(ROOT, '..', 'apps/poste/assets/donnees/jeu');
const NOMS = ['demandesAnalyses', 'patients', 'demandesImagerie', 'resultatsImagerie', 'consultations', 'personnel', 'crOperatoires', 'avances', 'factures', 'ecritures',
  'centresCouts', 'admissions', 'grossesses', 'accouchements', 'naissances', 'planificationFamiliale', 'registreSONU', 'soinsCuratifsMaternite', 'echeancesFiscales',
  'produits', 'lots', 'depenses', 'audit', 'actes', 'mouvements', 'administrations', 'planning', 'prescriptions', 'objectifsPilotage', 'facturesFournisseurs',
  'facturesMere', 'assureurs'];
const jeu = {};
NOMS.forEach((n) => { jeu[n] = JSON.parse(fs.readFileSync(path.join(JEU_DIR, n + '.json'), 'utf8')); });

(async () => {
  console.log('▶ Vecteurs du pilotage (PIL)');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(__dirname, '_m12-outils.js') });
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/dashboards.js') });
    const sortie = await m.page.evaluate(async (jeu) => {
      const S = SIGH.store, C = SIGH.core, K = SIGH.kit, PR = SIGH.parcours;
      const { propre, texte, dormir, db, releve, graphiques } = window.__O;
      const navigations = [];
      SIGH.app.go = (id) => { navigations.push(id); };
      const rep = {};

      /* ---------- le jeu du poste + les fiches posées sur les registres vides --------------------------------------------------------- */
      Object.keys(jeu).forEach((n) => { db()[n] = propre(jeu[n]); });
      const pat = jeu.patients.filter((p) => p.statut !== 'archive');
      const ops = jeu.crOperatoires.filter((r) => r.statut !== 'archive');
      const inj = {};
      inj.cpa = [
        { id: 'CPA-T1', patientId: ops[0].patientId, date: '2026-09-02', conclusion: 'Apte' },
        { id: 'CPA-T2', patientId: ops[1].patientId, date: '2026-09-20', conclusion: 'Apte avec réserves' },
        { id: 'CPA-T3', patientId: pat[0].id, date: '2026-10-05', conclusion: 'Apte' },
        { id: 'CPA-T4', patientId: pat[1].id, date: '2026-10-12' },
      ];
      inj.crAnesthesie = [
        { id: 'CRA-T1', patientId: ops[0].patientId, dateOperation: '2026-09-02', technique: 'Rachianesthésie', incidents: 'Aucun incident', decisionSortie: 'Retour en chambre' },
        { id: 'CRA-T2', patientId: ops[1].patientId, dateOperation: '2026-09-20', technique: 'Anesthésie générale', incidents: 'Hypotension transitoire', decisionSortie: 'Surveillance prolongée en salle de réveil' },
        { id: 'CRA-T3', patientId: pat[2].id, dateOperation: '2026-10-05', technique: 'Rachianesthésie', incidents: 'aucun', decisionSortie: 'Surveillance prolongée en salle de réveil' },
        { id: 'CRA-T4', patientId: pat[3].id, dateOperation: '2026-10-12', technique: 'Anesthésie locale', incidents: 'Désaturation brève' },
      ];
      const ag = jeu.personnel.filter((p) => p.statut !== 'archive' && p.salaireBase > 0);
      const agBas = ag.find((p) => p.salaireBase <= 60000) || ag[ag.length - 1];
      const agHaut = ag.find((p) => p.salaireBase > 60000) || ag[0];
      inj.bulletins = [
        { id: 'BUL-T1', personnelId: agHaut.id, annee: 2026, mois: 7, periode: 'Août 2026', brut: agHaut.salaireBase, net: Math.round(agHaut.salaireBase * 0.8) },
        { id: 'BUL-T2', personnelId: agHaut.id, annee: 2026, mois: 8, brut: agHaut.salaireBase, net: Math.round(agHaut.salaireBase * 0.81) },
        { id: 'BUL-T3', agentId: agHaut.id, date: '2026-10-01', periode: 'Octobre 2026', brut: agHaut.salaireBase, net: Math.round(agHaut.salaireBase * 0.82) },
        { id: 'BUL-T4', personnelId: agBas.id, annee: 2026, mois: 9, brut: agBas.salaireBase, net: Math.round(agBas.salaireBase * 0.8) },
      ];
      inj.tentativesConnexion = [{ id: 'TC1', motif: 'rôle archivé' }, { id: 'TC2', motif: 'rôle archivé' }, { id: 'TC3', motif: 'mot de passe' }];
      Object.keys(inj).forEach((n) => { db()[n] = propre(inj[n]); });
      rep.injections = inj;
      rep.agents = { bas: agBas.id, haut: agHaut.id };

      /* ---------- captation : classements (K.ranking) --------------------------------------------------------------------------------- */
      const classements = [];
      const rk = K.ranking;
      K.ranking = function (items, opts) { const r = rk.apply(this, arguments); classements.push({ items: propre(items), texte: texte(r) }); return r; };
      const vider = () => { graphiques.length = 0; classements.length = 0; };
      const lire = (root, extra) => {
        const r = releve(root);
        return Object.assign({
          kpis: r.kpis.map((k) => [k.label, k.valeur, k.indice]),
          graphiques: propre(graphiques), classements: propre(classements),
          tables: r.tables.map((t) => ({ titre: t.titre, entetes: t.entetes, lignes: t.lignes.map((l) => l.cellules), pied: t.pied })),
          cartes: r.cartes, notes: r.notes, boutons: r.boutons, onglets: r.onglets,
        }, extra || {});
      };
      const monter = async (id) => { vider(); return window.__O.monter(id); };
      const sel = (root) => [...root.querySelectorAll('select')];
      const dates = (root) => [...root.querySelectorAll('input[type=date]')];
      const poser = async (e, v) => {
        e.value = v; e.dispatchEvent(new Event('input', { bubbles: true })); e.dispatchEvent(new Event('change', { bubbles: true })); await dormir(120);
      };
      const options = (s) => [...s.options].map((o) => [o.value, texte(o)]);
      const bouton = (root, re) => window.__O.bouton(root, re);

      /* ---------- m5-stats-examens : les axes sont des FILTRES --------------------------------------------------------------------- */
      {
        const E = { scenarios: {} };
        const root = await monter('m5-stats-examens');
        const [sSer, sSex, sAge, sOri] = sel(root).slice(0, 4);
        const [dDeb, dFin] = dates(root);
        E.options = { service: options(sSer), sexe: options(sSex), age: options(sAge), origine: options(sOri) };
        E.defaut = lire(root);
        const svc = E.options.service.map((o) => o[0]).filter(Boolean);
        const etat = async (nom, f) => { vider(); await f(); vider(); await poser(dFin, dFin.value); E.scenarios[nom] = Object.assign({ filtres: { du: dDeb.value, au: dFin.value, service: sSer.value, sexe: sSex.value, age: sAge.value, origine: sOri.value } }, lire(root)); };
        for (const s of svc) await etat('service:' + s, async () => { await poser(sSer, s); });
        await poser(sSer, '');
        await etat('sexe:F', async () => { await poser(sSex, 'F'); });
        await etat('sexe:M', async () => { await poser(sSex, 'M'); });
        await poser(sSex, '');
        for (const a of E.options.age.map((o) => o[0]).filter(Boolean)) await etat('age:' + a, async () => { await poser(sAge, a); });
        await poser(sAge, '');
        await etat('origine:externe', async () => { await poser(sOri, 'externe'); });
        await etat('origine:interne', async () => { await poser(sOri, 'interne'); });
        await poser(sOri, '');
        await etat('plage:sept-oct', async () => { await poser(dDeb, '2026-09-01'); await poser(dFin, '2026-10-15'); });
        await etat('plage+sexe+origine', async () => { await poser(sSex, 'F'); await poser(sOri, 'interne'); });
        await etat('plage+age+service', async () => { await poser(sSex, ''); await poser(sOri, ''); await poser(sAge, '25-44'); await poser(sSer, svc[0]); });
        await etat('plage vide', async () => { await poser(sAge, ''); await poser(sSer, ''); await poser(dDeb, '2030-01-01'); await poser(dFin, '2030-02-01'); });
        E.libelles = [...root.querySelectorAll('label')].map(texte);
        rep.examens = E; root.remove();
      }

      /* ---------- m2-stats-echographie (imagerie médicale) ---------------------------------------------------------------------------- */
      {
        const root = await monter('m2-stats-echographie');
        rep.imagerie = { defaut: lire(root) }; root.remove();
        const sv = propre(db().resultatsImagerie), sd = propre(db().demandesImagerie);
        db().resultatsImagerie = []; db().demandesImagerie = [];
        const r2 = await monter('m2-stats-echographie'); rep.imagerie.vide = lire(r2); r2.remove();
        db().resultatsImagerie = sv; db().demandesImagerie = sd;
      }

      /* ---------- m2-stats-consultations / m3-stats-bloc / m12-rentabilite-groupes / m3-stats-hospitalisations : la plage de dates ------ */
      async function parPlage(id, plages, extraApres) {
        const out = { scenarios: {} };
        const root = await monter(id);
        const [dDeb, dFin] = dates(root);
        out.defaut = lire(root);
        for (const [nom, du, au] of plages) {
          vider(); await poser(dDeb, du); vider(); await poser(dFin, au);
          out.scenarios[nom] = Object.assign({ filtres: { du, au } }, lire(root, extraApres ? extraApres(root) : null));
        }
        vider(); await bouton(root, /Toute la période/).click(); await dormir(150);
        out.toutePeriode = lire(root);
        out.libelles = [...root.querySelectorAll('label')].map(texte);
        root.remove();
        return out;
      }
      const PLAGES = [['septembre', '2026-09-01', '2026-09-30'], ['octobre', '2026-10-01', '2026-10-31'], ['depuis-aout', '2026-08-01', ''], ['jusqu-a-juillet', '', '2026-07-31'],
        ['jour', '2026-10-12', '2026-10-12'], ['vide', '2030-01-01', '2030-12-31'], ['inversee', '2026-10-31', '2026-10-01']];
      rep.consultations = await parPlage('m2-stats-consultations', PLAGES);
      rep.bloc = await parPlage('m3-stats-bloc', PLAGES);
      rep.rentabilite = await parPlage('m12-rentabilite-groupes', PLAGES);
      rep.hospitalisations = await parPlage('m3-stats-hospitalisations', PLAGES);
      {
        const root = await monter('m3-stats-hospitalisations');
        const pa = window.__O.pieces.length;
        await window.__O.cliquer(root, /Éditer l’état/);
        rep.hospitalisations.piece = window.__O.pieces.length > pa ? window.__O.pieces[window.__O.pieces.length - 1] : null;
        root.remove();
      }
      {
        // brouillons écartés et charges non imputées : une écriture de classe 6 sans centre et un brouillon
        const sv = propre(db().ecritures);
        db().ecritures.push({ id: 'ECR-T1', numero: 'OD-T-1', date: '2026-10-10', compte: '601000', statut: 'validee', debit: 12345, credit: 0, libelle: 'test' });
        db().ecritures.push({ id: 'ECR-T2', numero: 'OD-T-2', date: '2026-10-11', compte: '604000', statut: 'brouillon', debit: 999, credit: 0, centreCout: 'laboratoire' });
        db().ecritures.push({ id: 'ECR-T3', numero: 'OD-T-3', date: '2026-10-12', compte: '641000', statut: 'validee', debit: 0, credit: 2000, centreCout: 'maternite' });
        const root = await monter('m12-rentabilite-groupes');
        rep.rentabilite.synthetique = lire(root); root.remove();
        db().ecritures = sv;
      }

      /* ---------- m10-cout-agent --------------------------------------------------------------------------------------------------------- */
      {
        const out = { scenarios: {} };
        let combo = null; const cb = SIGH.ui.combo;
        SIGH.ui.combo = function () { combo = cb.apply(this, arguments); return combo; };
        const root = await monter('m10-cout-agent');
        SIGH.ui.combo = cb;
        out.defaut = lire(root);
        const [dDeb, dFin] = dates(root);
        const choisir = async (id) => { combo.value = id; combo.dispatchEvent(new Event('change', { bubbles: true })); await dormir(150); };
        const tous = db().personnel.filter((p) => p.statut !== 'archive');
        const echant = [agHaut.id, agBas.id, tous.find((p) => !p.salaireBase) && tous.find((p) => !p.salaireBase).id, tous.find((p) => p.salaireBase === 60000) && tous.find((p) => p.salaireBase === 60000).id].filter(Boolean);
        for (const id of echant) { vider(); await choisir(id); out.scenarios['agent:' + id] = lire(root); }
        vider(); await choisir(agHaut.id);
        await poser(dDeb, '2026-09-01'); vider(); await poser(dFin, '2026-10-31'); out.scenarios['plage'] = lire(root);
        await poser(dDeb, '2026-10-01'); vider(); await poser(dFin, '2026-10-31'); out.scenarios['octobre'] = lire(root);
        out.agentsEntrees = tous.map((p) => ({ id: p.id, nomComplet: p.nomComplet, poste: p.poste || '', salaireBase: p.salaireBase || 0 })).slice(0, 5);
        out.libelles = [...root.querySelectorAll('label')].map(texte);
        out.paramPaie = propre(SIGH.data.PARAM_PAIE);
        // avances : une note
        db().avances.push({ id: 'AV-T', personnelId: agHaut.id, montant: 1000 });
        vider(); await choisir(agBas.id); await choisir(agHaut.id); out.scenarios['avecAvances'] = lire(root);
        root.remove();
        rep.coutAgent = out;
      }

      /* ---------- m4-stats-maternite -------------------------------------------------------------------------------------------------- */
      {
        const root = await monter('m4-stats-maternite');
        rep.maternite = { defaut: lire(root) }; root.remove();
        for (const n of ['grossesses', 'accouchements', 'naissances', 'planificationFamiliale', 'registreSONU', 'soinsCuratifsMaternite']) {
          const sv = propre(db()[n]); db()[n] = [];
          const r2 = await monter('m4-stats-maternite'); (rep.maternite.sans = rep.maternite.sans || {})[n] = lire(r2); r2.remove(); db()[n] = sv;
        }
      }

      /* ---------- m12-tableau-decisionnel et le moteur d'indicateurs ------------------------------------------------------------------ */
      {
        const out = { moteur: {} };
        const ind = (o) => propre(PR.indicateursPilotage(o));
        out.moteur.defaut = ind(); out.moteur.j30 = ind({ fin: '2026-10-30', jours: 30 }); out.moteur.j180 = ind({ fin: '2026-10-30', jours: 180 });
        out.moteur.aout = ind({ fin: '2026-08-16', jours: 90 }); out.moteur.futur = ind({ fin: '2027-03-01', jours: 90 });
        out.moteur.sansCA = ind({ fin: '2024-01-01', jours: 30 });
        out.moteur.sorties = { j90: PR.sortiesValorisees(PR.fenetrePilotage()), j30: PR.sortiesValorisees(PR.fenetrePilotage({ jours: 30 })) };
        out.moteur.delaiTransmission = PR.delaiTransmission();
        {
          const sv = propre(db().objectifsPilotage);
          db().objectifsPilotage = [];
          out.moteur.semence = ind();
          db().objectifsPilotage = sv;
          const o = db().objectifsPilotage.find((x) => x.id === 'dso');
          const avant = propre(o);
          o.cible = 300; o.alerte = 500; o.aValider = false; o.arreteLe = '2026-10-30';
          out.moteur.dsoArrete = ind();
          o.cible = 1; o.alerte = 2;
          out.moteur.dsoAlerte = ind();
          Object.keys(o).forEach((k) => delete o[k]); Object.assign(o, avant);
        }
        const sb = propre(db().factures); db().factures = [];
        out.moteur.sansFactures = ind(); db().factures = sb;
        const sa = propre(db().admissions); db().admissions = [];
        out.moteur.sansAdmissions = ind(); db().admissions = sa;
        out.objectifs = propre(PR.objectifsPilotage());
        out.axes = propre(SIGH.data.AXES_PILOTAGE);
        out.alertes = propre(PR.alertesRecouvrement());
        const root = await monter('m12-tableau-decisionnel');
        out.grille = lire(root);
        out.grilleBoutons = [...root.querySelectorAll('button')].map(texte).filter(Boolean);
        const pa = window.__O.pieces.length;
        await window.__O.cliquer(root, /Imprimer la grille/);
        out.piece = window.__O.pieces.length > pa ? window.__O.pieces[window.__O.pieces.length - 1] : null;
        await window.__O.onglet(root, /Objectifs & seuils/);
        out.objectifsEcran = lire(root);
        root.remove();
        // objectif sans donnée : « non calculable » n'est pas zéro
        const sf = propre(db().factures); db().factures = [];
        const r2 = await monter('m12-tableau-decisionnel'); out.sansFactures = lire(r2); r2.remove(); db().factures = sf;
        rep.decisionnel = out;
      }

      /* ---------- dash-admin ---------------------------------------------------------------------------------------------------------- */
      {
        const root = await monter('dash-admin');
        rep.admin = { defaut: lire(root), premierRegard: texte(root).slice(0, 400), texte: texte(root).slice(0, 2500) };
        rep.admin.constantes = { analyses: SIGH.data.ANALYSES.length, assureurs: SIGH.data.ASSUREURS.length, plan: SIGH.data.PLAN_COMPTABLE.length };
        root.remove();
        const sv = propre(db().tentativesConnexion); db().tentativesConnexion = [];
        const r2 = await monter('dash-admin'); rep.admin.sansTentatives = lire(r2, { texte: texte(r2).slice(0, 400) }); r2.remove(); db().tentativesConnexion = sv;
      }

      /* ---------- dash-direction ------------------------------------------------------------------------------------------------------ */
      {
        const root = await monter('dash-direction');
        rep.direction = { defaut: lire(root, { texte: texte(root).slice(0, 3500) }) };
        const pa = window.__O.pieces.length;
        const actions = SIGH.screens['dash-direction'].actions();
        actions[0].click(); await dormir(200);
        rep.direction.piece = window.__O.pieces.length > pa ? window.__O.pieces[window.__O.pieces.length - 1] : null;
        rep.direction.navigations = [];
        for (const re of [/Voir les échéances/, /Tableau décisionnel/, /Détail du BFR/]) {
          const b = bouton(root, re); const n0 = navigations.length;
          if (b) { b.click(); await dormir(50); }
          rep.direction.navigations.push(b ? (navigations[n0] || null) : null);
        }
        root.remove();
        const sv = propre(db().echeancesFiscales); db().echeancesFiscales.forEach((e) => { e.paye = true; });
        const r2 = await monter('dash-direction'); rep.direction.sansEcheance = { texte: texte(r2).slice(0, 500) }; r2.remove(); db().echeancesFiscales = sv;
        const sp = propre(db().produits), sl = propre(db().lots);
        db().produits.forEach((p) => { p.stock = (p.seuilAlerte || 0) + 5; }); db().lots.forEach((l) => { l.statut = 'valide'; });
        const r3 = await monter('dash-direction'); rep.direction.sansAlerte = { texte: texte(r3).slice(0, 800), kpis: lire(r3).kpis }; r3.remove(); db().produits = sp; db().lots = sl;
      }

      /* ---------- dash-da ------------------------------------------------------------------------------------------------------------ */
      {
        const out = { onglets: {} };
        const root = await monter('dash-da');
        out.defaut = lire(root, { texte: texte(root).slice(0, 4000) });
        const [pDeb, pFin] = dates(root);
        const zone = async (nom, du, au) => { await poser(pDeb, du); vider(); await poser(pFin, au); return lire(root, { texte: texte(root).slice(0, 1500) }); };
        out.plage = { sept: await zone('s', '2026-09-01', '2026-09-30'), tout: await zone('t', '2026-01-01', '2026-12-31'), vide: await zone('v', '2030-01-01', '2030-02-01') };
        await poser(pDeb, ''); await poser(pFin, '');
        const ancres = { jour: ['2026-10-30', '2026-08-14', '2026-08-13', '2026-09-30'], semaine: ['2026-10-30', '2026-08-12', '2026-08-05'], mois: ['0', '2', '5', '7', '8', '9'], trimestre: ['0', '3', '6', '9'],
          semestre: ['0', '6'], annee: ['2024', '2025', '2026', '2027'] };
        const bts = [...root.querySelectorAll('button.tab')];
        for (const b of bts) {
          const code = Object.keys(ancres)[bts.indexOf(b)];
          b.click(); await dormir(200);
          const unites = {};
          for (const a of ancres[code]) {
            vider();
            const portee = root;
            const ctrl = [...portee.querySelectorAll('.card-body select.input, .card-body input[type=date]')].filter((x) => !(x.type === 'date' && (x === pDeb || x === pFin))).pop();
            if (!ctrl) throw new Error('sélecteur de période introuvable : ' + code);
            await poser(ctrl, a);
            const r = lire(root, { texte: texte(root).slice(0, 1800) });
            unites[a] = { note: r.notes.find((x) => /Période retenue/.test(x)) || null, tables: r.tables.filter((t) => /grandeur|période/i.test((t.entetes || []).join(' '))), graphiques: r.graphiques, cartes: r.cartes };
          }
          out.onglets[code] = { options: (() => { const s = [...root.querySelectorAll('.card-body select.input')].pop(); return s ? options(s) : null; })(), unites };
        }
        out.onglets.libelles = bts.map(texte);
        root.remove();
        rep.da = out;
      }

      /* ---------- dash-croise : sources × axes × mesures × périodes ------------------------------------------------------------------------- */
      {
        const out = { sources: {} };
        const root = await monter('dash-croise');
        const selects = () => sel(root);
        const srcSel = () => selects()[0];
        out.sourcesOptions = options(srcSel());
        out.defaut = lire(root);
        for (const [code] of out.sourcesOptions) {
          vider(); await poser(srcSel(), code);
          const s = selects();
          const S1 = { axes: options(s[1]), mesures: options(s[3]), periodes: options(s[4]), defaut: lire(root, { table: lireCroise(root), choix: s.map((x) => x.value) }), combos: {}, mesuresLues: {}, periodesLues: {} };
          const axes = S1.axes.map((o) => o[0]);
          vider(); await poser(selects()[4], 'tout');
          S1.toutDefaut = lire(root, { table: lireCroise(root), choix: selects().map((x) => x.value) });
          const combos = [];
          axes.forEach((a, i) => { combos.push([a, '']); combos.push([a, axes[(i + 1) % axes.length]]); });
          for (const [l, c] of combos) {
            if (l === c) continue;
            vider(); await poser(selects()[1], l); vider(); await poser(selects()[2], c);
            S1.combos[l + '|' + c] = lire(root, { table: lireCroise(root) });
          }
          await poser(selects()[1], axes[0]); await poser(selects()[2], axes[1] || '');
          for (const [mv] of S1.mesures) { vider(); await poser(selects()[3], mv); S1.mesuresLues[mv] = lire(root, { table: lireCroise(root) }); }
          await poser(selects()[3], S1.mesures[0][0]);
          for (const [pv] of S1.periodes) { vider(); await poser(selects()[4], pv); S1.periodesLues[pv] = lire(root, { table: lireCroise(root) }); }
          await poser(selects()[4], 'mois');
          out.sources[code] = S1;
        }
        root.remove();
        rep.croise = out;
      }
      function lireCroise(root) {
        const cartes = [...root.querySelectorAll('.card')];
        const c = cartes.find((x) => x.querySelector('table'));
        if (!c) return null;
        const t = c.querySelector('table');
        return { titre: texte(c.querySelector('.card-title')), entetes: [...t.querySelectorAll('thead th')].map(texte), lignes: [...t.querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('td')].map(texte)) };
      }
      rep.navigations = navigations.length;
      return rep;
    }, jeu);
    ecrire('packages/domaine/test/vecteurs/pilotage.json', sortie);
    const taille = JSON.stringify(sortie).length;
    console.log('  vecteurs : ' + Math.round(taille / 1024) + ' Ko — erreurs JS : ' + m.erreurs.length);
    m.erreurs.slice(0, 5).forEach((e) => console.log('   ! ' + e));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
