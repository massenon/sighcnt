# Spécimens des états imprimés de SIGH-CNT

Dossier de présentation du projet : un spécimen PDF de chaque état imprimé que le logiciel sait produire, rangé par module. Ouvrir `index.html` pour la consultation en vignettes (aucune dépendance réseau).

**169 spécimens**, 47.4 Mo. Tous portent le filigrane et le bandeau « SPÉCIMEN, données fictives ».

## Méthode

1. La maquette (`prototype_html/`) est pilotée dans Chrome sur un banc isolé (base jetable, horloge décalée sur la date du jeu, 16/08/2026).
2. Les points d'entrée de l'impression (`SIGH.print.etat`, `ticket`, `badge`, `planche`) sont enveloppés : la feuille que le logiciel bâtit est relevée telle quelle, avec le site d'appel (fichier et ligne) lu dans la pile. Rien n'est redessiné.
3. Chaque écran est exploré : commandes d'impression de la page, de chaque onglet, des tiroirs de fiche et des fenêtres de paramétrage. Un spécimen est gardé par site d'appel et par intitulé d'état (au plus 6 variantes par site).
4. Les identités sont substituées dans le texte (voir Confidentialité), puis la feuille est rendue en PDF par Chrome (`page.pdf`) avec la même feuille de style que le logiciel : A4 portrait, ticket 80 mm, carte CR80 aux dimensions réelles.
5. Régénération : `npm run presentation` depuis `prototype_html/` (`build/presentation.js`, phases `capture`, `pdf`, `index`).

## Couverture mesurée

Inventaire : 169 sites d'appel d'un état (`P.etat`, `P.ticket`, `P.badge`, `P.planche`) dans les sources de la maquette ; 167 sites `P.tableau` (corps de tableau, toujours imprimés à l'intérieur d'un état).

