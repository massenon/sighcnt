/* =============================================================================
 * CAPTURE EXHAUSTIVE DES PRIX, par code et par voie de tarification (PRD-TARIFS, lot T1)
 * -----------------------------------------------------------------------------
 *   node build/capture-prix.js <sortie.json>
 *
 * Pour CHAQUE code des trois espaces (grille 147, actes 73, analyses 48) et pour les cinq voies de tarification
 * (prescription d'actes et d'analyses, prescription de soins, imagerie, caisse manuelle, certificats), relève le prix
 * que la voie donne RÉELLEMENT : en appelant ses points d'entrée publics (`PR.prescrire`, `PR.prescrireSoins`,
 * `PR.ouvrirDemandeImagerie`), en pilotant la caisse manuelle dans le navigateur, et en interrogeant les accesseurs.
 * Les deux colonnes sont relevées (patient non assuré, patient assuré à carte valide).
 *
 * Le fichier produit sert de PREUVE : lancé sur l'arbre d'avant le référentiel unique, puis sur l'arbre d'après, les
 * deux sorties doivent être IDENTIQUES (`node build/tarifs/comparer-prix.js avant.json apres.json`). Banc isolé :
 * SIGH_PORT_PHP, SIGH_BASE_TEST (nom portant « banc »), SIGH_PORT_TEST, CHROME_PATH.
 * ========================================================================== */
'use strict';
const fs = require('fs'), path = require('path'), http = require('http');
const ROOT = path.resolve(__dirname, '..');
const BANC = require('./_banc');
const puppeteer = require('puppeteer');
const PORT = Number(process.env.SIGH_PORT_TEST) || 8096;

