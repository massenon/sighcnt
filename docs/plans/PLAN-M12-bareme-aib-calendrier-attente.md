# PLAN : barème AIB daté, vérification du calendrier fiscal, valeurs d'attente du personnel

Statut : **proposé le 09/11/2026**. PRD : `docs/prd/PRD-M12-bareme-AIB-calendrier-fiscal-et-valeurs-d-attente-du-personnel.md`. **Aucun lot ne démarre avant les réponses Q1 et Q2** (texte du 5 % ; CNSS au 10 ou au 15) : le moteur du barème A1 peut commencer avec des taux « non arrêtés » sans attendre, mais le calendrier (A3) ne se modifie pas.
Méthode : maquette d'abord, vecteurs, domaine Dart, poste ; un agent Sonnet par lot, brief court, relecture du responsable pour les **droits** et l'**argent** ; bancs isolés (`SIGH_PORT_PHP`, `SIGH_BASE_TEST`, `SIGH_PORT_TEST`, piège E2263) ; une seule suite complète et un seul audit RBAC en fin de série ; fiches d'écran extraites sous l'horloge du 30/10/2026 (E2284).

## Agents

| Agent | Rôle | Fichiers | Ne touche pas |
|---|---|---|---|
| maquette-AIB (A1, A2) | collection `baremeAib`, moteur `PR.tauxAibALaDate`, écran `m12-bareme-aib`, droits, liste « à brancher » | `parcours.js`, `store.js`, `nav.js`, un module M12, `build/test-fonctionnel.js` | apps/poste, packages/domaine |
| audit-calendrier (A3) | rapport de vérification écran par écran, aucune modification de règle | lecture seule ; écrit `docs/architecture/AUDIT-calendrier-fiscal.md` | tout le code |
| maquette-RH (A4) | marquage de valeur d'attente par champ, journal | `m10-rh.js`, `store.js` | M11 paie sauf « Non calculable » |
| portage (A5) | vecteurs, domaine Dart, poste (un seul processus flutter à la fois) | `build/vecteurs-*.js`, `packages/domaine`, `apps/poste` | la maquette |
| **suivi (S)** | lit le plan, `git log`, ECARTS, résultats des bancs ; rend l'état de chaque lot, les blocages, les questions sans réponse ; **n'écrit aucun code** | lecture seule | tout |

L'agent de suivi est défini dans `.claude/agents/suivi-lots.md` ; il s'appelle après chaque retour d'agent et avant toute suite complète.

## Ordre

1. A1 (peut démarrer) puis A2, un agent à la fois (ils se partagent `store.js` et `test-fonctionnel.js`).
2. A3 en parallèle de A1 (lecture seule, aucun conflit).
3. A4 après A2 (même `store.js`).
4. Suite complète maquette + audit RBAC une fois A1 à A4 faits.
5. A5 après la suite verte.
6. Suivi S à chaque jalon.

## Lots

### A1 : moteur et collection
`baremeAib` (une fiche par version, jamais d'écrasement : une correction crée une version et ferme la précédente), `PR.tauxAibALaDate(date)` (refus nommé `AIB_SANS_BAREME`), valeurs proposées (5 % arrêté à compter du 07/09/2026 ; 1 % et 3 % non arrêtés), `VERSION`, `LIBELLES`, schéma régénéré. Preuves : scénario dédié, au moins 6 mutations (écrasement, date de bascule, version non fermée, marquage retiré, sans-barème rendu zéro, version archivée comptée).

### A2 : écran et droits
`m12-bareme-aib` par `K.crud` ; fiches RBAC : comptable écrit, Direction lit ; commande absente sinon ; corbeille ; liste de ce qu'il faudrait y brancher, en lecture. Preuves : audit RBAC ciblé comptable, direction, da, caissier ; sonde du texte « non arrêté ».

### A3 : calendrier fiscal (lecture seule)
Pour chaque obligation de `D.CALENDRIER_FISCAL` : jour de dépôt, jour montré par `cfg-comptabilite` et par `m12-echeances`, semis à l'ouverture (piège de l'amorçage), suivi peuplé, présence d'une vue mensuelle. Sortie : tableau d'écarts, pas de correction. La CNSS se compare au 10 confirmé le 25/08 ; l'écart avec le 15 du texte remis est **signalé, jamais tranché**.

### A4 : valeurs d'attente
Marquage par champ (salaire, date d'embauche, CNSS, tarif de vacation), modification d'un champ retire son marquage seulement, journal avant/après ; un agent sans salaire validé : « Non calculable » à la paie.

### A5 : portage
Vecteurs depuis la maquette, domaine (moteur daté), poste (écran, droits, familles de synchronisation R), parité N1.

## Vérifications globales
`node --check`, `php -l`, `npm run build` si le manifeste change, scénario(s) dédié(s), suite complète, audit RBAC, `dart test`, `flutter test`, parité N1.

## Risques
- Brancher l'AIB sur les achats fausserait la comptabilité sans décision : le moteur liste, ne branche pas.
- Taux et date sans texte réglementaire : tout est « non arrêté » tant que Q1 n'a pas de réponse écrite.
- Changer le jour de la CNSS contredirait un arbitrage du 25/08 : A3 signale seulement.
- Conflit sur `store.js` et `test-fonctionnel.js` entre agents : un seul agent d'écriture à la fois dans la maquette.
