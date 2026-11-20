# Audit : courriers (M13) et archivage des documents patients (M1)

Date : 07/11/2026. Lecture seule. Demande de la Direction : visualisation des scans dans un panneau latéral (offcanvas) à onglets, avec télécharger et imprimer, pour les courriers et pour les documents patients.

## 1. Périmètre examiné

- Courriers : `m13-courriers`, `prototype_html/assets/js/modules/m13-administration.js:38-163`, semence `data-seed.js:1853-1890`, poste `apps/poste/lib/modules/m13/adm_registres.dart:22-160`.
- Documents patients (`documentsPatient`, M1, NE PAS confondre avec la GED) : `m1-documents` `modules/m1-patients.js:1425-1700`, plan `m1-numerisation` `:1705-1760`, poste `apps/poste/lib/modules/m1/documents.dart` (500 lignes).
- GED établissement (`documents`, GED, vu seulement pour la distinction) : `modules/ged.js:38-199`, semence `data-seed.js:1927-1960`.
- Briques : `U.drawer` `ui.js:215-253`, `U.tabs` `ui.js:372-413`. Droits : `packages/rbac/data/rbac.json` (`parRole[rôle][écran] = [voir, éditer, annuler]`).

## 2. Fonctions demandées

| Fonction | Maquette | Poste | Manque | Preuve |
|---|---|---|---|---|
| Dépôt PDF/PNG/JPEG, taille | Documents patients : oui (+WEBP), avertit au-delà de 2 Mo sans refuser. Courriers : NON | Documents : oui (`file_picker`) | Aucun dépôt sur les courriers ; pas de plafond | `m1-patients.js:1581-1611`, `:1596`; `m13-administration.js:88-89` (case `numerise` seule); `documents.dart:96-143` |
| Conservation dans le poste | Documents : base 64 dans le magasin | Idem (champ `donnees`) | Courriers : aucun fichier ; semence `fichier:null`, `donnees:null` pour tous | `m1-patients.js:1638,1450-1457`; `documents.dart:186-196` |
| Prévisualisation PDF/image | Modale : `iframe` PDF, `img` image | Image seule ; PDF : simple texte, pas d'aperçu | Zoom, rotation, pagination, multipages absents partout | `m1-patients.js:1652-1664`; `documents.dart:205-206` |
| Panneau latéral à onglets | NON : modale (`U.modal`) pour M1 ; GED a un `U.drawer` mais sans onglets ni vrai aperçu | NON : modale | Offcanvas à onglets Document, Métadonnées, Historique, Pièces liées | `m1-patients.js:1665`; `ged.js:141-173`; `documents.dart:238` |
| Télécharger | NON (aucune occurrence de `download`) | NON | Nom de fichier d'origine (`fichier`) et type MIME à restituer | grep `download` sur `m1-patients.js`, `m13-administration.js`, `ged.js` : 0 |
| Imprimer un scan | Image : sur `P.etat` (en-tête et pied normalisés). PDF : texte « Reproduction du document… » sans le scan | Idem : jamais le scan | Impression du PDF scanné ; courriers : impression de la fiche seulement | `m1-patients.js:1668-1678`; `documents.dart:226-240`; `m13-administration.js:114-130` |
| Recherche et filtres | Documents : recherche texte, type, fichier déposé. Courriers : sens, traitement, service | Équivalent | Période, expéditeur/destinataire, statut d'archivage, service pour les documents | `m1-patients.js:1503-1512`; `m13-administration.js:101-105` |
| Statuts | Documents : `valide`/`en_attente`. Courriers : `en_attente`/`en_cours`/`traite` | Idem | « Reçu », « À traiter », « Archivé » absents du vocabulaire courrier | `m1-patients.js:1573`; `m13-administration.js:87` |
| Numérotation annuelle | Courriers : `ARR/DEP-AAAA-NNNN` par sens et année (E538). Documents : `GED-NNNNN` hors année | Courriers idem | Documents : `all().length + 1`, sans année | `m13-administration.js:96`; `m1-patients.js:1635` |
| Registre arrivée/départ, accusé | Oui, accusé = case à cocher | Oui | Accusé sans date ni auteur | `m13-administration.js:88`; `adm_registres.dart:121` |
| Traçabilité RG-12 | Via `colDocs().insert/archive` du magasin (journal) | Via magasin | Aperçu, téléchargement et impression NON journalisés (`S.journaliserAcces` existe) | `store.js:4201`; `m1-patients.js:1640,1692` |
| Archivage RG-14, corbeille | Documents : `archive(id, motif)` obligatoire, annulable ; libellé corbeille posé. Courriers : l'archivage vient de `K.crud` | Idem | Courriers : onglet Archivés de `K.crud` non sondé | `m1-patients.js:1684-1697`; `store.js:4046` |
| RBAC | Voir §3 (défaut 3) | Même matrice | Voir §3 | `rbac.json` |
| Hors ligne | Oui (aucune requête) ; PDF dans un `iframe` en `data:` | Oui | Poids dans PostgreSQL non mesuré | `m1-patients.js:1431` |

