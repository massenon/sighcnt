# PRD : Validation par modale de mise à jour, et fin du statut « à valider » une fois l'élément enregistré

Statut : **brouillon du 08/11/2026**, à arrêter par la Direction (questions de la section 10).
Sources : demande de la Direction du 08/11/2026 (« tout statut de module à valider doit être implémenté avec une modale de mise à jour du bouton Valider, qui permettra de transformer le statut à valider en validé, ou en enregistrant : on ne doit plus avoir le statut à valider ») ; moteur de validation commun livré le 07/11/2026 (`PR.validerReferentiel`, `PR.remettreAValider`, `PR.FAMILLES_A_VALIDER`, 14 familles, centre `adm-validations`, scénarios Vague 91 et Vague 92) ; CLAUDE.md vagues 49 et 51 (la Direction tranche ce qui est de son ressort, le professionnel nommé garde le sien).

## 1. Problème

Aujourd'hui un référentiel marqué « à valider » (proposition tirée d'un document, valeur d'attente) ne change d'état que par un geste séparé : le bouton **Valider**, posé par ligne ou par fiche. Deux défauts réels au guichet :

1. **Le geste de valider et le geste de corriger sont séparés.** Un professionnel qui ouvre une borne de laboratoire pour la corriger doit l'enregistrer, puis chercher le bouton Valider. Pire : depuis le lot du 07/11, **toute modification remet l'élément à valider** (même quand elle est faite par le validateur lui-même), si bien que le statut « à valider » revient sans cesse et ne se vide jamais.
2. **Le statut « à valider » ne disparaît pas** après un enregistrement par un profil habilité : l'écran continue de dire « proposition » sur une valeur que le professionnel vient de relire et de saisir.

## 2. Objectifs et non-objectifs

Objectifs (un critère de recette chacun) :
- O1. Dans la **modale de mise à jour** de chaque élément à valider, un choix explicite **Valider** (transforme « à valider » en « validé ») est offert aux seuls profils de la famille. Critère : sondé sur les 14 familles, bouton absent hors famille.
- O2. **Enregistrer par un profil de la famille valide** : après l'enregistrement, l'élément porte `valideLe`, `validePar`, `valideRole` de l'auteur et **plus aucune mention « à valider »**, nulle part (badge, centre, tableau de bord, impression). Critère : zéro occurrence de « à valider » à l'écran sur un élément enregistré par un validateur.
- O3. La validation reste **journalisée** (RG-12, avant/après) et **unitaire** : jamais de validation en masse.
- O4. Le centre des validations ne compte plus un élément validé en enregistrant.

Non-objectifs :
- Ne pas valider **à la place** d'un professionnel nommé (arbitrage de la vague 49) : la Direction ne signe pas une borne de laboratoire.
- Ne pas transformer les 14 familles en un seul droit : les rôles par famille (`FAMILLES_A_VALIDER`) restent la source.
- Hors périmètre : validation biologique des résultats d'analyse (verrou du laboratoire, autre mécanisme), validation comptable des écritures (brouillon vers validé, autre mécanisme).

## 3. Utilisateurs et rôles

| Profil | Voit | Fait | Ne voit pas |
|---|---|---|---|
| Rôle de la famille (ex. biologiste pour les bornes, médecin pour les pathologies, Direction/DA/admin pour tarifs et modèles) | l'élément, son état, la modale de mise à jour avec le choix Valider | valide, ou enregistre et valide dans le même geste | rien de plus que son profil |
| Rôle qui ouvre l'écran sans appartenir à la famille | l'élément et son état | **selon la décision Q2** | le choix Valider (absent, jamais grisé) |
| Réception, caissier, stock, etc. | ce que leur matrice permet | rien | aucun état de validation d'un référentiel hors de leur périmètre |

Une restriction s'annonce : le bandeau ou la note de l'écran dit quel profil valide cet élément (déjà le cas via `profilsFamille`).

## 4. Parcours

1. Un profil de la famille ouvre l'élément (clic sur la ligne ou **Modifier**).
2. La modale de mise à jour s'ouvre. En pied : **Enregistrer** et, si l'élément est « à valider », **Valider**.
3. **Valider** seul : l'élément reste tel quel, son état passe « validé » (marque, date, auteur, rôle), ligne de journal.
4. **Enregistrer** (modifié ou non) par un profil de la famille : mêmes effets que 3 sur l'état, plus l'écriture des valeurs modifiées, **une seule ligne de journal** avec avant/après.
5. Le badge, le centre, le tableau de bord se recalculent sans « à valider ».

## 5. Exigences fonctionnelles

