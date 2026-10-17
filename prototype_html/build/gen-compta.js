/* =============================================================================
 * Génération du référentiel comptable à partir des classeurs de la clinique
 * -----------------------------------------------------------------------------
 * Lit les deux classeurs Excel du cadrage et produit assets/js/data-compta.js :
 *   - le plan comptable SYSCOHADA réellement utilisé (90 comptes) ;
 *   - le compte de résultat 2025 : chiffre d'affaires et dépenses mensuelles.
 * La génération évite toute recopie manuelle des montants.
 *     node build/gen-compta.js
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const XLSX = require('xlsx');

const ROOT = path.resolve(__dirname, '..');
const DOCS = path.resolve(ROOT, '../docs');
const F_PLAN = path.join(DOCS, 'DOC-20250303-WA0017..xlsx');
const F_2025 = path.join(DOCS, 'DOC-20260408-WA0005..xlsx');

const MOIS = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];

const r2 = (n) => Math.round((Number(n) || 0) * 100) / 100;

/* --- 1. Plan comptable ---------------------------------------------------- */
const wbPlan = XLSX.readFile(F_PLAN);
const lignesPlan = XLSX.utils.sheet_to_json(wbPlan.Sheets[wbPlan.SheetNames[0]], { header: 1, blankrows: false, defval: '' });
const comptes = [];
const vus = new Set();
for (const r of lignesPlan.slice(2)) {
  const num = String(r[0] || '').trim();
  const libelle = String(r[1] || '').trim();
  if (!num || !libelle) continue;
  const cle = num + '|' + libelle;
  if (vus.has(cle)) continue;
  vus.add(cle);
  comptes.push({ num, libelle });
}

/* --- 2. Compte de résultat 2025 ------------------------------------------- */
const wb25 = XLSX.readFile(F_2025);
const wsRec = wb25.Sheets[wb25.SheetNames.find((n) => n.trim().toLowerCase().startsWith('recette'))];
const lignesRec = XLSX.utils.sheet_to_json(wsRec, { header: 1, blankrows: false, defval: '' });
const ligneCA = lignesRec.find((r) => String(r[0] || '').toUpperCase().includes('CHIFFRE'));
const chiffreAffaires = [];
for (let i = 1; i <= 12; i++) chiffreAffaires.push(r2(ligneCA[i]));
const totalCA = r2(ligneCA[13]);

const wsDep = wb25.Sheets['DEPENSES25'];
const lignesDep = XLSX.utils.sheet_to_json(wsDep, { header: 1, blankrows: false, defval: '' });
const depenses = [];
let ligneTotal = null;
for (const r of lignesDep.slice(2)) {
  const num = String(r[0] || '').trim();
  const libelle = String(r[1] || '').trim();
  /* Colonnes : compte, libellé, puis pour chaque mois (montant, montant fiscal).
     La colonne « fiscale » reprend le même montant : elle n'est pas cumulée. */
  const mois = [];
  for (let i = 0; i < 12; i++) mois.push(r2(r[2 + i * 2]));
  const total = r2(mois.reduce((a, b) => a + b, 0));
  if (num.toUpperCase() === 'TOTAL') { ligneTotal = { mois, total }; continue; }
  if (total <= 0) continue;
  if (!libelle) continue;
  /* Trois postes du classeur sont chiffrés sans numéro de compte : ils sont
     conservés et signalés comme restant à rattacher au plan comptable. */
  depenses.push({ num: num || null, libelle, mois, total, aRattacher: !num });
}

/* Postes de bilan présents dans la feuille des dépenses : ils ne constituent
   pas des charges d'exploitation et sont donc isolés du résultat. */
const HORS_EXPLOITATION = {
  162000: 'Remboursement d’emprunt — poste de bilan',
  275000: 'Dépôts et cautionnements versés — poste de bilan',
  244100: 'Acquisition d’immobilisation — poste de bilan',
};

const totalDepenses = r2(depenses.reduce((a, d) => a + d.total, 0));
const totalHorsExploitation = r2(depenses.filter((d) => HORS_EXPLOITATION[d.num]).reduce((a, d) => a + d.total, 0));
const totalCharges = r2(totalDepenses - totalHorsExploitation);
const resultat = r2(totalCA - totalCharges);
const aRattacher = depenses.filter((d) => d.aRattacher);

