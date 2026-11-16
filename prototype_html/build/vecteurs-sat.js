/* =============================================================================
 * VECTEURS DE LA SATISFACTION EN LIGNE (lot SAT, ADR-0009) : l'écran RÉEL adm-satisfaction (carte « Analyse » et ses filtres) et adm-enquetes
 * (versions datées du questionnaire, point de collecte, partage « En ligne ») pilotés comme le fait l'agent.
 *   node build/vecteurs-sat.js   →   packages/domaine/test/vecteurs/satisfaction_en_ligne.json
 * L'horloge est fixée au 16/08/2026 10 h : `C.aujourdhui()` ET `new Date()`.
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs satisfaction en ligne');
  const m = await ouvrirMaquette();
  try {
    await m.page.evaluate(() => {
      SIGH.core.aujourdhui = () => new Date(2026, 7, 16, 10, 0, 0);
      const Vrai = Date;
      const FIXE = new Vrai(2026, 7, 16, 10, 0, 0).getTime();
      class Faux extends Vrai { constructor(...a) { if (a.length === 0) super(FIXE); else super(...a); } static now() { return FIXE; } }
      window.Date = Faux;
      window.__etats = [];
      SIGH.print.etat = function (o) {
        const tab = [];
        let c = o.contenu;
        if (typeof c === 'string') { const d = document.createElement('div'); d.innerHTML = c; c = d; }
        if (c && c.querySelectorAll) {
          (c.tagName === 'TABLE' ? [c] : [...c.querySelectorAll('table')]).forEach((t) => tab.push({
            entetes: [...t.querySelectorAll('thead th')].map((x) => x.innerText.replace(/\s+/g, ' ').trim()),
            lignes: [...t.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => td.innerText.replace(/\s+/g, ' ').trim())),
            pied: [...t.querySelectorAll('tfoot tr')].map((tr) => [...tr.children].map((td) => td.innerText.replace(/\s+/g, ' ').trim())),
          }));
        }
        window.__etats.push(JSON.parse(JSON.stringify({ titre: o.titre, sousTitre: o.sousTitre || null, cartouche: o.cartouche || null, signatures: o.signatures || null, tableaux: tab })));
      };
    });
    for (const f of ['m13-administration.js', 'ged.js']) await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules', f) });

    const sortie = await m.page.evaluate(async () => {
      const S = SIGH.store, C = SIGH.core;
      const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x, (k, v) => (v === undefined ? null : v)));
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const norm = (t) => String(t || '').replace(/\s+/g, ' ').trim();
      const nettoyer = () => { document.querySelectorAll('.modal-root, [role=dialog]').forEach((e) => e.remove()); document.querySelectorAll('#toast-host > div').forEach((e) => e.remove()); };
      const monter = async (id) => { const root = document.createElement('div'); document.body.appendChild(root); SIGH.screens[id].render(root); await dormir(80); return root; };
      const kpis = (root) => [...root.querySelectorAll('.kpi')].map((k) => ({ label: norm(k.querySelector('.kpi-label').textContent), valeur: norm(k.querySelector('.kpi-value').textContent), indice: norm((k.querySelector('.kpi-value').nextElementSibling || {}).textContent) }));
      const lignesTable = (racine, n) => [...racine.querySelectorAll('tbody tr')].slice(0, n || 400).map((tr) => [...tr.children].map((td) => norm(td.textContent)));
      const entetes = (racine) => [...racine.querySelectorAll('thead th')].map((th) => norm(th.textContent));
      const bouton = (portee, libelle) => [...portee.querySelectorAll('button')].find((b) => norm(b.textContent) === libelle || b.getAttribute('aria-label') === libelle || b.title === libelle);
      const dernierBouton = (libelle) => [...document.querySelectorAll('button')].filter((b) => norm(b.textContent) === libelle).pop();
      const poser = (id, v) => { const e = document.getElementById('f_' + id); if (!e) throw new Error('champ ' + id + ' ; présents : ' + [...document.querySelectorAll('[id^=f_]')].map((x) => x.id).join(',')); e.value = v; e.dispatchEvent(new Event('input')); e.dispatchEvent(new Event('change')); };
      const toasts = () => [...document.querySelectorAll('#toast-host > div')].map((t) => norm((t.querySelector('p') || {}).textContent));
      const graphique = (carte) => { const cv = carte && carte.querySelector('canvas'); const ch = cv && Chart.getChart(cv); return ch ? { etiquettes: ch.data.labels, series: ch.data.datasets.map((d) => ({ label: d.label, data: d.data })) } : null; };
      const carteNommee = (root, titre) => [...root.querySelectorAll('.card')].find((c) => norm((c.querySelector('.card-title') || {}).textContent).startsWith(titre));
      const net = (x) => { const c = Object.assign({}, x); ['id', '_creePar', '_creeLe', '_modifiePar', '_modifieLe', '_archivePar', '_archiveLe'].forEach((k) => delete c[k]); return propre(c); };
      const champsOuverts = () => [...document.querySelectorAll('[role=dialog] [id^=f_]')].map((e) => ({ nom: e.id.slice(2), balise: e.tagName.toLowerCase(), options: e.tagName === 'SELECT' ? [...e.options].map((o) => o.value).filter(Boolean) : null }));
      const libellesChamps = () => [...document.querySelectorAll('[role=dialog] label')].map((l) => norm(l.textContent));
      const remplacer = (col, fiches) => { col.all().splice(0); fiches.forEach((f) => col.all().push(f)); };
      const compter = (rows, champs) => { const g = {}; rows.forEach((r) => { const p = {}; champs.forEach((c) => { p[c] = r[c] === undefined ? null : r[c]; }); const k = JSON.stringify(p); g[k] = g[k] || { p, n: 0 }; g[k].n++; }); return Object.values(g).map((x) => Object.assign({}, x.p, { n: x.n })); };
      try { SIGH.peuplerParcours(); } catch (e) { window.__erreurPeuplement = String(e); }
      const sortieG = {};
      const colEnq = S.collection('enquetes', { module: 'M13' }), colRep = S.collection('reponsesEnquetes', { module: 'M13' }), colJet = S.collection('jetonsEnquete', { module: 'M13' }), colPts = S.collection('pointsCollecte', { module: 'M13' });
      const enqSat = () => colEnq.all().find((e) => e.reference === 'ENQ-SAT');
      const root0 = await monter('adm-enquetes'); root0.remove();   // amorçage par l'écran
      const questionsOrigine = propre(enqSat().questions), versionsOrigine = propre(enqSat().versions), repsOrigine = propre(colRep.all()), jetOrigine = propre(colJet.all());
      sortieG.points = propre(colPts.active().map((p) => ({ code: p.code, libelle: p.libelle })));

      /* ---------- ANALYSE : l'écran réel, filtre par filtre ---------- */
      {
        const Q1 = [{ code: 'Q_ACCUEIL', libelle: 'Qualité de l’accueil', type: 'note' }, { code: 'Q_SOINS', libelle: 'Qualité des soins reçus', type: 'note' }, { code: 'Q_RECO', libelle: 'Recommanderiez-vous la clinique ?', type: 'choix', options: ['Oui, sans hésiter', 'Plutôt oui', 'Plutôt non', 'Non'] }, { code: 'Q_LIBRE', libelle: 'Ce que nous pourrions améliorer', type: 'texte' }];
        const Q2 = Q1.concat([{ code: 'Q_ATTENTE', libelle: 'Temps d’attente ressenti', type: 'note' }]);
        const versions = [{ version: 'V1', effetLe: '2026-08-01', questions: Q1 }, { version: 'V2', effetLe: '2026-08-10', questions: Q2 }];
        colEnq.update(enqSat().id, { questions: Q2, versions });
        colRep.all().splice(0);
        const rep = (id, date, version, point, canal, reponses) => colRep.all().push({ id, statut: 'actif', enqueteId: 'ENQ0001', date, version, point, canal, reponses, saisiPar: 'Réponse anonyme — lien partagé' });
        rep('R1', '2026-07-30', 'V1', 'accueil', 'Lien public', { Q_ACCUEIL: 5, Q_SOINS: 4, Q_RECO: 'Oui, sans hésiter' });
        rep('R2', '2026-08-02', 'V1', 'accueil', 'Lien public', { Q_ACCUEIL: 3, Q_SOINS: 2, Q_RECO: 'Plutôt non', Q_LIBRE: 'Attente longue' });
        rep('R3', '2026-08-05', 'V1', 'laboratoire', 'Au guichet', { Q_ACCUEIL: 4, Q_SOINS: 5, Q_RECO: 'Plutôt oui' });
        rep('R4', '2026-08-10', 'V2', 'laboratoire', 'Lien public', { Q_ACCUEIL: 5, Q_SOINS: 5, Q_ATTENTE: 2, Q_RECO: 'Oui, sans hésiter' });
        rep('R5', '2026-08-12', 'V2', 'maternite', 'Lien public', { Q_ACCUEIL: 4, Q_ATTENTE: 4, Q_RECO: 'Non' });
        rep('R6', '2026-08-15', 'V2', 'maternite', 'Lien public', { Q_ACCUEIL: 1, Q_SOINS: 3, Q_ATTENTE: '', Q_RECO: '' });
        rep('R7', '2026-08-16', 'V2', 'sortie', 'À la sortie', { Q_ACCUEIL: 'abc', Q_SOINS: 0, Q_ATTENTE: 6 });
        const projReps = () => colRep.active().map((x) => ({ enqueteId: x.enqueteId, date: x.date, version: x.version, point: x.point, canal: x.canal, reponses: x.reponses }));
        const cas = [];
        const lire = async (nom, filtres) => {
          const root = await monter('adm-satisfaction');
          const carte = carteNommee(root, 'Analyse');
          const ids = { du: 'an_du', au: 'an_au', point: 'an_point', version: 'an_version', canal: 'an_canal' };
          for (const [k, v] of Object.entries(filtres)) { const e = carte.querySelector('#' + ids[k]); e.value = v; e.dispatchEvent(new Event('change', { bubbles: true })); await dormir(30); }
          const tables = [...carte.querySelectorAll('table')].map((t) => ({ entetes: [...t.querySelectorAll('thead th')].map((x) => norm(x.textContent)), lignes: [...t.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => norm(td.textContent))) }));
          const r = { nom, filtres, kpis: kpis(carte), tables, options: { points: [...carte.querySelectorAll('#an_point option')].map((o) => o.value), versions: [...carte.querySelectorAll('#an_version option')].map((o) => o.value) } };
          root.remove();
          return r;
        };
        const entrees = { enquete: propre({ id: 'ENQ0001', questions: Q2, versions }), reponses: propre(projReps()), points: sortieG.points };
        cas.push(await lire('sans filtre', {}));
        cas.push(await lire('un point', { point: 'accueil' }));
        cas.push(await lire('une période', { du: '2026-08-02', au: '2026-08-12' }));
        cas.push(await lire('une version', { version: 'V2' }));
        cas.push(await lire('un canal', { canal: 'Lien public' }));
        cas.push(await lire('filtres combinés', { point: 'laboratoire', version: 'V2', canal: 'Lien public' }));
        cas.push(await lire('aucune réponse ne correspond', { point: 'pharmacie' }));
        cas.push(await lire('notes toutes invalides', { point: 'sortie' }));
        sortieG.analyse = { entrees, cas };
        colEnq.update(enqSat().id, { questions: questionsOrigine, versions: versionsOrigine });
        remplacer(colRep, repsOrigine);
      }

      /* ---------- VERSIONS DATÉES : modifier le questionnaire ajoute une version, la réponse garde la sienne ---------- */
      {
        colEnq.update(enqSat().id, { versions: [{ version: 'V1', effetLe: '2026-08-01', questions: questionsOrigine }] });
        let root = await monter('adm-enquetes');
        const lignes = () => [...root.querySelectorAll('tbody tr')].find((tr) => tr.textContent.includes('Satisfaction des patients'));
        const cas = {};
        cas.avant = { versions: propre(enqSat().versions), questions: propre(enqSat().questions) };
        // enregistrer sans changer : aucune version neuve
        bouton(lignes(), 'Modifier le modèle').click(); await dormir(80);
        dernierBouton('Enregistrer').click(); await dormir(120);
        cas.sansChangement = { versions: propre(enqSat().versions).map((v) => v.version) };
        nettoyer(); root.remove(); root = await monter('adm-enquetes');
        // retirer la première question : une version V2 prend effet aujourd'hui
        bouton(lignes(), 'Modifier le modèle').click(); await dormir(80);
        document.querySelector('[role=dialog] button[aria-label="Retirer la question"], [role=dialog] button[title="Retirer la question"]').click(); await dormir(60);
        dernierBouton('Enregistrer').click(); await dormir(150);
        const e2 = propre(enqSat());
        cas.apresModification = { versions: e2.versions.map((v) => ({ version: v.version, effetLe: v.effetLe, codes: v.questions.map((q) => q.code) })), questionsCourantes: e2.questions.map((q) => q.code), toasts: toasts() };
        nettoyer(); root.remove(); root = await monter('adm-enquetes');
        // recueillir : la réponse porte la version en vigueur
        bouton(lignes(), 'Recueillir').click(); await dormir(80);
        poser('_canal', 'Au guichet'); poser('Q_ATTENTE', '4'); poser('Q_PROPRETE', '4'); poser('Q_SOINS', '5'); poser('Q_RECO', 'Plutôt oui');
        dernierBouton('Enregistrer la réponse').click(); await dormir(100);
        const nee = colRep.all()[0];
        cas.reponseNee = { version: nee.version, point: nee.point === undefined ? null : nee.point, canal: nee.canal };
        cas.anciennesReponses = [...new Set(repsOrigine.map((x) => x.version))];
        cas.unitaires = [];
        // les règles pures (fonctions exposées de l'écran) : version à une date, refus d'une date antérieure
        nettoyer(); root.remove();
        sortieG.versions = cas;
        colEnq.update(enqSat().id, { questions: questionsOrigine, versions: versionsOrigine });
        remplacer(colRep, repsOrigine);
      }

      /* ---------- PARTAGE EN LIGNE : un point de collecte, une version, une adresse publique ---------- */
      {
        colJet.all().splice(0);
        let root = await monter('adm-enquetes');
        bouton(root, 'Partager à un tiers').click(); await dormir(80);
        const form = { libelles: libellesChamps(), champs: champsOuverts() };
        poser('anonyme', 'oui'); poser('usage', 'en_ligne'); poser('point', 'laboratoire'); poser('expireLe', '2026-09-15'); poser('note', 'Affiche du laboratoire');
        dernierBouton('Ouvrir le lien').click(); await dormir(120);
        const jet = colJet.all()[0];
        const tiroir = document.querySelector('[role=dialog]');
        const lien = tiroir && tiroir.querySelector('input[readonly]') ? tiroir.querySelector('input[readonly]').value : null;
        sortieG.partageEnLigne = { form, jeton: Object.assign(net(jet), { jeton: '…' }), formatJeton: /^[a-km-z2-9]{24}$/.test(jet.jeton), lienGabarit: lien && lien.replace(jet.jeton, '<jeton>'), qrPresent: !!(tiroir && tiroir.querySelector('svg')) };
        nettoyer(); root.remove();
        root = await monter('adm-enquetes');
        root.querySelectorAll('[role=tab]')[1].click(); await dormir(80);
        sortieG.partageEnLigne.table = { entetes: entetes(root), lignes: lignesTable(root).map((l) => l.map((c) => c.replace(jet.jeton.slice(0, 8), '<8 premiers>'))) };
        root.remove();
        remplacer(colJet, jetOrigine);
      }
      return sortieG;
    });
    ecrire('packages/domaine/test/vecteurs/satisfaction_en_ligne.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-sat.js : l’écran adm-satisfaction (carte Analyse) et adm-enquetes (versions datées, point de collecte, partage en ligne) de la maquette, horloge fixée au 16/08/2026.' }, sortie));
    if (m.erreurs.length) console.log('Erreurs de page :', m.erreurs.slice(0, 5));
    for (const [k, v] of Object.entries(sortie)) console.log('  ' + k + (Array.isArray(v) ? ' : ' + v.length + ' cas' : ''));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
