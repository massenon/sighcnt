/* =============================================================================
 * EXTRACTION DES NEUF ÉCRANS AUTONOMES (parité N1)
 * -----------------------------------------------------------------------------
 * Les pages SANS COQUILLE (connexion, mot de passe oublié, réinitialisation, double facteur, écran verrouillé, pages
 * d'erreur, plan du site, fiche d'enquête publique) n'ont ni `#page-content` ni fil d'Ariane : `extraire-ecrans.js`
 * les attend en vain (acces: "erreur"). Ce script ouvre chaque page RÉELLE de la maquette et relève ce que l'agent LIT :
 * titres, paragraphes, libellés, placeholders, aria-label, boutons, liens, messages. Jamais les valeurs du jeu.
 *
 *   node build/extraire-autonomes.js [--pages=index,auth-lock] [--dry]
 *
 * Écrit docs/architecture/ecrans/<id>.json, même format que les autres fiches (titre, description, cartes, champs,
 * commandes). Le test `apps/poste/test/parite_autonomes_test.dart` compare l'écran Flutter à ces fiches.
 *
 * Ports et verrou : SIGH_PORT_PHP (serveur PHP du banc), SIGH_PORT_TEST ; la base jetable est partagée, donc
 *   flock /tmp/sigh-banc.lock node build/extraire-autonomes.js
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette, REPO } = require('./extraire');
const BANC = require('./_banc');

const argv = process.argv.slice(2);
const filtre = (argv.find((a) => a.startsWith('--pages=')) || '').replace('--pages=', '').split(',').filter(Boolean);
const DRY = argv.includes('--dry');
const SORTIE = path.join(REPO, 'docs', 'architecture', 'ecrans');

/* Les neuf écrans : adresse réelle, et s'ils s'ouvrent sous une session (verrou) ou sans (tous les autres). */
const ECRANS = [
  { id: 'index', url: '/index.php', session: false },
  { id: 'auth-forgot', url: '/pages/auth-forgot.php', session: false },
  { id: 'auth-reset', url: '/pages/auth-reset.php', session: false },
  { id: 'auth-2fa', url: '/pages/auth-2fa.php', session: true },
  { id: 'auth-lock', url: '/pages/auth-lock.php', session: true },
  { id: 'error-404', url: '/pages/error-404.php', session: false },
  { id: 'error-403', url: '/pages/error-403.php', session: false },
  { id: 'plan-du-site', url: '/pages/plan-du-site.php', session: true },
  { id: 'enquete-publique', url: '/pages/enquete-publique.php?jeton=@JETON', session: false },
];

/** Relevé des textes visibles, exécuté DANS la page. Un « bloc » est un élément dont les enfants sont tous en ligne : son
 *  texte est lu d'un bloc (comme le fait un Text.rich côté Flutter), jamais morcelé par un <strong>. */
