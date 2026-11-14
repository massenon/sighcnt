/* =============================================================================
 * VECTEURS DES PRIX D'ACHAT DES PRODUITS (PRD-TARIFS, lot T5, porté au poste par le lot TFIN)
 * -----------------------------------------------------------------------------
 *   node build/vecteurs-tarifs-produits.js [sortie.json]      (défaut : packages/domaine/test/vecteurs/tarifs_produits.json)
 *
 * Les vecteurs ne se lisent pas dans le code : ils se TIRENT de la maquette en marche. Le générateur ouvre l'écran réel « Tarifs et prix » dans Chrome,
 * pilote le moteur des produits (proposition, refus nommés dont RG-02, création de la version 1, accesseur daté, migration) sur les articles RÉELS du jeu. Le poste (lot TFIN)
 * rejoue ces cas contre le domaine Dart. Banc isolé : SIGH_PORT_PHP, SIGH_BASE_TEST (nom portant « banc »), SIGH_PORT_TEST, CHROME_PATH. L'horloge du banc est
 * le 16/08/2026 : toute date du relevé est déterministe.
 * ========================================================================== */
'use strict';
const fs = require('fs'), path = require('path'), http = require('http');
const ROOT = path.resolve(__dirname, '..');
const REPO = path.resolve(ROOT, '..');
const BANC = require('./_banc');
const puppeteer = require('puppeteer');
const PORT = Number(process.env.SIGH_PORT_TEST) || 8096;

