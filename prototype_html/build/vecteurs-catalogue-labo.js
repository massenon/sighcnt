/* =============================================================================
 * VECTEURS DU PARAMÉTRAGE DU LABORATOIRE — m5-catalogue, m5-unites, m5-valeurs-reference, m5-reactifs (+ le moteur des plages par lot)
 * -----------------------------------------------------------------------------
 * Les écrans réels sont montés dans la page d'extraction, leurs filtres posés, leurs formulaires remplis, leurs boutons cliqués ; ce qui est né au
 * magasin, ce que l'écran affiche et ce que « Imprimer » passe à `P.etat` sont relus. L'horloge est FIXÉE au 30/10/2026 (le module lit `C.aujourdhui()`
 * à son chargement) : les vecteurs ne dépendent pas du jour d'exécution.
 *   node build/vecteurs-catalogue-labo.js   →   packages/domaine/test/vecteurs/cat_*.json
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs du paramétrage du laboratoire');
  const m = await ouvrirMaquette();
  try {
    await m.page.evaluate(() => { SIGH.core.aujourdhui = function () { return new Date(2026, 9, 30, 12, 0, 0); }; });
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m5-laboratoire.js') });
    const sortie = await m.page.evaluate(async () => {
      const S = SIGH.store, C = SIGH.core, D = SIGH.data, L = SIGH.labo;
      const propre = (x) => JSON.parse(JSON.stringify(x));
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const txt = (e) => (e ? e.innerText.replace(/\s+/g, ' ').trim() : null);
      const net = (x) => { const c = Object.assign({}, x); ['_creePar', '_creeLe', '_modifiePar', '_modifieLe', '_archivePar', '_archiveLe'].forEach((k) => delete c[k]); return propre(c); };
      const toasts = () => [...document.querySelectorAll('#toast-host > div')].map((n) => [...n.querySelectorAll('p')].map((p) => p.textContent.trim()));
      const viderToasts = () => { const h = document.getElementById('toast-host'); if (h) h.innerHTML = ''; };
      const fermer = () => document.querySelectorAll('.modal-root, [role=dialog]').forEach((e) => { if (!e.closest('#page-content')) e.remove(); });
      const bouton = (racine, texte) => [...racine.querySelectorAll('button')].find((b) => b.textContent.trim() === texte || b.getAttribute('aria-label') === texte || b.title === texte);
      const boutonModale = (texte) => [...document.querySelectorAll('button')].filter((b) => b.textContent.trim() === texte).pop();
      const poser = (id, v) => { const e = document.getElementById('f_' + id); if (!e) throw new Error('champ ' + id); if (e.type === 'checkbox') { e.checked = !!v; } else { e.value = v; } e.dispatchEvent(new Event('input')); e.dispatchEvent(new Event('change')); };
      const champsModale = () => [...document.querySelectorAll('[id^=f_]')].map((e) => [e.id.slice(2), e.type === 'checkbox' ? e.checked : (e.value === undefined ? null : e.value)]);
      const montage = async (id) => { const root = document.createElement('div'); root.id = 'page-content'; document.body.appendChild(root); SIGH.screens[id].render(root); await dormir(120); return root; };
      const tablesDe = (e) => [...e.querySelectorAll('*')].filter((x) => typeof x.lignesFiltrees === 'function');
      const kpis = (root) => [...root.querySelectorAll('.kpi')].map((k) => ({ label: txt(k.querySelector('.kpi-label')), valeur: txt(k.querySelector('.kpi-value')), indice: txt(k.querySelector('p.text-xs')) || null }));
      const lignesTexte = (root, n) => [...root.querySelectorAll('tbody tr')].slice(0, n || 9999).map((tr) => [...tr.querySelectorAll('td')].map((c) => txt(c)));
      const dernierLog = () => { const a = S.collection('audit').all()[0] || {}; return propre({ action: a.action, module: a.module, entite: a.entite, reference: a.reference, avant: a.avant, apres: a.apres, utilisateur: a.utilisateur }); };
      const changer = (e, v) => { e.value = v; e.dispatchEvent(new Event('change')); };

      /* --- interception de l'impression ------------------------------------------------------------------------------------ */
      const imprimes = [];
      const etatOrig = SIGH.print.etat;
      function lireContenu(n) {
        const blocs = [];
        [...(n.matches('table, p, h3, h4') ? [n] : []), ...n.querySelectorAll('table, p, h3, h4')].forEach((e) => {
          if (e.tagName === 'TABLE') {
            blocs.push({ table: { entetes: [...e.querySelectorAll('thead th')].map(txt), lignes: [...e.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map(txt)),
              pied: e.querySelector('tfoot tr') ? [...e.querySelector('tfoot tr').children].map(txt) : null } });
          } else if (!e.closest('table')) { blocs.push({ texte: txt(e) }); }
        });
        return blocs;
      }
      SIGH.print.etat = function (o) {
        const rec = { titre: o.titre, sousTitre: o.sousTitre || null, cartouche: propre(o.cartouche || null), signatures: propre(o.signatures || null), contenu: lireContenu(o.contenu) };
        const r = etatOrig.apply(this, arguments);
        const feuilles = document.querySelectorAll('.print-sheet');
        const feuille = feuilles[feuilles.length - 1];
        rec.filtres = [];
        if (feuille) {
          const brut = (e) => e.textContent.replace(/\s+/g, ' ').trim();
          const titre = [...feuille.querySelectorAll('p')].find((p) => brut(p) === 'Filtres appliqués à cet état');
          if (titre) [...titre.parentElement.querySelectorAll('.flex-wrap > span')].forEach((sp) => { rec.filtres.push([brut(sp.children[0]).replace(/ :$/, ''), brut(sp.children[1])]); });
        }
        imprimes.push(rec);
        return r;
      };

      const out = {};
      const jour = C.iso(C.aujourdhui());
      out.jour = jour;

      /* ==================================================================================================================== moteur */
      const LP = SIGH.laboPlages;
      const colPl = S.collection('plagesReactif');
      const sauvePl = colPl.all().splice(0);
      const V = { id: 'V1', code: 'GB', libelle: 'Globules blancs', type: 'numerique', min: 4, max: 8 };
      const pl = (id, extra) => Object.assign({ id, variableId: 'V1', lot: 'LOT-' + id, dateDebut: '2026-05-01', min: 3.5, max: 9, statut: 'actif' }, extra || {});
      const scenarios = [
        { nom: 'aucune plage : les bornes de la variable font foi', plages: [], dates: ['2026-06-01', '', '2026-10-30T10:00:00'] },
        { nom: 'deux lots versionnés par date d\'entrée en service', plages: [pl('A'), pl('B', { dateDebut: '2026-08-01', min: 4.5, max: 8.5 })],
          dates: ['2026-04-30', '2026-05-01', '2026-07-31T23:59:00', '2026-08-01', '2027-01-01', '2026-08-01T00:00:00.000Z'] },
        { nom: 'insérées dans le désordre : le tri est par date, pas par rang d\'insertion', plages: [pl('B', { dateDebut: '2026-08-01', min: 4.5, max: 8.5 }), pl('A')],
          dates: ['2026-06-15', '2026-09-01'] },
        { nom: 'plage ARCHIVÉE ignorée', plages: [pl('A'), pl('B', { dateDebut: '2026-08-01', statut: 'archive' })], dates: ['2026-09-01'] },
        { nom: 'plage d\'une AUTRE variable ignorée', plages: [pl('A', { variableId: 'V2' })], dates: ['2026-09-01'] },
        { nom: 'plage sans date d\'entrée : vaut depuis toujours, passe avant les datées', plages: [pl('A', { dateDebut: '' }), pl('B', { dateDebut: '2026-08-01', min: 5, max: 7 })],
          dates: ['2020-01-01', '2026-07-01', '2026-08-02'] },
        { nom: 'même date d\'entrée : la dernière du registre l\'emporte (tri stable)', plages: [pl('A'), pl('B', { min: 4.2, max: 8.2 })], dates: ['2026-06-01'] },
        { nom: 'borne haute seule : « < max » ; borne basse seule : « > min »', plages: [pl('A', { min: null, max: 10 }), pl('B', { dateDebut: '2026-08-01', min: 2, max: null })], dates: ['2026-06-01', '2026-09-01'] },
        { nom: 'borne à zéro : le zéro est une borne, pas une absence', plages: [pl('A', { min: 0, max: 5 })], dates: ['2026-06-01'] },
      ];
      out.plages = { _doc: 'SIGH.laboPlages (plagePour / variableALaDate / referenceALaDate) sur des plages posées', jourDefaut: jour, variable: V, cas: [] };
      scenarios.forEach((sc) => {
        colPl.all().splice(0); sc.plages.forEach((p) => colPl.all().push(propre(p)));
        out.plages.cas.push({ nom: sc.nom, plages: propre(sc.plages), resultats: sc.dates.map((d) => {
          const p = LP.plagePour(V, d);
          const v = LP.variableALaDate(V, d);
          return { date: d, plageId: p ? p.id : null, min: v.min === undefined ? null : v.min, max: v.max === undefined ? null : v.max, reference: LP.referenceALaDate(V, d) };
        }) });
      });
      colPl.all().splice(0); sauvePl.forEach((x) => colPl.all().push(propre(x)));

      const refs = [
        { type: 'numerique', min: 4, max: 8 }, { type: 'numerique', max: 6 }, { type: 'numerique', min: 0.35 }, { type: 'numerique' }, { type: 'numerique', min: 0, max: 5 },
        { type: 'numerique', min: 4, max: 8, regle: 'inférieure à la moitié de la glycémie' }, { type: 'binaire', normal: 'Négatif' }, { type: 'binaire' }, { type: 'ternaire', normal: 'Négatif' },
        { type: 'liste', normal: 'Absent' }, { type: 'titre', normal: 'Négatif', min: 4 }, { type: 'texte', min: 1, max: 2 }, { type: 'reactif', normal: 'x', min: 1 }, { type: 'lot' },
        { type: 'expiration' }, { type: 'commentaire', regle: 'ignorée : accompagnement' }, { type: 'commentaire', regle: 'x' }, { type: 'texte', regle: 'règle d\'un texte' }, { type: 'numerique', min: 1.5, max: 4.25 },
      ].map((v) => ({ variable: v, attendu: L.libelleReference(v) }));
      out.references = { _doc: 'L.libelleReference(variable) : la notation du document (« 4 - 8 », « < 6 », « > 0.35 »)', cas: refs,
        types: L.TYPES_VARIABLE.map((t) => [t.id, t.label]), accompagnement: L.TYPES_ACCOMPAGNEMENT.slice(), sections: L.SECTIONS.map((s) => [s.id, s.label]),
        typeInconnu: L.type('zzz'), sectionInconnue: L.section('zzz'), uniteInconnue: L.unite('zzz'), uniteSans: L.unite('sans'), source: L.source };

      /* ==================================================================================================================== catalogue */
      const colA = S.collection('analyses');
      const sauveA = propre(colA.all());
      async function lireCatalogue(root) {
        return { kpis: kpis(root), onglets: [...root.querySelectorAll('[role=tab]')].map((b) => txt(b)) };
      }
      {
        const root = await montage('m5-catalogue');
        const cat = { _doc: 'm5-catalogue : jeu de la maquette (48 analyses)', ...(await lireCatalogue(root)) };
        cat.entetes = [...root.querySelectorAll('thead th')].map((x) => txt(x));
        cat.filtres = [...root.querySelectorAll('select')].map((s) => [...s.options].map((o) => o.value + '|' + o.textContent));
        cat.page1 = lignesTexte(root);
        cat.aide = [...root.querySelectorAll('tbody tr')].map((tr) => !!tr.querySelector('[title="Tarif à confirmer"]'));
        cat.nbLignes = tablesDe(root)[0].lignesFiltrees().length;
        /* Onglet « Par catégorie » */
        [...root.querySelectorAll('[role=tab]')].find((b) => txt(b) === 'Par catégorie').click(); await dormir(80);
        cat.parCategorie = [...root.querySelectorAll('.card')].filter((c) => c.querySelector('ul')).map((c) => ({ titre: txt(c.querySelector('span.text-sm.font-semibold')), badge: txt(c.querySelector('.badge, span[class*=badge]')) || txt(c.querySelectorAll('span')[1]),
          lignes: [...c.querySelectorAll('li')].map((li) => [...li.querySelectorAll('span')].map(txt)) }));
        root.remove();
        out.catalogue = cat;
      }
      /* États modifiés : deux archivées, un tarif confirmé, un prix à zéro, tout archivé */
      {
        const rows = colA.all();
        rows[0].statut = 'archive'; rows[1].statut = 'archive'; rows[2].tarifProvisoire = false;
        const root = await montage('m5-catalogue');
        const k1 = await lireCatalogue(root);
        [...root.querySelectorAll('[role=tab]')].find((b) => txt(b).startsWith('Archivés')).click(); await dormir(80);
        const arch = lignesTexte(root);
        root.remove();
        colA.all().forEach((r) => { r.statut = 'archive'; });
        const root2 = await montage('m5-catalogue');
        const k2 = await lireCatalogue(root2);
        const vide = txt(root2.querySelector('[class*=empty], .text-slate-700.font-medium')) || txt(root2);
        root2.remove();
        colA.all().splice(0); sauveA.forEach((x) => colA.all().push(propre(x)));
        out.catalogueEtats = { _doc: 'deux archivées + un tarif confirmé, puis tout archivé', apresDeuxArchives: k1, archives: arch, toutArchive: k2, texteVide: vide };
      }
      /* Impression */
      {
        imprimes.length = 0;
        const root = await montage('m5-catalogue');
        const acts = (SIGH.screens['m5-catalogue'].actions ? SIGH.screens['m5-catalogue'].actions() : []);
        const bi = acts.find((b) => txt(b) === 'Imprimer le catalogue');
        if (bi) { bi.click(); await dormir(250); }
        out.catalogueImpression = { _doc: '« Imprimer le catalogue » (bouton d\'en-tête)', boutonPresent: !!bi, actions: acts.map((b) => txt(b)), imprime: imprimes.slice() };
        document.querySelectorAll('.print-sheet').forEach((e) => e.remove());
        root.remove();
      }
      /* Création / modification */
      {
        const creations = [];
        async function creer(nom, saisie) {
          const root = await montage('m5-catalogue');
          bouton(root, 'Nouveau').click(); await dormir(100);
          const initial = champsModale();
          const titre = txt(document.querySelector('.modal-root h2, [role=dialog] h2, .modal-root h3'));
          Object.entries(saisie).forEach(([k, v]) => poser(k, v));
          const avant = new Set(colA.all().map((x) => x.id));
          const nAvant = colA.all().length;
          viderToasts();
          boutonModale('Créer').click(); await dormir(120);
          const nouvelles = colA.all().filter((x) => !avant.has(x.id)).map(net);
          creations.push({ nom, saisie, initial, titre, nouvelles, nbApres: colA.all().length, nbAvant: nAvant, toasts: toasts(), modaleOuverte: !!document.querySelector('.modal-root, [role=dialog]') });
          fermer(); root.remove();
        }
        await creer('complète', { code: 'L99', designation: 'TEST ANALYSE', categorie: 'Biochimie', echantillon: 'Sang', delai: '2 h', prix: '1500' });
        await creer('minimale : échantillon et délai laissés vides', { code: 'L98', designation: 'AUTRE', prix: '800' });
        await creer('désignation manquante : refus, rien n\'est écrit', { code: 'L97', prix: '800' });
        await creer('code manquant : refus', { designation: 'SANS CODE', prix: '800' });
        await creer('tarif manquant : refus', { code: 'L96', designation: 'SANS TARIF' });
        await creer('tarif à zéro', { code: 'L95', designation: 'GRATUIT', prix: '0' });
        const modifs = [];
        async function modifier(nom, code, saisie) {
          const root = await montage('m5-catalogue');
          const q = root.querySelector('input[placeholder^="Rechercher"]'); q.value = code; q.dispatchEvent(new Event('input')); await dormir(150);
          const tr = [...root.querySelectorAll('tbody tr')].find((x) => txt(x).includes(code));
          const avant = net(colA.all().find((x) => x.code === code));
          bouton(tr, 'Modifier').click(); await dormir(100);
          const prerempli = champsModale();
          Object.entries(saisie).forEach(([k, v]) => poser(k, v));
          viderToasts();
          boutonModale('Enregistrer').click(); await dormir(120);
          const apres = net(colA.all().find((x) => x.id === avant.id));
          const patch = {};
          Object.keys(Object.assign({}, avant, apres)).forEach((k) => { if (JSON.stringify(avant[k]) !== JSON.stringify(apres[k])) patch[k] = apres[k] === undefined ? null : apres[k]; });
          modifs.push({ nom, code, saisie, prerempli, avant, patch, toasts: toasts() });
          fermer(); root.remove();
        }
        await modifier('prix et délai corrigés', 'L03', { prix: '2800', delai: '4 h' });
        await modifier('désignation corrigée', 'L05', { designation: 'BU (BANDELETTE URINAIRE)' });
        out.catalogueSaisie = { _doc: 'm5-catalogue : « Nouveau » → « Créer » et « Modifier » → « Enregistrer »', creations, modifications: modifs };
        /* fiche (tiroir) et boutons de ligne */
        const root = await montage('m5-catalogue');
        imprimes.length = 0;
        const tr0 = root.querySelector('tbody tr');
        const boutonsLigne = [...tr0.querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
        bouton(tr0, 'Consulter').click(); await dormir(150);
        const tiroir = [...document.querySelectorAll('[role=dialog], .drawer, aside')].map((e) => txt(e));
        const piedTiroir = [...document.querySelectorAll('[role=dialog] button, .drawer button, aside button')].map((b) => txt(b));
        fermer();
        document.querySelectorAll('aside, .drawer').forEach((e) => { if (!e.closest('#page-content')) e.remove(); });
        bouton(tr0, 'Imprimer l’état').click(); await dormir(150);
        out.catalogueFiche = { _doc: 'fiche en tiroir de la première analyse, et effet de « Imprimer l\'état » sur une ligne', boutonsLigne, tiroir, piedTiroir, imprimeApresEtat: imprimes.length, feuilles: document.querySelectorAll('.print-sheet').length };
        document.querySelectorAll('.print-sheet').forEach((e) => e.remove());
        root.remove();
        colA.all().splice(0); sauveA.forEach((x) => colA.all().push(propre(x)));
      }

      /* ==================================================================================================================== unités */
      const colU = S.collection('unitesLabo');
      const sauveU = propre(colU.all());
      {
        const root = await montage('m5-unites');
        const u = { _doc: 'm5-unites : jeu de la maquette' };
        u.kpis = kpis(root); u.onglets = [...root.querySelectorAll('[role=tab]')].map((b) => txt(b));
        u.entetes = [...root.querySelectorAll('thead th')].map((x) => txt(x));
        u.filtres = [...root.querySelectorAll('select')].map((s) => [...s.options].map((o) => o.value + '|' + o.textContent));
        u.lignes = lignesTexte(root);
        u.ids = tablesDe(root)[0].lignesFiltrees().map((r) => r.id);
        root.remove();
        out.unites = u;
        /* un jeu craft : aValider mêlé, source propre, domaine absent */
        colU.all().splice(0);
        [{ id: 'u1', statut: 'actif', symbole: 'a', libelle: 'alpha', domaine: 'Biochimie', source: 'Ma source' }, { id: 'u2', statut: 'actif', symbole: 'b', libelle: 'bravo', domaine: 'Biochimie', aValider: true },
          { id: 'u3', statut: 'actif', symbole: 'c', libelle: 'charlie', domaine: 'Général' }, { id: 'u4', statut: 'archive', symbole: 'd', libelle: 'delta', domaine: 'Hémostase', aValider: true },
          { id: 'u5', statut: 'actif', symbole: 'e', libelle: 'echo', domaine: 'Hémostase', aValider: false, source: 'Fiche X' }].forEach((x) => colU.all().push(x));
        const r2 = await montage('m5-unites');
        out.unitesCraft = { _doc: 'unités posées : provenance et indicateurs', fiches: propre(colU.all()), kpis: kpis(r2), lignes: lignesTexte(r2), ids: tablesDe(r2)[0].lignesFiltrees().map((r) => r.id) };
        r2.remove();
        colU.all().splice(0); sauveU.forEach((x) => colU.all().push(propre(x)));
        const creations = [];
        async function creer(nom, saisie) {
          const root3 = await montage('m5-unites');
          bouton(root3, 'Nouveau').click(); await dormir(100);
          const initial = champsModale();
          Object.entries(saisie).forEach(([k, v]) => poser(k, v));
          const avant = new Set(colU.all().map((x) => x.id));
          viderToasts();
          boutonModale('Créer').click(); await dormir(120);
          const nouvelles = colU.all().filter((x) => !avant.has(x.id)).map(net);
          const ligne0 = lignesTexte(root3, 1)[0];
          creations.push({ nom, saisie, initial, nouvelles, toasts: toasts(), modaleOuverte: !!document.querySelector('.modal-root, [role=dialog]'), premiereLigne: ligne0 });
          fermer(); root3.remove();
        }
        await creer('unité complète', { symbole: 'mg/dl', libelle: 'milligramme par décilitre', domaine: 'Biochimie' });
        await creer('symbole manquant : refus', { libelle: 'sans symbole' });
        const root4 = await montage('m5-unites');
        const q = root4.querySelector('input[placeholder^="Rechercher"]'); q.value = 'G/l'; q.dispatchEvent(new Event('input')); await dormir(150);
        const tr = [...root4.querySelectorAll('tbody tr')].find((x) => txt(x).includes('G/l'));
        const avant = net(colU.all().find((x) => x.symbole === 'G/l'));
        bouton(tr, 'Modifier').click(); await dormir(100);
        const prerempli = champsModale();
        poser('libelle', 'giga par litre (corrigé)'); viderToasts();
        boutonModale('Enregistrer').click(); await dormir(120);
        const apres = net(colU.all().find((x) => x.id === avant.id));
        const patch = {}; Object.keys(Object.assign({}, avant, apres)).forEach((k) => { if (JSON.stringify(avant[k]) !== JSON.stringify(apres[k])) patch[k] = apres[k] === undefined ? null : apres[k]; });
        out.unitesSaisie = { _doc: 'm5-unites : « Nouveau » → « Créer », « Modifier » → « Enregistrer »', creations, modification: { avant, prerempli, patch, toasts: toasts() } };
        fermer(); root4.remove();
        colU.all().splice(0); sauveU.forEach((x) => colU.all().push(propre(x)));
      }

      /* ==================================================================================================================== valeurs de référence */
      const colV = S.collection('variablesLabo');
      const sauveV = propre(colV.all());
      const colX = S.collection('examensLabo');
      {
        const root = await montage('m5-valeurs-reference');
        const sels = [...root.querySelectorAll('select')].slice(0, 3);
        const v = { _doc: 'm5-valeurs-reference : jeu de la maquette' };
        v.kpis = kpis(root);
        v.options = sels.map((s) => [...s.options].map((o) => o.value + '|' + o.textContent));
        v.entetes = [...root.querySelectorAll('thead th')].map((x) => txt(x));
        v.cartes = [...root.querySelectorAll('.card-head')].map((x) => txt(x));
        v.note = txt([...root.querySelectorAll('div')].find((d) => d.className && String(d.className).includes('rounded-lg') && txt(d).startsWith('Une variable d’accompagnement')));
        v.page1 = lignesTexte(root, 25);
        v.ids = tablesDe(root)[0].lignesFiltrees().map((r) => r.id);
        v.nbTotal = colV.all().length; v.nbActives = colV.active().length;
        v.exemplesFermables = colV.active().filter((x) => x.retractable).slice(0, 3).map((x) => x.id);
        v.plagesVide = txt(tablesDe(root)[1].closest('.card'));
        v.filtres = [];
        async function filtre(nom, section, examen, etat) {
          changer(sels[0], section || ''); await dormir(60);
          const optionsExamen = [...sels[1].options].map((o) => o.value + '|' + o.textContent);
          changer(sels[1], examen || ''); changer(sels[2], etat || ''); await dormir(80);
          const kp = kpis(root);
          v.filtres.push({ nom, section: section || '', examen: examen || '', etat: etat || '', optionsExamen, ids: tablesDe(root)[0].lignesFiltrees().map((r) => r.id), kpis: kp });
        }
        await filtre('section hématologie', 'hematologie');
        await filtre('section parasitologie', 'parasitologie');
        await filtre('examen VIH', '', 'VIH');
        await filtre('examen NFS', '', 'NFS');
        await filtre('état documentées', '', '', 'documente');
        await filtre('état à valider', '', '', 'valider');
        await filtre('état fermées', '', '', 'ferme');
        await filtre('section sérologie + à valider', 'serologie', '', 'valider');
        await filtre('retour à tout', '', '', '');
        root.remove();
        out.valeurs = v;
      }
      /* variables posées : tous les états */
      {
        const exNFS = colX.active()[0];
        const mkv = (id, extra) => Object.assign({ id, statut: 'actif', examen: exNFS.code, examenLibelle: exNFS.designation, section: exNFS.section, code: id, libelle: 'Var ' + id, type: 'numerique', unite: 'g_l_hb', min: 1, max: 2, ordre: 1, actif: true, accompagnement: false, retractable: false, aValider: false }, extra || {});
        colV.all().splice(0);
        [mkv('X1'), mkv('X2', { valideLe: '2026-09-01', validePar: 'Biologiste' }), mkv('X3', { aValider: true }), mkv('X4', { actif: false, retractable: true, type: 'commentaire', accompagnement: true }),
          mkv('X5', { aValider: true, valideLe: '2026-09-01' }), mkv('X6', { statut: 'archive' }), mkv('X7', { actif: false, aValider: true }), mkv('X8', { actif: undefined }), mkv('X9', { parent: 'X1', unite: 'zzz', type: 'binaire', normal: 'Négatif', min: undefined, max: undefined }),
          mkv('X10', { unite: 'sans', type: 'lot', accompagnement: true, retractable: true })].forEach((x) => colV.all().push(propre(x)));
        const root = await montage('m5-valeurs-reference');
        const sels = [...root.querySelectorAll('select')].slice(0, 3);
        const rec = { _doc: 'variables posées pour tous les états', fiches: propre(colV.all()), kpis: kpis(root), ids: tablesDe(root)[0].lignesFiltrees().map((r) => r.id), lignes: lignesTexte(root), filtres: [] };
        for (const [nom, etat] of [['documentées', 'documente'], ['à valider', 'valider'], ['fermées', 'ferme']]) {
          changer(sels[2], etat); await dormir(80);
          rec.filtres.push({ nom, etat, ids: tablesDe(root)[0].lignesFiltrees().map((r) => r.id) });
        }
        root.remove();
        out.valeursEtats = rec;
        colV.all().splice(0); sauveV.forEach((x) => colV.all().push(propre(x)));
      }
      /* impression du référentiel */
      {
        imprimes.length = 0;
        const root = await montage('m5-valeurs-reference');
        const sels = [...root.querySelectorAll('select')].slice(0, 3);
        changer(sels[0], 'serologie'); await dormir(60);
        bouton(root, 'Imprimer le référentiel').click(); await dormir(200);
        out.valeursImpression = { _doc: '« Imprimer le référentiel » (section sérologie)', filtre: 'serologie', imprime: imprimes.slice(), nb: tablesDe(root)[0].lignesFiltrees().length };
        document.querySelectorAll('.print-sheet').forEach((e) => e.remove());
        root.remove();
      }
      /* création / modification / fermeture d'une variable */
      {
        const gestes = { _doc: 'variables : « Nouvelle variable », « Modifier les paramètres », fermer / rouvrir' };
        const ligneDe = (root, id) => { const t = tablesDe(root)[0]; return t.lignesFiltrees().findIndex((r) => r.id === id); };
        async function ouvrirModif(id) {
          const root = await montage('m5-valeurs-reference');
          const sels = [...root.querySelectorAll('select')].slice(0, 3);
          const v = colV.all().find((x) => x.id === id);
          changer(sels[1], v.examen); await dormir(80);
          const tr = [...root.querySelectorAll('tbody tr')].find((x) => txt(x).includes(v.libelle) && txt(x).includes(v.code));
          if (!tr) throw new Error('ligne ' + id);
          bouton(tr, 'Modifier les paramètres').click(); await dormir(100);
          return { root, v: net(v) };
        }
        gestes.creations = [];
        async function creer(nom, saisie) {
          const root = await montage('m5-valeurs-reference');
          bouton(root, 'Nouvelle variable').click(); await dormir(100);
          const initial = champsModale();
          const modaleTexte = txt(document.querySelector('.modal-root, [role=dialog]'));
          Object.entries(saisie).forEach(([k, v]) => poser(k, v));
          const avant = new Set(colV.all().map((x) => x.id));
          viderToasts();
          boutonModale('Créer').click(); await dormir(120);
          gestes.creations.push({ nom, saisie, initial, modaleTexte: modaleTexte.slice(0, 400), nouvelles: colV.all().filter((x) => !avant.has(x.id)).map(net), toasts: toasts(), modaleOuverte: !!document.querySelector('.modal-root, [role=dialog]'), audit: dernierLog() });
          fermer(); root.remove();
        }
        const ex = colX.active().find((e) => e.code === 'VIH') || colX.active()[1];
        await creer('variable numérique complète', { examen: ex.code, code: 'ZZ1', libelle: 'Variable test', type: 'numerique', unite: 'mg_l', min: '1.5', max: '9', decimales: '1', ordre: '5' });
        await creer('variable de type réactif (accompagnement, rétractable)', { examen: ex.code, code: 'ZZ2', libelle: 'Réactif test', type: 'reactif', ordre: '6' });
        await creer('sans intitulé : refus', { examen: ex.code, code: 'ZZ3', type: 'numerique', ordre: '7' });
        await creer('sous-variable avec règle', { examen: ex.code, code: 'ZZ4', libelle: 'Sous-variable', type: 'numerique', parent: 'ZZ1', regle: 'inférieure à la moitié de la glycémie', ordre: '8' });
        await creer('qualitative avec issue attendue', { examen: ex.code, code: 'ZZ5', libelle: 'Qualitative', type: 'binaire', normal: 'Négatif', ordre: '9' });
        gestes.modifications = [];
        async function modifier(nom, id, saisie) {
          const { root, v } = await ouvrirModif(id);
          const prerempli = champsModale();
          const note = txt(document.querySelector('.modal-root, [role=dialog]')).slice(0, 260);
          Object.entries(saisie).forEach(([k, val]) => poser(k, val));
          viderToasts();
          boutonModale('Enregistrer').click(); await dormir(120);
          const apres = net(colV.all().find((x) => x.id === id));
          const patch = {}; Object.keys(Object.assign({}, v, apres)).forEach((k) => { if (JSON.stringify(v[k]) !== JSON.stringify(apres[k])) patch[k] = apres[k] === undefined ? null : apres[k]; });
          gestes.modifications.push({ nom, id, saisie, prerempli, note, avant: v, patch, toasts: toasts(), audit: dernierLog() });
          fermer(); root.remove();
        }
        await modifier('borne documentée déplacée : la source le dit', 'VAR-NFS-GB', { min: '3.8', max: '8.5' });
        await modifier('intitulé seul modifié : la source ne bouge pas', 'VAR-NFS-LY', { libelle: 'Lymphocytes (corrigé)' });
        await modifier('borne vidée', 'VAR-NFS-MO', { max: '' });
        /* fermer / rouvrir */
        gestes.fermetures = [];
        const retractable = colV.active().find((x) => x.retractable);
        async function basculer(nom, id, confirmer) {
          const root = await montage('m5-valeurs-reference');
          const sels = [...root.querySelectorAll('select')].slice(0, 3);
          const v = colV.all().find((x) => x.id === id);
          changer(sels[1], v.examen); await dormir(80);
          const tr = [...root.querySelectorAll('tbody tr')].find((x) => txt(x).includes(v.libelle) && txt(x).includes(v.code));
          const boutons = [...tr.querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
          const avant = net(v);
          const cible = bouton(tr, 'Fermer cette variable') || bouton(tr, 'Rouvrir cette variable');
          const libelleBouton = cible.getAttribute('aria-label') || cible.title;
          cible.click(); await dormir(100);
          const modale = txt(document.querySelector('.modal-root, [role=dialog]'));
          viderToasts();
          const final = [...document.querySelectorAll('button')].filter((b) => ['Fermer la variable', 'Rouvrir'].includes(txt(b))).pop();
          const libelleFinal = final ? txt(final) : null;
          if (confirmer && final) { final.click(); await dormir(120); }
          const apres = net(colV.all().find((x) => x.id === id));
          const patch = {}; Object.keys(Object.assign({}, avant, apres)).forEach((k) => { if (JSON.stringify(avant[k]) !== JSON.stringify(apres[k])) patch[k] = apres[k] === undefined ? null : apres[k]; });
          gestes.fermetures.push({ nom, id, boutons, libelleBouton, libelleFinal, modale, confirmer, patch, toasts: toasts(), etatAffiche: txt(tr) });
          fermer(); root.remove();
        }
        gestes.retractableId = retractable.id;
        await basculer('fermer une variable d\'accompagnement', retractable.id, true);
        await basculer('rouvrir', retractable.id, true);
        await basculer('fermer puis annuler : rien ne change', retractable.id, false);
        const nonRetractable = colV.active().find((x) => !x.retractable);
        {
          const root = await montage('m5-valeurs-reference');
          const sels = [...root.querySelectorAll('select')].slice(0, 3);
          changer(sels[1], nonRetractable.examen); await dormir(80);
          const tr = [...root.querySelectorAll('tbody tr')].find((x) => txt(x).includes(nonRetractable.libelle) && txt(x).includes(nonRetractable.code));
          gestes.nonRetractable = { id: nonRetractable.id, boutons: [...tr.querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title) };
          root.remove();
        }
        out.valeursGestes = gestes;
        colV.all().splice(0); sauveV.forEach((x) => colV.all().push(propre(x)));
      }
      /* plages par lot */
      {
        const g = { _doc: 'plages par lot de réactif : création, refus, modification, archivage' };
        colPl.all().splice(0);
        /* depuis la copie SAINE : la synchronisation entre postes peut relire la base avant la restauration de la collection */
        const numeriques = sauveV.filter((x) => x.statut !== 'archive' && !x.accompagnement && x.type === 'numerique');
        g.nbNumeriques = numeriques.length;
        g.premieres = numeriques.slice(0, 2).map((x) => ({ id: x.id, label: x.examenLibelle + ' — ' + x.libelle }));
        const cible = colV.all().find((x) => x.id === 'VAR-NFS-GB');
        async function ouvrir() { const root = await montage('m5-valeurs-reference'); return root; }
        g.creations = [];
        async function creer(nom, saisie) {
          const root = await ouvrir();
          bouton(root, 'Nouvelle plage de lot').click(); await dormir(100);
          const initial = champsModale();
          const options = [...document.querySelectorAll('[id=f_variableId] option, select#f_variableId option')].slice(0, 2).map((o) => o.value + '|' + o.textContent);
          Object.entries(saisie).forEach(([k, v]) => poser(k, v));
          const avant = new Set(colPl.all().map((x) => x.id));
          viderToasts();
          boutonModale('Enregistrer la plage').click(); await dormir(120);
          g.creations.push({ nom, saisie, initial, options, nouvelles: colPl.all().filter((x) => !avant.has(x.id)).map(net), toasts: toasts(), modaleOuverte: !!document.querySelector('.modal-root, [role=dialog]'), audit: dernierLog(),
            tableau: lignesTexte(tablesDe(root)[1].closest('.card'), 5) });
          fermer(); root.remove();
        }
        await creer('plage valide', { variableId: cible.id, lot: 'LOT-2026-A', dateDebut: '2026-09-01', min: '3.5', max: '9.5', source: 'Notice du réactif Sysmex' });
        await creer('aucune borne : refus nommé', { variableId: cible.id, lot: 'LOT-VIDE', dateDebut: '2026-09-02', source: 'Notice' });
        await creer('borne haute seule', { variableId: cible.id, lot: 'LOT-2026-B', dateDebut: '2026-10-01', max: '10', source: 'Validation de méthode' });
        await creer('source manquante : refus', { variableId: cible.id, lot: 'LOT-X', dateDebut: '2026-10-02', min: '1' });
        g.vide = null;
        {
          const root = await ouvrir();
          const tPl = tablesDe(root)[1];
          g.lignes = lignesTexte(tPl.closest('.card'));
          root.remove();
        }
        /* modification */
        {
          const root = await ouvrir();
          const tr = [...tablesDe(root)[1].closest('.card').querySelectorAll('tbody tr')].find((x) => txt(x).includes('LOT-2026-A'));
          const plage = colPl.all().find((x) => x.lot === 'LOT-2026-A');
          const avant = net(plage);
          bouton(tr, 'Modifier la plage').click(); await dormir(100);
          const prerempli = champsModale();
          poser('max', '9.8'); viderToasts();
          boutonModale('Enregistrer').click(); await dormir(120);
          const apres = net(colPl.all().find((x) => x.id === avant.id));
          const patch = {}; Object.keys(Object.assign({}, avant, apres)).forEach((k) => { if (JSON.stringify(avant[k]) !== JSON.stringify(apres[k])) patch[k] = apres[k] === undefined ? null : apres[k]; });
          g.modification = { avant, prerempli, patch, toasts: toasts(), audit: dernierLog() };
          fermer(); root.remove();
        }
        /* archivage */
        {
          const root = await ouvrir();
          const tr = [...tablesDe(root)[1].closest('.card').querySelectorAll('tbody tr')].find((x) => txt(x).includes('LOT-2026-B'));
          bouton(tr, 'Archiver la plage').click(); await dormir(100);
          const modale = txt(document.querySelector('.modal-root, [role=dialog]'));
          viderToasts();
          [...document.querySelectorAll('button')].filter((b) => txt(b) === 'Archiver').pop().click(); await dormir(120);
          g.archivage = { modale, statut: colPl.all().find((x) => x.lot === 'LOT-2026-B').statut, toasts: toasts(), restantes: lignesTexte(tablesDe(root)[1].closest('.card')).length };
          fermer(); root.remove();
        }
        out.valeursPlages = g;
        colPl.all().splice(0); sauvePl.forEach((x) => colPl.all().push(propre(x)));
        colV.all().splice(0); sauveV.forEach((x) => colV.all().push(propre(x)));
      }

      /* ==================================================================================================================== réactifs */
      const colP = S.collection('produits');
      const sauveP = colP.all().splice(0);
      const colM = S.collection('mouvements');
      const sauveM = colM.all().splice(0);
      const mk = (id, code, cat, stock, seuil, cump, extra) => Object.assign({ id, code, designation: 'D ' + code, categorie: cat, unite: 'Boîte', stock, seuilAlerte: seuil, cump, statut: 'actif' }, extra || {});
      const jeuP = [mk('P1', 'A1', 'reactif', 0, 10, 100), mk('P2', 'A2', 'reactif', 5, 10, 200), mk('P3', 'A3', 'conso_labo', 10, 10, 50), mk('P4', 'A4', 'conso_labo', 11, 10, 50),
        mk('P5', 'A5', 'reactif', 7, null, 300), mk('P6', 'A6', 'reactif', 0, null, 300), mk('P7', 'A7', 'medicament', 1, 1, 10), mk('P8', 'A8', 'reactif', 3, 0, 40), mk('P9', 'A9', 'reactif', 9, 5, 12, { statut: 'archive' }),
        mk('P10', 'A10', 'conso_labo', 2, 2, 0)];
      const sortie = (id, produitId, date, quantite, extra) => Object.assign({ id, produitId, date, quantite, type: 'sortie', statut: 'actif' }, extra || {});
      const jeuM = [sortie('M1', 'P2', '2026-10-29', 4), sortie('M2', 'P2', '2026-10-25', 6), sortie('M3', 'P3', '2026-10-30', 3), sortie('M4', 'P4', '2026-10-10', 9), sortie('M5', 'P1', '2026-08-01', 20), sortie('M6', 'P5', '2026-05-02', 11),
        sortie('M7', 'P7', '2026-10-29', 50), sortie('M8', 'P2', '2026-10-29', 2, { type: 'entree' }), sortie('M9', 'P8', '2026-10-24', 5), sortie('M10', 'P10', '2026-10-24', 5), sortie('M11', 'P6', '2026-04-29', 8),
        sortie('M12', 'P3', '2026-10-24T08:00', 1, { statut: 'archive' })];
      const colCache = (jeu) => { colP.all().splice(0); jeu.forEach((p) => colP.all().push(propre(p))); };
      {
        colCache(jeuP); colM.all().splice(0); jeuM.forEach((x) => colM.all().push(propre(x)));
        const root = await montage('m5-reactifs');
        const tt = tablesDe(root)[0];
        const sels = [...root.querySelectorAll('select')];
        const r = { _doc: 'm5-reactifs sur des produits posés', produits: propre(jeuP), mouvements: propre(jeuM) };
        r.kpis = kpis(root);
        r.noteSansSeuil = txt([...root.querySelectorAll('div')].find((d) => String(d.className).includes('rounded-lg') && txt(d) && txt(d).includes('sans seuil d’alerte') && !d.querySelector('.kpi')));
        r.entetes = [...root.querySelectorAll('thead th')].map((x) => txt(x));
        r.lignes = lignesTexte(root);
        r.ids = tt.lignesFiltrees().map((x) => x.id);
        r.classesStock = [...root.querySelectorAll('tbody tr')].map((tr) => { const sp = tr.querySelectorAll('td')[4].querySelector('span'); return sp ? sp.className : ''; });
        r.filtres = [];
        const selCat = sels[0], selNiveau = sels[1];
        for (const [nom, cat, niv] of [['réactifs', 'reactif', ''], ['consommables', 'conso_labo', ''], ['rupture', '', 'rupture'], ['sous le seuil', '', 'alerte'], ['stock suffisant', '', 'ok'], ['sans seuil', '', 'sansSeuil'], ['réactifs sous le seuil', 'reactif', 'alerte']]) {
          changer(selCat, cat); changer(selNiveau, niv); await dormir(80);
          r.filtres.push({ nom, categorie: cat, niveau: niv, ids: tt.lignesFiltrees().map((x) => x.id) });
        }
        changer(selCat, ''); changer(selNiveau, ''); await dormir(60);
        /* graphiques */
        r.periodes = [];
        const selPer = sels[2];
        for (const per of ['semaine', 'mois', 'trimestre', 'semestre', 'annee', 'libre']) {
          changer(selPer, per); await dormir(100);
          const cartes = [...root.querySelectorAll('.card')];
          const carteTop = cartes.find((c) => (txt(c.querySelector('.card-head')) || '').startsWith('Les plus consommés'));
          const lignesTop = [...carteTop.querySelectorAll('.space-y-2\\.5 > div')].map((d) => [...d.querySelectorAll('span')].map(txt));
          r.periodes.push({ periode: per, titre: txt(carteTop.querySelector('.card-head')), top: lignesTop, vide: lignesTop.length ? null : txt(carteTop) });
        }
        const carteVal = [...root.querySelectorAll('.card')].find((c) => txt(c.querySelector('.card-head')) === 'Valeur du stock par référence');
        r.valeurParReference = [...carteVal.querySelectorAll('.space-y-2\\.5 > div')].map((d) => ({ libelle: txt(d.querySelectorAll('span')[0]), valeur: txt(d.querySelectorAll('span')[1]), classe: d.querySelector('.h-full').className.match(/bg-[a-z]+-500/)[0] }));
        r.cartesTitres = [...root.querySelectorAll('.card-head')].map((x) => txt(x));
        r.aide = txt([...root.querySelectorAll('div')].find((d) => String(d.className).includes('rounded-lg') && txt(d) && txt(d).startsWith('Une référence dont')));
        r.source = txt([...root.querySelectorAll('p, div')].find((d) => txt(d) && txt(d).startsWith('Source :') && d.children.length < 3));
        /* anneau : intercepté */
        root.remove();
        out.reactifs = r;
      }
      /* données du graphique en anneau et du classement : par interception */
      {
        const anneaux = [];
        const anneauOrig = SIGH.charts.anneau;
        SIGH.charts.anneau = function (labels, data) { anneaux.push({ labels: propre(labels), data: propre(data) }); return anneauOrig.apply(this, arguments); };
        const barresOrig = SIGH.charts.barres;
        const barres = [];
        SIGH.charts.barres = function (labels, series, opts) { barres.push({ labels: propre(labels), series: propre(series.map((s) => ({ label: s.label, data: s.data }))) }); return barresOrig.apply(this, arguments); };
        const root = await montage('m5-reactifs');
        out.reactifsGraphiques = { _doc: 'graphiques de m5-reactifs (période « mois » par défaut)', anneaux, barres };
        root.remove();
        SIGH.charts.anneau = anneauOrig; SIGH.charts.barres = barresOrig;
      }
      /* bon de demande */
      {
        const bons = [];
        async function bon(nom, jeu) {
          colCache(jeu); imprimes.length = 0; viderToasts();
          const root = await montage('m5-reactifs');
          bouton(root, 'Bon de demande de réactifs').click(); await dormir(200);
          bons.push({ nom, produits: propre(jeu), imprime: imprimes.slice(), toasts: toasts() });
          document.querySelectorAll('.print-sheet').forEach((e) => e.remove());
          root.remove();
        }
        await bon('trois références sous le seuil, deux sans seuil', jeuP);
        await bon('aucune sous le seuil mais des références sans seuil : avertissement', [mk('B1', 'B1', 'reactif', 50, 10, 10), mk('B2', 'B2', 'conso_labo', 8, null, 10)]);
        await bon('aucune sous le seuil, tous les seuils fixés : succès', [mk('B1', 'B1', 'reactif', 50, 10, 10), mk('B2', 'B2', 'conso_labo', 80, 20, 10)]);
        await bon('seuil à zéro et stock à zéro : à commander au moins une unité', [mk('B3', 'B3', 'reactif', 0, 0, 10), mk('B4', 'B4', 'reactif', 1, 3, 10), mk('B5', 'B5', 'reactif', 20, 20, 10)]);
        out.reactifsBons = { _doc: '« Bon de demande de réactifs »', bons };
      }
      /* création / modification */
      {
        colCache(jeuP);
        const G = { _doc: 'm5-reactifs : « Nouveau réactif » → « Créer », « Modifier » (K.actionsLigne)', creations: [], modifications: [] };
        async function creer(nom, saisie) {
          const root = await montage('m5-reactifs');
          bouton(root, 'Nouveau réactif').click(); await dormir(100);
          const initial = champsModale();
          Object.entries(saisie).forEach(([k, v]) => poser(k, v));
          const avant = new Set(colP.all().map((x) => x.id));
          viderToasts();
          boutonModale('Créer').click(); await dormir(150);
          G.creations.push({ nom, saisie, initial, codesExistants: colP.all().filter((x) => !avant.has(x.id) === false).map((x) => x.code).filter((c) => String(c).startsWith('LAB-')), nouvelles: colP.all().filter((x) => !avant.has(x.id)).map(net), toasts: toasts(),
            modaleOuverte: !!document.querySelector('.modal-root, [role=dialog]'), kpis: kpis(root) });
          fermer(); root.remove();
        }
        await creer('réactif complet', { designation: 'KIT TEST', categorie: 'reactif', unite: 'Kit', stock: '12', seuilAlerte: '5', seuilCritique: '2', cump: '1500', emplacement: 'Rayon Z', fournisseur: 'LABOTECH' });
        await creer('deuxième création dans la même page : le code suit le registre', { designation: 'KIT DEUX', categorie: 'conso_labo', unite: 'Boîte', stock: '3', seuilAlerte: '1', cump: '200' });
        await creer('seuil vidé : « sans seuil », pas zéro', { designation: 'SANS SEUIL', categorie: 'reactif', unite: 'Unité', stock: '4', seuilAlerte: '', cump: '10' });
        await creer('désignation manquante : refus', { categorie: 'reactif', unite: 'Unité', stock: '4', seuilAlerte: '3' });
        await creer('stock négatif : refus', { designation: 'NEG', categorie: 'reactif', unite: 'Unité', stock: '-1', seuilAlerte: '3' });
        async function modifier(nom, code, saisie) {
          const root = await montage('m5-reactifs');
          const tr = [...root.querySelectorAll('tbody tr')].find((x) => txt(x.querySelector('td')) === code);
          const avant = net(colP.all().find((x) => x.code === code));
          bouton(tr, 'Modifier').click(); await dormir(100);
          const prerempli = champsModale();
          Object.entries(saisie).forEach(([k, v]) => poser(k, v));
          viderToasts();
          boutonModale('Enregistrer').click(); await dormir(150);
          const apres = net(colP.all().find((x) => x.id === avant.id));
          const patch = {}; Object.keys(Object.assign({}, avant, apres)).forEach((k) => { if (JSON.stringify(avant[k]) !== JSON.stringify(apres[k])) patch[k] = apres[k] === undefined ? null : apres[k]; });
          G.modifications.push({ nom, code, saisie, prerempli, avant, patch, toasts: toasts(), boutonsLigne: [...tr.querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title) });
          fermer(); root.remove();
        }
        await modifier('seuil et stock corrigés', 'A2', { stock: '25', seuilAlerte: '8' });
        await modifier('seuil vidé', 'A3', { seuilAlerte: '' });
        out.reactifsSaisie = G;
      }
      /* la fiche de réactif d'un jeu où des LAB- existent déjà */
      {
        colCache([mk('Q1', 'LAB-0007', 'reactif', 1, 1, 1), mk('Q2', 'LAB-0003', 'reactif', 1, 1, 1, { statut: 'archive' }), mk('Q3', 'LABX-0099', 'reactif', 1, 1, 1), mk('Q4', 'A1', 'reactif', 1, 1, 1)]);
        const root = await montage('m5-reactifs');
        bouton(root, 'Nouveau réactif').click(); await dormir(100);
        poser('designation', 'NOUVEAU'); poser('unite', 'U'); poser('stock', '1'); poser('seuilAlerte', '1');
        const avant = new Set(colP.all().map((x) => x.id));
        boutonModale('Créer').click(); await dormir(150);
        out.reactifsCode = { _doc: 'code attribué quand des LAB- existent déjà (archivés compris)', codes: ['LAB-0007', 'LAB-0003', 'LABX-0099', 'A1'], nouveau: colP.all().filter((x) => !avant.has(x.id)).map((x) => x.code) };
        fermer(); root.remove();
      }
      colP.all().splice(0); sauveP.forEach((x) => colP.all().push(propre(x)));
      colM.all().splice(0); sauveM.forEach((x) => colM.all().push(propre(x)));
      return out;
    });
    const doc = (nom) => ({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-catalogue-labo.js — ne pas éditer.' });
    ecrire('packages/domaine/test/vecteurs/cat_moteur.json', Object.assign(doc(), { jour: sortie.jour, plages: sortie.plages, references: sortie.references }));
    ecrire('packages/domaine/test/vecteurs/cat_catalogue.json', Object.assign(doc(), { catalogue: sortie.catalogue, etats: sortie.catalogueEtats, impression: sortie.catalogueImpression, saisie: sortie.catalogueSaisie, fiche: sortie.catalogueFiche }));
    ecrire('packages/domaine/test/vecteurs/cat_unites.json', Object.assign(doc(), { unites: sortie.unites, craft: sortie.unitesCraft, saisie: sortie.unitesSaisie }));
    ecrire('packages/domaine/test/vecteurs/cat_valeurs.json', Object.assign(doc(), { jour: sortie.jour, valeurs: sortie.valeurs, etats: sortie.valeursEtats, impression: sortie.valeursImpression, gestes: sortie.valeursGestes, plages: sortie.valeursPlages }));
    ecrire('packages/domaine/test/vecteurs/cat_reactifs.json', Object.assign(doc(), { jour: sortie.jour, reactifs: sortie.reactifs, graphiques: sortie.reactifsGraphiques, bons: sortie.reactifsBons, saisie: sortie.reactifsSaisie, code: sortie.reactifsCode }));
    console.log('  catalogue : ' + sortie.catalogue.kpis.map((k) => k.label + '=' + k.valeur).join(' · '));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
