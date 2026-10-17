/* =============================================================================
 * SIGH-CNT — Servir le prototype AVEC sa base
 * -----------------------------------------------------------------------------
 * Les pages sont en `.php` et l'API des données vit dans `api/` : il faut donc
 * un serveur qui exécute PHP, et il faut qu'il serve les DEUX depuis la même
 * origine — sinon le navigateur refuse la requête, et l'on passerait le reste
 * de la journée sur des en-têtes CORS.
 *
 * ON UTILISE LE SERVEUR INTÉGRÉ DE PHP, et non Apache, pour une raison
 * pratique : démarrer Apache suppose de redémarrer Laragon, donc d'interrompre
 * les autres sites locaux du poste. Le serveur intégré ne demande rien à
 * personne, s'arrête avec Ctrl+C, et sert exactement les mêmes fichiers.
 *
 * Apache reste possible et n'exige rien de plus : une jonction
 * `C:\laragon\www\sigh` vers ce dossier suffit, à condition que le PHP
 * d'Apache charge `pdo_pgsql`.
 *
 *   node build/serveur.js            → http://127.0.0.1:8080
 *   node build/serveur.js 9000       → sur un autre port
 *   SIGH_PHP=... node build/serveur.js  → avec un autre binaire PHP
 * ========================================================================== */
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const PORT = Number(process.argv[2]) || Number(process.env.SIGH_PORT_WEB) || 8080;

/** Le binaire PHP : celui qu'on nous donne, sinon le plus récent de Laragon. */
function trouverPhp() {
  if (process.env.SIGH_PHP && fs.existsSync(process.env.SIGH_PHP)) return process.env.SIGH_PHP;
  const base = 'C:/laragon/bin/php';
  if (fs.existsSync(base)) {
    const versions = fs.readdirSync(base)
      .filter((d) => fs.existsSync(path.join(base, d, 'php.exe')))
      .sort();
    if (versions.length) return path.join(base, versions[versions.length - 1], 'php.exe');
  }
  return 'php';
}

const php = trouverPhp();
console.log('PHP        : ' + php);
console.log('Racine     : ' + ROOT);
console.log('Adresse    : http://127.0.0.1:' + PORT + '/index.php');
console.log('API        : http://127.0.0.1:' + PORT + '/api/magasin.php');
console.log('');
console.log('Le magasin vit dans PostgreSQL (base `sigh_prototype`).');
console.log('Sans ce serveur, le prototype retombe sur le stockage du navigateur.');
console.log('Ctrl+C pour arrêter.');
console.log('');

const proc = spawn(php, ['-S', '127.0.0.1:' + PORT, '-t', ROOT], { stdio: 'inherit' });
proc.on('exit', (code) => process.exit(code == null ? 0 : code));
process.on('SIGINT', () => { proc.kill(); process.exit(0); });
