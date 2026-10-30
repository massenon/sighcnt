/* =============================================================================
 * VECTEURS DU POSTE D'IMAGERIE — m2-dashboard-imagerie, m2-imagerie-demandes, m2-echographie-galerie
 * -----------------------------------------------------------------------------
 * Les trois écrans RÉELS sont montés sur un magasin dont on pose les fiches, puis LUS comme l'agent les lit (indicateurs, tableaux, boutons
 * de ligne). La demande est ouverte par le moteur exposé `PR.ouvrirDemandeImagerie` (la fabrique unique que la modale « Nouvelle demande » appelle),
 * et le geste « Rendre » est cliqué sur l'écran réel.
 *   node build/vecteurs-img-demandes.js   →   packages/domaine/test/vecteurs/img_demandes.json
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs du poste d’imagerie (3 écrans + ouverture d’une demande)');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m2-consultations.js') });
    const sortie = await m.page.evaluate(async () => {
      const S = SIGH.store, C = SIGH.core, D = SIGH.data, PR = SIGH.parcours;
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
      const nettoyer = (x) => {
        const c = propre(x);
        ['id', '_creePar', '_creeLe', '_modifiePar', '_modifieLe', '_archivePar', '_archiveLe', 'creeLe'].forEach((k) => delete c[k]);
        return c;
      };
      const col = (n) => S.collection(n);
      const vider = (...noms) => noms.forEach((n) => col(n).all().forEach((f) => col(n).archive(f.id)));
      const texte = (e) => (e.innerText || '').replace(/\s+/g, ' ').trim();

      /* --- Lecture d'un écran monté ------------------------------------------------------------------------------------------------------- */
      async function lire(id) {
        const root = document.createElement('div'); document.body.appendChild(root);
        SIGH.screens[id].render(root); await dormir(60);
        const grille = root.querySelector('.grid.gap-3');
        const kpis = grille ? [...grille.children].map((k) => {
          const t = (k.innerText || '').split(/\n+/).map((s) => s.trim()).filter(Boolean);
          return { label: t[0], valeur: t[1], indice: t[2] || null };
        }) : [];
        const tables = [...root.querySelectorAll('.card')].filter((c) => c.querySelector('table')).map((c) => {
          const h = c.querySelector('.card-title');
          return {
            titre: h ? texte(h) : null,
            entetes: [...c.querySelectorAll('thead th')].map(texte).filter((s) => s !== ''),
            lignes: [...c.querySelectorAll('tbody tr')].map((tr) => ({
              cellules: [...tr.querySelectorAll('td')].map(texte),
              boutons: [...tr.querySelectorAll('button')].map((b) => b.getAttribute('title') || b.getAttribute('aria-label') || texte(b)).filter(Boolean),
            })),
            pied: texte(c.querySelector('.border-t, [class*=pagination]') || document.createElement('i')),
          };
        });
        const cartes = [...root.querySelectorAll('.card-title')].map(texte);
        const cliches = [...root.querySelectorAll('img')].map((i) => i.closest('.card')).filter(Boolean).map((c) => ({
          texte: [...c.querySelectorAll('p, span')].map(texte).filter(Boolean), boutons: [...c.querySelectorAll('button')].map((b) => b.getAttribute('title') || b.getAttribute('aria-label') || texte(b)),
        }));
        const bouton = (t) => [...root.querySelectorAll('button')].some((b) => texte(b) === t);
        const res = { kpis, tables, cartes, cliches, texteVide: texte(root), commandes: { nouvelleDemande: bouton('Nouvelle demande'), ajouterCliche: bouton('Ajouter un cliché') } };
        root.remove();
        return res;
      }

      /* --- Les modalités et les examens du catalogue, tels que la maquette les tient ------------------------------------------------------- */
      const IM = D.IMAGERIE;
      const modalites = IM.MODALITES.map((x) => ({ code: x.code, label: x.label, ecran: x.ecran, icone: x.icone }));
      const examens = col('examensImagerie').active().map((x) => ({ code: x.code, label: x.label, modalite: x.modalite || 'echographie' }));
      const exCode = (m) => examens.filter((x) => x.modalite === m).map((x) => x.code);
      const etats = [
        { id: 'demandee', label: 'Demandée — attente caisse' }, { id: 'payee', label: 'Payée — à exécuter' },
        { id: 'executee', label: 'Exécutée — CR en rédaction' }, { id: 'validee', label: 'Validée — CR rendu' },
      ];

      const maintenant = new Date();
      const moisCourant = C.iso(maintenant).slice(0, 7);
      const jourCourant = C.iso(maintenant);
      const unMoisAvant = C.iso(new Date(maintenant.getFullYear(), maintenant.getMonth() - 1, 15));
      const resume = (d) => ({ reference: d.reference, statut: d.statut, examenCode: d.examenCode, urgent: !!d.urgent, patient: d.patient });

      /* --- Fixtures ----------------------------------------------------------------------------------------------------------------------- */
      const D0 = [
        ['IME-00001', 'demandee', 'irm', 'BANI Zoukanéri', 'CNT/62/25', false, '2026-08-24T09:21:00.000Z', 'FI-2026-00407'],
        ['IME-00002', 'payee', 'echographie', 'OROU YO Chantal', 'CNT/162/26', true, '2026-08-25T10:00:00.000Z', 'FI-2026-00408'],
        ['IME-00003', 'payee', 'radiographie', 'ALI Sidi', 'CNT/7/26', false, '2026-08-23T08:30:00.000Z', null],
        ['IME-00004', 'executee', 'scanner', 'TIGRI Séraphine', 'CNT/11/26', false, '2026-08-22T15:00:00.000Z', 'FI-2026-00410'],
        ['IME-00005', 'validee', 'mammographie', 'KOUA Rose', 'CNT/55/26', false, '2026-08-21T11:00:00.000Z', null],
        ['IME-00006', 'validee', 'echographie', 'DJAGBA Paul', 'CNT/90/26', false, '2026-08-20T11:00:00.000Z', null],
        ['IME-00007', 'demandee', 'echographie', 'SOULE Ami', 'CNT/91/26', true, '2026-08-26T11:00:00.000Z', 'FI-2026-00411'],
        ['IME-00008', 'payee', 'irm', 'BANI Zoukanéri', 'CNT/62/25', false, '2026-08-19T08:00:00.000Z', null],
        ['IME-00009', 'validee', 'radiographie', 'ALI Sidi', 'CNT/7/26', false, '2026-08-18T08:00:00.000Z', null],
        ['IME-00010', 'executee', 'echographie', 'KOUA Rose', 'CNT/55/26', false, '2026-08-17T08:00:00.000Z', null],
        ['IME-00011', 'payee', 'scanner', 'DJAGBA Paul', 'CNT/90/26', false, '2026-08-16T08:00:00.000Z', null],
        ['IME-00012', 'validee', 'echographie', 'SOULE Ami', 'CNT/91/26', false, '2026-08-15T08:00:00.000Z', null],
        ['IME-00013', 'demandee', 'radiographie', 'TIGRI Séraphine', 'CNT/11/26', false, '2026-08-14T08:00:00.000Z', 'FI-2026-00413'],
        ['IME-00014', 'validee', 'echographie', 'OROU YO Chantal', 'CNT/162/26', false, '2026-08-13T08:00:00.000Z', null],
      ];
      const posees = D0.map(([ref, statut, mod, patient, code, urgent, dateHeure, fac], i) => {
        const ex = examens.filter((x) => x.modalite === mod)[0];
        return { reference: ref, statut, dateHeure, patientId: 'PATV' + i, patientCode: code, patient, examenCode: ex.code, examen: ex.label, prescripteur: 'Dr TEST ' + (i % 3),
          indication: 'Indication ' + i, urgent, origine: 'consultation', prix: 10000 + i * 1000, factureNumero: fac, bloqueParPaiement: statut === 'demandee' };
      });
      const crOf = (ref, statut, examen, renduLe, demandeRef) => ({ reference: ref, statut, examenCode: examen.code, examen: examen.label, patient: 'X', patientCode: 'CNT/1/26', date: renduLe || jourCourant, renduLe: renduLe || null, prescripteur: 'Dr T', realisateur: 'R', demandeReference: demandeRef });
      const exR = (mod) => examens.filter((x) => x.modalite === mod)[0];
      const crs = [
        crOf('IMG-0001', 'brouillon', exR('echographie'), null, null),
        crOf('IMG-0002', 'brouillon', exR('scanner'), null, null),
        crOf('IMG-0003', 'rendu', exR('echographie'), jourCourant + 'T10:00:00.000Z', null),
        crOf('IMG-0004', 'rendu', exR('echographie'), jourCourant + 'T11:00:00.000Z', null),
        crOf('IMG-0005', 'rendu', exR('radiographie'), jourCourant + 'T12:00:00.000Z', null),
        crOf('IMG-0006', 'rendu', exR('irm'), unMoisAvant + 'T12:00:00.000Z', null),
        crOf('IMG-0007', 'rendu', exR('mammographie'), null, null),
      ];
      /* Un CR « rendu » sans `renduLe` tombe sur sa date : celle-ci est le mois d'avant pour le dernier. */
      crs[6].date = unMoisAvant;
      const modaliteDe = (code) => (examens.filter((x) => x.code === code)[0] || {}).modalite || 'echographie';
      const liees = posees.map((d) => d);
      void liees; void resume; void modaliteDe;

      const taches = (a, b) => [].concat(
        Array.from({ length: a }, (_, i) => ({ type: 'imagerie', poste: 'imagerie', statut: 'en_attente', libelle: 'Examen', reference: 'FI-T-' + i, patient: 'P' + i, date: '2026-08-2' + i + 'T08:00:00.000Z' })),
        Array.from({ length: b }, (_, i) => ({ type: 'imagerie', poste: 'imagerie', statut: 'bloque', libelle: 'Examen', reference: 'FI-B-' + i, patient: 'B' + i, date: '2026-08-1' + i + 'T08:00:00.000Z' })));

      function poser(dems, crList, clList, tList) {
        vider('demandesImagerie', 'resultatsImagerie', 'clichesImagerie', 'taches');
        dems.forEach((d) => col('demandesImagerie').insert(Object.assign({}, d)));
        crList.forEach((d) => col('resultatsImagerie').insert(Object.assign({}, d)));
        clList.forEach((d) => col('clichesImagerie').insert(Object.assign({}, d)));
        tList.forEach((d) => col('taches').insert(Object.assign({}, d)));
      }

      const sortie = { modalites, etats, examens, moisCourant };

      /* --- Registre des demandes ---------------------------------------------------------------------------------------------------------- */
      sortie.registre = [];
      for (const [nom, dems] of [['14 demandes aux quatre états (pagination de 12, tri par date décroissante)', posees], ['registre vide', []], ['une seule demande en attente de caisse', posees.slice(0, 1)]]) {
        poser(dems, [], [], []);
        const lu = await lire('m2-imagerie-demandes');
        sortie.registre.push({ nom, demandes: dems, lu });
      }

      /* --- Poste d'imagerie (tableau de bord) ----------------------------------------------------------------------------------------------- */
      sortie.poste = [];
      for (const [nom, dems, cr, tl] of [
        ['poste chargé : 4 examens payés, 3 en attente de caisse, 2 CR en rédaction, 3 rendus ce mois-ci', posees, crs, taches(2, 1)],
        ['poste vide : rien n’attend', [], [], []],
        ['aucun examen payé mais des CR en rédaction', posees.filter((d) => d.statut !== 'payee'), crs, taches(0, 2)],
      ]) {
        poser(dems, cr, [], tl);
        const lu = await lire('m2-dashboard-imagerie');
        sortie.poste.push({ nom, demandes: dems, comptesRendus: cr, taches: tl, lu });
      }

      /* --- Galerie des clichés --------------------------------------------------------------------------------------------------------- */
      const PIXEL = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
      const cl = (i, patientId, patient, crRef, date) => ({ date, patientId, patient, patientCode: 'CNT/' + i + '/26', examen: examens[0].label, legende: i % 2 ? 'Coupe sagittale' : '', crReference: crRef, fichier: PIXEL, deposePar: 'AHOHOU Rodrigue' });
      const cliches = [cl(1, 'PA1', 'DJAGBA Paul', 'IMG-0003', '2026-08-20T09:00:00.000Z'), cl(2, 'PA1', 'DJAGBA Paul', null, '2026-08-22T09:00:00.000Z'), cl(3, 'PA2', 'KOUA Rose', 'IMG-0004', '2026-08-21T09:00:00.000Z'), cl(5, null, 'ALI Sidi', null, '2026-08-19T09:00:00.000Z')];
      sortie.galerie = [];
      for (const [nom, cList] of [['quatre clichés, trois patients, deux liés à un CR', cliches], ['galerie vide', []]]) {
        poser([], [], cList, []);
        const lu = await lire('m2-echographie-galerie');
        sortie.galerie.push({ nom, cliches: cList.map((c) => Object.assign({}, c, { fichier: 'png' })), lu });
      }

      /* --- Ouverture d'une demande (la fabrique unique appelée par « Nouvelle demande ») ---------------------------------------------------- */
      const tarifs = {};
      examens.forEach((x) => {
        const ex = (col('examensImagerie').active().filter((e) => e.code === x.code)[0]) || {};
        tarifs[x.code] = { nonAssure: D.tarifPrix((ex.tarifCode) || x.code, false), assure: D.tarifPrix((ex.tarifCode) || x.code, true) };
      });
      const patients = col('patients');
      const demain = C.iso(new Date(maintenant.getFullYear() + 1, 5, 1));
      const hier = C.iso(new Date(maintenant.getFullYear() - 1, 5, 1));
      patients.all().forEach((p) => patients.archive(p.id));
      const pNon = patients.insert({ code: 'CNT/7001/26', nom: 'NONASSURE', prenom: 'Awa', sexe: 'F', dateNaissance: '1990-01-01', statut: 'actif' }).record;
      const pAss = patients.insert({ code: 'CNT/7002/26', nom: 'ASSURE', prenom: 'Koffi', sexe: 'M', dateNaissance: '1985-05-05', assureur: 'NSIA', tauxPriseEnCharge: 80, carteExpiration: demain, statut: 'actif' }).record;
      const pExp = patients.insert({ code: 'CNT/7003/26', nom: 'EXPIREE', prenom: 'Marie', sexe: 'F', dateNaissance: '1980-03-03', assureur: 'NSIA', tauxPriseEnCharge: 80, carteExpiration: hier, statut: 'actif' }).record;
      const pAgent = patients.insert({ code: 'CNT/7004/26', nom: 'AGENT', prenom: 'Luc', sexe: 'M', dateNaissance: '1975-03-03', personnelId: 'PERS1', statut: 'actif' }).record;
      const DATE = '2026-10-30T09:00:00.000Z';
      const base = { date: DATE, prescripteur: 'Dr TEST', indication: 'Douleurs', urgent: false, secteurDemandeur: 'Consultation', origine: 'consultation' };
      const cas = [
        ['patient non assuré, une échographie', { patientId: pNon.id, examens: [exCode('echographie')[0]] }],
        ['patient assuré (carte valide), IRM : tarif assuré, 80 % à l’assureur', { patientId: pAss.id, examens: [exCode('irm')[0]] }],
        ['carte EXPIRÉE : facturé au tarif non assuré (RG-09)', { patientId: pExp.id, examens: [exCode('echographie')[0]] }],
        ['agent du personnel : pris en charge à 100 % par la clinique', { patientId: pAgent.id, examens: [exCode('radiographie')[0]] }],
        ['trois examens, dont un urgent', { patientId: pNon.id, examens: [exCode('echographie')[0], exCode('radiographie')[0], exCode('scanner')[0]], urgent: true }],
        ['patient adressé de l’extérieur : le dossier naît (âge déclaré)', { nom: 'externe', prenom: 'Jean', sexe: 'M', age: 40, telephone: '97000000', residence: 'Quartier Nord', examens: [exCode('echographie')[0]], origine: 'externe' }],
        ['externe avec prescripteur extérieur et date de naissance', { nom: 'Autre', prenom: 'Zoe', sexe: 'F', dateNaissance: '2001-02-03', examens: [exCode('mammographie')[0]], origine: 'externe', prescripteur: 'Dr Extérieur — CS Nord' }],
        ['aucun examen coché : refusé', { patientId: pNon.id, examens: [] }],
        ['examen sans tarif au catalogue : refusé en le nommant', { patientId: pNon.id, examens: ['IMG-INCONNU'] }],
        ['un examen tarifé et un sans tarif : refusé, rien n’est facturé', { patientId: pNon.id, examens: [exCode('echographie')[0], 'IMG-INCONNU'] }],
        ['externe sans identité : refusé', { nom: '', prenom: '', examens: [exCode('echographie')[0]], origine: 'externe' }],
        ['patient introuvable', { patientId: 'PATFANTOME', examens: [exCode('echographie')[0]] }],
      ];
      sortie.ouverture = [];
      vider('demandesImagerie', 'taches', 'notifications');
      col('factures').all().forEach((f) => col('factures').archive(f.id));
      for (const [nom, v] of cas) {
        const avantD = new Set(col('demandesImagerie').all().map((x) => x.id));
        const avantT = new Set(col('taches').all().map((x) => x.id));
        const avantN = new Set(col('notifications').all().map((x) => x.id));
        const avantF = new Set(col('factures').all().map((x) => x.id));
        const avantP = new Set(patients.all().map((x) => x.id));
        const entree = { nom, v: Object.assign({}, base, v), rangFactures: col('factures').all().length, rangPatients: patients.all().length,
          referencesExistantes: col('demandesImagerie').all().map((x) => x.reference) };
        const patientsDe = patients.all().map(propre);
        let erreur = null, res = null;
        try { res = PR.ouvrirDemandeImagerie(Object.assign({}, base, v)); } catch (e) { erreur = e.message; }
        const nouveaux = (c, avant) => col(c).all().filter((x) => !avant.has(x.id));
        sortie.ouverture.push({
          entree: Object.assign(entree, { nbPatients: patientsDe.length }), patientsAvant: patientsDe.filter((x) => x.id === v.patientId), erreur,
          demandes: nouveaux('demandesImagerie', avantD).map((x) => Object.assign(nettoyer(x), { _archivee: x.statut === 'archive' })),
          factures: nouveaux('factures', avantF).map(nettoyer),
          taches: nouveaux('taches', avantT).map(nettoyer),
          notifications: nouveaux('notifications', avantN).map(nettoyer),
          patientsCrees: patients.all().filter((x) => !avantP.has(x.id)).map(nettoyer),
        });
      }
      sortie.tarifs = tarifs;

      /* --- La modale « Nouvelle demande » PILOTÉE comme le fait l'agent ---------------------------------------------------------------------- */
      const soignants = col('soignants').active().filter((x) => x.prescrit);
      sortie.modale = [];
      async function modale(nom, saisie) {
        const root = document.createElement('div'); document.body.appendChild(root);
        document.getElementById('toast-host') && (document.getElementById('toast-host').innerHTML = '');
        SIGH.screens['m2-imagerie-demandes'].render(root); await dormir(60);
        [...root.querySelectorAll('button')].find((b) => texte(b) === 'Nouvelle demande').click(); await dormir(80);
        const poserChamp = (id, val) => { const e = document.getElementById('f_' + id); if (!e) throw new Error('champ ' + id); e.value = val; e.dispatchEvent(new Event('input')); e.dispatchEvent(new Event('change')); };
        Object.entries(saisie).forEach(([k, val]) => poserChamp(k, val));
        await dormir(40);
        const avantD = new Set(col('demandesImagerie').all().map((x) => x.id)), avantP = new Set(patients.all().map((x) => x.id));
        const avantF = new Set(col('factures').all().map((x) => x.id));
        const champsVisibles = [...document.querySelectorAll('[id^=f_]')].filter((e) => e.offsetParent !== null).map((e) => e.id.replace('f_', ''));
        [...document.querySelectorAll('button')].filter((b) => texte(b) === 'Émettre la demande').pop().click();
        await dormir(120);
        const out = {
          nom, saisie, champsVisibles, toast: texte(document.getElementById('toast-host') || document.createElement('i')),
          modaleOuverte: [...document.querySelectorAll('button')].some((b) => texte(b) === 'Émettre la demande'),
          demandes: col('demandesImagerie').all().filter((x) => !avantD.has(x.id)).map(nettoyer),
          patientsCrees: patients.all().filter((x) => !avantP.has(x.id)).map(nettoyer),
          factures: col('factures').all().filter((x) => !avantF.has(x.id)).map((f) => ({ numero: f.numero, montantTTC: f.montantTTC, partPatient: f.partPatient })),
        };
        document.querySelectorAll('.modal-root, [role=dialog]').forEach((e) => e.remove()); root.remove();
        sortie.modale.push(out);
      }
      const ecoPel = exCode('echographie')[0];
      await modale('patient du répertoire, un examen, prescripteur de la maison', { patientCode: 'CNT/7001/26', examens: [ecoPel], prescripteur: soignants[0].nomComplet, indication: 'Douleurs pelviennes' });
      await modale('patient adressé de l’extérieur (âge déclaré), prescripteur EXTÉRIEUR nommé', { nom: 'Kora', prenom: 'Salou', sexe: 'M', naissanceConnue: 'age', age: 33, telephone: '96000000', residence: 'Tchaourou', examens: [ecoPel], prescripteur: 'EXTERNE', prescripteurExterne: 'Dr SALIFOU Aminou, CS de Perma', indication: 'Bilan' });
      await modale('ni patient ni identité : refusé en le disant', { examens: [ecoPel], prescripteur: soignants[0].nomComplet, indication: 'x' });
      await modale('formulaire incomplet (indication absente) : erreurs, rien n’est écrit', { patientCode: 'CNT/7001/26', examens: [ecoPel], prescripteur: soignants[0].nomComplet });
      await modale('prescripteur extérieur sans nom libre : « Prescripteur extérieur »', { patientCode: 'CNT/7001/26', examens: [ecoPel], prescripteur: 'EXTERNE', indication: 'Bilan' });
      sortie.nomsPrescripteur = [
        ['interne', { prescripteur: 'Dr X' }], ['externe nommé', { prescripteur: 'EXTERNE', prescripteurExterne: '  Dr Y, CS Z ' }],
        ['externe sans nom', { prescripteur: 'EXTERNE', prescripteurExterne: '' }], ['externe espaces', { prescripteur: 'EXTERNE', prescripteurExterne: '   ' }],
      ].map(([nom, vv]) => ({ nom, v: vv, attendu: SIGH.kit.nomPrescripteur(vv, null, 'prescripteur') }));

      /* --- D.tarifPrix (RG-09) sur TOUT le catalogue tarifaire : non assuré / assuré, non couvert, certificats SOS, acte absent ------------------- */
      sortie.tarifPrix = D.CATALOGUE.map((e) => ({
        entree: { code: e.code, prixNonAssure: e.prixNonAssure, prixAssure: e.prixAssure, nonCouvert: !!e.nonCouvert, assurable: e.assurable },
        nonAssure: propre(D.tarifPrix(e.code, false)), assure: propre(D.tarifPrix(e.code, true)),
      })).concat([{ entree: null, code: 'ABSENT-DU-CATALOGUE', nonAssure: propre(D.tarifPrix('ABSENT-DU-CATALOGUE', false)), assure: propre(D.tarifPrix('ABSENT-DU-CATALOGUE', true)) }]);

      /* --- « Rendre » cliqué sur l'écran réel -------------------------------------------------------------------------------------------------- */
      vider('demandesImagerie', 'resultatsImagerie', 'notifications');
      document.getElementById('toast-host') && (document.getElementById('toast-host').innerHTML = '');
      const dem = col('demandesImagerie').insert(Object.assign({}, posees[3], { patientId: pNon.id })).record;
      const exo = exR('scanner');
      const cr1 = col('resultatsImagerie').insert({ reference: 'IMG-0100', statut: 'brouillon', demandeImagerieId: dem.id, demandeReference: dem.reference, examenCode: exo.code, examen: exo.label,
        patientId: pNon.id, patient: 'NONASSURE Awa', patientCode: 'CNT/7001/26', prescripteur: 'Dr TEST', realisateur: 'R', conclusion: '', date: DATE }).record;
      const root = document.createElement('div'); document.body.appendChild(root);
      SIGH.screens['m2-imagerie-demandes'].render(root); await dormir(60);
      const cliquer = async (t) => {
        const b = [...document.querySelectorAll('button')].filter((x) => texte(x) === t).pop();
        if (!b) throw new Error('bouton ' + t); b.click(); await dormir(80);
      };
      sortie.rendre = [];
      await cliquer('Rendre'); await dormir(50);
      const toastSans = texte(document.getElementById('toast-host') || document.createElement('i'));
      sortie.rendre.push({ nom: 'conclusion absente : refusé', toast: toastSans, crApres: nettoyer(col('resultatsImagerie').get(cr1.id)), demandeApres: nettoyer(col('demandesImagerie').get(dem.id)), notifications: col('notifications').active().length });
      col('resultatsImagerie').update(cr1.id, { conclusion: 'Examen sans particularité.' });
      root.remove();
      const root2 = document.createElement('div'); document.body.appendChild(root2);
      SIGH.screens['m2-imagerie-demandes'].render(root2); await dormir(60);
      await cliquer('Rendre');
      const ok = [...document.querySelectorAll('button')].filter((x) => texte(x) === 'Rendre');
      void ok;
      const confirmer = [...document.querySelectorAll('button')].filter((x) => texte(x) === 'Rendre').pop();
      confirmer.click(); await dormir(150);
      const apres = nettoyer(col('resultatsImagerie').get(cr1.id));
      sortie.rendre.push({ nom: 'conclusion posée : rendu au prescripteur, demande validée', crApres: apres, demandeApres: nettoyer(col('demandesImagerie').get(dem.id)),
        notifications: col('notifications').active().map(nettoyer), toast: texte(document.getElementById('toast-host') || document.createElement('i')), maintenant: maintenant.toISOString().slice(0, 10) });
      root2.remove();
      return sortie;
    });
    const lu = (c) => c.length;
    console.log('  registre ' + lu(sortie.registre) + ' · poste ' + lu(sortie.poste) + ' · galerie ' + lu(sortie.galerie) + ' · ouvertures ' + lu(sortie.ouverture) + ' · rendre ' + lu(sortie.rendre));
    sortie.ouverture.forEach((o) => console.log('   - ' + o.entree.nom + ' → ' + (o.erreur ? 'REFUS ' + o.erreur : o.demandes.map((d) => d.reference + ' ' + d.prix).join(', ') + ' · facture ' + (o.factures[0] || {}).numero)));
    console.log(JSON.stringify(sortie.rendre, null, 1).slice(0, 1800));
    ecrire('packages/domaine/test/vecteurs/img_demandes.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-img-demandes.js — les trois écrans du poste d’imagerie pilotés. Ne pas éditer.' }, sortie));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
