# Guide : mesurer l'OCR sur les trois vrais scans de la clinique

Décision de la Direction (PRD DOCS, Q7) : l'OCR est retenu en phase 2, local, APRÈS un essai sur trois vrais scans de la clinique. Le lot OCR-prep a préparé tout ce qui ne dépend pas du moteur ; ce guide dit exactement quoi faire le jour où les trois scans arrivent. **Aucun moteur n'est choisi par ce lot, aucun n'est installé, aucune qualité n'a été mesurée.**

## 1. Où déposer les scans d'essai

Dans un dossier PROPRE AU POSTE, hors du dépôt git, par exemple `C:\essai-ocr\` (Windows) ou `~/essai-ocr/`. Ces scans sont des documents réels : ils ne quittent jamais le poste, ne se commitent pas, ne s'envoient pas à un service externe. (Le dossier `packages/domaine/essai-ocr/` est ignoré par git si l'on préfère travailler dans le dépôt.)

Chaque scan est UNE IMAGE (une page) : `png`, `jpg`, `jpeg` ou `webp`. Un PDF scanné se mesure page par page : exporter chaque page en image (le banc nomme les PDF qu'il rencontre et ne les mesure pas : lire les pages d'un PDF exige un rendeur de pages qu'aucun poste n'a encore).

## 2. Nommer la transcription de référence

À côté de chaque image, un fichier texte de MÊME NOM, extension `.txt`, encodé en UTF-8 :

```
essai-ocr/
  courrier-prefecture.png
  courrier-prefecture.txt      <- ce qui est écrit sur le scan, recopié à la main
  ordonnance-1.jpg
  ordonnance-1.txt
  compte-rendu.png
  compte-rendu.txt
```

La transcription est la VÉRITÉ à laquelle le moteur est comparé : la recopier fidèlement, accents compris (é, è, ê, à, ç, œ), casse comprise, sans corriger une faute d'orthographe du scan. Un scan sans `.txt` est ignoré et NOMMÉ au rapport.

## 3. Prouver d'abord que la mesure est juste (aucun moteur réel)

Depuis `packages/domaine` :

```
dart run tool/mesure_ocr.dart --dossier test/fixtures/ocr_banc --sortie /tmp/essai --moteur factice-parfait,factice-sans-accents,factice-perd-mots,factice-bruit --exemples
```

Un moteur parfait donne 100 % ; le moteur qui supprime les accents le montre (mots corrects en baisse, accents retrouvés 0 %) ; celui qui perd un mot sur cinq fait monter les mots perdus. Ces moteurs sont FACTICES et les scans SYNTHÉTIQUES : ils prouvent la mesure, ils ne disent rien d'un moteur réel. (`dart test test/ocr_mesure_test.dart` rejoue cette preuve.)

## 4. Mesurer un moteur réel, le jour où il est installé

Le banc ne présume d'aucun moteur : on lui donne la LIGNE DE COMMANDE du moteur installé, avec `{image}` (le chemin du scan) et `{langue}` ; la sortie standard de la commande est le texte lu.

```
dart run tool/mesure_ocr.dart --dossier C:\essai-ocr --sortie C:\essai-ocr\rapport --commande "<commande du moteur> {image} <options> {langue}" --nom-moteur <nom> --version-moteur <version> --langue fra
```

Pour comparer deux moteurs, lancer deux fois (un rapport par date : renommer le premier avant le second) et rapprocher les tableaux « Comparaison ». Un moteur absent du poste ou qui sort avec un code non nul est un refus NOMMÉ (MOTEUR_ABSENT, MOTEUR_EN_ECHEC), compté pour zéro mot correct : il n'est jamais exclu de la moyenne.

Le rapport (`rapport-ocr-AAAA-MM-JJ.md` et `.json`) contient, par moteur et par scan : taux de mots corrects, taux de caractères corrects, mots perdus, accents français perdus, temps par page sur CE poste. Par défaut il ne cite AUCUN mot des documents (des nombres seulement) ; `--exemples` ajoute les mots perdus en clair, à éviter sur des documents de patients. Il se joint en annexe à la décision.

## 5. Lire le rapport

- **Mots corrects** : 1 moins la distance d'édition des mots sur le nombre de mots de la référence. Un moteur qui supprime les accents y perd des mots même si le texte se lit.
- **Mots perdus** : mots dont même la forme sans accent et sans casse n'est pas dans le texte lu (disparus ou déformés).
- **Accents retrouvés** : le risque propre au français (é lu e, ç lu c, œ lu oe). « Sans objet » quand la référence n'en porte aucun.
- **Temps par page** : mesuré sur ce poste, il vaut pour ce poste ; la charge CPU d'un poste de clinique en activité se relève à part.
- Trois scans indiquent, ils ne démontrent pas : le rapport le dit.

## 6. Après la mesure : brancher le moteur choisi (quelques heures)

La Direction choisit. Puis, sans toucher aux écrans ni à la synchronisation :

1. Écrire l'adaptateur Dart du moteur : une classe qui implémente `MoteurOcr` (`packages/domaine/lib/src/fichiers/ocr.dart`) : `id`, `version`, `langues`, `formats`, `lire(EntreeOcr)` qui rend un `ResultatOcr` ou lève `ErreurOcr(ocrRefus(code, motif))`. Le banc l'essaie tel quel (`mesurerDossier`) avant le poste.
2. Si les PDF scannés doivent être lus : écrire aussi un `RendeurPages` (rendu d'un PDF en images). Sans lui, un PDF sans couche texte est refusé en nommant `RENDU_PAGES_ABSENT`.
3. Installer le moteur et ses données de langue (`fra`) avec le poste (installeur Windows), hors ligne.
4. Au démarrage du poste (`apps/poste/lib/main.dart`, à côté de la création de `OcrPoste`), enregistrer le moteur : `ocr.enregistrer(MonMoteur())`.
5. L'administrateur ou la DAF ouvre « Lecture des scans (OCR) » (courriers ou documents du patient), choisit le moteur et la langue, saisit le motif, active. Les scans déjà déposés sont rattrapés par la file.
6. Vérifier sur un scan : l'état passe « en attente », « en cours », puis « texte lu par machine, à vérifier » ; la recherche le trouve et le dit.
7. Dire à la Direction les décisions restantes : activation par défaut, correction manuelle du texte, durée de conservation (`DECISIONS-A-VALIDER.md`, section T).
