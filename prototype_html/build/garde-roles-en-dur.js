/* =============================================================================
 * GARDE DE GÉNÉRATION : AUCUN NOUVEAU NOM DE RÔLE ÉCRIT EN DUR DANS UN MOTEUR OU UN ÉCRAN (PRD M12 clôture annuelle, EF-DRO-2 ; lot CLO C1)
 * -----------------------------------------------------------------------------
 *   node build/garde-roles-en-dur.js [racine des scripts]      (lancée par `npm run lint`)
 *   node build/garde-roles-en-dur.js --abaisser                (réécrit la liste blanche, SEULEMENT vers le bas)
 *
 * Règle de la Direction (11/11/2026, Q1) : ce qu'un profil voit ou peut faire ne se décide jamais par un nom de rôle écrit dans le code : cela vient de la matrice des droits ou d'un
 * réglage enregistré en base. La garde compte, dans assets/js (HORS `nav.js`, qui est le manifeste des droits d'origine, et `data*.js`, qui sont des semences), deux formes de rôle écrit en dur :
 *   (a) un tableau littéral dont TOUS les éléments sont des identifiants de rôle (`['da', 'direction', 'admin']`), quel qu'en soit l'usage ;
 *   (b) une comparaison d'un rôle à un identifiant (`role === 'comptable'`, `roleCourant() === 'admin'`, `.role == 'da'`).
 * Les identifiants de rôle sont LUS de `packages/rbac/data/rbac.json` (jamais recopiés ici). Chaque site existant est inscrit dans `garde-roles-en-dur.liste.json` (fichier, texte normalisé,
 * nombre) : la liste ne peut que DÉCROÎTRE. Un site nouveau (ou un site de plus avec le même texte) fait échouer la garde ; un site disparu aussi (il faut alors abaisser la liste, pour que
 * le plafond suive la migration). On migre les sites à la pièce, par risque : clôture d'abord (liste vide pour M12 clôture), puis le reste.
 * Sortie : code 0 si la liste est exacte, 1 avec le détail.
 * ========================================================================== */
'use strict';
const fs = require('fs'), path = require('path');
const RACINE = path.resolve(process.argv.find((a, i) => i > 1 && !a.startsWith('--')) || path.join(__dirname, '..', 'assets', 'js'));
const LISTE = path.join(__dirname, 'garde-roles-en-dur.liste.json');
const REGLES = path.resolve(__dirname, '..', '..', 'packages', 'rbac', 'data', 'rbac.json');