function releve() {
  const INLINE = new Set(['SPAN', 'B', 'STRONG', 'EM', 'I', 'A', 'SVG', 'SMALL', 'CODE', 'BR', 'KBD', 'MARK', 'U', 'SUB', 'SUP', 'IMG', 'INPUT', 'SELECT', 'TEXTAREA', 'PATH', 'LINE', 'CIRCLE', 'RECT', 'POLYLINE', 'POLYGON']);
  const norm = (s) => (s || '').replace(/\s+/g, ' ').trim();
  const visible = (el) => {
    if (!el || !el.getClientRects().length) return false;
    for (let e = el; e && e !== document.documentElement; e = e.parentElement) {
      const st = getComputedStyle(e);
      if (st.display === 'none' || st.visibility === 'hidden') return false;
    }
    return true;
  };
  const racine = document.getElementById('page') || document.body;
  const sortie = { titre: null, description: [], cartes: [], commandes: [], champs: [] };
  const vus = { description: new Set(), cartes: new Set(), commandes: new Set(), champs: new Set() };
  const poser = (cle, t) => { t = norm(t); if (!t || vus[cle].has(t)) return; vus[cle].add(t); sortie[cle].push(t); };
  const FORMAT = new Set(['B', 'STRONG', 'EM', 'I', 'SMALL', 'CODE', 'BR', 'KBD', 'MARK', 'U', 'SUB', 'SUP']);
  const texteDirect = (el) => norm(Array.from(el.childNodes).filter((n) => n.nodeType === 3).map((n) => n.textContent).join(' '));
  const parcourir = (el) => {
    const tag = el.tagName.toUpperCase();
    if (['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE', 'SVG', 'OPTION'].includes(tag)) return;
    if (!visible(el)) return;
    /* Attributs lus par l'agent : placeholder, aria-label, title. */
    ['placeholder', 'aria-label', 'title'].forEach((a) => { const v = el.getAttribute(a); if (v && norm(v)) poser('champs', v); });
    if (tag === 'INPUT' && ['button', 'submit'].includes(el.type) && el.value) poser('commandes', el.value);
    /* Une liste fermée ne montre que son choix courant : les autres entrées n'existent à l'écran qu'une fois la liste ouverte. */
    if (tag === 'SELECT') Array.from(el.selectedOptions).forEach((o) => poser('champs', o.textContent));
    if (['BUTTON', 'A'].includes(tag) || el.getAttribute('role') === 'button') {
      const t = norm(el.textContent);
      if (t) poser('commandes', t);
      return;
    }
    if (tag === 'LABEL') { poser('champs', Array.from(el.childNodes).filter((n) => n.nodeType === 3 || (n.nodeType === 1 && !/^(INPUT|SELECT|TEXTAREA)$/.test(n.tagName))).map((n) => n.textContent).join(' ')); }
    else if (/^H[1-6]$/.test(tag)) { if (tag === 'H1' && !sortie.titre) sortie.titre = norm(el.textContent); else poser('cartes', el.textContent); return; }
    else {
      const enfants = Array.from(el.children).filter((c) => !['SVG', 'IMG', 'PATH'].includes(c.tagName.toUpperCase()));
      const commandes = !!el.querySelector('input,select,textarea,button,a');
      if (!enfants.length) poser('description', el.textContent);
      else if (!commandes && texteDirect(el) && enfants.every((c) => FORMAT.has(c.tagName.toUpperCase()) || c.tagName.toUpperCase() === 'SPAN')) { poser('description', el.textContent); return; }
      else if (texteDirect(el)) poser('description', texteDirect(el));
    }
    Array.from(el.children).forEach(parcourir);
  };
  parcourir(racine);
  /* Les libellés de <label> sont déjà dans « champs » : on les retire de la description pour ne pas les compter deux fois. */
  sortie.description = sortie.description.filter((t) => !vus.champs.has(t) && !vus.commandes.has(t) && !vus.cartes.has(t));
  if (!sortie.titre) sortie.titre = norm(document.title);
  sortie.titreOnglet = norm(document.title);
  return sortie;
}

async function jetonValide(page) {
  /* Une enquête ET un jeton valides, créés par le magasin de la maquette puis envoyés au serveur : la page publique les relit. */
  return page.evaluate(async () => {
    const S = SIGH.store;
    const enq = S.collection('enquetes', { module: 'M13', entite: 'modèle d’enquête', prefix: 'ENQ' });
    let e = enq.all().find((x) => x.statut !== 'archive');
    if (!e) {
      e = enq.insert({ reference: 'ENQ-SAT', titre: 'Satisfaction des patients', description: 'Recueil à la sortie.', questions: [
        { code: 'Q_ACCUEIL', libelle: 'Qualité de l’accueil', type: 'note' },
        { code: 'Q_RECO', libelle: 'Recommanderiez-vous la clinique ?', type: 'choix', options: ['Oui', 'Non'] },
        { code: 'Q_LIBRE', libelle: 'Ce que nous pourrions améliorer', type: 'texte' }] }).record;
    }
    const code = SIGH.parcours.jetonEnquete();
    const j = S.collection('jetonsEnquete', { module: 'M13', entite: 'lien de partage', prefix: 'JET' });
    const jr = j.insert({ jeton: code, enqueteId: e.id, enqueteTitre: e.titre, anonyme: true, usage: 'Lien', creeLe: SIGH.core.iso(new Date()),
      expireLe: '2099-12-31', revoqueLe: null, note: null, ouvertPar: 'extraction' });
    if (S.vider) await S.vider(); else if (S.flush) await S.flush();
    await new Promise((r) => setTimeout(r, 2500));
    return { code, fixtureEnquete: JSON.parse(JSON.stringify({ enquete: e, jeton: jr.record })) };
  });
}

