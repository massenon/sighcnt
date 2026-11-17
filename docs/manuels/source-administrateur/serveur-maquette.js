/* Serveur ISOLÉ de la maquette pour les captures du manuel administrateur.
   Base jetable à soi (SIGH_BASE_TEST), port PHP et port HTTP à soi. Jamais sigh_cnt ni sigh_prototype.
   Usage : SIGH_PORT_PHP=8327 SIGH_PORT_MANUEL=8328 SIGH_BASE_TEST=sigh_manadm_essai node serveur-maquette.js (reste vivant ; Ctrl+C l'arrête). */
'use strict';
process.env.SIGH_PORT_PHP = process.env.SIGH_PORT_PHP || '8327';
process.env.SIGH_BASE_TEST = process.env.SIGH_BASE_TEST || 'sigh_manadm_essai';
const os = require('os');
const path = require('path');
const fs = require('fs');
const http = require('http');
const DOSSIER = path.join(os.tmpdir(), 'sigh-manadm');
for (const [v, d] of [['SIGH_FICHIERS_DIR', 'fichiers'], ['SIGH_SAUVEGARDES_DIR', 'sauvegardes'], ['SIGH_SMS_DIR', 'sms']]) {
  if (!process.env[v]) { const p = path.join(DOSSIER, d); fs.mkdirSync(p, { recursive: true }); process.env[v] = p; }
}
const ROOT = path.resolve(__dirname, '../../../prototype_html');
const BANC = require(path.join(ROOT, 'build/_banc.js'));
const PORT = Number(process.env.SIGH_PORT_MANUEL || 8328);
const MIME = { '.php': 'text/html; charset=utf-8', '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.woff2': 'font/woff2', '.jpeg': 'image/jpeg', '.png': 'image/png', '.svg': 'image/svg+xml', '.json': 'application/json' };
(async () => {
  const php = await BANC.demarrerPhp(ROOT);
  if (!php.php) { console.error('ÉCHEC : ' + php.raison); process.exit(1); }
  if (!process.env.GARDER) {
    const v = await BANC.banc('reinitialiser');
    if (v.erreur) { console.error('ÉCHEC base : ' + (v.detail || v.erreur)); php.php.kill(); process.exit(1); }
    console.log('Base « ' + v.base + ' » remise à neuf.');
  }
  const srv = http.createServer((req, res) => {
    if (req.url.indexOf('/api/') === 0) { BANC.relayer(req, res); return; }
    const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '') || 'index.php';
    const file = path.join(ROOT, rel);
    if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  }).listen(PORT, '127.0.0.1');
  console.log('Maquette servie sur http://127.0.0.1:' + PORT + '/ (PHP ' + process.env.SIGH_PORT_PHP + ', base ' + process.env.SIGH_BASE_TEST + ')');
  const fin = () => { try { php.php.kill(); } catch (e) { /* déjà arrêté */ } srv.close(); process.exit(0); };
  process.on('SIGINT', fin); process.on('SIGTERM', fin);
})();
