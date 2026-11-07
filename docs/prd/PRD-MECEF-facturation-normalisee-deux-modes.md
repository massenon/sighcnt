# PRD : Facturation normalisée MECeF pour la Clinique Nassièra Too, deux modes (boîtier CC300 au poste, e-MECeF en ligne), maquette, poste, relais

Statut : **proposé le 07/11/2026** à la demande de la Direction (« lire la documentation de facturation MECeF et dire comment l'implémenter pour Nassièra Too »). Les décisions de la section 11 sont à valider avant le premier code d'intégration.
Note de méthode : le skill `sdlc-kit:prd` exige un coffre `.sdlc` absent de ce dépôt ; ce PRD suit la convention du dépôt (`docs/prd/`).
Sources : `docs/annexes/` : le fichier de documentation remis le 07/11/2026 (`documentation_facturation_MeCef.txt`, lu en entier) ; le dépôt `issotina/eltrade-cc300-driver` (lu le 07/11/2026, pilote Go du boîtier Eltrade CC300) ; ADR-0003 (section « Le boîtier MECeF ») ; `CLAUDE.md` (régime de TVA, MECeF partielle, avoirs) ; relevés du code le 07/11/2026.
**Avertissement sur la documentation remise** : elle décrit le travail fait pour **d'autres projets** (un paquet Laravel `laraSgmefQR`, des applications « Le Gîte » et « TATACORA », un dépôt `claude/sleepy-dijkstra-uvt68t`, 3071 tests Laravel et 4105 tests Flutter qui ne sont **pas ceux de ce dépôt**). Elle sert ici de **source d'idées et de mises en garde**, pas de spécification de Nassièra Too : rien de ce qu'elle affirme comme « fait » ne l'est dans ce dépôt, et rien de ce qu'elle dit des adresses de l'API de la DGI n'est confirmé par un document officiel.
Règle de rédaction : pas de tiret cadratin comme ponctuation. Doctrine : maquette d'abord, puis vecteurs, domaine Dart, poste, relais ; **le numéro fiscal vient toujours du boîtier ou de la DGI, jamais fabriqué** ; une pièce émise ne se réécrit jamais (correction par avoir) ; RG-10, RG-12, RG-14.

## 1. Problème

**Ce qui existe (relevé le 07/11/2026).**
- La maquette et le poste **simulent** la facturation normalisée (écrans `mecef-*`, file en ligne simulée, numéro de série et QR de démonstration, bandeau DEMO). Aucun appel réel à un boîtier ni à la DGI.
- La décision d'architecture (ADR-0003, validée par la Direction le 06/11/2026) : la clinique utilise **un boîtier physique** (Eltrade CC300), **branché à la caisse** et non au hub ; **un seul boîtier** ; l'IFU est unique ; le numéro fiscal fait foi quand il vient du boîtier.
- Le régime fiscal appliqué (facture de référence certifiée) : TVA à 0 pour les produits de santé exonérés, AIB 1 %, base MECeF partielle = part réglée par le patient seulement (ni part assureur, ni remises).
- Le dépôt du pilote `eltrade-cc300-driver` a été lu : serveur HTTP local (`localhost:38917`, routes `/check`, `/info`, `/bill`), trames série vers le boîtier (USB, 115 200 bauds). **Défauts relevés** (à ne pas reprendre) : montants en `float32`, réponse 200 même en cas d'échec, aucune reprise sans doublon, aucun verrou entre deux encaissements, aucune authentification, boucle sans fin possible sur réponse tronquée, aucun test.

**Ce qui manque.** Un mode de facturation normalisée **réel** : (1) le **boîtier CC300** au poste de caisse ; (2) **e-MECeF** en ligne comme seconde voie ; (3) un **réglage** qui choisit le mode ; (4) la représentation d'une vente « simple » ou « normalisée » ; (5) la **reprise sans doublon fiscal** ; (6) la correction par **avoir** transmis comme facture d'avoir ; (7) des **tests** contre un faux boîtier et un faux serveur de la DGI.

## 2. Ce que la documentation remise apporte (et ce que Nassièra Too en retient)

| Idée de la documentation | Reprise pour Nassièra Too |
|---|---|
| **Prix entiers en FCFA** : tout montant envoyé à la DGI est un entier calculé en un seul endroit ; la remise se répartit sur les lignes, l'écart d'arrondi est absorbé par la plus grande ligne ; une quantité décimale reste possible, un prix décimal non | **Oui, exigence P0.** Cela corrige aussi le `float32` du pilote. Une seule fonction d'arrondi au domaine Dart, vecteurs tirés de la maquette |
| **Choix à la vente** : « Facture simple » (jamais transmise) ou « Facture normalisée » | **À trancher (Q1)** : pour une clinique, la loi peut exiger la normalisation de toute vente ; ce choix vient d'un autre commerce |
| **Fenêtre client** pour une facture normalisée : IFU du client, nom, taux AIB (5 % par défaut, 1 %, aucun) | Reprise partielle : IFU et nom de l'acheteur, **AIB à 1 % par défaut** (régime déjà appliqué dans cette maquette), 5 % et aucun en choix. Le taux par défaut est à confirmer (Q4) |
| **Hors ligne : la vente part « en attente » et le serveur la transmet à la synchronisation** | Oui, mais seulement pour **e-MECeF** ; avec le **boîtier**, la certification est locale et ne dépend pas d'Internet |
| **Frais de livraison** : ligne « Frais de livraison » sur la facture normalisée | Hors périmètre (la clinique ne livre pas), sauf décision contraire |
| **Réglages e-MECeF** : mode, IFU 13 chiffres, adresse de l'API, opérateur, jeton masqué, bouton « Tester la configuration » avec résultat en français (« Jeton refusé (401) », « Configuration valide ») | **Oui**, dans Paramètres, au poste et au web (voir section 6). L'adresse de l'environnement d'essai **n'est pas inventée** : elle est saisie par l'administrateur |
| **Deux temps pour e-MECeF** : création (`POST /invoice`) puis confirmation (`PUT /invoice/{uid}/confirm`) qui rend le code MECeF, le QR, la date, les compteurs, le NIM ; une facture non confirmée **expire après 2 minutes** | **Oui** si la Direction active e-MECeF ; la confirmation suit la création dans la foulée |
| **Classement des erreurs** (authentification, limite de débit, délai dépassé, réseau) et motifs en français | **Oui** (refus nommés : code, motif, geste) |
| **Avoir** (FA) avec référence de la facture d'origine | **Oui** : `rt = FA`, `rn = NIM-TC` pour le boîtier (déjà prévu au schéma du pilote) ; avoir de la maquette `SIGH.emettreAvoir` conservé |
| **Jeton JWT chiffré, masqué, jamais renvoyé au navigateur, jamais journalisé** | **Oui**, selon la décision de sécurité (secrets saisis au panneau, chiffrés, jamais relus). **Le jeton ne se colle jamais dans une conversation** |
| « Le relais serveur vers le PC est écarté » | Ne s'applique pas : ici l'appel e-MECeF passe par le **relais**, seul à porter le jeton et à être joignable |

## 3. Objectifs mesurables

- **O1.** Un encaissement à la caisse du poste produit une **facture normalisée réelle** : numéro fiscal, NIM, code de sécurité et QR issus du boîtier (ou de la DGI), imprimés sur la pièce. Critère : essai sur un vrai boîtier et un vrai compte, plus banc complet contre faux pilote et faux serveur DGI.
- **O2.** **Aucun doublon fiscal** : deux envois d'une même vente, une réponse perdue, une coupure en cours d'émission ne produisent jamais deux numéros fiscaux. Critère : sondes de coupure à chaque étape, mutations.
- **O3.** **Aucun montant décimal** n'est envoyé ; les totaux égalent la somme des lignes et le total des paiements. Critère : propriété vérifiée sur un millier de ventes tirées au hasard, vecteurs de la maquette.
- **O4.** Le **mode** (désactivé, boîtier, e-MECeF) est un réglage d'administrateur, un seul actif à la fois, au poste et au web. Critère : changer de mode ne réécrit aucune pièce émise.
- **O5.** Une facture normalisée est **figée** : sa correction passe par un avoir transmis lui aussi. Critère : tentative de modification refusée au moteur, avec le motif nommé.
- **O6.** Les **secrets** (jeton e-MECeF) ne figurent ni au poste, ni dans le dépôt, ni dans un journal, ni dans une sauvegarde en clair.

## 4. Hors périmètre de la v1

- Déclaration de TVA automatisée vers la DGI (la maquette porte la liasse, pas la télédéclaration).
- Plusieurs boîtiers (un seul, décision du 06/11).
- Émission depuis un smartphone (aucune émission fiscale hors de la caisse).
- Facturation « simple » non fiscale, tant que la Direction et le cabinet n'ont pas tranché Q1.

## 5. Les deux modes

**Mode « Boîtier CC300 (poste) ».** Le poste de caisse parle au pilote local par HTTP (`localhost:38917`, adresse réglable sans recompiler). Le pilote est **réécrit en Dart** derrière le port `Mecef` (adaptateur « boîtier ») : encodeur de trames, somme de contrôle, commandes d'état, de début de facture, d'ajout d'article, de paiement, de fin ; **verrou unique** (une seule émission à la fois) ; **vérification du contenu** de la réponse (jamais confiance à un 200) ; **reprise** : avant tout renvoi, comparaison du compteur du boîtier pour ne pas facturer deux fois, état « à vérifier » si l'on ne peut pas trancher, jamais de rejeu automatique. Le résultat remonte au serveur par la synchronisation, le serveur ne parle jamais au boîtier. Fonctionne **sans Internet**.

**Mode « e-MECeF (en ligne) ».** Le **relais** (qui porte le jeton chiffré) appelle l'API de la DGI : création puis confirmation, dans la foulée (délai de 2 minutes). Le poste demande l'émission au relais ; hors ligne, la vente part « en attente » et le relais transmet au retour. **Ne fonctionne pas sans Internet**, ce qui en fait la voie de secours et non le chemin principal d'une clinique qui subit des coupures.

**Mode « Désactivé ».** Aucune transmission, bandeau DEMO conservé.

## 6. Exigences

**P0**

1. **Réglage du mode** (`mecef-config`, administrateur et DA) : sélecteur à trois valeurs, un seul actif ; section « Facturation normalisée » dans Paramètres, au poste et au web.
2. **Section boîtier** (poste) : adresse du pilote, bouton **« Tester le boîtier »** (lit l'état, jamais ne crée de facture) avec résultat en français.
3. **Section e-MECeF** (web et poste en lecture) : IFU de 13 chiffres validé, adresse de l'API (https exigé, **non préremplie** tant qu'aucune source officielle ne la donne), opérateur, **jeton saisi au panneau**, chiffré, masqué (seule la date d'enregistrement s'affiche), bouton **« Tester la configuration »** (appel en lecture, aucune facture créée) : « Configuration valide », « Jeton refusé (401) », etc.
4. **Montants entiers** : une fonction unique au domaine, remises réparties, écart d'arrondi sur la plus grande ligne ; quantités décimales admises, prix non ; totaux contrôlés avant tout envoi (`TOTAL_INCOHERENT`).
5. **Fenêtre « Facture normalisée »** à l'encaissement : IFU et nom de l'acheteur, AIB ; ces données sont rangées dans la vente, imprimées, transmises.
6. **Reprise sans doublon** (sections 5 et 8) ; états : `simple` (selon Q1), `normalisee`, `en_attente`, `a_verifier`, `refusee`, `expiree`.
7. **Avoirs** : facture d'avoir transmise (FA, référence NIM-TC) ; plafond du cumul d'avoirs à la facture ; l'avoir d'une pièce normalisée est normalisé.
8. **Sécurité** : secrets chiffrés, jamais relus, jamais journalisés ; refus nommé `SECRET_NON_DEFINI` ; entrée de journal d'audit sans secret (RG-12).
9. **Impression** : QR, NIM, code de sécurité, IFU, compteurs imprimés **seulement** sur une facture réellement normalisée ; sinon le bandeau DEMO.
10. **Tests** : faux boîtier (simulateur de trames) et faux serveur DGI (succès, jeton refusé, limite de débit, délai dépassé, doublon, réponse perdue), mutations.

**P1**

- Réimpression d'un duplicata (commande de copie du boîtier) ; panne de papier ; réglage de l'horloge.
- Rapport d'activité fiscal (compteurs du boîtier, factures non transmises à la DGI).
- Reprise d'un lot de ventes « en attente » avec progression.

**P2**

- Second boîtier, taxe de séjour, taxes spécifiques (hors activité d'une clinique).

## 7. Droits

| Fonction | Qui |
|---|---|
| Régler le mode, le pilote, le jeton | administrateur, DA |
| Lire la configuration (sans jeton) | direction |
| Encaisser en normalisé | caissier, caissier dispensateur (droits de la caisse existants) |
| Retransmettre une vente refusée | caissier (une seule fois, motif nommé), DA |
| Émettre un avoir | comptable, DA, administrateur (le caissier n'émet pas : fiche RBAC12) |

Une commande interdite est **absente**. La configuration du jeton n'est jamais montrée.

## 8. Reprise sans doublon (cœur du risque)

Pour le boîtier : verrou unique ; avant d'émettre, lire le compteur ; après une réponse perdue, relire le compteur : s'il a avancé d'une facture, la vente est **réconciliée** avec cette facture (comparaison du total et de l'horodatage) ; s'il n'a pas avancé, renvoi possible ; si l'on ne peut pas trancher, état `a_verifier`, **aucun rejeu automatique**, décision humaine nommée. Pour e-MECeF : la création porte un identifiant de vente stable ; une vente déjà normalisée n'est **jamais** retransmise ; une facture non confirmée expirée est recréée seulement si la DGI confirme qu'elle n'existe pas. Chaque étape écrit son état avant d'appeler l'appareil, pour qu'un redémarrage reprenne au bon endroit.

## 9. Sondes et critères d'acceptation

1. Encaissement normalisé au boîtier simulé : numéro, NIM, QR rangés, pièce figée, impression complète.
2. Coupure avant l'envoi, après l'envoi, après la réponse : jamais deux numéros fiscaux.
3. Réponse 200 avec corps d'échec du pilote : traité comme un échec nommé.
4. Montants : jamais de décimale envoyée ; totaux égaux ; propriété sur ventes tirées au hasard.
5. Mode e-MECeF contre faux serveur : création puis confirmation dans la foulée ; jeton refusé : refus nommé ; limite de débit : report ; délai dépassé : `expiree`.
6. Avoir : référence correcte, plafond, avoir normalisé.
7. Secrets : jamais relus (API, collection, journal, export de base).
8. Droits : caissier sans accès à la configuration ; commande d'avoir absente pour lui.
9. Mode : changement sans réécriture des pièces émises.
Mutations (au moins 8) : verrou retiré, vérification du corps retirée, doublon accepté, arrondi décimal, secret relu, retransmission d'une pièce normalisée, avoir sans plafond, mode non exclusif.

## 10. Plan en lots (détail dans un plan à écrire après la décision Q1)

| Lot | Contenu | Où |
|---|---|---|
| M0 | Décisions Q1 à Q8 ; fiche technique du boîtier et protocole `MECeF_MCF_SFE_Protocole_v2` ; vérification des adresses de l'API auprès de la DGI | Direction, fournisseur |
| M1 | Montants entiers (fonction unique, vecteurs de la maquette), fenêtre « Facture normalisée », états de pièce | maquette puis domaine |
| M2 | Réglage du mode et sections boîtier et e-MECeF, boutons de test | maquette, poste, relais |
| M3 | Port `Mecef` et adaptateur boîtier en Dart, simulateur de trames, verrou, reprise sans doublon | domaine, poste |
| M4 | Avoirs normalisés | maquette, domaine, poste |
| M5 | e-MECeF au relais : création, confirmation, erreurs classées, file « en attente » | relais, poste |
| M6 | Impression conditionnelle, sondes et mutations, recette avec le vrai boîtier et un vrai compte | tous |

## 11 bis. Décisions de la Direction du 07/11/2026 (reçues)

**Q1 résolue : TOUTE VENTE EST NORMALISÉE À LA CLINIQUE.** Il n'y a donc **pas de « facture simple »** : le choix « simple ou normalisée » de la documentation d'un autre projet est **retiré**. Quand le mode n'est pas « Désactivé », chaque vente encaissée passe par le boîtier (ou e-MECeF). La fenêtre « Facture normalisée » ne sert plus qu'à saisir l'IFU et le nom de l'acheteur, et le taux d'AIB. Conséquences : la déclaration de TVA retient toutes les ventes ; une vente ne peut être remise que normalisée ; l'état `simple` disparaît (restent `normalisee`, `en_attente`, `a_verifier`, `refusee`, `expiree`) ; en mode « Désactivé » (démonstration seulement) le bandeau DEMO reste.

## 11. Décisions à valider (Direction)

| # | Question | Proposition |
|---|---|---|
| **Q1 (bloquante)** | Une **facture simple** (non transmise) peut-elle exister à la clinique, ou **toute vente** doit-elle être normalisée ? La documentation remise fait de la facture simple le défaut : c'est le cas d'un autre commerce. | à confirmer avec le cabinet FAGUEZ et la DGI ; en attendant, **toute vente encaissée est normalisée** quand le mode n'est pas « Désactivé » |
| Q2 | Mode de départ en production | **Boîtier CC300** (coupures d'Internet, un seul boîtier) ; e-MECeF activé seulement en secours |
| Q3 | Les adresses de l'API de la DGI (essai et production) | **fournies par la DGI ou le cabinet** ; aucune adresse préremplie |
| Q4 | Taux d'AIB par défaut | **1 %** (régime de la facture certifiée de référence) ; 5 % et aucun en choix |
| Q5 | IFU du client obligatoire ? | facultatif pour un particulier, obligatoire pour une compagnie d'assurance |
| Q6 | Une vente « en attente » (e-MECeF) peut-elle être remise au patient ? | non : seul le reçu provisoire, la facture normalisée ensuite |
| Q7 | Qui peut retransmettre une vente refusée ? | caissier une fois, puis DA |
| Q8 | Un avoir sur une facture normalisée par le boîtier passe par le même boîtier ? | oui, et seulement au poste de caisse |

## 12. Risques

- **Légal et fiscal** : tout ce qui touche la DGI (obligation de normaliser, taux AIB, régime de TVA exonéré) est une décision du cabinet et de la Direction, pas de l'équipe ; la maquette marque « à confirmer ».
- **Protocole du boîtier** : le seul protocole connu vient d'un dépôt tiers non officiel ; la fiche technique est à obtenir (M0). Un bit non confirmé reste marqué « à confirmer sur le boîtier ».
- **Un seul boîtier** : en panne ou sans papier, la caisse ne certifie plus ; la procédure de secours (e-MECeF, ou encaissement différé puis régularisation) est à écrire avant la mise en service.
- **Jeton e-MECeF** : sa fuite permet d'émettre des factures au nom de la clinique ; le jeton n'est jamais collé dans une conversation ni un message.
- **Documentation d'autres projets** : ne pas importer comme acquis les « tests verts » ou les « fonctions faites » de ces projets.
