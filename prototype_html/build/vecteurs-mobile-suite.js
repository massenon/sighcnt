/* =============================================================================
 * VECTEURS DU MOBILE, SUITE : CPN, CPoN, surveillance mère-bébé, orientation de la réception, réglages, lot de tournée, code PIN
 * -----------------------------------------------------------------------------
 * Complète `vecteurs-mobile.js` (constantes, note, prescription, analyses, dossier) pour les sept écrans du simulateur mobile restés non portés.
 * Même méthode : les pages `mobile/ecrans/*.php` sont servies en statique, ouvertes sous le profil qui les porte, remplies champ par champ,
 * et ce que l'écran répond est relevé tel quel : fiche des libellés (pour la mesure de parité N1), messages de refus, bornes, listes de choix,
 * opération mise en file (libellé, détail), toasts, clavier du code PIN touche par touche.
 *   node build/vecteurs-mobile-suite.js   →  packages/domaine/test/vecteurs/mobile_suite.json
 *                                            packages/domaine/lib/src/mobile/mob_suite_donnees.dart  (référentiels et textes)
 *                                            docs/architecture/ecrans-mobile/<id>.json              (fiche N1 de chaque écran)
 * Le port du serveur statique : SIGH_PORT_MOBILE (8591 par défaut). Chrome : CHROME_PATH.
 * ========================================================================== */
