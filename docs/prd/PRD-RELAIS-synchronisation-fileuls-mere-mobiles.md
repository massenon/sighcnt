# PRD : écran « Synchronisation » du panneau du relais (mère, fileuls, mobiles)

Statut : **livré le 13/11/2026** (lot RLS-SYNC), valeurs de départ « à valider » (`DECISIONS-A-VALIDER.md`, section U).
Sources : demande de la Direction du 13/11/2026 (« le relais doit gagner un écran des synchronisations des fileuls, de la mère et des mobiles ») et ses trois décisions : (1) uniquement des compteurs et des horodatages, jamais un identifiant de patient, un nom, un libellé de pièce ni un motif ; (2) accès réservé au superadmin ; (3) historique conservé trois mois, durée modifiable. Doctrine : `docs/specs/SPEC-protocole-synchronisation.md` (§12, §13), `docs/prd/PRD-RELAIS-copie-consultable.md`, ADR-0005 (relais opaque).
Règle de rédaction : pas de tiret cadratin comme ponctuation.

## 1. Problème

Le panneau du relais dit si la mère bat, combien d'appareils elle déclare bloqués et ce qu'une boîte contient en volume. Il ne dit pas **qui est en retard** : quel fileul n'a plus parlé à la mère depuis des heures, combien d'opérations lui restent à reprendre, quel mobile n'a pas relevé sa boîte. Les fileuls ne parlent pas au relais (réseau local de la clinique) : il ne peut pas les voir lui-même. Les mobiles, eux, passent par lui.

## 2. Objectifs

- **O1.** Un écran « Synchronisation », en lecture seule, trois cartes : la mère (dernier battement, séquence, version du protocole si publiée, état), les fileuls (une ligne par poste : nom technique, dernier contact, retard de journal, conflits ouverts, demandes d'import en attente, état), les mobiles (profil et fonction, dernier dépôt, dernière relève, enveloppes en attente, état), plus un historique sur la durée conservée.
- **O2.** La mère publie l'état de ses fileuls dans ses indicateurs de battement, par une **liste blanche de cinq clés** (poste, dernierContact, retardJournal, conflitsOuverts, demandesImportEnAttente). Critère : un test prouve qu'aucune autre clé, aucun texte hors le nom technique du poste, ne part ; le relais **refuse en nommant** tout le reste et n'enregistre rien d'un envoi refusé.
- **O3.** Un historique **à part** (jamais le champ libre des indicateurs, purgé à 48 h), conservé **90 jours par défaut**, réglable de 30 à 365 jours, en base.
- **O4.** Les seuils « en retard » et « silencieux » (mère, fileul, mobile) et le seuil de la boîte qui grossit sont des réglages en base avec un défaut semé, bornés, journalisés.
- **O5.** Le relais SIGNALE (alertes `fileul_silencieux`, `mobile_silencieux`, `boite_grossit`) sans jamais juger un contenu : le détail d'une alerte est un compte, jamais un nom.
- **O6.** Accès **superadmin seul** : un compte qui ne l'est pas n'obtient ni l'entrée de menu ni la route.
- **O7.** L'historique entre dans l'export du relais ; la preuve d'opacité couvre la nouvelle table.

## 3. Non-objectifs

- Aucune règle métier au relais (il ne juge pas un contenu, il compare des âges à des seuils).
- Aucun identifiant de patient, nom, libellé de pièce ni motif, nulle part (écran, historique, alerte, export).
- Rien vers un téléphone : ni l'état du relais, ni les indicateurs, ni l'historique, ni la publication de la mère.
- Pas d'écran équivalent à la maquette ni au poste Flutter (la maquette n'a ni mère, ni fileul, ni relais) : écart E2557.
- Pas de courbes : un tableau compact, par période et par nature.

## 4. Exigences

| N° | Exigence |
|---|---|
| EF-RLS-SYNC-01 | La mère publie `fileuls` dans `POST /mere/indicateurs`, au plus toutes les 2 secondes de calcul, omis (jamais une liste vide) quand sa lecture échoue. |
| EF-RLS-SYNC-02 | Clés permises : `poste` (nom technique, 40 caractères, lettres, chiffres, espace, point, deux-points, tiret, tiret bas), `dernierContact` (ms ou null), `retardJournal` (entier ou null), `conflitsOuverts`, `demandesImportEnAttente` (entiers). Un compteur est un entier positif ou nul : ni texte, ni booléen, ni décimal, ni négatif. |
| EF-RLS-SYNC-03 | Jamais vu : `dernierContact` et `retardJournal` valent `null` (« jamais vu », « non publié »), jamais zéro. |
| EF-RLS-SYNC-04 | Le relais refuse un envoi hors liste par un 422 (`indicateur_cle_inconnue`, `indicateur_valeur_invalide`, `indicateur_forme_invalide`) qui porte le motif, le geste et le chemin de la valeur, sans la recopier ; l'autorisation précède la validation. |
| EF-RLS-SYNC-05 | Un relevé d'historique par appareil à l'intervalle réglé (10 minutes par défaut) : mère, fileuls (à la réception d'un envoi), mobiles (au passage du cron). Colonnes : horodatage, nature, référence, dernier contact, retard de journal, conflits, demandes, enveloppes en attente. |
| EF-RLS-SYNC-06 | Purge par `relais:surveiller` au-delà de la durée réglée ; une valeur hors borne posée en base est ramenée au plancher à la lecture, jamais une purge en dessous. |
| EF-RLS-SYNC-07 | Le relais note la relève d'un mobile : l'heure et le plus haut rang remis ; « enveloppes en attente » = rangs de sa boîte au-delà. |
| EF-RLS-SYNC-08 | États : à jour, en retard, silencieux, jamais vu, inconnu (la mère ne publie plus : l'état de ses fileuls n'est pas établi, aucune alerte de fileul), révoqué, non publié. Jugés sur les seuils réglés. |
| EF-RLS-SYNC-09 | Réglages aux paramètres du panneau : tout ou rien, bornes dites, un seuil de silence supérieur à celui du retard, journal de l'ancienne et de la nouvelle valeur (RG-12). |
| EF-RLS-SYNC-10 | Accès : `users.superadmin` (vrai par défaut), middleware sur tout le panneau (403 journalisé), entrée de menu absente, composant qui refuse hors route. |

## 5. Réglages (valeurs de départ, à valider)

| Réglage | Défaut | Bornes |
|---|---|---|
| Durée de conservation de l'historique | 90 jours | 30 à 365 jours |
| Intervalle entre deux relevés | 10 min | 1 à 60 min |
| Mère en retard / silencieuse | 2 min / 5 min | 1 à 120 / 2 à 1 440 min |
| Fileul en retard / silencieux | 30 min / 240 min | 5 à 1 440 / 10 à 10 080 min |
| Fileul en retard au-delà de (journal) | 500 opérations | 10 à 100 000 |
| Mobile en retard / silencieux | 720 min / 2 880 min | 30 à 10 080 / 60 à 43 200 min |
| Boîte qui grossit au-delà de | 200 enveloppes | 10 à 100 000 |

## 6. Risques et limites

- Le nom technique d'un poste est l'étiquette de l'appairage, choisie par l'administrateur : la liste blanche prouve sa **forme**, pas son intention (un nom de personne y passerait).
- Les fileuls sont vus **par la mère** : une mère silencieuse rend leur état inconnu.
- Le banc éprouve le protocole sur des fileuls de référence ; le relais cPanel réel, deux machines et une charge réelle ne sont pas vérifiés.
