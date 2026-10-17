/* =============================================================================
 * SIGH-CNT — LE RUBAN RÉEL, CONFRONTÉ À LA CIBLE
 * -----------------------------------------------------------------------------
 * `newdocs/CIBLE-SIDEBAR-PAR-ROLE.md` dit ce que chaque poste DOIT voir. Ce
 * banc dit ce qu'il VOIT — en appelant `N.tree(role)`, la fonction même
 * qu'emploie le ruban, avec le magasin chargé depuis la base.
 *
 * TROIS ÉCARTS SE DISTINGUENT, ET LES CONFONDRE N'APPRENDRAIT RIEN :
 *   MANQUE   — la cible le demande, l'agent ne l'a pas. C'est un travail
 *              empêché : il ira le chercher ailleurs, ou le refera à la main.
 *   EN TROP  — l'agent l'a, la cible ne le demande pas. C'est une question de
 *              cloisonnement (RG-13), pas de confort.
 *   LIBELLÉ  — le même écran, nommé autrement. Ce n'est pas un défaut de
 *              droits : c'est un défaut de vocabulaire, et il se corrige au
 *              manifeste.
 * ========================================================================== */
'use strict';

const fs = require('fs');
const path = require('path');
const http = require('http');
const puppeteer = require('puppeteer');
const BANC = require('./_banc');

const ROOT = path.resolve(__dirname, '..');
const PORT = Number(process.env.SIGH_PORT_CIBLE || 8079);
const CIBLE = path.resolve(ROOT, '..', 'newdocs', 'CIBLE-SIDEBAR-PAR-ROLE.md');

/* Le poste nommé dans le document → l'identifiant technique du manifeste. */
const ROLES = {
  'Administrateur système': 'admin',
  'Directrice de l’Administration et des Finances': 'da',
  'Médecin': 'medecin',
  'Infirmier / Sage-femme': 'infirmier',
  'Aide-soignante': 'aide_soignant',
  'Biologiste médical': 'laborantin',
  'Gestionnaire de Stock': 'stock',
  'Comptable': 'comptable',
  'Caissier / Dispensaire': 'caissier',
  'Réception / Accueil': 'reception',
  'Technicien d’échographie': 'echographiste',
  'Surveillant': 'surveillant',
  'Assistant de Direction': 'assistant_comptable',
  'Chirurgien': 'chirurgien',
};

/* Les libellés diffèrent parfois d'une apostrophe ou d'une espace : on
   compare sur une forme normalisée, sans quoi l'audit crierait au loup pour
   une typographie. DÉCLARÉE ICI, avant tout ce qui la lit. */
