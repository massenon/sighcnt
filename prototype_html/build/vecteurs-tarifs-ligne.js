/* =============================================================================
 * VECTEURS DU PRIX D'UNE LIGNE DE PRESCRIPTION (lot TARIF-FIX, 16/11/2026)
 * -----------------------------------------------------------------------------
 *   node build/vecteurs-tarifs-ligne.js [sortie.json]      (défaut : packages/domaine/test/vecteurs/tarifs_ligne.json)
 *
 * Les vecteurs se TIRENT de la maquette en marche : le générateur ouvre l'écran réel « Nouvelle ordonnance » dans Chrome, y fait tourner le moteur pur
 * (`D.TARIFS.prixDeLigne`, `D.TARIFS.codePris`) sur un index de sonde qui couvre chaque branche (deux colonnes, colonne vide, version future, proposition en
 * attente, version refusée, alias, archive, prix nul, code absent), relève la même lecture sur le référentiel semé (certificats, consultation, analyse) et
 * les textes que l'écran affiche sous un acte sans prix. Le domaine Dart (`ReferentielTarifs.prixDeLigne`, `tarCodePris`) les rejoue. Banc isolé :
 * SIGH_PORT_PHP, SIGH_BASE_TEST (nom portant « test »), SIGH_PORT_TEST, CHROME_PATH. L'horloge du banc est le 16/08/2026.
 * ========================================================================== */
'use strict';
const fs = require('fs'), path = require('path'), http = require('http');
const ROOT = path.resolve(__dirname, '..');
const REPO = path.resolve(ROOT, '..');
const BANC = require('./_banc');
const puppeteer = require('puppeteer');
const PORT = Number(process.env.SIGH_PORT_TEST) || 8096;
let PHP = null;   /* tué aussi sur une erreur : un serveur orphelin occuperait le port du banc suivant */

