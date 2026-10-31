/* =============================================================================
 * VECTEURS DU MOBILE SOIGNANT : constantes, note de consultation, prescription, demande d'analyses (PILOTÉS dans Chrome)
 * -----------------------------------------------------------------------------
 * Les pages `mobile/ecrans/*.php` sont servies en statique (aucun PHP, aucune base : le simulateur ne parle à aucun serveur), ouvertes sous le profil
 * qui les porte, remplies champ par champ, et ce que l'écran répond est relevé tel quel : messages de refus, bornes, listes de choix, ecrans ouverts
 * par profil. S'y ajoute, avec `--regles` (maquette complète, PHP + PostgreSQL du banc), la matrice `PR.peutPrescrire(nature, session)` de la maquette
 * principale, fonction par fonction : « prescription selon droits ».
 *   node build/vecteurs-mobile.js            →  packages/domaine/test/vecteurs/mobile.json  (partie mobile seule)
 *   node build/vecteurs-mobile.js --regles   →  idem + la matrice des droits de prescription (exige PHP et PostgreSQL)
 * Le port de test du serveur statique : SIGH_PORT_MOBILE (8591 par défaut). La partie `--regles` utilise SIGH_PORT_PHP / SIGH_PORT_TEST.
 * ========================================================================== */
'use strict';
const fs = require('fs'), path = require('path'), http = require('http');
const { chromium } = require('playwright');
const { ecrire } = require('./extraire');
const M = require('../mobile/manifeste.js');
const ROOT = path.resolve(__dirname, '..');
const MIME = { '.php': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.jpeg': 'image/jpeg' };
const PORT = Number(process.env.SIGH_PORT_MOBILE || 8591);
const AVEC_REGLES = process.argv.includes('--regles');

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
  console.log('▶ Vecteurs du mobile soignant');
  const srv = http.createServer((req, res) => {
    const f = path.join(ROOT, decodeURIComponent(req.url.split('?')[0]));
    if (!f.startsWith(ROOT) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end(); }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' }); fs.createReadStream(f).pipe(res);
  }).listen(PORT);
  const nav = await chromium.launch();
  const page = await (await nav.newContext({ viewport: { width: 390, height: 844 } })).newPage();
  const erreursJs = [];
  page.on('pageerror', (e) => erreursJs.push(e.message));
  const base = `http://127.0.0.1:${PORT}/mobile/ecrans/`;
  const ouvrir = async (id, profil) => {
    await page.goto(base + '../index.php'); await page.evaluate(() => localStorage.clear());
    await page.goto(`${base}${id}.php?os=android&profil=${profil}&p=p1`); await page.waitForSelector('.barre');
  };
  const erreurs = () => page.evaluate(() => { const o = {}; document.querySelectorAll('[data-champ]').forEach((c) => { const e = c.querySelector('.erreur'); if (e && !e.hidden && e.textContent) o[c.getAttribute('data-champ')] = e.textContent; }); return o; });
  const texte = (sel) => page.evaluate((s) => { const e = document.querySelector(s); return e ? e.textContent.replace(/\s+/g, ' ').trim() : null; }, sel);

  async function essai(id, profil, saisie, bouton) {
    await ouvrir(id, profil);
    for (const [champ, val] of Object.entries(saisie)) await page.fill('#' + champ, String(val));
    await page.click(bouton || '#ok');
    return erreurs();
  }

  /* --- constantes ------------------------------------------------------------------------------------------------ */
  const casConstantes = [
    {}, { temperature: '57' }, { temperature: 'abc' }, { temperature: '29,9' }, { temperature: '30' }, { temperature: '45' }, { temperature: '45,1' }, { temperature: '38,6' },
    { temperature: '37', sys: '49' }, { temperature: '37', sys: '50' }, { temperature: '37', sys: '260' }, { temperature: '37', sys: '261' },
    { temperature: '37', dia: '29' }, { temperature: '37', dia: '30' }, { temperature: '37', dia: '160' }, { temperature: '37', dia: '161' },
    { temperature: '37', pouls: '19' }, { temperature: '37', pouls: '20' }, { temperature: '37', pouls: '250' }, { temperature: '37', pouls: '251' },
    { temperature: '37', fr: '4' }, { temperature: '37', fr: '5' }, { temperature: '37', fr: '80' }, { temperature: '37', fr: '81' },
    { temperature: '37', spo2: '49' }, { temperature: '37', spo2: '50' }, { temperature: '37', spo2: '100' }, { temperature: '37', spo2: '101' },
    { temperature: '37', poids: '0,4' }, { temperature: '37', poids: '0,5' }, { temperature: '37', poids: '300' }, { temperature: '37', poids: '300,1' },
    { temperature: '37', poids: '1e2' }, { temperature: '37', poids: '0x10' }, { temperature: '37', pouls: '  96  ' },
    { temperature: '37', poids: '5.' }, { temperature: '37', poids: '.5' }, { temperature: '37', poids: '+5' }, { temperature: '37', poids: '-1' }, { temperature: '37', poids: '1,2,3' },
    { temperature: '37', poids: 'Infinity' }, { temperature: 'NaN' }, { temperature: '37', pouls: '9 6' }, { temperature: '3 7' },
    { temperature: '57', sys: '300', dia: '10', pouls: 'x', fr: '200', spo2: '10', poids: '1000' },
  ];
  const constantes = [];
  for (const saisie of casConstantes) constantes.push({ saisie, erreurs: await essai('constantes', 'soignant', saisie) });

  /* --- note de consultation (écran « Consultation à domicile » du médecin) -------------------------------------------- */
  await ouvrir('consultation', 'medecin');
  const consultationChamps = await page.evaluate(() => {
    const o = {};
    document.querySelectorAll('[data-champ]').forEach((c) => {
      const s = c.querySelector('select'); const t = c.querySelector('textarea'); const i = c.querySelector('input');
      o[c.getAttribute('data-champ')] = { libelle: c.querySelector('span').textContent.replace('*', '').trim(), requis: !!c.querySelector('em'), type: s ? 'select' : (t ? 'textarea' : 'text'), options: s ? [...s.options].map((x) => x.value) : null, valeur: i ? i.value : null };
    });
    return o;
  });
  const consultation = [];
  for (const saisie of [{ motif: '' }, { motif: '   ' }, { motif: 'Suivi HTA' }]) consultation.push({ saisie, erreurs: await essai('consultation', 'medecin', saisie) });
  const noteConsultation = await texte('.note');

  /* --- prescription ---------------------------------------------------------------------------------------------- */
  await ouvrir('prescription', 'medecin');
  const prescriptionChamps = await page.evaluate(() => {
    const o = {};
    document.querySelectorAll('[data-champ]').forEach((c) => { const i = c.querySelector('input'); o[c.getAttribute('data-champ')] = { libelle: c.querySelector('span').textContent.replace('*', '').trim(), requis: !!c.querySelector('em'), placeholder: i ? i.placeholder : null }; });
    return o;
  });
  const notePrescription = await texte('.note');
  const prescription = [];
  for (const saisie of [{}, { med: 'Paracétamol 500 mg' }, { med: 'Paracétamol 500 mg', poso: '1 cp × 3/j' }, { med: 'x', poso: 'y', duree: '0' }, { med: 'x', poso: 'y', duree: '1' }, { med: 'x', poso: 'y', duree: '90' },
    { med: 'x', poso: 'y', duree: '91' }, { med: 'x', poso: 'y', duree: 'abc' }, { med: 'x', poso: 'y', duree: '5,5' }, { med: '  ', poso: 'y', duree: '5' }]) {
    prescription.push({ saisie, erreurs: await essai('prescription', 'medecin', saisie) });
  }

  /* --- demande d'analyses ---------------------------------------------------------------------------------------- */
  await ouvrir('demande-analyse', 'medecin');
  const analyses = await page.evaluate(() => ({ examens: [...document.querySelectorAll('.ex')].map((c) => c.value), urgences: [...document.querySelector('#urgence').options].map((o) => o.value), note: document.querySelector('.note').textContent.replace(/\s+/g, ' ').trim() }));
  await page.click('#ok');
  analyses.aucunExamen = await page.evaluate(() => { const e = document.getElementById('err-ex'); return { visible: !e.hidden, message: e.textContent }; });
  await page.check('.ex >> nth=0'); await page.click('#ok');
  analyses.unExamen = await page.evaluate(() => { const e = document.getElementById('err-ex'); return { visible: !e.hidden, message: e.textContent }; });

  /* --- ce que chaque profil ouvre -------------------------------------------------------------------------------- */
  const profils = {};
  for (const p of ['soignant', 'medecin', 'sagefemme']) {
    profils[p] = { label: M.PROFILS[p].label, ecrans: M.ECRANS.filter((e) => e.profils.includes(p)).map((e) => e.id) };
  }
  const libellesEcrans = {};
  for (const e of M.ECRANS) libellesEcrans[e.id] = e.label;

  /* --- le dossier et l'accueil du soignant, tels que l'écran les rend ------------------------------------------------ */
  await ouvrir('dossier', 'soignant');
  const dossier = await page.evaluate(() => ({ titres: [...document.querySelectorAll('.carte h2')].map((h) => h.textContent.trim()), boutons: [...document.querySelectorAll('.actions .btn')].map((b) => b.textContent.trim()) }));
  await ouvrir('dossier', 'medecin');
  dossier.boutonsMedecin = await page.evaluate(() => [...document.querySelectorAll('.actions .btn')].map((b) => b.textContent.trim()));
  await ouvrir('dossier', 'sagefemme');
  dossier.boutonsSageFemme = await page.evaluate(() => [...document.querySelectorAll('.actions .btn')].map((b) => b.textContent.trim()));
  dossier.cartes = {};
  for (const p of ['p1', 'p2', 'p3', 'p4']) {
    await page.goto(`${base}dossier.php?os=android&profil=soignant&p=${p}`); await page.waitForSelector('.barre');
    dossier.cartes[p] = await page.evaluate(() => { const o = {}; document.querySelectorAll('.carte').forEach((c) => { const h = c.querySelector('h2'); if (h) o[h.textContent.trim()] = c.textContent.replace(h.textContent, '').replace(/\s+/g, ' ').trim(); }); return o; });
  }
  await ouvrir('accueil-soignant', 'soignant');
  const accueil = { titre: await texte('h1'), kpis: await page.evaluate(() => [...document.querySelectorAll('.kpi')].map((k) => [k.querySelector('.l').textContent.trim(), k.querySelector('.v').textContent.trim()])) };
  await ouvrir('lot', 'soignant');
  const lot = { note: await texte('.note') };

  await nav.close(); srv.close();
  if (erreursJs.length) { console.error('Erreurs JS :', erreursJs); process.exit(1); }

  const sortie = {
    _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-mobile.js : les pages du simulateur mobile (mobile/ecrans/*.php) PILOTÉES dans Chrome, et, avec --regles, PR.peutPrescrire de la maquette complète. Ne pas éditer à la main.',
    constantes, consultation: { champs: consultationChamps, note: noteConsultation, cas: consultation },
    prescription: { champs: prescriptionChamps, note: notePrescription, cas: prescription }, analyses, profils, libellesEcrans, dossier, accueil, lot,
  };

  if (AVEC_REGLES) {
    const { ouvrirMaquette } = require('./extraire');
    const m = await ouvrirMaquette();
    try {
      sortie.droitsPrescription = await m.page.evaluate(() => {
        const PR = SIGH.parcours || SIGH.PR, D = SIGH.data;
        const fonctions = Object.keys(D.CAPACITES);
        const natures = D.NATURES_PRESCRIPTION.map((n) => n.id);
        const lignes = [];
        fonctions.forEach((f) => natures.forEach((n) => lignes.push({ fonction: f, nature: n, autorise: !!PR.peutPrescrire(n, { fonction: f, role: 'medecin' }) })));
        return { fonctions, natures, lignes, labels: Object.fromEntries(fonctions.map((f) => [f, D.CAPACITES[f].label])), note: Object.fromEntries(fonctions.map((f) => [f, D.CAPACITES[f].note || null])) };
      });
    } finally { await m.fermer(); }
  } else {
    console.log('  (sans --regles : la matrice peutPrescrire du fichier existant est conservée)');
    try {
      const ancien = JSON.parse(fs.readFileSync(path.join(ROOT, '..', 'packages/domaine/test/vecteurs/mobile.json'), 'utf8'));
      if (ancien.droitsPrescription) sortie.droitsPrescription = ancien.droitsPrescription;
    } catch (e) { /* pas de fichier précédent */ }
  }
  ecrire('packages/domaine/test/vecteurs/mobile.json', sortie);
  const donnees = {
    profils, libellesEcrans,
    analyses: { examens: analyses.examens, urgences: analyses.urgences, aucunExamen: analyses.aucunExamen.message },
    diagnostics: consultationChamps.diagnostic.options,
    textes: {
      consultation: noteConsultation, prescription: notePrescription, analyses: analyses.note, lot: lot.note,
      carteNonValide: dossier.cartes.p2.Couverture, allergiesAucune: dossier.cartes.p2.Allergies, constantesAucune: dossier.cartes.p1['Dernières constantes'],
    },
  };
  ecrire('packages/domaine/lib/src/mobile/mob_donnees.dart', '// ENGENDRÉ par prototype_html/build/vecteurs-mobile.js : référentiels et textes du mobile soignant, relevés sur les écrans du simulateur.\n// Ne pas éditer à la main : relancer le script.\n// ignore_for_file: prefer_single_quotes\nlibrary;\n\nconst Map<String, Object?> mobDonnees = ' + litteralDart(donnees, 0) + ';\n');
  console.log(`  ${constantes.length} cas de constantes · ${consultation.length} de note · ${prescription.length} de prescription · ${Object.keys(profils).length} profils`);
})().catch((e) => { console.error(e); process.exit(1); });
