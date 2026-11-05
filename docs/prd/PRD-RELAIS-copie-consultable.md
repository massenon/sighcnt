# PRD : Relais opaque mais consultable (copie chiffrée de la base, lue dans le navigateur)

Statut : **proposé le 05/11/2026** ; option **B** choisie par la Direction le 05/11/2026 (« relais opaque, mais consultable »). Les décisions de la section 9 sont à valider avant le premier code.
Sources : demande de la Direction du 05/11/2026 (le web doit garder une copie de la base du poste, consultable, avec échanges dans les deux sens) ; `docs/architecture/adr/ADR-0005-*` (relais opaque, clé de clinique, enveloppes chiffrées de bout en bout) ; `packages/sync_dart/lib/src/pont.dart` ; `apps/web/database/migrations/2026_10_29_000000_create_relais_tables.php` ; blueprint TATACORA fourni par la Direction (modèle de comparaison, option A écartée).
Règle de rédaction : pas de tiret cadratin comme ponctuation.

## 1. Problème

Le relais en ligne (`apps/web`) transporte aujourd'hui des enveloppes chiffrées de bout en bout (AES-256-GCM, clé de clinique que seuls les appareils de la clinique détiennent) et ne montre au panneau que des indicateurs sans nom de patient. La Direction veut **consulter les données depuis le web** (hors de la clinique, depuis un téléphone ou un ordinateur) : voir les tables et leurs enregistrements, à jour après chaque synchronisation.

La copie lisible côté serveur (modèle TATACORA, option A) a été écartée : elle mettrait les dossiers patients, la caisse et la paie en clair sur un hébergement mutualisé, et obligerait le relais à porter les règles métier (RG-03, RG-09, RG-10), donc à les écrire deux fois. Ce PRD définit l'option B : **le relais garde une copie qu'il ne peut pas lire ; le navigateur la déchiffre avec la clé de la clinique.**

## 2. Objectifs

- **O1.** Après chaque synchronisation de la mère, une copie à jour de la base consultable est déposée au relais, **chiffrée**. Critère : le relais ne contient aucun octet lisible d'un enregistrement (la preuve d'opacité le mesure sur les enveloppes de copie comme sur les autres).
- **O2.** Une page du panneau permet de **consulter** les tables et les enregistrements (liste, recherche, détail) après saisie de la clé de clinique. Critère : un enregistrement créé sur un poste est lisible au web après la synchronisation suivante de la mère.
- **O3.** La **clé ne quitte jamais le navigateur** : elle n'est ni envoyée, ni journalisée, ni stockée par le serveur. Critère : test qui parcourt les requêtes, les journaux et la base du relais et ne trouve pas la clé ni de clair.
- **O4.** **Aucune règle métier au relais.** Critère : `apps/web` ne contient aucun calcul de stock, de solde, de prise en charge ni d'écriture comptable.
- **O5.** Aucune suppression physique (RG-14) : un enregistrement archivé reste dans la copie avec son drapeau.

## 3. Non-objectifs

- **Écrire depuis le web** (créer ou corriger un enregistrement dans le navigateur) : v2. Les « échanges dans les deux sens » entre postes existent déjà par le journal d'opérations chiffré ; l'écriture web demanderait un client qui produit des opérations signées comme le mobile.
- **Copie lisible côté serveur** : écartée (option A).
- **Remplacer la mère** : la mère reste l'autorité et la seule à rejouer les règles.
- **Cloisonnement fin par rôle dans le navigateur** : une clé unique donne tout ou rien. Le cloisonnement RG-13 se règle par des clés séparées (section 9, Q2), pas par un filtre d'affichage.
- **Tableaux de bord calculés au web** : les indicateurs existants (sans nom de patient) restent ce qu'ils sont.

## 4. Récits d'utilisateur

- En tant que **Directrice Administrative**, je consulte depuis chez moi l'état de la caisse et du stock, en saisissant la clé de la clinique, afin de ne pas me déplacer.
- En tant que **Directeur Médical**, je retrouve un dossier patient depuis mon téléphone, afin de répondre à une urgence hors des murs ; sans la clé, je ne vois rien.
- En tant qu'**administrateur système**, je vois quand la dernière copie a été reçue et si elle est complète, afin de savoir si le web est à jour.
- En tant que **responsable de la sécurité**, je peux démontrer que le serveur ne lit pas les données, afin de rassurer la Direction.
- Cas limites : clé erronée (refus nommé, rien ne s'affiche) ; copie vide au premier jour (message nommé, pas d'écran vide muet) ; copie en retard (bandeau daté) ; navigateur sans WebCrypto (refus nommé) ; clé perdue (les données du web sont illisibles, la mère garde tout : voir Q1).

