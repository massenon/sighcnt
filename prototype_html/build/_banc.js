/* =============================================================================
 * SIGH-CNT — LE SERVEUR PHP DES BANCS D'ESSAI
 * -----------------------------------------------------------------------------
 * Depuis que la donnée métier vit en base et que le navigateur n'écrit plus
 * rien, un banc d'essai qui servirait les pages en statique n'éprouverait
 * RIEN : le magasin resterait vide et chaque scénario échouerait sans rapport
 * avec ce qu'il mesure. Les bancs ont donc besoin d'un vrai serveur PHP.
 *
 * DEUX DÉCISIONS, ET LA SECONDE EST LA PLUS IMPORTANTE :
 *
 *   1. Le serveur intégré de PHP est MONO-PROCESSUS : lui faire servir les
 *      quinze scripts de chacune des trois cents pages multiplierait la durée
 *      du contrôle. Node continue donc de servir les FICHIERS, vite, et ne
 *      relaie que `/api/` vers PHP — quelques appels par page.
 *
 *   2. Le banc tourne sur une base JETABLE, jamais sur celle de travail. Son
 *      nom doit porter « test », « essai » ou « banc » : `api/banc.php` refuse
 *      d'en vider une autre. Une variable d'environnement mal posée ne doit
 *      pas effacer le travail de la clinique.
 * ========================================================================== */
'use strict';

const http = require('http');
const { spawn, spawnSync } = require('child_process');

const PORT_PHP = Number(process.env.SIGH_PORT_PHP || 8099);
const BASE_TEST = process.env.SIGH_BASE_TEST || 'sigh_prototype_test';

/** Le compte dont les bancs endossent l'identité par défaut. */
const SESSION_BANC = {
  role: 'admin', nom: 'BASSONGUI Chabi Séko', poste: 'Administrateur système',
  identifiant: 'c.bassongui', fonction: 'direction', secteur: 'ADM',
};

function attendre(ms) { return new Promise((r) => setTimeout(r, ms)); }

/** Vrai si le port répond. */
function joignable(port) {
  return new Promise((resolve) => {
    const q = http.get({ host: '127.0.0.1', port: port, path: '/api/banc.php?action=etat', timeout: 1500 },
      (r) => { r.resume(); resolve(r.statusCode > 0); });
    q.on('error', () => resolve(false));
    q.on('timeout', () => { q.destroy(); resolve(false); });
  });
}

/**
 * Démarre le serveur PHP du banc. Retourne de quoi l'arrêter, ou `null` si PHP
 * n'est pas sur le poste — le banc le DIT alors plutôt que de prétendre avoir
 * éprouvé quelque chose.
 */
async function demarrerPhp(racine) {
  const essai = spawnSync('php', ['-v'], { encoding: 'utf8' });
  if (essai.error) {
    return { php: null, raison: 'PHP est absent du PATH : les scénarios ne peuvent pas '
      + 'être éprouvés contre la base.' };
  }
  const proc = spawn('php', ['-S', '127.0.0.1:' + PORT_PHP, '-t', racine], {
    cwd: racine,
    env: Object.assign({}, process.env, { SIGH_BASE: BASE_TEST, SIGH_BANC: '1' }),
    stdio: ['ignore', 'ignore', 'ignore'],
  });
  for (let i = 0; i < 40; i++) {
    await attendre(250);
    if (await joignable(PORT_PHP)) return { php: proc, raison: null };
  }
  try { proc.kill(); } catch (e) { /* déjà mort */ }
  return { php: null, raison: 'Le serveur PHP du banc n’a pas répondu sur le port ' + PORT_PHP + '.' };
}

/** Appelle `api/banc.php` et rend sa réponse. */
function banc(action) {
  return new Promise((resolve) => {
    const corps = JSON.stringify({ action: action });
    const q = http.request({ host: '127.0.0.1', port: PORT_PHP, path: '/api/banc.php',
      method: 'POST', headers: { 'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(corps) } },
    (r) => { let d = ''; r.on('data', (c) => { d += c; });
      r.on('end', () => { try { resolve(JSON.parse(d)); } catch (e) { resolve({ erreur: d.slice(0, 120) }); } }); });
    q.on('error', (e) => resolve({ erreur: e.message }));
    q.end(corps);
  });
}

/** Relaie une requête `/api/...` vers le serveur PHP. */
function relayer(req, res) {
  const morceaux = [];
  req.on('data', (c) => morceaux.push(c));
  req.on('end', () => {
    const corps = Buffer.concat(morceaux);
    const entetes = Object.assign({}, req.headers);
    delete entetes.host;
    delete entetes['accept-encoding'];
    if (corps.length) entetes['content-length'] = corps.length;
    const q = http.request({ host: '127.0.0.1', port: PORT_PHP, path: req.url,
      method: req.method, headers: entetes }, (r) => {
      res.writeHead(r.statusCode, r.headers);
      r.pipe(res);
    });
    q.on('error', (e) => {
      res.writeHead(502, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ erreur: 'relais', detail: e.message }));
    });
    if (corps.length) q.write(corps);
    q.end();
  });
}

/** Le banc S'AUTHENTIFIE POUR DE VRAI : il n'injecte pas un jeton, il en
 *  demande un à `auth.php`, qui vérifie le haché comme pour un agent. Le
 *  jeton est retenu pour toute l'exécution. */
var _jetonBanc = null;
function connecter(identifiant, motDePasse) {
  return new Promise((resolve) => {
    const corps = JSON.stringify({ action: 'connexion', identifiant: identifiant,
      motDePasse: motDePasse || 'demonstration', poste: 'banc d’essai' });
    const q = http.request({ host: '127.0.0.1', port: PORT_PHP, path: '/api/auth.php',
      method: 'POST', headers: { 'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(corps) } },
    (r) => { let d = ''; r.on('data', (c) => { d += c; });
      r.on('end', () => { try { resolve(JSON.parse(d)); } catch (e) { resolve({ erreur: d.slice(0, 120) }); } }); });
    q.on('error', (e) => resolve({ erreur: e.message }));
    q.end(corps);
  });
}

/**
 * Pose la session du banc AVANT que la page ne s'exécute.
 *
 * Sans elle, le magasin ne sème pas : il attend une session (RG-12 — rien ne
 * s'écrit sans auteur), et le banc ouvrirait trois cents pages vides.
 *
 * ON POSE AUSSI LE JETON, et c'est ce qui évite un 401 à chaque première
 * écriture : sans lui, le serveur refuse (à raison), le magasin rejoue après
 * avoir ouvert une session, et le navigateur journalise au passage une erreur
 * de console que le contrôle compterait comme une anomalie — alors que rien
 * n'a échoué.
 */
async function poserSession(page, session) {
  const s = Object.assign({}, session || SESSION_BANC);
  if (!_jetonBanc) {
    const r = await connecter(s.identifiant || SESSION_BANC.identifiant);
    _jetonBanc = (r && r.jeton) || null;
  }
  if (_jetonBanc) s.jeton = _jetonBanc;
  await page.evaluateOnNewDocument((sess, jeton) => {
    try {
      if (!localStorage.getItem('sigh-cnt:session')) {
        localStorage.setItem('sigh-cnt:session', JSON.stringify(sess));
      }
      if (jeton && !localStorage.getItem('sigh-cnt:jeton')) {
        localStorage.setItem('sigh-cnt:jeton', jeton);
      }
    } catch (e) { /* stockage indisponible : la page le dira */ }
  }, s, _jetonBanc);
}

module.exports = { PORT_PHP, BASE_TEST, SESSION_BANC, demarrerPhp, banc, relayer, poserSession, connecter };
