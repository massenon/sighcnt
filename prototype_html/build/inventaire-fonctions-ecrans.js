/* =============================================================================
 * INVENTAIRE DES FONCTIONS PAR ÉCRAN du prototype SIGH-CNT
 * -----------------------------------------------------------------------------
 * Alimente docs/architecture/AUDIT-FILTRES-CRUD-PARAMETRAGE.md (EX-11 du PRD M10).
 *
 * NORME RETENUE (PRD-M10, section 8) :
 *   filtre avancé   = recherche texte + période du/au + sélection multiple sur les
 *                     axes métier + tri + filtres enregistrables + effacement d'un
 *                     geste + report sur l'impression et l'export ;
 *   CRUD complet    = créer, consulter, modifier, archiver (jamais supprimer, RG-14),
 *                     restaurer, avec droits par commande, refus nommés et journal ;
 *   paramétrage     = toute valeur métier qui varie dans le temps est un réglage
 *                     versionné par date, jamais une constante.
 *
 * TROIS ÉTAGES, tous reproductibles :
 *   1. RELEVÉ (Chrome) : ouvre chaque page de travail sous la session admin à
 *      1440 px et lit le DOM RÉEL : tableaux U.dataTable et leurs colonnes, champ
 *      de recherche, filtres de liste (libellés), contrôles de période, listes à
 *      choix multiple, boutons d'écriture visibles (libellés), actions de ligne,
 *      impression, export, onglet « Archivés », bandeau de lecture seule. Chaque
 *      onglet de l'écran est cliqué et relevé à son tour. Les pages sont traitées
 *      PAR TRANCHES de préfixe, une instance de Chrome par tranche, le relevé est
 *      FUSIONNÉ et écrit après chaque page : un plantage ne perd rien.
 *   2. RATTACHEMENT (sans Chrome) : module et rôles du manifeste
 *      (packages/referentiels/data/manifeste.json), droits d'écriture par rôle
 *      (packages/rbac/data/rbac.json), signaux de source (K.crud, plageDates…).
 *   3. CLASSEMENT : type d'écran et verdict (conforme, ecart_mineur, ecart_reel,
 *      volontaire, non_applicable) sur les trois axes, avec la RAISON écrite.
 *      + relevé des CONSTANTES MÉTIER candidates au paramétrage (grep des sources).
 *
 * Usage :
 *   node build/inventaire-fonctions-ecrans.js                 relevé complet + classement
 *   node build/inventaire-fonctions-ecrans.js --tranches=m10-,cfg-   seules ces tranches
 *   node build/inventaire-fonctions-ecrans.js --reprendre     saute les pages déjà relevées
 *   node build/inventaire-fonctions-ecrans.js --classer       classement seul (sans Chrome)
 *   node build/inventaire-fonctions-ecrans.js --timeout=15    minutes par tranche
 *
 * Charge partagée : un seul Chrome à la fois, `nice -n 10` recommandé. Ports et
 * base PROPRES (le harnais refuse un port occupé) :
 *   SIGH_PORT=8447 SIGH_PORT_PHP=8448 SIGH_BASE_TEST=sigh_prototype_banc_inv5
 *   CHROME_PATH=/opt/pw-browsers/chromium
 * Sortie : build/mesures/inventaire-fonctions-ecrans.json (ignorée par git).
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const http = require('http');

const ROOT = path.resolve(__dirname, '..');
const DEPOT = path.resolve(ROOT, '..');
const DOSSIER = path.join(ROOT, 'build', 'mesures');
const SORTIE = path.join(DOSSIER, 'inventaire-fonctions-ecrans.json');
const MANIFESTE = path.join(DEPOT, 'packages', 'referentiels', 'data', 'manifeste.json');
const RBAC = path.join(DEPOT, 'packages', 'rbac', 'data', 'rbac.json');

const args = process.argv.slice(2);
const arg = (nom) => { const a = args.find((x) => x.startsWith('--' + nom + '=')); return a ? a.slice(nom.length + 3) : null; };
const classerSeul = args.includes('--classer');
const reprendre = args.includes('--reprendre');
const MINUTES = Number(arg('timeout')) || 15;

/* Pages SANS gabarit de travail : exclues du relevé. */
const EXCLUES = /^(index|auth-|error-|enquete-publique$|hub-)/;
/* Pages-renvoi connues (la détection DOM les recoupe). */
const RENVOIS_CONNUS = ['m1-dossier-medical', 'm1-dossier-etendu', 'm2-visites', 'm1-certificats-externes'];

/* =============================================================================
 * 1. LE RELEVÉ, exécuté DANS la page
 * ========================================================================== */