## 5. Conception (résumé)

**Qui publie.** La **mère seule** publie la copie : elle détient l'état consolidé après rejeu des opérations de tous les postes. Chaque enregistrement appliqué par la mère entre dans un lot ; un lot par passage (au plus toutes les 30 secondes) est chiffré et déposé comme **enveloppe de copie**, dans un nouveau sens `copie` à côté de `vers_mere`, `vers_mobile`, `journal`. Les fileuls ne publient rien de plus : leurs opérations atteignent déjà la mère.

**Ce que contient une enveloppe de copie.** Un lot d'enregistrements `{table, id, version, archive, donnees}` plus, pour la première copie, un **instantané** par table. Tout est dans le texte chiffré : le relais ne voit que `appareil`, `dir = copie`, le rang `n`, le nonce et la taille. Il ne voit ni nom de table, ni identifiant d'enregistrement.

**Chiffrement.** Même procédé que l'existant : AES-256-GCM, clé de clinique, `aad` = `id|appareil|dir|n`, ce qui lie l'enveloppe à sa place et empêche de rejouer ou de réordonner. Le rang contigu `n` détecte une enveloppe manquante.

**Lecture au web.** Une page du panneau, après connexion superadmin (déjà en place), demande la clé de clinique. Elle est lue **en mémoire du navigateur seulement** (jamais `localStorage`), importée dans WebCrypto, puis le navigateur télécharge les enveloppes `copie`, les déchiffre, reconstruit les tables en mémoire (IndexedDB chiffré en option, P1) et les affiche en lecture seule. L'authentification au panneau et la clé sont deux verrous distincts : le compte donne accès aux enveloppes chiffrées, la clé donne accès au contenu.

**Compaction.** Pour ne pas grossir sans fin sur un hébergement mutualisé : à intervalle, la mère dépose un **nouvel instantané** et le relais purge les enveloppes de copie antérieures à cet instantané (le relais ne lit pas : la mère annonce « purger avant le rang N », authentifié par la clé d'appareil de la mère).

**Retour (« les données renvoyées »).** Dans le sens poste vers poste, le journal chiffré existant assure déjà l'envoi, la réception et le renvoi, y compris les données saisies hors ligne. Le web n'ajoute pas un second chemin d'écriture (non-objectif v1).

## 6. Exigences et critères d'acceptation

### P0

| # | Exigence | Critère |
|---|---|---|
| R1 | La mère dépose un lot de copie chiffré après chaque passage de synchronisation, au plus toutes les 30 s | un enregistrement créé sur un fileul apparaît dans une enveloppe `copie` après le passage suivant de la mère |
| R2 | Le relais stocke les enveloppes `copie` comme les autres : nonce, texte chiffré, rang contigu, idempotence | redéposer la même enveloppe ne la duplique pas ; un trou de rang est signalé |
| R3 | Aucun clair au relais | la preuve d'opacité mesure aussi les enveloppes de copie (entropie, absence de noms de table et d'identifiants) |
| R4 | Page « Consulter la copie » au panneau : saisie de la clé, déchiffrement dans le navigateur, liste des tables, enregistrements, recherche | scénario navigateur : clé exacte, les enregistrements apparaissent ; clé fausse, refus nommé et rien affiché |
| R5 | La clé n'est ni envoyée, ni journalisée, ni stockée côté serveur | test qui balaie requêtes, journaux Laravel et base : ni la clé, ni un clair |
| R6 | Lecture seule : aucune commande d'écriture sur la page | l'audit RBAC ne relève aucune commande d'écriture ; les routes web acceptent seulement GET |
| R7 | État de la copie visible : dernière enveloppe reçue, complétude (rangs contigus), retard | bandeau daté ; copie en retard de plus de N minutes signalée |
| R8 | Archivage, jamais suppression (RG-14) | un enregistrement archivé reste lisible avec son drapeau |
| R9 | Aucune règle métier dans `apps/web` | revue : aucun calcul métier ajouté au relais |

