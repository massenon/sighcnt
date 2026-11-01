/* =============================================================================
 * VECTEURS DU MODULE D'IMPORTATION (IMP) : le moteur PILOTÉ sur un magasin contrôlé.
 * -----------------------------------------------------------------------------
 * Le moteur (`SIGH.importer`, assets/js/modules/import.js) est l'exécutable de référence du port Dart
 * (packages/domaine/lib/src/import/). Ce script :
 *   1. pose un MAGASIN CONTRÔLÉ (quelques fiches par collection : le résultat ne dépend plus du jeu de démonstration) et une horloge fixe ;
 *   2. analyse une quarantaine de fichiers (valides, doublons, colonne manquante, type invalide, péremption passée, quantité négative RG-03,
 *      code patient existant RG-01, écriture non équilibrée RG-10…) ;
 *   3. applique les lots valides, relève les fiches écrites, annule les lots, éprouve les refus d'annulation et l'ATOMICITÉ ;
 *   4. écrit les classeurs .xlsx de chaque cas (relus par `excel` côté Flutter : relecture indépendante) et les modèles téléchargeables.
 *   node build/vecteurs-import.js   →   packages/domaine/test/vecteurs/import.json
 *                                       packages/domaine/lib/src/import/donnees_import.dart
 *                                       apps/poste/test/fixtures/import/*.xlsx
 * Les deux classeurs `compresse-*.xlsx` du même dossier ne sont PAS régénérés ici : ce sont des copies de gs-valide et du modèle des patients
 * recompressées avec zlib (Python, niveaux 9 et 1) pour éprouver les lecteurs DEFLATE.
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT, REPO } = require('./extraire');

const MAGASIN = {
  produits: [
    { id: 'PRD0001', code: 'ABA', designation: 'ABAISSE LANGUE', unite: 'Unité', categorie: 'conso_medical', stock: 2, stockGros: 2, stockDetail: 0, statut: 'actif' },
    { id: 'PRD0002', code: 'PARA500', designation: 'PARACETAMOL 500 MG CP B/100', unite: 'Boîte', categorie: 'medicament', stock: 10, stockGros: 10, stockDetail: 0, statut: 'actif' },
  ],
  lots: [], mouvements: [{ id: 'MVT00001', reference: 'M000001', produitId: 'PRD0001', produit: 'ABAISSE LANGUE', type: 'entree', typeLabel: 'Entrée', quantite: 2, statut: 'actif' }],
  fournisseurs: [{ id: 'F001', code: 'SOBAPS', nom: 'SoBAPS SA', statut: 'actif' }],
  patients: [
    { id: 'PAT0001', code: 'CNT/1/25', nom: 'TCHANE', prenom: 'Bertine', dateNaissance: '1989-07-01', telephone: '0372398919', statut: 'actif' },
    { id: 'PAT0002', code: 'CNT/7/26', nom: 'ADJOVI', prenom: 'Paul', telephone: '0197000001', statut: 'actif' },
  ],
  personnel: [
    { id: 'EMP01', matricule: '1', nom: 'BASSONGUI', prenom: 'Chabi Séko', service: 'Direction', statut: 'actif' },
    { id: 'EMP02', matricule: '2', nom: 'KASSA', prenom: 'Augustin', service: 'Comptabilité', statut: 'actif' },
    { id: 'EMP03', matricule: '3', nom: 'TAKI', prenom: 'Alimatou', service: 'Soins infirmiers', statut: 'actif' },
  ],
  actes: [
    { id: 'ACT001', code: 'MG01', libelle: 'Consultation généraliste', secteur: 'Médecine générale', statut: 'actif' },
    { id: 'ACT002', code: 'CH01', libelle: 'Petite chirurgie', secteur: 'Chirurgie', statut: 'actif' },
  ],
  examensLabo: [{ id: 'EXA01', code: 'NFS', designation: 'NFS complète (hémogramme)', section: 'hematologie', statut: 'actif' }],
  assureurs: [
    { id: 'ASS01', code: 'AFR', nom: 'AFRICAINE DES ASSURANCES', convention: 'Signée', statut: 'actif' },
    { id: 'ASS02', code: 'NSIA', nom: 'NSIA ASSURANCE', convention: 'Signée', statut: 'actif' },
  ],
  souscripteurs: [{ id: 'SOU001', nom: 'PIB Bénin', police: 'AFR/2024/0100', assureur: 'AFR', statut: 'actif' }],
  comptes: [
    { id: 'CPT001', num: '101100', libelle: 'Capital souscrit, non appelé', classe: 1, journal: 'OD', statut: 'actif' },
    { id: 'CPT002', num: '571000', libelle: 'Caisse', classe: 5, journal: 'CAI', statut: 'actif' },
    { id: 'CPT003', num: '411000', libelle: 'Clients', classe: 4, journal: 'VTE', statut: 'actif' },
    { id: 'CPT004', num: '601000', libelle: 'Achats de marchandises', classe: 6, journal: 'ACH', statut: 'actif' },
  ],
  ecritures: [{ id: 'ECR1', numero: 'AN-2025-00001', date: '2025-01-01', journal: 'AN', compte: '571000', debit: 1, credit: 0, statut: 'brouillon' }],
  lotsImportation: [],
};

/* Un cas : [id, jeu, lignes d'objets {cle: valeur}, enteteSansCle?]. `null` dans une ligne = cellule vide. */
const GS = (o) => Object.assign({ code: null, designation: null, categorie: null, unite: null, quantite: null, lot: null, peremption: null, prixRevient: null, seuil: null, emplacement: null, fournisseur: null }, o);
const PA = (o) => Object.assign({ code: null, nom: null, prenom: null, sexe: null, dateNaissance: null, age: null, telephone: null, quartier: null, adresse: null, personneAPrevenir: null, groupeSanguin: null, assureur: null, numeroPolice: null, dateCreation: null }, o);
const SO = (o) => Object.assign({ date: '2026-01-01', compte: null, libelle: null, tiers: null, debit: null, credit: null }, o);
const AC = (o) => Object.assign({ code: null, libelle: null, secteur: 'Médecine générale', prixNonAssure: null, prixAssure: null, codeTarif: null }, o);
const PE = (o) => Object.assign({ matricule: null, nom: null, prenom: null, sexe: 'F', fonction: 'infirmier', poste: 'Infirmière', service: 'Soins infirmiers', categorie: null, dateEmbauche: null, telephone: null, cnss: null, situation: null, salaireBase: null }, o);
const FO = (o) => Object.assign({ code: null, nom: null, type: null, ville: null, adresse: null, tel: null, ifu: null, delai: null, banque: null, compte: null }, o);
const AS = (o) => Object.assign({ code: null, nom: null, tel: null, email: null, convention: null }, o);
const SC = (o) => Object.assign({ nom: null, police: null, assureur: null, categorie: null, effectif: null, dateDebut: null, dateFin: null }, o);
const PC = (o) => Object.assign({ num: null, libelle: null, journal: null }, o);
const AN = (o) => Object.assign({ code: null, designation: null, section: null, echantillon: null, delai: null }, o);

