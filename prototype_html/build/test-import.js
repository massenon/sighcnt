/* =============================================================================
 * SCÉNARIO 75 : le module d'importation, piloté dans un vrai navigateur sur la base jetable du banc
 * -----------------------------------------------------------------------------
 * Télécharger le modèle .xlsx et le RELIRE, téléverser pour de bon (sélecteur de fichier réel), refus NOMMÉ, fichier refusé
 * consigné sans rien écrire, rapport d'erreurs .xlsx, confirmation, fiches signées (source, lot, validé par), journal RG-12,
 * historique, annulation du lot par archivage (RG-14), refus d'annulation sous un stock vivant (RG-03), RG-01 sur les patients,
 * RG-10 sur les soldes d'ouverture, CSV, droits par jeu (commande absente, écran fermé).
 * Séparé de test-fonctionnel.js (11 700 lignes que d'autres chantiers allongent chaque jour) : même banc, mêmes serveurs.
 *     SIGH_PORT_PHP=8271 SIGH_PORT_TEST=8272 CHROME_PATH=… node build/test-import.js
 * ========================================================================== */
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');
const puppeteer = require('puppeteer');
const BANC = require('./_banc');

const ROOT = path.resolve(__dirname, '..');
const PORT = Number(process.env.SIGH_PORT_TEST) || 8096;
const MIME = { '.php': 'text/html; charset=utf-8', '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.woff2': 'font/woff2', '.jpeg': 'image/jpeg', '.png': 'image/png' };
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'sigh-import-'));
const pause = (ms) => new Promise((r) => setTimeout(r, ms));

const resultats = [];
let courant = null;
function scenario(nom) { courant = { nom, etapes: [], ok: true }; resultats.push(courant); }
function verifier(libelle, condition, detail) {
  const ok = !!condition;
  courant.etapes.push({ libelle, ok, detail: ok ? null : (detail || '') });
  if (!ok) courant.ok = false;
  process.stdout.write(ok ? '.' : 'X');
  if (!ok) process.stdout.write('\n  ✗ [' + courant.nom + '] ' + libelle + (detail ? '\n     → ' + String(detail).slice(0, 500) : '') + '\n');
}

