/* =============================================================================
 * MANIFESTE DE PARITÉ MAQUETTE → CIBLE, CARTOGRAPHIE DES MODULES, RÈGLES DE GESTION
 * -----------------------------------------------------------------------------
 * Tout est ENGENDRÉ — jamais saisi à la main (PRD Flutter, P0-1) :
 *   • le manifeste de navigation  → packages/referentiels/data/manifeste.json (extraire.js)
 *   • les droits                  → packages/rbac/data/rbac.json            (extraire.js)
 *   • les scénarios de la maquette → build/test-fonctionnel.js (analysé ici, sans l'exécuter)
 *   • les règles de gestion        → CLAUDE.md (RG-01 → RG-14)
 * Seuls les STATUTS de portage vivent à la main : docs/architecture/parite-statuts.json
 * (écran → « non commencé » | « porté » | « recetté »), jamais écrasé par la génération.
 *
 *   node build/parite.js
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const REPO = path.resolve(__dirname, '..', '..');
const lire = (rel) => fs.readFileSync(path.join(REPO, rel), 'utf8');
const json = (rel) => JSON.parse(lire(rel));
const ecrire = (rel, txt) => { fs.mkdirSync(path.dirname(path.join(REPO, rel)), { recursive: true }); fs.writeFileSync(path.join(REPO, rel), txt); console.log('  écrit : ' + rel); };

const manifeste = json('packages/referentiels/data/manifeste.json');
const rbac = json('packages/rbac/data/rbac.json');
const ecrans = manifeste.ecrans;
const connus = new Set(ecrans.map((e) => e.id));

/* --- scénarios de la maquette → écrans qu'ils nomment ----------------------------------- */
const source = lire('prototype_html/build/test-fonctionnel.js');
const scenarios = [];
{
  const re = /scenario\('((?:[^'\\]|\\.)*)'\)/g; let m; const bornes = [];
  while ((m = re.exec(source))) bornes.push({ nom: m[1].replace(/\\'/g, "'"), debut: m.index });
  bornes.forEach((b, i) => {
    const bloc = source.slice(b.debut, i + 1 < bornes.length ? bornes[i + 1].debut : source.length);
    const ids = new Set();
    for (const t of bloc.matchAll(/['"`]([a-z0-9]+(?:-[a-z0-9]+)+)(?:\.(?:html|php))?['"`]/g)) if (connus.has(t[1])) ids.add(t[1]);
    scenarios.push({ n: i + 1, nom: b.nom, ecrans: Array.from(ids) });
  });
}
const parEcran = {};
scenarios.forEach((s) => s.ecrans.forEach((id) => { (parEcran[id] = parEcran[id] || []).push(s.n); }));

/* --- tranches verticales (ordre du risque, plan P4→P6) ------------------------------------- */
const TRANCHE = { M8: 1, MECEF: 1, M6: 2, M7: 2, M5: 3, M4: 4, M3: 4, M2: 4, M1: 4, M9: 5, M12: 5 };
const nomTranche = { 1: '1 · caisse + MECeF + impression', 2: '2 · pharmacie, stocks, achats', 3: '3 · laboratoire (imagerie : rangée M2)', 4: '4 · parcours clinique (M1–M4)', 5: '5 · assurances et comptabilité', 6: '6 · RH, paie, administration, pilotage, configuration' };
const tranche = (e) => (/^m2-(imagerie|dashboard-imagerie|echographie)/.test(e.id) ? 3 : TRANCHE[e.module] || 6);

let statuts = {};
try { statuts = json('docs/architecture/parite-statuts.json'); } catch (e) { statuts = {}; }
const statutDe = (id) => statuts[id] || 'non commencé';

const rolesDe = (id) => rbac.roles.filter((r) => rbac.parRole[r.id] && rbac.parRole[r.id][id]).map((r) => r.id);
const lignes = ecrans.filter((e) => !e.hub).map((e) => ({
  id: e.id, label: e.label, module: e.module, domaine: e.domaine, tranche: tranche(e), standalone: e.standalone, universel: e.universel,
  roles: rolesDe(e.id), scenarios: parEcran[e.id] || [], statut: statutDe(e.id),
}));
const hubs = ecrans.filter((e) => e.hub);

/* --- le manifeste de parité -------------------------------------------------------------- */
const nb = (f) => lignes.filter(f).length;
const couverts = nb((l) => l.scenarios.length);
let md = `# Manifeste de parité — maquette → cible\n\n> **ENGENDRÉ** par \`prototype_html/build/parite.js\` — ne pas éditer. Seuls les statuts se saisissent, dans \`docs/architecture/parite-statuts.json\`.\n> Sources : \`packages/referentiels/data/manifeste.json\`, \`packages/rbac/data/rbac.json\`, \`prototype_html/build/test-fonctionnel.js\`.\n\n`;
md += `| Mesure | Valeur |\n|---|---|\n| Écrans du manifeste (hors hubs de module) | **${lignes.length}** |\n| Hubs de module (un par module, engendrés) | ${hubs.length} |\n| Écrans nommés par au moins un scénario de la maquette | ${couverts} (${Math.round(100 * couverts / lignes.length)} %) |\n| Écrans **sans** scénario (recette à écrire) | ${lignes.length - couverts} |\n| Écrans portés | ${nb((l) => l.statut === 'porté')} |\n| Écrans recettés | ${nb((l) => l.statut === 'recetté')} |\n| Scénarios de la maquette analysés | ${scenarios.length} |\n\n`;
md += `> « Nommé par un scénario » est une **estimation par analyse du texte** du banc (un identifiant d'écran cité dans le scénario) : elle dit où une recette existe déjà à reprendre, pas qu'elle couvre tout l'écran.\n\n`;
md += `## Par tranche\n\n| Tranche | Écrans | Avec scénario | Portés | Recettés |\n|---|---|---|---|---|\n`;
for (const t of [1, 2, 3, 4, 5, 6]) { const l = lignes.filter((x) => x.tranche === t); md += `| ${nomTranche[t]} | ${l.length} | ${l.filter((x) => x.scenarios.length).length} | ${l.filter((x) => x.statut === 'porté').length} | ${l.filter((x) => x.statut === 'recetté').length} |\n`; }
md += `\n## Par écran\n\nColonnes : **Rôles** = nombre de rôles qui voient l'écran (matrice effective) · **Scénarios** = numéros d'ordre dans \`test-fonctionnel.js\`.\n\n`;
for (const t of [1, 2, 3, 4, 5, 6]) {
  md += `### Tranche ${nomTranche[t]}\n\n| Écran | Libellé | Module | Rôles | Scénarios | Statut |\n|---|---|---|---|---|---|\n`;
  lignes.filter((l) => l.tranche === t).sort((a, b) => a.module.localeCompare(b.module, 'fr', { numeric: true }) || a.id.localeCompare(b.id)).forEach((l) => {
    md += `| \`${l.id}\` | ${l.label.replace(/\|/g, '/')} | ${l.module} | ${l.roles.length}${l.universel ? ' (universel)' : ''} | ${l.scenarios.join(', ') || '—'} | ${l.statut} |\n`;
  });
  md += '\n';
}
ecrire('docs/architecture/PARITE-MAQUETTE.md', md);
ecrire('docs/architecture/parite.json', JSON.stringify({ _doc: 'ENGENDRÉ par prototype_html/build/parite.js — ne pas éditer.', ecrans: lignes }, null, 1) + '\n');
if (!fs.existsSync(path.join(REPO, 'docs/architecture/parite-statuts.json'))) ecrire('docs/architecture/parite-statuts.json', '{}\n');

/* --- la cartographie des modules ------------------------------------------------------------- */
let carto = `# Cartographie des modules\n\n> **ENGENDRÉ** par \`prototype_html/build/parite.js\` depuis le manifeste de navigation de la maquette (\`nav.js\`) — ne pas éditer.\n> Un **domaine** est un onglet du ruban ; une **rangée** regroupe des écrans d'un module ; une rangée **alias** réunit des écrans d'un autre module sans les dupliquer ; une rangée **secondaire** apporte des écrans canoniques à un module sans créer de second hub.\n\n`;
const domaines = []; manifeste.modules.forEach((m) => { if (!domaines.includes(m.domaine)) domaines.push(m.domaine); });
for (const d of domaines) {
  carto += `## ${d}\n\n| Rangée | Module | Type | Écrans | Rôles d'origine |\n|---|---|---|---|---|\n`;
  manifeste.modules.filter((m) => m.domaine === d).forEach((m) => {
    const type = m.alias ? 'alias' : m.secondaire ? 'secondaire' : 'canonique';
    const roles = m.roles === 'ALL' ? 'tous' : (Array.isArray(m.roles) ? m.roles.join(', ') : String(m.roles));
    carto += `| ${m.label.replace(/\|/g, '/')} | ${m.code} | ${type} | ${m.ecrans.length} | ${roles} |\n`;
  });
  carto += '\n';
}
carto += `## Matrice effective rôle × module\n\nCases : \`V\` voir · \`E\` éditer · \`A\` annuler (droits du MODULE ; un écran peut surcharger, voir \`packages/rbac/data/rbac.json\`).\n\n`;
const codes = Array.from(new Set(ecrans.filter((e) => !e.standalone).map((e) => e.module)));
const casse = (d) => (d ? [d.voir ? 'V' : '', d.editer ? 'E' : '', d.annuler ? 'A' : ''].join('') || '·' : '·');
carto += `| Rôle | ${codes.join(' | ')} |\n|---|${codes.map(() => '---').join('|')}|\n`;
rbac.roles.forEach((r) => { carto += `| ${r.label}${r.archive ? ' (archivé)' : ''} | ${codes.map((c) => { const d = rbac.matriceModules[r.id][c]; return d && d.horsMatrice ? '—' : casse(d); }).join(' | ')} |\n`; });
ecrire('docs/architecture/CARTOGRAPHIE-MODULES.md', carto);

/* --- les règles de gestion, extraites de CLAUDE.md ------------------------------------------------- */
const claude = lire('CLAUDE.md');
const rg = Array.from(claude.matchAll(/^- \*\*(RG-\d{2}(?:\/\d{2}\/\d{2})?)\*\* — (.+)$/gm)).map((m) => ({ id: m[1], texte: m[2] }));
let regles = `# Règles de gestion RG-01 → RG-14\n\n> **ENGENDRÉ** par \`prototype_html/build/parite.js\` depuis \`CLAUDE.md\` (source : CDCT §6 et §9.4) — ne pas éditer. Chaque règle devra porter, côté cible, un **vecteur de test** (\`packages/domaine/test/vecteurs/\`) : sans vecteur, pas de règle portée.\n\n| Règle | Énoncé | Vecteur de test | Statut |\n|---|---|---|---|\n`;
rg.forEach((r) => { regles += `| **${r.id}** | ${r.texte.replace(/\|/g, '/')} | à écrire | non portée |\n`; });
regles += `\n## Autres invariants (CLAUDE.md)\n\n- Un lit ne peut porter qu'une admission active.\n- CUMP calculé automatiquement sur consommables labo/médicaux.\n- Cotisations : part patronale 16,4 % / part ouvrière 3,6 %.\n- Une pièce émise ne se réécrit jamais (avoir, rectification, nouvelle pièce).\n- Une donnée de référence qui change se **versionne par date** (couverture d'assurance, grille des primes, plages par lot) — on n'écrase pas.\n- Une restriction s'**annonce** ; une commande refusée est **absente**, pas grisée ; « non calculable » n'est pas zéro ; un tiret n'est ni zéro ni exclusion.\n`;
ecrire('docs/specs/REGLES-GESTION.md', regles);
console.log(`  ${lignes.length} écrans · ${scenarios.length} scénarios · ${rg.length} règles de gestion extraites`);
