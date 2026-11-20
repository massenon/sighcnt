/* =============================================================================
 * GARDE DE GÉNÉRATION : AUCUNE LECTURE DIRECTE D'UNE ANCIENNE LISTE DE PRIX (PRD-TARIFS, lot T7 / TFIN)
 * -----------------------------------------------------------------------------
 *   node build/garde-listes-prix.js [racine des scripts]       (lancée par `npm run lint`)
 *
 * `D.ANALYSES`, `D.TYPES_CHAMBRE` et `D.CATALOGUE` ne sont plus que la SEMENCE du référentiel de prix unique : leur prix (`prix`, `tarif`, `prixNonAssure`, `prixAssure`) est celui d'ORIGINE,
 * figé. Le lire hors amorçage, c'est facturer ou afficher un prix périmé en silence. Le prix se lit par `PR.prixAnalyseALaDate`, `PR.prixChambreALaDate`, `PR.prixActeALaDate`,
 * `PR.tarifALaDate` (ou `D.TARIFS.semence.*` pour un amorçage, ligne marquée `garde-prix`).
 *
 * Règle : pour chaque mention de ces trois listes dans assets/js (hors les fichiers data*.js, qui les DÉFINISSENT), la phrase qui la porte (jusqu'à la fin de l'expression, chaîne `.filter(...)[0].tarif`
 * comprise) ne doit pas lire une propriété de prix. Une ligne marquée `garde-prix` (amorçage) est admise ; une mention sans lecture de prix (désignation, code, effectif) est admise.
 * Sortie : code 0 si propre, 1 avec la liste « fichier:ligne ».
 * ========================================================================== */
'use strict';
const fs = require('fs'), path = require('path');
const RACINE = path.resolve(process.argv[2] || path.join(__dirname, '..', 'assets', 'js'));
const LISTES = /\b(?:D|data)\.(ANALYSES|TYPES_CHAMBRE|CATALOGUE)\b(?!_)/g;
const PRIX = /\.(prix|tarif|prixNonAssure|prixAssure)\b/;

function fichiers(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => e.isDirectory() ? fichiers(path.join(dir, e.name)) : /\.js$/.test(e.name) ? [path.join(dir, e.name)] : []);
}
/* La phrase qui commence en `debut` : jusqu'à la fin de l'expression, une chaîne `.x` ou `[i]` qui suit une parenthèse fermée faisant partie de la phrase. */
function phrase(src, debut) {
  let prof = 0, i = debut;
  for (; i < src.length; i++) {
    const c = src[i];
    if ('([{'.includes(c)) prof++;
    else if (')]}'.includes(c)) { prof--; if (prof < 0) break; if (prof === 0 && !/^\s*(?:\.|\[)/.test(src.slice(i + 1, i + 4))) { i++; break; } }
    else if (prof === 0 && (c === ';' || c === ',' || c === '\n')) break;
  }
  return src.slice(debut, i);
}
function analyser(racine) {
  const fautes = [];
  for (const f of fichiers(racine)) {
    if (/^data[-.\w]*\.js$/.test(path.basename(f)) && path.dirname(f) === racine) continue;
    /* Les commentaires ne sont pas du code : leur texte est blanchi (les sauts de ligne restent). */
    const brut = fs.readFileSync(f, 'utf8'), lignesBrutes = brut.split('\n');
    const src = brut.replace(/\/\*[\s\S]*?\*\//g, (c) => c.replace(/[^\n]/g, ' ')).replace(/(^|[^:\\'"`])\/\/[^\n]*/g, (c, a) => a + ' '.repeat(c.length - a.length));
    const ligneDe = (n) => src.slice(0, n).split('\n').length;
    let m; LISTES.lastIndex = 0;
    while ((m = LISTES.exec(src))) {
      const ligne = ligneDe(m.index), txt = src.split('\n')[ligne - 1];
      if (/garde-prix/.test(lignesBrutes[ligne - 1])) continue;
      /* `(D.X || [])` : la phrase commence à la parenthèse ouvrante. */
      let debut = m.index; { let k = debut - 1; while (k >= 0 && /\s/.test(src[k])) k--; if (src[k] === '(') debut = k; }
      let p = phrase(src, debut);
      /* Affectée à une variable (`var a = D.ANALYSES.filter(...)[0]`) : ce que les quatorze lignes suivantes font de cette variable compte aussi. */
      const aff = src.slice(Math.max(0, src.lastIndexOf('\n', m.index) + 1), m.index).match(/(?:var|let|const)\s+(\w+)\s*=\s*$/);
      let lu = p.match(PRIX);
      if (aff && !lu) {
        /* jusqu'à la sortie de la fonction qui porte l'affectation (indentation moindre) ou une redéclaration de la variable */
        const lignes = src.split('\n'), ind = (txt.match(/^\s*/) || [''])[0].length, v = aff[1];
        const re = new RegExp('\\b' + v + '\\.(prix|tarif|prixNonAssure|prixAssure)\\b');
        for (let k = ligne; k < Math.min(lignes.length, ligne + 14); k++) {
          const l = lignes[k];
          if (l.trim() && (l.match(/^\s*/) || [''])[0].length < ind) break;
          if (new RegExp('(?:var|let|const)\\s+' + v + '\\b').test(l)) break;
          const r = l.match(re); if (r) { lu = r; break; }
        }
      }
      if (lu) fautes.push({ fichier: path.relative(path.dirname(racine), f).replace(/\\/g, '/'), ligne, liste: m[1], lecture: lu[0] });
    }
  }
  return fautes;
}
if (require.main === module) {
  const fautes = analyser(RACINE);
  if (fautes.length) {
    console.error('GARDE LISTES DE PRIX : ' + fautes.length + ' lecture(s) directe(s) d\'une ancienne liste de prix (le prix se lit par PR.prixAnalyseALaDate, PR.prixChambreALaDate, PR.prixActeALaDate) :');
    fautes.forEach((x) => console.error('  ' + x.fichier + ':' + x.ligne + ' D.' + x.liste + '  lit  ' + x.lecture));
    process.exit(1);
  }
  console.log('Garde des listes de prix : 0 lecture directe de D.ANALYSES, D.TYPES_CHAMBRE, D.CATALOGUE (' + fichiers(RACINE).length + ' fichiers).');
}
module.exports = { analyser };
