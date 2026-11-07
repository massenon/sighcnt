/* =============================================================================
 * VECTEURS DU BLOC, DE L'ANESTHÉSIE ET DES SORTIES (M3) — m3-cpa, m3-bloc-cro, m3-cr-anesthesie, m3-bloc-checklist, m3-demande-examen,
 * m3-bons-pansements, m3-sorties, m3-sortie-avis-medical
 * -----------------------------------------------------------------------------
 * Les huit écrans sont montés TELS QUELS dans la page d'extraction, sur des jeux posés au magasin jetable ; on lit ce qu'ils AFFICHENT (KPI, tableaux,
 * notes), on PILOTE les modales et les tiroirs comme le fait l'agent (champs, valeurs par défaut, refus, création, modification, archivage), on
 * intercepte les pièces imprimées et l'on relit ce que les moteurs ont ÉCRIT (ordonnance, facture à lignes payables, demandes d'analyses, admission).
 *
 *   node build/vecteurs-bloc.js   →   packages/domaine/test/vecteurs/bloc.json
 *
 * L'horloge est fixée au 16/08/2026 : `C.aujourdhui()` ET `new Date()` à 10 h 00 locale.
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs bloc, anesthésie et sorties (M3)');
  const m = await ouvrirMaquette();
  try {
    await m.page.evaluate(() => {
      SIGH.core.aujourdhui = () => new Date(2026, 7, 16, 10, 0, 0);
      const Vrai = Date;
      const FIXE = new Vrai(2026, 7, 16, 10, 0, 0).getTime();
      class Faux extends Vrai { constructor(...a) { if (a.length === 0) super(FIXE); else super(...a); } static now() { return FIXE; } }
      window.Date = Faux;
      window.__etats = []; window.__erreurs = []; window.addEventListener('error', (e) => window.__erreurs.push(String(e.message)));
      SIGH.print.etat = function (o) {
        const tab = [];
        const c = o.contenu;
        if (c && c.querySelectorAll) {
          c.querySelectorAll('table').forEach((t) => tab.push({
            entetes: [...t.querySelectorAll('thead th')].map((x) => x.innerText.replace(/\s+/g, ' ').trim()),
            lignes: [...t.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => td.innerText.replace(/\s+/g, ' ').trim())),
            pied: [...t.querySelectorAll('tfoot tr')].map((tr) => [...tr.children].map((td) => td.innerText.replace(/\s+/g, ' ').trim())),
          }));
        }
        window.__etats.push(JSON.parse(JSON.stringify({
          titre: o.titre, sousTitre: o.sousTitre || null, cartouche: o.cartouche || null, signatures: o.signatures || null,
          texte: c && c.innerText ? c.innerText.replace(/\s+/g, ' ').trim() : null, tableaux: tab,
        })));
      };
    });
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m3-hospitalisation.js') });

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
        valeur: (id) => { const e = document.getElementById('f_' + id); return e ? (e.type === 'checkbox' ? e.checked : e.value) : '(absent)'; },
        cliquer: (texte) => { const bs = [...document.querySelectorAll('button')].filter((b) => b.textContent.trim() === texte); bs[bs.length - 1].click(); },
        icone: (ligne, nom) => [...ligne.querySelectorAll('button')].find((b) => (b.getAttribute('aria-label') || b.title) === nom),
        boutons: (racine) => [...racine.querySelectorAll('button')].map((b) => norm(b.textContent || b.getAttribute('aria-label') || b.title)).filter(Boolean),
        tiroir: () => { const t = document.querySelector('[role=dialog], .drawer-root') || document.body; return { texte: norm(t.innerText), boutons: [...t.querySelectorAll('button')].map((b) => norm(b.textContent || b.getAttribute('aria-label') || b.title)).filter(Boolean) }; },
        modale: () => norm((document.querySelector('.modal-root, [role=dialog]') || { innerText: '' }).innerText),
        monter: async (id) => {
          const root = document.createElement('div'); document.body.appendChild(root);
          window.__etats.length = 0;
          SIGH.screens[id].render(root);
          await new Promise((r) => setTimeout(r, 300));
          return root;
        },
        retirer: (root) => { root.remove(); H.fermerTout(); },
        mettreDeCote: (cols) => { const sauve = {}; cols.forEach((c) => { sauve[c.name] = c.all().splice(0); }); return sauve; },
        remettre: (cols, sauve) => { cols.forEach((c) => { c.all().splice(0); (sauve[c.name] || []).forEach((x) => c.all().push(x)); }); },
        J: (n) => { const d = new Date(2026, 7, 16 + n); return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'); },
        ligne: (racine, texte) => [...racine.querySelectorAll('tbody tr')].find((tr) => tr.innerText.includes(texte)),
        confirmer: async (motif) => {
          await H.dormir(250);
          const zone = document.querySelector('[role=dialog], .modal-root');
          const ta = zone && (zone.querySelector('textarea') || zone.querySelector('input[type=text]'));
          if (ta) { ta.value = motif; ta.dispatchEvent(new Event('input')); }
          const btns = zone ? [...zone.querySelectorAll('button')] : [];
          const ok = btns.find((b) => b.textContent.trim() === 'Archiver');
          if (ok) ok.click();
          await H.dormir(250);
        },
      };
    });

    const sortie = { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-bloc.js — ne pas éditer. Horloge : 16/08/2026 10 h.' };

    /* ------------------------------------------------------------------ référentiels (lus sur les listes des modales réelles) */
    sortie.referentiels = await m.page.evaluate(async () => {
      const S = SIGH.store, D = SIGH.data, L = SIGH.labo;
      const cols = ['cpa', 'crAnesthesie', 'crOperatoires', 'checklistsBloc'].map((n) => S.collection(n));
      const sauve = H.mettreDeCote(cols);
      const out = {};
      let racine = await H.monter('m3-cpa');   // vide : amorce 6 CPA, on les retire aussitôt pour lire les listes
      H.bouton(racine, 'Nouvelle CPA').click(); await H.dormir(300);
      out.cpaChamps = H.champs();
      out.asa = H.optsDe('asa'); out.mallampati = H.optsDe('mallampati'); out.techniques = H.optsDe('technique'); out.conclusions = H.optsDe('conclusion');
      out.cpaDefauts = {};
      ['patientCode', 'date', 'asa', 'mallampati', 'technique', 'antecedentsAnesthesiques', 'allergies', 'jeuneConsigne', 'conclusion', 'observations', 'anesthesiste'].forEach((n) => { out.cpaDefauts[n] = H.valeur(n); });
      H.retirer(racine);
      racine = await H.monter('m3-cr-anesthesie');
      H.bouton(racine, 'Nouveau compte rendu').click(); await H.dormir(300);
      out.craChamps = H.champs(); out.decisions = H.optsDe('decisionSortie'); out.craTechniques = H.optsDe('technique');
      out.craDefauts = {};
      ['patientCode', 'dateOperation', 'croReference', 'technique', 'decisionSortie'].forEach((n) => { out.craDefauts[n] = H.valeur(n); });
      H.retirer(racine);
      out.checklist = { entree: D.CHECKLIST_BLOC.entree, sortie: D.CHECKLIST_BLOC.sortie, aValider: D.CHECKLIST_BLOC.aValider, arreteLe: D.CHECKLIST_BLOC.arreteLe, arretePar: D.CHECKLIST_BLOC.arretePar };
      out.servicesDemandeurs = L.SERVICES_DEMANDEURS; out.niveauxUrgence = L.NIVEAUX_URGENCE;
      out.actesGyneco = (D.tarifParFamille ? D.tarifParFamille('GYNECO') : []).length;
      H.remettre(cols, sauve);
      return H.propre(out);
    });

    /* ------------------------------------------------------------------ amorçage de la CPA (jeu de démonstration) */
    sortie.amorcageCpa = await m.page.evaluate(async () => {
      const S = SIGH.store, J = H.J;
      const colAdm = S.collection('admissions'), colCpa = S.collection('cpa');
      const sauve = H.mettreDeCote([colAdm, colCpa]);
      const pats = S.collection('patients').active();
      for (let i = 0; i < 8; i++) {
        colAdm.all().push({ id: 'ADM' + (i + 1), statut: i === 7 ? 'sortie' : 'en_cours', reference: 'H0000' + (i + 1), patientId: pats[i].id, patient: pats[i].nom + ' ' + pats[i].prenom, patientCode: pats[i].code,
          chambre: 'A1', lit: 'A1 LIT1', dateEntree: J(-(i + 1)), dateSortie: null, diagnosticEntree: 'D' + i, infirmier: 'GARBA Yahouza' });
      }
      const racine = await H.monter('m3-cpa');
      const out = { admissions: H.propre(colAdm.all()), cpa: H.propre(colCpa.all().map(H.net)), kpis: H.kpis(racine), tableaux: H.tableaux(racine) };
      H.retirer(racine);
      H.remettre([colAdm, colCpa], sauve);
      return out;
    });

    /* ------------------------------------------------------------------ CPA + CRO : écran, création, refus, modification, archivage */
    sortie.cpa = await m.page.evaluate(async () => {
      const S = SIGH.store, J = H.J;
      const colCpa = S.collection('cpa'), colCro = S.collection('crOperatoires');
      const sauve = H.mettreDeCote([colCpa, colCro]);
      const pats = S.collection('patients').active();
      const p = (i) => ({ patientId: pats[i].id, patient: pats[i].nom + ' ' + pats[i].prenom, patientCode: pats[i].code });
      const cpa = (n, i, asa, conclusion, obs) => Object.assign({ id: 'CPA' + n, statut: 'actif', reference: 'CPA-2026-000' + n, date: J(-n), asa, mallampati: 'II', technique: 'Rachianesthésie',
        antecedentsAnesthesiques: 'Aucun', allergies: 'Aucune connue', jeuneConsigne: true, conclusion, observations: obs || '', anesthesiste: 'ADAM Colette' }, p(i));
      const cro = (n, i, date) => Object.assign({ id: 'CRO' + n, statut: 'actif', reference: 'CRO-000' + n, dateOperation: date, nip: 'N' + n, diagnosticPeroperatoire: 'D', intervention: 'I' + n, anesthesie: 'A', cro: 'Récit ' + n,
        operateurId: 'SOI03', operateur: 'TAKI Orou', anesthesisteId: 'SOI15', anesthesiste: 'ADAM Colette' }, p(i));
      [cpa(1, 0, 'I', 'Apte à l’anesthésie'), cpa(2, 1, 'III', 'Apte avec réserves', 'HTA à équilibrer'), cpa(3, 2, 'II', 'Intervention à reporter', 'Fièvre')].forEach((x) => colCpa.all().push(x));
      /* patients 0,1,2 ont une CPA ; 3 et 4 n'en ont pas : deux interventions sans CPA (le patient 3 compte deux CRO, 5 est sans patientId). */
      [cro(1, 0, J(-3)), cro(2, 3, J(-2)), cro(3, 3, J(-1)), cro(4, 4, J(-1)), Object.assign(cro(5, 0, J(0)), { patientId: null })].forEach((x) => colCro.all().push(x));
      const out = { jeu: { cpa: H.propre(colCpa.all()), cro: H.propre(colCro.all()) } };
      let racine = await H.monter('m3-cpa');
      out.ecran = { kpis: H.kpis(racine), notes: H.notes(racine), tableaux: H.tableaux(racine), boutons: H.boutons(racine).slice(0, 12) };
      out.ecran.boutonsLigne = [...H.ligne(racine, 'CPA-2026-0002').querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
      H.icone(H.ligne(racine, 'CPA-2026-0002'), 'Consulter').click(); await H.dormir(300);
      out.detail = H.tiroir(); H.fermerTout();
      H.icone(H.ligne(racine, 'CPA-2026-0002'), 'Imprimer la fiche').click(); await H.dormir(200);
      out.impression = H.propre(window.__etats[0]);
      /* création : valeurs par défaut, refus des réserves non nommées, puis succès */
      H.bouton(racine, 'Nouvelle CPA').click(); await H.dormir(300);
      out.creation = { modale: H.modale().slice(0, 200) };
      H.poser('patientCode', pats[1].code); H.poser('date', '2026-08-16'); H.poser('antecedentsAnesthesiques', 'Aucun'); H.poser('allergies', 'Aucune connue'); H.poser('anesthesiste', 'ADAM Colette');
      H.poser('conclusion', 'Apte avec réserves'); H.poser('observations', '');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(250);
      out.creation.refusReserves = { toasts: H.toasts(), total: colCpa.all().length };
      H.poser('observations', 'Hypertendue : équilibrer la tension');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.creation.creeAvecReserves = { toasts: H.toasts(), fiche: H.net(colCpa.all().find((x) => x.observations === 'Hypertendue : équilibrer la tension')), total: colCpa.all().length };
      out.creation.apres = { kpis: H.kpis(racine) };
      /* sans réserves : la CPA ne garde pas d'observations obligatoires */
      H.bouton(racine, 'Nouvelle CPA').click(); await H.dormir(300);
      H.poser('patientCode', pats[3].code); H.poser('date', '2026-08-16'); H.poser('antecedentsAnesthesiques', 'Aucun'); H.poser('allergies', 'Pénicilline'); H.poser('anesthesiste', 'ADAM Colette'); H.poser('jeuneConsigne', true);
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.creation.creeApte = { toasts: H.toasts(), fiche: H.net(colCpa.all().find((x) => x.allergies === 'Pénicilline')), kpis: H.kpis(racine) };
      /* modification : le contrôle métier vaut aussi à l'édition ; la référence et le patient ne sont PAS recalculés (pas de transform) */
      H.icone(H.ligne(racine, 'CPA-2026-0002'), 'Modifier').click(); await H.dormir(300);
      out.modification = { titre: H.modale().slice(0, 120), valeurs: {} };
      ['patientCode', 'date', 'asa', 'mallampati', 'technique', 'conclusion', 'observations', 'jeuneConsigne'].forEach((n) => { out.modification.valeurs[n] = H.valeur(n); });
      H.poser('observations', ''); H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(250);
      out.modification.refus = { toasts: H.toasts(), fiche: H.net(colCpa.all().find((x) => x.id === 'CPA2')) };
      H.poser('observations', 'HTA équilibrée'); H.poser('asa', 'IV'); H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.modification.enregistre = { toasts: H.toasts(), fiche: H.net(colCpa.all().find((x) => x.id === 'CPA2')) };
      /* changer le patient d'une CPA : le NOM porté par la fiche suit (E411) */
      H.icone(H.ligne(racine, 'CPA-2026-0001'), 'Modifier').click(); await H.dormir(300);
      H.poser('patientCode', pats[5].code); H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.modification.autrePatient = { fiche: H.net(colCpa.all().find((x) => x.id === 'CPA1')) };
      /* archivage avec motif */
      H.icone(H.ligne(racine, 'CPA-2026-0003'), 'Archiver').click(); await H.confirmer('Doublon');
      out.archivage = { toasts: H.toasts(), fiche: H.net(colCpa.all().find((x) => x.id === 'CPA3')), kpis: H.kpis(racine) };
      H.retirer(racine);

      /* --- compte rendu opératoire */
      racine = await H.monter('m3-bloc-cro');
      out.cro = { ecran: { kpis: H.kpis(racine), tableaux: H.tableaux(racine), boutons: H.boutons(racine).slice(0, 10) } };
      out.cro.ecran.boutonsLigne = [...H.ligne(racine, 'CRO-0001').querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
      H.icone(H.ligne(racine, 'CRO-0002'), 'Consulter').click(); await H.dormir(300);
      out.cro.detail = H.tiroir(); H.fermerTout();
      H.icone(H.ligne(racine, 'CRO-0002'), 'Imprimer le compte rendu').click(); await H.dormir(200);
      out.cro.impression = H.propre(window.__etats[0]);
      H.bouton(racine, 'Nouveau compte rendu').click(); await H.dormir(300);
      out.cro.creation = { champs: H.champs(), optsOperateur: H.optsDe('operateurId'), optsAide: H.optsDe('aideOperateurId'), optsAnesthesiste: H.optsDe('anesthesisteId'), defauts: {} };
      ['patientCode', 'nip', 'dateOperation', 'operateurId', 'aideOperateurId', 'anesthesisteId'].forEach((n) => { out.cro.creation.defauts[n] = H.valeur(n); });
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(250);
      out.cro.creation.refusVide = { toasts: H.toasts(), total: colCro.all().length };
      H.poser('patientCode', pats[2].code); H.poser('nip', 'NIP-9'); H.poser('dateOperation', '2026-08-16'); H.poser('diagnosticPeroperatoire', 'Kyste'); H.poser('intervention', 'Kystectomie');
      H.poser('anesthesie', 'Rachianesthésie'); H.poser('cro', 'Ligne 1\nLigne 2'); H.poser('operateurId', 'SOI03'); H.poser('aideOperateurId', 'SOI12'); H.poser('anesthesisteId', 'SOI15');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.cro.creation.cree = { toasts: H.toasts(), fiche: H.net(colCro.all().find((x) => x.nip === 'NIP-9')), kpis: H.kpis(racine) };
      H.bouton(racine, 'Nouveau compte rendu').click(); await H.dormir(300);
      H.poser('patientCode', pats[2].code); H.poser('nip', 'NIP-10'); H.poser('dateOperation', '2026-07-30'); H.poser('diagnosticPeroperatoire', 'x'); H.poser('intervention', 'y'); H.poser('anesthesie', 'z'); H.poser('cro', 'w');
      H.poser('operateurId', 'SOI03'); H.poser('aideOperateurId', ''); H.poser('anesthesisteId', 'SOI15');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.cro.creation.sansAide = { fiche: H.net(colCro.all().find((x) => x.nip === 'NIP-10')), kpis: H.kpis(racine) };
      /* modification : on change l'opérateur — le NOM porté par la fiche n'est pas recalculé (pas de transform à l'édition) */
      H.icone(H.ligne(racine, 'CRO-0002'), 'Modifier').click(); await H.dormir(300);
      H.poser('operateurId', 'SOI04'); H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.cro.modification = { toasts: H.toasts(), fiche: H.net(colCro.all().find((x) => x.id === 'CRO2')) };
      H.icone(H.ligne(racine, 'CRO-0003'), 'Archiver').click(); await H.confirmer('Erreur de saisie');
      out.cro.archivage = { toasts: H.toasts(), fiche: H.net(colCro.all().find((x) => x.id === 'CRO3')), kpis: H.kpis(racine) };
      H.retirer(racine);
      H.remettre([colCpa, colCro], sauve);
      return H.propre(out);
    });

    /* ------------------------------------------------------------------ compte rendu d'anesthésie */
    sortie.cra = await m.page.evaluate(async () => {
      const S = SIGH.store, J = H.J;
      const colCra = S.collection('crAnesthesie'), colCro = S.collection('crOperatoires'), colCpa = S.collection('cpa');
      const sauve = H.mettreDeCote([colCra, colCro, colCpa]);
      const pats = S.collection('patients').active();
      const p = (i) => ({ patientId: pats[i].id, patient: pats[i].nom + ' ' + pats[i].prenom, patientCode: pats[i].code });
      colCro.all().push(Object.assign({ id: 'CRO1', statut: 'actif', reference: 'CRO-0001', dateOperation: J(-1), nip: 'N', diagnosticPeroperatoire: 'D', intervention: 'I', anesthesie: 'A', cro: 'R', operateurId: 'SOI03', operateur: 'TAKI Orou', anesthesisteId: 'SOI15', anesthesiste: 'ADAM Colette' }, p(0)));
      colCpa.all().push({ id: 'CPAX', statut: 'actif', reference: 'CPA-2026-0001', date: J(-5), asa: 'I', conclusion: 'Apte à l’anesthésie' });   // évite l'amorçage
      const cra = (n, i, inc, dec, cro) => Object.assign({ id: 'CRA' + n, statut: 'actif', reference: 'CRA-2026-000' + n, dateOperation: J(-n), croReference: cro || '', technique: 'Rachianesthésie', agents: 'Bupivacaïne',
        heureInduction: '08:00', heureFin: '09:30', incidents: inc, surveillancePerop: n === 1 ? 'TA stable\nSpO2 98 %' : '', heureArriveeReveil: '09:40', etatReveil: 'Éveillé', decisionSortie: dec, anesthesiste: 'ADAM Colette' }, p(i));
      [cra(1, 0, 'Aucun incident', 'Retour dans le service', 'CRO-0001'), cra(2, 1, 'Hypotension transitoire traitée', 'Surveillance prolongée en salle de réveil'), cra(3, 2, 'aucun', 'Transfert / évacuation', 'CRO-0001'), cra(4, 1, 'Aucune difficulté', 'Retour dans le service')]
        .forEach((x) => colCra.all().push(x));
      const out = { jeu: { cra: H.propre(colCra.all()), cro: H.propre(colCro.all()), cpa: H.propre(colCpa.all()) } };
      let racine = await H.monter('m3-cr-anesthesie');
      out.ecran = { kpis: H.kpis(racine), notes: H.notes(racine), tableaux: H.tableaux(racine), boutons: H.boutons(racine).slice(0, 10) };
      out.ecran.boutonsLigne = [...H.ligne(racine, 'CRA-2026-0001').querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
      H.icone(H.ligne(racine, 'CRA-2026-0001'), 'Consulter').click(); await H.dormir(300);
      out.detail = H.tiroir(); H.fermerTout();
      H.icone(H.ligne(racine, 'CRA-2026-0001'), 'Imprimer le compte rendu').click(); await H.dormir(200);
      out.impression = H.propre(window.__etats[0]);
      H.bouton(racine, 'Nouveau compte rendu').click(); await H.dormir(300);
      out.creation = { optsCro: H.optsDe('croReference') };
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(250);
      out.creation.refusVide = { toasts: H.toasts(), total: colCra.all().length };
      H.poser('patientCode', pats[3].code); H.poser('dateOperation', '2026-08-16'); H.poser('croReference', 'CRO-0001'); H.poser('agents', 'Kétamine'); H.poser('heureInduction', '10:00'); H.poser('heureFin', '11:00');
      H.poser('incidents', 'Aucun incident'); H.poser('heureArriveeReveil', '11:10'); H.poser('etatReveil', 'Éveillé'); H.poser('decisionSortie', 'Surveillance prolongée en salle de réveil'); H.poser('anesthesiste', 'ADAM Colette');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.creation.cree = { toasts: H.toasts(), fiche: H.net(colCra.all().find((x) => x.agents === 'Kétamine')), kpis: H.kpis(racine) };
      H.icone(H.ligne(racine, 'CRA-2026-0004'), 'Modifier').click(); await H.dormir(300);
      H.poser('incidents', 'Désaturation brève'); H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.modification = { toasts: H.toasts(), fiche: H.net(colCra.all().find((x) => x.id === 'CRA4')), kpis: H.kpis(racine) };
      H.icone(H.ligne(racine, 'CRA-2026-0002'), 'Archiver').click(); await H.confirmer('Doublon');
      out.archivage = { fiche: H.net(colCra.all().find((x) => x.id === 'CRA2')), kpis: H.kpis(racine) };
      H.retirer(racine);
      H.remettre([colCra, colCro, colCpa], sauve);
      return H.propre(out);
    });

    /* ------------------------------------------------------------------ check-listes */
    sortie.checklist = await m.page.evaluate(async () => {
      const S = SIGH.store, J = H.J, D = SIGH.data;
      const col = S.collection('checklistsBloc');
      const sauve = H.mettreDeCote([col]);
      const pats = S.collection('patients').active();
      const rec = (n, moment, i, coches) => {
        const items = (moment === 'entree' ? D.CHECKLIST_BLOC.entree : D.CHECKLIST_BLOC.sortie).map((l, k) => ({ label: l, coche: k < coches }));
        return { id: 'CKL' + n, statut: 'actif', reference: 'CKL-000' + n, moment, dateHeure: J(-n) + 'T0' + n + ':00:00.000Z', patientId: pats[i].id, patient: pats[i].nom + ' ' + pats[i].prenom, responsableId: 'SOI14', responsable: 'BOUKARI Nadège', items, coches, total: items.length };
      };
      [rec(1, 'entree', 0, 12), rec(2, 'sortie', 0, 9), rec(3, 'entree', 1, 10), rec(4, 'sortie', 2, 4)].forEach((x) => col.all().push(x));
      const out = { jeu: H.propre(col.all()) };
      let racine = await H.monter('m3-bloc-checklist');
      out.ecran = { kpis: H.kpis(racine), notes: H.notes(racine), tableaux: H.tableaux(racine), boutons: H.boutons(racine).slice(0, 14), onglets: [...racine.querySelectorAll('[role=tab]')].map((t) => H.norm(t.innerText)) };
      out.ecran.boutonsLigne = [...racine.querySelectorAll('tbody tr')[0].querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
      H.icone(racine.querySelectorAll('tbody tr')[0], 'Consulter').click(); await H.dormir(300);
      out.detail = H.tiroir(); H.fermerTout();
      /* l'onglet « sortie » */
      [...racine.querySelectorAll('[role=tab]')].find((t) => t.innerText.includes('de sortie')).click(); await H.dormir(250);
      out.sortieOnglet = { tableaux: H.tableaux(racine), boutons: H.boutons(racine).slice(0, 14) };
      /* remplir la check-liste de sortie, partiellement */
      H.bouton(racine, 'Remplir la check-liste').click(); await H.dormir(300);
      out.remplirSortie = { champs: H.champs(), titre: H.modale().slice(0, 140), optsResponsable: H.optsDe('responsableId') };
      /* le patient et le responsable sont PRÉSÉLECTIONNÉS (liste obligatoire) : rien de coché s'enregistre, signalé */
      const avant0 = col.all().length;
      H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.remplirSortie.rienCoche = { toasts: H.toasts(), fiche: H.net(col.all().find((x) => x.coches === 0 && x.moment === 'sortie')), total: col.all().length - avant0, kpis: H.kpis(racine) };
      [...racine.querySelectorAll('[role=tab]')].find((t) => t.innerText.includes('de sortie')).click(); await H.dormir(250);
      H.bouton(racine, 'Remplir la check-liste').click(); await H.dormir(300);
      H.poser('patientCode', pats[3].code); H.poser('responsableId', 'SOI14'); H.poser('it0', true); H.poser('it1', true); H.poser('it2', true);
      H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.remplirSortie.incomplete = { toasts: H.toasts(), fiche: H.net(col.all().find((x) => x.coches === 3 && x.moment === 'sortie')), kpis: H.kpis(racine) };
      /* entrée complète */
      [...racine.querySelectorAll('[role=tab]')].find((t) => t.innerText.includes('d’entrée')).click(); await H.dormir(250);
      H.bouton(racine, 'Remplir la check-liste').click(); await H.dormir(300);
      H.poser('patientCode', pats[4].code); H.poser('responsableId', 'SOI15');
      for (let k = 0; k < D.CHECKLIST_BLOC.entree.length; k++) H.poser('it' + k, true);
      H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.remplirEntree = { toasts: H.toasts(), fiche: H.net(col.all().find((x) => x.moment === 'entree' && x.coches === 12 && x.id !== 'CKL1')), kpis: H.kpis(racine) };
      /* « Modifier » d'une ligne : la déclaration passe `champs = null` à K.actionsLigne */
      window.__erreurs.length = 0;
      try { H.icone(racine.querySelectorAll('tbody tr')[0], 'Modifier').click(); } catch (e) { window.__erreurs.push('clic : ' + e.message); }
      await H.dormir(300);
      out.modifier = { erreurs: window.__erreurs.slice(), modale: H.modale().slice(0, 120) };
      H.retirer(racine);
      H.remettre([col], sauve);
      return H.propre(out);
    });

    /* ------------------------------------------------------------------ fiche de demande d'examen du service */
    sortie.demandeExamen = await m.page.evaluate(async () => {
      const S = SIGH.store, J = H.J, L = SIGH.labo, D = SIGH.data;
      const cols = ['demandesAnalyses', 'factures', 'taches'].map((n) => S.collection(n));
      const sauve = H.mettreDeCote(cols);
      const colD = cols[0], colF = cols[1], colT = cols[2];
      const pats = S.collection('patients').active();
      const dem = (n, o) => Object.assign({ id: 'D' + n, statut: 'actif', reference: 'LAB-0000' + n, codeAnalyse: '0000' + n + '-2026', patientId: pats[0].id, patientCode: pats[0].code, patient: pats[0].nom + ' ' + pats[0].prenom, analyseCode: 'L24', analyse: 'NFS', categorie: 'Hématologie',
        prix: 4000, dateHeure: '2026-08-0' + n + 'T10:00:00.000Z', prescripteur: 'Dr X', origine: 'service', origineDemande: 'service', serviceDemandeur: 'maternite', etatAnalyse: 'en_attente', urgent: n === 2 }, o || {});
      [dem(1), dem(2, { etatAnalyse: 'attente_prelevement' }), dem(3, { etatAnalyse: 'valide' }), dem(4, { origine: 'ordonnance', origineDemande: 'consultation' }), dem(5, { etatAnalyse: 'valide_technique' })].forEach((x) => colD.all().push(x));
      const out = { jeu: H.propre(colD.all()) };
      let racine = await H.monter('m3-demande-examen');
      out.ecran = { kpis: H.kpis(racine), cartes: H.cartes(racine), tableaux: H.tableaux(racine), boutons: H.boutons(racine).slice(0, 10) };
      H.bouton(racine, 'Nouvelle fiche de demande').click(); await H.dormir(300);
      out.modale = { champs: H.champs(), titre: H.modale().slice(0, 160), defauts: {}, optsService: H.optsDe('serviceDemandeur'), optsUrgence: H.optsDe('urgence'), optsPrescripteur: H.optsDe('prescripteur') };
      ['patientCode', 'residence', 'serviceDemandeur', 'prescripteur', 'urgence', 'examenUrgent', 'hospitalise', 'indication'].forEach((n) => { out.modale.defauts[n] = H.valeur(n); });
      const ana = D.ANALYSES.filter((a) => a.prix).slice(0, 3);
      out.analyses = H.propre(ana.map((a) => ({ code: a.code, designation: a.designation, prix: a.prix, echantillon: a.echantillon })));
      H.viderToasts(); H.cliquer('Émettre la fiche'); await H.dormir(250);
      out.refusVide = { toasts: H.toasts(), demandes: colD.all().length };
      const base = (o) => { Object.entries(Object.assign({ patientCode: pats[1].code, residence: 'Natitingou', serviceDemandeur: 'maternite', prescripteur: 'BASSONGUI Chabi Séko', indication: 'Anémie', analyses: [ana[0].code, ana[1].code], urgence: 'aucune' }, o)).forEach(([k, v]) => H.poser(k, v)); };
      base({ urgence: 'examen', examenUrgent: '' });
      H.viderToasts(); H.cliquer('Émettre la fiche'); await H.dormir(250);
      out.refusExamenNonNomme = { toasts: H.toasts(), demandes: colD.all().length };
      const avant = (c) => new Set(c.all().map((x) => x.id));
      const ids = { d: avant(colD), f: avant(colF), t: avant(colT) };
      base({ urgence: 'examen', examenUrgent: ana[1].code, hospitalise: true });
      H.viderToasts(); H.cliquer('Émettre la fiche'); await H.dormir(400);
      const neuf = (c, s) => c.all().filter((x) => !s.has(x.id)).map(H.net);
      out.emission = { toasts: H.toasts(), demandes: neuf(colD, ids.d), factures: neuf(colF, ids.f), taches: neuf(colT, ids.t), impression: window.__etats[window.__etats.length - 1], kpis: H.kpis(racine) };
      /* service « médecine » : pas de secteur demandeur ; bilan entier */
      H.bouton(racine, 'Nouvelle fiche de demande').click(); await H.dormir(300);
      const ids2 = { d: avant(colD) };
      base({ patientCode: pats[2].code, serviceDemandeur: 'medecine', urgence: 'bilan', analyses: [ana[2].code] });
      H.viderToasts(); H.cliquer('Émettre la fiche'); await H.dormir(400);
      out.bilan = { toasts: H.toasts(), demandes: neuf(colD, ids2.d) };
      /* prescripteur extérieur : la liste porte la valeur « EXTERNE », que la fiche enregistre telle quelle */
      H.bouton(racine, 'Nouvelle fiche de demande').click(); await H.dormir(300);
      const ids3 = { d: avant(colD) };
      base({ patientCode: pats[3].code, prescripteur: 'EXTERNE', analyses: [ana[0].code] });
      out.externe = { champs: H.champs().filter((l) => /extérieur/i.test(l)) };
      H.poser('prescripteurExterne', 'Dr SALIFOU Aminou, Centre de santé de Perma');
      H.viderToasts(); H.cliquer('Émettre la fiche'); await H.dormir(400);
      out.externe.demandes = neuf(colD, ids3.d);
      /* la résidence se reprend du dossier au choix du patient */
      H.bouton(racine, 'Nouvelle fiche de demande').click(); await H.dormir(300);
      H.poser('patientCode', pats[5].code);
      out.reprise = { residence: H.valeur('residence'), adresse: pats[5].adresse || null, quartier: pats[5].quartier || null };
      H.retirer(racine);
      H.remettre(cols, sauve);
      return H.propre(out);
    });

    /* ------------------------------------------------------------------ bons de pansement */
    sortie.pansements = await m.page.evaluate(async () => {
      const S = SIGH.store, J = H.J, PR = SIGH.parcours;
      const cols = ['ordonnances', 'factures', 'taches', 'couverturesAssurance'].map((n) => S.collection(n));
      const sauve = H.mettreDeCote(cols);
      const colO = cols[0], colF = cols[1], colT = cols[2];
      const pats = S.collection('patients').active();
      const out = { actes: S.collection('actes').active().filter((a) => ['SO09', 'CH04'].includes(a.code)).map((a) => ({ code: a.code, libelle: a.libelle, prix: a.prix, tarifProvisoire: !!a.tarifProvisoire })) };
      const nonAssure = pats.find((p) => !(p.assureur) && !p.personnelId) || pats[0];
      out.patientNonAssure = { code: nonAssure.code, assureur: nonAssure.assureur || null };
      let racine = await H.monter('m3-bons-pansements');
      out.vide = { kpis: H.kpis(racine), cartes: H.cartes(racine), tableaux: H.tableaux(racine), boutons: H.boutons(racine).slice(0, 8) };
      H.bouton(racine, 'Nouveau bon de pansement').click(); await H.dormir(300);
      out.modale = { champs: H.champs(), defauts: {}, optsActe: H.optsDe('acteCode'), optsPrescripteur: H.optsDe('medecin') };
      ['patientCode', 'medecin', 'acteCode', 'seances', 'indication'].forEach((n) => { out.modale.defauts[n] = H.valeur(n); });
      H.viderToasts(); H.cliquer('Émettre le bon'); await H.dormir(250);
      out.refusVide = { toasts: H.toasts(), ordonnances: colO.all().length };
      const ids = { o: new Set(colO.all().map((x) => x.id)), f: new Set(colF.all().map((x) => x.id)), t: new Set(colT.all().map((x) => x.id)) };
      H.poser('patientCode', nonAssure.code); H.poser('medecin', H.optsDe('medecin')[0][0]); H.poser('acteCode', 'SO09'); H.poser('seances', '3'); H.poser('indication', 'Plaie du pied');
      H.viderToasts(); H.cliquer('Émettre le bon'); await H.dormir(500);
      const neuf = (c, s) => c.all().filter((x) => !s.has(x.id)).map(H.net);
      out.emission = { toasts: H.toasts(), ordonnances: neuf(colO, ids.o), factures: neuf(colF, ids.f), taches: neuf(colT, ids.t), impression: window.__etats[window.__etats.length - 1], kpis: H.kpis(racine), tableaux: H.tableaux(racine) };
      /* encaissement partiel : une séance réglée → « 1 / 3 » */
      const fac = colF.all().find((f) => !ids.f.has(f.id));
      const lig = fac.lignes[0];
      const res = PR.encaisser(fac.id, { lignes: [lig.id], mode: 'Espèces' });
      out.partiel = { ok: !!res, lignes: H.propre(colF.all().find((f) => f.id === fac.id).lignes.map((l) => ({ id: l.id, acteCode: l.acteCode, statutPaiement: l.statutPaiement, montantRegle: l.montantRegle, partPatient: l.partPatient }))) };
      H.retirer(racine);
      racine = await H.monter('m3-bons-pansements');
      out.apresPartiel = { kpis: H.kpis(racine), tableaux: H.tableaux(racine) };
      H.icone(racine.querySelector('tbody tr'), 'Imprimer le bon').click(); await H.dormir(200);
      out.impressionBon = H.propre(window.__etats[window.__etats.length - 1]);
      racine.querySelector('tbody tr').click(); await H.dormir(300);
      out.tiroir = H.tiroir(); H.fermerTout();
      H.retirer(racine);
      /* un assuré : carte valide posée, prix assuré 6 000 */
      const assure = pats.find((p) => p.assureur && p.id !== nonAssure.id) || pats[1];
      out.assure = { code: assure.code, assureur: assure.assureur || null };
      cols[3].all().splice(0);
      const lignesA = (() => {
        try {
          const r = PR.prescrire({ patientCode: assure.code, medecin: 'Dr TEST', diagnostic: 'Test', actes: ['SO09', 'SO09'] });
          return { montant: r.ordonnance.montant, lignes: r.facture.lignes.map((l) => ({ acteCode: l.acteCode, montant: l.montant, partAssureur: l.partAssureur, partPatient: l.partPatient })) };
        } catch (e) { return { erreur: e.message }; }
      })();
      out.assure.prescription = lignesA;
      /* C3 (31/10/2026) : le tarif ASSURÉ du pansement (6 000, colonnes inversées) s'applique réellement quand la carte est valide à la date ;
         une carte expirée facture au tarif non assuré (9 000). Patients posés pour l'occasion, carte valide / expirée, sans garantie saisie. */
      const colP = S.collection('patients');
      const posePatient = (code, expiration) => colP.insert({ code, nom: 'TEST', prenom: code, sexe: 'F', assureur: 'NSIA', assureurNom: 'NSIA', carteExpiration: expiration, tauxPriseEnCharge: 80, numeroPolice: 'POL-' + code }).record;
      const casAssure = (nom, expiration, code) => {
        posePatient(code, expiration);
        try {
          const r = PR.prescrire({ patientCode: code, medecin: 'Dr TEST', diagnostic: 'Test', actes: ['SO09', 'SO09'] });
          return { nom, carteExpiration: expiration, montant: r.ordonnance.montant, actes: r.ordonnance.actes.map((a) => ({ code: a.code, prix: a.prix })), lignes: r.facture.lignes.map((l) => ({ acteCode: l.acteCode, montant: l.montant, partAssureur: l.partAssureur, partPatient: l.partPatient })), partPatient: r.facture.partPatient, partAssurance: r.facture.partAssurance };
        } catch (e) { return { nom, erreur: e.message }; }
      };
      out.tarifAssure = [
        casAssure('carte valide : 6 000 la séance (grille, colonnes inversées)', '2099-12-31', 'CNT/9001/26'),
        casAssure('carte expirée : 9 000 la séance (non assuré)', '2000-01-01', 'CNT/9002/26'),
      ];
      colP.all().filter((x) => x.nom === 'TEST' && /^CNT\/900/.test(x.code)).forEach((x) => { colP.all().splice(colP.all().indexOf(x), 1); });
      H.remettre(cols, sauve);
      return H.propre(out);
    });

    /* ------------------------------------------------------------------ sorties d'hospitalisation (RG-06 / RG-07) */
    sortie.sorties = await m.page.evaluate(async () => {
      const S = SIGH.store, J = H.J;
      const cols = ['admissions', 'factures'].map((n) => S.collection(n));
      const sauve = H.mettreDeCote(cols);
      const colA = cols[0], colF = cols[1];
      const pats = S.collection('patients').active();
      const p = (i) => ({ patientId: pats[i].id, patient: pats[i].nom + ' ' + pats[i].prenom, patientCode: pats[i].code });
      const adm = (n, i, lit, entree, sortie, statut) => Object.assign({ id: 'ADM' + n, statut, reference: 'H0000' + n, chambre: lit.split(' ')[0], lit, dateEntree: J(entree), dateSortie: sortie == null ? null : J(sortie), diagnosticEntree: 'Diagnostic ' + n, infirmier: 'GARBA Yahouza' }, p(i));
      [adm(1, 0, 'A1 LIT1', -10, null, 'en_cours'), adm(2, 1, 'C1 LIT1', -2, null, 'en_cours'), adm(3, 2, 'A2 LIT1', -20, -14, 'sortie'), adm(4, 3, 'D1 LIT1', 0, null, 'en_cours'), adm(5, 4, 'B1 LIT1', -3, null, 'archive')].forEach((x) => colA.all().push(x));
      const fac = (n, i, reliquat) => Object.assign({ id: 'F' + n, statut: 'actif', numero: 'FA-2026-0000' + n, montantTTC: 10000, reliquat }, p(i));
      [fac(1, 0, 15000), fac(2, 0, 5000), fac(3, 1, 0), fac(4, 2, 7000), fac(5, 3, 0)].forEach((x) => colF.all().push(x));
      const out = { jeu: { admissions: H.propre(colA.all()), factures: H.propre(colF.all()) } };
      let racine = await H.monter('m3-sorties');
      out.ecran = { kpis: H.kpis(racine), cartes: H.cartes(racine), tableaux: H.tableaux(racine), boutons: H.boutons(racine).slice(0, 10) };
      out.ecran.boutonsLigne = [...racine.querySelector('tbody tr').querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title || H.norm(b.textContent));
      /* patient 1 : solde 20 000 — la fiche de sortie */
      H.bouton(H.ligne(racine, 'Diagnostic 1'), 'Préparer la sortie').click(); await H.dormir(300);
      out.fiche = { tiroir: H.tiroir(), champs: H.champs(), defauts: {}, optsEtat: H.optsDe('etatSortie') };
      ['dateSortie', 'etatSortie', 'consignes', 'sigPatient', 'sigInfirmier', 'constatGardien', 'derogation'].forEach((n) => { out.fiche.defauts[n] = H.valeur(n); });
      H.viderToasts(); H.cliquer('Finaliser la sortie'); await H.dormir(250);
      out.refus = { sansSignatures: { toasts: H.toasts() } };
      H.poser('sigPatient', true); H.poser('sigInfirmier', true);
      H.viderToasts(); H.cliquer('Finaliser la sortie'); await H.dormir(250);
      out.refus.deuxSignatures = { toasts: H.toasts() };
      H.poser('constatGardien', true);
      H.viderToasts(); H.cliquer('Finaliser la sortie'); await H.dormir(250);
      out.refus.soldeSansDerogation = { toasts: H.toasts(), admission: H.net(colA.all().find((x) => x.id === 'ADM1')) };
      H.poser('derogation', '   '); H.viderToasts(); H.cliquer('Finaliser la sortie'); await H.dormir(250);
      out.refus.derogationBlanche = { toasts: H.toasts() };
      /* bon de sortie imprimé AVANT finalisation, avec la saisie courante */
      H.poser('consignes', 'Repos 7 jours'); H.poser('etatSortie', 'Amélioré'); H.poser('dateSortie', '2026-08-16');
      H.cliquer('Éditer le bon de sortie'); await H.dormir(200);
      out.bonSortie = H.propre(window.__etats[window.__etats.length - 1]);
      H.poser('derogation', 'Accord de la Directrice Administrative');
      H.viderToasts(); H.cliquer('Finaliser la sortie'); await H.dormir(400);
      out.finalisation = { toasts: H.toasts(), admission: H.net(colA.all().find((x) => x.id === 'ADM1')), kpis: H.kpis(racine), tableaux: H.tableaux(racine) };
      /* patient 2 : solde apuré, sortie nette */
      H.bouton(H.ligne(racine, 'Diagnostic 2'), 'Préparer la sortie').click(); await H.dormir(300);
      out.apure = { tiroir: H.tiroir().texte.slice(0, 600) };
      H.poser('sigPatient', true); H.poser('sigInfirmier', true); H.poser('constatGardien', true); H.poser('etatSortie', 'Guéri');
      H.viderToasts(); H.cliquer('Finaliser la sortie'); await H.dormir(400);
      out.apure.sortie = { toasts: H.toasts(), admission: H.net(colA.all().find((x) => x.id === 'ADM2')), kpis: H.kpis(racine) };
      /* annuler la sortie : le patient revient en hospitalisation, les indicateurs suivent (E415) */
      [...document.querySelectorAll('#toast-host button')].find((b) => /annuler/i.test(b.textContent)).click(); await H.dormir(300);
      out.apure.annulee = { admission: H.net(colA.all().find((x) => x.id === 'ADM2')), kpis: H.kpis(racine) };
      H.retirer(racine);
      H.remettre(cols, sauve);
      return H.propre(out);
    });

    /* ------------------------------------------------------------------ sortie contre avis médical (RG-08) */
    sortie.avisMedical = await m.page.evaluate(async () => {
      const S = SIGH.store, J = H.J;
      const colS = S.collection('sortiesAvisMedical'), colA = S.collection('admissions');
      const sauve = H.mettreDeCote([colS, colA]);
      const pats = S.collection('patients').active();
      const p = (i) => ({ patientId: pats[i].id, patient: pats[i].nom + ' ' + pats[i].prenom, patientCode: pats[i].code });
      const adm = (n, i, lit, statut) => Object.assign({ id: 'ADM' + n, statut, reference: 'H0000' + n, chambre: lit.split(' ')[0], lit, dateEntree: J(-n), dateSortie: null, diagnosticEntree: 'Diagnostic ' + n, infirmier: 'GARBA Yahouza' }, p(i));
      [adm(1, 0, 'A1 LIT1', 'en_cours'), adm(2, 1, 'C1 LIT1', 'en_cours'), adm(3, 2, 'A2 LIT1', 'en_cours')].forEach((x) => colA.all().push(x));
      colS.all().push(Object.assign({ id: 'SAM0001', statut: 'actif', reference: 'SAM0001', dateSortie: J(-5), heureSortie: '14:00', motif: 'Raisons familiales', risques: 'Aggravation', avisProcureur: true, referenceProcureur: 'PR-12', decharge: true, cloture: true, admissionId: 'ADMX', lit: 'B1 LIT1' }, p(3)));
      colS.all().push(Object.assign({ id: 'SAM0002', statut: 'actif', reference: 'SAM0002', dateSortie: J(-4), heureSortie: '', motif: 'Coût', risques: '', avisProcureur: false, decharge: false, cloture: false, admissionId: 'ADMY', lit: 'B2 LIT1' }, p(4)));
      const out = { jeu: { sorties: H.propre(colS.all()), admissions: H.propre(colA.all()) } };
      let racine = await H.monter('m3-sortie-avis-medical');
      out.ecran = { kpis: H.kpis(racine), notes: H.notes(racine), cartes: H.cartes(racine), tableaux: H.tableaux(racine), boutons: H.boutons(racine).slice(0, 12) };
      out.ecran.boutonsLigne = [...racine.querySelector('tbody tr').querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
      H.icone(H.ligne(racine, 'SAM0001'), 'Imprimer le document').click(); await H.dormir(200);
      out.impression = H.propre(window.__etats[0]);
      H.bouton(racine, 'Enregistrer').click(); await H.dormir(300);
      out.creation = { champs: H.champs(), titre: H.modale().slice(0, 160), defauts: {}, optsAdmission: H.optsDe('admissionId') };
      ['admissionId', 'dateSortie', 'heureSortie', 'avisProcureur', 'decharge', 'cloture'].forEach((n) => { out.creation.defauts[n] = H.valeur(n); });
      H.viderToasts(); H.cliquer('Consigner'); await H.dormir(250);
      out.creation.refusMotif = { toasts: H.toasts(), total: colS.all().length };
      H.poser('admissionId', 'ADM1'); H.poser('motif', 'Veut rentrer au village'); H.poser('avisProcureur', true); H.poser('referenceProcureur', '');
      H.viderToasts(); H.cliquer('Consigner'); await H.dormir(250);
      out.creation.refusProcureur = { toasts: H.toasts(), total: colS.all().length };
      H.poser('referenceProcureur', 'PR-2026-41'); H.poser('risques', 'Infection'); H.poser('decharge', true);
      H.viderToasts(); H.cliquer('Consigner'); await H.dormir(400);
      out.creation.cree = { toasts: H.toasts(), fiche: H.net(colS.all().find((x) => x.motif === 'Veut rentrer au village')), admission: H.net(colA.all().find((x) => x.id === 'ADM1')), kpis: H.kpis(racine) };
      /* sans avis ni décharge */
      H.bouton(racine, 'Enregistrer').click(); await H.dormir(300);
      out.creation.optsApres = H.optsDe('admissionId');
      H.poser('admissionId', 'ADM2'); H.poser('motif', 'Départ non motivé'); H.poser('dateSortie', '2026-08-16');
      H.viderToasts(); H.cliquer('Consigner'); await H.dormir(400);
      out.creation.sansDecharge = { toasts: H.toasts(), fiche: H.net(colS.all().find((x) => x.motif === 'Départ non motivé')), admission: H.net(colA.all().find((x) => x.id === 'ADM2')), kpis: H.kpis(racine) };
      /* annuler la procédure remet aussi le patient en hospitalisation (E426) */
      H.bouton(racine, 'Enregistrer').click(); await H.dormir(300);
      H.poser('admissionId', 'ADM3'); H.poser('motif', 'Annulation test'); H.poser('dateSortie', '2026-08-16');
      H.viderToasts(); H.cliquer('Consigner'); await H.dormir(300);
      const avantUndo = { admission: H.net(colA.all().find((x) => x.id === 'ADM3')), actives: colS.all().filter((x) => x.statut !== 'archive').length };
      [...document.querySelectorAll('#toast-host button')].find((b) => /annuler/i.test(b.textContent)).click(); await H.dormir(300);
      out.annulation = { avant: avantUndo, apres: { admission: H.net(colA.all().find((x) => x.id === 'ADM3')), fiche: H.net(colS.all().find((x) => x.motif === 'Annulation test')), actives: colS.all().filter((x) => x.statut !== 'archive').length, kpis: H.kpis(racine) } };
      /* la fiche qu'on vient de créer (admission ADM1, déjà sortie) : l'éditer ne doit pas changer de patient (E419) */
      H.icone(H.ligne(racine, 'SAM0003'), 'Modifier').click(); await H.dormir(300);
      out.modifierCreee = { valeurs: { admissionId: H.valeur('admissionId'), dateSortie: H.valeur('dateSortie'), motif: H.valeur('motif') }, optsAdmission: H.optsDe('admissionId') };
      H.poser('motif', 'Veut rentrer au village (corrigé)'); H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.modifierCreee.enregistre = { toasts: H.toasts(), fiche: H.net(colS.all().find((x) => x.id === colS.all().find((y) => y.reference === 'SAM0003').id)), kpis: H.kpis(racine) };
      /* modification : ne touche pas à l'admission ; le patient est recalculé depuis l'admission choisie */
      H.icone(H.ligne(racine, 'SAM0002'), 'Modifier').click(); await H.dormir(300);
      out.modification = { titre: H.modale().slice(0, 140), valeurs: {} };
      ['admissionId', 'dateSortie', 'motif', 'avisProcureur', 'decharge'].forEach((n) => { out.modification.valeurs[n] = H.valeur(n); });
      H.poser('decharge', true); H.poser('cloture', true); H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.modification.enregistre = { toasts: H.toasts(), fiche: H.net(colS.all().find((x) => x.id === 'SAM0002')), kpis: H.kpis(racine) };
      H.icone(H.ligne(racine, 'SAM0001'), 'Archiver').click(); await H.dormir(200);
      out.archivage = { toasts: H.toasts(), fiche: H.net(colS.all().find((x) => x.id === 'SAM0001')), kpis: H.kpis(racine), modale: H.modale().slice(0, 160) };
      H.fermerTout();
      H.retirer(racine);
      H.remettre([colS, colA], sauve);
      return H.propre(out);
    });

    ecrire('packages/domaine/test/vecteurs/bloc.json', sortie);
    if (m.erreurs.length) console.log('  erreurs JS de la page : ' + m.erreurs.slice(0, 5).join(' | '));
  } finally {
    await m.fermer();
  }
})().catch((e) => { console.error(e); process.exit(1); });
