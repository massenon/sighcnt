/* =============================================================================
 * VECTEURS DE L'IMAGERIE (5 modalités) ET DE LA MÉCANIQUE DU COMPTE RENDU — les écrans RÉELS pilotés comme le fait l'agent
 * -----------------------------------------------------------------------------
 * Le script monte les cinq tableaux (`m2-imagerie`, `-radiographie`, `-mammographie`, `-scanner`, `-irm`) et la page `m2-imagerie-cr`
 * sur le jeu COMPLET (peuplement des parcours), puis relève : indicateurs, lignes du registre (toutes les pages), tiroir « Consulter » et
 * pièce imprimée de chaque compte rendu, formulaire de chaque examen du catalogue (cartes, champs, blocs répétés, champs conditionnels),
 * l'en-tête (modale) et les gestes d'écriture (enregistrer, rendre, nouveau compte rendu).
 *   node build/vecteurs-imagerie-cr.js   →   packages/domaine/test/vecteurs/imagerie-cr.json
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs de l\'imagerie (tableaux et compte rendu)');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m2-consultations.js') });
    const sortie = await m.page.evaluate(async () => {
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
      const S = SIGH.store, U = SIGH.ui, P = SIGH.print;
      SIGH.peuplerParcours();
      const col = S.collection('resultatsImagerie'), colD = S.collection('demandesImagerie'), colN = S.collection('notifications');
      const brut = (s) => String(s).replace(/\s+/g, ' ').trim();

      /* --- espions : navigation, messages, confirmations, pièce imprimée --- */
      const aller = [], toasts = [], differes = [], confirms = [], imprimes = [];
      SIGH.app = SIGH.app || {};
      SIGH.app.go = (id, p) => { aller.push({ id, p: p || null }); };
      const toastO = U.toast; U.toast = (t, o) => { toasts.push({ texte: String(t), type: (o && o.type) || null, detail: (o && o.detail) || null }); return toastO.call(U, t, o); };
      U.toastDiffere = (t, o) => { differes.push({ texte: String(t), type: (o && o.type) || null, detail: (o && o.detail) || null }); };
      U.confirm = (o) => { confirms.push({ titre: o.title, message: brut(String(o.message || '').replace(/<[^>]+>/g, '')), libelle: o.confirmLabel }); return Promise.resolve(true); };
      P.etat = (o) => {
        const contenu = [];
        [...(o.contenu ? o.contenu.children : [])].forEach((n) => {
          const gras = !!n.querySelector('.font-bold') || /font-(bold|semibold)/.test(n.className || '') && n.tagName === 'P' && !n.querySelector('.font-medium');
          contenu.push({ t: brut(n.textContent), gras: n.className.indexOf('font-semibold') >= 0 || n.className.indexOf('font-bold') >= 0 || !!n.querySelector('.font-bold') });
        });
        imprimes.push({ titre: o.titre, sousTitre: o.sousTitre, cartouche: o.cartouche, contenu, signatures: o.signatures });
      };
      const vider = () => { aller.length = 0; toasts.length = 0; differes.length = 0; confirms.length = 0; imprimes.length = 0; };

      const nettoyerCouches = () => document.querySelectorAll('aside, [role=dialog], .modal-root, .drawer-root').forEach((e) => e.remove());
      const montrer = async (id, hash) => {
        document.querySelectorAll('#page-content').forEach((e) => e.remove());
        location.hash = hash || '';
        const root = document.createElement('div'); root.id = 'page-content'; document.body.appendChild(root);
        SIGH.screens[id].render(root); await dormir(60);
        return root;
      };

      /* --- 1. LES CINQ TABLEAUX --- */
      const ECRANS = { echographie: 'm2-imagerie', radiographie: 'm2-imagerie-radiographie', mammographie: 'm2-imagerie-mammographie', scanner: 'm2-imagerie-scanner', irm: 'm2-imagerie-irm' };
      const ecrans = {}, details = [];
      for (const [modalite, id] of Object.entries(ECRANS)) {
        vider(); nettoyerCouches();
        const root = await montrer(id);
        const fiche = {};
        fiche.id = id; fiche.titre = brut(document.querySelector('h1') ? document.querySelector('h1').textContent : '');
        fiche.kpis = [...root.querySelectorAll('.kpi')].map((k) => ({ label: brut(k.querySelector('.kpi-label').textContent), value: brut(k.querySelector('.kpi-value').textContent), hint: (() => { const p = [...k.querySelectorAll('p')].filter((x) => !x.classList.contains('kpi-label') && !x.classList.contains('kpi-value')); return p.length ? brut(p[0].textContent) : null; })() }));
        fiche.blocs = [...root.firstElementChild.children].filter((n) => n.className.split(' ')[0] !== 'card').map((n) => ({ classe: n.className.split(' ')[0], texte: brut(n.textContent).slice(0, 700) }));
        fiche.entete = [...root.querySelectorAll('thead th')].map((t) => brut(t.textContent));
        fiche.commandes = [...root.querySelectorAll('button')].filter((b) => !b.closest('tbody')).map((b) => brut(b.getAttribute('aria-label') || b.title || b.textContent)).filter(Boolean);
        fiche.filtres = [...root.querySelectorAll('select')].map((s) => ({ label: brut(s.getAttribute('aria-label') || (s.previousElementSibling && s.previousElementSibling.textContent) || ''), options: [...s.options].map((o) => [o.value, brut(o.textContent)]) }));
        fiche.vide = brut((root.querySelector('tbody') || {}).textContent || '').slice(0, 80);
        fiche.pages = [];
        const lignes = [];
        const rowsDe = () => [...root.querySelectorAll('tbody tr')];
        for (let p = 1; p <= 12; p++) {
          const rows = rowsDe();
          const lignesPage = [];
          for (let i = 0; i < rows.length; i++) {
            const tr = rowsDe()[i];
            const cellules = [...tr.querySelectorAll('td')].map((td) => brut(td.textContent));
            const boutons = [...tr.querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
            if (!tr.querySelector('button')) { lignesPage.push({ cellules, boutons }); continue; }
            const ref = cellules[1] || cellules[0];
            const lig = { cellules, boutons, fiche: propre(col.all().filter((x) => x.reference === cellules[0])[0]) };
            /* Consulter */
            vider(); nettoyerCouches();
            [...tr.querySelectorAll('button')].find((b) => (b.getAttribute('aria-label') || b.title) === 'Consulter').click(); await dormir(40);
            const dr = [...document.querySelectorAll('aside, [role=dialog], .drawer')].pop();
            if (dr) {
              lig.tiroir = {
                titre: brut((dr.querySelector('h2, h3') || {}).textContent || ''),
                paires: [...dr.querySelectorAll('dl > div')].map((d) => [brut(d.querySelector('dt').textContent), brut(d.querySelector('dd').textContent)]),
                tableau: [...dr.querySelectorAll('tbody tr')].map((r) => [...r.querySelectorAll('td')].map((c) => brut(c.textContent))),
                sections: [...dr.querySelectorAll('p.whitespace-pre-line')].map((x) => ({ texte: brut(x.textContent), titre: brut(((x.closest('section') || x.parentElement).querySelector('h3, h4, p') || {}).textContent || '') })),
              };
            }
            nettoyerCouches();
            /* Imprimer */
            vider();
            [...tr.querySelectorAll('button')].find((b) => (b.getAttribute('aria-label') || b.title) === 'Imprimer le compte rendu').click(); await dormir(20);
            lig.impression = imprimes.length ? propre(imprimes[0]) : null;
            lignesPage.push(lig);
          }
          fiche.pages.push(lignesPage);
          const suivant = [...root.querySelectorAll('button')].find((b) => brut(b.textContent) === String(p + 1) && !b.closest('tbody'));
          if (!suivant) break;
          suivant.click(); await dormir(40);
        }
        ecrans[modalite] = fiche;
      }

      /* --- 2. LE FORMULAIRE DE CHAQUE EXAMEN --- */
      const lireChamps = (form) => [...form.children].map((w) => {
        const lbl = w.querySelector('label.label'); const ctrl = w.querySelector('input, select, textarea, .combo, button.combo');
        const genre = !ctrl ? 'section' : (ctrl.classList.contains('combo') ? 'combo' : ctrl.tagName.toLowerCase() + (ctrl.tagName === 'INPUT' ? ':' + ctrl.type : ''));
        const aide = w.querySelector('p.text-slate-400');
        return { label: lbl ? brut(lbl.textContent) : brut(w.textContent), nom: ctrl && ctrl.id ? ctrl.id.replace(/^f_/, '') : null, genre, cache: w.classList.contains('hidden'),
          options: ctrl && ctrl.tagName === 'SELECT' ? [...ctrl.options].map((o) => o.value) : null, aide: aide ? brut(aide.textContent) : null, col: (w.className.match(/sm:col-span-(\d)/) || [])[1] };
      });
      const lireCartes = (root) => {
        const out = [];
        [...root.querySelectorAll('.card')].forEach((c) => {
          const titre = brut((c.querySelector('.card-title') || {}).textContent || '');
          const forms = [...c.querySelectorAll(':scope > .card-body form')];
          const blocs = [...c.querySelectorAll('details')].map((d) => ({ resume: brut(d.querySelector('summary').textContent), cache: d.classList.contains('hidden'), champs: lireChamps(d.querySelector('form')) }));
          const principal = c.querySelector(':scope > .card-body > div > form, :scope > .card-body > form');
          if (!principal && !blocs.length) { out.push({ titre, champs: null }); return; }
          out.push({ titre, champs: principal ? lireChamps(principal) : [], blocs });
        });
        return out;
      };
      const examens = S.collection('examensImagerie').active();
      const formulaires = {};
      const tmp = [];
      for (const ex of examens) {
        const r = col.insert({ reference: 'TEST-' + ex.code, date: '2026-10-30T10:00:00.000Z', examenCode: ex.code, examen: ex.label, patientId: null, patient: 'TEST', patientCode: 'CNT/0/26', age: 30, indication: 'x', ddr: 'inconnue', condition: 'Bonne', prescripteur: 'P', realisateurId: null, realisateur: 'R', valeurs: {}, annexes: '', conclusion: '', statut: 'brouillon' }).record;
        tmp.push(r.id);
        const root = await montrer('m2-imagerie-cr', '#id=' + r.id + '&retour=m2-imagerie');
        formulaires[ex.code] = { modalite: SIGH.data ? null : null, cartes: lireCartes(root).filter((c) => c.champs !== null && !/Enchaînement|Règles de saisie|^Examen$/.test(c.titre)) };
        formulaires[ex.code].enteteCarte = lireCartes(root).filter((c) => c.titre === 'Examen').length;
        formulaires[ex.code].boutons = [...root.querySelectorAll('button')].map((b) => brut(b.textContent)).filter(Boolean);
      }
      tmp.forEach((id) => col.archive(id));

      /* --- 3. LES BLOCS RÉPÉTÉS ET LES CHAMPS CONDITIONNELS (échographie du 1er trimestre) --- */
      const poser = (root, nom, v) => { const c = root.querySelector('#f_' + nom); if (!c) throw new Error('champ ' + nom); c.value = v; c.dispatchEvent(new Event('input')); c.dispatchEvent(new Event('change')); };
      const etatBlocs = (root) => [...root.querySelectorAll('details')].map((d) => [d.getAttribute('data-exemplaire'), d.classList.contains('hidden')]);
      const cacheDe = (root, nom) => root.querySelector('#f_' + nom).parentElement.classList.contains('hidden');
      const dyn = [];
      {
        const r = col.insert({ reference: 'TEST-DYN', date: '2026-10-30T10:00:00.000Z', examenCode: 'IMG-ECHO-OBS1', examen: 'x', patientId: null, patient: 'TEST', patientCode: 'CNT/0/26', age: 30, indication: 'x', ddr: 'inconnue', condition: 'Bonne', prescripteur: 'P', realisateurId: null, realisateur: 'R', valeurs: {}, annexes: '', conclusion: 'ok', statut: 'brouillon' }).record;
        const root = await montrer('m2-imagerie-cr', '#id=' + r.id + '&retour=m2-imagerie');
        dyn.push({ etape: 'à l\'ouverture', blocs: etatBlocs(root), precision: cacheDe(root, 'SG_LOC_AUTRE') });
        for (const v of ['01', '02', '03', 'autre', '']) { poser(root, 'SG_NB', v); dyn.push({ etape: 'SG_NB = ' + JSON.stringify(v), blocs: etatBlocs(root) }); }
        poser(root, 'SG_LOC', 'Autre'); dyn.push({ etape: 'SG_LOC = Autre', precision: cacheDe(root, 'SG_LOC_AUTRE') });
        poser(root, 'SG_LOC', 'intra-utérine'); dyn.push({ etape: 'SG_LOC = intra-utérine', precision: cacheDe(root, 'SG_LOC_AUTRE') });
        poser(root, 'SG_LOC', 'Autre'); poser(root, 'SG_LOC_AUTRE', 'ectopique tubaire'); poser(root, 'SG_NB', '02'); poser(root, 'SG_ASP__2', 'tonique'); poser(root, 'SG_DIM__2', '8 mm');
        poser(root, 'SG_LOC', 'intra-utérine'); poser(root, 'SG_NB', '01');
        vider(); root.__enregistrerCR(); await dormir(40);
        const apres = col.get(r.id);
        dyn.push({ etape: 'enregistrer après retrait des valeurs masquées', valeurs: propre(apres.valeurs), aller: propre(aller), differes: propre(differes) });
        col.archive(r.id);
      }

      /* --- 4. ENREGISTRER / RENDRE --- */
      const gestes = [];
      const choisirBrouillon = (modalite, avecDemande) => col.active().filter((x) => x.statut !== 'rendu' && (x.demandeImagerieId ? avecDemande : !avecDemande)).filter((x) => {
        const ex = S.collection('examensImagerie').active().filter((e) => e.code === x.examenCode)[0]; return ex && ex.modalite === modalite; })[0];
      const instantane = () => ({ cr: propre(col.all()), dem: propre(colD.all()), notif: propre(colN.all()) });
      const diff = (avant, apres) => {
        const out = { creees: [], modifiees: [] };
        ['cr', 'dem', 'notif'].forEach((k) => {
          const a = new Map(avant[k].map((x) => [x.id, x]));
          apres[k].forEach((x) => {
            if (!a.has(x.id)) out.creees.push({ coll: k, fiche: x });
            else if (JSON.stringify(a.get(x.id)) !== JSON.stringify(x)) {
              const champs = {}; Object.keys(x).forEach((c) => { if (JSON.stringify(x[c]) !== JSON.stringify(a.get(x.id)[c])) champs[c] = x[c]; });
              out.modifiees.push({ coll: k, id: x.id, champs });
            }
          });
        });
        return out;
      };
      const net = (d) => { const f = (x) => { const c = Object.assign({}, x); ['_creePar', '_creeLe', '_modifiePar', '_modifieLe'].forEach((k) => delete c[k]); return c; };
        return { creees: d.creees.map((c) => ({ coll: c.coll, fiche: f(c.fiche) })), modifiees: d.modifiees.map((c) => { const ch = Object.assign({}, c.champs); ['_modifiePar', '_modifieLe'].forEach((k) => delete ch[k]); return { coll: c.coll, id: c.id, champs: ch }; }) }; };

      /* a. enregistrer sans conclusion (échographie) : refusé */
      {
        const r = choisirBrouillon('echographie', true) || choisirBrouillon('echographie', false);
        const root = await montrer('m2-imagerie-cr', '#id=' + r.id + '&retour=m2-imagerie');
        const av = instantane(); vider();
        root.__enregistrerCR(); await dormir(30);
        gestes.push({ nom: 'enregistrer sans conclusion : refusé, rien n\'est écrit (la conclusion est obligatoire)', ref: r.reference, toasts: propre(toasts), differes: propre(differes), aller: propre(aller), ecritures: net(diff(av, instantane())) });
      }
      /* b. enregistrer avec conclusion (radiographie, brouillon lié à une demande payée) */
      {
        const r = choisirBrouillon('radiographie', true) || choisirBrouillon('radiographie', false);
        const root = await montrer('m2-imagerie-cr', '#id=' + r.id + '&retour=m2-imagerie-radiographie');
        const dem = r.demandeImagerieId ? colD.get(r.demandeImagerieId) : null;
        if (dem) colD.update(dem.id, { statut: 'payee' });
        poser(root, 'resultats', 'Pas de lésion osseuse.'); poser(root, 'conclusion', 'Examen normal.'); poser(root, 'recommandation', 'Contrôle si douleur.');
        const av = instantane(); vider();
        root.__enregistrerCR(); await dormir(30);
        gestes.push({ nom: 'enregistrer avec conclusion : valeurs, rubriques rédigées, demande « payée » → « exécutée »', ref: r.reference, avecDemande: !!dem, statutDemandeAvant: 'payee', toasts: propre(toasts), differes: propre(differes), aller: propre(aller), ecritures: net(diff(av, instantane())) });
      }
      /* c. rendre sans conclusion / avec conclusion (par le tableau) */
      for (const [modalite, conclusion] of [['mammographie', ''], ['scanner', 'Pas d\'anomalie.']]) {
        const r = choisirBrouillon(modalite, true) || choisirBrouillon(modalite, false);
        col.update(r.id, { conclusion });
        const dem = r.demandeImagerieId ? colD.get(r.demandeImagerieId) : null;
        if (dem) colD.update(dem.id, { statut: 'executee' });
        const root = await montrer(ECRANS[modalite]);
        const av = instantane(); vider();
        const ligne = [...root.querySelectorAll('tbody tr')].find((tr) => tr.textContent.indexOf(r.reference) >= 0);
        if (!ligne) { gestes.push({ nom: 'rendre : ligne introuvable ' + r.reference }); continue; }
        [...ligne.querySelectorAll('button')].find((b) => (b.getAttribute('aria-label') || b.title) === 'Rendre au prescripteur').click(); await dormir(60);
        gestes.push({ nom: conclusion ? 'rendre avec conclusion : « rendu », demande « validée », notification au poste consultation' : 'rendre sans conclusion : refusé en le disant', modalite, ref: r.reference, avecDemande: !!dem, confirms: propre(confirms), toasts: propre(toasts), ecritures: net(diff(av, instantane())),
          boutonsApres: [...(([...root.querySelectorAll('tbody tr')].find((tr) => tr.textContent.indexOf(r.reference) >= 0)) || document.createElement('tr')).querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title) });
      }
      /* d. nouveau compte rendu : l'en-tête déposé, la page, la fiche qui naît à l'enregistrement */
      const nouveaux = [];
      for (const [modalite, codeExamen] of [['echographie', 'IMG-ECHO-PEL'], ['irm', 'IMG-IRM-GEN']]) {
        const patient = S.collection('patients').active()[3];
        const soignant = S.collection('soignants').active().filter((x) => x.realiseImagerie)[0];
        const entete = { examenCode: codeExamen, patientCode: patient.code, indication: 'Douleur', prescripteurId: 'EXTERNE', prescripteurIdExterne: 'Dr SALIFOU Aminou, CS de Perma', realisateurId: soignant.id, condition: 'Moyenne', ddr: 'inconnue', provenance: 'CS de Perma' };
        sessionStorage.setItem('sigh-cnt:cr-entete', JSON.stringify(entete));
        const avantN = col.all().length;
        const root = await montrer('m2-imagerie-cr', '#nouveau=1&modalite=' + modalite + '&retour=' + ECRANS[modalite]);
        const cartes = [...root.querySelectorAll('.card')].map((c) => brut((c.querySelector('.card-title') || {}).textContent || ''));
        const entetePage = [...root.querySelectorAll('dl > div')].map((d) => [brut(d.querySelector('dt').textContent), brut(d.querySelector('dd').textContent)]);
        const note = brut((root.querySelector('.note, [class*=bg-sky], [class*=bg-blue]') || {}).textContent || '');
        const dedans = sessionStorage.getItem('sigh-cnt:cr-entete');
        poser(root, 'conclusion', 'Conclusion test.');
        const av = instantane(); vider();
        root.__enregistrerCR(); await dormir(30);
        nouveaux.push({ modalite, entete, cartesPage: cartes, entetePage, nbAvant: avantN, enteteRestante: dedans, differes: propre(differes), aller: propre(aller), toasts: propre(toasts), ecritures: net(diff(av, instantane())) });
      }
      /* d2. adresse ouverte à froid / fiche introuvable / droits */
      const froid = [];
      {
        sessionStorage.removeItem('sigh-cnt:cr-entete');
        const root = await montrer('m2-imagerie-cr', '#nouveau=1&modalite=scanner&retour=m2-imagerie-scanner');
        froid.push({ nom: 'sans en-tête', texte: brut(root.innerText), boutons: [...root.querySelectorAll('button')].map((b) => brut(b.textContent)).filter(Boolean) });
        const root2 = await montrer('m2-imagerie-cr', '#id=INCONNU&retour=m2-imagerie');
        froid.push({ nom: 'fiche introuvable', texte: brut(root2.innerText), boutons: [...root2.querySelectorAll('button')].map((b) => brut(b.textContent)).filter(Boolean) });
      }

      /* --- 5. L'EN-TÊTE (MODALE) --- */
      const entetes = {};
      const soignantsRealisateurs = S.collection('soignants').active().filter((x) => x.realiseImagerie || x.qualite === 'medecin');
      for (const modalite of Object.keys(ECRANS)) {
        vider(); nettoyerCouches();
        const root = await montrer(ECRANS[modalite]);
        [...root.querySelectorAll('button')].find((b) => brut(b.textContent) === 'Nouveau compte rendu').click(); await dormir(80);
        const dlg = [...document.querySelectorAll('[role=dialog], .modal-root')].pop();
        const f = dlg.querySelector('form');
        const e = { titre: brut((dlg.querySelector('h2, h3') || {}).textContent || ''), sousTitre: brut(dlg.innerText).slice(0, 180), champs: lireChamps(f), boutons: [...dlg.querySelectorAll('button')].map((b) => brut(b.textContent)).filter(Boolean) };
        /* validation à vide */
        [...dlg.querySelectorAll('button')].find((b) => brut(b.textContent) === 'Continuer vers la saisie').click(); await dormir(40);
        e.videToasts = propre(toasts); e.videAller = propre(aller); vider();
        /* options des listes natives */
        e.options = {}; [...f.querySelectorAll('select')].forEach((s) => { e.options[s.name] = [...s.options].map((o) => [o.value, brut(o.textContent)]); });
        /* validation complète */
        const ex = S.collection('examensImagerie').active().filter((x) => x.modalite === modalite)[0];
        const pat = S.collection('patients').active()[1];
        const ctl = f.controls;
        ctl.examenCode.value = ex.code; ctl.patientCode.value = pat.code; ctl.indication.value = 'Contrôle'; ctl.realisateurId.value = soignantsRealisateurs[0].id;
        ['examenCode', 'patientCode', 'realisateurId', 'prescripteurId'].forEach((n) => { if (ctl[n]) { ctl[n].dispatchEvent(new Event('change')); } });
        if (ctl.prescripteurId) { ctl.prescripteurId.value = ctl.prescripteurId.options ? ctl.prescripteurId.options[0].value : ctl.prescripteurId.value; ctl.prescripteurId.dispatchEvent(new Event('change')); }
        sessionStorage.removeItem('sigh-cnt:cr-entete');
        [...dlg.querySelectorAll('button')].find((b) => brut(b.textContent) === 'Continuer vers la saisie').click(); await dormir(40);
        e.okAller = propre(aller); e.okDepose = JSON.parse(sessionStorage.getItem('sigh-cnt:cr-entete') || 'null'); e.okToasts = propre(toasts);
        sessionStorage.removeItem('sigh-cnt:cr-entete');
        nettoyerCouches();
        entetes[modalite] = e;
      }
      const variables = S.collection('variablesImagerie').active(), catalogue = S.collection('examensImagerie').active();
      const ordreMagasin = col.active().filter((x) => !/^TEST-/.test(x.reference)).map((x) => x.reference);
      return propre({ ordreMagasin, variables, catalogue, ecrans, formulaires, dyn, gestes, nouveaux, froid, entetes, examens: examens.map((x) => ({ code: x.code, modalite: x.modalite })) });
    });
    const n = Object.values(sortie.ecrans).reduce((s, e) => s + e.pages.reduce((t, p) => t + p.length, 0), 0);
    console.log('  tableaux : ' + Object.entries(sortie.ecrans).map(([k, e]) => k + ' ' + e.pages.reduce((t, p) => t + p.length, 0)).join(' · ') + ' (' + n + ' lignes)');
    console.log('  formulaires : ' + Object.keys(sortie.formulaires).length + ' examens · gestes : ' + sortie.gestes.length + ' · nouveaux : ' + sortie.nouveaux.length);
    ecrire('packages/domaine/test/vecteurs/imagerie-cr.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-imagerie-cr.js — les cinq tableaux d\'imagerie et la page de compte rendu PILOTÉS. Ne pas éditer.' }, sortie));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
