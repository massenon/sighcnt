/* =============================================================================
 * Contrôle syntaxique des sources JavaScript
 * -----------------------------------------------------------------------------
 * Passe chaque fichier au vérificateur de syntaxe de Node avant le build, afin
 * qu'une erreur d'écriture ne parvienne jamais jusqu'au navigateur.
 *     node build/lint.js
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');

function walk(dir, out = []) {
  for (const name of fs.readdirSync(dir)) {
    const full = path.join(dir, name);
    if (fs.statSync(full).isDirectory()) { if (name !== 'vendor' && name !== 'node_modules') walk(full, out); }
    else if (name.endsWith('.js')) out.push(full);
  }
  return out;
}

const files = walk(path.join(ROOT, 'assets/js')).concat(walk(path.join(ROOT, 'build')));
let erreurs = 0;

for (const f of files) {
  try {
    execFileSync(process.execPath, ['--check', f], { stdio: 'pipe' });
  } catch (e) {
    erreurs++;
    const msg = (e.stderr || e.stdout || '').toString().split('\n').slice(0, 6).join('\n');
    console.error(`\n✗ ${path.relative(ROOT, f)}\n${msg}`);
  }
}

/* LOT TFIN (T7) : aucune lecture directe d'une ancienne liste de prix (D.ANALYSES, D.TYPES_CHAMBRE, D.CATALOGUE) hors amorçage. */
{
  const fautes = require('./garde-listes-prix.js').analyser(path.join(ROOT, 'assets/js'));
  fautes.forEach((x) => { erreurs++; console.error(`\n✗ ${x.fichier}:${x.ligne} lecture directe de D.${x.liste} (${x.lecture}) : le prix se lit par PR.prixAnalyseALaDate, PR.prixChambreALaDate, PR.prixActeALaDate`); });
}

/* LOT CLO (C1) : aucun NOUVEAU nom de rôle écrit en dur dans un moteur ou un écran (liste blanche décroissante, PRD M12 clôture annuelle EF-DRO-2). */
{
  const r = require('./garde-roles-en-dur.js').analyser(path.join(ROOT, 'assets/js'));
  r.nouveaux.forEach((x) => { erreurs++; console.error(`\n✗ ${x.fichier}:${x.lignes.join(',')} rôle écrit en dur ${x.texte} (${x.n} > ${x.max}) : le droit se lit de la matrice (geste réservé) ou d'un réglage`); });
  r.disparus.forEach((x) => { erreurs++; console.error(`\n✗ ${x.fichier} site disparu ${x.texte} : abaisser la liste (node build/garde-roles-en-dur.js --abaisser)`); });
}

/* LOT EXP : aucun tableau sans cases ni « Exporter » (composant commun, encarts, tableaux à la main équipés ou inscrits avec leur nature et leur motif). */
{
  const r = require('./garde-tableaux.js').analyser(path.join(ROOT, 'assets/js'));
  r.fautes.forEach((x) => { erreurs++; console.error(`\n✗ garde des tableaux : ${x}`); });
}

console.log(`\nFichiers analysés : ${files.length}`);
console.log(erreurs === 0 ? 'Syntaxe : CONFORME' : `Syntaxe : ${erreurs} fichier(s) en erreur`);
process.exit(erreurs === 0 ? 0 : 1);
