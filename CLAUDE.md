# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Monorepo (initialisé le 17/10/2026)

Le dépôt `sighcnt` est un **monorepo npm** (ADR-0002) : `apps/` (poste, hub, vitrine), `packages/`
(domaine, schema, rbac, sync, referentiels, impression), `infra/`, `docs/` et la maquette gelée
`prototype_html/` — hors workspaces, avec son outillage propre (`npm run prototype:*` depuis la
racine). **La cible est hors ligne d'abord** : postes autonomes (SQLite chiffré), hub de clinique
en étoile (PostgreSQL), synchronisation par **journal d'opérations** — lire
`docs/architecture/ARCHITECTURE-CIBLE.md` et `docs/architecture/adr/` avant toute décision de
structure. Les skills SDLC du dépôt (`.claude/skills/` : `/prd`, `/adr`, `/spec`, `/plan`,
`/test-plan`, `/review`, `/release`) écrivent dans `docs/` et portent la doctrine ci-dessous.

**Jamais versionnés** : `node_modules`, `*.local.php`, `.env`, exports `*.sql` (voir `.gitignore`).
Le mot de passe PostgreSQL commis le 17/10/2026 dans `prototype_html/api/config.local.php` est à
**changer** sur le poste : il reste dans l'historique du commit initial.

Le reste de ce fichier décrit la **maquette** (`prototype_html/`) : sa doctrine, ses règles de
gestion et ses pièges s'appliquent tels quels au portage vers `apps/poste`.


## État du dépôt

Trois ensembles : la documentation de cadrage (`docs/`, plus les notes d'exigences `draf1.txt` / `draft2.txt`), le prototype applicatif **`prototype_html/`** — 305 pages couvrant les 14 modules — et le site vitrine public **`frontend_html/`** — 25 pages engendrées depuis `build/site.js`.

**Trois dossiers de cadrage supplémentaires, reçus fin août 2026** — à lire avant toute décision sur la cible :

- **`Instructions/`** — INSTRUCTION1 (≈ INSTRUCTION2), INSTRUCTION3, p15.txt : cartographie cible complète (méga-menu avec domaine ACCUEIL dédié, matrice RBAC **15 rôles** dont Chirurgien et Anesthésiste à créer, registre de bugs 0-16, ~45 écrans à créer, stats centralisées sous PIL).
- **`suite/`** — rapport officiel maternité du 27/08/2026 (docx + PDF) et formulaires obstétricaux nationaux scannés (dossier obstétrical, grille CPN, courbe poids/IMC, état du nouveau-né/délivrance, fiche de surveillance intégrée, partographie) : la refonte M4 — CPN structurée SP1-5/MILDA/GAR, partogramme, PC/PT/Apgar 1-5-10, CPoN 1-3, SONUB/SONUC 10 fonctions, PF 15 méthodes + A/N, PTME 4 volets.
- **`reunions/`** — observations du labo (fiche de demande d'examen, stats des examens multi-axes, paramètres d'examen modifiables selon réactif), bulletin d'analyses et fiche de résultats 2026080411 (déjà intégrés en vague 23).

L'audit du 31/08/2026 et le plan en 10 phases vers cette cible : https://claude.ai/code/artifact/e7b26030-30f3-4d4a-a2ea-342ced04404a

**Quatre arbitrages rendus par la Direction le 31/08/2026 — ils font foi, ne pas les re-questionner :**

1. **IFU/RCCM : unification STRICTE.** Un seul en-tête légal sur toutes les pièces (IFU 3201642748214, RCCM RB/NAT/2016-B-268). Le référentiel `enteteVariantes` et le champ `rccmFacturation` sont RETIRÉS ; les identités anciennes restent documentées par les scans de `docs/` seulement. Cette décision remplace les notes antérieures sur la conservation des variantes.
2. **Rôles assistants : création d'un 16ᵉ rôle « Assistant Comptable »** (matrice INSTRUCTION1 Partie 1, D interdit, `m12-cloture` fermé) ; l'existant reste l'Assistant de Direction.
3. **Répertoire patient : fusion à zones** — un seul `m1-patients`, Zone 1 Accueil / Zone 2 Consultation cloisonnées RBAC, journalisation conservée.
4. **Dépenses : `m12-depenses` reste en place**, enrichi — une dépense porte PLUSIEURS lignes de libellés (ajout/édition/suppression en modale, une écriture plate par ligne, RG-10 sur l'ensemble) et l'écran passe à 4 KPI au lieu de 5.

Confirmés sans objection : D de la matrice cible = archiver (RG-14) ; hub pharmacien conservé sous la Caissière-Dispensatrice ; `cfg-tarifs` en lecture pour la réception par surcharge d'écran ; alias de manifeste pour les écrans bi-domaines ; « sidebar » des Instructions = le ruban acté.

**Langue de travail : le français.** Tout le contenu produit (UI, libellés, commentaires, documents) est en français. Les documents sources sont français ; `draft2.txt` contient une liste de menus en anglais issue d'un thème tiers (Medigo) — c'est une source d'inspiration, pas la nomenclature cible.

## Commandes (depuis `prototype_html/`)

```bash
npm install       # Tailwind CLI + Puppeteer
npm run build     # génère les pages, la safelist, puis compile Tailwind
npm run compta    # régénère data-compta.js depuis les classeurs Excel de docs/
npm run lint      # node --check sur toutes les sources JS
npm run check     # ouvre les 306 pages dans Chrome : erreurs JS, liens, ressources
npm run test      # 66 parcours fonctionnels de bout en bout (1091 vérifications)
npm run serveur   # sert le prototype AVEC sa base (PHP intégré, port 8080)
npm run audit-rbac # chaque écran sous chaque profil : commandes offertes vs droits réels
npm run inventaire-rbac # ce que chaque rôle voit RÉELLEMENT → newdocs/INVENTAIRE-RBAC.md
npm run verify    # lint + build + check + test
```

### Lire les documents de `docs/`

Les PDF sont des scans CamScanner **sans couche texte** — `pdftoppm` est absent
et l'extraction de texte ne donne rien. Les rendre en images via Chrome puis les
lire visuellement : `node build/_pdf2png.js "../docs/fichier.pdf" build/pdf-pages 2`.
Les classeurs Excel s'inspectent avec `node build/_xlsx.js "../docs/fichier.xlsx"`.

`check` et `test` pilotent le Chrome installé sur le poste (`CHROME_PATH` pour surcharger). Attendu : **0 erreur JS, 0 lien cassé, 62/62 scénarios**, et **0 promesse** à l’audit RBAC (1091 sondages écran × profil).

Pour ne contrôler qu'un sous-ensemble : `node build/check.js --pages=m6-,m8-`.
Captures d'écran : `node build/shot.js <page>.html 1600 sortie.png`.

### Trois pièges du build

1. **Régénérer la safelist avant de compiler la CSS.** L'interface est construite en JavaScript ; Tailwind ne voit pas ces classes. `build/gen-safelist.js` relit les sources JS et écrit `build/safelist.html`, seul fichier scanné avec les pages. Oublier cette étape produit une CSS incomplète et une mise en page cassée.
2. **`build/gen-safelist.js` retire les commentaires avant d'analyser.** Une apostrophe française isolée dans un commentaire désynchronise le balayage des chaînes et fait disparaître silencieusement toutes les classes suivantes.
3. **Ajouter un écran = modifier `assets/js/nav.js` puis `npm run pages`.** Le manifeste est la source unique des liens ; aucun href n'est écrit à la main, ce qui garantit l'absence de lien cassé.

## Site vitrine (`frontend_html/`)

> **CE DOSSIER NE SE SUPPRIME EN AUCUN CAS** (consigne du 25/09/2026). Livrable distinct
> du logiciel de gestion, il n'est concerné par aucun arbitrage de pile. Restauré et
> vérifié le 25/09/2026 : 25 pages, 2 849 vérifications, 0 anomalie.

Site public de la clinique, distinct du logiciel de gestion : accueil, présentation de
l’établissement, huit fiches de service, départements, ressources patients, heures de visite,
tarifs, rendez-vous, soins à domicile, actualités, FAQ, contact, mentions légales.
HTML statique, aucune dépendance, aucune requête réseau. **Ce dossier a son propre `CLAUDE.md`,
plus détaillé — le lire avant d’y travailler.**

```bash
npm run build         # compile la CSS (sass) puis réécrit les 25 pages, sitemap.xml et robots.txt
node build/og.js      # régénère les 24 images de partage 1200 x 630
node build/check.js   # contrôle qualité (attendu : 0 anomalie sur ~2220 vérifications)
```

**Le contenu ne se modifie que dans `build/site.js`** — identité, horaires, navigation,
services, questions fréquentes, parcours, valeurs et repères. Les fichiers HTML de la racine
sont engendrés : les éditer à la main serait écrasé au build suivant. La feuille de style vient
de `scss/` (Sass) : `assets/css/style.css` est engendré lui aussi.

Deux pièges rencontrés, à ne pas réintroduire :

- un `backdrop-filter` sur l’en-tête en fait le bloc conteneur du tiroir de navigation en
  `position: fixed` — le menu mobile cesse alors de couvrir la hauteur de l’écran ;
- le tiroir fermé, translaté hors champ, élargit la zone de défilement horizontal tant que
  `html` ne porte pas `overflow-x: clip`.

**Tarifs volontairement absents du site.** Les documents de cadrage ne comportent aucune
grille tarifaire validée (colonnes de prix vierges) ; publier les valeurs d’attente du
prototype serait une faute. Le site renvoie à l’accueil et au téléphone.

## Projet

**SIGH-CNT** — Système Intégré de Gestion Hospitalière pour la CLINIQUE NASSIERA TOO SARL (Natitingou, Bénin). ~18 000 dossiers patients, ~30 agents. Remplace un parc cloisonné : SAGE SARI (stock), LABO BOOK (labo), PERFECTO (compta), E-HOSPI (dossiers), plus de nombreux supports papier.

### Documents de référence (à lire avant toute décision fonctionnelle)

| Fichier | Rôle |
|---|---|
| `docs/Cahier_des_Charges_Technique_...UPDATE.md` | **Référence contractuelle.** Modules M1–M14, règles RG-01→RG-14, schéma BD, matrice RBAC, EF-M1→EF-M14, UC-01→UC-08, catalogue des états, critères de recette |
| `docs/Rapport_de_Cadrage_et_Analyse_des_Besoins_....md` | Analyse de l'existant (AS-IS), parcours patient, besoins §10.1–10.13, priorisation MoSCoW |
| `draf1.txt` | Spécifications « Enterprise UX » par module (sidebar, KPIs, charts, cards, quick actions, sous-modules, profils) + **§1–25 : comment les documents de cadrage deviennent la configuration du logiciel** |
| `draft2.txt` | Liste des écrans Settings/Notifications attendus + rappel des modules §10.1–10.13 |
| `docs/*.pdf`, `docs/*.jpeg`, `docs/*.xlsx` | Documents réels collectés (organigramme, notes de service, tarifs, inventaire SAGE, facture SoBAPS, plannings, assureurs, logo/entête) |


3. **Maquette de référence** : `prototype_html/`, assets **vendorés localement** (Tailwind compilé, police Inter, Chart.js, Lucide). Depuis le 23/09/2026, ses pages sont servies en **`.php`** et son magasin vit dans PostgreSQL (base **`sigh_prototype`**, jamais `sigh_cnt`) : plus de plafond de 5 Mo, des données sauvegardables, et **plusieurs postes qui voient le même magasin**. **Sans serveur, il retombe sur le stockage du navigateur** et fonctionne comme avant — c’est ce repli qui préserve la contrainte hors ligne et qui permet aux bancs d’essai de partir d’un jeu propre.

### Architecture du prototype

Chaque page HTML est un gabarit de dix lignes appelant `SIGH.mount('<id>')`. La coquille, le méga-menu filtré par rôle, le fil d'Ariane et tous les liens sont produits depuis `assets/js/nav.js`. Le contenu vient des modules métier via `SIGH.screen(id, {title, description, regle, actions, render})`.

**Navigation : méga-menu horizontal en ruban** (`buildMenubar()` dans `app.js`). Rangée d'onglets = domaines fonctionnels, panneau blanc en dessous = **une rangée par module**, écrans en pastilles avec l'icône propre déclarée dans `nav.js`. Ouvert par défaut sur le domaine courant, replié automatiquement au défilement (sans écraser la préférence), état mémorisé dans `sigh-cnt:ruban`. Un clic sur un lien du panneau le referme et pose `sigh-cnt:ruban-transitoire`, drapeau à usage unique consommé au chargement suivant — la page appelée s’ouvre menu replié sans que la préférence durable soit écrasée. L’onglet du domaine de la page porte `ribbon-tab-current` **même panneau replié** : sans lui, aucun onglet n’était marqué sur un écran de sous-menu. `N.tree(role)` renvoie l'arborescence déjà filtrée par RBAC : ni domaine ni rangée vide ne peut apparaître.

**Recherche globale et liens profonds** : `N.RUBRIQUES` (dans `nav.js`, avec le reste du manifeste)
déclare les rubriques internes des écrans — un onglet, ses mots-clés. La recherche interroge ces
rubriques, les référentiels (`D.ACTES`, `D.ANALYSES`, assureurs, plan comptable) et les collections,
puis navigue via `app.go(id, { onglet })` → `…/cfg-tarifs.html#onglet=actes`. `U.tabs` lit cette ancre
au montage et ouvre l’onglet visé. Chercher « actes » mène donc au bon tableau, pas seulement à la bonne
page. Tout résultat est filtré par RBAC : jamais de lien vers un écran interdit au profil (RG-13).

**Écrans hors ruban** : `nav.js` accepte des entrées `STANDALONE` surchargeant `module` / `moduleLabel` / `domain` (code `SUP` → `modules/support.js` via `MODULE_FILES` de `gen-pages.js`). C'est ainsi que l'aide et le contact éditeur existent comme pages complètes, accessibles depuis le menu profil et par la recherche globale (`dansRecherche: true`), sans encombrer le méga-menu.

**Responsive** : sous 768 px, la rangée du ruban s'empile (intitulé du module au-dessus des pastilles) et, sans préférence enregistrée, le panneau arrive replié — `rubanOuvert()` teste `innerWidth >= 768`. La barre supérieure masque le nom de l'utilisateur et le libellé de recherche en dessous de `lg` : au-delà, la présentation du poste de travail est inchangée.

**Pages d'accueil de module (hubs)** : `nav.js` fabrique une entrée `hub-<code>` par module ; `_kit.js` enregistre l'écran correspondant, qui présente chaque écran du module en carte (icône, titre, **description reprise de la déclaration de l'écran**). Atteintes depuis le fil d'Ariane, l'intitulé de rangée du ruban et les quatre raccourcis permanents (`N.RACCOURCIS` — M1, M2, M6, M8). Ajouter un module suffit à créer son hub.

**LA GRILLE DES FORMULAIRES A SIX COLONNES** (`U.form`, 01/10/2026) — et non deux, comme
avant. Six se divise par deux ET par trois : c'est ce qui permet de ranger **Nom · Prénom ·
Sexe sur une seule rangée** sans écrire une seconde géométrie à côté de la première. Les
largeurs se déclarent par `col` — absent = un **demi** (`sm:col-span-3`), `'third'` = un
**tiers** (`sm:col-span-2`), `'full'` = toute la largeur (`sm:col-span-6`) ; une section en
occupe six. Le changement a été **rétrocompatible par construction**, et c'est la mesure qui
l'a permis : `col:` n'existait qu'en UNE seule valeur dans tout le dépôt (`'full'`, 305
fois), donc un demi est resté un demi et un plein un plein — 306 pages, 66 scénarios et
l'audit RBAC verts sans retoucher un seul appelant. **Un champ conditionnel masqué ne prend
pas de place dans la grille** : une rangée de trois tiers dont un disparaît laisse deux
colonnes libres, où un demi ne tient pas — il passe à la rangée suivante, et le compte de
rangées ne bouge pas. C'est ce qui fait tenir « L'examen demandé » sur deux rangées que le
prescripteur extérieur soit affiché ou non.

**La section « Ou patient adressé de l'extérieur » est la MÊME dans les trois écrans qui la
portent** (`m1-pieces`, `m2-imagerie-demandes`, `m5-demandes`) : identité sur une rangée,
naissance sur la suivante, téléphone et quartier sur la dernière. Elle naît de `K.champsAge`
pour les deux derniers ; `m1-pieces` ne demande QUE l'âge déclaré (« la réponse ordinaire au
guichet ») et tient donc en deux rangées — différence de modèle, pas de mise en page. **Une
aide de champ posée dans une fabrique partagée s'affiche dans TOUS ses appelants** : la
retirer pour un seul écran ferait expliquer le même champ ici et se taire là.

**Saisie : `U.combo()`** remplace `<select>` dès neuf entrées (automatique dans `U.form`, `search: false` pour forcer le natif). Panneau rendu dans `<body>` en `position: fixed` — donc jamais rogné par une modale — avec recherche, détail par ligne et navigation clavier. Il expose `value` et émet `change` : le reste du code le traite comme un `<select>`. Les champs obligatoires présélectionnent la première entrée, comme le faisait la liste native. Le type de champ **`multiselect`** ouvre le même panneau en cases à cocher : le panneau reste ouvert d’un choix à l’autre, `value` est un **tableau** de valeurs, et `required` y exige au moins une entrée.

Ordre de chargement : `core` (formats FCFA/dates, constructeur `el()`, identité de la clinique) → `data` (référentiels des documents de cadrage) → `store` (persistance, CRUD, archivage logique, audit) → `parcours` (chaîne inter-modules) → `ui` (tableaux, modales, tiroirs, messages) → `charts` / `print` → `nav` → `app` → `modules/_kit.js` → module de l'écran.

`SIGH.kit.crud()` fabrique un écran de gestion complet — onglets, KPI, tableau trié/filtré/paginé, création, édition, archivage annulable, duplication, fiche détaillée, impression — à partir d'une simple déclaration. C'est le gabarit de la plupart des écrans.

Trois compléments pour rendre les fiches modifiables :

- `kit.registre(cfg)` — `crud()` précédé de l'amorçage de la collection par `cfg.seed()`. À utiliser quand un registre était auparavant régénéré à chaque affichage (donc figé en lecture).
- `kit.actionsLigne(col, champs, opts)` — à brancher sur le `rowActions` d'un `U.dataTable` existant : ajoute consulter/modifier/archiver en une ligne. Le rafraîchissement remonte tout seul du bouton au tableau (`.card` porteur de `.refresh`).
- **Corbeille (RG-14)** — `S.corbeille()` balaie toutes les collections et renvoie les fiches archivées, libellées par `LIBELLES` dans `store.js`. L’onglet **Corbeille** de `cfg-systeme` les restaure d’un seul endroit, sans savoir de quel écran elles venaient. Ajouter une collection = ajouter sa ligne dans `LIBELLES`, sinon elle s’affiche sous son nom technique.
- `kit.lectureSeule(raison)` / propriété `regle` — un écran non modifiable doit **dire pourquoi** et indiquer où corriger la donnée d'origine (états calculés, journaux de preuve).

**Quatre pièges corrigés, à ne pas réintroduire :**
- `U.confirm()` protège sa promesse par un garde-fou. `modal.close()` déclenche `onClose`, qui résoudrait `null` avant la réponse réelle et rendrait **toute confirmation sans effet** (archivage, validation RG-04, clôture comptable).
- Une annulation doit être **visible** : le magasin restaure la donnée, mais c'est l'appelant qui rafraîchit la vue. `kit.crud` l'enveloppe via `annulable()`.
- Un `U.combo()` n'est **pas** un `<select>` : `C.clear()` sur lui vide son bouton et le fait disparaître. Pour changer ses entrées, utiliser `setOptions()`.
- Écrire les fichiers avec des scripts Python sous Windows les convertit en CRLF et casse les correspondances de motifs des scripts suivants. Passer par Node ou l'outil d'édition.

**Parcours transactionnel : `assets/js/parcours.js`** — le critère de réussite du prototype (draf1 §24-25)
n'est pas le nombre d'écrans mais la traversée des modules. Ce fichier, chargé sur **toutes** les pages
(chaque page ne charge que le module de son écran), porte la chaîne décrite par la Direction :

`PR.prescrire()` engendre d'un seul geste l'ordonnance, **les demandes d'analyses du laboratoire**, la
facture de la caisse et les files d'attente des postes concernés. Les tâches d'aval naissent **bloquées** :
`PR.encaisser()` les débloque, `PR.delivrer()` sort le stock (RG-03 : refus nommé si une ligne n'est pas
couverte, justificatif = numéro d'ordonnance). La saisie manuelle d'une demande d'analyse reste ouverte
— elle sert les patients adressés de l'extérieur, et se distingue par son champ `origine`.

`kit.fileAttente(type, cfg)` affiche cette file sur le poste concerné : caisse, pharmacie, laboratoire,
salle de soins et tableaux de bord s'en servent tous. Une tâche bloquée est visible mais non exécutable.

**Référentiels devenus administrables (vague 1)** — quatre listes vivaient dans le code, elles vivent
maintenant dans le magasin : le **catalogue des actes** (l’onglet portait quatorze tarifs inventés,
aucun issu d’un document), les **secteurs NS 145**, les **postes de l’organigramme** (l’arbre du
document est aplati en collection : chaque poste désigne son rattachement, d’où la création et la
réaffectation), les **natures de facture** et les **centres de coûts**.

Règle de placement : un référentiel lu par **plusieurs modules** s’amorce dans `store.seed()`
(`naturesFacture`, `centresCouts`) ; un référentiel lu par **un seul écran** s’amorce par cet écran
(`actes`, `secteurs`, `postes`, `ressources`). Se tromper de place donne une liste vide sur les pages
qui ne chargent pas le module propriétaire — chaque page ne charge que le sien. C’est l’erreur commise
puis corrigée sur les natures de facture, consommées à la fois par `cfg-natures-facture` et `m8-facturation`.

`kit.creer(col, champs, opts)` complète `kit.actionsLigne` : ensemble, ils donnent un CRUD entier à un
tableau construit à la main, là où `kit.crud()` ne s’applique pas (onglets d’un référentiel).

Deux commandes homonymes sur un même écran sont à proscrire : le bouton de création d’une nature de
facture s’appelle « Nouvelle nature », et non « Ajouter », qui désigne déjà l’ajout d’une ligne.

**Catalogue des actes** : `D.ACTES` (69 actes, 6 secteurs) vient du document « Répartition des activités
permettant l'évaluation des différents secteurs ». `prix: null` y signale un **tarif non validé** — cinq
seulement sont documentés, relevés sur des factures réellement émises. Ne pas les inventer.

**Prise en charge (vague 2)** — le taux unique par patient ne pouvait pas exprimer ce que le cahier de
charge exige : « appliquer des pourcentages par article et par prestation », variables d’une assurance
à l’autre et, pour un même assuré, selon la nature de l’article. Trois niveaux désormais, tels que les
pièces réelles les montrent : **compagnie → souscripteur (n° de police) → assuré**, et c’est le
**souscripteur** qui porte la grille — le barème versé au dossier est celui d’un employeur.

`PR.repartir(patient, lignes)` répond à quatre questions dans l’ordre : carte valide à la date (RG-09) ?
ligne exclue ? accord préalable obtenu ? quelle garantie, à quel taux, sous quel plafond ? Chaque ligne
repart avec son **motif** — une part patient à 100 % doit toujours pouvoir s’expliquer au guichet.

Deux pièges de ce moteur : une catégorie porte souvent **plusieurs garanties** (consultation généraliste
plafonnée à 5 000, spécialiste à 10 000) — prendre la première venue applique le mauvais plafond, d’où
la sélection par proximité de libellé ; et **aucune grille n’est présumée** : sans convention saisie, la
facture reste intégralement au patient et le dit, plutôt que de supposer une couverture.

**Facturation (vague 3)** — l’émission consomme la grille : chaque ligne porte sa **remise** (colonnes
REMISE et P.U NET des pièces réelles), sa **part assureur** et sa **part patient**, calculées par
`PR.repartir`. Trois règles à ne pas défaire :

- **Deux pièces pour un assuré** : les lignes couvertes et les lignes non couvertes font deux factures
  distinctes (suffixes `-A` et `-B`), une seule pour un patient non assuré ou quand tout est du même côté.
- **MECeF partielle** : `baseMecef` ne porte que la part réglée par le patient. Ni la part assureur ni
  les remises n’y entrent — c’est une exigence écrite du cahier de charge, pas un détail d’affichage.
- ~~Deux RCCM~~ **Un seul RCCM depuis l'arbitrage du 31/08/2026** : `C.BRAND.rccm` partout,
  `rccmFacturation` retiré. Les pièces anciennes qui divergent restent documentées par leurs scans.

`P.ticket()` imprime le **rouleau 80 mm** de la caisse — gabarit distinct du A4, avec bloc MECeF,
OPÉRATEUR, TYPE VENTE, ASSUREUR, ASSURÉ, montant en lettres et les deux formules de la clinique
(`formuleArrete`, `formulePolitesse`, dans `core.js`). L’aperçu commun aux deux formats est
`afficher()` dans `print.js`.

**États de caisse et pièces assureur (vague 4)** — le **relevé** (détail patient par patient, groupé par
souscripteur, avec la date de consultation) et la **facture mensuelle** (récapitulatif par souscripteur)
sont deux vues du même mois : `m9-factures-assureur` les produit toutes deux et **contrôle qu’elles se
recoupent** avant transmission. C’est ce même contrôle qui avait validé l’audit des pièces réelles.

La ventilation consultations / analyses / soins lit la `categorie` des lignes quand elle existe et
retombe sur le champ `type` pour les factures antérieures au détail par ligne — les deux générations
de données cohabitent.

`m8-operations` et `m8-recettes` partagent `PERIODES` et `bornes()` : six périodicités, de la journée à
l’année, plus une plage libre qui choisit son pas de découpage selon l’étendue demandée.

**RBAC métier (vague 5)** — le manifeste décide des **écrans**, il ne suffit pas : deux agents ouvrent le
même écran et ne doivent pas y voir les mêmes lignes. Trois axes désormais :

| Axe | Porte | Défini dans |
|---|---|---|
| Rôle | les écrans accessibles | `nav.js` (`N.can`) |
| Fonction | les capacités métier | `D.CAPACITES` |
| Secteur | le périmètre des données | collection `secteurs` (NS 145) |

La session porte `role`, `fonction` et `secteur`. `PR.capacites()`, `PR.peutVoirResultat(demande)`,
`PR.peutPrescrire(nature)` et `PR.peutExecuterSoin()` appliquent les règles dictées par la Direction :
médecin → tous les résultats ; sage-femme → ceux de son secteur ; infirmier et aide-soignant → aucun ;
laboratoire → ce qu’il produit, remis directement aux patients externes.

Trois principes à tenir :

- **Une restriction s’annonce.** Un filtre muet fait croire à une donnée manquante ; chaque écran
  restreint affiche qui il est, ce qu’il ne voit pas et pourquoi. `peutVoirResultat` retourne toujours
  un `motif`.
- **L’écran s’ouvre, la donnée se filtre.** M5 est ouvert au rôle `infirmier` parce que la sage-femme en
  a besoin ; c’est le filtre de données qui distingue l’une de l’autre. Fermer l’écran aurait fermé les
  deux.
- **Le secteur prescripteur est porté par la demande** (`secteurDemandeur`) : sans lui, aucune
  sage-femme ne voit rien — c’est le comportement sûr, mais il faut le renseigner à la prescription.

**Mise en observation (vague 6)** — surveillance de courte durée, **distincte de l’hospitalisation** :
sa propre collection `observations`, ses unités (`D.UNITES_OBSERVATION`), sa durée de référence
(`D.DUREE_OBSERVATION_REFERENCE`, 24 h) et sa décision de sortie (`D.ORIENTATIONS_OBSERVATION`).
Les confondre ferait disparaître exactement ce qu’on veut suivre — l’heure d’entrée, l’évolution
horodatée des constantes, et le moment où une décision devient nécessaire.

L’orientation « hospitalisation complète » **ouvre une admission M3** portant `origineObservation` :
l’observation se termine, le séjour commence, les deux restent séparés au dossier. Les prescriptions
passées depuis l’observation portent l’unité comme `secteurDemandeur` — donc soumises au RBAC métier
comme les autres.

**Dossier patient (vague 7)** — la fiche est le point où le parcours se relit d’un bloc : elle agrège
douze collections (`sien(nom)` filtre chacune sur le patient) — hospitalisations, observations,
températures, visites reçues, sorties, maternité, accouchements, naissances, décès, analyses,
ordonnances, consultations à domicile. Le **statut d’assurance figure au bandeau** en trois états
distincts — non assuré · carte valide · **CARTE NON VALIDE** en rouge — parce que c’est la première
question posée au guichet et qu’elle décide de la facturation (RG-09). L’onglet Analyses applique le
RBAC métier comme partout ailleurs.

Les **documents numérisés** sont désormais persistés et déposables (PDF, PNG, JPEG), fichier compris,
conservés dans le poste sans requête réseau — mêmes précautions de taille que les ressources graphiques.

`U.sonner(type)` et `U.alerter(message, opts)` produisent l’**alerte sonore** des échéances : son
synthétisé par l’API audio du navigateur, donc aucun fichier à charger et rien à casser hors ligne ;
un navigateur qui refuse l’audio retombe silencieusement sur le toast seul.

**Vagues 9 à 13** — quatre mécanismes à connaître :

- **Accès rapides déduits** : `accesRapides()` dans `app.js` fabrique les raccourcis du bandeau à partir
  du manifeste (voisins du module, puis le hub), filtrés par RBAC, au plus trois. Un écran qui déclare
  ses propres `actions` garde la main — les siennes passent en premier. Les écrire un à un sur cent
  trente-cinq écrans aurait été fastidieux et fragile.
- **Redevances ORTB annuelles** : `D.PARAM_PAIE.ortb.redevances` porte **deux redevances qui se
  cumulent**, et non deux tranches exclusives — **Radio 1 000 F pour TOUS les salariés sans exception**,
  en mars ; **Télé 3 000 F au-delà de 60 000 F de brut**, en juin, **en sus**. Un agent au-dessus du
  seuil acquitte donc **4 000 F** sur l’exercice. Le modèle précédent les traitait comme exclusives et
  dispensait de la radio les salaires élevés : c’est l’erreur que la Direction a corrigée le 20/08/2026.
  `calculOrtb(brut, mois)` renvoie **une ligne par catégorie applicable**, chacune ne portant son
  montant que sur le bulletin de son mois — la compter chaque mois majorerait les retenues de onze
  douzièmes. Les deux parts restent distinguées jusqu’au bulletin, au tiroir de paie, à l’état des
  cotisations et à l’état ORTB imprimable.
- **Réinitialisation des jeux de test** : bascule `sigh-cnt:reinit-autorisee`, fermée par défaut.
  Fermée, le bouton est **absent** et non grisé. `COLLECTIONS_PARAMETRAGE` liste ce qui survit toujours :
  tarifs, secteurs, conventions, comptes, personnel, certificats.
- **Deux bibliothèques documentaires distinctes** : `documentsPatient` (M1, dossier du patient) et
  `documents` (GED, pièces de l’établissement). Les avoir confondues faisait apparaître les unes dans
  l’écran des autres.

**Valorisation des sorties et classification des articles** — deux points tranchés :

- **Sortie au prix de vente ou au CUMP** : devenu un PARAMÈTRE, comme l’annotation manuscrite le
  demandait (« Paramétrer pour que… »), avec le prix de vente par défaut. Chaque mouvement porte les
  DEUX valeurs, faute de quoi changer de méthode rendrait l’historique incomparable. Mesure faite sur
  l’inventaire réel : l’écart entre les deux méthodes est de **1 015 FCFA sur tout le stock** — un effet
  d’arrondi, tant que RG-02 interdit la marge. Les deux valorisations ne divergeront vraiment que le
  jour où une marge sera appliquée hors médicament.
- **Familles et groupes d’articles** : les **sept familles** viennent du document (catégories de
  l’inventaire SAGE). Les **quatre groupes** ne figurent nulle part — ils sont une proposition, portée
  par `GROUPES_ARTICLES.aConfirmer`, et les écrans le disent. Ne pas les présenter comme une donnée
  reprise d’une source.

**Obligations fiscales — deux écrans, deux rôles.** Ne pas les confondre ni les fusionner :

- `cfg-comptabilite` (**Paramètres comptables & obligations**) est la **référence documentaire**. Il ne
  calcule rien : il dit ce qui est dû, quand, sur quelle base et après quelle déclaration — mensuelles
  (ITS, AIB, VPS, CNSS le 10), quatre acomptes d’impôt sur les sociétés, patente et CCIB en deux
  tranches, TVM, redevances ORTB Radio/Télé, liquidation du solde puis dépôt des états financiers au
  30 avril. Écrire ces règles dans l’application plutôt que dans un document séparé a une raison :
  une règle fiscale qui vit dans un fichier extérieur cesse d’être lue.
- `m12-echeances` (**Échéances fiscales & paiements**) est le **suivi**. Il déroule le calendrier sur
  l’exercice (63 échéances, 10 familles d’obligation), les classe en payée / en retard / à venir, et
  porte la validation du règlement — quittance imprimable, annulation, rappel — avec barre de
  notification et alerte sonore à l’ouverture quand une échéance est dépassée.

Trois points de mise en œuvre : `D.CALENDRIER_FISCAL` (`data.js`) est la **source unique des deux
écrans** — y ajouter une obligation les alimente tous les deux ; une échéance tombant un samedi ou un
dimanche est reportée par `jourOuvrableSuivant()`, jamais avancée ; la collection `echeancesFiscales`
est amorcée **par son écran** (un seul écran la lit) et figure dans `LIBELLES` pour la corbeille.

**Tarifs des actes : valeurs d’attente assumées.** La Direction a tranché (20/08/2026) que le jeu de
test porte des tarifs plutôt que des colonnes vides, tout en gardant le CRUD ouvert. Les 69 actes sont
donc tarifés, dont **64 marqués `tarifProvisoire`** — l’écran, la recherche globale et le filtre à trois
états le disent explicitement. Ne pas retirer ce marquage : il distingue une valeur d’attente d’un tarif
validé par la clinique, et c’est exactement la distinction que les colonnes vierges des documents
imposaient de préserver.

**Lignes conditionnelles d’un tableau imprimé** : les rubriques d’un bulletin qui valent `null`
quand elles ne s’appliquent pas (sanction NS 131, remboursement d’avance) sont éliminées par un
`.filter(Boolean)` unique en fin de tableau. Insérer des lignes au milieu par `.concat()` scinde le
tableau et sort la première moitié du filtre — `K.miniTable` reçoit alors un `null` et le rendu casse
**au clic**, donc hors de portée de `npm run check` qui ne clique pas. Chaque moitié doit filtrer.

**Matrice RBAC administrable (vague 15)** — le manifeste donne les droits d’ORIGINE ; l’administrateur
les corrige depuis `m14-roles`, et ses décisions vivent dans la collection `rbac`, **une fiche par rôle**.
Le défaut corrigé était structurel : l’écran d’édition écrivait dans une collection que personne ne
relisait, si bien que fermer un module ne fermait rien. C’est désormais `N.can()` qui applique la
surcharge, et il ne la consulte **que si l’appelant nomme le module** — d’où le `module: mod.code` ajouté
aux six points d’appel. Trois droits par module (`voir`, `editer`, `annuler`), la **lecture seule** étant
leur conséquence et non un quatrième axe : un module visible sans droit d’agir *est* en lecture seule.

Trois pièges de cette couche :

- **Un code de module absent du manifeste n’est pas un module fermé.** Les écrans hors ruban (`SUP`,
  `AUTH`) portent un code que `NAV` ne connaît pas ; les traiter comme fermés renvoyait l’aide et le
  contact éditeur vers la page 403. `droitsOrigine` retourne `horsMatrice` pour eux.
- **Le contrôle d’accès de la page doit passer par `can()`**, jamais par une lecture directe de
  `entry.roles` : sans cela un module fermé disparaît du menu mais reste atteignable en tapant son adresse.
- **Les commandes CRUD obéissent aux droits depuis le kit**, pas écran par écran. `kit.crud`,
  `kit.creer` et `kit.actionsLigne` consultent `K.droits(code)` — écrire la protection cent trente-cinq
  fois aurait garanti autant d’oublis. Une restriction s’annonce : le bandeau de lecture seule nomme le
  profil et renvoie à la matrice.

Un **rôle s’archive, jamais ne se supprime** (RG-14). Ses comptes cessent d’ouvrir une session : la
connexion est refusée par une modale explicite, la tentative est écrite dans `tentativesConnexion`, et
l’administrateur la retrouve dans l’onglet du même nom. Un rôle **se renomme** aussi (Laborantin →
Biologiste médical) : le libellé surchargé est appliqué à `N.ROLES[x].label` au chargement du manifeste,
donc tout le prototype suit sans le savoir.

**Phase 3 (vagues 39-40, 31/08-01/09/2026) — domaine ACCUEIL, alias et fusions.** Quatre mécanismes :

- **Alias de manifeste** : le domaine ACCUEIL (premier du ruban, ordre cible : Accueil → … → Pilotage) RÉUNIT des écrans de M1/M2/M13/CFG sans les dupliquer. Une rangée ou entrée `alias: true` apparaît dans le ruban mais n'engendre ni page, ni hub, ni entrée d'INDEX, et `tree()` résout ses droits depuis l'entrée CANONIQUE — un alias ne peut pas ouvrir ce que le manifeste ferme (sondé sur le caissier).
- **`K.crud` s'est enrichi** : `plageDates: {champ, aujourdhui}` (filtre du/au avec raccourcis — la doctrine du labo, portée au kit), pied de fiche avec **Archiver** (gaté, absent sans droit — Bug 10), et `extraTabs` accepte une **fonction** (un onglet gardé par un droit se décide au rendu).
- **Fusions (Bugs 1 et 3)** : `m2-rendezvous` = « Rendez-vous & visites » (natures + Affaire privée, **individu non enregistré** : `nonPatient`/`visiteurNom`, `patientCode: 'NON-PATIENT'`, aucun code CNT consommé) ; le dossier à deux zones est un **onglet de `m1-patients`** gardé par les droits de l'ancien écran `m1-dossier-etendu` (le biologiste n'y gagne rien) ; `m1-dossier-medical` et `m1-dossier-etendu` sont des pages-renvoi **hors ruban** (STANDALONE module M1) — retirer une entrée du manifeste n'est jamais la bonne façon de fermer un écran.
- **Bug 14** : la fiche de consultation reprend le dernier relevé `constantes` de l'accueil au choix du patient (température, tension, poids, pouls), sans écraser une saisie, en disant d'où viennent les valeurs. Et le **Bug 0a était réel** : `nouvelleVisite` vivait dans la fermeture de l'écran agenda pendant que `m2-visites` l'appelait — ReferenceError au clic, hissée au module.

**Phase 4 (vague 41, 01/09/2026) — la maternité du rapport officiel.** `data-maternite.js` porte les
référentiels TRACÉS vers le rapport du 27/08/2026 : les **10 fonctions SONU** (7 SONUB + 3 SONUC), les
**15 méthodes PF** avec la codification **A/N reprise telle quelle** (A = nouvelle acceptante — c'est la
codification des registres papier nationaux, surprenante mais officielle), les 3 CPoN, les **bornes
écrites** (PC 32–38, PT 30–36, alerte Apgar 5 min < 7, âges à risque CPN 18–35), le modèle de la
PARTOGRAPHIE (alerte 4 cm + 1 cm/h, action décalée de 4 h). Sept collections nouvelles semées **au
socle** (`data-seed`, section maternité — stats et tableaux de bord les lisent), `naissances` enrichies
(PC/PT/Apgar 1-5-10/K1/vaccins J0) avec **un seul formulaire** partagé entre registre des naissances et
dossier bébé. Le **verrou d'admission** (âge + poids, Module A) refuse en nommant OÙ corriger ; la
**Case 27** exige les jours si hospitalisée et les refuse sinon ; une hémorragie ante-partum **exige son
étiologie**. L'acte **Avortement/SAA** est au catalogue SANS prix (aucun document ne le tarife). Le
certificat de repos s'édite depuis la fiche d'accouchement. `m4-stats-maternite` (Pilotage) **calcule**
les indicateurs DHIS2 depuis les registres — jamais fournis. Scénario 46 : le premier parcours M4.

**Phase 5 (vague 42, 01/09/2026) — le financier : l'avoir remplace l'annulation.** Trois chantiers,
un principe : une pièce émise ne se réécrit jamais.

- **La facture d'avoir** (`m8-facture-avoir`, moteur `SIGH.emettreAvoir` — exposé pour être SONDÉ,
  pas recopié) : lignes NOMMÉES obligatoires, cumul plafonné à la facture, contre-passation PLATE en
  brouillon (débit 706000, crédit 571000 espèces ou 411000 créance, RG-10 contrôlé avant écriture).
  Une **fille consolidée dans une mère émise est refusée en nommant la mère** — la compagnie détient la
  pièce, la correction passe par avenant au niveau de la mère. La facture PORTE ses avoirs (`avoirIds`,
  `montantAvoirs`), elle n'est jamais réécrite. La collection `avoirs` est UNE : la vue caisse (M8) et
  le registre fiscal MECeF lisent la même pièce — `statutMecef: 'en_attente'` seulement si la facture
  d'origine était normalisée validée, `'sans_objet'` sinon. **Conséquence RBAC : `M8.annuler` est
  FERMÉ au caissier** (fiche RBAC12) ; il consulte l'avoir sans l'émettre — l'arbitrage différé de la
  phase 2 est soldé.
