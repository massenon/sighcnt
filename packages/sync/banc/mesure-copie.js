'use strict';
/* MESURE de la copie consultable à l'échelle d'une grosse clinique (PRD relais consultable). Reproductible :
     node banc/mesure-copie.js [--patients=18000] [--dart] [--sans-page]
   1. (--dart) le tour de copie du POSTE et de la MÈRE sur 18 000 patients et ~200 000 opérations (packages/sync_dart/tool/mesure_copie*.dart) ;
   2. la PAGE de consultation dans Chromium (Playwright) contre `php artisan serve` et une base SQLite jetable, avec deux formes de copie :
        A. la mère seule : lots de 500 fiches (36 enveloppes pour 18 000 fiches) ;
        B. un poste seul : une enveloppe par fiche (18 000 enveloppes, 90 pages de 200).
   Mesures de la page : temps de « Charger et déchiffrer » jusqu'au dernier lot, temps d'une recherche, tas JavaScript. Seuils d'échec à SIGNALER : un tour de copie > 2 s,
   une page > 5 s à 18 000 fiches. Sortie JSON. */
const { spawn, execFileSync } = require('node:child_process');
const fs = require('node:fs'); const os = require('node:os'); const path = require('node:path');
const { chiffrer } = require('./crypto');
const arg = (n, d) => { const a = process.argv.find((x) => x.startsWith('--' + n + '=')); return a ? a.split('=')[1] : d; };
const PATIENTS = +arg('patients', '18000'); const RACINE = path.join(__dirname, '..', '..', '..'); const WEB = path.join(RACINE, 'apps', 'web');
const CLE = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90'; const SORTIE = { patients: PATIENTS };

function mesureDart() {
  const cwd = path.join(RACINE, 'packages', 'sync_dart');
  const lire = (script, a) => { const t = execFileSync('dart', ['run', script, ...a], { cwd, encoding: 'utf8', timeout: 1800000 }); return JSON.parse(t.slice(t.indexOf('{'))); };
  SORTIE.poste = lire('tool/mesure_copie.dart', [`--patients=${PATIENTS}`, '--ops=200000']);
  SORTIE.mere = lire('tool/mesure_copie_mere.dart', [`--patients=${PATIENTS}`, '--ops=200000']);
}

const noms = ['AKPO', 'KOUA', 'DOSSOU', 'ADJOVI', 'SOGLO', 'HOUNKPATIN', 'TCHANDO', 'BIO'];
const fiche = (i) => ({ collection: 'patients', fiche: 'p' + i, data: { nom: noms[i % 8], prenom: 'Prénom' + i, tel: '9' + String(i).padStart(7, '0'), quartier: 'Quartier ' + (i % 40), naissance: '19' + (60 + i % 40) + '-01-01' }, archive: false, ordre: [3, 5000 + i, 'F1', 'o' + i] });

