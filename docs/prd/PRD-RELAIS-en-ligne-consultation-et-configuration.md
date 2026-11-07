# PRD : Relais en ligne, consultation à règles métier complètes, configuration et journal d'opérations conservés sans exception

Statut : **proposé le 07/11/2026** à la demande de la Direction. **Une décision bloquante (Q1) engage l'architecture : elle est à prendre avant tout code.**
Sources : demande de la Direction du 07/11/2026 ; `docs/prd/PRD-RELAIS-copie-consultable.md` (copie chiffrée, lecture dans le navigateur) ; `docs/specs/SPEC-protocole-synchronisation.md` ; ADR-0005 et ADR-0006 ; relevés du code le 07/11/2026 (`apps/web` : consultation, compaction, purges ; `store.js` : `COLLECTIONS_ESSENTIELLES`).
Règle de rédaction : pas de tiret cadratin comme ponctuation. Doctrine : « aucune règle en double » (les règles vivent en Dart dans `packages/domaine`) ; le relais est opaque tant que la Direction n'a pas décidé autrement ; RG-13 et RG-14 ne se négocient pas.

## 1. Ce que la Direction demande (textuel)

1. **Consultation** : « ça doit être en ligne et la règle métier à implémenter à 100 % ».
2. **Configuration** : « elle doit garder la configuration et le système total sans exception, les journaux d'opérations ».
3. **SMS** : voir `PRD-SMS-passerelle-et-test-envoi.md` (Twilio par défaut, Vonage en second, couverture du Bénin déclarée par la Direction, bibliothèques à installer ; installées le 07/11/2026).

## 1 bis. Décisions de la Direction du 07/11/2026 (reçues)

- **Q1 : option A** (relais opaque, règles exécutées dans le navigateur).
- **Q3 : les secrets (mot de passe SMTP, clés des fournisseurs SMS) vont dans le fichier `.env` du relais**, non versionné. Conséquence à valider (elle remplace la saisie dans le panneau décidée le 06/11) : le panneau affiche « défini dans .env » et n'accepte plus la saisie du secret ; le test d'envoi reste dans le panneau ; `.env` est ignoré par git, gardé hors du dossier public, droits de lecture restreints au compte du serveur web ; un secret absent donne le refus nommé `SECRET_NON_DEFINI` avec le nom de la variable à renseigner. Les hachés de comptes restent dans l'instantané, chiffrés.
- **La donnée vient de TOUS les postes, pas de la mère seule.** Chaque poste (fileul ou mère) dépose le journal chiffré de ses opérations au relais ; le client de consultation rejoue **les journaux de tous les appareils** avec la règle de fusion du domaine (`pair`), la même que celle des postes. La copie de la mère devient un **accélérateur** (instantané), plus la source unique : la consultation reste fraîche **même mère éteinte**, tant qu'un poste dépose. À vérifier au banc (étape R1 du plan) : le journal pair est chiffré avec la même clé de clinique et le domaine de fusion se compile pour le web.

## 2. Ce qui existe (relevé le 07/11/2026)

- **Consultation** : une page du panneau superadmin. La mère dépose, au plus toutes les 30 secondes, des enveloppes de copie **chiffrées** (AES-256-GCM, clé de clinique que le relais ne connaît pas). Le navigateur télécharge, déchiffre avec la clé collée par l'utilisateur (mémoire de l'onglet), reconstruit les tables et les affiche. **Aucune règle métier** n'est appliquée : pas de droits par rôle (la page est celle du seul superadmin), pas de filtrage, pas de calcul. Elle est « à jour » seulement tant que **la mère est allumée et connectée** : si elle s'éteint, la copie vieillit.
- **Configuration** : le relais **ne garde pas** la configuration de la clinique. Elle voyage de la mère aux fileuls **dans le journal** (famille R) et jamais aux mobiles (RG-13). Le relais porte seulement ses réglages propres (SMTP, activation de la mère, hébergement, paramètres de consultation).
- **Journal d'opérations** : chaque appareil dépose son propre journal chiffré à rangs contigus ; le relais le conserve et le sert aux autres. **Une compaction existe côté copie** : à chaque nouvel instantané, les enveloppes de copie antérieures sont purgées sur ordre de la mère. Le relais purge aussi, au-delà de 365 jours, **son propre** journal d'audit (pas les enveloppes).

## 3. Problème

- Une consultation hors ligne et sans règle n'est pas **un poste de consultation** : n'importe qui détenant la clé voit tout, sans le filtre RG-13, et la donnée affichée peut être ancienne sans que l'écran le dise toujours clairement.
- Une clinique dont la mère est détruite ne se reconstruit pas **depuis le relais seul** : la configuration n'y est pas, et la compaction a effacé une partie de l'historique.

