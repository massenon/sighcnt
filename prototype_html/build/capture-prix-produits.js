/* =============================================================================
 * CAPTURE DES PRIX DES PRODUITS, référence par référence (PRD-TARIFS, lot T5)
 * -----------------------------------------------------------------------------
 *   node build/capture-prix-produits.js <sortie.json>
 *
 * Pour CHAQUE référence du référentiel produits (les 184 de l'inventaire SAGE), relève ce que l'application donne RÉELLEMENT :
 *   - la fiche (prix d'achat, prix de vente, CUMP, marquage « à valoriser ») ;
 *   - la valeur unitaire de la valorisation du stock, selon les DEUX méthodes (prix de vente, CUMP), et la valeur d'une sortie (`PR.valoriserSortie`) ;
 *   - la ligne de facture qu'une prescription engendre (`PR.prescrire`), patient non assuré puis assuré à carte valide ;
 *   - la liste « Médicament » de la caisse manuelle (pilotée dans le navigateur) ;
 *   - la valeur totale du stock selon chaque méthode.
 *
 * Le fichier produit sert de PREUVE : lancé sur l'arbre d'avant le versionnement du prix d'achat, puis sur l'arbre d'après, les deux sorties doivent être
 * IDENTIQUES (`node build/tarifs/comparer-prix-produits.js avant.json apres.json`). N'emploie que des points d'entrée présents dans les deux arbres.
 * Banc isolé : SIGH_PORT_PHP, SIGH_BASE_TEST (nom portant « banc »), SIGH_PORT_TEST, CHROME_PATH.
 * ========================================================================== */
'use strict';
const fs = require('fs'), path = require('path'), http = require('http');
const ROOT = path.resolve(__dirname, '..');
const BANC = require('./_banc');
const puppeteer = require('puppeteer');
const PORT = Number(process.env.SIGH_PORT_TEST) || 8096;

(async () => {
  const sortie = process.argv[2];
  if (!sortie) { console.error('usage : node build/capture-prix-produits.js <sortie.json>'); process.exit(2); }
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
  await page.goto('http://127.0.0.1:' + PORT + '/pages/m8-facturation.php', { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => { const S = window.SIGH && window.SIGH.store; const c = document.getElementById('page-content'); return S && (!S.faitAutorite || S.faitAutorite()) && c && c.children.length > 0; }, { timeout: 150000 });
  await new Promise((r) => setTimeout(r, 600));

  const mesure = await page.evaluate(() => {
    const S = window.SIGH.store, PR = window.SIGH.parcours;
    const maintenant = new Date().toISOString();
    const ptNon = S.collection('patients').active().filter((p) => !p.externe && !p.assureur)[0];
    const ptAss = S.collection('patients').active().filter((p) => !p.externe && p.assureur && PR.carteValide(p, maintenant) && Number(p.tauxPriseEnCharge) > 0)[0];
    const produits = S.collection('produits').all().slice().sort((a, b) => String(a.code).localeCompare(String(b.code)));
    const R = { patients: { nonAssure: ptNon.code, assure: ptAss.code }, produits: produits.length, fiches: {}, valeurs: {}, sorties: {}, prescrire: {}, totaux: {} };
    const essai = (f) => { try { return f(); } catch (e) { return 'ERREUR:' + String(e.message || e).slice(0, 80); } };
    const methodeInitiale = S.valorisationSortie();
    produits.forEach((p) => {
      R.fiches[p.code] = [p.categorie, p.prixAchat, p.prixVente, p.cump, !!p.valorisationProvisoire, p.statut];
      const v = {};
      ['prixVente', 'cump'].forEach((m) => { S.setValorisationSortie(m); v[m] = S.valeurUnitaire(p); });
      R.valeurs[p.code] = [v.prixVente, v.cump];
      ['prixVente', 'cump'].forEach((m) => {
        S.setValorisationSortie(m);
        const s = essai(() => PR.valoriserSortie(p, 3));
        (R.sorties[p.code] = R.sorties[p.code] || {})[m] = typeof s === 'string' ? s : [s.valeur, s.valeurPrixVente, s.valeurCump, s.ecart];
      });
      [false, true].forEach((assure) => {
        const pt = assure ? ptAss : ptNon, col = assure ? 1 : 0;
        (R.prescrire[p.code] = R.prescrire[p.code] || [])[col] = essai(() => {
          const res = PR.prescrire({ patientCode: pt.code, medecin: 'CAPTURE', diagnostic: 'capture', medicaments: [{ produitId: p.id, quantite: 2 }] });
          const l = (res.facture.lignes || []).filter((x) => x.produitId === p.id)[0];
          const o = (res.ordonnance.medicaments || [])[0];
          return l ? [l.prixUnitaire, l.montant, l.partAssureur, l.partPatient, o ? o.prix : null] : 'AUCUNE LIGNE';
        });
      });
    });
    S.setValorisationSortie(methodeInitiale);
    ['prixVente', 'cump'].forEach((m) => {
      S.setValorisationSortie(m);
      R.totaux[m] = produits.reduce((n, p) => n + (p.stock || 0) * S.valeurUnitaire(p), 0);
    });
    S.setValorisationSortie(methodeInitiale);
    R.totaux.cump_x_stock = produits.reduce((n, p) => n + (p.stock || 0) * (p.cump || 0), 0);
    return R;
  });

  /* La liste « Médicament » de la caisse manuelle, telle que l'écran la propose (pilotée dans le navigateur). */
  const caisse = await page.evaluate(async () => {
    const sel = [...document.querySelectorAll('#page-content select')].find((s) => [...s.options].some((o) => o.value === 'analyse'));
    sel.value = 'medicament'; sel.dispatchEvent(new Event('change', { bubbles: true })); await new Promise((r) => setTimeout(r, 400));
    const h = [...document.querySelectorAll('#page-content *')].find((e) => e._liste);
    const S = window.SIGH.store, parId = {}; S.collection('produits').all().forEach((p) => { parId[p.id] = p.code; });
    return h ? h._liste.map((x) => [parId[x.produitId] || null, x.label, x.prix]).sort((a, b) => String(a[0]).localeCompare(String(b[0]))) : null;
  });
  mesure.caisseManuelle = caisse;
  const trie = (x) => (Array.isArray(x) || x === null || typeof x !== 'object') ? x : Object.keys(x).sort().reduce((o, k) => { o[k] = trie(x[k]); return o; }, {});
  const m = trie(mesure);
  const ligne = (o, ind) => '{\n' + Object.keys(o).map((k) => ind + JSON.stringify(k) + ':' + JSON.stringify(o[k])).join(',\n') + '\n' + ind.slice(1) + '}';
  fs.writeFileSync(sortie, '{\n"patients":' + JSON.stringify(m.patients) + ',\n"produits":' + m.produits + ',\n"totaux":' + JSON.stringify(m.totaux) + ',\n"fiches":' + ligne(m.fiches, ' ') + ',\n"valeurs":' + ligne(m.valeurs, ' ') + ',\n"sorties":' + ligne(m.sorties, ' ') + ',\n"prescrire":' + ligne(m.prescrire, ' ') + ',\n"caisseManuelle":' + JSON.stringify(m.caisseManuelle) + '\n}\n');
  console.log('Capture écrite : ' + sortie + ' (' + mesure.produits + ' produits ; caisse manuelle : ' + (caisse ? caisse.length : 'non relevée') + ' lignes ; erreurs JS : ' + erreurs.length + ')');
  await br.close(); srv.close(); try { php.php.kill(); } catch (e) { /* mort */ }
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