function releverDansLaPage() {
  const pc = document.getElementById('page-content');
  if (!pc) return null;
  const txt = (e) => (e ? (e.textContent || '') : '').replace(/\s+/g, ' ').trim();
  const visible = (e) => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
  const libelle = (b) => txt(b) || b.getAttribute('title') || b.getAttribute('aria-label') || '';
  const uniq = (a) => Array.from(new Set(a.filter(Boolean)));

  /* Tableaux U.dataTable : la barre d'outils porte les boutons « Colonnes » et « Exporter ». */
  const racines = [];
  Array.from(pc.querySelectorAll('button')).forEach((b) => {
    if (txt(b) === 'Colonnes') { const c = b.closest('.card'); if (c && racines.indexOf(c) < 0) racines.push(c); }
  });
  const tableaux = racines.map((c) => {
    const ths = Array.from(c.querySelectorAll('thead th')).map(txt).filter(Boolean);
    const lignes = c.querySelectorAll('tbody tr').length;
    const vide = !!c.querySelector('tbody td[colspan]') && lignes <= 1;
    const pied = txt(c.querySelector(':scope > div:last-child'));
    const m = /(\d[\d\s\u202f\u00a0]*)\s*(résultat|ligne|enregistrement|élément|fiche)/i.exec(pied) || /sur\s+(\d[\d\s\u202f\u00a0]*)/i.exec(pied);
    return {
      colonnes: ths,
      lignesAffichees: vide ? 0 : lignes,
      total: m ? Number(m[1].replace(/[\s\u202f\u00a0]/g, '')) : null,
      recherche: !!c.querySelector('input[type=search]'),
      filtres: Array.from(c.querySelectorAll('select')).map((s) => s.getAttribute('aria-label') || txt(s.options[0])),
      selectionMultiple: !!c.querySelector('thead input[type=checkbox]'),
      actionsLigne: uniq(Array.from(c.querySelectorAll('tbody button, tbody a.btn')).map((b) => b.getAttribute('title') || b.getAttribute('aria-label') || txt(b))),
      pied: pied.slice(0, 80),
    };
  });
  /* Tableaux natifs (K.miniTable, P.tableau en écran…) hors dataTable. */
  const natifs = Array.from(pc.querySelectorAll('table')).filter((t) => !racines.some((r) => r.contains(t)) && visible(t))
    .map((t) => ({ colonnes: Array.from(t.querySelectorAll('thead th')).map(txt).filter(Boolean), lignes: t.querySelectorAll('tbody tr').length }));

  /* Contrôles de période : champs date HORS formulaire, périodicités (liste ou boutons). */
  const dates = Array.from(pc.querySelectorAll('input[type=date], input[type=month], input[type=week], input[type=datetime-local]'))
    .filter((i) => visible(i))
    .map((i) => {
      const lab = (i.closest('div') && i.closest('div').querySelector('label')) ? txt(i.closest('div').querySelector('label')) : (i.getAttribute('aria-label') || i.placeholder || '');
      return { type: i.type, libelle: lab.slice(0, 40), dansFormulaire: !!i.closest('form') };
    });
  const motsPeriode = /mois|trimestre|semestre|ann[ée]e|semaine|jour|période|periode|exercice/i;
  const periodicites = [];
  Array.from(pc.querySelectorAll('select')).forEach((s) => {
    if (!visible(s)) return;
    const opts = Array.from(s.options).map(txt);
    if (opts.filter((o) => motsPeriode.test(o)).length >= 2) periodicites.push(opts.slice(0, 8).join(' | '));
  });
  Array.from(pc.querySelectorAll('.combo-value')).forEach((c) => { if (motsPeriode.test(txt(c))) periodicites.push('combo:' + txt(c)); });
  Array.from(pc.querySelectorAll('button')).forEach((b) => {
    const t = txt(b);
    if (/^(Aujourd.hui|Sept derniers jours|Ce mois|Mois|Semaine|Trimestre|Ann[ée]e|Toute la période)$/i.test(t)) periodicites.push('bouton:' + t);
  });

  /* Listes à choix (combo) hors formulaire = filtres de liste ; multiples non détectables au DOM : on relève l'attribut du panneau. */
  const combosFiltre = Array.from(pc.querySelectorAll('.combo')).filter((c) => !c.closest('form') && visible(c))
    .map((c) => txt(c.querySelector('.combo-value')).slice(0, 40));
  const selectsHorsTableau = Array.from(pc.querySelectorAll('select')).filter((s) => !racines.some((r) => r.contains(s)) && !s.closest('form') && visible(s))
    .map((s) => s.getAttribute('aria-label') || txt(s.options[0]));
  const recherchesHorsTableau = Array.from(pc.querySelectorAll('input[type=search]')).filter((i) => !racines.some((r) => r.contains(i)) && visible(i) && !i.classList.contains('combo-search')).length;

  /* Boutons d'écriture visibles (en-tête de page compris), avec leurs libellés. */
  const zone = [document.getElementById('page-actions'), pc].filter(Boolean);
  const boutons = [];
  zone.forEach((z) => Array.from(z.querySelectorAll('button, a.btn, a[role=button]')).forEach((b) => {
    if (!visible(b)) return;
    if (b.closest('tbody')) return;               /* actions de ligne comptées à part */
    if (b.classList.contains('tab')) return;
    if (b.closest('.combo')) return;
    const l = libelle(b);
    if (!l || /^\d+$/.test(l) || /^(Précédent|Suivant|‹|›|«|»)$/.test(l)) return;   /* pagination */
    boutons.push({
      l: l.slice(0, 60),
      impr: !!b.querySelector('svg.lucide-printer, svg.lucide-file-text') && /imprim|aper|état|etat|bulletin|reçu|ticket|fiche|bon/i.test(l),
      icone: (b.querySelector('svg') && (b.querySelector('svg').getAttribute('class') || '').replace(/.*lucide-([a-z0-9-]+).*/, '$1')) || '',
    });
  }));
  const onglets = Array.from(pc.querySelectorAll('[role=tab]')).map((t) => txt(t).replace(/\s*\d+$/, '').trim());
  const bandeauLectureSeule = /Lecture seule|État calculé/i.test(txt(pc.parentElement || pc));
  const formulaire = pc.querySelectorAll('form').length;
  const champs = pc.querySelectorAll('input:not([type=search]):not([type=checkbox]):not(.combo-search), textarea, select').length;
  const graphiques = pc.querySelectorAll('canvas').length;
  const kpi = pc.querySelectorAll('.kpi, [class*=kpi]').length;
  const cartes = pc.querySelectorAll('.card').length;
  return {
    tableaux, natifs, dates, periodicites: uniq(periodicites), combosFiltre, selectsHorsTableau, recherchesHorsTableau,
    boutons, onglets, bandeauLectureSeule, formulaire, champs, graphiques, kpi, cartes,
    texteLong: txt(pc).length,
    versionne: /date d.effet|en vigueur|à compter du|historique des (versions|modifications)|versionn/i.test(txt(pc)),
    renvoi: txt(pc).length < 900 && !racines.length && !natifs.length && /fusionn|déplac|renvoi|remplac[ée]/i.test(txt(pc)),
    titre: txt(document.querySelector('h1')).slice(0, 80),
  };
}

