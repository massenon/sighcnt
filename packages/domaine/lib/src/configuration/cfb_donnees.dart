/// ENGENDRÉ par prototype_html/build/gen-cfb-donnees.js depuis packages/domaine/test/vecteurs/cfb.json — NE PAS ÉDITER À LA MAIN.
/// Les référentiels statiques (`D.*` de la maquette) que lisent cfg-regles, cfg-fiscalite, cfg-comptabilite, cfg-notifications, cfg-modules, cfg-systeme.
/// Gardés par `test/cfb_regles_test.dart` (égalité avec les vecteurs).
library;

class CfbSource {
  const CfbSource(this.document, this.devient, this.module, this.ecran, this.statut);
  final String document, devient, module, statut;
  final String? ecran;
}

const cfbSourcesVerite = <CfbSource>[
  CfbSource('Organigramme de la Clinique NASSIERA TOO', 'Structure organisationnelle + RBAC', 'M14 / CFG', 'cfg-organisation', 'Intégré'),
  CfbSource('NS 131/07/DM/DA/CNT/2026', 'Moteur d’évaluation et de sanctions', 'M10', 'm10-evaluations', 'Intégré'),
  CfbSource('NS 132/07/DM/DA/CNT/2026', 'Moteur des primes', 'M10 / M11', 'm10-primes', 'Intégré'),
  CfbSource('Fiche d’évaluation et de solde (juillet 2026)', 'Modèle d’état imprimable', 'M10 / RAP', 'm10-evaluations', 'Intégré'),
  CfbSource('Tarifs des analyses de laboratoire (48)', 'Catalogue laboratoire', 'M5', 'm5-catalogue', 'Intégré — tarifs à confirmer'),
  CfbSource('Tarifs des médicaments et accessoires (144)', 'Catalogue tarifaire pharmacie', 'M6', 'cfg-tarifs', 'Intégré — tarifs à confirmer'),
  CfbSource('Inventaire « Grand Stock » (SAGE 100)', 'Stock initial — 175 articles repris', 'M6', 'm6-reprise', 'Intégré'),
  CfbSource('Facture fournisseur SoBAPS (BL 26LNA00026)', 'Modèle du workflow achat', 'M7', 'm7-receptions', 'Intégré'),
  CfbSource('Bon d’expression de besoins (modèle vierge)', 'Workflow de demande interne', 'M7', 'm7-besoins', 'Intégré'),
  CfbSource('Classeur comptable SYSCOHADA', 'Plan comptable + journaux', 'M12', 'm12-plan-comptable', 'Intégré — partiel'),
  CfbSource('Compte de résultat mensuel 2025', 'Baseline financière de comparaison', 'M12 / M14', 'm12-etats-financiers', 'À importer'),
  CfbSource('Planning de travail des médecins', 'Moteur de planning (garde 24h)', 'M10', 'm10-planning', 'Intégré'),
  CfbSource('Planning agents d’entretien et sécurité', 'Moteur de planning RH', 'M10', 'm10-securite-entretien', 'Intégré'),
  CfbSource('Liste des 13 compagnies d’assurance', 'Référentiel assureurs', 'M9', 'm9-compagnies', 'Intégré'),
  CfbSource('Photographies du site et entête officielle', 'Brand Configuration Center', 'CFG', 'cfg-branding', 'Intégré'),
];

class CfbRegleGestion {
  const CfbRegleGestion(this.code, this.regle, this.module, this.ecran);
  final String code, regle, module, ecran;
}

