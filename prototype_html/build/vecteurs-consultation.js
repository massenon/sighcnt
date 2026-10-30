/* =============================================================================
 * VECTEURS DE LA CONSULTATION — m2-consultations, m2-dossiers-consultation, m2-consultation-fiche, m2-pathologies, m2-ordonnances,
 * m2-prescriptions, m2-salle-soins, m2-dossier-consultation-nouveau, m2-ordonnance-nouvelle
 * -----------------------------------------------------------------------------
 * 1. Les six registres RÉELS sont montés sur le jeu amorcé et LUS comme l'agent les lit (indicateurs, onglets, en-têtes, lignes).
 * 2. Les moteurs que ces écrans appellent sont rejoués sur des fixtures POSÉES : `SIGH.consultationZone2.enregistrerDossier` /
 *    `enregistrerFiche` (le moteur exposé « pour être SONDÉ »), `PR.prescrire`, `PR.prescrireSoins`, `PR.administrer`, `PR.soinsDuSecteur`.
 *    Chaque cas enregistre l'ENTRÉE (fiches posées) et la SORTIE (fiches écrites / modifiées, refus nommé).
 * 3. Les référentiels de la maquette (`data-dossier.js`, `data-clinique.js`, `data.js`) sont ENGENDRÉS en Dart : jamais recopiés à la main.
 *   node build/vecteurs-consultation.js   →   packages/domaine/test/vecteurs/consultation.json
 *                                              packages/domaine/lib/src/consultation/cs_donnees.dart
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');
const JEU_DIR = path.join(ROOT, '..', 'apps/poste/assets/donnees/jeu');
const jeu = {};
['consultations', 'dossiersConsultation', 'ordonnances', 'prescriptions', 'administrations', 'pathologies', 'soignants'].forEach((n) => {
  jeu[n] = JSON.parse(fs.readFileSync(path.join(JEU_DIR, n + '.json'), 'utf8'));
});

/** JSON → littéral Dart `const` (chaînes à guillemets simples, `$` et `\` échappés). */
function litteralDart(x, indent) {
  const pad = '  '.repeat(indent || 0);
  if (x === null || x === undefined) return 'null';
  if (typeof x === 'string') return "'" + x.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$').replace(/\n/g, '\\n') + "'";
  if (typeof x === 'number') return Number.isInteger(x) ? String(x) : String(x);
  if (typeof x === 'boolean') return String(x);
  if (Array.isArray(x)) {
    if (!x.length) return '<Object?>[]';
    return '[\n' + x.map((v) => pad + '  ' + litteralDart(v, (indent || 0) + 1) + ',').join('\n') + '\n' + pad + ']';
  }
  const ks = Object.keys(x);
  if (!ks.length) return '<String, Object?>{}';
  return '{\n' + ks.map((k) => pad + '  ' + litteralDart(k) + ': ' + litteralDart(x[k], (indent || 0) + 1) + ',').join('\n') + '\n' + pad + '}';
}

