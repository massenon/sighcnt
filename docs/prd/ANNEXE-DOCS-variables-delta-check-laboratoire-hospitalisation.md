# Annexe : variables du laboratoire et de l'hospitalisation candidates au suivi d'antériorité

Annexe du PRD `PRD-DOCS-numerisation-courriers-dossier-et-antecedents.md` (EF-ANT-1 à EF-ANT-5). Établie le 11/11/2026 en lisant le catalogue réel du logiciel (`data-labo.js`, 163 variables, 70 examens) et les écrans de surveillance. **Aucun seuil n'est proposé** : la décision du 11/11/2026 les laisse vides, à saisir par le Biologiste médical.

## 1. Ce qui se compare, et ce qui ne se compare pas

| Type de variable | Nombre | Suivi d'antériorité |
|---|---|---|
| Numérique (valeur mesurée) | 72 | **Oui** : variation, pourcentage, alerte si un seuil est posé, courbe |
| Liste, binaire, ternaire (positif / négatif, etc.) | 38 | Comparaison **en texte** (« négatif puis positif »), sans pourcentage ni seuil |
| Titre, commentaire, texte libre | 43 | Aucune comparaison |
| Réactif, lot, expiration | 10 | Aucune comparaison (traçabilité du réactif, pas un résultat) |

Seules les **72 variables numériques** peuvent porter un seuil de variation brutale. Elles sont listées ci-dessous, examen par examen, avec l'unité et les bornes de référence du catalogue. La colonne « Seuil de variation » est **vide partout** : c'est au Biologiste médical de la remplir, variable par variable.

Les bornes marquées « à valider » ne sont pas encore signées par le biologiste. Un seuil de variation ne se pose pas sur une borne non validée sans le dire.

## 2. Hospitalisation : séries de surveillance (hors laboratoire)

Le delta check est une pratique de laboratoire. Pour l'hospitalisation, la même mécanique de courbe d'évolution s'applique aux **constantes**, mais **sans alerte de variation** tant qu'aucun document ne fixe de règle clinique. Variables relevées dans les écrans existants :

| Série | Écran | Variable | Unité |
|---|---|---|---|
| Constantes d'accueil | `m1-constantes` | Température | °C |
| | | Tension systolique, tension diastolique | cmHg |
| | | Pouls | bpm |
| | | Fréquence respiratoire | /min |
| | | Diurèse | L |
| | | Poids | kg |
| | | Taille | cm |
| Feuille de température (hospitalisation) | `m3-feuille-temperature` | Température | °C |
| | | Tension artérielle (saisie « 12/8 », texte) | cmHg |
| | | Pouls | bpm |
| | | Fréquence respiratoire | /min |
| | | Diurèse | ml |
| | | Poids | kg |
| Surveillance en observation | `m3-observation` | Température, tension, pouls | °C, cmHg, bpm |

Deux points à ne pas laisser passer :
- La **diurèse** est en **litres** à l'accueil et en **millilitres** à l'hospitalisation. Une courbe qui les rapproche sans conversion est fausse. À corriger à la source ou à convertir à l'affichage, décision à prendre au lot A1.
- La **tension** de l'hospitalisation est un **texte** (« 12/8 »), pas deux nombres. Elle ne se compare pas tant qu'elle n'est pas scindée en systolique et diastolique, comme à l'accueil.

## 3. Variables numériques du laboratoire

### NFS complète (hémogramme) (`NFS`, Hématologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Globules blancs | `GB` | G/l | 4 à 8 | oui |
| Lymphocytes | `LY` | G/l | 1 à 4,5 | oui |
| Monocytes | `MO` | G/l | 0,2 à 1 | oui |
| Polynucléaires éosinophiles | `PNE` | G/l | 0,1 à 0,4 | oui |
| Polynucléaires basophiles | `PNB` | G/l | 0 à 0,1 | oui |
| Polynucléaires neutrophiles | `PNN` | G/l | 1,5 à 6 | oui |
| Globules rouges | `GR` | T/l | 3,5 à 5,3 | oui |
| Hémoglobine | `HB` | g/dl | 11 à 14 | oui |
| Hématocrite | `HTE` | % | 35 à 49 | oui |
| VGM | `VGM` | fl | 80 à 100 | oui |
| CCMH | `CCMH` | g/dl | 32 à 36 | oui |
| TCMH | `TCMH` | pg | 28 à 32 | oui |
| Plaquettes | `PLQ` | G/l | 150 à 400 | oui |

