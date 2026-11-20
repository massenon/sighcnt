/* =============================================================================
 * MESURE DE LA MISE EN PAGE du prototype SIGH-CNT
 * -----------------------------------------------------------------------------
 * Ouvre CHAQUE page engendrée (pages/*.php, la liste même de check.js) dans
 * Chrome, à 1440 px puis à 400 px de large, attend la peinture de
 * `#page-content` et RELÈVE, sans juger :
 *
 *   - la largeur du contenu et tout débordement horizontal (page et contenu) ;
 *   - l'ordre des blocs du gabarit présents (en-tête, grille KPI, carte,
 *     tableau, formulaire, bandeau de lecture seule) et leur position (top) ;
 *   - pour chaque .card : padding des quatre côtés (carte, en-tête, corps),
 *     rayon, bordure, écart vertical réel avec le bloc frère précédent ;
 *   - pour chaque grille KPI : classes grid-cols-* et colonnes EFFECTIVES
 *     (getComputedStyle gridTemplateColumns) ;
 *   - pour chaque formulaire U.form : colonnes effectives et col-span employés ;
 *   - pour chaque tableau : largeur, débordement, police des cellules ;
 *   - les tailles de police sous 14,67 px (11 pt) sur des éléments VISIBLES,
 *     hors feuilles d'impression (#print-root, .print-only) ;
 *   - les largeurs et hauteurs écrites en style en ligne ;
 *   - les éléments qui dépassent #page-content à droite ;
 *   - une capture PNG (deviceScaleFactor 1) par page et par largeur.
 *
 * LA NORME N'EST PAS INVENTÉE : le résumé (`mise-en-page-resume.json`) donne,
 * métrique par métrique, la valeur DOMINANTE mesurée, sa fréquence et les
 * pages qui s'en écartent. Les écrans autonomes (auth-*, error-*,
 * enquete-publique, index) sont ouverts et capturés mais ne participent pas
 * aux normes : ils n'ont pas de gabarit de page de travail.
 *
 * Sorties (dossier build/mesures/, ignoré par git sauf le résumé) :
 *   build/mesures/mise-en-page.json          relevé complet (volumineux)
 *   build/mesures/mise-en-page-resume.json   résumé statistique (commité)
 *   build/mesures/mise-en-page/<page>@<largeur>.png
 *
 * Usage :
 *   node build/mesure-mise-en-page.js [--pages=m1-,m8-] [--largeurs=1440,400]
 *                                     [--resume-seulement] [--sans-captures]
 *
 * Charge partagée : un seul Chrome, pages en séquence. Ports et base propres :
 *   SIGH_PORT (Node, défaut 8441), SIGH_PORT_PHP (défaut 8442),
 *   SIGH_BASE_TEST (défaut sigh_prototype_mep_test ; `api/banc.php` exige que
 *   le nom porte « test », « essai » ou « banc », le script complète sinon).
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const http = require('http');
const puppeteer = require('puppeteer');

const ROOT = path.resolve(__dirname, '..');
const DOSSIER = path.join(ROOT, 'build', 'mesures');
const DOSSIER_CAPTURES = path.join(DOSSIER, 'mise-en-page');
const FICHIER_MESURES = path.join(DOSSIER, 'mise-en-page.json');
const FICHIER_RESUME = path.join(DOSSIER, 'mise-en-page-resume.json');

/* Ports et base PROPRES à cette mesure : un autre chantier peut faire tourner
   ses bancs sur 8099 et sigh_prototype_test au même moment. Posés AVANT le
   chargement de _banc.js, qui lit l'environnement au chargement. */
const PORT = Number(process.env.SIGH_PORT) || 8441;
process.env.SIGH_PORT_PHP = process.env.SIGH_PORT_PHP || '8442';
(function baseDuBanc() {
  var nom = process.env.SIGH_BASE_TEST || 'sigh_prototype_mep_test';
  if (!/(test|essai|banc)/i.test(nom)) nom += '_test';
  process.env.SIGH_BASE_TEST = nom;
})();
const BANC = require('./_banc');

/* 11 pt à 96 dpi : la taille minimale à l'écran demandée par le CDCT. */
const SEUIL_POLICE_PX = 11 * 96 / 72; /* 14.666… */
const HAUTEUR_CAPTURE_MAX = 2400;

/* --- Localisation d'un navigateur installé (même liste que check.js) ------ */
function trouverNavigateur() {
  const candidats = [
    process.env.CHROME_PATH,
    '/opt/pw-browsers/chromium',
    'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
    'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
  ].filter(Boolean);
  for (const c of candidats) if (fs.existsSync(c)) return c;
  return null;
}

/* --- Serveur statique minimal (copie de check.js : Node sert les fichiers,
       PHP ne reçoit que /api/) ---------------------------------------------- */
const MIME = {
  '.php': 'text/html; charset=utf-8',
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json',
  '.woff2': 'font/woff2', '.jpeg': 'image/jpeg', '.jpg': 'image/jpeg',
  '.png': 'image/png', '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
};
function servir() {
  return new Promise((resolve) => {
    const serveur = http.createServer((req, res) => {
      if (req.url.indexOf('/api/') === 0) { BANC.relayer(req, res); return; }
      const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '') || 'index.php';
      const fichier = path.join(ROOT, rel);
      if (!fichier.startsWith(ROOT) || !fs.existsSync(fichier) || fs.statSync(fichier).isDirectory()) {
        res.writeHead(404, { 'Content-Type': 'text/plain' }); res.end('404'); return;
      }
      res.writeHead(200, { 'Content-Type': MIME[path.extname(fichier)] || 'application/octet-stream' });
      fs.createReadStream(fichier).pipe(res);
    });
    serveur.listen(PORT, () => resolve(serveur));
  });
}

/* --- Inventaire des pages (la liste de check.js) --------------------------- */
function listerPages() {
  const pages = ['index.php'];
  for (const f of fs.readdirSync(path.join(ROOT, 'pages'))) {
    if (f.endsWith('.php')) pages.push('pages/' + f);
  }
  return pages;
}
function idDePage(rel) { return path.basename(rel, '.php'); }
/* Les écrans sans coquille : pas de gabarit de page de travail à comparer. */
function estAutonome(id) { return /^(auth-|error-|enquete-publique$|index$)/.test(id); }

