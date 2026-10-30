/* =============================================================================
 * VECTEURS DES POINTS DU GESTIONNAIRE DE STOCK — m6-point-ventes et m6-point-stock PILOTÉS comme le fait l'agent
 * -----------------------------------------------------------------------------
 * Les deux écrans sont CALCULÉS : tout vient des factures (lignes payables), des mouvements et des produits. Le script monte le VRAI écran,
 * règle les commandes (périodicité, date, plage libre, clients, groupes, articles, vue, familles), puis relit ce que l'écran a affiché :
 * la note, les indicateurs, les LIGNES COMPLÈTES de chaque tableau (`lignesFiltrees`), les blocs par patient, les données des graphiques
 * et ce que chaque bouton d'impression passe à `P.etat` (cartouche, tableaux, pied, phrases) — plus le bloc « Filtres appliqués » de la feuille.
 * Le portage Dart (`packages/domaine/lib/src/stock/points.dart`) reçoit les mêmes registres (factures, actes, produits, mouvements) et doit
 * retrouver ces sorties.
 *
 *   node build/vecteurs-points.js   →   packages/domaine/test/vecteurs/points.json
 *
 * Les dates de chaque cas sont EXPLICITES : le résultat ne dépend pas de l'horloge du moment.
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs des points du gestionnaire de stock');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m6-stock.js') });
    const sortie = await m.page.evaluate(async () => {
      const S = SIGH.store, C = SIGH.core, D = SIGH.data;
      const propre = (x) => JSON.parse(JSON.stringify(x));
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const txt = (e) => (e ? e.textContent.replace(/\s+/g, ' ').trim() : '');

      /* --- interception des graphiques et de l'impression ---------------------------------------------------------------- */
      const graphiques = [];
      const barresOrig = SIGH.charts.barres, anneauOrig = SIGH.charts.anneau;
      SIGH.charts.barres = function (labels, series, opts) {
        graphiques.push({ type: 'barres', labels: propre(labels), series: propre(series.map((s) => ({ label: s.label, data: s.data }))), horizontal: !!(opts && opts.horizontal) });
        return barresOrig.apply(this, arguments);
      };
      SIGH.charts.anneau = function (labels, data) {
        graphiques.push({ type: 'anneau', labels: propre(labels), data: propre(data) });
        return anneauOrig.apply(this, arguments);
      };
      const imprimes = [];
      const etatOrig = SIGH.print.etat;
      function lireContenu(n) {
        const blocs = [];
        /* Le contenu d'un état peut être le tableau LUI-MÊME (point du stock) : `querySelectorAll` ne rend que des descendants. */
        [...(n.matches('table, p, h3, h4') ? [n] : []), ...n.querySelectorAll('table, p, h3, h4')].forEach((e) => {
          if (e.tagName === 'TABLE') {
            blocs.push({ table: {
              entetes: [...e.querySelectorAll('thead th')].map(txt),
              lignes: [...e.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map(txt)),
              pied: e.querySelector('tfoot tr') ? [...e.querySelector('tfoot tr').children].map(txt) : null,
            } });
          } else if (!e.closest('table')) {
            blocs.push({ texte: txt(e) });
          }
        });
        return blocs;
      }
      SIGH.print.etat = function (o) {
        const rec = { titre: o.titre, sousTitre: o.sousTitre, cartouche: propre(o.cartouche), signatures: propre(o.signatures),
          contenu: lireContenu(o.contenu) };
        const r = etatOrig.apply(this, arguments);
        const feuilles = document.querySelectorAll('.print-sheet');
        const feuille = feuilles[feuilles.length - 1];
        rec.filtres = [];
        if (feuille) {
          const titre = [...feuille.querySelectorAll('p')].find((p) => txt(p) === 'Filtres appliqués à cet état');
          if (titre) {
            [...titre.parentElement.querySelectorAll('.flex-wrap > span')].forEach((s) => {
              rec.filtres.push([txt(s.children[0]).replace(/ :$/, ''), txt(s.children[1])]);
            });
          }
        }
        imprimes.push(rec);
        return r;
      };

      const combosDe = (root) => [...root.querySelectorAll('*')].filter((e) => typeof e.setOptions === 'function');
      const tablesDe = (e) => [...e.querySelectorAll('*')].filter((x) => typeof x.lignesFiltrees === 'function');
      const bouton = (root, t) => [...root.querySelectorAll('button')].find((b) => txt(b) === t);
      function kpis(root) {
        return [...root.querySelectorAll('.kpi')].map((k) => ({
          label: txt(k.querySelector('.kpi-label')), valeur: txt(k.querySelector('.kpi-value')),
          indice: txt(k.querySelector('p.text-xs')) || null }));
      }
      function note(root) {
        return txt(root.querySelector('div.flex.items-start.gap-2.rounded-lg.border'));
      }
      function blocsPatients(panel) {
        return [...panel.querySelectorAll(':scope .card')].map((c) => {
          const tete = c.querySelector('.card-head');
          const ps = [...tete.querySelectorAll('p')].map(txt);
          const corps = c.querySelector('.card-body');
          const secteurs = [];
          [...corps.children].forEach((ch) => {
            if (ch.querySelector && ch.querySelector('h4')) {
              secteurs.push({ titre: txt(ch.querySelector('h4')), resume: txt(ch.querySelector('span')), lignes: [] });
            } else if (ch.tagName === 'TABLE' || ch.querySelector('table')) {
              const t = ch.tagName === 'TABLE' ? ch : ch.querySelector('table');
              secteurs[secteurs.length - 1].lignes = [...t.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map(txt));
            }
          });
          return { patient: txt(tete.querySelector('h3')), sous: ps[0], netLibelle: ps[1], net: ps[2], secteurs };
        });
      }

      /* --- m6-point-ventes ---------------------------------------------------------------------------------------------- */
      const ventes = [];
      async function jouerVentes(nom, saisie) {
        graphiques.length = 0; imprimes.length = 0;
        const root = document.createElement('div'); root.id = 'page-content'; document.body.appendChild(root);
        SIGH.screens['m6-point-ventes'].render(root);
        await dormir(30);
        const sel = root.querySelector('select.select');
        const dates = [...root.querySelectorAll('input[type=date]')];
        const libre = root.querySelector('input[type=checkbox]');
        const [cClient, cGroupe, cArticle] = combosDe(root);
        const changer = (e) => e.dispatchEvent(new Event('change'));
        sel.value = saisie.periode || 'mois';
        dates[0].value = saisie.date || '2026-08-16';
        dates[1].value = saisie.du || '2026-07-18'; dates[2].value = saisie.au || '2026-08-16';
        libre.checked = !!saisie.libre;
        cClient.value = saisie.clients || []; cGroupe.value = saisie.groupes || []; cArticle.value = saisie.articles || [];
        graphiques.length = 0; changer(sel); await dormir(40);
        const cas = { nom, saisie, note: note(root), kpis: kpis(root), onglets: {}, impressions: {} };
        const ongletIds = ['journal', 'clients', 'patients', 'articles', 'groupes', 'evolution'];
        for (const id of ongletIds) {
          graphiques.length = 0;
          root.querySelector('[data-tab="' + id + '"]').click();
          await dormir(30);
          const panel = root.querySelector('[role=tab].tab-active').parentElement.nextElementSibling;
          const o = { tables: tablesDe(panel).map((t) => propre(t.lignesFiltrees())), graphiques: propre(graphiques) };
          if (id === 'patients') { o.blocs = blocsPatients(panel); o.texte = txt(panel).slice(0, 400); }
          if (id === 'evolution') o.texte = txt(panel).slice(0, 200);
          cas.onglets[id] = o;
        }
        cas.badgePatients = txt(root.querySelector('[data-tab="patients"]'));
        cas.badgeJournal = txt(root.querySelector('[data-tab="journal"]'));
        for (const [cle, libelle] of [['detaille', 'Point détaillé'], ['global', 'Point global'], ['patient', 'Point par patient']]) {
          imprimes.length = 0;
          bouton(root, libelle).click();
          await dormir(60);
          cas.impressions[cle] = propre(imprimes[0] || null);
        }
        root.remove();
        ventes.push(cas);
      }

      /* Les clients, groupes, articles réels du jeu — choisis par leur activité, jamais au hasard. */
      const factures = S.collection('factures').active();
      const parClient = C.groupBy(factures.filter((f) => f.patientId), 'patientId');
      const ordreClients = Object.keys(parClient).sort((a, b) => parClient[b].length - parClient[a].length);
      const assure = ordreClients.find((k) => parClient[k].some((f) => f.assureur));
      const agent = factures.find((f) => f.priseEnChargePersonnel);
      const remise = factures.find((f) => (f.lignes || []).some((l) => l.remise));
      const nonAssure = ordreClients.find((k) => !parClient[k].some((f) => f.assureur || f.priseEnChargePersonnel));
      const cl3 = [ordreClients[0], assure, agent && agent.patientId, remise && remise.patientId].filter((x, i, a) => x && a.indexOf(x) === i).slice(0, 3);
      const lignesToutes = factures.flatMap((f) => f.lignes || []);
      const art = lignesToutes.filter((l) => l.designation).map((l) => l.designation);
      const topArticles = [...new Set(art)].sort((a, b) => art.filter((x) => x === b).length - art.filter((x) => x === a).length).slice(0, 2);

      const cas = [
        ['mois fini le 16/08/2026', { periode: 'mois', date: '2026-08-16' }],
        ['journée du 14/08/2026', { periode: 'jour', date: '2026-08-14' }],
        ['semaine finie le 14/08/2026', { periode: 'semaine', date: '2026-08-14' }],
        ['trimestre fini le 16/08/2026', { periode: 'trimestre', date: '2026-08-16' }],
        ['semestre fini le 16/08/2026', { periode: 'semestre', date: '2026-08-16' }],
        ['année finie le 16/08/2026 (évolution au mois)', { periode: 'annee', date: '2026-08-16' }],
        ['plage libre avril–juin', { libre: true, du: '2026-04-01', au: '2026-06-30' }],
        ['plage libre INVERSÉE (remise dans l\'ordre)', { libre: true, du: '2026-06-30', au: '2026-04-01' }],
        ['plage libre de 40 jours (évolution au jour)', { libre: true, du: '2026-07-01', au: '2026-08-09' }],
        ['période sans vente (octobre 2026)', { periode: 'mois', date: '2026-10-30' }],
        ['groupe Laboratoire, année', { periode: 'annee', date: '2026-08-16', groupes: ['laboratoire'] }],
        ['groupes Pharmacie + Consultation, année', { periode: 'annee', date: '2026-08-16', groupes: ['pharmacie', 'consultation'] }],
        ['groupe Maternité (secteur de l\'acte), année', { periode: 'annee', date: '2026-08-16', groupes: ['maternite'] }],
        ['groupe Imagerie médicale, année', { periode: 'annee', date: '2026-08-16', groupes: ['echographie'] }],
        ['groupe Hospitalisation et soins, année', { periode: 'annee', date: '2026-08-16', groupes: ['hospitalisation'] }],
        ['un client, année (onglet Par patient)', { periode: 'annee', date: '2026-08-16', clients: cl3.slice(0, 1) }],
        ['trois clients dont un assuré / un agent, année', { periode: 'annee', date: '2026-08-16', clients: cl3 }],
        ['client non assuré, année', { periode: 'annee', date: '2026-08-16', clients: nonAssure ? [nonAssure] : [] }],
        ['deux articles les plus vendus, année', { periode: 'annee', date: '2026-08-16', articles: topArticles }],
        ['clients + groupe + article combinés', { periode: 'annee', date: '2026-08-16', clients: cl3.slice(0, 2), groupes: ['pharmacie', 'hospitalisation'], articles: topArticles }],
      ];
      for (const [nom, saisie] of cas) await jouerVentes(nom, saisie);

      /* --- m6-point-stock ----------------------------------------------------------------------------------------------- */
      const stock = [];
      async function jouerStock(nom, saisie) {
        graphiques.length = 0; imprimes.length = 0;
        S.setValorisationSortie(saisie.methode || 'prixVente');
        const root = document.createElement('div'); root.id = 'page-content'; document.body.appendChild(root);
        SIGH.screens['m6-point-stock'].render(root);
        await dormir(30);
        const [selVue, selPeriode] = root.querySelectorAll('select.select');
        const date = root.querySelector('input[type=date]');
        const [cFamille] = combosDe(root);
        selVue.value = saisie.vue; selPeriode.value = saisie.periode || 'mois'; date.value = saisie.date || '2026-08-16';
        cFamille.value = saisie.familles || [];
        graphiques.length = 0; selVue.dispatchEvent(new Event('change')); await dormir(60);
        const c = { nom, saisie, note: note(root), kpis: kpis(root), periodeDesactivee: selPeriode.disabled,
          tables: tablesDe(root).map((t) => propre(t.lignesFiltrees())), graphiques: propre(graphiques) };
        imprimes.length = 0;
        bouton(root, 'Imprimer le point').click();
        await dormir(60);
        c.impression = propre(imprimes[0] || null);
        root.remove();
        stock.push(c);
      }
      const vues = ['pharmacie_restant', 'pharmacie_recu', 'magasin_nouveau', 'magasin_sorti', 'magasin_restant'];
      for (const v of vues) await jouerStock('vue ' + v + ', mois fini le 16/08/2026', { vue: v });
      for (const v of vues) await jouerStock('vue ' + v + ', année finie le 16/08/2026', { vue: v, periode: 'annee' });
      await jouerStock('flux de la semaine du 10/08', { vue: 'magasin_sorti', periode: 'semaine', date: '2026-08-14' });
      await jouerStock('flux du jour 16/08', { vue: 'pharmacie_recu', periode: 'jour', date: '2026-08-16' });
      await jouerStock('flux trimestre', { vue: 'magasin_nouveau', periode: 'trimestre', date: '2026-08-16' });
      await jouerStock('flux sans mouvement (octobre 2026)', { vue: 'magasin_sorti', periode: 'mois', date: '2026-10-30' });
      await jouerStock('état pharmacie, familles Médicaments', { vue: 'pharmacie_restant', familles: ['medicament'] });
      await jouerStock('état magasin, deux familles', { vue: 'magasin_restant', familles: ['medicament', 'conso_medical'] });
      await jouerStock('flux filtré sur la famille Réactifs', { vue: 'magasin_nouveau', periode: 'annee', familles: ['reactif'] });
      await jouerStock('flux année, une seule famille (cumul par famille masqué)', { vue: 'magasin_sorti', periode: 'annee', familles: ['conso_labo'] });
      /* Sur le jeu, le CUMP arrondi et le prix de vente coïncident presque partout : trois articles reçoivent un CUMP franchement différent
         pour que la bascule de méthode se MESURE. Le correctif est consigné dans chaque cas, puis défait. */
      const colProd = S.collection('produits');
      const gros = colProd.active().slice().sort((a, b) => (b.stockGros + b.stockDetail) - (a.stockGros + a.stockDetail)).slice(0, 3);
      const sauve = gros.map((p) => ({ id: p.id, cump: p.cump }));
      const corrections = {};
      gros.forEach((p, i) => { corrections[p.id] = { cump: Math.round(p.prixVente * (0.5 + 0.1 * i) * 100) / 100 }; colProd.update(p.id, corrections[p.id]); });
      for (const v of vues) await jouerStock('vue ' + v + ' valorisée au CUMP', { vue: v, periode: 'annee', methode: 'cump', corrections });
      await jouerStock('vue magasin_restant au PRIX DE VENTE avec les mêmes CUMP corrigés', { vue: 'magasin_restant', corrections });
      sauve.forEach((s) => colProd.update(s.id, { cump: s.cump }));
      S.setValorisationSortie('prixVente');

      /* --- Empreinte des registres lus : le test Dart vérifie qu'il rejoue sur les MÊMES données ------------------------- */
      const somme = (a, k) => a.reduce((t, x) => t + (Number(x[k]) || 0), 0);
      const empreinte = {
        factures: factures.length, lignes: lignesToutes.length, sommeNet: somme(lignesToutes, 'montant'),
        produits: S.collection('produits').active().length, sommeStock: somme(S.collection('produits').active(), 'stock'),
        mouvements: S.collection('mouvements').active().length, sommeQteMouvements: somme(S.collection('mouvements').active(), 'quantite'),
        actes: S.collection('actes').all().length,
      };
      return { ventes, stock, empreinte, groupes: propre(D.GROUPES_PRESTATION), familles: propre(D.FAMILLES_ARTICLES), categories: propre(D.CATEGORIES_LIGNE),
        periodes: propre(C.PERIODES) };
    });
    sortie.ventes.forEach((c) => console.log('  ventes · ' + c.nom + ' → ' + c.kpis[0].valeur + ' brut, ' + (c.onglets.journal.tables[0] || []).length + ' pièces'));
    sortie.stock.forEach((c) => console.log('  stock  · ' + c.nom + ' → ' + (c.tables[0] || []).length + ' réf., montant ' + c.kpis[2].valeur));
    /* Écrit COMPACT : les lignes complètes de vingt-cinq cas pèsent plusieurs mégaoctets une fois indentées. */
    ecrire('packages/domaine/test/vecteurs/points.json', JSON.stringify(Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-points.js — m6-point-ventes et m6-point-stock pilotés. Ne pas éditer.' }, sortie)) + '\n');
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
