/* =============================================================================
 * Générateur des pages HTML du prototype SIGH-CNT
 * -----------------------------------------------------------------------------
 * Chaque page est engendrée à partir du manifeste assets/js/nav.js : la coquille
 * HTML est donc rigoureusement identique partout et tous les liens restent
 * cohérents. Relancer après toute modification du manifeste :
 *     node build/gen-pages.js
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');

/* --- Chargement du manifeste dans un contexte minimal --------------------- */
const sandbox = { SIGH: {} };
new Function('window', fs.readFileSync(path.join(ROOT, 'assets/js/nav.js'), 'utf8'))(sandbox);
const NAV = sandbox.SIGH.nav;

/* --- Association module → fichier de rendu ------------------------------- */
const MODULE_FILES = {
  DASH: 'dashboards', PIL: 'dashboards', M1: 'm1-patients', M2: 'm2-consultations', M3: 'm3-hospitalisation',
  M4: 'm4-maternite', M5: 'm5-laboratoire', M6: 'm6-stock', M7: 'm7-achats',
  M8: 'm8-facturation', M9: 'm9-assurances', MECEF: 'mecef', M12: 'm12-comptabilite',
  M10: 'm10-rh', M11: 'm11-paie', M13: 'm13-administration', GED: 'ged',
  RAP: 'rapports', MERE: 'mere', RLS: 'relais', M14: 'm14-securite', CFG: 'configuration', AUTH: 'auth', SUP: 'support',
};

const SCRIPTS = [
  'vendor/lucide.min.js', 'vendor/chart.umd.min.js', 'vendor/lz-string.min.js', 'vendor/qr.js',
  'core.js', 'data-compta.js', 'data-sage.js', 'data-labo.js', 'data.js', 'data-tarifs.js', 'data-clinique.js', 'data-imagerie.js', 'data-dossier.js', 'data-maternite.js', 'data-liasse.js', 'store.js', 'parcours.js', 'ui.js', 'charts.js', 'print.js', 'nav.js', 'notifications.js', 'app.js', 'data-seed.js',
  'modules/_kit.js',
];

function esc(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function template(entry, opts) {
  const o = opts || {};
  const depth = o.root ? '' : '../';
  const mod = MODULE_FILES[entry.module];
  const scripts = SCRIPTS.map((s) => `  <script src="${depth}assets/js/${s}"></script>`);
  if (mod) scripts.push(`  <script src="${depth}assets/js/modules/${mod}.js"></script>`);

  return `<!doctype html>
<html lang="fr" data-root="${depth}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="${esc(entry.moduleLabel)} — Système Intégré de Gestion Hospitalière de la Clinique NASSIERA TOO SARL.">
  <title>${esc(entry.label)} — SIGH Clinique NASSIERA TOO</title>
  <link rel="icon" href="${depth}assets/img/logo.jpeg">
  <link rel="stylesheet" href="${depth}assets/css/tailwind.css">
</head>
<body class="min-h-screen bg-slate-100">
${scripts.join('\n')}
  <script>SIGH.mount(${JSON.stringify(entry.id)});</script>
</body>
</html>
`;
}

/* --- Génération ----------------------------------------------------------
 * L'EXTENSION VIENT DU MANIFESTE (`NAV.EXT`), jamais d'ici : le générateur
 * et les liens doivent la lire au même endroit, faute de quoi on engendrerait
 * des pages que les href ne visent pas.
 * ------------------------------------------------------------------------ */
const EXT = NAV.EXT || '.html';
const pagesDir = path.join(ROOT, 'pages');
fs.mkdirSync(pagesDir, { recursive: true });

let created = 0, kept = 0;
const written = new Set();

/* GARDE : un écran désigné comme `servant` doit exister. `m6-inventaires` (pluriel) n'a jamais existé ; la feuille
   d'inventaire héritait donc des droits du MODULE au lieu de ceux du registre qu'elle alimente, sans que rien ne le dise. */
Object.keys(NAV.INDEX).forEach((id) => {
  const s = NAV.INDEX[id].servant;
  if (s && !NAV.INDEX[s]) throw new Error('Manifeste : « ' + id + ' » déclare servant « ' + s + ' », qui n\'existe pas.');
});

Object.keys(NAV.INDEX).forEach((id) => {
  const entry = NAV.INDEX[id];
  if (id === 'index') return; /* la page de connexion est écrite à la main */
  const file = path.join(pagesDir, id + EXT);
  const html = template(entry, {});
  written.add(id + EXT);
  const existing = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null;
  if (existing === html) { kept++; return; }
  fs.writeFileSync(file, html);
  created++;
});

/* --- Détection des pages orphelines --------------------------------------
 * Les pages de l'ancienne extension sont RETIRÉES, et non laissées à côté :
 * deux jeux de pages côte à côte, c'est une adresse sur deux qui ouvre une
 * version figée du jour du changement — et rien ne le dirait.
 * ------------------------------------------------------------------------ */
const anciennes = fs.readdirSync(pagesDir).filter((f) => f.endsWith('.html') && EXT !== '.html');
anciennes.forEach((f) => fs.unlinkSync(path.join(pagesDir, f)));
if (anciennes.length) console.log(`Pages de l'ancienne extension retirées : ${anciennes.length}`);
const orphans = fs.readdirSync(pagesDir).filter((f) => f.endsWith(EXT) && !written.has(f));

console.log(`Pages générées/mises à jour : ${created}`);
console.log(`Pages inchangées            : ${kept}`);
console.log(`Total au manifeste          : ${written.size}`);
if (orphans.length) console.log(`Pages orphelines (hors manifeste) : ${orphans.join(', ')}`);


/* --- Garde : la page de connexion doit porter les mêmes scripts ----------
   Elle est écrite à la main ; elle a déjà divergé une fois (13 scripts sur 24
   — un premier survol à froid semait le magasin et cassait sur L.EXAMENS).
   Le build échoue si elle diverge encore. */
const pageIndex = 'index' + EXT;
const cheminIndex = path.join(__dirname, '..', pageIndex);
if (!fs.existsSync(cheminIndex)) {
  console.error('ERREUR — ' + pageIndex + ' est introuvable à la racine du prototype.');
  process.exit(1);
}
const indexHtml = fs.readFileSync(cheminIndex, 'utf8');
const manquants = SCRIPTS.filter((s) => indexHtml.indexOf('assets/js/' + s) === -1);
if (manquants.length) {
  console.error('ERREUR — ' + pageIndex + ' ne charge pas : ' + manquants.join(', '));
  console.error('La page de connexion doit porter la même liste SCRIPTS que les pages générées.');
  process.exit(1);
}
console.log(pageIndex + ' : scripts alignés sur SCRIPTS (' + SCRIPTS.length + ').');