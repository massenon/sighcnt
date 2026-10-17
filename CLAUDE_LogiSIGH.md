# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## État du dépôt

Trois ensembles : la documentation de cadrage (`docs/`, plus les notes d'exigences `draf1.txt` / `draft2.txt`), le prototype applicatif **`prototype_html/`** — 242 pages couvrant les 14 modules — et le site vitrine public **`frontend_html/`** — 25 pages engendrées depuis `build/site.js`.

**Langue de travail : le français.** Tout le contenu produit (UI, libellés, commentaires, documents) est en français. Les documents sources sont français ; `draft2.txt` contient une liste de menus en anglais issue d'un thème tiers (Medigo) — c'est une source d'inspiration, pas la nomenclature cible.

## Commandes (depuis `prototype_html/`)

```bash
npm install       # Tailwind CLI + Puppeteer
npm run build     # génère les pages, la safelist, puis compile Tailwind
npm run compta    # régénère data-compta.js depuis les classeurs Excel de docs/
npm run lint      # node --check sur toutes les sources JS
npm run check     # ouvre les 242 pages dans Chrome : erreurs JS, liens, ressources
npm run test      # 40 parcours fonctionnels de bout en bout (714 vérifications)
npm run audit-rbac # chaque écran sous chaque profil : commandes offertes vs droits réels
npm run inventaire-rbac # ce que chaque rôle voit RÉELLEMENT → newdocs/INVENTAIRE-RBAC.md
npm run verify    # lint + build + check + test
```

### Lire les documents de `docs/`

Les PDF sont des scans CamScanner **sans couche texte** — `pdftoppm` est absent
et l'extraction de texte ne donne rien. Les rendre en images via Chrome puis les
lire visuellement : `node build/_pdf2png.js "../docs/fichier.pdf" build/pdf-pages 2`.
Les classeurs Excel s'inspectent avec `node build/_xlsx.js "../docs/fichier.xlsx"`.

`check` et `test` pilotent le Chrome installé sur le poste (`CHROME_PATH` pour surcharger). Attendu : **0 erreur JS, 0 lien cassé, 40/40 scénarios**, et **0 promesse sur 902 sondages** à l’audit RBAC.

Pour ne contrôler qu'un sous-ensemble : `node build/check.js --pages=m6-,m8-`.
Captures d'écran : `node build/shot.js <page>.html 1600 sortie.png`.

### Trois pièges du build

1. **Régénérer la safelist avant de compiler la CSS.** L'interface est construite en JavaScript ; Tailwind ne voit pas ces classes. `build/gen-safelist.js` relit les sources JS et écrit `build/safelist.html`, seul fichier scanné avec les pages. Oublier cette étape produit une CSS incomplète et une mise en page cassée.
2. **`build/gen-safelist.js` retire les commentaires avant d'analyser.** Une apostrophe française isolée dans un commentaire désynchronise le balayage des chaînes et fait disparaître silencieusement toutes les classes suivantes.
3. **Ajouter un écran = modifier `assets/js/nav.js` puis `npm run pages`.** Le manifeste est la source unique des liens ; aucun href n'est écrit à la main, ce qui garantit l'absence de lien cassé.

## Site vitrine (`frontend_html/`)

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

## Architecture cible

Deux niveaux à ne pas confondre :

1. **Solution finale (CDCT §8.5)** : application desktop .NET (C#, WPF ou WinUI 3) + PostgreSQL sur serveur local, client-serveur 2-tiers en LAN. **Architecture Web/API, Laravel et cloud sont explicitement écartés** — la clinique exige un fonctionnement 24h/24 sans dépendance Internet.
2. **Livrable réalisé** : prototype HTML statique dans `prototype_html/`, tous assets **vendorés localement** (Tailwind compilé, police Inter, Chart.js, Lucide) — aucune requête réseau, même contrainte hors-ligne que la cible.

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
- **Deux RCCM** : `C.BRAND.rccm` sur l’en-tête administratif, `C.BRAND.rccmFacturation` sur les pièces
  de caisse. Les deux coexistent sur les documents réels ; ne pas corriger l’un par l’autre.

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

**L’IDENTITÉ DE L’ÉTABLISSEMENT N’EST PAS UN ENREGISTREMENT UNIQUE.** Les 37 pièces réelles portent
**trois IFU, trois RCCM et deux autorisations d’ouverture** selon la famille de document — les
certificats médico-légaux portent `RB/NAT/2021/M02-020`, le rapport médical porte l’IFU
`1201400032505` et une autorisation d’ouverture de 2008 que personne d’autre ne porte. La divergence
est **systématique, pas accidentelle** : le Brand Configuration Center porte donc un référentiel de
**variantes d’en-tête** (`enteteVariantes`), chaque état désignant la sienne. Les corriger d’office
produirait des pièces qui ne ressemblent plus à celles que la clinique délivre.

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
- **`K.miniTable(colonnes, lignes)` attend des colonnes OBJETS** (`{key, label, align, render}`) et
  des lignes objets. Deux tableaux de chaînes produisent un tableau aux en-têtes vides et aux cellules
  vides : rien à l’écran, rien dans la console.

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

**Schéma des données** : `store.js` porte `_version` ; toute modification de forme (nouveau champ, nouvelle collection) doit l'incrémenter, sinon les postes conservent l'ancien jeu en `localStorage`. Version courante : **38** (ajouts successifs : `catalogueTarifs`, `enteteVariantes`, `typesPiece`, `pieces`, `soignants`, `prescriptions`, `administrations`, `crOperatoires`, `checklistsBloc`, `crMaternite`, `constantes`, `references`, `contreReferences`, `fichesPoste`, `facturesMere`, `materiel`, `valorisationsSage` ; la ligne de facture porte `montantBrut`, `remise`, `motifRemise`, `prixUnitaireNet` et `partPersonnel` ; `regimesTravail`, `grillePrimes` et `historiquePrimes`, `evenements` et `participations`, `rbac` et `tentativesConnexion`, `echeancesFiscales`, `examensLabo` / `unitesLabo` / `variablesLabo`, `modulesActifs`, `pathologies`, `notifications`, `emplacements`, `baremeNS131` et `historiqueBareme` ; le patient peut porter `personnelId`, qui vaut prise en charge à 100 %).

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