const CAS = [
  ['gs-valide', 'grand-stock', [
    GS({ code: 'MED1', designation: 'AMOXICILLINE 500 MG GELULE B/100', categorie: 'Médicaments', unite: 'Boîte', quantite: 100, lot: 'L1', peremption: '2028-06-30', prixRevient: 350, seuil: 20, emplacement: 'Rayon A, Casier 3', fournisseur: 'SOBAPS' }),
    GS({ code: 'MED1', designation: 'AMOXICILLINE 500 MG GELULE B/100', categorie: 'Médicaments', unite: 'Boîte', quantite: 50, lot: 'L2', peremption: '2029-01-31', prixRevient: 350 }),
    GS({ code: 'GANT1', designation: 'GANTS LATEX M B/100', categorie: 'Consommables médicaux', quantite: 40 }),
  ]],
  ['gs-modele-intact', 'grand-stock', [GS({ code: 'PARA500', designation: 'PARACETAMOL 500 MG CP B/100', categorie: 'Médicaments', unite: 'Boîte', quantite: 120, lot: 'L2026-014', peremption: '2028-06-30', prixRevient: 350, seuil: 20, emplacement: 'Rayon A, Casier 3', fournisseur: 'SOBAPS' })], 'exemple'],
  ['gs-doublon-fichier', 'grand-stock', [
    GS({ code: 'MED1', designation: 'AMOX', categorie: 'Médicaments', quantite: 10, lot: 'L1', peremption: '2028-06-30', prixRevient: 100 }),
    GS({ code: 'med1', designation: 'AMOX', categorie: 'Médicaments', quantite: 5, lot: 'L1', peremption: '2028-06-30', prixRevient: 100 }),
  ]],
  ['gs-doublon-magasin', 'grand-stock', [GS({ code: 'PARA500', designation: 'PARACETAMOL', categorie: 'Médicaments', quantite: 10, lot: 'L1', peremption: '2028-06-30', prixRevient: 100 })]],
  ['gs-colonne-manquante', 'grand-stock', [GS({ code: 'MED9', designation: 'AMOX', categorie: 'Médicaments', quantite: 10 })], 'sans:quantite'],
  ['gs-type-invalide', 'grand-stock', [GS({ code: 'MED9', designation: 'AMOX', categorie: 'Médicaments', quantite: 'abc', lot: 'L1', peremption: '2028-06-30' })]],
  ['gs-peremption-passee', 'grand-stock', [GS({ code: 'MED8', designation: 'EXPIRE', categorie: 'Médicaments', quantite: 10, lot: 'L9', peremption: '2020-01-01', prixRevient: 100 })]],
  ['gs-quantite-negative', 'grand-stock', [GS({ code: 'MED7', designation: 'NEGATIF', categorie: 'Médicaments', quantite: -5, lot: 'L1', peremption: '2028-06-30', prixRevient: 100 })]],
  ['gs-lot-obligatoire', 'grand-stock', [GS({ code: 'MED6', designation: 'SANS LOT', categorie: 'Médicaments', quantite: 5, prixRevient: 100 })]],
  ['gs-lot-incomplet', 'grand-stock', [GS({ code: 'FOU1', designation: 'PAPIER', categorie: 'Fournitures administratives', quantite: 5, lot: 'X1' })]],
  ['gs-categorie-inconnue', 'grand-stock', [GS({ code: 'BIJ1', designation: 'BIJOU', categorie: 'Bijoux', quantite: 1 })]],
  ['gs-incoherent', 'grand-stock', [
    GS({ code: 'MED2', designation: 'AMOX A', categorie: 'Médicaments', quantite: 5, lot: 'A', peremption: '2028-01-01', prixRevient: 100 }),
    GS({ code: 'MED2', designation: 'AUTRE NOM', categorie: 'Médicaments', quantite: 5, lot: 'B', peremption: '2028-01-01', prixRevient: 100 }),
  ]],
  ['gs-obligatoire-vide', 'grand-stock', [GS({ code: 'MED5', designation: null, categorie: 'Médicaments', quantite: 5, lot: 'A', peremption: '2028-01-01' })]],
  ['gs-fichier-vide', 'grand-stock', []],
  ['pa-valide', 'patients', [
    PA({ code: 'CNT/12/24', nom: 'AKPO', prenom: 'Marc', sexe: 'M', dateNaissance: '1990-04-12', telephone: '0197000010', quartier: 'Boukoumbé', assureur: 'AFR', numeroPolice: 'AFR/2024/0100', dateCreation: '2024-05-02' }),
    PA({ nom: 'DOSSOU', prenom: 'Aïcha', sexe: 'F', dateNaissance: '2001-09-30', telephone: '0197000011', dateCreation: '2026-03-10' }),
    PA({ nom: 'GBEDO', prenom: 'Lucien', sexe: 'M', age: 45 }),
  ]],
  ['pa-code-existant', 'patients', [PA({ code: 'CNT/1/25', nom: 'AUTRE', prenom: 'Personne', sexe: 'F', age: 30, telephone: '0197000099' })]],
  ['pa-doublon-identite', 'patients', [PA({ nom: 'TCHANE', prenom: 'Bertine', sexe: 'F', dateNaissance: '1989-07-01', telephone: '0197000098' })]],
  ['pa-doublon-telephone', 'patients', [PA({ nom: 'ADJOVI', prenom: 'Paul', sexe: 'M', age: 40, telephone: '0197000001' })]],
  ['pa-sans-age', 'patients', [PA({ nom: 'ZANNOU', prenom: 'Rose', sexe: 'F', telephone: '0197000012' })]],
  ['pa-code-invalide', 'patients', [PA({ code: 'DOSSIER-12', nom: 'ZANNOU', prenom: 'Rose', sexe: 'F', age: 20 })]],
  ['pa-date-future', 'patients', [PA({ nom: 'ZANNOU', prenom: 'Rose', sexe: 'F', dateNaissance: '2031-01-01' })]],
  ['so-valide', 'soldes-ouverture', [
    SO({ compte: '571000', libelle: 'Caisse à l’ouverture', debit: 300000 }),
    SO({ compte: '411000', tiers: 'NSIA', debit: 100000 }),
    SO({ compte: '411000', tiers: 'SUNU', debit: 50000 }),
    SO({ compte: '101100', libelle: 'Capital', credit: 450000 }),
  ]],
  ['so-desequilibre', 'soldes-ouverture', [SO({ compte: '571000', debit: 250000 }), SO({ compte: '101100', credit: 200000 })]],
  ['so-classe-6', 'soldes-ouverture', [SO({ compte: '601000', debit: 1000 }), SO({ compte: '101100', credit: 1000 })]],
  ['so-deux-sens', 'soldes-ouverture', [SO({ compte: '571000', debit: 1000, credit: 1000 })]],
  ['so-compte-inconnu', 'soldes-ouverture', [SO({ compte: '999999', debit: 1000 }), SO({ compte: '101100', credit: 1000 })]],
  ['so-an-existant', 'soldes-ouverture', [SO({ date: '2025-01-01', compte: '571000', debit: 10 }), SO({ date: '2025-01-01', compte: '101100', credit: 10 })]],
  ['so-dates-multiples', 'soldes-ouverture', [SO({ compte: '571000', debit: 10 }), SO({ date: '2026-01-02', compte: '101100', credit: 10 })]],
  ['ac-valide', 'actes', [
    AC({ code: 'X1', libelle: 'Acte A', prixNonAssure: 5000, prixAssure: 3000, codeTarif: 'T1' }),
    AC({ code: 'X2', libelle: 'Acte B', secteur: 'Chirurgie', prixNonAssure: 8000, prixAssure: 'NC' }),
    AC({ code: 'X3', libelle: 'Acte C', prixNonAssure: '-', prixAssure: '-' }),
  ]],
  ['ac-nc-non-assure', 'actes', [AC({ code: 'X4', libelle: 'Acte D', prixNonAssure: 'NC', prixAssure: 3000 })]],
  ['ac-type-invalide', 'actes', [AC({ code: 'X5', libelle: 'Acte E', prixNonAssure: '12,5', prixAssure: 3000 })]],
  ['ac-secteur-inconnu', 'actes', [AC({ code: 'X6', libelle: 'Acte F', secteur: 'Astrologie', prixNonAssure: 1000, prixAssure: 500 })]],
  ['pe-valide', 'personnel', [
    PE({ matricule: '45', nom: 'ADJOVI', prenom: 'Marie', categorie: 'E3-2', dateEmbauche: '2024-03-01', telephone: '0197000020', cnss: '294011541', situation: 'Marié(e)', salaireBase: 150000 }),
    PE({ matricule: '46', nom: 'HOUNKPATIN', prenom: 'Jean', sexe: 'M', fonction: 'stock', poste: 'Magasinier', service: 'Pharmacie' }),
  ]],
  ['pe-doublon-matricule', 'personnel', [PE({ matricule: '2', nom: 'NOUVEAU', prenom: 'Agent' })]],
  ['pe-doublon-identite', 'personnel', [PE({ matricule: '77', nom: 'kassa', prenom: 'augustin' })]],
  ['pe-service-inconnu', 'personnel', [PE({ matricule: '78', nom: 'NOUVEAU', prenom: 'Agent', service: 'Service fantôme' })]],
  ['pe-date-future', 'personnel', [PE({ matricule: '79', nom: 'NOUVEAU', prenom: 'Agent', dateEmbauche: '2031-01-01' })]],
  ['fo-valide', 'fournisseurs', [FO({ code: 'CAME', nom: 'Centrale d’achat', type: 'Grossiste', ville: 'Cotonou', ifu: '3202112446799', delai: 7 }), FO({ code: 'LOCAL', nom: 'Fournisseur local' })]],
  ['fo-doublon', 'fournisseurs', [FO({ code: 'sobaps', nom: 'SoBAPS bis' })]],
  ['fo-ifu-invalide', 'fournisseurs', [FO({ code: 'CAME', nom: 'Centrale d’achat', ifu: '12AB' })]],
  ['as-valide', 'assureurs', [AS({ code: 'SUNU', nom: 'SUNU ASSURANCES', tel: '0195000001 / 0195000002', email: 'contact@sunu.bj', convention: 'Signée' }), AS({ code: 'OLEA', nom: 'OLEA' })]],
  ['as-doublon', 'assureurs', [AS({ code: 'afr', nom: 'Autre' })]],
  ['as-email-invalide', 'assureurs', [AS({ code: 'GAB', nom: 'GAB', email: 'pas-un-email' })]],
  ['sc-valide', 'souscripteurs', [SC({ nom: 'Société X', police: 'NSIA/2026/001', assureur: 'NSIA', categorie: 'entreprise', effectif: 40, dateDebut: '2026-01-01' })]],
  ['sc-compagnie-inconnue', 'souscripteurs', [SC({ nom: 'Société Y', police: 'ZZZ/1', assureur: 'ZZZ' })]],
  ['sc-periode-inversee', 'souscripteurs', [SC({ nom: 'Société Z', police: 'NSIA/2026/002', assureur: 'NSIA', dateDebut: '2026-06-01', dateFin: '2026-01-01' })]],
  ['sc-police-existante', 'souscripteurs', [SC({ nom: 'PIB bis', police: 'afr/2024/0100', assureur: 'AFR' })]],
  ['pc-valide', 'plan-comptable', [PC({ num: '605000', libelle: 'Fournitures consommables', journal: 'ACH' }), PC({ num: '6051', libelle: 'Eau' })]],
  ['pc-doublon', 'plan-comptable', [PC({ num: '571000', libelle: 'Caisse bis' })]],
  ['pc-numero-invalide', 'plan-comptable', [PC({ num: '05', libelle: 'Trop court' })]],
  ['an-valide', 'analyses', [AN({ code: 'HBA1C', designation: 'Hémoglobine glyquée', section: 'Biochimie', echantillon: 'Sang total (EDTA)', delai: '24 h' })]],
  ['an-section-inconnue', 'analyses', [AN({ code: 'GLY', designation: 'Glycémie', section: 'Magie' })]],
];

