/* =============================================================================
 * VECTEURS DES ENQUÊTES, DE LA SATISFACTION, DES VALIDATIONS ET DE LA GED — les écrans RÉELS pilotés comme le fait l'agent
 * -----------------------------------------------------------------------------
 * Sept écrans : adm-enquetes, adm-satisfaction, adm-validations, enquete-publique (M13) ; ged-bibliotheque, ged-workflow, ged-archives (GED).
 * Chaque cas monte l'écran dans Chrome, pose les entrées au magasin (PROJETÉES aux seuls champs que la règle lit), clique, et relève ce que l'agent
 * voit : indicateurs, cartes, lignes de tableau, données de graphique, enregistrements nés. Le portage Dart rejoue les RÈGLES sur ces entrées.
 *   node build/vecteurs-qualite.js   →   packages/domaine/test/vecteurs/qualite.json
 * L'horloge est fixée au 16/08/2026 10 h : `C.aujourdhui()` ET `new Date()`.
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs enquêtes, satisfaction, validations et GED');
  const m = await ouvrirMaquette();
  try {
    await m.page.evaluate(() => {
      SIGH.core.aujourdhui = () => new Date(2026, 7, 16, 10, 0, 0);
      const Vrai = Date;
      const FIXE = new Vrai(2026, 7, 16, 10, 0, 0).getTime();
      class Faux extends Vrai { constructor(...a) { if (a.length === 0) super(FIXE); else super(...a); } static now() { return FIXE; } }
      window.Date = Faux;
      window.__etats = [];
      SIGH.print.etat = function (o) {
        const tab = [];
        let c = o.contenu;
        if (typeof c === 'string') { const d = document.createElement('div'); d.innerHTML = c; c = d; }
        if (c && c.querySelectorAll) {
          (c.tagName === 'TABLE' ? [c] : [...c.querySelectorAll('table')]).forEach((t) => tab.push({
            entetes: [...t.querySelectorAll('thead th')].map((x) => x.innerText.replace(/\s+/g, ' ').trim()),
            lignes: [...t.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => td.innerText.replace(/\s+/g, ' ').trim())),
            pied: [...t.querySelectorAll('tfoot tr')].map((tr) => [...tr.children].map((td) => td.innerText.replace(/\s+/g, ' ').trim())),
          }));
        }
        window.__etats.push(JSON.parse(JSON.stringify({ titre: o.titre, sousTitre: o.sousTitre || null, cartouche: o.cartouche || null, signatures: o.signatures || null, tableaux: tab })));
      };
    });
    for (const f of ['m13-administration.js', 'ged.js']) await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules', f) });

    const sortie = await m.page.evaluate(async () => {
      const S = SIGH.store, C = SIGH.core;
      const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x, (k, v) => (v === undefined ? null : v)));
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const norm = (t) => String(t || '').replace(/\s+/g, ' ').trim();
      const nettoyer = () => { document.querySelectorAll('.modal-root, [role=dialog]').forEach((e) => e.remove()); document.querySelectorAll('#toast-host > div').forEach((e) => e.remove()); };
      const monter = async (id) => { const root = document.createElement('div'); document.body.appendChild(root); SIGH.screens[id].render(root); await dormir(80); return root; };
      const kpis = (root) => [...root.querySelectorAll('.kpi')].map((k) => ({ label: norm(k.querySelector('.kpi-label').textContent), valeur: norm(k.querySelector('.kpi-value').textContent), indice: norm((k.querySelector('.kpi-value').nextElementSibling || {}).textContent) }));
      const lignesTable = (racine, n) => [...racine.querySelectorAll('tbody tr')].slice(0, n || 400).map((tr) => [...tr.children].map((td) => norm(td.textContent)));
      const entetes = (racine) => [...racine.querySelectorAll('thead th')].map((th) => norm(th.textContent));
      const bouton = (portee, libelle) => [...portee.querySelectorAll('button')].find((b) => norm(b.textContent) === libelle || b.getAttribute('aria-label') === libelle || b.title === libelle);
      const dernierBouton = (libelle) => [...document.querySelectorAll('button')].filter((b) => norm(b.textContent) === libelle).pop();
      const poser = (id, v) => { const e = document.getElementById('f_' + id); if (!e) throw new Error('champ ' + id + ' ; présents : ' + [...document.querySelectorAll('[id^=f_]')].map((x) => x.id).join(',')); e.value = v; e.dispatchEvent(new Event('input')); e.dispatchEvent(new Event('change')); };
      const toasts = () => [...document.querySelectorAll('#toast-host > div')].map((t) => norm((t.querySelector('p') || {}).textContent));
      const graphique = (carte) => { const cv = carte && carte.querySelector('canvas'); const ch = cv && Chart.getChart(cv); return ch ? { etiquettes: ch.data.labels, series: ch.data.datasets.map((d) => ({ label: d.label, data: d.data })) } : null; };
      const carteNommee = (root, titre) => [...root.querySelectorAll('.card')].find((c) => norm((c.querySelector('.card-title') || {}).textContent).startsWith(titre));
      const net = (x) => { const c = Object.assign({}, x); ['id', '_creePar', '_creeLe', '_modifiePar', '_modifieLe', '_archivePar', '_archiveLe'].forEach((k) => delete c[k]); return propre(c); };
      const champsOuverts = () => [...document.querySelectorAll('[role=dialog] [id^=f_]')].map((e) => ({ nom: e.id.slice(2), balise: e.tagName.toLowerCase(), options: e.tagName === 'SELECT' ? [...e.options].map((o) => o.value).filter(Boolean) : null }));
      const libellesChamps = () => [...document.querySelectorAll('[role=dialog] label')].map((l) => norm(l.textContent));
      const remplacer = (col, fiches) => { col.all().splice(0); fiches.forEach((f) => col.all().push(f)); };
      const compter = (rows, champs) => { const g = {}; rows.forEach((r) => { const p = {}; champs.forEach((c) => { p[c] = r[c] === undefined ? null : r[c]; }); const k = JSON.stringify(p); g[k] = g[k] || { p, n: 0 }; g[k].n++; }); return Object.values(g).map((x) => Object.assign({}, x.p, { n: x.n })); };
      try { SIGH.peuplerParcours(); } catch (e) { window.__erreurPeuplement = String(e); }
      const sortieG = {};
      const colEnq = S.collection('enquetes', { module: 'M13' }), colRep = S.collection('reponsesEnquetes', { module: 'M13' }), colJet = S.collection('jetonsEnquete', { module: 'M13' });
      const enqSat = () => colEnq.all().find((e) => e.reference === 'ENQ-SAT');

      /* ===================================================================================== SATISFACTION */
      const root0 = await monter('adm-enquetes'); root0.remove();   // amorçage par l'écran, comme la maquette
      const questionsOrigine = propre(enqSat().questions);
      const repsOrigine = propre(colRep.all());
      {
        const projReps = () => colRep.active().map((x) => ({ enqueteId: x.enqueteId, date: x.date, reponses: x.reponses }));
        const lire = async (nom, reps) => {
          const root = await monter('adm-satisfaction');
          const carteN = carteNommee(root, 'Note moyenne par question');
          const carteC = carteNommee(root, 'Derniers commentaires');
          const r = {
            nom, entrees: { enquete: propre(enqSat()), reponses: propre(reps) },
            kpis: kpis(root), graphique: graphique(carteN),
            videNotes: carteN ? norm(carteN.textContent) : null,
            commentaires: carteC ? [...carteC.querySelectorAll('.rounded-lg')].map((d) => [...d.querySelectorAll('p')].map((p) => norm(p.textContent))) : [],
            videCommentaires: carteC ? norm(carteC.textContent) : null,
            texte: norm(root.textContent),
          };
          root.remove();
          return r;
        };
        const cas = [];
        cas.push(await lire('jeu de démonstration (26 réponses)', projReps()));
        colRep.all().splice(0);
        const rep = (id, date, reponses) => colRep.all().push({ id, date, canal: 'Au guichet', reponses, statut: 'actif', enqueteId: 'ENQ0001' });
        rep('R1', '2026-08-01', { Q_ACCUEIL: 4, Q_ATTENTE: 1, Q_PROPRETE: '5', Q_SOINS: 0, Q_RECO: 'Oui, sans hésiter', Q_LIBRE: '  Bravo  ' });
        rep('R2', '2026-08-01', { Q_ACCUEIL: 5, Q_ATTENTE: 2, Q_PROPRETE: 'abc', Q_SOINS: 3, Q_RECO: 'plutôt oui', Q_LIBRE: 'Salle d’attente trop chaude' });
        rep('R3', '2026-08-03', { Q_ACCUEIL: 5, Q_ATTENTE: '', Q_PROPRETE: 3, Q_SOINS: 4, Q_RECO: 'Plutôt non', Q_LIBRE: '   ' });
        rep('R4', '2026-08-04', { Q_ACCUEIL: 3, Q_RECO: 'Non', Q_LIBRE: 'Un' });
        for (let i = 5; i <= 12; i++) rep('R' + i, '2026-08-' + String(i).padStart(2, '0'), { Q_ACCUEIL: 5, Q_RECO: 'Oui, sans hésiter', Q_LIBRE: 'Commentaire ' + i });
        cas.push(await lire('arrondis, valeurs ignorées, égalités de date, plus de huit commentaires', projReps()));
        colRep.all().splice(0);
        cas.push(await lire('aucune réponse', []));
        colEnq.update(enqSat().id, { questions: [{ code: 'Q_LIBRE', libelle: 'Ce que nous pourrions améliorer', type: 'texte' }] });
        rep('R20', '2026-08-02', { Q_LIBRE: 'Rien' });
        cas.push(await lire('un modèle sans question de type note', projReps()));
        colEnq.update(enqSat().id, { questions: [{ code: 'Q_X', libelle: 'Nous recommanderiez-vous ?', type: 'choix', options: ['Oui', 'Non'] }, { code: 'Q_N', libelle: 'Note', type: 'note' }] });
        colRep.all().splice(0);
        rep('R30', '2026-08-02', { Q_X: 'Oui, bien sûr', Q_N: 4 }); rep('R31', '2026-08-02', { Q_X: 'Non', Q_N: 3 });
        cas.push(await lire('la question de recommandation se reconnaît à son libellé', projReps()));
        colEnq.update(enqSat().id, { questions: questionsOrigine });
        colEnq.archive(enqSat().id);
        const root = await monter('adm-satisfaction');
        cas.push({ nom: 'aucune enquête active', texte: norm(root.textContent), kpis: kpis(root) });
        root.remove(); colEnq.restore(enqSat().id);
        remplacer(colRep, repsOrigine);
        sortieG.satisfaction = cas;
      }

      /* ===================================================================================== ENQUÊTES */
      {
        const cas = [];
        let root = await monter('adm-enquetes');
        cas.push({ nom: 'ouverture (jeu : un modèle, aucun lien)', kpis: kpis(root), onglets: [...root.querySelectorAll('[role=tab]')].map((t) => norm(t.textContent)),
          entetes: entetes(root), lignes: lignesTable(root) });

        // « Recueillir » : le formulaire naît du modèle — on ajoute une question AU MODÈLE, elle paraît à la prochaine saisie.
        bouton(root, 'Recueillir').click(); await dormir(60);
        const ouverture1 = { libelles: libellesChamps(), champs: champsOuverts() };
        nettoyer();
        const avantQ = propre(enqSat().questions);
        const neuve = { code: 'Q_NEUF', libelle: 'La signalisation est-elle claire ?', type: 'choix', options: ['Oui', 'Non'] };
        colEnq.update(enqSat().id, { questions: avantQ.concat([neuve]) });
        bouton(root, 'Recueillir').click(); await dormir(60);
        const ouverture2 = { libelles: libellesChamps(), champs: champsOuverts() };
        const nAvant = colRep.all().length;
        poser('_canal', 'À la sortie'); poser('Q_ACCUEIL', '5'); poser('Q_ATTENTE', '3'); poser('Q_PROPRETE', '4'); poser('Q_SOINS', '4');
        poser('Q_RECO', 'Plutôt oui'); poser('Q_LIBRE', 'Mieux indiquer la salle'); poser('Q_NEUF', 'Oui');
        dernierBouton('Enregistrer la réponse').click(); await dormir(80);
        const nee = colRep.all()[0];
        cas.push({ nom: 'Recueillir : le formulaire naît du modèle', questions: avantQ, questionsApres: avantQ.concat([neuve]), ouverture1, ouverture2,
          ajoutees: colRep.all().length - nAvant, reponse: net(nee), toastsApres: toasts() });
        nettoyer();
        colEnq.update(enqSat().id, { questions: avantQ });
        colRep.all().splice(0, 1);

        // Les trois types de question → champs engendrés.
        const modele = colEnq.insert({ reference: 'ENQ-T', titre: 'Modèle de test', description: '', aValider: false, creeLe: '2026-08-16',
          questions: [{ code: 'N1', libelle: 'Note A', type: 'note' }, { code: 'C1', libelle: 'Choix B', type: 'choix', options: ['x', 'y z'] }, { code: 'T1', libelle: 'Texte C', type: 'texte' }] }).record;
        root.remove(); root = await monter('adm-enquetes');
        const ligneT = [...root.querySelectorAll('tbody tr')].find((tr) => tr.textContent.includes('Modèle de test'));
        bouton(ligneT, 'Recueillir').click(); await dormir(60);
        cas.push({ nom: 'les trois types de question', modele: net(modele), libelles: libellesChamps(), champs: champsOuverts() });
        nettoyer();
        colEnq.archive(modele.id);

        // Nouveau modèle : sans question → refus ; question à choix sans choix → refus ; puis création.
        bouton(root, 'Nouveau modèle').click(); await dormir(60);
        const nM = colEnq.all().length;
        poser('titre', 'Accueil des visiteurs'); poser('description', 'Test');
        dernierBouton('Créer le modèle').click(); await dormir(60);
        const refusSansQuestion = { toasts: toasts(), ajoutes: colEnq.all().length - nM };
        nettoyer(); bouton(root, 'Nouveau modèle').click(); await dormir(60);
        poser('titre', 'Accueil des visiteurs'); poser('description', 'Test');
        bouton(document, 'Ajouter une question').click(); await dormir(60);
        poser('libelle', 'Quel service ?'); poser('type', 'choix'); poser('optionsTexte', '');
        dernierBouton('Ajouter').click(); await dormir(60);
        const refusChoix = { toasts: toasts() };
        poser('optionsTexte', 'Accueil | Caisse |  | Labo');
        dernierBouton('Ajouter').click(); await dormir(60);
        dernierBouton('Créer le modèle').click(); await dormir(80);
        const cree = colEnq.all().find((x) => x.titre === 'Accueil des visiteurs');
        cas.push({ nom: 'Nouveau modèle', refusSansQuestion, refusChoix,
          cree: Object.assign(net(cree), { reference: '…', questions: cree.questions.map((q) => Object.assign({}, q, { code: '…' })) }), toastsApres: toasts() });
        nettoyer(); colEnq.archive(cree.id);

        // Partage : un jeton daté et révocable, jamais l'identifiant de l'enquête.
        root.remove(); root = await monter('adm-enquetes');
        bouton(root, 'Partager à un tiers').click(); await dormir(60);
        const formPartage = { libelles: libellesChamps(), champs: champsOuverts() };
        poser('anonyme', 'oui'); poser('usage', 'tablette'); poser('expireLe', '2026-09-15'); poser('note', 'Salle d’attente');
        dernierBouton('Ouvrir le lien').click(); await dormir(100);
        const jet = colJet.all()[0];
        const tiroir = document.querySelector('[role=dialog]');
        const champLien = tiroir && tiroir.querySelector('input[readonly]');
        const lien = champLien ? champLien.value : null;
        cas.push({ nom: 'Partager à un tiers', formPartage, jeton: Object.assign(net(jet), { jeton: '…' }), formatJeton: /^[a-km-z2-9]{24}$/.test(jet.jeton),
          lienGabarit: lien && lien.replace(jet.jeton, '<jeton>'), lienSansIdEnquete: lien ? !lien.includes('ENQ0001') : null,
          tiroir: tiroir ? norm(tiroir.textContent).replace(jet.jeton, '<jeton>') : null, qrPresent: !!(tiroir && tiroir.querySelector('svg')) });
        nettoyer();
        root.remove(); root = await monter('adm-enquetes');
        root.querySelectorAll('[role=tab]')[1].click(); await dormir(80);
        const avantRevocation = { kpis: kpis(root), entetes: entetes(root), lignes: lignesTable(root).map((l) => l.map((c) => c.replace(jet.jeton.slice(0, 8), '<8 premiers>'))) };
        bouton(root, 'Révoquer le lien').click(); await dormir(60);
        dernierBouton('Révoquer').click(); await dormir(80);
        const kpisApres = kpis(root), ongletApres = [...root.querySelectorAll('[role=tab]')].map((t) => t.getAttribute('aria-selected'));
        root.querySelectorAll('[role=tab]')[1].click(); await dormir(80);
        const apresRevocation = { kpis: kpisApres, ongletApres, lignes: lignesTable(root).map((l) => l.map((c) => c.replace(jet.jeton.slice(0, 8), '<8 premiers>'))), toasts: toasts(),
          revoqueLe: colJet.all()[0].revoqueLe, revoquePar: !!colJet.all()[0].revoquePar, boutonRevoquer: !!bouton(root, 'Révoquer le lien'), reponsesConservees: colRep.all().length };
        cas.push({ nom: 'Révoquer ferme la porte sans rien effacer', avantRevocation, apresRevocation });
        nettoyer(); root.remove();
        sortieG.enquetes = cas;
        colJet.all().splice(0);
        colEnq.update(enqSat().id, { questions: questionsOrigine });
      }

      /* ===================================================================================== PAGE PUBLIQUE */
      {
        const cas = [];
        const aujourdhui = '2026-08-16';
        colJet.all().splice(0);
        const enq = enqSat();
        const jeton = (code, extra) => colJet.all().push(Object.assign({ id: 'J-' + code, statut: 'actif', jeton: code, enqueteId: enq.id, enqueteTitre: enq.titre, anonyme: true, usage: 'salle', creeLe: '2026-08-01', expireLe: '2026-09-30', revoqueLe: null }, extra || {}));
        jeton('ouvertanonyme2222222222222', {});
        jeton('ouvertnominatif33333333333', { anonyme: false });
        jeton('echeancememe444444444444444', { expireLe: '2026-08-16' });
        jeton('echu5555555555555555555555', { expireLe: '2026-08-15' });
        jeton('revoque666666666666666666666', { revoqueLe: '2026-08-10' });
        jeton('archive7777777777777777777', { statut: 'archive' });
        jeton('sansfin8888888888888888888', { expireLe: null });
        jeton('orphelin999999999999999999', { enqueteId: 'ENQ-INCONNUE' });
        const ouvrir = async (query) => {
          history.replaceState(null, '', location.pathname + query);
          return await monter('enquete-publique');
        };
        const lirePage = (root) => ({ texte: norm(root.textContent), titres: [...root.querySelectorAll('h1')].map((h) => norm(h.textContent)), libelles: [...root.querySelectorAll('label')].map((l) => norm(l.textContent)),
          champs: [...root.querySelectorAll('[id^=f_]')].map((e) => ({ nom: e.id.slice(2), balise: e.tagName.toLowerCase(), options: e.tagName === 'SELECT' ? [...e.options].map((o) => o.value).filter(Boolean) : null })),
          liens: root.querySelectorAll('a').length, boutons: [...root.querySelectorAll('button')].map((b) => norm(b.textContent)).filter(Boolean), menus: root.querySelectorAll('nav, #app-menubar, #app-topbar, [role=navigation]').length });
        const etats = [];
        for (const [nom, code] of [['jeton ouvert, recueil anonyme', 'ouvertanonyme2222222222222'], ['jeton ouvert, recueil nominatif', 'ouvertnominatif33333333333'], ['expire aujourd’hui : encore ouvert', 'echeancememe444444444444444'],
          ['jeton sans date d’expiration', 'sansfin8888888888888888888'], ['expiré hier', 'echu5555555555555555555555'], ['révoqué', 'revoque666666666666666666666'], ['archivé', 'archive7777777777777777777'],
          ['inconnu', 'nexistepas'], ['adresse sans jeton', null], ['jeton valide mais enquête introuvable', 'orphelin999999999999999999']]) {
          const root = await ouvrir(code === null ? '' : '?jeton=' + code);
          const j = colJet.all().find((x) => x.jeton === code);
          etats.push(Object.assign({ nom, code, jeton: j ? net(j) : null }, lirePage(root)));
          root.remove();
        }
        cas.push({ nom: 'ce que la page montre, selon l’état du jeton', aujourdhui, enquete: propre(enq), etats });

        // Envoyer une réponse — anonyme, nominative, formulaire en erreur.
        const envois = [];
        for (const [nom, code, valeurs, nomRepondant] of [
          ['anonyme', 'ouvertanonyme2222222222222', { Q_ACCUEIL: '5', Q_ATTENTE: '2', Q_PROPRETE: '4', Q_SOINS: '3', Q_RECO: 'Plutôt non', Q_LIBRE: 'Trop long' }, null],
          ['nominatif', 'ouvertnominatif33333333333', { Q_ACCUEIL: '4', Q_ATTENTE: '4', Q_PROPRETE: '4', Q_SOINS: '4', Q_RECO: 'Oui, sans hésiter', Q_LIBRE: '' }, 'KOUASSI Awa'],
          ['nominatif sans nom', 'ouvertnominatif33333333333', { Q_ACCUEIL: '4' }, '']]) {
          const root = await ouvrir('?jeton=' + code);
          const n0 = colRep.all().length;
          Object.entries(valeurs).forEach(([k, v]) => poser(k, v));
          if (nomRepondant !== null && document.getElementById('f__repondant')) poser('_repondant', nomRepondant);
          bouton(root, 'Envoyer ma réponse').click(); await dormir(100);
          const nee = colRep.all().length > n0 ? colRep.all()[0] : null;
          const j = colJet.all().find((x) => x.jeton === code);
          envois.push({ nom, code, valeurs, nomRepondant, ajoutees: colRep.all().length - n0, reponse: nee ? Object.assign(net(nee), { jetonId: nee.jetonId === j.id ? '<id du lien>' : nee.jetonId }) : null,
            toasts: toasts(), texte: norm(root.textContent), apres: norm(root.textContent).includes('Merci') });
          nettoyer(); root.remove();
        }
        cas.push({ nom: 'envoyer une réponse', envois });
        // Après révocation, la porte se ferme avec LA MÊME réponse que pour un jeton inconnu.
        colJet.update('J-ouvertanonyme2222222222222', { revoqueLe: '2026-08-16' });
        const rev = await ouvrir('?jeton=ouvertanonyme2222222222222'); const texteRev = norm(rev.textContent); rev.remove();
        const inc = await ouvrir('?jeton=inconnu'); const texteInc = norm(inc.textContent); inc.remove();
        cas.push({ nom: 'révoqué = inconnu', memeReponse: texteRev === texteInc });
        history.replaceState(null, '', location.pathname);
        sortieG.publique = cas;
        colJet.all().splice(0);
        remplacer(colRep, repsOrigine);
      }

      /* ===================================================================================== VALIDATIONS */
      {
        // Comme un poste qui a ouvert le parc technique et les achats : les files « besoins » et « matériel » sont alors amorcées.
        try { SIGH.semerAchats(true); } catch (e) { window.__erreurAchats = String(e); }
        const rm = await monter('m13-maintenance'); rm.remove();
        const noms = ['demandesAnalyses', 'ecritures', 'besoins', 'commandes', 'factures', 'resultatsImagerie', 'echeancesFiscales', 'materiel', 'plagesReactif'];
        const projeter = () => ({
          demandesAnalyses: compter(S.collection('demandesAnalyses').all(), ['statut', 'etatAnalyse']),
          ecritures: compter(S.collection('ecritures').all(), ['statut']),
          besoins: compter(S.collection('besoins').all(), ['statut', 'etape']),
          commandes: compter(S.collection('commandes').all(), ['statut', 'statutCommande']),
          factures: compter(S.collection('factures').all().map((f) => ({ statut: f.statut, statutMecef: f.statutMecef, numeroMecef: f.numeroMecef ? 'oui' : '' })), ['statut', 'statutMecef', 'numeroMecef']),
          resultatsImagerie: compter(S.collection('resultatsImagerie').all(), ['statut']),
          echeancesFiscales: compter(S.collection('echeancesFiscales').all(), ['statut', 'paye', 'echeance']),
          materiel: compter(S.collection('materiel').all(), ['statut', 'aCompleter']),
          plagesReactif: compter(S.collection('plagesReactif').all(), ['statut']),
        });
        const lire = async (nom) => {
          const entrees = projeter();
          const root = await monter('adm-validations');
          const blocs = [...root.querySelectorAll('.card')].filter((c) => c.querySelector(':scope > .card-head'));
          const titre = (c) => norm(c.querySelector('.card-title').textContent);
          const files = [...root.querySelectorAll('.grid .card')].map((c) => ({ textes: [...c.querySelectorAll('p')].map((p) => norm(p.textContent)), compte: norm((c.querySelector('span.text-lg') || {}).textContent), bouton: norm((c.querySelector('button') || {}).textContent) }));
          const bloc = (debut) => blocs.find((c) => titre(c).startsWith(debut));
          const lignesBloc = (c) => c ? [...c.querySelectorAll('.card-body > div > div')].map((d) => [...d.querySelectorAll('p')].map((p) => norm(p.textContent))) : [];
          const r = {
            nom, entrees, kpis: kpis(root), titres: blocs.map(titre), files,
            professionnels: lignesBloc(bloc('Référentiels en attente')), arbitrages: lignesBloc(bloc('En attente d’un ARBITRAGE')),
            validees: lignesTable(bloc('Validées par la DIRECTION')),
            boutons: [...root.querySelectorAll('button')].map((b) => norm(b.textContent)),
          };
          root.remove();
          return r;
        };
        const cas = [];
        cas.push(await lire('jeu de démonstration'));
        const sauve = {}; noms.forEach((n) => { sauve[n] = propre(S.collection(n).all()); });
        S.collection('besoins').all().splice(0); S.collection('commandes').all().splice(0);
        cas.push(await lire('besoins et commandes non amorcés : « — » et non 0'));
        remplacer(S.collection('besoins'), sauve.besoins); remplacer(S.collection('commandes'), sauve.commandes);
        const ajout = (nom, f) => S.collection(nom).all().push(Object.assign({ id: 'AJ-' + nom + Math.random().toString(36).slice(2, 7), statut: 'actif' }, f));
        ajout('demandesAnalyses', { etatAnalyse: 'valide_technique' }); ajout('demandesAnalyses', { etatAnalyse: 'valide_technique' });
        ajout('demandesAnalyses', { statut: 'archive', etatAnalyse: 'valide_technique' });
        ajout('ecritures', { statut: 'brouillon' }); ajout('ecritures', { statut: 'brouillon' }); ajout('ecritures', { statut: 'brouillon' });
        ajout('besoins', { etape: 'validation_da' }); ajout('besoins', { etape: 'brouillon' }); ajout('besoins', { etape: 'soumis', statut: 'archive' });
        ajout('commandes', { statutCommande: 'attente_validation' });
        ajout('factures', { statutMecef: 'en_attente', numeroMecef: 'MC-1' }); ajout('factures', { statutMecef: 'en_attente', numeroMecef: '' }); ajout('factures', { statutMecef: 'valide', numeroMecef: 'MC-2' });
        ajout('resultatsImagerie', { statut: 'brouillon' }); ajout('resultatsImagerie', { statut: 'rendu' });
        ajout('echeancesFiscales', { paye: false, echeance: '2026-08-15' }); ajout('echeancesFiscales', { paye: false, echeance: '2026-08-16' }); ajout('echeancesFiscales', { paye: true, echeance: '2026-08-01' });
        ajout('materiel', { aCompleter: true }); ajout('plagesReactif', { variable: 'X' }); ajout('plagesReactif', { variable: 'Y', statut: 'archive' });
        cas.push(await lire('gestes en plus : chaque file bouge de ce qu’on y pose'));
        noms.forEach((n) => remplacer(S.collection(n), sauve[n]));
        sortieG.validations = cas;
      }

      /* ===================================================================================== GED */
      {
        const colDoc = S.collection('documents', { module: 'GED' });
        const docsOrigine = propre(colDoc.all());
        const projDoc = (d) => { const c = Object.assign({}, d); delete c.id; return propre(c); };
        const cas = {};
        const etatsPris = () => { const e = window.__etats; window.__etats = []; return e; };
        const bib = async (nom) => {
          const entrees = colDoc.all().map(projDoc);
          const root = await monter('ged-bibliotheque');
          const explor = carteNommee(root, 'Explorateur');
          const r = { nom, nbEntrees: entrees.length, kpis: kpis(root), explorateur: [...explor.querySelectorAll('.rounded-xl')].map((c) => ({ titre: norm(c.querySelector('span.font-semibold').textContent), total: norm(c.querySelector('p.text-2xl').textContent), details: [...c.querySelectorAll('li')].map((li) => [...li.children].map((x) => norm(x.textContent))) })),
            entetes: entetes(root), lignes: lignesTable(root, 20) };
          return { r, root, entrees };
        };
        {
          const { r, root, entrees } = await bib('jeu de démonstration');
          r.entrees = entrees;
          const premiere = root.querySelector('tbody tr');
          const ref = norm(premiere.children[0].textContent);
          premiere.click(); await dormir(100);
          const tir = document.querySelector('[role=dialog]');
          r.tiroir = { reference: ref, texte: norm(tir.textContent), historique: [...tir.querySelectorAll('li')].map((li) => norm(li.textContent)) };
          nettoyer();
          bouton(premiere, 'Imprimer la fiche').click(); await dormir(60);
          r.fiche = etatsPris();
          cas.bibliotheque = [r];
          root.remove();
          const mk = (i, f) => Object.assign({ id: 'T' + i, statut: 'actif', reference: 'DOC-T-' + i, categorie: 'courrier', rattachement: 'Administration', rattacheA: 'Administration générale', codeRattachement: 'ADM', libelle: 'Courrier ' + i, date: '2026-08-01', taille: 512, format: 'PDF', version: 1, etatValidation: 'valide', signe: false, archive: false, deposePar: 'AGOSSOU Yahouza', consultations: 2, conservation: 5 }, f);
          const jeuBords = [mk(1, { signe: true, taille: 1000, consultations: 10 }), mk(2, { etatValidation: 'rejete', archive: true, categorie: 'contrat', rattachement: 'Employé', rattacheA: 'DOSSOU Salifou', codeRattachement: 'MAT-12', conservation: 10 }), mk(3, { etatValidation: 'en_attente', categorie: 'ordonnance', rattachement: 'Patient', rattacheA: 'BAKO Boukari', codeRattachement: 'CNT/2/26', conservation: 20, taille: 2048 }), mk(4, { etatValidation: 'en_attente', date: '2005-01-01', conservation: 5, archive: true }), mk(5, { categorie: 'cloture_exercice', date: '2026-08-16', conservation: 10 })];
          remplacer(colDoc, jeuBords);
          const b2 = await bib('jeu de bords (5 documents)'); b2.r.entrees = b2.entrees; cas.bibliotheque.push(b2.r); b2.root.remove();
          remplacer(colDoc, docsOrigine);
        }
        {
          const wf = async (nom) => {
            const entrees = colDoc.all().map(projDoc);
            const root = await monter('ged-workflow');
            const circuit = carteNommee(root, 'Circuit de validation');
            return { r: { nom, entrees, kpis: kpis(root), circuit: [...circuit.querySelectorAll('span.inline-flex')].map((s) => norm(s.textContent)), entetes: entetes(root), lignes: lignesTable(root, 15), texte: norm(root.textContent) }, root };
          };
          const { r, root } = await wf('jeu de démonstration');
          cas.workflow = [r];
          const ligne1 = root.querySelector('tbody tr');
          const ref1 = norm(ligne1.children[1].textContent);
          const doc1 = colDoc.all().find((d) => d.reference === ref1);
          bouton(ligne1, 'Valider').click(); await dormir(80);
          cas.workflow.push({ nom: 'valider un document', reference: ref1, apres: { etatValidation: doc1.etatValidation, signe: doc1.signe }, toasts: toasts(), kpis: kpis(root) });
          nettoyer();
          const ligne2 = root.querySelector('tbody tr'); const ref2 = norm(ligne2.children[1].textContent); const doc2 = colDoc.all().find((d) => d.reference === ref2);
          bouton(ligne2, 'Rejeter').click(); await dormir(60);
          const dlg = document.querySelector('[role=dialog]');
          const ouvertRejet = { texte: norm(dlg.textContent), zoneMotif: !!dlg.querySelector('textarea') };
          dlg.querySelector('textarea').value = 'Pièce illisible'; dlg.querySelector('textarea').dispatchEvent(new Event('input'));
          dernierBouton('Rejeter').click(); await dormir(80);
          cas.workflow.push({ nom: 'rejeter avec motif', reference: ref2, ouvertRejet, apres: { etatValidation: doc2.etatValidation, motifRejet: doc2.motifRejet === undefined ? null : doc2.motifRejet, signe: doc2.signe === undefined ? null : doc2.signe }, toasts: toasts(), kpis: kpis(root) });
          nettoyer();
          const ligne3 = root.querySelector('tbody tr'); const ref3 = norm(ligne3.children[1].textContent); const doc3 = colDoc.all().find((d) => d.reference === ref3);
          bouton(ligne3, 'Rejeter').click(); await dormir(60);
          dernierBouton('Rejeter').click(); await dormir(80);
          cas.workflow.push({ nom: 'rejeter sans motif', reference: ref3, apres: { etatValidation: doc3.etatValidation, motifRejet: doc3.motifRejet === undefined ? null : doc3.motifRejet }, modalesRestees: document.querySelectorAll('[role=dialog]').length, toasts: toasts() });
          nettoyer();
          const trs = [...root.querySelectorAll('tbody tr')].slice(0, 2);
          const refs = trs.map((tr) => norm(tr.children[1].textContent));
          const docs = refs.map((rf) => colDoc.all().find((d) => d.reference === rf));
          const avant = docs.map((d) => ({ etatValidation: d.etatValidation, signe: !!d.signe }));
          trs.forEach((tr) => { const cb = tr.querySelector('input[type=checkbox]'); cb.checked = true; cb.dispatchEvent(new Event('change')); });
          await dormir(60);
          const barre = norm(root.textContent).includes('Valider la sélection');
          bouton(document, 'Valider la sélection').click(); await dormir(80);
          cas.workflow.push({ nom: 'valider la sélection', refs, avant, apres: docs.map((d) => ({ etatValidation: d.etatValidation, signe: !!d.signe })), barre, toasts: toasts() });
          nettoyer(); root.remove();
          remplacer(colDoc, docsOrigine);
          colDoc.all().forEach((d) => { d.etatValidation = 'valide'; });
          const w2 = await wf('aucun document en attente'); w2.r.entrees = null; cas.workflow.push(w2.r); w2.root.remove();
          remplacer(colDoc, docsOrigine);
          const mkw = (i, date) => ({ id: 'W' + i, statut: 'actif', reference: 'DOC-W-' + i, categorie: 'bulletin', rattachement: 'Employé', rattacheA: 'X', codeRattachement: 'M', libelle: 'Bulletin ' + i, date, taille: 10, format: 'PDF', version: 1, etatValidation: 'en_attente', signe: false, archive: false, deposePar: 'Y', consultations: 0, conservation: 10 });
          remplacer(colDoc, [mkw(1, '2026-08-16'), mkw(2, '2026-08-15'), mkw(3, '2026-08-01'), mkw(4, '2026-07-31')]);
          const w3 = await wf('ancienneté'); w3.r.rouges = [...w3.root.querySelectorAll('tbody td span.text-danger-600')].map((s) => norm(s.textContent)); cas.workflow.push(w3.r); w3.root.remove();
          remplacer(colDoc, docsOrigine);
        }
        {
          const ar = async (nom) => {
            const entrees = colDoc.all().map(projDoc);
            const root = await monter('ged-archives');
            const noteEchus = [...root.querySelectorAll('div')].filter((n) => /ont atteint leur durée légale/.test(n.textContent) && !n.querySelector('div')).map((n) => norm(n.textContent))[0] || null;
            const r = { nom, entrees, kpis: kpis(root), anneau: graphique(carteNommee(root, 'Répartition par durée')), barres: graphique(carteNommee(root, 'Volume documentaire')), entetes: entetes(root), lignes: lignesTable(root, 20), noteEchus };
            return { r, root };
          };
          const a1 = await ar('jeu de démonstration');
          cas.archives = [a1.r];
          bouton(a1.root, 'Éditer le bordereau d’archivage').click(); await dormir(60);
          a1.r.bordereau = etatsPris().map((e) => Object.assign(e, { tableaux: e.tableaux.map((t) => ({ entetes: t.entetes, nbLignes: t.lignes.length, premieres: t.lignes.slice(0, 5), pied: t.pied })) }));
          const tr0 = a1.root.querySelector('tbody tr'); const ref0 = norm(tr0.children[0].textContent); const doc0 = colDoc.all().find((d) => d.reference === ref0);
          bouton(tr0, 'Modifier').click(); await dormir(60);
          const modif = { libelles: libellesChamps(), champs: champsOuverts(), valeursInitiales: [...document.querySelectorAll('[role=dialog] [id^=f_]')].map((e) => [e.id.slice(2), e.value]) };
          const copie = net(doc0);
          poser('titre', 'Titre de test'); poser('categorie', 'contrat'); poser('dureeConservation', '12'); poser('emplacement', 'Armoire B2'); poser('observations', 'À revoir');
          dernierBouton('Enregistrer').click(); await dormir(80);
          modif.reference = ref0; modif.ecrit = net(doc0); modif.avant = copie; modif.toasts = toasts(); modif.cellulesApres = lignesTable(a1.root, 1)[0];
          cas.archives.push({ nom: 'modifier un document', modif });
          nettoyer();
          const tr1 = a1.root.querySelector('tbody tr'); const ref1 = norm(tr1.children[0].textContent); const doc1 = colDoc.all().find((d) => d.reference === ref1);
          bouton(tr1, 'Archiver').click(); await dormir(60);
          const dlgA = document.querySelector('[role=dialog]');
          const zone = dlgA.querySelector('textarea'); if (zone) { zone.value = 'Doublon'; zone.dispatchEvent(new Event('input')); }
          dernierBouton('Archiver').click(); await dormir(80);
          cas.archives.push({ nom: 'archiver un document', reference: ref1, statut: doc1.statut, motif: doc1.motifArchivage === undefined ? null : doc1.motifArchivage, toasts: toasts(), compteApres: lignesTable(a1.root).length });
          nettoyer(); a1.root.remove();
          remplacer(colDoc, docsOrigine);
          const mk = (i, f) => Object.assign({ id: 'A' + i, statut: 'actif', reference: 'DOC-A-' + i, categorie: 'courrier', rattachement: 'Administration', rattacheA: 'ADM', codeRattachement: 'ADM', libelle: 'Courrier ' + i, date: '2026-08-01', taille: 512, format: 'PDF', version: 1, etatValidation: 'valide', signe: false, archive: false, deposePar: 'Z', consultations: 0, conservation: 5 }, f);
          remplacer(colDoc, [mk(1, { date: '2021-08-16', conservation: 5 }), mk(2, { date: '2021-08-17', conservation: 5 }), mk(3, { date: '2021-08-15', conservation: 5 }), mk(4, { date: '2006-08-16', conservation: 20, archive: true }), mk(5, { date: '2016-08-16', conservation: 10, categorie: 'contrat', rattachement: 'Employé' }), mk(6, { date: '2026-08-16', conservation: 10, categorie: 'ordonnance', rattachement: 'Patient', taille: 3000 })]);
          const a2 = await ar('bords de l’échéance : le jour même et la veille'); cas.archives.push(a2.r); a2.root.remove();
          colDoc.all().splice(0);
          const a3 = await ar('aucun document'); cas.archives.push(a3.r); a3.root.remove();
          remplacer(colDoc, docsOrigine);
        }
        sortieG.ged = cas;
      }
      return sortieG;
    });
    ecrire('packages/domaine/test/vecteurs/qualite.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-qualite.js — les écrans adm-enquetes, adm-satisfaction, adm-validations, enquete-publique, ged-bibliotheque, ged-workflow et ged-archives pilotés dans Chrome, horloge figée au 16/08/2026 10 h. Ne pas éditer.' }, sortie));
    if (m.erreurs.length) console.log('Erreurs de page :', m.erreurs.slice(0, 5));
    for (const [k, v] of Object.entries(sortie)) if (Array.isArray(v)) console.log('  ' + k + ' : ' + v.length + ' cas');
    for (const [k, v] of Object.entries(sortie.ged || {})) console.log('  ged.' + k + ' : ' + v.length + ' cas');
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
