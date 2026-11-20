/* =============================================================================
 * VECTEURS DE LA MECeF (simulation) — décomposition fiscale, facture normalisée, synchronisation, avoir MECeF
 * -----------------------------------------------------------------------------
 * Le module `mecef.js` garde ses règles dans ses fermetures. Ce script charge le VRAI module pour chaque régime de TVA, pilote les écrans
 * (impression d'une facture, « Synchroniser maintenant », modale d'avoir) et enregistre ce que la maquette produit. Le boîtier physique n'est
 * pas simulé ici : seul le comportement de la maquette l'est (échanges avec le dispositif fiscal = tirage pseudo-aléatoire GRAINÉ).
 *   node build/vecteurs-mecef.js   →   packages/domaine/test/vecteurs/mecef.json
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs de la MECeF (simulation)');
  const m = await ouvrirMaquette();
  try {
    const charger = (rg) => m.page.evaluate((r) => { SIGH.data.PARAM_FISCAL.regimeTva = r; }, rg).then(() => m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/mecef.js') }));
    const sortie = { impressions: [], synchronisations: [], avoirs: [] };

    // 1. Facture normalisée imprimée : on intercepte P.etat et on lit ses tableaux, pour chaque régime.
    for (const regime of ['exonere', 'normal']) {
      await charger(regime);
      const cas = await m.page.evaluate(async (rg) => {
        const S = SIGH.store, C = SIGH.core, P = SIGH.print;
        const colF = S.collection('factures');
        const propre = (x) => JSON.parse(JSON.stringify(x));
        const defs = [
          ['une ligne', 10000, [{ designation: 'Consultation', quantite: 1, prixUnitaire: 10000 }], 'MECEF1234567'],
          ['plusieurs lignes, quantités', 18000, [{ designation: 'Glycémie', quantite: 2, prixUnitaire: 3000 }, { designation: 'Pansement', quantite: 4, prixUnitaire: 3000 }], 'MECEF7654321'],
          ['montant impair (arrondis HT / AIB)', 7777, [{ designation: 'Soin', quantite: 1, prixUnitaire: 7777 }], 'MECEF1000001'],
          ['pièce sans détail par ligne et non transmise', 5000, [], null],
          ['grand montant', 184552, [{ designation: 'Hospitalisation', quantite: 1, prixUnitaire: 184552 }], 'MECEF9999999'],
          /* E14 (corrigé le 31/10/2026) : « IFU client » = l'IFU du CLIENT, vide si inconnu, jamais celui de la clinique. */
          ['IFU du client connu : imprimé tel quel', 10000, [{ designation: 'Consultation', quantite: 1, prixUnitaire: 10000 }], 'MECEF1234568', { ifuClient: '3201912345678' }],
        ];
        const out = [];
        let n = 0;
        for (const [nom, ttc, lignes, mecef, supp] of defs) {
          n++;
          const f = colF.insert(Object.assign({ numero: 'FN-2099-' + String(n).padStart(5, '0'), patientId: 'P' + n, patient: 'TEST Fiscal', patientCode: 'CNT/' + n + '/26', date: '2026-12-31', type: 'Consultation',
            montantTTC: ttc, lignes, statutMecef: mecef ? 'valide' : 'en_attente', numeroMecef: mecef || undefined, statutPaiement: 'soldee', montantPaye: ttc }, supp || {})).record;
          const root = document.createElement('div'); document.body.appendChild(root);
          SIGH.screens['mecef-factures'].render(root);
          let capte = null;
          const etat = P.etat; P.etat = (o) => { capte = o; };
          const ligne = [...root.querySelectorAll('tbody tr')].find((tr) => tr.textContent.includes(f.numero));
          // la table est paginée et triée par date décroissante : 2099 passe en tête
          const bouton = ligne.querySelector('button[title="Imprimer la facture normalisée"], button[aria-label="Imprimer la facture normalisée"]');
          bouton.click();
          P.etat = etat; root.remove();
          const tables = [...capte.contenu.querySelectorAll('table')].map((t) => [...t.querySelectorAll('tr')].map((tr) => [...tr.children].map((c) => c.textContent.trim())));
          const paragraphes = [...capte.contenu.querySelectorAll('p')].map((p) => p.textContent).filter((t) => !/Heure|Heure :/.test(t));
          out.push({ nom, regime: rg, facture: propre(f), titre: capte.titre, sousTitre: capte.sousTitre, cartouche: capte.cartouche, tables, paragraphes });
        }
        return out;
      }, regime);
      sortie.impressions.push(...cas);
    }

    // 2. Synchronisation : seul le lot en attente change ; tirage graine = nombre de factures * 7 + 13.
    await charger('exonere');
    for (const nb of [1, 2, 3, 5, 8, 13, 21]) {
      const cas = await m.page.evaluate(async (n) => {
        const S = SIGH.store, C = SIGH.core;
        const colF = S.collection('factures');
        colF.all().forEach((f) => { if (f.statutMecef === 'en_attente') colF.update(f.id, { statutMecef: 'valide' }); });
        const test = [];
        for (let i = 0; i < n; i++) test.push(colF.insert({ numero: 'FN-2098-' + String(i + 1).padStart(5, '0'), patientId: 'Q' + i, patient: 'TEST Synchro ' + i, date: '2026-12-31', type: 'Consultation', montantTTC: 1000 + i, lignes: [], statutMecef: 'en_attente', statutPaiement: 'soldee' }).record);
        const stIn = window.setTimeout; window.setTimeout = (f, ms, ...a) => (ms === 1500 || ms === 1200) ? 0 : stIn(f, ms, ...a);
        const root = document.createElement('div'); document.body.appendChild(root);
        SIGH.screens['mecef-transmission'].render(root);
        [...root.querySelectorAll('button')].find((b) => b.textContent.includes('Synchroniser maintenant')).click();
        await new Promise((r) => setTimeout(r, 60));
        [...document.querySelectorAll('button')].filter((b) => b.textContent.trim() === 'Transmettre').pop().click();
        await new Promise((r) => setTimeout(r, 80));
        window.setTimeout = stIn;
        const apres = test.map((t) => { const f = colF.get(t.id); return { numero: f.numero, statutMecef: f.statutMecef, numeroMecef: f.numeroMecef || null, codeRetour: f.codeRetour || null, dateTransmission: f.dateTransmission || null }; });
        root.remove();
        return { nb: n, jour: C.iso(C.aujourdhui()), resultats: apres };
      }, nb);
      sortie.synchronisations.push(cas);
    }
    // 3. Avoir MECeF : la modale réelle.
    const av = await m.page.evaluate(async () => {
      const S = SIGH.store, C = SIGH.core;
      const colF = S.collection('factures'), colA = S.collection('avoirs');
      const propre = (x) => JSON.parse(JSON.stringify(x));
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      colF.all().forEach((f) => { if (f.statutMecef === 'en_attente') colF.update(f.id, { statutMecef: 'valide' }); });
      const out = [];
      let n = 0;
      async function jouer(nom, saisie, extra, avant2) {
        n++;
        const f = colF.insert(Object.assign({ numero: 'FN-2097-' + String(n).padStart(5, '0'), patientId: 'R' + n, patient: 'TEST Avoir MECeF', patientCode: 'CNT/' + n + '/26', date: '2026-12-31', type: 'Consultation', montantTTC: 10000, lignes: [], statutMecef: 'valide', statutPaiement: 'soldee' }, extra || {})).record;
        if (avant2) avant2(f);
        const root = document.createElement('div'); document.body.appendChild(root);
        SIGH.screens['mecef-avoirs'].render(root);
        [...root.querySelectorAll('button')].find((b) => b.textContent.includes('Émettre un avoir')).click();
        await dormir(30);
        const poser = (id, v) => { const e = document.getElementById('f_' + id); if (!e) throw new Error('champ ' + id); e.value = v; e.dispatchEvent(new Event('input')); e.dispatchEvent(new Event('change')); };
        poser('factureId', f.id);
        Object.entries(saisie).forEach(([k, v]) => poser(k, v));
        const avant = new Set(colA.all().map((a) => a.id));
        const entree = { nom, facture: propre(colF.get(f.id)), saisie, avoirs: propre(colA.all().map((a) => ({ reference: a.reference, factureId: a.factureId, montant: a.montant }))) };
        [...document.querySelectorAll('button')].filter((b) => b.textContent.trim() === 'Émettre l’avoir').pop().click();
        await dormir(40);
        const nouveaux = colA.all().filter((a) => !avant.has(a.id)).map((a) => { const c = Object.assign({}, a); ['id', '_creePar', '_creeLe', 'statut', 'horodatage', 'ecritureIds', 'dateTransmission'].forEach((k) => delete c[k]); c.mecef = !!c.numeroMecef; delete c.numeroMecef; return c; });
        document.querySelectorAll('.modal-root, [role=dialog]').forEach((e) => e.remove()); root.remove();
        out.push({ entree, avoirs: propre(nouveaux) });
      }
      const base = { date: '2026-10-30', montant: 4000, motif: 'Erreur de facturation' };
      await jouer('avoir partiel : transmis et validé d\'office', base);
      await jouer('avoir égal à la facture', Object.assign({}, base, { montant: 10000 }));
      await jouer('avoir supérieur à la facture : refusé, rien n\'est écrit', Object.assign({}, base, { montant: 10001 }));
      await jouer('observations portées sur l\'avoir', Object.assign({}, base, { observations: 'Patient évacué' }));
      /* B10 (31/10/2026) : l'avoir MECeF APPELLE le moteur unique ; le plafond est CUMULÉ (E15) et le montant strictement positif (E10). */
      await jouer('montant nul : refusé en nommant le défaut (E10), rien n\'est écrit', Object.assign({}, base, { montant: 0 }));
      await jouer('cumul : 6 000 déjà émis (caisse), 4 001 MECeF refusé (E15)', Object.assign({}, base, { montant: 4001 }), null,
        (f) => { SIGH.parcours.emettreAvoir(f.id, { lignes: [{ designation: 'Caisse', montant: 6000 }], motif: 'Erreur de facturation', origine: 'caisse' }); });
      await jouer('cumul : 6 000 déjà émis (caisse), 4 000 MECeF soldent exactement', Object.assign({}, base, { montant: 4000 }), null,
        (f) => { SIGH.parcours.emettreAvoir(f.id, { lignes: [{ designation: 'Caisse', montant: 6000 }], motif: 'Erreur de facturation', origine: 'caisse' }); });
      return out;
    });
    sortie.avoirs = av;
    sortie.impressions.forEach((c) => console.log('  impression · ' + c.regime + ' · ' + c.nom + ' → ' + c.tables.length + ' tables'));
    sortie.synchronisations.forEach((c) => console.log('  synchro ' + c.nb + ' → ' + c.resultats.map((r) => r.statutMecef[0] + (r.codeRetour || '')).join(' ')));
    sortie.avoirs.forEach((c) => console.log('  avoir · ' + c.entree.nom + ' → ' + c.avoirs.length));
    ecrire('packages/domaine/test/vecteurs/mecef.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-mecef.js — mecef.js piloté, par régime de TVA. Ne pas éditer.' }, sortie));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
