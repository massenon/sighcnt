/* =============================================================================
 * GARDE DE GÉNÉRATION : AUCUN TABLEAU SANS CASES NI SORTIE (lot EXP, PRD des tableaux, critère d'acceptation « aucun tableau de l'application n'est
 * sans case à cocher ni sans bouton Exporter »)
 * -----------------------------------------------------------------------------
 *   node build/garde-tableaux.js [racine des scripts]        (lancée par `npm run lint`)
 *   node build/garde-tableaux.js --inventaire                (énumère tous les tableaux et leur nature)
 *
 * La garde ÉNUMÈRE tous les tableaux construits dans assets/js (hors `vendor/`) : `el('table…')`, `createElement('table')`, une chaîne `<table`.
 * Chaque site doit être, au choix :
 *   (a) ÉQUIPÉ : la variable du tableau est passée à `U.equiperTableau(` dans la même fonction (cases, « Exporter », moteur de sortie commun) ;
 *   (b) INSCRIT à `garde-tableaux.liste.json` avec sa nature et son motif écrit : `composant` (le composant commun lui-même), `saisie` (grille d'un
 *       formulaire en cours : pas encore de lignes à sortir), `document` (le tableau EST la pièce imprimée).
 * Un site ni équipé ni inscrit fait échouer la garde ; un site inscrit qui a disparu aussi (la liste suit le code). Une inscription sans motif aussi.
 * Le composant commun est vérifié À PART : `dataTable` coche par défaut (`selectable: true`) et pose la commande « Exporter » ; `K.miniTable`
 * équipe ses encarts. Enfin aucun écran ne retire les cases d'un tableau commun (`selectable: false`) sans être inscrit à `sansCases`.
 * Clé d’un site : fichier, nom de la dernière fonction nommée qui le précède, rang du tableau sous ce nom (jamais un numéro de ligne).
 * Sortie : code 0 si tout est conforme, 1 avec le détail.
 * ========================================================================== */
'use strict';
const fs = require('fs'), path = require('path');
const RACINE = path.resolve(process.argv.find((a, i) => i > 1 && !a.startsWith('--')) || path.join(__dirname, '..', 'assets', 'js'));
const LISTE = path.join(__dirname, 'garde-tableaux.liste.json');
const NATURES = ['composant', 'saisie', 'document'];

