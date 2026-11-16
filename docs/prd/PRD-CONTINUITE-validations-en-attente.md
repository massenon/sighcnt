# PRD : continuité de service des validations (lot CONT, 16/11/2026)

## Exigence (Direction, 14/11/2026 ; validée le 15/11/2026, `DECISIONS-A-VALIDER.md` section AH, point 36)

1. Une validation à faire n'empêche JAMAIS le fileul de travailler : ni verrou, ni écran bloquant, ni saisie suspendue.
2. Le poste de la mère n'est pas fait pour valider : la décision humaine se prend sur n'importe quel poste par le rôle autorisé ; la mère applique mécaniquement ; mère coupée, tout s'empile et se rejoue.

## Exigences fonctionnelles

| Code | Exigence | Où | Preuve |
|---|---|---|---|
| CONT-01 | Sur un fileul, le profil d'une famille du registre des validations voit « Valider » (il était absent) ; son geste SIGNE la décision (nom, rôle, date et heure, motif éventuel) et la dépose dans `demandesValidation` | `ValidationPoste.decider`, `valDeposerValidation` | `continuite_validation_ecrans_test.dart`, `demande_validation_test.dart` |
| CONT-02 | Rien n'est validé chez le fileul avant la mère ; le badge dit « Décision déposée, en attente de la mère » ; la commande devient ABSENTE pour cet élément seulement ; une seconde décision est refusée `DEMANDE_DEJA_DEPOSEE`, nommée, avec « le travail courant n'est pas bloqué » | idem | idem |
| CONT-03 | La mère applique sans personne à son poste : mêmes contrôles sous le rôle et le nom de l'auteur, date de la validation = date de la SIGNATURE, verdict nommé sur la même fiche ; un rejeu ne double jamais | `valAppliquerDemande`, `ServiceDemandesValidation` | `continuite_validation_sync_test.dart` (vraie mère) |
| CONT-04 | Mère coupée : décider reste possible ; les décisions s'empilent au journal local et se rejouent à la reconnexion, une fois, dans l'ordre | moteur fileul, pont | idem, test « MÈRE COUPÉE » et « MESURE » |
| CONT-05 | Une pastille dit « N décisions en attente de la mère » et l'âge de la plus ancienne (validations, prix, imports) ; absente à zéro, jamais zéro quand il y en a | `PastilleDecisions`, `valSyntheseToutesAttentes` | tests du domaine et de l'écran |
| CONT-06 | Au delà d'un délai RÉGLÉ EN BASE (`securite.delaiAlerteDecisionEnAttenteHeures`, défaut semé 24 h, à valider), une alerte au profil de la famille et à l'administrateur ; jamais un blocage, jamais une validation d'office ; calculée sur chaque poste, pas par la mère | `CentreNotifications`, source `decisions_en_attente` | `continuite_validation_ecrans_test.dart` |
| CONT-07 | Rien de tout cela ne part vers un téléphone (RG-13) | `collectionsValidationJamaisMobile` (mère Dart) | test « BOUT EN BOUT » (lecture réelle d'un mobile) |
| CONT-08 | La maquette ne perd plus un geste posé juste après un gros envoi (envois sérialisés) | `store.js`, `pousserServeur` | scénario 184 |

## Hors périmètre de ce lot

Modifier la configuration depuis un fileul (reste réglé sur la mère, refus nommé) ; synchroniser les commandes de stock (RG-04) ; promouvoir un fileul en mère (refusé par la Direction, point 37) ; les seuils de variation au poste (lot B non porté).

## Plan (fait)

0. Maquette : sérialiser les envois du magasin, scénario 184 rouge puis vert.
1. Inventaire mesuré : `docs/architecture/CONTINUITE-validations-en-attente.md`.
2. Domaine : `demande_validation.dart` et son test (refus nommés, application, idempotence, compte, alerte), paramètre déclaré.
3. Synchronisation : `demandesValidation` famille A (mère Dart, banc `mere.js`, pont du poste), exclusion du mobile.
4. Poste : dépôt au bouton et à la modale, service de la mère, pastille, alerte, tests contre la vraie mère, mesure du hors ligne prolongé.
5. Mutations (12), passage final, documents.

## Écart à la maquette

La maquette n'a pas de mère : son mode fileul est un drapeau (`posteFileul`) qui refuse la validation comme le faisait le poste. Le dépôt signé et son application ne sont donc pas tirés de l'écran réel de la maquette : ils sont portés au domaine avec des tests propres (E2663).
