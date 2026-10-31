/* =============================================================================
 * VECTEURS DE M12 (tranche « comptabilité de base ») — m12-dashboard, m12-plan-comptable, m12-journaux, m12-ecritures, m12-depenses,
 * m12-grand-livre, m12-balance — tirés des ÉCRANS RÉELS pilotés dans Chrome.
 * -----------------------------------------------------------------------------
 *   node build/vecteurs-comptabilite.js      (sous flock /tmp/sigh-banc.lock ; SIGH_PORT_PHP=<port inhabituel 98xx>)
 *
 * Le JEU du poste (apps/poste/assets/donnees/jeu) est posé dans le magasin de la maquette : c'est lui que les tests Flutter chargent. L'horloge de la
 * page est décalée au 30/10/2026 10 h (comme la parité N1). Les écrans sont MONTÉS, leurs indicateurs, tableaux, filtres, tiroirs, graphiques et pièces
 * imprimées sont LUS comme l'agent les lit ; les gestes d'écriture sont ACCOMPLIS par les boutons de l'écran et l'écart du magasin est enregistré.
 * Sorties (ENGENDRÉES) : packages/domaine/test/vecteurs/comptabilite.json et packages/domaine/lib/src/comptabilite/cpa_plan.dart
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');
const JEU_DIR = path.join(ROOT, '..', 'apps/poste/assets/donnees/jeu');
const NOMS = ['ecritures', 'comptes', 'banques', 'centresCouts', 'depenses', 'factures'];
const jeu = {};
NOMS.forEach((n) => { jeu[n] = JSON.parse(fs.readFileSync(path.join(JEU_DIR, n + '.json'), 'utf8')); });

(async () => {
  console.log('▶ Vecteurs de M12 (7 écrans)');
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
            entetes: [...tb.querySelectorAll('thead th')].map(texte),
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
          const rec = { type: k, etiquettes: propre(a[0]), series: k === 'anneau' ? propre(a[1]) : propre((a[1] || []).map((s) => ({ label: s.label, data: s.data }))) };
          graphiques.push(rec);
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
            entetes: [...tb.querySelectorAll('thead th')].map(texte).filter((s) => s !== ''),
            lignes: [...tb.querySelectorAll('tbody tr')].map((tr) => ({
              cellules: [...tr.querySelectorAll('td')].map(texte),
              boutons: [...tr.querySelectorAll('button')].map((b) => b.getAttribute('title') || b.getAttribute('aria-label') || texte(b)).filter(Boolean),
            })),
          };
        });
        const onglets = [...root.querySelectorAll('button.tab')].map(texte);
        const cartes = [...root.querySelectorAll('.card-title')].map(texte);
        const boutons = [...root.querySelectorAll('button')].map((b) => b.getAttribute('title') || b.getAttribute('aria-label') || texte(b)).filter(Boolean);
        const filtres = [...root.querySelectorAll('select[aria-label]')].map((s) => ({ label: s.getAttribute('aria-label'), options: [...s.options].map((o) => [o.value, texte(o)]) }));
        const notes = [...root.querySelectorAll('.rounded-lg.border')].map(texte).filter((t) => /RG-10|brouillon|justificatif|Écart|équilibr/i.test(t)).slice(0, 8);
        return { kpis, tables, onglets, cartes, boutons, filtres, notes };
      }
      async function monter(id) {
        const root = document.createElement('div'); document.body.appendChild(root);
        SIGH.screens[id].render(root); await dormir(150);
        return root;
      }
      const bouton = (portee, re) => [...portee.querySelectorAll('button')].find((b) => re.test(texte(b)) || re.test(b.getAttribute('title') || ''));
      async function cliquer(portee, re) { const b = bouton(portee, re); if (!b) throw new Error('bouton introuvable : ' + re); b.click(); await dormir(150); return b; }
      async function onglet(root, re) { const b = [...root.querySelectorAll('button.tab')].find((x) => re.test(texte(x))); if (!b) throw new Error('onglet introuvable ' + re); b.click(); await dormir(120); }
      function poser(portee, nom, valeur) {
        const e = portee.querySelector('#f_' + nom) || portee.querySelector('[name="' + nom + '"]');
        if (!e) throw new Error('champ introuvable : ' + nom);
        e.value = valeur; e.dispatchEvent(new Event('input', { bubbles: true })); e.dispatchEvent(new Event('change', { bubbles: true }));
      }
      async function filtrer(root, label, valeur) {
        const s = [...root.querySelectorAll('select[aria-label]')].find((x) => x.getAttribute('aria-label') === label);
        if (!s) throw new Error('filtre introuvable : ' + label);
        s.value = valeur; s.dispatchEvent(new Event('change', { bubbles: true })); await dormir(80);
      }
      const lignesDe = (root, i) => [...(root.querySelectorAll('table')[i || 0] || { querySelectorAll: () => [] }).querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('td')].map(texte));
      const fermerDialogues = () => { document.querySelectorAll('[role=dialog]').forEach((d) => d.remove()); };
      const dialogue = () => [...document.querySelectorAll('[role=dialog]')].pop();
      const instantane = (noms) => { const o = {}; noms.forEach((n) => { o[n] = propre(db()[n] || []); }); return o; };
      const IGN = new Set(['_creePar', '_creeLe', '_modifiePar', '_modifieLe', '_archivePar', '_archiveLe', 'id', 'ecritureId', 'ecritureIds', 'pieceId']);
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
      const COL = ['ecritures', 'comptes', 'depenses'];
      async function chercher(portee, valeur) {
        const i = portee.querySelector('input[type=search], input[placeholder^="Rechercher"]');
        if (!i) throw new Error('recherche introuvable');
        i.value = valeur; i.dispatchEvent(new Event('input', { bubbles: true })); await dormir(250);
      }
      /* Le combo du COMPTE de la ligne : le journal, passé à neuf entrées avec BQE, est devenu un combo à son tour (f_journal). */
      const combo = (portee, i) => [...portee.querySelectorAll('.combo')].filter((x) => x.id !== 'f_journal')[i || 0];
      const vuToasts = (depuis) => toasts.slice(depuis);

      const R = {}; // les écrans
      const cas = {};

      /* ---------- référentiels lus à la source ------------------------------------------------------------------------------------- */
      const referentiels = {
        journaux: propre(D.JOURNAUX), categoriesDepense: propre(D.CATEGORIES_DEPENSE), centres: propre(D.CENTRES_COUT),
        planComptable: propre(D.PLAN_COMPTABLE),
        exercices: propre(SIGH.exercice.liste().map((x) => ({ annee: x.annee, etat: x.etat, source: x.source, valideLe: x.valideLe || null }))),
        exerciceChoisi: SIGH.exercice.choisi(),
        provisoires2026: SIGH.exercice.provisoires(2026).length,
        depot: propre({ exerciceN: SIGH.liasse.DEPOT.exerciceN, exerciceN1: SIGH.liasse.DEPOT.exerciceN1, dateDepot: SIGH.liasse.DEPOT.dateDepot }),
      };

      /* ---------- 1. m12-dashboard -------------------------------------------------------------------------------------------------- */
      {
        graphiques.length = 0;
        const root = await monter('m12-dashboard');
        const r = releve(root);
        r.graphiques = propre(graphiques);
        r.classements = [...root.querySelectorAll('.space-y-2\\.5')].map((l) => [...l.children].map((x) => [...x.querySelectorAll('span')].slice(0, 2).map(texte)));
        r.alertes = [...root.querySelectorAll('.grid.gap-2')].map(texte);
        r.raccourcis = [...root.querySelectorAll('a, button')].map(texte).filter((t) => /Saisir une écriture|Grand livre|Balance|États financiers/.test(t));
        R['m12-dashboard'] = r; root.remove();
      }

      /* ---------- 2. m12-plan-comptable --------------------------------------------------------------------------------------------- */
      {
        const root = await monter('m12-plan-comptable');
        const r = releve(root);
        /* E724/E725 : les doublons du plan sont archivés au chargement (la fiche du document est conservée), avec leur motif (RG-14). */
        r.assainissement = db().comptes.filter((c) => c.statut === 'archive').map((c) => [c.num, c.libelle, c._motifArchivage || null]);
        r.numerosActifsUniques = (() => { const v = {}; db().comptes.filter((c) => c.statut !== 'archive').forEach((c) => { v[c.num] = (v[c.num] || 0) + 1; }); return Object.values(v).every((n) => n === 1); })();
        r.page1 = lignesDe(root);
        const f = {};
        for (const fl of r.filtres) {
          for (const [val] of fl.options) {
            if (val === '') continue;
            await filtrer(root, fl.label, val);
            f[fl.label + '|' + val] = { nb: lignesDe(root).length, premier: (lignesDe(root)[0] || [])[0] || null };
          }
          await filtrer(root, fl.label, '');
        }
        r.filtresResultats = f;
        await onglet(root, /Par classe/);
        r.parClasse = [...root.querySelectorAll('.card')].filter((c) => /^Classe/.test(texte(c.querySelector('.card-title') || c))).map((c) => ({ titre: texte(c.querySelector('.card-title')), lignes: [...c.querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('td')].map(texte)) }));
        await onglet(root, /Tous les comptes/);
        // tiroir
        root.querySelectorAll('table tbody tr')[0].click(); await dormir(200);
        const d = dialogue();
        r.tiroir = { texte: texte(d), boutons: [...d.querySelectorAll('button')].map(texte).filter(Boolean) };
        fermerDialogues();
        // impression
        const pa = pieces.length; SIGH.screens['m12-plan-comptable'].actions()[0].click(); await dormir(100);
        r.piece = pieces.length > pa ? derniere() : null;
        // créations
        const essais = {};
        async function tenter(nom, valeurs) {
          const t0 = toasts.length, avant = instantane(COL);
          await cliquer(root, /^Nouveau$/);
          const dlg = dialogue();
          if (!essais.__formulaire) essais.__formulaire = [...dlg.querySelectorAll('label')].map(texte);
          Object.keys(valeurs).forEach((k) => poser(dlg, k, valeurs[k]));
          await cliquer(dlg, /^Créer$/);
          const rep = { toasts: vuToasts(t0), ecart: ecart(avant, instantane(COL)), modaleOuverte: !!dialogue() };
          fermerDialogues(); essais[nom] = rep;
        }
        await tenter('numeroCourt', { num: '12345', libelle: 'Compte test', classe: '6', journal: 'OD' });
        await tenter('numeroLettres', { num: '60A900', libelle: 'Compte test', classe: '6', journal: 'OD' });
        await tenter('doublon', { num: '601100', libelle: 'Compte test', classe: '6', journal: 'OD' });
        await tenter('valide', { num: '605900', libelle: 'Petit outillage — essai', classe: '6', journal: 'ACH' });
        r.creations = essais;
        // modification du compte créé, puis archivage
        const cree = db().comptes.find((c) => c.num === '605900');
        {
          const t0 = toasts.length, avant = instantane(COL);
          const tr = [...root.querySelectorAll('table tbody tr')].find((x) => /605900/.test(texte(x)));
          // le tableau n'a pas été rafraîchi par la saisie hors écran : on remonte l'écran
          root.remove();
          const root2 = await monter('m12-plan-comptable');
          await chercher(root2, '605900');
          const ligne = [...root2.querySelectorAll('table tbody tr')].find((x) => /605900/.test(texte(x)));
          if (!ligne) { r.edition = { erreur: 'ligne 605900 introuvable', premiers: lignesDe(root2).slice(0, 3) }; } else {
            const bm = [...ligne.querySelectorAll('button')].find((b) => /Modifier/.test(b.getAttribute('title') || ''));
            bm.click(); await dormir(150);
            const dlg = dialogue();
            poser(dlg, 'libelle', 'Petit outillage — essai corrigé');
            poser(dlg, 'num', '605901');
            await cliquer(dlg, /^Enregistrer$/);
            r.edition = { toasts: vuToasts(t0), ecart: ecart(avant, instantane(COL)) };
            fermerDialogues();
            const t1 = toasts.length, avant2 = instantane(COL);
            await chercher(root2, '605901');
            const l2 = [...root2.querySelectorAll('table tbody tr')].find((x) => /605901/.test(texte(x)));
            const ba = [...l2.querySelectorAll('button')].find((b) => /Archiver/.test(b.getAttribute('title') || ''));
            ba.click(); await dormir(150);
            const dc = dialogue(); r.archivageDialogue = texte(dc);
            await cliquer(dc, /^Archiver$/);
            r.archivage = { toasts: vuToasts(t1), ecart: ecart(avant2, instantane(COL)) };
            fermerDialogues();
          }
          // modifier un compte ISSU DU DOCUMENT : que devient sa provenance ?
          {
            await chercher(root2, '601100');
            const t2 = toasts.length, avant3 = instantane(COL);
            const l3 = [...root2.querySelectorAll('table tbody tr')].find((x) => /601100/.test(texte(x)));
            const bm2 = [...l3.querySelectorAll('button')].find((b) => /Modifier/.test(b.getAttribute('title') || ''));
            bm2.click(); await dormir(150);
            const dl = dialogue();
            r.formulaireEdition = { labels: [...dl.querySelectorAll('label')].map(texte), valeurs: ['num', 'libelle', 'classe', 'journal'].map((k) => { const e = dl.querySelector('#f_' + k); return e ? e.value : null; }) };
            poser(dl, 'libelle', 'Achats de marchandises (corrigé)');
            await cliquer(dl, /^Enregistrer$/);
            r.editionDocument = { toasts: vuToasts(t2), ecart: ecart(avant3, instantane(COL)) };
            fermerDialogues();
          }
          /* E724 : l'unicité vaut aussi à la MODIFICATION (numéro déjà pris) et vis-à-vis d'un compte ARCHIVÉ. */
          {
            await chercher(root2, '601100');
            const t3 = toasts.length, avant4 = instantane(COL);
            const l4 = [...root2.querySelectorAll('table tbody tr')].find((x) => /601100/.test(texte(x)));
            const bm3 = [...l4.querySelectorAll('button')].find((b) => /Modifier/.test(b.getAttribute('title') || ''));
            bm3.click(); await dormir(150);
            const dl3 = dialogue();
            poser(dl3, 'num', '604100');
            await cliquer(dl3, /^Enregistrer$/);
            r.editionNumeroPris = { toasts: vuToasts(t3), ecart: ecart(avant4, instantane(COL)), modaleOuverte: !!dialogue() };
            fermerDialogues();
            const t4 = toasts.length, avant5 = instantane(COL);
            await cliquer(root2, /^Nouveau$/);
            const dl4 = dialogue();
            poser(dl4, 'num', '605901'); poser(dl4, 'libelle', 'Compte test archivé'); poser(dl4, 'classe', '6'); poser(dl4, 'journal', 'OD');
            await cliquer(dl4, /^Créer$/);
            r.creationNumeroArchive = { toasts: vuToasts(t4), ecart: ecart(avant5, instantane(COL)), modaleOuverte: !!dialogue() };
            fermerDialogues();
          }
          root2.remove();
        }
        R['m12-plan-comptable'] = r; root.remove(); fermerDialogues(); poserJeu();
      }

      /* ---------- 3. m12-journaux --------------------------------------------------------------------------------------------------- */
      {
        const root = await monter('m12-journaux');
        const r = releve(root);
        r.lignes = lignesDe(root);
        const tr = root.querySelectorAll('table tbody tr')[2]; tr.click(); await dormir(200); // CAI
        const d = dialogue();
        r.tiroir = { texte: texte(d), kpis: [...d.querySelectorAll('.kpi')].map((k) => [texte(k.querySelector('.kpi-label')), texte(k.querySelector('.kpi-value'))]),
          lignes: [...d.querySelectorAll('tbody tr')].map((x) => [...x.querySelectorAll('td')].map(texte)), boutons: [...d.querySelectorAll('button')].map(texte).filter(Boolean) };
        const pa = pieces.length; await cliquer(d, /Imprimer le journal/);
        r.piece = pieces.length > pa ? derniere() : null;
        fermerDialogues();
        R['m12-journaux'] = r; root.remove();
      }

      /* ---------- 4. m12-ecritures -------------------------------------------------------------------------------------------------- */
      {
        const root = await monter('m12-ecritures');
        const r = releve(root);
        r.page1 = lignesDe(root).slice(0, 5);
        const f = {};
        for (const fl of r.filtres) {
          for (const [val] of fl.options) {
            if (val === '') continue;
            await filtrer(root, fl.label, val);
            f[fl.label + '|' + val] = { nb: lignesDe(root).length, premier: (lignesDe(root)[0] || [])[0] || null };
          }
          await filtrer(root, fl.label, '');
        }
        r.filtresResultats = f;
        root.querySelectorAll('table tbody tr')[0].click(); await dormir(200);
        const d = dialogue();
        r.tiroir = { texte: texte(d), boutons: [...d.querySelectorAll('button')].map(texte).filter(Boolean) };
        fermerDialogues();

        // la saisie
        await cliquer(root, /Nouvelle écriture/);
        const dlg0 = dialogue();
        r.formulaire = { labels: [...dlg0.querySelectorAll('label')].map(texte), boutons: [...dlg0.querySelectorAll('button')].map(texte).filter(Boolean), texte: texte(dlg0) };
        fermerDialogues();

        async function saisir(nom, { date, journal, libelle, lignes, action, centre }) {
          const t0 = toasts.length, avant = instantane(COL);
          await cliquer(root, /Nouvelle écriture/);
          const dlg = dialogue();
          if (date) poser(dlg, 'date', date);
          poser(dlg, 'journal', journal); poser(dlg, 'libelle', libelle);
          if (centre) poser(dlg, 'centreCout', centre);
          poser(dlg, 'piece', 'PJ-' + nom);
          for (const l of lignes) {
            combo(dlg).value = l.compte;
            const nombres = [...dlg.querySelectorAll('input[type=number]')];
            nombres[0].value = l.debit || 0; nombres[1].value = l.credit || 0;
            await cliquer(dlg, /Ajouter la ligne/);
          }
          r['_note_' + nom] = texte(dlg).match(/RG-10[^.]*\./) ? texte(dlg).match(/RG-10[^.]*\./)[0] : null;
          await cliquer(dlg, action);
          const rep = { toasts: vuToasts(t0), ecart: ecart(avant, instantane(COL)), modaleOuverte: !!dialogue() };
          fermerDialogues(); cas[nom] = rep;
        }
        await saisir('ligneZero', { journal: 'OD', libelle: 'Essai zéro', lignes: [{ compte: '601100', debit: 0, credit: 0 }], action: /Enregistrer en brouillon/ });
        await saisir('ligneDouble', { journal: 'OD', libelle: 'Essai sans ligne', lignes: [], action: /Enregistrer en brouillon/ });
        await saisir('validerDesequilibree', { journal: 'OD', libelle: 'Écriture déséquilibrée', lignes: [{ compte: '601100', debit: 5000 }, { compte: '571000', credit: 4000 }], action: /Valider l’écriture/ });
        await saisir('brouillonDesequilibre', { journal: 'OD', libelle: 'Brouillon déséquilibré', lignes: [{ compte: '601100', debit: 5000 }, { compte: '571000', credit: 4000 }], action: /Enregistrer en brouillon/ });
        await saisir('validerEquilibree', { journal: 'CAI', libelle: 'Achat de petit matériel', centre: 'pharmacie', lignes: [{ compte: '605600', debit: 7500 }, { compte: '571000', credit: 7500 }], action: /Valider l’écriture/ });
        await saisir('brouillonEquilibre', { journal: 'BQ', libelle: 'Frais de tenue de compte', centre: 'direction', lignes: [{ compte: '631810', debit: 2500 }, { compte: '521000', credit: 2500 }], action: /Enregistrer en brouillon/ });
        await saisir('exerciceClos', { date: '2025-12-20', journal: 'OD', libelle: 'Écriture sur exercice clos', lignes: [{ compte: '601100', debit: 1000 }, { compte: '571000', credit: 1000 }], action: /Valider l’écriture/ });
        // le brouillon déséquilibré : Valider (ligne) refusé ; le brouillon équilibré : Valider la pièce
        {
          const root2 = await monter('m12-ecritures');
          const numDes = (db().ecritures.find((e) => e.libelle === 'Brouillon déséquilibré') || {}).numero;
          const numEq = (db().ecritures.find((e) => e.libelle === 'Frais de tenue de compte') || {}).numero;
          cas.numeros = { desequilibre: numDes, equilibre: numEq, attendusProchain: db().ecritures.filter((e) => /^OD-2026-/.test(e.numero)).map((e) => e.numero).sort().pop() };
          async function validerLigne(nom, numero) {
            const t0 = toasts.length, avant = instantane(COL);
            await filtrer(root2, 'Statut', 'brouillon');
            const lignes = [...root2.querySelectorAll('table tbody tr')].filter((x) => texte(x).indexOf(numero) >= 0);
            const bv = [...lignes[0].querySelectorAll('button')].find((b) => /Valider/.test(b.getAttribute('title') || ''));
            bv.click(); await dormir(150);
            cas[nom] = { nbLignes: lignes.length, toasts: vuToasts(t0), ecart: ecart(avant, instantane(COL)) };
          }
          await validerLigne('validerLigneDesequilibree', numDes);
          await validerLigne('validerPieceEquilibree', numEq);
          // archivage d'une ligne
          const t0 = toasts.length, avant = instantane(COL);
          await filtrer(root2, 'Statut', 'brouillon');
          const l = root2.querySelectorAll('table tbody tr')[0];
          const ba = [...l.querySelectorAll('button')].find((b) => /Archiver/.test(b.getAttribute('title') || ''));
          ba.click(); await dormir(150);
          cas.archivage = { toasts: vuToasts(t0), ecart: ecart(avant, instantane(COL)) };
          root2.remove();
        }
        R['m12-ecritures'] = r; cas.ecritures = r.kpis; root.remove(); fermerDialogues(); poserJeu();
      }

      /* ---------- 5. m12-grand-livre ------------------------------------------------------------------------------------------------ */
      {
        const root = await monter('m12-grand-livre');
        const r = releve(root);
        r.comptes = {};
        const cb = combo(root);
        const mouv = [...new Set(db().ecritures.map((e) => e.compte))].sort();
        r.comptesMouvementes = mouv;
        for (const num of mouv) {
          cb.value = num; cb.dispatchEvent(new Event('change', { bubbles: true })); await dormir(80);
          r.comptes[num] = { titre: texte(root.querySelector('.card-title')), kpis: [...root.querySelectorAll('.kpi')].map((k) => [texte(k.querySelector('.kpi-label')), texte(k.querySelector('.kpi-value')), (k.querySelector('p.mt-1.text-xs.text-slate-400') ? texte(k.querySelector('p.mt-1.text-xs.text-slate-400')) : null)]),
            premieres: lignesDe(root, 0).slice(0, 4), nb: lignesDe(root, 0).length };
        }
        cb.value = '571000'; cb.dispatchEvent(new Event('change', { bubbles: true })); await dormir(80);
        const pa = pieces.length; await cliquer(root, /Imprimer le grand livre/);
        r.piece = pieces.length > pa ? derniere() : null;
        const pb = pieces.length; await cliquer(root, /Grand livre complet/);
        r.pieceComplete = pieces.length > pb ? derniere() : null;
        R['m12-grand-livre'] = r; root.remove();
      }

      /* ---------- 6. m12-balance ---------------------------------------------------------------------------------------------------- */
      {
        const root = await monter('m12-balance');
        const r = releve(root);
        r.page1 = lignesDe(root);
        r.parClasse = {};
        const fClasse = r.filtres.find((x) => x.label === 'Classe') || { options: [], label: 'Classe' };
        for (const [val] of fClasse.options) {
          if (val === '') continue;
          await filtrer(root, fClasse.label, val);
          r.parClasse[val] = lignesDe(root);
        }
        await filtrer(root, fClasse.label, '');
        const pa = pieces.length; await cliquer(root, /Imprimer la balance$/);
        r.piece = pieces.length > pa ? derniere() : null;
        /* E718 : le filtre explicite « validées / toutes » (défaut : validées), et le bandeau qui dit ce qui est compté. */
        {
          const sel = () => root.querySelector('#balance-ecritures');
          r.modeDefaut = sel().value;
          r.modes = {};
          for (const mode of ['toutes', 'validees']) {
            sel().value = mode; sel().dispatchEvent(new Event('change', { bubbles: true })); await dormir(250);
            const rel = releve(root);
            const pm = pieces.length; await cliquer(root, /Imprimer la balance$/);
            r.modes[mode] = { kpis: rel.kpis, notes: rel.notes, lignes: lignesDe(root), piece: pieces.length > pm ? derniere() : null, valeur: sel().value };
          }
          const brouillons = db().ecritures.filter((e) => e.statut === 'brouillon' && e.date.slice(0, 4) === String(SIGH.exercice.choisi())).length;
          r.brouillonsExercice = brouillons;
        }
        await onglet(root, /Balance âgée/);
        r.agee = { lignes: lignesDe(root) };
        const pb = pieces.length; await cliquer(root, /Imprimer la balance âgée/);
        r.pieceAgee = pieces.length > pb ? derniere() : null;
        R['m12-balance'] = r; root.remove();
      }

      /* ---------- 7. m12-depenses --------------------------------------------------------------------------------------------------- */
      {
        graphiques.length = 0;
        const root = await monter('m12-depenses');
        const r = releve(root);
        r.graphiques = propre(graphiques);
        r.page1 = lignesDe(root, 0).slice(0, 4);
        r.cumul = lignesDe(root, 1);
        const f = {};
        for (const fl of r.filtres) {
          for (const [val] of fl.options) {
            if (val === '') continue;
            await filtrer(root, fl.label, val);
            f[fl.label + '|' + val] = { premier: (lignesDe(root, 0)[0] || [])[0] || null, kpis: [...root.querySelectorAll('.kpi')].map((k) => texte(k.querySelector('.kpi-value'))) };
          }
          await filtrer(root, fl.label, '');
        }
        r.filtresResultats = f;
        // plage de dates
        const [dDu, dAu] = root.querySelectorAll('input[type=date]');
        dDu.value = '2026-10-01'; dDu.dispatchEvent(new Event('change', { bubbles: true })); await dormir(100);
        dAu.value = '2026-10-30'; dAu.dispatchEvent(new Event('change', { bubbles: true })); await dormir(100);
        r.plageOctobre = { kpis: [...root.querySelectorAll('.kpi')].map((k) => [texte(k.querySelector('.kpi-label')), texte(k.querySelector('.kpi-value')), (k.querySelector('p.mt-1.text-xs.text-slate-400') ? texte(k.querySelector('p.mt-1.text-xs.text-slate-400')) : null)]), lignes: lignesDe(root, 0) };
        await cliquer(root, /Tout l’historique/);
        // tiroir
        root.querySelectorAll('table tbody tr')[0].click(); await dormir(200);
        const d = dialogue();
        r.tiroir = { texte: texte(d), boutons: [...d.querySelectorAll('button')].map(texte).filter(Boolean), tables: [...d.querySelectorAll('table')].map((tb) => [...tb.querySelectorAll('tr')].map((tr) => [...tr.querySelectorAll('th,td')].map(texte))) };
        const pa = pieces.length; await cliquer(d, /Imprimer la pièce/);
        r.pieceDepense = pieces.length > pa ? derniere() : null;
        fermerDialogues();
        const pb = pieces.length; await cliquer(root, /État des dépenses/);
        r.pieceEtat = pieces.length > pb ? derniere() : null;

        // saisie : trois lignes, multi-lignes
        async function ajouterLigne(dlg, libelle, compte, montant) {
          await cliquer(dlg, /Ajouter une ligne/);
          const dl = dialogue();
          poser(dl, 'libelle', libelle);
          combo(dl).value = compte;
          poser(dl, 'montant', String(montant));
          await cliquer(dl, /^Ajouter$/);
        }
        async function ouvrirNouvelle() { await cliquer(root, /Nouvelle dépense/); return dialogue(); }
        const nouvelles = {};
        {
          const t0 = toasts.length, avant = instantane(COL);
          const dlg = await ouvrirNouvelle();
          r.formulaire = { labels: [...dlg.querySelectorAll('label')].map(texte), texte: texte(dlg) };
          poser(dlg, 'date', '2026-10-30'); poser(dlg, 'compteTresorerie', 'BQ00'); poser(dlg, 'categorie', 'medical');
          await cliquer(dlg, /^Enregistrer$/);
          nouvelles.sansLigne = { toasts: vuToasts(t0), ecart: ecart(avant, instantane(COL)), modaleOuverte: !!dialogue() };
          // trois lignes
          await ajouterLigne(dlg, 'Gants d’examen', '601100', 12000);
          await ajouterLigne(dlg, 'Compresses', '604100', 8000);
          await ajouterLigne(dlg, 'Sparadrap', '605600', 4500);
          r.apresTroisLignes = texte(dlg);
          const t1 = toasts.length, avant1 = instantane(COL);
          await cliquer(dlg, /^Enregistrer$/);
          nouvelles.troisLignes = { toasts: vuToasts(t1), ecart: ecart(avant1, instantane(COL)), modaleOuverte: !!dialogue() };
          fermerDialogues();
        }
        {
          // une ligne, banque, objet fourni, exercice clos refusé
          const t0 = toasts.length, avant = instantane(COL);
          const dlg = await ouvrirNouvelle();
          poser(dlg, 'date', '2025-11-12'); poser(dlg, 'compteTresorerie', 'BQ01'); poser(dlg, 'categorie', 'fiscal');
          await ajouterLigne(dlg, 'Frais bancaires BOA', '631810', 9000);
          await cliquer(dlg, /^Enregistrer$/);
          nouvelles.exerciceClos = { toasts: vuToasts(t0), ecart: ecart(avant, instantane(COL)), modaleOuverte: !!dialogue() };
          fermerDialogues();
        }
        {
          const t0 = toasts.length, avant = instantane(COL);
          const dlg = await ouvrirNouvelle();
          poser(dlg, 'date', '2026-10-29'); poser(dlg, 'compteTresorerie', 'BQ01'); poser(dlg, 'categorie', 'fiscal'); poser(dlg, 'libelle', 'Droits de timbre — essai');
          await ajouterLigne(dlg, 'Timbres fiscaux', '646210', 3000);
          await cliquer(dlg, /^Enregistrer$/);
          nouvelles.uneLigneBanque = { toasts: vuToasts(t0), ecart: ecart(avant, instantane(COL)) };
          fermerDialogues();
        }
        r.nouvelles = nouvelles;
        // modification de la dépense à trois lignes : retirer une ligne, changer le compte de trésorerie
        const creeeId = (db().depenses.find((x) => x.lignes && x.lignes.length === 3 && x.libelle.indexOf('Gants') === 0) || {}).id;
        {
          root.remove();
          const root2 = await monter('m12-depenses');
          const ref = (db().depenses.find((x) => x.id === creeeId) || {}).reference;
          const ligne = [...root2.querySelectorAll('table tbody tr')].find((x) => texte(x).indexOf(ref) >= 0);
          const t0 = toasts.length, avant = instantane(COL);
          const bm = [...ligne.querySelectorAll('button')].find((b) => /Modifier/.test(b.getAttribute('title') || ''));
          bm.click(); await dormir(150);
          const dlg = dialogue();
          r.formulaireModifier = { texte: texte(dlg) };
          const retirer = [...dlg.querySelectorAll('button')].filter((b) => /Retirer la ligne/.test(b.getAttribute('title') || ''));
          retirer[2].click(); await dormir(100);
          poser(dlg, 'compteTresorerie', 'BQ00');
          await cliquer(dlg, /^Enregistrer$/);
          r.modification = { reference: ref, toasts: vuToasts(t0), ecart: ecart(avant, instantane(COL)) };
          fermerDialogues();
          // archivage
          const t1 = toasts.length, avant1 = instantane(COL);
          const l2 = [...root2.querySelectorAll('table tbody tr')].find((x) => texte(x).indexOf(ref) >= 0);
          const ba = [...l2.querySelectorAll('button')].find((b) => /Archiver/.test(b.getAttribute('title') || ''));
          ba.click(); await dormir(150);
          const dc = dialogue(); r.archivageDialogue = texte(dc);
          await cliquer(dc, /^Archiver$/);
          r.archivage = { toasts: vuToasts(t1), ecart: ecart(avant1, instantane(COL)) };
          fermerDialogues();
          root2.remove();
        }
        R['m12-depenses'] = r; fermerDialogues(); poserJeu();
      }

      return { referentiels, ecrans: R, cas, toastsTotal: toasts.length };
    }, jeu);
    ecrire('packages/domaine/test/vecteurs/comptabilite.json', sortie);
    // la table statique du plan comptable (D.PLAN_COMPTABLE) est ENGENDRÉE pour le domaine
    const plan = sortie.referentiels.planComptable;
    const q = (s) => "'" + String(s).replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$') + "'";
    const dart = "// ENGENDRÉ par prototype_html/build/vecteurs-comptabilite.js — ne pas éditer. `D.PLAN_COMPTABLE` de la maquette : ce que `compteLibelle` et\n"
      + "// `comptesCharge` (m12-comptabilite.js) lisent. Le plan est STATIQUE : un compte créé à l'écran n'y figure pas (écart E715).\n"
      + "library;\n\n"
      + "/// (numéro, intitulé, classe, journal usuel, provenance `DOC` ou `CDCT`).\n"
      + "const List<(String, String, int, String, String)> cpaPlanComptable = [\n"
      + plan.map((c) => `  (${q(c.num)}, ${q(c.libelle)}, ${c.classe}, ${q(c.journal)}, ${q(c.source)}),`).join('\n') + '\n];\n';
    const f = path.join(ROOT, '..', 'packages/domaine/lib/src/comptabilite/cpa_plan.dart');
    fs.mkdirSync(path.dirname(f), { recursive: true });
    fs.writeFileSync(f, dart);
    console.log('  écrit : packages/domaine/lib/src/comptabilite/cpa_plan.dart (' + plan.length + ' comptes)');
    if (m.erreurs.length) console.log('  avertissements : ' + m.erreurs.slice(0, 5).join(' | '));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
