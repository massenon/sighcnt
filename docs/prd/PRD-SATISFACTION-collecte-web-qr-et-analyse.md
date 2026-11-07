# PRD : Satisfaction des patients, collecte par lien web et code QR à l'accueil, enquêtes, analyse complète (maquette, relais, poste)

Statut : **proposé le 07/11/2026** à la demande de la Direction (module « complet, hors pair », avec toutes les options avancées et tous les filtres avancés). Les décisions de la section 10 sont à valider avant le premier code.
Note de méthode : le skill `sdlc-kit:prd` exige un coffre `.sdlc` initialisé (`/sdlc-kit:init`), absent de ce dépôt ; ce PRD suit donc la convention du dépôt (`docs/prd/`).
Sources : relevés dans le dépôt le 07/11/2026 (`m13-administration.js` ~1300 à 2300 : enquêtes, jetons, page publique ; `qual_enquetes.dart`, `qual_publique.dart`, `qual_qr.dart`, `qual_satisfaction.dart` ; vague 54 de `CLAUDE.md`) ; `docs/prd/PRD-RELAIS-copie-consultable.md` ; ADR-0005 et ADR-0006.
Règle de rédaction : pas de tiret cadratin comme ponctuation. Doctrine : maquette d'abord, puis vecteurs, domaine, poste ; **aucune donnée médicale** dans une enquête ; RG-12, RG-13, RG-14 ; hors ligne d'abord.

## 1. Problème

**Ce qui existe (relevé le 07/11/2026).**
- `adm-enquetes` : le questionnaire est une DONNÉE, le formulaire de saisie naît du modèle (trois types de question : note de 1 à 5, choix, texte) ; modèle de satisfaction amorcé (proposition validée par la Direction le 01/09) ; réponses horodatées avec leur canal.
- `adm-satisfaction` : lecture calculée (moyennes par question, recommandation, commentaires).
- Partage : un **lien à jeton** (24 caractères, daté, révocable) et son **code QR**, une page publique sans coquille (ni ruban, ni session), un **mode kiosque** sur tablette, un choix **anonyme** ou nominatif porté par le lien. Le poste Flutter porte les mêmes écrans (`qual_*`), parité N1 mesurée.
- **Limite écrite dans la maquette et au poste : la collecte reste LOCALE à la machine.** Un lien ouvert sur un téléphone affiche le formulaire, mais **la réponse ne revient jamais** au poste. Le geste est « maquetté ».

**Ce qui manque.**
1. **Le canal de retour** : une réponse saisie par un patient sur son téléphone n'atteint ni le poste ni la mère.
2. **L'affiche de l'accueil** : un QR imprimable (A4, chevalet de comptoir, ticket) et un parcours de réception qui le remet au patient.
3. **L'analyse complète** : peu de filtres, pas de période comparée, pas d'indicateur normalisé (NPS), pas d'alertes, pas de modération, pas d'export, pas de croisement.
4. **Les options de questionnaire** : trois types seulement, pas de logique conditionnelle, pas de versions, pas de langues, pas de fenêtre de validité.

## 2. Objectifs mesurables

- **O1.** Un patient scanne le QR (ou ouvre le lien), répond sur son téléphone, et **la réponse apparaît au poste** de l'accueil et de la Direction en moins de 60 secondes quand Internet est disponible. Critère : sonde de bout en bout contre le relais.
- **O2.** **Aucune perte et aucun doublon** : une réponse envoyée deux fois (réseau instable) n'est comptée qu'une fois ; une réponse faite hors ligne (tablette kiosque) est mise en file et partie au retour.
- **O3.** **Confidentialité** : le relais ne lit jamais les réponses (enveloppe scellée, voir section 6) ; aucun champ médical ; l'anonymat annoncé est tenu (ni nom, ni lien vers un dossier, ni empreinte permettant de remonter au patient).
- **O4.** **Analyse complète** : filtres avancés sur toutes les dimensions utiles (section 5) ; indicateurs normalisés (NPS, CSAT, taux de réponse) ; comparaison de périodes ; export ; alertes. Critère : chaque indicateur affiché est recalculable depuis les réponses, un recompte du magasin égale l'écran.
- **O5.** **Un seul générateur de formulaire** (saisie interne, page publique, kiosque) : une question ajoutée au modèle paraît partout, sondé au geste (leçon de la vague 54).
- **O6.** Zéro régression de l'anonymat, de la révocation et de l'expiration des liens (sondes existantes conservées).

