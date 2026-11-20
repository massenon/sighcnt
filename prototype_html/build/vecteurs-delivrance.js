/* =============================================================================
 * VECTEURS DE LA DÉLIVRANCE (M6) — le moteur PR.delivrer ET les deux pharmacies, PILOTÉS comme le fait l'agent
 * -----------------------------------------------------------------------------
 * 1. `moteur` : PR.delivrer(ordonnanceId) (RG-03, justificatif = n° d'ordonnance, valorisation, alerte de stock, tâche refermée) sur des
 *    produits et des ordonnances posés au magasin jetable ; on enregistre l'ENTRÉE, la SORTIE (ou le refus nommé) et le magasin d'après.
 * 2. `pharmacie` : les écrans m6-pharmacie-interne / m6-pharmacie-externe montés pour de bon (KPI, lignes, boutons, modale de confirmation,
 *    messages), puis le clic « Délivrer » sur une ligne et ce qui est né au magasin.
 *   node build/vecteurs-delivrance.js   →   packages/domaine/test/vecteurs/delivrance.json
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs de la délivrance (moteur + pharmacies)');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m6-stock.js') });
    const sortie = await m.page.evaluate(async () => {
      const S = SIGH.store, C = SIGH.core, PR = SIGH.parcours;
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const propre = (x) => JSON.parse(JSON.stringify(x));
      const P = S.collection('produits'), O = S.collection('ordonnances'), T = S.collection('taches'), M = S.collection('mouvements');
      const META = ['_creePar', '_creeLe', '_modifiePar', '_modifieLe', 'statutAvantArchivage'];
      const net = (x, retirer) => { const c = propre(x); META.concat(retirer || []).forEach((k) => delete c[k]); if (c.statut === 'actif') delete c.statut; return c; };
      let n = 0;
      const pid = (s) => 'V' + n + s;

      /* ------------------------------------------------------------- 1. LE MOTEUR */
      const moteur = [];
      function produit(suffixe, extra) {
        return Object.assign({ id: pid(suffixe), code: 'C' + suffixe, designation: 'PRODUIT ' + suffixe + ' INJ', unite: 'Ampoule', categorie: 'medicament',
          stock: 20, stockDetail: 8, stockGros: 12, prixAchat: 500, prixVente: 500, cump: 480, seuilAlerte: 5 }, extra || {});
      }
      function jouer(nom, def) {
        n++;
        const produits = (def.produits || [{ s: 'A' }]).map((d) => produit(d.s, d.extra));
        produits.forEach((p) => P.insert(p));
        const lignes = (def.lignes || [{ s: 'A', q: 2 }]).map((l) => ({ produitId: l.s === '?' ? 'INCONNU-' + n : pid(l.s), produit: 'PRODUIT ' + l.s + ' INJ', quantite: l.q, posologie: l.poso || '1/j' }));
        const ord = Object.assign({ id: 'OV' + n, numero: 'ORD-V' + n, date: '2026-10-01', patient: 'TEST Delivrance', patientCode: 'CNT/' + n + '/26', medecin: 'Dr TEST',
          statutPaiement: 'soldee', statutDispensation: 'en_attente', medicaments: lignes }, def.ordonnance || {});
        const o = O.insert(ord).record;
        const taches = (def.taches || []).map((t) => T.insert(Object.assign({ id: 'TV' + n + t.k }, t.fiche(o))).record);
        if (def.methode) S.setValorisationSortie(def.methode);
        const refsExistantes = M.all().map((x) => x.reference).filter((r) => /^M\d{6}$/.test(r)).sort();
        const entree = { nom, methode: S.valorisationSortie(), utilisateur: S.currentUser(), refMouvementMax: refsExistantes.length ? refsExistantes[refsExistantes.length - 1] : null,
          produits: propre(produits).map((p) => net(p)), ordonnance: net(o), taches: taches.map((t) => net(t)) };
        const avantMv = new Set(M.all().map((x) => x.id)), avantT = new Set(T.all().map((x) => x.id));
        let res = null, erreur = null;
        try { res = PR.delivrer(o.id); } catch (e) { erreur = e.message; }
        if (def.methode) S.setValorisationSortie('prixVente');
        const nom2 = (x) => net(x, ['id', 'date', 'dispenseLe', 'creeLe', 'faitLe']);
        const apresTaches = T.all().filter((t) => taches.some((x) => x.id === t.id) || !avantT.has(t.id)).map((t) => Object.assign(nom2(t), avantT.has(t.id) ? { id: t.id } : { id: '<nouvelle>' }));
        moteur.push({ nom, entree, sortie: {
          erreur, deja: !!(res && res.deja),
          produits: produits.map((p) => nom2(P.get(p.id))),
          ordonnance: { statutDispensation: O.get(o.id).statutDispensation, dispensePar: O.get(o.id).dispensePar === undefined ? null : O.get(o.id).dispensePar, aDispenseLe: !!O.get(o.id).dispenseLe },
          mouvements: M.all().filter((x) => !avantMv.has(x.id)).reverse().map(nom2),
          taches: apresTaches,
          alertes: res && res.alertes ? res.alertes.map((a) => ({ produitId: a.produit.id, niveau: a.niveau, dispo: a.dispo, seuil: a.seuil })) : [],
        } });
      }
      jouer('une ligne : stock de détail et stock total décomptés, justificatif = n° d\'ordonnance, valorisée au prix de vente', {});
      jouer('deux produits sur la même ordonnance : une sortie par ligne', { produits: [{ s: 'A' }, { s: 'B', extra: { prixVente: 700, cump: 650 } }], lignes: [{ s: 'A', q: 2 }, { s: 'B', q: 3 }] });
      jouer('produit sans stock de détail : le stock total sert de disponible', { produits: [{ s: 'A', extra: { stockDetail: null, stock: 10 } }], lignes: [{ s: 'A', q: 3 }] });
      jouer('ordonnance non réglée : la délivrance est bloquée', { ordonnance: { statutPaiement: 'impayee' } });
      jouer('ordonnance déjà servie : rien n\'est refait', { ordonnance: { statutDispensation: 'servie' } });
      jouer('stock de détail insuffisant : refus NOMMÉ, rien n\'est écrit', { produits: [{ s: 'A', extra: { stockDetail: 3 } }], lignes: [{ s: 'A', q: 5 }] });
      jouer('une ligne couverte et une non couverte : tout est refusé (jamais de service à moitié)', { produits: [{ s: 'A' }, { s: 'B', extra: { stockDetail: 1 } }], lignes: [{ s: 'A', q: 2 }, { s: 'B', q: 4 }] });
      jouer('produit introuvable : refus nommé (0 disponible)', { lignes: [{ s: '?', q: 1 }] });
      jouer('RG-03 — deux lignes du MÊME produit : le cumul dépasse le stock, refusé (écart E42 corrigé)', { produits: [{ s: 'A', extra: { stockDetail: 8 } }], lignes: [{ s: 'A', q: 5 }, { s: 'A', q: 5 }] });
      jouer('deux lignes du même produit dont le cumul tient : servies', { produits: [{ s: 'A', extra: { stockDetail: 8 } }], lignes: [{ s: 'A', q: 3 }, { s: 'A', q: 5 }] });
      jouer('valorisation au CUMP (paramètre de la Direction) : les DEUX valeurs sont portées', { methode: 'cump', produits: [{ s: 'A', extra: { prixVente: 500, cump: 480.4 } }], lignes: [{ s: 'A', q: 3 }] });
      jouer('produit sans prix de vente : le prix d\'achat sert', { produits: [{ s: 'A', extra: { prixVente: null, prixAchat: 250, cump: null } }], lignes: [{ s: 'A', q: 4 }] });
      jouer('la sortie fait passer SOUS le seuil : une tâche de réapprovisionnement naît', { produits: [{ s: 'A', extra: { stockDetail: 8, stock: 8, seuilAlerte: 6 } }], lignes: [{ s: 'A', q: 3 }] });
      jouer('la sortie vide le rayon : RUPTURE, priorité haute', { produits: [{ s: 'A', extra: { stockDetail: 3, stock: 3 } }], lignes: [{ s: 'A', q: 3 }] });
      jouer('une tâche de réapprovisionnement déjà ouverte : mise à jour, jamais de doublon', {
        produits: [{ s: 'A', extra: { stockDetail: 8, stock: 8, seuilAlerte: 6 } }], lignes: [{ s: 'A', q: 3 }],
        taches: [{ k: 'R', fiche: () => ({ type: 'reapprovisionnement', poste: 'stock', libelle: 'Sous le seuil — PRODUIT A INJ', produitId: pid('A'), statut: 'en_attente', priorite: 'normale', stockRestant: 7, seuil: 6 }) }] });
      jouer('une tâche de réapprovisionnement déjà TERMINÉE (statut « fait ») : mise à jour aussi, aucune nouvelle (écart E43 porté tel quel)', {
        produits: [{ s: 'A', extra: { stockDetail: 8, stock: 8, seuilAlerte: 6 } }], lignes: [{ s: 'A', q: 3 }],
        taches: [{ k: 'R', fiche: () => ({ type: 'reapprovisionnement', poste: 'stock', libelle: 'Sous le seuil — PRODUIT A INJ', produitId: pid('A'), statut: 'fait', priorite: 'normale', stockRestant: 7, seuil: 6 }) }] });
      jouer('au-dessus du seuil : aucune alerte', { produits: [{ s: 'A', extra: { stockDetail: 30, stock: 30, seuilAlerte: 5 } }], lignes: [{ s: 'A', q: 2 }] });
      jouer('seuil non fixé : signalé « sans seuil », aucune tâche', { produits: [{ s: 'A', extra: { seuilAlerte: null } }], lignes: [{ s: 'A', q: 2 }] });
      jouer('la tâche de dispensation de l\'ordonnance est refermée', { taches: [{ k: 'D', fiche: (o) => ({ type: 'dispensation', poste: 'pharmacie', statut: 'en_attente', ordonnanceId: o.id, reference: o.numero, patient: 'TEST', patientCode: 'CNT/1/26', detail: 'Délivrer', montant: 1000 }) }] });

      /* ---------------------------------------------------------- 2. LES DEUX PHARMACIES */
      const pharmacie = [];
      /* Le décor : quatre produits, cinq ordonnances — une par situation que l'écran distingue. */
      function decor() {
        n++;
        O.all().forEach((o) => O.archive(o.id)); T.all().forEach((t) => T.archive(t.id));
        const p = (s, designation, extra) => P.insert(Object.assign({ id: 'PH' + n + s, code: 'PH' + s, designation, unite: 'Unité', categorie: 'medicament', stock: 20, stockDetail: 10, stockGros: 10, prixAchat: 100, prixVente: 100, cump: 100, seuilAlerte: 3 }, extra || {})).record;
        const ids = {
          inj: p('1', 'ADRENALINE 1 MG INJ', { stock: 10, stockDetail: 4 }).id,
          serum: p('2', 'SERUM SALE 0,9 % 500 ML INJ', { stock: 2, stockDetail: 2 }).id,
          cp: p('3', 'PARACETAMOL 500 MG CP', { stock: 50, stockDetail: 20 }).id,
          gel: p('4', 'AMOXICILLINE 500 MG GELULE', { stock: 1, stockDetail: 1 }).id,
        };
        const l = (id, nom, q, extra) => Object.assign({ produitId: id, produit: nom, quantite: q, posologie: 'Posologie ' + nom.split(' ')[0] }, extra || {});
        const o = (num, date, st, sd, meds) => O.insert({ id: 'PO' + n + num, numero: 'ORD-P' + num, date, patient: 'TEST Patient' + num, patientCode: 'CNT/' + num + '/26', medecin: 'Dr TEST', statutPaiement: st, statutDispensation: sd, medicaments: meds }).record;
        o('A', '2026-10-01', 'soldee', 'en_attente', [l(ids.inj, 'ADRENALINE 1 MG INJ', 2), l(ids.cp, 'PARACETAMOL 500 MG CP', 10)]);
        o('B', '2026-10-02', 'impayee', 'en_attente', [l(ids.serum, 'SERUM SALE 0,9 % 500 ML INJ', 1), l(ids.cp, 'PARACETAMOL 500 MG CP', 3)]);
        o('C', '2026-10-03', 'soldee', 'servie', [l(ids.cp, 'PARACETAMOL 500 MG CP', 5)]);
        o('D', '2026-10-04', 'soldee', 'en_attente', [l(ids.serum, 'SERUM SALE 0,9 % 500 ML INJ', 5), l(ids.gel, 'AMOXICILLINE 500 MG GELULE', 1)]);
        o('E', '2026-10-05', 'soldee', 'en_attente', [l(ids.cp, 'PARACETAMOL 500 MG CP', 2, { voie: 'parenterale' }), l('INCONNU', 'PRODUIT INCONNU', 1)]);
        return ids;
      }
      const lireEcran = (root) => {
        const txt = root.innerText.split('\n').map((x) => x.trim()).filter(Boolean);
        const kpi = ['Lignes de cette pharmacie', 'À délivrer', 'Bloquées faute de règlement', 'Non couvertes par le stock'].map((lab) => txt[txt.indexOf(lab) + 1]);
        const lignes = [...root.querySelectorAll('tbody tr')].map((tr) => ({
          cellules: [...tr.children].slice(0, -1).map((td) => td.innerText.replace(/\s+/g, ' ').trim()),
          actions: [...tr.querySelectorAll('button')].map((b) => (b.title || b.getAttribute('aria-label') || '') + '|' + b.textContent.trim()),
        }));
        return { kpi, lignes, vide: txt.filter((x) => /^Aucun/.test(x)) };
      };
      const toasts = () => [...document.querySelectorAll('#toast-host > div')].map((d) => [...d.querySelectorAll('p')].map((p) => p.textContent.trim()));
      const boutonLigne = (root, numero, libelle) => { const tr = [...root.querySelectorAll('tbody tr')].find((x) => x.children[0].innerText.trim() === numero); return tr && [...tr.querySelectorAll('button')].find((b) => (b.title || b.getAttribute('aria-label') || b.textContent).includes(libelle)); };
      for (const [ecran, voie] of [['m6-pharmacie-interne', 'parenterale'], ['m6-pharmacie-externe', 'orale']]) {
        const ids = decor();
        const root = document.createElement('div'); document.body.appendChild(root);
        SIGH.screens[ecran].render(root);
        const cas = { ecran, voie, ids, entree: { produits: propre(P.all().filter((x) => x.id.startsWith('PH' + n))).map((x) => net(x)), ordonnances: propre(O.active()).map((x) => net(x)), refMvtMax: M.all().map((x) => x.reference).filter((r) => /^MVT-\d{5}$/.test(r)).sort().pop() || null },
          lu: lireEcran(root), actions: [] };
        /* Les gestes : une ligne bloquée, une ligne non couverte, une ligne délivrable. */
        const gestes = voie === 'orale'
          ? [['ORD-PB', 'Bloquée', null], ['ORD-PD', 'Délivrer', 'refus'], ['ORD-PA', 'Délivrer', 'ok']]
          : [['ORD-PB', 'Bloquée', null], ['ORD-PD', 'Délivrer', 'refus'], ['ORD-PA', 'Délivrer', 'ok']];
        for (const [num, lib, attendu] of gestes) {
          document.querySelectorAll('#toast-host > div').forEach((d) => d.remove());
          const b = boutonLigne(root, num, lib);
          if (!b) { cas.actions.push({ ordonnance: num, bouton: lib, absent: true }); continue; }
          const avantP = propre(P.all().filter((x) => x.id.startsWith('PH' + n))).map((x) => net(x)), avantMv = new Set(M.all().map((x) => x.id));
          b.click(); await dormir(40);
          const modale = document.querySelector('.modal-root, [role=dialog]');
          const rec = { ordonnance: num, bouton: lib, modale: modale ? modale.innerText.replace(/\s+/g, ' ').trim() : null };
          if (modale) { [...modale.querySelectorAll('button')].filter((x) => x.textContent.trim() === 'Délivrer').pop().click(); await dormir(60); }
          rec.toasts = toasts();
          rec.produits = propre(P.all().filter((x) => x.id.startsWith('PH' + n))).map((x) => net(x));
          rec.mouvements = M.all().filter((x) => !avantMv.has(x.id)).map((x) => net(x, ['id', 'date']));
          rec.ordonnance_apres = { statutDispensation: O.all().find((o) => o.numero === num).statutDispensation };
          rec.lu_apres = lireEcran(root);
          rec.changements = JSON.stringify(rec.produits) !== JSON.stringify(avantP);
          cas.actions.push(rec);
          document.querySelectorAll('.modal-root, [role=dialog]').forEach((e) => e.remove());
        }
        root.remove(); document.querySelectorAll('.modal-root, [role=dialog]').forEach((e) => e.remove());
        pharmacie.push(cas);
      }
      O.all().forEach((o) => O.archive(o.id));
      /* ------------------------------------------------------------- 3. LA DISPENSATION */
      n++;
      O.all().forEach((o) => O.archive(o.id)); T.all().forEach((t) => T.archive(t.id));
      P.all().forEach((x) => P.archive(x.id));
      const col = S.collection('dispensations', { module: 'M6', entite: 'Dispensation' });
      col.all().forEach((d) => col.archive(d.id));
      const pd = (s, designation, detail, extra) => P.insert(Object.assign({ id: 'DS' + n + s, code: 'DS' + s, designation, unite: 'Unité', categorie: 'medicament', stock: detail, stockDetail: detail, stockGros: 0, prixAchat: 100, prixVente: 100, cump: 100, seuilAlerte: 3 }, extra || {})).record;
      const q1 = pd('1', 'ARTESUNATE 60 MG INJ', 12), q2 = pd('2', 'COTON HYDROPHILE 500 G', 0), q3 = pd('3', 'GANT STERILE', 5), q4 = pd('4', 'SERUM SALE 0,9 % 500 ML INJ', 2);
      [['DISP-00001', '2026-09-20', 'Dupont', [{ produit: 'ARTESUNATE 60 MG INJ', quantite: 2, unite: 'Unité', prix: 1500 }, { produit: 'GANT STERILE', quantite: 1, unite: 'Boîte', prix: 750 }]],
        ['DISP-00002', '2026-09-25', 'Martin', [{ produit: 'SERUM SALE 0,9 % 500 ML INJ', quantite: 3, unite: 'Poche', prix: 600 }]],
        ['DISP-00003', '2026-10-02', 'Durand', []]].forEach(([ref, date, nom, lignes], i) => col.insert({ reference: ref, date, patientId: 'P' + i, patient: 'TEST ' + nom, patientCode: 'CNT/' + (i + 1) + '/26',
        lignes, montant: lignes.reduce((t, l) => t + l.quantite * l.prix, 0), dispensePar: 'DIEYABIDI Aïssatou' }));
      const ordo = (num, date, st, meds) => O.insert({ id: 'DO' + n + num, numero: 'ORD-D' + num, date, patient: 'TEST Dispensation' + num, patientCode: 'CNT/' + num + '/26', medecin: 'Dr TEST', statutPaiement: st, statutDispensation: 'en_attente', medicaments: meds }).record;
      const lg = (p, q, poso) => ({ produitId: p.id, produit: p.designation, quantite: q, posologie: poso });
      const o1 = ordo('1', '2026-10-10', 'soldee', [lg(q1, 2, '1 inj/j'), lg(q3, 1, '')]);
      const o2 = ordo('2', '2026-10-11', 'soldee', [lg(q3, 4, '2/j'), lg(q4, 6, '1/j')]);
      const o3 = ordo('3', '2026-10-12', 'impayee', [lg(q1, 1, '1/j')]);
      const o4 = ordo('4', '2026-10-13', 'impayee', [lg(q1, 1, '1/j')]);
      const tache = (o, statut, urgent) => T.insert({ id: 'TD' + n + o.id, type: 'dispensation', poste: 'pharmacie', statut, ordonnanceId: o.id, reference: o.numero, patient: o.patient, patientCode: o.patientCode, detail: 'Délivrer ' + o.medicaments.length + ' ligne(s)', montant: 1000, date: o.date, urgent: !!urgent }).record;
      tache(o1, 'en_attente'); tache(o2, 'en_attente', true); tache(o3, 'en_attente'); tache(o4, 'bloque');
      const rootD = document.createElement('div'); document.body.appendChild(rootD);
      SIGH.screens['m6-dispensation'].render(rootD);
      const lireD = () => {
        const txt = rootD.innerText.split('\n').map((x) => x.trim()).filter(Boolean);
        const kpi = ['Dispensations enregistrées', 'Valeur dispensée', 'Références en pharmacie', 'Ruptures en pharmacie'].map((lab) => txt[txt.indexOf(lab) + 1]);
        const tables = [...rootD.querySelectorAll('table')].map((t) => ({
          entetes: [...t.querySelectorAll('thead th')].map((th) => th.innerText.replace(/\s+/g, ' ').trim()),
          lignes: [...t.querySelectorAll('tbody tr')].map((tr) => ({ cellules: [...tr.children].map((td) => td.innerText.replace(/\s+/g, ' ').trim()), actions: [...tr.querySelectorAll('button')].map((b) => (b.title || b.getAttribute('aria-label') || '') + '|' + b.textContent.trim()) })),
        }));
        return { kpi, titreFile: txt.find((x) => /^Ordonnances à délivrer/.test(x)) || null, tables, vide: txt.filter((x) => /^Aucun/.test(x)) };
      };
      const dispensation = { entree: { produits: [q1, q2, q3, q4].map((x) => net(P.get(x.id))), dispensations: propre(col.active()).map((x) => net(x)), ordonnances: [o1, o2, o3, o4].map((x) => net(O.get(x.id))), taches: T.active().map((x) => net(x, ['date'])) }, lu: lireD(), actions: [] };
      const cliquerFile = async (num, titre) => {
        document.querySelectorAll('#toast-host > div').forEach((d) => d.remove());
        const tr = [...rootD.querySelectorAll('tbody tr')].find((x) => x.children[0].innerText.includes(num));
        const b = tr && [...tr.querySelectorAll('button')].find((x) => (x.title || x.getAttribute('aria-label') || '').includes(titre));
        const rec = { ordonnance: num, bouton: titre, absent: !b };
        if (!b) return rec;
        b.click(); await dormir(40);
        const modale = document.querySelector('.modal-root, [role=dialog]');
        rec.modale = modale ? modale.innerText.replace(/\s+/g, ' ').trim() : null;
        rec.boutonsModale = modale ? [...modale.querySelectorAll('button')].map((x) => x.textContent.trim()).filter(Boolean) : [];
        rec.toastsOuverture = toasts();
        if (modale) {
          const c = [...modale.querySelectorAll('button')].find((x) => x.textContent.trim() === 'Confirmer la délivrance');
          if (c) {
            const avantMv = new Set(M.all().map((x) => x.id));
            c.click(); await dormir(60);
            rec.toasts = toasts();
            rec.mouvements = M.all().filter((x) => !avantMv.has(x.id)).map((x) => net(x, ['id', 'date']));
            rec.produits = [q1, q2, q3, q4].map((x) => net(P.get(x.id)));
            rec.ordonnance_apres = { statutDispensation: O.all().find((o) => o.numero === num).statutDispensation };
            rec.lu_apres = lireD();
          }
        }
        document.querySelectorAll('.modal-root, [role=dialog]').forEach((e) => e.remove());
        return rec;
      };
      dispensation.actions.push(await cliquerFile('ORD-D1', 'Délivrer'));
      dispensation.actions.push(await cliquerFile('ORD-D2', 'Délivrer'));
      dispensation.actions.push(await cliquerFile('ORD-D3', 'Délivrer'));
      dispensation.actions.push(await cliquerFile('ORD-D4', 'Bloquée'));
      /* Le tiroir d'une dispensation de l'historique. */
      const ligneH = [...rootD.querySelectorAll('table')][1].querySelector('tbody tr');
      ligneH.click(); await dormir(50);
      const tiroir = [...document.querySelectorAll('[role=dialog], aside, .drawer')].pop();
      dispensation.tiroir = tiroir ? tiroir.innerText.replace(/\s+/g, ' ').trim() : null;
      dispensation.tiroirRef = ligneH.children[0].innerText.trim();
      document.querySelectorAll('.modal-root, [role=dialog], .drawer').forEach((e) => e.remove());
      rootD.remove();
      O.all().forEach((o) => O.archive(o.id)); T.all().forEach((t) => T.archive(t.id));
      return { moteur, pharmacie, dispensation };
    });
    ecrire('packages/domaine/test/vecteurs/delivrance.json', { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-delivrance.js — PR.delivrer et les pharmacies de m6-stock.js pilotés. Ne pas éditer.', ...sortie });
    console.log('  dispensation : ' + JSON.stringify(sortie.dispensation.lu.kpi) + ' ' + sortie.dispensation.lu.titreFile + ' · ' + sortie.dispensation.actions.map((a) => a.ordonnance + ':' + (a.absent ? 'absent' : (a.toasts || a.toastsOuverture || []).map((t) => t.join(' / ')).join('|'))).join(' ; '));
    sortie.pharmacie.forEach((c) => console.log('  ' + c.ecran + ' : kpi ' + c.lu.kpi.join('/') + ' · ' + c.lu.lignes.length + ' ligne(s) · ' + c.actions.map((a) => a.ordonnance + ':' + (a.toasts ? JSON.stringify(a.toasts) : 'absent')).join(' ; ')));
    sortie.moteur.forEach((c) => console.log('  ' + c.nom + ' → ' + (c.sortie.erreur ? 'REFUS ' + c.sortie.erreur : c.sortie.deja ? 'déjà' : c.sortie.mouvements.length + ' sortie(s), ' + c.sortie.alertes.map((a) => a.niveau).join('/'))));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
