/* =============================================================================
 * MESURE DU LOT TARIF-FIX (16/11/2026) : les trois constats de la note de la Direction du 14/11/2026
 * -----------------------------------------------------------------------------
 *   node build/tarifs/mesure-tarif-fix.js <sortie.json>
 *
 * Banc isolé (SIGH_PORT_PHP, SIGH_BASE_TEST portant « test », SIGH_PORT_TEST, CHROME_PATH). Relève, sur le jeu de
 * démonstration servi par un vrai serveur PHP et lu dans Chrome, par les points d'entrée publics :
 *   1. le doublon CERT-APT : chaque ligne qui porte ce code (ou une variante de casse ou d'espaces) dans le référentiel
 *      `tarifs`, ses versions, les projections `catalogueTarifs` et `actes`, la grille de semence, les types de pièce ;
 *      et ce que le moteur répond à la création d'un second code identique (exact, en minuscules, entouré d'espaces) ;
 *   2. la prescription d'actes (`PR.prescrire({ actes: [code] })`) pour CHAQUE code des trois espaces (grille, actes,
 *      analyses), patient non assuré et patient assuré à carte valide : le prix de la ligne de facture, et la CAUSE de
 *      chaque ligne qui ne porte pas un prix strictement positif ;
 *   3. le catalogue du laboratoire : les analyses sans prix (sans prestation de prix, ou sans version en vigueur).
 * Rien n'est corrigé : la mesure est la preuve de l'état. Lancée sur l'arbre d'avant le lot puis sur celui d'après.
 * ========================================================================== */
'use strict';
const fs = require('fs'), path = require('path'), http = require('http');
const ROOT = path.resolve(__dirname, '..', '..');
const BANC = require('../_banc');
const puppeteer = require('puppeteer');
const PORT = Number(process.env.SIGH_PORT_TEST) || 8096;
let PHP = null;   /* tué aussi sur une erreur : un serveur orphelin occuperait le port du banc suivant */