- **Les dépenses multi-lignes** (arbitrage n° 4) : `editeurLignes()` dans `m12-comptabilite.js` —
  table en modale avec ajout/édition/suppression de lignes, le montant de la pièce est LA SOMME
  (`totauxDepuisLignes`), l'écriture pose UN débit plat par ligne + un crédit trésorerie du total.
  `lignesDe(dep)` adapte les pièces d'ancienne génération (mono-champ) — les deux formes cohabitent.
  **4 KPI, pas 5** : la « dépense moyenne » est retirée par l'arbitrage.
- **Les PV de réception** (`m7-pv-reception-consommables` / `-reactifs`, fabrique `ecranPV(nature)`) :
  lignes commandée/livrée/écart avec `somme`, **réserves OBLIGATOIRES dès que la conclusion n'est pas
  « Conforme »**, chaîne du froid sur les seuls réactifs (null sur les consommables — un booléen y
  affirmerait un contrôle qui n'a pas eu lieu), impression à trois signatures (magasinier, DAF,
  représentant du fournisseur). L'assistant comptable y accède par sa fiche RBAC (M7 EDITER), sans
  figurer aux listes du manifeste — une surcharge accorde.

Scénario 47 sonde le tout : somme des lignes, 4 KPI, moteur d'avoir (émission, refus nommé, plafond),
fermeture caissier, PV des deux natures.

**Phase 6 (vague 43, 01/09/2026) — laboratoire : traçabilité et comparaison.** Cinq chantiers,
aucun ne touche aux deux verrous ni à `D.ETATS_RESULTAT` :

- **Le code d'analyse unique `NNNNN-AAAA`** (série annuelle, comme les pièces certifiantes) vit dans
  UNE fabrique — `PR.codeAnalyse(date)` dans `parcours.js` — consommée par les quatre voies de
  création (ordonnance, accueil externe, saisie labo, amorçage). La leçon du code patient, qui vivait
  à deux endroits, est appliquée d'office. La référence `LAB-NNNNN` reste : elle identifie la demande
  dans le logiciel, le code identifie le dossier au registre annuel.
- **`m5-impression-resultats`** : le compte rendu ne sort que pour un examen RÉGLÉ — le règlement se
  lit sur la LIGNE de facture (`demandeId`), et la réponse a TROIS états : réglé, dû (bouton
  verrouillé qui nomme la caisse et la pièce), et **« sans pièce liée »** pour les demandes d'avant
  les lignes payables — les dire impayées serait aussi faux que les dire réglées.
- **`m5-resultats-comparatif`** : le bi-panneau des antériorités (la colonne « Antériorités » de la
  fiche réelle). Seuls les résultats RENDUS se comparent, chaque colonne aux bornes de SON époque.
- **Les plages par lot de réactif** (`plagesReactif`, moteur exposé `SIGH.laboPlages` pour être
  sondé) : versionnées PAR DATE comme la grille des primes — un résultat se compare aux bornes du lot
  en service à SA date, relever une borne ne change pas un compte rendu rendu. AUCUNE plage n'est
  pré-remplie : aucun document n'en fournit. La saisie, le compte rendu et le comparatif passent tous
  par `variableALaDate`/`referenceALaDate`.