const cfbReglesGestion = <CfbRegleGestion>[
  CfbRegleGestion('RG-01', 'Identifiant patient CNT/[n°]/[année] généré automatiquement, unique et non modifiable', 'M1', 'm1-patients'),
  CfbRegleGestion('RG-02', 'Médicaments facturés au prix d’achat, sans marge bénéficiaire', 'M6 / M8', 'm6-produits'),
  CfbRegleGestion('RG-03', 'Toute sortie de stock rattachée à un justificatif ; stock jamais négatif', 'M6', 'm6-mouvements'),
  CfbRegleGestion('RG-04', 'Commande de stock gros validée par la Directrice Administrative', 'M7', 'm7-commandes'),
  CfbRegleGestion('RG-05', 'Rangement FEFO et alertes de péremption automatiques', 'M6', 'm6-lots'),
  CfbRegleGestion('RG-06', 'Sortie d’hospitalisation conditionnée à l’apurement du solde', 'M3', 'm3-sorties'),
  CfbRegleGestion('RG-07', 'Sortie requérant signature patient, signature infirmier et constat du gardien', 'M3', 'm3-sorties'),
  CfbRegleGestion('RG-08', 'Sortie contre avis médical motivée ; avis du Procureur si nécessaire', 'M3', 'm3-sortie-avis-medical'),
  CfbRegleGestion('RG-09', 'Prise en charge assurance appliquée uniquement si la carte est valide', 'M9', 'm9-assures'),
  CfbRegleGestion('RG-10', 'Toute écriture comptable équilibrée avant validation', 'M12', 'm12-ecritures'),
  CfbRegleGestion('RG-11', 'Primes de garde et de permanence calculées depuis le planning validé', 'M10 / M11', 'm10-primes'),
  CfbRegleGestion('RG-12', 'Journalisation de toute action ; aucune action anonyme', 'M14', 'm14-audit'),
  CfbRegleGestion('RG-13', 'Cloisonnement des données médicales, financières et RH', 'M14', 'm14-roles'),
  CfbRegleGestion('RG-14', 'Suppression logique uniquement, jamais de suppression physique', 'Transverse', 'm14-audit'),
];

/// `D.PARAM_STOCK.options` : (identifiant, libellé, note).
const cfbOptionsValorisation = <(String, String, String)>[
  ('prixVente', 'Prix de vente', 'Valeur de sortie = prix de vente de l’article. Demandé par la Direction ; la marge éventuelle est reconnue dès la sortie de stock.'),
  ('cump', 'Coût unitaire moyen pondéré (CUMP)', 'Valeur de sortie = coût moyen d’acquisition. Méthode comptable classique ; la marge n’apparaît qu’à la facturation.'),
];
const cfbValorisationDefaut = 'prixVente';

/// `D.FAMILLES_ARTICLES` : (identifiant, libellé, groupe).
const cfbFamillesArticles = <(String, String, String)>[
  ('medicament', 'Médicaments', 'pharmacie'),
  ('conso_medical', 'Consommables médicaux', 'pharmacie'),
  ('reactif', 'Réactifs de laboratoire', 'laboratoire'),
  ('conso_labo', 'Consommables de laboratoire', 'laboratoire'),
  ('petit_materiel', 'Petit matériel médical', 'equipement'),
  ('entretien', 'Produits d’entretien', 'logistique'),
  ('fourniture', 'Fournitures de bureau', 'logistique'),
];
/// `D.GROUPES_ARTICLES` : (identifiant, libellé).
const cfbGroupesArticles = <(String, String)>[
  ('pharmacie', 'Pharmacie et consommables de soins'),
  ('laboratoire', 'Laboratoire'),
  ('equipement', 'Équipement et petit matériel'),
  ('logistique', 'Logistique et fonctionnement'),
];

class CfbNoteService {
  const CfbNoteService(this.reference, this.version, this.dateEffet, this.statut, this.objet);
  final String reference, dateEffet, statut, objet;
  final int version;
}

/// `D.NS131` / `D.NS132` (référence, version, date d'effet, statut, objet).
const cfbNs131 = CfbNoteService('NS 131/07/DM/DA/CNT/2026', 1, '2026-07-13', 'ACTIVE', 'Modification de l’évaluation du rendement entrant dans le compte de la rémunération salariale');
const cfbNs132 = CfbNoteService('NS n° 132/07/DM/DA/CNT/2026', 1, '2026-07-13', 'ACTIVE', 'Primes diverses');

class CfbObligation {
  const CfbObligation(this.code, this.libelle, this.periodicite, this.jour, this.mois, this.part, this.declaration, this.note, this.source);
  final String code, libelle, periodicite, note, source;
  final int jour;

  /// 0 (janvier) à 11 ; `null` pour une obligation mensuelle.
  final int? mois;

  /// Part réglée (en %) ; `null` : sans objet (déclaration, solde).
  final int? part;
  final String? declaration;
}

