# PRD : M12 et socle, sélecteur d'exercice dans la barre supérieure, trois états, clôture par pièces CL et AN, réouverture par contre-passation

Statut : brouillon du 05/11/2026. Complète et, sur les points signalés « change », remplace [PRD-M12-cloture-exercice](PRD-M12-cloture-exercice.md) (20/10/2026, mis en œuvre aux vagues 69 et 70). Source : demande de la Direction du 05/11/2026 (texte reçu, avec l'avis d'expert-comptable qui l'accompagne). Ce qui n'a pas de source documentaire est une proposition à valider, et le dit.

## 1. Problème

Le sélecteur d'exercice existe (`#selecteur-exercice`, en tête des seuls écrans M12, MECeF et M9) mais il est enfermé dans la comptabilité : le directeur qui lit les ventes, le responsable des achats ou la paie ne peuvent pas relire 2025 sans passer par un écran comptable. Le cycle de l'exercice est aussi plus court que ce que la pratique comptable demande : deux états de passage (`ouvert`, `en_attente_cloture`, `clos`) sans retour arrière documenté, une pièce de résultat nommée `OD-AAAA-RES` au lieu d'un journal de clôture, une archive réduite à la balance en CSV, aucune réouverture. Sans cela, une erreur découverte après la clôture oblige à tout reprendre dans PERFECTO, et la clinique n'a pas de piste d'audit SYSCOHADA complète.

## 2. Objectifs et non-objectifs

Objectifs (mesurables) :

1. Le choix de l'exercice se fait de la barre supérieure, sur tous les écrans qui ont une notion d'année, et un seul endroit le tient (la session).
2. Aucune écriture ne change d'exercice parce qu'on en consulte un autre : 100 % des pièces créées portent l'exercice de LEUR date (scénario de mutation, section 12).
3. Un exercice a trois états et quatre transitions, dont une réouverture qui ne supprime rien (contre-passation).
4. La clôture est faite de pièces comptables (CL puis AN) dans une seule transaction, et laisse une archive immuable vérifiée à chaque téléchargement.
5. Deux exercices s'écrivent en parallèle au passage de N à N+1, sans arrêter la caisse.

Non-objectifs :

- Le sélecteur ne donne AUCUN droit et ne déplace aucune écriture (principe de la demande).
- Pas de changement de la numérotation des pièces certifiantes ni des factures.
- Pas de consolidation multi-établissements, pas de calendrier fiscal décalé (exercice = année civile, comme la liasse déposée).
- Pas de format d'archive validé par la DGI dans cette version : le format est isolé en un point et marqué à valider (section 9).

## 3. Utilisateurs et rôles

| Rôle | Fait | Ne fait pas |
|---|---|---|
| Comptable | change d'exercice, démarre la clôture, reprend la saisie, passe les écritures d'inventaire en clôture, **rouvre** un exercice clôturé (motif d'au moins 10 caractères) | clôture définitive (voir question 1) |
| Direction / DAF | change d'exercice, lit tous les états, **clôture définitivement** (proposition, voir question 1) | saisit une écriture |
| Assistant comptable (`aide_comptable`) | change d'exercice, saisit sur un exercice ouvert | démarrer, clôturer, rouvrir : `m12-cloture` lui reste fermé nommément |
| Assistant de Direction | change d'exercice sur les écrans qu'il voit, lit | écrit en M12 |
| Caissier, gestionnaire de stock et autres postes du jour | rien : le sélecteur n'apparaît pas sur leurs écrans du jour | — |

Le sélecteur n'élargit jamais ce qu'un écran montre : un profil qui n'a pas le droit de voir un écran ne le voit pas davantage en choisissant 2025.

## 4. Parcours

1. **Consulter 2025 depuis les ventes** : le directeur choisit « 2025 » dans la barre, l'écran se recharge, un bandeau dit « Exercice 2025, clôturé : lecture seule ». Il lit ; il ne peut rien y écrire.
2. **Encaisser le 2 janvier** : la caissière encaisse comme d'habitude. L'écriture naît en brouillon sur l'exercice 2026, quel que soit l'exercice affiché ailleurs sur son poste.
3. **Passer de N à N+1** : le 1ᵉʳ janvier 2027, 2027 est ouvert, 2026 aussi ; les écritures tardives de décembre se passent dans 2026, janvier dans 2027 ; la balance de 2027 affiche des à-nouveaux provisoires et le dit.
4. **Clôturer** : le comptable démarre la clôture (les modules ne peuvent plus écrire dans 2026), passe ses écritures d'inventaire, la liste de contrôle passe, la clôture définitive pose CL puis AN puis le verrou puis l'archive.
5. **Corriger après coup** : le comptable rouvre 2026 avec un motif ; la clôture et les à-nouveaux sont contre-passés, 2026 repasse « en clôture ».

## 5. Exigences fonctionnelles

### 5.1 Sélecteur de la barre supérieure

| Réf. | Énoncé | Critère d'acceptation | État actuel |
|---|---|---|---|
| EF-EX-01 | Le sélecteur est dans la barre supérieure, à côté de la recherche, et ne s'affiche que sur les écrans « à année » (liste en 5.2). | Sur `m12-ecritures` il est présent ; sur `m8-caisse` il est absent. | **Change** : aujourd'hui dans l'en-tête des seuls écrans M12. |
| EF-EX-02 | Le choix vit dans la session de l'utilisateur, en UN endroit ; tous les écrans le lisent là, jamais depuis une copie. | Un écran qui garde sa propre copie échoue au test de source unique (une recherche de la clé de stockage hors du module de session ne trouve rien). | **Change** : aujourd'hui `sigh-cnt:exercice` dans le navigateur, lu par plusieurs modules. |
| EF-EX-03 | Exercice par défaut : le plus récent des exercices ouverts, sinon le plus récent tout court. | Jeu avec 2025 clôturé, 2026 ouvert : défaut 2026. Jeu avec 2025 et 2026 clôturés : défaut 2026. | Aujourd'hui : l'année en cours. |
| EF-EX-04 | Changer d'exercice recharge l'écran ; le choix n'écrit rien et ne donne aucun droit. | Avant et après un changement, le journal d'audit ne gagne aucune écriture comptable ; les commandes offertes sont celles du rôle. | Conforme sur M12. |
| EF-EX-05 | Boutons « Exercice N-1 » et « Exercice N+1 » à côté du sélecteur, désactivés aux bornes. | Sur le plus ancien exercice, « N-1 » est absent (jamais grisé sans explication). | Nouveau. |
| EF-EX-06 | Un bandeau d'état dit « en clôture » ou « clôturé » et renvoie au geste qui permet de corriger. | Exercice clôturé : le bandeau nomme la réouverture et le rôle qui la fait. | Partiel (lecture seule annoncée sur M12). |
| EF-EX-07 | **Dates relatives** : « ce mois », « ce trimestre » se calculent depuis aujourd'hui si l'exercice consulté le contient, sinon depuis son dernier jour. | Consulter 2025 en 2026 : « ce mois » = décembre 2025. Consulter 2026 en 2026 : mois courant. | **Change** : `C.bornes` part de la date du jour sans considérer l'exercice. |

### 5.2 Écrans concernés

À année (sélecteur affiché) : comptabilité (M12 entière), états et rapports (RAP, pilotage financier), dépenses, facturation (registres, avoirs, factures assureur), achats (M7), paie (M11), accueil dans sa part statistique. Du jour (sélecteur absent) : caisse, point de vente, suivi des ventes du jour, tableaux de bord du poste comptable et du gestionnaire de stock. La liste vit dans le manifeste (propriété déclarée par écran, `exerciceSelecteur`), jamais écrite à la main dans chaque écran.

### 5.3 Où va une écriture

| Réf. | Énoncé | Critère d'acceptation |
|---|---|---|
| EF-EX-10 | Toute pièce (vente, dépense, encaissement, paie) est rattachée à l'exercice de SA date, jamais à l'exercice consulté. | Sélecteur sur 2025, encaissement daté du jour : la pièce naît dans 2026. Test de mutation : faire lire le sélecteur par la création doit faire échouer le test. |
| EF-EX-11 | Une pièce dont la date tombe dans un exercice `en clôture` ou `clos` est refusée aux modules, en nommant l'exercice et le geste de correction ; seule la comptabilité passe une écriture d'inventaire en clôture. | Refus nommé, journalisé (RG-12), rien d'écrit. |

### 5.4 Les trois états

| État | Modules | Saisie manuelle | Comptable |
|---|---|---|---|
| `ouvert` | écrivent | oui | oui |
| `en_cloture` | refusés | refusée | écritures d'inventaire seulement |
| `cloture` | refusés | refusée | rien, sauf réouverture |

**Change** : l'état actuel `en_attente_cloture` (attente de validation de la Direction) devient `en_cloture` et prend le sens de la demande. Une migration renomme l'état des exercices existants.

### 5.5 Passage de N à N+1

| Réf. | Énoncé | Critère d'acceptation |
|---|---|---|
| EF-EX-20 | Ouverture automatique : l'exercice de l'année en cours existe toujours ; en décembre, celui de l'année suivante aussi. La première pièce datée du 1ᵉʳ janvier ouvre l'année si elle manque. | Horloge au 15/12/2026 : 2026 et 2027 ouverts. Pièce du 01/01/2028 sans exercice 2028 : 2028 s'ouvre. |
| EF-EX-21 | **Prototype** : la collection `exercices` est DÉRIVÉE des écritures et de l'année en cours (vague 69), donc l'ouverture est déjà « automatique » à la lecture. Une tâche planifiée à 00:05 NE PEUT PAS écrire la collection (doctrine du planificateur : les postes réécrivent leurs collections entières, une écriture serveur serait écrasée). Elle vérifie et lève une alerte si un exercice attendu manque. | La tâche `exercices_ouverture` figure au registre, écrit dans `notifications_serveur` et jamais dans `collections`. |
| EF-EX-22 | **Cible** : l'ouverture est une opération de la mère (agrégat à invariant), lancée à 00:05 par son planificateur. | Hors du périmètre du prototype. |
| EF-EX-23 | Deux exercices ouverts en parallèle ; N reste ouvert tant que sa clôture n'a pas commencé. | Écriture du 28/12 acceptée dans N pendant qu'une écriture du 03/01 l'est dans N+1. |
| EF-EX-24 | À-nouveaux provisoires : tant que N n'est pas clôturé, la balance de N+1 inclut les soldes de bilan de N, calculés à la volée, jamais écrits, avec le résultat de N en 131 ou 139 ; l'écran dit « provisoire ». Les classes 6 à 9 repartent de zéro. | Aucune ligne `AN` n'existe dans le journal tant que N n'est pas clôturé. Après clôture, l'à-nouveau est écrit et le mot « provisoire » disparaît. |

### 5.6 Clôture et réouverture

| Transition | Qui | Effet |
|---|---|---|
| Démarrer la clôture (`ouvert` vers `en_cloture`) | comptable | les modules ne peuvent plus écrire dans N |
| Reprendre la saisie (`en_cloture` vers `ouvert`) | comptable | possible tant que rien n'est clôturé |
| Clôturer définitivement (`en_cloture` vers `cloture`) | voir question 1 | CL, AN, verrou, archive, dans cet ordre |
| Rouvrir (`cloture` vers `en_cloture`) | comptable seul, motif d'au moins 10 caractères | contre-passe CL et AN, ne supprime rien |

Liste de contrôle avant la clôture définitive. Bloquants : aucune écriture en brouillon, balance équilibrée (RG-10), exercice N-1 déjà clôturé, exercice N+1 non clôturé. Non bloquant : liste des postes qui ont des opérations à envoyer (ils doivent d'abord synchroniser : une fois N en clôture, la mère refuse leurs pièces datées de N). Chaque contrôle nomme les pièces en cause et l'écran où corriger.

À la clôture définitive, dans une seule transaction, dans cet ordre :

1. **Pièce de clôture** au 31/12/N, journal `CL` : solde les classes 6, 7 et 8 centre de coûts par centre de coûts ; la contrepartie va en 131 (bénéfice) ou 139 (perte). **Change** : aujourd'hui la pièce `OD-AAAA-RES` porte le résultat sans journal propre.
2. **Pièce d'à-nouveaux** au 01/01/N+1, journal `AN` : reporte les soldes des classes 1 à 5, résultat compris. Elle remplace les à-nouveaux provisoires.
3. **Verrou** : N passe à `cloture`.
4. **Archive légale** (5.8).

Si l'un des quatre échoue, rien n'est écrit (atomicité). Les journaux `CL` et `AN` ne se choisissent pas à la saisie manuelle. Les états de N restent ceux d'avant la clôture : le journal `CL` est exclu du compte de résultat, qui montre le résultat de l'année et non zéro.

Réouverture : une pièce `CL-C` et une pièce `AN-C` contre-passent les deux pièces d'origine (mêmes lignes, sens inversé, motif, auteur, date). Elle est REFUSÉE, en nommant l'exercice, si N+1 n'est pas `ouvert` (un N+1 en clôture ou clôturé a déjà consommé l'à-nouveau). Elle prévient la Direction par notification.

### 5.7 Consulter l'année précédente

- Comparatif : le compte de résultat et le bilan portent une colonne « Exercice N-1 » quand il existe, mêmes postes, même filtre (déjà en place pour le bilan, vague 70 ; à étendre au compte de résultat et au flux).
- Grand livre : chaque compte montre son solde d'ouverture et de clôture. Pour un compte de bilan, l'ouverture est l'à-nouveau : écrit si N-1 est clôturé, provisoire (calculé, et dit tel) sinon. Si N-1 a été clôturé sans à-nouveaux, l'ouverture est « inconnue », jamais zéro.
- Le **résultat reporté** se calcule, jamais saisi : pour chaque exercice clôturé il est lu depuis la pièce `CL`.

### 5.8 Archive légale

CSV des écritures, CSV de la balance, PDF des états (bilan, compte de résultat, flux), manifeste avec l'empreinte SHA-256 de chaque fichier. Créée à chaque clôture, jamais régénérée, immuable, vérifiée avant chaque téléchargement (une empreinte qui ne correspond plus est un refus nommé, pas un fichier livré). Rangée à la GED (`documents`, conservation 10 ans comme aujourd'hui). **Change** : aujourd'hui balance CSV et empreinte seulement. Le format du CSV des écritures (colonnes, encodage, nom) est isolé en UN point du code et marqué « à valider avec le cabinet comptable ou la DGI Bénin ».

### 5.9 Paramétrage

Les comptes de résultat 131 (bénéfice) et 139 (perte) viennent d'une table de correspondance paramétrable (référentiel de `cfg-comptabilite`), pas du code. **Change** : aujourd'hui `131000` et `139000` sont écrits dans le moteur.

## 6. Données

- `exercices` : année, début, fin, état (`ouvert`, `en_cloture`, `cloture`), auteurs et dates de chaque transition, motif de réouverture, empreinte de l'archive. Dérivée des écritures au prototype, agrégat de la mère dans la cible.
- `clotures` (nouvelle) : une fiche par clôture définitive (numéros des pièces CL et AN, résultat, auteur, date, empreintes) et par réouverture (pièces contre-passées, motif). Jamais modifiée.
- `journaux` : `CL` et `AN` réservés (le référentiel porte déjà `AN`).
- `comptesResultat` (nouvelle, référentiel) : 131 et 139.
- Choix d'exercice : clé unique de session, lue par un seul accesseur.
- Incrément de `VERSION` (collections nouvelles, états renommés, fiches RBAC si les droits changent).

## 7. Hors ligne et synchronisation

| Donnée | Famille | Si deux postes agissent sans la mère | Ce que l'écran dit |
|---|---|---|---|
| Écriture d'un exercice ouvert | pièce émise | deux brouillons restent deux pièces | rien de particulier |
| Transition d'état, clôture, réouverture | agrégat à invariant | **opération de la mère seule** : un poste hors ligne ne clôture ni ne rouvre | « Disponible quand la mère est joignable » |
| Écriture datée de N arrivant après le passage de N en clôture | invariant violé | refusée et mise en suspens, tâche au comptable, jamais perdue | pièce nommée, exercice nommé, geste : la passer comme écriture d'inventaire ou la dater de N+1 |
| Postes ayant des opérations à envoyer | information | le battement des postes (`postesClinique`) porte le nombre d'opérations en attente ; l'avertissement de la liste de contrôle le lit | postes nommés |
| Choix d'exercice | session locale | sans objet | — |

## 8. Impression et états

Les états imprimés portent l'exercice consulté dans le cartouche et la mention « provisoire » quand les à-nouveaux le sont ; un exercice clôturé imprime la date et le numéro de sa clôture. Le filtre d'exercice figure parmi les filtres relevés sur la pièce par `print.js`.

## 9. Ce qui n'est pas documenté

- Le format exact du CSV des écritures de l'archive (colonnes, encodage, nom) : à valider avec le cabinet comptable ou la DGI Bénin.
- La liste des écrans « à année » est celle de la demande ; la frontière « accueil » et « poste comptable » est ambiguë (voir question 2).
- Le seuil de dix caractères du motif de réouverture vient de la demande ; aucun document de cadrage ne le fixe.
- Le rôle qui clôture définitivement n'est pas écrit dans la demande.

## 10. Questions ouvertes

Bloquantes pour la Direction :

1. **Qui clôture définitivement ?** La demande donne la réouverture au comptable seul mais ne dit pas qui clôture. Le PRD du 20/10 exigeait deux personnes (demande par le comptable, validation par la Direction ou le DAF, jamais la même). Recommandation : garder ce principe, « démarrer » par le comptable, « clôturer définitivement » par la Direction ou le DAF. Conséquence à accepter : le comptable seul peut défaire ce que la Direction a signé ; recommandation : notification et entrée de journal à la Direction à chaque réouverture.
2. **Frontière des écrans à année.** « Accueil » désigne-t-il les statistiques d'accueil ? « Comptabilité » apparaît dans les deux listes de la demande (à année et du jour) : lire « poste comptable » comme son tableau de bord du jour ? Recommandation : tableaux de bord de poste sans sélecteur, tout registre ou état avec.

Non bloquantes :

3. Format du CSV des écritures (cabinet comptable, DGI Bénin).
4. Réouverture quand N+1 est déjà en clôture : refus (recommandé) ou contre-passation en cascade ?
5. Écriture d'inventaire passée par le comptable en clôture : à marquer d'une nature « inventaire » pour la retrouver à l'audit ?

## 11. Priorités

- **P0** : EF-EX-01 à 04 et 07 (sélecteur en barre, session, défaut, dates relatives), EF-EX-10 et 11 (où va une écriture), 5.4 (trois états), 5.6 (CL, AN, verrou, réouverture, liste de contrôle), 5.9 (131 et 139 paramétrables).
- **P1** : 5.8 (archive complète, vérifiée), EF-EX-05 et 06 (navigation, bandeau), 5.7 (comparatif étendu, ouvertures du grand livre), EF-EX-20 et 21 (tâche 00:05 de vérification).
- **P2** : EF-EX-22 (ouverture par la mère), liaison du battement aux opérations en attente.

Découpage proposé : (a) maquette d'abord, états et pièces CL, AN, scénario ; (b) sélecteur en barre et session ; (c) archive ; (d) portage Flutter par les vecteurs de la maquette, comme pour la tranche 1.

## 12. Tests

Maquette (scénario dédié) puis domaine (`dart test`) puis poste. Cas à écrire, chacun avec sa mutation :

| Cas | Mutation qui doit faire échouer le test |
|---|---|
| Une pièce naît dans l'exercice de sa date | faire lire le sélecteur à la création |
| Sélecteur sur 2025, aucune écriture au journal | écrire au changement d'exercice |
| Exercice `en_cloture` : un module refusé, le comptable passe | retirer la distinction de rôle |
| Exercice `cloture` : tout refusé, y compris le comptable hors réouverture | oublier le verrou |
| CL solde 6, 7, 8 centre par centre, contrepartie 131 ou 139 selon le signe | inverser le signe, ignorer le centre |
| AN reporte 1 à 5, résultat compris, équilibré (RG-10) | reporter une classe 6 |
| CL, AN, verrou, archive atomiques : un échec laisse l'exercice inchangé | commiter après CL seule |
| Réouverture : motif de dix caractères, comptable seul, contre-passations, rien d'effacé | accepter un motif de neuf caractères ; supprimer au lieu de contre-passer |
| Réouverture refusée si N+1 n'est pas ouvert | omettre le contrôle |
| Dates relatives : 2025 consulté en 2026 donne décembre 2025 | partir de la date du jour sans l'exercice |
| À-nouveaux provisoires jamais écrits tant que N n'est pas clôturé | écrire une ligne AN à la volée |
| Ouverture d'un compte de bilan « inconnue » si N-1 clôturé sans AN, jamais zéro | retourner zéro |
| Archive : empreinte vérifiée au téléchargement, fichier modifié refusé | sauter la vérification ; régénérer l'archive |
| États de N inchangés après clôture (journal CL exclu) | inclure CL dans le compte de résultat |
| Sélecteur absent sur la caisse et le point de vente, présent sur les registres | afficher partout |
| RBAC : assistant comptable ne démarre ni ne clôture ni ne rouvre ; le sélecteur n'ajoute aucune commande | donner un droit par le sélecteur |

## 13. Indicateurs de réussite

- 0 pièce créée dans un exercice autre que celui de sa date, mesuré à l'audit du journal.
- Relire 2025 depuis un écran non comptable en moins de trois clics.
- Clôture de 2026 faite dans le logiciel avant le 30/04/2027, avec archive vérifiée, sans ressaisie dans PERFECTO (indicateur retardé).
- Balance de N+1 au 1ᵉʳ janvier égale aux soldes de clôture de N, au franc.