function fichiers(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => e.isDirectory() ? (e.name === 'vendor' ? [] : fichiers(path.join(dir, e.name))) : /\.js$/.test(e.name) ? [path.join(dir, e.name)] : []);
}
/** Les commentaires ne sont pas du code : leur texte est blanchi (les sauts de ligne restent, les numéros de ligne aussi). */
function sansCommentaires(brut) {
  return brut.replace(/\/\*[\s\S]*?\*\//g, (c) => c.replace(/[^\n]/g, ' ')).replace(/(^|[^:\\'"`])\/\/[^\n]*/g, (c, a) => a + ' '.repeat(c.length - a.length));
}
const RE_TABLE = /el\(\s*(['"])table[.#'"\s,)]|createElement\(\s*['"]table['"]\s*\)|<table[\s>]/g;
const RE_FONCTION = /function\s+([A-Za-z_$][\w$]*)\s*\(/g;

function fonctionEnglobante(src, index) {
  let m, nom = '(module)'; RE_FONCTION.lastIndex = 0;
  while ((m = RE_FONCTION.exec(src)) && m.index < index) nom = m[1];
  return nom;
}
/** La variable qui reçoit le tableau (`var t = el('table…')`), si elle existe. */
function variableDe(src, index) {
  const debut = src.lastIndexOf('\n', index) + 1;
  const m = /(?:var|let|const)\s+([A-Za-z_$][\w$]*)\s*=\s*$/.exec(src.slice(debut, index)) || /([A-Za-z_$][\w$]*)\s*=\s*$/.exec(src.slice(debut, index));
  return m ? m[1] : null;
}
function sites(racine) {
  const out = [];
  for (const f of fichiers(racine)) {
    const src = sansCommentaires(fs.readFileSync(f, 'utf8'));
    const rel = path.relative(path.dirname(racine), f).replace(/\\/g, '/');
    const rangs = {}, trouves = [];
    let m; RE_TABLE.lastIndex = 0;
    while ((m = RE_TABLE.exec(src))) trouves.push(m.index);
    trouves.forEach((index, i) => {
      const fonction = fonctionEnglobante(src, index);
      rangs[fonction] = (rangs[fonction] || 0) + 1;
      const variable = variableDe(src, index);
      /* équipé : `equiperTableau(<variable>` après le site, avant le tableau suivant du fichier et dans les 150 lignes qui suivent */
      let fin = i + 1 < trouves.length ? trouves[i + 1] : src.length;
      const lignes150 = src.slice(index).split('\n').slice(0, 150).join('\n').length;
      fin = Math.min(fin, index + lignes150);
      const re = variable ? new RegExp('equiperTableau\\(\\s*' + variable.replace(/\$/g, '\\$') + '\\b') : null;
      const equipe = !!(re && re.test(src.slice(index, fin)));
      out.push({ fichier: rel, fonction, rang: rangs[fonction], variable, equipe, ligne: src.slice(0, index).split('\n').length });
    });
  }
  return out;
}
function cle(s) { return s.fichier + '#' + s.fonction + '#' + s.rang; }
function lireListe() { return JSON.parse(fs.readFileSync(LISTE, 'utf8')); }
/** { fautes: [texte], inventaire: {equipes, inscrits par nature, total} } */
function analyser(racine, liste) {
  racine = racine || RACINE;
  const l = liste || lireListe();
  const inscrits = {};
  (l.sites || []).forEach((x) => { inscrits[x.fichier + '#' + x.fonction + '#' + x.rang] = x; });
  const fautes = [], vus = {}, parNature = { equipe: 0 };
  NATURES.forEach((n) => { parNature[n] = 0; });
  for (const s of sites(racine)) {
    const k = cle(s); vus[k] = true;
    const ins = inscrits[k];
    if (s.equipe) {
      parNature.equipe++;
      if (ins) fautes.push(`${s.fichier}:${s.ligne} (${s.fonction}, rang ${s.rang}) est ÉQUIPÉ et encore inscrit comme « ${ins.nature} » : retirer l'inscription`);
      continue;
    }
    if (!ins) { fautes.push(`${s.fichier}:${s.ligne} (${s.fonction}, rang ${s.rang}) : tableau SANS cases ni « Exporter » : passer par U.dataTable, l'équiper (U.equiperTableau) ou l'inscrire avec sa nature et son motif`); continue; }
    if (NATURES.indexOf(ins.nature) < 0) fautes.push(`${k} : nature « ${ins.nature} » inconnue (${NATURES.join(', ')})`);
    else if (!String(ins.motif || '').trim()) fautes.push(`${k} : inscription sans motif écrit`);
    else parNature[ins.nature]++;
  }
  Object.keys(inscrits).forEach((k) => { if (!vus[k]) fautes.push(`${k} : site inscrit DISPARU du code : retirer l'inscription`); });

  /* Le composant commun et l'encart */
  const ui = fs.readFileSync(path.join(racine, 'ui.js'), 'utf8');
  const corpsDataTable = (ui.split('function dataTable(config)')[1] || '').split('\n  function ')[0];
  if (!/selectable:\s*true\b/.test(corpsDataTable.slice(0, 600))) fautes.push('ui.js : dataTable ne coche plus par défaut (selectable: true attendu dans ses valeurs par défaut)');
  if (!/fenetreSortie\(/.test(corpsDataTable) || !/commande:\s*'exporter'/.test(corpsDataTable)) fautes.push('ui.js : dataTable ne pose plus la commande « Exporter » (fenetreSortie)');
  const kit = fs.readFileSync(path.join(racine, 'modules', '_kit.js'), 'utf8');
  const corpsMini = (kit.split('function miniTable(')[1] || '').split('\n  function ')[0];
  if (!/equiperTableau\(/.test(corpsMini)) fautes.push('_kit.js : K.miniTable n\'équipe plus ses encarts (U.equiperTableau attendu)');

  /* Aucun écran ne retire les cases d'un tableau commun sans être inscrit */
  const sansCases = {};
  (l.sansCases || []).forEach((x) => { sansCases[x.fichier] = (sansCases[x.fichier] || 0) + (x.n || 1); });
  for (const f of fichiers(racine)) {
    const rel = path.relative(path.dirname(racine), f).replace(/\\/g, '/');
    const n = (sansCommentaires(fs.readFileSync(f, 'utf8')).match(/selectable:\s*false\b/g) || []).length;
    if (n > (sansCases[rel] || 0)) fautes.push(`${rel} : ${n} tableau(x) commun(s) sans cases (selectable: false), ${sansCases[rel] || 0} inscrit(s) à « sansCases »`);
  }
  const total = Object.keys(vus).length;
  return { fautes, inventaire: Object.assign({ total }, parNature) };
}
if (require.main === module) {
  const r = analyser(RACINE);
  if (process.argv.includes('--inventaire')) {
    const l = lireListe(), ins = {};
    (l.sites || []).forEach((x) => { ins[x.fichier + '#' + x.fonction + '#' + x.rang] = x; });
    sites(RACINE).forEach((s) => console.log([s.fichier + ':' + s.ligne, s.fonction, 'rang ' + s.rang, s.equipe ? 'équipé' : (ins[cle(s)] ? ins[cle(s)].nature : 'NON TRAITÉ')].join('  ')));
  }
  if (r.fautes.length) { r.fautes.forEach((x) => console.error('GARDE TABLEAUX : ' + x)); process.exit(1); }
  console.log('Garde des tableaux : ' + r.inventaire.total + ' tableau(x) construit(s) hors composant, ' + r.inventaire.equipe + ' équipé(s), '
    + NATURES.map((n) => r.inventaire[n] + ' ' + n).join(', ') + ' (inscrits avec motif) ; composant commun et encarts conformes.');
}
module.exports = { analyser, sites };