(async () => {
  console.log('▶ Vecteurs du module d’importation');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/vendor/xlsx-mini.js') });
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/import.js') });
    const sortie = await m.page.evaluate(async ([MAG, CAS]) => {
      const S = SIGH.store, C = SIGH.core, D = SIGH.data, I = SIGH.importer, X = SIGH.xlsx;
      C.aujourdhui = () => new Date(2026, 10, 1, 12, 0, 0);
      S.currentUser = () => 'ADMIN TEST';
      const propre = (x) => JSON.parse(JSON.stringify(x));
      Object.keys(MAG).forEach((n) => { const a = S.collection(n).all(); a.splice(0, a.length); MAG[n].forEach((f) => a.push(propre(f))); });
      const META = ['_creePar', '_creeLe', '_modifiePar', '_modifieLe', 'statutAvantArchivage', '_archivePar', '_archiveLe', '_motifArchivage'];
      const nettoyer = (f, idVersCode) => {
        const c = propre(f); META.forEach((k) => delete c[k]); delete c.id;
        if (c.produitId && idVersCode[c.produitId]) c.produitId = 'code:' + idVersCode[c.produitId];
        return c;
      };
      const out = { jour: '2026-11-01', utilisateur: 'ADMIN TEST', magasin: propre(MAG), cas: [], fixtures: {} };
      const entetes = (j) => I.jeu(j).colonnes.map((c) => c.label);
      const versLigne = (j, o) => I.jeu(j).colonnes.map((c) => (o[c.cle] === undefined || o[c.cle] === null ? '' : o[c.cle]));
      /* 1. Analyses sur le magasin PRISTINE. */
      CAS.forEach(([id, j, lignes, mode]) => {
        let tete = entetes(j);
        let donnees = lignes.map((o) => versLigne(j, o));
        if (mode === 'exemple') donnees = [I.jeu(j).colonnes.map((c) => (c.exemple === undefined ? '' : c.exemple))];
        if (mode && mode.indexOf('sans:') === 0) {
          const cle = mode.slice(5), i = I.jeu(j).colonnes.findIndex((c) => c.cle === cle);
          tete = tete.filter((_, k) => k !== i); donnees = donnees.map((l) => l.filter((_, k) => k !== i));
        }
        const table = [tete].concat(donnees);
        /* Le classeur est écrit puis RELU par le moteur : on éprouve l'écriture ET la lecture. */
        const octets = X.ecrire({ feuilles: [{ nom: 'Données', lignes: table }] });
        const a = I.analyserOctets(j, octets, id + '.xlsx');
        const b = I.analyserLignes(I.jeu(j), table, id + '.xlsx');
        out.fixtures[id] = Array.from(octets);
        out.cas.push({
          id: id, jeu: j, lignes: table,
          attendu: {
            accepte: a.accepte, nbLignes: a.nbLignes, compte: a.compte, coherentCsv: JSON.stringify(a.compte) === JSON.stringify(b.compte) && a.accepte === b.accepte,
            problemes: I.problemes(a).map((p) => ({ n: p.n, colonne: p.colonne, code: p.code, niveau: p.niveau, valeur: String(p.valeur === undefined ? '' : p.valeur) })),
            etats: a.lignes.map((l) => [l.n, l.etat]),
          },
        });
      });
      /* 2. Les modèles téléchargeables. */
      out.modeles = {};
      I.JEUX.forEach((j) => {
        const octets = I.modele(j.id);
        out.fixtures['modele-' + j.id] = Array.from(octets);
        const lu = X.lire(octets);
        out.modeles[j.id] = {
          libelle: j.libelle, ecran: j.ecran, statut: j.statut, module: j.module, roles: j.roles, cibles: j.cibles, source: j.source, fichier: j.fichierModele,
          entetes: j.colonnes.map((c) => c.label), cles: j.colonnes.map((c) => c.cle), obligatoires: j.colonnes.map((c) => !!c.obligatoire),
          types: j.colonnes.map((c) => c.type), exemple: lu.feuilles[0].lignes[1], feuilles: lu.feuilles.map((f) => f.nom),
          instructions: lu.feuilles[1].lignes.length, listes: lu.feuilles[2].lignes[0],
        };
      });
      /* 3. Application, relevé des fiches, annulation. L'ordre fixe les références de lot. */
      const ordre = ['gs-valide', 'pa-valide', 'so-valide', 'ac-valide', 'pe-valide', 'fo-valide', 'as-valide', 'sc-valide', 'pc-valide', 'an-valide'];
      out.applications = [];
      const refus = I.analyserOctets('grand-stock', Uint8Array.from(out.fixtures['gs-quantite-negative']), 'gs-quantite-negative.xlsx');
      const lotRefus = I.consigner(I.jeu('grand-stock'), refus);
      out.lotRefus = propre({ reference: lotRefus.reference, etat: lotRefus.etat, nbLignes: lotRefus.nbLignes, nbAvertissements: lotRefus.nbAvertissements, nbRefus: lotRefus.nbRefus, erreursTotal: lotRefus.erreursTotal, jeu: lotRefus.jeu, fichier: lotRefus.fichier });
      const lots = {};
      ordre.forEach((id) => {
        const cas = out.cas.find((c) => c.id === id);
        const a = I.analyserOctets(cas.jeu, Uint8Array.from(out.fixtures[id]), id + '.xlsx');
        const avant = {};
        Object.keys(MAG).concat(['lotsImportation']).forEach((n) => { avant[n] = S.collection(n).all().length; });
        const r = I.appliquer(cas.jeu, a);
        if (!r.ok) throw new Error('application refusée ' + id + ' : ' + JSON.stringify({ code: r.code, motif: r.motif, pb: r.analyse ? I.problemes(r.analyse).slice(0, 3) : I.problemes(a).slice(0, 3) }));
        const lot = r.lot;
        lots[id] = lot;
        const idVersCode = {};
        S.collection('produits').all().forEach((p) => { idVersCode[p.id] = p.code; });
        const fiches = {};
        (lot.ecrits || []).forEach((e) => { (fiches[e.collection] = fiches[e.collection] || []).push(nettoyer(S.collection(e.collection).get(e.id), idVersCode)); });
        out.applications.push({ cas: id, jeu: cas.jeu, ok: r.ok, reference: lot.reference, ecrits: lot.ecrits.length, fiches: fiches,
          lot: { etat: lot.etat, nbLignes: lot.nbLignes, nbAvertissements: lot.nbAvertissements, jeu: lot.jeu, fichier: lot.fichier, validePar: lot.validePar, date: lot.date } });
      });
      /* 4. Un second import du même fichier est refusé : les fiches existent maintenant. */
      const rejeu = I.analyserOctets('grand-stock', Uint8Array.from(out.fixtures['gs-valide']), 'gs-valide.xlsx');
      out.rejeu = { accepte: rejeu.accepte, codes: I.problemes(rejeu).filter((p) => p.niveau === 'refus').map((p) => p.code) };
      /* 5. Annulations : refus nommé sous un stock vivant, puis annulation réussie. */
      out.annulations = [];
      const prodMed1 = S.collection('produits').all().find((p) => p.code === 'MED1');
      S.collection('mouvements').insert({ reference: 'M000050', date: '2026-11-01', produitId: prodMed1.id, produit: prodMed1.designation, type: 'sortie', typeLabel: 'Sortie', quantite: 3, stockType: 'gros', justificatif: 'Ordonnance test' });
      const refusGs = I.annulerLot(lots['gs-valide'].id, 'test');
      out.annulations.push({ cas: 'gs-valide', ok: refusGs.ok, code: refusGs.code || null });
      /* Sans le mouvement, l'annulation passe : on l'archive. */
      const mv = S.collection('mouvements').all().find((x) => x.reference === 'M000050'); S.collection('mouvements').archive(mv.id, 'test');
      ordre.forEach((id) => {
        const r = I.annulerLot(lots[id].id, 'test');
        const arch = (lots[id].ecrits || []).filter((e) => S.collection(e.collection).get(e.id).statut === 'archive').length;
        out.annulations.push({ cas: id, ok: r.ok, code: r.code || null, archives: r.archives === undefined ? null : r.archives, archivesVerifiees: arch, etatLot: S.collection('lotsImportation').get(lots[id].id).etat });
      });
      const deux = I.annulerLot(lots['gs-valide'].id, 'encore');
      out.annulations.push({ cas: 'gs-valide-deuxieme-fois', ok: deux.ok, code: deux.code || null });
      /* 6. Atomicité : l'écriture comptable est refusée en cours de lot, rien ne subsiste. */
      const avantEcr = S.collection('ecritures').all().length, avantLots = S.collection('lotsImportation').all().length;
      S.garder('ecritures', (op) => (op === 'inserer' && S.collection('ecritures').all().length >= avantEcr + 2 ? 'exercice clos (garde d’essai)' : null));
      const casSo = out.cas.find((c) => c.id === 'so-valide');
      const ate = I.appliquer('soldes-ouverture', I.analyserOctets('soldes-ouverture', Uint8Array.from(out.fixtures['so-valide']), 'so-valide.xlsx'));
      S.garder('ecritures', null);
      out.atomicite = { ok: ate.ok, code: ate.code || null, ecrituresAvant: avantEcr, ecrituresApres: S.collection('ecritures').all().length, lotsAjoutes: S.collection('lotsImportation').all().length - avantLots, lotEtat: ate.lot ? ate.lot.etat : null };
      /* 7. Rapport d'erreurs et CSV. */
      const rap = X.lire(I.rapport(lotRefus, I.jeu('grand-stock')));
      out.rapport = { feuilles: rap.feuilles.map((f) => f.nom), entete: rap.feuilles[0].lignes[0], nbLignes: rap.feuilles[0].lignes.length };
      out.csv = { grandStock: I.modeleCsv('grand-stock') };
      const csvLu = X.lireCsv(out.csv.grandStock);
      out.csv.lignes = csvLu;
      /* 8. Référentiels de contrôle dont le port a besoin. */
      out.referentiels = {
        categories: D.CATEGORIES_PRODUIT.map((c) => [c.id, c.label]),
        fonctions: Object.keys(D.CAPACITES),
        groupesSanguins: D.GROUPES_SANGUINS,
        journaux: D.JOURNAUX.map((j) => [j.code, j.libelle]),
        sectionsLabo: SIGH.labo.SECTIONS.map((s) => [s.id, s.label]),
        services: D.SERVICES,
        secteursActes: Array.from(new Set(D.ACTES.map((a) => a.secteur).filter(Boolean))),
      };
      out.lienCellules = { serie1: X.versDate(1), serie60: X.versDate(61), serie45000: X.versDate(45000), serie46023: X.versDate(46023) };
      return out;
    }, [MAGASIN, CAS]);

    const fixtures = sortie.fixtures; delete sortie.fixtures;
    const dossier = path.join(REPO, 'apps/poste/test/fixtures/import');
    fs.mkdirSync(dossier, { recursive: true });
    Object.keys(fixtures).forEach((k) => fs.writeFileSync(path.join(dossier, k + '.xlsx'), Buffer.from(fixtures[k])));
    console.log('  fixtures .xlsx : ' + Object.keys(fixtures).length);
    ecrire('packages/domaine/test/vecteurs/import.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-import.js : le moteur d’importation piloté sur un magasin contrôlé. Ne pas éditer.' }, sortie));
    const R = sortie.referentiels;
    const q = (s) => "'" + String(s).replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$') + "'";
    const dart = '// ENGENDRÉ par prototype_html/build/vecteurs-import.js : référentiels de contrôle du module d\'importation. Ne pas éditer.\n'
      + '/// Catégories d\'articles (`D.CATEGORIES_PRODUIT`) : [identifiant, libellé].\n'
      + 'const importCategoriesProduit = <List<String>>[\n' + R.categories.map((c) => '  [' + q(c[0]) + ', ' + q(c[1]) + '],').join('\n') + '\n];\n\n'
      + '/// Fonctions du personnel (`D.CAPACITES`).\n'
      + 'const importFonctions = <String>[' + R.fonctions.map(q).join(', ') + '];\n\n'
      + '/// Groupes sanguins (`D.GROUPES_SANGUINS`).\n'
      + 'const importGroupesSanguins = <String>[' + R.groupesSanguins.map(q).join(', ') + '];\n\n'
      + '/// Journaux comptables (`D.JOURNAUX`) : [code, libellé].\n'
      + 'const importJournaux = <List<String>>[\n' + R.journaux.map((c) => '  [' + q(c[0]) + ', ' + q(c[1]) + '],').join('\n') + '\n];\n\n'
      + '/// Services de la clinique (`D.SERVICES`).\n'
      + 'const importServices = <String>[' + R.services.map(q).join(', ') + '];\n\n'
      + '/// Secteurs du catalogue des actes (`D.ACTES`).\n'
      + 'const importSecteursActes = <String>[' + R.secteursActes.map(q).join(', ') + '];\n\n'
      + '/// Sections du laboratoire (`SIGH.labo.SECTIONS`) : [identifiant, libellé].\n'
      + 'const importSectionsLabo = <List<String>>[\n' + R.sectionsLabo.map((c) => '  [' + q(c[0]) + ', ' + q(c[1]) + '],').join('\n') + '\n];\n';
    const dir = path.join(REPO, 'packages/domaine/lib/src/import');
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, 'donnees_import.dart'), dart);
    console.log('  écrit : packages/domaine/lib/src/import/donnees_import.dart');
    const ko = sortie.cas.filter((c) => !c.attendu.coherentCsv);
    console.log('  cas : ' + sortie.cas.length + ' · applications : ' + sortie.applications.length + ' · incohérences xlsx/lignes : ' + ko.length);
    console.log('  atomicité : ' + JSON.stringify(sortie.atomicite));
    console.log('  annulations : ' + sortie.annulations.map((a) => a.cas + ':' + a.ok + (a.code ? '(' + a.code + ')' : '')).join(' '));
    if (m.erreurs.length) console.log('  erreurs JS de la page : ' + m.erreurs.join(' | '));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
