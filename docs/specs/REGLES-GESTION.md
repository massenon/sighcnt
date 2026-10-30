# Règles de gestion RG-01 → RG-14

> **ENGENDRÉ** par `prototype_html/build/parite.js` depuis `CLAUDE.md` (source : CDCT §6 et §9.4) — ne pas éditer. Chaque règle devra porter, côté cible, un **vecteur de test** (`packages/domaine/test/vecteurs/`) : sans vecteur, pas de règle portée.

| Règle | Énoncé | Vecteur de test | Statut |
|---|---|---|---|
| **RG-01** | Identifiant patient `CNT[n°]/[année]` (ex. `CNT530/25`), généré automatiquement, unique, non modifiable. | à écrire | non portée |
| **RG-02** | Médicaments facturés **au prix d'achat, sans marge**. Exception = validation Direction tracée. | à écrire | non portée |
| **RG-03** | Toute sortie de stock rattachée à un justificatif ; **le stock ne peut jamais devenir négatif**. | à écrire | non portée |
| **RG-04** | Commande de stock gros validée par la Directrice Administrative avant transmission fournisseur. | à écrire | non portée |
| **RG-05** | Rangement pharmacie en **FEFO** ; alertes de péremption automatiques et paramétrables. | à écrire | non portée |
| **RG-06/07/08** | Sortie d'hospitalisation : solde apuré + signature patient + signature infirmier + constat du gardien ; sortie contre avis médical motivée (avis du Procureur consigné si nécessaire). | à écrire | non portée |
| **RG-09** | Prise en charge assurance appliquée uniquement si la carte est valide à la date de facturation, sinon facturation intégrale au patient. | à écrire | non portée |
| **RG-10** | Toute écriture comptable équilibrée (débit = crédit) avant validation. | à écrire | non portée |
| **RG-11** | Primes de garde/permanence calculées depuis le planning validé et la grille en vigueur. | à écrire | non portée |
| **RG-12** | Journalisation systématique (utilisateur, date/heure, entité, ancienne/nouvelle valeur) ; **aucune action anonyme**. | à écrire | non portée |
| **RG-13** | Cloisonnement RBAC : médical réservé au soignant habilité, financier/RH aux profils comptables et RH. | à écrire | non portée |
| **RG-14** | **Suppression logique (archivage) uniquement**, jamais de suppression physique. | à écrire | non portée |

## Autres invariants (CLAUDE.md)

- Un lit ne peut porter qu'une admission active.
- CUMP calculé automatiquement sur consommables labo/médicaux.
- Cotisations : part patronale 16,4 % / part ouvrière 3,6 %.
- Une pièce émise ne se réécrit jamais (avoir, rectification, nouvelle pièce).
- Une donnée de référence qui change se **versionne par date** (couverture d'assurance, grille des primes, plages par lot) — on n'écrase pas.
- Une restriction s'**annonce** ; une commande refusée est **absente**, pas grisée ; « non calculable » n'est pas zéro ; un tiret n'est ni zéro ni exclusion.
