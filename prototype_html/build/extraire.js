/* =============================================================================
 * EXTRACTION DES RÉFÉRENTIELS DE LA MAQUETTE — source unique pour la cible
 * -----------------------------------------------------------------------------
 * La maquette est l'exécutable de référence : tout ce que la cible (Flutter, Laravel) doit
 * reprendre est EXTRAIT d'elle par ce script, jamais recopié à la main.
 *
 *   node build/extraire.js            tout
 *   node build/extraire.js rbac       matrice des droits + manifeste de navigation
 *   node build/extraire.js jetons     jetons de design (+ jetons.dart pour packages/domaine)
 *
 * Le navigateur (Playwright, déjà présent sur le poste de rédaction) charge les scripts de la maquette
 * sur un gabarit généré, avec le magasin amorcé par `data-seed.js` : on interroge `SIGH.nav` — la
 * fonction même qu'appelle le ruban — plutôt que d'interpréter le manifeste en théorie.
 * Sorties (versionnées, ENGENDRÉES : ne pas les éditer à la main) :
 *   packages/rbac/data/rbac.json · packages/referentiels/data/manifeste.json
 *   docs/design/design-tokens.json · packages/domaine/lib/src/design/jetons.dart
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '..');
const REPO = path.resolve(ROOT, '..');
const SCRIPTS = (() => {
  const src = fs.readFileSync(path.join(__dirname, 'gen-pages.js'), 'utf8');
  const m = /const SCRIPTS = \[([\s\S]*?)\];/.exec(src);
  return Array.from(m[1].matchAll(/'([^']+)'/g)).map((x) => x[1]);
})();

function ecrire(rel, objet) {
  const f = path.join(REPO, rel);
  fs.mkdirSync(path.dirname(f), { recursive: true });
  fs.writeFileSync(f, typeof objet === 'string' ? objet : JSON.stringify(objet, null, 1) + '\n');
  console.log('  écrit : ' + rel);
}

/** Ouvre un gabarit minimal qui charge TOUS les scripts de la maquette, servi par le serveur PHP du banc
 *  (base JETABLE `sigh_prototype_test`, jamais la base de travail) : le magasin n'est plus une source
 *  navigateur, il vient de la base, amorcé par `data-seed.js` au premier accès après ouverture de session. */
async function ouvrirMaquette() {
  const BANC = require('./_banc');
  const { chromium } = require('playwright');
  const demarrage = await BANC.demarrerPhp(ROOT);
  if (!demarrage.php) throw new Error('serveur PHP du banc indisponible : ' + demarrage.raison);
  const rep = await BANC.banc('reinitialiser');
  if (rep && rep.erreur) throw new Error('base jetable inaccessible : ' + rep.erreur + ' — ' + (rep.detail || ''));
  const jeton = (await BANC.connecter(BANC.SESSION_BANC.identifiant) || {}).jeton;
  if (!jeton) throw new Error('connexion du banc refusée');
  const gabarit = path.join(ROOT, '_extraction.html');
  fs.writeFileSync(gabarit, '<!doctype html><html lang="fr" data-root=""><head><meta charset="utf-8"></head><body>\n'
    + SCRIPTS.map((s) => `<script src="assets/js/${s}"></script>`).join('\n') + '\n</body></html>');
  const navigateur = await chromium.launch();
  const page = await navigateur.newPage();
  const erreurs = [];
  page.on('pageerror', (e) => erreurs.push(String(e && e.message || e)));
  await page.addInitScript(([session, j]) => {
    localStorage.setItem('sigh-cnt:session', JSON.stringify(session));
    localStorage.setItem('sigh-cnt:jeton', j);
  }, [BANC.SESSION_BANC, jeton]);
  await page.goto(`http://127.0.0.1:${BANC.PORT_PHP}/_extraction.html`);
  await page.waitForFunction(() => window.SIGH && SIGH.nav && SIGH.store, null, { timeout: 15000 });
  /* Hydratation, puis premier accès : c'est lui qui sème (la session est posée). */
  await page.evaluate(async () => { await SIGH.store.hydraterServeur(); SIGH.store.collection('patients', { module: 'M1' }).all(); });
  return { page, erreurs, fermer: async () => {
    await navigateur.close();
    try { fs.unlinkSync(gabarit); } catch (e) { /* déjà retiré */ }
    try { demarrage.php.kill(); } catch (e) { /* déjà arrêté */ }
  } };
}

