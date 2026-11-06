# Panne de connexion : ce qui continue, ce qui attend, ce qui se passe au retour

Exigence de la Direction (06/11/2026) : quand Internet tombe, ou quand le réseau local qui relie les postes à la mère tombe, **les activités des fileuls et de la mère continuent**. Ce guide dit ce qui continue, ce qui attend, ce qui se passe au retour, et pour chaque affirmation la preuve qui existe dans le dépôt (un scénario du banc `packages/sync/banc`, un test Flutter `apps/poste/test`, ou la spécification `docs/specs/SPEC-protocole-synchronisation.md`). Une affirmation sans preuve n'y figure pas.

Rappel de la cible (ADR-0005, ADR-0006) : chaque poste a sa base chiffrée et travaille **d'abord en local**. La mère est le poste de référence de la clinique (réseau local) ; le relais en ligne porte les mobiles, les échanges entre postes et la copie consultable ; il ne voit jamais un clair.

## 1. Ce qui CONTINUE sur un fileul coupé de la mère

| Ce qui continue | Pourquoi | Preuve |
|---|---|---|
| Saisir : dossiers, rendez-vous, consultations, admissions | Le magasin du poste est local ; les écrans ne lisent aucun réseau | `apps/poste/test/panne_connexion_test.dart` (mère arrêtée : un dossier est saisi, puis remonte au retour) ; tous les tests d'écran tournent sans réseau (par exemple `m8_caisse_test.dart`) |
| Encaisser à la caisse, imprimer reçus et factures | Caisse et impression sont locales | `m8_caisse_test.dart`, `m8_caisse_file_test.dart`, `impression_test.dart`, `impression_systeme_test.dart` |
| Sortir du stock, dans la **part** du poste (RG-03) | Hors ligne, un poste ne sort que sa part (stock connu divisé par le nombre de postes) ; au-delà, refus nommé ; jamais négatif | `pont_regles_test.dart` « HORS LIGNE : un poste ne sort que sa part… » et « un FILEUL dont la mère est injoignable est hors ligne même si sa base locale répond » ; `panne_connexion_test.dart` |
| Numéroter dans sa **plage** (RG-01) ; plage épuisée : numéro **provisoire**, jamais inventé | Plages réservées par poste, réconciliées au retour sans toucher un numéro déjà attribué | `plages_codes_test.dart` « plage épuisée hors ligne : jamais de numéro inventé, un code PROVISOIRE » ; spec §8 |
| Voir où on en est : pastille **Hors ligne depuis N min** | Jamais un voyant muet ; « depuis » compte depuis le début de la coupure | `bout_en_bout_test.dart`, `source_sync_test.dart` (« depuis » compte depuis le DÉBUT de la coupure), `pastille_test.dart`, `moteur_fileul_test.dart` |
| Garder ses gestes dans une **file persistée**, même après coupure de courant ou arrêt brutal | La file SQLite survit au redémarrage ; rien n'est perdu ni dupliqué | banc R19 (SIGKILL : les opérations sont toujours en attente, les dossiers visibles hors ligne, puis tout part sans doublon) ; banc P2 |
| En mode pair (ADR-0006), s'échanger entre postes **sans la mère**, par le relais | La règle de fusion tourne sur chaque poste | banc P1 (mère éteinte : trois fileuls convergent, la DA valide sur un autre poste), P2 (poste hors réseau puis tué) |
| Envoyer un courriel : s'il part, tout de suite ; sinon il **attend en file** et repart seul | Essai immédiat, puis reprises à 1 min, 5 min, 30 min, 2 h, 12 h | `file_courriels_test.dart` (essai immédiat prouvé au puits SMTP ; hors ligne : en file avec l'étape « connexion » ; retour : reçu une fois) |

## 2. Ce qui CONTINUE sur la mère coupée d'Internet