(async () => {
  const sortie = process.argv[2] || path.join(REPO, 'packages/domaine/test/vecteurs/tarifs_ligne.json');
  const php = await BANC.demarrerPhp(ROOT);
  PHP = php.php;
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
  const peindre = async (rel) => {
    await page.goto('http://127.0.0.1:' + PORT + '/pages/' + rel, { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => { const S = window.SIGH && window.SIGH.store; const c = document.getElementById('page-content'); return S && (!S.faitAutorite || S.faitAutorite()) && c && c.children.length > 0; }, { timeout: 150000 });
    await new Promise((r) => setTimeout(r, 800));
  };
  await peindre('m2-ordonnance-nouvelle.php');

  const R = await page.evaluate(() => {
    const TA = window.SIGH.data.TARIFS, PR = window.SIGH.parcours;
    const out = { _doc: 'Prix d’une ligne de prescription (lot TARIF-FIX) : un montant strictement positif, ou « prix à définir » avec sa cause, son motif et son geste. Jamais un zéro. Tiré de la maquette en marche (écran « Nouvelle ordonnance »).' };
    /* --- 1. L'index de sonde : chaque branche ------------------------------------------------------------------------------------------------------------- */
    const tarifs = [
      { code: 'A1', codeActe: 'A1', libelle: 'Acte assurable à deux colonnes', famille: 'ACTE', assurable: true, statut: 'actif' },
      { code: 'A2', codeActe: 'A2', libelle: 'Acte assurable, colonne assurée vide', famille: 'ACTE', assurable: true, statut: 'actif' },
      { code: 'A3', codeActe: 'A3', libelle: 'Acte à prix unique', famille: 'ACTE', statut: 'actif' },
      { code: 'A4', codeActe: 'A4', libelle: 'Acte, colonne non assurée vide', famille: 'ACTE', assurable: true, statut: 'actif' },
      { code: 'A5', codeActe: 'A5', libelle: 'Acte seulement proposé', famille: 'ACTE', statut: 'actif' },
      { code: 'A6', codeActe: 'A6', libelle: 'Acte à effet futur', famille: 'ACTE', statut: 'actif' },
      { code: 'A7', codeActe: 'A7', libelle: 'Acte refusé', famille: 'ACTE', statut: 'actif' },
      { code: 'A8', codeActe: 'A8', libelle: 'Acte à deux versions', famille: 'ACTE', statut: 'actif' },
      { code: 'A9', codeActe: 'A9', libelle: 'Acte à prix nul', famille: 'ACTE', statut: 'actif' },
      { code: 'A10', codeActe: 'A10', libelle: 'Acte non couvert', famille: 'ACTE', assurable: true, statut: 'actif' },
      { code: 'G1', codeGrille: 'G1', libelle: 'Certificat de sonde', famille: 'CERTIFICAT', assurable: 'sos', statut: 'actif' },
      { code: 'G2', codeGrille: 'G2', libelle: 'Soin non couvert', famille: 'AMI', assurable: true, statut: 'actif' },
      { code: 'G3', codeGrille: 'G3', libelle: 'Consultation de sonde', famille: 'CONSULTATION', assurable: true, statut: 'actif' },
      { code: 'G4', codeGrille: 'G4', libelle: 'Ligne de grille, colonne assurée vide', famille: 'GYNECO', assurable: true, statut: 'actif' },
      { code: 'L1', codeAnalyse: 'L1', codeGrille: 'LAB-X', codesAlias: ['LAB-X'], libelle: 'Analyse à prix unique', famille: 'LABO', statut: 'actif' },
      { code: 'L2', codeAnalyse: 'L2', libelle: 'Analyse à deux colonnes', famille: 'LABO', statut: 'actif' },
      { code: 'L3', codeAnalyse: 'L3', libelle: 'Analyse sans prix', famille: 'LABO', statut: 'actif' },
      { code: 'L4', codeAnalyse: 'L4', libelle: 'Analyse, colonne assurée vide', famille: 'LABO', statut: 'actif' },
      { code: 'AR1', codeActe: 'AR1', libelle: 'Acte archivé', famille: 'ACTE', statut: 'archive' },
    ];
    const versions = [
      { code: 'A1', version: 1, prixNonAssure: 9000, prixAssure: 6000, etatAssure: 'montant', statut: 'valide' },
      { code: 'A2', version: 1, prixNonAssure: 4000, prixAssure: null, etatAssure: 'manquant', statut: 'valide' },
      { code: 'A3', version: 1, prixNonAssure: 2000, prixAssure: null, etatAssure: 'unique', statut: 'valide' },
      { code: 'A4', version: 1, prixNonAssure: null, etatNonAssure: 'manquant', prixAssure: 3000, etatAssure: 'montant', statut: 'valide' },
      { code: 'A5', version: 1, prixNonAssure: 2500, prixAssure: null, etatAssure: 'unique', statut: 'propose', dateEffet: '2026-08-16' },
      { code: 'A6', version: 1, prixNonAssure: 3500, prixAssure: null, etatAssure: 'unique', statut: 'valide', dateEffet: '2026-08-20' },
      { code: 'A6', version: 2, prixNonAssure: 3700, prixAssure: null, etatAssure: 'unique', statut: 'valide', dateEffet: '2026-09-01' },
      { code: 'A7', version: 1, prixNonAssure: 1900, prixAssure: null, etatAssure: 'unique', statut: 'refuse', dateEffet: '2026-08-16' },
      { code: 'A8', version: 1, prixNonAssure: 5000, prixAssure: null, etatAssure: 'unique', statut: 'valide' },
      { code: 'A8', version: 2, prixNonAssure: 5500, prixAssure: null, etatAssure: 'unique', statut: 'valide', dateEffet: '2026-08-20' },
      { code: 'A9', version: 1, prixNonAssure: 0, prixAssure: null, etatAssure: 'unique', statut: 'valide' },
      { code: 'A10', version: 1, prixNonAssure: 1200, prixAssure: null, etatAssure: 'nc', statut: 'valide' },
      { code: 'G1', version: 1, prixNonAssure: 7000, prixAssure: 7000, etatAssure: 'montant', statut: 'valide' },
      { code: 'G2', version: 1, prixNonAssure: 1500, prixAssure: null, etatAssure: 'nc', statut: 'valide' },
      { code: 'G3', version: 1, prixNonAssure: 3000, prixAssure: 5000, etatAssure: 'montant', statut: 'valide' },
      { code: 'G4', version: 1, prixNonAssure: 2000, prixAssure: null, etatAssure: 'manquant', statut: 'valide' },
      { code: 'L1', version: 1, prixNonAssure: 2500, prixAssure: 2500, etatAssure: 'unique', statut: 'valide' },
      { code: 'L2', version: 1, prixNonAssure: 2000, prixAssure: 2500, etatAssure: 'montant', statut: 'valide' },
      { code: 'L3', version: 1, prixNonAssure: null, etatNonAssure: 'manquant', prixAssure: null, etatAssure: 'manquant', statut: 'valide' },
      { code: 'L4', version: 1, prixNonAssure: 1800, prixAssure: null, etatAssure: 'manquant', statut: 'valide' },
      { code: 'AR1', version: 1, prixNonAssure: 800, prixAssure: null, etatAssure: 'unique', statut: 'valide' },
    ];
    const h = TA.indexer(tarifs, versions);
    const cas = [];
    const codesActe = ['A1', 'A2', 'A3', 'A4', 'A5', 'A6', 'A7', 'A8', 'A9', 'A10', 'G1', 'G2', 'G3', 'G4', 'L1', 'LAB-X', 'AR1', 'ZZ', ''];
    const codesAnalyse = ['L1', 'L2', 'L3', 'L4', 'LAB-X', 'A1', 'ZZ'];
    const jours = ['2026-08-16', '2026-08-20', '2026-09-01'];
    const garder = (r) => { const o = {}; ['ok', 'montant', 'tarif', 'motif', 'prestation', 'libelle', 'version', 'cause', 'geste', 'effectifLe', 'colonne', 'code'].forEach((k) => { if (r[k] !== undefined && r[k] !== null) o[k] = r[k]; }); return o; };
    [['acte', codesActe], ['analyse', codesAnalyse]].forEach((x) => x[1].forEach((c) => jours.forEach((j) => [false, true].forEach((a) => {
      cas.push({ voie: x[0], code: c, jour: j, assure: a, attendu: garder(TA.prixDeLigne(h, c, j, a, x[0])) });
    }))));
    out.sonde = { tarifs: tarifs, versions: versions, cas: cas, sansReferentiel: garder(TA.prixDeLigne(null, 'A1', '2026-08-16', false, 'acte')) };
    /* --- 2. Un code ne se réutilise pas ---------------------------------------------------------------------------------------------------------------------- */
    const pris = [{ code: 'CERT-APT', codeGrille: 'CERT-APT', libelle: 'Certificat médical d’aptitude', statut: 'actif' }, { code: 'SO02', codeActe: 'SO02', codeGrille: 'SIV', codesAlias: ['SIV'], libelle: 'Soins IV', statut: 'actif' },
      { code: 'OLD1', codeActe: 'OLD1', libelle: 'Acte archivé', statut: 'archive' }];
    out.codePris = { tarifs: pris, cas: ['CERT-APT', 'cert-apt', ' CERT-APT ', 'Cert-Apt  ', 'siv', ' so02', 'old1', 'CERT-CA', '', null].map((c) => { const p = TA.codePris(pris, c); return { code: c, pris: p ? p.code : null, normalise: TA.codeNormalise(c) }; }) };
    /* --- 3. Le référentiel semé, par la lecture du moteur de prescription ----------------------------------------------------------------------------------- */
    out.seme = ['CERT-APT', 'CERT-CA', 'CONS-GEN', 'SO09', 'L05', 'LAB-NFS', 'IMG-ECHO-PEL'].map((c) => ({ code: c, acte: [false, true].map((a) => garder(PR.prixLignePrescription(c, '2026-08-16', a, 'acte'))),
      analyse: [false, true].map((a) => garder(PR.prixLignePrescription(c, '2026-08-16', a, 'analyse'))) }));
    return out;
  });

  /* --- 4. Les textes de l'écran réel sous un acte sans prix (proposé, puis décidé à effet futur) ------------------------------------------------------------ */
  const ecran = await page.evaluate(() => {
    const S = window.SIGH.store, PR = window.SIGH.parcours;
    S.setSession({ role: 'admin', nom: 'VECTEUR TARIF-FIX', nomComplet: 'VECTEUR TARIF-FIX', fonction: 'direction', secteur: 'DIR' });
    const pP = PR.proposerTarif({ code: 'VTFP', prixNonAssure: 2500, etatAssure: 'unique', dateEffet: '2026-08-16', motif: 'Vecteur', creation: { libelle: 'Vecteur proposé', famille: 'ACTE', secteur: 'Soins' } });
    const pF = PR.proposerTarif({ code: 'VTFF', prixNonAssure: 3500, etatAssure: 'unique', dateEffet: '2026-08-20', motif: 'Vecteur', creation: { libelle: 'Vecteur futur', famille: 'ACTE', secteur: 'Soins' } });
    if (pF.ok) PR.deciderTarif(pF.version.id, 'oui');
    S.collection('actes').insert({ id: 'ACT-VTFP', code: 'VTFP', libelle: 'Vecteur proposé', secteur: 'Soins', statut: 'actif' });
    S.collection('actes').insert({ id: 'ACT-VTFF', code: 'VTFF', libelle: 'Vecteur futur', secteur: 'Soins', statut: 'actif' });
    return { proposee: pP.ok, decidee: pF.ok };
  });
  await page.evaluate(() => { const S = window.SIGH.store; if (S.pousserMaintenant) S.pousserMaintenant(); });
  await page.waitForFunction(() => !window.SIGH.store.fileEnAttente || window.SIGH.store.fileEnAttente() === 0, { timeout: 30000 });
  await peindre('m2-ordonnance-nouvelle.php');
  const textes = await page.evaluate(async () => {
    const pause = (ms) => new Promise((r) => setTimeout(r, ms));
    const ctrl = document.getElementById('f_actes');
    const btn = ctrl.querySelector('button'); btn.click(); await pause(300);
    const champ = document.querySelector('.combo-panel:not([hidden]) input.combo-search'); champ.value = 'Vecteur'; champ.dispatchEvent(new Event('input', { bubbles: true })); await pause(300);
    const options = [...document.querySelectorAll('.combo-panel:not([hidden]) [role="option"]')].map((o) => o.textContent.replace(/\s+/g, ' ').trim()).filter((t) => /Vecteur/.test(t));
    btn.click();
    ctrl.value = ['VTFP']; ctrl.dispatchEvent(new Event('change', { bubbles: true })); await pause(300);
    const total = [...document.querySelectorAll('#page-content p')].map((p) => p.textContent).filter((t) => /Non calculable/.test(t))[0] || null;
    return { options: options, total: total };
  });
  R.ecran = Object.assign(ecran, textes, { texteCatalogueSansPrix: 'sans prix : à tarifier dans Tarifs et prix' });
  fs.writeFileSync(sortie, JSON.stringify(R, null, 1) + '\n');
  console.log('Vecteurs écrits : ' + sortie + ' (' + R.sonde.cas.length + ' cas de sonde, ' + R.codePris.cas.length + ' cas de code pris ; erreurs JS : ' + erreurs.length + ')');
  await br.close(); srv.close(); try { php.php.kill(); } catch (e) { /* mort */ }
  process.exit(erreurs.length ? 1 : 0);
})().catch((e) => { console.error(e); try { if (PHP) PHP.kill(); } catch (x) { /* mort */ } process.exit(1); });