## 3. Défauts réels

1. **Grave. Courriers sans aucun scan.** Le registre est dit « numérisé » (`m13-administration.js:40`) mais « Document numérisé » n'est qu'une case. Aucun fichier ne se dépose, donc rien à visualiser, télécharger ou imprimer. Même en poste (`adm_registres.dart:122`).
2. **Grave. Visualisation en modale, non en offcanvas à onglets** (demande de la Direction), pour M1 comme pour les courriers. La GED a un tiroir, mais l'aperçu y est un cadre vide : les 40 pièces semées n'ont pas de fichier (`ged.js:144-148`, aucun `donnees` au seed).
3. **Moyen. RG-13 : la bibliothèque M1 n'est pas filtrée par nature.** `reception` (`doc` 110) lit et écrit « Résultat de laboratoire », « Compte rendu médical », « Imagerie » (`TYPES_DOCUMENT`, `m1-patients.js:1434`) alors que sa zone est l'identité. À arbitrer : même droit pour `da` et `admin`. Non vérifié : le détail de la fiche du rôle `reception` au-delà de `rbac.json`.
4. **Moyen. Télécharger absent.** Aucun nom de fichier restitué alors que `fichier` et `format` sont stockés.
5. **Moyen. Impression d'un PDF scanné impossible** : seul un texte de substitution sort (`m1-patients.js:1677`, `documents.dart:240`). Le pied normalisé n'est donc pas porté sur le scan.
6. **Moyen. Poste en retrait.** PDF non prévisualisé (`documents.dart:205-206`), pas de zoom ni de rotation. Les courriers n'ont rien à porter.
7. **Moyen. Numérotation des documents patients** : `'GED-' + (all().length + 1)` (`m1-patients.js:1635`). Préfixe identique à celui de la GED, sans année, et non unique si une fiche est retirée de `all()`. La GED, elle, emploie `DOC-2026-` (`data-seed.js:1946`), et la collision de noms prête à confusion. Le plus simple : `C.referenceSuivante`, déjà employé par les courriers.
8. **Moyen. Taille : avertissement seulement** (`:1596`). Le message parle du « stockage du navigateur » alors que le magasin est désormais PostgreSQL (vague 66). Aucun plafond serveur mesuré.
9. **Mineur. `depose` saisi à la main**, préremplit `S.currentUser()` mais reste éditable (`:1575,1614`) : RG-12 prévoit « aucune action anonyme », le déposant devrait être figé.
10. **Mineur. Accès non tracés** : consulter ou imprimer un document médical n'écrit aucune ligne d'audit (RG-12, RG-13), alors que `journaliserAcces` existe.
11. **Mineur. Courriers : filtres incomplets** (pas de période, pas de recherche expéditeur dédiée au-delà de `searchable` du kit, `m13-administration.js:101-105`). Service limité à 5 valeurs alors que le formulaire en propose 7.
12. **Mineur. Plan de numérisation en dur** (`TOTAL = 18000`, `traites = 4230`, `:1710-1711`) : chiffres non calculés depuis `documentsPatient`. À dire ou à relier.
13. **Mineur. Courriers : seule la série « arrivée/départ »** ; pas de pièces liées (réponse à un courrier, facture, réunion), alors que l'écran promet « suivi des réponses » (`:40`).