/* =============================================================================
 * LE RELEVÉ, exécuté DANS la page
 * -----------------------------------------------------------------------------
 * Tout ce qui suit tourne dans le navigateur. Il ne juge rien : il mesure ce
 * que Chrome a réellement peint, et le rend en JSON sérialisable.
 * ========================================================================== */
function releverDansLaPage(seuilPolice) {
  const doc = document;
  const racine = doc.documentElement;
  const pc = doc.getElementById('page-content');
  const arrondi = (v) => Math.round(v * 100) / 100;
  const nombre = (s) => { const n = parseFloat(s); return isNaN(n) ? null : arrondi(n); };

  function visible(e) {
    if (!e || !(e instanceof Element)) return false;
    const t = e.tagName;
    if (t === 'SCRIPT' || t === 'STYLE' || t === 'NOSCRIPT' || t === 'OPTION' || t === 'TEMPLATE') return false;
    const r = e.getBoundingClientRect();
    if (r.width <= 0 && r.height <= 0) return false;
    const cs = getComputedStyle(e);
    if (cs.visibility === 'hidden' || cs.display === 'none' || cs.opacity === '0') return false;
    return true;
  }
  /* Une feuille d'impression affichée à l'écran n'est pas une page de travail. */
  function horsImpression(e) { return !e.closest('#print-root, .print-only, .print-chrome'); }
  function dansContenu(e) { return !!(pc && pc.contains(e)); }
  function classesDe(e) { return (e.getAttribute('class') || '').trim().replace(/\s+/g, ' '); }
  function signature(e) {
    const cl = classesDe(e);
    return e.tagName.toLowerCase() + (e.id ? '#' + e.id : '') + (cl ? '.' + cl.split(' ').slice(0, 5).join('.') : '');
  }
  function texteCourt(e, n) {
    const t = (e.textContent || '').replace(/\s+/g, ' ').trim();
    return t.length > (n || 60) ? t.slice(0, n || 60) + '…' : t;
  }
  function padding(cs) {
    return { haut: nombre(cs.paddingTop), droite: nombre(cs.paddingRight), bas: nombre(cs.paddingBottom), gauche: nombre(cs.paddingLeft) };
  }
  function rayon(cs) {
    const v = [cs.borderTopLeftRadius, cs.borderTopRightRadius, cs.borderBottomRightRadius, cs.borderBottomLeftRadius].map(nombre);
    return v.every((x) => x === v[0]) ? v[0] : v;
  }
  function bordure(cs) {
    return { largeur: nombre(cs.borderTopWidth), style: cs.borderTopStyle, couleur: cs.borderTopColor };
  }
  function colonnesEffectives(cs) {
    const g = cs.gridTemplateColumns || '';
    if (!g || g === 'none') return null;
    return g.trim().split(/\s+/).filter((x) => x && x !== '/').length;
  }
  function espacementParent(e) {
    const p = e.parentElement; if (!p) return null;
    const cs = getComputedStyle(p);
    return { classes: classesDe(p).split(' ').filter((c) => /^(space-y-|gap-|grid|flex|lg:|sm:|md:)/.test(c)).join(' '),
      gapLigne: nombre(cs.rowGap), affichage: cs.display };
  }

  const fenetre = { largeur: window.innerWidth, hauteur: window.innerHeight };
  const document_ = {
    largeurClient: racine.clientWidth,
    largeurDefilement: racine.scrollWidth,
    hauteurDefilement: racine.scrollHeight,
    debordementHorizontal: racine.scrollWidth > racine.clientWidth,
  };

  const res = { fenetre: fenetre, document: document_, contenu: null, blocs: null, ordre: null,
    cartes: [], kpiGrilles: [], formulaires: [], tableaux: [], polices: null, stylesEnLigne: null,
    depassementsDroite: null, texteSansCoquille: false };

  /* ---- Les polices et les styles en ligne se relèvent sur TOUT ce qui est
          visible, coquille comprise : un texte trop petit dans le ruban est
          aussi illisible qu'un texte trop petit dans une carte. ------------- */
  const tous = Array.from(doc.body.querySelectorAll('*'));
  const parTaille = {}, parTailleContenu = {}, exemplesParTaille = {};
  let totalTexte = 0, sousSeuil = 0, sousSeuilContenu = 0, minimum = null, minimumContenu = null;
  for (const e of tous) {
    if (!visible(e) || !horsImpression(e)) continue;
    /* Un élément porte du texte s'il a un nœud texte DIRECT non vide : la
       taille de police d'un conteneur sans texte propre ne se lit nulle part. */
    let porteTexte = false;
    for (const n of e.childNodes) { if (n.nodeType === 3 && n.textContent.trim()) { porteTexte = true; break; } }
    if (!porteTexte) continue;
    totalTexte++;
    const taille = parseFloat(getComputedStyle(e).fontSize);
    const contenu = dansContenu(e);
    if (minimum === null || taille < minimum) minimum = taille;
    if (contenu && (minimumContenu === null || taille < minimumContenu)) minimumContenu = taille;
    if (taille < seuilPolice - 0.001) {
      sousSeuil++;
      const cle = String(arrondi(taille));
      parTaille[cle] = (parTaille[cle] || 0) + 1;
      if (contenu) { sousSeuilContenu++; parTailleContenu[cle] = (parTailleContenu[cle] || 0) + 1; }
      /* Trois exemples par taille, signatures distinctes : les plus petites
         polices sont celles qu'on veut voir, pas les premières du DOM. */
      const liste = exemplesParTaille[cle] = exemplesParTaille[cle] || [];
      if (liste.length < 3 && !liste.some((x) => x.signature === signature(e))) {
        liste.push({ signature: signature(e), texte: texteCourt(e, 50), dansContenu: contenu });
      }
    }
  }
  res.polices = { seuil: arrondi(seuilPolice), elementsTexte: totalTexte, sousSeuil: sousSeuil,
    sousSeuilDansContenu: sousSeuilContenu,
    minimum: minimum === null ? null : arrondi(minimum),
    minimumContenu: minimumContenu === null ? null : arrondi(minimumContenu),
    parTaille: parTaille, parTailleContenu: parTailleContenu, exemplesParTaille: exemplesParTaille };

  const enLigne = { total: 0, canvas: 0, pourcentage: 0, autres: 0, autresDansContenu: 0, exemples: [] };
  for (const e of tous) {
    const st = e.getAttribute('style') || '';
    if (!/(^|;)\s*(width|height|min-width|max-width|min-height|max-height)\s*:/i.test(st)) continue;
    if (!visible(e) || !horsImpression(e)) continue;
    enLigne.total++;
    const estCanvas = e.tagName === 'CANVAS' || !!e.closest('.chart, [data-chart]') || e.querySelector('canvas') !== null;
    const pourcentage = /(width|height)\s*:\s*[\d.]+%/i.test(st);
    const contenu = dansContenu(e);
    if (estCanvas) enLigne.canvas++;
    else if (pourcentage) enLigne.pourcentage++;
    else { enLigne.autres++; if (contenu) enLigne.autresDansContenu++; }
    if (enLigne.exemples.length < 12) {
      enLigne.exemples.push({ signature: signature(e), style: st.slice(0, 120), canvas: estCanvas, pourcentage: pourcentage, dansContenu: contenu });
    }
  }
  res.stylesEnLigne = enLigne;

  /* Un écran autonome n'a pas de #page-content : on s'arrête là. */
  if (!pc) {
    res.texteSansCoquille = true;
    return res;
  }

  const rPC = pc.getBoundingClientRect();
  res.contenu = {
    largeur: pc.clientWidth, largeurDefilement: pc.scrollWidth, hauteur: arrondi(pc.scrollHeight),
    debordementHorizontal: pc.scrollWidth > pc.clientWidth + 1,
    gauche: arrondi(rPC.left), droite: arrondi(rPC.right), top: arrondi(rPC.top + window.scrollY),
    enfants: pc.children.length,
  };

  /* ---- Blocs du gabarit et leur ordre ------------------------------------ */
  const main = pc.closest('main');
  const entete = main && main.firstElementChild !== pc ? main.firstElementChild : null;
  const topDe = (e) => arrondi(e.getBoundingClientRect().top + window.scrollY);
  const premier = (sel, filtre) => Array.from(pc.querySelectorAll(sel)).filter((e) => visible(e) && (!filtre || filtre(e)))[0] || null;
  const estGrilleKpi = (e) => e.classList.contains('grid') && Array.from(e.children).some((c) => c.classList.contains('kpi'));
  const grillesKpi = Array.from(pc.querySelectorAll('.grid')).filter((e) => visible(e) && estGrilleKpi(e));
  const premiereCarte = premier('.card');
  const premierTableau = premier('table');
  const premierFormulaire = premier('form.grid');
  /* Le bandeau de lecture seule : celui de l'en-tête commun (app.js) ou la
     note du kit (« État calculé — lecture seule »). Reconnu par son texte,
     seul trait commun aux deux. */
  const lectureSeule = Array.from(doc.querySelectorAll('main .rounded-lg.border'))
    .filter((e) => visible(e) && /lecture seule/i.test(e.textContent || '') && (e.textContent || '').length < 600)[0] || null;

  const blocs = {
    entete: entete ? { top: topDe(entete), hauteur: arrondi(entete.getBoundingClientRect().height), signature: signature(entete) } : null,
    lectureSeule: lectureSeule ? { top: topDe(lectureSeule), texte: texteCourt(lectureSeule, 80) } : null,
    kpi: grillesKpi.length ? { top: topDe(grillesKpi[0]), nombre: grillesKpi.length } : null,
    carte: premiereCarte ? { top: topDe(premiereCarte), nombre: Array.from(pc.querySelectorAll('.card')).filter(visible).length } : null,
    tableau: premierTableau ? { top: topDe(premierTableau), nombre: Array.from(pc.querySelectorAll('table')).filter(visible).length } : null,
    formulaire: premierFormulaire ? { top: topDe(premierFormulaire), nombre: Array.from(pc.querySelectorAll('form.grid')).filter(visible).length } : null,
  };
  res.blocs = blocs;
  res.ordre = Object.keys(blocs).filter((k) => blocs[k]).sort((a, b) => blocs[a].top - blocs[b].top);
  /* Les blocs DIRECTS du contenu (ou de l'enveloppe unique que pose K.dash),
     dans l'ordre du DOM : c'est l'ordre réel du gabarit tel qu'il se lit. */
  let niveau = pc;
  while (niveau.children.length === 1 && niveau.firstElementChild.children.length > 1
    && !niveau.firstElementChild.classList.contains('card') && !estGrilleKpi(niveau.firstElementChild)
    && !niveau.firstElementChild.classList.contains('grid')) {
    niveau = niveau.firstElementChild;
  }
  res.sequenceDirecte = Array.from(niveau.children).filter(visible).map((e) => {
    if (e.classList.contains('card')) return 'carte';
    if (estGrilleKpi(e)) return 'kpi';
    if (e.tagName === 'FORM') return 'formulaire';
    if (e.tagName === 'TABLE') return 'tableau';
    if (e.querySelector && e.querySelector(':scope > .tab, :scope > [role="tablist"], :scope > .flex > .tab')) return 'onglets';
    if (/lecture seule/i.test(e.textContent || '') && e.classList.contains('border')) return 'lectureSeule';
    if (e.classList.contains('rounded-lg') && e.classList.contains('border')) return 'note';
    if (e.classList.contains('grid')) return 'grille';
    return e.tagName.toLowerCase() + (classesDe(e) ? '.' + classesDe(e).split(' ')[0] : '');
  });

  /* ---- Cartes ------------------------------------------------------------- */
  for (const c of Array.from(pc.querySelectorAll('.card')).filter(visible)) {
    const cs = getComputedStyle(c);
    const r = c.getBoundingClientRect();
    const tete = Array.from(c.children).find((x) => x.classList.contains('card-head'));
    const corps = Array.from(c.children).find((x) => x.classList.contains('card-body'));
    let prec = c.previousElementSibling;
    while (prec && !visible(prec)) prec = prec.previousElementSibling;
    const ecart = prec ? arrondi(r.top - prec.getBoundingClientRect().bottom) : null;
    res.cartes.push({
      titre: tete ? texteCourt(tete, 50) : null,
      top: topDe(c), hauteur: arrondi(r.height), largeur: arrondi(r.width),
      padding: padding(cs),
      paddingEntete: tete ? padding(getComputedStyle(tete)) : null,
      paddingCorps: corps ? padding(getComputedStyle(corps)) : null,
      rayon: rayon(cs), bordure: bordure(cs), ombre: cs.boxShadow !== 'none',
      ecartPrecedent: ecart, precedent: prec ? signature(prec).slice(0, 60) : null,
      parent: espacementParent(c),
      imbriquee: !!(c.parentElement && c.parentElement.closest('.card')),
    });
  }

  /* ---- Grilles KPI -------------------------------------------------------- */
  for (const g of grillesKpi) {
    const cs = getComputedStyle(g);
    const kpis = Array.from(g.children).filter((x) => x.classList.contains('kpi') && visible(x));
    const k0 = kpis[0] ? getComputedStyle(kpis[0]) : null;
    res.kpiGrilles.push({
      classes: classesDe(g).split(' ').filter((x) => /grid-cols-/.test(x)),
      colonnesEffectives: colonnesEffectives(cs), nbKpi: kpis.length,
      gap: nombre(cs.columnGap), gapLigne: nombre(cs.rowGap),
      largeurKpi: kpis[0] ? arrondi(kpis[0].getBoundingClientRect().width) : null,
      paddingKpi: k0 ? padding(k0) : null, rayonKpi: k0 ? rayon(k0) : null,
      dansCarte: !!g.closest('.card'), top: topDe(g),
    });
  }

  /* ---- Formulaires U.form ------------------------------------------------- */
  for (const f of Array.from(pc.querySelectorAll('form.grid'))) {
    const estVisible = visible(f);
    const cs = getComputedStyle(f);
    const spans = {};
    let nbChamps = 0;
    for (const w of f.children) {
      if (!(w instanceof Element)) continue;
      nbChamps++;
      const cl = classesDe(w).split(' ').filter((x) => /col-span-/.test(x));
      const cle = cl.length ? cl.join(' ') : '(aucun)';
      spans[cle] = (spans[cle] || 0) + 1;
    }
    res.formulaires.push({
      visible: estVisible, classes: classesDe(f).split(' ').filter((x) => /grid-cols-|gap-/.test(x)),
      colonnesEffectives: estVisible ? colonnesEffectives(cs) : null, gap: estVisible ? nombre(cs.columnGap) : null,
      nbChamps: nbChamps, spans: spans, dansCarte: !!f.closest('.card'), top: estVisible ? topDe(f) : null,
    });
  }

  /* ---- Tableaux ----------------------------------------------------------- */
  for (const t of Array.from(pc.querySelectorAll('table')).filter(visible)) {
    const r = t.getBoundingClientRect();
    const td = t.querySelector('tbody td'), th = t.querySelector('thead th');
    let conteneur = t.parentElement;
    while (conteneur && conteneur !== pc && !/(auto|scroll|hidden|clip)/.test(getComputedStyle(conteneur).overflowX)) conteneur = conteneur.parentElement;
    const defilant = conteneur && conteneur !== pc;
    res.tableaux.push({
      largeur: arrondi(r.width), largeurConteneur: conteneur ? conteneur.clientWidth : null,
      classes: classesDe(t), colonnes: t.querySelectorAll('thead th').length, lignes: t.querySelectorAll('tbody tr').length,
      debordeConteneur: conteneur ? r.width > conteneur.clientWidth + 1 : null,
      conteneurDefilant: !!defilant,
      policeCellule: td ? nombre(getComputedStyle(td).fontSize) : null,
      policeEntete: th ? nombre(getComputedStyle(th).fontSize) : null,
      paddingCellule: td ? padding(getComputedStyle(td)) : null,
      dansCarte: !!t.closest('.card'), top: topDe(t),
    });
  }

  /* ---- Éléments qui dépassent le contenu à droite ------------------------- */
  const dep = { total: 0, defilementsInternes: 0, exemples: [] };
  const limiteDroite = rPC.right + 1;
  for (const e of Array.from(pc.querySelectorAll('*'))) {
    if (!visible(e) || !horsImpression(e)) continue;
    const r = e.getBoundingClientRect();
    if (r.right <= limiteDroite) continue;
    const cs = getComputedStyle(e);
    if (cs.position === 'fixed' || cs.position === 'absolute') continue;
    /* Un tableau plus large que son conteneur `overflow-x-auto` DÉFILE : ce
       n'est pas un débordement de page, c'est un défilement interne voulu. */
    let a = e.parentElement, clippe = false;
    while (a && a !== pc) {
      if (/(auto|scroll|hidden|clip)/.test(getComputedStyle(a).overflowX)) { clippe = true; break; }
      a = a.parentElement;
    }
    if (clippe) { dep.defilementsInternes++; continue; }
    dep.total++;
    if (dep.exemples.length < 10) dep.exemples.push({ signature: signature(e), depassement: arrondi(r.right - rPC.right), largeur: arrondi(r.width) });
  }
  res.depassementsDroite = dep;

  return res;
}

