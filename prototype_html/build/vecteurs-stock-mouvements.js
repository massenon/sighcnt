/* =============================================================================
 * VECTEURS DES ÉCRANS DE MOUVEMENTS DE STOCK (M6) — transferts, mouvements, inventaire (feuille), pertes
 * -----------------------------------------------------------------------------
 * Ces règles vivent dans la FERMETURE des écrans (`ouvrir()`, `valider()`, `declarer()`…) : on ne peut pas les appeler seules. Le script monte donc
 * les VRAIS écrans dans la page d'extraction, pilote les modales comme le fait l'agent (choix de l'article, quantité, « Ajouter », « Valider… »),
 * capte les messages (U.toast : refus nommés, annulation) et relit ce qui est né au magasin. Pour chaque cas : les fiches d'ENTRÉE (produits, lots,
 * bons existants) et la SORTIE (bon, mouvements, état des produits, messages, état APRÈS annulation).
 *   node build/vecteurs-stock-mouvements.js   →   packages/domaine/test/vecteurs/stock_mouvements.json
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs des mouvements de stock (transferts, mouvements, inventaire, pertes)');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m6-stock.js') });
    const sortie = await m.page.evaluate(async () => {
      const S = SIGH.store, C = SIGH.core, U = SIGH.ui;
      const propre = (x) => JSON.parse(JSON.stringify(x));
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const colP = S.collection('produits'), colL = S.collection('lots'), colT = S.collection('transferts'),
        colM = S.collection('mouvements'), colI = S.collection('inventaires');
      const jour = C.iso(C.aujourdhui());
      const utilisateur = S.currentUser();

      /* Capte les messages de l'écran (refus nommés, annulation). */
      const toasts = [];
      const toastOrigine = U.toast;
      U.toast = function (message, opts) { toasts.push({ message, type: (opts && opts.type) || 'info', detail: (opts && opts.detail) || null, undo: opts && opts.undo || null }); return toastOrigine.apply(this, arguments); };
      const messages = () => toasts.map((t) => ({ message: t.message, type: t.type, detail: t.detail }));

      let n = 0;
      const produit = (extra) => { n++; const code = 'ZT' + n; return Object.assign({ id: 'PRD-ZT' + n, code, designation: 'ZZ Test ' + n, unite: 'Boîte', categorie: 'immobilisation',
        prixAchat: 100, prixVente: 100, cump: 100, seuilAlerte: 5, stockGros: 50, stockDetail: 10, stock: 60, statut: 'actif' }, extra || {}); };
      const poserP = (extra) => colP.insert(produit(extra)).record;
      const etatP = (ids) => ids.map((id) => { const p = colP.get(id); return { id, stockGros: p.stockGros, stockDetail: p.stockDetail, stock: p.stock }; });
      const net = (x) => { const c = Object.assign({}, x); Object.keys(c).forEach((k) => { if (k[0] === '_') delete c[k]; }); delete c.id; return propre(c); };
      const rangMax = (re) => colM.all().reduce((mx, x) => { const r = re.exec(x.reference || ''); return r ? Math.max(mx, Number(r[1])) : mx; }, 0);
      const fermer = () => document.querySelectorAll('.modal-root, [role=dialog]').forEach((e) => e.remove());
      const bouton = (txt, portee) => { const b = [...(portee || document).querySelectorAll('button')].find((x) => x.textContent.trim() === txt) || [...(portee || document).querySelectorAll('button')].find((x) => x.textContent.includes(txt)); if (!b) throw new Error('bouton introuvable : ' + txt); return b; };
      const poser = (id, v) => { const e = document.getElementById('f_' + id); if (!e) throw new Error('champ ' + id); e.value = v; e.dispatchEvent(new Event('input')); e.dispatchEvent(new Event('change')); };

      /* ----------------------------------------------------------------------
       * FEUILLE D'INVENTAIRE — comptage, écarts, régularisation, annulation
       * -------------------------------------------------------------------- */
      const inventaires = [];
      async function jouerInventaire(nom, magasin, produits, comptes, opts) {
        opts = opts || {};
        toasts.length = 0;
        const entete = Object.assign({ magasin, type: 'Mensuel', date: '2026-10-30', perimetre: 'Immobilisations', operateur: 'Testeur Inventaire' }, opts.entete || {});
        location.hash = '#' + Object.entries(entete).map(([k, v]) => encodeURIComponent(k) + '=' + encodeURIComponent(v)).join('&');
        const root = document.createElement('div'); root.id = 'page-content'; document.body.appendChild(root);
        const entree = { nom, entete, produits: propre(produits.map((p) => colP.get(p.id))), comptes, inventairesExistants: propre(colI.all().map((i) => i.reference)), rangMax: rangMax(/^M(\d+)$/), jour, utilisateur };
        const avantI = new Set(colI.all().map((x) => x.id)), avantM = new Set(colM.all().map((x) => x.id));
        SIGH.screens['m6-inventaire-feuille'].render(root); await dormir(120);
        await dormir(30);
        const lignesDom = [...root.querySelectorAll('tbody tr')];
        const apercu = lignesDom.map((tr) => ({ cle: tr.dataset.cle, cellules: [...tr.children].map((td) => td.textContent) }));
        const ecransEnDirect = [];
        for (const [code, physique] of Object.entries(comptes)) {
          const tr = lignesDom.find((r) => r.dataset.cle.indexOf(code.toLowerCase()) !== -1 && r.dataset.cle.endsWith(' ' + code.toLowerCase()));
          const champ = tr.querySelector('input'); champ.value = physique; champ.dispatchEvent(new Event('input'));
          ecransEnDirect.push({ code, ecart: tr.children[3].textContent, valeur: tr.children[4].textContent });
        }
        const resume = root.querySelector('.space-y-3') ? [...root.querySelectorAll('.kpi, [class*=kpi]')].map((k) => k.textContent) : [];
        bouton('Valider l’inventaire', root).click();
        await dormir(80);
        const inv = colI.all().filter((x) => !avantI.has(x.id)).map(net);
        const mvts = colM.all().filter((x) => !avantM.has(x.id)).map(net);
        const sortieCas = { lignesAffichees: apercu.length, enDirect: ecransEnDirect, resume, inventaires: inv, mouvements: mvts, produits: etatP(produits.map((p) => p.id)), messages: messages() };
        if (opts.annuler) {
          const t = toasts.filter((x) => x.type === 'success' && x.undo).pop();
          t.undo(); await dormir(40);
          sortieCas.apresAnnulation = { produits: etatP(produits.map((p) => p.id)), inventairesActifs: colI.active().filter((x) => !avantI.has(x.id)).length, mouvementsActifs: colM.active().filter((x) => !avantM.has(x.id)).length };
        }
        root.remove(); fermer();
        inventaires.push({ entree, sortie: sortieCas });
      }
      /* Les produits du périmètre « Immobilisations » : aucun dans le jeu, donc ce sont les nôtres seuls. */
      const A = poserP({ stockGros: 20, stockDetail: 8, stock: 28, cump: 500 });
      const B = poserP({ stockGros: 5, stockDetail: 0, stock: 5, cump: 1200 });
      const Cc = poserP({ stockGros: 12, stockDetail: 6, stock: 18, cump: 80 });
      const Dd = poserP({ stockGros: 10, stockDetail: 8, stock: 2, cump: 300 });
      await jouerInventaire('magasin GROS : surplus et manquant régularisés sur le stock gros ; le détail n\'est pas touché', 'gros', [A, B, Cc, Dd], { [A.code]: 23, [B.code]: 2 });
      await jouerInventaire('magasin DÉTAIL : la régularisation porte sur le détail seul', 'detail', [A, B, Cc, Dd], { [A.code]: 5, [Cc.code]: 9 });
      await jouerInventaire('aucun écart : inventaire enregistré, aucun mouvement', 'gros', [A, B, Cc, Dd], {});
      await jouerInventaire('stock total inférieur au stock du magasin (après des pertes) : le total ne passe jamais sous zéro', 'detail', [A, B, Cc, Dd], { [Dd.code]: 0 });
      await jouerInventaire('annulation du message : stocks, mouvements et inventaire restitués', 'gros', [A, B, Cc, Dd], { [A.code]: 0, [B.code]: 9 }, { annuler: true });
      await jouerInventaire('type annuel : le type est porté tel quel sur la pièce', 'gros', [A, B, Cc, Dd], { [A.code]: 21 }, { entete: { type: 'Annuel' } });

      /* ----------------------------------------------------------------------
       * TRANSFERTS
       * -------------------------------------------------------------------- */
      const transferts = [];
      async function jouerTransfert(nom, preparer, gestes, opts) {
        opts = opts || {};
        toasts.length = 0;
        const ctx = preparer();   /* { produits: [...], lots: [...], bons: [...] } */
        const root = document.createElement('div'); document.body.appendChild(root);
        SIGH.screens['m6-transferts'].render(root); await dormir(120);
        bouton('Nouveau transfert').click();
        await dormir(40);
        const entete = Object.assign({ date: '2026-10-30', demandeur: 'Maternité', motif: '' }, opts.entete || {});
        poser('date', entete.date); poser('demandeur', entete.demandeur);
        if (entete.motif) poser('motif', entete.motif);
        const modale = document.querySelector('.modal-root, [role=dialog]');
        const combo = [...modale.querySelectorAll('*')].filter((e) => typeof e.setOptions === 'function').pop();
        const qte = document.getElementById('transfert-quantite');
        const entree = { nom, produits: propre(ctx.produits.map((p) => colP.get(p.id))), lots: propre(ctx.lots || []), bons: propre(colT.all().map((b) => ({ reference: b.reference, statut: b.statut }))), entete, gestes, jour, utilisateur };
        const avantT = new Set(colT.all().map((x) => x.id)), avantM = new Set(colM.all().map((x) => x.id));
        const ids = ctx.produits.map((p) => p.id);
        const lignesVues = [];
        for (const g of gestes) {
          if (g.ajouter) {
            combo.value = g.ajouter.produitId; combo.dispatchEvent(new Event('change'));
            qte.value = g.ajouter.quantite; qte.dispatchEvent(new Event('input'));
            bouton('Ajouter', modale).click(); await dormir(30);
          } else if (g.modifier) {   /* crayon de la ligne k : modale « Modifier — … » puis « Appliquer » */
            const crayons = [...modale.querySelectorAll('button')].filter((b) => (b.getAttribute('aria-label') || b.title) === 'Modifier la quantité');
            crayons[g.modifier.rang].click(); await dormir(30);
            const modales = document.querySelectorAll('.modal-root, [role=dialog]');
            const haute = modales[modales.length - 1];
            const champ = haute.querySelector('#f_quantite'); champ.value = g.modifier.quantite; champ.dispatchEvent(new Event('input')); champ.dispatchEvent(new Event('change'));
            bouton('Appliquer', haute).click(); await dormir(30);
          } else if (g.retirer != null) {
            const poubelles = [...modale.querySelectorAll('button')].filter((b) => (b.getAttribute('aria-label') || b.title) === 'Retirer la ligne');
            poubelles[g.retirer].click(); await dormir(30);
          } else if (g.retablir) {   /* « Annuler » du message « Ligne retirée » */
            const t = toasts.filter((x) => x.message.indexOf('Ligne retirée') === 0).pop(); t.undo(); await dormir(30);
          } else if (g.stockBouge) {   /* le stock a bougé pendant la saisie */
            colP.update(g.stockBouge.produitId, g.stockBouge.patch);
          }
          lignesVues.push((modale.querySelector('p.text-right.text-sm.font-semibold') || {}).textContent || null);
        }
        const bouton2 = bouton('Valider le transfert', modale);
        bouton2.click(); await dormir(60);
        const bonsNes = colT.all().filter((x) => !avantT.has(x.id)).map(net);
        const mvtsNes = colM.all().filter((x) => !avantM.has(x.id)).map(net);
        const sortieCas = { messages: messages(), recapitulatifs: lignesVues, bons: bonsNes, mouvements: mvtsNes, produits: etatP(ids) };
        if (opts.annuler) {
          const t = toasts.filter((x) => x.type === 'success' && x.undo).pop();
          t.undo(); await dormir(40);
          sortieCas.apresAnnulation = { produits: etatP(ids), bonsActifs: colT.active().filter((x) => !avantT.has(x.id)).length, mouvementsActifs: colM.active().filter((x) => !avantM.has(x.id)).length, messages: messages() };
        }
        fermer(); root.remove();
        transferts.push({ entree, sortie: sortieCas });
      }
      const ligneA = (p, q) => ({ ajouter: { produitId: p.id, quantite: q } });

      const P = {};
      const cas = [];
      const def = (nom, preparer, gestes, opts) => cas.push({ nom, preparer, gestes, opts });

      def('une ligne : le magasin est débité, la pharmacie créditée, deux mouvements symétriques',
        () => { P.a = poserP(); return { produits: [P.a] }; }, () => [ligneA(P.a, 12)], { entete: { motif: 'Réapprovisionnement' } });
      def('trois lignes : un seul bon, deux mouvements par ligne, en-tête sans motif',
        () => { P.a = poserP({ cump: 250 }); P.b = poserP({ stockGros: 30, stockDetail: 0, stock: 30, cump: 40, unite: 'Flacon' }); P.c = poserP({ stockGros: 7, stockDetail: 3, stock: 10, cump: 1000 }); return { produits: [P.a, P.b, P.c] }; },
        () => [ligneA(P.a, 10), ligneA(P.b, 30), ligneA(P.c, 7)], { entete: { demandeur: 'Pharmacie d’urgence' } });
      def('le même article ajouté deux fois se CUMULE sur une seule ligne',
        () => { P.a = poserP(); return { produits: [P.a] }; }, () => [ligneA(P.a, 10), ligneA(P.a, 15)]);
      def('RG-03 : une ligne qui dépasse le stock est refusée en nommant l\'article, rien n\'est ajouté',
        () => { P.a = poserP({ stockGros: 8, stock: 18 }); return { produits: [P.a] }; }, () => [ligneA(P.a, 9)]);
      def('RG-03 : le disponible tient compte de ce qui est DÉJÀ posé sur le bon (« déjà N sur ce bon »)',
        () => { P.a = poserP({ stockGros: 20, stock: 30 }); return { produits: [P.a] }; }, () => [ligneA(P.a, 15), ligneA(P.a, 6)]);
      def('RG-03 : le cumul exact du stock est accepté',
        () => { P.a = poserP({ stockGros: 20, stock: 30 }); return { produits: [P.a] }; }, () => [ligneA(P.a, 15), ligneA(P.a, 5)]);
      def('quantité nulle : refusée',
        () => { P.a = poserP(); return { produits: [P.a] }; }, () => [ligneA(P.a, 0)]);
      def('aucun article choisi : refusé',
        () => { P.a = poserP(); return { produits: [P.a] }; }, () => [{ ajouter: { produitId: '', quantite: 5 } }]);
      def('aucune ligne : « Valider » refusé, rien n\'est écrit',
        () => { P.a = poserP(); return { produits: [P.a] }; }, () => []);
      def('modifier la quantité d\'une ligne : contrôlée contre le disponible RESTANT (sans compter la ligne elle-même)',
        () => { P.a = poserP({ stockGros: 20, stock: 30 }); return { produits: [P.a] }; }, () => [ligneA(P.a, 5), { modifier: { rang: 0, quantite: 20 } }]);
      def('modifier la quantité au-delà du disponible : refusé',
        () => { P.a = poserP({ stockGros: 20, stock: 30 }); return { produits: [P.a] }; }, () => [ligneA(P.a, 5), { modifier: { rang: 0, quantite: 21 } }]);
      def('retirer une ligne puis la rétablir (« Annuler »)',
        () => { P.a = poserP(); P.b = poserP(); return { produits: [P.a, P.b] }; }, () => [ligneA(P.a, 3), ligneA(P.b, 4), { retirer: 0 }, { retablir: true }]);
      def('retirer une ligne : le bon ne porte plus que l\'autre',
        () => { P.a = poserP(); P.b = poserP(); return { produits: [P.a, P.b] }; }, () => [ligneA(P.a, 3), ligneA(P.b, 4), { retirer: 0 }]);
      def('le stock a bougé pendant la saisie : dernier contrôle RG-03 avant écriture, la ligne fautive est nommée',
        () => { P.a = poserP({ stockGros: 20, stock: 30 }); return { produits: [P.a] }; }, () => [ligneA(P.a, 15), { stockBouge: { produitId: P.a.id, patch: { stockGros: 10 } } }]);
      def('lot FEFO : la ligne porte le lot qui périme le PREMIER (hors périmé et épuisé)',
        () => {
          P.a = poserP({ stockGros: 40, stock: 40 });
          const l = [{ produitId: P.a.id, numeroLot: 'L-TARD', datePeremption: '2028-05-01', quantiteRestante: 10, statut: 'actif' },
            { produitId: P.a.id, numeroLot: 'L-PERIME', datePeremption: '2025-01-01', quantiteRestante: 10, statut: 'perime' },
            { produitId: P.a.id, numeroLot: 'L-VIDE', datePeremption: '2026-12-01', quantiteRestante: 0, statut: 'actif' },
            { produitId: P.a.id, numeroLot: 'L-TOT', datePeremption: '2027-03-01', quantiteRestante: 5, statut: 'actif' }];
          l.forEach((x, i) => colL.insert(Object.assign({ id: 'LOT-ZT' + n + '-' + i }, x)));
          return { produits: [P.a], lots: l };
        }, () => [ligneA(P.a, 6)]);
      def('numérotation : TR-(plus grand rang EXISTANT + 1), archivés compris',
        () => {
          P.a = poserP();
          const bons = [{ id: 'TRB-1', reference: 'TR-00007', date: '2026-01-01', demandeur: 'Maternité', statut: 'actif' }, { id: 'TRB-2', reference: 'TR-00012', date: '2026-01-02', demandeur: 'Laboratoire', statut: 'archive' },
            { id: 'TRB-3', reference: 'AUTRE-9', date: '2026-01-03', demandeur: 'Laboratoire', statut: 'actif' }];
          bons.forEach((b) => colT.insert(Object.assign({ lignes: [], nbLignes: 0, quantite: 0 }, b)));
          return { produits: [P.a], bons };
        }, () => [ligneA(P.a, 2)]);
      def('annulation du message : TOUTES les lignes sont restituées (stocks, mouvements, bon)',
        () => { P.a = poserP(); P.b = poserP({ stockGros: 9, stock: 19 }); return { produits: [P.a, P.b] }; }, () => [ligneA(P.a, 4), ligneA(P.b, 9)], { annuler: true });

      for (const d of cas) {
        const ctxGestes = (function () { const ctx = d.preparer(); return { ctx, gestes: d.gestes(ctx) }; })();
        await jouerTransfert(d.nom, () => ctxGestes.ctx, ctxGestes.gestes, d.opts);
      }

      /* ----------------------------------------------------------------------
       * MOUVEMENTS (K.crud) — création, édition, RG-03 à l'enregistrement
       * -------------------------------------------------------------------- */
      const mouvements = [];
      async function jouerMouvement(nom, prod, saisie, opts) {
        opts = opts || {};
        toasts.length = 0;
        const root = document.createElement('div'); document.body.appendChild(root);
        SIGH.screens['m6-mouvements'].render(root); await dormir(120);
        const existant = opts.edition ? colM.insert(Object.assign({ id: 'MVT-ZT-ED' + (++n), reference: 'M' + String(900000 + n), produitId: prod.id, produit: prod.designation, type: 'entree', typeLabel: 'Entrée', quantite: 5, stockType: 'gros', date: '2026-10-01', justificatif: 'BL-TEST', utilisateur: 'Ancien' }, opts.edition)).record : null;
        const avant = new Set(colM.all().map((x) => x.id));
        const entree = { nom, produit: propre(colP.get(prod.id)), saisie, rangMax: rangMax(/^M(\d+)$/), edition: existant ? net(existant) : null, jour, utilisateur };
        if (existant) {   /* édition : le crayon de la ligne */
          const champ = root.querySelector('input[type=search]'); champ.value = existant.reference; champ.dispatchEvent(new Event('input')); await dormir(400);
          const ligne = [...root.querySelectorAll('tbody tr')].find((tr) => tr.textContent.includes(existant.reference));
          if (!ligne) throw new Error('ligne du mouvement introuvable : ' + existant.reference);
          [...ligne.querySelectorAll('button')].find((b) => (b.getAttribute('aria-label') || b.title) === 'Modifier').click();
        } else bouton('Nouveau', root).click();
        await dormir(40);
        const valeursDefaut = {};
        ['type', 'stockType', 'date'].forEach((k) => { const e = document.getElementById('f_' + k); valeursDefaut[k] = e ? e.value : null; });
        entree.valeursParDefaut = valeursDefaut;
        Object.entries(saisie).forEach(([k, v]) => poser(k, v));
        bouton(existant ? 'Enregistrer' : 'Créer', document.querySelector('.modal-root, [role=dialog]')).click();
        await dormir(60);
        const nes = colM.all().filter((x) => !avant.has(x.id)).map(net);
        mouvements.push({ entree, sortie: { messages: messages(), mouvements: nes, modifie: existant ? net(colM.get(existant.id)) : null, produit: etatP([prod.id])[0] } });
        fermer(); root.remove();
      }
      const pm = () => poserP({ stockGros: 10, stockDetail: 4, stock: 14 });
      { const p = pm(); await jouerMouvement('entrée : enregistrée au registre, SANS toucher au stock du produit', p, { produitId: p.id, type: 'entree', quantite: 6, date: '2026-10-30', stockType: 'gros', justificatif: 'BL-777' }); }
      { const p = pm(); await jouerMouvement('sortie dans la limite du stock concerné (gros)', p, { produitId: p.id, type: 'sortie', quantite: 10, date: '2026-10-30', stockType: 'gros', justificatif: 'FAC-1' }); }
      { const p = pm(); await jouerMouvement('RG-03 : sortie supérieure au stock GROS refusée', p, { produitId: p.id, type: 'sortie', quantite: 11, date: '2026-10-30', stockType: 'gros', justificatif: 'FAC-2' }); }
      { const p = pm(); await jouerMouvement('RG-03 : sortie supérieure au stock DÉTAIL refusée (le stock concerné est celui qui est choisi)', p, { produitId: p.id, type: 'sortie', quantite: 5, date: '2026-10-30', stockType: 'detail', justificatif: 'FAC-3' }); }
      { const p = pm(); await jouerMouvement('perte : même contrôle qu\'une sortie (sens négatif)', p, { produitId: p.id, type: 'perte', quantite: 5, date: '2026-10-30', stockType: 'detail', justificatif: 'PV-1' }); }
      { const p = pm(); await jouerMouvement('transfert (sens nul) : jamais refusé, même supérieur au stock', p, { produitId: p.id, type: 'transfert', quantite: 99, date: '2026-10-30', stockType: 'gros', justificatif: 'TR-X' }); }
      { const p = pm(); await jouerMouvement('stock « laboratoire » proposé par la liste : sortie contrôlée contre le stock DÉTAIL (la maquette ne connaît que gros et détail)', p, { produitId: p.id, type: 'sortie', quantite: 5, date: '2026-10-30', stockType: 'labo', justificatif: 'FAC-4' }); }
      { const p = pm(); await jouerMouvement('justificatif vide : formulaire en erreur, rien n\'est écrit', p, { produitId: p.id, type: 'entree', quantite: 1, date: '2026-10-30', stockType: 'gros', justificatif: '' }); }
      { const p = pm(); await jouerMouvement('édition : les champs transformés sont recalculés, l\'opérateur devient l\'agent connecté', p, { type: 'sortie', quantite: 3, justificatif: 'FAC-5', stockType: 'detail' }, { edition: {} }); }
      { const p = pm(); await jouerMouvement('édition : RG-03 contrôlé aussi à la modification', p, { type: 'sortie', quantite: 50, justificatif: 'FAC-6', stockType: 'detail' }, { edition: {} }); }

      /* ----------------------------------------------------------------------
       * PERTES — déclaration (un mouvement), refus RG-03, annulation
       * -------------------------------------------------------------------- */
      const pertes = [];
      async function jouerPerte(nom, prod, saisie, opts) {
        opts = opts || {};
        toasts.length = 0;
        const root = document.createElement('div'); document.body.appendChild(root);
        SIGH.screens['m6-pertes'].render(root); await dormir(120);
        bouton('Déclarer une perte', root).click();
        await dormir(40);
        Object.entries(saisie).forEach(([k, v]) => poser(k, k === 'produitId' ? prod.id : v));
        const entree = { nom, produit: propre(colP.get(prod.id)), saisie, rangMax: rangMax(/^MVT-(\d+)$/), jour, utilisateur };
        const avant = new Set(colM.all().map((x) => x.id));
        bouton('Déclarer la perte', document.querySelector('.modal-root, [role=dialog]')).click();
        await dormir(60);
        const nes = colM.all().filter((x) => !avant.has(x.id)).map(net);
        const sortieCas = { messages: messages(), mouvements: nes, produit: etatP([prod.id])[0] };
        if (opts.annuler) {
          const t = toasts.filter((x) => x.type === 'success' && x.undo).pop(); t.undo(); await dormir(30);
          sortieCas.apresAnnulation = { produit: etatP([prod.id])[0], mouvementsActifs: colM.active().filter((x) => !avant.has(x.id)).length, messages: messages() };
        }
        fermer(); root.remove();
        pertes.push({ entree, sortie: sortieCas });
      }
      const pp = () => poserP({ stockGros: 10, stockDetail: 4, stock: 14, cump: 250 });
      { const p = pp(); await jouerPerte('casse de 3 unités : un mouvement valorisé au CUMP, le stock total décroît', p, { produitId: p.id, type: 'casse', quantite: 3, date: '2026-10-30', justificatif: 'PV-100', constatePar: 'Magasinier', observation: 'Chute du carton' }); }
      { const p = pp(); await jouerPerte('péremption', p, { produitId: p.id, type: 'peremption', quantite: 14, date: '2026-10-30', justificatif: 'Lot L-9', constatePar: 'Pharmacien' }); }
      { const p = pp(); await jouerPerte('perte supérieure au stock : refusée en nommant l\'article', p, { produitId: p.id, type: 'perte', quantite: 15, date: '2026-10-30', justificatif: 'PV-101', constatePar: 'Magasinier' }); }
      { const p = pp(); await jouerPerte('justificatif vide : formulaire en erreur', p, { produitId: p.id, type: 'perte', quantite: 1, date: '2026-10-30', justificatif: '', constatePar: 'Magasinier' }); }
      { const p = pp(); await jouerPerte('annulation : le stock est rétabli, le mouvement retiré', p, { produitId: p.id, type: 'casse', quantite: 4, date: '2026-10-30', justificatif: 'PV-102', constatePar: 'Magasinier' }, { annuler: true }); }
      { const p = pp(); await jouerPerte('référence : suit les mouvements existants (série MVT-)', p, { produitId: p.id, type: 'perte', quantite: 1, date: '2026-10-30', justificatif: 'PV-103', constatePar: 'Magasinier' }); }

      return { transferts, mouvements, inventaires, pertes, erreursPage: [] };
    });
    const total = sortie.transferts.length + sortie.mouvements.length + sortie.inventaires.length + sortie.pertes.length;
    console.log(`  ${sortie.transferts.length} transferts · ${sortie.mouvements.length} mouvements · ${sortie.inventaires.length} inventaires · ${sortie.pertes.length} pertes = ${total} cas`);
    if (m.erreurs.length) console.log('  erreurs de page : ' + m.erreurs.slice(0, 5).join(' | '));
    ecrire('packages/domaine/test/vecteurs/stock_mouvements.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-stock-mouvements.js — les écrans m6-transferts, m6-mouvements, m6-inventaire-feuille et m6-pertes pilotés. Ne pas éditer.' }, sortie));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
