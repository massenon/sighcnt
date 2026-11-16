'use strict';
/* LA PAGE PUBLIQUE DANS UN VRAI CHROME (lot SAT, ADR-0009) : sert le VRAI relais Laravel (serveur intégré, SQLite jetable), publie un lien, remplit le formulaire, clique « Envoyer » et CAPTURE
 * l'enveloppe réellement postée. Elle sert de vecteur à `packages/sync_dart/test/satisfaction_navigateur_test.dart` (ouverture par la mère Dart d'une enveloppe fabriquée par WebCrypto).
 *   SAT_CLE_PUBLIQUE=<base64> node tests/navigateur/satisfaction.cjs <sortie.json> */
const { spawn, spawnSync } = require('node:child_process');
const fs = require('node:fs'), path = require('node:path'), os = require('node:os'), http = require('node:http');
const WEB = path.resolve(__dirname, '..', '..');
const PORT = +(process.env.SAT_PORT || 9808);
const SORTIE = process.argv[2];
const CLE = process.env.SAT_CLE_PUBLIQUE;
if (!SORTIE || !CLE) { console.error('usage : SAT_CLE_PUBLIQUE=<base64> node satisfaction.cjs <sortie.json>'); process.exit(2); }
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sigh-sat-nav-'));
const DB = path.join(dir, 'relais.sqlite'); fs.closeSync(fs.openSync(DB, 'a'));
const env = Object.assign({}, process.env, { APP_KEY: 'base64:' + Buffer.alloc(32, 7).toString('base64'), APP_ENV: 'local', APP_DEBUG: 'false', DB_CONNECTION: 'sqlite', DB_DATABASE: DB, SESSION_DRIVER: 'array', CACHE_STORE: 'array', QUEUE_CONNECTION: 'sync', LOG_CHANNEL: 'stderr', RELAIS_SECRET_MERE: 'secret-mere' });
const amorce = path.join(WEB, 'tests/outils/amorce_arbre.php');
const m = spawnSync('php', ['-d', 'auto_prepend_file=' + amorce, 'artisan', 'migrate', '--force', '--no-interaction'], { cwd: WEB, env, encoding: 'utf8' });
if (m.status !== 0) { console.error(m.stderr || m.stdout); process.exit(3); }
const php = spawn('php', ['-S', '127.0.0.1:' + PORT, '-t', '.', path.join(WEB, 'tests/outils/routeur_arbre.php')], { cwd: path.join(WEB, 'public'), env, stdio: 'ignore' });
const fin = (code) => { try { php.kill('SIGKILL'); } catch (e) { /* mort */ } fs.rmSync(dir, { recursive: true, force: true }); process.exit(code); };
const appeler = (methode, chemin, corps) => new Promise((ok, ko) => {
  const r = http.request({ host: '127.0.0.1', port: PORT, path: chemin, method: methode, headers: { 'x-mere': 'secret-mere', 'Content-Type': 'application/json' } }, (rep) => { let t = ''; rep.on('data', (c) => (t += c)); rep.on('end', () => ok({ statut: rep.statusCode, corps: t })); });
  r.on('error', ko); if (corps) r.write(JSON.stringify(corps)); r.end();
});
(async () => {
  for (let i = 0; i < 80; i++) { try { await appeler('GET', '/up'); break; } catch (e) { await new Promise((r) => setTimeout(r, 150)); } }
  const jeton = 'jetonnavigateur0123456789';
  const charge = { enquete: 'ENQ0001', version: 'V1', point: { code: 'accueil', libelle: 'Accueil' }, titre: 'Votre avis', intro: 'Merci',
    questions: [{ code: 'Q_A', type: 'note', libelle: 'Accueil', obligatoire: true }, { code: 'Q_R', type: 'choix', libelle: 'Recommanderiez-vous ?', options: ['Oui', 'Non'], obligatoire: true }, { code: 'Q_T', type: 'texte', libelle: 'Avis', obligatoire: false }] };
  const emp = require('node:crypto').createHash('sha256').update(jeton).digest('hex');
  const pub = await appeler('POST', '/satisfaction/publier', { cle: CLE, liens: [{ empreinte: emp, charge }] });
  if (pub.statut !== 200) throw new Error('publication : ' + pub.corps);
  const { chromium } = (() => { try { return require('playwright'); } catch (e) { return require(path.join(WEB, '..', '..', 'prototype_html', 'node_modules', 'playwright')); } })();
  const nav = await chromium.launch();
  const page = await nav.newPage({ viewport: { width: 390, height: 800 } });
  const cookies = []; page.on('response', (r) => { const h = r.headers()['set-cookie']; if (h) cookies.push(h); });
  let poste = null;
  await page.route('**/s/' + jeton, async (route) => { if (route.request().method() === 'POST') poste = JSON.parse(route.request().postData()); await route.continue(); });
  await page.goto(`http://127.0.0.1:${PORT}/s/${jeton}`);
  await page.waitForSelector('#questions fieldset');
  await page.check('input[name="Q_A"][value="5"]');
  await page.check('input[name="Q_R"][value="Oui"]');
  await page.fill('#q_Q_T', 'Très bon accueil, merci');
  await page.click('#envoyer');
  await page.waitForSelector('#merci', { timeout: 10000 });
  const titre = await page.title(); const mention = await page.textContent('body');
  // un envoi vide est refusé par la page, sans appel réseau
  await nav.close();
  if (!poste) throw new Error('aucune enveloppe capturée');
  const clairAttendu = { enquete: 'ENQ0001', version: 'V1', point: 'accueil', langue: 'fr', reponses: { Q_A: 5, Q_R: 'Oui', Q_T: 'Très bon accueil, merci' } };
  fs.writeFileSync(SORTIE, JSON.stringify({ _doc: 'ENGENDRÉ par apps/web/tests/navigateur/satisfaction.cjs : l’enveloppe réellement postée par la page publique dans Chrome. Clé de test du banc.', jeton, cle: CLE, enveloppe: poste, clairAttendu, cookies, titre }, null, 1));
  console.log('enveloppe capturée : id=' + poste.id + ' ct=' + poste.ct.length + ' cookies=' + cookies.length + ' titre=' + titre);
  fin(0);
})().catch((e) => { console.error(e); fin(1); });
