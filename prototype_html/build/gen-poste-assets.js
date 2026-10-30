/* Copie les données ENGENDRÉES dont l'application Flutter a besoin (manifeste de navigation, matrice des droits) et
   engendre la table des icônes Lucide. Rien n'est écrit à la main : lancer après `node build/extraire.js rbac`.
     node build/gen-poste-assets.js */
'use strict';
const fs = require('fs'), path = require('path');
const REPO = path.resolve(__dirname, '..', '..');
const POSTE = path.join(REPO, 'apps', 'poste');
fs.mkdirSync(path.join(POSTE, 'assets', 'donnees'), { recursive: true });
for (const [src, dst] of [['packages/referentiels/data/manifeste.json', 'manifeste.json'], ['packages/rbac/data/rbac.json', 'rbac.json'], ['docs/architecture/parite.json', 'parite.json']]) {
  fs.copyFileSync(path.join(REPO, src), path.join(POSTE, 'assets', 'donnees', dst));
  console.log('  copié : apps/poste/assets/donnees/' + dst);
}
const man = JSON.parse(fs.readFileSync(path.join(REPO, 'packages/referentiels/data/manifeste.json'), 'utf8'));
const noms = new Set(['house', 'search', 'bell', 'maximize', 'chevron-down', 'chevron-up', 'chevron-right', 'sparkles', 'circle', 'map', 'construction', 'lock', 'server', 'monitor', 'wifi', 'wifi-off', 'cloud']);
man.domaines.forEach((d) => d.icone && noms.add(d.icone));
man.modules.forEach((m) => m.icone && noms.add(m.icone));
man.ecrans.forEach((e) => e.icone && noms.add(e.icone));
/* Le paquet Flutter nomme les icônes en lowerCamelCase ; on vérifie l'existence de chacune dans sa source. */
let src = '';
try {
  const cfg = JSON.parse(fs.readFileSync(path.join(POSTE, '.dart_tool', 'package_config.json'), 'utf8'));
  const p = cfg.packages.find((x) => x.name === 'lucide_icons_flutter');
  const racine = decodeURIComponent(new URL(p.rootUri, 'file://' + path.join(POSTE, '.dart_tool', 'package_config.json')).pathname);
  src = fs.readFileSync(path.join(racine, 'lib', 'lucide_icons.dart'), 'utf8');
} catch (e) { console.error('paquet lucide_icons_flutter introuvable : lancer `flutter pub get` dans apps/poste'); process.exit(1); }
const camel = (k) => k.replace(/-([a-z0-9])/g, (_, c) => c.toUpperCase());
const ALIAS = { home: 'house' };
const ok = [], manquants = [];
[...noms].sort().forEach((n) => { const c = camel(ALIAS[n] || n); (new RegExp('static const IconData ' + c + '\\b').test(src) ? ok : manquants).push([n, c]); });
let d = '// ENGENDRÉ par prototype_html/build/gen-poste-assets.js — NE PAS ÉDITER.\n// Les icônes de la maquette (Lucide), par leur nom de la maquette. Une icône inconnue retombe sur « circle ».\nimport \'package:flutter/widgets.dart\';\nimport \'package:lucide_icons_flutter/lucide_icons.dart\';\n\nconst Map<String, IconData> iconesLucide = {\n';
ok.forEach(([n, c]) => { d += `  '${n}': LucideIcons.${c},\n`; });
d += '};\n\nIconData icone(String? nom) => iconesLucide[nom] ?? LucideIcons.circle;\n';
fs.writeFileSync(path.join(POSTE, 'lib', 'core', 'icones.dart'), d);
console.log(`  icônes : ${ok.length} reconnues` + (manquants.length ? `, ${manquants.length} sans équivalent (repli « circle ») : ${manquants.map((x) => x[0]).join(', ')}` : ''));

/* Jetons de la coque : des CONSTANTES (utilisables dans les widgets const), tirées de docs/design/design-tokens.json. */
const jet = JSON.parse(fs.readFileSync(path.join(REPO, 'docs/design/design-tokens.json'), 'utf8')).couleurs;
const argb = (h) => '0xFF' + h.replace('#', '').toUpperCase();
let j = '// ENGENDRÉ par prototype_html/build/gen-poste-assets.js depuis docs/design/design-tokens.json — NE PAS ÉDITER.\n// Constantes de couleur de la coque. Les « slate » sont la palette neutre par défaut de Tailwind, utilisée par la maquette.\nimport \'package:flutter/painting.dart\';\n\nclass JetonsShell {\n  JetonsShell._();\n';
for (const fam of ['navy', 'success', 'warning', 'danger']) for (const [n, h] of Object.entries(jet[fam])) j += `  static const Color ${fam}${n} = Color(${argb(h)});\n`;
const slate = { 50: '#f8fafc', 100: '#f1f5f9', 200: '#e2e8f0', 300: '#cbd5e1', 400: '#94a3b8', 500: '#64748b', 600: '#475569', 700: '#334155', 800: '#1e293b', 900: '#0f172a' };
for (const [n, h] of Object.entries(slate)) j += `  static const Color slate${n} = Color(${argb(h)});\n`;
j += '}\n';
fs.writeFileSync(path.join(POSTE, 'lib', 'core', 'jetons_shell.dart'), j);
console.log('  jetons de la coque : lib/core/jetons_shell.dart');