## 4. Plan de correction

**Lot A (maquette, composant partagé)** : `K.visionneuse(doc, opts)` dans `modules/_kit.js`, posée sur `U.drawer` (largeur `max-w-3xl`) et `U.tabs` : onglets Document, Métadonnées, Historique (journal filtré par entité), Pièces liées. Aperçu image avec zoom et rotation (CSS `transform`), PDF en `iframe` avec `#page=N` (précaution : pagination native du lecteur), boutons Télécharger (`<a download>` sur le `data:` avec `fichier`) et Imprimer (impression de l'image ou du PDF, via `P.etat` pour l'en-tête et le pied). Journalisation `S.journaliserAcces` à chaque ouverture, téléchargement et impression. Attention au piège des tiroirs (`el` enfants multiples) et au gabarit `.card`. Fichiers : `_kit.js`, `ui.js` (au besoin), `build/safelist` via `gen-safelist`.

**Lot B (maquette, courriers)** : champ `pieces` (PDF/PNG/JPEG, plusieurs fichiers) avec les mêmes limites que M1 ; vocabulaire de statut aligné (reçu, à traiter, traité, archivé) ; période, expéditeur et destinataire en filtres ; accusé de réception daté et signé ; pièces liées. Fichiers : `m13-administration.js`, `data-seed.js`. Incrémenter `VERSION` si la forme change.

**Lot C (maquette, documents patients)** : brancher la visionneuse sur `m1-documents` (au lieu de `previsualiser`), numérotation `C.referenceSuivante('DOCP-' + année + '-')`, déposant figé, filtre période, statut archivé en filtre, plafond de taille nommé. Question RG-13 en attente de la Direction. Fichiers : `m1-patients.js`, `store.js` (LIBELLES), `rbac` si arbitrage.

**Lot D (poste Flutter)** : `m13/adm_registres.dart` et `m1/documents.dart` : panneau latéral (`Drawer`/`endDrawer` ou équivalent du kit) à `TabBar`, aperçu PDF et image (`InteractiveViewer` pour zoom et rotation), téléchargement (`file_picker.saveFile`), impression (le paquet `pdf` est déjà au pubspec, `printing` est absent : à ajouter ou à contourner). Parité N1 : lire les libellés de la maquette corrigée.

**Sondes à écrire** (`build/test-fonctionnel.js`, après le scénario 75) : le tiroir s'ouvre avec 4 onglets ; Télécharger porte le nom d'origine ; Imprimer produit un en-tête et un pied ; ouverture journalisée (lire la dernière entrée du journal, pas sa longueur) ; dépôt d'un PDF puis d'un PNG, relecture après rechargement ; numérotation sans doublon après archivage ; réception refusée sur un type médical si arbitré ; audit RBAC à 0 promesse.

## 5. Questions pour la Direction

1. Le courrier porte-t-il plusieurs pièces jointes, et lesquelles doivent s'imprimer (la lettre seule, ou la lettre et les annexes) ?
2. La réception (accueil) peut-elle lire les résultats et comptes rendus de la bibliothèque documentaire patient (RG-13) ?
3. Statuts du courrier : « reçu, à traiter, traité, archivé » remplacent-ils « en attente, en cours, traité » (changement de vocabulaire) ?
4. Taille maximale d'un document déposé, et durée de conservation d'un courrier (la GED affiche 5 à 10 ans par pièce) ?
5. Un document patient a-t-il une numérotation annuelle propre (série à distinguer de la GED établissement) ?

Audit lu seulement, aucun code modifié