## 3. Hors périmètre de la v1

- Réponses nominatives liées au dossier médical (la satisfaction ne lit jamais un diagnostic).
- Envoi des liens par SMS ou courriel au patient (dépend de la passerelle SMS : voir `PRD-SMS-passerelle-et-test-envoi.md`, P1 ici).
- Analyse de sentiment par apprentissage automatique (hors cahier des charges).
- Publication des résultats sur le site vitrine.

## 4. Utilisateurs

| Profil | Besoin |
|---|---|
| Patient ou accompagnant | répondre en moins d'une minute, sur son téléphone ou la tablette, sans compte |
| Réception | afficher le QR, lancer le mode kiosque, voir le nombre de réponses du jour |
| Direction, DAF, Directeur médical | lire, filtrer, comparer, exporter, être alertés d'une mauvaise note |
| Agent administratif | gérer les modèles et les liens |
| Administrateur | réglages, archivage, corbeille |

## 5. Exigences

**P0 (la v1 ne sort pas sans)**

*Collecte*
1. **Page publique hébergée par le relais** (seule surface joignable depuis Internet) : formulaire généré du modèle, sans coquille ni lien vers le logiciel, adaptée au téléphone, accessible (clavier, lecteur d'écran, contraste).
2. **QR et lien à jeton** : jeton aléatoire (24 caractères), daté, révocable ; **inconnu, expiré, révoqué : même réponse générique**. QR imprimable : affiche A4, chevalet de comptoir, vignette de ticket ; un QR **par point de collecte** (accueil, consultation, laboratoire, pharmacie, maternité, hospitalisation, sortie) pour mesurer par service.
3. **Enveloppe scellée** : la page chiffre la réponse avec la **clé publique de la clinique** (incluse dans la page) ; le relais ne stocke qu'un texte chiffré qu'il ne peut pas lire ; **seule la mère** (clé privée) ouvre l'enveloppe et l'ingère. Anti-rejeu par identifiant de réponse unique.
4. **Mode kiosque** : tablette à l'accueil, plein écran, remise à zéro après chaque réponse, **file locale chiffrée** si Internet manque, reprise au retour.
5. **Ingestion** : la mère ouvre les enveloppes, écrit les réponses dans la collection `reponsesEnquetes` (famille B, journal) ; les fileuls les reçoivent par le journal ; le canal est **« Lien public »**, « QR accueil », « Kiosque », « Guichet ».
6. **Anti-abus** : débit limité par adresse, champ piège, taille maximale, une réponse par jeton unique lorsque le lien est nominatif à usage unique ; aucune adresse IP conservée au-delà du contrôle.
7. **Consentement et information** : mention courte (finalité, anonymat, durée) avant la première question ; case obligatoire si la réponse est nominative.

*Questionnaires (options avancées)*
8. Types : note 1 à 5, **note 0 à 10 (NPS)**, oui ou non, choix unique, choix multiples, échelle de smileys, texte court, texte long, date ; question **obligatoire** ou facultative.
9. **Logique conditionnelle** (afficher une question selon une réponse), **sections**, ordre modifiable, **aperçu** avant publication.
10. **Versions datées** d'un modèle : modifier un modèle publié crée une version ; les réponses restent attachées à la version sous laquelle elles ont été données (même règle que la grille des primes et les plages par lot).
11. **Fenêtre de validité** (du / au), **plafond de réponses**, **langues** (français obligatoire ; autres langues administrables), **modèles par service**.
12. Modèle de satisfaction **reconduit** et deux modèles supplémentaires proposés (accueil, hospitalisation), tous marqués « proposition à valider » tant que la Direction ne les a pas arrêtés (aucun document de cadrage ne fixe de questionnaire).

*Analyse (filtres et options avancés)*
13. **Filtres avancés** : période (du / au, raccourcis, **comparaison à la période précédente de même nature**), service, point de collecte, canal, modèle et version, **note minimale et maximale**, **NPS (promoteurs, passifs, détracteurs)**, question, présence de commentaire, langue, anonyme ou nominatif, jour de la semaine et tranche horaire, **recherche texte** dans les commentaires ; filtres **enregistrables et nommés** par utilisateur.
14. **Indicateurs** : taux de réponse (réponses sur passages comptés à l'accueil), CSAT par question et global, **NPS**, répartition des notes, **évolution** (jour, semaine, mois, trimestre), **classement des services**, **top des motifs d'insatisfaction** (questions les plus basses), temps de remplissage.
15. **Croisements** (service par période, canal par note) et **exploration** : clic sur un chiffre ouvre les réponses qui le composent.
16. **Modération des commentaires** : masquer (jamais supprimer, RG-14), marquer « à traiter », « traité » avec auteur et date ; un commentaire contenant un mot de la liste médicale est signalé.
17. **Alertes** : une réponse sous un seuil (réglable), ou une moyenne de service sous un seuil sur une période, alerte la Direction par la cloche et, si activé, par SMS ou courriel (dépend de la passerelle).
18. **Exports et impressions** : tableau filtré en Excel (CSV) et PDF sur papier à en-tête officiel, **filtres en force relevés sur la pièce** (mécanisme de `print.js`), rapport mensuel de satisfaction imprimable et signable.
19. **Colonnes configurables, tri, pagination, sélection multiple** (standard du kit), corbeille RG-14.

**P1**
- Liens à usage unique envoyés au patient par SMS ou courriel après la sortie (dépend de la passerelle).
- Tableau de bord de la satisfaction par poste (accueil, direction).
- Suivi d'un commentaire négatif jusqu'à la réponse au patient (si nominatif et consenti).
- Réponses par le mobile Flutter des agents pour les patients sans téléphone (saisie assistée).

**P2**
- Autres langues locales administrables par la Direction ; lecture vocale ; analyse de thèmes.

## 6. Contraintes d'architecture

- **Relais seul joignable** : la page publique et le dépôt des enveloppes y vivent. **Opacité** : le relais ne reçoit que du texte chiffré avec une clé publique (boîte scellée) ; la clé privée n'existe que sur la mère. Un relais piraté ne lit aucune réponse. (Pas de réponse en clair chez l'hébergeur.)
- **Pas d'écriture directe en base par une page publique** : le dépôt est un POST d'enveloppe, validé en forme et en taille, rien de plus.
- **Hors ligne** : le kiosque garde une file chiffrée ; la mère éteinte, les enveloppes attendent au relais (conservation intégrale, `PRD-RELAIS-en-ligne-…`).
- **Famille de fusion** : modèles et liens = famille A (fiche, plus récent gagne) ; **réponses = famille B** (journal, append-only, jamais réécrites) ; configuration non secrète des canaux = R.
- **Données** : `enquetes` (versionnées), `jetonsEnquete`, `reponsesEnquetes`, nouvelles `pointsCollecte`, `alertesSatisfaction`, `vuesSatisfaction` (filtres enregistrés), `moderationsCommentaires` ; `VERSION` du prototype incrémentée (mesurer le quota avant d'ajouter des collections).
- **Poste** : parité N1 à 100 % des écrans modifiés ; la file de réponses se range comme la file de courriels (envoi puis reprise).

## 7. Droits (RBAC)

| Écran | admin | da | direction | dm | agentadmin | reception |
|---|---|---|---|---|---|---|
| `adm-enquetes` (modèles, liens, QR) | écrit | écrit | écrit | fermé | écrit | lit (affiche le QR, lance le kiosque) |
| `adm-satisfaction` (analyse) | écrit | écrit | écrit | lit | écrit | fermé |
| Modération | oui | oui | oui | fermé | oui | fermé |
| Alertes (réglage) | oui | oui | oui | fermé | fermé | fermé |

Une commande interdite est **absente**. La réception ne voit jamais les réponses individuelles ni les commentaires.

## 8. Sondes et critères d'acceptation

Scénarios « Vague 87 » (maquette, banc avec relais de test) et tests poste :
1. Réponse sur la page publique : enveloppe scellée au relais, **illisible au relais** (mesure d'entropie sur la base), ouverte par la mère, présente au poste en moins de 60 s.
2. Même réponse envoyée deux fois : une seule.
3. Kiosque hors ligne : file, puis reprise sans doublon.
4. Jeton inconnu, expiré, révoqué : réponses identiques, aucune enquête nommée.
5. Anonymat : aucune donnée permettant de remonter au patient dans la réponse ni au journal.
6. Logique conditionnelle, versions : une réponse reste liée à sa version ; une question ajoutée paraît sur la page publique (sondé au geste).
7. Filtres : le compte affiché égale le recompte du magasin pour chaque filtre et pour leurs combinaisons ; NPS recalculé à la main sur un jeu connu.
8. Alertes : seuil franchi, notification émise une seule fois par franchissement.
9. Modération : masquer ne supprime pas, annulable, journalisé RG-12.
10. Droits : réception et dm limités comme au tableau ; export filtré portant les filtres en force.
Mutations : au moins 6 (enveloppe en clair, doublon accepté, jeton révoqué accepté, filtre ignoré, réception lit les commentaires, alerte répétée).

## 9. Risques

- **Protection des données** : même anonyme, un commentaire libre peut contenir des données personnelles ; modération et mention d'information sont des exigences.
- **Abus et bruit** : un lien public attire des réponses malveillantes ; débit, champ piège, plafond et révocation sont les garde-fous.
- **Biais** : un QR à l'accueil sur-représente les patients satisfaits ou pressés ; l'écran affiche le taux de réponse.
- **Clé privée de la mère** : si elle est perdue, les enveloppes déposées sont illisibles (même procédure de remise que la clé de clinique).

## 10 bis. Décisions de la Direction du 07/11/2026 (reçues)

| # | Décision |
|---|---|
| S1 | Réponses anonymes par défaut ; nominatives seulement avec consentement coché. **Validé.** |
| S2 | Sept points de collecte (accueil, consultation, laboratoire, pharmacie, maternité, hospitalisation, sortie) **et**, en plus, l'**appréciation du personnel** : comportement des infirmiers, des médecins et des soignants, qualité du travail, du traitement, de l'écoute, du respect, de l'hygiène, des gestes, etc. Ces critères deviennent des **dimensions de questionnaire** par catégorie de personnel. Garde-fou proposé : l'appréciation porte sur une **catégorie** (infirmiers, médecins, soignants, sage-femmes), jamais sur un agent nommé, sauf décision écrite de la Direction (une note négative nominative est une mesure RH, elle relève de la NS 131). |
| S3 | Alertes : réponse de 2 sur 5 ou moins, ou moyenne de service sous 3,5 sur 7 jours. **Validé.** |
| S4 | **Français par défaut, uniquement.** Un **champ de sélection de langue** est ajouté (page publique, kiosque, administration) : la Direction active d'autres langues et saisit les traductions du questionnaire ; sans traduction d'une question, la page retombe sur le français. |
| S5 | La Direction répond hors outil **et peut laisser des commentaires internes et des « dispositions à prendre »** sur une réponse (champ de suivi : texte, auteur, date, état à faire ou fait), jamais visibles du patient. |
| S6 | Conserver et archiver (RG-14) ; durée active de 3 ans, puis archivage, jamais de suppression. |
| S7 | Mode kiosque dès la v1, file locale chiffrée. **Validé.** |
| S8 | Modèles acceptés « à valider », **avec un bouton Valider** qui enregistre la validation (`valideLe`, `validePar`, journal RG-12), fait changer le statut de « à valider » à « validé » et retire le marquage. **Règle étendue à tous les modules** : tout ce qui est marqué « à valider » doit porter son geste de validation (audit en cours : `docs/architecture/AUDIT-marquages-a-valider.md`). |

## 10. Décisions à valider (Direction), état initial (voir 10 bis)

| # | Question | Proposition |
|---|---|---|
| Q1 | Les réponses restent-elles **anonymes par défaut** ? Une réponse nominative est-elle admise ? | anonyme par défaut ; nominatif seulement avec consentement coché |
| Q2 | Quels points de collecte ? | accueil, consultation, laboratoire, pharmacie, maternité, hospitalisation, sortie |
| Q3 | Seuils d'alerte par défaut | note de 2 sur 5 ou moins sur une réponse ; moyenne de service sous 3,5 sur 7 jours |
| Q4 | Langues de la v1 | français seul, autres en P2 |
| Q5 | Qui répond aux commentaires négatifs ? | la Direction, hors outil en v1 |
| Q6 | Conservation des réponses | 3 ans puis archivage (RG-14) |
| Q7 | Le mode kiosque est-il prévu à l'accueil dès la v1 (achat de tablette) ? | oui, la file locale chiffrée est de toute façon requise |
| Q8 | Les modèles proposés (accueil, hospitalisation) sont-ils acceptés ? | oui, marqués « à valider » jusqu'à signature de la Direction |
