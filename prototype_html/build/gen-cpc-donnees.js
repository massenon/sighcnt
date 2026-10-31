/* =============================================================================
 * ENGENDRE les référentiels documentaires du poste pour M12 (liasse déposée, classeur 2025, objectifs de pilotage) depuis
 * `assets/js/data-liasse.js`, `data-compta.js` et `data.js` — jamais recopiés à la main.
 *   node build/gen-cpc-donnees.js
 * Sorties (ENGENDRÉES, ne pas éditer) : packages/domaine/lib/src/comptabilite/cpc_liasse.dart, cpc_donnees.dart
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const ROOT = path.join(__dirname, '..');
const OUT = path.join(ROOT, '..', 'packages/domaine/lib/src/comptabilite');
const JS = (f) => path.join(ROOT, 'assets/js', f);

function charger(fichiers) {
  const w = { SIGH: {} };
  w.window = w; w.global = w; w.console = console;
  vm.createContext(w);
  fichiers.forEach((f) => vm.runInContext(fs.readFileSync(JS(f), 'utf8'), w, { filename: f }));
  return w;
}
function clair(x) { return JSON.parse(JSON.stringify(x)); }
function dart(nom, json) {
  const s = JSON.stringify(json);
  if (s.includes("'''")) throw new Error('triple apostrophe dans ' + nom);
  return `const String ${nom} = r'''${s}''';\n`;
}

const liasse = charger(['data-liasse.js']).SIGH.liasse;
const L = clair({ DEPOT: liasse.DEPOT, BILAN_ACTIF: liasse.BILAN_ACTIF, BILAN_PASSIF: liasse.BILAN_PASSIF, RESULTAT: liasse.RESULTAT, FLUX: liasse.FLUX,
  DISPONIBILITES: liasse.DISPONIBILITES, SYNTHESE: liasse.SYNTHESE, NOTES_SYNTHESE: liasse.NOTES_SYNTHESE, ECARTS: liasse.ECARTS });
fs.writeFileSync(path.join(OUT, 'cpc_liasse.dart'),
  '// FICHIER ENGENDRÉ par prototype_html/build/gen-cpc-donnees.js depuis assets/js/data-liasse.js — ne pas éditer à la main.\n'
  + '// La liasse fiscale DÉPOSÉE (15/05/2026, BK505416) : références, libellés, ordre et valeurs du formulaire. Des faits : ils se citent, ne se recalculent pas.\n'
  + dart('cpcLiasseJson', L));

const compta = charger(['data-compta.js']).SIGH.compta.EXERCICE_2025;
const E = clair({ annee: compta.annee, mois: compta.mois, chiffreAffaires: compta.chiffreAffaires, totalChiffreAffaires: compta.totalChiffreAffaires,
  depenses: compta.depenses, totalDepenses: compta.totalDepenses, horsExploitation: compta.horsExploitation,
  totalHorsExploitation: compta.totalHorsExploitation, totalCharges: compta.totalCharges, resultat: compta.resultat, controle: compta.controle });
const data = fs.readFileSync(JS('data.js'), 'utf8');
function extraire(nom) {
  const i = data.indexOf('var ' + nom + ' = ');
  if (i < 0) throw new Error('introuvable : ' + nom);
  const w = {};
  vm.createContext(w);
  const fin = data.indexOf('\n  ];', i);
  vm.runInContext(data.slice(i, fin + 5).replace(/^var /, 'this.R = '), w);
  return clair(w.R);
}
const objectifs = extraire('OBJECTIFS_PILOTAGE');
fs.writeFileSync(path.join(OUT, 'cpc_donnees.dart'),
  '// FICHIER ENGENDRÉ par prototype_html/build/gen-cpc-donnees.js (data-compta.js, data.js) — ne pas éditer à la main.\n'
  + dart('cpcExercice2025Json', E) + dart('cpcObjectifsPilotageJson', objectifs));
console.log('OK', Object.keys(L).length, 'blocs de liasse ;', E.depenses.length, 'postes 2025 ;', objectifs.length, 'objectifs');
