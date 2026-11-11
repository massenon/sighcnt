# SPEC : format de l'archive de clôture d'exercice (SIGH-ARC, version 1)

Statut : **proposition de format**, du 11/11/2026, décrivant l'archive **déjà produite** par la maquette (`deposerArchive` dans `parcours.js`) et l'écrivant noir sur blanc
Décision de la Direction du 11/11/2026 : « pas de format DGI : proposer un format et faire l'archive actuelle (CSV, balance, PDF, SHA-256) ». La conservation est **illimitée**.

## 1. Ce que cette spec dit, et ce qu'elle ne dit pas

- Elle **nomme et fige** le format que le logiciel produit déjà (colonnes du journal SYSCOHADA révisé, empreintes SHA-256). Le format du CSV des écritures a été validé par la Direction le 05/11/2026.
- Elle **ne prétend pas** être un format imposé par la DGI du Bénin : aucun document du dépôt n'en décrit un. Si la DGI ou un commissaire aux comptes en exige un, ce format se **convertit** depuis l'archive sans la modifier (section 6).
- Rien dans cette spec n'est une promesse de conformité légale : c'est un format **de conservation et de preuve**, lisible sans le logiciel.

## 2. Identité et immuabilité

- Référence : `ARC-AAAA-NN` (`AAAA` exercice, `NN` numéro de clôture, 01 pour la première ; une réouverture puis une nouvelle clôture produit `ARC-AAAA-02`, jamais une régénération de la première).
- La collection `archivesExercice` refuse toute modification, tout archivage et tout second dépôt pour la même clôture. Une archive n'est **jamais** régénérée (RG-14).
- Elle naît **avec** la clôture définitive, dans la GED de l'établissement (bibliothèque distincte des documents patient).

## 3. Contenu de l'archive (quatre fichiers)

| Fichier | Contenu | Format |
|---|---|---|
| `ecritures-AAAA.csv` | toutes les écritures de l'exercice, pièce de clôture et d'à-nouveaux comprises | CSV, séparateur `;`, UTF-8 avec BOM, fin de ligne CRLF, dates `JJ/MM/AAAA`, montants **entiers en FCFA** (la monnaie n'a pas de subdivision) |
| `balance-AAAA.csv` | balance générale par compte | mêmes conventions |
| `etats-AAAA.html` | états de synthèse imprimables (bilan par soldes, charges et produits, classe 8) ; « Enregistrer en PDF » se fait à l'impression | HTML autonome, sans ressource externe |
| `manifeste-AAAA.txt` | une ligne par fichier : `empreinte SHA-256`, deux espaces, `nom` | texte, UTF-8 |

**Colonnes de `ecritures-AAAA.csv`** (dans cet ordre) : Journal ; Date ; N° pièce ; Compte ; Intitulé du compte ; Libellé de l'écriture ; Centre de coûts ; Débit ; Crédit ; Lettrage ; Statut.

**Colonnes de `balance-AAAA.csv`** : Compte ; Intitulé ; Débit ; Crédit ; Solde.

Un champ qui contient `;`, un guillemet ou un saut de ligne est entouré de guillemets, les guillemets internes sont doublés. Les lignes sont triées par date, puis numéro de pièce, puis compte.

## 4. Vérification et téléchargement

- À **chaque** téléchargement, le logiciel **recalcule** l'empreinte SHA-256 du fichier et la compare à celle du manifeste. Une différence est un **refus nommé** (« le manifeste ne porte pas l'empreinte de … »), jamais un fichier livré.
- L'empreinte du manifeste lui-même est portée par la fiche de l'archive et par la pièce de clôture au journal d'audit, pour qu'on puisse vérifier le manifeste sans lui faire confiance.
- Vérifier hors du logiciel : `sha256sum -c manifeste-AAAA.txt` dans le dossier des fichiers.

## 5. Conservation et chemin

- Conservation **illimitée**, aucune purge.
- La fiche de l'archive indique le **chemin local** du fichier sur le poste (même règle que les scans, PRD documents EF-DOC-3b) et ses copies sont synchronisées comme tous les fichiers, par empreinte (spec de synchronisation EF-SYNC-18).

## 6. Extensions proposées (à valider, non produites aujourd'hui)

Rien de ce qui suit n'existe dans la maquette ; c'est une liste de propositions, à décider une par une.

| N° | Extension | Intérêt |
|---|---|---|
| X1 | `grand-livre-AAAA.csv` (une ligne par écriture, regroupée par compte, avec soldes d'ouverture et de clôture) | rapprochement compte par compte sans rejouer le journal |
| X2 | `journal-CL-AN-AAAA.csv` (les deux pièces de clôture et d'à-nouveaux isolées) | contrôle rapide de la bascule |
| X3 | une ligne d'en-tête de version dans le manifeste : `# SIGH-ARC 1` | savoir quel format lire dans dix ans |
| X4 | le procès-verbal de clôture (qui a démarré, qui a clôturé, motif, date, résultat) en fichier de l'archive | la preuve de la décision voyage avec les écritures |
| X5 | un export de **conversion** vers un format exigé par la DGI ou un commissaire aux comptes, produit **à la demande** depuis l'archive | répondre à un contrôle sans modifier l'archive |

Recommandation : X3 et X4 tout de suite (coût faible, aucune ambiguïté), X1 et X2 si le Comptable les demande, X5 seulement le jour où un format cible est nommé par écrit.

## 7. Questions ouvertes

| N° | Question | Recommandation |
|---|---|---|
| Q1 | Un format DGI existe-t-il pour le Bénin ? | à demander au Comptable ou au commissaire aux comptes ; sans réponse, ce format reste la référence |
| Q2 | Faut-il le PDF produit par le logiciel plutôt que le HTML à imprimer ? | non tant qu'aucun poste n'exige un PDF sans impression ; le HTML est lisible partout |
| Q3 | X3 et X4 maintenant ? | oui |