### Taux de réticulocytes (`RETIC`, Hématologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Réticulocytes | `RET` | G/l | 25 à 100 | à valider |

### Temps de saignement (`TS`, Hématologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Temps de saignement | `TSV` | min | 2 à 4 | à valider |

### Temps de coagulation (`TC`, Hématologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Temps de coagulation | `TCV` | min | 5 à 10 | à valider |

### Temps de prothrombine : INR (`TP`, Hématologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| INR | `INR` | sans unité | 0,8 à 1,2 | oui |
| Taux de prothrombine | `TP` | % | 80 à 100 | oui |

### Temps de céphaline activée (TCA / TCK) (`TCA`, Hématologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Temps du malade | `TCAM` | s | 25 à 40 | à valider |
| Temps du témoin | `TCAT` | s | 25 à 40 | à valider |
| Rapport malade / témoin | `TCAR` | sans unité | 0,8 à 1,2 | à valider |

### Vitesse de sédimentation (`VS`, Hématologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Première heure | `H1` | mm | jusqu’à 6 | oui |
| Deuxième heure | `H2` | mm | jusqu’à 10 | oui |

### Protéine C-réactive (CRP) (`CRP`, Sérologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Taux sérique | `CRPT` | mg/l | jusqu’à 6 | oui |

### Goutte épaisse : densité parasitaire (`GEDP`, Parasitologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Densité parasitaire | `DENS` | parasites/µl | Non renseigné | oui |

### Glycémie à jeun (`GLYAJ`, Biochimie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Glycémie | `GLY` | g/l | 0,7 à 1,1 | oui |

### Glycémie post-prandiale (`GLYPP`, Biochimie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Glycémie | `GLYP` | g/l | jusqu’à 1,6 | oui |

### Créatinine (`CREA`, Biochimie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Créatinine | `CREA` | mg/l | 6 à 14 | oui |

### Azotémie (urée) (`AZOT`, Biochimie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Azotémie | `AZO` | g/l | 0,15 à 0,45 | oui |

### Calcémie (`CA`, Biochimie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Calcémie | `CAL` | mg/l | 84 à 104 | oui |

### Magnésémie (`MG`, Biochimie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Magnésémie | `MAG` | mg/l | 16 à 30 | oui |

### Ionogramme sanguin (Na, K, Cl) (`IONO`, Biochimie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Natrémie | `NA` | mmol/l | 135 à 148 | oui |
| Kaliémie | `K` | mmol/l | 3,4 à 5,4 | oui |
| Chlorémie | `CL` | mmol/l | 98 à 108 | oui |

### Transaminases TGO / TGP (`TGO`, Biochimie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| TGO (ASAT) | `TGO` | UI/l | jusqu’à 45 | oui |
| TGP (ALAT) | `TGP` | UI/l | jusqu’à 49 | oui |

### Gamma-GT (`GGT`, Biochimie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| GGT | `GGTH` | UI/l | jusqu’à 45 | oui |

### Cholestérol total (`CHOLT`, Biochimie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Cholestérol total | `CT` | g/l | jusqu’à 2 | oui |

### Cholestérol HDL (`CHOLH`, Biochimie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Cholestérol HDL | `CH` | g/l | 0,35 | oui |

### Cholestérol LDL (`CHOLL`, Biochimie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Cholestérol LDL | `CLD` | g/l | jusqu’à 1,6 | à valider |

### Triglycérides (`TG`, Biochimie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Triglycérides | `TGL` | g/l | jusqu’à 1,5 | oui |

### Bilirubine totale, conjuguée et non conjuguée (`BILI`, Biochimie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Bilirubine T | `BT` | mg/l | jusqu’à 10 | oui |
| Bilirubine C | `BC` | mg/l | jusqu’à 2 | oui |
| Bilirubine NC | `BNC` | mg/l | jusqu’à 8 | à valider |

### Protidémie (`PROT`, Biochimie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Protidémie | `PRO` | g/l | 60 à 80 | oui |