(async () => {
  const sortie = process.argv[2] || path.join(REPO, 'packages/domaine/test/vecteurs/tarifs_produits.json');
  const php = await BANC.demarrerPhp(ROOT);
  if (!php.php) { console.error(php.raison); process.exit(1); }
  const vidage = await BANC.banc('reinitialiser');
  if (vidage.erreur) { console.error(vidage); try { php.php.kill(); } catch (e) { /* mort */ } process.exit(1); }
  const MIME = { '.php': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css', '.woff2': 'font/woff2', '.png': 'image/png', '.jpeg': 'image/jpeg' };
  const srv = http.createServer((req, res) => {
    if (req.url.indexOf('/api/') === 0) { BANC.relayer(req, res); return; }
    const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '') || 'index.php';
    const f = path.join(ROOT, rel);
    if (!fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' }); fs.createReadStream(f).pipe(res);
  }).listen(PORT);
  const br = await puppeteer.launch({ executablePath: process.env.CHROME_PATH, headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const page = await br.newPage(); await BANC.poserSession(page);
  page.setDefaultNavigationTimeout(180000); page.setDefaultTimeout(180000);
  const erreurs = []; page.on('pageerror', (e) => erreurs.push(e.message));
  await page.goto('http://127.0.0.1:' + PORT + '/pages/cfg-tarifs.php', { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => { const S = window.SIGH && window.SIGH.store; const c = document.getElementById('page-content'); return S && (!S.faitAutorite || S.faitAutorite()) && c && c.children.length > 0; }, { timeout: 150000 });
  await new Promise((r) => setTimeout(r, 800));

  const R = await page.evaluate(() => {
    const S = window.SIGH.store, PR = window.SIGH.parcours, C = window.SIGH.core, TA = window.SIGH.data.TARIFS;
    const jour = C.iso(C.aujourdhui()), plus = (n) => C.iso(new Date(C.aujourdhui().getTime() + n * 86400000));
    S.setSession({ role: 'admin', nom: 'VECTEURS', nomComplet: 'VECTEURS', fonction: 'direction', identifiant: 'vecteurs', secteur: 'DIR' });
    const R = { _doc: 'Prix d’achat des produits (lot T5 de la maquette, porté au poste par le lot TFIN) : RG-02, refus nommés, version 1 à la création, accesseur daté. Chaque cas porte l’ÉTAT dont il part (fiche, prestation, versions, pièces).', aujourdhui: jour, role: 'admin', auteur: 'VECTEURS', cas: [], lectures: [] };
    const brut = () => S.raw();
    const prods = brut().produits.filter((p) => p.statut !== 'archive');
    const avecPrix = (f) => prods.filter((p) => f(p) && typeof p.prixAchat === 'number' && p.prixAchat > 0 && TA.lire().parProduit[p.code]);
    const meds = avecPrix((p) => p.categorie === 'medicament'), autres = avecPrix((p) => p.categorie !== 'medicament');
    const etat = (code, avecFactures) => {
      const b = brut(), t = b.tarifs.filter((x) => x.code === code), f = b.produits.filter((x) => x.code === code && x.statut !== 'archive');
      /* Seuls les champs que le moteur lit : la fiche complète (source, lot d'import…) n'apporte rien au vecteur. */
      const mince = f.map((x) => { const o = {}; ['id', 'code', 'designation', 'categorie', 'unite', 'prixAchat', 'prixVente', 'statut'].forEach((k) => { if (x[k] !== undefined) o[k] = x[k]; }); return o; });
      return { produits: mince, tarifs: t, versions: b.versionsTarif.filter((v) => v.code === code).sort((a, b2) => a.version - b2.version), factures: !avecFactures ? [] : b.factures.filter((x) => x.statut !== 'archive' && !x.proforma && (x.lignes || []).some((l) => l.produitId && f.some((p) => p.id === l.produitId))).map((x) => ({ id: x.id, numero: x.numero, date: x.date, statut: x.statut, lignes: x.lignes.filter((l) => l.produitId).map((l) => ({ produitId: l.produitId })) })) };
    };
    const cas = (nom, code, o, ecrire) => {
      const avant = etat(code, /vendu/.test(nom));
      const r = ecrire ? PR.proposerTarif(o) : PR.proposerTarif(Object.assign({}, o, { essai: true }));
      const e = { nom: nom, code: code, demande: o, ecrit: !!ecrire, avant: avant, ok: r.ok === true, refus: r.ok ? null : { code: r.code, motif: r.motif, geste: r.geste } };
      if (r.ok && ecrire) { e.version = r.version; e.identite = r.identite || null; e.valideeEnUnGeste = !!r.valideeEnUnGeste; }
      R.cas.push(e); return r;
    };
    const M = meds.slice(0, 12), A = autres.slice(0, 4);
    /* les refus (essai : rien n'est écrit) */
    cas('RG-02 : un médicament avec un prix de vente différent', M[1].code, { code: M[1].code, prixNonAssure: M[1].prixAchat + 10, prixVente: M[1].prixAchat + 40, dateEffet: plus(2), motif: 'x' });
    cas('prix zéro', M[2].code, { code: M[2].code, prixNonAssure: 0, dateEffet: plus(2), motif: 'x' });
    cas('prix absent en changement', M[2].code, { code: M[2].code, prixNonAssure: '', dateEffet: plus(2), motif: 'x' });
    cas('prix décimal', M[2].code, { code: M[2].code, prixNonAssure: 12.5, dateEffet: plus(2), motif: 'x' });
    cas('prix de vente décimal', A[0].code, { code: A[0].code, prixNonAssure: A[0].prixAchat + 5, prixVente: 99.5, dateEffet: plus(2), motif: 'x' });
    cas('sans motif', M[2].code, { code: M[2].code, prixNonAssure: M[2].prixAchat + 5, dateEffet: plus(2), motif: '' });
    cas('sans date d’effet', M[2].code, { code: M[2].code, prixNonAssure: M[2].prixAchat + 5, dateEffet: '', motif: 'x' });
    cas('date passée sans case', M[2].code, { code: M[2].code, prixNonAssure: M[2].prixAchat + 5, dateEffet: plus(-1), motif: 'x' });
    cas('prix inchangé', M[3].code, { code: M[3].code, prixNonAssure: M[3].prixAchat, dateEffet: plus(2), motif: 'x' });
    cas('produit introuvable', 'ZZ-INCONNU', { code: 'ZZ-INCONNU', prixNonAssure: 500, dateEffet: plus(2), motif: 'x' });
    cas('code d’une prestation (création refusée)', 'SO02', { code: 'SO02', prixNonAssure: 500, creation: { famille: 'PRODUIT', libelle: 'Doublon' }, motif: 'x' });
    /* un article déjà utilisé par une facture : la date d'effet qui précède une pièce est refusée (contrôle d'usage) */
    const pr5 = M[5], fac = S.collection('factures').insert({ numero: 'FAC-VEC-PRD', date: jour, statut: 'emise', patientId: null, lignes: [{ produitId: pr5.id, designation: pr5.designation, quantite: 1, prixUnitaire: pr5.prixAchat }] });
    cas('article déjà vendu depuis cette date', pr5.code, { code: pr5.code, prixNonAssure: pr5.prixAchat + 5, dateEffet: jour, motif: 'x' });
    if (fac && fac.record) S.collection('factures').archive(fac.record.id);
    /* les écritures réelles */
    const v1 = cas('médicament : changement futur proposé', M[0].code, { code: M[0].code, prixNonAssure: M[0].prixAchat + 50, dateEffet: plus(3), motif: 'Vecteur : nouveau tarif du fournisseur', source: 'Facture VEC' }, true);
    cas('un seul changement en attente', M[0].code, { code: M[0].code, prixNonAssure: M[0].prixAchat + 60, dateEffet: plus(4), motif: 'x' });
    cas('hors médicament : prix de vente propre', A[1].code, { code: A[1].code, prixNonAssure: A[1].prixAchat + 10, prixVente: A[1].prixAchat + 40, dateEffet: plus(3), motif: 'Vecteur : prix de vente propre' }, true);
    cas('médicament : valider en un geste, date passée motivée', M[4].code, { code: M[4].code, prixNonAssure: M[4].prixAchat + 25, dateEffet: plus(-2), datePassee: true, valider: true, motif: 'Vecteur : correction' }, true);
    cas('médicament : valider en un geste, date future', M[6].code, { code: M[6].code, prixNonAssure: M[6].prixAchat + 30, dateEffet: plus(3), valider: true, motif: 'Vecteur : validation d’emblée' }, true);
    /* les lectures datées (l'accesseur) : avant et après les dates d'effet */
    const lire = (code, date) => { const p = brut().produits.filter((x) => x.code === code && x.statut !== 'archive')[0]; const r = PR.prixProduitALaDate(p, date); return { absent: r.absent === true, achat: r.achat, vente: r.vente, version: r.version == null ? null : r.version, dateEffet: r.dateEffet || null, motif: r.motif || null }; };
    [M[0].code, A[1].code, M[4].code, M[6].code, M[7].code, A[2].code].forEach((code) => {
      [null, plus(2), plus(3), plus(10), '2020-01-01'].forEach((d) => R.lectures.push({ code: code, date: d, attendu: lire(code, d), etat: etat(code) }));
    });
    /* Un code inconnu n'est PAS un produit : `evaluerProposition` l'envoie par la voie des prestations (PRESTATION_INTROUVABLE, texte des prestations) ; l'accesseur, lui, ne se lit que sur une fiche. */
    /* la création : la version 1 se pose par la MÊME voie (valide, sans date d'effet) ; sans prix d'achat, `manquant` */
    const fiche = (code, extra) => S.collection('produits').insert(Object.assign({ code: code, designation: 'Article ' + code, categorie: 'consommable', unite: 'unité', statut: 'actif', stockGros: 0, stockDetail: 0, stock: 0 }, extra)).record;
    R.creations = [];
    [['VEC-NEUF-1', { prixAchat: 700 }], ['VEC-NEUF-2', { categorie: 'medicament', prixAchat: 450 }], ['VEC-NEUF-3', {}]].forEach(([code, extra]) => {
      const f = fiche(code, extra), avant = etat(code);
      ['source', 'lotImport', 'valoriseSage'].forEach((k) => { delete f[k]; });
      const r = PR.creerPrixProduit(f, { motif: undefined });
      R.creations.push({ code: code, fiche: f, avant: { tarifs: avant.tarifs, versions: avant.versions }, ok: r.ok === true, version: r.version || null, identite: r.identite || null, reutilise: r.reutilise === true, apres: etat(code).versions });
    });
    /* la migration d'un produit (reprise) : version 1 de `migrerProduits`, prix absent = manquant */
    const crafts = [{ code: 'MIG-1', designation: 'Un médicament', categorie: 'medicament', prixAchat: 300, prixVente: 300, statut: 'actif' }, { code: 'MIG-2', designation: 'Un consommable avec prix de vente', categorie: 'consommable', prixAchat: 500, prixVente: 650, statut: 'actif' },
      { code: 'MIG-3', designation: 'Sans prix', categorie: 'consommable', statut: 'actif' }, { code: 'MIG-4', designation: 'Prix zéro', categorie: 'medicament', prixAchat: 0, statut: 'actif' }, { code: 'MIG-5', designation: 'Archivé', categorie: 'medicament', prixAchat: 10, statut: 'archive' },
      { code: 'MIG-6', designation: 'Valorisé à titre provisoire', categorie: 'consommable', prixAchat: 120, valorisationProvisoire: true, sourceValorisation: 'Inventaire initial (reprise)', statut: 'actif' }];
    const m = TA.migrerProduits(crafts, { origine: 'reprise' });
    R.migration = { entree: crafts, tarifs: m.tarifs, versions: m.versions };
    /* le correctif de fiche : la fiche suit la version en vigueur */
    R.correctifs = [];
    [[{ code: 'C1', categorie: 'medicament', prixAchat: 100, prixVente: 100 }, { na: 120, vrs: { prixNonAssure: 120 } }], [{ code: 'C2', categorie: 'consommable', prixAchat: 100, prixVente: 100 }, { na: 120, vrs: { prixNonAssure: 120, prixVente: 200 } }],
      [{ code: 'C3', categorie: 'medicament', prixAchat: 100, prixVente: 100 }, { na: 100, vrs: { prixNonAssure: 100 } }], [{ code: 'C4', categorie: 'medicament', prixAchat: 100, prixVente: 100 }, { na: null, vrs: { etatNonAssure: 'manquant' } }]].forEach(([doc, s]) => {
      R.correctifs.push({ doc: doc, s: s, attendu: TA.correctifProduit(doc, null, s) });
    });
    return R;
  });
  fs.writeFileSync(sortie, JSON.stringify(R, null, 1));
  console.log('Vecteurs écrits : ' + sortie + ' (' + R.cas.length + ' cas, ' + R.lectures.length + ' lectures, ' + R.creations.length + ' créations ; erreurs JS : ' + erreurs.length + ')');
  if (erreurs.length) console.error(erreurs.slice(0, 5));
  await br.close(); srv.close(); try { php.php.kill(); } catch (e) { /* mort */ }
  process.exit(erreurs.length ? 1 : 0);
})();
