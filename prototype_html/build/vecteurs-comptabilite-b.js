/* =============================================================================
 * VECTEURS DE M12 (tranche « comptabilité B ») — m12-analytique, m12-budgets, m12-immobilisations, m12-banques, m12-compte-resultat,
 * m12-flux-tresorerie, m12-seuil-rentabilite — tirés des ÉCRANS RÉELS pilotés dans Chrome.
 * -----------------------------------------------------------------------------
 *   node build/vecteurs-comptabilite-b.js      (sous flock /tmp/sigh-banc.lock ; SIGH_PORT_PHP=<port inhabituel 100xx>)
 *
 * Le JEU du poste (apps/poste/assets/donnees/jeu) est posé dans le magasin de la maquette ; l'horloge de la page est décalée au 30/10/2026 10 h.
 * Les écrans sont MONTÉS, lus comme l'agent les lit, et leurs gestes sont ACCOMPLIS par les boutons.
 * Sorties (ENGENDRÉES) : packages/domaine/test/vecteurs/comptabilite_b.json, packages/domaine/lib/src/comptabilite/cpb_liasse.dart (la liasse DÉPOSÉE,
 * `SIGH.liasse`) et cpb_donnees.dart (`D.RUBRIQUES_RESULTAT`, `D.NATURE_CHARGE`). Jamais recopiés à la main.
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');
const JEU_DIR = path.join(ROOT, '..', 'apps/poste/assets/donnees/jeu');
const NOMS = ['ecritures', 'comptes', 'banques', 'centresCouts', 'depenses', 'factures', 'budgets', 'immobilisations', 'rapprochements'];
const jeu = {};
NOMS.forEach((n) => { jeu[n] = JSON.parse(fs.readFileSync(path.join(JEU_DIR, n + '.json'), 'utf8')); });

/* Littéral Dart d'une valeur JSON (const) : clés chaînes, `$` et `\` échappés. */
function litDart(v, ind) {
  const pad = '  '.repeat(ind || 0);
  if (v === null || v === undefined) return 'null';
  if (typeof v === 'number' || typeof v === 'boolean') return String(v);
  if (typeof v === 'string') return "'" + v.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$').replace(/\n/g, '\\n') + "'";
  if (Array.isArray(v)) return '[\n' + v.map((x) => pad + '  ' + litDart(x, (ind || 0) + 1) + ',').join('\n') + '\n' + pad + ']';
  return '{\n' + Object.keys(v).map((k) => pad + '  ' + litDart(k) + ': ' + litDart(v[k], (ind || 0) + 1) + ',').join('\n') + '\n' + pad + '}';
}

