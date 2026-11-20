/* =============================================================================
 * VECTEURS DE LA BANQUE DE SANG ET DES STATISTIQUES DE RÉACTIFS (M5) — m5-reactifs-stats, m5-banque-sang, m5-donneurs
 * -----------------------------------------------------------------------------
 * Les trois écrans sont montés TELS QUELS dans la page d'extraction, sur un jeu d'essai posé au magasin jetable ; on lit ce qu'ils AFFICHENT (KPI,
 * cartes de disponibilité, tableaux, graphiques interceptés), on PILOTE les modales (création, modification, refus) comme le fait l'agent, et on
 * intercepte les pièces imprimées. La banque de sang et la transfusion sont FERMÉES par défaut dans la maquette (activité non pratiquée,
 * `modulesActifs`) : les écrans sont montés directement, hors du filtre d'activité, pour mesurer leur comportement — la fermeture d'activité
 * n'est pas portée par ces écrans.
 *
 *   node build/vecteurs-sang.js   →   packages/domaine/test/vecteurs/sang.json
 *
 * L'horloge est fixée au 16/08/2026 à MINUIT LOCAL avant le chargement du module (`AUJ` est lu une fois, au chargement) : voir E17.
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs banque de sang / donneurs / statistiques de réactifs');
  const m = await ouvrirMaquette();
  try {
    await m.page.evaluate(() => { SIGH.core.aujourdhui = () => new Date(2026, 7, 16, 0, 0, 0); });
    await m.page.evaluate(() => {
      window.__graphiques = [];
      window.__etats = [];
      const G = SIGH.charts;
      const orig = G.barres;
      G.barres = function () {
        window.__graphiques.push({ type: 'barres', args: JSON.parse(JSON.stringify(Array.prototype.slice.call(arguments, 0, 3))) });
        return orig.apply(this, arguments);
      };
      SIGH.print.etat = function (o) {
        const tab = [];
        const c = o.contenu;
        if (c && c.querySelectorAll) {
          c.querySelectorAll('table').forEach((t) => tab.push({
            entetes: [...t.querySelectorAll('thead th')].map((x) => x.innerText.replace(/\s+/g, ' ').trim()),
            lignes: [...t.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => td.innerText.replace(/\s+/g, ' ').trim())),
          }));
        }
        window.__etats.push(JSON.parse(JSON.stringify({
          titre: o.titre, sousTitre: o.sousTitre || null, cartouche: o.cartouche || null, signatures: o.signatures || null,
          texte: c && c.innerText ? c.innerText.replace(/\s+/g, ' ').trim() : null, tableaux: tab,
        })));
      };
    });
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m5-laboratoire.js') });

    const sortie = await m.page.evaluate(async () => {
      const S = SIGH.store, D = SIGH.data, L = SIGH.labo;
      const propre = (x) => JSON.parse(JSON.stringify(x));
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const norm = (t) => String(t == null ? '' : t).replace(/[\n\t\r]+/g, ' ').replace(/\s+/g, ' ').trim();
      const net = (x) => { const c = Object.assign({}, x); ['_creePar', '_creeLe', '_modifiePar', '_modifieLe', '_archivePar', '_archiveLe'].forEach((k) => delete c[k]); return propre(c); };

      const kpis = (root) => [...root.querySelectorAll('.kpi')].map((k) => {
        const p = k.querySelectorAll('p');
        return { libelle: norm(p[0].innerText), valeur: norm(p[1].innerText), indice: p[2] ? norm(p[2].innerText) : null };
      });
      const tableaux = (root) => [...root.querySelectorAll('table')].map((t) => ({
        entetes: [...t.querySelectorAll('thead th')].map((x) => norm(x.innerText)),
        lignes: [...t.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => norm(td.innerText))),
      }));
      const cartes = (root) => [...root.querySelectorAll('.card')].map((c) => {
        const h = c.querySelector('.card-header, .card-head, h3, h2');
        return h ? norm(h.innerText) : null;
      }).filter(Boolean);
      const notes = (root) => [...root.querySelectorAll('.rounded-lg.border')].map((n) => norm(n.innerText)).filter((t) => t.length > 20);
      async function monter(id) {
        const root = document.createElement('div'); document.body.appendChild(root);
        window.__graphiques.length = 0; window.__etats.length = 0;
        SIGH.screens[id].render(root);
        await dormir(300);
        return root;
      }
      const fermerTout = () => document.querySelectorAll('[role=dialog], .modal-root, .drawer-root').forEach((x) => x.remove());
      const retirer = (root) => { root.remove(); fermerTout(); };
      const toasts = () => [...document.querySelectorAll('#toast-host > div')].map((n) => [...n.querySelectorAll('p')].map((p) => p.textContent.trim()));
      const viderToasts = () => { const h = document.getElementById('toast-host'); if (h) h.innerHTML = ''; };
      const bouton = (racine, texte) => [...racine.querySelectorAll('button')].find((b) => b.textContent.trim() === texte || (texte === 'Nouveau' && b.textContent.includes(texte)) || b.getAttribute('aria-label') === texte || b.title === texte);
      const poser = (id, v) => { const e = document.getElementById('f_' + id); if (!e) throw new Error('champ ' + id); if (e.type === 'checkbox') { e.checked = !!v; } else { e.value = v; } e.dispatchEvent(new Event('input')); e.dispatchEvent(new Event('change')); };
      const champs = () => [...document.querySelectorAll('[role=dialog] label, .modal-root label')].map((l) => norm(l.innerText));
      const mettreDeCote = (cols) => { const sauve = {}; cols.forEach((c) => { sauve[c.name] = c.all().splice(0); }); return sauve; };
      const cliquer = (texte) => [...document.querySelectorAll('button')].find((b) => b.textContent.trim() === texte).click();
      const icone = (ligne, nom) => [...ligne.querySelectorAll('button')].find((b) => (b.getAttribute('aria-label') || b.title) === nom);

      const out = {};
      const colPro = S.collection('produits'), colLot = S.collection('lots'), colDem = S.collection('demandesAnalyses');
      const colPo = S.collection('poches', { module: 'M5', entite: 'PocheSang' });
      const colDo = S.collection('donneurs', { module: 'M5', entite: 'DonneurSang' });
      const J = (n) => { const d = new Date(2026, 7, 16 + n); return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'); };

      out.groupes = D.GROUPES_SANGUINS;
      out.sections = L.SECTIONS.map((s) => ({ id: s.id, label: s.label }));
      out.examens = L.EXAMENS.map((e) => ({ code: e.code, designation: e.designation, section: e.section }));

      /* =================================================================== m5-reactifs-stats */
      const sauveStats = mettreDeCote([colPro, colLot, colDem]);
      const prod = (id, designation, categorie, stock, seuil, prix) => {
        const p = { id, statut: 'actif', code: id, designation, categorie };
        if (prix !== undefined) p.prixAchat = prix;
        if (stock !== undefined) p.stock = stock;
        if (seuil !== undefined) p.seuilAlerte = seuil;
        return p;
      };
      const lotS = (id, produitId, st) => ({ id, statut: st, produitId, numeroLot: 'L-' + id });
      const ex = L.EXAMENS;
      const dem = (id, analyse, extra) => Object.assign({ id, statut: 'actif', reference: 'LAB-' + id, analyse }, extra || {});
      const jeuxStats = [
        { nom: 'jeu mixte : seuils, sans seuil, valeur, lots périmés et en alerte, demandes par section',
          produits: [
            prod('R1', 'Réactif NFS', 'reactif', 5, 10, 1000), prod('R2', 'Réactif glycémie', 'reactif', 50, 10, 200),
            prod('C1', 'Tubes EDTA', 'conso_labo', 3, undefined, 500), prod('C2', 'Gants labo', 'conso_labo', 0, 0, 100),
            prod('C3', 'Pipettes', 'conso_labo', 5, 10, 250), prod('M1', 'Paracétamol', 'medicament', 5, 100, 50),
            prod('R3', 'Réactif sans stock', 'reactif', undefined, 5, 300), prod('R4', 'Réactif sans prix', 'reactif', 7, 7),
          ],
          lots: [lotS('LT1', 'R1', 'perime'), lotS('LT2', 'R2', 'perime'), lotS('LT3', 'R2', 'alerte'), lotS('LT4', 'C1', 'actif'), lotS('LT5', 'M1', 'perime'), lotS('LT6', 'R1', 'archive')],
          demandes: [
            dem('1', ex[0].designation), dem('2', ex[0].designation), dem('3', ex[0].designation),
            dem('4', ex[1].designation), dem('5', ex[1].designation), dem('6', ex[2].designation),
            dem('7', 'Examen inconnu', { categorie: 'Parasitologie' }), dem('8', 'Autre examen inconnu'), dem('9', 'Dernier inconnu', { categorie: 'Parasitologie' }),
            dem('10', ex[3].designation.toLowerCase().replace(/é/g, 'e')), dem('11', ex[4].designation + ' (suite)'),
            dem('12', ''), dem('13', 'x', { examenCode: ex[5].code }), dem('14', ex[0].designation, { statut: 'archive' }),
          ] },
        { nom: 'aucune référence de laboratoire', produits: [prod('M1', 'Paracétamol', 'medicament', 5, 100, 50)], lots: [lotS('LT1', 'M1', 'perime')], demandes: [dem('A1', 'archivée', { statut: 'archive' })] },
        { nom: 'tout est sous contrôle : seuils fixés, aucun lot en défaut',
          produits: [prod('R1', 'Réactif A', 'reactif', 40, 10, 100), prod('C1', 'Tubes', 'conso_labo', 11, 10, 20)], lots: [lotS('LT1', 'R1', 'actif')], demandes: [dem('1', ex[2].designation)] },
        { nom: 'égalité de stock : le tri est stable, stock = seuil compte comme sous le seuil',
          produits: [prod('R1', 'Zèbre', 'reactif', 4, 4, 10), prod('R2', 'Alpha', 'reactif', 4, 3, 10), prod('R3', 'Mu', 'conso_labo', 2, 5, 10), prod('R4', 'Beta', 'reactif', 4, 9, 10)], lots: [], demandes: [dem('A1', 'archivée', { statut: 'archive' })] },
      ];
      out.stats = [];
      for (const jeu of jeuxStats) {
        for (const c of [colPro, colLot, colDem]) c.all().splice(0);
        jeu.produits.forEach((p) => colPro.all().push(p));
        jeu.lots.forEach((l) => colLot.all().push(l));
        jeu.demandes.forEach((d) => colDem.all().push(d));
        const racine = await monter('m5-reactifs-stats');
        out.stats.push({
          nom: jeu.nom, produits: propre(jeu.produits), lots: propre(jeu.lots), demandes: propre(jeu.demandes),
          kpis: kpis(racine), notes: notes(racine), cartes: cartes(racine), tableaux: tableaux(racine), graphiques: propre(window.__graphiques),
        });
        retirer(racine);
      }
      for (const c of [colPro, colLot, colDem]) { c.all().splice(0); sauveStats[c.name].forEach((x) => c.all().push(x)); }

      /* =================================================================== m5-banque-sang */
      const sauvePo = mettreDeCote([colPo]);
      const poche = (n, groupe, jours, etat, reserve, extra) => Object.assign({
        id: 'PS' + n, statut: 'actif', reference: 'PS-' + String(n).padStart(4, '0'), groupe, volume: 450,
        datePrelevement: J(jours - 42), datePeremption: J(jours), donneur: 'Donneur ' + String(n).padStart(3, '0'), etat, reserve: !!reserve,
      }, extra || {});
      const jeuBanque = [
        poche(1, 'O+', 20, 'actif', false), poche(2, 'O+', 3, 'alerte', false), poche(3, 'O+', -2, 'perime', false), poche(4, 'O+', 30, 'actif', true),
        poche(5, 'A+', 12, 'actif', false), poche(6, 'A+', 25, 'actif', false), poche(7, 'A+', 8, 'actif', false),
        poche(8, 'B-', 15, 'actif', false), poche(9, 'B-', 6, 'alerte', true),
        poche(10, 'AB+', 0, 'alerte', false), poche(11, 'AB+', 7, 'actif', false),
        poche(12, 'O-', 9, 'alerte', false, { volume: 250 }), poche(13, 'O-', 40, 'actif', false, { volume: 350 }), poche(14, 'O-', -10, 'perime', true),
        poche(15, 'A-', 5, 'actif', false, { statut: 'archive' }),
      ];
      colPo.all().splice(0);
      jeuBanque.forEach((p) => colPo.all().push(p));
      let racine = await monter('m5-banque-sang');
      const grille = [...racine.querySelectorAll('.grid .rounded-xl.border')].map((c) => {
        const ps = c.querySelectorAll('p');
        return { groupe: norm(ps[0].innerText), nombre: norm(ps[1].innerText), mot: norm(ps[2].innerText), ton: ps[0].className.match(/text-(danger|warning|success)-700/)[1] };
      });
      out.banque = {
        poches: propre(jeuBanque),
        kpis: kpis(racine), cartes: cartes(racine), grille, tableaux: tableaux(racine),
        filtres: [...racine.querySelectorAll('select')].map((s) => [...s.options].map((o) => [o.value, norm(o.textContent)])),
        boutons: [...racine.querySelectorAll('button')].map((b) => norm(b.textContent || b.getAttribute('aria-label') || b.title)).filter(Boolean).slice(0, 12),
      };
      bouton(racine, 'Bon de demande de sang').click(); await dormir(200);
      out.banque.bon = propre(window.__etats[0] || null);
      const ligne = (ref) => [...racine.querySelectorAll('tbody tr')].find((tr) => tr.innerText.includes(ref));
      icone(ligne('PS-0001'), 'Modifier').click(); await dormir(250);
      out.banque.modification = { champs: champs() };
      viderToasts();
      poser('datePeremption', '');
      cliquer('Enregistrer'); await dormir(250);
      out.banque.modification.refusSansPeremption = { toasts: toasts(), fiche: net(colPo.all().find((p) => p.id === 'PS1')) };
      fermerTout(); viderToasts();
      icone(ligne('PS-0001'), 'Modifier').click(); await dormir(250);
      poser('datePeremption', J(-5)); poser('volume', '350'); poser('donneur', 'Donneur modifié'); poser('observations', 'Contrôle');
      cliquer('Enregistrer'); await dormir(300);
      out.banque.modification.enregistre = { toasts: toasts(), fiche: net(colPo.all().find((p) => p.id === 'PS1')) };
      retirer(racine);
      racine = await monter('m5-banque-sang');
      out.banque.apresModification = { kpis: kpis(racine), tableaux: tableaux(racine) };
      retirer(racine);
      colPo.all().splice(0);
      const gr = D.GROUPES_SANGUINS;
      const grand = [];
      for (let i = 1; i <= 17; i++) { const j = (i * 7) % 23 - 4; grand.push(poche(i, gr[i % 8], j, j < 0 ? 'perime' : (j < 7 ? 'alerte' : 'actif'), i % 5 === 0)); }
      grand.forEach((p) => colPo.all().push(p));
      racine = await monter('m5-banque-sang');
      out.banque.grand = { poches: propre(grand), kpis: kpis(racine), tableaux: tableaux(racine) };
      retirer(racine);
      colPo.all().splice(0); sauvePo.poches.forEach((x) => colPo.all().push(x));

      /* =================================================================== m5-donneurs */
      const sauveDo = mettreDeCote([colDo]);
      const don = (n, nom, groupe, type, nb, dernier, eligible, extra) => Object.assign({
        id: 'DON' + String(n).padStart(4, '0'), statut: 'actif', reference: 'DON-' + String(n).padStart(4, '0'), nom, telephone: '9700000' + n,
        groupe, dernierDon: J(dernier), nbDons: nb, eligible, type,
      }, extra || {});
      const jeuDon = [
        don(1, 'ADAM Karim', 'O+', 'Bénévole', 3, -200, true), don(2, 'BIO Salamatou', 'A+', 'Familial', 1, -90, true),
        don(3, 'CHABI Rock', 'B-', 'Familial', 12, -89, true), don(4, 'DOSSOU Ida', 'AB+', 'Compensation', 5, -30, true),
        don(5, 'EDAH Paul', 'O-', 'Bénévole', 2, -400, false), don(6, 'FASSINOU Léa', 'O+', 'Bénévole', 7, -10, false),
        don(7, 'GBEGNON Eric', 'A-', 'Compensation', 4, -91, true), don(8, 'HOUNKPATIN Ana', 'B+', 'Familial', 9, 0, true),
        don(9, 'ILLA Zita', 'B+', 'Bénévole', 2, -50, true, { statut: 'archive' }),
      ];
      colDo.all().splice(0);
      jeuDon.forEach((p) => colDo.all().push(p));
      racine = await monter('m5-donneurs');
      out.donneurs = {
        donneurs: propre(jeuDon), kpis: kpis(racine), onglets: [...racine.querySelectorAll('[role=tab], .tab')].map((t) => norm(t.textContent)),
        tableaux: tableaux(racine),
        filtres: [...racine.querySelectorAll('select')].map((s) => [...s.options].map((o) => [o.value, norm(o.textContent)])),
        boutons: [...racine.querySelectorAll('button')].map((b) => norm(b.textContent || b.getAttribute('aria-label') || b.title)).filter(Boolean).slice(0, 14),
      };
      const lig = (ref) => [...racine.querySelectorAll('tbody tr')].find((tr) => tr.innerText.includes(ref));
      lig('DON-0003').click(); await dormir(250);
      const tiroir = document.querySelector('[role=dialog], .drawer-root') || document.body;
      out.donneurs.tiroir = {
        texte: norm(tiroir.innerText),
        boutons: [...tiroir.querySelectorAll('button')].map((b) => norm(b.textContent || b.getAttribute('aria-label') || b.title)).filter(Boolean),
      };
      fermerTout();
      icone(lig('DON-0003'), 'Imprimer l’état').click(); await dormir(200);
      out.donneurs.carte = propre(window.__etats[0] || null);
      bouton(racine, 'Nouveau').click(); await dormir(250);
      out.donneurs.creation = { champs: champs(), defauts: {} };
      for (const n of ['nom', 'telephone', 'groupe', 'type', 'dernierDon', 'nbDons', 'eligible']) {
        const e = document.getElementById('f_' + n);
        out.donneurs.creation.defauts[n] = e ? (e.type === 'checkbox' ? e.checked : e.value) : '(absent)';
      }
      viderToasts();
      cliquer('Créer'); await dormir(200);
      out.donneurs.creation.refusVide = { toasts: toasts(), total: colDo.all().length };
      poser('nom', 'IMOROU Zaki'); poser('telephone', '97111111'); poser('groupe', 'AB-'); poser('type', 'Compensation'); poser('dernierDon', '2026-07-01'); poser('nbDons', '6'); poser('eligible', false);
      viderToasts();
      cliquer('Créer'); await dormir(300);
      out.donneurs.creation.cree = { toasts: toasts(), fiche: net(colDo.all().find((d) => d.nom === 'IMOROU Zaki')), total: colDo.all().length };
      bouton(racine, 'Nouveau').click(); await dormir(250);
      poser('nom', 'JOHNSON Mary'); poser('telephone', '97222222');
      cliquer('Créer'); await dormir(300);
      out.donneurs.creation.creeDefauts = { fiche: net(colDo.all().find((d) => d.nom === 'JOHNSON Mary')) };
      icone(lig('DON-0003'), 'Modifier').click(); await dormir(250);
      out.donneurs.modification = { champs: champs() };
      poser('nbDons', '13'); poser('telephone', '97999999');
      viderToasts();
      cliquer('Enregistrer'); await dormir(300);
      out.donneurs.modification.enregistre = { toasts: toasts(), fiche: net(colDo.all().find((d) => d.id === 'DON0003')) };
      retirer(racine);
      colDo.all().splice(0); sauveDo.donneurs.forEach((x) => colDo.all().push(x));
      return out;
    });
    ecrire('packages/domaine/test/vecteurs/sang.json', sortie);
    console.log('  stats: ' + sortie.stats.length + ' jeux · banque: ' + sortie.banque.poches.length + ' poches · donneurs: ' + sortie.donneurs.donneurs.length);
    if (m.erreurs.length) console.log('  erreurs JS de la page : ' + m.erreurs.slice(0, 5).join(' | '));
  } finally {
    await m.fermer();
  }
})().catch((e) => { console.error(e); process.exit(1); });
