# PLAN : documents numérisés (courriers M13, dossier patient M1), stockage des fichiers hors du magasin, recherche avancée, puis suivi d'antériorité
Source : `docs/prd/PRD-DOCS-numerisation-courriers-dossier-et-antecedents.md` (EF-DOC-1 à 10, EF-ANT-1 à 6), réponses de la Direction du 11/11/2026 (`docs/decisions/DECISIONS-A-VALIDER.md` sections H et H bis : Q1 à Q10 acceptées), `docs/specs/SPEC-protocole-synchronisation.md` EF-SYNC-18 (fichiers par empreinte), `docs/plans/PLAN-importation-bouton-par-ecran.md` (forme et jeu `courriers`) · Écarts : `docs/architecture/ECARTS-MAQUETTE.md` E2481 à E2491 · Branche : `claude/sighcnt-monorepo-offline-first-i0v3v9`.

## Résultat attendu
- Un agent dépose un scan (PDF, JPEG, PNG, WEBP au dossier patient) sur la fiche d'un courrier ou d'un document patient, le voit tout de suite (visionneuse d'image écrite pour le projet, PDF dans le lecteur du navigateur), le télécharge sous son nom normalisé, et retrouve la pièce par un mot de son texte quand le PDF porte une couche texte.
- Le fichier ne vit PLUS dans le magasin JSON : le magasin garde les métadonnées (empreinte SHA-256, nom, type, taille, pages) et le fichier est rangé hors du magasin, sous sa clé d'empreinte, derrière la session et une règle par famille alignée sur `rbac.json`.
- Chaque comportement a un scénario écrit sur le geste (Chrome) qui ÉCHOUE sur l'arbre d'avant ; les mutations du PRD section 11 rougissent la sonde visée.

## Mesure D0 (avant tout code, 12/11/2026, banc isolé `sigh_banc_d0`, jeu courant, `VERSION` 81)
Chiffres relevés par un script de mesure (Chrome sans interface, serveur PHP et PostgreSQL du banc), en caractères JSON ou en octets de réponse.
- **`documentsPatient` aujourd'hui** : 99 fiches, 28 150 caractères (28 Ko) au total, **0 fiche porte un fichier** (`donnees` vide partout, `fichier` vide partout). Les 99 fiches de démonstration DÉCLARENT pourtant des tailles de 80 Ko à 3,1 Mo : somme déclarée 159 384 576 octets (152 Mo), soit 212 512 768 caractères une fois en base64. Aucun de ces octets n'existe : si les scans que ces fiches décrivent étaient déposés tels quels, le magasin passerait de 5,4 Mo à plus de 217 Mo.
- **`courriers`** : 34 fiches, 12 791 caractères, 25 portent `numerise: true` et aucune ne porte de fichier (la case dit qu'un scan existe, rien ne l'ouvre).
- **Le magasin entier** : 5 454 586 caractères JSON en mémoire (5,2 Mo), 5 501 024 octets lus de `api/magasin.php` en 160 ms (médiane de trois lectures, localhost). Plus grosses collections : `factures` 762 902, `demandesAnalyses` 311 067, `planning` 275 231.
- **Dix scans de 500 Ko déposés en base64** : la lecture du magasin passe à 12 330 748 octets (+6 829 724 octets, +124 %) et 233 ms. Chaque poste relit le magasin entier à chaque chargement de page : un scan de 500 Ko coûte 683 Ko à CHAQUE page de CHAQUE poste, tant qu'il est dans le magasin.
- **Marge de quota du navigateur : sans objet depuis la suppression de la seconde destination.** Le code de `store.js` (`ecrire`) le dit : « PAS DE SECONDE DESTINATION. Autrefois le magasin retombait sur le localStorage ; cette branche est retirée. Sans serveur, il n'y a pas d'écriture. » Mesuré : la clé de session est la seule écrite en `localStorage` (133 caractères) et la marge de `localStorage` est de 5 232 640 caractères, intacte. Le CLAUDE.md qui décrit un repli navigateur est en retard sur le code (constat, E2481). La contrainte réelle est donc le POIDS DU MAGASIN transporté, pas un quota.
- **Conséquence pour D1** : « repli sans serveur » signifie ici : sans serveur joignable, un dépôt est REFUSÉ en le nommant (comme toute écriture) ; la lecture des fiches anciennes qui portent encore un `donnees` base64 reste possible (affichage de ce qui est déjà en mémoire), et rien ne casse les bancs qui tournent sans écrire.

## Étapes
### Lot D0 : mesure [FAIT 12/11/2026]
- Chiffres ci-dessus. Script : `build/mesure-quota-documents.js` (rejouable, base isolée).
### Lot D1 : stockage de fichiers [FAIT 12/11/2026, maquette]
- Fichiers : `api/fichiers.php` (dépôt, lecture, chemin ; empreinte SHA-256 recalculée par le serveur ; session obligatoire ; règle par famille ; journal serveur `acces_fichiers`), `api/_pdf_texte.php` (extracteur local, lot D4), `api/regles-fichiers.json` ENGENDRÉ par `build/gen-regles-fichiers.js` depuis `packages/rbac/data/rbac.json` et `data.js`, `.gitignore` (`prototype_html/api/fichiers/`), `build/_banc.js` (dossier de fichiers PAR BANC, comme la passerelle SMS), `api/banc.php` (deux altérations de banc, fermées hors `SIGH_BANC=1`), `assets/js/modules/fichiers.js` (service client, empreinte, visionneuse), `assets/js/data.js` (`D.DOCUMENTS` : formats, taille par défaut, types et zones), `assets/js/store.js` (`VERSION` 82, `LIBELLES.fichiers`, reprise de ce qui porte un fichier, migration du base64), schéma relationnel régénéré (`build/gen-schema-pg.js`), `docs/architecture/DICTIONNAIRE-DONNEES.md`.
- Données : collection `fichiers` (empreinte, taille, première date, nombre de références, texte indexé), champ `fichier` d'un courrier ou d'un document patient (`sha256`, `nom`, `nomNormalise`, `mime`, `taille`, `pages`, `texteIndexe`, `deposePar`, `deposeLe`), `fichiersRetires` (historique d'une pièce retirée), `numerise` d'un courrier DÉRIVÉ de `fichier`.
- Vérification : scénarios Vague 152 (serveur) et 153 (migration, restauration) ; `projection --verifier` 117 collections, 11 668 fiches, 0 écart ; le magasin ne porte plus un octet de base64 après la migration (5 564 938 octets avec deux scans en base64, 5 512 146 après, 5 510 135 sans scan) ; empreinte vérifiée AVANT retrait ; SHA-256 identique après restauration.
### Lot D2 : courriers [FAIT 12/11/2026, maquette]
- Fichiers : `assets/js/modules/m13-administration.js` (fiche, zone d'import, aperçu, téléchargement, retrait annulable, chemin local, fiche imprimée), `assets/js/modules/fichiers.js` (visionneuse, zone d'import, refus nommés), `assets/js/nav.js` (script de l'écran), réglage de la taille maximale (`documentsBornes`, défaut 10 Mo « à valider ») dans « Paramètres système ».
- Vérification : scénarios Vague 154 et 155.
### Lot D3 : dossier patient [FAIT 12/11/2026, maquette]
- Fichiers : `assets/js/modules/m1-patients.js` (`m1-documents` : même geste, vue unifiée, journal de consultation), `assets/js/parcours.js` (`PR.peutVoirDocument`, droit par zone), `assets/js/data.js` (zones des types).
- Droit : le droit d'IMPORT par jeu (`N.IMPORTS`, IMP-A) est celui d'un FICHIER TABLEUR de lignes ; déposer un scan sur une fiche est un autre geste. Il suit donc le droit de l'écran (`editer` pour déposer, `annuler` pour retirer) auquel s'ajoute la zone du type de document (l'accueil dépose une pièce d'identité, ne lit pas un compte rendu). Hypothèse à confirmer : E2487.
- Vérification : scénarios Vague 156, audit RBAC ciblé 0 promesse.
### Lot D4 : recherche avancée [FAIT 12/11/2026, maquette]
- Fichiers : `api/_pdf_texte.php`, `assets/js/ui.js` (`searchExtra` du tableau), `assets/js/modules/_kit.js` (`recherche` de `K.crud`), les deux registres.
- Vérification : scénario Vague 157 (un PDF à couche texte se retrouve par un mot de son corps ; un scan image est dit « texte non indexé », jamais « aucun résultat »).
### Lot SAUV-F : sauvegarde et restauration du dossier de fichiers [FAIT 12/11/2026, maquette]
Constat E2491 : la sauvegarde nocturne ne copiait pas `api/fichiers/`. Trois tâches du planificateur (`sauvegarde_nocturne` désormais sensible à la destination, `sauvegarde_fichiers` horaire et incrémentale, `controle_fichiers` nocturne), une destination RÉGLABLE (`_reglages.sauvegardeFichiers`, défaut `api/sauvegardes/` dit « même disque »), `api/restaurer.php --fichiers`, `api/controler_fichiers.php`, la carte de sauvegarde de `m14-taches`. Scénarios Vagues 158 à 162. Écarts E2492 à E2499, décisions à confirmer : `DECISIONS-A-VALIDER.md` section O.

### Lot A1 : antériorités [FAIT 13/11/2026, maquette]
- Fichiers : `assets/js/modules/m5-laboratoire.js` (`SIGH.laboAnteriorites`, comparatif à mesure comparée et trois antériorités, variation, courbe, impression du comparatif, colonne « Antériorités » de la fiche imprimée), `assets/js/charts.js` (options de `G.ligne`).
- Vérification : scénarios Vague 163 à 165, six mutations rouges, avant/après. Écarts E2510 à E2514 (hypothèses, un défaut de périmètre corrigé à l'impression, deux constats hors lot).
### Lot A2 : seuils de variation brutale [FAIT 13/11/2026, maquette]
- Fichiers : `assets/js/parcours.js` (`SIGH.laboSeuils` : enregistrer, valider, abandonner, seuil en vigueur à une date, alerte), `assets/js/store.js` (collection `seuilsDelta`, garde d'immutabilité, reprise à la montée de `VERSION` 83), `assets/js/modules/m5-laboratoire.js` (section « Seuils de variation brutale » de `m5-valeurs-reference`, alerte au comparatif et à l'écran de validation biologique), schéma `m5.seuils_delta`.
- Vérification : scénarios Vague 166 à 168, douze mutations rouges, avant/après. Écarts E2515 à E2519, décisions à confirmer : `DECISIONS-A-VALIDER.md` section Q.
### Lot D5 : poste Flutter [À FAIRE, hors de ce brief]
- Domaine, vecteurs, composant de lecture PDF, fichiers par empreinte dans la synchronisation (EF-SYNC-18). Le vecteur `administration.json` n'est PAS régénéré par ce brief (la case `numerise` de la fiche courrier disparaît à la saisie : sa régénération rougirait le poste jusqu'à D5).

## Commandes
- `service postgresql start`, puis banc isolé : `SIGH_PORT_PHP=9210 SIGH_BASE_TEST=sigh_banc_d1 SIGH_PORT_TEST=9211 CHROME_PATH=/opt/pw-browsers/chromium node build/test-fonctionnel.js --seul=Vague_152|Vague_153|…` (`ps aux | grep "[p]hp -S"` avant de croire un résultat).
- `node build/mesure-quota-documents.js` : la mesure D0.
- `node build/gen-regles-fichiers.js` : la règle par famille du serveur (aussi lancée par `npm run pages`).
- `php api/projection.php --verifier` : parité du magasin et des tables.
- `node build/audit-rbac.js --pages=m13-courriers,m1-documents` : 0 promesse.
- `npm run lint`, `npm run build` (safelist avant Tailwind), `node build/check.js --pages=m13-courriers,m1-documents`.

## Schéma et données
`VERSION` 81 vers 82 (une seule constante). Collection nouvelle `fichiers` ; champs nouveaux sur `courriers` et `documentsPatient`. Une montée de `VERSION` ré-amorce le jeu : la reprise garde les fiches qui portent déjà un fichier ou un base64 (comme les postes de l'organigramme et les prix), puis la migration range les base64 dans le dossier de fichiers.

## Synchronisation
Aucune opération nouvelle au journal dans ce brief. Les fichiers voyageront à part, par empreinte (EF-SYNC-18), au lot D5 ; `fichiers` est une collection de métadonnées (ajout seul par empreinte).

## Hors périmètre
OCR (phase 2, après essai sur trois vrais scans), recherche par le sens (NON, Q8), pilotage du scanner, poste Flutter, antériorités et seuils.

## Risques
| Risque | Signal précoce | Parade |
|---|---|---|
| Fichier altéré sur disque | `FICHIER_ALTERE` à la lecture | empreinte recalculée à chaque lecture, refus nommé, jamais servi |
| Migration qui perd un scan | base64 retiré sans empreinte vérifiée | vérification à la relecture AVANT retrait, mutation qui rougit la sonde |
| Règle serveur en retard sur la matrice | `regles-fichiers.json` différent de `rbac.json` | engendré par le build, comparé par un scénario |
| Texte de PDF non extrait | « texte non indexé » sur un PDF qui en porte | dit à l'écran, jamais « aucun résultat » |

## Définition de « fini »
lint + build + check ciblé + scénarios 152 à 157 + audit RBAC ciblé verts, `projection --verifier` 0 écart, mutations rouges nommées, CLAUDE.md et `ECARTS-MAQUETTE.md` à jour. La suite complète est lancée par le relecteur.

## Résultat du lot (12/11/2026)
Scénarios Vagues 152 à 157 : 6 sur 6, 110 vérifications ; rejoués sur l'arbre d'avant : 0 sur 6 ; 8 mutations rouges, SHA-256 identique après restauration ; audit RBAC ciblé (`m13-courriers`, `m1-documents`) 0 promesse, 0 lecture non dite ; `check` ciblé 0 erreur JS, 0 lien cassé ; `projection --verifier` 0 écart. La suite complète n'a PAS été lancée par ce lot. Écarts E2481 à E2491, décisions à confirmer section M de `DECISIONS-A-VALIDER.md`.