### P1

- R10 : compaction (nouvel instantané, purge annoncée par la mère).
- R11 : cache local chiffré dans le navigateur (IndexedDB) pour éviter de retélécharger toute la copie.
- R12 : clés séparées par domaine (médical, financier, administratif), si la Direction veut un cloisonnement.
- R13 : export CSV d'une table consultée, avec journalisation de l'export.

### P2

- Écriture depuis le web par opérations signées ; recherche plein texte côté navigateur ; partage temporaire d'un enregistrement.

## 7. Sécurité et conformité

- **Menace principale** : un serveur piraté ou un hébergeur curieux. Il obtient des enveloppes chiffrées, sans la clé ; l'opacité est mesurée, pas déclarée.
- **Nouvelle surface** : la page web qui manipule la clé. Elle doit être servie en HTTPS, avec une politique de contenu (CSP) sans script externe, sans stockage persistant de la clé, et un verrouillage après inactivité (la clé est effacée de la mémoire).
- **Perte de la clé** : les données du web deviennent illisibles ; la mère n'est pas affectée. Une procédure de remise de la clé (impression, coffre) est à décider (Q1).
- **Compromission d'un navigateur** : celui qui voit la clé voit tout (limite du modèle à clé unique). D'où Q2.
- **Journalisation (RG-12)** : chaque ouverture de la page et chaque export sont journalisés avec le compte, sans contenu.

## 8. Métriques de réussite

- **À la livraison** : 100 % des enregistrements d'une base de test présents dans la copie ; 0 octet lisible mesuré par la preuve d'opacité ; clé fausse refusée dans 100 % des cas.
- **Après un mois** : retard moyen de la copie sous 2 minutes ; 0 incident de donnée en clair ; taille de la copie sous le quota de l'hébergement.

## 9. Décisions à valider par la Direction

| # | Question | Ma recommandation | Bloquante |
|---|---|---|---|
| **Q1** | Comment la clé de clinique est-elle remise au navigateur, et que fait-on si elle est perdue ? | la mère l'affiche (écran « Clé de clinique » existant) en texte et en QR ; la personne la colle ou la scanne ; elle reste en mémoire de l'onglet seulement ; une copie papier est gardée au coffre de la Direction | oui |
| **Q2** | Une clé unique donne tout (patients, caisse, paie). Voulez-vous des clés séparées par domaine (médical, financier, administratif) ? | oui en P1 ; en v1, une clé unique **réservée à l'administrateur, à la DA et à la Direction**, et le médical n'est consultable qu'avec sa propre clé | oui |
| **Q3** | Les dossiers de patients sont-ils dans la copie consultable ? | oui, chiffrés, avec la clé médicale séparée (Q2) ; sinon la copie ne porte que le non médical | oui |
| **Q4** | Quel volume l'hébergement accepte-t-il ? (MySQL ou PostgreSQL sur cPanel, quota) | mesurer la taille d'une copie complète sur le jeu de démonstration avant de fixer l'intervalle d'instantané | oui |
| Q5 | Écriture depuis le web : v2 ? | oui, hors de ce PRD | non |
| Q6 | Fréquence de dépôt de la copie | toutes les 30 secondes au plus, uniquement s'il y a du nouveau | non |
| Q7 | Durée de verrouillage automatique de la page | 10 minutes d'inactivité | non |

## 10. Plan en phases

1. **Phase A (relais et mère, sans interface)** : sens `copie` au relais, dépôt par la mère, rang contigu, opacité mesurée, tests de bout en bout dans le banc (`npm run banc:sync`).
2. **Phase B (page web)** : saisie de la clé, déchiffrement WebCrypto, liste et détail en lecture seule, bandeau d'état, tests navigateur.
3. **Phase C** : compaction, cache local, clés par domaine (P1).

## 11. Ce qui ne peut pas être vérifié ici

L'environnement ne reproduit pas l'hébergement cPanel (quota, version de base, HTTPS réel) ni un vrai navigateur mobile. La preuve d'opacité, les rangs et le chiffrement sont testables ici ; le volume réel et le comportement du navigateur sur téléphone sont à mesurer sur l'hébergement final.