function roles() { return Object.keys(JSON.parse(fs.readFileSync(REGLES, 'utf8')).gestes.parRole); }
function fichiers(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => e.isDirectory() ? fichiers(path.join(dir, e.name)) : /\.js$/.test(e.name) ? [path.join(dir, e.name)] : []);
}
const EXCLUS = (f, racine) => path.dirname(f) === racine && (path.basename(f) === 'nav.js' || /^data[-.\w]*\.js$/.test(path.basename(f)));
function sites(racine) {
  const alt = roles().map((r) => r.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|');
  const tableau = new RegExp("\\[\\s*'(?:" + alt + ")'(?:\\s*,\\s*'(?:" + alt + ")')*\\s*\\]", 'g');
  const compare = new RegExp("(?:\\brole\\b|roleCourant\\(\\)|\\.role|\\bsession\\.role)\\s*[!=]==?\\s*'(?:" + alt + ")'", 'g');
  const out = {};
  for (const f of fichiers(racine)) {
    if (EXCLUS(f, racine)) continue;
    const brut = fs.readFileSync(f, 'utf8');
    /* Les commentaires ne sont pas du code : leur texte est blanchi (les sauts de ligne restent). */
    const src = brut.replace(/\/\*[\s\S]*?\*\//g, (c) => c.replace(/[^\n]/g, ' ')).replace(/(^|[^:\\'"`])\/\/[^\n]*/g, (c, a) => a + ' '.repeat(c.length - a.length));
    const rel = path.relative(path.dirname(racine), f).replace(/\\/g, '/');
    for (const re of [tableau, compare]) {
      let m; re.lastIndex = 0;
      while ((m = re.exec(src))) {
        const texte = m[0].replace(/\s+/g, ' ');
        const ligne = src.slice(0, m.index).split('\n').length;
        ((out[rel] = out[rel] || {})[texte] = out[rel][texte] || { n: 0, lignes: [] });
        out[rel][texte].n++; out[rel][texte].lignes.push(ligne);
      }
    }
  }
  return out;
}
/** { nouveaux: [{fichier, texte, n, max, lignes}], disparus: [{fichier, texte, n, max}] } contre la liste blanche. */
function analyser(racine, liste) {
  const trouves = sites(racine || RACINE), permis = liste || JSON.parse(fs.readFileSync(LISTE, 'utf8')).sites;
  const nouveaux = [], disparus = [];
  Object.keys(trouves).forEach((f) => Object.keys(trouves[f]).forEach((t) => {
    const max = (permis[f] && permis[f][t]) || 0;
    if (trouves[f][t].n > max) nouveaux.push({ fichier: f, texte: t, n: trouves[f][t].n, max: max, lignes: trouves[f][t].lignes });
  }));
  Object.keys(permis).forEach((f) => Object.keys(permis[f]).forEach((t) => {
    const n = (trouves[f] && trouves[f][t] && trouves[f][t].n) || 0;
    if (n < permis[f][t]) disparus.push({ fichier: f, texte: t, n: n, max: permis[f][t] });
  }));
  return { nouveaux, disparus, total: Object.keys(trouves).reduce((s, f) => s + Object.keys(trouves[f]).reduce((a, t) => a + trouves[f][t].n, 0), 0) };
}
function abaisser(racine) {
  const trouves = sites(racine || RACINE), cur = JSON.parse(fs.readFileSync(LISTE, 'utf8'));
  const r = analyser(racine, cur.sites);
  if (r.nouveaux.length) throw new Error('Refus : la liste blanche ne s\'écrit que vers le bas, ' + r.nouveaux.length + ' site(s) nouveau(x).');
  const sites2 = {};
  Object.keys(trouves).forEach((f) => Object.keys(trouves[f]).forEach((t) => { (sites2[f] = sites2[f] || {})[t] = trouves[f][t].n; }));
  fs.writeFileSync(LISTE, JSON.stringify({ _doc: cur._doc, sites: sites2 }, null, 1) + '\n');
}
if (require.main === module) {
  if (process.argv.includes('--initialiser')) {
    const t = sites(RACINE), s = {};
    Object.keys(t).forEach((f) => Object.keys(t[f]).forEach((x) => { (s[f] = s[f] || {})[x] = t[f][x].n; }));
    fs.writeFileSync(LISTE, JSON.stringify({ _doc: 'ENGENDRÉE par build/garde-roles-en-dur.js --initialiser puis --abaisser : liste blanche DÉCROISSANTE des rôles écrits en dur (PRD M12 clôture annuelle, EF-DRO-2). Ne s\'écrit que vers le bas.', sites: s }, null, 1) + '\n');
    console.log('Liste initialisée : ' + Object.keys(s).length + ' fichier(s).');
  } else if (process.argv.includes('--abaisser')) { abaisser(); console.log('Liste abaissée.'); }
  else {
    const r = analyser(RACINE);
    if (r.nouveaux.length || r.disparus.length) {
      r.nouveaux.forEach((x) => console.error('GARDE RÔLES EN DUR : site NOUVEAU ' + x.fichier + ':' + x.lignes.join(',') + '  ' + x.texte + '  (' + x.n + ' > ' + x.max + ') : le droit se lit de la matrice (geste réservé) ou d\'un réglage, jamais d\'un nom de rôle écrit dans le code.'));
      r.disparus.forEach((x) => console.error('GARDE RÔLES EN DUR : site DISPARU ' + x.fichier + '  ' + x.texte + '  (' + x.n + ' < ' + x.max + ') : abaisser la liste (node build/garde-roles-en-dur.js --abaisser).'));
      process.exit(1);
    }
    console.log('Garde des rôles en dur : ' + r.total + ' site(s) inscrits à la liste blanche, 0 nouveau.');
  }
}
module.exports = { analyser, sites, abaisser };
