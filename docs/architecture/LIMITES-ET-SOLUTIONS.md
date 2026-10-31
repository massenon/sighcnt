# Inventaire des limites du portage Flutter — et solutions proposées (à valider)

Établi le 31/10/2026 sur l'état du dépôt : **228 écrans déclarés portés sur 321** (N1 = 100 % mesuré), 4 lots en cours (CFG-b, DASH a/b, PIL).
Source : rapports des agents de portage, `docs/architecture/ECARTS-MAQUETTE.md` (E1 → E1039), échanges avec la Direction.

**Lecture.** Chaque limite porte : *ce qui est vrai aujourd'hui* · *l'avis d'expert* (comptable, DAF, stock, digitalisation hospitalière, génie logiciel,
architecture/BDD) · *la solution proposée* · *la décision demandée* (**V** = à valider par la Direction, **T** = technique, je décide si vous ne dites rien) ·
*l'effort* (S = < 1 j, M = 1-3 j, L = > 3 j).
Règle conservée : on ne corrige **jamais d'office** une règle de gestion — on propose, vous validez, la maquette est corrigée **d'abord**, puis le poste.

**Déjà tranché par la Direction (31/10/2026)** — appliqué, à ne plus rediscuter :
- L'**accueil tient le répertoire des ambulances** (créer, vérifier, changer la disponibilité) : écriture accordée sur `m13-repertoire-ambulances` seulement (le reste de M13 reste fermé à l'accueil). `VERSION` 67.
- Nettoyage des dossiers temporaires `/tmp` autorisé.

---

## A. Identité, droits, sécurité (architecture + DAF)

