/* =============================================================================
 * VECTEURS DU RÉFÉRENTIEL DE PRIX UNIQUE (PRD-TARIFS, lots T1 et T2)
 * -----------------------------------------------------------------------------
 *   node build/vecteurs-tarifs.js [sortie.json]      (défaut : packages/domaine/test/vecteurs/tarifs.json)
 *
 * Les vecteurs ne se lisent pas dans le code : ils se TIRENT de la maquette en marche. Le générateur ouvre l'écran réel « Tarifs et prix » dans Chrome,
 * pilote le moteur (migration, résolution à une date, proposition, décision, refus nommés) et relève ce que l'écran affiche. Le poste (lot T6) rejouera
 * ces cas contre le domaine Dart. Banc isolé : SIGH_PORT_PHP, SIGH_BASE_TEST (nom portant « banc »), SIGH_PORT_TEST, CHROME_PATH. L'horloge du banc est
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
  const sortie = process.argv[2] || path.join(REPO, 'packages/domaine/test/vecteurs/tarifs.json');
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

  /* --- 1. La migration et l'écran tels qu'ils naissent --------------------------------------------------------------------------------------------- */
  const naissance = await page.evaluate(async () => {
    const S = window.SIGH.store, TA = window.SIGH.data.TARIFS, h = TA.lire(), pause = (ms) => new Promise((r) => setTimeout(r, ms));
    const brut = S.raw();
    const fiche = (code) => { const p = h.parCode[code]; return { tarif: p, versions: brut.versionsTarif.filter((v) => v.code === p.code).sort((a, b) => a.version - b.version) }; };
    const R = { _doc: 'Référentiel de prix unique : migration des listes d’avant (73 actes, 147 lignes de grille, 48 analyses) sans changer un prix, écran « Tarifs et prix » tel que la maquette le rend.' };
    const par = (f) => brut.tarifs.filter(f).length;
    R.migration = { tarifs: brut.tarifs.length, versions: brut.versionsTarif.length, versions1: brut.versionsTarif.filter((v) => v.version === 1).length, propositionsGrille: brut.versionsTarif.filter((v) => v.origine === 'semence-grille').length,
      parFamille: brut.tarifs.reduce((o, p) => { o[p.famille] = (o[p.famille] || 0) + 1; return o; }, {}), avecActe: par((p) => p.codeActe), avecGrille: par((p) => p.codeGrille), avecAnalyse: par((p) => p.codeAnalyse),
      actesEtGrille: par((p) => p.codeActe && p.codeGrille), analysesEtGrille: par((p) => p.codeAnalyse && p.codeGrille), grilleSeule: par((p) => p.codeGrille && !p.codeActe && !p.codeAnalyse),
      etatsAssure: brut.versionsTarif.reduce((o, v) => { o[v.etatAssure] = (o[v.etatAssure] || 0) + 1; return o; }, {}), version: brut._version };
    R.exemples = {};
    ['SO02', 'MG01', 'HO02', 'GY-SAA', 'L01', 'L05', 'IMG-ECHO-PEL', 'CERT-DEC', 'LAB-SDW', 'IMG-RX-THO', 'AMIU'].forEach((c) => { R.exemples[c] = fiche(c); });
    const m = S.migrerTarifsDepuis({ actes: brut.actes.filter((a) => !!h.parActe[a.code]), analyses: TA.semence.analyses, catalogueTarifs: [] });
    R.ecarts = { parType: m.ecarts.reduce((o, e) => { o[e.type] = (o[e.type] || 0) + 1; return o; }, {}), analysesSansGrille: m.ecarts.filter((e) => e.type === 'analyse-sans-grille').map((e) => e.code).sort(), grilleSansAnalyse: m.ecarts.filter((e) => e.type === 'grille-sans-analyse').map((e) => e.code) };
    const lire = async (id) => { const t = document.querySelector('[data-tab="' + id + '"]'); if (t) t.click(); await pause(500); const c = document.getElementById('page-content'); return { entetes: [...c.querySelectorAll('thead th')].map((x) => x.textContent.replace(/\s+/g, ' ').trim()), lignes: c.querySelectorAll('tbody tr').length, premiere: (c.querySelector('tbody tr') || { textContent: '' }).textContent.replace(/\s+/g, ' ').trim() }; };
    R.ecran = { titre: (document.querySelector('h1') || {}).textContent, onglets: [...document.querySelectorAll('#page-content [data-tab]')].map((t) => t.textContent.trim()), kpi: [...document.querySelectorAll('#page-content .kpi')].map((k) => k.textContent.replace(/\s+/g, ' ').trim()), vues: {} };
    for (const id of ['prestations', 'analyses', 'imagerie', 'produits', 'alertes']) R.ecran.vues[id] = await lire(id);
    R.rubriques = window.SIGH.nav.RUBRIQUES.filter((r) => r.ecran === 'cfg-tarifs').map((r) => ({ onglet: r.onglet, label: r.label }));
    return R;
  });

  /* --- 2. La résolution à une date, la proposition et la décision, avec leurs refus nommés ------------------------------------------------------------ */
  const moteur = await page.evaluate(() => {
    const S = window.SIGH.store, PR = window.SIGH.parcours, C = window.SIGH.core;
    const jour = C.iso(C.aujourdhui()), plus = (n) => C.iso(new Date(C.aujourdhui().getTime() + n * 86400000));
    S.setSession({ role: 'admin', nom: 'VECTEURS', nomComplet: 'VECTEURS', fonction: 'direction', identifiant: 'vecteurs', secteur: 'DIR' });
    const R = { aujourdhui: jour, cas: [] };
    const lire = (code, date, assure) => { const r = PR.tarifALaDate(code, date, assure); return { montant: r.montant, tarif: r.tarif || null, motif: r.motif || null, version: r.version || null, absent: r.absent === true, reserveSos: r.reserveSos === true }; };
    const refus = (nom, r) => R.cas.push({ nom: nom, ok: r.ok === true, code: r.code || null, motif: r.motif || null, geste: r.geste || null });
    const grille = (code) => ({ nonAssure: lire(code, null, false), assure: lire(code, null, true) });
    const base = PR.tarifALaDate('SO02', null, false).montant, baseA = PR.tarifALaDate('SO02', null, true).montant;
    /* refus nommés de la proposition */
    refus('prix zéro', PR.proposerTarif({ code: 'SO02', prixNonAssure: 0, etatAssure: 'unique', dateEffet: plus(1), motif: 'x' }));
    refus('prix décimal', PR.proposerTarif({ code: 'SO02', prixNonAssure: 1250.5, etatAssure: 'unique', dateEffet: plus(1), motif: 'x' }));
    refus('prix absent', PR.proposerTarif({ code: 'SO02', prixNonAssure: null, etatAssure: 'unique', dateEffet: plus(1), motif: 'x' }));
    refus('colonne assurée annoncée sans montant', PR.proposerTarif({ code: 'SO02', prixNonAssure: base + 1, etatAssure: 'montant', prixAssure: null, dateEffet: plus(1), motif: 'x' }));
    refus('sans motif', PR.proposerTarif({ code: 'SO02', prixNonAssure: base + 1, etatAssure: 'unique', dateEffet: plus(1), motif: '' }));
    refus('sans date d’effet', PR.proposerTarif({ code: 'SO02', prixNonAssure: base + 1, etatAssure: 'unique', dateEffet: '', motif: 'x' }));
    refus('date passée', PR.proposerTarif({ code: 'SO02', prixNonAssure: base + 1, etatAssure: 'unique', dateEffet: plus(-1), motif: 'x' }));
    refus('prix inchangé', PR.proposerTarif({ code: 'SO02', prixNonAssure: base, etatAssure: 'montant', prixAssure: baseA, dateEffet: plus(1), motif: 'x' }));
    refus('prestation introuvable', PR.proposerTarif({ code: 'NEXISTE', prixNonAssure: 100, etatAssure: 'unique', dateEffet: plus(1), motif: 'x' }));
    refus('code existant (alias)', PR.proposerTarif({ code: 'SIV', creation: { libelle: 'Doublon', famille: 'AMI' }, prixNonAssure: 100, etatAssure: 'unique', dateEffet: plus(1), motif: 'x' }));
    /* un changement futur : la proposition ne change rien, le Oui prend effet à sa date, un second changement n'est pas permis en attendant */
    const p1 = PR.proposerTarif({ code: 'SO02', prixNonAssure: base + 200, etatAssure: 'montant', prixAssure: baseA + 100, dateEffet: plus(3), motif: 'Vecteur : changement futur' });
    const avantOui = { aujourdhui: lire('SO02', null, false), dansTroisJours: lire('SO02', plus(3), false) };
    refus('un seul changement en attente', PR.proposerTarif({ code: 'SO02', prixNonAssure: base + 300, etatAssure: 'unique', dateEffet: plus(4), motif: 'x' }));
    const oui = PR.deciderTarif(p1.version.id, 'oui');
    R.futur = { proposee: { id: p1.version.id, statut: p1.version.statut }, avantOui: avantOui, decision: { ok: oui.ok === true, statut: oui.version && oui.version.statut, role: oui.version && oui.version.roleDecision },
      apresOui: { aujourdhui: lire('SO02', null, false), veille: lire('SO02', plus(2), false), jourDit: lire('SO02', plus(3), false), jourDitAssure: lire('SO02', plus(3), true), lendemain: lire('SO02', plus(10), false), grilleSIV: grille('SIV') } };
    refus('décision rejouée', PR.deciderTarif(p1.version.id, 'oui'));
    /* un Non : motif exigé, rien ne change */
    const p2 = PR.proposerTarif({ code: 'SO12', prixNonAssure: PR.tarifALaDate('SO12', null, false).montant + 50, etatAssure: 'unique', dateEffet: plus(1), motif: 'Vecteur : à refuser' });
    refus('refus sans motif', PR.deciderTarif(p2.version.id, 'non', {}));
    const non = PR.deciderTarif(p2.version.id, 'non', { motif: 'Vecteur : hors grille' });
    R.refus = { statut: non.version && non.version.statut, motif: non.version && non.version.motifDecision, prixInchange: PR.tarifALaDate('SO12', plus(1), false).montant === PR.tarifALaDate('SO12', null, false).montant };
    /* une proposition « à dater » : la décision fixe la date */
    const v2 = S.raw().versionsTarif.filter((v) => v.origine === 'semence-grille' && v.statut === 'propose')[0];
    R.aDater = { id: v2.id, code: v2.code, avant: lire(v2.code, null, false) };
    refus('Oui sans date d’effet à une proposition à dater', PR.deciderTarif(v2.id, 'oui', {}));
    refus('Oui avec une date passée', PR.deciderTarif(v2.id, 'oui', { dateEffet: plus(-1) }));
    const ouiDate = PR.deciderTarif(v2.id, 'oui', { dateEffet: plus(5) });
    R.aDater.apresOui = { ok: ouiDate.ok === true, dateEffet: ouiDate.version && ouiDate.version.dateEffet, aujourdhui: lire(v2.code, null, false), ledit: lire(v2.code, plus(5), false) };
    /* les droits : la liste de rôles décide, jamais « éditer » */
    R.droits = {};
    ['admin', 'da', 'direction', 'comptable', 'caissier', 'laborantin', 'stock', 'medecin', 'reception'].forEach((role) => {
      S.setSession({ role: role, nom: 'V ' + role, nomComplet: 'V ' + role, fonction: role, identifiant: 'v.' + role, secteur: 'DIR' });
      R.droits[role] = { decider: PR.peutDeciderTarif(), proposer: PR.peutProposerTarif(), refusDecision: PR.peutDeciderTarif() ? null : PR.deciderTarif('X@x@1', 'oui').code };
    });
    S.setSession({ role: 'admin', nom: 'VECTEURS', nomComplet: 'VECTEURS', fonction: 'direction', identifiant: 'vecteurs', secteur: 'DIR' });
    /* une version est immuable */
    const col = S.collection('versionsTarif'), id = 'SO12@origine@1';
    R.immuable = { prix: col.update(id, { prixNonAssure: 1 }) === null, archive: col.archive(id, 'x') === null, retrait: col.update(id, { statut: 'retire' }) === null };
    /* les voies lisent la même version : la prescription, avec une carte valide ou non */
    R.voies = { SO02: grille('SO02'), SIV: grille('SIV'), 'IMG-ECHO-PEL': grille('IMG-ECHO-PEL'), 'CERT-DEC': grille('CERT-DEC'), L01: grille('L01'), 'LAB-GGT': grille('LAB-GGT') };
    R.projection = { actes: S.raw().actes.filter((a) => a.code === 'SO02').map((a) => [a.code, a.prix, a.prixNonAssure, a.prixAssure]), catalogue: S.raw().catalogueTarifs.filter((a) => a.code === 'SIV').map((a) => [a.code, a.prixNonAssure, a.prixAssure]), parite: S.paritesTarifs().length };
    return R;
  });
  const m = Object.assign({}, naissance, { moteur: moteur });
  fs.writeFileSync(sortie, JSON.stringify(m, null, 1) + '\n');
  console.log('Vecteurs écrits : ' + sortie + ' (erreurs JS : ' + erreurs.length + ')');
  await br.close(); srv.close(); try { php.php.kill(); } catch (e) { /* mort */ }
  process.exit(erreurs.length ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