/* =============================================================================
 * Harnais : ports, base, serveur statique (même montage que check.js)
 * ========================================================================== */
const MIME = {
  '.php': 'text/html; charset=utf-8', '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.woff2': 'font/woff2', '.jpeg': 'image/jpeg',
  '.jpg': 'image/jpeg', '.png': 'image/png', '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
};
let BANC = null; let PORT = 0;
function preparerHarnais() {
  PORT = Number(process.env.SIGH_PORT) || 8447;
  process.env.SIGH_PORT_PHP = process.env.SIGH_PORT_PHP || '8448';
  let nom = process.env.SIGH_BASE_TEST || 'sigh_prototype_banc_inv5';
  if (!/(test|essai|banc)/i.test(nom)) nom += '_test';
  process.env.SIGH_BASE_TEST = nom;
  BANC = require('./_banc');
}
function servir() {
  return new Promise((resolve) => {
    const s = http.createServer((req, res) => {
      if (req.url.indexOf('/api/') === 0) { BANC.relayer(req, res); return; }
      const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '') || 'index.php';
      const f = path.join(ROOT, rel);
      if (!f.startsWith(ROOT) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); res.end('404'); return; }
      res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' });
      fs.createReadStream(f).pipe(res);
    });
    s.listen(PORT, () => resolve(s));
  });
}
function navigateurInstalle() {
  return [process.env.CHROME_PATH, '/opt/pw-browsers/chromium', 'C:/Program Files/Google/Chrome/Application/chrome.exe']
    .filter(Boolean).find((c) => fs.existsSync(c)) || null;
}
function listerPages() {
  return fs.readdirSync(path.join(ROOT, 'pages')).filter((f) => f.endsWith('.php')).map((f) => f.replace(/\.php$/, ''))
    .filter((id) => !EXCLUES.test(id)).sort();
}
/* Tranche = préfixe jusqu'au premier tiret (m10, cfg, dash…) ; un préfixe lourd est scindé en deux. */
function tranchesDe(pages) {
  const g = {};
  pages.forEach((id) => { const p = id.split('-')[0] + '-'; (g[p] = g[p] || []).push(id); });
  const sortie = [];
  Object.keys(g).sort().forEach((p) => {
    const l = g[p];
    if (l.length > 45) { const h = Math.ceil(l.length / 2); sortie.push({ nom: p + ' (1/2)', pages: l.slice(0, h) }, { nom: p + ' (2/2)', pages: l.slice(h) }); }
    else sortie.push({ nom: p, pages: l });
  });
  return sortie;
}

function lireSortie() {
  try { return JSON.parse(fs.readFileSync(SORTIE, 'utf8')); } catch (e) { return null; }
}
function ecrireSortie(o) { fs.mkdirSync(DOSSIER, { recursive: true }); fs.writeFileSync(SORTIE, JSON.stringify(o)); }