/* =============================================================================
 * OUVERTURE D'UNE PAGE À UNE LARGEUR
 * ========================================================================== */
async function ouvrirEtRelever(navigateur, rel, largeur, opts) {
  const id = idDePage(rel);
  const autonome = estAutonome(id);
  const page = await navigateur.newPage();
  await page.setViewport({ width: largeur, height: largeur < 768 ? 850 : 900, deviceScaleFactor: 1, isMobile: false });
  await BANC.poserSession(page);
  page.setDefaultNavigationTimeout(180000);
  page.setDefaultTimeout(180000);
  const erreurs = [];
  page.on('pageerror', (e) => erreurs.push(String(e.message || e)));
  page.on('console', (m) => { if (m.type() === 'error') erreurs.push('console.error: ' + m.text()); });

  const t0 = Date.now();
  const sortie = { largeur: largeur, ms: 0, peinte: false, redirigee: null, erreursJS: [], capture: null, releve: null, erreur: null };
  try {
    await page.goto(`http://127.0.0.1:${PORT}/${rel}`, { waitUntil: 'domcontentloaded', timeout: 180000 });
    if (autonome) {
      /* Pas de #page-content : on attend que le corps ait quelque chose à montrer. */
      await page.waitForFunction(() => document.body && document.body.children.length > 1 && document.body.textContent.trim().length > 20,
        { timeout: 30000 }).catch(() => null);
    } else {
      /* La peinture, comme check.js ; OU une redirection (activité fermée →
         error-403, session refusée → index) : l'attendre 150 s ne mesurerait
         qu'une adresse, et la page d'arrivée n'a pas de #page-content. */
      await page.waitForFunction((attendu) => {
        if (!location.pathname.includes('/' + attendu + '.')) return true;
        const c = document.getElementById('page-content');
        return !!(window.SIGH && window.SIGH.store && c && c.children.length > 0);
      }, { timeout: 150000 }, id).catch(() => null);
    }
    await new Promise((r) => setTimeout(r, 450)); /* rendu différé (graphiques, icônes) */
    const url = page.url();
    const idFinal = idDePage(url.split('?')[0].split('#')[0]);
    if (idFinal !== id) sortie.redirigee = idFinal;
    sortie.peinte = await page.evaluate(() => {
      const c = document.getElementById('page-content');
      return !!(c && c.children.length > 0);
    }).catch(() => false);
    if (!sortie.redirigee) {
      sortie.releve = await page.evaluate(releverDansLaPage, SEUIL_POLICE_PX);
    }
    if (opts.captures && !sortie.redirigee) {
      const hauteur = await page.evaluate(() => Math.max(document.documentElement.scrollHeight, document.body.scrollHeight));
      const fichier = path.join(DOSSIER_CAPTURES, `${id}@${largeur}.png`);
      await page.screenshot({ path: fichier, type: 'png', captureBeyondViewport: true,
        clip: { x: 0, y: 0, width: largeur, height: Math.min(Math.max(hauteur, 300), HAUTEUR_CAPTURE_MAX) } });
      sortie.capture = path.relative(ROOT, fichier).replace(/\\/g, '/');
    }
  } catch (e) {
    sortie.erreur = e.message;
  }
  sortie.ms = Date.now() - t0;
  sortie.erreursJS = [...new Set(erreurs)].slice(0, 6);
  await page.close().catch(() => null);
  return sortie;
}