- **Vues par service** (`m5-demandes-maternite`, `m5-demandes-hospitalisation`) — des VUES du même
  registre, jamais une seconde collection — et **`m5-reactifs-stats`**, calculées depuis le stock,
  les lots et les demandes (l'écran dit que le FLUX vit en M6).

Scénario 48 : série annuelle sans doublon, verrouillage d'impression annoncé, versionnement des
plages (décalées après la mise en service, intactes avant, lot nommé), RBAC des nouvelles vues.

**Phase 7 (vague 44, 01/09/2026) — bloc, anesthésie et demandes du service.** Quatre écrans M3 :

- **`m3-cpa`** (consultation pré-anesthésique) et **`m3-cr-anesthesie`** : les pièces du rôle
  anesthésiste (sa fiche RBAC ACCORDE M3 — aucun ajout aux listes du manifeste). Les échelles ASA et
  Mallampati et la liste des techniques ne viennent d'AUCUN document remis : comme les check-listes du
  bloc, propositions marquées à valider. Une CPA « avec réserves » **exige ses réserves nommées** ;
  une intervention sans CPA est **signalée, jamais bloquée** (l'urgence n'attend pas). Le CR
  d'anesthésie couvre induction/entretien/**réveil** avec décision de sortie — la surveillance
  d'étage reste `m3-surveillance` ; « aucun incident » **s'écrit** (un champ vide ne distingue pas
  l'absence d'incident de l'oubli).
- **`m3-demande-examen`** : la fiche papier de reunions/ — tous champs obligatoires, urgence PAR
  EXAMEN ou bilan entier, service demandeur. Elle passe par `PR.ouvrirDemandeExterne` étendu
  (`origineFiche`/`origineDemande: 'service'`, `secteurDemandeur`) — la fabrique reste UNIQUE, et
  l'identité n'est plus exigée en ressaisie pour un patient du répertoire (`patientId`). La chaîne
  existante suit : lignes payables, caisse saisie, prélèvement bloqué.
- **`m3-bons-pansements`** : le bon = `PR.prescrire` avec l'acte répété — **une ligne payable PAR
  SÉANCE**, la caisse encaisse des séances nommées et un partiel libère exactement celles qu'il
  couvre. **Le pansement vaut 9 000 non assuré / 6 000 assuré** : colonnes de la grille INVERSÉES
  (décision du 26/08) — l'avoir cru à 6 000 était l'erreur de lecture que `COLONNES_INVERSEES`
  documente ; le moteur avait raison.
- **`K.creer`/`K.actionsLigne` acceptent `avant(v, record)`** : le contrôle métier de l'appelant,
  qui refuse EN LE DISANT (son propre toast) et retourne `false` — rien n'est écrit. C'est lui qui
  porte l'exigence des réserves de la CPA.

Scénario 49 : réserves nommées, chaîne de la fiche du service (demandes codées au secteur, caisse,
prélèvement bloqué), bon 3 séances / partiel « 1 / 3 », accès anesthésiste / refus caissier.

**Phase 8 (vague 45, 01/09/2026) — l'imagerie éclatée.** L'écran unique devient un circuit :

- **`PR.ouvrirDemandeImagerie`** (fabrique UNIQUE) : la demande suit LES MÊMES ÉTATS que le labo —
  demandée → payée → exécutée → validée. La ligne payable porte `demandeImagerieId` ; `PR.encaisser`
  libère l'examen NOMMÉ (bloc dédié, ligne par ligne + repli facture soldée). Un examen sans tarif
  est **refusé en le nommant** — un tiret n'est pas un zéro. RG-09 sur la grille INVERSÉE
  (pelvienne 9 000 / ECG 15 000 non assuré).
- **`m2-imagerie-demandes`** (registre), **`m2-dashboard-imagerie`** (le poste : payés à exécuter,
  file d'attente), **`m2-echographie-galerie`** (clichés rattachés au patient et au CR, précautions
  de taille des documents), **`cfg-imagerie-catalogue`** (CFG) et **`m2-stats-echographie`** (PIL,
  calculées). La mécanique du CR est HISSÉE AU MODULE (`saisirCR`/`rendreCR`/`detailCR`/`imprimerCR`)
  — une mécanique, plusieurs portes ; la saisie directe de `m2-imagerie` reste la voie « manuelle ».
- **Le catalogue de l'imagerie vit AU MAGASIN** : `examensImagerie`/`variablesImagerie` semées au
  socle depuis `D.IMAGERIE` (la semence — lues par M2 ET CFG, le piège documenté), administrables ;
  la saisie lit la collection (`imVariablesDe`), plus la constante — la leçon D2 des actes.
- **L'échographiste EXÉCUTE sans PRESCRIRE** : surcharges d'écran (le module M2 ne le liste pas) —
  demandes/dashboard/galerie en écriture, `m2-stats-echographie` accordé nommément (PIL lui est
  fermé au module), et la commande « Nouvelle demande » lui est fermée NOMMÉMENT sur l'écran même :
  deux droits distincts sur un écran, l'écriture du registre n'emporte pas la prescription.
- **`K.actionsLigne` accepte `transform`** (comme `K.creer`) — l'édition des variables du catalogue
  reconstruit ses listes de choix depuis le champ texte.

Scénario 50 : moteur (lignes nommées, tarifs inversés, refus nommé, libération partielle), chaîne
complète MENÉE SOUS LE RÔLE échographiste (saisir → exécutée, rendre → validée, prescrire absent),
galerie rendue, catalogue au magasin, stats PIL, RBAC.

**Phase 9 (vague 46, 01/09/2026) — pilotage & statistiques transverses.** Huit écrans, un principe :
TOUT est calculé depuis les registres, rien n'est fourni, et chaque proxy ou proposition SE DIT.

- **`m5-stats-examens`** (PIL) — la demande écrite du laboratoire (reunions/) : les examens selon
  PLUSIEURS AXES — service demandeur, sexe, tranche d'âge, interne/externe, plage de dates. Chaque axe
  est un FILTRE : compteurs, graphiques et tableau se recalculent sur la population filtrée.
- **`m2-stats-consultations`** (par praticien ; le « secteur » affiché est le service du praticien à
  l'organigramme — la consultation ne porte pas de secteur propre, et l'écran le dit) ;
  **`m3-stats-bloc`** (CRO par opérateur, CRA par technique, conclusions CPA, interventions sans CPA —
  signalées, jamais bloquées) ; **`m10-cout-agent`** — DEUX colonnes à ne jamais additionner : le coût
  employeur (brut + CNSS patronale 16,4 % + VPS 4 %) et les retenues de l'AGENT (CNSS 3,6 %, ORTB) ;
  l'ITS, progressif, se lit sur le bulletin — le recalculer ici créerait une seconde vérité.
- **`m12-rentabilite-groupes`** : recettes par groupe de prestation (lignes payables) FACE AUX charges
  validées par centre de coûts — sans les soustraire ligne à ligne : aucun document ne ventile les
  charges par groupe, le rapprochement est une PROPOSITION dite, et les brouillons écartés sont comptés.
- **Petits écrans** : `m2-agenda-medecin` (une VUE du registre, ouverte sur le praticien connecté),
  `m2-file-cabinet` (les DEUX listes de la vague 35 — nommés par cabinet, vivier commun — jamais
  fondues), `m1-certificats-externes` (VUE des pièces des patients `externe` ; la délivrance reste à
  `m1-pieces` — une seconde saisie créerait deux numérotations). **Cette VUE a FUSIONNÉ dans
  `m1-pieces` le 22/09/2026** (onglet « Patients externes ») : deux registres sur la même collection
  finissaient par ne pas dire la même chose. La page subsiste hors ruban et renvoie.

Aucune collection nouvelle : la phase LIT — pas d'incrément de `_version`. Scénario 51 : l'axe
filtre VRAIMENT (compte affiché = recompte du magasin), recettes = somme des lignes, proposition
dite, agenda qui suit le praticien, RBAC.

**Phase 10 (vague 47, 01/09/2026) — qualité, enquêtes & dette. Le plan en 10 phases est SOLDÉ.**

- **`adm-enquetes`** (M13) — le principe KoboCollect transposé hors ligne : **le questionnaire est
  une DONNÉE et le formulaire de saisie NAÎT du modèle** — ajouter une question au modèle suffit à la
  faire paraître à la prochaine saisie, rien n'est codé (sondé au geste, scénario 52). Éditeur de
  questions en modale (le motif `editeurLignes` des dépenses), trois types (note 1-5, choix, texte),
  réponses horodatées avec canal. Le modèle de satisfaction amorcé est une **proposition** — aucun
  document de cadrage ne fixe de questionnaire, les écrans le disent. **`adm-satisfaction`** : la
  lecture calculée (moyennes par question, recommandation, commentaires).
- **Dette D5, MESURÉE puis soldée à sa juste taille** : sur 103 `K.btn` à verbe d'écriture, 27
  seulement sont des ENTRÉES d'écran (le reste : pieds de modale déjà derrière une porte), et sur
  ces 27, la plupart IMPRIMENT (« Éditer l'état » = P.etat, pas une écriture). **Quatre vraies
  écritures nues** converties en `K.commande` : Nouvelle évaluation (M10), Nouvelle écriture (M12),
  Lancer un inventaire (M6), Nouvelle relance (M9). L'audit RBAC (0 promesse) reste le garde-fou
  des pieds de modale — on ne les gate pas : on n'y arrive pas sans la porte.
- **Dette D6** : scénario 52 sonde M7 (quantité accordée ≠ demandée, sous le rôle STOCK — M7 est
  fermé à l'agent administratif et c'est l'ouverture de l'écran qui amorce), M13 (courriers semés au
  socle) et la GED (bibliothèque de l'établissement DISTINCTE des documents patients).
- `_version` 48 (`enquetes`, `reponsesEnquetes`).

**Vague 48 (01/09/2026) — arbitrage « plus aucun montant nul » et le bloc SOINS ramené dans
ACCUEIL.** Trois décisions de la Direction :

- **La rangée « RDV, Visites & Consultations » entière figure dans ACCUEIL**, en ALIAS (chaque écran
  une seule fois — les cinq entrées qu'Accueil portait déjà sont absorbées par la liste complète,
  dans l'ordre canonique). La rangée canonique reste en SOINS ; les droits se résolvent depuis
  l'entrée canonique, comme tout alias.
- **Plus aucun montant NUL** — cet arbitrage REMPLACE les marquages « sans prix » antérieurs, sans
  jamais se faire passer pour une donnée documentée : **GY-SAA** reçoit un tarif d'ATTENTE aligné
  sur l'AMIU (la SAA se pratique par AMIU — `tarifProvisoire`, motif daté, dans le seed du socle où
  l'acte est ajouté, PAS dans data-tarifs : la règle ne vit qu'à UN endroit) ; les **34 références
  SAGE non valorisées** reçoivent la **MÉDIANE de leur catégorie** (calculée dans `genProduits`,
  jamais écrite en dur — elle suit l'inventaire), marquées `valorisationProvisoire` et TRACÉES dans
  la surcouche `valorisationsSage`, désormais semée au socle (une fiche datée/sourcée par référence
  — le document SAGE reste ce qu'il est, la réconciliation ne bouge pas). Analyses et grille :
  déjà toutes tarifées (vague 26). `_version` 49.
- **`index.html` (connexion) est écrit à la main et n'avait PAS suivi les vagues** : il ne chargeait
  que 13 scripts — un PREMIER survol à froid semait le magasin et cassait sur `L.EXAMENS`
  (data-labo absent), bug latent depuis la vague 23, masqué parce que tests et check arrivent par
  `pages/`. Il est aligné sur la liste `SCRIPTS` de `gen-pages`, et une **GARDE DE BUILD** refuse
  désormais tout désalignement : `gen-pages` échoue si `index.html` ne porte pas chaque script.

**Vague 49 (01/09/2026) — les validations : la Direction tranche, le professionnel garde.**

- **Les validations du ressort de la DIRECTION sont levées** : les tarifs d'attente du 20/08 sont
  **ARRÊTÉS** (`tarifArreteLe` sur le catalogue VIVANT ; la SEMENCE `D.ACTES` garde son marquage —
  elle documente ce qui venait d'un document), les 34 valorisations confirmées (surcouche tracée,
  révisable à la première facture), les quatre groupes d'articles confirmés, le questionnaire de
  satisfaction validé. **Les marquages qui attendent un PROFESSIONNEL nommé RESTENT** : bornes labo
  (biologiste), pathologies (tableau de morbidité), check-listes/ASA/Mallampati (praticiens du bloc),
  plages par lot — la Direction ne signe pas à leur place, et l'écran le dit. `_version` 50.
- **`adm-validations`** (M13, alias dans ACCUEIL) — le centre des validations : trois familles (les
  gestes DE POSTE avec leur compte et le chemin ; les référentiels en attente d'un professionnel ;
  ce que la Direction a validé), et **jamais de validation en masse** — la validation est un geste
  humain porté à son poste. Une file amorcée par un écran d'un autre module s'annonce « non
  amorcée » plutôt que d'afficher un 0 faux (doctrine vague 31).
- **La passe « somme », MESURÉE** : 87 `P.tableau` impriment des montants, 32 déclarent `somme`,
  **55 ne la déclarent pas** — inventaire par fichier dans le scratchpad. Ne PAS les convertir en
  masse : beaucoup sont des barèmes et prix unitaires où un total n'aurait aucun sens (« un total
  faux est pire qu'un total absent ») ; chaque site se juge à la pièce, au fil des retouches.
- **Un scénario qui VIDE une collection la RESTAURE** (le scénario de valorisation vidait la
  surcouche et effaçait les 34 fiches pour tous les scénarios suivants) — et la sauvegarde passe
  par `sessionStorage`, car `window` est balayé à chaque navigation du scénario.

**Vague 50 (01/09/2026) — l'activation PAR MODULE, pour une autre clinique.** `cfg-modules` porte
désormais une **bascule par module M1…M14/MECEF/GED/RAP/PIL**, dérivée du manifeste (un module ajouté
paraît seul). Le moteur existait (une fiche `{module, actif:false}` sans liste d'écrans ferme le
module entier — `can()` → `ecranActif(id, code)` retire ruban, alias, recherche, hubs, raccourcis et
adresses, tous rôles) ; la vague ajoute l'UI, deux garanties et un correctif :

- **Le NOYAU ne se ferme pas** : CFG (porte l'interrupteur — un interrupteur qui se coupe lui-même
  ne se rallume plus) et DASH (la page d'accueil de chaque rôle). Bascule absente sur leurs cartes
  ET refus nommé dans `basculer()` — la porte `declarer()` est gardée aussi.
- **L'INDÉPENDANCE est garantie et SONDÉE** (scénario 54) : Accueil (M1) et Soins (M2) fermés, les
  stocks, la paie et les RH montent et travaillent — fermer un module n'arrête que ses écrans ; les
  files qu'il alimentait cessent de se remplir, ses données restent, la saisie directe des autres
  postes demeure (doctrine de la saisie manuelle du labo, généralisée). L'adresse d'un module fermé
  renvoie au 403 ; la réouverture rend tout en l'état.
- **Correctif de moteur** : `modulesDesactives()` lisait `.all()` — une fiche de fermeture
  ARCHIVÉE continuait de fermer le module, invisible de l'écran de pilotage (une fermeture
  indébrayable). Une fiche archivée ne ferme plus rien (RG-14).
- Piège `var`-après-`return` payé une DEUXIÈME fois (`NOYAU`, après `CODES_PANSEMENT`) : toute
  affectation lue par `afficher()` se déclare AVANT l'appel initial.

**Vague 52 (02/09/2026) — M2 DÉPLACÉ dans ACCUEIL, pas aliasé.** La demande du 01/09 (« ramener le
bloc ») avait été lue comme un alias bi-domaine ; la Direction a précisé : un DÉPLACEMENT. La rangée
**canonique** M2 vit désormais dans ACCUEIL — le domaine de rattachement (fil d'Ariane, onglet
courant, hub) suit — et SOINS n'en garde **ni rangée ni alias** : il commence à l'hospitalisation.
Le mécanisme d'alias reste en service pour M1/M13/CFG dans ACCUEIL.

**Vague 53 (02/09/2026) — LE GRAND RESSERRAGE RBAC : les cinq fiches qui manquaient.**

- **Un rôle sans fiche a TOUS les droits** sur ce que le manifeste lui ouvre — l'inventaire montrait
  le comptable en édition/annulation sur le dossier médical. Les CINQ fiches manquantes sont écrites
  (RBAC20-24) : **dm** (écrit le clinique M1-M5, lit stock et caisse), **direction** (lit tout,
  décide l'institutionnel — M13/M14/CFG/GED — et VALIDE LA PAIE par surcharge d'écran
  `m11-validation` : signer n'est pas saisir), **comptable** (M12/M8 avoirs/M9/MECEF/M11 en
  écriture ; achats et stock en lecture SAUF la facture fournisseur, qui est SA pièce ; aucun
  clinique), **agentadmin** (secrétariat M13/GED/RAP ; identité patient sans dossier),
  **ambulancier** (ses interventions et le répertoire d'urgence, rien du secrétariat). Seul
  l'`admin` système reste sans fiche — son poste EST l'accès complet, assumé.
- **Fermetures du 02/09** : caissier — `m6-stock-gros` (lecture comprise), `m6-dashboard`,
  `m12-depenses` (REMPLACE la doctrine « une dépense se saisit à la caisse » : c'est un geste
  comptable) ; magasinier — **M1 fermé au MODULE** (roles '*' au manifeste : la fermeture module
  couvre les écrans futurs) ; biologiste — `m7-livraisons` fermé (le bon de livraison est le geste
  du magasinier, impression comprise).
- **`m6-dispensation` : AUCUNE création manuelle** — toute délivrance naît d'une ordonnance du
  médecin passée en caisse (RG-03, justificatif = n° d'ordonnance) ; l'écran devient le REGISTRE,
  le geste vit sur la file débloquée par l'encaissement. **`m6-alertes` : le bouton « Établir un
  bon de commande » est RETIRÉ** — l'alerte SIGNALE, la commande suit son circuit M7 (RG-04).
- **Filtres** : plage de dates sur `m2-stats-consultations`, `m3-stats-bloc`,
  `m12-rentabilite-groupes`, `m10-cout-agent` (historique des paies), `dash-da` (analyse libre) et
  les DEUX états de stock (l'ÉTAT reste à une date — c'est le bloc « mouvements de la période » qui
  prend la plage) ; `searchable` sur les tableaux des dashboards et sur TOUTE file d'attente
  (`K.fileAttente` — on y cherche un nom au guichet). L'ordre hero → accès rapides → indicateurs
  était déjà garanti par `K.dash`.
- **Piège `String.replace` sans regex** : il frappe la PREMIÈRE occurrence du FICHIER — un
  branchement destiné à `m10-cout-agent` a atterri dans `dash-patient` (ReferenceError). Tout
  remplacement scripté se fait à partir d'une ancre UNIQUE, jamais d'un motif générique.

**Vague 51 (02/09/2026) — la passe « somme », les validations écrites, la journée des postes.**

- **Passe « somme » SOLDÉE à la pièce** : 17 sites totalisés (bulletins d'examens, journaux de paie,
  états de stock/pertes/inventaire, bons, créances par compagnie, arrêté de caisse, facture MECeF,
  grand livre d'un compte, analytique par centre) ; le reste LAISSÉ avec motif — récapitulatifs
  hétérogènes (brut+retenues+net ne s'additionnent pas), barèmes et prix unitaires, bulletins à
  lignes TOTAL intégrées, tables TRONQUÉES (`slice`) où un total partiel se lirait comme total du
  compte, SIG en cascade, bilan à totaux propres, pièces mono-ligne.
- **Les validations écrites des PROFESSIONNELS sont arrivées (01/09)** : bornes suppléées → badge
  « **Validée (biologiste)** », JAMAIS confondu avec « Documentée » (fiche du 21/08) — trois
  provenances, pas deux ; pathologies arrêtées par les médecins ; check-listes/ASA/Mallampati
  arrêtées par les praticiens (`D.CHECKLIST_BLOC.arreteLe`) ; seuils d'alerte confirmés ;
  **rapprochement groupe ↔ centre ARRÊTÉ** — affiché centre par centre, bénéfice brut par groupe,
  charges TRANSVERSES non ventilées (les répartir exigerait une clé qu'aucun document ne donne).
  **Deux exclusions d'honnêteté** : le parc technique `aCompleter` (marque/série MANQUENT
  physiquement — une validation ne crée pas un numéro de série, le marquage tombe par la SAISIE) et
  les plages par lot (structurel : chaque nouveau lot porte les bornes de SA notice).
- **La « journée des postes »** (`gestesDePoste()` en fin de peuplement) : le jeu figurait un
  établissement où personne n'avait validé depuis des mois. Les postes ont fait leurs gestes —
  datés, attribués — et il reste le FLUX COURANT : ~15 brouillons, 5 relectures biologiques, 4 CR
  d'imagerie, 5 bons + 3 commandes au circuit, 4 MECeF, et UNE échéance dépassée (l'alarme doit
  avoir quelque chose à montrer). `_version` 51.

**Vague 54 (05/09/2026) — BADGES DU PERSONNEL et PARTAGE D'UNE FICHE D'ENQUÊTE.**

- **Le badge est une PIÈCE IMPRIMÉE rattachée à un agent : sa place est M10**, jamais un module
  nouveau — l'agent, sa fonction et son service y vivent déjà, et un module séparé aurait créé une
  seconde vérité sur l'identité du personnel, qui aurait divergé du dossier RH au premier changement
  de service. Quatre écrans : `m10-badges` (registre), `m10-badges-verification`,
  `m10-badges-modeles`, `m10-badges-impression`. Deux collections et pas une — `badges` (une fiche
  par badge émis) et `modelesBadge` (les gabarits) : les fondre aurait obligé à recopier le gabarit
  sur chaque carte, et changer une mention du verso aurait demandé de reprendre tous les badges émis.
- **CE QUE PORTE LE QR EST LA DÉCISION LA PLUS IMPORTANTE DU MODULE : le matricule et le numéro de
  série, RIEN D'AUTRE.** Ni nom, ni fonction, ni téléphone, ni URL. Trois raisons, et la troisième
  commande les deux autres : un badge se photographie dans un couloir ; le logiciel fonctionne hors
  ligne, donc une URL ne mènerait nulle part ; et **la vérification doit passer par le LOGICIEL**,
  seul à savoir si le badge est encore valide. Un QR qui porterait le nom en clair remplacerait un
  contrôle par une simple lecture — c'est exactement ce qu'un faux badge cherche à obtenir.
  Fabrique UNIQUE dans `parcours.js` (`PR.numeroBadge`, `PR.badgeQR`, `PR.lireBadgeQR`), comme le
  code d'analyse : les quatre voies — émission, impression, vérification, amorçage — la partagent.
- **L'encodeur QR est VENDORÉ LOCALEMENT** (`assets/js/vendor/qr.js`, écrit pour le prototype) :
  aucune API de génération en ligne, aucune requête réseau — on imprime aussi un badge un jour de
  coupure. Mode octet, correction M, **versions 1 à 6 seulement** (106 octets) : au-delà, la norme
  impose des blocs d'information de version, et **refuser explicitement vaut mieux qu'un code que
  rien ne saurait relire**. Rendu SVG par `C.qr()` — net à l'impression à n'importe quelle taille,
  zone de silence comprise. Vérifié par RELECTURE indépendante : format BCH, désentrelacement,
  **syndromes de Reed-Solomon nuls** et charge utile revenue à l'identique sur les six versions.
- **Le badge est le TROISIÈME gabarit d'impression**, à côté du A4 et du rouleau 80 mm : carte
  **CR80 (85,6 × 54 mm)**, celui des imprimantes à cartes et des porte-badges du commerce.
  **L'en-tête officiel ne s'y applique PAS tel quel** — logo, dénomination et devise, mais **ni IFU
  ni RCCM** : ce sont des mentions FISCALES, destinées à une pièce comptable, pas à une carte
  accrochée à une blouse. Le pied normalisé (date, utilisateur, identifiant) va sur la **planche**
  A4, pas sur les cartes. **Aucune couleur en dur** : les classes viennent du design system, si bien
  que la dérivation vers une autre clinique suit sans retouche.
- **UN BADGE SE RETIRE, IL NE SE SUPPRIME PAS** (RG-14, et davantage) : le badge perdu est
  précisément la fiche qu'on ressort le jour où quelqu'un se présente avec. Un seul badge valide par
  agent — deux cartes valides pour la même personne, c'est une carte qui circule sans que personne ne
  la réclame ; l'émission d'une seconde est refusée **en nommant la première**. La planche ne propose
  jamais un badge retiré : le réimprimer le remettrait en circulation.
- **La vérification distingue QUATRE réponses, pas deux** : VALIDE · EXPIRÉ · RETIRÉ · **INCONNU**.
  « Inconnu » n'est pas « retiré » — le premier signale un badge qui ne vient pas d'ici, le second un
  badge que la clinique a repris ; les confondre ferait traiter un faux badge comme une simple
  péremption. La saisie manuelle du numéro est acceptée autant que le scan : la refuser rendrait le
  contrôle impossible le jour où le QR est abîmé, c'est-à-dire le jour où il sert le plus. Chaque
  vérification est **journalisée** (RG-12) — et le journal étant **plafonné à 400 entrées**, une
  sonde qui compte sa longueur ne prouve rien : elle lit la dernière entrée.
- **Droits** : la DAF (qui porte les RH depuis l'archivage du compte `rh`) et la **Direction**
  émettent — accordé PAR ÉCRAN sur la fiche RBAC21, M10 restant en lecture, exactement comme
  `m11-validation` : le badge atteste devant un tiers qu'un agent est des nôtres. Le **Surveillant**
  et l'**Assistant de Direction** VÉRIFIENT sans émettre (registre et vérification en lecture,
  modèles et planche fermés nommément) ; fermé partout ailleurs. L'Assistant de Direction n'a pas M10
  au module : **l'ajouter aux listes du manifeste n'aurait eu aucun effet**, la surcharge de module
  l'emportant — c'est sa fiche RBAC qui l'accorde.
- **Quatre points restent à ARBITRER par la Direction**, marqués et affichés : la **durée de
  validité** (24 mois d'attente), le **format du numéro de série** (`BDG-NNNNN-AAAA`, série annuelle
  proposée par analogie avec les pièces certifiantes), les **mentions du verso** (elles engagent la
  clinique envers le porteur) et **si le badge sert de support de POINTAGE** — s'il pointe, il se
  relie au registre des présences et la conception change. `adm-validations` gagne une **quatrième
  famille** : ce qui attend un arbitrage de la Direction elle-même, distinct de ce qui attend la
  signature d'un professionnel nommé — les ranger ensemble ferait attendre l'un pour l'autre.

**Partage d'une fiche d'enquête à un tiers** — le module `adm-enquetes` existait ; ce qui manquait
n'était pas le formulaire mais **le canal**.

- **UN LIEN SUPPOSE D'ÊTRE JOIGNABLE**, et c'est le point qui commande tout : le serveur est local,
  sans port ouvert sur Internet. Le lien et le QR couvrent le tiers **DANS la clinique** (salle
  d'attente, Wi-Fi) et la **tablette en mode kiosque**, qui ne demande même pas de lien. Faire
  répondre un patient **depuis chez lui** exige une surface publique sur Internet : c'est un
  **ré-arbitrage d'architecture**, à porter par une page publique hébergée AILLEURS qui se
  synchroniserait ensuite — surtout pas l'ouverture du serveur de la clinique. L'écran le dit.
- **L'adresse porte un JETON, jamais l'identifiant de l'enquête** (`PR.jetonEnquete`, 24 caractères
  sans `l`/`1` ni `o`/`0`) : sans cela, on énumère les enquêtes en changeant un numéro. Il est
  **daté et révocable** — un lien qui vit indéfiniment collecte des réponses des mois après la
  clôture, et personne ne s'en aperçoit. Révoquer **ferme la porte sans rien effacer**.
- **La page publique (`enquete-publique`, hors ruban, `standalone`) ne porte NI ruban, NI recherche,
  NI session, NI fil d'Ariane, ni le moindre lien vers le logiciel** : une page d'enquête qui
  afficherait la coquille de l'application serait une porte — on la tend à des inconnus. **Jeton
  inconnu, expiré et révoqué reçoivent LA MÊME réponse**, qui ne nomme aucune enquête : distinguer
  les trois renseignerait sur ce qui existe.
- **UN SEUL GÉNÉRATEUR, DEUX HABILLAGES** : `champsDepuisModele()` sert la saisie interne et la page
  publique. Un second générateur aurait divergé à la première question ajoutée — on l'aurait ajoutée
  au modèle, elle serait apparue au guichet et pas sur le lien, sans que rien ne le signale. Le
  scénario 56 le sonde AU GESTE : question ajoutée au modèle, page publique rouverte, question
  présente.
- **Deux décisions prises explicitement** : l'**anonymat** est un choix porté par le lien — annoncé
  anonyme, on ne stocke ni nom ni lien vers un dossier, sinon le mot est un mensonge ; et **aucune
  donnée médicale sur une page publique** — une enquête interroge l'accueil, l'attente, la propreté,
  jamais le diagnostic ni le motif de venue. Le champ `canal` reçoit la valeur **« Lien public »**,
  non sélectionnable à la main : elle permettra de comparer ce que disent les réponses du guichet et
  celles remplies seul sur un téléphone.
- **Dans le prototype, la collecte reste LOCALE au poste** : un lien ouvert sur une autre machine y
  afficherait le formulaire, mais ses réponses ne reviendraient jamais. Le geste se **maquette** —
  jeton, page publique, QR ; la collecte réelle appartient à la version web, et l'écran le dit.
  Le « live » ne demande aucune technique particulière : `adm-satisfaction` recalcule déjà ses
  moyennes à l'affichage.
- `_version` **53** (`badges`, `modelesBadge`, `jetonsEnquete`). Scénarios **55** et **56**.
  `SIGH_PORT` / `SIGH_PORT_TEST` surchargent les ports de `check` et `test` : sur un poste où 8099
  servait déjà, le contrôle échouait au démarrage sans rapport avec le prototype.

**Vague 55 (06/09/2026) — corrections du ruban, fusion achevée, et LE VOCABULAIRE DES SIX SECTEURS.**

- **La rangée d'ACCUEIL est resserrée sur le travail de réception** : Agenda, Rendez-vous & visites,
  File d'attente, File par cabinet, Agenda du médecin, Écran d'appel, Consultations & soins à
  domicile, Registre des appels, Consultations. Le **geste clinique** (fiche, pathologies,
  ordonnances, prescriptions, salle de soins) et l'**IMAGERIE** ont leurs rangées dans SOINS : on ne
  cherche pas une ordonnance ni un compte rendu d'échographie dans le menu de l'accueil.
  « Validations en attente » quitte « Courriers & orientation » — l'accueil oriente des patients, il
  n'arbitre pas les files des autres postes.
- **Un nouveau mécanisme de manifeste : `secondaire: true`.** La rangée paraît au ruban et ses écrans
  y sont CANONIQUES (une page, un fil d'Ariane, une entrée d'index), mais elle ne crée pas de second
  hub et ne redéfinit pas le module. Un **alias** aurait affiché les mêmes écrans deux fois ; un
  **module nouveau** aurait imposé de réécrire dix fiches RBAC pour un simple regroupement visuel.
  Le module reste M2 : **les droits ne bougent pas d'un pouce**, et le scénario 57 le sonde
  (caissier fermé, échographiste ouvert sur ses demandes et fermé sur les ordonnances).
  `N.module()` AGRÈGE les écrans de toutes les rangées d'un code — sans quoi le hub n'en montrerait
  qu'une partie et l'on croirait le module amputé.
- **`droitsOrigine` ne retenait pas la bonne rangée** : la boucle gardait la DERNIÈRE portant le
  code, et ne tombait juste que parce que les rangées d'alias — qui ne déclarent aucun rôle, donc
  ouvriraient le module à tous — étaient déclarées avant les canoniques. Une rangée ajoutée après
  aurait suffi à fausser les droits d'origine d'un module entier. Seule la rangée CANONIQUE fait foi.
- **L'IMAGERIE MÉDICALE, et non « l'échographie »** : la clinique fait aussi de l'ECG et des
  radiographies. Rangée « Imagerie médicale » (Poste d'imagerie médicale, Demandes d'imagerie
  médicale, **Tableau Échographie**, Galerie des clichés) ; « Échographie & imagerie » disparaît, et
  « Statistiques de l'échographie » devient « Statistiques de l'imagerie médicale ».
  « Point des ventes & cumuls » devient **« Suivi des ventes »** — hero, fil d'Ariane et ruban.
- **La fusion des visites est ACHEVÉE** : `m2-visites` devient une page-renvoi hors ruban, et
  `m2-rendezvous` tient seul les rendez-vous PRIS et les passages SPONTANÉS — deux filtres les
  distinguent (« Venue », « Venu »). Deux registres sur la même collection finissaient toujours par
  ne pas dire la même chose : l'un filtrait `type !== 'Domicile'`, l'autre non.
- **LA PERSONNE NON ENREGISTRÉE A QUATRE CHAMPS** — nom, prénom, quartier, téléphone — et non plus un
  seul « nom et prénoms » : l'accueil doit pouvoir la RAPPELER et savoir d'où elle vient. Ce sont les
  quatre renseignements du registre papier. Le même jeu de champs sert la prise de rendez-vous ET le
  passage sans rendez-vous ; le dossier patient n'est plus obligatoire ; et cette voie **n'ouvre
  aucun dossier médical ni ne consomme de code CNT** (RG-01), ce que le scénario vérifie par un
  delta sur la collection des patients — compter les homonymes mesurait le jeu de démonstration.
- **La demande d'IMAGERIE s'ouvre au patient adressé de l'extérieur**, comme le laboratoire : une
  échographie prescrite ailleurs se pratique ici. Le dossier naît d'une **fabrique UNIQUE**
  (`dossierExterne` dans `parcours.js`), partagée avec `ouvrirDemandeExterne`. Au passage,
  **le code patient y était construit À LA MAIN** à l'ancien format (« CNT905/26 ») : la règle qui
  vit en deux exemplaires diverge au premier correctif, et celle-ci avait déjà divergé — c'est
  `C.codePatient()` qui fait foi.
- **Le laboratoire voit les DEUX identifiants du dossier à la saisie** : le **code d'analyse**
  (NNNNN-AAAA, le registre annuel) et la **référence** (LAB-NNNNN, la demande dans le logiciel). Ils
  ne se lisaient nulle part sur la modale, alors que ce sont eux qu'on compare au bon papier posé à
  côté de l'automate : saisir sans les voir, c'est risquer de porter le résultat au dossier du
  patient précédent.
- **LE VOCABULAIRE DES SIX SECTEURS, arrêté et UNIQUE** : Laboratoire · Pharmacie · Consultation ·
  Échographie · Maternité · Hospitalisation et soins — plus la **Direction**, transverse, du côté des
  centres de coûts. Les quatre groupes précédents mêlaient consultation et acte, confondaient
  l'imagerie avec les soins et n'isolaient pas la maternité : **trois secteurs sur six étaient
  invisibles**. `D.secteurNormalise()` ramène toute clé — secteur d'acte, centre de coûts, origine de
  prescription — à l'un des six ; « bloc » cesse d'être un mot que l'écran voisin ne connaît pas.
- **La maternité n'est comptable que par le SECTEUR de l'acte** : un accouchement et un pansement
  sont tous deux des « actes », seule la fiche du catalogue les sépare. `groupePrestation(categorie,
  ligne)` accepte donc la LIGNE ; l'appel à un seul argument continue de répondre, les appelants
  anciens n'ont rien à changer.
- **DEUX RÉFÉRENTIELS DE CENTRES DE COÛTS COEXISTAIENT ET NE SE PARLAIENT PAS** : la collection
  portait des codes `CC01…CC92` tirés des secteurs NS 145, les écritures portaient
  `consultation`, `laboratoire`… Le formulaire de saisie proposait les premiers, la ventilation
  analytique comparait aux seconds — **une écriture imputée à la main n'apparaissait dans aucun
  centre**, et le rapprochement affichait des identifiants techniques en minuscules. Le `code` de la
  collection EST désormais l'imputation portée par les écritures, et le scénario 57 vérifie que
  **toutes** les écritures imputées se rattachent à un centre existant.
- `_version` **54** (forme de `centresCouts`). Scénario **57**. État : 286 pages, 57/57 scénarios
  (959 vérifications), 1048 sondages RBAC / 0 promesse.

**Vague 56 (07/09/2026) — RG-10 vaut aussi pour le JEU DE DÉMONSTRATION.** Le moteur refusait une
pièce déséquilibrée (`PR.ecrireEncaissement` contrôle avant d'écrire) pendant que le peuplement en
écrivait 130 qui ne l'étaient pas : chaque ligne tirait son compte au hasard dans TOUT le plan, puis
son sens par **deux tirages indépendants**. Mesuré : **6 157 000 F d'écart** entre débit et crédit,
**68 lignes portant à la fois un débit ET un crédit** — une ligne d'écriture a un sens, pas deux —,
**81 lignes de classe 6 au CRÉDIT** (d'où les charges NÉGATIVES du rapprochement par centre) et
6 lignes de classe 7 au débit. Un invariant qui ne tient pas sur les données qu'on montre ne tient
pas : la balance, le grand livre, le compte de résultat, l'analytique et le seuil de rentabilité
lisaient tous ce journal.

`OPERATIONS_COMPTABLES` décrit 26 opérations réelles (facturation, encaissement, achats, paie,
charges) ; une **PIÈCE** porte deux lignes de même numéro, date, statut et montant, une au débit et
une au crédit, sur des comptes que l'opération désigne. **L'équilibre n'est plus contrôlé après coup,
il est CONSTRUIT.** Le centre de coûts est porté par la pièce, ce qui répartit enfin les charges sur
les six secteurs. `gestesDePoste` valide désormais une **pièce entière** : la validation ligne à ligne
coupait une écriture en deux au hasard de la découpe, laissant la balance boiteuse sans le dire.

**Ce qui n'a PAS été « corrigé » : l'ordre de grandeur.** Les recettes de l'écran de rentabilité
viennent des **lignes de facture** (M8), les charges du **journal** (M12) : deux registres que le jeu
de démonstration ne calibre pas l'un sur l'autre. Le classeur 2025 donnerait bien un ratio
charges/CA, mais l'appliquer reviendrait à **inventer une échelle** — l'écran dit désormais que c'est
la RÉPARTITION entre groupes qui s'y lit, pas le résultat de l'exercice, qui se lit au compte de
résultat. `_version` **55**.

**Vagues 57-59 (06-08/09/2026) — LA COMPTABILITÉ SUR SES DOCUMENTS, ET LE PATIENT EXTERNE.**

- **La liasse fiscale DÉPOSÉE est transcrite** (`assets/js/data-liasse.js`) : liasse remise à la DGI
  le 15/05/2026, code BK505416, six feuillets. `m12-etats-financiers` porte les **cinq onglets** du
  formulaire — bilan, compte de résultat, flux de trésorerie, note 11 « Disponibilités », note 34
  « Fiche de synthèse » — avec les **mêmes références** (AD, AI, XB, ZA…), les mêmes libellés et le
  même ordre : un comptable doit retrouver SES lignes, à LEUR place, pour rapprocher l'écran du dépôt.
  **Deux natures de colonne qui ne se mélangent jamais** : « déposé » CITE le document (des faits, qui
  ne se recalculent pas) ; « exercice en cours » est CALCULÉE depuis le journal par les préfixes
  SYSCOHADA — et reste **vide** là où le journal ne porte rien, un zéro y ferait croire à un solde nul.
- **Un compte de tiers change de côté selon son sens** : le plan SYSCOHADA emploie les mêmes comptes de
  classe 4 pour les créances et pour les dettes. Solde débiteur → actif, créditeur → passif. Sans cette
  règle, le même compte paraissait des deux côtés, et du côté où il n'a rien à faire il sortait en
  NÉGATIF — ce qui ne veut rien dire sur un bilan.
- **Les écarts internes du document déposé sont CONSERVÉS, non arbitrés** — six recensés et affichés :
  la CAFG N-1 (le tableau des flux porte la valeur ajoutée N-1 au lieu de la CAFG), la variation du
  besoin de financement qui ne se retrouve pas à partir de ses composantes, ZB, les flux opérationnels
  et de financement qui diffèrent entre le tableau des flux et la note 34, la trésorerie nette à 450 F
  près. Les corriger ferait diverger le logiciel de ce que la clinique a **réellement déposé** —
  précisément ce qu'un contrôle vient comparer. **À noter : la MARGE COMMERCIALE y est NULLE**, ce qui
  confirme RG-02 par un document déposé.
- **Le BILAN D'OUVERTURE** (`m12-ouverture`, journal **AN** ajouté au référentiel) : un exercice
  s'ouvrait sur un journal vide, et il fallait relire tout l'historique pour connaître la situation au
  1ᵉʳ janvier. **Seules les classes 1 à 5 se reportent** — un compte de charge ou de produit ne passe
  jamais à l'exercice suivant, il est soldé par le résultat (compte 13) ; le reporter reviendrait à
  compter deux fois la même dépense. Report **refusé s'il ne s'équilibre pas** (RG-10) et refusé une
  seconde fois (double à-nouveau) ; la pièce naît en **brouillon**.
- **Immobilisations : l'amortissement court au SEMESTRE**, de la date d'acquisition à aujourd'hui.
  L'annuité ne se constate qu'à la clôture : un bien acquis en février et un bien acquis en novembre
  portaient le même amortissement au 31 décembre. Le dernier semestre solde le reliquat, de sorte que
  la somme des dotations fasse exactement la valeur d'acquisition. Un bien **cédé** cesse de s'amortir
  à sa date de sortie et quitte le bilan ; sa fiche reste au registre. Colonnes renommées (**Date
  d'acquisition**, **Valeur d'acquisition**) et colonne **Cession / sortie** ajoutée. Un onglet
  **« Report au bilan »** range les biens par rubrique de la liasse (AE→AS, sous-totaux AD/AI/AQ,
  total AZ), rattachés par le **compte SYSCOHADA** et non par la catégorie d'usage : ses trois totaux
  SONT les colonnes BRUT / AMORT. / NET de l'actif immobilisé.
- **Les FILTRES EN FORCE sont portés sur la pièce** (`print.js`). Un état imprimé depuis un écran
  filtré ne montrait qu'une PARTIE des données, et rien ne le disait : deux tirages du même état, sur
  deux filtres différents, sortaient identiques de présentation et différents de contenu. Le relevé est
  fait **sur la page** — listes, dates, recherche, listes à recherche — plutôt que déclaré par chaque
  appelant : il y a plus de cent trente états imprimés, et un mécanisme qu'il faut penser à câbler cent
  trente fois manquera quelque part. `filtres: false` le retire d'un état qui ne dépend d'aucun écran
  filtré (une facture, un certificat).
- **Bon de transfert** : le registre n'affichait que « N articles ». Le **détail des lignes** est
  consultable et **imprimé**, avec son **TOTAL** calculé depuis les lignes réellement imprimées — on
  ne signe pas un bon qui ne dit pas ce qu'il transporte. **« Modifier » existe et REFUSE en
  expliquant** : le bon a déjà déplacé le stock, deux mouvements symétriques ont été écrits ; le
  corriger laisserait les deux stocks faux sans qu'aucun mouvement ne le dise (RG-03). Le chemin est
  nommé : archiver, puis réémettre.
- **Le PATIENT EXTERNE, ses quatre natures de demande** : `m1-externe` porte cinq vues — analyses,
  maternité, hospitalisation, imagerie médicale, résultats. **Ce sont des VUES**, jamais de secondes
  collections. La modale porte la **nature** et les deux catalogues, et chaque nature passe par SA
  fabrique du parcours. **Rien ne se saisit avant la caisse** : la commande de saisie d'un examen non
  réglé reste **visible et verrouillée**, et le verrou **nomme** où la balle se trouve. **La saisie
  reste au poste** — la rouvrir à l'accueil créerait une seconde voie d'écriture sur la même donnée, et
  l'accueil n'a pas à saisir un résultat biologique (RG-13).
- **Une fabrique UNIQUE pour le dossier du patient adressé de l'extérieur** (`PR.dossierExterne`),
  partagée par le laboratoire, l'imagerie et l'accueil. Au passage : le code patient y était construit
  **à la main** à l'ancien format « CNT905/26 » — la règle qui vit en deux exemplaires diverge au
  premier correctif, et celle-ci avait déjà divergé.
- **La passe « somme », RE-MESURÉE** : sur 159 `P.tableau`, 87 portent des montants et **33** ne
  déclaraient pas `somme`. Examinés un par un, **un seul** méritait son total (la balance âgée des
  comptes de tiers, désormais totalisée) : les autres sont des **barèmes** et grilles tarifaires, des
  **récapitulatifs hétérogènes** (brut + retenues + net ne s'additionnent pas), des **pièces
  mono-lignes**, des **tables tronquées** (`slice`) où un total partiel se lirait comme total du
  compte, le **SIG en cascade** et le **formulaire de la liasse**, qui porte ses propres sous-totaux.
  Le jugement de la vague 51 est confirmé, cette fois par un inventaire.
- Autres : `m5-demandes` accepte un patient adressé de l'extérieur ; **« Statistiques des
  hospitalisations »** rejoint le pilotage (la durée moyenne de séjour ne porte que sur les séjours
  TERMINÉS) ; le grand livre dit « Achat de marchandises — Médicaments », le libellé nomme l'opération
  et non le fournisseur du jour ; `build/_pdftext.js` extrait la couche texte des PDF engendrés.
- **Leçon de sonde** : lire une colonne **par son NOM**, jamais par son rang — compter les cellules
  depuis la fin donnait la valeur nette là où l'on croyait lire l'amortissement, et la sonde mesurait
  sa propre supposition. Scénarios **58** et **59**.

**Vague 60 (08/09/2026) — LA MATERNITÉ SUR SON CAHIER, ET CE QU’UNE DONNÉE QUI CHANGE NE DOIT PAS
EFFACER.** Un dossier obstétrical RÉELLEMENT REMPLI (exemplaire de recette du 06/09) a servi de cas
de recette pour M4 : les scans de `suite/` donnaient les formulaires vierges — on savait quelles
cases existent, pas comment elles se remplissent ni lesquelles se remplissent ensemble. **Aucune
identité du document n’est reprise** : c’est sa STRUCTURE qui est exploitée, le jeu invente ses
propres patientes.

- **`m4-dossier-obstetrical` — le cahier qui tient les autres.** Le prototype portait déjà la CPN,
  le partogramme, l’accouchement, le nouveau-né et les CPoN, chacun dans son écran et rien pour les
  relier ; or le formulaire national est UN SEUL cahier, ouvert à la première consultation prénatale
  et refermé après la surveillance du deuxième jour. L’écran est une **LECTURE** qui rassemble — il
  ne duplique aucun geste, chacun reste à son écran. Le **numéro suit le registre papier**
  (`NNNNN/AA`, série annuelle), comme le code d’analyse et les pièces certifiantes. La **date
  probable se DÉDUIT de la DDR** (280 jours) : la saisir à part ouvrirait deux dates qui ne se
  recoupent pas. **Le risque n’est pas un champ** : il se déduit du CUMUL des douze facteurs cochés,
  et les cases se rangent dans UNE carte — sans elle, chaque écran voulant savoir si la grossesse
  est à risque devrait connaître les douze noms de champ, et un facteur ajouté en oublierait un.
- **Le peuplement suit le formulaire, pas l’inverse.** Une visite de CPN portait quatre chiffres ;
  elle porte désormais la **grille entière** (40 lignes, groupées Venue / État général / Examens /
  Prévention / Conseils / Conclusion / Suite) — c’est ce qui permet de lire une ÉVOLUTION plutôt
  qu’un état, et un écran qui ne montrerait qu’une visite perdrait exactement l’information que la
  grille existe pour donner. S’y ajoutent la **délivrance** (mode, gestes GATPA, hémorragie
  quantifiée), l’**examen du placenta**, l’**issue en quatre questions** — ce sont EXACTEMENT les
  quatre que les indicateurs nationaux comptent —, la **fiche de surveillance intégrée** (mère ET
  bébé sur la même grille de temps : c’est la coïncidence des deux séries qui fait la valeur de la
  feuille unique), les **éléments H4→H24** du nouveau-né, l’**Apgar élément par élément** (le score
  seul ne dit pas CE QUI manquait, et c’est ce que la réanimation vise) et le **partogramme coté**
  (chevauchement 0-3, descente en travers de doigts, durée des contractions, ocytocine).
- **`dash-maternite` — la maternité est un POSTE, pas une spécialité du médecin.** La sage-femme de
  garde arrive avec trois questions : qui est en travail, quels termes tombent cette semaine,
  quelles grossesses sont à risque. Le tableau du médecin n’en traite aucune. Premier regard : les
  **partogrammes ouverts** — un partogramme non clos est une femme en salle de travail, c’est la
  seule chose qui n’attend pas. Un **terme dépassé** n’est pas une erreur de saisie : c’est la femme
  qu’il faut rappeler.
- **La couverture d’assurance est DATÉE** (`couverturesAssurance`, moteur `PR.couvertureALaDate` /
  `PR.changerCouverture`). Un assuré change de compagnie d’une année à l’autre ; le dossier ne
  portait qu’un ÉTAT, et le mettre à jour effaçait la couverture sous laquelle les factures de
  l’année précédente avaient été émises — la créance de l’ancienne compagnie devenait
  injustifiable. **C’est le mécanisme de la grille des primes et des plages par lot de réactif**, et
  ce n’est pas un hasard : chaque fois qu’une donnée de référence change alors que des pièces ont
  été émises sous l’ancienne, la réponse est la même — versionner par date, jamais écraser. La
  fiche du dossier reflète TOUJOURS la couverture en force **aujourd’hui** (une bascule datée du
  mois prochain ne change pas ce que la caisse applique ce matin) ; `debut: null` signifie « depuis
  l’ouverture du dossier », parce que l’historique **ne peut pas inventer une date d’effet que
  personne n’a saisie**. Motif et date d’effet sont obligatoires. `carteValide` et `souscripteurDe`
  lisent désormais la couverture DE LA DATE, et les trois copies locales de `carteValide` (M1, M8,
  M9) délèguent au moteur — une copie aurait divergé au premier changement.
- **L’agenda s’apure sans rien perdre.** Un rendez-vous honoré n’a plus rien à faire dans la fenêtre
  de l’agenda ; mais « apurer » ne veut dire ni supprimer ni **archiver** : un rendez-vous honoré
  EST la consultation, l’archiver effacerait l’acte des dossiers, des ordonnances et des
  statistiques. Il change donc d’ONGLET, pas d’existence — d’où `filtreBase` au kit : **la liste
  principale est une VUE, pas la collection**. Deux états manquaient au référentiel : **REPORTÉ**
  (une nouvelle date est fixée, l’ancienne reste écrite) et **NON HONORÉ** (le patient n’est pas
  venu) ; les confondre ferait disparaître l’absentéisme, qui est précisément ce que l’accueil veut
  mesurer. Un rendez-vous planifié dont la date est passée est **signalé, jamais tranché** — le
  décider tout seul inventerait une absence.
- **Une période SE NOMME.** Les six onglets de `dash-da` affichaient « les 30 derniers jours » : une
  fenêtre glissante, sans date, impossible à déplacer. Un cumul dont on ignore les bornes ne se
  rapproche d’aucun document, et « le mois » d’un tableau qui court sur trente jours à cheval sur
  deux mois n’est le mois de personne. Les bornes sont désormais **CALENDAIRES**, la période **se
  choisit** (une date pour le jour et la semaine, une liste pour le mois, le trimestre, le semestre
  et l’année, l’année courante par défaut), et la période de comparaison est **l’unité de même
  nature qui précède** — pas « la même durée avant ».
- **Filtres avancés M9** : la balance âgée des créances filtre sur la **date des factures**, la
  compagnie, l’ancienneté retenue et un seuil de créance — l’ancienneté restant comptée par rapport
  à aujourd’hui : les confondre ferait vieillir une créance parce qu’on a rétréci la fenêtre. Le
  référentiel des compagnies gagne cinq filtres (convention, créance, ancienneté, portefeuille,
  cartes expirées), et `ancienneteAssureur` est une **fabrique unique** partagée avec la balance —
  deux découpages divergents ne se verraient qu’en réunion. Les filtres étant relevés SUR LA PAGE
  par `print.js`, l’état édité retrace la sélection sans être recâblé.
- **Piège payé une troisième fois** : `var ancresDA = {}` déclaré APRÈS l’appel de `afficher()` —
  la déclaration est hissée, l’affectation non, et le premier onglet se peignait sur `undefined`.
  Toute affectation lue par un premier rendu se déclare AVANT l’appel.
- **Deux leçons de sonde.** (1) Un scénario qui change de RÔLE le RESTAURE : le précédent laissait
  la session sur « réception », à qui M4 est fermé — `#page-content` était nul et la
  sonde mesurait un 403, pas l’écran. (2) **Le magasin du navigateur est un `localStorage`,
  et il sature.** La fiche de surveillance intégrée portée sur les 48 accouchements de l’année
  faisait ~900 relevés et 5 139 Ko à écrire : le jeu restait en mémoire et se perdait au changement
  d’écran. Elle couvre les **48 premières heures** — elle ne se tient donc que pour les
  accouchements récents, et elle s’affiche au dossier. Un peuplement qui déborde le quota ne montre
  RIEN.
- Scénarios **60** et **61**. `_version` **56**. État : 291 pages / 0 erreur,
  61/61 scénarios (1022 vérifications), 1064 sondages RBAC / 0 promesse / 0 lecture non dite.

**Vague 61 (14/09/2026) — LES FEUILLETS 7/51 ET 8/51 DE LA LIASSE, ET L'IMAGERIE À CINQ MODALITÉS.**

- **`m12-compte-resultat` est désormais le FEUILLET 7/51** de « Documents comptable exemplaire.pdf » (page 3) :
  références TA → XI, libellés, repères A/B/C/D, colonne (2), notes, sous-totaux, en-tête de dépôt (date,
  dénomination, IFU), colonnes « Exercice au 31/12 (N) / (N-1) — NET (1) ». La cascade « maison » est
  retirée : le comptable rapproche l'écran du dépôt ligne à ligne. **`m12-flux-tresorerie` (nouveau)
  est le FEUILLET 8/51** (page 4) : ZA, FA→FE, ligne « Variation du BF / FB+FC+FD+FE : », ZB, FF→FJ, ZC,
  FK→FN, ZD, FO→FQ, ZE, ZF, ZG, ZH, puis la **ligne de contrôle** « Trésorerie actif N − Trésorerie passif
  N » et la note (1). Même moteur pour les deux (`tableFeuillet`), même rendu à l'écran ET sur la pièce
  imprimée — deux rendus auraient pu montrer deux formulaires.
- **Deux sources, jamais dans la même colonne** : « Liasse déposée » CITE `SIGH.liasse` (N = 2025,
  N-1 = 2024) ; « Exercice AAAA — calculé » (défaut : l'année en cours, arrêtée au jour) CALCULE depuis
  les écritures VALIDÉES, et sa colonne N-1 CITE le dépôt si l'exercice précédent a été déposé. Les
  **sous-totaux calculés suivent les formules imprimées** (`FORMULES_RESULTAT`, `FORMULES_FLUX` : « XC =
  XB + RA + RB + somme TE à RJ »…) — jamais saisis. Une ligne de détail que le journal n'alimente pas
  reste « — » ; le dépôt porte ses zéros, on les cite.
- **UN COMPTE N'ALIMENTE QU'UNE LIGNE : le préfixe le PLUS LONG gagne.** « 654 » va à RO et non à RJ
  (« 65 ») ; TE lit le compte 73 et non plus les 6032/6033 qu'il partageait avec RD/RF — deux lignes au
  même préfixe comptaient deux fois la même écriture. RL/RN/TJ/TN/RO ont reçu les comptes du SYSCOHADA
  révisé (691, 697, 799, 82, 81). Un compte de gestion sans ligne est **nommé**, jamais compté en silence.
- **Le tableau des flux calculé est la méthode indirecte**, bouclée par le contrôle du formulaire : CAFG
  = classes 6/7/8 hors non-décaissables (68, 69, 79, 81, 82, 654, 754) ; FC = −Δ classe 3 ; FD/FE suivent
  **chaque compte de tiers de son côté** à l'ouverture et à la date (SYSCOHADA) ; FF/FG/FH = débits des
  21 / 22-24 / 26-27 ; FO/FQ = crédits/débits des 16-18 ; FN = débits du 465 (sorti du BF pour ne pas
  compter deux fois). **Les à-nouveaux (journal AN) forment l'ouverture, jamais un flux** — sinon le
  capital paraîtrait apporté dans l'année. Contrôle : classe 5 à la date = ZH ; un écart NOMME les comptes
  non classés. Sur le jeu actuel : concordant. ZA vaut 0 en 2026 faute d'à-nouveaux, et l'écran le dit.
- **Le contrôle du DÉPÔT compare chaque sous-total à SES composantes DÉPOSÉES, sans cascade.** Le premier
  jet cascadait les recalculs et accusait ZG et ZH, qui se recoupent pourtant avec le ZB déposé. Résultat
  mesuré : les 9 sous-totaux du compte de résultat 2025 ET 2024 se recalculent à l'identique ; au tableau
  des flux, « Variation du BF » (N et **N-1** — écart du document que `ECARTS` ne nommait pas pour 2024)
  et ZB (N) ne se recalculent pas — signalés, non arbitrés.
- **L'IMAGERIE : UN SOCLE, CINQ MODALITÉS — et non quatre modules.** Réponse au questionnaire
  `AJOUTEDEMODULES.txt` : la demande (`PR.ouvrirDemandeImagerie`), la ligne payable, le verrou de caisse,
  les états demandée → payée → exécutée → validée, le CR par variables, le rendu au prescripteur et la
  galerie existaient pour l'échographie. Radiographie, mammographie, scanner et IRM s'y branchent : **la
  modalité est une PROPRIÉTÉ DE L'EXAMEN** (`D.IMAGERIE.MODALITES`, `modalite` sur chaque examen, lue au
  catalogue — le CR n'en porte pas, il pourrait contredire son examen). Quatre écrans
  (`m2-imagerie-radiographie`, `-mammographie`, `-scanner`, `-irm`) et `m2-imagerie` sortent d'**une
  fabrique** (`ecranTableauImagerie`), chacun avec son indicateur propre (fractures relevées, ACR ≥ 4 par
  sein, injections et réactions, gadolinium). Registre des demandes : colonne et filtre « Modalité » ; poste
  d'imagerie : « Activité par modalité » (clic → tableau, gardé par RBAC).
- **Les rubriques rédigées dépendent de la modalité** (`rubriquesLibres`) : l'échographie garde Annexes +
  Conclusion (le brouillon de l'échographiste) ; les autres suivent le plan radiologique — Résultats,
  **Conclusion obligatoire**, Recommandation. `saisirCR`/`detailCR`/`imprimerCR` lisent ces rubriques au
  lieu de `annexes`/`conclusion` en dur ; type de variable **`multiple`** (séquences IRM, niveaux
  rachidiens). Mammographie : **classification ACR par sein** ; scanner : l'injection est une donnée de
  sécurité (« aucune réaction » s'écrit) ; IRM : contre-indications vérifiées AVANT l'examen.
- **Tout est PROPOSITION, et le dit** : 16 examens et leurs variables marqués `aValider` (aucun modèle de
  compte rendu remis) ; **16 tarifs d'ATTENTE** (`IMAGERIES_ATTENTE`, hors `batir()` — aucune colonne à
  inverser, `tarifProvisoire` + motif daté, l'assuré paie moins) par l'arbitrage « plus aucun montant nul ».
  **Pas de DICOM/PACS** : le logiciel tient demande, CR et clichés joints (option A du questionnaire).
- **Droits** : écrans de M2 → droits de M2. Surcharges miroir de `m2-imagerie` : poste d'imagerie
  (`echographiste`) en écriture sur les quatre tableaux, accueil fermé, chirurgien en lecture. **Qui réalise
  radiographie/scanner/IRM reste à arbitrer** (aucun radiologue au tableau des comptes).
- `_version` **57** (examens et variables des quatre modalités semés au socle). Scénario **62**. État : 296 pages /
  0 erreur, 62/62 scénarios (1042 vérifications), 1091 sondages RBAC / 0 promesse / 0 lecture non dite.

**Vague 62 (14/09/2026) — LE PARCOURS DE CONSULTATION REFAIT, LES TIROIRS RÉPARÉS À LA RACINE, ET LE QUOTA TENU.**
Menée par quatre agents aux fichiers disjoints (consultation · transferts · peuplement · balayage des tiroirs), sur
`METHODOLOGIE.txt`, `DOSSIER CONSULTATION.txt` et `CORRECTIONTOMADE.txt`.

- **Dossier → Fiche → Prescription → Caisse, dans cet ordre et pas autrement.** Nouvel écran
  **`m2-dossiers-consultation`** (rangée « Consultations & prescriptions », avant la fiche) : anamnèse, antécédents
  en trois catégories, données préalables, antécédents et examen **obstétricaux** pour les femmes, état général, et
  l'**examen IPPOA par appareil** (neuf blocs repliables, bouton « Normal par défaut » qui ne remplit que les champs
  vides) stocké en **`examensPhysiques`** (objet par appareil — `D.examensPhysiquesDe(d)` relit les dossiers
  anciens à champs plats sans les réécrire). Référentiels dans `assets/js/data-dossier.js`. Les constantes de
  l'accueil sont COPIÉES datées (`constantesAccueil`) et affichées en lecture — jamais ressaisies. Un second dossier
  ouvert pour le même patient est refusé en nommant le premier.
- **La fiche REFUSE sans dossier enregistré** (refus nommé, code `SANS_DOSSIER`), en fait le **récapitulatif**, et
  c'est la SEULE porte de prescription : médicaments, analyses, **imagerie (cinq modalités)**. Moteur exposé
  `SIGH.consultationZone2.enregistrerFiche` : consultation liée (`dossierConsultationId`), `PR.prescrire`, cycle
  avancé (en attente labo si analyses/imagerie, sinon clôturé), orientation (RDV de contrôle, admission,
  observation, référence). Un échec de prescription DÉFAIT la consultation — rien d'écrit à moitié. Les actes
  restent en `m2-prescriptions`.
- **UNE facture globale** : la création des demandes d'imagerie est sortie en fabrique unique `creerDemandesImagerie`
  (partagée par `ouvrirDemandeImagerie` et `PR.prescrire`) — lignes payables `demandeImagerieId` DANS la même
  pièce que médicaments et analyses ; `PR.encaisser` libère ligne à ligne.
- **L'onglet « dossier à deux zones » quitte `m1-patients`** (Zone 1 y reste) ; `m1-dossier-etendu` renvoie au
  nouvel écran. RBAC : accueil et échographiste FERMÉS, caissier/laborantin/anesthésiste sans accès, aide-soignante
  et surveillant en lecture. **Cet arbitrage de l'utilisateur REMPLACE, pour la Zone 2, la « fusion à zones dans
  un seul `m1-patients` » du 31/08.** La fiche patient gagne l'onglet **« Imagerie médicale »**.
- **Imagerie — les corrections de l'échographiste (14/09)** : « Annexes » retirée, mesures en TEXTE, options
  « Autre » qui n'ouvrent leur champ QUE choisies, **sacs gestationnels et embryons/fœtus RÉPÉTÉS** en blocs
  repliables selon le nombre déclaré, nouvel examen `IMG-ECHO-OBS1E` (1er trimestre évolué, tarif de
  l'obstétricale), champ **Provenance** à l'ouverture du CR. Le document proposé écrasait tout le fichier
  d'imagerie : les corrections ont été appliquées une à une, rien d'autre n'a été retiré.
- **LES TIROIRS VIDES : deux défauts de SOCLE, pas trente et un écrans.** `K.grid([[libellé, valeur], …])` — la
  forme employée par 31 vues de détail — n'existait pas (le tableau partait dans `class`) : `grid()` accepte
  désormais les deux formes. Et **`el(tag, attrs, a, b, c)` ignorait tout enfant au-delà du premier** : il les
  ajoute tous, et `append` aplatit les listes imbriquées. Le balayage de 296 pages (831 tiroirs ouverts à 1440 px,
  338 à 400 px) a levé le reste : tiroir de repli qui vidait l'enregistrement brut (« mereCode »,
  « [object Object] ») → construit depuis les colonnes et champs déclarés ; nœuds rendus en texte dans
  `descList`/`miniTable` ; débordement des KPI sous 640 px.
- **Transferts gros → détail** : 20 bons / 139 lignes / 278 mouvements peuplés (`transfertsGrosDetail`, stocks
  inchangés = état APRÈS transferts, donc jamais négatifs) ; onglet « Vue détaillée par article », tiroir et
  impressions portant chaque ligne avec TOTAL par `somme`. Corrigés au passage : KPI de valeur à 0 sur les bons
  multi-lignes, numérotation qui repartait à TR-00001, double comptage « pharmacie reçu ». `U.dataTable` expose
  `lignesFiltrees` : l'état imprime ce que l'écran montre.
- **Peuplés** : 35 demandes d'imagerie (cinq modalités, quatre états, CR liés), 121 relevés de constantes
  d'accueil, 12 patients externes / 28 demandes d'analyses, 7 certificats externes, et **dix fiches patient
  complètes** (codes dans `_fichesDemo` du magasin : `CNT913/25` agent, `CNT/13/26` grossesse + accouchement,
  `CNT/174/26` carte expirée, `CNT/1109/26` externe…). Bugs de lecture corrigés : feuille de température lue sur
  `releves`, accouchements sur `dateHeure`, naissances sur `mereId`, suivi sur `termeSA`/`observations`,
  `valideBiologiquePar`.
- **LE QUOTA : deux corrections du magasin.** (1) **Les champs nuls ne s'écrivent plus** (`sansNuls` au
  `JSON.stringify`) : ~480 000 caractères de `"acteCode":null` — un null se relit `undefined`, vérifié : aucun
  enregistrement n'est comparé à `=== null` ; chaînes vides, `false` et `0` restent écrits ; un null DANS un
  tableau se garde. Conséquence à connaître : **`'champ' in record` et `Object.keys(record)` ne voient plus un
  champ nul** — une sonde l'a payé. (2) **L'alarme « stockage saturé » était une FAUSSE alarme** : elle criait au
  premier refus, avant la seconde tentative compressée qui réussit ; `storage.set(k, v, silencieux)` ne l'annonce
  plus qu'à l'échec de la seconde. Le jeu frais passe de 5,13 à 4,89 M de caractères.
- `_version` **58**. Scénarios **63** (parcours consultation) et **64** (corrections échographie). **Leçon
  d'orchestration** : un agent qui LANCE une commande en arrière-plan puis s'arrête « en attendant » rend un
  rapport vide — lui redemander explicitement de lire sa sortie.

**Vague 63 (21/09/2026) — LA DIRECTIVE D'ÉCHOGRAPHIE RELUE JUSQU'AU BOUT : LE RYTHME CARDIAQUE
N'ÉTAIT PAS SUPPRIMÉ, IL ÉTAIT DÉPLACÉ.** Audit de `nouvelle_directive.txt` contre le code : la vague 62
en avait appliqué l'essentiel — Annexes retirée de toutes les échographies, `saisieTexte` passant chaque
mesure en texte, Provenance à l'en-tête, pelvienne (vacuité, « intermédiaire », hétérogène → précision,
Contenu, ovaires dynamiques), 1er trimestre (localisation « Autre », trophoblastique en quatre valeurs,
vésicule vitelline, blocs obsolètes retirés, duplication `repete` des sacs), examen évolué (Fœtus,
BIP/PC/LF, activité cardiaque « Autre »), obstétricale (présentation, placenta, abondance, « mesure des
04 citernes », trouble, Synthèse retirée). **Un seul écart, et il tenait à une phrase lue à moitié.**

- **La directive dit DEUX choses du rythme cardiaque, et la seconde annule la lecture qu'on fait de la
  première** : « suppression du champ *Rythme cardiaque (bpm)* **initial** », puis, trois lignes plus
  bas, ce même champ figure dans la liste de ceux qui **passent en texte** — entre le LCC et l'âge
  gestationnel correspondant. Ce n'était pas une suppression, c'était un **déplacement**. La vague 62
  s'était arrêtée à la première puce et avait retiré `EM_BPM` du référentiel : l'échographiste n'avait
  plus où porter le rythme qu'il mesure, et rien ne le disait. Il revient à SA place — après le LCC, et
  après la biométrie (BIP, PC, LF) sur l'examen évolué, où la directive place celle-ci « immédiatement
  après le bloc LCC ».
- **Une variable d'imagerie vit AU MAGASIN** (`variablesImagerie`, semée depuis `D.IMAGERIE`) : la
  rajouter sans incrémenter `_version` aurait laissé chaque poste sur son jeu de la version 58, et
  l'échographiste n'aurait vu aucun changement. `_version` **59**.
- **Une sonde écrite sur une lecture fausse verrouille l'erreur.** Le scénario 64 affirmait
  `rythmeRetire: !v('IMG-ECHO-OBS1', 'EM_BPM')` — il ne mesurait pas la directive, il mesurait ce que la
  vague 62 avait compris d'elle, et il aurait refusé la correction. Il vérifie désormais la **position**
  (`EM_BPM` après `EM_LCC`, après `EM_LF` sur l'évolué, avant `EM_AG`) et que le champ se rend bien
  en `type="text"`.
- Deux libellés alignés sur la directive : l'examen devient « du 1er trimestre **évolué** » (c'est le
  trimestre qui l'est, non l'échographie) et la présentation « **transversal** dos supérieur / inférieur ».

**« AMNIOS » : LA QUESTION POSÉE, LA RÉPONSE APPLIQUÉE (21/09/2026).** Trois écarts de vocabulaire
séparaient la directive de la terminologie médicale. Ils n'ont pas été corrigés d'office : ils ont été
**signalés**, et l'un a reçu sa réponse. La directive écrivait « **Amnios** » dans l'abondance du liquide
amniotique ; le code portait `anamnios` — *amnios* est la membrane, *anamnios* l'absence de liquide, et la
lecture évidente était la coquille. **Elle était fausse : l'échographiste a confirmé « Amnios ».** C'est SON
vocabulaire qui fait foi sur la pièce qu'il signe — la liste dit ce qu'il écrit, elle ne lui enseigne pas sa
nomenclature. Le mot est appliqué, et `_version` passe à **60** : les OPTIONS d'une variable vivent au
magasin comme la variable elle-même, un poste amorcé en 59 aurait continué de proposer le mot qu'il
n'emploie pas. **La leçon porte au-delà du mot** — corriger d'office aurait imposé au professionnel un
terme qu'il n'emploie pas, sans que personne ne s'en aperçoive ; signaler a suffi à obtenir la réponse en
une phrase.

**DEUX DIVERGENCES RESTENT OUVERTES**, faute de la même réponse :

| La directive écrit | Le code porte | Pourquoi on ne tranche pas |
|---|---|---|
| « Oligo-amnios », « Hydramnios » | `oligoamnios`, `hydramnios` | orthographe médicale usuelle, sans trait d'union |
| « Ovaire droit **normal** » parmi les valeurs qui ouvrent Taille et Échostructure | les trois valeurs **anormales** | détailler la taille d'un ovaire déclaré normal n'a pas d'objet ; lu comme une coquille pour « ovaire gauche anormal » |

**Vague 64 (22/09/2026) — LE BESOIN EN FONDS DE ROULEMENT ET LE TABLEAU DÉCISIONNEL
(BFR_TABLEAU.txt).** Trois piliers, un moteur, et une découverte de placement.

- **LE MOTEUR VIT AU SOCLE** (`PR.bfr`, exposé `SIGH.bfr` pour être SONDÉ) : le BFR se lit depuis
  la comptabilité (M12), depuis le pilotage (PIL), depuis les deux tableaux de la Direction et
  depuis le moteur d'alertes, qui n'appartient à aucun écran. Une page ne charge que le module du
  sien — le poser dans un module l'aurait rendu invisible aux quatre autres. Il **n'invente rien** :
  `créances` (part assureur des factures assurées + restes à charge, la MÊME définition que la
  balance âgée de M9) + `stocks` (valorisés par `S.valeurUnitaire`, donc selon la méthode que la
  Direction a choisie) − `dettes fournisseurs` (M7). **Un composant non amorcé SE DIT** : `incomplet`
  porte son nom, parce qu'un BFR amputé de ses dettes est SURESTIMÉ et qu'un chiffre faux qui a l'air
  juste est pire qu'une case vide.
- **L'AMORÇAGE DES ACHATS A DÛ REMONTER AU SOCLE** — et c'est le vrai enseignement de la vague. Les
  quatre registres M7 (`besoins`, `commandes`, `livraisons`, `facturesFournisseurs`) étaient semés
  PAR LEURS ÉCRANS : sur un poste qui n'avait jamais ouvert « Factures fournisseurs », la dette
  valait zéro et le BFR s'en trouvait surestimé d'autant. La graine reste celle de l'écran (911) :
  le jeu ne change pas d'un franc, et l'insertion ne décale aucun tirage voisin. M7 **appelle**
  désormais `SIGH.semerAchats` au lieu d'en porter une copie.
- **LE QUOTA DU NAVIGATEUR EST LA CONTRAINTE, ET ELLE ÉTAIT DÉJÀ ATTEINTE.** Mesuré : le magasin
  persisté pesait **4 853 Ko pour ~250 Ko de marge** avant refus d'écriture, et la soupape de
  compression s'armait en cours de parcours d'essai (une écriture à ~2,4 s : l'interface gèle).
  Trois réductions ont rendu la marge, et aucune ne coûte un écran :
  le jeu d'achats est **volontairement réduit** (20 bons, 15 commandes, **2 à 4 lignes** et non 2 à 7
  — les lignes sont recopiées une seconde fois sur le bon de livraison) ; les **bons de besoins ne
  sont PAS semés au socle**, le BFR ne les lit pas et `semerAchats(complet)` les réserve à
  l'ouverture de M7 ; et les **extraits du journal d'audit passent de 140 à 100 caractères**, ce qui
  PROTÈGE LE NOMBRE D'ENTRÉES — entre quatre cents gestes journalisés avec une citation plus courte
  et deux cent cinquante avec une citation longue, RG-12 penche du premier côté. État : **4 786 Ko
  pour ~330 Ko de marge**, soit moins qu'avant la vague. **8 commandes sont livrées d'office** — le
  tirage n'en donnait que deux, donc deux factures fournisseurs, donc une dette anecdotique : un jeu
  de démonstration doit montrer ce qu'il sert à montrer.
  **Toute collection ajoutée au socle doit désormais se mesurer avant d'être semée** — et la
  sentinelle du banc d'essai est scindée en deux assertions qui disent chacune ce qu'elles mesurent
  (le tampon s'est vidé / le jeu tient sous le quota), la seconde **portant les kilo-octets** : un
  échec qui ne dit pas de combien on déborde n'apprend rien.
- **`m12-bfr`** (rangée `secondaire` « Contrôle de gestion & trésorerie », domaine Financier —
  le module reste M12, les droits ne bougent pas d'un pouce) MONTRE d'où vient chaque composante et
  **rend chaque source ouvrable** : un agrégat qu'on ne peut pas redescendre est un agrégat qu'on ne
  vérifie jamais. **L'encours se lit À UNE DATE, le flux SUR UNE PÉRIODE** — les afficher sous le
  même filtre sans le dire ferait croire que le stock détenu dépend de la fenêtre qu'on regarde.
- **`m12-tableau-decisionnel`** (PIL) — la grille « objectif fixé / réel atteint » sur les quatre
  axes du document. **AUCUN OBJECTIF N'EST DOCUMENTÉ** : ni le cahier des charges, ni le rapport de
  cadrage, ni la liasse déposée ne fixent de cible de DSO ou de taux d'occupation. Les huit cibles
  de `D.OBJECTIFS_PILOTAGE` sont des PROPOSITIONS, marquées à valider et corrigeables à l'onglet
  « Objectifs & seuils » — un objectif chiffré finit dans une évaluation, et faire juger un poste
  sur un nombre que personne n'a arrêté serait une faute. Corriger une cible l'ARRÊTE (la mention
  tombe, la date et l'auteur sont portés). **`sens` dit de quel côté se trouve la réussite** : sans
  lui, la grille colorerait en rouge un DSO excellent. **« Non calculable » n'est pas « zéro »** :
  un indicateur dont la donnée manque le dit, il ne s'affiche pas en échec.
- **`m12-cout-activite`** (pilier C) — **CE QUI EST CALCULABLE L'EST ; CE QUI NE L'EST PAS SE DIT.**
  Le consommable réel se lit (sortie de stock au CUMP, rattachée par son justificatif) ; le **coût
  de personnel n'est PAS imputable à un séjour** — aucun document ne donne la clé, et le prototype
  refuse depuis toujours d'en inventer une. L'écran calcule donc une **marge sur consommables**, la
  nomme ainsi, et dit ce qu'elle ne comprend pas. La **prévision saisonnière** applique au BFR
  l'indice des admissions du mois : une projection, pas une prévision budgétaire, et l'écran le dit.
- **L'alerte de recouvrement ROUTE, elle ne décide pas du seuil** : la source `creance_agee` de
  `notifications.js` lit `PR.alertesRecouvrement`, dont le seuil vit dans `objectifsPilotage`. Le
  jour où la Direction passe de 60 à 45 jours, le moteur d'alertes n'a rien à changer.
- Correctif au passage : la fiche fournisseur proposait « soldée » à l'édition quand le registre,
  son filtre et son indicateur comptaient sur « payée » — une pièce éditée reparaissait donc dans
  les impayées, et pèse désormais sur le BFR.
- **APPLIQUER_REGLES.txt était DÉJÀ appliqué** (vague 63) : les quatre règles sont PORTÉES PAR LA
  MODALITÉ (`saisieTexte`, `provenance`, `autreSystematique`) et une passe les étend à tous les
  examens, présents comme futurs. Le **scénario 66** le sonde sur les cinq modalités plutôt que sur
  la seule échographie — aucune liste sans « Autre » et son champ de précision, aucun champ
  numérique strict, aucune rubrique « Annexes », et le prescripteur extérieur sur la demande.
- `_version` **61**. Scénarios **65** et **66**.

**Vague 65 (22/09/2026) — LES MODALES DEVIENNENT DES PAGES, ET UNE SEULE GÉOMÉTRIE LES TIENT.**

- **`K.pageFormulaire(cfg)` — UN gabarit, posé au kit.** Six grandes saisies quittent les modales ;
  écrire six fois la même géométrie, c'est obtenir six géométries — six gouttières, six largeurs de
  colonne, six barres de pied. Le gabarit rend `grid gap-4 lg:grid-cols-3` / `space-y-4 lg:col-span-2`
  / `space-y-4`, la saisie EN CARTES à gauche, l'**Enchaînement du parcours** et les rappels de règle
  à droite. Il **partage la déclaration de champs de `crud`** : la même liste sert la modale
  d'édition et la page de création — deux listes auraient divergé au premier champ ajouté.
  `cfg.creerVers` (qui existait pour la facture) fait naviguer le bouton « Nouveau ».
- **Pages nouvelles** : `m1-patient-nouveau` (l'ouverture d'un dossier se fait au guichet, devant la
  personne), `m4-dossier-obstetrical-nouveau` (douze facteurs de surveillance et un plan
  d'accouchement), `m6-inventaire-feuille` (on y compte deux cents articles, la main sur le rayon).
  La **feuille d'inventaire porte sur un MAGASIN NOMMÉ** : stock théorique, écart et régularisation
  ne concernent que lui — compter les rayons de la pharmacie et régulariser le magasin central était
  le défaut corrigé la veille, et il se rejouerait si la page retombait sur `stock`, le total des deux.
  Le choix du magasin ne propose plus que **gros et détail** : un article ne porte pas de stock
  « labo », et l'offrir ferait compter une quantité qui n'existe sur aucune fiche.
- **La fiche patient passe à DEUX PANNEAUX et un MENU COLLANT.** Treize onglets sur une ligne
  débordent : on faisait défiler horizontalement pour trouver « Traçabilité ». Le panneau gauche
  porte l'identité, la couverture, les allergies, **le dossier de consultation complet** (anamnèse,
  antécédents en trois catégories, données préalables, constantes datées, **examen IPPOA appareil
  par appareil AVEC ses dates**) puis la rubrique choisie ; le menu collant tient à droite.
  **L'ORDRE DU DOM EST CELUI DU TÉLÉPHONE** : la fiche sert aussi le tiroir du répertoire, qui
  n'atteint jamais 1024 px — en une colonne, un menu placé après le contenu se retrouve après treize
  rubriques de tableaux, donc introuvable. Les entrées portent `role="tab"` : une prise stable pour
  les lecteurs d'écran comme pour les sondes. **Deux dates distinguées** sur chaque appareil : celle
  de la VENUE (le jour de l'examen) et celle de l'ENREGISTREMENT — elles diffèrent quand le
  praticien saisit le soir ce qu'il a examiné le matin.
- **Les certificats FUSIONNENT en un seul registre**, à quatre onglets — toutes, patients de la
  clinique, patients externes, **Archives**. `m1-certificats-externes` devient une page-renvoi hors
  ruban : deux registres sur la même collection finissaient toujours par ne pas dire la même chose.
  La délivrance accepte désormais **un patient du répertoire OU un patient adressé de l'extérieur**,
  dont le dossier naît par la **fabrique unique** `PR.dossierExterne` — un second constructeur de
  code patient divergerait, et celui-là avait déjà divergé une fois.
- **UNE PIÈCE CERTIFIANTE PASSE PAR LA CAISSE** (`PR.facturerPiece`, `PR.statutPiece`). Le
  certificat est une prestation tarifée ; il se délivrait sans qu'aucune pièce de caisse ne naisse,
  et le total des « recettes des certificats » comptait des sommes jamais entrées. **L'état de
  règlement n'est pas stocké sur la pièce : il se LIT sur la ligne de facture** — le porter en
  double donnerait deux vérités. **TROIS RÉPONSES, PAS DEUX** : réglé · à encaisser · **en attente**
  pour les pièces délivrées avant que la caisse n'entre dans le circuit — les dire impayées serait
  aussi faux que les dire réglées. La répartition suit la grille (`assurable === 'sos'`) et non le
  taux du dossier : un assuré NSIA règle son certificat intégralement.
- **Chaque rubrique d'un compte rendu d'imagerie a sa CARTE** (« Résultat », « Ovaires et
  cul-de-sac de Douglas », « Conclusion »). Elles se suivaient dans un seul formulaire, séparées par
  de simples titres : sur trente champs, on remplit la taille d'un ovaire dans la ligne du
  cul-de-sac sans s'en apercevoir. Le relevé n'a rien eu à changer — `formulaires` était DÉJÀ une
  liste. Même passage aux cartes pour le **dossier de consultation** : `repliable()` emprunte
  `card` / `card-head` / `card-body` au lieu de porter ses propres bordures, et la carte
  enveloppante de la fiche patient est retirée — un cadre dans un cadre faisait diverger cet écran
  de tous les autres.
- **Le banc d'essai avait une COURSE, pas un défaut d'écran.** Depuis que les saisies naviguent, les
  attentes fixes calibrées sur une modale tombaient tantôt sur un contexte détruit, tantôt sur un
  document dont les scripts n'avaient pas tourné : « Cannot read properties of undefined (reading
  'store') », à un endroit DIFFÉRENT à chaque exécution. `page.evaluate` est désormais gardé — il
  attend un document complet et le socle chargé —, et **chaque échec est nommé sur-le-champ** :
  quand un scénario ultérieur fait tomber le banc, le récapitulatif de fin n'est jamais écrit, et un
  « X » au milieu d'une ligne de points ne dit ni où ni quoi.
- **UNE PAGE DE SAISIE PORTE LES DROITS DU REGISTRE QU'ELLE ALIMENTE** — le défaut le plus grave de
  la conversion, et il ne se voyait que sous un rôle précis. Une page est un ÉCRAN : elle hérite donc
  de son MODULE. Or l'échographiste a **M2 en lecture** et `m2-imagerie` **en écriture par surcharge
  d'écran** : il ne pouvait plus saisir un compte rendu qu'il saisissait la veille dans une modale
  ouverte depuis un écran où il a le droit d'écrire. L'entrée de manifeste déclare donc `servant` —
  l'écran dont elle prolonge le geste — et `can()` comme `app.droits()` résolvent **sur lui**. Fermer
  le registre ferme la page : son adresse serait sinon une porte dérobée. L'alternative aurait été
  d'ajouter six surcharges d'écran à seize fiches de rôle — oubliées au premier rôle créé, et le
  défaut serait revenu sans bruit.
- **LE MESSAGE DE CONFIRMATION SURVIT À LA NAVIGATION** (`U.toastDiffere`, consommé une fois par
  `app.js` au chargement suivant, dans `sessionStorage`). Une page de saisie enregistre puis REVIENT
  au registre : le toast était posé, puis emporté par le rechargement en une fraction de seconde —
  l'agent validait et ne voyait ni le numéro attribué, ni ce qui avait été transmis. **Exception
  assumée : la feuille d'inventaire ne part pas.** Son annulation est une FONCTION — elle restitue
  les stocks et retire les mouvements — et une fonction ne traverse pas une navigation ; afficher un
  message d'où « Annuler » aurait disparu, juste après l'opération qui en a le plus besoin, serait
  pire que rester. La feuille se referme donc sur son résultat, et c'est l'agent qui repart.
- **`&amp;` écrit à la main dans un texte de `K.note` ressortait LITTÉRALEMENT** : `texteEnrichi`
  échappe d'abord tout, puis réactive un sous-ensemble de balises — l'esperluette s'y trouvait donc
  échappée deux fois. Cinq occurrences corrigées (« Rôles & permissions », « Rendez-vous & visites »,
  « Rapports & Impression »). On écrit `&`, pas `&amp;`.

- **Un test qui recopie le manifeste finit toujours par diverger de lui** — payé une fois de plus :
  le nombre de rangées du domaine Financier était figé à 4 et tombait à l'ajout de la rangée
  « Contrôle de gestion ». Il se dérive désormais de `N.tree()`.

**Vague 66 (23/09/2026) — LE MAGASIN QUITTE LE NAVIGATEUR : PAGES EN `.php`, DONNÉES EN
PostgreSQL.** Décision de la Direction après le constat du quota : faire **1 + 2 et pas 3** — servir
les pages en PHP, porter les DONNÉES sur un serveur, et **ne pas réécrire l'interface**. Les ~300
écrans n'ont pas bougé d'une ligne.

**CE QUE L'ON A TROUVÉ AVANT DE COMMENCER, ET QU'IL FAUT SAVOIR** : la base `sigh_cnt` EXISTE déjà —
173 tables, 61 migrations Laravel — et l'application qui la porte aussi : **`sigh_web/`** (Laravel 12
+ Inertia/Vue 3, 288 pages Vue et **70 570 lignes de PHP en seize modules** — mesure rectifiée le
25/09/2026, voir « Architecture cible » ; dernière touche le **06/09/2026**, **sous aucun
contrôle de version**). Le prototype écrit donc dans une base SÉPARÉE, `sigh_prototype`, et jamais
dans `sigh_cnt` : y mêler des collections en JSON polluerait un schéma relationnel que personne n'a
demandé de mélanger, et l'on ne saurait plus, à la reprise, ce qui vient de la maquette et ce qui
vient du produit.

- **L'EXTENSION DES PAGES VIT À UN SEUL ENDROIT** — `N.EXT` dans `nav.js`, et rien d'autre. Le
  manifeste étant la source unique des liens, le passage de `.html` à `.php` s'est fait en changeant
  une constante : `gen-pages.js` l'y lit, `app.js` aussi, et les cinq bancs d'essai la normalisent
  en UN point chacun (`ouvrir()` couvre à lui seul 284 appels). **Le contenu des pages n'a pas
  changé d'une ligne** — ce sont toujours les dix lignes engendrées qui appellent `SIGH.mount()`, et
  l'interface reste construite en JavaScript. Les pages de l'ancienne extension sont RETIRÉES à la
  génération : deux jeux côte à côte, c'est une adresse sur deux qui ouvre une version figée du jour
  du changement, et rien ne le dirait.
- **`var EXT` déclaré APRÈS son premier usage** : le piège du dépôt, payé une quatrième fois. La
  déclaration est hissée, l'affectation non — et la liste `STANDALONE`, évaluée au chargement,
  recevait `undefined`. Toute constante lue par un littéral de haut niveau se déclare AVANT lui.
- **L'API : `api/magasin.php`, `api/session.php`, `api/config.php`.** GET rend le magasin ENTIER,
  dans la forme même que le prototype tient en mémoire ; le navigateur l'assigne et continue de lire
  de façon **synchrone** — c'est exactement ce qui permet aux trois cents écrans de ne pas changer.
  POST applique un **DELTA par collection** : réexpédier 4,8 Mo à chaque geste coûterait plus cher
  que le `localStorage` qu'on remplace. Le magasin compare chaque collection à ce qu'il a déjà
  envoyé et n'expédie que l'écart — mesuré : 101 collections au premier envoi, **2** au geste suivant.
- **CE QUE LE SERVEUR APPORTE, ET QUE LE NAVIGATEUR NE POUVAIT PAS** : pas de plafond ; des données
  qui survivent au navigateur et se sauvegardent (`pg_dump`) ; et surtout **PLUSIEURS POSTES QUI
  VOIENT LE MÊME MAGASIN**. C'est cela, simuler une clinique. Sondé sur deux profils Chrome
  distincts — donc deux `localStorage` séparés : le poste A ouvre un dossier, le poste B le voit
  après rechargement.
- **LA SESSION EST TENUE PAR LE SERVEUR** (`sessions_poste`). Tant que les données vivaient dans le
  même navigateur, une session déclarée par la page n'engageait personne ; dès lors que plusieurs
  postes écrivent dans la même base, ce qu'un poste écrit, les autres le lisent. Le serveur délivre
  donc son propre **jeton** — jamais choisi par le client — et **refuse toute écriture anonyme**
  (RG-12). **Ce qui n'est PAS fait, et qu'il ne faut pas laisser croire** : la matrice des droits par
  module vit encore dans le manifeste JavaScript ; le serveur ne la connaît pas et ne prétend donc
  pas la faire respecter. La porter en PHP est le pas suivant.
- **LE REPLI EST LA RÈGLE, PAS L'EXCEPTION.** Sans serveur — ouverture par double-clic, serveurs Node
  des bancs d'essai — l'hydratation rend `false` aussitôt et le magasin retombe sur le navigateur,
  sans rien casser. **Les bancs d'essai DOIVENT y rester** : chaque exécution part d'un jeu propre et
  reproductible, une base partagée les ferait dépendre les unes des autres.
- **LE PIÈGE QUI A COÛTÉ LE PLUS CHER : `mount()` n'AFFICHE PAS.** Il ENREGISTRE la page ; c'est
  `boot()`, accroché au chargement du document, qui peint. Tant que le montage était synchrone,
  l'ordre tombait juste. Avec l'attente du magasin, la page arrivait APRÈS le départ de `boot` — qui
  trouvait `PAGE` vide et repartait **sans rien afficher et sans rien dire**. On rend donc la main à
  `boot` une fois la page posée, et `boot` ne peint qu'une fois. Leçon générale : une porte qui
  attend doit rendre la main à ce qui suivait, et **un rendu qui échoue doit le DIRE** — une page
  blanche muette fait chercher le défaut dans l'écran pendant des heures.
- **La première écriture partait avant la session.** L'amorçage se faisait pendant l'hydratation, la
  session s'ouvrait après : le serveur refusait, à juste titre. Le magasin ne sème donc plus pendant
  l'hydratation — il attend le premier accès, après la session. Et une écriture refusée **est
  reprogrammée** au lieu d'être perdue : le delta est remis en attente, sans quoi il n'attendrait
  que le prochain geste de l'utilisateur — et s'il n'y en a pas, le travail resterait dans le
  navigateur sans que rien ne le dise.
- **Les identifiants ne sont PAS dans le dépôt** : `api/config.local.php` est ignoré par git, et
  `api/config.local.exemple.php` dit quoi y mettre. L'accès passe par **PDO** : basculer sur MySQL
  ne tient qu'à la ligne du DSN.
- **`npm run serveur`** lance le serveur intégré de PHP sur le prototype (port 8080 par défaut).
  Apache reste possible — une jonction `C:\laragon\www\sigh` vers ce dossier suffit — mais son PHP
  doit charger `pdo_pgsql` : sur ce poste, Apache tourne sur PHP 8.1.10 où les deux extensions
  étaient commentées. Elles sont activées (copie de sauvegarde : `php.ini.avant-sigh`), **effectif
  au prochain redémarrage de Laragon** — non fait ici pour ne pas interrompre les autres sites du
  poste.
- **Trois liens en dur retrouvés au passage** : la page de connexion et le verrou de session
  (`auth.js`) et l’adresse publique d’une fiche d’enquête (`m13-administration.js`) fabriquaient
  leur `.html` eux-mêmes. Le contrôle en a levé deux d’un coup — **303 liens cassés** sur le plan
  du site — et le banc d’essai le troisième : l’écran verrouillé ne savait plus nommer l’écran de
  retour. C’est exactement ce qu’un manifeste source unique doit produire quand on s’en écarte.
- **Le banc d’essai accepte les DEUX extensions** là où il sonde un href : ce qu’il mesure est le
  repli du ruban ou l’absence de lien vers le logiciel, jamais une extension.

**Vague 67 (24/09/2026) — NEINSTRUCTION, NEINSTRUCTION1, NEINSTRUCTION2 : ce qui a été appliqué,
et ce qui ne l'a pas été.** Trois documents reçus : une matrice RBAC « stricte et définitive » pour
15 rôles, la sidebar attendue de chacun, et un module nouveau — l'expression des besoins.

**DEUX ÉCARTS DE VOCABULAIRE À GARDER EN TÊTE AVANT DE LIRE CES DOCUMENTS** : ils parlent de
**15 rôles** quand le projet en porte **16** (l'Assistant Comptable, arbitré le 31/08/2026 — et
NEINSTRUCTION1 en décrit d'ailleurs 16) ; et ils disent **« sidebar »** là où la clinique a demandé
un **ruban** le 16/08/2026. Leurs noms techniques diffèrent aussi des nôtres : leur
`assistant-comptable` est notre `aide_comptable`, leur `admin-agent` est notre
`assistant_comptable`. On ne renomme pas un identifiant technique — c'est la doctrine « laborantin ».

- **LE MODULE D'EXPRESSION DES BESOINS (NEINSTRUCTION2)** — `m7-besoins` devient **QUATRE VUES sur
  une seule collection** : *Mes demandes* (tout agent), *Arbitrage & validation DAF*, *Besoins
  validés — achats & logistique*, *Tous les bons*. Quatre écrans auraient donné quatre vérités sur
  la même pièce : c'est la leçon des visites et des certificats, payée deux fois. Chaque vue est
  gardée par CE QU'ELLE PERMET et non par un module — un onglet visible sans le droit d'agir
  promettrait une porte fermée. Sondé : le médecin et le caissier ne voient que *Mes demandes*, la
  DAF les quatre, le gestionnaire de stock trois.
- **UN ÉCRAN PEUT ÊTRE DÉCLARÉ `universel`** — nouveau mécanisme de manifeste. Exprimer un besoin
  appartient à TOUT agent : le médecin sans papier, la sage-femme sans gants, la réception dont
  l'imprimante est vide. L'écran vit en M7, que la plupart des rôles n'ouvrent pas. **Une
  déclaration, pas seize surcharges** — l'écrire dans chaque fiche aurait tenu jusqu'au premier rôle
  créé en exploitation, qui ne l'aurait pas eue. `universel` **ne rouvre pas** un module désactivé
  (`ecranActif` tranche avant, pour tous les rôles), ne ressuscite pas un rôle archivé, et **cède
  devant une surcharge d'écran explicite** : un administrateur qui ferme nommément garde le dernier
  mot. Il accorde `voir` et `editer` — jamais `annuler` : retirer le bon d'un autre service
  n'appartient pas à celui qui passe par là.
- **L'ARBITRAGE DE LA DAF a trois réponses, et deux EXIGENT leur motif.** Un refus sans motif se
  represente la semaine suivante à l'identique : le service n'a rien appris, la DAF rearbitre la
  même chose. **La validation informe DEUX POSTES par une tâche, pas par un message à écrire à la
  main** — le comptable pour l'engagement, le gestionnaire de stock pour l'achat ou la distribution.
  C'est le geste qui fait naître la notification, comme l'encaissement fait naître l'écriture.
  `rejete` et `complement` sont des **ISSUES, pas des étapes** : les ranger dans la file linéaire
  ferait croire qu'un bon rejeté avance. Et **un bon rejeté n'est pas archivé** — le service doit
  pouvoir en lire le motif.
- **Le formulaire s'adapte à qui l'ouvre** : un agent qui exprime un besoin ne choisit pas son
  « étape du circuit » — lui présenter la file complète l'inviterait à se placer lui-même en
  « validation DA », c'est-à-dire à s'accorder ce qu'il demande. Son bon part **SOUMIS** : laissé en
  brouillon, il attendrait indéfiniment que son auteur pense à l'envoyer.

**CE QUE LA MATRICE A RÉELLEMENT LEVÉ — deux défauts, trouvés en confrontant l'inventaire aux
documents plutôt qu'en les appliquant à l'aveugle :**

- **RAP ÉTAIT OUVERT EN ÉCRITURE ET ANNULATION À TOUS LES RÔLES.** Le module porte `roles: ALL` — et
  c'est juste pour la bibliothèque des états, le CDCT faisant de l'impression une exigence de chaque
  poste. Mais ce sont les listes de CHAQUE écran qui filtrent, et aucune n'était posée : un médecin,
  un caissier, la réception pouvaient **écrire et annuler dans « États de la Direction » et dans le
  générateur de rapports**. Les trois écrans qui PRODUISENT sont fermés ; la bibliothèque qui
  IMPRIME reste ouverte — elle n'a aucune écriture, c'est un catalogue.
- **L'ASSISTANT DE DIRECTION perd le LABORATOIRE — mais garde l'inventaire des réactifs.** M5 en
  lecture lui donnait les demandes d'analyses et les RÉSULTATS, données de santé que RG-13 réserve
  au soignant habilité ; NEINSTRUCTION en fait une « restriction absolue ». Le module est fermé.
  **Mais le banc d'essai a rappelé ce que la fermeture en bloc emportait** : sa description de poste
  porte « l'inventaire des médicaments d'urgence et des réactifs », et c'est écrit au motif de sa
  propre fiche. L'écran `m5-reactifs` lui est donc ACCORDÉ NOMMÉMENT — une surcharge accorde autant
  qu'elle restreint, et un stock de réactifs n'est pas un résultat d'analyse. **M12 reste à TOUT** :
  NEINSTRUCTION1 ne donne aucun Financier à son « assistant de direction », mais le poste qu'il
  décrit est un secrétariat quand le nôtre est bâti sur une description explicitement comptable —
  on ne retire pas une attribution documentée sur la foi d'une homonymie. `_version` **62** : les
  fiches RBAC étant SEMÉES, sans incrément un poste garderait l'ancienne.
- **LES DRAPEAUX D'UN ÉCRAN VIENNENT DE L'INDEX, PLUS DE L'APPELANT.** Cinq endroits fabriquent une
  entrée SYNTHÉTIQUE pour interroger `can()` — ruban, cartes de hub, accès rapides, recherche,
  matrice — et chacun recopie ce qu'il croit utile : le module a été oublié une fois, l'identifiant
  une deuxième, `universel` cette fois-ci — ce qui a fait disparaître l'écran des besoins du ruban
  du biologiste. **Le défaut est revenu TROIS fois** : dès que l'appelant nomme l'écran, `can()`
  relit désormais ses propriétés à la source, et un drapeau ajouté demain sera pris en compte par
  les cinq appelants sans qu'aucun soit retouché. Au passage, la RECHERCHE GLOBALE ne passait pas
  l'identifiant — une activité fermée y restait donc proposée.

**CE QUI N'A PAS ÉTÉ APPLIQUÉ — ET QUE LA DIRECTION A VALIDÉ EN L'ÉTAT LE 25/09/2026.** Les cinq
points ci-dessous avaient été écartés faute de pouvoir renverser seul une décision antérieure ; la
Direction a confirmé que leur traitement actuel est le bon. **Ce ne sont donc plus des questions
ouvertes : ce sont des arbitrages**, et les rouvrir demanderait une décision explicite. Le tableau
est conservé parce qu'il dit POURQUOI — sans lui, la prochaine lecture de NEINSTRUCTION ferait
reprendre le même débat depuis le début.

| Ce que le document demande | Ce qui est en place et VALIDÉ | Le motif de l’arbitrage |
|---|---|---|
| Comptable : **RH interdit** | M11 Paie en écriture | Décision documentée du 02/09/2026 (fiche RBAC du comptable). La renverser retirerait la saisie de paie au seul poste qui la tient. |
| Réception : **Système interdit** | `cfg-tarifs` en lecture | Arbitrage explicite de la Direction du 31/08/2026 — « `cfg-tarifs` en lecture pour la réception par surcharge d'écran ». |
| Caissier, comptable, ambulancier, agent administratif : **Soins interdit** | Répertoire patients en LECTURE | Différence de TAXONOMIE, pas de droit : leur sidebar range le répertoire sous *Accueil*, notre ruban sous *Soins*. Le document lui-même accorde « Accueil (consultation du répertoire patient) ». |
| Aide-soignante, ambulancier, caissier : **Pilotage interdit** | Leur PROPRE tableau de bord | Fermer DASH retirerait au rôle sa page d'accueil. La doctrine est écrite depuis la vague 37. |
| Stock, assistant comptable, assistant de direction : **Accueil (consultation)** | Domaine absent | Mention trop vague pour ouvrir neuf écrans d'agenda et de file d'attente à trois postes qui n'y ont rien à faire. À préciser : quels écrans ? |

Autres demandes de la vague, appliquées : la pastille du ruban **« Répertoire des ambulances »** (un
alias qui se nomme autrement fait croire à deux écrans) ; la rangée **« Gestion & trésorerie »**
déplacée du Financier au **Pilotage** — elle reste `secondaire` de M12, donc **les droits ne bougent
pas d'un pouce** ; et le **mot de passe à la création d'un compte** (`m14-utilisateurs`).

- **LE MOT DE PASSE EST SAISI, IL N'EST PAS GARDÉ.** Ce qui entre au magasin, c'est la DATE de
  définition, son auteur, et l'obligation de changer à la première connexion — jamais le secret.
  Écrire un mot de passe en clair dans un magasin que l'on exporte, que l'on sauvegarde et que l'on
  relit à l'écran serait pire que pas de mot de passe du tout. Il **n'apparaît pas à la
  modification** : changer le mot de passe de quelqu'un n'est pas « corriger une fiche », c'est un
  geste distinct qui doit se voir au journal.
- **L'EN-TÊTE DU COMPTE RENDU D'IMAGERIE REVIENT EN MODALE**, et c'est sa validation qui ouvre la
  page. Les deux gestes n'ont pas la même durée : désigner l'examen, le patient et le réalisateur
  prend quinze secondes et se fait debout ; rédiger prend dix minutes et demande toute la largeur de
  l'écran. **L'en-tête ne crée rien** — il est déposé pour le chargement suivant (le mécanisme du
  message différé) et la fiche ne naît qu'à l'ENREGISTREMENT : la créer à la validation de la modale
  laisserait un brouillon vide au registre chaque fois qu'on ouvre une saisie puis qu'on se ravise.
  Déposé dans `sessionStorage` et non dans l'adresse : l'en-tête porte huit champs, dont un nom de
  prescripteur extérieur en toutes lettres, qu'une adresse afficherait dans l'historique du
  navigateur. Les **cinq modalités** passent par la même fabrique.

**Vague 68 (20/10/2026) — L'HORLOGE RÉELLE, LA CONNEXION ÉPURÉE, LE VIDAGE QUI TIENT — et trois
PRD pour la suite.** Trois défauts signalés par la Direction le même jour, un fil commun : ce que
l'écran montre doit être ce que le magasin porte.

- **« AUJOURD'HUI » VALAIT LE 16 AOÛT DANS DIX-NEUF MODULES.** Chaque module portait
  `var AUJ = new Date(2026, 7, 16)` — la date du jeu de démonstration, figée pour que les tableaux de
  bord aient quelque chose à montrer. Le formulaire de rendez-vous, lui, partait de l'horloge réelle :
  un rendez-vous pris le 20 octobre tombait hors de la fenêtre de l'agenda (du 14 au 20 août) et ne se
  retrouvait nulle part — « enregistré, mais introuvable ». **La date du jour vit désormais en UN
  endroit, `C.aujourdhui()`, et c'est l'horloge réelle** ; le jeu de démonstration reste daté
  (`data-seed.js`, `store.js` : c'est un fait sur le jeu, pas sur l'horloge). Conséquence
  assumée : sur le jeu, les indicateurs « aujourd'hui » des tableaux de bord sont vides tant que
  le jeu n'est pas ré-ancré — c'est le comportement JUSTE d'un logiciel qui lit l'heure.
  **C'est le BANC qui décale l'horloge sur la date du jeu** (`HORLOGE_BANC` dans `build/_banc.js`,
  posée par `poserSession` dans les quatre bancs) : le temps continue de s'écouler — identifiants,
  minuteries, journal — seul le point de départ change, et un scénario peut la déplacer
  (`window.__SIGH_HORLOGE.decaler`). Les 1 091 vérifications écrites « au 16 août » restent
  vraies sans en réécrire une. Au passage : `C.isoLocal()` pour les champs `datetime-local` —
  `toISOString()` rend l'heure UTC, le Bénin est à UTC+1, l'heure proposée était fausse d'une heure.
  Et **l'agenda étend sa fenêtre jusqu'au rendez-vous qu'on vient de prendre** : pris hors de la
  fenêtre affichée, il disparaissait à l'enregistrement.
- **LA PAGE DE CONNEXION NE LISTE PLUS LES COMPTES.** Le sélecteur « Profil de connexion
  (démonstration) », le mot de passe pré-rempli et le pied (« comptes ouverts par
  l'administrateur », double facteur, plan du site) sont retirés : l'agent saisit SES identifiants,
  le serveur vérifie le haché. Le scénario 40 mesurait le renommage des rôles sur le TEXTE de cette
  page ; il le mesure désormais là où il vit — le manifeste `N.ROLES` et l'annuaire
  `api/auth.php?action=comptes`.
- **« RÉINITIALISER » RÉGÉNÉRAIT LE JEU AU LIEU DE LE RETIRER** — on cliquait, tout revenait à
  l'identique : « ça n'a pas marché ». Et le vidage des jeux de test, derrière sa bascule, avait
  DEUX défauts de fond. (1) **La liste de ce qui est conservé était incomplète** : la matrice RBAC,
  les modules actifs, les catalogues du laboratoire et de l'imagerie, le barème et la grille des
  primes n'y figuraient pas — vider rouvrait la banque de sang, rendait TOUS les droits à TOUS les
  rôles (un rôle sans fiche a tout, vague 36) et privait le laboratoire de ses examens. (2) **Le
  vidage ne tenait pas** : une quinzaine d'écrans ré-amorcent leur collection dès qu'ils la trouvent
  vide (contrats, congés, budgets, avances, poches, achats…) — ouvrir l'écran suffisait à faire
  renaître le jeu, écran par écran. **Les deux vivent désormais AU SOCLE** :
  `S.COLLECTIONS_ESSENTIELLES` (paramétrage, référentiels, comptes, droits, modules, catalogues,
  règles datées, modèles), `S.viderActivite(motif)` — la MÊME fabrique sert le bouton de
  maintenance et l'onglet « Jeux de test » — et le drapeau de méta `_jeuVide`, lu par
  `S.amorcable(nom)` : `K.amorcer`, `semerAchats` et les treize sites `if (!col.all().length)`
  le consultent ; un référentiel DÉRIVÉ d'un document (le calendrier fiscal) reste libre de se
  reconstruire. `S.reset()` abaisse le drapeau — et l'ENVOIE (une clé de méta absente du nouveau
  magasin ne partirait pas, et la base garderait l'ancien). Le rechargement **attend que le serveur
  ait reçu** le vidage (`recharger()`) : lancé pendant l'envoi, il relisait la base d'avant.
  Un vidage est journalisé, et c'est la première entrée du journal neuf (RG-12).
- **Trois PRD** (`docs/prd/`) pour ce que la Direction a demandé le même jour et qui ne se
  corrige pas en une vague : la **clôture d'exercice** (résultat, à-nouveaux au solde et ligne à
  ligne, sélecteur d'exercice, exercices clos en lecture seule AU MOTEUR, exercices ouverts
  simultanés avec à-nouveaux provisoires, N / N-1, archive), le **suivi des ventes par patient et
  par secteur** (le Point global détaille ce qui a été vendu à chaque patient sélectionné, secteur
  par secteur ; **« Imagerie médicale » remplace « Échographie » comme secteur de recette** —
  l'IRM, le scanner et la mammographie se comptaient sous « Échographie » ; identifiants techniques
  inchangés), et **l'application sans rechargement** (routeur en document unique, modules
  paresseux, hydratation unique puis deltas, flux d'événements entre postes, notifications qui
  CONSOMMENT, planificateur de tâches serveur) — la condition de la phase P2 de l'architecture cible.
- **LE BANC MENTAIT PAR OMISSION, ET LE RELAIS HTTP ÉTAIT EN CAUSE.** Le premier passage complet a rendu
  seize échecs épars — « bouton absent », « 16/17 tableaux de bord », « 0/0 demandes » — avec 0 erreur
  JS. Reproduit sur l'arbre d'AVANT la vague : le défaut était préexistant. Le relais Node des bancs
  (`relayer` dans `build/_banc.js`) recopiait les en-têtes du serveur intégré de PHP — « Connection:
  close », sans Content-Length — et recodait le corps de 5 Mo en morceaux ; environ une fois sur
  quarante, le navigateur ne voyait jamais la fin du corps, l'hydratation restait PENDANTE, la page
  restait BLANCHE, et `attendrePeinture` rendait la main en silence après 150 s : chaque assertion
  suivante mesurait une page vide. La réponse est désormais mise en TAMPON et renvoyée avec sa
  longueur, et `ouvrir()` DIT quand une page ne s'est pas peinte. Doctrine confirmée une fois de plus :
  un rendu qui échoue doit le dire — et un banc qui attend doit dire ce qu'il attendait. Diagnostic
  établi par un agent de reproduction isolé (cinq rejeux sur base neuve, ports et base distincts).
- Scénario **67** (dernier : il VIDE le magasin et le régénère en sortant). État : bancs en cours de relance au 20/10/2026 — chiffres définitifs au commit suivant.

**Repli du ruban sur accès rapide (vague 16)** — un lien du panneau du ruban posait le drapeau
transitoire, les boutons du bandeau non : la page appelée s’ouvrait menu déployé alors que l’utilisateur
venait de choisir sa destination. Le conteneur porte désormais l’identifiant `#page-actions` et un
écouteur de clic délégué.

**Régimes de travail et portée des modifications (vague 17)** — les régimes ont quitté le code pour la
collection `regimesTravail` (amorcée dans `store.seed()` : deux écrans les lisent). Modifier un régime
**demande sa portée** — vacations à venir seulement, ou historique compris — parce que les vacations
passées ont donné lieu à des primes calculées, parfois payées. Chaque vacation porte `regimeLibelle`,
le régime sous lequel elle a été posée : sans cette trace, l’historique deviendrait illisible.
Le régime **Incinération des déchets** y a été ajouté avec son honoraire (5 000 F, NS 132).
`m10-stats-gardes` compte les gardes par agent sur six périodicités — **repos et congés exclus**, faute
de quoi les agents les plus reposés apparaîtraient comme les plus chargés.

**Grille des primes datée (vague 19)** — `D.NS132.montant(primeId, fonction, **date**)` lit la collection
`grillePrimes` et, pour une date antérieure, remonte `historiquePrimes`. C’est ce troisième argument qui
distingue le moteur d’une simple table : une prime relevée le 20 août ne doit pas changer la prime de
juillet, déjà calculée et souvent payée. La modification demande là aussi sa portée, et le calcul de paie
passe la date du bulletin. Ne pas retirer les versions antérieures : c’est en elles qu’un bulletin ancien
retrouve son montant.

**Assurance du personnel (vague 20)** — la clinique soigne ses agents à 100 %. Ce n’est **pas** une
assurance au sens de M9 : aucun tiers ne rembourse, aucune créance ne naît, et la prestation ne remonte
**ni aux recettes ni à la comptabilité**. Le lien se fait par `personnelId` sur le dossier patient — il ne
se devine pas d’un nom. L’écran `m10-assurance-personnel` **n’ouvre aucune saisie** : il se remplit depuis
les consultations, analyses et hospitalisations de l’agent. Y ouvrir un CRUD créerait une seconde vérité,
divergente du dossier.

**Frais de participation aux événements (vague 21)** — un événement touchant un agent (mariage, naissance,
décès) engendre **une participation par agent, hors bénéficiaire** : c’est ce geste unique qui fait tenir
le module. Deux modes de règlement, deux conséquences : **imputation sur salaire** → la retenue figure au
bulletin du **seul mois de retenue** (la porter chaque mois la prélèverait douze fois) ; **paiement au
comptant** → versement encaissé avec reçu. Ces sommes **transitent** : ni recette ni charge. Modifier un
événement ne touche que les participations **non réglées** — ce qui a été encaissé l’a été au montant
annoncé sur le reçu.

**Verrouillage de session (vague 22)** — quinze minutes d’inactivité verrouillent l’écran (CDCT §12.2).
La session est **suspendue, pas fermée**, et `auth-lock` ramène l’utilisateur **à l’écran qu’il avait, à
l’onglet près** : un verrouillage qui fait perdre la saisie en cours est désactivé dès la première semaine.
L’adresse de retour (`sigh-cnt:verrou-retour`) est à usage unique.

**Laboratoire — le modèle de résultat (vague 23).** `assets/js/data-labo.js` est fondé sur DEUX pièces
réelles, qui ne disent pas la même chose : le **bulletin d’analyses bio-médicales** (formulaire papier)
donne le catalogue et son classement en six sections ; la **fiche de résultats du dossier 2026080411**,
éditée le 21/08/2026, donne les variables, les unités et les valeurs de référence.

Un résultat n’est pas un champ de texte : c’est un jeu de **variables**, parfois de **sous-variables**,
chacune avec son type, son unité et ses bornes. Ce que la fiche réelle a corrigé, et qu’il ne faut pas
réintroduire :

- la **formule leucocytaire est en valeurs absolues (G/l)**, pas en pourcentages ;
- les bornes du laboratoire ne sont **pas** celles des manuels — hémoglobine 11–14 g/dl sans distinction
  de sexe, GB 4–8 G/l, GR 3,5–5,3 T/l ;
- la CCMH s’exprime en **g/dl**, pas en pourcentage ;
- le **VIH porte trois tests**, chacun avec le **nom, le lot et l’expiration** de son réactif, puis une
  conclusion ;
- la **CRP porte deux variables** : une issue qualitative et un taux sérique ;
- l’**ASLO est qualitative**, pas dosée en UI/l ;
- **TBG = test biologique de grossesse**, pas une hormone thyroïdienne — la TSH figure séparément.

Les symboles d’unité sont ceux du document (« G/l », « T/l », « g/dl »), pas les notations normalisées :
le laboratoire lit ce qu’il écrit, et lui imposer une autre notation l’obligerait à traduire.

Deux distinctions à ne jamais confondre :

- le **commentaire d’examen** (interprétation d’un résultat — Widal, VIH) et le **commentaire général**
  du compte rendu (« échantillon hémolysé, reprendre le prélèvement ») ;
- une variable de résultat et une variable d’**accompagnement** (réactif, lot, expiration, commentaire).
  Ces dernières sont **rétractables** : `actif: false` les retire des comptes rendus à venir sans toucher
  aux résultats déjà rendus. C’est la demande textuelle du biologiste — « on peut les fermer ».

`aValider` distingue le documenté du supplé. Les bornes lues sur la fiche valent `false` ; celles qu’il a
fallu suppléer pour les examens absents de la fiche valent `true`, et les écrans le disent. **Ne pas
retirer ce marquage avant validation écrite du biologiste** : les valeurs de référence dépendent du
réactif et de l’automate.

Une divergence entre les deux pièces est **conservée, non arbitrée** : le sérodiagnostic de Widal est
classé en parasitologie sur le bulletin et en sérologie sur la fiche. `sectionResultat` porte la seconde ;
trancher appartient au biologiste.

**Circuit du prélèvement (vague 25)** — le maillon que le prototype sautait. Le circuit décrit par le
biologiste : consultation → le médecin coche les examens → le patient sort avec son **bon d’analyse** →
il paie à la **caisse** → **salle de prélèvement** → prélèvement fait, **le patient peut partir** → la
salle achemine l’échantillon au laboratoire avec le bon → résultats saisis, imprimés, transmis au
clinicien prescripteur, ou **directement au patient s’il est externe**. `m5-prelevement` tient les trois
états : à prélever, à transmettre, reçu. Le laboratoire ne saisit un résultat que sur un échantillon
**reçu** — sans quoi un résultat pourrait être rendu pour un prélèvement jamais fait.

**Activité des modules (vague 24)** — `cfg-modules` ouvre et ferme les activités que la clinique
n’exerce pas. **La banque de sang et la transfusion sont fermées** : la clinique ne les pratique pas.
Une activité fermée sort du méga-menu, de la recherche **et de ses propres adresses**, **pour tous les
rôles, administrateur compris** — ce n’est pas une habilitation. Rien n’est supprimé : la réouverture
rend les écrans en l’état. La fermeture porte sur des **écrans** autant que sur des modules : fermer la
banque de sang ne doit pas fermer le laboratoire.

**Réactifs et consommables** — le **seuil d’alerte est fixé par la clinique**, référence par référence :
le document SAGE ne renseigne pas cette colonne, et un seuil unique n’aurait aucun sens entre un réactif
à péremption courte et un consommable de fond de rayon. Les références sans seuil sont comptées et
signalées : sans seuil, aucune alerte n’est possible.

**Un piège de littéral objet** : deux clés `actions` dans le même `U.dataTable({...})` — la seconde
écrase la première en silence, et le bouton disparaît sans le moindre message. Fusionner les tableaux
d’actions plutôt que d’ajouter une seconde clé.

**Pathologie ≠ diagnostic (vague 29).** La **pathologie** est un code que la clinique compte ; le
**diagnostic** est la phrase que le médecin rédige. Les deux coexistent sur la fiche de consultation, et
c’est délibéré : n’avoir que le second rend toute statistique de morbidité impossible — « paludisme
simple », « accès palustre » et « palu » ne se regroupent pas d’eux-mêmes. `D.PATHOLOGIES` propose 54
entrées sur 12 chapitres, **toutes marquées `aValider`** : la liste est administrable depuis
`m2-pathologies`, et c’est le tableau de morbidité de la clinique qui doit la faire évoluer. Le
classement suit les grands chapitres de la CIM-10 **sans en reprendre la codification** — la clinique ne
code pas en CIM, et lui imposer une nomenclature qu’elle n’emploie pas ferait saisir n’importe quoi.
Les pathologies **notifiables** sont signalées : le logiciel les repère, il ne les déclare pas.

**Les trois postes informés à l’encaissement (vague 28).** `PR.encaisser()` ne se contente plus de
débloquer les tâches d’aval :

- **le comptable** l’est par une **écriture**, pas par un message — 571 Caisse au débit, 411 Clients
  assurance au débit pour la part de l’assureur, 706 Prestations au crédit. Elle est contrôlée
  **équilibrée avant écriture** (RG-10) et naît en **brouillon** : la validation comptable reste un
  geste humain. Sans elle, la recette se ressaisit à la main — exactement ce que la clinique fait
  aujourd’hui entre PERFECTO et la caisse ;
- **le laboratoire** passe en `attente_prelevement`, et pas seulement « débloqué » : lever le blocage
  sans changer l’état laisserait la demande indistinguable des impayées, alors que c’est précisément ce
  que la salle de prélèvement doit voir pour appeler le patient ;
- **le stock** l’est à la délivrance, par `PR.alerterStock()` : une sortie qui fait passer un article
  sous son seuil ouvre une tâche de réapprovisionnement **au moment où elle a lieu**, pas le jour de
  l’inventaire. Une seule tâche ouverte par article — réalerter à chaque sortie noierait le
  gestionnaire sous les doublons.

**La facture porte des LIGNES PAYABLES.** C'est le correctif structurant du lot : `prescrire()` et
`ouvrirDemandeExterne()` construisent une ligne par prestation, et chaque ligne connaît ce qu'elle
couvre (`demandeId`, `produitId`, `acteCode`). Sans ce lien, régler « trois examens sur cinq » ne
pouvait pas désigner LESQUELS trois passent au laboratoire — d'où cinq symptômes distincts qui n'étaient
qu'un seul défaut : reçu sans détail, partiel qui ne libère rien, reste dû anonyme, patient externe
inencaissable.

`PR.encaisser(factureId, opts)` accepte deux formes. `opts.lignes` est la forme juste : la caisse
encaisse des prestations nommées. `opts.montant` reste acceptée et **alloue** la somme aux lignes dues,
dans l'ordre de la pièce, **une ligne n'étant réglée que si elle l'est entièrement** — un demi-examen ne
se prélève pas. Les deux formes produisent le même résultat : des lignes réglées, et un déblocage qui ne
porte que sur elles. L'écriture comptable est posée **à chaque versement**, partiel compris : attendre le
solde laisserait la caisse et la comptabilité divergentes entre-temps.

**Pas de signature patient sur une pièce de caisse** : un encaissement est attesté par celui qui
encaisse, pas par celui qui paie.

**Le patient externe : la demande naît à l'ACCUEIL** (`m1-externe`). Trois raisons, et la troisième est
une règle de contrôle interne : le patient arrive avec une ordonnance extérieure, il s'agit de
**transcrire** et non de prescrire ; son premier point de chute est l'accueil ; et **la caisse ne crée
jamais la demande** — lui donner ce pouvoir ouvrirait une recette sans acte à l'origine. Le manifeste le
tient : `m1-externe` est ouvert à `reception`, fermé à `caissier`. Contrepartie non négociable :
l'accueil **coche les examens au catalogue**, jamais un montant libre, sans quoi la facture n'a pas de
lignes. Le laboratoire garde sa saisie manuelle ; les deux voies se distinguent par `origineDemande`.

**Quatre pièges corrigés au poste 1 :**

- **Les fiches sortaient vides** parce qu'elles imprimaient depuis le formulaire *et* lisaient les mauvais
  champs — `v.prescription` au lieu de `v.medicaments`, et `x.designation === v.analyses` alors que
  `v.analyses` est un tableau depuis le passage au multiselect. Les deux pièces s'impriment désormais
  depuis l'**ordonnance enregistrée** : le papier doit dire ce qui est parti, pas ce qui est saisi.
- **Modale et tiroir s'ouvraient ensemble.** Un clic *programmatique* n'ouvre que la modale — voilà
  pourquoi les scénarios ne l'avaient jamais vu. À la souris, la cible est le `<svg>` de l'icône et la
  remontée par `closest()` ne rattrape pas le bouton. La cellule d'actions **arrête la propagation** :
  une ligne dans `ui.js`, tous les tableaux corrigés.
- **`stock <= null` est faux.** Depuis que le seuil peut être vide, le bon de réactifs sortait sans une
  ligne et sans un mot. Un seuil non fixé n'est pas un seuil de zéro : l'article est signalé à part.
- **Le méga-menu restait ouvert** sur tout lien autre qu'un accès rapide. La délégation remonte au
  conteneur : fil d'Ariane, cartes de tableau de bord, liens de tableau. Ancres, liens externes et
  téléchargements exclus.

**Un piège de littéral objet** : deux clés `actions` dans le même `U.dataTable({...})` — la seconde
écrase la première en silence, et le bouton disparaît sans message. Fusionner, jamais ajouter une
seconde clé.

**Aucune action « Dupliquer »** : un doublon que rien ne distingue de l'original est un doublon que
quelqu'un modifiera par erreur. Retirée du kit, donc de tous les écrans.

**Les DEUX VERROUS du laboratoire (poste 3).** La **validation technique** atteste la saisie ; la
**validation biologique** rend le résultat opposable. Entre les deux, le résultat existe mais le
prescripteur ne le voit pas — c’est la fenêtre pendant laquelle le laboratoire relit, et elle n’a de sens
que si personne ne lit par-dessus son épaule. Le verrou est posé **dans `peutVoirResultat()`, avant toute
question d’habilitation** : un médecin habilité à tout ne voit pas un résultat non validé.

Deux arbitrages rendus :

- **qui détient la validation biologique** : le biologiste médical. Le TSL le peut **en son absence**, et
  l’intérim est **porté sur le compte rendu** — une clinique de trente agents ne peut pas suspendre ses
  rendus pendant un congé, et masquer l’intérim reviendrait à faire signer quelqu’un d’autre ;
- **une correction après validation biologique est une RECTIFICATION** : la version lue par le médecin
  est conservée, la nouvelle est numérotée, et le prescripteur est **notifié que ce qu’il a lu a changé**.
  Écraser en silence le laisserait avec une valeur qui n’existe plus nulle part. Le motif est obligatoire
  et voyage avec la notification.

`D.ETATS_RESULTAT` porte les huit états et `D.resultatRendu(etat)` dit si le résultat est opposable.
Les **notifications de poste** (`PR.notifier`, collection `notifications`) s’adressent à un POSTE et non à
une personne : le prescripteur peut être en congé, c’est le service qui doit voir passer l’information.

**Le filtre de date est un FILTRE, pas un tri** — plage du/au, avec raccourcis « aujourd’hui » et
« sept derniers jours ». Un tri décroissant ne répond pas à « montrez-moi les demandes du 21 août ».

**La matrice descend au niveau de l’ÉCRAN (poste 4).** Elle raisonnait par module — « M1 ouvert » ou
« M1 fermé ». La Direction demandait plus fin : le laborantin consulte le répertoire des patients mais
n’accède ni au dossier médical, ni aux antécédents, ni aux documents, ni au plan de numérisation. D’où
`droitsEcrans` sur la fiche de rôle, et `N.droitsEcran(role, ecranId, code)`.

**Un écran l’emporte sur son module.** Sans cette priorité, ouvrir M1 en lecture rouvrirait les quatre
écrans qu’on vient d’en fermer. Un écran **non réglé suit son module** : il ne faut pas déclarer cent
quatre-vingts écrans pour en fermer quatre.

**LA SURCHARGE ACCORDE AUTANT QU’ELLE RESTREINT.** C’est le défaut de conception que la création de rôle
a révélé : `can()` vérifiait d’abord la liste `roles` du manifeste, si bien qu’une surcharge ne pouvait
que **fermer** ce que le manifeste ouvrait. Un rôle inventé, absent de toutes les listes, restait
inutilisable quoi qu’on lui ouvre. Désormais une surcharge qui pose explicitement `voir: true` **accorde**
— c’est le sens même d’une matrice administrable. Sans surcharge, le manifeste fait foi et rien ne change
pour les quinze rôles d’origine.

**Un rôle créé part de zéro, explicitement.** Les modules M1 et RAP portent `roles: '*'` au manifeste :
« tous les rôles » a été écrit pour ceux qui existaient, pas pour ceux qu’on inventera. La création écrit
donc une surcharge qui **ferme chaque module nommément** — sondé : 0 écran à la création, visible dès
qu’on lui en ouvre un.

**Une seule fiche RBAC par rôle.** Deux fiches rendaient la matrice imprévisible : selon l’ordre de
lecture, c’est l’une ou l’autre qui l’emportait, et le renommage disparaissait. `surcharges()` **fusionne**
désormais champ par champ (la dernière l’emporte sur ce qu’elle définit seulement), et l’écran écrit en
**upsert**.

**Les actions rapides sont filtrées par les droits** : proposer un raccourci vers un écran interdit promet
une porte fermée. « Assurés & cartes » et « Patient externe » y figurent.

**Le barème NS 131 est modifiable, mais derrière une porte (poste 5).** Condition posée par la Direction :
le CRUD ne s’ouvre que depuis « Paramètres système », onglet *Barème NS 131*. Un barème de sanctions ne se
retouche pas au détour d’un écran d’évaluation. **Porte fermée, la modification est ABSENTE et non
grisée** — un bouton grisé invite à chercher pourquoi, un bouton absent dit que ce n’est pas ici que cela
se règle. La **portée rétroactive réutilise le mécanisme du NS 132** au lieu d’en inventer un second : deux
mécanismes auraient divergé au premier correctif.

**Une bascule d’exploitation appartient au SOCLE, pas à un module.** `baremeModifiable()` avait été posée
dans `configuration.js` — chargé sur les seules pages de configuration — et l’écran des évaluations, qui
la consulte, ne la voyait pas. C’est le piège documenté du prototype : chaque page ne charge que le module
de son écran. Les bascules vivent donc dans `store.js`.

**Une perte se déclare, mais s’enregistre comme un MOUVEMENT.** L’écran des pertes était en lecture seule
au motif juste qu’une perte est un mouvement de stock — mais ce motif n’oblige pas à faire sortir
l’utilisateur de l’écran où il constate la casse. La déclaration écrit donc un mouvement, RG-03 est
préservé, et la perte apparaît aux deux endroits **parce qu’elle n’existe qu’une fois**. Une perte
supérieure au stock est refusée en nommant l’article : RG-03 interdit le stock négatif.

**Les emplacements sont un référentiel, plus un texte libre.** Deux agents écrivaient « Rayon A2 » et
« rayon a-2 », et le plan des rayons affichait deux casiers là où il n’y en a qu’un. Le référentiel est
amorcé **depuis ce que les produits portent déjà** : il régularise l’existant au lieu de partir de zéro.

**Une participation vise TOUT le personnel par défaut.** Le champ « Agent concerné » désignait le
bénéficiaire — celui qui ne cotise pas. Ce qui manquait était le choix de **qui cotise** : tout le
personnel, ou une sélection pour les événements de service. Le bénéficiaire reste exclu dans les deux cas.

**Le piège de la double clé `actions`, rencontré deux fois.** Deux clés `actions` dans le même
`U.dataTable({...})` : la seconde écrase la première **en silence**, et le bouton disparaît sans message.
Vu sur `m5-reactifs` puis sur `m6-pertes`. Fusionner les tableaux d’actions, jamais ajouter une seconde clé.

**LA GRILLE PORTE DEUX PRIX (vague 26).** C’est le fait qui commande tout le reste, découvert en lisant
les six grilles tarifaires de `newinfos/` : chacune porte **PRIX NON ASSURÉ** et **PRIX ASSURÉ**, et
l’assuré est presque toujours facturé plus cher. Ce n’est pas une coquille, c’est le modèle économique —
le tarif conventionné opposable à une compagnie n’est pas le tarif de guichet. Un `prix` unique faussait
simultanément la facture du patient, la créance de l’assureur et la recette comptable. `data-tarifs.js`
porte les 130 lignes documentées ; c’est **RG-09**, la validité de la carte **à la date**, qui décide
lequel s’applique — et non le fait de posséder une carte.

**Trois états, pas deux, dans la colonne assurée** : un montant · **NON COUVERT** (l’acte est tarifé mais
aucune compagnie ne le prend en charge — l’assuré paie le tarif non assuré, motif à l’appui ; ce sont
sans exception les actes de **planification familiale** et l’hydrotubation) · un **tiret**, qui n’est ni
un zéro ni une exclusion mais une **valeur manquante** — trois actes, dont le **VIH**, restent `null` et
bloquent la facturation. Traiter le tiret comme un zéro rendrait le dépistage VIH gratuit ; le traiter
comme « non couvert » affirmerait une exclusion que le document ne dit pas. Les deux sont des fautes.

**Les certificats ne sont couverts que par SOS**, mention manuscrite portée sur la grille. D’où
`assurable` à **trois valeurs** (`true` / `false` / `'sos'`) : un booléen aurait forcé à choisir entre
exclure SOS à tort et ouvrir la couverture aux treize compagnies à tort.

**L’anomalie « tarifs des analyses vierges » est levée** — les 41 analyses sont tarifées. Celle des
**médicaments subsiste** : le document qui s’en réclame ne porte que 144 désignations, sans colonne de
prix, ce qui est cohérent avec RG-02 (prix d’achat sans marge : le prix est **calculé**, pas saisi).

**L'IDENTITÉ IMPRIMÉE EST UNIQUE DEPUIS L'ARBITRAGE DU 31/08/2026.** Les 37 pièces réelles portaient
trois IFU, trois RCCM et deux autorisations selon la famille de document ; la Direction a tranché
(Bugs 7/8/13 des Instructions) : le référentiel `enteteVariantes` est retiré, `cfg-entetes` présente
l'unique en-tête légal, et toutes les pièces l'impriment. Les divergences anciennes restent
documentées par les scans de `docs/` — un document ancien qui diverge n'est pas un faux, il est
antérieur à l'unification.

**Quatorze pièces certifiantes**, numérotées `<SIGLE> n°/n°/CNT/<direction>/<année>`, la série repartant
à 1 chaque année comme le registre papier. **Deux collisions de sigles existent dans les sources** —
`CMA` pour l’accouchement ET l’aptitude, `CMD` pour le décès ET le genre de mort. Elles sont
**conservées et signalées** : renuméroter romprait la correspondance avec les registres papier tenus
depuis des années. Le **certificat prénuptial ne se saisit pas** : il se remplit depuis les six examens
**validés biologiquement** du patient — sans quoi le médecin attesterait d’un résultat non rendu.

**DEUX PRESCRIPTIONS, QUATRE ORIGINES (vague 27).** La clinique distingue la prescription
d’**ordonnance** (des médicaments, qui sortent du stock) et la prescription de **soins** (des actes, qui
ne sortent pas du stock, sont **adressés à un secteur** et exécutés par quelqu’un, sous son nom). Les
confondre rendait invisible tout le travail infirmier. Quatre origines : **consultation,
hospitalisation, bloc, maternité** — le prototype n’en connaissait qu’une.

**LA RÈGLE DE RELAIS** est la pièce la plus fine du circuit, et elle vit dans `D.secteurAdministrateur`,
pas dans un écran : traitement **ambulatoire** → salle de soins du premier au dernier passage ;
traitement **hospitalier** → **première** administration en salle de soins, **suivantes** en
hospitalisation. C’est le **rang** qui décide du secteur, jamais l’organisation du service. Un poste qui
tente de prendre ce qui ne lui revient pas est refusé **en le nommant** — un refus muet ferait croire à
une panne.

**Qui prescrit n’est pas qui exécute, et la sage-femme est aux deux.** Prescripteurs : 3 médecins et
3 sages-femmes. Exécutants : 7 infirmiers et les mêmes 3 sages-femmes. D’où **deux droits distincts sur
une même fiche** (`prescrit`, `execute`) et non deux listes — deux listes auraient obligé à inscrire la
sage-femme deux fois, avec le risque de n’en corriger qu’une. Les **soignants sont dérivés du
personnel**, jamais ressaisis : une seconde liste de noms divergerait du dossier RH au premier
recrutement. Les effectifs énoncés par la Direction tombent juste dès lors qu’on met à part
l’**Infirmier — Surveillant Général** (qui supervise : c’est l’IG de la description de poste) et
l’**Échographiste** (qui réalise sans prescrire).

**Bloc opératoire** : le compte rendu porte ses **trois intervenants nommés** — opérateur,
aide-opérateur, anesthésiste — parce que c’est la pièce qu’on ressort quand une suite opératoire est
contestée. Les **deux check-listes sont séparées** : les fondre ferait cocher après l’intervention ce
qui devait l’être avant. Leur contenu ne vient d’**aucun document remis** et reste marqué à valider.
Une check-liste incomplète est **signalée, jamais refusée** — refuser l’enregistrement pousserait à tout
cocher pour pouvoir avancer.

**Maternité : trois comptes rendus** (accouchement, planning familial, AMIU) aux rubriques propres. Un
gabarit unique aurait fait remplir à la sage-femme des champs sans objet, ce qui est le plus sûr moyen
de la faire écrire n’importe quoi.

**Le méga-menu se replie désormais sur `go()`**, et non plus seulement sur les ancres. Les boutons des
tableaux de bord (« Encaisser », « Prélever ») et les raccourcis permanents du bandeau ne sont pas des
`<a href>` et échappaient à la délégation ; `go()` étant le point de passage obligé de toute navigation
programmatique, aucun bouton présent ou futur ne peut plus y échapper. La délégation sur les liens
remonte au **document** et non plus au conteneur de page, qui ne contenait pas les raccourcis.

**Quatre pièges rencontrés dans ce lot :**
- `C.fcfa` n’existe pas — le formateur s’appelle `C.money`. Invisible au `node --check`, visible
  au premier rendu.
- `P.etat` prend `{titre, sousTitre, cartouche, contenu, signatures}` et une signature porte `role`,
  jamais `label`. Supposer une API plutôt que la lire coûte un aller-retour à chaque fois.
- `K.creer()` **insère lui-même**. Une création qui doit passer par le moteur (contrôle
  d’habilitation, tarif RG-09, notification du secteur) produirait alors **deux fiches, dont une vide** :
  on lui emprunte le contrôle des droits, on écrit l’insertion soi-même.
- Une fonction utilitaire déclarée dans la fermeture d’un écran est **invisible au suivant**. Deux
  écrans qui posent la même question la déclarent au **module**.

**LE TOTAL D’UN ÉTAT EST CALCULÉ, JAMAIS FOURNI (vague 28).** Défaut signalé par la Direction et
bien réel : `P.tableau` acceptait un objet `total` déjà rempli par l’appelant. Sur environ cent
trente tableaux imprimés, **six** en portaient un — et un appelant qui calcule à côté produisait un
faux total que rien ne contredisait, puisque la somme n’était jamais refaite. Le total est devenu une
propriété de la **colonne** (`somme`), refaite depuis les lignes réellement imprimées : un état ne
peut plus afficher un total qui ne corresponde pas à ce qu’il montre. **On ne totalise que ce qui a un
sens** — ni le prix unitaire ni la remise unitaire : additionner des prix unitaires ne produit aucune
grandeur, et un total faux est pire qu’un total absent parce qu’il se lit comme un total juste.

**TROIS PARTS SUR LA PIÈCE DE CAISSE.** La part **NON ASSURÉE** n’est pas la part assuré : la
seconde comprend le ticket modérateur sur des lignes **couvertes**, la première porte l’intégralité
des lignes que **personne** ne couvre — certificats hors SOS, planification familiale, actes exclus.
Les confondre empêche de répondre à la question qu’on pose tous les jours au guichet : « je suis
assuré, pourquoi je paie tout ça ? ». S’y ajoute le **TOTAL DÛ**, sans lequel un règlement partiel
laissait le patient repartir sans savoir ce qu’il devait encore. La **base MECeF** est désormais
imprimée sur la pièce : elle ne porte que la part réglée par le patient, ce qui se vérifie sans ouvrir
le logiciel. Une opération de caisse **sans dossier patient** est possible et le dit — vendre un
carnet n’oblige pas à ouvrir un dossier.

**Décisions RBAC de la Direction.** Le **laborantin devient Biologiste médical** — libellé long ET
court, car c’est le court que portent le ruban et le bandeau ; un renommage à moitié appliqué fait
croire à deux rôles distincts. Les comptes **Pharmacie** et **RH** sont **fermés par ARCHIVAGE**
(RG-14) : effacer rendrait anonymes des mouvements de stock signés et des bulletins émis. **Un
archivage va TOUJOURS avec son transfert** — la pharmacie passe au Caissier, les RH et la paie à la
Directrice Administrative ; fermer sans transférer aurait fermé le métier. Quatre comptes créés :
Aide-soignante, Technicien d’échographie, Surveillant, Assistant comptable. Le **technicien
d’échographie n’a aucun accès financier** et lit le dossier sans le modifier — un manipulateur qui
verrait la caisse pourrait faire dépendre l’examen du paiement. Le **Surveillant** recouvre les
missions 1 et 5 de la description de poste de l’Infirmier Général.

**Le code patient devient `CNT/[n° d’ordre]/[année]`.** Le séparateur après CNT lève l’ambiguïté :
« CNT530/25 » se lit mal, « CNT/530/25 » ne laisse aucun doute. **RG-01 interdisant de modifier un
code attribué, le format ne vaut que pour les dossiers à venir** — renuméroter l’existant romprait le
lien avec l’archive papier, ce qui est exactement ce que la règle protège.

**La devise « Votre santé, notre raison de vivre »** figure à l’en-tête de chaque module et sur les
états imprimés. Le prototype portait « Votre santé, notre priorité », qui n’est pas la formule de la
clinique. Une devise qui ne se lit nulle part n’en est pas une.

**Un piège de plus : `node -e` mange les échappements de classes Tailwind** entre guillemets, comme
il mange déjà les backticks. Tout script d’édition passe par un fichier.

**UNE FACTURE SANS LIGNES N’EST PAS UNE FACTURE, C’EST UN TOTAL (vague 29).** Défaut signalé par la
Direction : « le reçu de paiement ne détaille pas les articles […] quel examen a été payé, on doit
savoir », et « les examens payés ne viennent pas au labo ». **La sonde a renversé l’hypothèse
évidente** : le reçu détaillé et l’encaissement ligne par ligne fonctionnaient — trois analyses réglées
sur cinq passaient bien en `attente_prelevement`, deux restaient bloquées. Le défaut était que les
**320 factures du jeu de démonstration étaient engendrées avec un montant tiré au hasard et AUCUNE
ligne**. Sur ces pièces — presque toutes celles que la caisse voit — le reçu n’avait rien à détailler
et un règlement partiel n’avait aucune ligne à sélectionner. `genFactures()` construit désormais les
lignes d’abord, et **le total est leur somme**, jamais un nombre choisi à part.

**Le bug des totaux, pris sur le fait.** Les deux reçus passaient à `P.tableau` un objet `total` dont
les clés — `nature`, `qte`, `pu` — ne correspondaient à **aucune colonne** : les colonnes n’ont pas de
`key`, elles ont des `value`. Le pied cherchait `total[undefined]` et n’affichait rien. Le total
n’était pas faux, il était **absent** — et un pied vide se lit comme une mise en page. D’où le passage
au calcul automatique par `somme` sur la colonne.

**Le registre des pièces du jour** manquait à l’écran de caisse, qui ne portait que l’arrêté journalier
(un état agrégé) et la file des prescriptions. Le patient qui revient avec son reçu ne pouvait pas être
servi. Le registre réimprime le reçu détaillé et **reprend l’encaissement là où il s’était arrêté**.

**Les quatorze comptes nommés par la Direction (25/08/2026) rectifient trois postes de l’organigramme,
et les rectifications ne sont pas cosmétiques :** KINNOU A. Ganiou est **Ingénieur Biomédical** et non
laborantin — il entretient les automates, il ne rend pas de résultats, et lui laisser le compte du
laboratoire lui aurait ouvert la **validation biologique**, qui engage la responsabilité du biologiste.
Conséquence à signaler : **aucun compte de biologiste médical ne figure dans la liste remise**.
GBEDJI Hervé est **Assistant de Direction** — c’est bien le poste que décrit la seconde description de
poste, celle qui s’intitule « Directrice Administrative » mais décrit son adjoint. DIEYABIDI Aïssatou
est **Caissière-Dispensatrice**, poste combiné qui confirme le rattachement de la pharmacie au compte
Caissier. **La liste des comptes n’est pas l’effectif soignant** : 14 personnes ouvrent une session,
la clinique compte 3 médecins, 3 sages-femmes et 7 infirmiers. Les confondre fermerait le logiciel à
dix agents.

**Le soin intraveineux renverse la règle générale.** La grille relevée porte 800 / 1 200 ; la Direction
arrête **1 000 non assuré, 800 assuré**. C’est le **seul** acte du catalogue où l’assuré paie moins.
L’exception est appliquée et **signalée** — non marquée, elle passerait pour une coquille et quelqu’un
la « corrigerait ».

**Le calendrier fiscal est CONFIRMÉ, pas corrigé.** Les réponses de la Direction correspondent
exactement à ce qui était implémenté : impôt sur les sociétés aux 10 mars, juin, septembre et décembre ;
liquidation du solde **puis** dépôt des états financiers au 30 avril ; CCIB en déclaration prévisionnelle
de fin de mois, deux tranches de 50 % aux 10 mars et 10 juin. La mention « reste à confirmer » a été
levée : la laisser ferait redemander indéfiniment ce qui est tranché.

**Deux ordonnances, deux pharmacies.** La **pharmacie interne** sert les soins d’urgence administrés sur
place : le produit part vers la **salle de soins**, jamais vers le patient, et la sortie est justifiée
par une prescription, non par un ticket. La **pharmacie externe** sert la voie orale que le patient
emporte. Deux écrans et non un filtre : les circuits n’ont ni le même justificatif, ni le même
destinataire, ni le même rythme.

**Le transfert de stock devient multi-lignes.** Un réapprovisionnement porte sur quinze à vingt
références ; les transférer une à une produisait vingt bons là où le magasinier fait **un** voyage.
RG-03 est contrôlé **ligne par ligne** en nommant l’article, et le disponible tient compte de ce qui est
**déjà posé sur le bon** — sans quoi on pourrait inscrire deux fois la totalité du stock. L’annulation
restitue **toutes** les lignes : un transfert à moitié annulé laisserait le stock faux.

**Fiche de référence et contre-référence** — deux collections et non une. La contre-référence revient
d’un **autre établissement**, souvent des semaines plus tard, et parfois jamais : les fondre obligerait
à distinguer « pas encore revenue » de « champs non remplis », alors que c’est précisément l’indicateur
à suivre. Le lien est le **numéro de la fiche**, seul identifiant que les deux établissements partagent.
La **concordance des diagnostics** et le caractère **justifié** de la référence sont les deux indicateurs
que le formulaire officiel demande : une discordance n’est pas une faute à masquer, c’est l’information
la plus utile que le centre d’accueil puisse renvoyer.

**L’échographie applique la spécification manuscrite de l’échographiste** : listes de choix partout,
**sauf Annexes et Conclusion** — « à remplir par moi-même », écrit-il. L’âge gestationnel est un
**couple SA + jours** et non un texte : le saisir librement autoriserait « 7 mois », qui ne se compare à
rien. Le compte rendu porte **deux intervenants nommés**, le prescripteur et le réalisateur.

**Feuille de température : une donnée, deux présentations.** Le graphique à **cinq échelles partageant
six lignes de grille** et le tableau lisent la **même** collection. L’échelle du pouls
(60·80·100·120·140·**180**) **n’est pas linéaire** : le dernier intervalle vaut le double, et une règle
de trois placerait tous les points hauts au mauvais endroit — d’où l’interpolation entre graduations.

**Trois pièges rencontrés dans ce lot, tous mis au jour par la SONDE et non par la lecture :**
- **Les admissions portent `statut: 'en_cours'`, pas `'actif'`**, et la date s’appelle `dateEntree`.
  Mon filtre ne correspondait à rien et la fiche de surveillance restait vide sur un patient hospitalisé
  depuis six jours.
- **Le format du code patient vivait à DEUX endroits** : `C.codePatient()` et une construction en dur
  dans l’amorçage. Corriger la première n’avait aucun effet. Une règle qui existe en deux exemplaires
  diverge au premier correctif — c’est précisément ce que « ne rien coder en dur » interdit.
- **`releves` était amorcée par un écran** alors que trois la lisent : celui qu’on ouvrait en premier
  décidait si les autres voyaient quelque chose. Le piège documenté du prototype, rencontré une fois de
  plus.

**Un test qui recopie le manifeste finit toujours par diverger de lui.** Le compte de cartes d’un hub
était écrit en dur (13) et échouait à chaque écran ajouté, alors que l’assertion avait raison. Il est
désormais **dérivé du manifeste**.

**LA FACTURE MÈRE VAUT PAR SON RAPPROCHEMENT (vague 30).** La facture mensuelle s’adresse à UN
souscripteur ; la compagnie en reçoit plusieurs et n’avait aucune pièce unique à rapprocher de son
règlement. La **mère** consolide ses **filles** — mais ce n’est pas la consolidation qui fait sa
valeur, c’est le contrôle : **trois totaux doivent coïncider** — somme des souscripteurs, somme des
factures patients, somme du **détail ligne à ligne**. L’émission est **refusée** tant qu’ils divergent,
et l’écart **nomme la pièce en cause**. Une mère qui ne se recoupe pas donnerait à la compagnie un
montant que la clinique ne saurait pas justifier le jour du litige.

Le troisième contrôle descend à la **ligne** parce que c’est le niveau auquel une compagnie conteste.
Une mère émise **fige les numéros de ses filles et son contrôle** : sans cela, refaire le rapprochement
six mois plus tard serait impossible dès qu’une pièce aurait été archivée. Elle **ne se modifie plus** —
une correction passe par un avoir, sans quoi la compagnie et la clinique n’auraient plus le même
document sous les yeux.

**LE RÉPERTOIRE DES AMBULANCES N’EST PAS UN CARNET D’ADRESSES.** On y vient dans une urgence, et trois
choses décident du temps perdu : les **disponibles remontent en tête** (un numéro qu’on appelle pour
s’entendre dire « nous sommes en course » a coûté deux minutes), le **numéro se lit en grand** et
cliquable, et la **dernière vérification est datée** — un répertoire d’urgence dont on ignore l’âge est
un répertoire qu’on n’ose pas utiliser. Un numéro périmé est **signalé, jamais masqué** : un vieux
numéro vaut mieux que rien.

**AUCUN NUMÉRO D’URGENCE N’EST INVENTÉ.** Seuls ceux de l’en-tête officiel figurent ; les structures
extérieures ont une fiche **vide qui le dit**. Inventer un numéro d’urgence serait la faute la plus
grave de tout ce prototype.

**LE DOSSIER ÉTENDU : DEUX ZONES, DEUX RESPONSABILITÉS.** La coupure n’est pas une commodité
d’affichage. **Zone 1 — Accueil** : identification, coordonnées, couverture, constantes ; l’accueil
remplit et ne voit rien d’autre (RG-13), et chacune de ses consultations est **journalisée**.
**Zone 2 — Consultation** : historique, antécédents, examen physique, décisions. Mêler les deux ferait
qu’un secrétaire médical lirait un diagnostic en cherchant un numéro de téléphone.

**Les antécédents sont en TROIS catégories strictes** — médicaux, chirurgicaux, gynéco-obstétricaux.
Un antécédent chirurgical rangé dans les médicaux se perd au moment où le chirurgien en a besoin,
c’est-à-dire avant d’ouvrir. **L’examen physique suit ses quatre temps dans l’ordre** — inspection,
palpation, percussion, auscultation : un champ unique « examen » laisse oublier la percussion, quatre
champs rappellent ce qui n’a pas été fait.

**Le cycle de vie est ORDONNÉ** : EN ATTENTE → EN CONSULTATION → EN ATTENTE LABO → CLÔTURÉ. Les sauts
sont **refusés** — clôturer un dossier resté « en attente » signerait une consultation qui n’a pas eu
lieu. « EN ATTENTE LABO » n’est pas un état de garage : c’est celui qui permet de compter les dossiers
suspendus à un résultat.

**Les actes chirurgicaux et le bloc ne s’ÉCRIVENT que par le chirurgien — mais se LISENT par tous.**
La distinction est essentielle : le généraliste doit pouvoir lire ce que le chirurgien a écrit, c’est
son patient aussi. Les rubriques ne sont donc pas masquées, elles sont désactivées, et le contrôle est
**refait au moteur** — un champ désactivé dans le navigateur ne protège rien.

**Trois pièges de plus, tous mis au jour par la SONDE :**
- **Le journal se journalisait lui-même.** `journaliserRecherche` écrivait par
  `collection('audit').insert()`, or `insert()` appelle `log()` qui écrit déjà dans `db.audit` :
  une recherche produisait **deux entrées**, dont une fantôme décrivant l’écriture de la première. Un
  journal d’audit qui se double devient illisible au moment précis où l’on en a besoin. D’où
  `S.journaliserAcces()`, qui écrit une entrée et une seule.
- **`check.js` comptait `tel:` comme un lien de page** et déclarait cassés des numéros de téléphone
  parfaitement valides. Le filtre exclut désormais `tel:`, `sms:`, `data:` et `javascript:`.
- **Un guillemet fermant français hors chaîne** (`» `) casse le fichier au `node --check`. La
  typographie française et le JavaScript se disputent les mêmes caractères ; il faut relire.

**LE PREMIER REGARD (vague 31).** Chaque tableau de bord porte un bandeau unique — ce que le profil
vérifie **en arrivant**. Ce n’est pas un cinquième indicateur : un bandeau de KPI demande à être lu et
comparé, le premier regard demande à être **vu**. Il porte UNE question, son compte et le lien qui y
mène, et il est posé **avant** les accès rapides et les indicateurs — l’ordre de lecture est la seule
chose qu’un tableau de bord contrôle vraiment.

**À zéro, il énonce une phrase.** « Rien ne vous attend » est une information ; un bandeau gris sans
texte ferait douter de l’écran. Le champ `vide` est donc obligatoire.

**Chaque premier regard est DÉRIVÉ d’un document**, non inventé : le point journalier de la caisse pour
la DAF vient de l’activité 25 de sa description de poste ; les retards du Surveillant de l’activité 7 et
de son indicateur « 95 % des retards constatés et notifiés » ; les créances de l’Assistant de Direction
de l’activité 8, où le mot « surtout les assureurs » est écrit. Ce qui n’est pas fondé est marqué
« proposition à valider » dans la note du bandeau.

**LE PIÈGE DE L’AMORÇAGE, À UNE ÉCHELLE NOUVELLE.** Les tableaux de bord lisent des collections que
d’autres modules amorçaient **depuis leur écran**. Un comptable ouvrant son tableau sans être passé par
« Échéances fiscales » lisait « 0 échéance dépassée ». Ce n’est pas un affichage vide, c’est un
affichage **faux** — il dit à la Direction qu’il n’y a rien à payer. Un tableau de bord qui se trompe
dans ce sens est plus dangereux qu’un tableau de bord absent. Le **calendrier fiscal** est donc remonté
au socle : c’est un référentiel entièrement dérivé de `D.CALENDRIER_FISCAL`, et la note qui le disait
« lu par un seul écran » est devenue fausse le jour où les tableaux l’ont lu.

**UN COMPTEUR QUI LIT LE MAUVAIS CHAMP SE TROMPE DANS LES DEUX SENS.** Le premier jet du bandeau de la
Direction filtrait sur `statut !== 'payee'` et `dateEcheance`, alors que les champs réels sont `paye`
et `echeance` : il annonçait **63 échéances dépassées** au lieu de 4 — alarmant à tort là où l’erreur
symétrique aurait rassuré à tort. Les deux sont également fautifs, et seule la **sonde** les distingue
d’un chiffre plausible.

**Cinq tableaux de bord pour les rôles créés** — aide-soignante, technicien d’échographie, surveillant,
assistant de direction, ingénieur biomédical. Sans tableau propre, ils retombaient sur celui d’un autre
profil : le technicien d’échographie voyait le tableau du médecin, qui lui montre des résultats
d’analyse dont il n’a que faire. Chacun **annonce aussi ce qu’il ne voit pas** — l’échographiste n’a
aucun accès financier, l’aide-soignante aucun résultat, l’ingénieur biomédical aucune validation
biologique.

**Un tableau de bord de compte FERMÉ le dit.** Pharmacie et RH sont archivés ; leurs tableaux annoncent
la fermeture et **où la fonction a été transférée**, au lieu d’afficher des indicateurs vides comme si
de rien n’était.

**`check.js` comptait `tel:` comme un lien de page** et déclarait cassés des numéros de téléphone
valides. Le filtre exclut désormais `tel:`, `sms:`, `data:` et `javascript:`.

**LE TABLEAU DE BORD EST UN MODE D’EMPLOI, PAS UN MENU (vague 32).** Demande de la Direction :
« sur chaque page, quelles sont les actions à faire — scénarios métier de A à Z », et « les boutons des
actions courantes doivent être sur les accès rapides ». Une grille de liens dit **où** aller ; elle ne
dit ni **ce qu’il faut faire**, ni **dans quel ordre**, ni **qui prend la suite**. Un agent nouveau
devine, un agent ancien fait ce qu’il a toujours fait, et personne ne voit l’étape qu’on saute.

`K.parcours(groupes)` rend la **chaîne** : titre, étapes numérotées, détail par étape, bouton sur la
première action. Treize postes en portent — accueil (les onze chaînes dictées par la Direction),
médecin, infirmier, biologiste, caisse, stock, comptabilité, aide-soignante, échographiste, surveillant,
assistant de direction, biomédical, ambulancier.

Trois règles de conception, toutes trois nées d’un défaut évité :

- **une étape dont l’écran est fermé au profil reste VISIBLE mais non cliquable.** La masquer ferait
  croire qu’elle n’existe pas ; la rendre cliquable promettrait une porte fermée. Elle est grisée et
  porte la mention « fermé à votre profil » ;
- **une étape d’un AUTRE poste est nommée** par une pastille — « Caisse », « Laboratoire », « DAF ».
  Sans elle, l’accueil traite son geste comme une fin en soi et le patient arrive à la caisse sans que
  la caisse sache pourquoi ;
- **l’ordre est celui du terrain, pas celui des modules.** La chaîne « sortie d’hospitalisation »
  commence par le solde (M8) et finit par le rendez-vous de contrôle (M2).

La section porte `rapide: true` : elle remonte **avant** les indicateurs. Un mode d’emploi placé sous
les tableaux ne se lit pas.

**Un écran cité doit exister au manifeste.** Le contrôle est trivial — extraire les `ecran:` des
parcours et les confronter aux `id:` de `nav.js` — et il a levé deux cibles mortes, dont une qui
existait **avant** cette vague : `dash-biomedical` comptait les pannes d’une collection que rien
n’alimentait et renvoyait vers `m13-maintenance`, absent du manifeste. Un indicateur éternellement à
zéro n’alerte de rien.

**Parc technique & maintenance (vague 32).** L’écran manquant a donc été créé plutôt que le lien retiré :
c’est l’outil de l’ingénieur biomédical, et le laboratoire y voit qu’un automate est en panne. Deux
partis pris. **Le parc est une proposition, pas un relevé** — aucun document de cadrage n’inventorie
les équipements, l’inventaire SAGE ne porte que les *articles* ; les dix-huit fiches amorcées portent
`aCompleter` et le marquage **disparaît par la saisie** de la marque, du n° de série et de la mise en
service, non par une case à cocher qu’on oublie. **Une panne est un état, pas un commentaire** : trois
états seulement — en service, en panne, réformé — parce que c’est la seule question posée à huit heures
du matin. Les amortissements restent en `m12-immobilisations` : un parc technique n’est pas un
registre comptable.

**LES ACTES REPRENNENT LES PRIX DES GRILLES (vague 33).** Réponse à B5 — « publie des seeders de prix
réels ». Les 69 actes du document « Répartition des activités » portaient **64 tarifs d’attente**,
inventés le 20/08/2026 pour rendre la facturation exerçable ; les six grilles imprimées, extraites
depuis, donnent les prix réels — et **deux par acte**. Vingt-huit actes sont désormais rapprochés,
0 contredit la règle de la Direction (« l’assuré paie moins »), et l’écran affiche **les deux colonnes**.

Le rapprochement vit dans `data-tarifs.js`, **pas** dans `data.js` : l’ordre de chargement met
`data.js` avant, donc `D.CATALOGUE` n’existe pas encore quand les actes se construisent.

**Deux voies de rapprochement, et aucune troisième.** Libellé identique (aux accents, à la casse et aux
parenthèses près), ou **correspondance nommée** écrite une par une avec sa raison. Le rapprochement
approximatif est proscrit, et l’essai l’a montré : il appariait « Consultation généraliste **à
domicile** » avec « Consultation généraliste » — le déplacement disparaissait — et « Glycémie rapide »
au lit du malade avec la « Glycémie » du laboratoire, qui n’est pas le même acte.

**Un acte que la grille DÉCLINE n’est pas un acte sans prix.** Sept accouchements, quatre paliers
d’oxygénothérapie, trois épisiotomies, deux ponctions lombaires : `variantesGrille` les porte et
`motifPrix` le dit. Choisir une variante à la place de la clinique facturerait le mauvais tarif ;
chercher un prix manquant là où c’est une question de nomenclature ferait perdre du temps.

**LES ANOMALIES DU CLASSEUR 2025 — DIAGNOSTIC, PAS GOMMAGE (vague 33).** La Direction a répondu
« FAUT CORRIGER » (C8). Corriger un écart, ce n’est pas le faire disparaître : c’est trouver la ligne
qui l’explique et dire **laquelle des deux sources fait foi**.

- **L’écart de 141 667 FCFA n’est pas un arrondi.** Les lignes du détail somment **exactement** à leur
  propre total (cumul des écarts internes : 0), et 141 667 est **précisément l’échéance mensuelle** de
  la ligne « FONDS DE GARANTIE », en novembre et décembre — et ce montant n’apparaît nulle part
  ailleurs dans le classeur. La ligne TOTAL **omet une échéance** : c’est elle qui est fautive. La
  baseline s’appuie donc sur le détail, et la correction porte sur le **document source**, pas sur le
  logiciel. Le diagnostic est **calculé à l’affichage**, jamais écrit en dur — `npm run compta`
  régénère `data-compta.js` depuis l’Excel, et un montant codé serait faux à la première régénération.
- **Les trois postes sans numéro de compte relèvent du même emprunt** : un rattachement est **proposé**
  (275000 Dépôts et cautionnements, 631800 Autres frais bancaires, 646800 Autres droits), et l’écran
  dit que c’est une proposition. Rattacher d’office fausserait la balance sans que personne ne l’ait
  décidé.
- **Les 32 articles SAGE non valorisés ne peuvent pas être corrigés depuis les documents** :
  vérification faite, le catalogue des médicaments a lui aussi ses colonnes vierges et une seule de ces
  références y figure — sans montant. Ce qui **était** corrigeable, c’est l’impossibilité de corriger :
  la saisie du prix de revient est ouverte, référence par référence, **avec sa source obligatoire**.
  Un prix de revient sans origine est exactement le problème qu’on cherche à résoudre.

**LA CORRECTION EST UNE SURCOUCHE, JAMAIS UNE RÉÉCRITURE.** La valorisation vit dans la collection
`valorisationsSage`, datée et signée ; `INVENTAIRE_SAGE` reste ce qu’il est et fait foi sur ce qu’il
porte. Écraser le document ferait perdre la distinction entre ce qu’il disait et ce que la clinique a
décidé — précisément ce qu’un audit demande. L’écran compte les deux séparément.

**DEUX APPELS ÉCRITS SUR UNE API IMAGINÉE, invisibles au contrôle (vague 33) :**

- **`K.crud` n’accepte pas d’onglets déclaratifs.** Il fabrique lui-même « Tous les X » et
  « Archivés », et ne prend que des `extraTabs` porteurs de leur propre `render`. Quatre onglets
  passés sous une clé `onglets` ont été **ignorés en silence** — l’écran s’affichait, simplement sans
  eux. Un **filtre** était de toute façon le bon instrument : trois lectures d’une même population ne
  sont pas trois populations.
- **`K.miniTable(colonnes, lignes)` accepte DEUX formes depuis la phase 1** : colonnes objets
  (`{key, label, align, render}`) avec lignes objets, ou colonnes **chaînes** avec lignes-tableaux de
  valeurs (une chaîne devient `{label, key: rang}`). Avant cette normalisation, dix-sept vues de
  détail rendaient des tableaux aux en-têtes vides et aux cellules « — », sans un mot — dont le
  détail de la pièce de caisse. Le scénario 41 le sonde.

Les deux sont hors de portée de `npm run check`, qui **n’ouvre pas les onglets et ne lit pas les
cellules**. C’est le **scénario 37** qui les a levés — il clique, il change de profil, et il vérifie que
le diagnostic est **vrai** et non seulement affiché.

**UN RÔLE DÉCIDÉ PAR LA DIRECTION A SA FICHE AU MANIFESTE (vague 33).** Les cinq rôles créés le
24/08/2026 — aide-soignant, technicien d’échographie, surveillant, assistant de direction, ingénieur
biomédical — avaient leurs écrans, leurs comptes et leur tableau de bord, mais **aucune entrée dans
`N.ROLES`** : ni intitulé, ni couleur, ni page d’accueil. Tout ce qui lit ce référentiel — bandeau,
ruban, écran de connexion, états imprimés — ne savait pas les nommer.

Le mécanisme d’**enregistrement dynamique** (`nouveau` dans la collection `rbac`) sert aux rôles que
l’administrateur invente **en cours d’exploitation**. Un rôle décidé par la Direction et pourvu d’un
tableau de bord écrit n’en relève pas : sa place est au manifeste, comme les quinze premiers.

**Le défaut ne s’est révélé qu’en rattachant un agent à son propre rôle.** TEPA Séraphine ouvrait encore
sa session en `infirmier` — rôle qui existait avant que le sien ne soit créé — et tombait donc sur le
tableau de bord des infirmiers, qui montre des prescriptions à exécuter. En la rattachant à
`aide_soignant`, la liste des connexions a lu `N.ROLES[role].label` sur une fiche absente et la page
d’accueil a cassé. Un rôle à moitié déclaré ne se voit pas tant que personne ne l’endosse.

**TROIS PARTS, ET NON DEUX (vague 34).** La Direction demande que les points imprimés affichent
« le pourcentage payé par l’assuré, par le personnel ayant bénéficié de remise ou un client ayant
bénéficié de remise ». Deux de ces trois grandeurs **n’existaient pas dans les données** : toute ligne
portait `remise: 0` et le calcul de prise en charge ignorait `personnelId`. Les colonnes demandées
auraient affiché zéro partout.

Ce qu’il ne faut pas confondre :

| Grandeur | Qui la doit | Conséquence |
|---|---|---|
| **Part assureur** | un tiers | c’est une **créance** : 411, recouvrement, facture mère |
| **Prise en charge du personnel** | personne | la clinique la **supporte** ; ni recette ni écriture |
| **Remise** | personne | elle **diminue la base**, ce n’est pas une part |

Ranger la prise en charge du personnel dans la part assureur fabriquerait **une créance sur personne**.
**RG-02 gouverne les remises** : un médicament se facture au prix d’achat sans marge, donc une remise le
vendrait à perte — aucune ligne de médicament n’en porte, ni au peuplement ni au moteur.

**LE MOTEUR ET LE PEUPLEMENT CONSTRUISENT LA MÊME PIÈCE.** `construireLignes()` porte les trois parts
comme `genFactures()` : sans cela, le point de vente compterait juste sur les pièces du jeu de
démonstration et faux sur celles émises en séance. Et l’en-tête **somme ses lignes** au lieu de
recalculer à côté — le défaut déjà corrigé sur les états imprimés.

**LES POINTS DU GESTIONNAIRE DE STOCK (vague 34).** Quatorze exigences, **un seul principe** : la même
population de lignes lue selon **quatre axes** — période, client, article, groupe. Écrire un écran par
exigence aurait produit quatorze façons de compter la même chose, qui auraient divergé au premier
correctif.

- `m6-point-ventes` — journal des ventes (détail par client), par client, par article (la **quantité
  vendue** est la première colonne : c’est la question posée), par groupe et famille, évolution.
  Impression **détaillée ou globale**, portant les trois pourcentages en colonnes **et en toutes
  lettres** sous le tableau.
- `m6-point-stock` — les cinq vues demandées, chacune avec **son montant** : restant pharmacie, reçu
  pharmacie, nouveau magasin, sorti magasin, restant magasin.

**UN ÉTAT N’EST PAS UN FLUX.** Un état se lit **à une date** (ce qui reste en rayon), un flux **sur une
période** (ce qui est entré ou sorti). Les afficher sous le même filtre sans le dire ferait croire que
le stock restant dépend de la fenêtre qu’on regarde. L’écran le dit, et la périodicité est **désactivée**
sur les vues d’état.

**Un transfert n’est pas une entrée nouvelle.** Le « stock nouveau enregistré au magasin » ne compte que
les entrées fournisseur du stock gros : compter les transferts gonflerait la valeur du stock de ce que
la clinique possède déjà.

**POURQUOI CES ÉCRANS SONT EN M6 ET NON EN M8.** `m8-recettes` répond à « combien a-t-on encaissé cette
semaine ? » — un seul axe, le temps. Le gestionnaire demande « combien ce client a-t-il payé », « combien
de fois cet article est-il sorti », « que pèse le groupe analyses ». Plaquer ces axes analytiques sur
l’écran des recettes l’aurait rendu illisible pour le caissier, qui n’en a pas besoin.

**DEUX RÉFÉRENTIELS REMONTÉS AU SOCLE.** Le piège documenté, rencontré deux fois de plus :

- **les six périodicités** vivaient dans `m8-facturation.js` ; les points sont des écrans de M6, et une
  page ne charge que le module de son écran. Elles sont dans `core.js` (`C.PERIODES`, `C.bornes`,
  `C.bornesLibres`, `C.dansBornes`, `C.libellePeriode`) ;
- **la méthode de valorisation** (prix de vente ou CUMP) était lue de DEUX façons : `configuration.js`
  consultait la préférence enregistrée, tout le reste lisait `D.PARAM_STOCK`, que seul cet écran met à
  jour. La Direction basculait sur le CUMP et rien ne changeait ailleurs — une bascule qui paraît sans
  effet est pire que pas de bascule. Elle est désormais dans `store.js` (`S.valorisationSortie()`,
  `S.valeurUnitaire()`), comme les autres bascules d’exploitation.

**LES GROUPES DE PRESTATION** (`D.GROUPES_PRESTATION`) coiffent les catégories de ligne : « soins » n’est
pas une catégorie, c’est une famille de catégories — consultation et acte s’y rangent ensemble parce que
c’est ainsi que la clinique compte son activité. **L’hospitalisation reste à part** : c’est une durée
facturée, pas un acte, et la fondre dans les soins rendrait le prix de journée incomparable d’un mois à
l’autre.

**ACCÈS À LA CAISSE (26/08/2026).** Le DA, le comptable et le gestionnaire de stock avaient déjà M8 ;
**le Directeur Médical y entre**. Les quatre ont été nommés ensemble par la Direction.

**LE TECHNICIEN D’ÉCHOGRAPHIE : LE MODULE EN LECTURE, SON ÉCRAN EN ÉCRITURE.** `M2: EDITER` lui ouvrait
aussi les **ordonnances**, la salle de soins et la file d’attente. Un manipulateur qui rédige une
ordonnance, ce n’est pas une habilitation trop large — c’est un exercice illégal. M2 passe en lecture, et
`m2-imagerie` est ouvert en écriture par surcharge d’écran : **un écran l’emporte sur son module, et une
surcharge accorde autant qu’elle restreint**. Les trois écrans qu’il ne doit pas toucher sont fermés
**nommément**, pour que la matrice se vérifie sans raisonner sur le module.

**LE PROTOTYPE COMPOSE EN TYPOGRAPHIE FRANÇAISE.** `C.money` sépare les milliers par une **espace fine
insécable** (U+202F) et pose une **espace insécable** (U+00A0) avant la devise — un montant ne se coupe
pas en fin de ligne. Une sonde qui cherche une espace ordinaire mesure sa propre supposition et non
l’écran : comparer les **chiffres seuls**, toute espace neutralisée.

**UN ÉTAT ÉCRIT SOUS DEUX NOMS N’EST PLUS UN ÉTAT (vague 35).** Le défaut le plus grave du lot, et
il était invisible : `D.ETATS_RESULTAT` connaît `valide` — le seul état, avec `rectifie`, que
`D.resultatRendu()` déclare **opposable au prescripteur**. Le peuplement écrivait `valide_bio`.

Trois conséquences, toutes silencieuses :

- `resultatRendu('valide_bio')` vaut **faux** : aucun résultat n’était jamais rendu. L’écran affichait
  « aucun résultat » — pas « aucun résultat validé ». **327 demandes existaient, 0 était visible.**
- `etatResultat()` ne trouvait pas sa fiche et retombait sur un état fabriqué dont le libellé était le
  code lui-même.
- Le tableau de bord du médecin comparait **à la main** `'valide_bio' || 'rendu'` — deux codes dont
  **aucun** n’est au référentiel. Comparer un état à une chaîne écrite à la main plutôt que d’interroger
  le référentiel, c’est ainsi que deux vérités s’installent.

La correction porte sur les trois, et le magasin **reprend les jeux enregistrés** : sans reprise, le
laboratoire serait resté muet jusqu’à la prochaine réinitialisation.

**UNE FONCTION INCONNUE NE DOIT PAS FERMER L’ÉCRAN EN SILENCE.** `capacites()` retombait sur
`accueil` — le profil **le plus restrictif** — quand `session.fonction` n’était pas une clé de
`D.CAPACITES`. Un agent parfaitement habilité par son RÔLE ouvrait son poste, ne voyait rien, et lisait
qu’il n’avait pas accès ; personne ne pouvait relier la cause à l’effet. La fonction inconnue retombe
désormais sur la fonction **déduite du rôle** — donnée sûre, venue du manifeste et non d’une saisie — et
la substitution est signalée par `fonctionInconnue`.

**LE LABORATOIRE NE SAISIT PAS AVANT RÉCEPTION (vague 35).** L’onglet « À saisir » comptait
`en_attente` et `attente_prelevement` parmi les demandes saisissables. Le circuit décrit par le
biologiste est formel : saisir avant, c’est rendre un résultat pour un prélèvement qui n’a pas eu lieu.
**La ligne reste visible, le bouton est verrouillé** — la retirer ferait croire que la demande n’existe
pas, alors que le laboratoire a besoin de voir ce qui arrive. Le bouton dit **pourquoi** et **à quel
poste la balle se trouve**. Le clic sur la ligne est gardé aussi : un contrôle qu’on peut contourner
n’en est pas un.

**LE BANDEAU DE LECTURE SEULE APPARTIENT AU SOCLE.** `kit.crud` le posait sur ses propres écrans ; les
écrans construits à la main ne l’avaient pas. Il est désormais posé **une fois**, dans l’en-tête commun,
et tout écran présent ou futur en hérite. Deux précautions : il ne paraît que sur un écran **qui se
modifie** (un tableau de bord ou une statistique n’ont rien à modifier, et y annoncer une lecture seule
inquiéterait sans raison), et il ne double pas celui du kit.

**L’AUDIT DES ACTIONS PAR PROFIL (vague 35)** — `npm run audit-rbac` ouvre **chaque écran sous chaque
profil qui y a accès**, relève les commandes d’écriture affichées et les confronte aux droits du moteur.
Sur 106 sondages, **trois promesses réelles** : le biologiste et l’échographiste voyaient « Modifier le
dossier » et « Modifier les antécédents » sans en avoir le droit. Deux fautes symétriques sont
recherchées, et la seconde est la plus grave :

- **promettre** — un bouton actif sans le droit : il mène à un refus, ou pire, à une modification qui ne
  s’enregistre pas ;
- **cacher** — aucune commande alors que le droit est accordé : l’agent croit le logiciel incomplet et
  ressaisit ailleurs.

**Un tableau de bord n’est pas un écran d’écriture** : ses boutons sont des raccourcis vers un écran où
le profil a, lui, le droit d’écrire. Les compter comme des promesses ferait signaler un défaut là où il
n’y en a pas — et un audit qui crie au loup finit ignoré.

**« ADMINISTRATION » ET « DIRECTION » NE FONT PLUS QU’UN.** Le personnel portait tantôt l’un, tantôt
l’autre, et le plan analytique avait deux centres : l’effectif sortait coupé en deux dans les graphiques.
**Ce qui n’est PAS renommé** : le domaine « Administration » du méga-menu (M13 — courriers, réunions,
ambulance) désigne une **famille fonctionnelle d’écrans**, pas un service de l’organigramme. Le renommer
ferait chercher les courriers dans le bureau du Directeur Médical.

**DÉPENSES JOURNALIÈRES (vague 35) — la logique comptable.** Une dépense de trésorerie directe constate
une charge sans passer par un compte fournisseur : **débit compte de charge (classe 6), crédit compte de
trésorerie (5xx)**. Trois règles :

1. **RG-10 contrôlé AVANT écriture.** Le cas est trivial aujourd’hui ; le contrôle est là pour le jour
   où une dépense portera plusieurs lignes de charge.
2. **L’écriture naît en brouillon** — la validation comptable reste un geste humain, et d’autant plus
   qu’ici la saisie est ouverte à la caisse.
3. **Une dépense sans justificatif est une charge contestable.** Le reçu n’est pas bloquant — on
   n’empêche pas d’enregistrer une dépense réelle parce que le vendeur n’a pas de carnet — mais elle est
   **comptée et signalée**. C’est la première pièce qu’un contrôle réclame.

**DEUX CATÉGORIES SUR LE MÊME FORMULAIRE, ET CE N’EST PAS UN DOUBLON.** La **catégorie des charges
(SYSCOHADA)** est le compte du plan : elle décide où la charge tombe dans la balance et répond au fisc.
La **catégorie de dépenses** est la lecture de gestion — fonctionnement, médical, logistique — et répond
à la Direction, qui ne raisonne pas en numéros de compte. Le même achat de gants est « 604100 Matières
consommables » pour le comptable et « Consommables médicaux » pour la Directrice.

**L’ÉCRITURE DE DÉPENSE PREND LA FORME DES AUTRES.** Le magasin et le moteur d’encaissement posent **une
écriture plate par ligne** — même numéro de pièce, un compte et un sens chacune. J’avais écrit une
écriture porteuse d’un tableau `lignes` : la dépense aurait été **invisible du grand livre, de la
balance et du compte de résultat**, et le déséquilibre serait passé inaperçu parce qu’il n’aurait rien
déséquilibré — il aurait simplement manqué. Archiver une dépense archive **toutes** ses lignes : une
demi-écriture au journal serait pire qu’aucune.

**COMPTE DE RÉSULTAT — la cascade, pas le bloc (vague 35).** Marge commerciale → valeur ajoutée → EBE →
résultat d’exploitation → résultat financier → résultat net. C’est la cascade qui dit **d’où vient** le
résultat, et pas seulement combien il vaut. Trois points de méthode :

- **la marge commerciale doit être nulle** — RG-02 facture les médicaments au prix d’achat sans marge.
  Si elle ne l’est pas, c’est un signal, pas une bonne nouvelle ;
- **l’EBE ignore les amortissements et le financement**, qui dépendent de décisions passées et non de
  l’activité de l’année : c’est lui qu’on regarde pour savoir si l’exploitation tient debout ;
- **les intérêts d’emprunt sont au résultat financier**, jamais à l’exploitation — les y mettre ferait
  juger l’activité sur des choix de financement.

**Seules les écritures VALIDÉES sont retenues** : un brouillon n’est pas un fait comptable, et le
compter donnerait un résultat qui change quand le comptable rectifie une saisie. Le nombre de brouillons
écartés est **annoncé** — un écart silencieux entre le journal et le résultat serait pire.

**SEUIL DE RENTABILITÉ — la répartition fixe/variable est un JUGEMENT.** Aucun plan comptable ne la
porte : elle relève de l’analyse de gestion. Elle est donc **proposée, affichée compte par compte et
corrigeable**, et l’écran dit que c’est une proposition. La cacher donnerait un seuil qui a l’air d’un
fait alors qu’il dépend d’un choix. Deuxième réserve portée à l’écran : **le seuil suppose la structure
constante** — l’extrapoler au double serait faux, il faudrait embaucher et les charges fixes
changeraient de palier. Un seuil incalculable (marge sur coût variable nulle ou négative) est **un
diagnostic, pas un défaut d’affichage**.

**LE MÉDECIN VOIT SES PATIENTS — deux listes, jamais fondues.** Le ticket de file porte désormais un
`praticien` **facultatif** : dans une clinique de cette taille la file de consultation est souvent
**commune**, et rendre le champ obligatoire forcerait l’accueil à désigner quelqu’un au hasard. Le
tableau de bord montre donc **ceux qui l’attendent nommément** et **le vivier commun** : les mélanger
ferait manquer un patient adressé, n’afficher que les siens lui cacherait la charge du service.

**TROIS RÉFÉRENTIELS DE PLUS REMONTÉS AU SOCLE** — le piège documenté, rencontré trois fois dans ce lot :
les **comptes de trésorerie** (amorcés par l’écran des rapprochements, lus par la saisie des dépenses),
le **registre des présences** (amorcé par son écran, lu par trois), et la **méthode de valorisation**.

**« Modifier les antécédents » : le clic sur la ligne contournait le bouton retiré.** Retirer une
commande sans garder son chemin d’accès ne protège rien.

**LE RBAC N'EXISTAIT PAS POUR LA MOITIÉ DES RÔLES (vague 36).** L'inventaire l'a montré sans
ambiguïté : **un rôle sans fiche de surcharge obtient TOUS LES DROITS** sur chaque module que le
manifeste lui ouvre. Le caissier écrivait le **dossier médical**, les **antécédents**, le **stock gros**
et la **configuration fiscale** — 60 écrans, 60 modifiables. Le médecin : 74 sur 74.

Le manifeste dit **qui peut ouvrir l'écran**. Il ne dit rien de **qui peut y écrire**. Tant que la
question n'est pas posée, la réponse par défaut est « tout le monde » — l'inverse exact de RG-13.

Cinq fiches explicites — caissier, médecin, infirmier, gestionnaire de stock, accueil — bornent
désormais l'écriture. **La lecture reste large** : cloisonner au-delà du nécessaire fait ressaisir
ailleurs.

**DEUX PIÈGES DE LA SURCHARGE, PAYÉS COMPTANT :**

- **Une surcharge ACCORDE.** Déclarer `M6: { voir: true }` pour le caissier ne borne pas ses droits :
  cela lui **ouvre** le module, que le manifeste le lui donne ou non. Mesuré : caissier passé de 60 à
  84 écrans, médecin de 74 à 86. **Une fiche ne mentionne que les modules déjà ouverts au rôle.**
- **Un module `roles: ALL` ne se déclare jamais.** `DASH` et `RAP` portent `ALL` au manifeste, et ce
  sont les listes de CHAQUE écran qui filtrent. Déclarer le module en surcharge accorde tous ses écrans
  d'un coup — le caissier voyait les dix-neuf tableaux de bord.

**`npm run inventaire-rbac`** produit `newdocs/INVENTAIRE-RBAC.md` : ce que **chaque rôle voit
réellement**, obtenu en appelant `N.tree(role)` — la fonction même qu'appelle le ruban — avec le
magasin chargé. Ce n'est pas ce que le manifeste déclare, c'est ce que l'agent a sous les yeux.

**UN ÉCRAN AJOUTÉ À UN MODULE HÉRITE DE SES DROITS**, et rouvre donc en silence ce que les surcharges
avaient fermé. Le biologiste avait récupéré cinq écrans de M1 ajoutés depuis sa fiche. **L'inventaire
doit se refaire à chaque lot.**

**UN ÉCRAN FERMÉ QU'ON PEUT ENCORE ATTEINDRE N'EST PAS FERMÉ (vague 36).** `hubCartes` interrogeait
`N.can` avec une entrée **synthétique sans `id`** — or c'est l'`id` que consulte `ecranActif()`. La
banque de sang restait offerte sur le hub M5 alors qu'elle est fermée partout ailleurs. Le même défaut
vivait dans `accesRapides()`. **Passer l'identifiant réel, toujours.**

**RETIRER UNE ENTRÉE DU MANIFESTE N'EST JAMAIS LA BONNE FAÇON DE FERMER UN ÉCRAN.** Le manifeste est la
source unique des pages ET des liens : retirer l'entrée supprime la page à la génération et casse tout
lien qui la vise. Le canal correct est `modulesActifs`, celui qui ferme la banque de sang.

**PHARMACIE ET BIOMÉDICAL — deux cas qui se ressemblent et ne sont pas les mêmes.** L'**ingénieur
biomédical** n'existe pas : le poste avait été inventé sur une lecture erronée de la liste des comptes,
son tableau n'a pas de titulaire et se ferme. La **pharmacie existe** : c'est le COMPTE qui a été fermé
et l'activité transférée à la Caissière-Dispensatrice — son tableau **change de titulaire**, il ne ferme
pas. Le confondre supprimerait la vue d'une activité qui continue.

**LES MODALES AFFICHAIENT LEURS BALISES.** `U.confirm` rend son message en TEXTE ; onze appelants y
passent du HTML. Rendre en `innerHTML` aurait réglé l'affichage et **ouvert une injection** — ces
messages portent des noms de patients et des motifs saisis par un agent. `U.texteEnrichi()` échappe
**d'abord** tout, puis réactive un sous-ensemble fermé de balises de mise en forme. **C'est l'ordre qui
rend la fonction sûre.**

**LE CIRCUIT DU PRÉLÈVEMENT NE MONTRAIT RIEN DE CE QU'IL AVAIT FAIT.** L'écran range ses onglets sur les
HORODATAGES — `preleveLe`, `recuLaboLe` — et c'est le bon choix : la date dit QUAND le geste a eu lieu,
l'état ne dit que le résultat. Le peuplement écrivait `prelevementLe`. Un caractère d'écart :
« À transmettre » affichait **0** avec 38 échantillons prélevés, « À prélever » en comptait **244**,
c'est-à-dire tout, y compris des analyses déjà rendues. **Aucun test ne le voyait, parce qu'aucun test
n'ouvrait ces onglets.**

**UN ÉTAT DÉCLARÉ QUE RIEN NE PEUPLE EST UN ÉTAT QU'ON NE VOIT JAMAIS.** `en_cours` — reçu, non saisi —
est le seul état où le laboratoire a quelque chose à faire immédiatement. Le peuplement sautait de
« prélevé » à « validé techniquement ».

**LA CONTINUITÉ VAUT AUSSI POUR LA RELECTURE.** Corriger un résultat avant sa validation, c'est décider
de ce qui sera validé : laisser ce geste à un tiers viderait la règle de son sens — il suffirait de
corriger la saisie d'un collègue puis de le laisser signer.

**LE MOTEUR DE NOTIFICATION ET D'ALERTE SONORE (vague 36).** Couche **transversale** qui CONSOMME les
événements déjà produits. Elle ne décide jamais « si le stock est sous X, alerter » : le module l'a
déjà déterminé, avec le seuil que la clinique a fixé. **Le jour où un seuil change, `notifications.js`
n'a rien à changer.**

Quatre couches : événement métier → moteur (collecte, regroupe, route, priorise) → distribution (cloche,
badge, toast, centre) → sonorisation.

- **Le son est un CANAL, pas une logique.** Aucun module n'appelle `sonner()` : ils émettent leur
  événement, et le service audio est le seul composant qui lit un son.
- **Couper le son ne coupe pas l'alerte** — cloche, badge, toast et historique continuent. C'est ce qui
  rend le mode silencieux utilisable en salle.
- **Jamais de donnée médicale dans le son ni dans le message d'alerte** : « une nouvelle alerte nécessite
  votre attention », le détail reste derrière les permissions.
- **Entendre n'est pas traiter.** Une alerte acquittée cesse de sonner et sort du badge, mais **reste au
  centre** tant que sa cause dure. Elle disparaît quand la SOURCE cesse de la produire.
- **Une panne audio ne bloque jamais rien** : détection au démarrage, repli silencieux sur le visuel.
- **Tester le son ne crée aucune notification métier** — un test qui laisserait une trace serait pire
  qu'aucun test.

**UNE CLOCHE À 105 EST UNE CLOCHE QU'ON N'OUVRE PLUS.** Le moteur produisait une alerte par ARTICLE sous
son seuil. Fidèle aux données, inutilisable. **Le regroupement** rend UNE ligne portant le compte au-delà
de **trois** alertes de même nature : en dessous, nommer l'article rend service ; au-delà, c'est le
nombre qui informe. Une ligne groupée n'est acquittée que si tous ses membres le sont — **ou** si on
l'acquitte explicitement.

**LA CLOCHE PORTAIT UN BADGE « 4 » ÉCRIT EN DUR.** Quatre alertes, toujours, quel que soit le poste.
C'est **pire qu'un badge absent** : il donne à croire qu'on compte quelque chose. Le centre de
notifications, lui, recalculait ses propres seuils dans la barre supérieure — une seconde vérité, et
aucun routage : un caissier y lisait les alertes du magasin.

**UN CROCHET QUI NE SE DÉCLENCHE PAS RESSEMBLE EN TOUT POINT À UN CROCHET QUI FONCTIONNE.** Le rappel du
biologiste était déclaré sur la DÉFINITION de l'écran alors que le kit lit `avant` dans la configuration
du tableau de bord.

**Messages** : les toasts s’empilent **en haut à droite**, sous `#app-topbar` (décalage posé en style en ligne, donc hors safelist), le plus récent en tête de pile.

**Schéma des données** : `store.js` porte `_version` ; toute modification de forme (nouveau champ, nouvelle collection) doit l'incrémenter, sinon les postes conservent l'ancien jeu en `localStorage`. **LE NUMÉRO VIT DANS LA CONSTANTE `VERSION`, ET NULLE PART AILLEURS** (03/10/2026) : trois endroits le lisent — la semence, la garde du navigateur et la **garde du serveur** —, et tant qu'il était recopié dans chacun il finissait par diverger. C'est arrivé : la vague 67 a porté les deux premiers à 62 et laissé le troisième à 61, si bien qu'un poste hydraté **depuis PostgreSQL** ne se ré-amorçait jamais et faisait tourner du code de la version 62 sur des données de la 61 — exactement ce que `_version` existe pour empêcher. Mesuré sur la base réelle avant correction (`_version = 61` y subsistait), puis vérifié après (ré-amorçage déclenché, base passée en 62). N'incrémenter que `VERSION`. Version courante : **62** — vague 67 du 24/09/2026 : l’ASSISTANT DE DIRECTION perd le laboratoire (M5 : demandes d’analyses et RÉSULTATS, données de santé nominatives qu’aucune de ses trente activités ne demande — RG-13) et passe de TOUT à VOIR sur M12 (écrire et annuler des écritures comptables appartient au Comptable). Les fiches RBAC sont SEMÉES : sans incrément, un poste garderait l’ancienne matrice. Version **61** — vague 64 du 22/09/2026 : les OBJECTIFS DU PILOTAGE (`objectifsPilotage`, semés au socle — le BFR, la grille objectif/réel et le moteur d’alertes les lisent) et l’AMORÇAGE DES ACHATS remonté au socle (`besoins`, `commandes`, `livraisons`, `facturesFournisseurs` : semés par leurs écrans, la dette fournisseur valait zéro sur tout poste n’ayant jamais ouvert M7, et le BFR s’en trouvait surestimé). Version **60** — vague 63 du 21/09/2026, second temps : « **Amnios** » remplace « anamnios » dans l'abondance du liquide amniotique (arbitrage de l'échographiste) — les OPTIONS d'une variable vivent au magasin comme la variable. Version **59** — vague 63 du 21/09/2026 : le RYTHME CARDIAQUE du 1er trimestre revient au catalogue des variables d'imagerie, DÉPLACÉ après le LCC (et après la biométrie sur l'examen évolué) au lieu d'être supprimé — les variables vivant au magasin, un poste amorcé en 58 aurait gardé le jeu sans ce champ. Version **58** — vague 62 du 14/09/2026 : dossier de consultation structuré (`examensPhysiques` IPPOA), transferts, imagerie, constantes et externes peuplés, champs nuls non écrits. Version **57** — vague 61 du 14/09/2026 : l'imagerie à CINQ modalités (examens et variables de radiographie, mammographie, scanner et IRM semés au socle, `examensImagerie` porte `modalite`). Version **56** — vague 57 du 08/09/2026 : le DOSSIER OBSTÉTRICAL (collection `dossiersObstetricaux` — le cahier de la parturiente, semé au socle et lu par le tableau de bord de la maternité), la maternité PEUPLÉE sur le formulaire national rempli (grille CPN de 40 lignes par visite, délivrance/placenta/issue, fiche de surveillance intégrée mère-bébé, Apgar élément par élément, éléments H4→H24, partogramme coté chevauchement/descente/contractions) et l'HISTORIQUE DE COUVERTURE (`couverturesAssurance` : un assuré change de compagnie, la facture d'hier garde la sienne). Version **55** — vague 56 du 07/09/2026 : le jeu d'ÉCRITURES respecte enfin RG-10 (une pièce = deux lignes de même numéro, date, statut et montant ; l'équilibre est CONSTRUIT, plus contrôlé après coup). Version **54** — vague 55 du 06/09/2026 : les SIX SECTEURS deviennent le vocabulaire unique (groupes de prestation ET centres de coûts — Laboratoire, Pharmacie, Consultation, Échographie, Maternité, Hospitalisation et soins, plus la Direction transverse) ; la collection `centresCouts` change de forme, son `code` EST désormais l'imputation portée par les écritures. Version **53** — vague 54 du 05/09/2026 : les BADGES du personnel (`badges`, `modelesBadge` — un badge se RETIRE, il ne se supprime pas ; le QR ne porte que matricule et n° de série) et le PARTAGE d'une fiche d'enquête (`jetonsEnquete` : un jeton daté et révocable, jamais un identifiant d'enquête dans l'adresse). Version **52** — vague 53 du 02/09/2026 : les cinq fiches RBAC qui manquaient (dm, direction, comptable, agentadmin, ambulancier — un rôle sans fiche avait tous les droits), fermetures caissier (stock-gros lecture comprise, dashboard stock, dépenses), M1 fermé au MODULE pour le magasinier, `m7-livraisons` fermé au biologiste. Version **51** — vague 51 du 02/09/2026 : validations écrites des professionnels (`valideLe`/`validePar` sur variables labo et pathologies — la semence garde son marquage), seuils confirmés, et la « journée des postes » du peuplement (`gestesDePoste` : brouillons validés, résultats rendus, files résiduelles). Version **50** — vague 49 du 01/09/2026 : les validations du ressort de la Direction sont levées — tarifs d'attente ARRÊTÉS (`tarifArreteLe`, la semence garde son marquage), valorisations et groupes confirmés, questionnaire validé ; les marquages des professionnels nommés restent. Version **49** — arbitrage du 01/09/2026 « plus aucun montant nul » : GY-SAA au tarif d'attente aligné AMIU, les 34 références SAGE non valorisées à la médiane de leur catégorie (`valorisationProvisoire`, surcouche `valorisationsSage` semée au socle). Version **48** — phase 10 du 01/09/2026 : les collections `enquetes` (modèles de questionnaires — le formulaire naît du modèle) et `reponsesEnquetes`. Version **47** — phase 8 du 01/09/2026 : l'imagerie éclatée — `demandesImagerie` (états du labo : demandée → payée → exécutée → validée), `clichesImagerie` (galerie), `examensImagerie` et `variablesImagerie` au socle (administrables par `cfg-imagerie-catalogue`), la ligne payable porte `demandeImagerieId`. Version **46** — phase 7 du 01/09/2026 : collections `cpa` (consultation pré-anesthésique) et `crAnesthesie` (compte rendu d'anesthésie), et la demande d'analyse peut porter l'origine `'service'` (fiche `m3-demande-examen`). Version **45** — phase 6 du 01/09/2026 : le code d'analyse unique `NNNNN-AAAA` sur les demandes (fabrique unique `PR.codeAnalyse`, série annuelle) et la collection `plagesReactif` (bornes par lot de réactif, versionnées par date d'entrée en service). Version **44** — phase 5 du 01/09/2026 : collection `avoirs` (une seule, lue par la vue caisse ET le registre MECeF — référence, lignes annulées, contre-passation), collection `pvReceptions` (M7, deux natures), la dépense porte des **LIGNES** dont le total est la somme (arbitrage), `M8.annuler` fermé au caissier sur la fiche RBAC12 et surcharge d'écran `m8-facture-avoir` en lecture. Versions **41–43** — phases 3 et 4 : alias de manifeste, fusion RDV & visites, dossiers étendus à zones, puis les sept collections maternité (`grossesses`, `cpon`, `planificationFamiliale`, `registreSONU`, `ptme`, `soinsCuratifsMaternite`, `partogrammes`) et `naissances` enrichies. Version **40** — phase 2 du 31/08/2026 : trois rôles au manifeste et en fiches RBAC17-19 — **`chirurgien`** (base médecin + bloc, M4 fermé nommément, D interdit ; titulaire réel : Dr BASSONGUI, NS 145 secteur CHI), **`anesthesiste`** (péri-opératoire : M3 écriture, M1/M5 lecture, constantes en saisie ; CPA/feuille d'anesthésie en phase 6), **`aide_comptable`** (« Assistant Comptable », 16ᵉ rôle de l'arbitrage — identifiant technique distinct d'`assistant_comptable` qui RESTE l'Assistant de Direction, doctrine « laborantin » : on ne renomme pas un identifiant technique ; saisie M12/M7/M9 sans annulation, `m12-cloture` fermé nommément, aucun accès clinique) ; **fermetures caissier** `m6-transferts`/`m6-mouvements`/`m6-lots` (voir: false — matrice cible ; `M8.annuler` reste ouvert TANT QUE la facture d'avoir n'existe pas, à fermer en phase 5) ; trois tableaux de bord (`dash-chirurgien`, `dash-anesthesiste`, `dash-aide-comptable`) et sélecteur de connexion sans répétition du rôle (Bug 0). Versions : **39** — phase 1 du 31/08/2026 : catalogue des `actes` amorcé au socle (`store.seed()`, lu par consultation/hospitalisation/facturation/recherche/moteur — `D.ACTES` n'est que la semence), `reunions` et `documents` (GED) semées par `data-seed.js` avec `courriers` et `ambulance` aux **formes canoniques des écrans** (`traitement` tri-état ; `dateHeure`/`kilometrage`/`tarif`/`facture`/`etat`), `enteteVariantes` et `rccmFacturation` **retirés** (arbitrage IFU/RCCM), persistance **différée** (une écriture 300 ms après le dernier geste, tampon vidé sur `pagehide` — sérialiser le magasin à chaque insertion était quadratique) avec **compression lz-string en soupape** (`vendor/lz-string.min.js`, préfixe `U+0002` : mesurée à ~2,4 s sur 4 Mo, elle ne s'active QUE lorsqu'une écriture est refusée par le quota, et l'annonce ; `U.alerter` signale toute écriture perdue). Versions antérieures : **38** (ajouts successifs : `catalogueTarifs`, `enteteVariantes`, `typesPiece`, `pieces`, `soignants`, `prescriptions`, `administrations`, `crOperatoires`, `checklistsBloc`, `crMaternite`, `constantes`, `references`, `contreReferences`, `fichesPoste`, `facturesMere`, `materiel`, `valorisationsSage` ; la ligne de facture porte `montantBrut`, `remise`, `motifRemise`, `prixUnitaireNet` et `partPersonnel` ; `regimesTravail`, `grillePrimes` et `historiquePrimes`, `evenements` et `participations`, `rbac` et `tentativesConnexion`, `echeancesFiscales`, `examensLabo` / `unitesLabo` / `variablesLabo`, `modulesActifs`, `pathologies`, `notifications`, `emplacements`, `baremeNS131` et `historiqueBareme` ; le patient peut porter `personnelId`, qui vaut prise en charge à 100 %).

**UNE COMMANDE D’ÉCRITURE SE DÉCLARE COMME TELLE (vague 37).** `crud`, `creer` et `actionsLigne`
consultaient les droits ; les écrans construits **à la main**, non — et l’audit en a relevé
**trente-quatre**. Un assistant de direction se voyait offrir « Nouvelle commande » et « Valider (DA) »,
une aide-soignante « Nouvelle ordonnance », **le technicien d’échographie « Enregistrer et prescrire »**
— pour lui, ce n’est pas une habilitation trop large, c’est un exercice illégal, et la Direction l’avait
précisément fermé dans la matrice ; l’écran ne la consultait pas. L’accueil, lui, se voyait offrir
« Nouveau relevé » sur la feuille de température (RG-13).

`K.commande()` / `K.commandeIcone()` remplacent `K.btn` / `K.iconBtn` sur ces commandes. **On ne devine
pas une écriture à partir du libellé** : une protection qui dépend d’un mot change de sens le jour où
quelqu’un renomme un bouton. C’est l’AUTEUR qui la déclare. La commande refusée est **absente**, comme
pour le barème NS 131 — un bouton grisé invite à chercher pourquoi. `C.append` ignorant les `null`, elle
reste en place dans un tableau d’actions ; mais `C.append` attend un **nœud**, pas un tableau : pour
empiler dans une liste, il faut tester soi-même.

**LES DROITS DE L’ÉCRAN, PAS CEUX D’UN AUTRE MODULE.** La salle de soins interrogeait `K.droits('M3')`
alors qu’elle est un écran de **M2** : l’aide-soignante, qui a M3 en écriture et M2 en lecture, pouvait
administrer. `K.droits()` sans argument résout le module de l’écran courant — c’est la forme sûre.

**LE MODULE DES TABLEAUX DE BORD NE SE DÉCLARE JAMAIS AU NIVEAU DU MODULE.** DASH porte `roles: ALL` et
ce sont les listes de CHAQUE écran qui filtrent. Les deux façons de le déclarer sont fautives et
symétriques : `DASH: VOIR` **accorde les vingt tableaux** — l’aide-soignante lisait ceux de la
comptabilité et des RH, l’échographiste ceux de la caisse et de la comptabilité, alors qu’« aucun accès
financier » est la condition posée par la Direction pour ce poste ; `DASH` fermé retirerait au rôle sa
propre page d’accueil. `fermerTout()` l’omet donc. Mesuré : aide-soignante 66 → 47 écrans, échographiste
48 → 29, surveillant 91 → 73, assistant de direction 108 → 91. La **création** d’un rôle en exploitation
est un autre cas : là, tout est fermé DASH compris, un rôle inventé n’ayant pas de tableau à lui.

**LE TOTAL D’UN ÉTAT, SUITE — 21 pieds de tableau étaient VIDES.** `P.tableau` lit `o.total[c.key]` ;
douze appels transmettaient un objet dont les clés ne correspondaient à **aucune colonne porteuse de
`key`** — les colonnes de montants ne déclarent que `value`. Le pied cherchait `total[undefined]` et
n’imprimait rien, sur le **relevé** et la **facture mensuelle assureur**, la **balance générale**, les
**journaux comptables**, le **journal de paie**, l’état ORTB, le bon de commande, le bon de sortie,
l’ordonnance, le bulletin d’analyses. Le total n’était pas faux, il était **absent** — et un pied vide se
lit comme une mise en page. Tous convertis à `somme` sur la colonne.

**L’AUDIT RBAC NE SONDAIT QU’UN HUITIÈME DE LA SURFACE.** Il interrogeait `N.can` avec l’item brut du
manifeste, **qui ne porte ni `module` ni `roles` hérités** : sans le module, la surcharge est ignorée ;
sans les rôles du module, les écrans qui n’ont pas de liste propre étaient écartés. 117 sondages au lieu
de **902**. Même défaut que sur les cartes de hub et les accès rapides, une troisième fois. Et
**« Éditer » n’est pas une écriture** : sur les vingt-quatre libellés du prototype, tous impriment un
document — le verbe d’écriture ici est « Modifier ».

**UN SCÉNARIO QUI MUTE LA MATRICE DOIT LA RESTAURER — ET NE JAMAIS LA RECOPIER.** L’épreuve de fermeture
d’un module remplaçait la fiche du biologiste sans la remettre en place ; un bloc écrit plus tard pour
compenser **recopiait la fiche avec six réglages d’écran quand l’amorçage en porte treize**, si bien que
les cinq fermetures les plus récentes se rouvraient en silence et qu’une assertion trente scénarios plus
loin mesurait cette copie. Le scénario sauvegarde et restaure désormais l’objet réel. Corollaire déjà vu
deux fois : le compte de cartes de l’écran d’aide, écrit en dur à 19, est **dérivé du manifeste**.

**Écrans ajoutés, par vague** — chacun déclaré dans `nav.js`, jamais de lien écrit à la main :

| Vague | Écrans |
|---|---|
| 19–21 | `m10-stats-gardes`, `m10-evenements`, `m10-participations`, `m10-assurance-personnel` |
| 22 | `cfg-comptabilite`, `m12-echeances` |
| 30 | `m9-facture-mere`, `m13-repertoire-ambulances`, `m1-dossier-etendu`, `m1-reference`, `m1-contre-reference` |
| 31 | `dash-aide-soignant`, `dash-echographiste`, `dash-surveillant`, `dash-assistant-comptable`, `dash-biomedical`, `dash-croise`, `dash-da` |
| 32 | `m13-maintenance` (parc technique) |
| 37 | *(aucun écran ; le domaine **Pilotage** est scindé en deux rangées — `PIL` « Pilotage & analyse » et `DASH` « Tableaux de bord par poste ». Une rangée de vingt pastilles où « Direction » et « Statistiques de la Direction » se suivaient ne se lisait pas. `PIL` doit figurer dans `MODULE_FILES` de `gen-pages.js` et dans le test de `ecranModifiable()`.)* |
| 54 | `m10-badges`, `m10-badges-verification`, `m10-badges-modeles`, `m10-badges-impression`, et `enquete-publique` (hors ruban, sans coquille — la fiche d'enquête ouverte à un tiers) |
| 55 | *(aucun écran ; le ruban est RÉORGANISÉ — la rangée d'Accueil resserrée sur la réception, deux rangées `secondaire` dans SOINS : « Consultations & prescriptions » et « Imagerie médicale ». `m2-visites` rejoint les pages-renvoi hors ruban.)* |
| 57-59 | `m3-stats-hospitalisations` (Pilotage), `m12-ouverture` (bilan d'ouverture & à-nouveaux). `assets/js/data-liasse.js` transcrit la liasse déposée ; `m12-etats-financiers` en porte les cinq onglets. |
| 62 | `m2-dossiers-consultation` (avant la fiche de consultation, rangée « Consultations & prescriptions »). |
| 61 | `m12-flux-tresorerie` (feuillet 8/51), `m2-imagerie-radiographie`, `m2-imagerie-mammographie`, `m2-imagerie-scanner`, `m2-imagerie-irm` (fabrique commune, rangée « Imagerie médicale »). |
| 60 | `m4-dossier-obstetrical` (le cahier de la parturiente, en tête de la rangée M4) et `dash-maternite` (rangée « Tableaux de bord par poste »). |
| 64 | `m12-bfr` et `m12-cout-activite` (rangée `secondaire` « Contrôle de gestion & trésorerie », domaine Financier) et `m12-tableau-decisionnel` (Pilotage). |
| 65 | `m1-patient-nouveau`, `m4-dossier-obstetrical-nouveau` et `m6-inventaire-feuille` — trois PAGES de saisie hors ruban, sorties du gabarit `K.pageFormulaire`. `m1-certificats-externes` rejoint les pages-renvoi. |

### Les 14 modules (codification à respecter partout)

M1 Patients & DMI · M2 RDV/Visites/Consultations · M3 Hospitalisation · M4 Maternité/Naissances/Décès · M5 Laboratoire & Banque de sang · M6 Pharmacie & Stocks · M7 Achats & Fournisseurs · M8 Facturation/Caisse/MECeF · M9 Assurances & Créances · M10 RH · M11 Paie & Primes · M12 Comptabilité SYSCOHADA · M13 Administration & Ambulance · M14 Sécurité & Tableau de bord.

`draf1.txt` ajoute deux modules traités séparément : **MECeF** (facturation normalisée, centre de supervision fiscale propre) et **Rapports/Impression/États officiels**.

### Principe structurant : documents réels → configuration

Règle centrale de `draf1.txt` §1–2 : **ne rien coder en dur**. Les documents collectés sont les sources de vérité et deviennent des référentiels versionnés, avec traçabilité vers leur document d'origine.

**Tous les documents de `docs/` sont extraits et intégrés** (`assets/js/data.js`, `data-sage.js`, `data-compta.js`) : organigramme (44 agents), NS 131, NS 132, 48 analyses, 144 désignations de médicaments, inventaire SAGE (184 articles / 12 080 unités / 3 976 459 FCFA), plan comptable (93 comptes), compte de résultat 2025 (CA 190 830 994 FCFA), 13 assureurs, 7 régimes de planning, liasse SoBAPS (structure fiscale MECeF), entête officielle. Inventaire et comptabilité se réconcilient exactement avec leurs documents.

**Anomalies des sources, exposées dans l'application et non corrigées d'office** : colonnes de tarifs vierges (analyses et médicaments), 32 articles SAGE non valorisés, seuils d'alerte absents, 3 postes de dépense sans numéro de compte, écart de 141 667 FCFA sur la ligne TOTAL du classeur 2025, régime de TVA exonéré à confirmer, RCCM divergent entre documents.

**Point fiscal à ne pas « corriger » sans confirmation** : sur la facture certifiée MECeF de référence, la TVA vaut 0 (produits de santé exonérés) et le net à payer = HT + AIB 1 %. Le prototype applique ce régime, paramétrable dans `mecef-config`.

Correspondance document → rôle dans le logiciel :

- Organigramme → structure organisationnelle + RBAC
- NS 131/07/DM/DA/CNT/2026 → moteur d'évaluation & sanctions (4 axes : ponctualité/assiduité, exécution des tâches, attitude envers les patients, respect de la hiérarchie)
- NS 132/07/DM/DA/CNT/2026 → moteur des primes (permanence, garde, aide bloc, bloc fixe, hydrotubation, accouchement, caisse, urgence, incinération, accueil, circoncision — montants différenciés par fonction)
- Tarifs médicaments / 48 analyses labo → référentiels tarifaires versionnés (**un seul TARIF MASTER** consommé par pharmacie, facturation, assurance, compta)
- Inventaire SAGE « Grand Stock » → import de migration (jamais de saisie manuelle), avec `source`/`import_batch`/`validated_by`
- Bon d'expression de besoins → workflow natif, avec **quantité demandée ≠ quantité accordée** (distinction du process réel)
- Classeur SYSCOHADA → plan comptable + journaux ; compte de résultat 2025 → baseline de comparaison des dashboards
- Plannings → moteur de planning (garde 24h 08h→08h, permanence 08h–18h, repos 24h/48h, incompatibilités bloquées)
- 13 assureurs (Africaine des Assurances, NSIA, OLEA, Sanlam, Transvie, SUNU, Dayo, SOS, GAB, Becotra, Nobila, ASCOMA, ASK) → référentiel administrable
- Logo/entête/photos → Brand Configuration Center alimentant **tous** les états imprimables

Conserver une distinction explicite entre données importées du cadrage, données opérationnelles, et règles configurées par l'administrateur.

## Règles de gestion à ne jamais contourner

Ces invariants (CDCT §6, §9.4) traversent tous les modules :

- **RG-01** — Identifiant patient `CNT[n°]/[année]` (ex. `CNT530/25`), généré automatiquement, unique, non modifiable.
- **RG-02** — Médicaments facturés **au prix d'achat, sans marge**. Exception = validation Direction tracée.
- **RG-03** — Toute sortie de stock rattachée à un justificatif ; **le stock ne peut jamais devenir négatif**.
- **RG-04** — Commande de stock gros validée par la Directrice Administrative avant transmission fournisseur.
- **RG-05** — Rangement pharmacie en **FEFO** ; alertes de péremption automatiques et paramétrables.
- **RG-06/07/08** — Sortie d'hospitalisation : solde apuré + signature patient + signature infirmier + constat du gardien ; sortie contre avis médical motivée (avis du Procureur consigné si nécessaire).
- **RG-09** — Prise en charge assurance appliquée uniquement si la carte est valide à la date de facturation, sinon facturation intégrale au patient.
- **RG-10** — Toute écriture comptable équilibrée (débit = crédit) avant validation.
- **RG-11** — Primes de garde/permanence calculées depuis le planning validé et la grille en vigueur.
- **RG-12** — Journalisation systématique (utilisateur, date/heure, entité, ancienne/nouvelle valeur) ; **aucune action anonyme**.
- **RG-13** — Cloisonnement RBAC : médical réservé au soignant habilité, financier/RH aux profils comptables et RH.
- **RG-14** — **Suppression logique (archivage) uniquement**, jamais de suppression physique.

Autres invariants : un lit ne peut porter qu'une admission active ; CUMP calculé automatiquement sur consommables labo/médicaux ; cotisations part patronale 16,4 % / part ouvrière 3,6 %.

## Design system & standard UX

- **Couleurs** : bleu institutionnel (navy) pour entêtes et actions principales ; fonds blanc/gris clair ; sémantique vert (validé/disponible), orange (alerte), rouge (rupture/péremption/erreur).
- **Typographie** : Segoe UI / Inter, taille minimale équivalente 11 pt.
- **Navigation** : écran de connexion → dashboard personnalisé par profil ; navigation hiérarchique avec badges d'alerte ; topbar (recherche globale patient/produit/employé, plein écran, notifications, profil, déconnexion) ; fil d'Ariane ; actions rapides contextuelles. *`draf1.txt` demandait une sidebar verticale ; la clinique a demandé ensuite un méga-menu horizontal en ruban (16/08/2026) — c'est cette forme qui est implémentée.*
- **Gabarit de page standard** (à appliquer identiquement sur tous les modules, `draf1.txt` « Standard UX commun ») : header (titre, fil d'Ariane, actions) → bloc KPI → cards + graphiques → recherche et filtres avancés → tableau (tri, pagination, colonnes configurables, sélection multiple) → CRUD complet (créer/consulter/modifier/archiver/restaurer/dupliquer) → drawer de détail latéral → modales standardisées → timeline + journal d'audit + documents liés.
- **États à prévoir** : chargement, vide, erreur. **Mobile** : KPI en accordéons, tableaux en cartes, graphiques verticaux, bouton d'action flottant.
- **Dashboards distincts par profil** : Admin, Médecin, Patient, Pharmacien, Infirmier, Réceptionniste, Comptable — chacun avec sa page Profil détaillée.

## Impression et états officiels — exigence critique

L'impression des états n'est pas un accessoire : c'est une exigence majeure répétée dans tous les documents. Tout document édité (facture, bon, bulletin, ordonnance, résultat, rapport, état comptable) doit reprendre automatiquement l'entête officielle paramétrable :

Logo CNT · dénomination complète · BP 507, Natitingou · téléphones · e-mail · n° d'autorisation d'ouverture · **IFU 3201642748214** · **RCCM RB/NAT/2016-B-268**, avec pied de page (pagination, date/heure d'impression, utilisateur générateur, identifiant unique).

Chaque état doit être prévisualisable, imprimable, exportable (PDF/Excel), archivable, signable, et verrouillé après validation. Le catalogue complet figure au §21 du CDCT et dans la « Bibliothèque des États » de `draf1.txt`.

## Critère de réussite du prototype

Explicitement défini dans `draf1.txt` §24–25 : **ce n'est pas le nombre de pages, mais l'intégration transactionnelle inter-modules**. Un scénario complet doit pouvoir traverser plusieurs modules de bout en bout :

- Patient → consultation → prescription d'analyse → facturation → paiement → résultat → PDF archivé au dossier → écriture comptable
- Demande de stock → validation DA → quantité accordée → transfert Grand Stock → réception pharmacie → mouvement → CUMP/FEFO → historique
- Planning → présence → garde → prime → évaluation → calcul paie → retenues → bulletin PDF → écriture comptable

Exigences de qualité posées par l'utilisateur : sous-onglets fonctionnels, ajout/édition/suppression avec annulation, export PDF, **zéro erreur JS**, zéro lien cassé.

## Hors périmètre (CDCT §4.3)

Portail patient public et RDV en ligne · application mobile grand public · télémédecine/visioconsultation · IA d'aide au diagnostic · interfaçage automatisé avec les SI des assureurs · BI avancée · architecture Web/API ou cloud pour l'usage courant · migration rétroactive intégrale des 18 000 dossiers papier.

Ne pas proposer ces éléments comme fonctionnalités du système ; les écrans de type « télémédecine » présents dans `draft2.txt` proviennent du thème tiers et sont hors périmètre.