/// `D.CALENDRIER_FISCAL`, dans l'ordre de la maquette.
const cfbCalendrierFiscal = <CfbObligation>[
  CfbObligation('ITS', 'Impôt sur les traitements salariaux', 'mensuelle', 10, null, 100, 'Déclaration mensuelle avant paiement', 'Le 10 du mois suivant le mois d’exercice. Reporté au jour ouvrable suivant si l’échéance tombe un week-end.', 'Précisions du comptable — réunion du 19/08/2026'),
  CfbObligation('AIB', 'Acompte sur impôt assis sur les bénéfices', 'mensuelle', 10, null, 100, 'Déclaration mensuelle avant paiement', 'Le 10 de chaque mois, après la déclaration préalable.', 'Précisions du comptable — réunion du 19/08/2026'),
  CfbObligation('VPS', 'Versement patronal sur salaires', 'mensuelle', 10, null, 100, 'Déclaration mensuelle avant paiement', 'Le 10 du mois suivant le mois d’exercice.', 'Précisions du comptable — réunion du 19/08/2026'),
  CfbObligation('CNSS', 'Cotisations sociales CNSS', 'mensuelle', 10, null, 100, 'Déclaration mensuelle avant paiement', 'Le 10 du mois suivant. Part patronale 16,4 %, part ouvrière 3,6 %.', 'Précisions du comptable — réunion du 19/08/2026'),
  CfbObligation('IS-1', 'Impôt sur les sociétés — 1er acompte', 'annuelle', 10, 2, 25, null, 'Premier des quatre acomptes trimestriels, assis sur l’impôt de l’exercice précédent divisé par quatre. Le 10 mars — confirmé par la Direction le 25/08/2026.', 'Précisions du comptable — réunion du 19/08/2026'),
  CfbObligation('IS-2', 'Impôt sur les sociétés — 2e acompte', 'annuelle', 10, 5, 25, null, 'Deuxième acompte trimestriel.', 'Précisions du comptable — réunion du 19/08/2026'),
  CfbObligation('IS-3', 'Impôt sur les sociétés — 3e acompte', 'annuelle', 10, 8, 25, null, 'Troisième acompte trimestriel.', 'Précisions du comptable — réunion du 19/08/2026'),
  CfbObligation('IS-4', 'Impôt sur les sociétés — 4e acompte', 'annuelle', 10, 11, 25, null, 'Quatrième acompte trimestriel.', 'Précisions du comptable — réunion du 19/08/2026'),
  CfbObligation('IS-SOLDE', 'Liquidation du solde de l’impôt sur les sociétés', 'annuelle', 30, 3, null, null, 'Le 30 avril de chaque année, PRÉALABLEMENT au dépôt des états financiers. Ajuste à la hausse ou à la baisse les acomptes versés l’exercice précédent — confirmé par la Direction le 25/08/2026.', 'Précisions du comptable — réunion du 19/08/2026'),
  CfbObligation('ETATS-FIN', 'Dépôt des états financiers', 'annuelle', 30, 3, null, null, 'Le 30 avril de l’année suivant l’exercice clos, après la liquidation du solde.', 'Précisions du comptable — réunion du 19/08/2026'),
  CfbObligation('PATENTE-DECL', 'Patente — déclaration prévisionnelle', 'annuelle', 31, 0, null, null, 'Date limite de la déclaration prévisionnelle de la patente.', 'Précisions du comptable — réunion du 19/08/2026'),
  CfbObligation('PATENTE-1', 'Patente — 1er acompte', 'annuelle', 10, 1, 50, 'Déclaration prévisionnelle au 31 janvier', 'Première moitié. La patente se paie une fois par an, avec possibilité de régler en deux tranches.', 'Précisions du comptable — réunion du 19/08/2026'),
  CfbObligation('PATENTE-2', 'Patente — solde', 'annuelle', 30, 3, 50, null, 'Seconde moitié, au 30 avril.', 'Précisions du comptable — réunion du 19/08/2026'),
  CfbObligation('CCIB-DECL', 'CCIB — déclaration prévisionnelle', 'annuelle', 28, 1, null, null, 'La déclaration prévisionnelle s’effectue à la FIN DU MOIS, avant le premier acompte — confirmé par la Direction le 25/08/2026.', 'Précisions du comptable — réunion du 19/08/2026'),
  CfbObligation('CCIB-1', 'CCIB — 1re tranche', 'annuelle', 10, 2, 50, 'Déclaration prévisionnelle en fin de mois', 'Contribution annuelle de 300 000 FCFA, réglée en deux tranches égales de 150 000 FCFA. Premier acompte le 10 mars (50 %) — confirmé par la Direction le 25/08/2026.', 'Précisions du comptable — réunion du 19/08/2026'),
  CfbObligation('CCIB-2', 'CCIB — 2e tranche', 'annuelle', 10, 5, 50, null, 'Seconde tranche de 150 000 FCFA, le 10 juin (50 %) — confirmé par la Direction le 25/08/2026.', 'Précisions du comptable — réunion du 19/08/2026'),
  CfbObligation('TVM', 'Taxe sur véhicules à moteur', 'annuelle', 30, 3, 100, null, 'Une fois par an, au plus tard le 30 avril.', 'Précisions du comptable — réunion du 19/08/2026'),
  CfbObligation('ORTB-RADIO', 'Redevance ORTB / Radio', 'annuelle', 30, 2, 100, null, 'Prélevée sur TOUS les salariés sans exception — 1 000 FCFA par agent, au mois de mars.', 'Précisions du comptable — réunion du 19/08/2026'),
  CfbObligation('ORTB-TELE', 'Redevance ORTB / Télé', 'annuelle', 30, 5, 100, null, 'Prélevée en SUS de la radio sur les salaires supérieurs à 60 000 FCFA — 3 000 FCFA par agent, au mois de juin.', 'Précisions du comptable — réunion du 19/08/2026'),
];
const cfbCcibTotal = 300000;

