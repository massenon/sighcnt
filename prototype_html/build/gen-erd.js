/* =============================================================================
 * ERD — diagramme entité-relation, ENGENDRÉ depuis le schéma PostgreSQL (packages/schema/postgres/)
 * -----------------------------------------------------------------------------
 *   node build/gen-erd.js      → docs/architecture/ERD.md (Mermaid ; un diagramme par module + le diagramme transversal)
 * Les relations sont celles que le schéma DÉCLARE : clés étrangères de 0001 (tables filles → parent) et de 0002
 * (collection → collection). Une relation qui n'est pas déclarée n'est pas dessinée : mieux vaut un diagramme incomplet
 * qu'un diagramme qui promet une contrainte inexistante.
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const REPO = path.resolve(__dirname, '..', '..');
const sql1 = fs.readFileSync(path.join(REPO, 'packages/schema/postgres/0001_modules.sql'), 'utf8');
const sql2 = fs.readFileSync(path.join(REPO, 'packages/schema/postgres/0002_cles_etrangeres.sql'), 'utf8');

const schemas = {}; for (const m of sql1.matchAll(/COMMENT ON SCHEMA "([^"]+)" IS '([^']+)'/g)) schemas[m[1]] = m[2];
const tables = new Set(); const colonnes = {};
for (const m of sql1.matchAll(/CREATE TABLE (?:IF NOT EXISTS )?"([^"]+)"\."([^"]+)" \(([\s\S]*?)\n\);/g)) {
  tables.add(m[1] + '.' + m[2]);
  colonnes[m[1] + '.' + m[2]] = (m[3].match(/^\s+"[a-z0-9_]+"\s/gm) || []).length;
}
const rel = []; // [enfant, parent, colonne, type]
for (const m of sql1.matchAll(/CREATE TABLE (?:IF NOT EXISTS )?"([^"]+)"\."([^"]+)" \(([\s\S]*?)\n\);/g)) {
  for (const f of m[3].matchAll(/FOREIGN KEY \("([^"]+)"\) REFERENCES "([^"]+)"\."([^"]+)"/g)) rel.push([m[1] + '.' + m[2], f[2] + '.' + f[3], f[1], 'fille']);
}
for (const m of sql2.matchAll(/ALTER TABLE "([^"]+)"\."([^"]+)" ADD CONSTRAINT "[^"]+" FOREIGN KEY \("([^"]+)"\) REFERENCES "([^"]+)"\."([^"]+)"/g)) rel.push([m[1] + '.' + m[2], m[4] + '.' + m[5], m[3], 'collection']);

const id = (t) => t.replace(/[^a-z0-9]/gi, '_');
let md = `# Diagramme entité-relation\n\n> **ENGENDRÉ** par \`prototype_html/build/gen-erd.js\` depuis \`packages/schema/postgres/\` — ne pas éditer. Dictionnaire des colonnes : [\`DICTIONNAIRE-DONNEES.md\`](DICTIONNAIRE-DONNEES.md).\n> Ne figurent que les relations **déclarées** au schéma (${rel.length} clés étrangères sur ${tables.size} tables, ${Object.keys(schemas).length} schémas). Les liens que le jeu courant ne respecte pas à 100 % ne sont pas déclarés (ils bloqueraient l'écriture) : la cible, avec un seul chemin d'écriture ordonné, les appliquera.\n\n`;
md += `| Mesure | Valeur |\n|---|---|\n| Tables | ${tables.size} |\n| Schémas (un par module) | ${Object.keys(schemas).length} |\n| Clés étrangères déclarées | ${rel.length} (dont ${rel.filter((r) => r[3] === 'fille').length} tables filles, ${rel.filter((r) => r[3] === 'collection').length} entre collections) |\n\n`;

function diagramme(titre, sel) {
  const lignes = rel.filter(sel);
  if (!lignes.length) return `### ${titre}\n\nAucune relation déclarée.\n\n`;
  const noeuds = new Set(); lignes.forEach((r) => { noeuds.add(r[0]); noeuds.add(r[1]); });
  let d = `### ${titre}\n\n\`\`\`mermaid\nerDiagram\n`;
  for (const r of lignes) d += `  ${id(r[1])} ||--o{ ${id(r[0])} : "${r[2]}"\n`;
  d += '```\n\n';
  d += `Tables : ${Array.from(noeuds).sort().map((t) => `\`${t}\` (${colonnes[t] || '?'} col.)`).join(' · ')}\n\n`;
  return d;
}
md += `## Transversal — liens entre modules\n\n`;
md += diagramme('Collections qui référencent d\'autres collections', (r) => r[3] === 'collection' && r[0].split('.')[0] !== r[1].split('.')[0]);
md += `## Par module\n\n`;
for (const s of Object.keys(schemas).sort((a, b) => a.localeCompare(b, 'fr', { numeric: true }))) {
  md += diagramme(`${s} — ${schemas[s]}`, (r) => r[0].startsWith(s + '.') && r[1].startsWith(s + '.'));
}
md += `## Tables sans aucune relation déclarée\n\n`;
const liees = new Set(); rel.forEach((r) => { liees.add(r[0]); liees.add(r[1]); });
const seules = Array.from(tables).filter((t) => !liees.has(t)).sort();
md += `${seules.length} tables sur ${tables.size} : ce sont des registres autonomes (référentiels, journaux, pièces émises) ou des collections dont les liens ne sont pas encore garantis.\n\n<details><summary>Liste</summary>\n\n${seules.map((t) => `- \`${t}\``).join('\n')}\n\n</details>\n`;
const out = path.join(REPO, 'docs/architecture/ERD.md'); fs.writeFileSync(out, md); console.log(`  écrit : docs/architecture/ERD.md — ${tables.size} tables, ${rel.length} relations, ${seules.length} sans relation`);
