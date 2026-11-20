/* =============================================================================
 * VECTEURS DE m6-etiquetage — « Étiquetage & emplacements » PILOTÉ comme le fait l'agent
 * -----------------------------------------------------------------------------
 * Le décor (casiers, articles, lots) est posé au magasin jetable, l'écran monté pour de bon : KPI, référentiel des emplacements (avec le compte
 * d'articles rangés), plan des rayons, tableau des articles, étiquettes ; puis les gestes — création d'un emplacement, modification, archivage
 * avec motif, modification d'un article — et ce qui est né au magasin.
 *   node build/vecteurs-etiquetage.js   →   packages/domaine/test/vecteurs/etiquetage.json
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs de l\'étiquetage & des emplacements');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m6-stock.js') });
    const sortie = await m.page.evaluate(async () => {
      const S = SIGH.store, C = SIGH.core;
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const propre = (x) => JSON.parse(JSON.stringify(x));
      const META = ['_creePar', '_creeLe', '_modifiePar', '_modifieLe', 'statutAvantArchivage'];
      const net = (x, retirer) => { const c = propre(x); META.concat(retirer || []).forEach((k) => delete c[k]); if (c.statut === 'actif') delete c.statut; return c; };
      const P = S.collection('produits'), L = S.collection('lots'), E = S.collection('emplacements', { module: 'M6', entite: 'emplacement', prefix: 'EMP' });
      P.all().forEach((x) => P.archive(x.id)); L.all().forEach((x) => L.archive(x.id)); E.all().forEach((x) => E.archive(x.id));

      const e = (id, code, libelle, zone, temperature, capacite) => E.insert({ id, code, libelle, zone, temperature, capacite, source: 'test' }).record;
      e('E1', 'A1', 'Rayon A — Casier 1', 'Rayonnage sec', 'Ambiante', 2);
      e('E2', 'F1', 'Réfrigérateur 1', 'Chaîne du froid', '2 à 8 °C', 10);
      e('E3', 'R9', 'Réserve fond', 'Réserve', 'Ambiante');
      const p = (id, code, designation, emplacement, stock, seuil, extra) => P.insert(Object.assign({ id, code, designation, unite: 'Unité', categorie: 'medicament', stock, stockDetail: stock, stockGros: 0, prixAchat: 100, prixVente: 150, cump: 100, seuilAlerte: seuil, emplacement }, extra || {})).record;
      p('Q1', 'Q1', 'ARTESUNATE 60 MG INJ', 'A1', 12, 5);
      p('Q2', 'Q2', 'GANT STERILE', 'A1', 3, 5);
      p('Q3', 'Q3', 'VACCIN HEPATITE B INJ', 'F1', 8, 2, { prixVente: 2500 });
      p('Q4', 'Q4', 'COTON HYDROPHILE 500 G', 'R9', 0, 2);
      p('Q5', 'Q5', 'SPARADRAP', undefined, 7, 2);
      for (let i = 6; i <= 12; i++) p('Q' + i, 'Q' + i, 'ARTICLE DE RESERVE ' + i, 'R9', 10 + i, 2);
      const l = (id, produitId, numeroLot, datePeremption) => L.insert({ id, produitId, numeroLot, datePeremption, quantite: 5 }).record;
      l('LQ1', 'Q1', 'LOT-B', '2027-03-01'); l('LQ2', 'Q1', 'LOT-A', '2026-12-15'); l('LQ3', 'Q3', 'V-77', '2027-01-31');

      const root = document.createElement('div'); document.body.appendChild(root);
      SIGH.screens['m6-etiquetage'].render(root);
      const lire = () => {
        const txt = root.innerText.split('\n').map((x) => x.trim()).filter(Boolean);
        const kpi = ['Emplacements définis', 'Articles rangés', 'Articles sans emplacement', 'Lots classés FEFO'].map((lab) => txt[txt.indexOf(lab) + 1]);
        const tables = [...root.querySelectorAll('table')].map((t) => ({
          entetes: [...t.querySelectorAll('thead th')].map((th) => th.innerText.replace(/\s+/g, ' ').trim()),
          lignes: [...t.querySelectorAll('tbody tr')].map((tr) => ({ cellules: [...tr.children].map((td) => td.innerText.replace(/\s+/g, ' ').trim()), actions: [...tr.querySelectorAll('button')].map((b) => (b.title || b.getAttribute('aria-label') || '') + '|' + b.textContent.trim()) })),
        }));
        const cartes = [...root.querySelectorAll('.shadow-card')].filter((c) => c.querySelector('ul')).map((c) => ({
          titre: c.children[0].children[0].innerText.trim(), badge: c.children[0].children[1].innerText.trim(),
          lignes: [...c.querySelectorAll('li')].map((li) => li.innerText.replace(/\s+/g, ' ').trim()),
        }));
        return { kpi, tables, cartes, textes: txt.filter((x) => /FEFO|sérums/.test(x)) };
      };
      const toasts = () => [...document.querySelectorAll('#toast-host > div')].map((d) => [...d.querySelectorAll('p')].map((p) => p.textContent.trim()));
      const vider = () => { document.querySelectorAll('#toast-host > div').forEach((d) => d.remove()); };
      const cas = { entree: { emplacements: E.active().map((x) => net(x)), produits: P.active().map((x) => net(x)), lots: L.active().map((x) => net(x)) }, lu: lire(), gestes: {} };

      /* --- Les étiquettes d'un casier, puis de tout le stock --- */
      const etiquettes = async (bouton) => {
        bouton.click(); await dormir(60);
        const ov = document.querySelector('.print-chrome');
        const r = { titre: ov ? ov.querySelector('.text-white').innerText.trim() : null, textes: ov ? [...ov.querySelectorAll('.border-slate-400')].map((d) => [...d.querySelectorAll('p')].map((p) => p.innerText.trim())) : [], entete: ov ? ov.innerText.replace(/\s+/g, ' ').trim().slice(0, 400) : null };
        if (ov) [...ov.querySelectorAll('button')].find((b) => b.textContent.includes('Fermer')).click();
        await dormir(20);
        return r;
      };
      const bCasier = [...root.querySelectorAll('button')].filter((b) => b.textContent.trim() === 'Étiquettes');
      cas.gestes.etiquettesCasiers = [];
      for (const b of bCasier) cas.gestes.etiquettesCasiers.push(await etiquettes(b));
      cas.gestes.etiquettesTout = await etiquettes([...root.querySelectorAll('button')].find((b) => b.textContent.includes('Éditer toutes les étiquettes')));

      /* --- Création d'un emplacement --- */
      const champ = (id, v) => { const x = document.getElementById('f_' + id); if (!x) throw new Error('champ ' + id); x.value = v; x.dispatchEvent(new Event('input')); x.dispatchEvent(new Event('change')); };
      const ouvrirCreation = async () => { [...root.querySelectorAll('button')].find((b) => b.textContent.includes('Nouvel emplacement')).click(); await dormir(40); };
      const boutonModale = (lib) => [...document.querySelectorAll('.modal-root button, [role=dialog] button')].find((b) => b.textContent.trim() === lib);
      const fermerModales = () => document.querySelectorAll('.modal-root, [role=dialog]').forEach((x) => x.remove());
      await ouvrirCreation();
      const modaleC = document.querySelector('.modal-root, [role=dialog]');
      cas.gestes.creation = { modale: modaleC.innerText.replace(/\s+/g, ' ').trim(), champs: [...modaleC.querySelectorAll('input, select, textarea')].map((x) => x.id + '=' + x.value) };
      vider();
      boutonModale('Créer').click(); await dormir(40);
      cas.gestes.creationVide = { toasts: toasts(), compte: E.active().length };
      vider();
      champ('code', 'B2'); champ('libelle', 'Armoire sécurisée 2'); champ('zone', 'Armoire sécurisée'); champ('temperature', 'Sous clé, ambiante'); champ('capacite', '4'); champ('observation', 'Stupéfiants');
      boutonModale('Créer').click(); await dormir(60);
      cas.gestes.creationOk = { toasts: toasts(), cree: net(E.active()[0], ['id']), compte: E.active().length, lu: lire() };
      vider(); fermerModales();
      await ouvrirCreation(); champ('code', 'Z0'); champ('libelle', 'Sans capacité');
      boutonModale('Créer').click(); await dormir(60);
      cas.gestes.creationSansCapacite = { cree: net(E.active()[0], ['id']) };
      vider(); fermerModales();

      /* --- Modification et archivage depuis le référentiel --- */
      const ligneRef = (code) => [...root.querySelectorAll('table')][0] && [...[...root.querySelectorAll('table')][0].querySelectorAll('tbody tr')].find((tr) => tr.children[0].innerText.trim() === code);
      const bLigne = (tr, titre) => { if (!tr) throw new Error('ligne absente'); const b = [...tr.querySelectorAll('button')].find((x) => (x.title || x.getAttribute('aria-label') || '').includes(titre)); if (!b) throw new Error('bouton « ' + titre + ' » absent : ' + [...tr.querySelectorAll('button')].map((x) => x.outerHTML.slice(0, 160)).join(' || ') + ' ## ' + tr.innerText); return b; };
      cas.debugA1 = ligneRef('A1') ? [...ligneRef('A1').querySelectorAll('button')].map((b) => b.outerHTML.slice(0, 200)) : [...root.querySelectorAll('table')].map((t) => t.innerText.slice(0, 300));
      bLigne(ligneRef('A1'), 'Modifier').click(); await dormir(50);
      const modaleM = document.querySelector('.modal-root, [role=dialog]');
      cas.gestes.modification = { modale: modaleM.innerText.replace(/\s+/g, ' ').trim(), champs: [...modaleM.querySelectorAll('input, select, textarea')].map((x) => x.id + '=' + x.value) };
      champ('libelle', 'Rayon A — Casier 1 (réorganisé)'); champ('capacite', '1');
      vider(); boutonModale('Enregistrer').click(); await dormir(60);
      cas.gestes.modification.apres = { toasts: toasts(), fiche: net(E.get('E1'), ['id']), lu: lire() };
      vider(); fermerModales();

      const archiver = async (code, motif) => {
        bLigne(ligneRef(code), 'Archiver').click(); await dormir(50);
        const modale = document.querySelector('.modal-root, [role=dialog]');
        const rec = { code, modale: modale.innerText.replace(/\s+/g, ' ').trim() };
        vider();
        if (motif) { const t = modale.querySelector('textarea'); t.value = motif; t.dispatchEvent(new Event('input')); }
        [...modale.querySelectorAll('button')].find((x) => x.textContent.trim() === 'Archiver').click(); await dormir(60);
        rec.toasts = toasts(); rec.actifs = E.active().length; rec.fiche = net(E.all().find((x) => x.code === code), ['id']); rec.lu = lire();
        vider(); fermerModales();
        return rec;
      };
      cas.gestes.archivageSansMotif = await archiver('R9', '');
      cas.gestes.archivageAvecMotif = await archiver('F1', 'Local désaffecté');

      /* --- Modification d'un article depuis « Articles par emplacement » --- */
      const tabP = [...root.querySelectorAll('table')][1];
      const trQ1 = [...tabP.querySelectorAll('tbody tr')].find((tr) => tr.innerText.includes('ARTESUNATE'));
      bLigne(trQ1, 'Modifier').click(); await dormir(50);
      const modaleP = document.querySelector('.modal-root, [role=dialog]');
      cas.gestes.article = { champs: [...modaleP.querySelectorAll('input, select, textarea')].map((x) => x.id + '=' + x.value), boutons: [...tabP.querySelectorAll('tbody tr')].slice(0, 1).map((tr) => [...tr.querySelectorAll('button')].map((b) => (b.title || b.getAttribute('aria-label') || ''))) };
      champ('emplacement', 'F1'); champ('seuilAlerte', '9');
      vider(); boutonModale('Enregistrer').click(); await dormir(60);
      cas.gestes.article.apres = { toasts: toasts(), fiche: net(P.get('Q1'), ['id']), lu: lire() };
      vider(); fermerModales(); root.remove();
      return cas;
    });
    ecrire('packages/domaine/test/vecteurs/etiquetage.json', { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-etiquetage.js — m6-etiquetage piloté. Ne pas éditer.', ...sortie });
    console.log('  kpi ' + sortie.lu.kpi.join('/') + ' · cartes ' + sortie.lu.cartes.length + ' · ' + JSON.stringify(sortie.gestes.creationVide.toasts) + ' · ' + JSON.stringify(sortie.gestes.creationOk.toasts));
    console.log('  ' + JSON.stringify(sortie.gestes.archivageSansMotif.fiche) + JSON.stringify(sortie.gestes.archivageAvecMotif.fiche));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
