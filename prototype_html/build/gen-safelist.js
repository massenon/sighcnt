/* =============================================================================
 * Générateur de liste blanche Tailwind
 * -----------------------------------------------------------------------------
 * L'essentiel de l'interface est construit en JavaScript : les classes n'y
 * apparaissent pas sous la forme `class="…"` que l'extracteur de Tailwind sait
 * reconnaître (sélecteurs pointés, échappements, concaténations dynamiques).
 * Ce script relit les sources JS, reconstitue les classes réellement produites
 * et les dépose dans build/safelist.html, que Tailwind scanne comme un fichier
 * ordinaire. Relancer avant chaque build CSS :
 *     node build/gen-safelist.js && npm run css
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const JS_DIRS = [path.join(ROOT, 'assets/js')];

/* --- Collecte des fichiers JS (hors bibliothèques vendorées) -------------- */
function walk(dir, out = []) {
  for (const name of fs.readdirSync(dir)) {
    const full = path.join(dir, name);
    const st = fs.statSync(full);
    if (st.isDirectory()) { if (name !== 'vendor') walk(full, out); }
    else if (name.endsWith('.js')) out.push(full);
  }
  return out;
}

/* --- Découpage identique à celui de core.js : splitSpec() ----------------- */
function splitSpec(spec) {
  const parts = []; let buf = '';
  for (let i = 0; i < spec.length; i++) {
    const ch = spec[i];
    if (ch === '\\' && i + 1 < spec.length) { buf += spec[i + 1]; i++; continue; }
    if (ch === '.' || ch === '#') { parts.push(buf); buf = ch; continue; }
    buf += ch;
  }
  parts.push(buf);
  return parts.filter(Boolean);
}

const tokens = new Set();

function addCandidate(raw) {
  if (!raw || raw.length > 200) return;
  /* Le texte du fichier porte les échappements du littéral JavaScript :
     `w-\\[17rem\\]` dans la source vaut `w-\[17rem\]` à l'exécution. On
     déroule d'abord ce niveau pour retrouver la chaîne que verra core.js. */
  const js = raw.replace(/\\\\/g, '\\');

  /* a) découpage par espaces (attribut class="a b c") */
  for (const t of js.split(/\s+/)) {
    const clean = t.replace(/\\(.)/g, '$1').trim();
    if (clean && /^[a-z0-9]/i.test(clean)) tokens.add(clean);
  }
  /* b) découpage par points (sélecteur pointé de el()) */
  if (js.includes('.')) {
    for (const p of splitSpec(js)) {
      if (p[0] === '.') { const c = p.slice(1).trim(); if (c) tokens.add(c); }
    }
  }
}

/* --- Extraction de toutes les chaînes littérales --------------------------
 * Les commentaires sont retirés au préalable : une apostrophe française isolée
 * (« l'écran », « d'Ariane ») y désynchroniserait le balayage des chaînes et
 * ferait disparaître silencieusement toutes les classes suivantes.
 * ---------------------------------------------------------------------- */
const files = JS_DIRS.flatMap((d) => (fs.existsSync(d) ? walk(d) : []));
const STRING_RE = /'((?:[^'\\\n]|\\.)*)'|"((?:[^"\\\n]|\\.)*)"/g;

function stripComments(src) {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, ' ')   // commentaires de bloc
    .replace(/(^|[^:'"\\])\/\/[^\n]*/g, '$1'); // commentaires de ligne (hors URL)
}

for (const file of files) {
  const src = stripComments(fs.readFileSync(file, 'utf8'));
  let m;
  while ((m = STRING_RE.exec(src)) !== null) addCandidate(m[1] != null ? m[1] : m[2]);
}

/* --- Classes assemblées dynamiquement ------------------------------------ */
const TONES = ['navy', 'success', 'warning', 'danger', 'info', 'slate', 'neutral'];
const SHADES = ['50', '100', '200', '300', '400', '500', '600', '700', '800', '900', '950'];
const dynamic = [];

for (const t of TONES) {
  for (const s of SHADES) {
    dynamic.push(`bg-${t}-${s}`, `text-${t}-${s}`, `border-${t}-${s}`, `ring-${t}-${s}`);
  }
  dynamic.push(`badge-${t}`, `btn-${t}`);
}
dynamic.push(
  'badge-neutral', 'badge-navy', 'badge-success', 'badge-warning', 'badge-danger', 'badge-info',
  'btn-primary', 'btn-secondary', 'btn-ghost', 'btn-success', 'btn-warning', 'btn-danger',
  'btn-sm', 'btn-lg', 'btn-icon', 'nav-link-active', 'tab-active', 'input-error',
  'grid-cols-1', 'grid-cols-2', 'grid-cols-3', 'grid-cols-4', 'grid-cols-5', 'grid-cols-6',
  'grid-cols-7', 'grid-cols-8', 'grid-cols-12',
  'sm:grid-cols-2', 'sm:grid-cols-3', 'sm:grid-cols-4',
  'md:grid-cols-2', 'md:grid-cols-3', 'md:grid-cols-4',
  'lg:grid-cols-2', 'lg:grid-cols-3', 'lg:grid-cols-4', 'lg:grid-cols-5', 'lg:grid-cols-6',
  'col-span-1', 'col-span-2', 'col-span-3', 'col-span-4', 'sm:col-span-2', 'lg:col-span-2', 'lg:col-span-3',
  'text-left', 'text-right', 'text-center', 'whitespace-nowrap', 'num',
  'bg-slate-50', 'bg-slate-100', 'bg-white', 'hidden', 'block', 'flex',
);
dynamic.forEach((c) => tokens.add(c));

/* --- Écriture ------------------------------------------------------------ */
const list = [...tokens].sort();
const out = `<!-- Fichier généré par build/gen-safelist.js — NE PAS ÉDITER À LA MAIN.
     Recense les classes produites dynamiquement par le JavaScript afin que
     Tailwind les conserve lors du build. -->
<div class="${list.join(' ')}"></div>
`;
fs.mkdirSync(path.join(ROOT, 'build'), { recursive: true });
fs.writeFileSync(path.join(ROOT, 'build/safelist.html'), out);

console.log(`Fichiers JS analysés : ${files.length}`);
console.log(`Classes candidates   : ${list.length}`);
