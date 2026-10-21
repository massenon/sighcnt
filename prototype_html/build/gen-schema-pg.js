/* =============================================================================
 * Générateur du schéma relationnel PostgreSQL du prototype SIGH-CNT
 * -----------------------------------------------------------------------------
 * Le prototype tient ses données en COLLECTIONS (une ligne JSON par collection
 * dans la table `collections`). Ce script en déduit des TABLES : une par
 * collection, rangée dans le schéma de son module, avec
 *   - des colonnes TYPÉES pour chaque champ scalaire observé ;
 *   - des tables FILLES pour les tableaux d'objets (lignes de facture, etc.) ;
 *   - une colonne `extra` (jsonb) qui reçoit tout champ non prévu — un champ
 *     ajouté demain à un écran n'est ainsi jamais perdu ni refusé ;
 *   - des clés étrangères UNIQUEMENT là où les données actuelles n'ont aucun
 *     orphelin (une clé que le jeu viole déjà ne protège rien, elle bloque).
 *
 * Usage :  node build/gen-schema-pg.js <magasin.json>
 *   où magasin.json = { "patients": [...], ... } (psql -At -c
 *   "select json_object_agg(nom, donnees) from collections").
 * Sorties : api/schema/{schema.sql,manifeste.json} (exécution du prototype) et
 *   ../packages/schema/postgres/0001_modules.sql (copie pour le projet cible).
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');

const RACINE = path.resolve(__dirname, '..');
const magasin = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));

/* --- Module de chaque collection : lu dans les sources, jamais deviné -------- */
const sources = [];
(function lire(d) {
  fs.readdirSync(d, { withFileTypes: true }).forEach((e) => {
    const p = path.join(d, e.name);
    if (e.isDirectory() && e.name !== 'vendor') lire(p);
    else if (e.name.endsWith('.js')) sources.push(fs.readFileSync(p, 'utf8'));
  });
})(path.join(RACINE, 'assets/js'));
const MODULE_DE = {};
const re = /collection\('([A-Za-z0-9_]+)',\s*\{[^}]*?module:\s*'([A-Z0-9]+)'/g;
sources.forEach((s) => { let m; while ((m = re.exec(s))) { if (!MODULE_DE[m[1]]) MODULE_DE[m[1]] = m[2]; } });
/* Collections que le socle sème sans que le code les déclare à un module : rangées au module qui les ÉCRIT,
   décidé ici une fois. `taches` (la file du parcours inter-modules) reste au socle, c'est sa place. */
const MODULE_PAR_DEFAUT = { ambulance: 'M13', assureurs: 'M9', audit: 'M14', comptes: 'M14', courriers: 'M13', cpon: 'M4', fournisseurs: 'M7',
  lots: 'M6', planificationFamiliale: 'M4', ptme: 'M4', registreSONU: 'M4', reunions: 'M13', soins: 'M2', soinsCuratifsMaternite: 'M4' };
Object.keys(MODULE_PAR_DEFAUT).forEach((n) => { if (!MODULE_DE[n]) MODULE_DE[n] = MODULE_PAR_DEFAUT[n]; });
const SCHEMAS = { M1: 'm1', M2: 'm2', M3: 'm3', M4: 'm4', M5: 'm5', M6: 'm6', M7: 'm7', M8: 'm8', M9: 'm9', M10: 'm10', M11: 'm11',
  M12: 'm12', M13: 'm13', M14: 'm14', MECEF: 'mecef', GED: 'ged', RAP: 'rap', PIL: 'pil', CFG: 'cfg', DASH: 'dash', AUTH: 'auth', SUP: 'sup' };
const LIBELLE_MODULE = { m1: 'M1 Patients & DMI', m2: 'M2 RDV, visites, consultations, imagerie', m3: 'M3 Hospitalisation & bloc', m4: 'M4 Maternité, naissances, décès',
  m5: 'M5 Laboratoire', m6: 'M6 Pharmacie & stocks', m7: 'M7 Achats & fournisseurs', m8: 'M8 Facturation & caisse', m9: 'M9 Assurances & créances',
  m10: 'M10 Ressources humaines', m11: 'M11 Paie & primes', m12: 'M12 Comptabilité SYSCOHADA', m13: 'M13 Administration & ambulance',
  m14: 'M14 Sécurité & audit', mecef: 'MECeF', ged: 'GED', rap: 'Rapports', pil: 'Pilotage', cfg: 'Configuration', dash: 'Tableaux de bord',
  auth: 'Authentification', sup: 'Support', socle: 'Socle commun (référentiels lus par plusieurs modules)' };
function schemaDe(nom) { return SCHEMAS[MODULE_DE[nom]] || 'socle'; }

/* --- Noms ------------------------------------------------------------------ */
const RESERVES = new Set(['user', 'order', 'group', 'table', 'desc', 'asc', 'check', 'default', 'end', 'from', 'limit', 'offset', 'primary',
  'references', 'select', 'to', 'all', 'analyse', 'analyze', 'both', 'case', 'cast', 'column', 'constraint', 'create', 'current_date', 'current_time',
  'current_timestamp', 'current_user', 'distinct', 'do', 'else', 'except', 'false', 'for', 'foreign', 'grant', 'having', 'in', 'initially', 'intersect',
  'into', 'leading', 'localtime', 'localtimestamp', 'not', 'null', 'only', 'or', 'placing', 'returning', 'session_user', 'some', 'symmetric', 'then',
  'trailing', 'true', 'union', 'unique', 'using', 'variadic', 'when', 'where', 'window', 'with', 'authorization', 'binary', 'collation', 'concurrently',
  'cross', 'freeze', 'full', 'ilike', 'inner', 'is', 'isnull', 'join', 'left', 'like', 'natural', 'notnull', 'outer', 'overlaps', 'right', 'similar',
  'tablesample', 'verbose', 'fetch', 'lateral', 'on', 'and', 'any', 'array', 'as']);
function sansAccents(s) { return s.normalize('NFD').replace(/[̀-ͯ]/g, ''); }
function snake(s) {
  let t = sansAccents(String(s)).replace(/([a-z0-9])([A-Z])/g, '$1_$2').replace(/([A-Z]+)([A-Z][a-z])/g, '$1_$2')
    .replace(/[^A-Za-z0-9]+/g, '_').replace(/^_+|_+$/g, '').toLowerCase();
  if (!t) t = 'champ';
  if (/^[0-9]/.test(t)) t = 'c_' + t;
  return RESERVES.has(t) ? t + '_' : t;
}
function unique(base, pris) { let n = base.slice(0, 60), i = 2; while (pris.has(n)) { n = base.slice(0, 56) + '_' + i++; } pris.add(n); return n; }
const q = (s) => '"' + s.replace(/"/g, '""') + '"';

/* --- Types ----------------------------------------------------------------- */
const RE_DATE = /^\d{4}-\d{2}-\d{2}$/;
const RE_TS = /^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?$/;
function classe(v) {
  if (v === null || v === undefined) return null;
  if (typeof v === 'boolean') return 'bool';
  if (typeof v === 'number') return Number.isInteger(v) ? (Math.abs(v) > 2147483647 ? 'bigint' : 'int') : 'num';
  if (typeof v === 'string') { if (RE_DATE.test(v)) return 'date'; if (RE_TS.test(v)) return /(Z|[+-]\d{2}:?\d{2})$/.test(v) ? 'tstz' : 'ts'; return 'str'; }
  if (Array.isArray(v)) return 'arr';
  return 'obj';
}
function typeSql(classes) {
  const c = new Set(classes);
  if (!c.size) return 'text';
  if (c.size === 1) { const x = [...c][0]; return { bool: 'boolean', int: 'integer', bigint: 'bigint', num: 'numeric', date: 'date', ts: 'timestamp', tstz: 'timestamptz', str: 'text', obj: 'jsonb', arr: 'jsonb' }[x]; }
  const tous = (...a) => [...c].every((x) => a.includes(x));
  if (tous('int', 'bigint')) return 'bigint';
  if (tous('int', 'bigint', 'num')) return 'numeric';
  if (tous('date', 'ts')) return 'timestamp';
  if (tous('date', 'ts', 'tstz')) return 'timestamptz';
  if (tous('str', 'date')) return 'text';
  if (tous('str', 'ts') || tous('str', 'tstz') || tous('str', 'date', 'ts', 'tstz')) return 'text';
  return 'jsonb';   /* types mêlés : on ne devine pas, on garde la valeur telle quelle */
}

function analyser(lignes) {
  const champs = new Map();
  lignes.forEach((r) => {
    Object.keys(r).forEach((k) => {
      const e = champs.get(k) || { classes: [], presents: 0, tableauxObjets: 0, tableauxAutres: 0 };
      const cl = classe(r[k]);
      if (cl) { e.classes.push(cl); e.presents++; }
      if (cl === 'arr') {
        const vide = r[k].length === 0;
        if (!vide && r[k].every((x) => x && typeof x === 'object' && !Array.isArray(x))) e.tableauxObjets++;
        else if (!vide) e.tableauxAutres++;
      }
      champs.set(k, e);
    });
  });
  return champs;
}

/* --- Construction ----------------------------------------------------------- */
/* Une collection dont aucune entrée n'est un objet (liste de codes, de chaînes) n'a rien à mettre en colonnes. */
const estFiche = (r) => r && typeof r === 'object' && !Array.isArray(r);
const IGNOREES = Object.keys(magasin).filter((n) => Array.isArray(magasin[n]) && magasin[n].length && !magasin[n].some(estFiche)).sort();
const noms = Object.keys(magasin).filter((n) => Array.isArray(magasin[n]) && IGNOREES.indexOf(n) < 0).sort();
const tables = {};
const ids = {};
noms.forEach((n) => { ids[n] = new Set(magasin[n].map((r) => r && r.id).filter((x) => x !== undefined && x !== null).map(String)); });

noms.forEach((nom) => {
  const lignes = magasin[nom].filter((r) => r && typeof r === 'object' && !Array.isArray(r));
  const schema = schemaDe(nom);
  const champs = analyser(lignes);
  const pris = new Set(['extra']);
  const colonnes = [], enfants = [];
  const aId = lignes.length && lignes.every((r) => r.id !== undefined && r.id !== null) && new Set(lignes.map((r) => String(r.id))).size === lignes.length;
  champs.forEach((e, k) => {
    if (e.tableauxObjets && !e.tableauxAutres && e.classes.every((c) => c === 'arr')) { enfants.push(k); return; }
    const col = unique(snake(k), pris);
    const typ = k === 'id' && aId ? 'text' : typeSql(e.classes);
    colonnes.push({ champ: k, col, typ, presents: e.presents });
  });
  const fils = enfants.map((k) => {
    const objets = []; lignes.forEach((r) => { if (Array.isArray(r[k])) r[k].forEach((o) => objets.push(o)); });
    const ch = analyser(objets); const pc = new Set(['extra', 'parent_id', 'rang']); const cols = [];
    ch.forEach((e, kk) => { cols.push({ champ: kk, col: unique(snake(kk), pc), typ: typeSql(e.classes), presents: e.presents }); });
    return { champ: k, table: unique(snake(nom + '_' + k), new Set()), colonnes: cols, lignes: objets.length };
  });
  tables[nom] = { collection: nom, schema, table: snake(nom), aId: !!aId, lignes: lignes.length, colonnes, enfants: fils };
});
/* Deux collections peuvent donner le même nom de table dans le même schéma : on suffixe. */
const vus = new Set();
Object.values(tables).forEach((t) => { let n = t.table, i = 2; while (vus.has(t.schema + '.' + n)) n = t.table + '_' + i++; t.table = n; vus.add(t.schema + '.' + n); t.enfants.forEach((f) => { f.table = (t.table + '_' + snake(f.champ)).slice(0, 60); }); });

/* --- Références : une clé étrangère seulement si le jeu actuel n'a AUCUN orphelin */
const parNom = {};
noms.forEach((n) => { parNom[n.toLowerCase()] = n; });
function cible(champ) {
  if (!/Id$/.test(champ) || champ === 'id') return null;
  const b = champ.slice(0, -2).toLowerCase();
  for (const c of [b + 's', b + 'x', b, b.replace(/e$/, 'es'), b + 'es']) if (parNom[c] && tables[parNom[c]] && tables[parNom[c]].aId) return parNom[c];
  return null;
}
const fks = [];
Object.values(tables).forEach((t) => {
  t.colonnes.forEach((c) => {
    const cib = cible(c.champ);
    if (!cib || cib === t.collection) return;
    const valeurs = magasin[t.collection].map((r) => r && r[c.champ]).filter((v) => v !== undefined && v !== null && v !== '');
    if (!valeurs.length || c.typ !== 'text') return;
    const orphelins = valeurs.filter((v) => !ids[cib].has(String(v))).length;
    c.ref = { collection: cib, orphelins, utilises: valeurs.length };
    if (orphelins === 0) { c.fk = cib; fks.push({ de: t.collection, col: c.col, vers: cib }); }
  });
});

/* --- DDL ------------------------------------------------------------------- */
const out = [];
out.push('-- =============================================================================');
out.push('-- SIGH-CNT — tables relationnelles de TOUS les modules (PostgreSQL)');
out.push('-- ENGENDRÉ par prototype_html/build/gen-schema-pg.js — ne pas éditer à la main.');
out.push('-- Une table par collection du magasin, un schéma par module, des tables filles pour');
out.push('-- les tableaux d\'objets, une colonne `extra` pour tout champ non prévu, des clés');
out.push('-- étrangères là où le jeu courant n\'a aucun orphelin. RG-14 : aucune suppression');
out.push('-- physique côté application — `statut = \'archive\'` reste une valeur, pas un DELETE.');
out.push('-- =============================================================================');
Array.from(new Set(Object.values(tables).map((t) => t.schema))).sort().forEach((s) => {
  out.push('CREATE SCHEMA IF NOT EXISTS ' + q(s) + ';');
  out.push('COMMENT ON SCHEMA ' + q(s) + ' IS ' + "'" + (LIBELLE_MODULE[s] || s).replace(/'/g, "''") + "';");
});
out.push('');
const manifeste = { version: 1, tables: {} };
Object.values(tables).sort((a, b) => (a.schema + a.table).localeCompare(b.schema + b.table)).forEach((t) => {
  const nomT = q(t.schema) + '.' + q(t.table);
  const lignes = [];
  t.colonnes.forEach((c) => {
    const pk = c.champ === 'id' && t.aId;
    lignes.push('  ' + q(c.col) + ' ' + c.typ + (pk ? ' PRIMARY KEY' : ''));
  });
  if (!t.aId) lignes.unshift('  "_rang" integer PRIMARY KEY');
  lignes.push('  "extra" jsonb');
  out.push('CREATE TABLE IF NOT EXISTS ' + nomT + ' (\n' + lignes.join(',\n') + '\n);');
  out.push('COMMENT ON TABLE ' + nomT + ' IS ' + "'Collection « " + t.collection + " » — " + (LIBELLE_MODULE[t.schema] || t.schema).replace(/'/g, "''") + "'" + ';');
  const idx = new Set();
  t.colonnes.forEach((c) => {
    if (/Id$/.test(c.champ) || /^(statut|etat|code|numero|reference|date|dateHeure|patientId|annee|periode|type|nature)$/.test(c.champ)) {
      if (c.typ !== 'jsonb' && !(c.champ === 'id') && !idx.has(c.col)) { idx.add(c.col); out.push('CREATE INDEX IF NOT EXISTS ' + q('ix_' + t.table + '_' + c.col) + ' ON ' + nomT + ' (' + q(c.col) + ');'); }
    }
  });
  t.enfants.forEach((f) => {
    const nf = q(t.schema) + '.' + q(f.table);
    const cl = ['  "parent_id" text NOT NULL', '  "rang" integer NOT NULL'];
    f.colonnes.forEach((c) => cl.push('  ' + q(c.col) + ' ' + c.typ));
    cl.push('  "extra" jsonb', '  PRIMARY KEY ("parent_id", "rang")');
    if (t.aId) cl.push('  FOREIGN KEY ("parent_id") REFERENCES ' + nomT + ' ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED');
    out.push('CREATE TABLE IF NOT EXISTS ' + nf + ' (\n' + cl.join(',\n') + '\n);');
    out.push('COMMENT ON TABLE ' + nf + ' IS ' + "'Lignes « " + f.champ + " » de « " + t.collection + " »';");
  });
  manifeste.tables[t.collection] = {
    schema: t.schema, table: t.table, aId: t.aId,
    colonnes: t.colonnes.map((c) => ({ champ: c.champ, col: c.col, typ: c.typ })),
    enfants: t.enfants.map((f) => ({ champ: f.champ, table: f.table, colonnes: f.colonnes.map((c) => ({ champ: c.champ, col: c.col, typ: c.typ })) })),
  };
});
out.push('');
out.push('-- Clés étrangères : seulement celles que les données actuelles respectent à 100 %.');
fks.forEach((fk) => {
  const t = tables[fk.de], c = tables[fk.vers];
  out.push('ALTER TABLE ' + q(t.schema) + '.' + q(t.table) + ' ADD CONSTRAINT ' + q('fk_' + t.table + '_' + fk.col).slice(0, 63) + '"'.slice(0, 0)
    + ' FOREIGN KEY (' + q(fk.col) + ') REFERENCES ' + q(c.schema) + '.' + q(c.table) + ' ("id") DEFERRABLE INITIALLY DEFERRED;');
});
/* ADD CONSTRAINT n'a pas de IF NOT EXISTS : on les emballe pour que le script reste rejouable. */
const sql = out.join('\n').replace(/^(ALTER TABLE .* ADD CONSTRAINT .*;)$/gm, (l) => {
  const m = /ADD CONSTRAINT "([^"]+)"/.exec(l); const t = /^ALTER TABLE ("[^"]+")\.("[^"]+")/.exec(l);
  return 'DO $$ BEGIN ' + l + ' EXCEPTION WHEN duplicate_object THEN NULL; END $$;';
});
manifeste.fks = fks;
manifeste.ignorees = IGNOREES;
fs.writeFileSync(path.join(RACINE, 'api/schema/schema.sql'), sql + '\n');
fs.writeFileSync(path.join(RACINE, 'api/schema/manifeste.json'), JSON.stringify(manifeste));
fs.mkdirSync(path.resolve(RACINE, '../packages/schema/postgres'), { recursive: true });
fs.writeFileSync(path.resolve(RACINE, '../packages/schema/postgres/0001_modules.sql'), sql + '\n');

/* --- Dictionnaire lisible -------------------------------------------------- */
const dico = ['# Dictionnaire des données — tables PostgreSQL par module', '',
  'Engendré par `prototype_html/build/gen-schema-pg.js` à partir du magasin du prototype. **Ne pas éditer à la main.**', '',
  '| Schéma (module) | Tables | Tables filles | Colonnes typées | Fiches observées |', '|---|---:|---:|---:|---:|'];
const parSchema = {};
Object.values(tables).forEach((t) => { const s = parSchema[t.schema] || (parSchema[t.schema] = { t: 0, f: 0, c: 0, n: 0 }); s.t++; s.f += t.enfants.length; s.c += t.colonnes.length; s.n += t.lignes; });
Object.keys(parSchema).sort().forEach((s) => dico.push('| `' + s + '` — ' + (LIBELLE_MODULE[s] || s) + ' | ' + parSchema[s].t + ' | ' + parSchema[s].f + ' | ' + parSchema[s].c + ' | ' + parSchema[s].n + ' |'));
dico.push('', '## Détail par table', '');
Object.values(tables).sort((a, b) => (a.schema + a.table).localeCompare(b.schema + b.table)).forEach((t) => {
  dico.push('### `' + t.schema + '.' + t.table + '` (collection « ' + t.collection + ' », ' + t.lignes + ' fiches)', '');
  dico.push('| Colonne | Champ | Type | Référence |', '|---|---|---|---|');
  t.colonnes.forEach((c) => dico.push('| `' + c.col + '` | ' + c.champ + ' | ' + c.typ + ' | ' + (c.fk ? '→ ' + c.fk + ' (FK)' : (c.ref ? '→ ' + c.ref.collection + ' (' + c.ref.orphelins + ' orphelin(s) sur ' + c.ref.utilises + ', pas de FK)' : '')) + ' |'));
  t.enfants.forEach((f) => dico.push('', 'Table fille `' + t.schema + '.' + f.table + '` — ' + f.lignes + ' lignes : ' + f.colonnes.map((c) => c.col + ' ' + c.typ).join(', ')));
  dico.push('');
});
fs.writeFileSync(path.resolve(RACINE, '../docs/architecture/DICTIONNAIRE-DONNEES.md'), dico.join('\n'));
const nbT = Object.keys(tables).length, nbF = Object.values(tables).reduce((a, t) => a + t.enfants.length, 0);
console.log('Ignorées (sans fiche objet) : ' + IGNOREES.join(', '));
console.log('Collections : ' + nbT + ' → tables ' + nbT + ' + filles ' + nbF + ' · schémas ' + Object.keys(parSchema).length + ' · clés étrangères ' + fks.length);
const sansModule = Object.values(tables).filter((t) => t.schema === 'socle').map((t) => t.collection);
console.log('Rangées au socle (module non déclaré) : ' + sansModule.length + (sansModule.length ? ' — ' + sansModule.slice(0, 12).join(', ') : ''));