/// Numérotation des documents (littéral de l'écran) : type, préfixe, format, séquence.
const cfbNumerotation = <(String, String, String, String)>[
  ('Facture normalisée', 'FN-2026-', 'FN-AAAA-NNNNN', 'Strictement séquentielle'),
  ('Facture pro-forma', 'PRO-2026-', 'PRO-AAAA-NNNNN', 'Indépendante'),
  ('Avoir', 'AV-2026-', 'AV-AAAA-NNNN', 'Strictement séquentielle'),
  ('Dossier patient', 'CNT', 'CNT/[n°]/[AA]', 'Par année civile (RG-01)'),
  ('Bon de commande', 'BC-2026-', 'BC-AAAA-NNNN', 'Par exercice'),
  ('Bon d’expression de besoins', 'BEB-2026-', 'BEB-AAAA-NNNN', 'Par exercice'),
  ('Bulletin de paie', 'BP-', 'BP-NNNNN', 'Par période de paie'),
  ('Écriture comptable', '[JOURNAL]-2026-', 'JJJ-AAAA-NNNNN', 'Par journal'),
];
/// Obligations déclaratives (littéral de l'écran) : déclaration, périodicité, échéance, écran producteur.
const cfbObligationsDeclaratives = <(String, String, String, String)>[
  ('Cotisations CNSS', 'Mensuelle', '15 du mois suivant', 'm11-cotisations'),
  ('Impôt sur les traitements et salaires (ITS)', 'Mensuelle', '10 du mois suivant', 'm11-cotisations'),
  ('Versement patronal de solidarité (VPS)', 'Mensuelle', '10 du mois suivant', 'm11-cotisations'),
  ('Transmission des factures normalisées', 'Continue', 'À l’émission', 'mecef-transmission'),
  ('États financiers de synthèse', 'Annuelle', 'Clôture de l’exercice', 'm12-etats-financiers'),
];
const cfbEcranMecefConfig = 'mecef-config';

class CfbNotification {
  const CfbNotification(this.id, this.libelle, this.detail, this.destinataires, this.app, this.sms, this.mail);
  final String id, libelle, detail, destinataires;
  final bool app, sms, mail;
}

