/* =============================================================================
 * LA RÈGLE PAR FAMILLE DES FICHIERS, CÔTÉ SERVEUR (lot D1 du plan documents numérisés)
 * -----------------------------------------------------------------------------
 *   node build/gen-regles-fichiers.js           écrit api/regles-fichiers.json
 *   node build/gen-regles-fichiers.js --verifier  compare sans écrire (code de sortie 1 si le fichier est en retard)
 *
 * Le serveur PHP ne connaît pas la matrice des droits (CLAUDE.md, vague 66). Pour les FICHIERS il en reçoit une copie GROSSIÈRE, par famille et par rôle, ENGENDRÉE ici :
 *   courrier : les droits du rôle sur l'écran `m13-courriers` ;
 *   patient  : les droits du rôle sur l'écran `m1-documents`, plus la ZONE du type du document (les profils de la zone 2 sont ceux de `D.DOCUMENTS.ROLES_ZONE_2`).
 * Sources : `packages/rbac/data/rbac.json` (matrice d'ORIGINE) et le bloc `D.DOCUMENTS` de `assets/js/data.js`. Limite à dire : une fiche RBAC corrigée à chaud par
 * l'administrateur dans « Rôles & permissions » n'est PAS lue ici (la matrice d'origine fait foi côté serveur) ; la porter côté serveur est le pas suivant du CLAUDE.md.
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '..');
const REPO = path.resolve(ROOT, '..');

function documents() {
  const src = fs.readFileSync(path.join(ROOT, 'assets/js/data.js'), 'utf8');
  const a = src.indexOf('  var DOCUMENTS = {');
  const b = src.indexOf('DOCUMENTS.abrege');
  if (a < 0 || b < 0) throw new Error('bloc D.DOCUMENTS introuvable dans data.js');
  const fin = src.indexOf('\n', b);
  return new Function(src.slice(a, fin) + '\nreturn DOCUMENTS;')();
}

function construire() {
  const D = documents();
  const rbac = JSON.parse(fs.readFileSync(path.join(REPO, 'packages/rbac/data/rbac.json'), 'utf8'));
  const roles = {};
  Object.keys(rbac.parRole).sort().forEach((role) => {
    const e = rbac.parRole[role] || {};
    const droit = (ecran) => { const x = e[ecran]; return x ? [x[0] ? 1 : 0, x[1] ? 1 : 0, x[2] ? 1 : 0] : [0, 0, 0]; };
    const entree = { courrier: droit('m13-courriers'), patient: droit('m1-documents') };
    if (entree.courrier.concat(entree.patient).some(Boolean)) roles[role] = entree;
  });
  const types = {};
  D.TYPES_PATIENT.forEach((t) => { types[t.libelle] = t.zone; });
  return {
    _doc: 'ENGENDRÉ par prototype_html/build/gen-regles-fichiers.js : ne pas éditer. Règle par famille de api/fichiers.php. roles[rôle][famille] = [voir, éditer, annuler] lus de packages/rbac/data/rbac.json (matrice d\'origine) ; zone2 = profils qui lisent les types de zone 2 (D.DOCUMENTS.ROLES_ZONE_2) ; types = zone de chaque type de document du patient.',
    familles: { courrier: 'm13-courriers', patient: 'm1-documents' },
    roles: roles,
    zone2: D.ROLES_ZONE_2.slice(),
    types: types,
    formats: D.FORMATS.map((f) => ({ id: f.id, mime: f.mime, ext: f.ext, familles: f.familles })),
    tailleDefaut: D.TAILLE_DEFAUT, taillePlancher: D.TAILLE_PLANCHER, taillePlafond: D.TAILLE_PLAFOND,
  };
}

if (require.main === module) {
  const sortie = path.join(ROOT, 'api/regles-fichiers.json');
  const texte = JSON.stringify(construire(), null, 1).replace(/\[\s+([\d,\s]+?)\s+\]/g, (m, x) => '[' + x.replace(/\s+/g, '') + ']') + '\n';
  if (process.argv.includes('--verifier')) {
    const actuel = fs.existsSync(sortie) ? fs.readFileSync(sortie, 'utf8') : '';
    if (actuel !== texte) { console.error('api/regles-fichiers.json est en retard sur rbac.json ou data.js : lancer node build/gen-regles-fichiers.js'); process.exit(1); }
    console.log('api/regles-fichiers.json à jour.');
  } else {
    fs.writeFileSync(sortie, texte);
    console.log('  écrit : prototype_html/api/regles-fichiers.json');
  }
}
module.exports = { construire };
