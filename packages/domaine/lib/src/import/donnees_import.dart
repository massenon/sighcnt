// ENGENDRÉ par prototype_html/build/vecteurs-import.js : référentiels de contrôle du module d'importation. Ne pas éditer.
/// Catégories d'articles (`D.CATEGORIES_PRODUIT`) : [identifiant, libellé].
const importCategoriesProduit = <List<String>>[
  ['medicament', 'Médicaments'],
  ['reactif', 'Réactifs de laboratoire'],
  ['conso_labo', 'Consommables de laboratoire'],
  ['conso_medical', 'Consommables médicaux'],
  ['fourniture', 'Fournitures administratives'],
  ['entretien', 'Produits d’entretien'],
  ['petit_materiel', 'Petit matériel médical'],
  ['immobilisation', 'Immobilisations'],
];

/// Fonctions du personnel (`D.CAPACITES`).
const importFonctions = <String>['medecin', 'sage_femme', 'infirmier', 'aide_soignant', 'tsl', 'biologiste', 'accueil', 'caissiere', 'dispensatrice', 'direction', 'stock', 'comptable', 'securite', 'entretien', 'chauffeur', 'chirurgien'];

/// Groupes sanguins (`D.GROUPES_SANGUINS`).
const importGroupesSanguins = <String>['O+', 'O-', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-'];

/// Journaux comptables (`D.JOURNAUX`) : [code, libellé].
const importJournaux = <List<String>>[
  ['ACH', 'Journal des achats'],
  ['VTE', 'Journal des ventes'],
  ['CAI', 'Journal de caisse-dépenses'],
  ['BQ', 'Journal de banque'],
  ['BQE', 'Journal de banque, dépenses'],
  ['SAL', 'Journal des salaires'],
  ['IMM', 'Journal des immobilisations'],
  ['OD', 'Journal des opérations diverses'],
  ['AN', 'Journal des à-nouveaux'],
];

/// Services de la clinique (`D.SERVICES`).
const importServices = <String>['Médecine générale', 'Maternité', 'Chirurgie', 'Laboratoire', 'Pharmacie', 'Imagerie / Échographie', 'Soins infirmiers', 'Accueil', 'Direction', 'Comptabilité'];

/// Secteurs du catalogue des actes (`D.ACTES`).
const importSecteursActes = <String>['Médecine générale', 'Chirurgie', 'Maternité', 'Imagerie médicale', 'Soins et observation'];

/// Sections du laboratoire (`SIGH.labo.SECTIONS`) : [identifiant, libellé].
const importSectionsLabo = <List<String>>[
  ['hematologie', 'Hématologie'],
  ['serologie', 'Sérologie'],
  ['parasitologie', 'Parasitologie'],
  ['biochimie', 'Biochimie'],
  ['bacteriologie', 'Bactériologie'],
  ['hormonologie', 'Hormonologie'],
];
