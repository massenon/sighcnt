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
  'catalogueTarifs', 'visitesHospi',
  /* lot T6 : le référentiel de prix unique (PRD-TARIFS) ; `actes`, `analyses` et `catalogueTarifs` n'en sont que les PROJECTIONS de lecture (prix en vigueur) */
  'tarifs', 'versionsTarif', 'analyses',
  /* configuration fiscale validée et datée (06/11/2026) : identité par versions, obligations et paramètres ORTB, historique */
  'identiteLegale', 'obligationsFiscales', 'historiqueObligations', 'validationsReferentiels', 'rbac', 'appels', 'reunions', 'contreReferences', 'documentsPatient', 'fichesReference', 'pieces', 'fileAttente', 'soins', 'administrations', 'admissions', 'checklistsBloc', 'cpa', 'crOperatoires', 'observations', 'rapportsMedicaux', 'releves', 'scoresGlasgow', 'surveillancesTransfusion', 'accouchements', 'cpon', 'crMaternite', 'deces', 'dossiersObstetricaux', 'grossesses', 'naissances', 'partogrammes', 'planificationFamiliale', 'ptme', 'registreSONU', 'soinsCuratifsMaternite', 'suiviMaternite', 'chambres', 'lits', 'rendezvous', 'visites', 'antecedents', 'documents', 'consultations', 'dossiersConsultation', 'prescriptions', 'constantes', 'pathologies', 'soignants', 'notifications',
  /* activités fermées : les fiches de la maquette (la banque de sang), puis les fermetures PROPRES AU POSTE ci-dessous */
  'modulesActifs'];
/* FERMETURES PROPRES AU POSTE (Direction, 11/11/2026) : deux écrans restent fermés (calendrier fiscal et barème de l'AIB) ; le lot SMS-R (16/11/2026) a porté les deux écrans SMS (MODP02 et MODP04 retirés, réouverture des postes déjà installés par `reouvrirFermeturesLevees`). À l'origine, quatre écrans que la maquette porte et que le poste ne porte pas encore. Ils sont fermés par la collection
   `modulesActifs` (activité fermée par écran, pour tous les rôles, administrateur compris), jamais par un nom de rôle. La maquette NE LES FERME PAS : ces fiches
   n'existent que dans le jeu du poste (`proprePoste`), ce qui les écarte de la RÉFÉRENCE de la matrice des droits (`rbac.json` ne les connaît pas). Porter un écran,
   c'est retirer son entrée ici et régénérer ; un poste déjà installé garde la fiche fermée tant qu'on ne la rouvre pas depuis la gestion des activités, qui ne le
   propose que si l'écran a un widget. Le jeu sobre (fixture des vecteurs) n'en porte aucune : il reproduit la maquette. */