| # | Limite | Avis d'expert | Solution proposée | Décision / effort |
|---|---|---|---|---|
| A1 | **La coque ne porte que le RÔLE**, pas de personne : le « demandeur ≠ validateur » de la clôture se vérifie sur le libellé du rôle (deux comptables sont indiscernables) ; `validePar` / `acteur` = libellé du rôle (E800, E687, E625) ; fonction/secteur/agent absents (E170, E375) ; la continuité du prélèvement bloque tant que l'agent n'est pas connu. | Séparation des tâches (SOX-like) impossible sans identité nominative. C'est le **défaut structurant n° 1** : RG-12 « aucune action anonyme » n'est tenue qu'au niveau du poste. | Introduire une **`Session` nominative** dans la coque : `{utilisateurId, matricule, nom, role, fonction, secteur}`, issue du compte `utilisateurs` (m14) à la connexion. Toutes les écritures et le journal RG-12 y lisent l'acteur. Les écrans reçoivent `ContexteEcran.agent`. | **V** (structure) · L — débloque A2, A3, B1, D2, D3 |
| A2 | **Séparation des tâches de la paie** (E692) : le comptable génère ET valide les bulletins ; `m11-validation` lui est en écriture. | Le DAF doit pouvoir *saisir*, la Direction *signer* : jamais la même personne. | Retirer `m11-validation` en écriture au comptable (fiche RBAC21→comptable : voir seulement) ; la Direction/DAF valide ; contrôle moteur « validateur ≠ générateur » (grâce à A1). | **V** · S (+A1) |
| A3 | **RG-04 contournable** (E72) : « Valider (DA) » est offert à tout rédacteur M7 ; le validateur écrit est toujours `TAKI Alimatou`. | Contrôle interne des achats : seul le DAF (ou son intérim désigné) valide une commande gros. | Gate « Valider (DA) » sur le droit DAF ; `validePar` = acteur réel (A1) ; intérim = désignation datée (comme l'intérim biologiste). | **V** · S (+A1) |
| A4 | **`rbac.json` ne relit pas les surcharges saisies dans `m14-roles`** (E596) ; la **fermeture d'une activité** retire l'écran de la matrice pour tous les rôles, admin compris (E203 : banque de sang/donneurs inaccessibles) ; l'onglet « Poste → rôle → accès » ignore aussi ces surcharges. | La matrice est *engendrée* et statique ; la maquette la fait évoluer à chaud (collection `rbac`, `modulesActifs`). Deux vérités. | `MatriceDroits` charge **base engendrée + surcharges (`rbac`, `modulesActifs`)** à l'exécution, comme `N.can()` de la maquette ; réouverture/fermeture d'activité = fiches datées, jamais suppression (RG-14). Banque de sang : écran *présent mais fermé* (message « activité non pratiquée »), réouvrable. | **V** (principe) · M |
| A5 | **Mots de passe** : le poste n'ouvre aucune session par compte ; `tentativesConnexion` jamais écrite ; m14 ne conserve que date/auteur/obligation de changer (correct). | Aujourd'hui aucune authentification réelle : acceptable en maquette, **bloquant avant mise en service**. | Authentification locale hachée (Argon2id, sel par compte) stockée chiffrée dans la base poste ; verrou 15 min (CDCT §12.2) ; journal des échecs ; double facteur optionnel. Lié à A1. | **V** · L |
| A6 | **Écran sans coquille** : la coque enveloppe tout écran dans barre + ruban ; `enquete-publique`, `auth-*`, `error-*` ne peuvent pas être servis (ces 8+1 écrans sont bloqués). | Page publique = surface d'attaque : elle ne doit **rien** partager avec la coque. | Ajouter une **route plein écran sans chrome** (déjà prototypée par `ouvrirPagePublique`) et l'utiliser pour `auth-*`, `error-*`, `enquete-publique`. | **T** · S-M |

## B. Comptabilité & paie (expert-comptable, DAF)

| # | Limite | Avis d'expert | Solution proposée | Décision / effort |
|---|---|---|---|---|
| B1 | **Exercice** : sélecteur de la coque non porté (l'exercice = année de l'horloge) ; M9, MECeF, états ne suivent pas l'exercice ; la **garde de lecture seule** ne protège que les écrans M12 et `ecritures` (pas l'encaissement). | Un exercice clos doit être **immuable partout** (OHADA/SYSCOHADA : intangibilité des écritures validées). Une garde au niveau écran est insuffisante. | Garde **au niveau `Magasin`** (déjà amorcée : `CollectionMagasin.garder`) étendue à toute collection comptable (`ecritures`, `avoirs`, `factures`, `paiements`) ; **sélecteur d'exercice dans la coque** (mémorisé) ; M9/MECeF filtrent par exercice **sauf créances** (un encours reste dû). | **V** · M-L |
| B2 | **Identité du demandeur de clôture** : voir A1. | — | Résolu par A1. | — |
| B3 | **GED / archive de clôture** et **export CSV de l'exercice** non portés ; empreinte SHA-256 portée. | Obligation de conservation 10 ans (OHADA) : l'archive doit exister **avec** la clôture. | À la validation de clôture : générer balance CSV + PV + empreinte, déposer en GED (`documents`, conservation 10 ans, une par exercice) — comme la maquette. | **T** · M |
| B4 | **Doublon de la liasse** déposée : `cpb_liasse` et `cpc_liasse`. | Deux copies = deux vérités ; la liasse DÉPOSÉE est un fait. | Garder `cpb_liasse` (source unique, engendrée), faire importer `cpc_*` depuis elle, supprimer `cpc_liasse`/script jumeau ; test d'égalité avant suppression. | **T** · S |
| B5 | **Règlement d'une facture mère remplace le précédent** (E501) : 1 000 puis 29 140 sur 30 140 ne soldent pas. | Erreur de gestion des créances : un règlement partiel doit **s'additionner** (lettrage). | Règlements **cumulatifs datés** (lignes de règlement) ; solde = facture − Σ règlements ; statut soldée à 0 ; écriture 411/512 par règlement. Corrigé **maquette d'abord**. | **V** · M |
| B6 | **Aucune écriture comptable de paie** (E693) ; statut « Diffusé » jamais atteint ; heures sup. validées et prêts-études **non lus** par le calcul (E689, E691) ; participations non retenues (E690/E742). | Paie non comptabilisée = comptabilité fausse (641/42/43/44). Retenues d'avances/prêts/participations non prélevées = perte pour la clinique. | (1) Écriture de paie **en brouillon** à la validation du lot (débit 661/664, crédit 421/431/447…, RG-10 contrôlé) ; (2) le calcul lit heures sup validées, échéances de prêt du mois, participations imputées du mois (une seule retenue, au mois de retenue) ; (3) corriger la forme des participations au semis (`employeId`/`statutPaiement`) puis régénérer ; (4) commande « Diffuser » après validation. Maquette d'abord. | **V** · L |
| B7 | **Barème NS 131 « administrable » n'atteint aucune évaluation** (E650) ; **prime retirée encore versée** (E651) ; **primes fixes à tous les agents de la fonction** (E654) ; **prime d'ancienneté hors assiette** (E652). | Risque social et fiscal : prélèvements/primes calculés sur des règles que l'écran dit modifiées. | Les évaluations lisent le barème **en vigueur à leur date** (versionné) ; prime retirée = date de fin (la paie ne la lit plus après) ; primes fixes **désignent leurs bénéficiaires** (liste datée) ; ancienneté intégrée à l'assiette *si* la Direction le confirme. | **V** · M-L |
| B8 | **Balance compte les brouillons** alors que le bandeau dit « validées » (E718) ; journal `BQE` inexistant (E719) ; **deux comptes de résultat** 130000 vs 131/139 (E813) ; **doublons du plan** 244100/631810 (E724/E725) ; plan statique fait foi sur les comptes créés (E715) ; millésimes `2026` en dur (E6, E538, E777, E686…). | Intégrité du plan comptable et des numérotations — base de tout contrôle. | Balance : filtre explicite *validées / toutes* (défaut validées) ; ajouter le journal BQE au référentiel ; **un seul** compte de résultat (131/139 à la clôture, 130 réservé aux reports manuels signalés) ; unicité du numéro de compte à la création ; millésime = année de la pièce (série annuelle par préfixe). Maquette d'abord. | **V** · M |
| B9 | **Écarts internes du dépôt DGI conservés** (Variation du BF N/N-1, ZB N, CAFG N-1, trésorerie 450 F). | Ce sont des erreurs du document **déposé** ; on ne peut pas les « corriger » sans déclaration rectificative. | Conserver et afficher ; proposer à l'expert-comptable de la clinique une **liasse rectificative** si l'écart est jugé matériel. | **V** (comptable externe) |
| B10 | **Trois canaux d'avoir** (E12/E15), **remboursement à 0 FCFA accepté** (E10), « IFU client » imprime l'IFU de la clinique (E14), pièce sans lignes (E2), date/instant (E4). | Une pièce émise ne se réécrit jamais ; **un seul** mécanisme de correction doit exister. | Canal unique : la collection `avoirs` (`m8-facture-avoir`) ; l'écran de facturation et MECeF **appellent** ce moteur ; plafond cumulé partout ; remboursement ≥ 1 FCFA ; IFU client = celui du client (vide si inconnu, jamais celui de la clinique). | **V** · M |
| B11 | **Échéance GED à 365 j/an** (E565, bissextiles) ; **pas de pied de total** sur deux tableaux de facture mère (E512). | Détails de conformité. | Échéance par calcul de dates calendaires ; `somme` au kit pour les tableaux d'écran. | **T** · S |

