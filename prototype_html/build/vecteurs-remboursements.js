/* =============================================================================
 * VECTEURS DES REMBOURSEMENTS & ANNULATIONS — la modale de m8-remboursements PILOTÉE comme le fait l'agent
 * -----------------------------------------------------------------------------
 * Trois natures (« Facture avoir », « Remboursement », « Annulation »), trois effets différents sur les factures. Le script monte l'écran réel,
 * ouvre « Nouvelle opération », remplit le formulaire, clique « Enregistrer » et relit ce qui est né au magasin.
 *   node build/vecteurs-remboursements.js   →   packages/domaine/test/vecteurs/remboursements.json
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs des remboursements & annulations');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m8-facturation.js') });
    const cas = await m.page.evaluate(async () => {
      const S = SIGH.store, C = SIGH.core;
      const propre = (x) => JSON.parse(JSON.stringify(x));
      const colF = S.collection('factures'), colR = S.collection('remboursements'), colA = S.collection('avoirs'), colE = S.collection('ecritures');
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      let n = 0;
      const poser = (extra) => { n++; return colF.insert(Object.assign({ numero: 'FN-2099-' + String(n).padStart(5, '0'), patientId: 'P' + n, patient: 'TEST Remb', patientCode: 'CNT/' + n + '/26',
        date: '2099-01-01', type: 'Consultation', montantTTC: 10000, montantPaye: 10000, reliquat: 0, statutPaiement: 'soldee', statutMecef: 'valide', lignes: [] }, extra || {})).record; };
      const sortie = [];
      async function jouer(nom, saisie, extra, avant) {
        const f = poser(extra);
        if (avant) avant(f);
        const root = document.createElement('div'); document.body.appendChild(root);
        SIGH.screens['m8-remboursements'].render(root);
        [...root.querySelectorAll('button')].find((b) => b.textContent.includes('Nouvelle opération')).click();
        await dormir(30);
        const dans = (id) => document.getElementById('f_' + id);
        const poserChamp = (id, v) => { const e = dans(id); if (!e) throw new Error('champ ' + id); e.value = v; e.dispatchEvent(new Event('input')); e.dispatchEvent(new Event('change')); };
        poserChamp('factureId', f.id);
        Object.entries(saisie).forEach(([k, v]) => poserChamp(k, v));
        const avantR = new Set(colR.all().map((x) => x.id)), avantF = new Set(colF.all().map((x) => x.id)), avantA = new Set(colA.all().map((x) => x.id)), avantE = new Set(colE.all().map((x) => x.id));
        const entree = { nom, facture: propre(colF.get(f.id)), saisie, rangFactures: colF.all().length, remboursements: propre(colR.all().map((r) => ({ reference: r.reference }))), avoirs: propre(colA.all().map((a) => ({ reference: a.reference, factureId: a.factureId, montant: a.montant }))), jour: C.iso(C.aujourdhui()) };
        [...document.querySelectorAll('button')].filter((b) => b.textContent.trim() === 'Enregistrer').pop().click();
        await dormir(40);
        const net = (x) => { const c = Object.assign({}, x); ['id', '_creePar', '_creeLe', '_modifiePar', '_modifieLe', 'statut'].forEach((k) => delete c[k]); delete c.numeroMecef; return propre(c); };
        const nR = colR.all().filter((x) => !avantR.has(x.id)).map(net);
        const nF = colF.all().filter((x) => !avantF.has(x.id)).map((x) => Object.assign(net(x), { mecef: !!x.numeroMecef }));
        const nA = colA.all().filter((x) => !avantA.has(x.id)).map((x) => { const c = net(x); delete c.horodatage; delete c.ecritureIds; return c; });
        const nE = colE.all().filter((x) => !avantE.has(x.id)).map((x) => { const c = propre(x); ['id', '_creePar', '_creeLe', '_modifiePar', '_modifieLe', 'pieceId'].forEach((k) => delete c[k]); return c; });
        const apres = colF.get(f.id);
        document.querySelectorAll('.modal-root, [role=dialog]').forEach((e) => e.remove()); root.remove();
        sortie.push({ entree, remboursements: nR, facturesCreees: nF, avoirsCrees: nA, ecrituresCreees: nE,
          factureAvoirs: { avoirIds: (apres.avoirIds || []).length, montantAvoirs: apres.montantAvoirs === undefined ? null : apres.montantAvoirs },
          facturePatch: { statutPaiement: apres.statutPaiement, statutMecef: apres.statutMecef, annulee: apres.annulee === undefined ? null : apres.annulee } });
      }
      const base = { date: '2026-10-30', montant: 4000, motif: 'Trop-perçu constaté', autorisePar: 'TAKI Alimatou' };
      await jouer('remboursement d\'un trop-perçu : la facture n\'est pas touchée', Object.assign({ nature: 'Remboursement' }, base));
      await jouer('annulation : la facture repasse impayée, MECeF « rejeté », marquée annulée', Object.assign({ nature: 'Annulation' }, base));
      /* B10 (31/10/2026) : la nature « Facture avoir » APPELLE le moteur unique (collection `avoirs`) ; plus de pièce négative dans `factures`. */
      await jouer('facture avoir (erreur) : un avoir dans la collection `avoirs`, contre-passation en brouillon, aucune pièce négative', Object.assign({ nature: 'Facture avoir', motifAvoir: 'erreur', refacturation: 'refaire' }, base));
      await jouer('facture avoir, service non rendu et non refacturé', Object.assign({ nature: 'Facture avoir', motifAvoir: 'non_rendu', refacturation: 'aucune' }, base, { montant: 2500 }));
      await jouer('facture avoir « remboursement au patient » : crédit caisse 571 (espèces rendues)', Object.assign({ nature: 'Facture avoir', motifAvoir: 'remboursement', refacturation: 'aucune' }, base, { montant: 1500 }));
      await jouer('facture avoir au-delà de la facture : REFUSÉ (plafond cumulé), rien n\'est écrit, pas même l\'opération', Object.assign({ nature: 'Facture avoir', motifAvoir: 'erreur', refacturation: 'aucune' }, base, { montant: 10001 }));
      await jouer('facture avoir : 6 000 déjà émis par un autre canal, 4 001 refusé', Object.assign({ nature: 'Facture avoir', motifAvoir: 'erreur', refacturation: 'aucune' }, base, { montant: 4001 }), null,
        (f) => { SIGH.emettreAvoir(f.id, { lignes: [{ designation: 'MECeF', montant: 6000 }], motif: 'Erreur de tarif', origine: 'mecef' }); });
      await jouer('facture avoir : 6 000 déjà émis, 4 000 soldent exactement', Object.assign({ nature: 'Facture avoir', motifAvoir: 'erreur', refacturation: 'aucune' }, base, { montant: 4000 }), null,
        (f) => { SIGH.emettreAvoir(f.id, { lignes: [{ designation: 'MECeF', montant: 6000 }], motif: 'Erreur de tarif', origine: 'mecef' }); });
      await jouer('montant nul : REFUSÉ en nommant le défaut (E10 corrigé), rien n\'est écrit', Object.assign({ nature: 'Remboursement' }, base, { montant: 0 }));
      await jouer('facture avoir de montant nul : REFUSÉ aussi', Object.assign({ nature: 'Facture avoir', motifAvoir: 'erreur', refacturation: 'aucune' }, base, { montant: 0 }));
      await jouer('motif vide : formulaire en erreur (le motif est obligatoire, RG-12), rien n\'est écrit', Object.assign({ nature: 'Annulation' }, base, { motif: '' }));
      return sortie;
    });
    cas.forEach((c) => console.log('  ' + c.entree.nom + ' → ' + JSON.stringify(c.remboursements.map((r) => r.reference + ' ' + r.nature)) + ' · factures créées : ' + c.facturesCreees.length));
    ecrire('packages/domaine/test/vecteurs/remboursements.json', { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-remboursements.js — la modale de m8-remboursements pilotée. Ne pas éditer.', cas });
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
