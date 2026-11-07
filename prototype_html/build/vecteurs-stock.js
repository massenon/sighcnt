/* =============================================================================
 * VECTEURS DES ÉCRANS DE STOCK (M6) — m6-dashboard, m6-produits, m6-stock-gros, m6-stock-detail, m6-lots, m6-alertes
 * -----------------------------------------------------------------------------
 * Les règles chiffrées de ces écrans (état du stock, seuils, valeur au CUMP, échéance de péremption, classement FEFO, « à commander »,
 * ventilation par catégorie, période des mouvements, transformation à l'enregistrement) vivent DANS les écrans de la maquette, pas dans un moteur
 * exposé : on monte donc les VRAIS écrans sur un jeu d'essai posé au magasin jetable, on lit ce qu'ils AFFICHENT (KPI, tableaux, graphiques
 * interceptés), et on PILOTE les modales de création comme le fait l'agent. Le portage Dart
 * (`packages/domaine/lib/src/stock/`) reçoit les mêmes fiches en argument et doit rendre les mêmes sorties.
 *
 *   node build/vecteurs-stock.js     →  packages/domaine/test/vecteurs/stock.json
 *
 * L'horloge de la maquette est fixée au 16/08/2026 à MINUIT LOCAL avant le chargement du module (`AUJ` est lu une fois, au chargement) : la
 * maquette calcule l'échéance par `Math.round((minuit UTC de la date − maintenant) / 86 400 000)` — elle dépend donc de l'heure de la journée et
 * du fuseau (voir ECARTS-MAQUETTE.md, E17). À minuit local et fuseau UTC l'écart est un nombre entier de jours : c'est le seul cas où la
 * maquette et le calcul calendaire se confondent, donc le seul cas qu'un vecteur peut figer.
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs des écrans de stock (M6)');
  const m = await ouvrirMaquette();
  try {
    await m.page.evaluate(() => { SIGH.core.aujourdhui = () => new Date(2026, 7, 16, 0, 0, 0); });
    // Les graphiques sont interceptés AVANT le chargement du module : on enregistre ce que l'écran leur demande de dessiner.
    await m.page.evaluate(() => {
      window.__graphiques = [];
      const G = SIGH.charts;
      for (const k of ['barres', 'anneau']) {
        const orig = G[k];
        G[k] = function () {
          window.__graphiques.push({ type: k, args: JSON.parse(JSON.stringify(Array.prototype.slice.call(arguments, 0, 2))) });
          return orig.apply(this, arguments);
        };
      }
    });
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m6-stock.js') });

    const sortie = await m.page.evaluate(async () => {
      const S = SIGH.store, D = SIGH.data;
      const propre = (x) => JSON.parse(JSON.stringify(x));
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const colP = S.collection('produits'), colL = S.collection('lots'), colM = S.collection('mouvements');
      const norm = (t) => String(t == null ? '' : t).replace(/[\n\t\r]+/g, ' ').trim();

      /* --- lecture de l'écran ------------------------------------------------------------------------------------------------------------ */
      const kpis = (root) => [...root.querySelectorAll('.kpi')].map((k) => {
        const p = k.querySelectorAll('p');
        return { libelle: norm(p[0].innerText), valeur: norm(p[1].innerText), indice: p[2] ? norm(p[2].innerText) : null };
      });
      const tableaux = (root) => [...root.querySelectorAll('table')].map((t) => {
        const entetes = [...t.querySelectorAll('thead th')].map((x) => norm(x.innerText));
        const lignes = [...t.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => norm(td.innerText)));
        return { entetes, lignes };
      });
      const cartes = (root) => [...root.querySelectorAll('.card')].map((c) => {
        const h = c.querySelector('.card-header, .card-head, h3, h2');
        return h ? norm(h.innerText) : null;
      }).filter(Boolean);
      const onglets = (root) => [...root.querySelectorAll('[role=tab], .tab, .tabs button, button')]
        .map((b) => norm(b.textContent)).filter((t) => /^(Tous les|Ordre de sortie|Archivés|Ruptures|Sous le seuil|Péremptions)/.test(t));
      async function monter(id) {
        const root = document.createElement('div'); document.body.appendChild(root);
        window.__graphiques.length = 0;
        SIGH.screens[id].render(root);
        await dormir(250);
        return root;
      }
      async function cliquerOnglet(root, debut) {
        const b = [...root.querySelectorAll('button, [role=tab], a')].find((x) => norm(x.textContent).startsWith(debut));
        if (!b) throw new Error('onglet introuvable : ' + debut);
        b.click(); await dormir(200);
      }
      const retirer = (root) => { root.remove(); document.querySelectorAll('[role=dialog]').forEach((x) => x.remove()); };

      /* --- le jeu d'essai : on met de côté (archive) tout l'existant, puis on pose les fiches ---------------------------------------------- */
      for (const col of [colP, colL, colM]) col.active().forEach((r) => col.archive(r.id));
      const produit = (id, code, designation, categorie, unite, prix, cump, gros, detail, seuil, emplacement, fournisseur) => {
        const p = { id, code, designation, categorie, unite, prixAchat: prix, prixVente: prix, cump, stockGros: gros, stockDetail: detail, stock: gros + detail,
          emplacement, fournisseur, statut: 'actif' };
        if (seuil !== undefined) p.seuilAlerte = seuil;
        return p;
      };
      const P = [
        produit('PRD9001', 'AMX5', 'AMOXICILLINE 500 MG', 'medicament', 'Boîte', 800, 800, 0, 0, 5, 'Rayon A — Casier 1', 'CAME'),
        produit('PRD9002', 'PAR5', 'PARACETAMOL 500 MG', 'medicament', 'Boîte', 250, 250, 3, 2, 5, 'Rayon A — Casier 2', 'CAME'),
        produit('PRD9003', 'SER5', 'SERUM SALE 500 ML', 'conso_medical', 'Flacon', 1000, 1000, 4, 2, 5, 'Rayon B — Casier 1', 'SOBAPS'),
        produit('PRD9004', 'GNS', 'GANTS NON STERILES', 'conso_medical', 'Boîte', 3500, 3500, 0, 0, null, 'Rayon B — Casier 2', 'SOBAPS'),
        produit('PRD9005', 'SER5M', 'SERINGUE 5 ML', 'conso_medical', 'Unité', 45, 45, 3, 0, null, 'Rayon B — Casier 3', 'SOBAPS'),
        produit('PRD9006', 'COT5', 'COTON 500 G', 'conso_medical', 'Rouleau', 1200, 1200, 10, 0, 0, 'Rayon C — Casier 1', 'CAME'),
        produit('PRD9007', 'BET', 'BETADINE 125 ML', 'medicament', 'Flacon', 600, 600, 0, 0, 0, 'Rayon A — Casier 3', 'CAME'),
        produit('PRD9008', 'RGL', 'REACTIF GLYCEMIE', 'reactif', 'Boîte', 15000, 15000, 40, 0, 40, 'Rayon D — Casier 1', 'LABOTECH'),
        produit('PRD9009', 'EDTA', 'TUBE EDTA', 'conso_labo', 'Unité', 120, 333.33, 0, 7, 10, 'Rayon D — Casier 2', 'LABOTECH'),
        produit('PRD9010', 'AUT50', 'AUTOCLAVE 50 L', 'immobilisation', 'Unité', 1250000, 1250000, 1, 0, 1, 'Rayon E — Casier 1', 'MEDIPLUS'),
        produit('PRD9011', 'DET5', 'DETERGENT 5 L', 'entretien', 'Bidon', 4000, 4000, 12, 3, 8, 'Rayon E — Casier 2', 'NATIFOURN'),
        produit('PRD9012', 'A4', 'RAME PAPIER A4', 'fourniture', 'Rame', 3200, 3200, 20, 0, 10, 'Rayon E — Casier 3', 'NATIFOURN'),
      ];
      P.forEach((p) => colP.insert(p));
      const lot = (id, produitId, numero, jours, qte, emplacement) => {
        const d = new Date(2026, 7, 16 + jours);
        const iso = SIGH.core.iso(d);
        const j = jours;
        return { id, produitId, produit: P.find((p) => p.id === produitId).designation, numeroLot: numero, datePeremption: iso, quantiteRestante: qte, emplacement,
          statut: j < 0 ? 'perime' : (j <= 90 ? 'alerte' : 'actif') };
      };
      const L = [
        lot('LOT9001', 'PRD9002', 'LOT-A01', -10, 4, 'Rayon A — Casier 2'),
        lot('LOT9002', 'PRD9003', 'LOT-B02', -1, 2, 'Rayon B — Casier 1'),
        lot('LOT9003', 'PRD9003', 'LOT-B03', 0, 1, 'Rayon B — Casier 1'),
        lot('LOT9004', 'PRD9008', 'LOT-D04', 1, 10, 'Rayon D — Casier 1'),
        lot('LOT9005', 'PRD9008', 'LOT-D05', 29, 5, 'Rayon D — Casier 1'),
        lot('LOT9006', 'PRD9009', 'LOT-D06', 30, 3, 'Rayon D — Casier 2'),
        lot('LOT9007', 'PRD9009', 'LOT-D07', 31, 3, 'Rayon D — Casier 2'),
        lot('LOT9008', 'PRD9011', 'LOT-E08', 89, 6, 'Rayon E — Casier 2'),
        lot('LOT9009', 'PRD9011', 'LOT-E09', 90, 2, 'Rayon E — Casier 2'),
        lot('LOT9010', 'PRD9012', 'LOT-E10', 91, 5, 'Rayon E — Casier 3'),
        lot('LOT9011', 'PRD9002', 'LOT-A11', 400, 12, 'Rayon A — Casier 2'),
        lot('LOT9012', 'PRD9005', 'LOT-B12', 31, 9, 'Rayon B — Casier 3'),
        lot('LOT9013', 'PRD9001', 'LOT-A13', 45, 0, 'Rayon A — Casier 1'),
      ];
      L.forEach((l) => colL.insert(l));
      const mvt = (id, date, produitId, type, quantite, stockType, justificatif) => {
        const t = D.TYPES_MOUVEMENT.find((x) => x.id === type);
        const r = { id, reference: 'M' + id.slice(-4), date, produitId, produit: P.find((p) => p.id === produitId).designation, type, typeLabel: t.label, quantite,
          justificatif, utilisateur: 'MAMAN Zoukanéri', statut: 'actif' };
        if (stockType) r.stockType = stockType;
        return r;
      };
      const M = [
        mvt('MVT9001', '2026-08-16', 'PRD9003', 'entree', 50, 'gros', 'BL-001'),
        mvt('MVT9002', '2026-08-16', 'PRD9002', 'sortie', 3, 'detail', 'FAC-001'),
        mvt('MVT9003', '2026-08-10', 'PRD9003', 'perte', 2, 'gros', 'Perte P-1'),
        mvt('MVT9004', '2026-07-20', 'PRD9008', 'entree', 10, 'gros', 'BL-002'),
        mvt('MVT9005', '2026-07-17', 'PRD9009', 'sortie', 1, 'gros', 'BS-001'),
        mvt('MVT9006', '2026-07-16', 'PRD9009', 'sortie', 1, 'gros', 'BS-002'),
        mvt('MVT9007', '2026-06-05', 'PRD9002', 'entree', 5, 'detail', 'TR-001'),
        mvt('MVT9008', '2026-08-31', 'PRD9011', 'entree', 4, 'gros', 'BL-003'),
        mvt('MVT9009', '2026-08-16', 'PRD9001', 'sortie', 7, 'gros', 'BS-003'),
        mvt('MVT9010', '2026-08-12', 'PRD9005', 'casse', 1, null, 'Casse C-1'),
        mvt('MVT9011', '2025-09-20', 'PRD9012', 'entree', 8, 'gros', 'BL-004'),
        mvt('MVT9012', '2025-08-30', 'PRD9012', 'entree', 6, 'gros', 'BL-005'),
        mvt('MVT9013', '2026-08-02', 'PRD9004', 'peremption', 2, 'detail', 'Retour R-1'),
      ];
      M.forEach((x) => colM.insert(x));

      const jeu = { produits: propre(colP.active()), lots: propre(colL.active()), mouvements: propre(colM.active()) };
      const sorties = {};

      /* --- les six écrans, jeu d'essai posé -------------------------------------------------------------------------------------------- */
      async function lire(id, etapes) {
        const root = await monter(id);
        const r = { kpis: kpis(root), tableaux: tableaux(root), onglets: onglets(root), cartes: cartes(root), graphiques: propre(window.__graphiques) };
        if (etapes) await etapes(root, r);
        retirer(root);
        return r;
      }

      sorties.dashboard = await lire('m6-dashboard', async (root, r) => {
        const wrap = root.querySelector('.grid.gap-2');
        r.notes = wrap ? [...wrap.children].map((c) => norm(c.innerText)) : [];
        r.raccourcis = [...root.querySelectorAll('a')].map((a) => norm(a.innerText));
      });

      sorties.produits = await lire('m6-produits', async (root, r) => {
        r.detail = {};
        for (const code of ['PAR5', 'GNS']) {
          const tr = [...root.querySelectorAll('tbody tr')].find((x) => [...x.children].some((td) => norm(td.innerText) === code));
          tr.click(); await dormir(250);
          const tiroir = document.querySelector('[role=dialog]');
          r.detail[code] = { texte: norm(tiroir.innerText), kpis: kpis(tiroir), tableaux: tableaux(tiroir) };
          // la fiche d'un produit : l'onglet « Lots (FEFO) » puis « Mouvements »
          for (const o of ['Lots (FEFO)', 'Mouvements']) {
            const b = [...tiroir.querySelectorAll('button')].find((x) => norm(x.textContent).startsWith(o));
            b.click(); await dormir(150);
            r.detail[code][o] = { tableaux: tableaux(tiroir) };
          }
          tiroir.remove();
        }
      });

      for (const [id, cle] of [['m6-stock-gros', 'stockGros'], ['m6-stock-detail', 'stockDetail']]) {
        sorties[cle] = await lire(id, async (root, r) => {
          // la période des mouvements : défaut (30 jours jusqu'à AUJ) puis une plage choisie
          const dates = () => [...root.querySelectorAll('input[type=date]')];
          r.periodeDefaut = dates().map((d) => d.value);
          r.mouvementsDefaut = tableaux(root).slice(-1)[0];
          const [d1, d2] = dates();
          d1.value = '2026-08-01'; d1.dispatchEvent(new Event('change'));
          d2.value = '2026-08-12'; d2.dispatchEvent(new Event('change'));
          await dormir(200);
          r.mouvementsPlage = { debut: '2026-08-01', fin: '2026-08-12', table: tableaux(root).slice(-1)[0] };
        });
      }

      sorties.lots = await lire('m6-lots', async (root, r) => {
        await cliquerOnglet(root, 'Ordre de sortie FEFO');
        r.fefo = tableaux(root).slice(-1)[0];
      });

      sorties.alertes = await lire('m6-alertes', async (root, r) => {
        r.parOnglet = {};
        r.parOnglet.Ruptures = tableaux(root).slice(-1)[0];
        await cliquerOnglet(root, 'Sous le seuil');
        r.parOnglet['Sous le seuil'] = tableaux(root).slice(-1)[0];
        await cliquerOnglet(root, 'Péremptions');
        r.parOnglet['Péremptions'] = tableaux(root).slice(-1)[0];
      });

      /* --- création de fiches : la modale pilotée comme le fait l'agent ------------------------------------------------------------------ */
      async function creer(id, valeurs) {
        const root = await monter(id);
        const avant = new Set((id === 'm6-produits' ? colP : colL).all().map((x) => x.id));
        const lireToasts = () => [...document.querySelectorAll('[role=status], [role=alert], .toast')].map((t) => norm(t.innerText)).filter(Boolean);
        document.querySelectorAll('[role=status], [role=alert], .toast').forEach((t) => t.remove());
        [...root.querySelectorAll('button')].find((b) => norm(b.textContent) === 'Nouveau').click();
        await dormir(250);
        const modal = document.querySelector('[role=dialog]');
        for (const [nom, v] of Object.entries(valeurs)) {
          // une liste de neuf entrées ou plus est un U.combo (bouton + panneau) : on lui pose la valeur comme à un <select>
          const champ = modal.querySelector('[name="' + nom + '"]') || [...modal.querySelectorAll('*')].find((e) => typeof e.setOptions === 'function' && (e.dataset.name === nom || e.getAttribute('name') === nom || nom === 'produitId'));
          if (!champ) throw new Error('champ introuvable : ' + nom);
          champ.value = v; champ.dispatchEvent(new Event('input', { bubbles: true })); champ.dispatchEvent(new Event('change', { bubbles: true }));
        }
        const bouton = [...modal.querySelectorAll('button')].find((b) => norm(b.textContent) === 'Créer');
        bouton.click(); await dormir(300);
        const nouvelles = (id === 'm6-produits' ? colP : colL).all().filter((x) => !avant.has(x.id));
        const erreurs = [...document.querySelectorAll('[data-error-for]')].filter((e) => !e.hidden && norm(e.textContent)).map((e) => e.dataset.errorFor + ' : ' + norm(e.textContent));
        const toasts = lireToasts();
        const out = { creee: nouvelles.length ? propre(nouvelles[0]) : null, erreurs, toasts };
        retirer(root);
        return out;
      }
      const base = { code: 'NOUV', designation: 'ARTICLE D\'ESSAI', categorie: 'medicament', unite: 'Boîte', prixAchat: '500', seuilAlerte: '10' };
      const casProduits = [
        ['médicament sans prix de vente ni CUMP : prix de vente = prix d\'achat, CUMP = prix d\'achat', Object.assign({}, base, { stockGros: '3', stockDetail: '4' })],
        ['médicament avec un prix de vente saisi : RG-02, il est ramené au prix d\'achat', Object.assign({}, base, { prixVente: '700', cump: '450' })],
        ['réactif avec prix de vente et CUMP saisis : conservés', Object.assign({}, base, { categorie: 'reactif', prixVente: '900', cump: '400' })],
        ['réactif sans prix de vente : prix d\'achat', Object.assign({}, base, { categorie: 'reactif' })],
        ['stocks vides : zéro', Object.assign({}, base, { stockGros: '', stockDetail: '' })],
        ['stock gros négatif : refus RG-03', Object.assign({}, base, { stockGros: '-1', stockDetail: '2' })],
        ['stock détail négatif : refus RG-03', Object.assign({}, base, { stockGros: '2', stockDetail: '-5' })],
        ['code manquant : champ obligatoire', Object.assign({}, base, { code: '' })],
        ['seuil d\'alerte manquant : champ obligatoire', Object.assign({}, base, { seuilAlerte: '' })],
        ['prix d\'achat manquant : champ obligatoire', Object.assign({}, base, { prixAchat: '' })],
        ['seuil zéro accepté', Object.assign({}, base, { seuilAlerte: '0' })],
      ];
      sorties.creationProduits = [];
      for (const [nom, valeurs] of casProduits) sorties.creationProduits.push({ nom, entree: valeurs, sortie: await creer('m6-produits', valeurs) });

      const baseLot = { produitId: 'PRD9002', numeroLot: 'LOT-NEW', quantiteRestante: '5', emplacement: 'Rayon A — Casier 2' };
      const jour = (n) => SIGH.core.iso(new Date(2026, 7, 16 + n));
      const casLots = [
        ['péremption dépassée : périmé', Object.assign({}, baseLot, { datePeremption: jour(-3) })],
        ['péremption aujourd\'hui : alerte (0 jour)', Object.assign({}, baseLot, { datePeremption: jour(0) })],
        ['péremption à 90 jours : alerte', Object.assign({}, baseLot, { datePeremption: jour(90) })],
        ['péremption à 91 jours : actif', Object.assign({}, baseLot, { datePeremption: jour(91) })],
        ['produit libellé au lot', Object.assign({}, baseLot, { produitId: 'PRD9008', datePeremption: jour(200) })],
        ['numéro de lot manquant : champ obligatoire', Object.assign({}, baseLot, { numeroLot: '', datePeremption: jour(10) })],
        ['date manquante : champ obligatoire', Object.assign({}, baseLot, { datePeremption: '' })],
      ];
      sorties.creationLots = [];
      for (const [nom, valeurs] of casLots) sorties.creationLots.push({ nom, entree: valeurs, sortie: await creer('m6-lots', valeurs) });

      /* --- le magasin VIDE : les états vides disent quelque chose ------------------------------------------------------------------------ */
      for (const col of [colP, colL, colM]) col.active().forEach((r) => col.archive(r.id));
      sorties.vide = {};
      sorties.vide.dashboard = await lire('m6-dashboard', async (root, r) => {
        const wrap = root.querySelector('.grid.gap-2');
        r.notes = wrap ? [...wrap.children].map((c) => norm(c.innerText)) : [];
        r.texte = norm(root.innerText);
      });
      sorties.vide.alertes = await lire('m6-alertes', async (root, r) => { r.texte = norm(root.innerText); });
      sorties.vide.lots = await lire('m6-lots', async (root, r) => { r.texte = norm(root.innerText); });

      const referentiels = {
        categories: D.CATEGORIES_PRODUIT.map((c) => ({ id: c.id, label: c.label })),
        typesMouvement: D.TYPES_MOUVEMENT.map((t) => ({ id: t.id, label: t.label, badge: t.badge })),
        typesStock: D.TYPES_STOCK.map((t) => ({ id: t.id, label: t.label })),
      };
      return { auj: '2026-08-16', referentiels, jeu, sorties };
    });

    ecrire('packages/domaine/test/vecteurs/stock.json', Object.assign({
      _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-stock.js — ne pas éditer. Écrans de stock M6 de la maquette montés sur un jeu d\'essai (produits, lots, mouvements) ; sorties = ce que l\'écran affiche. Horloge fixée au 16/08/2026 à minuit local.',
    }, sortie));
    if (m.erreurs.length) console.log('  (avertissements de chargement : ' + m.erreurs.length + ')');
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
