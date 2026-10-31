/* =============================================================================
 * VECTEURS DE M12 — ÉCHÉANCES FISCALES & PAIEMENTS et BASELINE 2025 (m12-echeances, m12-baseline-2025), tirés des ÉCRANS RÉELS pilotés dans Chrome.
 * -----------------------------------------------------------------------------
 *   node build/vecteurs-m12-echeances.js      (sous flock /tmp/sigh-banc.lock ; SIGH_PORT_PHP=<port inhabituel 101xx>)
 *
 * Le JEU du poste est posé dans le magasin de la maquette, l'horloge est décalée au 30/10/2026 10 h (`_m12-outils.js`).
 * Sortie (ENGENDRÉE) : packages/domaine/test/vecteurs/echeances.json
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');
const JEU_DIR = path.join(ROOT, '..', 'apps/poste/assets/donnees/jeu');
const NOMS = ['echeancesFiscales', 'factures', 'audit', 'notifications'];
const jeu = {};
NOMS.forEach((n) => { jeu[n] = JSON.parse(fs.readFileSync(path.join(JEU_DIR, n + '.json'), 'utf8')); });

(async () => {
  console.log('▶ Vecteurs de M12 — échéances et baseline 2025');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(__dirname, '_m12-outils.js') });
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m12-comptabilite.js') });
    const sortie = await m.page.evaluate(async (jeu) => {
      const S = SIGH.store, C = SIGH.core, D = SIGH.data;
      const O = window.__O;
      const { propre, texte, dormir, db } = O;
      const poserJeu = () => { Object.keys(jeu).forEach((n) => { db()[n] = propre(jeu[n]); }); };
      poserJeu();
      const rep = {};

      /* ---------- les échéances ---------------------------------------------------------------------------------------------------- */
      const E = {};
      {
        const a0 = O.alertes.length;
        const root = await O.monter('m12-echeances');
        await dormir(1100);                                    // l'alerte sonore part 800 ms après l'ouverture
        const r = O.releve(root);
        E.alertesOuverture = O.alertes.slice(a0);
        E.ouverture = { kpis: r.kpis, notes: r.notes, titreTable: r.tables[0].titre, entetes: r.tables[0].entetes, boutons: r.boutons.slice(0, 12) };
        const tout = [];
        // toutes les pages du tableau (20 par page)
        let page = 1;
        O.lignesDe(root, 0).forEach((l) => tout.push(l));
        for (let p = 2; p <= 4; p++) {
          const bp = [...root.querySelectorAll('.flex.items-center.gap-1 button')].find((x) => texte(x) === String(p));
          if (!bp) break;
          bp.click(); await dormir(150); page = p;
          O.lignesDe(root, 0).forEach((l) => tout.push(l));
        }
        E.nbPages = page;
        E.lignes = tout;
        E.filtres = [...root.querySelectorAll('select[aria-label]')].map((s) => ({ label: s.getAttribute('aria-label'), options: [...s.options].map((o) => [o.value, texte(o)]) }));
        E.parFiltre = {};
        for (const [label, val] of [['État', 'en_retard'], ['État', 'a_payer'], ['État', 'declaration'], ['État', 'payee'], ['État', 'a_venir'], ['Périodicité', 'annuelle'], ['Obligation', 'ITS']]) {
          await O.filtrer(root, label, val);
          E.parFiltre[label + '|' + val] = O.lignesDe(root, 0).length;
          await O.filtrer(root, label, '');
        }
        await O.chercher(root, 'CNSS');
        E.rechercheCNSS = O.lignesDe(root, 0).length;
        root.remove();
      }
      // le tiroir d'une échéance (non payée) et d'une échéance payée
      {
        const root = await O.monter('m12-echeances');
        await O.filtrer(root, 'État', 'en_retard');
        const tr = root.querySelector('tbody tr');
        tr.click(); await dormir(250);
        const d = O.dialogue();
        E.tiroirDue = { texte: texte(d), boutons: [...d.querySelectorAll('button')].map(texte).filter(Boolean) };
        O.fermerDialogues();
        await O.filtrer(root, 'État', 'payee');
        const trp = root.querySelector('tbody tr');
        trp.click(); await dormir(250);
        const d2 = O.dialogue();
        E.tiroirPayee = { texte: texte(d2), boutons: [...d2.querySelectorAll('button')].map(texte).filter(Boolean) };
        O.fermerDialogues();
        // quittance
        const pa = O.pieces.length;
        const bq = [...trp.querySelectorAll('button')].find((b) => b.getAttribute('title') === 'Éditer la quittance');
        bq.click(); await dormir(150);
        E.quittance = O.pieces[O.pieces.length - 1];
        E.quittanceImprimee = O.pieces.length > pa;
        root.remove();
      }
      // valider un paiement : formulaire, refus, écriture ; puis annuler
      {
        const root = await O.monter('m12-echeances');
        const avant = db().echeancesFiscales.filter((e) => !e.paye).sort((a, b) => String(a.echeance).localeCompare(b.echeance))[0];
        await O.chercher(root, avant.libelle.slice(0, 20));
        const tr = [...root.querySelectorAll('tbody tr')].find((x) => texte(x).includes(C.dateFR(avant.echeance)) && !/Payée/.test(texte(x)));
        if (!tr) throw new Error('DEBUG ' + JSON.stringify({ avant, lignes: O.lignesDe(root, 0).slice(0, 3) }));
        const b = [...tr.querySelectorAll('button')].find((x) => x.getAttribute('title') === 'Valider le paiement effectué');
        b.click(); await dormir(250);
        const d = O.dialogue();
        E.modaleValider = { texte: texte(d), boutons: [...d.querySelectorAll('button')].map(texte).filter(Boolean),
          champs: [...d.querySelectorAll('input, select, textarea')].map((e) => ({ id: e.id, type: e.type || e.tagName, valeur: e.value, requis: e.required })) };
        const t0 = O.toasts.length, a0 = O.instantane(['echeancesFiscales', 'audit']);
        // sans saisie : le formulaire refuse (champs requis)
        await O.cliquer(d, /Confirmer le paiement/);
        E.sansSaisie = { toasts: O.toasts.slice(t0).map((t) => t.message), ecart: O.ecart(a0, O.instantane(['echeancesFiscales'])) };
        O.poser(d, 'montant', '125000'); O.poser(d, 'moyen', 'Virement bancaire'); O.poser(d, 'reference', 'QUIT-TEST-0001');
        await O.cliquer(d, /Confirmer le paiement/);
        E.apres = { cle: avant.id, ecart: O.ecart(a0, O.instantane(['echeancesFiscales', 'audit'])), toasts: O.toasts.slice(t0).map((t) => ({ message: t.message, type: t.type, detail: t.detail })) };
        root.remove();
      }
      // annuler la validation (motif obligatoire)
      {
        const cible = db().echeancesFiscales.find((e) => e.paye && e.reference === 'QUIT-TEST-0001');
        const root = await O.monter('m12-echeances');
        await O.chercher(root, cible.libelle.slice(0, 20));
        const tr = [...root.querySelectorAll('tbody tr')].find((x) => texte(x).includes('QUIT-TEST-0001'));
        const b = [...tr.querySelectorAll('button')].find((x) => x.getAttribute('title') === 'Annuler la validation');
        b.click(); await dormir(250);
        const d = O.dialogue();
        E.modaleAnnuler = { texte: texte(d), boutons: [...d.querySelectorAll('button')].map(texte).filter(Boolean) };
        const a0 = O.instantane(['echeancesFiscales']);
        const ta = d.querySelector('textarea'); ta.value = 'Paiement saisi sur la mauvaise échéance'; ta.dispatchEvent(new Event('input', { bubbles: true }));
        await O.cliquer(d, /Annuler la validation/);
        E.annulation = { ecart: O.ecart(a0, O.instantane(['echeancesFiscales'])) };
        root.remove();
        // rappel
        const root2 = await O.monter('m12-echeances');
        await O.filtrer(root2, 'État', 'en_retard');
        const tr2 = root2.querySelector('tbody tr');
        const al0 = O.alertes.length;
        [...tr2.querySelectorAll('button')].find((x) => x.getAttribute('title') === 'Rappeler cette échéance').click(); await dormir(120);
        E.rappel = O.alertes.slice(al0);
        E.rappelLigne = texte(tr2);
        root2.remove();
        poserJeu();
      }
      // barre de notification : trois situations
      {
        const jeuBrut = propre(jeu.echeancesFiscales);
        const cas = {};
        async function lire(nom, transformer) {
          db().echeancesFiscales = propre(jeuBrut).map(transformer);
          const a0 = O.alertes.length;
          const root = await O.monter('m12-echeances'); await dormir(1100);
          const r = O.releve(root);
          cas[nom] = { kpis: r.kpis.map((k) => [k.label, k.valeur, k.indice]), notes: r.notes, alertes: O.alertes.slice(a0) };
          root.remove();
        }
        await dormir(1200); await lire('toutPaye', (e) => Object.assign(e, { paye: true }));
        await lire('rienPaye', (e) => Object.assign(e, { paye: false }));
        await lire('toutALAvenir', (e) => Object.assign(e, { paye: e.echeance < '2026-10-30', echeance: e.echeance < '2026-10-30' ? e.echeance : '2027-' + e.echeance.slice(5) }));
        E.cas = cas;
        poserJeu();
      }
      E.joursOuvrables = {};
      rep.echeances = E;

      /* ---------- la baseline 2025 -------------------------------------------------------------------------------------------------- */
      const B = {};
      {
        O.graphiques.length = 0;
        const root = await O.monter('m12-baseline-2025');
        const r = O.releve(root);
        B.kpis = r.kpis; B.onglets = r.onglets; B.cartes = r.cartes; B.notes = r.notes; B.boutons = r.boutons;
        B.tablesControle = r.tables.slice(0, 1).map((t) => ({ entetes: t.entetes, lignes: t.lignes.map((l) => l.cellules) }));
        B.graphiques = propre(O.graphiques.slice(0, 2));
        B.mensuel = O.lignesDe(root, r.tables.length - 1);
        const nT = (re) => root.querySelectorAll('table').length;
        await O.onglet(root, /Postes de charges/);
        const tables = [...root.querySelectorAll('table')];
        B.charges = { nb: O.lignesDe(root, tables.length - 1).length, premier: O.lignesDe(root, tables.length - 1).slice(0, 3), dernier: O.lignesDe(root, tables.length - 1).slice(-2),
          classement: [...root.querySelectorAll('.space-y-2\\.5')].map((l) => [...l.children].map((x) => [...x.querySelectorAll('span')].slice(0, 2).map(texte))) };
        await O.onglet(root, /Comparaison/);
        B.graphiquesComparaison = propre(O.graphiques.slice(2));
        const tabs2 = [...root.querySelectorAll('table')];
        B.comparaison = { lignes: O.lignesDe(root, tabs2.length - 1), notes: O.releve(root).notes, entetes: O.releve(root).tables.slice(-1)[0].entetes };
        const pa = O.pieces.length;
        SIGH.screens['m12-baseline-2025'].actions()[0].click(); await dormir(120);
        B.piece = O.pieces.length > pa ? O.pieces[O.pieces.length - 1] : null;
        B.sourceTexte = texte(root).slice(-200);
        root.remove();
        const E25 = SIGH.compta.EXERCICE_2025;
        B.donnees = { totalCA: E25.totalChiffreAffaires, totalCharges: E25.totalCharges, resultat: E25.resultat, horsExploitation: E25.totalHorsExploitation,
          chargesMois: E25.mois.map((_, i) => E25.chargesDuMois(i)), resultatMois: E25.mois.map((_, i) => E25.resultatDuMois(i)) };
      }
      rep.baseline = B;
      rep.toastsTotal = O.toasts.length;
      return rep;
    }, jeu);
    if (m.erreurs.length) console.log('  ⚠ erreurs JS de la page : ' + m.erreurs.slice(0, 5).join(' | '));
    ecrire('packages/domaine/test/vecteurs/echeances.json', sortie);
    console.log('  ✓ ' + Object.keys(sortie).length + ' blocs');
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