(async () => {
  const php = await BANC.demarrerPhp(ROOT);
  if (!php.php) { console.error('ÉCHEC : ' + php.raison); process.exit(1); }
  const vidage = await BANC.banc('reinitialiser');
  if (vidage.erreur) { console.error('ÉCHEC base du banc : ' + (vidage.detail || vidage.erreur)); process.exit(1); }
  const server = http.createServer((req, res) => {
    if (req.url.indexOf('/api/') === 0) { BANC.relayer(req, res); return; }
    const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '') || 'index.php';
    const file = path.join(ROOT, rel);
    if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  }).listen(PORT);
  const browser = await puppeteer.launch({ executablePath: process.env.CHROME_PATH, headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const page = await browser.newPage();
  await BANC.poserSession(page);
  page.setDefaultNavigationTimeout(180000);
  page.setDefaultTimeout(180000);
  await page.setViewport({ width: 1600, height: 1000 });
  let erreursJS = [];
  page.on('pageerror', (e) => erreursJS.push(String(e.message)));
  page.on('console', (m) => { if (m.type() === 'error') erreursJS.push(m.text()); });

  async function attendreEcritures() {
    try {
      await page.evaluate(() => { if (window.SIGH && window.SIGH.store && window.SIGH.store.pousserMaintenant) window.SIGH.store.pousserMaintenant(); });
      await page.waitForFunction(() => !window.SIGH || !window.SIGH.store || !window.SIGH.store.fileEnAttente || window.SIGH.store.fileEnAttente() === 0, { timeout: 30000 });
    } catch (e) { /* page détruite */ }
  }
  async function ouvrir(ecran) {
    await attendreEcritures();
    erreursJS = [];
    const rep = await page.goto('http://127.0.0.1:' + PORT + '/pages/' + ecran + '.php', { waitUntil: 'domcontentloaded' }).catch(() => null);
    if (rep && rep.status() === 404) { console.log('\n  PAGE INTROUVABLE : ' + ecran); return; }
    const fin = Date.now() + 120000;
    while (Date.now() < fin) {
      try {
        await page.waitForFunction(() => {
          const S = window.SIGH && window.SIGH.store;
          if (!S) return false;
          if (/error-403|\/auth-|\/index\.php/.test(location.pathname)) return true;
          if (S.faitAutorite && !S.faitAutorite()) return false;
          const c = document.getElementById('page-content');
          return !!(c && c.children.length > 0);
        }, { timeout: 4000 });
        break;
      } catch (e) { /* pas encore */ }
    }
    await pause(400);
  }
  const ev = (fn, ...a) => page.evaluate(fn, ...a);
  async function role(r) {
    await ev((x) => window.SIGH.store.setSession({ role: x, fonction: x === 'admin' ? 'direction' : x, nom: 'TEST ' + x, nomComplet: 'TEST ' + x, identifiant: 'banc.' + x }), r);
  }
  async function cliquer(texte, sel) {
    const ok = await ev((t, s) => {
      const n = [...document.querySelectorAll(s || 'button, a, [role="tab"]')].find((x) => (x.textContent || '').trim().toLowerCase().includes(t.toLowerCase()) && x.offsetParent !== null);
      if (n) { n.click(); return true; }
      return false;
    }, texte, sel);
    await pause(500);
    return ok;
  }
  const texte = () => ev(() => document.querySelector('#page-content') ? document.querySelector('#page-content').innerText.replace(/\s+/g, ' ') : '');
  const aBouton = (t) => ev((x) => [...document.querySelectorAll('#page-content button')].some((b) => b.textContent.trim().toLowerCase().includes(x.toLowerCase())), t);
  async function ecrireClasseur(nom, table) {
    const octets = await ev((t) => Array.from(SIGH.xlsx.ecrire({ feuilles: [{ nom: 'Données', lignes: t }] })), table);
    const f = path.join(TMP, nom);
    fs.writeFileSync(f, Buffer.from(octets));
    return f;
  }
  async function televerser(fichier) {
    const input = await page.$('input[data-import-fichier]');
    await input.uploadFile(fichier);
    const fin = Date.now() + 20000;
    while (Date.now() < fin) {
      if (/Résultat de l’analyse du fichier/.test(await texte())) break;
      await pause(250);
    }
    await pause(300);
  }
  const ENTETE_GS = ['Code article', 'Désignation', 'Catégorie', 'Unité', 'Quantité', 'N° de lot', 'Date de péremption', 'Prix de revient unitaire', 'Seuil d’alerte', 'Emplacement', 'Code fournisseur'];

  /* ==========================================================================
   * 1. Accueil du module
   * ======================================================================== */
  scenario('Vague 71 : Importation : accueil du module et modèles .xlsx téléchargeables');
  await ouvrir('imp-accueil');
  await role('admin');
  await ouvrir('imp-accueil');
  let t = await texte();
  verifier('L’accueil du module liste les dix jeux d’import, chacun marqué « Supporté » ou « Proposition à valider »',
    (await ev(() => [...document.querySelectorAll('#page-content a')].filter((a) => a.textContent.trim() === 'Ouvrir').length)) === 10
      && /Proposition à valider/.test(t) && (t.match(/Supporté/g) || []).length >= 9, t.slice(0, 300));
  verifier('Chaque jeu dit sa source et ses collections cibles (rien d’inventé)', /Source : Inventaire SAGE 100/.test(t) && /Écrit dans : produits, lots, mouvements/.test(t), t.slice(0, 200));

  await ouvrir('m6-import-grand-stock');
  t = await texte();
  const titre = await ev(() => (document.querySelector('h1') || {}).textContent || '');
  verifier('L’écran porte le libellé exact « Importation Grand Stock »', /Importation Grand Stock/.test(titre), titre);
  await cliquer('Télécharger le modèle (.xlsx)');
  const modele = await ev(() => {
    const d = SIGH.importer.dernierTelechargement;
    const lu = SIGH.xlsx.lire(d.octets);
    return { nom: d.nom, signature: [d.octets[0], d.octets[1]], feuilles: lu.feuilles.map((f) => f.nom), entete: lu.feuilles[0].lignes[0], exemple: lu.feuilles[0].lignes[1],
      instr: lu.feuilles[1].lignes.map((l) => l[0]).filter(Boolean).slice(0, 14), listes: lu.feuilles[2].lignes[0], premiereListe: lu.feuilles[2].lignes.slice(1, 4).map((l) => l[0]) };
  });
  verifier('Le bouton produit un vrai .xlsx (archive ZIP « PK ») de trois feuilles : Données, Instructions, Listes',
    modele.nom === 'modele-import-grand-stock.xlsx' && modele.signature[0] === 0x50 && modele.signature[1] === 0x4b && modele.feuilles.join('|') === 'Données|Instructions|Listes', JSON.stringify(modele));
  verifier('La feuille Données porte les en-têtes exacts du jeu et une ligne d’exemple', JSON.stringify(modele.entete) === JSON.stringify(ENTETE_GS) && modele.exemple[0] === 'PARA500', JSON.stringify(modele.entete));
  verifier('La feuille Instructions liste colonnes, formats et valeurs permises ; la feuille Listes porte les référentiels',
    modele.instr.some((x) => /Colonne/.test(x)) && modele.instr.some((x) => /Code article/.test(x)) && modele.listes[0] === 'Catégorie' && modele.premiereListe[0] === 'Médicaments', JSON.stringify(modele));
  verifier('Le modèle intact (ligne d’exemple non modifiée) est refusé comme fichier vide, jamais importé',
    await ev(() => { const a = SIGH.importer.analyserOctets('grand-stock', SIGH.importer.dernierTelechargement.octets, 'modele.xlsx'); return !a.accepte && a.globaux[0].code === 'FICHIER_VIDE'; }), '');
  await cliquer('Modèle CSV');
  verifier('Le modèle CSV est aussi proposé (BOM, point-virgule, mêmes en-têtes)',
    await ev((e) => { const d = SIGH.importer.dernierTelechargement; const txt = new TextDecoder('utf-8', { ignoreBOM: true }).decode(d.octets); return d.nom === 'modele-import-grand-stock.csv' && txt.charCodeAt(0) === 0xFEFF && SIGH.xlsx.lireCsv(txt)[0].join('|') === e.join('|'); }, ENTETE_GS), '');

  /* Le lecteur DEFLATE de la maquette (inflate écrit pour le prototype) relit des classeurs compressés par un AUTRE compresseur (zlib de Python,
     niveaux 1 et 9 : blocs fixes et dynamiques) : un classeur sorti d'Excel est toujours compressé, jamais « stocké ». */
  const dossierFixtures = path.join(ROOT, '..', 'apps', 'poste', 'test', 'fixtures', 'import');
  const compresses = ['compresse-gs-valide', 'compresse-niveau1-modele-patients'].map((n) => ({
    n: n, octets: Array.from(fs.readFileSync(path.join(dossierFixtures, n + '.xlsx'))),
    ref: Array.from(fs.readFileSync(path.join(dossierFixtures, n.replace(/^compresse-(niveau1-)?/, '') + '.xlsx'))),
  }));
  const relus = await ev((l) => l.map((x) => {
    const a = SIGH.xlsx.lire(Uint8Array.from(x.octets)), b = SIGH.xlsx.lire(Uint8Array.from(x.ref));
    return { n: x.n, memes: JSON.stringify(a) === JSON.stringify(b), feuilles: a.feuilles.map((y) => y.nom).join('|'), lignes: a.feuilles[0].lignes.length };
  }), compresses);
  verifier('Le lecteur de la maquette relit des classeurs DEFLATE (niveaux 1 et 9) à l’identique de leurs originaux non compressés',
    relus.every((r) => r.memes && r.lignes >= 2), JSON.stringify(relus));

  /* ==========================================================================
   * 2. Grand Stock : refus nommé, consignation, rapport
   * ======================================================================== */
  scenario('Vague 71 : Importation Grand Stock : refus nommé, fichier consigné sans rien écrire, rapport d’erreurs .xlsx');
  const avant = await ev(() => ({ produits: SIGH.store.collection('produits').all().length, lots: SIGH.store.collection('lots').all().length, mouv: SIGH.store.collection('mouvements').all().length,
    lotsImport: SIGH.store.collection('lotsImportation').all().length }));
  const mauvais = [ENTETE_GS,
    ['TST-A', 'AMOXICILLINE TEST', 'Médicaments', 'Boîte', 100, 'L1', '2028-06-30', 350, 20, 'A1', 'SOBAPS'],
    ['TST-B', 'GANTS TEST', 'Consommables médicaux', 'Boîte', -4, '', '', '', '', '', ''],
    ['TST-C', 'QUINE TEST', 'Médicaments', 'Boîte', 'beaucoup', 'L2', '2028-01-01', 100, '', '', ''],
    ['TST-A', 'AMOXICILLINE TEST', 'Médicaments', 'Boîte', 5, 'L1', '2028-06-30', 350, '', '', ''],
    ['TST-D', 'SANS LOT', 'Médicaments', 'Boîte', 5, '', '', 100, '', '', ''],
    ['TST-E', 'BIJOU', 'Bijoux', '', 1, '', '', '', '', '', '']];
  await ouvrir('m6-import-grand-stock');
  await televerser(await ecrireClasseur('gs-mauvais.xlsx', mauvais));
  t = await texte();
  verifier('Le fichier fautif est REFUSÉ en entier et le dit : « Fichier refusé. Rien n’a été écrit »', /Fichier refusé\. Rien n’a été écrit/.test(t), t.slice(0, 400));
  verifier('Chaque refus est nommé : ligne, colonne, valeur, motif et geste de correction (jamais un refus muet)',
    /Quantité « -4 »/.test(t) && /stock ne peut jamais être négatif \(RG-03\)/.test(t) && /Quantité « beaucoup »/.test(t) && /identique à la ligne 2/.test(t)
      && /ne peut pas se ranger en FEFO/.test(t) && /Catégorie « Bijoux »/.test(t) && /Choisissez parmi : Médicaments/.test(t), t.slice(0, 900));
  const apres = await ev(() => ({ produits: SIGH.store.collection('produits').all().length, lots: SIGH.store.collection('lots').all().length, mouv: SIGH.store.collection('mouvements').all().length,
    lotsImport: SIGH.store.collection('lotsImportation').all().length, dernier: SIGH.store.collection('lotsImportation').all()[0] }));
  verifier('Rien n’est écrit dans produits, lots ni mouvements ; le fichier refusé est consigné en un lot « refusé »',
    apres.produits === avant.produits && apres.lots === avant.lots && apres.mouv === avant.mouv && apres.lotsImport === avant.lotsImport + 1
      && apres.dernier.etat === 'refuse' && apres.dernier.nbLignes === 6 && apres.dernier.erreurs.length >= 5, JSON.stringify(apres.dernier).slice(0, 300));
  verifier('Aucun bouton de confirmation n’est proposé sur un fichier refusé', !(await aBouton('Confirmer l’importation')), '');
  await cliquer('Rapport d’erreurs (.xlsx)', '#page-content button');
  const rap = await ev(() => { const d = SIGH.importer.dernierTelechargement; const lu = SIGH.xlsx.lire(d.octets); return { nom: d.nom, feuilles: lu.feuilles.map((f) => f.nom), entete: lu.feuilles[0].lignes[0], n: lu.feuilles[0].lignes.length, codes: lu.feuilles[0].lignes.slice(1).map((l) => l[4]) }; });
  verifier('Le rapport d’erreurs se télécharge en .xlsx (ligne, colonne, valeur, niveau, code, motif, geste)',
    /^rapport-IMP-\d{4}-\d{3}\.xlsx$/.test(rap.nom) && rap.entete.join('|') === 'Ligne|Colonne|Valeur|Niveau|Code|Motif|Geste de correction' && rap.n >= 6 && rap.codes.includes('RG03_STOCK_NEGATIF') && rap.codes.includes('DOUBLON_FICHIER'), JSON.stringify(rap));
  verifier('L’historique du jeu montre le lot refusé et son rapport', /Refusé, rien écrit/.test(await texte()), '');

  /* Colonne manquante. */
  const sansQte = mauvais.map((l) => l.filter((_, i) => i !== 4));
  await televerser(await ecrireClasseur('gs-sans-quantite.xlsx', sansQte));
  t = await texte();
  verifier('Une colonne obligatoire manquante est nommée avec son geste (orthographe exacte du modèle)', /colonne obligatoire « Quantité » absente/.test(t) && /téléchargez le modèle de nouveau/.test(t), t.slice(0, 500));
  verifier('Un fichier qui n’est pas un classeur est refusé en le disant', await (async () => {
    const f = path.join(TMP, 'faux.xlsx'); fs.writeFileSync(f, 'ceci n’est pas un classeur');
    await televerser(f);
    return /fichier illisible/.test(await texte());
  })(), '');

  /* ==========================================================================
   * 3. Grand Stock : confirmation, signature des fiches, journal, annulation
   * ======================================================================== */
  scenario('Vague 71 : Importation Grand Stock : confirmation, fiches signées, journal RG-12, historique, annulation du lot (RG-14)');
  const bon = [ENTETE_GS,
    ['TST-A', 'AMOXICILLINE TEST 500 MG B/100', 'Médicaments', 'Boîte', 100, 'LT1', '2028-06-30', 350, 20, 'Rayon T, Casier 1', 'SOBAPS'],
    ['TST-A', 'AMOXICILLINE TEST 500 MG B/100', 'Médicaments', 'Boîte', 50, 'LT2', '2029-01-31', 350, '', '', ''],
    ['TST-G', 'GANTS TEST M B/100', 'Consommables médicaux', '', 40, '', '', '', '', '', ''],
    ['TST-P', 'LOT PERIME TEST', 'Médicaments', 'Boîte', 10, 'LT9', '2020-01-01', 100, '', '', '']];
  const avantBon = await ev(() => ({ audit: SIGH.store.collection('audit').all().length }));
  await televerser(await ecrireClasseur('gs-bon.xlsx', bon));
  t = await texte();
  verifier('Un fichier conforme est accepté avec ses avertissements nommés, et RIEN n’est encore écrit',
    /Analyse conforme/.test(t) && /4 ligne\(s\) lue\(s\)/.test(t) && /1 avertissement/.test(t) === false && /le lot est déjà périmé/.test(t) && /prix de revient absent/.test(t)
      && (await ev(() => SIGH.store.collection('produits').all().filter((p) => /^TST-/.test(p.code)).length)) === 0, t.slice(0, 600));
  await cliquer('Confirmer l’importation (4 lignes)');
  verifier('La confirmation demande un accord explicite avant d’écrire', /Écrire ce lot/.test(await texte()) || (await ev(() => !!document.querySelector('[role=dialog]'))), '');
  await cliquer('Écrire le lot', 'button');
  await pause(900);
  const ecrit = await ev(() => {
    const S = SIGH.store, lot = S.collection('lotsImportation').all()[0];
    const prods = S.collection('produits').all().filter((p) => /^TST-/.test(p.code));
    const a = prods.find((p) => p.code === 'TST-A'), g = prods.find((p) => p.code === 'TST-G');
    return { lot: { ref: lot.reference, etat: lot.etat, n: lot.nbLignes, ecrits: lot.ecrits.length, validePar: lot.validePar },
      prods: prods.length, a: a && { stock: a.stock, gros: a.stockGros, detail: a.stockDetail, lot: a.lotImport, source: a.source, valide: a.validePar, prix: a.prixAchat, vente: a.prixVente, seuil: a.seuilAlerte },
      g: g && { prov: g.valorisationProvisoire, seuilAValider: g.seuilAValider },
      lots: S.collection('lots').all().filter((l) => l.lotImport === lot.reference).map((l) => [l.numeroLot, l.quantiteRestante, l.statut]),
      mouv: S.collection('mouvements').all().filter((m) => m.lotImport === lot.reference).map((m) => [m.type, m.stockType, m.quantite, m.justificatif]),
      audit: S.collection('audit').all().filter((x) => x.action === 'Import').length };
  });
  verifier('Le lot s’écrit d’un seul geste : 3 articles, 3 lots de péremption, 4 mouvements d’entrée au justificatif du lot (RG-03)',
    ecrit.lot.etat === 'applique' && ecrit.prods === 3 && ecrit.lots.length === 3 && ecrit.mouv.length === 4 && ecrit.mouv.every((m) => m[0] === 'entree' && m[1] === 'gros' && /^Import IMP-\d{4}-\d{3} \(stock initial/.test(m[3])), JSON.stringify(ecrit));
  verifier('Les quantités se cumulent par article (100 + 50) dans le magasin central, prix de vente = prix d’achat (RG-02), seuil de la ligne',
    ecrit.a.stock === 150 && ecrit.a.gros === 150 && ecrit.a.detail === 0 && ecrit.a.prix === 350 && ecrit.a.vente === 350 && ecrit.a.seuil === 20, JSON.stringify(ecrit.a));
  verifier('Chaque fiche porte source, lot d’import et validé par ; un prix absent crée un article « à valoriser », seuil « à valider », jamais un prix inventé',
    ecrit.a.lot === ecrit.lot.ref && /^Import Importation Grand Stock \(gs-bon\.xlsx\)$/.test(ecrit.a.source) && ecrit.a.valide === ecrit.lot.validePar && ecrit.g.prov === true && ecrit.g.seuilAValider === true, JSON.stringify(ecrit));
  verifier('Un lot déjà périmé est créé « périmé » (à retirer), pas masqué', ecrit.lots.some((l) => l[0] === 'LT9' && l[2] === 'perime'), JSON.stringify(ecrit.lots));
  verifier('L’importation est journalisée (RG-12) et l’historique du jeu montre le lot « Appliqué »', ecrit.audit >= 1 && /Appliqué/.test(await texte()), '');
  /* Rejeu du même fichier : refusé, les articles existent. */
  await televerser(await ecrireClasseur('gs-bon.xlsx', bon));
  t = await texte();
  verifier('Téléverser une seconde fois le même fichier est refusé en nommant les articles déjà présents, et ne crée aucun doublon',
    /existe déjà dans le référentiel/.test(t) && (await ev(() => SIGH.store.collection('produits').all().filter((p) => /^TST-/.test(p.code)).length)) === 3, t.slice(0, 400));
  /* Annulation refusée sous un stock vivant. */
  await ev(() => { const p = SIGH.store.collection('produits').all().find((x) => x.code === 'TST-A'); SIGH.store.collection('mouvements').insert({ reference: 'M-TST-1', date: '2026-08-16', produitId: p.id, produit: p.designation, type: 'sortie', typeLabel: 'Sortie', quantite: 3, stockType: 'gros', justificatif: 'Ordonnance test' }); });
  await ouvrir('m6-import-grand-stock');
  await ev(() => { document.querySelector('#page-content [title="Annuler le lot"]').click(); });
  await pause(500);
  await cliquer('Annuler le lot', '[role=dialog] button, .modal button, button');
  await pause(800);
  const refusAnnul = await ev(() => ({ actifs: SIGH.store.collection('produits').all().filter((p) => /^TST-/.test(p.code) && p.statut !== 'archive').length,
    etat: SIGH.store.collection('lotsImportation').all().find((l) => l.etat !== 'refuse').etat, toasts: [...document.querySelectorAll('#toast-host > div')].map((d) => d.innerText.replace(/\s+/g, ' ')).join(' | ') }));
  verifier('Annuler le lot sous un mouvement de stock postérieur est REFUSÉ en nommant le mouvement et le geste (RG-03) ; rien n’est archivé',
    refusAnnul.actifs === 3 && refusAnnul.etat === 'applique' && /Annulation refusée/.test(refusAnnul.toasts) && /mouvement de stock/.test(refusAnnul.toasts), JSON.stringify(refusAnnul));
  await ev(() => { const m = SIGH.store.collection('mouvements').all().find((x) => x.reference === 'M-TST-1'); SIGH.store.collection('mouvements').archive(m.id, 'essai'); });
  await ouvrir('m6-import-grand-stock');
  await ev(() => { document.querySelector('#page-content [title="Annuler le lot"]').click(); });
  await pause(500);
  await cliquer('Annuler le lot', '[role=dialog] button, .modal button, button');
  await pause(900);
  const annule = await ev(() => {
    const S = SIGH.store, lot = S.collection('lotsImportation').all().find((l) => l.etat !== 'refuse');
    return { etat: lot.etat, motif: lot.motifAnnulation,
      produits: S.collection('produits').all().filter((p) => /^TST-/.test(p.code)).map((p) => p.statut),
      lots: S.collection('lots').all().filter((l) => l.lotImport === lot.reference).map((l) => l.statut),
      physique: S.collection('produits').all().filter((p) => /^TST-/.test(p.code)).length };
  });
  verifier('L’annulation du lot ARCHIVE ses fiches (RG-14), les garde en base, et marque le lot « annulé »',
    annule.etat === 'annule' && annule.produits.length === 3 && annule.produits.every((s) => s === 'archive') && annule.lots.every((s) => s === 'archive') && annule.physique === 3 && /annulation demandée/.test(annule.motif), JSON.stringify(annule));
  verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));

  /* ==========================================================================
   * 4. Patients (RG-01) et soldes d'ouverture (RG-10)
   * ======================================================================== */
  scenario('Vague 71 : Importation des patients (RG-01) et des soldes d’ouverture (RG-10)');
  const ENT_PA = ['Code dossier', 'Nom', 'Prénom', 'Sexe', 'Date de naissance', 'Âge déclaré', 'Téléphone', 'Quartier', 'Adresse', 'Personne à prévenir', 'Groupe sanguin', 'Code assureur', 'N° de police', 'Date d’ouverture du dossier'];
  await role('reception');
  await ouvrir('imp-patients');
  const existant = await ev(() => SIGH.store.collection('patients').all()[0]);
  await televerser(await ecrireClasseur('pa-refus.xlsx', [ENT_PA,
    [existant.code, 'AUTRE', 'PERSONNE', 'F', '', 30, '0197000099', '', '', '', '', '', '', ''],
    ['', existant.nom, existant.prenom, existant.sexe, existant.dateNaissance, '', '', '', '', '', '', '', '', ''],
    ['', 'SANSAGE', 'Rose', 'F', '', '', '', '', '', '', '', '', '', '']]));
  t = await texte();
  verifier('RG-01 : un code patient déjà attribué est refusé en nommant le dossier, un doublon d’identité aussi, et l’absence d’âge aussi',
    /RG-01 : le code .* est déjà attribué/.test(t) && /doublon probable du dossier/.test(t) && /ni date de naissance ni âge déclaré/.test(t), t.slice(0, 700));
  await televerser(await ecrireClasseur('pa-bon.xlsx', [ENT_PA,
    ['CNT/9001/20', 'KPADE', 'Honorine', 'F', '1992-03-14', '', '0197111111', 'Natitingou', '', '', 'O+', '', '', '2020-02-10'],
    ['', 'DJIDJOHO', 'Rodrigue', 'M', '', 41, '0197222222', '', '', '', '', '', '', '']]));
  await cliquer('Confirmer l’importation (2 lignes)');
  await cliquer('Écrire le lot', 'button');
  await pause(900);
  const pats = await ev(() => SIGH.store.collection('patients').all().filter((p) => p.origineDossier === 'Reprise du répertoire papier').map((p) => [p.code, p.nom, p.age, p.externe, p.validePar ? 1 : 0, p.lotImport ? 1 : 0]));
  verifier('Le code du registre papier est conservé tel quel (RG-01), l’autre reçoit le prochain code CNT/n/AA ; chaque dossier est signé du lot',
    pats.length === 2 && pats.some((p) => p[0] === 'CNT/9001/20') && pats.some((p) => /^CNT\/\d+\/26$/.test(p[0]) && p[1] === 'DJIDJOHO' && p[2] === 41) && pats.every((p) => p[3] === false && p[4] === 1 && p[5] === 1), JSON.stringify(pats));
  const codes = await ev(() => { const c = SIGH.store.collection('patients').all().map((p) => p.code); return c.length - new Set(c).size; });
  verifier('Aucun code patient en double après l’import', codes === 0, String(codes));

  await role('comptable');
  await ouvrir('imp-soldes-ouverture');
  const ENT_SO = ['Date', 'N° de compte', 'Libellé', 'Tiers', 'Débit', 'Crédit'];
  await televerser(await ecrireClasseur('so-desequilibre.xlsx', [ENT_SO, ['2026-01-01', '571000', 'Caisse', '', 250000, ''], ['2026-01-01', '101100', 'Capital', '', '', 200000], ['2026-01-01', '601000', 'Achats', '', 5, '']]));
  t = await texte();
  verifier('Une ligne de classe 6 est refusée nommément : un compte de gestion ne se reporte jamais', /ne se reporte jamais/.test(t), t.slice(0, 500));
  await televerser(await ecrireClasseur('so-desequilibre2.xlsx', [ENT_SO, ['2026-01-01', '571000', 'Caisse', '', 250000, ''], ['2026-01-01', '101100', 'Capital', '', '', 200000]]));
  t = await texte();
  verifier('RG-10 : une écriture non équilibrée est refusée avec les deux totaux et l’écart ; aucune pièce déséquilibrée ne s’écrit',
    /écriture non équilibrée \(RG-10\)/.test(t) && /écart 50[\s  ]000/.test(t), t.slice(0, 500));
  const avantEcr = await ev(() => SIGH.store.collection('ecritures').all().length);
  await televerser(await ecrireClasseur('so-bon.xlsx', [ENT_SO, ['2026-01-01', '571000', 'Caisse', '', 250000, ''], ['2026-01-01', '101100', 'Capital', '', '', 250000]]));
  const ouvrBouton = await aBouton('Confirmer l’importation (2 lignes)');
  verifier('Une pièce équilibrée est acceptée', /Analyse conforme/.test(await texte()) && ouvrBouton, (await texte()).slice(0, 300));
  await cliquer('Confirmer l’importation (2 lignes)');
  await cliquer('Écrire le lot', 'button');
  await pause(900);
  const ecr = await ev((a) => {
    const nouv = SIGH.store.collection('ecritures').all().slice(0, SIGH.store.collection('ecritures').all().length - a);
    return nouv.filter((e) => e.journal === 'AN' && /Import/.test(e.source || '')).map((e) => [e.numero, e.statut, e.debit, e.credit]);
  }, avantEcr);
  verifier('La pièce d’ouverture naît en BROUILLON au journal AN, une seule pièce de deux lignes, débit = crédit',
    ecr.length === 2 && ecr.every((e) => e[1] === 'brouillon' && e[0] === ecr[0][0]) && ecr.reduce((s, e) => s + e[2], 0) === ecr.reduce((s, e) => s + e[3], 0), JSON.stringify(ecr));
  await televerser(await ecrireClasseur('so-bon.xlsx', [ENT_SO, ['2026-01-01', '571000', 'Caisse', '', 250000, ''], ['2026-01-01', '101100', 'Capital', '', '', 250000]]));
  verifier('Un exercice ne s’ouvre qu’une fois : un second à-nouveau est refusé en nommant la pièce existante', /porte déjà un à-nouveau \(AN-2026-/.test(await texte()), (await texte()).slice(0, 300));
  verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));

  /* ==========================================================================
   * 5. CSV, trois états du tiret, droits par jeu
   * ======================================================================== */
  scenario('Vague 71 : Importation : CSV, trois états du tarif (montant, NC, tiret), droits par jeu');
  await role('admin');
  await ouvrir('imp-actes');
  const ENT_AC = ['Code acte', 'Libellé', 'Secteur', 'Prix non assuré', 'Prix assuré', 'Code tarif'];
  await televerser(await ecrireClasseur('ac-bon.xlsx', [ENT_AC, ['TST-X1', 'Acte test A', 'Médecine générale', 5000, 3000, ''], ['TST-X2', 'Acte test B', 'Chirurgie', 8000, 'NC', ''], ['TST-X3', 'Acte test C', 'Maternité', '-', '-', '']]));
  t = await texte();
  verifier('Les trois états de la colonne assurée sont reconnus ; un tiret avertit (valeur manquante) sans jamais valoir zéro', /Analyse conforme/.test(t) && /ne se facturera pas/.test(t), t.slice(0, 500));
  await cliquer('Confirmer l’importation (3 lignes)');
  await cliquer('Écrire le lot', 'button');
  await pause(900);
  const actes = await ev(() => SIGH.store.collection('actes').all().filter((a) => /^TST-X/.test(a.code)).map((a) => [a.code, a.prixNonAssure, a.prixAssure, a.nonCouvert, a.assurable]).sort());
  verifier('Montant, NC (non couvert, l’assuré paie le prix de guichet) et tiret (null, ni zéro ni exclusion) sont écrits comme tels',
    JSON.stringify(actes) === JSON.stringify([['TST-X1', 5000, 3000, false, true], ['TST-X2', 8000, null, true, false], ['TST-X3', null, null, false, true]]), JSON.stringify(actes));
  await ouvrir('imp-fournisseurs');
  const csv = 'Code fournisseur;Raison sociale;Type;Ville;Adresse;Téléphone;IFU;Délai de livraison (jours);Banque;N° de compte\r\nTST-F1;"Fournisseur ""test"" SARL";Grossiste;Parakou;;0191000000;3202112446701;4;;\r\n';
  const fcsv = path.join(TMP, 'fournisseurs.csv'); fs.writeFileSync(fcsv, '\uFEFF' + csv);
  await televerser(fcsv);
  t = await texte();
  verifier('Un fichier .csv (BOM, point-virgule, guillemets doublés) est accepté comme un classeur', /Analyse conforme/.test(t) && /1 ligne\(s\) lue\(s\)/.test(t), t.slice(0, 400));

  /* Droits. */
  await role('stock');
  await ouvrir('m6-import-grand-stock');
  verifier('Le gestionnaire de stock importe le Grand Stock : téléverser et confirmer lui sont offerts', await aBouton('Téléverser un fichier'), '');
  await ouvrir('imp-patients');
  verifier('Le gestionnaire de stock n’ouvre pas l’import des patients : accès refusé', await ev(() => /error-403/.test(location.pathname)), await ev(() => location.pathname));
  await role('reception');
  await ouvrir('imp-patients');
  verifier('La réception importe les patients (commande offerte)', await aBouton('Téléverser un fichier'), '');
  await ouvrir('imp-personnel');
  verifier('La réception n’ouvre ni le personnel ni le Grand Stock', await ev(() => /error-403/.test(location.pathname)), '');
  await ouvrir('m6-import-grand-stock');
  verifier('… ni le Grand Stock', await ev(() => /error-403/.test(location.pathname)), '');
  await role('comptable');
  await ouvrir('imp-plan-comptable');
  verifier('Le comptable importe le plan comptable', await aBouton('Téléverser un fichier'), '');
  await ouvrir('imp-personnel');
  verifier('Le comptable n’ouvre pas l’import du personnel (réservé à la DAF et à l’administrateur)', await ev(() => /error-403/.test(location.pathname)), '');
  await role('direction');
  await ouvrir('m6-import-grand-stock');
  const dir = { telecharge: await aBouton('Télécharger le modèle'), televerse: await aBouton('Téléverser un fichier') };
  verifier('La Direction lit l’écran et télécharge le modèle, mais la commande « Téléverser » est ABSENTE (jamais grisée)', dir.telecharge && !dir.televerse, JSON.stringify(dir));
  await role('caissier');
  await ouvrir('imp-accueil');
  verifier('Le caissier n’a aucun accès au module d’importation', await ev(() => /error-403/.test(location.pathname)), '');
  await role('admin');
  await ouvrir('imp-accueil');
  await cliquer('Historique des lots', '[role="tab"]');
  t = await texte();
  verifier('L’historique général liste les lots de tous les jeux, avec leur état', /IMP-\d{4}-\d{3}/.test(t) && /Appliqué/.test(t) && /Annulé/.test(t) && /Refusé/.test(t), t.slice(0, 500));
  verifier('Aucune erreur JavaScript sur ces écrans', erreursJS.length === 0, erreursJS.join(' | '));

  await browser.close();
  server.close();
  try { php.php.kill(); } catch (e) { /* déjà mort */ }
  fs.rmSync(TMP, { recursive: true, force: true });

  const ligne = '─'.repeat(72);
  console.log('\n\n' + ligne + '\nTESTS DU MODULE D’IMPORTATION\n' + ligne);
  let total = 0, ok = 0;
  for (const s of resultats) {
    const o = s.etapes.filter((e) => e.ok).length; total += s.etapes.length; ok += o;
    console.log(`\n${s.ok ? '✓' : '✗'} ${s.nom}   (${o}/${s.etapes.length})`);
    for (const e of s.etapes) if (!e.ok) console.log(`    ✗ ${e.libelle}${e.detail ? '  →  ' + e.detail : ''}`);
  }
  const sOk = resultats.filter((s) => s.ok).length;
  console.log('\n' + ligne + `\nScénarios : ${sOk}/${resultats.length}     Vérifications : ${ok}/${total}\n` + ligne);
  process.exit(sOk === resultats.length ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