| Ce qui continue | Preuve |
|---|---|
| La clinique entière : les fileuls synchronisent avec la mère par le réseau local comme si de rien n'était | banc R6 « Internet coupé : le poste continue de synchroniser avec la mère » |
| Le retard de réplication vers le relais est **visible** sur la console | banc R6 « le retard de réplication est VISIBLE sur la console » |
| Internet rétabli : la mère **rattrape seule** le relais ; une mère muette trop longtemps déclenche une alerte au relais | banc R6 (« Internet rétabli : la mère rattrape SEULE », « mère muette > seuil : ALERTE au relais ») |

## 3. Ce qui ATTEND (et le dit)

| Ce qui attend | Pourquoi | Preuve |
|---|---|---|
| Une validation à faire par **un autre poste** (DAF, Direction) | Elle passe par la mère, ou par le relais en mode pair : sans réseau, le bon reste « soumis » | banc P1 (la validation revient au demandeur par la synchronisation) |
| La configuration de la mère (tarifs, rôles, identité) | Famille R : la mère seule l'écrit, le fileul la **reçoit** ; un fileul refuse d'écrire la configuration en le disant | `configuration_sync_test.dart` (« le fileul REFUSE d'écrire la configuration, en disant pourquoi ») |
| Les mobiles | Ils ne parlent qu'au relais, jamais au réseau local ; coupure de courant : la réception de secours saisit sur mobile, ses dossiers portent des codes de **sa** plage, un doublon possible attend l'arbitrage | banc R15, R10 |
| La copie consultable au relais | Déposée au tour suivant, rangs contigus, rien perdu après un arrêt brutal | banc P5 (`scenarios-copie.js`) |
| Un poste **révoqué** pendant qu'il travaillait hors ligne | Au retour il se **suspend** (pastille « suspendu »), conserve ses données, son opération reste en attente | banc R7 |

## 4. Ce qui se passe au RETOUR

| Au retour | Preuve |
|---|---|
| Tout ce qui a été saisi hors ligne **remonte, une seule fois** ; l'auteur ne reçoit pas d'écho | `panne_connexion_test.dart`, banc R19, banc P2, `pont_activite_test.dart` (« une fiche créée sur un poste arrive aux autres, une seule fois ») |
| Deux postes ont touché la même fiche : champs différents fusionnés, même champ **marqué en conflit**, jamais un « dernier gagne » muet | `pont_activite_test.dart`, banc P3, spec §9 |
| Deux dossiers au même code, deux pièces au même numéro, deux admissions sur un lit : **marqués**, jamais renumérotés ni effacés | `pont_regles_test.dart`, `pont_activite_test.dart` (RG-01) |
| Deux postes ont sorti les dernières unités hors ligne : le négatif est **détecté et marqué** (RG-03), jamais effacé | `pont_regles_test.dart` « deux dernières unités sorties hors ligne par deux postes… » |
| En mode pair, la mère revenue relève les journaux, attribue le **seq qui fait foi**, laisse le conflit marqué pour la Direction | banc P4 |
| La pastille redit « Synchronisé », les parts de stock cessent de s'appliquer | `panne_connexion_test.dart`, `pont_regles_test.dart` |

## 5. Limites dites

- Ces preuves tournent dans un seul ordinateur (processus réels, réseau local simulé). Deux postes physiques, un vrai routeur coupé, Windows et Android n'ont pas été exercés dans l'environnement de rédaction.
- Un courriel interrompu entre l'envoi et la réponse du serveur peut partir deux fois (« au moins une fois ») ; le `Message-ID` est stable pour que la messagerie du destinataire dédoublonne.
- La file de courriels n'avance que poste ouvert (minuterie dans l'application, pas de service Windows).
- Hors ligne, la part de stock d'un poste est calculée sur le stock **connu** et le nombre de postes **connus** : un poste qui n'a jamais vu les autres se croit seul.

Rejouer les preuves : `cd packages/sync && service postgresql start && node banc/run.js R6 R7 R15 R19 P1 P2 P4 P5` ; `cd apps/poste && flutter test test/panne_connexion_test.dart test/pont_regles_test.dart test/plages_codes_test.dart test/file_courriels_test.dart`.