(async () => {
  console.log('▶ Vecteurs de la consultation (6 registres + moteurs dossier / fiche / prescription / soins)');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m2-consultations.js') });
    const sortie = await m.page.evaluate(async (jeu) => {
      const S = SIGH.store, C = SIGH.core, D = SIGH.data, PR = SIGH.parcours;
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
      const texte = (e) => (e.innerText || '').replace(/\s+/g, ' ').trim();
      const col = (n) => S.collection(n);
      const db = () => S.raw();

      /* --- 1. Lecture d'un écran monté ------------------------------------------------------------------------------------------------ */
      function releve(root) {
        const grille = root.querySelector('.grid.gap-3');
        const kpis = grille ? [...grille.children].map((k) => {
          const t = (k.innerText || '').split(/\n+/).map((s) => s.trim()).filter(Boolean);
          return { label: t[0], valeur: t[1], indice: t[2] || null };
        }) : [];
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
        const onglets = [...root.querySelectorAll('[role=tab], button.tab, .tabs button')].map(texte);
        const cartes = [...root.querySelectorAll('.card-title')].map(texte);
        const boutons = [...root.querySelectorAll('button')].map((b) => b.getAttribute('title') || b.getAttribute('aria-label') || texte(b)).filter(Boolean);
        return { kpis, tables, onglets, cartes, boutons };
      }
      async function lire(id, apres) {
        const root = document.createElement('div'); document.body.appendChild(root);
        SIGH.screens[id].render(root); await dormir(80);
        const res = releve(root);
        if (apres) { res.suite = await apres(root); }
        root.remove();
        return res;
      }
      async function cliquerOnglets(root) {
        const sortieOnglets = {};
        const btns = [...root.querySelectorAll('button')].filter((b) => /^(Toutes|Prescriptions de soins|Ordonnances|En cours|Tableau de morbidité|Référentiel)/.test(texte(b)));
        for (const b of btns) {
          b.click(); await dormir(60);
          sortieOnglets[texte(b)] = releve(root);
        }
        return sortieOnglets;
      }

      const moisCourant = C.iso(new Date()).slice(0, 7);
      const jourCourant = C.iso(new Date());
      /* Le JEU du poste (apps/poste/assets/donnees/jeu) est posé dans le magasin de la maquette : c'est lui que le test Flutter chargera. */
      Object.keys(jeu).forEach((n) => { db()[n] = propre(jeu[n]); });
      const ajustements = [];
      const ajuster = (nom, i, patch) => { const f = db()[nom][i]; Object.assign(f, patch); ajustements.push({ col: nom, id: f.id, patch }); };
      [1, 2, 3, 4, 5].forEach((n, i) => ajuster('consultations', i, { date: moisCourant + '-0' + n + 'T10:00:00.000Z' }));
      [0, 1, 2].forEach((i) => ajuster('dossiersConsultation', i, { dateArrivee: jourCourant }));
      const ecrans = {};
      ecrans['m2-consultations'] = await lire('m2-consultations');
      ecrans['m2-dossiers-consultation'] = await lire('m2-dossiers-consultation');
      ecrans['m2-pathologies'] = await lire('m2-pathologies', cliquerOnglets);
      ecrans['m2-ordonnances'] = await lire('m2-ordonnances');
      ecrans['m2-prescriptions'] = await lire('m2-prescriptions', cliquerOnglets);
      ecrans['m2-salle-soins'] = await lire('m2-salle-soins');
      const comptes = {
        consultations: col('consultations').active().length, dossiers: col('dossiersConsultation').active().length,
        ordonnances: col('ordonnances').active().length, prescriptions: col('prescriptions').active().length,
        pathologies: col('pathologies').active().length,
      };

      /* --- 2. Référentiels de la maquette ---------------------------------------------------------------------------------------------- */
      const referentiels = propre({
        appareils: D.APPAREILS_EXAMEN, temps: D.TEMPS_EXAMEN, antecedents: D.CATEGORIES_ANTECEDENT, etatsDossier: D.ETATS_DOSSIER,
        typesVenue: D.TYPES_VENUE, etatsGeneraux: D.ETATS_GENERAUX, pathologiesObstetricales: D.PATHOLOGIES_OBSTETRICALES_ANTERIEURES,
        examenObstetrical: D.EXAMEN_OBSTETRICAL, rubriquesChirurgicales: D.RUBRIQUES_CHIRURGICALES, chapitres: D.CHAPITRES_PATHOLOGIE,
        originesPrescription: D.ORIGINES_PRESCRIPTION, secteursSoins: D.SECTEURS_SOINS, modalites: D.MODALITES_TRAITEMENT,
        mentionNormale: D.MENTION_NORMALE,
      });
      const syntheses = [
        { examens: {}, attendu: D.syntheseExamen({}) },
        { examens: { cardio_vasculaire: { inspection: 'RAS', palpation: 'RAS' } }, attendu: D.syntheseExamen({ cardio_vasculaire: { inspection: 'RAS', palpation: 'RAS' } }) },
        { examens: { cardio_vasculaire: { inspection: 'RAS', auscultation: 'Souffle systolique' }, genito_urinaire: { menstruation: 'Régulières' }, global: { inspection: 'ancien' } },
          attendu: D.syntheseExamen({ cardio_vasculaire: { inspection: 'RAS', auscultation: 'Souffle systolique' }, genito_urinaire: { menstruation: 'Régulières' }, global: { inspection: 'ancien' } }) },
        { examens: { orl: { inspection: '   ' } }, attendu: D.syntheseExamen({ orl: { inspection: '   ' } }) },
      ];
      const transitions = [];
      D.ETATS_DOSSIER.forEach((a) => D.ETATS_DOSSIER.forEach((b) => transitions.push({ de: a.code, vers: b.code, permise: D.transitionPermise(a.code, b.code) })));
      transitions.push({ de: 'inconnu', vers: 'consultation', permise: D.transitionPermise('inconnu', 'consultation') });
      const ancien = D.examensPhysiquesDe({ exam_inspection: 'x', exam_palpation: 'y' });

      /* --- 3. Fixtures et moteurs ------------------------------------------------------------------------------------------------------- */
      const WATCH = ['consultations', 'dossiersConsultation', 'ordonnances', 'demandesAnalyses', 'demandesImagerie', 'factures', 'taches',
        'notifications', 'prescriptions', 'administrations'];
      const poser = (nom, fiches) => { db()[nom] = propre(fiches); };
      const instantane = () => { const o = {}; WATCH.forEach((n) => { o[n] = propre(db()[n] || []); }); return o; };
      const IGN = new Set(['_creePar', '_creeLe', '_modifiePar', '_modifieLe', '_archivePar', '_archiveLe']);
      const net = (f) => { const c = propre(f); IGN.forEach((k) => delete c[k]); return c; };
      function ecart(avant, apres) {
        const inserts = {}, modifs = {};
        WATCH.forEach((n) => {
          const a = new Map((avant[n] || []).map((f) => [f.id, f]));
          (apres[n] || []).forEach((f) => {
            if (!a.has(f.id)) { (inserts[n] = inserts[n] || []).push(net(f)); return; }
            const b = a.get(f.id), patch = {};
            Object.keys(f).forEach((k) => { if (!IGN.has(k) && JSON.stringify(f[k]) !== JSON.stringify(b[k])) patch[k] = f[k]; });
            Object.keys(b).forEach((k) => { if (!IGN.has(k) && !(k in f)) patch[k] = null; });
            if (Object.keys(patch).length) (modifs[n] = modifs[n] || []).push({ id: f.id, patch: propre(patch) });
          });
        });
        return { inserts, modifs };
      }

      /* Catalogues réels dont les cas ont besoin (enregistrés TELS QUELS dans l'entrée). */
      const produits = col('produits').active().filter((p) => p.categorie === 'medicament' && p.prixAchat > 0).slice(0, 3).map(propre);
      const analyses = D.ANALYSES.slice(0, 3).map(propre);
      const actes = col('actes').active().filter((a) => a.prix > 0).slice(0, 2).map(propre);
      const examensToutes = col('examensImagerie').active();
      const avecTarif = examensToutes.filter((x) => { const t = D.tarifPrix((x.tarifCode) || x.code, false); return t.montant != null; });
      const examens = avecTarif.slice(0, 2).map(propre);
      const examenSansTarif = { id: 'EXI-SANS', code: 'IMG-SANS-PRIX', label: 'Examen sans tarif (fixture)', modalite: 'echographie', statut: 'actif' };
      const cat = propre(D.CATALOGUE);
      const ami = D.tarifParFamille('AMI').filter((a) => a.prixNonAssure != null).slice(0, 3).map((a) => a.code);
      const amiSansPrix = D.tarifParFamille('AMI').filter((a) => a.prixNonAssure == null).slice(0, 1).map((a) => a.code);
      const soignants = propre(col('soignants').active());
      const pathologies = propre(col('pathologies').active());
      const medecinNom = soignants.filter((s) => s.prescrit)[0].nomComplet;

      const PATS = [
        { id: 'PATX1', code: 'CNT/1001/26', nom: 'ALPHA', prenom: 'Une', sexe: 'F', dateNaissance: '1990-01-01', statut: 'actif' },
        { id: 'PATX2', code: 'CNT/1002/26', nom: 'BETA', prenom: 'Deux', sexe: 'M', dateNaissance: '1985-05-05', statut: 'actif',
          assureur: 'NSIA', assureurNom: 'NSIA', tauxPriseEnCharge: 80, carteExpiration: '2099-12-31' },
        { id: 'PATX3', code: 'CNT/1003/26', nom: 'GAMMA', prenom: 'Trois', sexe: 'F', dateNaissance: '1992-02-02', statut: 'actif',
          assureur: 'NSIA', assureurNom: 'NSIA', tauxPriseEnCharge: 80, carteExpiration: '2020-01-01' },
        { id: 'PATX4', code: 'CNT/1004/26', nom: 'DELTA', prenom: 'Quatre', sexe: 'M', dateNaissance: '1980-04-04', statut: 'actif', personnelId: 'EMP01' },
        { id: 'PATX5', code: 'CNT/1005/26', nom: 'EPSILON', prenom: 'Cinq', sexe: 'F', dateNaissance: '1995-05-05', statut: 'actif' },
      ];
      const RELEVES = [
        { id: 'CSTX1', statut: 'actif', patientCode: 'CNT/1001/26', patientId: 'PATX1', dateHeure: '2026-08-10T08:00', temperature: 37.2, tension: '12/8', pouls: 80, spo2: 98, poids: 60, taille: 165, releveePar: 'ACCUEIL X' },
        { id: 'CSTX2', statut: 'actif', patientCode: 'CNT/1001/26', patientId: 'PATX1', dateHeure: '2026-08-12T09:30', temperature: 38.1, tension: '13/8', pouls: 96, spo2: 97, poids: 61, taille: 165, imc: 22.4, releveePar: 'ACCUEIL Y' },
      ];
      function monter() {
        ['consultations', 'dossiersConsultation', 'ordonnances', 'demandesAnalyses', 'demandesImagerie', 'factures', 'taches', 'notifications',
          'prescriptions', 'administrations'].forEach((n) => poser(n, []));
        poser('patients', PATS); poser('couverturesAssurance', []); poser('constantes', RELEVES);
        poser('examensImagerie', examensToutes.map(propre).concat([examenSansTarif]));
      }
      const idCode = (c) => c.match(/\/(\d+)\//)[1];
      const DOSS = (patientCode, etat, extra) => Object.assign({
        id: 'DOSX-' + idCode(patientCode) + etat, statut: 'actif', reference: 'DOS-9' + idCode(patientCode), patientCode, nip: patientCode,
        patient: 'X', etat, motifVenue: 'Fièvre', typeVenue: 'premiere', soignant: medecinNom, dateArrivee: '2026-08-15', dossierSaisiLe: '2026-08-15T09:00:00.000Z',
      }, extra || {});

      async function essayer(f) {
        try { return { resultat: await f() }; } catch (e) { return { erreur: e.message, code: e.code || null }; }
      }
      const cas = { dossier: [], fiche: [], prescrire: [], soins: [], administrer: [], soinsDuSecteur: [] };
      async function jouer(groupe, nom, preparer, appeler, nettoyerSortie) {
        monter();
        const entree = propre(preparer() || {});
        if (entree.dossiers) poser('dossiersConsultation', entree.dossiers);
        const avant = instantane();
        const r = await essayer(appeler);
        const apres = instantane();
        const e = ecart(avant, apres);
        cas[groupe].push({ nom, entree, sortie: Object.assign({ erreur: r.erreur || null, code: r.code || null }, e, nettoyerSortie ? nettoyerSortie(r.resultat) : {}) });
      }

      const Z = SIGH.consultationZone2;
      const dossierComplet = (patientCode, extra) => Object.assign({
        patientCode, soignant: medecinNom, typeVenue: 'premiere', dateArrivee: '2026-08-15', heureArrivee: '08h30', motifVenue: 'Fièvre et céphalées',
        histoire: 'Depuis trois jours', traitementEnCours: '', ant_medicaux: 'HTA', ant_chirurgicaux: '', ant_gyneco_obstetricaux: '',
        allergies: '', allergiesMedicamenteuses: 'Pénicilline', etatGeneral: 'bon', etatGeneralPrecision: '',
        examensPhysiques: { cardio_vasculaire: { inspection: 'RAS', auscultation: 'RAS' }, orl: { inspection: 'Angine' } },
        antecedentsObstetricaux: null, examenObstetrical: null,
        actesChirurgicaux: 'Cure de hernie', indicationOperatoire: '', blocPrevu: '', risqueOperatoire: '',
      }, extra || {});

      /* ---- enregistrerDossier ---- */
      await jouer('dossier', 'création complète, constantes de l’accueil copiées (relevé le plus récent)', () => ({ patients: PATS, constantes: RELEVES }),
        () => { const r = Z.enregistrerDossier(dossierComplet('CNT/1001/26', { antecedentsObstetricaux: { gestite: 2, parite: 1, pathologies: ['Œuf clair'] }, examenObstetrical: { terme: '30 SA' } }), null); return r; });
      await jouer('dossier', 'patient sans relevé : constantesAccueil nul', () => ({ patients: PATS }),
        () => Z.enregistrerDossier(dossierComplet('CNT/1002/26'), null));
      await jouer('dossier', 'patient inconnu au répertoire', () => ({}), () => Z.enregistrerDossier(dossierComplet('CNT/9999/26'), null));
      await jouer('dossier', 'second dossier ouvert pour le même patient : refusé en nommant le premier',
        () => { poser('dossiersConsultation', [DOSS('CNT/1001/26', 'consultation')]); return { dossiers: [DOSS('CNT/1001/26', 'consultation')] }; },
        () => { poser('dossiersConsultation', [DOSS('CNT/1001/26', 'consultation')]); return Z.enregistrerDossier(dossierComplet('CNT/1001/26'), null); });
      await jouer('dossier', 'un dossier EN ATTENTE ne bloque pas l’ouverture d’un autre (il n’est pas « enregistré »)',
        () => { return { dossiers: [DOSS('CNT/1001/26', 'attente')] }; },
        () => { poser('dossiersConsultation', [DOSS('CNT/1001/26', 'attente')]); return Z.enregistrerDossier(dossierComplet('CNT/1001/26'), null); });
      await jouer('dossier', 'édition d’un dossier EN ATTENTE : passe en consultation, constantes déjà posées conservées',
        () => { return { dossiers: [DOSS('CNT/1001/26', 'attente', { constantesAccueil: { temperature: 99 } })] }; },
        () => { const d = DOSS('CNT/1001/26', 'attente', { constantesAccueil: { temperature: 99 } }); poser('dossiersConsultation', [d]); return Z.enregistrerDossier(dossierComplet('CNT/1001/26', { motifVenue: 'Corrigé' }), propre(d)); });
      await jouer('dossier', 'édition d’un dossier CLÔTURÉ : refusée',
        () => ({ dossiers: [DOSS('CNT/1001/26', 'cloture')] }),
        () => { const d = DOSS('CNT/1001/26', 'cloture'); poser('dossiersConsultation', [d]); return Z.enregistrerDossier(dossierComplet('CNT/1001/26'), propre(d)); });
      await jouer('dossier', 'édition d’un dossier EN CONSULTATION : état inchangé, rubriques chirurgicales gardées (non chirurgien)',
        () => ({ dossiers: [DOSS('CNT/1001/26', 'consultation', { actesChirurgicaux: 'Ancien acte' })] }),
        () => { const d = DOSS('CNT/1001/26', 'consultation', { actesChirurgicaux: 'Ancien acte' }); poser('dossiersConsultation', [d]); return Z.enregistrerDossier(dossierComplet('CNT/1001/26', { actesChirurgicaux: 'Nouvel acte' }), propre(d)); });

      /* ---- prescrire (moteur du parcours) ---- */
      const med = (i, q) => ({ produitId: produits[i].id, quantite: q, posologie: '1 cp × 3/j', duree: '5 jours' });
      const base = (patientCode, extra) => Object.assign({
        patientCode, medecin: medecinNom, diagnostic: 'Paludisme', date: '2026-08-20T09:00:00.000Z', secteurDemandeur: 'Consultation',
        medicaments: [med(0, 2), med(1, 3)], analyses: [analyses[0].code, analyses[1].code], actes: [actes[0].code], imagerie: [examens[0].code],
      }, extra || {});
      const fixtureCatalogues = () => ({ patients: PATS });
      const prescrireCas = [
        ['patient non assuré : médicaments, analyses, acte et imagerie (une facture globale)', base('CNT/1001/26')],
        ['patient assuré (carte valide) : parts assureur / patient sur chaque ligne', base('CNT/1002/26')],
        ['carte EXPIRÉE : tarif non assuré, facturation intégrale au patient (RG-09)', base('CNT/1003/26')],
        ['agent de la clinique : prise en charge du personnel, jamais une créance', base('CNT/1004/26')],
        ['médicaments seuls, urgence', base('CNT/1001/26', { analyses: [], actes: [], imagerie: [], urgent: true })],
        ['analyses seules', base('CNT/1001/26', { medicaments: [], actes: [], imagerie: [] })],
        ['quantité nulle : la ligne est écartée', base('CNT/1001/26', { medicaments: [med(0, 0), med(1, 1)], analyses: [], actes: [], imagerie: [] })],
        ['imagerie sans tarif : refusée en nommant l’examen, rien d’orphelin', base('CNT/1001/26', { medicaments: [med(0, 1)], analyses: [], actes: [], imagerie: ['IMG-SANS-PRIX'] })],
        ['ordonnance vide (aucune ligne)', base('CNT/1001/26', { medicaments: [], analyses: [], actes: [], imagerie: [] })],
        ['patient introuvable', base('CNT/9999/26')],
      ];
      for (const [nom, v] of prescrireCas) {
        await jouer('prescrire', nom, fixtureCatalogues, () => PR.prescrire(propre(v)), (r) => (r ? { retour: { ordonnanceNumero: r.ordonnance.numero, factureNumero: r.facture.numero, demandes: r.demandes.length, demandesImagerie: r.demandesImagerie.length, taches: r.taches.length } } : {}));
        cas.prescrire[cas.prescrire.length - 1].params = v;
      }
      /* numérotation : un second appel numérote à la suite (série lue sur les fiches existantes). */
      monter();
      PR.prescrire(propre(base('CNT/1001/26', { medicaments: [med(0, 1)], analyses: [analyses[0].code], actes: [], imagerie: [] })));
      {
        const avant = instantane();
        const r = PR.prescrire(propre(base('CNT/1001/26', { medicaments: [med(0, 1)], analyses: [analyses[0].code], actes: [], imagerie: [] })));
        cas.prescrire.push({ nom: 'second appel : numéros, références LAB- et code d’analyse à la suite', entree: { avant: propre(avant) },
          params: base('CNT/1001/26', { medicaments: [med(0, 1)], analyses: [analyses[0].code], actes: [], imagerie: [] }),
          sortie: Object.assign({ erreur: null, code: null }, ecart(avant, instantane())) });
      }

      /* ---- enregistrerFiche ---- */
      const fiche = (patientCode, extra) => Object.assign({
        patientCode, medecin: medecinNom, date: '2026-08-20T09:00', resumeSyndromique: 'Syndrome fébrile', hypotheses: 'Palu', pathologies: [pathologies[0].code],
        diagnostic: 'Paludisme simple', traitementEmblee: '', conduite: 'Repos', orientation: 'domicile', tarif: 3000,
        medicaments: [], analyses: [], imagerie: [],
      }, extra || {});
      const avecDossier = (code, etat) => () => { poser('dossiersConsultation', [DOSS(code, etat || 'consultation', { constantesAccueil: { temperature: 38.1, tension: '13/8', poids: 61, pouls: 96 } })]); };
      const ficheCas = [
        ['sans dossier : SANS_DOSSIER', () => {}, fiche('CNT/1001/26')],
        ['dossier EN ATTENTE : refusé en le disant', avecDossier('CNT/1001/26', 'attente'), fiche('CNT/1001/26')],
        ['dossier CLÔTURÉ désigné : refusé', avecDossier('CNT/1001/26', 'cloture'), fiche('CNT/1001/26', { dossierConsultationId: 'DOSX-1001cloture' })],
        ['dossier d’un AUTRE patient désigné : ignoré, SANS_DOSSIER', avecDossier('CNT/1002/26'), fiche('CNT/1001/26', { dossierConsultationId: 'DOSX-1002consultation' })],
        ['aucune pathologie retenue', avecDossier('CNT/1001/26'), fiche('CNT/1001/26', { pathologies: [] })],
        ['diagnostic vide', avecDossier('CNT/1001/26'), fiche('CNT/1001/26', { diagnostic: '   ' })],
        ['patient introuvable', () => {}, fiche('CNT/9999/26')],
        ['sans prescription, orientation domicile avec contrôle : dossier clôturé, rendez-vous planifié', avecDossier('CNT/1001/26'),
          fiche('CNT/1001/26', { prochainRdv: '2026-08-27T10:00' })],
        ['sans prescription, contrôle sans date : aucun rendez-vous', avecDossier('CNT/1001/26'), fiche('CNT/1001/26', { tarif: null })],
        ['médicaments seuls : dossier clôturé, ordonnance et facture, consultation liée', avecDossier('CNT/1001/26'),
          fiche('CNT/1001/26', { medicaments: [med(0, 2)] })],
        ['analyses et imagerie, orientation hospitalisation : dossier en attente labo, admission notifiée', avecDossier('CNT/1002/26'),
          fiche('CNT/1002/26', { medicaments: [med(0, 1)], analyses: [analyses[0].code], imagerie: [examens[0].code], orientation: 'hospitalisation' })],
        ['orientation mise en observation', avecDossier('CNT/1001/26'), fiche('CNT/1001/26', { orientation: 'observation' })],
        ['orientation référence', avecDossier('CNT/1001/26'), fiche('CNT/1001/26', { orientation: 'reference' })],
        ['type de venue urgence → consultation « Urgence »', () => { poser('dossiersConsultation', [DOSS('CNT/1001/26', 'consultation', { typeVenue: 'urgence' })]); }, fiche('CNT/1001/26')],
        ['prescription REFUSÉE (imagerie sans tarif) : la consultation est défaite, rien n’est écrit', avecDossier('CNT/1001/26'),
          fiche('CNT/1001/26', { medicaments: [med(0, 1)], imagerie: ['IMG-SANS-PRIX'] })],
        ['dossier ancien (constantes à plat, sans copie)', () => { poser('dossiersConsultation', [DOSS('CNT/1001/26', 'consultation', { temperature: 39, tension: '14/9', pouls: 100 })]); }, fiche('CNT/1001/26')],
      ];
      for (const [nom, prep, v] of ficheCas) {
        await jouer('fiche', nom, () => { prep(); return { dossiers: propre(db().dossiersConsultation) }; }, () => Z.enregistrerFiche(propre(v)),
          (r) => (r ? { retour: { suites: r.suites, rdv: !!r.rendezVous, prescription: !!r.prescription } } : {}));
        cas.fiche[cas.fiche.length - 1].params = v;
      }

      /* ---- prescrireSoins / administrer / soinsDuSecteur ---- */
      const soignantPrescripteur = soignants.filter((s) => s.prescrit)[0];
      const soignantNonHabilite = soignants.filter((s) => !s.prescrit)[0];
      const soignantExecutant = soignants.filter((s) => s.execute && (s.secteurs || []).indexOf('salle_soins') !== -1)[0];
      const soignantMedecinSeul = soignants.filter((s) => !s.execute)[0];
      const soinsCas = [
        ['ambulatoire, patient non assuré : deux actes AMI, tarif non assuré', { patientCode: 'CNT/1001/26', prescripteurId: soignantPrescripteur.id, origine: 'consultation', secteurDestinataire: 'salle_soins', modalite: 'ambulatoire', indication: 'Pansement', actes: [{ code: ami[0], nbAdministrations: 3 }, { code: ami[1], nbAdministrations: 1 }] }],
        ['hospitalisation, patient assuré (carte valide) : tarif assuré, premier administrateur = salle de soins', { patientCode: 'CNT/1002/26', prescripteurId: soignantPrescripteur.id, origine: 'hospitalisation', secteurDestinataire: 'hospitalisation', modalite: 'hospitalisation', indication: 'IV', actes: [{ code: ami[0], nbAdministrations: 4 }] }],
        ['carte expirée : tarif non assuré', { patientCode: 'CNT/1003/26', prescripteurId: soignantPrescripteur.id, origine: 'bloc', secteurDestinataire: 'salle_soins', modalite: 'ambulatoire', actes: [{ code: ami[2], nbAdministrations: 1 }] }],
        ['prescripteur non habilité : refusé en le nommant', { patientCode: 'CNT/1001/26', prescripteurId: soignantNonHabilite.id, origine: 'consultation', actes: [{ code: ami[0] }] }],
        ['acte sans prix au catalogue : ligne « à valider », montant exclu', { patientCode: 'CNT/1001/26', prescripteurId: soignantPrescripteur.id, origine: 'maternite', secteurDestinataire: 'maternite', actes: [{ code: ami[0] }, { code: amiSansPrix[0] || 'INCONNU-X' }] }],
        ['code d’acte inconnu : libellé = code, prix nul', { patientCode: 'CNT/1001/26', prescripteurId: soignantPrescripteur.id, actes: ['ZZZ-INCONNU'] }],
        ['patient introuvable', { patientCode: 'CNT/9999/26', prescripteurId: soignantPrescripteur.id, actes: [{ code: ami[0] }] }],
        ['sans prescripteurId : prescripteur de la saisie, urgent', { patientCode: 'CNT/1001/26', prescripteur: 'Dr Libre', urgent: true, actes: [{ code: ami[0] }] }],
      ];
      for (const [nom, v] of soinsCas) {
        v.date = '2026-08-20T09:00:00.000Z';
        await jouer('soins', nom, fixtureCatalogues, () => PR.prescrireSoins(propre(v)));
        cas.soins[cas.soins.length - 1].params = v;
      }

      /* Administrations : une prescription posée, réglée ou non. */
      const presSoins = (modalite, paiement, lignes) => ({
        id: 'PRSX1', statut: 'en_cours', reference: 'PRS-00901', type: 'soins', origine: 'consultation', date: '2026-08-20T09:00:00.000Z',
        patientId: 'PATX1', patientCode: 'CNT/1001/26', patient: 'ALPHA Une', prescripteur: 'X', secteurDestinataire: 'salle_soins', modalite,
        lignes: lignes || [{ acteCode: ami[0], libelle: 'Acte A', quantite: 1, prix: 1000, nbAdministrations: 2 }], montant: 1000, statutPaiement: paiement,
      });
      const adm = (rang, ligneIndex) => ({ id: 'ADMX' + rang, statut: 'actif', prescriptionId: 'PRSX1', ligneIndex: ligneIndex || 0, rang });
      const admCas = [
        ['prescription non réglée : bloquée', 'ambulatoire', 'impayee', [], { ligneIndex: 0, secteur: 'salle_soins', executantId: soignantExecutant.id }],
        ['non réglée mais forcée', 'ambulatoire', 'impayee', [], { ligneIndex: 0, secteur: 'salle_soins', executantId: soignantExecutant.id, forcer: true }],
        ['ambulatoire réglée : 1re administration en salle de soins', 'ambulatoire', 'payee', [], { ligneIndex: 0, secteur: 'salle_soins', executantId: soignantExecutant.id, observation: 'RAS' }],
        ['hospitalisation, 2e administration réclamée par la salle de soins : refusée en nommant le relais', 'hospitalisation', 'payee', [adm(1)], { ligneIndex: 0, secteur: 'salle_soins', executantId: soignantExecutant.id }],
        ['hospitalisation, 2e administration par l’hospitalisation : acceptée, prescription terminée', 'hospitalisation', 'payee', [adm(1)], { ligneIndex: 0, secteur: 'hospitalisation', executantId: soignantExecutant.id }],
        ['exécutant qui n’exécute pas (médecin) : refusé', 'ambulatoire', 'payee', [], { ligneIndex: 0, secteur: 'salle_soins', executantId: soignantMedecinSeul.id }],
        ['ligne introuvable', 'ambulatoire', 'payee', [], { ligneIndex: 7, secteur: 'salle_soins', executantId: soignantExecutant.id }],
        ['prescription introuvable', null, null, [], { ligneIndex: 0 }],
      ];
      for (const [nom, modalite, paiement, deja, opts] of admCas) {
        await jouer('administrer', nom, () => { if (modalite) { poser('prescriptions', [presSoins(modalite, paiement)]); poser('administrations', deja); } return { prescriptions: propre(db().prescriptions), administrations: deja }; },
          () => PR.administrer(modalite ? 'PRSX1' : 'INCONNUE', propre(opts)), (r) => ({ retour: r ? { ok: r.ok, rang: r.rang || null, secteur: r.secteur || null, secteurAttendu: r.secteurAttendu || null, motif: r.motif || null } : null }));
        cas.administrer[cas.administrer.length - 1].params = { modalite, paiement, deja, opts };
      }
      /* soinsDuSecteur : plusieurs prescriptions, des administrations déjà faites. */
      {
        monter();
        const P1 = presSoins('ambulatoire', 'payee', [{ acteCode: 'A', libelle: 'Acte A', quantite: 1, prix: 1, nbAdministrations: 2 }, { acteCode: 'B', libelle: 'Acte B', quantite: 1, prix: 1, nbAdministrations: 1 }]);
        const P2 = Object.assign(presSoins('hospitalisation', 'impayee', [{ acteCode: 'C', libelle: 'Acte C', quantite: 1, prix: 1, nbAdministrations: 3 }]), { id: 'PRSX2', reference: 'PRS-00902' });
        const P3 = Object.assign(presSoins('hospitalisation', 'payee', [{ acteCode: 'D', libelle: 'Acte D', quantite: 1, prix: 1, nbAdministrations: 2 }]), { id: 'PRSX3', reference: 'PRS-00903' });
        const P4 = Object.assign(presSoins('ambulatoire', 'payee', []), { id: 'PRSX4', reference: 'PRS-00904', statut: 'termine' });
        const adms = [{ id: 'A1', statut: 'actif', prescriptionId: 'PRSX1', ligneIndex: 0, rang: 1 }, { id: 'A2', statut: 'actif', prescriptionId: 'PRSX3', ligneIndex: 0, rang: 1 }, { id: 'A3', statut: 'actif', prescriptionId: 'PRSX3', ligneIndex: 0, rang: 2 }];
        poser('prescriptions', [P1, P2, P3, P4]); poser('administrations', adms);
        const lectures = {};
        ['salle_soins', 'hospitalisation', 'maternite'].forEach((s) => {
          lectures[s] = PR.soinsDuSecteur(s).map((d) => ({ prescription: d.prescription.reference, lignes: d.lignes.map((l) => ({ index: l.index, rang: l.rang, total: l.total, secteur: l.secteur, motif: l.motif, du: l.du, bloque: l.bloque })) }));
        });
        cas.soinsDuSecteur.push({ nom: 'trois secteurs, administrations déjà faites', entree: { prescriptions: [P1, P2, P3, P4], administrations: adms }, sortie: lectures });
      }

      /* Les écrans de saisie (nouvelle ordonnance / dossier) : leurs rubriques. */
      return {
        _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-consultation.js — registres lus + moteurs dossier / fiche / prescription / soins. Ne pas éditer.',
        moisCourant, jourCourant, ajustements, comptes, ecrans, referentiels, syntheses, transitions, ancien,
        catalogues: { produits, analyses, actes, examens: examensToutes.map(propre), examenSansTarif, catalogueTarifs: cat, soignants, pathologies, patients: PATS, releves: RELEVES, medecin: medecinNom, ami, amiSansPrix },
        cas,
      };
    }, jeu);
    ecrire('packages/domaine/test/vecteurs/consultation.json', sortie);

    /* --- Référentiels → Dart ------------------------------------------------------------------------------------------------------------- */
    const R = sortie.referentiels;
    const corps = [
      '// ENGENDRÉ par prototype_html/build/vecteurs-consultation.js — référentiels de la consultation lus sur la maquette',
      '// (data-dossier.js, data-clinique.js, data.js). Ne pas éditer à la main : relancer le script.',
      '// ignore_for_file: prefer_single_quotes',
      'library;',
      '',
      '/// Les référentiels de la maquette, tels que `SIGH.data` les porte.',
      'const Map<String, Object?> csDonnees = ' + litteralDart(R, 0) + ';',
      '',
    ].join('\n');
    const dest = path.join(ROOT, '..', 'packages/domaine/lib/src/consultation/cs_donnees.dart');
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.writeFileSync(dest, corps);
    console.log('  écrit : packages/domaine/lib/src/consultation/cs_donnees.dart');
    const bilan = Object.entries(sortie.cas).map(([k, v]) => k + ' ' + (Array.isArray(v) ? v.length : '')).join(' · ');
    console.log('  cas : ' + bilan);
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