'use strict';
const fs = require('fs'), path = require('path'), http = require('http');
const { chromium } = require('playwright');
const { ecrire, REPO } = require('./extraire');
const M = require('../mobile/manifeste.js');
const ROOT = path.resolve(__dirname, '..');
const MIME = { '.php': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.jpeg': 'image/jpeg' };
const PORT = Number(process.env.SIGH_PORT_MOBILE || 8591);

function litteralDart(x, indent) {
  const pad = '  '.repeat(indent || 0);
  if (x === null || x === undefined) return 'null';
  if (typeof x === 'string') return "'" + x.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$').replace(/\n/g, '\\n') + "'";
  if (typeof x === 'number' || typeof x === 'boolean') return String(x);
  if (Array.isArray(x)) {
    if (!x.length) return '<Object?>[]';
    return '[\n' + x.map((v) => pad + '  ' + litteralDart(v, (indent || 0) + 1) + ',').join('\n') + '\n' + pad + ']';
  }
  const ks = Object.keys(x);
  if (!ks.length) return '<String, Object?>{}';
  return '{\n' + ks.map((k) => pad + '  ' + litteralDart(k) + ': ' + litteralDart(x[k], (indent || 0) + 1) + ',').join('\n') + '\n' + pad + '}';
}

(async () => {
  console.log('▶ Vecteurs du mobile, suite');
  const srv = http.createServer((req, res) => {
    const f = path.join(ROOT, decodeURIComponent(req.url.split('?')[0]));
    if (!f.startsWith(ROOT) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end(); }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' }); fs.createReadStream(f).pipe(res);
  }).listen(PORT);
  const nav = await chromium.launch(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {});
  const page = await (await nav.newContext({ viewport: { width: 390, height: 844 } })).newPage();
  const erreursJs = [];
  page.on('pageerror', (e) => erreursJs.push(e.message));
  const base = `http://127.0.0.1:${PORT}/mobile/ecrans/`;
  const ouvrir = async (id, profil, p, avant) => {
    await page.goto(base + '../index.php'); await page.evaluate(() => localStorage.clear());
    if (avant) await page.evaluate(avant);
    await page.goto(`${base}${id}.php?os=android&profil=${profil}${p ? '&p=' + p : ''}`); await page.waitForSelector('.barre');
  };
  const erreurs = () => page.evaluate(() => { const o = {}; document.querySelectorAll('[data-champ]').forEach((c) => { const e = c.querySelector('.erreur'); if (e && !e.hidden && e.textContent) o[c.getAttribute('data-champ')] = e.textContent; }); return o; });

  /* La fiche N1 d'un écran : tout ce que l'agent LIT, dans l'ordre du document (titre, sous-titre, cartes, champs avec options, notes, commandes). */
  const fiche = () => page.evaluate(() => {
    const t = (e) => e.textContent.replace(/\s+/g, ' ').trim();
    const o = { titre: null, sous: null, textes: [], champs: [], boutons: [], onglets: [], notes: [], cartes: [], items: [], kpis: [] };
    const h1 = document.querySelector('h1'); o.titre = h1 ? t(h1) : null;
    const sous = document.querySelector('.barre .sous'); o.sous = sous ? t(sous) : null;
    document.querySelectorAll('.note').forEach((n) => o.notes.push({ ton: [...n.classList].filter((c) => c !== 'note').join(' '), texte: t(n) }));
    document.querySelectorAll('main h2').forEach((h) => o.cartes.push(t(h)));
    let section = null;
    document.querySelectorAll('main h2, main [data-champ]').forEach((c) => {
      if (c.tagName === 'H2') { section = t(c); return; }
      const s = c.querySelector('select'), ta = c.querySelector('textarea'), i = c.querySelector('input');
      o.champs.push({
        section: c.closest('.carte') ? section : null, id: c.getAttribute('data-champ'), libelle: t(c.querySelector('span')).replace(/\s*\*$/, ''), requis: !!c.querySelector('em'),
        type: s ? 'select' : (ta ? 'textarea' : 'input'), saisie: i ? i.type : null, clavier: i ? i.getAttribute('inputmode') : (ta ? ta.getAttribute('inputmode') : null),
        placeholder: (i || ta) ? ((i || ta).placeholder || null) : null, options: s ? [...s.options].map((x) => x.value) : null, valeur: i ? (i.value || null) : (s ? s.value : null),
      });
    });
    document.querySelectorAll('main .btn, main button.btn').forEach((b) => o.boutons.push(t(b)));
    document.querySelectorAll('nav.onglets a').forEach((a) => o.onglets.push(t(a)));
    document.querySelectorAll('main .item').forEach((it) => o.items.push({ titre: it.querySelector('.titre') ? t(it.querySelector('.titre')) : null, detail: it.querySelector('.detail') ? t(it.querySelector('.detail')) : null, fin: it.querySelector('.fin') ? t(it.querySelector('.fin')) : null }));
    document.querySelectorAll('main .kpi').forEach((k) => o.kpis.push([t(k.querySelector('.l')), t(k.querySelector('.v'))]));
    const vide = document.querySelector('main .vide'); if (vide) o.vide = t(vide);
    o.textes = [...document.querySelectorAll('main p, main .l, main b, main .cle, main .vide, main .badge')].flatMap((e) => (e.tagName === 'P' ? e.innerText.split('\n') : [e.textContent])).map((x) => x.replace(/\s+/g, ' ').trim()).filter(Boolean);
    return o;
  });

  const remplir = async (saisie) => {
    for (const [champ, val] of Object.entries(saisie)) {
      const tag = await page.evaluate((c) => document.getElementById(c).tagName, champ);
      if (tag === 'SELECT') await page.selectOption('#' + champ, String(val)); else await page.fill('#' + champ, String(val));
    }
  };
  /* Un essai : saisir, valider ; rend les erreurs par champ ET, quand tout est bon, l'opération mise en file et les toasts. */
  async function essai(id, profil, p, saisie) {
    await ouvrir(id, profil, p);
    await remplir(saisie);
    await page.click('#ok');
    const erreursChamps = await erreurs();
    const r = await page.evaluate(() => {
      const f = JSON.parse(localStorage.getItem('sighm:file') || '[]');
      return { op: f[0] ? { type: f[0].type, libelle: f[0].libelle, detail: f[0].detail, etat: f[0].etat } : null, toasts: [...document.querySelectorAll('.toast')].map((x) => x.textContent) };
    });
    return { saisie, erreurs: erreursChamps, op: r.op, toasts: r.toasts };
  }

  const sortie = { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-mobile-suite.js : CPN, CPoN, surveillance, orientation, réglages, lot, code PIN, relevés sur les pages du simulateur mobile PILOTÉES dans Chrome. Ne pas éditer à la main.' };
  const fiches = {};

  /* --- CPN ------------------------------------------------------------------------------------------------------- */
  const cpnBase = { sa: '28', poids: '60', sys: '120', dia: '80' };
  const cpnCas = [
    {}, { sa: 'abc' }, { ...cpnBase, sa: '3' }, { ...cpnBase, sa: '4' }, { ...cpnBase, sa: '45' }, { ...cpnBase, sa: '46' },
    { ...cpnBase, poids: '29' }, { ...cpnBase, poids: '30' }, { ...cpnBase, poids: '200' }, { ...cpnBase, poids: '200,1' }, { ...cpnBase, poids: '62,5' },
    { ...cpnBase, sys: '59' }, { ...cpnBase, sys: '60' }, { ...cpnBase, sys: '260' }, { ...cpnBase, sys: '261' },
    { ...cpnBase, dia: '29' }, { ...cpnBase, dia: '30' }, { ...cpnBase, dia: '160' }, { ...cpnBase, dia: '161' },
    { ...cpnBase, bcf: '59' }, { ...cpnBase, bcf: '60' }, { ...cpnBase, bcf: '220' }, { ...cpnBase, bcf: '221' }, { ...cpnBase, bcf: 'x' }, { ...cpnBase, hu: '28' }, { ...cpnBase, hu: 'texte' },
    { ...cpnBase, sys: '139', dia: '89' }, { ...cpnBase, sys: '140', dia: '80' }, { ...cpnBase, sys: '120', dia: '90' }, { ...cpnBase, sys: '139', dia: '89', proteinurie: '+' },
    { ...cpnBase, proteinurie: 'Traces' }, { ...cpnBase, proteinurie: '++' }, { ...cpnBase, proteinurie: '+++' },
    { ...cpnBase, sp: 'SP 2', milda: 'Non', presentation: 'Siège', bcf: '140', hu: '27' }, { sa: ' 28 ', poids: ' 60 ', sys: ' 120 ', dia: ' 80 ' },
  ];
  const cpn = { cas: [], risque: {} };
  for (const s of cpnCas) cpn.cas.push(await essai('cpn', 'sagefemme', 'p4', s));
  for (const p of ['p1', 'p2', 'p3', 'p4']) {
    await ouvrir('cpn', 'sagefemme', p);
    cpn.risque[p] = await page.evaluate(() => { const n = document.querySelector('.note.warn'); return { note: n ? n.textContent.replace(/\s+/g, ' ').trim() : null, sous: document.querySelector('.sous').textContent.trim() }; });
  }
  await ouvrir('cpn', 'sagefemme');
  cpn.sansPatient = await page.evaluate(() => document.querySelector('.sous').textContent.trim());
  sortie.cpn = cpn;
  await ouvrir('cpn', 'sagefemme', 'p4'); fiches.cpn = await fiche();

  /* --- CPoN ------------------------------------------------------------------------------------------------------ */
  const cponBase = { ta: '12/8', t: '37', pb: '3200' };
  const cponCas = [
    {}, { ...cponBase, ta: '' }, { ...cponBase, t: '' }, { ...cponBase, pb: '' }, { ...cponBase, t: 'abc' },
    { ...cponBase, t: '33,9' }, { ...cponBase, t: '34' }, { ...cponBase, t: '43' }, { ...cponBase, t: '43,1' }, { ...cponBase, t: '38,6' },
    { ...cponBase, pb: '999' }, { ...cponBase, pb: '1000' }, { ...cponBase, pb: '6000' }, { ...cponBase, pb: '6001' }, { ...cponBase, pb: '3200,5' }, { ...cponBase, pb: 'x' },
    cponBase, { ...cponBase, jour: 'J7', lochies: 'Abondantes', uterus: 'Insuffisante', cordon: 'Infecté', allait: 'Difficulté' }, { ...cponBase, jour: 'J42', cordon: 'Suintant' },
    { ...cponBase, ta: 'n’importe quoi' },
  ];
  const cpon = { cas: [], patientParDefaut: null };
  for (const s of cponCas) cpon.cas.push(await essai('cpon', 'sagefemme', 'p2', s));
  await ouvrir('cpon', 'sagefemme'); cpon.patientParDefaut = await page.evaluate(() => document.querySelector('.sous').textContent.trim());
  sortie.cpon = cpon;
  await ouvrir('cpon', 'sagefemme', 'p2'); fiches.cpon = await fiche();

  /* --- surveillance mère-bébé ------------------------------------------------------------------------------------- */
  const survCas = [
    {}, { mpouls: '29' }, { mpouls: '30' }, { mpouls: '220' }, { mpouls: '221' }, { mpouls: 'x' }, { bfr: '9' }, { bfr: '10' }, { bfr: '100' }, { bfr: '101' },
    { bt: '33,9' }, { bt: '34' }, { bt: '41' }, { bt: '41,1' }, { bt: 'chaud' },
    { heure: 'H12', mta: '12/8', mpouls: '80', saign: 'Abondant', bfr: '40', bt: '36,8', bcordon: 'Suintant' }, { heure: 'H24', mta: '11/7' }, { heure: 'H8', bfr: '44' },
    { mpouls: '300', bfr: '200', bt: '50' },
  ];
  const surveillance = { cas: [] };
  for (const s of survCas) surveillance.cas.push(await essai('surveillance', 'sagefemme', null, s));
  sortie.surveillance = surveillance;
  await ouvrir('surveillance', 'sagefemme'); fiches.surveillance = await fiche();

  /* --- orientation de la réception -------------------------------------------------------------------------------- */
  const dossiersJeu = [
    { id: 'd1', code: 'CNT/1241/26', provisoire: false, nom: 'AKPO', prenom: 'Marc', age: 34, quartier: 'Kouba', motif: 'Urgence', quand: Date.now() - 600000, doublon: true },
    { id: 'd2', code: 'PROV-1', provisoire: true, nom: 'HOUNKPATIN', prenom: 'Ida', age: 22, quartier: '', motif: 'Accouchement', quand: Date.now() - 60000, doublon: false },
  ];
  const orientation = { cas: [] };
  await ouvrir('orientation', 'reception'); orientation.sansDossier = await fiche(); fiches['orientation-vide'] = orientation.sansDossier;
  const avantDossiers = `localStorage.setItem('sighm:dossiers', ${JSON.stringify(JSON.stringify(dossiersJeu))})`;
  await ouvrir('orientation', 'reception', null, avantDossiers); orientation.fiche = await fiche(); fiches.orientation = orientation.fiche;
  for (const dest of orientation.fiche.champs.find((c) => c.id === 'dest').options) {
    for (const urg of orientation.fiche.champs.find((c) => c.id === 'urg').options) {
      await ouvrir('orientation', 'reception', null, avantDossiers);
      await page.selectOption('#pat', { index: 1 }); await page.selectOption('#dest', dest); await page.selectOption('#urg', urg); await page.click('#ok');
      const r = await page.evaluate(() => { const f = JSON.parse(localStorage.getItem('sighm:file') || '[]'); return { op: f[0] ? { type: f[0].type, libelle: f[0].libelle, detail: f[0].detail } : null, toasts: [...document.querySelectorAll('.toast')].map((x) => x.textContent) }; });
      orientation.cas.push({ patient: orientation.fiche.champs[0].options[1], dest, urg, ...r });
    }
  }
  // Hors ligne : le toast change, et l'opération reste en attente.
  await ouvrir('orientation', 'reception', null, avantDossiers + `;localStorage.setItem('sighm:reseau', '"hors-ligne"')`);
  await page.click('#ok');
  orientation.horsLigne = await page.evaluate(() => { const f = JSON.parse(localStorage.getItem('sighm:file') || '[]'); return { etat: f[0].etat, toasts: [...document.querySelectorAll('.toast')].map((x) => x.textContent) }; });
  // La page de retour de l'orientation et l'écran fermé aux autres profils.
  orientation.retour = await page.evaluate(() => document.querySelector('a.retour').getAttribute('href'));
  sortie.orientation = orientation;

  /* --- écrans fermés : le message qui NOMME le profil ------------------------------------------------------------- */
  const fermes = {};
  for (const [ecran, profil] of [['cpn', 'medecin'], ['cpn', 'soignant'], ['cpn', 'reception'], ['cpon', 'medecin'], ['surveillance', 'soignant'], ['surveillance', 'reception'], ['orientation', 'sagefemme'], ['orientation', 'soignant'], ['orientation', 'medecin'], ['lot', 'reception']]) {
    await ouvrir(ecran, profil);
    fermes[ecran + '/' + profil] = await page.evaluate(() => ({ titre: document.querySelector('h1').textContent.trim(), note: document.querySelector('.note').textContent.replace(/\s+/g, ' ').trim(), bouton: document.querySelector('.contenu .btn').textContent.trim() }));
  }
  sortie.fermes = fermes;

  /* --- réglages, un profil après l'autre -------------------------------------------------------------------------- */
  const reglages = { profils: {} };
  for (const profil of Object.keys(M.PROFILS)) {
    await ouvrir('parametres', profil); reglages.profils[profil] = await fiche(); fiches['parametres-' + profil] = reglages.profils[profil];
  }
  // Réinitialiser l'appairage : le texte de la confirmation, puis ce qui se passe quand on accepte et quand on refuse.
  await ouvrir('parametres', 'soignant');
  let dialogue = null;
  page.once('dialog', async (d) => { dialogue = { type: d.type(), message: d.message() }; await d.dismiss(); });
  await page.click('#reset'); await page.waitForTimeout(300);
  reglages.confirmation = { ...dialogue, urlApres: page.url().replace(/\?.*/, '').split('/').pop(), appaire: await page.evaluate(() => localStorage.getItem('sighm:appaire')) };
  page.once('dialog', async (d) => { await d.accept(); });
  await Promise.all([page.waitForNavigation({ timeout: 5000 }).catch(() => null), page.click('#reset')]);
  await page.waitForTimeout(300);
  reglages.acceptation = { urlApres: page.url().replace(/\?.*/, '').split('/').pop(), appaire: await page.evaluate(() => localStorage.getItem('sighm:appaire')) };
  sortie.reglages = reglages;

  /* --- lot de tournée ---------------------------------------------------------------------------------------------- */
  const lot = { cas: [] };
  await ouvrir('lot', 'soignant'); lot.defaut = await fiche(); fiches.lot = lot.defaut;
  const MS = 60000;
  for (const [nom, delta] of [['dans 10 h', 600 * MS + 30000], ['dans 90 min', 90 * MS + 30000], ['dans 89 min', 89 * MS], ['dans 31 min', 31 * MS], ['dans 29 min', 29 * MS], ['dans 1 min', 1 * MS],
    ['dans 150 min', 150 * MS + 30000], ['dans 149 min', 149 * MS], ['dans 48 h', 2880 * MS + 30000], ['expire à l’instant', -1000], ['expiré depuis 5 h', -300 * MS]]) {
    await ouvrir('lot', 'soignant', null, `localStorage.setItem('sighm:lot', JSON.stringify({ depose: Date.now() - 5400000, expire: Date.now() + (${delta}), dossiers: 4 }))`);
    const f = await fiche();
    lot.cas.push({ nom, deltaMs: delta, validite: f.kpis.find((k) => k[0] === 'Validité restante')[1], dossiers: f.kpis.find((k) => k[0] === 'Dossiers')[1], note: f.notes.map((n) => n.texte) });
  }
  await ouvrir('lot', 'soignant', null, `localStorage.setItem('sighm:lot', JSON.stringify({ depose: Date.now() - 5400000, expire: Date.now() + 36000000, dossiers: 0 }))`);
  lot.sansDossier = (await fiche()).kpis;
  for (const p of ['medecin', 'sagefemme']) { await ouvrir('lot', p); lot['pour_' + p] = (await fiche()).items.length; }
  sortie.lot = lot;

  /* --- code PIN : le clavier, touche par touche -------------------------------------------------------------------- */
  const pin = { sequences: [] };
  await ouvrir('verrou', 'soignant'); fiches.verrou = await fiche();
  pin.pave = await page.evaluate(() => [...document.querySelectorAll('.pin > *')].map((e) => e.tagName === 'BUTTON' ? e.dataset.k : ''));
  pin.invite = await page.evaluate(() => document.querySelector('main p').firstChild.textContent.trim());
  pin.demo = await page.evaluate(() => document.querySelector('main p .cle').textContent.trim());
  const sequences = [
    ['1', '2', '3', '4'], ['0', '0', '0', '0'], ['9', '9', '9', '9', '1', '1', '1', '1', '2', '2', '2', '2'],
    ['9', '9', '9', '9', '1', '1', '1', '1', '2', '2', '2', '2', '1', '2', '3', '4'], ['1', '2', '⌫', '3', '4'], ['1', '2', '⌫', '⌫', '⌫', '1', '2', '3', '4'],
    ['1', '2', '3'], ['1', '2', '3', '⌫'], ['⌫'], ['9', '9', '9', '9', '1', '2', '3', '4'], ['9', '9', '9', '9', '9', '9', '9', '9', '1', '2', '3', '4'],
    ['4', '3', '2', '1'], ['1', '2', '3', '5'],
  ];
  for (const profil of ['soignant']) {
    for (const seq of sequences) {
      await ouvrir('verrou', profil);
      const pas = [];
      for (const k of seq) {
        await page.click(`.pin button[data-k="${k}"]`).catch(() => null);
        await page.waitForTimeout(30);
        const etat = await page.evaluate(() => ({ msg: document.getElementById('msg') ? document.getElementById('msg').textContent : null, points: document.querySelectorAll('#pts span.plein').length, url: location.pathname.split('/').pop() }));
        pas.push({ touche: k, ...etat });
        if (etat.url !== 'verrou.php') break;
      }
      pin.sequences.push({ profil, touches: seq, pas });
    }
  }
  pin.accueilParProfil = {};
  for (const profil of Object.keys(M.PROFILS)) {
    await ouvrir('verrou', profil);
    for (const k of ['1', '2', '3', '4']) await page.click(`.pin button[data-k="${k}"]`);
    await page.waitForTimeout(300);
    pin.accueilParProfil[profil] = page.url().replace(/\?.*/, '').split('/').pop().replace(/\.php$/, '');
  }
  // Le verrou ne se rouvre pas de lui-même : il faut recharger la page pour retrouver trois essais (rien ne retient les 30 s annoncées).
  await ouvrir('verrou', 'soignant');
  for (const k of ['0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0']) await page.click(`.pin button[data-k="${k}"]`);
  await page.waitForTimeout(31000 > 0 ? 200 : 0);
  pin.apresBlocage = await page.evaluate(() => document.getElementById('msg').textContent);
  await page.reload(); await page.waitForSelector('.barre');
  pin.apresRechargement = await page.evaluate(() => document.getElementById('msg').textContent);
  sortie.pin = pin;

  /* --- les profils et leurs écrans (pour les droits) ---------------------------------------------------------------- */
  sortie.ecransProfils = {};
  for (const p of Object.keys(M.PROFILS)) sortie.ecransProfils[p] = M.ECRANS.filter((e) => e.profils.includes(p)).map((e) => e.id);
  sortie.profils = Object.fromEntries(Object.entries(M.PROFILS).map(([k, v]) => [k, { label: v.label, agent: v.agent, accueil: v.accueil }]));

  await nav.close(); srv.close();
  if (erreursJs.length) { console.error('Erreurs JS :', erreursJs); process.exit(1); }

  ecrire('packages/domaine/test/vecteurs/mobile_suite.json', sortie);
  for (const [id, f] of Object.entries(fiches)) ecrire('docs/architecture/ecrans-mobile/' + id + '.json', { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-mobile-suite.js : la fiche N1 de la page du simulateur mobile « ' + id + ' ». Ne pas éditer à la main.', ...f });

  const champs = (f) => f.champs.map((c) => ({ section: c.section, id: c.id, libelle: c.libelle, requis: c.requis, type: c.type, saisie: c.saisie, clavier: c.clavier, placeholder: c.placeholder, options: c.options }));
  const donnees = {
    cpn: { titre: fiches.cpn.titre, champs: champs(fiches.cpn), cartes: fiches.cpn.cartes, bouton: fiches.cpn.boutons[0], alerte: cpn.cas.find((c) => c.toasts.length === 2).toasts[0] },
    cpon: { titre: fiches.cpon.titre, champs: champs(fiches.cpon), cartes: fiches.cpon.cartes, bouton: fiches.cpon.boutons[0] },
    surveillance: { titre: fiches.surveillance.titre, champs: champs(fiches.surveillance), cartes: fiches.surveillance.cartes, note: fiches.surveillance.notes[0].texte, bouton: fiches.surveillance.boutons[0] },
    orientation: { titre: fiches.orientation.titre, champs: champs(fiches.orientation), bouton: fiches.orientation.boutons[0], vide: fiches['orientation-vide'].vide },
    fermes: Object.fromEntries(Object.entries(fermes).map(([k, v]) => [k, v.note])),
    lot: { titre: fiches.lot.titre, cartes: fiches.lot.cartes, kpis: fiches.lot.kpis.map((k) => k[0]), notes: fiches.lot.notes.map((n) => n.texte) },
    reglages: { titre: fiches['parametres-soignant'].titre, confirmation: reglages.confirmation.message, items: fiches['parametres-soignant'].items.map((i) => [i.titre, i.detail, i.fin]), bouton: fiches['parametres-soignant'].boutons[0] },
    pin: { titre: fiches.verrou.titre, invite: pin.invite, demo: pin.demo, pave: pin.pave, incorrect: pin.sequences[1].pas[3].msg.replace('(1/', '(#/'), bloque: pin.apresBlocage },
    toasts: { enLigne: cpn.cas.find((c) => c.op).toasts.slice(-1)[0], horsLigne: orientation.horsLigne.toasts[0] },
    profils: sortie.profils, ecransProfils: sortie.ecransProfils,
    appareils: Object.fromEntries(Object.entries(reglages.profils).map(([k, f]) => [k, f.textes.find((t) => t.indexOf('Appareil') === 0)])),
  };
  ecrire('packages/domaine/lib/src/mobile/mob_suite_donnees.dart', '// ENGENDRÉ par prototype_html/build/vecteurs-mobile-suite.js : référentiels et textes de CPN, CPoN, surveillance, orientation, réglages, lot et code PIN du mobile,\n// relevés sur les pages du simulateur. Ne pas éditer à la main : relancer le script.\n// ignore_for_file: prefer_single_quotes\nlibrary;\n\nconst Map<String, Object?> mobSuiteDonnees = ' + litteralDart(donnees, 0) + ';\n');
  console.log(`  CPN ${cpn.cas.length} · CPoN ${cpon.cas.length} · surveillance ${surveillance.cas.length} · orientation ${orientation.cas.length} · lot ${lot.cas.length} · PIN ${pin.sequences.length} séquences`);
})().catch((e) => { console.error(e); process.exit(1); });