## 4. Objectifs mesurables

- **O1.** La consultation en ligne applique **100 % des règles de lecture** : droits par rôle (`rbac.json`), cloisonnement RG-13, règles d'affichage et de calcul des écrans consultables. Critère : les **vecteurs du domaine** (323 et plus, source unique) passent identiquement dans le client web ; un test de parité N1 et N2 par écran consultable ; zéro règle codée à la main côté relais.
- **O2.** La donnée affichée a un **âge connu et affiché** (celui du dernier dépôt de **n'importe quel poste**) (« mise à jour il y a N s »). Critère : latence mère vers consultation de 5 secondes au plus en fonctionnement normal ; quand la mère est éteinte ou injoignable, la page le dit en toutes lettres avec l'heure de la dernière copie, **jamais un état « en ligne » trompeur**.
- **O3.** Le relais conserve **la configuration complète et le journal d'opérations de toutes les familles, sans purge ni exception** (hors secrets de fournisseur, voir Q3). Critère : une mère neuve restaure l'état entier depuis le relais seul, et l'empreinte de l'état restauré égale celle de la mère d'origine (test de bout en bout).
- **O4.** L'opacité du relais est **conservée** si la Direction retient l'option A (Q1) ; sinon elle est abandonnée **explicitement** par décision écrite.
- **O5.** Aucune régression de RG-12 (journalisation de chaque ouverture) ni de RG-14 (jamais de suppression).

## 5. Hors périmètre de la v1

- **Écriture depuis la consultation web.** Elle reste en lecture (voir Q4). Le journal d'opérations est le seul chemin d'écriture : un second chemin créerait deux vérités.
- Édition de la configuration depuis le relais (la mère reste l'autorité de la configuration, famille R).
- Consultation par le patient (hors périmètre du cahier des charges).

## 6. L'option qui commande tout (Q1, bloquante)

La demande « règle métier à 100 % **en ligne** » se réalise de deux façons qui s'excluent.

**Option A (recommandée) : relais opaque, règles exécutées dans le navigateur.**
Le client web de consultation embarque **le même domaine Dart** que le poste (compilé pour le web : application Flutter web ou PWA, prévue par ADR-0005). Il déchiffre les enveloppes avec la clé de clinique, applique `rbac.json` et les règles du domaine, et affiche. Le relais ne voit toujours que des enveloppes chiffrées.
- Pour : **une seule implémentation des règles** (aucune copie PHP qui divergerait) ; l'hébergeur mutualisé et un serveur piraté ne voient aucune donnée de santé ; RG-13 tient ; compatible ADR-0005.
- Contre : la clé de clinique doit parvenir au navigateur de chaque consultant (voir Q2) ; la fraîcheur dépend de la mère (limite de O2).

**Option B : le relais connaît les données en clair et exécute les règles.**
Le relais déchiffre, stocke en clair, applique les règles côté serveur.
- Pour : consultation possible mère éteinte avec données fraîches **si** le relais reçoit les opérations en clair ; filtrage serveur par rôle.
- Contre, tous bloquants à décider : **l'hébergeur mutualisé voit les données de santé** (RG-13, protection des données) ; il faut **réécrire toutes les règles en PHP** (règle « aucune règle en double » violée, divergence garantie) ; l'ADR-0005 est renversé ; la sécurité repose sur un serveur partagé.

**Recommandation : option A.** Elle donne à la Direction ce qu'elle demande (en ligne, règles à 100 %) sans renoncer à l'opacité. Choisir B suppose une ADR de renversement, un accord de traitement des données avec l'hébergeur et l'engagement de porter les règles en PHP.

## 7. Exigences

**P0 (la v1 ne sort pas sans)**

1. **Client de consultation web** (option A) : authentification nominative (compte et rôle), droits par écran issus de `rbac.json`, lecture seule, **toutes les écrans consultables du manifeste** listés dans la spec ; une commande interdite est absente.
2. **Âge de la donnée** affiché en permanence ; rafraîchissement automatique (relève du compteur toutes les 5 secondes, ETag) ; état « source injoignable » nommé.
3. **Copie quasi continue** : la mère dépose chaque lot appliqué sans attendre 30 secondes (plafonné à une enveloppe par 5 secondes), avec reprise.
4. **Conservation intégrale** : plus aucune purge des enveloppes de copie ni des journaux ; la compaction par instantané est **remplacée** par instantané plus archive froide (les anciennes enveloppes restent, compressées, hors du chemin de lecture).
5. **Instantané de configuration versionné** : à chaque changement de configuration (famille R, matrice RBAC, modules actifs, catalogues, tarifs, configuration fiscale par versions datées, identité, branding, paramètres notifications, passerelles non secrètes), la mère dépose un instantané **chiffré, daté, daté de son auteur**, conservé sans limite de versions.
6. **Restauration depuis le relais seul** : procédure `restaurer-depuis-le-relais` (mère neuve, clé de clinique, code de secours) qui rejoue instantané et journaux et **vérifie l'empreinte** ; refus nommés (`CLE_INCORRECTE`, `RANG_MANQUANT`, `EMPREINTE_DIVERGENTE`).
7. **Rien n'est supprimé** (RG-14) : « purger » devient « archiver », annulable.
8. **Journalisation RG-12** de chaque ouverture, chaque export et chaque restauration, sans contenu.
9. **Mobiles** : ne reçoivent jamais la configuration (RG-13), inchangé.

**P1**

- Ouverture de la consultation par les rôles autres que superadmin (médecin, DA) avec clé enveloppée par compte (voir Q2).
- Rapport d'intégrité périodique (la chaîne de rangs et d'empreintes est vérifiée sans clé).
- Export de la configuration lisible pour audit (par la mère, jamais par le relais).

**P2**

- Écriture depuis le web par le journal (Q4), consultation hors ligne (PWA avec cache chiffré).

## 8. Droits

| Fonction | Qui |
|---|---|
| Consulter (option A) | rôles du manifeste, écran par écran, lecture seule |
| Déposer instantanés et enveloppes | la mère seule (clé d'appareil) |
| Restaurer depuis le relais | administrateur et DA, avec la clé de clinique, sur une mère neuve |
| Archiver (ex-purge) | administrateur seul, motif obligatoire, annulable |

## 9. Sondes et critères d'acceptation

1. Parité : les vecteurs du domaine donnent les mêmes résultats au poste et au client web (zéro divergence).
2. RBAC : un rôle sans droit sur un écran ne le voit pas, ne le reçoit pas, et l'adresse directe est refusée.
3. Âge : mère éteinte, la page affiche « source injoignable depuis HH:MM » et ne se prétend pas à jour.
4. Conservation : après N instantanés, aucune enveloppe n'a disparu (comptage et chaîne de rangs).
5. Restauration : mère neuve, état identique (empreinte), y compris la configuration et le journal de toutes les familles.
6. Opacité (option A) : le relais, interrogé en base, ne contient aucun nom de table ni donnée lisible (mesure d'entropie, comme l'existant).
7. Aucune suppression physique, aucun accès sans trace.

## 10. Décisions à valider (Direction)

| # | Question | Proposition |
|---|---|---|
| **Q1 (bloquante)** | Option A (règles dans le navigateur, relais opaque) ou option B (relais en clair, règles en PHP) ? | **A** |
| Q2 | Comment la clé de clinique atteint-elle chaque consultant ? (clé unique collée, ou clé enveloppée par compte) | clé enveloppée par compte (P1), clé collée en v1 pour le superadmin seul |
| Q3 | « Sans exception » inclut-il les **secrets** (mots de passe SMTP, clés des fournisseurs SMS, hachés de comptes, code de secours) ? | oui pour les hachés et l'empreinte du code de secours, **chiffrés** dans l'instantané ; les clés de fournisseur restent dans le coffre du relais (il en a besoin pour envoyer) et ne figurent jamais en clair dans une sauvegarde |
| Q4 | La consultation web doit-elle aussi **permettre d'écrire** ? | non en v1 |
| Q5 | Espace disque de l'hébergement : combien de Go pour conserver tout sans purge ? Archive froide hors hébergement mutualisé ? | mesure d'abord ; archive froide sur disque de la mère et copie externe si le quota est atteint |
| Q6 | Durée de conservation légale du journal et de la configuration | illimitée en v1 ; la Direction fixe un horizon d'archivage |
| Q7 | Fraîcheur visée (5 s) acceptable ? | oui |

## 11. Risques

- **Protection des données** : tout choix qui met des données de santé en clair chez l'hébergeur est une décision de la Direction, pas une optimisation.
- **Quota** : « sans purge » grossit sans fin sur un hébergement mutualisé ; le dire avant d'être à court d'espace.
- **Clé de clinique** : la perdre rend la consultation et la restauration impossibles ; la procédure de remise (coffre, courriel à l'adresse du superadmin ou de la DA) existe déjà et reste la seule voie.
- **Compilation web du domaine** : à vérifier par un banc (les 323 vecteurs sur le web) avant de promettre « 100 % ».