const JEUX_IMPORT_NON_PORTES = [
];
const FERMETURES_PROPRES_AU_POSTE = [
  { id: 'MODP01', module: 'M12', ecran: 'm12-calendrier-fiscal', libelle: 'Calendrier fiscal mensuel' },
  { id: 'MODP03', module: 'CFG', ecran: 'cfg-bareme-aib', libelle: 'Barème de l’AIB' },
  /* LOT IMP-C (12/11/2026) : les JEUX D'IMPORT que le poste ne porte pas encore. Leur page `imp-<jeu>` existe au manifeste et à la maquette ; sans jeu au registre du poste elle n'aurait
     aucun widget. Elle est fermée comme les quatre ci-dessus (activité fermée par écran, jamais par un nom de rôle) ; PORTER UN JEU, c'est retirer sa ligne ici ET dans
     `ecrans_sans_chantier_test.dart` puis régénérer. La fermeture ferme aussi le DROIT du jeu (`droitImport` lit les activités fermées) : aucun bouton « Importer les données ». */
  ...JEUX_IMPORT_NON_PORTES.map(([id, ecran, libelle]) => ({ id: 'MODP' + id, module: 'IMP', ecran: ecran, libelle: libelle, impNonPorte: true })),
].map((f) => ({
  /* `code` suit la règle d'une activité déclarée à l'écran (`cfbCodeActivite` : module, tiret, libellé en majuscules hors A-Z0-9, huit caractères) */
  id: f.id, code: f.module + '-' + f.libelle.toUpperCase().replace(/[^A-Z0-9]+/g, '').slice(0, 8), libelle: f.libelle, module: f.module, ecrans: [f.ecran], actif: false,
  motif: f.impNonPorte ? 'Jeu d’import non porté au poste (lot IMP-C), à porter. La page existe à la maquette.' : 'Non porté au poste, à porter (décision de la Direction du 11/11/2026). L’écran existe à la maquette.',
  fermeLe: f.impNonPorte ? '2026-11-12' : '2026-11-11', fermePar: f.impNonPorte ? 'Lot IMP-C (à confirmer par la Direction)' : 'Direction', proprePoste: true,
}));
/* SIGH_JEU=sobre : jeu SANS le peuplement des parcours, sur lequel les vecteurs des tranches 1-2 ont été tirés (fixture de test). */
const SOBRE = process.env.SIGH_JEU === 'sobre';
/* SIGH_COLLECTIONS=a,b : n'exporte que ces collections (les autres fichiers du jeu restent tels quels). */
const FILTRE = (process.env.SIGH_COLLECTIONS || '').split(',').map((x) => x.trim()).filter(Boolean);
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
    for (const nom of COLLECTIONS.filter((n) => !FILTRE.length || FILTRE.includes(n))) {
      const lignes = await m.page.evaluate((n) => JSON.parse(JSON.stringify(SIGH.store.collection(n).all().concat(SIGH.store.collection(n).archived()), (k, v) => (v === null ? undefined : v))), nom);
      if (nom === 'modulesActifs' && !SOBRE) lignes.push(...FERMETURES_PROPRES_AU_POSTE);
      /* LOT TARIF-FIX : les prestations de prix des PRODUITS (famille PRODUIT, version 1 « reprise ») ne sont pas livrées : la maquette les pose à sa projection, le poste les pose
         lui-même au démarrage de la mère (`TarifsPoste.assurerProduits`, lot TFIN-2). Les exporter changerait l'origine de leur version 1 au poste. */
      if (nom === 'tarifs' || nom === 'versionsTarif') {
        const produits = await m.page.evaluate(() => SIGH.store.collection('tarifs').all().filter((t) => t.famille === 'PRODUIT').map((t) => t.code));
        const exclus = new Set(produits);
        for (let i = lignes.length - 1; i >= 0; i--) if (exclus.has(lignes[i].code) && (nom === 'versionsTarif' || lignes[i].famille === 'PRODUIT')) lignes.splice(i, 1);
      }
      fs.writeFileSync(path.join(SORTIE, nom + '.json'), JSON.stringify(lignes));
      console.log(`  ${nom} : ${lignes.length} fiches, ${(fs.statSync(path.join(SORTIE, nom + '.json')).size / 1024).toFixed(0)} Ko`);
    }
    /* Référentiels STATIQUES de la maquette (ne sont pas des collections) : analyses, chambres, secteurs. */
    const ref = await m.page.evaluate(() => JSON.parse(JSON.stringify({ analyses: SIGH.data.ANALYSES, typesChambre: SIGH.data.TYPES_CHAMBRE, secteursActivite: SIGH.data.SECTEURS_ACTIVITE || [], paramFiscal: SIGH.data.PARAM_FISCAL })));
    fs.writeFileSync(path.join(SORTIE, 'referentiels.json'), JSON.stringify(ref));
    console.log(`  referentiels : ${ref.analyses.length} analyses, ${ref.typesChambre.length} types de chambre, ${ref.secteursActivite.length} secteurs`);
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
