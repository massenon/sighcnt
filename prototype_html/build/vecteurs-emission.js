/* =============================================================================
 * VECTEURS DE L'ÉMISSION DE FACTURE — l'écran m8-facturation PILOTÉ comme le fait l'agent
 * -----------------------------------------------------------------------------
 * `enregistrer()` vit dans la fermeture de l'écran : on ne peut pas l'appeler seul. Ce script monte donc le VRAI écran
 * dans la page d'extraction, choisit le patient, ajoute les lignes, saisit le règlement et clique « Enregistrer… » —
 * puis relit les factures qui sont nées au magasin. Pour chaque cas il enregistre les fiches d'ENTRÉE (patient,
 * couvertures, souscripteurs, garanties, lignes saisies, règlement) et la SORTIE (les pièces émises). Le portage Dart
 * (`packages/domaine/lib/src/caisse/emission.dart`) reçoit ces mêmes fiches en argument.
 *
 *   node build/vecteurs-emission.js     →  packages/domaine/test/vecteurs/emission.json
 *
 * Non exporté (hasard / horloge) : `numeroMecef` (tirage) — seule sa PRÉSENCE est enregistrée.
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs de l\'émission de facture');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m8-facturation.js') });
    const cas = await m.page.evaluate(async () => {
      const S = SIGH.store, PR = SIGH.parcours, C = SIGH.core;
      const propre = (x) => JSON.parse(JSON.stringify(x));
      const colSous = S.collection('souscripteurs'), colGar = S.collection('garanties'), colCou = S.collection('couverturesAssurance');
      const colPat = S.collection('patients'), colFac = S.collection('factures');
      const poser = (col, fiche) => col.insert(fiche).record;

      /* fiches de test : un employeur à grille (consultation 80 % plafonnée, médicament 70 %, analyses 100 %) */
      const sA = poser(colSous, { nom: 'Employeur EMI', assureur: 'ASS-EMI', police: 'PE-1' });
      poser(colGar, { souscripteurId: sA.id, assureur: 'ASS-EMI', categorie: 'consultation', libelle: 'Consultation', taux: 80, plafond: 5000, unitePlafond: 'acte' });
      poser(colGar, { souscripteurId: sA.id, assureur: 'ASS-EMI', categorie: 'medicament', libelle: 'Médicaments', taux: 70, plafond: null });
      poser(colGar, { souscripteurId: sA.id, assureur: 'ASS-EMI', categorie: 'analyse', libelle: 'Analyses biologiques', taux: 100, plafond: null });
      const sansGrille = poser(colSous, { nom: 'Employeur sans grille', assureur: 'ASS-NOG', police: 'PN-1' });

      const patient = (code, extra) => poser(colPat, Object.assign({ code, nom: 'EMISSION', prenom: code, statut: 'actif' }, extra));
      const pNA = patient('NA');
      const pAss = patient('ASS', { assureur: 'ASS-EMI', assureurNom: 'EMI', souscripteurId: sA.id, carteExpiration: '2099-12-31', tauxPriseEnCharge: 80 });
      const pExp = patient('EXP', { assureur: 'ASS-EMI', assureurNom: 'EMI', souscripteurId: sA.id, carteExpiration: '2020-01-01', tauxPriseEnCharge: 80 });
      const pNog = patient('NOG', { assureur: 'ASS-NOG', assureurNom: 'NOG', souscripteurId: sansGrille.id, carteExpiration: '2099-12-31', tauxPriseEnCharge: 80 });

      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const sortie = [];
      async function jouer(nom, pat, saisie, reglement, options) {
        const o = options || {};
        const root = document.createElement('div'); document.body.appendChild(root);
        SIGH.screens['m8-facturation'].render(root);
        const combos = [...root.querySelectorAll('*')].filter((e) => typeof e.setOptions === 'function');
        const selPatient = combos[0];
        selPatient.value = pat.id; selPatient.dispatchEvent(new Event('change'));
        const natures = root.querySelectorAll('select.select');
        const selNature = natures[0];
        const articles = combos[combos.length - 1];
        const champs = root.querySelectorAll('input.input');
        const bouton = (txt) => [...root.querySelectorAll('button')].find((b) => b.textContent.trim() === txt);
        // saisie : { nature, index, qte, pu, remise, typeRemise, motif, libre } ; `resolue` = ce que l'écran a réellement retenu
        const resolue = [];
        for (const l of saisie) {
          selNature.value = l.nature; selNature.dispatchEvent(new Event('change'));
          if (l.nature === 'libre') {
            [...champs].find((c) => c.placeholder === 'Désignation de la prestation').value = l.libre;
          } else {
            const i = l.label ? articles._liste.findIndex((x) => new RegExp(l.label, 'i').test(x.label)) : l.index;
            if (i < 0) throw new Error('article introuvable : ' + l.label);
            articles.value = String(i); articles.dispatchEvent(new Event('change'));
          }
          const q = [...champs].find((c) => c.type === 'number' && c.classList.contains('w-24') && c.min === '1');
          q.value = l.qte || 1;
          const pu = [...champs].find((c) => c.type === 'number' && c.classList.contains('w-32'));
          if (l.pu != null) pu.value = l.pu;
          const rem = [...champs].find((c) => c.type === 'number' && c.classList.contains('w-24') && c.min === '0');
          rem.value = l.remise || 0;
          const tr = root.querySelectorAll('select.select')[1]; tr.value = l.typeRemise || 'pct';
          const mo = root.querySelectorAll('select.select')[2]; mo.value = l.motif || '';
          const art = l.nature === 'libre' ? null : articles._liste[Number(articles.value)];
          resolue.push({ nature: l.nature, designation: l.nature === 'libre' ? l.libre : art.label, quantite: Number(q.value), prixUnitaire: Number(pu.value),
            produitId: art && art.produitId || null, secteur: art && art.secteur || null, remise: Number(rem.value), typeRemise: tr.value, motif: mo.value || null });
          const lignesAvant = root.querySelectorAll('tbody tr').length;
          // stock disponible lu AVANT l'ajout : le contrôle RG-03 en a besoin
          if (art && art.produitId) resolue[resolue.length - 1].stockDetail = S.collection('produits').get(art.produitId).stockDetail;
          bouton('Ajouter').click();
          resolue[resolue.length - 1].ajoutee = root.querySelectorAll('tbody tr').length > lignesAvant;
        }
        const regle = [...root.querySelectorAll('input.input')].find((c) => c.type === 'number' && !c.classList.contains('w-24') && !c.classList.contains('w-32') && !c.classList.contains('w-20'));
        if (reglement != null) regle.value = reglement;
        const mode = [...root.querySelectorAll('select.select')].find((s) => [...s.options].some((x) => x.value === 'especes'));
        if (o.mode) mode.value = o.mode;
        if (o.dissocier) root.querySelector('#f_dissocier').click();
        const avant = new Set(colFac.all().map((f) => f.id));
        const entree = {
          nom, patient: propre(colPat.get(pat.id)), saisie: resolue, reglement, mode: mode.value, proforma: !!o.proforma,
          date: C.iso(C.aujourdhui()), rangDebut: SIGH.parcours.rangSerieFactures((o.proforma ? 'PRO-' : 'FN-') + C.iso(C.aujourdhui()).slice(0, 4) + '-') - 1,
          souscripteurs: propre(colSous.all().filter((s) => s.id === pat.souscripteurId)),
          garanties: propre(colGar.all().filter((g) => g.souscripteurId === pat.souscripteurId)),
          couvertures: propre(colCou.all().filter((c) => c.patientId === pat.id)),
          dissocier: !!o.dissocier,
          type: C.sortBy(S.collection('naturesFacture').active(), 'ordre')[0].libelle,
        };
        const stockAvant = Object.fromEntries(S.collection('produits').all().map((p) => [p.id, [p.stockDetail, p.stock]]));
        const mvAvant = new Set(S.collection('mouvements').all().map((x) => x.id));
        bouton(o.proforma ? 'Facture pro-forma' : 'Enregistrer et encaisser').click();
        await dormir(30);
        const nees = colFac.all().filter((f) => !avant.has(f.id));
        const sorties = S.collection('mouvements').all().filter((x) => !mvAvant.has(x.id)).map((x) => ({
          produitId: x.produitId, quantite: x.quantite, type: x.type, stockType: x.stockType, justificatif: x.justificatif }));
        const stocks = S.collection('produits').all().filter((p) => stockAvant[p.id] && (stockAvant[p.id][0] !== p.stockDetail || stockAvant[p.id][1] !== p.stock))
          .map((p) => ({ produitId: p.id, avant: { stockDetail: stockAvant[p.id][0], stock: stockAvant[p.id][1] }, apres: { stockDetail: p.stockDetail, stock: p.stock } }));
        entree.produits = propre(stocks.map((x) => ({ id: x.produitId, stockDetail: x.avant.stockDetail, stock: x.avant.stock })));
        document.querySelectorAll('.print-sheet, .print-overlay').forEach((e) => e.remove());
        root.remove();
        sortie.push({
          entree, sorties, stocks,
          pieces: propre(nees.map((f) => {
            const c = Object.assign({}, f);
            ['id', 'cree', 'creeLe', 'maj', 'majLe'].forEach((k) => delete c[k]);
            c.mecef = !!c.numeroMecef; delete c.numeroMecef;
            return c;
          })),
        });
      }

      const cons = { nature: 'acte', label: 'consultation g' };
      const analyse = { nature: 'analyse', index: 0 };
      const libre = (txt, pu, qte, extra) => Object.assign({ nature: 'libre', libre: txt, pu, qte: qte || 1 }, extra || {});
      await jouer('non assuré : une seule pièce, règlement total', pNA, [analyse, libre('Carnet de santé', 500, 2)], null);
      await jouer('non assuré : règlement partiel, reliquat', pNA, [analyse, libre('Carnet de santé', 500, 2)], 1200);
      await jouer('non assuré : règlement supérieur au dû, plafonné', pNA, [libre('Soin', 1000)], 99999);
      await jouer('non assuré : règlement nul, impayée', pNA, [libre('Soin', 1000)], 0);
      await jouer('non assuré : mode MTN', pNA, [libre('Soin', 1000)], null, { mode: 'mtn' });
      await jouer('non assuré : opération dissociée du dossier (vente au comptoir)', pNA, [libre('Carnet de santé', 500)], null, { dissocier: true });
      await jouer('pro-forma : rien d\'encaissé, pas de base MECeF', pNA, [libre('Soin', 1000)], 1000, { proforma: true });
      await jouer('assuré : lignes couvertes ET non couvertes → deux pièces -A / -B', pAss, [cons, libre('Certificat hors convention', 2000)], null);
      await jouer('assuré, deux pièces : règlement partiel qui ne couvre que la pièce -A', pAss, [cons, libre('Certificat hors convention', 2000)], 100);
      await jouer('assuré, deux pièces : règlement qui déborde sur la pièce -B', pAss, [cons, libre('Certificat hors convention', 2000)], 1500);
      await jouer('assuré, deux pièces : pro-forma', pAss, [cons, libre('Certificat hors convention', 2000)], null, { proforma: true });
      await jouer('assuré : tout est couvert → une pièce, base MECeF sur la part patient', pAss, [cons, analyse], null);
      await jouer('assuré : analyses 100 % → part patient nulle, MECeF en attente', pAss, [analyse], null);
      await jouer('carte expirée (RG-09) : tout au patient, une pièce', pExp, [cons, analyse], null);
      await jouer('convention non saisie : tout au patient, une pièce', pNog, [cons], null);
      await jouer('remise en % avec motif personnel', pNA, [libre('Soin', 2000, 1, { remise: 10, typeRemise: 'pct', motif: 'personnel' })], null);
      await jouer('remise en FCFA supérieure au prix : plafonnée au prix', pNA, [libre('Soin', 1000, 3, { remise: 5000, typeRemise: 'montant', motif: 'direction' })], null);
      await jouer('remise sur un assuré : elle diminue la base avant la prise en charge', pAss, [Object.assign({}, cons, { remise: 20, typeRemise: 'pct', motif: 'client' })], null);
      await jouer('médicament : sortie de stock RG-03, justificatif = numéro de pièce', pNA, [{ nature: 'medicament', index: 0, qte: 2 }], null);
      await jouer('RG-03 : quantité supérieure au stock en pharmacie → la ligne n\'est pas ajoutée, rien à émettre', pNA, [{ nature: 'medicament', index: 0, qte: 100000 }], null);
      await jouer('RG-03 : deux ajouts du même médicament dont le cumul dépasse le stock → le second est refusé', pNA, [{ nature: 'medicament', index: 0, qte: 1 }, { nature: 'medicament', index: 0, qte: 100000 }], null);
      await jouer('catégories : hospitalisation, ligne libre « ambulance », ligne libre « consultation »', pAss, [{ nature: 'hospitalisation', index: 0, qte: 2 }, libre('Transfert ambulance', 15000), libre('Consultation à domicile', 4000)], null);
      await jouer('médicament, pro-forma : aucune sortie de stock', pNA, [{ nature: 'medicament', index: 0, qte: 2 }], null, { proforma: true });
      await jouer('assuré + médicament + non couvert : trois lignes, deux pièces, sortie de stock', pAss, [{ nature: 'medicament', index: 0, qte: 1 }, cons, libre('Certificat hors convention', 2000)], null);
      /* E6 (corrigé le 31/10/2026) : le millésime est lu sur la DATE de la pièce et le rang est celui de la série de l'année. L'horloge passe au
         4 janvier 2027 : la série repart à 00001 (plus le nombre total de factures). */
      const aujourdhuiReel = C.aujourdhui;
      C.aujourdhui = () => new Date(2027, 0, 4, 10, 0, 0);
      try {
        await jouer('nouvelle année (4 janvier 2027) : millésime 2027 et série repartie à 00001', pNA, [libre('Soin', 1000)], null);
        await jouer('nouvelle année : la 2e pièce de 2027 suit (00002), pro-forma dans SA série PRO-2027-', pNA, [libre('Soin', 1000)], null);
        await jouer('nouvelle année : pro-forma, série PRO-2027- indépendante', pNA, [libre('Soin', 1000)], 1000, { proforma: true });
      } finally { C.aujourdhui = aujourdhuiReel; }
      return sortie;
    });
    cas.forEach((c) => console.log('  ' + c.entree.nom + ' → ' + c.pieces.map((p) => p.numero + ' ' + p.statutPaiement + ' payé ' + p.montantPaye + ' base ' + p.baseMecef + (p.mecef ? ' MECeF' : '')).join(' | ') + (c.sorties.length ? ' [stock ' + c.sorties.length + ']' : '')));
    ecrire('packages/domaine/test/vecteurs/emission.json', { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-emission.js — l\'écran m8-facturation piloté. Ne pas éditer.', cas });
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