(async () => {
  const sortie = process.argv[2];
  if (!sortie) { console.error('usage : node build/capture-prix.js <sortie.json>'); process.exit(2); }
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
  const peindre = async (rel) => {
    await page.goto('http://127.0.0.1:' + PORT + '/pages/' + rel, { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => { const S = window.SIGH && window.SIGH.store; const c = document.getElementById('page-content'); return S && (!S.faitAutorite || S.faitAutorite()) && c && c.children.length > 0; }, { timeout: 150000 });
    await new Promise((r) => setTimeout(r, 600));
  };
  await peindre('m8-facturation.php');

  /* --- 1. Accesseurs, voies par point d'entrée (dans la page) ------------------------------------------------------------------------------------------ */
  const mesure = await page.evaluate(() => {
    const S = window.SIGH.store, PR = window.SIGH.parcours, D = window.SIGH.data;
    const maintenant = new Date().toISOString();
    const ptNon = S.collection('patients').active().filter((p) => !p.externe && !p.assureur)[0];
    const ptAss = S.collection('patients').active().filter((p) => !p.externe && p.assureur && PR.carteValide(p, maintenant) && Number(p.tauxPriseEnCharge) > 0)[0];
    const grille = D.CATALOGUE.map((e) => e.code);
    const actes = S.collection('actes').all().map((a) => a.code);
    const analyses = D.ANALYSES.map((a) => a.code);
    const codes = Array.from(new Set(grille.concat(actes, analyses))).sort();
    const R = { patients: { nonAssure: ptNon.code, assure: ptAss.code }, espaces: { grille: grille.length, actes: actes.length, analyses: analyses.length }, codes: codes.length, voies: {} };
    const V = (n) => (R.voies[n] = R.voies[n] || {});
    const essai = (f) => { try { return f(); } catch (e) { return 'ERREUR:' + String(e.message || e).slice(0, 80); } };
    codes.forEach((c) => {
      [false, true].forEach((assure) => {
        const pt = assure ? ptAss : ptNon, col = assure ? 1 : 0;
        /* accesseurs */
        const pr = D.tarifPrix(c, assure);
        (V('accesseur.tarifPrix')[c] = V('accesseur.tarifPrix')[c] || [])[col] = [pr.montant, pr.tarif || null, pr.motif || null, pr.reserveSos === true];
        /* voie 1 : prescription (actes, puis analyses) */
        (V('prescrire.acte')[c] = V('prescrire.acte')[c] || [])[col] = essai(() => {
          const res = PR.prescrire({ patientCode: pt.code, medecin: 'CAPTURE', diagnostic: 'capture', actes: [c] });
          const l = (res.facture.lignes || []).filter((x) => x.acteCode === c)[0];
          return l ? [l.prixUnitaire, l.montant, l.partAssureur, l.partPatient] : 'AUCUNE LIGNE';
        });
        (V('prescrire.analyse')[c] = V('prescrire.analyse')[c] || [])[col] = essai(() => {
          const res = PR.prescrire({ patientCode: pt.code, medecin: 'CAPTURE', diagnostic: 'capture', analyses: [c] });
          const a = (res.ordonnance.analyses || []).filter((x) => x.code === c)[0];
          const l = (res.facture.lignes || []).filter((x) => x.demandeId || x.categorie === 'analyse')[0];
          return a ? [a.prix, l ? l.prixUnitaire : null, l ? l.partAssureur : null] : 'AUCUNE ANALYSE';
        });
        /* voie 2 : prescription de soins */
        (V('soins')[c] = V('soins')[c] || [])[col] = essai(() => {
          const p = PR.prescrireSoins({ patientCode: pt.code, prescripteurId: null, actes: [c], secteurDestinataire: 'salle_soins' });
          const l = (p.lignes || [])[0];
          return l ? [l.prix, l.tarif, l.motifTarif, l.prixAValider, l.libelle, l.famille] : 'AUCUNE LIGNE';
        });
        /* voie 3 : imagerie */
        (V('imagerie')[c] = V('imagerie')[c] || [])[col] = essai(() => {
          const res = PR.ouvrirDemandeImagerie({ patientId: pt.id, examens: [c], prescripteur: 'CAPTURE', indication: 'capture' });
          const d = res.demandes[0];
          const l = (res.facture.lignes || []).filter((x) => x.categorie === 'imagerie')[0];
          return [d.prix, l ? l.prixUnitaire : null, l ? l.partAssureur : null];
        });
      });
    });
    /* voie 5 : certificats, par le chemin du délivrer (D.tarif du tarifCode du type de pièce) */
    S.collection('typesPiece').all().forEach((t) => {
      const tf = t.tarifCode ? D.tarif(t.tarifCode) : null;
      V('certificats')[t.code || t.id] = tf ? [t.tarifCode, tf.prixNonAssure, tf.assurable, tf.libelle] : [t.tarifCode || null, null];
    });
    D.tarifParFamille('CERTIFICAT').forEach((t) => { V('certificats.grille')[t.code] = [t.prixNonAssure, t.prixAssure, t.assurable, t.libelle]; });
    /* accesseurs de lecture historiques */
    D.CATALOGUE.forEach((e) => { const t = D.tarif(e.code); V('accesseur.tarif')[e.code] = t ? [t.libelle, t.famille, t.prixNonAssure, t.prixAssure, !!t.nonCouvert, t.assurable, !!t.prixAValider] : null; });
    codes.forEach((c) => { if (!R.voies['accesseur.tarif'][c]) { const t = D.tarif(c); R.voies['accesseur.tarif'][c] = t ? [t.libelle, t.famille, t.prixNonAssure, t.prixAssure, !!t.nonCouvert, t.assurable, !!t.prixAValider] : null; } });
    /* collections de lecture (projection) : chaque lecteur non migré reçoit exactement ceci */
    const pick = (o, ks) => ks.map((k) => (o[k] === undefined ? null : o[k]));
    R.collections = {
      actes: S.collection('actes').all().map((a) => [a.id, a.code, a.libelle, a.secteur].concat(pick(a, ['prix', 'prixNonAssure', 'prixAssure', 'nonCouvert', 'assurable', 'codeTarif', 'tarifProvisoire', 'tarifArreteLe', 'statut']))),
      analyses: S.collection('analyses').all().map((a) => [a.id, a.code, a.designation].concat(pick(a, ['prix', 'tarifProvisoire', 'aValider', 'statut']))),
      catalogueTarifs: S.collection('catalogueTarifs').all().map((a) => [a.id, a.code, a.libelle, a.famille].concat(pick(a, ['prixNonAssure', 'prixAssure', 'nonCouvert', 'assurable', 'prixAValider', 'statut']))),
      typesChambre: D.TYPES_CHAMBRE.map((t) => [t.id, t.label, t.tarif]),
    };
    return R;
  });

  /* --- 2. Voie 4 : caisse manuelle (les listes que l'écran propose), pilotée dans le navigateur ------------------------------------------------------ */
  const lire = (nature) => page.evaluate(async (n) => {
    const sel = [...document.querySelectorAll('#page-content select')].find((s) => [...s.options].some((o) => o.value === 'analyse'));
    sel.value = n; sel.dispatchEvent(new Event('change', { bubbles: true })); await new Promise((r) => setTimeout(r, 300));
    const h = [...document.querySelectorAll('#page-content *')].find((e) => e._liste);
    return h ? h._liste.map((x) => [x.code || null, x.label, x.prix]) : null;
  }, nature);
  mesure.voies['caisse.acte'] = await lire('acte');
  mesure.voies['caisse.analyse'] = await lire('analyse');
  mesure.voies['caisse.hospitalisation'] = await lire('hospitalisation');
  mesure.voies['caisse.medicament'] = (await lire('medicament')) ? 'non relevé : produits hors périmètre (RG-02, lot T5)' : null;

  const trie = (x) => (Array.isArray(x) || x === null || typeof x !== 'object') ? x : Object.keys(x).sort().reduce((o, k) => { o[k] = trie(x[k]); return o; }, {});
  /* Une ligne par code et par voie : le fichier se lit et se compare au diff. */
  const m = trie(mesure);
  const ligne = (o, ind) => '{\n' + Object.keys(o).map((k) => ind + JSON.stringify(k) + ':' + JSON.stringify(o[k])).join(',\n') + '\n' + ind.slice(1) + '}';
  const voies = '{\n' + Object.keys(m.voies).map((v) => ' ' + JSON.stringify(v) + ':' + (m.voies[v] && typeof m.voies[v] === 'object' && !Array.isArray(m.voies[v]) ? ligne(m.voies[v], '  ') : JSON.stringify(m.voies[v]))).join(',\n') + '\n}';
  const cols = ligne(m.collections, ' ');
  fs.writeFileSync(sortie, '{\n"patients":' + JSON.stringify(m.patients) + ',\n"espaces":' + JSON.stringify(m.espaces) + ',\n"codes":' + m.codes + ',\n"voies":' + voies + ',\n"collections":' + cols + '\n}\n');
  console.log('Capture écrite : ' + sortie + ' (' + mesure.codes + ' codes, ' + Object.keys(mesure.voies).length + ' voies ; erreurs JS : ' + erreurs.length + ')');
  await br.close(); srv.close(); try { php.php.kill(); } catch (e) { /* mort */ }
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
