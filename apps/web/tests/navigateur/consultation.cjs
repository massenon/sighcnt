'use strict';
/* Page « Consultation des copies » exercée dans un VRAI navigateur (Chromium via Playwright) contre `php artisan serve` et une base SQLite jetable.
   Usage : node tests/navigateur/consultation.cjs  (depuis apps/web ; requiert playwright, php, node). Sort en code 1 au premier échec.
   Preuves : la clé saisie n'est JAMAIS envoyée au serveur (toutes les requêtes sont interceptées et fouillées), une fausse clé est refusée, les dossiers
   s'affichent déchiffrés, la recherche filtre, une copie plus récente remplace la précédente, l'archivage s'affiche. */
const { spawn, execFileSync } = require('node:child_process');
const fs = require('node:fs'); const os = require('node:os'); const path = require('node:path');
const { chiffrer } = require('../../../../packages/sync/banc/crypto');
const { chromium } = require('playwright');

const PORT = 18000 + Math.floor(Math.random() * 1000); const BASE = `http://127.0.0.1:${PORT}`; const SECRET = 'secret-navigateur';
const CLE = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90'; const CLE_FAUSSE = 'ff'.repeat(32);
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'relais-nav-')); const dbf = path.join(dir, 'relais.sqlite'); fs.writeFileSync(dbf, '');
const env = Object.assign({}, process.env, { DB_CONNECTION: 'sqlite', DB_DATABASE: dbf, RELAIS_SECRET_MERE: SECRET, APP_ENV: 'local', SESSION_DRIVER: 'file', CACHE_STORE: 'file' });
let bon = 0; let mauvais = 0;
const verifier = (l, ok, d) => { if (ok) { bon++; console.log('   ✓ ' + l); } else { mauvais++; console.log('   ✗ ' + l + (d !== undefined ? '  → ' + JSON.stringify(d) : '')); } };
const art = (...a) => execFileSync('php', ['artisan', ...a], { env, cwd: path.join(__dirname, '..', '..'), encoding: 'utf8' });
const json = async (m, p, corps, h) => { const r = await fetch(BASE + p, { method: m, headers: Object.assign({ 'content-type': 'application/json', accept: 'application/json' }, h || {}), body: corps ? JSON.stringify(corps) : undefined }); return { status: r.status, json: await r.json().catch(() => ({})) }; };

