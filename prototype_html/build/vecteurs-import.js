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
    /* Lot 8 (jeux du stock) : de quoi éprouver le stock détail initial, le bon de transfert et le comptage d'inventaire. */
    { id: 'PRD0003', code: 'AMOXI', designation: 'AMOXICILLINE 500 MG B/100', unite: 'Boîte', categorie: 'medicament', stock: 30, stockGros: 30, stockDetail: 0, cump: 100, statut: 'actif' },
    { id: 'PRD0004', code: 'COTON', designation: 'COTON HYDROPHILE 500 G', unite: 'Unité', categorie: 'conso_medical', stock: 12, stockGros: 12, stockDetail: 0, cump: 50, statut: 'actif' },
    { id: 'PRD0005', code: 'SIROP', designation: 'SIROP TOUX 125 ML', unite: 'Flacon', categorie: 'medicament', stock: 20, stockGros: 15, stockDetail: 5, cump: 80, statut: 'actif' },
    { id: 'PRD0006', code: 'INCOH', designation: 'ARTICLE INCOHERENT', unite: 'Unité', categorie: 'conso_medical', stock: 10, stockGros: 4, stockDetail: 4, cump: 10, statut: 'actif' },
    { id: 'PRD0007', code: 'DOLIP', designation: 'DOLIPRANE 1 G B/8', unite: 'Boîte', categorie: 'medicament', stock: 40, stockGros: 40, stockDetail: 0, cump: 200, statut: 'actif' },
  ],
  lots: [
    { id: 'LOT0001', produitId: 'PRD0003', produit: 'AMOXICILLINE 500 MG B/100', numeroLot: 'L-A', datePeremption: '2026-12-15', quantiteRestante: 20, magasin: 'gros', statut: 'alerte' },
    { id: 'LOT0002', produitId: 'PRD0003', produit: 'AMOXICILLINE 500 MG B/100', numeroLot: 'L-B', datePeremption: '2027-05-31', quantiteRestante: 10, magasin: 'gros', statut: 'actif' },
    { id: 'LOT0003', produitId: 'PRD0003', produit: 'AMOXICILLINE 500 MG B/100', numeroLot: 'L-OLD', datePeremption: '2025-01-31', quantiteRestante: 5, magasin: 'gros', statut: 'perime' },
  ], mouvements: [{ id: 'MVT00001', reference: 'M000001', produitId: 'PRD0001', produit: 'ABAISSE LANGUE', type: 'entree', typeLabel: 'Entrée', quantite: 2, statut: 'actif' }],
  fournisseurs: [{ id: 'F001', code: 'SOBAPS', nom: 'SoBAPS SA', statut: 'actif' }],
  patients: [
    { id: 'PAT0001', code: 'CNT/1/25', nom: 'TCHANE', prenom: 'Bertine', dateNaissance: '1989-07-01', telephone: '0372398919', statut: 'actif' },
    { id: 'PAT0002', code: 'CNT/7/26', nom: 'ADJOVI', prenom: 'Paul', telephone: '0197000001', statut: 'actif' },
    { id: 'PAT0003', code: 'CNT/3/26', nom: 'KOUASSI', prenom: 'Ama', assureur: 'AFR', assureurNom: 'AFRICAINE DES ASSURANCES', numeroPolice: 'AFR/2024/0100', categorieAssurance: 'entreprise', tauxPriseEnCharge: 80, carteExpiration: '2029-12-31', souscripteurId: 'SOU001', statut: 'actif' },
    { id: 'PAT0004', code: 'CNT/4/26', nom: 'DOSSOU', prenom: 'Rose', assureur: 'NSIA', assureurNom: 'NSIA ASSURANCE', numeroPolice: 'NSIA/2024/0200', categorieAssurance: 'entreprise', tauxPriseEnCharge: 90, carteExpiration: '2026-12-31', souscripteurId: 'SOU002', statut: 'actif' },
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
  souscripteurs: [{ id: 'SOU001', nom: 'PIB Bénin', police: 'AFR/2024/0100', assureur: 'AFR', categorie: 'entreprise', statut: 'actif' }, { id: 'SOU002', nom: 'Banque du Nord', police: 'NSIA/2024/0200', assureur: 'NSIA', categorie: 'entreprise', statut: 'actif' }],
  comptes: [
    { id: 'CPT001', num: '101100', libelle: 'Capital souscrit, non appelé', classe: 1, journal: 'OD', statut: 'actif' },
    { id: 'CPT002', num: '571000', libelle: 'Caisse', classe: 5, journal: 'CAI', statut: 'actif' },
    { id: 'CPT003', num: '411000', libelle: 'Clients', classe: 4, journal: 'VTE', statut: 'actif' },
    { id: 'CPT004', num: '601000', libelle: 'Achats de marchandises', classe: 6, journal: 'ACH', statut: 'actif' },
  ],
  ecritures: [{ id: 'ECR1', numero: 'AN-2025-00001', date: '2025-01-01', journal: 'AN', compte: '571000', debit: 1, credit: 0, statut: 'brouillon' }],
  /* Lot IMP-C : les référentiels des jeux portés au poste (natures, centres, unités, prestataires, emplacements) : une fiche tenue chacun, de quoi éprouver les doublons. */
  naturesFacture: [{ id: 'NAT01', code: 'CONS', libelle: 'Consultation', secteur: 'Médecine générale', statut: 'actif' }],
  centresCouts: [{ id: 'CC01', code: 'laboratoire', libelle: 'Laboratoire', type: 'exploitation', statut: 'actif' }],
  unitesLabo: [{ id: 'UNI1', symbole: 'g/dl', libelle: 'gramme par décilitre', domaine: 'Biochimie', statut: 'actif' }],
  prestataires: [{ id: 'PE1', reference: 'PE-0001', nom: 'Dr ADJO Marius', specialite: 'Chirurgie', tarifActe: 20000, actesRealises: 3, ifu: '3202112446712', statut: 'actif' }],
  emplacements: [{ id: 'EMP1', code: 'A2', libelle: 'Rayon A, casier 2', zone: 'Rayonnage sec', statut: 'actif' }],
  transferts: [], inventaires: [],
  /* Lot 8b, groupe PRIX : un référentiel de prix de quelques prestations (une par famille d'espace de codes), versionné par date, de quoi éprouver le changement de prix, la création, l'inchangé,
     l'inversion des colonnes, la proposition en attente et le code d'un produit ; le catalogue d'imagerie tient un examen. */
  tarifs: [
    { id: 'MG01', code: 'MG01', libelle: 'Consultation généraliste', famille: 'ACTE', secteur: 'Médecine générale', codeActe: 'MG01', assurable: true, statut: 'actif' },
    { id: 'MG02', code: 'MG02', libelle: 'Consultation de suivi', famille: 'ACTE', secteur: 'Médecine générale', codeActe: 'MG02', assurable: true, statut: 'actif' },
    { id: 'CH01', code: 'CH01', libelle: 'Petite chirurgie', famille: 'ACTE', secteur: 'Chirurgie', codeActe: 'CH01', assurable: true, statut: 'actif' },
    { id: 'NFS', code: 'NFS', libelle: 'NFS complète (hémogramme)', famille: 'LABO', secteur: 'Laboratoire', codeAnalyse: 'NFS', statut: 'actif' },
    { id: 'IMG-ECHO-PEL', code: 'IMG-ECHO-PEL', libelle: 'Échographie pelvienne', famille: 'IMAGERIE', secteur: 'Imagerie médicale', codeGrille: 'IMG-ECHO-PEL', statut: 'actif' },
    { id: 'PARA500', code: 'PARA500', libelle: 'PARACETAMOL 500 MG CP B/100', famille: 'PRODUIT', statut: 'actif' },
  ],
  versionsTarif: [
    { id: 'MG01@origine@1', code: 'MG01', version: 1, prixNonAssure: 5000, prixAssure: 3000, etatAssure: 'montant', origine: 'migration', statut: 'valide' },
    { id: 'MG02@origine@1', code: 'MG02', version: 1, prixNonAssure: 3000, prixAssure: 2000, etatAssure: 'montant', origine: 'migration', statut: 'valide' },
    { id: 'MG02@2027-03-01@2', code: 'MG02', version: 2, dateEffet: '2027-03-01', prixNonAssure: 3500, prixAssure: 2500, etatAssure: 'montant', motif: 'Ajustement', origine: 'ecran', statut: 'propose', proposePar: 'AUTRE AGENT', proposeLe: '2026-10-30', proposeRole: 'da' },
    { id: 'CH01@origine@1', code: 'CH01', version: 1, prixNonAssure: 20000, etatAssure: 'unique', origine: 'migration', statut: 'valide' },
    { id: 'NFS@origine@1', code: 'NFS', version: 1, prixNonAssure: 4000, etatAssure: 'unique', origine: 'migration', statut: 'valide' },
    { id: 'IMG-ECHO-PEL@origine@1', code: 'IMG-ECHO-PEL', version: 1, prixNonAssure: 15000, prixAssure: 10000, etatAssure: 'montant', origine: 'migration', statut: 'valide' },
    { id: 'PARA500@origine@1', code: 'PARA500', version: 1, prixNonAssure: 1200, etatAssure: 'unique', origine: 'migration', statut: 'valide' },
  ],
  /* Lot 8b, groupe GARANTIES ET COUVERTURES : deux souscripteurs, des garanties versionnées (une série sans date, une série à deux versions), deux assurés (l'un avec un historique de
     couverture, l'autre sans : la première modification reprend alors la couverture du dossier) et une facture émise sous la grille du premier souscripteur. */
  garanties: [
    { id: 'GAR1', souscripteurId: 'SOU001', assureur: 'AFR', code: 'CS-GEN', libelle: 'Consultation généraliste', categorie: 'consultation', taux: 80, zone: 'Bénin', version: 1, statut: 'actif' },
    { id: 'GAR2', souscripteurId: 'SOU001', assureur: 'AFR', code: 'LAB', libelle: 'Analyses', categorie: 'analyse', taux: 70, plafond: 50000, unitePlafond: 'an', zone: 'Bénin', dateEffet: '2026-01-01', version: 1, statut: 'actif' },
    { id: 'GAR3', souscripteurId: 'SOU001', assureur: 'AFR', code: 'LAB', libelle: 'Analyses', categorie: 'analyse', taux: 60, plafond: 50000, unitePlafond: 'an', zone: 'Bénin', dateEffet: '2027-06-01', version: 2, statut: 'actif' },
  ],
  couverturesAssurance: [
    { id: 'COU1', patientId: 'PAT0003', patientCode: 'CNT/3/26', patient: 'KOUASSI Ama', assureur: 'AFR', assureurNom: 'AFRICAINE DES ASSURANCES', numeroPolice: 'AFR/2024/0100', categorieAssurance: 'entreprise', tauxPriseEnCharge: 80, carteExpiration: '2029-12-31', souscripteurId: 'SOU001', debut: '2026-01-01', motif: 'Première couverture', statut: 'actif' },
  ],
  factures: [{ id: 'FAC1', numero: 'F-2026-0001', patientId: 'PAT0003', assureur: 'AFR', date: '2026-10-20', statut: 'emise' }],
  examensImagerie: [{ id: 'EXI01', code: 'IMG-ECHO-PEL', label: 'Échographie pelvienne', modalite: 'echographie', icone: 'scan-line', statut: 'actif' }],
  lotsImportation: [],
};

