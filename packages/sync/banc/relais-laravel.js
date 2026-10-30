'use strict';
/* =============================================================================
 * Adaptateur : fait tourner le VRAI relais Laravel (apps/web) à la place de relais.js,
 * pour rejouer les MÊMES scénarios du banc contre le code destiné au cPanel.
 *
 *   SIGH_RELAIS=laravel node --no-warnings banc/run.js R6 R13 R23
 *
 * Même contrat que relais.js : --port --db --banc --seuil-battement ; signale `pret` par IPC.
 * Base : un SQLite jetable migré par `php artisan migrate` ; serveur : le serveur intégré de PHP.
 * ========================================================================== */
const { spawn, spawnSync } = require('node:child_process');
const path = require('node:path');
const http = require('node:http');
const arg = (n, d) => { const a = process.argv.find((x) => x.startsWith('--' + n + '=')); return a ? a.split('=').slice(1).join('=') : d; };
const PORT = +arg('port', 0); const DB = arg('db', '/tmp/relais.sqlite');
const WEB = path.resolve(__dirname, '..', '..', '..', 'apps', 'web');
const env = Object.assign({}, process.env, {
  APP_KEY: 'base64:' + require('node:crypto').randomBytes(32).toString('base64'), APP_ENV: 'local', APP_DEBUG: 'false', DB_CONNECTION: 'sqlite', DB_DATABASE: DB, SESSION_DRIVER: 'array', CACHE_STORE: 'array', QUEUE_CONNECTION: 'sync',
  LOG_CHANNEL: 'stderr', RELAIS_SECRET_MERE: 'secret-mere', RELAIS_SEUIL_BATTEMENT_MS: arg('seuil-battement', '300000'), RELAIS_BANC: arg('banc', '0') === '1' ? 'true' : 'false',
});
require('node:fs').closeSync(require('node:fs').openSync(DB, 'a'));
const m = spawnSync('php', ['artisan', 'migrate', '--force', '--no-interaction'], { cwd: WEB, env, encoding: 'utf8' });
if (m.status !== 0) { console.error('migration impossible : ' + (m.stderr || m.stdout)); process.exit(2); }
/* Comme `php artisan serve` : le serveur intégré tourne DEPUIS public/, avec le routeur de Laravel. */
const php = spawn('php', ['-S', `127.0.0.1:${PORT}`, '-t', '.', path.join(WEB, 'vendor/laravel/framework/src/Illuminate/Foundation/resources/server.php')],
  { cwd: path.join(WEB, 'public'), env, stdio: ['ignore', 'ignore', 'ignore'] });
const fin = () => { try { php.kill('SIGKILL'); } catch (e) { /* déjà arrêté */ } process.exit(0); };
process.on('SIGTERM', fin); process.on('exit', () => { try { php.kill('SIGKILL'); } catch (e) { /* déjà arrêté */ } });
(function attendre(essais) {
  http.get({ host: '127.0.0.1', port: PORT, path: '/up', timeout: 800 }, (r) => { r.resume(); if (process.send) process.send({ pret: true, port: PORT }); })
    .on('error', () => { if (essais > 60) process.exit(3); setTimeout(() => attendre(essais + 1), 150); });
})(0);