(async () => {
  art('migrate', '--force'); art('relais:superadmin', 'nav@exemple.bj', '--mot-de-passe=motdepasse-nav');
  const srv = spawn('php', ['artisan', 'serve', '--host=127.0.0.1', `--port=${PORT}`], { env, cwd: path.join(__dirname, '..', '..'), stdio: 'ignore', detached: true });
  let navigateur;
  try {
    for (let i = 0; i < 60; i++) { try { await fetch(BASE + '/panneau/connexion'); break; } catch (e) { await new Promise((r) => setTimeout(r, 250)); } }
    // un poste appairé dépose sa copie (au format réel des postes)
    const uuid = 'poste-nav-1'; const code = 'CODE-NAV';
    await json('POST', '/mere/code', { hash: require('node:crypto').createHash('sha256').update(code).digest('hex') }, { 'x-mere': SECRET });
    const jeton = (await json('POST', '/appairage', { code, uuid })).json.jeton; const auth = { Authorization: 'Bearer ' + jeton };
    const cle = Buffer.from(CLE, 'hex'); let n = 0;
    const deposer = async (charge) => { n += 1; const r = await json('POST', '/depot', { enveloppe: chiffrer(cle, charge, { id: `${uuid}-copie-${n}`, appareil: uuid, dir: 'copie', n }) }, auth); if (r.status !== 200) throw new Error('dépôt refusé ' + JSON.stringify(r)); };
    await deposer({ collection: 'patients', fiche: 'p1', data: { nom: 'AKPO', prenom: 'Awa', tel: '90' }, archive: false });
    await deposer({ collection: 'patients', fiche: 'p2', data: { nom: 'KOUA', prenom: 'Bio' }, archive: false });
    await deposer({ collection: 'patients', fiche: 'p1', data: { nom: 'AKPO', prenom: 'Awa', tel: '91' }, archive: false }); // version plus récente
    await deposer({ collection: 'patients', fiche: 'p2', data: { nom: 'KOUA', prenom: 'Bio' }, archive: true });              // archivée
    await deposer({ lot: [{ collection: 'patients', fiche: 'p3', data: { nom: 'DOSSOU', prenom: 'Zeb' }, archive: false }] });  // lot de la mère

    navigateur = await chromium.launch({ args: ['--no-sandbox'] });
    const page = await (await navigateur.newContext({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 1 })).newPage();
    const requetes = []; page.on('request', (r) => requetes.push({ url: r.url(), corps: r.postData() || '' }));
    const erreursJs = []; page.on('pageerror', (e) => erreursJs.push(String(e)));

    await page.goto(BASE + '/panneau/connexion');
    await page.fill('#courriel', 'nav@exemple.bj'); await page.fill('#mot_de_passe', 'motdepasse-nav');
    await Promise.all([page.waitForURL(/\/panneau\/?$/), page.click('button[type=submit]')]);
    await page.goto(BASE + '/panneau/consultation');
    await page.waitForSelector('input[aria-label="Clé de la clinique"]');
    verifier('la page de consultation s\'ouvre pour le superadmin connecté', true);

    // 1. fausse clé : refusée, aucun dossier
    await page.fill('input[aria-label="Clé de la clinique"]', CLE_FAUSSE);
    await page.click('text=Charger et déchiffrer');
    await page.waitForFunction(() => /illisible|refus|incorrecte|invalide|échec/i.test(document.querySelector('[role=status]').textContent), null, { timeout: 15000 }).catch(() => {});
    const msgFausse = (await page.textContent('[role=status]')).trim();
    verifier('une fausse clé est refusée en le disant, aucun dossier n\'apparaît', /illisible|refus|incorrecte|invalide|échec/i.test(msgFausse) && (await page.locator('tbody tr').count()) === 0, msgFausse);

    // 2. bonne clé : les dossiers sont déchiffrés
    await page.fill('input[aria-label="Clé de la clinique"]', CLE);
    await page.click('text=Charger et déchiffrer');
    await page.waitForSelector('tbody tr', { timeout: 15000 });
    const lignes = await page.locator('tbody tr').allTextContents();
    const texte = lignes.join(' | ');
    verifier('la bonne clé affiche les dossiers déchiffrés (trois fiches, lot de la mère compris)', lignes.length === 3 && /AKPO/.test(texte) && /KOUA/.test(texte) && /DOSSOU/.test(texte), lignes);
    verifier('la version la plus récente remplace la précédente (tel 91, pas 90)', /91/.test(texte) && !/\b90\b/.test(texte), texte);
    const archives = await page.locator('tbody tr', { hasText: 'KOUA' }).locator('td').nth(2).textContent();
    verifier('l\'archivage s\'affiche (p2 archivée : oui)', archives.trim() === 'oui', archives);

    // 3. recherche
    await page.fill('input[aria-label="Rechercher un dossier"]', 'DOSSOU');
    await page.waitForFunction(() => document.querySelectorAll('tbody tr').length === 1);
    verifier('la recherche filtre les dossiers', (await page.locator('tbody tr').count()) === 1);
    await page.screenshot({ path: path.join(dir, 'consultation.png') });

    // 4. la clé ne part JAMAIS au serveur
    const fouille = requetes.filter((r) => r.url.startsWith(BASE));
    const fuite = fouille.filter((r) => r.corps.includes(CLE) || r.corps.includes(CLE_FAUSSE) || r.url.includes(CLE) || r.url.includes(CLE_FAUSSE) || r.url.includes('cle='));
    verifier('la clé saisie (bonne et fausse) n\'apparaît dans AUCUNE requête vers le serveur', fouille.length > 3 && fuite.length === 0, fuite.map((r) => r.url));
    const stockage = await page.evaluate(() => JSON.stringify([Object.entries(localStorage), Object.entries(sessionStorage)]));
    verifier('la clé n\'est écrite ni dans localStorage ni dans sessionStorage', !stockage.includes('a1b2c3d4e5f6'));
    verifier('aucune erreur JavaScript dans la page', erreursJs.length === 0, erreursJs);

    // 5. recharger oublie la clé
    await page.reload(); await page.waitForSelector('input[aria-label="Clé de la clinique"]');
    verifier('recharger la page oublie la clé et les dossiers', (await page.inputValue('input[aria-label="Clé de la clinique"]')) === '' && (await page.locator('tbody tr').count()) === 0);
    console.log('   capture : ' + path.join(dir, 'consultation.png'));
  } finally {
    if (navigateur) await navigateur.close();
    try { process.kill(-srv.pid, 'SIGKILL'); } catch (e) { srv.kill('SIGKILL'); } /* `artisan serve` lance un serveur fils : on tue le groupe */
  }
  console.log(`\n══ ${bon} vérifications vertes, ${mauvais} échec(s) ══`);
  process.exit(mauvais ? 1 : 0);
})().catch((e) => { console.error('ERREUR', e); process.exit(2); });
