/* JEU DE DÉMONSTRATION du poste Flutter : exporte de la maquette amorcée les collections dont les écrans PORTÉS ont besoin, telles que
   le magasin les tient (champs nuls omis, comme la persistance). Source de vérité = la maquette ; ne pas éditer à la main.
     node build/gen-poste-jeu.js → apps/poste/assets/donnees/jeu/<collection>.json */
'use strict';
const fs = require('fs'), path = require('path');
const { ouvrirMaquette, ROOT } = require('./extraire');
const COLLECTIONS = ['factures', 'patients', 'avoirs', 'taches', 'demandesAnalyses', 'demandesImagerie', 'ordonnances', 'ecritures', 'audit',
  /* émission de facture : catalogue, médicaments, natures, conventions */
  'naturesFacture', 'actes', 'produits', 'souscripteurs', 'garanties', 'couverturesAssurance', 'mouvements', 'facturesMere', 'remboursements',
  /* tranche 2 : stocks (M6) et achats (M7) */
  'dispensations', 'emplacements', 'inventaires', 'lots', 'transferts', 'valorisationsSage', 'besoins', 'commandes', 'facturesFournisseurs', 'fournisseurs', 'livraisons', 'pvReceptions',
  /* tranche 3 : laboratoire (M5) et imagerie (M2) */
  'examensLabo', 'unitesLabo', 'variablesLabo', 'plagesReactif', 'donneurs', 'poches', 'personnel', 'examensImagerie', 'variablesImagerie', 'clichesImagerie', 'resultatsImagerie',
  'catalogueTarifs', 'visitesHospi', 'appels', 'reunions', 'contreReferences', 'documentsPatient', 'fichesReference', 'pieces', 'fileAttente', 'soins', 'administrations', 'admissions', 'checklistsBloc', 'cpa', 'crOperatoires', 'observations', 'rapportsMedicaux', 'releves', 'scoresGlasgow', 'surveillancesTransfusion', 'accouchements', 'cpon', 'crMaternite', 'deces', 'dossiersObstetricaux', 'grossesses', 'naissances', 'partogrammes', 'planificationFamiliale', 'ptme', 'registreSONU', 'soinsCuratifsMaternite', 'suiviMaternite', 'chambres', 'lits', 'rendezvous', 'visites', 'antecedents', 'documents', 'consultations', 'dossiersConsultation', 'prescriptions', 'constantes', 'pathologies', 'soignants', 'notifications'];
/* SIGH_JEU=sobre : jeu SANS le peuplement des parcours, sur lequel les vecteurs des tranches 1-2 ont été tirés (fixture de test). */
const SOBRE = process.env.SIGH_JEU === 'sobre';
const SORTIE = SOBRE ? path.resolve(__dirname, '..', '..', 'apps', 'poste', 'test', 'fixtures', 'jeu_sobre') : path.resolve(__dirname, '..', '..', 'apps', 'poste', 'assets', 'donnees', 'jeu');
(async () => {
  fs.mkdirSync(SORTIE, { recursive: true });
  const m = await ouvrirMaquette();
  try {
    /* Les registres d'achats ne naissent que sur demande dans la maquette (l'ouverture de M7) : on les amorce comme elle, avant l'export. */
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m7-achats.js') });
    /* Les PV de réception sont amorcés PAR LEUR ÉCRAN (`amorcerPV`, local à m7-achats.js) : on monte l'écran comme l'agent, sinon l'export est vide. */
    await m.page.evaluate(() => {
      try { SIGH.semerAchats(true); } catch (e) { console.error(e); }
      try { const r = document.createElement('div'); document.body.appendChild(r); SIGH.screens['m7-pv-reception-consommables'].render(r); r.remove(); } catch (e) { console.error(e); }
    });
    /* La mise en observation est amorcée PAR SON ÉCRAN (`amorcerObservations`, local à m3-hospitalisation.js : 18 séjours à l'ouverture) : on monte
       l'écran comme l'agent, sinon `observations` s'exporte vide. Avant le peuplement des parcours : le jeu sobre l'amorce aussi. */
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m3-hospitalisation.js') });
    await m.page.evaluate(() => { try { const r = document.createElement('div'); document.body.appendChild(r); SIGH.screens['m3-observation'].render(r); r.remove(); } catch (e) { console.error(e); } });
    /* LE JEU DE DÉMONSTRATION COMPLET : le peuplement des parcours (demandes d'analyses et d'imagerie, ordonnances, tâches, transferts…) est déclenché par
       la page au démarrage dans la maquette ; la page d'extraction ne le fait pas, d'où des collections vides à l'export. */
    if (!SOBRE) await m.page.evaluate(() => { try { SIGH.peuplerParcours(); } catch (e) { console.error(e); } });
    /* Le registre des appels est amorcé PAR SON ÉCRAN (m2-registre-appels) : on le monte comme l'agent. */
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m2-consultations.js') }).catch(() => {});
    await m.page.evaluate(() => { try { const r = document.createElement('div'); document.body.appendChild(r); SIGH.screens['m2-registre-appels'].render(r); r.remove(); } catch (e) { console.error(e); } });
    /* La bibliothèque documentaire du patient est amorcée PAR SON ÉCRAN (m1-documents). */
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m1-patients.js') }).catch(() => {});
    await m.page.evaluate(() => { try { const r = document.createElement('div'); document.body.appendChild(r); SIGH.screens['m1-documents'].render(r); r.remove(); } catch (e) { console.error(e); } });
    /* Les visites aux patients hospitalisés sont amorcées PAR LEUR ÉCRAN (m3-visites-patients). */
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m3-hospitalisation.js') }).catch(() => {});
    await m.page.evaluate(() => { try { const r = document.createElement('div'); document.body.appendChild(r); SIGH.screens['m3-visites-patients'].render(r); r.remove(); } catch (e) { console.error(e); } });
    for (const nom of COLLECTIONS) {
      const lignes = await m.page.evaluate((n) => JSON.parse(JSON.stringify(SIGH.store.collection(n).all().concat(SIGH.store.collection(n).archived()), (k, v) => (v === null ? undefined : v))), nom);
      fs.writeFileSync(path.join(SORTIE, nom + '.json'), JSON.stringify(lignes));
      console.log(`  ${nom} : ${lignes.length} fiches, ${(fs.statSync(path.join(SORTIE, nom + '.json')).size / 1024).toFixed(0)} Ko`);
    }
    /* Référentiels STATIQUES de la maquette (ne sont pas des collections) : analyses, chambres, secteurs. */
    const ref = await m.page.evaluate(() => JSON.parse(JSON.stringify({ analyses: SIGH.data.ANALYSES, typesChambre: SIGH.data.TYPES_CHAMBRE, secteursActivite: SIGH.data.SECTEURS_ACTIVITE || [], paramFiscal: SIGH.data.PARAM_FISCAL })));
    fs.writeFileSync(path.join(SORTIE, 'referentiels.json'), JSON.stringify(ref));
    console.log(`  referentiels : ${ref.analyses.length} analyses, ${ref.typesChambre.length} types de chambre, ${ref.secteursActivite.length} secteurs`);
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