## C. Stock, pharmacie, achats (gestionnaire de stock)

| # | Limite | Avis d'expert | Solution proposée | Décision / effort |
|---|---|---|---|---|
| C1 | **Stock total vs stock de détail** (E45) : la dispensation compte le total, `PR.delivrer` le détail. | RG-03 (jamais négatif) n'est garanti que si **une seule** quantité fait foi par magasin. | Un **stock par emplacement/magasin** (gros, détail, labo) ; le « total » est *dérivé* (Σ) ; toute sortie cible un magasin nommé. | **V** · M |
| C2 | **Tarifs d'imagerie** : 16 « tarifs d'attente » (proposition) et examens sans tarif refusés en les nommant ; valorisation **par défaut = prix de vente** (E808). | Valorisation CUMP vs prix de vente = choix de gestion (impacte marge/stock). RG-02 : pas de marge. | Faire valider les 16 tarifs par la Direction ; méthode de valorisation **fiche datée** (versionnée, pas d'écrasement) avec défaut CUMP si la Direction préfère. | **V** · S |
| C3 | **« 6 000 assuré » du pansement** annoncé mais non appliqué hors garantie (E414). | Un tarif conventionné doit s'appliquer **par la grille**, jamais par une annonce. | Vérifier la grille NSIA/… : appliquer le tarif assuré *par la garantie* ou retirer l'annonce. | **V** · S |
| C4 | **Séances en attente de règlement** compte des bons, pas des séances (E413). | Indicateur de trésorerie faussé. | Compter les lignes payables restantes. | **T** · S |

## D. Clinique & digitalisation hospitalière

| # | Limite | Avis d'expert | Solution proposée | Décision / effort |
|---|---|---|---|---|
| D1 | **Secteur de session absent** : `secteurDemandeur` vide, une sage-femme ne voit aucun résultat/CR (E343, E170) ; fonction déduite du rôle. | RG-13 : le cloisonnement par secteur est une exigence métier. | Via A1 : la session porte fonction + secteur du **dossier RH** ; le prescripteur renseigne `secteurDemandeur`. | **T** (+A1) · S |
| D2 | **Prescription directe sans dossier ni fiche** (`m2-ordonnance-nouvelle`, E344). | Traçabilité médico-légale : toute ordonnance doit s'adosser à une consultation. | Exiger un dossier enregistré (même circuit que la fiche) ; ordonnance « ré-édition » seulement depuis une consultation existante. | **V** · S |
| D3 | **Sortie d'hospitalisation « contre avis médical »** ne déclenche pas RG-08 (E416) ; **décharge « impérative » non exigée** (E427). | Médico-légal. | L'état « contre avis médical » ouvre la procédure RG-08 (motif, référence du Procureur si requis) ; décharge exigée. | **V** · S |
| D4 | **Compte rendu d'imagerie** : saisie de variables non portée dans les écrans de demande/poste/galerie (renvois) ; **qui réalise radio/scanner/IRM reste à arbitrer** ; **pas de DICOM/PACS**. | Une clinique de 30 agents : DICOM hors périmètre ; le CR + clichés joints suffit. | Confirmer : option A (demande + CR + clichés joints) ; désigner le réalisateur par modalité. | **V** · — |
| D5 | **Sélecteur de fichier natif absent** (clichés, documents, ressources graphiques, photo badge, justificatifs) : on saisit un chemin. | Ergonomie inacceptable en production. | `file_selector` (desktop) : lecture du fichier, contrôle taille/type, stockage chiffré. | **T** · S-M |
| D6 | **Champ date-heure** (déjà ajouté au kit) et **sélecteurs de date en anglais** (OK/Cancel) : `flutter_localizations` absent. | Interface 100 % française. | Ajouter `flutter_localizations` + `locale fr` dans l'application et dans les tests. | **T** · S |
| D7 | **Lien `tel:` inerte**, **alerte sonore remplacée par un message**, **détail par option des listes** non rendu. | Confort et sécurité (alertes critiques). | `url_launcher` (Windows/Linux) ; alerte sonore via un petit service audio (canal, jamais logique métier — doctrine vague 36) ; `OptionChamp.detail`. | **T** · S-M |
| D8 | **Impression** : jamais essayée sur imprimante réelle (A4, ticket 80 mm, **cartes CR80**) ; PDF badge généré ; N3 (comparaison visuelle) jamais faite. | Le papier est le livrable légal. | Banc d'impression : golden PDF → image, 3 formats ; un test sur matériel au moment de la finalisation (vous fournirez le matériel). | **V** (calendrier) · M |
| D9 | **MECeF : boîtier physique non intégré** (protocole absent du dépôt) ; la simulation est portée. | Obligation fiscale béninoise. | Dix questions au fournisseur/DGI déjà posées dans l'ADR ; implémenter l'adaptateur à la caisse dès réception du protocole. | **V** (vous fournissez) |
| D10 | **Dossiers à arbitrer par la Direction** (badge) : durée de validité (24 mois), format `BDG-NNNNN-AAAA`, mentions du verso, pointage. | Ce sont des décisions d'organisation. | Proposition : 24 mois, format conservé, verso = « propriété de la clinique, rapporter si trouvé » + téléphone d'en-tête, **pas** de pointage en v1. | **V** |

## E. Architecture logicielle & base de données

| # | Limite | Avis d'expert | Solution proposée | Décision / effort |
|---|---|---|---|---|
| E1 | **Pas de services serveur au poste** : `m14-taches` (planificateur), `m14-sessions`, sauvegarde réelle, import par module, restauration. | Le poste mère doit porter ces services (cible ADR-0005) ; la maquette les avait côté PHP. | Service **Dart de la mère** : planificateur (tâches lues-seules, alertes en table dédiée), sauvegardes chiffrées quotidiennes, restauration vérifiée ; sessions réelles via A1/A5. | **V** · L (tâche T19) |
| E2 | **Jeu de démonstration non déterministe** : régénérer `gen-poste-jeu.js` change les tirages et casse les vecteurs ; fixtures `jeu_sobre` à synchroniser à la main. | Dette de test. | **Figer** le jeu (graine fixe dans la maquette pour l'export) ; une seule commande qui régénère jeu + fixture + vecteurs ; CI qui détecte une divergence. | **T** · M |
| E3 | **Tests dépendants de l'horloge/fuseau** (vecteurs en UTC) ; parité à horloge épinglée 30/10/2026 10 h. | Fragile. | Horloge injectée partout (déjà `SighPoste.horloge`) ; vecteurs avec horloge figée **et** fuseau Africa/Porto-Novo. | **T** · M |
| E4 | **Schéma relationnel** : `remboursements` absent du schéma d'origine (projection d'erreurs), `donneurs`/`poches` ajoutés à la main ; générateur incapable de rejouer sans base complète. | Projection = copie ; doit rester reconstruisible. | Régénération du schéma **depuis les déclarations des collections** (pas depuis un export de base) ; test de parité magasin ↔ tables en CI. | **T** · M |
| E5 | **Namespaces du domaine** : un barrel unique + préfixes (`ass`, `cpa`, `rha`…) et `hide`. | Couplage fort, collisions à chaque ajout. | Un **paquet par domaine** (`sigh_domaine_caisse`, `…_stock`, …) avec exports explicites ; migration par lot. | **T** · L |
| E6 | **Numérotation des écarts E** en doublon (plages réservées par agent), 1 039 écarts : lisibilité. | Documentation. | Renuméroter, classer par module et par nature (corrigé / fidèle / à arbitrer) ; export tableau. | **T** · S |
| E7 | **Disque/CI** : builds Flutter lourds ; worktrees. | — | Cache Flutter hors dépôt ; CI sur machine dédiée ; exécution des suites en parallèle contrôlée. | **T** · S |
| E8 | **Jamais compilé nativement** : Windows/Linux/Android non buildés ; **SQLCipher** non branché ; service Windows non fait. | Risque d'intégration majeur, normal à ce stade. | Banc natif au moment de la finalisation (vous fournissez l'environnement) ; SQLCipher avec clé issue du mot de passe/DPAPI ; installateur MSIX/DEB. | **V** (calendrier) · L |
| E9 | **Synchronisation** : dernier-geste-gagne dans la maquette ; protocole mère/fileul testé au banc seulement. | Conflits réels à gérer. | Journal d'opérations (déjà spécifié) : rejouer les écrans critiques sur deux postes ; règles de conflit par entité (jamais suppression, RG-14). | **T** · L |

