/* =============================================================================
 * VECTEURS DES MONTANTS ENTIERS DE LA MECeF (lot M1, 08/11/2026) : SIGH.mecefMontants et SIGH.mecef.validerAcheteur
 * -----------------------------------------------------------------------------
 * La fonction unique des montants (parcours.js) est PILOTÉE dans la maquette : on enregistre ce qu'elle rend pour un jeu de cas fixes (remise
 * répartie, écart d'arrondi sur la plus grande ligne, quantités décimales, refus nommés, base sans part assureur) et pour 300 ventes tirées au
 * hasard d'un générateur à graine. Le domaine Dart (lot suivant) rejouera ces vecteurs ; AUCUN Dart n'est écrit ici.
 *   node build/vecteurs-mecef-montants.js   →   packages/domaine/test/vecteurs/mecef_montants.json
 * ========================================================================== */
'use strict';
const { ouvrirMaquette, ecrire } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs des montants entiers MECeF');
  const m = await ouvrirMaquette();
  try {
    const sortie = await m.page.evaluate(() => {
      const M = SIGH.mecefMontants, A = SIGH.mecef.validerAcheteur;
      const L = (net, o) => Object.assign({ designation: 'x', quantite: 1, prixUnitaire: net }, o || {});
      const cas = [
        ['une ligne', { lignes: [L(10000)] }],
        ['remise globale répartie, écart sur la plus grande ligne', { lignes: [L(10000), L(3), L(7)], remiseGlobale: 100 }],
        ['quantité décimale, moitié vers le haut', { lignes: [L(3001, { quantite: 0.5 })] }],
        ['quantité à quatre décimales refusée', { lignes: [L(1000, { quantite: 1.2345 })] }],
        ['prix décimal refusé', { lignes: [L(1500.5)] }],
        ['montant brut porté par la pièce (prix décimal toléré)', { lignes: [{ designation: 'x', quantite: 3, prixUnitaire: 333.33, montantBrut: 1000 }] }],
        ['remise de ligne supérieure au montant refusée', { lignes: [L(1000, { remise: 1001 })] }],
        ['total attendu différent refusé', { lignes: [L(1000), L(2000)], totalAttendu: 3001 }],
        ['total attendu égal', { lignes: [L(1000), L(2000)], totalAttendu: 3000 }],
        ['parts qui ne totalisent pas la ligne refusées', { lignes: [L(10000, { partAssureur: 3000, partPatient: 6999 })] }],
        ['paiements différents de la base refusés', { lignes: [L(1000)], paiements: [999] }],
        ['base : ni part assureur ni remise', { lignes: [L(10000, { partAssureur: 3000 }), L(6000, { remise: 1000 })] }],
        ['seulement les lignes payées', { lignes: [L(10000, { statutPaiement: 'paye' }), L(5000, { statutPaiement: 'du' })], seulementPayees: true }],
        ['AIB 1 % sur base exonérée', { lignes: [L(7777)], aibTaux: 1, tauxTva: 0 }],
        ['AIB 5 %, TVA 18 %', { lignes: [L(11800)], aibTaux: 5, tauxTva: 18 }],
        ['aucune ligne refusée', { lignes: [] }],
      ].map(([nom, entree]) => ({ nom, entree, sortie: JSON.parse(JSON.stringify(M(entree))) }));
      let g = 20261108; const r = () => (g = (g * 1103515245 + 12345) % 2147483648) / 2147483648;
      const hasard = [];
      for (let i = 0; i < 300; i++) {
        const n = 1 + Math.floor(r() * 5), lignes = [];
        for (let k = 0; k < n; k++) {
          const q = [1, 2, 3, 0.5, 1.5, 2.25][Math.floor(r() * 6)], pu = 100 + Math.floor(r() * 50000);
          const brut = Math.floor((Math.round(q * 1000) * pu + 500) / 1000);
          const remise = r() < 0.3 ? Math.floor(r() * brut * 0.5) : 0;
          lignes.push({ designation: 'l' + k, quantite: q, prixUnitaire: pu, remise, partAssureur: r() < 0.4 ? Math.floor((brut - remise) * 0.8) : 0 });
        }
        const entree = { lignes, remiseGlobale: r() < 0.4 ? Math.floor(r() * 500) : 0, aibTaux: [0, 1, 5][Math.floor(r() * 3)], tauxTva: 0 };
        hasard.push({ entree, sortie: JSON.parse(JSON.stringify(M(entree))) });
      }
      const acheteurs = [{}, { ifu: '3201642748214', nom: 'Clinique X' }, { ifu: '3201 6427 48214', nom: 'X' }, { ifu: '123', nom: 'X' }, { ifu: '32016427482AB', nom: 'X' },
        { ifu: '3201642748214', nom: '' }, { ifu: '', nom: 'Particulier' }, { aibTaux: 5 }, { aibTaux: 7 }, { aibTaux: 0 }].map((e) => ({ entree: e, sortie: JSON.parse(JSON.stringify(A(e))) }));
      return { cas, hasard, acheteurs };
    });
    console.log('  ' + sortie.cas.length + ' cas fixes · ' + sortie.hasard.length + ' ventes au hasard · ' + sortie.acheteurs.length + ' acheteurs');
    ecrire('packages/domaine/test/vecteurs/mecef_montants.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-mecef-montants.js : SIGH.mecefMontants et validerAcheteur de la maquette. Ne pas éditer.' }, sortie));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
