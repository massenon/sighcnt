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
/* La date du jeu de démonstration : « aujourd'hui » pour toute page ouverte par un banc. */
const HORLOGE_BANC = { annee: 2026, mois: 7, jour: 16 };
/* Le DÉCALAGE est calculé UNE fois, ici : recalculé à chaque document, l'horloge se
   re-piquait à 12:00:00 à chaque navigation — une fiche créée sur la page suivante
   devenait antérieure à celle de la page précédente. */
const DECALAGE_BANC = new Date(HORLOGE_BANC.annee, HORLOGE_BANC.mois, HORLOGE_BANC.jour, 12, 0, 0).getTime() - Date.now();

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
      /* LA RÉPONSE EST MISE EN TAMPON, PUIS RENVOYÉE AVEC SA LONGUEUR (vague 68).
         Le serveur intégré de PHP répond « Connection: close » SANS Content-Length
         (il termine son corps en fermant la connexion) ; recopier ces en-têtes
         et recoder le corps de 5 Mo en morceaux faisait qu'environ une fois sur
         quarante le navigateur ne voyait JAMAIS la fin du corps — sans erreur,
         sans requête échouée. L'hydratation restait pendante, la page restait
         blanche, et le banc attendait 150 s en silence avant de compter chaque
         assertion comme fausse (« bouton absent », « 16/17 tableaux »). Défaut
         préexistant au commit 77393f8, reproduit sur l'arbre 1a82f80. */
      const morceauxR = [];
      r.on('data', (c) => morceauxR.push(c));
      r.on('end', () => {
        const corpsR = Buffer.concat(morceauxR);
        const entetesR = Object.assign({}, r.headers);
        delete entetesR.connection;
        delete entetesR['transfer-encoding'];
        delete entetesR['keep-alive'];
        entetesR['content-length'] = corpsR.length;
        res.writeHead(r.statusCode, entetesR);
        res.end(corpsR);
      });
      r.on('error', (e) => {
        try {
          res.writeHead(502, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ erreur: 'relais', detail: e.message }));
        } catch (e2) { /* réponse déjà partie */ }
      });
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
  await page.evaluateOnNewDocument((sess, jeton, horloge, decalage) => {
    try {
      if (!localStorage.getItem('sigh-cnt:session')) {
        localStorage.setItem('sigh-cnt:session', JSON.stringify(sess));
      }
      if (jeton && !localStorage.getItem('sigh-cnt:jeton')) {
        localStorage.setItem('sigh-cnt:jeton', jeton);
      }
    } catch (e) { /* stockage indisponible : la page le dira */ }
    /* L'HORLOGE DU BANC EST DÉCALÉE SUR LA DATE DU JEU (vague 68, 20/10/2026).
       L'application lit l'horloge RÉELLE (`C.aujourdhui()`) ; le jeu de
       démonstration, lui, est daté du 16/08/2026 et c'est à cette date que les
       1 091 vérifications ont été écrites. Le banc DÉCALE donc le temps de la
       page pour qu'« aujourd'hui » tombe ce jour-là — le temps continue de
       s'écouler (identifiants, minuteries, journal), seul le point de départ
       change. Un scénario peut déplacer l'horloge par `window.__SIGH_HORLOGE`. */
    try {
      var Reel = window.Date;
      var etat = { decalage: decalage };
      function maintenant() { return Reel.now() + etat.decalage; }
      function Decalee() {
        if (!(this instanceof Decalee)) return String(new Reel(maintenant()));
        if (arguments.length === 0) return new Reel(maintenant());
        return new (Function.prototype.bind.apply(Reel, [null].concat(Array.prototype.slice.call(arguments))))();
      }
      Decalee.prototype = Reel.prototype;
      Decalee.now = maintenant;
      Decalee.UTC = Reel.UTC;
      Decalee.parse = Reel.parse;
      window.Date = Decalee;
      window.__SIGH_HORLOGE = {
        reel: Reel,
        instant: maintenant,
        decaler: function (ms) { etat.decalage += ms; },
        poser: function (annee, mois, jour) {
          etat.decalage = new Reel(annee, mois, jour, 12, 0, 0).getTime() - Reel.now();
        },
      };
    } catch (e) { /* sans horloge décalée, la page tourne à l'heure réelle */ }
  }, s, _jetonBanc, HORLOGE_BANC, DECALAGE_BANC);
}

module.exports = { PORT_PHP, BASE_TEST, SESSION_BANC, HORLOGE_BANC, demarrerPhp, banc, relayer, poserSession, connecter };
