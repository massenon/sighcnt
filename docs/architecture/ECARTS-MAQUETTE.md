# Écarts relevés dans la maquette au moment du portage

> Règle du dépôt : **on porte fidèlement, on signale, on ne corrige pas d'office** (« extraire, ne pas deviner »). Chaque écart ci-dessous est reproduit par un vecteur engendré par la maquette ; le portage Dart en rend le même comportement. Corriger exige une décision de la Direction, puis un changement **dans la maquette d'abord** (exécutable de référence), puis la régénération des vecteurs.

| # | Où | Constat | Effet | Vecteur |
|---|---|---|---|---|
| E1 ✅ **corrigé le 30/10/2026** | `PR.encaisser` → `ecrireEncaissement` | La **part assureur de TOUTE la facture** est ré-inscrite (débit 411 et crédit 706) à **chaque versement partiel**. Une facture assurée réglée en deux fois par le patient pose deux fois la créance sur la compagnie. | Créance assureur et produits **comptés plusieurs fois** au journal (en brouillon : la validation comptable est humaine, mais elle valide ce qu'elle voit). | `encaissement.json` — « assuré : part assureur … » (2 versements, 411 = 14 000 deux fois) |
| E2 | `PR.encaisser`, pièce **sans lignes** (antérieure au modèle par lignes) | Un `montant` supérieur au dû est accepté tel quel : `montantPaye` dépasse le TTC, `baseMecef` aussi. | Base MECeF supérieure à la facture. Concerne les seules pièces anciennes (les nouvelles ont des lignes). | `encaissement.json` — « facture sans lignes … partiel puis solde » (99 999 sur 5 000 dus) |
| E3 ✅ **corrigé le 30/10/2026** | `ecrireEncaissement` | Le numéro de pièce comptable prend les **cinq derniers chiffres** du numéro de facture ; faute de chiffres (id technique), il n'en reste qu'un ou deux (`CAI-2026-8`). Le millésime `2026` est **écrit en dur**. | Collisions possibles de numéros de pièce ; millésime faux dès 2027. | `encaissement.json` — « numéro de pièce sans chiffres » |
| E4 | `PR.repartir` (`carteValide`) | La carte qui expire le jour même est valide si la date de facturation est un **jour** (`2026-08-16`), non valide si c'est un **instant** du même jour (`…T12:00:00Z`) : la comparaison est faite en millisecondes entre minuit UTC et l'instant. | Selon la manière dont l'appelant formate la date, la même carte est valide ou non le dernier jour. À normaliser en jour avant de comparer. | `prise_en_charge.json` — « carte qui expire LE JOUR même » / « date avec heure (UTC) » |

**Décision de la Direction du 30/10/2026 : « il faut corriger » E1 et E3.** Corrigés **dans la maquette d'abord** (`ecrireEncaissement`, `creanceAssureurDejaConstatee`, `numeroPieceCaisse` dans `parcours.js`), vecteurs régénérés, puis portés en Dart :
- **E1** — la créance assureur (411) et le produit correspondant (706) ne sont constatés qu'au **premier** versement ; sur la vie de la facture : 706 = facturé, 411 = part assureur, 571 = part patient.
- **E3** — le numéro de pièce est une **série annuelle** `CAI-AAAA-NNNNN` (millésime de la date de l'écriture, rang suivant) reprise par tous les versements d'une même facture.

E2 (pièce sans lignes) et E4 (date jour / instant) restent à arbitrer ; ils sont portés fidèlement.

## E5 — « Factures par jour (mois en cours) » était figé sur août 2026 — CORRIGÉ dans la maquette le 30/10/2026

`m8-facturation.js` construit les jours du graphique avec `new Date(2026, 7, d)` : le mois est écrit en dur, pas lu de l'horloge. Sur un poste réel, le graphique compterait toujours les factures d'août 2026. Le portage Dart lit le mois de l'horloge du poste (conforme au titre « mois en cours »). **À corriger dans la maquette ; le comportement du Dart fait foi.**