(async () => {
  console.log('▶ Extraction des écrans autonomes');
  const m = await ouvrirMaquette();
  const navigateur = m.page.context().browser();
  const manifeste = JSON.parse(fs.readFileSync(path.join(REPO, 'packages/referentiels/data/manifeste.json'), 'utf8'));
  const resume = [];
  try {
    let jeton = null; let fixtureEnquete = null;
    if (!filtre.length || filtre.includes('enquete-publique')) { const r0 = await jetonValide(m.page); jeton = r0.code; fixtureEnquete = r0.fixtureEnquete; }
    for (const e of ECRANS) {
      if (filtre.length && !filtre.includes(e.id)) continue;
      /* Un contexte NEUF par écran : sans session pour les pages d'accès, avec la session du banc pour le verrou. */
      const ctx = await navigateur.newContext({ viewport: { width: 1440, height: 900 } });
      const page = await ctx.newPage();
      if (e.session) {
        const j = (await BANC.connecter(BANC.SESSION_BANC.identifiant) || {}).jeton;
        await page.addInitScript(([s, t]) => { localStorage.setItem('sigh-cnt:session', JSON.stringify(s)); localStorage.setItem('sigh-cnt:jeton', t); },
          [Object.assign({}, BANC.SESSION_BANC, { jeton: j }), j]);
      }
      const url = `http://127.0.0.1:${BANC.PORT_PHP}` + e.url.replace('@JETON', jeton || 'inconnu');
      let fiche;
      try {
        await page.goto(url, { waitUntil: 'load' });
        await page.waitForFunction(() => document.body && document.body.innerText.replace(/\s+/g, ' ').trim().length > 15, null, { timeout: 15000 });
        await page.waitForTimeout(1200);
        const urlFinale = page.url();
        const r = await page.evaluate(releve);
        const man = manifeste.ecrans.find((x) => x.id === e.id) || {};
        fiche = { id: e.id, module: man.module || 'AUTH', domaine: man.domaine || 'Système', libelleManifeste: man.label || e.id, acces: 'ouvert',
          autonome: true, titre: r.titre, titreOnglet: r.titreOnglet, description: r.description, cartes: r.cartes, champs: r.champs, commandes: r.commandes };
        if (e.id === 'enquete-publique') fiche.fixtureEnquete = fixtureEnquete;
        if (new URL(urlFinale).pathname !== new URL(url).pathname) fiche.redirigeVers = new URL(urlFinale).pathname;
      } catch (err) { fiche = { id: e.id, acces: 'erreur', erreur: String(err.message || err).slice(0, 160) }; }
      await ctx.close();
      resume.push(fiche);
      console.log(`  ${e.id} : ${fiche.acces}${fiche.redirigeVers ? ' → ' + fiche.redirigeVers : ''}`);
      if (DRY) console.log(JSON.stringify(fiche, null, 1));
      else if (fiche.acces === 'ouvert') fs.writeFileSync(path.join(SORTIE, e.id + '.json'), JSON.stringify(fiche, null, 1) + '\n');
    }
  } finally { await m.fermer(); }
  /* L'index général des fiches reprend les neuf lignes (ouvert), sans rien refaire des autres. */
  const fIndex = path.join(SORTIE, 'ecrans.index.json');
  if (!DRY && fs.existsSync(fIndex)) {
    const idx = JSON.parse(fs.readFileSync(fIndex, 'utf8'));
    resume.filter((f) => f.acces === 'ouvert').forEach((f) => {
      const ligne = { id: f.id, acces: f.acces, titre: f.titre || null, kpis: 0, tableaux: 0, onglets: 0, commandes: (f.commandes || []).length };
      const i = idx.ecrans.findIndex((x) => x.id === f.id);
      if (i >= 0) idx.ecrans[i] = ligne; else idx.ecrans.push(ligne);
    });
    fs.writeFileSync(fIndex, JSON.stringify(idx, null, 1) + '\n');
  }
  const ko = resume.filter((f) => f.acces !== 'ouvert');
  if (ko.length) { console.error('  ÉCHEC : ' + ko.map((f) => f.id).join(', ')); process.exit(1); }
})().catch((e) => { console.error(e); process.exit(1); });