### Lipasémie (`LIPA`, Biochimie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Lipasémie | `LIP` | UI/l | jusqu’à 60 | à valider |

### Phosphorémie (`PHOS`, Biochimie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Phosphorémie | `PHO` | mg/l | 25 à 45 | oui |

### Phosphatase alcaline (`PAL`, Biochimie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Phosphatase alcaline | `PALV` | UI/l | 40 à 130 | à valider |

### Glucorachie (`GLUCO`, Biochimie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Glucorachie | `GLC` | g/l | Non renseigné | oui |

### Protéinorachie (`PROTR`, Biochimie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Protéinorachie | `PRR` | g/l | 0,15 à 0,45 | à valider |

### D-dimères (`DDIM`, Biochimie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| D-dimères | `DD` | mg/l | 0 à 0,5 | oui |

### Hémoglobine glyquée (HbA1c) (`HBA1C`, Biochimie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Hémoglobine glyquée (HbA1c) | `A1C` | % | 4 à 6,5 | oui |

### Uricémie (acide urique) (`URIC`, Biochimie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Acide urique | `ACU` | mg/l | 30 à 70 | oui |

### ECB du liquide céphalo-rachidien (`ECBLCR`, Bactériologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Leucocytes | `LEUX` | /champ | Non renseigné | à valider |

### ECB du liquide pleural (`ECBLP`, Bactériologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Leucocytes | `LEUX` | /champ | Non renseigné | à valider |

### ECB du liquide d’ascite (`ECBLA`, Bactériologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Leucocytes | `LEUX` | /champ | Non renseigné | à valider |

### ECB du pus (`ECBPUS`, Bactériologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Leucocytes | `LEUX` | /champ | Non renseigné | à valider |

### Prélèvement urétral (PU) (`PU`, Bactériologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Leucocytes | `LEUX` | /champ | Non renseigné | à valider |

### ß-HCG (dosage sérique) (`BHCG`, Hormonologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| ß-HCG | `HCG` | mUI/ml | jusqu’à 5 | à valider |

### FSH (`FSH`, Hormonologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| FSH | `FSHV` | mUI/ml | Non renseigné | à valider |

### LH (`LH`, Hormonologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| LH | `LHV` | mUI/ml | Non renseigné | à valider |

### Œstradiol (`OEST`, Hormonologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Œstradiol | `OES` | pg/ml | Non renseigné | à valider |

### Progestérone (`PROG`, Hormonologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Progestérone | `PRG` | ng/ml | Non renseigné | à valider |

### PSA total (`PSAT`, Hormonologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| TPSA | `TPSA` | ng/ml | 0 à 4 | oui |

### PSA libre (`PSAL`, Hormonologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| PSA libre | `PSAL` | ng/ml | Non renseigné | oui |
| Rapport PSA libre / PSA total | `RATIO` | % | 25 | à valider |

### Testostérone (`TESTO`, Hormonologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Testostérone | `TST` | ng/ml | Non renseigné | à valider |

### AMH : hormone antimüllérienne (`AMH`, Hormonologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| AMH | `AMHV` | ng/ml | Non renseigné | à valider |

### Prolactinémie (`PRL`, Hormonologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| Prolactine | `PROL` | ng/ml | 3,34 à 26,72 | oui |

### TSH (`TSH`, Hormonologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| TSH | `TSHV` | µUI/ml | 0,4 à 4 | à valider |

### T3 (`T3`, Hormonologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| T3 libre | `T3V` | pg/ml | 2,3 à 4,2 | à valider |

### T4 (`T4`, Hormonologie)

| Variable | Code | Unité | Bornes de référence | Bornes validées |
|---|---|---|---|---|
| T4 libre | `T4V` | pg/ml | 8,9 à 17,2 | à valider |

## 4. Saisie des seuils

Le seuil se pose par variable, dans les paramètres du laboratoire, en base, **versionné par date** : changer un seuil ne change pas une alerte déjà émise. Une variable sans seuil n'alerte jamais. Chaque seuil porte son auteur (le Biologiste médical), sa date d'effet et son motif, sur le modèle des plages par lot de réactif.
