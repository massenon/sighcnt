# CLAUDE.md

Guide de travail pour Claude Code sur ce dépôt. **Version courte (13/11/2026)** : l'historique détaillé des vagues, des lots et des pièges payés est dans `docs/architecture/HISTORIQUE-CLAUDE-MD.md` (l'ancien `CLAUDE.md` complet, 313 Ko). Le chercher par mot-clé avant de toucher un sujet : `grep -n "lot IMP-E" docs/architecture/HISTORIQUE-CLAUDE-MD.md`. Ne pas le lire en entier.

## Projet

**SIGH-CNT** : système de gestion hospitalière de la CLINIQUE NASSIERA TOO SARL (Natitingou, Bénin), ~18 000 dossiers, ~30 agents. Langue de travail : le français (UI, libellés, commentaires, documents). Il remplace un parc cloisonné (stock, labo, comptabilité, dossiers, papier).

Monorepo npm (ADR-0002), **cible hors ligne d'abord** :
- `prototype_html/` : la **maquette**, exécutable de référence (305 pages PHP/JS, magasin PostgreSQL `sigh_prototype`, jamais `sigh_cnt`).
- `apps/poste` (Flutter desktop, modes fileul et mère), `apps/mobile` (Flutter, par le relais seul), `apps/web` (Laravel 12 sur cPanel : relais opaque + panneau superadmin), `packages/domaine` (règles en Dart, un seul exemplaire), `packages/sync` (banc), `packages/sync_dart` (moteur), `packages/rbac`, `packages/referentiels`, `packages/schema`.
- `frontend_html/` : site vitrine public. **Ne se supprime en aucun cas** (consigne du 25/09/2026). Il a son propre `CLAUDE.md`.
- `docs/` : cadrage, PRD, plans, ADR, `docs/decisions/DECISIONS-A-VALIDER.md` (réponses de la Direction, en cas de contradiction entre case et remarque, la remarque l'emporte), `docs/architecture/ECARTS-MAQUETTE.md` (chaque écart numéroté).

## Méthode (la doctrine qui a fait ses preuves)

1. **On extrait, on ne devine pas.** Ce qui n'a pas de source se dit (« proposition à valider »), jamais un tarif, un numéro d'urgence ou une borne inventés.
2. **Maquette d'abord** quand une forme de donnée ou un libellé change, puis les **vecteurs tirés de l'écran réel de la maquette piloté dans Chrome** (`prototype_html/build/vecteurs-*.js`), puis le domaine Dart, puis le poste, puis la synchronisation. Une règle sans vecteur n'est pas portée.
3. **Un refus se nomme** (code, motif, geste de correction). Une commande interdite est **ABSENTE**, jamais grisée. « Non calculable » n'est pas zéro. Le moteur refuse aussi : masquer un bouton ne protège rien.
4. **Une source, jamais deux.** Droits : `packages/rbac/data/rbac.json`. Navigation : `packages/referentiels/data/manifeste.json`. Couleurs : `docs/design/design-tokens.json`. Fichiers engendrés par `prototype_html/build/*.js` : on régénère, on n'édite pas. Une règle écrite en deux exemplaires diverge au premier correctif.
5. **Une pièce émise ne se réécrit jamais** ; une donnée de référence qui change alors que des pièces existent se **versionne par date**. Rien ne se supprime (RG-14) : on archive, annulable.
6. **Règle de paramétrage (Direction, 09/11/2026)** : tout ce qui est paramétrable (taux, dates, seuils, circuits, modes) est **enregistré en base** avec un **défaut semé**, jamais une constante du code, et se versionne par date. Les paramètres du poste se synchronisent vers le relais, qui les stocke chiffrés.
7. **Règle de rédaction (31/10/2026)** : pas de tiret cadratin (—), demi-cadratin (–) ni trait d'union comme ponctuation dans le code, les commentaires et les textes d'interface ; utiliser la virgule, les deux-points, les parenthèses ou le point. Les identifiants, intervalles et dates restent de la syntaxe. Aucun « SAGE » visible (la reprise s'appelle « Inventaire initial (reprise) »). Le bloc RG ci-dessous garde son format, `build/parite.js` l'extrait par motif.
8. **Le texte médical ne quitte jamais la clinique** : aucun service externe, aucune donnée de santé dans une requête, une alerte ou un son.
9. **La Direction tranche, le professionnel garde le sien** : les marquages « à valider » qui attendent un professionnel nommé (bornes du labo, pathologies, check-listes) restent jusqu'à sa validation écrite.
10. **Preuves** : chaque comportement a un test qui échoue sur l'arbre d'avant puis passe ; mutations rouges avec fichier restauré à l'identique (SHA-256) ; dire ce qui n'est PAS vérifié (Windows, SQLCipher, relais réel, deux machines, charge). Jamais de faux vert.
11. **Un scénario qui vide une collection ou change de rôle la RESTAURE ; une sonde se cherche par la référence d'une ligne, jamais par son rang ; une sonde isolée peut cacher une dépendance d'ordre** (rejouer derrière des scénarios voisins).

## Commandes

Depuis `prototype_html/` : `npm run lint`, `npm run build` (pages + safelist + Tailwind), `npm run check` (306 pages, 0 erreur JS, 0 lien cassé), `npm test` (~175 scénarios, ~60 min), `npm run audit-rbac` (0 promesse, 0 lecture non dite), `npm run serveur`. Une page ou un écran s'ajoute dans `assets/js/nav.js` puis `npm run pages` (le manifeste est la source des liens). Régénérer la safelist avant Tailwind ; `gen-safelist.js` retire les commentaires (une apostrophe isolée dans un commentaire fait disparaître des classes). `node_modules` de la maquette vient de Windows : compiler la CSS par `node node_modules/tailwindcss/lib/cli.js -i src/input.css -o assets/css/tailwind.css --minify`.

Cible : `cd packages/domaine && dart test` ; `cd packages/sync_dart && dart test` ; `cd apps/poste && flutter analyze && flutter test` (~17 min, lancer en `setsid nohup` dans un journal et attendre par une boucle `until grep`) ; `npm run banc:sync` (protocole, ~140 s), `npm run banc:cible` (mère, fileuls, mobile Dart contre le relais Laravel) ; `cd apps/web && php artisan test` ; `cd packages/rbac && node --test`. SDK Flutter : `export PATH=/tmp/flutter-dl/flutter/bin:$PATH` (réinstaller selon `.claude/skills/sigh-flutter` si absent). `service postgresql start` avant tout banc de la maquette ou du relais.

**Pièges des bancs.** Le serveur PHP d'un banc écoute sur `SIGH_PORT_PHP` (8099 par défaut), PAS sur `SIGH_PORT_TEST` ; la base se choisit par `SIGH_BASE_TEST`. Pour tout passage isolé : `SIGH_PORT_PHP=<port libre> SIGH_BASE_TEST=<base à soi> SIGH_PORT_TEST=<port libre> CHROME_PATH=/opt/pw-browsers/chromium SIGH_FICHIERS_DIR=<à soi> SIGH_SAUVEGARDES_DIR=<à soi> node build/test-fonctionnel.js --seul=<fragment|autre>`, et `ps aux | grep "[p]hp -S"` avant de croire un résultat. Jamais deux bancs à la fois. `rapport-tests.json` et `rapport-controle.json` sont réécrits par chaque banc : les restaurer par `git checkout --`, ne jamais les commiter. Disque serré (~4 Go) : nettoyer ses dossiers et bases temporaires. Le nombre de scénarios, de vérifications et de sondages RBAC qui fait foi est celui MESURÉ.

## Schéma de la maquette

`store.js` porte une constante `VERSION` (nulle part ailleurs : trois endroits la lisent). Toute modification de forme (nouveau champ, nouvelle collection, fiches RBAC semées) l'incrémente, sinon les postes gardent l'ancien jeu. Version courante : **86**. Une collection ajoutée au socle se mesure avant d'être semée (le quota et la taille du jeu comptent). Un référentiel lu par plusieurs modules s'amorce au socle ; un référentiel lu par un seul écran, par cet écran (chaque page ne charge que le module de son écran). Les champs nuls ne s'écrivent plus (`'champ' in record` ne voit pas un champ nul). Le repli `localStorage` n'existe plus : sans serveur, un dépôt est refusé en le nommant.

## Architecture de la maquette en dix lignes

Chaque page est un gabarit appelant `SIGH.mount('<id>')` ; `mount()` enregistre, `boot()` peint (un rendu qui échoue doit le DIRE). Ordre de chargement : `core`, `data`, `store`, `parcours`, `ui`, `charts`/`print`, `nav`, `app`, `modules/_kit.js`, module de l'écran. `nav.js` est le manifeste (écrans, droits d'origine, alias, rangées `secondaire`, écrans `universel`, `servant`, `N.IMPORTS`, `N.RUBRIQUES`). `K.crud`, `K.creer`, `K.actionsLigne`, `K.pageFormulaire`, `K.commande` (une écriture se déclare comme telle), `K.fileAttente`, `K.importer` sont les gabarits. `parcours.js` porte la chaîne transactionnelle (`PR.prescrire`, `PR.encaisser`, `PR.delivrer`, fabriques uniques : code patient, code d'analyse, dossier externe, badge, pièce de caisse). Les droits ont trois axes : rôle (écrans), fonction (capacités), secteur (périmètre) ; un rôle sans fiche RBAC a TOUS les droits, une surcharge accorde autant qu'elle restreint, un module `roles: ALL` ne se déclare jamais en surcharge. Navigation sans rechargement (`app.go`, `ecoute()` pour tout écouteur de `document`/`window`). Planificateur serveur `api/cron.php`, sondage des postes toutes les 3 s, projection relationnelle `api/projection.php`.

## Règles de gestion à ne jamais contourner

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

## Arbitrages de la Direction qui font foi (ne pas les re-questionner)

Identité imprimée UNIQUE (IFU 3201642748214, RCCM RB/NAT/2016-B-268, `C.BRAND`) ; 16 rôles dont l'Assistant Comptable (`aide_comptable`) et l'Assistant de Direction (`assistant_comptable`, identifiant technique conservé) ; ruban horizontal (pas de sidebar) ; la devise « Votre santé, notre raison de vivre » ; la grille de prix porte DEUX prix (non assuré, assuré) et RG-09 décide lequel ; le code patient est `CNT/[n°]/[année]` pour les dossiers à venir ; le MECeF est le BOÎTIER physique, certification locale à la caisse ; les six secteurs (Laboratoire, Pharmacie, Consultation, Imagerie médicale, Maternité, Hospitalisation et soins, plus la Direction transverse) ; le rôle Ingénieur biomédical est supprimé ; les Réponses du 13/11/2026 (`DECISIONS-A-VALIDER.md` section V) : seuils de variation « l'une ou l'autre », validation des seuils au Biologiste médical (droit RBAC réglable), correction OCR signée et journalisée, réglage OCR de clinique, deux destinations de sauvegarde, idempotence des imports (appliquée au lot IDEM : le même inventaire est le même lot, identité de CONTENU, la mère confirme une fois, un second fileul est adopté ; `grep -n "lot IDEM" docs/architecture/HISTORIQUE-CLAUDE-MD.md`). Lot B (13/11/2026, maquette) : valider un seuil de variation est un geste réservé de la fiche RBAC par RÔLE (`N.droitGeste`, `droitsGestes`, clé `gestes` de `rbac.json`), la diurèse est en mL et la tension en deux nombres (cmHg) partout, le seuil porte un délai entre deux mesures (vide par défaut, « non évalué » dit, jamais bloquant) ; le poste Flutter ne l'a pas encore (`grep -n "Seuils du laboratoire, constantes" docs/architecture/HISTORIQUE-CLAUDE-MD.md`, `DECISIONS-A-VALIDER.md` section X). Lot C (14/11/2026) : la correction manuelle du texte lu par OCR est une version SIGNÉE de `lecturesOcr` (jamais une réécriture, une relance machine ne la détruit pas), droit = geste réservé `corriger_texte_ocr`, et le réglage OCR est de CLINIQUE (paramètres `ocr.*` posés à la mère, jamais vers un téléphone) ; `grep -n "Correction signée du texte lu" docs/architecture/HISTORIQUE-CLAUDE-MD.md`, `DECISIONS-A-VALIDER.md` section Y. Les cinq arbitrages de la matrice du 25/09/2026 et les décisions de chaque vague sont dans l'historique.

## Hors périmètre (CDCT §4.3)

Portail patient public et RDV en ligne, application mobile grand public, télémédecine, IA d'aide au diagnostic, interfaçage automatisé avec les SI des assureurs, BI avancée, architecture Web/API ou cloud pour l'usage courant, migration rétroactive des 18 000 dossiers papier. Ne pas proposer ces éléments comme fonctionnalités.

## Impression et états officiels

Tout document édité (facture, bon, bulletin, ordonnance, résultat, état) reprend l'en-tête officiel paramétrable (logo, dénomination, BP 507 Natitingou, téléphones, e-mail, autorisation, IFU, RCCM) avec pied normalisé (pagination, date, utilisateur, identifiant). Trois gabarits : A4, rouleau 80 mm (caisse), carte CR80 (badge, sans IFU ni RCCM). Un total d'état est CALCULÉ (`somme` sur la colonne), jamais fourni.

## Où lire ensuite

`docs/architecture/HISTORIQUE-CLAUDE-MD.md` (tout ce qui a été décidé, vague par vague : à chercher par mot-clé), `docs/architecture/ARCHITECTURE-CIBLE.md` et `adr/`, `docs/specs/SPEC-protocole-synchronisation.md`, `docs/architecture/PARITE-MAQUETTE.md`, `docs/decisions/DECISIONS-A-VALIDER.md`, `docs/architecture/ECARTS-MAQUETTE.md`, `docs/plans/`, `docs/guides/GUIDE-DEMARRAGE.md`. Skills du dépôt : `.claude/skills/` (`sigh-maitre`, `sigh-flutter`, `sigh-sync`, `sigh-laravel`, `test-plan`, `spec`, `plan`, `prd`, `adr`, `review`, `release`). Documents de cadrage : `docs/Cahier_des_Charges_Technique_*.md` (référence contractuelle M1 à M14, RG, EF, UC), `docs/Rapport_de_Cadrage_*.md`, `draf1.txt`, `draft2.txt`. Les PDF de `docs/` sont des scans sans couche texte : les rendre en images (`node build/_pdf2png.js`).

**Jamais versionnés** : `node_modules`, `vendor/`, `*.local.php`, `.env`, exports `*.sql`. Le mot de passe PostgreSQL commis le 17/10/2026 dans `prototype_html/api/config.local.php` est à changer sur le poste (il reste dans l'historique du commit initial).