async function extraireRbac() {
  console.log('▶ RBAC et manifeste');
  const m = await ouvrirMaquette();
  try {
    const r = await m.page.evaluate(() => {
      const N = SIGH.nav; const propre = (x) => JSON.parse(JSON.stringify(x));
      /* seeding : toute lecture de collection amorce le magasin ; on force l'amorçage avant de lire les droits */
      try { SIGH.store.collection('rbac').all(); } catch (e) { /* le fallback lit quand même */ }
      /* `nav.js` lit la matrice AVANT que le magasin soit amorcé : on vide ses caches, comme le fait la page
         après hydratation (store.invaliderManifeste). Sans cela, TOUTE la couche de surcharges serait morte. */
      N.invaliderRbac(); N.invaliderModules(); N.appliquerRenommages();
      const roles = Object.keys(N.ROLES).map((id) => Object.assign({}, propre(N.ROLES[id]), { archive: !!N.roleArchive(id) }));
      const modules = []; const vus = new Set();
      N.NAV.forEach((d) => d.modules.forEach((mod) => {
        modules.push({ domaine: d.domain, code: mod.code, label: mod.label, alias: !!mod.alias, secondaire: !!mod.secondaire,
          roles: mod.roles === undefined ? 'ALL' : propre(mod.roles), ecrans: mod.items.map((i) => i.id) });
        vus.add(mod.code);
      }));
      const codes = Array.from(new Set(Object.values(N.INDEX).map((e) => e.module)));
      const ecrans = N.ids().map((id) => {
        const e = N.get(id);
        return { id, label: e.label, module: e.module, moduleLabel: e.moduleLabel, domaine: e.domain, hub: !!e.hub, standalone: !!e.standalone,
          universel: !!e.universel, servant: e.servant || null, roles: propre(e.roles) };
      });
      /* Droits EFFECTIFS : ce que chaque rôle voit réellement, écran par écran (même appel que le ruban). */
      const matrice = {}; const parRole = {};
      roles.forEach((ro) => {
        matrice[ro.id] = {};
        codes.forEach((c) => { const d = N.droits(ro.id, c); matrice[ro.id][c] = d.horsMatrice ? { horsMatrice: true } : { voir: !!d.voir, editer: !!d.editer, annuler: !!d.annuler }; });
        parRole[ro.id] = {};
        ecrans.forEach((e) => {
          if (e.hub) return;
          const entree = N.get(e.id);
          let visible = false; try { visible = !!N.can(ro.id, { roles: entree.roles, module: entree.module, id: e.id, universel: entree.universel, servant: entree.servant }); } catch (x) { visible = false; }
          if (!visible) return;
          const d = N.droitsEcran(ro.id, e.id, e.module);
          parRole[ro.id][e.id] = [d.voir ? 1 : 0, d.editer ? 1 : 0, d.annuler ? 1 : 0];
        });
      });
      return { roles, modules, ecrans, matrice, parRole, version: SIGH.store.VERSION || null };
    });
    const total = Object.values(r.parRole).reduce((a, o) => a + Object.keys(o).length, 0);
    console.log(`  ${r.roles.length} rôles · ${r.modules.length} rangées · ${r.ecrans.length} entrées d'index · ${total} droits écran×rôle`);
    if (m.erreurs.length) console.log('  (avertissements de chargement : ' + m.erreurs.length + ')');
    ecrire('packages/rbac/data/rbac.json', {
      _doc: 'ENGENDRÉ par prototype_html/build/extraire.js — ne pas éditer. Source unique des droits : lue par le service de la mère, le poste, le mobile et le panneau. parRole[rôle][écran] = [voir, éditer, annuler].',
      roles: r.roles, matriceModules: r.matrice, parRole: r.parRole });
    ecrire('packages/referentiels/data/manifeste.json', {
      _doc: 'ENGENDRÉ par prototype_html/build/extraire.js — manifeste de navigation de la maquette (domaines, rangées, écrans).',
      modules: r.modules, ecrans: r.ecrans });
    return r;
  } finally { await m.fermer(); }
}

function extraireJetons() {
  console.log('▶ Jetons de design');
  const cfg = require(path.join(ROOT, 'tailwind.config.js')).theme.extend;
  const css = fs.readFileSync(path.join(ROOT, 'src/input.css'), 'utf8');
  const composants = {};
  for (const m of css.matchAll(/^\s*\.([a-z0-9-]+(?:\s*,\s*\.[a-z0-9-]+)*)\s*\{\s*@apply\s+([^;]+);/gm)) composants[m[1].replace(/\s+/g, '')] = m[2].trim().replace(/\s+/g, ' ');
  const jetons = {
    _doc: 'ENGENDRÉ par prototype_html/build/extraire.js depuis tailwind.config.js et src/input.css — ne pas éditer. Aucune couleur en dur hors de ce fichier (PRD Flutter P0-3).',
    police: cfg.fontFamily, couleurs: cfg.colors, ombres: cfg.boxShadow, animations: cfg.animation,
    tailleMinimalePt: 11, composants,
  };
  ecrire('docs/design/design-tokens.json', jetons);
  /* Dart : entiers ARGB, utilisables par un ThemeData sans importer de bibliothèque. */
  const argb = (hex) => '0xFF' + hex.replace('#', '').toUpperCase();
  let d = '// ENGENDRÉ par prototype_html/build/extraire.js — NE PAS ÉDITER.\n'
    + '// Jetons de design de la maquette (tailwind.config.js). Aucune couleur en dur ailleurs.\n'
    + '// ignore_for_file: constant_identifier_names\n\n'
    + '/// Palettes (nuance -> ARGB). Utilisation : `Color(JetonsSigh.navy[900]!)`.\n'
    + 'class JetonsSigh {\n  JetonsSigh._();\n';
  for (const [nom, nuances] of Object.entries(cfg.colors)) {
    d += `  static const Map<int, int> ${nom} = {\n` + Object.entries(nuances).map(([k, v]) => `    ${k}: ${argb(v)},`).join('\n') + '\n  };\n';
  }
  d += `  static const List<String> policeSans = [${cfg.fontFamily.sans.map((x) => `'${x}'`).join(', ')}];\n`;
  d += `  static const List<String> policeMono = [${cfg.fontFamily.mono.map((x) => `'${x}'`).join(', ')}];\n`;
  d += '  /// Taille de texte minimale (CDCT) : 11 pt équivalent.\n  static const double tailleMinimalePt = 11;\n}\n';
  ecrire('packages/domaine/lib/src/design/jetons.dart', d);
  console.log(`  ${Object.keys(cfg.colors).length} palettes · ${Object.keys(composants).length} composants CSS recensés`);
  return jetons;
}

module.exports = { ouvrirMaquette, ecrire, REPO, ROOT };
if (require.main === module) (async () => {
  const quoi = process.argv[2] || 'tout';
  if (quoi === 'rbac' || quoi === 'tout') await extraireRbac();
  if (quoi === 'jetons' || quoi === 'tout') extraireJetons();
})().catch((e) => { console.error(e); process.exit(1); });
