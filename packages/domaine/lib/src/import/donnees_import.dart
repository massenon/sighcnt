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

/// Secteurs porteurs d'activité facturable (`D.SECTEURS_ACTIVITE`).
const importSecteursActivite = <String>['Médecine générale', 'Chirurgie', 'Maternité', 'Imagerie médicale', 'Laboratoire', 'Accueil', 'Soins et observation', 'Pharmacie'];

/// Spécialités d'un prestataire externe (`D.SPECIALITES_PRESTATAIRE`).
const importSpecialitesPrestataire = <String>['Circoncision', 'Hydrotubation', 'Accouchement', 'Analyses spécialisées', 'Chirurgie', 'Échographie', 'Anesthésie', 'Autre'];

/// Domaines des unités de mesure du laboratoire (`D.DOMAINES_UNITES_LABO`).
const importDomainesUnitesLabo = <String>['Hématologie', 'Biochimie', 'Hormonologie', 'Bactériologie', 'Parasitologie', 'Hémostase', 'Andrologie', 'Général'];

/// Zones et températures de conservation d'un emplacement de rangement (colonnes du jeu `emplacements`).
const importZonesEmplacement = <String>['Rayonnage sec', 'Chaîne du froid', 'Armoire sécurisée', 'Réserve', 'Salle de soins'];
const importTemperaturesEmplacement = <String>['Ambiante', '2 à 8 °C', '− 20 °C', 'Sous clé, ambiante'];

/// Services destinataires d'un bon de transfert (`PR.DESTINATIONS_TRANSFERT`).
const importDestinationsTransfert = <String>['Pharmacie d’urgence', 'Pharmacie externe', 'Laboratoire', 'Hospitalisation', 'Maternité', 'Bloc opératoire', 'Salle de soins'];

/// Types d'un inventaire et magasins nommés (colonnes du jeu `inventaire-comptage`) : [valeur, libellé].
const importTypesInventaire = <String>['Hebdomadaire', 'Mensuel', 'Annuel', 'Tournant', 'Ponctuel'];
const importMagasinsInventaire = <List<String>>[['gros', 'Stock gros'], ['detail', 'Stock détail']];

/// Sections du laboratoire (`SIGH.labo.SECTIONS`) : [identifiant, libellé].
const importSectionsLabo = <List<String>>[
  ['hematologie', 'Hématologie'],
  ['serologie', 'Sérologie'],
  ['parasitologie', 'Parasitologie'],
  ['biochimie', 'Biochimie'],
  ['bacteriologie', 'Bactériologie'],
  ['hormonologie', 'Hormonologie'],
];
