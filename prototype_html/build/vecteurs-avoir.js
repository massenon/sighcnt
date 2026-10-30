/* =============================================================================
 * VECTEURS DE LA FACTURE D'AVOIR — SIGH.emettreAvoir (moteur exposé « pour être SONDÉ »)
 * -----------------------------------------------------------------------------
 * Chaque cas pose des factures (et éventuellement une facture mère, des avoirs déjà émis) au magasin jetable, appelle le moteur de la maquette,
 * et enregistre les fiches d'ENTRÉE et la SORTIE : l'avoir, ses deux écritures de contre-passation (RG-10) et ce que la facture porte ensuite.
 *   node build/vecteurs-avoir.js   →   packages/domaine/test/vecteurs/avoir.json
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs de la facture d\'avoir');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m8-facturation.js') });
    const cas = await m.page.evaluate(() => {
      const S = SIGH.store;
      const propre = (x) => JSON.parse(JSON.stringify(x));
      const colF = S.collection('factures'), colA = S.collection('avoirs'), colM = S.collection('facturesMere'), colE = S.collection('ecritures');
      let n = 0;
      const ligne = (id, designation, montant) => ({ id, designation, quantite: 1, prixUnitaire: montant, montant, partPatient: montant, partAssureur: 0 });
      const poser = (extra) => { n++; return colF.insert(Object.assign({ numero: 'FN-2026-' + String(800 + n).padStart(5, '0'), patientId: 'P' + n, patient: 'TEST Avoir', patientCode: 'CNT/' + n + '/26',
        lignes: [ligne('L1', 'Consultation', 5000), ligne('L2', 'Glycémie', 3000), ligne('L3', 'Pansement', 2000)], montantTTC: 10000, statutPaiement: 'soldee', statutMecef: 'valide' }, extra || {})).record; };
      const defs = [];
      const cas = (nom, preparer, params, idPersonnalise) => defs.push({ nom, preparer, params, idPersonnalise });

      cas('deux lignes nommées, créance réduite (411)', () => ({ f: poser() }), (c) => ({ lignes: [{ designation: 'Consultation', montant: 5000 }, { designation: 'Glycémie', montant: 3000 }], motif: 'Erreur de facturation', remboursement: 'creance' }));
      cas('remboursement en espèces (571)', () => ({ f: poser() }), () => ({ lignes: [{ designation: 'Pansement', montant: 2000 }], motif: 'Interruption de soins', remboursement: 'especes', observations: 'Patient évacué' }));
      cas('suite donnée omise : créance réduite par défaut', () => ({ f: poser() }), () => ({ lignes: [{ designation: 'Pansement', montant: 2000 }], motif: 'Autre (préciser en observations)' }));
      cas('date fournie', () => ({ f: poser() }), () => ({ lignes: [{ designation: 'Pansement', montant: 2000 }], motif: 'Erreur de facturation', date: '2026-03-15' }));
      cas('pièce non transmise à la MECeF : registre « sans objet »', () => ({ f: poser({ statutMecef: 'en_attente' }) }), () => ({ lignes: [{ designation: 'Pansement', montant: 2000 }], motif: 'Erreur de facturation' }));
      cas('avoir total d\'une pièce sans détail par ligne', () => ({ f: poser({ lignes: [], montantTTC: 8000 }) }), (c) => ({ lignes: [{ designation: 'Avoir total — ' + c.f.numero, montant: 8000 }], motif: 'Prestation non réalisée' }));
      cas('cumul : un second avoir qui tient encore dans la facture', () => {
        const f = poser(); SIGH.emettreAvoir(f.id, { lignes: [{ designation: 'Consultation', montant: 5000 }], motif: 'Erreur de facturation' }); return { f: colF.get(f.id) };
      }, () => ({ lignes: [{ designation: 'Glycémie', montant: 3000 }], motif: 'Erreur de facturation' }));
      cas('cumul exact : l\'avoir qui solde la facture est accepté', () => {
        const f = poser(); SIGH.emettreAvoir(f.id, { lignes: [{ designation: 'Consultation', montant: 7000 }], motif: 'Erreur de facturation' }); return { f: colF.get(f.id) };
      }, () => ({ lignes: [{ designation: 'Glycémie', montant: 3000 }], motif: 'Erreur de facturation' }));
      cas('cumul dépassé : refusé, rien n\'est écrit', () => {
        const f = poser(); SIGH.emettreAvoir(f.id, { lignes: [{ designation: 'Consultation', montant: 7000 }], motif: 'Erreur de facturation' }); return { f: colF.get(f.id) };
      }, () => ({ lignes: [{ designation: 'Glycémie', montant: 3001 }], motif: 'Erreur de facturation' }));
      cas('avoir supérieur à la facture dès le premier', () => ({ f: poser() }), () => ({ lignes: [{ designation: 'Tout', montant: 10001 }], motif: 'Erreur de facturation' }));
      cas('aucune ligne nommée : refusé', () => ({ f: poser() }), () => ({ lignes: [], motif: 'Erreur de facturation' }));
      cas('lignes omises : refusé', () => ({ f: poser() }), () => ({ motif: 'Erreur de facturation' }));
      cas('montant nul : refusé', () => ({ f: poser() }), () => ({ lignes: [{ designation: 'Rien', montant: 0 }], motif: 'Erreur de facturation' }));
      cas('facture introuvable', () => ({ f: { id: 'INCONNUE', numero: 'X' } }), () => ({ lignes: [{ designation: 'Rien', montant: 100 }], motif: 'Erreur de facturation' }), 'INCONNUE');
      cas('fille consolidée dans une mère ÉMISE : refusé en nommant la mère', () => {
        const f = poser();
        const mere = colM.insert({ numero: 'FM-2026-0007', compagnie: 'NSIA', piecesFilles: [f.numero], statut: 'emise' }).record;
        return { f, mere };
      }, () => ({ lignes: [{ designation: 'Pansement', montant: 2000 }], motif: 'Erreur de facturation' }));
      cas('fille d\'une mère en BROUILLON : refusé aussi (le moteur ne regarde pas le statut de la mère)', () => {
        const f = poser();
        const mere = colM.insert({ numero: 'FM-2026-0009', compagnie: 'SUNU', piecesFilles: [f.numero], statut: 'brouillon' }).record;
        return { f, mere };
      }, () => ({ lignes: [{ designation: 'Pansement', montant: 2000 }], motif: 'Erreur de facturation' }));
      cas('une mère dont la fille est une AUTRE pièce ne bloque pas', () => {
        const f = poser(); colM.insert({ numero: 'FM-2026-0008', compagnie: 'NSIA', piecesFilles: ['AUTRE-PIECE'] });
        return { f };
      }, () => ({ lignes: [{ designation: 'Pansement', montant: 2000 }], motif: 'Erreur de facturation' }));
      cas('série annuelle : la référence suit les avoirs déjà émis', () => {
        const f = poser(); SIGH.emettreAvoir(poser().id, { lignes: [{ designation: 'A', montant: 100 }], motif: 'Erreur de facturation' });
        SIGH.emettreAvoir(poser().id, { lignes: [{ designation: 'B', montant: 100 }], motif: 'Erreur de facturation' });
        return { f };
      }, () => ({ lignes: [{ designation: 'Pansement', montant: 2000 }], motif: 'Erreur de facturation' }));
      cas('millésime : un avoir daté d\'une autre année ouvre SA série', () => ({ f: poser() }), () => ({ lignes: [{ designation: 'Pansement', montant: 2000 }], motif: 'Erreur de facturation', date: '2027-01-04' }));

      const out = [];
      for (const d of defs) {
        const ctx = d.preparer();
        const fac = ctx.f, params = d.params(ctx);
        const factureAvant = propre(colF.get(fac.id) || fac);
        const meres = propre(colM.all());
        const avoirsAvant = propre(colA.all());
        const ecrAvant = new Set(colE.all().map((e) => e.id));
        const r = SIGH.emettreAvoir(fac.id, params);
        const sortie = {};
        if (r.erreur) sortie.erreur = r.erreur;
        else {
          const rec = propre(r.record);
          ['id', '_creePar', '_creeLe', 'statut', 'maj', 'majLe', 'ecritureIds'].forEach((k) => delete rec[k]);
          sortie.avoir = rec;
          sortie.ecritures = propre(colE.all().filter((e) => !ecrAvant.has(e.id)).map((e) => { const c = Object.assign({}, e); ['id', '_creePar', '_creeLe', 'statut2'].forEach((k) => delete c[k]); return c; }));
          const apres = colF.get(fac.id);
          sortie.facture = { avoirsAjoutes: (apres.avoirIds || []).length - (factureAvant.avoirIds || []).length, montantAvoirs: apres.montantAvoirs === undefined ? null : apres.montantAvoirs };
        }
        sortie.avoirsApres = colA.all().length - avoirsAvant.length;
        out.push({ entree: { nom: d.nom, facture: factureAvant, facturesMere: meres, avoirs: avoirsAvant.map((a) => ({ reference: a.reference, factureId: a.factureId, montant: a.montant })), params, utilisateur: S.currentUser(), jour: SIGH.core.iso(SIGH.core.aujourdhui()) }, sortie });
      }
      return out;
    });
    cas.forEach((c) => console.log('  ' + c.entree.nom + ' → ' + (c.sortie.erreur ? 'REFUS ' + c.sortie.erreur.slice(0, 70) : c.sortie.avoir.reference + ' −' + c.sortie.avoir.montant + ' ' + c.sortie.avoir.statutMecef)));
    ecrire('packages/domaine/test/vecteurs/avoir.json', { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-avoir.js — SIGH.emettreAvoir. Ne pas éditer.', cas });
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
