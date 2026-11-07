/* =============================================================================
 * VECTEURS DE RAP — rapports-bibliotheque, rapports-direction, rapports-generateur, rapports-historique
 * -----------------------------------------------------------------------------
 * Les quatre écrans RÉELS de `assets/js/modules/rapports.js`, montés dans Chrome sur le JEU DU POSTE (horloge figée 30/10/2026 10 h), lus comme l'agent
 * les lit et PILOTÉS (période × axe × cumul détaillé × date d'arrêté, modèles du générateur, refus, historique avec éditions réelles).
 * `ECRANS` (le rattachement état → écran producteur) est une variable de fermeture : elle est EXPOSÉE par un remplacement ancré dans le texte du module
 * (`window.__ECRANS`), le module lui-même n'est pas modifié.
 *   SIGH_PORT_PHP=10731 flock /tmp/sigh-banc.lock node build/vecteurs-rapports.js   →   packages/domaine/test/vecteurs/rap.json
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');
const JEU = path.resolve(ROOT, '..', 'apps', 'poste', 'assets', 'donnees', 'jeu');
const NOMS_JEU = fs.readdirSync(JEU).filter((f) => f.endsWith('.json') && f !== 'referentiels.json').map((f) => f.replace(/\.json$/, ''));

(async () => {
  console.log('▶ Vecteurs de RAP — quatre écrans');
  const m = await ouvrirMaquette();
  try {
    await m.page.evaluate(() => {
      const Vrai = Date;
      window.__Vrai = Vrai;
      window.__FIXE = new Vrai(2026, 9, 30, 10, 0, 0).getTime();
      class Faux extends Vrai { constructor(...a) { if (a.length === 0) super(window.__FIXE); else super(...a); } static now() { return window.__FIXE; } }
      window.Date = Faux;
      SIGH.core.aujourdhui = () => new Faux();
      window.__etats = []; window.__erreurs = []; window.addEventListener('error', (e) => window.__erreurs.push(String(e.message)));
      SIGH.ui.sonner = () => {};
      SIGH.print.etat = function (o) {
        const tab = [];
        const c = o.contenu;
        if (c && c.querySelectorAll) {
          (c.tagName === 'TABLE' ? [c] : [...c.querySelectorAll('table')]).forEach((t) => tab.push({
            entetes: [...t.querySelectorAll('thead th')].map((x) => x.innerText.replace(/\s+/g, ' ').trim()),
            lignes: [...t.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => td.innerText.replace(/\s+/g, ' ').trim())),
            pied: [...t.querySelectorAll('tfoot tr')].map((tr) => [...tr.children].map((td) => td.innerText.replace(/\s+/g, ' ').trim())),
          }));
        }
        window.__etats.push(JSON.parse(JSON.stringify({
          titre: o.titre, sousTitre: o.sousTitre || null, filigrane: o.filigrane || null, cartouche: o.cartouche || null, signatures: o.signatures || null,
          texte: c && c.innerText ? c.innerText.replace(/\s+/g, ' ').trim() : null, tableaux: tab,
        })));
      };
      /* Les données BRUTES de chaque tableau et de chaque graphique : ce que l'écran calcule, avant pagination. */
      window.__tables = []; window.__barres = []; window.__rankings = [];
      const dt = SIGH.ui.dataTable;
      SIGH.ui.dataTable = function (cfg) {
        window.__tables.push(JSON.parse(JSON.stringify({ title: cfg.title, rows: cfg.rows, colonnes: cfg.columns.map((c) => c.label), filtres: (cfg.filters || []).map((f) => [f.name, f.label, f.options]) })));
        return dt.apply(this, arguments);
      };
      const gb = SIGH.charts.barres;
      SIGH.charts.barres = function (etiquettes, series) { window.__barres.push(JSON.parse(JSON.stringify({ etiquettes, series }))); return gb.apply(this, arguments); };
      const rk = SIGH.kit.ranking;
      SIGH.kit.ranking = function (items) { window.__rankings.push(JSON.parse(JSON.stringify(items))); return rk.apply(this, arguments); };
      window.__go = []; SIGH.app.go = function (id, o) { window.__go.push([id, o || null]); };
    });
    /* ECRANS exposé par un remplacement ANCRÉ (une seule occurrence) — le module n'est pas modifié sur le disque. */
    const src = fs.readFileSync(path.join(ROOT, 'assets/js/modules/rapports.js'), 'utf8');
    const ancre = '  function catalogue() {';
    if (src.split(ancre).length !== 2) throw new Error('ancre `function catalogue()` introuvable ou multiple');
    await m.page.addScriptTag({ content: src.replace(ancre, '  global.__ECRANS = ECRANS;\n' + ancre) });

    await m.page.evaluate(() => {
      const norm = (t) => String(t == null ? '' : t).replace(/[\n\t\r]+/g, ' ').replace(/\s+/g, ' ').trim();
      window.H = {
        norm,
        dormir: (ms) => new Promise((r) => setTimeout(r, ms)),
        kpis: (root) => [...root.querySelectorAll('.kpi')].map((k) => {
          const p = k.querySelectorAll('p');
          return { libelle: norm(p[0].innerText), valeur: norm(p[1].innerText), indice: p[2] ? norm(p[2].innerText) : null };
        }),
        cartes: (root) => [...root.querySelectorAll('.card')].map((c) => {
          const h = c.querySelector('.card-header, .card-head, h3, h2');
          return h ? norm(h.innerText) : null;
        }).filter(Boolean),
        notes: (root) => [...root.querySelectorAll('.rounded-lg.border')].map((n) => norm(n.innerText)).filter((t) => t.length > 20),
        boutons: (racine) => [...racine.querySelectorAll('button, a.btn')].map((b) => norm(b.textContent || b.getAttribute('aria-label') || b.title)).filter(Boolean),
        toasts: () => [...document.querySelectorAll('#toast-host > div')].map((n) => [...n.querySelectorAll('p')].map((p) => p.textContent.trim())),
        viderToasts: () => { const h = document.getElementById('toast-host'); if (h) h.innerHTML = ''; },
        monter: async (id) => {
          const root = document.createElement('div'); document.body.appendChild(root);
          window.__etats.length = 0; window.__tables.length = 0; window.__barres.length = 0; window.__rankings.length = 0;
          SIGH.screens[id].render(root);
          await new Promise((r) => setTimeout(r, 300));
          return root;
        },
        retirer: (root) => { root.remove(); },
        poser: (el, v) => { if (el.type === 'checkbox') el.checked = !!v; else el.value = v; el.dispatchEvent(new Event('input', { bubbles: true })); el.dispatchEvent(new Event('change', { bubbles: true })); },
        bouton: (racine, texte) => [...racine.querySelectorAll('button, a.btn')].find((b) => norm(b.textContent) === texte),
      };
    });

    /* Le JEU DU POSTE entier est posé dans le magasin de la maquette : ce que l'écran lit est ce que le poste lit. */
    const jeu = Object.fromEntries(NOMS_JEU.map((n) => [n, JSON.parse(fs.readFileSync(path.join(JEU, n + '.json'), 'utf8'))]));
    await m.page.evaluate((j) => {
      const S = SIGH.store;
      window.__jeu = j;
      for (const [nom, lignes] of Object.entries(j)) {
        S.collection(nom).all();
        const brut = S.raw()[nom];
        if (Array.isArray(brut)) { brut.splice(0); lignes.forEach((x) => brut.push(JSON.parse(JSON.stringify(x)))); }
      }
    }, jeu);

    const sortie = { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-rapports.js — ne pas éditer. Horloge : 30/10/2026 10 h. Jeu : apps/poste/assets/donnees/jeu.' };
    const essayer = async (nom, f) => { try { sortie[nom] = await f(); } catch (e) { sortie[nom] = { erreur: String(e && e.stack || e) }; console.log('  ERREUR ' + nom + ' : ' + String(e && e.message || e)); } };

    /* ---------------------------------------------------------------- constantes */
    await essayer('constantes', () => m.page.evaluate(() => {
      const D = SIGH.data, C = SIGH.core;
      return JSON.parse(JSON.stringify({
        catalogue: D.CATALOGUE_ETATS,
        ecrans: Object.entries(window.__ECRANS),
        nbAnalyses: D.ANALYSES.length, nbAssureurs: D.ASSUREURS.length,
        brand: { nom: C.BRAND.nom, bp: C.BRAND.bp, telephones: C.BRAND.telephones, email: C.BRAND.email, autorisation: C.BRAND.autorisation, ifu: C.BRAND.ifu, rccm: C.BRAND.rccm, devise: C.BRAND.devise },
        utilisateur: SIGH.store.currentUser(),
      }));
    }));

    /* ---------------------------------------------------------------- 1. bibliothèque */
    await essayer('bibliotheque', () => m.page.evaluate(async () => {
      const root = await H.monter('rapports-bibliotheque');
      const cartes = [...root.querySelectorAll('.card')].map((c) => {
        const h = c.querySelector('.card-header, .card-head, h3, h2');
        const lignes = [...c.querySelectorAll('.flex.items-center.gap-3.rounded-lg.border')].map((l) => ({
          etat: H.norm(l.innerText).replace(/ ?(Éditer|À venir)$/, ''),
          action: H.norm((l.querySelector('a.btn') || { innerText: '' }).innerText) || (H.norm(l.innerText).endsWith('À venir') ? 'À venir' : ''),
          href: l.querySelector('a.btn') ? l.querySelector('a.btn').getAttribute('href') : null,
        }));
        return { titre: h ? H.norm(h.innerText) : null, lignes };
      });
      const liens = [...root.querySelectorAll('a.btn')].map((a) => [H.norm(a.innerText), a.getAttribute('href')]);
      const out = {
        kpis: H.kpis(root), cartes, noms: H.cartes(root), notes: H.notes(root), liens,
        cardMentions: H.norm([...root.querySelectorAll('.card')].find((c) => H.norm(c.innerText).startsWith('Mentions portées')).innerText),
        cardPied: H.norm([...root.querySelectorAll('.card')].find((c) => H.norm(c.innerText).startsWith('Pied de page')).innerText),
        texte: H.norm(root.innerText),
      };
      H.retirer(root);
      return out;
    }));

    /* ---------------------------------------------------------------- 2. générateur */
    await essayer('generateur', () => m.page.evaluate(async () => {
      const out = {};
      const root = await H.monter('rapports-generateur');
      const champs = () => {
        const r = {};
        [...root.querySelectorAll('input, select')].forEach((e, i) => {
          const lab = e.closest('div') && e.closest('div').querySelector('label') ? H.norm(e.closest('div').querySelector('label').innerText) : null;
          r[(e.id || ('c' + i))] = { type: e.type, valeur: e.type === 'checkbox' ? e.checked : e.value, libelle: lab,
            options: e.tagName === 'SELECT' ? [...e.options].map((o) => o.value) : null };
        });
        return r;
      };
      const cases = () => [...root.querySelectorAll('input[type=checkbox]')].map((c) => [H.norm(c.parentElement.innerText), c.checked]);
      out.initial = { champs: champs(), cases: cases(), cartes: H.cartes(root), boutons: H.boutons(root), notes: H.notes(root), texte: H.norm(root.innerText) };
      /* génération par défaut */
      const lancer = async () => {
        H.viderToasts(); window.__etats.length = 0;
        H.bouton(root, 'Prévisualiser et imprimer').click(); await H.dormir(150);
        return { etat: window.__etats.slice(), toasts: H.toasts() };
      };
      out.defaut = await lancer();
      /* chaque modèle enregistré */
      out.modeles = {};
      for (const nom of ['Rapport d’activité mensuel', 'Situation des stocks', 'Rapport financier trimestriel', 'Bilan social']) {
        H.viderToasts();
        H.bouton(root, nom.replace(/\s+/g, ' ')) ? 0 : 0;
        const b = [...root.querySelectorAll('button')].find((x) => H.norm(x.innerText).startsWith(nom));
        b.click(); await H.dormir(100);
        const apres = { toasts: H.toasts(), champs: champs(), cases: cases() };
        apres.gen = await lancer();
        out.modeles[nom] = apres;
      }
      /* toutes les sections, filigrane, période libre */
      [...root.querySelectorAll('input[type=checkbox]')].forEach((c) => H.poser(c, true));
      const ctl = [...root.querySelectorAll('input, select')].filter((e) => e.type !== 'checkbox');
      const par = (lib) => ctl.find((e) => e.closest('div') && e.closest('div').querySelector('label') && H.norm(e.closest('div').querySelector('label').innerText).startsWith(lib));
      H.poser(par('Titre'), 'Rapport complet'); H.poser(par('Sous-titre'), ''); H.poser(par('Filigrane'), 'Confidentiel'); H.poser(par('Période'), 'Annuelle'); H.poser(par('Destinataire'), 'Partenaire technique');
      H.poser(par('Du'), '2026-01-01'); H.poser(par('Au'), '2026-06-30');
      out.toutes = await lancer();
      /* refus : aucune section ; titre vide */
      [...root.querySelectorAll('input[type=checkbox]')].forEach((c) => H.poser(c, false));
      out.refusSections = await lancer();
      [...root.querySelectorAll('input[type=checkbox]')].forEach((c) => H.poser(c, true));
      H.poser(par('Titre'), '');
      out.refusTitre = await lancer();
      H.retirer(root);
      return out;
    }));

    /* Écritures déséquilibrées : la ligne « Équilibre » doit nommer l'écart. */
    await essayer('generateurEcart', () => m.page.evaluate(async () => {
      const S = SIGH.store;
      const ajout = { id: 'ECR-RAP-ECART', statut: 'valide', numero: 'ECR-RAP-ECART', date: '2026-08-10', debit: 12345, credit: 0, compte: '571000' };
      S.raw().ecritures.push(ajout);
      window.__injectionEcriture = ajout;
      const root = await H.monter('rapports-generateur');
      const cb = [...root.querySelectorAll('input[type=checkbox]')];
      cb.forEach((c) => H.poser(c, false)); H.poser(cb[5], true);
      window.__etats.length = 0;
      H.bouton(root, 'Prévisualiser et imprimer').click(); await H.dormir(150);
      const r = { injection: ajout, etat: window.__etats.slice() };
      H.retirer(root);
      return r;
    }));

    /* ---------------------------------------------------------------- 3. historique */
    const historique = () => m.page.evaluate(async () => {
      const root = await H.monter('rapports-historique');
      const t = window.__tables[0];
      const sortie = {
        kpis: H.kpis(root), notes: H.notes(root), cartes: H.cartes(root), boutons: H.boutons(root),
        lignes: t.rows, colonnes: t.colonnes, filtres: t.filtres,
        barres: window.__barres.slice(), rankings: window.__rankings.slice(), texte: H.norm(root.innerText),
      };
      H.retirer(root);
      return sortie;
    });
    await essayer('historiqueJeu', historique);
    await essayer('historiqueEditions', async () => {
      /* trois éditions ARCHIVÉES depuis l'aperçu (journal « Impression », module RAP) */
      const inj = await m.page.evaluate(() => {
        const S = SIGH.store;
        S.log('Impression', 'RAP', 'Document', 'CNT-20261030-0001', null, { titre: 'Journal d’audit' });
        S.log('Impression', 'RAP', 'Document', 'CNT-20261030-0002', null, { titre: 'Point mensuel' });
        S.log('Impression', 'RAP', 'Document', null, null, { titre: 'Sans référence' });
        return JSON.parse(JSON.stringify(S.raw().audit.slice(0, 3)));
      });
      const r = await historique();
      r.injection = inj;
      return r;
    });

    /* ---------------------------------------------------------------- 4. États de la Direction */
    const direction = (reglages) => m.page.evaluate(async (regl) => {
      const root = await H.monter('rapports-direction');
      const [selPeriode, selAxe] = root.querySelectorAll('select');
      const date = root.querySelector('input[type=date]');
      const det = root.querySelector('#f_detaille');
      const sorties = [];
      for (const r of regl) {
        window.__tables.length = 0; window.__etats.length = 0;
        // chaque changement relance `afficher()` (synchrone) : le dernier tableau capturé est celui de l'état final.
        H.poser(selPeriode, r.periode); H.poser(selAxe, r.axe); H.poser(date, r.fin); H.poser(det, r.detaille);
        const tab = window.__tables[window.__tables.length - 1] || null;
        H.bouton(root, 'Éditer l’état').click();
        sorties.push({
          reglage: r, kpis: H.kpis(root), notes: H.notes(root), titreTableau: tab && tab.title, colonnes: tab && tab.colonnes,
          lignes: tab && tab.rows, etat: window.__etats.map((e) => { const c = Object.assign({}, e); delete c.texte; return c; }),
        });
      }
      const premier = { kpis: H.kpis(root), cartes: H.cartes(root), boutons: H.boutons(root), texte: H.norm(root.innerText) };
      H.retirer(root);
      return { premier, sorties };
    }, reglages);

    const PERIODES = ['jour', 'semaine', 'mois', 'trimestre', 'semestre', 'annee'];
    const AXES = ['client', 'nature', 'assureur', 'article', 'famille', 'groupe'];
    const FINS = ['2026-10-30', '2026-08-16', '2026-06-30', '2026-12-31'];
    const grille = [];
    for (const fin of FINS) for (const p of PERIODES) for (const a of AXES) for (const d of [false, true]) grille.push({ periode: p, axe: a, fin, detaille: d });
    await essayer('direction', async () => {
      const r = await direction(grille);
      r.premier.reglageInitial = await m.page.evaluate(async () => {
        const root = await H.monter('rapports-direction');
        const [selPeriode, selAxe] = root.querySelectorAll('select');
        const date = root.querySelector('input[type=date]');
        const o = { periode: selPeriode.value, axe: selAxe.value, fin: date.value, periodes: [...selPeriode.options].map((x) => [x.value, x.text]), axes: [...selAxe.options].map((x) => [x.value, x.text]),
          kpis: H.kpis(root), texte: H.norm(root.innerText), tableaux: window.__tables.slice() };
        H.retirer(root);
        return o;
      });
      return r;
    });

    /* Cas limites : factures synthétiques (avoir négatif exclu, lignes sans montant, désignation absente, produit inconnu, sans assureur, sans patient). */
    await essayer('directionLimites', async () => {
      const inj = await m.page.evaluate(() => {
        const S = SIGH.store;
        const prod = S.raw().produits.filter((p) => p.categorie === 'reactif')[0] || S.raw().produits[0];
        const a = [
          { id: 'FAC-RAP-1', statut: 'actif', numero: 'FAC-RAP-1', date: '2026-08-10', patient: 'ZZ LIMITE Un', type: 'Pharmacie', montantTTC: 3000, montantPaye: 1000, assureur: 'NSIA', partAssurance: 2000, partPatient: 1000,
            lignes: [{ designation: 'Article X', quantite: 2, prixUnitaire: 500, produitId: prod.id }, { produit: 'Article Y', prixUnitaire: 2000 }, { quantite: 3, prixUnitaire: 100, montant: 0 }] },
          { id: 'FAC-RAP-2', statut: 'actif', numero: 'FAC-RAP-2', date: '2026-08-10', patient: '', type: '', montantTTC: 500, montantPaye: 0,
            lignes: [{ designation: 'Article X', quantite: 1, prixUnitaire: 500, produitId: 'PRD-INCONNU' }] },
          { id: 'FAC-RAP-3', statut: 'actif', numero: 'FAC-RAP-3', date: '2026-08-10', patient: 'ZZ LIMITE Deux', type: 'Soins', montantTTC: -800, montantPaye: 0, lignes: [{ designation: 'Avoir', quantite: 1, prixUnitaire: -800 }] },
          { id: 'FAC-RAP-4', statut: 'actif', numero: 'FAC-RAP-4', date: '2026-08-10', patient: 'ZZ LIMITE Un', type: 'Soins', montantTTC: 700, montantPaye: 700, assureur: '', lignes: [] },
          { id: 'FAC-RAP-5', statut: 'actif', numero: 'FAC-RAP-5', date: '2026-08-11', patient: 'ZZ LIMITE Trois', type: 'Soins', montantTTC: 900, montantPaye: 900, partPatient: 0, partAssurance: 0 },
        ];
        a.forEach((x) => S.raw().factures.push(x));
        return { factures: a, produitId: prod.id, categorie: prod.categorie };
      });
      const reglages = [];
      for (const p of ['jour', 'semaine']) for (const ax of AXES) for (const d of [false, true]) reglages.push({ periode: p, axe: ax, fin: '2026-08-10', detaille: d });
      for (const ax of AXES) reglages.push({ periode: 'mois', axe: ax, fin: '2026-08-11', detaille: true });
      const r = await direction(reglages);
      r.injection = inj;
      /* retrait : les factures synthétiques ne polluent pas la suite */
      await m.page.evaluate(() => { const f = SIGH.store.raw().factures; for (let i = f.length - 1; i >= 0; i--) if (String(f[i].id).startsWith('FAC-RAP-')) f.splice(i, 1); });
      return r;
    });

    sortie.erreurs = await m.page.evaluate(() => window.__erreurs);
    ecrire('packages/domaine/test/vecteurs/rap.json', sortie);
    console.log('  erreurs de page : ' + sortie.erreurs.length);
    for (const k of Object.keys(sortie)) if (sortie[k] && sortie[k].erreur) console.log('  ÉCHEC ' + k + ' : ' + String(sortie[k].erreur).split('\n')[0]);
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
