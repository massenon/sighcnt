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

console.log(`\nFichiers analysés : ${files.length}`);
console.log(erreurs === 0 ? 'Syntaxe : CONFORME' : `Syntaxe : ${erreurs} fichier(s) en erreur`);
process.exit(erreurs === 0 ? 0 : 1);
