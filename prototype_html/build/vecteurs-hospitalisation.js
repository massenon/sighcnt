/* =============================================================================
 * VECTEURS DE L'HOSPITALISATION (M3) — m3-admissions, m3-chambres, m3-plan-lits, m3-observation, m3-feuille-temperature, m3-soins,
 * m3-administrations, m3-surveillance, m3-transfusion, m3-glasgow
 * -----------------------------------------------------------------------------
 * Les dix écrans sont montés TELS QUELS dans la page d'extraction, sur des jeux d'essai posés au magasin jetable ; on lit ce qu'ils AFFICHENT
 * (KPI, tableaux, cartes, graphiques et dessins interceptés), on PILOTE les modales et les tiroirs comme le fait l'agent, on intercepte les
 * pièces imprimées, et l'on appelle les moteurs exposés (relais d'administration). La banque de sang est fermée dans la maquette : la
 * surveillance transfusionnelle, elle, reste ouverte (la clinique pose du sang venu de l'extérieur).
 *
 *   node build/vecteurs-hospitalisation.js   →   packages/domaine/test/vecteurs/hospitalisation.json
 *
 * L'horloge est fixée au 16/08/2026 : `C.aujourdhui()` ET `new Date()` à 10 h 00 locale.
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs hospitalisation (M3)');
  const m = await ouvrirMaquette();
  try {
    await m.page.evaluate(() => {
      SIGH.core.aujourdhui = () => new Date(2026, 7, 16, 10, 0, 0);
      /* new Date() sans argument : 16/08/2026 10 h 00 locale (durée d'observation, relevés « du jour »). */
      const Vrai = Date;
      const FIXE = new Vrai(2026, 7, 16, 10, 0, 0).getTime();
      class Faux extends Vrai { constructor(...a) { if (a.length === 0) super(FIXE); else super(...a); } static now() { return FIXE; } }
      window.Date = Faux;
      window.__graphiques = [];
      window.__etats = [];
      const G = SIGH.charts;
      ['barres', 'ligne'].forEach((t) => {
        const orig = G[t];
        G[t] = function () {
          window.__graphiques.push({ type: t, args: JSON.parse(JSON.stringify(Array.prototype.slice.call(arguments, 0, 3))) });
          return orig.apply(this, arguments);
        };
      });
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
      /* Le tiroir et la modale : on lit ce qu'ils portent. */
    });
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m3-hospitalisation.js') });

    /* Aides communes, posées dans la page. */
    await m.page.evaluate(() => {
      const norm = (t) => String(t == null ? '' : t).replace(/[\n\t\r]+/g, ' ').replace(/\s+/g, ' ').trim();
      window.H = {
        norm,
        propre: (x) => JSON.parse(JSON.stringify(x)),
        dormir: (ms) => new Promise((r) => setTimeout(r, ms)),
        net: (x) => { const c = Object.assign({}, x); ['_creePar', '_creeLe', '_modifiePar', '_modifieLe', '_archivePar', '_archiveLe'].forEach((k) => delete c[k]); return JSON.parse(JSON.stringify(c)); },
        kpis: (root) => [...root.querySelectorAll('.kpi')].map((k) => {
          const p = k.querySelectorAll('p');
          return { libelle: norm(p[0].innerText), valeur: norm(p[1].innerText), indice: p[2] ? norm(p[2].innerText) : null };
        }),
        tableaux: (root) => [...root.querySelectorAll('table')].map((t) => ({
          entetes: [...t.querySelectorAll('thead th')].map((x) => norm(x.innerText)),
          lignes: [...t.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => norm(td.innerText))),
        })),
        cartes: (root) => [...root.querySelectorAll('.card')].map((c) => {
          const h = c.querySelector('.card-header, .card-head, h3, h2');
          return h ? norm(h.innerText) : null;
        }).filter(Boolean),
        notes: (root) => [...root.querySelectorAll('.rounded-lg.border')].map((n) => norm(n.innerText)).filter((t) => t.length > 20),
        fermerTout: () => document.querySelectorAll('[role=dialog], .modal-root, .drawer-root').forEach((x) => x.remove()),
        toasts: () => [...document.querySelectorAll('#toast-host > div')].map((n) => [...n.querySelectorAll('p')].map((p) => p.textContent.trim())),
        viderToasts: () => { const h = document.getElementById('toast-host'); if (h) h.innerHTML = ''; },
        bouton: (racine, texte) => [...racine.querySelectorAll('button')].find((b) => b.textContent.trim() === texte || b.getAttribute('aria-label') === texte || b.title === texte),
        poser: (id, v) => { const e = document.getElementById('f_' + id); if (!e) throw new Error('champ ' + id); if (e.type === 'checkbox') { e.checked = !!v; } else { e.value = v; } e.dispatchEvent(new Event('input')); e.dispatchEvent(new Event('change')); },
        champs: () => [...document.querySelectorAll('[role=dialog] label, .modal-root label')].map((l) => norm(l.innerText)),
        optsDe: (id) => { const e = document.getElementById('f_' + id); if (!e || !e.options) return null; if (typeof e.options === 'function') return e.options().map((o) => [o.value, norm(o.label)].concat(o.detail ? [norm(o.detail)] : [])); return [...e.options].map((o) => [o.value, norm(o.textContent)]); },
        cliquer: (texte) => [...document.querySelectorAll('button')].find((b) => b.textContent.trim() === texte).click(),
        icone: (ligne, nom) => [...ligne.querySelectorAll('button')].find((b) => (b.getAttribute('aria-label') || b.title) === nom),
        boutons: (racine) => [...racine.querySelectorAll('button')].map((b) => norm(b.textContent || b.getAttribute('aria-label') || b.title)).filter(Boolean),
        tiroir: () => { const t = document.querySelector('[role=dialog], .drawer-root') || document.body; return { texte: norm(t.innerText), boutons: [...t.querySelectorAll('button')].map((b) => norm(b.textContent || b.getAttribute('aria-label') || b.title)).filter(Boolean) }; },
        monter: async (id) => {
          const root = document.createElement('div'); document.body.appendChild(root);
          window.__graphiques.length = 0; window.__etats.length = 0;
          SIGH.screens[id].render(root);
          await new Promise((r) => setTimeout(r, 300));
          return root;
        },
        retirer: (root) => { root.remove(); H.fermerTout(); },
        mettreDeCote: (cols) => { const sauve = {}; cols.forEach((c) => { sauve[c.name] = c.all().splice(0); }); return sauve; },
        remettre: (cols, sauve) => { cols.forEach((c) => { c.all().splice(0); (sauve[c.name] || []).forEach((x) => c.all().push(x)); }); },
        J: (n) => { const d = new Date(2026, 7, 16 + n); return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'); },
      };
    });

    const sortie = { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-hospitalisation.js — ne pas éditer. Horloge : 16/08/2026.' };

    /* ------------------------------------------------------------------ référentiels et moteur de relais */
    sortie.referentiels = await m.page.evaluate(() => {
      const D = SIGH.data, PR = SIGH.parcours;
      const relais = [];
      ['ambulatoire', 'hospitalisation'].forEach((mod) => [1, 2, 3, 4].forEach((rang) => relais.push({ modalite: mod, rang, ...D.secteurAdministrateur(mod, rang) })));
      return H.propre({
        chambres: D.CHAMBRES, typesChambre: D.TYPES_CHAMBRE, unitesObservation: D.UNITES_OBSERVATION, orientations: D.ORIENTATIONS_OBSERVATION,
        dureeObservation: D.DUREE_OBSERVATION_REFERENCE, actesSoins: D.ACTES_SOINS,
        executerSoins: Object.fromEntries(Object.keys(D.CAPACITES).map((k) => [k, !!D.CAPACITES[k].executerSoins])),
        relais,
      });
    });

    /* ------------------------------------------------------------------ admissions, chambres, plan des lits */
    sortie.admissions = await m.page.evaluate(async () => {
      const S = SIGH.store, J = H.J;
      const colAdm = S.collection('admissions'), colFac = S.collection('factures');
      const sauve = H.mettreDeCote([colAdm, colFac]);
      const pats = S.collection('patients').active();
      const p = (i) => ({ patientId: pats[i].id, patient: pats[i].nom + ' ' + pats[i].prenom, patientCode: pats[i].code });
      const adm = (n, i, lit, type, entree, sortie, statut, extra) => Object.assign({
        id: 'ADM' + n, statut, reference: 'H' + String(n).padStart(5, '0'), ...p(i), chambre: lit.split(' ')[0], lit, typeChambre: type,
        dateEntree: J(entree), dateSortie: sortie == null ? null : J(sortie), diagnosticEntree: 'Diagnostic ' + n, symptomes: 'Symptômes ' + n,
        priseEnCharge: n % 2 ? 'plus_8h' : 'moins_8h', infirmier: 'GARBA Yahouza',
      }, extra || {});
      const jeu = [
        adm(1, 0, 'A1 LIT1', 'standard', -10, null, 'en_cours'),
        adm(2, 1, 'C1 LIT1', 'vip', -2, null, 'en_cours'),
        adm(3, 2, 'A2 LIT1', 'standard', -20, -14, 'sortie'),
        adm(4, 3, 'B1 LIT1', 'standard', -9, -8, 'sortie'),
        adm(5, 0, 'D1 LIT1', 'vvip', 0, null, 'en_cours'),
        adm(6, 1, 'B2 LIT1', 'standard', -40, -30, 'sortie', { statut: 'archive' }),
        adm(7, 2, 'A3 LIT2', 'standard', -6, null, 'en_cours'),
      ];
      colAdm.all().splice(0); jeu.forEach((x) => colAdm.all().push(x));
      colFac.all().splice(0);
      [{ id: 'FX1', statut: 'actif', patientId: pats[0].id, reliquat: 5000 }, { id: 'FX2', statut: 'actif', patientId: pats[0].id, reliquat: 2500 }]
        .forEach((x) => colFac.all().push(x));

      const out = { patients: pats.slice(0, 4).map((x) => ({ id: x.id, code: x.code, nom: x.nom, prenom: x.prenom })), nbPatients: pats.length, jeu: H.propre(jeu), factures: H.propre(colFac.all()) };
      let racine = await H.monter('m3-admissions');
      out.ecran = { kpis: H.kpis(racine), tableaux: H.tableaux(racine), boutons: H.boutons(racine).slice(0, 14),
        filtres: [...racine.querySelectorAll('select')].map((s) => [...s.options].map((o) => [o.value, H.norm(o.textContent)])) };
      const lig = (ref) => [...racine.querySelectorAll('tbody tr')].find((tr) => tr.innerText.includes(ref));
      lig('H00001').click(); await H.dormir(250);
      out.tiroirSolde = H.tiroir(); H.fermerTout();
      lig('H00002').click(); await H.dormir(250);
      out.tiroirApure = H.tiroir(); H.fermerTout();
      lig('H00003').click(); await H.dormir(250);
      out.tiroirSortie = H.tiroir(); H.fermerTout();
      H.icone(lig('H00001'), 'Imprimer l’état').click(); await H.dormir(200);
      out.etat = H.propre(window.__etats[0] || null);
      /* Création */
      H.bouton(racine, 'Nouveau').click(); await H.dormir(250);
      out.creation = { champs: H.champs(), defauts: {} };
      for (const n of ['patientCode', 'lit', 'infirmier', 'dateEntree', 'priseEnCharge', 'diagnosticEntree', 'symptomes']) {
        const e = document.getElementById('f_' + n);
        out.creation.defauts[n] = e ? e.value : '(absent)';
      }
      const optsDe = H.optsDe;
      out.creation.optionsLit = optsDe('lit'); out.creation.optionsInfirmier = optsDe('infirmier'); out.creation.optionsPriseEnCharge = optsDe('priseEnCharge');
      out.creation.optionsPatient = optsDe('patientCode') ? optsDe('patientCode').slice(0, 3) : null;
      H.viderToasts();
      H.cliquer('Créer'); await H.dormir(200);
      out.creation.refusVide = { toasts: H.toasts(), total: colAdm.all().length };
      H.poser('patientCode', pats[1].code); H.poser('lit', 'A1 LIT1'); H.poser('diagnosticEntree', 'Paludisme grave');
      H.viderToasts();
      H.cliquer('Créer'); await H.dormir(250);
      out.creation.refusLitOccupe = { toasts: H.toasts(), total: colAdm.all().length };
      H.poser('lit', 'A1 LIT2'); H.poser('symptomes', 'Fièvre'); H.poser('infirmier', H.optsDe('infirmier')[1][0]);
      H.viderToasts();
      H.cliquer('Créer'); await H.dormir(300);
      out.creation.cree = { toasts: H.toasts(), fiche: H.net(colAdm.all().find((a) => a.diagnosticEntree === 'Paludisme grave')), total: colAdm.all().length };
      /* La référence suivante lit le registre : on archive la dernière et on recrée. */
      H.bouton(racine, 'Nouveau').click(); await H.dormir(250);
      H.poser('patientCode', pats[2].code); H.poser('lit', 'B3 LIT1'); H.poser('diagnosticEntree', 'Deuxième création');
      H.cliquer('Créer'); await H.dormir(300);
      out.creation.deuxieme = { fiche: H.net(colAdm.all().find((a) => a.diagnosticEntree === 'Deuxième création')) };
      /* Modification : un lit libre, un lit occupé par un autre, le sien */
      H.icone(lig('H00001'), 'Modifier').click(); await H.dormir(250);
      out.modification = { champs: H.champs(), optionsLit: optsDe('lit'), valeurs: {} };
      for (const n of ['patientCode', 'lit', 'infirmier', 'dateEntree', 'priseEnCharge', 'diagnosticEntree']) out.modification.valeurs[n] = document.getElementById('f_' + n).value;
      H.poser('lit', 'A2 LIT2'); H.poser('diagnosticEntree', 'Diagnostic corrigé');
      H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.modification.enregistre = { toasts: H.toasts(), fiche: H.net(colAdm.all().find((a) => a.id === 'ADM1')) };
      H.icone(lig('H00002'), 'Modifier').click(); await H.dormir(250);
      H.poser('lit', 'A2 LIT2'); H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(250);
      out.modification.refusOccupe = { toasts: H.toasts(), fiche: H.net(colAdm.all().find((a) => a.id === 'ADM2')) };
      H.fermerTout();
      H.retirer(racine);
      out.etatFinal = H.propre(colAdm.all());
      /* chambres et plan des lits sur l'état courant du registre */
      racine = await H.monter('m3-chambres');
      out.chambres = { kpis: H.kpis(racine), tableaux: H.tableaux(racine), cartes: H.cartes(racine), boutons: H.boutons(racine).slice(0, 8),
        filtres: [...racine.querySelectorAll('select')].map((s) => [...s.options].map((o) => [o.value, H.norm(o.textContent)])) };
      H.bouton(racine, 'Imprimer le plan').click(); await H.dormir(200);
      out.chambres.etat = H.propre(window.__etats[0] || null);
      H.retirer(racine);
      racine = await H.monter('m3-plan-lits');
      const cartesLits = [...racine.querySelectorAll('button')].filter((b) => /LIT\d/.test(b.textContent)).map((b) => ({
        texte: H.norm(b.textContent), couleur: (b.querySelector('span').className.match(/bg-(success|danger|warning)-500/) || [])[1] || null }));
      out.plan = { kpis: H.kpis(racine), cartes: H.cartes(racine), lits: cartesLits, graphiques: H.propre(window.__graphiques),
        legende: H.norm([...racine.querySelectorAll('span')].find((s) => s.textContent.trim() === 'Légende :').parentElement.innerText) };
      const bl = (t) => [...racine.querySelectorAll('button')].find((b) => b.textContent.includes(t));
      bl('A1 LIT1').click(); await H.dormir(250); out.plan.tiroirOccupe = H.tiroir(); H.fermerTout();
      bl('C2 LIT1').click(); await H.dormir(250); out.plan.tiroirLibre = H.tiroir(); H.fermerTout();
      bl('A3 LIT2').click(); await H.dormir(250); out.plan.tiroirLong = H.tiroir(); H.fermerTout();
      H.retirer(racine);
      H.remettre([colAdm, colFac], sauve);
      return out;
    });
    /* ------------------------------------------------------------------ mise en observation */
    sortie.observation = await m.page.evaluate(async () => {
      const S = SIGH.store, D = SIGH.data;
      const colObs = S.collection('observations', { module: 'M3', entite: 'mise en observation', prefix: 'OBS' });
      const colAdm = S.collection('admissions');
      const sauve = H.mettreDeCote([colObs, colAdm]);
      const out = {};
      /* L'AMORÇAGE de la maquette sur un registre vide : c'est lui qui fait le jeu de démonstration (18 séjours, 6 en cours). */
      let racine = await H.monter('m3-observation');
      out.amorcage = { observations: H.propre(colObs.all()), kpis: H.kpis(racine), notes: H.notes(racine), tableaux: H.tableaux(racine) };
      H.retirer(racine);
      colObs.all().splice(0);
      const pats = S.collection('patients').active();
      const p = (i) => ({ patientId: pats[i].id, patient: pats[i].nom + ' ' + pats[i].prenom, patientCode: pats[i].code });
      const U = D.UNITES_OBSERVATION;
      const il = (h) => new Date(new Date(2026, 7, 16, 10, 0, 0).getTime() - h * 3600000).toISOString();
      const cst = (h, t, ta, pouls, spo2, obs, par) => ({ heure: il(h), temperature: t, tension: ta, pouls, spo2, observation: obs, par });
      const obs = (n, i, unite, hEntree, hSortie, statutObs, orient, constantes, extra) => Object.assign({
        id: 'OBS' + String(n).padStart(4, '0'), statut: 'actif', reference: 'OBS-2026-' + String(n).padStart(4, '0'), ...p(i),
        unite: U[unite].id, uniteLabel: U[unite].label, place: 'place ' + n, motif: 'Motif ' + n, dateEntree: il(hEntree), dateSortie: hSortie == null ? null : il(hSortie),
        medecin: 'BASSONGUI Chabi Séko', infirmier: 'GARBA Yahouza', constantes: constantes || [], statutObservation: statutObs,
        orientation: orient ? orient.id : null, orientationLabel: orient ? orient.label : null, conclusion: orient ? 'Conclusion ' + n : null,
      }, extra || {});
      const O = D.ORIENTATIONS_OBSERVATION;
      const jeu = [
        obs(1, 0, 0, 3, null, 'en_cours', null, [cst(3, '37.2', '12/8', 80, 98, 'Repos', 'DOSSOU Moussa'), cst(1, '38.4', '11/7', 96, 95, 'Fièvre', 'DOSSOU Moussa')]),
        obs(2, 1, 1, 20, null, 'en_cours', null, []),
        obs(3, 2, 1, 25, null, 'en_cours', null, [cst(24, '36.8', '13/8', 72, 99, 'Conscient', 'GARBA Yahouza'), cst(12, '37.0', '12/8', 76, 98, '', 'GARBA Yahouza'), cst(2, '39.1', '10/6', 110, 93, 'Sous perfusion', 'NKOUÉ Jean')]),
        obs(4, 3, 2, 48, null, 'en_cours', null, [cst(40, '37.5', '12/7', 88, 97, '', 'BAGRI Elvyre')]),
        obs(5, 0, 3, 50, 30, 'clos', O[0], [cst(49, '37.0', '12/8', 70, 99, '', 'GARBA Yahouza')]),
        obs(6, 1, 0, 100, 70, 'clos', O[1], []),
        obs(7, 2, 1, 10, null, 'en_cours', null, [], { statut: 'archive' }),
      ];
      jeu.forEach((x) => colObs.all().push(x));
      racine = await H.monter('m3-observation');
      out.jeu = H.propre(jeu);
      out.ecran = { kpis: H.kpis(racine), notes: H.notes(racine), cartes: H.cartes(racine), tableaux: H.tableaux(racine), boutons: H.boutons(racine).slice(0, 12),
        filtres: [...racine.querySelectorAll('select')].map((s) => [...s.options].map((o) => [o.value, H.norm(o.textContent)])) };
      const onglets = [...racine.querySelectorAll('[role=tab]')];
      out.ecran.onglets = onglets.map((t) => H.norm(t.textContent));
      if (!onglets[1]) throw new Error('onglets absents : ' + H.norm(racine.innerText).slice(0, 400));
      onglets[1].click(); await H.dormir(250);
      out.ecran.closTableaux = H.tableaux(racine);
      out.ecran.closBoutons = H.boutons(racine).slice(0, 20);
      onglets[0].click(); await H.dormir(250);
      const lig = (ref) => [...racine.querySelectorAll('tbody tr')].find((tr) => tr.innerText.includes(ref));
      out.ecran.boutonsLigneEnCours = [...lig('OBS-2026-0003').querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
      /* fiche */
      lig('OBS-2026-0003').click(); await H.dormir(300);
      out.fiche = Object.assign(H.tiroir(), { graphiques: H.propre(window.__graphiques) });
      out.fiche.tables = H.tableaux(document.querySelector('[role=dialog], .drawer-root') || document.body);
      H.fermerTout();
      lig('OBS-2026-0002').click(); await H.dormir(300);
      out.ficheSansReleve = H.tiroir(); H.fermerTout();
      H.icone(lig('OBS-2026-0003'), 'Imprimer la feuille').click(); await H.dormir(200);
      out.etat = H.propre(window.__etats[0] || null);
      /* mise en observation */
      out.actionsEntete = SIGH.screens['m3-observation'].actions().map((b) => H.norm(b.textContent));
      SIGH.screens['m3-observation'].actions().find((b) => b.textContent.trim() === 'Mettre en observation').click(); await H.dormir(250);
      out.admission = { champs: H.champs(), defauts: {} };
      for (const n of ['patientCode', 'motif', 'unite', 'place', 'dateEntree', 'medecin', 'infirmier']) { const e = document.getElementById('f_' + n); out.admission.defauts[n] = e ? e.value : '(absent)'; }
      out.admission.optionsUnite = H.optsDe('unite'); out.admission.optionsMedecin = H.optsDe('medecin'); out.admission.optionsInfirmier = H.optsDe('infirmier');
      H.viderToasts(); H.cliquer('Mettre en observation'); await H.dormir(200);
      out.admission.refusVide = { toasts: H.toasts(), total: colObs.all().length };
      H.poser('patientCode', pats[3].code); H.poser('motif', 'Malaise'); H.poser('unite', 'pediatrie'); H.poser('place', 'P2'); H.poser('dateEntree', '2026-08-16T08:30');
      H.viderToasts(); H.cliquer('Mettre en observation'); await H.dormir(300);
      out.admission.cree = { toasts: H.toasts(), fiche: H.net(colObs.all().find((o) => o.motif === 'Malaise')), total: colObs.all().length };
      /* relevé */
      H.icone(lig('OBS-2026-0003'), 'Relever les constantes').click(); await H.dormir(250);
      out.releve = { champs: H.champs(), defauts: {} };
      for (const n of ['heure', 'temperature', 'tension', 'pouls', 'spo2', 'observation', 'par']) { const e = document.getElementById('f_' + n); out.releve.defauts[n] = e ? e.value : '(absent)'; }
      H.viderToasts(); H.cliquer('Enregistrer le relevé'); await H.dormir(200);
      out.releve.refusVide = { toasts: H.toasts() };
      H.poser('temperature', '38.2'); H.poser('tension', '11/7'); H.poser('pouls', '90'); H.poser('heure', '2026-08-16T09:45');
      H.viderToasts(); H.cliquer('Enregistrer le relevé'); await H.dormir(300);
      out.releve.enregistre = { toasts: H.toasts(), constantes: H.propre(colObs.all().find((o) => o.id === 'OBS0003').constantes) };
      /* orientation : retour à domicile */
      H.icone(lig('OBS-2026-0003'), 'Décider de l’orientation').click(); await H.dormir(250);
      out.orientation = { champs: H.champs(), defauts: {}, texte: H.tiroir().texte, optionsOrientation: H.optsDe('orientation') };
      for (const n of ['orientation', 'conclusion', 'dateSortie', 'medecin', 'destination']) { const e = document.getElementById('f_' + n); out.orientation.defauts[n] = e ? e.value : '(absent)'; }
      H.viderToasts(); H.cliquer('Enregistrer la décision'); await H.dormir(200);
      out.orientation.refusVide = { toasts: H.toasts() };
      H.poser('orientation', 'domicile'); H.poser('conclusion', 'Évolution favorable'); H.poser('dateSortie', '2026-08-16T09:50');
      const avant = colAdm.all().length;
      H.viderToasts(); H.cliquer('Enregistrer la décision'); await H.dormir(300);
      out.orientation.domicile = { toasts: H.toasts(), fiche: H.net(colObs.all().find((o) => o.id === 'OBS0003')), admissionsCreees: colAdm.all().length - avant };
      /* orientation : hospitalisation complète → une ADMISSION portant origineObservation */
      H.icone(lig('OBS-2026-0001'), 'Décider de l’orientation').click(); await H.dormir(250);
      H.poser('orientation', 'hospitalisation'); H.poser('conclusion', 'Aggravation constatée'); H.poser('dateSortie', '2026-08-16T09:55'); H.poser('destination', '');
      H.viderToasts(); H.cliquer('Enregistrer la décision'); await H.dormir(300);
      out.orientation.hospitalisation = { toasts: H.toasts(), fiche: H.net(colObs.all().find((o) => o.id === 'OBS0001')),
        admissionsCreees: colAdm.all().length - avant, admission: H.net(colAdm.all().find((a) => a.origineObservation === 'OBS-2026-0001')) };
      /* le registre après ces gestes */
      H.retirer(racine);
      racine = await H.monter('m3-observation');
      out.apres = { kpis: H.kpis(racine), notes: H.notes(racine), tableaux: H.tableaux(racine) };
      H.retirer(racine);
      out.finalObservations = H.propre(colObs.all());
      H.remettre([colObs, colAdm], sauve);
      return out;
    });

    /* ------------------------------------------------------------------ feuille de température */
    sortie.temperature = await m.page.evaluate(async () => {
      const S = SIGH.store, J = H.J;
      const colAdm = S.collection('admissions'), colRel = S.collection('releves', { module: 'M3', entite: 'FeuilleTemperature' });
      const sauve = H.mettreDeCote([colAdm, colRel]);
      const pats = S.collection('patients').active();
      const adm = (n, i, lit, type, entree) => ({ id: 'ADM' + n, statut: 'en_cours', reference: 'H' + String(n).padStart(5, '0'), patientId: pats[i].id, patient: pats[i].nom + ' ' + pats[i].prenom,
        patientCode: pats[i].code, chambre: lit.split(' ')[0], lit, typeChambre: type, dateEntree: J(entree), dateSortie: null, diagnosticEntree: 'Diagnostic ' + n, symptomes: '', priseEnCharge: 'plus_8h', infirmier: 'GARBA Yahouza' });
      const jeuAdm = [adm(1, 0, 'A1 LIT1', 'standard', -4), adm(2, 1, 'C1 LIT1', 'vip', -1)];
      jeuAdm.forEach((x) => colAdm.all().push(x));
      const rel = (n, date, heure, t, ta, fc, spo2, extra) => Object.assign({ id: 'REL' + n, statut: 'actif', admissionId: 'ADM1', date, heure, temperature: t, tension: ta, fc, spo2, fr: 18, diurese: 900 + n, poids: 60 + n, taille: 170, traitement: 'Traitement ' + n, saisiPar: 'DOSSOU Moussa' }, extra || {});
      const jeuRel = [
        rel(1, J(-3), '08:00', 37.2, '12/8', 80, 98), rel(2, J(-3), '20:00', 38.4, '13/9', 96, 93), rel(3, J(-2), '08:00', 35.8, '10/6', 62, 99),
        rel(4, J(-2), '20:00', 38.0, '12/8', 88, 94), rel(5, J(-1), '08:00', 36.9, '11/7', 74, 97), rel(6, J(-1), '14:00', 39.2, '14/9', 110, 90),
        rel(7, J(0), '08:00', 37.0, '12/8', 78, 98, { statut: 'archive' }),
      ];
      jeuRel.forEach((x) => colRel.all().push(x));
      const out = { admissions: H.propre(jeuAdm), releves: H.propre(jeuRel) };
      let racine = await H.monter('m3-feuille-temperature');
      const combo = () => [...racine.querySelectorAll('*')].find((e) => typeof e.options === 'function' && typeof e.setOptions === 'function');
      out.ecran = { cartes: H.cartes(racine), tableaux: H.tableaux(racine), graphiques: H.propre(window.__graphiques), boutons: H.boutons(racine).slice(0, 14),
        texte: H.norm(racine.innerText).slice(0, 700), options: combo().options().map((o) => [o.value, o.label, o.detail]) };
      /* création */
      H.bouton(racine, 'Nouveau relevé').click(); await H.dormir(250);
      out.saisie = { champs: H.champs(), defauts: {} };
      for (const n of ['date', 'heure', 'temperature', 'tension', 'fc', 'spo2', 'fr', 'diurese', 'poids', 'taille', 'traitement']) { const e = document.getElementById('f_' + n); out.saisie.defauts[n] = e ? e.value : '(absent)'; }
      H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(200);
      out.saisie.refusVide = { toasts: H.toasts() };
      H.poser('temperature', '50'); H.poser('tension', '12/8'); H.poser('fc', '80'); H.poser('spo2', '97');
      H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(200);
      out.saisie.refusPlage = { toasts: H.toasts(), erreurs: [...document.querySelectorAll('[role=dialog] .field-error, [role=dialog] .text-danger-600')].map((e) => H.norm(e.textContent)).filter(Boolean), total: colRel.all().length };
      H.poser('temperature', '37.8'); H.poser('fr', '20'); H.poser('diurese', '1200'); H.poser('traitement', 'Paracétamol');
      H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.saisie.cree = { toasts: H.toasts(), fiche: H.net(colRel.all().find((r) => r.traitement === 'Paracétamol')), total: colRel.all().length };
      out.apresCreation = { cartes: H.cartes(racine), tableaux: H.tableaux(racine), graphiques: H.propre(window.__graphiques).slice(-2) };
      /* archivage d'un relevé */
      const ligneRel = [...racine.querySelectorAll('tbody tr')].find((tr) => tr.innerText.includes('Paracétamol'));
      H.viderToasts(); H.icone(ligneRel, 'Archiver ce relevé').click(); await H.dormir(300);
      out.archivage = { toasts: H.toasts(), statut: colRel.all().find((r) => r.traitement === 'Paracétamol').statut };
      /* impression */
      H.bouton(racine, 'Imprimer la feuille').click(); await H.dormir(200);
      out.etat = H.propre(window.__etats[0] || null);
      /* second patient : aucun relevé */
      combo().value = 'ADM2'; combo().dispatchEvent(new Event('change')); await H.dormir(250);
      out.sansReleve = { cartes: H.cartes(racine), texte: H.norm(racine.innerText).slice(0, 600), boutons: H.boutons(racine).slice(0, 8) };
      H.retirer(racine);
      /* aucun patient hospitalisé */
      colAdm.all().splice(0);
      racine = await H.monter('m3-feuille-temperature');
      out.vide = { texte: H.norm(racine.innerText) };
      H.retirer(racine);
      H.remettre([colAdm, colRel], sauve);
      return out;
    });

    /* ------------------------------------------------------------------ feuille de soins (K.crud + file des actes prescrits) */
    sortie.soins = await m.page.evaluate(async () => {
      const S = SIGH.store, J = H.J, PR = SIGH.parcours;
      const colAdm = S.collection('admissions'), colSoi = S.collection('soins'), colTa = S.collection('taches'), colOrd = S.collection('ordonnances');
      const sauve = H.mettreDeCote([colAdm, colSoi, colTa, colOrd]);
      const session0 = localStorage.getItem('sigh-cnt:session');
      const pats = S.collection('patients').active();
      const adm = (n, i, lit, entree) => ({ id: 'ADM' + n, statut: 'en_cours', reference: 'H' + String(n).padStart(5, '0'), patientId: pats[i].id, patient: pats[i].nom + ' ' + pats[i].prenom,
        patientCode: pats[i].code, chambre: lit.split(' ')[0], lit, typeChambre: 'standard', dateEntree: J(entree), dateSortie: null, diagnosticEntree: 'Diagnostic ' + n, symptomes: '', priseEnCharge: 'plus_8h', infirmier: 'GARBA Yahouza' });
      const jeuAdm = [adm(1, 0, 'A1 LIT1', -4), adm(2, 1, 'A2 LIT1', -1)];
      jeuAdm.forEach((x) => colAdm.all().push(x));
      const soin = (n, a, date, heure, acte, etat, extra) => Object.assign({ id: 'SOI' + n, statut: 'actif', date, heure, admissionId: jeuAdm[a].id, patientId: jeuAdm[a].patientId, patient: jeuAdm[a].patient, patientCode: jeuAdm[a].patientCode, lit: jeuAdm[a].lit, acte, produit: n % 2 ? 'Produit ' + n : '', quantite: n % 2 ? 2 : 0, soignant: 'DOSSOU Moussa', observations: n === 1 ? 'RAS' : '', etat }, extra || {});
      const jeuSoins = [soin(1, 0, J(-2), '08:00', 'Injection intraveineuse', 'realise'), soin(2, 0, J(-1), '12:00', 'Pose de perfusion', 'planifie'),
        soin(3, 1, J(-1), '16:00', 'Aérosol', 'realise'), soin(4, 1, J(0), '09:00', 'Soins de nursing', 'planifie'), soin(5, 1, J(-3), '10:00', 'Aérosol', 'realise', { statut: 'archive' })];
      jeuSoins.forEach((x) => colSoi.all().push(x));
      colOrd.all().push({ id: 'ORD1', numero: 'ORD-T1', statut: 'actif', patientCode: pats[0].code, patient: pats[0].nom + ' ' + pats[0].prenom });
      const tache = (n, statut, urgent) => ({ id: 'TCH' + n, statut, type: 'acte', role: 'infirmier', module: 'M3', ecran: 'm3-soins', titre: 'Exécuter les soins', reference: 'ORD-T' + n,
        ordonnanceId: n === 1 ? 'ORD1' : null, patient: pats[n - 1].nom + ' ' + pats[n - 1].prenom, patientCode: pats[n - 1].code, date: '2026-08-1' + n + 'T09:00:00.000Z', urgent: !!urgent, detail: '2 acte(s) — Soin ' + n, montant: 1500 * n });
      const jeuTaches = [tache(1, 'en_attente', true), tache(2, 'bloque', false), tache(3, 'en_attente', false)];
      jeuTaches.forEach((x) => colTa.all().push(x));
      const out = { admissions: H.propre(jeuAdm), soins: H.propre(jeuSoins), taches: H.propre(jeuTaches) };
      /* 1) sous la fonction « direction » de la session : l'exécution ne revient pas à ce profil */
      let racine = await H.monter('m3-soins');
      out.directionNote = H.notes(racine);
      out.ecran = { kpis: H.kpis(racine), cartes: H.cartes(racine), tableaux: H.tableaux(racine), boutons: H.boutons(racine).slice(0, 18),
        filtres: [...racine.querySelectorAll('select')].map((s) => [...s.options].map((o) => [o.value, H.norm(o.textContent)])) };
      const ligT = (ref) => [...racine.querySelectorAll('tbody tr')].find((tr) => tr.innerText.includes(ref));
      H.viderToasts(); H.icone(ligT('ORD-T1'), 'Marquer le soin fait').click(); await H.dormir(250);
      out.refusDirection = { toasts: H.toasts(), dialogue: !!document.querySelector('[role=dialog]'), tache: colTa.all().find((t) => t.id === 'TCH1').statut };
      H.fermerTout();
      H.retirer(racine);
      /* 2) sous la fonction « infirmier » : confirmation, puis l'ordonnance et la tâche sont mises à jour */
      const s = JSON.parse(session0); s.fonction = 'infirmier'; localStorage.setItem('sigh-cnt:session', JSON.stringify(s));
      out.peutExecuter = { infirmier: PR.peutExecuterSoin() };
      racine = await H.monter('m3-soins');
      out.infirmierNote = H.notes(racine);
      H.viderToasts(); H.icone(ligT('ORD-T1'), 'Marquer le soin fait').click(); await H.dormir(250);
      out.confirmation = { texte: H.tiroir().texte, boutons: H.tiroir().boutons };
      H.cliquer('Soin fait'); await H.dormir(400);
      out.fait = { toasts: H.toasts(), tache: H.net(colTa.all().find((t) => t.id === 'TCH1')), ordonnance: H.net(colOrd.all().find((o) => o.id === 'ORD1')), boutons: H.boutons(racine).slice(0, 12) };
      H.viderToasts(); H.icone(ligT('ORD-T2'), 'Bloquée jusqu’à l’encaissement').click(); await H.dormir(250);
      out.bloquee = { toasts: H.toasts() };
      H.retirer(racine);
      localStorage.setItem('sigh-cnt:session', session0);
      /* 3) le registre des actes */
      racine = await H.monter('m3-soins');
      const lig = (txt) => [...racine.querySelectorAll('tbody tr')].find((tr) => tr.innerText.includes(txt));
      const ongletsSoins = [...racine.querySelectorAll('[role=tab]')].map((t) => H.norm(t.textContent));
      out.ecran.onglets = ongletsSoins;
      /* le tableau des actes est le DERNIER tableau de la page (la file des actes prescrits est le premier) */
      const tableauActes = () => { const t = [...racine.querySelectorAll('table')]; return t[t.length - 1]; };
      out.registre = { entetes: [...tableauActes().querySelectorAll('thead th')].map((x) => H.norm(x.innerText)), lignes: [...tableauActes().querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => H.norm(td.innerText))) };
      const ligActe = (txt) => [...tableauActes().querySelectorAll('tbody tr')].find((tr) => tr.innerText.includes(txt));
      ligActe('Pose de perfusion').click(); await H.dormir(250);
      out.detail = H.tiroir(); H.fermerTout();
      H.icone(ligActe('Pose de perfusion'), 'Imprimer l’état').click(); await H.dormir(200);
      out.etat = H.propre(window.__etats[0] || null);
      H.bouton(racine, 'Nouveau').click(); await H.dormir(250);
      out.creation = { champs: H.champs(), defauts: {}, optionsPatient: H.optsDe('admissionId'), optionsActe: H.optsDe('acte'), optionsEtat: H.optsDe('etat') };
      for (const n of ['admissionId', 'date', 'heure', 'acte', 'produit', 'quantite', 'soignant', 'etat', 'observations']) { const e = document.getElementById('f_' + n); out.creation.defauts[n] = e ? e.value : '(absent)'; }
      H.viderToasts(); H.poser('soignant', ''); H.cliquer('Créer'); await H.dormir(200);
      out.creation.refusSansSoignant = { toasts: H.toasts(), total: colSoi.all().length };
      H.poser('admissionId', 'ADM2'); H.poser('acte', 'Injection intramusculaire'); H.poser('produit', 'Ceftriaxone'); H.poser('quantite', '1'); H.poser('soignant', 'NKOUÉ Jean'); H.poser('observations', 'Bien toléré');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.creation.cree = { toasts: H.toasts(), fiche: H.net(colSoi.all().find((r) => r.produit === 'Ceftriaxone')), total: colSoi.all().length };
      out.apres = { kpis: H.kpis(racine) };
      /* modification : le patient change, la fiche reprend le lit de l'admission choisie */
      H.icone(ligActe('Ceftriaxone'), 'Modifier').click(); await H.dormir(250);
      out.modification = { valeurs: {} };
      for (const n of ['admissionId', 'date', 'heure', 'acte', 'produit', 'quantite', 'soignant', 'etat']) { const e = document.getElementById('f_' + n); out.modification.valeurs[n] = e ? e.value : '(absent)'; }
      H.poser('admissionId', 'ADM1'); H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.modification.enregistre = { toasts: H.toasts(), fiche: H.net(colSoi.all().find((r) => r.produit === 'Ceftriaxone')) };
      H.retirer(racine);
      H.remettre([colAdm, colSoi, colTa, colOrd], sauve);
      localStorage.setItem('sigh-cnt:session', session0);
      return out;
    });

    /* ------------------------------------------------------------------ administrations (règle de relais) */
    sortie.administrations = await m.page.evaluate(async () => { try {
      const S = SIGH.store, J = H.J, PR = SIGH.parcours;
      const colPre = S.collection('prescriptions'), colAd = S.collection('administrations', { module: 'M3', entite: 'administration de traitement', prefix: 'ADM' });
      const sauve = H.mettreDeCote([colPre, colAd]);
      const pats = S.collection('patients').active();
      const pres = (n, i, modalite, paiement, lignes, extra) => Object.assign({ id: 'PRS' + n, statut: 'en_cours', reference: 'PRS-0000' + n, type: 'ordonnance', origine: 'hospitalisation', date: '2026-08-14T09:00:00.000Z',
        patientId: pats[i].id, patientCode: pats[i].code, patient: pats[i].nom + ' ' + pats[i].prenom, prescripteur: 'BASSONGUI Chabi Séko', modalite, statutPaiement: paiement, lignes }, extra || {});
      const lg = (libelle, nb) => ({ libelle, quantite: 1, posologie: '1/j', duree: nb + ' jours', prix: 500, nbAdministrations: nb });
      const jeuPre = [
        pres(1, 0, 'hospitalisation', 'payee', [lg('Ceftriaxone 1 g', 3), lg('Perfusion de sérum', 1)]),
        pres(2, 1, 'hospitalisation', 'impayee', [lg('Métronidazole', 2)]),
        pres(3, 2, 'ambulatoire', 'payee', [lg('Injection IM', 2)]),
        pres(4, 3, 'hospitalisation', 'payee', [lg('Paracétamol IV', 2)]),
        pres(5, 0, 'hospitalisation', 'payee', [lg('Dernier passage', 2)], { statut: 'termine' }),
      ];
      jeuPre.forEach((x) => colPre.all().push(x));
      const ad = (n, presId, ligneIndex, rang, total, secteur, extra) => Object.assign({ id: 'AD' + n, statut: 'actif', reference: 'ADM-0000' + n, prescriptionId: presId, prescriptionRef: 'PRS-0000' + presId.slice(3),
        ligneIndex, libelle: 'Ligne ' + n, patientId: pats[0].id, patientCode: pats[0].code, patient: pats[0].nom + ' ' + pats[0].prenom, dateHeure: '2026-08-15T0' + n + ':00:00.000Z', rang, total, secteur, executantId: 'SOI06', executant: 'IDRISSOU ANIKI Baba-Toundé', observation: n === 2 ? 'RAS' : '', modalite: 'hospitalisation' }, extra || {});
      const jeuAd = [
        ad(1, 'PRS1', 0, 1, 3, 'salle_soins'),
        ad(2, 'PRS2', 0, 1, 2, 'salle_soins'),
        ad(3, 'PRS4', 0, 1, 2, 'salle_soins'),
        ad(4, 'PRS4', 0, 2, 2, 'hospitalisation'),
        ad(5, 'PRS1', 0, 2, 3, 'hospitalisation', { statut: 'archive' }),
      ];
      jeuAd.forEach((x) => colAd.all().push(x));
      const out = { prescriptions: H.propre(jeuPre), administrations: H.propre(jeuAd) };
      /* le moteur, appelé directement : refus nommés */
      const cas = (nom, presId, opts) => { const avant = colAd.all().length; let r; try { r = PR.administrer(presId, opts); } catch (e) { return { nom, presId, opts, resultat: { erreur: e.message }, ecrites: colAd.all().length - avant }; } return { nom, presId, opts, resultat: H.propre(Object.assign({}, r, { administration: r.administration ? H.net(r.administration) : undefined })), ecrites: colAd.all().length - avant }; };
      out.moteur = [
        cas('hospitalisation rang 2 attribué à l’hospitalisation', 'PRS1', { ligneIndex: 0, secteur: 'hospitalisation', executantId: 'SOI07', observation: 'Bien toléré' }),
        cas('même ligne, rang 3 : dernière administration', 'PRS1', { ligneIndex: 0, secteur: 'hospitalisation', executantId: 'SOI06' }),
        cas('ligne inexistante', 'PRS1', { ligneIndex: 5, secteur: 'hospitalisation' }),
        cas('prescription inexistante', 'PRSX', { ligneIndex: 0, secteur: 'hospitalisation' }),
        cas('première administration d’un traitement hospitalier : salle de soins, pas l’hospitalisation', 'PRS1', { ligneIndex: 1, secteur: 'hospitalisation', executantId: 'SOI06' }),
        cas('ambulatoire : toujours la salle de soins', 'PRS3', { ligneIndex: 0, secteur: 'hospitalisation', executantId: 'SOI06' }),
        cas('non réglée', 'PRS2', { ligneIndex: 0, secteur: 'hospitalisation', executantId: 'SOI06' }),
        cas('exécutant qui n’exécute pas (médecin)', 'PRS4', { ligneIndex: 0, secteur: 'hospitalisation', executantId: 'SOI01' }),
        cas('sans poste déclaré : le secteur attendu s’applique', 'PRS3', { ligneIndex: 0, executantId: 'SOI06' }),
      ];
      out.apresMoteur = { prescriptions: H.propre(colPre.all().map((p) => ({ id: p.id, statut: p.statut }))), nbAdministrations: colAd.all().length };
      /* remise à l'état de départ pour piloter l'écran */
      colPre.all().splice(0); colAd.all().splice(0);
      jeuPre.forEach((x) => colPre.all().push(x)); jeuAd.forEach((x) => colAd.all().push(x));
      let racine = await H.monter('m3-administrations');
      out.ecran = { kpis: H.kpis(racine), notes: H.notes(racine), tableaux: H.tableaux(racine), boutons: H.boutons(racine).slice(0, 14) };
      const onglets = [...racine.querySelectorAll('[role=tab]')];
      out.ecran.onglets = onglets.map((t) => H.norm(t.textContent));
      const ligne = (txt) => [...racine.querySelectorAll('tbody tr')].find((tr) => tr.innerText.includes(txt));
      if (!ligne('PRS-00002')) throw new Error('lignes : ' + H.norm(racine.innerText).slice(0, 900));
      out.ecran.boutonsLigneBloquee = [...ligne('PRS-00002').querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title || H.norm(b.textContent));
      H.viderToasts(); H.icone(ligne('PRS-00002'), 'Bloquée : la prescription n’est pas réglée').click(); await H.dormir(250);
      out.bloquee = { toasts: H.toasts() };
      onglets[1].click(); await H.dormir(250);
      out.historique = { tableaux: H.tableaux(racine) };
      onglets[0].click(); await H.dormir(250);
      /* administrer */
      [...ligne('PRS-00001').querySelectorAll('button')].find((b) => H.norm(b.textContent) === 'Administrer').click(); await H.dormir(250);
      out.modale = { texte: H.tiroir().texte, champs: H.champs(), options: H.optsDe('executantId'), defauts: { executantId: document.getElementById('f_executantId').value, observation: document.getElementById('f_observation').value } };
      H.poser('executantId', 'SOI07'); H.poser('observation', 'Bien toléré');
      H.viderToasts(); H.cliquer('Confirmer l’administration'); await H.dormir(300);
      out.administre = { toasts: H.toasts(), fiche: H.net(colAd.all().find((a) => a.observation === 'Bien toléré')) };
      out.apres = { kpis: H.kpis(racine), tableaux: H.tableaux(racine) };
      H.retirer(racine);
      colPre.all().splice(0); colAd.all().splice(0);
      racine = await H.monter('m3-administrations');
      out.vide = { kpis: H.kpis(racine), texte: H.norm(racine.innerText).slice(0, 700) };
      H.retirer(racine);
      H.remettre([colPre, colAd], sauve);
      return out;
    } catch (e) { throw new Error('ADM ' + e.stack); } });

    /* ------------------------------------------------------------------ fiche de surveillance (courbe à cinq échelles) */
    sortie.surveillance = await m.page.evaluate(async () => {
      const S = SIGH.store, J = H.J;
      const colAdm = S.collection('admissions'), colRel = S.collection('releves', { module: 'M3', entite: 'FeuilleTemperature' }), colCst = S.collection('constantes', { module: 'M1', entite: 'relevé de constantes', prefix: 'CST' });
      const sauve = H.mettreDeCote([colAdm, colRel, colCst]);
      const pats = S.collection('patients').active();
      const adm = (n, i) => ({ id: 'ADM' + n, statut: 'en_cours', reference: 'H' + String(n).padStart(5, '0'), patientId: pats[i].id, patient: pats[i].nom + ' ' + pats[i].prenom, patientCode: pats[i].code, chambre: 'A1', lit: 'A1 LIT' + n, typeChambre: 'standard', dateEntree: J(-9), dateSortie: null, diagnosticEntree: 'D', symptomes: '', priseEnCharge: 'plus_8h', infirmier: 'GARBA Yahouza' });
      [adm(1, 0), adm(2, 1)].forEach((x) => colAdm.all().push(x));
      const cst = (n, i, jour, heure, t, sys, pouls, fr, spo2, diurese) => ({ id: 'CST' + n, statut: 'actif', reference: 'CST-0000' + n, patientId: pats[i].id, patientCode: pats[i].code, patient: pats[i].nom + ' ' + pats[i].prenom,
        dateHeure: J(jour) + 'T' + heure, temperature: t, tensionSys: sys, tension: sys == null ? null : sys + '/8', pouls, fr, spo2, diurese, releveePar: 'SANNI Bibata', origine: 'accueil' });
      const rel = (n, adId, jour, heure, t, ta, fc, fr, spo2, diurese) => ({ id: 'REL' + n, statut: 'actif', admissionId: adId, date: J(jour), heure, temperature: t, tension: ta, fc, spo2, fr, diurese, poids: 60, taille: 170, traitement: '', saisiPar: 'DOSSOU Moussa' });
      const jeuCst = [cst(1, 0, -9, '09:30', 38.9, 13, 118, 28, 94, 0.5), cst(2, 0, -9, '15:00', 39.4, 14, 150, 30, 92, 0.7), cst(3, 2, -2, '09:00', 37, 12, 80, 18, 98, 1)];
      const jeuRel = [
        rel(1, 'ADM1', -9, '08:00', 38.2, '12/8', 100, 24, 96, 800), rel(2, 'ADM1', -8, '19:00', 36.5, '11/7', 50, null, 99, 2600), rel(3, 'ADM1', -7, '08:00', 42, '16/10', 180, 70, 90, 0),
        rel(4, 'ADM1', -6, '13:00', 37.5, '10/6', 140, 10, 97, 1250), rel(5, 'ADM1', -5, '08:30', 37, '9/5', 130, 20, 98, 500), rel(6, 'ADM1', -4, '23:00', 38.5, '12/8', 90, 50, 95, 1500),
        rel(7, 'ADM1', -3, '10:59', 39, '13/9', 110, null, 94, 2000), rel(8, 'ADM1', -2, '17:00', 40, '', 120, 35, 93, null), rel(9, 'ADM1', -1, '08:00', 36, '14/9', 160, 12, 97, 100),
        rel(10, 'ADM2', 0, '08:00', 37.1, '12/8', 70, 16, 99, 1200), rel(11, 'ADM2', -1, '14:00', 38.1, '12/7', 88, 22, 97, 1000),
      ];
      jeuCst.forEach((x) => colCst.all().push(x)); jeuRel.forEach((x) => colRel.all().push(x));
      const out = { constantes: H.propre(jeuCst), releves: H.propre(jeuRel), patients: pats.slice(0, 3).map((p) => ({ id: p.id, code: p.code, nom: p.nom, prenom: p.prenom })) };
      const racine = await H.monter('m3-surveillance');
      const dessin = () => {
        const svg = [...racine.querySelectorAll('svg')].find((x) => Number(x.getAttribute('height')) > 100);
        const tx = [...svg.querySelectorAll('text')].map((t) => ({ x: Number(t.getAttribute('x')), y: Number(t.getAttribute('y')), t: t.textContent }));
        return { largeur: Number(svg.getAttribute('width')), hauteur: Number(svg.getAttribute('height')), lignes: [...svg.querySelectorAll('line')].map((l) => [l.getAttribute('x1'), l.getAttribute('y1'), l.getAttribute('x2'), l.getAttribute('y2'), l.getAttribute('stroke')]),
          textes: tx, polylignes: [...svg.querySelectorAll('polyline')].map((p) => ({ points: p.getAttribute('points'), couleur: p.getAttribute('stroke') })),
          cercles: [...svg.querySelectorAll('circle')].map((c) => [c.getAttribute('cx'), c.getAttribute('cy'), c.getAttribute('fill')]) };
      };
      const sel = racine.querySelector('select');
      out.options = [...sel.options].map((o) => [o.value, H.norm(o.textContent)]);
      out.premier = { kpis: H.kpis(racine), cartes: H.cartes(racine), tableaux: H.tableaux(racine), dessin: dessin(), texteCarte: H.norm([...racine.querySelectorAll('svg')].find((x) => Number(x.getAttribute('height')) > 100).parentElement.parentElement.innerText) };
      sel.value = out.options[1][0]; sel.dispatchEvent(new Event('change')); await H.dormir(250);
      out.second = { cartes: H.cartes(racine), tableaux: H.tableaux(racine), dessin: dessin() };
      H.retirer(racine);
      colAdm.all().splice(0); colRel.all().splice(0); colCst.all().splice(0);
      const racine2 = await H.monter('m3-surveillance');
      out.vide = { texte: H.norm(racine2.innerText) };
      H.retirer(racine2);
      H.remettre([colAdm, colRel, colCst], sauve);
      return out;
    });

    /* ------------------------------------------------------------------ surveillance transfusionnelle */
    sortie.transfusion = await m.page.evaluate(async () => {
      const S = SIGH.store, J = H.J;
      const col4 = S.collection('surveillancesTransfusion', { module: 'M3', entite: 'surveillance transfusionnelle', prefix: 'TRF' });
      const sauve = H.mettreDeCote([col4]);
      const pats = S.collection('patients').active();
      window.__alertes = []; const alerter0 = SIGH.ui.alerter; SIGH.ui.alerter = function (msg, o) { window.__alertes.push([msg, o || null]); return alerter0.apply(this, arguments); };
      window.__erreursClic = []; window.addEventListener('error', (e) => window.__erreursClic.push(e.message));
      const T = ['t0', 't15', 't30', 't60', 't90', 'fin', 'h1', 'h2'], E = ['temperature', 'ta', 'fr', 'fc', 'spo2', 'urines', 'conscience', 'autre'];
      const valeurs = (n) => { const v = {}; T.slice(0, n).forEach((t) => { v[t] = {}; E.forEach((e) => { v[t][e] = e === 'ta' ? '12/8' : (e === 'urines' ? 'claires' : (e === 'autre' ? '' : '3' + n)); }); }); return v; };
      const rec = (n, i, relevesN, incident, extra) => Object.assign({ id: 'TRF' + n, statut: 'actif', reference: 'TRF-000' + n, patientId: pats[i].id, patient: pats[i].nom + ' ' + pats[i].prenom, patientCode: pats[i].code, service: 'Service ' + n, date: J(-n),
        pochePSL: 'PSL-' + n, debut: '0' + n + 'h15', responsableId: 'SOI06', responsable: 'IDRISSOU ANIKI Baba-Toundé', valeurs: valeurs(relevesN), releves: relevesN, attendus: 8, incident, natureIncident: incident ? 'Frissons' : '', conclusion: 'Conclusion ' + n }, extra || {});
      const jeu = [rec(1, 0, 8, false), rec(2, 1, 5, true), rec(3, 2, 8, false, { statut: 'archive' })];
      jeu.forEach((x) => col4.all().push(x));
      const out = { jeu: H.propre(jeu), patients: pats.slice(0, 3).map((p) => ({ id: p.id, code: p.code, nom: p.nom, prenom: p.prenom })) };
      let racine = await H.monter('m3-transfusion');
      out.ecran = { kpis: H.kpis(racine), notes: H.notes(racine), tableaux: H.tableaux(racine), boutons: H.boutons(racine).slice(0, 14) };
      const lig = (ref) => [...racine.querySelectorAll('tbody tr')].find((tr) => tr.innerText.includes(ref));
      out.ecran.boutonsLigne = [...lig('TRF-0002').querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
      H.icone(lig('TRF-0002'), 'Consulter').click(); await H.dormir(300);
      out.detail = Object.assign(H.tiroir(), { tables: H.tableaux(document.querySelector('[role=dialog], .drawer-root') || document.body) });
      H.fermerTout();
      H.icone(lig('TRF-0001'), 'Consulter').click(); await H.dormir(300);
      out.detailSansIncident = { texte: H.tiroir().texte }; H.fermerTout();
      const avantErr = window.__erreursClic.length;
      H.icone(lig('TRF-0001'), 'Modifier').click(); await H.dormir(300);
      out.modifier = { erreurs: window.__erreursClic.slice(avantErr), dialogue: !!document.querySelector('[role=dialog]') };
      H.fermerTout();
      /* nouvelle surveillance */
      H.bouton(racine, 'Nouvelle surveillance').click(); await H.dormir(300);
      const champsModale = H.champs();
      out.creation = { nbChamps: champsModale.length, champs: champsModale, sections: [...document.querySelectorAll('[role=dialog] h3, [role=dialog] h4, [role=dialog] .section-title, [role=dialog] legend')].map((x) => H.norm(x.textContent)), defauts: {} };
      for (const n of ['patientCode', 'service', 'date', 'pochePSL', 'debut', 'responsableId', 't0_temperature', 'h2_autre', 'incident', 'natureIncident', 'conclusion']) { const e = document.getElementById('f_' + n); out.creation.defauts[n] = e ? (e.type === 'checkbox' ? e.checked : e.value) : '(absent)'; }
      out.creation.optionsResponsable = H.optsDe('responsableId');
      out.creation.optionsPatient = (H.optsDe('patientCode') || []).slice(0, 3);
      H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(200);
      out.creation.refusVide = { toasts: H.toasts(), total: col4.all().length };
      H.poser('patientCode', pats[1].code); H.poser('service', 'Médecine'); H.poser('pochePSL', 'PSL-900'); H.poser('debut', '08h30'); H.poser('conclusion', 'RAS');
      H.poser('t0_temperature', '37.0'); H.poser('t0_ta', '12/8'); H.poser('t15_temperature', '37.2'); H.poser('fin_conscience', 'normale'); H.poser('h2_autre', 'x');
      H.viderToasts(); window.__alertes.length = 0; H.cliquer('Enregistrer'); await H.dormir(300);
      out.creation.partielle = { toasts: H.toasts(), alertes: window.__alertes.slice(), fiche: H.net(col4.all().find((r) => r.pochePSL === 'PSL-900')), total: col4.all().length };
      H.bouton(racine, 'Nouvelle surveillance').click(); await H.dormir(300);
      H.poser('patientCode', pats[2].code); H.poser('service', 'Urgences'); H.poser('pochePSL', 'PSL-901'); H.poser('debut', '09h00'); H.poser('conclusion', 'Frissons à 30 min');
      ['t0', 't15', 't30', 't60', 't90', 'fin', 'h1', 'h2'].forEach((t) => H.poser(t + '_temperature', '37'));
      H.poser('incident', true); H.poser('natureIncident', 'Frissons');
      H.viderToasts(); window.__alertes.length = 0; H.cliquer('Enregistrer'); await H.dormir(300);
      out.creation.complete = { toasts: H.toasts(), alertes: window.__alertes.slice(), fiche: H.net(col4.all().find((r) => r.pochePSL === 'PSL-901')) };
      out.apres = { kpis: H.kpis(racine), tableaux: H.tableaux(racine) };
      /* archivage d'une surveillance */
      H.viderToasts(); H.icone(lig('TRF-0001'), 'Archiver').click(); await H.dormir(250);
      out.archivage = { dialogue: H.tiroir().texte };
      H.fermerTout();
      H.retirer(racine);
      col4.all().splice(0);
      racine = await H.monter('m3-transfusion');
      out.vide = { kpis: H.kpis(racine), texte: H.norm(racine.innerText).slice(0, 900) };
      H.retirer(racine);
      H.remettre([col4], sauve);
      SIGH.ui.alerter = alerter0;
      return out;
    });

    /* ------------------------------------------------------------------ score de Glasgow */
    sortie.glasgow = await m.page.evaluate(async () => {
      const S = SIGH.store, J = H.J;
      const col5 = S.collection('scoresGlasgow', { module: 'M3', entite: 'score de Glasgow', prefix: 'GCS' });
      const sauve = H.mettreDeCote([col5]);
      const pats = S.collection('patients').active();
      window.__erreursClic = window.__erreursClic || [];
      const ax = (a, b, c) => [{ axe: 'Ouverture des yeux', libelle: 'x', points: a }, { axe: 'Réponse verbale', libelle: 'y', points: b }, { axe: 'Réponse motrice', libelle: 'z', points: c }];
      const rec = (n, i, a, b, c, extra) => Object.assign({ id: 'GCS' + n, statut: 'actif', reference: 'GCS-000' + n, patientId: pats[i].id, patient: pats[i].nom + ' ' + pats[i].prenom, nip: pats[i].code, dateHeure: J(-n) + 'T1' + n + ':00',
        axes: ax(a, b, c), score: a + b + c, evaluePar: 'SOI06', evaluateur: 'IDRISSOU ANIKI Baba-Toundé', observation: n === 1 ? 'Stable' : '' }, extra || {});
      const jeu = [rec(1, 0, 4, 5, 6), rec(2, 1, 3, 4, 5), rec(3, 2, 2, 2, 3), rec(4, 0, 1, 1, 1), rec(5, 1, 4, 5, 6, { statut: 'archive' }), rec(6, 2, 3, 3, 4)];
      jeu.forEach((x) => col5.all().push(x));
      const out = { jeu: H.propre(jeu) };
      let racine = await H.monter('m3-glasgow');
      out.ecran = { kpis: H.kpis(racine), notes: H.notes(racine), tableaux: H.tableaux(racine), boutons: H.boutons(racine).slice(0, 14),
        badges: [...racine.querySelectorAll('tbody tr')].map((tr) => (tr.querySelector('.badge') || tr.querySelector('span[class*=badge]') || { className: '' }).className) };
      const lig = (ref) => [...racine.querySelectorAll('tbody tr')].find((tr) => tr.innerText.includes(ref));
      out.ecran.boutonsLigne = [...lig('GCS-0001').querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
      H.icone(lig('GCS-0003'), 'Consulter').click(); await H.dormir(300);
      out.detail = Object.assign(H.tiroir(), { tables: H.tableaux(document.querySelector('[role=dialog], .drawer-root') || document.body) });
      H.fermerTout();
      H.bouton(racine, 'Nouvelle évaluation').click(); await H.dormir(300);
      out.creation = { champs: H.champs(), defauts: {} };
      for (const n of ['patientCode', 'nip', 'dateHeure', 'axe0', 'axe1', 'axe2', 'observation', 'evaluePar']) { const e = document.getElementById('f_' + n); out.creation.defauts[n] = e ? e.value : '(absent)'; }
      out.creation.optionsAxes = ['axe0', 'axe1', 'axe2'].map((n) => H.optsDe(n));
      out.creation.optionsEvaluateur = H.optsDe('evaluePar');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(200);
      out.creation.refusSansDate = { toasts: H.toasts(), total: col5.all().length };
      H.poser('patientCode', pats[1].code); H.poser('dateHeure', '2026-08-16T09:00'); H.poser('axe0', '2'); H.poser('axe1', '3'); H.poser('axe2', '4'); H.poser('observation', 'Obnubilé'); H.poser('nip', '');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.creation.cree = { toasts: H.toasts(), fiche: H.net(col5.all().find((r) => r.observation === 'Obnubilé')), total: col5.all().length };
      out.apres = { kpis: H.kpis(racine), tableaux: H.tableaux(racine) };
      /* première évaluation avec les valeurs PAR DÉFAUT (axes présélectionnés) */
      H.bouton(racine, 'Nouvelle évaluation').click(); await H.dormir(300);
      H.poser('dateHeure', '2026-08-16T09:30'); H.poser('nip', 'NIP-77');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.creation.defautsAxes = { fiche: H.net(col5.all().find((r) => r.nip === 'NIP-77')) };
      /* modification */
      H.icone(lig('GCS-0003'), 'Modifier').click(); await H.dormir(300);
      out.modification = { champs: H.champs(), valeurs: {} };
      for (const n of ['patientCode', 'nip', 'dateHeure', 'axe0', 'axe1', 'axe2', 'observation', 'evaluePar']) { const e = document.getElementById('f_' + n); out.modification.valeurs[n] = e ? e.value : '(absent)'; }
      H.poser('observation', 'Corrigée'); H.poser('axe0', '1');
      H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.modification.enregistre = { toasts: H.toasts(), fiche: H.net(col5.all().find((r) => r.id === 'GCS3')) };
      H.retirer(racine);
      H.remettre([col5], sauve);
      return out;
    });

/*BLOCS*/
    ecrire('packages/domaine/test/vecteurs/hospitalisation.json', sortie);
    if (m.erreurs.length) console.log('  erreurs JS de la page : ' + m.erreurs.slice(0, 5).join(' | '));
  } finally {
    await m.fermer();
  }
})().catch((e) => { console.error(e); process.exit(1); });