/* Un cas : [id, jeu, lignes d'objets {cle: valeur}, enteteSansCle?]. `null` dans une ligne = cellule vide. */
const GS = (o) => Object.assign({ code: null, designation: null, categorie: null, unite: null, quantite: null, lot: null, peremption: null, prixRevient: null, seuil: null, emplacement: null, fournisseur: null }, o);
const PA = (o) => Object.assign({ code: null, nom: null, prenom: null, sexe: null, dateNaissance: null, age: null, telephone: null, quartier: null, adresse: null, personneAPrevenir: null, assureur: null, numeroPolice: null, dateCreation: null }, o);
const SO = (o) => Object.assign({ date: '2026-01-01', compte: null, libelle: null, tiers: null, debit: null, credit: null }, o);
const AC = (o) => Object.assign({ code: null, libelle: null, secteur: 'Médecine générale', prixNonAssure: null, prixAssure: null, codeTarif: null }, o);
const PE = (o) => Object.assign({ matricule: null, nom: null, prenom: null, sexe: 'F', fonction: 'infirmier', poste: 'Infirmière', service: 'Soins infirmiers', categorie: null, dateEmbauche: null, telephone: null, cnss: null, situation: null, salaireBase: null }, o);
const FO = (o) => Object.assign({ code: null, nom: null, type: null, ville: null, adresse: null, tel: null, ifu: null, delai: null, banque: null, compte: null }, o);
const AS = (o) => Object.assign({ code: null, nom: null, tel: null, email: null, convention: null }, o);
const SC = (o) => Object.assign({ nom: null, police: null, assureur: null, categorie: null, effectif: null, dateDebut: null, dateFin: null }, o);
const PC = (o) => Object.assign({ num: null, libelle: null, journal: null }, o);
const NA = (o) => Object.assign({ code: null, libelle: null, secteur: null, source: null }, o);
const CE = (o) => Object.assign({ code: null, libelle: null, type: 'Centre d’exploitation', responsable: null, source: null }, o);
const UN = (o) => Object.assign({ symbole: null, libelle: null, domaine: null }, o);
const PS = (o) => Object.assign({ nom: null, specialite: null, telephone: null, tarifActe: null, ifu: null, factureNormalisee: null }, o);
const EM = (o) => Object.assign({ code: null, libelle: null, zone: null, temperature: null, capacite: null, observation: null }, o);
const SD = (o) => Object.assign({ code: null, lot: null, peremption: null, quantite: null }, o);
const TL = (o) => Object.assign({ code: null, lot: null, quantite: null, destination: 'Pharmacie d’urgence', date: null, motif: null }, o);
const IC = (o) => Object.assign({ magasin: 'Stock gros', code: null, compte: null, type: null, date: null }, o);
const TA = (o) => Object.assign({ code: null, designation: null, famille: null, secteur: null, prixNonAssure: null, prixAssure: null, couverture: null, dateEffet: '2027-01-01', valider: null, motif: 'Nouvelle grille tarifaire', source: null }, o);
const GA = (o) => Object.assign({ police: 'AFR/2024/0100', categorie: 'Consultations', garantie: 'Consultation généraliste', taux: null, plafond: null, unite: null, dateEffet: '2027-01-01', motif: 'Avenant du 01/12/2026', source: null }, o);
const CV = (o) => Object.assign({ patient: null, assureur: null, police: null, dateEffet: '2030-01-01', motif: 'Changement d’employeur', categorie: null, taux: null, carteExpiration: '2030-12-31' }, o);
const CI = (o) => Object.assign({ code: null, libelle: null, modalite: null, voie: null, tarifCode: null }, o);
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
  /* Les cas du jeu `actes` (prix) quittent ce tirage : le jeu s'appelle `tarifs` (lot IMP-A), il écrit par PR.proposerTarif sur le référentiel de prix, que le magasin contrôlé
     d'ici ne pose pas ; ses preuves sont les scénarios Vague 124 et 125 de test-fonctionnel.js. Le port Dart de ce jeu est du lot IMP-C. */
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
  ['an-valide', 'analyses-modele', [AN({ code: 'HBA1C', designation: 'Hémoglobine glyquée', section: 'Biochimie', echantillon: 'Sang total (EDTA)', delai: '24 h' })]],
  ['an-section-inconnue', 'analyses-modele', [AN({ code: 'GLY', designation: 'Glycémie', section: 'Magie' })]],
  /* Lot IMP-C : cinq référentiels de plus au poste. */
  ['na-valide', 'natures-facture', [NA({ code: 'orth', libelle: 'Orthopédie', secteur: 'Chirurgie', source: 'Décision de la Direction' }), NA({ code: 'KINE', libelle: 'Kinésithérapie', secteur: 'Chirurgie' })]],
  ['na-doublon-code', 'natures-facture', [NA({ code: 'cons', libelle: 'Autre libellé', secteur: 'Chirurgie' })]],
  ['na-doublon-libelle', 'natures-facture', [NA({ code: 'NEWC', libelle: 'consultation', secteur: 'Chirurgie' })]],
  ['na-code-invalide', 'natures-facture', [NA({ code: 'A B', libelle: 'Avec espace', secteur: 'Chirurgie' })]],
  ['na-secteur-inconnu', 'natures-facture', [NA({ code: 'XYZ', libelle: 'Secteur fantôme', secteur: 'Magie' })]],
  ['ce-valide', 'centres-couts', [CE({ code: 'orthopedie', libelle: 'Orthopédie', responsable: 'Dr BASSONGUI' }), CE({ code: 'support-logistique', libelle: 'Logistique', type: 'Centre de support' })]],
  ['ce-doublon-code', 'centres-couts', [CE({ code: 'LABORATOIRE', libelle: 'Autre', type: 'Centre de support' })]],
  ['ce-doublon-libelle', 'centres-couts', [CE({ code: 'labo2', libelle: 'laboratoire' })]],
  ['ce-code-invalide', 'centres-couts', [CE({ code: 'un code', libelle: 'Avec espace' })]],
  ['un-valide', 'unites-labo', [UN({ symbole: 'mmol/l', libelle: 'millimole par litre', domaine: 'Biochimie' }), UN({ symbole: 'G/dl', libelle: 'giga par décilitre', domaine: 'Hématologie' })]],
  ['un-doublon', 'unites-labo', [UN({ symbole: 'g/dl', libelle: 'doublon exact', domaine: 'Biochimie' })]],
  ['un-casse-distincte', 'unites-labo', [UN({ symbole: 'G/dl', libelle: 'distincte de g/dl : la casse compte', domaine: 'Hématologie' })]],
  ['un-domaine-inconnu', 'unites-labo', [UN({ symbole: 'xx', libelle: 'inconnu', domaine: 'Magie' })]],
  ['ps-valide', 'prestataires', [PS({ nom: 'Dr SANNI Idrissou', specialite: 'Échographie', telephone: '0197000000', tarifActe: 25000, ifu: '3202112446799', factureNormalisee: 'Oui' }), PS({ nom: 'Mme KOUDJO Rose', specialite: 'Accouchement', tarifActe: 15000 })]],
  ['ps-doublon-nom', 'prestataires', [PS({ nom: 'dr adjo marius', specialite: 'Chirurgie', tarifActe: 1000 })]],
  ['ps-doublon-ifu', 'prestataires', [PS({ nom: 'Dr AUTRE', specialite: 'Chirurgie', tarifActe: 1000, ifu: '3202112446712' })]],
  ['ps-ifu-invalide', 'prestataires', [PS({ nom: 'Dr IFU', specialite: 'Chirurgie', tarifActe: 1000, ifu: '12AB' })]],
  ['ps-tarif-tiret', 'prestataires', [PS({ nom: 'Dr TIRET', specialite: 'Chirurgie', tarifActe: '-' })]],
  ['ps-colonne-retiree', 'prestataires', [PS({ nom: 'Dr RETIRE', specialite: 'Chirurgie', tarifActe: 1000 })], 'plus:Actes réalisés'],
  ['em-valide', 'emplacements', [EM({ code: 'B7', libelle: 'Rayon B, casier 7', zone: 'Chaîne du froid', temperature: '2 à 8 °C', capacite: 40 }), EM({ code: 'C1', libelle: 'Réserve C1' })]],
  ['em-doublon-casse', 'emplacements', [EM({ code: 'a2', libelle: 'Doublon par la casse' }), EM({ code: 'A-2', libelle: 'Casier distinct : le tiret compte' })]],
  ['em-zone-inconnue', 'emplacements', [EM({ code: 'Z9', libelle: 'Zone inconnue', zone: 'Cave' })]],
  ['em-capacite-negative', 'emplacements', [EM({ code: 'N1', libelle: 'Capacité négative', capacite: -3 })]],
  /* Lot 8, groupe STOCK : le stock détail initial, le bon de transfert et le comptage d'inventaire. */
  ['sd-valide', 'stock-detail-initial', [SD({ code: 'DOLIP', lot: 'D1', peremption: '2028-03-31', quantite: 25 }), SD({ code: 'DOLIP', lot: 'D2', peremption: '2029-01-31', quantite: 15 })]],
  ['sd-deja-mouvemente', 'stock-detail-initial', [SD({ code: 'ABA', quantite: 1 })]],
  ['sd-deja-en-stock', 'stock-detail-initial', [SD({ code: 'SIROP', lot: 'X1', peremption: '2028-01-01', quantite: 3 })]],
  ['sd-incoherent', 'stock-detail-initial', [SD({ code: 'INCOH', quantite: 2 })]],
  ['sd-article-inconnu', 'stock-detail-initial', [SD({ code: 'NOPE', quantite: 2 })]],
  ['sd-lot-obligatoire', 'stock-detail-initial', [SD({ code: 'DOLIP', quantite: 2 })]],
  ['sd-lot-incomplet', 'stock-detail-initial', [SD({ code: 'COTON', lot: 'X', quantite: 2 })]],
  ['sd-peremption-passee', 'stock-detail-initial', [SD({ code: 'DOLIP', lot: 'P1', peremption: '2020-01-01', quantite: 5 })]],
  ['sd-quantite-negative', 'stock-detail-initial', [SD({ code: 'COTON', quantite: -3 })]],
  ['sd-quantite-nulle', 'stock-detail-initial', [SD({ code: 'COTON', quantite: 0 }), SD({ code: 'DOLIP', lot: 'Q1', peremption: '2028-03-31', quantite: 2 })]],
  ['sd-doublon-fichier', 'stock-detail-initial', [SD({ code: 'DOLIP', lot: 'D1', peremption: '2028-03-31', quantite: 5 }), SD({ code: 'dolip', lot: 'd1', peremption: '2028-03-31', quantite: 5 })]],
  ['tl-valide', 'transfert-lignes', [TL({ code: 'AMOXI', quantite: 10, date: '2026-10-30', motif: 'Réapprovisionnement' }), TL({ code: 'COTON', quantite: 4 }), TL({ code: 'AMOXI', lot: 'L-A', quantite: 5 })]],
  ['tl-stock-insuffisant', 'transfert-lignes', [TL({ code: 'COTON', quantite: 20 })]],
  ['tl-cumul-bon', 'transfert-lignes', [TL({ code: 'AMOXI', quantite: 20 }), TL({ code: 'AMOXI', lot: 'L-A', quantite: 15 })]],
  ['tl-lot-inconnu', 'transfert-lignes', [TL({ code: 'AMOXI', lot: 'ZZ', quantite: 1 })]],
  ['tl-lot-perime', 'transfert-lignes', [TL({ code: 'AMOXI', lot: 'L-OLD', quantite: 1 })]],
  ['tl-lot-non-fefo', 'transfert-lignes', [TL({ code: 'AMOXI', lot: 'L-B', quantite: 1 })]],
  ['tl-destinations-multiples', 'transfert-lignes', [TL({ code: 'COTON', quantite: 1 }), TL({ code: 'AMOXI', quantite: 1, destination: 'Laboratoire' })]],
  ['tl-destination-absente', 'transfert-lignes', [TL({ code: 'COTON', quantite: 1, destination: null })]],
  ['tl-dates-multiples', 'transfert-lignes', [TL({ code: 'COTON', quantite: 1, date: '2026-10-01' }), TL({ code: 'AMOXI', quantite: 1, date: '2026-10-02' })]],
  ['tl-motifs-multiples', 'transfert-lignes', [TL({ code: 'COTON', quantite: 1, motif: 'A' }), TL({ code: 'AMOXI', quantite: 1, motif: 'B' })]],
  ['tl-date-future', 'transfert-lignes', [TL({ code: 'COTON', quantite: 1, date: '2031-01-01' })]],
  ['tl-quantite-nulle', 'transfert-lignes', [TL({ code: 'COTON', quantite: 0 })]],
  ['tl-article-inconnu', 'transfert-lignes', [TL({ code: 'NOPE', quantite: 1 })]],
  ['ic-valide', 'inventaire-comptage', [IC({ code: 'AMOXI', compte: 28, type: 'Mensuel', date: '2026-10-31' }), IC({ code: 'COTON', compte: 12, type: 'Mensuel', date: '2026-10-31' }), IC({ magasin: 'Stock détail', code: 'SIROP', compte: 6 })]],
  ['ic-article-inconnu', 'inventaire-comptage', [IC({ code: 'NOPE', compte: 1 })]],
  ['ic-date-future', 'inventaire-comptage', [IC({ code: 'COTON', compte: 1, date: '2031-01-01' })]],
  ['ic-feuille-unique', 'inventaire-comptage', [IC({ code: 'COTON', compte: 1, type: 'Mensuel' }), IC({ code: 'AMOXI', compte: 1, type: 'Annuel' })]],
  ['ic-compte-negatif', 'inventaire-comptage', [IC({ code: 'COTON', compte: -1 })]],
  ['ic-magasin-invalide', 'inventaire-comptage', [IC({ magasin: 'Cave', code: 'COTON', compte: 1 })]],
  /* Lot 8b, groupe PRIX : les prix de prestations (changement versionné, création, Oui et Non, inchangé) et le catalogue de l'imagerie. La session de tirage est l'administrateur (il décide). */
  ['ta-valide', 'tarifs', [
    TA({ code: 'MG01', prixNonAssure: 5500, prixAssure: 3300, valider: 'Oui' }),
    TA({ code: 'NFS', prixNonAssure: 4500, prixAssure: 'UNIQUE', valider: 'Oui' }),
    TA({ code: 'CS-NEW', designation: 'Consultation nouvelle', famille: 'Consultations', secteur: 'Médecine générale', prixNonAssure: 8000, prixAssure: 'NC', couverture: 'Non couvert', valider: 'Oui' }),
    TA({ code: 'CH01', prixNonAssure: 20000, prixAssure: 'UNIQUE', valider: 'Oui' }),
    TA({ code: 'IMG-ECHO-PEL', prixNonAssure: 16000, prixAssure: 11000, valider: 'Non', motif: 'Grille non arrêtée' }),
  ]],
  ['ta-proposition', 'tarifs', [TA({ code: 'MG01', prixNonAssure: 5200, prixAssure: 3100 }), TA({ code: 'NFS', prixNonAssure: 4200, prixAssure: '-', valider: 'Oui' })]],
  ['ta-code-produit', 'tarifs', [TA({ code: 'PARA500', prixNonAssure: 1300, prixAssure: 'UNIQUE' })]],
  ['ta-nc-non-assure', 'tarifs', [TA({ code: 'MG01', prixNonAssure: 'NC', prixAssure: 3000 })]],
  ['ta-prix-absent', 'tarifs', [TA({ code: 'MG01', prixNonAssure: '-', prixAssure: 3000 })]],
  ['ta-prix-zero', 'tarifs', [TA({ code: 'MG01', prixNonAssure: 0, prixAssure: 3000 })]],
  ['ta-prix-decimal', 'tarifs', [TA({ code: 'MG01', prixNonAssure: 5000.5, prixAssure: 3000 })]],
  ['ta-date-passee', 'tarifs', [TA({ code: 'MG01', prixNonAssure: 5600, prixAssure: 3400, dateEffet: '2026-10-01' })]],
  ['ta-date-absente', 'tarifs', [TA({ code: 'MG01', prixNonAssure: 5600, prixAssure: 3400, dateEffet: null })]],
  ['ta-motif-requis', 'tarifs', [TA({ code: 'MG01', prixNonAssure: 5600, prixAssure: 3400, motif: null })]],
  ['ta-non-sans-motif', 'tarifs', [TA({ code: 'MG01', prixNonAssure: 5600, prixAssure: 3400, valider: 'Non', motif: null })]],
  ['ta-identite-incomplete', 'tarifs', [TA({ code: 'XX99', prixNonAssure: 1000, prixAssure: 'UNIQUE' }), TA({ code: 'XX98', designation: 'Sans famille', prixNonAssure: 1000, prixAssure: 'UNIQUE' })]],
  ['ta-colonnes-inversees', 'tarifs', [TA({ code: 'MG01', prixNonAssure: 3000, prixAssure: 5000 })]],
  ['ta-identite-differente', 'tarifs', [TA({ code: 'MG01', designation: 'Autre libellé', prixNonAssure: 5300, prixAssure: 3200 }), TA({ code: 'CH01', famille: 'Consultations', prixNonAssure: 21000, prixAssure: 'UNIQUE' })]],
  ['ta-en-attente', 'tarifs', [TA({ code: 'MG02', prixNonAssure: 3600, prixAssure: 2600 })]],
  ['ta-inchange', 'tarifs', [TA({ code: 'MG01', prixNonAssure: 5000, prixAssure: 3000 })]],
  ['ta-code-existant-alias', 'tarifs', [TA({ code: 'MG01', prixNonAssure: 5000, prixAssure: 3000 }), TA({ code: 'mg01', prixNonAssure: 5100, prixAssure: 3000 })]],
  ['ta-famille-inconnue', 'tarifs', [TA({ code: 'ZZ01', designation: 'Soin', famille: 'Bijoux', prixNonAssure: 1000, prixAssure: 'UNIQUE' })]],
  ['ta-unique-interdit-non-assure', 'tarifs', [TA({ code: 'MG01', prixNonAssure: 'UNIQUE', prixAssure: 3000 })]],
  ['ci-valide', 'catalogue-imagerie', [CI({ code: 'IMG-RAD-THO', libelle: 'Radiographie du thorax', modalite: 'Radiographie', voie: 'face' }), CI({ code: 'IMG-ECH-ABD', libelle: 'Échographie abdominale', modalite: 'Échographie', tarifCode: 'IMG-ECHO-PEL' })]],
  ['ci-doublon-magasin', 'catalogue-imagerie', [CI({ code: 'IMG-ECHO-PEL', libelle: 'Échographie pelvienne', modalite: 'Échographie' })]],
  ['ci-modalite-inconnue', 'catalogue-imagerie', [CI({ code: 'IMG-XX', libelle: 'Examen', modalite: 'Télépathie' })]],
  ['ci-code-invalide', 'catalogue-imagerie', [CI({ code: 'X', libelle: 'Examen', modalite: 'Scanner' })]],
  ['ci-obligatoire-vide', 'catalogue-imagerie', [CI({ code: 'IMG-SC1', libelle: null, modalite: 'Scanner' })]],
  ['ci-doublon-fichier', 'catalogue-imagerie', [CI({ code: 'IMG-SC2', libelle: 'Scanner crâne', modalite: 'Scanner' }), CI({ code: 'img-sc2', libelle: 'Scanner crâne bis', modalite: 'Scanner' })]],
  /* Lot 8b, groupe GARANTIES ET COUVERTURES. */
  ['ga-valide', 'garanties', [GA({ taux: 70 }), GA({ police: 'NSIA/2024/0200', categorie: 'Chirurgie', garantie: 'Chirurgie courante', taux: 90, plafond: 500000, unite: 'par acte' })]],
  ['ga-suivante', 'garanties', [GA({ taux: 65, dateEffet: '2027-06-01' })]],
  ['ga-inchangee', 'garanties', [GA({ taux: 80 })]],
  ['ga-police-inconnue', 'garanties', [GA({ police: 'XXX/0', taux: 70 })]],
  ['ga-categorie-hors-liste', 'garanties', [GA({ categorie: 'Bijoux', taux: 70 })]],
  ['ga-taux-hors-bornes', 'garanties', [GA({ taux: 101 })]],
  ['ga-unite-requise', 'garanties', [GA({ taux: 70, plafond: 1000 })]],
  ['ga-unite-sans-plafond', 'garanties', [GA({ taux: 70, unite: 'par acte' })]],
  ['ga-date-absente', 'garanties', [GA({ taux: 70, dateEffet: null })]],
  ['ga-version-meme-date', 'garanties', [GA({ categorie: 'Analyses de laboratoire', garantie: 'Analyses', taux: 75, plafond: 50000, unite: 'par an', dateEffet: '2026-01-01' })]],
  ['ga-version-anterieure', 'garanties', [GA({ categorie: 'Analyses de laboratoire', garantie: 'Analyses', taux: 65, plafond: 50000, unite: 'par an', dateEffet: '2027-03-01' })]],
  ['ga-facture-emise', 'garanties', [GA({ taux: 75, dateEffet: '2026-10-01' })]],
  ['ga-deux-versions', 'garanties', [GA({ taux: 70 }), GA({ taux: 60, dateEffet: '2027-09-01' })]],
  ['ga-doublon-fichier', 'garanties', [GA({ taux: 70 }), GA({ police: 'afr/2024/0100', taux: 71 })]],
  ['cv-valide', 'couvertures-assurance', [
    CV({ patient: 'CNT/3/26', assureur: 'NSIA', police: 'NSIA/2024/0200', dateEffet: '2030-01-01', taux: 70 }),
    CV({ patient: 'CNT/4/26', assureur: 'AFR', police: 'AFR/2024/0100', dateEffet: '2030-02-01', motif: 'Changement de compagnie par l’assuré', taux: 80, carteExpiration: '2030-12-31' }),
  ]],
  ['cv-suivante', 'couvertures-assurance', [CV({ patient: 'CNT/3/26', assureur: 'AFR', police: 'AFR/2024/0100', dateEffet: '2030-06-01', taux: 80 })]],
  ['cv-patient-inconnu', 'couvertures-assurance', [CV({ patient: 'CNT/99/26', assureur: 'AFR', police: 'AFR/2024/0100' })]],
  ['cv-police-inconnue', 'couvertures-assurance', [CV({ patient: 'CNT/3/26', assureur: 'AFR', police: 'XXX/0' })]],
  ['cv-police-autre-compagnie', 'couvertures-assurance', [CV({ patient: 'CNT/3/26', assureur: 'NSIA', police: 'AFR/2024/0100' })]],
  ['cv-date-anterieure', 'couvertures-assurance', [CV({ patient: 'CNT/3/26', assureur: 'AFR', police: 'AFR/2024/0100', dateEffet: '2026-01-01' })]],
  ['cv-sans-carte', 'couvertures-assurance', [CV({ patient: 'CNT/3/26', assureur: 'AFR', police: 'AFR/2024/0100', carteExpiration: null })]],
  ['cv-facture-emise', 'couvertures-assurance', [CV({ patient: 'CNT/3/26', assureur: 'AFR', police: 'AFR/2024/0100', dateEffet: '2026-10-01' })]],
  ['cv-motif-hors-liste', 'couvertures-assurance', [CV({ patient: 'CNT/3/26', assureur: 'AFR', police: 'AFR/2024/0100', motif: 'Parce que' })]],
  ['cv-motif-fin-de-couverture', 'couvertures-assurance', [CV({ patient: 'CNT/3/26', assureur: 'AFR', police: 'AFR/2024/0100', motif: 'Fin de couverture — patient redevenu non assuré' })]],
  ['cv-assureur-hors-liste', 'couvertures-assurance', [CV({ patient: 'CNT/3/26', assureur: 'ZZZ', police: 'AFR/2024/0100' })]],
  ['cv-doublon-fichier', 'couvertures-assurance', [CV({ patient: 'CNT/3/26', assureur: 'AFR', police: 'AFR/2024/0100' }), CV({ patient: 'cnt/3/26', assureur: 'NSIA', police: 'NSIA/2024/0200' })]],
  ['ic-doublon-fichier', 'inventaire-comptage', [IC({ code: 'COTON', compte: 1 }), IC({ code: 'coton', compte: 2 })]],
];

