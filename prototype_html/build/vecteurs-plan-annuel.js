/* =============================================================================
 * VECTEURS DU PLAN ANNUEL DE TRAVAIL (lot PTA, 16/11/2026 ; Direction : « rien ne doit rester en dur »)
 * -----------------------------------------------------------------------------
 * La maquette est PILOTÉE sur son écran réel `m13-plan-annuel` (monté dans Chrome à l'horloge figée du 30/10/2026) : une action est créée PAR LA MODALE de l'écran, les chiffres
 * (indicateurs, totaux, bilan imprimé, signataires imprimés) sont lus tels que l'écran les peint ; puis les règles du socle (`D.PLAN`) et le moteur (`SIGH.planAnnuel` : contrôle,
 * adoption, version datée, reconduction, alertes) sont relevés dans la MÊME page. Le domaine Dart (`packages/domaine/lib/src/administration/plan_annuel.dart`) rejoue ces vecteurs.
 *   node build/vecteurs-plan-annuel.js   →   packages/domaine/test/vecteurs/plan_annuel.json
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs du plan annuel de travail');
  const m = await ouvrirMaquette();
  try {
    await m.page.evaluate(() => {
      const Vrai = Date;
      window.__FIXE = new Vrai(2026, 9, 30, 10, 0, 0).getTime();
      class Faux extends Vrai { constructor(...a) { if (a.length === 0) super(window.__FIXE); else super(...a); } static now() { return window.__FIXE; } }
      window.Date = Faux;
      SIGH.core.aujourdhui = () => new Faux();
      window.__etats = [];
      const setTimeoutReel = window.setTimeout.bind(window);
      window.setTimeout = (fn, ms, ...a) => (String(fn).includes('location.reload') ? 0 : setTimeoutReel(fn, ms, ...a));
      SIGH.ui.sonner = () => {};
      SIGH.ui.alerter = () => ({ close() {} });
      SIGH.print.etat = function (o) {
        const tab = [], c = o.contenu;
        if (c && c.querySelectorAll) {
          c.querySelectorAll('table').forEach((t) => tab.push({
            entetes: [...t.querySelectorAll('thead th')].map((x) => x.innerText.replace(/\s+/g, ' ').trim()),
            lignes: [...t.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => td.innerText.replace(/\s+/g, ' ').trim())),
            pied: [...t.querySelectorAll('tfoot tr')].map((tr) => [...tr.children].map((td) => td.innerText.replace(/\s+/g, ' ').trim())),
          }));
        }
        window.__etats.push(JSON.parse(JSON.stringify({ titre: o.titre, sousTitre: o.sousTitre || null, cartouche: o.cartouche || null, signatures: o.signatures || null, tableaux: tab,
          texte: c && c.innerText ? c.innerText.replace(/\s+/g, ' ').trim() : null })));
      };
    });
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m13-administration.js') });
    await m.page.evaluate(() => {
      const norm = (t) => String(t == null ? '' : t).replace(/[\n\t\r]+/g, ' ').replace(/\s+/g, ' ').trim();
      window.H = {
        norm, propre: (x) => JSON.parse(JSON.stringify(x === undefined ? null : x)),
        dormir: (ms) => new Promise((r) => setTimeout(r, ms)),
        net: (x) => { const c = Object.assign({}, x); ['_creePar', '_creeLe', '_modifiePar', '_modifieLe', '_archivePar', '_archiveLe', '_motifArchivage', 'id'].forEach((k) => delete c[k]); return JSON.parse(JSON.stringify(c)); },
        kpis: (root) => [...root.querySelectorAll('.kpi')].map((k) => { const p = k.querySelectorAll('p'); return { libelle: norm(p[0].innerText), valeur: norm(p[1].innerText), indice: p[2] ? norm(p[2].innerText) : null }; }),
        tableaux: (root) => [...root.querySelectorAll('table')].map((t) => ({ entetes: [...t.querySelectorAll('thead th')].map((x) => norm(x.innerText)).filter((s) => s !== ''),
          lignes: [...t.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => norm(td.innerText)).filter((s, i) => i > 0 || s !== '')) })),
        boutons: (racine) => [...racine.querySelectorAll('button')].map((b) => norm(b.textContent || b.getAttribute('aria-label') || b.title)).filter(Boolean),
        bouton: (racine, texte) => [...racine.querySelectorAll('button')].find((b) => b.textContent.trim() === texte || b.getAttribute('aria-label') === texte || b.title === texte),
        poser: (id, v) => { const e = document.getElementById('f_' + id); if (!e) throw new Error('champ ' + id); if (e.type === 'checkbox') { e.checked = !!v; } else { e.value = v; } e.dispatchEvent(new Event('input')); e.dispatchEvent(new Event('change')); },
        champs: () => [...document.querySelectorAll('[role=dialog] label, .modal-root label')].map((l) => norm(l.innerText)),
        cliquer: (texte) => { const bs = [...document.querySelectorAll('button')].filter((b) => b.textContent.trim() === texte); bs[bs.length - 1].click(); },
        toasts: () => [...document.querySelectorAll('#toast-host > div')].map((n) => [...n.querySelectorAll('p')].map((p) => p.textContent.trim())),
        viderToasts: () => { const h = document.getElementById('toast-host'); if (h) h.innerHTML = ''; },
        fermerTout: () => document.querySelectorAll('[role=dialog], .modal-root, .drawer-root, .drawer-backdrop').forEach((x) => x.remove()),
        monter: async (id) => { const root = document.createElement('div'); document.body.appendChild(root); window.__etats.length = 0; SIGH.screens[id].render(root); await new Promise((r) => setTimeout(r, 300)); return root; },
        retirer: (root) => { root.remove(); H.fermerTout(); },
        ligne: (racine, texte) => [...racine.querySelectorAll('tbody tr')].find((tr) => tr.innerText.includes(texte)),
        icone: (ligne, nom) => [...ligne.querySelectorAll('button')].find((b) => (b.getAttribute('aria-label') || b.title) === nom),
      };
    });

    const sortie = { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-plan-annuel.js, ne pas éditer. Horloge : 30/10/2026 10 h.' };
    sortie.maquette = await m.page.evaluate(async () => {
      const S = SIGH.store, D = SIGH.data, C = SIGH.core, N = SIGH.nav, PA = SIGH.planAnnuel, propre = H.propre;
      const out = {};
      const col = S.collection('planAnnuel');
      col.all().splice(0);
      /* L'exercice suivant s'ouvre à partir du mois réglé du circuit de clôture (décembre) : à la date des vecteurs il n'existe pas encore ; on pose sa fiche comme la tâche d'ouverture le ferait. */
      if (!SIGH.exercice.liste().some((x) => x.annee === 2027)) S.collection('exercices').all().unshift({ id: 'EXO-2027', annee: 2027, debut: '2027-01-01', fin: '2027-12-31', statut: 'actif', etat: 'ouvert', source: 'journal' });
      /* Une ligne du module Budgets pour l'exercice 2026 (le registre se sème à son écran) : le plan s'y rattache. */
      if (!S.collection('budgets').active().some((b) => b.exercice === 2026)) S.collection('budgets').all().push({ id: 'BUDPTA1', statut: 'actif', reference: 'BG-2026-001', exercice: 2026, centreCout: 'CC-LAB', centre: 'Laboratoire', nature: 'Charges de fonctionnement', prevu: 1000000 });
      S.collection('adoptionsPlan').all().splice(0);
      const rolePose = (role) => { const s = S.session() || {}; S.setSession && S.setSession(Object.assign({}, s, { role })); };
      /* le contexte : exercices, axes, états, personnel, postes, signataires semés */
      const exos = PA.exercices();
      const ag = S.collection('personnel').active()[0], po = S.collection('postes').active().filter((p) => p.role === 'comptable')[0];
      const bud = S.collection('budgets').active().filter((b) => b.exercice === 2026)[0];
      out.contexte = { exercices: exos.map((x) => ({ annee: x.annee, debut: x.debut, fin: x.fin, etat: x.etat })), axes: D.PLAN.referentiel('axe').map((x) => ({ code: x.code, libelle: x.libelle })),
        etats: D.PLAN.referentiel('etat').map((x) => ({ code: x.code, libelle: x.libelle, nature: x.nature, ton: x.ton })), agent: ag ? { id: ag.id, nomComplet: ag.nomComplet, poste: ag.poste } : null,
        poste: po ? { id: po.id, poste: po.poste, titulaire: po.titulaire } : null, budget: bud ? { id: bud.id, reference: bud.reference } : null,
        signataires: propre(PA.signataires('2026-10-30').signataires), graceDefaut: D.parametreCliniqueALaDate('plan.graceRetardJours', '2026-10-30').valeur };

      /* 1. L'ÉCRAN RÉEL : création PAR LA MODALE (champs, valeurs, refus affichés), tableau et indicateurs lus */
      const racine = await H.monter('m13-plan-annuel');
      out.ecranVide = { kpis: H.kpis(racine), boutons: H.boutons(racine).slice(0, 12), selecteur: [...racine.querySelectorAll('#plan-exercice option')].map((o) => o.value) };
      H.bouton(racine, 'Nouvelle action').click(); await H.dormir(300);
      out.modaleCreation = { champs: H.champs() };
      H.poser('action', 'Campagne de vaccination'); H.poser('axe', 'sante_publique'); H.poser('responsable', 'poste:' + po.id); H.poser('trimestreDebut', '1'); H.poser('trimestreFin', '2');
      H.poser('budgetPrevu', '1000000'); H.poser('indicateur', 'Enfants vaccinés'); H.poser('cible', '200');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(400);
      out.creeParEcran = { fiche: H.net(col.all()[0]), toasts: H.toasts() };
      H.bouton(racine, 'Nouvelle action').click(); await H.dormir(300);
      H.poser('action', 'Formation des infirmiers'); H.poser('axe', 'formation'); H.poser('responsable', 'agent:' + ag.id); H.poser('trimestreDebut', '3'); H.poser('trimestreFin', '3');
      H.poser('tauxAvancement', '150'); H.viderToasts(); H.cliquer('Créer'); await H.dormir(400);
      out.refusParEcran = { toasts: H.toasts(), nb: col.active().length };
      H.fermerTout();

      /* 2. les actions de référence, créées par le moteur (même chemin que la modale) */
      const mk = (action, axe, d, f, av, extra) => PA.ajouter(Object.assign({ exercice: 2026, action, axe, trimestreDebut: d, trimestreFin: f, avancement: av, responsable: 'poste:' + po.id }, extra || {}));
      out.creations = [
        mk('Inventaire général des stocks', 'logistique', 1, 1, 'realisee', { budgetPrevu: 500000, budgetRealise: 450000, tauxAvancement: 100 }),
        mk('Acquisition d’un échographe', 'investissement', 3, 3, 'planifiee', { budgetPrevu: 8000000, indicateur: 'Appareil installé', cible: 1, valeurAtteinte: 0 }),
        mk('Audit qualité', 'qualite', 4, 4, 'en_cours', { tauxAvancement: 40, budgetId: bud ? bud.id : undefined }),
        mk('Révision de la grille des primes', 'ressources_humaines', 2, 3, 'en_cours', { tauxAvancement: 0 }),
      ].map((r) => ({ ok: r.ok, code: r.code || null, reference: r.reference || null }));
      const ids = col.active().map((a) => a.id);
      out.fiches = propre(col.active().slice().reverse().map(H.net));
      const refus = (r) => ({ ok: !!r.ok, code: r.code || null });
      const base = { exercice: 2026, action: 'Essai', axe: 'qualite', trimestreDebut: 1, trimestreFin: 2, avancement: 'planifiee', responsableType: 'poste', responsableRef: po.id };
      const cas = [
        ['valide', {}], ['action vide', { action: '' }], ['exercice inconnu', { exercice: 1999 }], ['axe inconnu', { axe: 'inconnu' }], ['état inconnu', { avancement: 'inconnu' }],
        ['trimestres inversés', { trimestreDebut: 3, trimestreFin: 2 }], ['trimestre 5', { trimestreFin: 5 }], ['trimestre 0', { trimestreDebut: 0 }],
        ['responsable texte libre', { responsable: 'KASSA Augustin', responsableType: undefined, responsableRef: undefined }], ['responsable inconnu', { responsableRef: 'PST-INCONNU' }],
        ['responsable agent', { responsableType: 'agent', responsableRef: ag.id }], ['pourcentage 101', { tauxAvancement: 101 }], ['pourcentage -1', { tauxAvancement: -1 }],
        ['pourcentage 100', { tauxAvancement: 100 }], ['pourcentage 0', { tauxAvancement: 0 }], ['pourcentage texte', { tauxAvancement: 'abc' }], ['budget négatif', { budgetPrevu: -5 }],
        ['budget vide', { budgetPrevu: '' }], ['réalisé négatif', { budgetRealise: -1 }], ['cible texte', { cible: 'x' }], ['budget inconnu', { budgetId: 'BUD-INCONNU' }],
      ];
      out.controles = cas.map(([nom, patch]) => { const f = Object.assign({}, base, patch); Object.keys(f).forEach((k) => { if (f[k] === undefined) delete f[k]; }); return { nom, fiche: propre(f), code: (PA.controler(f) || {}).code || null }; });

      /* 3. règles pures du socle */
      out.finTrimestre = [['2026-01-01', 1], ['2026-01-01', 2], ['2026-01-01', 3], ['2026-01-01', 4], ['2026-04-01', 4], ['2027-01-01', 1], ['2024-01-01', 1], ['2024-11-01', 1], ['2026-01-01', 0], ['2026-01-01', 5], ['', 1], ['abc', 2]]
        .map(([d, q]) => ({ debut: d, q, fin: D.PLAN.finTrimestre(d, q) }));
      out.pourcentage = [null, '', undefined, 0, 100, 50.5, '45', 101, -0.1, 'abc', NaN].map((v) => ({ v: v === undefined ? '__undef' : (typeof v === 'number' && isNaN(v) ? '__nan' : v), r: propre(D.PLAN.pourcentage(v)) }));
      out.nombre = [null, '', undefined, 0, 12, '12.5', -1, 'x'].map((v) => ({ v: v === undefined ? '__undef' : v, r: D.PLAN.nombre(v) === undefined ? '__invalide' : D.PLAN.nombre(v) }));
      out.atteinte = [{}, { cible: 100 }, { cible: 100, valeurAtteinte: 0 }, { cible: 100, valeurAtteinte: 50 }, { cible: 3, valeurAtteinte: 1 }, { cible: 100, valeurAtteinte: 150 }, { cible: 0, valeurAtteinte: 5 }, { cible: '', valeurAtteinte: '' }, { cible: 'x', valeurAtteinte: 1 }]
        .map((a) => ({ a, r: propre(D.PLAN.atteinteIndicateur(a)) }));
      const jeux = [
        [], [{ avancement: 'realisee' }], [{ avancement: 'realisee', budgetPrevu: 100, budgetRealise: 80, tauxAvancement: 100 }, { avancement: 'en_cours', budgetPrevu: 50, tauxAvancement: 40 }],
        [{ avancement: 'planifiee', budgetPrevu: 0, budgetRealise: 0, tauxAvancement: 0 }, { avancement: 'planifiee' }], [{ avancement: 'inconnu', tauxAvancement: 10 }, { avancement: 'en_cours', tauxAvancement: 33 }, { avancement: 'en_cours', tauxAvancement: 34 }],
      ];
      out.totaux = jeux.map((j) => ({ actions: j, r: propre(D.PLAN.totaux(j)) }));
      const act = (av, fin) => ({ avancement: av, trimestreFin: fin });
      out.retard = [];
      [['2026-01-01', act('en_cours', 1), '2026-04-01', 0], ['2026-01-01', act('en_cours', 1), '2026-04-02', 0], ['2026-01-01', act('en_cours', 1), '2026-04-05', 5], ['2026-01-01', act('en_cours', 1), '2026-04-06', 5],
        ['2026-01-01', act('realisee', 1), '2026-12-01', 0], ['2026-01-01', act('planifiee', 3), '2026-10-01', 0], ['2026-01-01', act('planifiee', 3), '2026-09-30', 0], ['2026-01-01', act('inconnu', 1), '2026-12-31', 0],
        ['2026-01-01', act('en_cours', 9), '2026-12-31', 0], ['', act('en_cours', 1), '2026-12-31', 0], ['2026-01-01', act('en_cours', 4), '2026-12-31', 0], ['2026-01-01', act('en_cours', 4), '2027-01-01', 0]]
        .forEach(([debut, a, auj, grace]) => out.retard.push({ debut, a, auj, grace, r: propre(D.PLAN.retard(a, debut, auj, grace)) }));
      const fiches = [{ reference: 'PA-2026-001' }, { reference: 'PA-2026-007' }, { reference: 'PA-2025-099' }, { reference: 'BEB-2026-0100' }, { reference: 'PA-2026-abc' }];
      out.references = [['PA-', '2026-03-05', 3], ['PA-', '2027-01-01', 3], ['PA-', '2025-12-31', 3], ['PA-', '2024-06-01', 4], ['PA-', '', 3]].map(([p, d, l]) => ({ prefixe: p, date: d, largeur: l, fiches, ref: d ? C.referenceAnnuelle(p, d, l, fiches) : null }));

      /* 4. adoption : le geste réservé, le moteur qui refuse, la version datée */
      out.geste = { detenteurs: N.rolesAvecGeste('adopter_plan_annuel').slice().sort() };
      const roleAvant = (S.session() || {}).role;
      const poserRole = (role) => { const s = Object.assign({}, S.session() || {}, { role }); S.session = () => s; };
      const sessionOrig = S.session;
      poserRole('comptable');
      out.adoption = { sansDroit: refus(PA.adopter(2026, 'Délibération du conseil')) };
      poserRole('direction');
      out.adoption.sansMotif = refus(PA.adopter(2026, ''));
      out.adoption.exerciceInconnu = refus(PA.adopter(1999, 'Test'));
      out.adoption.planVide = refus(PA.adopter(2025, 'Test'));
      const r1 = PA.adopter(2026, 'Délibération du conseil d’administration du 30/10/2026');
      out.adoption.adopte = { ok: r1.ok, nbActions: r1.nbActions };
      out.adoption.fiche = H.net(S.collection('adoptionsPlan').active()[0]);
      out.adoption.deuxieme = refus(PA.adopter(2026, 'Encore'));
      const A = col.active().filter((a) => a.reference === 'PA-2026-001')[0] || col.active()[0];
      const garde = (patch) => { const r = col.update(A.id, patch); return r ? 'ECRIT' : 'REFUSE'; };
      out.adoption.apresAdoption = {
        modifierContenu: garde({ action: 'Autre libellé' }), modifierTrimestre: garde({ trimestreFin: 3 }), modifierBudgetPrevu: garde({ budgetPrevu: 1 }),
        modifierSuivi: garde({ tauxAvancement: 77 }), modifierReel: garde({ budgetRealise: 1234 }), archiver: (col.archive(A.id, 'test') ? 'ECRIT' : 'REFUSE'),
        ajouterDirect: (col.insert({ exercice: 2026, action: 'Directe', axe: 'qualite', trimestreDebut: 1, trimestreFin: 1, avancement: 'planifiee', responsableType: 'poste', responsableRef: po.id, reference: 'PA-2026-099', version: 1 }) ? 'ECRIT' : 'REFUSE'),
        suiviApres: A.tauxAvancement, realiseApres: A.budgetRealise,
      };
      out.adoption.ajoutSansMotif = refus(PA.ajouter({ exercice: 2026, action: 'Ajout', axe: 'qualite', trimestreDebut: 4, trimestreFin: 4, avancement: 'planifiee', responsable: 'poste:' + po.id }));
      const aj = PA.ajouter({ exercice: 2026, action: 'Ajout', axe: 'qualite', trimestreDebut: 4, trimestreFin: 4, avancement: 'planifiee', responsable: 'poste:' + po.id, motif: 'Demande de la Direction' });
      out.adoption.ajoutApres = { ok: aj.ok, reference: aj.reference, fiche: H.net(col.get(aj.id)) };
      const rv0 = PA.reviser(A.id, { trimestreFin: 2 }, '');
      out.adoption.reviserSansMotif = refus(rv0);
      out.adoption.reviserSuivi = refus(PA.reviser(A.id, { tauxAvancement: 5 }, 'Motif'));
      const rv = PA.reviser(A.id, { action: 'Inventaire général des stocks (révisé)', trimestreFin: 2 }, 'Report de l’inventaire au deuxième trimestre');
      out.adoption.revision = { ok: rv.ok, version: rv.version, reference: rv.reference, nouvelle: H.net(col.get(rv.id)), ancienneStatut: col.get(A.id).statut, ancienneMotif: col.get(A.id)._motifArchivage, actives: col.active().filter((x) => x.reference === A.reference).length };
      out.adoption.revisionDeLAncienne = refus(PA.reviser(A.id, { trimestreFin: 3 }, 'Encore'));
      S.session = sessionOrig;

      /* 5. reconduction vers 2027 */
      poserRole('admin');
      const sourceAvant = propre(col.active().filter((a) => a.exercice === 2026));
      const rec = PA.reconduire(2026, 2027);
      out.reconduction = { sourceAvant, ok: rec.ok, copiees: rec.copiees, ignorees: rec.ignorees, fiches: propre(col.active().filter((a) => a.exercice === 2027).slice().reverse().map(H.net)) };
      const rec2 = PA.reconduire(2026, 2027);
      out.reconduction.seconde = { ok: rec2.ok, copiees: rec2.copiees, ignorees: rec2.ignorees };
      out.reconduction.memeExercice = refus(PA.reconduire(2026, 2026));
      out.reconduction.versPlanAdopte = refus(PA.reconduire(2027, 2026));
      out.reconduction.sourceIntacte = col.active().filter((a) => a.exercice === 2026).length;
      S.session = sessionOrig;

      /* 6. alertes de retard à une date (une par action, retombent) */
      const al = (date) => PA.alertes(date).map((x) => x.action.reference + ':' + x.action.version).sort();
      out.alertes = { avril: al('2026-04-05'), juillet: al('2026-07-15'), octobre: al('2026-10-30'), janvier: al('2027-01-02') };
      const aCours = col.active().filter((a) => a.exercice === 2026 && a.avancement === 'en_cours')[0];
      const avantAl = al('2026-10-30').length;
      col.update(aCours.id, { avancement: 'realisee' });
      out.alertes.apresRealisation = { avant: avantAl, apres: al('2026-10-30').length };
      /* 7. signataires */
      out.signataires = { semes: propre(PA.signataires('2026-10-30')), sansDroit: null };
      poserRole('comptable');
      out.signataires.sansDroit = refus(PA.definirSignataires([po.id], '2026-11-01', 'Test'));
      poserRole('admin');
      out.signataires.vide = refus(PA.definirSignataires([], '2026-11-01', 'Test'));
      out.signataires.inconnu = refus(PA.definirSignataires(['PST-INCONNU'], '2026-11-01', 'Test'));
      out.signataires.sansMotif = refus(PA.definirSignataires([po.id], '2026-11-01', ''));
      const sv = PA.definirSignataires([po.id], '2026-11-15', 'Changement de signataire');
      out.signataires.version = { ok: sv.ok, avant: propre(PA.signataires('2026-11-14').signataires), apres: propre(PA.signataires('2026-11-15').signataires) };
      out.signataires.anterieure = refus(PA.definirSignataires([po.id], '2026-11-01', 'Rétroactif'));
      S.session = sessionOrig;
      return out;
    });

    /* 8. L'ÉCRAN RÉEL APRÈS ADOPTION : boutons de ligne, impression du plan et du bilan, totaux calculés (état de l'exercice 2026 adopté ci-dessus) */
    sortie.ecran = await m.page.evaluate(async () => {
      const out = {};
      const racine = await H.monter('m13-plan-annuel');
      out.kpis = H.kpis(racine);
      out.boutons = H.boutons(racine).slice(0, 12);
      const detail = [...racine.querySelectorAll('.card')].filter((c) => /Détail des actions/.test(c.innerText)).pop();
      out.tableaux = H.tableaux(racine);
      const ligne = [...detail.querySelectorAll('tbody tr')][0];
      out.boutonsLigne = [...ligne.querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
      H.bouton(racine, 'Imprimer le plan').click(); await H.dormir(200);
      out.etatPlan = H.propre(window.__etats[0]);
      window.__etats.length = 0;
      H.bouton(racine, 'Imprimer le bilan').click(); await H.dormir(200);
      out.etatBilan = H.propre(window.__etats[0]);
      H.retirer(racine);
      return out;
    });
    if (m.erreurs.length) throw new Error('erreurs JavaScript : ' + m.erreurs.join(' | '));
    ecrire('packages/domaine/test/vecteurs/plan_annuel.json', sortie);
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
