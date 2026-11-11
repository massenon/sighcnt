# PRD : documents numérisés (courriers M13, dossier patient M1) et suivi d'antériorité des résultats (delta check)

Statut : **brouillon** du 11/11/2026, à arrêter par la Direction, le Biologiste médical et la DAF
Sources : demande de la Direction du 11/11/2026 (import de documents scannés à part, aperçu à l'écran, recherche plein texte et sémantique, comparatif ancien et nouveau résultat) · état de la maquette mesuré dans cette session (`m13-courriers`, `m1-documents`, `m1-numerisation`, `m5-resultats-comparatif`, fiche de résultats imprimée) · `docs/specs/SPEC-protocole-synchronisation.md` (fichiers par empreinte) · `PRD-IMP-bouton-importer-par-ecran.md` (jeu `courriers`)

Ce PRD n'est pas écrit avec l'outil `sdlc-kit` (aucun coffre `.sdlc` dans ce dépôt) : il suit la forme des PRD de `docs/prd/`.

## 1. Problème

Le logiciel ne pilote pas le scanner. L'agent numérise avec l'outil de son poste (PDF, JPG, PNG), puis doit **importer** le fichier et le **retrouver** ensuite. Trois constats, mesurés :

1. **Courriers (M13)** : le registre porte une case « Document numérisé » (`numerise`), mais **aucun fichier** n'est rattaché. La case dit qu'un scan existe ; rien ne permet de l'ouvrir.
2. **Dossier patient (M1)** : les documents numérisés sont déposables et visibles (aperçu PDF en `iframe`, image en `img`), mais le fichier est conservé **en base64 dans le magasin JSON**. C'est la contrainte du quota (CLAUDE.md, vagues 62 et 64) : le magasin pesait 4 786 Ko pour ~330 Ko de marge. Dix scans de 500 Ko le saturent. L'écran avertit à 2 Mo, mais ne retire pas la cause.
3. **Antériorité des résultats** : la fiche de résultats imprimée porte déjà une colonne « Antériorités », **mais elle s'imprime vide** (le commentaire du code le dit : « elle existe même vide »). L'écran `m5-resultats-comparatif` compare **deux** mesures avec une flèche et un écart absolu : ni plusieurs antériorités, ni pourcentage, ni alerte de variation brutale, ni courbe.

Coût de ne rien faire : des courriers dont le scan n'est pas retrouvable le jour d'un litige, un magasin qui sature au premier lot de scans, et un clinicien qui doit ouvrir deux écrans pour lire une évolution.

## 2. Objectifs et non-objectifs

**Objectifs**
- O1. Un **dépôt de fichier** sur la fiche courrier et sur le dossier patient, par glisser-déposer ou sélection, avec nom de stockage normalisé et empreinte SHA-256.
- O2. Un **aperçu immédiat** sans téléchargement (image avec zoom et rotation, PDF), et un téléchargement du fichier d'origine.
- O3. Des fichiers **hors du magasin JSON** : le magasin ne garde que les métadonnées.
- O4. Une **recherche** par métadonnées et filtres sur les deux registres, et sur le texte des PDF qui portent une couche texte.
- O5. Un **suivi d'antériorité** : N antériorités, variation, alerte de variation brutale, courbe, dans le comparatif **et** sur la fiche imprimée.

**Non-objectifs (cette version)**
- Piloter le scanner (TWAIN, WIA, SANE) : le flux reste « scanner à part, puis import ».
- **Reconnaissance de caractères (OCR)** des scans image : proposition en phase 2, à arbitrer (section 9).
- **Recherche sémantique** : voir section 9, non recommandée en l'état.
- Valeurs seuils de delta check **inventées** : aucun document n'en fournit (section 9).
- Remplacer la GED de l'établissement (`documents`) : elle reste distincte des documents patient (vague 9 à 13).

## 3. Utilisateurs et rôles

| Profil | Courriers | Documents du dossier patient | Antériorités |
|---|---|---|---|
| Agent administratif, DAF, Direction | dépose, consulte, télécharge | aucun accès aux pièces médicales (RG-13) | non |
| Accueil | non | dépose Pièce d'identité, Carte d'assurance (zone 1) ; ne lit pas le reste | non |
| Médecin, infirmier, sage-femme | non | consulte selon le RBAC métier existant | lit les résultats **rendus** |
| Biologiste médical | non | non | lit, règle les seuils, voit l'alerte à la validation |
| Administrateur | tout | tout | tout |

Les droits **ne sont pas inventés ici** : un document patient suit le droit de l'écran qui le porte (`m1-documents`, `m1-numerisation`), un courrier suit `m13-courriers`. Un droit **importer** distinct de **éditer** s'ajoute à la fiche RBAC selon `PRD-IMP` (voir, importer, annuler).

## 4. Parcours

1. **Courrier** : l'agent scanne. Dans « Courriers (départ / arrivée) », il crée la fiche (numéro `ARR-AAAA-NNNN` ou `DEP-AAAA-NNNN`, déjà en place), glisse le fichier dans la zone d'import, le serveur le range sous une clé d'empreinte et la fiche affiche l'aperçu. La case « Numérisé » **se coche seule** quand un fichier est rattaché, elle ne se saisit plus.
2. **Dossier patient** : même geste depuis `m1-documents`, avec le type de document de la liste existante (ordonnance, résultat, compte rendu, consentement, imagerie, etc.).
3. **Consultation** : depuis la fiche, aperçu dans un tiroir (offcanvas) ou une modale large, téléchargement du fichier d'origine sous le nom normalisé.
4. **Recherche** : une zone de recherche plein texte sur les métadonnées (objet, correspondant, type, nom du patient, observations, nom du fichier) plus les filtres existants ; cherche aussi dans le texte extrait des PDF qui en portent.
5. **Antériorité** : au comparatif, le patient et l'examen choisis affichent la mesure du jour et jusqu'à trois antériorités, la variation, une courbe au clic sur une variable ; la fiche imprimée remplit sa colonne « Antériorités ».

## 5. Exigences fonctionnelles

| N° | Exigence |
|---|---|
| EF-DOC-1 | Formats acceptés : PDF, JPEG, PNG (WEBP déjà accepté au dossier patient, conservé). Un autre format est refusé **en le nommant** avec le geste de correction. |
| EF-DOC-2 | Taille maximale **réglable en paramètre**, défaut proposé 10 Mo par fichier, « à valider ». Au-delà, refus nommé avec le conseil de numériser en résolution plus basse. |
| EF-DOC-3 | Le fichier est rangé **hors du magasin** (serveur : dossier de fichiers ignoré par git ; poste : dossier de données) sous la clé `sha256`. Le magasin garde : empreinte, nom d'origine, nom normalisé, type MIME, taille, nombre de pages si PDF, déposé par, date. |
| EF-DOC-3b | **Chemin local indiqué** (décision du 11/11/2026) : la fiche d'un courrier ou d'un document patient **affiche le chemin du fichier sur le poste** (dossier de données du poste, puis le nom de stockage), avec un bouton « Copier le chemin » et un bouton « Ouvrir le dossier » quand le système le permet. Le chemin est celui **de ce poste** : sur un autre poste, c'est le chemin de sa propre copie, et si la copie n'est pas encore arrivée, la fiche dit « Fichier pas encore reçu sur ce poste » au lieu d'un chemin faux. La conservation est illimitée : aucune purge, jamais. |
| EF-DOC-4 | **Nom normalisé** : `AAAA-MM-JJ_<ARR\|DEP>_NNNN.<ext>` pour un courrier (date de la fiche, rang de la référence), `AAAA-MM-JJ_<CODE patient>_<type>_NNN.<ext>` pour un document patient. Le nom est un nom de **téléchargement** : la **référence** de la fiche ne change jamais (E530, E538). |
| EF-DOC-5 | **Doublon** : un fichier de même empreinte déjà rattaché à la même fiche est refusé en nommant la pièce existante ; sur une autre fiche, il est accepté après avertissement nommé. |
| EF-DOC-6 | **Aperçu** : image avec zoom, rotation et ajustement ; PDF dans le lecteur du navigateur. Aucune bibliothèque chargée depuis Internet : tout est vendoré localement (CLAUDE.md). |
| EF-DOC-7 | **Une pièce rattachée ne se supprime pas** (RG-14) : on la retire de la fiche par archivage annulable ; le fichier reste, l'empreinte reste au journal. |
| EF-DOC-8 | **Journal** (RG-12) de chaque dépôt, consultation et téléchargement d'un document patient : qui, quand, quelle empreinte. La consultation d'un courrier est journalisée aussi. |
| EF-DOC-9 | **Vue unifiée du dossier patient** : l'onglet Documents liste les scans **et** renvoie vers les pièces **produites** par le logiciel (ordonnances, résultats rendus, comptes rendus, imagerie). Les pièces produites ne sont **jamais copiées** : c'est une **vue**, pas une seconde collection (leçon des visites et des certificats). Les consentements sont des scans typés. |
| EF-DOC-10 | **Recherche** plein texte sur les métadonnées des deux registres, avec filtres de dates. Le texte d'un PDF est extrait **à l'import** quand le PDF porte une couche texte ; sinon la pièce est marquée « texte non indexé » (jamais « aucun résultat »). |
| EF-ANT-1 | Le comparatif accepte **jusqu'à trois antériorités** d'un même examen, rendues seulement (validées biologiquement), dans l'ordre chronologique, chaque colonne **aux bornes de son époque** (plages par lot datées, déjà en place). |
| EF-ANT-2 | Chaque variable affiche la **variation** à la mesure précédente : sens (↑ ↓ =), écart absolu, pourcentage. Une valeur non numérique (qualitative) se compare en texte, sans pourcentage. |
| EF-ANT-3 | **Alerte de variation brutale (delta check)** : seuil **par variable, en base, réglable**, versionné par date comme les plages. **Aucun seuil par défaut** : un seuil vide signifie « pas d'alerte configurée », jamais « zéro ». L'alerte se voit au comparatif et à l'écran de validation biologique, **pas** sur le résultat que lit le prescripteur. |
| EF-ANT-3b | **Bouton Valider sur les seuils** (décision du 11/11/2026) : chaque seuil se saisit puis se **valide**. Deux états visibles : **Enregistré** (saisi, sans effet : aucune alerte) et **Validé** (en vigueur). Le bouton **Valider** fait passer un seuil de Enregistré à Validé ; **Enregistrer** garde l'état Enregistré. Seul un seuil **Validé** déclenche une alerte. Valider est le geste du Biologiste médical (liste de rôles de la famille, revérifiée par le moteur, jamais le simple droit d'éditer), tracé avec auteur, date et motif. Modifier un seuil Validé crée une **nouvelle version** datée ; l'ancienne reste lisible. Ce mécanisme est celui de la validation par modale déjà en place pour les référentiels (`K.ecrireValidable`). |
| EF-ANT-4 | **Courbe de tendance** par variable (Chart.js déjà vendoré), sur tous les résultats rendus du patient pour cet examen. |
| EF-ANT-5 | La **fiche de résultats imprimée** remplit sa colonne « Antériorités » (mesure et date de l'antériorité la plus récente, par variable). Une variable sans antériorité imprime « Aucune antériorité », non un blanc. |
| EF-ANT-6 | Le périmètre reste celui du **RBAC métier** (`peutVoirResultat`) : on ne compare que ce qu'on a le droit de voir. |

## 6. Données

- `courriers` : champ `fichier` (objet : `sha256`, `nom`, `nomNormalise`, `mime`, `taille`, `pages`, `texteIndexe`) ; `numerise` devient **dérivé** de `fichier`.
- `documentsPatient` : mêmes champs ; l'ancien champ `donnees` (base64) est **migré** vers le dossier de fichiers au premier démarrage de la nouvelle version, puis retiré du magasin. La migration vérifie l'empreinte avant de retirer le base64.
- Nouvelle collection `fichiers` (empreinte, taille, première date, nombre de références) pour le dédoublonnage et la purge contrôlée ; **aucune purge physique** sans décision (RG-14).
- Paramètres : taille maximale, formats, seuils de delta check par variable (`seuilsDelta`, versionnés par date).
- `VERSION` incrémentée ; collections ajoutées à `LIBELLES` ; schéma relationnel régénéré ; **mesure du quota avant semis**.

## 7. Hors ligne, synchronisation et sécurité (section obligatoire)

- **Hors ligne d'abord** : le fichier se range sur le poste, sans réseau. Le poste désigné comme mère l'envoie au relais ; la spec de synchronisation prévoit déjà les **fichiers à part, par empreinte SHA-256, métadonnées d'abord, binaire ensuite avec reprise** (EF-SYNC-18). Ce PRD s'y conforme, il n'invente pas de second canal.
- **Mobiles** : aucun document patient ne descend au mobile (RG-13, et le mobile ne porte pas le dossier). Les courriers non plus.
- **Relais opaque** : le binaire transite **chiffré** comme le reste ; le relais ne connaît ni le nom, ni le type, ni le texte.
- **Limite connue à dire** : le serveur PHP de la maquette ne connaît pas la matrice RBAC (CLAUDE.md, vague 66). Le téléchargement d'un document patient est donc protégé par la **session serveur** et par le droit du client, **pas** par une matrice côté serveur. Une règle serveur grossière par famille de collection est proposée (question Q4).
- **Poste Flutter** : le lecteur de PDF n'existe pas dans Flutter comme dans un navigateur ; il faut un composant de rendu PDF local (lot dédié, à choisir). Aucun lecteur n'est supposé.

## 8. Impression et états

La fiche de courrier imprimée mentionne le nom normalisé du fichier et son empreinte abrégée (huit caractères). La fiche de résultats imprimée remplit « Antériorités » (EF-ANT-5). Le comparatif est imprimable avec les mêmes colonnes que l'écran.

## 9. Ce qui n'est pas documenté, et ce qu'on ne devine pas

- **Seuils de delta check** : aucun document de cadrage ne les donne. Ils sont une décision du **Biologiste médical** (la Direction ne signe pas à sa place). Le logiciel les **prévoit vides**.
- **OCR** : les scans image n'ont pas de couche texte (CLAUDE.md : les PDF de `docs/` sont des scans sans couche texte). Indexer leur contenu exige un OCR **local** (Tesseract ou équivalent). Proposition en phase 2, après mesure de la qualité sur trois vrais scans de la clinique.
- **Recherche sémantique** (par le sens) : elle exige un modèle d'embeddings. Hors ligne, c'est un modèle **local** lourd à embarquer sur un poste Windows ; en ligne, c'est un **service externe**, ce qui ferait sortir du texte médical de la clinique, contraire à la règle de confidentialité du projet. **Non recommandée** en phase 1 ; à rouvrir si la Direction veut un modèle local.
- **Durée de conservation** des scans : la décision P2 du 11/11 (« aucune durée de conservation ») vaut pour les copies de fiche de paie. Pour les documents patient et courriers, **à confirmer** (Q6).

## 10. Questions ouvertes (avec recommandation)

| N° | Question | Recommandation |
|---|---|---|
| Q1 | Taille maximale par fichier | 10 Mo, réglable en paramètre |
| Q2 | Le lecteur PDF de la maquette | lecteur natif du navigateur (`iframe`) d'abord, sans dépendance ; PDF.js vendoré seulement si un contrôle fin (rotation, recherche dans le PDF) est exigé |
| Q3 | Visionneuse d'images | une visionneuse légère **écrite pour le projet** (zoom, rotation, déplacement, ajustement) plutôt que Viewer.js, pour ne rien ajouter à la chaîne de licences et rester dans la doctrine « assets vendorés » ; Viewer.js vendoré si la Direction préfère un composant connu |
| Q4 | Contrôle d'accès serveur des fichiers | session obligatoire + règle par famille (courrier, document patient) alignée sur `rbac.json` ; matrice complète côté serveur reste un pas suivant |
| Q5 | Format du nom normalisé | celui de l'EF-DOC-4 ; la **référence** de la fiche ne change pas |
| Q6 | Durée de conservation des scans | à confirmer par la Direction ; le logiciel ne purge rien en attendant |
| Q7 | OCR local en phase 2 | oui, après mesure sur trois scans réels |
| Q8 | Recherche sémantique | non en phase 1 (confidentialité, hors ligne) |
| Q9 | Seuils de delta check | vides par défaut, saisis par le Biologiste médical |
| Q10 | Nombre d'antériorités affichées | trois, réglable |

## 11. Lots proposés

| Lot | Contenu | Preuve exigée |
|---|---|---|
| **D0 mesure** | combien pèsent `documentsPatient` et les scans de démonstration dans le magasin ; marge de quota réelle | chiffres en Ko, avant tout code |
| **D1 stockage de fichiers** | `api/fichiers.php` (dépôt, lecture, empreinte), dossier ignoré par git, migration du base64 de `documentsPatient`, `numerise` dérivé | le magasin perd le base64 ; empreinte vérifiée avant retrait ; `projection --verifier` : 0 écart |
| **D2 courriers** | zone d'import, nom normalisé, aperçu, téléchargement, journal, doublon | scénario au geste : dépôt, aperçu, téléchargement sous le bon nom, doublon refusé nommément |
| **D3 dossier patient** | vue unifiée, types, droits, journal de consultation | audit RBAC : 0 promesse ; l'accueil ne lit pas un compte rendu |
| **D4 recherche** | plein texte sur métadonnées, texte des PDF à couche texte, « non indexé » dit | un PDF avec couche texte se retrouve par un mot de son corps ; un scan image est dit non indexé |
| **A1 antériorités** | N antériorités, variation, courbe, colonne imprimée remplie | un scénario écrit sur le geste, bornes de l'époque respectées |
| **A2 delta check** | seuils par variable versionnés, alerte à la validation | seuil vide : aucune alerte ; seuil posé : alerte ; le prescripteur ne la voit pas |
| **D5 poste Flutter** | domaine, vecteurs, composant PDF, fichiers par empreinte dans la synchronisation | `flutter analyze`, `flutter test`, banc de synchronisation à deux postes |

Mutations à écrire : retirer la vérification d'empreinte à la migration (la sonde doit rougir) ; faire lire un résultat non rendu au comparatif ; donner à l'accueil la lecture d'un compte rendu.

## 12. Indicateurs

- 0 octet de fichier dans le magasin JSON après D1.
- 100 % des courriers « numérisés » ouvrent un aperçu.
- 0 résultat non rendu lu au comparatif ; 0 alerte de delta check sans seuil posé.