(async () => {
  console.log('▶ Vecteurs du module d’importation');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/vendor/xlsx-mini.js') });
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/import.js') });
    const GS_LOT = GS({ code: 'MED77', designation: 'IBUPROFENE 400 MG CP B/30', categorie: 'Médicaments', unite: 'Boîte', quantite: 10, lot: 'L77', peremption: '2028-06-30', prixRevient: 100 });
    const sortie = await m.page.evaluate(async ([MAG, CAS, GS_LOT]) => {
      const S = SIGH.store, C = SIGH.core, D = SIGH.data, I = SIGH.importer, X = SIGH.xlsx, PR = SIGH.parcours;
      C.aujourdhui = () => new Date(2026, 10, 1, 12, 0, 0);
      S.currentUser = () => 'ADMIN TEST';
      const propre = (x) => JSON.parse(JSON.stringify(x));
      Object.keys(MAG).forEach((n) => { const a = S.collection(n).all(); a.splice(0, a.length); MAG[n].forEach((f) => a.push(propre(f))); });
      if (D.TARIFS && D.TARIFS.invalider) D.TARIFS.invalider();
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
        if (mode && mode.indexOf('plus:') === 0) {
          tete = tete.concat([mode.slice(5)]); donnees = donnees.map((l) => l.concat([5]));
        }
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
            /* Ce qui entre à l'HISTORIQUE et au rapport : MASQUÉ pour un jeu restreint (aucune valeur de cellule, motif fixe par code), intégral sinon (lot IMP-A). */
            consignes: I.problemes(a, I.jeu(j)).map((p) => ({ n: p.n, colonne: p.colonne, code: p.code, niveau: p.niveau, valeur: String(p.valeur === undefined ? '' : p.valeur), motif: p.motif })),
            aEcrire: a.aEcrire,
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
      const ordre = ['gs-valide', 'pa-valide', 'so-valide', 'pe-valide', 'fo-valide', 'as-valide', 'sc-valide', 'pc-valide', 'an-valide', 'na-valide', 'ce-valide', 'un-valide', 'ps-valide', 'em-valide', 'sd-valide', 'tl-valide', 'ic-valide', 'ci-valide'];
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
      /* 5 bis. LOT 8, groupe STOCK : les garde-fous que seul un stock VIVANT éprouve (un détail déjà dispensé, un transfert déjà dispensé, un comptage déjà régularisé,
         un magasin qui a bougé entre l'analyse et la confirmation, la régularisation STRICTE d'une feuille importée). */
      out.stock = {};
      {
        const lu = (code) => S.collection('produits').all().find((p) => p.code === code);
        const poser = (id) => {
          const cas = out.cas.find((c) => c.id === id);
          const r = I.appliquer(cas.jeu, I.analyserOctets(cas.jeu, Uint8Array.from(out.fixtures[id]), id + '.xlsx'));
          if (!r.ok) throw new Error('lot du stock non posé ' + id + ' : ' + JSON.stringify({ code: r.code, motif: r.motif }));
          return r.lot;
        };
        const refusDe = (r) => ({ ok: r.ok, code: r.code || null, motif: r.motif || null, geste: r.geste || null });
        const stocks = (codes) => { const o = {}; codes.forEach((c) => { const p = lu(c); o[c] = { stock: p.stock, stockGros: p.stockGros, stockDetail: p.stockDetail }; }); return o; };
        /* Stock détail initial : dispensé, puis mouvement postérieur, puis annulation qui passe. */
        {
          const lot = poser('sd-valide');
          out.stock.detailPose = stocks(['DOLIP']);
          const avant = lu('DOLIP').stockDetail;
          S.collection('produits').update(lu('DOLIP').id, { stockDetail: avant - 10 });
          out.stock.detailDejaDispense = refusDe(I.annulerLot(lot.id, 'essai'));
          S.collection('produits').update(lu('DOLIP').id, { stockDetail: avant });
          const mvx = S.collection('mouvements').insert({ reference: 'M000060', date: '2026-11-01', produitId: lu('DOLIP').id, produit: 'DOLIPRANE 1 G B/8', type: 'sortie', typeLabel: 'Sortie', quantite: 1, stockType: 'detail', justificatif: 'Dispensation test' });
          out.stock.detailMouvementPosterieur = refusDe(I.annulerLot(lot.id, 'essai'));
          S.collection('mouvements').archive(mvx.record.id, 'test');
          const ok = I.annulerLot(lot.id, 'essai');
          out.stock.detailAnnule = { ok: ok.ok, archives: ok.archives === undefined ? null : ok.archives, stocks: stocks(['DOLIP']) };
        }
        /* Bon de transfert : dispensé, puis annulation qui restitue gros ET détail ; magasin qui bouge entre l'analyse et la confirmation. */
        {
          const lot = poser('tl-valide');
          out.stock.transfertPose = stocks(['AMOXI', 'COTON']);
          const bon = S.collection('transferts').all().find((b) => b.lotImport === lot.reference);
          out.stock.transfertBon = nettoyer(bon, {});
          const am = lu('AMOXI').stockDetail;
          S.collection('produits').update(lu('AMOXI').id, { stockDetail: 3 });
          out.stock.transfertDejaDispense = refusDe(I.annulerLot(lot.id, 'essai'));
          S.collection('produits').update(lu('AMOXI').id, { stockDetail: am });
          const ok = I.annulerLot(lot.id, 'essai');
          out.stock.transfertAnnule = { ok: ok.ok, archives: ok.archives === undefined ? null : ok.archives, stocks: stocks(['AMOXI', 'COTON']) };
          const analyse = I.analyserOctets('transfert-lignes', Uint8Array.from(out.fixtures['tl-valide']), 'tl-valide.xlsx');
          const g = lu('COTON').stockGros;
          S.collection('produits').update(lu('COTON').id, { stockGros: 1 });
          const r = I.appliquer('transfert-lignes', analyse);
          out.stock.magasinChange = { ok: r.ok, code: r.code || null, stocks: stocks(['AMOXI', 'COTON']) };
          S.collection('produits').update(lu('COTON').id, { stockGros: g });
        }
        /* Comptage : régularisation STRICTE de la feuille importée (un mouvement par écart), refusée si le stock a bougé ; annulation refusée une fois régularisée. */
        {
          const lot = poser('ic-valide');
          const feuilles = S.collection('inventaires').all().filter((f) => f.lotImport === lot.reference);
          out.stock.feuilles = feuilles.map((f) => nettoyer(f, {}));
          const gros = feuilles.find((f) => f.magasin === 'gros');
          const g0 = lu('AMOXI').stockGros;
          S.collection('produits').update(lu('AMOXI').id, { stockGros: g0 + 1 });
          const perimee = PR.regulariserInventaire(gros, { strict: true, operateur: 'ADMIN TEST' });
          out.stock.regularisationPerimee = { ok: perimee.ok, code: perimee.code || null, motif: perimee.motif || null, geste: perimee.geste || null, stocks: stocks(['AMOXI']) };
          S.collection('produits').update(lu('AMOXI').id, { stockGros: g0 });
          const reg = PR.regulariserInventaire(gros, { strict: true, operateur: 'ADMIN TEST' });
          out.stock.regularisation = { ok: reg.ok, nb: reg.nb, mouvements: (reg.mouvements || []).map((m) => nettoyer(m, {})), stocks: stocks(['AMOXI', 'COTON']) };
          S.collection('inventaires').update(gros.id, { statutInv: 'valide' });
          out.stock.inventaireRegularise = refusDe(I.annulerLot(lot.id, 'essai'));
          reg.annuler();
          S.collection('inventaires').update(gros.id, { statutInv: 'importe' });
          const ok = I.annulerLot(lot.id, 'essai');
          out.stock.comptageAnnule = { ok: ok.ok, archives: ok.archives === undefined ? null : ok.archives, stocks: stocks(['AMOXI', 'COTON']) };
        }
      }
      /* 6. Atomicité : l'écriture comptable est refusée en cours de lot, rien ne subsiste. */
      const avantEcr = S.collection('ecritures').all().length, avantLots = S.collection('lotsImportation').all().length;
      S.garder('ecritures', (op) => (op === 'inserer' && S.collection('ecritures').all().length >= avantEcr + 2 ? 'exercice clos (garde d’essai)' : null));
      const casSo = out.cas.find((c) => c.id === 'so-valide');
      const ate = I.appliquer('soldes-ouverture', I.analyserOctets('soldes-ouverture', Uint8Array.from(out.fixtures['so-valide']), 'so-valide.xlsx'));
      S.garder('ecritures', null);
      out.atomicite = { ok: ate.ok, code: ate.code || null, ecrituresAvant: avantEcr, ecrituresApres: S.collection('ecritures').all().length, lotsAjoutes: S.collection('lotsImportation').all().length - avantLots, lotEtat: ate.lot ? ate.lot.etat : null };
      /* 6 bis. LE DROIT D'IMPORT (lot IMP-A), mesuré en changeant le profil de la session : le moteur REFUSE sans le droit (masquer un bouton ne protège rien). */
      out.droits = {};
      const sess0 = S.session();
      const enRole = (role, utilisateur, f) => {
        S.setSession(Object.assign({}, sess0, { role: role }));
        const u0 = S.currentUser; S.currentUser = () => utilisateur;
        try { return f(); } finally { S.setSession(sess0); S.currentUser = u0; }
      };
      const octetsDe = (id) => Uint8Array.from(out.fixtures[id]);
      const codes = (a) => a.globaux.concat(a.lignes.reduce((t, l) => t.concat(l.problemes), [])).map((p) => p.code);
      const nbLots = () => S.collection('lotsImportation').all().length;
      /* 6 ter. LOT 8b, groupe PRIX : le changement de prix versionné par date. Rôle qui DÉCIDE (admin) : Oui vaut version validée d'emblée, et un lot validé ne s'annule plus ; rôle qui ne décide
         pas (stock, qui importe des prix sans éditer l'écran) : le Oui vaut proposition, et ses propositions se retirent avec leur lot. Un prix identique à celui en vigueur est « inchangé ». */
      out.prix = {};
      {
        /* Ici l'auteur d'une version est le nom de la SESSION (`auteurDeLaSession`) : on le pose avec le rôle, comme le poste porte un seul nom d'agent. */
        const enRole = (role, utilisateur, f) => {
          S.setSession(Object.assign({}, sess0, { role: role, nomComplet: utilisateur, nom: utilisateur }));
          const u0 = S.currentUser; S.currentUser = () => utilisateur;
          try { return f(); } finally { S.setSession(sess0); S.currentUser = u0; }
        };
        const detailDe = (x) => (x && x.decision !== undefined ? ['Ancien : ' + x.ancien, 'nouveau : ' + x.nouveau].concat(x.variation ? ['variation : ' + x.variation] : []).concat(['décision : ' + x.decision]).join(' ; ') : '');
        const resumeAnalyse = (a) => ({ accepte: a.accepte, compte: a.compte, problemes: I.problemes(a).map((p) => ({ n: p.n, colonne: p.colonne, code: p.code, niveau: p.niveau })), details: a.lignes.map((l) => [l.n, l.etat, detailDe(l.extra)]) });
        const net = (f) => { const c = nettoyer(f, {}); c.id = f.id; return c; };
        const fichesDe = (lot) => lot.ecrits.map((e) => net(S.collection(e.collection).get(e.id)));
        out.prix.adminValide = enRole('admin', 'ADMIN TEST', () => resumeAnalyse(I.analyserOctets('tarifs', octetsDe('ta-valide'), 'ta-valide.xlsx')));
        out.prix.stockValide = enRole('stock', 'STOCK TEST', () => resumeAnalyse(I.analyserOctets('tarifs', octetsDe('ta-valide'), 'ta-valide.xlsx')));
        out.prix.stockProposition = enRole('stock', 'STOCK TEST', () => resumeAnalyse(I.analyserOctets('tarifs', octetsDe('ta-proposition'), 'ta-proposition.xlsx')));
        const avantLots = nbLots();
        /* A. L'administrateur applique : versions validées d'emblée, identité créée. */
        const rA = enRole('admin', 'ADMIN TEST', () => I.appliquer('tarifs', I.analyserOctets('tarifs', octetsDe('ta-valide'), 'ta-valide.xlsx')));
        if (!rA.ok) throw new Error('lot de prix non posé : ' + JSON.stringify({ code: rA.code, motif: rA.motif }));
        out.prix.appliqueAdmin = { reference: rA.lot.reference, etat: rA.lot.etat, nbLignes: rA.lot.nbLignes, nbInchanges: rA.lot.nbInchanges, nbNon: rA.lot.nbNon, ecrits: rA.lot.ecrits.map((e) => e.collection), fiches: fichesDe(rA.lot) };
        const refusA = enRole('admin', 'ADMIN TEST', () => I.annulerLot(rA.lot.id, 'essai'));
        out.prix.annulationValidee = { ok: refusA.ok, code: refusA.code || null, motif: refusA.motif || null, geste: refusA.geste || null };
        /* Le même fichier rejoué : le prix est celui en vigueur, rien à écrire. */
        out.prix.rejeu = enRole('admin', 'ADMIN TEST', () => resumeAnalyse(I.analyserOctets('tarifs', octetsDe('ta-valide'), 'ta-valide.xlsx')));
        /* B. Le gestionnaire de stock propose : le Oui vaut proposition, aucune version validée. */
        const rB = enRole('stock', 'STOCK TEST', () => I.appliquer('tarifs', I.analyserOctets('tarifs', octetsDe('ta-proposition'), 'ta-proposition.xlsx')));
        if (!rB.ok) throw new Error('lot de propositions non posé : ' + JSON.stringify({ code: rB.code, motif: rB.motif }));
        out.prix.appliqueStock = { reference: rB.lot.reference, etat: rB.lot.etat, nbAvertissements: rB.lot.nbAvertissements, ecrits: rB.lot.ecrits.map((e) => e.collection), fiches: fichesDe(rB.lot) };
        /* L'auteur retire ses propositions avec son lot : les versions restent lisibles (retirées), rien n'est supprimé. */
        const ids = rB.lot.ecrits.map((e) => e.id);
        const rBa = enRole('stock', 'STOCK TEST', () => I.annulerLot(rB.lot.id, 'essai'));
        out.prix.annulationPropositions = { ok: rBa.ok, code: rBa.code || null, archives: rBa.archives === undefined ? null : rBa.archives, etatLot: S.collection('lotsImportation').get(rB.lot.id).etat,
          versions: ids.map((id) => { const v = S.collection('versionsTarif').get(id); return { id: id, statut: v.statut, motifDecision: v.motifDecision, decidePar: v.decidePar, roleDecision: v.roleDecision }; }) };
        const rBb = enRole('stock', 'STOCK TEST', () => I.annulerLot(rB.lot.id, 'encore'));
        out.prix.annulationDeuxFois = { ok: rBb.ok, code: rBb.code || null };
        /* C. Un autre agent ne retire pas les propositions d'un lot qui n'est pas le sien (sans supervision) : le moteur le dit. */
        out.prix.lotsAjoutes = nbLots() - avantLots;
        /* D. Un rôle sans le droit d'importer les prix : refus de l'application, rien n'est écrit. */
        const avV = S.collection('versionsTarif').all().length;
        const rD = enRole('caissier', 'CAISSIER TEST', () => I.appliquer('tarifs', I.analyserOctets('tarifs', octetsDe('ta-valide'), 'ta-valide.xlsx')));
        out.prix.sansDroit = { ok: rD.ok, code: rD.code || null, versionsAjoutees: S.collection('versionsTarif').all().length - avV };
        /* Les références de lot dépendent de ce qui précède : elles se disent {A} et {B} (le test rejoue sur son propre magasin). */
        out.prix = JSON.parse(JSON.stringify(out.prix).split(rA.lot.reference).join('{A}').split(rB.lot.reference).join('{B}'));
      }
      /* 6 quater. LOT 8b, groupe GARANTIES ET COUVERTURES : une version datée ne réécrit jamais une pièce émise. Une garantie ne s'annule plus sous une facture émise ou sous une version plus
         récente de sa série ; une couverture de même (la précédente reprend sa fin, le dossier retrouve son état). */
      out.assurances = {};
      {
        const detailDe = (x) => (x && x.decision !== undefined ? ['Ancien : ' + x.ancien, 'nouveau : ' + x.nouveau].concat(x.variation ? ['variation : ' + x.variation] : []).concat(['décision : ' + x.decision]).join(' ; ') : '');
        const resume = (a) => ({ accepte: a.accepte, compte: a.compte, problemes: I.problemes(a).map((p) => ({ n: p.n, colonne: p.colonne, code: p.code, niveau: p.niveau })), details: a.lignes.map((l) => [l.n, l.etat, detailDe(l.extra)]) });
        const net = (f) => { const c = nettoyer(f, {}); c.id = f.id; if (/^COU[a-z0-9]{8,}$/.test(String(f.id))) c.id = 'COU:' + f.patientId + '@' + (f.debut || 'reprise'); if (/^GAR[a-z0-9]{8,}$/.test(String(f.id))) c.id = 'GAR:' + f.souscripteurId + '@' + f.libelle + '@' + (f.dateEffet || 'origine'); return c; };
        const fiches = (lot) => lot.ecrits.map((e) => ({ collection: e.collection, avant: e.avant || null, fiche: net(S.collection(e.collection).get(e.id)) }));
        const refusDe = (r) => ({ ok: r.ok, code: r.code || null, motif: r.motif || null, geste: r.geste || null });
        const analyser = (id) => enRole('admin', 'ADMIN TEST', () => I.analyserOctets(I.jeu(id.startsWith('ga-') ? 'garanties' : 'couvertures-assurance').id, octetsDe(id), id + '.xlsx'));
        const poser = (id) => { const r = enRole('admin', 'ADMIN TEST', () => I.appliquer(id.startsWith('ga-') ? 'garanties' : 'couvertures-assurance', analyser(id))); if (!r.ok) throw new Error('lot non posé ' + id + ' : ' + JSON.stringify({ code: r.code, motif: r.motif })); return r.lot; };
        const annuler = (lot) => enRole('admin', 'ADMIN TEST', () => I.annulerLot(lot.id, 'essai'));
        const mask = (o, refs) => { let t = JSON.stringify(o); refs.forEach((r, i) => { t = t.split(r).join('{' + 'ABCD'[i] + '}'); }); return JSON.parse(t); };
        const refsG = [], refsC = [];
        /* Garanties */
        const G = out.assurances.garanties = {};
        G.analyse = resume(analyser('ga-valide'));
        const g1 = poser('ga-valide'); refsG.push(g1.reference);
        G.pose = { etat: g1.etat, nbLignes: g1.nbLignes, fiches: fiches(g1) };
        G.rejeu = resume(analyser('ga-valide'));
        const fac2 = S.collection('factures').insert({ numero: 'F-2027-0002', patientId: 'PAT0003', assureur: 'AFR', date: '2027-02-01', statut: 'emise' });
        G.annulationFactureEmise = refusDe(annuler(g1));
        S.collection('factures').archive(fac2.record.id, 'essai');
        const g3 = poser('ga-suivante'); refsG.push(g3.reference);
        G.annulationVersionPosterieure = refusDe(annuler(g1));
        const r3 = annuler(g3), r1 = annuler(g1);
        G.annulations = { suivante: { ok: r3.ok, archives: r3.archives === undefined ? null : r3.archives }, premiere: { ok: r1.ok, archives: r1.archives === undefined ? null : r1.archives },
          statuts: g1.ecrits.map((e) => S.collection(e.collection).get(e.id).statut) };
        /* Couvertures */
        const C_ = out.assurances.couvertures = {};
        const patientsEtat = () => ['PAT0003', 'PAT0004'].map((id) => { const p = S.collection('patients').get(id); return { id: id, assureur: p.assureur || null, numeroPolice: p.numeroPolice || null, tauxPriseEnCharge: p.tauxPriseEnCharge === undefined ? null : p.tauxPriseEnCharge, carteExpiration: p.carteExpiration || null, souscripteurId: p.souscripteurId || null }; });
        const couverturesEtat = () => S.collection('couverturesAssurance').all().map((c) => ({ patientId: c.patientId, debut: c.debut || null, fin: c.fin || null, statut: c.statut, assureur: c.assureur || null })).sort((a, b) => (a.patientId + a.debut + a.statut) < (b.patientId + b.debut + b.statut) ? -1 : 1);
        C_.avant = { patients: patientsEtat(), couvertures: couverturesEtat() };
        C_.analyse = resume(analyser('cv-valide'));
        const c1 = poser('cv-valide'); refsC.push(c1.reference);
        C_.pose = { etat: c1.etat, nbLignes: c1.nbLignes, fiches: fiches(c1), patients: patientsEtat(), couvertures: couverturesEtat() };
        const fac3 = S.collection('factures').insert({ numero: 'F-2030-0003', patientId: 'PAT0003', assureur: 'NSIA', date: '2030-02-01', statut: 'emise' });
        S.collection('factures').update(fac3.record.id, { _creeLe: '2999-01-01T00:00:00.000Z' });
        C_.annulationFactureEmise = refusDe(annuler(c1));
        S.collection('factures').archive(fac3.record.id, 'essai');
        const c3 = poser('cv-suivante'); refsC.push(c3.reference);
        C_.annulationPosterieure = refusDe(annuler(c1));
        const rc3 = annuler(c3), rc1 = annuler(c1);
        C_.annulations = { suivante: { ok: rc3.ok, archives: rc3.archives === undefined ? null : rc3.archives }, premiere: { ok: rc1.ok, archives: rc1.archives === undefined ? null : rc1.archives } };
        C_.apresAnnulation = { patients: patientsEtat(), couvertures: couverturesEtat() };
        out.assurances = { garanties: mask(out.assurances.garanties, refsG), couvertures: mask(out.assurances.couvertures, refsC) };
      }
      {
        /* 1. Analyse sans le droit d'importer : refusée en nommant, rien n'est consigné. */
        const avant = nbLots();
        const a = enRole('caissier', 'CAISSIER TEST', () => I.analyserOctets('fournisseurs', octetsDe('fo-valide'), 'fo-valide.xlsx'));
        const lotRefus2 = enRole('caissier', 'CAISSIER TEST', () => I.consigner(I.jeu('fournisseurs'), a));
        out.droits.analyseSansDroit = { role: 'caissier', jeu: 'fournisseurs', accepte: a.accepte, droitRefuse: !!a.droitRefuse, codes: codes(a), motif: a.globaux[0].motif, geste: a.globaux[0].geste,
          consigne: lotRefus2 === null ? null : 'consigné', lotsAjoutes: nbLots() - avant };
        /* 2. Application sans le droit (analyse faite sous un profil qui l'a) : le moteur relit le droit au moment d'écrire. */
        const aOk = I.analyserOctets('patients', octetsDe('pa-valide'), 'pa-valide.xlsx');
        const avantPat = S.collection('patients').all().length;
        const r = enRole('stock', 'STOCK TEST', () => I.appliquer('patients', aOk));
        out.droits.applicationSansDroit = { role: 'stock', jeu: 'patients', ok: r.ok, code: r.code, motif: r.motif, patientsAjoutes: S.collection('patients').all().length - avantPat, lotsAjoutes: nbLots() - avant };
        /* 3. Annulation : sans le droit d'annuler, puis le lot d'un AUTRE agent (le gestionnaire détient `A` sur les fournisseurs mais ne supervise pas). */
        /* Un lot APPLIQUÉ à défaire, d'un jeu que le gestionnaire détient (`A` sur le Grand Stock) : un article neuf, écrit par l'administrateur. */
        const tableGs = [I.jeu('grand-stock').colonnes.map((c) => c.label), versLigne('grand-stock', GS_LOT)];
        const octetsGs = X.ecrire({ feuilles: [{ nom: 'Données', lignes: tableGs }] });
        const reposé = I.appliquer('grand-stock', I.analyserOctets('grand-stock', octetsGs, 'gs-droits.xlsx'));
        if (!reposé.ok) throw new Error('lot à défaire non posé : ' + JSON.stringify({ code: reposé.code, motif: reposé.motif }));
        const lotFo = S.collection('lotsImportation').get(reposé.lot.id);
        const sansDroit = enRole('caissier', 'CAISSIER TEST', () => I.annulerLot(lotFo.id, 'essai'));
        const dUnAutre = enRole('stock', 'STOCK TEST', () => I.annulerLot(lotFo.id, 'essai'));
        out.droits.annulation = { jeu: 'grand-stock', sansDroit: { code: sansDroit.code, motif: sansDroit.motif }, dUnAutre: { code: dUnAutre.code, motif: dUnAutre.motif, geste: dUnAutre.geste }, etatLot: S.collection('lotsImportation').get(lotFo.id).etat };
        /* 4. Taille maximale : un réglage en base par jeu, un refus nommé (le défaut vaut 5 000 lignes). */
        S.setReglage('importBornes', { fournisseurs: 1 });
        const b = I.analyserOctets('fournisseurs', octetsDe('fo-valide'), 'fo-valide.xlsx');
        S.setReglage('importBornes', null);
        out.droits.borne = { borne: 1, accepte: b.accepte, codes: codes(b), motif: b.globaux[0].motif };
        /* 4 bis. Régler la taille maximale : réservé à qui SUPERVISE (droit d'annuler sur chaque jeu), entier de 1 à 100 000, motivé. */
        const rg = (role, jeuId, n, motif) => { const r = enRole(role, role.toUpperCase() + ' TEST', () => I.definirBorne(jeuId, n, motif)); return { ok: r.ok, code: r.code || null, avant: r.avant === undefined ? null : r.avant, lignes: r.lignes === undefined ? null : r.lignes }; };
        out.droits.reglageBorne = { sansSupervision: rg('stock', 'fournisseurs', 100, 'essai'), invalide: rg('da', 'fournisseurs', 'abc', 'essai'), zero: rg('da', 'fournisseurs', 0, 'essai'),
          trop: rg('da', 'fournisseurs', 100001, 'essai'), decimal: rg('da', 'fournisseurs', 12.5, 'essai'), sansMotif: rg('da', 'fournisseurs', 100, ' '), inconnu: rg('da', 'nimporte-quoi', 100, 'essai'),
          ok: rg('da', 'fournisseurs', 8000, 'Grosse reprise'), lu: S.reglage('importBornes', null) };
        S.setReglage('importBornes', null);
        /* 5. Capacité paie : un profil qui importe le personnel SANS écrire dans la paie n'a pas la colonne « Salaire de base » (lue de la matrice, jamais d'un nom de rôle). */
        const fiche = S.collection('rbac').insert({ role: 'agentadmin', statut: 'actif', droitsImport: { personnel: { voir: true, importer: true, annuler: false } } });
        SIGH.nav.invaliderRbac();
        const tete = I.jeu('personnel').colonnes.map((c) => c.label);
        const ligne = (o) => I.jeu('personnel').colonnes.map((c) => (o[c.cle] === undefined ? '' : o[c.cle]));
        const base = { matricule: '88', nom: 'NOUVEAU', prenom: 'Agent', sexe: 'F', fonction: 'infirmier', poste: 'Infirmière', service: 'Soins infirmiers' };
        const avecSalaire = [tete, ligne(Object.assign({ salaireBase: 150000 }, base))];
        const sansSalaire = [tete.filter((t) => t !== 'Salaire de base'), ligne(base).filter((_, k) => I.jeu('personnel').colonnes[k].cle !== 'salaireBase')];
        const enteteAdmin = enRole('admin', 'ADMIN TEST', () => I.analyserLignes(I.jeu('personnel'), avecSalaire, 'x.xlsx'));
        const enteteAgent = enRole('agentadmin', 'AGENT TEST', () => I.analyserLignes(I.jeu('personnel'), avecSalaire, 'x.xlsx'));
        const agentSans = enRole('agentadmin', 'AGENT TEST', () => I.analyserLignes(I.jeu('personnel'), sansSalaire, 'x.xlsx'));
        const modeleAgent = enRole('agentadmin', 'AGENT TEST', () => X.lire(I.modele('personnel')).feuilles[0].lignes[0]);
        const modeleAdmin = enRole('admin', 'ADMIN TEST', () => X.lire(I.modele('personnel')).feuilles[0].lignes[0]);
        S.collection('rbac')._remove(fiche.record.id);
        SIGH.nav.invaliderRbac();
        const noms = (a) => a.globaux.concat(a.lignes.reduce((t, l) => t.concat(l.problemes), [])).map((p) => p.code + ':' + p.niveau);
        out.droits.capacitePaie = { avecSalaireAdmin: { accepte: enteteAdmin.accepte, codes: noms(enteteAdmin) }, avecSalaireAgent: { accepte: enteteAgent.accepte, codes: noms(enteteAgent), motif: enteteAgent.globaux[0].motif },
          sansSalaireAgent: { accepte: agentSans.accepte, codes: noms(agentSans) }, modeleAgent: modeleAgent, modeleAdmin: modeleAdmin };
      }
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
        /* Lot IMP-C : les listes de saisie des cinq référentiels portés, lues des colonnes des jeux (aucune recopiée à la main). */
        secteursActivite: D.SECTEURS_ACTIVITE, specialitesPrestataire: D.SPECIALITES_PRESTATAIRE, domainesUnitesLabo: D.DOMAINES_UNITES_LABO,
        motifsCouverture: D.MOTIFS_COUVERTURE,
        destinationsTransfert: SIGH.parcours.DESTINATIONS_TRANSFERT, typesInventaire: I.jeu('inventaire-comptage').colonnes.find((c) => c.cle === 'type').liste, magasinsInventaire: I.jeu('inventaire-comptage').colonnes.find((c) => c.cle === 'magasin').liste,
        zonesEmplacement: I.jeu('emplacements').colonnes.find((c) => c.cle === 'zone').liste, temperaturesEmplacement: I.jeu('emplacements').colonnes.find((c) => c.cle === 'temperature').liste,
      };
      out.lienCellules = { serie1: X.versDate(1), serie60: X.versDate(61), serie45000: X.versDate(45000), serie46023: X.versDate(46023) };
      return out;
    }, [MAGASIN, CAS, GS_LOT]);

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
      + '/// Secteurs porteurs d\'activité facturable (`D.SECTEURS_ACTIVITE`).\n'
      + 'const importSecteursActivite = <String>[' + R.secteursActivite.map(q).join(', ') + '];\n\n'
      + '/// Spécialités d\'un prestataire externe (`D.SPECIALITES_PRESTATAIRE`).\n'
      + 'const importSpecialitesPrestataire = <String>[' + R.specialitesPrestataire.map(q).join(', ') + '];\n\n'
      + '/// Domaines des unités de mesure du laboratoire (`D.DOMAINES_UNITES_LABO`).\n'
      + 'const importDomainesUnitesLabo = <String>[' + R.domainesUnitesLabo.map(q).join(', ') + '];\n\n'
      + '/// Zones et températures de conservation d\'un emplacement de rangement (colonnes du jeu `emplacements`).\n'
      + 'const importZonesEmplacement = <String>[' + R.zonesEmplacement.map(q).join(', ') + '];\n'
      + 'const importTemperaturesEmplacement = <String>[' + R.temperaturesEmplacement.map(q).join(', ') + '];\n\n'
      + '/// Motifs d\'un changement de couverture (`D.MOTIFS_COUVERTURE`).\n'
      + 'const importMotifsCouverture = <String>[' + R.motifsCouverture.map(q).join(', ') + '];\n\n'
      + '/// Services destinataires d\'un bon de transfert (`PR.DESTINATIONS_TRANSFERT`).\n'
      + 'const importDestinationsTransfert = <String>[' + R.destinationsTransfert.map(q).join(', ') + '];\n\n'
      + '/// Types d\'un inventaire et magasins nommés (colonnes du jeu `inventaire-comptage`) : [valeur, libellé].\n'
      + 'const importTypesInventaire = <String>[' + R.typesInventaire.map(q).join(', ') + '];\n'
      + 'const importMagasinsInventaire = <List<String>>[' + R.magasinsInventaire.map((c) => '[' + q(c.valeur) + ', ' + q(c.label) + ']').join(', ') + '];\n\n'
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