function clef(s) {
  return String(s).normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .replace(/[’']/g, "'")
    /* « & » ET « et » SONT LE MÊME MOT. Sans cette équivalence, l'audit
       comptait « Prescripteurs et exécutants » comme MANQUANT et
       « Prescripteurs & exécutants » comme EN TROP — deux écarts annoncés
       pour un écran parfaitement en place. Un audit qui crie au loup sur une
       esperluette finit par être ignoré. */
    .replace(/\s*&\s*/g, ' et ')
    .replace(/\s+/g, ' ').trim().toLowerCase();
}

/* --- Lecture de la cible -------------------------------------------------- */
const inconnus = [];
function lireCible() {
  const texte = fs.readFileSync(CIBLE, 'utf8');
  const cible = {};
  let poste = null;
  for (const ligne of texte.split(/\r?\n/)) {
    const titre = /^##\s+\d+\.\s+(.+?)\s+—/.exec(ligne);
    if (titre) {
      const nom = titre[1].trim();
      /* PAR LA FORME NORMALISÉE, jamais par la chaîne brute : le document
         porte une apostrophe droite là où la table en attendait une
         typographique, et DEUX postes étaient silencieusement sautés. */
      poste = null;
      Object.keys(ROLES).forEach((k) => { if (clef(k) === clef(nom)) poste = ROLES[k]; });
      if (poste) cible[poste] = { nom: nom, ecrans: [] };
      else inconnus.push(nom);
      continue;
    }
    if (!poste) continue;
    /* « - Rangée : écran · écran · écran » */
    const rangee = /^-\s+(.+?)\s*:\s*(.+)$/.exec(ligne);
    if (rangee) {
      rangee[2].split('·').forEach((e) => {
        const l = e.trim();
        if (l) cible[poste].ecrans.push(l);
      });
    }
  }
  return cible;
}

/* --- Serveur : Node pour les fichiers, PHP pour l'API --------------------- */
const MIME = { '.php': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.woff2': 'font/woff2',
  '.png': 'image/png', '.svg': 'image/svg+xml', '.jpg': 'image/jpeg', '.ico': 'image/x-icon' };

function servir() {
  return new Promise((resolve) => {
    const s = http.createServer((req, res) => {
      if (req.url.indexOf('/api/') === 0) { BANC.relayer(req, res); return; }
      const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '') || 'index.php';
      const f = path.join(ROOT, rel);
      if (!f.startsWith(ROOT) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) {
        res.writeHead(404); res.end(); return;
      }
      res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' });
      fs.createReadStream(f).pipe(res);
    });
    s.listen(PORT, () => resolve(s));
  });
}

function trouverChrome() {
  const c = [process.env.CHROME_PATH,
    'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe'];
  for (const p of c) if (p && fs.existsSync(p)) return p;
  return undefined;
}

/* --- Comparaison ---------------------------------------------------------- */

(async () => {
  const cible = lireCible();
  const postes = Object.keys(cible);
  console.log('\n' + '─'.repeat(74));
  console.log('LE RUBAN RÉEL, CONFRONTÉ À LA CIBLE DU 10/10/2026');
  console.log('─'.repeat(74));
  console.log('Postes à vérifier : ' + postes.length
    + (inconnus.length ? '   (NON RECONNUS : ' + inconnus.join(', ') + ')' : '') + '\n');

  const php = await BANC.demarrerPhp(ROOT);
  if (!php.php) { console.error('  ÉCHEC — ' + php.raison); process.exit(1); }
  const vidage = await BANC.banc('reinitialiser');
  if (vidage.erreur) {
    console.error('  ÉCHEC — ' + (vidage.detail || vidage.erreur));
    try { php.php.kill(); } catch (e) { /* déjà mort */ }
    process.exit(1);
  }

  const serveur = await servir();
  const navigateur = await puppeteer.launch({ executablePath: trouverChrome(), headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const page = await navigateur.newPage();
  await BANC.poserSession(page);
  page.setDefaultNavigationTimeout(180000);
  page.setDefaultTimeout(180000);

  await page.goto('http://127.0.0.1:' + PORT + '/pages/dash-admin.php',
    { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => {
    const c = document.getElementById('page-content');
    return !!(window.SIGH && window.SIGH.store && c && c.children.length > 0);
  }, { timeout: 180000 }).catch(() => null);
  await new Promise((r) => setTimeout(r, 4000));

  const reel = await page.evaluate((liste) => {
    const N = window.SIGH.nav;
    const out = {};
    liste.forEach((role) => {
      const ecrans = [];
      const rangees = [];
      const dash = [];
      try {
        N.tree(role).forEach((d) => d.modules.forEach((m) => {
          rangees.push(d.label + ' › ' + m.label);
          m.items.forEach((i) => {
            ecrans.push(i.label);
            if (String(i.id || '').indexOf('dash-') === 0) dash.push(i.label);
          });
        }));
      } catch (e) { /* rôle inconnu : la liste reste vide */ }
      out[role] = { ecrans: ecrans, rangees: rangees, dash: dash };
    });
    return out;
  }, postes);

  let manques = 0, surplus = 0;
  const rapport = [];

  /* CE QUI EST VOULU ET N'EST PAS UN ÉCART. La cible le dit elle-même : elle
     ne couvre ni les hubs, ni les écrans hors ruban. S'y ajoutent deux
     familles portées par des arbitrages antérieurs :
       — la BIBLIOTHÈQUE DES ÉTATS, ouverte à tous parce que le cahier des
         charges fait de l'impression une exigence de CHAQUE poste (vague 67) ;
       — le TABLEAU DE BORD du poste, qui est sa page d'accueil : le fermer
         priverait le rôle de son point d'entrée (doctrine de la vague 37). */
  const TOLERES = ['Bibliothèque des états'];

  postes.forEach((role) => {
    const attendu = cible[role].ecrans;
    /* UN ÉCRAN ALIASÉ NE COMPTE QU'UNE FOIS. Le domaine ACCUEIL réunit des
       écrans de M1/M2/M13 sans les dupliquer — les compter deux fois gonflait
       le surplus sans qu'un seul écran de plus soit offert à l'agent. */
    const vuBrut = (reel[role] || { ecrans: [] }).ecrans;
    const vu = [];
    const deja = {};
    vuBrut.forEach((e) => { const k = clef(e); if (!deja[k]) { deja[k] = 1; vu.push(e); } });

    const vuClefs = vu.map(clef);
    const attClefs = attendu.map(clef);

    const absents = attendu.filter((e) => vuClefs.indexOf(clef(e)) === -1);
    const brut = vu.filter((e) => attClefs.indexOf(clef(e)) === -1);

    /* On sépare les tableaux de bord : la cible n'en nomme qu'un par poste,
       et voir celui d'un autre service n'est pas la même faute que voir son
       dossier médical. */
    const tableaux = brut.filter((e) => (reel[role].dash || []).indexOf(e) !== -1);
    const toleres = brut.filter((e) => TOLERES.indexOf(e) !== -1);
    const enTrop = brut.filter((e) => tableaux.indexOf(e) === -1 && toleres.indexOf(e) === -1);

    manques += absents.length;
    surplus += enTrop.length;
    rapport.push({ role: role, nom: cible[role].nom, attendu: attendu.length,
      vu: vu.length, absents: absents, enTrop: enTrop,
      tableauxAutres: tableaux, toleres: toleres, rangees: reel[role].rangees });
  });

  rapport.forEach((r) => {
    const etat = (r.absents.length === 0 && r.enTrop.length === 0) ? '✓' : '✗';
    console.log(etat + ' ' + r.nom + '  (cible ' + r.attendu + ' · vu ' + r.vu + ')');
    if (r.absents.length) {
      console.log('    MANQUE (' + r.absents.length + ') : ' + r.absents.join(' · '));
    }
    if (r.enTrop.length) {
      console.log('    EN TROP (' + r.enTrop.length + ') : ' + r.enTrop.join(' · '));
    }
    if (r.tableauxAutres.length) {
      console.log('    tableaux d’autres postes (' + r.tableauxAutres.length + ') : '
        + r.tableauxAutres.join(' · '));
    }
    console.log('');
  });

  console.log('─'.repeat(74));
  console.log('Écrans manquants : ' + manques + '     Écrans en trop : ' + surplus);
  console.log(manques === 0 && surplus === 0
    ? 'RÉSULTAT : le ruban réel correspond exactement à la cible.'
    : 'RÉSULTAT : ' + (manques + surplus) + ' écart(s) à arbitrer.');
  console.log('─'.repeat(74) + '\n');

  fs.writeFileSync(path.resolve(ROOT, '..', 'newdocs', 'ECARTS-CIBLE-RUBAN.json'),
    JSON.stringify(rapport, null, 1), 'utf8');
  console.log('  Détail : newdocs/ECARTS-CIBLE-RUBAN.json\n');

  await navigateur.close();
  serveur.close();
  try { php.php.kill(); } catch (e) { /* déjà mort */ }
  process.exit(0);
})();
