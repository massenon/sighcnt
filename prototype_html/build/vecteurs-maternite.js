/* =============================================================================
 * VECTEURS DE LA MATERNITÉ (M4) — les 15 écrans pilotés dans Chrome
 * -----------------------------------------------------------------------------
 * Les écrans réels sont montés sur le jeu de la maquette (horloge fixée au 16/08/2026, date du jeu), leurs filtres posés, leurs formulaires remplis,
 * leurs boutons cliqués ; ce qui s'affiche (indicateurs, en-têtes, lignes), ce qui est né au magasin, les refus et ce que « Imprimer » passe à
 * `P.etat` sont relus. Les référentiels `D.*` de la maternité sont EXTRAITS (jamais recopiés) vers `mat_referentiels.dart`.
 *   node build/vecteurs-maternite.js   →   packages/domaine/test/vecteurs/mat_*.json + packages/domaine/lib/src/maternite/mat_donnees.dart
 * ========================================================================== */
'use strict';
const path = require('path');
const fs = require('fs');
const { ouvrirMaquette, ecrire, ROOT, REPO } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs de la maternité');
  const m = await ouvrirMaquette();
  try {
    await m.page.evaluate(() => { SIGH.core.aujourdhui = function () { return new Date(2026, 7, 16, 12, 0, 0); }; });
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m4-maternite.js') });
    const sortie = await m.page.evaluate(async () => {
      const S = SIGH.store, C = SIGH.core, D = SIGH.data;
      const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const txt = (e) => (e ? e.innerText.replace(/\s+/g, ' ').trim() : null);
      const net = (x) => { const c = Object.assign({}, x); ['_creePar', '_creeLe', '_modifiePar', '_modifieLe', '_archivePar', '_archiveLe'].forEach((k) => delete c[k]); return propre(c); };
      const toasts = () => [...document.querySelectorAll('#toast-host > div')].map((n) => [...n.querySelectorAll('p')].map((p) => p.textContent.trim()));
      const viderToasts = () => { const h = document.getElementById('toast-host'); if (h) h.innerHTML = ''; };
      const fermer = () => document.querySelectorAll('.modal-root, [role=dialog], .print-overlay').forEach((e) => { if (!e.closest('#page-content')) e.remove(); });
      const bouton = (racine, texte) => !racine ? (() => { throw new Error('racine nulle pour « ' + texte + ' » (' + (window.__ctx || '') + ')'); })() : [...racine.querySelectorAll('button')].find((b) => txt(b) === texte || b.getAttribute('aria-label') === texte || b.title === texte);
      const boutonModale = (texte) => [...document.querySelectorAll('button')].filter((b) => txt(b) === texte).pop();
      const poser = (id, v) => { const e = document.getElementById('f_' + id); if (!e) throw new Error('champ ' + id); if (e.type === 'checkbox') { e.checked = !!v; } else { e.value = v; } e.dispatchEvent(new Event('input')); e.dispatchEvent(new Event('change')); };
      const champsModale = () => [...document.querySelectorAll('[id^=f_]')].map((e) => [e.id.slice(2), e.type === 'checkbox' ? e.checked : (e.value === undefined ? null : e.value)]);
      const montage = async (id) => { window.__ctx = id; const root = document.createElement('div'); root.id = 'page-content'; document.body.appendChild(root); SIGH.screens[id].render(root); await dormir(150); return root; };
      const tablesDe = (e) => [...e.querySelectorAll('*')].filter((x) => typeof x.lignesFiltrees === 'function');
      const kpis = (root) => [...root.querySelectorAll('.kpi')].map((k) => ({ label: txt(k.querySelector('.kpi-label')), valeur: txt(k.querySelector('.kpi-value')), indice: txt(k.querySelector('p.text-xs')) || null }));
      const lignesTexte = (root, n) => [...root.querySelectorAll('tbody tr')].slice(0, n || 9999).map((tr) => [...tr.querySelectorAll('td')].map((c) => txt(c)));
      const col = (n) => S.collection(n);
      const cache = {};
      const sauver = (n) => { if (!cache[n]) cache[n] = propre(col(n).all()); };
      const poserCol = (n, fiches) => { sauver(n); const a = col(n).all(); a.splice(0); fiches.forEach((f) => a.push(propre(f))); };
      const restaurer = () => Object.keys(cache).forEach((n) => { const a = col(n).all(); a.splice(0); cache[n].forEach((f) => a.push(propre(f))); delete cache[n]; });

      /* --- interception de l'impression ----------------------------------------------------------------------------------- */
      const imprimes = [];
      const etatOrig = SIGH.print.etat;
      function lireContenu(n) {
        const blocs = [];
        if (!n) return blocs;
        [...(n.matches('table, p, h3, h4') ? [n] : []), ...n.querySelectorAll('table, p, h3, h4')].forEach((e) => {
          if (e.tagName === 'TABLE') {
            blocs.push({ table: { entetes: [...e.querySelectorAll('thead th')].map(txt), lignes: [...e.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map(txt)),
              pied: e.querySelector('tfoot tr') ? [...e.querySelector('tfoot tr').children].map(txt) : null } });
          } else if (!e.closest('table')) { blocs.push({ texte: txt(e) }); }
        });
        return blocs;
      }
      SIGH.print.etat = function (o) {
        const rec = { titre: o.titre, sousTitre: o.sousTitre || null, filigrane: o.filigrane || null, cartouche: propre(o.cartouche || null), signatures: propre(o.signatures || null), contenu: lireContenu(o.contenu) };
        imprimes.push(rec);
        return etatOrig.apply(this, arguments);
      };
      const imprimer = async (root, ref, libelle) => {
        const q = root.querySelector('input[placeholder^="Rechercher"]'); if (q) { q.value = ref; q.dispatchEvent(new Event('input')); await dormir(450); }
        const tr = [...root.querySelectorAll('tbody tr')].find((x) => txt(x).includes(ref)); const n = imprimes.length;
        bouton(tr, libelle || 'Imprimer l’état').click(); await dormir(120); fermer();
        return propre(imprimes[n]);
      };

      /* Le jeu COMPLET, comme l'export du jeu du poste (gen-poste-jeu.js) : la page d'extraction ne lance pas le peuplement des parcours. */
      try { SIGH.peuplerParcours(); } catch (e) { console.error(e); }
      const out = { jour: C.iso(C.aujourdhui()) };

      /* ================================================================================== référentiels (→ mat_donnees.dart) */
      const NOMS = ['SONU', 'METHODES_PF', 'STATUTS_ACCEPTANTE', 'DOSES_SP', 'TYPES_CPON', 'BORNES_NOUVEAU_NE', 'AGES_RISQUE_CPN', 'URGENCES_MATERNITE', 'TRANCHES_AGE_CURATIF',
        'PTME', 'TYPES_ACCOUCHEMENT', 'ACTES_ACCOUCHEMENT', 'PARTOGRAMME', 'DROITS_FONDAMENTAUX', 'PLAN_ACCOUCHEMENT', 'FACTEURS_SURVEILLANCE', 'EXAMENS_DOSSIER',
        'COMPTES_RENDUS_MATERNITE', 'GROUPES_SANGUINS', 'CLASSES_MERES', 'GRILLE_CPN', 'INDICATEURS_DHIS2'];
      out.referentiels = {}; NOMS.forEach((n) => { out.referentiels[n] = propre(D[n]); });

      /* ================================================================================== lecture des écrans */
      async function lire(id, opts) {
        opts = opts || {};
        const root = await montage(id);
        const t = tablesDe(root)[0];
        const r = { id, kpis: kpis(root), onglets: [...root.querySelectorAll('[role=tab]')].map(txt), entetes: [...root.querySelectorAll('thead th')].map(txt),
          page1: lignesTexte(root, 12), nb: t ? t.lignesFiltrees().length : null, ids: t ? t.lignesFiltrees().map((x) => x.id) : [], filtres: [] };
        const selects = [...root.querySelectorAll('select')];
        for (const s of selects) {
          const f = { options: [...s.options].map((o) => [o.value, o.textContent.trim()]), effets: [] };
          for (const o of [...s.options]) {
            if (!o.value) continue;
            s.value = o.value; s.dispatchEvent(new Event('change')); await dormir(80);
            f.effets.push({ valeur: o.value, nb: t.lignesFiltrees().length, ids: t.lignesFiltrees().map((x) => x.id) });
          }
          s.value = ''; s.dispatchEvent(new Event('change')); await dormir(60);
          r.filtres.push(f);
        }
        if (opts.plage) {
          r.plage = [];
          for (const lib of ['Sept derniers jours', 'Aujourd’hui', 'Toute la période']) {
            bouton(root, lib).click(); await dormir(100);
            r.plage.push({ bouton: lib, nb: t.lignesFiltrees().length, ids: t.lignesFiltrees().map((x) => x.id), kpis: kpis(root) });
          }
          const du = root.querySelector('input[type=date]'); const au = root.querySelectorAll('input[type=date]')[1];
          du.value = opts.plage[0]; du.dispatchEvent(new Event('change')); au.value = opts.plage[1]; au.dispatchEvent(new Event('change')); await dormir(100);
          r.plage.push({ bouton: 'du ' + opts.plage[0] + ' au ' + opts.plage[1], nb: t.lignesFiltrees().length, ids: t.lignesFiltrees().map((x) => x.id), kpis: kpis(root) });
          bouton(root, 'Toute la période').click(); await dormir(80);
        }
        if (opts.fiche !== false && t) {
          const tr = root.querySelector('tbody tr'); const b = tr && bouton(tr, 'Consulter');
          if (b) { b.click(); await dormir(150); const dr = document.querySelector('.drawer-backdrop'); r.fiche = { ref: txt(tr.querySelector('td:nth-child(2)')), titre: txt(dr && dr.querySelector('h2')), texte: txt(dr && dr.querySelector('.overflow-y-auto')), boutons: dr ? [...dr.querySelectorAll('button')].map((x) => txt(x) || x.getAttribute('aria-label')) : [] }; fermer(); }
        }
        r.actionsLigne = (() => { const tr = root.querySelector('tbody tr'); return tr ? [...tr.querySelectorAll('button')].map((x) => x.getAttribute('aria-label') || x.title || txt(x)) : []; })();
        r.commandes = [...root.querySelectorAll('button')].filter((b) => !b.closest('tbody') && !b.closest('[role=tablist]')).map((b) => txt(b) || b.getAttribute('aria-label')).filter(Boolean);
        root.remove();
        return r;
      }
      const L = {};
      for (const id of ['m4-maternite', 'm4-accouchements', 'm4-naissances', 'm4-deces', 'm4-cpn', 'm4-dossier-bebe', 'm4-cpon', 'm4-sonu', 'm4-ptme']) L[id] = await lire(id);
      for (const id of ['m4-planification', 'm4-soins-curatifs']) L[id] = await lire(id, { plage: ['2026-07-01', '2026-07-31'] });
      L['m4-dossier-obstetrical'] = await lire('m4-dossier-obstetrical', { plage: ['2026-06-01', '2026-06-30'] });
      out.lectures = L;

      /* ================================================================================== comptes rendus de maternité */
      {
        const root = await montage('m4-comptes-rendus');
        const cr = { kpis: kpis(root), onglets: [...root.querySelectorAll('[role=tab]')].map(txt), notes: [...root.querySelectorAll('.note, [class*=bg-warning-50]')].map(txt), parOnglet: [] };
        for (const tab of [...root.querySelectorAll('[role=tab]')]) {
          tab.click(); await dormir(120);
          const t = tablesDe(root)[0];
          cr.parOnglet.push({ onglet: txt(tab), entetes: [...root.querySelectorAll('thead th')].map(txt), page1: lignesTexte(root, 12), nb: t.lignesFiltrees().length,
            note: txt([...root.querySelectorAll('p')].find((p) => /NON couverts|TOUS non couverts/.test(p.textContent) && p.closest('.space-y-3'))) });
        }
        // fiche d'un compte rendu de chaque type
        cr.fiches = [];
        for (const tab of [...root.querySelectorAll('[role=tab]')]) {
          tab.click(); await dormir(250);
          if (!root.querySelector('tbody tr')) throw new Error('aucune ligne : ' + txt(tab) + ' / ' + root.innerText.slice(0, 300));
          const b = bouton(root.querySelector('tbody tr'), 'Consulter'); b.click(); await dormir(150);
          const dr = document.querySelector('.drawer-backdrop'); cr.fiches.push({ onglet: txt(tab), titre: txt(dr.querySelector('h2')), texte: txt(dr.querySelector('.overflow-y-auto')) }); fermer();
        }
        // création d'un compte rendu par onglet (rubriques engendrées depuis la déclaration)
        cr.creations = [];
        const femme = S.collection('patients').active().filter((p) => p.sexe === 'F').sort((a, b) => (a.code < b.code ? -1 : 1))[0];
        const sf = S.collection('soignants').active().filter((x) => x.prescrit || x.execute)[0];
        cr.femme = femme.code; cr.soignant = { id: sf.id, nom: sf.nomComplet };
        const tabs = [...root.querySelectorAll('[role=tab]')];
        const cas = [
          ['planning', 1, { patientCode: femme.code, sageFemmeId: sf.id, dateActe: '2026-08-10', methode: 'Implant', geste: 'Pose', counseling: true, effetsSecondaires: true }],
          ['planning : méthode manquante (refus)', 1, { patientCode: femme.code, sageFemmeId: sf.id, dateActe: '2026-08-10', geste: 'Pose' }],
          ['amiu', 2, { patientCode: femme.code, sageFemmeId: sf.id, dateHeure: '2026-08-11T09:30', indication: 'Avortement incomplet', deroulement: 'RAS', suites: 'Surveillance', operateurId: sf.id }],
        ];
        for (const [nom, i, saisie] of cas) {
          [...root.querySelectorAll('[role=tab]')][i].click(); await dormir(300);
          const avant = new Set(col('crMaternite').all().map((x) => x.id));
          { const bb = bouton(root, i === 1 ? 'Nouveau — de planning familial' : 'Nouveau — d’AMIU'); if (!bb) throw new Error('boutons : ' + [...root.querySelectorAll('button')].map((b) => JSON.stringify(txt(b))).join(' ')); bb.click(); await dormir(120); }
          const initial = champsModale(); const titre = txt(document.querySelector('.modal-root h2, [role=dialog] h2'));
          Object.entries(saisie).forEach(([k, v]) => poser(k, v)); viderToasts();
          boutonModale('Créer').click(); await dormir(150);
          cr.creations.push({ nom, saisie, titre, initial, nouvelles: col('crMaternite').all().filter((x) => !avant.has(x.id)).map(net), toasts: toasts(), modaleOuverte: !!document.querySelector('.modal-root, [role=dialog]') });
          fermer();
        }
        root.remove();
        out.comptesRendus = cr;
      }

      /* ================================================================================== règles du nouveau-né (alertes, Apgar) */
      {
        const base = col('naissances').all()[0];
        const cas = [['dans les bornes', 3.1, 34, 33, 8, 9, 10], ['PC trop petit', 3, 31.9, 33, 8, 9, 10], ['PC à 32 (borne)', 3, 32, 33, 8, 9, 10], ['PC à 38 (borne)', 3, 38, 33, 8, 9, 10],
          ['PC à 38,1', 3, 38.1, 33, 8, 9, 10], ['PT à 29,9', 3, 34, 29.9, 8, 9, 10], ['PT à 36 (borne)', 3, 34, 36, 8, 9, 10], ['PT à 36,1', 3, 34, 36.1, 8, 9, 10],
          ['Apgar 5 min = 6', 3, 34, 33, 5, 6, 8], ['Apgar 5 min = 7 (seuil, pas d\'alerte)', 3, 34, 33, 6, 7, 9], ['Apgar manquant', 3, 34, 33, null, null, null],
          ['mesures manquantes', 3, null, null, 8, 9, 10], ['trois alertes', 3, 30, 40, 2, 3, 5]];
        const fiches = cas.map((c, i) => Object.assign({}, propre(base), { id: 'NV' + i, reference: 'NAI-9' + String(i).padStart(3, '0'), statut: 'actif', poids: c[1], pc: c[2], pt: c[3], apgar1: c[4], apgar5: c[5], apgar10: c[6] }));
        poserCol('naissances', fiches);
        const root = await montage('m4-dossier-bebe');
        const bebe = { cas: cas.map((c) => c[0]), fiches: propre(fiches), kpis: kpis(root) };
        const t = tablesDe(root)[0];
        bebe.lignes = t.lignesFiltrees().map((r) => r.id);
        // le rendu d'une ligne : classes d'alerte sur PC et PT, texte Apgar
        bebe.rendu = [...root.querySelectorAll('tbody tr')].map((tr) => ({ ref: txt(tr.children[1]), pc: txt(tr.children[4]), pcAlerte: !!tr.children[4].querySelector('.text-danger-600'), pt: txt(tr.children[5]), ptAlerte: !!tr.children[5].querySelector('.text-danger-600'), apgar: txt(tr.children[6]) }));
        root.remove();
        const root2 = await montage('m4-naissances');
        bebe.registre = { kpis: kpis(root2), rendu: [...root2.querySelectorAll('tbody tr')].map((tr) => ({ ref: txt(tr.children[1]), apgar: txt(tr.children[7]), apgarAlerte: !!tr.children[7].querySelector('.text-danger-600'), pc: txt(tr.children[8]), horsBornes: !!tr.children[8].querySelector('.text-warning-700') })) };
        root2.remove();
        out.nouveauNe = bebe;
        restaurer();
      }

      /* ================================================================================== saisies : création, refus, modification */
      const saisies = [];
      async function saisie(nom, ecran, ouvrir, saisieV, valider, colNom, pre) {
        const root = await montage(ecran);
        bouton(root, ouvrir).click(); await dormir(120);
        const initial = champsModale(); const titre = txt(document.querySelector('.modal-root h2, [role=dialog] h2'));
        Object.entries(saisieV).forEach(([k, v]) => poser(k, v));
        const avant = new Set(col(colNom).all().map((x) => x.id)); const nAvant = col(colNom).all().length;
        viderToasts();
        boutonModale(valider || 'Créer').click(); await dormir(180);
        saisies.push({ nom, ecran, saisie: saisieV, titre, initial, nouvelles: col(colNom).all().filter((x) => !avant.has(x.id)).map(net), nbAvant: nAvant, nbApres: col(colNom).all().length, toasts: toasts(),
          modaleOuverte: !!document.querySelector('.modal-root, [role=dialog]') });
        fermer(); root.remove();
      }
      async function modifier(nom, ecran, colNom, ref, saisieV) {
        const root = await montage(ecran);
        const q = root.querySelector('input[placeholder^="Rechercher"]'); q.value = ref; q.dispatchEvent(new Event('input')); await dormir(450);
        const tr = [...root.querySelectorAll('tbody tr')].find((x) => txt(x).includes(ref));
        const id = tablesDe(root)[0].lignesFiltrees().find((r) => (r.reference || r.numeroDossier) === ref).id;
        const avant = net(col(colNom).all().find((x) => x.id === id));
        bouton(tr, 'Modifier').click(); await dormir(120);
        const prerempli = champsModale();
        Object.entries(saisieV).forEach(([k, v]) => poser(k, v)); viderToasts();
        boutonModale('Enregistrer').click(); await dormir(180);
        const apres = net(col(colNom).all().find((x) => x.id === id)); const patch = {};
        Object.keys(Object.assign({}, avant, apres)).forEach((k) => { if (JSON.stringify(avant[k]) !== JSON.stringify(apres[k])) patch[k] = apres[k] === undefined ? null : apres[k]; });
        saisies.push({ nom, ecran, modification: true, ref, saisie: saisieV, prerempli, avant, patch, toasts: toasts(), modaleOuverte: !!document.querySelector('.modal-root, [role=dialog]') });
        fermer(); root.remove();
      }
      const femmes = C.sortBy(S.collection('patients').active().filter((p) => p.sexe === 'F'), 'code');
      const F = femmes[0], F2 = femmes[1];
      const sages = S.collection('personnel').active().filter((e) => e.fonction === 'sage_femme' || e.fonction === 'medecin');
      const SF = sages[0].nomComplet;
      out.contexte = { femme: F.code, femme2: F2.code, sageFemme: SF, femmeSansNaissance: null };
      // une patiente SANS date de naissance, pour le verrou d'admission
      const sansNaiss = femmes.find((p) => !p.dateNaissance);
      let patientSans = null;
      if (sansNaiss) patientSans = sansNaiss.code;
      else { sauver('patients'); const p = col('patients').all().find((x) => x.code === F2.code); p.dateNaissance = null; patientSans = p.code; }
      out.contexte.femmeSansNaissance = patientSans;

      await saisie('suivi : admission complète', 'm4-maternite', 'Nouveau', { patientCode: F.code, termeSA: 30, poids: 62.5, dpa: '2026-10-05', cpn: 4, risque: 'Élevé', sageFemme: SF, observations: 'RAS' }, 'Créer', 'suiviMaternite');
      await saisie('suivi : dossier sans date de naissance (verrou nommant où corriger)', 'm4-maternite', 'Nouveau', { patientCode: patientSans, termeSA: 20, poids: 55, dpa: '2026-12-01' }, 'Créer', 'suiviMaternite');
      await saisie('accouchement : césarienne avec actes', 'm4-accouchements', 'Nouveau', { patientCode: F.code, dateHeure: '2026-08-15T22:10', type: 'Césarienne', actes: ['Épisiotomie', 'GATPA'], duree: '8 h', sageFemme: SF, complications: 'Aucune', issue: 'Favorable' }, 'Créer', 'accouchements');
      await saisie('accouchement : eutocique (voie basse)', 'm4-accouchements', 'Nouveau', { patientCode: F.code, dateHeure: '2026-08-14T03:00', type: 'Eutocique', sageFemme: SF, issue: 'Défavorable', complications: 'Souffrance fœtale' }, 'Créer', 'accouchements');
      await saisie('accouchement : date manquante (refus)', 'm4-accouchements', 'Nouveau', { patientCode: F.code, sageFemme: SF }, 'Créer', 'accouchements');
      await saisie('naissance : complète (alerte Apgar 5 min < 7)', 'm4-naissances', 'Nouveau', { mereCode: F.code, dateHeure: '2026-08-15T22:30', sexe: 'F', vivant: true, poids: 2.8, taille: 48, pc: 31, pt: 33, apgar1: 4, apgar5: 6, apgar10: 8, reanimation: true, vitK1: true, bcg: true, declare: false }, 'Créer', 'naissances');
      await saisie('naissance : PC manquant (refus, obligatoire)', 'm4-naissances', 'Nouveau', { mereCode: F.code, dateHeure: '2026-08-15T22:30', sexe: 'M', poids: 3.2, pt: 33, apgar1: 8, apgar5: 9 }, 'Créer', 'naissances');
      await saisie('dossier bébé : même formulaire, même fiche', 'm4-dossier-bebe', 'Nouveau', { mereCode: F2.code, dateHeure: '2026-08-13T10:00', sexe: 'M', poids: 3.4, pc: 34, pt: 33, apgar1: 8, apgar5: 9, vitK1: true, vpo0: true }, 'Créer', 'naissances');
      await saisie('décès', 'm4-deces', 'Nouveau', { patientCode: F.code, dateHeure: '2026-08-12T05:45', cause: 'Choc hémorragique', lieu: 'Maternité', medecin: SF, declare: false }, 'Créer', 'deces');
      await saisie('CPN : grossesse suivie (alerte âge hors fenêtre si le dossier le porte)', 'm4-cpn', 'Nouveau', { patientCode: F.code, ddr: '2026-02-01', dpa: '2026-11-08', termeSA: 28, groupeSanguin: 'O+', sageFemme: SF, sp: ['SP1', 'SP2', 'SP3'], milda: true, gar: false, mebendazole: true, vat: 'VAT2', fer: true, folates: true }, 'Créer', 'grossesses');
      await saisie('CPoN : hémorragie ante-partum SANS étiologie (refus)', 'm4-cpon', 'Nouveau', { patientCode: F.code, date: '2026-08-10', type: 'cpon1', hemorragieAntePartum: true, sageFemme: SF }, 'Créer', 'cpon');
      await saisie('CPoN : hémorragie ante-partum avec étiologie', 'm4-cpon', 'Nouveau', { patientCode: F.code, date: '2026-08-10', type: 'cpon2', hemorragieAntePartum: true, etiologieAnte: 'Placenta praevia', hpp: true, examen: 'TA 12/8', conseilPF: true, sageFemme: SF }, 'Créer', 'cpon');
      await saisie('CPoN : étiologie sans hémorragie (effacée)', 'm4-cpon', 'Nouveau', { patientCode: F.code, date: '2026-08-10', type: 'cpon3', hemorragieAntePartum: false, etiologieAnte: 'Rupture utérine', sageFemme: SF }, 'Créer', 'cpon');
      await saisie('PF : nouvelle acceptante, implant', 'm4-planification', 'Nouveau', { patientCode: F.code, date: '2026-08-12', acceptante: 'A', methode: 'jadelle', rdv: '2026-09-12', sageFemme: SF }, 'Créer', 'planificationFamiliale');
      await saisie('SONU : fonctions triées, numériques', 'm4-sonu', 'Nouveau', { patientCode: F.code, dateHeure: '2026-08-15T01:20', gestite: 3, parite: 2, evacuation: true, provenance: 'CS Kouandé', fonctions: ['10', '3', '1'], evolution: 'Favorable', agent: SF }, 'Créer', 'registreSONU');
      await saisie('SONU : aucune fonction (refus)', 'm4-sonu', 'Nouveau', { patientCode: F.code, dateHeure: '2026-08-15T01:20', evolution: 'Favorable', agent: SF }, 'Créer', 'registreSONU');
      await saisie('PTME', 'm4-ptme', 'Nouveau', { patientCode: F.code, vihTrimestre: '2', vihType: 'VIH-1', agHbs: 'Négatif', syphilis: 'Négatif', chargeVirale: 'Indétectable', allaitement: 'Exclusif', pcrNaissance: 'En attente', ctm: true }, 'Créer', 'ptme');
      await saisie('Case 27 : hospitalisée sans jours (refus)', 'm4-soins-curatifs', 'Nouveau', { patientCode: F.code, date: '2026-08-12', diagnostic: 'Paludisme', femmeHospitalisee: true, agent: SF }, 'Créer', 'soinsCuratifsMaternite');
      await saisie('Case 27 : jours sans hospitalisation (refus)', 'm4-soins-curatifs', 'Nouveau', { patientCode: F.code, date: '2026-08-12', diagnostic: 'Paludisme', femmeHospitalisee: false, joursHospitalisation: 3, agent: SF }, 'Créer', 'soinsCuratifsMaternite');
      await saisie('Case 27 : hospitalisée 3 jours', 'm4-soins-curatifs', 'Nouveau', { patientCode: F.code, date: '2026-08-12', diagnostic: 'Paludisme', femmeObservee: true, femmeHospitalisee: true, joursHospitalisation: 3, urgenceMaternite: 'referee', mildaDelivree: true, agent: SF }, 'Créer', 'soinsCuratifsMaternite');
      // modifications : la référence est-elle conservée ?
      const ref0 = (n, p) => col(n).all().find((x) => x.reference && x.reference.indexOf(p) === 0 && x.statut !== 'archive').reference;
      await modifier('accouchement : type corrigé', 'm4-accouchements', 'accouchements', 'ACC-0002', { type: 'Dystocique' });
      await modifier('naissance : déclarée à l\'état civil', 'm4-naissances', 'naissances', 'NAI-0002', { declare: true });
      await modifier('décès : déclaré', 'm4-deces', 'deces', 'DEC-0002', { declare: true });
      await modifier('CPN : GAR coché', 'm4-cpn', 'grossesses', 'CPN-0002', { gar: true });
      await modifier('CPoN : séance corrigée', 'm4-cpon', 'cpon', 'CPO-0002', { type: 'cpon3' });
      await modifier('PF : méthode corrigée (libellé relu)', 'm4-planification', 'planificationFamiliale', 'PF-0002', { methode: 'co' });
      await modifier('SONU : évolution', 'm4-sonu', 'registreSONU', 'SONU-0002', { evolution: 'Référée' });
      await modifier('PTME : charge virale', 'm4-ptme', 'ptme', 'PTME-0002', { chargeVirale: 'Indétectable' });
      await modifier('Case 27 : hospitalisée → jours conservés', 'm4-soins-curatifs', 'soinsCuratifsMaternite', 'SCM-0002', { femmeHospitalisee: false, femmeObservee: true });
      out.saisies = saisies;
      restaurer();

      /* ================================================================================== impressions (ligne « Imprimer l'état ») */
      out.impressions = {};
      for (const [ecran, ref] of [['m4-maternite', null], ['m4-accouchements', 'ACC-0003'], ['m4-naissances', 'NAI-0003'], ['m4-deces', 'DEC-0003'], ['m4-cpn', 'CPN-0003'], ['m4-dossier-bebe', 'NAI-0004'],
        ['m4-cpon', 'CPO-0003'], ['m4-planification', 'PF-0003'], ['m4-sonu', 'SONU-0003'], ['m4-dossier-obstetrical', '00003/26']]) {
        const root = await montage(ecran);
        if (ref) out.impressions[ecran] = await imprimer(root, ref);
        else { const tr = root.querySelector('tbody tr'); const n = imprimes.length; bouton(tr, 'Imprimer l’état').click(); await dormir(120); fermer(); out.impressions[ecran] = propre(imprimes[n]); }
        root.remove();
      }
      { // certificat de repos depuis la fiche d'accouchement
        const root = await montage('m4-accouchements');
        bouton(root.querySelector('tbody tr'), 'Consulter').click(); await dormir(150);
        const n = imprimes.length; bouton(document.querySelector('.drawer-backdrop'), 'Certificat de repos post-partum').click(); await dormir(150);
        out.impressions.certificatRepos = propre(imprimes[n]); out.impressions.certificatReposRef = txt(root.querySelector('tbody tr td:nth-child(2)'));
        fermer(); root.remove();
      }

      /* ================================================================================== fiche CPN : visites, ajout d'une visite */
      {
        const root = await montage('m4-cpn');
        const id = tablesDe(root)[0].lignesFiltrees()[0].id; const g = net(col('grossesses').all().find((x) => x.id === id));
        const tr = root.querySelector('tbody tr'); bouton(tr, 'Consulter').click(); await dormir(150);
        const dr = document.querySelector('.drawer-backdrop');
        const avant = { texte: txt(dr.querySelector('.overflow-y-auto')), nbVisites: (g.visites || []).length, gar: !!g.gar };
        bouton(dr, 'Ajouter une visite CPN').click(); await dormir(150);
        const titre = txt([...document.querySelectorAll('h2')].pop());
        poser('date', '2026-08-14'); poser('ta', '12/8'); poser('poids', '64.5'); poser('hu', '28'); poser('bdcf', '140'); poser('albumine', '+'); poser('sucre', '—'); viderToasts();
        boutonModale('Enregistrer la visite').click(); await dormir(150);
        const apres = net(col('grossesses').all().find((x) => x.id === id));
        out.cpnVisite = { ref: g.reference, avant, titre, visites: apres.visites, nbApres: (apres.visites || []).length, toasts: toasts() };
        fermer(); root.remove();
        // garde : la visite sans poids est refusée par le formulaire (obligatoire)
        const root2 = await montage('m4-cpn');
        bouton(root2.querySelector('tbody tr'), 'Consulter').click(); await dormir(150);
        bouton(document.querySelector('.drawer-backdrop'), 'Ajouter une visite CPN').click(); await dormir(120);
        poser('date', '2026-08-14'); poser('ta', '12/8'); const nb0 = (col('grossesses').all().find((x) => x.id === id).visites || []).length;
        boutonModale('Enregistrer la visite').click(); await dormir(120);
        out.cpnVisiteRefus = { nb0, nb1: (col('grossesses').all().find((x) => x.id === id).visites || []).length, modaleOuverte: !!document.querySelector('.modal-root, [role=dialog]') };
        fermer(); root2.remove();
        // GAR : note de la fiche d'une grossesse à risque
        const gar = col('grossesses').all().find((x) => x.gar);
        out.cpnGar = gar ? gar.reference : null;
      }

      /* ================================================================================== PARTOGRAMME */
      {
        const base = col('partogrammes').all();
        const mk = (id, ref, mesures, clos) => ({ id, reference: ref, patient: 'TEST ' + id, patientCode: 'CNT/' + id, debut: '2026-08-15T20:00:00.000Z', mesures, clos: !!clos, statut: 'actif', accoucheur: 'X', gestite: 2, parite: 1 });
        const m_ = (h, d) => ({ heure: h, dilatation: d, descente: 3, bdf: 140, contractions: 3, ta: '12/8', pouls: 80, liquide: 'C' });
        const cas = [
          mk('P1', 'PARTO-9001', [m_(0, 4), m_(1, 5), m_(2, 6)]),
          mk('P2', 'PARTO-9002', [m_(0, 4), m_(4, 4), m_(5, 4.5)]),            // heure 4 : dilatation 4 < attendu 4 → action NON franchie (égal)
          mk('P3', 'PARTO-9003', [m_(0, 4), m_(5, 4)]),                         // heure 5 : attendu 5, dilatation 4 → franchie
          mk('P4', 'PARTO-9004', [m_(0, 5), m_(3, 3), m_(8, 10)], true),        // heure 3 < 4 : jamais franchie avant l'heure 4 ; heure 8 : 10 ≥ 8
          mk('P5', 'PARTO-9005', []),
          mk('P6', 'PARTO-9006', [m_(2, 4), m_(4, 3), m_(12, 9)]),              // heure 4 : 3 < 4 franchie
        ];
        poserCol('partogrammes', cas);
        const root = await montage('m4-partogramme');
        const P = { fiches: propre(cas), kpis: kpis(root), cartes: [...root.querySelectorAll('.card .font-semibold, .card-head')].map(txt).filter(Boolean), commandes: [...root.querySelectorAll('button')].map((b) => txt(b)).filter(Boolean) };
        P.sans = { note: !![...root.querySelectorAll('div')].find((d) => /La ligne d’ACTION est franchie/.test(d.textContent) && d.children.length < 6) };
        // un cas par partogramme : choisir dans le combo
        P.cas = [];
        for (const f of cas) {
          const combo = root.querySelector('.combo'); const hostSel = root.querySelector('.combo');
          const sel = root.querySelector('[class*=combo]');
          // le combo expose value et émet change
          const inputs = [...root.querySelectorAll('*')].filter((x) => x.value === (P.cas.length ? cas[P.cas.length - 1].id : 'P1') && x.classList && x.classList.contains('combo'));
          const cb = root.querySelector('div.combo');
          cb.value = f.id; cb.dispatchEvent(new Event('change')); await dormir(150);
          P.cas.push({ id: f.id, ref: f.reference, note: /La ligne d’ACTION est franchie/.test(root.textContent), mesures: lignesTexte(root), enTete: txt(root.querySelector('.card .card-head, .card h3, .card .font-semibold')), texteNote: txt([...root.querySelectorAll('div')].filter((d) => /La ligne d’ACTION est franchie/.test(d.textContent)).pop()) });
        }
        out.partogramme = P;
        root.remove();
        // ouvrir un partogramme, ajouter des mesures (clôture à 10 cm), impression
        const root2 = await montage('m4-partogramme');
        bouton(root2, 'Ouvrir un partogramme').click(); await dormir(120);
        const initial = champsModale(); poser('patientCode', F.code); poser('debut', '2026-08-16T08:00'); poser('gestite', '2'); poser('parite', '1'); poser('accoucheur', SF); viderToasts();
        const avant = new Set(col('partogrammes').all().map((x) => x.id));
        boutonModale('Ouvrir').click(); await dormir(180);
        const nouveau = col('partogrammes').all().filter((x) => !avant.has(x.id)).map(net);
        const ouverture = { initial, nouveau, toasts: toasts() };
        const mesures = [];
        const ajouter = async (saisieV) => {
          bouton(root2, 'Ajouter une mesure').click(); await dormir(120);
          const prerempli = champsModale(); Object.entries(saisieV).forEach(([k, v]) => poser(k, v)); viderToasts();
          boutonModale('Enregistrer').click(); await dormir(180);
          const p = net(col('partogrammes').all().find((x) => x.id === nouveau[0].id));
          mesures.push({ saisie: saisieV, prerempli, mesures: p.mesures, clos: p.clos, resume: p.resume || null, toasts: toasts(), modaleOuverte: !!document.querySelector('.modal-root, [role=dialog]') });
          fermer();
        };
        await ajouter({ heure: 0, dilatation: 4, descente: 4, bdf: 140, contractions: 3, ta: '12/8', pouls: 82, liquide: 'C' });
        await ajouter({ heure: 5, dilatation: 4, descente: 3, bdf: 150, contractions: 4, ta: '12/8', pouls: 90, liquide: 'M' });
        await ajouter({ heure: 3, dilatation: 6, bdf: 40 });
        await ajouter({ heure: 7, dilatation: 10, descente: 0, bdf: 138, contractions: 5 });
        P.ouverture = ouverture; P.ajouts = mesures;
        P.imprime = await (async () => { const n = imprimes.length; bouton(root2, 'Imprimer').click(); await dormir(150); fermer(); return propre(imprimes[n]); })();
        root2.remove();
        restaurer();
      }

      /* ================================================================================== DOSSIER OBSTÉTRICAL : numéro, DPA, risque */
      {
        const D0 = col('dossiersObstetricaux').all();
        out.dossier = { nb: D0.length, numeros: D0.map((d) => d.numeroDossier).slice(0, 5), facteurs: propre(D.FACTEURS_SURVEILLANCE) };
        out.dossier.gar = D0.map((d) => [d.numeroDossier, Object.keys(d.facteurs || {}).filter((k) => d.facteurs[k]).length]);
        // la page d'ouverture : valeurs initiales, création réelle, DPA déduite, numéro de série annuelle
        SIGH.app.go = function (id) { window.__navigue = id; };
        const creer = async (nom, saisieV, pre) => {
          window.__navigue = null; try { sessionStorage.clear(); } catch (e) { /* aucun */ }
          const root = await montage('m4-dossier-obstetrical-nouveau');
          const initial = champsModale();
          Object.entries(saisieV).forEach(([k, v]) => poser(k, v));
          const avant = new Set(col('dossiersObstetricaux').all().map((x) => x.id)); viderToasts();
          const b = [...root.querySelectorAll('button')].find((x) => txt(x) === 'Ouvrir le dossier') || boutonModale('Ouvrir le dossier'); b.click(); await dormir(200);
          out.dossier.creations = out.dossier.creations || [];
          out.dossier.creations.push({ nom, saisie: saisieV, initial, nouvelles: col('dossiersObstetricaux').all().filter((x) => !avant.has(x.id)).map(net), toasts: toasts(), differe: Object.entries(sessionStorage).map(([k, v]) => v), navigue: window.__navigue });
          fermer(); root.remove();
        };
        await creer('sans facteur', { patientCode: F.code, dateEntree: '2026-08-16', ddr: '2026-05-10', gestite: 2, parite: 1, statutDossier: 'suivi' });
        await creer('deux facteurs cochés, numéro déjà pris', { patientCode: F2.code, dateEntree: '2026-08-16', numeroDossier: '00001/26', ddr: '2025-12-31', gestite: 7, parite: 7, facteur_parite: true, facteur_hta: true, referee: true, refereePar: 'CS Kouandé', statutDossier: 'suivi' });
        await creer('DDR manquante (refus)', { patientCode: F.code, dateEntree: '2026-08-16', gestite: 1, parite: 0 });
        // la série annuelle : le numéro proposé se lit sur le registre (archivés compris), d'après l'année de l'horloge
        out.dossier.series = [];
        for (const [nom, numeros] of [['registre vide', []], ['trois années, un archivé, un numéro illisible, un non rempli',
          [['00007/25', 'actif'], ['00031/26', 'actif'], ['bidon', 'actif'], ['00040/26', 'archive'], ['12/26', 'actif'], ['00999/27', 'actif']]], ['aucun numéro de l\'année', [['00041/25', 'actif']]]]) {
          poserCol('dossiersObstetricaux', numeros.map(([n, st], i) => ({ id: 'X' + i, numeroDossier: n, statut: st })));
          const r3 = await montage('m4-dossier-obstetrical-nouveau');
          out.dossier.series.push({ nom, numeros, propose: champsModale().find((c) => c[0] === 'numeroDossier')[1] });
          fermer(); r3.remove();
        }
        restaurer();
        // modification en modale (le risque se déduit du cumul)
        const root = await montage('m4-dossier-obstetrical');
        const q = root.querySelector('input[placeholder^="Rechercher"]'); q.value = '00003/26'; q.dispatchEvent(new Event('input')); await dormir(450);
        const tr = [...root.querySelectorAll('tbody tr')].find((x) => txt(x).includes('00003/26'));
        const avant3 = net(col('dossiersObstetricaux').all().find((x) => x.numeroDossier === '00003/26'));
        bouton(tr, 'Modifier').click(); await dormir(120);
        const prerempli = champsModale(); poser('facteur_diabete', true); poser('ddr', '2026-03-01'); viderToasts();
        boutonModale('Enregistrer').click(); await dormir(180);
        const apres3 = net(col('dossiersObstetricaux').all().find((x) => x.numeroDossier === '00003/26'));
        out.dossier.modification = { avant: avant3, prerempli, apres: apres3, toasts: toasts() };
        fermer(); root.remove();
        // la fiche : les cinq onglets
        const root2 = await montage('m4-dossier-obstetrical');
        bouton(root2.querySelector('tbody tr'), 'Consulter').click(); await dormir(200);
        const dr = document.querySelector('.drawer-backdrop');
        out.dossier.fiche = { kpis: kpis(dr), onglets: [...dr.querySelectorAll('[role=tab]')].map(txt), parOnglet: [] };
        for (const tab of [...dr.querySelectorAll('[role=tab]')]) { tab.click(); await dormir(120); out.dossier.fiche.parOnglet.push({ onglet: txt(tab), texte: txt(dr.querySelector('.overflow-y-auto')), cartes: [...dr.querySelectorAll('.card > .card-head, .card h3, .card .font-semibold')].map(txt) }); }
        out.dossier.fiche.ref = txt(root2.querySelector('tbody tr td'));
        fermer(); root2.remove();
        restaurer();
      }
      return out;
    });
    const doc = { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-maternite.js — ne pas éditer.' };
    const V = path.join(REPO, 'packages/domaine/test/vecteurs');
    ecrire('packages/domaine/test/vecteurs/mat_lectures.json', Object.assign({}, doc, { jour: sortie.jour, lectures: sortie.lectures, comptesRendus: sortie.comptesRendus, impressions: sortie.impressions }));
    ecrire('packages/domaine/test/vecteurs/mat_saisies.json', Object.assign({}, doc, { contexte: sortie.contexte, saisies: sortie.saisies, cpnVisite: sortie.cpnVisite, cpnVisiteRefus: sortie.cpnVisiteRefus, cpnGar: sortie.cpnGar }));
    ecrire('packages/domaine/test/vecteurs/mat_regles.json', Object.assign({}, doc, { nouveauNe: sortie.nouveauNe, partogramme: sortie.partogramme, dossier: sortie.dossier }));
    /* Le référentiel : un littéral Dart constant, engendré (le domaine n'a pas d'accès aux fichiers à l'exécution). */
    const lit = JSON.stringify(sortie.referentiels, null, 1).replace(/\$/g, '\\$');
    fs.mkdirSync(path.join(REPO, 'packages/domaine/lib/src/maternite'), { recursive: true });
    fs.writeFileSync(path.join(REPO, 'packages/domaine/lib/src/maternite/mat_donnees.dart'),
      '// ENGENDRÉ par prototype_html/build/vecteurs-maternite.js depuis assets/js/data-maternite.js, data-clinique.js et data.js — NE PAS ÉDITER.\n'
      + '// Référentiels de la maternité tracés vers le rapport officiel du 27/08/2026 (10 fonctions SONU, 15 méthodes PF, codification A/N, bornes écrites, partographie).\n'
      + 'const Map<String, Object?> matDonnees = ' + lit + ';\n');
    console.log('  écrit : packages/domaine/lib/src/maternite/mat_donnees.dart');
    console.log('  écrans lus : ' + Object.keys(sortie.lectures).length + ' · saisies : ' + sortie.saisies.length);
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