**États atteints : 156 / 169 sites (92 %).** Sites `P.tableau` traversés : 146 / 167 (87 %). Un site peut produire plusieurs états (variantes d'intitulé) ; un état n'est compté qu'une fois par site.

| Module (fichier source) | Sites d'état | Atteints | Taux |
|---|---|---|---|
| CFG | 6 | 5 | 83 % |
| DASH | 4 | 4 | 100 % |
| GED | 2 | 2 | 100 % |
| M1 | 6 | 5 | 83 % |
| M10 | 23 | 22 | 96 % |
| M11 | 6 | 6 | 100 % |
| M12 | 26 | 25 | 96 % |
| M13 | 6 | 6 | 100 % |
| M14 | 4 | 4 | 100 % |
| M2 | 7 | 5 | 71 % |
| M3 | 13 | 12 | 92 % |
| M4 | 12 | 12 | 100 % |
| M5 | 10 | 8 | 80 % |
| M6 | 14 | 12 | 86 % |
| M7 | 6 | 6 | 100 % |
| M8 | 10 | 8 | 80 % |
| M9 | 8 | 8 | 100 % |
| MECEF | 2 | 2 | 100 % |
| RAP | 2 | 2 | 100 % |
| SOCLE (_kit.js) | 1 | 1 | 100 % |
| SOCLE (ui.js) | 1 | 1 | 100 % |

## Sommaire par module

### M1 Patients & Dossier médical (7)

| État | Gabarit | Fichier |
|---|---|---|
| Ordonnance | A4 portrait | [`specimens/M1-patients-dossier-medical/m1-documents-ordonnance.pdf`](specimens/M1-patients-dossier-medical/m1-documents-ordonnance.pdf) |
| État d’avancement de la numérisation | A4 portrait | [`specimens/M1-patients-dossier-medical/m1-numerisation-etat-d-avancement-de-la-numerisation.pdf`](specimens/M1-patients-dossier-medical/m1-numerisation-etat-d-avancement-de-la-numerisation.pdf) |
| Fiche patient | A4 portrait | [`specimens/M1-patients-dossier-medical/m1-patient-profil-fiche-patient.pdf`](specimens/M1-patients-dossier-medical/m1-patient-profil-fiche-patient.pdf) |
| Fiche patient | A4 portrait | [`specimens/M1-patients-dossier-medical/m1-patients-fiche-patient.pdf`](specimens/M1-patients-dossier-medical/m1-patients-fiche-patient.pdf) |
| CERTIFICAT MÉDICAL DE NON CONTRE-INDICATION AUX ACTIVITÉS PHYSIQUES ET SPORTIVES | A4 portrait | [`specimens/M1-patients-dossier-medical/m1-pieces-certificat-medical-de-non-contre-indication-aux-activites-ph.pdf`](specimens/M1-patients-dossier-medical/m1-pieces-certificat-medical-de-non-contre-indication-aux-activites-ph.pdf) |
| CERTIFICAT MÉDICAL PRÉNUPTIAL | A4 portrait | [`specimens/M1-patients-dossier-medical/m1-pieces-certificat-medical-prenuptial.pdf`](specimens/M1-patients-dossier-medical/m1-pieces-certificat-medical-prenuptial.pdf) |
| FICHE DE RÉFÉRENCE | A4 portrait | [`specimens/M1-patients-dossier-medical/m1-reference-fiche-de-reference.pdf`](specimens/M1-patients-dossier-medical/m1-reference-fiche-de-reference.pdf) |

### M2 Consultations & prescriptions (3)

| État | Gabarit | Fichier |
|---|---|---|
| DOSSIER DE CONSULTATION | A4 portrait | [`specimens/M2-consultations-prescriptions/m2-dossiers-consultation-dossier-de-consultation.pdf`](specimens/M2-consultations-prescriptions/m2-dossiers-consultation-dossier-de-consultation.pdf) |
| Ordonnance médicale | A4 portrait | [`specimens/M2-consultations-prescriptions/m2-ordonnances-ordonnance-medicale.pdf`](specimens/M2-consultations-prescriptions/m2-ordonnances-ordonnance-medicale.pdf) |
| Tableau de morbidité | A4 portrait | [`specimens/M2-consultations-prescriptions/m2-pathologies-tableau-de-morbidite.pdf`](specimens/M2-consultations-prescriptions/m2-pathologies-tableau-de-morbidite.pdf) |

### M2 Imagerie médicale (5)

| État | Gabarit | Fichier |
|---|---|---|
| ÉCHOGRAPHIE PELVIENNE | A4 portrait | [`specimens/M2-imagerie-medicale/m2-imagerie-echographie-pelvienne.pdf`](specimens/M2-imagerie-medicale/m2-imagerie-echographie-pelvienne.pdf) |
| IRM DU RACHIS LOMBAIRE | A4 portrait | [`specimens/M2-imagerie-medicale/m2-imagerie-irm-irm-du-rachis-lombaire.pdf`](specimens/M2-imagerie-medicale/m2-imagerie-irm-irm-du-rachis-lombaire.pdf) |
| MAMMOGRAPHIE BILATÉRALE DE DÉPISTAGE | A4 portrait | [`specimens/M2-imagerie-medicale/m2-imagerie-mammographie-mammographie-bilaterale-de-depistage.pdf`](specimens/M2-imagerie-medicale/m2-imagerie-mammographie-mammographie-bilaterale-de-depistage.pdf) |
| RADIOGRAPHIE D’UN MEMBRE | A4 portrait | [`specimens/M2-imagerie-medicale/m2-imagerie-radiographie-radiographie-d-un-membre.pdf`](specimens/M2-imagerie-medicale/m2-imagerie-radiographie-radiographie-d-un-membre.pdf) |
| SCANNER CÉRÉBRAL | A4 portrait | [`specimens/M2-imagerie-medicale/m2-imagerie-scanner-scanner-cerebral.pdf`](specimens/M2-imagerie-medicale/m2-imagerie-scanner-scanner-cerebral.pdf) |

### M2 RDV, Visites & Consultations (1)

| État | Gabarit | Fichier |
|---|---|---|
| Compte rendu de consultation | A4 portrait | [`specimens/M2-rdv-visites-consultations/m2-consultations-compte-rendu-de-consultation.pdf`](specimens/M2-rdv-visites-consultations/m2-consultations-compte-rendu-de-consultation.pdf) |

### M3 Hospitalisation (12)

| État | Gabarit | Fichier |
|---|---|---|
| Bon d’admission | A4 portrait | [`specimens/M3-hospitalisation/m3-admissions-bon-d-admission.pdf`](specimens/M3-hospitalisation/m3-admissions-bon-d-admission.pdf) |
| COMPTE RENDU OPÉRATOIRE | A4 portrait | [`specimens/M3-hospitalisation/m3-bloc-cro-compte-rendu-operatoire.pdf`](specimens/M3-hospitalisation/m3-bloc-cro-compte-rendu-operatoire.pdf) |
| BON DE PANSEMENT | A4 portrait | [`specimens/M3-hospitalisation/m3-bons-pansements-bon-de-pansement.pdf`](specimens/M3-hospitalisation/m3-bons-pansements-bon-de-pansement.pdf) |
| Plan d’occupation des lits | A4 portrait | [`specimens/M3-hospitalisation/m3-chambres-plan-d-occupation-des-lits.pdf`](specimens/M3-hospitalisation/m3-chambres-plan-d-occupation-des-lits.pdf) |
| CONSULTATION PRÉ-ANESTHÉSIQUE | A4 portrait | [`specimens/M3-hospitalisation/m3-cpa-consultation-pre-anesthesique.pdf`](specimens/M3-hospitalisation/m3-cpa-consultation-pre-anesthesique.pdf) |
| COMPTE RENDU D’ANESTHÉSIE | A4 portrait | [`specimens/M3-hospitalisation/m3-cr-anesthesie-compte-rendu-d-anesthesie.pdf`](specimens/M3-hospitalisation/m3-cr-anesthesie-compte-rendu-d-anesthesie.pdf) |
| Feuille de température | A4 portrait | [`specimens/M3-hospitalisation/m3-feuille-temperature-feuille-de-temperature.pdf`](specimens/M3-hospitalisation/m3-feuille-temperature-feuille-de-temperature.pdf) |
| Feuille de mise en observation | A4 portrait | [`specimens/M3-hospitalisation/m3-observation-feuille-de-mise-en-observation.pdf`](specimens/M3-hospitalisation/m3-observation-feuille-de-mise-en-observation.pdf) |
| RAPPORT MÉDICAL | A4 portrait | [`specimens/M3-hospitalisation/m3-rapport-rapport-medical.pdf`](specimens/M3-hospitalisation/m3-rapport-rapport-medical.pdf) |
| Feuille de soins | A4 portrait | [`specimens/M3-hospitalisation/m3-soins-feuille-de-soins.pdf`](specimens/M3-hospitalisation/m3-soins-feuille-de-soins.pdf) |
| Sortie contre avis médical | A4 portrait | [`specimens/M3-hospitalisation/m3-sortie-avis-medical-sortie-contre-avis-medical.pdf`](specimens/M3-hospitalisation/m3-sortie-avis-medical-sortie-contre-avis-medical.pdf) |
| Bon de sortie d’hospitalisation | A4 portrait | [`specimens/M3-hospitalisation/m3-sorties-bon-de-sortie-d-hospitalisation.pdf`](specimens/M3-hospitalisation/m3-sorties-bon-de-sortie-d-hospitalisation.pdf) |

### M4 Maternité, Naissances & Décès (12)

| État | Gabarit | Fichier |
|---|---|---|
| Fiche d’accouchement | A4 portrait | [`specimens/M4-maternite-naissances-deces/m4-accouchements-fiche-d-accouchement.pdf`](specimens/M4-maternite-naissances-deces/m4-accouchements-fiche-d-accouchement.pdf) |
| CERTIFICAT DE REPOS | A4 portrait | [`specimens/M4-maternite-naissances-deces/m4-accouchements-certificat-de-repos.pdf`](specimens/M4-maternite-naissances-deces/m4-accouchements-certificat-de-repos.pdf) |
| Carte maternelle — suivi CPN | A4 portrait | [`specimens/M4-maternite-naissances-deces/m4-cpn-carte-maternelle-suivi-cpn.pdf`](specimens/M4-maternite-naissances-deces/m4-cpn-carte-maternelle-suivi-cpn.pdf) |
| Consultation post-natale | A4 portrait | [`specimens/M4-maternite-naissances-deces/m4-cpon-consultation-post-natale.pdf`](specimens/M4-maternite-naissances-deces/m4-cpon-consultation-post-natale.pdf) |
| Déclaration de décès | A4 portrait | [`specimens/M4-maternite-naissances-deces/m4-deces-declaration-de-deces.pdf`](specimens/M4-maternite-naissances-deces/m4-deces-declaration-de-deces.pdf) |
| Volet nouveau-né | A4 portrait | [`specimens/M4-maternite-naissances-deces/m4-dossier-bebe-volet-nouveau-ne.pdf`](specimens/M4-maternite-naissances-deces/m4-dossier-bebe-volet-nouveau-ne.pdf) |
| Dossier obstétrical | A4 portrait | [`specimens/M4-maternite-naissances-deces/m4-dossier-obstetrical-dossier-obstetrical.pdf`](specimens/M4-maternite-naissances-deces/m4-dossier-obstetrical-dossier-obstetrical.pdf) |
| Fiche de suivi de grossesse | A4 portrait | [`specimens/M4-maternite-naissances-deces/m4-maternite-fiche-de-suivi-de-grossesse.pdf`](specimens/M4-maternite-naissances-deces/m4-maternite-fiche-de-suivi-de-grossesse.pdf) |
| Attestation de naissance | A4 portrait | [`specimens/M4-maternite-naissances-deces/m4-naissances-attestation-de-naissance.pdf`](specimens/M4-maternite-naissances-deces/m4-naissances-attestation-de-naissance.pdf) |
| PARTOGRAPHIE | A4 portrait | [`specimens/M4-maternite-naissances-deces/m4-partogramme-partographie.pdf`](specimens/M4-maternite-naissances-deces/m4-partogramme-partographie.pdf) |
| Fiche de planification familiale | A4 portrait | [`specimens/M4-maternite-naissances-deces/m4-planification-fiche-de-planification-familiale.pdf`](specimens/M4-maternite-naissances-deces/m4-planification-fiche-de-planification-familiale.pdf) |
| Registre SONUB / SONUC — fiche d’urgence | A4 portrait | [`specimens/M4-maternite-naissances-deces/m4-sonu-registre-sonub-sonuc-fiche-d-urgence.pdf`](specimens/M4-maternite-naissances-deces/m4-sonu-registre-sonub-sonuc-fiche-d-urgence.pdf) |

### M5 Laboratoire (8)

| État | Gabarit | Fichier |
|---|---|---|
| Tarifs des analyses de laboratoire | A4 portrait | [`specimens/M5-laboratoire/m5-catalogue-tarifs-des-analyses-de-laboratoire.pdf`](specimens/M5-laboratoire/m5-catalogue-tarifs-des-analyses-de-laboratoire.pdf) |
| Bon de prélèvement | A4 portrait | [`specimens/M5-laboratoire/m5-demandes-bon-de-prelevement.pdf`](specimens/M5-laboratoire/m5-demandes-bon-de-prelevement.pdf) |
| Résultat d’analyse de laboratoire | A4 portrait | [`specimens/M5-laboratoire/m5-impression-resultats-resultat-d-analyse-de-laboratoire.pdf`](specimens/M5-laboratoire/m5-impression-resultats-resultat-d-analyse-de-laboratoire.pdf) |
| Bulletin d’analyses bio-médicales | A4 portrait | [`specimens/M5-laboratoire/m5-prelevement-bulletin-d-analyses-bio-medicales.pdf`](specimens/M5-laboratoire/m5-prelevement-bulletin-d-analyses-bio-medicales.pdf) |
| Bon d’expression de besoins — Laboratoire | A4 portrait | [`specimens/M5-laboratoire/m5-reactifs-bon-d-expression-de-besoins-laboratoire.pdf`](specimens/M5-laboratoire/m5-reactifs-bon-d-expression-de-besoins-laboratoire.pdf) |
| Compte rendu | A4 portrait | [`specimens/M5-laboratoire/m5-resultats-compte-rendu.pdf`](specimens/M5-laboratoire/m5-resultats-compte-rendu.pdf) |
| Activité du laboratoire d’analyses biomédicales | A4 portrait | [`specimens/M5-laboratoire/m5-stats-activite-du-laboratoire-d-analyses-biomedicales.pdf`](specimens/M5-laboratoire/m5-stats-activite-du-laboratoire-d-analyses-biomedicales.pdf) |
| Référentiel des valeurs de référence | A4 portrait | [`specimens/M5-laboratoire/m5-valeurs-reference-referentiel-des-valeurs-de-reference.pdf`](specimens/M5-laboratoire/m5-valeurs-reference-referentiel-des-valeurs-de-reference.pdf) |

### M6 Pharmacie & Stocks (14)

| État | Gabarit | Fichier |
|---|---|---|
| Étiquettes produits | A4 portrait | [`specimens/M6-pharmacie-stocks/m6-etiquetage-etiquettes-produits.pdf`](specimens/M6-pharmacie-stocks/m6-etiquetage-etiquettes-produits.pdf) |
| Bordereau de reprise du stock initial | A4 portrait | [`specimens/M6-pharmacie-stocks/m6-import-grand-stock-bordereau-de-reprise-du-stock-initial.pdf`](specimens/M6-pharmacie-stocks/m6-import-grand-stock-bordereau-de-reprise-du-stock-initial.pdf) |
| État des produits périmés | A4 portrait | [`specimens/M6-pharmacie-stocks/m6-lots-etat-des-produits-perimes.pdf`](specimens/M6-pharmacie-stocks/m6-lots-etat-des-produits-perimes.pdf) |
| Fiche de lot | A4 portrait | [`specimens/M6-pharmacie-stocks/m6-lots-fiche-de-lot.pdf`](specimens/M6-pharmacie-stocks/m6-lots-fiche-de-lot.pdf) |
| Constat de pertes et casses | A4 portrait | [`specimens/M6-pharmacie-stocks/m6-pertes-constat-de-pertes-et-casses.pdf`](specimens/M6-pharmacie-stocks/m6-pertes-constat-de-pertes-et-casses.pdf) |
| Stock restant à la pharmacie | A4 portrait | [`specimens/M6-pharmacie-stocks/m6-point-stock-stock-restant-a-la-pharmacie.pdf`](specimens/M6-pharmacie-stocks/m6-point-stock-stock-restant-a-la-pharmacie.pdf) |
| Point détaillé des ventes | A4 portrait | [`specimens/M6-pharmacie-stocks/m6-point-ventes-point-detaille-des-ventes.pdf`](specimens/M6-pharmacie-stocks/m6-point-ventes-point-detaille-des-ventes.pdf) |
| Point global des ventes | A4 portrait | [`specimens/M6-pharmacie-stocks/m6-point-ventes-point-global-des-ventes.pdf`](specimens/M6-pharmacie-stocks/m6-point-ventes-point-global-des-ventes.pdf) |
| Fiche article | A4 portrait | [`specimens/M6-pharmacie-stocks/m6-produits-fiche-article.pdf`](specimens/M6-pharmacie-stocks/m6-produits-fiche-article.pdf) |
| État du stock détail (pharmacie d’urgence) | A4 portrait | [`specimens/M6-pharmacie-stocks/m6-stock-detail-etat-du-stock-detail-pharmacie-d-urgence.pdf`](specimens/M6-pharmacie-stocks/m6-stock-detail-etat-du-stock-detail-pharmacie-d-urgence.pdf) |
| État du stock gros (magasin central) | A4 portrait | [`specimens/M6-pharmacie-stocks/m6-stock-gros-etat-du-stock-gros-magasin-central.pdf`](specimens/M6-pharmacie-stocks/m6-stock-gros-etat-du-stock-gros-magasin-central.pdf) |
| Registre des transferts gros → détail | A4 portrait | [`specimens/M6-pharmacie-stocks/m6-transferts-registre-des-transferts-gros-detail.pdf`](specimens/M6-pharmacie-stocks/m6-transferts-registre-des-transferts-gros-detail.pdf) |
| Bon de transfert de stock | A4 portrait | [`specimens/M6-pharmacie-stocks/m6-transferts-bon-de-transfert-de-stock.pdf`](specimens/M6-pharmacie-stocks/m6-transferts-bon-de-transfert-de-stock.pdf) |
| État détaillé des articles transférés | A4 portrait | [`specimens/M6-pharmacie-stocks/m6-transferts-etat-detaille-des-articles-transferes.pdf`](specimens/M6-pharmacie-stocks/m6-transferts-etat-detaille-des-articles-transferes.pdf) |

### M7 Achats & Fournisseurs (7)

| État | Gabarit | Fichier |
|---|---|---|
| Bon d’expression de besoins | A4 portrait | [`specimens/M7-achats-fournisseurs/m7-besoins-bon-d-expression-de-besoins.pdf`](specimens/M7-achats-fournisseurs/m7-besoins-bon-d-expression-de-besoins.pdf) |
| Bon de commande | A4 portrait | [`specimens/M7-achats-fournisseurs/m7-commandes-bon-de-commande.pdf`](specimens/M7-achats-fournisseurs/m7-commandes-bon-de-commande.pdf) |
| État des écarts de livraison | A4 portrait | [`specimens/M7-achats-fournisseurs/m7-ecarts-etat-des-ecarts-de-livraison.pdf`](specimens/M7-achats-fournisseurs/m7-ecarts-etat-des-ecarts-de-livraison.pdf) |
| Fiche fournisseur | A4 portrait | [`specimens/M7-achats-fournisseurs/m7-fournisseurs-fiche-fournisseur.pdf`](specimens/M7-achats-fournisseurs/m7-fournisseurs-fiche-fournisseur.pdf) |
| Bon de livraison | A4 portrait | [`specimens/M7-achats-fournisseurs/m7-livraisons-bon-de-livraison.pdf`](specimens/M7-achats-fournisseurs/m7-livraisons-bon-de-livraison.pdf) |
| PROCÈS-VERBAL DE RÉCEPTION | A4 portrait | [`specimens/M7-achats-fournisseurs/m7-pv-reception-consommables-proces-verbal-de-reception.pdf`](specimens/M7-achats-fournisseurs/m7-pv-reception-consommables-proces-verbal-de-reception.pdf) |
| PROCÈS-VERBAL DE RÉCEPTION | A4 portrait | [`specimens/M7-achats-fournisseurs/m7-pv-reception-reactifs-proces-verbal-de-reception.pdf`](specimens/M7-achats-fournisseurs/m7-pv-reception-reactifs-proces-verbal-de-reception.pdf) |

### M8 Facturation & Caisse (9)

| État | Gabarit | Fichier |
|---|---|---|
| État de caisse journalier | A4 portrait | [`specimens/M8-facturation-caisse/m8-caisse-etat-de-caisse-journalier.pdf`](specimens/M8-facturation-caisse/m8-caisse-etat-de-caisse-journalier.pdf) |
| Reçu de paiement | A4 portrait | [`specimens/M8-facturation-caisse/m8-caisse-recu-de-paiement.pdf`](specimens/M8-facturation-caisse/m8-caisse-recu-de-paiement.pdf) |
| Ticket de caisse | ticket 80 mm | [`specimens/M8-facturation-caisse/m8-facturation-ticket-de-caisse.pdf`](specimens/M8-facturation-caisse/m8-facturation-ticket-de-caisse.pdf) |
| FACTURE D’AVOIR | A4 portrait | [`specimens/M8-facturation-caisse/m8-facture-avoir-facture-d-avoir.pdf`](specimens/M8-facturation-caisse/m8-facture-avoir-facture-d-avoir.pdf) |
| Facture normalisée | A4 portrait | [`specimens/M8-facturation-caisse/m8-factures-facture-normalisee.pdf`](specimens/M8-facturation-caisse/m8-factures-facture-normalisee.pdf) |
| Inventaire de caisse — journalière | A4 portrait | [`specimens/M8-facturation-caisse/m8-operations-inventaire-de-caisse-journaliere.pdf`](specimens/M8-facturation-caisse/m8-operations-inventaire-de-caisse-journaliere.pdf) |
| Reçu de paiement | A4 portrait | [`specimens/M8-facturation-caisse/m8-paiements-recu-de-paiement.pdf`](specimens/M8-facturation-caisse/m8-paiements-recu-de-paiement.pdf) |
| État des recettes | A4 portrait | [`specimens/M8-facturation-caisse/m8-recettes-etat-des-recettes.pdf`](specimens/M8-facturation-caisse/m8-recettes-etat-des-recettes.pdf) |
| Facture normalisée | A4 portrait | [`specimens/M8-facturation-caisse/m8-reliquats-facture-normalisee.pdf`](specimens/M8-facturation-caisse/m8-reliquats-facture-normalisee.pdf) |

### M9 Assurances & Créances (10)

| État | Gabarit | Fichier |
|---|---|---|
| Attestation de prise en charge | A4 portrait | [`specimens/M9-assurances-creances/m9-assures-attestation-de-prise-en-charge.pdf`](specimens/M9-assurances-creances/m9-assures-attestation-de-prise-en-charge.pdf) |
| Fiche compagnie d’assurance | A4 portrait | [`specimens/M9-assurances-creances/m9-compagnies-fiche-compagnie-d-assurance.pdf`](specimens/M9-assurances-creances/m9-compagnies-fiche-compagnie-d-assurance.pdf) |
| assureurs | A4 portrait | [`specimens/M9-assurances-creances/m9-compagnies-assureurs.pdf`](specimens/M9-assurances-creances/m9-compagnies-assureurs.pdf) |
| Sélection — compagnies | A4 portrait | [`specimens/M9-assurances-creances/m9-compagnies-selection-compagnies.pdf`](specimens/M9-assurances-creances/m9-compagnies-selection-compagnies.pdf) |
| Convention de prise en charge | A4 portrait | [`specimens/M9-assurances-creances/m9-conventions-convention-de-prise-en-charge.pdf`](specimens/M9-assurances-creances/m9-conventions-convention-de-prise-en-charge.pdf) |
| État des créances — tiers payeurs | A4 portrait | [`specimens/M9-assurances-creances/m9-creances-etat-des-creances-tiers-payeurs.pdf`](specimens/M9-assurances-creances/m9-creances-etat-des-creances-tiers-payeurs.pdf) |
| FACTURE MÈRE — AFRICAINE DES ASSURANCES | A4 portrait | [`specimens/M9-assurances-creances/m9-facture-mere-facture-mere-africaine-des-assurances.pdf`](specimens/M9-assurances-creances/m9-facture-mere-facture-mere-africaine-des-assurances.pdf) |
| Relevé des prestations de la clinique | A4 portrait | [`specimens/M9-assurances-creances/m9-factures-assureur-releve-des-prestations-de-la-clinique.pdf`](specimens/M9-assurances-creances/m9-factures-assureur-releve-des-prestations-de-la-clinique.pdf) |
| Facture — prestations de santé | A4 portrait | [`specimens/M9-assurances-creances/m9-factures-assureur-facture-prestations-de-sante.pdf`](specimens/M9-assurances-creances/m9-factures-assureur-facture-prestations-de-sante.pdf) |
| Lettre de relance | A4 portrait | [`specimens/M9-assurances-creances/m9-relances-lettre-de-relance.pdf`](specimens/M9-assurances-creances/m9-relances-lettre-de-relance.pdf) |

### M10 Ressources humaines (22)

| État | Gabarit | Fichier |
|---|---|---|
| État de la prise en charge du personnel | A4 portrait | [`specimens/M10-ressources-humaines/m10-assurance-personnel-etat-de-la-prise-en-charge-du-personnel.pdf`](specimens/M10-ressources-humaines/m10-assurance-personnel-etat-de-la-prise-en-charge-du-personnel.pdf) |
| Badge — DAKO Marcelle | carte CR80 (recto et verso) | [`specimens/M10-ressources-humaines/m10-badges-badge-dako-marcelle.pdf`](specimens/M10-ressources-humaines/m10-badges-badge-dako-marcelle.pdf) |
| Badge — SOSSA Narcisse | carte CR80 (recto et verso) | [`specimens/M10-ressources-humaines/m10-badges-impression-badge-sossa-narcisse.pdf`](specimens/M10-ressources-humaines/m10-badges-impression-badge-sossa-narcisse.pdf) |
| Planche de badges | A4 portrait | [`specimens/M10-ressources-humaines/m10-badges-impression-planche-de-badges.pdf`](specimens/M10-ressources-humaines/m10-badges-impression-planche-de-badges.pdf) |
| Décision de congé | A4 portrait | [`specimens/M10-ressources-humaines/m10-conges-decision-de-conge.pdf`](specimens/M10-ressources-humaines/m10-conges-decision-de-conge.pdf) |
| Contrat de travail | A4 portrait | [`specimens/M10-ressources-humaines/m10-contrats-contrat-de-travail.pdf`](specimens/M10-ressources-humaines/m10-contrats-contrat-de-travail.pdf) |
| Fiche d’évaluation du mois de JUILLET 2026 | A4 portrait | [`specimens/M10-ressources-humaines/m10-evaluations-fiche-d-evaluation-du-mois-de-juillet-2026.pdf`](specimens/M10-ressources-humaines/m10-evaluations-fiche-d-evaluation-du-mois-de-juillet-2026.pdf) |
| Liste de collecte — participation du personnel | A4 portrait | [`specimens/M10-ressources-humaines/m10-evenements-liste-de-collecte-participation-du-personnel.pdf`](specimens/M10-ressources-humaines/m10-evenements-liste-de-collecte-participation-du-personnel.pdf) |
| DESCRIPTION DE POSTE | A4 portrait | [`specimens/M10-ressources-humaines/m10-fiches-poste-description-de-poste.pdf`](specimens/M10-ressources-humaines/m10-fiches-poste-description-de-poste.pdf) |
| Ordre de mission | A4 portrait | [`specimens/M10-ressources-humaines/m10-missions-ordre-de-mission.pdf`](specimens/M10-ressources-humaines/m10-missions-ordre-de-mission.pdf) |
| État des participations du personnel | A4 portrait | [`specimens/M10-ressources-humaines/m10-participations-etat-des-participations-du-personnel.pdf`](specimens/M10-ressources-humaines/m10-participations-etat-des-participations-du-personnel.pdf) |
| Reçu de participation | A4 portrait | [`specimens/M10-ressources-humaines/m10-participations-recu-de-participation.pdf`](specimens/M10-ressources-humaines/m10-participations-recu-de-participation.pdf) |
| Fiche individuelle de l’agent | A4 portrait | [`specimens/M10-ressources-humaines/m10-personnel-fiche-individuelle-de-l-agent.pdf`](specimens/M10-ressources-humaines/m10-personnel-fiche-individuelle-de-l-agent.pdf) |
| Planning de garde et de permanence | A4 portrait | [`specimens/M10-ressources-humaines/m10-planning-planning-de-garde-et-de-permanence.pdf`](specimens/M10-ressources-humaines/m10-planning-planning-de-garde-et-de-permanence.pdf) |
| État de rémunération — prestataire externe | A4 portrait | [`specimens/M10-ressources-humaines/m10-prestataires-etat-de-remuneration-prestataire-externe.pdf`](specimens/M10-ressources-humaines/m10-prestataires-etat-de-remuneration-prestataire-externe.pdf) |
| Note de service — primes diverses | A4 portrait | [`specimens/M10-ressources-humaines/m10-primes-note-de-service-primes-diverses.pdf`](specimens/M10-ressources-humaines/m10-primes-note-de-service-primes-diverses.pdf) |
| État des primes diverses | A4 portrait | [`specimens/M10-ressources-humaines/m10-primes-etat-des-primes-diverses.pdf`](specimens/M10-ressources-humaines/m10-primes-etat-des-primes-diverses.pdf) |
| Notification de sanction | A4 portrait | [`specimens/M10-ressources-humaines/m10-sanctions-notification-de-sanction.pdf`](specimens/M10-ressources-humaines/m10-sanctions-notification-de-sanction.pdf) |
| Planning des agents de sécurité et d’entretien | A4 portrait | [`specimens/M10-ressources-humaines/m10-securite-entretien-planning-des-agents-de-securite-et-d-entretien.pdf`](specimens/M10-ressources-humaines/m10-securite-entretien-planning-des-agents-de-securite-et-d-entretien.pdf) |
| État des gardes effectuées | A4 portrait | [`specimens/M10-ressources-humaines/m10-stats-gardes-etat-des-gardes-effectuees.pdf`](specimens/M10-ressources-humaines/m10-stats-gardes-etat-des-gardes-effectuees.pdf) |
| Statistiques des permanences | A4 portrait | [`specimens/M10-ressources-humaines/m10-stats-permanences-statistiques-des-permanences.pdf`](specimens/M10-ressources-humaines/m10-stats-permanences-statistiques-des-permanences.pdf) |
| Taux de présence par service | A4 portrait | [`specimens/M10-ressources-humaines/m10-stats-presence-taux-de-presence-par-service.pdf`](specimens/M10-ressources-humaines/m10-stats-presence-taux-de-presence-par-service.pdf) |

### M11 Paie & Primes (9)

| État | Gabarit | Fichier |
|---|---|---|
| Demande d’avance sur salaire | A4 portrait | [`specimens/M11-paie-primes/m11-avances-demande-d-avance-sur-salaire.pdf`](specimens/M11-paie-primes/m11-avances-demande-d-avance-sur-salaire.pdf) |
| Journal de paie | A4 portrait | [`specimens/M11-paie-primes/m11-calcul-journal-de-paie.pdf`](specimens/M11-paie-primes/m11-calcul-journal-de-paie.pdf) |
| Bulletin de paie | A4 portrait | [`specimens/M11-paie-primes/m11-calcul-bulletin-de-paie.pdf`](specimens/M11-paie-primes/m11-calcul-bulletin-de-paie.pdf) |
| État de l’impôt sur les traitements et salaires | A4 portrait | [`specimens/M11-paie-primes/m11-cotisations-etat-de-l-impot-sur-les-traitements-et-salaires.pdf`](specimens/M11-paie-primes/m11-cotisations-etat-de-l-impot-sur-les-traitements-et-salaires.pdf) |
| État des cotisations CNSS | A4 portrait | [`specimens/M11-paie-primes/m11-cotisations-etat-des-cotisations-cnss.pdf`](specimens/M11-paie-primes/m11-cotisations-etat-des-cotisations-cnss.pdf) |
| État des redevances ORTB | A4 portrait | [`specimens/M11-paie-primes/m11-cotisations-etat-des-redevances-ortb.pdf`](specimens/M11-paie-primes/m11-cotisations-etat-des-redevances-ortb.pdf) |
| État du versement patronal de solidarité | A4 portrait | [`specimens/M11-paie-primes/m11-cotisations-etat-du-versement-patronal-de-solidarite.pdf`](specimens/M11-paie-primes/m11-cotisations-etat-du-versement-patronal-de-solidarite.pdf) |
| État des redevances ORTB | A4 portrait | [`specimens/M11-paie-primes/m11-ortb-etat-des-redevances-ortb.pdf`](specimens/M11-paie-primes/m11-ortb-etat-des-redevances-ortb.pdf) |
| Journal de paie — validation | A4 portrait | [`specimens/M11-paie-primes/m11-validation-journal-de-paie-validation.pdf`](specimens/M11-paie-primes/m11-validation-journal-de-paie-validation.pdf) |

### M12 Comptabilité SYSCOHADA (23)

| État | Gabarit | Fichier |
|---|---|---|
| Balance analytique | A4 portrait | [`specimens/M12-comptabilite-syscohada/m12-analytique-balance-analytique.pdf`](specimens/M12-comptabilite-syscohada/m12-analytique-balance-analytique.pdf) |
| Balance générale des comptes | A4 portrait | [`specimens/M12-comptabilite-syscohada/m12-balance-balance-generale-des-comptes.pdf`](specimens/M12-comptabilite-syscohada/m12-balance-balance-generale-des-comptes.pdf) |
| Balance âgée des comptes de tiers | A4 portrait | [`specimens/M12-comptabilite-syscohada/m12-balance-balance-agee-des-comptes-de-tiers.pdf`](specimens/M12-comptabilite-syscohada/m12-balance-balance-agee-des-comptes-de-tiers.pdf) |
| État de rapprochement bancaire | A4 portrait | [`specimens/M12-comptabilite-syscohada/m12-banques-etat-de-rapprochement-bancaire.pdf`](specimens/M12-comptabilite-syscohada/m12-banques-etat-de-rapprochement-bancaire.pdf) |
| Compte de résultat — exercice 2025 | A4 portrait | [`specimens/M12-comptabilite-syscohada/m12-baseline-2025-compte-de-resultat-exercice-2025.pdf`](specimens/M12-comptabilite-syscohada/m12-baseline-2025-compte-de-resultat-exercice-2025.pdf) |
| Compte de résultat | A4 portrait | [`specimens/M12-comptabilite-syscohada/m12-compte-resultat-compte-de-resultat.pdf`](specimens/M12-comptabilite-syscohada/m12-compte-resultat-compte-de-resultat.pdf) |
| État des dépenses de trésorerie | A4 portrait | [`specimens/M12-comptabilite-syscohada/m12-depenses-etat-des-depenses-de-tresorerie.pdf`](specimens/M12-comptabilite-syscohada/m12-depenses-etat-des-depenses-de-tresorerie.pdf) |
| Pièce de dépense | A4 portrait | [`specimens/M12-comptabilite-syscohada/m12-depenses-piece-de-depense.pdf`](specimens/M12-comptabilite-syscohada/m12-depenses-piece-de-depense.pdf) |
| Justificatif de paiement — obligation fiscale | A4 portrait | [`specimens/M12-comptabilite-syscohada/m12-echeances-justificatif-de-paiement-obligation-fiscale.pdf`](specimens/M12-comptabilite-syscohada/m12-echeances-justificatif-de-paiement-obligation-fiscale.pdf) |
| Bilan | A4 portrait | [`specimens/M12-comptabilite-syscohada/m12-etats-financiers-bilan.pdf`](specimens/M12-comptabilite-syscohada/m12-etats-financiers-bilan.pdf) |
| Compte de résultat | A4 portrait | [`specimens/M12-comptabilite-syscohada/m12-etats-financiers-compte-de-resultat.pdf`](specimens/M12-comptabilite-syscohada/m12-etats-financiers-compte-de-resultat.pdf) |
| Tableau des flux de trésorerie | A4 portrait | [`specimens/M12-comptabilite-syscohada/m12-etats-financiers-tableau-des-flux-de-tresorerie.pdf`](specimens/M12-comptabilite-syscohada/m12-etats-financiers-tableau-des-flux-de-tresorerie.pdf) |
| NOTE 11 : DISPONIBILITÉS | A4 portrait | [`specimens/M12-comptabilite-syscohada/m12-etats-financiers-note-11-disponibilites.pdf`](specimens/M12-comptabilite-syscohada/m12-etats-financiers-note-11-disponibilites.pdf) |
| Fiche de synthèse des principaux indicateurs financiers | A4 portrait | [`specimens/M12-comptabilite-syscohada/m12-etats-financiers-fiche-de-synthese-des-principaux-indicateurs-fina.pdf`](specimens/M12-comptabilite-syscohada/m12-etats-financiers-fiche-de-synthese-des-principaux-indicateurs-fina.pdf) |
| Tableau des flux de trésorerie | A4 portrait | [`specimens/M12-comptabilite-syscohada/m12-flux-tresorerie-tableau-des-flux-de-tresorerie.pdf`](specimens/M12-comptabilite-syscohada/m12-flux-tresorerie-tableau-des-flux-de-tresorerie.pdf) |
| Grand livre | A4 portrait | [`specimens/M12-comptabilite-syscohada/m12-grand-livre-grand-livre.pdf`](specimens/M12-comptabilite-syscohada/m12-grand-livre-grand-livre.pdf) |
| Grand livre général | A4 portrait | [`specimens/M12-comptabilite-syscohada/m12-grand-livre-grand-livre-general.pdf`](specimens/M12-comptabilite-syscohada/m12-grand-livre-grand-livre-general.pdf) |
| Fiche d’immobilisation & plan d’amortissement | A4 portrait | [`specimens/M12-comptabilite-syscohada/m12-immobilisations-fiche-d-immobilisation-plan-d-amortissement.pdf`](specimens/M12-comptabilite-syscohada/m12-immobilisations-fiche-d-immobilisation-plan-d-amortissement.pdf) |
| Report des immobilisations à l’actif du bilan | A4 portrait | [`specimens/M12-comptabilite-syscohada/m12-immobilisations-report-des-immobilisations-a-l-actif-du-bilan.pdf`](specimens/M12-comptabilite-syscohada/m12-immobilisations-report-des-immobilisations-a-l-actif-du-bilan.pdf) |
| Journal comptable — Journal des achats | A4 portrait | [`specimens/M12-comptabilite-syscohada/m12-journaux-journal-comptable-journal-des-achats.pdf`](specimens/M12-comptabilite-syscohada/m12-journaux-journal-comptable-journal-des-achats.pdf) |
| Bilan d’ouverture — à-nouveaux | A4 portrait | [`specimens/M12-comptabilite-syscohada/m12-ouverture-bilan-d-ouverture-a-nouveaux.pdf`](specimens/M12-comptabilite-syscohada/m12-ouverture-bilan-d-ouverture-a-nouveaux.pdf) |
| Plan comptable SYSCOHADA | A4 portrait | [`specimens/M12-comptabilite-syscohada/m12-plan-comptable-plan-comptable-syscohada.pdf`](specimens/M12-comptabilite-syscohada/m12-plan-comptable-plan-comptable-syscohada.pdf) |
| Seuil de rentabilité | A4 portrait | [`specimens/M12-comptabilite-syscohada/m12-seuil-rentabilite-seuil-de-rentabilite.pdf`](specimens/M12-comptabilite-syscohada/m12-seuil-rentabilite-seuil-de-rentabilite.pdf) |

### M12 Gestion & trésorerie (2)

| État | Gabarit | Fichier |
|---|---|---|
| Besoin en fonds de roulement | A4 portrait | [`specimens/M12-gestion-tresorerie/m12-bfr-besoin-en-fonds-de-roulement.pdf`](specimens/M12-gestion-tresorerie/m12-bfr-besoin-en-fonds-de-roulement.pdf) |
| Coût à l’activité — marge sur consommables | A4 portrait | [`specimens/M12-gestion-tresorerie/m12-cout-activite-cout-a-l-activite-marge-sur-consommables.pdf`](specimens/M12-gestion-tresorerie/m12-cout-activite-cout-a-l-activite-marge-sur-consommables.pdf) |

### M13 Administration & Ambulance (6)

| État | Gabarit | Fichier |
|---|---|---|
| Fiche d’intervention — ambulance | A4 portrait | [`specimens/M13-administration-ambulance/m13-ambulance-fiche-d-intervention-ambulance.pdf`](specimens/M13-administration-ambulance/m13-ambulance-fiche-d-intervention-ambulance.pdf) |
| Registre du courrier | A4 portrait | [`specimens/M13-administration-ambulance/m13-courriers-registre-du-courrier.pdf`](specimens/M13-administration-ambulance/m13-courriers-registre-du-courrier.pdf) |
| Fiche de courrier | A4 portrait | [`specimens/M13-administration-ambulance/m13-courriers-fiche-de-courrier.pdf`](specimens/M13-administration-ambulance/m13-courriers-fiche-de-courrier.pdf) |
| Fiche d’équipement | A4 portrait | [`specimens/M13-administration-ambulance/m13-maintenance-fiche-d-equipement.pdf`](specimens/M13-administration-ambulance/m13-maintenance-fiche-d-equipement.pdf) |
| Plan annuel de travail | A4 portrait | [`specimens/M13-administration-ambulance/m13-plan-annuel-plan-annuel-de-travail.pdf`](specimens/M13-administration-ambulance/m13-plan-annuel-plan-annuel-de-travail.pdf) |
| Convocation à une réunion | A4 portrait | [`specimens/M13-administration-ambulance/m13-reunions-convocation-a-une-reunion.pdf`](specimens/M13-administration-ambulance/m13-reunions-convocation-a-une-reunion.pdf) |

### M14 Sécurité & Utilisateurs (4)

| État | Gabarit | Fichier |
|---|---|---|
| Journal d’audit | A4 portrait | [`specimens/M14-securite-utilisateurs/m14-audit-journal-d-audit.pdf`](specimens/M14-securite-utilisateurs/m14-audit-journal-d-audit.pdf) |
| Matrice des droits d’accès (RBAC) | A4 portrait | [`specimens/M14-securite-utilisateurs/m14-roles-matrice-des-droits-d-acces-rbac.pdf`](specimens/M14-securite-utilisateurs/m14-roles-matrice-des-droits-d-acces-rbac.pdf) |
| Journal des sauvegardes | A4 portrait | [`specimens/M14-securite-utilisateurs/m14-sauvegardes-journal-des-sauvegardes.pdf`](specimens/M14-securite-utilisateurs/m14-sauvegardes-journal-des-sauvegardes.pdf) |
| Fiche de compte utilisateur | A4 portrait | [`specimens/M14-securite-utilisateurs/m14-utilisateurs-fiche-de-compte-utilisateur.pdf`](specimens/M14-securite-utilisateurs/m14-utilisateurs-fiche-de-compte-utilisateur.pdf) |

### CFG Configuration Clinique (5)

| État | Gabarit | Fichier |
|---|---|---|
| Aperçu du papier à en-tête | A4 portrait | [`specimens/CFG-configuration-clinique/cfg-branding-apercu-du-papier-a-en-tete.pdf`](specimens/CFG-configuration-clinique/cfg-branding-apercu-du-papier-a-en-tete.pdf) |
| Répartition des secteurs de la clinique | A4 portrait | [`specimens/CFG-configuration-clinique/cfg-organisation-repartition-des-secteurs-de-la-clinique.pdf`](specimens/CFG-configuration-clinique/cfg-organisation-repartition-des-secteurs-de-la-clinique.pdf) |
| Organigramme de la Clinique NASSIERA TOO | A4 portrait | [`specimens/CFG-configuration-clinique/cfg-organisation-organigramme-de-la-clinique-nassiera-too.pdf`](specimens/CFG-configuration-clinique/cfg-organisation-organigramme-de-la-clinique-nassiera-too.pdf) |
| Matrice de traçabilité des règles métier | A4 portrait | [`specimens/CFG-configuration-clinique/cfg-regles-matrice-de-tracabilite-des-regles-metier.pdf`](specimens/CFG-configuration-clinique/cfg-regles-matrice-de-tracabilite-des-regles-metier.pdf) |
| Grille tarifaire des actes et prestations | A4 portrait | [`specimens/CFG-configuration-clinique/cfg-tarifs-grille-tarifaire-des-actes-et-prestations.pdf`](specimens/CFG-configuration-clinique/cfg-tarifs-grille-tarifaire-des-actes-et-prestations.pdf) |

### DASH Tableaux de bord par poste (1)

| État | Gabarit | Fichier |
|---|---|---|
| Situation du patient | A4 portrait | [`specimens/DASH-tableaux-de-bord-par-poste/dash-patient-situation-du-patient.pdf`](specimens/DASH-tableaux-de-bord-par-poste/dash-patient-situation-du-patient.pdf) |

### GED Gestion documentaire (2)

| État | Gabarit | Fichier |
|---|---|---|
| Bordereau d’archivage documentaire | A4 portrait | [`specimens/GED-gestion-documentaire/ged-archives-bordereau-d-archivage-documentaire.pdf`](specimens/GED-gestion-documentaire/ged-archives-bordereau-d-archivage-documentaire.pdf) |
| Fiche documentaire | A4 portrait | [`specimens/GED-gestion-documentaire/ged-bibliotheque-fiche-documentaire.pdf`](specimens/GED-gestion-documentaire/ged-bibliotheque-fiche-documentaire.pdf) |

### MECEF MECeF : Facture normalisée (2)

| État | Gabarit | Fichier |
|---|---|---|
| Avoir sur facture normalisée | A4 portrait | [`specimens/MECEF-mecef-facture-normalisee/mecef-avoirs-avoir-sur-facture-normalisee.pdf`](specimens/MECEF-mecef-facture-normalisee/mecef-avoirs-avoir-sur-facture-normalisee.pdf) |
| Facture de vente — normalisée | A4 portrait | [`specimens/MECEF-mecef-facture-normalisee/mecef-factures-facture-de-vente-normalisee.pdf`](specimens/MECEF-mecef-facture-normalisee/mecef-factures-facture-de-vente-normalisee.pdf) |

### PIL Pilotage & analyse (3)

| État | Gabarit | Fichier |
|---|---|---|
| Rapport d’activité — Direction | A4 portrait | [`specimens/PIL-pilotage-analyse/dash-direction-rapport-d-activite-direction.pdf`](specimens/PIL-pilotage-analyse/dash-direction-rapport-d-activite-direction.pdf) |
| Tableau de bord décisionnel | A4 portrait | [`specimens/PIL-pilotage-analyse/m12-tableau-decisionnel-tableau-de-bord-decisionnel.pdf`](specimens/PIL-pilotage-analyse/m12-tableau-decisionnel-tableau-de-bord-decisionnel.pdf) |
| Statistiques des hospitalisations | A4 portrait | [`specimens/PIL-pilotage-analyse/m3-stats-hospitalisations-statistiques-des-hospitalisations.pdf`](specimens/PIL-pilotage-analyse/m3-stats-hospitalisations-statistiques-des-hospitalisations.pdf) |

### RAP Rapports & Impression (2)

| État | Gabarit | Fichier |
|---|---|---|
| Point mensuel — par client | A4 portrait | [`specimens/RAP-rapports-impression/rapports-direction-point-mensuel-par-client.pdf`](specimens/RAP-rapports-impression/rapports-direction-point-mensuel-par-client.pdf) |
| Rapport d’activité | A4 portrait | [`specimens/RAP-rapports-impression/rapports-generateur-rapport-d-activite.pdf`](specimens/RAP-rapports-impression/rapports-generateur-rapport-d-activite.pdf) |

## Ce qui n'a pas pu être produit

Sites d'état de la maquette que l'exploration automatique n'a pas atteints (13). La raison générale est la même : l'état n'est offert qu'après un geste que l'exploration ne sait pas faire seule (saisie d'un formulaire à champs obligatoires, état métier particulier du jeu, sélection multiple, état déclenché par un événement ou par un rôle autre que l'administrateur) ou l'écran est fermé au profil du banc. Aucun fichier de l'application n'a été modifié pour les atteindre.

### CFG : 1 non atteint(s)

- `assets/js/modules/configuration.js:3338` (intitulé construit à l'exécution) : impression d'un certificat du registre : cause non vérifiée (probablement aucune ligne imprimable sur le jeu)

### M1 : 1 non atteint(s)

- `assets/js/modules/m1-patients.js:2304` « Bulletin d’analyses bio-médicales » : proposé après la saisie d'une demande d'analyses de patient externe, en fenêtre ; non rejoué

### M10 : 1 non atteint(s)

- `assets/js/modules/m10-rh.js:2462` « Note de service » : le clic sur « Imprimer la note » n'ouvre aucun aperçu sur le banc (cause non élucidée)

### M12 : 1 non atteint(s)

- `assets/js/modules/m12-comptabilite.js:2396` « Procès-verbal de clôture — exercice  » : exige une clôture en deux gestes (demande, puis validation Direction) après une pré-clôture sans brouillon ; le jeu porte des brouillons

### M2 : 2 non atteint(s)

- `assets/js/modules/m2-consultations.js:483` « Bulletin d’analyses bio-médicales » : exige une consultation portant des analyses prescrites ; non rejoué
- `assets/js/modules/m2-consultations.js:2902` « Ordonnance médicale » : code mort : `etatOrdonnanceAncienne` n'est appelée nulle part (l'ordonnance s'imprime par `etatOrdonnanceMedicale`)

### M3 : 1 non atteint(s)

- `assets/js/modules/m3-hospitalisation.js:3623` « FICHE DE DEMANDE D’EXAMEN » : le formulaire exige des examens cochés et l'urgence par examen : la saisie automatique est refusée (erreurs de formulaire)

### M5 : 2 non atteint(s)

- `assets/js/modules/m5-laboratoire.js:3446` « Bon de demande de sang » : activité Banque de sang fermée (cfg-modules) : écran inaccessible à tous les profils, administrateur compris
- `assets/js/modules/m5-laboratoire.js:3579` « Carte de donneur de sang » : activité Banque de sang fermée (cfg-modules) : écran inaccessible à tous les profils, administrateur compris

### M6 : 2 non atteint(s)

- `assets/js/modules/m6-stock.js:1808` « État d’inventaire » : exige une feuille d'inventaire comptée (registre vide sur le jeu) ; saisie de comptage non rejouée
- `assets/js/modules/m6-stock.js:2568` « Bon de sortie de stock — dispensation » : aucune création manuelle (RG-03) : le bon naît d'une dispensation, qui exige une ordonnance encaissée puis servie ; chaîne non rejouée

### M8 : 2 non atteint(s)

- `assets/js/modules/m8-facturation.js:1934` « Engagement de paiement » : exige un patient débiteur et la saisie d'un engagement de paiement ; non rejoué
- `assets/js/modules/m8-facturation.js:2120` (intitulé construit à l'exécution) : opération de remboursement à saisir (champs obligatoires) ; non rejouée

### Écrans non explorés

- `m5-donneurs` : non peinte (activité Banque de sang fermée)
- `plan-du-site` : non peinte
- `m5-banque-sang` : non peinte (activité Banque de sang fermée)

## Limites

- Les montants et les lignes sont ceux du jeu de démonstration, à la date du banc (16/08/2026) : un état peut sortir avec des zéros ou des tableaux vides quand le jeu n'a rien à cette date (l'arrêté de caisse du jour, par exemple). Rien n'est inventé pour le remplir.
- Un site d'impression peut produire plusieurs documents (selon le patient, la modalité, le mois) : seuls les premiers intitulés distincts sont gardés (au plus 6 par site).
- Les écrans sont explorés avec le profil administrateur : un état réservé à un autre profil par surcharge d'écran reste atteignable tant que l'écran s'ouvre à l'administrateur ; les écrans fermés à tous (activités désactivées) ne sont pas explorés.
- Les états de la maquette sont tous en A4 portrait, sauf le ticket de caisse (rouleau 80 mm) et le badge (carte CR80, recto et verso sur une feuille de 93,6 mm).
- La taille tient à Chrome, qui écrit la police Inter (variable) en Type 3 ; les objets identiques sont dédoublonnés après coup (pypdf), sans perte.

## Confidentialité

Le jeu de démonstration porte les noms du personnel de l'organigramme réel. Avant le PDF, une table de substitution déterministe remplace dans le texte de chaque état (noms et prénoms par jetons, y compris dans les identifiants de connexion, téléphones et numéros CNSS) par des identités fictives. Les noms de patients du jeu sont générés et sont conservés. L'en-tête légal de la clinique (dénomination, IFU, RCCM) est conservé tel quel : c'est la mise en page réelle des pièces. Aucune pièce ne porte de compte bancaire, de mot de passe ni de jeton.

**Contrôle fait** : relecture de la couche texte de 169 PDF avec `pdftotext -layout`, recherche de 70 jetons de noms réels (personnel, titulaires de l'organigramme, comptes), 88 téléphones et numéros CNSS réels, et des mots IBAN, RIB, mot de passe, jeton. Résultat : **aucune occurrence**.

Les salaires affichés (bulletins, états de paie) sont des valeurs de démonstration du jeu, non des salaires réels (voir `CLAUDE.md`, champs de test conservés au vidage).
