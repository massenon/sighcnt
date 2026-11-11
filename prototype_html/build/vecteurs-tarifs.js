/* =============================================================================
 * VECTEURS DU RÉFÉRENTIEL DE PRIX UNIQUE (PRD-TARIFS, lots T1, T2 et T3)
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
  /* --- 3. Le circuit complet (lot T3) : contrôle d'usage, date passée, Valider en un geste, alerte, retour à l'auteur, famille du centre, pro-forma ------------------ */
  const circuit = await page.evaluate(() => {
    const S = window.SIGH.store, PR = window.SIGH.parcours, C = window.SIGH.core, N = window.SIGH.nav, NT = window.SIGH.notifications, V = window.SIGH.validations;
    const jour = C.iso(C.aujourdhui()), plus = (n) => C.iso(new Date(C.aujourdhui().getTime() + n * 86400000));
    const en = (role, nom) => S.setSession({ role: role, nom: nom || 'V ' + role, nomComplet: nom || 'V ' + role, fonction: role, identifiant: 'v.' + role, secteur: 'DIR' });
    const na = (code, d) => PR.tarifALaDate(code, d || null, false).montant;
    const pt = S.collection('patients').active().filter((p) => !p.externe && !p.assureur)[0];
    const piece = (code, date) => PR.prescrire({ patientCode: pt.code, medecin: 'VEC', diagnostic: 's', actes: [code], date: date }).facture;
    const prop = (o) => PR.proposerTarif(Object.assign({ etatAssure: 'unique', motif: 'Vecteur T3' }, o));
    const R = { aujourdhui: jour, cas: [], _doc: 'Circuit Oui/Non des prix (lot T3) : contrôle d’usage tarif_deja_utilise (proposition et Oui rejoué), cas limites de 5.6, date passée réservée à la DAF et à la Direction, Valider en un geste, alerte et retour à l’auteur, famille du centre des validations, pro-forma à la conversion.' };
    const cas = (nom, r, extra) => R.cas.push(Object.assign({ nom: nom, ok: r.ok === true, code: r.code || null, motif: r.motif || null, geste: r.geste || null }, extra || {}));
    en('da', 'Vecteur DAF');
    /* contrôle d'usage */
    const f1 = piece('MG01');
    const a1 = prop({ code: 'MG01', prixNonAssure: na('MG01') + 100, dateEffet: jour });
    cas('usage : une pièce du jour porte la prestation', a1, { pieceNommee: a1.motif && a1.motif.indexOf(f1.numero) >= 0, nbPieces: a1.nbPieces });
    const a2 = prop({ code: 'MG01', prixNonAssure: na('MG01') + 100, dateEffet: plus(1) });
    cas('usage : le même changement à effet de demain', a2);
    piece('MG01', plus(1) + 'T10:00:00');
    const a3 = PR.deciderTarif(a2.version.id, 'oui');
    cas('usage : rejoué au Oui (pièce émise pendant l’attente)', a3, { statutApres: S.raw().versionsTarif.filter((v) => v.id === a2.version.id)[0].statut });
    cas('Non avec motif (aucune version nouvelle)', PR.deciderTarif(a2.version.id, 'non', { motif: 'Vecteur : une pièce de demain' }), { versions: S.raw().versionsTarif.filter((v) => v.code === 'MG01').length });
    /* deux changements le même jour */
    const b0 = na('MG02');
    const b1 = prop({ code: 'MG02', prixNonAssure: b0 + 100, dateEffet: plus(2) });
    cas('deux changements : un seul en attente', prop({ code: 'MG02', prixNonAssure: b0 + 150, dateEffet: plus(2) }));
    PR.deciderTarif(b1.version.id, 'oui');
    const b3 = prop({ code: 'MG02', prixNonAssure: b0 + 200, dateEffet: plus(2) });
    PR.deciderTarif(b3.version.id, 'oui');
    R.memeJour = { vigueur: na('MG02', plus(2)), attendu: b0 + 200, versions: S.raw().versionsTarif.filter((v) => v.code === 'MG02').sort((a, b) => a.version - b.version).map((v) => v.version + ':' + v.statut) };
    piece('MG02', plus(2) + 'T10:00:00');
    cas('deux changements : la pièce du jour ferme la date', prop({ code: 'MG02', prixNonAssure: b0 + 300, dateEffet: plus(2) }));
    /* date passée */
    piece('MG03', plus(-3) + 'T10:00:00');
    cas('date passée déjà utilisée (DAF, case cochée)', prop({ code: 'MG03', prixNonAssure: na('MG03') + 100, dateEffet: plus(-5), datePassee: true }));
    cas('date passée sans la case (DAF)', prop({ code: 'MG04', prixNonAssure: na('MG04') + 100, dateEffet: plus(-1) }));
    const pa = prop({ code: 'MG04', prixNonAssure: na('MG04') + 100, dateEffet: plus(-1), datePassee: true });
    cas('date passée avec la case (DAF)', pa, { marquee: pa.ok && pa.version.datePassee === true });
    en('admin', 'Vecteur admin');
    cas('date passée sans la case (administrateur)', prop({ code: 'CH01', prixNonAssure: na('CH01') + 100, dateEffet: plus(-1) }));
    cas('date passée avec la case (administrateur)', prop({ code: 'CH01', prixNonAssure: na('CH01') + 100, dateEffet: plus(-1), datePassee: true }));
    cas('décision d’une date passée par l’administrateur', PR.deciderTarif(pa.version.id, 'oui'));
    en('direction', 'Vecteur Direction');
    cas('décision d’une date passée par la Direction', PR.deciderTarif(pa.version.id, 'oui'), { prixHier: na('MG04', plus(-1)), prixAvantHier: na('MG04', plus(-2)) });
    /* cas limites */
    en('da', 'Vecteur DAF');
    cas('prix zéro', prop({ code: 'CH02', prixNonAssure: 0, dateEffet: plus(1) }));
    cas('prix vide', prop({ code: 'CH02', prixNonAssure: '', dateEffet: plus(1) }));
    cas('proposition vide', PR.proposerTarif({ code: 'CH02' }));
    cas('ligne identique', prop({ code: 'CH02', prixNonAssure: na('CH02'), dateEffet: plus(1) }));
    const d4 = PR.proposerTarif({ code: 'CH02', prixNonAssure: na('CH02') + 10, etatAssure: 'manquant', dateEffet: plus(1), motif: 'Vecteur : tiret assuré' });
    cas('tiret de la colonne assurée', d4, { etatAssure: d4.ok ? d4.version.etatAssure : null });
    if (d4.ok) PR.deciderTarif(d4.version.id, 'non', { motif: 'Vecteur : libère la ligne' });
    /* Valider en un geste */
    const v0 = na('CH03');
    const vg = prop({ code: 'CH03', prixNonAssure: v0 + 250, dateEffet: jour, valider: true });
    cas('valider en un geste (DAF)', vg, { statut: vg.ok ? vg.version.statut : null, roleDecision: vg.ok ? vg.version.roleDecision : null, prixApres: na('CH03'), prixAttendu: v0 + 250 });
    const o = N.droitsEcran;
    N.droitsEcran = function (role, id, code) { return id === 'cfg-tarifs' && role === 'comptable' ? { voir: true, editer: true, annuler: false } : o.apply(N, arguments); };
    try {
      en('comptable', 'Vecteur comptable');
      cas('valider par un profil qui édite sans décider', prop({ code: 'CH04', prixNonAssure: na('CH04') + 100, dateEffet: jour, valider: true }));
      const pe = prop({ code: 'CH04', prixNonAssure: na('CH04') + 100, dateEffet: jour });
      cas('proposer par un profil qui édite sans décider', pe, { proposeRole: pe.ok ? pe.version.proposeRole : null });
      R.idEditeur = pe.ok ? pe.version.id : null;
    } finally { N.droitsEcran = o; }
    /* alerte, retour à l'auteur, famille du centre */
    en('da', 'Vecteur DAF');
    const lots = (poste, detaille) => NT.collecter({ poste: poste, detaille: !!detaille }).filter((n) => n.source === 'prix_a_valider' || (n.source === 'poste' && /changement de prix/i.test(n.titre))).map((n) => ({ cle: n.cle, titre: n.titre, detail: n.detail, priorite: n.priorite, lien: n.lien, onglet: n.onglet || null }));
    R.alerte = { da: lots('da', true), caissier: lots('caissier', true), grille: S.raw().versionsTarif.filter((v) => v.statut === 'propose' && v.origine === 'semence-grille').length };
    const non = PR.deciderTarif(R.idEditeur, 'non', { motif: 'Prix hors grille de la clinique' });
    cas('décision Non avec motif', non);
    R.retour = { comptable: lots('comptable', true).map((n) => ({ titre: n.titre, detail: n.detail, priorite: n.priorite, onglet: n.onglet })), apresDa: lots('da', true).map((n) => n.cle).filter((c) => c !== 'prix:grille') };
    const centre = V.referentielsAValider().filter((x) => x.famille === 'prix')[0];
    R.centre = { famille: centre && { libelle: centre.libelle, profil: centre.profil, ecran: centre.ecran, enAttente: centre.enAttente }, reelles: S.raw().versionsTarif.filter((v) => v.statut === 'propose').length,
      depuisCentre: V.validerReferentiel('prix', (S.raw().versionsTarif.filter((v) => v.statut === 'propose')[0] || {}).id).code };
    /* Oui à tout : encadré */
    R.ouiATout = { sansComparaison: PR.deciderTousTarifs({ ids: [] }).code };
    en('caissier', 'Vecteur caissier');
    R.ouiATout.sansDroit = PR.deciderTousTarifs({ comparaisonAffichee: true, ids: [] }).code;
    en('da', 'Vecteur DAF');
    const t1 = prop({ code: 'CH05', prixNonAssure: na('CH05') + 100, dateEffet: plus(1) });
    const t2 = prop({ code: 'CH06', prixNonAssure: na('CH06') + 100, dateEffet: plus(1) });
    piece('CH06', plus(1) + 'T10:00:00');
    const tout = PR.deciderTousTarifs({ comparaisonAffichee: true, ids: [t1.version.id, t2.version.id] });
    R.ouiATout.resultat = { acceptees: tout.acceptees.map((x) => x.code), refusees: tout.refusees.map((x) => x.code + ':' + x.refus), exclues: tout.exclues.length };
    /* pro-forma */
    R.proforma = { defaut: PR.validiteProformaJours(), propose: PR.VALIDITE_PROFORMA_DEFAUT };
    const P = na('SO17');
    const mk = (n, num) => S.collection('factures').insert({ numero: 'PRO-2026-8' + num, date: plus(-n) + 'T09:00:00', patientCode: pt.code, patient: pt.nom, proforma: true, statut: 'actif', type: 'Consultation', montantTTC: P,
      lignes: [{ id: 'L001', categorie: 'acte', designation: 'Vecteur : estimation', quantite: 1, prixUnitaire: P, montant: P, acteCode: 'SO17' }] }).record;
    const PA = mk(10, '0001'), PB = mk(40, '0002');
    prop({ code: 'SO17', prixNonAssure: P + 300, dateEffet: jour, valider: true });
    const ec = (f) => { const e = PR.ecartProforma(f.id); return { regle: e.regle, age: e.ageJours, validite: e.validiteJours, ancien: e.lignes[0].ancien, nouveau: e.lignes[0].nouveau, retenu: e.lignes[0].retenu, ecart: e.ecartTotal }; };
    R.proforma.dixJours = ec(PA); R.proforma.quaranteJours = ec(PB);
    R.proforma.regle = PR.definirValiditeProforma({ jours: 5, motif: 'Vecteur' }); R.proforma.dixJoursApres = ec(PA);
    R.proforma.invalides = ['abc', '', '2.5', '-1', '400'].map((j) => PR.definirValiditeProforma({ jours: j }).code);
    en('caissier', 'Vecteur caissier');
    R.proforma.reserve = PR.definirValiditeProforma({ jours: 99 }).code;
    R.proforma.venteNonProforma = PR.ecartProforma(S.raw().factures.filter((f) => !f.proforma)[0].id).code;
    return R;
  });
  const m = Object.assign({}, naissance, { moteur: moteur, circuit: circuit });
  fs.writeFileSync(sortie, JSON.stringify(m, null, 1) + '\n');
  console.log('Vecteurs écrits : ' + sortie + ' (erreurs JS : ' + erreurs.length + ')');
  await br.close(); srv.close(); try { php.php.kill(); } catch (e) { /* mort */ }
  process.exit(erreurs.length ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