(async () => {
  const sortie = process.argv[2];
  if (!sortie) { console.error('usage : node build/tarifs/mesure-tarif-fix.js <sortie.json>'); process.exit(2); }
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
  await page.goto('http://127.0.0.1:' + PORT + '/pages/m8-facturation.php', { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => { const S = window.SIGH && window.SIGH.store; const c = document.getElementById('page-content'); return S && (!S.faitAutorite || S.faitAutorite()) && c && c.children.length > 0; }, { timeout: 150000 });
  await new Promise((r) => setTimeout(r, 600));

  const mesure = await page.evaluate(() => {
    const S = window.SIGH.store, PR = window.SIGH.parcours, D = window.SIGH.data, brut = S.raw();
    const maintenant = new Date().toISOString(), jour = maintenant.slice(0, 10);
    const norm = (c) => String(c == null ? '' : c).trim().toUpperCase();
    const R = { jour: jour, version: S.VERSION || null };

    /* --- 1. Le doublon CERT-APT ------------------------------------------------------------------------------------ */
    const porte = (x) => norm(x.code) === 'CERT-APT' || norm(x.tarifCode) === 'CERT-APT' || norm(x.codeGrille) === 'CERT-APT' || norm(x.codeTarif) === 'CERT-APT' || (x.codesAlias || []).some((c) => norm(c) === 'CERT-APT');
    const aptitude = (x) => /aptitude/i.test(String(x.libelle || x.designation || ''));
    const resume = (x) => ({ id: x.id, code: x.code || x.tarifCode || null, libelle: x.libelle || x.designation || null, statut: x.statut || null, na: x.prixNonAssure != null ? x.prixNonAssure : (x.prix != null ? x.prix : null), pa: x.prixAssure != null ? x.prixAssure : null, etat: x.etatAssure || null, version: x.version || null, dateEffet: x.dateEffet || null });
    R.certApt = {
      tarifs: (brut.tarifs || []).filter((x) => porte(x) || aptitude(x)).map(resume),
      versionsTarif: (brut.versionsTarif || []).filter(porte).map(resume),
      catalogueTarifs: (brut.catalogueTarifs || []).filter((x) => porte(x) || aptitude(x)).map(resume),
      actes: (brut.actes || []).filter((x) => porte(x) || aptitude(x)).map(resume),
      grilleSemence: D.CATALOGUE.filter((x) => porte(x) || aptitude(x)).map(resume),
      typesPiece: (brut.typesPiece || []).filter((x) => porte(x) || aptitude(x)).map((x) => ({ id: x.id, sigle: x.sigle, libelle: x.libelle, tarifCode: x.tarifCode || null })),
      certificatsTypes: 'cfg-certificats : type « aptitude » (Certificat d’aptitude physique), sans prix ni code tarifaire',
      lu: { tarifALaDate: (() => { const r = PR.tarifALaDate('CERT-APT', maintenant, false); return [r.montant, r.libelle, r.version]; })(), dTarif: (() => { const t = D.tarif('CERT-APT'); return t ? [t.libelle, t.prixNonAssure] : null; })() },
    };
    const essai = (code) => { const r = PR.proposerTarif({ code: code, prixNonAssure: 5000, etatAssure: 'unique', dateEffet: jour, motif: 'Mesure TARIF-FIX', essai: true, creation: { libelle: 'Certificat d’aptitude', famille: 'CERTIFICAT' } }); return r.ok ? 'ACCEPTÉ (essai)' : r.code + ' : ' + r.motif; };
    R.certApt.creationSecondCode = { exact: essai('CERT-APT'), minuscules: essai('cert-apt'), espaces: essai(' CERT-APT '), minusculesEspaces: essai(' cert-apt') };

    /* --- 2. La prescription d'actes, code par code ---------------------------------------------------------------------- */
    const ptNon = S.collection('patients').active().filter((p) => !p.externe && !p.assureur)[0];
    const ptAss = S.collection('patients').active().filter((p) => !p.externe && p.assureur && PR.carteValide(p, maintenant) && Number(p.tauxPriseEnCharge) > 0)[0];
    const grille = D.CATALOGUE.map((e) => e.code), actes = S.collection('actes').all().map((a) => a.code), analyses = D.ANALYSES.map((a) => a.code);
    const codes = Array.from(new Set(grille.concat(actes, analyses))).sort();
    R.espaces = { grille: grille.length, actes: actes.length, analyses: analyses.length, codes: codes.length };
    const h = D.TARIFS.lire();
    function cause(c, assure) {
      const pActe = h.parActe[c], p = h.parCode[c];
      if (!p) return 'absent-du-referentiel';
      if (!pActe) return p.famille === 'LABO' || h.parAnalyse[c] ? 'analyse-hors-espace-des-actes' : 'grille-hors-espace-des-actes';
      const s = D.TARIFS.instantane(h, pActe, jour);
      if (!s) {
        const futur = (h.vers[pActe.code] || []).filter((v) => v.statut === 'valide' && v.dateEffet && v.dateEffet > jour)[0];
        return futur ? 'version-future-seulement' : 'acte-sans-version-en-vigueur';
      }
      if (s.na == null) return 'prix-non-assure-vide';
      if (assure && pActe.assurable === true && s.etatAssure === 'manquant') return 'prix-assure-vide-repli-non-assure';
      return null;
    }
    const lignes = {}, parCause = { nonAssure: {}, assure: {} }, zero = { nonAssure: [], assure: [] }, erreursPrescription = {};
    codes.forEach((c) => {
      [false, true].forEach((assure) => {
        const pt = assure ? ptAss : ptNon, cle = assure ? 'assure' : 'nonAssure';
        let l = null, err = null;
        try {
          const res = PR.prescrire({ patientCode: pt.code, medecin: 'MESURE TARIF-FIX', diagnostic: 'mesure', actes: [c] });
          const fl = (res.facture.lignes || []).filter((x) => x.acteCode === c)[0];
          const ol = (res.ordonnance.actes || []).filter((x) => x.code === c)[0];
          l = { prixUnitaire: fl ? fl.prixUnitaire : null, montant: fl ? fl.montant : null, tarifValide: ol ? ol.tarifValide : null };
        } catch (e) { err = String(e.message || e).slice(0, 160); }
        (lignes[c] = lignes[c] || {})[cle] = l || ('REFUS : ' + err);
        if (err) { erreursPrescription[c] = err; return; }
        const k = cause(c, assure);
        if (!(l.prixUnitaire > 0)) {
          zero[cle].push(c);
          (parCause[cle][k || 'inexpliquee'] = parCause[cle][k || 'inexpliquee'] || []).push(c);
        } else if (k === 'prix-assure-vide-repli-non-assure') {
          (parCause[cle][k] = parCause[cle][k] || []).push(c);
        }
      });
    });
    R.prescriptionActes = { patients: { nonAssure: ptNon.code, assure: ptAss.code }, zeroNonAssure: zero.nonAssure.length, zeroAssure: zero.assure.length,
      zeroDansLesDeux: zero.nonAssure.filter((c) => zero.assure.indexOf(c) >= 0).length, parCause: parCause, refus: erreursPrescription, lignes: lignes };

    /* --- 3. Le catalogue du laboratoire : les analyses sans prix ---------------------------------------------------------- */
    const cat = S.collection('analyses').active();
    R.catalogueLabo = {
      analyses: cat.length,
      sansPrestation: cat.filter((a) => !h.parAnalyse[a.code]).map((a) => a.code),
      sansVersionEnVigueur: cat.filter((a) => h.parAnalyse[a.code] && !D.TARIFS.instantane(h, h.parAnalyse[a.code], jour)).map((a) => a.code),
      prixNulOuVide: cat.filter((a) => !(a.prix > 0)).map((a) => a.code),
    };
    return R;
  });
  mesure.erreursJS = erreurs.slice(0, 10);
  fs.writeFileSync(sortie, JSON.stringify(mesure, null, 1) + '\n');
  const p = mesure.prescriptionActes;
  console.log('Mesure écrite : ' + sortie);
  console.log('Codes : ' + mesure.espaces.codes + ' (grille ' + mesure.espaces.grille + ', actes ' + mesure.espaces.actes + ', analyses ' + mesure.espaces.analyses + ')');
  console.log('Prescription d’actes, ligne sans prix strictement positif : ' + p.zeroNonAssure + ' (non assuré), ' + p.zeroAssure + ' (assuré), refus : ' + Object.keys(p.refus).length);
  ['nonAssure', 'assure'].forEach((k) => console.log('  ' + k + ' : ' + Object.keys(p.parCause[k]).map((c) => c + ' ' + p.parCause[k][c].length).join(', ')));
  console.log('CERT-APT : ' + JSON.stringify({ tarifs: mesure.certApt.tarifs.length, versions: mesure.certApt.versionsTarif.length, catalogue: mesure.certApt.catalogueTarifs.length, creation: mesure.certApt.creationSecondCode }));
  console.log('Catalogue du laboratoire : ' + JSON.stringify({ analyses: mesure.catalogueLabo.analyses, sansPrestation: mesure.catalogueLabo.sansPrestation.length, sansVersion: mesure.catalogueLabo.sansVersionEnVigueur.length, prixNulOuVide: mesure.catalogueLabo.prixNulOuVide.length }));
  console.log('Erreurs JS : ' + erreurs.length);
  await br.close(); srv.close(); try { php.php.kill(); } catch (e) { /* mort */ }
  process.exit(0);
})().catch((e) => { console.error(e); try { if (PHP) PHP.kill(); } catch (x) { /* mort */ } process.exit(1); });