async function releverPage(navigateur, id) {
  const page = await navigateur.newPage();
  const sortie = { page: id, ok: false, redirigee: null, erreur: null, ms: 0, defaut: null, parOnglet: {} };
  const t0 = Date.now();
  try {
    await page.setViewport({ width: 1440, height: 900, deviceScaleFactor: 1 });
    await BANC.poserSession(page);
    page.setDefaultNavigationTimeout(120000); page.setDefaultTimeout(60000);
    await page.goto(`http://127.0.0.1:${PORT}/pages/${id}.php`, { waitUntil: 'domcontentloaded', timeout: 120000 });
    await page.waitForFunction((attendu) => {
      if (!location.pathname.includes('/' + attendu + '.')) return true;
      const c = document.getElementById('page-content');
      return !!(window.SIGH && window.SIGH.store && c && c.children.length > 0);
    }, { timeout: 90000 }, id).catch(() => null);
    await new Promise((r) => setTimeout(r, 500));
    const final = page.url().split('?')[0].split('#')[0].replace(/^.*\//, '').replace(/\.php$/, '');
    if (final !== id) { sortie.redirigee = final; return sortie; }
    sortie.defaut = await page.evaluate(releverDansLaPage);
    if (!sortie.defaut) { sortie.erreur = 'page non peinte'; return sortie; }
    sortie.ok = true;
    /* Chaque onglet est cliqué et relevé (jusqu'à 12). */
    const nb = Math.min(sortie.defaut.onglets.length, 12);
    for (let i = 0; i < nb; i++) {
      try {
        await page.evaluate((k) => { const t = document.querySelectorAll('#page-content [role=tab]')[k]; if (t) t.click(); }, i);
        await new Promise((r) => setTimeout(r, 350));
        const r = await page.evaluate(releverDansLaPage);
        if (r) sortie.parOnglet[sortie.defaut.onglets[i]] = r;
      } catch (e) { /* un onglet qui plante ne perd pas la page */ }
    }
  } catch (e) { sortie.erreur = String(e.message || e).slice(0, 200); }
  sortie.ms = Date.now() - t0;
  await page.close().catch(() => null);
  return sortie;
}

async function releve() {
  preparerHarnais();
  const puppeteer = require('puppeteer');
  const exe = navigateurInstalle();
  if (!exe) { console.error('Aucun navigateur. Définir CHROME_PATH.'); process.exit(2); }
  let pages = listerPages();
  const t = arg('tranches');
  if (t) { const v = t.split(',').map((s) => s.trim()); pages = pages.filter((id) => v.some((p) => id.startsWith(p))); }
  const p = arg('pages');
  if (p) { const v = p.split(',').map((s) => s.trim()); pages = pages.filter((id) => v.includes(id)); }

  let sortie = lireSortie() || { genereLe: null, pages: {} };
  if (!reprendre && !t && !p) sortie = { genereLe: null, pages: {} };
  if (reprendre) pages = pages.filter((id) => !(sortie.pages[id] && sortie.pages[id].ok));

  const php = await BANC.demarrerPhp(ROOT);
  if (!php.php) { console.error('ÉCHEC : ' + php.raison); process.exit(1); }
  const vidage = await BANC.banc('reinitialiser');
  if (vidage.erreur) { console.error('ÉCHEC base du banc : ' + (vidage.detail || vidage.erreur)); try { php.php.kill(); } catch (e) { /* mort */ } process.exit(1); }
  console.log(`  Banc : base « ${vidage.base} » remise à neuf ; Node ${PORT}, PHP ${process.env.SIGH_PORT_PHP}. ${pages.length} pages.`);
  const serveur = await servir();

  for (const tr of tranchesDe(pages)) {
    const debut = Date.now();
    let navigateur = null;
    try {
      navigateur = await puppeteer.launch({ executablePath: exe, headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu', '--hide-scrollbars'] });
      let n = 0;
      for (const id of tr.pages) {
        if (Date.now() - debut > MINUTES * 60000) { console.log(`  [${tr.nom}] délai de ${MINUTES} min atteint : reprise par --reprendre.`); break; }
        let r;
        try { r = await releverPage(navigateur, id); } catch (e) { r = { page: id, ok: false, erreur: String(e.message || e).slice(0, 200) }; }
        sortie.pages[id] = r; n++;
        sortie.genereLe = new Date().toISOString();
        ecrireSortie(sortie);                        /* écriture après CHAQUE page : un plantage ne perd rien */
        console.log(`  ${tr.nom.padEnd(12)} ${String(n).padStart(3)}/${tr.pages.length} ${id.padEnd(40)} ${String(r.ms || 0).padStart(6)} ms ${r.ok ? 'ok' : (r.redirigee ? 'redirigée vers ' + r.redirigee : 'ECHEC ' + r.erreur)}`);
      }
    } catch (e) { console.log(`  [${tr.nom}] Chrome a planté : ${String(e.message || e).slice(0, 120)} (relevé conservé)`); }
    try { if (navigateur) await navigateur.close(); } catch (e) { /* déjà mort */ }
  }
  serveur.close();
  try { php.php.kill(); } catch (e) { /* mort */ }
}

/* =============================================================================
 * 2 et 3. RATTACHEMENT, CLASSEMENT, CONSTANTES CANDIDATES
 * ========================================================================== */
const RE = {
  creer: /^(nouveau|nouvelle|ajouter|cr[ée]er|ouvrir (un|une)|[ée]mettre|saisir|d[ée]clarer|enregistrer (un|une)|planifier|programmer|prescrire|admettre|[ée]tablir|g[ée]n[ée]rer|encaisser|d[ée]livrer|affecter|inscrire|consigner|poser|lancer|importer)/i,
  modifier: /^(modifier|corriger|renommer|[ée]diter la fiche|param[ée]trer|mettre [àa] jour|r[ée]gler)/i,
  archiver: /archiver|^retirer|d[ée]sactiver|mettre au rebut|^annuler/i,
  restaurer: /restaurer|r[ée]activer|rouvrir/i,
  valider: /valider|approuver|signer|arbitrer|accorder|certifier|cl[ôo]turer|rendre|transmettre/i,
  importer: /import/i,
  imprimer: /imprimer|aper[çc]u|[ée]diter l.[ée]tat|^[ée]tat |bulletin|re[çc]u|ticket|[ée]diter le|planche/i,
  exporter: /export|csv|excel|pdf/i,
};
function charger(f) { return JSON.parse(fs.readFileSync(f, 'utf8')); }

function sourcesParEcran() {
  const dir = path.join(ROOT, 'assets', 'js', 'modules');
  const blocs = {}; const fichierDe = {};
  fs.readdirSync(dir).filter((f) => f.endsWith('.js')).forEach((f) => {
    const s = fs.readFileSync(path.join(dir, f), 'utf8');
    const re = /SIGH\.screen\(\s*'([^']+)'\s*,/g; let m; const pos = [];
    while ((m = re.exec(s))) pos.push({ id: m[1], i: m.index });
    pos.forEach((p, k) => { blocs[p.id] = s.slice(p.i, k + 1 < pos.length ? pos[k + 1].i : Math.min(s.length, p.i + 40000)); fichierDe[p.id] = f; });
  });
  return { blocs, fichierDe };
}
function signauxSource(b) {
  if (!b) return null;
  return {
    crud: /\b(K|kit)\.(crud|registre)\(/.test(b), creer: /\bK\.creer\(/.test(b), actionsLigne: /\bK\.actionsLigne\(/.test(b),
    plageDates: /plageDates\s*:/.test(b), filtresDeclares: (b.match(/filters\s*:\s*\[/g) || []).length,
    archivage: /archiv/i.test(b), restauration: /restaur/i.test(b),
    lectureSeule: /lectureSeule\s*:\s*true|K\.lectureSeule\(/.test(b), dash: /\bK\.dash\(/.test(b),
    pageFormulaire: /K\.pageFormulaire\(/.test(b), fileAttente: /K\.fileAttente\(/.test(b),
    versionneDate: /(dateEffet|dateDebut|debut\s*:|historique[A-Z]|entreeEnVigueur|versionn)/.test(b),
    searchableFalse: /searchable\s*:\s*false/.test(b),
  };
}

function typeEcran(id, r, ent, src) {
  const d = r.defaut;
  if (RENVOIS_CONNUS.includes(id) || d.renvoi) return 'renvoi';
  if (/^dash-/.test(id)) return 'tableau_de_bord';
  const unionTab = unionner(r);
  if (/^(cfg-|m14-)/.test(id) || (ent && /^(CFG|M14)$/.test(ent.module))) return 'configuration';
  if (/stats|statistique|rentabilite|tableau-decisionnel|cout-|bfr|comparatif|indicateurs|satisfaction/.test(id) || (ent && ent.module === 'PIL')) return 'statistique';
  if (unionTab.tableaux.length) return 'registre';
  if (d.formulaire || d.champs >= 4) return 'formulaire';
  if (d.graphiques || d.kpi) return 'tableau_de_bord';
  if (unionTab.natifs.length) return 'etat_calcule';
  return 'outil';
}

/* Union de ce que l'écran offre sur TOUS ses onglets (défaut compris). */
function unionner(r) {
  const vues = [r.defaut].concat(Object.keys(r.parOnglet || {}).map((k) => r.parOnglet[k])).filter(Boolean);
  const u = { tableaux: [], natifs: [], dates: [], periodicites: [], boutons: [], onglets: r.defaut.onglets, combosFiltre: [], selectsHorsTableau: [], recherchesHorsTableau: 0, bandeauLectureSeule: false, versionne: false };
  const vuTab = new Set();
  vues.forEach((v) => {
    v.tableaux.forEach((t) => { const k = t.colonnes.join('|'); if (!vuTab.has(k)) { vuTab.add(k); u.tableaux.push(t); } });
    v.natifs.forEach((t) => u.natifs.push(t));
    v.dates.forEach((x) => u.dates.push(x));
    u.periodicites.push(...v.periodicites);
    v.boutons.forEach((b) => { if (!u.boutons.some((x) => x.l === b.l)) u.boutons.push(b); });
    u.combosFiltre.push(...v.combosFiltre); u.selectsHorsTableau.push(...v.selectsHorsTableau);
    u.recherchesHorsTableau = Math.max(u.recherchesHorsTableau, v.recherchesHorsTableau);
    u.bandeauLectureSeule = u.bandeauLectureSeule || v.bandeauLectureSeule;
    u.versionne = u.versionne || v.versionne;
  });
  u.dates = u.dates.filter((x, i, a) => a.findIndex((y) => y.libelle === x.libelle && y.dansFormulaire === x.dansFormulaire) === i);
  u.periodicites = Array.from(new Set(u.periodicites));
  return u;
}

const COL_DATEE = /(^|\s)(date|du|au|le|heure|échéance|echeance|émis|émission|début|fin|admission|entrée|sortie|naissance|arrivée|rdv|prise|validité|expiration|péremption|période|mois|jour)(\s|$)|date/i;

function classer(id, r, ent, droitsEcran, src) {
  const type = typeEcran(id, r, ent, src);
  const u = unionner(r);
  const lib = u.boutons.map((b) => b.l);
  const actionsLigne = Array.from(new Set([].concat(...u.tableaux.map((t) => t.actionsLigne))));
  const tous = lib.concat(actionsLigne);
  const a = {
    creer: tous.some((l) => RE.creer.test(l)) && !/^importer/i.test(tous.find((l) => RE.creer.test(l)) || ''),
    modifier: tous.some((l) => RE.modifier.test(l)),
    archiver: tous.some((l) => RE.archiver.test(l)) || (src && src.archivage && src.crud),
    restaurer: u.onglets.some((o) => /^Archiv/i.test(o)) || tous.some((l) => RE.restaurer.test(l)),
    valider: tous.some((l) => RE.valider.test(l)),
    importer: tous.some((l) => RE.importer.test(l)),
    imprimer: u.boutons.some((b) => b.impr || RE.imprimer.test(b.l)) || u.tableaux.length > 0,
    exporter: u.tableaux.length > 0 || lib.some((l) => RE.exporter.test(l)),
    consulter: u.tableaux.some((t) => t.actionsLigne.some((x) => /consulter|voir|détail|ouvrir/i.test(x))) || (src && src.crud),
  };
  const nbDT = u.tableaux.length;
  const colonnes = [].concat(...u.tableaux.map((t) => t.colonnes));
  const totalLignes = u.tableaux.reduce((m, t) => Math.max(m, t.total != null ? t.total : t.lignesAffichees), 0);
  const filtres = Array.from(new Set([].concat(...u.tableaux.map((t) => t.filtres)).concat(u.selectsHorsTableau).concat(u.combosFiltre)));
  const dateFiltre = u.dates.filter((d) => !d.dansFormulaire);
  const periode = dateFiltre.length >= 1 || u.periodicites.length > 0 || !!(src && src.plageDates);
  const recherche = u.tableaux.some((t) => t.recherche) || u.recherchesHorsTableau > 0;
  const datee = colonnes.some((c) => COL_DATEE.test(c));
  /* Droits : qui ÉCRIT cet écran (rbac.json : [voir, éditer, annuler]). */
  const ecrivains = droitsEcran.ecrivains;
  const lectureSeuleVolontaire = u.bandeauLectureSeule && /^[ée]tat calcul[ée]/i.test('') ? true : !!(src && src.lectureSeule);
  const aucunEcrivain = droitsEcran.connu && ecrivains.length === 0;

  const raisons = { filtre: [], crud: [], parametrage: [] };
  const verdict = { filtre: 'non_applicable', crud: 'non_applicable', parametrage: 'non_applicable' };
  const mesure = { type, nbTableaux: nbDT, totalLignes, colonnes: colonnes.length, recherche, filtres, periode, datee, actions: a, ecrivains: ecrivains.length };

  /* ----- FILTRE AVANCÉ ----- */
  if (type === 'registre') {
    const manque = [];
    if (!recherche) manque.push('recherche');
    if (!filtres.length && colonnes.length >= 5) manque.push('filtre métier');
    if (datee && !periode) manque.push('période du/au');
    if (!manque.length) verdict.filtre = 'conforme';
    else if (totalLignes > 0 && totalLignes <= 12 && !manque.includes('recherche')) { verdict.filtre = 'ecart_mineur'; raisons.filtre.push('moins de 13 lignes au jeu : ' + manque.join(', ')); }
    else if (manque.includes('recherche') || manque.length >= 2 || (manque.includes('période du/au') && (totalLignes > 30 || totalLignes === 0))) { verdict.filtre = 'ecart_reel'; raisons.filtre.push('manque : ' + manque.join(', ') + ' (' + totalLignes + ' lignes au jeu)'); }
    else { verdict.filtre = 'ecart_mineur'; raisons.filtre.push('manque : ' + manque.join(', ') + ' (' + totalLignes + ' lignes au jeu)'); }
  } else if (type === 'tableau_de_bord' || type === 'statistique') {
    if (periode) verdict.filtre = 'conforme';
    else { verdict.filtre = type === 'statistique' ? 'ecart_reel' : 'ecart_mineur'; raisons.filtre.push('aucun contrôle de période relevé'); }
  } else if (type === 'configuration' && nbDT) {
    verdict.filtre = recherche || totalLignes <= 12 ? 'conforme' : 'ecart_mineur';
  }

  /* ----- CRUD ----- */
  if (type === 'registre' || type === 'configuration') {
    if (!nbDT) { verdict.crud = 'non_applicable'; }
    else if (aucunEcrivain || u.bandeauLectureSeule && !a.creer && !a.modifier || (src && src.lectureSeule)) {
      verdict.crud = 'volontaire'; raisons.crud.push(aucunEcrivain ? 'aucun rôle n\'écrit cet écran (rbac.json)' : 'lecture seule déclarée');
    } else {
      const manque = [];
      if (!a.creer) manque.push('créer');
      if (!a.modifier) manque.push('modifier');
      if (!a.archiver) manque.push('archiver');
      if (!a.restaurer) manque.push('restaurer');
      if (!manque.length) verdict.crud = 'conforme';
      else if (manque.length === 4) { verdict.crud = (src && src.lectureSeule) || totalLignes === 0 ? 'ecart_mineur' : 'ecart_reel'; raisons.crud.push('aucune commande d\'écriture visible au rôle admin'); }
      else if (manque.length === 1 && manque[0] === 'restaurer') { verdict.crud = 'ecart_mineur'; raisons.crud.push('archivage présent, restauration seulement par la Corbeille de cfg-systeme (RG-14 tenu)'); }
      else { verdict.crud = manque.length >= 2 || manque.includes('archiver') ? 'ecart_reel' : 'ecart_mineur'; raisons.crud.push('manque : ' + manque.join(', ')); }
    }
  } else if (type === 'formulaire') {
    verdict.crud = 'non_applicable';
  }

  /* ----- PARAMÉTRAGE : l'écran de configuration pèse-t-il sur des pièces émises, est-il versionné ? ----- */
  if (type === 'configuration') {
    const versionne = u.versionne || (src && src.versionneDate);
    verdict.parametrage = versionne ? 'conforme' : 'a_examiner';
    raisons.parametrage.push(versionne ? 'indices de versionnement par date relevés' : 'aucun indice de versionnement par date : à relire (voir §5)');
  }
  return { type, verdict, raisons, mesure };
}

/* Constantes métier candidates : les littéraux qui ressemblent à une règle (durée, seuil, taux, plafond, délai). */
function constantesCandidates() {
  const dir = path.join(ROOT, 'assets', 'js');
  const fichiers = fs.readdirSync(dir).filter((f) => /^(data.*|parcours|store|core|notifications)\.js$/.test(f)).map((f) => path.join(dir, f))
    .concat(fs.readdirSync(path.join(dir, 'modules')).filter((f) => f.endsWith('.js') && f !== 'mere.js').map((f) => path.join(dir, 'modules', f)));
  const motifs = [
    { k: 'durée/délai', re: /\b(var|const|let)\s+([A-Z][A-Z0-9_]*(?:DUREE|DELAI|JOURS|HEURES|MINUTES|MOIS|VALIDITE|PREAVIS|ANCIENNETE)[A-Z0-9_]*)\s*=\s*([^;]{1,80})/ },
    { k: 'seuil/plafond', re: /\b(var|const|let)\s+([A-Z][A-Z0-9_]*(?:SEUIL|PLAFOND|LIMITE|MAX|MIN|BORNE|TOLERANCE)[A-Z0-9_]*)\s*=\s*([^;]{1,80})/ },
    { k: 'taux', re: /\b(var|const|let)\s+([A-Z][A-Z0-9_]*(?:TAUX|PCT|POURCENT|COEF|RATIO|BAREME|COTISATION)[A-Z0-9_]*)\s*=\s*([^;]{1,80})/ },
    { k: 'littéral nommé', re: /\b(var|const|let)\s+([A-Z][A-Z0-9_]{3,})\s*=\s*(\d[\d_.,]*|\[[^\]]{0,80}\])\s*;/ },
    { k: 'taux littéral', re: /(0[.,]1[0-9]+|0[.,]0[0-9]+)\s*\*|\*\s*(0[.,]\d{2,3})\b/ },
  ];
  const sortie = []; const vus = new Set();
  fichiers.forEach((f) => {
    const lignes = fs.readFileSync(f, 'utf8').split('\n');
    lignes.forEach((ligne, i) => {
      if (/^\s*(\/\/|\*|\/\*)/.test(ligne)) return;
      motifs.forEach((m) => {
        const x = m.re.exec(ligne); if (!x) return;
        const cle = path.basename(f) + ':' + (x[2] || x[0]);
        if (vus.has(cle)) return; vus.add(cle);
        sortie.push({ fichier: path.relative(ROOT, f).replace(/\\/g, '/'), ligne: i + 1, genre: m.k, nom: x[2] || null, extrait: ligne.trim().slice(0, 140) });
      });
    });
  });
  return sortie;
}

function classement() {
  const brut = lireSortie();
  if (!brut) { console.error('Aucun relevé : lancer sans --classer.'); process.exit(1); }
  const man = charger(MANIFESTE); const rbac = charger(RBAC);
  const parId = {}; man.ecrans.forEach((e) => { parId[e.id] = e; });
  const { blocs, fichierDe } = sourcesParEcran();
  const ecrans = []; const synthese = { types: {}, filtre: {}, crud: {}, parametrage: {}, parModule: {} };
  Object.keys(brut.pages).sort().forEach((id) => {
    const r = brut.pages[id];
    const ent = parId[id] || null;
    const ecr = [];
    Object.keys(rbac.parRole).forEach((role) => { const d = rbac.parRole[role][id]; if (d && d[1]) ecr.push(role); });
    const connu = Object.keys(rbac.parRole).some((role) => rbac.parRole[role][id]);
    const droits = { ecrivains: ecr, connu, voyeurs: Object.keys(rbac.parRole).filter((role) => rbac.parRole[role][id] && rbac.parRole[role][id][0]).length };
    const src = signauxSource(blocs[id]);
    const ligne = { id, module: ent ? ent.module : null, domaine: ent ? ent.domaine : null, titre: r.defaut ? r.defaut.titre : null, ok: !!r.ok, redirigee: r.redirigee || null, erreur: r.erreur || null,
      rolesManifeste: ent ? ent.roles : null, rolesQuiEcrivent: ecr, fichierSource: fichierDe[id] || null, source: src };
    if (r.ok) {
      const c = classer(id, r, ent, droits, src);
      const u = unionner(r);
      Object.assign(ligne, { type: c.type, verdict: c.verdict, raisons: c.raisons, mesure: c.mesure,
        releve: { onglets: u.onglets, boutons: u.boutons.map((b) => b.l), periodicites: u.periodicites, dates: u.dates, bandeauLectureSeule: u.bandeauLectureSeule,
          tableaux: u.tableaux.map((t) => ({ colonnes: t.colonnes, lignes: t.total != null ? t.total : t.lignesAffichees, recherche: t.recherche, filtres: t.filtres, selectionMultiple: t.selectionMultiple, actionsLigne: t.actionsLigne })) } });
      synthese.types[c.type] = (synthese.types[c.type] || 0) + 1;
      ['filtre', 'crud', 'parametrage'].forEach((ax) => { synthese[ax][c.verdict[ax]] = (synthese[ax][c.verdict[ax]] || 0) + 1; });
      const mod = ligne.module || '?'; synthese.parModule[mod] = synthese.parModule[mod] || { ecrans: 0, filtre_reel: 0, crud_reel: 0 };
      synthese.parModule[mod].ecrans++;
      if (c.verdict.filtre === 'ecart_reel') synthese.parModule[mod].filtre_reel++;
      if (c.verdict.crud === 'ecart_reel') synthese.parModule[mod].crud_reel++;
    }
    ecrans.push(ligne);
  });
  /* Les écrans du manifeste sans relevé (exclus ou non peints) : listés pour que le total se recoupe. */
  const manquants = man.ecrans.filter((e) => !brut.pages[e.id] && !EXCLUES.test(e.id) && !e.alias).map((e) => e.id);
  const globaux = {
    /* Mécanismes absents du socle (relevés dans ui.js et _kit.js, voir le document §4). */
    filtreMultipleListe: 0, filtresEnregistrables: 0, effacerEnUnGeste: 0,
  };
  const out = { genereLe: brut.genereLe, classeLe: new Date().toISOString(), norme: 'PRD-M10 section 8', synthese, globaux, manquantsDuReleve: manquants, constantes: constantesCandidates(), ecrans };
  /* Le relevé brut est conservé dans la sortie : le classement se refait sans Chrome. */
  out.pages = brut.pages;
  ecrireSortie(out);
  console.log('Classement écrit : ' + path.relative(ROOT, SORTIE));
  console.log(JSON.stringify(synthese, null, 1));
}

(async () => {
  if (!classerSeul) await releve();
  classement();
})().catch((e) => { console.error(e); process.exit(1); });