/// `NOTIFS` de cfg-notifications : un événement, ses destinataires et ses canaux par défaut.
const cfbNotifications = <CfbNotification>[
  CfbNotification('admission', 'Nouvelle admission', 'Alerte à l’admission d’un patient', 'Infirmiers, Direction médicale', true, false, false),
  CfbNotification('sortie', 'Sortie d’hospitalisation', 'Alerte à la caisse pour vérification du solde (RG-06)', 'Caisse, Infirmiers', true, false, false),
  CfbNotification('rupture', 'Rupture de stock', 'Produit passant sous le seuil d’alerte', 'Gestionnaire de stock, Pharmacie', true, true, false),
  CfbNotification('peremption', 'Péremption proche', 'Lot arrivant à échéance sous 90 jours (RG-05)', 'Pharmacie, Gestionnaire de stock', true, false, false),
  CfbNotification('resultat', 'Résultat de laboratoire disponible', 'Notification au médecin prescripteur', 'Médecins', true, true, false),
  CfbNotification('facture', 'Facture générée', 'Notification à la caisse et à la comptabilité', 'Caisse, Comptabilité', true, false, false),
  CfbNotification('commande', 'Commande à valider', 'Demande de validation (RG-04)', 'Directrice Administrative', true, false, true),
  CfbNotification('paie', 'Paie à valider', 'Soumission des bulletins à la Direction', 'Direction', true, false, true),
  CfbNotification('carte', 'Carte d’assurance expirée', 'Alerte à la facturation (RG-09)', 'Caisse', true, false, false),
  CfbNotification('mecef', 'Facture MECeF rejetée', 'Anomalie fiscale à corriger', 'Caisse, Comptabilité', true, false, true),
  CfbNotification('securite', 'Tentative de connexion infructueuse', 'Alerte de sécurité (RG-12)', 'Administrateur système', true, false, true),
  CfbNotification('sauvegarde', 'Échec de sauvegarde', 'Alerte technique', 'Administrateur système', true, true, true),
];

/// `NT.PROFILS_AUDIO` : (identifiant, libellé, volume, répétition, note).
const cfbProfilsAudio = <(String, String, double, int, String)>[
  ('silencieux', 'Silencieux', 0.0, 0, 'Aucun son. La cloche, le badge et les toasts continuent de fonctionner.'),
  ('discret', 'Discret', 0.4, 0, 'Un son court, jamais répété. Pour les postes en salle.'),
  ('standard', 'Standard', 1.0, 0, 'Son court pour l’information, son renforcé pour l’urgent.'),
  ('critique', 'Critique seulement', 1.0, 1, 'Seules les alertes graves sonnent, et elles se répètent une fois.'),
];
/// `NT.DEFAUTS`.
const cfbParamsNotifDefaut = <String, Object>{'visuel': true, 'son': true, 'profil': 'standard', 'volume': 0.8, 'temporisation': 30};

/// `S.COLLECTIONS_ESSENTIELLES` : ce que le vidage des jeux de test CONSERVE toujours.
const cfbEssentielles = <String>[
  'actes',
  'analyses',
  'produits',
  'assureurs',
  'fournisseurs',
  'comptes',
  'banques',
  'naturesFacture',
  'centresCouts',
  'secteurs',
  'postes',
  'personnel',
  'soignants',
  'fichesPoste',
  'ressources',
  'souscripteurs',
  'garanties',
  'certificats',
  'typesPiece',
  'catalogueTarifs',
  'objectifsPilotage',
  'valorisationsSage',
  'ambulances',
  'materiel',
  'utilisateurs',
  'rbac',
  'modulesActifs',
  'regimesTravail',
  'grillePrimes',
  'historiquePrimes',
  'baremeNS131',
  'historiqueBareme',
  'examensLabo',
  'unitesLabo',
  'variablesLabo',
  'plagesReactif',
  'examensImagerie',
  'variablesImagerie',
  'pathologies',
  'modelesBadge',
  'modelesMessage',
  'enquetes',
  'emplacements',
  'audit',
];