/* =============================================================================
 * RÉSUMÉ STATISTIQUE
 * -----------------------------------------------------------------------------
 * Pour chaque métrique : distribution des valeurs, valeur dominante (le mode),
 * fréquence, et pages hors norme. « Hors norme » = la page porte une valeur
 * RARE : différente de la dominante et représentant moins de 5 % des
 * occurrences. Le seuil est écrit dans le résumé, pas caché dans le code.
 * ========================================================================== */
const PART_RARE = 0.05;

function cleValeur(v) {
  if (v === null || v === undefined) return 'null';
  return typeof v === 'object' ? JSON.stringify(v) : String(v);
}

/** occurrences : [{ page, valeur }] → statistique. */
function statistique(occurrences, opts) {
  opts = opts || {};
  const comptes = {};
  const pagesParValeur = {};
  for (const o of occurrences) {
    const k = cleValeur(o.valeur);
    comptes[k] = (comptes[k] || 0) + 1;
    (pagesParValeur[k] = pagesParValeur[k] || new Set()).add(o.page);
  }
  const total = occurrences.length;
  const tri = Object.entries(comptes).sort((a, b) => b[1] - a[1]);
  const dominante = tri.length ? tri[0][0] : null;
  const rares = new Set(tri.filter(([k, n]) => k !== dominante && n / total < PART_RARE).map(([k]) => k));
  const horsNorme = {};
  for (const o of occurrences) {
    const k = cleValeur(o.valeur);
    if (!rares.has(k)) continue;
    (horsNorme[o.page] = horsNorme[o.page] || []).push(k);
  }
  const horsNormeListe = Object.entries(horsNorme).map(([page, vals]) => {
    const c = {}; vals.forEach((v) => { c[v] = (c[v] || 0) + 1; });
    return { page: page, valeurs: c };
  }).sort((a, b) => a.page.localeCompare(b.page));
  return {
    unite: opts.unite || null,
    occurrences: total,
    pages: new Set(occurrences.map((o) => o.page)).size,
    dominante: dominante === null ? null : (opts.brute ? dominante : essayerNombre(dominante)),
    frequence: dominante === null ? null : { nombre: tri[0][1], part: arrondiPart(tri[0][1] / total),
      pages: pagesParValeur[dominante].size },
    distribution: tri.slice(0, opts.max || 10).map(([k, n]) => ({ valeur: opts.brute ? k : essayerNombre(k), nombre: n, part: arrondiPart(n / total), pages: pagesParValeur[k].size })),
    horsNorme: horsNormeListe,
    nbPagesHorsNorme: horsNormeListe.length,
  };
}
function essayerNombre(k) {
  if (k === 'null') return null;
  if (/^-?\d+(\.\d+)?$/.test(k)) return Number(k);
  if (/^[\[{]/.test(k)) { try { return JSON.parse(k); } catch (e) { return k; } }
  return k;
}
function arrondiPart(x) { return Math.round(x * 1000) / 10; }

function resumer(mesures) {
  const largeurs = mesures.largeurs;
  const pagesTravail = mesures.pages.filter((p) => !p.autonome && p.largeurs[largeurs[0]] && p.largeurs[largeurs[0]].releve && p.largeurs[largeurs[0]].releve.contenu);
  const resume = {
    genereLe: new Date().toISOString(),
    source: path.relative(ROOT, FICHIER_MESURES).replace(/\\/g, '/'),
    regleHorsNorme: 'Une page est hors norme sur une métrique quand elle porte une valeur différente de la dominante '
      + 'et représentant moins de ' + (PART_RARE * 100) + ' % des occurrences mesurées. La norme est la valeur dominante MESURÉE, '
      + 'jamais une valeur choisie.',
    seuilPolicePx: Math.round(SEUIL_POLICE_PX * 100) / 100,
    pages: { total: mesures.pages.length, travail: pagesTravail.length,
      autonomes: mesures.pages.filter((p) => p.autonome).map((p) => p.page),
      redirigees: [], nonPeintes: [], enErreur: [], avecErreursJS: [] },
    largeurs: largeurs,
    metriques: {},
  };
  for (const p of mesures.pages) {
    for (const L of largeurs) {
      const m = p.largeurs[L]; if (!m) continue;
      if (m.redirigee) resume.pages.redirigees.push({ page: p.page, largeur: L, vers: m.redirigee });
      else if (!p.autonome && !m.peinte) resume.pages.nonPeintes.push({ page: p.page, largeur: L });
      if (m.erreur) resume.pages.enErreur.push({ page: p.page, largeur: L, erreur: m.erreur });
      if (m.erreursJS && m.erreursJS.length) resume.pages.avecErreursJS.push({ page: p.page, largeur: L, erreurs: m.erreursJS });
    }
  }

  const M = resume.metriques;
  const occ = () => [];
  for (const L of largeurs) {
    const releves = pagesTravail.map((p) => ({ page: p.page, r: p.largeurs[L] && p.largeurs[L].releve })).filter((x) => x.r && x.r.contenu);
    const o = {
      largeurContenu: occ(), debordementContenu: occ(), debordementDocument: occ(), depassementsDroite: occ(),
      paddingCarte: occ(), paddingCorpsCarte: occ(), paddingEnteteCarte: occ(), rayonCarte: occ(), bordureCarte: occ(), ecartEntreBlocs: occ(),
      colonnesKpi: occ(), classesKpi: occ(), paddingKpi: occ(), gapKpi: occ(),
      colonnesFormulaire: occ(), spansFormulaire: occ(), gapFormulaire: occ(),
      policeCelluleTableau: occ(), policeEnteteTableau: occ(), tableauDebordeConteneur: occ(), tableauDefilant: occ(),
      policeMinimalePage: occ(), policeMinimaleContenu: occ(), policesSousSeuil: occ(), tailleSousSeuil: occ(), tailleSousSeuilContenu: occ(),
      stylesEnLigneHorsCanvas: occ(), stylesEnLigneContenu: occ(), ordreBlocs: occ(), sequenceDirecte: occ(), enteteAvantContenu: occ(), kpiAvantPremiereCarte: occ(),
    };
    for (const { page, r } of releves) {
      o.largeurContenu.push({ page, valeur: r.contenu.largeur });
      o.debordementContenu.push({ page, valeur: r.contenu.debordementHorizontal });
      o.debordementDocument.push({ page, valeur: r.document.debordementHorizontal });
      o.depassementsDroite.push({ page, valeur: r.depassementsDroite ? r.depassementsDroite.total : 0 });
      for (const c of r.cartes) {
        o.paddingCarte.push({ page, valeur: c.padding });
        if (c.paddingCorps) o.paddingCorpsCarte.push({ page, valeur: c.paddingCorps });
        if (c.paddingEntete) o.paddingEnteteCarte.push({ page, valeur: c.paddingEntete });
        o.rayonCarte.push({ page, valeur: c.rayon });
        o.bordureCarte.push({ page, valeur: c.bordure.largeur + 'px ' + c.bordure.style });
        if (c.ecartPrecedent !== null && !c.imbriquee) o.ecartEntreBlocs.push({ page, valeur: Math.round(c.ecartPrecedent) });
      }
      for (const g of r.kpiGrilles) {
        o.colonnesKpi.push({ page, valeur: g.colonnesEffectives });
        o.classesKpi.push({ page, valeur: g.classes.join(' ') || '(aucune)' });
        if (g.paddingKpi) o.paddingKpi.push({ page, valeur: g.paddingKpi });
        o.gapKpi.push({ page, valeur: g.gap });
      }
      for (const f of r.formulaires) {
        if (!f.visible) continue;
        o.colonnesFormulaire.push({ page, valeur: f.colonnesEffectives });
        o.gapFormulaire.push({ page, valeur: f.gap });
        for (const [span, n] of Object.entries(f.spans)) for (let i = 0; i < n; i++) o.spansFormulaire.push({ page, valeur: span });
      }
      for (const t of r.tableaux) {
        if (t.policeCellule !== null) o.policeCelluleTableau.push({ page, valeur: t.policeCellule });
        if (t.policeEntete !== null) o.policeEnteteTableau.push({ page, valeur: t.policeEntete });
        o.tableauDebordeConteneur.push({ page, valeur: t.debordeConteneur });
        o.tableauDefilant.push({ page, valeur: t.conteneurDefilant });
      }
      if (r.polices) {
        o.policeMinimalePage.push({ page, valeur: r.polices.minimum });
        o.policeMinimaleContenu.push({ page, valeur: r.polices.minimumContenu });
        o.policesSousSeuil.push({ page, valeur: r.polices.sousSeuilDansContenu });
        for (const [taille, n] of Object.entries(r.polices.parTaille)) for (let i = 0; i < Math.min(n, 400); i++) o.tailleSousSeuil.push({ page, valeur: Number(taille) });
        for (const [taille, n] of Object.entries(r.polices.parTailleContenu || {})) for (let i = 0; i < Math.min(n, 400); i++) o.tailleSousSeuilContenu.push({ page, valeur: Number(taille) });
      }
      if (r.stylesEnLigne) {
        o.stylesEnLigneHorsCanvas.push({ page, valeur: r.stylesEnLigne.autres });
        o.stylesEnLigneContenu.push({ page, valeur: r.stylesEnLigne.autresDansContenu || 0 });
      }
      if (r.ordre) o.ordreBlocs.push({ page, valeur: r.ordre.join(' > ') });
      if (r.sequenceDirecte) o.sequenceDirecte.push({ page, valeur: r.sequenceDirecte.slice(0, 4).join(' > ') + (r.sequenceDirecte.length > 4 ? ' > …' : '') });
      if (r.blocs && r.blocs.entete) o.enteteAvantContenu.push({ page, valeur: r.blocs.entete.top <= r.contenu.top });
      if (r.blocs && r.blocs.kpi && r.blocs.carte && !/^dash-/.test(page)) o.kpiAvantPremiereCarte.push({ page, valeur: r.blocs.kpi.top <= r.blocs.carte.top });
    }
    const S = {};
    S.largeurContenu = statistique(o.largeurContenu, { unite: 'px' });
    S.debordementHorizontalContenu = listeVraies(o.debordementContenu);
    S.debordementHorizontalDocument = listeVraies(o.debordementDocument);
    S.depassementsDroite = { pages: o.depassementsDroite.filter((x) => x.valeur > 0).map((x) => ({ page: x.page, elements: x.valeur })),
      nbPages: o.depassementsDroite.filter((x) => x.valeur > 0).length };
    S.paddingCarte = statistique(o.paddingCarte, { unite: 'px (la .card elle-même)' });
    S.paddingCorpsCarte = statistique(o.paddingCorpsCarte, { unite: 'px (.card-body)' });
    S.paddingEnteteCarte = statistique(o.paddingEnteteCarte, { unite: 'px (.card-head)' });
    S.rayonCarte = statistique(o.rayonCarte, { unite: 'px' });
    S.bordureCarte = statistique(o.bordureCarte, { brute: true });
    S.ecartEntreBlocs = statistique(o.ecartEntreBlocs, { unite: 'px (marge réelle entre une carte et le bloc frère qui la précède)' });
    S.colonnesKpi = statistique(o.colonnesKpi, { unite: 'colonnes effectives' });
    S.classesKpi = statistique(o.classesKpi, { brute: true });
    S.paddingKpi = statistique(o.paddingKpi, { unite: 'px (.kpi)' });
    S.gapKpi = statistique(o.gapKpi, { unite: 'px' });
    S.colonnesFormulaire = statistique(o.colonnesFormulaire, { unite: 'colonnes effectives (formulaires visibles)' });
    S.spansFormulaire = statistique(o.spansFormulaire, { brute: true });
    S.gapFormulaire = statistique(o.gapFormulaire, { unite: 'px' });
    S.policeCelluleTableau = statistique(o.policeCelluleTableau, { unite: 'px' });
    S.policeEnteteTableau = statistique(o.policeEnteteTableau, { unite: 'px' });
    S.tableauDebordeConteneur = listeVraies(o.tableauDebordeConteneur);
    S.tableauDefilant = listeVraies(o.tableauDefilant);
    S.policeMinimalePage = statistique(o.policeMinimalePage, { unite: 'px (plus petite police visible de la page, coquille comprise)' });
    S.policeMinimaleContenu = statistique(o.policeMinimaleContenu, { unite: 'px (plus petite police visible dans #page-content)' });
    S.taillesSousSeuil = statistique(o.tailleSousSeuil, { unite: 'px (tailles < ' + resume.seuilPolicePx + ' px sur toute la page, chaque élément compté, plafonné à 400 par taille et par page)' });
    S.taillesSousSeuilContenu = statistique(o.tailleSousSeuilContenu, { unite: 'px (tailles < ' + resume.seuilPolicePx + ' px dans #page-content seulement)' });
    S.elementsSousSeuilDansContenuParPage = statistique(o.policesSousSeuil.map((x) => ({ page: x.page, valeur: tranche(x.valeur) })), { brute: true, unite: 'tranche du nombre d’éléments < 11 pt dans #page-content' });
    S.stylesEnLigneHorsCanvasEtPourcentage = {
      note: 'Styles en ligne width/height hors canvas de graphique et hors largeurs en pourcentage (barres de progression). `coquille` compte la barre supérieure et le ruban, communs à toutes les pages.',
      pagesContenu: o.stylesEnLigneContenu.filter((x) => x.valeur > 0).map((x) => ({ page: x.page, elements: x.valeur })),
      nbPagesContenu: o.stylesEnLigneContenu.filter((x) => x.valeur > 0).length,
      nbPagesCoquilleOuContenu: o.stylesEnLigneHorsCanvas.filter((x) => x.valeur > 0).length,
    };
    S.ordreBlocs = statistique(o.ordreBlocs, { brute: true, max: 15 });
    S.sequenceDirecte = statistique(o.sequenceDirecte, { brute: true, max: 15 });
    S.enteteAvantContenu = listeFausses(o.enteteAvantContenu);
    S.kpiAvantPremiereCarte = Object.assign(listeFausses(o.kpiAvantPremiereCarte), { note: 'Pages hors tableaux de bord (dash-*) portant une grille KPI ET une carte : la grille KPI précède-t-elle la première carte ?' });
    M[L] = S;
  }
  return resume;
}
function listeVraies(occ) {
  const pages = occ.filter((x) => x.valeur === true).map((x) => x.page);
  return { mesures: occ.length, vrais: pages.length, pages: [...new Set(pages)] };
}
function listeFausses(occ) {
  const pages = occ.filter((x) => x.valeur === false).map((x) => x.page);
  return { mesures: occ.length, faux: pages.length, pages: [...new Set(pages)] };
}
function tranche(n) {
  if (n === 0) return '0'; if (n <= 10) return '1-10'; if (n <= 50) return '11-50'; if (n <= 150) return '51-150'; return '> 150';
}

/* =============================================================================
 * PROGRAMME PRINCIPAL
 * ========================================================================== */
(async () => {
  const args = process.argv.slice(2);
  const seulement = (args.find((a) => a.startsWith('--pages=')) || '').replace('--pages=', '');
  const largeurs = ((args.find((a) => a.startsWith('--largeurs=')) || '--largeurs=1440,400').replace('--largeurs=', ''))
    .split(',').map((x) => Number(x.trim())).filter(Boolean);
  const resumeSeulement = args.includes('--resume-seulement');
  const captures = !args.includes('--sans-captures');

  fs.mkdirSync(DOSSIER_CAPTURES, { recursive: true });
  /* Le dossier porte son propre .gitignore : tout est ignoré sauf le résumé. */
  const gi = path.join(DOSSIER, '.gitignore');
  if (!fs.existsSync(gi)) fs.writeFileSync(gi, '# Relevés et captures : volumineux, régénérés par build/mesure-mise-en-page.js.\n*\n!.gitignore\n!mise-en-page-resume.json\n');

  if (resumeSeulement) {
    const mesures = JSON.parse(fs.readFileSync(FICHIER_MESURES, 'utf8'));
    const resume = resumer(mesures);
    fs.writeFileSync(FICHIER_RESUME, JSON.stringify(resume, null, 1));
    console.log('Résumé recalculé : ' + path.relative(ROOT, FICHIER_RESUME));
    return;
  }

  const exe = trouverNavigateur();
  if (!exe) { console.error('Aucun navigateur Chrome/Edge trouvé. Définir CHROME_PATH.'); process.exit(2); }

  let pages = listerPages();
  if (seulement) {
    const voulues = seulement.split(',').map((s) => s.trim()).filter(Boolean);
    pages = pages.filter((p) => voulues.some((w) => p.includes(w)));
  }

  const php = await BANC.demarrerPhp(ROOT);
  if (!php.php) { console.error('\n  ÉCHEC : ' + php.raison + '\n'); process.exit(1); }
  const vidage = await BANC.banc('reinitialiser');
  if (vidage.erreur) {
    console.error('\n  ÉCHEC, base du banc : ' + (vidage.detail || vidage.erreur) + '\n');
    try { php.php.kill(); } catch (e) { /* déjà mort */ }
    process.exit(1);
  }
  console.log('  Banc : base « ' + vidage.base + ' » remise à neuf ; Node sur ' + PORT + ', PHP sur ' + process.env.SIGH_PORT_PHP + '.');

  const serveur = await servir();
  const navigateur = await puppeteer.launch({
    executablePath: exe, headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu', '--hide-scrollbars'],
  });

  const mesures = { genereLe: new Date().toISOString(), largeurs: largeurs, seuilPolicePx: SEUIL_POLICE_PX,
    hauteurCaptureMax: HAUTEUR_CAPTURE_MAX, base: vidage.base, pages: [] };
  /* LA MESURE FUSIONNE (06/11/2026) : un passage ciblé (--pages=…) remplaçait tout le relevé par ses seules pages, et un plantage de Chrome en
     cours de route perdait ce qui avait été mesuré. Le relevé existant est repris, les pages demandées sont retirées puis remesurées ; un passage
     sans --pages repart de zéro (relevé complet). */
  const cible = args.find((a) => a.startsWith('--pages='));
  if (cible && fs.existsSync(FICHIER_MESURES)) {
    try {
      const ancien = JSON.parse(fs.readFileSync(FICHIER_MESURES, 'utf8'));
      const redemandees = new Set(pages.map((rel) => idDePage(rel)));
      mesures.pages = (ancien.pages || []).filter((p) => !redemandees.has(p.page));
    } catch (e) { console.warn('  Relevé existant illisible, repart de zéro : ' + e.message); }
  }
  let n = 0;
  const debut = Date.now();
  for (const rel of pages) {
    const id = idDePage(rel);
    const entree = { page: id, fichier: rel, autonome: estAutonome(id), largeurs: {} };
    for (const L of largeurs) {
      entree.largeurs[L] = await ouvrirEtRelever(navigateur, rel, L, { captures: captures });
    }
    mesures.pages.push(entree);
    n++;
    const m0 = entree.largeurs[largeurs[0]];
    const etat = m0.redirigee ? 'redirigée vers ' + m0.redirigee : (m0.erreur ? 'ERREUR ' + m0.erreur.slice(0, 60) : (m0.peinte || entree.autonome ? 'ok' : 'NON PEINTE'));
    console.log(`  ${String(n).padStart(3)}/${pages.length}  ${id.padEnd(40)} ${String(m0.ms).padStart(6)} ms  ${etat}`);
    /* Écriture incrémentale : une interruption ne perd pas ce qui est mesuré. */
    if (n % 10 === 0) fs.writeFileSync(FICHIER_MESURES, JSON.stringify(mesures));
  }
  mesures.dureeMs = Date.now() - debut;
  fs.writeFileSync(FICHIER_MESURES, JSON.stringify(mesures));

  await navigateur.close();
  serveur.close();
  try { php.php.kill(); } catch (e) { /* déjà mort */ }

  const resume = resumer(mesures);
  fs.writeFileSync(FICHIER_RESUME, JSON.stringify(resume, null, 1));

  const ligne = '─'.repeat(72);
  console.log('\n' + ligne);
  console.log('MESURE DE LA MISE EN PAGE');
  console.log(ligne);
  console.log(`Pages mesurées            : ${mesures.pages.length} (${resume.pages.travail} pages de travail, ${resume.pages.autonomes.length} autonomes)`);
  console.log(`Redirigées                : ${resume.pages.redirigees.length}`);
  console.log(`Non peintes               : ${resume.pages.nonPeintes.length}`);
  console.log(`En erreur                 : ${resume.pages.enErreur.length}`);
  console.log(`Durée                     : ${Math.round(mesures.dureeMs / 1000)} s`);
  for (const L of largeurs) {
    const S = resume.metriques[L];
    if (!S) continue;
    console.log(`\n── ${L} px ` + '─'.repeat(60));
    console.log(`  largeur de #page-content   : ${S.largeurContenu.dominante} px (${S.largeurContenu.frequence ? S.largeurContenu.frequence.part : 0} %)`);
    console.log(`  padding .card-body         : ${JSON.stringify(S.paddingCorpsCarte.dominante)} (${S.paddingCorpsCarte.frequence ? S.paddingCorpsCarte.frequence.part : 0} %), hors norme : ${S.paddingCorpsCarte.nbPagesHorsNorme} page(s)`);
    console.log(`  rayon .card                : ${S.rayonCarte.dominante} px ; bordure : ${S.bordureCarte.dominante}`);
    console.log(`  écart entre blocs          : ${S.ecartEntreBlocs.dominante} px (${S.ecartEntreBlocs.frequence ? S.ecartEntreBlocs.frequence.part : 0} %), hors norme : ${S.ecartEntreBlocs.nbPagesHorsNorme} page(s)`);
    console.log(`  colonnes KPI effectives    : ${S.colonnesKpi.dominante} (${S.colonnesKpi.frequence ? S.colonnesKpi.frequence.part : 0} %), hors norme : ${S.colonnesKpi.nbPagesHorsNorme} page(s)`);
    console.log(`  colonnes formulaire        : ${S.colonnesFormulaire.dominante} (${S.colonnesFormulaire.frequence ? S.colonnesFormulaire.frequence.part : 0} %)`);
    console.log(`  police cellule tableau     : ${S.policeCelluleTableau.dominante} px`);
    console.log(`  police minimale (contenu)  : ${S.policeMinimaleContenu.dominante} px (${S.policeMinimaleContenu.frequence ? S.policeMinimaleContenu.frequence.part : 0} %) ; page entière : ${S.policeMinimalePage.dominante} px`);
    console.log(`  débordement horizontal     : contenu ${S.debordementHorizontalContenu.vrais}, document ${S.debordementHorizontalDocument.vrais} page(s)`);
    console.log(`  dépassements à droite      : ${S.depassementsDroite.nbPages} page(s)`);
    console.log(`  styles en ligne (hors canvas et %) dans le contenu : ${S.stylesEnLigneHorsCanvasEtPourcentage.nbPagesContenu} page(s)`);
  }
  console.log('\n' + ligne);
  console.log('Relevé complet : ' + path.relative(ROOT, FICHIER_MESURES));
  console.log('Résumé         : ' + path.relative(ROOT, FICHIER_RESUME));
  console.log('Captures       : ' + path.relative(ROOT, DOSSIER_CAPTURES) + '/');
  console.log(ligne);
})().catch((e) => { console.error(e); process.exit(1); });
