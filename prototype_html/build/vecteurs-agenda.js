/* =============================================================================
 * VECTEURS DE L'ACCUEIL M2 — m2-agenda, m2-rendezvous, m2-domicile, m2-registre-appels, m2-file-attente, m2-affichage,
 * m2-agenda-medecin, m2-file-cabinet, m2-visites
 * -----------------------------------------------------------------------------
 * Les écrans RÉELS sont montés dans Chrome sur un magasin dont on pose les fiches, à une HORLOGE FIGÉE (16/08/2026 12:00), puis LUS comme l'agent les
 * lit (indicateurs, onglets, tableaux, boutons, cartes de la grille) et PILOTÉS (modales de prise de rendez-vous, de passage sans rendez-vous,
 * d'inscription en file ; gestes honoré / reporté / non honoré / appeler / priorité).
 *   node build/vecteurs-agenda.js   →   packages/domaine/test/vecteurs/ag_agenda.json
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs de l’accueil M2 (agenda, rendez-vous, files, registres)');
  const m = await ouvrirMaquette();
  try {
    /* Horloge FIGÉE avant le chargement du module : `AUJ` (C.aujourdhui) et `new Date()` valent tous le 16/08/2026 12:00 (UTC). */
    await m.page.evaluate(() => {
      const Reel = window.Date; const fige = new Reel(2026, 7, 16, 12, 0, 0).getTime();
      function F() { if (!(this instanceof F)) return String(new Reel(fige)); if (arguments.length === 0) return new Reel(fige); return new (Function.prototype.bind.apply(Reel, [null].concat(Array.prototype.slice.call(arguments))))(); }
      F.prototype = Reel.prototype; F.now = () => fige; F.UTC = Reel.UTC; F.parse = Reel.parse; window.Date = F;
    });
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m2-consultations.js') });
    const sortie = await m.page.evaluate(async () => {
      const S = SIGH.store, C = SIGH.core, U = SIGH.ui;
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
      const texte = (e) => (e.innerText || '').replace(/\s+/g, ' ').trim();
      const col = (n) => S.collection(n);
      const RETIRER = ['_creePar', '_creeLe', '_modifiePar', '_modifieLe'];
      const net = (f) => { const c = propre(f); RETIRER.forEach((k) => delete c[k]); return c; };

      /* --- Neutraliser ce qui sort du cadre : rechargement de page, son, toasts capturés --------------------------------------------------- */
      const setTimeoutReel = window.setTimeout.bind(window);
      window.setTimeout = (fn, ms, ...a) => (String(fn).includes('location.reload') ? 0 : setTimeoutReel(fn, ms, ...a));
      U.sonner = () => {};
      const messages = [];
      const toastReel = U.toast, alerterReel = U.alerter;
      U.toast = (msg, o) => { messages.push({ canal: 'toast', message: msg, type: (o || {}).type || null, detail: (o || {}).detail || null }); return { close() {} }; };
      U.alerter = (msg, o) => { messages.push({ canal: 'alerte', message: msg, type: (o || {}).type || null, son: (o || {}).son || null, detail: (o || {}).detail || null }); return { close() {} }; };
      void toastReel; void alerterReel;
      const prendreMessages = (garderRappel) => messages.splice(0, messages.length).filter((x) => garderRappel || !/^Échéances du jour/.test(x.message));

      /* --- Lecture d'un écran ------------------------------------------------------------------------------------------------------------- */
      async function monter(id) {
        const root = document.createElement('div'); document.body.appendChild(root);
        SIGH.screens[id].render(root); await dormir(70);
        return root;
      }
      function demonter(root) {
        document.querySelectorAll('.drawer-backdrop, .modal-root, [role=dialog]').forEach((e) => e.remove());
        root.remove();
      }
      const boutonsDe = (n) => [...n.querySelectorAll('button')].map((b) => b.getAttribute('title') || b.getAttribute('aria-label') || texte(b)).filter(Boolean);
      function kpisDe(root) {
        const g = [...root.querySelectorAll('.grid.gap-3')].find((x) => /grid-cols-2/.test(x.className));
        return g ? [...g.children].map((k) => {
          const t = (k.innerText || '').split(/\n+/).map((s) => s.trim()).filter(Boolean);
          return { label: t[0], valeur: t[1], indice: t[2] || null };
        }) : [];
      }
      function tableauxDe(root) {
        return [...root.querySelectorAll('.card')].filter((c) => c.querySelector('table')).map((c) => {
          const h = c.querySelector('h3.text-sm, .card-title');
          return {
            titre: h ? texte(h) : null,
            entetes: [...c.querySelectorAll('thead th')].map(texte).filter((s) => s !== ''),
            lignes: [...c.querySelectorAll('tbody tr')].map((tr) => ({
              cellules: [...tr.querySelectorAll('td')].map(texte).filter((s, i) => i > 0 || s !== ''),
              boutons: [...tr.querySelectorAll('button')].map((b) => b.getAttribute('title') || b.getAttribute('aria-label') || texte(b)).filter(Boolean),
            })),
            pied: texte(c.querySelector('.border-t') || document.createElement('i')),
          };
        });
      }
      const ongletsDe = (root) => [...root.querySelectorAll('.tab')].map(texte);
      const notesDe = (root) => [...root.querySelectorAll('.note, [class*=bg-info-50], [class*=bg-warning-50], [class*=bg-success-50], [class*=bg-danger-50]')].map(texte).filter(Boolean);
      const cartesDe = (root) => [...root.querySelectorAll('.card-title')].map(texte);
      function lire(root) {
        return { kpis: kpisDe(root), onglets: ongletsDe(root), tables: tableauxDe(root).map((t) => ({ titre: t.titre, entetes: t.entetes, lignes: t.lignes, pied: t.pied })),
          cartes: cartesDe(root), notes: notesDe(root), boutons: boutonsDe(root).filter((b) => !/^(Sélectionner|Tout sélectionner)/.test(b)) };
      }
      const pied0 = (root) => { const t = tableauxDe(root)[0]; return t ? t.pied : texte(root.querySelector('.card.overflow-hidden') || root).slice(0, 200); };
      const refsDe = (root) => tableauxDe(root).flatMap((t) => t.lignes.map((l) => l.cellules[0]));
      function changer(e, v) {
        if (e.type === 'checkbox') e.checked = !!v; else e.value = v;
        e.dispatchEvent(new Event('input', { bubbles: true })); e.dispatchEvent(new Event('change', { bubbles: true }));
      }
      const champ = (nom) => document.getElementById('f_' + nom);
      const poserChamp = (nom, v) => { const e = champ(nom); if (!e) throw new Error('champ ' + nom); changer(e, v); };
      const bouton = (t, dans) => [...(dans || document).querySelectorAll('button')].find((b) => texte(b) === t);
      const boutonsPied = (t) => [...document.querySelectorAll('button')].filter((b) => texte(b) === t).pop();

      /* --- Les acteurs : praticiens et patients du magasin --------------------------------------------------------------------------------- */
      const medecins = col('personnel').active().filter((e) => e.fonction === 'medecin').map((e) => ({ nomComplet: e.nomComplet, poste: e.poste, id: e.id }));
      const patients = col('patients').active().slice(0, 8).map((p) => ({ id: p.id, code: p.code, nom: p.nom, prenom: p.prenom, assureur: !!p.assureur, assureurNom: p.assureurNom || null, tauxPriseEnCharge: p.tauxPriseEnCharge || 0 }));
      const MED = medecins.map((x) => x.nomComplet);
      const jour = (dec, h, mi, z) => { const d = new Date(2026, 7, 16 + dec, h, mi, 0); return z === false ? C.isoLocal(d) : d.toISOString(); };
      const sortie = { horloge: '2026-08-16T12:00:00', medecins, patients };

      /* --- Les consultations posées -------------------------------------------------------------------------------------------------------- */
      let nref = 0;
      const rdv = (dec, h, mi, statut, type, im, ip, extra) => {
        nref++;
        const p = ip == null ? null : patients[ip];
        return Object.assign({
          reference: 'C' + String(nref).padStart(5, '0'), date: jour(dec, h, mi, !(nref % 5 === 0) ? true : false), statut, type, medecin: MED[im % MED.length], medecinId: medecins[im % MED.length].id,
          motif: ['Paludisme suspecté', 'Contrôle diabète', 'Plaie infectée', 'Fièvre persistante', 'Suivi de grossesse'][nref % 5],
          diagnostic: nref % 3 === 0 ? 'Diagnostic ' + nref : '', tarif: [3000, 5000, 10000][nref % 3],
        }, p ? { patientId: p.id, patientCode: p.code, patient: p.nom + ' ' + p.prenom } : {}, extra || {});
      };
      const F1 = [
        /* aujourd'hui : neuf rendez-vous non apurés + un honoré */
        rdv(0, 8, 30, 'terminee', 'Consultation', 0, 0), rdv(0, 9, 0, 'planifiee', 'Consultation', 0, 1), rdv(0, 9, 30, 'planifiee', 'Contrôle', 1, 2),
        rdv(0, 10, 0, 'en_cours', 'Urgence', 2, 3), rdv(0, 10, 30, 'planifiee', 'Consultation', 0, 4), rdv(0, 11, 0, 'planifiee', 'Consultation', 1, 5),
        rdv(0, 11, 30, 'planifiee', 'Consultation', 2, 6), rdv(0, 13, 30, 'planifiee', 'Consultation', 0, 0), rdv(0, 15, 0, 'reporte', 'Contrôle', 1, 1, { dateInitiale: jour(-2, 15, 0), motifReport: 'Demande du patient' }),
        rdv(0, 16, 0, 'non_honore', 'Consultation', 2, 2, { motifNonHonore: 'Ne s’est pas présenté', constateLe: jour(0, 11, 0) }),
        /* le passé */
        rdv(-1, 15, 0, 'planifiee', 'Consultation', 1, 3), rdv(-2, 10, 0, 'terminee', 'Contrôle', 0, 4), rdv(-3, 14, 0, 'non_honore', 'Consultation', 2, 5),
        rdv(-5, 9, 0, 'planifiee', 'Urgence', 0, 6), rdv(-10, 10, 0, 'terminee', 'Domicile', 1, 7, { fraisDeplacement: 5000, adresseIntervention: 'Quartier Boriyouré' }),
        rdv(-12, 11, 0, 'terminee', 'Consultation', 2, 0), rdv(-20, 8, 0, 'terminee', 'Consultation', 0, 1), rdv(-25, 9, 0, 'en_cours', 'Contrôle', 1, 2),
        rdv(-29, 9, 0, 'terminee', 'Consultation', 2, 3), rdv(-30, 9, 0, 'terminee', 'Consultation', 0, 4), rdv(-31, 9, 0, 'terminee', 'Consultation', 0, 5),
        rdv(-45, 9, 0, 'terminee', 'Domicile', 1, 6, { fraisDeplacement: 5000 }), rdv(-60, 9, 0, 'planifiee', 'Consultation', 2, 7),
        /* l'avenir */
        rdv(1, 9, 0, 'planifiee', 'Consultation', 0, 0), rdv(2, 10, 0, 'reporte', 'Contrôle', 1, 1, { dateInitiale: jour(0, 10, 0), motifReport: 'Indisponibilité du praticien' }),
        rdv(3, 8, 30, 'planifiee', 'Urgence', 2, 2), rdv(4, 14, 0, 'planifiee', 'Domicile', 0, 3, { fraisDeplacement: 5000 }), rdv(9, 9, 0, 'planifiee', 'Consultation', 1, 4), rdv(40, 9, 0, 'planifiee', 'Consultation', 2, 5),
        /* les personnes non enregistrées */
        rdv(0, 12, 45, 'planifiee', 'Visite', 0, null, { patient: 'KPADE Marcel', patientCode: 'NON-PATIENT', patientId: null, nonPatient: true, visiteurNom: 'kpade', visiteurPrenom: 'Marcel', visiteurQuartier: 'Pélébina', visiteurTelephone: '0197000001' }),
        rdv(-1, 10, 0, 'en_cours', 'Consultation', 1, null, { patient: 'ALASSANI Fati', patientCode: 'NON-PATIENT', patientId: null, nonPatient: true, sansRendezVous: true, visiteurNom: 'alassani', visiteurPrenom: 'Fati', visiteurQuartier: 'Kantaborifa', visiteurTelephone: '0197000002' }),
        rdv(5, 16, 0, 'planifiee', 'Affaire privée', 2, null, { patient: 'GBEGAN Roger', patientCode: 'NON-PATIENT', patientId: null, nonPatient: true, visiteurNom: 'gbegan', visiteurPrenom: 'Roger' }),
        rdv(-4, 10, 0, 'terminee', 'Consultation', 1, 0, { sansRendezVous: true, orientation: 'Médecine générale' }),
      ];
      function poser(nom, fiches) {
        const db = S.raw(); db[nom] = [];
        const c = col(nom);
        [...fiches].reverse().forEach((f) => c.insert(Object.assign({}, f)));
        return c;
      }
      function poserConsultations(fiches, archiver) {
        const c = poser('consultations', fiches);
        (archiver || []).forEach((ref) => { const r = c.all().find((x) => x.reference === ref); if (r) c.archive(r.id, 'test'); });
        return c;
      }
      const etatCons = () => col('consultations').all().map(net);

      /* ======================================================================================================================================
       * 1. AGENDA
       * ==================================================================================================================================== */
      function lireAgenda(root) {
        const dates = [...root.querySelectorAll('input[type=date]')].map((i) => i.value);
        const grille = root.querySelector('.grid.gap-3.md\\:grid-cols-4');
        const jours = grille ? [...grille.children].map((carte) => {
          const ps = [...carte.querySelectorAll('p')].map(texte);
          const items = [...carte.querySelectorAll('button')].map((b) => [...b.querySelectorAll('span')].map(texte));
          return { entete: ps[0], mois: ps[1], aucun: ps.includes('Aucun'), autres: ps.find((p) => /^\+ \d+ autre/.test(p)) || null, items, aujourdhui: /ring-1/.test(carte.className) };
        }) : [];
        const titre = [...root.querySelectorAll('.card-title')].map(texte).find((t) => /^Du /.test(t)) || null;
        /* « Charge par praticien » : le classement ; « Répartition par type » : les données du graphique */
        const cartes = [...root.querySelectorAll('.card')].filter((c) => c.querySelector('.card-title'));
        const carteCharge = cartes.find((c) => /Charge par praticien/.test(texte(c.querySelector('.card-title'))));
        const charge = carteCharge ? [...carteCharge.querySelectorAll('.space-y-2\\.5 > div')].map((d) => { const s = [...d.querySelectorAll('span')].map(texte); return { label: s[0], valeur: s[1] }; }) : [];
        const carteType = cartes.find((c) => /Répartition par type/.test(texte(c.querySelector('.card-title'))));
        let repartition = null;
        const cv = carteType && carteType.querySelector('canvas');
        if (cv && window.Chart && window.Chart.getChart && window.Chart.getChart(cv)) { const d = window.Chart.getChart(cv).data; repartition = { labels: d.labels, valeurs: d.datasets[0].data }; }
        return { kpis: kpisDe(root), dates, titre, jours, charge, repartition, boutons: boutonsDe(root).filter((b) => !/^\d+$/.test(b)), commandes: [...root.querySelectorAll('button')].map(texte).filter(Boolean) };
      }
      sortie.agenda = [];
      {
        poserConsultations(F1, ['C00019']);
        const fixtures = etatCons();
        const reglages = [
          ['fenêtre par défaut (du 14 au 20 août)', null],
          ['du 1er au 31 août — trente et un jours', ['2026-08-01', '2026-08-31']],
          ['dates inversées : un seul jour (le début)', ['2026-08-10', '2026-08-05']],
          ['plus de trente et un jours : plafonnée à 31', ['2026-07-01', '2026-09-30']],
          ['une seule journée, celle de neuf rendez-vous', ['2026-08-16', '2026-08-16']],
        ];
        for (const [nom, plage] of reglages) {
          const root = await monter('m2-agenda');
          if (plage) { const [d, f] = [...root.querySelectorAll('input[type=date]')]; changer(d, plage[0]); changer(f, plage[1]); await dormir(60); }
          sortie.agenda.push({ nom, plage, lu: lireAgenda(root) });
          demonter(root);
        }
        sortie.agendaFixtures = fixtures;
        /* « Semaine en cours » après un changement de plage */
        {
          const root = await monter('m2-agenda');
          const [d, f] = [...root.querySelectorAll('input[type=date]')]; changer(d, '2026-08-01'); changer(f, '2026-08-31'); await dormir(30);
          bouton('Semaine en cours', root).click(); await dormir(60);
          sortie.agendaSemaineEnCours = lireAgenda(root);
          demonter(root);
        }
        /* Le rappel des échéances : se déclenche 900 ms après l'ouverture */
        sortie.rappels = [];
        for (const [nom, fiches] of [['un rendez-vous dans les deux heures', F1], ['un seul rendez-vous proche (12h45)', F1.filter((x) => x.reference !== 'C00008')], ['aucun rendez-vous proche', F1.filter((x) => x.reference !== 'C00008' && x.visiteurNom !== 'kpade')], ['registre vide', []]]) {
          await dormir(1100); prendreMessages(true);
          poserConsultations(fiches);
          const root = await monter('m2-agenda'); await dormir(1000);
          sortie.rappels.push({ nom, messages: prendreMessages(true).filter((x) => x.canal === 'alerte'), fiches: fiches.length });
          demonter(root);
        }
      }

      /* La prise de rendez-vous : fenêtre étendue jusqu'au rendez-vous pris */
      sortie.priseRdv = [];
      {
        const cas = [
          ['dans la fenêtre', { patientCode: patients[0].code, medecin: MED[0], type: 'Consultation', date: '2026-08-17T09:00', motif: 'Contrôle', tarif: '3000', notifier: true }],
          ['avant la fenêtre : le début recule', { patientCode: patients[1].code, medecin: MED[1], type: 'Contrôle', date: '2026-08-10T09:30', motif: 'Suivi', tarif: '5000', notifier: false }],
          ['après la fenêtre : la fin avance', { patientCode: patients[2].code, medecin: MED[2], type: 'Urgence', date: '2026-08-25T14:00', motif: 'Urgence différée', tarif: '', notifier: true }],
          ['plus de trente et un jours : la fenêtre se recentre', { patientCode: patients[3].code, medecin: MED[0], type: 'Consultation', date: '2026-10-30T08:15', motif: 'Visite lointaine', tarif: '4000', notifier: false }],
          ['sans motif : formulaire en erreur, rien n’est écrit', { patientCode: patients[0].code, medecin: MED[0], type: 'Consultation', date: '2026-08-18T09:00', motif: '', tarif: '', notifier: false }],
        ];
        for (const [nom, saisie] of cas) {
          poserConsultations(F1);
          prendreMessages();
          const root = await monter('m2-agenda');
          const avant = new Set(col('consultations').all().map((x) => x.id));
          bouton('Nouveau rendez-vous', root).click(); await dormir(40);
          const defauts = { date: champ('date') ? champ('date').value : null, notifier: champ('notifier') ? champ('notifier').checked : null };
          Object.entries(saisie).forEach(([k, v]) => { if (k === 'notifier') changer(champ(k), v); else poserChamp(k, v); });
          boutonsPied('Enregistrer le rendez-vous').click(); await dormir(60);
          const nouveaux = col('consultations').all().filter((x) => !avant.has(x.id)).map(net);
          sortie.priseRdv.push({ nom, saisie, defauts, creees: nouveaux, messages: prendreMessages(), lu: lireAgenda(root), total: col('consultations').all().length });
          demonter(root);
        }
      }

      /* Les gestes de suite depuis la grille : honoré, reporté, non honoré, annuler */
      sortie.suites = [];
      {
        const gestes = [
          ['honoré', 'Marquer honoré', null],
          ['reporté', 'Reporter', { nouvelleDate: '2026-08-30T10:00', motifReport: 'Demande du patient' }],
          ['reporté sans date : refusé', 'Reporter', { nouvelleDate: '', motifReport: 'Demande du patient' }],
          ['non honoré', 'Non honoré', { motif: 'Patient absent, injoignable' }],
          ['annulé (archivé)', 'Annuler le rendez-vous', { motif: 'Doublon' }],
        ];
        for (const [nom, libelle, saisie] of gestes) {
          poserConsultations(F1);
          prendreMessages();
          const root = await monter('m2-agenda');
          const cibles = [...root.querySelectorAll('.grid.gap-3.md\\:grid-cols-4 button')];
          const carte = cibles.find((b) => texte(b).includes('Plaie infectée')) || cibles[0];
          carte.click(); await dormir(50);
          const tiroir = document.querySelector('.drawer-backdrop');
          const lireTiroir = { titre: texte(tiroir.querySelector('h2')), sous: texte(tiroir.querySelector('h2 + p')), texte: texte(tiroir.querySelector('.overflow-y-auto')), pied: boutonsDe(tiroir.querySelector('.border-t.bg-slate-50') || tiroir) };
          const ref = (/Référence\s+(C\d+)/.exec(lireTiroir.texte) || [])[1] || null;
          const avantEtat = etatCons().find((x) => x.reference === ref);
          bouton(libelle, tiroir.querySelector('.border-t.bg-slate-50')).click(); await dormir(50);
          if (saisie && saisie.nouvelleDate !== undefined) {
            poserChamp('nouvelleDate', saisie.nouvelleDate); poserChamp('motifReport', saisie.motifReport);
            boutonsPied('Reporter').click(); await dormir(50);
          } else if (saisie && saisie.motif !== undefined) {
            const ta = document.querySelector('.modal-root textarea, [role=dialog] textarea, textarea');
            changer(ta, saisie.motif);
            const confirmer = ['Marquer non honoré', 'Annuler le rendez-vous'].map((t) => boutonsPied(t)).filter(Boolean).pop();
            confirmer.click(); await dormir(60);
          }
          const apres = etatCons().find((x) => x.reference === ref);
          sortie.suites.push({ nom, geste: libelle, saisie, tiroir: lireTiroir, avant: avantEtat, apres, messages: prendreMessages(), lu: lireAgenda(root) });
          demonter(root);
        }
      }

      /* ======================================================================================================================================
       * 2. RENDEZ-VOUS & VISITES
       * ==================================================================================================================================== */
      sortie.rendezvous = {};
      {
        poserConsultations(F1, ['C00019', 'C00021']);
        const refsArchives = col('consultations').archived().map((x) => x.reference);
        sortie.rendezvous.archivees = refsArchives;
        sortie.rendezvous.fixtures = etatCons();
        let root = await monter('m2-rendezvous');
        const base = lire(root);
        sortie.rendezvous.defaut = base;
        sortie.rendezvous.filtres = [];
        const selects = [...root.querySelectorAll('select')];
        for (const s of selects) {
          const nomF = s.getAttribute('aria-label');
          for (const o of [...s.options].filter((x) => x.value !== '')) {
            changer(s, o.value); await dormir(40);
            sortie.rendezvous.filtres.push({ filtre: nomF, valeur: o.value, libelle: o.textContent, pied: pied0(root), refs: refsDe(root) });
          }
          changer(s, ''); await dormir(30);
        }
        /* la plage de dates */
        sortie.rendezvous.plages = [];
        const [du, au] = [...root.querySelectorAll('input[type=date]')];
        const plages = [['du 10 au 16 août', '2026-08-10', '2026-08-16'], ['seulement un début', '2026-08-15', ''], ['seulement une fin', '', '2026-08-01']];
        for (const [nom, a, b] of plages) {
          changer(du, a); changer(au, b); await dormir(40);
          sortie.rendezvous.plages.push({ nom, du: a, au: b, onglets: ongletsDe(root), pied: pied0(root), refs: refsDe(root) });
        }
        bouton('Aujourd’hui', root).click(); await dormir(40);
        sortie.rendezvous.plages.push({ nom: 'raccourci Aujourd’hui', du: du.value, au: au.value, onglets: ongletsDe(root), pied: pied0(root), refs: refsDe(root) });
        bouton('Sept derniers jours', root).click(); await dormir(40);
        sortie.rendezvous.plages.push({ nom: 'raccourci Sept derniers jours', du: du.value, au: au.value, onglets: ongletsDe(root), pied: pied0(root), refs: refsDe(root) });
        bouton('Toute la période', root).click(); await dormir(40);
        sortie.rendezvous.plages.push({ nom: 'raccourci Toute la période', du: du.value, au: au.value, onglets: ongletsDe(root), pied: pied0(root), refs: refsDe(root) });
        /* l'onglet « Honorés » et l'onglet « Archivés » */
        [...root.querySelectorAll('.tab')].find((t) => /Honorés/.test(texte(t))).click(); await dormir(60);
        sortie.rendezvous.honores = lire(root);
        [...root.querySelectorAll('.tab')].find((t) => /Archivés/.test(texte(t))).click(); await dormir(60);
        sortie.rendezvous.archives = lire(root);
        demonter(root);

        /* la fiche d'un rendez-vous : un par cas du détail */
        sortie.rendezvous.fiches = [];
        const cibles = [
          ['reporté, avec sa date initiale', 'C00009'], ['non honoré', 'C00010'], ['planifié dont la date est passée (à statuer)', 'C00011'],
          ['personne non enregistrée', 'C00031'], ['honoré, patient assuré', 'C00012'], ['honoré, à domicile', 'C00015'], ['honoré, venu sans rendez-vous', 'C00033'],
        ];
        for (const [nom, ref] of cibles) {
          root = await monter('m2-rendezvous');
          const rech = root.querySelector('input[type=search]'); changer(rech, ref); await sleepDebounce();
          let tr = [...root.querySelectorAll('tbody tr')].find((t) => texte(t).includes(ref));
          if (!tr) { [...root.querySelectorAll('.tab')].find((t) => /Honorés/.test(texte(t))).click(); await dormir(60); changer(root.querySelector('input[type=search]'), ref); await sleepDebounce(); tr = [...root.querySelectorAll('tbody tr')].find((t) => texte(t).includes(ref)); }
          let fiche = null;
          if (tr) { tr.click(); await dormir(60); const t = document.querySelector('.drawer-backdrop'); fiche = { titre: texte(t.querySelector('h2')), sous: texte(t.querySelector('h2 + p')), texte: texte(t.querySelector('.overflow-y-auto')), pied: boutonsDe(t.querySelector('.border-t.bg-slate-50') || t), boutonsCorps: boutonsDe(t.querySelector('.overflow-y-auto')) }; }
          sortie.rendezvous.fiches.push({ nom, reference: ref, fiche });
          demonter(root);
        }
      }
      function sleepDebounce() { return dormir(260); }
      sortie.rendezvous.editions = [];
      {
        const cas = [['modifier le motif d’un rendez-vous : la référence ne change pas', 'C00002', { motif: 'Motif corrigé', tarif: '4500' }], ['modifier une personne non enregistrée', 'C00030', { visiteurQuartier: 'Tiélé', motif: 'Autre motif' }], ['modifier un rendez-vous reporté : son état est conservé', 'C00009', { motif: 'Motif corrigé' }], ['modifier un rendez-vous non honoré : son état est conservé', 'C00010', { motif: 'Motif corrigé' }]];
        for (const [nom, ref, saisie] of cas) {
          poserConsultations(F1); prendreMessages();
          const root = await monter('m2-rendezvous');
          changer(root.querySelector('input[type=search]'), ref); await sleepDebounce();
          const tr = [...root.querySelectorAll('tbody tr')].find((t) => texte(t).includes(ref));
          [...tr.querySelectorAll('button')].find((b) => b.getAttribute('title') === 'Modifier').click(); await dormir(50);
          const avant = net(col('consultations').all().find((x) => x.reference === ref));
          const valeursAvant = Object.fromEntries(['patientCode', 'visiteurNom', 'visiteurQuartier', 'medecin', 'type', 'motif', 'statut', 'tarif'].map((k) => [k, champ(k) ? champ(k).value : null]));
          Object.entries(saisie).forEach(([k, v]) => poserChamp(k, v));
          boutonsPied('Enregistrer').click(); await dormir(60);
          sortie.rendezvous.editions.push({ nom, reference: ref, saisie, valeursAvant, avant, apres: net(col('consultations').all().find((x) => x.id === avant.id)), messages: prendreMessages(), total: col('consultations').all().length });
          demonter(root);
        }
      }

      /* La création d'une venue : patient du répertoire, personne non enregistrée, refus */
      sortie.rendezvous.creations = [];
      {
        const cas = [
          ['patient du répertoire', { patientCode: patients[0].code, medecin: MED[1], type: 'Consultation', date: '2026-08-20T10:00', motif: 'Fièvre', statut: 'planifiee' }],
          ['personne non enregistrée : quatre champs, aucun dossier, aucun code CNT', { visiteurNom: 'dossou', visiteurPrenom: 'Alice', visiteurQuartier: 'Péporiyakou', visiteurTelephone: '0197112233', medecin: MED[0], type: 'Visite', date: '2026-08-21T11:00', motif: 'Rencontre', statut: 'planifiee' }],
          ['affaire privée avec la Direction, nom seul', { visiteurNom: 'tchabi', medecin: MED[2], type: 'Affaire privée', date: '2026-08-22T15:30', motif: 'Affaire privée', statut: 'planifiee' }],
          ['ni dossier ni nom : refusé par le contrôle de l’écran', { medecin: MED[0], type: 'Consultation', date: '2026-08-20T10:00', motif: 'Fièvre', statut: 'planifiee' }],
          ['dossier ET nom saisi : le dossier l’emporte', { patientCode: patients[2].code, visiteurNom: 'ignoré', medecin: MED[0], type: 'Contrôle', date: '2026-08-23T09:00', motif: 'Contrôle', statut: 'en_cours' }],
        ];
        for (const [nom, saisie] of cas) {
          poserConsultations(F1);
          const patientsAvant = col('patients').all().length;
          prendreMessages();
          const root = await monter('m2-rendezvous');
          const avant = new Set(col('consultations').all().map((x) => x.id));
          const dernier = bouton('Nouveau', root);
          dernier.click(); await dormir(50);
          const defauts = Object.fromEntries(['type', 'tarif', 'statut'].map((k) => [k, champ(k) ? champ(k).value : null]));
          Object.entries(saisie).forEach(([k, v]) => poserChamp(k, v));
          boutonsPied('Créer').click(); await dormir(70);
          sortie.rendezvous.creations.push({ nom, saisie, defauts, creees: col('consultations').all().filter((x) => !avant.has(x.id)).map(net),
            patientsCrees: col('patients').all().length - patientsAvant, messages: prendreMessages(), kpis: kpisDe(root), onglets: ongletsDe(root) });
          demonter(root);
        }
      }

      /* Le passage sans rendez-vous (depuis l'agenda) */
      sortie.passages = [];
      {
        const cas = [
          ['patient du répertoire, prioritaire', { patientCode: patients[4].code, date: '2026-08-16T11:50', motif: 'Douleur thoracique', type: 'Urgence', orientation: 'Salle de soins', medecin: MED[1], priorite: true, tarif: '5000' }],
          ['personne non enregistrée, orientée vers la pharmacie', { visiteurNom: 'bio', visiteurPrenom: 'Yaya', visiteurQuartier: 'Boriyouré', visiteurTelephone: '0198000001', date: '2026-08-16T11:55', motif: 'Retrait de résultat', type: 'Consultation', orientation: 'Pharmacie', tarif: '' }],
          ['ni dossier ni nom : refusé', { date: '2026-08-16T11:55', motif: 'Rien', type: 'Consultation', orientation: 'Maternité' }],
          ['sans praticien pressenti, retour à domicile', { patientCode: patients[5].code, date: '2026-08-16T08:05', motif: 'Pansement', type: 'Contrôle', orientation: 'Retour à domicile' }],
        ];
        for (const [nom, saisie] of cas) {
          poserConsultations(F1);
          prendreMessages();
          const avant = new Set(col('consultations').all().map((x) => x.id));
          const rootR = await monter('m2-rendezvous');
          // l'action d'en-tête n'existe que dans le gabarit de page : on lit les boutons que l'écran déclare
          const declencheur = SIGH.screens['m2-rendezvous'].actions ? SIGH.screens['m2-rendezvous'].actions() : [];
          const bt = declencheur.find((b) => texte(b) === 'Passage sans rendez-vous');
          bt.click(); await dormir(50);
          const defauts = { priorite: champ('priorite') ? champ('priorite').checked : null, date: champ('date') ? champ('date').value : null };
          Object.entries(saisie).forEach(([k, v]) => { if (k === 'priorite') changer(champ(k), v); else poserChamp(k, v); });
          boutonsPied('Enregistrer le passage').click(); await dormir(60);
          sortie.passages.push({ nom, saisie, defauts, creees: col('consultations').all().filter((x) => !avant.has(x.id)).map(net), messages: prendreMessages() });
          demonter(rootR);
        }
      }

      /* La page-renvoi */
      {
        const root = await monter('m2-visites');
        sortie.visites = { texte: texte(root), boutons: boutonsDe(root) };
        demonter(root);
      }

      /* ======================================================================================================================================
       * 3. DOMICILE
       * ==================================================================================================================================== */
      sortie.domicile = {};
      {
        poserConsultations(F1, ['C00015']);
        sortie.domicile.fixtures = etatCons();
        const root = await monter('m2-domicile');
        sortie.domicile.defaut = lire(root);
        [...root.querySelectorAll('.tab')].find((t) => /Archivés/.test(texte(t))).click(); await dormir(60);
        sortie.domicile.archives = lire(root);
        demonter(root);
        const r2 = await monter('m2-domicile');
        prendreMessages();
        const avant = new Set(col('consultations').all().map((x) => x.id));
        bouton('Nouveau', r2).click(); await dormir(50);
        const defauts = Object.fromEntries(['type', 'statut', 'tarif', 'fraisDeplacement'].map((k) => [k, champ(k) ? champ(k).value : null]));
        const saisie = { patientCode: patients[1].code, medecin: MED[0], date: '2026-08-19T09:00', motif: 'Soins de plaie à domicile', statut: 'planifiee', tarif: '10000', fraisDeplacement: '5000', adresseIntervention: 'Toucountouna' };
        Object.entries(saisie).forEach(([k, v]) => poserChamp(k, v));
        boutonsPied('Créer').click(); await dormir(60);
        sortie.domicile.creation = { saisie, defauts, creees: col('consultations').all().filter((x) => !avant.has(x.id)).map(net), messages: prendreMessages(), kpis: kpisDe(r2) };
        demonter(r2);
      }

      /* ======================================================================================================================================
       * 4. REGISTRE DES APPELS
       * ==================================================================================================================================== */
      sortie.appels = {};
      {
        const objets = ['Prise de rendez-vous', 'Report de rendez-vous', 'Demande de résultat d’analyse', 'Renseignement tarifaire', 'Suivi post-hospitalisation', 'Rappel de règlement', 'Demande d’ambulance', 'Information administrative'];
        const suites = ['Rendez-vous fixé', 'Information donnée', 'Rappel à programmer', 'Transféré au médecin', 'Sans suite'];
        const appels = Array.from({ length: 30 }, (_, i) => ({
          reference: 'A' + String(i + 1).padStart(5, '0'), id: 'APL' + String(i + 1).padStart(4, '0'), dateHeure: new Date(2026, 7, 16 - (i % 12), 7 + (i % 12), (i * 7) % 60).toISOString(),
          sens: i % 3 === 0 ? 'sortant' : 'entrant', interlocuteur: patients[i % patients.length].nom + ' ' + patients[i % patients.length].prenom, telephone: '019700' + String(1000 + i),
          objet: objets[i % objets.length], agent: ['OROU YO Edmond', 'Secrétaire médicale', 'Caisse'][i % 3], suite: suites[(i * 2) % suites.length], statut: 'actif',
          observations: i % 4 === 0 ? 'Observation ' + i : '',
        }));
        poser('appels', appels);
        sortie.appels.fixtures = col('appels').all().map(net);
        let root = await monter('m2-registre-appels');
        sortie.appels.defaut = lire(root);
        sortie.appels.filtres = [];
        for (const s of [...root.querySelectorAll('select')]) {
          const nomF = s.getAttribute('aria-label');
          for (const o of [...s.options].filter((x) => x.value !== '')) {
            changer(s, o.value); await dormir(40);
            sortie.appels.filtres.push({ filtre: nomF, valeur: o.value, pied: pied0(root), refs: refsDe(root) });
          }
          changer(s, ''); await dormir(30);
        }
        const tr = root.querySelector('tbody tr'); tr.click(); await dormir(50);
        const t = document.querySelector('.drawer-backdrop');
        sortie.appels.fiche = { titre: texte(t.querySelector('h2')), sous: texte(t.querySelector('h2 + p')), texte: texte(t.querySelector('.overflow-y-auto')), pied: boutonsDe(t.querySelector('.border-t.bg-slate-50') || t) };
        demonter(root);
        root = await monter('m2-registre-appels');
        prendreMessages();
        const avant = new Set(col('appels').all().map((x) => x.id));
        bouton('Nouveau', root).click(); await dormir(50);
        const defauts = Object.fromEntries(['dateHeure', 'sens', 'agent'].map((k) => [k, champ(k) ? champ(k).value : null]));
        const saisie = { dateHeure: '2026-08-16T11:30', sens: 'sortant', interlocuteur: 'ZIME Ramatou', telephone: '0197555555', objet: 'Rappel de règlement', agent: 'Caisse', suite: 'Rappel à programmer', observations: 'Rappeler vendredi' };
        Object.entries(saisie).forEach(([k, v]) => poserChamp(k, v));
        boutonsPied('Créer').click(); await dormir(60);
        sortie.appels.creation = { saisie, defauts, creees: col('appels').all().filter((x) => !avant.has(x.id)).map(net), messages: prendreMessages(), kpis: kpisDe(root) };
        demonter(root);
      }

      /* ======================================================================================================================================
       * 5. FILES : attente, affichage, cabinet
       * ==================================================================================================================================== */
      const arr = (dec, mi) => new Date(2026, 7, 16, 8, mi + dec).toISOString();
      const tk = (poste, numero, p, priorite, motif, mi, extra) => Object.assign({ poste, posteLabel: poste, numero, patient: patients[p].nom + ' ' + patients[p].prenom, patientCode: patients[p].code, patientId: patients[p].id, priorite, motif, arriveeLe: arr(0, mi), etat: 'attente' }, extra || {});
      const FILE = [
        tk('accueil', 'A001', 0, 'ordre_arrivee', 'Renseignement', 5), tk('accueil', 'A002', 1, 'urgence', 'Malaise', 12),
        tk('consultation', 'C001', 2, 'ordre_arrivee', 'Fièvre', 10), tk('consultation', 'C002', 3, 'rdv', 'Contrôle', 20, { praticien: MED[0] }),
        tk('consultation', 'C003', 4, 'urgence_vitale', 'Détresse', 35, { praticien: MED[1] }), tk('consultation', 'C004', 5, 'ordre_arrivee', 'Toux', 8, { praticien: MED[0] }),
        tk('consultation', 'C005', 6, 'urgence', 'Plaie', 15), tk('consultation', 'C006', 7, 'rdv', 'Résultats', 2),
        tk('consultation', 'C000', 0, 'ordre_arrivee', 'Déjà reçu', 1, { etat: 'servi', serviLe: arr(0, 9), appelePar: 'Accueil' }),
        tk('caisse', 'C101', 1, 'ordre_arrivee', 'Règlement', 14), tk('caisse', 'C102', 2, 'ordre_arrivee', 'Règlement', 14),
        tk('caisse', 'C100', 3, 'ordre_arrivee', 'Règlement', 3, { etat: 'servi', serviLe: arr(0, 33), appelePar: 'Caisse' }),
        tk('prelevement', 'S001', 3, 'rdv', 'Prélèvement', 30), tk('pharmacie', 'P001', 4, 'ordre_arrivee', 'Ordonnance', 40),
        tk('pharmacie', 'P000', 5, 'ordre_arrivee', 'Ordonnance', 1, { arriveeLe: new Date(2026, 7, 15, 16, 0).toISOString(), etat: 'servi', serviLe: new Date(2026, 7, 15, 17, 0).toISOString(), appelePar: 'Pharmacie' }),
        tk('pharmacie', 'P002', 6, 'ordre_arrivee', 'Clos', 1, { etat: 'clos' }),
      ];
      function lireFile(root) {
        const onglets = ongletsDe(root);
        return { kpis: kpisDe(root), onglets, notes: notesDe(root), tables: tableauxDe(root).map((t) => ({ entetes: t.entetes, lignes: t.lignes, pied: t.pied })), boutons: boutonsDe(root).filter((b) => !/^(Sélectionner|Tout sélectionner)/.test(b)) };
      }
      sortie.file = {};
      {
        poser('fileAttente', FILE);
        sortie.file.fixtures = col('fileAttente').all().map(net);
        const root = await monter('m2-file-attente');
        sortie.file.defaut = lireFile(root);
        sortie.file.postes = [];
        for (const t of [...root.querySelectorAll('.tab')]) {
          t.click(); await dormir(60);
          sortie.file.postes.push({ onglet: texte(t), lu: lireFile(root) });
        }
        demonter(root);
        /* l'écran d'appel */
        const ra = await monter('m2-affichage');
        sortie.file.affichage = [...ra.querySelectorAll('.rounded-xl')].map((c) => [...c.querySelectorAll('p')].map(texte));
        sortie.file.affichagePied = [...ra.querySelectorAll('p')].map(texte).slice(-1)[0];
        demonter(ra);
        /* le cabinet */
        const rc = await monter('m2-file-cabinet');
        sortie.file.cabinet = { kpis: kpisDe(rc), cartes: cartesDe(rc), tables: tableauxDe(rc).map((t) => ({ titre: null, entetes: t.entetes, lignes: t.lignes.map((l) => l.cellules) })), vide: texte(rc).includes('Vivier vide') };
        demonter(rc);
        poser('fileAttente', FILE.filter((x) => x.praticien));
        const rc2 = await monter('m2-file-cabinet');
        sortie.file.cabinetSansVivier = { kpis: kpisDe(rc2), cartes: cartesDe(rc2), vide: texte(rc2).includes('Vivier vide') };
        demonter(rc2);
        poser('fileAttente', []);
        const rc3 = await monter('m2-file-cabinet');
        sortie.file.cabinetVide = { kpis: kpisDe(rc3), cartes: cartesDe(rc3), vide: texte(rc3).includes('Vivier vide') };
        demonter(rc3);
        const ra2 = await monter('m2-affichage');
        sortie.file.affichageVide = [...ra2.querySelectorAll('.rounded-xl')].map((c) => [...c.querySelectorAll('p')].map(texte));
        demonter(ra2);
      }

      /* Les gestes de la file */
      sortie.file.gestes = [];
      {
        const ouvrirPoste = async (root, libelle) => { const t = [...root.querySelectorAll('.tab')].find((x) => texte(x).startsWith(libelle)); t.click(); await dormir(60); };
        const cas = [
          ['inscrire à l’accueil, ordre d’arrivée', 'Accueil', { patientCode: patients[2].code, priorite: 'ordre_arrivee', motif: 'Renseignement' }],
          ['inscrire en consultation, praticien désigné, urgence', 'Consultation', { patientCode: patients[3].code, priorite: 'urgence', motif: 'Plaie', praticien: MED[2] }],
          ['inscrire en consultation, file commune', 'Consultation', { patientCode: patients[4].code, priorite: 'rdv', motif: 'Contrôle', praticien: '' }],
          ['inscrire à la salle de prélèvement', 'Salle de prélèvement', { patientCode: patients[1].code, priorite: 'ordre_arrivee', motif: 'Prélèvement' }],
          ['inscrire sans motif : refusé', 'Caisse', { patientCode: patients[1].code, priorite: 'ordre_arrivee', motif: '' }],
        ];
        for (const [nom, poste, saisie] of cas) {
          poser('fileAttente', FILE); prendreMessages();
          const root = await monter('m2-file-attente');
          await ouvrirPoste(root, poste);
          const avant = new Set(col('fileAttente').all().map((x) => x.id));
          bouton('Inscrire un patient', root).click(); await dormir(50);
          const defauts = { priorite: champ('priorite') ? champ('priorite').value : null, praticien: champ('praticien') ? champ('praticien').value : '(absent)' };
          Object.entries(saisie).forEach(([k, v]) => poserChamp(k, v));
          boutonsPied('Inscrire').click(); await dormir(60);
          sortie.file.gestes.push({ nom, poste, saisie, defauts, creees: col('fileAttente').all().filter((x) => !avant.has(x.id)).map(net), messages: prendreMessages(), kpis: kpisDe(root), onglets: ongletsDe(root) });
          demonter(root);
        }
        /* appeler le premier de la consultation */
        {
          poser('fileAttente', FILE); prendreMessages();
          const root = await monter('m2-file-attente');
          await ouvrirPoste(root, 'Consultation');
          const premier = root.querySelector('tbody tr');
          const numero = texte(premier.querySelectorAll('td')[2] || premier);
          bouton('Appeler', premier).click(); await dormir(60);
          sortie.file.gestes.push({ nom: 'appeler le premier de la consultation', numero, apres: col('fileAttente').all().map(net), messages: prendreMessages(), kpis: kpisDe(root), onglets: ongletsDe(root), lu: lireFile(root) });
          demonter(root);
        }
        /* changer la priorité d'un patient */
        {
          const cas2 = [['avec motif', { priorite: 'urgence', motifChangement: 'Douleur aiguë' }], ['sans motif : refusé', { priorite: 'urgence', motifChangement: '' }]];
          for (const [nom, saisie] of cas2) {
            poser('fileAttente', FILE); prendreMessages();
            const root = await monter('m2-file-attente');
            await ouvrirPoste(root, 'Consultation');
            const lignes = [...root.querySelectorAll('tbody tr')];
            const cible = lignes[lignes.length - 1];
            const avantLignes = (tableauxDe(root)[0] || { lignes: [] }).lignes.map((l) => l.cellules[1]);
            [...cible.querySelectorAll('button')].find((b) => b.getAttribute('title') === 'Modifier la priorité').click(); await dormir(50);
            Object.entries(saisie).forEach(([k, v]) => poserChamp(k, v));
            boutonsPied('Appliquer').click(); await dormir(60);
            sortie.file.gestes.push({ nom: 'priorité ' + nom, saisie, avantNumeros: avantLignes, apresNumeros: (tableauxDe(root)[0] || { lignes: [] }).lignes.map((l) => l.cellules[1]), apres: col('fileAttente').all().map(net), messages: prendreMessages() });
            demonter(root);
          }
        }
      }

      /* ======================================================================================================================================
       * 6. AGENDA DU MÉDECIN
       * ==================================================================================================================================== */
      sortie.agendaMedecin = { options: [], praticiens: [] };
      {
        poserConsultations(F1);
        const root = await monter('m2-agenda-medecin');
        const sel = root.querySelector('select');
        sortie.agendaMedecin.options = [...sel.options].map((o) => ({ valeur: o.value, libelle: o.textContent }));
        for (const o of [...sel.options]) {
          changer(sel, o.value); await dormir(60);
          sortie.agendaMedecin.praticiens.push({ praticien: o.value, lu: lire(root) });
        }
        demonter(root);
        poserConsultations([]);
        const r2 = await monter('m2-agenda-medecin');
        sortie.agendaMedecinVide = lire(r2);
        demonter(r2);
      }
      return sortie;
    });
    if (m.erreurs.length) console.log('  (avertissements de chargement : ' + m.erreurs.slice(0, 4).join(' | ') + ')');
    ecrire('packages/domaine/test/vecteurs/ag_agenda.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-agenda.js — les écrans M2 d’accueil lus et pilotés dans Chrome, horloge figée au 16/08/2026 12:00. Ne pas éditer.' }, sortie));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