/// `S.libelleCollection` pour les collections du jeu du poste : (module, entité) — « — » / nom technique si la table de la maquette n'en porte pas.
const cfbLibellesCollections = <String, (String, String)>{
  'accouchements': ('M4', 'Accouchements'),
  'actes': ('CFG', 'Catalogue des actes'),
  'administrations': ('M3', 'Administrations de traitement'),
  'admissions': ('M3', 'Admissions'),
  'ambulance': ('M13', 'Ambulance'),
  'ambulances': ('M13', 'Répertoire des ambulances'),
  'analyses': ('M5', 'Catalogue des analyses'),
  'antecedents': ('—', 'antecedents'),
  'appels': ('—', 'appels'),
  'assurancesPersonnel': ('M10', 'Assurances du personnel'),
  'assureurs': ('M9', 'Compagnies d’assurance'),
  'audit': ('M14', 'Journal d’audit'),
  'avances': ('M11', 'Avances'),
  'avoirs': ('M8', 'Avoirs'),
  'badges': ('M10', 'Badges du personnel'),
  'banques': ('M12', 'Comptes de trésorerie'),
  'baremeNS131': ('M10', 'Barème d’évaluation NS 131'),
  'besoins': ('M7', 'Bons de besoins'),
  'budgets': ('M12', 'Budgets'),
  'bulletins': ('M11', 'Bulletins de paie'),
  'catalogueTarifs': ('CFG', 'Catalogue tarifaire'),
  'centresCouts': ('M12', 'Centres de coûts'),
  'certificats': ('CFG', 'Certificats médicaux'),
  'chambres': ('—', 'chambres'),
  'checklistsBloc': ('M3', 'Check-listes du bloc'),
  'clichesImagerie': ('M2', 'Clichés d’échographie'),
  'commandes': ('M7', 'Commandes'),
  'comptes': ('M12', 'Plan comptable'),
  'conges': ('M10', 'Congés'),
  'constantes': ('—', 'constantes'),
  'consultations': ('M2', 'Consultations et rendez-vous'),
  'contrats': ('M10', 'Contrats'),
  'contreReferences': ('M1', 'Fiches de contre-référence'),
  'courriers': ('M13', 'Courriers'),
  'couverturesAssurance': ('M9', 'Couvertures d’assurance (historique)'),
  'cpa': ('M3', 'Consultations pré-anesthésiques'),
  'cpon': ('M4', 'Consultations post-natales'),
  'crMaternite': ('M4', 'Comptes rendus de maternité'),
  'crOperatoires': ('M3', 'Comptes rendus opératoires'),
  'deces': ('M4', 'Décès'),
  'demandesAnalyses': ('M5', 'Demandes d’analyses'),
  'demandesImagerie': ('M2', 'Demandes d’imagerie'),
  'depenses': ('M12', 'Dépenses de trésorerie'),
  'dispensations': ('M6', 'Dispensations'),
  'documents': ('GED', 'Bibliothèque documentaire'),
  'documentsPatient': ('M1', 'Documents numérisés du patient'),
  'donneurs': ('M5', 'Donneurs'),
  'dossiersConsultation': ('M1', 'Dossiers de consultation'),
  'dossiersObstetricaux': ('M4', 'Dossiers obstétricaux'),
  'echeancesFiscales': ('M12', 'Échéances fiscales'),
  'ecritures': ('M12', 'Écritures'),
  'emplacements': ('M6', 'Emplacements de rangement'),
  'enquetes': ('M13', 'Modèles d’enquête'),
  'evaluations': ('M10', 'Évaluations'),
  'evenements': ('M10', 'Événements du personnel'),
  'evenementsEtablissement': ('M13', 'Événements de l’établissement'),
  'examensImagerie': ('CFG', 'Catalogue des examens d’imagerie'),
  'examensLabo': ('M5', 'Catalogue des examens'),
  'executionsTaches': ('—', 'executionsTaches'),
  'exercices': ('—', 'exercices'),
  'factures': ('M8', 'Factures'),
  'facturesFournisseurs': ('M7', 'Factures fournisseurs'),
  'facturesMere': ('M9', 'Factures mères d’assurance'),
  'fichesPoste': ('M10', 'Fiches de poste'),
  'fichesReference': ('M1', 'Fiches de référence'),
  'fichiersSauvegarde': ('—', 'fichiersSauvegarde'),
  'fileAttente': ('M2', 'File d’attente'),
  'fournisseurs': ('M7', 'Fournisseurs'),
  'garanties': ('M9', 'Garanties de prise en charge'),
  'grillePrimes': ('M10', 'Grille des primes NS 132'),
  'grossesses': ('M4', 'Suivi CPN & carte maternelle'),
  'heuresSup': ('M11', 'Heures supplémentaires'),
  'historiqueBareme': ('M10', 'Versions antérieures du barème'),
  'historiquePrimes': ('M10', 'Versions antérieures de la grille des primes'),
  'immobilisations': ('M12', 'Immobilisations'),
  'inventaires': ('M6', 'Inventaires'),
  'jetonsEnquete': ('M13', 'Liens de partage des enquêtes'),
  'lits': ('—', 'lits'),
  'livraisons': ('M7', 'Livraisons'),
  'lots': ('M6', 'Lots'),
  'materiel': ('M13', 'Parc technique'),
  'missions': ('M10', 'Ordres de mission'),
  'modelesBadge': ('M10', 'Modèles de badge'),
  'modelesMessage': ('CFG', 'Modèles de message'),
  'modulesActifs': ('CFG', 'Activité des modules'),
  'modulesManifeste': ('—', 'modulesManifeste'),
  'mouvements': ('M6', 'Mouvements de stock'),
  'naissances': ('M4', 'Naissances'),
  'naturesFacture': ('CFG', 'Natures de facture'),
  'notifications': ('M14', 'Notifications'),
  'objectifsPilotage': ('M12', 'Objectifs et seuils du pilotage'),
  'observations': ('M3', 'Mises en observation'),
  'ordonnances': ('M2', 'Ordonnances'),
  'participations': ('M10', 'Participations aux événements'),
  'partogrammes': ('M4', 'Partogrammes'),
  'pathologies': ('M2', 'Référentiel des pathologies'),
  'patients': ('M1', 'Patients'),
  'personnel': ('M10', 'Personnel'),
  'pieces': ('M1', 'Pièces certifiantes délivrées'),
  'plagesReactif': ('M5', 'Plages de référence par lot de réactif'),
  'planAnnuel': ('M13', 'Plan annuel'),
  'planificationFamiliale': ('M4', 'Planification familiale'),
  'planning': ('M10', 'Planning'),
  'poches': ('M5', 'Banque de sang'),
  'postes': ('CFG', 'Postes de l’organigramme'),
  'prescriptions': ('M2', 'Prescriptions'),
  'presences': ('M10', 'Présences'),
  'prestataires': ('M10', 'Prestataires'),
  'pretsEtudes': ('M11', 'Prêts-études et avances'),
  'produits': ('M6', 'Produits et médicaments'),
  'ptme': ('M4', 'Registre PTME'),
  'pvReceptions': ('M7', 'PV de réception'),
  'rappels': ('CFG', 'Rappels'),
  'rapportsMedicaux': ('M3', 'Rapports médicaux'),
  'rapprochements': ('M12', 'Rapprochements bancaires'),
  'rbac': ('M14', 'Rôles et permissions'),
  'regimesTravail': ('M10', 'Régimes de travail par catégorie'),
  'registreSONU': ('M4', 'Registre SONUB / SONUC'),
  'relances': ('M9', 'Relances'),
  'releves': ('M3', 'Relevés de constantes au lit du patient'),
  'remboursements': ('M8', 'Remboursements'),
  'rendezvous': ('—', 'rendezvous'),
  'reponsesEnquetes': ('M13', 'Réponses d’enquête'),
  'ressources': ('CFG', 'Ressources graphiques'),
  'resultatsImagerie': ('M2', 'Comptes rendus d’imagerie'),
  'reunions': ('M13', 'Réunions'),
  'rolesBase': ('—', 'rolesBase'),
  'scoresGlasgow': ('M3', 'Scores de Glasgow'),
  'secteurs': ('CFG', 'Secteurs de la clinique'),
  'soignants': ('M14', 'Prescripteurs et exécutants de soins'),
  'soins': ('M3', 'Soins'),
  'soinsCuratifsMaternite': ('M4', 'Soins curatifs & urgences maternité'),
  'souscripteurs': ('M9', 'Souscripteurs'),
  'suiviMaternite': ('M4', 'Suivi maternité'),
  'surveillancesTransfusion': ('M3', 'Surveillances transfusionnelles'),
  'taches': ('CFG', 'Files d’attente'),
  'tachesPlanifiees': ('—', 'tachesPlanifiees'),
  'tentativesConnexion': ('M14', 'Tentatives de connexion refusées'),
  'transferts': ('M6', 'Transferts'),
  'typesPiece': ('CFG', 'Types de pièces certifiantes'),
  'unitesLabo': ('M5', 'Unités de mesure'),
  'utilisateurs': ('M14', 'Utilisateurs'),
  'valorisationsSage': ('M6', 'Valorisations de la reprise SAGE'),
  'variablesImagerie': ('CFG', 'Variables des comptes rendus d’imagerie'),
  'variablesLabo': ('M5', 'Variables et valeurs de référence'),
  'visites': ('—', 'visites'),
  'visitesHospi': ('—', 'visitesHospi'),
};

/// `NOYAU` de cfg-modules : les modules qui ne se ferment pas, et pourquoi.
const cfbNoyau = <String, String>{
  'CFG': 'porte cet interrupteur — un interrupteur qui se coupe lui-même ne se rallume plus',
  'DASH': 'porte la page d’accueil de chaque rôle — la fermer laisserait la connexion sans destination',
};
