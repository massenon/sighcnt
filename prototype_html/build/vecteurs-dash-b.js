/* =============================================================================
 * VECTEURS DES TABLEAUX DE BORD « B » — dash-ambulancier, dash-aide-soignant, dash-echographiste, dash-surveillant, dash-assistant-comptable,
 * dash-chirurgien, dash-anesthesiste, dash-aide-comptable, dash-maternite, dash-patient, tirés des ÉCRANS RÉELS pilotés dans Chrome.
 * -----------------------------------------------------------------------------
 *   node build/vecteurs-dash-b.js      (sous flock /tmp/sigh-banc.lock ; SIGH_PORT_PHP=<port inhabituel 105xx>)
 *
 * Le JEU du poste est posé dans le magasin de la maquette, l'horloge est décalée au 30/10/2026 10 h (`_m12-outils.js`). Chaque tableau est monté
 * sous son propre rôle ET sous un rôle qui n'en a pas l'usage (les étapes de parcours fermées au profil doivent rester visibles mais non cliquables).
 * Sortie (ENGENDRÉE) : packages/domaine/test/vecteurs/tbb_dash.json
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');
const JEU_DIR = path.join(ROOT, '..', 'apps/poste/assets/donnees/jeu');
const NOMS = ['checklistsBloc', 'crOperatoires', 'admissions', 'ecritures', 'factures', 'ambulance', 'consultations', 'releves', 'visitesHospi', 'examensImagerie',
  'resultatsImagerie', 'presences', 'planning', 'conges', 'personnel', 'echeancesFiscales', 'produits', 'partogrammes', 'dossiersObstetricaux',
  'accouchements', 'naissances', 'patients', 'chambres', 'lits'];
const jeu = {};
NOMS.forEach((n) => {
  const f = path.join(JEU_DIR, n + '.json');
  jeu[n] = fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, 'utf8')) : null;
});

const ECRANS = [
  ['dash-ambulancier', 'ambulancier'], ['dash-aide-soignant', 'aide_soignant'], ['dash-echographiste', 'echographiste'],
  ['dash-surveillant', 'surveillant'], ['dash-assistant-comptable', 'assistant_comptable'], ['dash-chirurgien', 'chirurgien'],
  ['dash-anesthesiste', 'anesthesiste'], ['dash-aide-comptable', 'aide_comptable'], ['dash-maternite', 'infirmier'], ['dash-patient', 'reception'],
];

(async () => {
  console.log('▶ Vecteurs des tableaux de bord B');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(__dirname, '_m12-outils.js') });
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/dashboards.js') });
    const sortie = await m.page.evaluate(async ([jeu, ecrans]) => {
      const S = SIGH.store, O = window.__O;
      const { propre, texte, dormir, db } = O;
      const poserJeu = () => {
        Object.keys(jeu).forEach((n) => {
          if (jeu[n] === null) { try { db()[n] = []; } catch (e) { /* absent */ } return; }
          db()[n] = propre(jeu[n]);
        });
      };
      poserJeu();
      const sessionReelle = S.session;
      const sous = (role) => { S.session = () => Object.assign({}, sessionReelle() || {}, { role }); };
      const idDe = (href) => { const x = /([A-Za-z0-9_-]+)\.(?:php|html)(?:[#?].*)?$/.exec(href || ''); return x ? x[1] : href; };

      function lire(root) {
        const hote = root.firstElementChild;
        const ordre = [...hote.children].map((c) => {
          const t = c.querySelector(':scope > .card-header .card-title, :scope .card-title');
          if (c.textContent.indexOf('À regarder en premier') >= 0 && !c.classList.contains('card')) return 'PREMIER_REGARD';
          if (c.classList.contains('kpi-grid') || c.querySelector('.kpi') && !c.classList.contains('card')) return 'KPI';
          return t ? texte(t) : (c.tagName + '.' + [...c.classList].slice(0, 2).join('.'));
        });
        const pr = [...hote.children].find((c) => c.textContent.indexOf('À regarder en premier') >= 0 && !c.classList.contains('card'));
        let premier = null;
        if (pr) {
          const ps = [...pr.querySelectorAll('p')].map(texte);
          const a = pr.querySelector('a');
          premier = { ton: (/border-(\w+)-200/.exec(pr.className) || [])[1], ligne: ps[1], note: ps[2] || null,
            lien: a ? { texte: texte(a), ecran: idDe(a.getAttribute('href')) } : null };
        }
        const parcours = [...root.querySelectorAll('ol')].map((ol) => {
          const carte = ol.parentElement;
          const tete = carte.firstElementChild;
          const ps = [...tete.querySelectorAll('p')].map(texte);
          const etapes = [...ol.children].map((li) => {
            const corps = li.lastElementChild;
            const a = corps.querySelector('a');
            const spans = [...corps.children].filter((x) => x !== a).map(texte);
            const detail = [...corps.querySelectorAll(':scope > span.block')].map(texte)[0] || null;
            return { num: texte(li.firstElementChild), label: a ? texte(a) : texte(corps.firstElementChild),
              ecran: a ? idDe(a.getAttribute('href')) : null, spans: spans.filter((s) => s && s !== detail), detail };
          });
          const b = carte.querySelector(':scope > div.mt-3 a');
          return { titre: ps[0], detail: ps[1] || null, etapes, bouton: b ? { texte: texte(b), ecran: idDe(b.getAttribute('href')) } : null };
        });
        const raccourcis = [...root.querySelectorAll('a.group')].map((a) => ({ ecran: idDe(a.getAttribute('href')),
          libelle: texte(a.querySelector('.text-sm')), detail: a.querySelector('.text-xs') ? texte(a.querySelector('.text-xs')) : null }));
        const rel = O.releve(root);
        const tables = rel.tables;
        const vides = [...root.querySelectorAll('.card')].filter((c) => !c.querySelector('table') && c.querySelector('.card-title') &&
          /^Aucun/.test(texte(c.querySelector('.card-body')))).map((c) => [texte(c.querySelector('.card-title')), texte(c.querySelector('.card-body'))]);
        const liens = [...root.querySelectorAll('.card-header a, .card-header button')].map((b) => [texte(b), b.getAttribute('href') ? idDe(b.getAttribute('href')) : null]);
        return { ordre, premier, parcours, raccourcis, kpis: rel.kpis, tables, cartes: rel.cartes, notes: rel.notes, vides, liens,
          classement: [...root.querySelectorAll('.card')].filter((c) => c.querySelector('.h-1\\.5') && !c.querySelector('table'))
            .map((c) => [texte(c.querySelector('.card-title')), [...c.querySelectorAll('.card-body > .space-y-2\\.5 > div')].map(texte)]),
          texteBrut: texte(root) };
      }

      const R = {};
      for (const [id, roleProprio] of ecrans) {
        R[id] = {};
        for (const role of [roleProprio, 'caissier', 'admin']) {
          if (R[id][role]) continue;
          sous(role);
          O.graphiques.length = 0; O.alertes.length = 0;
          try { sessionStorage.clear(); } catch (e) { /* sans effet */ }
          const racine = await O.monter(id);
          const r = lire(racine);
          r.graphiques = propre(O.graphiques); r.alertes = propre(O.alertes);
          R[id][role] = r;
          racine.remove();
        }
        R[id]._proprio = roleProprio;
      }

      /* ---- dash-patient : le sélecteur de patient et la fiche remise ---------------------------------------------------------------- */
      sous('reception');
      const P = { patients: [], pieces: [] };
      const racine = await O.monter('dash-patient');
      const pats = SIGH.store.collection('patients').active().map((p) => ({ id: p.id, code: p.code, nom: p.nom, prenom: p.prenom, quartier: p.quartier }));
      pats.sort((a, b) => String(a.code).localeCompare(String(b.code)));
      const combo = racine.querySelector('[role=combobox], .combo') || racine.querySelector('.card-body > div > *:nth-child(2)');
      const lus = [];
      const echantillon = [pats[0], pats[1], pats[Math.floor(pats.length / 2)], pats[pats.length - 1]];
      for (const p of echantillon) {
        const sel = racine.querySelector('.max-w-md');
        sel.value = p.id; sel.dispatchEvent(new Event('change', { bubbles: true })); await dormir(250);
        const vue = lire(racine);
        O.pieces.length = 0;
        const bouton = O.bouton(racine, /Remettre la fiche/);
        if (bouton) { bouton.click(); await dormir(300); }
        lus.push({ patient: p, kpis: vue.kpis, texteBrut: vue.texteBrut, boutons: O.releve(racine).boutons, piece: propre(O.pieces[0] || null),
          fil: [...racine.querySelectorAll('.card')].filter((c) => /Parcours de soins/.test(texte(c.querySelector('.card-title') || c))).map((c) => texte(c.querySelector('.card-body')))[0] });
        O.fermerDialogues();
      }
      P.patients = pats.length; P.echantillon = lus;
      racine.remove();
      R['dash-patient']._selection = P;

      /* ---- le jeu ENRICHI : des fiches synthétiques du jour (le jeu est daté d'août, la plupart des compteurs « du jour » y valent 0) ------ */
      const AJOUTS = {
        ambulance: [
          { id: 'AMB-T1', statut: 'actif', etat: 'demandee', dateHeure: '2026-10-12T08:00:00', kilometrage: 40, patient: 'T1' },
          { id: 'AMB-T2', statut: 'actif', etat: 'demandee', dateHeure: '2026-09-30T08:00:00', kilometrage: 10, patient: 'T2' },
          { id: 'AMB-T3', statut: 'actif', etat: 'en_cours', dateHeure: '2026-10-29T22:00:00', kilometrage: 25, patient: 'T3' },
          { id: 'AMB-T4', statut: 'actif', etat: 'terminee', dateHeure: '2026-10-05T10:00:00', kilometrage: 70, patient: 'T4' },
          { id: 'AMB-T5', statut: 'archive', etat: 'demandee', dateHeure: '2026-10-20T10:00:00', kilometrage: 99, patient: 'T5' },
        ],
        admissions: [
          { id: 'ADM-T1', statut: 'en_cours', dateEntree: '2026-10-20', patient: 'T1', patientId: 'PAT0001' },
          { id: 'ADM-T2', statut: 'en_cours', dateEntree: '2026-10-10', dateSortie: '2026-10-29', patient: 'T2', patientId: 'PAT0010' },
        ],
        releves: [
          { id: 'REL-T1', statut: 'actif', admissionId: 'ADM-T1', date: '2026-10-30', heure: '08:00', temperature: 37.1 },
          { id: 'REL-T2', statut: 'actif', admissionId: 'ADM-T1', date: '2026-10-30', heure: '14:00', temperature: 37.4 },
          { id: 'REL-T3', statut: 'actif', admissionId: 'ADM-T1', date: '2026-10-29', heure: '14:00', temperature: 37.4 },
        ],
        visitesHospi: [
          { id: 'VIS-T1', statut: 'actif', date: '2026-10-30', heure: '15:00', patient: 'T1', visiteur: 'Famille' },
          { id: 'VIS-T2', statut: 'actif', date: '2026-10-29', heure: '15:00', patient: 'T1', visiteur: 'Famille' },
        ],
        presences: [
          { id: 'PRS-T1', statut: 'actif', date: '2026-10-30', employeId: 'EMP01', employe: 'T1', etat: 'retard' },
          { id: 'PRS-T2', statut: 'actif', date: '2026-10-30', employeId: 'EMP02', employe: 'T2', etat: 'present' },
          { id: 'PRS-T3', statut: 'actif', date: '2026-10-30', employeId: 'EMP03', employe: 'T3', etat: 'retard' },
          { id: 'PRS-T4', statut: 'actif', date: '2026-10-29', employeId: 'EMP04', employe: 'T4', etat: 'retard' },
        ],
        planning: [
          { id: 'PLN-T1', statut: 'validee', date: '2026-10-30', employeId: 'EMP01', employe: 'T1', type: 'garde' },
          { id: 'PLN-T2', statut: 'validee', date: '2026-10-30', employeId: 'EMP02', employe: 'T2', type: 'permanence' },
        ],
        conges: [
          { id: 'CNG-T1', statut: 'actif', employeId: 'EMP01', employe: 'T1', dateDebut: '2026-10-28', dateFin: '2026-11-02', statutConge: 'valide' },
          { id: 'CNG-T2', statut: 'actif', employeId: 'EMP02', employe: 'T2', dateDebut: '2026-10-28', dateFin: '2026-11-02', statutConge: 'en_attente' },
          { id: 'CNG-T3', statut: 'actif', employeId: 'EMP03', employe: 'T3', dateDebut: '2026-10-01', dateFin: '2026-10-10', statutConge: 'valide' },
        ],
        checklistsBloc: [
          { id: 'CKL-T1', statut: 'actif', moment: 'entree', coches: 3, total: 10, patient: 'T1' },
          { id: 'CKL-T2', statut: 'actif', moment: 'sortie', coches: 5, total: 10, patient: 'T2' },
          { id: 'CKL-T3', statut: 'actif', moment: 'entree', coches: 10, total: 10, patient: 'T3' },
        ],
        crOperatoires: [
          { id: 'CRO-T1', statut: 'actif', dateOperation: '2026-10-12', anesthesie: 'Anesthésie générale', aideOperateur: 'X', patient: 'T1' },
          { id: 'CRO-T2', statut: 'actif', dateOperation: '2026-10-15', anesthesie: 'Rachianesthésie', patient: 'T2' },
          { id: 'CRO-T3', statut: 'actif', dateOperation: '2026-10-28', anesthesie: 'Anesthésie générale', aideOperateur: 'Y', patient: 'T3' },
          { id: 'CRO-T4', statut: 'actif', dateOperation: '2026-09-28', anesthesie: 'Anesthésie générale', patient: 'T4' },
        ],
        ecritures: [
          { id: 'ECR-T1', statut: 'brouillon', date: '2026-10-30', numero: 'T1', compte: '571000' },
          { id: 'ECR-T2', etat: 'brouillon', statut: 'valide', date: '2026-10-29', numero: 'T2', compte: '571000' },
          { id: 'ECR-T3', statut: 'valide', date: '2026-10-29', numero: 'T3', compte: '571000' },
        ],
        factures: [
          { id: 'FAC-T1', statut: 'actif', date: '2026-10-30', numero: 'T1', montantTTC: 10000, montantPaye: 5000, partAssurance: 3000, reliquat: 1000, statutPaiement: 'partielle' },
          { id: 'FAC-T2', statut: 'actif', date: '2026-10-30T09:00:00', numero: 'T2', montantTTC: 4000, montantPaye: 4000, partAssurance: 0, reliquat: 0, statutPaiement: 'soldee' },
          { id: 'FAC-T3', statut: 'actif', date: '2026-10-29', numero: 'T3', montantTTC: 4000, montantPaye: 1000, partAssurance: 2000, reliquat: 500, statutPaiement: 'impayee' },
          { id: 'FAC-T4', statut: 'actif', date: '2026-10-29', numero: 'T4', montantTTC: 4000, montantPaye: 4000, partAssurance: 2000, reliquat: 0, statutPaiement: 'soldee' },
        ],
        produits: [
          { id: 'PRD-T1', statut: 'actif', designation: 'T1', famille: 'Réactifs', seuilAlerte: 5, stock: 2 },
          { id: 'PRD-T2', statut: 'actif', designation: 'T2', famille: 'reactif', seuilAlerte: 5, stock: 50 },
          { id: 'PRD-T3', statut: 'actif', designation: 'T3', famille: 'Réactifs', stock: 0 },
        ],
        resultatsImagerie: [
          { id: 'IMG-T1', statut: 'brouillon', date: '2026-10-29T10:00:00', examen: 'T1' },
          { id: 'IMG-T2', statut: 'rendu', date: '2026-10-30T10:00:00', examen: 'T2' },
        ],
        accouchements: [
          { id: 'ACC-T1', statut: 'actif', dateHeure: '2026-10-20T10:00:00', type: 'Eutocique', patient: 'T1' },
          { id: 'ACC-T2', statut: 'actif', dateHeure: '2026-10-21T10:00:00', type: 'Dystocique', patient: 'T2' },
          { id: 'ACC-T3', statut: 'actif', dateHeure: '2026-10-22T10:00:00', type: 'Eutocique', patient: 'T3' },
        ],
        naissances: [
          { id: 'NAI-T1', statut: 'actif', dateHeure: '2026-10-20T10:00:00', vivant: true, mere: 'T1' },
          { id: 'NAI-T2', statut: 'actif', dateHeure: '2026-10-21T10:00:00', vivant: true, mere: 'T2' },
          { id: 'NAI-T3', statut: 'actif', dateHeure: '2026-10-22T10:00:00', vivant: false, mere: 'T3' },
        ],
      };
      poserJeu();
      Object.keys(AJOUTS).forEach((n) => {
        const base = db()[n] || [];
        db()[n] = base.concat(propre(AJOUTS[n]));
      });
      for (const [id, roleProprio] of ecrans) {
        if (id === 'dash-patient') continue;
        sous(roleProprio);
        O.graphiques.length = 0; O.alertes.length = 0;
        try { sessionStorage.clear(); } catch (e) { /* sans effet */ }
        const racine = await O.monter(id);
        const r = lire(racine);
        r.graphiques = propre(O.graphiques); r.alertes = propre(O.alertes);
        R[id]._enrichi = r;
        racine.remove();
      }
      R._ajouts = AJOUTS;

      /* ---- règles de lecture que les tableaux appliquent : sondes directes sur le magasin ----------------------------------------------- */
      const C = SIGH.core;
      const stat = {
        auj: C.iso(new Date()),
        checklistsIncompletes: S.collection('checklistsBloc').active().filter((c) => (c.coches || 0) < (c.total || 0)).length,
        checklistsEntree: S.collection('checklistsBloc').active().filter((c) => c.moment === 'entree' && (c.coches || 0) < (c.total || 0)).length,
      };
      R._stat = stat;
      return R;
    }, [jeu, ECRANS]);
    sortie._doc = 'ENGENDRÉ par prototype_html/build/vecteurs-dash-b.js — ne pas éditer. Horloge : 30/10/2026 10 h. Jeu : apps/poste/assets/donnees/jeu.';
    if (m.erreurs.length) console.log('  (erreurs de page : ' + m.erreurs.length + ') ' + m.erreurs.slice(0, 3).join(' | '));
    ecrire('packages/domaine/test/vecteurs/tbb_dash.json', sortie);
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
