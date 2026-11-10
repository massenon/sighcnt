// ENGENDRÉ par prototype_html/build/vecteurs-aib.js (SIGH.data.SITUATIONS_AIB et BAREME_AIB, tels que la maquette les sème au socle), ne pas éditer.
// Les semences du barème de l'AIB : trois situations de l'acheteur et quatre versions datées, toutes « à valider » (aucun texte réglementaire au dépôt, Direction 09/11/2026).

const List<Map<String, Object?>> aibSituationsSemees = [
  {'id': 'SAI01', 'code': 'ifu_actif', 'libelle': 'Acheteur avec IFU actif', 'declencheur': 'ifu_renseigne', 'ordre': 1, 'description': 'L’acheteur présente un IFU de 13 chiffres. L’activité de l’IFU n’est pas vérifiée auprès de la DGI (la maquette ne peut pas l’interroger) : elle est présumée.'},
  {'id': 'SAI02', 'code': 'ifu_inactif_ou_absent', 'libelle': 'Acheteur sans IFU actif', 'declencheur': 'ifu_absent', 'ordre': 2, 'description': 'Aucun IFU renseigné (particulier) ou IFU désactivé : contribuable non conforme ou non immatriculé.'},
  {'id': 'SAI03', 'code': 'prestation_service', 'libelle': 'Prestation de service retenue par le payeur', 'declencheur': 'choix', 'ordre': 3, 'description': 'Prestation de service dont l’organisme payeur retient l’AIB sur le prix hors taxe. Choisie par le caissier, jamais d’office.'},
];

const List<Map<String, Object?>> aibBaremeSeme = [
  {'id': 'BAI001', 'situation': 'ifu_inactif_ou_absent', 'taux': 1, 'dateEffet': '2026-01-01', 'dateFin': '2026-09-06', 'source': 'Régime de la facture certifiée de référence (AIB 1 %, paramètre fiscal de la maquette) et modalités de 2022 rapportées par la presse : proposition à valider, texte réglementaire à produire', 'motif': 'Taux appliqué avant le communiqué de septembre 2026 : défaut historique de la maquette (date d’effet d’attente : début de l’exercice 2026).'},
  {'id': 'BAI002', 'situation': 'ifu_inactif_ou_absent', 'taux': 5, 'dateEffet': '2026-09-07', 'dateFin': null, 'source': 'Communiqué de la DGI (3 ou 4 septembre 2026) rapporté par la presse béninoise (La Nouvelle Tribune, BeninWebTV) : proposition à valider, texte réglementaire à produire', 'motif': 'Généralisation du prélèvement de 5 % à l’émission des factures normalisées, à compter du 07/09/2026.'},
  {'id': 'BAI003', 'situation': 'ifu_actif', 'taux': 1, 'dateEffet': '2026-01-01', 'dateFin': null, 'source': 'Régime de la facture certifiée de référence (AIB 1 %, paramètre fiscal de la maquette) et modalités de 2022 rapportées par la presse : proposition à valider, texte réglementaire à produire', 'motif': 'Défaut de la fenêtre MECeF quand l’acheteur a un IFU actif (date d’effet d’attente : début de l’exercice 2026).'},
  {'id': 'BAI004', 'situation': 'prestation_service', 'taux': 3, 'dateEffet': '2026-01-01', 'dateFin': null, 'source': 'Modalités de 2022 rapportées par la presse (prestations de services : 3 %, retenue par l’organisme payeur) : proposition à valider, texte réglementaire à produire', 'motif': 'Prestation de service retenue par le payeur (date d’effet d’attente : début de l’exercice 2026).'},
];