/* Contrôle : la ligne TOTAL du classeur ne se réconcilie pas exactement avec la
   somme de son propre détail. L'écart est exposé plutôt que corrigé d'office. */
const controle = {
  totalDetail: totalDepenses,
  totalClasseur: ligneTotal ? ligneTotal.total : null,
  ecart: ligneTotal ? r2(ligneTotal.total - totalDepenses) : null,
  postesSansCompte: aRattacher.length,
  montantSansCompte: r2(aRattacher.reduce((a, d) => a + d.total, 0)),
};

/* --- 3. Écriture du module ------------------------------------------------ */
const j = (v) => JSON.stringify(v);
const sortie = `/* =============================================================================
 * SIGH-CNT — Référentiel comptable de la clinique
 * -----------------------------------------------------------------------------
 * FICHIER GÉNÉRÉ par build/gen-compta.js — ne pas modifier à la main.
 * Sources : « Classeur comptable SYSCOHADA » (plan de comptes de la clinique)
 * et « Compte de résultat / dépenses 2025 », transmis lors du cadrage.
 *
 * Le compte de résultat 2025 constitue la BASELINE FINANCIÈRE de référence :
 * les tableaux de bord comparent l'exercice courant à ces montants réels
 * (draf1 §14).
 * ========================================================================== */
(function (global) {
  'use strict';

  /* Plan comptable réellement tenu par le service comptable — ${comptes.length} comptes.
     Aucun compte de produits (classe 7) n'y figure : le chiffre d'affaires est
     suivi globalement sur la feuille « Recette ». Les comptes de produits requis
     par le SIGH sont ajoutés comme compléments dans data.js. */
  var PLAN_COMPTABLE_CNT = ${j(comptes)};

  /* Compte de résultat 2025 — montants réels, en francs CFA. */
  var EXERCICE_2025 = {
    source: 'DOC — Classeur comptable SYSCOHADA et compte de résultat 2025',
    annee: 2025,
    mois: ${j(MOIS)},
    chiffreAffaires: ${j(chiffreAffaires)},
    totalChiffreAffaires: ${totalCA},
    depenses: ${j(depenses)},
    totalDepenses: ${totalDepenses},
    horsExploitation: ${j(HORS_EXPLOITATION)},
    totalHorsExploitation: ${totalHorsExploitation},
    totalCharges: ${totalCharges},
    resultat: ${resultat},
    /* Contrôles de cohérence relevés sur le classeur source. */
    controle: ${j(controle)},
    /** Charges d'exploitation du mois (index 0 = janvier). */
    chargesDuMois: function (i) {
      return EXERCICE_2025.depenses
        .filter(function (d) { return !EXERCICE_2025.horsExploitation[d.num]; })
        .reduce(function (a, d) { return a + (d.mois[i] || 0); }, 0);
    },
    /** Résultat du mois : chiffre d'affaires moins charges d'exploitation. */
    resultatDuMois: function (i) {
      return EXERCICE_2025.chiffreAffaires[i] - EXERCICE_2025.chargesDuMois(i);
    },
    /** Postes de charges classés par poids décroissant. */
    postesCharges: function () {
      return EXERCICE_2025.depenses
        .filter(function (d) { return !EXERCICE_2025.horsExploitation[d.num]; })
        .slice()
        .sort(function (a, b) { return b.total - a.total; });
    },
  };

  global.SIGH.compta = {
    PLAN_COMPTABLE_CNT: PLAN_COMPTABLE_CNT,
    EXERCICE_2025: EXERCICE_2025,
  };
})(window);
`;

fs.writeFileSync(path.join(ROOT, 'assets/js/data-compta.js'), sortie);

console.log('Plan comptable          : ' + comptes.length + ' comptes');
console.log('Postes de dépenses 2025 : ' + depenses.length);
console.log('Chiffre d’affaires 2025 : ' + totalCA.toLocaleString('fr-FR') + ' FCFA');
console.log('Total feuille dépenses  : ' + totalDepenses.toLocaleString('fr-FR') + ' FCFA');
console.log('  dont hors exploitation: ' + totalHorsExploitation.toLocaleString('fr-FR') + ' FCFA');
console.log('Charges d’exploitation  : ' + totalCharges.toLocaleString('fr-FR') + ' FCFA');
console.log('Résultat 2025           : ' + resultat.toLocaleString('fr-FR') + ' FCFA');
console.log('\nÉcrit : assets/js/data-compta.js');
