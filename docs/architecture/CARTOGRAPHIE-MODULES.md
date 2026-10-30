# Cartographie des modules

> **ENGENDRÉ** par `prototype_html/build/parite.js` depuis le manifeste de navigation de la maquette (`nav.js`) — ne pas éditer.
> Un **domaine** est un onglet du ruban ; une **rangée** regroupe des écrans d'un module ; une rangée **alias** réunit des écrans d'un autre module sans les dupliquer ; une rangée **secondaire** apporte des écrans canoniques à un module sans créer de second hub.

## Accueil

| Rangée | Module | Type | Écrans | Rôles d'origine |
|---|---|---|---|---|
| RDV, Visites & Consultations | M2 | canonique | 9 | reception, medecin, infirmier, dm, admin, direction |
| Patients & constantes | M1 | alias | 3 | tous |
| Courriers & orientation | M13 | alias | 2 | tous |
| Tarification & information patient | CFG | alias | 3 | tous |

## Soins

| Rangée | Module | Type | Écrans | Rôles d'origine |
|---|---|---|---|---|
| Patients & Dossier médical | M1 | canonique | 10 | * |
| Consultations & prescriptions | M2 | secondaire | 6 | reception, medecin, infirmier, dm, admin, direction |
| Imagerie médicale | M2 | secondaire | 8 | reception, medecin, infirmier, dm, admin, direction |
| Hospitalisation | M3 | canonique | 20 | medecin, infirmier, dm, admin, direction, reception |
| Maternité, Naissances & Décès | M4 | canonique | 14 | medecin, infirmier, dm, admin, direction |
| Laboratoire | M5 | canonique | 15 | laborantin, medecin, dm, admin, direction |

## Logistique

| Rangée | Module | Type | Écrans | Rôles d'origine |
|---|---|---|---|---|
| Pharmacie & Stocks | M6 | canonique | 17 | pharmacien, stock, da, comptable, medecin, admin, direction |
| Achats & Fournisseurs | M7 | canonique | 9 | stock, da, comptable, admin, direction |

## Financier

| Rangée | Module | Type | Écrans | Rôles d'origine |
|---|---|---|---|---|
| Facturation & Caisse | M8 | canonique | 11 | caissier, comptable, da, stock, dm, admin, direction |
| Assurances & Créances | M9 | canonique | 10 | caissier, comptable, da, admin, direction |
| MECeF — Facture normalisée | MECEF | canonique | 6 | caissier, comptable, da, admin, direction |
| Comptabilité SYSCOHADA | M12 | canonique | 19 | comptable, da, admin, direction |

## RH

| Rangée | Module | Type | Écrans | Rôles d'origine |
|---|---|---|---|---|
| Ressources humaines | M10 | canonique | 24 | rh, da, admin, direction |
| Paie & Primes | M11 | canonique | 9 | rh, da, comptable, admin, direction |

## Administration

| Rangée | Module | Type | Écrans | Rôles d'origine |
|---|---|---|---|---|
| Administration & Ambulance | M13 | canonique | 11 | agentadmin, da, admin, direction, ambulancier, assistant_comptable |
| Gestion documentaire | GED | canonique | 3 | agentadmin, da, admin, direction, comptable, assistant_comptable |
| Rapports & Impression | RAP | canonique | 4 | * |

## Système

| Rangée | Module | Type | Écrans | Rôles d'origine |
|---|---|---|---|---|
| Sécurité & Utilisateurs | M14 | canonique | 7 | admin, direction, da |
| Configuration Clinique | CFG | canonique | 18 | admin, da, direction |

## Pilotage

| Rangée | Module | Type | Écrans | Rôles d'origine |
|---|---|---|---|---|
| Pilotage & analyse | PIL | canonique | 13 | * |
| Gestion & trésorerie | M12 | secondaire | 2 | comptable, da, admin, direction |
| Tableaux de bord par poste | DASH | canonique | 20 | * |

## Matrice effective rôle × module

Cases : `V` voir · `E` éditer · `A` annuler (droits du MODULE ; un écran peut surcharger, voir `packages/rbac/data/rbac.json`).

| Rôle | M2 | M1 | M3 | M4 | M5 | M6 | M7 | M8 | M9 | MECEF | M12 | M10 | M11 | M13 | GED | RAP | M14 | CFG | PIL | DASH | SUP |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Administrateur système | VEA | VEA | VEA | VEA | VEA | VEA | VEA | VEA | VEA | VEA | VEA | VEA | VEA | VEA | VEA | VEA | VEA | VEA | VEA | VEA | — |
| Direction / Gérance | V | V | V | V | V | V | V | V | V | V | V | V | V | VEA | VE | VE | VEA | VE | VEA | VEA | — |
| Directeur Médical | VEA | VE | VEA | VE | VE | V | · | V | · | · | · | · | · | VE | · | VE | · | · | VEA | VEA | — |
| Directrice de l’Administration et des Finances (DAF) | · | VEA | · | · | · | VEA | VEA | VEA | VEA | VEA | VEA | VEA | VEA | VEA | VEA | VEA | VEA | VEA | VEA | VEA | — |
| Médecin | VEA | VE | VEA | VE | VE | V | · | · | · | · | · | · | · | · | · | VEA | · | · | VEA | VEA | — |
| Infirmier / Sage-femme | VE | VE | VEA | VEA | VEA | · | · | · | · | · | · | · | · | VEA | · | VEA | · | · | VEA | VEA | — |
| Pharmacien (archivé) | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | — |
| Biologiste médical | · | V | · | · | VEA | · | VEA | · | · | · | · | · | · | VEA | · | VEA | · | · | VEA | VEA | — |
| Gestionnaire de Stock | · | · | · | · | · | VEA | VEA | V | · | · | · | · | · | · | · | VEA | · | · | · | VEA | — |
| Caissier — Dispensaire (Pharmacie) | · | V | · | · | · | VEA | · | VE | VE | VE | VEA | · | · | · | · | VEA | · | · | · | VEA | — |
| Comptable | · | V | · | · | · | V | V | VEA | VE | VE | VEA | · | VE | V | VE | VE | · | · | VEA | VEA | — |
| Responsable RH (archivé) | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | — |
| Réception / Accueil | VE | VE | V | · | · | · | · | · | · | · | · | · | · | V | · | VEA | · | · | · | VEA | — |
| Agent Administratif | · | V | · | · | · | · | · | · | · | · | · | · | · | VEA | VE | VE | · | · | · | VEA | — |
| Ambulancier | · | V | · | · | · | · | · | · | · | · | · | · | · | VE | · | V | · | · | · | VEA | — |
| Aide-soignante | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | VEA | — |
| Technicien d’échographie | V | V | · | · | V | · | · | · | · | · | · | · | · | · | · | V | · | · | VEA | VEA | — |
| Surveillant | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | VEA | VEA | — |
| Assistant de Direction | · | · | · | · | · | · | · | · | · | · | · | · | · | VE | VE | · | · | · | VEA | VEA | — |
| Chirurgien | VE | VE | VE | · | V | · | · | · | · | · | · | · | · | · | · | V | · | · | VEA | VEA | — |
| Anesthésiste — Réanimateur | · | V | VE | · | V | · | · | · | · | · | · | · | · | · | · | V | · | · | VEA | VEA | — |
| Assistant Comptable | · | · | · | · | · | · | VE | V | VE | V | VE | · | · | · | · | V | · | · | · | VEA | — |