- **EF-VAL-01** : chaque écran branché au moteur (les 14 familles) offre, dans sa modale de mise à jour, le choix **Valider** quand l'élément est « à valider » et que le profil est de la famille. Commande absente sinon. Critère : scénario par famille, rôle de la famille / hors famille.
- **EF-VAL-02** : **Enregistrer par un profil de la famille valide.** `PR.remettreAValider` n'est **plus appelé** par un enregistrement fait par un validateur ; il l'est seulement pour un enregistrement fait par un profil **hors famille** (voir Q2). Critère : éditer puis enregistrer sous le rôle de la famille laisse l'élément validé, auteur et date de l'enregistrement.
- **EF-VAL-03** : un **élément créé** par un profil de la famille naît validé ; créé par un profil hors famille, il naît « à valider » (Q2). Critère : création d'un acte sous Direction, sous un profil hors famille.
- **EF-VAL-04** : **aucune occurrence de « à valider »** (badge, note, tableau, impression) sur un élément validé ; les notes d'écran qui disent « proposition à valider » ne s'affichent que tant qu'il reste des éléments en attente. Critère : sonde de texte sur les 14 écrans après enregistrement.
- **EF-VAL-05** : le geste est **journalisé** une seule fois (RG-12) : avant (état et valeurs), après, auteur, rôle, date. Critère : un enregistrement ⇒ une ligne `Validation` ou `Modification` portant l'état validé.
- **EF-VAL-06** : le refus se **nomme** (code, motif, geste) : `VALIDATION_RESERVEE`, `DEJA_VALIDE` (le choix Valider est absent si déjà validé, le refus existe pour l'appel direct), `TARIF_ABSENT` (un acte ou une analyse sans tarif ne se valide pas, un tiret n'est pas un zéro).
- **EF-VAL-07** : sur un **fileul**, la commande est absente et le geste refusé (`CONFIGURATION_DE_LA_MERE`) pour les familles qui voyagent mère vers fileuls ; sur la mère, le geste suit le journal de configuration. Critère : sonde dédiée (absente aujourd'hui, voir section 9).
- **EF-VAL-08** : même comportement au **poste Flutter**, mêmes vecteurs que la maquette (`validation.json`), mêmes refus.

## 6. Données

- Aucune collection nouvelle. Champs existants : `aValider`/`tarifProvisoire` (marquage), `valideLe`, `validePar`, `valideRole` (trace), collection `validationsReferentiels` (VRF-<cible>) pour les pièces portées par le code.
- Changement de **règle** et non de forme : `remettreAValider` n'est appelé que pour une modification hors famille. Incrément de `VERSION` seulement si un seed change (les éléments créés par la clinique naissent validés par un validateur).
- Distinction conservée : donnée importée du cadrage (marquée), donnée opérationnelle, règle configurée par l'administrateur.

## 7. Hors ligne et synchronisation

Famille de fusion : **fiche descriptive** (dernier écrivain gagne **sur l'état de validation**, mais une validation n'est jamais perdue par une modification concurrente d'un autre champ). Le pont ne porte pas encore ces familles : `validationsReferentiels` voyage de la mère vers les fileuls avec la configuration (famille R), un fileul ne l'écrit pas. Si deux validateurs valident sans hub, l'état reste « validé » (aucun conflit à régulariser) ; si l'un valide et l'autre modifie hors famille, la modification hors famille repasse l'élément « à valider » (Q2). L'écran dit « en suspens » tant que la mère n'a pas reçu le geste du fileul, sans jamais afficher « à valider » à tort.

## 8. Impression et états

Les états imprimés qui citent un référentiel ne portent plus « proposition à valider » pour un élément validé, et la portent pour un élément en attente (mention « à valider par <profil> »). Aucun nouveau gabarit.

## 9. Ce qui n'est pas documenté ou pas vérifié

- La liste des **profils par famille** (`FAMILLES_A_VALIDER`) est une proposition arrêtée le 07/11 pour certaines familles et à valider par la Direction pour d'autres (modèles de badge, jeux d'import).
- Le refus `CONFIGURATION_DE_LA_MERE` sur fileul **n'a pas de test**.
- Le cas d'une fiche `VRF-<cible>` **archivée** qui existe déjà crée un doublon (même comportement dans la maquette et au poste).
- L'inventaire des **éditeurs par famille** (qui peut modifier) n'est pas dressé contre celui des **validateurs** : il fixe l'ampleur de Q2.

## 10. Questions ouvertes pour la Direction

| N° | Question | Option recommandée |
|---|---|---|
| Q1 | « En enregistrant on ne doit plus avoir le statut à valider » vaut-il **pour les seuls profils de la famille** ? | Oui : c'est la lecture qui respecte « la Direction ne signe pas à la place du professionnel ». |
| Q2 | Un profil qui **peut modifier mais n'est pas de la famille** (ex. un administrateur sur une borne de laboratoire) : (a) sa modification est refusée, la commande Modifier est absente ; (b) il enregistre et l'élément repasse « à valider » ; (c) il enregistre une **proposition de modification** que le validateur accepte ou refuse. | (b) pour rester simple et sûr : l'état « à valider » ne subsiste alors que pour une modification non validée par un professionnel. (c) est plus juste mais plus lourd. |
| Q3 | Les éléments **semés** (propositions tirées d'un document, valeurs d'attente) restent-ils « à valider » jusqu'au premier enregistrement ou à la première validation par un profil de la famille ? | Oui : on ne valide pas à la place du professionnel, la première relecture suffit. |
| Q4 | Faut-il un **motif** obligatoire quand le validateur enregistre une valeur modifiée (traçabilité d'une correction de borne ou de tarif) ? | Oui pour les valeurs chiffrées (bornes, tarifs, barème), non pour les libellés. |
| Q5 | Le choix **Valider** dans la modale s'applique-t-il aussi aux **créations** (nouvel acte, nouvelle pathologie) faites par un validateur : elles naissent validées, sans second geste ? | Oui (EF-VAL-03). |

## Lots proposés (après arbitrage)

| Lot | Contenu | Où |
|---|---|---|
| V1 | Moteur : `remettreAValider` limité aux modifications hors famille, création validée par un validateur, nouvelles sondes (Vague 95), mutations | maquette |
| V2 | Modale de mise à jour : choix Valider en pied, une ligne de journal par enregistrement, texte « à valider » conditionné à l'état réel | maquette, 14 écrans |
| V3 | Vecteurs `validation.json` régénérés, domaine Dart, poste (helper `validation_poste`, 14 écrans), parité N1 | domaine, poste |
| V4 | Sonde du refus fileul (`CONFIGURATION_DE_LA_MERE`), cas de la fiche archivée | maquette, poste |
