# PRD : tableaux, export Excel (.xlsx) et impression des lignes cochées

Statut : **brouillon du 15/11/2026, précisé le 15/11/2026 par la Direction** : la demande porte sur (a) l'**exportation en masse**, (b) les **lignes cochées** et (c) l'**impression des lignes cochées** (section 3 bis). Source : question de la Direction du 15/11/2026 (« est-ce que les différents écrans ont le bouton Exporter en xlsx, et aussi l'option de sélection par case à cocher des lignes de tables pour imprimer ? »). Skills : `spec`, `sigh-maitre`, `sigh-flutter`.
Règle de rédaction : pas de tiret cadratin comme ponctuation.

## 1. Ce qui existe aujourd'hui (mesuré dans le code le 15/11/2026, pas un audit écran par écran)

**Maquette** (`prototype_html/assets/js/ui.js`, composant de tableau commun) :
- Un bouton « Exporter » est posé par le composant : il ouvre une fenêtre à deux choix, « CSV / Excel » et « PDF / Impression ». Le premier produit un fichier **`.csv`** (`exportCSV`), pas un classeur `.xlsx`. Le second imprime les lignes **filtrées** (`printTable`), jamais seulement les lignes cochées.
- Une colonne de cases à cocher (une par ligne, plus « Tout sélectionner »), une barre « N sélectionnées » et des actions de groupe (`bulkActions`) existent dans le composant, mais ne sont **activées que sur 2 écrans** (`selectable: true`, valeur par défaut `false`) et ne servent qu'à des actions de groupe propres à ces écrans (5 déclarations d'actions de groupe). **Aucun écran n'imprime ni n'exporte les seules lignes cochées.**
- Un **écrivain `.xlsx` existe déjà** : `SIGH.xlsx.ecrire` (`assets/js/vendor/xlsx-mini.js`, sans dépendance, en-tête figé, largeurs de colonnes, chaînes partagées), chargé au clic pour les modèles d'import. Il n'est pas branché sur le bouton « Exporter ».
- 189 déclarations de nom d'export (`exportName`) : la plupart des écrans passent par ce composant commun, donc **ont déjà un bouton « Exporter » (CSV)**. 29 tableaux sont construits à la main (`el('table')`) hors composant : ils n'ont **pas** ce bouton.

**Poste Flutter** (`apps/poste/lib/kit/tableau.dart`) : le kit tableau a la même modale (« CSV / Excel », texte CSV passé à `alExporter(nom, csv)`) et une sélection multiple (`selectionnable`, `actionsGroupe`). Mesuré : la sélection n'est activée que sur 8 écrans et le rappel d'export n'est branché que sur 5 écrans. Le poste dispose déjà de `archive` (ZIP, donc de quoi écrire un `.xlsx`) et de `file_selector` (choix du dossier d'enregistrement) dans `pubspec.yaml`.

**Réponse à la question** : (1) l'export « Excel » est en réalité un CSV partout où le bouton existe, et ce bouton est absent des tableaux construits hors composant et, au poste, de la plupart des écrans ; (2) la sélection par cases à cocher pour imprimer n'existe nulle part : la sélection existe sur quelques écrans pour d'autres usages seulement.

## 2. Problème

Un agent veut sortir un tableau dans Excel (comptabilité, stock, recettes, planning) ou imprimer seulement quelques lignes (trois factures, deux bons de sortie). Aujourd'hui il obtient un CSV (accents et séparateurs mal ouverts dans Excel, aucune largeur de colonne, nombres en texte) et, pour imprimer, tout le filtre ou rien.

## 3. Objectifs