(async () => {
  console.log('▶ Vecteurs de M12-B (7 écrans)');
  const m = await ouvrirMaquette();
  try {
    await m.page.evaluate(() => {
      const Reel = window.Date;
      const decalage = new Reel(2026, 9, 30, 10, 0, 0).getTime() - Reel.now();
      const maintenant = () => Reel.now() + decalage;
      function Decalee() {
        if (!(this instanceof Decalee)) return String(new Reel(maintenant()));
        if (arguments.length === 0) return new Reel(maintenant());
        return new (Function.prototype.bind.apply(Reel, [null].concat(Array.prototype.slice.call(arguments))))();
      }
      Decalee.prototype = Reel.prototype; Decalee.now = maintenant; Decalee.UTC = Reel.UTC; Decalee.parse = Reel.parse;
      window.Date = Decalee;
    });
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m12-comptabilite.js') });
    const sortie = await m.page.evaluate(async (jeu) => {
      const S = SIGH.store, C = SIGH.core, D = SIGH.data;
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
      const texte = (e) => ((e && e.innerText) || '').replace(/\s+/g, ' ').trim();
      const db = () => S.raw();
      const poserJeu = () => { Object.keys(jeu).forEach((n) => { db()[n] = propre(jeu[n]); }); };
      poserJeu();

      const pieces = [], toasts = [], graphiques = [];
      SIGH.print.etat = function (o) {
        pieces.push({
          titre: o.titre, sousTitre: o.sousTitre || null, cartouche: propre(o.cartouche || []),
          contenu: o.contenu ? texte(o.contenu) : null,
          tables: o.contenu && o.contenu.querySelectorAll ? [...o.contenu.querySelectorAll('table')].map((tb) => ({
            entetes: [...tb.querySelectorAll('thead tr')].map((tr) => [...tr.querySelectorAll('th')].map(texte)),
            lignes: [...tb.querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('td')].map(texte)),
            pied: [...tb.querySelectorAll('tfoot td, tfoot th')].map(texte),
          })) : [],
          signatures: propre(o.signatures || []),
        });
      };
      const derniere = () => pieces[pieces.length - 1];
      const toastReel = SIGH.ui.toast;
      SIGH.ui.toast = function (message, opts) { toasts.push({ message: String(message), type: (opts && opts.type) || null, detail: (opts && opts.detail) || null }); return toastReel.apply(this, arguments); };
      ['ligne', 'anneau', 'barres'].forEach((k) => {
        const f = SIGH.charts[k];
        SIGH.charts[k] = function () {
          const a = [...arguments];
          graphiques.push({ type: k, etiquettes: propre(a[0]), series: k === 'anneau' ? propre(a[1]) : propre((a[1] || []).map((s) => ({ label: s.label, data: s.data }))) });
          return f.apply(this, arguments);
        };
      });

      function releve(root) {
        const kpis = [...root.querySelectorAll('.kpi')].map((k) => ({
          label: texte(k.querySelector('.kpi-label')), valeur: texte(k.querySelector('.kpi-value')),
          indice: (() => { const h = k.querySelector('p.mt-1.text-xs.text-slate-400'); return h ? texte(h) : null; })(),
        }));
        const tables = [...root.querySelectorAll('table')].map((tb) => {
          const carte = tb.closest('.card');
          const h = carte && carte.querySelector('.card-title');
          return {
            titre: h ? texte(h) : null,
            entetes: [...tb.querySelectorAll('thead tr')].map((tr) => [...tr.querySelectorAll('th')].map(texte).filter((s) => s !== '')),
            lignes: [...tb.querySelectorAll('tbody tr')].map((tr) => ({
              cellules: [...tr.querySelectorAll('td')].map(texte),
              boutons: [...tr.querySelectorAll('button')].map((b) => b.getAttribute('title') || b.getAttribute('aria-label') || texte(b)).filter(Boolean),
            })),
          };
        });
        const onglets = [...root.querySelectorAll('button.tab')].map(texte);
        const cartes = [...root.querySelectorAll('.card-title')].map(texte);
        const boutons = [...root.querySelectorAll('button')].map((b) => b.getAttribute('title') || b.getAttribute('aria-label') || texte(b)).filter(Boolean);
        const notes = [...root.querySelectorAll('.rounded-lg.border')].map(texte).filter((t) => t.length > 0);
        return { kpis, tables, onglets, cartes, boutons, notes };
      }
      async function monter(id) {
        const root = document.createElement('div'); document.body.appendChild(root);
        SIGH.screens[id].render(root); await dormir(200);
        return root;
      }
      const bouton = (portee, re) => [...portee.querySelectorAll('button')].find((b) => re.test(texte(b)) || re.test(b.getAttribute('title') || ''));
      async function cliquer(portee, re) { const b = bouton(portee, re); if (!b) throw new Error('bouton introuvable : ' + re); b.click(); await dormir(150); return b; }
      async function onglet(root, re) { const b = [...root.querySelectorAll('button.tab')].find((x) => re.test(texte(x))); if (!b) throw new Error('onglet introuvable ' + re); b.click(); await dormir(150); }
      function poser(portee, nom, valeur) {
        const e = portee.querySelector('#f_' + nom) || portee.querySelector('[name="' + nom + '"]');
        if (!e) throw new Error('champ introuvable : ' + nom);
        e.value = valeur; e.dispatchEvent(new Event('input', { bubbles: true })); e.dispatchEvent(new Event('change', { bubbles: true }));
      }
      async function poserId(id, valeur) {
        const e = document.getElementById(id);
        if (!e) throw new Error('champ introuvable : ' + id);
        e.value = valeur; e.dispatchEvent(new Event('change', { bubbles: true })); await dormir(150);
      }
      const fermerDialogues = () => { document.querySelectorAll('[role=dialog]').forEach((d) => d.remove()); };
      const dialogue = () => [...document.querySelectorAll('[role=dialog]')].pop();
      const instantane = (noms) => { const o = {}; noms.forEach((n) => { o[n] = propre(db()[n] || []); }); return o; };
      const IGN = new Set(['_creePar', '_creeLe', '_modifiePar', '_modifieLe', '_archivePar', '_archiveLe', 'id']);
      const net = (f) => { const c = propre(f); IGN.forEach((k) => delete c[k]); return c; };
      function ecart(avant, apres) {
        const inserts = {}, modifs = {};
        Object.keys(apres).forEach((n) => {
          const a = new Map((avant[n] || []).map((f) => [f.id, f]));
          apres[n].forEach((f) => {
            if (!a.has(f.id)) { (inserts[n] = inserts[n] || []).push(net(f)); return; }
            const b = a.get(f.id), patch = {};
            Object.keys(f).forEach((k) => { if (!IGN.has(k) && JSON.stringify(f[k]) !== JSON.stringify(b[k])) patch[k] = f[k]; });
            Object.keys(b).forEach((k) => { if (!IGN.has(k) && !(k in f)) patch[k] = null; });
            if (Object.keys(patch).length) (modifs[n] = modifs[n] || []).push({ cle: b.numero || b.reference || b.num || b.id, patch: propre(patch) });
          });
        });
        return { inserts, modifs };
      }
      async function chercher(portee, valeur) {
        const i = portee.querySelector('input[type=search], input[placeholder^="Rechercher"]');
        if (!i) throw new Error('recherche introuvable');
        i.value = valeur; i.dispatchEvent(new Event('input', { bubbles: true })); await dormir(250);
      }
      async function filtrer(root, label, valeur) {
        const s = [...root.querySelectorAll('select[aria-label]')].find((x) => x.getAttribute('aria-label') === label);
        if (!s) throw new Error('filtre introuvable : ' + label);
        s.value = valeur; s.dispatchEvent(new Event('change', { bubbles: true })); await dormir(80);
      }
      const vuToasts = (depuis) => toasts.slice(depuis);

      const R = {};
      const L = SIGH.liasse;
      const donnees = {
        liasse: propre({ DEPOT: L.DEPOT, BILAN_ACTIF: L.BILAN_ACTIF, BILAN_PASSIF: L.BILAN_PASSIF, RESULTAT: L.RESULTAT, FLUX: L.FLUX,
          DISPONIBILITES: L.DISPONIBILITES, SYNTHESE: L.SYNTHESE, NOTES_SYNTHESE: L.NOTES_SYNTHESE, ECARTS: L.ECARTS }),
        rubriquesResultat: propre(D.RUBRIQUES_RESULTAT),
        natureCharge: propre(D.NATURE_CHARGE),
      };
      const referentiels = {
        centres: propre(D.CENTRES_COUT), exerciceChoisi: SIGH.exercice.choisi(),
        provisoires: SIGH.exercice.provisoires(SIGH.exercice.choisi()).length,
      };

      /* ---------- feuillets 7/51 et 8/51 ---------------------------------------------------------------------------------------- */
      async function feuillet(id, genre) {
        const scen = {};
        const sc = [
          ['defaut', null, null], ['2026_juin', '2026', '2026-06-30'], ['2026_dec', '2026', '2026-12-31'],
          ['depose', 'depose', null], ['2026_vide', '2026', '2026-01-01'],
        ];
        for (const [nom, choix, arrete] of sc) {
          graphiques.length = 0;
          const root = await monter(id);
          if (choix) await poserId('feuillet-exercice-' + genre, choix);
          if (arrete) await poserId('feuillet-arrete-' + genre, arrete);
          const r = releve(root);
          r.reglages = { exercice: document.getElementById('feuillet-exercice-' + genre).value, arrete: document.getElementById('feuillet-arrete-' + genre).value,
            arreteVisible: !document.getElementById('feuillet-arrete-' + genre).parentElement.hidden };
          r.options = [...document.getElementById('feuillet-exercice-' + genre).options].map((o) => [o.value, texte(o)]);
          r.graphiques = propre(graphiques);
          r.entete = [...root.querySelectorAll('.grid.gap-x-8 div.flex')].map(texte);
          if (nom === 'defaut' || nom === 'depose') {
            const pa = pieces.length;
            await cliquer(root, genre === 'resultat' ? /Imprimer le compte de résultat/ : /Imprimer le tableau des flux/);
            r.piece = pieces.length > pa ? derniere() : null;
          }
          scen[nom] = r; root.remove();
        }
        return scen;
      }
      R['m12-compte-resultat'] = await feuillet('m12-compte-resultat', 'resultat');
      R['m12-flux-tresorerie'] = await feuillet('m12-flux-tresorerie', 'flux');

      /* ---------- seuil de rentabilité ------------------------------------------------------------------------------------------- */
      {
        const scen = {};
        async function lire(periode, arrete) {
          graphiques.length = 0;
          const root = await monter('m12-seuil-rentabilite');
          if (periode || arrete) {
            const sel = root.querySelector('select'), inp = root.querySelector('input[type=date]');
            if (periode) { sel.value = periode; sel.dispatchEvent(new Event('change', { bubbles: true })); }
            if (arrete) { inp.value = arrete; inp.dispatchEvent(new Event('change', { bubbles: true })); }
            await dormir(200);
          }
          const r = releve(root);
          r.periodes = [...root.querySelector('select').options].map((o) => [o.value, texte(o)]);
          r.reglages = { periode: root.querySelector('select').value, arrete: root.querySelector('input[type=date]').value };
          r.graphiques = propre(graphiques);
          return { root, r };
        }
        for (const [nom, p, a] of [['defaut', null, null], ['mois', 'mois', null], ['semestre', 'semestre', '2026-06-30'], ['jour', 'jour', null], ['trimestre_aout', 'trimestre', '2026-08-31']]) {
          const { root, r } = await lire(p, a);
          if (nom === 'defaut') {
            const pa = pieces.length;
            await cliquer(root, /Imprimer l.analyse/);
            r.piece = pieces.length > pa ? derniere() : null;
            const f = {};
            r.filtres = [...root.querySelectorAll('select[aria-label]')].map((s) => ({ label: s.getAttribute('aria-label'), options: [...s.options].map((o) => [o.value, texte(o)]) }));
            await filtrer(root, 'Nature', 'variable'); f.variable = [...root.querySelectorAll('table tbody tr')].length;
            await filtrer(root, 'Nature', 'fixe'); f.fixe = [...root.querySelectorAll('table tbody tr')].length;
            await filtrer(root, 'Nature', '');
            r.filtreNb = f;
          }
          scen[nom] = r; root.remove();
        }
        // basculer la nature d'un compte : le seuil se recalcule, la décision vit au magasin
        {
          const { root, r } = await lire(null, null);
          const ligne = [...root.querySelectorAll('table tbody tr')][0];
          const avant = texte(ligne);
          const t0 = toasts.length;
          const b = [...ligne.querySelectorAll('button')].find((x) => /Basculer/.test(x.getAttribute('title') || ''));
          const titreBouton = b.getAttribute('title');
          b.click(); await dormir(300);
          const apres = releve(root);
          scen.bascule = { ligneAvant: avant, titreBouton, kpisAvant: r.kpis, kpisApres: apres.kpis, notesApres: apres.notes,
            toasts: vuToasts(t0), reglage: propre(S.reglage('naturesCharges', {})), ligneApres: texte(root.querySelectorAll('table tbody tr')[0]) };
          root.remove();
          S.setReglage('naturesCharges', {});
        }
        // tout variable : la marge sur coût variable devient nulle ou négative → seuil INCALCULABLE (un diagnostic) ; tout fixe : seuil = charges fixes / 100 %
        {
          const nums = [...new Set(db().ecritures.map((e) => String(e.compte)).filter((n) => /^6/.test(n)))];
          const corr = {}; nums.forEach((n) => { corr[n] = 'variable'; });
          S.setReglage('naturesCharges', corr);
          const a = await lire(null, null); scen.toutVariable = a.r; a.root.remove();
          const corr2 = {}; nums.forEach((n) => { corr2[n] = 'fixe'; });
          S.setReglage('naturesCharges', corr2);
          const b = await lire(null, null); scen.toutFixe = b.r; b.root.remove();
          S.setReglage('naturesCharges', {});
        }
        R['m12-seuil-rentabilite'] = scen;
      }

      /* ---------- m12-analytique ------------------------------------------------------------------------------------------------------ */
      {
        graphiques.length = 0;
        const root = await monter('m12-analytique');
        const r = releve(root);
        r.graphiques = propre(graphiques);
        const pa = pieces.length;
        await cliquer(root, /Imprimer la balance analytique/);
        r.piece = pieces.length > pa ? derniere() : null;
        R['m12-analytique'] = r; root.remove();
      }

      /* ---------- m12-budgets ----------------------------------------------------------------------------------------------------------- */
      {
        const COL = ['budgets'];
        const r = {};
        let root = await monter('m12-budgets');
        Object.assign(r, releve(root));
        graphiques.length = 0;
        await onglet(root, /Budget vs réalisé/);
        r.suivi = { graphiques: propre(graphiques), texte: texte(root.querySelector('.card-title') ? root : root) .slice(0, 400) };
        await onglet(root, /Archivés/);
        r.archives = releve(root);
        await onglet(root, /Tous les budgets/);
        // un budget d'un autre exercice : le réalisé suit-il l'exercice du budget ? (le jeu n'en porte qu'un)
        // création
        const t0 = toasts.length, avant = instantane(COL);
        await cliquer(root, /^Nouveau$/);
        let dlg = dialogue();
        r.formulaire = { texte: texte(dlg), valeurs: ['exercice', 'centreCout', 'nature', 'prevu'].map((k) => { const e = dlg.querySelector('#f_' + k); return [k, e ? e.value : null]; }) };
        poser(dlg, 'exercice', '2026'); poser(dlg, 'centreCout', 'maternite'); poser(dlg, 'nature', 'Investissements'); poser(dlg, 'prevu', '1500000');
        r.boutonsFormulaire = [...dlg.querySelectorAll('button')].map(texte).filter(Boolean);
        await cliquer(dlg, /^Créer$/);
        r.creation = { toasts: vuToasts(t0), ecart: ecart(avant, instantane(COL)) };
        fermerDialogues();
        // sans montant : refus
        {
          const t1 = toasts.length, av = instantane(COL);
          await cliquer(root, /^Nouveau$/);
          const d2 = dialogue();
          poser(d2, 'centreCout', 'maternite'); poser(d2, 'prevu', '');
          await cliquer(d2, /^Créer$/);
          r.sansMontant = { toasts: vuToasts(t1), ecart: ecart(av, instantane(COL)), modaleOuverte: !!dialogue(), texte: texte(dialogue() || d2).slice(0, 300) };
          fermerDialogues();
        }
        root.remove();
        root = await monter('m12-budgets');
        const cree = db().budgets.find((b) => b.reference && b.nature === 'Investissements' && b.prevu === 1500000);
        r.creeRef = cree ? cree.reference : null;
        if (!r.creeRef) throw new Error('budget non créé : ' + JSON.stringify(r.creation) + ' / ' + JSON.stringify(r.sansMontant));
        const ligneDe = (ref) => [...root.querySelectorAll('table tbody tr')].find((x) => texte(x).indexOf(ref) >= 0);
        // la seconde création : la référence suit-elle la précédente ?
        {
          const av = instantane(COL);
          await cliquer(root, /^Nouveau$/);
          const d3 = dialogue();
          poser(d3, 'centreCout', 'consultation'); poser(d3, 'prevu', '800000');
          await cliquer(d3, /^Créer$/);
          r.deuxiemeCreation = { ecart: ecart(av, instantane(COL)) };
          fermerDialogues();
        }
        // modification
        {
          const t2 = toasts.length, av = instantane(COL);
          root.remove(); root = await monter('m12-budgets');
          const bm = [...ligneDe(r.creeRef).querySelectorAll('button')].find((b) => /Modifier/.test(b.getAttribute('title') || ''));
          bm.click(); await dormir(150);
          const d4 = dialogue();
          r.formulaireModifier = { valeurs: ['exercice', 'centreCout', 'nature', 'prevu'].map((k) => { const e = d4.querySelector('#f_' + k); return [k, e ? e.value : null]; }) };
          poser(d4, 'prevu', '2000000'); poser(d4, 'nature', 'Charges de personnel');
          await cliquer(d4, /^Enregistrer$/);
          r.modification = { toasts: vuToasts(t2), ecart: ecart(av, instantane(COL)) };
          fermerDialogues();
        }
        // tiroir
        root.remove(); root = await monter('m12-budgets');
        ligneDe(r.creeRef).click(); await dormir(200);
        r.tiroir = { texte: texte(dialogue()), boutons: [...dialogue().querySelectorAll('button')].map(texte).filter(Boolean) };
        fermerDialogues();
        // archivage
        {
          const t3 = toasts.length, av = instantane(COL);
          const ba = [...ligneDe(r.creeRef).querySelectorAll('button')].find((b) => /Archiver/.test(b.getAttribute('title') || ''));
          ba.click(); await dormir(150);
          const dc = dialogue(); r.archivageDialogue = texte(dc);
          await cliquer(dc, /^Archiver$/);
          r.archivage = { toasts: vuToasts(t3), ecart: ecart(av, instantane(COL)) };
          fermerDialogues();
        }
        R['m12-budgets'] = r; root.remove(); poserJeu();
      }

      /* ---------- m12-immobilisations -------------------------------------------------------------------------------------------------- */
      {
        const COL = ['immobilisations'];
        const r = {};
        let root = await monter('m12-immobilisations');
        Object.assign(r, releve(root));
        r.filtres = [...root.querySelectorAll('select[aria-label]')].map((s) => ({ label: s.getAttribute('aria-label'), options: [...s.options].map((o) => [o.value, texte(o)]) }));
        const f = {};
        for (const fl of r.filtres) {
          for (const [val] of fl.options) {
            if (val === '') continue;
            await filtrer(root, fl.label, val);
            f[fl.label + '|' + val] = [...root.querySelectorAll('table tbody tr')].length;
          }
          await filtrer(root, fl.label, '');
        }
        r.filtresNb = f;
        await onglet(root, /Report au bilan/);
        r.bilan = releve(root);
        { const pa = pieces.length; await cliquer(root, /Imprimer le report/); r.pieceReport = pieces.length > pa ? derniere() : null; }
        await onglet(root, /Archivés/);
        r.archives = releve(root);
        await onglet(root, /Tous les immobilisations/);
        // un bien par rubrique du bilan (comptes de classe 2), relus au rapport : le rattachement se fait par le COMPTE, jamais par la catégorie
        {
          const avantRub = propre(db().immobilisations);
          const comptes = ['211000', '213000', '215000', '217000', '221000', '231100', '235000', '241000', '245000', '261000', '271000', '229000'];
          comptes.forEach((cpt, i) => {
            db().immobilisations.unshift({ id: 'IMMX' + i, statut: 'actif', reference: 'IX-' + (i + 1), designation: 'Bien ' + cpt, categorie: 'Installations',
              valeurAcquisition: 1000000 * (i + 1), dureeAmortissement: 2, compte: cpt, dateAcquisition: '2026-01-10', etat: 'En service' });
          });
          const rt = await monter('m12-immobilisations');
          await onglet(rt, /Report au bilan/);
          r.bilanParCompte = { comptes, lignes: [...rt.querySelectorAll('table tbody tr')].map((tr) => [...tr.querySelectorAll('td')].map(texte)) };
          rt.remove();
          db().immobilisations.splice(0, db().immobilisations.length, ...avantRub);
        }
        // tiroir du premier bien + impression de la fiche
        root.querySelectorAll('table tbody tr')[0].click(); await dormir(250);
        {
          const d = dialogue();
          r.tiroir = { texte: texte(d), boutons: [...d.querySelectorAll('button')].map(texte).filter(Boolean),
            tables: [...d.querySelectorAll('table')].map((tb) => ({ entetes: [...tb.querySelectorAll('thead th')].map(texte), lignes: [...tb.querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('td')].map(texte)) })) };
          const pa = pieces.length;
          await cliquer(d, /^Imprimer$/);
          r.pieceFiche = pieces.length > pa ? derniere() : null;
          fermerDialogues();
        }
        // création d'un bien, puis cession
        const t0 = toasts.length, avant = instantane(COL);
        await cliquer(root, /^Nouveau$/);
        let dlg = dialogue();
        r.formulaire = { texte: texte(dlg), valeurs: ['designation', 'categorie', 'dateAcquisition', 'valeurAcquisition', 'dureeAmortissement', 'etat'].map((k) => { const e = dlg.querySelector('#f_' + k); return [k, e ? e.value : null]; }) };
        poser(dlg, 'designation', 'Réfrigérateur de laboratoire'); poser(dlg, 'categorie', 'Matériel de laboratoire');
        poser(dlg, 'dateAcquisition', '2025-03-15'); poser(dlg, 'valeurAcquisition', '1000000'); poser(dlg, 'dureeAmortissement', '4');
        await cliquer(dlg, /^Créer$/);
        r.creation = { toasts: vuToasts(t0), ecart: ecart(avant, instantane(COL)) };
        fermerDialogues();
        const cree = db().immobilisations.find((b) => b.designation === 'Réfrigérateur de laboratoire');
        r.creeRef = cree ? cree.reference : null;
        root.remove(); root = await monter('m12-immobilisations');
        const ligneDe = (ref) => [...root.querySelectorAll('table tbody tr')].find((x) => texte(x).indexOf(ref) >= 0);
        r.ligneCree = ligneDe(r.creeRef) ? [...ligneDe(r.creeRef).querySelectorAll('td')].map(texte) : null;
        // cession : l'amortissement s'ARRÊTE à la date de sortie, le bien quitte le bilan
        {
          const t1 = toasts.length, av = instantane(COL);
          const bm = [...ligneDe(r.creeRef).querySelectorAll('button')].find((b) => /Modifier/.test(b.getAttribute('title') || ''));
          bm.click(); await dormir(150);
          const d4 = dialogue();
          poser(d4, 'dateCession', '2025-12-20'); poser(d4, 'motifSortie', 'Cession'); poser(d4, 'valeurCession', '400000');
          await cliquer(d4, /^Enregistrer$/);
          r.cession = { toasts: vuToasts(t1), ecart: ecart(av, instantane(COL)) };
          fermerDialogues();
        }
        root.remove(); root = await monter('m12-immobilisations');
        r.ligneCedee = ligneDe(r.creeRef) ? [...ligneDe(r.creeRef).querySelectorAll('td')].map(texte) : null;
        r.kpisApresCession = releve(root).kpis;
        ligneDe(r.creeRef).click(); await dormir(250);
        r.tiroirCede = { texte: texte(dialogue()), tables: [...dialogue().querySelectorAll('table')].map((tb) => ({ lignes: [...tb.querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('td')].map(texte)) })) };
        fermerDialogues();
        await onglet(root, /Report au bilan/);
        r.bilanApresCession = releve(root);
        await onglet(root, /Tous les immobilisations/);
        // archivage
        {
          const t3 = toasts.length, av = instantane(COL);
          const ba = [...ligneDe(r.creeRef).querySelectorAll('button')].find((b) => /Archiver/.test(b.getAttribute('title') || ''));
          ba.click(); await dormir(150);
          const dc = dialogue(); r.archivageDialogue = texte(dc);
          await cliquer(dc, /^Archiver$/);
          r.archivage = { toasts: vuToasts(t3), ecart: ecart(av, instantane(COL)) };
          fermerDialogues();
        }
        R['m12-immobilisations'] = r; root.remove(); poserJeu();
      }

      /* ---------- m12-banques ----------------------------------------------------------------------------------------------------------- */
      {
        const COL = ['banques'];
        const r = {};
        let root = await monter('m12-banques');
        Object.assign(r, releve(root));
        r.filtres = [...root.querySelectorAll('select[aria-label]')].map((s) => ({ label: s.getAttribute('aria-label'), options: [...s.options].map((o) => [o.value, texte(o)]) }));
        const f = {};
        for (const fl of r.filtres) {
          for (const [val] of fl.options) {
            if (val === '') continue;
            await filtrer(root, fl.label, val);
            const tbs = [...root.querySelectorAll('table')];
            f[fl.label + '|' + val] = tbs.length > 1 ? tbs[1].querySelectorAll('tbody tr').length : 0;
          }
          await filtrer(root, fl.label, '');
        }
        r.filtresNb = f;
        // impression d'un rapprochement avec écart, d'un autre sans écart
        const rapRows = [...root.querySelectorAll('table')[1].querySelectorAll('tbody tr')];
        r.pieces = [];
        for (const sel of [(x) => /Rapproché/.test(texte(x)), (x) => !/Rapproché/.test(texte(x))]) {
          const tr = rapRows.find(sel);
          if (!tr) continue;
          const pa = pieces.length;
          const b = [...tr.querySelectorAll('button')].find((x) => /Imprimer/.test(x.getAttribute('title') || ''));
          b.click(); await dormir(120);
          r.pieces.push({ ligne: [...tr.querySelectorAll('td')].map(texte), piece: pieces.length > pa ? derniere() : null });
        }
        // création d'un compte bancaire
        const t0 = toasts.length, avant = instantane(COL);
        await cliquer(root, /^Nouveau$/);
        let dlg = dialogue();
        r.formulaire = { texte: texte(dlg), valeurs: ['banque', 'intitule', 'numeroCompte', 'compteComptable', 'devise', 'statutCompte'].map((k) => { const e = dlg.querySelector('#f_' + k); return [k, e ? e.value : null]; }), boutons: [...dlg.querySelectorAll('button')].map(texte).filter(Boolean) };
        poser(dlg, 'banque', 'Banque Atlantique Bénin'); poser(dlg, 'intitule', 'Compte courant BAB'); poser(dlg, 'numeroCompte', '010 20300 55');
        poser(dlg, 'compteComptable', '521300');
        const bc = [...dlg.querySelectorAll('button')].find((b) => /^(Créer|Enregistrer|Ajouter)$/.test(texte(b)));
        r.boutonCreer = bc ? texte(bc) : null;
        bc.click(); await dormir(200);
        r.creation = { toasts: vuToasts(t0), ecart: ecart(avant, instantane(COL)) };
        fermerDialogues();
        // champs obligatoires
        {
          const av = instantane(COL), t1 = toasts.length;
          await cliquer(root, /^Nouveau$/);
          const d2 = dialogue();
          const bc2 = [...d2.querySelectorAll('button')].find((b) => /^(Créer|Enregistrer|Ajouter)$/.test(texte(b)));
          bc2.click(); await dormir(150);
          r.sansChamps = { toasts: vuToasts(t1), ecart: ecart(av, instantane(COL)), modaleOuverte: !!dialogue(), texte: texte(dialogue() || d2).slice(0, 400) };
          fermerDialogues();
        }
        root.remove(); root = await monter('m12-banques');
        const cree = db().banques.find((b) => b.banque === 'Banque Atlantique Bénin');
        const t2 = toasts.length;
        r.creeId = cree ? cree.id : null;
        const ligneB = () => [...root.querySelectorAll('table')[0].querySelectorAll('tbody tr')].find((x) => texte(x).indexOf('Banque Atlantique') >= 0);
        r.ligneCreee = ligneB() ? { cellules: [...ligneB().querySelectorAll('td')].map(texte), boutons: [...ligneB().querySelectorAll('button')].map((b) => b.getAttribute('title')) } : null;
        // modification : clôturer le compte
        {
          const av = instantane(COL), t3 = toasts.length;
          const bm = [...ligneB().querySelectorAll('button')].find((b) => /Modifier/.test(b.getAttribute('title') || ''));
          bm.click(); await dormir(150);
          const d3 = dialogue();
          poser(d3, 'statutCompte', 'cloture');
          const bs = [...d3.querySelectorAll('button')].find((b) => /^(Enregistrer|Créer)$/.test(texte(b)));
          bs.click(); await dormir(150);
          r.modification = { toasts: vuToasts(t3), ecart: ecart(av, instantane(COL)) };
          fermerDialogues();
        }
        // archivage
        {
          const av = instantane(COL), t4 = toasts.length;
          root.remove(); root = await monter('m12-banques');
          const ba = [...ligneB().querySelectorAll('button')].find((b) => /Archiver/.test(b.getAttribute('title') || ''));
          ba.click(); await dormir(150);
          const dc = dialogue(); r.archivageDialogue = texte(dc);
          const bo = [...dc.querySelectorAll('button')].find((b) => /^Archiver$/.test(texte(b)));
          bo.click(); await dormir(200);
          r.archivage = { toasts: vuToasts(t4), ecart: ecart(av, instantane(COL)) };
          fermerDialogues();
        }
        R['m12-banques'] = r; root.remove(); poserJeu();
      }

      return { referentiels, donnees, ecrans: R, toastsTotal: toasts.length };
    }, jeu);
    ecrire('packages/domaine/test/vecteurs/comptabilite_b.json', Object.assign({}, sortie, { donnees: undefined }));
    const d = sortie.donnees;
    const entete = (what) => `// ENGENDRÉ par prototype_html/build/vecteurs-comptabilite-b.js — NE PAS ÉDITER. ${what}\nlibrary;\n\n`;
    fs.writeFileSync(path.join(ROOT, '..', 'packages/domaine/lib/src/comptabilite/cpb_liasse.dart'),
      entete('La liasse fiscale DÉPOSÉE à la DGI le 15/05/2026 (code BK505416) — `SIGH.liasse` de prototype_html/assets/js/data-liasse.js : structure du formulaire\n// (références, libellés, ordre, sous-totaux) ET valeurs déposées (exercice N = 2025, N-1 = 2024). Des faits : ils se citent, ils ne se recalculent pas.\n// Les écarts internes du document (`ECARTS`) sont CONSERVÉS, non arbitrés.')
      + '/// `SIGH.liasse` : DEPOT, BILAN_ACTIF, BILAN_PASSIF, RESULTAT, FLUX, DISPONIBILITES, SYNTHESE, NOTES_SYNTHESE, ECARTS.\n'
      + 'const Map<String, Object?> cpbLiasse = ' + litDart(d.liasse, 0) + ';\n');
    fs.writeFileSync(path.join(ROOT, '..', 'packages/domaine/lib/src/comptabilite/cpb_donnees.dart'),
      entete('`D.RUBRIQUES_RESULTAT` (la cascade des soldes de gestion) et `D.NATURE_CHARGE` (la répartition fixe / variable PROPOSÉE — un jugement de gestion,\n// non une donnée du plan comptable) de prototype_html/assets/js/data.js.')
      + 'const List<Map<String, Object?>> cpbRubriquesResultat = ' + litDart(d.rubriquesResultat, 0) + ';\n\n'
      + "/// Préfixe de compte → `fixe` ou `variable` (le préfixe le plus long l'emporte). `aValider` et `note` sont lus à part.\n"
      + 'const Map<String, Object?> cpbNatureChargeReferentiel = ' + litDart(d.natureCharge, 0) + ';\n');
    console.log('  écrit : cpb_liasse.dart, cpb_donnees.dart, comptabilite_b.json');
    if (m.erreurs.length) console.log('  avertissements : ' + m.erreurs.slice(0, 5).join(' | '));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
