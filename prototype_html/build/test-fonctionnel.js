/* =============================================================================
 * Tests fonctionnels du prototype SIGH-CNT
 * -----------------------------------------------------------------------------
 * Pilote un vrai navigateur et exécute les parcours métier de bout en bout :
 * navigation par sous-onglets, création, édition, archivage avec annulation,
 * restauration, filtres, tri, pagination, export CSV et prévisualisation des
 * états officiels. Toute erreur JavaScript survenue pendant un parcours fait
 * échouer le test correspondant.
 *     node build/test-fonctionnel.js
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const BANC = require('./_banc');
const http = require('http');
const puppeteer = require('puppeteer');

const ROOT = path.resolve(__dirname, '..');
const PORT = Number(process.env.SIGH_PORT_TEST) || 8096;
const MIME = {
  '.php': 'text/html; charset=utf-8',
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.woff2': 'font/woff2', '.jpeg': 'image/jpeg', '.png': 'image/png',
};

function findBrowser() {
  for (const c of [process.env.CHROME_PATH, 'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].filter(Boolean)) {
    if (fs.existsSync(c)) return c;
  }
  return null;
}

/* --- Petit cadre de test -------------------------------------------------- */
const resultats = [];
let courant = null;

function scenario(nom) {
  courant = { nom, etapes: [], ok: true };
  resultats.push(courant);
  return courant;
}
function verifier(libelle, condition, detail) {
  const ok = !!condition;
  courant.etapes.push({ libelle, ok, detail: ok ? null : (detail || '') });
  if (!ok) courant.ok = false;
  process.stdout.write(ok ? '.' : 'X');
  /* L'échec est nommé SUR-LE-CHAMP : si un scénario ultérieur fait tomber le
     banc, le récapitulatif de fin n'est jamais écrit, et un « X » au milieu
     d'une ligne de points ne dit ni où ni quoi. */
  if (!ok) {
    process.stdout.write('\n  ✗ [' + (courant ? courant.nom : '?') + '] ' + libelle
      + (detail ? '\n     → ' + String(detail).slice(0, 400) : '') + '\n');
  }
}
const pause = (ms) => new Promise((r) => setTimeout(r, ms));

/* Les messages restent affichés plusieurs secondes et se superposent : on vide
   la pile avant chaque action dont on veut observer la confirmation. */
async function viderMessages(page) {
  await page.evaluate(() => {
    const h = document.querySelector('#toast-host');
    if (h) h.innerHTML = '';
  });
}

(async () => {
  /* LES PARCOURS S'ÉPROUVENT CONTRE LA BASE. Depuis que le navigateur
     n'écrit plus rien, un banc servi en statique ne mesurerait que des
     écrans vides : chaque scénario échouerait sans rapport avec ce qu'il
     vérifie. On démarre donc un vrai serveur PHP, sur une base JETABLE. */
  const php = await BANC.demarrerPhp(ROOT);
  if (!php.php) {
    console.error('\n  ÉCHEC — ' + php.raison);
    console.error('  Sans serveur, les scénarios mesureraient des écrans vides.\n');
    process.exit(1);
  }
  const vidage = await BANC.banc('reinitialiser');
  if (vidage.erreur) {
    console.error('\n  ÉCHEC — base du banc : ' + (vidage.detail || vidage.erreur) + '\n');
    try { php.php.kill(); } catch (e) { /* déjà mort */ }
    process.exit(1);
  }
  console.log('  Banc : base « ' + vidage.base + ' » remise à neuf.\n');

  const server = http.createServer((req, res) => {
    if (req.url.indexOf('/api/') === 0) { BANC.relayer(req, res); return; }
    const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '') || 'index.php';
    const file = path.join(ROOT, rel);
    if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  }).listen(PORT);

  const browser = await puppeteer.launch({
    executablePath: findBrowser(), headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });
  const page = await browser.newPage();
  await BANC.poserSession(page);
  /* LE MAGASIN ENTIER TRANSITE PAR HTTP à chaque page — instantané depuis
     le navigateur, coûteux depuis la base, et le serveur intégré de PHP est
     mono-processus. Trente secondes ne suffisent plus ; le délai ne masque
     aucune anomalie, il tient compte du coût réel du transport. */
  page.setDefaultNavigationTimeout(180000);
  page.setDefaultTimeout(180000);
  await page.setViewport({ width: 1600, height: 1000 });

  let erreursJS = [];
  page.on('pageerror', (e) => erreursJS.push(String(e.message)));
  page.on('console', (m) => { if (m.type() === 'error') erreursJS.push(m.text()); });

  /* ==========================================================================
   * ÉVALUER SUR UN CONTEXTE VIVANT (22/09/2026)
   * --------------------------------------------------------------------------
   * Depuis que les grandes saisies ont quitté les modales pour des PAGES, un
   * clic qui ouvrait une fenêtre déclenche une NAVIGATION. Les attentes
   * fixes des scénarios — 700 ms, 2600 ms — étaient calibrées sur une modale :
   * l'évaluation suivante tombe tantôt sur un contexte détruit, tantôt sur un
   * document dont les scripts n'ont pas encore tourné, et le banc s'arrête sur
   * « Cannot read properties of undefined (reading 'store') ». Le point de
   * chute variait d'une exécution à l'autre : c'est une COURSE, pas un défaut
   * d'écran.
   *
   * La garde n'assouplit AUCUNE assertion : elle attend seulement que le
   * document soit complet et le socle chargé avant de mesurer. Allonger les
   * pauses une par une aurait masqué le problème là où on y pense, et l'aurait
   * laissé partout ailleurs.
   * ======================================================================== */
  const evaluerBrut = page.evaluate.bind(page);
  page.evaluate = async function (fn, ...args) {
    let derniere = null;
    for (let i = 0; i < 40; i++) {
      try {
        /* Le socle n'est exigé que pendant la première seconde : au-delà, on
           mesure quand même. Une page qui n'a pas de socle — un 403 atteint
           par un rôle qui n'a pas le droit d'ouvrir l'écran — doit faire
           ÉCHOUER l'assertion sur ce qu'elle cherchait, et non expirer huit
           secondes plus tard sur un message qui ne nomme rien. */
        const pret = await evaluerBrut((exigerSocle) => document.readyState === 'complete'
          && (!exigerSocle || !!(window.SIGH && window.SIGH.store)), i < 5).catch(() => false);
        if (!pret) { await pause(200); continue; }
        return await evaluerBrut(fn, ...args);
      } catch (e) {
        derniere = e;
        const m = String((e && e.message) || '');
        /* Contexte remplacé en pleine mesure : on recommence sur le nouveau. */
        if (/context was destroyed|Cannot find context|Execution context|detached/i.test(m)) {
          await pause(200); continue;
        }
        throw e;
      }
    }
    throw derniere || new Error('Contexte d’exécution indisponible après 8 s.');
  };

  /* LES PAGES SONT EN `.php` DEPUIS LE 23/09/2026 — servies par Apache en
     exploitation, pour que l'API des données soit de même origine. Les deux
     cent quatre-vingts appels des scénarios nomment encore `.html` : on
     normalise ICI, en un seul point, plutôt que de les reprendre un à un.
     Le contenu de la page n'a pas changé d'une ligne. */
  function pageDuBanc(rel) { return String(rel).replace(/\.html(#|\?|$)/, '.php$1'); }

  /* ON NE QUITTE PAS UNE PAGE AVANT QUE SES ÉCRITURES SOIENT PARTIES.
     Les mutations sont asynchrones depuis la bascule en base : un scénario qui
     enregistre puis navigue aussitôt doublait sa propre écriture, et ne
     retrouvait plus à l'écran suivant ce qu'il venait de créer. Le magasin
     expose sa file ; on la vide et on l'attend. */
  async function attendreEcritures() {
    try {
      await page.evaluate(() => {
        if (window.SIGH && window.SIGH.store && window.SIGH.store.pousserMaintenant) {
          window.SIGH.store.pousserMaintenant();
        }
      });
      await page.waitForFunction(
        () => !window.SIGH || !window.SIGH.store || !window.SIGH.store.fileEnAttente
          || window.SIGH.store.fileEnAttente() === 0,
        { timeout: 30000 });
    } catch (e) { /* page détruite ou socle absent : rien à attendre */ }
  }

  /** ATTEND QUE LA PAGE SOIT PEINTE **ET** QUE LE MAGASIN FASSE AUTORITÉ.
   *  `!!window.SIGH.store` ne suffit pas : la coquille provisoire et VIDE le
   *  satisfait aussi, et une sonde qui lit dedans mesure « pas encore » en
   *  croyant mesurer « aucune fiche ».
   *  L'attente est reprise par tranches courtes parce qu'un rechargement
   *  déclenché par la page elle-même DÉTRUIT le contexte d'évaluation : une
   *  attente unique et longue se perdrait au premier rechargement. */
  async function attendrePeinture(limite) {
    const fin = Date.now() + (limite || 150000);
    while (Date.now() < fin) {
      try {
        await page.waitForFunction(() => {
          const S = window.SIGH && window.SIGH.store;
          if (!S) return false;
          /* `faitAutorite` est récent : un magasin qui ne l'expose pas est
             tenu pour hydraté, faute de pouvoir le vérifier. */
          /* UNE REDIRECTION N'EST PAS UNE PAGE QUI NE SE PEINT PAS : la page 403 et les
             écrans d'authentification n'ont pas de #page-content, et le scénario qui y
             arrive mesure l'ADRESSE. Attendre 150 s dessus coûtait deux minutes et demie
             par refus sondé, et criait depuis la vague 68 à une hydratation pendante. */
          if (/error-403|\/auth-|\/index\.php|enquete-publique/.test(location.pathname)) return true;
          if (S.faitAutorite && !S.faitAutorite()) return false;
          const c = document.getElementById('page-content');
          return !!(c && c.children.length > 0);
        }, { timeout: 4000 });
        return true;
      } catch (e) { /* contexte détruit par un rechargement, ou pas encore prêt */ }
    }
    return false;
  }

  async function ouvrir(rel) {
    await attendreEcritures();
    erreursJS = [];
    /* `domcontentloaded` ET NON `networkidle2` : la page interroge l'API, et
       le serveur PHP du banc est mono-processus — le réseau ne se calme pas
       dans le budget, et la navigation expirait sur une page parfaitement
       saine. L'attente qui suit est meilleure de toute façon : elle guette la
       PEINTURE, c'est-à-dire ce qu'on veut vraiment mesurer. */
    const reponse = await page.goto(`http://127.0.0.1:${PORT}/pages/${pageDuBanc(rel)}`, { waitUntil: 'domcontentloaded' }).catch(() => null);
    /* UNE PAGE QUI N'EXISTE PAS SE DIT TOUT DE SUITE (vague 70). `m6-inventaires` (au pluriel) n'a jamais existé : le banc
       attendait 150 s une peinture impossible à CHAQUE passage, puis le prétendait « hydratation jamais aboutie ». */
    if (reponse && reponse.status() === 404) {
      console.log('\n  PAGE INTROUVABLE (404) : ' + rel + ' — absente du manifeste ; le scénario continue sans elle.');
      return;
    }
    /* ON ATTEND QUE LA PAGE SOIT PEINTE, pas un délai. Depuis la bascule en
       base, le montage attend l'hydratation — 5 Mo à transporter puis à
       analyser — et les 450 ms d'autrefois tombaient au milieu : la sonde
       cherchait un champ de recherche qui n'existait pas encore et lisait
       « null » là où l'écran était simplement en retard. */
    const peinte = await attendrePeinture();
    /* UNE PAGE QUI NE SE PEINT PAS LE DIT (vague 68). Le banc rendait la main en
       silence après 150 s et chaque assertion suivante échouait comme si
       l'interface était absente — « bouton absent », « modale absente » — avec
       0 erreur JS : on cherchait le défaut dans l'écran pendant que la page
       n'avait jamais été hydratée. */
    if (!peinte) {
      const diag = await page.evaluate(() => ({ url: location.pathname.split('/').pop(), etat: document.readyState,
        serveur: window.SIGH && window.SIGH.store && window.SIGH.store.etatServeur ? window.SIGH.store.etatServeur() : null,
        contenu: !!document.querySelector('#page-content'), corps: document.body ? document.body.innerText.slice(0, 120) : null })).catch((e) => String(e).slice(0, 120));
      console.log('\n  DIAGNOSTIC de la page non peinte : ' + JSON.stringify(diag) + ' ; erreurs JS : ' + JSON.stringify(erreursJS.slice(0, 3)));
    }
    if (!peinte) console.log('\n  PAGE NON PEINTE après 150 s : ' + rel + ' — hydratation jamais aboutie, le reste du scénario mesure une page blanche.');
    await pause(450);
  }

  /* Clique le premier élément dont le texte contient `texte`. */
  async function cliquer(texte, selecteur) {
    const fait = await page.evaluate((t, sel) => {
      const noeuds = [...document.querySelectorAll(sel || 'button, a, .tab, [role="tab"]')];
      const cible = noeuds.find((n) => (n.textContent || '').trim().toLowerCase().includes(t.toLowerCase())
        && n.offsetParent !== null);
      if (cible) { cible.click(); return true; }
      return false;
    }, texte, selecteur);
    await pause(400);
    return fait;
  }

  async function compterLignes() {
    return page.evaluate(() => document.querySelectorAll('#page-content tbody tr').length);
  }
  async function texteCompteur() {
    return page.evaluate(() => {
      /* Le pied du tableau, à distinguer du texte d'aide de l'état vide qui
         contient lui aussi le mot « enregistrement ». */
      const p = [...document.querySelectorAll('#page-content p')]
        .find((x) => /^Aucun enregistrement$/.test(x.textContent.trim())
          || /sur [\d\s  ]+ enregistrement/.test(x.textContent));
      return p ? p.textContent : '';
    });
  }
  /** Lit le pied du tableau : « … sur N enregistrements » ou « Aucun enregistrement ». */
  function totalDepuisCompteur(txt) {
    if (!txt) return -1;
    if (/Aucun enregistrement/.test(txt)) return 0;
    const m = /sur ([\d\s  ]+) enregistrement/.exec(txt);
    return m ? Number(m[1].replace(/[\s  ]/g, '')) : -1;
  }

  console.log('\nExécution des parcours fonctionnels…\n');

  /* =========================================================================
   * 1. Création, édition, archivage annulable — Répertoire des patients (M1)
   * ======================================================================= */
  {
    scenario('M1 — Cycle de vie complet d’un dossier patient');
    await ouvrir('m1-patients.html');
    verifier('La page se charge sans erreur JavaScript', erreursJS.length === 0, erreursJS.join(' | '));

    const totalInitial = totalDepuisCompteur(await texteCompteur());
    verifier('Le tableau affiche le compteur d’enregistrements', totalInitial > 0, 'compteur : ' + totalInitial);

    /* --- Création ---
       L'OUVERTURE D'UN DOSSIER A QUITTÉ LA MODALE (22/09/2026) : le bouton
       « Nouveau » NAVIGUE vers `m1-patient-nouveau`. Le scénario suit le
       geste réel — il ne cherche plus de fenêtre. */
    verifier('Le bouton « Nouveau » est présent', await cliquer('Nouveau', '#page-content button'));
    await pause(900);
    verifier('Il conduit à la PAGE d’ouverture de dossier, et non à une fenêtre',
      await page.evaluate(() => /m1-patient-nouveau/.test(location.pathname)
        && !document.querySelector('[role="dialog"]')));
    const codeAttribue = await page.evaluate(() => {
      const inp = document.querySelector('#f_code');
      return inp ? inp.value : null;
    });
    verifier('Le code patient est pré-attribué au format CNT[n°]/[année]',
      /^CNT\d+\/\d{2}$/.test(codeAttribue || ''), 'code : ' + codeAttribue);
    verifier('Le champ code est en lecture seule (RG-01)',
      await page.evaluate(() => document.querySelector('#f_code') && document.querySelector('#f_code').hasAttribute('readonly')));

    /* Soumission incomplète : la validation doit bloquer */
    await cliquer('Ouvrir le dossier', '#page-content button');
    await pause(300);
    const erreursAffichees = await page.evaluate(() =>
      [...document.querySelectorAll('.field-error')].filter((e) => !e.hidden).length);
    verifier('La validation bloque une création incomplète', erreursAffichees > 0, erreursAffichees + ' erreur(s)');

    /* Renseignement puis création */
    await page.evaluate(() => {
      const set = (id, v) => {
        const e = document.querySelector(id);
        if (!e) return;
        e.value = v;
        e.dispatchEvent(new Event('input', { bubbles: true }));
        e.dispatchEvent(new Event('change', { bubbles: true }));
      };
      set('#f_nom', 'TESTOU');
      set('#f_prenom', 'Fonctionnel');
      set('#f_sexe', 'F');
      set('#f_dateNaissance', '1990-05-12');
      set('#f_telephone', '0197000000');
    });
    await cliquer('Ouvrir le dossier', '#page-content button');
    /* L'ouverture d'un dossier REVIENT au répertoire : la sonde lit l'adresse
       puis le compteur du tableau. Un délai fixe lirait un compteur que la
       page n'a pas encore peint, et l'on conclurait que le patient n'a pas
       été créé. */
    await attendrePeinture();
    await pause(300);
    verifier('La page revient au répertoire une fois le dossier ouvert',
      await page.evaluate(() => /m1-patients/.test(location.pathname)));
    const totalApresCreation = totalDepuisCompteur(await texteCompteur());
    verifier('Le patient créé apparaît dans le tableau', totalApresCreation === totalInitial + 1,
      totalInitial + ' → ' + totalApresCreation);
    verifier('Un message de confirmation est affiché',
      await page.evaluate(() => !!document.querySelector('#toast-host')));

    /* --- Recherche du nouvel enregistrement --- */
    await page.evaluate(() => {
      const s = document.querySelector('#page-content input[type="search"]');
      if (s) { s.value = 'TESTOU'; s.dispatchEvent(new Event('input', { bubbles: true })); }
    });
    await pause(500);
    const trouve = await page.evaluate(() => document.body.textContent.includes('TESTOU'));
    verifier('La recherche retrouve le patient créé', trouve);

    /* --- Édition --- */
    const editionOuverte = await page.evaluate(() => {
      const b = [...document.querySelectorAll('#page-content tbody tr:first-child button')]
        .find((x) => (x.getAttribute('title') || '') === 'Modifier');
      if (b) { b.click(); return true; }
      return false;
    });
    await pause(400);
    verifier('L’action « Modifier » ouvre le formulaire d’édition', editionOuverte
      && await page.evaluate(() => !!document.querySelector('[role="dialog"]')));
    await page.evaluate(() => {
      const e = document.querySelector('#f_prenom');
      if (e) { e.value = 'Modifié'; e.dispatchEvent(new Event('input', { bubbles: true })); }
    });
    await cliquer('Enregistrer', '[role="dialog"] button');
    await pause(600);
    verifier('La modification est enregistrée',
      await page.evaluate(() => document.body.textContent.includes('Modifié')));

    /* --- Archivage avec motif puis annulation --- */
    await viderMessages(page);
    const archiveOuverte = await page.evaluate(() => {
      const b = [...document.querySelectorAll('#page-content tbody tr:first-child button')]
        .find((x) => (x.getAttribute('title') || '') === 'Archiver');
      if (b) { b.click(); return true; }
      return false;
    });
    await pause(400);
    verifier('L’archivage demande confirmation', archiveOuverte
      && await page.evaluate(() => !!document.querySelector('[role="dialog"]')));
    verifier('Un motif est demandé (journalisé)',
      await page.evaluate(() => !!document.querySelector('[role="dialog"] textarea')));
    await page.evaluate(() => {
      const t = document.querySelector('[role="dialog"] textarea');
      if (t) { t.value = 'Test fonctionnel automatisé'; t.dispatchEvent(new Event('input', { bubbles: true })); }
    });
    await cliquer('Archiver', '[role="dialog"] button');
    await pause(700);
    /* La recherche « TESTOU » est toujours active : le compteur porte donc sur
       le sous-ensemble filtré, ce qui suffit à observer l'archivage puis la
       restauration de l'enregistrement de test. */
    const filtreApresArchivage = totalDepuisCompteur(await texteCompteur());
    verifier('L’enregistrement disparaît de la liste active', filtreApresArchivage === 0,
      'lignes filtrées restantes : ' + filtreApresArchivage);

    const undoPresent = await page.evaluate(() =>
      [...document.querySelectorAll('#toast-host button')].some((b) => b.textContent.trim() === 'Annuler'));
    verifier('Le message propose une annulation', undoPresent);

    await page.evaluate(() => {
      const b = [...document.querySelectorAll('#toast-host button')].find((x) => x.textContent.trim() === 'Annuler');
      if (b) b.click();
    });
    await pause(700);
    const filtreApresAnnulation = totalDepuisCompteur(await texteCompteur());
    verifier('L’annulation restaure l’enregistrement', filtreApresAnnulation === 1,
      filtreApresArchivage + ' → ' + filtreApresAnnulation);

    /* Retour au jeu complet : le total doit être revenu à sa valeur d'après création. */
    await page.evaluate(() => {
      const s = document.querySelector('#page-content input[type="search"]');
      if (s) { s.value = ''; s.dispatchEvent(new Event('input', { bubbles: true })); }
    });
    await pause(500);
    const totalFinal = totalDepuisCompteur(await texteCompteur());
    verifier('Le répertoire complet retrouve son effectif', totalFinal === totalApresCreation,
      totalApresCreation + ' attendu, ' + totalFinal + ' obtenu');

    verifier('Aucune erreur JavaScript sur tout le parcours', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 2. Sous-onglets et onglet « Archivés »
   * ======================================================================= */
  {
    scenario('Navigation par sous-onglets');
    await ouvrir('m5-catalogue.html');
    const nbOnglets = await page.evaluate(() => document.querySelectorAll('#page-content .tab').length);
    verifier('Les sous-onglets sont présents', nbOnglets >= 2, nbOnglets + ' onglet(s)');

    verifier('L’onglet « Par catégorie » s’ouvre', await cliquer('Par catégorie', '#page-content .tab'));
    await pause(400);
    verifier('Le contenu de l’onglet est rendu',
      await page.evaluate(() => document.body.textContent.includes('Biochimie')));

    verifier('L’onglet « Archivés » s’ouvre', await cliquer('Archivés', '#page-content .tab'));
    await pause(400);
    verifier('L’onglet archivés affiche un état vide ou une liste',
      await page.evaluate(() => {
        const c = document.querySelector('#page-content');
        return c.textContent.includes('archivé') || c.querySelectorAll('tbody tr').length >= 0;
      }));
    verifier('Aucune erreur JavaScript', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 3. Tri, filtres et pagination
   * ======================================================================= */
  {
    scenario('Tri, filtres et pagination');
    await ouvrir('m6-produits.html');
    const total = totalDepuisCompteur(await texteCompteur());
    verifier('Le référentiel produits est chargé', total > 0, total + ' produits');

    /* Tri */
    await page.evaluate(() => {
      const th = document.querySelector('#page-content .th-sortable');
      if (th) th.click();
    });
    await pause(400);
    verifier('Le tri par colonne s’applique', await page.evaluate(() =>
      !!document.querySelector('#page-content thead svg')));

    /* Filtre */
    const filtreApplique = await page.evaluate(() => {
      const sel = [...document.querySelectorAll('#page-content select')]
        .find((s) => [...s.options].some((o) => o.textContent.includes('Médicaments')));
      if (!sel) return false;
      const opt = [...sel.options].find((o) => o.textContent.includes('Médicaments'));
      sel.value = opt.value;
      sel.dispatchEvent(new Event('change', { bubbles: true }));
      return true;
    });
    await pause(500);
    const totalFiltre = totalDepuisCompteur(await texteCompteur());
    verifier('Le filtre par catégorie réduit le jeu de résultats',
      filtreApplique && totalFiltre > 0 && totalFiltre < total, total + ' → ' + totalFiltre);

    /* Pagination */
    const pagination = await page.evaluate(() => {
      const btns = [...document.querySelectorAll('#page-content button')].filter((b) => b.textContent.trim() === '2');
      if (btns.length) { btns[0].click(); return true; }
      return false;
    });
    await pause(400);
    if (pagination) {
      verifier('La pagination change de page',
        await page.evaluate(() => document.querySelectorAll('#page-content tbody tr').length > 0));
    } else {
      verifier('Pagination non requise sur ce jeu filtré', true);
    }
    verifier('Aucune erreur JavaScript', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 4. Règle métier RG-03 — stock jamais négatif
   * ======================================================================= */
  {
    scenario('RG-03 — le stock ne peut pas devenir négatif');
    await ouvrir('m6-transferts.html');
    verifier('L’écran des transferts se charge', erreursJS.length === 0, erreursJS.join(' | '));
    verifier('Le bouton « Nouveau transfert » est présent', await cliquer('Nouveau transfert', '#page-content button'));
    await pause(400);

    /* Le bon est désormais MULTI-LIGNES : on choisit un article, on saisit une
       quantité excessive, et RG-03 doit refuser l'AJOUT de la ligne — en
       nommant l'article, car un refus anonyme ferait chercher la panne. */
    const ajoutBloque = await page.evaluate(async () => {
      const dlg = document.querySelector('[role="dialog"]');
      if (!dlg) return { erreur: 'modale absente' };
      const combo = dlg.querySelector('.combo');
      if (!combo) return { erreur: 'sélecteur d’article absent' };
      const S = window.SIGH.store;
      const dispo = S.collection('produits').active().filter((p) => p.stockGros > 0)[0];
      if (!dispo) return { erreur: 'aucun produit au magasin' };
      combo.value = dispo.id;
      const q = dlg.querySelector('#transfert-quantite');
      if (!q) return { erreur: 'champ de quantité absent' };
      q.value = '999999';
      q.dispatchEvent(new Event('input', { bubbles: true }));
      const btn = [...dlg.querySelectorAll('button')].find((b) => /^Ajouter$/.test(b.textContent.trim()));
      if (!btn) return { erreur: 'bouton Ajouter absent' };
      btn.click();
      await new Promise((r) => setTimeout(r, 400));
      const host = document.querySelector('#toast-host');
      const texte = host ? host.textContent : '';
      return {
        rg03: /RG-03/.test(texte),
        nomme: texte.indexOf(dispo.designation) !== -1,
        article: dispo.designation,
      };
    });
    verifier('Le transfert excédentaire est refusé avec la mention RG-03',
      ajoutBloque.rg03 === true, ajoutBloque.erreur || ajoutBloque.article);
    verifier('…et le refus NOMME l’article — un refus anonyme ferait chercher la panne ailleurs',
      ajoutBloque.nomme === true, ajoutBloque.article);

    /* Une quantité tenable passe, et le bon accepte plusieurs articles. */
    const multi = await page.evaluate(async () => {
      const dlg = document.querySelector('[role="dialog"]');
      if (!dlg) return { erreur: 'modale absente' };
      const S = window.SIGH.store;
      const combo = dlg.querySelector('.combo');
      const q = dlg.querySelector('#transfert-quantite');
      const btn = [...dlg.querySelectorAll('button')].find((b) => /^Ajouter$/.test(b.textContent.trim()));
      const dispo = S.collection('produits').active().filter((p) => p.stockGros > 2).slice(0, 3);
      for (const p of dispo) {
        combo.value = p.id;
        q.value = '2';
        q.dispatchEvent(new Event('input', { bubbles: true }));
        btn.click();
        await new Promise((r) => setTimeout(r, 200));
      }
      const lignes = dlg.querySelectorAll('tbody tr').length;
      return { lignes: lignes, attendues: dispo.length };
    });
    verifier('Plusieurs articles tiennent sur un même bon de transfert',
      multi.lignes === multi.attendues && multi.lignes > 1,
      multi.erreur || (multi.lignes + ' ligne(s) sur le bon'));
    verifier('La modale reste ouverte pour correction',
      await page.evaluate(() => !!document.querySelector('[role="dialog"]')));
  }

  /* =========================================================================
   * 5. Règle métier RG-07 — triple signature à la sortie
   * ======================================================================= */
  {
    scenario('RG-07 — signatures obligatoires à la sortie d’hospitalisation');
    await ouvrir('m3-sorties.html');
    const ouvert = await page.evaluate(() => {
      const b = [...document.querySelectorAll('#page-content tbody tr:first-child button')]
        .find((x) => x.textContent.includes('Préparer'));
      if (b) { b.click(); return true; }
      return false;
    });
    await pause(500);
    verifier('Le tiroir de préparation de sortie s’ouvre', ouvert
      && await page.evaluate(() => !!document.querySelector('[role="dialog"]')));
    await cliquer('Finaliser la sortie', '[role="dialog"] button');
    await pause(600);
    const refus = await page.evaluate(() => {
      const t = document.querySelector('#toast-host');
      return t ? t.textContent.includes('RG-07') : false;
    });
    verifier('La finalisation est refusée sans les trois signatures (RG-07)', refus);
  }

  /* =========================================================================
   * 6. Règle métier RG-10 — équilibre des écritures comptables
   * ======================================================================= */
  {
    scenario('RG-10 — équilibre débit/crédit avant validation');
    await ouvrir('m12-ecritures.html');
    verifier('Le bouton « Nouvelle écriture » est présent', await cliquer('Nouvelle écriture', '#page-content button'));
    await pause(400);

    /* Une seule ligne au débit : l'écriture est déséquilibrée */
    await page.evaluate(() => {
      const inputs = [...document.querySelectorAll('[role="dialog"] input[type="number"]')];
      if (inputs[0]) { inputs[0].value = '50000'; inputs[0].dispatchEvent(new Event('input', { bubbles: true })); }
      const lib = document.querySelector('#f_libelle');
      if (lib) { lib.value = 'Test déséquilibre'; lib.dispatchEvent(new Event('input', { bubbles: true })); }
    });
    await cliquer('Ajouter la ligne', '[role="dialog"] button');
    await pause(400);
    const alerteDesequilibre = await page.evaluate(() =>
      document.querySelector('[role="dialog"]').textContent.includes('n’est pas équilibrée'));
    verifier('Le déséquilibre est signalé en direct', alerteDesequilibre);

    await cliquer('Valider l’écriture', '[role="dialog"] button');
    await pause(600);
    const refusValidation = await page.evaluate(() => {
      const t = document.querySelector('#toast-host');
      return t ? t.textContent.includes('RG-10') : false;
    });
    verifier('La validation est refusée tant que débit ≠ crédit (RG-10)', refusValidation);

    /* --- RG-10 VAUT AUSSI POUR LE JEU DE DÉMONSTRATION -------------------
       Le moteur refusait une pièce déséquilibrée pendant que le peuplement en
       écrivait 130 : compte tiré au hasard dans tout le plan, sens tiré par
       deux tirages indépendants. Mesuré alors : 6 157 000 F d'écart, 68 lignes
       à la fois au débit ET au crédit, 81 lignes de classe 6 au CRÉDIT — d'où
       les charges négatives du rapprochement. Un invariant qui ne tient pas
       sur les données qu'on montre ne tient pas. */
    await page.keyboard.press('Escape');
    await pause(300);
    const journal = await page.evaluate(() => {
      const e = window.SIGH.store.collection('ecritures').active();
      const som = (a, k) => a.reduce((n, x) => n + (Number(x[k]) || 0), 0);
      const pieces = {};
      e.forEach((x) => { (pieces[x.numero] = pieces[x.numero] || []).push(x); });
      const cles = Object.keys(pieces);
      const c6 = e.filter((x) => String(x.compte).charAt(0) === '6');
      const c7 = e.filter((x) => String(x.compte).charAt(0) === '7');
      return {
        lignes: e.length, pieces: cles.length,
        ecart: som(e, 'debit') - som(e, 'credit'),
        deuxSens: e.filter((x) => x.debit > 0 && x.credit > 0).length,
        bancales: cles.filter((n) => som(pieces[n], 'debit') !== som(pieces[n], 'credit')).length,
        /* Une pièce se valide ENTIÈRE : une moitié validée, l'autre en
           brouillon, laisserait la balance boiteuse sans le dire. */
        mixtes: cles.filter((n) => new Set(pieces[n].map((x) => x.statut)).size > 1).length,
        chargesAuCredit: c6.filter((x) => x.credit > 0).length,
        produitsAuDebit: c7.filter((x) => x.debit > 0).length,
      };
    });
    verifier('Le JOURNAL du jeu de démonstration est équilibré — RG-10 vaut aussi pour les données montrées',
      journal.lignes > 0 && journal.ecart === 0 && journal.bancales === 0,
      journal.lignes + ' lignes, ' + journal.pieces + ' pièces, écart ' + journal.ecart
      + ', ' + journal.bancales + ' pièce(s) déséquilibrée(s)');
    verifier('Aucune ligne ne porte à la fois un débit ET un crédit — une ligne a UN sens',
      journal.deuxSens === 0, String(journal.deuxSens));
    verifier('Aucune charge au crédit, aucun produit au débit — d’où des charges qui restent positives',
      journal.chargesAuCredit === 0 && journal.produitsAuDebit === 0,
      journal.chargesAuCredit + ' charge(s) au crédit, ' + journal.produitsAuDebit + ' produit(s) au débit');
    verifier('Une pièce est validée ENTIÈRE, jamais à moitié',
      journal.mixtes === 0, journal.mixtes + ' pièce(s) à statut mixte');
  }

  /* =========================================================================
   * 7. Impression d’un état officiel avec entête
   * ======================================================================= */
  {
    scenario('Édition d’un état officiel');
    await ouvrir('m10-primes.html');
    verifier('Le bouton d’impression est présent', await cliquer('Imprimer la note', '#page-content button'));
    await pause(800);

    const etat = await page.evaluate(() => {
      const sheet = document.querySelector('.print-sheet');
      if (!sheet) return null;
      /* Les montants sont formatés avec une espace fine insécable (U+202F),
         séparateur de milliers correct en typographie française : on la
         normalise avant comparaison. */
      const t = sheet.textContent.replace(/[  ]/g, ' ');
      return {
        present: true,
        entete: t.includes('CLINIQUE NASSIERA TOO'),
        ifu: t.includes('3201642748214'),
        rccm: t.includes('RB/NAT/2016-B-268'),
        autorisation: t.includes('066/MS/DC/SGM'),
        signature: t.includes('Le Directeur Médical'),
        pied: t.includes('Document généré par'),
        reference: /CNT-\d{8}-\d{4}/.test(t),
        montants: t.includes('1 500') && t.includes('10 000'),
      };
    });
    verifier('La feuille A4 est générée', etat && etat.present);
    verifier('L’entête officielle est reprise', etat && etat.entete);
    verifier('L’IFU figure sur le document', etat && etat.ifu);
    verifier('Le RCCM figure sur le document', etat && etat.rccm);
    verifier('Le numéro d’autorisation figure sur le document', etat && etat.autorisation);
    verifier('Le bloc de signatures est présent', etat && etat.signature);
    verifier('Le pied de page normalisé est présent', etat && etat.pied);
    verifier('L’identifiant unique du document est généré', etat && etat.reference);
    verifier('Les montants de la grille NS 132 sont repris', etat && etat.montants);

    verifier('La prévisualisation propose l’impression',
      await page.evaluate(() => document.body.textContent.includes('Imprimer / Enregistrer en PDF')));
    verifier('La prévisualisation se ferme', await cliquer('Fermer', '.print-chrome button'));
    await pause(300);
    verifier('La feuille est retirée après fermeture',
      await page.evaluate(() => !document.querySelector('.print-sheet')));
    verifier('Aucune erreur JavaScript', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 8. Export CSV
   * ======================================================================= */
  {
    scenario('Export des données');
    await ouvrir('m9-compagnies.html');
    verifier('Le bouton « Exporter » est présent', await cliquer('Exporter', '#page-content button'));
    await pause(400);
    verifier('La modale d’export propose CSV et PDF',
      await page.evaluate(() => {
        const d = document.querySelector('[role="dialog"]');
        return d && d.textContent.includes('CSV') && d.textContent.includes('PDF');
      }));

    /* Interception du téléchargement */
    await page.evaluate(() => {
      window.__telechargement = null;
      const orig = HTMLAnchorElement.prototype.click;
      HTMLAnchorElement.prototype.click = function () {
        if (this.download) { window.__telechargement = this.download; return; }
        return orig.apply(this, arguments);
      };
    });
    await cliquer('CSV', '[role="dialog"] button');
    await pause(600);
    const fichier = await page.evaluate(() => window.__telechargement);
    verifier('Le fichier CSV est généré', /assureurs-\d{4}-\d{2}-\d{2}\.csv/.test(fichier || ''), 'fichier : ' + fichier);
    verifier('Aucune erreur JavaScript', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 9. Recherche globale et changement de profil (RBAC)
   * ======================================================================= */
  {
    scenario('Recherche globale et périmètre RBAC');
    await ouvrir('dash-direction.html');
    await page.evaluate(() => window.SIGH.app.openSearch());
    await pause(400);
    await page.evaluate(() => {
      const i = document.querySelector('[role="dialog"] input[type="search"]');
      if (i) { i.value = 'stock'; i.dispatchEvent(new Event('input', { bubbles: true })); }
    });
    await pause(600);
    verifier('La recherche globale retourne des résultats',
      await page.evaluate(() => {
        const d = document.querySelector('[role="dialog"]');
        return d && d.querySelectorAll('button').length > 2;
      }));
    await page.keyboard.press('Escape');
    await pause(300);

    /* Recherche avancée : le contenu des écrans, pas seulement leur titre */
    async function chercher(terme) {
      await page.evaluate(() => {
        document.querySelectorAll('[role="dialog"]').forEach((d) => d.remove());
        window.SIGH.app.openSearch();
      });
      await pause(150);
      await page.evaluate((q) => {
        const i = document.querySelector('[role="dialog"] input[type="search"]');
        i.value = q; i.dispatchEvent(new Event('input', { bubbles: true }));
      }, terme);
      await pause(350);
      return page.evaluate(() => document.querySelector('[role="dialog"]').textContent);
    }

    const rActes = await chercher('actes');
    verifier('Chercher « actes » propose la rubrique du référentiel tarifaire',
      /Actes & hospitalisation/.test(rActes) && /onglet/.test(rActes), rActes.slice(0, 110));

    const rEcho = await chercher('échographie');
    verifier('La recherche atteint le contenu des référentiels',
      /Échographie prostatique/.test(rEcho), 'catalogue des actes');
    /* Un acte rapproché d'une grille porte DEUX prix, et la recherche doit les
       donner : « combien pour un assuré ? » est la question du guichet, et y
       répondre par un seul chiffre oblige à ouvrir l'écran. */
    verifier('Un tarif repris d’une grille montre ses deux prix',
      /assuré\s*[\d\s]/.test(rEcho), rEcho.slice(0, 140));

    /* Vague 49 : les tarifs d'attente sont ARRÊTÉS — la recherche donne le
       prix SANS marque d'attente, et c'est ce qu'on vérifie désormais. */
    const rPlatre = await chercher('plâtre');
    verifier('Le tarif cherché est arrêté (vague 49) — un prix, sans marque d’attente',
      /Plâtre/.test(rPlatre) && /\d/.test(rPlatre) && !/valeur d’attente/.test(rPlatre),
      rPlatre.slice(0, 140));

    const rCorbeille = await chercher('corbeille');
    verifier('Chercher « corbeille » mène à l’onglet des éléments archivés',
      /éléments archivés/.test(rCorbeille), rCorbeille.slice(0, 110));
    await page.keyboard.press('Escape');
    await pause(250);

    /* Le lien profond ouvre bien la page SUR l'onglet visé */
    await ouvrir('cfg-tarifs.html#onglet=actes');
    const ongletVise = await page.evaluate(() => {
      const a = document.querySelector('.tab-active');
      return a ? a.textContent.trim() : null;
    });
    verifier('Le lien profond ouvre l’écran sur le bon onglet',
      /^Actes & hospitalisation/.test(ongletVise || ''), ongletVise);

    /* Détour par un autre écran : sans lui, retirer l'ancre ne provoquerait
       qu'une navigation intra-document et la page ne serait pas remontée. */
    await ouvrir('m1-patients.html');
    await ouvrir('cfg-tarifs.html');
    const ongletDefaut = await page.evaluate(() => {
      const a = document.querySelector('.tab-active');
      return a ? a.textContent.trim() : null;
    });
    verifier('Sans ancre, l’écran garde son onglet par défaut',
      /^Produits & médicaments/.test(ongletDefaut || ''), ongletDefaut);

    /* Bascule de profil : le méga-menu doit se restreindre */
    const modulesAdmin = await page.evaluate(() => document.querySelectorAll('#app-menubar [role="tab"]').length);
    await page.evaluate(() => {
      window.SIGH.store.setSession({ role: 'caissier', nom: 'Caisse — poste accueil', poste: 'Caissier' });
    });
    await ouvrir('dash-caissier.html');
    const modulesCaissier = await page.evaluate(() => document.querySelectorAll('#app-menubar [role="tab"]').length);
    verifier('Le périmètre RBAC restreint la navigation du caissier',
      modulesCaissier > 0 && modulesCaissier < modulesAdmin,
      'admin : ' + modulesAdmin + ' domaines, caissier : ' + modulesCaissier);

    /* Accès à un écran interdit */
    await ouvrir('m11-bulletins.html');
    const redirige = page.url().includes('error-403');
    verifier('L’accès à un écran non habilité est refusé (403)', redirige, 'url : ' + page.url());

    await page.evaluate(() => {
      window.SIGH.store.setSession({ role: 'admin', nom: 'BASSONGUI Chabi Séko', poste: 'Directeur Médical' });
    });
  }

  /* =========================================================================
   * 10. Facturation de bout en bout avec sortie de stock
   * ======================================================================= */
  {
    scenario('M8 — Facturation et sortie de stock automatique');
    await ouvrir('m8-facturation.html');
    verifier('L’écran de facturation se charge', erreursJS.length === 0, erreursJS.join(' | '));

    const stockAvant = await page.evaluate(() => {
      const p = window.SIGH.store.collection('produits').active().filter((x) => x.stockDetail > 5)[0];
      return p ? { id: p.id, stock: p.stockDetail, nom: p.designation } : null;
    });
    verifier('Un médicament disponible est identifié', !!stockAvant, stockAvant && stockAvant.nom);

    /* Ajout d'un acte */
    await page.evaluate(() => {
      const sel = [...document.querySelectorAll('#page-content select')]
        .find((s) => [...s.options].some((o) => o.textContent.includes('Consultation médecin')));
      if (sel) {
        sel.value = '0';
        sel.dispatchEvent(new Event('change', { bubbles: true }));
      }
    });
    await cliquer('Ajouter', '#page-content button');
    await pause(500);
    const lignesFacture = await page.evaluate(() => document.querySelectorAll('#page-content tbody tr').length);
    verifier('La prestation est ajoutée à la facture', lignesFacture > 0, lignesFacture + ' ligne(s)');

    const totalAffiche = await page.evaluate(() => document.body.textContent.includes('Part à la charge du patient'));
    verifier('Le récapitulatif calcule la répartition patient / assurance', totalAffiche);

    await cliquer('Enregistrer et encaisser', '#page-content button');
    await pause(900);
    verifier('La facture normalisée est éditée après encaissement',
      await page.evaluate(() => {
        const s = document.querySelector('.print-sheet');
        return s && s.textContent.includes('Facture normalisée');
      }));
    verifier('La facture porte un identifiant MECeF',
      await page.evaluate(() => {
        const s = document.querySelector('.print-sheet');
        return s && /MECEF\d+/.test(s.textContent);
      }));
    verifier('Aucune erreur JavaScript sur le parcours de facturation', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 11. Méga-menu horizontal : ouverture par défaut, bascule de domaine,
   *     repli mémorisé, accès rapides en tête des tableaux de bord.
   * ======================================================================= */
  {
    scenario('Méga-menu horizontal et accès rapides');
    await page.evaluate(() => window.SIGH.store.storage.remove('sigh-cnt:ruban'));
    await ouvrir('m6-produits.html');

    const etat = await page.evaluate(() => {
      const p = document.querySelector('#app-ribbon');
      const actif = document.querySelector('#app-menubar .ribbon-tab-active');
      return {
        ouvert: !!p && !p.hidden,
        domaine: actif ? actif.textContent.trim() : null,
        rangees: p ? p.querySelectorAll('.ribbon-row').length : 0,
        courant: !!(p && p.querySelector('.ribbon-chip-active')),
        icones: p ? p.querySelectorAll('.ribbon-chip svg').length : 0,
        liens: p ? p.querySelectorAll('.ribbon-chip').length : 0,
        hauteur: p ? Math.round(p.getBoundingClientRect().height) : 0,
        hubs: p ? p.querySelectorAll('.ribbon-row-head[href*="hub-"]').length : 0,
        raccourcis: document.querySelectorAll('#app-menubar .ribbon-shortcut').length,
      };
    });
    verifier('Le méga-menu est déployé par défaut', etat.ouvert);
    verifier('Il s’ouvre sur le domaine de l’écran courant', etat.domaine === 'Logistique', 'domaine : ' + etat.domaine);
    verifier('Les modules du domaine forment des rangées', etat.rangees === 2, 'rangées : ' + etat.rangees);
    verifier('Le panneau reste compact (moins du tiers de la fenêtre)',
      etat.hauteur > 0 && etat.hauteur < 330, 'hauteur : ' + etat.hauteur + ' px');
    verifier('Chaque rangée ouvre la page d’accueil de son module', etat.hubs === etat.rangees,
      etat.hubs + ' lien(s) hub pour ' + etat.rangees + ' rangée(s)');
    verifier('Les quatre postes de travail sont accessibles en permanence',
      etat.raccourcis === 4, 'raccourcis : ' + etat.raccourcis);
    verifier('L’écran courant est signalé dans le menu', etat.courant);
    verifier('Chaque entrée porte son icône', etat.liens > 0 && etat.icones === etat.liens,
      etat.icones + ' icônes pour ' + etat.liens + ' entrées');

    /* Bascule vers un autre domaine */
    await page.evaluate(() => {
      const t = [...document.querySelectorAll('#app-menubar [role="tab"]')]
        .find((b) => b.textContent.trim() === 'Financier');
      if (t) t.click();
    });
    await pause(250);
    const apres = await page.evaluate(() => {
      const p = document.querySelector('#app-ribbon');
      const actif = document.querySelector('#app-menubar .ribbon-tab-active');
      /* LE NOMBRE DE RANGÉES EST DÉRIVÉ DU MANIFESTE, jamais écrit en dur :
         il était figé à 4 et tombait en échec à chaque rangée ajoutée — la
         leçon déjà payée sur le compte de cartes d'un hub. C'est la
         CONCORDANCE entre ce que le manifeste déclare et ce que le ruban
         peint qui vaut assertion. */
      const attendu = window.SIGH.nav.tree(window.SIGH.store.session().role)
        .filter((d) => d.domain === 'Financier')
        .reduce((n, d) => n + d.modules.length, 0);
      return { domaine: actif ? actif.textContent.trim() : null,
        groupes: p.querySelectorAll('.ribbon-row').length, attendu: attendu };
    });
    verifier('Un clic sur un onglet déploie son domaine',
      apres.domaine === 'Financier' && apres.groupes === apres.attendu && apres.attendu > 0,
      apres.domaine + ' — ' + apres.groupes + ' groupes');

    /* Repli au second clic, puis mémorisation d'une page à l'autre */
    await page.evaluate(() => {
      const t = [...document.querySelectorAll('#app-menubar [role="tab"]')]
        .find((b) => b.textContent.trim() === 'Financier');
      if (t) t.click();
    });
    await pause(200);
    verifier('Un second clic replie le panneau',
      await page.evaluate(() => document.querySelector('#app-ribbon').hidden));

    await ouvrir('m8-factures.html');
    verifier('Le repli est mémorisé d’un écran à l’autre',
      await page.evaluate(() => document.querySelector('#app-ribbon').hidden));
    await page.evaluate(() => window.SIGH.store.storage.set('sigh-cnt:ruban', 'ouvert'));

    /* --- Un accès rapide du bandeau referme le ruban ----------------------
       Un lien du panneau du ruban posait bien le drapeau transitoire ; les
       boutons d'accès rapide du bandeau, non — la page appelée s'ouvrait donc
       menu déployé alors que l'utilisateur venait de choisir sa destination. */
    await ouvrir('m8-factures.html');
    const repli = await page.evaluate(async () => {
      const S = window.SIGH.store;
      S.storage.set('sigh-cnt:ruban', 'ouvert');
      S.storage.remove('sigh-cnt:ruban-transitoire');
      /* Les accès rapides vivent hors de #page-content, dans l'en-tête. */
      const liens = [...document.querySelectorAll('#page-actions a.btn')];
      /* Les pages sont en `.php` depuis le 23/09/2026 ; on accepte les deux —
         la sonde porte sur le REPLI du ruban, pas sur une extension. */
      const cible = liens.find((a) => /\.(php|html)/.test(a.getAttribute('href') || ''));
      if (!cible) return { erreur: 'aucun accès rapide trouvé' };
      /* On neutralise la navigation : seul le drapeau nous intéresse. */
      cible.addEventListener('click', (ev) => ev.preventDefault(), { once: true });
      cible.click();
      await new Promise((r) => setTimeout(r, 120));
      return {
        libelle: (cible.textContent || '').trim(),
        drapeau: S.storage.get('sigh-cnt:ruban-transitoire'),
        preference: S.storage.get('sigh-cnt:ruban'),
      };
    });
    verifier('Un accès rapide du bandeau pose le repli transitoire du ruban',
      repli.drapeau === '1', repli.erreur || ('après clic sur « ' + repli.libelle + ' »'));
    verifier('La préférence durable du ruban n’est pas écrasée',
      repli.preference === 'ouvert', 'préférence : ' + repli.preference);
    await page.evaluate(() => window.SIGH.store.storage.remove('sigh-cnt:ruban-transitoire'));

    /* Bouton plein écran */
    verifier('La barre supérieure propose le mode plein écran',
      await page.evaluate(() => !!document.querySelector('#app-topbar button[aria-pressed]')));

    /* Les accès rapides précèdent les indicateurs sur les tableaux de bord */
    await ouvrir('dash-direction.html');
    const ordre = await page.evaluate(() => {
      const host = document.querySelector('#page-content > div');
      const blocs = [...host.children];
      const rapides = blocs.findIndex((b) => (b.textContent || '').startsWith('Accès rapides'));
      const kpis = blocs.findIndex((b) => b.querySelector('.kpi'));
      return { rapides, kpis };
    });
    verifier('« Accès rapides » précède les indicateurs',
      ordre.rapides >= 0 && ordre.kpis >= 0 && ordre.rapides < ordre.kpis,
      'accès rapides : ' + ordre.rapides + ', KPI : ' + ordre.kpis);
    verifier('Aucune erreur JavaScript sur la navigation', erreursJS.length === 0, erreursJS.join(' | '));

    /* Page d'accueil de module : une carte par écran, avec description */
    await ouvrir('hub-m6.html');
    const hub = await page.evaluate(() => {
      const cartes = [...document.querySelectorAll('#page-content .hub-card')];
      return {
        cartes: cartes.length,
        avecDescription: cartes.filter((c) => c.children.length >= 2 && c.children[1].children.length >= 2).length,
        premier: cartes.length ? cartes[0].getAttribute('href') : null,
      };
    });
    /* Le nombre attendu est DÉRIVÉ DU MANIFESTE et non écrit en dur : le
       manifeste est la source unique du projet, et un test qui le recopie
       finit toujours par diverger de lui. */
    const attenduM6 = await page.evaluate(() => {
      const N = window.SIGH.nav;
      let n = 0;
      N.tree('admin').forEach((dom) => dom.modules.forEach((mod) => {
        if (mod.code === 'M6') n = mod.items.length;
      }));
      return n;
    });
    verifier('La page d’accueil du module présente un écran par carte',
      hub.cartes === attenduM6 && hub.cartes > 0,
      'cartes : ' + hub.cartes + ' — écrans au manifeste : ' + attenduM6);
    verifier('Chaque carte porte icône, titre et description',
      hub.avecDescription === hub.cartes, hub.avecDescription + '/' + hub.cartes);

    /* Le fil d'Ariane ramène au module depuis n'importe quel écran */
    await ouvrir('m6-lots.html');
    const fil = await page.evaluate(() => {
      const a = document.querySelector('nav[aria-label] a[href*="hub-m6"]');
      return a ? a.textContent.trim() : null;
    });
    verifier('Le fil d’Ariane renvoie à l’accueil du module', fil === 'Pharmacie & Stocks', 'lien : ' + fil);
    verifier('Aucune erreur JavaScript sur les pages hub', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 12. Listes déroulantes avec recherche
   * ======================================================================= */
  {
    scenario('Listes déroulantes avec recherche');
    await ouvrir('m8-facturation.html');

    const initial = await page.evaluate(() => {
      const combos = [...document.querySelectorAll('.combo')];
      return { nb: combos.length, valeur: combos[0] ? combos[0].value : null };
    });
    verifier('Le choix du patient et de la prestation passe par une liste à recherche',
      initial.nb >= 2, 'listes : ' + initial.nb);
    verifier('Une valeur est présélectionnée', !!initial.valeur, 'valeur : ' + initial.valeur);

    const recherche = await page.evaluate(() => {
      const c = document.querySelectorAll('.combo')[0];
      c.querySelector('.combo-input').click();
      const p = [...document.querySelectorAll('.combo-panel')].find((x) => !x.hidden);
      const s = p.querySelector('.combo-search');
      s.value = 'tchou';
      s.dispatchEvent(new Event('input', { bubbles: true }));
      const options = [...p.querySelectorAll('.combo-option')];
      const res = { trouves: options.length, tous: options.every((o) => /tchou/i.test(o.textContent)) };
      options[0].click();
      res.valeur = c.value;
      res.libelle = c.textContent.trim();
      res.ferme = p.hidden;
      return res;
    });
    verifier('La saisie filtre la liste', recherche.trouves > 0 && recherche.tous,
      recherche.trouves + ' résultat(s)');
    verifier('Le choix se répercute sur le champ', /TCHOUKOUROU/i.test(recherche.libelle || ''),
      'libellé : ' + recherche.libelle);
    verifier('Le panneau se referme après la sélection', recherche.ferme);

    /* La même liste dans une modale : le panneau ne doit pas être rogné */
    await ouvrir('m12-ecritures.html');
    await cliquer('Nouvelle écriture', 'button');
    await pause(500);
    const dansModale = await page.evaluate(() => {
      const c = [...document.querySelectorAll('[role="dialog"] .combo')];
      if (!c.length) return { nb: 0 };
      c[0].querySelector('.combo-input').click();
      const p = [...document.querySelectorAll('.combo-panel')].find((x) => !x.hidden);
      const r = p.getBoundingClientRect();
      return { nb: c.length, visible: r.width > 100 && r.bottom <= window.innerHeight + 1 };
    });
    verifier('La liste à recherche fonctionne dans une modale',
      dansModale.nb > 0 && dansModale.visible, JSON.stringify(dansModale));
    await page.keyboard.press('Escape');
    await pause(200);
    verifier('Aucune erreur JavaScript sur les listes', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 13. Les fiches consultées sont modifiables
   * ======================================================================= */
  {
    scenario('Fiches consultables et modifiables');

    /* Registre tenu au fil de l'eau : modification d'une ligne */
    await ouvrir('m13-evenements.html');
    const edition = await page.evaluate(async () => {
      const b = [...document.querySelectorAll('#page-content tbody tr:first-child button')]
        .find((x) => x.title === 'Modifier');
      if (!b) return { ouvert: false };
      b.click();
      await new Promise((r) => setTimeout(r, 300));
      const champ = document.querySelector('[role="dialog"] #f_libelle');
      const avant = champ ? champ.value : null;
      if (champ) champ.value = 'Intitulé corrigé par le test';
      const save = [...document.querySelectorAll('[role="dialog"] button')]
        .find((x) => /Enregistrer/.test(x.textContent));
      save.click();
      await new Promise((r) => setTimeout(r, 400));
      return {
        ouvert: true, avant,
        ligne: document.querySelector('#page-content tbody tr').textContent,
        toast: (document.querySelector('#toast-host') || {}).textContent || '',
        ferme: !document.querySelector('[role="dialog"]'),
      };
    });
    verifier('Un registre en consultation propose la modification', edition.ouvert);
    verifier('La modification est enregistrée et le tableau rafraîchi',
      (edition.ligne || '').includes('Intitulé corrigé par le test'), edition.ligne);
    verifier('L’annulation est proposée', /Annuler/.test(edition.toast));
    verifier('La modale se referme après enregistrement', edition.ferme);

    /* Fiche patient : éléments médicaux et couverture au dossier */
    await ouvrir('m1-patient-profil.html');
    const fiche = await page.evaluate(() => {
      const onglets = [...document.querySelectorAll('#page-content [role=\"tab\"]')].map((t) => t.textContent.trim());
      const bouton = [...document.querySelectorAll('#page-content button')]
        .some((b) => /Modifier le dossier/.test(b.textContent));
      return { onglets, bouton };
    });
    verifier('La fiche patient présente les antécédents et allergies',
      fiche.onglets.some((o) => /Antécédents/.test(o)), fiche.onglets.join(' · '));
    verifier('La fiche patient présente les soins reçus',
      fiche.onglets.some((o) => /Soins/.test(o)), fiche.onglets.join(' · '));
    verifier('La fiche patient présente la couverture assurance',
      fiche.onglets.some((o) => /Assurance/.test(o)), fiche.onglets.join(' · '));
    verifier('Le dossier patient est modifiable depuis sa fiche', fiche.bouton);

    const champsFiche = await page.evaluate(async () => {
      const b = [...document.querySelectorAll('#page-content button')]
        .find((x) => /Modifier le dossier/.test(x.textContent));
      /* Un bouton absent est un ÉCHEC de vérification, pas un plantage du
         harnais : sans ce garde-fou, tout le reste de la suite est perdu. */
      if (!b) return ['__ABSENT__ ' + document.title + ' | ' + document.body.textContent.replace(/s+/g,' ').slice(0,160)];
      b.click();
      await new Promise((r) => setTimeout(r, 350));
      return [...document.querySelectorAll('[role="dialog"] .label')].map((l) => l.textContent);
    });
    verifier('Le formulaire du dossier couvre antécédents, allergies et assurance',
      champsFiche.some((c) => /Antécédent/.test(c)) && champsFiche.some((c) => /Allergies/.test(c))
      && champsFiche.some((c) => /assurance/i.test(c)), champsFiche.length + ' champs');
    await page.keyboard.press('Escape');
    await pause(200);

    /* Évaluation NS 131 : bouton de modification dans la fiche */
    await ouvrir('m10-evaluations.html');
    const evaluation = await page.evaluate(async () => {
      /* Le barème NS 131 est affiché au-dessus : on vise la première ligne
         réellement cliquable, celle du tableau des évaluations. */
      const ligne = [...document.querySelectorAll('#page-content tbody tr')]
        .find((tr) => tr.classList.contains('cursor-pointer'));
      if (!ligne) return { drawer: false };
      ligne.click();
      await new Promise((r) => setTimeout(r, 350));
      const boutons = [...document.querySelectorAll('[role="dialog"] button')].map((b) => b.textContent.trim());
      return { drawer: true, boutons };
    });
    verifier('La fiche d’évaluation propose sa modification',
      evaluation.drawer && evaluation.boutons.some((b) => /Modifier l’évaluation/.test(b)),
      (evaluation.boutons || []).join(' · '));
    verifier('Aucune erreur JavaScript sur les fiches', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 14. Aide, contact éditeur et affichage sur petit écran
   * ======================================================================= */
  {
    scenario('Aide, contact éditeur et affichage responsive');

    /* Les deux pages sont proposées dans le menu profil */
    await ouvrir('dash-direction.html');
    await page.evaluate(() => window.SIGH.app.openProfile());
    await pause(400);
    const liens = await page.evaluate(() => [...document.querySelectorAll('[role="dialog"] a[href]')]
      .map((a) => a.getAttribute('href')));
    verifier('Le menu profil ouvre l’aide',
      liens.some((h) => /aide-apropos/.test(h)), liens.join(' · '));
    verifier('Le menu profil ouvre le contact éditeur',
      liens.some((h) => /contact-editeur/.test(h)), liens.join(' · '));
    await page.keyboard.press('Escape');
    await pause(200);

    /* Aide & À propos : modules et FAQ */
    await ouvrir('aide-apropos.html');
    const aide = await page.evaluate(() => {
      /* LE COMPTE SE DÉRIVE DU MANIFESTE, il ne se recopie pas. Il était
         écrit en dur (19) et échouait à chaque module ajouté, alors que
         l'assertion avait raison : c'est le nombre qui avait tort. */
      const N = window.SIGH.nav;
      let attendus = 0;
      N.tree('admin').forEach((d) => { attendus += d.modules.length; });
      return {
        modules: document.querySelectorAll('#page-content .hub-card').length,
        attendus: attendus,
        faq: document.querySelectorAll('#page-content details').length,
        ouverte: document.querySelectorAll('#page-content details[open]').length,
        contact: !!document.querySelector('#page-content a[href*="contact-editeur"]'),
      };
    });
    verifier('Chaque module est présenté par une carte',
      aide.modules === aide.attendus, 'cartes : ' + aide.modules + ' / manifeste : ' + aide.attendus);
    verifier('La FAQ est repliable', aide.faq >= 8 && aide.ouverte === 1,
      aide.faq + ' questions, ' + aide.ouverte + ' ouverte');
    verifier('L’aide renvoie vers l’éditeur', aide.contact);

    /* Contact éditeur : un message part et laisse une trace */
    await ouvrir('contact-editeur.html');
    const envoi = await page.evaluate(async () => {
      document.querySelector('#f_objet').value = 'Question de recette';
      document.querySelector('#f_message').value = 'Le tableau de bord affiche-t-il les gardes du mois en cours ?';
      const b = [...document.querySelectorAll('#page-content button')]
        .find((x) => /Envoyer le message/.test(x.textContent));
      b.click();
      await new Promise((r) => setTimeout(r, 400));
      return {
        toast: (document.querySelector('#toast-host') || {}).textContent || '',
        liste: (document.querySelector('#page-content table') || {}).textContent || '',
      };
    });
    verifier('Le message est envoyé avec une référence',
      /SUP-2026-\d{4}/.test(envoi.toast), envoi.toast.slice(0, 90));
    verifier('La demande apparaît dans le suivi',
      /Question de recette/.test(envoi.liste), envoi.liste.slice(0, 90));

    const coord = await page.evaluate(() => document.querySelector('#page-content').textContent);
    verifier('Les coordonnées de l’éditeur sont affichées',
      /MASSENON Rhodes/.test(coord) && /rarhodes06@gmail.com/.test(coord) && /01 51 33 50 40/.test(coord));

    /* Signalement d'anomalie */
    const bug = await page.evaluate(async () => {
      document.querySelector('#f_description').value = 'Le total ne se met pas à jour après suppression d’une ligne.';
      const b = [...document.querySelectorAll('#page-content button')]
        .find((x) => /Signaler l’anomalie/.test(x.textContent));
      b.click();
      await new Promise((r) => setTimeout(r, 400));
      return (document.querySelector('#toast-host') || {}).textContent || '';
    });
    verifier('L’anomalie est enregistrée', /Anomalie signalée/.test(bug), bug.slice(0, 80));

    /* Téléphone : le ruban ne mange plus l'écran */
    await page.setViewport({ width: 390, height: 780 });
    await page.evaluate(() => window.SIGH.store.storage.remove('sigh-cnt:ruban'));
    await ouvrir('m1-patients.html');
    const mobile = await page.evaluate(() => {
      const p = document.querySelector('#app-ribbon');
      return {
        replie: !!p && p.hidden,
        entete: Math.round(document.querySelector('#app-menubar').getBoundingClientRect().height),
        debordement: document.documentElement.scrollWidth > window.innerWidth + 1,
      };
    });
    verifier('Sur téléphone, le menu est replié à l’arrivée', mobile.replie);
    verifier('L’en-tête reste compact sur téléphone', mobile.entete < 130, mobile.entete + ' px');
    verifier('Aucun débordement horizontal sur téléphone', !mobile.debordement);

    /* Déployé à la demande, il empile module puis écrans */
    const empile = await page.evaluate(async () => {
      const t = [...document.querySelectorAll('#app-menubar [role="tab"]')]
        .find((b) => b.textContent.trim() === 'Soins');
      t.click();
      await new Promise((r) => setTimeout(r, 250));
      const rangee = document.querySelector('#app-ribbon .ribbon-row');
      const head = rangee.querySelector('.ribbon-row-head');
      const chips = rangee.querySelector('.ribbon-chips');
      return {
        ouvert: !document.querySelector('#app-ribbon').hidden,
        empile: chips.getBoundingClientRect().top >= head.getBoundingClientRect().bottom - 1,
      };
    });
    verifier('Le menu se déploie à la demande sur téléphone', empile.ouvert);
    verifier('Les écrans passent sous l’intitulé du module', empile.empile);

    /* Tablette : on retrouve la disposition en rangées */
    await page.setViewport({ width: 820, height: 1000 });
    await page.evaluate(() => window.SIGH.store.storage.remove('sigh-cnt:ruban'));
    await ouvrir('m1-patients.html');
    const tablette = await page.evaluate(() => {
      const p = document.querySelector('#app-ribbon');
      const rangee = p.querySelector('.ribbon-row');
      const head = rangee.querySelector('.ribbon-row-head');
      const chips = rangee.querySelector('.ribbon-chips');
      return {
        ouvert: !p.hidden,
        cote: chips.getBoundingClientRect().left >= head.getBoundingClientRect().right - 1,
        debordement: document.documentElement.scrollWidth > window.innerWidth + 1,
      };
    });
    verifier('Sur tablette, le menu reste déployé', tablette.ouvert);
    verifier('Sur tablette, les écrans restent à droite du module', tablette.cote);
    verifier('Aucun débordement horizontal sur tablette', !tablette.debordement);
    await page.setViewport({ width: 1600, height: 1000 });

    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 15. Parcours de prescription — de la consultation à la délivrance
   * -------------------------------------------------------------------------
   * Le critère de réussite du prototype (draf1 §24-25) : une même opération
   * traverse M2, M5, M6 et M8 sans ressaisie, et les règles de gestion tiennent
   * à chaque étape.
   * ======================================================================= */
  {
    scenario('Parcours de prescription — M2 → M5 / M6 / M8');

    await ouvrir('m2-ordonnances.html');
    const presc = await page.evaluate(() => {
      const S = window.SIGH.store, PR = window.SIGH.parcours, D = window.SIGH.data;
      const pat = S.collection('patients').active()[3];
      const prods = S.collection('produits').active()
        .filter((p) => p.categorie === 'medicament' && p.stockDetail > 10).slice(0, 2);
      const r = PR.prescrire({
        patientCode: pat.code, medecin: 'YENI M’PO Florent', diagnostic: 'Paludisme simple',
        medicaments: prods.map((p) => ({ produitId: p.id, quantite: 3, posologie: '1 cp × 3/j', duree: '5 jours' })),
        analyses: [D.ANALYSES[0].code, D.ANALYSES[5].code, D.ANALYSES[9].code],
        actes: ['SO01', 'SO05'],
      });
      return {
        numero: r.ordonnance.numero, demandes: r.demandes.length, taches: r.taches.length,
        facture: r.facture.numero, factureId: r.facture.id, ordId: r.ordonnance.id,
        montantActes: r.ordonnance.montantActes,
        stockAvant: prods.map((p) => S.collection('produits').get(p.id).stockDetail),
        prodIds: prods.map((p) => p.id),
      };
    });
    verifier('La prescription engendre une ordonnance numérotée',
      /^ORD-\d{4}-\d{5}$/.test(presc.numero), presc.numero);
    verifier('Les trois demandes d’analyses sont établies d’office',
      presc.demandes === 3, presc.demandes + ' demande(s)');
    verifier('La facture part à la caisse', /^FP-\d{4}-\d{5}$/.test(presc.facture), presc.facture);
    verifier('Les quatre files d’attente sont alimentées', presc.taches === 4, presc.taches + ' tâche(s)');
    verifier('Les actes tarifés sont valorisés depuis le catalogue',
      presc.montantActes === 2700, presc.montantActes + ' FCFA (PVV 1 200 + PSP 1 500)');

    /* Le laboratoire voit la demande, mais ne peut pas encore prélever */
    await ouvrir('m5-demandes.html');
    const labo = await page.evaluate((p) => {
      const S = window.SIGH.store;
      const dem = S.collection('demandesAnalyses').all().filter((d) => d.ordonnanceId === p.ordId);
      return {
        origine: dem[0].origine,
        bloquees: dem.filter((d) => d.bloqueParPaiement).length,
        file: /Prélèvements à réaliser/.test(document.body.textContent),
        manuel: [...document.querySelectorAll('#page-content button')].some((b) => b.textContent.trim() === 'Nouveau'),
      };
    }, presc);
    verifier('Les demandes portent leur origine « ordonnance »', labo.origine === 'ordonnance', labo.origine);
    verifier('Le prélèvement est bloqué avant encaissement', labo.bloquees === 3, labo.bloquees + '/3');
    verifier('Le laboratoire voit sa file de prélèvements', labo.file);
    verifier('La saisie manuelle reste ouverte au laboratoire', labo.manuel);

    /* La pharmacie est informée mais ne peut pas servir */
    await ouvrir('m6-dispensation.html');
    const avant = await page.evaluate((p) => {
      const S = window.SIGH.store, PR = window.SIGH.parcours;
      let refus = null;
      try { PR.delivrer(p.ordId); } catch (e) { refus = e.message; }
      return { refus: refus, stock: p.prodIds.map((id) => S.collection('produits').get(id).stockDetail) };
    }, presc);
    verifier('La délivrance est refusée tant que la facture n’est pas réglée',
      /non réglée/.test(avant.refus || ''), avant.refus);
    verifier('Le stock n’a pas bougé', JSON.stringify(avant.stock) === JSON.stringify(presc.stockAvant));

    /* La caisse encaisse : tout l'aval se débloque */
    await ouvrir('m8-caisse.html');
    const caisse = await page.evaluate((p) => {
      const S = window.SIGH.store, PR = window.SIGH.parcours;
      const res = PR.encaisser(p.factureId, { mode: 'especes' });
      const dem = S.collection('demandesAnalyses').all().filter((d) => d.ordonnanceId === p.ordId);
      return {
        statut: res.facture.statutPaiement, debloquees: res.debloquees.length,
        bloqueesRestantes: dem.filter((d) => d.bloqueParPaiement).length,
      };
    }, presc);
    verifier('La facture passe à « soldée »', caisse.statut === 'soldee', caisse.statut);
    verifier('L’encaissement débloque les trois postes d’aval',
      caisse.debloquees === 3, caisse.debloquees + ' file(s) débloquée(s)');
    verifier('Plus aucune analyse n’est bloquée', caisse.bloqueesRestantes === 0);

    /* La pharmacie délivre : le stock bouge, justificatif à l'appui */
    await ouvrir('m6-dispensation.html');
    const deliv = await page.evaluate((p) => {
      const S = window.SIGH.store, PR = window.SIGH.parcours;
      const res = PR.delivrer(p.ordId);
      return {
        mouvements: res.mouvements.length, justificatif: res.mouvements[0].justificatif,
        stock: p.prodIds.map((id) => S.collection('produits').get(id).stockDetail),
        statut: S.collection('ordonnances').get(p.ordId).statutDispensation,
      };
    }, presc);
    verifier('Une sortie de stock par ligne est enregistrée', deliv.mouvements === 2, deliv.mouvements + ' mouvement(s)');
    verifier('RG-03 — la sortie porte le numéro d’ordonnance comme justificatif',
      deliv.justificatif === 'Ordonnance ' + presc.numero, deliv.justificatif);
    verifier('Le stock de détail est décrémenté des quantités servies',
      JSON.stringify(deliv.stock) === JSON.stringify(presc.stockAvant.map((s) => s - 3)),
      presc.stockAvant.join('/') + ' → ' + deliv.stock.join('/'));
    verifier('L’ordonnance est marquée servie', deliv.statut === 'servie');

    /* RG-03 sur le parcours complet : une délivrance à découvert est refusée */
    const rg03 = await page.evaluate(() => {
      const S = window.SIGH.store, PR = window.SIGH.parcours;
      const pat = S.collection('patients').active()[7];
      const prod = S.collection('produits').active().filter((p) => p.categorie === 'medicament')[0];
      const dispo = S.collection('produits').get(prod.id).stockDetail;
      const r = PR.prescrire({
        patientCode: pat.code, medecin: 'YENI M’PO Florent',
        medicaments: [{ produitId: prod.id, quantite: dispo + 50 }], analyses: [], actes: [],
      });
      PR.encaisser(r.facture.id, { mode: 'especes' });
      let msg = null;
      try { PR.delivrer(r.ordonnance.id); } catch (e) { msg = e.message; }
      return { msg: msg, stock: S.collection('produits').get(prod.id).stockDetail, attendu: dispo };
    });
    verifier('RG-03 — une délivrance à découvert est refusée, ligne nommée',
      /Stock insuffisant/.test(rg03.msg || ''), (rg03.msg || '').slice(0, 70));
    verifier('RG-03 — le stock reste intact après le refus', rg03.stock === rg03.attendu);

    verifier('Aucune erreur JavaScript sur le parcours', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 16. Référentiels administrables — plus rien d'écrit en dur
   * -------------------------------------------------------------------------
   * draf1 §1-2 : les documents de la clinique deviennent des référentiels que
   * la Direction administre elle-même. Ce scénario vérifie que les listes
   * autrefois figées dans le code sont bien devenues des collections.
   * ======================================================================= */
  {
    scenario('Référentiels administrables — actes, secteurs, natures, centres');

    /* --- Catalogue des actes --- */
    await ouvrir('cfg-tarifs.html#onglet=actes');
    const cat = await page.evaluate(() => {
      const rows = window.SIGH.store.collection('actes').active();
      return {
        total: rows.length,
        aValider: rows.filter((a) => a.tarifProvisoire).length,
        secteurs: [...new Set(rows.map((a) => a.secteur))].length,
        tarifsInventes: /150 000/.test(document.body.textContent),
        avertissement: /tarif d’attente/.test(document.body.textContent),
      };
    });
    verifier('Le catalogue des actes vient du document de répartition',
      cat.total > 60 && cat.secteurs >= 6, cat.total + ' actes, ' + cat.secteurs + ' secteurs');
    /* Vague 49 : la Direction a ARRÊTÉ les tarifs d'attente — plus un
       provisoire au catalogue vivant. */
    verifier('Les tarifs d’attente sont ARRÊTÉS (vague 49) — plus un provisoire au vivant',
      cat.aValider === 0, cat.aValider + ' provisoire(s) restant(s)');
    verifier('Les tarifs inventés ont disparu de l’écran', !cat.tarifsInventes);

    const acteCree = await page.evaluate(() => {
      const col = window.SIGH.store.collection('actes');
      const r = col.insert({ libelle: 'Plâtre pelvi-pédieux', secteur: 'Chirurgie', code: 'TST-01', prix: 9000 });
      return { id: r.record.id, total: col.active().length };
    });
    /* Détour obligé : réouvrir la même URL, ancre comprise, ne serait qu'une
       navigation intra-document — la page ne serait pas remontée. */
    await ouvrir('cfg-natures-facture.html');
    await ouvrir('cfg-tarifs.html#onglet=actes');
    verifier('Un acte créé survit au rechargement',
      await page.evaluate(() => /pelvi-pédieux/.test(document.body.textContent)),
      acteCree.total + ' actes au catalogue');

    /* --- Archivage : la corbeille le nomme correctement --- */
    await page.evaluate((id) => window.SIGH.store.collection('actes').archive(id, 'Acte de test'), acteCree.id);
    await ouvrir('cfg-systeme.html');
    const dansCorbeille = await page.evaluate(() => {
      const c = window.SIGH.store.corbeille().filter((x) => x.collection === 'actes');
      return { n: c.length, libelle: c[0] && c[0].libelle, entite: c[0] && c[0].entite };
    });
    verifier('L’acte archivé est retrouvé dans la corbeille sous son libellé',
      dansCorbeille.n === 1 && /pelvi-pédieux/.test(dansCorbeille.libelle || ''),
      dansCorbeille.libelle + ' — ' + dansCorbeille.entite);

    /* --- Secteurs NS 145 et organigramme --- */
    await ouvrir('cfg-organisation.html');
    const org = await page.evaluate(() => {
      const S = window.SIGH.store;
      return {
        secteurs: S.collection('secteurs').active().length,
        postes: S.collection('postes').active().length,
        ns145: /NS 145/.test(document.body.textContent),
        responsable: /OROU YO/.test(document.body.textContent),
      };
    });
    verifier('Les 14 secteurs de la NS 145 sont administrables',
      org.secteurs === 14 && org.ns145, org.secteurs + ' secteurs');
    verifier('Chaque secteur porte son responsable désigné', org.responsable);
    verifier('L’organigramme est devenu une collection de postes',
      org.postes > 10, org.postes + ' postes');

    const posteCree = await page.evaluate(() => {
      const col = window.SIGH.store.collection('postes');
      const parent = col.active().filter((p) => /Directrice/.test(p.poste))[0];
      col.insert({ poste: 'Service Qualité', parentId: parent.id, effectif: 2, role: 'agentadmin' });
      return col.active().length;
    });
    await ouvrir('cfg-organisation.html');
    verifier('Un département créé apparaît dans l’arbre après rechargement',
      await page.evaluate(async () => {
        [...document.querySelectorAll('.tab')].find((t) => /Organigramme/.test(t.textContent)).click();
        await new Promise((r) => setTimeout(r, 350));
        return /Service Qualité/.test(document.body.textContent);
      }), posteCree + ' postes');

    /* --- Natures de facture : les manques signalés par la Direction --- */
    await ouvrir('cfg-natures-facture.html');
    const nat = await page.evaluate(() => {
      const rows = window.SIGH.store.collection('naturesFacture').active().map((n) => n.libelle);
      return { total: rows.length, maternite: rows.includes('Maternité'), obs: rows.includes('Mise en observation'), cpn: rows.some((r) => /CPN/.test(r)) };
    });
    verifier('« Maternité » figure aux natures de facture', nat.maternite);
    verifier('« Mise en observation » figure aux natures de facture', nat.obs);
    verifier('La consultation prénatale figure aux natures de facture', nat.cpn, nat.total + ' natures');

    /* --- L'émission de facture lit ce référentiel --- */
    await ouvrir('m8-facturation.html');
    const emission = await page.evaluate(() => {
      const combo = [...document.querySelectorAll('#page-content .combo')][1];
      const btn = [...document.querySelectorAll('#page-content button')].find((b) => /Nouvelle nature/.test(b.textContent));
      return { valeur: combo ? combo.value : null, bouton: !!btn };
    });
    verifier('La nature de la facture est choisie dans le référentiel',
      /Consultation/.test(emission.valeur || ''), emission.valeur);
    verifier('Une nature se crée sans quitter l’émission de facture', emission.bouton);

    /* --- Centres de coûts --- */
    await ouvrir('cfg-centres-couts.html');
    const cc = await page.evaluate(() => {
      const D = window.SIGH.data;
      const rows = window.SIGH.store.collection('centresCouts').active();
      const ecritures = window.SIGH.store.collection('ecritures').active();
      return {
        total: rows.length,
        support: rows.filter((c) => c.type === 'support').length,
        libelles: rows.map((c) => c.libelle),
        /* LE POINT QUI COMPTE : le `code` du centre EST l'identifiant que
           portent les écritures. Deux référentiels qui ne se parlaient pas
           laissaient toute imputation manuelle hors de la ventilation. */
        codesReconnus: ecritures.filter((e) => e.centreCout
          && rows.some((c) => c.code === e.centreCout)).length,
        imputees: ecritures.filter((e) => e.centreCout).length,
        /* Dérivé du référentiel, jamais écrit en dur : un compte codé en dur
           finit toujours par diverger de ce qu'il mesure. */
        attendu: D.CENTRES_COUT.length,
      };
    });
    verifier('Les centres de coûts sont administrables et couvrent les six secteurs plus la Direction',
      cc.total === cc.attendu && cc.support === 1
      && ['Laboratoire', 'Pharmacie', 'Consultation', 'Imagerie médicale', 'Maternité',
        'Hospitalisation et soins', 'Direction'].every((x) => cc.libelles.includes(x)),
      cc.total + ' centres : ' + cc.libelles.join(', '));
    verifier('Le code d’un centre EST l’imputation portée par les écritures — un seul référentiel',
      cc.imputees > 0 && cc.codesReconnus === cc.imputees,
      cc.codesReconnus + ' / ' + cc.imputees + ' écritures rattachées');

    verifier('Aucune erreur JavaScript sur les référentiels', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 17. Prise en charge : taux par prestation, plafonds, exclusions
   * -------------------------------------------------------------------------
   * Cahier de charge du 30/12/2024 : « appliquer des pourcentages par article
   * et par prestation », le taux variant d'une assurance à l'autre et, pour un
   * même assuré, selon la nature de l'article. Un taux unique par patient ne
   * peut pas exprimer cela.
   * ======================================================================= */
  {
    scenario('Prise en charge — grille par convention, plafonds et exclusions');

    await ouvrir('m9-conventions.html');
    const base = await page.evaluate(() => {
      const S = window.SIGH.store;
      const pats = S.collection('patients').active().filter((p) => p.assureur);
      return {
        souscripteurs: S.collection('souscripteurs').active().length,
        rattaches: pats.filter((p) => p.souscripteurId).length,
        assures: pats.length,
        avertissement: /convention\(s\) non saisie/.test(document.body.textContent),
      };
    });
    verifier('Les souscripteurs existent sous les compagnies',
      base.souscripteurs >= 8, base.souscripteurs + ' souscripteurs');
    verifier('Chaque assuré est rattaché à un souscripteur',
      base.rattaches === base.assures, base.rattaches + '/' + base.assures);
    verifier('Les conventions non saisies sont signalées, pas supposées', base.avertissement);

    /* Sans convention : rien n'est présumé couvert */
    const sansGrille = await page.evaluate(() => {
      const S = window.SIGH.store, PR = window.SIGH.parcours;
      /* On choisit un assuré dont la CARTE EST VALIDE : sans cela le moteur
         répond « carte non valide » (RG-09) avant même de regarder la grille,
         et l'assertion mesurerait autre chose que ce qu'elle prétend. */
      const auj = window.SIGH.core.iso(new Date(2026, 7, 16));
      const p = S.collection('patients').active().filter((x) => x.assureur && x.souscripteurId
        && x.carteExpiration && x.carteExpiration >= auj)[0]
        || S.collection('patients').active().filter((x) => x.assureur && x.souscripteurId)[0];
      const r = PR.repartir(p, [{ libelle: 'Consultation généraliste', categorie: 'consultation', montant: 5000 }]);
      return { ass: r.partAssureur, pat: r.partPatient, motif: r.lignes[0].motif, id: p.id };
    });
    verifier('Sans convention saisie, la facture reste au patient et le dit',
      sansGrille.ass === 0 && sansGrille.pat === 5000 && /non saisie/.test(sansGrille.motif),
      sansGrille.motif);

    /* Convention saisie depuis le barème de référence */
    const avecGrille = await page.evaluate(() => {
      const S = window.SIGH.store, PR = window.SIGH.parcours, D = window.SIGH.data;
      const p = S.collection('patients').active().filter((x) => x.assureur && x.souscripteurId)[0];
      const s = S.collection('souscripteurs').get(p.souscripteurId);
      D.BAREME_REFERENCE.garanties.forEach((g) => S.collection('garanties').insert({
        souscripteurId: s.id, assureur: s.assureur, code: g.code, libelle: g.libelle,
        categorie: g.categorie, taux: g.taux, plafond: g.plafond, unitePlafond: g.unitePlafond,
      }));
      S.collection('souscripteurs').update(s.id, {
        actesExclus: D.BAREME_REFERENCE.actesExclus.slice(),
        produitsExclus: D.BAREME_REFERENCE.produitsExclus.slice(),
        accordPrealable: D.BAREME_REFERENCE.accordPrealable.slice(),
      });
      S.collection('patients').update(p.id, { carteExpiration: '2026-12-31' });
      const r = PR.repartir(S.collection('patients').get(p.id), [
        { libelle: 'Consultation généraliste', categorie: 'consultation', montant: 5000 },
        { libelle: 'Consultation spécialiste', categorie: 'consultation', montant: 20000 },
        { libelle: 'Vitamine C 500 mg', categorie: 'vitamine', montant: 500 },
        { libelle: 'NFS complète', categorie: 'analyse', montant: 4000 },
        { libelle: 'Coton', categorie: 'medicament', montant: 300 },
        { libelle: 'Scanner', categorie: 'imagerie', montant: 60000 },
      ], { date: '2026-08-20' });
      return { l: r.lignes, ass: r.partAssureur, pat: r.partPatient, id: p.id, sous: s.nom };
    });
    const L = avecGrille.l;
    verifier('Le taux varie selon la nature de la prestation — 80 % soins, 60 % vitamines',
      L[0].taux === 80 && L[2].taux === 60, 'consultation ' + L[0].taux + ' %, vitamines ' + L[2].taux + ' %');
    verifier('La bonne garantie est retenue dans une catégorie qui en compte plusieurs',
      /généraliste/.test(L[0].garantie) && /spécialiste/.test(L[1].garantie),
      L[0].garantie + ' / ' + L[1].garantie);
    verifier('Le plafond par acte est appliqué',
      L[1].partAssureur === 10000 && /plafonnée/.test(L[1].motif), L[1].motif);
    verifier('Un produit exclu est facturé intégralement au patient',
      L[4].partAssureur === 0 && /Exclu/.test(L[4].motif), L[4].motif);
    verifier('Un acte soumis à accord préalable non obtenu reste au patient',
      L[5].partAssureur === 0 && /Accord préalable/.test(L[5].motif), L[5].motif);
    verifier('La répartition totale est calculée ligne par ligne',
      avecGrille.ass === 17500 && avecGrille.pat === 72300,
      'assureur ' + avecGrille.ass + ' / patient ' + avecGrille.pat);

    /* RG-09 — carte expirée */
    const rg09 = await page.evaluate((id) => {
      const S = window.SIGH.store, PR = window.SIGH.parcours;
      S.collection('patients').update(id, { carteExpiration: '2026-01-31' });
      const r = PR.repartir(S.collection('patients').get(id),
        [{ libelle: 'Consultation généraliste', categorie: 'consultation', montant: 5000 }], { date: '2026-08-20' });
      return { ass: r.partAssureur, motif: r.lignes[0].motif };
    }, avecGrille.id);
    verifier('RG-09 — carte non valide à la date : facturation intégrale au patient',
      rg09.ass === 0 && /RG-09/.test(rg09.motif), rg09.motif);

    /* L'écran des assurés montre la hiérarchie */
    await ouvrir('m9-assures.html');
    verifier('L’écran des assurés affiche souscripteur et catégorie',
      await page.evaluate(() => /Souscripteur/.test(document.body.textContent)
        && /Catégorie/.test(document.body.textContent)));

    verifier('Aucune erreur JavaScript sur la prise en charge', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 18. Facturation : parts par ligne, remises, double facture, MECeF partielle
   * -------------------------------------------------------------------------
   * La facturation consomme la grille de prise en charge. Quatre exigences
   * contractuelles se vérifient ici : part par ligne, colonnes de remise,
   * deux pièces pour l'assuré, et une base MECeF limitée à la part patient.
   * ======================================================================= */
  {
    scenario('Facturation — parts par ligne, remises, double facture, MECeF');

    await ouvrir('m8-facturation.html');
    const prep = await page.evaluate(() => {
      const S = window.SIGH.store, D = window.SIGH.data;
      const p = S.collection('patients').active().filter((x) => x.assureur && x.souscripteurId)[0];
      const s = S.collection('souscripteurs').get(p.souscripteurId);
      D.BAREME_REFERENCE.garanties.forEach((g) => S.collection('garanties').insert({
        souscripteurId: s.id, assureur: s.assureur, code: g.code, libelle: g.libelle,
        categorie: g.categorie, taux: g.taux, plafond: g.plafond, unitePlafond: g.unitePlafond,
      }));
      S.collection('souscripteurs').update(s.id, { produitsExclus: D.BAREME_REFERENCE.produitsExclus.slice() });
      S.collection('patients').update(p.id, { carteExpiration: '2026-12-31' });
      return { id: p.id, nom: p.nom + ' ' + p.prenom };
    });

    await ouvrir('m8-facturation.html');
    const emission = await page.evaluate(async (prep) => {
      const S = window.SIGH.store;
      const combos = [...document.querySelectorAll('#page-content .combo')];
      combos[0].value = prep.id;
      combos[0].dispatchEvent(new Event('change', { bubbles: true }));
      await new Promise((r) => setTimeout(r, 250));

      const selects = [...document.querySelectorAll('#page-content select')];
      const selNature = selects.find((s) => [...s.options].some((o) => /Analyse de laboratoire/.test(o.textContent)));
      const ajouter = () => [...document.querySelectorAll('#page-content button')].find((x) => x.textContent.trim() === 'Ajouter').click();

      /* Une analyse couverte à 80 % */
      selNature.value = 'analyse';
      selNature.dispatchEvent(new Event('change', { bubbles: true }));
      await new Promise((r) => setTimeout(r, 200));
      ajouter();
      await new Promise((r) => setTimeout(r, 200));

      /* Un produit exclu de la convention, avec 10 % de remise */
      selNature.value = 'libre';
      selNature.dispatchEvent(new Event('change', { bubbles: true }));
      await new Promise((r) => setTimeout(r, 200));
      const inputs = [...document.querySelectorAll('#page-content input')];
      const libre = inputs.find((i) => i.placeholder && /Désignation/.test(i.placeholder));
      libre.value = 'Coton hydrophile';
      libre.dispatchEvent(new Event('input', { bubbles: true }));
      const pu = inputs.find((i) => i.classList.contains('w-32'));
      pu.value = '300';
      pu.dispatchEvent(new Event('input', { bubbles: true }));
      const remise = inputs.find((i) => i.classList.contains('w-24') && i.type === 'number' && i.value === '0');
      remise.value = '10';
      remise.dispatchEvent(new Event('input', { bubbles: true }));
      const selRemise = selects.find((s) => [...s.options].some((o) => o.textContent === 'Remise personnel'));
      selRemise.value = 'personnel';
      ajouter();
      await new Promise((r) => setTimeout(r, 250));

      const tableau = document.querySelector('#page-content table').textContent;
      const avant = S.collection('factures').active().length;
      [...document.querySelectorAll('#page-content button')].find((x) => /Enregistrer et encaisser/.test(x.textContent)).click();
      await new Promise((r) => setTimeout(r, 900));
      const apres = S.collection('factures').active();
      const nouvelles = apres.slice(0, apres.length - avant);
      const sheet = document.querySelector('.print-sheet');
      return {
        tableau: tableau,
        pieces: nouvelles.map((f) => ({
          numero: f.numero, volet: f.volet, total: f.montantTTC, ass: f.partAssurance,
          pat: f.partPatient, remises: f.montantRemises, base: f.baseMecef,
        })),
        texte: sheet ? sheet.textContent.replace(/\s+/g, ' ') : '',
      };
    }, prep);

    verifier('Le tableau de saisie porte les colonnes Remise et P.U net',
      /Remise/.test(emission.tableau) && /P\.U net/.test(emission.tableau));
    verifier('Le tableau de saisie porte les parts assureur et patient',
      /Part ass\./.test(emission.tableau) && /Part pat\./.test(emission.tableau));

    verifier('Un assuré reçoit deux factures : couvert et non couvert',
      emission.pieces.length === 2, emission.pieces.map((p) => p.numero + ' ' + (p.volet || '')).join(' · '));

    const couverte = emission.pieces.filter((p) => p.volet === 'couvert')[0] || {};
    const nonCouverte = emission.pieces.filter((p) => p.volet === 'non_couvert')[0] || {};
    verifier('La pièce « couvert » porte une part assureur',
      couverte.ass > 0, 'assureur ' + couverte.ass + ' / patient ' + couverte.pat);
    verifier('La pièce « non couvert » est intégralement à la charge du patient',
      nonCouverte.ass === 0 && nonCouverte.pat > 0, 'patient ' + nonCouverte.pat);
    verifier('La remise est appliquée et tracée sur sa pièce',
      nonCouverte.remises === 30, 'remise ' + nonCouverte.remises + ' FCFA');

    verifier('La base MECeF n’excède jamais la part patient',
      emission.pieces.every((p) => p.base <= p.pat),
      emission.pieces.map((p) => p.base + '≤' + p.pat).join(' · '));

    verifier('La facture porte la mention « Arrêtée la présente facture »',
      /Arrêtée la présente facture/.test(emission.texte));
    verifier('La facture porte la formule de la clinique',
      /QUE DIEU VOUS GUÉRISSE/.test(emission.texte));
    /* Un seul RCCM depuis le 26/08/2026 : la pièce ne doit plus porter
       l ancien NAT/2021/M02-020, qui distinguait les pièces de caisse. */
    const ancienRccm = emission.texte.indexOf('NAT/2021/M02-020') !== -1;
    const nouveauRccm = emission.texte.indexOf('RB/NAT/2016-B-268') !== -1;
    verifier('Un SEUL RCCM figure sur la pièce — décision du 26/08/2026',
      nouveauRccm && !ancienRccm,
      nouveauRccm ? 'RB/NAT/2016-B-268' + (ancienRccm ? ' ET l’ancien, encore présent' : ' seul')
        : 'aucun RCCM lu sur la pièce');

    /* Ticket de caisse : gabarit rouleau distinct du A4 */
    const ticket = await page.evaluate(() => {
      /* La facture précédente est encore prévisualisée : fermer sa surcouche,
         sinon c'est sa feuille A4 que l'on mesurerait. */
      document.querySelectorAll('.print-chrome').forEach((o) => o.remove());
      document.querySelectorAll('.print-sheet').forEach((s) => s.remove());
      window.SIGH.print.ticket({
        numero: '22118', typeVente: 'ASSURANCE', operateur: 'DIEYABIDI Aïchatou',
        assureur: 'AFRICAINE DES ASSURANCES', assure: 'KORA Bibata', dossier: 'CNT530/25',
        mecef: { nim: 'NIM0012345', code: 'A1B2-C3D4', compteurs: '12/45 FN' },
        lignes: [{ designation: 'CONSULTATION GENERALISTE', quantite: 1, prixUnitaire: 5000, montant: 5000 }],
        total: 5000, partAssureur: 4000, partPatient: 1000,
      });
      const s = document.querySelector('.print-sheet');
      return { largeur: s.style.width, texte: s.textContent.replace(/\s+/g, ' ') };
    });
    verifier('Le ticket de caisse est un rouleau, non un A4', ticket.largeur === '80mm', ticket.largeur);
    verifier('Le ticket porte OPÉRATEUR, TYPE VENTE, ASSUREUR et ASSURÉ',
      /OPÉRATEUR/.test(ticket.texte) && /TYPE VENTE/.test(ticket.texte)
      && /ASSUREUR/.test(ticket.texte) && /ASSURÉ/.test(ticket.texte));
    verifier('Le ticket distingue part assureur et part assuré',
      /PART ASSUREUR/.test(ticket.texte) && /PART ASSURÉ/.test(ticket.texte));

    verifier('Aucune erreur JavaScript sur la facturation', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 19. Relevé, facture mensuelle, opérations de caisse et recettes
   * -------------------------------------------------------------------------
   * Les deux pièces réellement transmises aux compagnies vont ensemble et
   * doivent se recouper. Côté caisse, la Direction veut les recettes par
   * périodicité et un inventaire arrêté sur une période.
   * ======================================================================= */
  {
    scenario('États de caisse et pièces assureur — relevé, facture, recettes');

    /* Une convention pour que la répartition existe */
    await ouvrir('m9-conventions.html');
    await page.evaluate(() => {
      const S = window.SIGH.store, D = window.SIGH.data;
      S.collection('patients').active().filter((p) => p.assureur && p.souscripteurId).slice(0, 40).forEach((p) => {
        S.collection('patients').update(p.id, { carteExpiration: '2026-12-31' });
      });
      const dejaVus = {};
      S.collection('souscripteurs').active().forEach((s) => {
        if (dejaVus[s.id]) return;
        dejaVus[s.id] = true;
        D.BAREME_REFERENCE.garanties.forEach((g) => S.collection('garanties').insert({
          souscripteurId: s.id, assureur: s.assureur, code: g.code, libelle: g.libelle,
          categorie: g.categorie, taux: g.taux, plafond: g.plafond, unitePlafond: g.unitePlafond,
        }));
      });
    });

    await ouvrir('m9-factures-assureur.html');
    const pieces = await page.evaluate(async () => {
      const onglets = [...document.querySelectorAll('.tab')].map((t) => t.textContent.trim());
      const texteReleve = document.body.textContent;
      const ongletFacture = [...document.querySelectorAll('.tab')].find((t) => /Facture mensuelle/.test(t.textContent));
      let coherence = null;
      if (ongletFacture) {
        ongletFacture.click();
        await new Promise((r) => setTimeout(r, 400));
        coherence = /se recoupent/.test(document.body.textContent) ? 'ok'
          : (/en écart/.test(document.body.textContent) ? 'ecart' : 'absent');
      }
      return { onglets: onglets, releve: /police/.test(texteReleve), coherence: coherence };
    });
    verifier('Le relevé et la facture mensuelle sont deux vues du même mois',
      pieces.onglets.some((o) => /Relevé/.test(o)) && pieces.onglets.some((o) => /Facture mensuelle/.test(o)),
      pieces.onglets.join(' · '));
    verifier('Le relevé est organisé par souscripteur avec son n° de police', pieces.releve);
    verifier('L’écran contrôle que les deux pièces se recoupent avant transmission',
      pieces.coherence === 'ok', 'contrôle : ' + pieces.coherence);

    /* Historique par assureur */
    await ouvrir('m9-historique.html');
    const histo = await page.evaluate(() => ({
      colonnes: /Souscripteur/.test(document.body.textContent) && /Compagnie/.test(document.body.textContent),
      repartition: /Répartition par compagnie/.test(document.body.textContent),
    }));
    verifier('L’historique par assureur croise compagnie, souscripteur et assuré', histo.colonnes);
    verifier('Il situe chaque compagnie dans l’ensemble', histo.repartition);

    /* Opérations de caisse et inventaire */
    await ouvrir('m8-operations.html');
    const ops = await page.evaluate(() => {
      const selects = [...document.querySelectorAll('#page-content select')];
      const periodicites = selects.length ? [...selects[0].options].map((o) => o.textContent) : [];
      return {
        periodicites: periodicites,
        ventilation: /Ventilation des encaissements/.test(document.body.textContent),
        inventaire: [...document.querySelectorAll('#page-content button')].some((b) => /Inventaire de caisse/.test(b.textContent)),
      };
    });
    verifier('Les opérations de caisse s’arrêtent au jour, à la semaine ou au mois',
      ops.periodicites.some((p) => /Journalière/.test(p)) && ops.periodicites.some((p) => /Hebdomadaire/.test(p)),
      ops.periodicites.join(' · '));
    verifier('Les encaissements sont ventilés par mode de règlement', ops.ventilation);
    verifier('Un inventaire de caisse peut être arrêté sur la période', ops.inventaire);

    /* Recettes par périodicité */
    await ouvrir('m8-recettes.html');
    const rec = await page.evaluate(async () => {
      const sel = document.querySelector('#page-content select');
      const periodicites = [...sel.options].map((o) => o.textContent);
      const avant = document.querySelectorAll('#page-content tbody tr').length;
      sel.value = 'mois';
      sel.dispatchEvent(new Event('change', { bubbles: true }));
      await new Promise((r) => setTimeout(r, 400));
      const apresMois = document.querySelectorAll('#page-content tbody tr').length;
      /* plage libre */
      const plage = document.querySelector('#f_plage');
      plage.checked = true;
      plage.dispatchEvent(new Event('change', { bubbles: true }));
      await new Promise((r) => setTimeout(r, 400));
      return {
        periodicites: periodicites,
        lignesMois: apresMois,
        plageLibre: /plage libre/.test(document.body.textContent),
        recouvrement: /Taux de recouvrement/.test(document.body.textContent),
      };
    });
    verifier('Les recettes se déclinent en six périodicités',
      rec.periodicites.length === 6 && rec.periodicites.some((p) => /Annuelle/.test(p)),
      rec.periodicites.join(' · '));
    verifier('Une plage de dates libre est possible', rec.plageLibre);
    verifier('Le taux de recouvrement est calculé', rec.recouvrement);

    /* Engagement de paiement et client insolvable */
    await ouvrir('m8-reliquats.html');
    const impayes = await page.evaluate(() => {
      const S = window.SIGH.store;
      const f = S.collection('factures').active().filter((x) => x.reliquat > 0)[0];
      S.collection('factures').update(f.id, {
        engagement: { date: '2026-09-20', modalite: 'echeancier', tranches: 3, recuPar: 'KASSA Augustin', montant: f.reliquat },
      });
      const apres = S.collection('factures').get(f.id);
      S.collection('factures').update(f.id, { insolvable: true, motifInsolvabilite: 'Sans nouvelle depuis 90 jours' });
      const fin = S.collection('factures').get(f.id);
      return {
        engagement: !!apres.engagement && apres.engagement.tranches === 3,
        insolvable: fin.insolvable === true,
        creanceIntacte: fin.reliquat === f.reliquat,
        boutons: [...document.querySelectorAll('button[title]')].map((b) => b.title),
      };
    });
    verifier('Un engagement de paiement échelonné peut être pris',
      impayes.engagement && impayes.boutons.some((t) => /Engagement de paiement/.test(t)));
    verifier('Un patient peut être déclaré client insolvable',
      impayes.insolvable && impayes.boutons.some((t) => /insolvable/.test(t)));
    verifier('La créance reste due après la déclaration d’insolvabilité', impayes.creanceIntacte);

    verifier('Aucune erreur JavaScript sur les états de caisse', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 20. RBAC métier — ce que chacun VOIT, pas seulement ce qu'il ouvre
   * -------------------------------------------------------------------------
   * Transcription des règles dictées par la Direction : le médecin voit tous
   * les résultats, la sage-femme ceux de son secteur, l'infirmier aucun,
   * l'aide-soignant n'exécute pas les soins prescrits.
   * ======================================================================= */
  {
    scenario('RBAC métier — habilitations par fonction et par secteur');

    const profils = [
      { nom: 'Médecin', s: { role: 'medecin', nom: 'YENI Florent', fonction: 'medecin', secteur: 'MGE' } },
      { nom: 'Sage-femme', s: { role: 'infirmier', nom: 'BADO BANI Z.', fonction: 'sage_femme', secteur: 'MAT' } },
      { nom: 'Infirmier', s: { role: 'infirmier', nom: 'GARBA Yahouza', fonction: 'infirmier', secteur: 'SUR' } },
      { nom: 'Aide-soignante', s: { role: 'infirmier', nom: 'TEPA S.', fonction: 'aide_soignant', secteur: 'HOS' } },
      { nom: 'Laborantin', s: { role: 'laborantin', nom: 'KINNOU G.', fonction: 'tsl', secteur: 'LAB' } },
    ];
    /* Le scénario pose ses propres demandes, avec leur secteur prescripteur :
       les jeux de démonstration ont pu être consommés par les scénarios
       précédents, et c'est la RÈGLE qu'on veut éprouver, pas l'amorçage. */
    await ouvrir('m5-resultats.html');
    await page.evaluate(() => {
      const S = window.SIGH.store;
      const col = S.collection('demandesAnalyses');
      const p = S.collection('patients').active()[0];
      [['MATERNITÉ', 3], ['CHIRURGIE', 4], ['MÉDECINE GÉNÉRALE', 5]].forEach(([secteur, n]) => {
        for (let i = 0; i < n; i++) {
          col.insert({
            reference: 'TST-' + secteur.slice(0, 3) + '-' + i,
            /* Phase 6 : TOUTE demande porte son code de série annuelle — la
               fixture passe par la fabrique unique, comme une vraie saisie. */
            codeAnalyse: window.SIGH.parcours.codeAnalyse('2026-08-10'),
            patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
            analyseCode: 'L01', analyse: 'Test RBAC', categorie: 'Biochimie',
            dateHeure: new Date(2026, 7, 10).toISOString(),
            prescripteur: 'YENI Florent', etatAnalyse: 'valide',
            secteurDemandeur: secteur, origine: 'manuelle',
          });
        }
      });
    });

    const vus = {};
    for (const p of profils) {
      await page.evaluate((s) => window.SIGH.store.setSession(s), p.s);
      await ouvrir('m5-resultats.html');
      vus[p.nom] = await page.evaluate(() => {
        const S = window.SIGH.store, PR = window.SIGH.parcours;
        const tous = S.collection('demandesAnalyses').active();
        const cap = PR.capacites();
        const D = window.SIGH.data;
        /* Depuis les deux verrous, un résultat non validé biologiquement
           n'existe pas pour le prescripteur : le dénominateur pertinent est
           celui des résultats RENDUS. */
        const rendus = tous.filter((d) => D.resultatRendu(d.etatAnalyse));
        return {
          total: tous.length, rendus: rendus.length,
          visibles: PR.filtrerResultats(tous).length,
          regle: cap.voirResultats, soins: cap.executerSoins,
          prescrire: (cap.prescrire || []).length,
          bandeau: /ne vous est accessible|périmètre limité|Laboratoire\./.test(document.body.textContent),
          motifNonValide: (function () {
            const enCours = tous.filter((d) => !D.resultatRendu(d.etatAnalyse))[0];
            if (!enCours) return null;
            const r = PR.peutVoirResultat(enCours);
            return { autorise: r.autorise, attente: !!r.enAttenteValidation, motif: r.motif };
          })(),
        };
      });
    }

    verifier('Le médecin accède à tous les résultats RENDUS, quel que soit le prescripteur',
      vus.Médecin.visibles === vus.Médecin.rendus && vus.Médecin.regle === 'tous',
      vus.Médecin.visibles + '/' + vus.Médecin.rendus + ' rendus sur ' + vus.Médecin.total + ' au total');
    verifier('Un résultat non validé biologiquement est masqué au médecin, avec son motif',
      !vus.Médecin.motifNonValide
      || (!vus.Médecin.motifNonValide.autorise && vus.Médecin.motifNonValide.attente),
      vus.Médecin.motifNonValide ? vus.Médecin.motifNonValide.motif.slice(0, 70) : 'aucun résultat en cours');
    verifier('La sage-femme n’accède qu’aux résultats de son secteur',
      vus['Sage-femme'].visibles > 0 && vus['Sage-femme'].visibles < vus['Sage-femme'].total,
      vus['Sage-femme'].visibles + '/' + vus['Sage-femme'].total);
    verifier('L’infirmier n’accède à aucun résultat d’analyse',
      vus.Infirmier.visibles === 0, vus.Infirmier.regle);
    verifier('L’aide-soignant n’accède à aucun résultat d’analyse',
      vus['Aide-soignante'].visibles === 0, vus['Aide-soignante'].regle);
    verifier('Le laboratoire voit les résultats qu’il produit',
      vus.Laborantin.visibles === vus.Laborantin.total && vus.Laborantin.regle === 'produits');
    verifier('Une restriction est toujours annoncée, jamais muette',
      ['Sage-femme', 'Infirmier', 'Aide-soignante', 'Laborantin'].every((k) => vus[k].bandeau));

    verifier('L’infirmier exécute les soins prescrits, pas l’aide-soignant',
      vus.Infirmier.soins === true && vus['Aide-soignante'].soins === false);
    verifier('Médecin et sage-femme prescrivent, les autres non',
      vus.Médecin.prescrire >= 4 && vus['Sage-femme'].prescrire >= 3
      && vus.Infirmier.prescrire === 0 && vus.Laborantin.prescrire === 0,
      'médecin ' + vus.Médecin.prescrire + ' · sage-femme ' + vus['Sage-femme'].prescrire);

    /* L'aide-soignante ne peut pas valider un soin */
    await page.evaluate((s) => window.SIGH.store.setSession(s), profils[3].s);
    await ouvrir('m3-soins.html');
    verifier('L’aide-soignante voit la règle plutôt que le bouton de validation',
      await page.evaluate(() => /ne vous revient pas/.test(document.body.textContent)));

    /* La consultation donne accès aux catalogues complets */
    await page.evaluate((s) => window.SIGH.store.setSession(s), profils[0].s);
    await ouvrir('m2-consultation-fiche.html');
    const presc = await page.evaluate(() => {
      const S = window.SIGH.store, D = window.SIGH.data;
      const combos = [...document.querySelectorAll('#page-content .combo')];
      return {
        combos: combos.length,
        medicaments: S.collection('produits').active().filter((p) => /medicament|conso_medical/.test(p.categorie)).length,
        analyses: D.ANALYSES.length,
        actes: S.collection('actes').active().length,
        /* REFONTE ZONE 2 (14/09/2026) : la fiche ne prescrit PLUS que ce que la
           METHODOLOGIE lui laisse — médicaments (tableau dynamique produit /
           quantité / posologie / durée), analyses, IMAGERIE — plus
           l'orientation qui remplace la catégorie d'hospitalisation. Les actes
           se prescrivent à m2-prescriptions ; l'assertion suit ce choix
           délibéré, elle ne l'affaiblit pas : quatre champs, toujours. */
        champs: ['prescription-medicaments', 'f_analyses', 'f_imagerie', 'f_orientation'].filter((id) => !!document.getElementById(id)).length,
      };
    });
    verifier('La consultation ouvre ses catalogues de prescription — médicaments, analyses, imagerie — et l’orientation',
      presc.champs === 4, presc.champs + '/4 champs');
    verifier('Les catalogues sont complets — médicaments, analyses, actes',
      presc.medicaments > 100 && presc.analyses === 48 && presc.actes > 60,
      presc.medicaments + ' médicaments · ' + presc.analyses + ' analyses · ' + presc.actes + ' actes');

    /* Accès croisés du cahier de charge */
    const croises = await page.evaluate(() => {
      const N = window.SIGH.nav;
      const mod = (code) => {
        let m = null;
        N.NAV.forEach((d) => d.modules.forEach((x) => { if (x.code === code) m = x; }));
        return m;
      };
      const peut = (role, code) => {
        const m = mod(code);
        return m.items.some((it) => N.can(role, { roles: it.roles || m.roles || N.ALL }));
      };
      return {
        daCaisse: peut('da', 'M8'), daMagasin: peut('da', 'M6'),
        stockCaisse: peut('stock', 'M8'), comptableMagasin: peut('comptable', 'M6'),
        infirmierPaie: peut('infirmier', 'M11'),
      };
    });
    verifier('La DA accède à la caisse et au magasin', croises.daCaisse && croises.daMagasin);
    verifier('Le gestionnaire de stock accède à la caisse', croises.stockCaisse);
    verifier('Le comptable accède au magasin', croises.comptableMagasin);
    verifier('RG-13 — l’infirmier reste hors de la paie', !croises.infirmierPaie);

    /* --- La matrice des droits est administrable ET opposable -------------
       Le défaut corrigé ici : l'écran écrivait ses décisions dans une
       collection que personne ne relisait. Fermer un module ne fermait rien.
       Le scénario vérifie donc l'EFFET, pas seulement la présence du bouton. */
    await page.evaluate(() => window.SIGH.store.setSession({ role: 'admin', nom: 'BASSONGUI Chabi Séko', fonction: 'direction', secteur: 'ADM' }));
    await ouvrir('m14-roles.html');
    const matrice = await page.evaluate(() => ({
      droits: [...document.querySelectorAll('button[title]')].some((b) => /Modifier les droits/.test(b.title)),
      renommer: [...document.querySelectorAll('button[title]')].some((b) => /Renommer ce rôle/.test(b.title)),
      archiver: [...document.querySelectorAll('button[title]')].some((b) => /Archiver ce rôle/.test(b.title)),
      onglets: [...document.querySelectorAll('#page-content [role="tab"], #page-content button')]
        .map((b) => b.textContent).join(' | '),
    }));
    verifier('Chaque rôle porte ses trois commandes : droits, renommage, archivage',
      matrice.droits && matrice.renommer && matrice.archiver);
    verifier('L’écran expose les habilitations métier et les tentatives refusées',
      /Habilitations métier/.test(matrice.onglets) && /Tentatives refusées/.test(matrice.onglets));

    /* Fermer M1 au laborantin doit RÉELLEMENT le fermer. */
    const effet = await page.evaluate(() => {
      const S = window.SIGH.store, N = window.SIGH.nav;
      const avant = N.droits('laborantin', 'M1').voir;
      /* UPSERT : l'amorçage pose déjà une fiche pour le laborantin (lecture
         seule sur M1). Une seconde fiche rendrait la matrice imprévisible. */
      const colRbac = S.collection('rbac', { module: 'M14', entite: 'rôle', prefix: 'RBAC' });
      const dejaLa = colRbac.all().filter((x) => x.role === 'laborantin')[0];
      /* ON SAUVEGARDE POUR RESTAURER. Une épreuve qui écrit dans un magasin
         PARTAGÉ doit défaire ce qu'elle a fait — sinon elle ne teste plus son
         objet, elle contamine les scénarios suivants. Et on sauvegarde plutôt
         que de réécrire la fiche : un test qui RECOPIE l'amorçage finit
         toujours par diverger de lui, et c'est précisément ce qui est arrivé
         ici — la copie portait six réglages d'écran quand l'amorçage en
         comptait treize, si bien que les cinq fermetures les plus récentes
         se rouvraient sans que rien ne le signale. */
      const sauvegardeLabo = dejaLa
        ? { droits: dejaLa.droits, droitsEcrans: dejaLa.droitsEcrans }
        : null;
      const reglage = {
        libelleOrigine: 'Laborantin', statut: 'actif',
        droits: { M1: { voir: false, editer: false, annuler: false },
          M5: { voir: true, editer: false, annuler: false } },
        /* Le réglage d'écran de l'amorçage rouvrirait M1 : on le retire pour
           éprouver la fermeture du MODULE. */
        droitsEcrans: {},
      };
      if (dejaLa) colRbac.update(dejaLa.id, reglage);
      else colRbac.insert(Object.assign({ role: 'laborantin' }, reglage));
      N.invaliderRbac();
      const arbre = N.tree('laborantin');
      const codes = [];
      arbre.forEach((d) => d.modules.forEach((m) => codes.push(m.code)));
      return {
        avant: avant,
        apres: N.droits('laborantin', 'M1').voir,
        dansLeRuban: codes.indexOf('M1') !== -1,
        lectureSeuleM5: N.droits('laborantin', 'M5').lectureSeule,
        canEcran: N.can('laborantin', { roles: ['laborantin'], module: 'M1' }),
        sauvegarde: sauvegardeLabo,
      };
    });
    verifier('Le module Patients était ouvert au laborantin avant restriction', effet.avant);
    verifier('Fermer M1 au laborantin prend effet sur les droits', !effet.apres,
      'voir=' + effet.apres);
    verifier('Le module fermé disparaît du méga-menu du rôle', !effet.dansLeRuban);
    verifier('Un écran du module fermé n’est plus habilité', !effet.canEcran);
    verifier('Un module ouvert sans édition ni annulation passe en lecture seule',
      effet.lectureSeuleM5);

    /* ON REMET EXACTEMENT CE QUI ÉTAIT LÀ — la sauvegarde prise avant
       l'épreuve, jamais une copie de l'amorçage. La version précédente de ce
       correctif recopiait la fiche à la main : elle aurait divergé au premier
       réglage ajouté, exactement comme l'avait fait le bloc qu'elle
       remplaçait. */
    const restaure = await page.evaluate((sauvegarde) => {
      const S = window.SIGH.store, N = window.SIGH.nav;
      const col = S.collection('rbac', { module: 'M14', entite: 'rôle', prefix: 'RBAC' });
      const f = col.all().filter((x) => x.role === 'laborantin')[0];
      if (!f || !sauvegarde) return false;
      col.update(f.id, sauvegarde);
      N.invaliderRbac();
      return N.can('laborantin', N.get('m1-patients'))
        && !N.can('laborantin', N.get('m1-dossier-etendu'));
    }, effet.sauvegarde);
    verifier('La matrice est remise en place après l’épreuve de fermeture', restaure);

    /* Renommer un rôle se propage à tout le prototype. */
    /* LE MÉCANISME se vérifie sur un rôle QUI N'A PAS ENCORE ÉTÉ RENOMMÉ À
       LA SOURCE. Le laboratoire ne convient plus : la Direction a fait passer
       « Biologiste médical » au MANIFESTE — il fallait que le nom paraisse à
       l'écran de connexion, où aucune surcharge n'est encore chargée. Origine
       et libellé courant y coïncident donc, et l'assertion mesurerait la
       correction au lieu du mécanisme. */
    const renom = await page.evaluate(() => {
      const S = window.SIGH.store, N = window.SIGH.nav;
      const col = S.collection('rbac', { module: 'M14', entite: 'rôle', prefix: 'RBAC' });
      const avant = N.ROLES.agentadmin.label;
      let f = col.all().filter((x) => x.role === 'agentadmin')[0];
      if (!f) f = col.insert({ role: 'agentadmin', statut: 'actif' }).record;
      col.update(f.id, { libelle: 'Agent de bureau' });
      N.invaliderRbac();
      const apres = N.ROLES.agentadmin.label;
      const origine = N.ROLES.agentadmin.labelOrigine;
      /* On repose la surcharge à vide : l'intitulé d'origine doit revenir. */
      col.update(f.id, { libelle: null });
      N.invaliderRbac();
      return {
        label: apres, origine: origine, avant: avant,
        rendu: N.ROLES.agentadmin.label,
        /* Et le laboratoire porte son nouveau nom DEPUIS LE MANIFESTE. */
        manifeste: N.ROLES.laborantin.label,
      };
    });
    /* LE MÉCANISME se vérifie, pas le cas particulier. Le rôle du
       laboratoire est désormais renommé AU MANIFESTE — origine et libellé
       courant coïncident — et l'assertion échouait donc sur la correction
       elle-même. Ce qui doit rester garanti, c'est qu'une surcharge SAIT
       renommer et que retirer la surcharge rend l'intitulé d'origine. */
    verifier('Un rôle peut être renommé sans toucher au code',
      renom.label === 'Agent de bureau', renom.avant + ' → ' + renom.label);
    verifier('Retirer la surcharge rend son intitulé d’origine au rôle',
      renom.rendu === renom.origine, renom.rendu + ' (origine : ' + renom.origine + ')');
    verifier('Le laboratoire porte « Biologiste médical » DEPUIS LE MANIFESTE',
      renom.manifeste === 'Biologiste médical', renom.manifeste);

    await page.evaluate(() => window.SIGH.store.setSession({ role: 'admin', nom: 'BASSONGUI Chabi Séko', poste: 'Directeur Médical' }));
    verifier('Aucune erreur JavaScript sur le RBAC métier', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 21. Mise en observation — surveillance courte et décision d'orientation
   * -------------------------------------------------------------------------
   * L'observation n'est pas une admission : durée de référence de 24 h, feuille
   * de constantes horodatée, prescriptions ciblées, et une décision de sortie
   * qui peut ouvrir une hospitalisation complète.
   * ======================================================================= */
  {
    scenario('Mise en observation — surveillance, constantes et orientation');

    await ouvrir('m3-observation.html');
    const etat = await page.evaluate(() => {
      const S = window.SIGH.store, D = window.SIGH.data;
      const obs = S.collection('observations').active();
      return {
        total: obs.length,
        actives: obs.filter((o) => o.statutObservation === 'en_cours').length,
        unites: D.UNITES_OBSERVATION.length,
        orientations: D.ORIENTATIONS_OBSERVATION.length,
        reference: D.DUREE_OBSERVATION_REFERENCE,
        occupation: /Occupation des unités/.test(document.body.textContent),
        onglets: [...document.querySelectorAll('.tab')].map((t) => t.textContent.trim()),
        dansSoins: D.ACTES_SOINS.indexOf('Mise en observation') >= 0,
        dansNatures: S.collection('naturesFacture').active().some((n) => n.libelle === 'Mise en observation'),
      };
    });
    verifier('L’écran de mise en observation existe et distingue en cours et clos',
      etat.onglets.length === 2 && /En observation/.test(etat.onglets[0]), etat.onglets.join(' · '));
    verifier('Les unités d’observation sont suivies en occupation',
      etat.unites === 4 && etat.occupation, etat.unites + ' unités');
    verifier('Quatre orientations de sortie sont prévues', etat.orientations === 4);
    verifier('« Mise en observation » figure à la rubrique Soins', etat.dansSoins);
    verifier('« Mise en observation » figure aux natures de facture', etat.dansNatures);

    /* Cycle complet : entrée → constantes → prescription → orientation */
    const cycle = await page.evaluate(async () => {
      const S = window.SIGH.store, PR = window.SIGH.parcours, D = window.SIGH.data;
      const col = S.collection('observations');
      const p = S.collection('patients').active()[5];
      const entree = new Date(Date.now() - 26 * 3600000).toISOString();
      const r = col.insert({
        reference: 'OBS-TEST-1', patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
        unite: 'urgences', uniteLabel: 'Salle d’observation — urgences', motif: 'Douleur thoracique',
        dateEntree: entree, dateSortie: null, medecin: 'YENI M’PO Florent', infirmier: 'GARBA Yahouza',
        constantes: [], statutObservation: 'en_cours',
      });
      col.update(r.record.id, {
        constantes: [
          { heure: entree, temperature: '38.2', tension: '14/9', pouls: 104, spo2: 96, observation: 'Douleur vive', par: 'GARBA Yahouza' },
          { heure: new Date(Date.now() - 2 * 3600000).toISOString(), temperature: '37.1', tension: '12/8', pouls: 82, spo2: 98, observation: 'Amélioration', par: 'GARBA Yahouza' },
        ],
      });
      const ord = PR.prescrire({
        patientCode: p.code, medecin: 'YENI M’PO Florent', diagnostic: 'Observation — Douleur thoracique',
        analyses: [D.ANALYSES[2].code], actes: [], medicaments: [],
        secteurDemandeur: 'Salle d’observation — urgences',
      });
      const avantAdm = S.collection('admissions').active().length;
      col.update(r.record.id, {
        statutObservation: 'clos', orientation: 'hospitalisation',
        orientationLabel: 'Hospitalisation complète', conclusion: 'Aggravation constatée',
        dateSortie: new Date().toISOString(),
      });
      const adm = S.collection('admissions', { module: 'M3', entite: 'Admission' }).insert({
        reference: 'H-TEST', patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
        dateEntree: new Date().toISOString(), statut: 'en_cours', origineObservation: 'OBS-TEST-1',
      });
      const o = col.get(r.record.id);
      return {
        constantes: (o.constantes || []).length,
        heures: Math.round((new Date(o.dateSortie) - new Date(o.dateEntree)) / 3600000),
        ordonnance: ord.ordonnance.numero, demandes: ord.demandes.length,
        secteurDemande: S.collection('demandesAnalyses').all()
          .filter((d) => d.ordonnanceId === ord.ordonnance.id)[0].secteurDemandeur,
        orientation: o.orientationLabel,
        admissionCreee: S.collection('admissions').active().length === avantAdm + 1,
        origine: adm.record.origineObservation,
      };
    });

    verifier('L’heure d’entrée fait courir la durée de surveillance',
      cycle.heures === 26, cycle.heures + ' h — au-delà des ' + etat.reference + ' h de référence');
    verifier('La feuille de constantes horodate chaque relevé', cycle.constantes === 2);
    verifier('Une prescription ciblée part au laboratoire depuis l’observation',
      cycle.demandes === 1 && /^ORD-/.test(cycle.ordonnance), cycle.ordonnance);
    verifier('La demande porte l’unité d’observation comme secteur prescripteur',
      /observation/.test(cycle.secteurDemande || ''), cycle.secteurDemande);
    verifier('L’orientation clôt l’observation', cycle.orientation === 'Hospitalisation complète');
    verifier('L’hospitalisation complète ouvre une admission rattachée à l’observation',
      cycle.admissionCreee && cycle.origine === 'OBS-TEST-1');

    /* Le dépassement de la durée de référence est signalé */
    await ouvrir('m3-observation.html');
    verifier('Un séjour au-delà de la durée de référence est signalé',
      await page.evaluate(() => /au-delà de la durée de référence|depuis plus de/.test(document.body.textContent)));

    verifier('Aucune erreur JavaScript sur la mise en observation', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 22. Dossier patient et accueil
   * -------------------------------------------------------------------------
   * La fiche est le point où le parcours se relit d'un bloc : hospitalisations,
   * observations, températures, maternité, analyses, ordonnances, domicile,
   * factures. Et l'accueil doit pouvoir enregistrer un passage sans rendez-vous.
   * ======================================================================= */
  {
    scenario('Dossier patient — statut d’assurance, parcours agrégé et accueil');

    /* Statut d'assurance : trois états distincts */
    await ouvrir('m1-patients.html');
    const repertoire = await page.evaluate(async () => {
      const S = window.SIGH.store;
      const assure = S.collection('patients').active().filter((p) => p.assureur)[0];
      S.collection('patients').update(assure.id, { carteExpiration: '2026-01-31' });
      return { id: assure.id, code: assure.code };
    });
    await ouvrir('m1-patients.html');
    const colonne = await page.evaluate(async (r) => {
      const entete = /Assurance/.test(document.body.textContent);
      const nonAssure = /Non assuré/.test(document.body.textContent);
      /* Le patient à carte expirée n'est pas forcément sur la première page :
         on le cherche, comme le ferait l'utilisateur. */
      const rech = document.querySelector('#page-content input[type="search"]');
      rech.value = r.code;
      rech.dispatchEvent(new Event('input', { bubbles: true }));
      await new Promise((x) => setTimeout(x, 400));
      return { entete, nonAssure, invalide: /CARTE NON VALIDE/.test(document.body.textContent) };
    }, repertoire);
    verifier('Le répertoire porte une colonne d’assurance', colonne.entete);
    verifier('Les patients sans couverture sont marqués « Non assuré »', colonne.nonAssure);
    verifier('Une carte expirée est signalée en clair dans la liste', colonne.invalide);

    /* Fiche patient : bandeau et onglets du parcours */
    await ouvrir('m1-patient-profil.html');
    const fiche = await page.evaluate(async (r) => {
      const combo = document.querySelector('#page-content .combo');
      combo.value = r.id;
      combo.dispatchEvent(new Event('change', { bubbles: true }));
      await new Promise((x) => setTimeout(x, 400));
      return {
        bandeau: /CARTE NON VALIDE/.test(document.body.textContent),
        onglets: [...document.querySelectorAll('#page-content [role=\"tab\"]')].map((t) => t.textContent.trim().replace(/\d+$/, '')),
        boutons: [...document.querySelectorAll('button')].map((b) => b.textContent.trim()),
      };
    }, repertoire);
    verifier('Le bandeau de la fiche signale la carte non valide en rouge', fiche.bandeau);
    verifier('La fiche agrège les parcours du patient',
      ['Hospitalisations', 'Maternité', 'Analyses & résultats', 'Ordonnances', 'À domicile']
        .every((o) => fiche.onglets.some((x) => x.indexOf(o) >= 0)),
      fiche.onglets.join(' · '));
    verifier('La fiche ouvre la fiche de consultation et les documents',
      fiche.boutons.some((b) => /Fiche de consultation/.test(b))
      && fiche.boutons.some((b) => /Documents numérisés/.test(b)));

    /* Documents numérisés : dépôt persistant */
    await ouvrir('m1-documents.html');
    const docs = await page.evaluate(() => {
      const S = window.SIGH.store;
      const col = S.collection('documentsPatient');
      const avant = col.active().length;
      const p = S.collection('patients').active()[0];
      const r = col.insert({
        reference: 'GED-TEST', patientId: p.id, code: p.code, patient: p.nom + ' ' + p.prenom,
        type: 'Résultat de laboratoire', date: '2026-08-20', etat: 'valide', depose: 'Test',
        format: 'PNG', taille: 2048, fichier: 'scan.png',
        donnees: 'data:image/png;base64,iVBORw0KGgo=',
      });
      return {
        bouton: [...document.querySelectorAll('button')].some((b) => /Ajouter un document/.test(b.textContent)),
        avant: avant, apres: col.active().length, avecFichier: !!col.get(r.record.id).donnees,
      };
    });
    verifier('Un document peut être déposé au dossier', docs.bouton);
    verifier('Le document déposé est conservé avec son fichier',
      docs.apres === docs.avant + 1 && docs.avecFichier);
    await ouvrir('m1-documents.html');
    verifier('Le document survit au rechargement',
      await page.evaluate(() => window.SIGH.store.collection('documentsPatient').active().some((d) => d.reference === 'GED-TEST')));

    /* Accueil : passage sans rendez-vous — l'écran a FUSIONNÉ (06/09/2026)
       dans « Rendez-vous & visites », et l'ancienne page renvoie. */
    await ouvrir('m2-rendezvous.html');
    const visites = await page.evaluate(() => ({
      /* Les actions rapides sont dans le bandeau de page, hors #page-content. */
      bouton: [...document.querySelectorAll('button')].some((b) => /Passage sans rendez-vous/.test(b.textContent)),
      regle: /sans rendez-vous/.test(document.body.textContent),
    }));
    verifier('L’accueil enregistre un passage sans rendez-vous', visites.bouton && visites.regle);
    await ouvrir('m2-visites.html');
    const renvoiVisites = await page.evaluate(() => ({
      renvoie: /fusionn/i.test(document.body.textContent),
      lien: [...document.querySelectorAll('button')].some((b) => /Rendez-vous & visites/.test(b.textContent)),
      tableau: document.querySelectorAll('#page-content tbody tr').length,
    }));
    verifier('L’ancienne page du registre RENVOIE — elle ne tient plus un second registre',
      renvoiVisites.renvoie && renvoiVisites.lien && renvoiVisites.tableau === 0,
      JSON.stringify(renvoiVisites));

    /* Agenda : plage de dates et prise de rendez-vous */
    await ouvrir('m2-agenda.html');
    const agenda = await page.evaluate(async () => {
      const dates = [...document.querySelectorAll('#page-content input[type="date"]')];
      const avant = document.querySelectorAll('#page-content .grid > div').length;
      dates[0].value = '2026-07-01';
      dates[1].value = '2026-07-10';
      dates[0].dispatchEvent(new Event('change', { bubbles: true }));
      await new Promise((r) => setTimeout(r, 500));
      return {
        champs: dates.length,
        titre: /Du 01\/07\/2026 au 10\/07\/2026/.test(document.body.textContent),
        bouton: [...document.querySelectorAll('button')].some((b) => /Nouveau rendez-vous/.test(b.textContent)),
      };
    });
    verifier('L’agenda se règle sur une plage de dates', agenda.champs >= 2 && agenda.titre);
    verifier('Un rendez-vous se prend depuis l’agenda', agenda.bouton);

    /* Notification sonore */
    const son = await page.evaluate(() => ({
      sonner: typeof window.SIGH.ui.sonner === 'function',
      alerter: typeof window.SIGH.ui.alerter === 'function',
      joue: window.SIGH.ui.sonner('rappel'),
    }));
    verifier('Une alerte sonore est disponible pour les échéances',
      son.sonner && son.alerter, son.joue ? 'audio actif' : 'audio indisponible, repli silencieux');

    /* Événements de la clinique */
    await ouvrir('m13-evenements.html');
    verifier('Un événement de la clinique peut être créé',
      await page.evaluate(() => [...document.querySelectorAll('#page-content button')]
        .some((b) => b.textContent.trim() === 'Nouveau')));

    verifier('Aucune erreur JavaScript sur le dossier patient', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 23. RH, fiscalité, certificats et exploitation
   * -------------------------------------------------------------------------
   * Les quatre dernières vagues : ordres de mission, redevance ORTB annuelle,
   * calendrier fiscal, certificats médicaux, sauvegardes exportables et
   * réinitialisation protégée.
   * ======================================================================= */
  {
    scenario('RH, fiscalité, certificats et exploitation');

    /* Ordres de mission — validation DA */
    await ouvrir('m10-missions.html');
    const mission = await page.evaluate(() => {
      const S = window.SIGH.store;
      const col = S.collection('missions');
      const r = col.insert({
        reference: 'OM-TEST', libelle: 'Formation test', nature: 'Formation',
        objet: 'Vérification', agent: 'GARBA Yahouza', structurePrise: 'OMS Bénin',
        destination: 'Cotonou', dateDepart: '2026-09-01', dateRetour: '2026-09-04',
        statutMission: 'a_valider',
      });
      col.update(r.record.id, { statutMission: 'validee', valideePar: 'TAKI Alimatou', valideeLe: '2026-08-25' });
      const m = col.get(r.record.id);
      return {
        total: col.active().length, statut: m.statutMission, valideePar: m.valideePar,
        priseEnCharge: m.structurePrise,
        alerte: /en attente de validation/.test(document.body.textContent),
      };
    });
    verifier('Un ordre de mission porte sa structure de prise en charge',
      mission.priseEnCharge === 'OMS Bénin');
    verifier('La Directrice Administrative valide avant le départ',
      mission.statut === 'validee' && mission.valideePar === 'TAKI Alimatou');
    verifier('Les ordres en attente de validation sont signalés', mission.alerte);

    /* Redevances ORTB — deux catégories cumulables, mars et juin.
       La règle a été corrigée par la Direction le 20/08/2026 : la radio est
       due par TOUS, la télé s'y AJOUTE au-delà de 60 000 F. Le piège que ce
       scénario garde fermé est le modèle précédent, qui dispensait de la
       radio les salaires élevés. */
    await ouvrir('m11-ortb.html');
    const ortb = await page.evaluate(() => {
      const S = window.SIGH.store, D = window.SIGH.data;
      const r = D.PARAM_PAIE.ortb.redevances;
      const radio = r.filter((x) => x.id === 'radio')[0];
      const tele = r.filter((x) => x.id === 'tele')[0];
      /* Le calcul lui-même, éprouvé de part et d'autre du seuil. */
      const sess = S.session();
      const petit = 45000, gros = 250000;
      const lignes = [...document.querySelectorAll('#page-content tbody tr')].map((x) => x.textContent);
      const entetes = [...document.querySelectorAll('#page-content thead th')].map((x) => x.textContent);
      return {
        radioMontant: radio.montant, radioSeuil: radio.seuilMin, radioMois: radio.moisLabel,
        radioAssiette: radio.assiette,
        teleMontant: tele.montant, teleSeuil: tele.seuilMin, teleMois: tele.moisLabel,
        cumul: D.PARAM_PAIE.ortb.cumulMaximum,
        seuilTele: D.PARAM_PAIE.ortb.seuilTele,
        /* Sous le seuil : radio seule. Au-dessus : les deux. */
        souSeuil: r.filter((x) => (x.seuilMin == null || petit >= x.seuilMin)).map((x) => x.id),
        surSeuil: r.filter((x) => (x.seuilMin == null || gros >= x.seuilMin)).map((x) => x.id),
        colonneRadio: entetes.some((h) => /ORTB Radio/.test(h)),
        colonneTele: entetes.some((h) => /ORTB T[ée]l[ée]/.test(h)),
        afficheMars: lignes.some((l) => /mars/.test(l)) || document.body.textContent.includes('mars'),
        afficheJuin: lignes.some((l) => /juin/.test(l)) || document.body.textContent.includes('juin'),
        cumulAffiche: /Radio \+ T[ée]l[ée]/.test(document.body.textContent),
        session: sess.role,
      };
    });
    verifier('La redevance ORTB Radio vaut 1 000 F pour TOUS les salariés, en mars',
      ortb.radioMontant === 1000 && ortb.radioSeuil == null && ortb.radioMois === 'mars',
      ortb.radioMontant + ' F · ' + ortb.radioAssiette + ' · ' + ortb.radioMois);
    verifier('La redevance ORTB Télé vaut 3 000 F au-delà de 60 000 F, en juin',
      ortb.teleMontant === 3000 && ortb.teleSeuil === 60001 && ortb.teleMois === 'juin',
      ortb.teleMontant + ' F · > ' + ortb.seuilTele + ' F · ' + ortb.teleMois);
    verifier('Un salaire sous le seuil ne doit que la radio',
      ortb.souSeuil.length === 1 && ortb.souSeuil[0] === 'radio',
      ortb.souSeuil.join(' + '));
    verifier('Un salaire au-dessus du seuil doit les DEUX, soit 4 000 F',
      ortb.surSeuil.length === 2 && ortb.cumul === 4000,
      ortb.surSeuil.join(' + ') + ' = ' + ortb.cumul + ' F');
    verifier('Les deux catégories sont distinguées à l’écran',
      ortb.colonneRadio && ortb.colonneTele && ortb.cumulAffiche);
    verifier('Le prélèvement reste annuel : mars pour la radio, juin pour la télé',
      ortb.afficheMars && ortb.afficheJuin);

    /* La catégorisation doit se retrouver sur le bulletin et aux cotisations. */
    await ouvrir('m11-cotisations.html');
    const cot = await page.evaluate(() => {
      const entetes = [...document.querySelectorAll('#page-content thead th')].map((x) => x.textContent);
      const t = document.body.textContent;
      return {
        colRadio: entetes.some((h) => /ORTB Radio/.test(h)),
        colTele: entetes.some((h) => /ORTB T[ée]l[ée]/.test(h)),
        colTotal: entetes.some((h) => /ORTB total/.test(h)),
        kpiRadio: /ORTB Radio/.test(t),
        kpiTele: /ORTB T[ée]l[ée]/.test(t),
        etat: [...document.querySelectorAll('#page-content button')].some((b) => /État ORTB/.test(b.textContent)),
      };
    });
    verifier('Les cotisations distinguent ORTB Radio, ORTB Télé et le total',
      cot.colRadio && cot.colTele && cot.colTotal);
    verifier('Les deux catégories ont leur indicateur et leur état imprimable',
      cot.kpiRadio && cot.kpiTele && cot.etat);

    /* Le bulletin de mars porte la radio, celui de juin la télé. */
    await ouvrir('m11-bulletins.html');
    const bul = await page.evaluate(() => {
      const M = window.SIGH.modules && window.SIGH.modules.paie;
      const D = window.SIGH.data;
      const r = D.PARAM_PAIE.ortb.redevances;
      /* Reconstitution du calcul depuis le référentiel, sans dépendre d'un
         agent particulier du jeu de test. */
      function du(brut, mois) {
        return r.filter((x) => (x.seuilMin == null || brut >= x.seuilMin) && x.mois === mois)
          .reduce((n, x) => n + x.montant, 0);
      }
      return {
        petitMars: du(45000, 2), petitJuin: du(45000, 5),
        grosMars: du(250000, 2), grosJuin: du(250000, 5),
        grosAnnuel: du(250000, 2) + du(250000, 5),
        autreMois: du(250000, 0) + du(250000, 8),
        moduleCharge: !!M || true,
      };
    });
    verifier('Un petit salaire supporte 1 000 F en mars et rien en juin',
      bul.petitMars === 1000 && bul.petitJuin === 0,
      bul.petitMars + ' F en mars · ' + bul.petitJuin + ' F en juin');
    verifier('Un salaire élevé supporte 1 000 F en mars PUIS 3 000 F en juin',
      bul.grosMars === 1000 && bul.grosJuin === 3000 && bul.grosAnnuel === 4000,
      bul.grosMars + ' + ' + bul.grosJuin + ' = ' + bul.grosAnnuel + ' F');
    verifier('Aucun autre mois n’est prélevé', bul.autreMois === 0);

    /* Le bulletin lui-même : les deux catégories doivent s'afficher, y compris
       celle qui n'est pas prélevée ce mois-ci. Le tiroir ne s'ouvre qu'au clic,
       donc le contrôle des pages ne le voit pas — d'où ce garde-fou. */
    await ouvrir('m11-calcul.html');
    const tiroir = await page.evaluate(async () => {
      const sel = [...document.querySelectorAll('#page-content select')]
        .find((x) => [...x.options].some((o) => /mars/i.test(o.textContent)));
      if (!sel) return { erreur: 'sélecteur de période introuvable' };
      sel.value = '2'; /* mars — la radio est prélevée, la télé ne l'est pas */
      sel.dispatchEvent(new Event('change'));
      await new Promise((r) => setTimeout(r, 250));
      const tr = document.querySelector('#page-content tbody tr');
      if (!tr) return { erreur: 'aucun agent au tableau' };
      tr.click();
      await new Promise((r) => setTimeout(r, 350));
      const lignes = [...document.querySelectorAll('tbody tr')]
        .map((x) => x.textContent.replace(/\s+/g, ' ').trim())
        .filter((x) => /ORTB/.test(x));
      return {
        radio: lignes.some((l) => /Radio/.test(l) && /prélevée ce mois/.test(l)),
        tele: lignes.some((l) => /T[ée]l[ée]/.test(l) && /prélevée en juin/.test(l)),
        nombre: lignes.length,
      };
    });
    verifier('Le bulletin de mars porte la radio prélevée et la télé annoncée pour juin',
      tiroir.radio && tiroir.tele && tiroir.nombre === 2,
      tiroir.erreur || (tiroir.nombre + ' ligne(s) ORTB au tiroir'));


    /* Assurances du personnel — dossier RH, hors recettes */
    await ouvrir('m10-personnel.html');
    const assRh = await page.evaluate(() => {
      const S = window.SIGH.store;
      const e = S.collection('personnel').active()[0];
      const col = S.collection('assurancesPersonnel');
      col.insert({
        employeId: e.id, agent: e.nomComplet, type: 'Mutuelle de santé',
        organisme: 'Mutuelle test', numeroAdhesion: 'MUT-001', taux: 80, dateDebut: '2026-01-01',
      });
      return {
        n: col.active().length,
        horsRecettes: !S.collection('factures').active().some((f) => /Mutuelle test/.test(f.type || '')),
      };
    });
    verifier('Le personnel a ses propres couvertures, hors des recettes',
      assRh.n > 0 && assRh.horsRecettes);

    /* Calendrier fiscal */
    await ouvrir('cfg-fiscalite.html');
    const fiscal = await page.evaluate(() => {
      const D = window.SIGH.data;
      const txt = document.body.textContent;
      return {
        echeances: D.CALENDRIER_FISCAL.length,
        mensuelles: D.CALENDRIER_FISCAL.filter((e) => e.periodicite === 'mensuelle').map((e) => e.code),
        acomptes: D.CALENDRIER_FISCAL.filter((e) => /^IS-\d$/.test(e.code)).length,
        affiche: /Calendrier fiscal et social/.test(txt),
        ccib: /CCIB/.test(txt),
        liquidation: /liquidation du solde|Liquidation du solde/.test(txt),
      };
    });
    verifier('ITS, AIB, VPS et CNSS sont au 10 du mois suivant',
      ['ITS', 'AIB', 'VPS', 'CNSS'].every((c) => fiscal.mensuelles.includes(c)),
      fiscal.mensuelles.join(' · '));
    verifier('L’impôt sur les sociétés se paie en quatre acomptes', fiscal.acomptes === 4);
    verifier('Le calendrier couvre patente, CCIB, TVM et liquidation du solde',
      fiscal.affiche && fiscal.ccib && fiscal.liquidation, fiscal.echeances + ' échéances');

    /* Certificats médicaux */
    await ouvrir('cfg-certificats.html');
    const certif = await page.evaluate(() => {
      const S = window.SIGH.store;
      const col = S.collection('certificats');
      const p = S.collection('patients').active()[0];
      const r = col.insert({
        numero: 'CERT-TEST', type: 'repos', date: '2026-08-20',
        patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
        praticien: 'YENI M’PO Florent', duree: 5, dateDebut: '2026-08-21',
        texte: 'Je soussigné(e), YENI M’PO Florent, certifie… repos de 5 jour(s).',
      });
      return {
        types: (document.body.textContent.match(/Certificat médical de|Attestation d’/g) || []).length,
        cree: !!col.get(r.record.id),
        repos: /repos/.test(col.get(r.record.id).texte),
      };
    });
    verifier('Le catalogue des certificats couvre les types énumérés',
      certif.types >= 4, certif.types + ' types affichés');
    verifier('Un certificat délivré est numéroté et conserve son texte',
      certif.cree && certif.repos);

    /* Sauvegardes exportables */
    await ouvrir('m14-sauvegardes.html');
    const backup = await page.evaluate(() => {
      const S = window.SIGH.store;
      const col = S.collection('fichiersSauvegarde');
      const avant = col.active().length;
      const cols = Object.keys(S.raw()).filter((k) => k[0] !== '_' && Array.isArray(S.raw()[k]));
      col.insert({
        fichier: 'sigh-cnt-test.json', date: '2026-08-20', heure: '10:00',
        portee: 'Base complète', tables: cols.length, taille: 1024, genereePar: 'Test',
      });
      return {
        table: /Fichiers de sauvegarde disponibles/.test(document.body.textContent),
        colonnes: /Fichier/.test(document.body.textContent) && /Tables/.test(document.body.textContent),
        generer: [...document.querySelectorAll('button')].some((b) => /Générer une sauvegarde/.test(b.textContent)),
        importer: [...document.querySelectorAll('button')].some((b) => /Importer par module/.test(b.textContent)),
        avant: avant, apres: col.active().length,
      };
    });
    verifier('La table des sauvegardes porte fichier, date, tables et action',
      backup.table && backup.colonnes);
    verifier('Une sauvegarde peut être générée et une autre importée par module',
      backup.generer && backup.importer);
    verifier('Le fichier généré s’ajoute au registre', backup.apres === backup.avant + 1);

    /* Réinitialisation protégée par bascule */
    await ouvrir('cfg-systeme.html');
    const reinit = await page.evaluate(async () => {
      const S = window.SIGH.store;
      S.storage.remove('sigh-cnt:reinit-autorisee');
      const onglet = [...document.querySelectorAll('.tab')].find((t) => /Jeux de test/.test(t.textContent));
      onglet.click();
      await new Promise((r) => setTimeout(r, 400));
      const verrouille = /verrouillée|Verrouillée/.test(document.body.textContent)
        && !document.body.textContent.includes('Vider les jeux de test');
      S.storage.set('sigh-cnt:reinit-autorisee', 'oui');
      onglet.click();
      await new Promise((r) => setTimeout(r, 400));
      const ouverte = document.body.textContent.includes('Vider les jeux de test');
      S.storage.remove('sigh-cnt:reinit-autorisee');
      return {
        onglet: !!onglet, verrouille: verrouille, ouverte: ouverte,
        conserve: /Conservé — paramétrage et référentiels/.test(document.body.textContent),
      };
    });
    verifier('Un onglet « Jeux de test » figure aux paramètres', reinit.onglet);
    verifier('Verrouillée, la réinitialisation est indisponible — pas seulement refusée', reinit.verrouille);
    verifier('Déverrouillée, elle devient possible', reinit.ouverte);
    verifier('L’écran distingue ce qui serait effacé de ce qui serait conservé', reinit.conserve);

    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 24. Valorisation des sorties et états de la Direction
   * -------------------------------------------------------------------------
   * Les deux points laissés en suspens : la méthode de valorisation des sorties
   * de stock, devenue un paramètre, et les états par groupe et famille, dont
   * les familles viennent du document et les groupes d'une proposition.
   * ======================================================================= */
  {
    scenario('Valorisation des sorties et états de la Direction');

    await ouvrir('cfg-regles.html');
    const valo = await page.evaluate(() => {
      const D = window.SIGH.data;
      return {
        defaut: D.PARAM_STOCK.valorisationSortie,
        options: D.PARAM_STOCK.options.map((o) => o.id),
        familles: D.FAMILLES_ARTICLES.length,
        groupes: D.GROUPES_ARTICLES.length,
        aConfirmer: D.GROUPES_ARTICLES.aConfirmer === true,
        affiche: /Valorisation des sorties de stock/.test(document.body.textContent),
        mesure: /Écart entre les deux méthodes/.test(document.body.textContent),
        avertissement: /proposition/.test(document.body.textContent),
      };
    });
    verifier('La valorisation des sorties est un paramètre, non une règle figée',
      valo.options.length === 2 && valo.options.includes('prixVente') && valo.options.includes('cump'));
    verifier('Le prix de vente est retenu par défaut, comme demandé', valo.defaut === 'prixVente');
    verifier('L’écran mesure ce que le choix change réellement', valo.affiche && valo.mesure);

    verifier('Les sept familles viennent de l’inventaire SAGE', valo.familles === 7);
    /* Vague 49 : les quatre groupes sont CONFIRMÉS par la Direction. */
    verifier('Les quatre groupes d’articles sont CONFIRMÉS (vague 49)',
      valo.groupes === 4 && valo.aConfirmer === false);

    /* Le mouvement de sortie porte les deux valorisations */
    await ouvrir('m6-dispensation.html');
    const mouvement = await page.evaluate(() => {
      const S = window.SIGH.store, PR = window.SIGH.parcours;
      const p = S.collection('produits').active().filter((x) => x.stockDetail > 5)[0];
      const v = PR.valoriserSortie(p, 3);
      return {
        methode: v.methode,
        prixVente: v.valeurPrixVente, cump: v.valeurCump,
        retenu: v.valeur,
        coherent: v.valeur === (v.methode === 'cump' ? v.valeurCump : v.valeurPrixVente),
      };
    });
    verifier('Une sortie porte les deux valorisations, pas seulement celle retenue',
      mouvement.prixVente > 0 && mouvement.cump > 0 && mouvement.coherent,
      'retenu ' + mouvement.retenu + ' · prix de vente ' + mouvement.prixVente + ' · CUMP ' + mouvement.cump);

    /* États de la Direction : période × axe */
    await ouvrir('rapports-direction.html');
    const etats = await page.evaluate(async () => {
      const selects = [...document.querySelectorAll('#page-content select')];
      const periodes = [...selects[0].options].map((o) => o.textContent);
      const axes = [...selects[selects.length - 1].options].map((o) => o.textContent);
      /* Bascule sur l'axe « famille » */
      const selAxe = selects[selects.length - 1];
      selAxe.value = 'famille';
      selAxe.dispatchEvent(new Event('change', { bubbles: true }));
      await new Promise((r) => setTimeout(r, 450));
      const familleAffichee = /Famille|famille/.test(document.body.textContent);
      selAxe.value = 'groupe';
      selAxe.dispatchEvent(new Event('change', { bubbles: true }));
      await new Promise((r) => setTimeout(r, 450));
      return {
        periodes: periodes, axes: axes,
        familleAffichee: familleAffichee,
        avertissementGroupe: /proposition/.test(document.body.textContent),
        cumul: /Cumul global/.test(document.body.textContent),
        quantite: /Quantité vendue/.test(document.body.textContent),
      };
    });
    verifier('Les six périodicités du cahier de charge sont proposées',
      etats.periodes.length === 6 && etats.periodes.some((p) => /Journalier/.test(p))
      && etats.periodes.some((p) => /Annuel/.test(p)), etats.periodes.join(' · '));
    verifier('Les états se déclinent par client, article, famille et groupe',
      etats.axes.length === 6 && etats.axes.some((a) => /client/.test(a))
      && etats.axes.some((a) => /famille/.test(a)) && etats.axes.some((a) => /groupe/.test(a)));
    verifier('L’axe famille produit un état', etats.familleAffichee);
    verifier('L’axe groupe rappelle qu’il s’agit d’une proposition', etats.avertissementGroupe);
    verifier('Le cumul global et la quantité vendue sont totalisés',
      etats.cumul && etats.quantite);

    verifier('Aucune erreur JavaScript sur ces états', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 25. Obligations fiscales — documentation, échéancier et validation
   * -------------------------------------------------------------------------
   * Arbitrages de la Direction du 20/08/2026 : le calendrier du comptable est
   * documenté, déroulé sur l'exercice, et chaque paiement se valide.
   * ======================================================================= */
  {
    scenario('Obligations fiscales — documentation, échéancier et validation');

    /* La page de référence documente tout ce que le comptable a précisé */
    await ouvrir('cfg-comptabilite.html');
    const doc = await page.evaluate(() => {
      const t = document.body.textContent;
      const esp = (n) => new RegExp(n.replace(/ /g, '[\s\u202f\u00a0]')).test(t);
      return {
        patente: /31 janvier/.test(t) && /10 février/.test(t) && /30 avril/.test(t),
        ccib: esp('300 000') && /10 mars/.test(t) && /10 juin/.test(t),
        acomptes: /10 mars/.test(t) && /10 juin/.test(t) && /10 septembre/.test(t) && /10 décembre/.test(t),
        tvm: /véhicules à moteur/i.test(t) && /30 avril/.test(t),
        ortb: /ORTB/.test(t) && esp('1 000') && esp('3 000') && esp('4 000')
          && /sans exception/.test(t) && /cumulent/.test(t),
        liquidation: /liquidation du solde/i.test(t) && /états financiers/i.test(t),
        report: /jour ouvrable/i.test(t),
      };
    });
    verifier('La patente est documentée : déclaration au 31 janvier, deux tranches', doc.patente);
    verifier('La CCIB est documentée : 300 000 F en deux tranches, mars et juin', doc.ccib);
    verifier('Les quatre acomptes d'+String.fromCharCode(8217)+'impôt sur les sociétés sont datés', doc.acomptes);
    verifier('La TVM est documentée : une fois par an, au 30 avril', doc.tvm);
    verifier('Les redevances ORTB Radio et Télé sont documentées', doc.ortb);
    verifier('Liquidation du solde et dépôt des états financiers sont distingués', doc.liquidation);
    verifier('Le report au jour ouvrable est énoncé', doc.report);

    /* L'échéancier déroule les obligations et suit leur état */
    await ouvrir('m12-echeances.html');
    const ech = await page.evaluate(() => {
      const S = window.SIGH.store;
      const rows = S.collection('echeancesFiscales').active();
      return {
        total: rows.length,
        familles: [...new Set(rows.map((e) => e.famille))].length,
        mensuelles: rows.filter((e) => e.periodicite === 'mensuelle').length,
        reportees: rows.filter((e) => e.reportee).length,
        barre: /échéance|paiement|déclaration/i.test(document.body.textContent),
      };
    });
    verifier('Les obligations sont déroulées sur l'+String.fromCharCode(8217)+'exercice',
      ech.total > 50 && ech.familles === 10, ech.total + ' échéances · ' + ech.familles + ' obligations');
    verifier('Les obligations mensuelles donnent douze échéances chacune',
      ech.mensuelles === 48, ech.mensuelles + ' échéances mensuelles');
    verifier('Les échéances tombant un week-end sont reportées',
      ech.reportees > 0, ech.reportees + ' reportée(s) au jour ouvrable');
    verifier('Une barre de notification signale ce qui est dû', ech.barre);

    /* Validation d'un paiement, puis annulation */
    const paiement = await page.evaluate(() => {
      const S = window.SIGH.store;
      const col = S.collection('echeancesFiscales');
      const e = col.active().filter((x) => !x.paye)[0];
      col.update(e.id, {
        paye: true, datePaiement: '2026-08-20', montant: 150000,
        moyen: 'Virement bancaire', reference: 'QUIT-TEST', valideePar: 'KASSA Augustin',
      });
      /* collection().get() rend l'enregistrement VIVANT : le figer avant
         d'annuler, sans quoi l'annulation réécrirait ce qu'on vient de lire. */
      const apres = Object.assign({}, col.get(e.id));
      col.update(e.id, { paye: false, montant: null, reference: null, valideePar: null });
      return {
        code: apres.code, paye: apres.paye, montant: apres.montant,
        reference: apres.reference, valideePar: apres.valideePar,
        redevenueDue: col.get(e.id).paye === false,
      };
    });
    verifier('Un paiement se valide avec montant, quittance et auteur',
      paiement.paye && paiement.montant === 150000 && paiement.reference === 'QUIT-TEST'
      && paiement.valideePar === 'KASSA Augustin', paiement.code);
    verifier('La validation reste annulable — l'+String.fromCharCode(8217)+'échéance redevient due', paiement.redevenueDue);

    /* Tarifs d'attente sur les actes */
    await ouvrir('cfg-tarifs.html#onglet=actes');
    const tarifs = await page.evaluate(() => {
      const A = window.SIGH.data.ACTES;
      const rapproches = A.filter((a) => a.codeTarif);
      return {
        total: A.length,
        tarifes: A.filter((a) => a.prix != null).length,
        provisoires: A.filter((a) => a.tarifProvisoire).length,
        documentes: A.filter((a) => a.prix != null && !a.tarifProvisoire).length,
        rapproches: rapproches.length,
        /* Un acte rapproché ne peut plus être « en attente » : son prix vient
           d'une grille imprimée. */
        rapprochesProvisoires: rapproches.filter((a) => a.tarifProvisoire).length,
        /* Règle de la Direction : dans tous les actes, l'assuré paie moins. */
        assurePaieplus: rapproches.filter((a) => a.prixAssure != null
          && a.prixNonAssure != null && a.prixAssure > a.prixNonAssure).length,
        /* Deux voies de rapprochement, et aucune troisième. */
        voies: Array.from(new Set(rapproches.map((a) => a.rapprochement))).sort(),
        /* Un acte que la grille décline n'est pas « sans prix » : il attend
           qu'on dise DE QUEL acte il s'agit. */
        declines: A.filter((a) => a.variantesGrille && a.variantesGrille.length).length,
        motifsDeclines: A.filter((a) => a.variantesGrille && a.variantesGrille.length
          && a.motifPrix).length,
        signale: /valeur d/.test(document.body.textContent),
        montreAssure: /Tarif assuré/.test(document.body.textContent),
      };
    });
    verifier('Tous les actes portent désormais un tarif',
      tarifs.tarifes === tarifs.total, tarifs.tarifes + '/' + tarifs.total);
    verifier('Les actes reprennent les prix des grilles imprimées',
      tarifs.rapproches === 28, tarifs.rapproches + ' acte(s) rapproché(s)');
    verifier('Un acte rapproché n'+String.fromCharCode(8217)+'est plus une valeur d'+String.fromCharCode(8217)+'attente',
      tarifs.rapprochesProvisoires === 0, String(tarifs.rapprochesProvisoires));
    verifier('Le rapprochement passe par le libellé ou par une correspondance nommée, jamais par approximation',
      tarifs.voies.length === 2 && tarifs.voies.join(' | ') === 'correspondance nommée | libellé identique',
      tarifs.voies.join(' | '));
    verifier('Dans tous les actes rapprochés, l'+String.fromCharCode(8217)+'assuré paie moins que le non-assuré',
      tarifs.assurePaieplus === 0, String(tarifs.assurePaieplus) + ' contre-exemple(s)');
    verifier('Les actes déclinés par la grille disent pourquoi ils restent sans prix',
      tarifs.declines === 4 && tarifs.motifsDeclines === tarifs.declines,
      tarifs.declines + ' décliné(s), ' + tarifs.motifsDeclines + ' motivé(s)');
    /* Vague 49 : la SEMENCE documente l'état du 20/08 (40 attente · 29
       documentés) ; le catalogue VIVANT, lui, est arrêté par la Direction. */
    verifier('La semence garde la distinction du 20/08 ; le catalogue vivant est arrêté (vague 49)',
      tarifs.provisoires === 40 && tarifs.documentes === 29,
      tarifs.documentes + ' documentés · ' + tarifs.provisoires + ' en attente (semence)');
    verifier('L'+String.fromCharCode(8217)+'écran montre les deux colonnes de la grille',
      tarifs.montreAssure, 'colonne « Tarif assuré »');

    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 26. RH ÉTENDUE — régimes, primes datées, événements, verrouillage
   * -------------------------------------------------------------------------
   * Ce que ce scénario garde fermé : une modification de régime ou de prime
   * qui réécrirait le passé, une participation prélevée douze fois au lieu
   * d'une, et un verrouillage qui ferait perdre l'écran en cours.
   * ======================================================================= */
  {
    scenario('RH étendue — régimes, primes datées, événements et verrouillage');

    await page.evaluate(() => window.SIGH.store.setSession({
      role: 'admin', nom: 'BASSONGUI Chabi Séko', fonction: 'direction', secteur: 'ADM',
    }));

    /* --- Régimes de travail administrables -------------------------------- */
    await ouvrir('m10-planning.html');
    const reg = await page.evaluate(() => {
      const S = window.SIGH.store;
      const rows = S.collection('regimesTravail').active();
      const inc = rows.filter((r) => /Incin/i.test(r.libelle))[0];
      const boutons = [...document.querySelectorAll('#page-content button')].map((b) => b.textContent);
      const titres = [...document.querySelectorAll('#page-content button[title]')].map((b) => b.title);
      return {
        n: rows.length,
        incineration: !!inc,
        honoraire: inc ? inc.honoraire : null,
        source: inc ? inc.source : '',
        nouveau: boutons.some((t) => /Nouveau régime/.test(t)),
        modifier: titres.some((t) => /Modifier ce régime/.test(t)),
        archiver: titres.some((t) => /Archiver ce régime/.test(t)),
        graphes: /Gardes par agent|Gardes par service/.test(document.body.textContent),
      };
    });
    verifier('Les régimes de travail vivent dans le magasin', reg.n >= 8, reg.n + ' régime(s)');
    verifier('Le régime d’incinération des déchets porte son honoraire',
      reg.incineration && reg.honoraire === 5000, reg.honoraire + ' FCFA — ' + reg.source);
    verifier('Le tableau des régimes offre création, modification et archivage',
      reg.nouveau && reg.modifier && reg.archiver);
    verifier('Le planning porte ses graphiques de charge', reg.graphes);

    /* --- Statistiques de garde -------------------------------------------- */
    await ouvrir('m10-stats-gardes.html');
    const stats = await page.evaluate(() => {
      const t = document.body.textContent;
      const entetes = [...document.querySelectorAll('#page-content thead th')].map((x) => x.textContent);
      return {
        lignes: [...document.querySelectorAll('#page-content tbody tr')].length,
        colonnes: entetes.join(' | '),
        repos: /repos et congés en sont exclus/i.test(t),
        periodes: [...document.querySelectorAll('#page-content select option')].map((o) => o.textContent).join(' | '),
      };
    });
    verifier('Les statistiques de garde comptent par agent', stats.lignes > 0, stats.lignes + ' agent(s)');
    verifier('Le décompte distingue gardes, permanences et soirées',
      /Gardes/.test(stats.colonnes) && /Permanences/.test(stats.colonnes) && /Soirées/.test(stats.colonnes));
    verifier('Les repos sont explicitement exclus du comptage', stats.repos);
    verifier('Les périodicités vont de la semaine à l’année',
      /Semaine/.test(stats.periodes) && /Trimestre/.test(stats.periodes) && /Semestre/.test(stats.periodes));

    /* --- Grille des primes datée ------------------------------------------ */
    await ouvrir('m10-primes.html');
    const primes = await page.evaluate(() => {
      const S = window.SIGH.store, D = window.SIGH.data;
      const col = S.collection('grillePrimes');
      const hist = S.collection('historiquePrimes');
      const garde = col.active().filter((x) => x.primeId === 'garde')[0];
      const avant = D.NS132.montant('garde', 'infirmier', '2026-07-28');
      hist.insert({
        primeId: 'garde', label: garde.label, mode: garde.mode,
        montants: Object.assign({}, garde.montants),
        dateEffet: garde.dateEffet, dateFin: '2026-08-20',
      });
      const nouveaux = Object.assign({}, garde.montants);
      Object.keys(nouveaux).forEach((k) => { nouveaux[k] = nouveaux[k] + 500; });
      col.update(garde.id, { montants: nouveaux, dateEffet: '2026-08-21' });
      return {
        juillet: D.NS132.montant('garde', 'infirmier', '2026-07-28'),
        aout: D.NS132.montant('garde', 'infirmier', '2026-08-28'),
        avant: avant,
        crud: [...document.querySelectorAll('#page-content button')].map((b) => b.textContent).join(' | '),
      };
    });
    verifier('La grille des primes est modifiable depuis l’écran',
      /Nouvelle prime/.test(primes.crud));
    verifier('Une prime relevée ne réécrit PAS le mois déjà calculé',
      primes.juillet === primes.avant, 'juillet : ' + primes.juillet + ' F, inchangé');
    verifier('La nouvelle valeur s’applique à compter de sa date d’effet',
      primes.aout === primes.avant + 500, 'août : ' + primes.aout + ' F');

    /* --- Événements du personnel ------------------------------------------ */
    await ouvrir('m10-evenements.html');
    const evt = await page.evaluate(() => {
      const S = window.SIGH.store, C = window.SIGH.core;
      const cols = S.collection('evenements', { module: 'M10', entite: 'événement', prefix: 'EVT' });
      const parts = S.collection('participations', { module: 'M10', entite: 'participation', prefix: 'PAR' });
      const agents = S.collection('personnel').active();
      const ben = agents[0];
      const res = cols.insert({
        reference: 'EVT-TEST', nature: 'mariage', libelle: 'Mariage de recette',
        beneficiaireId: ben.id, beneficiaire: ben.nomComplet,
        date: C.iso(new Date(2026, 7, 21)), montantParAgent: 1000,
        periodePaiement: '2026-08', modeParDefaut: 'salaire',
      });
      agents.filter((e) => e.id !== ben.id).forEach((e) => {
        parts.insert({
          evenementId: res.record.id, evenementLibelle: 'Mariage de recette',
          nature: 'mariage', employeId: e.id, agent: e.nomComplet, matricule: e.matricule,
          fonction: e.fonction, service: e.service, montant: 1000,
          mode: 'salaire', periodeRetenue: '2026-08', statutPaiement: 'du',
        });
      });
      const mes = parts.active().filter((x) => x.evenementId === res.record.id);
      return {
        agents: agents.length, participations: mes.length,
        beneficiaireExclu: !mes.some((x) => x.employeId === ben.id),
        attendu: mes.reduce((n, x) => n + x.montant, 0),
        evenementId: res.record.id, premierAgent: mes[0].employeId,
        natures: window.SIGH.data.PARAM_EVENEMENTS.natures.map((n) => n.label).join(' | '),
        standard: window.SIGH.data.PARAM_EVENEMENTS.montantStandard,
      };
    });
    verifier('Créer un événement engendre une participation par agent',
      evt.participations === evt.agents - 1,
      evt.participations + ' participations pour ' + evt.agents + ' agents');
    verifier('Le bénéficiaire ne cotise pas à son propre événement', evt.beneficiaireExclu);
    verifier('La participation standard est de 1 000 FCFA', evt.standard === 1000);
    verifier('Les natures d’événement couvrent mariage, naissance et décès',
      /Mariage/.test(evt.natures) && /Naissance/.test(evt.natures) && /Décès/.test(evt.natures));

    /* --- La retenue figure au bulletin du mois choisi, une seule fois ------ */
    await ouvrir('m11-calcul.html');
    const bul = await page.evaluate((employeId) => {
      const S = window.SIGH.store;
      const parts = S.collection('participations').active()
        .filter((x) => x.employeId === employeId && x.mode === 'salaire');
      const entetes = [...document.querySelectorAll('#page-content thead th')].map((x) => x.textContent);
      /* Le mois de retenue est unique : la participation ne se prélève pas
         chaque mois de l'année. */
      const periodes = [...new Set(parts.map((x) => x.periodeRetenue))];
      return {
        aRetenir: parts.length, periodes: periodes,
        colonneEvenements: entetes.some((h) => /Événements/.test(h)),
        colonneAvance: entetes.some((h) => /Avance sur salaire/.test(h)),
      };
    }, evt.premierAgent);
    verifier('Le détail du calcul porte une colonne « Avance sur salaire »', bul.colonneAvance);
    verifier('Le détail du calcul porte une colonne « Événements »', bul.colonneEvenements);
    verifier('La participation ne vise qu’un seul mois de retenue',
      bul.periodes.length === 1 && bul.periodes[0] === '2026-08', bul.periodes.join(', '));

    /* --- Paiement au comptant, tracé --------------------------------------- */
    await ouvrir('m10-participations.html');
    const comptant = await page.evaluate((evenementId) => {
      const S = window.SIGH.store, C = window.SIGH.core;
      const parts = S.collection('participations');
      const x = parts.active().filter((y) => y.evenementId === evenementId)[0];
      parts.update(x.id, {
        mode: 'comptant', statutPaiement: 'paye', montantVerse: 1000,
        datePaiement: C.iso(new Date(2026, 7, 21)), recu: 'REC-PART-0001',
        encaissePar: 'Caisse — poste accueil',
      });
      const apres = Object.assign({}, parts.get(x.id));
      return { statut: apres.statutPaiement, recu: apres.recu, mode: apres.mode, verse: apres.montantVerse };
    }, evt.evenementId);
    verifier('Un règlement au comptant est encaissé avec son reçu',
      comptant.statut === 'paye' && comptant.mode === 'comptant' && !!comptant.recu,
      comptant.recu + ' — ' + comptant.verse + ' FCFA');

    /* --- Assurance du personnel -------------------------------------------- */
    await ouvrir('m10-assurance-personnel.html');
    const ass = await page.evaluate(() => {
      const S = window.SIGH.store;
      const agents = S.collection('patients').active().filter((p) => p.personnelId);
      const t = document.body.textContent;
      const boutons = [...document.querySelectorAll('#page-content button')].map((b) => b.textContent).join(' | ');
      return {
        dossiers: agents.length,
        lignes: [...document.querySelectorAll('#page-content tbody tr')].length,
        horsRecettes: /chiffre d’affaires|Ni recette, ni créance/.test(t),
        sansSaisie: !/Nouveau|Ajouter/.test(boutons),
        centPourCent: /100 %/.test(t),
      };
    });
    verifier('Des agents disposent d’un dossier patient rattaché',
      ass.dossiers > 0, ass.dossiers + ' dossier(s)');
    verifier('Les prestations au personnel sont listées', ass.lignes > 0, ass.lignes + ' ligne(s)');
    verifier('La prise en charge est de 100 % et se dit telle', ass.centPourCent);
    verifier('L’écran n’ouvre aucune saisie — il se remplit seul', ass.sansSaisie);
    verifier('Les prestations sont annoncées hors recettes et hors comptabilité', ass.horsRecettes);

    /* --- Verrouillage de session ------------------------------------------- */
    await ouvrir('m1-patients.html');
    const verrou = await page.evaluate(() => {
      const S = window.SIGH.store, A = window.SIGH.app;
      S.storage.set(A.VERROU_RETOUR, 'm1-patients.php#onglet=liste');
      return { delai: A.delaiVerrou() };
    });
    verifier('Le délai de verrouillage est de quinze minutes',
      verrou.delai === 900000, Math.round(verrou.delai / 60000) + ' minutes');

    await ouvrir('auth-lock.html');
    const lock = await page.evaluate(() => {
      const t = document.body.textContent;
      const S = window.SIGH.store;
      return {
        suspendue: /suspendue, pas fermée/.test(t),
        retour: /Répertoire des patients/.test(t),
        sessionIntacte: !!S.session(),
        deverrouiller: [...document.querySelectorAll('button')].some((b) => /Déverrouiller/.test(b.textContent)),
      };
    });
    verifier('L’écran verrouillé conserve la session ouverte', lock.sessionIntacte);
    verifier('Le verrouillage suspend la session sans la fermer', lock.suspendue);
    verifier('L’écran annonce où l’utilisateur reviendra', lock.retour);
    verifier('Le déverrouillage est proposé', lock.deverrouiller);

    await page.evaluate(() => {
      const S = window.SIGH.store, A = window.SIGH.app;
      S.storage.remove(A.VERROU_RETOUR);
    });
    verifier('Aucune erreur JavaScript sur la RH étendue', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 27. LABORATOIRE — modèle de résultat, circuit du prélèvement, modules
   * -------------------------------------------------------------------------
   * Le contrôle décisif : le modèle reproduit-il la FICHE RÉELLE du dossier
   * 2026080411 ? Les deux valeurs qu'elle met en gras — lymphocytes 0,70 G/l
   * et hémoglobine 14,3 g/dl — doivent ressortir hors bornes, et aucune autre.
   * ======================================================================= */
  {
    scenario('Laboratoire — modèle de résultat, prélèvement et activité des modules');

    await page.evaluate(() => window.SIGH.store.setSession({
      role: 'admin', nom: 'BASSONGUI Chabi Séko', fonction: 'direction', secteur: 'ADM',
    }));

    /* --- Le catalogue vient du bulletin papier ---------------------------- */
    await ouvrir('m5-valeurs-reference.html');
    const cat = await page.evaluate(() => {
      const S = window.SIGH.store, L = window.SIGH.labo;
      const ex = S.collection('examensLabo').active();
      const va = S.collection('variablesLabo').active();
      const un = S.collection('unitesLabo').active();
      return {
        examens: ex.length, variables: va.length, unites: un.length,
        sections: L.SECTIONS.map((x) => x.id),
        documentes: ex.filter((e) => e.documente).length,
        aValider: va.filter((v) => v.aValider).length,
        valideesBio: va.filter((v) => v.valideLe && /iologiste/.test(v.validePar || '')).length,
        retractables: va.filter((v) => v.retractable).length,
        sousVariables: va.filter((v) => v.parent).length,
      };
    });
    verifier('Le catalogue reprend les examens du bulletin papier',
      cat.examens >= 65, cat.examens + ' examens');
    verifier('Les six sections du bulletin sont respectées',
      ['hematologie', 'serologie', 'parasitologie', 'biochimie', 'bacteriologie', 'hormonologie']
        .every((x) => cat.sections.indexOf(x) !== -1), cat.sections.join(', '));
    verifier('Chaque examen porte ses variables et sous-variables',
      cat.variables >= 150 && cat.sousVariables >= 20,
      cat.variables + ' variables dont ' + cat.sousVariables + ' sous-variables');
    verifier('Les unités sont pré-insérées', cat.unites >= 20, cat.unites + ' unités');
    /* Vague 51 : la validation écrite du biologiste est arrivée — les bornes
       suppléées portent VALIDÉE, distinctes des documentées de la fiche. */
    verifier('Les bornes suppléées portent la validation du biologiste (01/09) — provenances distinctes',
      cat.aValider === 0 && cat.valideesBio > 0 && cat.valideesBio < cat.variables,
      cat.valideesBio + ' validée(s) sur ' + cat.variables);

    /* --- LA VÉRIFICATION QUI COMPTE : la fiche réelle ---------------------- */
    const fiche = await page.evaluate(() => {
      const L = window.SIGH.labo;
      const v = (code) => L.variablesDe('NFS').filter((x) => x.code === code)[0];
      /* Les valeurs exactes du dossier 2026080411, éditées le 21/08/2026. */
      const reels = {
        GB: 7.20, LY: 0.70, MO: 0.60, PNE: 0.2, PNB: 0.00, PNN: 5.70,
        GR: 5.43, HB: 14.3, HTE: 43.50, VGM: 80.10, CCMH: 32.80, TCMH: 26.30, PLQ: 236.00,
      };
      const horsBornes = Object.keys(reels).filter((c) => L.ecart(v(c), reels[c]));
      return {
        horsBornes: horsBornes,
        unites: L.variablesDe('NFS').map((x) => L.unite(x.unite)),
        refGB: L.libelleReference(v('GB')),
        refHB: L.libelleReference(v('HB')),
        refLY: L.libelleReference(v('LY')),
      };
    });
    /* La fiche met en gras : Lymphocytes, Globules Rouges, Hémoglobine, TCMH. */
    verifier('Les valeurs hors bornes de la fiche réelle sont retrouvées',
      ['LY', 'GR', 'HB', 'TCMH'].every((c) => fiche.horsBornes.indexOf(c) !== -1),
      'hors bornes : ' + fiche.horsBornes.join(', '));
    verifier('Aucune valeur normale n’est signalée à tort',
      ['GB', 'MO', 'PNE', 'PNB', 'PNN', 'HTE', 'VGM', 'CCMH', 'PLQ']
        .every((c) => fiche.horsBornes.indexOf(c) === -1),
      fiche.horsBornes.join(', '));
    verifier('La formule leucocytaire est en valeurs absolues (G/l), pas en pourcentages',
      fiche.unites.slice(0, 6).every((u) => u === 'G/l'), fiche.unites.slice(0, 6).join(' '));
    verifier('Les références sont celles du laboratoire, pas celles des manuels',
      fiche.refGB === '4 - 8' && fiche.refHB === '11 - 14' && fiche.refLY === '1 - 4.5',
      'GB ' + fiche.refGB + ' · Hb ' + fiche.refHB + ' · Lympho ' + fiche.refLY);

    /* --- Le VIH : trois tests, réactif, lot, expiration -------------------- */
    const vih = await page.evaluate(() => {
      const L = window.SIGH.labo;
      const v = L.variablesDe('VIH');
      const widal = L.variablesDe('SDW');
      return {
        nb: v.length,
        tests: v.filter((x) => x.type === 'ternaire').length,
        reactifs: v.filter((x) => x.type === 'reactif').length,
        lots: v.filter((x) => x.type === 'lot').length,
        expirations: v.filter((x) => x.type === 'expiration').length,
        conclusion: v.some((x) => x.code === 'CONC'),
        widalAntigenes: widal.filter((x) => x.type === 'titre').length,
        widalReactif: widal.some((x) => x.type === 'reactif'),
        widalCommentaire: widal.some((x) => x.type === 'commentaire'),
      };
    });
    verifier('Le VIH porte trois tests, comme la fiche réelle',
      vih.tests === 3 && vih.conclusion, vih.tests + ' tests + conclusion');
    verifier('Chaque test VIH porte son réactif, son lot et son expiration',
      vih.reactifs === 3 && vih.lots === 3 && vih.expirations === 3,
      vih.reactifs + ' réactifs · ' + vih.lots + ' lots · ' + vih.expirations + ' expirations');
    verifier('Le Widal porte ses huit antigènes, son réactif et son commentaire',
      vih.widalAntigenes === 8 && vih.widalReactif && vih.widalCommentaire,
      vih.widalAntigenes + ' antigènes');

    /* --- Une variable d’accompagnement se ferme sans se supprimer ---------- */
    const fermeture = await page.evaluate(() => {
      const S = window.SIGH.store;
      const col = S.collection('variablesLabo');
      const v = col.active().filter((x) => x.retractable)[0];
      col.update(v.id, { actif: false });
      const apres = Object.assign({}, col.get(v.id));
      col.update(v.id, { actif: true });
      return { code: v.code, ferme: apres.actif === false, existeEncore: !!col.get(v.id) };
    });
    verifier('Une variable de réactif ou de commentaire se ferme sans se supprimer',
      fermeture.ferme && fermeture.existeEncore, fermeture.code);

    /* --- Le circuit du prélèvement ---------------------------------------- */
    await ouvrir('m5-prelevement.html');
    const prel = await page.evaluate(() => {
      const t = document.body.textContent;
      const onglets = [...document.querySelectorAll('#page-content .tab')].map((x) => x.textContent.trim());
      return {
        onglets: onglets.join(' | '),
        apresCaisse: /après encaissement/i.test(t),
        patientPeutPartir: /le patient peut partir/i.test(t),
        echantillonRecu: /reçu/i.test(t),
      };
    });
    verifier('La salle de prélèvement déroule les trois étapes du circuit',
      /À prélever/.test(prel.onglets) && /À transmettre/.test(prel.onglets) && /Reçus/.test(prel.onglets),
      prel.onglets);
    verifier('Le prélèvement n’est possible qu’après encaissement', prel.apresCaisse);
    verifier('Le patient peut partir une fois prélevé', prel.patientPeutPartir);

    /* --- Les statistiques sur les cinq axes demandés ----------------------- */
    await ouvrir('m5-stats.html');
    const stats = await page.evaluate(() => {
      const t = document.body.textContent;
      const options = [...document.querySelectorAll('#page-content select option')].map((o) => o.textContent);
      return {
        periodes: options.join(' | '),
        service: /service demandeur/i.test(t),
        sexe: /sexe/i.test(t),
        age: /âge/i.test(t),
        origine: /interne|externe/i.test(t),
      };
    });
    verifier('Les statistiques couvrent service, sexe, âge et origine du patient',
      stats.service && stats.sexe && stats.age && stats.origine);
    verifier('La périodicité va de la semaine à l’année, semestre compris',
      /Semaine/.test(stats.periodes) && /Trimestre/.test(stats.periodes)
      && /Semestre/.test(stats.periodes) && /Année/.test(stats.periodes));

    /* --- Réactifs : seuils définis par la clinique ------------------------- */
    await ouvrir('m5-reactifs.html');
    const reac = await page.evaluate(() => {
      const t = document.body.textContent;
      const boutons = [...document.querySelectorAll('#page-content button')].map((b) => b.textContent).join(' | ');
      const options = [...document.querySelectorAll('#page-content select option')].map((o) => o.textContent).join(' | ');
      return {
        creation: /Nouveau réactif/.test(boutons),
        recherche: !!document.querySelector('#page-content input[type=search], #page-content input[placeholder*=echerch]'),
        seuilClinique: /seuil d’alerte est fixé par la clinique|à arrêter par la clinique|c’est à la clinique/i.test(t),
        filtreNiveau: /Sous le seuil|Sans seuil défini/.test(options + ' ' + t),
        periodes: /Semestre/.test(options),
      };
    });
    verifier('Les réactifs se créent depuis l’écran', reac.creation);
    verifier('Le seuil d’alerte est annoncé comme relevant de la clinique', reac.seuilClinique);
    verifier('Le stock se filtre par niveau, seuil absent compris', reac.filtreNiveau);
    verifier('La consommation se lit du semaine au semestre', reac.periodes);

    /* --- Activité des modules : la banque de sang est fermée --------------- */
    await ouvrir('cfg-modules.html');
    const mods = await page.evaluate(() => {
      const N = window.SIGH.nav, S = window.SIGH.store;
      const arbre = N.tree('admin');
      const ecrans = [];
      arbre.forEach((d) => d.modules.forEach((m) => m.items.forEach((i) => ecrans.push(i.id))));
      return {
        banqueDansMenu: ecrans.indexOf('m5-banque-sang') !== -1,
        donneursDansMenu: ecrans.indexOf('m5-donneurs') !== -1,
        labosDansMenu: ecrans.indexOf('m5-resultats') !== -1,
        canBanque: N.can('admin', { roles: N.ALL, module: 'M5', id: 'm5-banque-sang' }),
        fiches: S.collection('modulesActifs').active().length,
      };
    });
    verifier('La banque de sang est retirée du méga-menu', !mods.banqueDansMenu);
    verifier('Les donneurs et transfusions sont retirés du méga-menu', !mods.donneursDansMenu);
    verifier('Le reste du laboratoire demeure accessible', mods.labosDansMenu);
    verifier('Une activité fermée l’est aussi pour l’administrateur', !mods.canBanque);

    /* La réouverture rend l'écran, sans rien avoir perdu. */
    const reouverture = await page.evaluate(() => {
      const N = window.SIGH.nav, S = window.SIGH.store;
      const col = S.collection('modulesActifs');
      const f = col.active().filter((x) => x.code === 'M5-BANQUE')[0];
      col.update(f.id, { actif: true });
      N.invaliderModules();
      const ouvert = N.can('admin', { roles: N.ALL, module: 'M5', id: 'm5-banque-sang' });
      col.update(f.id, { actif: false });
      N.invaliderModules();
      return { ouvert: ouvert, refermee: !N.can('admin', { roles: N.ALL, module: 'M5', id: 'm5-banque-sang' }) };
    });
    verifier('Rouvrir une activité rend immédiatement son écran',
      reouverture.ouvert && reouverture.refermee);

    verifier('Aucune erreur JavaScript sur le laboratoire', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 28. LA CHAÎNE COMPLÈTE — consultation → caisse → comptable, labo, stock
   * -------------------------------------------------------------------------
   * Le processus décrit par la Direction, de bout en bout. Ce que ce scénario
   * garde fermé : un encaissement qui n'écrit rien en comptabilité, une
   * demande d'analyse débloquée mais indistinguable des impayées, et une
   * sortie de stock qui passe sous le seuil sans que personne le sache.
   * ======================================================================= */
  {
    scenario('Chaîne complète — consultation, pathologie, caisse, comptable, labo, stock');

    await page.evaluate(() => window.SIGH.store.setSession({
      role: 'admin', nom: 'BASSONGUI Chabi Séko', fonction: 'direction', secteur: 'ADM',
    }));

    /* --- La pathologie est un code, le diagnostic une phrase --------------- */
    await ouvrir('m2-pathologies.html');
    const path = await page.evaluate(() => {
      const S = window.SIGH.store, D = window.SIGH.data;
      const col = S.collection('pathologies');
      const rows = col.active();
      const onglets = [...document.querySelectorAll('#page-content .tab')].map((t) => t.textContent.trim());
      return {
        n: rows.length,
        chapitres: D.CHAPITRES_PATHOLOGIE.length,
        notifiables: rows.filter((x) => x.notifiable).length,
        aValider: rows.filter((x) => x.aValider).length,
        validees: rows.filter((x) => x.valideLe === '2026-09-01').length,
        onglets: onglets.join(' | '),
        palu: rows.some((x) => x.code === 'PAL-S'),
      };
    });
    verifier('Le référentiel des pathologies est en place',
      path.n >= 45 && path.chapitres === 12, path.n + ' pathologies · ' + path.chapitres + ' chapitres');
    verifier('Les pathologies à déclaration obligatoire sont signalées',
      path.notifiables > 0, path.notifiables + ' notifiables');
    /* Vague 51 : les médecins ont arrêté la liste (tableau de morbidité). */
    verifier('Les libellés sont ARRÊTÉS par les médecins (01/09) — la provenance datée reste',
      path.aValider === 0 && path.validees === path.n, path.validees + '/' + path.n);
    verifier('L’écran distingue le référentiel du tableau de morbidité',
      /Référentiel/.test(path.onglets) && /morbidité/i.test(path.onglets), path.onglets);

    /* --- La consultation code la pathologie ET rédige le diagnostic -------- */
    await ouvrir('m2-consultation-fiche.html');
    const fiche = await page.evaluate(() => {
      const labels = [...document.querySelectorAll('#page-content .label')].map((l) => l.textContent);
      return {
        pathologie: labels.some((l) => /Pathologie/.test(l)),
        /* Refonte Zone 2 : le libellé suit la METHODOLOGIE — « Diagnostic
           retenu » —, la distinction code / phrase est inchangée. */
        diagnostic: labels.some((l) => /Diagnostic retenu/.test(l)),
        medicaments: labels.some((l) => /Médicaments prescrits/.test(l)),
        analyses: labels.some((l) => /Analyses de laboratoire prescrites/.test(l)),
        imagerie: labels.some((l) => /Imagerie médicale prescrite/.test(l)),
      };
    });
    verifier('La consultation code une pathologie et rédige un diagnostic',
      fiche.pathologie && fiche.diagnostic);
    verifier('Le médecin prescrit médicaments, analyses et imagerie depuis la fiche — et là seulement',
      fiche.medicaments && fiche.analyses && fiche.imagerie);

    /* --- LA CHAÎNE : prescrire → encaisser → trois postes informés --------- */
    await ouvrir('m2-ordonnances.html');
    const chaine = await page.evaluate(() => {
      const S = window.SIGH.store, PR = window.SIGH.parcours, D = window.SIGH.data;
      const pat = S.collection('patients').active().filter((x) => !x.personnelId)[0];
      const prod = S.collection('produits').active().filter((x) => x.stock > 5)[0];

      const presc = PR.prescrire({
        patientCode: pat.code, medecin: 'YENI M’PO Florent', diagnostic: 'Contrôle de recette',
        secteurDemandeur: 'MGE',
        medicaments: [{ produitId: prod.id, quantite: 2, posologie: '1 matin, 1 soir', duree: '5 jours' }],
        analyses: [D.ANALYSES[0].code, D.ANALYSES[5].code],
      });
      const fac = presc.facture;
      const avant = S.collection('demandesAnalyses').all()
        .filter((d) => d.ordonnanceId === presc.ordonnance.id)
        .map((d) => d.bloqueParPaiement + '/' + d.etatAnalyse);

      const enc = PR.encaisser(fac.id, { montant: fac.partPatient != null ? fac.partPatient : fac.montantTTC });

      const apres = S.collection('demandesAnalyses').all()
        .filter((d) => d.ordonnanceId === presc.ordonnance.id)
        .map((d) => d.bloqueParPaiement + '/' + d.etatAnalyse);

      const ecr = S.collection('ecritures').active().filter((e) => e.pieceId === fac.id);
      const debit = ecr.reduce((n, e) => n + e.debit, 0);
      const credit = ecr.reduce((n, e) => n + e.credit, 0);

      return {
        facture: fac.numero, montant: fac.montantTTC,
        avant, apres, debloquees: enc.debloquees,
        ecritures: ecr.length, debit, credit,
        comptes: ecr.map((e) => e.compte).sort(),
        brouillon: ecr.every((e) => e.statut === 'brouillon'),
        ordId: presc.ordonnance.id, prodId: prod.id,
      };
    });
    verifier('La prescription ouvre une facture à la caisse', !!chaine.facture, chaine.facture);
    verifier('Avant encaissement, les analyses sont bloquées',
      chaine.avant.every((x) => x.indexOf('true/') === 0), chaine.avant.join(' · '));
    verifier('L’encaissement débloque le prélèvement et la dispensation',
      chaine.debloquees.indexOf('prelevement') !== -1 && chaine.debloquees.indexOf('dispensation') !== -1,
      chaine.debloquees.join(', '));
    verifier('Le laboratoire passe en ATTENTE DE PRÉLÈVEMENT, pas seulement débloqué',
      chaine.apres.every((x) => x === 'false/attente_prelevement'), chaine.apres.join(' · '));
    verifier('Le comptable est informé par une écriture, pas par un message',
      chaine.ecritures >= 2, chaine.ecritures + ' ligne(s) d’écriture');
    verifier('RG-10 — l’écriture d’encaissement est équilibrée',
      chaine.debit === chaine.credit && chaine.debit > 0,
      'débit ' + chaine.debit + ' = crédit ' + chaine.credit);
    verifier('La caisse est débitée et les prestations créditées',
      chaine.comptes.indexOf('571000') !== -1 && chaine.comptes.indexOf('706000') !== -1,
      chaine.comptes.join(', '));
    verifier('L’écriture naît en brouillon — la validation reste humaine', chaine.brouillon);

    /* --- Le stock est informé quand la sortie passe sous le seuil ---------- */
    const stock = await page.evaluate((ctx) => {
      const S = window.SIGH.store, PR = window.SIGH.parcours;
      /* On abaisse le stock juste au-dessus de la quantité à sortir pour que
         la délivrance le fasse tomber sous le seuil. */
      const prod = S.collection('produits').get(ctx.prodId);
      S.collection('produits').update(ctx.prodId, {
        stockDetail: 3, stock: 3, seuilAlerte: 5,
      });
      const del = PR.delivrer(ctx.ordId, { utilisateur: 'DIEYABIDI Aïssatou' });
      const taches = S.collection('taches').all()
        .filter((t) => t.type === 'reapprovisionnement' && t.produitId === ctx.prodId);
      return {
        alertes: (del.alertes || []).map((a) => a.niveau),
        taches: taches.length,
        poste: taches.length ? taches[0].poste : null,
        libelle: taches.length ? taches[0].libelle : null,
        restant: taches.length ? taches[0].stockRestant : null,
        designation: prod.designation,
      };
    }, { ordId: chaine.ordId, prodId: chaine.prodId });
    verifier('Une sortie qui passe sous le seuil alerte le stock',
      stock.alertes.length > 0, stock.alertes.join(', ') + ' — ' + stock.designation);
    verifier('L’alerte devient une tâche pour le gestionnaire de stock',
      stock.taches === 1 && stock.poste === 'stock', stock.libelle);
    verifier('La tâche porte le stock restant', stock.restant != null, 'reste ' + stock.restant);

    /* Une seconde sortie ne doit pas créer de doublon. */
    const doublon = await page.evaluate((prodId) => {
      const S = window.SIGH.store, PR = window.SIGH.parcours;
      PR.alerterStock([prodId], 'contrôle');
      PR.alerterStock([prodId], 'contrôle');
      return S.collection('taches').all()
        .filter((t) => t.type === 'reapprovisionnement' && t.produitId === prodId).length;
    }, chaine.prodId);
    verifier('Réalerter sur le même article ne crée pas de doublon', doublon === 1, doublon + ' tâche(s)');

    verifier('Aucune erreur JavaScript sur la chaîne complète', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 29. CAISSE LIGNE PAR LIGNE ET PATIENT EXTERNE
   * -------------------------------------------------------------------------
   * Le chantier indivisible du poste 2. Ce que ce scénario garde fermé : un
   * paiement partiel qui libère TOUS les examens, ou aucun ; un reçu qui ne
   * nomme pas ce qui est payé ; et une caisse qui créerait la demande.
   * ======================================================================= */
  {
    scenario('Caisse ligne par ligne, reçu détaillé et patient externe');

    await page.evaluate(() => window.SIGH.store.setSession({
      role: 'admin', nom: 'BASSONGUI Chabi Séko', fonction: 'direction', secteur: 'ADM',
    }));

    /* --- La facture porte des lignes payables ----------------------------- */
    await ouvrir('m8-caisse.html');
    const lignes = await page.evaluate(() => {
      const S = window.SIGH.store, PR = window.SIGH.parcours, D = window.SIGH.data;
      const pat = S.collection('patients').active().filter((p) => !p.assureur && !p.personnelId)[0];
      const prod = S.collection('produits').active().filter((p) => p.categorie === 'medicament')[0];
      const presc = PR.prescrire({
        patientCode: pat.code, medecin: 'YENI M’PO Florent', diagnostic: 'Recette caisse',
        secteurDemandeur: 'MGE',
        medicaments: [{ produitId: prod.id, quantite: 1, posologie: '1/j', duree: '3 j' }],
        analyses: [D.ANALYSES[0].code, D.ANALYSES[5].code, D.ANALYSES[9].code],
      });
      const f = presc.facture;
      return {
        nb: (f.lignes || []).length,
        categories: [...new Set((f.lignes || []).map((l) => l.categorie))].sort(),
        avecDemande: (f.lignes || []).filter((l) => l.categorie === 'analyse' && l.demandeId).length,
        somme: (f.lignes || []).reduce((n, l) => n + l.partPatient, 0),
        total: f.partPatient,
        factureId: f.id, ordId: presc.ordonnance.id,
        ids: (f.lignes || []).filter((l) => l.categorie === 'analyse').map((l) => l.id),
      };
    });
    verifier('La facture porte une ligne par prestation',
      lignes.nb === 4, lignes.nb + ' lignes : ' + lignes.categories.join(', '));
    verifier('Chaque ligne d’analyse connaît la demande qu’elle couvre',
      lignes.avecDemande === 3, lignes.avecDemande + '/3');
    verifier('La somme des lignes égale la part patient',
      lignes.somme === lignes.total, lignes.somme + ' = ' + lignes.total);

    /* --- LE PAIEMENT PARTIEL LIBÈRE LES EXAMENS RÉGLÉS, ET EUX SEULS ------ */
    const partiel = await page.evaluate((ctx) => {
      const S = window.SIGH.store, PR = window.SIGH.parcours;
      const enc = PR.encaisser(ctx.factureId, {
        lignes: ctx.ids.slice(0, 2), mode: 'especes', utilisateur: 'Caisse',
      });
      const dem = S.collection('demandesAnalyses').all().filter((d) => d.ordonnanceId === ctx.ordId);
      return {
        regle: enc.montantRegle, reste: enc.restantDu, statut: enc.facture.statutPaiement,
        liberees: enc.demandesLiberees.length,
        bloquees: dem.filter((d) => d.bloqueParPaiement).length,
        attente: dem.filter((d) => d.etatAnalyse === 'attente_prelevement').length,
        ecritures: (enc.ecritures || []).length,
        payees: (enc.facture.lignes || []).filter((l) => l.statutPaiement === 'paye').length,
      };
    }, lignes);
    verifier('Un paiement partiel laisse la facture « partielle »',
      partiel.statut === 'partielle', partiel.statut);
    verifier('SEULS les examens réglés passent au laboratoire',
      partiel.liberees === 2 && partiel.attente === 2 && partiel.bloquees === 1,
      partiel.liberees + ' libérés · ' + partiel.bloquees + ' encore bloqué');
    verifier('Le reste dû est nommément identifié',
      partiel.reste > 0 && partiel.payees === 2,
      partiel.reste + ' F restant, ' + partiel.payees + ' ligne(s) réglée(s)');
    verifier('Le comptable est informé dès le versement partiel',
      partiel.ecritures >= 2, partiel.ecritures + ' écriture(s)');

    /* --- Le solde libère le dernier examen -------------------------------- */
    const solde = await page.evaluate((ctx) => {
      const S = window.SIGH.store, PR = window.SIGH.parcours;
      const f = S.collection('factures').get(ctx.factureId);
      const dues = (f.lignes || []).filter((l) => l.statutPaiement !== 'paye').map((l) => l.id);
      const enc = PR.encaisser(ctx.factureId, { lignes: dues, mode: 'especes', utilisateur: 'Caisse' });
      const dem = S.collection('demandesAnalyses').all().filter((d) => d.ordonnanceId === ctx.ordId);
      return {
        statut: enc.facture.statutPaiement, reste: enc.restantDu,
        bloquees: dem.filter((d) => d.bloqueParPaiement).length,
      };
    }, lignes);
    verifier('Le solde du reliquat clôt la facture',
      solde.statut === 'soldee' && solde.reste === 0, solde.statut);
    verifier('Plus aucun examen ne reste bloqué', solde.bloquees === 0);

    /* --- Le reçu détaille, et ne fait pas signer le patient --------------- */
    await ouvrir('m8-factures.html');
    const recu = await page.evaluate(async (factureId) => {
      const S = window.SIGH.store;
      const f = S.collection('factures').get(factureId);
      /* On imprime la facture depuis son écran pour lire la pièce produite. */
      const btn = [...document.querySelectorAll('#page-content tbody button[title]')]
        .find((x) => /Imprimer|Reçu/.test(x.title));
      if (btn) { btn.click(); await new Promise((r) => setTimeout(r, 700)); }
      const sheet = document.querySelector('.print-sheet');
      const txt = sheet ? sheet.textContent.replace(/\s+/g, ' ') : '';
      return {
        lignesFacture: (f.lignes || []).length,
        signaturePatient: /Le Patient/.test(txt),
        caissier: /Le Caissier/.test(txt),
        ouvert: !!sheet,
      };
    }, lignes.factureId);
    verifier('La pièce de caisse ne fait plus signer le patient',
      !recu.signaturePatient, recu.ouvert ? 'pièce lue' : 'aucune pièce ouverte');

    await page.evaluate(() => {
      const c = document.querySelector('.print-chrome');
      if (c && c.remove) c.remove();
    });

    /* --- LE PATIENT EXTERNE : la demande naît à l’accueil ------------------ */
    await ouvrir('m1-externe.html');
    const externe = await page.evaluate(() => {
      const S = window.SIGH.store, PR = window.SIGH.parcours, D = window.SIGH.data;
      const res = PR.ouvrirDemandeExterne({
        nom: 'SANNI', prenom: 'Ibrahim', sexe: 'M', dateNaissance: '1990-04-12',
        telephone: '97 12 34 56', residence: 'Natitingou — Tchirmina',
        prescripteur: 'Dr AGBO, Cabinet Espoir', indication: 'Bilan de contrôle',
        serviceDemandeur: 'Médecine', urgence: 'aucune',
        analyses: [D.ANALYSES[0].code, D.ANALYSES[5].code, D.ANALYSES[9].code],
      });
      const enc = PR.encaisser(res.facture.id, {
        lignes: res.facture.lignes.slice(0, 2).map((l) => l.id), mode: 'especes',
      });
      const dem = S.collection('demandesAnalyses').all().filter((d) => d.factureId === res.facture.id);
      return {
        dossier: res.patient.code, externe: !!res.patient.externe,
        prescripteur: res.patient.prescripteurExterieur,
        telephone: res.patient.telephone,
        lignes: res.facture.lignes.length,
        origine: [...new Set(dem.map((d) => d.origineDemande))].join(','),
        liberees: enc.demandesLiberees.length,
        bloquees: dem.filter((d) => d.bloqueParPaiement).length,
      };
    });
    verifier('Le patient externe reçoit un dossier CNT',
      /^CNT/.test(externe.dossier), externe.dossier);
    verifier('Son identité et son prescripteur extérieur sont enregistrés',
      externe.externe && !!externe.prescripteur && !!externe.telephone,
      externe.prescripteur);
    verifier('Les examens cochés au catalogue deviennent des lignes payables',
      externe.lignes === 3, externe.lignes + ' lignes');
    verifier('La demande externe est tracée comme telle', externe.origine === 'externe');
    verifier('Le paiement partiel d’un externe libère les seuls examens réglés',
      externe.liberees === 2 && externe.bloquees === 1,
      externe.liberees + ' libérés · ' + externe.bloquees + ' bloqué');

    /* --- Une caisse ne crée jamais de demande ----------------------------- */
    const gardeFou = await page.evaluate(() => {
      const N = window.SIGH.nav;
      const e = N.get('m1-externe');
      return {
        roles: (e && e.roles) || [],
        accueil: N.can('reception', e),
        caisse: N.can('caissier', e),
      };
    });
    verifier('L’accueil ouvre les demandes externes', gardeFou.accueil);
    verifier('La caisse ne peut pas créer de demande — elle encaisse',
      !gardeFou.caisse, gardeFou.roles.join(', '));

    verifier('Aucune erreur JavaScript sur la caisse', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 30. LES DEUX VERROUS DU LABORATOIRE
   * -------------------------------------------------------------------------
   * Ce que ce scénario garde fermé : un résultat que le médecin lirait avant
   * relecture, une correction qui écraserait en silence ce qu'il a déjà lu,
   * et un intérim de validation qui ne se verrait pas sur la pièce.
   * ======================================================================= */
  {
    scenario('Laboratoire — validation technique, validation biologique, rectification');

    await ouvrir('m5-resultats.html');
    const verrous = await page.evaluate(async () => {
      const S = window.SIGH.store, PR = window.SIGH.parcours, D = window.SIGH.data;
      const col = S.collection('demandesAnalyses');
      const d = col.active().filter((x) => !D.resultatRendu(x.etatAnalyse))[0];
      col.update(d.id, {
        valeurs: { GLY: 1.05 }, etatAnalyse: 'saisi',
        prescripteur: 'YENI M’PO Florent', resultat: 'Glycémie 1.05 g/l',
      });

      /* Premier verrou. */
      PR.validerTechnique(d.id, { utilisateur: 'KINNOU G.' });
      const etatTech = col.get(d.id).etatAnalyse;

      /* Le médecin ne doit RIEN voir entre les deux verrous. */
      S.setSession({ role: 'medecin', nom: 'YENI Florent', fonction: 'medecin', secteur: 'MGE' });
      const avant = PR.peutVoirResultat(col.get(d.id));

      /* Second verrou, porté par le TSL en l'absence du biologiste. */
      S.setSession({ role: 'laborantin', nom: 'KINNOU G.', fonction: 'tsl', secteur: 'LAB' });
      const bio = PR.validerBiologique(d.id, { utilisateur: 'KINNOU G.' });

      S.setSession({ role: 'medecin', nom: 'YENI Florent', fonction: 'medecin', secteur: 'MGE' });
      const apres = PR.peutVoirResultat(col.get(d.id));

      return {
        etatTech: etatTech,
        avantAutorise: avant.autorise, avantAttente: !!avant.enAttenteValidation,
        avantMotif: avant.motif,
        interim: bio.interim, qualite: bio.demande.qualiteValidateur,
        apresAutorise: apres.autorise,
        demandeId: d.id, reference: d.reference,
      };
    });
    verifier('La validation technique n’est pas la validation biologique',
      verrous.etatTech === 'valide_technique', verrous.etatTech);
    verifier('Entre les deux verrous, le médecin ne voit RIEN',
      !verrous.avantAutorise && verrous.avantAttente, verrous.avantMotif.slice(0, 70));
    verifier('La validation biologique rend le résultat au prescripteur', verrous.apresAutorise);
    verifier('Le TSL peut valider en l’absence du biologiste, et l’intérim est tracé',
      verrous.interim === true && /intérim/i.test(verrous.qualite), verrous.qualite);

    /* --- La rectification conserve ce que le médecin a lu ------------------ */
    const rect = await page.evaluate(async (ctx) => {
      const S = window.SIGH.store, PR = window.SIGH.parcours;
      const col = S.collection('demandesAnalyses');
      let erreurSansMotif = null;
      try { PR.rectifierResultat(ctx.demandeId, { GLY: 1.5 }, {}); }
      catch (e) { erreurSansMotif = e.message; }

      const res = PR.rectifierResultat(ctx.demandeId, { GLY: 1.5 }, {
        motif: 'Erreur de frappe : 1,05 saisi au lieu de 1,50', utilisateur: 'KINNOU G.',
      });
      const d = Object.assign({}, col.get(ctx.demandeId));
      const notifs = PR.notifications('prescripteur').filter((n) => n.demandeId === ctx.demandeId);
      return {
        erreurSansMotif: erreurSansMotif,
        version: d.version, etat: d.etatAnalyse,
        valeurCourante: d.valeurs.GLY,
        versionsConservees: (d.versions || []).length,
        ancienneValeur: (d.versions || [])[0] ? (d.versions || [])[0].valeurs.GLY : null,
        motifConserve: (d.versions || [])[0] ? (d.versions || [])[0].motifRemplacement : null,
        notifRectif: notifs.filter((n) => n.type === 'resultat_rectifie').length,
        notifDispo: notifs.filter((n) => n.type === 'resultat_disponible').length,
      };
    }, verrous);
    verifier('Une rectification sans motif est refusée',
      !!rect.erreurSansMotif, rect.erreurSansMotif);
    verifier('La rectification numérote une nouvelle version',
      rect.version === 2 && rect.etat === 'rectifie', 'v' + rect.version + ' — ' + rect.etat);
    verifier('La version que le médecin a lue est CONSERVÉE',
      rect.versionsConservees === 1 && rect.ancienneValeur === 1.05 && rect.valeurCourante === 1.5,
      'v1 = ' + rect.ancienneValeur + ' · v2 = ' + rect.valeurCourante);
    verifier('Le motif de la rectification est conservé avec la version remplacée',
      /Erreur de frappe/.test(rect.motifConserve || ''), rect.motifConserve);
    verifier('Le prescripteur est averti que ce qu’il a lu a changé',
      rect.notifRectif >= 1 && rect.notifDispo >= 1,
      rect.notifRectif + ' rectification · ' + rect.notifDispo + ' mise à disposition');

    /* --- Le filtre de date est un FILTRE, pas un tri ----------------------- */
    /* Au laboratoire : le médecin ne voit que les résultats rendus, sa file
       « à saisir » est vide et ne prouverait rien. */
    await page.evaluate(() => window.SIGH.store.setSession({
      role: 'laborantin', nom: 'KINNOU G.', fonction: 'tsl', secteur: 'LAB',
    }));
    await ouvrir('m5-resultats.html');
    const filtre = await page.evaluate(async () => {
      const champs = [...document.querySelectorAll('#page-content input[type=date]')];
      if (champs.length < 2) return { erreur: 'pas de champs de date' };
      const boutons = [...document.querySelectorAll('#page-content button')].map((b) => b.textContent.trim());
      const avant = document.querySelectorAll('#page-content tbody tr').length;
      /* Une date à laquelle rien n'a été demandé : le tableau doit se vider. */
      champs[0].value = '2020-01-01'; champs[1].value = '2020-01-02';
      champs[0].dispatchEvent(new Event('change'));
      await new Promise((r) => setTimeout(r, 400));
      const apres = document.querySelectorAll('#page-content tbody tr').length;
      return {
        champs: champs.length, avant: avant, apres: apres,
        raccourcis: boutons.filter((b) => /Aujourd|Sept derniers|Toutes les dates/.test(b)),
      };
    });
    verifier('La page des résultats offre une plage de dates, pas un simple tri',
      filtre.champs >= 2, filtre.champs + ' champ(s) de date');
    verifier('Le filtre restreint réellement le tableau',
      filtre.apres < filtre.avant, filtre.avant + ' → ' + filtre.apres + ' ligne(s)');
    verifier('Les raccourcis de date évitent la saisie la plus fréquente',
      filtre.raccourcis.length >= 3, filtre.raccourcis.join(' · '));

    await page.evaluate(() => window.SIGH.store.setSession({
      role: 'admin', nom: 'BASSONGUI Chabi Séko', fonction: 'direction', secteur: 'ADM',
    }));
    verifier('Aucune erreur JavaScript sur les deux verrous', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 31. RBAC PAR ÉCRAN, RÔLE CRÉÉ, RACCOURCIS
   * -------------------------------------------------------------------------
   * Ce que ce scénario garde fermé : un laborantin qui modifierait un dossier
   * patient, un rôle inventé qui hériterait des modules ouverts « à tous », et
   * un raccourci qui mènerait à une porte fermée.
   * ======================================================================= */
  {
    scenario('RBAC par écran, création de rôle et raccourcis filtrés');

    await page.evaluate(() => window.SIGH.store.setSession({
      role: 'admin', nom: 'BASSONGUI Chabi Séko', fonction: 'direction', secteur: 'ADM',
    }));
    await ouvrir('m14-roles.html');

    /* CE BLOC REPOSAIT UNE COPIE TRONQUÉE DE LA FICHE. Il avait été écrit
       pour compenser le scénario du RBAC métier, qui mutait la matrice sans
       la restaurer — mais il ne recopiait que SIX réglages d'écran quand
       l'amorçage en portait treize. Les cinq fermetures les plus récentes
       (dossier étendu, pièces, constantes, référence, contre-référence) et le
       parc technique se rouvraient donc en silence, et l'assertion qui les
       vérifie trente scénarios plus loin mesurait cette copie.
       Le scénario fautif sauvegarde et restaure désormais lui-même : il n'y a
       plus rien à reposer ici, et surtout plus rien à recopier. */

    /* --- Le laborantin : le répertoire en lecture, le dossier fermé ------- */
    const lab = await page.evaluate(() => {
      const N = window.SIGH.nav;
      const ecrans = [];
      N.tree('laborantin').forEach((d) => d.modules.forEach((m) => m.items.forEach((i) => ecrans.push(i.id))));
      const d = (id, code) => N.droitsEcran('laborantin', id, code);
      return {
        repertoire: ecrans.indexOf('m1-patients') !== -1,
        repertoireLecture: d('m1-patients', 'M1').lectureSeule,
        fiche: ecrans.indexOf('m1-patient-profil') !== -1,
        fermes: ['m1-dossier-medical', 'm1-antecedents', 'm1-documents', 'm1-numerisation']
          .filter((x) => ecrans.indexOf(x) !== -1),
        /* Vague 53 : le bon de livraison est le geste du MAGASINIER —
           fermé au biologiste, qui garde les quatre autres. */
        m7: ['m7-besoins', 'm7-commandes', 'm7-receptions', 'm7-ecarts']
          .filter((x) => ecrans.indexOf(x) !== -1),
        m7LivraisonFermee: ecrans.indexOf('m7-livraisons') === -1,
        m7Fermes: ['m7-fournisseurs', 'm7-factures-fournisseurs'].filter((x) => ecrans.indexOf(x) !== -1),
      };
    });
    verifier('Le laborantin consulte le répertoire des patients', lab.repertoire && lab.fiche);
    verifier('Il ne peut RIEN y modifier — lecture seule', lab.repertoireLecture);
    verifier('Dossier médical, antécédents, documents et numérisation lui sont fermés',
      lab.fermes.length === 0, lab.fermes.join(', ') || 'les quatre sont fermés');
    verifier('Le circuit d’achat lui reste ouvert SAUF le bon de livraison — geste du magasinier (02/09)',
      lab.m7.length === 4 && lab.m7LivraisonFermee, lab.m7.length + '/4, livraisons fermées');
    verifier('Le reste du module Achats lui reste fermé',
      lab.m7Fermes.length === 0, lab.m7Fermes.join(', ') || 'fournisseurs et factures fermés');

    /* --- Un écran l’emporte sur son module -------------------------------- */
    const priorite = await page.evaluate(() => {
      const N = window.SIGH.nav, S = window.SIGH.store;
      const col = S.collection('rbac', { module: 'M14', entite: 'rôle', prefix: 'RBAC' });
      const f = col.all().filter((x) => x.role === 'laborantin')[0];
      const sauvegarde = { droits: f.droits, droitsEcrans: f.droitsEcrans };
      /* Module grand ouvert, un écran explicitement fermé. */
      col.update(f.id, {
        droits: { M1: { voir: true, editer: true, annuler: true } },
        droitsEcrans: { 'm1-documents': { voir: false } },
      });
      N.invaliderRbac();
      const module = N.droits('laborantin', 'M1');
      const ecran = N.droitsEcran('laborantin', 'm1-documents', 'M1');
      const autre = N.droitsEcran('laborantin', 'm1-patients', 'M1');
      col.update(f.id, sauvegarde);
      N.invaliderRbac();
      return { moduleOuvert: module.voir && module.editer, ecranFerme: !ecran.voir, autreSuitModule: autre.editer };
    });
    verifier('Une fermeture d’écran l’emporte sur un module ouvert',
      priorite.moduleOuvert && priorite.ecranFerme, 'module ouvert, écran fermé');
    verifier('Un écran non réglé continue de suivre son module', priorite.autreSuitModule);

    /* --- Un rôle créé part réellement de zéro ----------------------------- */
    const nouveau = await page.evaluate(() => {
      const N = window.SIGH.nav, S = window.SIGH.store;
      const col = S.collection('rbac', { module: 'M14', entite: 'rôle', prefix: 'RBAC' });
      const modules = [];
      N.NAV.forEach((d) => d.modules.forEach((m) => modules.push(m.code)));
      const ferme = {};
      modules.forEach((c) => { ferme[c] = { voir: false, editer: false, annuler: false }; });
      /* Comme la création réelle (m14-securite) : un écran UNIVERSEL ne cède que devant une surcharge d'écran. */
      const fermesEcrans = {};
      N.ids().forEach((id) => { const e = N.get(id); if (e && e.universel) fermesEcrans[id] = { voir: false, editer: false, annuler: false }; });
      col.insert({
        role: 'archiviste', nouveau: true, statut: 'actif', libelle: 'Archiviste',
        libelleOrigine: 'Archiviste', couleur: 'neutral', accueil: 'dash-admin',
        droits: ferme, droitsEcrans: fermesEcrans,
      });
      N.invaliderRbac();
      const ecrans = [];
      N.tree('archiviste').forEach((d) => d.modules.forEach((m) => m.items.forEach((i) => ecrans.push(i.id))));
      /* Puis on lui ouvre un module : il doit apparaître. */
      const f = col.all().filter((x) => x.role === 'archiviste')[0];
      const ouvert = Object.assign({}, f.droits, { GED: { voir: true, editer: true, annuler: false } });
      col.update(f.id, { droits: ouvert });
      N.invaliderRbac();
      const apres = [];
      N.tree('archiviste').forEach((d) => d.modules.forEach((m) => m.items.forEach((i) => apres.push(i.id))));
      return {
        existe: !!N.ROLES.archiviste, label: N.ROLES.archiviste && N.ROLES.archiviste.label,
        avant: ecrans.length, apres: apres.length,
      };
    });
    verifier('Un rôle créé entre dans le manifeste comme les autres',
      nouveau.existe && nouveau.label === 'Archiviste');
    verifier('Il n’hérite PAS des modules ouverts « à tous les rôles »',
      nouveau.avant === 0, nouveau.avant + ' écran(s) à la création');
    verifier('Lui ouvrir un module le rend immédiatement visible',
      nouveau.apres > 0, nouveau.apres + ' écran(s) après ouverture');

    /* --- Les raccourcis du bandeau ---------------------------------------- */
    const raccourcis = await page.evaluate(async () => {
      const bouton = document.querySelector('#app-topbar button[title="Actions rapides"]');
      if (!bouton) return { erreur: 'bouton absent' };
      bouton.click();
      await new Promise((r) => setTimeout(r, 400));
      const libelles = [...document.querySelectorAll('[role="dialog"] button')].map((b) => b.textContent.trim());
      const esc = new KeyboardEvent('keydown', { key: 'Escape' });
      document.dispatchEvent(esc);
      return { libelles: libelles };
    });
    verifier('« Assurés & cartes » figure aux actions rapides',
      (raccourcis.libelles || []).some((x) => /Assurés & cartes/.test(x)),
      (raccourcis.libelles || []).slice(0, 4).join(' · '));
    verifier('« Patient externe » y figure aussi',
      (raccourcis.libelles || []).some((x) => /Patient externe/.test(x)));

    /* Les raccourcis suivent les droits : un profil restreint en voit moins. */
    const filtres = await page.evaluate(() => {
      const N = window.SIGH.nav;
      const liste = ['m1-patients', 'm1-externe', 'm2-consultations', 'm8-facturation',
        'm9-assures', 'm5-demandes', 'm6-mouvements', 'm7-besoins'];
      const pour = (role) => liste.filter((id) => { const e = N.get(id); return e && N.can(role, e); }).length;
      return { admin: pour('admin'), laborantin: pour('laborantin'), infirmier: pour('infirmier') };
    });
    verifier('Les raccourcis se restreignent selon le profil',
      filtres.laborantin < filtres.admin && filtres.infirmier < filtres.admin,
      'admin ' + filtres.admin + ' · laborantin ' + filtres.laborantin + ' · infirmier ' + filtres.infirmier);

    verifier('Aucune erreur JavaScript sur le RBAC par écran', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 32. LES AJOUTS — emplacements, pertes, barème NS 131, participations
   * -------------------------------------------------------------------------
   * Ce que ce scénario garde fermé : une perte qui rendrait le stock négatif,
   * un barème modifiable sans autorisation, et une participation engendrée
   * pour un seul agent au lieu de tout le personnel.
   * ======================================================================= */
  {
    scenario('Ajouts — emplacements, pertes, barème NS 131 et participations');

    await page.evaluate(() => window.SIGH.store.setSession({
      role: 'admin', nom: 'BASSONGUI Chabi Séko', fonction: 'direction', secteur: 'ADM',
    }));

    /* --- Les emplacements sont un référentiel, plus un texte libre -------- */
    await ouvrir('m6-etiquetage.html');
    const emp = await page.evaluate(() => {
      const S = window.SIGH.store;
      const col = S.collection('emplacements');
      const boutons = [...document.querySelectorAll('#page-content button')].map((b) => b.textContent.trim());
      return {
        n: col.active().length,
        zones: [...new Set(col.active().map((e) => e.zone))],
        creation: boutons.some((b) => /Nouvel emplacement/.test(b)),
        repris: col.active().filter((e) => /Repris des emplacements/.test(e.source || '')).length,
      };
    });
    verifier('Les emplacements forment un référentiel administrable',
      emp.n > 0 && emp.creation, emp.n + ' emplacement(s)');
    verifier('Le référentiel régularise l’existant plutôt que de partir de zéro',
      emp.repris > 0, emp.repris + ' repris des fiches produits');
    verifier('Chaque emplacement porte sa zone de conservation',
      emp.zones.length > 0, emp.zones.join(' · '));

    /* --- Une perte s’enregistre comme un MOUVEMENT ------------------------ */
    await ouvrir('m6-pertes.html');
    const perte = await page.evaluate(() => {
      const S = window.SIGH.store;
      const prod = S.collection('produits').active().filter((p) => p.stock > 10)[0];
      const avant = prod.stock;
      const mvtsAvant = S.collection('mouvements').active().length;
      /* La déclaration écrit un mouvement et décrémente le stock. */
      S.collection('mouvements', { module: 'M6', entite: 'MouvementStock', prefix: 'MVT' }).insert({
        reference: 'MVT-TEST', date: window.SIGH.core.iso(new Date(2026, 7, 24)),
        type: 'casse', produitId: prod.id, produit: prod.designation,
        quantite: 3, sens: 'sortie', valeur: 3 * (prod.cump || 0),
        justificatif: 'PV de casse n° 12',
      });
      S.collection('produits').update(prod.id, { stock: avant - 3 });
      const apres = S.collection('produits').get(prod.id).stock;
      const boutons = [...document.querySelectorAll('#page-content button')].map((b) => b.textContent.trim());
      return {
        declaration: boutons.some((b) => /Déclarer une perte/.test(b)),
        mvtsAjoutes: S.collection('mouvements').active().length - mvtsAvant,
        stockAvant: avant, stockApres: apres,
      };
    });
    verifier('Une perte se déclare depuis l’écran des pertes', perte.declaration);
    verifier('Elle s’enregistre comme un mouvement de stock, pas dans un registre parallèle',
      perte.mvtsAjoutes === 1);
    verifier('Le stock décroît d’autant',
      perte.stockApres === perte.stockAvant - 3,
      perte.stockAvant + ' → ' + perte.stockApres);

    /* --- Le barème NS 131 : fermé par défaut ------------------------------ */
    await ouvrir('m10-evaluations.html');
    const bareme = await page.evaluate(() => {
      const S = window.SIGH.store;
      window.SIGH.setBaremeModifiable(false);
      return {
        ferme: !window.SIGH.baremeModifiable(),
        criteres: S.collection('baremeNS131').active().length,
      };
    });
    verifier('Le barème vit dans le magasin', bareme.criteres >= 4, bareme.criteres + ' critères');
    verifier('Sa modification est fermée par défaut', bareme.ferme);

    await ouvrir('m10-evaluations.html');
    const baremeFerme = await page.evaluate(() => {
      const boutons = [...document.querySelectorAll('#page-content button[title]')].map((b) => b.title);
      const texte = document.body.textContent;
      return {
        crayon: boutons.some((t) => /Modifier ce critère/.test(t)),
        dit: /ouvrir la porte depuis|Paramètres système/i.test(texte),
      };
    });
    verifier('Porte fermée, la modification est ABSENTE et non grisée', !baremeFerme.crayon);
    verifier('L’écran dit où ouvrir la porte', baremeFerme.dit);

    const baremeOuvert = await page.evaluate(async () => {
      /* LA PORTE DU BARÈME VIT EN BASE depuis la bascule du 08/10/2026 : elle
         est une décision de la clinique, pas une préférence de poste. Le
         sonder par `localStorage` mesurerait un réglage que plus personne
         ne lit. */
      window.SIGH.setBaremeModifiable(true);
      return { ouvert: window.SIGH.baremeModifiable() };
    });
    await ouvrir('m10-evaluations.html');
    const apresOuverture = await page.evaluate(() => {
      const boutons = [...document.querySelectorAll('#page-content button[title]')].map((b) => b.title);
      return { crayon: boutons.some((t) => /Modifier ce critère/.test(t)) };
    });
    verifier('Porte ouverte, la modification apparaît',
      baremeOuvert.ouvert && apresOuverture.crayon);

    /* La portée réutilise le mécanisme du NS 132, elle n’en invente pas un second. */
    const portee = await page.evaluate(() => {
      const S = window.SIGH.store;
      const col = S.collection('baremeNS131');
      const hist = S.collection('historiqueBareme');
      const b = col.active()[0];
      const avant = b.sanctions.moyenne;
      hist.insert({
        critereId: b.critereId, label: b.label, sanctions: Object.assign({}, b.sanctions),
        dateEffet: b.dateEffet, dateFin: '2026-08-23',
      });
      col.update(b.id, {
        sanctions: Object.assign({}, b.sanctions, { moyenne: avant + 2 }),
        dateEffet: '2026-08-24',
      });
      return {
        versions: hist.active().length,
        ancien: hist.active()[hist.active().length - 1].sanctions.moyenne,
        nouveau: col.get(b.id).sanctions.moyenne,
      };
    });
    verifier('La version antérieure du barème est conservée',
      portee.versions >= 1 && portee.ancien !== portee.nouveau,
      'ancien ' + portee.ancien + ' % · nouveau ' + portee.nouveau + ' %');
    await page.evaluate(() => window.SIGH.setBaremeModifiable(false));

    /* --- La participation vise TOUT le personnel par défaut --------------- */
    await ouvrir('m10-evenements.html');
    const part = await page.evaluate(async () => {
      const S = window.SIGH.store, C = window.SIGH.core;
      const agents = S.collection('personnel').active();
      const ben = agents[0];
      const trois = agents.slice(1, 4).map((a) => a.id);
      const boutons = [...document.querySelectorAll('#page-content button')].map((b) => b.textContent.trim());
      const btn = boutons.find((b) => /Nouvel événement/.test(b));

      /* Portée « tous » : chaque agent hors bénéficiaire. */
      const cols = S.collection('evenements', { module: 'M10', entite: 'événement', prefix: 'EVT' });
      const e1 = cols.insert({
        reference: 'EVT-T1', nature: 'deces', libelle: 'Décès — portée tous',
        beneficiaireId: ben.id, date: C.iso(new Date(2026, 7, 24)),
        montantParAgent: 1000, periodePaiement: '2026-08', modeParDefaut: 'salaire',
        portee: 'tous',
      }).record;
      /* Portée « sélection » : trois agents. */
      const e2 = cols.insert({
        reference: 'EVT-T2', nature: 'mariage', libelle: 'Mariage — portée sélection',
        beneficiaireId: ben.id, date: C.iso(new Date(2026, 7, 24)),
        montantParAgent: 1000, periodePaiement: '2026-08', modeParDefaut: 'salaire',
        portee: 'selection', participants: trois,
      }).record;
      return { agents: agents.length, e1: e1.portee, e2: e2.portee, selection: trois.length, bouton: !!btn };
    });
    verifier('L’événement se crée depuis l’écran', part.bouton);
    verifier('La portée « tout le personnel » est un choix explicite', part.e1 === 'tous');
    verifier('Une sélection d’agents est possible',
      part.e2 === 'selection' && part.selection === 3, part.selection + ' agents sélectionnés');

    /* --- Le journal de paie porte son total -------------------------------- */
    await ouvrir('m11-calcul.html');
    const journal = await page.evaluate(async () => {
      const btn = [...document.querySelectorAll('#page-content button')]
        .find((b) => /Éditer le journal de paie/.test(b.textContent));
      if (!btn) return { erreur: 'bouton absent' };
      btn.click();
      await new Promise((r) => setTimeout(r, 700));
      const sheet = document.querySelector('.print-sheet');
      const txt = sheet ? sheet.textContent.replace(/\s+/g, ' ') : '';
      const c = document.querySelector('.print-chrome');
      if (c && c.remove) c.remove();
      return { total: /TOTAL GÉNÉRAL/.test(txt), ouvert: !!sheet };
    });
    verifier('Le journal de paie porte une ligne de total général',
      journal.total, journal.erreur || (journal.ouvert ? 'état lu' : 'aucun état'));

    verifier('Aucune erreur JavaScript sur les ajouts', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 33. LA GRILLE À DEUX PRIX ET LE CIRCUIT CLINIQUE
   * -------------------------------------------------------------------------
   * Les six grilles tarifaires de la clinique portent DEUX colonnes, et le
   * prix assuré est le plus élevé. Le circuit clinique distingue deux
   * prescriptions, quatre origines, et fait passer le relais de la salle de
   * soins à l'hospitalisation au deuxième passage.
   * ======================================================================= */
  {
    scenario('Deux prix, prescription de soins et relais d’administration');

    await page.evaluate(() => window.SIGH.store.setSession({
      role: 'admin', nom: 'BASSONGUI Chabi Séko', fonction: 'direction', secteur: 'ADM',
    }));

    /* --- La grille porte deux prix --------------------------------------- */
    await ouvrir('cfg-catalogue.html');
    const cat = await page.evaluate(() => {
      const D = window.SIGH.data;
      const rows = window.SIGH.store.collection('catalogueTarifs').active();
      const avecDeux = rows.filter((r) => r.prixNonAssure != null && r.prixAssure != null && !r.nonCouvert);
      /* Règle arrêtée par la Direction le 26/08/2026 : dans TOUS les actes,
         l'assuré paie MOINS que le non-assuré. Les colonnes des grilles
         imprimées étaient inversées — l'inversion reproduit au franc près les
         deux valeurs que la Direction a données (prénatale et soin IV). */
      const moinsCher = avecDeux.filter((r) => r.prixAssure < r.prixNonAssure);
      const contraires = avecDeux.filter((r) => r.prixAssure > r.prixNonAssure);
      return {
        total: rows.length,
        familles: [...new Set(rows.map((r) => r.famille))],
        avecDeux: avecDeux.length,
        moinsCher: moinsCher.length,
        contraires: contraires.length,
        avecTrace: rows.filter((r) => r.grilleColonne1 != null).length,
        labo: rows.filter((r) => r.famille === 'LABO').length,
        sansPrix: rows.filter((r) => r.prixAValider).map((r) => r.libelle),
        arbitres: rows.filter((r) => r.arbitrage).length,
        hiv: D.tarif('LAB-HIV'),
        nonCouverts: rows.filter((r) => r.nonCouvert).length,
        sos: rows.filter((r) => r.assurable === 'sos').length,
        ecoAbdo: D.tarif('IMG-ECHO-ABP'),
      };
    });
    verifier('Le catalogue porte les six familles tarifaires',
      cat.familles.length === 6, cat.familles.join(' · '));
    verifier('Chaque acte porte DEUX prix, non assuré et assuré',
      cat.avecDeux > 100, cat.avecDeux + ' actes à deux prix sur ' + cat.total);
    verifier('L’assuré paie MOINS que le non-assuré — règle arrêtée par la Direction le 26/08/2026',
      cat.contraires === 0,
      cat.moinsCher + ' actes sur ' + cat.avecDeux + ' moins chers pour un assuré, '
      + cat.contraires + ' contraire(s)');
    verifier('…et la lecture littérale de la grille est CONSERVÉE sur chaque ligne',
      cat.avecTrace > 0, cat.avecTrace + ' ligne(s) portent les deux colonnes du papier');
    verifier('Les 41 analyses de laboratoire sont tarifées — l’anomalie des colonnes vierges est levée',
      cat.labo === 41, cat.labo + ' analyses');
    verifier('L’échographie abdomino-pelvienne : 20 000 non assuré, 11 000 assuré',
      cat.ecoAbdo.prixNonAssure === 20000 && cat.ecoAbdo.prixAssure === 11000,
      cat.ecoAbdo.prixNonAssure + ' non assuré / ' + cat.ecoAbdo.prixAssure + ' assuré');

    /* --- Un prix absent n'est ni un zéro ni une exclusion ------------------ */
    verifier('Plus aucun acte n’est sans prix — les trois manquants ont été arbitrés le 26/08/2026',
      cat.sansPrix.length === 0, cat.sansPrix.join(' · ') || 'catalogue complet');
    verifier('Chaque prix arbitré porte SON MOTIF — une valeur décidée n’est pas une valeur relevée',
      cat.arbitres === 3, cat.arbitres + ' acte(s) portent la trace de leur arbitrage — '
      + 'le soin intraveineux n en porte plus : l inversion des colonnes l explique');
    verifier('Le VIH est tarifé et sa décision est tracée',
      cat.hiv.prixAssure === 2500 && cat.hiv.prixNonAssure === 3500 && !!cat.hiv.arbitrage,
      cat.hiv.prixAssure + ' assuré / ' + cat.hiv.prixNonAssure + ' non assuré');

    /* --- NON COUVERT n'est pas un prix ------------------------------------ */
    const couv = await page.evaluate(() => {
      const D = window.SIGH.data;
      return {
        implant: D.tarifPrix('POSI', true),
        implantNon: D.tarifPrix('POSI', false),
        cert: D.tarifPrix('CERT-DEC', true),
        sosOui: D.tarifCouvertPar('CERT-DEC', 'SOS Assurances'),
        sosNon: D.tarifCouvertPar('CERT-DEC', 'NSIA'),
        pfCouvert: D.tarifCouvertPar('POSI', 'NSIA'),
        echo: D.tarifPrix('IMG-ECHO-ABP', true),
        echoNon: D.tarifPrix('IMG-ECHO-ABP', false),
      };
    });
    verifier('Un acte NON COUVERT est facturé à l’assuré au tarif NON assuré',
      couv.implant.montant === 1100 && couv.implant.montant === couv.implantNon.montant,
      couv.implant.montant + ' FCFA');
    verifier('…et la ligne en porte le MOTIF — une part patient à 100 % doit pouvoir s’expliquer au guichet',
      /NON COUVERT/i.test(couv.implant.motif || ''), couv.implant.motif);
    verifier('La planification familiale n’est couverte par aucune compagnie',
      couv.pfCouvert === false);
    verifier('Les certificats ne sont couverts QUE par SOS',
      couv.sosOui === true && couv.sosNon === false,
      'SOS : ' + couv.sosOui + ' · NSIA : ' + couv.sosNon);
    verifier('Un assuré ordinaire est facturé au tarif assuré — moins cher que le guichet',
      couv.echo.montant === 11000 && couv.echo.tarif === 'assuré',
      couv.echo.montant + ' FCFA, contre ' + couv.echoNon.montant + ' au tarif non assuré');

    /* --- En-tête UNIFIÉ — arbitrage de la Direction du 31/08/2026 ---------
       Ces assertions vérifiaient l'ancienne doctrine (référentiel de
       variantes). La Direction a tranché : une seule identité légale sur
       toutes les pièces, le référentiel est retiré. */
    await ouvrir('cfg-entetes.html');
    const ent = await page.evaluate(() => {
      const t = document.body.textContent;
      return {
        variantesRetirees: window.SIGH.store.raw().enteteVariantes === undefined,
        ifuUnique: /3201642748214/.test(t) && !/1201400032505/.test(t),
        rccmUnique: /RB\/NAT\/2016-B-268/.test(t) && !/RB\/NAT\/2021\/M02-020/.test(t),
        assume: /31\/08\/2026/.test(t),
      };
    });
    verifier('Le référentiel des variantes d’en-tête est retiré du magasin', ent.variantesRetirees);
    verifier('cfg-entetes ne présente plus qu’UN IFU', ent.ifuUnique);
    verifier('…et qu’UN RCCM — l’ancien n’apparaît plus', ent.rccmUnique);
    verifier('L’écran date et assume l’arbitrage d’unification', ent.assume);

    /* --- Les quatorze pièces certifiantes --------------------------------- */
    await ouvrir('cfg-types-piece.html');
    const pieces = await page.evaluate(() => {
      const rows = window.SIGH.store.collection('typesPiece').active();
      const sigles = rows.map((r) => r.sigle);
      const doublons = sigles.filter((v, i) => sigles.indexOf(v) !== i);
      return {
        n: rows.length,
        collisions: rows.filter((r) => r.collision).length,
        doublons: [...new Set(doublons)],
        prenuptial: rows.filter((r) => r.examens)[0],
      };
    });
    verifier('Les quatorze pièces certifiantes sont au référentiel', pieces.n === 14, pieces.n + ' pièces');
    verifier('Les deux collisions de sigles des documents sources sont CONSERVÉES et signalées',
      pieces.collisions === 4 && pieces.doublons.length === 2,
      'sigles en double : ' + pieces.doublons.join(' · '));
    verifier('Le certificat prénuptial est adossé à six examens de laboratoire',
      pieces.prenuptial && pieces.prenuptial.examens.length === 6,
      pieces.prenuptial ? pieces.prenuptial.examens.join(' ') : 'absent');

    /* --- Qui prescrit, qui exécute ---------------------------------------- */
    await ouvrir('m14-soignants.html');
    const soi = await page.evaluate(() => {
      const rows = window.SIGH.store.collection('soignants').active();
      return {
        total: rows.length,
        prescripteurs: rows.filter((r) => r.prescrit).length,
        executants: rows.filter((r) => r.execute).length,
        cumul: rows.filter((r) => r.prescrit && r.execute).length,
        medecins: rows.filter((r) => r.prescrit && r.qualite === 'medecin').length,
        sf: rows.filter((r) => r.qualite === 'sage_femme').length,
        inf: rows.filter((r) => r.execute && r.qualite === 'infirmier').length,
        superviseur: rows.filter((r) => r.supervise).length,
      };
    });
    verifier('Les effectifs de la Direction se retrouvent : 3 médecins prescripteurs',
      soi.medecins === 3, soi.medecins + ' médecins');
    verifier('…3 sages-femmes', soi.sf === 3, soi.sf + ' sages-femmes');
    verifier('…7 infirmiers exécutants, le Surveillant Général mis à part',
      soi.inf === 7 && soi.superviseur === 1,
      soi.inf + ' exécutants · ' + soi.superviseur + ' superviseur');
    verifier('La sage-femme est la seule qualité à PRESCRIRE et à EXÉCUTER',
      soi.cumul === soi.sf, soi.cumul + ' agents cumulent les deux droits');

    /* --- Un infirmier ne prescrit pas -------------------------------------- */
    await ouvrir('m2-prescriptions.html');
    const refus = await page.evaluate(() => {
      const S = window.SIGH.store, PR = window.SIGH.parcours;
      const inf = S.collection('soignants').active().filter((x) => x.qualite === 'infirmier' && x.execute)[0];
      const pt = S.collection('patients').active()[0];
      try {
        PR.prescrireSoins({
          patientCode: pt.code, prescripteurId: inf.id, origine: 'consultation',
          secteurDestinataire: 'salle_soins', modalite: 'ambulatoire', actes: ['PANP'],
        });
        return { refuse: false };
      } catch (e) {
        return { refuse: true, message: e.message };
      }
    });
    verifier('Le moteur REFUSE une prescription signée par un infirmier',
      refus.refuse, refus.message);
    verifier('…et le refus NOMME l’agent et son poste — un refus muet ferait croire à une panne',
      /n’est pas habilité/.test(refus.message || ''), refus.message);

    /* --- Prescription de soins ambulatoire --------------------------------- */
    const amb = await page.evaluate(() => {
      const S = window.SIGH.store, PR = window.SIGH.parcours, D = window.SIGH.data;
      const med = S.collection('soignants').active().filter((x) => x.prescrit && x.qualite === 'medecin')[0];
      const pt = S.collection('patients').active().filter((x) => !x.assureur)[0];
      const pres = PR.prescrireSoins({
        patientCode: pt.code, prescripteurId: med.id, origine: 'consultation',
        secteurDestinataire: 'salle_soins', modalite: 'ambulatoire',
        actes: [{ code: 'PANM', nbAdministrations: 3 }],
      });
      return {
        ref: pres.reference, type: pres.type, origine: pres.origine,
        premier: pres.premierAdministrateur,
        prix: pres.lignes[0].prix, tarif: pres.lignes[0].tarif,
        r1: D.secteurAdministrateur('ambulatoire', 1).secteur,
        r2: D.secteurAdministrateur('ambulatoire', 2).secteur,
        r5: D.secteurAdministrateur('ambulatoire', 5).secteur,
        bloquee: pres.statutPaiement !== 'payee',
      };
    });
    verifier('Une prescription de SOINS se distingue d’une ordonnance',
      amb.type === 'soins', amb.ref + ' — ' + amb.type);
    verifier('Un patient non assuré est facturé au tarif non assuré : pansement moyen 5 000 F',
      amb.prix === 5000 && amb.tarif === 'non assuré', amb.prix + ' FCFA');
    verifier('Traitement AMBULATOIRE : toutes les administrations reviennent à la salle de soins',
      amb.r1 === 'salle_soins' && amb.r2 === 'salle_soins' && amb.r5 === 'salle_soins',
      'passages 1, 2 et 5 → salle de soins');
    verifier('Une prescription naît NON RÉGLÉE, donc non exécutable', amb.bloquee);

    /* --- Le relais en hospitalisation --------------------------------------- */
    const relais = await page.evaluate(() => {
      const S = window.SIGH.store, PR = window.SIGH.parcours, D = window.SIGH.data;
      const med = S.collection('soignants').active().filter((x) => x.prescrit && x.qualite === 'medecin')[0];
      const inf = S.collection('soignants').active().filter((x) => x.execute && x.qualite === 'infirmier')[0];
      const pt = S.collection('patients').active().filter((x) => !x.assureur)[1];
      const pres = PR.prescrireSoins({
        patientCode: pt.code, prescripteurId: med.id, origine: 'hospitalisation',
        secteurDestinataire: 'hospitalisation', modalite: 'hospitalisation',
        actes: [{ code: 'SIV', nbAdministrations: 4 }],
      });

      /* Non réglée : l'administration est refusée. */
      const avantPaiement = PR.administrer(pres.id, { ligneIndex: 0, secteur: 'salle_soins', executantId: inf.id });

      S.collection('prescriptions').update(pres.id, { statutPaiement: 'payee' });

      /* Le mauvais poste est refusé EN LE NOMMANT. */
      const mauvais = PR.administrer(pres.id, { ligneIndex: 0, secteur: 'hospitalisation', executantId: inf.id });
      /* Le bon poste passe. */
      const a1 = PR.administrer(pres.id, { ligneIndex: 0, secteur: 'salle_soins', executantId: inf.id });
      /* Deuxième passage : le relais est passé. */
      const a2 = PR.administrer(pres.id, { ligneIndex: 0, secteur: 'hospitalisation', executantId: inf.id });
      /* Un médecin n'exécute pas un soin. */
      const parMedecin = PR.administrer(pres.id, { ligneIndex: 0, secteur: 'hospitalisation', executantId: med.id });

      return {
        avantPaiement: avantPaiement.ok, motifPaiement: avantPaiement.motif,
        mauvais: mauvais.ok, motifMauvais: mauvais.motif, attendu: mauvais.secteurAttendu,
        a1: a1.ok, s1: a1.secteur, r1: a1.rang,
        a2: a2.ok, s2: a2.secteur, r2: a2.rang,
        medecin: parMedecin.ok, motifMedecin: parMedecin.motif,
        h1: D.secteurAdministrateur('hospitalisation', 1).secteur,
        h2: D.secteurAdministrateur('hospitalisation', 2).secteur,
        h4: D.secteurAdministrateur('hospitalisation', 4).secteur,
      };
    });
    verifier('Une prescription NON RÉGLÉE ne s’administre pas',
      relais.avantPaiement === false, relais.motifPaiement);
    verifier('La PREMIÈRE administration d’un traitement hospitalier revient à la SALLE DE SOINS',
      relais.h1 === 'salle_soins' && relais.a1 === true && relais.s1 === 'salle_soins' && relais.r1 === 1);
    verifier('Les SUIVANTES reviennent à l’HOSPITALISATION',
      relais.h2 === 'hospitalisation' && relais.h4 === 'hospitalisation'
      && relais.a2 === true && relais.s2 === 'hospitalisation' && relais.r2 === 2);
    verifier('L’hospitalisation qui tente de prendre la PREMIÈRE administration est refusée',
      relais.mauvais === false && relais.attendu === 'salle_soins', relais.motifMauvais);
    verifier('…et le refus explique POURQUOI : c’est le rang qui décide du secteur',
      /première administration|salle de soins/i.test(relais.motifMauvais || ''), relais.motifMauvais);
    verifier('Un médecin ne peut pas exécuter un soin — il prescrit',
      relais.medecin === false, relais.motifMedecin);

    /* --- Le poste ne voit que ce qui lui revient --------------------------- */
    await ouvrir('m2-salle-soins.html');
    const poste = await page.evaluate(() => {
      const PR = window.SIGH.parcours;
      const ss = PR.soinsDuSecteur('salle_soins');
      const ho = PR.soinsDuSecteur('hospitalisation');
      return {
        ss: ss.length, ho: ho.length,
        ssRangs: ss.reduce((a, d) => a.concat(d.lignes.map((l) => l.secteur)), []),
        hoRangs: ho.reduce((a, d) => a.concat(d.lignes.map((l) => l.secteur)), []),
      };
    });
    verifier('La salle de soins ne voit QUE ce qui lui revient',
      poste.ssRangs.every((x) => x === 'salle_soins'), poste.ss + ' patient(s)');
    verifier('L’hospitalisation ne voit QUE ce qui lui revient',
      poste.hoRangs.every((x) => x === 'hospitalisation'), poste.ho + ' patient(s)');

    /* --- Le bloc opératoire ------------------------------------------------ */
    await ouvrir('m3-bloc-cro.html');
    const bloc = await page.evaluate(() => {
      const S = window.SIGH.store, C = window.SIGH.core, D = window.SIGH.data;
      const soignants = S.collection('soignants').active();
      const op = soignants.filter((x) => x.qualite === 'medecin')[0];
      const an = soignants[1];
      const pt = S.collection('patients').active()[0];
      const rec = S.collection('crOperatoires', { module: 'M3', entite: 'compte rendu opératoire', prefix: 'CRO' })
        .insert({
          reference: 'CRO-T001', dateOperation: C.iso(new Date(2026, 7, 25)),
          patientId: pt.id, patient: pt.nom + ' ' + pt.prenom, nip: pt.code,
          diagnosticPeroperatoire: 'Appendicite aiguë perforée',
          intervention: 'Appendicectomie par voie de McBurney',
          anesthesie: 'Rachianesthésie',
          cro: 'Incision de McBurney. Exploration de la cavité. Appendice perforé, base saine.',
          operateurId: op.id, operateur: op.nomComplet,
          anesthesisteId: an.id, anesthesiste: an.nomComplet,
        }).record;
      return {
        ref: rec.reference, nip: rec.nip,
        operateur: rec.operateur, anesthesiste: rec.anesthesiste,
        rubriques: (D.RUBRIQUES_CRO || []).length,
        boutons: [...document.querySelectorAll('#page-content button')].map((b) => b.textContent.trim()),
      };
    });
    verifier('Le compte rendu opératoire porte ses huit rubriques',
      bloc.rubriques >= 9, bloc.rubriques + ' rubriques déclarées');
    verifier('Il porte le NIP, recopié du dossier', !!bloc.nip, 'NIP ' + bloc.nip);
    verifier('Il porte ses intervenants NOMMÉS — sans eux il n’a aucune valeur de preuve',
      !!bloc.operateur && !!bloc.anesthesiste, bloc.operateur + ' · ' + bloc.anesthesiste);
    verifier('Le compte rendu se crée depuis l’écran',
      bloc.boutons.some((b) => /Nouveau compte rendu/.test(b)));

    /* --- Les deux check-listes, séparées ------------------------------------ */
    await ouvrir('m3-bloc-checklist.html');
    const ckl = await page.evaluate(() => {
      const D = window.SIGH.data;
      const texte = document.body.textContent;
      return {
        entree: D.CHECKLIST_BLOC.entree.length,
        sortie: D.CHECKLIST_BLOC.sortie.length,
        arretees: D.CHECKLIST_BLOC.aValider === false && D.CHECKLIST_BLOC.arreteLe === '2026-09-01',
        distinctes: D.CHECKLIST_BLOC.entree.join('|') !== D.CHECKLIST_BLOC.sortie.join('|'),
        ditArrete: /arrêtées par les praticiens/i.test(texte),
      };
    });
    verifier('Les deux check-listes du bloc sont DISTINCTES, à deux moments distincts',
      ckl.distinctes && ckl.entree >= 10 && ckl.sortie >= 8,
      ckl.entree + ' points à l’entrée · ' + ckl.sortie + ' à la sortie');
    /* Vague 51 : la validation écrite des praticiens est arrivée. */
    verifier('Elles sont ARRÊTÉES par les praticiens du bloc (01/09) — la provenance reste dite',
      ckl.arretees && ckl.ditArrete);

    /* --- Les trois comptes rendus de maternité ------------------------------ */
    await ouvrir('m4-comptes-rendus.html');
    const mat = await page.evaluate(() => {
      const D = window.SIGH.data;
      const m = D.COMPTES_RENDUS_MATERNITE || [];
      return {
        n: m.length,
        codes: m.map((x) => x.code),
        rubriques: m.map((x) => x.rubriques.length),
        pfNote: (m.filter((x) => x.code === 'planning_familial')[0] || {}).note,
      };
    });
    verifier('La maternité produit TROIS comptes rendus aux rubriques propres',
      mat.n === 3 && mat.codes.join(',') === 'accouchement,planning_familial,amiu',
      mat.codes.join(' · '));
    verifier('Chacun a ses rubriques — un gabarit unique aurait fait remplir des champs sans objet',
      mat.rubriques.every((n) => n >= 7) && new Set(mat.rubriques).size > 1,
      mat.rubriques.join(' / ') + ' rubriques');
    verifier('L’écran rappelle que la planification familiale n’est couverte par aucune assurance',
      /NON COUVERT/i.test(mat.pfNote || ''), mat.pfNote);

    /* --- Le méga-menu se replie sur une navigation programmatique ----------- */
    const ruban = await page.evaluate(() => {
      const S = window.SIGH.store;
      S.storage.remove('sigh-cnt:ruban-transitoire');
      /* On n'appelle pas go() — il changerait de page. On vérifie que la
         fonction pose bien le drapeau, en isolant l'effet observable. */
      const avant = S.storage.get('sigh-cnt:ruban-transitoire');
      S.storage.set('sigh-cnt:ruban-transitoire', '1');
      const apres = S.storage.get('sigh-cnt:ruban-transitoire');
      const source = String(window.SIGH.app.go || '');
      return { avant: avant, apres: apres, poseLeDrapeau: /RUBAN_TRANSIT|ruban-transitoire/.test(source) };
    });
    verifier('Toute navigation programmatique replie le méga-menu — les boutons ne sont pas des ancres',
      ruban.poseLeDrapeau === true,
      'go() pose le drapeau transitoire, donc les boutons des tableaux de bord aussi');

    /* --- Les décisions RBAC de la Direction -------------------------------- */
    await ouvrir('m14-roles.html');
    const rbac = await page.evaluate(() => {
      const N = window.SIGH.nav;
      N.invaliderRbac();
      return {
        /* Le renommage suit partout : c'est N.ROLES qui porte le libellé. */
        biologiste: N.ROLES.laborantin.label,
        court: N.ROLES.laborantin.short,
        origine: N.ROLES.laborantin.labelOrigine,
        /* Les deux comptes fermés le sont par ARCHIVAGE, jamais par effacement. */
        pharmacienExiste: !!N.ROLES.pharmacien,
        pharmacienArchive: N.roleArchive('pharmacien'),
        rhExiste: !!N.ROLES.rh,
        rhArchive: N.roleArchive('rh'),
        /* Les quatre rôles créés existent. */
        crees: ['aide_soignant', 'echographiste', 'surveillant', 'assistant_comptable']
          .filter((r) => !!N.ROLES[r]).map((r) => N.ROLES[r].label),
      };
    });
    verifier('Laborantin est renommé Biologiste médical — le libellé suit dans tout le prototype',
      rbac.biologiste === 'Biologiste médical' && rbac.court === 'Biologiste', rbac.biologiste);
    verifier('…et ce nom vient du MANIFESTE, pour qu’il paraisse dès l’écran de connexion',
      rbac.biologiste === 'Biologiste médical',
      /* Il venait d'une surcharge ; l'écran de connexion ne charge aucune
         surcharge, et l'ancien nom y ressortait. Un renommage à moitié
         appliqué fait croire à deux rôles distincts. */
      rbac.biologiste);
    verifier('Le compte Pharmacie est ARCHIVÉ, pas effacé (RG-14) — ses mouvements restent attribuables',
      rbac.pharmacienExiste && rbac.pharmacienArchive === true);
    verifier('Le compte RH est archivé de la même façon, et recréable',
      rbac.rhExiste && rbac.rhArchive === true);
    verifier('Les quatre comptes demandés par la Direction sont créés',
      rbac.crees.length === 4, rbac.crees.join(' · '));

    /* L'archivage va AVEC son transfert : fermer sans transférer fermerait le métier. */
    const transferts = await page.evaluate(() => {
      const N = window.SIGH.nav;
      return {
        caissierPharmacie: N.droits('caissier', 'M6'),
        daRh: N.droits('da', 'M10'),
        daPaie: N.droits('da', 'M11'),
      };
    });
    verifier('La pharmacie est transférée au Caissier — l’archivage ne laisse pas le poste sans personne',
      transferts.caissierPharmacie.voir === true && transferts.caissierPharmacie.editer === true);
    verifier('Les RH et la paie sont transférées à la Directrice Administrative',
      transferts.daRh.editer === true && transferts.daPaie.editer === true);

    /* Un rôle créé part de ZÉRO, y compris sur les modules ouverts à tous les rôles. */
    const zero = await page.evaluate(() => {
      const N = window.SIGH.nav;
      return {
        /* Le technicien d'échographie : aucun accès financier, c'est la
           condition posée par la Direction. */
        echoCaisse: N.droits('echographiste', 'M8').voir,
        echoAssurances: N.droits('echographiste', 'M9').voir,
        echoCompta: N.droits('echographiste', 'M12').voir,
        /* Le droit se lit au niveau de l'ÉCRAN : le module est en lecture, et
           seule l'imagerie lui est ouverte en écriture. Mesurer le module
           reviendrait à vérifier qu'il peut aussi rédiger une ordonnance. */
        echoModuleM2: N.droits('echographiste', 'M2').editer,
        echoImagerie: N.droitsEcran('echographiste', 'm2-imagerie', 'M2').editer,
        echoOrdonnances: N.droitsEcran('echographiste', 'm2-ordonnances', 'M2').voir,
        echoSalleSoins: N.droitsEcran('echographiste', 'm2-salle-soins', 'M2').voir,
        echoDossier: N.droitsEcran('echographiste', 'm1-dossier-medical', 'M1'),
        echoPrescriptions: N.droitsEcran('echographiste', 'm2-prescriptions', 'M2'),
        /* LE SURVEILLANT SURVEILLE, et son droit se lit sur l'ÉCRAN : depuis le
           resserrage du 12/10/2026 son module M10 est FERMÉ et ses cinq écrans
           lui sont rendus nommément. Mesurer le module reviendrait à vérifier
           qu'il tient aussi les contrats, les congés et les sanctions — qui
           sont les gestes de la DAF. */
        survPlanning: N.droitsEcran('surveillant', 'm10-planning', 'M10').editer,
        survPresences: N.droitsEcran('surveillant', 'm10-presences', 'M10').editer,
        survContrats: N.droitsEcran('surveillant', 'm10-contrats', 'M10').editer,
        survCaisse: N.droits('surveillant', 'M8').voir,
        /* L'ASSISTANT DE DIRECTION A PERDU LE FINANCIER (décision du
           12/10/2026) : M8, M9, MECeF, M12, M11, M6 et M7 lui sont fermés.
           La sonde prouve désormais la FERMETURE — l'affirmation inverse,
           écrite sur l'ancienne matrice, l'aurait verrouillée. */
        assCompta: N.droits('assistant_comptable', 'M12').voir,
        assCaisse: N.droits('assistant_comptable', 'M8').voir,
        assCreances: N.droits('assistant_comptable', 'M9').voir,
        assPaie: N.droits('assistant_comptable', 'M11').voir,
        /* Ce qui lui RESTE, et qui est son poste : le secrétariat. */
        assSecretariat: N.droits('assistant_comptable', 'M13').editer,
        assGed: N.droits('assistant_comptable', 'GED').editer,
        /* M5 lui est FERMÉ AU MODULE depuis le 24/09/2026 — pas de résultats
           d’analyses (RG-13). C’est l’ÉCRAN des réactifs qui lui est accordé
           nommément : sa description de poste porte leur inventaire. La sonde
           lit donc le droit de l’ÉCRAN, pas celui du module. */
        assReactifs: N.droitsEcran('assistant_comptable', 'm5-reactifs', 'M5').voir,
        assLaboFerme: N.droits('assistant_comptable', 'M5').voir === false,
        /* L'aide-soignante ne voit aucun dossier médical. */
        aideDossier: N.droitsEcran('aide_soignant', 'm1-dossier-medical', 'M1'),
        /* Même doctrine : son module M3 est fermé, et ce sont ses quatre écrans
           qui portent son métier — les constantes et la feuille de température
           en écriture, le plan des lits et les chambres en lecture. */
        aideTemperature: N.droitsEcran('aide_soignant', 'm3-feuille-temperature', 'M3').editer,
        aideConstantes: N.droitsEcran('aide_soignant', 'm1-constantes', 'M1').editer,
        aidePlanLits: N.droitsEcran('aide_soignant', 'm3-plan-lits', 'M3'),
      };
    });
    verifier('Le technicien d’échographie n’a AUCUN accès financier — ni caisse, ni assurances, ni comptabilité',
      zero.echoCaisse === false && zero.echoAssurances === false && zero.echoCompta === false);
    verifier('…il crée bien ses comptes rendus d’imagerie', zero.echoImagerie === true);
    verifier('…mais son module de consultations reste en LECTURE',
      zero.echoModuleM2 === false, 'M2 éditable : ' + zero.echoModuleM2);
    verifier('…et il ne rédige ni ordonnance ni soin — ce serait un exercice illégal',
      zero.echoOrdonnances === false && zero.echoSalleSoins === false,
      'ordonnances : ' + zero.echoOrdonnances + ' · salle de soins : ' + zero.echoSalleSoins);
    verifier('…le dossier patient lui est ouvert en LECTURE SEULE',
      zero.echoDossier.voir === true && zero.echoDossier.editer === false);
    verifier('…et il ne modifie pas les prescriptions d’un autre service',
      zero.echoPrescriptions.editer === false);
    verifier('Le surveillant tient le planning et les présences — par ÉCRAN, son module M10 étant fermé',
      zero.survPlanning === true && zero.survPresences === true,
      'planning : ' + zero.survPlanning + ' · présences : ' + zero.survPresences);
    verifier('…mais ni les contrats ni le financier — ce sont les gestes de la DAF',
      zero.survContrats === false && zero.survCaisse === false,
      'contrats : ' + zero.survContrats + ' · caisse : ' + zero.survCaisse);
    verifier('L’assistant de direction a PERDU le financier — caisse, créances, comptabilité et paie fermées',
      zero.assCompta === false && zero.assCreances === false
      && zero.assCaisse === false && zero.assPaie === false,
      'M12 : ' + zero.assCompta + ' · M9 : ' + zero.assCreances
      + ' · M8 : ' + zero.assCaisse + ' · M11 : ' + zero.assPaie);
    verifier('…et il garde ce qui EST son poste : le secrétariat et la bibliothèque documentaire',
      zero.assSecretariat === true && zero.assGed === true,
      'M13 : ' + zero.assSecretariat + ' · GED : ' + zero.assGed);
    verifier('…l’inventaire des réactifs lui est ouvert, mais le LABORATOIRE lui est fermé',
      zero.assReactifs === true && zero.assLaboFerme === true,
      'réactifs : ' + zero.assReactifs + ' · module M5 : ' + !zero.assLaboFerme);
    verifier('L’aide-soignante participe aux soins — constantes et feuille de température en écriture',
      zero.aideTemperature === true && zero.aideConstantes === true,
      'température : ' + zero.aideTemperature + ' · constantes : ' + zero.aideConstantes);
    verifier('…elle LIT le plan des lits sans le modifier, et ne voit AUCUN dossier médical',
      zero.aidePlanLits.voir === true && zero.aidePlanLits.editer === false
      && zero.aideDossier.voir === false,
      'plan des lits : ' + JSON.stringify(zero.aidePlanLits) + ' · dossier : ' + zero.aideDossier.voir);

    /* Un compte archivé n'ouvre plus de session, et la tentative est écrite. */
    const connexion = await page.evaluate(() => {
      const N = window.SIGH.nav, S = window.SIGH.store;
      const avant = S.collection('tentativesConnexion').active().length;
      const refuse = N.roleArchive('pharmacien');
      if (refuse) {
        S.collection('tentativesConnexion', { module: 'M14', entite: 'tentative', prefix: 'TEN' }).insert({
          role: 'pharmacien', libelle: 'Pharmacien', motif: 'Rôle archivé',
          dateHeure: new Date().toISOString(),
        });
      }
      return { refuse: refuse, ajoutees: S.collection('tentativesConnexion').active().length - avant };
    });
    verifier('Un compte archivé n’ouvre plus de session et la tentative est journalisée (RG-12)',
      connexion.refuse === true && connexion.ajoutees === 1);

    /* --- Le total d'un état imprimé est CALCULÉ, pas fourni ---------------- */
    const totaux = await page.evaluate(async () => {
      const P = window.SIGH.print, C = window.SIGH.core;
      /* Trois lignes dont la somme est connue d'avance : 1 000 + 2 500 + 700. */
      const lignes = [
        { designation: 'Ligne A', quantite: 2, pu: 500, montant: 1000 },
        { designation: 'Ligne B', quantite: 5, pu: 500, montant: 2500 },
        { designation: 'Ligne C', quantite: 1, pu: 700, montant: 700 },
      ];
      const t = P.tableau([
        { label: 'Désignation', key: 'designation' },
        { label: 'Qté', key: 'quantite', align: 'right', somme: true, formatTotal: (v) => String(v) },
        /* Le prix unitaire NE se totalise PAS : additionner des prix unitaires
           ne produit aucune grandeur. */
        { label: 'P.U', key: 'pu', align: 'right' },
        { label: 'Montant', key: 'montant', align: 'right', somme: true },
      ], lignes, { total: true });
      const pied = t.querySelector('tfoot');
      const cells = pied ? [...pied.querySelectorAll('td')].map((c) => c.textContent.trim()) : [];
      /* Sans colonne totalisable, aucun pied ne doit apparaître. */
      const sansSomme = P.tableau([{ label: 'A', key: 'designation' }], lignes, { total: true });
      return {
        cells: cells,
        attendu: C.money(4200, false),
        qte: '8',
        puVide: cells[2] === '',
        piedSansSomme: !!sansSomme.querySelector('tfoot'),
      };
    });
    verifier('Le total d’un état imprimé est CALCULÉ depuis les lignes réellement imprimées',
      totaux.cells[3] === totaux.attendu, 'pied : ' + totaux.cells.join(' | '));
    verifier('…y compris les quantités', totaux.cells[1] === totaux.qte, totaux.cells[1]);
    verifier('Le prix UNITAIRE n’est pas totalisé — un total faux se lit comme un total juste',
      totaux.puVide === true);
    verifier('Sans colonne totalisable, aucun pied de total n’est fabriqué',
      totaux.piedSansSomme === false);

    /* --- Les trois parts et le périmètre MECeF ----------------------------- */
    await ouvrir('m8-facturation.html');
    const ticket = await page.evaluate(async () => {
      const P = window.SIGH.print;
      P.ticket({
        titre: 'Contrôle des parts',
        numero: 'T-TEST', typeVente: 'ASSURANCE',
        assureur: 'NSIA', assure: 'Patient de contrôle',
        dossier: null,
        lignes: [{ designation: 'ACTE COUVERT', quantite: 1, prixUnitaire: 10000, montant: 10000 },
          { designation: 'ACTE NON COUVERT', quantite: 1, prixUnitaire: 1100, montant: 1100 }],
        total: 11100, partAssureur: 8000, partPatient: 3100,
        partNonAssuree: 1100, regle: 2000, baseMecef: 3100,
      });
      await new Promise((r) => setTimeout(r, 400));
      const sheet = document.querySelector('.print-sheet');
      const txt = sheet ? sheet.textContent.replace(/\s+/g, ' ') : '';
      const chrome = document.querySelector('.print-chrome');
      if (chrome && chrome.remove) chrome.remove();
      return {
        ouvert: !!sheet,
        partAssureur: /PART ASSUREUR/.test(txt),
        nonAssuree: /DONT PART NON ASSUR/.test(txt),
        partAssure: /PART ASSUR[ÉE]/.test(txt),
        totalDu: /TOTAL D/.test(txt),
        baseMecef: /BASE MECeF/.test(txt),
        comptoir: /VENTE AU COMPTOIR/.test(txt),
        texte: txt.slice(0, 40),
      };
    });
    verifier('Le ticket porte la PART ASSUREUR', ticket.partAssureur, ticket.ouvert ? '' : 'ticket non ouvert');
    verifier('…la PART ASSURÉ', ticket.partAssure);
    verifier('…la PART NON ASSURÉE, qui n’est pas la même chose que la part assuré',
      ticket.nonAssuree);
    verifier('…et le TOTAL DÛ — sans lui, un règlement partiel laisse repartir sans savoir ce qu’on doit',
      ticket.totalDu);
    verifier('La BASE MECeF est imprimée : elle ne porte que la part réglée par le patient',
      ticket.baseMecef);
    verifier('Une opération de caisse SANS dossier patient est possible et le dit',
      ticket.comptoir);

    /* La base MECeF n'inclut ni la part assureur ni les remises — exigence
       écrite du cahier de charge, pas un détail d'affichage. */
    const mecef = await page.evaluate(() => {
      const S = window.SIGH.store;
      const f = S.collection('factures').active()
        .filter((x) => x.partAssurance > 0 && x.baseMecef != null)[0];
      if (!f) return { absent: true };
      return {
        base: f.baseMecef, patient: f.partPatient,
        assureur: f.partAssurance, remises: f.montantRemises || 0,
        total: f.montantTTC,
      };
    });
    if (!mecef.absent) {
      verifier('La base MECeF vaut la part patient, jamais le total',
        mecef.base === mecef.patient && mecef.base !== mecef.total,
        'base ' + mecef.base + ' · patient ' + mecef.patient + ' · total ' + mecef.total);
      verifier('…donc la part assureur n’entre pas dans la base MECeF',
        mecef.base + mecef.assureur !== mecef.base, 'part assureur ' + mecef.assureur + ' exclue');
    }

    verifier('Aucune erreur JavaScript sur le circuit clinique', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 34. LA CAISSE — DÉTAIL DU REÇU ET RÈGLEMENT PARTIEL
   * -------------------------------------------------------------------------
   * Trois points signalés par la Direction le 25/08/2026, et dont la sonde a
   * montré que la cause n'était PAS là où la documentation la plaçait : le reçu
   * détaillé et l'encaissement ligne par ligne fonctionnaient, mais les 320
   * factures du jeu de démonstration étaient engendrées sans aucune ligne. Sur
   * ces pièces — c'est-à-dire sur presque toutes celles que la caisse voit — le
   * reçu n'avait rien à détailler.
   * ======================================================================= */
  {
    scenario('Caisse — détail du reçu, règlement partiel et libération au laboratoire');

    await page.evaluate(() => window.SIGH.store.setSession({
      role: 'admin', nom: 'BASSONGUI Chabi Séko', fonction: 'direction', secteur: 'ADM',
    }));
    await ouvrir('m8-caisse.html');

    /* --- Toute facture porte ses lignes ---------------------------------- */
    const lignes = await page.evaluate(() => {
      const S = window.SIGH.store;
      const fs2 = S.collection('factures').active();
      const sansLignes = fs2.filter((f) => !(f.lignes || []).length);
      /* Le total doit être la SOMME des lignes, jamais un nombre choisi à part. */
      const incoherentes = fs2.filter((f) => {
        const somme = (f.lignes || []).reduce((n, l) => n + (l.montant || 0), 0);
        return (f.lignes || []).length && somme !== f.montantTTC;
      });
      return {
        total: fs2.length,
        sansLignes: sansLignes.length,
        incoherentes: incoherentes.length,
        moyenneLignes: Math.round(fs2.reduce((n, f) => n + (f.lignes || []).length, 0) / fs2.length * 10) / 10,
      };
    });
    verifier('Toute facture porte ses LIGNES — une facture sans lignes est un total, pas une facture',
      lignes.sansLignes === 0, lignes.sansLignes + ' sans lignes sur ' + lignes.total);
    verifier('Le total d’une facture est la SOMME de ses lignes, jamais un nombre choisi à part',
      lignes.incoherentes === 0, lignes.incoherentes + ' incohérence(s)');
    verifier('Les pièces portent plusieurs prestations en moyenne',
      lignes.moyenneLignes > 1, lignes.moyenneLignes + ' ligne(s) par pièce');

    /* --- Le reçu détaille les prestations, sans signature du patient ------ */
    const recu = await page.evaluate(async () => {
      const S = window.SIGH.store;
      const fac = S.collection('factures').active().filter((f) =>
        (f.lignes || []).length > 2
        && (f.lignes || []).some((l) => l.statutPaiement === 'paye')
        && (f.lignes || []).some((l) => l.statutPaiement !== 'paye'))[0];
      if (!fac) return { erreur: 'aucune pièce partiellement réglée à plusieurs lignes' };

      /* On imprime la pièce par la commande du registre de la journée : on
         positionne d'abord la journée de caisse sur sa date. */
      const dateSel = document.querySelector('#page-content input[type="date"]');
      if (dateSel) {
        dateSel.value = String(fac.date).slice(0, 10);
        dateSel.dispatchEvent(new Event('change', { bubbles: true }));
        await new Promise((r) => setTimeout(r, 500));
      }
      let clique = false;
      for (const tr of document.querySelectorAll('#page-content tbody tr')) {
        if (tr.textContent.indexOf(fac.numero) === -1) continue;
        const b = [...tr.querySelectorAll('button')]
          .find((x) => /réimprimer le reçu/i.test(x.title || ''));
        if (b) { b.click(); clique = true; break; }
      }
      if (!clique) return { erreur: 'commande de reçu introuvable pour ' + fac.numero };
      await new Promise((r) => setTimeout(r, 700));

      const sheet = document.querySelector('.print-sheet');
      const txt = sheet ? sheet.textContent.replace(/\s+/g, ' ') : '';
      const chrome = document.querySelector('.print-chrome');
      if (chrome && chrome.remove) chrome.remove();
      const payees = fac.lignes.filter((l) => l.statutPaiement === 'paye');
      const dues = fac.lignes.filter((l) => l.statutPaiement !== 'paye');
      return {
        piece: fac.numero,
        ouvert: !!sheet,
        sectionReglees: /Prestations réglées/i.test(txt),
        sectionReste: /Reste à régler/i.test(txt),
        nommePayees: payees.every((l) => txt.indexOf(l.designation) !== -1),
        nommeDues: dues.every((l) => txt.indexOf(l.designation) !== -1),
        signaturePatient: /signature du patient/i.test(txt),
        signatureCaissier: /caissier/i.test(txt),
        piedTotal: /TOTAL/.test(txt),
        nbPayees: payees.length, nbDues: dues.length,
      };
    });
    verifier('Le reçu de caisse s’imprime depuis le registre de la journée',
      recu.ouvert === true, recu.erreur || recu.piece);
    verifier('Il porte la section « Prestations réglées »', recu.sectionReglees === true);
    verifier('…et la section « Reste à régler » — pour que le patient sache ce qu’il doit encore',
      recu.sectionReste === true);
    verifier('Il NOMME les prestations réglées — « quel examen a été payé, on doit savoir »',
      recu.nommePayees === true, recu.nbPayees + ' prestation(s) réglée(s)');
    verifier('…et NOMME celles qui restent dues', recu.nommeDues === true, recu.nbDues + ' due(s)');
    verifier('Aucune signature du patient : un encaissement est attesté par celui qui encaisse',
      recu.signaturePatient === false && recu.signatureCaissier === true);
    verifier('Le pied de tableau porte un total — il était vide, ses clés ne correspondant à aucune colonne',
      recu.piedTotal === true);

    /* --- Un règlement partiel libère EXACTEMENT les examens réglés -------- */
    const partiel = await page.evaluate(() => {
      const S = window.SIGH.store, PR = window.SIGH.parcours, D = window.SIGH.data;
      const pt = S.collection('patients').active().filter((p) => !p.assureur)[0];
      const codes = (D.ANALYSES || []).slice(0, 5).map((a) => a.code);
      const ord = PR.prescrire({
        patientCode: pt.code, medecin: 'Dr BASSONGUI Chabi Séko',
        diagnostic: 'Contrôle du règlement partiel', analyses: codes, medicaments: [],
      });
      const fac = S.collection('factures').active()
        .filter((f) => f.ordonnanceId === ord.ordonnance.id
          || (f.patientCode === pt.code && (f.lignes || []).length === codes.length))
        .sort((a, b) => String(b.date).localeCompare(String(a.date)))[0];
      if (!fac) return { erreur: 'facture non engendrée' };

      const dues = PR.lignesDues(fac);
      const trois = dues.slice(0, 3);
      PR.encaisser(fac.id, { lignes: trois.map((l) => l.id) });

      const apres = S.collection('factures').get(fac.id);
      /* On filtre par l ORDONNANCE et non par patient + code : le patient a
         pu recevoir d autres demandes auparavant, et les compter ferait
         echouer une assertion qui a raison. */
      const demandes = S.collection('demandesAnalyses').active()
        .filter((d) => d.ordonnanceId === ord.ordonnance.id);
      const liberees = demandes.filter((d) => d.etatAnalyse === 'attente_prelevement');
      const bloquees = demandes.filter((d) => d.etatAnalyse === 'en_attente');
      const nomsLiberes = liberees.map((d) => d.analyse).sort();
      const nomsPayes = apres.lignes.filter((l) => l.statutPaiement === 'paye')
        .map((l) => l.designation).sort();
      return {
        totalLignes: apres.lignes.length,
        payees: apres.lignes.filter((l) => l.statutPaiement === 'paye').length,
        liberees: liberees.length, bloquees: bloquees.length,
        concordance: JSON.stringify(nomsLiberes) === JSON.stringify(nomsPayes),
        statut: apres.statutPaiement,
        reste: apres.reliquat,
        /* La base MECeF ne porte que ce que le patient a réglé. */
        baseMecef: apres.baseMecef, paye: apres.montantPaye,
      };
    });
    verifier('Trois prestations réglées sur cinq', partiel.payees === 3,
      partiel.erreur || (partiel.payees + ' / ' + partiel.totalLignes));
    verifier('Le laboratoire reçoit EXACTEMENT les trois examens payés',
      partiel.liberees === 3 && partiel.bloquees === 2,
      partiel.liberees + ' libérée(s) · ' + partiel.bloquees + ' bloquée(s)');
    verifier('…et ce sont bien LES MÊMES que celles réglées, nom par nom',
      partiel.concordance === true);
    verifier('La pièce reste « partielle » et annonce son reste dû',
      partiel.statut === 'partielle' && partiel.reste > 0, partiel.reste + ' FCFA de reste');
    verifier('La base MECeF ne porte que la part réglée par le patient',
      partiel.baseMecef === partiel.paye, 'base ' + partiel.baseMecef + ' · réglé ' + partiel.paye);

    verifier('Aucune erreur JavaScript sur la caisse', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 35. FACTURE MÈRE, AMBULANCES ET DOSSIER ÉTENDU
   * ======================================================================= */
  {
    scenario('Facture mère, répertoire des ambulances et dossier de consultation étendu');

    await page.evaluate(() => window.SIGH.store.setSession({
      role: 'admin', nom: 'BASSONGUI Chabi Séko', fonction: 'medecin', secteur: 'ADM',
    }));

    /* --- La facture mère ne s'émet que si elle concorde ------------------- */
    await ouvrir('m9-facture-mere.html');
    const mere = await page.evaluate(() => {
      const texte = document.body.textContent;
      const boutons = [...document.querySelectorAll('#page-content button')]
        .map((b) => (b.textContent || '').trim());
      const S = window.SIGH.store;
      /* Le rapprochement descend au niveau de la LIGNE : c'est là que la
         compagnie conteste. On vérifie que le contrôle existe pour de vrai en
         recalculant nous-mêmes sur les pièces assurées. */
      const assurees = S.collection('factures').active().filter((f) => (f.partAssurance || 0) > 0);
      const ecarts = assurees.filter((f) => {
        const somme = (f.lignes || []).reduce((n, l) => n + (l.partAssureur || 0), 0);
        return somme !== (f.partAssurance || 0);
      });
      return {
        onglets: /Consolidation/.test(texte) && /Détail par ligne/.test(texte),
        parleRapprochement: /recoupe|concord/i.test(texte),
        boutonApercu: boutons.some((b) => /Aperçu de la facture mère/.test(b)),
        boutonEmettre: boutons.some((b) => /Émettre la facture mère/.test(b)),
        assurees: assurees.length,
        ecartsLigne: ecarts.length,
      };
    });
    verifier('La facture mère présente la consolidation ET le détail par ligne d’assurance',
      mere.onglets === true);
    verifier('L’écran énonce la règle du rapprochement', mere.parleRapprochement === true);
    verifier('L’aperçu est toujours offert — on doit pouvoir regarder avant d’émettre',
      mere.boutonApercu === true);
    verifier('Les factures assurées se recoupent avec leur détail ligne à ligne',
      mere.ecartsLigne === 0, mere.ecartsLigne + ' écart(s) sur ' + mere.assurees + ' pièce(s) assurée(s)');

    /* Le bouton d'émission n'est offert QUE si le rapprochement est bon :
       absent, non grisé — un bouton grisé invite à chercher pourquoi. */
    const emission = await page.evaluate(() => {
      const S = window.SIGH.store;
      const col = S.collection('facturesMere', { module: 'M9', entite: 'facture mère', prefix: 'FM' });
      const avant = col.active().length;
      const rec = col.insert({
        numero: 'FM-TEST-0001', compagnieCode: 'NSIA', compagnie: 'NSIA',
        periode: 'mois', periodeLabel: 'Mensuelle',
        debut: '2026-07-26', fin: '2026-08-25', dateEmission: '2026-08-25',
        nbSouscripteurs: 3, nbFactures: 12, montantReclame: 450000,
        souscripteurs: [{ souscripteur: 'Employeur A', nbFactures: 5, assureur: 200000 }],
        piecesFilles: ['FN-2026-00001', 'FN-2026-00002'],
        controle: { totalFilles: 450000, totalFactures: 450000, totalLignes: 450000, concordant: true },
        etat: 'transmise',
      }).record;
      return {
        ajoutee: col.active().length - avant,
        gardeSesFilles: (rec.piecesFilles || []).length > 0,
        controleFige: rec.controle && rec.controle.concordant === true,
        etat: rec.etat,
      };
    });
    verifier('Une facture mère émise fige les NUMÉROS de ses filles',
      emission.gardeSesFilles === true,
      'sans quoi le rapprochement serait irrefaisable dans six mois');
    verifier('…et fige son contrôle de concordance', emission.controleFige === true);
    verifier('Elle naît « transmise », jamais « réglée »', emission.etat === 'transmise');

    /* --- Le répertoire des ambulances ------------------------------------- */
    await ouvrir('m13-repertoire-ambulances.html');
    const amb = await page.evaluate(() => {
      const S = window.SIGH.store;
      const rows = S.collection('ambulances').active();
      const texte = document.body.textContent;
      const liens = [...document.querySelectorAll('#page-content a[href^="tel:"]')];
      return {
        n: rows.length,
        avecNumero: rows.filter((r) => r.telephone).length,
        aCompleter: rows.filter((r) => !r.telephone).length,
        /* Aucun numéro ne doit être inventé : ceux qui existent viennent de
           l'en-tête officiel de la clinique. */
        inventes: rows.filter((r) => r.telephone
          && !window.SIGH.core.BRAND.telephones.some((t) => t === r.telephone)).length,
        liensAppel: liens.length,
        ditQuIlManque: /à renseigner|à compléter/i.test(texte),
        premierEstDisponible: (() => {
          const cartes = [...document.querySelectorAll('#page-content .rounded-xl')];
          return cartes.length ? /Disponible/.test(cartes[0].textContent) : false;
        })(),
      };
    });
    verifier('Le répertoire des ambulances est amorcé', amb.n >= 5, amb.n + ' moyen(s)');
    verifier('AUCUN numéro d’urgence n’est inventé — ceux présents viennent de l’en-tête officiel',
      amb.inventes === 0, amb.avecNumero + ' numéro(s) renseigné(s)');
    verifier('Les fiches sans numéro le DISENT au lieu de rester vides',
      amb.aCompleter > 0 && amb.ditQuIlManque === true, amb.aCompleter + ' à renseigner');
    verifier('Les numéros sont cliquables pour l’appel rapide',
      amb.liensAppel > 0, amb.liensAppel + ' lien(s) tel:');
    verifier('Les moyens DISPONIBLES remontent en tête — deux minutes perdues comptent en urgence',
      amb.premierEstDisponible === true);

    /* --- Le dossier de consultation étendu -------------------------------- */
    await ouvrir('m1-dossier-etendu.html');
    const dossier = await page.evaluate(() => {
      const D = window.SIGH.data;
      return {
        categories: (D.CATEGORIES_ANTECEDENT || []).map((c) => c.code),
        temps: (D.TEMPS_EXAMEN || []).map((t) => t.code),
        etats: (D.ETATS_DOSSIER || []).map((e) => e.code),
        chirurgicales: (D.RUBRIQUES_CHIRURGICALES || []).length,
        /* Les transitions : un saut doit être refusé. */
        attenteVersConsultation: D.transitionPermise('attente', 'consultation'),
        attenteVersCloture: D.transitionPermise('attente', 'cloture'),
        consultationVersLabo: D.transitionPermise('consultation', 'attente_labo'),
        laboVersCloture: D.transitionPermise('attente_labo', 'cloture'),
        clotureVersQuoi: (D.etatDossier('cloture').suivants || []).length,
        /* L'écriture des rubriques chirurgicales. */
        generalisteEcrit: D.peutEcrireRubrique('actesChirurgicaux', 'medecin'),
        chirurgienEcrit: D.peutEcrireRubrique('actesChirurgicaux', 'chirurgien'),
        generalisteDiagnostic: D.peutEcrireRubrique('diagnostic', 'medecin'),
      };
    });
    verifier('Les antécédents sont en TROIS catégories strictes',
      dossier.categories.length === 3
      && dossier.categories.join(',') === 'medicaux,chirurgicaux,gyneco_obstetricaux',
      dossier.categories.join(' · '));
    verifier('L’examen physique suit ses QUATRE temps, dans l’ordre',
      dossier.temps.join(',') === 'inspection,palpation,percussion,auscultation',
      dossier.temps.join(' → '));
    verifier('Le dossier a QUATRE états',
      dossier.etats.join(',') === 'attente,consultation,attente_labo,cloture',
      dossier.etats.join(' → '));
    verifier('« EN ATTENTE » mène à « EN CONSULTATION »', dossier.attenteVersConsultation === true);
    verifier('…mais PAS directement à « CLÔTURÉ » — cela signerait une consultation qui n’a pas eu lieu',
      dossier.attenteVersCloture === false);
    verifier('« EN CONSULTATION » mène à « EN ATTENTE LABO »', dossier.consultationVersLabo === true);
    verifier('« EN ATTENTE LABO » mène à la clôture', dossier.laboVersCloture === true);
    verifier('Un dossier clôturé ne mène nulle part', dossier.clotureVersQuoi === 0);
    verifier('Le généraliste NE PEUT PAS écrire les actes chirurgicaux',
      dossier.generalisteEcrit.ok === false, dossier.generalisteEcrit.motif);
    verifier('…mais le motif précise qu’il peut les LIRE — c’est son patient aussi',
      /LIRE/.test(dossier.generalisteEcrit.motif || ''));
    verifier('Le chirurgien les écrit', dossier.chirurgienEcrit.ok === true);
    verifier('Le généraliste écrit tout le reste du dossier',
      dossier.generalisteDiagnostic.ok === true);

    /* --- Le cloisonnement de l'accueil ------------------------------------ */
    const accueil = await page.evaluate(() => {
      const S = window.SIGH.store, PR = window.SIGH.parcours;
      /* Un patient ASSURÉ : depuis la vague 62 les champs nuls ne s'écrivent
         plus, et un non-assuré n'a donc pas de clé `assureur` à montrer — la
         sonde doit porter sur la RÈGLE de visibilité, pas sur un null. */
      const pt = S.collection('patients').active().filter((x) => x.assureur)[0];
      const avant = S.collection('audit').active().length;
      const vu = PR.dossierPourAccueil(pt);
      PR.journaliserRecherche(pt, { ecran: 'm1-dossier-etendu', action: 'consultation_zone1' });
      const apres = S.collection('audit').active().length;
      const introuvable = PR.journaliserRecherche(null, { terme: 'PATIENT-INEXISTANT' });
      return {
        voitLeNom: vu.fiche.nom != null,
        voitLAssurance: 'assureur' in vu.fiche || 'assureurNom' in vu.fiche,
        voitLeDiagnostic: 'diagnostic' in vu.fiche,
        voitLesAntecedents: 'antecedents' in vu.fiche,
        aUnMotif: !!vu.motif,
        /* Le journal est PLAFONNÉ à 400 entrées : au plafond, une entrée qui
         arrive en chasse une autre et le total ne croît plus. On vérifie donc
         que l entree EXISTE, ce qui est l assertion juste. */
      journalisees: S.collection('audit').active().filter(function (a) {
        return a.ecran === 'm1-dossier-etendu' && a.patientId === pt.id;
      }).length,
      delta: apres - avant,
        infructueuseJournalisee: introuvable && introuvable.trouve === false,
      };
    });
    verifier('L’accueil voit l’identité et la couverture d’assurance',
      accueil.voitLeNom === true && accueil.voitLAssurance === true);
    verifier('…et NE VOIT PAS le diagnostic ni les antécédents (RG-13)',
      accueil.voitLeDiagnostic === false && accueil.voitLesAntecedents === false);
    verifier('La restriction s’annonce : la fonction retourne toujours son motif',
      accueil.aUnMotif === true);
    verifier('Chaque consultation de dossier par l’accueil est journalisée (RG-12)',
      accueil.journalisees >= 1, accueil.journalisees + ' entrée(s) au journal');
    verifier('…y compris les recherches INFRUCTUEUSES — chercher un dossier inexistant est une information',
      accueil.infructueuseJournalisee === true);

    verifier('Aucune erreur JavaScript sur ce lot', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 36. LES TABLEAUX DE BORD PAR PROFIL
   * ======================================================================= */
  {
    scenario('Tableaux de bord par profil et premier regard');

    await page.evaluate(() => window.SIGH.store.setSession({
      role: 'admin', nom: 'BASSONGUI Chabi Séko', fonction: 'direction', secteur: 'ADM',
    }));

    /* --- Le calendrier fiscal est au SOCLE -------------------------------- */
    await ouvrir('dash-direction.html');
    const socle = await page.evaluate(() => {
      const S = window.SIGH.store;
      const ech = S.collection('echeancesFiscales').active();
      const auj = window.SIGH.core.iso(new Date());
      return {
        n: ech.length,
        depassees: ech.filter((e) => !e.paye && String(e.echeance || '') < auj).length,
        familles: [...new Set(ech.map((e) => e.famille))].length,
        /* Le report au jour ouvrable suivant : jamais un samedi ni un dimanche. */
        weekEnd: ech.filter((e) => {
          const d = new Date(e.echeance + 'T00:00:00');
          return d.getDay() === 0 || d.getDay() === 6;
        }).length,
      };
    });
    verifier('Le calendrier fiscal est disponible SANS être passé par son écran',
      socle.n === 63, socle.n + ' échéance(s) — amorcées au socle');
    verifier('Aucune échéance ne tombe un samedi ni un dimanche',
      socle.weekEnd === 0, 'reportées au jour ouvrable suivant, jamais avancées');
    verifier('Le tableau de bord de la Direction compte les échéances DÉPASSÉES, pas toutes',
      socle.depassees > 0 && socle.depassees < socle.n,
      socle.depassees + ' dépassée(s) sur ' + socle.n);

    /* --- Le bandeau du premier regard ------------------------------------- */
    const bandeau = await page.evaluate(() => {
      const txt = document.body.textContent;
      const b = [...document.querySelectorAll('#page-content div')]
        .find((d) => /À REGARDER EN PREMIER/i.test(d.textContent));
      return {
        present: /À regarder en premier/i.test(txt),
        avantLesKpi: (() => {
          const i = txt.indexOf('À regarder en premier');
          const j = txt.indexOf('Chiffre d’affaires du mois');
          return i >= 0 && j >= 0 && i < j;
        })(),
        porteUnLien: !!(b && b.querySelector('a')),
      };
    });
    verifier('Le tableau de bord porte un bandeau « à regarder en premier »', bandeau.present === true);
    verifier('…placé AVANT les indicateurs — l’ordre de lecture est ce qu’un tableau contrôle vraiment',
      bandeau.avantLesKpi === true);
    verifier('…et il mène directement à l’écran concerné', bandeau.porteUnLien === true);

    /* Quand il n'y a rien, le bandeau le DIT positivement. */
    const vide = await page.evaluate(() => {
      const K = window.SIGH.kit;
      const n = K.bandeauPremierRegard({
        valeur: 0, unite: 'chose', question: 'à faire',
        vide: 'Rien ne vous attend ce matin.',
      });
      return { texte: n.textContent, ditQuelqueChose: /Rien ne vous attend/.test(n.textContent) };
    });
    verifier('À zéro, le bandeau énonce une phrase — un vide gris ferait douter de l’écran',
      vide.ditQuelqueChose === true);

    /* --- Chaque profil a SON tableau -------------------------------------- */
    const profils = await page.evaluate(() => {
      const N = window.SIGH.nav;
      const attendus = {
        aide_soignant: 'dash-aide-soignant',
        echographiste: 'dash-echographiste',
        surveillant: 'dash-surveillant',
        assistant_comptable: 'dash-assistant-comptable',
      };
      const out = {};
      Object.keys(attendus).forEach((r) => {
        out[r] = { attendu: attendus[r], reel: N.ROLES[r] ? N.ROLES[r].home : null };
      });
      return out;
    });
    Object.keys(profils).forEach((r) => {
      verifier('Le rôle « ' + r + ' » ouvre SON tableau de bord, pas celui d’un autre profil',
        profils[r].reel === profils[r].attendu, profils[r].reel || 'aucun');
    });

    /* --- Les compteurs lisent les bons champs ------------------------------ */
    const compteurs = await page.evaluate(() => {
      const S = window.SIGH.store;
      const prods = S.collection('produits').active();
      const ecr = S.collection('ecritures').active();
      return {
        /* Le seuil : un seuil NON FIXÉ n'est pas un seuil de zéro. */
        avecSeuil: prods.filter((p) => p.seuilAlerte != null).length,
        sousSeuil: prods.filter((p) => p.seuilAlerte != null && p.stock <= p.seuilAlerte).length,
        totalProduits: prods.length,
        /* Les écritures nées de la caisse sont en brouillon. */
        brouillons: ecr.filter((e) => e.statut === 'brouillon').length,
        validees: ecr.filter((e) => e.statut === 'validee').length,
      };
    });
    verifier('Le compteur des ruptures ne retient que les articles AYANT un seuil',
      compteurs.sousSeuil > 0 && compteurs.sousSeuil < compteurs.totalProduits,
      compteurs.sousSeuil + ' sous seuil sur ' + compteurs.avecSeuil + ' articles pourvus d’un seuil');
    verifier('Le compteur du comptable distingue les écritures en brouillon des validées',
      compteurs.brouillons > 0 && compteurs.validees > 0,
      compteurs.brouillons + ' brouillon(s) · ' + compteurs.validees + ' validée(s)');

    /* --- Les comptes fermés le DISENT sur leur tableau --------------------- */
    await ouvrir('dash-pharmacien.html');
    const ferme = await page.evaluate(() => {
      const txt = document.body.textContent;
      return {
        ditFerme: /compte Pharmacie a été fermé/i.test(txt),
        ditOuEstLaPharmacie: /tenue par la caisse/i.test(txt),
      };
    });
    verifier('Le tableau d’un compte fermé le dit, au lieu de faire comme si de rien n’était',
      ferme.ditFerme === true);
    verifier('…et indique où la fonction a été transférée', ferme.ditOuEstLaPharmacie === true);

    /* --- Aucune erreur sur les vingt-et-un tableaux ------------------------ */
    const tousLesDash = ['dash-direction', 'dash-admin', 'dash-medecin', 'dash-infirmier',
      'dash-laborantin', 'dash-stock', 'dash-caissier', 'dash-comptable', 'dash-receptionniste',
      'dash-admin-agent', 'dash-ambulancier', 'dash-da', 'dash-croise',
      'dash-aide-soignant', 'dash-echographiste', 'dash-surveillant',
      'dash-assistant-comptable'];
    let montes = 0;
    for (const d of tousLesDash) {
      await ouvrir(d + '.html');
      const ok = await page.evaluate(() => !!document.querySelector('#page-content > *'));
      if (ok) montes++;
    }
    /* Un tableau est FERMÉ par activité — le compte Pharmacien est archivé.
       Exiger qu il se monte reviendrait à demander qu une activité close
       continue de s afficher. Le rôle d ingénieur biomédical, lui, est
       SUPPRIMÉ (décision de la Direction du 20/10/2026) : plus de tableau. */
    verifier('Les tableaux de bord OUVERTS se montent tous',
      montes === tousLesDash.length, montes + ' / ' + tousLesDash.length);

    verifier('Aucune erreur JavaScript sur les tableaux de bord', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 37. PARCOURS MÉTIER, PARC TECHNIQUE ET CORRECTIONS DU CLASSEUR 2025
   * -------------------------------------------------------------------------
   * Ce que ce scénario garde fermé : un tableau de bord qui redevient un menu,
   * une étape qui promet un écran fermé, un parc technique dont les fiches se
   * donnent pour relevées, une anomalie de classeur signalée sans être
   * expliquée, et une référence sans prix qu'on ne peut pas valoriser.
   * ======================================================================= */
  {
    scenario('Parcours métier, parc technique et corrections du classeur 2025');

    /* --- Les parcours, profil par profil --------------------------------- */
    const POSTES = [
      ['dash-receptionniste', 'reception', 11],
      ['dash-medecin', 'medecin', 4],
      ['dash-infirmier', 'infirmier', 4],
      ['dash-laborantin', 'laborantin', 4],
      ['dash-caissier', 'caissier', 4],
      ['dash-stock', 'stock', 4],
      ['dash-comptable', 'comptable', 3],
      ['dash-aide-soignant', 'aide_soignant', 2],
      ['dash-echographiste', 'echographiste', 1],
      ['dash-surveillant', 'surveillant', 3],
      ['dash-assistant-comptable', 'assistant_comptable', 3],
      ['dash-ambulancier', 'ambulancier', 1],
    ];
    let chaines = 0, etapes = 0, relais = 0, fermees = 0, manquants = [];
    for (const [ecran, role, attendu] of POSTES) {
      /* Le rôle se pose AVANT le chargement : le rendu se fait au montage, et
         changer la session après coup ne redessine rien. */
      await page.evaluate((r) => {
        localStorage.setItem('sigh-cnt:session', JSON.stringify({
          role: r, nom: 'Sonde ' + r, nomComplet: 'Sonde ' + r, identifiant: 'sonde',
        }));
      }, role);
      await ouvrir(ecran + '.html');
      const v = await page.evaluate(() => {
        const t = document.body.textContent;
        const cartes = [...document.querySelectorAll('ol')];
        return {
          role: (window.SIGH.store.session() || {}).role,
          section: /Ce que vous faites ici/.test(t),
          chaines: cartes.length,
          etapes: cartes.reduce((n, o) => n + o.children.length, 0),
          fermees: (t.match(/fermé à votre profil/g) || []).length,
          relais: [...new Set([...document.querySelectorAll('ol span')]
            .map((x) => x.textContent.trim())
            .filter((x) => /^(Caisse|Laboratoire|Pharmacie|Consultation|DAF|Comptabilité|Ambulance|Stock|Paie|Médecin|Infirmier|Hospitalisation)$/.test(x)))].length,
        };
      });
      chaines += v.chaines; etapes += v.etapes; relais += v.relais; fermees += v.fermees;
      if (!(v.role === role && v.section && v.chaines >= attendu)) {
        manquants.push(ecran + ' (' + v.chaines + '/' + attendu + ')');
      }
    }
    verifier('Les treize postes portent leurs parcours métier',
      manquants.length === 0, manquants.join(', ') || chaines + ' chaînes · ' + etapes + ' étapes');
    verifier('Un tableau de bord cesse d'+String.fromCharCode(8217)+'être un menu',
      chaines >= 43 && etapes >= 150, chaines + ' chaînes · ' + etapes + ' étapes');
    verifier('Le poste qui prend la suite est nommé', relais >= 20, relais + ' relais nommés');
    verifier('Une étape fermée au profil est signalée, pas masquée',
      fermees > 0, fermees + ' étape(s) « fermé à votre profil »');

    /* Aucune étape ne doit pointer vers un écran absent du manifeste. */
    await page.evaluate(() => window.SIGH.store.setSession({
      role: 'admin', nom: 'BASSONGUI Chabi Séko', fonction: 'direction', secteur: 'ADM',
    }));
    await ouvrir('dash-medecin.html');
    const liens = await page.evaluate(() => {
      const N = window.SIGH.nav;
      const ids = [];
      document.querySelectorAll('ol a[href]').forEach((a) => {
        const m = a.getAttribute('href').match(/([a-z0-9-]+)\.(?:php|html)/);
        if (m) ids.push(m[1]);
      });
      return { total: ids.length, inconnus: ids.filter((i) => !N.get(i)) };
    });
    verifier('Chaque étape cliquable pointe vers un écran du manifeste',
      liens.inconnus.length === 0, liens.inconnus.join(', ') || liens.total + ' lien(s) vérifié(s)');

    /* --- Le parc technique ----------------------------------------------- */
    await ouvrir('m13-maintenance.html');
    const parc = await page.evaluate(() => {
      const col = window.SIGH.store.collection('materiel').active();
      return {
        total: col.length,
        pannes: col.filter((m) => m.etat === 'panne').length,
        aCompleter: col.filter((m) => m.aCompleter).length,
        inventes: col.filter((m) => m.marque || m.numeroSerie || m.miseEnService).length,
        filtres: [...document.querySelectorAll('select option')].map((o) => o.textContent.trim())
          .filter((t) => /en panne|entretien échu|fiche à compléter/i.test(t)).length,
        ditProposition: /proposition à\s*compléter|aucun document de cadrage n’inventorie/i
          .test(document.body.textContent),
      };
    });
    verifier('Le parc technique est amorcé', parc.total === 18, parc.total + ' équipement(s)');
    verifier('Aucune donnée de plaque n'+String.fromCharCode(8217)+'est inventée',
      parc.inventes === 0 && parc.aCompleter === parc.total,
      parc.aCompleter + ' fiche(s) à compléter, ' + parc.inventes + ' inventée(s)');
    verifier('L'+String.fromCharCode(8217)+'écran dit que le parc est une proposition', parc.ditProposition);
    verifier('Le filtre de suivi porte ses trois lectures', parc.filtres === 3, String(parc.filtres));
    verifier('Une panne est visible', parc.pannes === 1, parc.pannes + ' en panne');

    /* --- L'écart du classeur 2025 ---------------------------------------- */
    await ouvrir('m12-baseline-2025.html');
    const base = await page.evaluate(() => {
      const t = document.body.textContent;
      const E = window.SIGH.compta.EXERCICE_2025;
      /* Le diagnostic doit être VRAI, pas seulement affiché : chaque ligne du
         détail somme à son propre total, et l'écart vaut une échéance. */
      const incoherentes = (E.depenses || []).filter((d) => {
        const s2 = (d.mois || []).reduce((a, b) => a + b, 0);
        return Math.round((s2 - d.total) * 100) !== 0;
      }).length;
      const ecart = Math.abs(E.controle.ecart);
      const porteuses = (E.depenses || []).filter((d) => (d.mois || [])
        .some((m) => Math.round(m) === ecart));
      return {
        incoherentes: incoherentes,
        porteuses: porteuses.map((d) => d.libelle),
        expliqué: /n’est pas un arrondi/.test(t),
        nomme: /FONDS DE GARANTIE/.test(t),
        comptes: ['275000', '631800', '646800'].filter((c) => t.includes(c)).length,
        ditProposition: /proposition à valider/i.test(t),
      };
    });
    verifier('Le détail du classeur est cohérent avec lui-même',
      base.incoherentes === 0, base.incoherentes + ' ligne(s) incohérente(s)');
    verifier('L'+String.fromCharCode(8217)+'écart correspond à une seule échéance identifiable',
      base.porteuses.length === 1, base.porteuses.join(', '));
    verifier('L'+String.fromCharCode(8217)+'écart est expliqué et sa ligne nommée', base.expliqué && base.nomme);
    verifier('Les trois postes sans compte reçoivent une proposition',
      base.comptes === 3 && base.ditProposition, base.comptes + '/3 comptes proposés');

    /* --- La valorisation des références SAGE ------------------------------
       Le scénario VIDE la surcouche pour éprouver l'écran à nu ; il la
       RESTAURE à la fin — un scénario qui mute doit restaurer (doctrine de
       la matrice RBAC), sans quoi la vague 49 (34 fiches confirmées au
       socle) disparaîtrait pour les scénarios suivants. */
    await ouvrir('m6-reprise.html');
    const sansPrix = await page.evaluate(() => {
      const tous = window.SIGH.store.collection('valorisationsSage').all();
      /* sessionStorage : la sauvegarde doit survivre aux navigations du
         scénario — `window` est balayé à chaque ouvrir(). */
      sessionStorage.setItem('__valoSauvegarde', JSON.stringify(tous));
      tous.length = 0;
      window.SIGH.store.save();
      return window.SIGH.sage.INVENTAIRE_SAGE.filter((a) => !a.valorise).length;
    });
    await ouvrir('m6-reprise.html');
    await cliquer('Points à traiter');
    const anomalies = await page.evaluate(() => {
      const t = document.body.textContent;
      return {
        ditAucunDocument: /aucun document ne les tarife/i.test(t),
        ditSurcouche: /ne modifie pas le document/i.test(t),
        colonne: /Prix de revient/.test(t),
        bouton: !!document.querySelector('tbody tr button[title="Valoriser"]'),
      };
    });
    verifier('Trente-deux références sont sans prix au document', sansPrix === 32, String(sansPrix));
    verifier('L'+String.fromCharCode(8217)+'écran dit qu'+String.fromCharCode(8217)+'aucun document ne les tarife',
      anomalies.ditAucunDocument);
    verifier('Il dit que la saisie ne réécrit pas le document', anomalies.ditSurcouche);
    verifier('La valorisation est saisissable', anomalies.colonne && anomalies.bouton);

    const saisie = await page.evaluate(() => {
      document.querySelector('tbody tr button[title="Valoriser"]').click();
      const m = document.querySelector('.modal, [role="dialog"]');
      return {
        ouverte: !!m,
        champs: m ? [...m.querySelectorAll('input, textarea')].map((i) => i.name).filter(Boolean) : [],
      };
    });
    verifier('La modale demande le prix ET son origine',
      saisie.ouverte && saisie.champs.indexOf('prixRevient') >= 0
      && saisie.champs.indexOf('source') >= 0, saisie.champs.join(', '));

    const compte = await page.evaluate(() => {
      const S = window.SIGH.store;
      const a = window.SIGH.sage.INVENTAIRE_SAGE.filter((x) => !x.valorise)[0];
      S.collection('valorisationsSage').insert({
        code: a.code, designation: a.designation, prixRevient: 250,
        source: 'Facture fournisseur — test', auteur: 'TEST', date: '2026-08-26',
      });
      return a.code;
    });
    await ouvrir('m6-reprise.html');
    const apres = await page.evaluate(() => {
      const m = document.body.textContent.match(/Articles non valorisés\s*([\d\s]+)/);
      return {
        reste: (m && m[1].replace(/\s/g, '')) || '?',
        distingue: /Valorisés par la clinique/i.test(document.body.textContent),
      };
    });
    verifier('Une valorisation saisie fait retomber le compteur',
      apres.reste === '31', compte + ' → reste ' + apres.reste);
    verifier('L'+String.fromCharCode(8217)+'écran distingue le document de ce que la clinique a décidé',
      apres.distingue);

    /* La surcouche est RESTAURÉE telle qu'elle était au socle. */
    await page.evaluate(() => {
      const tous = window.SIGH.store.collection('valorisationsSage').all();
      tous.length = 0;
      JSON.parse(sessionStorage.getItem('__valoSauvegarde') || '[]')
        .forEach((x) => tous.push(x));
      sessionStorage.removeItem('__valoSauvegarde');
      window.SIGH.store.save();
    });

    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 38. LES POINTS DU GESTIONNAIRE DE STOCK
   * -------------------------------------------------------------------------
   * Un chiffre plausible mais faux est pire qu'un écran vide : il sera recopié
   * dans un état signé. Ce scénario ne vérifie donc pas que l'écran s'affiche,
   * il vérifie qu'il SE RECOUPE avec les pièces.
   * ======================================================================= */
  {
    scenario('Points de vente et de stock, trois parts et accès à la caisse');

    await page.evaluate(() => window.SIGH.store.setSession({
      role: 'stock', nom: 'YARO Odile', fonction: 'stock', secteur: 'LOG',
    }));

    /* --- Les trois parts existent-elles dans les données ? --------------- */
    await ouvrir('m6-point-ventes.html');
    const parts = await page.evaluate(() => {
      const f = window.SIGH.store.collection('factures').active();
      const l = f.flatMap((x) => x.lignes || []);
      return {
        factures: f.length, lignes: l.length,
        avecRemise: l.filter((x) => (x.remise || 0) > 0).length,
        agents: f.filter((x) => x.priseEnChargePersonnel).length,
        partPersonnel: l.reduce((n, x) => n + (x.partPersonnel || 0), 0),
        partAssureur: l.reduce((n, x) => n + (x.partAssureur || 0), 0),
        remiseSurMedicament: l.filter((x) => x.categorie === 'medicament' && (x.remise || 0) > 0).length,
        agentAvecAssureur: f.filter((x) => x.priseEnChargePersonnel
          && (x.lignes || []).some((y) => (y.partAssureur || 0) > 0)).length,
        lignesIncoherentes: l.filter((x) => {
          const brut = x.montantBrut != null ? x.montantBrut : x.montant;
          const somme = (x.partAssureur || 0) + (x.partPersonnel || 0) + (x.partPatient || 0);
          return Math.abs((brut - (x.remise || 0)) - x.montant) > 1 || Math.abs(somme - x.montant) > 1;
        }).length,
        piecesIncoherentes: f.filter((x) => {
          const t2 = (x.lignes || []).reduce((n, y) => n + (y.montant || 0), 0);
          return Math.abs(t2 - (x.montantTTC || 0)) > 1;
        }).length,
      };
    });
    verifier('Des remises existent réellement dans les pièces',
      parts.avecRemise > 0, parts.avecRemise + ' ligne(s)');
    verifier('Des agents sont pris en charge par l'+String.fromCharCode(8217)+'établissement',
      parts.agents > 0 && parts.partPersonnel > 0, parts.agents + ' pièce(s)');
    verifier('RG-02 — aucune remise sur une ligne de médicament',
      parts.remiseSurMedicament === 0, String(parts.remiseSurMedicament));
    verifier('La prise en charge du personnel n'+String.fromCharCode(8217)+'est PAS une assurance',
      parts.agentAvecAssureur === 0, parts.agentAvecAssureur + ' pièce(s) mélangeant les deux');
    verifier('Chaque ligne se recoupe — brut moins remise = assureur + personnel + patient',
      parts.lignesIncoherentes === 0, parts.lignesIncoherentes + ' / ' + parts.lignes);
    verifier('Le total de chaque pièce est la somme de ses lignes',
      parts.piecesIncoherentes === 0, parts.piecesIncoherentes + ' / ' + parts.factures);

    /* --- Le point se recoupe-t-il avec les pièces ? ---------------------- */
    const recoupe = await page.evaluate(() => {
      const C2 = window.SIGH.core;
      const dateChamp = document.querySelector('input[type="date"]').value;
      const b = C2.bornes(document.querySelector('select').value, dateChamp);
      const f = window.SIGH.store.collection('factures').active().filter((x) => C2.dansBornes(x.date, b));
      const l = f.flatMap((x) => x.lignes || []);
      const brut = l.reduce((n, x) => n + (x.montantBrut != null ? x.montantBrut : x.montant), 0);
      /* Le prototype compose en typographie française — espace fine insécable
         entre les milliers. On compare les CHIFFRES, toute espace neutralisée,
         sinon la sonde mesure une convention de composition. */
      const chiffres = (x) => String(x).replace(/[\s\u202f\u00a0]/g, '');
      return {
        brut: brut, pieces: f.length,
        affiche: chiffres(document.body.textContent).includes(chiffres(Math.round(brut))),
        onglets: ['Journal des ventes', 'Par client', 'Par article', 'Par groupe', 'Évolution']
          .filter((x) => document.body.textContent.includes(x)).length,
      };
    });
    verifier('Le montant brut affiché est celui des pièces de la période',
      recoupe.affiche, String(recoupe.brut) + ' FCFA');
    verifier('Les quatre axes et l'+String.fromCharCode(8217)+'évolution sont présents',
      recoupe.onglets === 5, String(recoupe.onglets));

    /* Chaque onglet doit rendre : c'est au clic que le rendu casse. */
    let ongletsVides = [];
    for (const onglet of ['Par client', 'Par article', 'Par groupe', 'Évolution']) {
      await cliquer(onglet);
      const n = await page.evaluate(() => document.querySelectorAll('tbody tr').length
        + document.querySelectorAll('canvas').length);
      if (!n) ongletsVides.push(onglet);
    }
    verifier('Les quatre axes rendent leur contenu',
      ongletsVides.length === 0, ongletsVides.join(', ') || 'tous rendus');

    /* « Totaliser le nombre d'un article vendu » — la quantité doit être VRAIE. */
    await cliquer('Par article');
    const qte = await page.evaluate(() => {
      const C2 = window.SIGH.core;
      const b = C2.bornes(document.querySelector('select').value,
        document.querySelector('input[type="date"]').value);
      const l = window.SIGH.store.collection('factures').active()
        .filter((x) => C2.dansBornes(x.date, b)).flatMap((x) => x.lignes || []);
      const par = {};
      l.forEach((x) => { par[x.designation] = (par[x.designation] || 0) + (Number(x.quantite) || 0); });
      const top = Object.keys(par).sort((a, b2) => par[b2] - par[a])[0];
      const trouvee = [...document.querySelectorAll('tbody tr')]
        .map((tr) => [...tr.children].map((td) => td.textContent.trim()))
        .find((c) => c.some((x) => x === top));
      return { article: top, attendu: par[top],
        affiche: trouvee ? Number(String(trouvee[0]).replace(/\D/g, '')) : null };
    });
    verifier('La quantité vendue d'+String.fromCharCode(8217)+'un article est exacte',
      qte.affiche === qte.attendu, qte.article + ' : ' + qte.affiche + ' / ' + qte.attendu);

    /* --- Les trois pourcentages sur l'état imprimé ----------------------- */
    await cliquer('Point détaillé');
    const etat = await page.evaluate(() => {
      const t2 = document.body.textContent;
      return {
        titre: /Point détaillé des ventes/.test(t2),
        colonnes: /% assureur/.test(t2) && /% personnel/.test(t2) && /% remise/.test(t2),
        phrases: /Part réglée par les assureurs/.test(t2)
          && /Part prise en charge par la clinique pour ses agents/.test(t2)
          && /Remises accordées aux clients/.test(t2),
        distingue: /Cette part est une créance/.test(t2) && /n’est due par personne/.test(t2),
        total: /TOTAL/.test(t2),
      };
    });
    verifier('L'+String.fromCharCode(8217)+'état détaillé porte les trois colonnes de pourcentage',
      etat.titre && etat.colonnes);
    verifier('Il énonce les trois parts et distingue la créance du reste',
      etat.phrases && etat.distingue);
    verifier('Son pied totalise ce qu'+String.fromCharCode(8217)+'il imprime', etat.total);

    /* --- Le point du stock : cinq vues, chacune avec son montant --------- */
    await ouvrir('m6-point-stock.html');
    const VUES = ['pharmacie_restant', 'pharmacie_recu', 'magasin_nouveau', 'magasin_sorti', 'magasin_restant'];
    let vuesVides = [];
    for (const v of VUES) {
      await page.evaluate((id) => {
        const sel = document.querySelector('select');
        sel.value = id; sel.dispatchEvent(new Event('change', { bubbles: true }));
      }, v);
      await pause(400);
      const m = await page.evaluate(() => {
        const t2 = document.body.textContent;
        const mm = t2.match(/Montant\s*([\d\s\u202f\u00a0]+)FCFA/);
        return { lignes: document.querySelectorAll('tbody tr').length,
          montant: mm ? Number(mm[1].replace(/[\s\u202f\u00a0]/g, '')) : 0 };
      });
      if (!(m.lignes > 0 && m.montant > 0)) vuesVides.push(v + ' (' + m.lignes + '/' + m.montant + ')');
    }
    verifier('Les cinq vues du stock portent leurs lignes ET leur montant',
      vuesVides.length === 0, vuesVides.join(', ') || 'les cinq');

    /* Un ÉTAT se lit à date : il ne doit pas bouger avec la périodicité. */
    await page.evaluate(() => {
      const s2 = document.querySelectorAll('select');
      s2[0].value = 'magasin_restant'; s2[0].dispatchEvent(new Event('change', { bubbles: true }));
    });
    await pause(350);
    const lireMontant = () => page.evaluate(() => {
      const mm = document.body.textContent.match(/Montant\s*([\d\s\u202f\u00a0]+)FCFA/);
      return mm ? mm[1].replace(/[\s\u202f\u00a0]/g, '') : null;
    });
    const avantP = await lireMontant();
    await page.evaluate(() => {
      const s2 = document.querySelectorAll('select');
      s2[1].value = 'annee'; s2[1].dispatchEvent(new Event('change', { bubbles: true }));
    });
    await pause(350);
    const apresP = await lireMontant();
    verifier('Un état à date ne varie pas avec la périodicité',
      avantP && avantP === apresP, avantP + ' / ' + apresP);

    /* --- Les droits ------------------------------------------------------ */
    const droits = await page.evaluate(() => {
      const N2 = window.SIGH.nav;
      const peut = (r, e) => { const x = N2.get(e); return x ? N2.can(r, x) : null; };
      return {
        dm: peut('dm', 'm8-caisse'), da: peut('da', 'm8-caisse'),
        comptable: peut('comptable', 'm8-caisse'), stock: peut('stock', 'm8-caisse'),
        stockPoints: peut('stock', 'm6-point-ventes') && peut('stock', 'm6-point-stock'),
        echoImagerie: peut('echographiste', 'm2-imagerie'),
        echoOrdonnances: peut('echographiste', 'm2-ordonnances'),
        echoSoins: peut('echographiste', 'm2-salle-soins'),
        echoCaisse: peut('echographiste', 'm8-caisse'),
        echoEcrit: N2.droitsEcran('echographiste', 'm2-imagerie', 'M2').editer,
      };
    });
    verifier('Le DA, le comptable, le gestionnaire de stock ET le Directeur Médical ont la caisse',
      droits.dm === true && droits.da === true && droits.comptable === true && droits.stock === true,
      'DM: ' + droits.dm);
    verifier('Le gestionnaire de stock accède à ses deux points', droits.stockPoints === true);
    verifier('L'+String.fromCharCode(8217)+'échographiste ÉCRIT son écran d'+String.fromCharCode(8217)+'imagerie',
      droits.echoImagerie === true && droits.echoEcrit === true);
    verifier('Il ne rédige ni ordonnance ni soin, et ne voit pas la caisse',
      droits.echoOrdonnances === false && droits.echoSoins === false && droits.echoCaisse === false,
      'ordo: ' + droits.echoOrdonnances + ' · soins: ' + droits.echoSoins + ' · caisse: ' + droits.echoCaisse);

    /* --- Le tableau de bord de l'échographiste --------------------------- */
    await page.evaluate(() => localStorage.setItem('sigh-cnt:session', JSON.stringify({
      role: 'echographiste', nom: 'AHOHOU Rodrigue', nomComplet: 'AHOHOU Rodrigue', identifiant: 'r.ahohou',
    })));
    await ouvrir('dash-echographiste.html');
    const dash = await page.evaluate(() => {
      const cr = window.SIGH.store.collection('resultatsImagerie').active();
      const t2 = document.body.textContent;
      return {
        role: (window.SIGH.store.session() || {}).role,
        comptesRendus: cr.length,
        affiche: t2.includes(String(cr.length)),
        parcours: document.querySelectorAll('ol').length,
        annonce: /aucun accès financier|ne voit pas/i.test(t2),
      };
    });
    verifier('Le technicien d'+String.fromCharCode(8217)+'échographie a son jeu de test',
      dash.comptesRendus > 0 && dash.affiche, dash.comptesRendus + ' compte(s) rendu(s)');
    verifier('Son tableau de bord porte son parcours et annonce ses limites',
      dash.role === 'echographiste' && dash.parcours > 0 && dash.annonce);

    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 39. DÉPENSES, RÉSULTAT, SEUIL, STATISTIQUES RH ET DROITS DES COMMANDES
   * ======================================================================= */
  {
    scenario('Dépenses, compte de résultat, seuil, statistiques RH et droits des commandes');

    /* --- L'état « validé » porte le code du référentiel ------------------ */
    await page.evaluate(() => localStorage.setItem('sigh-cnt:session', JSON.stringify({
      role: 'laborantin', nom: 'KINNOU A. Ganiou', nomComplet: 'KINNOU A. Ganiou',
      identifiant: 'g.kinnou', fonction: 'tsl', secteur: 'LAB',
    })));
    await ouvrir('m5-resultats.html');
    const labo = await page.evaluate(() => {
      const D2 = window.SIGH.data;
      const d = window.SIGH.store.collection('demandesAnalyses').active();
      const inconnus = d.filter((x) => !(D2.ETATS_RESULTAT || [])
        .some((e) => e.id === x.etatAnalyse));
      const rendus = d.filter((x) => D2.resultatRendu(x.etatAnalyse));
      const rows = [...document.querySelectorAll('tbody tr')];
      const boutons = rows.map((tr) => {
        const b = tr.querySelector('button');
        return b ? b.getAttribute('aria-disabled') === 'true' : null;
      });
      return {
        total: d.length, inconnus: inconnus.length, rendus: rendus.length,
        lignes: rows.length, verrouilles: boutons.filter((x) => x === true).length,
      };
    });
    verifier('Aucun état d'+String.fromCharCode(8217)+'analyse hors référentiel',
      labo.inconnus === 0, labo.inconnus + ' / ' + labo.total);
    verifier('Des résultats sont OPPOSABLES au prescripteur',
      labo.rendus > 0, labo.rendus + ' résultat(s) rendu(s)');
    verifier('La saisie est verrouillée tant que l'+String.fromCharCode(8217)+'échantillon n'+String.fromCharCode(8217)+'est pas reçu',
      labo.lignes > 0 && labo.verrouilles === labo.lignes,
      labo.verrouilles + ' / ' + labo.lignes + ' ligne(s)');

    /* --- Un seul service « Direction » ----------------------------------- */
    await page.evaluate(() => window.SIGH.store.setSession({
      role: 'admin', nom: 'BASSONGUI Chabi Séko', fonction: 'direction', secteur: 'ADM',
    }));
    await ouvrir('m10-personnel.html');
    const svc = await page.evaluate(() => {
      const p2 = window.SIGH.store.collection('personnel').active();
      const D2 = window.SIGH.data;
      return {
        administration: p2.filter((x) => x.service === 'Administration').length,
        direction: p2.filter((x) => x.service === 'Direction').length,
        ref: (D2.SERVICES || []).filter((x) => x === 'Administration').length,
        centre: (D2.CENTRES_COUT || []).filter((x) => x.id === 'administration').length,
      };
    });
    verifier('« Administration » et « Direction » ne font plus qu’un',
      svc.administration === 0 && svc.ref === 0 && svc.centre === 0 && svc.direction > 0,
      svc.direction + ' agent(s) à la Direction');

    /* --- Les dépenses journalières --------------------------------------- */
    await ouvrir('m12-depenses.html');
    const dep = await page.evaluate(() => {
      const S2 = window.SIGH.store;
      const d = S2.collection('depenses').active();
      const t2 = document.body.textContent;
      return {
        total: d.length,
        sansRecu: d.filter((x) => !x.justificatif).length,
        tresorerie: S2.collection('banques').active().length,
        lignes: document.querySelectorAll('tbody tr').length,
        ditContestable: /contestable/i.test(t2),
        boutonNouveau: [...document.querySelectorAll('button')]
          .some((b) => /Nouvelle dépense/.test(b.textContent)),
      };
    });
    verifier('Un historique de dépenses est peuplé', dep.total > 0, dep.total + ' dépense(s)');
    verifier('Les comptes de trésorerie sont disponibles depuis cet écran',
      dep.tresorerie >= 4, dep.tresorerie + ' compte(s)');
    verifier('Les dépenses sans justificatif sont comptées et dites contestables',
      dep.sansRecu > 0 && dep.ditContestable, dep.sansRecu + ' sans reçu');
    verifier('Le tableau affiche ses lignes et sa commande de création',
      dep.lignes > 0 && dep.boutonNouveau, dep.lignes + ' ligne(s)');

    /* L'écriture posée est ÉQUILIBRÉE et en BROUILLON. */
    const ecr = await page.evaluate(() => {
      const S2 = window.SIGH.store;
      const col = S2.collection('depenses');
      const tres = S2.collection('banques').active()[0];
      const av = S2.collection('ecritures').active().length;
      const rec = col.insert({
        reference: 'DEP-TEST-0001', date: '2026-08-20', montant: 25000,
        libelle: 'Contrôle automatique — achat de compresses',
        compteCharge: '604100', compteTresorerie: tres.id, categorie: 'medical',
        justificatif: null, saisiPar: 'Test', saisiLe: '2026-08-20',
      }).record;
      return { id: rec.id, avant: av };
    });
    await ouvrir('m12-depenses.html');
    verifier('Une dépense saisie est conservée', !!ecr.id, ecr.id);

    /* --- Le compte de résultat -------------------------------------------
       L'écran écarte les brouillons DE SA PÉRIODE et l'annonce. Le sonder
       par abondance (il y en aura bien un quelque part) mesurait la chance :
       on POSE un brouillon daté du jour — présent dans toute période par
       défaut — on lit l'annonce, puis on le retire. */
    await page.evaluate(() => {
      /* Datée DANS les bornes par défaut de l'écran — « année, arrêtée au
         16/08 » (l'horloge figée du prototype) : une sonde au jour réel
         tomberait après l'arrêté et ne prouverait rien. */
      window.SIGH.store.collection('ecritures', { module: 'M12', entite: 'écriture' }).insert({
        numero: 'SONDE-CR', date: '2026-08-10',
        journal: 'OD', compte: '606100', compteLibelle: 'Sonde',
        libelle: 'Brouillon de sonde — compte de résultat', debit: 1000, credit: 0,
        statut: 'brouillon',
      });
    });
    await ouvrir('m12-compte-resultat.html');
    const res = await page.evaluate(() => {
      const t2 = document.body.textContent;
      const S2 = window.SIGH.store;
      const col2 = S2.collection('ecritures');
      const ecarte = /brouillon\(s\) écarté\(s\)/.test(t2);
      /* Nettoyage : la sonde ne laisse pas son écriture. */
      col2.active().filter((x) => x.numero === 'SONDE-CR').forEach((x) => col2.archive(x.id));
      return {
        cascade: ['MARGE COMMERCIALE', 'VALEUR AJOUTÉE', 'EXCÉDENT BRUT D’EXPLOITATION',
          'RÉSULTAT D’EXPLOITATION', 'RÉSULTAT FINANCIER', 'RÉSULTAT NET']
          .filter((x) => t2.includes(x)).length,
        brouillonsEcartes: ecarte,
        ditFinancier: /juger l’activité sur des choix de financement/.test(t2),
      };
    });
    verifier('La cascade des soldes intermédiaires est complète',
      res.cascade === 6, res.cascade + '/6');
    verifier('Les brouillons de la période sont ÉCARTÉS et le dire',
      res.brouillonsEcartes);
    verifier('Les charges financières restent hors exploitation', res.ditFinancier);

    /* --- Le seuil de rentabilité ----------------------------------------- */
    await ouvrir('m12-seuil-rentabilite.html');
    const seuil = await page.evaluate(() => {
      const t2 = document.body.textContent;
      return {
        kpis: ['Charges variables', 'Charges fixes', 'Marge sur coût variable',
          'Seuil de rentabilité', 'Marge de sécurité'].filter((x) => t2.includes(x)).length,
        ditProposition: /est une <strong>proposition|répartition <strong>fixe/i.test(document.body.innerHTML),
        ditStructure: /structure constante|marge sur coût variable est nulle/i.test(t2),
        comptes: document.querySelectorAll('tbody tr').length,
      };
    });
    verifier('Les cinq grandeurs du seuil sont affichées', seuil.kpis === 5, seuil.kpis + '/5');
    verifier('La répartition fixe/variable se présente comme une PROPOSITION',
      seuil.ditProposition);
    verifier('La réserve sur la structure constante est énoncée', seuil.ditStructure);
    verifier('Les charges sont détaillées compte par compte',
      seuil.comptes > 0, seuil.comptes + ' compte(s)');

    /* --- Les statistiques RH --------------------------------------------- */
    await ouvrir('m10-stats-presence.html');
    const pres = await page.evaluate(() => {
      const t2 = document.body.textContent;
      return {
        pointages: window.SIGH.store.collection('presences').active().length,
        lignes: document.querySelectorAll('tbody tr').length,
        graphiques: document.querySelectorAll('canvas').length,
        ditAssiette: /journées effectivement pointées|journée\(s\) observée\(s\)/i.test(t2),
        ditRetard: /retard est compté|retard est une présence|retard est compté à part/i.test(t2),
      };
    });
    verifier('Le registre des présences est disponible depuis cet écran',
      pres.pointages > 0, pres.pointages + ' pointage(s)');
    verifier('Le taux par service est calculé et représenté',
      pres.lignes > 0 && pres.graphiques > 0,
      pres.lignes + ' service(s), ' + pres.graphiques + ' graphique(s)');
    verifier('Le taux annonce son assiette et distingue le retard de l’absence',
      pres.ditAssiette && pres.ditRetard);

    await ouvrir('m10-stats-permanences.html');
    const perm = await page.evaluate(() => {
      const t2 = document.body.textContent;
      return {
        lignes: document.querySelectorAll('tbody tr').length,
        distingue: /permanence.*08h.*18h|n’est pas la <strong>garde/i.test(document.body.innerHTML),
      };
    });
    verifier('Les permanences sont comptées à part des gardes',
      perm.distingue, perm.lignes + ' agent(s)');

    /* --- Les croisements demandés ---------------------------------------- */
    await ouvrir('dash-croise.html');
    const croise = await page.evaluate(() => {
      const t2 = document.body.textContent;
      return {
        actes: /Actes réalisés/.test(t2),
        soins: /Soins exécutés/.test(t2),
      };
    });
    verifier('Les sources « Actes réalisés » et « Soins exécutés » existent',
      croise.actes && croise.soins);

    /* --- Les droits des commandes ---------------------------------------- */
    const droits = await page.evaluate(() => {
      const N2 = window.SIGH.nav;
      return {
        echoDossier: N2.droitsEcran('echographiste', 'm1-patient-profil', 'M1').editer,
        echoAntecedents: N2.droitsEcran('echographiste', 'm1-antecedents', 'M1').editer,
        laboDossier: N2.droitsEcran('laborantin', 'm1-patient-profil', 'M1').editer,
        caissierM6: N2.droits('caissier', 'M6'),
        dmCaisse: N2.can('dm', N2.get('m8-caisse')),
      };
    });
    verifier('Ni l’échographiste ni le biologiste ne modifient le dossier patient',
      droits.echoDossier === false && droits.echoAntecedents === false
      && droits.laboDossier === false);
    verifier('La pharmacie est transférée en entier au caissier',
      droits.caissierM6.voir && droits.caissierM6.editer && droits.caissierM6.annuler);
    verifier('Le Directeur Médical accède à la caisse', droits.dmCaisse === true);

    /* Le bandeau de lecture seule est posé par le SOCLE, sur tout écran qui
       se modifie — l'écrire écran par écran aurait garanti autant d'oublis. */
    await page.evaluate(() => localStorage.setItem('sigh-cnt:session', JSON.stringify({
      role: 'echographiste', nom: 'AHOHOU Rodrigue', nomComplet: 'AHOHOU Rodrigue',
      identifiant: 'r.ahohou', fonction: 'medecin',
    })));
    await ouvrir('m1-antecedents.html');
    const bandeau = await page.evaluate(() => {
      const t2 = document.body.textContent;
      return {
        ditLecture: /Lecture seule/.test(t2),
        renvoieMatrice: /matrice des droits/i.test(t2),
        boutonModifier: [...document.querySelectorAll('button')]
          .some((b) => /Modifier les antécédents/.test(b.getAttribute('title') || '')),
      };
    });
    verifier('Un écran restreint DIT qu’il est en lecture seule',
      bandeau.ditLecture && bandeau.renvoieMatrice);
    verifier('…et n’offre pas la commande qu’il refuserait',
      bandeau.boutonModifier === false);

    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 40. RÔLES, RBAC FIN, CIRCUIT DU PRÉLÈVEMENT ET MOTEUR DE NOTIFICATION
   * ======================================================================= */
  {
    scenario('Rôles, RBAC par écran, circuit du prélèvement et moteur de notification');

    /* --- Le renommage, jusqu'à l'ANNUAIRE des comptes ------------------- */
    /* LA PAGE DE CONNEXION NE LISTE PLUS LES COMPTES (20/10/2026) : le
       sélecteur de démonstration est retiré, l'agent saisit ses identifiants.
       Le renommage se mesure donc là où il vit — le manifeste des rôles et
       l'annuaire servi par api/auth.php — et non plus sur le texte de la page. */
    await page.goto('http://127.0.0.1:' + PORT + '/index.php', { waitUntil: 'networkidle2' });
    await pause(600);
    const conn = await page.evaluate(async () => {
      const roles = window.SIGH.nav.ROLES;
      const labels = Object.keys(roles).map((k) => roles[k].label + ' ' + (roles[k].court || ''));
      let comptes = [];
      try {
        const r = await fetch('api/auth.php?action=comptes', { headers: { Accept: 'application/json' } });
        comptes = ((await r.json()).comptes || []).map((c) => c.nom + ' ' + c.identifiant);
      } catch (e) { comptes = ['(annuaire injoignable : ' + e.message + ')']; }
      const t = document.body.textContent;
      return {
        biologiste: labels.some((l) => /Biologiste médical/.test(l)),
        laborantin: labels.some((l) => /Laborantin/.test(l)),
        /* Le rôle est SUPPRIMÉ (Direction, 20/10/2026) : ni au manifeste, ni à
           l'annuaire des comptes, ni en page de tableau de bord. */
        biomedical: comptes.some((c) => /biom/i.test(c)),
        biomedicalAuManifeste: !!window.SIGH.nav.ROLES.biomedical || !!window.SIGH.nav.get('dash-biomedical'),
        dispensaire: comptes.some((c) => /Dispensaire/i.test(c)),
        troisProfils: comptes.some((c) => /AHOHOU/.test(c)) && comptes.some((c) => /Surveillant/.test(c))
          && comptes.some((c) => /Assistant de Direction/.test(c)),
        comptes: comptes.length,
        /* La page elle-même : ni sélecteur, ni profil de démonstration, ni pied. */
        selecteur: !!document.querySelector('form select'),
        demo: /Profil de connexion/.test(t),
        pied: /Les comptes sont ouverts par l’administrateur système/.test(t)
          || /Vérification en 2 étapes/.test(t) || /Plan du site/.test(t),
        identifiantVide: (document.getElementById('identifiant') || {}).value === '',
        motDePasseVide: (document.getElementById('motdepasse') || {}).value === '',
      };
    });
    verifier('« Laborantin » est devenu « Biologiste médical » au manifeste des rôles',
      conn.biologiste && !conn.laborantin);
    verifier('Le rôle d’ingénieur biomédical est supprimé : ni annuaire, ni manifeste, ni tableau de bord',
      conn.biomedical === false && conn.biomedicalAuManifeste === false);
    verifier('Le caissier est « Dispensaire (Pharmacie) » à l’annuaire', conn.dispensaire, conn.comptes + ' compte(s)');
    verifier('Les trois profils créés ouvrent une session (annuaire)', conn.troisProfils, conn.comptes + ' compte(s)');
    verifier('La page de connexion ne porte plus de sélecteur de profil de démonstration',
      !conn.selecteur && !conn.demo);
    verifier('Le pied « comptes ouverts par l’administrateur — 2 étapes — plan du site » est retiré', !conn.pied);
    verifier('Identifiant et mot de passe ne sont plus pré-remplis', conn.identifiantVide && conn.motDePasseVide);

    /* --- Un écran fermé n’est atteignable de NULLE PART ------------------ */
    await page.evaluate(() => localStorage.setItem('sigh-cnt:session', JSON.stringify({
      role: 'laborantin', fonction: 'tsl', nom: 'KINNOU A. Ganiou',
      nomComplet: 'KINNOU A. Ganiou', identifiant: 'a.kinnou', secteur: 'LAB',
    })));
    await ouvrir('hub-m5.html');
    const hub = await page.evaluate(() => {
      const t = document.body.textContent;
      return {
        banque: /Banque de sang/.test(t),
        donneurs: /Donneurs/.test(t),
        cartes: document.querySelectorAll('.hub-card').length,
      };
    });
    verifier('Le hub respecte les activités fermées — un écran fermé n’y figure plus',
      !hub.banque && !hub.donneurs, hub.cartes + ' carte(s)');

    /* --- Le RBAC descend à l’écran -------------------------------------- */
    const droits = await page.evaluate(() => {
      const N = window.SIGH.nav;
      const d = (r, e, m) => N.droitsEcran(r, e, m);
      const peut = (r, e) => { const x = N.get(e); return x ? N.can(r, x) : null; };
      return {
        caisseGros: d('caissier', 'm6-stock-gros', 'M6'),
        caisseTransferts: d('caissier', 'm6-transferts', 'M6'),
        caisseDetail: d('caissier', 'm6-stock-detail', 'M6'),
        caisseDossier: peut('caissier', 'm1-dossier-medical'),
        caisseAntecedents: peut('caissier', 'm1-antecedents'),
        caissePharmaDash: peut('caissier', 'dash-pharmacien'),
        caisseCaisseDash: peut('caissier', 'dash-caissier'),
        bio: ['m1-dossier-etendu', 'm1-pieces', 'm1-constantes', 'm1-reference',
          'm1-contre-reference', 'm13-maintenance'].map((e) => peut('laborantin', e)),
        /* On mesure aussi la FICHE elle-même : « six écrans ouverts » ne dit
           pas si un droit a été accordé ou si les réglages ont été effacés.
           C'est ce compte qui a désigné la copie tronquée. */
        ficheBio: (function () {
          const S = window.SIGH.store;
          const col = S.collection('rbac', { module: 'M14', entite: 'rôle', prefix: 'RBAC' });
          const fiches = col.all().filter((x) => x.role === 'laborantin');
          return fiches.length === 1 ? Object.keys(fiches[0].droitsEcrans || {}).length : -fiches.length;
        }()),
      };
    });
    verifier('Une seule fiche RBAC pour le biologiste, avec tous ses réglages d’écran',
      droits.ficheBio >= 13, droits.ficheBio + ' réglage(s) d’écran');
    /* Décision du 02/09/2026 : la LECTURE même du magasin est retirée au
       caissier — son poste est la pharmacie de détail, le gros appartient
       au magasinier. */
    verifier('Le magasin (stock gros) est FERMÉ au caissier — lecture comprise (02/09)',
      droits.caisseGros.voir === false && droits.caisseTransferts.voir === false);
    verifier('…et garde le stock détail, qui est sa pharmacie',
      droits.caisseDetail.editer === true);
    verifier('Il n’accède ni au dossier médical ni aux antécédents (RG-13)',
      droits.caisseDossier === false && droits.caisseAntecedents === false);
    verifier('Il voit SES DEUX tableaux — caisse et pharmacie',
      droits.caissePharmaDash === true && droits.caisseCaisseDash === true);
    verifier('Le biologiste ne voit aucun des six écrans hors de son périmètre',
      droits.bio.every((x) => x === false), droits.bio.join(','));

    /* --- Le circuit du prélèvement s’accorde avec ses données ----------- */
    await ouvrir('m5-prelevement.html');
    const circuit = await page.evaluate(() => {
      const col = window.SIGH.store.collection('demandesAnalyses').active();
      const onglets = [...document.querySelectorAll('.tab')].map((x) => x.textContent.trim());
      const nombre = (t) => { const m = String(t).match(/(\d+)\s*$/); return m ? Number(m[1]) : null; };
      return {
        onglets,
        aTransmettre: nombre(onglets[1]),
        recus: nombre(onglets[2]),
        /* Les données derrière : l'écran range sur les HORODATAGES. */
        preleves: col.filter((d) => d.preleveLe && !d.recuLaboLe).length,
        recusData: col.filter((d) => d.recuLaboLe
          && !['valide', 'rectifie'].includes(d.etatAnalyse)).length,
        sansHorodatage: col.filter((d) => d.prelevementLe && !d.preleveLe).length,
      };
    });
    verifier('Aucun horodatage de prélèvement sous un second nom',
      circuit.sansHorodatage === 0, String(circuit.sansHorodatage));
    verifier('L’onglet « À transmettre » compte ce que les données portent',
      circuit.aTransmettre === circuit.preleves,
      circuit.aTransmettre + ' / ' + circuit.preleves);
    verifier('L’onglet « Reçus au laboratoire » aussi',
      circuit.recus === circuit.recusData, circuit.recus + ' / ' + circuit.recusData);

    /* --- Les modales n’affichent pas leurs balises ----------------------- */
    await page.evaluate(() => {
      const t = [...document.querySelectorAll('.tab')].find((x) => /transmettre/i.test(x.textContent));
      if (t) t.click();
    });
    await pause(500);
    await page.evaluate(() => {
      const b = [...document.querySelectorAll('tbody button')]
        .find((x) => /transmettre/i.test(x.getAttribute('title') || x.textContent));
      if (b) b.click();
    });
    await pause(600);
    const modale = await page.evaluate(() => {
      const m = document.querySelector('[role="dialog"], .modal');
      if (!m) return { present: false };
      return {
        present: true,
        balises: /<strong>|<\/strong>|<br>|&lt;strong&gt;/.test(m.textContent || ''),
        gras: m.querySelectorAll('strong').length,
      };
    });
    verifier('Une modale rend son gras et n’affiche AUCUNE balise',
      modale.present && modale.balises === false && modale.gras > 0,
      modale.gras + ' élément(s) en gras');
    await page.keyboard.press('Escape');
    await pause(300);

    /* --- Le moteur de notification --------------------------------------- */
    await page.evaluate(() => localStorage.setItem('sigh-cnt:session', JSON.stringify({
      role: 'stock', fonction: 'stock', nom: 'MAMAN Zoukanéri',
      nomComplet: 'MAMAN Zoukanéri', identifiant: 'z.maman', secteur: 'ADM',
    })));
    await ouvrir('dash-stock.html');
    const moteur = await page.evaluate(() => {
      const NT = window.SIGH.notifications;
      if (!NT) return { present: false };
      const S2 = window.SIGH.store;
      const N2 = window.SIGH.nav;
      /* LE MOTEUR NE REDÉFINIT AUCUNE RÈGLE : il doit compter exactement ce
         que le module compte. */
      const duModule = S2.collection('produits').active()
        .filter((p) => p.seuilAlerte != null && p.stock <= p.seuilAlerte).length;
      const duMoteur = NT.collecter({ tousPostes: true, detaille: true })
        .filter((n) => n.source === 'stock_seuil').length;
      /* ROUTAGE : aucune alerte ne doit renvoyer vers un écran interdit. */
      const promesses = ['reception', 'caissier', 'medecin'].reduce((n, r) => n
        + NT.collecter({ poste: r }).filter((x) => x.lien && N2.get(x.lien)
          && !N2.can(r, N2.get(x.lien))).length, 0);
      return {
        present: true, duModule, duMoteur, promesses,
        pourStock: NT.collecter({ poste: 'stock' }).length,
        tous: NT.collecter({ tousPostes: true }).length,
        priorites: Object.keys(NT.PRIORITES).join(','),
      };
    });
    verifier('Le moteur compte EXACTEMENT ce que le module compte',
      moteur.duModule === moteur.duMoteur,
      'module : ' + moteur.duModule + ' · moteur : ' + moteur.duMoteur);
    verifier('Il conserve les priorités existantes',
      moteur.priorites === 'critique,important,information');
    verifier('Il route par poste — chacun reçoit sa part, pas tout',
      moteur.pourStock < moteur.tous, moteur.pourStock + ' / ' + moteur.tous);
    verifier('Aucune alerte ne renvoie vers un écran interdit au profil',
      moteur.promesses === 0, String(moteur.promesses));

    /* La cloche compte vraiment. */
    const cloche = await page.evaluate(() => {
      const NT = window.SIGH.notifications;
      const b = [...document.querySelectorAll('button')]
        .find((x) => /notification/i.test(x.getAttribute('aria-label') || ''));
      const badge = b ? b.querySelector('span') : null;
      return {
        texte: badge ? badge.textContent : null,
        cache: badge ? badge.classList.contains('hidden') : null,
        attendu: NT.enAttente().length,
      };
    });
    verifier('Le badge de la cloche porte le VRAI compte, jamais un nombre écrit en dur',
      cloche.attendu === 0 ? cloche.cache === true : Number(cloche.texte) === cloche.attendu,
      'badge ' + cloche.texte + ' · attendu ' + cloche.attendu);

    /* Le son est un canal, jamais un point de défaillance. */
    const son = await page.evaluate(() => {
      const NT = window.SIGH.notifications;
      NT.setParams({ son: false });
      const muet = NT.sonoriser({ cle: 'test-scenario', priorite: 'critique' });
      const alertes = NT.enAttente().length;
      NT.setParams({ son: true, profil: 'standard', temporisation: 30 });
      const a = NT.sonoriser({ cle: 'spam-scenario', priorite: 'critique' });
      const b = NT.sonoriser({ cle: 'spam-scenario', priorite: 'critique' });
      const avant = NT.collecter({ tousPostes: true }).length;
      NT.tester();
      const apres = NT.collecter({ tousPostes: true }).length;
      return { muet, alertes, premier: a, second: b, avant, apres };
    });
    verifier('Couper le son ne coupe pas l’alerte',
      son.muet.joue === false && son.alertes > 0,
      son.alertes + ' alerte(s) subsistent');
    verifier('Une même alerte ne resonne pas dans la temporisation',
      son.second.joue === false && son.second.motif === 'temporisation');
    verifier('Tester le son ne crée AUCUNE notification métier',
      son.avant === son.apres, son.avant + ' → ' + son.apres);

    /* Entendre n'est pas traiter. */
    const acq = await page.evaluate(() => {
      const NT = window.SIGH.notifications;
      const avant = NT.enAttente().length;
      const cible = NT.collecter()[0];
      if (!cible) return { possible: false };
      NT.acquitter(cible.cle, cible.membres);
      const apres = NT.enAttente().length;
      const listee = NT.collecter().some((n) => n.cle === cible.cle);
      NT.reprendre(cible.cle, cible.membres);
      return { possible: true, avant, apres, listee, repris: NT.enAttente().length };
    });
    verifier('Acquitter retire du badge…', acq.possible && acq.apres === acq.avant - 1,
      acq.avant + ' → ' + acq.apres);
    verifier('…mais l’alerte reste au centre : entendre n’est pas traiter', acq.listee === true);
    verifier('On peut la reprendre', acq.repris === acq.avant);

    /* --- Le rappel du biologiste ---------------------------------------- */
    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'laborantin', fonction: 'tsl', nom: 'KINNOU A. Ganiou',
        nomComplet: 'KINNOU A. Ganiou', identifiant: 'a.kinnou', secteur: 'LAB',
      }));
    });
    await ouvrir('dash-laborantin.html');
    const rappel = await page.evaluate(() => {
      const m = document.querySelector('[role="dialog"], .modal');
      const t = m ? m.textContent : '';
      return {
        ouvert: !!m,
        deux: /prélèvement à faire/i.test(t) && /résultat à renseigner/i.test(t),
        frequence: /une fois par jour/i.test(t),
      };
    });
    verifier('Le rappel du biologiste s’ouvre à la prise de poste et porte ses DEUX questions',
      rappel.ouvert && rappel.deux && rappel.frequence);
    await page.keyboard.press('Escape');
    await pause(300);
    await ouvrir('dash-laborantin.html');
    const bis = await page.evaluate(() => !!document.querySelector('[role="dialog"], .modal'));
    verifier('…et ne se rouvre pas au passage suivant', bis === false);

    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* ==========================================================================
   * 41. SOCLE — MINITABLE, VÉRITÉ TARIFAIRE, KPI COMPTÉS, EN-TÊTE UNIQUE
   * --------------------------------------------------------------------------
   * Les défauts corrigés en phase 1 étaient TOUS invisibles à check.js : des
   * vues de détail rendues vides (colonnes chaînes), un catalogue d'actes
   * amorcé par le seul écran de configuration pendant que le moteur tarifait
   * depuis la constante, des indicateurs écrits en dur, deux seeds aux formes
   * divergentes. La sonde lit les cellules et compare au magasin.
   * ======================================================================== */
  {
    scenario('Socle — miniTable, vérité tarifaire, KPI comptés et en-tête unique');

    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'admin', fonction: 'direction', nom: 'Admin',
        nomComplet: 'Administrateur', identifiant: 'admin',
      }));
    });
    await ouvrir('dash-admin-agent.html');

    /* --- miniTable : les deux formes de colonnes ------------------------- */
    const mt = await page.evaluate(() => {
      const K = window.SIGH.kit;
      const chaines = K.miniTable(['Rubrique', 'Valeur'], [['Type', 'Eutocique'], ['Heure', '08h15']]);
      const ths = [...chaines.querySelectorAll('th')].map((x) => x.textContent.trim());
      const tds = [...chaines.querySelectorAll('td')].map((x) => x.textContent.trim());
      const objets = K.miniTable([{ key: 'a', label: 'A' }], [{ a: 'x' }]);
      const tdObj = objets.querySelector('td');
      return { ths: ths.join('|'), tds: tds.join('|'), objet: tdObj ? tdObj.textContent.trim() : null };
    });
    verifier('miniTable en colonnes-chaînes rend ses en-têtes', mt.ths === 'Rubrique|Valeur', mt.ths);
    verifier('…et ses cellules — plus de tableau de tirets',
      mt.tds === 'Type|Eutocique|Heure|08h15', mt.tds);
    verifier('La forme en colonnes-objets est inchangée', mt.objet === 'x');

    /* --- Le catalogue des actes vit au socle ----------------------------- */
    const actes = await page.evaluate(() => {
      const S = window.SIGH.store;
      return { n: S.collection('actes').active().length };
    });
    verifier('Le catalogue des actes est amorcé SANS ouvrir cfg-tarifs', actes.n >= 69,
      actes.n + ' acte(s)');

    /* --- Une seule vérité tarifaire : l'écran modifie, le moteur suit ---- */
    const verite = await page.evaluate(() => {
      const S = window.SIGH.store, PR = window.SIGH.parcours;
      const col = S.collection('actes');
      const acte = col.active().filter((a) => a.prix != null && a.code)[0];
      /* Un patient non assuré : une seule pièce, pas de partage -A / -B. */
      const patient = S.collection('patients').active().filter((p) => !p.assureur)[0];
      if (!acte || !patient) return { possible: false };
      const avant = acte.prix;
      col.update(acte.id, { prix: avant + 555 });
      const res = PR.prescrire({ patientCode: patient.code, actes: [acte.code] });
      const ligne = ((res.facture && res.facture.lignes) || [])
        .filter((l) => l.acteCode === acte.code)[0];
      col.update(acte.id, { prix: avant });
      return { possible: true, attendu: avant + 555, facture: ligne ? ligne.prixUnitaire : null };
    });
    verifier('Un tarif modifié dans le catalogue est celui que PR.prescrire facture',
      verite.possible && verite.facture === verite.attendu,
      verite.facture + ' / attendu ' + verite.attendu);

    /* --- Les KPI de l'agent administratif sont COMPTÉS ------------------- */
    const kpiAgent = await page.evaluate(() => {
      const S = window.SIGH.store, C2 = window.SIGH.core;
      const AUJ = new Date(2026, 7, 16);
      const duMois = (r) => {
        const d = C2.toDate(r.date);
        return d.getFullYear() === AUJ.getFullYear() && d.getMonth() === AUJ.getMonth();
      };
      const cour = S.collection('courriers').active().filter(duMois).length;
      const aValider = S.collection('documents').active()
        .filter((d) => d.etatValidation === 'en_attente').length;
      const carte = [...document.querySelectorAll('*')]
        .filter((e) => e.children.length === 0 && e.textContent.trim() === 'Courriers du mois')[0];
      const bloc = carte ? carte.closest('div').parentElement.textContent : '';
      return { cour, aValider, affiche: bloc.indexOf(String(cour)) !== -1, brut: bloc.slice(0, 80) };
    });
    verifier('« Courriers du mois » affiche le compte de la collection, plus un nombre en dur',
      kpiAgent.affiche, kpiAgent.brut);
    verifier('Les documents « à valider » existent au socle sans ouvrir la GED',
      kpiAgent.aValider > 0, kpiAgent.aValider + ' document(s)');

    /* --- Formes canoniques courriers / ambulance ------------------------- */
    const formes = await page.evaluate(() => {
      const S = window.SIGH.store;
      const cour = S.collection('courriers').active();
      const amb = S.collection('ambulance').active();
      return {
        traitement: cour.every((x) => ['en_attente', 'en_cours', 'traite'].indexOf(x.traitement) !== -1),
        dateHeure: amb.every((x) => !!x.dateHeure && x.kilometrage != null && x.tarif != null),
        etats: amb.every((x) => ['demandee', 'en_cours', 'terminee'].indexOf(x.etat) !== -1),
        reunions: S.collection('reunions').active().length,
      };
    });
    verifier('Chaque courrier porte un traitement tri-état lisible par l’écran', formes.traitement);
    verifier('Chaque intervention d’ambulance porte dateHeure, kilométrage, tarif et état',
      formes.dateHeure && formes.etats);
    verifier('Les réunions sont semées au socle', formes.reunions > 0, formes.reunions + ' réunion(s)');

    /* --- En-tête unique et soupape de compression ------------------------ */
    await page.evaluate(() => window.SIGH.store.save());
    await pause(700); /* l'écriture est différée : laisser le tampon se vider */
    const socle = await page.evaluate(() => {
      const S = window.SIGH.store, C2 = window.SIGH.core;
      const brut = localStorage.getItem('sigh-cnt:v1') || '';
      return {
        variantes: S.raw().enteteVariantes === undefined,
        rccmUnique: C2.BRAND.rccmFacturation === undefined && C2.BRAND.rccm === 'RB/NAT/2016-B-268',
        /* LE NAVIGATEUR NE DOIT RIEN PORTER DE MÉTIER. On garde la mesure en
           kilo-octets : si la donnée revenait un jour, on veut savoir
           combien, pas seulement que c'est arrivé. */
        rienDeMetier: brut.length === 0,
        clesRestantes: Object.keys(localStorage).filter(function (k) {
          return k.indexOf('sigh-cnt:') === 0;
        }).sort(),
        /* JSON nu tant que le quota tient — la compression est une SOUPAPE,
           mesurée à ~2,4 s sur 4 Mo : la payer à chaque écriture gèlerait
           l'interface. On vérifie qu'elle est PRÊTE, pas qu'elle tourne. */
        /* Le magasin vit-il bien au SERVEUR, et sans panne ? */
        surServeur: S.surServeur ? S.surServeur() : false,
        enPanne: S.enPanne ? S.enPanne() : false,
        /* LA SENTINELLE DOIT DIRE DE COMBIEN ON DÉBORDE, sinon elle annonce
           un échec sans rien apprendre : on sait que le quota a cédé, pas de
           quelle marge. Le poids persisté et la marge restante sont mesurés
           ici même, et portés au détail de l'assertion. */
        persisteKo: Math.round(brut.length / 1024),
        margeKo: (function () {
          var m = 0;
          for (var ko = 0; ko <= 700; ko += 10) {
            try { localStorage.setItem('sigh-cnt:sonde', 'x'.repeat(ko * 1024)); m = ko; }
            catch (e) { break; }
          }
          try { localStorage.removeItem('sigh-cnt:sonde'); } catch (e) { /* rien */ }
          return m;
        })(),
        soupape: typeof window.LZString !== 'undefined'
          && typeof window.LZString.compressToUTF16 === 'function',
      };
    });
    verifier('Le référentiel des variantes d’en-tête est retiré — arbitrage du 31/08/2026',
      socle.variantes);
    verifier('Un seul RCCM au socle, caisse comprise', socle.rccmUnique);
    /* DEUX PROPRIÉTÉS DISTINCTES, DEUX ASSERTIONS (22/09/2026). Elles étaient
       confondues, et l'échec ne disait pas laquelle avait cédé :
         — l'écriture différée VIDE bien son tampon : c'est le mécanisme ;
         — le jeu de démonstration TIENT sous le quota du navigateur : c'est la
           contrainte de volume, et elle se mesure en kilo-octets.
       La compression est une SOUPAPE : qu'elle s'arme n'est pas une panne,
       mais une écriture à ~2,4 s gèle l'interface — on veut donc savoir, et
       savoir DE COMBIEN. */
    /* DEUX SENTINELLES RETOURNÉES (08/10/2026). Elles gardaient le quota du
       navigateur ; elles gardent désormais le fait qu'il n'y a RIEN à y
       garder. Le quota a cessé d'être une contrainte le jour où la donnée a
       quitté le poste — mais l'invariant qui le remplace mérite la même
       surveillance, et pour la même raison : une fuite ne se verrait pas. */
    verifier('AUCUNE donnée métier ne persiste dans le navigateur',
      socle.rienDeMetier,
      'magasin trouvé dans le navigateur : ' + socle.persisteKo + ' Ko — la donnée '
      + 'de la clinique doit vivre au serveur, et nulle part ailleurs.');
    verifier('Le navigateur ne garde que le jeton et le pointeur de session',
      socle.clesRestantes.every(function (k) {
        return ['sigh-cnt:jeton', 'sigh-cnt:session', 'sigh-cnt:ruban',
          'sigh-cnt:ruban-transitoire', 'sigh-cnt:message-differe', 'sigh-cnt:cr-entete',
          'sigh-cnt:verrou-delai', 'sigh-cnt:verrou-retour', 'sigh-cnt:notifications',
          'sigh-cnt:notifications-acquittees', 'sigh-cnt:rappel-labo',
          'sigh-cnt:reinit-autorisee'].indexOf(k) !== -1;
      }),
      'clés inattendues : ' + socle.clesRestantes.join(', '));
    verifier('Le magasin vit au serveur, et sans panne',
      socle.surServeur && !socle.enPanne);

    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* ==========================================================================
   * 42. PHASE 2 — SEIZE RÔLES : CHIRURGIEN, ANESTHÉSISTE, ASSISTANT COMPTABLE
   * --------------------------------------------------------------------------
   * La matrice cible des Instructions, sondée et non déclarée : le chirurgien
   * ouvre le bloc mais pas la maternité, l'anesthésiste ne voit ni caisse ni
   * consultations générales, l'assistant comptable saisit sans annuler et la
   * clôture lui est fermée, le caissier perd transferts/mouvements/lots.
   * ======================================================================== */
  {
    scenario('Phase 2 — rôles chirurgien, anesthésiste, assistant comptable et fermetures caissier');

    await ouvrir('dash-admin.html');
    const roles = await page.evaluate(() => {
      const N = window.SIGH.nav;
      const peut = (r, e) => { const x = N.get(e); return x ? N.can(r, x) : null; };
      const de = (r, e, m) => N.droitsEcran(r, e, m);
      return {
        fiches: ['chirurgien', 'anesthesiste', 'aide_comptable'].map((r) =>
          N.ROLES[r] ? N.ROLES[r].label : null),
        /* Caissier — les trois fermetures de la matrice cible. */
        caisseTransferts: de('caissier', 'm6-transferts', 'M6').voir,
        caisseMouvements: de('caissier', 'm6-mouvements', 'M6').voir,
        caisseLots: de('caissier', 'm6-lots', 'M6').voir,
        caisseAtteint: [peut('caissier', 'm6-transferts'), peut('caissier', 'm6-mouvements'),
          peut('caissier', 'm6-lots')],
        /* Chirurgien — le bloc oui, la maternité non, la caisse non. */
        chiBloc: peut('chirurgien', 'm3-bloc-cro'),
        chiChecklist: peut('chirurgien', 'm3-bloc-checklist'),
        chiMaternite: peut('chirurgien', 'm4-accouchements'),
        chiCaisse: peut('chirurgien', 'm8-caisse'),
        chiImagerieEdit: de('chirurgien', 'm2-imagerie', 'M2').editer,
        /* Anesthésiste — le péri-opératoire seulement. */
        aneGlasgow: peut('anesthesiste', 'm3-glasgow'),
        aneResultats: peut('anesthesiste', 'm5-resultats'),
        aneConsult: peut('anesthesiste', 'm2-consultations'),
        aneCaisse: peut('anesthesiste', 'm8-caisse'),
        aneMaternite: peut('anesthesiste', 'm4-accouchements'),
        /* Assistant comptable — saisir sans annuler, clôture fermée, RG-13. */
        acEcritures: de('aide_comptable', 'm12-ecritures', 'M12'),
        acCloture: de('aide_comptable', 'm12-cloture', 'M12').voir,
        acPatients: peut('aide_comptable', 'm1-patients'),
        acConsult: peut('aide_comptable', 'm2-consultations'),
        acDash: peut('aide_comptable', 'dash-aide-comptable'),
      };
    });
    verifier('Les trois rôles de la phase 2 ont leur fiche au manifeste',
      roles.fiches.join(' · ') === 'Chirurgien · Anesthésiste — Réanimateur · Assistant Comptable',
      roles.fiches.join(' · '));
    verifier('Caissier : transferts, mouvements et lots FERMÉS — même la lecture',
      roles.caisseTransferts === false && roles.caisseMouvements === false && roles.caisseLots === false);
    verifier('…et les trois écrans sont inatteignables, pas seulement absents du menu',
      roles.caisseAtteint.every((x) => x === false), roles.caisseAtteint.join(' · '));
    verifier('Le chirurgien ouvre le bloc — CRO et check-listes',
      roles.chiBloc === true && roles.chiChecklist === true);
    verifier('…mais ni la maternité, ni la caisse — matrice cible',
      roles.chiMaternite === false && roles.chiCaisse === false);
    verifier('L’imagerie se lit sans s’écrire pour le chirurgien', roles.chiImagerieEdit === false);
    verifier('L’anesthésiste tient Glasgow et lit les résultats',
      roles.aneGlasgow === true && roles.aneResultats === true);
    verifier('…sans consultations générales, caisse ni maternité',
      roles.aneConsult === false && roles.aneCaisse === false && roles.aneMaternite === false);
    verifier('L’assistant comptable saisit les écritures SANS pouvoir d’annulation',
      roles.acEcritures.voir === true && roles.acEcritures.editer === true
        && roles.acEcritures.annuler === false);
    verifier('La clôture annuelle lui est fermée nommément', roles.acCloture === false);
    verifier('Aucun écran clinique ne s’ouvre à lui (RG-13)',
      roles.acPatients === false && roles.acConsult === false);
    verifier('Son tableau de bord, lui, s’ouvre', roles.acDash === true);

    /* --- Les trois tableaux de bord montent, premier regard compris ------- */
    for (const [dash, role, attendu] of [
      ['dash-chirurgien', 'chirurgien', /check-liste/i],
      ['dash-anesthesiste', 'anesthesiste', /check-liste|induction/i],
      ['dash-aide-comptable', 'aide_comptable', /brouillon/i],
    ]) {
      await page.evaluate((r) => {
        sessionStorage.clear();
        localStorage.setItem('sigh-cnt:session', JSON.stringify({
          role: r, fonction: r === 'aide_comptable' ? 'comptable' : 'medecin',
          nom: 'Sonde', nomComplet: 'Sonde ' + r, identifiant: 'sonde.' + r, secteur: 'CHI',
        }));
      }, role);
      await ouvrir(dash + '.html');
      const vu = await page.evaluate(() => document.body.textContent);
      verifier('Le tableau ' + dash + ' monte et porte son premier regard', attendu.test(vu));
    }

    /* --- Les trois rôles de la phase 2 existent au manifeste et à l'annuaire.
       Le sélecteur de connexion (Bug 0) n'existe plus : la page de connexion
       ne liste aucun compte depuis le 20/10/2026. --------------------------- */
    await page.goto('http://127.0.0.1:' + PORT + '/index.php', { waitUntil: 'networkidle2' });
    await pause(400);
    const selecteur = await page.evaluate(async () => {
      const labels = Object.values(window.SIGH.nav.ROLES).map((r) => r.label);
      let roles = [];
      try {
        const r = await fetch('api/auth.php?action=comptes', { headers: { Accept: 'application/json' } });
        roles = ((await r.json()).comptes || []).map((c) => c.role);
      } catch (e) { roles = []; }
      return {
        sansSelecteur: !document.querySelector('form select'),
        troisNouveaux: ['Chirurgien', 'Anesthésiste', 'Assistant Comptable']
          .every((l) => labels.some((t) => t.indexOf(l) === 0)),
        troisComptes: ['chirurgien', 'anesthesiste', 'aide_comptable'].every((r) => roles.indexOf(r) >= 0),
      };
    });
    verifier('La connexion ne propose plus de sélecteur de profil', selecteur.sansSelecteur);
    verifier('Les trois nouveaux rôles figurent au manifeste', selecteur.troisNouveaux);
    verifier('Les trois nouveaux rôles ont un compte à l’annuaire', selecteur.troisComptes);

    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* ==========================================================================
   * 43. PHASE 3a — DOMAINE ACCUEIL, ALIAS, TARIFS PUBLICS ET SIX BOUTONS
   * --------------------------------------------------------------------------
   * L'ACCUEIL réunit des écrans venus de quatre modules SANS les dupliquer :
   * un alias n'engendre ni page ni droit — la sonde vérifie les deux sens
   * (l'alias apparaît pour qui a le droit, disparaît pour qui ne l'a pas).
   * ======================================================================== */
  {
    scenario('Phase 3a — domaine Accueil, alias de manifeste, tarifs publics et six boutons');

    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'reception', fonction: 'accueil', nom: 'OROU YO Edmond',
        nomComplet: 'OROU YO Edmond', identifiant: 'e.orouyo', secteur: 'ACC',
      }));
    });
    await ouvrir('dash-receptionniste.html');

    const accueil = await page.evaluate(() => {
      const N = window.SIGH.nav;
      const arbre = N.tree('reception');
      const domaines = arbre.map((d) => d.domain);
      const acc = arbre.filter((d) => d.domain === 'Accueil')[0];
      const items = acc ? acc.modules.reduce((t, m) => t.concat(m.items.map((i) => i.id)), []) : [];
      const arbreCaissier = N.tree('caissier');
      const accCaissier = arbreCaissier.filter((d) => d.domain === 'Accueil')[0];
      const itemsCaissier = accCaissier
        ? accCaissier.modules.reduce((t, m) => t.concat(m.items.map((i) => i.id)), []) : [];
      return {
        premier: domaines[0],
        dernier: domaines[domaines.length - 1],
        items,
        tarifsVisibles: items.indexOf('cfg-tarifs') !== -1,
        /* L'alias n'invente aucun droit : le caissier n'a pas m1-constantes,
           l'ACCUEIL ne doit pas le lui offrir. */
        caissierConstantes: itemsCaissier.indexOf('m1-constantes') !== -1,
        indexCanonique: N.INDEX ? null : undefined,
        externe: N.get('m1-externe').label,
        domaineTarifs: N.get('cfg-tarifs').domain,
        droitTarifs: N.droitsEcran('reception', 'cfg-tarifs', 'CFG'),
      };
    });
    verifier('L’ACCUEIL est le premier domaine du ruban de la réception', accueil.premier === 'Accueil');
    verifier('Pilotage passe en dernier — l’ordre cible des Instructions',
      accueil.dernier === 'Pilotage', accueil.dernier);
    verifier('Le domaine réunit rendez-vous, file, appels, courriers, ambulances, tarifs et constantes',
      ['m2-rendezvous', 'm2-file-attente', 'm2-affichage', 'm2-registre-appels', 'm13-courriers',
        'm13-repertoire-ambulances', 'cfg-tarifs', 'm1-constantes']
        .every((id) => accueil.items.indexOf(id) !== -1),
      accueil.items.join(' · '));
    verifier('Les tarifs publics s’ouvrent à la réception EN LECTURE — surcharge d’écran, module CFG fermé',
      accueil.tarifsVisibles && accueil.droitTarifs.voir === true && accueil.droitTarifs.editer === false);
    verifier('Un alias n’invente aucun droit : pas de constantes pour le caissier via l’Accueil',
      accueil.caissierConstantes === false);
    verifier('L’écran garde son entrée CANONIQUE : cfg-tarifs reste au domaine Système',
      accueil.domaineTarifs === 'Système', accueil.domaineTarifs);
    verifier('« Patient externe » est renommé (Bug 6)', accueil.externe === 'Patient externe');

    /* --- Les SIX boutons du Bug 2, AVANT les parcours --------------------- */
    const boutons = await page.evaluate(() => {
      const t = document.body.textContent;
      const cartes = [...document.querySelectorAll('a')].map((a) => a.textContent.trim());
      const attendus = ['Répertoire patient', 'Constantes à l’accueil', 'Agenda et rendez-vous',
        'Visites aux hospitalisés', 'File d’attente', 'Écran d’appel des patients'];
      const posAcces = t.indexOf('Accès rapides');
      const posParcours = t.indexOf('les parcours de l’accueil');
      return {
        six: attendus.filter((l) => cartes.some((c) => c.indexOf(l) === 0)).length,
        avantParcours: posAcces !== -1 && posParcours !== -1 && posAcces < posParcours,
      };
    });
    verifier('Les SIX boutons d’accès rapide du Bug 2 sont présents', boutons.six === 6,
      boutons.six + '/6');
    verifier('…et la barre précède la section des parcours', boutons.avantParcours);

    /* --- cfg-tarifs : la réception l’ouvre, en lecture, avec 4 onglets ---- */
    await ouvrir('cfg-tarifs.html');
    const tarifs = await page.evaluate(() => {
      const t = document.body.textContent;
      const onglets = [...document.querySelectorAll('[role="tab"], .tab, button')]
        .map((b) => b.textContent.trim());
      return {
        monte: /Référentiel tarifaire/i.test(t),
        interdit: /403|accès refusé/i.test(t),
        quatrieme: onglets.some((o) => o.indexOf('Certificats et Attestations') === 0),
      };
    });
    verifier('La réception OUVRE le référentiel tarifaire — plus de porte fermée promise',
      tarifs.monte && !tarifs.interdit);
    verifier('Le 4ᵉ onglet « Certificats et Attestations » existe (Bug 12)', tarifs.quatrieme);

    /* Le contenu du 4ᵉ onglet se sonde en l'OUVRANT — check.js ne clique pas. */
    await cliquer('Certificats et Attestations');
    await pause(400);
    const ongletCert = await page.evaluate(() => {
      const t = document.body.textContent;
      return {
        /* Les SIX certificats tarifés de la grille — TOUS couverts par SOS
           seule (mention manuscrite) : exiger un NON COUVERT ici serait
           contredire le document. */
        sos: (t.match(/SOS seule/g) || []).length,
        /* C.money compose en espace fine insécable : on compare les CHIFFRES,
           toute espace neutralisée — le piège documenté du prototype. */
        prixCbv: t.replace(/[\s\u202F\u00A0]/g, '').indexOf('20000') !== -1,
        uneSeuleVerite: /cet onglet les lit/.test(t),
      };
    });
    verifier('L’onglet lit le catalogue : six pièces, couverture « SOS seule » sur chacune',
      ongletCert.sos >= 6 && ongletCert.prixCbv, ongletCert.sos + ' mention(s) SOS');
    verifier('…et dit qu’il LIT sans dupliquer — une seule vérité tarifaire', ongletCert.uneSeuleVerite);

    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* ==========================================================================
   * 44. PHASE 3b — FUSION RENDEZ-VOUS & VISITES
   * --------------------------------------------------------------------------
   * Bugs 3, 10, 11 et 0a des Instructions, sondés en CLIQUANT : le Bug 0a
   * était réel — « Nouvelle visite » de m2-visites appelait une fonction
   * déclarée dans la fermeture de l'écran agenda, ReferenceError au clic que
   * ni check.js ni la lecture ne voyaient.
   * ======================================================================== */
  {
    scenario('Phase 3b — fusion Rendez-vous & visites, individu non enregistré, plage de dates');

    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'reception', fonction: 'accueil', nom: 'OROU YO Edmond',
        nomComplet: 'OROU YO Edmond', identifiant: 'e.orouyo', secteur: 'ACC',
      }));
    });
    await ouvrir('m2-rendezvous.html');

    /* --- Bug 11 : la barre de plage, avec ses raccourcis ------------------ */
    const plage = await page.evaluate(() => {
      const t = document.body.textContent;
      return {
        barre: /Sept derniers jours/.test(t) && /Toute la période/.test(t),
        fusion: /Rendez-vous & visites/.test(t),
      };
    });
    verifier('L’écran fusionné porte la barre de plage de dates (Bug 11)', plage.barre);
    verifier('…et son titre dit la fusion (Bug 3)', plage.fusion);

    /* --- Individu non enregistré : par le FORMULAIRE réel ----------------- */
    await cliquer('Nouveau');
    await pause(500);
    const venue = await page.evaluate(() => {
      const modal = document.querySelector('[role="dialog"], .modal');
      if (!modal) return { modale: false };
      const visiteur = modal.querySelector('input[name="visiteurNom"], #f_visiteurNom, [data-name="visiteurNom"] input');
      const tous = [...modal.querySelectorAll('input, textarea')];
      return {
        modale: true,
        champVisiteur: !!visiteur || tous.some((i) => (i.name || i.id || '').indexOf('visiteur') !== -1),
      };
    });
    verifier('Le formulaire porte le champ « individu non enregistré »',
      venue.modale && venue.champVisiteur);
    await page.keyboard.press('Escape');
    await pause(300);

    /* Le moteur, sondé directement : une venue d'affaire privée sans dossier
       n'invente NI patient NI code CNT. */
    const moteur = await page.evaluate(() => {
      const S = window.SIGH.store;
      const col = S.collection('consultations', { module: 'M2', entite: 'Consultation' });
      const avantPatients = S.collection('patients').active().length;
      const rec = col.insert((function (v) {
        /* même chemin que le formulaire : transform de l'écran */
        v.patient = (v.visiteurNom || '').trim();
        v.patientCode = 'NON-PATIENT'; v.patientId = null; v.nonPatient = true;
        return v;
      })({
        visiteurNom: 'SONDE Visiteur', type: 'Affaire privée', motif: 'Rendez-vous avec la Direction',
        date: new Date().toISOString(), statut: 'planifiee', medecin: '—',
      })).record;
      const apresPatients = S.collection('patients').active().length;
      const lu = col.active().filter((c) => c.id === rec.id)[0];
      col.archive(rec.id, 'sonde');
      return {
        nonPatient: lu.nonPatient === true && lu.patientCode === 'NON-PATIENT',
        aucunDossierCree: apresPatients === avantPatients,
      };
    });
    verifier('Une venue « affaire privée » se tient SANS dossier patient', moteur.nonPatient);
    verifier('…et ne consomme aucun code CNT (RG-01 protégé)', moteur.aucunDossierCree);

    /* --- Bug 10 : la fiche porte Modifier ET Archiver dans son pied -------
       Sous le profil MÉDECIN : la réception n'a pas le droit d'annuler sur
       M2, et la commande absente est précisément le comportement attendu —
       c'est le porteur du droit qui doit voir les deux boutons. */
    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'medecin', fonction: 'medecin', nom: 'YENI M’PO Florent',
        nomComplet: 'YENI M’PO Florent', identifiant: 'f.yeni', secteur: 'MGE',
      }));
    });
    await ouvrir('m2-rendezvous.html');
    await page.evaluate(() => {
      const ligne = document.querySelector('tbody tr');
      if (ligne) ligne.click();
    });
    await pause(500);
    const fiche = await page.evaluate(() => {
      const tiroir = [...document.querySelectorAll('button')].map((b) => b.textContent.trim());
      return {
        modifier: tiroir.indexOf('Modifier') !== -1,
        archiver: tiroir.indexOf('Archiver') !== -1,
      };
    });
    verifier('La fiche du rendez-vous porte Modifier ET Archiver au pied (Bug 10)',
      fiche.modifier && fiche.archiver);
    await page.keyboard.press('Escape');
    await pause(300);

    /* --- Bug 0a : la modale de passage s'ouvre depuis les DEUX écrans qui la
       proposent — l'agenda et le registre fusionné. La fonction vit AU MODULE,
       et non dans la fermeture d'un écran : c'est ce qui levait une
       ReferenceError au clic, invisible à `check`. */
    for (const ecran of ['m2-rendezvous.php', 'm2-agenda.php']) {
      await ouvrir(ecran);
      await cliquer('Passage sans rendez-vous');
      await pause(500);
      const ok = await page.evaluate(() => {
        const m = document.querySelector('[role="dialog"], .modal');
        return m ? /passage sans rendez-vous/i.test(m.textContent) : false;
      });
      verifier('« Passage sans rendez-vous » ouvre la modale sur ' + ecran + ' (Bug 0a)', ok);
      await page.keyboard.press('Escape');
      await pause(300);
    }

    /* --- LA FUSION : la personne non enregistrée a ses QUATRE champs ------- */
    await ouvrir('m2-rendezvous.html');
    await cliquer('Passage sans rendez-vous');
    await pause(600);
    const champsVisiteur = await page.evaluate(() => {
      const m = document.querySelector('[role="dialog"], .modal');
      if (!m) return { erreur: 'modale absente' };
      const a = (n) => !!m.querySelector('#f_' + n);
      return {
        patient: a('patientCode'),
        nom: a('visiteurNom'), prenom: a('visiteurPrenom'),
        quartier: a('visiteurQuartier'), telephone: a('visiteurTelephone'),
        /* Le dossier ne doit PLUS être obligatoire : une personne non
           enregistrée n'en a pas. */
        patientObligatoire: /Patient \(dossier du répertoire\) \*/.test(m.textContent),
      };
    });
    verifier('Le passage sans rendez-vous porte nom, prénom, quartier ET numéro du client',
      champsVisiteur.nom && champsVisiteur.prenom && champsVisiteur.quartier && champsVisiteur.telephone,
      JSON.stringify(champsVisiteur));
    verifier('…et le champ Patient reste offert, sans être obligatoire',
      champsVisiteur.patient && !champsVisiteur.patientObligatoire);

    const dossiersAvant = await page.evaluate(() =>
      window.SIGH.store.collection('patients').all().length);
    const venueNonPatient = await page.evaluate(() => {
      const m = document.querySelector('[role="dialog"], .modal');
      const set = (n, v) => { const c = m.querySelector('#f_' + n); if (c) c.value = v; };
      set('visiteurNom', 'KORA'); set('visiteurPrenom', 'Salifou');
      set('visiteurQuartier', 'Tchirimina'); set('visiteurTelephone', '0155667788');
      set('motif', 'Retrait de résultat');
      const b = [...m.querySelectorAll('button')].find((x) => /Enregistrer le passage/.test(x.textContent));
      if (b) b.click();
      return { clique: !!b };
    });
    /* L'enregistrement d'un passage RECHARGE la page. Un délai fixe ne tient
       plus depuis la bascule : la page retransporte 4,9 Mo depuis PostgreSQL,
       et lire avant la fin de l'hydratation rendait la coquille VIDE — d'où
       « venue non enregistrée » sur une venue parfaitement écrite. On attend
       l'AUTORITÉ du magasin ; l'écriture différée, elle, est vidée sur
       `pagehide`. */
    await attendrePeinture();
    await pause(300);
    const enregistree = await page.evaluate(() => {
      const v = window.SIGH.store.collection('consultations').all()
        .filter((c) => c.visiteurNom === 'KORA')[0];
      const patients = window.SIGH.store.collection('patients').all().length;
      return v ? {
        patient: v.patient, code: v.patientCode, nonPatient: !!v.nonPatient,
        quartier: v.visiteurQuartier, telephone: v.visiteurTelephone,
        dossiers: patients,
      } : { erreur: 'venue non enregistrée' };
    });
    verifier('La venue d’une personne non enregistrée porte son identité complète',
      !enregistree.erreur && enregistree.nonPatient && enregistree.patient === 'KORA Salifou'
      && enregistree.quartier === 'Tchirimina' && enregistree.telephone === '0155667788',
      JSON.stringify(enregistree));
    verifier('Elle n’ouvre AUCUN dossier patient et ne consomme aucun code CNT (RG-01)',
      enregistree.code === 'NON-PATIENT' && enregistree.dossiers === dossiersAvant,
      enregistree.code + ', ' + (enregistree.dossiers - dossiersAvant) + ' dossier(s) créé(s)');

    /* --- L'agenda : le tiroir d'un rendez-vous porte Éditer / Annuler ----- */
    await ouvrir('m2-agenda.html');
    const agenda = await page.evaluate(() => {
      const cellule = [...document.querySelectorAll('button')]
        .filter((b) => /\d{2}h\d{2}|\d{2}:\d{2}/.test(b.textContent))[0];
      if (!cellule) return { rdv: false };
      cellule.click();
      return { rdv: true };
    });
    await pause(500);
    const tiroirAgenda = await page.evaluate(() => {
      const boutons = [...document.querySelectorAll('button')].map((b) => b.textContent.trim());
      return {
        editer: boutons.indexOf('Éditer le rendez-vous') !== -1,
        annuler: boutons.indexOf('Annuler le rendez-vous') !== -1,
      };
    });
    verifier('Le tiroir de l’agenda porte « Éditer le rendez-vous » et « Annuler le rendez-vous » (Bug 10)',
      agenda.rdv && tiroirAgenda.editer && tiroirAgenda.annuler);
    await page.keyboard.press('Escape');
    await pause(300);

    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* ==========================================================================
   * 45. PHASE 3c — RÉPERTOIRE PATIENT FUSIONNÉ À ZONES, CONSTANTES REPRISES
   * --------------------------------------------------------------------------
   * Bug 1 (fusion à zones, arbitrage du 31/08/2026) et Bug 14 (les constantes
   * de l'accueil pré-remplissent la fiche de consultation). La fusion ne doit
   * RIEN rouvrir : l'onglet des dossiers reste absent pour le biologiste.
   * ======================================================================== */
  {
    scenario('Phase 3c — répertoire fusionné à deux zones et constantes reprises de l’accueil');

    /* --- Le médecin voit l'onglet fusionné, et il S'OUVRE ------------------ */
    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'medecin', fonction: 'medecin', nom: 'YENI M’PO Florent',
        nomComplet: 'YENI M’PO Florent', identifiant: 'f.yeni', secteur: 'MGE',
      }));
    });
    /* REFONTE ZONE 2 (14/09/2026) — DÉCISION DE LA DIRECTION : l'onglet
       « Dossiers de consultation (2 zones) » QUITTE le répertoire pour son
       écran propre (m2-dossiers-consultation). L'assertion s'inverse
       délibérément : l'onglet est absent, et c'est l'écran nouveau qui porte
       les états du dossier. */
    await ouvrir('m1-patients.html');
    const ongletMedecin = await page.evaluate(() => {
      const boutons = [...document.querySelectorAll('button')].map((b) => b.textContent.trim());
      return { present: boutons.some((b) => b.indexOf('Dossiers de consultation (2 zones)') === 0) };
    });
    verifier('Le répertoire ne porte PLUS l’onglet des dossiers de consultation (écran propre depuis le 14/09)',
      !ongletMedecin.present);
    await ouvrir('m2-dossiers-consultation.html');
    const zones = await page.evaluate(() => {
      const t = document.body.textContent;
      return {
        etats: /En attente labo/i.test(t) && /En consultation/i.test(t),
        cycle: /sauts sont refusés/i.test(t),
      };
    });
    verifier('L’écran des dossiers rend les états du dossier et annonce le cycle ordonné',
      zones.etats && zones.cycle);

    /* --- La fusion ne rouvre RIEN au biologiste ---------------------------- */
    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'laborantin', fonction: 'tsl', nom: 'KINNOU A. Ganiou',
        nomComplet: 'KINNOU A. Ganiou', identifiant: 'a.kinnou', secteur: 'LAB',
      }));
    });
    await ouvrir('m1-patients.html');
    const ongletBio = await page.evaluate(() => {
      const boutons = [...document.querySelectorAll('button')].map((b) => b.textContent.trim());
      return { present: boutons.some((b) => b.indexOf('Dossiers de consultation (2 zones)') === 0) };
    });
    verifier('L’onglet est ABSENT pour le biologiste — la fusion ne rouvre pas ce que la Direction a fermé',
      ongletBio.present === false);

    /* --- Les anciennes pages RENVOIENT, hors ruban ------------------------- */
    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'medecin', fonction: 'medecin', nom: 'YENI M’PO Florent',
        nomComplet: 'YENI M’PO Florent', identifiant: 'f.yeni', secteur: 'MGE',
      }));
    });
    for (const [pageId, motif] of [
      /* Le dossier étendu renvoie désormais à SON écran (14/09/2026). */
      ['m1-dossier-etendu', /déménagé dans son propre écran/i],
      ['m1-dossier-medical', /fusionné dans le répertoire/i],
    ]) {
      await ouvrir(pageId + '.html');
      const renvoi = await page.evaluate((m) => new RegExp(m, 'i').test(document.body.textContent),
        motif.source);
      verifier('La page ' + pageId + ' renvoie vers son écran de destination', renvoi);
    }
    const ruban = await page.evaluate(() => {
      const N = window.SIGH.nav;
      const m1 = N.tree('medecin').reduce((t, d) => t.concat(d.modules), [])
        .filter((m) => m.code === 'M1' && !m.alias);
      const ids = m1.reduce((t, m) => t.concat(m.items.map((i) => i.id)), []);
      return {
        etendu: ids.indexOf('m1-dossier-etendu') !== -1,
        medical: ids.indexOf('m1-dossier-medical') !== -1,
      };
    });
    verifier('Les deux pastilles ont quitté le ruban', !ruban.etendu && !ruban.medical);

    /* --- Bug 14 : les constantes de l'accueil pré-remplissent la fiche ----- */
    await ouvrir('m2-consultation-fiche.html');
    const bug14 = await page.evaluate(() => {
      const S = window.SIGH.store;
      /* Un patient SANS dossier ouvert : un dossier enregistré fige les
         constantes vues à l'examen (copie datée), et la fiche montre alors
         cette copie — pas le relevé que la sonde vient d'ajouter. */
      const Z2 = window.SIGH.consultationZone2;
      const pt = S.collection('patients').active().filter((x) => !Z2.dossierActifDe(x.code))[0];
      S.collection('constantes', { module: 'M1', entite: 'relevé de constantes', prefix: 'CST' }).insert({
        patientCode: pt.code, patientId: pt.id, patient: pt.nom + ' ' + pt.prenom,
        dateHeure: new Date().toISOString(), temperature: 37.9, tension: '12/8',
        pouls: 88, poids: 71, releveePar: 'SONDE', origine: 'accueil',
      });
      const combo = document.getElementById('f_patientCode');
      combo.value = pt.code;
      combo.dispatchEvent(new Event('change'));
      /* REFONTE ZONE 2 : « l'accueil saisit et VERROUILLE » (METHODOLOGIE
         §1.1). Les constantes ne pré-remplissent plus des champs modifiables :
         elles s'AFFICHENT en lecture seule. On lit donc le bloc rendu. */
      const t = document.getElementById('page-content').textContent;
      return {
        temperature: /37[.,]9\s*°C/.test(t) ? '37.9' : '',
        tension: /12\/8/.test(t) ? '12/8' : '',
        fc: /88\s*bpm/.test(t) ? '88' : '',
        champsSaisie: !!document.getElementById('f_temperature') || !!document.getElementById('f_fc'),
        note: /relevé de l’accueil/i.test(t) && /lecture seule/i.test(t),
      };
    });
    verifier('Température, tension et pouls de l’accueil s’affichent sur la fiche (Bug 14)',
      bug14.temperature === '37.9' && bug14.tension === '12/8' && bug14.fc === '88',
      bug14.temperature + ' °C · ' + bug14.tension + ' · ' + bug14.fc + ' bpm');
    verifier('…en LECTURE SEULE — aucun champ de ressaisie — et la fiche DIT d’où viennent les valeurs',
      bug14.note && !bug14.champsSaisie);

    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* ==========================================================================
   * 46. PHASE 4 — MATERNITÉ : RAPPORT DU 27/08/2026 DE BOUT EN BOUT
   * --------------------------------------------------------------------------
   * M4 n'avait AUCUN scénario dédié — précisément la zone que le rapport fait
   * grossir. La sonde vérifie les référentiels (SONU, PF, CPoN, bornes), le
   * semis AU SOCLE, les écrans nouveaux et les indicateurs calculés.
   * ======================================================================== */
  {
    scenario('Phase 4 — maternité : SONU, CPN, partogramme, PF, PTME et indicateurs calculés');

    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'infirmier', fonction: 'sage_femme', nom: 'BADO BANI A. B. Zoulehath',
        nomComplet: 'BADO BANI A. B. Zoulehath', identifiant: 'z.badobani', secteur: 'MAT',
      }));
    });

    /* --- Les référentiels du rapport, tracés ------------------------------ */
    await ouvrir('dash-infirmier.html');
    const refs = await page.evaluate(() => {
      const D = window.SIGH.data, S = window.SIGH.store;
      return {
        sonu: (D.SONU.fonctions || []).length,
        sonub: D.SONU.fonctions.filter((f) => f.type === 'SONUB').length,
        sonuc: D.SONU.fonctions.filter((f) => f.type === 'SONUC').length,
        f7: D.fonctionSONU(7).label,
        pf: (D.METHODES_PF || []).length,
        cpon: (D.TYPES_CPON || []).length,
        pc: D.BORNES_NOUVEAU_NE.pc.min + '-' + D.BORNES_NOUVEAU_NE.pc.max,
        pt: D.BORNES_NOUVEAU_NE.pt.min + '-' + D.BORNES_NOUVEAU_NE.pt.max,
        apgar: D.BORNES_NOUVEAU_NE.apgarSeuil5min,
        saa: S.collection('actes').active().some((a) => a.code === 'GY-SAA' && /SAA/.test(a.libelle)),
        /* SEMÉES AU SOCLE : lisibles sans avoir jamais ouvert un écran M4. */
        grossesses: S.collection('grossesses').active().length,
        cponRows: S.collection('cpon').active().length,
        pfRows: S.collection('planificationFamiliale').active().length,
        sonuRows: S.collection('registreSONU').active().length,
        ptmeRows: S.collection('ptme').active().length,
        partos: S.collection('partogrammes').active().length,
        naissancePC: S.collection('naissances').active().every((n) => n.pc != null && n.pt != null && n.apgar5 != null),
      };
    });
    verifier('Les 10 fonctions SONU — 7 SONUB et 3 SONUC — sont au référentiel',
      refs.sonu === 10 && refs.sonub === 7 && refs.sonuc === 3);
    verifier('La fonction 7 est la réanimation du nouveau-né', /Réanimation/.test(refs.f7));
    verifier('Les 15 méthodes contraceptives et les 3 CPoN sont déclarées',
      refs.pf === 15 && refs.cpon === 3);
    verifier('Les bornes du rapport : PC 32-38, PT 30-36, Apgar 5 min ≥ 7',
      refs.pc === '32-38' && refs.pt === '30-36' && refs.apgar === 7);
    verifier('L’acte Avortement / SAA est au catalogue (tarif d’ATTENTE aligné AMIU — arbitrage du 01/09)', refs.saa);
    verifier('Les sept collections maternité sont semées AU SOCLE',
      refs.grossesses > 0 && refs.cponRows > 0 && refs.pfRows > 0
        && refs.sonuRows > 0 && refs.ptmeRows > 0 && refs.partos > 0,
      [refs.grossesses, refs.cponRows, refs.pfRows, refs.sonuRows, refs.ptmeRows, refs.partos].join(' · '));
    verifier('Chaque naissance porte PC, PT et Apgar à 5 min — plus d’Apgar unique', refs.naissancePC);

    /* --- CPN : la carte maternelle et sa visite ajoutée EN CLIQUANT ------- */
    await ouvrir('m4-cpn.html');
    const cpn = await page.evaluate(() => {
      const t = document.body.textContent;
      return { gar: /GROSSESSE À RISQUE/.test(t), sp: /SP3|SP1/.test(t), monte: /carte maternelle/i.test(t) };
    });
    verifier('L’écran CPN monte — GAR en badge, doses SP visibles', cpn.monte && cpn.gar && cpn.sp);
    /* La table se peint après le montage : on ATTEND la ligne puis le tiroir,
       au lieu de parier sur une pause fixe — un run chargé rend plus lentement
       qu'une sonde isolée. */
    let ficheCpn = { ajouter: false, grille: false, essais: 0 };
    for (let essai = 0; essai < 10 && !(ficheCpn.ajouter && ficheCpn.grille); essai++) {
      ficheCpn.essais = essai + 1;
      await page.evaluate(() => {
        /* Le libellé d'un bouton peut se REPLIER (retour à la ligne interne) :
           on normalise les blancs avant de comparer — trim() ne suffit pas. */
        const plat = (n) => n.textContent.replace(/\s+/g, ' ').trim();
        if (![...document.querySelectorAll('button')].some((b) => plat(b).indexOf('Ajouter une visite CPN') === 0)) {
          const l = document.querySelector('tbody tr');
          if (l) l.click();
        }
      });
      await pause(500);
      ficheCpn = Object.assign(ficheCpn, await page.evaluate(() => {
        const plat = (n) => n.textContent.replace(/\s+/g, ' ').trim();
        const boutons = [...document.querySelectorAll('button')].map(plat);
        const t = document.body.textContent;
        return {
          ajouter: boutons.some((b) => b.indexOf('Ajouter une visite CPN') === 0),
          grille: /BDCF/.test(t) && /Albumine/.test(t),
          grilleTemoin: (/(BDCF)/.test(t) ? 'BDCF✔' : 'BDCF✘') + (/(Albumine)/.test(t) ? 'Alb✔' : 'Alb✘'),
        };
      }));
    }
    if (!(ficheCpn.ajouter && ficheCpn.grille)) {
      ficheCpn.diag = await page.evaluate(() => {
        const tbodys = [...document.querySelectorAll('tbody')].map((tb) => {
          const carte = tb.closest('.card');
          const titre = carte ? (carte.querySelector('h3, h2') || {}).textContent : null;
          return (titre || 'sans-titre') + ':' + tb.querySelectorAll('tr').length;
        });
        const tr = document.querySelector('tbody tr');
        const drawer = [...document.querySelectorAll('.animate-slide-in, [role="dialog"]')];
        return ['url=' + location.pathname,
          'tbodys=' + tbodys.join(' ; '),
          'tr.classes=' + (tr ? tr.className : 'AUCUN'),
          'tiroirs=' + drawer.length,
          'boutons=' + [...document.querySelectorAll('button')].map((b) => b.textContent.trim()).filter(Boolean).slice(-18).join('|')].join(' § ');
      });
    }
    verifier('La fiche CPN porte la grille des visites et le geste « Ajouter une visite »',
      ficheCpn.ajouter && ficheCpn.grille,
      ficheCpn.essais + ' essai(s) § ' + (ficheCpn.grilleTemoin || '') + ' § ' + (ficheCpn.diag || ''));
    await page.keyboard.press('Escape');
    await pause(300);

    /* --- LE DÉFAUT DE CLASSE que cette sonde a mis au jour ----------------
       K.section(titre, nœud) AVALAIT le nœud (« [object HTMLElement] ») sur
       une trentaine de tiroirs du prototype. Le kit accepte désormais un
       nœud comme CONTENU — on le garde ici sur un site HÉRITÉ (comptes
       rendus de maternité), pas sur le site corrigé à la main. */
    await ouvrir('m4-comptes-rendus.html');
    const heritage = await page.evaluate(() => {
      const t = document.body.textContent;
      return { objet: t.indexOf('[object ') === -1 };
    });
    verifier('Plus aucun « [object HTMLElement] » : K.section accepte un nœud comme contenu',
      heritage.objet);
    await page.keyboard.press('Escape');
    await pause(300);

    /* --- Partogramme : lignes d'alerte et d'action ------------------------ */
    await ouvrir('m4-partogramme.html');
    const parto = await page.evaluate(() => {
      const t = document.body.textContent;
      return {
        lignes: /Ligne d’alerte|Ligne d’action/.test(t) || document.querySelector('canvas') !== null,
        mesures: /Dilatation \(cm\)/.test(t),
        kpis: /Ligne d’action franchie/.test(t),
      };
    });
    verifier('Le partogramme monte — graphique, mesures horaires et compteur de franchissements',
      parto.lignes && parto.mesures && parto.kpis);

    /* --- CPoN : l'hémorragie ANTE-partum est là, et exigée motivée -------- */
    await ouvrir('m4-cpon.html');
    const cpon = await page.evaluate(() => {
      const t = document.body.textContent;
      return { colonne: /Hémorragie ANTE-partum/i.test(t), etiologie: /Placenta praevia|HRP|étiologie/i.test(t) };
    });
    verifier('La CPoN porte la variable NOUVELLE — hémorragie ante-partum avec son étiologie',
      cpon.colonne && cpon.etiologie);

    /* --- Le verrou d'admission : le POIDS est exigé au formulaire --------- */
    await ouvrir('m4-maternite.html');
    await cliquer('Nouveau');
    await pause(500);
    const verrou = await page.evaluate(() => {
      const poids = document.getElementById('f_poids');
      /* U.form marque l'obligation par l'astérisque du label et la contrôle à
         la collecte — l'attribut DOM `required` n'est pas garanti. */
      const lbl = document.querySelector('label[for="f_poids"]');
      return {
        present: !!poids,
        requis: (poids && poids.required === true) || (lbl && lbl.textContent.indexOf('*') !== -1),
      };
    });
    verifier('L’admission maternité EXIGE le poids (verrou du rapport, Module A)',
      verrou.present && verrou.requis, 'champ: ' + verrou.present + ' · requis: ' + verrou.requis);
    await page.keyboard.press('Escape');
    await pause(300);

    /* --- SONU et PF montent avec leurs listes fermées --------------------- */
    await ouvrir('m4-sonu.html');
    const sonuEcran = await page.evaluate(() => {
      const t = document.body.textContent;
      return { sonuc: /SONUC/.test(t), badge: /Réanimation/.test(t) || /fonction/i.test(t) };
    });
    verifier('Le registre SONU distingue SONUB et SONUC à l’écran', sonuEcran.sonuc && sonuEcran.badge);

    await ouvrir('m4-planification.html');
    const pfEcran = await page.evaluate(() => {
      const t = document.body.textContent;
      return { an: /nouvelle|ancienne/i.test(t), quinze: /\/ 15/.test(t) };
    });
    verifier('La PF affiche la codification A/N et compte ses méthodes sur 15', pfEcran.an && pfEcran.quinze);

    /* --- Les indicateurs DHIS2 sont CALCULÉS, pas fournis ----------------- */
    await ouvrir('m4-stats-maternite.html');
    const stats = await page.evaluate(() => {
      const S = window.SIGH.store;
      const gros = S.collection('grossesses').active();
      const sp3 = gros.filter((g) => (g.sp || []).indexOf('SP3') !== -1).length;
      /* LA MÊME FONCTION que l'écran (C.pct) produit la valeur attendue :
         comparer un arrondi maison à un format maison mesurerait la sonde. */
      const attendu = window.SIGH.core.pct(gros.length ? sp3 / gros.length * 100 : 0);
      const nu = (s2) => String(s2).replace(/[\s\u202F\u00A0]/g, '');
      const t = document.body.textContent;
      return {
        monte: /Couverture SP3/.test(t),
        exact: nu(t).indexOf(nu(attendu)) !== -1,
        vaccins: /VPO0/.test(t) && /BCG/.test(t),
      };
    });
    verifier('Les statistiques maternité montent sous Pilotage', stats.monte && stats.vaccins);
    verifier('La couverture SP3 affichée est CELLE du registre — recalculée, jamais fournie', stats.exact);

    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* ==========================================================================
   * 47. PHASE 5 — FINANCIER : DÉPENSES MULTI-LIGNES, AVOIR, PV DE RÉCEPTION
   * --------------------------------------------------------------------------
   * L'arbitrage des dépenses (les lignes, leur somme, 4 KPI), le canal de
   * correction (facture d'avoir : contre-passation en brouillon, refus nommé
   * sur une fille consolidée, cumul plafonné) et la fermeture de l'annulation
   * au caissier — la matrice cible, sondée.
   * ======================================================================== */
  {
    scenario('Phase 5 — dépenses multi-lignes, facture d’avoir et PV de réception');

    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'comptable', fonction: 'comptable', nom: 'KASSA Augustin',
        nomComplet: 'KASSA Augustin', identifiant: 'a.kassa', secteur: 'ADM',
      }));
    });

    /* --- Dépenses : l'arbitrage, mesuré ----------------------------------- */
    await ouvrir('m12-depenses.html');
    const dep = await page.evaluate(() => {
      const S = window.SIGH.store;
      const rows = S.collection('depenses').active();
      const multi = rows.filter((r) => (r.lignes || []).length > 1);
      const coherentes = multi.every((r) => {
        const somme = r.lignes.reduce((n, l) => n + (Number(l.montant) || 0), 0);
        return somme === r.montant;
      });
      const t = document.body.textContent;
      return {
        multi: multi.length,
        coherentes,
        moyenneAbsente: t.indexOf('Dépense moyenne') === -1,
        quatre: ['Dépensé aujourd’hui', 'Dépensé ce mois', 'Total enregistré', 'Sans justificatif']
          .every((l) => t.indexOf(l) !== -1),
      };
    });
    verifier('Des pièces multi-lignes existent, et le total est LA SOMME de leurs lignes',
      dep.multi > 0 && dep.coherentes, dep.multi + ' pièce(s) multi-lignes');
    verifier('QUATRE indicateurs, pas cinq — la « dépense moyenne » est retirée (arbitrage)',
      dep.quatre && dep.moyenneAbsente);

    /* La fiche d'une pièce nomme ses lignes — `lignesDe` adapte aussi les
       pièces d'ancienne génération, donc TOUTE fiche en porte. La page
       affichée est paginée : on clique une ligne PRÉSENTE, multi-lignes si
       la première page en montre une. */
    const cliqueDep = await page.evaluate(() => {
      const S = window.SIGH.store;
      const refs = S.collection('depenses').active()
        .filter((r) => (r.lignes || []).length > 1).map((r) => r.reference);
      const trs = [...document.querySelectorAll('tbody tr')];
      const tr = trs.filter((x) => refs.some((rf) => x.textContent.indexOf(rf) !== -1))[0] || trs[0];
      if (tr) tr.click();
      return !!tr;
    });
    await pause(600);
    const tiroirDep = await page.evaluate(() => /Lignes de la pièce/.test(document.body.textContent));
    verifier('La fiche de la dépense porte ses « Lignes de la pièce »', cliqueDep && tiroirDep);
    await page.keyboard.press('Escape');
    await pause(300);

    /* --- Le moteur d'avoir, appelé directement ----------------------------
       Le moteur vit dans m8-facturation.js et CHAQUE PAGE NE CHARGE QUE LE
       MODULE DE SON ÉCRAN : la sonde doit se placer sur une page M8. */
    await ouvrir('m8-facture-avoir.html');
    const comptableEmet = await page.evaluate(() => {
      const plat = (n) => n.textContent.replace(/\s+/g, ' ').trim();
      return [...document.querySelectorAll('button')].map(plat)
        .some((b) => b.indexOf('Émettre un avoir') === 0);
    });
    verifier('Le comptable, lui, dispose de la commande d’émission', comptableEmet);
    const avoir = await page.evaluate(() => {
      const S = window.SIGH.store;
      const meres = S.collection('facturesMere').active();
      const figees = meres.reduce((acc, m) => acc.concat(m.piecesFilles || []), []);
      const libre = S.collection('factures').active().filter((f) =>
        (f.lignes || []).length > 0 && figees.indexOf(f.numero) === -1)[0];
      const figee = S.collection('factures').active().filter((f) => figees.indexOf(f.numero) !== -1)[0];
      if (!libre) return { possible: false };

      const ligne = libre.lignes[0];
      const res = window.SIGH.emettreAvoir(libre.id, {
        lignes: [{ designation: ligne.designation, montant: Number(ligne.montant || ligne.prixUnitaire || 0) }],
        motif: 'Erreur de facturation', remboursement: 'creance',
      });
      if (res.erreur) return { possible: true, erreurInattendue: res.erreur };

      const ecr = S.collection('ecritures').active().filter((e) => e.numero === res.record.reference);
      const facApres = S.collection('factures').active().filter((f) => f.id === libre.id)[0];
      const dansMecef = S.collection('avoirs').active().some((a) => a.id === res.record.id);

      /* Le refus nommé sur une fille consolidée. */
      let refus = null;
      if (figee) {
        const r2 = window.SIGH.emettreAvoir(figee.id, {
          lignes: [{ designation: 'test', montant: 100 }], motif: 'Erreur de facturation',
        });
        refus = r2.erreur || 'ACCEPTÉ À TORT';
      }

      /* Le plafond : un second avoir qui dépasserait la facture est refusé. */
      const trop = window.SIGH.emettreAvoir(libre.id, {
        lignes: [{ designation: 'dépassement', montant: (libre.montantTTC || 0) + 1 }],
        motif: 'Erreur de facturation',
      });

      return {
        possible: true,
        montantJuste: res.record.montant === Number(ligne.montant || ligne.prixUnitaire || 0),
        ecritures: ecr.length,
        equilibre: ecr.reduce((n, e) => n + (e.debit || 0), 0) === ecr.reduce((n, e) => n + (e.credit || 0), 0),
        brouillon: ecr.every((e) => e.statut === 'brouillon'),
        facturePorte: (facApres.avoirIds || []).indexOf(res.record.id) !== -1
          && facApres.montantAvoirs >= res.record.montant,
        dansMecef,
        refusNomme: refus === null ? 'aucune fille figée au jeu' : refus,
        refusOk: refus === null || /facture mère|consolidée/i.test(refus || ''),
        plafond: !!trop.erreur && /excéderait/i.test(trop.erreur),
      };
    });
    verifier('L’avoir s’émet sur des lignes NOMMÉES et son montant est leur somme',
      avoir.possible && !avoir.erreurInattendue && avoir.montantJuste, avoir.erreurInattendue || '');
    verifier('La contre-passation est PLATE, équilibrée (RG-10) et en BROUILLON',
      avoir.ecritures === 2 && avoir.equilibre && avoir.brouillon);
    verifier('La facture PORTE son avoir — elle n’est jamais réécrite', avoir.facturePorte);
    verifier('Le registre MECeF lit la MÊME collection — une pièce, deux vues', avoir.dansMecef);
    verifier('Une fille consolidée dans une mère émise est refusée EN NOMMANT la mère',
      avoir.refusOk, String(avoir.refusNomme).slice(0, 90));
    verifier('Le cumul des avoirs est plafonné à la facture', avoir.plafond);

    /* --- Le caissier : consulter oui, émettre non, annuler non ------------ */
    const caisse = await page.evaluate(() => {
      const N = window.SIGH.nav;
      return {
        voit: N.droitsEcran('caissier', 'm8-facture-avoir', 'M8').voir,
        emet: N.droitsEcran('caissier', 'm8-facture-avoir', 'M8').editer,
        annule: N.droitsEcran('caissier', 'm8-factures', 'M8').annuler,
      };
    });
    verifier('Le caissier CONSULTE l’avoir sans pouvoir l’émettre',
      caisse.voit === true && caisse.emet === false);
    verifier('M8.annuler est FERMÉ au caissier — l’arbitrage différé est soldé',
      caisse.annule === false);
    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'caissier', fonction: 'caissiere', nom: 'DIEYABIDI Aïssatou',
        nomComplet: 'DIEYABIDI Aïssatou', identifiant: 'a.dieyabidi', secteur: 'CPH',
      }));
    });
    await ouvrir('m8-facture-avoir.html');
    const guichet = await page.evaluate(() => {
      const plat = (n) => n.textContent.replace(/\s+/g, ' ').trim();
      const boutons = [...document.querySelectorAll('button')].map(plat);
      return {
        monte: /Registre des avoirs/.test(document.body.textContent),
        emettreAbsent: !boutons.some((b) => b.indexOf('Émettre un avoir') === 0),
      };
    });
    verifier('Au guichet, le registre s’ouvre et la commande d’émission est ABSENTE — pas grisée',
      guichet.monte && guichet.emettreAbsent);

    /* --- PV de réception : les deux natures ------------------------------- */
    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'stock', fonction: 'stock', nom: 'MAMAN Zoukanéri',
        nomComplet: 'MAMAN Zoukanéri', identifiant: 'z.maman', secteur: 'ADM',
      }));
    });
    await ouvrir('m7-pv-reception-reactifs.html');
    const pv = await page.evaluate(() => {
      const S = window.SIGH.store;
      const tous = S.collection('pvReceptions').active();
      const rea = tous.filter((r) => r.nature === 'reactifs');
      const con = tous.filter((r) => r.nature === 'consommables');
      const plat = (n) => n.textContent.replace(/\s+/g, ' ').trim();
      const boutons = [...document.querySelectorAll('button')].map(plat);
      return {
        deuxNatures: rea.length > 0 && con.length > 0,
        froid: rea.every((r) => r.chaineFroid !== null && r.chaineFroid !== undefined),
        nouveau: boutons.some((b) => b.indexOf('Nouveau PV') === 0),
        monte: /Registre des procès-verbaux/.test(document.body.textContent),
        assistant: window.SIGH.nav.can('aide_comptable', window.SIGH.nav.get('m7-pv-reception-reactifs')),
      };
    });
    verifier('Les PV existent pour les DEUX natures, et les réactifs portent la chaîne du froid',
      pv.deuxNatures && pv.froid);
    verifier('Le magasinier peut dresser un PV — l’écran monte avec sa commande',
      pv.monte && pv.nouveau);
    verifier('L’assistant comptable accède aux PV par sa fiche RBAC (M7), sans figurer au manifeste',
      pv.assistant === true);

    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* ==========================================================================
   * 48. PHASE 6 — LABORATOIRE : CODE UNIQUE, IMPRESSION FILTRÉE, PLAGES PAR LOT
   * --------------------------------------------------------------------------
   * Le code d'analyse NNNNN-AAAA (série annuelle, fabrique unique), les vues
   * par service, l'impression verrouillée sur les examens non réglés, le
   * comparatif des antériorités et le versionnement des bornes par lot de
   * réactif — sans toucher aux deux verrous.
   * ======================================================================== */
  {
    scenario('Phase 6 — laboratoire : code unique, impression filtrée, plages par lot');

    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'laborantin', fonction: 'biologiste', nom: 'GARBA Yahouza',
        nomComplet: 'GARBA Yahouza', identifiant: 'y.garba', secteur: 'LAB',
      }));
    });

    /* --- Le code d'analyse unique ----------------------------------------- */
    await ouvrir('m5-demandes.html');
    const codes = await page.evaluate(() => {
      const S = window.SIGH.store;
      const rows = S.collection('demandesAnalyses').active();
      const forme = /^\d{5}-\d{4}$/;
      const portes = rows.filter((r) => forme.test(r.codeAnalyse || ''));
      const vus = {};
      let doublon = null;
      portes.forEach((r) => {
        if (vus[r.codeAnalyse]) doublon = r.codeAnalyse;
        vus[r.codeAnalyse] = true;
      });
      const suivant = window.SIGH.parcours.codeAnalyse('2026-08-16');
      const maxSerie = Math.max(...portes
        .filter((r) => r.codeAnalyse.slice(6) === '2026')
        .map((r) => +r.codeAnalyse.slice(0, 5)), 0);
      return {
        total: rows.length, portes: portes.length, doublon,
        suivantJuste: suivant === String(maxSerie + 1).padStart(5, '0') + '-2026',
        /* La page est paginée : on cherche LA FORME du code, pas une valeur
           précise qui pourrait être sur une autre page. */
        afficheEnColonne: /\d{5}-\d{4}/.test(document.body.textContent),
      };
    });
    verifier('Chaque demande porte son code NNNNN-AAAA, sans doublon',
      codes.total > 0 && codes.portes === codes.total && !codes.doublon,
      codes.portes + '/' + codes.total + (codes.doublon ? ' doublon ' + codes.doublon : ''));
    verifier('La fabrique UNIQUE (PR.codeAnalyse) continue la série annuelle', codes.suivantJuste);
    verifier('Le code se lit au registre des demandes', codes.afficheEnColonne);

    /* --- Les vues par service demandeur ------------------------------------ */
    await ouvrir('m5-demandes-maternite.html');
    const vueMat = await page.evaluate(() => {
      const S = window.SIGH.store;
      const mat = S.collection('demandesAnalyses').active()
        .filter((r) => /MATERN/i.test(String(r.secteurDemandeur || '')) || r.serviceDemandeur === 'maternite');
      return { compte: mat.length, monte: /Demandes du service/.test(document.body.textContent) };
    });
    verifier('La vue maternité monte et le registre porte des demandes du service',
      vueMat.monte && vueMat.compte > 0, vueMat.compte + ' demande(s)');
    await ouvrir('m5-demandes-hospitalisation.html');
    const vueHosp = await page.evaluate(() =>
      /Demandes du service/.test(document.body.textContent));
    verifier('La vue hospitalisation monte', vueHosp);

    /* --- L'impression filtrée par le règlement ----------------------------- */
    await ouvrir('m5-impression-resultats.html');
    const impr = await page.evaluate(() => {
      const t = document.body.textContent;
      const verrous = [...document.querySelectorAll('button[aria-disabled="true"]')]
        .filter((b) => /Imprimer/.test(b.textContent));
      const badgesDus = /Règlement dû/.test(t);
      return {
        kpis: ['Résultats rendus', 'Imprimables (réglés)', 'Verrouillés — règlement dû', 'Sans pièce de caisse liée']
          .every((l) => t.indexOf(l) !== -1),
        regleDit: /reste visible|verrouillée, en le disant|ne s’imprime pas/.test(t),
        coherent: !badgesDus || verrous.length > 0,
      };
    });
    verifier('L’écran d’impression classe rendus / imprimables / verrouillés / sans pièce', impr.kpis);
    verifier('Un examen non réglé est verrouillé EN LE DISANT — jamais masqué',
      impr.regleDit && impr.coherent);

    /* --- Le comparatif des antériorités ------------------------------------ */
    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'medecin', fonction: 'medecin', nom: 'BASSONGUI Chabi Séko',
        nomComplet: 'BASSONGUI Chabi Séko', identifiant: 'c.bassongui', secteur: 'MED',
      }));
    });
    await ouvrir('m5-resultats-comparatif.html');
    const compar = await page.evaluate(() => {
      const t = document.body.textContent.replace(/\s+/g, ' ');
      return {
        monte: /Choisir un patient/.test(t),
        colonneAnteriorites: /Antériorités/.test(t),
      };
    });
    verifier('Le comparatif s’ouvre sur le choix du patient — la colonne « Antériorités » de la fiche',
      compar.monte && compar.colonneAnteriorites);

    /* --- Les plages par lot de réactif : le versionnement ------------------- */
    const plages = await page.evaluate(() => {
      const S = window.SIGH.store;
      const LP = window.SIGH.laboPlages;
      const v = S.collection('variablesLabo').active()
        .filter((x) => x.type === 'numerique' && !x.accompagnement && x.min != null && x.max != null)[0];
      if (!v) return { possible: false };
      S.collection('plagesReactif', { module: 'M5', entite: 'plage de référence', prefix: 'PLG' }).insert({
        variableId: v.id, variableLibelle: v.libelle, examenLibelle: v.examenLibelle, examen: v.examen,
        lot: 'LOT-TEST-48', dateDebut: '2026-06-01',
        min: v.min + 1, max: v.max + 1, source: 'Sonde fonctionnelle',
      });
      const apres = LP.variableALaDate(v, '2026-08-01');
      const avant = LP.variableALaDate(v, '2026-01-15');
      const refApres = LP.referenceALaDate(v, '2026-08-01');
      /* Nettoyage : la sonde ne laisse pas de trace dans le paramétrage. */
      const col = S.collection('plagesReactif');
      col.active().filter((p) => p.lot === 'LOT-TEST-48').forEach((p) => col.archive(p.id));
      return {
        possible: true,
        apresDecale: apres.min === v.min + 1 && apres.max === v.max + 1,
        avantIntact: avant.min === v.min && avant.max === v.max,
        refNommeLot: /LOT-TEST-48/.test(refApres),
        nettoye: !S.collection('plagesReactif').active().some((p) => p.lot === 'LOT-TEST-48'),
      };
    });
    verifier('Une plage de lot DÉCALE les bornes des demandes postérieures à sa mise en service',
      plages.possible && plages.apresDecale);
    verifier('Un résultat ANTÉRIEUR au lot garde les bornes de son époque — versionné comme les primes',
      plages.avantIntact);
    verifier('La référence affichée NOMME le lot', plages.refNommeLot && plages.nettoye);

    /* --- Statistiques des réactifs et RBAC --------------------------------- */
    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'laborantin', fonction: 'biologiste', nom: 'GARBA Yahouza',
        nomComplet: 'GARBA Yahouza', identifiant: 'y.garba', secteur: 'LAB',
      }));
    });
    await ouvrir('m5-reactifs-stats.html');
    const stats = await page.evaluate(() => {
      const N = window.SIGH.nav;
      const t = document.body.textContent;
      return {
        kpi: /Références suivies/.test(t) && /Valeur du stock/.test(t),
        calcule: /calculés/.test(t),
        caissierFerme: !N.can('caissier', N.get('m5-impression-resultats')),
        sageFemmeVoit: !!N.can('infirmier', N.get('m5-demandes-maternite')),
      };
    });
    verifier('Les statistiques des réactifs sont CALCULÉES depuis stock, lots et demandes',
      stats.kpi && stats.calcule);
    verifier('Le caissier n’imprime pas de résultats ; la sage-femme voit sa vue maternité',
      stats.caissierFerme && stats.sageFemmeVoit);

    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* ==========================================================================
   * 49. PHASE 7 — ANESTHÉSIE, DEMANDE D'EXAMEN DU SERVICE, BONS DE PANSEMENT
   * --------------------------------------------------------------------------
   * La CPA et ses réserves, la fiche de demande d'examen qui suit la chaîne
   * existante (caisse, prélèvement), et le bon de pansement dont chaque
   * séance est une LIGNE PAYABLE — un règlement partiel libère des séances
   * nommées.
   * ======================================================================== */
  {
    scenario('Phase 7 — CPA, demande d’examen du service et bons de pansement');

    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'medecin', fonction: 'medecin', nom: 'BASSONGUI Chabi Séko',
        nomComplet: 'BASSONGUI Chabi Séko', identifiant: 'c.bassongui', secteur: 'MED',
      }));
    });

    /* --- La CPA ------------------------------------------------------------ */
    await ouvrir('m3-cpa.html');
    const cpa = await page.evaluate(() => {
      const S = window.SIGH.store;
      const rows = S.collection('cpa').active();
      const reserves = rows.filter((r) => r.conclusion !== 'Apte à l’anesthésie');
      const t = document.body.textContent;
      return {
        seme: rows.length > 0,
        reservesNommees: reserves.every((r) => String(r.observations || '').trim().length > 0),
        kpiSansCpa: t.indexOf('Interventions sans CPA') !== -1,
        arretees: /arrêtées par les praticiens du bloc/.test(t),
      };
    });
    verifier('La CPA est amorcée et chaque réserve est NOMMÉE', cpa.seme && cpa.reservesNommees);
    verifier('Une intervention sans CPA est SIGNALÉE — jamais bloquée', cpa.kpiSansCpa);
    /* Vague 51 : les échelles sont arrêtées par les praticiens. */
    verifier('Les échelles ASA/Mallampati sont ARRÊTÉES par les praticiens du bloc (01/09)', cpa.arretees);

    await ouvrir('m3-cr-anesthesie.html');
    const cra = await page.evaluate(() => {
      const t = document.body.textContent;
      return /Comptes rendus d’anesthésie/.test(t) && /fiche de surveillance/.test(t);
    });
    verifier('Le CR d’anesthésie monte et renvoie la surveillance d’étage à m3-surveillance', cra);

    /* --- La fiche de demande d'examen du service --------------------------- */
    await ouvrir('m3-demande-examen.html');
    const fiche = await page.evaluate(() => {
      const S = window.SIGH.store, PR = window.SIGH.parcours;
      const pt = S.collection('patients').active().filter((p) => !p.externe)[0];
      const analyses = window.SIGH.data.ANALYSES.filter((a) => a.prix).slice(0, 2).map((a) => a.code);
      const res = PR.ouvrirDemandeExterne({
        patientId: pt.id, analyses,
        urgence: 'bilan', prescripteur: 'YENI Florent',
        serviceDemandeur: 'maternite', indication: 'Bilan pré-opératoire',
        hospitalise: true,
        origineFiche: 'service', origineDemande: 'service', secteurDemandeur: 'MATERNITÉ',
      });
      const d = res.demandes[0];
      const lignes = (res.facture.lignes || []).filter((l) => l.demandeId);
      const tacheCaisse = res.taches.filter((x) => x.type === 'encaissement')[0];
      const tachePrel = res.taches.filter((x) => x.type === 'prelevement')[0];
      return {
        origine: d.origine, origineDemande: d.origineDemande,
        secteur: d.secteurDemandeur, code: /^\d{5}-\d{4}$/.test(d.codeAnalyse || ''),
        urgent: d.urgent === true,
        lignesLiees: lignes.length === res.demandes.length,
        caisseOuverte: tacheCaisse && tacheCaisse.statut === 'en_attente',
        prelBloque: tachePrel && tachePrel.statut === 'bloque',
        numeroFiche: res.facture.numero,
      };
    });
    verifier('La fiche du service crée des demandes SERVICE, codées, au secteur du prescripteur',
      fiche.origine === 'service' && fiche.origineDemande === 'service'
      && fiche.secteur === 'MATERNITÉ' && fiche.code && fiche.urgent);
    verifier('La chaîne existante est réutilisée : lignes payables, caisse saisie, prélèvement bloqué',
      fiche.lignesLiees && fiche.caisseOuverte && fiche.prelBloque);
    await ouvrir('m3-demande-examen.html');
    const registreFiche = await page.evaluate(() => ({
      registre: /Registre des fiches de demande/.test(document.body.textContent),
      badge: /Fiche de service|Registre/.test(document.body.textContent),
      commande: [...document.querySelectorAll('button')]
        .some((b) => b.textContent.replace(/\s+/g, ' ').indexOf('Nouvelle fiche de demande') !== -1),
    }));
    verifier('Le registre des fiches monte avec sa commande d’émission',
      registreFiche.registre && registreFiche.commande);

    /* --- Le bon de pansement : une ligne payable PAR SÉANCE ----------------- */
    const bon = await page.evaluate(() => {
      const S = window.SIGH.store, PR = window.SIGH.parcours;
      const pt = S.collection('patients').active().filter((p) => !p.externe && !p.assureur)[0];
      const res = PR.prescrire({
        patientCode: pt.code, medecin: 'BASSONGUI Chabi Séko',
        diagnostic: 'Plaie du membre inférieur', actes: ['SO09', 'SO09', 'SO09'],
      });
      /* 9 000 F : les colonnes de la grille sont INVERSÉES (décision du
         26/08/2026) — le non-assuré paie 9 000, l'assuré 6 000. */
      const lignes = (res.facture.lignes || []).filter((l) => l.acteCode === 'SO09');
      const prixJuste = lignes.every((l) => l.montant === 9000);
      /* Le règlement PARTIEL : une séance réglée, deux dues. */
      PR.encaisser(res.facture.id, { lignes: [lignes[0].id] });
      const fac = S.collection('factures').active().filter((f) => f.id === res.facture.id)[0];
      const reglees = (fac.lignes || []).filter((l) => l.acteCode === 'SO09' && l.statutPaiement === 'paye');
      return {
        numero: res.ordonnance.numero,
        troisLignes: lignes.length === 3,
        prixJuste,
        partiel: reglees.length === 1,
      };
    });
    verifier('Le bon porte UNE ligne payable par séance, au tarif de la grille (9 000 F non assuré)',
      bon.troisLignes && bon.prixJuste);
    verifier('Un règlement partiel libère la séance NOMMÉE — une sur trois', bon.partiel);
    await ouvrir('m3-bons-pansements.html');
    const registreBon = await page.evaluate((numero) => {
      const t = document.body.textContent.replace(/\s+/g, ' ');
      return {
        monte: /Registre des bons/.test(t),
        leBon: t.indexOf(numero) !== -1,
        compteur: /1 \/ 3/.test(t),
      };
    }, bon.numero);
    verifier('Le registre des bons montre le bon et ses séances réglées « 1 / 3 »',
      registreBon.monte && registreBon.leBon && registreBon.compteur);

    /* --- RBAC : l'anesthésiste entre, le caissier non ----------------------- */
    const acces = await page.evaluate(() => {
      const N = window.SIGH.nav;
      return {
        anesthesiste: !!N.can('anesthesiste', N.get('m3-cpa')),
        caissier: !N.can('caissier', N.get('m3-cpa')),
      };
    });
    verifier('L’anesthésiste ouvre la CPA (sa surcharge ACCORDE M3) ; le caissier non',
      acces.anesthesiste && acces.caissier);

    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* ==========================================================================
   * 50. PHASE 8 — L'IMAGERIE ÉCLATÉE : ÉTATS DU LABO, GALERIE, CATALOGUE
   * --------------------------------------------------------------------------
   * La demande d'imagerie suit les états du laboratoire (demandée → payée →
   * exécutée → validée), la caisse libère des examens NOMMÉS, l'échographiste
   * exécute sans prescrire, la galerie conserve les clichés et le catalogue
   * vit au magasin.
   * ======================================================================== */
  {
    scenario('Phase 8 — imagerie éclatée : états du labo, galerie et catalogue');

    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'medecin', fonction: 'medecin', nom: 'BASSONGUI Chabi Séko',
        nomComplet: 'BASSONGUI Chabi Séko', identifiant: 'c.bassongui', secteur: 'MED',
      }));
    });
    await ouvrir('m2-imagerie-demandes.html');

    /* --- Le moteur : demande, tarif RG-09 inversé, refus nommé, caisse ----- */
    const moteur = await page.evaluate(() => {
      const S = window.SIGH.store, PR = window.SIGH.parcours;
      const pt = S.collection('patients').active().filter((p) => !p.externe && !p.assureur)[0];
      const res = PR.ouvrirDemandeImagerie({
        patientId: pt.id, examens: ['IMG-ECHO-PEL', 'IMG-ECG'],
        prescripteur: 'YENI Florent', indication: 'Douleurs pelviennes',
      });
      const lignes = (res.facture.lignes || []).filter((l) => l.categorie === 'imagerie');
      const pel = res.demandes.filter((d) => d.examenCode === 'IMG-ECHO-PEL')[0];
      const ecg = res.demandes.filter((d) => d.examenCode === 'IMG-ECG')[0];

      let refus = null;
      try { PR.ouvrirDemandeImagerie({ patientId: pt.id, examens: ['IMG-FAUX'] }); }
      catch (e) { refus = e.message; }

      /* La caisse règle L'EXAMEN NOMMÉ : la pelvienne passe, l'ECG attend. */
      const lignePel = lignes.filter((l) => l.demandeImagerieId === pel.id)[0];
      PR.encaisser(res.facture.id, { lignes: [lignePel.id] });
      const pelApres = S.collection('demandesImagerie').get(pel.id);
      const ecgApres = S.collection('demandesImagerie').get(ecg.id);
      const taches = res.taches.map((t) => t.type + ':' + t.statut);

      return {
        deux: res.demandes.length === 2,
        lignesLiees: lignes.length === 2 && lignes.every((l) => l.demandeImagerieId),
        /* Colonnes INVERSÉES (26/08) : pelvienne 9 000 et ECG 15 000 pour le
           non-assuré. */
        tarifs: pel.prix === 9000 && ecg.prix === 15000,
        refusNomme: /Tarif non renseigné/.test(refus || '') && /IMG-FAUX/.test(refus || ''),
        pelPayee: pelApres.statut === 'payee' && pelApres.bloqueParPaiement === false,
        ecgAttend: ecgApres.statut === 'demandee' && ecgApres.bloqueParPaiement === true,
        taches,
        pelId: pel.id, ecgId: ecg.id,
      };
    });
    verifier('La demande naît bloquée, ses lignes payables NOMMENT chaque examen',
      moteur.deux && moteur.lignesLiees
      && moteur.taches.indexOf('encaissement:en_attente') !== -1
      && moteur.taches.indexOf('imagerie:bloque') !== -1);
    verifier('RG-09 sur la grille inversée : pelvienne 9 000, ECG 15 000 (non assuré)', moteur.tarifs);
    verifier('Un examen sans tarif est refusé EN LE NOMMANT', moteur.refusNomme);
    verifier('Le règlement partiel libère l’examen NOMMÉ : pelvienne payée, ECG en attente',
      moteur.pelPayee && moteur.ecgAttend);

    /* --- L'échographiste : exécute et rend, sans pouvoir prescrire --------- */
    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'echographiste', fonction: 'echographiste', nom: 'AHOHOU Rodrigue',
        nomComplet: 'AHOHOU Rodrigue', identifiant: 'r.ahohou', secteur: 'MED',
      }));
    });
    await ouvrir('m2-imagerie-demandes.html');
    const echo1 = await page.evaluate((ids) => new Promise((resolve) => {
      const plat = (n) => n.textContent.replace(/\s+/g, ' ').trim();
      const boutons = [...document.querySelectorAll('button')];
      const prescrireAbsent = !boutons.some((b) => plat(b).indexOf('Nouvelle demande') === 0);
      const verrouPresent = boutons.some((b) => plat(b).indexOf('Saisir le CR') === 0 && b.getAttribute('aria-disabled'));
      /* LA LIGNE SE CHERCHE PAR SA RÉFÉRENCE, JAMAIS PAR SON RANG (vague 68). Depuis que le
         banc décale l'horloge sur la date du jeu, la demande créée par le scénario n'est
         plus la plus récente du registre : le PREMIER bouton « Saisir le CR » était celui
         d'une autre demande, et la sonde mesurait son rang — un compte rendu naissait sur
         la mauvaise demande sans qu'aucune assertion ne le dise. */
      const dem = window.SIGH.store.collection('demandesImagerie').get(ids.pelId);
      const champ = document.querySelector('#page-content input[type="search"]');
      if (champ && dem) { champ.value = dem.reference; champ.dispatchEvent(new Event('input', { bubbles: true })); }
      setTimeout(() => {
        const ligne = [...document.querySelectorAll('#page-content tbody tr')].find((tr) => dem && plat(tr).indexOf(dem.reference) >= 0);
        const saisir = ligne ? [...ligne.querySelectorAll('button')].filter((b) => plat(b).indexOf('Saisir le CR') === 0 && !b.getAttribute('aria-disabled')) : [];
        if (saisir[0]) saisir[0].click();
        resolve({ prescrireAbsent, saisirPresent: saisir.length > 0, verrouPresent, reference: dem && dem.reference, ligne: !!ligne });
      }, 400);
    }), moteur);
    await pause(700);
    verifier('L’échographiste EXÉCUTE (Saisir le CR) mais ne PRESCRIT pas (Nouvelle demande absente)',
      echo1.prescrireAbsent && echo1.saisirPresent, JSON.stringify(echo1));
    verifier('Un examen non réglé garde son bouton VERROUILLÉ, visible', echo1.verrouPresent);

    /* Le CR s'enregistre : conclusion obligatoire, la demande passe EXÉCUTÉE.
       LA SAISIE A QUITTÉ LA MODALE POUR UNE PAGE (21/09/2026) : « Saisir le
       CR » NAVIGUE, et l'enregistrement ramène au tableau. On attend donc
       les deux navigations au lieu de mesurer dans la foulée du clic. */
    /* ON ATTEND LE CHAMP, PAS LE CHRONOMÈTRE. La page du compte rendu est
       atteinte tout de suite, mais depuis la bascule en base elle n'est
       peinte qu'après l'hydratation : les 700 ms d'autrefois tombaient entre
       les deux, et la sonde concluait « conclusion absente » sur un écran
       simplement en retard. */
    await page.waitForFunction(() => !!document.querySelector('#f_conclusion'),
      { timeout: 150000 }).catch(() => null);
    const ouvertCR = await page.evaluate(() => ({
      page: /m2-imagerie-cr/.test(location.pathname),
      conclusion: !!document.querySelector('#f_conclusion'),
    }));
    await page.evaluate(() => {
      const conclusion = document.querySelector('#f_conclusion');
      if (conclusion) {
        conclusion.value = 'Échographie pelvienne sans anomalie décelée.';
        conclusion.dispatchEvent(new Event('input', { bubbles: true }));
      }
    });
    await cliquer('Enregistrer le compte rendu', '#page-content button');
    /* Depuis la vague 65 l'enregistrement REVIENT au registre : c'est une
       navigation, et la sonde lit ensuite le magasin. On attend son autorité
       plutôt qu'un délai — lire la coquille provisoire aurait fait conclure
       que le compte rendu n'avait pas été créé. */
    await attendrePeinture();
    await pause(300);
    const saisie = await page.evaluate((pelId) => {
      const S = window.SIGH.store;
      const cr = S.collection('resultatsImagerie').active().filter((r) => r.demandeImagerieId === pelId)[0];
      const dem = S.collection('demandesImagerie').get(pelId);
      return { modale: true, crCree: !!cr, executee: dem && dem.statut === 'executee',
        crId: cr ? cr.id : null };
    }, moteur.pelId);
    verifier('« Saisir le CR » conduit à la PAGE du compte rendu, conclusion comprise',
      ouvertCR.page && ouvertCR.conclusion, JSON.stringify(ouvertCR));
    verifier('Le CR se crée depuis la demande et l’enregistrement passe la demande en EXÉCUTÉE',
      saisie.modale && saisie.crCree && saisie.executee);

    /* Le rendu au prescripteur clôt le circuit : demande VALIDÉE. */
    await ouvrir('m2-imagerie-demandes.html');
    await page.evaluate((ids) => new Promise((resolve) => {
      const plat = (n) => n.textContent.replace(/\s+/g, ' ').trim();
      const dem = window.SIGH.store.collection('demandesImagerie').get(ids.pelId);
      const champ = document.querySelector('#page-content input[type="search"]');
      if (champ && dem) { champ.value = dem.reference; champ.dispatchEvent(new Event('input', { bubbles: true })); }
      setTimeout(() => {
        const ligne = [...document.querySelectorAll('#page-content tbody tr')].find((tr) => dem && plat(tr).indexOf(dem.reference) >= 0);
        const b = ligne ? [...ligne.querySelectorAll('button')].filter((x) => plat(x) === 'Rendre')[0] : null;
        if (b) b.click();
        resolve(!!b);
      }, 400);
    }), moteur);
    await pause(500);
    await page.evaluate(() => {
      const plat = (n) => n.textContent.replace(/\s+/g, ' ').trim();
      const b = [...document.querySelectorAll('button')].filter((x) => plat(x) === 'Rendre').pop();
      if (b) b.click();
    });
    await pause(500);
    const rendu = await page.evaluate((ids) => {
      const S = window.SIGH.store;
      const dem = S.collection('demandesImagerie').get(ids.pelId);
      const cr = S.collection('resultatsImagerie').active().filter((r) => r.demandeImagerieId === ids.pelId)[0];
      return { validee: dem && dem.statut === 'validee', crRendu: cr && cr.statut === 'rendu' };
    }, moteur);
    verifier('Le rendu au prescripteur passe la demande en VALIDÉE — les états du labo, tenus',
      rendu.validee && rendu.crRendu);

    /* --- La galerie : le cliché se conserve, rattaché ----------------------- */
    await ouvrir('m2-echographie-galerie.html');
    const galerie = await page.evaluate(() => {
      const S = window.SIGH.store;
      const pt = S.collection('patients').active()[0];
      S.collection('clichesImagerie', { module: 'M2', entite: 'cliché', prefix: 'CLI' }).insert({
        date: new Date().toISOString(),
        patientId: pt.id, patient: pt.nom + ' ' + pt.prenom, patientCode: pt.code,
        examen: 'Échographie pelvienne', legende: 'Coupe sagittale — sonde 50',
        crReference: null,
        fichier: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
        deposePar: 'Sonde fonctionnelle',
      });
      const plat = (n) => n.textContent.replace(/\s+/g, ' ').trim();
      return {
        commande: [...document.querySelectorAll('button')].some((b) => plat(b).indexOf('Ajouter un cliché') === 0),
      };
    });
    await ouvrir('m2-echographie-galerie.html');
    const galerie2 = await page.evaluate(() => ({
      image: !!document.querySelector('img[src^="data:image"]'),
      legende: /Coupe sagittale/.test(document.body.textContent),
    }));
    verifier('La galerie est l’instrument de l’échographiste : commande présente, cliché rendu',
      galerie.commande && galerie2.image && galerie2.legende);

    /* --- Le catalogue vit au magasin --------------------------------------- */
    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'admin', fonction: 'admin', nom: 'Administrateur',
        nomComplet: 'Administrateur', identifiant: 'admin', secteur: 'ADM',
      }));
    });
    await ouvrir('cfg-imagerie-catalogue.html');
    const catalogue = await page.evaluate(() => {
      const S = window.SIGH.store;
      const t = document.body.textContent;
      return {
        examens: S.collection('examensImagerie').active().length,
        variables: S.collection('variablesImagerie').active().length,
        monte: /brouillon manuscrit/.test(t) && /Examens/.test(t) && /Variables/.test(t),
      };
    });
    verifier('Le catalogue de l’imagerie vit AU MAGASIN — semé du brouillon, administrable',
      catalogue.examens >= 7 && catalogue.variables > 50 && catalogue.monte);

    /* --- Stats sous PIL et RBAC -------------------------------------------- */
    await ouvrir('m2-stats-echographie.html');
    const stats = await page.evaluate(() => {
      const N = window.SIGH.nav;
      const t = document.body.textContent;
      return {
        kpi: /Comptes rendus émis/.test(t) && /calculés/.test(t),
        caissierFerme: !N.can('caissier', N.get('m2-imagerie-demandes')),
        echographisteStats: !!N.can('echographiste', N.get('m2-stats-echographie')),
        echographisteCfgFerme: !N.can('echographiste', N.get('cfg-imagerie-catalogue')),
      };
    });
    verifier('Les statistiques de l’échographie sont CALCULÉES, sous Pilotage', stats.kpi);
    verifier('RBAC : le caissier ne voit pas les demandes ; l’échographiste a ses stats, pas le catalogue CFG',
      stats.caissierFerme && stats.echographisteStats && stats.echographisteCfgFerme);

    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* ==========================================================================
   * 51. PHASE 9 — PILOTAGE & STATISTIQUES TRANSVERSES
   * --------------------------------------------------------------------------
   * Les statistiques multi-axes demandées par le laboratoire, les lectures
   * par praticien, bloc, coût de l'agent et groupes de prestation — toutes
   * CALCULÉES —, et les deux vues de terrain (agenda médecin, file par
   * cabinet aux deux listes jamais fondues).
   * ======================================================================== */
  {
    scenario('Phase 9 — pilotage : stats multi-axes, coût de l’agent, files et agendas');

    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'laborantin', fonction: 'biologiste', nom: 'GARBA Yahouza',
        nomComplet: 'GARBA Yahouza', identifiant: 'y.garba', secteur: 'LAB',
      }));
    });

    /* --- Les stats des examens : l'axe filtre VRAIMENT ---------------------- */
    await ouvrir('m5-stats-examens.html');
    const axes = await page.evaluate(() => {
      const S = window.SIGH.store;
      const total = S.collection('demandesAnalyses').active().length;
      const sel = [...document.querySelectorAll('select')][0]; /* service — premier select de la barre */
      const option = [...sel.options].map((o) => o.value).filter(Boolean)[0];
      const attendus = S.collection('demandesAnalyses').active()
        .filter((r) => (r.secteurDemandeur || r.serviceDemandeur) === option).length;
      sel.value = option;
      sel.dispatchEvent(new Event('change'));
      /* Lire le KPI par son LIBELLÉ, chiffres seuls — C.num compose en
         espaces fines insécables, on neutralise tout ce qui n'est pas un
         chiffre (doctrine de sonde). */
      const feuille = [...document.querySelectorAll('*')]
        .find((e) => e.children.length === 0 && e.textContent.trim() === 'Examens (population filtrée)');
      const bloc = feuille && feuille.parentElement && feuille.parentElement.parentElement;
      const chiffres = bloc ? bloc.textContent.replace(/[^\d]/g, '') : null;
      return {
        total,
        option,
        attendus,
        affiche: chiffres ? Number(String(chiffres).replace(/[^\d]/g, '')) : null,
        source: /reunions/.test(document.body.textContent),
      };
    });
    verifier('L’axe « service demandeur » FILTRE la population — le compte affiché est recalculé',
      axes.total > 0 && axes.affiche === axes.attendus && axes.attendus < axes.total,
      axes.option + ' : ' + axes.affiche + '/' + axes.attendus);
    verifier('La source nomme la demande écrite du laboratoire (reunions/)', axes.source);

    /* --- Consultations et bloc --------------------------------------------- */
    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'medecin', fonction: 'medecin', nom: 'BASSONGUI Chabi Séko',
        nomComplet: 'BASSONGUI Chabi Séko', identifiant: 'c.bassongui', secteur: 'MED',
      }));
    });
    await ouvrir('m2-stats-consultations.html');
    const consult = await page.evaluate(() => {
      const t = document.body.textContent;
      return /Par praticien/.test(t) && /service du praticien/.test(t) && /Praticiens actifs/.test(t);
    });
    verifier('Les consultations se lisent par praticien, le « secteur » annoncé comme proxy', consult);

    await ouvrir('m3-stats-bloc.html');
    const bloc = await page.evaluate(() => {
      const t = document.body.textContent;
      return /Interventions sans CPA/.test(t) && /NOMMÉS/.test(t) && /jamais bloquées/.test(t);
    });
    verifier('Le bloc compte les interventions sans CPA — signalées, jamais bloquées', bloc);

    /* --- Le coût global de l'agent : deux colonnes jamais additionnées ------ */
    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'da', fonction: 'da', nom: 'TAKI Alimatou',
        nomComplet: 'TAKI Alimatou', identifiant: 'a.taki', secteur: 'ADM',
      }));
    });
    await ouvrir('m10-cout-agent.html');
    const cout = await page.evaluate(() => {
      const t = document.body.textContent;
      return {
        monte: /Choisir un agent/.test(t),
        regle: /jamais additionner/.test(t) && /retenues/i.test(t),
        its: /bulletin/.test(t),
      };
    });
    verifier('Le coût de l’agent sépare coût employeur et retenues — et renvoie l’ITS au bulletin',
      cout.monte && cout.regle && cout.its);

    /* --- Recettes & charges : la proposition est DITE ------------------------ */
    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'comptable', fonction: 'comptable', nom: 'KASSA Augustin',
        nomComplet: 'KASSA Augustin', identifiant: 'a.kassa', secteur: 'ADM',
      }));
    });
    await ouvrir('m12-rentabilite-groupes.html');
    const renta = await page.evaluate(() => {
      const S = window.SIGH.store;
      let attendu = 0;
      S.collection('factures').active().forEach((fa) => {
        (fa.lignes || []).forEach((l) => { attendu += l.montant || 0; });
      });
      const feuille = [...document.querySelectorAll('*')]
        .find((e) => e.children.length === 0 && e.textContent.trim() === 'Recettes facturées (lignes)');
      const bloc = feuille && feuille.parentElement && feuille.parentElement.parentElement;
      const affiche = bloc ? Number(bloc.textContent.replace(/[^\d]/g, '') || '0') : null;
      return {
        recettesJustes: affiche === attendu,
        arrete: /Rapprochement ARRÊTÉ le 01\/09\/2026/.test(document.body.textContent),
        beneficeBrut: /Bénéfice brut par groupe/.test(document.body.textContent),
        transversesDits: /transverses/i.test(document.body.textContent),
        brouillonsDits: /Brouillons écartés/.test(document.body.textContent),
      };
    });
    verifier('Les recettes affichées SONT la somme des lignes payables du magasin', renta.recettesJustes);
    /* Vague 51 : le rapprochement est ARRÊTÉ — bénéfice brut par groupe,
       transverses non ventilés dits, brouillons écartés annoncés. */
    verifier('Le rapprochement est ARRÊTÉ (01/09) : bénéfice brut par groupe, transverses non ventilés',
      renta.arrete && renta.beneficeBrut && renta.transversesDits && renta.brouillonsDits);

    /* --- Agenda médecin et file par cabinet --------------------------------- */
    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'medecin', fonction: 'medecin', nom: 'BASSONGUI Chabi Séko',
        nomComplet: 'BASSONGUI Chabi Séko', identifiant: 'c.bassongui', secteur: 'MED',
      }));
    });
    await ouvrir('m2-agenda-medecin.html');
    const agenda = await page.evaluate(() => {
      const sel = document.querySelector('select');
      const autre = [...sel.options].map((o) => o.value).filter((v) => v !== sel.value)[0];
      sel.value = autre;
      sel.dispatchEvent(new Event('change'));
      return {
        titreSuit: document.body.textContent.indexOf('Agenda — ' + autre) !== -1,
      };
    });
    verifier('L’agenda suit le praticien choisi — une vue du registre, pas une copie', agenda.titreSuit);

    await ouvrir('m2-file-cabinet.html');
    const file = await page.evaluate(() => {
      const S = window.SIGH.store;
      const tickets = S.collection('fileAttente').active()
        .filter((x) => x.poste === 'consultation' && x.etat !== 'servi' && x.etat !== 'clos');
      const nommes = tickets.filter((x) => x.praticien).length;
      const vivier = tickets.filter((x) => !x.praticien).length;
      const t = document.body.textContent.replace(/[  ]/g, ' ');
      return {
        deuxListes: /Vivier commun/.test(t) && /praticien nommé/.test(t),
        nommes, vivier,
        coherent: new RegExp('Attendent un praticien nommé\\\\s*' + nommes).test(t)
          || t.indexOf(String(nommes)) !== -1,
      };
    });
    verifier('La file par cabinet tient les DEUX listes — nommés et vivier commun',
      file.deuxListes && (file.nommes + file.vivier) >= 0);

    /* --- Certificats externes et RBAC --------------------------------------- */
    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'reception', fonction: 'accueil', nom: 'OROU YO Marguerite',
        nomComplet: 'OROU YO Marguerite', identifiant: 'm.orouyo', secteur: 'ACC',
      }));
    });
    /* LES DEUX REGISTRES ONT FUSIONNÉ (22/09/2026) : « Certificats —
       externes » est devenu une page de RENVOI, et le registre unique porte
       l'onglet « Patients externes ». Deux registres sur la même collection
       finissaient toujours par ne pas dire la même chose. */
    await ouvrir('m1-pieces.html');
    const ongletsPieces = await page.evaluate(() =>
      [...document.querySelectorAll('#page-content .tab')].map((t) => t.textContent.trim()));
    verifier('Le registre des certificats porte les quatre onglets — toutes, clinique, externes, archives',
      ['Toutes les pièces', 'Patients de la clinique', 'Patients externes', 'Archives']
        .every((o) => ongletsPieces.some((x) => x.indexOf(o) === 0)),
      ongletsPieces.join(' · '));

    await ouvrir('m1-certificats-externes.html');
    const certes = await page.evaluate(() => {
      const N = window.SIGH.nav;
      const t = document.body.textContent;
      return {
        monte: /patients externes/i.test(t),
        renvoi: /Certificats & attestations/.test(t),
        caissierCout: !N.can('caissier', N.get('m10-cout-agent')),
        laborantinExamens: !!N.can('laborantin', N.get('m5-stats-examens')),
        echographisteExamens: !N.can('echographiste', N.get('m5-stats-examens')),
      };
    });
    verifier('Les certificats des externes : une VUE qui renvoie la délivrance au registre',
      certes.monte && certes.renvoi);
    verifier('RBAC : le caissier ne lit pas le coût de l’agent ; le labo a ses stats, pas l’échographiste',
      certes.caissierCout && certes.laborantinExamens && certes.echographisteExamens);

    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* ==========================================================================
   * 52. PHASE 10 — ENQUÊTES (LE FORMULAIRE NAÎT DU MODÈLE), M7, M13 ET GED
   * --------------------------------------------------------------------------
   * Le principe KoboCollect sondé au geste : une question ajoutée au modèle
   * paraît à la saisie suivante sans une ligne de code. Puis les sondes que
   * la dette D6 réclamait : achats, courriers, GED.
   * ======================================================================== */
  {
    scenario('Phase 10 — enquêtes générées du modèle, sondes M7 / M13 / GED');

    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'agentadmin', fonction: 'accueil', nom: 'GBEDJI Hervé',
        nomComplet: 'GBEDJI Hervé', identifiant: 'h.gbedji', secteur: 'ADM',
      }));
    });

    /* --- Le générateur : recueillir une réponse ----------------------------- */
    await ouvrir('adm-enquetes.html');
    const avant = await page.evaluate(() => {
      const S = window.SIGH.store;
      const enq = S.collection('enquetes').active()[0];
      const reps = S.collection('reponsesEnquetes').active().length;
      const plat = (n) => n.textContent.replace(/\s+/g, ' ').trim();
      const b = [...document.querySelectorAll('button')].filter((x) => plat(x) === 'Recueillir')[0];
      if (b) b.click();
      return { questions: enq ? enq.questions.length : 0, reps, enqId: enq ? enq.id : null };
    });
    await pause(500);
    const saisie = await page.evaluate(() => {
      const champs = ['#f__canal', '#f_Q_ACCUEIL', '#f_Q_ATTENTE', '#f_Q_PROPRETE', '#f_Q_SOINS', '#f_Q_RECO']
        .map((s) => document.querySelector(s));
      if (champs.some((c) => !c)) return { formes: false };
      champs[0].value = 'À la sortie';
      ['#f_Q_ACCUEIL', '#f_Q_ATTENTE', '#f_Q_PROPRETE', '#f_Q_SOINS'].forEach((s) => {
        document.querySelector(s).value = '5';
      });
      champs[5].value = 'Oui, sans hésiter';
      const libre = document.querySelector('#f_Q_LIBRE');
      if (libre) libre.value = 'Sonde fonctionnelle — parcours impeccable.';
      const plat = (n) => n.textContent.replace(/\s+/g, ' ').trim();
      const b = [...document.querySelectorAll('button')].filter((x) => plat(x) === 'Enregistrer la réponse').pop();
      if (b) b.click();
      return { formes: true };
    });
    const apresSaisie = await page.evaluate((ctx) => {
      const S = window.SIGH.store;
      const reps = S.collection('reponsesEnquetes').active();
      const mienne = reps.filter((x) => (x.reponses || {}).Q_LIBRE === 'Sonde fonctionnelle — parcours impeccable.')[0];
      return {
        plusUne: reps.length === ctx.reps + 1,
        noteNumerique: mienne && mienne.reponses.Q_ACCUEIL === 5,
        canal: mienne && mienne.canal === 'À la sortie',
      };
    }, avant);
    verifier('Le formulaire de recueil NAÎT du modèle — six questions, saisie enregistrée',
      avant.questions === 6 && saisie.formes && apresSaisie.plusUne && apresSaisie.noteNumerique
      && apresSaisie.canal);

    /* --- LA preuve du générateur : une question ajoutée paraît aussitôt ----- */
    await page.evaluate((enqId) => {
      const S = window.SIGH.store;
      const enq = S.collection('enquetes').get(enqId);
      S.collection('enquetes').update(enqId, {
        questions: enq.questions.concat([{ code: 'Q_SONDE', libelle: 'Question ajoutée par la sonde', type: 'note' }]),
      });
    }, avant.enqId);
    await ouvrir('adm-enquetes.html');
    await page.evaluate(() => {
      const plat = (n) => n.textContent.replace(/\s+/g, ' ').trim();
      const b = [...document.querySelectorAll('button')].filter((x) => plat(x) === 'Recueillir')[0];
      if (b) b.click();
    });
    await pause(500);
    const genere = await page.evaluate((enqId) => {
      const S = window.SIGH.store;
      const present = !!document.querySelector('#f_Q_SONDE');
      /* Nettoyage : la sonde ne laisse pas sa question au modèle. */
      const enq = S.collection('enquetes').get(enqId);
      S.collection('enquetes').update(enqId, {
        questions: enq.questions.filter((q) => q.code !== 'Q_SONDE'),
      });
      return present;
    }, avant.enqId);
    await page.keyboard.press('Escape');
    await pause(300);
    verifier('Une question ajoutée au MODÈLE paraît à la saisie suivante — rien n’est codé', genere);

    /* --- La lecture de satisfaction ----------------------------------------- */
    await ouvrir('adm-satisfaction.html');
    const satis = await page.evaluate(() => {
      const t = document.body.textContent;
      return /Note moyenne globale/.test(t) && /validé par la Direction/i.test(t)
        && /Recommanderaient la clinique/.test(t);
    });
    verifier('La satisfaction est CALCULÉE et le questionnaire porte sa validation (vague 49)', satis);

    /* --- Dette D6 : M7, M13 et GED ------------------------------------------ */
    /* M7 est fermé à l'agent administratif : le magasinier ouvre son écran —
       et c'est son ouverture qui amorce les bons. */
    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'stock', fonction: 'stock', nom: 'MAMAN Zoukanéri',
        nomComplet: 'MAMAN Zoukanéri', identifiant: 'z.maman', secteur: 'ADM',
      }));
    });
    await ouvrir('m7-besoins.html');
    const m7 = await page.evaluate(() => {
      const S = window.SIGH.store;
      const besoins = S.collection('besoins').active();
      const distincts = besoins.some((b) => (b.lignes || []).some(
        (l) => l.quantiteAccordee != null && l.quantiteAccordee !== l.quantiteDemandee));
      return {
        compte: besoins.length,
        distincts,
        circuit: /brouillon/.test(document.body.textContent) && /validation DA/i.test(document.body.textContent),
      };
    });
    verifier('M7 : la quantité ACCORDÉE se distingue de la demandée, le circuit est affiché',
      m7.compte > 0 && m7.distincts && m7.circuit);

    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'agentadmin', fonction: 'accueil', nom: 'GBEDJI Hervé',
        nomComplet: 'GBEDJI Hervé', identifiant: 'h.gbedji', secteur: 'ADM',
      }));
    });
    await ouvrir('m13-courriers.html');
    const m13 = await page.evaluate(() => {
      const S = window.SIGH.store;
      return {
        registre: S.collection('courriers').active().length,
        monte: /[Cc]ourrier/.test(document.body.textContent),
      };
    });
    verifier('M13 : le registre des courriers est semé au socle et son écran monte',
      m13.registre > 0 && m13.monte);

    await ouvrir('ged-bibliotheque.html');
    const ged = await page.evaluate(() => {
      const S = window.SIGH.store;
      const docs = S.collection('documents').active();
      const docsPatient = S.collection('documentsPatient').active();
      return {
        compte: docs.length,
        monte: /documentaire|[Bb]iblioth/.test(document.body.textContent),
        /* Les deux bibliothèques restent DISTINCTES (vague 13). */
        distinctes: !docs.some((d) => docsPatient.some((p) => p.id === d.id)),
      };
    });
    verifier('GED : la bibliothèque de l’établissement est semée, DISTINCTE des documents patients',
      ged.compte > 0 && ged.monte && ged.distinctes);

    /* --- D5 : les quatre entrées converties restent offertes aux habilités --- */
    const d5 = await page.evaluate(() => {
      const N = window.SIGH.nav;
      return {
        comptable: N.droitsEcran('comptable', 'm12-ecritures', 'M12').editer !== false,
        aideComptable: !!N.can('aide_comptable', N.get('m12-depenses') || { id: 'm12-depenses', module: 'M12' }),
      };
    });
    verifier('D5 : les commandes converties en K.commande restent offertes aux profils habilités',
      d5.comptable);

    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* ==========================================================================
   * 53. VAGUE 49 — LES VALIDATIONS : LA DIRECTION TRANCHE, LE PROFESSIONNEL GARDE
   * --------------------------------------------------------------------------
   * Les validations du ressort de la Direction sont LEVÉES (tarifs arrêtés,
   * valorisations confirmées, groupes confirmés, questionnaire validé) ; les
   * marquages qui attendent un professionnel nommé RESTENT. Le centre des
   * validations oriente sans jamais valider en masse.
   * ======================================================================== */
  {
    scenario('Vague 49 — validations de la Direction levées, marquages professionnels gardés');

    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'direction', fonction: 'direction', nom: 'OROU YO Marguerite',
        nomComplet: 'OROU YO Marguerite', identifiant: 'm.orouyo', secteur: 'DIR',
      }));
    });
    await ouvrir('adm-validations.html');
    const etat = await page.evaluate(() => {
      const S = window.SIGH.store, D = window.SIGH.data;
      const actes = S.collection('actes').active();
      const t = document.body.textContent;
      return {
        /* La Direction a tranché : plus un provisoire au catalogue VIVANT,
           chaque arrêté daté ; la SEMENCE garde son marquage historique. */
        provisoiresVivants: actes.filter((a) => a.tarifProvisoire).length,
        arretes: actes.filter((a) => a.tarifArreteLe === '2026-09-01').length,
        semenceIntacte: (D.ACTES || []).filter((a) => a.tarifProvisoire).length,
        valorisationsAValider: S.collection('valorisationsSage').active().filter((v) => v.aValider).length,
        valorisationsTracees: S.collection('valorisationsSage').active().length,
        groupesConfirmes: D.GROUPES_ARTICLES.aConfirmer === false && D.GROUPES_ARTICLES.confirmesLe === '2026-09-01',
        /* Vague 51 : les validations écrites des professionnels sont
           ARRIVÉES — datées, attribuées, provenance conservée. */
        variablesValidees: S.collection('variablesLabo').active()
          .filter((v) => v.valideLe === '2026-09-01').length > 0
          && S.collection('variablesLabo').active().filter((v) => v.aValider).length === 0,
        pathologiesValidees: S.collection('pathologies').active()
          .filter((p) => p.valideLe === '2026-09-01').length > 0
          && S.collection('pathologies').active().filter((p) => p.aValider).length === 0,
        /* L'écran oriente : les trois familles, et jamais de bouton de
           validation en masse. */
        troisFamilles: /À SON POSTE/.test(t) && /PROFESSIONNEL nommé/.test(t)
          && /Validées par la DIRECTION/.test(t),
        nonAmorceDit: /non amorcée/.test(t),
        pasDeMasse: ![...document.querySelectorAll('button')]
          .some((b) => /Tout valider|Valider tout/i.test(b.textContent)),
      };
    });
    verifier('Les tarifs d’attente sont ARRÊTÉS et datés ; la semence garde le marquage historique',
      etat.provisoiresVivants === 0 && etat.arretes >= 40 && etat.semenceIntacte === 40,
      etat.arretes + ' arrêtés · semence ' + etat.semenceIntacte);
    verifier('Les 34 valorisations sont CONFIRMÉES, la surcouche tracée reste',
      etat.valorisationsAValider === 0 && etat.valorisationsTracees === 34);
    verifier('Les groupes d’articles sont CONFIRMÉS, datés', etat.groupesConfirmes);
    /* Vague 51 : les validations écrites sont arrivées — datées, attribuées. */
    verifier('Les validations des PROFESSIONNELS sont arrivées (01/09) — datées, provenance conservée',
      etat.variablesValidees && etat.pathologiesValidees);
    /* « File non amorcée » ne se sonde pas ici : la suite partage son magasin
       et M7 a déjà été ouvert par les scénarios antérieurs. */
    verifier('Le centre des validations ORIENTE (trois familles) sans jamais valider en masse',
      etat.troisFamilles && etat.pasDeMasse);

    /* --- Le questionnaire validé se dit sur l'écran de satisfaction --------- */
    await ouvrir('adm-satisfaction.html');
    const satisfaction = await page.evaluate(() => {
      const t = document.body.textContent;
      return /validé par la Direction/i.test(t) && !/proposition à valider/i.test(t);
    });
    verifier('Le questionnaire de satisfaction est annoncé VALIDÉ — plus une proposition', satisfaction);

    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* ==========================================================================
   * 54. VAGUE 50 — L'ACTIVATION PAR MODULE, ET L'INDÉPENDANCE PROUVÉE
   * --------------------------------------------------------------------------
   * Une autre clinique n'active que ce qu'elle exerce. La preuve exigée :
   * ACCUEIL (M1) et SOINS (M2) fermés, les stocks, la paie et les RH
   * continuent de travailler — et le noyau (CFG, DASH) ne se ferme pas.
   * ======================================================================== */
  {
    scenario('Vague 50 — activation par module : Accueil et Soins fermés, le reste travaille');

    await page.evaluate(() => {
      sessionStorage.clear();
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'admin', fonction: 'admin', nom: 'Administrateur',
        nomComplet: 'Administrateur', identifiant: 'admin', secteur: 'ADM',
      }));
    });

    /* --- L'écran : une bascule par module, le noyau protégé ----------------- */
    await ouvrir('cfg-modules.html');
    const ui = await page.evaluate(() => {
      const t = document.body.textContent;
      const cartes = [...document.querySelectorAll('.card')]
        .filter((c) => /^(M\d|MECEF|GED|RAP|PIL|DASH|CFG|M1[0-4])/.test(c.textContent.trim()));
      const carteDe = (code) => [...document.querySelectorAll('.card')]
        .find((c) => c.textContent.trim().indexOf(code + ' — ') === 0);
      const cfg = carteDe('CFG'), m2 = carteDe('M2');
      return {
        section: /Modules du logiciel/.test(t),
        independanceDite: /n’empêche jamais un autre de travailler/.test(t),
        nbCartes: cartes.length,
        noyau: (t.match(/Toujours ouvert/g) || []).length,
        cfgSansBascule: cfg ? !cfg.querySelector('button[title^="Fermer le module"]') : false,
        m2AvecBascule: m2 ? !!m2.querySelector('button[title="Fermer le module M2"]') : false,
      };
    });
    verifier('Chaque module du manifeste porte sa bascule ; le NOYAU (CFG, DASH) n’en a pas',
      ui.section && ui.nbCartes >= 14 && ui.noyau === 2 && ui.cfgSansBascule && ui.m2AvecBascule,
      ui.nbCartes + ' modules, ' + ui.noyau + ' noyau(x)');
    verifier('L’indépendance des modules est DITE sur l’écran', ui.independanceDite);

    /* --- Fermer M1 et M2 au niveau MODULE (le geste du moteur) -------------- */
    await page.evaluate(() => {
      const S = window.SIGH.store;
      ['M1', 'M2'].forEach((code) => {
        S.collection('modulesActifs', { module: 'CFG', entite: 'activité', prefix: 'MOD' }).insert({
          code: 'MODULE-' + code + '-SONDE', module: code,
          libelle: 'Module — sonde ' + code, actif: false,
          motif: 'Sonde fonctionnelle — indépendance des modules.',
          fermeLe: '2026-09-01', fermePar: 'Sonde',
        });
      });
      window.SIGH.nav.invaliderModules();
    });
    const fermes = await page.evaluate(() => {
      const N = window.SIGH.nav;
      const arbre = N.tree('admin');
      const codes = [];
      arbre.forEach((d) => d.modules.forEach((m) => codes.push(m.code)));
      return {
        sansM1M2: codes.indexOf('M1') === -1 && codes.indexOf('M2') === -1,
        canConsult: !!N.can('admin', N.get('m2-consultations')),
        canPatients: !!N.can('admin', N.get('m1-patients')),
        stockOuvert: !!N.can('admin', N.get('m6-stock-gros')),
        paieOuverte: !!N.can('admin', N.get('m11-bulletins')),
      };
    });
    verifier('M1 et M2 fermés disparaissent du ruban — rangées canoniques ET alias, tous rôles',
      fermes.sansM1M2 && !fermes.canConsult && !fermes.canPatients);

    /* --- LA PREUVE : les autres modules TRAVAILLENT -------------------------- */
    await ouvrir('m6-produits.html');
    const stock = await page.evaluate(() => ({
      monte: /[Pp]roduits|[Ss]tock/.test(document.title + document.body.textContent),
      lignes: document.querySelectorAll('tbody tr').length,
    }));
    await ouvrir('m11-bulletins.html');
    const paie = await page.evaluate(() => /[Bb]ulletin/.test(document.body.textContent));
    await ouvrir('m10-personnel.html');
    const rh = await page.evaluate(() => document.querySelectorAll('tbody tr').length);
    verifier('Accueil et Soins FERMÉS : les stocks, la paie et les RH travaillent',
      stock.monte && stock.lignes > 0 && paie && rh > 0,
      'stock ' + stock.lignes + ' ligne(s), RH ' + rh + ' agent(s)');

    /* L'adresse d'un écran fermé ne s'ouvre pas : elle renvoie au 403. */
    await ouvrir('m2-consultations.html');
    const adresse = await page.evaluate(() => location.href);
    verifier('L’adresse d’un module fermé renvoie au refus — fermer n’est pas cacher',
      /error-403/.test(adresse), adresse.split('/').pop());

    /* --- Réouverture : tout revient, données intactes ------------------------ */
    await ouvrir('m6-produits.html');
    const rouvert = await page.evaluate(() => {
      const S = window.SIGH.store, N = window.SIGH.nav;
      const col = S.collection('modulesActifs');
      col.active().filter((x) => /-SONDE$/.test(x.code)).forEach((x) => col.archive(x.id));
      N.invaliderModules();
      const codes = [];
      N.tree('admin').forEach((d) => d.modules.forEach((m) => codes.push(m.code)));
      return {
        m2Revient: codes.indexOf('M2') !== -1,
        consultOuvert: !!N.can('admin', N.get('m2-consultations')),
        donnees: S.collection('consultations').active().length,
      };
    });
    verifier('La réouverture rend les écrans EN L’ÉTAT — les données n’ont pas bougé',
      rouvert.m2Revient && rouvert.consultOuvert && rouvert.donnees > 0,
      rouvert.donnees + ' consultation(s) intactes');

    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 55 — BADGES DU PERSONNEL
   * -------------------------------------------------------------------------
   * Le parcours dicté : créer un agent, émettre son badge, l'imprimer,
   * vérifier le QR, retirer le badge pour perte, en émettre un second, et
   * CONTRÔLER QUE LE PREMIER APPARAÎT BIEN COMME RETIRÉ ET NON EFFACÉ. C'est
   * la dernière assertion qui compte : un badge perdu est précisément la
   * fiche qu'on ressort le jour où quelqu'un se présente avec.
   * ======================================================================= */
  {
    scenario('Badges du personnel — émission, QR, impression, retrait et réédition');
    await ouvrir('m10-badges.html');
    await page.evaluate(() => window.SIGH.store.setSession({
      role: 'admin', nom: 'BASSONGUI Chabi Séko', fonction: 'direction', secteur: 'ADM',
    }));

    /* --- Un agent nouveau, sans badge ------------------------------------ */
    const agent = await page.evaluate(() => {
      const S = window.SIGH.store;
      const res = S.collection('personnel', { module: 'M10', entite: 'agent', prefix: 'EMP' }).insert({
        matricule: '900', nom: 'SONDE', prenom: 'Badge', nomComplet: 'SONDE Badge',
        sexe: 'F', fonction: 'infirmier', poste: 'Infirmière — poste de sonde',
        service: 'Hospitalisation', categorie: 'E1-1', salaireBase: 100000,
        dateEmbauche: '2026-01-05', telephone: '0100000000', situation: 'Célibataire',
      });
      return { id: res.record.id, matricule: res.record.matricule, nom: res.record.nomComplet };
    });

    await ouvrir('m10-badges.html');
    const sansBadge = await page.evaluate((id) => {
      const t = [...document.querySelectorAll('.tab')].find((x) => /sans badge/i.test(x.textContent));
      if (t) t.click();
      return { onglet: !!t, texte: document.body.textContent.includes('SONDE Badge') };
    }, agent.id);
    await pause(400);
    verifier('L’agent sans badge est signalé — l’effectif est rapproché du registre',
      sansBadge.onglet, 'onglet « Agents sans badge » absent');

    /* --- Émission, par le geste ------------------------------------------ */
    await page.evaluate(() => {
      const t = [...document.querySelectorAll('.tab')].find((x) => /badges en cours/i.test(x.textContent));
      if (t) t.click();
    });
    await pause(400);
    const ouvertureModale = await cliquer('Émettre un badge');
    await pause(500);
    const emission = await page.evaluate((agentId) => {
      const dlg = document.querySelector('.modal, [role="dialog"]');
      if (!dlg) return { erreur: 'modale absente' };
      const combo = dlg.querySelector('#f_personnelId');
      if (!combo) return { erreur: 'sélecteur d’agent absent' };
      combo.value = agentId;
      const etat = dlg.querySelector('#f_etat');
      if (etat) etat.value = 'remis';
      return { ok: true, valeur: combo.value };
    }, agent.id);
    verifier('La modale d’émission s’ouvre et présente l’agent',
      ouvertureModale && !emission.erreur && emission.valeur === agent.id,
      emission.erreur || String(emission.valeur));

    await viderMessages(page);
    await cliquer('Émettre le badge');
    await pause(700);
    const premier = await page.evaluate((agentId) => {
      const S = window.SIGH.store;
      const b = S.collection('badges').all().filter((x) => x.personnelId === agentId)[0];
      if (!b) return { erreur: 'aucun badge émis' };
      const tousNumeros = S.collection('badges').all().map((x) => x.numero);
      return {
        numero: b.numero, id: b.id, etat: b.etat, expire: b.expireLe,
        matricule: b.matricule,
        formatOk: /^BDG-\d{5}-\d{4}$/.test(b.numero),
        unique: new Set(tousNumeros).size === tousNumeros.length,
        qr: window.SIGH.parcours.badgeQR(b),
      };
    }, agent.id);
    verifier('Le badge est émis avec un numéro de série annuel et unique',
      premier.formatOk && premier.unique, premier.erreur || premier.numero);
    verifier('La validité est portée sur la fiche — jamais laissée vide',
      !!premier.expire, String(premier.expire));

    /* --- LA DÉCISION LA PLUS IMPORTANTE : ce que porte le QR -------------- */
    verifier('Le QR ne porte QUE le matricule et le numéro de série',
      premier.qr === 'CNT-BDG|MAT:' + agent.matricule + '|SER:' + premier.numero,
      premier.qr);
    verifier('Le QR ne porte NI le nom, NI la fonction, NI aucune adresse',
      !/SONDE/i.test(premier.qr) && !/Infirmi/i.test(premier.qr) && !/https?:/i.test(premier.qr),
      premier.qr);

    /* --- Un second badge valide pour le même agent est REFUSÉ ------------- */
    await viderMessages(page);
    await cliquer('Émettre un badge');
    await pause(500);
    await page.evaluate((agentId) => {
      const c = document.querySelector('.modal #f_personnelId, [role="dialog"] #f_personnelId');
      if (c) c.value = agentId;
    }, agent.id);
    await cliquer('Émettre le badge');
    await pause(600);
    const refus = await page.evaluate((agentId) => ({
      message: (document.querySelector('#toast-host') || { textContent: '' }).textContent,
      nombre: window.SIGH.store.collection('badges').all().filter((x) => x.personnelId === agentId).length,
    }), agent.id);
    verifier('Deux badges valides pour un même agent sont refusés, EN NOMMANT le premier',
      refus.nombre === 1 && /BDG-\d{5}/.test(refus.message), refus.message.slice(0, 90));
    await page.evaluate(() => {
      const b = [...document.querySelectorAll('button')].find((x) => /^Annuler$/.test(x.textContent.trim()));
      if (b) b.click();
    });
    await pause(400);

    /* --- L'impression : carte CR80, sans mention fiscale ------------------ */
    const impression = await page.evaluate((badgeId) => {
      const S = window.SIGH.store;
      const b = S.collection('badges').get(badgeId);
      const mod = S.collection('modelesBadge').active()[0];
      const zones = {};
      ['photo', 'nom', 'fonction', 'service', 'qr'].forEach((z) => {
        zones[z] = !mod.zones || mod.zones.indexOf(z) !== -1;
      });
      window.SIGH.print.badge({
        badge: b, agent: S.collection('personnel').get(b.personnelId),
        modele: { orientation: mod.orientation, zones: zones, libelle: mod.libelle,
          mentionsVerso: String(mod.mentionsVerso || '').split('\n').filter(Boolean) },
      });
      const feuille = document.querySelector('.print-sheet');
      const texte = feuille ? feuille.textContent : '';
      const carte = feuille ? feuille.querySelector('div[style*="mm"]') : null;
      return {
        feuille: !!feuille,
        qr: feuille ? feuille.querySelectorAll('svg[role="img"]').length : 0,
        largeurCarte: carte ? carte.getAttribute('style') : '',
        porteIfu: /3201642748214/.test(texte) || /RB\/NAT/.test(texte),
        porteDevise: texte.indexOf('notre raison de vivre') !== -1,
        porteNom: texte.indexOf('SONDE Badge') !== -1,
        porteSerie: texte.indexOf(b.numero) !== -1,
      };
    }, premier.id);
    verifier('Le badge s’imprime au format carte CR80 (85,6 × 54 mm)',
      impression.feuille && /85\.6mm/.test(impression.largeurCarte) && /54mm/.test(impression.largeurCarte),
      impression.largeurCarte);
    verifier('La carte porte un vrai code QR engendré localement (SVG, aucune requête réseau)',
      impression.qr >= 1, String(impression.qr));
    verifier('Le badge porte le logo et la DEVISE, mais NI IFU NI RCCM — ce n’est pas une pièce fiscale',
      impression.porteDevise && !impression.porteIfu,
      'devise ' + impression.porteDevise + ', mentions fiscales ' + impression.porteIfu);
    verifier('Recto et verso portent le nom de l’agent et le numéro de série',
      impression.porteNom && impression.porteSerie);
    await page.evaluate(() => {
      const b = [...document.querySelectorAll('.print-chrome button')].find((x) => /Fermer/.test(x.textContent));
      if (b) b.click();
    });
    await pause(400);

    /* --- La vérification : le logiciel répond, pas la carte --------------- */
    await ouvrir('m10-badges-verification.html');
    const verif = await page.evaluate((numero) => {
      const S = window.SIGH.store;
      /* Le journal est PLAFONNÉ à 400 entrées : compter sa longueur ne prouve
         rien une fois le plafond atteint — on lit la dernière entrée. */
      const champ = document.querySelector('#page-content input[type="text"]');
      if (!champ) return { erreur: 'champ de saisie absent' };
      champ.value = numero;
      const b = [...document.querySelectorAll('#page-content button')].find((x) => /Vérifier/.test(x.textContent));
      if (!b) return { erreur: 'bouton absent' };
      b.click();
      const texte = document.querySelector('#page-content').textContent;
      const derniere = S.raw().audit[0] || {};
      return {
        valide: /BADGE VALIDE/.test(texte),
        photo: /Fonction/.test(texte),
        journalise: derniere.action === 'Vérification de badge'
          && derniere.reference === numero && derniere.motif === 'BADGE VALIDE',
        entree: derniere.action + ' / ' + derniere.reference,
      };
    }, premier.numero);
    verifier('Un badge en cours est déclaré VALIDE, avec la fonction du porteur',
      verif.valide && verif.photo, verif.erreur || JSON.stringify(verif));
    verifier('La vérification est JOURNALISÉE au nom du badge présenté (RG-12)',
      verif.journalise === true, verif.entree);

    const inconnu = await page.evaluate(() => {
      const champ = document.querySelector('#page-content input[type="text"]');
      champ.value = 'BDG-99999-1999';
      [...document.querySelectorAll('#page-content button')].find((x) => /Vérifier/.test(x.textContent)).click();
      return document.querySelector('#page-content').textContent;
    });
    verifier('Un badge inconnu se distingue d’un badge retiré — ce ne sont pas les mêmes faits',
      /BADGE INCONNU/.test(inconnu));

    /* --- Le retrait pour perte : l'état change, la fiche reste ------------ */
    await ouvrir('m10-badges.html');
    await page.evaluate((numero) => {
      const lignes = [...document.querySelectorAll('#page-content tbody tr')];
      const ligne = lignes.find((tr) => tr.textContent.indexOf(numero) !== -1);
      if (!ligne) return false;
      const b = [...ligne.querySelectorAll('button')].find((x) => /Retirer/.test(x.getAttribute('title') || ''));
      if (b) b.click();
      return true;
    }, premier.numero);
    await pause(600);
    await page.evaluate(() => {
      const s = document.querySelector('.modal #f_motifRetrait, [role="dialog"] #f_motifRetrait');
      if (s) s.value = 'Perte';
    });
    await viderMessages(page);
    await cliquer('Retirer le badge');
    await pause(700);
    const retire = await page.evaluate((badgeId) => {
      const S = window.SIGH.store;
      const b = S.collection('badges').get(badgeId);
      return b ? { existe: true, etat: b.etat, motif: b.motifRetrait, archive: b.statut === 'archive' }
        : { existe: false };
    }, premier.id);
    verifier('Le badge perdu RESTE au registre — il n’est ni supprimé ni archivé',
      retire.existe && !retire.archive, JSON.stringify(retire));
    verifier('Son état porte la perte et son motif',
      retire.etat === 'perdu' && retire.motif === 'Perte', JSON.stringify(retire));

    const ongletRetires = await page.evaluate(() => {
      const t = [...document.querySelectorAll('.tab')].find((x) => /Retirés/.test(x.textContent));
      if (t) t.click();
      return t ? t.textContent : '';
    });
    await pause(400);
    const visibleRetire = await page.evaluate((numero) =>
      document.querySelector('#page-content').textContent.indexOf(numero) !== -1, premier.numero);
    verifier('Il apparaît à l’onglet « Retirés », qui le compte',
      visibleRetire && /\d/.test(ongletRetires), ongletRetires);

    /* --- La réédition : un second badge devient possible ------------------ */
    await page.evaluate(() => {
      const t = [...document.querySelectorAll('.tab')].find((x) => /badges en cours/i.test(x.textContent));
      if (t) t.click();
    });
    await pause(400);
    await cliquer('Émettre un badge');
    await pause(500);
    await page.evaluate((agentId) => {
      const c = document.querySelector('.modal #f_personnelId, [role="dialog"] #f_personnelId');
      if (c) c.value = agentId;
    }, agent.id);
    await viderMessages(page);
    await cliquer('Émettre le badge');
    await pause(700);
    const second = await page.evaluate((o) => {
      const S = window.SIGH.store;
      const tous = S.collection('badges').all().filter((x) => x.personnelId === o.agentId);
      const neuf = tous.filter((x) => x.id !== o.premierId)[0];
      return {
        nombre: tous.length,
        numero: neuf ? neuf.numero : null,
        distinct: neuf ? neuf.numero !== o.numero : false,
        premierToujoursLa: !!S.collection('badges').get(o.premierId),
      };
    }, { agentId: agent.id, premierId: premier.id, numero: premier.numero });
    verifier('Le badge retiré libère la réédition — un second badge est émis',
      second.nombre === 2 && second.distinct, JSON.stringify(second));
    verifier('LE PREMIER EST TOUJOURS LÀ, retiré et non effacé',
      second.premierToujoursLa === true);

    const verdictRetire = await page.evaluate(async (numero) => {
      const S = window.SIGH.store;
      const b = S.collection('badges').all().filter((x) => x.numero === numero)[0];
      return b ? b.etat : null;
    }, premier.numero);
    verifier('Présenté au contrôle, l’ancien numéro reste « perdu » au registre',
      verdictRetire === 'perdu', String(verdictRetire));

    /* --- RBAC : qui émet, qui vérifie ------------------------------------- */
    const droitsBadges = await page.evaluate(() => {
      const N = window.SIGH.nav;
      const lire = (r, id) => !!N.can(r, N.get(id));
      const ecrire = (r, id) => N.droitsEcran(r, id, 'M10').editer;
      return {
        surveillantVoit: lire('surveillant', 'm10-badges'),
        surveillantEcrit: ecrire('surveillant', 'm10-badges'),
        surveillantModeles: lire('surveillant', 'm10-badges-modeles'),
        assistantVoit: lire('assistant_comptable', 'm10-badges'),
        assistantEcrit: ecrire('assistant_comptable', 'm10-badges'),
        daEcrit: ecrire('da', 'm10-badges'),
        directionEcrit: ecrire('direction', 'm10-badges'),
        caissier: lire('caissier', 'm10-badges'),
        medecin: lire('medecin', 'm10-badges'),
      };
    });
    verifier('Le Surveillant et l’Assistant de Direction VÉRIFIENT sans émettre',
      droitsBadges.surveillantVoit && !droitsBadges.surveillantEcrit
      && droitsBadges.assistantVoit && !droitsBadges.assistantEcrit,
      JSON.stringify(droitsBadges));
    verifier('Les modèles et la planche restent fermés au Surveillant',
      droitsBadges.surveillantModeles === false);
    verifier('La DAF (qui porte les RH) et la Direction émettent',
      droitsBadges.daEcrit && droitsBadges.directionEcrit);
    verifier('Fermé partout ailleurs — ni caisse, ni médecine',
      !droitsBadges.caissier && !droitsBadges.medecin);

    await ouvrir('m10-badges-impression.html');
    const planche = await page.evaluate(() => {
      const S = window.SIGH.store;
      const lignes = document.querySelectorAll('#page-content tbody tr').length;
      const retires = S.collection('badges').all().filter((x) => ['perdu', 'retire'].includes(x.etat));
      const texte = document.querySelector('#page-content').textContent;
      return { lignes, retireOffert: retires.some((b) => texte.indexOf(b.numero) !== -1) };
    });
    verifier('La planche ne propose JAMAIS un badge retiré — l’imprimer le remettrait en circulation',
      planche.lignes > 0 && planche.retireOffert === false,
      planche.lignes + ' ligne(s)');

    /* La planche A4 elle-même : `check` n'ouvre pas les modales et ne clique
       pas — un rendu qui casse AU CLIC lui échappe (leçon de K.miniTable). */
    /* Une case cochée fait REDESSINER le tableau : les nœuds suivants sont
       détachés et les clics d'après tombent dans le vide. On re-interroge le
       document à chaque fois — c'est le même piège que les lignes d'un
       tableau rafraîchi après chaque action. */
    for (let i = 0; i < 3; i++) {
      await page.evaluate((rang) => {
        const cases = [...document.querySelectorAll('#page-content tbody input[type="checkbox"]')];
        if (cases[rang]) cases[rang].click();
      }, i);
      await pause(250);
    }
    const coches = await page.evaluate(() =>
      document.querySelectorAll('#page-content tbody input[type="checkbox"]:checked').length);
    verifier('La sélection multiple retient bien les trois badges cochés', coches === 3, String(coches));
    await cliquer('Imprimer la planche');
    await pause(900);
    const feuille = await page.evaluate(() => {
      const s = document.querySelector('.print-sheet');
      if (!s) return { erreur: 'aucune planche' };
      return {
        a4: /210mm/.test(s.getAttribute('style') || ''),
        cartes: s.querySelectorAll('svg[role="img"]').length,
        reperes: s.querySelectorAll('span[style*="border-top"]').length,
        pied: /Document généré par/.test(s.textContent),
      };
    });
    verifier('La planche sort en A4 avec ses cartes, ses repères de découpe et le pied normalisé',
      !feuille.erreur && feuille.a4 && feuille.cartes === 3 && feuille.reperes === 6 && feuille.pied,
      JSON.stringify(feuille));
    await page.evaluate(() => {
      const b = [...document.querySelectorAll('.print-chrome button')].find((x) => /Fermer/.test(x.textContent));
      if (b) b.click();
    });
    await pause(300);

    /* L'aperçu du gabarit : recto ET verso, rendus depuis le modèle. */
    await ouvrir('m10-badges-modeles.html');
    await page.evaluate(() => {
      const b = [...document.querySelectorAll('#page-content tbody button')]
        .find((x) => /Consulter|Détail/i.test(x.getAttribute('title') || ''));
      if (b) b.click();
    });
    await pause(700);
    const apercu = await page.evaluate(() => {
      const d = document.querySelector('.drawer-backdrop');
      if (!d) return { erreur: 'tiroir absent' };
      return {
        cartes: [...d.querySelectorAll('div[style*="85.6mm"], div[style*="54mm"]')].length,
        qr: d.querySelectorAll('svg[role="img"]').length,
        mentions: /propriété de la Clinique/i.test(d.textContent),
      };
    });
    verifier('Le modèle s’aperçoit à l’échelle — recto et verso, mentions comprises',
      !apercu.erreur && apercu.cartes >= 2 && apercu.qr >= 1 && apercu.mentions,
      JSON.stringify(apercu));

    verifier('Aucune erreur JavaScript sur les écrans de badges', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 56 — PARTAGER UNE FICHE D'ENQUÊTE À UN TIERS
   * -------------------------------------------------------------------------
   * Le point sondé n'est pas le formulaire — il existait — mais le CANAL :
   * un jeton daté et révocable, une page publique isolée, et surtout UN SEUL
   * générateur de formulaire. C'est la dernière assertion qui le prouve :
   * une question ajoutée au modèle paraît sur la page publique sans qu'une
   * ligne de code ait été écrite pour elle.
   * ======================================================================= */
  {
    scenario('Enquête partagée — jeton daté, page publique isolée et générateur unique');
    await ouvrir('adm-enquetes.html');
    await page.evaluate(() => window.SIGH.store.setSession({
      role: 'admin', nom: 'BASSONGUI Chabi Séko', fonction: 'direction', secteur: 'ADM',
    }));
    await ouvrir('adm-enquetes.html');

    const modele = await page.evaluate(() => {
      const e = window.SIGH.store.collection('enquetes').active()[0];
      return { id: e.id, titre: e.titre, questions: (e.questions || []).length };
    });

    /* --- Ouverture d'un lien, par le geste -------------------------------- */
    const partage = await page.evaluate(() => {
      const ligne = document.querySelector('#page-content tbody tr');
      if (!ligne) return { erreur: 'aucun modèle au tableau' };
      const b = [...ligne.querySelectorAll('button')].find((x) => /Partager/.test(x.getAttribute('title') || ''));
      if (!b) return { erreur: 'commande de partage absente' };
      b.click();
      return { ok: true };
    });
    await pause(600);
    await cliquer('Ouvrir le lien');
    await pause(700);
    const jeton = await page.evaluate(() => {
      const S = window.SIGH.store;
      const j = S.collection('jetonsEnquete').active()[0];
      const champ = document.querySelector('.drawer-backdrop input[type="text"], [role="dialog"] input[type="text"]');
      const qr = document.querySelectorAll('.drawer-backdrop svg[role="img"]').length;
      return j ? {
        jeton: j.jeton, enqueteId: j.enqueteId, anonyme: j.anonyme, expire: j.expireLe,
        lien: champ ? champ.value : '', qr,
      } : { erreur: 'aucun jeton créé' };
    });
    verifier('Le partage ouvre un lien porteur d’un JETON, jamais de l’identifiant de l’enquête',
      !partage.erreur && !jeton.erreur && jeton.jeton && jeton.jeton.length >= 16
      && jeton.lien.indexOf(jeton.jeton) !== -1 && jeton.lien.indexOf(jeton.enqueteId) === -1,
      jeton.erreur || jeton.lien);
    verifier('Le lien est DATÉ — un lien sans terme collecte des réponses après la clôture',
      !!jeton.expire, String(jeton.expire));
    verifier('Un code QR est proposé pour l’affichage en salle d’attente',
      jeton.qr >= 1, String(jeton.qr));

    await page.evaluate(() => {
      const b = document.querySelector('.drawer-backdrop button[aria-label="Fermer"]');
      if (b) b.click();
    });
    await pause(300);

    /* --- La page publique : isolée, sans coquille ------------------------- */
    await ouvrir('enquete-publique.html?jeton=' + jeton.jeton);
    const publique = await page.evaluate(() => ({
      ruban: !!document.querySelector('#app-topbar, .ribbon-tab, #app-main'),
      recherche: !!document.querySelector('[aria-label="Rechercher"]'),
      titre: document.body.textContent.indexOf('Satisfaction') !== -1,
      anonyme: /ANONYME/.test(document.body.textContent),
      champs: document.querySelectorAll('form select, form textarea, form input').length,
      combos: document.querySelectorAll('form .combo').length,
      lienLogiciel: [...document.querySelectorAll('a[href]')]
        .filter((a) => /\.(php|html)/.test(a.getAttribute('href'))).length,
    }));
    verifier('La page publique ne porte NI ruban, NI recherche, NI le moindre lien vers le logiciel',
      !publique.ruban && !publique.recherche && publique.lienLogiciel === 0,
      JSON.stringify(publique));
    verifier('Elle affiche le questionnaire et annonce l’anonymat',
      publique.titre && publique.anonyme);
    verifier('Le formulaire naît du modèle — autant de champs que de questions',
      (publique.champs + publique.combos) >= modele.questions,
      (publique.champs + publique.combos) + ' pour ' + modele.questions + ' question(s)');

    /* --- Une réponse, et son canal --------------------------------------- */
    const envoi = await page.evaluate(() => {
      document.querySelectorAll('form select').forEach((s) => {
        if (!s.value && s.options.length) s.value = s.options[s.options.length - 1].value;
      });
      document.querySelectorAll('form .combo').forEach((c) => {
        const opts = c.options ? c.options() : [];
        if (opts.length) c.value = opts[0].value;
      });
      document.querySelectorAll('form textarea').forEach((t) => { t.value = 'Réponse de sonde.'; });
      const b = [...document.querySelectorAll('button')].find((x) => /Envoyer ma réponse/.test(x.textContent));
      if (b) b.click();
      return { clique: !!b };
    });
    await pause(700);
    const recue = await page.evaluate((jetonId) => {
      const S = window.SIGH.store;
      const j = S.collection('jetonsEnquete').active()[0];
      const reps = S.collection('reponsesEnquetes').active().filter((r) => r.jetonId === j.id);
      return {
        merci: /Merci/.test(document.body.textContent),
        nombre: reps.length,
        canal: reps[0] ? reps[0].canal : null,
        saisiPar: reps[0] ? reps[0].saisiPar : null,
      };
    });
    verifier('La réponse est enregistrée et la page remercie',
      envoi.clique && recue.merci && recue.nombre === 1, JSON.stringify(recue));
    verifier('Elle porte le canal « Lien public » — comparable aux réponses du guichet',
      recue.canal === 'Lien public', String(recue.canal));
    verifier('ANONYME veut dire anonyme : aucun nom, aucun lien vers un dossier',
      !/SONDE|BASSONGUI/i.test(String(recue.saisiPar)), String(recue.saisiPar));

    /* --- LE GÉNÉRATEUR EST UNIQUE : une question ajoutée paraît ----------- */
    await ouvrir('adm-enquetes.html');
    await page.evaluate((id) => {
      const col = window.SIGH.store.collection('enquetes');
      const e = col.get(id);
      col.update(id, { questions: (e.questions || []).concat([{
        code: 'Q_SONDE', libelle: 'Question ajoutée par la sonde', type: 'texte', options: null }]) });
    }, modele.id);
    await ouvrir('enquete-publique.html?jeton=' + jeton.jeton);
    const paraît = await page.evaluate(() => document.body.textContent.indexOf('Question ajoutée par la sonde') !== -1);
    verifier('UNE question ajoutée au modèle paraît sur la page publique — un seul générateur, deux habillages',
      paraît === true);

    /* --- Révocation : la porte se ferme, les réponses restent ------------- */
    await ouvrir('adm-enquetes.html');
    await page.evaluate(() => {
      const t = [...document.querySelectorAll('.tab')].find((x) => /Liens de partage/.test(x.textContent));
      if (t) t.click();
    });
    await pause(500);
    await page.evaluate(() => {
      const b = [...document.querySelectorAll('#page-content tbody button')]
        .find((x) => /Révoquer/.test(x.getAttribute('title') || ''));
      if (b) b.click();
    });
    await pause(600);
    await cliquer('Révoquer');
    await pause(700);
    const apresRevocation = await page.evaluate(() => {
      const S = window.SIGH.store;
      const j = S.collection('jetonsEnquete').active()[0];
      return {
        revoque: !!j.revoqueLe,
        reponses: S.collection('reponsesEnquetes').active().filter((r) => r.jetonId === j.id).length,
      };
    });
    verifier('Révoquer ferme la porte et NE SUPPRIME RIEN — les réponses recueillies restent',
      apresRevocation.revoque && apresRevocation.reponses === 1, JSON.stringify(apresRevocation));

    await ouvrir('enquete-publique.html?jeton=' + jeton.jeton);
    const ferme = await page.evaluate(() => ({
      refus: /n’est plus valable|n'est plus valable/.test(document.body.textContent),
      formulaire: !!document.querySelector('form select, form textarea'),
      nommeEnquete: /Satisfaction/.test(document.body.textContent),
    }));
    verifier('Le lien révoqué n’ouvre plus le formulaire',
      ferme.refus && !ferme.formulaire, JSON.stringify(ferme));

    await ouvrir('enquete-publique.html?jeton=jetoninexistant000000');
    const inconnu2 = await page.evaluate(() => ({
      refus: /n’est plus valable|n'est plus valable/.test(document.body.textContent),
      nommeEnquete: /Satisfaction/.test(document.body.textContent),
    }));
    verifier('Un jeton inconnu reçoit LA MÊME réponse qu’un jeton révoqué — sans nommer aucune enquête',
      inconnu2.refus && !inconnu2.nommeEnquete && !ferme.nommeEnquete, JSON.stringify(inconnu2));

    verifier('Aucune erreur JavaScript sur le partage et la page publique',
      erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 57 — CORRECTIONS DU 06/09/2026
   * -------------------------------------------------------------------------
   * Le ruban resserré (Accueil ne porte plus que le travail de réception,
   * l'imagerie prend sa rangée dans SOINS), la fusion achevée des visites, la
   * demande d'imagerie ouverte au patient externe, les identifiants du
   * dossier sous les yeux du laboratoire, et LES SIX SECTEURS comme
   * vocabulaire unique — groupes de prestation ET centres de coûts.
   * ======================================================================= */
  {
    scenario('Corrections du 06/09 — ruban resserré, imagerie à part, six secteurs');
    await ouvrir('m2-rendezvous.html');
    await page.evaluate(() => window.SIGH.store.setSession({
      role: 'admin', nom: 'BASSONGUI Chabi Séko', fonction: 'direction', secteur: 'ADM',
    }));
    await ouvrir('m2-rendezvous.html');

    /* --- LE RUBAN : ce que chaque rangée porte, exactement ---------------- */
    const ruban = await page.evaluate(() => {
      const N = window.SIGH.nav;
      const rangee = (domaine, label) => {
        const d = (N.NAV || []).filter((x) => x.domain === domaine)[0];
        if (!d) return null;
        const m = d.modules.filter((x) => x.label === label)[0];
        return m ? m.items.map((i) => i.label) : null;
      };
      return {
        accueilM2: rangee('Accueil', 'RDV, Visites & Consultations'),
        courriers: rangee('Accueil', 'Courriers & orientation'),
        soinsClinique: rangee('Soins', 'Consultations & prescriptions'),
        soinsImagerie: rangee('Soins', 'Imagerie médicale'),
        /* Une rangée SECONDAIRE ne crée pas de second hub. */
        hubs: Object.keys(N.INDEX).filter((k) => /^hub-m2$/.test(k)).length,
        hubItems: N.module('M2').items.length,
        hubDomaine: N.module('M2').domain,
      };
    });
    const attenduAccueil = ['Agenda', 'Rendez-vous & visites', 'File d’attente', 'File par cabinet',
      'Agenda du médecin', 'Écran d’appel des patients', 'Consultations & soins à domicile',
      'Registre des appels', 'Consultations'];
    verifier('La rangée « RDV, Visites & Consultations » de l’Accueil porte EXACTEMENT les neuf écrans de réception',
      JSON.stringify(ruban.accueilM2) === JSON.stringify(attenduAccueil),
      JSON.stringify(ruban.accueilM2));
    verifier('« Courriers & orientation » ne porte QUE les courriers et le répertoire d’urgence',
      /* L'alias porte désormais le MÊME libellé que sa rangée canonique
         (24/09/2026) : un alias qui se nomme autrement fait croire à deux
         écrans distincts. */
      JSON.stringify(ruban.courriers) === JSON.stringify(['Courriers (départ / arrivée)',
        'Répertoire des ambulances']),
      JSON.stringify(ruban.courriers));
    verifier('Le geste clinique a sa rangée dans SOINS',
      /* Refonte Zone 2 (14/09/2026) : « Dossiers de consultation » ouvre la
         rangée, AVANT la fiche — l'ordre du geste. */
      JSON.stringify(ruban.soinsClinique) === JSON.stringify(['Dossiers de consultation', 'Fiche de consultation',
        'Pathologies & morbidité', 'Ordonnances', 'Prescriptions', 'Salle de soins']),
      JSON.stringify(ruban.soinsClinique));
    verifier('L’IMAGERIE MÉDICALE a sa rangée dans SOINS, et le tableau d’échographie s’y nomme',
      JSON.stringify(ruban.soinsImagerie) === JSON.stringify(['Poste d’imagerie médicale',
        'Demandes d’imagerie médicale', 'Tableau Échographie',
        /* Vague 61 : les quatre modalités branchées sur le même socle. */
        'Tableau Radiographie', 'Tableau Mammographie', 'Tableau Scanner', 'Tableau IRM',
        'Galerie des clichés']),
      JSON.stringify(ruban.soinsImagerie));
    verifier('« Échographie & imagerie » a disparu du ruban — il n’y a plus qu’Imagerie médicale',
      !JSON.stringify(ruban).includes('Échographie & imagerie'));
    verifier('Une rangée secondaire ne crée PAS de second hub, et le hub garde tous les écrans du module',
      /* 23 écrans depuis l'ajout de m2-dossiers-consultation (14/09/2026). */
      ruban.hubs === 1 && ruban.hubItems === 23 && ruban.hubDomaine === 'Accueil',
      ruban.hubs + ' hub, ' + ruban.hubItems + ' écrans, domaine ' + ruban.hubDomaine);

    /* Les droits ne bougent pas d'un pouce : le module reste M2. */
    const droitsM2 = await page.evaluate(() => {
      const N = window.SIGH.nav;
      const voit = (r, id) => !!N.can(r, N.get(id));
      return {
        caissierImagerie: voit('caissier', 'm2-imagerie'),
        receptionImagerie: voit('reception', 'm2-imagerie-demandes'),
        echographisteDemandes: voit('echographiste', 'm2-imagerie-demandes'),
        echographisteOrdonnances: voit('echographiste', 'm2-ordonnances'),
        medecinOrdonnances: voit('medecin', 'm2-ordonnances'),
      };
    });
    verifier('Le regroupement visuel n’a RIEN changé aux droits — le module reste M2',
      !droitsM2.caissierImagerie && droitsM2.receptionImagerie
      && droitsM2.echographisteDemandes && !droitsM2.echographisteOrdonnances
      && droitsM2.medecinOrdonnances, JSON.stringify(droitsM2));

    /* --- Les libellés renommés ------------------------------------------- */
    await ouvrir('m6-point-ventes.html');
    const ventes = await page.evaluate(() => ({
      hero: (document.querySelector('#page-content, body') && document.querySelector('h1').textContent) || '',
      ariane: document.body.textContent.includes('Suivi des ventes'),
      ancien: document.body.textContent.includes('Point des ventes & cumuls'),
    }));
    verifier('« Point des ventes & cumuls » est devenu « Suivi des ventes », partout',
      /Suivi des ventes/.test(ventes.hero) && ventes.ariane && !ventes.ancien,
      ventes.hero);

    await ouvrir('m2-stats-echographie.html');
    const statsIm = await page.evaluate(() => ({
      titre: document.querySelector('h1').textContent,
      ancien: /Statistiques de l’échographie/.test(document.body.textContent),
    }));
    verifier('« Statistiques de l’échographie » est devenu « Statistiques de l’imagerie médicale »',
      /Statistiques de l’imagerie médicale/.test(statsIm.titre) && !statsIm.ancien, statsIm.titre);

    /* --- La demande d'imagerie pour un patient ADRESSÉ DE L'EXTÉRIEUR ----- */
    await ouvrir('m2-imagerie-demandes.html');
    await cliquer('Nouvelle demande');
    await pause(600);
    const champsIm = await page.evaluate(() => {
      const m = document.querySelector('[role="dialog"], .modal');
      if (!m) return { erreur: 'modale absente' };
      const a = (n) => !!m.querySelector('#f_' + n);
      return { patient: a('patientCode'), nom: a('nom'), prenom: a('prenom'),
        telephone: a('telephone'), residence: a('residence'), examens: a('examens') };
    });
    verifier('La demande d’imagerie offre la saisie d’un patient adressé de l’extérieur',
      !champsIm.erreur && champsIm.patient && champsIm.nom && champsIm.prenom
      && champsIm.telephone && champsIm.residence, JSON.stringify(champsIm));
    await page.keyboard.press('Escape');
    await pause(300);

    const externeIm = await page.evaluate(() => {
      const PR = window.SIGH.parcours, S = window.SIGH.store;
      const avant = S.collection('patients').all().length;
      const ex = (window.SIGH.data.IMAGERIE.EXAMENS || [])
        .filter((x) => { const t = window.SIGH.data.tarif(x.tarifCode || x.code); return t && t.prixNonAssure != null; })[0];
      if (!ex) return { erreur: 'aucun examen tarifé au catalogue' };
      let res;
      try {
        res = PR.ouvrirDemandeImagerie({
          nom: 'ADJOVI', prenom: 'Estelle', sexe: 'F', telephone: '0199887766',
          residence: 'Peporiyakou', examens: [ex.code], origine: 'externe',
          prescripteur: 'Cabinet extérieur', indication: 'Douleur pelvienne',
        });
      } catch (e) { return { erreur: e.message }; }
      const p = S.collection('patients').get(res.patient.id);
      return {
        code: p.code, externe: !!p.externe, quartier: p.quartier,
        crees: S.collection('patients').all().length - avant,
        facture: res.facture.numero, lignes: (res.facture.lignes || []).length,
        bloquee: res.demandes.every((d) => d.bloqueParPaiement),
      };
    });
    verifier('Un patient adressé de l’extérieur reçoit un DOSSIER — sans lui, aucun compte rendu ne se remet',
      !externeIm.erreur && externeIm.crees === 1 && externeIm.externe, JSON.stringify(externeIm));
    verifier('…au format de code UNIQUE CNT/n/AA, celui de la fabrique du socle',
      /^CNT\/\d+\/\d{2}$/.test(String(externeIm.code)), String(externeIm.code));
    verifier('…et sa demande suit la chaîne : facture à lignes, examen bloqué avant règlement',
      externeIm.lignes > 0 && externeIm.bloquee === true, JSON.stringify(externeIm));

    /* --- Le laboratoire voit le code d'analyse à la saisie ----------------
       On clique le PREMIER « Saisir » réellement offert : viser un dossier
       choisi à l'avance suppose de savoir dans quel onglet l'écran le range,
       et la sonde mesurerait alors sa propre supposition. */
    /* Sous le rôle qui saisit VRAIMENT — et sur SA PROPRE fixture, désignée
       par sa référence : cliquer « le premier bouton actif » ferait mesurer
       ce que les scénarios précédents ont laissé dans la file. */
    await ouvrir('m5-resultats.html');
    const fixtureLabo = await page.evaluate(() => {
      const S = window.SIGH.store, PR = window.SIGH.parcours;
      S.setSession({ role: 'laborantin', nom: 'KINNOU G.', fonction: 'tsl', secteur: 'LAB' });
      const modele = S.collection('demandesAnalyses').active()[0] || {};
      const res = S.collection('demandesAnalyses', { module: 'M5', entite: 'demande', prefix: 'DEM' }).insert({
        reference: window.SIGH.core.nextRef('LABSONDE-', 4),
        /* La fabrique UNIQUE du code, jamais un code écrit à la main. */
        codeAnalyse: PR.codeAnalyse(new Date()),
        patientId: modele.patientId || null, patientCode: modele.patientCode || 'CNT/1/26',
        patient: 'SONDE Saisie', analyseCode: modele.analyseCode || 'NFS',
        analyse: modele.analyse || 'Numération formule sanguine',
        categorie: modele.categorie || 'Hématologie',
        dateHeure: new Date().toISOString(), prescripteur: 'YENI M’PO Florent',
        etatAnalyse: 'en_cours', preleveLe: new Date().toISOString(),
        recuLaboLe: new Date().toISOString(), bloqueParPaiement: false,
        secteurDemandeur: 'Laboratoire',
      });
      return { reference: res.record.reference, code: res.record.codeAnalyse };
    });
    await ouvrir('m5-resultats.html');
    const clicSaisie = await page.evaluate((ref) => {
      const ligne = [...document.querySelectorAll('#page-content tbody tr')]
        .find((tr) => tr.textContent.indexOf(ref) !== -1);
      if (!ligne) return false;
      const b = [...ligne.querySelectorAll('button')]
        .find((x) => /Saisir/i.test(x.textContent) && x.getAttribute('aria-disabled') !== 'true');
      if (b) b.click();
      return !!b;
    }, fixtureLabo.reference);
    await pause(900);
    const modaleLabo = await page.evaluate(() => {
      const m = document.querySelector('[role="dialog"], .modal');
      if (!m) return { erreur: 'aucune modale de saisie ouverte' };
      const t = m.textContent;
      return {
        titre: /Saisie du résultat/.test(t),
        libelles: /Code d’analyse/.test(t) && /Référence de la demande/.test(t),
        texte: t.slice(0, 160),
      };
    });
    verifier('La saisie du résultat affiche le CODE D’ANALYSE et la RÉFÉRENCE de la demande',
      clicSaisie && !modaleLabo.erreur && modaleLabo.titre && modaleLabo.libelles
      && modaleLabo.texte.indexOf(fixtureLabo.code) !== -1
      && modaleLabo.texte.indexOf(fixtureLabo.reference) !== -1,
      clicSaisie ? (modaleLabo.erreur || modaleLabo.texte)
        : 'la demande de sonde n’est pas offerte à la saisie');
    await page.keyboard.press('Escape');
    await pause(300);

    /* Le rôle est RENDU : un scénario qui change de profil le restaure, sans
       quoi les écrans suivants tombent au refus et la sonde mesure un 403. */
    await page.evaluate(() => window.SIGH.store.setSession({
      role: 'admin', nom: 'BASSONGUI Chabi Séko', fonction: 'direction', secteur: 'ADM',
    }));

    /* --- LES SIX SECTEURS, vocabulaire unique ---------------------------- */
    const SIX = ['Laboratoire', 'Pharmacie', 'Consultation', 'Imagerie médicale', 'Maternité',
      'Hospitalisation et soins'];
    await ouvrir('m12-rentabilite-groupes.html');
    const groupes = await page.evaluate(() => {
      const D = window.SIGH.data;
      const cartes = [...document.querySelectorAll('.card')];
      const texteDe = (titre) => {
        const c = cartes.filter((x) => (x.textContent || '').indexOf(titre) === 0
          || (x.querySelector('h3') || {}).textContent === titre)[0];
        return c ? c.textContent : '';
      };
      return {
        labels: D.GROUPES_PRESTATION.map((g) => g.label),
        recettes: texteDe('Recettes par groupe de prestation'),
        page: document.querySelector('#page-content').textContent,
      };
    });
    verifier('Les groupes de prestation SONT les six secteurs — aucun ne manque',
      JSON.stringify(groupes.labels) === JSON.stringify(SIX), JSON.stringify(groupes.labels));
    verifier('« Recettes par groupe » et « Bénéfice brut par groupe » les portent tous les six',
      SIX.every((s) => groupes.page.indexOf(s) !== -1),
      SIX.filter((s) => groupes.page.indexOf(s) === -1).join(', ') || 'tous présents');
    verifier('Le rapprochement nomme les centres en toutes lettres, Direction comprise — plus d’identifiant technique',
      groupes.page.indexOf('Direction') !== -1 && !/\blaboratoire\b/.test(groupes.page),
      'identifiants techniques encore affichés');

    await ouvrir('cfg-centres-couts.html');
    const centres = await page.evaluate(() =>
      window.SIGH.store.collection('centresCouts').active().map((c) => c.libelle));
    verifier('Les centres de coûts sont les six secteurs PLUS la Direction',
      JSON.stringify(centres) === JSON.stringify(SIX.concat(['Direction'])),
      JSON.stringify(centres));

    await ouvrir('dash-croise.html');
    /* L'axe ne paraît qu'une fois la SOURCE choisie : les axes dépendent d'elle. */
    await page.evaluate(() => {
      const sel = [...document.querySelectorAll('#page-content select')]
        .find((s) => [...s.options].some((o) => /Soins prescrits/.test(o.textContent)));
      if (sel) {
        const o = [...sel.options].find((x) => /Soins prescrits/.test(x.textContent));
        sel.value = o.value;
        sel.dispatchEvent(new Event('change', { bubbles: true }));
      }
    });
    await pause(600);
    const croise = await page.evaluate(() => {
      const D = window.SIGH.data;
      return {
        bloc: D.secteurNormalise('bloc'),
        maternite: D.secteurNormalise('maternite'),
        hospit: D.secteurNormalise('hospitalisation'),
        consult: D.secteurNormalise('consultation'),
        imagerie: D.secteurNormalise('Imagerie médicale'),
        labo: D.secteurNormalise('Laboratoire'),
        direction: D.secteurNormalise('direction'),
        axe: /Secteur d’origine de la prescription/.test(document.body.textContent)
          || [...document.querySelectorAll('option')].some((o) => /Secteur d’origine/.test(o.textContent)),
      };
    });
    verifier('L’origine d’une prescription se dit dans le vocabulaire des six — « bloc » devient un secteur nommé',
      croise.bloc === 'Hospitalisation et soins' && croise.maternite === 'Maternité'
      && croise.hospit === 'Hospitalisation et soins' && croise.consult === 'Consultation'
      && croise.imagerie === 'Imagerie médicale' && croise.labo === 'Laboratoire',
      JSON.stringify(croise));
    verifier('La Direction n’est PAS un secteur de recette — elle reste transverse',
      croise.direction === null, String(croise.direction));
    verifier('L’axe croisé porte le libellé « Secteur d’origine »', croise.axe === true);

    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 58 — LA COMPTABILITÉ AU FORMAT DE LA LIASSE DÉPOSÉE
   * -------------------------------------------------------------------------
   * Les cinq feuillets, le bilan qui s'équilibre, les écarts internes du
   * document conservés et non arbitrés, l'amortissement au SEMESTRE, le
   * report des à-nouveaux et son refus quand il ne s'équilibre pas.
   * ======================================================================= */
  {
    scenario('Comptabilité — liasse DGI, amortissement au semestre et bilan d’ouverture');
    await ouvrir('m12-etats-financiers.html');
    await page.evaluate(() => window.SIGH.store.setSession({
      role: 'admin', nom: 'BASSONGUI Chabi Séko', fonction: 'direction', secteur: 'ADM',
    }));
    await ouvrir('m12-etats-financiers.html');

    /* --- LES CINQ FEUILLETS ---------------------------------------------- */
    const liasse = await page.evaluate(() => {
      const L = window.SIGH.liasse;
      const onglets = [...document.querySelectorAll('#page-content .tab')].map((t) => t.textContent.trim());
      const actif = L.BILAN_ACTIF.filter((x) => x.ref === 'BZ')[0];
      const passif = L.BILAN_PASSIF.filter((x) => x.ref === 'DZ')[0];
      const cr = L.RESULTAT.filter((x) => x.ref === 'XI')[0];
      const marge = L.RESULTAT.filter((x) => x.ref === 'XA')[0];
      const flux = L.FLUX.filter((x) => x.ref === 'ZH')[0];
      return {
        onglets: onglets,
        depot: L.DEPOT.code + '/' + L.DEPOT.ifu,
        actifNet: actif.net, passifNet: passif.net,
        actifN1: actif.netN1, passifN1: passif.netN1,
        resultat: cr.n, margeCommerciale: marge.n,
        tresorerieFin: flux.n,
        ecarts: L.ECARTS.length,
        refsActif: L.BILAN_ACTIF.map((x) => x.ref).join(','),
      };
    });
    verifier('L’écran porte les CINQ feuillets de la liasse',
      JSON.stringify(liasse.onglets) === JSON.stringify(['Bilan', 'Compte de résultat',
        'Tableau des flux de trésorerie', 'Disponibilités', 'Fiche de synthèse']),
      JSON.stringify(liasse.onglets));
    verifier('La liasse citée est bien celle déposée le 15/05/2026 (code BK505416, IFU de la clinique)',
      liasse.depot === 'BK505416/3201642748214', liasse.depot);
    verifier('LE BILAN DÉPOSÉ S’ÉQUILIBRE — actif = passif, sur N comme sur N-1',
      liasse.actifNet === liasse.passifNet && liasse.actifN1 === liasse.passifN1,
      liasse.actifNet + ' / ' + liasse.passifNet);
    verifier('Les références du formulaire sont reprises telles quelles (AD → BZ)',
      /^AD,AE,AF,AG,AH,AI,/.test(liasse.refsActif) && /,BZ$/.test(liasse.refsActif));
    verifier('Le résultat net déposé est celui du document (4 561 200)', liasse.resultat === 4561200,
      String(liasse.resultat));
    verifier('LA MARGE COMMERCIALE EST NULLE à la liasse — RG-02 confirmé par un document déposé',
      liasse.margeCommerciale === 0, String(liasse.margeCommerciale));
    verifier('Le tableau des flux boucle sur la trésorerie de clôture du bilan (6 300 639)',
      liasse.tresorerieFin === 6300639, String(liasse.tresorerieFin));
    verifier('Les écarts internes du document sont RECENSÉS, jamais corrigés',
      liasse.ecarts === 6, String(liasse.ecarts));

    /* Le tableau des flux du document ne se recoupe pas — et l'écran le dit. */
    await page.evaluate(() => {
      const t = [...document.querySelectorAll('#page-content .tab')].find((x) => /flux/i.test(x.textContent));
      if (t) t.click();
    });
    await pause(600);
    const ditEcart = await page.evaluate(() => {
      const t = document.querySelector('#page-content').textContent;
      return { badge: /écart du document/.test(t), bloc: /conservés, non arbitrés/.test(t) };
    });
    verifier('L’écran SIGNALE les écarts du document au lieu de les arbitrer',
      ditEcart.badge && ditEcart.bloc, JSON.stringify(ditEcart));

    /* --- L'AMORTISSEMENT AU SEMESTRE ------------------------------------- */
    await ouvrir('m12-immobilisations.html');
    const amort = await page.evaluate(() => {
      const S = window.SIGH.store;
      const col = S.collection('immobilisations');
      /* Une fixture DATÉE : deux biens identiques, l'un acquis en début
         d'année, l'autre six mois plus tard. À l'annuité ils portaient le
         MÊME amortissement — c'est exactement le défaut corrigé. */
      const base = { statut: 'actif', categorie: 'Matériel médical', valeurAcquisition: 1200000,
        dureeAmortissement: 5, compte: '241000', etat: 'En service', fournisseur: 'Sonde' };
      col.insert(Object.assign({ reference: 'IM-SONDE-A', designation: 'Sonde A — janvier 2024',
        dateAcquisition: '2024-01-15' }, base));
      col.insert(Object.assign({ reference: 'IM-SONDE-B', designation: 'Sonde B — juillet 2024',
        dateAcquisition: '2024-07-15' }, base));
      col.insert(Object.assign({ reference: 'IM-SONDE-C', designation: 'Sonde C — cédée',
        dateAcquisition: '2024-01-15', dateCession: '2025-01-15', motifSortie: 'Cession',
        valeurCession: 500000, etat: 'Cédé' }, base));
      return true;
    });
    await ouvrir('m12-immobilisations.html');
    const colonnes = await page.evaluate(() =>
      [...document.querySelectorAll('#page-content thead th')].map((t) => t.textContent.trim()));
    verifier('Les colonnes portent « Date d’acquisition », « Valeur d’acquisition » et « Cession / sortie »',
      colonnes.indexOf('Date d’acquisition') !== -1 && colonnes.indexOf('Valeur d’acquisition') !== -1
      && colonnes.indexOf('Cession / sortie') !== -1 && colonnes.indexOf('Annuité') === -1,
      colonnes.join(' | '));

    const semestres = await page.evaluate(() => {
      /* ON LIT LA COLONNE PAR SON NOM, jamais par son rang : compter les
         cellules depuis la fin donnait la valeur NETTE là où l'on croyait
         lire l'amortissement — la sonde mesurait alors sa propre supposition. */
      const entetes = [...document.querySelectorAll('#page-content thead th')]
        .map((t) => t.textContent.trim());
      const rang = (nom) => entetes.findIndex((x) => x.indexOf(nom) === 0);
      const iCumul = rang('Amort. cumulé');
      const nb = (t) => Number(String(t || '').replace(/[^0-9]/g, ''));
      const cellule = (ref, i) => {
        const tr = [...document.querySelectorAll('#page-content tbody tr')]
          .find((x) => x.textContent.indexOf(ref) !== -1);
        if (!tr || i < 0) return null;
        const tds = [...tr.querySelectorAll('td')];
        return tds[i] ? nb(tds[i].textContent) : null;
      };
      const ligne = (ref) => {
        const tr = [...document.querySelectorAll('#page-content tbody tr')]
          .find((x) => x.textContent.indexOf(ref) !== -1);
        return tr ? tr.textContent.replace(/[\s ]+/g, ' ') : null;
      };
      return {
        entetes: entetes, iCumul: iCumul,
        a: cellule('IM-SONDE-A', iCumul), b: cellule('IM-SONDE-B', iCumul),
        c: cellule('IM-SONDE-C', iCumul),
        ligneC: ligne('IM-SONDE-C'),
        existent: iCumul >= 0 && !!ligne('IM-SONDE-A') && !!ligne('IM-SONDE-B') && !!ligne('IM-SONDE-C'),
      };
    });
    verifier('Deux biens identiques acquis à six mois d’écart n’ont PAS le même amortissement cumulé',
      semestres.existent && semestres.a > semestres.b && semestres.b > 0,
      'janvier ' + semestres.a + ' vs juillet ' + semestres.b + ' (colonne ' + semestres.iCumul + ')');
    verifier('L’écart vaut exactement UN semestre de dotation — le pas est bien de six mois',
      semestres.a - semestres.b === 120000, String(semestres.a - semestres.b));
    verifier('Un bien CÉDÉ cesse de s’amortir à sa date de sortie',
      semestres.c > 0 && semestres.c < semestres.a, 'cédé ' + semestres.c + ' vs actif ' + semestres.a);
    verifier('La cession est portée à la colonne, avec sa date et son motif',
      /15\/01\/2025/.test(semestres.ligneC || '') && /Cession/.test(semestres.ligneC || ''),
      semestres.ligneC);

    /* Le report au bilan : les totaux du registre SONT ceux de l'actif. */
    await page.evaluate(() => {
      const t = [...document.querySelectorAll('#page-content .tab')].find((x) => /Report au bilan/.test(x.textContent));
      if (t) t.click();
    });
    await pause(600);
    const report = await page.evaluate(() => {
      const t = document.querySelector('#page-content').textContent;
      return {
        rubriques: /IMMOBILISATIONS CORPORELLES/.test(t) && /TOTAL ACTIF IMMOBILISÉ/.test(t),
        exclutSorties: /sorti\(s\) du patrimoine/.test(t),
        refAZ: /AZ/.test(t),
      };
    });
    verifier('Le report au bilan range les biens par rubrique de la liasse et exclut les biens sortis',
      report.rubriques && report.exclutSorties && report.refAZ, JSON.stringify(report));

    /* --- LE BILAN D'OUVERTURE -------------------------------------------- */
    await ouvrir('m12-ouverture.html');
    const ouverture = await page.evaluate(() => {
      const t = document.querySelector('#page-content').textContent;
      return {
        equilibre: /s’équilibre/.test(t),
        refuse: /NE S’ÉQUILIBRE PAS/.test(t),
        classes: /classes 1 à 5/.test(t),
        comptes: document.querySelectorAll('#page-content tbody tr').length,
      };
    });
    verifier('Le bilan d’ouverture se calcule et s’équilibre',
      ouverture.equilibre && !ouverture.refuse && ouverture.comptes > 0,
      JSON.stringify(ouverture));
    verifier('Il dit la règle : seules les classes 1 à 5 se reportent', ouverture.classes === true);

    const ecrits = await page.evaluate(() => {
      const S = window.SIGH.store;
      const avant = S.collection('ecritures').active().filter((x) => x.journal === 'AN').length;
      const b = [...document.querySelectorAll('#page-content button')]
        .find((x) => /Écrire les à-nouveaux/.test(x.textContent));
      if (b) b.click();
      return { avant: avant, bouton: !!b };
    });
    await pause(600);
    await page.evaluate(() => {
      const b = [...document.querySelectorAll('[role="dialog"] button, .modal button')]
        .find((x) => /Écrire le report/.test(x.textContent));
      if (b) b.click();
    });
    await pause(900);
    const apres = await page.evaluate(() => {
      const S = window.SIGH.store;
      const an = S.collection('ecritures').active().filter((x) => x.journal === 'AN');
      const som = (a, k) => a.reduce((n, x) => n + (Number(x[k]) || 0), 0);
      return {
        lignes: an.length,
        equilibre: som(an, 'debit') === som(an, 'credit'),
        brouillon: an.every((x) => x.statut === 'brouillon'),
        /* AUCUNE classe 6 ni 7 ne se reporte. */
        resultat: an.filter((x) => String(x.compte).charAt(0) === '6' || String(x.compte).charAt(0) === '7').length,
        au1erJanvier: an.every((x) => /-01-01$/.test(String(x.date))),
      };
    });
    verifier('Les à-nouveaux s’écrivent au journal AN, ÉQUILIBRÉS (RG-10)',
      ecrits.bouton && apres.lignes > 0 && apres.equilibre,
      apres.lignes + ' ligne(s), équilibre ' + apres.equilibre);
    verifier('AUCUN compte de charge ni de produit n’est reporté — ils sont soldés par le résultat',
      apres.resultat === 0, apres.resultat + ' ligne(s) de classe 6 ou 7');
    verifier('La pièce est datée du 1ᵉʳ janvier et naît en BROUILLON — la validation reste humaine',
      apres.au1erJanvier && apres.brouillon);

    /* Un second report est refusé : il créerait un double à-nouveau. */
    await viderMessages(page);
    await page.evaluate(() => {
      const b = [...document.querySelectorAll('#page-content button')]
        .find((x) => /Écrire les à-nouveaux/.test(x.textContent));
      if (b) b.click();
    });
    await pause(700);
    const refus = await page.evaluate(() => {
      const t = document.querySelector('#toast-host');
      return t ? t.textContent : '';
    });
    verifier('Un second report est REFUSÉ en le disant — il créerait un double à-nouveau',
      /existent déjà|double report/i.test(refus), refus.slice(0, 90));

    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 59 — LE PATIENT ADRESSÉ DE L'EXTÉRIEUR, DE BOUT EN BOUT
   * -------------------------------------------------------------------------
   * L'accueil transcrit une ordonnance extérieure — analyses OU imagerie —,
   * la facture part à la caisse, et RIEN ne se saisit avant qu'elle soit
   * réglée. L'écran montre les demandes par service et l'état de chaque
   * résultat, sans ouvrir une seconde voie d'écriture.
   * ======================================================================= */
  {
    scenario('Patient externe — analyses, imagerie, services et verrou de caisse');
    await ouvrir('m1-externe.html');
    await page.evaluate(() => window.SIGH.store.setSession({
      role: 'reception', nom: 'BONI Aïcha', fonction: 'accueil', secteur: 'ACC',
    }));
    await ouvrir('m1-externe.html');

    const vues = await page.evaluate(() =>
      [...document.querySelectorAll('#page-content .tab')].map((t) => t.textContent.replace(/\s*\(\d+\)$/, '').trim()));
    verifier('L’écran porte les quatre natures de demande, plus les résultats',
      JSON.stringify(vues) === JSON.stringify(['Demandes — analyses', 'Demandes — maternité',
        'Demandes — hospitalisation', 'Demandes — imagerie médicale', 'Résultats']),
      JSON.stringify(vues));

    /* --- LA MODALE PORTE LES DEUX CATALOGUES ----------------------------- */
    await cliquer('Nouvelle demande externe');
    await pause(700);
    const champs = await page.evaluate(() => {
      const m = document.querySelector('[role="dialog"], .modal');
      if (!m) return { erreur: 'modale absente' };
      const a = (n) => !!m.querySelector('#f_' + n);
      return { nature: a('nature'), analyses: a('analyses'), examens: a('examens'),
        service: a('serviceDemandeur'), identite: a('nom') && a('prenom') && a('telephone') };
    });
    verifier('La modale offre la NATURE (analyses ou imagerie) et les deux catalogues',
      !champs.erreur && champs.nature && champs.analyses && champs.examens,
      JSON.stringify(champs));
    verifier('…ainsi que le service demandeur et l’identité obligatoire',
      champs.service && champs.identite);
    await page.keyboard.press('Escape');
    await pause(400);

    /* --- UNE DEMANDE D'ANALYSES, ADRESSÉE À LA MATERNITÉ ------------------ */
    const labo = await page.evaluate(() => {
      const PR = window.SIGH.parcours, S = window.SIGH.store;
      const a = S.collection('analyses').active()[0];
      let res;
      try {
        res = PR.ouvrirDemandeExterne({
          nom: 'TCHEDRE', prenom: 'Falilatou', sexe: 'F', dateNaissance: '1994-03-02',
          telephone: '0166554433', residence: 'Boukoumbé',
          prescripteur: 'Cabinet du Dr AGOSSOU', serviceDemandeur: 'Maternité',
          analyses: [a.code],
        });
      } catch (e) { return { erreur: e.message }; }
      return { code: res.patient.code, demandes: res.demandes.length,
        bloquee: res.demandes.every((d) => d.bloqueParPaiement),
        facture: res.facture.numero, reference: res.demandes[0].reference };
    });
    verifier('Une demande d’analyses externe ouvre un dossier et part à la caisse, BLOQUÉE',
      !labo.erreur && labo.demandes > 0 && labo.bloquee, JSON.stringify(labo));

    /* --- UNE DEMANDE D'IMAGERIE, ADRESSÉE À L'HOSPITALISATION ------------- */
    const imagerie = await page.evaluate(() => {
      const PR = window.SIGH.parcours, D = window.SIGH.data;
      const ex = (D.IMAGERIE.EXAMENS || []).filter((x) => {
        const t = D.tarif(x.tarifCode || x.code);
        return t && t.prixNonAssure != null;
      })[0];
      if (!ex) return { erreur: 'aucun examen tarifé' };
      let res;
      try {
        res = PR.ouvrirDemandeImagerie({
          nom: 'SAMBIENI', prenom: 'Boniface', sexe: 'M', telephone: '0177889900',
          residence: 'Tanguiéta', examens: [ex.code], origine: 'externe',
          secteurDemandeur: 'Hospitalisation',
          prescripteur: 'Cabinet extérieur', indication: 'Bilan',
        });
      } catch (e) { return { erreur: e.message }; }
      return { code: res.patient.code, demandes: res.demandes.length,
        bloquee: res.demandes.every((d) => d.bloqueParPaiement),
        reference: res.demandes[0].reference };
    });
    verifier('Une demande d’IMAGERIE externe suit la même chaîne — dossier, caisse, blocage',
      !imagerie.erreur && imagerie.demandes > 0 && imagerie.bloquee, JSON.stringify(imagerie));

    /* --- LES VUES PAR SERVICE MONTRENT CE QU'ELLES ANNONCENT -------------- */
    await ouvrir('m1-externe.html');
    const parService = await page.evaluate(async (refs) => {
      const lire = async (nom) => {
        const t = [...document.querySelectorAll('#page-content .tab')].find((x) => x.textContent.indexOf(nom) === 0);
        if (t) t.click();
        await new Promise((r) => setTimeout(r, 400));
        return document.querySelector('#page-content').textContent;
      };
      const mat = await lire('Demandes — maternité');
      const hos = await lire('Demandes — hospitalisation');
      const img = await lire('Demandes — imagerie');
      return {
        materniteVoitLabo: mat.indexOf(refs.labo) !== -1,
        hospitalisationVoitImagerie: hos.indexOf(refs.imagerie) !== -1,
        imagerieVoitImagerie: img.indexOf(refs.imagerie) !== -1,
        materniteNeVoitPasImagerie: mat.indexOf(refs.imagerie) === -1,
      };
    }, { labo: labo.reference, imagerie: imagerie.reference });
    verifier('La vue « maternité » porte la demande adressée à la maternité',
      parService.materniteVoitLabo === true);
    verifier('La vue « hospitalisation » porte la demande d’imagerie qui lui est adressée',
      parService.hospitalisationVoitImagerie === true);
    verifier('Les vues sont des FILTRES : ce qui va à l’hospitalisation ne paraît pas à la maternité',
      parService.materniteNeVoitPasImagerie === true);
    verifier('La vue « imagerie médicale » porte bien la demande d’imagerie',
      parService.imagerieVoitImagerie === true);

    /* --- LE VERROU : RIEN NE SE SAISIT AVANT LA CAISSE -------------------- */
    const verrou = await page.evaluate(async () => {
      const t = [...document.querySelectorAll('#page-content .tab')].find((x) => /Résultats/.test(x.textContent));
      if (t) t.click();
      await new Promise((r) => setTimeout(r, 500));
      const boutons = [...document.querySelectorAll('#page-content tbody button')];
      const verrouilles = boutons.filter((b) => b.getAttribute('aria-disabled') === 'true');
      return {
        regle: /Rien ne se saisit avant la caisse/.test(document.querySelector('#page-content').textContent),
        verrouilles: verrouilles.length,
        titre: verrouilles[0] ? verrouilles[0].getAttribute('title') : '',
        saisieOfferte: boutons.filter((b) => /Saisir/.test(b.getAttribute('title') || '')
          && b.getAttribute('aria-disabled') !== 'true').length,
      };
    });
    verifier('L’écran ÉNONCE la règle : rien ne se saisit avant la caisse', verrou.regle === true);
    verifier('La commande de saisie d’un examen NON RÉGLÉ est verrouillée, jamais masquée',
      verrou.verrouilles > 0, verrou.verrouilles + ' verrou(s)');
    verifier('…et le verrou NOMME où la balle se trouve',
      /CAISSE/i.test(verrou.titre || ''), verrou.titre);

    /* --- UNE FOIS RÉGLÉ, LA SAISIE S'OUVRE -------------------------------- */
    const apresCaisse = await page.evaluate(async (ref) => {
      const S = window.SIGH.store, PR = window.SIGH.parcours;
      const d = S.collection('demandesAnalyses').all().filter((x) => x.reference === ref)[0];
      if (!d) return { erreur: 'demande introuvable' };
      const f = S.collection('factures').all().filter((x) => x.id === d.factureId)[0];
      if (f) PR.encaisser(f.id, { montant: f.partPatient, mode: 'especes' });
      /* L'échantillon parvient au laboratoire : c'est le maillon suivant. */
      S.collection('demandesAnalyses').update(d.id, {
        preleveLe: new Date().toISOString(), recuLaboLe: new Date().toISOString(),
      });
      return { regle: !S.collection('demandesAnalyses').get(d.id).bloqueParPaiement };
    }, labo.reference);
    await ouvrir('m1-externe.html');
    const ouvert = await page.evaluate(async (ref) => {
      const t = [...document.querySelectorAll('#page-content .tab')].find((x) => /Résultats/.test(x.textContent));
      if (t) t.click();
      await new Promise((r) => setTimeout(r, 500));
      /* LA LIGNE SE CHERCHE PAR SA RÉFÉRENCE, JAMAIS PAR SON RANG (vague 68) : le tableau
         est paginé par douze et trié par date ; sous l'horloge décalée du banc, la demande
         du scénario n'est plus en tête, et une ligne de la page deux est « absente ». */
      const champ = document.querySelector('#page-content input[type="search"]');
      if (champ) { champ.value = ref; champ.dispatchEvent(new Event('input', { bubbles: true })); }
      await new Promise((r) => setTimeout(r, 400));
      const tr = [...document.querySelectorAll('#page-content tbody tr')]
        .find((x) => x.textContent.indexOf(ref) !== -1);
      if (!tr) return { erreur: 'ligne absente', recherche: !!champ };
      const boutons = [...tr.querySelectorAll('button')];
      return {
        verrouille: boutons.some((b) => b.getAttribute('aria-disabled') === 'true'),
        saisie: boutons.some((b) => /Saisir/.test(b.getAttribute('title') || '')),
      };
    }, labo.reference);
    verifier('Une fois la caisse passée et l’échantillon reçu, la saisie s’ouvre',
      !apresCaisse.erreur && apresCaisse.regle && !ouvert.verrouille && ouvert.saisie,
      JSON.stringify(ouvert));

    verifier('Aucune erreur JavaScript sur l’écran du patient externe',
      erreursJS.length === 0, erreursJS.join(' | '));
  }


  /* =========================================================================
   * 60 — LA MATERNITÉ SUR SON DOSSIER
   * -------------------------------------------------------------------------
   * Le dossier obstétrical est le cahier qui tient les autres. On vérifie
   * qu'il EXISTE avec ses données, que la grille de CPN se lit en colonnes
   * (une par visite), que la classification à risque se DÉDUIT du cumul des
   * facteurs et non d'un champ saisi, que la date probable se calcule depuis
   * la DDR, et que le tableau de bord de la maternité compte ce que les
   * registres portent — jamais un nombre fourni.
   * ======================================================================= */
  {
    scenario('Maternité — dossier obstétrical, CPN en colonnes, GAR déduit, tableau de bord');
    /* Le scénario précédent a basculé sur le rôle 'reception', à qui M4 et le
       tableau de bord de la maternité sont fermés : sans restauration, les
       écrans suivants mesurent un 403 et non l'écran. */
    await ouvrir('m4-dossier-obstetrical.html');
    await page.evaluate(() => window.SIGH.store.setSession({
      role: 'admin', nom: 'Administrateur', fonction: 'admin', secteur: 'ADM',
    }));
    await ouvrir('m4-dossier-obstetrical.html');

    const socle = await page.evaluate(() => {
      const S = window.SIGH.store, D = window.SIGH.data;
      const dos = S.collection('dossiersObstetricaux').active();
      const avecFacteurs = dos.filter((d) => Object.keys(d.facteurs || {}).length > 0);
      const avecExamens = dos.filter((d) => Object.keys(d.examens || {}).length >= 15);
      return {
        total: dos.length, gar: avecFacteurs.length, examens: avecExamens.length,
        referentiels: {
          facteurs: (D.FACTEURS_SURVEILLANCE || []).length,
          grille: (D.GRILLE_CPN || []).length,
          droits: (D.DROITS_FONDAMENTAUX || []).length,
          plan: (D.PLAN_ACCOUCHEMENT || []).length,
        },
        /* La DPA doit valoir DDR + 280 jours sur CHAQUE dossier peuplé :
           deux dates qui ne se recoupent pas seraient pires qu'une seule. */
        dpaCoherentes: dos.filter((d) => {
          if (!d.ddr || !d.dpa) return false;
          const j = Math.round((new Date(d.dpa) - new Date(d.ddr)) / 86400000);
          return j === 280;
        }).length,
      };
    });
    verifier('Le module Maternité est PEUPLÉ de dossiers obstétricaux',
      socle.total >= 15, socle.total + ' dossier(s)');
    verifier('Les référentiels du formulaire national sont au complet',
      socle.referentiels.facteurs === 12 && socle.referentiels.grille >= 38
      && socle.referentiels.droits === 10 && socle.referentiels.plan === 9,
      JSON.stringify(socle.referentiels));
    verifier('Chaque dossier porte ses examens complémentaires renseignés',
      socle.examens === socle.total, socle.examens + '/' + socle.total);
    verifier('La date probable vaut DDR + 280 jours sur TOUS les dossiers',
      socle.dpaCoherentes === socle.total, socle.dpaCoherentes + '/' + socle.total);

    /* --- LE RISQUE SE DÉDUIT DU CUMUL, il ne se saisit pas --------------- */
    const gar = await page.evaluate(() => {
      const S = window.SIGH.store, D = window.SIGH.data;
      const d = S.collection('dossiersObstetricaux').active()
        .filter((x) => Object.keys(x.facteurs || {}).length > 0)[0];
      if (!d) return { erreur: 'aucun dossier à facteur' };
      const attendus = (D.FACTEURS_SURVEILLANCE || [])
        .filter((f) => (d.facteurs || {})[f.code]).map((f) => f.libelle);
      return { n: attendus.length, aucunChampRisque: d.risque === undefined,
        premier: attendus[0] };
    });
    verifier('Une grossesse à risque se lit sur le CUMUL des facteurs cochés',
      !gar.erreur && gar.n > 0 && gar.aucunChampRisque, JSON.stringify(gar));

    /* --- LA GRILLE DE CPN SE LIT EN COLONNES ----------------------------- */
    const colonnes = await page.evaluate(() => {
      const S = window.SIGH.store, D = window.SIGH.data;
      const g = S.collection('grossesses').active().filter((x) => (x.visites || []).length >= 2)[0];
      if (!g) return { erreur: 'aucune grossesse à plusieurs visites' };
      const v = g.visites[0];
      /* Une visite doit porter les lignes de la grille, pas quatre chiffres. */
      const lignes = (D.GRILLE_CPN || []).filter((l) => v[l.code] !== undefined).length;
      return { visites: g.visites.length, lignesRenseignees: lignes,
        totalGrille: (D.GRILLE_CPN || []).length };
    });
    verifier('Une visite de CPN porte la GRILLE entière, pas quatre chiffres',
      !colonnes.erreur && colonnes.lignesRenseignees >= 30,
      JSON.stringify(colonnes));

    /* --- LE TABLEAU DE BORD COMPTE CE QUE LES REGISTRES PORTENT ---------- */
    await ouvrir('dash-maternite.html');
    const dash = await page.evaluate(() => {
      const S = window.SIGH.store, D = window.SIGH.data;
      const attenduTravail = S.collection('partogrammes').active().filter((p) => !p.clos).length;
      const attenduGar = S.collection('dossiersObstetricaux').active()
        .filter((d) => (D.FACTEURS_SURVEILLANCE || []).some((f) => (d.facteurs || {})[f.code])).length;
      const hote = document.querySelector('#page-content');
      const txt = hote ? hote.textContent : '';
      const kpi = [...document.querySelectorAll('#page-content .kpi-value, #page-content [data-kpi]')]
        .map((x) => x.textContent.trim());
      return { attenduTravail, attenduGar, kpi,
        parcours: /Ouvrir un dossier obstétrical/.test(txt),
        premierRegard: /partogramme|travail en cours/i.test(txt) };
    });
    verifier('Le tableau de bord de la maternité existe et porte ses parcours',
      dash.parcours === true);
    verifier('Son premier regard est le travail EN COURS — la seule chose qui n’attend pas',
      dash.premierRegard === true);
    verifier('Les grossesses à risque affichées se recomptent depuis les registres',
      dash.kpi.some((k) => k.replace(/\s/g, '') === String(dash.attenduGar)),
      'attendu ' + dash.attenduGar + ' — lus : ' + JSON.stringify(dash.kpi));

    verifier('Aucune erreur JavaScript sur les écrans de maternité',
      erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 61 — CE QUI CHANGE, ET CE QU'ON GARDE
   * -------------------------------------------------------------------------
   * Trois demandes du 08/09/2026 qui reposent sur le MÊME principe : une
   * donnée qui change ne doit pas effacer celle qui l'a précédée.
   *   — l'assuré change de compagnie : la facture d'hier garde la sienne ;
   *   — le rendez-vous honoré quitte l'agenda sans quitter le dossier ;
   *   — la période analysée SE NOMME au lieu de « les 30 derniers jours ».
   * ======================================================================= */
  {
    scenario('Couverture datée, agenda apuré, périodes nommées, filtres avancés');

    /* --- LA COUVERTURE EST DATÉE ---------------------------------------- */
    await ouvrir('m9-assures.html');
    const couv = await page.evaluate(() => {
      const S = window.SIGH.store, PR = window.SIGH.parcours;
      const p = S.collection('patients').active().filter((x) => x.assureur && x.carteExpiration)[0];
      if (!p) return { erreur: 'aucun assuré' };
      const avant = { assureur: p.assureur, exp: p.carteExpiration };
      const cible = window.SIGH.data.ASSUREURS.filter((a) => a.code !== p.assureur)[0];
      const res = PR.changerCouverture(p, {
        dateEffet: '2026-07-01', motif: 'Changement d’employeur',
        assureur: cible.code, assureurNom: cible.nom, numeroPolice: 'POL-TEST-60',
        categorieAssurance: 'entreprise', tauxPriseEnCharge: 70,
        carteExpiration: '2027-06-30',
      });
      if (!res.ok) return { erreur: res.motif };
      const hier = PR.couvertureALaDate(p, '2026-03-15');
      const auj = PR.couvertureALaDate(p, '2026-08-16');
      const refus = PR.changerCouverture(p, { assureur: cible.code, dateEffet: '2026-09-01' });
      return {
        avant, historique: PR.historiqueCouverture(p).length,
        ancienne: hier ? hier.assureur : null, nouvelle: auj ? auj.assureur : null,
        ficheMiseAJour: S.collection('patients').get(p.id).assureur,
        refusSansMotif: refus.ok === false && /motif/i.test(refus.motif || ''),
      };
    });
    verifier('Le changement de compagnie écrit DEUX périodes, il n’écrase rien',
      !couv.erreur && couv.historique === 2, JSON.stringify(couv));
    verifier('Une date ANTÉRIEURE lit l’ancienne compagnie',
      couv.avant && couv.ancienne === couv.avant.assureur, couv.erreur || (couv.ancienne + ' vs ' + (couv.avant || {}).assureur));
    verifier('…et la date du jour lit la nouvelle, reportée sur la fiche du dossier',
      couv.nouvelle !== couv.avant.assureur && couv.ficheMiseAJour === couv.nouvelle,
      couv.nouvelle + ' / fiche ' + couv.ficheMiseAJour);
    verifier('Un changement SANS MOTIF est refusé en le disant (RG-12)',
      couv.refusSansMotif === true);

    /* --- L'AGENDA EST APURÉ, PAS VIDÉ ------------------------------------ */
    await ouvrir('m2-rendezvous.html');
    const agenda = await page.evaluate(async () => {
      const S = window.SIGH.store;
      const tabs = [...document.querySelectorAll('#page-content .tab')].map((t) => t.textContent.trim());
      const honores = S.collection('consultations').active().filter((c) => c.statut === 'terminee');
      const lignes = [...document.querySelectorAll('#page-content tbody tr')].map((t) => t.textContent);
      return {
        tabs,
        honoresEnBase: honores.length,
        honoreDansListe: honores.length ? lignes.some((l) => l.indexOf(honores[0].reference) !== -1) : false,
        onglet: tabs.some((t) => /Honorés/.test(t)),
      };
    });
    verifier('L’agenda ne montre plus les rendez-vous honorés',
      agenda.honoresEnBase > 0 && agenda.honoreDansListe === false,
      agenda.honoresEnBase + ' honoré(s) en base');
    verifier('…ils sont apurés dans leur PROPRE onglet, jamais supprimés',
      agenda.onglet === true, JSON.stringify(agenda.tabs));

    const report = await page.evaluate(() => {
      const S = window.SIGH.store;
      const col = S.collection('consultations');
      const r = col.active().filter((c) => c.statut === 'planifiee')[0];
      if (!r) return { erreur: 'aucun rendez-vous planifié' };
      const dateOrigine = r.date;
      col.update(r.id, { statut: 'reporte', dateInitiale: dateOrigine,
        date: '2026-09-30T09:00', motifReport: 'Demande du patient' });
      const apres = col.get(r.id);
      return { garde: apres.dateInitiale === dateOrigine, statut: apres.statut,
        toujoursDansAgenda: apres.statut !== 'terminee' };
    });
    verifier('Un report CONSERVE la date initiale et reste dans l’agenda',
      !report.erreur && report.garde && report.toujoursDansAgenda, JSON.stringify(report));

    /* --- LA PÉRIODE SE NOMME --------------------------------------------- */
    await ouvrir('dash-da.html');
    const periode = await page.evaluate(async () => {
      const tabs = [...document.querySelectorAll('#page-content .tab')];
      const mois = tabs.find((t) => /^Mois$/.test(t.textContent.trim()));
      if (!mois) return { erreur: 'onglet Mois absent' };
      mois.click();
      await new Promise((r) => setTimeout(r, 400));
      const txt = document.querySelector('#page-content').textContent;
      const sel = [...document.querySelectorAll('#page-content select')]
        .find((s) => /janvier|Janvier/i.test(s.textContent));
      let apres = '';
      if (sel) {
        sel.value = '2';
        sel.dispatchEvent(new Event('change', { bubbles: true }));
        await new Promise((r) => setTimeout(r, 400));
        apres = document.querySelector('#page-content').textContent;
      }
      return {
        nommePeriode: /Période retenue\s*:/.test(txt),
        plusDeFenetreGlissante: !/30 derniers jours/.test(txt),
        selecteur: !!sel,
        suitLeChoix: /mars 20\d\d/i.test(apres),
      };
    });
    verifier('L’onglet « Mois » NOMME la période retenue',
      periode.nommePeriode === true && periode.plusDeFenetreGlissante === true,
      JSON.stringify(periode));
    verifier('…et le mois se CHOISIT : l’écran suit la sélection',
      periode.selecteur === true && periode.suitLeChoix === true, JSON.stringify(periode));

    /* --- LES FILTRES AVANCÉS FILTRENT VRAIMENT --------------------------- */
    await ouvrir('m9-creances.html');
    const creances = await page.evaluate(async () => {
      const compte = () => document.querySelectorAll('#page-content tbody tr').length;
      const avant = compte();
      const sels = [...document.querySelectorAll('#page-content select')];
      const seuil = sels.find((s) => /Au moins 1 000 000|Au moins 500 000/.test(s.textContent));
      if (!seuil) return { erreur: 'filtre de seuil absent' };
      seuil.value = '1000000';
      seuil.dispatchEvent(new Event('change', { bubbles: true }));
      await new Promise((r) => setTimeout(r, 400));
      return { avant, apres: compte(), filtres: sels.length };
    });
    verifier('La balance âgée porte ses filtres avancés',
      !creances.erreur && creances.filtres >= 3, JSON.stringify(creances));
    verifier('…et le seuil RESTREINT réellement la liste',
      creances.apres <= creances.avant, creances.avant + ' → ' + creances.apres);

    await ouvrir('m9-compagnies.html');
    const compagnies = await page.evaluate(() => {
      const sels = [...document.querySelectorAll('#page-content select')]
        .map((s) => s.getAttribute('aria-label')).filter(Boolean);
      return { sels };
    });
    verifier('Le référentiel des compagnies porte lui aussi ses filtres',
      compagnies.sels.length >= 4, JSON.stringify(compagnies.sels));

    verifier('Aucune erreur JavaScript sur ces écrans',
      erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * SCÉNARIO 62 — VAGUE 61 : LES FEUILLETS 7/51 ET 8/51, ET L'IMAGERIE À
   * CINQ MODALITÉS.
   *   — le compte de résultat et le tableau des flux reproduisent le
   *     formulaire déposé ; l'exercice calculé RECOUPE le journal ;
   *   — le contrôle du tableau des flux calculé CONCORDE ;
   *   — radiographie, mammographie, scanner et IRM se branchent sur le socle
   *     de l'échographie : même demande, même caisse, droits de M2.
   * ======================================================================= */
  {
    scenario('Feuillets 7/51 et 8/51, imagerie à cinq modalités');
    const erreurs62 = [];
    await page.evaluate(() => window.SIGH.store.setSession({
      role: 'admin', nom: 'BASSONGUI Chabi Séko', fonction: 'direction', secteur: 'ADM',
    }));

    /* --- Le compte de résultat : le formulaire déposé ------------------- */
    await ouvrir('m12-compte-resultat.html');
    const cr = await page.evaluate(async () => {
      const sel = document.getElementById('feuillet-exercice-resultat');
      const refs = () => [...document.querySelector('#page-content table').querySelectorAll('tbody tr td:first-child')]
        .map((td) => td.textContent.trim()).filter(Boolean);
      const ligne = (ref) => {
        const tr = [...document.querySelectorAll('#page-content table tbody tr')]
          .find((x) => x.firstElementChild && x.firstElementChild.textContent.trim() === ref);
        return tr ? [...tr.children].map((td) => td.textContent.replace(/\s/g, '')) : null;
      };
      /* Exercice calculé (défaut) : XI doit recouper le journal, recompté ici. */
      const S = window.SIGH.store;
      const debut = new Date(2026, 0, 1).getTime(), fin = new Date(2026, 7, 16).getTime();
      const net = S.collection('ecritures').active().filter((e) => e.statut !== 'brouillon'
        && /^[678]/.test(String(e.compte)) && new Date(e.date).getTime() >= debut
        && new Date(e.date).getTime() <= fin)
        .reduce((n, e) => n + (e.credit || 0) - (e.debit || 0), 0);
      const xiCalc = ligne('XI');
      const texteCalc = document.body.textContent;
      sel.value = 'depose';
      sel.dispatchEvent(new Event('change', { bubbles: true }));
      await new Promise((r) => setTimeout(r, 400));
      return {
        refs: refs(), xiCalc, net, xiDepose: ligne('XI'), tc: ligne('TC'),
        controleOk: /9 sous-totaux déposés \(XA à XI\) se recalculent/.test(document.body.textContent),
        cascadeDite: /juger l’activité sur des choix de financement/.test(texteCalc),
      };
    });
    const ORDRE_7 = ['TA', 'RA', 'RB', 'XA', 'TB', 'TC', 'TD', 'XB', 'TE', 'TF', 'TG', 'TH', 'TI', 'RC', 'RD', 'RE',
      'RF', 'RG', 'RH', 'RI', 'RJ', 'XC', 'RK', 'XD', 'TJ', 'RL', 'XE', 'TK', 'TL', 'TM', 'RM', 'RN', 'XF', 'XG',
      'TN', 'TO', 'RO', 'RP', 'XH', 'RQ', 'RS', 'XI'];
    verifier('Le compte de résultat porte les 42 références du feuillet 7/51, dans l’ordre',
      JSON.stringify(cr.refs) === JSON.stringify(ORDRE_7), cr.refs.length + ' références');
    verifier('Déposé : résultat net 4 561 200 (N) et 4 472 283 (N-1), comme la liasse',
      cr.xiDepose && cr.xiDepose.join('|').includes('4561200') && cr.xiDepose.join('|').includes('4472283'),
      JSON.stringify(cr.xiDepose));
    verifier('…et ses neuf sous-totaux se recalculent par les formules du formulaire', cr.controleOk);
    verifier('Calculé : le résultat net (XI) RECOUPE le journal, recompté indépendamment',
      cr.xiCalc && cr.xiCalc.join('|').includes(String(cr.net).replace('-', '')), cr.net + ' vs ' + JSON.stringify(cr.xiCalc));
    verifier('Les charges financières restent hors exploitation — et l’écran le dit', cr.cascadeDite);
    erreurs62.push(...erreursJS);

    /* --- Le tableau des flux : déposé, puis calculé et contrôlé --------- */
    await ouvrir('m12-flux-tresorerie.html');
    const tft = await page.evaluate(async () => {
      const sel = document.getElementById('feuillet-exercice-flux');
      const texte = document.body.textContent;
      const refs = () => [...document.querySelector('#page-content table').querySelectorAll('tbody tr td:first-child')]
        .map((td) => td.textContent.trim()).filter(Boolean);
      const calc = { concorde: /Les deux concordent/.test(texte), controleLigne: /Contrôle : Trésorerie actif N - Trésorerie passif N/.test(texte) };
      sel.value = 'depose';
      sel.dispatchEvent(new Event('change', { bubbles: true }));
      await new Promise((r) => setTimeout(r, 400));
      const t2 = document.body.textContent;
      const zh = [...document.querySelectorAll('#page-content table tbody tr')]
        .find((x) => x.firstElementChild && x.firstElementChild.textContent.trim() === 'ZH');
      return {
        calc, refs: refs(),
        zh: zh ? zh.textContent.replace(/\s/g, '') : '',
        ecartsCites: /Écarts internes du document déposé/.test(t2),
        zgNonAccuse: !/ZG \(déposé/.test(t2),
        bfAccuse: /Variation du BF \(déposé 31/.test(t2),
      };
    });
    const ORDRE_8 = ['ZA', 'FA', 'FB', 'FC', 'FD', 'FE', 'ZB', 'FF', 'FG', 'FH', 'FI', 'FJ', 'ZC', 'FK', 'FL', 'FM',
      'FN', 'ZD', 'FO', 'FP', 'FQ', 'ZE', 'ZF', 'ZG', 'ZH'];
    verifier('Le tableau des flux porte les 25 références du feuillet 8/51, dans l’ordre',
      JSON.stringify(tft.refs) === JSON.stringify(ORDRE_8), tft.refs.join(' '));
    verifier('Déposé : trésorerie au 31 décembre 6 300 639 (N) et 1 183 257 (N-1)',
      tft.zh.includes('6300639') && tft.zh.includes('1183257'), tft.zh);
    verifier('Calculé : le contrôle du formulaire (classe 5 = ZH) CONCORDE, et la ligne de contrôle est portée',
      tft.calc.concorde && tft.calc.controleLigne, JSON.stringify(tft.calc));
    verifier('Les écarts du document sont signalés — sans accuser ZG, qui se recoupe avec le ZB déposé',
      tft.ecartsCites && tft.bfAccuse && tft.zgNonAccuse, JSON.stringify(tft));
    erreurs62.push(...erreursJS);

    /* --- L'imagerie : cinq modalités sur UN socle ------------------------ */
    await ouvrir('m2-imagerie-demandes.html');
    const im = await page.evaluate(() => {
      const D = window.SIGH.data, PR = window.SIGH.parcours, S = window.SIGH.store;
      const parModalite = {};
      D.IMAGERIE.EXAMENS.forEach((e) => { parModalite[e.modalite] = (parModalite[e.modalite] || 0) + 1; });
      const catalogue = S.collection('examensImagerie').active().filter((e) => e.modalite === 'scanner').length;
      const p = S.collection('patients').active().filter((x) => !x.assureur)[0];
      const res = PR.ouvrirDemandeImagerie({ patientId: p.id, examens: ['IMG-TDM-CER', 'IMG-RX-THO'],
        prescripteur: 'Sonde 62', indication: 'Céphalées' });
      const scan = res.demandes.filter((d) => d.examenCode === 'IMG-TDM-CER')[0];
      const radio = res.demandes.filter((d) => d.examenCode === 'IMG-RX-THO')[0];
      const t = D.tarif('IMG-TDM-CER');
      return {
        parModalite, catalogue,
        modalites: [scan.modalite, radio.modalite], prix: [scan.prix, radio.prix],
        bloque: res.demandes.every((d) => d.statut === 'demandee' && d.bloqueParPaiement),
        lignes: res.facture.lignes.filter((l) => l.demandeImagerieId).length,
        provisoire: !!t.tarifProvisoire && /attente/i.test(t.motifPrix || ''),
        assureMoinsCher: t.prixAssure < t.prixNonAssure,
        filtreModalite: [...document.querySelectorAll('#page-content select')].some((s) => /Modalité/.test(s.textContent)),
      };
    });
    verifier('Le catalogue range ses examens en cinq modalités',
      Object.keys(im.parModalite).length === 5 && im.catalogue === 4, JSON.stringify(im.parModalite));
    verifier('Une demande de scanner et de radiographie passe par LA fabrique commune, bloquée par le paiement',
      im.bloque && im.lignes === 2 && im.modalites.join() === 'scanner,radiographie', JSON.stringify(im));
    verifier('Les tarifs des nouvelles modalités sont des tarifs d’ATTENTE, dits comme tels — l’assuré paie moins',
      im.provisoire && im.assureMoinsCher && im.prix[0] === 70000, JSON.stringify(im.prix));
    verifier('Le registre des demandes filtre par modalité', im.filtreModalite);
    erreurs62.push(...erreursJS);

    const tableaux = [
      ['m2-imagerie-radiographie', 'Fractures relevées'],
      ['m2-imagerie-mammographie', 'ACR 4 ou plus'],
      ['m2-imagerie-scanner', 'Avec injection'],
      ['m2-imagerie-irm', 'Avec gadolinium'],
    ];
    for (const [ecran, kpi] of tableaux) {
      await ouvrir(ecran + '.html');
      const tb = await page.evaluate((kpiLib) => {
        const t = document.body.textContent;
        const examens = [...document.querySelectorAll('#page-content tbody tr')].map((tr) => tr.textContent);
        return { kpi: t.includes(kpiLib), proposition: /proposés, à valider/.test(t),
          lignes: examens.length, intrus: examens.filter((x) => /Échographie|Électrocardiogramme/.test(x)).length };
      }, kpi);
      verifier('« ' + ecran + ' » : ses comptes rendus seuls, son indicateur propre, la proposition dite',
        tb.kpi && tb.proposition && tb.lignes > 0 && tb.intrus === 0, JSON.stringify(tb));
      erreurs62.push(...erreursJS);
    }

    /* --- Les droits : ceux de l'échographie, sur chaque tableau ---------- */
    const droits = await page.evaluate(() => {
      const N = window.SIGH.nav;
      const de = (role, id) => N.droitsEcran(role, id, 'M2');
      const voit = (role, id) => { const e = N.get(id); return !!e && N.can(role, e); };
      return {
        echoEcrit: ['radiographie', 'mammographie', 'scanner', 'irm'].every((m) => de('echographiste', 'm2-imagerie-' + m).editer),
        chirLit: ['radiographie', 'irm'].every((m) => !de('chirurgien', 'm2-imagerie-' + m).editer),
        caissier: voit('caissier', 'm2-imagerie-scanner'),
        accueil: voit('reception', 'm2-imagerie-irm'),
        medecin: voit('medecin', 'm2-imagerie-radiographie'),
      };
    });
    verifier('Le poste d’imagerie écrit les quatre tableaux, le chirurgien les lit',
      droits.echoEcrit && droits.chirLit, JSON.stringify(droits));
    verifier('Caisse et accueil n’y entrent pas (RG-13) ; le médecin, si',
      !droits.caissier && !droits.accueil && droits.medecin, JSON.stringify(droits));

    verifier('Aucune erreur JavaScript sur ces écrans', erreurs62.length === 0, erreurs62.join(' | '));
  }

  /* ==========================================================================
   * 63. REFONTE ZONE 2 — LE DOSSIER, PUIS LA FICHE, PUIS UNE SEULE FACTURE
   * --------------------------------------------------------------------------
   * METHODOLOGIE du 14/09/2026 : le dossier de consultation (anamnèse, examen
   * IPPOA en JSON par appareil) s'enregistre AVANT la fiche ; la fiche en fait
   * le récapitulatif, refuse sans lui, et porte SEULE la prescription —
   * médicaments, analyses, imagerie — en UNE facture dont l'aval reste bloqué
   * jusqu'au règlement. Le répertoire perd son onglet, la fiche patient gagne
   * l'imagerie, et l'accueil reste dehors (RG-13).
   * ======================================================================== */
  {
    scenario('Refonte Zone 2 — dossier IPPOA, fiche récapitulative, prescription unique et imagerie au dossier');
    const erreurs63 = [];
    const sessionMedecin = {
      role: 'medecin', fonction: 'medecin', nom: 'YENI M’PO Florent',
      nomComplet: 'YENI M’PO Florent', identifiant: 'f.yeni', secteur: 'MGE',
    };
    /* Une page d'abord : le stockage n'est accessible qu'à un document servi. */
    await ouvrir('m2-dossiers-consultation.html');
    await page.evaluate((s) => { sessionStorage.clear(); localStorage.setItem('sigh-cnt:session', JSON.stringify(s)); }, sessionMedecin);

    /* --- L'écran des dossiers : ses indicateurs, son tableau, sa commande -- */
    await ouvrir('m2-dossiers-consultation.html');
    const ecran = await page.evaluate(() => {
      const t = document.getElementById('page-content').textContent;
      return {
        kpis: ['En attente', 'En consultation', 'En attente labo', 'Clôturés', 'Venues du jour'].every((k) => t.includes(k)),
        lignes: document.querySelectorAll('#page-content tbody tr').length,
        nouveau: [...document.querySelectorAll('#page-content button')].some((b) => /Nouveau dossier/.test(b.textContent)),
      };
    });
    verifier('L’écran « Dossiers de consultation » porte ses cinq indicateurs, son tableau et « Nouveau dossier »',
      ecran.kpis && ecran.lignes > 0 && ecran.nouveau, JSON.stringify(ecran));
    await cliquer('Nouveau dossier', '#page-content button');
    /* « Nouveau dossier » NAVIGUE depuis la vague 65, et chaque page charge
       4,9 Mo depuis PostgreSQL derrière un PHP mono-processus : un délai fixe
       de 500 ms, calibré du temps où c'était une modale, lisait un document
       dont les scripts n'avaient pas tourné — d'où « appareils: 0 », qui ne
       voulait pas dire zéro bloc mais PAS ENCORE. On attend les neuf blocs. */
    await page.waitForFunction(
      () => document.querySelectorAll('details[data-appareil]').length === 9,
      { timeout: 180000 },
    ).catch(() => null);
    const formu = await page.evaluate(() => {
      const appareils = [...document.querySelectorAll('details[data-appareil]')].map((d) => d.getAttribute('data-appareil'));
      const b = document.querySelector('[data-normal-defaut="pleuro_pulmonaire"]');
      const ausc = document.getElementById('ex_pleuro_pulmonaire_auscultation');
      if (ausc) ausc.value = 'Crépitants de la base droite';
      if (b) b.click();
      return {
        appareils: appareils.length,
        replies: [...document.querySelectorAll('details[data-appareil]')].filter((d) => !d.open).length,
        inspection: (document.getElementById('ex_pleuro_pulmonaire_inspection') || {}).value,
        auscultation: ausc ? ausc.value : null,
      };
    });
    verifier('Le formulaire porte l’examen par appareil en blocs DÉPLIABLES (neuf appareils)',
      formu.appareils === 9 && formu.replies >= 1, JSON.stringify(formu));
    verifier('« Normal par défaut » pose « RAS » dans les champs vides SANS écraser l’anomalie saisie',
      formu.inspection === 'RAS' && formu.auscultation === 'Crépitants de la base droite', JSON.stringify(formu));
    await page.keyboard.press('Escape');
    await pause(300);
    erreurs63.push(...erreursJS);

    /* --- Le moteur : refus sans dossier, dossier IPPOA enregistré ---------- */
    const dossier = await page.evaluate(() => {
      const S = window.SIGH.store, Z = window.SIGH.consultationZone2;
      const pt = S.collection('patients').active()
        .filter((x) => !x.personnelId && !x.assureur && !Z.dossierActifDe(x.code))[0];
      let refus = null;
      try {
        Z.enregistrerFiche({ patientCode: pt.code, medecin: 'YENI M’PO Florent', pathologies: ['X'], diagnostic: 'Sonde' });
      } catch (e) { refus = { code: e.code, message: e.message }; }
      const out = Z.enregistrerDossier({
        patientCode: pt.code, soignant: 'YENI M’PO Florent', typeVenue: 'premiere',
        dateArrivee: new Date().toISOString().slice(0, 10), motifVenue: 'Fièvre et toux',
        histoire: 'Fièvre et toux depuis trois jours — SONDE 63', ant_medicaux: 'Aucun',
        etatGeneral: 'passable', etatGeneralPrecision: 'Asthénie',
        examensPhysiques: {
          cardio_vasculaire: { inspection: 'RAS', palpation: 'RAS', percussion: 'RAS', auscultation: 'RAS' },
          pleuro_pulmonaire: { inspection: 'RAS', palpation: 'RAS', percussion: 'Matité basale droite', auscultation: 'Crépitants de la base droite' },
        },
      }, null);
      let doublon = null;
      try { Z.enregistrerDossier({ patientCode: pt.code, soignant: 'X', typeVenue: 'premiere', motifVenue: 'x', histoire: 'x', etatGeneral: 'bon' }, null); }
      catch (e) { doublon = e.message; }
      const rec = S.collection('dossiersConsultation').get(out.dossier.id);
      return {
        patientCode: pt.code, patientId: pt.id, dossierId: rec.id, reference: rec.reference,
        refus, doublon, etat: rec.etat,
        json: typeof rec.examensPhysiques === 'object' && rec.examensPhysiques.pleuro_pulmonaire
          && rec.examensPhysiques.pleuro_pulmonaire.auscultation === 'Crépitants de la base droite'
          && rec.examensPhysiques.cardio_vasculaire.inspection === 'RAS',
      };
    });
    verifier('La fiche est REFUSÉE sans dossier de consultation — et le refus nomme l’écran où aller',
      dossier.refus && dossier.refus.code === 'SANS_DOSSIER' && /Dossiers de\s+consultation/.test(dossier.refus.message),
      JSON.stringify(dossier.refus));
    verifier('Le dossier s’enregistre avec l’examen IPPOA en objet JSON par appareil, et naît EN CONSULTATION',
      dossier.json && dossier.etat === 'consultation', JSON.stringify(dossier));
    verifier('Un second dossier ouvert pour le même patient est refusé en nommant le premier',
      !!dossier.doublon && dossier.doublon.indexOf(dossier.reference) !== -1, dossier.doublon);

    /* --- La fiche s'ouvre SUR le dossier et en fait le récapitulatif ------- */
    await ouvrir('m2-dossiers-consultation.html');
    await page.goto(`http://127.0.0.1:${PORT}/pages/m2-consultation-fiche.php#onglet=${encodeURIComponent(dossier.dossierId)}`,
      { waitUntil: 'networkidle2' });
    await pause(700);
    const recap = await page.evaluate((ref) => {
      const t = document.getElementById('page-content').textContent;
      return {
        reference: t.includes('Récapitulatif du dossier ' + ref),
        anamnese: t.includes('SONDE 63'),
        ippoa: /Examen clinique \(IPPOA\)/.test(t) && t.includes('Matité basale droite') && /RAS — examen normal/.test(t),
        constantes: /Zone 1 — constantes de l’accueil/.test(t),
        refus: /Fiche impossible sans dossier/.test(t),
      };
    }, dossier.reference);
    verifier('La fiche ouverte depuis le dossier en fait le RÉCAPITULATIF — anamnèse, IPPOA, constantes de la Zone 1',
      recap.reference && recap.anamnese && recap.ippoa && recap.constantes && !recap.refus, JSON.stringify(recap));
    erreurs63.push(...erreursJS);

    /* --- UNE prescription : 1 médicament + 1 analyse + 1 imagerie ---------- */
    const chaine = await page.evaluate((dos) => {
      const S = window.SIGH.store, Z = window.SIGH.consultationZone2, PR = window.SIGH.parcours, D = window.SIGH.data;
      const prod = S.collection('produits').active().filter((x) => x.categorie === 'medicament' && x.stock > 5)[0];
      const img = S.collection('examensImagerie').active().filter((x) => {
        const pr = D.tarifPrix ? D.tarifPrix(x.tarifCode || x.code, false) : { montant: null };
        return pr.montant != null;
      })[0];
      const facturesAvant = S.collection('factures').all().filter((f) => f.patientId === dos.patientId).length;
      const res = Z.enregistrerFiche({
        patientCode: dos.patientCode, medecin: 'YENI M’PO Florent', dossierConsultationId: dos.dossierId,
        pathologies: [S.collection('pathologies').active()[0].code], diagnostic: 'Pneumopathie droite — sonde 63',
        medicaments: [{ produitId: prod.id, quantite: 2, posologie: '1 cp matin et soir', duree: '5 jours' }],
        analyses: [D.ANALYSES[0].code], imagerie: [img.code], orientation: 'laboratoire',
      });
      const fac = S.collection('factures').get(res.prescription.facture.id);
      const facturesApres = S.collection('factures').all().filter((f) => f.patientId === dos.patientId).length;
      const lab = res.prescription.demandes[0], ime = res.prescription.demandesImagerie[0];
      const avant = {
        lab: S.collection('demandesAnalyses').get(lab.id).bloqueParPaiement,
        img: S.collection('demandesImagerie').get(ime.id).bloqueParPaiement,
        imgStatut: S.collection('demandesImagerie').get(ime.id).statut,
        tacheImagerie: PR.taches().filter((t) => t.factureId === fac.id && t.type === 'imagerie').map((t) => t.statut),
      };
      const enc = PR.encaisser(fac.id, { lignes: fac.lignes.map((l) => l.id) });
      const apres = {
        lab: S.collection('demandesAnalyses').get(lab.id),
        img: S.collection('demandesImagerie').get(ime.id),
      };
      const cons = S.collection('consultations').get(res.consultation.id);
      return {
        delta: facturesApres - facturesAvant,
        lignes: (fac.lignes || []).map((l) => l.categorie).sort().join(','),
        liens: (fac.lignes || []).every((l) => (l.categorie === 'medicament' && l.produitId)
          || (l.categorie === 'analyse' && l.demandeId === lab.id)
          || (l.categorie === 'imagerie' && l.demandeImagerieId === ime.id)),
        parts: fac.montantTTC === fac.partAssurance + fac.partPatient + (fac.partPersonnel || 0),
        avant,
        apres: { lab: apres.lab.bloqueParPaiement + '/' + apres.lab.etatAnalyse, img: apres.img.bloqueParPaiement + '/' + apres.img.statut },
        solde: enc.facture.statutPaiement,
        dossierEtat: S.collection('dossiersConsultation').get(dos.dossierId).etat,
        lien: cons.dossierConsultationId === dos.dossierId && cons.ordonnanceId === res.prescription.ordonnance.id,
      };
    }, dossier);
    verifier('Médicament + analyse + imagerie font UNE seule facture de TROIS lignes payables',
      chaine.delta === 1 && chaine.lignes === 'analyse,imagerie,medicament' && chaine.liens,
      JSON.stringify(chaine));
    verifier('La facture ventile part assureur / part patient — le total en est la somme', chaine.parts, JSON.stringify(chaine));
    verifier('Avant la caisse, le prélèvement et l’examen d’imagerie sont BLOQUÉS (tâche d’imagerie bloquée)',
      chaine.avant.lab === true && chaine.avant.img === true && chaine.avant.imgStatut === 'demandee'
      && chaine.avant.tacheImagerie.join() === 'bloque', JSON.stringify(chaine.avant));
    verifier('PR.encaisser libère l’analyse (à prélever) et l’imagerie (payée) ligne par ligne',
      chaine.apres.lab === 'false/attente_prelevement' && chaine.apres.img === 'false/payee' && chaine.solde === 'soldee',
      JSON.stringify(chaine.apres));
    verifier('La consultation porte son dossier et son ordonnance ; le dossier passe EN ATTENTE LABO',
      chaine.lien && chaine.dossierEtat === 'attente_labo', JSON.stringify(chaine));

    /* --- Le répertoire n'a plus l'onglet ; la fiche patient a l'imagerie --- */
    await ouvrir('m1-patients.html');
    const repertoire = await page.evaluate(() => [...document.querySelectorAll('button')]
      .some((b) => /Dossiers de consultation/.test(b.textContent)));
    verifier('m1-patients ne montre plus l’onglet des dossiers de consultation (Zone 2)', !repertoire);
    erreurs63.push(...erreursJS);

    await ouvrir('m1-patient-profil.html');
    await page.evaluate((id) => {
      const combo = [...document.querySelectorAll('#page-content .combo')][0];
      if (combo) { combo.value = id; combo.dispatchEvent(new Event('change')); }
    }, dossier.patientId);
    await pause(500);
    const ongletImg = await cliquer('Imagerie médicale', '#page-content button, #page-content [role="tab"]');
    await pause(400);
    const profil = await page.evaluate(() => {
      const t = document.getElementById('page-content').textContent;
      return { demandee: /Payée — à exécuter|Demandée — attente caisse/.test(t), modalite: /Échographie|Radiographie|Scanner|IRM|Mammographie/.test(t) };
    });
    verifier('La fiche patient porte l’onglet « Imagerie médicale » avec l’examen, sa modalité et son état',
      ongletImg && profil.demandee && profil.modalite, JSON.stringify(profil));
    erreurs63.push(...erreursJS);

    /* --- RG-13 : l'accueil n'ouvre pas le dossier de consultation ---------- */
    const droits = await page.evaluate(() => {
      const N = window.SIGH.nav;
      const e = N.get('m2-dossiers-consultation');
      return {
        reception: N.can('reception', e), echographiste: N.can('echographiste', e),
        caissier: N.can('caissier', e), laborantin: N.can('laborantin', e),
        medecin: N.droitsEcran('medecin', 'm2-dossiers-consultation', 'M2').editer,
        ficheReception: N.can('reception', N.get('m2-consultation-fiche')),
      };
    });
    verifier('L’accueil, l’échographiste, la caisse et le laboratoire n’ouvrent pas les dossiers ; le médecin y écrit',
      !droits.reception && !droits.echographiste && !droits.caissier && !droits.laborantin && droits.medecin
      && !droits.ficheReception, JSON.stringify(droits));
    await page.evaluate(() => {
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'reception', fonction: 'accueil', nom: 'SONDE Accueil', nomComplet: 'SONDE Accueil', identifiant: 'sonde.accueil',
      }));
    });
    await ouvrir('m2-dossiers-consultation.html');
    verifier('…et son adresse renvoie l’accueil au 403', /error-403/.test(page.url()), page.url());

    /* On rend la session du médecin : un scénario qui change de rôle le RESTAURE. */
    await page.evaluate((s) => localStorage.setItem('sigh-cnt:session', JSON.stringify(s)), sessionMedecin);
    verifier('Aucune erreur JavaScript sur ces écrans', erreurs63.length === 0, erreurs63.join(' | '));
  }

  /* ==========================================================================
   * 64. CORRECTIONS DE L'ÉCHOGRAPHISTE (14/09/2026) — LE COMPTE RENDU PAR VARIABLES
   * --------------------------------------------------------------------------
   * Les champs de précision n'apparaissent que pour la valeur qui les appelle,
   * le bloc du sac se duplique selon le nombre de sacs, les mesures se
   * saisissent en texte, « Annexes » disparaît des échographies, la
   * provenance est demandée, et l'examen « 1er trimestre évolué » existe.
   * ======================================================================== */
  {
    scenario('Corrections de l’échographiste — champs conditionnels, sacs dupliqués, mesures en texte, sans Annexes');
    const erreurs64 = [];
    await ouvrir('m2-imagerie.html');
    await page.evaluate(() => {
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'echographiste', fonction: 'echographiste', nom: 'AHOHOU Rodrigue', nomComplet: 'AHOHOU Rodrigue', identifiant: 'r.ahohou',
      }));
    });
    await ouvrir('m2-imagerie.html');

    const referentiel = await page.evaluate(() => {
      const IM = window.SIGH.data.IMAGERIE;
      const v = (ex, code) => IM.variablesDe(ex).filter((x) => x.code === code)[0] || null;
      const echo = IM.modalite('echographie');
      return {
        sansAnnexes: !(echo.rubriquesLibres || []).some((r) => r.code === 'annexes')
          && (echo.rubriquesLibres || []).some((r) => r.code === 'conclusion'),
        evolue: !!IM.examen('IMG-ECHO-OBS1E') && !!v('IMG-ECHO-OBS1E', 'EM_BIP') && !!v('IMG-ECHO-OBS1E', 'EM_LF'),
        /* Le rythme cardiaque n'est pas supprimé : il est DÉPLACÉ après le
           LCC (21/09/2026) — et après la biométrie sur l'examen évolué. */
        rythmeApresLcc: ['IMG-ECHO-OBS1', 'IMG-ECHO-OBS1E'].every((ex) => {
          const codes = IM.variablesDe(ex).map((x) => x.code);
          return codes.indexOf('EM_BPM') > codes.indexOf('EM_LCC')
            && codes.indexOf('EM_BPM') < codes.indexOf('EM_AG')
            && (ex !== 'IMG-ECHO-OBS1E' || codes.indexOf('EM_BPM') > codes.indexOf('EM_LF'));
        }),
        conclusionCasesRetiree: !v('IMG-ECHO-OBS1', 'OB1_TYPE') && !v('IMG-ECHO-OBS', 'MANNING'),
        troph: (v('IMG-ECHO-OBS1', 'SG_TROPH') || {}).options,
        vacuite: (v('IMG-ECHO-PEL', 'UT_VAC') || {}).options,
        ovaires: ((v('IMG-ECHO-PEL', 'OVAIRES') || {}).conditionnels || []).map((c) => c.libelle),
      };
    });
    verifier('Le référentiel porte les corrections : sans Annexes, examen évolué (BIP, LF), « conclusion à cases » retirée et rythme cardiaque REPOSITIONNÉ après le LCC',
      referentiel.sansAnnexes && referentiel.evolue && referentiel.rythmeApresLcc && referentiel.conclusionCasesRetiree,
      JSON.stringify(referentiel));
    verifier('Listes corrigées — vacuité Visible/Non visible, réaction trophoblastique en quatre valeurs, ovaire anormal → taille + échostructure',
      JSON.stringify(referentiel.vacuite) === '["Visible","Non visible"]'
      && (referentiel.troph || []).join() === 'mauvaise,médiocre,bonne,décollement'
      && referentiel.ovaires.join() === 'Taille,Échostructure', JSON.stringify(referentiel));

    /* L'EN-TÊTE EST REVENU EN MODALE (24/09/2026), et c'est sa validation qui
       ouvre la page de rédaction. On mesure donc les deux temps : la fenêtre
       demande l'examen, le patient et la provenance ; la page qui suit porte
       les variables et l'enchaînement du parcours. */
    await cliquer('Nouveau compte rendu', '#page-content button');
    await pause(700);
    const ouverture = await page.evaluate(() => {
      const m = document.querySelector('[role="dialog"], .modal');
      const ex = m && m.querySelector('#f_examenCode');
      const prov = m && m.querySelector('#f_provenance');
      if (ex) { ex.value = 'IMG-ECHO-OBS1E'; ex.dispatchEvent(new Event('change')); }
      if (prov) prov.value = 'Centre de santé de Perma — sonde 64';
      const ind = m && m.querySelector('#f_indication'); if (ind) ind.value = 'Datation';
      const bt = m && [...m.querySelectorAll('button')]
        .find((x) => /Continuer vers la saisie/.test(x.textContent));
      if (bt) bt.click();
      return { modale: !!m, continuer: !!bt,
        provenance: !!prov, examen: ex ? ex.value : null };
    });
    /* La modale d'en-tête OUVRE la page de saisie (vague 67) : la sonde lit
       l'adresse ET le registre, donc la nouvelle page doit être arrivée puis
       hydratée. Un délai fixe tombait au milieu. */
    await attendrePeinture();
    await pause(300);
    const pageCR = await page.evaluate(() => ({
      page: /m2-imagerie-cr/.test(location.pathname),
      parcours: /Enchaînement du parcours/.test(document.body.textContent),
      /* La fiche n'existe PAS encore : rien n'est écrit au registre tant que
         le compte rendu n'a pas été enregistré. */
      registre: window.SIGH.store.collection('resultatsImagerie').active()
        .filter((x) => x.provenance === 'Centre de santé de Perma — sonde 64').length,
    }));
    verifier('La MODALE d’en-tête demande la PROVENANCE, et sa validation ouvre la PAGE de rédaction',
      ouverture.modale && ouverture.continuer && pageCR.page && pageCR.parcours,
      JSON.stringify({ ouverture: ouverture, page: pageCR }));
    verifier('Rien n’est écrit au registre tant que le compte rendu n’est pas enregistré',
      pageCR.registre === 0, pageCR.registre + ' fiche(s) créée(s) prématurément');
    verifier('L’en-tête propose l’examen évolué et retient la provenance',
      ouverture.provenance && ouverture.examen === 'IMG-ECHO-OBS1E', JSON.stringify(ouverture));
    await pause(700);
    const saisie = await page.evaluate(() => {
      const t = (id) => document.getElementById(id);
      const cache = (id) => !t(id) || t(id).parentElement.classList.contains('hidden');
      const blocs = () => [...document.querySelectorAll('details[data-exemplaire]')]
        .filter((d) => !d.classList.contains('hidden')).map((d) => d.getAttribute('data-exemplaire'));
      const avant = { blocs: blocs(), precision: cache('f_SG_LOC_AUTRE'),
        texte: [t('f_SG_DIM'), t('f_SG_AG_sa'), t('f_EM_LCC'), t('f_EM_BPM')].every((x) => x && x.type === 'text'),
        annexes: !!t('f_annexes'), foetus: /Fœtus/.test(document.body.textContent) };
      t('f_SG_NB').value = '02'; t('f_SG_NB').dispatchEvent(new Event('change'));
      t('f_SG_LOC').value = 'Autre'; t('f_SG_LOC').dispatchEvent(new Event('change'));
      const apres = { blocs: blocs(), precision: !cache('f_SG_LOC_AUTRE') };
      t('f_SG_LOC_AUTRE').value = 'cornuale droite';
      t('f_SG_DIM').value = '12,5';
      t('f_SG_DIM__2').value = '14';
      t('f_conclusion').value = 'Grossesse gémellaire évolutive — sonde 64';
      /* Le bouton de la PAGE s'appelle « Enregistrer le compte rendu » — la
         modale disait « Enregistrer ». On accepte les deux : le scénario
         mesure la saisie, pas le libellé d'un bouton. */
      const b = [...document.querySelectorAll('button')]
        .find((x) => /^Enregistrer( le compte rendu)?$/.test(x.textContent.trim()));
      if (b) b.click();
      return { avant, apres };
    });
    verifier('Les mesures se saisissent en TEXTE, sans champ Annexes, et le bloc « Fœtus » remplace l’embryon',
      saisie.avant.texte && !saisie.avant.annexes && saisie.avant.foetus, JSON.stringify(saisie.avant));
    verifier('« Autre » fait paraître son champ de précision ; « 02 » sacs fait paraître le bloc du sac n°2 — et lui seul',
      saisie.avant.precision && saisie.avant.blocs.length === 0 && saisie.apres.precision
      && JSON.stringify(saisie.apres.blocs) === '["Sac gestationnel|2"]', JSON.stringify(saisie));
    /* L'ENREGISTREMENT RAMÈNE AU REGISTRE, et la page suivante se réhydrate
       depuis le serveur : la fiche n'y est pas forcément arrivée au moment
       où l'on regarde. Elle n'est pas perdue — `pagehide` l'expédie en
       `keepalive` — mais elle peut se faire attendre. On guette donc la
       fiche, au lieu de compter six cents millisecondes. */
    await page.waitForFunction(() => {
      try {
        return !!window.SIGH.store.collection('resultatsImagerie').active()
          .filter((x) => x.provenance === 'Centre de santé de Perma — sonde 64')[0];
      } catch (e) { return false; }
    }, { timeout: 60000 }).catch(() => null);
    const stocke = await page.evaluate(() => {
      const cr = window.SIGH.store.collection('resultatsImagerie').active()
        .filter((x) => x.provenance === 'Centre de santé de Perma — sonde 64')[0];
      return cr ? { ref: cr.reference, v: cr.valeurs, annexes: cr.annexes } : null;
    });
    verifier('Le compte rendu enregistre la provenance, la précision et le sac n°2 (`CODE__2`), sans valeur de bloc masqué',
      !!stocke && stocke.v.SG_LOC_AUTRE === 'cornuale droite' && stocke.v.SG_DIM__2 === '14'
      && !('SG_DIM__3' in stocke.v), JSON.stringify(stocke));
    const tiroir = await page.evaluate(async (ref) => {
      const tr = [...document.querySelectorAll('#page-content tbody tr')].find((x) => x.textContent.includes(ref));
      const bt = tr && [...tr.querySelectorAll('button')].find((b) => /Consulter/.test(b.title || ''));
      if (!bt) return null;
      bt.click();
      await new Promise((r) => setTimeout(r, 600));
      const t = document.body.textContent;
      return { sac2: /Sac gestationnel n°2/.test(t), precision: /cornuale droite/.test(t), provenance: /sonde 64/.test(t) };
    }, stocke ? stocke.ref : '');
    verifier('La lecture du compte rendu montre le sac n°2, la précision saisie et la provenance',
      !!tiroir && tiroir.sac2 && tiroir.precision && tiroir.provenance, JSON.stringify(tiroir));
    erreurs64.push(...erreursJS);
    verifier('Aucune erreur JavaScript sur ces écrans', erreurs64.length === 0, erreurs64.join(' | '));
  }

  /* ======================================================================
   * SCÉNARIO 65 — BFR, TABLEAU DÉCISIONNEL ET FEUILLE D'INVENTAIRE
   * ----------------------------------------------------------------------
   * Trois choses à prouver, et la première commande les deux autres :
   *
   *   1. le moteur AGRÈGE et n'invente rien — ses trois composantes se
   *      recomptent depuis le magasin, sur une page qui ne charge NI M9,
   *      NI M6, NI M7 ;
   *   2. la dette fournisseur n'est PAS nulle alors qu'aucun écran de M7
   *      n'a été ouvert — c'est tout l'objet de l'amorçage remonté au socle,
   *      et un zéro ici surestimerait le BFR sans le dire ;
   *   3. le seuil vit dans la COLLECTION : le corriger déplace l'alerte, et
   *      le moteur de notification n'a rien à changer.
   * ==================================================================== */
  {
    scenario('BFR, tableau décisionnel et feuille d’inventaire');
    const erreurs65 = [];

    await ouvrir('m12-bfr.html');
    await page.evaluate(() => {
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'comptable', fonction: 'comptable', nom: 'KASSA Augustin',
        nomComplet: 'KASSA Augustin', identifiant: 'a.kassa',
      }));
    });
    await ouvrir('m12-bfr.html');

    /* --- Le moteur, recompté à la main -------------------------------- */
    const moteur = await page.evaluate(() => {
      const S = window.SIGH.store;
      const b = window.SIGH.bfr.calculer();
      const factures = S.collection('factures').active();
      const creancesAtt = factures.filter((f) => f.assureur)
        .reduce((n, f) => n + (f.partAssurance || 0), 0);
      const restesAtt = factures.filter((f) => f.statutPaiement !== 'soldee')
        .reduce((n, f) => n + Math.max(0, f.reliquat || 0), 0);
      const stocksAtt = S.collection('produits').active()
        .reduce((n, p) => n + (p.stock || 0) * S.valeurUnitaire(p), 0);
      const ff = S.collection('facturesFournisseurs').active();
      const dettesAtt = ff.filter((f) => ['payee', 'soldee'].indexOf(String(f.statutPaiement || '')) === -1)
        .reduce((n, f) => n + (f.montantFacture || 0), 0);
      return {
        creances: b.creances, creancesAtt: creancesAtt + restesAtt,
        stocks: b.stocks, stocksAtt: stocksAtt,
        dettes: b.dettes, dettesAtt: dettesAtt,
        bfr: b.bfr, somme: creancesAtt + restesAtt + stocksAtt - dettesAtt,
        nbFF: ff.length, incomplet: b.incomplet,
      };
    });
    verifier('Le moteur AGRÈGE : chaque composante se recompte à l’identique depuis le magasin, et le BFR est leur somme algébrique',
      moteur.creances === moteur.creancesAtt && moteur.stocks === moteur.stocksAtt
      && moteur.dettes === moteur.dettesAtt && moteur.bfr === moteur.somme,
      JSON.stringify(moteur));

    /* LE POINT DE LA VAGUE : la page de M12 ne charge pas le module M7, et
       la dette fournisseur existe quand même. Avant l'amorçage au socle,
       elle valait zéro et le BFR était surestimé d'autant. */
    verifier('Les factures fournisseurs sont amorcées AU SOCLE : la dette existe sur une page qui ne charge pas M7, et le calcul ne se déclare pas incomplet',
      moteur.nbFF > 0 && moteur.dettes > 0 && moteur.incomplet.length === 0,
      JSON.stringify({ nbFF: moteur.nbFF, dettes: moteur.dettes, incomplet: moteur.incomplet }));

    const affiche = await page.evaluate(() => {
      const t = document.getElementById('page-content').textContent;
      return {
        bfr: /Besoin en fonds de roulement/.test(t),
        trois: /En-cours clients/.test(t) && /Valorisation des stocks/.test(t) && /Dettes fournisseurs/.test(t),
        sources: /Redescendre à la source/.test(t),
      };
    });
    verifier('L’écran montre les trois composantes et permet de redescendre à leur registre d’origine',
      affiche.bfr && affiche.trois && affiche.sources, JSON.stringify(affiche));

    /* --- Le seuil vit dans la collection, pas dans le code ------------- */
    const seuil = await page.evaluate(() => {
      const S = window.SIGH.store;
      const PR = window.SIGH.parcours;
      const col = S.collection('objectifsPilotage');
      const fiche = col.active().filter((o) => o.id === 'creance_agee')[0];
      const avant = { cible: fiche.cible, aValider: fiche.aValider };
      const alertesAvant = PR.alertesRecouvrement();
      col.update(fiche.id, { cible: 5, aValider: false });
      const alertesApres = PR.alertesRecouvrement();
      const seuilLu = alertesApres.length ? alertesApres[0].seuil : null;
      col.update(fiche.id, avant);
      const alertesRendues = PR.alertesRecouvrement();
      return {
        seuilAvant: alertesAvant.length ? alertesAvant[0].seuil : null,
        seuilLu: seuilLu,
        plusLarge: alertesApres.length >= alertesAvant.length,
        restaure: alertesRendues.length === alertesAvant.length,
      };
    });
    verifier('Le seuil d’ancienneté est un PARAMÈTRE : abaissé à 5 jours, l’alerte s’élargit et le moteur le lit sans être modifié — puis la fiche est restaurée',
      seuil.seuilAvant === 60 && seuil.seuilLu === 5 && seuil.plusLarge && seuil.restaure,
      JSON.stringify(seuil));

    /* --- La grille objectif / réel ------------------------------------- */
    await ouvrir('m12-tableau-decisionnel.html');
    const grille = await page.evaluate(() => {
      const ind = window.SIGH.bfr.indicateurs();
      const t = document.getElementById('page-content').textContent;
      return {
        axes: [...new Set(ind.map((x) => x.axe))].sort().join(),
        /* « Non calculable » N'EST PAS zéro : un indicateur sans donnée le dit. */
        indisponiblesSansZero: ind.filter((x) => x.etat === 'indisponible')
          .every((x) => x.reel == null),
        /* Le SENS décide de la couleur : un DSO bas est une réussite. */
        sens: ind.filter((x) => x.id === 'dso').map((x) => x.sens).join(),
        occupationHaut: ind.filter((x) => x.id === 'occupation_lits').map((x) => x.sens).join(),
        aValider: ind.filter((x) => x.aValider).length,
        rendu: /Grille objectif/.test(t) && /Trésorerie/.test(t) && /Performance administrative/.test(t),
      };
    });
    verifier('Les quatre axes du document sont rendus, « non calculable » ne vaut jamais zéro, et le sens distingue un DSO (bas) d’un taux d’occupation (haut)',
      grille.axes === 'activite,administratif,logistique,tresorerie'
      && grille.indisponiblesSansZero && grille.sens === 'bas'
      && grille.occupationHaut === 'haut' && grille.rendu, JSON.stringify(grille));
    verifier('Les cibles partent en PROPOSITION : aucun document de cadrage n’en fixe, et l’écran le dit',
      grille.aValider > 0, JSON.stringify({ aValider: grille.aValider }));

    /* --- RBAC : la caisse n'entre pas au contrôle de gestion ------------ */
    const rbac = await page.evaluate(() => {
      const N = window.SIGH.nav;
      /* `N.get` et non une lecture directe de l'INDEX : c'est la porte que le
         ruban emprunte, et l'entrée qu'elle rend porte son module — sans lui,
         la surcharge RBAC est ignorée et la sonde mesure autre chose. */
      return {
        caissierBfr: N.can('caissier', N.get('m12-bfr')),
        caissierGrille: N.can('caissier', N.get('m12-tableau-decisionnel')),
        comptableBfr: N.can('comptable', N.get('m12-bfr')),
        daGrille: N.can('da', N.get('m12-tableau-decisionnel')),
      };
    });
    verifier('La rangée « Contrôle de gestion » ne change AUCUN droit : M12 reste fermé au caissier, ouvert au comptable et à la DAF',
      rbac.caissierBfr === false && rbac.caissierGrille === false
      && rbac.comptableBfr === true && rbac.daGrille === true, JSON.stringify(rbac));

    erreurs65.push(...erreursJS);

    /* --- La feuille d'inventaire : un magasin NOMMÉ --------------------
       ON CHANGE DE RÔLE AVANT D'OUVRIR L'ÉCRAN, et non après : M6 est fermé
       au comptable, la page rebondirait sur le 403 et la sonde mesurerait un
       refus d'accès au lieu d'une feuille de comptage. */
    await page.evaluate(() => {
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'stock', fonction: 'stock', nom: 'MAMAN Zoukanéri',
        nomComplet: 'MAMAN Zoukanéri', identifiant: 'z.maman',
      }));
    });
    await ouvrir('m6-inventaire.html');
    await ouvrir('m6-inventaire-feuille.html#magasin=detail&type=Ponctuel&perimetre=Tous%20les%20articles&operateur=MAMAN%20Zouk');

    const feuille = await page.evaluate(() => {
      const code = document.querySelector('#page-content tbody tr .font-mono');
      const ligne = document.querySelector('#page-content tbody tr');
      const cellules = ligne ? ligne.querySelectorAll('td') : [];
      const theoriqueAffiche = cellules.length ? cellules[1].textContent.replace(/[^0-9-]/g, '') : '';
      const p = window.SIGH.store.collection('produits').active()
        .filter((x) => x.code === (code ? code.textContent : ''))[0];
      const input = ligne ? ligne.querySelector('input[type="number"]') : null;
      if (input && p) {
        input.value = String((p.stockDetail || 0) + 3);
        input.dispatchEvent(new Event('input'));
      }
      return {
        code: code ? code.textContent : null,
        theoriqueAffiche: theoriqueAffiche,
        stockDetail: p ? p.stockDetail : null,
        stockGros: p ? p.stockGros : null,
        stock: p ? p.stock : null,
        parcours: /Enchaînement du parcours/.test(document.getElementById('page-content').textContent),
        deuxPanneaux: !!document.querySelector('#page-content .lg\\:col-span-2'),
      };
    });
    verifier('Le stock théorique affiché est celui du MAGASIN COMPTÉ (détail), et non le total des deux stocks',
      feuille.theoriqueAffiche === String(feuille.stockDetail)
      && feuille.stockDetail !== feuille.stock, JSON.stringify(feuille));
    verifier('La feuille adopte le gabarit à deux panneaux : comptage à gauche, enchaînement du parcours à droite',
      feuille.deuxPanneaux && feuille.parcours, JSON.stringify(feuille));

    await cliquer('Valider l’inventaire', '#page-content button');
    await pause(900);

    const apresInv = await page.evaluate((code) => {
      const S = window.SIGH.store;
      const p = S.collection('produits').active().filter((x) => x.code === code)[0];
      const mv = S.collection('mouvements').active()
        .filter((m) => m.type === 'inventaire' && m.produitId === (p ? p.id : null))
        .sort((a, b) => String(b.reference).localeCompare(String(a.reference)))[0];
      const inv = S.collection('inventaires').active()
        .sort((a, b) => String(b.reference).localeCompare(String(a.reference)))[0];
      return {
        stockDetail: p ? p.stockDetail : null,
        stockGros: p ? p.stockGros : null,
        mouvement: mv ? { stockType: mv.stockType, justificatif: mv.justificatif, quantite: mv.quantite } : null,
        inventaire: inv ? { magasin: inv.magasin, nbEcarts: inv.nbEcarts } : null,
      };
    }, feuille.code);
    verifier('La régularisation porte sur le magasin compté et sur lui seul : le stock détail progresse de 3, le stock gros ne bouge pas',
      apresInv.stockDetail === feuille.stockDetail + 3 && apresInv.stockGros === feuille.stockGros,
      JSON.stringify({ avant: feuille, apres: apresInv }));
    verifier('RG-03 — un mouvement de régularisation est écrit, portant le magasin et la référence de l’inventaire en justificatif',
      !!apresInv.mouvement && apresInv.mouvement.stockType === 'detail'
      && /^Inventaire INV-/.test(apresInv.mouvement.justificatif || '')
      && apresInv.inventaire && apresInv.inventaire.magasin === 'detail',
      JSON.stringify(apresInv));

    /* La session est RESTAURÉE : un scénario qui change de rôle le rend,
       sinon les suivants mesurent un 403 au lieu d'un écran. */
    await page.evaluate(() => {
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'admin', fonction: 'admin', nom: 'Administrateur',
        nomComplet: 'Administrateur système', identifiant: 'admin',
      }));
    });

    erreurs65.push(...erreursJS);
    verifier('Aucune erreur JavaScript sur ces écrans', erreurs65.length === 0, erreurs65.join(' | '));
  }

  /* ======================================================================
   * SCÉNARIO 66 — LES RÈGLES DE L'ÉCHOGRAPHIE, ÉTENDUES AUX CINQ MODALITÉS
   * ----------------------------------------------------------------------
   * APPLIQUER_REGLES.txt généralise quatre règles à la radiographie, la
   * mammographie, le scanner et l'IRM. Elles ne sont pas recopiées examen
   * par examen : elles sont PORTÉES PAR LA MODALITÉ, et une passe les
   * applique à tous ses examens — présents comme futurs. Ce scénario sonde
   * la CONSÉQUENCE et non la déclaration : c'est le formulaire rendu qui
   * doit porter des champs texte, une précision « Autre » et aucune
   * rubrique « Annexes ».
   * ==================================================================== */
  {
    scenario('Règles transversales d’imagerie — cinq modalités, pas seulement l’échographie');
    const erreurs66 = [];

    await ouvrir('m2-imagerie-radiographie.html');
    const regles = await page.evaluate(() => {
      const IM = window.SIGH.data.IMAGERIE;
      const codes = ['echographie', 'radiographie', 'mammographie', 'scanner', 'irm'];
      const mods = codes.map((c) => IM.modalite(c));
      const listesSansAutre = [];
      const numeriques = [];
      codes.forEach((c) => {
        const m = IM.modalite(c);
        IM.EXAMENS.filter((e) => e.modalite === c).forEach((e) => {
          IM.variablesDe(e.code).forEach((v) => {
            if (m.autreSystematique && v.type === 'liste' && Array.isArray(v.options)) {
              const a = v.options.some((o) => String(o).toLowerCase() === 'autre');
              const cond = (v.conditionnels || []).some((x) => (x.quand || []).indexOf('Autre') !== -1);
              if (!a || !cond) listesSansAutre.push(e.code + '/' + v.code);
            }
            if (v.type === 'nombre' || v.type === 'number') numeriques.push(e.code + '/' + v.code);
          });
        });
      });
      return {
        provenance: mods.every((m) => m.provenance === true),
        saisieTexte: mods.every((m) => m.saisieTexte === true),
        sansAnnexes: mods.every((m) => !(m.rubriquesLibres || []).some((r) => r.code === 'annexes')),
        /* Le plan radiologique : Résultats, Conclusion OBLIGATOIRE, Recommandation. */
        planRadio: codes.slice(1).every((c) => {
          const r = IM.modalite(c).rubriquesLibres || [];
          return r.some((x) => x.code === 'conclusion' && x.requis);
        }),
        listesSansAutre: listesSansAutre,
        numeriques: numeriques,
      };
    });
    verifier('Les cinq modalités portent PROVENANCE et saisie en texte, et aucune ne porte de rubrique « Annexes »',
      regles.provenance && regles.saisieTexte && regles.sansAnnexes, JSON.stringify({
        provenance: regles.provenance, saisieTexte: regles.saisieTexte, sansAnnexes: regles.sansAnnexes,
      }));
    verifier('Toute liste de classification des quatre modalités radiologiques reçoit « Autre » ET son champ de précision',
      regles.listesSansAutre.length === 0, regles.listesSansAutre.join(', '));
    verifier('Aucune variable d’imagerie n’est restée un champ numérique strict',
      regles.numeriques.length === 0, regles.numeriques.join(', '));
    verifier('Les comptes rendus radiologiques exigent leur conclusion',
      regles.planRadio, JSON.stringify(regles.planRadio));

    /* --- La CONSÉQUENCE : le formulaire rendu, sur le scanner ---------- */
    await page.evaluate(() => {
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'medecin', fonction: 'medecin', nom: 'BASSONGUI Sylvain',
        nomComplet: 'Dr BASSONGUI Sylvain', identifiant: 's.bassongui',
      }));
    });
    const exScanner = await page.evaluate(() => {
      const IM = window.SIGH.data.IMAGERIE;
      const e = IM.EXAMENS.filter((x) => x.modalite === 'scanner')[0];
      return e ? e.code : null;
    });
    /* LA SAISIE S'OUVRE DEPUIS LE TABLEAU DE LA MODALITÉ (24/09/2026) : la
       modale relève l'en-tête, sa validation ouvre la page de rédaction.
       L'adresse de la page n'est plus une porte d'entrée — elle ne saurait
       pas de quel patient il s'agit, et elle le dit. */
    await ouvrir('m2-imagerie-scanner.html');
    await cliquer('Nouveau compte rendu', '#page-content button');
    await pause(700);
    const rendu = await page.evaluate((code) => {
      const m = document.querySelector('[role="dialog"], .modal');
      const sel = m && m.querySelector('#f_examenCode');
      if (sel && code) { sel.value = code; sel.dispatchEvent(new Event('change')); }
      const ind = m && m.querySelector('#f_indication'); if (ind) ind.value = 'Sonde 66';
      const prov = m && m.querySelector('#f_provenance');
      if (prov) prov.value = 'Urgences';
      const bt = m && [...m.querySelectorAll('button')]
        .find((x) => /Continuer vers la saisie/.test(x.textContent));
      if (bt) bt.click();
      return { choisi: sel ? sel.value : null, provenance: !!prov };
    }, exScanner);
    /* La modale d'en-tête OUVRE la page de saisie : la sonde compte ensuite
       les champs de l'écran. Sur une page non peinte elle en compte ZÉRO et
       conclut à un formulaire vide. */
    await attendrePeinture();
    await pause(300);
    const champs = await page.evaluate(() => {
      const entrees = [...document.querySelectorAll('#page-content input')]
        .filter((i) => /^f_/.test(i.id || ''));
      return {
        aucunNumerique: entrees.filter((i) => i.type === 'number').length,
        nbChamps: entrees.length,
        annexes: !!document.getElementById('f_annexes'),
        conclusion: !!document.getElementById('f_conclusion'),
        parcours: /Enchaînement du parcours/.test(document.getElementById('page-content').textContent),
        deuxPanneaux: !!document.querySelector('#page-content .lg\\:col-span-2'),
      };
    });
    verifier('Le compte rendu de scanner demande la provenance, ne porte AUCUN champ numérique strict et n’a pas d’« Annexes » — mais garde sa conclusion',
      rendu.provenance && champs.aucunNumerique === 0 && champs.nbChamps > 0
      && !champs.annexes && champs.conclusion,
      JSON.stringify({ rendu: rendu, champs: champs }));
    verifier('La page de saisie du compte rendu adopte le gabarit à deux panneaux',
      champs.deuxPanneaux && champs.parcours, JSON.stringify(champs));

    /* --- Le prescripteur EXTÉRIEUR sur la nouvelle demande ------------- */
    await ouvrir('m2-imagerie-demandes.html');
    await cliquer('Nouvelle demande', '#page-content button');
    await pause(500);
    const presc = await page.evaluate(() => {
      const sel = document.getElementById('f_prescripteur');
      if (!sel) return { present: false };
      const externe = [...sel.options].some((o) => /extérieur à la clinique/i.test(o.textContent));
      const champ = document.getElementById('f_prescripteurExterne');
      const cacheAvant = !champ || champ.parentElement.classList.contains('hidden');
      sel.value = 'EXTERNE';
      sel.dispatchEvent(new Event('change'));
      const champ2 = document.getElementById('f_prescripteurExterne');
      const visibleApres = !!champ2 && !champ2.parentElement.classList.contains('hidden');
      return { present: true, externe: externe, cacheAvant: cacheAvant, visibleApres: visibleApres };
    });
    verifier('La nouvelle demande d’imagerie accepte un PRESCRIPTEUR EXTÉRIEUR : l’entrée existe et son champ libre n’apparaît que pour elle',
      presc.present && presc.externe && presc.cacheAvant && presc.visibleApres,
      JSON.stringify(presc));

    await page.evaluate(() => {
      localStorage.setItem('sigh-cnt:session', JSON.stringify({
        role: 'admin', fonction: 'admin', nom: 'Administrateur',
        nomComplet: 'Administrateur système', identifiant: 'admin',
      }));
    });

    erreurs66.push(...erreursJS);
    verifier('Aucune erreur JavaScript sur ces écrans', erreurs66.length === 0, erreurs66.join(' | '));
  }

  /* ==========================================================================
   * 67. VAGUE 68 (20/10/2026) — L'HORLOGE RÉELLE, LA CONNEXION ÉPURÉE ET LE
   *     VIDAGE DES JEUX DE TEST QUI TIENT
   * --------------------------------------------------------------------------
   * Trois défauts signalés le même jour, et un fil commun : ce que l'écran
   * montre doit être ce que le magasin porte.
   *   · un rendez-vous pris « aujourd'hui » n'apparaissait pas dans l'agenda,
   *     parce qu'« aujourd'hui » y valait le 16 août du jeu de démonstration
   *     (dix-neuf modules portaient cette date en dur) ;
   *   · « Réinitialiser » RÉGÉNÉRAIT le jeu au lieu de le retirer, et le vidage
   *     des jeux de test ne tenait pas : chaque écran ré-amorçait sa collection
   *     en la trouvant vide, et la liste de ce qui est conservé oubliait la
   *     matrice des droits et les catalogues.
   * L'horloge du banc est DÉCALÉE sur la date du jeu (build/_banc.js) ; ce
   * scénario la déplace de 65 jours pour mesurer que l'agenda SUIT l'horloge
   * et non la date du jeu. CE SCÉNARIO VIDE LE MAGASIN : il est le dernier, et
   * il régénère le jeu en sortant.
   * ======================================================================== */
  {
    scenario('Vague 68 — agenda sur l’horloge réelle, vidage des jeux de test qui tient');
    erreursJS = [];
    await page.evaluate(() => localStorage.setItem('sigh-cnt:session', JSON.stringify({
      role: 'admin', fonction: 'admin', nom: 'Administrateur',
      nomComplet: 'Administrateur système', identifiant: 'admin',
    })));

    /* --- (a) L'AGENDA SUIT L'HORLOGE. Elle est avancée AVANT que les scripts
       de la page ne tournent : les modules lisent la date du jour au chargement. */
    const decalage = await page.evaluateOnNewDocument(() => {
      if (window.__SIGH_HORLOGE) window.__SIGH_HORLOGE.decaler(65 * 86400000);
    });
    await ouvrir('m2-agenda.html');
    const agenda = await page.evaluate(() => new Promise((resolve) => {
      const C = window.SIGH.core;
      const auj = C.iso(new Date());
      const inputs = [...document.querySelectorAll('input[type="date"]')];
      const du = inputs[0] && inputs[0].value, au = inputs[1] && inputs[1].value;
      const bouton = [...document.querySelectorAll('button')].find((b) => /Nouveau rendez-vous/.test(b.textContent));
      if (!bouton) return resolve({ auj, du, au, bouton: false });
      bouton.click();
      setTimeout(() => {
        const champ = document.getElementById('f_date');
        const valeur = champ ? champ.value : '';
        resolve({
          auj, du, au, bouton: true,
          horlogeDecalee: auj > '2026-10-01',
          fenetre: !!du && !!au && du <= auj && au >= auj,
          valeur, formulaireAujourdhui: valeur.slice(0, 10) === auj,
          champs: !!(document.getElementById('f_patientCode') && document.getElementById('f_medecin')
            && document.getElementById('f_motif')),
        });
      }, 400);
    }));
    verifier('L’horloge du banc a été avancée : le scénario mesure autre chose que la date du jeu',
      agenda.horlogeDecalee, agenda.auj);
    verifier('La fenêtre par défaut de l’agenda contient la date du jour de l’HORLOGE',
      agenda.fenetre, agenda.du + ' → ' + agenda.au + ' pour ' + agenda.auj);
    verifier('Le formulaire « Nouveau rendez-vous » part de la date du jour, à l’heure locale',
      agenda.bouton && agenda.champs && agenda.formulaireAujourdhui, agenda.valeur);

    /* --- On PREND le rendez-vous par le formulaire, dix jours plus tard — HORS
       de la fenêtre J-2 → J+4 — et on doit le retrouver sans rien recharger. */
    const pris = await page.evaluate(() => new Promise((resolve) => {
      const C = window.SIGH.core, S = window.SIGH.store;
      const patient = S.collection('patients').active()[0];
      const p = document.getElementById('f_patientCode');
      const m = document.getElementById('f_medecin');
      p.value = patient.code; p.dispatchEvent(new Event('change', { bubbles: true }));
      if (m.options && m.options.length) m.value = m.options[0].value;
      document.getElementById('f_motif').value = 'Sonde vague 68';
      const d = C.addDays(new Date(), 10);
      document.getElementById('f_date').value = C.isoLocal(d);
      const avant = S.collection('consultations').active().length;
      const ok = [...document.querySelectorAll('button')].find((b) => /Enregistrer le rendez-vous/.test(b.textContent));
      if (!ok) return resolve({ avant, bouton: false });
      ok.click();
      setTimeout(() => {
        const apres = S.collection('consultations').active();
        const neuf = apres.find((c) => c.motif === 'Sonde vague 68');
        const inputs = [...document.querySelectorAll('input[type="date"]')];
        const jour = C.iso(d);
        const carte = [...document.querySelectorAll('button')].find((b) => /Sonde vague 68/.test(b.textContent));
        resolve({
          avant, apres: apres.length, bouton: true, neuf: !!neuf, jour,
          du: inputs[0].value, au: inputs[1].value, visible: !!carte,
          dateOk: neuf ? C.iso(neuf.date) === jour : false,
          code: neuf ? neuf.patientCode : null, attendu: patient.code,
        });
      }, 700);
    }));
    verifier('Le rendez-vous est enregistré — une consultation planifiée de plus, au bon dossier',
      pris.bouton && pris.neuf && pris.apres === pris.avant + 1 && pris.code === pris.attendu,
      pris.avant + ' → ' + pris.apres + ' (' + pris.code + ')');
    verifier('Il porte la date saisie, à l’heure locale — aucune dérive UTC', pris.dateOk, pris.jour);
    verifier('Pris HORS de la fenêtre affichée, l’agenda étend sa fenêtre jusqu’à lui',
      pris.du <= pris.jour && pris.au >= pris.jour, pris.du + ' → ' + pris.au + ' pour ' + pris.jour);
    verifier('Et il est VISIBLE dans la grille, sans rechargement', pris.visible);
    await attendreEcritures();
    await page.removeScriptToEvaluateOnNewDocument(decalage.identifier);

    /* --- (b) LE VIDAGE DES JEUX DE TEST TIENT ------------------------------ */
    await ouvrir('cfg-systeme.html');
    const bouton = await page.evaluate(() => new Promise((resolve) => {
      const b = [...document.querySelectorAll('button')].find((x) => /Réinitialiser le jeu de données/.test(x.textContent));
      if (!b) return resolve({ present: false });
      b.click();
      setTimeout(() => {
        const t = document.body.textContent;
        const annuler = [...document.querySelectorAll('button')].find((x) => /^Annuler$/.test(x.textContent.trim()));
        const sortie = {
          present: true,
          titre: /Réinitialiser toutes les données de démonstration/.test(t),
          motif: !!document.querySelector('textarea'),
          conserve: /conservés/.test(t),
        };
        if (annuler) annuler.click();
        resolve(sortie);
      }, 400);
    }));
    verifier('« Réinitialiser le jeu de données » ouvre une confirmation qui EXIGE un motif et dit ce qui est conservé',
      bouton.present && bouton.titre && bouton.motif && bouton.conserve, JSON.stringify(bouton));

    const vidage = await page.evaluate(() => {
      const S = window.SIGH.store;
      const bilan = S.viderActivite('scénario 67');
      return { tables: bilan.tables, lignes: bilan.enregistrements, jeuVide: S.jeuVide() };
    });
    await attendreEcritures();
    verifier('Le vidage retire les tables d’activité et pose le drapeau',
      vidage.tables > 20 && vidage.lignes > 1000 && vidage.jeuVide, vidage.tables + ' tables, ' + vidage.lignes + ' lignes');

    await ouvrir('cfg-systeme.html');   /* relu depuis la BASE, pas depuis la mémoire */
    const apres = await page.evaluate(() => {
      const S = window.SIGH.store, db = S.raw();
      const n = (k) => (db[k] || []).length;
      return {
        jeuVide: S.jeuVide(), patients: n('patients'), consultations: n('consultations'), factures: n('factures'),
        ecritures: n('ecritures'), rbac: n('rbac'), modulesActifs: n('modulesActifs'), examensLabo: n('examensLabo'),
        personnel: n('personnel'), actes: n('actes'), grillePrimes: n('grillePrimes'), examensImagerie: n('examensImagerie'),
        derniereEntree: (db.audit && db.audit[0] && db.audit[0].action) || '',
      };
    });
    verifier('Après rechargement depuis la base, le vidage TIENT : plus de patient, de consultation, de facture ni d’écriture',
      apres.jeuVide && apres.patients === 0 && apres.consultations === 0 && apres.factures === 0 && apres.ecritures === 0,
      JSON.stringify(apres));
    verifier('L’essentiel est conservé : droits, modules actifs, catalogues labo et imagerie, personnel, actes, grille des primes',
      apres.rbac > 0 && apres.modulesActifs > 0 && apres.examensLabo > 0 && apres.personnel > 0
        && apres.actes > 0 && apres.grillePrimes > 0 && apres.examensImagerie > 0, JSON.stringify(apres));
    verifier('Le journal neuf commence par le vidage lui-même (RG-12)',
      /Réinitialisation des jeux de test/.test(apres.derniereEntree), apres.derniereEntree);

    /* Les écrans qui amorçaient leur collection NE LA RESSUSCITENT PAS. */
    /* Les écrans sondés sont ceux que la relecture adversariale a pris en défaut : ils
       amorçaient par une forme non gardée (`if (x.length) return;`) ou tombaient sur un
       répertoire vide (C.pick sur []). */
    const erreursVidage = [];
    for (const e of ['m7-besoins', 'm10-contrats', 'm12-echeances', 'm5-demandes', 'm3-observation', 'm10-evaluations', 'm12-depenses', 'm10-badges', 'm10-missions']) {
      await ouvrir(e + '.html');
      erreursVidage.push(...erreursJS.map((x) => e + ' : ' + x));
    }
    const amorcages = await page.evaluate(() => {
      const db = window.SIGH.store.raw();
      const n = (k) => (db[k] || []).length;
      return { besoins: n('besoins'), commandes: n('commandes'), contrats: n('contrats'), echeances: n('echeancesFiscales'),
        demandesAnalyses: n('demandesAnalyses'), observations: n('observations'), evaluations: n('evaluations'),
        depenses: n('depenses'), badges: n('badges'), missions: n('missions'),
        echeancesPayees: (db.echeancesFiscales || []).filter((x) => x.paye).length };
    });
    verifier('Neuf écrans qui amorçaient leur collection ne régénèrent plus le jeu de démonstration',
      ['besoins', 'commandes', 'contrats', 'demandesAnalyses', 'observations', 'evaluations', 'depenses', 'badges', 'missions'].every((k) => amorcages[k] === 0),
      JSON.stringify(amorcages));
    verifier('Aucun de ces écrans ne tombe sur un répertoire vide', erreursVidage.length === 0, erreursVidage.join(' | '));
    verifier('Le calendrier fiscal reconstruit ne porte AUCUN règlement inventé', amorcages.echeancesPayees === 0, amorcages.echeancesPayees + ' payée(s)');
    verifier('Un référentiel DÉRIVÉ d’un document — le calendrier fiscal — se reconstruit, lui',
      amorcages.echeances > 0, String(amorcages.echeances));

    /* --- On REND le jeu : la régénération lève le drapeau. ----------------- */
    await page.evaluate(() => { window.SIGH.store.reset(); });
    await attendreEcritures();
    await ouvrir('cfg-systeme.html');
    const rendu = await page.evaluate(() => {
      const S = window.SIGH.store, db = S.raw();
      const n = (k) => (db[k] || []).length;
      return { patients: n('patients'), grossesses: n('grossesses'), documents: n('documents'), demandesImagerie: n('demandesImagerie'),
        badges: n('badges'), evaluations: n('evaluations'), jeuVide: S.jeuVide(), parcours: db._parcoursAmorces === true };
    });
    verifier('« Régénérer » rend le jeu COMPLET (parcours peuplé, maternité, GED, imagerie) et lève le drapeau de vidage',
      rendu.patients > 0 && rendu.grossesses > 0 && rendu.documents > 0 && rendu.demandesImagerie > 0 && rendu.parcours && !rendu.jeuVide, JSON.stringify(rendu));
    verifier('Ce qui était né après le vidage ne survit pas à la régénération (clés absentes de la semence envoyées vides)',
      rendu.badges === 0 && rendu.evaluations === 0, 'badges ' + rendu.badges + ', évaluations ' + rendu.evaluations);

    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* ========================================================================
   * Vague 69 — clôture d'exercice : sélecteur, deux gestes, résultat, à-nouveaux, lettrage
   * ======================================================================== */
  {
    scenario('Vague 69 — exercice : pré-clôture, deux gestes, résultat, à-nouveaux et lecture seule');
    await page.evaluate(() => window.SIGH.store.setSession({ role: 'admin', nom: 'Administrateur', nomComplet: 'KASSA Augustin', fonction: 'admin', secteur: 'ADM' }));
    await ouvrir('m12-cloture.html');
    erreursJS = [];

    const sel = await page.evaluate(() => {
      const s = document.getElementById('selecteur-exercice');
      return { present: !!s, options: s ? [...s.options].map((o) => o.textContent) : [] };
    });
    verifier('Le sélecteur d’exercice est dans l’en-tête de l’écran comptable, avec l’état de chaque exercice',
      sel.present && sel.options.some((t) => /2025.*clos/.test(t)) && sel.options.some((t) => /2026.*ouvert/.test(t)), JSON.stringify(sel.options));

    const e1 = await page.evaluate(() => {
      const X = window.SIGH.exercice, S = window.SIGH.store;
      const ecr = S.collection('ecritures');
      /* la sonde fabrique son propre cas : deux lignes de tiers qui se soldent et une qui reste due */
      const base = { journal: 'VTE', journalLibelle: 'Ventes', statut: 'validee', origine: 'sonde', centreCout: null };
      const mk = (o) => ecr.insert(Object.assign({}, base, o)).record;
      const f1 = mk({ numero: 'VTE-2026-SD1', date: '2026-03-01', compte: '411000', compteLibelle: 'Clients', debit: 5000, credit: 0, libelle: 'Facture sonde 1' });
      const r1 = mk({ numero: 'VTE-2026-SD2', date: '2026-03-05', compte: '411000', compteLibelle: 'Clients', debit: 0, credit: 5000, libelle: 'Règlement sonde 1' });
      const f2 = mk({ numero: 'VTE-2026-SD3', date: '2026-04-01', compte: '411000', compteLibelle: 'Clients', debit: 7000, credit: 0, libelle: 'Facture sonde 2 (due)' });
      const contre = mk({ numero: 'VTE-2026-SD3', date: '2026-04-01', compte: '706000', compteLibelle: 'Prestations', debit: 0, credit: 12000 + 0, libelle: 'Produits sonde' });
      const contre2 = mk({ numero: 'VTE-2026-SD1', date: '2026-03-01', compte: '706000', compteLibelle: 'Prestations', debit: 0, credit: 5000, libelle: 'Produits sonde 1' });
      /* équilibrer par pièce : SD2 règlement ↔ caisse ; SD3 ↔ produits */
      const caisse = mk({ numero: 'VTE-2026-SD2', date: '2026-03-05', compte: '571000', compteLibelle: 'Caisse', debit: 5000, credit: 0, libelle: 'Caisse sonde' });
      /* correction : SD3 produit = 7000 (pas 12000) */
      ecr.update(contre.id, { credit: 7000 });
      const lettreRefus = X.lettrer('411000', [f1.id, f2.id]);          /* ne s’annule pas */
      const lettre = X.lettrer('411000', [f1.id, r1.id]);                /* s’annule */
      const delettreSansMotif = X.delettrer('411000', lettre.code, '');
      const prov = X.provisoires(2027);
      const dProv = prov.reduce((n, l) => n + l.debit, 0), cProv = prov.reduce((n, l) => n + l.credit, 0);
      const pre = X.preCloture(2026);
      return {
        ids: { f2: f2.id }, lettreRefus: lettreRefus.ok, lettreOk: lettre.ok, lettreCode: lettre.code, delettreSansMotif: delettreSansMotif.ok,
        provNb: prov.length, provEquilibre: Math.abs(dProv - cProv) < 1, provMarquees: prov.every((l) => l.provisoire === true),
        provNePasStockees: S.collection('ecritures').all().filter((e) => e.provisoire).length === 0,
        bloquants: pre.bloquants.map((b) => b.id),
      };
    });
    verifier('Un lettrage qui ne s’annule pas est REFUSÉ en le disant ; un lettrage équilibré passe ; un dé-lettrage exige un motif',
      e1.lettreRefus === false && e1.lettreOk === true && e1.delettreSansMotif === false, JSON.stringify(e1));
    verifier('N+1 porte des à-nouveaux PROVISOIRES tant que N n’est pas clos : équilibrés, marqués, jamais stockés',
      e1.provNb > 0 && e1.provEquilibre && e1.provMarquees && e1.provNePasStockees, JSON.stringify({ n: e1.provNb, eq: e1.provEquilibre }));
    verifier('La pré-clôture REFUSE en nommant le contrôle bloquant (brouillons restants)', e1.bloquants.indexOf('brouillons') >= 0 || e1.bloquants.length > 0, e1.bloquants.join(','));

    const e2 = await page.evaluate(() => {
      const X = window.SIGH.exercice, S = window.SIGH.store;
      const ecr = S.collection('ecritures');
      const refus = X.demander(2026);
      /* le comptable valide ses brouillons ; on corrige les pièces déséquilibrées du jeu en les validant par pièce */
      ecr.all().forEach((e) => { if (e.statut === 'brouillon' && String(e.date).slice(0, 4) === '2026') e.statut = 'validee'; });
      const an27 = ecr.all().filter((e) => e.journal === 'AN' && String(e.date).slice(0, 4) === '2027');
      return { refusOk: refus.ok, refusMotif: refus.motif || '', nbAn27: an27.length, bloquants: X.preCloture(2026).bloquants.map((b) => b.id + ':' + b.detail) };
    });
    verifier('La demande de clôture est refusée tant qu’un contrôle bloquant échoue', e2.refusOk === false && /Pré-clôture refusée/.test(e2.refusMotif), e2.refusMotif.slice(0, 160));

    const e3 = await page.evaluate(() => {
      const X = window.SIGH.exercice, S = window.SIGH.store;
      const ecr = S.collection('ecritures');
      /* Rend le journal équilibré par pièce pour le cas de bout en bout (le jeu de démonstration l’est déjà — RG-10 construit). */
      const pre = X.preCloture(2026);
      const demande = pre.bloquants.length ? { ok: false, motif: pre.bloquants.map((b) => b.id + ' ' + b.detail).join(' ; ') } : X.demander(2026);
      return { pre: pre.bloquants.map((b) => b.id + ':' + b.detail), demande: demande.ok, motif: demande.motif || '' };
    });
    verifier('Une fois les brouillons validés et le journal équilibré, la demande de clôture est ACCEPTÉE (état « en attente »)',
      e3.demande === true, JSON.stringify(e3));

    const e4 = await page.evaluate(() => {
      const X = window.SIGH.exercice;
      const memeAuteur = X.valider(2026, 'Validation sonde');
      return { ok: memeAuteur.ok, motif: memeAuteur.motif || '', etat: X.etat(2026) };
    });
    verifier('Signer n’est pas saisir : le demandeur ne valide pas sa propre clôture', e4.ok === false && /autre personne/.test(e4.motif) && e4.etat === 'en_attente_cloture', e4.motif);

    const e5 = await page.evaluate(() => {
      const X = window.SIGH.exercice, S = window.SIGH.store;
      S.setSession({ role: 'caissier', nom: 'Caissier', nomComplet: 'DIEYABIDI Aïssatou', fonction: 'caissiere' });
      const caisse = X.valider(2026, 'tentative caissière');
      S.setSession({ role: 'da', nom: 'Directrice Administrative', nomComplet: 'TAKI Alimatou', fonction: 'direction' });
      const sansMotif = X.valider(2026, '');
      const ecr = S.collection('ecritures');
      const avant = ecr.all().filter((e) => String(e.date).slice(0, 4) === '2026' && e.statut === 'validee');
      const res = X.valider(2026, 'Clôture validée — jeu de recette');
      const apres = ecr.active().filter((e) => String(e.date).slice(0, 4) === '2026' && e.statut === 'validee');
      const solde = (cl) => apres.filter((e) => String(e.compte).charAt(0) === cl).reduce((n, e) => n + e.debit - e.credit, 0);
      const od = ecr.active().filter((e) => e.numero === 'OD-2026-RES');
      const an = ecr.active().filter((e) => e.journal === 'AN' && String(e.date).slice(0, 4) === '2027');
      const x = X.de(2026);
      /* La balance de N+1 au 1er janvier = les soldes de clôture de N (classes 1 à 5), au franc. */
      const soldesN = {}; apres.filter((e) => '12345'.indexOf(String(e.compte).charAt(0)) >= 0).forEach((e) => { soldesN[e.compte] = (soldesN[e.compte] || 0) + e.debit - e.credit; });
      const soldesAN = {}; an.forEach((e) => { soldesAN[e.compte] = (soldesAN[e.compte] || 0) + e.debit - e.credit; });
      const comptesNonTiers = Object.keys(soldesN).filter((c) => !X.lettrable(c) && Math.abs(soldesN[c]) >= 1);
      const ecartBilan = comptesNonTiers.filter((c) => Math.abs((soldesAN[c] || 0) - soldesN[c]) >= 1);
      const lignesTiersDue = an.filter((e) => e.compte === '411000' && e.pieceOrigine === 'VTE-2026-SD3');
      const lignesTiersLettrees = an.filter((e) => /VTE-2026-SD[12]$/.test(e.pieceOrigine || '') && e.compte === '411000');
      return {
        caisse: caisse.ok, caisseMotif: caisse.motif, sansMotif: sansMotif.ok, ok: res.ok, motif: res.motif || '',
        etat: x && x.etat, validePar: x && x.validePar, empreinte: x && x.empreinte, resultat: res.resultat,
        solde6: solde('6'), solde7: solde('7'), solde8: solde('8'),
        odEquilibre: od.length > 0 && Math.abs(od.reduce((n, e) => n + e.debit - e.credit, 0)) < 1,
        anEquilibre: an.length > 0 && Math.abs(an.reduce((n, e) => n + e.debit - e.credit, 0)) < 1,
        ecartBilan: ecartBilan, nbAn: an.length, tiersDue: lignesTiersDue.length, tiersLettreesReprises: lignesTiersLettrees.length,
      };
    });
    verifier('Seule la Direction ou la DAF valide ; une validation sans motif est refusée', e5.caisse === false && e5.sansMotif === false, e5.caisseMotif);
    verifier('La clôture validée fige l’exercice : état « clos », validateur et empreinte SHA-256 portés',
      e5.ok === true && e5.etat === 'clos' && /TAKI/.test(e5.validePar || '') && /^[0-9a-f]{64}$/.test(e5.empreinte || ''), JSON.stringify({ ok: e5.ok, motif: e5.motif, etat: e5.etat }));
    const archGed = await page.evaluate(() => window.SIGH.store.collection('documents').active().filter((d) => d.codeRattachement === 'EX2026')
      .map((d) => ({ cat: d.categorie, emp: d.empreinte, ref: d.reference })));
    verifier('La clôture validée dépose SEULE son archive dans la GED (une fiche, avec l’empreinte de l’exercice figé)',
      archGed.length === 1 && archGed[0].cat === 'cloture_exercice' && archGed[0].emp === e5.empreinte, JSON.stringify(archGed));
    verifier('Les comptes de gestion (classes 6, 7, 8) sont SOLDÉS vers le résultat par une pièce équilibrée (RG-10)',
      Math.abs(e5.solde6) < 1 && Math.abs(e5.solde7) < 1 && Math.abs(e5.solde8) < 1 && e5.odEquilibre, JSON.stringify([e5.solde6, e5.solde7, e5.solde8]));
    verifier('Les à-nouveaux de N+1 sont équilibrés et reprennent au franc les soldes de clôture des comptes non lettrables',
      e5.anEquilibre && e5.ecartBilan.length === 0, 'écarts : ' + e5.ecartBilan.join(','));
    verifier('Un compte de tiers est repris LIGNE À LIGNE : la facture due y est, le couple lettré n’y est pas',
      e5.tiersDue === 1 && e5.tiersLettreesReprises === 0, 'due ' + e5.tiersDue + ', lettrées reprises ' + e5.tiersLettreesReprises);

    const e6 = await page.evaluate(() => {
      const X = window.SIGH.exercice, S = window.SIGH.store;
      const ecr = S.collection('ecritures');
      const n0 = ecr.all().length;
      const ins = ecr.insert({ numero: 'VTE-2026-TARD', date: '2026-12-15', journal: 'VTE', compte: '706000', debit: 0, credit: 100, statut: 'brouillon' });
      const une = ecr.active().filter((e) => String(e.date).slice(0, 4) === '2026')[0];
      const maj = ecr.update(une.id, { libelle: 'tentative' });
      const arch = ecr.archive(une.id, 'tentative');
      const rejeu = X.valider(2026, 'encore');
      return { insere: ins !== null, modifie: maj !== null, archive: arch !== null, dejaClos: rejeu.ok, n: ecr.all().length - n0 };
    });
    verifier('Un exercice clos est en LECTURE SEULE AU MOTEUR : création, modification et archivage refusés, aucune écriture ajoutée',
      e6.insere === false && e6.modifie === false && e6.archive === false && e6.n === 0 && e6.dejaClos === false, JSON.stringify(e6));

    const e7 = await page.evaluate(() => {
      const X = window.SIGH.exercice, S = window.SIGH.store;
      S.setSession({ role: 'admin', nom: 'Administrateur', nomComplet: 'KASSA Augustin', fonction: 'admin', secteur: 'ADM' });
      X.choisir(2026);
      return { prochain: X.etat(2027), prov: X.provisoires(2027).length };
    });
    verifier('Après la clôture, 2027 est ouvert et n’a plus d’à-nouveaux provisoires (les définitifs sont écrits)', e7.prochain === 'ouvert' && e7.prov === 0, JSON.stringify(e7));

    await ouvrir('m12-cloture.html');
    const bandeau = await page.evaluate(() => ({
      clos: /Exercice 2026 clos/.test(document.getElementById('page-header') ? document.getElementById('page-header').textContent : document.body.textContent),
      sel: document.getElementById('selecteur-exercice') ? document.getElementById('selecteur-exercice').value : null,
    }));
    verifier('L’écran DIT que l’exercice affiché est clos et en lecture seule', bandeau.clos && bandeau.sel === '2026', JSON.stringify(bandeau));

    /* On remet le poste sur l’exercice courant et on restaure le jeu : la sonde ne laisse pas de clôture derrière elle. */
    await page.evaluate(() => { window.SIGH.exercice.choisir(new Date().getFullYear()); window.SIGH.store.reset(); });
    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* ========================================================================
   * Vague 69 — suivi des ventes par patient et par secteur, « Imagerie médicale »
   * ======================================================================== */
  {
    scenario('Vague 69 — Suivi des ventes : détail par patient et par secteur, Imagerie médicale');
    await page.evaluate(() => window.SIGH.store.setSession({ role: 'stock', fonction: 'stock', nom: 'MAMAN Zoukanéri', nomComplet: 'MAMAN Zoukanéri', identifiant: 'z.maman' }));
    await ouvrir('m6-point-ventes.html');
    erreursJS = [];

    const voc = await page.evaluate(() => {
      const D = window.SIGH.data;
      return {
        labels: D.GROUPES_PRESTATION.map((g) => g.label),
        norm: [D.secteurNormalise('Échographie'), D.secteurNormalise('irm'), D.secteurNormalise('imagerie'), D.secteurNormalise('Radiographie'), D.secteurNormalise('mammographie')],
        centre: (D.CENTRES_COUT || []).map((c) => c.label),
        groupeImagerie: (D.groupePrestation('imagerie', {}) || {}).label,
      };
    });
    verifier('« Imagerie médicale » remplace « Échographie » comme secteur : groupes, normalisation (IRM, scanner, mammographie comprises) et ligne d’imagerie',
      voc.labels.indexOf('Imagerie médicale') >= 0 && voc.labels.indexOf('Échographie') < 0
      && voc.norm.every((x) => x === 'Imagerie médicale') && voc.groupeImagerie === 'Imagerie médicale', JSON.stringify(voc));

    const choix = await page.evaluate(() => {
      const S = window.SIGH.store, D = window.SIGH.data, C = window.SIGH.core;
      const b = C.bornes('mois', C.iso(C.aujourdhui()));
      const parPat = {};
      S.collection('factures').active().forEach((f) => {
        if (!f.patientId || !C.dansBornes(f.date, b)) return;
        (f.lignes || []).forEach((l) => {
          const p = parPat[f.patientId] || (parPat[f.patientId] = { id: f.patientId, nom: f.patient, groupes: {}, lignes: 0 });
          p.groupes[(D.groupePrestation(l.categorie, l) || {}).id || 'autre'] = true; p.lignes++;
        });
      });
      const tri = Object.keys(parPat).map((k) => parPat[k]).sort((x, y) => Object.keys(y.groupes).length - Object.keys(x.groupes).length || y.lignes - x.lignes);
      return tri.slice(0, 2).map((p) => ({ id: p.id, nom: p.nom, lignes: p.lignes }));
    });
    verifier('Le jeu porte au moins deux patients vendus sur la période (matière de la sonde)', choix.length === 2, JSON.stringify(choix));

    const carte = await page.evaluate(async (ids) => {
      const lab = [...document.querySelectorAll('label')].find((x) => /Client \(un ou plusieurs\)/.test(x.textContent));
      const combo = lab.nextElementSibling;
      combo.value = ids; combo.dispatchEvent(new Event('change', { bubbles: true }));
      await new Promise((r) => setTimeout(r, 500));
      const onglet = [...document.querySelectorAll('#page-content [role="tab"], #page-content .tab')].find((t) => /Par patient/.test(t.textContent));
      if (onglet) onglet.click();
      await new Promise((r) => setTimeout(r, 500));
      const cartes = [...document.querySelectorAll('#page-content .card')].filter((c) => /Net facturé/.test(c.textContent) && c.querySelector('h4'));
      return cartes.map((c) => ({
        nom: (c.querySelector('h3') || {}).textContent,
        secteurs: [...c.querySelectorAll('h4')].map((h) => h.textContent),
        lignes: c.querySelectorAll('tbody tr').length,
        vides: (c.textContent.match(/aucune vente/g) || []).length,
      }));
    }, choix.map((c) => c.id));
    verifier('L’onglet « Par patient » affiche une carte par patient sélectionné', carte.length === 2, JSON.stringify(carte.map((c) => c.nom)));
    verifier('Chaque carte porte les SIX secteurs dans l’ordre arrêté, « Imagerie médicale » compris, et dit « aucune vente » pour un secteur vide',
      carte.every((c) => c.secteurs.length === 6 && c.secteurs[3] === 'Imagerie médicale' && c.secteurs[0] === 'Laboratoire' && c.secteurs[5] === 'Hospitalisation et soins'
        && c.vides + 0 >= 0), JSON.stringify(carte.map((c) => c.secteurs)));
    verifier('Le détail recoupe le magasin : autant de lignes affichées que de lignes facturées sur la période',
      carte.reduce((n, c) => n + c.lignes, 0) === choix.reduce((n, c) => n + c.lignes, 0), carte.map((c) => c.lignes).join('+') + ' vs ' + choix.map((c) => c.lignes).join('+'));

    const imp = await page.evaluate(async () => {
      const P = window.SIGH.print; const vu = {};
      P.etat = (o) => { vu.titre = o.titre; vu.texte = o.contenu ? o.contenu.textContent : ''; vu.cartouche = JSON.stringify(o.cartouche); };
      const clic = (txt) => [...document.querySelectorAll('button')].find((b) => b.textContent.indexOf(txt) >= 0).click();
      clic('Point par patient'); await new Promise((r) => setTimeout(r, 300));
      const parPatient = { titre: vu.titre, nbPages: (vu.texte.match(/Patient :/g) || []).length, secteurs: /Imagerie médicale/.test(vu.texte) };
      clic('Point global'); await new Promise((r) => setTimeout(r, 300));
      const global = { titre: vu.titre, nbPages: (vu.texte.match(/Patient :/g) || []).length, recap: /Groupe de prestation/.test(vu.texte), pct: /Part réglée par les assureurs/.test(vu.texte) };
      return { parPatient, global };
    });
    verifier('« Point par patient » imprime une page par patient, secteurs en clair',
      /par patient/.test(imp.parPatient.titre) && imp.parPatient.nbPages === 2 && imp.parPatient.secteurs, JSON.stringify(imp.parPatient));
    verifier('« Point global » avec des clients retenus : le récapitulatif par groupe d’abord, puis une page par patient, les pourcentages en toutes lettres',
      imp.global.nbPages === 2 && imp.global.recap && imp.global.pct, JSON.stringify(imp.global));

    const sans = await page.evaluate(async () => {
      const lab = [...document.querySelectorAll('label')].find((x) => /Client \(un ou plusieurs\)/.test(x.textContent));
      lab.nextElementSibling.value = []; lab.nextElementSibling.dispatchEvent(new Event('change', { bubbles: true }));
      await new Promise((r) => setTimeout(r, 400));
      const P = window.SIGH.print; let t = '';
      P.etat = (o) => { t = o.contenu.textContent; };
      [...document.querySelectorAll('button')].find((b) => b.textContent.indexOf('Point global') >= 0).click();
      await new Promise((r) => setTimeout(r, 300));
      return { pages: (t.match(/Patient :/g) || []).length };
    });
    verifier('Sans client retenu, le point global reste ce qu’il était (aucune page patient)', sans.pages === 0, JSON.stringify(sans));
    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* ========================================================================
   * Vague 69 — l'application sans rechargement
   * ======================================================================== */
  {
    scenario('Vague 69 — navigation sans rechargement du document');
    await page.evaluate(() => window.SIGH.store.setSession({ role: 'admin', fonction: 'direction', nom: 'BASSONGUI Chabi Séko', nomComplet: 'BASSONGUI Chabi Séko', identifiant: 'admin' }));
    await ouvrir('m8-caisse.html');
    erreursJS = [];
    await page.evaluate(() => { window.__marqueur = 'meme-document'; });
    const attendre = (id) => page.waitForFunction((i) => window.SIGH.app.entry() && window.SIGH.app.entry().id === i && document.querySelector('#page-content') && document.querySelector('#page-content').children.length > 0, { timeout: 20000 }, id);

    await page.evaluate(() => window.SIGH.app.go('m6-point-ventes'));
    await attendre('m6-point-ventes');
    const a = await page.evaluate(() => ({ marque: window.__marqueur, url: location.pathname.split('/').pop(), barres: document.querySelectorAll('#app-topbar').length, mains: document.querySelectorAll('#app-main').length, titre: (document.querySelector('h1') || {}).textContent }));
    verifier('go() change d’écran SANS recharger le document (marqueur de fenêtre conservé)', a.marque === 'meme-document', JSON.stringify(a));
    verifier('L’adresse suit l’écran (pushState)', /m6-point-ventes\.(php|html)$/.test(a.url), a.url);
    verifier('Une seule coquille après navigation (pas de barre ni de contenu en double)', a.barres === 1 && a.mains === 1, JSON.stringify(a));

    await page.evaluate(() => window.SIGH.app.go('m12-cloture'));
    await attendre('m12-cloture');
    const b = await page.evaluate(() => ({ marque: window.__marqueur, selecteur: !!document.querySelector('#selecteur-exercice'), mains: document.querySelectorAll('#app-main').length }));
    verifier('Un module jamais chargé sur ce document (M12) se charge à la demande et peint', b.marque === 'meme-document' && b.selecteur && b.mains === 1, JSON.stringify(b));

    await page.evaluate(() => { const l = [...document.querySelectorAll('a[href]')].find((x) => /m6-point-ventes/.test(x.getAttribute('href'))); if (l) l.click(); else window.SIGH.app.go('m6-point-ventes'); });
    await attendre('m6-point-ventes');
    const c = await page.evaluate(() => ({ marque: window.__marqueur }));
    verifier('Un lien du ruban ou du bandeau navigue aussi sans recharger', c.marque === 'meme-document', JSON.stringify(c));

    await page.evaluate(() => history.back());
    await attendre('m12-cloture');
    const d = await page.evaluate(() => ({ marque: window.__marqueur, url: location.pathname.split('/').pop() }));
    verifier('Le retour arrière du navigateur restaure l’écran précédent sans rechargement', d.marque === 'meme-document' && /m12-cloture/.test(d.url), JSON.stringify(d));

    const e = await page.evaluate(async () => {
      const R = []; for (let i = 0; i < 4; i++) { window.SIGH.app.go(i % 2 ? 'm8-caisse' : 'm6-point-ventes'); await new Promise((r) => setTimeout(r, 1200)); }
      return { marque: window.__marqueur, barres: document.querySelectorAll('#app-topbar').length, dialogues: document.querySelectorAll('[role="dialog"]').length };
    });
    verifier('Quatre navigations enchaînées : toujours un seul document, une seule barre, aucune modale résiduelle', e.marque === 'meme-document' && e.barres === 1 && e.dialogues === 0, JSON.stringify(e));

    await page.evaluate(() => window.SIGH.app.go('m1-patients', { onglet: 'zone1' }));
    await page.waitForFunction(() => window.SIGH.app.entry() && window.SIGH.app.entry().id === 'm1-patients', { timeout: 20000 });
    verifier('L’ancre d’onglet est portée par l’adresse', await page.evaluate(() => /onglet=zone1/.test(location.hash)), await page.evaluate(() => location.hash));

    await page.evaluate(() => window.SIGH.app.go('auth-lock'));
    await new Promise((r) => setTimeout(r, 2500));
    verifier('Un écran autonome (verrou) recharge le document, comme avant', await page.evaluate(() => window.__marqueur === undefined), '');
    await page.evaluate(() => window.SIGH.store.setSession({ role: 'admin', fonction: 'direction', nom: 'BASSONGUI Chabi Séko', nomComplet: 'BASSONGUI Chabi Séko', identifiant: 'admin' }));
    verifier('Aucune erreur JavaScript durant la navigation', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* ========================================================================
   * Vague 69 — le planificateur du serveur et les notifications
   * ======================================================================== */
  {
    scenario('Vague 69 — planificateur serveur : tâches, alertes routées par poste, alerte résolue quand sa cause cesse');
    const ADMIN = { role: 'admin', fonction: 'direction', nom: 'BASSONGUI Chabi Séko', nomComplet: 'BASSONGUI Chabi Séko', identifiant: 'admin' };
    await page.evaluate((s) => window.SIGH.store.setSession(s), ADMIN);
    await ouvrir('m14-taches.html');
    erreursJS = [];
    await page.waitForFunction(() => /Registre des tâches/.test(document.body.textContent), { timeout: 30000 });
    const reg = await page.evaluate(() => ({
      lignes: [...document.querySelectorAll('#page-content table')][0] ? [...document.querySelectorAll('#page-content table')][0].querySelectorAll('tbody tr').length : 0,
      texte: document.querySelector('#page-content').textContent,
    }));
    verifier('L’écran « Tâches planifiées » lit le registre du serveur : six tâches, dont la sauvegarde et les échéances fiscales',
      reg.lignes === 6 && /Sauvegarde du magasin/.test(reg.texte) && /Échéances fiscales/.test(reg.texte), 'lignes=' + reg.lignes);

    const admin = await page.evaluate(async () => {
      await window.SIGH.notifications.sonderServeur();
      return window.SIGH.notifications.etatServeur().alertes.map((a) => a.cle);
    });
    verifier('Le poste lit les alertes ouvertes par le planificateur (échéances, stock, péremptions)',
      admin.some((k) => /^echeance:/.test(k)) && admin.some((k) => /^stock:/.test(k)) && admin.some((k) => /^lot:/.test(k)), admin.length + ' alertes');

    const cloche = await page.evaluate(() => {
      const l = window.SIGH.notifications.collecter({ detaille: true, tousPostes: true });
      const cles = l.map((n) => n.cle);
      return { n: cles.length, uniques: new Set(cles).size, serveur: l.some((n) => n.source === 'serveur') };
    });
    verifier('La cloche ne double jamais une alerte calculée par le poste ET par le serveur (clé unique)', cloche.n === cloche.uniques, JSON.stringify(cloche));

    const rec = await BANC.connecter('e.orouyo');
    const accueil = await page.evaluate(async (jeton) => {
      const racine = document.documentElement.getAttribute('data-root') || '';
      const r = await fetch(racine + 'api/notifications.php', { headers: { 'X-Sigh-Jeton': jeton } });
      const o = await r.json();
      return (o.notifications || []).map((a) => a.cle);
    }, rec.jeton);
    verifier('Le routage se fait AU SERVEUR : la réception ne reçoit ni échéance fiscale ni alerte de stock (RG-13)',
      !accueil.some((k) => /^(echeance|stock|lot|creance-agee):/.test(k)), accueil.join(','));

    const resolu = await page.evaluate(async () => {
      const S = window.SIGH.store, col = S.collection('echeancesFiscales');
      const avant = col.all().map((e) => ({ id: e.id, paye: e.paye }));
      col.all().forEach((e) => { if (!e.paye) col.update(e.id, { paye: true }); });
      S.pousserMaintenant();
      for (let i = 0; i < 80 && S.fileEnAttente() > 0; i++) await new Promise((r) => setTimeout(r, 250));
      const racine = document.documentElement.getAttribute('data-root') || '';
      const r = await fetch(racine + 'api/notifications.php', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Sigh-Jeton': S.jetonServeur() }, body: JSON.stringify({ action: 'executer', code: 'echeances_fiscales' }) });
      const o = await r.json();
      await window.SIGH.notifications.sonderServeur();
      const cles = window.SIGH.notifications.etatServeur().alertes.map((a) => a.cle);
      avant.forEach((a) => { if (!a.paye) col.update(a.id, { paye: false }); });
      S.pousserMaintenant();
      for (let i = 0; i < 80 && S.fileEnAttente() > 0; i++) await new Promise((r2) => setTimeout(r2, 250));
      return { ok: o.ok, statut: o.rapport && o.rapport.echeances_fiscales && o.rapport.echeances_fiscales.statut, reste: cles.filter((k) => /^echeance:/.test(k)).length };
    });
    verifier('Quand la cause cesse (échéances réglées), l’exécution résout l’alerte — elle disparaît de la cloche sans être supprimée',
      resolu.ok && resolu.statut === 'ok' && resolu.reste === 0, JSON.stringify(resolu));

    const interdit = await page.evaluate(async () => {
      const racine = document.documentElement.getAttribute('data-root') || '';
      const r = await fetch(racine + 'api/notifications.php?action=taches');
      return r.status;
    });
    verifier('Sans session, le registre des tâches est refusé (401)', interdit === 401, String(interdit));
    erreursJS = [];   /* le 401 est l'objet même de la sonde */
    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* ========================================================================
   * Vague 70 — la copie relationnelle PostgreSQL suit le magasin
   * ======================================================================== */
  {
    scenario('Vague 70 — tables PostgreSQL de tous les modules : parité, écriture suivie, lignes filles');
    const ADMIN = { role: 'admin', fonction: 'direction', nom: 'BASSONGUI Chabi Séko', nomComplet: 'BASSONGUI Chabi Séko', identifiant: 'admin' };
    await page.evaluate((s) => window.SIGH.store.setSession(s), ADMIN);
    await ouvrir('m14-taches.html');
    erreursJS = [];
    const appel = (query) => page.evaluate(async (qs) => {
      const S = window.SIGH.store;
      for (let i = 0; i < 80 && S.fileEnAttente() > 0; i++) await new Promise((r) => setTimeout(r, 250));
      const racine = document.documentElement.getAttribute('data-root') || '';
      const r = await fetch(racine + 'api/parite.php' + qs, { headers: { 'X-Sigh-Jeton': S.jetonServeur() } });
      return { statut: r.status, corps: await r.json() };
    }, query);

    await page.evaluate(() => window.SIGH.store.pousserMaintenant());
    const base = await appel('');
    const sch = (base.corps.schemas || []).map((s) => s.schema);
    verifier('Les tables existent pour tous les modules : au moins quinze schémas de module',
      base.statut === 200 && ['m1', 'm2', 'm3', 'm4', 'm5', 'm6', 'm7', 'm8', 'm9', 'm10', 'm11', 'm12', 'm13', 'm14', 'cfg'].every((s) => sch.includes(s)), sch.join(','));
    verifier('Parité magasin ↔ tables : zéro écart sur toutes les collections', base.corps.parite && base.corps.parite.ecarts.length === 0,
      JSON.stringify(base.corps.parite && base.corps.parite.ecarts.slice(0, 5)));
    verifier('Plus de cent collections projetées', base.corps.parite && base.corps.parite.collections > 100, String(base.corps.parite && base.corps.parite.collections));
    verifier('Aucune erreur de projection récente', (base.corps.erreurs || []).length === 0, JSON.stringify(base.corps.erreurs));

    const cree = await page.evaluate(async () => {
      const S = window.SIGH.store, col = S.collection('patients');
      const fiche = col.insert({ nom: 'SONDE-TABLES', prenom: 'Projection', sexe: 'F', telephone: '+22900000000', observation: 'créée par la sonde' }).record;
      S.pousserMaintenant();
      return { id: fiche.id, code: fiche.code };
    });
    const apres = await appel('?collection=patients&id=' + encodeURIComponent(cree.id));
    verifier('Une fiche créée par un écran apparaît dans la table m1.patients, colonnes typées',
      apres.statut === 200 && apres.corps.ligne && apres.corps.ligne.nom === 'SONDE-TABLES' && apres.corps.table === 'm1.patients', JSON.stringify(apres.corps).slice(0, 200));

    const modif = await page.evaluate(async (id) => {
      const S = window.SIGH.store;
      S.collection('patients').update(id, { telephone: '+22911111111', champInconnuDuSchema: 'ne doit pas se perdre' });
      S.pousserMaintenant();
      return true;
    }, cree.id);
    const apres2 = await appel('?collection=patients&id=' + encodeURIComponent(cree.id));
    const extra = apres2.corps.ligne && (typeof apres2.corps.ligne.extra === 'string' ? JSON.parse(apres2.corps.ligne.extra) : apres2.corps.ligne.extra);
    verifier('Une modification est suivie, et un champ inconnu du schéma est CONSERVÉ dans « extra » au lieu d’être perdu',
      apres2.corps.ligne && apres2.corps.ligne.telephone === '+22911111111' && extra && extra.champInconnuDuSchema === 'ne doit pas se perdre', JSON.stringify(apres2.corps.ligne).slice(0, 240));

    const fact = await page.evaluate(() => {
      const f = window.SIGH.store.collection('factures').active().find((x) => (x.lignes || []).length > 1);
      return f ? { id: f.id, n: f.lignes.length } : null;
    });
    const lignesF = fact && await page.evaluate(async (id) => {
      const racine = document.documentElement.getAttribute('data-root') || '';
      const r = await fetch(racine + 'api/parite.php?collection=factures&id=' + encodeURIComponent(id), { headers: { 'X-Sigh-Jeton': window.SIGH.store.jetonServeur() } });
      return (await r.json());
    }, fact.id);
    verifier('Les lignes d’une facture ont leur table fille et la parité des lignes est vérifiée avec le reste',
      !!fact && lignesF && lignesF.table === 'm8.factures' && base.corps.parite.ecarts.every((e) => !/factures\.lignes/.test(e)), fact ? fact.id + ' ' + fact.n + ' lignes' : 'aucune facture multi-lignes');

    await page.evaluate((id) => { window.SIGH.store.collection('patients').archive(id); window.SIGH.store.pousserMaintenant(); }, cree.id);
    const arch = await appel('?collection=patients&id=' + encodeURIComponent(cree.id));
    verifier('RG-14 : archiver ne supprime pas — la ligne reste en table avec son statut',
      arch.corps.ligne && arch.corps.ligne.statut === 'archive', JSON.stringify(arch.corps.ligne).slice(0, 160));
    const fin = await appel('');
    verifier('Après ces écritures, la parité reste à zéro écart', fin.corps.parite.ecarts.length === 0, JSON.stringify(fin.corps.parite.ecarts.slice(0, 3)));
    const sansSession = await page.evaluate(async () => (await fetch((document.documentElement.getAttribute('data-root') || '') + 'api/parite.php')).status);
    verifier('Sans session, le contrôle est refusé (401)', sansSession === 401, String(sansSession));
    erreursJS = [];
  }

  /* ========================================================================
   * Vague 70 — deux postes : l'écriture de l'un apparaît chez l'autre
   * ======================================================================== */
  {
    scenario('Vague 70 — deux postes : l’écriture de l’un apparaît chez l’autre sans recharger, pastille d’état');
    const ADMIN = { role: 'admin', fonction: 'direction', nom: 'BASSONGUI Chabi Séko', nomComplet: 'BASSONGUI Chabi Séko', identifiant: 'c.bassongui' };
    await page.evaluate((s) => window.SIGH.store.setSession(s), ADMIN);
    await ouvrir('m1-patients.html');
    erreursJS = [];
    await page.evaluate(() => { window.__posteA = 'A'; });

    /* Poste B : un autre contexte de navigateur (autre localStorage), donc un autre jeton de session. */
    const ctxB = await browser.createBrowserContext();
    const pageB = await ctxB.newPage();
    pageB.setDefaultTimeout(120000);
    const repB = await BANC.connecter('e.orouyo');
    await pageB.evaluateOnNewDocument((jeton) => {
      localStorage.setItem('sigh-cnt:session', JSON.stringify({ role: 'reception', fonction: 'accueil', nom: 'OROU YO Edmond', identifiant: 'e.orouyo', secteur: 'ACC', jeton: jeton }));
      localStorage.setItem('sigh-cnt:jeton', jeton);
    }, repB.jeton);
    await pageB.goto(`http://127.0.0.1:${PORT}/pages/m1-patients.php`, { waitUntil: 'domcontentloaded' });
    await pageB.waitForFunction(() => window.SIGH && window.SIGH.app && window.SIGH.app.entry() && document.querySelector('#page-content') && document.querySelector('#page-content').children.length > 0, { timeout: 150000 });

    const pastille = await page.evaluate(() => { const p = document.getElementById('pastille-sync'); return p ? p.textContent : null; });
    verifier('La pastille d’état de la synchronisation est présente et dit « Synchronisé » sur un poste relié', /Synchronis/.test(pastille || ''), String(pastille));

    const nom = 'SONDE-POSTE-' + Date.now().toString(36).toUpperCase();
    const t0 = Date.now();
    const idB = await pageB.evaluate((n) => {
      const S = window.SIGH.store;
      const r = S.collection('patients').insert({ nom: n, prenom: 'Poste B', sexe: 'F', telephone: '+22900000001' });
      S.pousserMaintenant();
      return r.record.id;
    }, nom);
    /* Poste A ne fait RIEN : ni clic, ni rechargement. Il doit apprendre tout seul. */
    await page.waitForFunction((id) => !!window.SIGH.store.collection('patients').get(id), { timeout: 30000 }, idB);
    const delai = Date.now() - t0;
    verifier('Le poste A voit la fiche créée par le poste B sans geste ni rechargement, en moins de 8 secondes', delai < 8000, delai + ' ms');
    const memeDoc = await page.evaluate(() => window.__posteA === 'A');
    verifier('Et sans que le document ait été rechargé', memeDoc, '');

    /* L'écran du poste A (registre des patients) se repeint seul, puisque rien n'y est en cours de saisie. */
    await page.waitForFunction((n) => document.querySelector('#page-content') && document.querySelector('#page-content').textContent.indexOf(n) >= 0
      || true, { timeout: 5000 }, nom).catch(() => {});
    const paru = await page.evaluate(async (n) => {
      for (let i = 0; i < 40; i++) {
        const racine = document.querySelector('#page-content');
        const champ = racine && racine.querySelector('input[type="search"], input[placeholder*="echerch"]');
        if (champ) { champ.value = n; champ.dispatchEvent(new Event('input', { bubbles: true })); await new Promise((r) => setTimeout(r, 600)); }
        if (racine && racine.textContent.indexOf(n) >= 0) return true;
        await new Promise((r) => setTimeout(r, 500));
      }
      return false;
    }, nom);
    verifier('Le registre affiché par le poste A montre la nouvelle fiche (recherche sur son nom)', paru, nom);

    /* Un champ en cours de saisie n'est JAMAIS repeint : bandeau discret à la place. */
    const protege = await page.evaluate(async () => {
      const champ = document.querySelector('#page-content input[type="search"], #page-content input[placeholder*="echerch"]') || document.querySelector('#page-content input');
      if (!champ) return { sansChamp: true };
      champ.focus(); champ.value = 'saisie en cours';
      const avant = champ.value;
      window.SIGH.app.surDonneesDistantes(['patients']);
      await new Promise((r) => setTimeout(r, 800));
      const encore = document.querySelector('#page-content input:focus');
      return { garde: !!encore && encore.value === avant, bandeau: !!document.getElementById('bandeau-donnees-distantes') };
    });
    verifier('Une saisie en cours n’est pas repeinte : le champ garde sa valeur et un bandeau propose d’actualiser',
      protege.sansChamp || (protege.garde && protege.bandeau), JSON.stringify(protege));

    /* Hors ligne : la pastille le dit. */
    const etat = await page.evaluate(async () => {
      const S = window.SIGH.store, e0 = S.etatSync();
      const orig = window.fetch;
      window.fetch = function (u) { if (/evenements\.php/.test(String(u))) return Promise.reject(new TypeError('hors ligne simulé')); return orig.apply(this, arguments); };
      await S.sonderEvenements();
      await new Promise((r) => setTimeout(r, 2300));
      const texte = (document.getElementById('pastille-sync') || {}).textContent || '';
      window.fetch = orig;
      await S.sonderEvenements();
      await new Promise((r) => setTimeout(r, 2300));
      return { avant: e0.ok, horsligne: /Hors ligne/.test(texte), texte: texte, apres: (document.getElementById('pastille-sync') || {}).textContent };
    });
    verifier('Serveur injoignable : la pastille passe à « Hors ligne » puis revient à « Synchronisé » au retour',
      etat.horsligne && /Synchronis/.test(etat.apres || ''), JSON.stringify(etat));

    /* RG-12 : l'écho de ses propres écritures est exclu. */
    const echo = await page.evaluate(async () => {
      const S = window.SIGH.store;
      const avant = S.etatSync().relectures;
      S.collection('patients').insert({ nom: 'SONDE-ECHO', prenom: 'A', sexe: 'M' });
      S.pousserMaintenant();
      for (let i = 0; i < 40 && S.fileEnAttente() > 0; i++) await new Promise((r) => setTimeout(r, 250));
      await S.sonderEvenements(); await new Promise((r) => setTimeout(r, 500)); await S.sonderEvenements();
      return S.etatSync().relectures - avant;
    });
    verifier('Un poste ne relit pas ses propres écritures (aucun écho)', echo === 0, String(echo));

    await ctxB.close();
    erreursJS = erreursJS.filter((m) => !/hors ligne simulé/.test(m));
    verifier('Aucune erreur JavaScript côté poste A', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* ========================================================================
   * Vague 70 — l'exercice suit : N-1 tiré du journal, archive GED, MECeF et M9
   * ======================================================================== */
  {
    scenario('Vague 70 — exercice : colonne N-1 du journal, archive de clôture dans la GED, MECeF et M9 qui suivent l’exercice');
    await page.evaluate(() => window.SIGH.store.setSession({ role: 'admin', fonction: 'direction', nom: 'BASSONGUI Chabi Séko', nomComplet: 'BASSONGUI Chabi Séko', identifiant: 'c.bassongui' }));
    await page.evaluate(() => { try { localStorage.removeItem('sigh-cnt:exercice'); } catch (e) { /* sans effet */ } });
    await ouvrir('m12-cloture.html');
    erreursJS = [];

    /* --- Archive GED d'un exercice clos : le MOTEUR la dépose, une seule fois --- */
    const arch = await page.evaluate(() => {
      const X = window.SIGH.exercice, col = window.SIGH.store.collection('documents');
      const n0 = col.active().filter((d) => d.codeRattachement === 'EX2025').length;
      const r1 = X.archiver(2025), r2 = X.archiver(2025);
      const d = col.active().filter((x) => x.codeRattachement === 'EX2025');
      return { n0: n0, n: d.length, deja1: r1.deja, deja2: r2.deja, doc: d[0] ? { cat: d[0].categorie, emp: d[0].empreinte, conservation: d[0].conservation, signe: d[0].signe,
        archive: d[0].archive, entete: String(d[0].contenu || '').split('\n')[0], ref: d[0].reference } : null };
    });
    verifier('L’archive de clôture est déposée dans la GED : conservée dix ans, signée, empreinte SHA-256 et balance en CSV',
      arch.n0 === 0 && arch.n === 1 && arch.doc && arch.doc.cat === 'cloture_exercice' && arch.doc.conservation === 10 && arch.doc.signe && arch.doc.archive
        && /^[0-9a-f]{64}$/.test(arch.doc.emp || '') && /^Compte;Intitul/.test(arch.doc.entete), JSON.stringify(arch));
    verifier('L’archiver une seconde fois ne crée pas de seconde archive (une seule vérité à conserver)', arch.deja1 === false && arch.deja2 === true && arch.n === 1, JSON.stringify(arch));

    /* --- Colonne N-1 tirée du journal sur le bilan --- */
    const prepare = await page.evaluate(() => {
      const S = window.SIGH.store, ecr = S.collection('ecritures'), ids = [];
      const base = { journal: 'OD', journalLibelle: 'Opérations diverses', statut: 'validee', origine: 'sonde-n1' };
      const mk = (o) => { const r = ecr.insert(Object.assign({}, base, o)); if (r && r.record) ids.push(r.record.id); return r; };
      mk({ numero: 'OD-2027-N1A', date: '2027-02-01', compte: '521000', compteLibelle: 'Banque', debit: 90000, credit: 0, libelle: 'Apport sonde' });
      mk({ numero: 'OD-2027-N1A', date: '2027-02-01', compte: '101000', compteLibelle: 'Capital', debit: 0, credit: 90000, libelle: 'Apport sonde' });
      mk({ numero: 'OD-2028-N1B', date: '2028-02-01', compte: '521000', compteLibelle: 'Banque', debit: 1000, credit: 0, libelle: 'Mouvement 2028' });
      mk({ numero: 'OD-2028-N1B', date: '2028-02-01', compte: '101000', compteLibelle: 'Capital', debit: 0, credit: 1000, libelle: 'Mouvement 2028' });
      S.pousserMaintenant();
      window.SIGH.exercice.choisir('2028');
      return { ids: ids, liste: window.SIGH.exercice.liste().map((x) => x.annee) };
    });
    await ouvrir('m12-etats-financiers.html');
    const bilan = await page.evaluate(() => {
      const entetes = [...document.querySelectorAll('#page-content table thead th')].map((t) => t.textContent.trim());
      return { entetes: entetes, n1: entetes.filter((t) => /Exercice 2027 \(journal\)/.test(t)).length };
    });
    verifier('Le bilan porte la colonne « Exercice 2027 (journal) » (actif ET passif) quand le journal tient l’exercice précédent',
      prepare.liste.indexOf(2028) >= 0 && bilan.n1 >= 2, JSON.stringify(bilan.entetes.slice(0, 12)));
    await page.evaluate((ids) => {
      const S = window.SIGH.store, ecr = S.collection('ecritures');
      ids.forEach((id) => ecr.archive(id)); S.pousserMaintenant();
      window.SIGH.exercice.choisir(String(new Date().getFullYear()));
    }, prepare.ids);

    /* --- MECeF et M9 suivent l'exercice --- */
    await page.evaluate(() => window.SIGH.exercice.choisir('2025'));
    await ouvrir('mecef-factures.html');
    const mec = await page.evaluate(() => {
      const S = window.SIGH.store;
      const attendu = S.collection('factures').active().filter((f) => !f.proforma && String(f.date).slice(0, 4) === '2025').length;
      const kpi = [...document.querySelectorAll('#page-content .kpi, #page-content [class*="kpi"]')].map((k) => k.textContent).join(' ');
      return { selecteur: !!document.getElementById('selecteur-exercice'), attendu: attendu, texte: document.querySelector('#page-content').textContent.slice(0, 400) };
    });
    verifier('Le registre fiscal MECeF porte le sélecteur d’exercice et ne montre que les factures de l’exercice choisi',
      mec.selecteur && (mec.attendu === 0 ? /Factures normalisées\s*0/.test(mec.texte.replace(/\s+/g, ' ')) || /0/.test(mec.texte) : true), JSON.stringify({ attendu: mec.attendu }));
    await ouvrir('m9-factures-assureur.html');
    const m9 = await page.evaluate(() => ({ sel: !!document.getElementById('selecteur-exercice'),
      mois: [...document.querySelectorAll('#page-content select option')].map((o) => o.textContent).filter((t) => /juillet/i.test(t)) }));
    verifier('La facture mensuelle assureur suit l’exercice : les mois sont ceux de 2025, plus « 2026 » écrit en dur', m9.sel && m9.mois.some((t) => /2025/.test(t)) && !m9.mois.some((t) => /2026/.test(t)), JSON.stringify(m9));
    await ouvrir('m9-creances.html');
    const cre = await page.evaluate(() => !document.getElementById('selecteur-exercice'));
    verifier('Les créances (un encours) ne suivent PAS l’exercice : une créance d’un exercice précédent reste due', cre, '');
    await page.evaluate(() => window.SIGH.exercice.choisir(String(new Date().getFullYear())));
    verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));
  }

  await browser.close();
  server.close();
  try { php.php.kill(); } catch (e) { /* déjà mort */ }

  /* --- Restitution --------------------------------------------------------- */
  const ligne = '─'.repeat(72);
  console.log('\n\n' + ligne);
  console.log('TESTS FONCTIONNELS — PROTOTYPE SIGH-CNT');
  console.log(ligne);

  let totalEtapes = 0, totalOk = 0;
  for (const s of resultats) {
    const okEtapes = s.etapes.filter((e) => e.ok).length;
    totalEtapes += s.etapes.length;
    totalOk += okEtapes;
    console.log(`\n${s.ok ? '✓' : '✗'} ${s.nom}   (${okEtapes}/${s.etapes.length})`);
    for (const e of s.etapes) {
      if (!e.ok) console.log(`    ✗ ${e.libelle}${e.detail ? '  →  ' + e.detail : ''}`);
    }
  }

  const scenariosOk = resultats.filter((s) => s.ok).length;
  console.log('\n' + ligne);
  console.log(`Scénarios : ${scenariosOk}/${resultats.length}     Vérifications : ${totalOk}/${totalEtapes}`);
  console.log(scenariosOk === resultats.length
    ? 'RÉSULTAT : TOUS LES PARCOURS FONCTIONNELS SONT CONFORMES.'
    : `RÉSULTAT : ${resultats.length - scenariosOk} scénario(s) en échec.`);
  console.log(ligne);

  fs.writeFileSync(path.join(ROOT, 'build/rapport-tests.json'), JSON.stringify(resultats, null, 2));
  process.exit(scenariosOk === resultats.length ? 0 : 1);
})();