async function mesurePage() {
  const { chromium } = require('playwright');
  const { DatabaseSync } = require('node:sqlite');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mesure-copie-')); const dbf = path.join(dir, 'relais.sqlite'); fs.writeFileSync(dbf, '');
  const PORT = 19000 + Math.floor(Math.random() * 900); const BASE = `http://127.0.0.1:${PORT}`;
  const env = Object.assign({}, process.env, { DB_CONNECTION: 'sqlite', DB_DATABASE: dbf, RELAIS_SECRET_MERE: 'secret-mesure', APP_ENV: 'local', SESSION_DRIVER: 'file', CACHE_STORE: 'file' });
  const art = (...a) => execFileSync('php', ['artisan', ...a], { env, cwd: WEB, encoding: 'utf8' });
  art('migrate', '--force'); art('relais:superadmin', 'mesure@exemple.bj', '--mot-de-passe=motdepasse-mesure');
  const cle = Buffer.from(CLE, 'hex');
  const peupler = (appareil, charges) => {
    const db = new DatabaseSync(dbf); db.exec('DELETE FROM relais_enveloppes;');
    const ins = db.prepare('INSERT INTO relais_enveloppes (id, appareil, dir, n, nonce, ct, taille, recu) VALUES (?,?,?,?,?,?,?,?)');
    db.exec('BEGIN'); let n = 0;
    for (const c of charges) { n++; const e = chiffrer(cle, c, { id: `${appareil}-copie-${n}`, appareil, dir: 'copie', n }); ins.run(e.id, appareil, 'copie', n, e.nonce, e.ct, e.ct.length, Date.now()); }
    db.exec('COMMIT'); db.close(); return n;
  };
  const srv = spawn('php', ['artisan', 'serve', '--host=127.0.0.1', `--port=${PORT}`], { env, cwd: WEB, stdio: 'ignore', detached: true });
  const navigateur = await chromium.launch({ args: ['--no-sandbox'] });
  try {
    for (let i = 0; i < 60; i++) { try { await fetch(BASE + '/panneau/connexion'); break; } catch (e) { await new Promise((r) => setTimeout(r, 250)); } }
    const formes = {
      A_mere_lots_de_500: () => { const l = []; for (let d = 0; d < PATIENTS; d += 500) l.push({ lot: Array.from({ length: Math.min(500, PATIENTS - d) }, (_, k) => fiche(d + k)) }); return ['mere', l]; },
      B_poste_une_enveloppe_par_fiche: () => ['F1', Array.from({ length: PATIENTS }, (_, i) => fiche(i))],
    };
    SORTIE.page = {};
    for (const [nom, fab] of Object.entries(formes)) {
      const [appareil, charges] = fab(); const nEnv = peupler(appareil, charges);
      const page = await (await navigateur.newContext({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 1 })).newPage();
      const erreurs = []; page.on('pageerror', (e) => erreurs.push(String(e)));
      await page.goto(BASE + '/panneau/connexion');
      await page.fill('#courriel', 'mesure@exemple.bj'); await page.fill('#mot_de_passe', 'motdepasse-mesure');
      await Promise.all([page.waitForURL(/\/panneau\/?$/), page.click('button[type=submit]')]);
      await page.goto(BASE + '/panneau/consultation'); await page.waitForSelector('input[aria-label="Clé de la clinique"]');
      await page.waitForTimeout(500);
      await page.fill('input[aria-label="Clé de la clinique"]', CLE);
      const t0 = Date.now();
      await page.click('text=Charger et déchiffrer');
      await page.waitForFunction((n) => /dossier\(s\) lisible/.test(document.querySelector('[role=status]').textContent) && true, PATIENTS, { timeout: 600000 });
      const chargement = Date.now() - t0;
      const msg = (await page.textContent('[role=status]')).trim();
      const lignes = await page.locator('tbody tr').count();
      const tas = await page.evaluate(() => performance.memory ? Math.round(performance.memory.usedJSHeapSize / 1048576) : null);
      const t1 = Date.now();
      await page.fill('input[aria-label="Rechercher un dossier"]', 'Prénom1234');
      await page.waitForFunction(() => document.querySelectorAll('tbody tr').length <= 12, null, { timeout: 120000 });
      const recherche = Date.now() - t1;
      SORTIE.page[nom] = { enveloppes: nEnv, chargement_ms: chargement, message: msg, lignes_affichees: lignes, tas_js_mo: tas, recherche_ms: recherche, erreurs_js: erreurs.length, limite_5s_depassee: chargement > 5000 };
      await page.context().close();
    }
  } finally { await navigateur.close(); try { process.kill(-srv.pid, 'SIGKILL'); } catch (e) { srv.kill('SIGKILL'); } }
}

(async () => {
  if (process.argv.includes('--dart')) mesureDart();
  if (!process.argv.includes('--sans-page')) await mesurePage();
  console.log(JSON.stringify(SORTIE, null, 2));
})().catch((e) => { console.error('ERREUR', e); process.exit(2); });