- **O1.** Le bouton « Exporter » de chaque tableau propose un vrai **`.xlsx`** (feuille nommée, en-tête figé, largeurs de colonnes, montants et dates en cellules numériques et dates, jamais du texte), en plus du CSV conservé.
- **O2.** **Case à cocher par ligne et « Tout sélectionner »** sur TOUS les tableaux (maquette et poste), avec la barre « N sélectionnées ». Une sélection cochée vaut périmètre : « Exporter » et « Imprimer » portent alors **les lignes cochées** ; sans sélection ils portent les lignes filtrées, comme aujourd'hui, et la fenêtre le dit (« 3 lignes cochées » ou « 124 lignes filtrées »).
- **O3.** **Les droits du tableau s'appliquent à la sortie** : un export ou une impression ne contient jamais une colonne ou une ligne que l'écran ne montre pas à ce profil (RG-13, zones). Les colonnes masquées par l'utilisateur ne sortent pas, comme aujourd'hui.
- **O4.** **L'impression d'une sélection** respecte les trois gabarits (A4, rouleau 80 mm, carte CR80 quand ils s'appliquent), l'en-tête officiel et le pied normalisé ; un total de colonne est CALCULÉ sur les lignes imprimées (jamais fourni), « non calculable » n'est pas zéro.
- **O5.** Un export ou une impression de données nominatives est **journalisé** (RG-12 : utilisateur, date, écran, nombre de lignes, identifiants des fiches, jamais le contenu).
- **O6.** Une limite de lignes par export est un **réglage en base** (défaut semé, borné, à valider), avec refus nommé au-delà (code, motif, geste : affiner le filtre ou cocher moins de lignes).

## 3 bis. Précision de la Direction (15/11/2026) : trois besoins

- **(a) Exportation en masse** : sortir en un geste TOUT le contenu d'un tableau (toutes les pages, pas seulement la page affichée ni les 12 lignes visibles), avec le filtre actif ou sans filtre au choix. Lecture proposée, à confirmer : « en masse » = toutes les lignes du tableau en un seul fichier ; une variante « plusieurs tableaux d'un module dans un même classeur, une feuille par tableau » est proposée en P2 (section 5), pas en version 1.
- **(b) Lignes cochées** : cocher des lignes (une, plusieurs, toutes) et exporter SEULEMENT celles-ci.
- **(c) Impression des lignes cochées** : imprimer SEULEMENT les lignes cochées, au gabarit du document (A4, rouleau 80 mm, carte CR80 quand ils s'appliquent).
Les trois suivent les mêmes règles de droits, de journal et de limite (O3, O5, O6 ci-dessous). L'export en masse est le seul qui peut dépasser la limite de lignes réglable : il est alors refusé nommé avec le geste (affiner le filtre) et jamais tronqué en silence.

## 4. Non-objectifs

- Aucun envoi par courriel ni par service externe (le texte médical ne quitte jamais la clinique) : le fichier est écrit sur le poste.
- Pas d'import de retour depuis ce fichier (l'import reste celui des jeux validés).
- Pas de tableau croisé, ni de graphique, ni de macro dans le classeur.
- Pas d'export sur les téléphones.

## 5. Exigences

| N° | Exigence | Priorité |
|---|---|---|
| EF-TAB-1 | Le composant de tableau commun (maquette) et le kit tableau (poste) écrivent un `.xlsx` (écrivain existant côté maquette, `archive` côté poste) : types de cellules corrects (nombre, date, texte), en-tête figé, largeurs, nom de feuille et de fichier datés | P0 |
| EF-TAB-2 | La sélection par cases est activée par défaut sur tous les tableaux (réglage `selectable` inversé), avec « Tout sélectionner » sur la page affichée et sur l'ensemble filtré, et le compte dit | P0 |
| EF-TAB-3 | « Exporter » et « Imprimer » prennent la sélection si elle existe, sinon le filtre ; la fenêtre dit lequel | P0 |
| EF-TAB-4 | Les 29 tableaux construits hors composant sont migrés vers le composant commun (ou reçoivent le même bouton) ; liste exhaustive mesurée avant le lot | P0 |
| EF-TAB-5 | Les droits de lecture (rôle, fonction, secteur, zone) filtrent colonnes et lignes de la sortie ; un test par écran sensible (patients, résultats, paie, comptabilité) | P0 |
| EF-TAB-6 | Journal d'export et d'impression nominatifs (RG-12) | P0 |
| EF-TAB-7 | Limite de lignes par export réglable en base, refus nommé | P1 |
| EF-TAB-8 | Impression de la sélection aux gabarits A4 et rouleau 80 mm, totaux calculés | P1 |
| EF-TAB-10 | **Exportation en masse** : un geste « Tout exporter » écrit toutes les lignes du tableau (toutes pages), avec ou sans le filtre actif au choix, en arrière-plan avec un compteur de progression au-delà d'un seuil réglable ; jamais de troncature silencieuse | P0 |
| EF-TAB-11 | **Export multi-feuilles** : plusieurs tableaux d'un même module dans un seul classeur, une feuille par tableau | P2 |
| EF-TAB-9 | Droit réservé « exporter les données d'un écran » réglable par rôle (comme `corriger_texte_ocr`), commande ABSENTE sans le droit, le moteur refuse aussi | P1 |

## 6. Critères d'acceptation (extraits)

- Un tableau de la comptabilité exporté en `.xlsx` s'ouvre dans Excel avec les montants en cellules numériques (une somme Excel de la colonne égale le total affiché) et les dates en dates.
- Trois lignes cochées : l'export et l'impression contiennent ces trois lignes et rien d'autre ; deux sélections successives après un changement de page ou de filtre gardent la sélection ou la remettent à zéro de façon DITE (jamais en silence).
- Un profil sans le droit de lire la colonne « salaire » n'obtient jamais cette colonne dans le fichier ; un profil sans droit d'export ne voit pas la commande.
- Un export de 12 000 lignes est refusé nommé tant que la limite réglée est plus basse, avec le geste de correction.
- Aucun tableau de l'application n'est sans case à cocher ni sans bouton « Exporter » (test de garde de génération qui énumère les tableaux, comme `garde-roles-en-dur.js`).

## 7. Décisions à demander à la Direction

1. Faut-il conserver le CSV à côté du `.xlsx` (proposition : oui, les deux).
2. Tous les rôles peuvent-ils exporter, ou seulement certains (proposition : droit réservé réglable par rôle, défaut : les rôles qui lisent l'écran, hors rôles d'accueil pour les données financières).
3. Limite de lignes par export (aucune valeur n'est proposée : à fixer sur la plus grande table réelle).
4. La sélection est-elle conservée d'une page à l'autre d'un même tableau (proposition : oui, jusqu'à ce que l'agent la vide).
5. Imprimer la sélection : un état par ligne cochée (bons, factures) ou un seul tableau des lignes cochées (proposition : un seul tableau par défaut, un état par ligne là où un document unitaire existe déjà).

## 8. Lots proposés (maquette d'abord)

1. **EXP-0 mesure** : énumérer les tableaux de la maquette et du poste (composant commun / hors composant, sélection oui/non, export oui/non, colonnes sensibles par profil) ; rien ne se code avant le tableau de couverture.
2. **EXP-1 maquette** : `.xlsx` dans le composant commun, sélection par défaut, sortie de la sélection, impression de la sélection, droits sur la sortie, journal, limite réglable ; migration des 29 tableaux ; vecteurs tirés de l'écran réel.
3. **EXP-2 poste** : le même au kit tableau (écriture `.xlsx` avec `archive`, choix du dossier avec `file_selector`), tests de widgets et de droits, journal au magasin.

Preuves attendues : test qui échoue avant puis passe, mutations rouges (colonne interdite exportée, sélection ignorée, nombre écrit en texte, limite ignorée, export sans journal, commande visible sans le droit), classeur relu par `SIGH.xlsx.lire` (maquette) et par un lecteur indépendant. Non vérifié d'avance : ouverture dans Excel et LibreOffice réels sur Windows.