## F. Divers conformité & ergonomie

- **cfg-branding (E841)** : « Enregistrer » ne fait que journaliser et promet que les états reprendront les mentions (faux). → Faire lire la configuration de marque par `PieceA4` (en-tête, pied) ; l'identité légale reste **unique** (arbitrage du 31/08). **V** · S.
- **cfg-certificats (E844)** : second registre de certificats (sans caisse ni numérotation officielle) à côté de `m1-pieces`. → Fusionner : `cfg-certificats` ne garde que les **gabarits** ; la délivrance passe par `m1-pieces` (caisse + série annuelle). **V** · M.
- **Option « Poste → rôle → accès »** ne relit pas les surcharges → résolu par A4.
- **Quatre arbitrages d'organisation** (badge) → D10.
- **Photo de badge, imprimante à cartes** → D5, D8.

---

## Ordre d'exécution proposé

1. **A1 + A5 + A6** (identité, authentification, écrans sans chrome) — débloquent A2, A3, B1, B2, D1.
2. **A4** (droits à chaud) — débloque la banque de sang et l'onglet « Poste → rôle → accès ».
3. **B1 + B3 + B4** (exercice partout, archive GED, doublon liasse).
4. **B5, B6, B7, B8, B10** après validation de la Direction (corrections *maquette d'abord*, banc 74/74, puis poste).
5. **C1, C2** après validation du gestionnaire de stock et de la Direction.
6. **D5, D6, D7** (ergonomie), **E2-E4** (dettes de test et de schéma).
7. **E1, E8, E9, D8, D9** à la finalisation, avec vos fournitures (boîtier MECeF, imprimantes, environnements natifs).

## Ce que je vous demande

Répondre **par numéro** : `A1 oui`, `B5 oui avec …`, `D10 : durée 36 mois`, etc. Tout ce qui est marqué **T** sera traité sans autre question ; tout ce qui est **V** attend votre réponse.


---

## Décisions de la Direction du 31/10/2026 : « Je valide et j'accepte tout »

Toutes les solutions V du présent document sont **validées**, avec les valeurs proposées quand une valeur était demandée :

- **D10 (badge)** : validité 24 mois, format `BDG-NNNNN-AAAA` conservé, verso « propriété de la clinique, à rapporter si trouvé » + téléphone d'en-tête, pas de pointage en v1.
- **C2** : les 16 tarifs d'imagerie en attente sont **arrêtés** le 31/10/2026 (`tarifArreteLe` sur le catalogue vivant, la semence garde son marquage). Méthode de valorisation : fiche datée, défaut inchangé (prix de vente) tant que la Direction ne bascule pas.
- **RLS (12 écrans)** : déclarés « porté (apps/web) » après contrôle de parité contre le panneau Laravel existant.
- **MERE (22 écrans)** : portés depuis la spécification du protocole et le moteur de synchronisation (tâche T19).
- **Banque de sang et donneurs** : débloqués par A4.
- **Statut des écrans autonomes non mesurables** : « porté », avec la mention « non mesurable » et des tests de comportement.
- **Règle de rédaction** : plus de tirets cadratins (—), demi-cadratins (–) ni de traits d'union utilisés comme ponctuation dans le code, les commentaires, les textes d'interface et les paragraphes `text-xs text-info-900` ; on utilise la virgule, les deux-points, les parenthèses ou le point. Les identifiants (ids kebab, noms de fichiers, intervalles, dates) restent syntaxe.

### Plan d'exécution (maquette d'abord pour toute règle de gestion, puis poste)

| Vague | Contenu | Statut |
|---|---|---|
| 1 | A1+A5 (session nominative, authentification hachée) ; A4 (droits à chaud, banque de sang, onglet poste/rôle/accès) ; B5+B10 ; B6+A2+E742 ; B7+B8+B11+C3+C4 | lancée |
| 2 | B1+B3+B4 (exercice partout, archive GED, doublon liasse) ; C1+C2+A3 ; D2+D3 ; F (branding, certificats) | après vague 1 |
| 3 | D5+D6+D7 (fichier natif, français, tel/son) ; E2+E3+E4 (jeu figé, horloge, schéma) ; E5+E6 | après vague 2 |
| 4 | MERE (22 écrans) ; RLS (12, contrôle de parité apps/web) | après vague 1 |
| 5 | D8+D9+E1+E8+E9 (matériel : imprimantes, boîtier MECeF, builds natifs, synchronisation) | à la finalisation, avec vos fournitures |
